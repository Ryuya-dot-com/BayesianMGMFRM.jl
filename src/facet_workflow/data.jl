
"""
    FacetData(table; person, rater, item, score, group = nothing, task = nothing,
              form = nothing, occasion = nothing, response_id = nothing,
              testlet_id = nothing, category_levels = nothing,
              missing_policy = :error)

Prepare a table of observed ratings for analysis. Each row is one person's
score on one item from one rater. Pass column names as Julia symbols, such as
`person = :student`; the example below uses a named tuple of column vectors.
For responses without a rater facet, explicitly pass `rater = nothing`; no
rater column is needed. Use the scalar unit-slope `mfrm_spec` entry: binary
categories `0:1` give Rasch/1PL, and ordered categories give PCM or RSM.
The synthetic single `"no_rater"` reference has fixed zero severity and no free
rater parameter. It is not an observed judge. `data.columns.rater === nothing`
records this choice; rater anchors and rater bias terms are not applicable.
Use `category_levels` to preserve the complete intended consecutive integer
score scale, even if a category was not observed. Missing ratings are not score zero. By default,
missing required values are rejected, and `missing_policy = :error` is the
only supported policy. Decide how to handle missing ratings before constructing
the table, preserving a record of any exclusions.

Return a `FacetData` object. `data.n` is the retained number of rating rows,
and `data.person_levels`, `data.item_levels`, `data.rater_levels` and
`data.category_levels` give their labels and ordering. Creating the object
does not validate the measurement design or estimate parameters; call
[`validate_design`](@ref) next.

# Examples

This artificial panel illustrates input syntax, not an adequate study size.
It requires only this package and runs no sampler.

```jldoctest
julia> using BayesianMGMFRM

julia> ratings = (student = ["P1", "P1", "P1", "P1", "P2", "P2", "P2", "P2"],
                  item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
                  rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
                  score = [0, 1, 2, 0, 1, 2, 0, 2]);

julia> data = FacetData(ratings; person = :student, item = :item,
                       rater = :rater, score = :score, category_levels = 0:2);

julia> (data.n, length(data.person_levels), length(data.category_levels))
(8, 2, 3)

julia> report = validate_design(data); report.passed
true

julia> spec = mfrm_spec(data; prior = :default, validation_report = report);

julia> spec isa AbstractMFRMSpec
true
```

`report.passed` means no blocking design errors were found; inspect
`report.issues` for warnings. It does not establish model adequacy or precision.
See also [`mfrm_spec`](@ref) and [`facet_response_table`](@ref).

# Extended help

The object encodes labels as deterministic integer indexes. Optional columns are
stored as indexed metadata; supplying them does not add fitted model terms.
Use `response_id` for a globally unique scored response and `testlet_id` for
its declared task or item-cluster identity. `occasion` remains categorical
metadata; its encoded index must not be interpreted as elapsed time or row
sequence. By default, the ordinal scale is the contiguous integer range from
the minimum through maximum observed score. Pass `category_levels`, such as
`0:4`, to preserve an intended consecutive integer scale when the realized
data omit an endpoint or another structurally possible category.
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
category and facet counts, graph components, item/category and boundary-pattern
warnings, requested DFF cell counts, and data signatures used to prevent stale
report reuse.
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

# Validation results compare their contents, including signatures for stale-data checks.
_validation_fields(x::Union{ValidationIssue,ValidationReport}) =
    ntuple(i -> getfield(x, i), fieldcount(typeof(x)))
function _validation_equal(x, y)::Bool
    x === y && return true
    (ismissing(x) || ismissing(y)) && return false
    x isa Real && y isa Real && return (isnan(x) && isnan(y)) || (x == y)
    x isa Complex && y isa Complex && return _validation_equal(real(x), real(y)) && _validation_equal(imag(x), imag(y))
    if x isa AbstractDict && y isa AbstractDict
        length(x) == length(y) || return false
        return all(((k, v),) -> haskey(y, k) && _validation_equal(v, y[k]), pairs(x))
    end
    if (x isa Tuple && y isa Tuple) || (x isa AbstractArray && y isa AbstractArray && axes(x) == axes(y))
        length(x) == length(y) || return false
        return all(i -> _validation_equal(x[i], y[i]), eachindex(x, y))
    end
    if x isa NamedTuple && y isa NamedTuple
        return keys(x) == keys(y) && _validation_equal(Tuple(x), Tuple(y))
    end
    eq = (x == y)
    return eq isa Bool ? eq : false
end
for T in (ValidationIssue, ValidationReport)
    @eval begin
        Base.:(==)(a::$T, b::$T) = _validation_equal(_validation_fields(a), _validation_fields(b))
        Base.isequal(a::$T, b::$T) = isequal(_validation_fields(a), _validation_fields(b))
        Base.hash(x::$T, h::UInt) = hash(_validation_fields(x), hash($T, h))
    end
end

"""
    FacetSpec

Compatibility specification for reference-coded `0.1.x` workflows, available as
`BayesianMGMFRM.Legacy.FacetSpec` (also `BayesianMGMFRM.FacetSpec`). Use
[`AbstractMFRMSpec`](@ref) for type annotations covering standard v0.2 models.
To build a standard isometric specification from `FacetData`, pass
`mfrm_spec(data; prior = :default)`. The legacy object can hold GMFRM/MGMFRM
configuration intent for design inspection. A narrower scalar-GMFRM and
fixed-Q confirmatory MGMFRM subset is available through the explicitly limited
`BayesianMGMFRM.Experimental.fit(spec)` entrypoint; broader represented
configurations remain inspection-only.

Display `spec` at the Julia prompt, or use `show(stdout, MIME"text/plain"(), spec)`
in a script, to read its slopes, step ownership, validation-only terms and fitting
entry. This display uses the existing model contract without fitting a model.
"""
struct FacetSpec <: AbstractMFRMSpec
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

Compatibility design object with deterministic parameter names and block ranges,
available as `Legacy.FacetDesign`. Standard specifications are inspected with
`design_summary` and `validate_design`.
Stable MFRM/RSM/PCM designs use either default first-level references or
declared exact individual hard anchors for rater and item blocks, plus
sum-to-zero threshold steps. GMFRM/MGMFRM preview designs expose their
declared raw and constrained parameter layouts for inspection; only the narrow
subset accepted by `BayesianMGMFRM.Experimental.fit(spec)` is numerically
available, and that limited entrypoint does not make the preview compiler a
stable generalized fitting API.
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
    column = try
        getindex(table, args...)
    catch err
        if err isa MethodError
            _is_missing_getindex_method(err, table, args) || rethrow()
            return nothing
        end
        _is_column_lookup_error(err) || rethrow()
        return nothing
    end
    return collect(column)
end

function _dict_lookup_column(d::AbstractDict, name::Symbol)
    matches = [k for k in Base.keys(d) if (k isa Union{Symbol, AbstractString}) && Symbol(k) === name]
    length(matches) > 1 && throw(ArgumentError("table contains duplicate column keys for :$name"))
    length(matches) == 1 || throw(ArgumentError("column :$name was not found"))
    return d[only(matches)]
end

function _column(table, name::Symbol)
    if table isa AbstractDict
        return collect(_dict_lookup_column(table, name))
    end
    if table isa AbstractVector
        if !isempty(table) && first(table) isa NamedTuple
            all(r -> r isa NamedTuple && haskey(r, name), table) ||
                throw(ArgumentError("column :$name was not found"))
            return [getfield(r, name) for r in table]
        elseif !isempty(table) && first(table) isa AbstractDict
            all(r -> r isa AbstractDict, table) || throw(ArgumentError("column :$name was not found"))
            return [_dict_lookup_column(r, name) for r in table]
        elseif isempty(table) && isconcretetype(eltype(table)) && eltype(table) <: NamedTuple
            name in fieldnames(eltype(table)) || throw(ArgumentError("column :$name was not found"))
            return fieldtype(eltype(table), name)[]
        end
        throw(ArgumentError("column :$name was not found"))
    end
    table isa AbstractArray && throw(ArgumentError("column :$name was not found"))
    if hasproperty(table, name)
        return collect(getproperty(table, name))
    end
    table isa NamedTuple && throw(ArgumentError("column :$name was not found"))
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

function _normalize_category_levels(category_levels)
    raw_levels = try
        collect(category_levels)
    catch
        throw(ArgumentError(
            "category_levels must be an iterable of consecutive integer scores; " *
            "got $(repr(category_levels))",
        ))
    end
    levels = [_score_to_int(level, :category_levels) for level in raw_levels]
    length(levels) >= 2 || throw(ArgumentError(
        "category_levels must contain at least two ordered categories"))
    length(unique(levels)) == length(levels) || throw(ArgumentError(
        "category_levels must not contain duplicate scores"))
    issorted(levels) || throw(ArgumentError(
        "category_levels must be in strictly increasing order"))
    levels == collect(first(levels):last(levels)) || throw(ArgumentError(
        "category_levels must contain consecutive integer scores"))
    return levels
end

function _encode_scores(col, name::Symbol, intended_levels)
    scores = [_score_to_int(x, name) for x in col]
    levels = intended_levels === nothing ?
        (isempty(scores) ? Int[] : collect(minimum(scores):maximum(scores))) :
        _normalize_category_levels(intended_levels)
    outside = sort!(unique([score for score in scores if score ∉ levels]))
    isempty(outside) || throw(ArgumentError(
        "column :$name contains score value(s) outside category_levels: $outside"))
    index = Dict{Int,Int}(level => i for (i, level) in pairs(levels))
    return scores, [index[x] for x in scores], levels
end

function FacetData(table;
        person::Symbol,
        rater::Union{Nothing,Symbol},
        item::Symbol,
        score::Symbol,
        group::Union{Nothing,Symbol} = nothing,
        task::Union{Nothing,Symbol} = nothing,
        form::Union{Nothing,Symbol} = nothing,
        occasion::Union{Nothing,Symbol} = nothing,
        response_id::Union{Nothing,Symbol} = nothing,
        testlet_id::Union{Nothing,Symbol} = nothing,
        category_levels = nothing,
        missing_policy::Symbol = :error)
    missing_policy in (:error, :drop_with_audit) ||
        throw(ArgumentError("missing_policy must be :error or :drop_with_audit (got $(repr(missing_policy)))"))

    person_col = _column(table, person)
    n_input = length(person_col)
    rater_col = rater === nothing ? fill("no_rater", n_input) : _column(table, rater)
    item_col = _column(table, item)
    score_col = _column(table, score)
    _check_length!(n_input, rater_col, something(rater, :rater))
    _check_length!(n_input, item_col, item)
    _check_length!(n_input, score_col, score)

    opt_raw = Vector{Tuple{Symbol,Symbol,Any}}()
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
        _check_length!(n_input, col, column)
        push!(opt_raw, (role, column, col))
    end

    missing_audit = nothing
    if missing_policy === :drop_with_audit
        keep = trues(n_input)
        dropped_by_column = Dict{Symbol,Int}()
        check_cols = Tuple{Symbol,Any}[(person, person_col), (item, item_col), (score, score_col)]
        rater === nothing || push!(check_cols, (rater, rater_col))
        for (_, column, col) in opt_raw
            push!(check_cols, (column, col))
        end
        for (cname, col) in check_cols
            cnt = 0
            for idx in 1:n_input
                v = col[idx]
                if ismissing(v) || v === nothing
                    keep[idx] = false
                    cnt += 1
                end
            end
            cnt > 0 && (dropped_by_column[cname] = cnt)
        end
        dropped_rows = findall(!, keep)
        n_dropped = length(dropped_rows)
        if n_dropped > 0
            @warn "FacetData(missing_policy = :drop_with_audit) dropped $n_dropped of $n_input row(s) containing missing/nothing values; inspect data.columns.missing_audit." dropped_by_column=dropped_by_column
            person_col = person_col[keep]
            rater_col = rater_col[keep]
            item_col = item_col[keep]
            score_col = score_col[keep]
            opt_raw = [(role, column, col[keep]) for (role, column, col) in opt_raw]
        end
        missing_audit = (;
            policy = :drop_with_audit,
            n_input_rows = n_input,
            n_dropped_rows = n_dropped,
            n_retained_rows = n_input - n_dropped,
            dropped_rows,
            dropped_by_column,
        )
    end
    n = length(person_col)

    person_index, person_levels = _encode_levels(person_col, person)
    rater_index, rater_levels = _encode_levels(rater_col, something(rater, :rater))
    item_index, item_levels = _encode_levels(item_col, item)
    scores, category_index, checked_category_levels =
        _encode_scores(score_col, score, category_levels)

    optional = Dict{Symbol,Vector{Int}}()
    optional_levels = Dict{Symbol,Vector{Any}}()
    optional_columns = Dict{Symbol,Symbol}()
    for (role, column, col) in opt_raw
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
        category_scale_source = category_levels === nothing ?
            :contiguous_observed_minimum_to_maximum : :declared,
        missing_policy,
        (missing_audit === nothing ? (;) : (; missing_audit))...,
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
        checked_category_levels,
        optional,
        optional_levels,
        columns,
    )
end

Base.length(data::FacetData) = data.n

function Base.show(io::IO, data::FacetData)
    print(io, "FacetData(", data.n, " ratings, ",
        length(data.person_levels), " persons, ",
        data.columns.rater === nothing ? "no rater facet, " :
            string(length(data.rater_levels), " raters, "),
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
item = :item, score = :score, category_levels = data.category_levels, ...)`
when a role-normalized split is desired. Preserve `category_levels` explicitly
when the selected rows may omit an intended category.
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
