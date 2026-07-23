# facet_workflow.jl -- v0.1 long-format data, validation, and minimal spec layer

using LinearAlgebra

"""
    FacetData(table; person, rater, item, score, group = nothing, task = nothing,
              form = nothing, occasion = nothing, response_id = nothing,
              testlet_id = nothing, missing_policy = :error)

Encode long-format rating data into deterministic integer indexes for the
required person, rater, item, and ordinal score columns. Optional columns are
stored as indexed metadata and are not model terms in the v0.1 design scaffold.
Use `response_id` for a globally unique scored response and `testlet_id` for
its declared task or item-cluster identity. `occasion` remains categorical
metadata; its encoded index must not be interpreted as elapsed time or row
sequence.
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
requested DFF cell counts, and data signatures used to prevent stale report
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

Machine-readable many-facet measurement specification produced by `mfrm_spec`.
The current fitting compiler supports the minimal one-dimensional MFRM/RSM/PCM
slice. The same object can also hold planned GMFRM/MGMFRM configuration intent
so reviewers and downstream reports can inspect family, dimensionality,
discrimination, Q-mask, validation-bias terms, anchors, constraints, and prior
contracts before those terms are exposed for fitting.
"""
struct FacetSpec
    data::FacetData
    thresholds::Symbol
    validation::ValidationReport
    family::Symbol
    dimensions::Int
    dimension_labels::Vector{String}
    discrimination::Symbol
    q_matrix::Union{Nothing,Matrix{Bool}}
    validation_bias_terms::Vector{Tuple{Symbol,Symbol}}
    anchors::Vector{NamedTuple}
    constraints::Vector{NamedTuple}
    prior_blocks::Vector{NamedTuple}
    estimation_status::Symbol
end

FacetSpec(data::FacetData, thresholds::Symbol, validation::ValidationReport) =
    FacetSpec(
        data,
        thresholds,
        validation,
        :mfrm,
        1,
        _default_dimension_labels(1),
        :none,
        nothing,
        Tuple{Symbol,Symbol}[],
        NamedTuple[],
        _constraint_rows(;
            family = :mfrm,
            thresholds,
            dimensions = 1,
            discrimination = :none,
            q_matrix = nothing,
            validation_bias_terms = Tuple{Symbol,Symbol}[],
            anchors = NamedTuple[],
            estimation_status = :fit_supported,
        ),
        _prior_rows(:mfrm, 1, :none),
        :fit_supported,
    )

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

_facet_spec(::FacetData) = nothing
_facet_spec(spec::FacetSpec) = spec
_facet_spec(design::FacetDesign) = design.spec

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
        response_id::Union{Nothing,Symbol} = nothing,
        testlet_id::Union{Nothing,Symbol} = nothing,
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
    for (role, column) in (
            (:group, group),
            (:task, task),
            (:form, form),
            (:occasion, occasion),
            (:response_id, response_id),
            (:testlet_id, testlet_id),
        )
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

function _check_observation_indices(data::FacetData, observations, context::AbstractString)
    observations === nothing && return collect(1:data.n)

    collected = collect(observations)
    out = Int[]
    for observation in collected
        observation isa Integer && !(observation isa Bool) ||
            throw(ArgumentError("$context observations must be integer row indices"))
        index = Int(observation)
        1 <= index <= data.n ||
            throw(ArgumentError(
                "$context observation index $index is outside 1:$(data.n)"))
        push!(out, index)
    end
    length(unique(out)) == length(out) ||
        throw(ArgumentError("$context observations must be unique"))
    return out
end

"""
    facet_response_table(data::FacetData; observations = nothing)
    facet_response_table(spec::FacetSpec; kwargs...)
    facet_response_table(design::FacetDesign; kwargs...)

Return a role-normalized long-format response table from encoded `FacetData`.
The table is a named tuple with `person`, `rater`, `item`, and `score` vectors,
plus optional facet vectors such as `group`, `task`, `form`, `occasion`,
`response_id`, or `testlet_id` when present. Pass `observations` to materialize
a selected row order, for example a training or heldout row set from
[`kfold_plan`](@ref).

The returned table uses role names rather than the original input column names,
so it can be passed back to `FacetData(table; person = :person, rater = :rater,
item = :item, score = :score, ...)` when a role-normalized split is desired.
"""
function facet_response_table(data::FacetData; observations = nothing)
    rows = _check_observation_indices(data, observations, "facet_response_table")
    names = Symbol[:person, :rater, :item, :score]
    values = Any[
        [data.person_levels[data.person[row]] for row in rows],
        [data.rater_levels[data.rater[row]] for row in rows],
        [data.item_levels[data.item[row]] for row in rows],
        [data.score[row] for row in rows],
    ]
    for facet in sort(collect(keys(data.optional)); by = string)
        push!(names, facet)
        push!(values, [data.optional_levels[facet][data.optional[facet][row]]
            for row in rows])
    end
    return NamedTuple{Tuple(names)}(Tuple(values))
end

facet_response_table(spec::FacetSpec; kwargs...) =
    facet_response_table(spec.data; kwargs...)
facet_response_table(design::FacetDesign; kwargs...) =
    facet_response_table(design.spec.data; kwargs...)

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

function _suggestion_for_issue(issue::ValidationIssue)
    code = issue.code
    code === :empty_data && return (
        action = :provide_ratings,
        suggestion = "Provide at least one complete long-format rating row before constructing a model specification.",
    )
    code === :single_observed_category && return (
        action = :collect_or_recode_categories,
        suggestion = "Use at least two observed score categories, or recode/collapse the outcome before fitting an ordered-response model.",
    )
    code === :unused_interior_category && return (
        action = :inspect_scale_use,
        suggestion = "Inspect skipped interior categories; consider collapsing sparse categories or documenting that the unused category is structurally possible.",
    )
    code === :single_item_category && return (
        action = :simplify_thresholds_or_collect_data,
        suggestion = "Items using only one category weakly inform partial-credit thresholds; collect more ratings, collapse categories, or prefer a simpler threshold structure.",
    )
    code === :unobserved_item_category && return (
        action = :check_threshold_support,
        suggestion = "Unobserved item/category cells can make partial-credit thresholds weakly informed; inspect category coverage before fitting item-specific steps.",
    )
    code === :singleton_facet_level && return (
        action = :collect_more_linking_data,
        suggestion = "Facet levels with one rating are weakly linked; collect more ratings, merge levels, or keep the level out of modelled effects.",
    )
    code === :disconnected_design && return (
        action = :add_links_or_split_design,
        suggestion = "Add common raters/items/persons or anchors to connect the graph; otherwise analyze connected components separately.",
    )
    code === :rank_deficient_design && return (
        action = :simplify_or_relink_design,
        suggestion = "The current reference-constrained location design is rank deficient; add linking observations or remove aliased facet effects.",
    )
    code === :invalid_bias_term && return (
        action = :fix_bias_syntax,
        suggestion = "Use two-facet tuples such as (:rater, :group) for bias/DFF validation terms.",
    )
    code === :unknown_bias_facet && return (
        action = :check_facet_roles,
        suggestion = "Bias/DFF terms must reference required facets or optional roles supplied to FacetData.",
    )
    code === :empty_dff_cell && return (
        action = :pool_or_remove_dff_term,
        suggestion = "Empty DFF cells cannot support unpooled interaction estimates; collect data, collapse levels, use hierarchical pooling, or remove the term.",
    )
    code === :sparse_dff_cell && return (
        action = :pool_or_collect_dff_data,
        suggestion = "Sparse DFF cells require caution; collect more data, collapse levels, or use hierarchical shrinkage with sensitivity checks.",
    )
    code === :potential_dff_confounding && return (
        action = :inspect_dff_confounding,
        suggestion = "A facet level is observed with only one level of the paired DFF facet; improve crossing or avoid interpreting the DFF contrast.",
    )
    return (
        action = :inspect_issue,
        suggestion = "Inspect this validation issue before fitting a more complex model.",
    )
end

"""
    validation_suggestions(report::ValidationReport)
    validation_suggestions(issue::ValidationIssue)

Return machine-readable next-step suggestions for validation issues. Suggestions
are intentionally conservative and are meant to guide design repair or model
simplification before fitting more complex MFRM/GMFRM/MGMFRM specifications.
"""
function validation_suggestions(issue::ValidationIssue)
    suggestion = _suggestion_for_issue(issue)
    return (;
        code = issue.code,
        severity = issue.severity,
        action = suggestion.action,
        message = issue.message,
        suggestion = suggestion.suggestion,
        context = copy(issue.context),
    )
end

function validation_suggestions(report::ValidationReport)
    return [validation_suggestions(issue) for issue in report.issues]
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
`:task`, `:form`, `:occasion`, `:response_id`, or `:testlet_id`.
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
    if unit === :response_id
        haskey(data.optional, :response_id) ||
            throw(ArgumentError("unit = :response_id requires FacetData(...; response_id = ...)"))
        return (data.optional[:response_id][row],)
    end
    if unit === :testlet_id
        haskey(data.optional, :testlet_id) ||
            throw(ArgumentError("unit = :testlet_id requires FacetData(...; testlet_id = ...)"))
        return (data.optional[:testlet_id][row],)
    end
    if unit === :person_testlet
        haskey(data.optional, :testlet_id) ||
            throw(ArgumentError("unit = :person_testlet requires FacetData(...; testlet_id = ...)"))
        return (data.person[row], data.optional[:testlet_id][row])
    end
    if unit === :response_item
        haskey(data.optional, :response_id) ||
            throw(ArgumentError("unit = :response_item requires FacetData(...; response_id = ...)"))
        return (data.optional[:response_id][row], data.item[row])
    end
    throw(ArgumentError(
        "unit must be one of :person, :item, :person_item, :task, " *
        ":person_task, :response_id, :testlet_id, :person_testlet, or :response_item"))
end

function _rater_overlap_unit_metadata(unit::Symbol)
    if unit in (:testlet_id, :person_testlet)
        return (;
            overlap_purpose = :descriptive_coverage,
            rater_linking_eligible = false,
            interpretation =
                :shared_testlet_coverage_does_not_establish_common_response_linking,
        )
    elseif unit in (:response_id, :response_item)
        return (;
            overlap_purpose = :common_response_linking,
            rater_linking_eligible = true,
            interpretation = :shared_response_overlap_can_support_rater_linking,
        )
    end
    return (;)
end

function _require_rater_linking_unit(unit::Symbol, caller::Symbol)
    unit in (:testlet_id, :person_testlet) || return nothing
    throw(ArgumentError(
        "$(String(caller)) cannot use unit = :$unit for rater-link " *
        "connectivity because it is descriptive cluster coverage only; " *
        "use rater_overlap(...; unit = :$unit) for coverage counts, or " *
        "use unit = :response_id or :response_item for common-response linking"))
end

"""
    rater_overlap(data_or_spec; unit = :person_item)

Return pairwise rater-overlap data for coverage and linking plots. `unit`
controls what counts as a shared rated unit and may be `:person`, `:item`,
`:person_item`, `:task`, `:person_task`, `:response_id`, `:testlet_id`,
`:person_testlet`, or `:response_item`. Metadata-based units require the
corresponding optional role in `FacetData`. Rows for `:testlet_id` and
`:person_testlet` are explicitly marked as descriptive coverage and are not
eligible for rater-link connectivity. Rows for `:response_id` and
`:response_item` are marked as common-response linking units.
"""
function rater_overlap(data_or_spec; unit::Symbol = :person_item)
    data = _facet_data(data_or_spec)
    unit_metadata = _rater_overlap_unit_metadata(unit)
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
            unit_metadata...,
        ))
    end
    return rows
end

function _anchor_target(anchor)
    target = _anchor_symbol(anchor, (:level, :facet_level, :target, :parameter))
    return target === nothing ? missing : target
end

function _anchor_block_levels(data::FacetData, block::Symbol)
    block in (:person, :person_location, :persons) && return data.person_levels
    block in (:rater, :rater_severity, :raters) && return data.rater_levels
    block in (:item, :item_difficulty, :items) && return data.item_levels
    block in (:thresholds, :threshold_steps, :steps) && return data.category_levels
    return Any[]
end

function _anchor_linking_anchor_rows(spec, data::FacetData)
    spec === nothing && return NamedTuple[]
    rows = NamedTuple[]
    for (index, anchor) in pairs(spec.anchors)
        target = _anchor_target(anchor)
        levels = _anchor_block_levels(data, anchor.block)
        target_found = ismissing(target) ? missing :
            any(level -> isequal(level, target), levels)
        passed = ismissing(target_found) || target_found
        push!(rows, (;
            anchor_index = index,
            block = anchor.block,
            target,
            target_found,
            anchor_type = anchor.anchor_type,
            anchor_value = anchor.value,
            anchor_scale = anchor.anchor_scale,
            implementation_status = :specified_only,
            passed,
            status = passed ? :declared : :anchor_target_not_in_data,
        ))
    end
    return rows
end

function _anchor_link_root!(parent::Vector{Int}, index::Int)
    while parent[index] != index
        parent[index] = parent[parent[index]]
        index = parent[index]
    end
    return index
end

function _anchor_link_union!(parent::Vector{Int}, a::Int, b::Int)
    root_a = _anchor_link_root!(parent, a)
    root_b = _anchor_link_root!(parent, b)
    root_a == root_b && return nothing
    parent[root_b] = root_a
    return nothing
end

function _rater_level_index(levels, level)
    index = findfirst(candidate -> isequal(candidate, level), levels)
    index === nothing &&
        throw(ArgumentError("rater overlap row references an unknown rater level"))
    return index
end

function _rater_link_components(data::FacetData, overlap_rows, min_shared_units::Int)
    n_raters = length(data.rater_levels)
    parent = collect(1:n_raters)
    for row in overlap_rows
        row.shared_units >= min_shared_units || continue
        a = _rater_level_index(data.rater_levels, row.rater_a)
        b = _rater_level_index(data.rater_levels, row.rater_b)
        _anchor_link_union!(parent, a, b)
    end

    grouped = Dict{Int,Vector{Any}}()
    for index in 1:n_raters
        root = _anchor_link_root!(parent, index)
        push!(get!(grouped, root, Any[]), data.rater_levels[index])
    end
    components = collect(values(grouped))
    for component in components
        sort!(component; by = string)
    end
    sort!(components; by = component -> isempty(component) ? "" : string(first(component)))
    return Tuple(Tuple(component) for component in components)
end

function _anchor_sensitivity_status(sensitivity_rows)
    sensitivity_rows === nothing && return (;
        status = :not_supplied,
        passed = missing,
        n_rows = 0,
        missing_required_axes = (:anchor,),
        summary = nothing,
    )
    summary = sensitivity_comparison_summary(sensitivity_rows; required_axes = (:anchor,))
    return (;
        status = summary.passed ? :complete : :incomplete,
        passed = summary.passed,
        n_rows = summary.n_rows,
        missing_required_axes = summary.missing_required_axes,
        summary,
    )
end

"""
    anchor_linking_summary(data_or_spec; unit = :person_item,
        min_shared_units = 1, sensitivity_rows = nothing)

Return a compact anchoring and rater-linking diagnostic summary. The summary
combines declared hard/soft anchor rows from a `FacetSpec` or `FacetDesign`,
pairwise rater-overlap connectivity for the chosen linking `unit`, and an
optional anchor-axis sensitivity coverage check from
[`sensitivity_comparison_summary`](@ref).

This is a report and design-review helper. It does not fit hard anchors, turn
soft anchors into priors, estimate linking constants, or create sensitivity
refits. Use it to document whether declared anchors are internally consistent
and whether raters are connected strongly enough for a planned analysis.
`unit = :testlet_id` and `:person_testlet` are descriptive coverage units and
are rejected here; use `rater_overlap` to inspect them without a linking claim.
"""
function anchor_linking_summary(data_or_spec; unit::Symbol = :person_item,
        min_shared_units::Int = 1,
        sensitivity_rows = nothing)
    min_shared_units >= 1 ||
        throw(ArgumentError("min_shared_units must be positive"))
    _require_rater_linking_unit(unit, :anchor_linking_summary)
    data = _facet_data(data_or_spec)
    spec = _facet_spec(data_or_spec)
    validation = _validation_report(data_or_spec)
    overlap_rows = rater_overlap(data; unit)
    components = _rater_link_components(data, overlap_rows, min_shared_units)
    n_raters = length(data.rater_levels)
    n_components = length(components)
    n_links = count(row -> row.shared_units >= min_shared_units, overlap_rows)
    n_weak_links = count(row -> 0 < row.shared_units < min_shared_units, overlap_rows)
    n_zero_overlap_pairs = count(row -> row.shared_units == 0, overlap_rows)
    rater_linking_status = n_raters <= 1 ? :single_rater :
        n_components == 1 ? :connected : :disconnected

    anchor_rows = _anchor_linking_anchor_rows(spec, data)
    n_hard_anchors = count(row -> row.anchor_type === :hard_anchor, anchor_rows)
    n_soft_anchors = count(row -> row.anchor_type === :soft_anchor, anchor_rows)
    n_anchor_target_failures = count(row -> !row.passed, anchor_rows)
    anchor_status = isempty(anchor_rows) ? :not_declared :
        n_anchor_target_failures == 0 ? :declared : :invalid_targets
    sensitivity = _anchor_sensitivity_status(sensitivity_rows)
    linking_passed = rater_linking_status !== :disconnected
    sensitivity_passed = sensitivity_rows === nothing || sensitivity.passed === true

    return (;
        schema = "bayesianmgmfrm.anchor_linking_summary.v1",
        object = :anchor_linking_summary,
        family = spec === nothing ? missing : spec.family,
        thresholds = spec === nothing ? missing : spec.thresholds,
        estimation_status = spec === nothing ? missing : spec.estimation_status,
        data_signature = validation === nothing ? _data_signature(data) :
            validation.data_signature,
        unit,
        min_shared_units,
        n_raters,
        rater_linking_status,
        n_rater_components = n_components,
        rater_components = components,
        largest_rater_component = isempty(components) ? 0 : maximum(length, components),
        n_overlap_pairs = length(overlap_rows),
        n_links_at_or_above_min = n_links,
        n_weak_links,
        n_zero_overlap_pairs,
        minimum_shared_units = isempty(overlap_rows) ? missing :
            minimum(row.shared_units for row in overlap_rows),
        overlap_rows = Tuple(overlap_rows),
        anchor_status,
        n_anchors = length(anchor_rows),
        n_hard_anchors,
        n_soft_anchors,
        n_anchor_target_failures,
        anchor_rows = Tuple(anchor_rows),
        anchor_sensitivity_status = sensitivity.status,
        anchor_sensitivity_passed = sensitivity.passed,
        anchor_sensitivity_n_rows = sensitivity.n_rows,
        anchor_sensitivity_missing_required_axes = sensitivity.missing_required_axes,
        anchor_sensitivity_summary = sensitivity.summary,
        passed = linking_passed && n_anchor_target_failures == 0 && sensitivity_passed,
        caveat = :diagnostic_summary_not_anchor_refit_or_linking_estimator,
        next_gate = :predeclared_anchor_sensitivity_case_study,
    )
end

function _rating_design_audit_row(; audit::Symbol,
        status::Symbol,
        severity::Symbol = :info,
        facets = Symbol[],
        unit = missing,
        n_expected = missing,
        n_observed = missing,
        n_missing = missing,
        n_sparse = missing,
        n_repeated = missing,
        n_components = missing,
        min_count = missing,
        max_count = missing,
        note::Symbol = :none,
        details = (;))
    return (;
        schema = "bayesianmgmfrm.rating_design_audit_row.v1",
        audit,
        status,
        severity,
        facets = Tuple(facets),
        unit,
        n_expected,
        n_observed,
        n_missing,
        n_sparse,
        n_repeated,
        n_components,
        min_count,
        max_count,
        note,
        details,
    )
end

function _rating_design_facet_value(data::FacetData, facet::Symbol, row::Int)
    indexed = _facet(data, facet)
    indexed === nothing &&
        throw(ArgumentError("facet :$facet is not present in FacetData"))
    index, levels = indexed
    return levels[index[row]]
end

function _rating_design_pair_examples(pairs; limit::Int = 10)
    n = min(length(pairs), limit)
    return Tuple((; cell = first(pairs[index]), count = last(pairs[index]))
        for index in 1:n)
end

function _rating_design_cell_count_summary(data::FacetData, facets,
        min_sparse_cell_count::Int)
    isempty(facets) &&
        throw(ArgumentError("at least one facet is required"))
    level_counts = Int[]
    for facet in facets
        indexed = _facet(data, facet)
        indexed === nothing &&
            throw(ArgumentError("facet :$facet is not present in FacetData"))
        push!(level_counts, length(indexed[2]))
    end

    counts = Dict{Tuple,Int}()
    for row in 1:data.n
        key = Tuple(_rating_design_facet_value(data, facet, row) for facet in facets)
        counts[key] = get(counts, key, 0) + 1
    end
    pairs = sort(collect(counts); by = pair -> string(first(pair)))
    observed_counts = [last(pair) for pair in pairs]
    sparse_pairs = [pair for pair in pairs if last(pair) < min_sparse_cell_count]
    repeated_pairs = [pair for pair in pairs if last(pair) > 1]
    n_expected = prod(level_counts)
    n_observed = length(pairs)
    return (;
        facets = Tuple(facets),
        n_expected,
        n_observed,
        n_missing = max(n_expected - n_observed, 0),
        n_sparse = length(sparse_pairs),
        n_repeated = length(repeated_pairs),
        min_count = isempty(observed_counts) ? missing : minimum(observed_counts),
        max_count = isempty(observed_counts) ? missing : maximum(observed_counts),
        sparse_examples = _rating_design_pair_examples(sparse_pairs),
        repeated_examples = _rating_design_pair_examples(repeated_pairs),
        missingness_class = :unobserved_grid_cells,
        distinguishability =
            :structural_vs_accidental_not_distinguishable_from_observed_long_data,
    )
end

function _rating_design_components(data::FacetData, validation)
    raw_components = validation === nothing ?
        [[_label_node(data, node) for node in component]
         for component in _connected_components(data)] :
        validation.components
    components = [
        Tuple((; facet = facet, level) for (facet, level) in component)
        for component in raw_components
    ]
    return Tuple(components)
end

function _rating_design_optional_summary(data::FacetData)
    optional_facets = sort(collect(keys(data.optional)); by = string)
    time_order_facets = [facet for facet in optional_facets if facet === :occasion]
    descriptive_assignment_facets = [
        facet for facet in optional_facets
        if facet in (:group, :task, :form, :occasion)
    ]
    return (;
        optional_facets = Tuple(optional_facets),
        time_order_facets = Tuple(time_order_facets),
        descriptive_assignment_facets = Tuple(descriptive_assignment_facets),
        occasion_recorded = haskey(data.optional, :occasion),
    )
end

"""
    rating_design_audit(data_or_spec_or_design; unit = :person_item,
        min_shared_units = 1, min_sparse_cell_count = 2)

Return a report-ready audit of the observed rating design before fitting. Rows
summarize person-rater-item graph components, rater overlap strength, anchor
coverage, complete-grid coverage for required facet combinations, repeated
ratings, sparse observed person-rater-item blocks, optional time/order fields,
and the interpretation limitation caused by unmodeled rater assignment.

The current `FacetData` contract stores complete observed long-format rows but
does not store an external planned-design table. Consequently the audit counts
unobserved complete-grid cells and explicitly marks structural versus
accidental missingness as not identified from the observed data alone.
`unit = :testlet_id` and `:person_testlet` are descriptive coverage units and
cannot be used for the audit's rater-link connectivity decision.
"""
function rating_design_audit(data_or_spec_or_design;
        unit::Symbol = :person_item,
        min_shared_units::Int = 1,
        min_sparse_cell_count::Int = 2)
    min_shared_units >= 1 ||
        throw(ArgumentError("min_shared_units must be positive"))
    min_sparse_cell_count >= 1 ||
        throw(ArgumentError("min_sparse_cell_count must be positive"))
    _require_rater_linking_unit(unit, :rating_design_audit)

    data = _facet_data(data_or_spec_or_design)
    spec = _facet_spec(data_or_spec_or_design)
    validation = _validation_report(data_or_spec_or_design)
    anchor_summary = anchor_linking_summary(
        data_or_spec_or_design;
        unit,
        min_shared_units)
    overlap_rows = anchor_summary.overlap_rows
    components = _rating_design_components(data, validation)
    n_graph_components = length(components)
    graph_status = n_graph_components <= 1 ? :connected : :disconnected

    optional = _rating_design_optional_summary(data)
    coverage_specs = (
        (:person, :rater),
        (:person, :item),
        (:rater, :item),
        (:person, :rater, :item),
    )
    coverage_summaries = [
        _rating_design_cell_count_summary(data, facets, min_sparse_cell_count)
        for facets in coverage_specs
    ]
    person_rater_item = coverage_summaries[end]

    rows = NamedTuple[]
    push!(rows, _rating_design_audit_row(;
        audit = :rating_graph_components,
        status = graph_status,
        severity = graph_status === :connected ? :info : :error,
        facets = (:person, :rater, :item),
        n_components = n_graph_components,
        min_count = isempty(components) ? missing : minimum(length, components),
        max_count = isempty(components) ? missing : maximum(length, components),
        note = graph_status === :connected ?
            :person_rater_item_graph_connected :
            :person_rater_item_graph_disconnected,
        details = (;
            component_sizes = Tuple(length(component) for component in components),
            components,
        ),
    ))

    rater_linking_status = anchor_summary.rater_linking_status
    push!(rows, _rating_design_audit_row(;
        audit = :rater_linking,
        status = rater_linking_status,
        severity = rater_linking_status === :disconnected ? :error : :info,
        facets = (:rater,),
        unit,
        n_observed = anchor_summary.n_links_at_or_above_min,
        n_missing = anchor_summary.n_zero_overlap_pairs,
        n_sparse = anchor_summary.n_weak_links,
        n_components = anchor_summary.n_rater_components,
        min_count = anchor_summary.minimum_shared_units,
        max_count = isempty(overlap_rows) ? missing :
            maximum(row.shared_units for row in overlap_rows),
        note = rater_linking_status === :disconnected ?
            :rater_overlap_below_minimum_disconnects_graph :
            :rater_overlap_links_graph_at_minimum_threshold,
        details = (;
            min_shared_units,
            rater_components = anchor_summary.rater_components,
            n_overlap_pairs = anchor_summary.n_overlap_pairs,
            overlap_rows,
        ),
    ))

    anchor_status = anchor_summary.anchor_status
    anchor_severity = anchor_summary.n_anchor_target_failures == 0 ? :info : :error
    push!(rows, _rating_design_audit_row(;
        audit = :anchor_coverage,
        status = anchor_status,
        severity = anchor_severity,
        facets = (:person, :rater, :item, :thresholds),
        n_observed = anchor_summary.n_anchors,
        n_missing = anchor_summary.n_anchor_target_failures,
        note = anchor_status === :not_declared ?
            :anchors_not_declared :
            anchor_status === :declared ?
                :declared_anchor_targets_found :
                :declared_anchor_targets_missing,
        details = (;
            n_hard_anchors = anchor_summary.n_hard_anchors,
            n_soft_anchors = anchor_summary.n_soft_anchors,
            anchor_rows = anchor_summary.anchor_rows,
            anchor_sensitivity_status = anchor_summary.anchor_sensitivity_status,
            anchor_sensitivity_passed = anchor_summary.anchor_sensitivity_passed,
        ),
    ))

    coverage_rows = NamedTuple[]
    for summary in coverage_summaries
        status = summary.n_missing == 0 ? :complete_observed_grid :
            :unobserved_grid_cells
        row = _rating_design_audit_row(;
            audit = :observed_cell_coverage,
            status,
            severity = summary.n_missing == 0 ? :info : :warning,
            facets = summary.facets,
            n_expected = summary.n_expected,
            n_observed = summary.n_observed,
            n_missing = summary.n_missing,
            min_count = summary.min_count,
            max_count = summary.max_count,
            note =
                :structural_vs_accidental_missingness_not_identified_by_observed_long_data,
            details = (;
                missingness_class = summary.missingness_class,
                distinguishability = summary.distinguishability,
            ),
        )
        push!(coverage_rows, row)
        push!(rows, row)
    end

    repeated_status = person_rater_item.n_repeated == 0 ? :none_detected :
        :repeated_ratings_detected
    push!(rows, _rating_design_audit_row(;
        audit = :repeated_person_rater_item_ratings,
        status = repeated_status,
        severity = person_rater_item.n_repeated == 0 ? :info : :warning,
        facets = (:person, :rater, :item),
        n_observed = person_rater_item.n_observed,
        n_repeated = person_rater_item.n_repeated,
        min_count = person_rater_item.min_count,
        max_count = person_rater_item.max_count,
        note = person_rater_item.n_repeated == 0 ?
            :no_repeated_person_rater_item_cells :
            :repeated_person_rater_item_cells_require_interpretation_policy,
        details = (;
            repeated_examples = person_rater_item.repeated_examples,
        ),
    ))

    sparse_status = person_rater_item.n_sparse == 0 ? :none_detected :
        :sparse_observed_cells_detected
    push!(rows, _rating_design_audit_row(;
        audit = :sparse_person_rater_item_blocks,
        status = sparse_status,
        severity = person_rater_item.n_sparse == 0 ? :info : :warning,
        facets = (:person, :rater, :item),
        n_observed = person_rater_item.n_observed,
        n_sparse = person_rater_item.n_sparse,
        min_count = person_rater_item.min_count,
        max_count = person_rater_item.max_count,
        note = person_rater_item.n_sparse == 0 ?
            :observed_person_rater_item_cells_meet_sparse_threshold :
            :observed_person_rater_item_cells_below_sparse_threshold,
        details = (;
            min_sparse_cell_count,
            sparse_examples = person_rater_item.sparse_examples,
        ),
    ))

    push!(rows, _rating_design_audit_row(;
        audit = :optional_time_order_fields,
        status = optional.occasion_recorded ? :recorded_not_modeled : :not_declared,
        severity = :info,
        facets = optional.optional_facets,
        n_observed = length(optional.time_order_facets),
        note = optional.occasion_recorded ?
            :occasion_recorded_as_metadata_not_likelihood_term :
            :time_or_order_field_not_declared,
        details = optional,
    ))

    push!(rows, _rating_design_audit_row(;
        audit = :nonignorable_assignment,
        status = :limitation,
        severity = :warning,
        facets = optional.descriptive_assignment_facets,
        note = :current_likelihood_does_not_model_rater_assignment,
        details = (;
            assignment_model = :not_included,
            descriptive_assignment_facets = optional.descriptive_assignment_facets,
            interpretation =
                :nonrandom_or_nonignorable_rater_assignment_requires_external_design_or_assignment_model,
        ),
    ))

    total_unobserved_grid_cells = sum(row.n_missing for row in coverage_rows)
    passed = graph_status !== :disconnected &&
        rater_linking_status !== :disconnected &&
        anchor_summary.passed === true
    return (;
        schema = "bayesianmgmfrm.rating_design_audit.v1",
        object = :rating_design_audit,
        family = spec === nothing ? missing : spec.family,
        thresholds = spec === nothing ? missing : spec.thresholds,
        estimation_status = spec === nothing ? missing : spec.estimation_status,
        data_signature = validation === nothing ? _data_signature(data) :
            validation.data_signature,
        unit,
        min_shared_units,
        min_sparse_cell_count,
        status = passed ? :reviewed : :warning,
        passed,
        rows = Tuple(rows),
        n_rows = length(rows),
        overlap_rows,
        anchor_linking = anchor_summary,
        summary = (;
            passed,
            n_rows = length(rows),
            rating_graph_status = graph_status,
            n_rating_graph_components = n_graph_components,
            rater_linking_status,
            n_rater_components = anchor_summary.n_rater_components,
            anchor_status,
            n_anchors = anchor_summary.n_anchors,
            n_anchor_target_failures = anchor_summary.n_anchor_target_failures,
            n_unobserved_grid_cells = total_unobserved_grid_cells,
            n_repeated_person_rater_item_cells = person_rater_item.n_repeated,
            n_sparse_person_rater_item_cells = person_rater_item.n_sparse,
            structural_missingness_distinguishable = false,
            missingness_note =
                :structural_vs_accidental_missingness_not_identified_by_observed_long_data,
            optional_time_order_recorded = optional.occasion_recorded,
            nonignorable_assignment_flagged = true,
        ),
    )
end

const _EXPERIMENTAL_CANONICAL_ENTRYPOINT =
    "BayesianMGMFRM.Experimental.fit(spec)"
const _EXPERIMENTAL_LEGACY_ENTRYPOINT =
    "BayesianMGMFRM.fit(spec; experimental = true)"

function _guarded_generalized_fit_capability(family::Symbol)
    if family === :gmfrm
        return (;
            family,
            scope = :scalar_gmfrm_guarded_experimental,
            minimum_dimensions = 1,
            maximum_dimensions = 1,
            threshold_regimes = (:partial_credit,),
            spec_discrimination = (:rater,),
            requires_fixed_q = false,
            allows_validation_bias_terms = false,
            allows_anchors = false,
            kernel_discrimination = (:item_discrimination, :rater_consistency),
            kernel_threshold_block = :rater_steps,
            expected_blocks =
                (:person, :rater, :item, :item_discrimination,
                    :rater_consistency, :rater_steps),
        )
    elseif family === :mgmfrm
        return (;
            family,
            scope = :fixed_q_confirmatory_mgmfrm_guarded_experimental,
            minimum_dimensions = 2,
            maximum_dimensions = nothing,
            threshold_regimes = (:partial_credit,),
            spec_discrimination = (:none,),
            requires_fixed_q = true,
            allows_validation_bias_terms = false,
            allows_anchors = false,
            kernel_discrimination =
                (:item_dimension_discrimination, :rater_consistency),
            kernel_threshold_block = :item_steps,
            expected_blocks =
                (:person, :rater, :item, :item_dimension_discrimination,
                    :rater_consistency, :item_steps),
        )
    end
    throw(ArgumentError(
        "guarded generalized fitting supports only family = :gmfrm or :mgmfrm; got :$family",
    ))
end

"""
    model_ladder()

Return the package's machine-readable model ladder. Rows distinguish the
implemented minimal MFRM/RSM/PCM fitting slice, guarded experimental
generalized fit surfaces, and broader specified-only GMFRM/MGMFRM
configurations. The ladder is documentation data: it is used to keep claims
about fitting support separate from claims about representable specification
intent.
"""
function model_ladder()
    gmfrm_capability = _guarded_generalized_fit_capability(:gmfrm)
    mgmfrm_capability = _guarded_generalized_fit_capability(:mgmfrm)
    return [
        (;
            family = :mfrm,
            scope = :minimal_mfrm_rsm_pcm,
            dimensions = "1",
            discrimination = :none,
            threshold_regimes = (:rating_scale, :partial_credit),
            estimation_status = :fit_supported,
            public_fit = true,
            experimental_public = false,
            identification = (:reference_first_rater, :reference_first_item, :sum_to_zero_thresholds),
            note = "implemented additive one-dimensional many-facet Rasch location model",
        ),
        (;
            family = :gmfrm,
            scope = gmfrm_capability.scope,
            dimensions = "1",
            discrimination = gmfrm_capability.spec_discrimination,
            spec_discrimination = gmfrm_capability.spec_discrimination,
            kernel_discrimination = gmfrm_capability.kernel_discrimination,
            threshold_regimes = gmfrm_capability.threshold_regimes,
            estimation_status = :experimental_public,
            public_fit = true,
            experimental_public = true,
            identification = (:item_discrimination_product_constraint, :rater_consistency_positive, :rater_step_constraints),
            note = "guarded scalar rater-consistency GMFRM through BayesianMGMFRM.Experimental.fit(spec)",
        ),
        (;
            family = :mgmfrm,
            scope = mgmfrm_capability.scope,
            dimensions = ">= 2",
            discrimination = mgmfrm_capability.kernel_discrimination,
            spec_discrimination = mgmfrm_capability.spec_discrimination,
            kernel_discrimination = mgmfrm_capability.kernel_discrimination,
            threshold_regimes = mgmfrm_capability.threshold_regimes,
            estimation_status = :experimental_public,
            public_fit = true,
            experimental_public = true,
            identification = (:fixed_confirmatory_q_mask, :identity_latent_correlation, :standard_normal_ability_scale, :positive_q_masked_loadings),
            note = "guarded fixed-Q confirmatory MGMFRM through BayesianMGMFRM.Experimental.fit(spec)",
        ),
        (;
            family = :gmfrm,
            scope = :planned_generalized_mfrm,
            dimensions = "1",
            discrimination = (:global, :rater, :item, :rater_item),
            threshold_regimes = (:rating_scale, :partial_credit),
            estimation_status = :specified_only,
            public_fit = false,
            experimental_public = false,
            identification = (:item_discrimination_product_constraint, :rater_consistency_positive, :rater_step_constraints),
            note = "source-aligned preview for broader manifests and constraint review; broad fitting remains planned",
        ),
        (;
            family = :mgmfrm,
            scope = :planned_multidimensional_gmfrm,
            dimensions = ">= 2",
            discrimination = (:none, :global, :rater, :item, :rater_item),
            threshold_regimes = (:rating_scale, :partial_credit),
            estimation_status = :specified_only,
            public_fit = false,
            experimental_public = false,
            identification = (:confirmatory_q_mask, :rater_consistency_product_constraint, :item_step_constraints),
            note = "source-aligned preview for broader manifests and multidimensional gauge review; broad fitting remains planned",
        ),
    ]
end

function _release_scope_fit_surface_rows()
    gmfrm_capability = _guarded_generalized_fit_capability(:gmfrm)
    mgmfrm_capability = _guarded_generalized_fit_capability(:mgmfrm)
    return (
        (;
            surface = :minimal_mfrm_rsm_pcm,
            family = :mfrm,
            scope = :minimal_mfrm_rsm_pcm,
            status = :public_fit_supported,
            entrypoint = "fit(spec)",
            experimental_public = false,
            public_fit = true,
            claim_scope = :small_model_workflow_scaffold,
            note = "MFRM/RSM/PCM posterior fitting and report helpers for the minimal identified design",
        ),
        (;
            surface = :scalar_gmfrm_guarded_experimental,
            family = :gmfrm,
            scope = :scalar_gmfrm_fit_ready_candidate,
            status = :guarded_experimental_public,
            entrypoint = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
            legacy_entrypoint = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
            experimental_public = true,
            public_fit = true,
            claim_scope = :guarded_scalar_rater_consistency_only,
            threshold_regimes = gmfrm_capability.threshold_regimes,
            spec_discrimination = gmfrm_capability.spec_discrimination,
            q_matrix_policy = :not_used,
            anchors_allowed = gmfrm_capability.allows_anchors,
            validation_bias_terms_allowed =
                gmfrm_capability.allows_validation_bias_terms,
            note = "guarded scalar rater-consistency GMFRM, without broader generalized claims",
        ),
        (;
            surface = :fixed_q_confirmatory_mgmfrm_guarded_experimental,
            family = :mgmfrm,
            scope = :minimal_confirmatory_mgmfrm_candidate,
            status = :guarded_experimental_public,
            entrypoint = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
            legacy_entrypoint = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
            experimental_public = true,
            public_fit = true,
            claim_scope = :fixed_q_confirmatory_only,
            threshold_regimes = mgmfrm_capability.threshold_regimes,
            spec_discrimination = mgmfrm_capability.spec_discrimination,
            q_matrix_policy = :fixed_confirmatory,
            anchors_allowed = mgmfrm_capability.allows_anchors,
            validation_bias_terms_allowed =
                mgmfrm_capability.allows_validation_bias_terms,
            note = "guarded fixed-Q confirmatory MGMFRM, without model-weight or sparse-superiority claims",
        ),
    )
end

function _release_scope_status_vocabulary_rows()
    return (
        (;
            status = :supported,
            current_aliases = (:fit_supported, :public_fit_supported),
            public_fit = true,
            experimental_public = false,
            stable_public = false,
            external_validated = false,
            meaning = "ordinary fit-supported public workflow for the current release scope",
        ),
        (;
            status = :experimental_public,
            current_aliases = (
                :experimental_public,
                :guarded_experimental,
                :guarded_experimental_public,
            ),
            public_fit = true,
            experimental_public = true,
            stable_public = false,
            external_validated = false,
            meaning = "narrow guarded fit path with explicit caveats and blocked broad claims",
        ),
        (;
            status = :specified_only,
            current_aliases = (:specified_only,),
            public_fit = false,
            experimental_public = false,
            stable_public = false,
            external_validated = false,
            meaning = "manifest and preview surface only; ordinary fitting is rejected",
        ),
        (;
            status = :blocked,
            current_aliases = (
                :blocked,
                :out_of_scope,
                :not_public_fit_api,
                :not_a_public_fit_api,
                :manual_only,
            ),
            public_fit = false,
            experimental_public = false,
            stable_public = false,
            external_validated = false,
            meaning = "unsupported or claim-blocked surface",
        ),
        (;
            status = :stable_public,
            current_aliases = (:stable_public,),
            public_fit = true,
            experimental_public = false,
            stable_public = true,
            external_validated = false,
            meaning = "ordinary package claims backed by simulation, sensitivity, and reproducibility evidence",
        ),
        (;
            status = :external_validated,
            current_aliases = (:external_validated,),
            public_fit = true,
            experimental_public = false,
            stable_public = true,
            external_validated = true,
            meaning = "post-v0.2.0 external validation claims backed by known-truth R-package simulations and later real-data evidence",
        ),
    )
end

function _status_policy_label(estimation_status::Symbol;
        public_fit::Bool = estimation_status === :fit_supported,
        experimental_public::Bool = false,
        stable_public::Bool = false,
        external_validated::Bool = false)
    external_validated && return :external_validated
    stable_public && return :stable_public
    experimental_public && return :experimental_public
    public_fit && return :supported
    estimation_status === :specified_only && return :specified_only
    return :blocked
end

function _status_policy_blocked_claims(family::Symbol, status_label::Symbol)
    blocked = Symbol[
        :dff_model_effects,
        :model_weight_or_superiority,
    ]
    status_label !== :external_validated && append!(blocked, (
        :r_package_overlap_comparison,
        :real_data_validation,
        :external_validation,
    ))
    family in (:gmfrm, :mgmfrm) &&
        status_label in (:experimental_public, :specified_only, :blocked) &&
        push!(blocked, :broad_generalized_fit)
    family === :mgmfrm && push!(blocked, :sparse_mgmfrm_superiority)
    status_label in (:specified_only, :blocked) && push!(blocked, :public_fit)
    !(status_label in (:stable_public, :external_validated)) &&
        push!(blocked, :stable_public_claim)
    return Tuple(blocked)
end

function _status_policy_manifest(family::Symbol,
        estimation_status::Symbol;
        public_fit::Bool = estimation_status === :fit_supported,
        experimental_public::Bool = false,
        fit_ready::Bool = public_fit,
        stable_public::Bool = false,
        external_validated::Bool = false,
        claim_scope = missing)
    normalized_stable_public = stable_public || external_validated
    normalized_experimental_public = experimental_public && !normalized_stable_public
    normalized_public_fit =
        public_fit || normalized_experimental_public || normalized_stable_public
    normalized_fit_ready = fit_ready || normalized_public_fit
    status_label = _status_policy_label(
        estimation_status;
        public_fit = normalized_public_fit,
        experimental_public = normalized_experimental_public,
        stable_public = normalized_stable_public,
        external_validated,
    )
    return (;
        schema = "bayesianmgmfrm.status_policy.v1",
        family,
        estimation_status,
        status_label,
        public_fit = normalized_public_fit,
        experimental_public = normalized_experimental_public,
        fit_ready = normalized_fit_ready,
        stable_public = normalized_stable_public,
        external_validated,
        claim_scope,
        blocked_claims = _status_policy_blocked_claims(family, status_label),
        next_gate = status_label === :experimental_public ?
            :v0_1_1_generalized_refinement :
            status_label === :specified_only ?
            :promotion_review :
            status_label === :supported ?
            :ordinary_supported_workflow :
            status_label === :stable_public ?
            :post_v0_2_external_validation :
            status_label === :external_validated ?
            :maintain_external_validation_evidence :
            :scope_or_design_repair,
    )
end

function _release_scope_blocked_option_rows()
    rows = NamedTuple[]
    for row in _gmfrm_experimental_rejected_option_rows()
        push!(rows, merge((family = :gmfrm, scope = :scalar_gmfrm_fit_ready_candidate), row))
    end
    for row in _mgmfrm_experimental_rejected_option_rows()
        push!(rows, merge((family = :mgmfrm, scope = :minimal_confirmatory_mgmfrm_candidate), row))
    end
    return Tuple(rows)
end

function _release_scope_blocked_claim_rows()
    return (
        (;
            claim = :broad_generalized_fit,
            status = :blocked,
            blocker = :manual_public_scope_release_decision_required,
            note = "only the guarded scalar GMFRM and fixed-Q confirmatory MGMFRM surfaces are enabled",
        ),
        (;
            claim = :dff_model_effects,
            status = :blocked,
            blocker = :future_dff_model_effect_fit_policy,
            note = "DFF support is validation and screening only",
        ),
        (;
            claim = :model_weight_or_superiority,
            status = :blocked,
            blocker = :model_weight_or_superiority_claim_not_promoted,
            note = "WAIC, raw LOO, and K-fold helpers record diagnostics but do not authorize model-weight claims",
        ),
        (;
            claim = :sparse_mgmfrm_superiority,
            status = :blocked,
            blocker = :broader_sparse_mgmfrm_claim_scope_not_promoted,
            note = "local sparse evidence supports guarded experimentation only",
        ),
        (;
            claim = :r_package_overlap_comparison,
            status = :blocked,
            blocker = :post_v0_2_known_truth_simulation_comparison_required,
            note = "overlap comparisons with R packages are post-v0.2.0 validation evidence",
        ),
        (;
            claim = :real_data_validation,
            status = :blocked,
            blocker = :post_v0_2_external_validation_sequence_required,
            note = "real-data validation is not a v0.1.x or v0.2.0 release gate",
        ),
        (;
            claim = :external_validation,
            status = :blocked,
            blocker = :post_v0_2_external_validation_sequence_required,
            note = "external validation claims require later known-truth comparisons before real-data claims",
        ),
        (;
            claim = :publication_or_registration,
            status = :manual_only,
            blocker = :manual_publication_or_registration_by_user_only,
            note = "the package records local evidence but performs no publication or registration action",
        ),
    )
end

function _release_scope_evidence_rows()
    rows = NamedTuple[]
    for row in _gmfrm_experimental_public_evidence_rows()
        push!(rows, merge((family = :gmfrm, scope = :scalar_gmfrm_fit_ready_candidate), row))
    end
    for row in _mgmfrm_experimental_public_evidence_rows()
        push!(rows, merge((family = :mgmfrm, scope = :minimal_confirmatory_mgmfrm_candidate), row))
    end
    append!(rows, [
        (family = :all_package_surfaces,
            scope = :general_registration_readiness,
            evidence = :pre_registration_gate_available,
            status = :done,
            artifact = :scripts_pre_registration_gate),
        (family = :all_package_surfaces,
            scope = :documentation_readiness,
            evidence = :documenter_html_page_size_gate,
            status = :done,
            artifact = :docs_make),
        (family = :gmfrm,
            scope = :scalar_gmfrm_fit_ready_candidate,
            evidence = :guarded_generalized_fit_cache,
            status = :done,
            artifact = :cached_fit_experimental_gmfrm),
        (family = :mgmfrm,
            scope = :minimal_confirmatory_mgmfrm_candidate,
            evidence = :guarded_generalized_fit_cache,
            status = :done,
            artifact = :cached_fit_experimental_mgmfrm),
        (family = :all_fit_objects,
            scope = :fit_reproduction_manifest,
            evidence = :fit_reproduction_cache_identity_check,
            status = :done,
            artifact = :fit_reproduction_manifest),
        (family = :gmfrm_mgmfrm,
            scope = :v0_1_1_generalized_refinement,
            evidence = :implementation_checklist_created,
            status = :planned,
            artifact = :docs_src_v0_1_1_implementation_checklist),
        (family = :all_evidence_artifacts,
            scope = :evidence_schema_policy,
            evidence = :evidence_artifact_schema_policy,
            status = :done,
            artifact = :evidence_artifact_schema_policy),
        (family = :all_package_surfaces,
            scope = :status_synchronization,
            evidence = :release_gate_check,
            status = :done,
            artifact = :release_gate_check),
        (family = :all_related_software,
            scope = :positioning_and_non_superiority,
            evidence = :related_software_capability_matrix,
            status = :done,
            artifact = :related_software_capability_matrix),
    ])
    return Tuple(rows)
end

"""
    release_scope_summary(; include_evidence = false)

Return a machine-readable summary of the package's current release scope. The
summary lists the public fit surfaces that are currently enabled, the
unsupported generalized options that remain rejected, and the broad claims that
remain blocked. Set `include_evidence = true` to include the local evidence rows
recorded by the guarded GMFRM/MGMFRM exposure manifests plus the current
fit-cache, reproduction-manifest, documentation-size, and pre-registration gate
guardrails.

This is a release-scope guardrail, not a statistical validation result and not a
publication or registration action.
"""
function release_scope_summary(; include_evidence::Bool = false)
    fit_surfaces = _release_scope_fit_surface_rows()
    blocked_options = _release_scope_blocked_option_rows()
    blocked_claims = _release_scope_blocked_claim_rows()
    status_vocabulary = _release_scope_status_vocabulary_rows()
    evidence_policy = evidence_artifact_schema_policy(:release_scope_evidence;
        include_environment = false,
        include_cache_provenance = true,
        raw_data_status = :not_included,
        unsupported_claims = Tuple(row.claim for row in blocked_claims))
    evidence_rows = include_evidence ? _release_scope_evidence_rows() : NamedTuple[]
    return (;
        schema = "bayesianmgmfrm.release_scope_summary.v1",
        object = :release_scope_summary,
        status = :scope_recorded,
        status_vocabulary,
        evidence_artifact_schema_policy = evidence_policy,
        public_fit_surfaces = fit_surfaces,
        blocked_public_options = blocked_options,
        blocked_claims,
        evidence_rows,
        summary = (;
            n_status_vocabulary_rows = length(status_vocabulary),
            n_public_fit_surfaces = length(fit_surfaces),
            n_guarded_experimental_surfaces =
                count(row -> row.experimental_public, fit_surfaces),
            n_blocked_public_options = length(blocked_options),
            n_blocked_claims = length(blocked_claims),
            n_evidence_rows = length(evidence_rows),
            minimal_mfrm_fit_allowed = true,
            scalar_gmfrm_guarded_fit_allowed = true,
            fixed_q_mgmfrm_guarded_fit_allowed = true,
            guarded_generalized_fit_cache_ready = true,
            fit_reproduction_cache_identity_checked = true,
            documenter_html_page_size_gate = true,
            pre_registration_gate_available = true,
            evidence_artifact_schema_policy_recorded = true,
            related_software_capability_matrix_recorded = true,
            general_registration_manual_only = true,
            broader_generalized_fit_allowed = false,
            dff_model_effects_allowed = false,
            model_weight_claims_allowed = false,
            sparse_superiority_claims_allowed = false,
            publication_or_registration_action = false,
            v0_1_1_generalized_refinement_planned = true,
            next_gate = :manual_publication_or_registration_by_user_only,
        ),
    )
end

function _related_software_source_rows()
    return (
        (;
            tool = :facets,
            source_kind = :official_product_documentation,
            url = "https://www.winsteps.com/facets.htm",
            role = :many_facet_rasch_measurement,
        ),
        (;
            tool = :facets,
            source_kind = :official_theory_documentation,
            url = "https://www.winsteps.com/facetman/theory.htm",
            role = :many_facet_model_theory,
        ),
        (;
            tool = :tam,
            source_kind = :official_cran_reference,
            url = "https://cran.r-project.org/web/packages/TAM/refman/TAM.html",
            role = :irt_mfrm_multidimensional_models,
        ),
        (;
            tool = :mirt,
            source_kind = :journal_article,
            url = "https://www.jstatsoft.org/article/view/v048i06",
            role = :exploratory_and_confirmatory_mirt,
        ),
        (;
            tool = :sirt,
            source_kind = :official_cran_reference,
            url = "https://cran.r-project.org/web/packages/sirt/sirt.pdf",
            role = :supplementary_irt_models_and_rater_effects,
        ),
        (;
            tool = :immer,
            source_kind = :official_cran_reference,
            url = "https://cran.r-project.org/web/packages/immer/immer.pdf",
            role = :item_response_models_for_multiple_ratings,
        ),
        (;
            tool = :brms_stan,
            source_kind = :official_cran_reference,
            url = "https://cran.r-project.org/web/packages/brms/brms.pdf",
            role = :bayesian_multilevel_models_via_stan,
        ),
        (;
            tool = :stan,
            source_kind = :official_user_guide,
            url = "https://mc-stan.org/docs/stan-users-guide/item-response-models.html",
            role = :custom_bayesian_irt_modeling,
        ),
        (;
            tool = :bayesianmgmfrm,
            source_kind = :package_manifest,
            url = "local://BayesianMGMFRM.jl/release_scope_summary",
            role = :source_audited_bayesian_mgmfrm_workflow,
        ),
    )
end

function _related_software_row(; tool::Symbol,
        display_name::AbstractString,
        ecosystem::Symbol,
        current_role::Symbol,
        model_coverage,
        estimation_methods,
        rater_facet_support::Symbol,
        multidimensional_support::Symbol,
        bayesian_support::Symbol,
        diagnostics_and_sensitivity,
        report_artifact_support::Symbol,
        bayesianmgmfrm_overlap,
        v0_1_1_position::Symbol,
        comparison_gate::Symbol,
        source_urls)
    return (;
        schema = "bayesianmgmfrm.related_software_capability_row.v1",
        tool,
        display_name = String(display_name),
        ecosystem,
        current_role,
        model_coverage = Tuple(Symbol(item) for item in model_coverage),
        estimation_methods = Tuple(Symbol(item) for item in estimation_methods),
        rater_facet_support,
        multidimensional_support,
        bayesian_support,
        diagnostics_and_sensitivity =
            Tuple(Symbol(item) for item in diagnostics_and_sensitivity),
        report_artifact_support,
        bayesianmgmfrm_overlap =
            Tuple(Symbol(item) for item in bayesianmgmfrm_overlap),
        v0_1_1_position,
        comparison_gate,
        source_urls = Tuple(String(url) for url in source_urls),
    )
end

function _related_software_capability_rows()
    return (
        _related_software_row(
            tool = :facets,
            display_name = "Facets",
            ecosystem = :standalone_rasch,
            current_role = :mature_many_facet_rasch_measurement,
            model_coverage = (:unidimensional_mfrm, :ordinal_rasch,
                :many_facet_rating_designs),
            estimation_methods = (:rasch_measurement_workflow,),
            rater_facet_support = :first_class_many_facet_rater_support,
            multidimensional_support = :not_the_primary_public_claim,
            bayesian_support = :not_a_bayesian_workflow,
            diagnostics_and_sensitivity = (:fit_statistics, :facet_maps,
                :separation_reliability, :practitioner_tables),
            report_artifact_support = :interactive_and_report_oriented_outputs,
            bayesianmgmfrm_overlap = (:mfrm_practitioner_outputs,
                :facet_maps, :fit_statistics),
            v0_1_1_position = :migration_reference_not_replacement_claim,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = (
                "https://www.winsteps.com/facets.htm",
                "https://www.winsteps.com/facetman/theory.htm",
            )),
        _related_software_row(
            tool = :tam,
            display_name = "TAM",
            ecosystem = :r_package,
            current_role = :broad_irt_and_mfr_modeling,
            model_coverage = (:rasch, :pcm, :gpcm, :multidimensional_irt,
                :multi_faceted_rasch_models),
            estimation_methods = (:marginal_maximum_likelihood,
                :joint_maximum_likelihood, :expected_a_posteriori),
            rater_facet_support = :multi_faceted_rasch_available,
            multidimensional_support = :broad_multidimensional_irt_available,
            bayesian_support = :not_the_primary_public_workflow,
            diagnostics_and_sensitivity = (:irt_model_tables,
                :fit_and_item_diagnostics, :plausible_values),
            report_artifact_support = :r_objects_and_tables,
            bayesianmgmfrm_overlap = (:mfrm_pcm_gpcm_overlap,
                :fixed_q_multidimensional_overlap_candidates),
            v0_1_1_position = :breadth_baseline_not_feature_checklist,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = (
                "https://cran.r-project.org/web/packages/TAM/refman/TAM.html",)),
        _related_software_row(
            tool = :mirt,
            display_name = "mirt",
            ecosystem = :r_package,
            current_role = :exploratory_and_confirmatory_mirt,
            model_coverage = (:unidimensional_irt, :multidimensional_irt,
                :exploratory_mirt, :confirmatory_mirt),
            estimation_methods = (:em, :mhrm, :multiple_group_estimation),
            rater_facet_support = :not_a_dedicated_mfrm_facets_workflow,
            multidimensional_support = :first_class_mirt_support,
            bayesian_support = :not_the_primary_public_workflow,
            diagnostics_and_sensitivity = (:item_fit, :model_fit,
                :technical_mirt_outputs),
            report_artifact_support = :r_objects_and_tables,
            bayesianmgmfrm_overlap = (:fixed_q_mirt_expectations,
                :dimension_loading_interpretation),
            v0_1_1_position = :multidimensional_baseline_not_mfr_replacement,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = (
                "https://www.jstatsoft.org/article/view/v048i06",)),
        _related_software_row(
            tool = :sirt,
            display_name = "sirt",
            ecosystem = :r_package,
            current_role = :supplementary_irt_methods,
            model_coverage = (:rasch_extensions, :differential_item_functioning,
                :rater_effects, :diagnostic_models),
            estimation_methods = (:specialized_irt_estimators,
                :simulation_and_diagnostics),
            rater_facet_support = :rater_effect_related_methods,
            multidimensional_support = :selected_multidimensional_and_diagnostic_models,
            bayesian_support = :not_the_primary_public_workflow,
            diagnostics_and_sensitivity = (:supplementary_irt_diagnostics,
                :simulation_helpers),
            report_artifact_support = :r_objects_and_tables,
            bayesianmgmfrm_overlap = (:rater_effect_screening,
                :bias_and_dff_context),
            v0_1_1_position = :specialized_method_reference,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = (
                "https://cran.r-project.org/web/packages/sirt/sirt.pdf",)),
        _related_software_row(
            tool = :immer,
            display_name = "immer",
            ecosystem = :r_package,
            current_role = :models_for_multiple_ratings,
            model_coverage = (:multiple_ratings, :rater_models,
                :item_response_models),
            estimation_methods = (:specialized_rater_model_estimators,),
            rater_facet_support = :first_class_multiple_rating_support,
            multidimensional_support = :not_the_primary_public_claim,
            bayesian_support = :not_the_primary_public_workflow,
            diagnostics_and_sensitivity = (:rater_model_outputs,),
            report_artifact_support = :r_objects_and_tables,
            bayesianmgmfrm_overlap = (:rater_effect_context,
                :multiple_rating_designs),
            v0_1_1_position = :rater_model_reference,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = (
                "https://cran.r-project.org/web/packages/immer/immer.pdf",)),
        _related_software_row(
            tool = :brms_stan,
            display_name = "brms/Stan workflows",
            ecosystem = :r_and_stan,
            current_role = :custom_bayesian_multilevel_modeling,
            model_coverage = (:ordinal_models, :multilevel_models,
                :custom_irt_possible_in_stan),
            estimation_methods = (:hmc_nuts, :bayesian_posterior_inference),
            rater_facet_support = :possible_with_custom_multilevel_formulas_or_stan,
            multidimensional_support = :possible_with_custom_modeling,
            bayesian_support = :first_class_bayesian_inference,
            diagnostics_and_sensitivity = (:mcmc_diagnostics,
                :posterior_predictive_checks, :loo_workflows),
            report_artifact_support = :r_stan_objects_and_user_built_reports,
            bayesianmgmfrm_overlap = (:bayesian_diagnostics,
                :custom_irt_targets, :posterior_predictive_checks),
            v0_1_1_position = :bayesian_workflow_baseline_not_packaged_mgmfrm,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = (
                "https://cran.r-project.org/web/packages/brms/brms.pdf",
                "https://mc-stan.org/docs/stan-users-guide/item-response-models.html",
            )),
        _related_software_row(
            tool = :bayesianmgmfrm,
            display_name = "BayesianMGMFRM.jl",
            ecosystem = :julia_package,
            current_role = :source_audited_bayesian_mgmfrm_workflow,
            model_coverage = (:supported_mfrm_rsm_pcm,
                :experimental_scalar_rater_consistency_gmfrm,
                :experimental_fixed_q_confirmatory_mgmfrm,
                :blocked_broad_generalized_mgmfrm),
            estimation_methods = (:random_walk_metropolis, :advancedhmc_nuts,
                :turing_nuts, :guarded_raw_coordinate_hmc),
            rater_facet_support = :mfrm_and_guarded_rater_consistency_workflow,
            multidimensional_support = :fixed_q_confirmatory_experimental_only,
            bayesian_support = :package_core_workflow,
            diagnostics_and_sensitivity = (:mcmc_diagnostics,
                :posterior_predictive_checks, :calibration,
                :prior_likelihood_sensitivity, :release_gate_check),
            report_artifact_support = :versioned_hash_checked_artifacts,
            bayesianmgmfrm_overlap = (:package_under_development,),
            v0_1_1_position = :narrow_auditable_workflow_not_generic_irt_replacement,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = ("local://BayesianMGMFRM.jl/release_scope_summary",)),
    )
end

"""
    related_software_capability_matrix()

Return the v0.1.1 related-software positioning matrix. The matrix compares
Facets, TAM, mirt, sirt, immer, brms/Stan-style workflows, and
`BayesianMGMFRM.jl` across model coverage, estimation style, rater/facet
support, multidimensional support, Bayesian workflow support, diagnostics and
sensitivity coverage, and report-artifact support.

This is a scope-governance artifact, not validation evidence and not a
superiority claim. Overlap comparisons against R packages or Facets remain a
post-v0.2.0 known-truth simulation task where model targets genuinely overlap.
"""
function related_software_capability_matrix()
    rows = _related_software_capability_rows()
    sources = _related_software_source_rows()
    axes = (
        :model_coverage,
        :estimation_methods,
        :rater_facet_support,
        :multidimensional_support,
        :bayesian_support,
        :diagnostics_and_sensitivity,
        :report_artifact_support,
    )
    return (;
        schema = "bayesianmgmfrm.related_software_capability_matrix.v1",
        object = :related_software_capability_matrix,
        status = :scope_positioning_recorded,
        axes,
        rows,
        sources,
        summary = (;
            n_tools = length(rows),
            n_axes = length(axes),
            tools = Tuple(row.tool for row in rows),
            includes_facets = any(row -> row.tool === :facets, rows),
            includes_tam = any(row -> row.tool === :tam, rows),
            includes_mirt = any(row -> row.tool === :mirt, rows),
            includes_sirt = any(row -> row.tool === :sirt, rows),
            includes_immer = any(row -> row.tool === :immer, rows),
            includes_brms_stan = any(row -> row.tool === :brms_stan, rows),
            includes_bayesianmgmfrm =
                any(row -> row.tool === :bayesianmgmfrm, rows),
            no_superiority_claims = true,
            generic_irt_replacement_claims_allowed = false,
            r_package_overlap_comparison_allowed = false,
            comparison_gate =
                :post_v0_2_known_truth_simulation_where_overlap_exists,
            package_niche =
                :source_audited_bayesian_rater_mediated_mgmfrm_workflow,
        ),
    )
end

_release_gate_default_root() = normpath(joinpath(@__DIR__, ".."))

function _release_gate_document_specs()
    return (
        (;
            target = :readme_public_surface,
            path = "README.md",
            required = (
                "Pkg.add(\"BayesianMGMFRM\")",
                "| Scalar rater-consistency GMFRM | Experimental |",
                "| Fixed-Q confirmatory MGMFRM | Experimental |",
                "| Broader discrimination structures | Not supported |",
                "BayesianMGMFRM.Experimental.fit",
                "fit(spec; experimental = true)",
                "no anchors",
                "fitted DFF terms",
            ),
            forbidden = (),
        ),
        (;
            target = :news_public_changes,
            path = "NEWS.md",
            required = (
                "## Unreleased",
                "BayesianMGMFRM.Experimental",
                "canonical quarantine namespace",
                "no longer the recommended entry point",
                "## 0.1.1",
                "User-facing experimental fit displays",
                "Refocus the published manual on installation, model scope, fitting",
                "version-1 report payloads remain unchanged",
            ),
            forbidden = (),
        ),
        (;
            target = :docs_index_public_surface,
            path = joinpath("docs", "src", "index.md"),
            required = (
                "rater-consistency GMFRM",
                "fixed-Q confirmatory MGMFRM",
                "not supported",
                "Scope and Releases",
                "fit_report_markdown",
            ),
            forbidden = (),
        ),
        (;
            target = :docs_fitting_experimental_contract,
            path = joinpath("docs", "src", "fitting.md"),
            required = (
                "`thresholds = :partial_credit`",
                "`discrimination = :rater`",
                "`discrimination = :none`",
                "no anchors and no fitted DFF terms",
                "Custom generalized prior objects are not supported",
            ),
            forbidden = (),
        ),
        (;
            target = :docs_experimental_namespace_contract,
            path = joinpath("docs", "src", "experimental.md"),
            required = (
                "BayesianMGMFRM.Experimental",
                "BayesianMGMFRM.Experimental.fit",
                "fit(spec; experimental = true)",
                "fixed-Q confirmatory MGMFRM",
                "contract.stable_public_gates",
                "contract.external_validated_gates",
                "Stable-public consideration",
                "external-validated level separately",
                "tests does not perform it",
            ),
            forbidden = (),
        ),
        (;
            target = :docs_scope_public_surface,
            path = joinpath("docs", "src", "scope.md"),
            required = (
                "| MFRM with rating-scale or partial-credit steps | Supported |",
                "| Scalar rater-consistency GMFRM | Experimental |",
                "| Fixed-Q confirmatory MGMFRM | Experimental |",
                "| Broader generalized discrimination structures | Not supported |",
                "The registered release remains the default installation.",
            ),
            forbidden = (),
        ),
        (;
            target = :docs_model_equations_scope,
            path = joinpath("docs", "src", "model-equations.md"),
            required = (
                "rater-consistency",
                "fixed-Q confirmatory",
                "under development",
                "Scope and Releases",
            ),
            forbidden = (),
        ),
        (;
            target = :docs_bayesian_workflow_scope,
            path = joinpath("docs", "src", "bayesian-workflow.md"),
            required = (
                "Validate the Rating Design",
                "Inspect the Model Before Fitting",
                "Fit and Diagnose",
                "Compare Models Carefully",
                "Report the Boundary",
            ),
            forbidden = (),
        ),
        (;
            target = :docs_examples_public_surface,
            path = joinpath("docs", "src", "examples.md"),
            required = (
                "learning and",
                "public surfaces",
                "experimental MGMFRM entrypoint",
                "does not support exploratory loadings",
            ),
            forbidden = (),
        ),
        (;
            target = :documenter_public_boundary,
            path = joinpath("docs", "make.jl"),
            required = (
                "checkdocs = :exports",
                "pagesonly = true",
                "Scope and Releases",
                "BayesianMGMFRM.Experimental",
                "\"experimental.md\"",
                "\"scope.md\"",
            ),
            forbidden = (
                "\"roadmap.md\"",
                "\"registration.md\"",
                "\"mgmfrm-research-roadmap.md\"",
                "\"v0.1.1-implementation-checklist.md\"",
            ),
        ),
    )
end

function _release_gate_row(; source::Symbol, target::Symbol, path = missing,
        check::Symbol, expected, observed, passed::Bool, note::AbstractString = "")
    return (;
        schema = "bayesianmgmfrm.release_gate_check_row.v1",
        source,
        target,
        path,
        check,
        expected,
        observed,
        status = passed ? :passed : :failed,
        note,
    )
end

_release_gate_contains(text::AbstractString, needle::AbstractString) =
    occursin(lowercase(needle), lowercase(text))

_release_gate_forbidden_public_tokens() = (
    "experimental_public",
    "guarded_local_fit",
    "internal_target_constructor",
    "internal_sampler_diagnostic_constructor",
    "blocked_option",
    "supported_surface",
    "next_gate",
    "pre-registration",
    "registration handoff",
    "test/fixtures/",
    "scripts/generate_",
)

function _release_gate_document_rows(root::AbstractString)
    rows = NamedTuple[]
    for spec in _release_gate_document_specs()
        path = joinpath(root, spec.path)
        present = isfile(path)
        push!(rows, _release_gate_row(
            source = :documentation,
            target = spec.target,
            path = spec.path,
            check = :document_present,
            expected = :present,
            observed = present ? :present : :missing,
            passed = present,
            note = "critical release-scope document is present",
        ))
        present || continue
        text = read(path, String)
        for token in spec.required
            found = _release_gate_contains(text, token)
            push!(rows, _release_gate_row(
                source = :documentation,
                target = spec.target,
                path = spec.path,
                check = :required_text,
                expected = token,
                observed = found ? :present : :missing,
                passed = found,
                note = "required generalized-support wording is present",
            ))
        end
        for token in (spec.forbidden..., _release_gate_forbidden_public_tokens()...)
            found = _release_gate_contains(text, token)
            push!(rows, _release_gate_row(
                source = :documentation,
                target = spec.target,
                path = spec.path,
                check = :forbidden_text_absent,
                expected = :absent,
                observed = found ? token : :absent,
                passed = !found,
                note = "outdated generalized-support wording is absent",
            ))
        end
    end
    return Tuple(rows)
end

function _release_gate_manifest_rows(scope)
    rows = NamedTuple[]
    statuses = Tuple(row.status for row in scope.status_vocabulary)
    for status in (:supported, :experimental_public, :specified_only, :blocked,
            :stable_public, :external_validated)
        passed = status in statuses
        push!(rows, _release_gate_row(
            source = :manifest,
            target = :status_vocabulary,
            check = :status_defined,
            expected = status,
            observed = passed ? status : statuses,
            passed = passed,
            note = "release status vocabulary includes the expected status",
        ))
    end

    surfaces = scope.public_fit_surfaces
    blocked_claims = Tuple(row.claim for row in scope.blocked_claims)
    evidence_rows = scope.evidence_rows
    ladder = model_ladder()
    gmfrm_guarded_surface = only(row for row in ladder
        if row.scope === :scalar_gmfrm_guarded_experimental)
    mgmfrm_guarded_surface = only(row for row in ladder
        if row.scope === :fixed_q_confirmatory_mgmfrm_guarded_experimental)
    manifest_checks = (
        (target = :minimal_mfrm_supported,
            expected = :supported_public_fit,
            observed = any(row -> row.surface === :minimal_mfrm_rsm_pcm &&
                row.public_fit && !row.experimental_public,
                surfaces)),
        (target = :scalar_gmfrm_experimental_public,
            expected = :experimental_public_guarded_fit,
            observed = any(row -> row.surface === :scalar_gmfrm_guarded_experimental &&
                row.public_fit && row.experimental_public &&
                row.entrypoint == _EXPERIMENTAL_CANONICAL_ENTRYPOINT &&
                row.legacy_entrypoint == _EXPERIMENTAL_LEGACY_ENTRYPOINT &&
                row.claim_scope === :guarded_scalar_rater_consistency_only &&
                row.threshold_regimes == (:partial_credit,) &&
                row.spec_discrimination == (:rater,) &&
                !row.anchors_allowed && !row.validation_bias_terms_allowed,
                surfaces)),
        (target = :fixed_q_mgmfrm_experimental_public,
            expected = :experimental_public_guarded_fit,
            observed = any(row -> row.surface ===
                :fixed_q_confirmatory_mgmfrm_guarded_experimental &&
                row.public_fit && row.experimental_public &&
                row.entrypoint == _EXPERIMENTAL_CANONICAL_ENTRYPOINT &&
                row.legacy_entrypoint == _EXPERIMENTAL_LEGACY_ENTRYPOINT &&
                row.claim_scope === :fixed_q_confirmatory_only &&
                row.threshold_regimes == (:partial_credit,) &&
                row.spec_discrimination == (:none,) &&
                row.q_matrix_policy === :fixed_confirmatory &&
                !row.anchors_allowed && !row.validation_bias_terms_allowed,
                surfaces)),
        (target = :scalar_gmfrm_fail_closed_option_contract,
            expected = :partial_credit_rater_no_implicit_variant,
            observed = gmfrm_guarded_surface.threshold_regimes ==
                (:partial_credit,) &&
                gmfrm_guarded_surface.spec_discrimination == (:rater,)),
        (target = :fixed_q_mgmfrm_fail_closed_option_contract,
            expected = :partial_credit_generic_none_no_implicit_variant,
            observed = mgmfrm_guarded_surface.threshold_regimes ==
                (:partial_credit,) &&
                mgmfrm_guarded_surface.spec_discrimination == (:none,)),
        (target = :broad_generalized_claims_blocked,
            expected = :blocked,
            observed = :broad_generalized_fit in blocked_claims &&
                !scope.summary.broader_generalized_fit_allowed),
        (target = :dff_model_effects_blocked,
            expected = :blocked,
            observed = :dff_model_effects in blocked_claims &&
                !scope.summary.dff_model_effects_allowed),
        (target = :model_weight_claims_blocked,
            expected = :blocked,
            observed = :model_weight_or_superiority in blocked_claims &&
                !scope.summary.model_weight_claims_allowed),
        (target = :sparse_superiority_claims_blocked,
            expected = :blocked,
            observed = :sparse_mgmfrm_superiority in blocked_claims &&
                !scope.summary.sparse_superiority_claims_allowed),
        (target = :post_v0_2_external_validation_blocked,
            expected = :blocked_until_external_validation,
            observed = all(claim -> claim in blocked_claims,
                (:r_package_overlap_comparison, :real_data_validation,
                    :external_validation))),
        (target = :v0_1_1_refinement_evidence_row,
            expected = :recorded,
            observed = any(row -> row.scope === :v0_1_1_generalized_refinement &&
                row.evidence === :implementation_checklist_created,
                evidence_rows)),
        (target = :release_gate_check_evidence_row,
            expected = :recorded,
            observed = any(row -> row.scope === :status_synchronization &&
                row.evidence === :release_gate_check,
                evidence_rows)),
        (target = :related_software_capability_matrix_evidence_row,
            expected = :recorded,
            observed = any(row -> row.scope === :positioning_and_non_superiority &&
                row.evidence === :related_software_capability_matrix,
                evidence_rows)),
    )
    for check in manifest_checks
        passed = check.observed === true
        push!(rows, _release_gate_row(
            source = :manifest,
            target = check.target,
            check = :manifest_consistency,
            expected = check.expected,
            observed = check.observed,
            passed = passed,
            note = "release-scope manifest agrees with the v0.1.1 public-surface policy",
        ))
    end
    return Tuple(rows)
end

"""
    release_gate_check(; root = package root, throw_on_failure = false)

Check that README, roadmap, docs, and release-scope manifest rows agree about
the current generalized support policy. The gate expects minimal MFRM/RSM/PCM
to remain `supported`, the scalar rater-consistency GMFRM and fixed-Q
confirmatory MGMFRM paths to remain `experimental_public`, and broad
generalized fitting, DFF model effects, model-weight claims, sparse-superiority
claims, and post-v0.2.0 external-validation claims to remain blocked.

Set `throw_on_failure = true` for release scripts or CI steps that should fail
as soon as documentation and manifest status rows drift.
"""
function release_gate_check(; root::AbstractString = _release_gate_default_root(),
        throw_on_failure::Bool = false)
    normalized_root = normpath(root)
    scope = release_scope_summary(; include_evidence = true)
    document_rows = _release_gate_document_rows(normalized_root)
    manifest_rows = _release_gate_manifest_rows(scope)
    rows = (document_rows..., manifest_rows...)
    failed_rows = Tuple(row for row in rows if row.status !== :passed)
    passed = isempty(failed_rows)
    summary = (;
        passed,
        n_rows = length(rows),
        n_document_rows = length(document_rows),
        n_manifest_rows = length(manifest_rows),
        n_failed_rows = length(failed_rows),
        failed_targets = Tuple(row.target for row in failed_rows),
        broad_generalized_fit_allowed = scope.summary.broader_generalized_fit_allowed,
        dff_model_effects_allowed = scope.summary.dff_model_effects_allowed,
        model_weight_claims_allowed = scope.summary.model_weight_claims_allowed,
        sparse_superiority_claims_allowed =
            scope.summary.sparse_superiority_claims_allowed,
        publication_or_registration_action = false,
        next_gate = passed ? :manual_publication_or_registration_by_user_only :
            :repair_release_scope_documentation_or_manifest_drift,
    )
    result = (;
        schema = "bayesianmgmfrm.release_gate_check.v1",
        object = :release_gate_check,
        status = passed ? :passed : :failed,
        root = normalized_root,
        release_scope = scope,
        rows,
        summary,
    )
    if throw_on_failure && !passed
        throw(ArgumentError(
            "release gate failed with $(summary.n_failed_rows) failed row(s): " *
            join(string.(summary.failed_targets), ", ")))
    end
    return result
end

function _default_case_study_source_records()
    return (
        (;
            source_id = :writing_rater_mediated_slice,
            source_role = :real_data_case_study_input,
            family = :gmfrm,
            scope = :scalar_gmfrm_fit_ready_candidate,
            data_release = :not_public,
            license_status = :local_review_recorded_not_public_license,
            anonymization_status = :pseudonymized,
            direct_identifiers_removed = true,
            person_ids_pseudonymized = true,
            rater_ids_pseudonymized = true,
            archive_sync_required = true,
        ),
        (;
            source_id = :speaking_rater_mediated_slice,
            source_role = :real_data_case_study_input,
            family = :gmfrm,
            scope = :scalar_gmfrm_fit_ready_candidate,
            data_release = :not_public,
            license_status = :local_review_recorded_not_public_license,
            anonymization_status = :pseudonymized,
            direct_identifiers_removed = true,
            person_ids_pseudonymized = true,
            rater_ids_pseudonymized = true,
            archive_sync_required = true,
        ),
    )
end

function _default_case_study_archive_records()
    return (
        (;
            archive = :real_data_case_study,
            path = "test/fixtures/gmfrm_real_data_case_study.json",
            role = :case_study_evidence,
            publication_facing = false,
            requires_source_license_record = true,
            requires_anonymization_record = true,
            sync_status = :synchronized_by_manifest,
            publication_or_registration_action = false,
        ),
        (;
            archive = :claim_recovery_reproduction_archive,
            path = "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
            role = :claim_recovery_archive,
            publication_facing = false,
            requires_source_license_record = true,
            requires_anonymization_record = true,
            sync_status = :synchronized_by_manifest,
            publication_or_registration_action = false,
        ),
        (;
            archive = :manuscript_scale_simulation_grid,
            path = "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
            role = :gate_e_evidence_grid,
            publication_facing = true,
            requires_source_license_record = true,
            requires_anonymization_record = true,
            sync_status = :synchronized_by_manifest,
            publication_or_registration_action = false,
        ),
        (;
            archive = :full_paper_reproduction_archive,
            path = "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
            role = :full_local_reproduction_archive,
            publication_facing = true,
            requires_source_license_record = true,
            requires_anonymization_record = true,
            sync_status = :synchronized_by_manifest,
            publication_or_registration_action = false,
        ),
    )
end

function _case_study_record_tuple(records, name::Symbol)
    records isa NamedTuple && return (records,)
    records isa Tuple && (tupled = records)
    records isa AbstractVector && (tupled = Tuple(records))
    @isdefined(tupled) ||
        throw(ArgumentError("$name must be a NamedTuple, Tuple, or vector of NamedTuples"))
    isempty(tupled) && throw(ArgumentError("$name cannot be empty"))
    all(row -> row isa NamedTuple, tupled) ||
        throw(ArgumentError("$name must contain only NamedTuple rows"))
    return tupled
end

_case_study_nt_get(row::NamedTuple, key::Symbol, default) =
    haskey(row, key) ? getproperty(row, key) : default

function _case_study_required(row::NamedTuple, key::Symbol, name::Symbol)
    haskey(row, key) || throw(ArgumentError("$name row is missing required field $key"))
    return getproperty(row, key)
end

function _case_study_normalize_source(row::NamedTuple)
    source_id = _case_study_required(row, :source_id, :source_records)
    anonymization_status =
        _case_study_nt_get(row, :anonymization_status, :missing)
    license_status = _case_study_nt_get(row, :license_status, :missing)
    direct_identifiers_removed =
        _case_study_nt_get(row, :direct_identifiers_removed, false) === true
    anonymization_record_passed =
        direct_identifiers_removed &&
        anonymization_status in (:anonymized, :pseudonymized, :deidentified)
    license_record_declared =
        !(ismissing(license_status) || license_status === :missing)
    return merge(row, (;
        schema = "bayesianmgmfrm.case_study_source_provenance.v1",
        object = :case_study_source_provenance,
        source_id,
        anonymization_record_passed,
        license_record_declared,
        external_public_release_allowed =
            _case_study_nt_get(row, :external_public_release_allowed, false) === true,
        archive_sync_required =
            _case_study_nt_get(row, :archive_sync_required, true) === true,
    ))
end

function _case_study_normalize_archive(row::NamedTuple)
    archive = _case_study_required(row, :archive, :archive_records)
    sync_status = _case_study_nt_get(row, :sync_status, :missing)
    requires_source_license_record =
        _case_study_nt_get(row, :requires_source_license_record, true) === true
    requires_anonymization_record =
        _case_study_nt_get(row, :requires_anonymization_record, true) === true
    publication_facing =
        _case_study_nt_get(row, :publication_facing, false) === true
    publication_or_registration_action =
        _case_study_nt_get(row, :publication_or_registration_action, false) === true
    provenance_sync_passed =
        sync_status in (:synchronized, :synchronized_by_manifest) &&
        requires_source_license_record &&
        requires_anonymization_record &&
        !publication_or_registration_action
    return merge(row, (;
        schema = "bayesianmgmfrm.case_study_archive_sync.v1",
        object = :case_study_archive_sync,
        archive,
        publication_facing,
        requires_source_license_record,
        requires_anonymization_record,
        publication_or_registration_action,
        provenance_sync_passed,
    ))
end

"""
    case_study_provenance_manifest(; source_records = ..., archive_records = ...)

Return a machine-readable provenance manifest tying the compact real-data case
study source records to claim-level and publication-facing reproduction
archives. The default records cover the local guarded scalar GMFRM writing and
speaking rater-mediated slices and the current real-data, claim-recovery,
manuscript-scale, and full-paper archive artifacts.

The manifest checks only that licensing status and anonymization status are
declared and synchronized with archive records. It is not a data license grant,
IRB determination, publication action, registration action, or manuscript claim
approval.
"""
function case_study_provenance_manifest(;
        source_records = _default_case_study_source_records(),
        archive_records = _default_case_study_archive_records())
    sources = Tuple(_case_study_normalize_source(row)
        for row in _case_study_record_tuple(source_records, :source_records))
    archives = Tuple(_case_study_normalize_archive(row)
        for row in _case_study_record_tuple(archive_records, :archive_records))
    all_source_records_anonymized =
        all(row -> row.anonymization_record_passed, sources)
    all_license_records_declared =
        all(row -> row.license_record_declared, sources)
    all_archive_records_synchronized =
        all(row -> row.provenance_sync_passed, archives)
    publication_archives_synchronized =
        all(row -> !row.publication_facing || row.provenance_sync_passed, archives)
    no_public_source_release =
        all(row -> !row.external_public_release_allowed, sources)
    no_publication_actions =
        all(row -> !row.publication_or_registration_action, archives)
    passed = all_source_records_anonymized &&
        all_license_records_declared &&
        all_archive_records_synchronized &&
        publication_archives_synchronized &&
        no_publication_actions

    return (;
        schema = "bayesianmgmfrm.case_study_provenance_manifest.v1",
        object = :case_study_provenance_manifest,
        status = passed ? :synchronized : :incomplete,
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        source_records = sources,
        archive_records = archives,
        summary = (;
            passed,
            n_source_records = length(sources),
            n_archive_records = length(archives),
            n_publication_facing_archives =
                count(row -> row.publication_facing, archives),
            all_source_records_anonymized,
            all_license_records_declared,
            all_archive_records_synchronized,
            publication_archives_synchronized,
            no_public_source_release,
            no_publication_actions,
            license_grant = false,
            irb_determination = false,
            publication_or_registration_action = false,
            manuscript_claims_allowed = false,
            caveat = :provenance_manifest_not_license_irb_or_publication_approval,
            next_gate = :manual_publication_or_registration_by_user_only,
        ),
    )
end

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

function _check_dimensions(family::Symbol, dimensions::Int)
    dimensions >= 1 || throw(ArgumentError("dimensions must be positive"))
    family === :mfrm && dimensions == 1 ||
        family !== :mfrm ||
        throw(ArgumentError("family = :mfrm currently requires dimensions = 1"))
    family === :gmfrm && dimensions == 1 ||
        family !== :gmfrm ||
        throw(ArgumentError(
            "family = :gmfrm is one-dimensional; use family = :mgmfrm with " *
            "dimensions >= 2 and a fixed q_matrix for multidimensional models",
        ))
    family === :mgmfrm && dimensions >= 2 ||
        family !== :mgmfrm ||
        throw(ArgumentError("family = :mgmfrm requires dimensions >= 2"))
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

    family_applicability_status =
        family === :mgmfrm ? :applicable : :not_applicable
    family_applicability_severity =
        family === :mgmfrm || q_matrix === nothing ? :info : :error
    push!(rows, _q_matrix_validation_row(;
        check = :family_applicability,
        status = family_applicability_status,
        severity = family_applicability_severity,
        n_items = length(data.item_levels),
        n_dimensions = dimensions,
        note = family === :mgmfrm ?
            :q_matrix_required_for_mgmfrm :
            :q_matrix_only_applies_to_mgmfrm,
    ))
    if family !== :mgmfrm
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

    single_loading_missing = Int[]
    for dim in axes(mat, 2)
        has_single_loading_anchor =
            any(item -> mat[item, dim] && count(@view mat[item, :]) == 1, axes(mat, 1))
        has_single_loading_anchor || push!(single_loading_missing, dim)
    end
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

    passed = !any(row -> row.severity === :error, rows)
    return (;
        schema = "bayesianmgmfrm.q_matrix_validation.v1",
        object = :q_matrix_validation,
        family,
        dimensions,
        dimension_labels = copy(dimension_labels),
        cross_loading_policy,
        q_matrix = _q_matrix_manifest(mat),
        matrix = include_matrix ? mat : nothing,
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
cross-loading policy, simple loading anchors, and dimension-specific
person-rater-item subgraph coverage. Error rows make `passed = false`; warning
rows remain actionable review evidence without rejecting the fixed-Q spec.
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

function _q_matrix_guarded_structure_passed(validation)
    # Keep this as a small coverage denylist: every unclassified current or
    # future error remains blocking, so mutable Q inputs fail closed.
    return all(
        row -> row.severity !== :error ||
            row.check in _Q_MATRIX_OBSERVATION_COVERAGE_CHECKS,
        validation.rows,
    )
end

function _normalize_q_matrix(data::FacetData,
        family::Symbol,
        dimensions::Int,
        q_matrix,
        dimension_labels::Vector{String})
    if family !== :mgmfrm
        q_matrix === nothing || throw(ArgumentError("q_matrix is only accepted for family = :mgmfrm"))
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
            "invalid fixed-Q MGMFRM q_matrix; failing_checks=$(failing_checks); " *
            "inspect q_matrix_validation(...) for actionable rows",
        ))
    end
    return validation.matrix
end

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

function _estimation_status(family::Symbol,
        dimensions::Int,
        discrimination::Symbol,
        q_matrix,
        anchors)
    family === :mfrm &&
        dimensions == 1 &&
        discrimination === :none &&
        q_matrix === nothing &&
        isempty(anchors) &&
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

function _check_guarded_generalized_spec(
        spec::FacetSpec,
        caller::AbstractString;
        require_q_observation_coverage::Bool = true)
    capability = _guarded_generalized_fit_capability(spec.family)
    spec.dimensions >= capability.minimum_dimensions &&
        (capability.maximum_dimensions === nothing ||
            spec.dimensions <= capability.maximum_dimensions) ||
        throw(_guarded_generalized_unsupported_error(
            caller,
            spec.family,
            :dimensions,
            spec.dimensions,
            "the guarded surface has a family-specific dimensionality contract",
        ))
    spec.thresholds in capability.threshold_regimes ||
        throw(_guarded_generalized_unsupported_error(
            caller,
            spec.family,
            :thresholds,
            spec.thresholds,
            "the compiled generalized kernel uses $(capability.kernel_threshold_block); " *
            "unsupported threshold labels are not silently reinterpreted",
        ))
    spec.discrimination in capability.spec_discrimination ||
        throw(_guarded_generalized_unsupported_error(
            caller,
            spec.family,
            :discrimination,
            spec.discrimination,
            "the guarded surface requires its family-specific generic discrimination selector",
        ))
    if capability.requires_fixed_q
        spec.q_matrix === nothing &&
            throw(_guarded_generalized_unsupported_error(
                caller,
                spec.family,
                :q_matrix,
                nothing,
                "the guarded MGMFRM surface requires a fixed confirmatory q_matrix",
            ))
        q_validation = q_matrix_validation(spec)
        q_validation_passed = require_q_observation_coverage ?
            q_validation.passed :
            _q_matrix_guarded_structure_passed(q_validation)
        q_validation_passed ||
            throw(_guarded_generalized_unsupported_error(
                caller,
                spec.family,
                :q_matrix,
                spec.q_matrix,
                "the fixed q_matrix no longer passes confirmatory " *
                (require_q_observation_coverage ? "validation; " :
                    "structural validation; ") *
                "mutable specification inputs are revalidated before numerical execution",
            ))
    end
    !capability.allows_validation_bias_terms &&
        !isempty(spec.validation_bias_terms) &&
        throw(_guarded_generalized_unsupported_error(
            caller,
            spec.family,
            :dff_effects,
            spec.validation_bias_terms,
            "DFF/bias terms are validation and reporting rows only; they are not fitted model effects",
        ))
    !capability.allows_anchors && !isempty(spec.anchors) &&
        throw(_guarded_generalized_unsupported_error(
            caller,
            spec.family,
            :anchors,
            spec.anchors,
            "declared anchors are not yet applied by the generalized likelihood or raw-coordinate transform",
        ))
    spec.estimation_status === :specified_only ||
        throw(_guarded_generalized_unsupported_error(
            caller,
            spec.family,
            :estimation_status,
            spec.estimation_status,
            "guarded generalized fitting expects the specified-only manifest path",
        ))
    return capability
end

function _spec_scope(family::Symbol, status::Symbol)
    family === :mfrm && status === :fit_supported && return :minimal_mfrm_rsm_pcm
    family === :mfrm && return :planned_mfrm_variant
    family === :gmfrm && return :planned_generalized_mfrm
    family === :mgmfrm && return :planned_multidimensional_gmfrm
    return :unknown
end

function _equation_sources(family::Symbol, thresholds::Symbol)
    if family === :mfrm
        source = thresholds === :rating_scale ?
            "Uto and Ueno (2020), Eq. 6, with Andrich (1978) rating-scale lineage" :
            "Masters (1982) partial-credit model with Uto and Ueno (2020), Eq. 3, GPCM/PCM decomposition"
        return [source]
    elseif family === :gmfrm
        return ["Uto and Ueno (2020), Behaviormetrika 47, Eq. 9 and identification restrictions"]
    elseif family === :mgmfrm
        return ["Uto (2021), Behaviormetrika 48, Eq. 6 and identification restrictions"]
    end
    return String[]
end

function _equation_source_urls(family::Symbol, thresholds::Symbol)
    if family === :mfrm
        return thresholds === :partial_credit ?
            ["https://doi.org/10.1007/BF02296272", "https://doi.org/10.1007/s41237-020-00115-7"] :
            ["https://doi.org/10.1007/BF02293814", "https://doi.org/10.1007/s41237-020-00115-7"]
    elseif family === :gmfrm
        return ["https://doi.org/10.1007/s41237-020-00115-7"]
    elseif family === :mgmfrm
        return ["https://doi.org/10.1007/s41237-021-00144-w"]
    end
    return String[]
end

function _equation_kernel(spec::FacetSpec)
    if spec.family === :mfrm
        return spec.thresholds === :rating_scale ?
            "eta[k] = (k - 1) * (theta[p] - beta_r[r] - beta_i[i]) - sum_{m=1}^{k-1} d[m]" :
            "eta[k] = (k - 1) * (theta[p] - beta_r[r] - beta_i[i]) - sum_{m=1}^{k-1} d[i,m]"
    elseif spec.family === :gmfrm
        return "eta[k] = sum_{m=1}^{k} alpha_r[r] * alpha_i[i] * (theta[p] - beta_i[i] - beta_r[r] - d[r,m])"
    elseif spec.family === :mgmfrm
        return "eta[k] = sum_{m=1}^{k} 1.7 * alpha_r[r] * (sum_l alpha_i_l[i,l] * theta[p,l] - beta_i[i] - beta_r[r] - d[i,m])"
    end
    return ""
end

function _equation_required_blocks(spec::FacetSpec)
    if spec.family === :mfrm
        return (:person_location, :rater_severity, :item_difficulty, :threshold_steps)
    elseif spec.family === :gmfrm
        return (
            :person_location,
            :rater_severity,
            :item_difficulty,
            :item_discrimination,
            :rater_consistency,
            :rater_step,
        )
    elseif spec.family === :mgmfrm
        return (
            :person_location_by_dimension,
            :rater_severity,
            :item_difficulty,
            :item_dimension_discrimination,
            :rater_consistency,
            :item_step,
        )
    end
    return Symbol[]
end

function _equation_identification(spec::FacetSpec)
    if spec.family === :mfrm
        return (
            :location_constraint_on_rater_and_item_blocks,
            :threshold_sum_to_zero,
            :ability_location_scale_set_by_parameterization_or_prior,
        )
    elseif spec.family === :gmfrm
        return (
            :prod_item_discrimination_equals_one,
            :sum_item_difficulty_equals_zero,
            :rater_first_step_fixed_zero,
            :rater_step_sum_to_zero,
            :ability_distribution_sets_location_and_scale,
        )
    elseif spec.family === :mgmfrm
        return (
            :prod_rater_consistency_equals_one,
            :sum_rater_severity_equals_zero,
            :item_first_step_fixed_zero,
            :item_step_sum_to_zero,
            :standard_normal_ability_prior_by_dimension,
            :dimension_order_or_loading_gauge_required,
        )
    end
    return Symbol[]
end

function _equation_implementation_gaps(spec::FacetSpec)
    gaps = Symbol[]
    spec.family === :mfrm && return gaps
    if spec.family === :gmfrm
        append!(gaps, (
            :identified_transform_for_item_discrimination_product_constraint,
            :identified_transform_for_rater_step_constraints,
            :literature_gmfrm_likelihood_kernel,
            :source_matched_fixture_tests,
        ))
    elseif spec.family === :mgmfrm
        append!(gaps, (
            :identified_transform_for_rater_consistency_product_constraint,
            :identified_transform_for_item_step_constraints,
            :multidimensional_ability_prior_and_gauge,
            :literature_mgmfrm_likelihood_kernel,
            :source_matched_fixture_tests,
        ))
    end
    return gaps
end

"""
    model_equation(spec_or_design)

Return a source-traced mathematical contract for the specification. The result
records the intended likelihood family, a compact adjacent-category logit
kernel, primary-source references, required parameter blocks, identification
restrictions, and implementation gaps.

For specified-only GMFRM/MGMFRM specs this function deliberately reports the
missing blocks needed to match the literature equations; it does not enable
fitting.
"""
function model_equation(spec::FacetSpec)
    return (;
        schema = "bayesianmgmfrm.model_equation.v1",
        family = spec.family,
        scope = _spec_scope(spec.family, spec.estimation_status),
        thresholds = spec.thresholds,
        dimensions = spec.dimensions,
        dimension_labels = copy(spec.dimension_labels),
        discrimination = spec.discrimination,
        estimation_status = spec.estimation_status,
        probability_form = :adjacent_category_softmax,
        category_indexing = :internal_one_based_with_observed_integer_scores,
        kernel = _equation_kernel(spec),
        primary_sources = _equation_sources(spec.family, spec.thresholds),
        source_urls = _equation_source_urls(spec.family, spec.thresholds),
        required_blocks = _equation_required_blocks(spec),
        identification = _equation_identification(spec),
        implementation_gaps = _equation_implementation_gaps(spec),
        fit_ready = spec.estimation_status === :fit_supported &&
            isempty(_equation_implementation_gaps(spec)),
    )
end

model_equation(design::FacetDesign) = model_equation(design.spec)

function _constraint_rows(;
        family::Symbol,
        thresholds::Symbol,
        dimensions::Int,
        dimension_labels = _default_dimension_labels(dimensions),
        discrimination::Symbol,
        q_matrix,
        validation_bias_terms,
        anchors,
        estimation_status::Symbol)
    implemented = estimation_status === :fit_supported ? :implemented : :specified_only
    rows = NamedTuple[]
    if family === :mfrm
        append!(rows, NamedTuple[
            (;
                block = :person,
                constraint = dimensions == 1 ? :free : :latent_location_by_dimension,
                transform = :identity,
                status = implemented,
                note = "person latent location parameters",
            ),
            (;
                block = :rater,
                constraint = :reference_first,
                transform = :identity,
                status = implemented,
                note = "first rater severity fixed to zero",
            ),
            (;
                block = :item,
                constraint = :reference_first,
                transform = :identity,
                status = implemented,
                note = "first item difficulty fixed to zero",
            ),
            (;
                block = :thresholds,
                constraint = :sum_to_zero,
                transform = thresholds === :rating_scale ? :shared_steps : :item_steps,
                status = implemented,
                note = "last threshold step derived by a sum-to-zero constraint",
            ),
        ])
    elseif family === :gmfrm
        append!(rows, NamedTuple[
            (;
                block = :person,
                constraint = :ability_distribution_location_scale,
                transform = :identity,
                status = :specified_only,
                note = "person latent locations; ability distribution supplies location and scale in the source model",
            ),
            (;
                block = :rater,
                constraint = :free_given_item_location_constraint,
                transform = :identity,
                status = :specified_only,
                note = "rater severity beta_r in Uto and Ueno (2020), Eq. 9",
            ),
            (;
                block = :item,
                constraint = :sum_to_zero,
                transform = :identity,
                status = :specified_only,
                note = "item/task difficulty beta_i with sum_i beta_i = 0",
            ),
            (;
                block = :item_discrimination,
                constraint = :geometric_mean_one,
                transform = :log_link,
                status = :specified_only,
                note = "positive item/task discrimination alpha_i with product_i alpha_i = 1",
            ),
            (;
                block = :rater_consistency,
                constraint = :positive,
                transform = :log_link,
                status = :specified_only,
                note = "positive rater consistency alpha_r",
            ),
            (;
                block = :rater_steps,
                constraint = :first_step_zero_sum_to_zero,
                transform = :rater_category_steps,
                status = :specified_only,
                note = "rater-specific category-use steps d_rm with d_r1 = 0 and sum_{m=2}^K d_rm = 0",
            ),
        ])
    elseif family === :mgmfrm
        append!(rows, NamedTuple[
            (;
                block = :person,
                constraint = :standard_normal_by_dimension,
                transform = :identity,
                status = :specified_only,
                dimension_labels = Tuple(dimension_labels),
                note = "multidimensional person locations theta_jl with source-model standard normal ability prior",
            ),
            (;
                block = :rater,
                constraint = :sum_to_zero,
                transform = :identity,
                status = :specified_only,
                note = "rater severity beta_r with sum_r beta_r = 0",
            ),
            (;
                block = :item,
                constraint = :free_given_ability_and_rater_constraints,
                transform = :identity,
                status = :specified_only,
                note = "item/evaluation difficulty beta_i in Uto (2021), Eq. 6",
            ),
            (;
                block = :item_dimension_discrimination,
                constraint = :confirmatory_q_mask,
                transform = :log_link,
                status = :specified_only,
                dimension_labels = Tuple(dimension_labels),
                note = "positive item-by-dimension discrimination alpha_il under the fixed Q-mask",
            ),
            (;
                block = :rater_consistency,
                constraint = :geometric_mean_one,
                transform = :log_link,
                status = :specified_only,
                note = "positive rater consistency alpha_r with product_r alpha_r = 1",
            ),
            (;
                block = :item_steps,
                constraint = :first_step_zero_sum_to_zero,
                transform = :item_category_steps,
                status = :specified_only,
                note = "item-specific category-use steps d_im with d_i1 = 0 and sum_{m=2}^K d_im = 0",
            ),
        ])
    end
    if family === :mgmfrm
        q_matrix === nothing || push!(rows, (;
            block = :q_matrix,
            constraint = :fixed_mask,
            transform = :none,
            status = :specified_only,
            dimension_labels = Tuple(dimension_labels),
            note = "fixed $(size(q_matrix, 1)) by $(size(q_matrix, 2)) item-dimension mask",
        ))
    end
    for term in validation_bias_terms
        push!(rows, (;
            block = Symbol("dff_", term[1], "_", term[2]),
            constraint = :validation_only,
            transform = :none,
            status = :validation_only,
            note = "DFF/bias term validated for sparse cells but not included in the fitted likelihood",
        ))
    end
    for anchor in anchors
        anchor_type = haskey(anchor, :anchor_type) ? anchor.anchor_type : _normalize_anchor_type(anchor)
        anchor_scale = haskey(anchor, :anchor_scale) ? anchor.anchor_scale : _anchor_scale(anchor)
        push!(rows, (;
            block = anchor.block,
            constraint = anchor_type,
            transform = anchor_type === :soft_anchor ? :soft_anchor_prior : :fixed_value,
            status = :specified_only,
            anchor_value = anchor.value,
            anchor_scale,
            note = anchor_type === :soft_anchor ?
                "soft anchor declared in specification; fitting support is planned" :
                "hard anchor declared in specification; fitting support is planned",
        ))
    end
    return rows
end

function _prior_rows(family::Symbol, dimensions::Int, discrimination::Symbol)
    rows = NamedTuple[
        (block = :person, prior = :normal, parameters = (location = 0.0, scale = :person_sd), status = :implemented),
        (block = :rater, prior = :normal, parameters = (location = 0.0, scale = :rater_sd), status = :implemented),
        (block = :item, prior = :normal, parameters = (location = 0.0, scale = :item_sd), status = :implemented),
        (block = :thresholds, prior = :normal, parameters = (location = 0.0, scale = :step_sd), status = :implemented),
    ]
    if family === :gmfrm
        push!(rows,
            (block = :item_discrimination, prior = :lognormal_or_hierarchical, parameters = (center = 1.0,), status = :specified_only),
            (block = :rater_consistency, prior = :lognormal_or_hierarchical, parameters = (center = 1.0,), status = :specified_only),
            (block = :rater_steps, prior = :normal, parameters = (location = 0.0, scale = :step_sd), status = :specified_only))
    elseif family === :mgmfrm
        push!(rows,
            (block = :item_dimension_discrimination, prior = :lognormal_or_hierarchical, parameters = (center = 1.0,), status = :specified_only),
            (block = :rater_consistency, prior = :lognormal_or_hierarchical, parameters = (center = 1.0,), status = :specified_only),
            (block = :item_steps, prior = :normal, parameters = (location = 0.0, scale = :step_sd), status = :specified_only))
    end
    return rows
end

"""
    mfrm_spec(data::FacetData; thresholds = :partial_credit,
              family = :mfrm, dimensions = 1, discrimination = :none,
              q_matrix = nothing, dimension_labels = nothing,
              bias = Tuple{Symbol,Symbol}[], anchors = NamedTuple[], min_cell_count = 2,
              validation_report = nothing)

Construct a many-facet measurement specification after validation errors are
resolved. The default `family = :mfrm`, `dimensions = 1`, and
`discrimination = :none` path is the minimal MFRM/RSM/PCM slice supported by
`getdesign` and `fit`. GMFRM/MGMFRM configurations can be represented for
manifest and constraint review with `estimation_status = :specified_only`.
The guarded generalized numerical path is narrower than this representation
surface: it requires `thresholds = :partial_credit`, no anchors or fitted DFF
terms, and the family-specific discrimination/Q contract documented by
[`fit`](@ref). Other specified-only configurations remain inspection-only and
are rejected before numerical evaluation.
"""
function mfrm_spec(data::FacetData;
        thresholds::Symbol = :partial_credit,
        family::Symbol = :mfrm,
        dimensions::Int = 1,
        discrimination::Symbol = :none,
        q_matrix = nothing,
        dimension_labels = nothing,
        bias = Tuple{Symbol,Symbol}[],
        anchors = NamedTuple[],
        min_cell_count::Int = 2,
        validation_report::Union{Nothing,ValidationReport} = nothing)
    thresholds in (:rating_scale, :partial_credit) ||
        throw(ArgumentError("thresholds must be :rating_scale or :partial_credit"))
    checked_family = _check_family(family)
    checked_dimensions = _check_dimensions(checked_family, dimensions)
    checked_dimension_labels =
        _normalize_dimension_labels(checked_dimensions, dimension_labels)
    checked_discrimination = _check_discrimination(checked_family, discrimination)
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
    checked_q_matrix = _normalize_q_matrix(
        data,
        checked_family,
        checked_dimensions,
        q_matrix,
        checked_dimension_labels,
    )
    checked_bias_terms = _normalize_bias_terms(bias, report)
    checked_anchors = _normalize_anchors(anchors)
    estimation_status = _estimation_status(
        checked_family,
        checked_dimensions,
        checked_discrimination,
        checked_q_matrix,
        checked_anchors,
    )
    constraints = _constraint_rows(;
        family = checked_family,
        thresholds,
        dimensions = checked_dimensions,
        dimension_labels = checked_dimension_labels,
        discrimination = checked_discrimination,
        q_matrix = checked_q_matrix,
        validation_bias_terms = checked_bias_terms,
        anchors = checked_anchors,
        estimation_status,
    )
    prior_blocks = _prior_rows(checked_family, checked_dimensions, checked_discrimination)
    return FacetSpec(
        data,
        thresholds,
        report,
        checked_family,
        checked_dimensions,
        checked_dimension_labels,
        checked_discrimination,
        checked_q_matrix,
        checked_bias_terms,
        checked_anchors,
        constraints,
        prior_blocks,
        estimation_status,
    )
end

function Base.show(io::IO, spec::FacetSpec)
    print(io, "FacetSpec(family = :", spec.family,
        ", thresholds = :", spec.thresholds,
        ", dimensions = ", spec.dimensions,
        ", estimation_status = :", spec.estimation_status,
        ", ", spec.data, ")")
end

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
    _push_block!(names, blocks, :rater, data.rater_levels[2:end], "rater")
    _push_block!(names, blocks, :item, data.item_levels[2:end], "item")
    _push_named_block!(names, blocks, :thresholds, _threshold_parameter_names(spec))

    identification = Dict{Symbol,Symbol}(
        :person => :free,
        :rater => :reference_first,
        :item => :reference_first,
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

Return the current minimal additive RSM/PCM design scaffold. The first rater
and first item levels are fixed to zero as reference levels. Rating-scale and
partial-credit threshold steps are represented with a sum-to-zero constraint.

Specified-only GMFRM/MGMFRM configurations are rejected by default so fitting
code cannot silently use an unsupported likelihood. Set `preview = true` to
compile an inspectable, non-fit-ready parameter blueprint for specified-only
configurations.
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
rows explain the planned constraint/gauge rather than pretending the likelihood
is fit-ready. For a compiled `FacetDesign`, implemented rows also include
parameter ranges and names.
"""
function constraint_table(spec::FacetSpec)
    return copy(spec.constraints)
end

function constraint_table(design::FacetDesign)
    base_rows = constraint_table(design.spec)
    rows = NamedTuple[]
    for row in base_rows
        if haskey(design.blocks, row.block)
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
            anchor_value = row.anchor_value,
            anchor_scale = row.anchor_scale,
        ))
    end
    return base
end

function _attach_design_parameter_metadata(row, design::FacetDesign)
    if haskey(design.blocks, row.block)
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
    return [_identification_declaration_row(spec, row) for row in constraint_table(spec)]
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
    data = design.spec.data
    person_indices = _person_parameter_indices(design, data.person[row])
    rater_parameter_index = _facet_parameter_index(design.blocks[:rater], data.rater[row], length(data.rater_levels))
    item_parameter_index = _facet_parameter_index(design.blocks[:item], data.item[row], length(data.item_levels))
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
        item_index = data.item[row],
        item = data.item_levels[data.item[row]],
        item_parameter_index,
        item_parameter_name = _reference_parameter_name(design, item_parameter_index),
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
    rater_block = design.blocks[:rater]
    item_block = design.blocks[:item]
    person_value = params[person_block[data.person[row]]]
    rater_value = _reference_value(params, rater_block, data.rater[row])
    item_value = _reference_value(params, item_block, data.item[row])
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
GMFRM/MGMFRM previews. Those models still require fixture-backed identified
transforms and a public generalized likelihood interface before fitting or
numeric likelihood evaluation is exposed.
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

function _gmfrm_source_fixture_constraints(design::FacetDesign, params::AbstractVector)
    data = design.spec.data
    item_values = params[design.blocks[:item]]
    item_discriminations = params[design.blocks[:item_discrimination]]
    rater_consistencies = params[design.blocks[:rater_consistency]]
    _check_approx_constraint("sum(item difficulty)", sum(item_values), _param_zero(params))
    _check_positive_constraint("item discrimination", item_discriminations)
    _check_approx_constraint("prod(item discrimination)", prod(item_discriminations), one(prod(item_discriminations)))
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
        raw_params::AbstractVector)
    blueprint = _mgmfrm_source_unconstrained_blueprint(design)
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
    _check_approx_constraint("prod(rater consistency)", prod(rater_consistencies), one(prod(rater_consistencies)))
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
        index_by_name,
        params::AbstractVector,
        row::Int)
    data = design.spec.data
    K = length(data.category_levels)
    length(etas) == K ||
        throw(ArgumentError("eta vector has length $(length(etas)); expected $K"))
    terms = _mgmfrm_source_row_terms(design, index_by_name, params, row)
    etas[1] = zero(terms.scale_value * terms.location_value)
    cumulative = zero(etas[1])
    item_index = data.item[row]
    for category_index in 2:K
        step_value = _source_step_value(design, params, :item_steps, item_index, category_index)
        cumulative += terms.scale_value * (terms.location_value - step_value)
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
    _check_parameter_vector_length(design, params)
    _mgmfrm_source_fixture_constraints(design, params)
    data = design.spec.data
    K = length(data.category_levels)
    T = typeof(_param_zero(params) + 0.0)
    etas = Vector{T}(undef, K)
    out = Vector{T}(undef, data.n)
    index_by_name = _parameter_index_map(design)
    for row in 1:data.n
        _mgmfrm_source_linear_predictors!(etas, design, index_by_name, params, row)
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
        raw_params::AbstractVector)
    pointwise = _mgmfrm_source_pointwise_loglikelihood_from_unconstrained(design, raw_params)
    return sum(pointwise; init = _param_zero(pointwise))
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
    rows = NamedTuple[]
    for row in 1:data.n
        _mgmfrm_source_linear_predictors!(etas, design, index_by_name, params, row)
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

"""
    design_row_table(spec_or_design; preview = false)

Return one row of machine-readable design metadata per observed rating. The
table records the facet level indexes and labels, identified parameter indexes
and names touched by the row, the source-step path up to the observed category,
and preview-only generalized blocks such as item discrimination,
item-dimension discrimination, and rater consistency when a specified-only
GMFRM/MGMFRM design is compiled with `preview = true`.

For a `FacetSpec`, specified-only GMFRM/MGMFRM configurations are rejected
unless `preview = true`, matching [`getdesign`](@ref). The returned table is a
compiler inspection aid; it does not make specified-only likelihoods fit-ready.
"""
function design_row_table(spec::FacetSpec; preview::Bool = false)
    return design_row_table(getdesign(spec; preview))
end

function design_row_table(design::FacetDesign; preview::Bool = false)
    preview &&
        throw(ArgumentError("preview is only a FacetSpec compilation option; pass design_row_table(spec; preview = true) for specified-only specs"))
    data = design.spec.data
    index_by_name = _parameter_index_map(design)
    rows = NamedTuple[]
    for row in 1:data.n
        components = _predictor_components(design, index_by_name, row, data.category[row])
        push!(rows, (;
            row,
            score = data.score[row],
            category_index = data.category[row],
            category = data.category_levels[data.category[row]],
            person_index = data.person[row],
            person = data.person_levels[data.person[row]],
            person_parameter_indices = components.person_parameter_indices,
            person_parameter_names = components.person_parameter_names,
            rater_index = data.rater[row],
            rater = data.rater_levels[data.rater[row]],
            rater_parameter_index = components.rater_parameter_index,
            rater_parameter_name = components.rater_parameter_name,
            item_index = data.item[row],
            item = data.item_levels[data.item[row]],
            item_parameter_index = components.item_parameter_index,
            item_parameter_name = components.item_parameter_name,
            item_discrimination_parameter_index = components.item_discrimination_parameter_index,
            item_discrimination_parameter_name = components.item_discrimination_parameter_name,
            threshold_path = components.step_path,
            threshold_parameter_indices = components.step_parameter_indices,
            threshold_parameter_names = components.step_parameter_names,
            threshold_statuses = components.step_statuses,
            threshold_blocks = components.step_blocks,
            loading_dimensions = _loading_dimensions(design.spec, data.item[row]),
            loading_parameter_indices = components.item_dimension_discrimination_parameter_indices,
            loading_parameter_names = components.item_dimension_discrimination_parameter_names,
            item_dimension_discrimination_parameter_indices = components.item_dimension_discrimination_parameter_indices,
            item_dimension_discrimination_parameter_names = components.item_dimension_discrimination_parameter_names,
            rater_consistency_parameter_index = components.rater_consistency_parameter_index,
            rater_consistency_parameter_name = components.rater_consistency_parameter_name,
            discrimination_parameter_indices = components.discrimination_parameter_indices,
            discrimination_parameter_names = components.discrimination_parameter_names,
        ))
    end
    return rows
end

function _namedtuple_from_pairs(pairs)
    isempty(pairs) && return NamedTuple{()}(())
    names = Tuple(first(pair) for pair in pairs)
    values = Tuple(last(pair) for pair in pairs)
    return NamedTuple{names}(values)
end

function _optional_levels_manifest(data::FacetData)
    pairs = Pair{Symbol,Any}[]
    for role in sort(collect(keys(data.optional_levels)); by = string)
        push!(pairs, role => copy(data.optional_levels[role]))
    end
    return _namedtuple_from_pairs(pairs)
end

function _optional_columns_manifest(data::FacetData)
    pairs = Pair{Symbol,Any}[]
    for role in sort(collect(keys(data.columns.optional)); by = string)
        push!(pairs, role => data.columns.optional[role])
    end
    return _namedtuple_from_pairs(pairs)
end

function _data_manifest(data::FacetData)
    return (;
        n_observations = data.n,
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        n_categories = length(data.category_levels),
        columns = (;
            person = data.columns.person,
            rater = data.columns.rater,
            item = data.columns.item,
            score = data.columns.score,
            optional = _optional_columns_manifest(data),
            missing_policy = data.columns.missing_policy,
        ),
        levels = (;
            person = copy(data.person_levels),
            rater = copy(data.rater_levels),
            item = copy(data.item_levels),
            category = copy(data.category_levels),
            optional = _optional_levels_manifest(data),
        ),
        optional_facets = sort(collect(keys(data.optional)); by = string),
        data_signature = _data_signature(data),
    )
end

function _issue_count_rows(report::ValidationReport)
    codes = sort(unique(issue.code for issue in report.issues); by = string)
    return [(; code, count = count(issue -> issue.code === code, report.issues)) for code in codes]
end

function _validation_manifest(report::ValidationReport)
    return (;
        passed = report.passed,
        n_issues = length(report.issues),
        n_errors = count(issue -> issue.severity === :error, report.issues),
        n_warnings = count(issue -> issue.severity === :warning, report.issues),
        issue_counts = _issue_count_rows(report),
        issues = [(;
            code = issue.code,
            severity = issue.severity,
            message = issue.message,
            context = copy(issue.context),
        ) for issue in report.issues],
        suggestions = validation_suggestions(report),
        data_signature = report.data_signature,
        options_signature = report.options_signature,
    )
end

function _q_matrix_manifest(q_matrix::Union{Nothing,Matrix{Bool}})
    q_matrix === nothing && return nothing
    return [q_matrix[row, col] for row in axes(q_matrix, 1), col in axes(q_matrix, 2)]
end

function _spec_manifest(spec::FacetSpec)
    return (;
        family = spec.family,
        scope = _spec_scope(spec.family, spec.estimation_status),
        thresholds = spec.thresholds,
        dimensions = spec.dimensions,
        dimension_labels = copy(spec.dimension_labels),
        discrimination = spec.discrimination,
        q_matrix = _q_matrix_manifest(spec.q_matrix),
        q_matrix_validation = q_matrix_validation(spec),
        validation_bias_terms = copy(spec.validation_bias_terms),
        anchors = copy(spec.anchors),
        estimation_status = spec.estimation_status,
        status_policy = _status_policy_manifest(
            spec.family,
            spec.estimation_status;
            public_fit = spec.estimation_status === :fit_supported,
            experimental_public = false,
            fit_ready = spec.estimation_status === :fit_supported,
            claim_scope = _spec_scope(spec.family, spec.estimation_status),
        ),
        required_facets = (:person, :rater, :item),
        optional_facets = sort(collect(keys(spec.data.optional)); by = string),
        equation = model_equation(spec),
        identification_declarations = identification_declarations(spec),
        constraints = constraint_table(spec),
        model_surface_audit = model_surface_audit(spec),
        prior_blocks = copy(spec.prior_blocks),
    )
end

function _design_block_rows(design::FacetDesign)
    rows = NamedTuple[]
    for block in sort(collect(keys(design.blocks)); by = string)
        range = design.blocks[block]
        indices = collect(range)
        names = isempty(indices) ? String[] : design.parameter_names[indices]
        push!(rows, (;
            block,
            first_parameter = isempty(indices) ? missing : first(indices),
            last_parameter = isempty(indices) ? missing : last(indices),
            n_parameters = length(indices),
            parameter_names = copy(names),
            identification = design.identification[block],
        ))
    end
    return rows
end

function _block_manifest_rows(blocks::Dict{Symbol,UnitRange{Int}}, parameter_names::Vector{String})
    rows = NamedTuple[]
    for block in sort(collect(keys(blocks)); by = string)
        range = blocks[block]
        indices = collect(range)
        push!(rows, (;
            block,
            first_parameter = isempty(indices) ? missing : first(indices),
            last_parameter = isempty(indices) ? missing : last(indices),
            n_parameters = length(indices),
            parameter_names = isempty(indices) ? String[] : copy(parameter_names[indices]),
        ))
    end
    return rows
end

function _direct_identity_transform_rows(design::FacetDesign)
    rows = NamedTuple[]
    for block in sort(collect(keys(design.blocks)); by = string)
        range = design.blocks[block]
        indices = collect(range)
        names = isempty(indices) ? String[] : copy(design.parameter_names[indices])
        push!(rows, (;
            raw_block = block,
            constrained_block = block,
            transform = :identity,
            constraint = design.identification[block],
            status = design.spec.estimation_status,
            raw_first_parameter = isempty(indices) ? missing : first(indices),
            raw_last_parameter = isempty(indices) ? missing : last(indices),
            raw_n_parameters = length(indices),
            raw_parameter_names = copy(names),
            constrained_first_parameter = isempty(indices) ? missing : first(indices),
            constrained_last_parameter = isempty(indices) ? missing : last(indices),
            constrained_n_parameters = length(indices),
            constrained_parameter_names = copy(names),
            jacobian_policy = :identity,
        ))
    end
    return rows
end

function _mfrm_fit_ready_parameter_layout(design::FacetDesign)
    design.spec.family === :mfrm &&
        design.spec.estimation_status === :fit_supported ||
        throw(ArgumentError("fit-ready MFRM parameter layout requires a fit-supported MFRM/RSM/PCM design"))
    block_rows = _block_manifest_rows(design.blocks, design.parameter_names)
    return (;
        schema = "bayesianmgmfrm.fit_ready_parameter_layout.v1",
        family = :mfrm,
        scope = _spec_scope(design.spec.family, design.spec.estimation_status),
        status = :fit_supported,
        compiler_stage = :fit_supported_design,
        likelihood = :mfrm_rsm_pcm,
        fit_ready = true,
        public_fit = true,
        experimental_public = false,
        density_space = :constrained_direct,
        parameterization = :direct,
        n_parameters = length(design.parameter_names),
        parameter_names = copy(design.parameter_names),
        blocks = block_rows,
        n_raw_parameters = length(design.parameter_names),
        raw_parameter_names = copy(design.parameter_names),
        raw_blocks = copy(block_rows),
        n_constrained_parameters = length(design.parameter_names),
        constrained_parameter_names = copy(design.parameter_names),
        constrained_blocks = copy(block_rows),
        transforms = _direct_identity_transform_rows(design),
        constraints = constraint_table(design),
        identification_declarations = identification_declarations(design),
    )
end

function _generalized_fit_ready_parameter_layout(design::FacetDesign, blueprint)
    transforms = _source_transform_manifest_rows(blueprint)
    raw_blocks = _block_manifest_rows(blueprint.blocks, blueprint.parameter_names)
    constrained_blocks = _block_manifest_rows(
        blueprint.constrained_blocks,
        blueprint.constrained_parameter_names,
    )
    likelihood = design.spec.family === :gmfrm ?
        :scalar_gmfrm_source_aligned :
        :confirmatory_mgmfrm_source_aligned
    return (;
        schema = "bayesianmgmfrm.fit_ready_parameter_layout.v1",
        family = design.spec.family,
        scope = blueprint.scope,
        status = blueprint.status,
        compiler_stage = blueprint.compiler_stage,
        likelihood,
        fit_ready = blueprint.fit_ready,
        public_fit = false,
        experimental_public = design.spec.family in (:gmfrm, :mgmfrm),
        density_space = :raw_unconstrained,
        parameterization = :raw_to_constrained,
        n_parameters = blueprint.n_parameters,
        parameter_names = copy(blueprint.parameter_names),
        blocks = raw_blocks,
        n_raw_parameters = blueprint.n_parameters,
        raw_parameter_names = copy(blueprint.parameter_names),
        raw_blocks,
        n_constrained_parameters = length(blueprint.constrained_parameter_names),
        constrained_parameter_names = copy(blueprint.constrained_parameter_names),
        constrained_blocks,
        transforms,
        constraints = _fit_ready_candidate_constraint_rows(blueprint),
        identification_declarations = identification_declarations(design),
    )
end

"""
    fit_ready_parameter_layout(spec_or_design; preview = false)

Return deterministic parameter names and block ranges for each compiled
likelihood layout currently represented by the package. The fit-supported
MFRM/RSM/PCM path reports direct parameter blocks. Specified-only GMFRM/MGMFRM
preview designs report experimental raw and constrained fit-ready blocks,
including raw-to-constrained transform rows, without enabling broad public
generalized fitting.

For specified-only `FacetSpec` values, pass `preview = true`, matching
[`getdesign`](@ref).
"""
function fit_ready_parameter_layout(spec::FacetSpec; preview::Bool = false)
    return fit_ready_parameter_layout(getdesign(spec; preview))
end

function fit_ready_parameter_layout(design::FacetDesign; preview::Bool = false)
    preview &&
        throw(ArgumentError("preview is only a FacetSpec compilation option; pass fit_ready_parameter_layout(spec; preview = true)"))
    if design.spec.family === :mfrm && design.spec.estimation_status === :fit_supported
        return _mfrm_fit_ready_parameter_layout(design)
    elseif design.spec.family === :gmfrm && design.spec.estimation_status === :specified_only
        blueprint = _gmfrm_fit_ready_candidate_blueprint(design)
        return _generalized_fit_ready_parameter_layout(design, blueprint)
    elseif design.spec.family === :mgmfrm && design.spec.estimation_status === :specified_only
        blueprint = _mgmfrm_fit_ready_candidate_blueprint(design)
        return _generalized_fit_ready_parameter_layout(design, blueprint)
    end
    throw(ArgumentError(
        "fit_ready_parameter_layout currently supports fit-supported MFRM/RSM/PCM " *
        "designs and specified-only GMFRM/MGMFRM preview designs",
    ))
end

function _specified_only_preview_parameter_layout(design::FacetDesign)
    block_rows = _block_manifest_rows(design.blocks, design.parameter_names)
    return (;
        schema = "bayesianmgmfrm.fit_ready_parameter_layout.v1",
        family = design.spec.family,
        scope = _spec_scope(design.spec.family, design.spec.estimation_status),
        status = design.spec.estimation_status,
        compiler_stage = :specified_only_preview,
        likelihood = :not_fit_ready,
        fit_ready = false,
        public_fit = false,
        experimental_public = false,
        density_space = :not_fit_ready,
        parameterization = :direct_preview,
        n_parameters = length(design.parameter_names),
        parameter_names = copy(design.parameter_names),
        blocks = block_rows,
        n_raw_parameters = length(design.parameter_names),
        raw_parameter_names = copy(design.parameter_names),
        raw_blocks = copy(block_rows),
        n_constrained_parameters = length(design.parameter_names),
        constrained_parameter_names = copy(design.parameter_names),
        constrained_blocks = copy(block_rows),
        transforms = _direct_identity_transform_rows(design),
        constraints = constraint_table(design),
        identification_declarations = identification_declarations(design),
    )
end

function _domain_compilation_layout(design::FacetDesign)
    try
        return fit_ready_parameter_layout(design)
    catch err
        err isa ArgumentError || rethrow()
        design.spec.family === :mfrm &&
            design.spec.estimation_status === :specified_only ||
            rethrow()
        return _specified_only_preview_parameter_layout(design)
    end
end

_domain_nt_get(row::NamedTuple, key::Symbol, default) =
    haskey(row, key) ? getproperty(row, key) : default

function _domain_constraint_row(design::FacetDesign, block)
    ismissing(block) && return nothing
    for row in constraint_table(design)
        row.block === block && return row
    end
    return nothing
end

function _domain_prior_row(spec::FacetSpec, block)
    ismissing(block) && return nothing
    for row in spec.prior_blocks
        row.block === block && return row
    end
    return nothing
end

function _domain_transform_row(layout, block)
    ismissing(block) && return nothing
    for row in layout.transforms
        row.constrained_block === block && return row
    end
    return nothing
end

function _domain_block_row(rows, block)
    ismissing(block) && return nothing
    for row in rows
        row.block === block && return row
    end
    return nothing
end

function _domain_option_value(spec::FacetSpec, option::Symbol)
    option === :family && return spec.family
    option === :thresholds && return spec.thresholds
    option === :dimensions && return spec.dimensions
    option === :discrimination && return spec.discrimination
    option === :q_matrix && return _q_matrix_manifest(spec.q_matrix)
    option === :bias && return copy(spec.validation_bias_terms)
    option === :anchors && return copy(spec.anchors)
    option === :validation && return spec.validation.options_signature
    return missing
end

function _domain_option_for_block(spec::FacetSpec, block::Symbol)
    block === :person && return :dimensions
    block in (:rater, :item) && return :family
    block in (:thresholds, :rater_steps, :item_steps) && return :thresholds
    block in (:discrimination, :item_discrimination, :rater_consistency) &&
        return :discrimination
    block === :item_dimension_discrimination && return :q_matrix
    return :family
end

function _domain_role_for_block(block::Symbol)
    block in (:person, :rater, :item) && return :additive_block
    block in (:thresholds, :rater_steps, :item_steps) && return :scoring_block
    block === :item_dimension_discrimination && return :loading_block
    block in (:discrimination, :item_discrimination, :rater_consistency) &&
        return :discrimination_block
    return :parameter_block
end

function _domain_scoring_block(spec::FacetSpec)
    spec.family === :gmfrm && return :rater_steps
    spec.family === :mgmfrm && return :item_steps
    return :thresholds
end

function _domain_row(spec::FacetSpec,
        layout;
        domain_option::Symbol,
        option_value = _domain_option_value(spec, domain_option),
        compiled_role::Symbol,
        block = missing,
        raw_block = missing,
        constrained_block = block,
        parameter_names = String[],
        raw_parameter_names = String[],
        constraint = missing,
        transform = missing,
        prior_block = missing,
        prior = missing,
        scoring_vector = Int[],
        loading_mask = nothing,
        validation_requirement = missing,
        status = layout.status,
        note = "")
    return (;
        family = spec.family,
        scope = layout.scope,
        estimation_status = spec.estimation_status,
        compiler_stage = layout.compiler_stage,
        density_space = layout.density_space,
        parameterization = layout.parameterization,
        fit_ready = layout.fit_ready,
        public_fit = layout.public_fit,
        experimental_public = layout.experimental_public,
        domain_option,
        option_value,
        compiled_role,
        block,
        raw_block,
        constrained_block,
        parameter_names = copy(parameter_names),
        raw_parameter_names = copy(raw_parameter_names),
        constraint,
        transform,
        prior_block,
        prior,
        scoring_vector = copy(scoring_vector),
        loading_mask,
        validation_requirement,
        status,
        note,
    )
end

function _domain_block_summary_row(spec::FacetSpec,
        design::FacetDesign,
        layout,
        block::Symbol)
    constrained = _domain_block_row(layout.constrained_blocks, block)
    transform = _domain_transform_row(layout, block)
    constraint = _domain_constraint_row(design, block)
    prior = _domain_prior_row(spec, block)
    domain_option = _domain_option_for_block(spec, block)
    parameter_names = constrained === nothing ? String[] : constrained.parameter_names
    raw_block = transform === nothing ? block : transform.raw_block
    raw_names = transform === nothing ? String[] : transform.raw_parameter_names
    return _domain_row(spec, layout;
        domain_option,
        compiled_role = _domain_role_for_block(block),
        block,
        raw_block,
        constrained_block = block,
        parameter_names,
        raw_parameter_names = raw_names,
        constraint = constraint === nothing ? missing : constraint.constraint,
        transform = transform === nothing ? missing : transform.transform,
        prior_block = transform === nothing ?
            (prior === nothing ? missing : prior.block) :
            _domain_nt_get(transform, :prior_block,
                prior === nothing ? missing : prior.block),
        prior = prior === nothing ? missing : prior.prior,
        validation_requirement = :parameter_block_compiled,
        status = constraint === nothing ? layout.status : constraint.status,
        note = constraint === nothing ? "" : constraint.note,
    )
end

function _domain_validation_requirement_rows(spec::FacetSpec, layout)
    rows = NamedTuple[]
    summary = _validation_summary(spec.validation)
    push!(rows, _domain_row(spec, layout;
        domain_option = :validation,
        option_value = summary,
        compiled_role = :validation_requirement,
        validation_requirement = :validated_facet_design,
        status = spec.validation.passed ? :passed : :failed,
        note = "validation report attached to the compiled specification",
    ))
    for term in spec.validation_bias_terms
        block = Symbol("dff_", term[1], "_", term[2])
        push!(rows, _domain_row(spec, layout;
            domain_option = :bias,
            option_value = term,
            compiled_role = :validation_requirement,
            block,
            constrained_block = block,
            constraint = :validation_only,
            transform = :none,
            validation_requirement = :dff_cell_counts,
            status = :validation_only,
            note = "DFF/bias term validated for sparse cells but not included in the fitted likelihood",
        ))
    end
    for anchor in spec.anchors
        anchor_type = haskey(anchor, :anchor_type) ? anchor.anchor_type : _normalize_anchor_type(anchor)
        anchor_scale = haskey(anchor, :anchor_scale) ? anchor.anchor_scale : _anchor_scale(anchor)
        push!(rows, _domain_row(spec, layout;
            domain_option = :anchors,
            option_value = anchor,
            compiled_role = :constraint,
            block = anchor.block,
            constrained_block = anchor.block,
            constraint = anchor_type,
            transform = anchor_type === :soft_anchor ? :soft_anchor_prior : :fixed_value,
            validation_requirement = :anchor_declared,
            status = :specified_only,
            note = anchor_type === :soft_anchor ?
                "soft anchor declared with scale $(anchor_scale)" :
                "hard anchor declared with fixed value",
        ))
    end
    return rows
end

"""
    domain_compilation_summary(spec_or_design; preview = false)

Return a review table showing how domain options were compiled into the current
design contract. Rows cover likelihood family, additive/location blocks,
discrimination or loading blocks, scoring vectors, constraints, priors, fixed
Q-masks, validation requirements, DFF/bias validation terms, and anchors.

Fit-supported MFRM/RSM/PCM designs report `fit_ready = true` and
`public_fit = true`. Specified-only GMFRM/MGMFRM previews report the
experimental parameterization without enabling broad generalized fitting. For
specified-only `FacetSpec` values, pass `preview = true`, matching
[`getdesign`](@ref).
"""
function domain_compilation_summary(spec::FacetSpec; preview::Bool = false)
    return domain_compilation_summary(getdesign(spec; preview))
end

function domain_compilation_summary(design::FacetDesign; preview::Bool = false)
    preview &&
        throw(ArgumentError("preview is only a FacetSpec compilation option; pass domain_compilation_summary(spec; preview = true)"))
    spec = design.spec
    layout = _domain_compilation_layout(design)
    rows = NamedTuple[]
    push!(rows, _domain_row(spec, layout;
        domain_option = :family,
        compiled_role = :likelihood_kernel,
        validation_requirement = :likelihood_family_checked,
        status = layout.status,
        note = model_equation(spec).kernel,
    ))
    for block_row in layout.constrained_blocks
        push!(rows, _domain_block_summary_row(spec, design, layout, block_row.block))
    end
    scoring_block = _domain_scoring_block(spec)
    scoring_constraint = _domain_constraint_row(design, scoring_block)
    scoring_transform = _domain_transform_row(layout, scoring_block)
    scoring_names = begin
        row = _domain_block_row(layout.constrained_blocks, scoring_block)
        row === nothing ? String[] : row.parameter_names
    end
    push!(rows, _domain_row(spec, layout;
        domain_option = :thresholds,
        compiled_role = :scoring_vector,
        block = scoring_block,
        raw_block = scoring_transform === nothing ? scoring_block : scoring_transform.raw_block,
        constrained_block = scoring_block,
        parameter_names = scoring_names,
        raw_parameter_names = scoring_transform === nothing ? String[] :
            scoring_transform.raw_parameter_names,
        constraint = scoring_constraint === nothing ? missing : scoring_constraint.constraint,
        transform = scoring_constraint === nothing ? missing : scoring_constraint.transform,
        prior_block = scoring_transform === nothing ? scoring_block :
            _domain_nt_get(scoring_transform, :prior_block, scoring_block),
        prior = begin
            prior = _domain_prior_row(spec, scoring_block)
            prior === nothing ? missing : prior.prior
        end,
        scoring_vector = spec.data.category_levels,
        validation_requirement = :ordinal_score_categories,
        status = scoring_constraint === nothing ? layout.status : scoring_constraint.status,
        note = "observed ordinal categories used by row-by-category predictors",
    ))
    if spec.q_matrix !== nothing
        q_block = :item_dimension_discrimination
        q_transform = _domain_transform_row(layout, q_block)
        q_constraint = _domain_constraint_row(design, q_block)
        q_names = begin
            row = _domain_block_row(layout.constrained_blocks, q_block)
            row === nothing ? String[] : row.parameter_names
        end
        push!(rows, _domain_row(spec, layout;
            domain_option = :q_matrix,
            compiled_role = :loading_mask,
            block = q_block,
            raw_block = q_transform === nothing ? q_block : q_transform.raw_block,
            constrained_block = q_block,
            parameter_names = q_names,
            raw_parameter_names = q_transform === nothing ? String[] :
                q_transform.raw_parameter_names,
            constraint = q_constraint === nothing ? :fixed_mask : q_constraint.constraint,
            transform = q_transform === nothing ? :fixed_mask : q_transform.transform,
            prior_block = q_transform === nothing ? missing :
                _domain_nt_get(q_transform, :prior_block, missing),
            prior = begin
                prior = _domain_prior_row(spec, q_block)
                prior === nothing ? missing : prior.prior
            end,
            loading_mask = _q_matrix_manifest(spec.q_matrix),
            validation_requirement = :fixed_q_matrix_validated,
            status = q_constraint === nothing ? layout.status : q_constraint.status,
            note = "fixed confirmatory item-by-dimension loading mask",
        ))
    end
    append!(rows, _domain_validation_requirement_rows(spec, layout))
    return rows
end

function _surface_status_policy_for_spec(spec::FacetSpec)
    return _status_policy_manifest(
        spec.family,
        spec.estimation_status;
        public_fit = spec.estimation_status === :fit_supported,
        experimental_public = false,
        fit_ready = spec.estimation_status === :fit_supported,
        claim_scope = _spec_scope(spec.family, spec.estimation_status),
    )
end

function _surface_source_symbol(family::Symbol, block)
    ismissing(block) && return missing
    family === :mfrm && block === :person && return "theta_p"
    family === :mfrm && block === :rater && return "beta_r"
    family === :mfrm && block === :item && return "beta_i"
    family === :mfrm && block === :thresholds && return "d_m or d_im"
    family === :gmfrm && block === :person && return "theta_j"
    family === :gmfrm && block === :rater && return "beta_r"
    family === :gmfrm && block === :item && return "beta_i"
    family === :gmfrm && block === :item_discrimination && return "alpha_i"
    family === :gmfrm && block === :rater_consistency && return "alpha_r"
    family === :gmfrm && block === :rater_steps && return "d_rm"
    family === :mgmfrm && block === :person && return "theta_jl"
    family === :mgmfrm && block === :rater && return "beta_r"
    family === :mgmfrm && block === :item && return "beta_i"
    family === :mgmfrm && block === :item_dimension_discrimination && return "alpha_il"
    family === :mgmfrm && block === :rater_consistency && return "alpha_r"
    family === :mgmfrm && block === :item_steps && return "d_im"
    family === :mgmfrm && block === :q_matrix && return "Q_il"
    startswith(String(block), "dff_") && return "validation cell"
    return String(block)
end

function _surface_direct_interpretation(family::Symbol, block)
    ismissing(block) && return missing
    block === :person && return family === :mgmfrm ?
        "person ability/location by dimension" :
        "person ability/location"
    block === :rater && return "rater severity"
    block === :item && return "item/task difficulty"
    block === :thresholds && return "ordinal category threshold or step"
    block === :item_discrimination && return "positive item/task discrimination"
    block === :rater_consistency && return "positive rater consistency multiplier"
    block === :rater_steps && return "rater-specific category-use step"
    block === :item_dimension_discrimination &&
        return "positive fixed-Q item-by-dimension loading/discrimination"
    block === :item_steps && return "item-specific category-use step"
    block === :q_matrix && return "fixed confirmatory item-by-dimension mask"
    startswith(String(block), "dff_") &&
        return "DFF/bias validation cell, not a fitted model effect"
    return "model block"
end

function _surface_report_label(block)
    ismissing(block) && return missing
    block === :person && return :person_measure
    block === :rater && return :rater_severity
    block === :item && return :item_difficulty
    block === :thresholds && return :category_threshold
    block === :item_discrimination && return :item_discrimination
    block === :rater_consistency && return :rater_consistency
    block === :rater_steps && return :rater_category_step
    block === :item_dimension_discrimination && return :dimension_loading
    block === :item_steps && return :item_category_step
    block === :q_matrix && return :q_matrix
    startswith(String(block), "dff_") && return :dff_screening
    return block
end

function _surface_prior_scale(prior_block, block)
    ismissing(prior_block) && ismissing(block) && return missing
    prior_key = ismissing(prior_block) ? block : prior_block
    prior_key === :person && return :person_sd
    prior_key === :rater && return :rater_sd
    prior_key === :item && return :item_sd
    prior_key in (:thresholds, :rater_steps, :item_steps) && return :step_sd
    prior_key in (:item_discrimination, :log_item_discrimination,
        :log_item_dimension_discrimination) && return :log_discrimination_sd
    prior_key in (:rater_consistency, :log_rater_consistency) &&
        return :log_consistency_sd
    return missing
end

function _surface_prior_parameters(spec::FacetSpec, block, prior_block)
    if !ismissing(block)
        prior_row = _domain_prior_row(spec, block)
        prior_row === nothing || return prior_row.parameters
    end
    prior_scale = _surface_prior_scale(prior_block, block)
    ismissing(prior_scale) && return missing
    return (location = 0.0, scale = prior_scale)
end

function _model_surface_audit(design::FacetDesign; status_policy = _surface_status_policy_for_spec(design.spec))
    spec = design.spec
    rows = NamedTuple[]
    for row in domain_compilation_summary(design)
        haskey(row, :block) || continue
        block = row.block
        ismissing(block) && continue
        prior_scale = _surface_prior_scale(row.prior_block, block)
        push!(rows, (;
            schema = "bayesianmgmfrm.model_surface_audit_row.v1",
            family = spec.family,
            scope = status_policy.claim_scope,
            estimation_status = spec.estimation_status,
            current_status = status_policy.status_label,
            public_fit = status_policy.public_fit,
            experimental_public = status_policy.experimental_public,
            fit_ready = status_policy.fit_ready,
            stable_public = status_policy.stable_public,
            external_validated = status_policy.external_validated,
            block,
            compiled_role = row.compiled_role,
            source_symbol = _surface_source_symbol(spec.family, block),
            direct_interpretation = _surface_direct_interpretation(spec.family, block),
            raw_coordinate = row.raw_block,
            constrained_block = row.constrained_block,
            constraint = row.constraint,
            transform = row.transform,
            prior_block = row.prior_block,
            prior = row.prior,
            prior_scale,
            prior_parameters = _surface_prior_parameters(spec, block, row.prior_block),
            report_label = _surface_report_label(block),
            parameter_names = copy(row.parameter_names),
            raw_parameter_names = copy(row.raw_parameter_names),
            block_status = row.status,
            blocked_claims = status_policy.blocked_claims,
            next_gate = status_policy.next_gate,
            note = row.note,
        ))
    end
    return rows
end

"""
    model_surface_audit(spec_or_design; preview = nothing)

Return a machine-readable audit table for the current model surface. Rows trace
each parameter or validation block from the source-equation symbol to the direct
interpretation, raw coordinate, constraint, prior scale, report label, and
current status policy.

For specified-only GMFRM/MGMFRM specs, `preview` defaults to `true` so the audit
can inspect the represented source-aligned blocks without enabling broad public
fitting. Passing a compiled `FacetDesign` audits that design directly.
"""
function model_surface_audit(spec::FacetSpec; preview::Union{Nothing,Bool} = nothing)
    compile_preview = preview === nothing ?
        spec.estimation_status !== :fit_supported :
        preview
    design = getdesign(spec; preview = compile_preview)
    return _model_surface_audit(design; status_policy = _surface_status_policy_for_spec(spec))
end

function model_surface_audit(design::FacetDesign; preview::Bool = false)
    preview &&
        throw(ArgumentError("preview is only a FacetSpec compilation option; pass model_surface_audit(spec; preview = true)"))
    return _model_surface_audit(design; status_policy = _surface_status_policy_for_spec(design.spec))
end

function _source_transform_declarations(family::Symbol)
    family === :gmfrm && return NamedTuple[
        (raw_block = :person, constrained_block = :person, transform = :identity,
            constraint = :free, prior_block = :person),
        (raw_block = :rater, constrained_block = :rater, transform = :identity,
            constraint = :free, prior_block = :rater),
        (raw_block = :item_free, constrained_block = :item, transform = :sum_to_zero_last,
            constraint = :sum_to_zero, prior_block = :item),
        (raw_block = :log_item_discrimination_free, constrained_block = :item_discrimination,
            transform = :geometric_mean_one_log_last, constraint = :geometric_mean_one,
            prior_block = :log_item_discrimination),
        (raw_block = :log_rater_consistency, constrained_block = :rater_consistency,
            transform = :positive_log, constraint = :positive,
            prior_block = :log_rater_consistency),
        (raw_block = :rater_steps, constrained_block = :rater_steps, transform = :identity,
            constraint = :first_step_zero_sum_to_zero, prior_block = :rater_steps),
    ]
    family === :mgmfrm && return NamedTuple[
        (raw_block = :person, constrained_block = :person, transform = :identity,
            constraint = :multidimensional_location_gauge, prior_block = :person),
        (raw_block = :rater_free, constrained_block = :rater, transform = :sum_to_zero_last,
            constraint = :sum_to_zero, prior_block = :rater),
        (raw_block = :item, constrained_block = :item, transform = :identity,
            constraint = :free, prior_block = :item),
        (raw_block = :log_item_dimension_discrimination,
            constrained_block = :item_dimension_discrimination,
            transform = :positive_log_q_mask, constraint = :confirmatory_q_mask,
            prior_block = :log_item_dimension_discrimination),
        (raw_block = :log_rater_consistency_free, constrained_block = :rater_consistency,
            transform = :geometric_mean_one_log_last, constraint = :geometric_mean_one,
            prior_block = :log_rater_consistency),
        (raw_block = :item_steps, constrained_block = :item_steps, transform = :identity,
            constraint = :first_step_zero_sum_to_zero, prior_block = :item_steps),
    ]
    return NamedTuple[]
end

function _source_transform_manifest_rows(blueprint)
    rows = NamedTuple[]
    for declaration in _source_transform_declarations(blueprint.family)
        raw_range = blueprint.blocks[declaration.raw_block]
        constrained_range = blueprint.constrained_blocks[declaration.constrained_block]
        raw_indices = collect(raw_range)
        constrained_indices = collect(constrained_range)
        push!(rows, merge(declaration, (;
            raw_first_parameter = isempty(raw_indices) ? missing : first(raw_indices),
            raw_last_parameter = isempty(raw_indices) ? missing : last(raw_indices),
            raw_n_parameters = length(raw_indices),
            raw_parameter_names = isempty(raw_indices) ? String[] : copy(blueprint.parameter_names[raw_indices]),
            constrained_first_parameter = isempty(constrained_indices) ? missing : first(constrained_indices),
            constrained_last_parameter = isempty(constrained_indices) ? missing : last(constrained_indices),
            constrained_n_parameters = length(constrained_indices),
            constrained_parameter_names = isempty(constrained_indices) ? String[] :
                copy(blueprint.constrained_parameter_names[constrained_indices]),
            jacobian_policy = :none_raw_coordinate_density,
        )))
    end
    return rows
end

function _raw_prior_parameter_space(raw_block::Symbol)
    raw_block in (:log_item_discrimination_free,
        :log_item_dimension_discrimination,
        :log_rater_consistency,
        :log_rater_consistency_free) &&
        return :raw_log_positive_coordinate
    raw_block in (:rater_steps, :item_steps) &&
        return :raw_constrained_step_coordinate
    return :raw_unconstrained_coordinate
end

function _raw_prior_public_surface_role(family::Symbol, raw_block::Symbol)
    family === :gmfrm && raw_block === :log_rater_consistency &&
        return :guarded_scalar_gmfrm_core
    family === :gmfrm && raw_block === :log_item_discrimination_free &&
        return :source_block_active_public_item_target_preview_only
    family === :mgmfrm && raw_block === :log_item_dimension_discrimination &&
        return :fixed_q_loading_core
    family === :mgmfrm && raw_block === :log_rater_consistency_free &&
        return :fixed_q_rater_consistency_core
    raw_block in (:rater_steps, :item_steps) &&
        return :source_step_block_not_public_option
    return :guarded_generalized_support_block
end

function _generalized_raw_prior_control_rows(blueprint)
    rows = NamedTuple[]
    for transform in _source_transform_manifest_rows(blueprint)
        scale_parameter = _surface_prior_scale(
            transform.prior_block,
            transform.constrained_block,
        )
        push!(rows, (;
            schema = "bayesianmgmfrm.generalized_raw_prior_control_row.v1",
            family = blueprint.family,
            scope = blueprint.scope,
            status = :active,
            density_space = :raw_unconstrained,
            raw_block = transform.raw_block,
            constrained_block = transform.constrained_block,
            prior_block = transform.prior_block,
            parameter_space = _raw_prior_parameter_space(transform.raw_block),
            prior_family = :normal,
            location = 0.0,
            scale_parameter,
            scale = missing,
            scale_status = :symbolic_control,
            direct_scale_prior = false,
            jacobian_policy = transform.jacobian_policy,
            transform = transform.transform,
            constraint = transform.constraint,
            raw_n_parameters = transform.raw_n_parameters,
            raw_parameter_names = copy(transform.raw_parameter_names),
            constrained_n_parameters = transform.constrained_n_parameters,
            constrained_parameter_names = copy(transform.constrained_parameter_names),
            independent_by_parameter = true,
            public_surface_role =
                _raw_prior_public_surface_role(blueprint.family, transform.raw_block),
        ))
    end
    push!(rows, (;
        schema = "bayesianmgmfrm.generalized_raw_prior_control_row.v1",
        family = blueprint.family,
        scope = blueprint.scope,
        status = :blocked,
        density_space = :raw_unconstrained,
        raw_block = missing,
        constrained_block = :direct_scale_generalized_priors,
        prior_block = missing,
        parameter_space = :direct_constrained_parameter,
        prior_family = :not_enabled,
        location = 0.0,
        scale_parameter = :not_applicable,
        scale = missing,
        scale_status = :not_applicable,
        direct_scale_prior = true,
        jacobian_policy = :requires_future_log_jacobian_policy,
        transform = :not_enabled,
        constraint = :not_enabled,
        raw_n_parameters = 0,
        raw_parameter_names = String[],
        constrained_n_parameters = 0,
        constrained_parameter_names = String[],
        independent_by_parameter = false,
        public_surface_role = :blocked_direct_scale_prior_policy,
    ))
    return rows
end

function _generalized_raw_prior_control_manifest(blueprint;
        public_fit::Bool = false,
        experimental_public::Bool = public_fit)
    rows = _generalized_raw_prior_control_rows(blueprint)
    return (;
        schema = "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1",
        family = blueprint.family,
        scope = blueprint.scope,
        status = :policy_recorded,
        density_space = :raw_unconstrained,
        prior_policy = :independent_normal_raw_coordinates,
        direct_scale_priors = false,
        direct_prior_policy = :not_enabled_raw_coordinate_priors_only,
        jacobian_policy = :none_raw_coordinate_density,
        public_fit,
        experimental_public,
        rows,
        n_rows = length(rows),
        summary = (;
            n_active_rows = count(row -> row.status === :active, rows),
            n_blocked_rows = count(row -> row.status === :blocked, rows),
            raw_rater_consistency_control_recorded =
                any(row -> row.raw_block in
                    (:log_rater_consistency, :log_rater_consistency_free), rows),
            item_discrimination_source_control_recorded =
                any(row -> row.raw_block in
                    (:log_item_discrimination_free,
                        :log_item_dimension_discrimination), rows),
            direct_scale_generalized_priors_enabled = false,
            all_active_rows_no_jacobian =
                all(row -> row.status !== :active ||
                    row.jacobian_policy === :none_raw_coordinate_density, rows),
        ),
    )
end

function _fit_ready_candidate_constraint_rows(blueprint)
    rows = NamedTuple[]
    for transform in _source_transform_manifest_rows(blueprint)
        push!(rows, (;
            raw_block = transform.raw_block,
            constrained_block = transform.constrained_block,
            constraint = transform.constraint,
            transform = transform.transform,
            status = :internal_fit_ready_candidate,
            prior_block = transform.prior_block,
            raw_n_parameters = transform.raw_n_parameters,
            constrained_n_parameters = transform.constrained_n_parameters,
            jacobian_policy = transform.jacobian_policy,
        ))
    end
    return rows
end

const _GMFRM_PUBLIC_TARGET_LABEL = :guarded_scalar_gmfrm_logdensity
const _GMFRM_PUBLIC_TARGET_DESCRIPTION = "guarded scalar GMFRM log density"
const _GMFRM_INTERNAL_TARGET_CONSTRUCTOR = :_gmfrm_promotion_candidate_logdensity
const _GMFRM_INTERNAL_GRADIENT_DIAGNOSTIC_CONSTRUCTOR =
    :_gmfrm_promotion_candidate_diagnostics
const _GMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR =
    :_gmfrm_promotion_candidate_sampler_diagnostics
const _MGMFRM_PUBLIC_TARGET_LABEL = :guarded_confirmatory_mgmfrm_logdensity
const _MGMFRM_PUBLIC_TARGET_DESCRIPTION =
    "guarded fixed-Q confirmatory MGMFRM log density"
const _MGMFRM_INTERNAL_TARGET_CONSTRUCTOR =
    :_mgmfrm_guarded_local_fit_logdensity
const _MGMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR =
    :_mgmfrm_guarded_local_fit_sampler_diagnostics

function _gmfrm_rater_step_public_option_policy(blueprint)
    return (;
        schema = "bayesianmgmfrm.gmfrm_rater_step_public_option_policy.v1",
        family = :gmfrm,
        scope = blueprint.scope,
        status = :policy_recorded,
        source_block = :rater_steps,
        source_block_status = :internal_source_model_block,
        internal_block_enabled = true,
        public_option = :rater_steps,
        public_keyword_enabled = false,
        public_option_status = :blocked_until_policy_gate,
        blocker = :rater_step_public_option_policy_not_promoted,
        next_gate = :rater_step_public_option_policy,
        required_before_public_rejection = true,
        rationale = :rater_steps_are_source_equation_terms_not_public_fit_options,
    )
end

function _gmfrm_item_discrimination_promotion_decision(blueprint)
    return (;
        schema = "bayesianmgmfrm.gmfrm_item_discrimination_promotion_decision.v1",
        family = :gmfrm,
        scope = blueprint.scope,
        status = :decision_recorded,
        decision = :keep_preview_only_for_v0_1_1,
        public_option = :discrimination,
        requested_public_value = :item,
        guarded_public_value = :rater,
        source_block = :item_discrimination,
        source_block_status = :enabled_within_guarded_rater_consistency_surface,
        preview_design_available = true,
        public_fit_enabled = false,
        internal_promotion_target_enabled = false,
        blocked_option = :discrimination,
        blocked_value = :item,
        blocker = :item_discrimination_promotion_target_not_selected,
        next_gate = :item_discrimination_promotion_decision,
        required_before_promotion = (
            :separate_item_discrimination_estimand,
            :bridge_oracle,
            :candidate_chain_study,
            :recovery_smoke,
            :prior_sensitivity,
            :artifact_contract_review,
        ),
        rationale =
            :v0_1_1_keeps_only_guarded_rater_consistency_scalar_gmfrm_fit,
    )
end

function _gmfrm_fit_ready_compiler_candidate(blueprint)
    return (;
        schema = "bayesianmgmfrm.gmfrm_fit_ready_compiler_candidate.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :internal_fit_ready_candidate,
        public_fit = false,
        fit_ready = false,
        fixture_only = false,
        compiler_stage = :fit_ready_candidate,
        source_oracle = :scalar_gmfrm_source_aligned,
        density_space = :raw_unconstrained,
        prior_policy = :independent_normal_raw_coordinates,
        direct_prior_policy = :not_enabled_raw_coordinate_priors_only,
        jacobian_policy = :none_raw_coordinate_density,
        raw_prior_control_manifest =
            _generalized_raw_prior_control_manifest(blueprint),
        public_target_label = _GMFRM_PUBLIC_TARGET_LABEL,
        public_target_description = _GMFRM_PUBLIC_TARGET_DESCRIPTION,
        internal_target_constructor = _GMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        rater_step_public_option_policy =
            _gmfrm_rater_step_public_option_policy(blueprint),
        item_discrimination_promotion_decision =
            _gmfrm_item_discrimination_promotion_decision(blueprint),
        n_raw_parameters = blueprint.n_parameters,
        raw_parameter_names = copy(blueprint.parameter_names),
        constrained_parameter_names = copy(blueprint.constrained_parameter_names),
        raw_blocks = _block_manifest_rows(blueprint.blocks, blueprint.parameter_names),
        constrained_blocks = _block_manifest_rows(
            blueprint.constrained_blocks,
            blueprint.constrained_parameter_names,
        ),
        transforms = _source_transform_manifest_rows(blueprint),
        constraints = _fit_ready_candidate_constraint_rows(blueprint),
        unsupported_public_options = [
            :direct_scale_priors,
            :dff_effects,
            :multidimensional_ability,
            :free_latent_correlation,
            :item_discrimination_public_target,
            :public_rater_steps,
            :hierarchical_rater_thresholds,
        ],
    )
end

function _promotion_candidate_gate_rows(family::Symbol)
    family === :gmfrm && return [
        (gate = :raw_transform_manifest, status = :done,
            evidence = :design_raw_parameterization),
        (gate = :fit_ready_compiler_manifest, status = :done,
            evidence = :gmfrm_fit_ready_compiler_candidate),
        (gate = :direct_parameter_metadata, status = :done,
            evidence = :constrained_block_manifest),
        (gate = :raw_to_direct_transform, status = :done,
            evidence = :promotion_candidate_transform_diagnostics),
        (gate = :direct_pointwise_fixture, status = :done,
            evidence = :promotion_candidate_pointwise_fixture),
        (gate = :pointwise_likelihood_fixture, status = :done,
            evidence = :source_aligned_julia_fixture),
        (gate = :logdensity_gradient_check, status = :done,
            evidence = :forwarddiff_finite_difference_test),
        (gate = :bridge_oracle_check, status = :done,
            evidence = :bridgestan_logdensity_gradient_fixture),
        (gate = :bridge_direct_parameter_check, status = :done,
            evidence = :bridgestan_constrained_parameter_fixture),
        (gate = :hmc_smoke_check, status = :done,
            evidence = :advancedhmc_fixture_smoke_test),
        (gate = :public_fit_api, status = :blocked,
            evidence = :fit_rejects_specified_only_gmfrm),
        (gate = :production_diagnostics, status = :done,
            evidence = :promotion_candidate_sampler_diagnostics),
        (gate = :candidate_chain_study, status = :done,
            evidence = :gmfrm_candidate_chain_study_fixture),
        (gate = :stress_chain_grid, status = :done,
            evidence = :gmfrm_stress_chain_grid_fixture),
        (gate = :recovery_smoke_study, status = :done,
            evidence = :gmfrm_recovery_smoke_fixture),
        (gate = :baseline_comparison, status = :done,
            evidence = :gmfrm_baseline_comparison_fixture),
        (gate = :baseline_calibration_grid, status = :done,
            evidence = :gmfrm_baseline_calibration_grid_fixture),
        (gate = :interval_decision_grid, status = :done,
            evidence = :gmfrm_interval_decision_grid_fixture),
        (gate = :sparse_design_grid, status = :done,
            evidence = :gmfrm_sparse_design_grid_fixture),
        (gate = :waic_influence_review, status = :done,
            evidence = :gmfrm_waic_influence_review_fixture),
        (gate = :psis_loo_review, status = :done,
            evidence = :gmfrm_psis_loo_review_fixture),
        (gate = :exact_loo_or_kfold_review, status = :done,
            evidence = :gmfrm_exact_loo_or_kfold_review_fixture),
        (gate = :guarded_exposure_review, status = :done,
            evidence = :gmfrm_guarded_exposure_review_fixture),
        (gate = :guarded_fit_api_dry_run, status = :done,
            evidence = :gmfrm_guarded_fit_api_dry_run_fixture),
        (gate = :guarded_fit_method_wiring, status = :done,
            evidence = :gmfrm_guarded_fit_method_wiring_fixture),
        (gate = :experimental_fit_validation_grid, status = :done,
            evidence = :gmfrm_experimental_fit_validation_grid_fixture),
        (gate = :posterior_predictive_grid, status = :done,
            evidence = :gmfrm_posterior_predictive_grid_fixture),
        (gate = :sparse_pathology_recovery_grid, status = :done,
            evidence = :gmfrm_sparse_pathology_recovery_grid_fixture),
        (gate = :prior_likelihood_sensitivity_grid, status = :done,
            evidence = :gmfrm_prior_likelihood_sensitivity_grid_fixture),
        (gate = :real_data_case_study, status = :done,
            evidence = :gmfrm_real_data_case_study_fixture),
        (gate = :claim_recovery_reproduction_archive, status = :done,
            evidence = :gmfrm_claim_recovery_reproduction_archive_fixture),
        (gate = :broader_experimental_exposure_decision_review, status = :done,
            evidence = :gmfrm_broader_experimental_exposure_decision_review_fixture),
        (gate = :direct_scale_prior_jacobian_policy, status = :done,
            evidence = :raw_prior_jacobian_policy_decision),
        (gate = :experimental_public_api, status = :done,
            evidence = :gmfrm_experimental_public_api_decision),
    ]
    return NamedTuple[]
end

function _gmfrm_experimental_candidate_option_rows()
    capability = _guarded_generalized_fit_capability(:gmfrm)
    return [
        (option = :entrypoint, value = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
            status = :enabled_guarded,
            note = :scalar_gmfrm_only),
        (option = :legacy_entrypoint, value = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
            status = :compatibility_only,
            note = :source_compatibility_during_namespace_migration),
        (option = :family, value = capability.family,
            status = :candidate_only,
            note = :scalar_gmfrm_before_mgmfrm),
        (option = :dimensions, value = capability.minimum_dimensions,
            status = :candidate_only,
            note = :one_dimensional_only),
        (option = :thresholds, value = only(capability.threshold_regimes),
            status = :candidate_only,
            note = :source_aligned_rater_step_kernel),
        (option = :discrimination, value = only(capability.spec_discrimination),
            status = :candidate_only,
            note = :source_aligned_scalar_gmfrm_fixture),
        (option = :validation_bias_terms, value = (),
            status = :candidate_only,
            note = :validation_only_not_fitted),
        (option = :anchors, value = (),
            status = :candidate_only,
            note = :anchor_likelihood_not_implemented),
        (option = :density_space, value = :raw_unconstrained,
            status = :candidate_only,
            note = :raw_coordinate_prior_contract_required),
        (option = :rater_steps, value = :internal_source_block,
            status = :candidate_only,
            note = :not_a_public_fit_option),
    ]
end

function _gmfrm_experimental_rejected_option_rows()
    return [
        (option = :thresholds, value = :rating_scale,
            status = :blocked,
            blocker = :guarded_generalized_threshold_contract),
        (option = :anchors, value = :nonempty,
            status = :blocked,
            blocker = :generalized_anchor_likelihood_not_implemented),
        (option = :family, value = :mgmfrm,
            status = :blocked,
            blocker = :mgmfrm_baseline_sparse_prior_policy_pending),
        (option = :dimensions, value = :multidimensional,
            status = :blocked,
            blocker = :mgmfrm_public_scope_not_promoted),
        (option = :discrimination, value = :item,
            status = :blocked,
            blocker = :item_discrimination_promotion_target_not_selected),
        (option = :direct_scale_priors, value = :constrained_direct,
            status = :blocked,
            blocker = :raw_prior_policy_selected_for_candidate),
        (option = :bias_or_dff_terms, value = :model_effects,
            status = :blocked,
            blocker = :dff_model_effect_fit_policy_not_promoted),
        (option = :hierarchical_rater_thresholds, value = :enabled,
            status = :blocked,
            blocker = :pooling_and_identification_policy_missing),
        (option = :rater_steps, value = :public_option,
            status = :blocked,
            blocker = :rater_step_public_option_policy_not_promoted),
        (option = :model_comparison_weights, value = :loo_or_stacking,
            status = :blocked,
            blocker = :psis_loo_pareto_k_target_missing),
    ]
end

function _experimental_fit_artifact_contract_field_rows(family::Symbol)
    rows = [
        (field = :schema, status = :required,
            note = :family_specific_experimental_fit_artifact_schema),
        (field = :experimental_public, status = :required,
            note = :true_only_when_guarded_entrypoint_is_enabled),
        (field = :public_fit, status = :required,
            note = :must_match_manifest_decision),
        (field = :family, status = :required,
            note = :generalized_family_name),
        (field = :scope, status = :required,
            note = :narrow_candidate_scope),
        (field = :public_target_label, status = :required,
            note = :stable_user_facing_guarded_fit_target_name),
        (field = :internal_target_constructor, status = :required,
            note = :private_helper_name_kept_as_compatibility_metadata),
        (field = :density_space, status = :required,
            note = :raw_unconstrained_or_documented_direct_policy),
        (field = :raw_prior_control_manifest, status = :required,
            note = :block_level_raw_prior_controls_and_no_jacobian_policy),
        (field = :parameter_layout, status = :required,
            note = :compiler_generated_raw_direct_blocks_transforms_and_constraints),
        (field = :raw_parameter_names, status = :required,
            note = :sampler_coordinate_order),
        (field = :direct_parameter_names, status = :required,
            note = :interpretable_constrained_order),
        (field = :raw_to_direct_transform, status = :required,
            note = :constraint_and_jacobian_policy_provenance),
        (field = :sampler_controls, status = :required,
            note = :backend_seed_warmup_draws_chains_and_metric),
        (field = :diagnostics, status = :required,
            note = :rhat_ess_divergence_treedepth_and_ebfmi_rows),
        (field = :pointwise_loglikelihood, status = :required,
            note = :observation_ordered_loglikelihood_matrix),
        (field = :caveat_docs_artifact, status = :required,
            note = :guarded_generalized_model_caveats),
        (field = :fixture_provenance, status = :required,
            note = :bridge_chain_recovery_artifact_paths_and_hashes),
        (field = :raw_posterior_row_schema, status = :required,
            note = :raw_posterior_summary_fields_and_compiler_block_provenance),
        (field = :direct_posterior_row_schema, status = :required,
            note = :direct_posterior_summary_fields_and_compiler_block_provenance),
    ]
    family === :mgmfrm || return rows
    return [
        rows...,
        (field = :q_matrix, status = :required,
            note = :fixed_confirmatory_mask),
        (field = :latent_correlation, status = :required,
            note = :identity_fixed_for_first_candidate),
        (field = :ability_scale, status = :required,
            note = :standard_normal_gauge),
        (field = :initialization_policy, status = :required,
            note = :raw_initial_source_fallback_and_finite_logdensity_policy),
        (field = :initialization_rows, status = :required,
            note = :row_level_initial_raw_direct_and_chain_jitter_checks),
        (field = :fixed_q_invariance_rows, status = :required,
            note = :fixed_q_sign_identity_correlation_and_blocked_rotation_checks),
    ]
end

function _experimental_fit_artifact_contract_provenance_rows(;
        bridge_artifact,
        candidate_chain_study_artifact,
        recovery_smoke_artifact,
        caveat_docs_artifact)
    return [
        (artifact = :bridge_oracle, status = :required,
            value = bridge_artifact,
            hash_policy = :sha256_when_exported),
        (artifact = :candidate_chain_study, status = :required,
            value = candidate_chain_study_artifact,
            hash_policy = :sha256_when_exported),
        (artifact = :recovery_smoke_study, status = :required,
            value = recovery_smoke_artifact,
            hash_policy = :sha256_when_exported),
        (artifact = :caveat_docs, status = :required,
            value = caveat_docs_artifact,
            hash_policy = :git_blob_or_sha256_when_exported),
    ]
end

function _experimental_fit_artifact_contract(family::Symbol,
        scope::Symbol;
        bridge_artifact,
        candidate_chain_study_artifact,
        recovery_smoke_artifact,
        caveat_docs_artifact,
        public_fit::Bool = false,
        experimental_public::Bool = public_fit,
        artifact_kind::Symbol = public_fit ?
            :experimental_generalized_fit_artifact :
            :future_experimental_generalized_fit_artifact)
    required_fields = _experimental_fit_artifact_contract_field_rows(family)
    provenance_rows = _experimental_fit_artifact_contract_provenance_rows(;
        bridge_artifact,
        candidate_chain_study_artifact,
        recovery_smoke_artifact,
        caveat_docs_artifact)
    return (;
        schema = "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1",
        family,
        scope,
        status = :contract_recorded,
        public_fit,
        experimental_public,
        artifact_kind,
        required_fields,
        provenance_rows,
        summary = (;
            n_required_fields = length(required_fields),
            n_required_provenance_artifacts = length(provenance_rows),
            enables_public_fit = public_fit,
        ),
    )
end

function _generalized_raw_prior_jacobian_policy(family::Symbol,
        scope::Symbol;
        public_fit::Bool = false,
        experimental_public::Bool = public_fit)
    return (;
        schema = "bayesianmgmfrm.generalized_raw_prior_jacobian_policy.v1",
        family,
        scope,
        status = :policy_recorded,
        density_space = :raw_unconstrained,
        prior_policy = :independent_normal_raw_coordinates,
        direct_scale_priors = false,
        direct_prior_policy = :not_enabled_raw_coordinate_priors_only,
        jacobian_policy = :none_raw_coordinate_density,
        direct_parameter_summaries = :deterministic_transforms_of_raw_draws,
        public_fit,
        experimental_public,
        notes = [
            :no_log_jacobian_for_raw_coordinate_density,
            :direct_scale_priors_require_future_jacobian_policy,
            :direct_parameters_are_interpretable_transforms_not_prior_scales,
        ],
    )
end

function _gmfrm_experimental_public_evidence_rows()
    return [
        (evidence = :fit_ready_compiler_manifest, status = :done,
            artifact = :gmfrm_fit_ready_compiler_candidate),
        (evidence = :raw_to_direct_transform_diagnostics, status = :done,
            artifact = :gmfrm_promotion_candidate_transform_diagnostics),
        (evidence = :direct_pointwise_fixture, status = :done,
            artifact = :gmfrm_promotion_candidate_pointwise_fixture),
        (evidence = :bridgestan_fit_ready_oracle, status = :done,
            artifact = :fit_ready_scalar_gmfrm_bridge_oracle),
        (evidence = :candidate_chain_study, status = :done,
            artifact = "test/fixtures/gmfrm_candidate_chain_study.json"),
        (evidence = :recovery_smoke_study, status = :done,
            artifact = "test/fixtures/gmfrm_recovery_smoke.json"),
        (evidence = :fit_artifact_manifest_for_experimental_public, status = :done,
            artifact = :experimental_public_fit_artifact_contract),
        (evidence = :rater_step_public_option_policy, status = :done,
            artifact = :gmfrm_rater_step_public_option_policy),
        (evidence = :item_discrimination_promotion_decision, status = :done,
            artifact = :gmfrm_item_discrimination_promotion_decision),
        (evidence = :stress_chain_grid, status = :done,
            artifact = "test/fixtures/gmfrm_stress_chain_grid.json"),
        (evidence = :baseline_comparison, status = :done,
            artifact = "test/fixtures/gmfrm_baseline_comparison.json"),
        (evidence = :baseline_calibration_grid, status = :done,
            artifact = "test/fixtures/gmfrm_baseline_calibration_grid.json"),
        (evidence = :interval_decision_grid, status = :done,
            artifact = "test/fixtures/gmfrm_interval_decision_grid.json"),
        (evidence = :sparse_design_grid, status = :done,
            artifact = "test/fixtures/gmfrm_sparse_design_grid.json"),
        (evidence = :waic_influence_review, status = :done,
            artifact = "test/fixtures/gmfrm_waic_influence_review.json"),
        (evidence = :psis_loo_review, status = :done,
            artifact = "test/fixtures/gmfrm_psis_loo_review.json"),
        (evidence = :exact_loo_or_kfold_review, status = :done,
            artifact = "test/fixtures/gmfrm_exact_loo_or_kfold_review.json"),
        (evidence = :guarded_exposure_review, status = :done,
            artifact = "test/fixtures/gmfrm_guarded_exposure_review.json"),
        (evidence = :guarded_fit_api_dry_run, status = :done,
            artifact = "test/fixtures/gmfrm_guarded_fit_api_dry_run.json"),
        (evidence = :guarded_fit_method_wiring, status = :done,
            artifact = "test/fixtures/gmfrm_guarded_fit_method_wiring.json"),
        (evidence = :experimental_fit_validation_grid, status = :done,
            artifact = "test/fixtures/gmfrm_experimental_fit_validation_grid.json"),
        (evidence = :posterior_predictive_grid, status = :done,
            artifact = "test/fixtures/gmfrm_posterior_predictive_grid.json"),
        (evidence = :sparse_pathology_recovery_grid, status = :done,
            artifact = "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json"),
        (evidence = :prior_likelihood_sensitivity_grid, status = :done,
            artifact =
                "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json"),
        (evidence = :real_data_case_study, status = :done,
            artifact = "test/fixtures/gmfrm_real_data_case_study.json"),
        (evidence = :claim_recovery_reproduction_archive, status = :done,
            artifact =
                "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json"),
        (evidence = :broader_experimental_exposure_decision_review,
            status = :done,
            artifact =
                "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json"),
        (evidence = :mgmfrm_baseline_comparison, status = :done,
            artifact = "test/fixtures/mgmfrm_baseline_comparison.json"),
        (evidence = :mgmfrm_sparse_recovery_grid, status = :done,
            artifact = "test/fixtures/mgmfrm_sparse_recovery_grid.json"),
        (evidence = :dff_estimand_validation_grid, status = :done,
            artifact = "test/fixtures/gmfrm_dff_estimand_validation_grid.json"),
        (evidence = :manuscript_scale_simulation_grid, status = :done,
            artifact =
                "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json"),
        (evidence = :full_paper_reproduction_archive, status = :done,
            artifact =
                "test/fixtures/gmfrm_full_paper_reproduction_archive.json"),
        (evidence = :direct_prior_jacobian_policy, status = :done,
            artifact = :generalized_raw_prior_jacobian_policy),
        (evidence = :raw_prior_control_manifest, status = :done,
            artifact = :generalized_raw_prior_control_manifest),
        (evidence = :public_caveat_docs, status = :done,
            artifact = "docs/src/fitting.md#guarded-generalized-model-caveats"),
    ]
end

function _gmfrm_experimental_public_blocker_rows()
    return NamedTuple[]
end

function _gmfrm_experimental_public_api_decision(blueprint)
    evidence_rows = _gmfrm_experimental_public_evidence_rows()
    blocker_rows = _gmfrm_experimental_public_blocker_rows()
    return (;
        schema = "bayesianmgmfrm.gmfrm_experimental_public_api_decision.v1",
        family = :gmfrm,
        scope = blueprint.scope,
        status = :experimental_public,
        decision = :enable_guarded_experimental,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        proposed_entrypoint = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
        legacy_entrypoint = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
        public_target_label = _GMFRM_PUBLIC_TARGET_LABEL,
        public_target_description = _GMFRM_PUBLIC_TARGET_DESCRIPTION,
        internal_target_constructor = _GMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        internal_sampler_diagnostic_constructor =
            _GMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR,
        rater_step_public_option_policy =
            _gmfrm_rater_step_public_option_policy(blueprint),
        item_discrimination_promotion_decision =
            _gmfrm_item_discrimination_promotion_decision(blueprint),
        target_constructor = _GMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        sampler_diagnostic_constructor =
            _GMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR,
        candidate_chain_study_artifact =
            "test/fixtures/gmfrm_candidate_chain_study.json",
        stress_chain_grid_artifact = "test/fixtures/gmfrm_stress_chain_grid.json",
        recovery_smoke_artifact = "test/fixtures/gmfrm_recovery_smoke.json",
        baseline_comparison_artifact =
            "test/fixtures/gmfrm_baseline_comparison.json",
        baseline_calibration_grid_artifact =
            "test/fixtures/gmfrm_baseline_calibration_grid.json",
        interval_decision_grid_artifact =
            "test/fixtures/gmfrm_interval_decision_grid.json",
        sparse_design_grid_artifact =
            "test/fixtures/gmfrm_sparse_design_grid.json",
        waic_influence_review_artifact =
            "test/fixtures/gmfrm_waic_influence_review.json",
        psis_loo_review_artifact =
            "test/fixtures/gmfrm_psis_loo_review.json",
        exact_loo_or_kfold_review_artifact =
            "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        guarded_exposure_review_artifact =
            "test/fixtures/gmfrm_guarded_exposure_review.json",
        guarded_fit_api_dry_run_artifact =
            "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        guarded_fit_method_wiring_artifact =
            "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
        experimental_fit_validation_grid_artifact =
            "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        posterior_predictive_grid_artifact =
            "test/fixtures/gmfrm_posterior_predictive_grid.json",
        sparse_pathology_recovery_grid_artifact =
            "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        prior_likelihood_sensitivity_grid_artifact =
            "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        real_data_case_study_artifact =
            "test/fixtures/gmfrm_real_data_case_study.json",
        claim_recovery_reproduction_archive_artifact =
            "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        broader_experimental_exposure_decision_review_artifact =
            "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json",
        mgmfrm_baseline_comparison_artifact =
            "test/fixtures/mgmfrm_baseline_comparison.json",
        mgmfrm_sparse_recovery_grid_artifact =
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        dff_estimand_validation_grid_artifact =
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        manuscript_scale_simulation_grid_artifact =
            "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        full_paper_reproduction_archive_artifact =
            "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
        baseline_comparison_interpretation = (;
            status = :initial_smoke_done,
            comparison_target = :same_observation_waic,
            interpretation = :inconclusive_high_variance_smoke,
            public_exposure_support = :insufficient_alone,
            required_followup = :satisfied_by_baseline_calibration_grid_artifact,
        ),
        baseline_calibration_grid_interpretation = (;
            status = :grid_recorded,
            comparison_target = :same_observation_waic_and_expected_score_calibration,
            interpretation = :all_scenarios_passed_with_high_variance_waic_warnings,
            public_exposure_support = :reviewed_insufficient_for_public_fit,
            required_followup = :satisfied_by_interval_decision_grid_artifact,
        ),
        interval_decision_grid_interpretation = (;
            status = :grid_recorded,
            comparison_target =
                :direct_parameter_interval_coverage_and_keep_internal_stability,
            interpretation = :intervals_finite_and_keep_internal_decision_stable,
            public_exposure_support =
                :satisfied_for_sparse_design_grid_followup,
            required_followup = :satisfied_by_sparse_design_grid_artifact,
        ),
        sparse_design_grid_interpretation = (;
            status = :grid_recorded,
            comparison_target =
                :sparse_connected_design_validation_interval_and_decision_stability,
            interpretation =
                :sparse_designs_passed_with_recorded_validation_warnings,
            public_exposure_support =
                :satisfied_for_waic_influence_followup,
            required_followup = :satisfied_by_waic_influence_review_artifact,
        ),
        waic_influence_review_interpretation = (;
            status = :review_recorded,
            comparison_target =
                :pointwise_waic_influence_and_flagged_observation_sensitivity,
            interpretation =
                :flagged_observation_removal_changes_some_model_ranks,
            public_exposure_support =
                :satisfied_for_psis_loo_followup,
            required_followup = :satisfied_by_psis_loo_review_artifact,
        ),
        psis_loo_review_interpretation = (;
            status = :review_recorded,
            comparison_target = :raw_importance_loo_pareto_k_screen,
            interpretation =
                :high_pareto_k_requires_exact_loo_or_kfold,
            public_exposure_support =
                :satisfied_for_exact_loo_or_kfold_followup,
            required_followup =
                :satisfied_by_exact_loo_or_kfold_review_artifact,
        ),
        exact_loo_or_kfold_review_interpretation = (;
            status = :review_recorded,
            comparison_target = :heldout_observation_kfold_refit_log_score,
            interpretation =
                :kfold_refit_review_satisfied_exact_loo_followup,
            public_exposure_support =
                :satisfied_for_guarded_fit_api_dry_run_followup,
            required_followup = :satisfied_by_guarded_fit_api_dry_run_artifact,
        ),
        guarded_exposure_review_interpretation = (;
            status = :review_recorded,
            review_target = :experimental_public_scalar_gmfrm,
            interpretation =
                :local_evidence_reviewed_full_archive_recorded_and_broader_exposure_decision_recorded,
            public_exposure_support = :guarded_scalar_gmfrm_only,
            required_followup = :manual_publication_or_registration_by_user_only,
        ),
        guarded_fit_api_dry_run_interpretation = (;
            status = :dry_run_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :guarded_entrypoint_contract_dry_run_passed_but_method_not_wired,
            public_exposure_support =
                :satisfied_by_guarded_fit_method_wiring,
            required_followup = :satisfied_by_guarded_fit_method_wiring,
        ),
        guarded_fit_method_wiring_interpretation = (;
            status = :method_wired,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :scalar_gmfrm_guarded_experimental_fit_method_enabled,
            public_exposure_support =
                :satisfied_for_experimental_fit_validation_grid_followup,
            required_followup = :experimental_fit_validation_grid,
        ),
        experimental_fit_validation_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :guarded_scalar_gmfrm_experimental_fit_validation_grid_passed_ppc_and_sparse_pathology_checked,
            public_exposure_support =
                :satisfied_by_sparse_pathology_recovery_grid,
            required_followup = :scalar_gmfrm_prior_likelihood_sensitivity_grid,
        ),
        posterior_predictive_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :guarded_scalar_gmfrm_posterior_predictive_grid_passed,
            public_exposure_support =
                :satisfied_by_sparse_pathology_recovery_grid,
            required_followup = :scalar_gmfrm_prior_likelihood_sensitivity_grid,
        ),
        sparse_pathology_recovery_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :guarded_scalar_gmfrm_sparse_pathology_recovery_grid_passed,
            public_exposure_support =
                :satisfied_by_prior_likelihood_sensitivity_grid,
            required_followup = :scalar_gmfrm_real_data_case_study,
        ),
        prior_likelihood_sensitivity_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :guarded_scalar_gmfrm_prior_likelihood_sensitivity_grid_passed,
            public_exposure_support =
                :satisfied_by_real_data_case_study,
            required_followup = :claim_level_recovery_and_reproduction_archive,
        ),
        real_data_case_study_interpretation = (;
            status = :case_study_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :guarded_scalar_gmfrm_real_data_case_study_passed,
            public_exposure_support =
                :satisfied_by_claim_recovery_reproduction_archive,
            required_followup = :broader_experimental_exposure_decision_review,
        ),
        claim_recovery_reproduction_archive_interpretation = (;
            status = :archive_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_claim_support,
            interpretation =
                :claim_level_recovery_reproduction_archive_recorded,
            public_exposure_support =
                :satisfied_by_broader_experimental_exposure_decision_review,
            required_followup =
                :satisfied_by_broader_experimental_exposure_decision_review,
        ),
        broader_experimental_exposure_decision_review_interpretation = (;
            status = :decision_recorded,
            review_target = :broader_generalized_model_exposure,
            interpretation =
                :broader_exposure_review_recorded_full_archive_available_keep_broader_claims_blocked,
            public_exposure_support = :guarded_scalar_gmfrm_only,
            required_followup = :manual_publication_or_registration_by_user_only,
        ),
        mgmfrm_baseline_comparison_interpretation = (;
            status = :comparison_recorded,
            comparison_target =
                :confirmatory_mgmfrm_same_observation_waic_against_mfrm_baselines,
            interpretation =
                :baseline_comparison_recorded_keep_mgmfrm_internal,
            public_exposure_support = :insufficient_for_mgmfrm_public_fit,
            required_followup = :manual_public_scope_review_for_mgmfrm_fit,
        ),
        mgmfrm_sparse_recovery_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :confirmatory_mgmfrm_sparse_connected_recovery,
            interpretation =
                :sparse_recovery_grid_recorded_keep_mgmfrm_internal,
            public_exposure_support = :insufficient_for_broader_public_claims,
            required_followup = :manual_public_scope_review_for_mgmfrm_fit,
        ),
        dff_estimand_validation_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :dff_estimand_validation_evidence,
            interpretation =
                :dff_estimands_predeclared_keep_model_effects_validation_only,
            public_exposure_support =
                :satisfied_for_gate_e_followup_without_dff_model_effect_fit,
            required_followup = :future_dff_model_effect_fit_policy,
        ),
        manuscript_scale_simulation_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :gate_e_broader_generalized_claim_evidence,
            interpretation =
                :manuscript_scale_grid_recorded_full_archive_available,
            public_exposure_support =
                :full_archive_recorded_without_broader_fit,
            required_followup = :manual_publication_or_registration_by_user_only,
        ),
        full_paper_reproduction_archive_interpretation = (;
            status = :archive_recorded,
            review_target = :full_local_reproduction_bundle,
            interpretation =
                :full_archive_recorded_without_publication_or_registration,
            public_exposure_support =
                :local_full_reproduction_archive_recorded,
            required_followup = :manual_publication_or_registration_by_user_only,
        ),
        caveat_docs_artifact =
            "docs/src/fitting.md#guarded-generalized-model-caveats",
        prior_jacobian_policy =
            _generalized_raw_prior_jacobian_policy(
                :gmfrm,
                blueprint.scope;
                public_fit = true,
                experimental_public = true),
        raw_prior_control_manifest =
            _generalized_raw_prior_control_manifest(
                blueprint;
                public_fit = true,
                experimental_public = true),
        fit_artifact_contract = _experimental_fit_artifact_contract(
            :gmfrm,
            blueprint.scope;
            bridge_artifact = :fit_ready_scalar_gmfrm_bridge_oracle,
            candidate_chain_study_artifact =
                "test/fixtures/gmfrm_candidate_chain_study.json",
            recovery_smoke_artifact = "test/fixtures/gmfrm_recovery_smoke.json",
            caveat_docs_artifact =
                "docs/src/fitting.md#guarded-generalized-model-caveats",
            public_fit = true,
            experimental_public = true,
            artifact_kind = :experimental_generalized_fit_artifact),
        accepted_candidate_options = _gmfrm_experimental_candidate_option_rows(),
        rejected_public_options = _gmfrm_experimental_rejected_option_rows(),
        evidence_rows,
        blocker_rows,
        summary = (;
            fit_allowed = true,
            canonical_namespace_enabled = true,
            experimental_keyword_enabled = true,
            legacy_keyword_status = :compatibility_only,
            n_evidence_done = count(row -> row.status === :done, evidence_rows),
            n_evidence_pending = count(row -> row.status === :pending, evidence_rows),
            n_evidence_blocked = count(row -> row.status === :blocked, evidence_rows),
            n_blockers = length(blocker_rows),
            next_gate = :manual_publication_or_registration_by_user_only,
        ),
    )
end

function _gmfrm_direct_parameterization_candidate(blueprint)
    return (;
        schema = "bayesianmgmfrm.gmfrm_direct_parameterization_candidate.v1",
        family = :gmfrm,
        scope = blueprint.scope,
        status = :internal_promotion_candidate,
        public_fit = false,
        fit_ready = false,
        fixture_only = blueprint.fixture_only,
        density_space = :constrained_direct,
        prior_policy = :derived_from_raw_candidate_no_direct_prior,
        jacobian_policy = :not_applicable_for_direct_likelihood,
        n_parameters = length(blueprint.constrained_parameter_names),
        parameter_names = copy(blueprint.constrained_parameter_names),
        blocks = _block_manifest_rows(
            blueprint.constrained_blocks,
            blueprint.constrained_parameter_names,
        ),
        source_transforms = _source_transform_manifest_rows(blueprint),
    )
end

function _mgmfrm_confirmatory_candidate_gate_rows()
    return [
        (gate = :confirmatory_q_mask, status = :done,
            evidence = :facet_spec_q_matrix),
        (gate = :fixed_identity_latent_correlation, status = :done,
            evidence = :mgmfrm_gauge_manifest),
        (gate = :standard_normal_ability_scale, status = :done,
            evidence = :mgmfrm_gauge_manifest),
        (gate = :positive_interpreted_loadings, status = :done,
            evidence = :log_link_q_masked_loadings),
        (gate = :source_fixture_logdensity, status = :done,
            evidence = :mgmfrm_source_fixture_logdensity),
        (gate = :bridge_source_oracle, status = :done,
            evidence = :source_mgmfrm_bridge_logdensity_fixture),
        (gate = :fit_ready_raw_transform_manifest, status = :done,
            evidence = :mgmfrm_fit_ready_candidate_transform_manifest),
        (gate = :fit_ready_pointwise_fixture, status = :done,
            evidence = :mgmfrm_confirmatory_candidate_pointwise_fixture),
        (gate = :fit_ready_bridge_pointwise_oracle, status = :done,
            evidence = :fit_ready_confirmatory_mgmfrm_bridge_oracle),
        (gate = :sampler_diagnostic_study, status = :done,
            evidence = :mgmfrm_candidate_chain_study_fixture),
        (gate = :recovery_smoke_study, status = :done,
            evidence = :mgmfrm_recovery_smoke_fixture),
        (gate = :public_fit_api, status = :done,
            evidence = :mgmfrm_experimental_public_api_decision),
    ]
end

function _mgmfrm_confirmatory_gauge_rows(design::FacetDesign)
    return [
        (gauge = :q_matrix, status = :fixed,
            value = _q_matrix_manifest(design.spec.q_matrix),
            note = :confirmatory_item_dimension_mask),
        (gauge = :latent_correlation, status = :fixed,
            value = :identity,
            note = :no_free_latent_correlation_in_first_candidate),
        (gauge = :ability_location, status = :fixed,
            value = :zero_by_dimension,
            note = :source_standard_normal_ability_distribution),
        (gauge = :ability_scale, status = :fixed,
            value = :unit_variance_by_dimension,
            note = :source_standard_normal_ability_distribution),
        (gauge = :loading_sign, status = :fixed,
            value = :positive_q_masked_loadings,
            note = :interpreted_loadings_use_log_link),
        (gauge = :source_scale, status = :fixed,
            value = 1.7,
            note = :uto_ueno_logistic_scaling_constant),
    ]
end

function _mgmfrm_confirmatory_sign_rows()
    return [
        (block = :item_dimension_discrimination,
            rule = :positive_interpreted_q_masked_loadings,
            transform = :log_link,
            status = :fixed_for_candidate),
        (block = :rater_consistency,
            rule = :positive_geometric_mean_one,
            transform = :geometric_mean_one_log_last,
            status = :fixed_for_candidate),
        (block = :rater,
            rule = :sum_to_zero,
            transform = :sum_to_zero_last,
            status = :fixed_for_candidate),
        (block = :item_steps,
            rule = :first_step_zero_sum_to_zero,
            transform = :identity_with_last_derived,
            status = :source_fixture_only),
    ]
end

function _mgmfrm_confirmatory_evidence_rows()
    return [
        (evidence = :q_matrix_manifest, status = :done,
            artifact = :model_manifest_spec_q_matrix),
        (evidence = :source_linear_predictor_fixture, status = :done,
            artifact = :mgmfrm_source_fixture_values),
        (evidence = :raw_transform_fixture, status = :done,
            artifact = :mgmfrm_source_constrained_params_from_unconstrained),
        (evidence = :bridgestan_source_oracle, status = :done,
            artifact = "test/fixtures/source_mgmfrm_bridge_logdensity.json"),
        (evidence = :fit_ready_transform_manifest, status = :done,
            artifact = :mgmfrm_confirmatory_candidate_transform_manifest),
        (evidence = :fit_ready_pointwise_fixture, status = :done,
            artifact = :mgmfrm_confirmatory_candidate_pointwise_fixture),
        (evidence = :fit_ready_bridge_pointwise_oracle, status = :done,
            artifact = "test/fixtures/source_mgmfrm_bridge_logdensity.json#confirmatory_candidate"),
        (evidence = :raw_prior_control_manifest, status = :done,
            artifact = :generalized_raw_prior_control_manifest),
        (evidence = :sampler_diagnostic_study, status = :done,
            artifact = "test/fixtures/mgmfrm_candidate_chain_study.json"),
        (evidence = :recovery_smoke_study, status = :done,
            artifact = "test/fixtures/mgmfrm_recovery_smoke.json"),
    ]
end

function _mgmfrm_confirmatory_blocker_rows()
    return NamedTuple[]
end

function _mgmfrm_experimental_candidate_option_rows()
    capability = _guarded_generalized_fit_capability(:mgmfrm)
    return [
        (option = :entrypoint, value = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
            status = :enabled_guarded_experimental,
            note = :fixed_q_confirmatory_mgmfrm_only),
        (option = :legacy_entrypoint, value = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
            status = :compatibility_only,
            note = :source_compatibility_during_namespace_migration),
        (option = :family, value = capability.family,
            status = :enabled_guarded_experimental,
            note = :confirmatory_mgmfrm_after_scalar_gmfrm),
        (option = :dimensions, value = :two_or_more,
            status = :enabled_guarded_experimental,
            note = :fixed_q_confirmatory_dimensions_two_or_more),
        (option = :q_matrix, value = :fixed_confirmatory,
            status = :enabled_guarded_experimental,
            note = :no_exploratory_loading_search),
        (option = :thresholds, value = only(capability.threshold_regimes),
            status = :enabled_guarded_experimental,
            note = :source_aligned_item_step_kernel),
        (option = :discrimination, value = only(capability.spec_discrimination),
            status = :enabled_guarded_experimental,
            note = :generic_selector_unused_q_masked_loadings_are_internal),
        (option = :validation_bias_terms, value = (),
            status = :enabled_guarded_experimental,
            note = :validation_only_not_fitted),
        (option = :anchors, value = (),
            status = :enabled_guarded_experimental,
            note = :anchor_likelihood_not_implemented),
        (option = :latent_correlation, value = :identity_fixed,
            status = :enabled_guarded_experimental,
            note = :no_rotation_or_correlation_estimation),
    ]
end

function _mgmfrm_experimental_rejected_option_rows()
    return [
        (option = :thresholds, value = :rating_scale,
            status = :blocked,
            blocker = :guarded_generalized_threshold_contract),
        (option = :discrimination, value = :nondefault_generic_selector,
            status = :blocked,
            blocker = :mgmfrm_generic_discrimination_not_implemented),
        (option = :bias_or_dff_terms, value = :model_effects,
            status = :blocked,
            blocker = :mgmfrm_dff_model_effects_not_implemented),
        (option = :anchors, value = :nonempty,
            status = :blocked,
            blocker = :generalized_anchor_likelihood_not_implemented),
        (option = :q_matrix, value = :estimated_or_free,
            status = :blocked,
            blocker = :q_matrix_selection_not_implemented),
        (option = :latent_correlation, value = :free,
            status = :blocked,
            blocker = :rotation_and_correlation_policy_missing),
        (option = :direct_scale_priors, value = :constrained_direct,
            status = :blocked,
            blocker = :raw_prior_policy_selected_for_candidate),
        (option = :sparse_design_claims, value = :enabled,
            status = :blocked_broader_claim,
            blocker = :broader_sparse_mgmfrm_claim_scope_not_promoted),
        (option = :baseline_comparison, value = :mfrm_rsm_pcm_comparison,
            status = :evidence_only_for_guarded_fit,
            blocker = :model_weight_or_superiority_claim_not_promoted),
    ]
end

function _mgmfrm_experimental_public_evidence_rows()
    return [
        (evidence = :confirmatory_gauge_manifest, status = :done,
            artifact = :mgmfrm_confirmatory_candidate),
        (evidence = :fit_ready_transform_manifest, status = :done,
            artifact = :mgmfrm_confirmatory_candidate_transform_manifest),
        (evidence = :bridgestan_fit_ready_oracle, status = :done,
            artifact = "test/fixtures/source_mgmfrm_bridge_logdensity.json#confirmatory_candidate"),
        (evidence = :candidate_chain_study, status = :done,
            artifact = "test/fixtures/mgmfrm_candidate_chain_study.json"),
        (evidence = :recovery_smoke_study, status = :done,
            artifact = "test/fixtures/mgmfrm_recovery_smoke.json"),
        (evidence = :public_caveat_docs, status = :done,
            artifact = "docs/src/fitting.md#guarded-generalized-model-caveats"),
        (evidence = :fit_artifact_manifest_for_experimental_public, status = :done,
            artifact = :experimental_public_fit_artifact_contract),
        (evidence = :baseline_comparison, status = :done,
            artifact = "test/fixtures/mgmfrm_baseline_comparison.json"),
        (evidence = :sparse_recovery_grid, status = :done,
            artifact = "test/fixtures/mgmfrm_sparse_recovery_grid.json"),
        (evidence = :guarded_fit_method_wiring, status = :done,
            artifact = "test/fixtures/mgmfrm_guarded_fit_method_wiring.json"),
        (evidence = :guarded_fit_validation_grid, status = :done,
            artifact = "test/fixtures/mgmfrm_guarded_fit_validation_grid.json"),
        (evidence = :guarded_fit_api_dry_run, status = :done,
            artifact = "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json"),
        (evidence = :guarded_local_fit_entrypoint, status = :done,
            artifact = :_fit_guarded_mgmfrm),
        (evidence = :guarded_fit_public_exposure_review, status = :done,
            artifact =
                "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json"),
        (evidence = :prediction_target_and_model_weight_policy, status = :done,
            artifact =
                "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json"),
        (evidence = :dff_estimand_validation_grid, status = :done,
            artifact = "test/fixtures/gmfrm_dff_estimand_validation_grid.json"),
        (evidence = :manuscript_scale_simulation_grid, status = :done,
            artifact =
                "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json"),
        (evidence = :full_paper_reproduction_archive, status = :done,
            artifact =
                "test/fixtures/gmfrm_full_paper_reproduction_archive.json"),
        (evidence = :direct_prior_jacobian_policy, status = :done,
            artifact = :generalized_raw_prior_jacobian_policy),
        (evidence = :raw_prior_control_manifest, status = :done,
            artifact = :generalized_raw_prior_control_manifest),
    ]
end

function _mgmfrm_experimental_public_blocker_rows()
    return NamedTuple[]
end

function _mgmfrm_experimental_public_api_decision(blueprint)
    evidence_rows = _mgmfrm_experimental_public_evidence_rows()
    blocker_rows = _mgmfrm_experimental_public_blocker_rows()
    return (;
        schema = "bayesianmgmfrm.mgmfrm_experimental_public_api_decision.v1",
        family = :mgmfrm,
        scope = blueprint.scope,
        status = :experimental_public,
        decision = :enable_guarded_experimental,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        proposed_entrypoint = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
        legacy_entrypoint = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
        public_target_label = _MGMFRM_PUBLIC_TARGET_LABEL,
        public_target_description = _MGMFRM_PUBLIC_TARGET_DESCRIPTION,
        internal_target_constructor = _MGMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        internal_sampler_diagnostic_constructor =
            _MGMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR,
        target_constructor = :_source_fixture_logdensity,
        guarded_local_entrypoint = :_fit_guarded_mgmfrm,
        guarded_local_fit_target_constructor =
            _MGMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        guarded_local_fit_sampler_diagnostic_constructor =
            _MGMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR,
        guarded_local_fit_artifact_schema =
            "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1",
        experimental_fit_artifact_schema =
            "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1",
        candidate_chain_study_artifact =
            "test/fixtures/mgmfrm_candidate_chain_study.json",
        recovery_smoke_artifact = "test/fixtures/mgmfrm_recovery_smoke.json",
        baseline_comparison_artifact =
            "test/fixtures/mgmfrm_baseline_comparison.json",
        sparse_recovery_grid_artifact =
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        guarded_fit_method_wiring_artifact =
            "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        guarded_fit_validation_grid_artifact =
            "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        guarded_fit_api_dry_run_artifact =
            "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        guarded_fit_public_exposure_review_artifact =
            "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        prediction_target_and_model_weight_policy_artifact =
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        dff_estimand_validation_grid_artifact =
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        manuscript_scale_simulation_grid_artifact =
            "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        full_paper_reproduction_archive_artifact =
            "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
        caveat_docs_artifact =
            "docs/src/fitting.md#guarded-generalized-model-caveats",
        prior_jacobian_policy =
            _generalized_raw_prior_jacobian_policy(
                :mgmfrm,
                blueprint.scope;
                public_fit = true,
                experimental_public = true),
        raw_prior_control_manifest =
            _generalized_raw_prior_control_manifest(
                blueprint;
                public_fit = true,
                experimental_public = true),
        fit_artifact_contract = _experimental_fit_artifact_contract(
            :mgmfrm,
            blueprint.scope;
            bridge_artifact =
                "test/fixtures/source_mgmfrm_bridge_logdensity.json#confirmatory_candidate",
            candidate_chain_study_artifact =
                "test/fixtures/mgmfrm_candidate_chain_study.json",
            recovery_smoke_artifact = "test/fixtures/mgmfrm_recovery_smoke.json",
            caveat_docs_artifact =
                "docs/src/fitting.md#guarded-generalized-model-caveats",
            public_fit = true,
            experimental_public = true,
            artifact_kind = :experimental_generalized_fit_artifact),
        accepted_candidate_options = _mgmfrm_experimental_candidate_option_rows(),
        rejected_public_options = _mgmfrm_experimental_rejected_option_rows(),
        guarded_fit_public_exposure_review_interpretation = (;
            status = :review_recorded,
            review_target = :confirmatory_mgmfrm_guarded_fit_public_exposure,
            interpretation =
                :guarded_mgmfrm_public_exposure_review_recorded_enable_guarded_experimental,
            public_exposure_support =
                :supports_fixed_q_confirmatory_mgmfrm_experimental_fit,
            required_followup =
                :satisfied_by_prediction_target_and_model_weight_policy,
        ),
        prediction_target_and_model_weight_policy_interpretation = (;
            status = :policy_recorded,
            review_target =
                :guarded_scalar_gmfrm_and_confirmatory_mgmfrm_claim_boundaries,
            interpretation =
                :heldout_kfold_selected_enable_guarded_mgmfrm_fit_without_weight_claims,
            public_exposure_support =
                :guarded_confirmatory_mgmfrm_fit_enabled_no_weight_claims,
            required_followup = :manual_publication_or_registration_by_user_only,
        ),
        evidence_rows,
        blocker_rows,
        summary = (;
            fit_allowed = true,
            canonical_namespace_enabled = true,
            experimental_keyword_enabled = true,
            legacy_keyword_status = :compatibility_only,
            n_evidence_done = count(row -> row.status === :done, evidence_rows),
            n_evidence_pending = count(row -> row.status === :pending, evidence_rows),
            n_evidence_blocked = count(row -> row.status === :blocked, evidence_rows),
            n_blockers = length(blocker_rows),
            next_gate = :manual_publication_or_registration_by_user_only,
        ),
    )
end

function _mgmfrm_confirmatory_candidate(blueprint, design::FacetDesign)
    evidence_rows = _mgmfrm_confirmatory_evidence_rows()
    blocker_rows = _mgmfrm_confirmatory_blocker_rows()
    return (;
        schema = "bayesianmgmfrm.mgmfrm_confirmatory_candidate.v1",
        family = :mgmfrm,
        scope = blueprint.scope,
        status = blueprint.status,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        fixture_only = blueprint.fixture_only,
        source_fixture_only = false,
        compiler_stage = blueprint.compiler_stage,
        source_oracle = :mgmfrm_source_aligned,
        fit_ready_transform_ready = true,
        fit_ready_pointwise_oracle_ready = true,
        dimensions = design.spec.dimensions,
        q_matrix = _q_matrix_manifest(design.spec.q_matrix),
        latent_correlation = :identity_fixed,
        ability_location = :zero_by_dimension,
        ability_scale = :unit_variance_by_dimension,
        source_scale = 1.7,
        interpreted_loading_sign = :positive,
        raw_parameter_names = copy(blueprint.parameter_names),
        raw_blocks = _block_manifest_rows(blueprint.blocks, blueprint.parameter_names),
        constrained_parameter_names = copy(blueprint.constrained_parameter_names),
        constrained_blocks = _block_manifest_rows(
            blueprint.constrained_blocks,
            blueprint.constrained_parameter_names,
        ),
        raw_prior_control_manifest =
            _generalized_raw_prior_control_manifest(
                blueprint;
                public_fit = true,
                experimental_public = true),
        gauge_rows = _mgmfrm_confirmatory_gauge_rows(design),
        sign_positive_rules = _mgmfrm_confirmatory_sign_rows(),
        evidence_rows,
        blocker_rows,
        candidate_gates = _mgmfrm_confirmatory_candidate_gate_rows(),
        experimental_public_api_decision =
            _mgmfrm_experimental_public_api_decision(blueprint),
        summary = (;
            candidate_frozen = true,
            fit_allowed = true,
            n_evidence_done = count(row -> row.status === :done, evidence_rows),
            n_evidence_pending = count(row -> row.status === :pending, evidence_rows),
            n_blockers = length(blocker_rows),
            next_gate = :manual_publication_or_registration_by_user_only,
        ),
    )
end

function _raw_parameterization_promotion_candidate(blueprint)
    blueprint.family === :gmfrm || return nothing
    return (;
        schema = "bayesianmgmfrm.gmfrm_promotion_candidate.v1",
        family = :gmfrm,
        scope = blueprint.scope,
        status = :internal_promotion_candidate,
        public_fit = false,
        fit_ready = false,
        fixture_only = blueprint.fixture_only,
        compiler_stage = blueprint.compiler_stage,
        source_oracle = :scalar_gmfrm_source_aligned,
        transform_ready = true,
        logdensity_ready = true,
        bridge_oracle_ready = true,
        bridge_direct_ready = true,
        direct_pointwise_ready = true,
        sampler_smoke_ready = true,
        production_diagnostics_ready = true,
        candidate_chain_study_ready = true,
        stress_chain_grid_ready = true,
        recovery_smoke_ready = true,
        baseline_comparison_ready = true,
        baseline_calibration_grid_ready = true,
        interval_decision_grid_ready = true,
        sparse_design_grid_ready = true,
        waic_influence_review_ready = true,
        psis_loo_review_ready = true,
        exact_loo_or_kfold_review_ready = true,
        guarded_exposure_review_ready = true,
        guarded_fit_api_dry_run_ready = true,
        guarded_fit_method_wiring_ready = true,
        experimental_fit_validation_grid_ready = true,
        posterior_predictive_grid_ready = true,
        sparse_pathology_recovery_grid_ready = true,
        prior_likelihood_sensitivity_grid_ready = true,
        real_data_case_study_ready = true,
        claim_recovery_reproduction_archive_ready = true,
        broader_experimental_exposure_decision_review_ready = true,
        fit_ready_compiler_ready = true,
        experimental_public_ready = true,
        public_target_label = _GMFRM_PUBLIC_TARGET_LABEL,
        public_target_description = _GMFRM_PUBLIC_TARGET_DESCRIPTION,
        internal_target_constructor = _GMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        internal_diagnostic_constructor =
            _GMFRM_INTERNAL_GRADIENT_DIAGNOSTIC_CONSTRUCTOR,
        internal_sampler_diagnostic_constructor =
            _GMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR,
        rater_step_public_option_policy =
            _gmfrm_rater_step_public_option_policy(blueprint),
        item_discrimination_promotion_decision =
            _gmfrm_item_discrimination_promotion_decision(blueprint),
        target_constructor = _GMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        diagnostic_constructor = _GMFRM_INTERNAL_GRADIENT_DIAGNOSTIC_CONSTRUCTOR,
        sampler_diagnostic_constructor =
            _GMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR,
        pointwise_fixture_constructor = :_gmfrm_promotion_candidate_pointwise_fixture,
        compiler_blueprint_constructor = :_gmfrm_fit_ready_candidate_blueprint,
        density_space = :raw_unconstrained,
        prior_policy = :independent_normal_raw_coordinates,
        jacobian_policy = :none_raw_coordinate_density,
        raw_prior_control_manifest =
            _generalized_raw_prior_control_manifest(blueprint),
        n_raw_parameters = blueprint.n_parameters,
        raw_parameter_names = copy(blueprint.parameter_names),
        raw_blocks = _block_manifest_rows(blueprint.blocks, blueprint.parameter_names),
        fit_ready_compiler = _gmfrm_fit_ready_compiler_candidate(blueprint),
        direct_parameterization = _gmfrm_direct_parameterization_candidate(blueprint),
        experimental_public_api =
            _gmfrm_experimental_public_api_decision(blueprint),
        candidate_gates = _promotion_candidate_gate_rows(:gmfrm),
    )
end

function _raw_parameterization_manifest(design::FacetDesign)
    if design.spec.family === :gmfrm
        source_blueprint = _gmfrm_source_unconstrained_blueprint(design)
        candidate_blueprint = _gmfrm_fit_ready_candidate_blueprint(design)
        confirmatory_candidate = nothing
    elseif design.spec.family === :mgmfrm
        source_blueprint = _mgmfrm_source_unconstrained_blueprint(design)
        candidate_blueprint = _mgmfrm_fit_ready_candidate_blueprint(design)
        confirmatory_candidate = _mgmfrm_confirmatory_candidate(candidate_blueprint, design)
    else
        return nothing
    end
    return (;
        schema = "bayesianmgmfrm.raw_parameterization.v1",
        family = source_blueprint.family,
        status = :internal_source_fixture,
        public_fit = false,
        fit_ready = source_blueprint.fit_ready,
        fixture_only = source_blueprint.fixture_only,
        density_space = :raw_unconstrained,
        prior_policy = :independent_normal_raw_coordinates,
        jacobian_policy = :none_raw_coordinate_density,
        n_raw_parameters = source_blueprint.n_parameters,
        raw_parameter_names = copy(source_blueprint.parameter_names),
        constrained_parameter_names = copy(source_blueprint.constrained_parameter_names),
        raw_blocks = _block_manifest_rows(source_blueprint.blocks, source_blueprint.parameter_names),
        constrained_blocks = _block_manifest_rows(
            source_blueprint.constrained_blocks,
            source_blueprint.constrained_parameter_names,
        ),
        transforms = _source_transform_manifest_rows(source_blueprint),
        promotion_candidate = _raw_parameterization_promotion_candidate(candidate_blueprint),
        confirmatory_candidate,
    )
end

function _design_manifest(design::FacetDesign)
    return (;
        n_parameters = length(design.parameter_names),
        parameter_names = copy(design.parameter_names),
        blocks = _design_block_rows(design),
        constraints = constraint_table(design),
        identification_declarations = identification_declarations(design),
        identification = _namedtuple_from_pairs([
            block => design.identification[block]
            for block in sort(collect(keys(design.identification)); by = string)
        ]),
        raw_parameterization = _raw_parameterization_manifest(design),
    )
end

"""
    model_manifest(data_or_spec_or_design)

Return a serializable, report-ready manifest for `FacetData`, `FacetSpec`, or
`FacetDesign`. The manifest records facet roles, level maps, category scale,
validation status, threshold structure, deterministic parameter names, block
ranges, identification rules, and data signatures. It is intended as the stable
provenance contract for future cached fits, reports, and HMC/GMFRM/MGMFRM
extensions.
"""
function model_manifest(data::FacetData)
    return (;
        schema = "bayesianmgmfrm.model_manifest.v1",
        object = :data,
        data = _data_manifest(data),
        rating_design = rating_design_audit(data),
    )
end

function model_manifest(spec::FacetSpec)
    _require_current_facet_spec(spec, "model_manifest")
    spec_manifest = _spec_manifest(spec)
    return (;
        schema = "bayesianmgmfrm.model_manifest.v1",
        object = :spec,
        status_policy = spec_manifest.status_policy,
        data = _data_manifest(spec.data),
        validation = _validation_manifest(spec.validation),
        spec = spec_manifest,
        rating_design = rating_design_audit(spec),
    )
end

function model_manifest(design::FacetDesign)
    _require_canonical_design(design, "model_manifest")
    spec = design.spec
    spec_manifest = _spec_manifest(spec)
    return (;
        schema = "bayesianmgmfrm.model_manifest.v1",
        object = :design,
        status_policy = spec_manifest.status_policy,
        data = _data_manifest(spec.data),
        validation = _validation_manifest(spec.validation),
        spec = spec_manifest,
        design = _design_manifest(design),
        design_identity = design_identity(design),
        model_surface_audit = model_surface_audit(design),
        rating_design = rating_design_audit(design),
    )
end

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
