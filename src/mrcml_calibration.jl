# Coordinates and covariance axes travel together in the source's declared order.
function _joint_calibration(input, steps)
    input isa NamedTuple && Set(keys(input)) == Set((:coordinates, :covariance)) ||
        throw(ArgumentError("calibration requires coordinates and their covariance"))
    records = input.coordinates
    records isa Union{AbstractVector,Tuple} && !isempty(records) ||
        throw(ArgumentError("provide a nonempty sequence of calibration coordinates"))
    coordinates = NamedTuple[]
    facets = Dict{Symbol,Dict{Any,Float64}}()
    upper = Dict{Any,Dict{Any,Float64}}()
    for r in records
        r isa NamedTuple && haskey(r,:block) && r.block isa Symbol ||
            throw(ArgumentError("each calibration coordinate requires a named facet block or :steps"))
        is_step = r.block === :steps
        fields = is_step ? (:block,:owner,:level,:upper_category,:estimate) : (:block,:level,:estimate)
        Set(keys(r)) == Set(fields) || throw(ArgumentError("expected calibration fields $fields"))
        r.estimate isa Real && !(r.estimate isa Bool) && isfinite(Float64(r.estimate)) ||
            throw(ArgumentError("calibration estimates must be finite logit values"))
        is_step && !isequal(r.owner,steps) && throw(ArgumentError("calibration step owner differs from the model"))
        by_level = is_step ? get!(upper,r.level,Dict{Any,Float64}()) : get!(facets,r.block,Dict{Any,Float64}())
        key = is_step ? r.upper_category : r.level
        haskey(by_level,key) && throw(ArgumentError("duplicate calibration coordinate $r"))
        by_level[key] = Float64(r.estimate)
        push!(coordinates, (; (f=>getproperty(r,f) for f in fields if f !== :estimate)..., estimate=Float64(r.estimate)))
    end
    n = length(records)
    V = input.covariance
    V isa AbstractMatrix && size(V)==(n,n) && all(x->x isa Real && !(x isa Bool) && isfinite(Float64(x)),V) ||
        throw(ArgumentError("covariance must be a finite square matrix with one axis per coordinate"))
    V = Matrix{Float64}(V)
    isapprox(V,transpose(V);rtol=32eps(Float64),atol=0) || throw(ArgumentError("asymmetric calibration covariance"))
    issymmetric(V) || (V = V ./ 2 .+ transpose(V) ./ 2)
    isposdef(Symmetric(V)) || throw(ArgumentError("calibration covariance must be positive definite on independent coordinates"))
    fixed = (;facets=(;facets...))
    isempty(upper) || (fixed=merge(fixed,(;steps=(owner=steps,values=upper))))
    return (;coordinates,covariance=V), fixed
end

# Columns map perturbations on the supplied scale into reconstructed model values.
# In a centered step block the unconstrained step mean offsets the transferred sum.
function _calibration_map(coords, model_names, group_levels, supports, categories)
    index = Dict(name=>i for (i,name) in enumerate(model_names))
    rows, cols, values = Int[], Int[], Float64[]
    function entry(name,j,value)
        push!(rows,index[name]); push!(cols,j); push!(values,value)
    end
    for (j,r) in enumerate(coords)
        if r.block !== :steps
            entry("$(r.block)[$(repr(r.level))]",j,1.)
            continue
        end
        key = repr(r.level)
        group = findfirst(isequal(r.level),group_levels)
        transferred = [s.upper_category for s in coords if s.block === :steps && isequal(s.level,r.level)]
        remaining = setdiff(categories[supports[group]][2:end], transferred)
        isempty(remaining) && throw(ArgumentError("omit a dependent step for owner $key from the calibration coordinates"))
        entry("steps[$key,$(r.upper_category)]",j,1.)
        for h in remaining
            entry("steps[$key,$h]",j,-1.0/length(remaining))
        end
    end
    sparse(rows,cols,values,length(model_names),length(coords))
end


# JSON arrays preserve both covariance axes and the types of potentially ambiguous IDs.
function _report_calibration(cal)
    labels = [r.level isa Tuple ? map(label_encoding,r.level) : label_encoding(r.level) for r in cal.coordinates]
    merge(cal,(;covariance=[collect(row) for row in eachrow(cal.covariance)],coordinate_level_labels=labels))
end

# String and Symbol IDs can have the same JSON representation.
function _report_calibration_groups(cal)
    groups = [merge(g,(;level_labels=label_encoding.(g.levels))) for g in cal.groups]
    merge(cal,(;groups))
end
