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
plus optional facet vectors such as `group`, `task`, `form`, or `occasion` when
present. Pass `observations` to materialize a selected row order, for example a
training or heldout row set from [`kfold_plan`](@ref).

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
"""
function anchor_linking_summary(data_or_spec; unit::Symbol = :person_item,
        min_shared_units::Int = 1,
        sensitivity_rows = nothing)
    min_shared_units >= 1 ||
        throw(ArgumentError("min_shared_units must be positive"))
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
            scope = :scalar_gmfrm_guarded_experimental,
            dimensions = "1",
            discrimination = (:rater,),
            threshold_regimes = (:rating_scale, :partial_credit),
            estimation_status = :experimental_public,
            public_fit = true,
            experimental_public = true,
            identification = (:item_discrimination_product_constraint, :rater_consistency_positive, :rater_step_constraints),
            note = "guarded scalar rater-discrimination GMFRM through fit(spec; experimental = true)",
        ),
        (;
            family = :mgmfrm,
            scope = :fixed_q_confirmatory_mgmfrm_guarded_experimental,
            dimensions = "2",
            discrimination = (:item_dimension_discrimination, :rater_consistency),
            threshold_regimes = (:partial_credit,),
            estimation_status = :experimental_public,
            public_fit = true,
            experimental_public = true,
            identification = (:fixed_confirmatory_q_mask, :identity_latent_correlation, :standard_normal_ability_scale, :positive_q_masked_loadings),
            note = "guarded fixed-Q two-dimensional confirmatory MGMFRM through fit(spec; experimental = true)",
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
            entrypoint = "fit(spec; experimental = true)",
            experimental_public = true,
            public_fit = true,
            claim_scope = :guarded_scalar_rater_discrimination_only,
            note = "guarded scalar rater-discrimination GMFRM, without broader generalized claims",
        ),
        (;
            surface = :fixed_q_confirmatory_mgmfrm_guarded_experimental,
            family = :mgmfrm,
            scope = :minimal_confirmatory_mgmfrm_candidate,
            status = :guarded_experimental_public,
            entrypoint = "fit(spec; experimental = true)",
            experimental_public = true,
            public_fit = true,
            claim_scope = :fixed_q_two_dimensional_confirmatory_only,
            note = "guarded fixed-Q confirmatory MGMFRM, without model-weight or sparse-superiority claims",
        ),
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
fit-cache and reproduction-manifest guardrails.

This is a release-scope guardrail, not a statistical validation result and not a
publication or registration action.
"""
function release_scope_summary(; include_evidence::Bool = false)
    fit_surfaces = _release_scope_fit_surface_rows()
    blocked_options = _release_scope_blocked_option_rows()
    blocked_claims = _release_scope_blocked_claim_rows()
    evidence_rows = include_evidence ? _release_scope_evidence_rows() : NamedTuple[]
    return (;
        schema = "bayesianmgmfrm.release_scope_summary.v1",
        object = :release_scope_summary,
        status = :scope_recorded,
        public_fit_surfaces = fit_surfaces,
        blocked_public_options = blocked_options,
        blocked_claims,
        evidence_rows,
        summary = (;
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
            broader_generalized_fit_allowed = false,
            dff_model_effects_allowed = false,
            model_weight_claims_allowed = false,
            sparse_superiority_claims_allowed = false,
            publication_or_registration_action = false,
            next_gate = :manual_publication_or_registration_by_user_only,
        ),
    )
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

function _check_dimensions(family::Symbol, dimensions::Int)
    dimensions >= 1 || throw(ArgumentError("dimensions must be positive"))
    family === :mfrm && dimensions == 1 ||
        family !== :mfrm ||
        throw(ArgumentError("family = :mfrm currently requires dimensions = 1"))
    family === :gmfrm && dimensions == 1 ||
        family !== :gmfrm ||
        throw(ArgumentError("family = :gmfrm currently represents one-dimensional generalized MFRM configurations"))
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

function _normalize_q_matrix(data::FacetData, family::Symbol, dimensions::Int, q_matrix)
    if family !== :mgmfrm
        q_matrix === nothing || throw(ArgumentError("q_matrix is only accepted for family = :mgmfrm"))
        return nothing
    end
    q_matrix === nothing &&
        throw(ArgumentError("family = :mgmfrm requires a confirmatory q_matrix"))
    q_matrix isa AbstractMatrix ||
        throw(ArgumentError("q_matrix must be a two-dimensional matrix"))
    mat = Matrix{Bool}(q_matrix)
    size(mat, 1) == length(data.item_levels) ||
        throw(ArgumentError("q_matrix must have one row per item"))
    size(mat, 2) == dimensions ||
        throw(ArgumentError("q_matrix must have one column per dimension"))
    for item in axes(mat, 1)
        any(@view mat[item, :]) ||
            throw(ArgumentError("each q_matrix row must load on at least one dimension"))
    end
    for dim in axes(mat, 2)
        any(@view mat[:, dim]) ||
            throw(ArgumentError("each q_matrix dimension must have at least one item"))
    end
    return mat
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
              q_matrix = nothing, bias = Tuple{Symbol,Symbol}[],
              anchors = NamedTuple[], min_cell_count = 2,
              validation_report = nothing)

Construct a many-facet measurement specification after validation errors are
resolved. The default `family = :mfrm`, `dimensions = 1`, and
`discrimination = :none` path is the minimal MFRM/RSM/PCM slice supported by
`getdesign` and `fit`. GMFRM/MGMFRM configurations can be represented for
manifest and constraint review, but have `estimation_status = :specified_only`
until their likelihoods and identification checks are implemented.
"""
function mfrm_spec(data::FacetData;
        thresholds::Symbol = :partial_credit,
        family::Symbol = :mfrm,
        dimensions::Int = 1,
        discrimination::Symbol = :none,
        q_matrix = nothing,
        bias = Tuple{Symbol,Symbol}[],
        anchors = NamedTuple[],
        min_cell_count::Int = 2,
        validation_report::Union{Nothing,ValidationReport} = nothing)
    thresholds in (:rating_scale, :partial_credit) ||
        throw(ArgumentError("thresholds must be :rating_scale or :partial_credit"))
    checked_family = _check_family(family)
    checked_dimensions = _check_dimensions(checked_family, dimensions)
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
    checked_q_matrix = _normalize_q_matrix(data, checked_family, checked_dimensions, q_matrix)
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
        "person[$(person),dim=$(dim)]"
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
        push!(names, "item_dimension_discrimination[item=$(item),dim=$(dim)]")
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
        push!(indices, index_by_name["item_dimension_discrimination[item=$(item),dim=$(dim)]"])
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
    for block in (:person, :rater, :item, :item_discrimination, :rater_consistency, :rater_steps)
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

function _check_mgmfrm_source_fixture_design(design::FacetDesign, caller::AbstractString)
    design.spec.family === :mgmfrm &&
        design.spec.estimation_status === :specified_only ||
        throw(ArgumentError("$caller is only for specified-only MGMFRM preview designs"))
    for block in (:person, :rater, :item, :item_dimension_discrimination, :rater_consistency, :item_steps)
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

function _mgmfrm_source_pointwise_loglikelihood(design::FacetDesign, params::AbstractVector)
    _check_mgmfrm_source_fixture_design(design, "_mgmfrm_source_pointwise_loglikelihood")
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
        discrimination = spec.discrimination,
        q_matrix = _q_matrix_manifest(spec.q_matrix),
        validation_bias_terms = copy(spec.validation_bias_terms),
        anchors = copy(spec.anchors),
        estimation_status = spec.estimation_status,
        required_facets = (:person, :rater, :item),
        optional_facets = sort(collect(keys(spec.data.optional)); by = string),
        equation = model_equation(spec),
        identification_declarations = identification_declarations(spec),
        constraints = constraint_table(spec),
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
preview designs report internal raw and constrained fit-ready candidate blocks,
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
`public_fit = true`. Specified-only GMFRM/MGMFRM previews report the internal
candidate parameterization without enabling broad public fitting. For
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
    return [
        (option = :entrypoint, value = "fit(spec; experimental = true)",
            status = :enabled_guarded,
            note = :scalar_gmfrm_only),
        (option = :family, value = :gmfrm,
            status = :candidate_only,
            note = :scalar_gmfrm_before_mgmfrm),
        (option = :dimensions, value = 1,
            status = :candidate_only,
            note = :one_dimensional_only),
        (option = :discrimination, value = :rater,
            status = :candidate_only,
            note = :source_aligned_scalar_gmfrm_fixture),
        (option = :density_space, value = :raw_unconstrained,
            status = :candidate_only,
            note = :raw_coordinate_prior_contract_required),
    ]
end

function _gmfrm_experimental_rejected_option_rows()
    return [
        (option = :family, value = :mgmfrm,
            status = :blocked,
            blocker = :mgmfrm_baseline_sparse_prior_policy_pending),
        (option = :dimensions, value = :multidimensional,
            status = :blocked,
            blocker = :mgmfrm_public_scope_not_promoted),
        (option = :direct_scale_priors, value = :constrained_direct,
            status = :blocked,
            blocker = :raw_prior_policy_selected_for_candidate),
        (option = :bias_or_dff_terms, value = :model_effects,
            status = :blocked,
            blocker = :dff_model_effect_fit_policy_not_promoted),
        (option = :hierarchical_rater_thresholds, value = :enabled,
            status = :blocked,
            blocker = :pooling_and_identification_policy_missing),
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
        (field = :density_space, status = :required,
            note = :raw_unconstrained_or_documented_direct_policy),
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
        proposed_entrypoint = "fit(spec; experimental = true)",
        target_constructor = :_gmfrm_promotion_candidate_logdensity,
        sampler_diagnostic_constructor =
            :_gmfrm_promotion_candidate_sampler_diagnostics,
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
            experimental_keyword_enabled = true,
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
    return [
        (option = :entrypoint, value = "fit(spec; experimental = true)",
            status = :enabled_guarded_experimental,
            note = :fixed_q_confirmatory_mgmfrm_only),
        (option = :family, value = :mgmfrm,
            status = :enabled_guarded_experimental,
            note = :confirmatory_mgmfrm_after_scalar_gmfrm),
        (option = :dimensions, value = 2,
            status = :enabled_guarded_experimental,
            note = :two_dimensional_fixed_q_smoke_only),
        (option = :q_matrix, value = :fixed_confirmatory,
            status = :enabled_guarded_experimental,
            note = :no_exploratory_loading_search),
        (option = :latent_correlation, value = :identity_fixed,
            status = :enabled_guarded_experimental,
            note = :no_rotation_or_correlation_estimation),
    ]
end

function _mgmfrm_experimental_rejected_option_rows()
    return [
        (option = :q_matrix, value = :estimated_or_free,
            status = :blocked,
            blocker = :q_matrix_selection_not_implemented),
        (option = :latent_correlation, value = :free,
            status = :blocked,
            blocker = :rotation_and_correlation_policy_missing),
        (option = :dimensions, value = :greater_than_two,
            status = :blocked,
            blocker = :gauge_and_recovery_scope_not_validated),
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
        proposed_entrypoint = "fit(spec; experimental = true)",
        target_constructor = :_source_fixture_logdensity,
        guarded_local_entrypoint = :_fit_guarded_mgmfrm,
        guarded_local_fit_target_constructor =
            :_mgmfrm_guarded_local_fit_logdensity,
        guarded_local_fit_sampler_diagnostic_constructor =
            :_mgmfrm_guarded_local_fit_sampler_diagnostics,
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
            experimental_keyword_enabled = true,
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
        target_constructor = :_gmfrm_promotion_candidate_logdensity,
        diagnostic_constructor = :_gmfrm_promotion_candidate_diagnostics,
        sampler_diagnostic_constructor =
            :_gmfrm_promotion_candidate_sampler_diagnostics,
        pointwise_fixture_constructor = :_gmfrm_promotion_candidate_pointwise_fixture,
        compiler_blueprint_constructor = :_gmfrm_fit_ready_candidate_blueprint,
        density_space = :raw_unconstrained,
        prior_policy = :independent_normal_raw_coordinates,
        jacobian_policy = :none_raw_coordinate_density,
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
    )
end

function model_manifest(spec::FacetSpec)
    return (;
        schema = "bayesianmgmfrm.model_manifest.v1",
        object = :spec,
        data = _data_manifest(spec.data),
        validation = _validation_manifest(spec.validation),
        spec = _spec_manifest(spec),
    )
end

function model_manifest(design::FacetDesign)
    spec = design.spec
    return (;
        schema = "bayesianmgmfrm.model_manifest.v1",
        object = :design,
        data = _data_manifest(spec.data),
        validation = _validation_manifest(spec.validation),
        spec = _spec_manifest(spec),
        design = _design_manifest(design),
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

"""
    pointwise_loglikelihood(design::FacetDesign, params)

Evaluate the minimal additive RSM/PCM pointwise log likelihood for the
identified parameter vector returned by `getdesign`. This helper is for design
validation and does not apply Bayesian priors.
"""
function pointwise_loglikelihood(design::FacetDesign, params::AbstractVector)
    _check_fit_supported_mfrm(design, "pointwise_loglikelihood")
    _check_parameter_vector_length(design, params)
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
