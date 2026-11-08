module JointRatingDesign

using LinearAlgebra

# Isolated input prototype; not a fitted model or an extension of FacetData.
const SCHEMA = "bayesianmgmfrm.joint_rating_design.v1"
const IDS = (:observation_id, :person, :task, :response_id, :rating_event_id, :rater, :criterion)
nonempty_id(x) = x isa AbstractString && !isempty(strip(x))
integer_score(x) = x isa Integer && !(x isa Bool)

"""
    prepare_ratings(rows; criteria)

Validate observed long-format rows with explicit observation, person, physical
task, response, rating-event, rater and criterion IDs. Each criterion declaration contains
`criterion`, increasing integer `levels`, `direction` (`:higher_is_more` or
`:higher_is_less`) and `threshold_group`. Keep raw scores; encode their declared
direction once as 0:(K-1). Missing ratings must be omitted, not coded as zero.

One response belongs to one person/task pair; repeated responses to the same
pair are allowed. One rating event belongs to one response/rater pair, but the
same rater can assess that response again in a different event. One event and
criterion identify at most one rating.
Threshold sharing requires equal category counts, not equal observed ranges.
This validates input semantics, not latent dimensionality or identification.
"""
function prepare_ratings(rows; criteria)
    isempty(rows) && throw(ArgumentError("observed ratings must not be empty"))
    isempty(criteria) && throw(ArgumentError("declare every observed criterion"))
    scales = Dict{String,NamedTuple}()
    group_sizes = Dict{String,Int}()
    for c in criteria
        all(f -> hasproperty(c, f), (:criterion, :levels, :direction, :threshold_group)) ||
            throw(ArgumentError("incomplete criterion declaration"))
        nonempty_id(c.criterion) && nonempty_id(c.threshold_group) ||
            throw(ArgumentError("criterion and threshold group IDs must be nonempty strings"))
        haskey(scales, c.criterion) && throw(ArgumentError("duplicate criterion declaration"))
        c.levels isa Union{AbstractVector,Tuple} && length(c.levels) >= 2 &&
            all(integer_score, c.levels) && issorted(c.levels) && allunique(c.levels) ||
            throw(ArgumentError("levels must be strictly increasing integers; declare all possible categories"))
        c.direction isa Symbol && c.direction in (:higher_is_more, :higher_is_less) ||
            throw(ArgumentError("declare score direction explicitly"))
        levels = collect(c.levels)
        K = length(levels)
        get(group_sizes, c.threshold_group, K) == K ||
            throw(ArgumentError("a shared threshold group cannot have different category counts"))
        group_sizes[c.threshold_group] = K
        scales[c.criterion] = (; criterion=String(c.criterion), levels,
            direction=c.direction, threshold_group=String(c.threshold_group))
    end
    observations = String[]
    seen_ids = Set{String}()
    seen_ratings = Set{Tuple{String,String}}()
    owners = Dict{String,Tuple{String,String}}()
    event_owners = Dict{String,Tuple{String,String}}()
    encoded = Int[]
    category_counts = Int[]
    kept = NamedTuple[]
    for row in rows
        all(f -> hasproperty(row, f) && nonempty_id(getproperty(row, f)), IDS) ||
            throw(ArgumentError("all seven rating IDs must be nonempty strings"))
        hasproperty(row, :score) && integer_score(row.score) ||
            throw(ArgumentError("score must be an integer; omit missing/recused rows"))
        row.observation_id in seen_ids && throw(ArgumentError("duplicate observation ID"))
        push!(seen_ids, row.observation_id)
        key = (String(row.rating_event_id), String(row.criterion))
        key in seen_ratings && throw(ArgumentError("duplicate rating-event/criterion rating"))
        push!(seen_ratings, key)
        owner = (String(row.person), String(row.task))
        get(owners, row.response_id, owner) == owner ||
            throw(ArgumentError("a response ID cannot change person or physical task"))
        owners[row.response_id] = owner
        event_owner = (String(row.response_id), String(row.rater))
        get(event_owners, row.rating_event_id, event_owner) == event_owner ||
            throw(ArgumentError("a rating-event ID cannot change response or rater"))
        event_owners[row.rating_event_id] = event_owner
        haskey(scales, row.criterion) || throw(ArgumentError("undeclared criterion"))
        c = scales[row.criterion]
        j = findfirst(==(row.score), c.levels)
        j === nothing && throw(ArgumentError("score outside the criterion's declared category set"))
        K = length(c.levels)
        push!(observations, row.observation_id)
        push!(encoded, c.direction == :higher_is_more ? j-1 : K-j)
        push!(category_counts, K)
        push!(kept, (; (f => String(getproperty(row, f)) for f in IDS)..., score=row.score))
    end
    Set(getproperty.(kept, :criterion)) == Set(keys(scales)) ||
        throw(ArgumentError("every declared criterion needs an observed rating"))
    return (; schema=SCHEMA, rows=kept, criteria=[scales[k] for k in sort(collect(keys(scales)))],
        observation_ids=observations, score=encoded, category_counts,
        response_ids=getproperty.(kept, :response_id),
        rating_event_ids=getproperty.(kept, :rating_event_id),
        threshold_groups=[scales[r.criterion].threshold_group for r in kept])
end

"""
    common_scale_table(data)

Return columns compatible with existing `FacetData`, including physical task
and response metadata, only when all declared category counts match. Use
`item=:criterion`, `score=:score`, and the returned `category_levels` explicitly.
This bridge does not add shared effects, predictors or threshold-group terms
to the existing fitted model. Unequal supports are never padded.
"""
function common_scale_table(data)
    length(unique(data.category_counts)) == 1 || throw(ArgumentError(
        "FacetData has one category scale; mixed supports cannot use this bridge"))
    K = first(data.category_counts)
    return (; table=(; observation_id=data.observation_ids,
        person=getproperty.(data.rows, :person), task=getproperty.(data.rows, :task),
        response_id=data.response_ids, rating_event_id=data.rating_event_ids,
        rater=getproperty.(data.rows, :rater),
        criterion=getproperty.(data.rows, :criterion), score=data.score),
        category_levels=0:(K-1))
end

"""
    checked_predictors(data, rows; columns, rtol=sqrt(eps(Float64)))

Align finite numeric named columns by observation ID and reject a deficient
fixed-predictor matrix. No intercept, centering, scaling, interactions or time
order is inferred. Column normalization is used only for the SVD rank check;
returned values retain their supplied units. Every training subset needs its
own check. Full rank of X alone does not establish identification against facet
effects, covariance identification, causal interpretation or good precision.
"""
function checked_predictors(data, rows; columns, rtol=sqrt(eps(Float64)))
    columns isa Union{AbstractVector,Tuple} && !isempty(columns) &&
        all(c -> c isa Symbol, columns) && length(unique(columns)) == length(columns) ||
        throw(ArgumentError("declare distinct predictor column names"))
    rtol isa Real && !(rtol isa Bool) && isfinite(rtol) && 0 < rtol < 1 ||
        throw(ArgumentError("rank tolerance must be finite and between zero and one"))
    lookup = Dict{String,Int}()
    for (i, row) in enumerate(rows)
        hasproperty(row, :observation_id) && nonempty_id(row.observation_id) ||
            throw(ArgumentError("predictor rows require observation IDs"))
        haskey(lookup, row.observation_id) && throw(ArgumentError("duplicate predictor observation ID"))
        lookup[row.observation_id] = i
    end
    Set(keys(lookup)) == Set(data.observation_ids) ||
        throw(ArgumentError("predictor observation IDs must match exactly"))
    X = Matrix{Float64}(undef, length(data.rows), length(columns))
    for (i, id) in enumerate(data.observation_ids), (j, column) in enumerate(columns)
        row = rows[lookup[id]]
        hasproperty(row, column) || throw(ArgumentError("missing predictor $column"))
        value = getproperty(row, column)
        value isa Real && isfinite(value) && isfinite(Float64(value)) ||
            throw(ArgumentError("predictor $column must be finite and numeric"))
        X[i,j] = value
    end
    scaled = copy(X)
    for j in axes(X,2)
        scale = maximum(abs, view(X,:,j))
        scale > 0 || throw(ArgumentError("zero predictor column $(columns[j])"))
        scaled[:,j] ./= scale
        scaled[:,j] ./= norm(view(scaled,:,j))
    end
    singular = svdvals(scaled)
    matrix_rank = count(>(rtol*first(singular)), singular)
    matrix_rank == length(columns) || throw(ArgumentError(
        "fixed predictors are rank deficient at rtol=$rtol (rank $matrix_rank of $(length(columns))): $(join(columns, ", "))"))
    return (; observation_ids=copy(data.observation_ids), names=collect(columns), values=X,
        matrix_rank, rank_rtol=Float64(rtol), scaled_singular_values=singular,
        identification_checked=false)
end

end
