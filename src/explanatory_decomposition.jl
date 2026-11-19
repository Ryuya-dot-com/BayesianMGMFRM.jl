# Data ownership transformation, independent of rating multiplicity and likelihood.
_has_column(t,c)=t isa AbstractDict ? (haskey(t,c) || haskey(t,String(c))) : c in propertynames(t)
function _derived_column!(out,table,c,x)
    all(isfinite,x) || throw(ArgumentError("decomposed predictor $c is not representable"))
    if _has_column(table,c)
        _numeric_column(table,c,length(x))==x || throw(ArgumentError("supplied derived column $c disagrees with the stored decomposition"))
    end
    out[c]=x
end

function decompose_predictors(base,table,rules::NamedTuple)
    isempty(rules) && throw(ArgumentError("decompose requires at least one source column"))
    perf=base.columns.performance
    perf===nothing && throw(ArgumentError("decompose requires an explicit performance column"))
    outputs=Symbol[]
    for (source,r) in pairs(rules)
        _named(r,"decompose.$source");_keys(r,(:between,:within),"decompose.$source")
        r.between isa Symbol && r.within isa Symbol || throw(ArgumentError("decomposition output names must be Symbols"))
        source in keys(base.table) && throw(ArgumentError("decomposition source cannot be a score or identity column"))
        append!(outputs,(r.between,r.within))
    end
    length(unique(outputs))==length(outputs) && all(c->!(c in keys(base.table) || c in keys(rules)),outputs) ||
        throw(ArgumentError("decomposition output names must be distinct from identities, scores and all source columns"))
    ids=base.table[perf];unique_ids=unique(ids);lookup=Dict(id=>j for (j,id) in enumerate(unique_ids))
    ix=[lookup[id] for id in ids];n=length(ids);out=Dict{Symbol,Vector}();records=NamedTuple[]
    for (source,r) in pairs(rules)
        x=_numeric_column(table,source,n);values=fill(NaN,length(unique_ids));people=fill(0,length(unique_ids))
        for i in eachindex(x)
            j=ix[i]
            isnan(values[j]) || values[j]==x[i] || throw(ArgumentError("decomposition source $source changes within performance $(repr(ids[i]))"))
            values[j]=x[i];people[j]=base.person[i]
        end
        means=fill(NaN,length(base.people));counts=zeros(Int,length(base.people))
        buckets=[Float64[] for _ in base.people]
        for (p,x) in zip(people,values);push!(buckets[p],x);end
        for p in unique(people)
            xs=sort!(buckets[p]);counts[p]=length(xs)
            # Sorting makes the floating-point result independent of rating row order.
            means[p]=sum(xs./length(xs))
        end
        between=means[base.person];within=x.-between
        out[source]=x;_derived_column!(out,table,r.between,between);_derived_column!(out,table,r.within,within)
        push!(records,(;source,between=r.between,within=r.within,performance_ids=copy(unique_ids),
            person_ids=base.people[people],values,means=means[people],counts=counts[people]))
    end
    out,(;weighting=:equal_unique_performances,centering=:observed_person_mean,
        units=:unchanged_source_units,temporal_adjustment=:none,rules=records)
end

function prediction_decomposition(t,base,table)
    hasproperty(t.specification,:decomposition) || return Dict{Symbol,Vector}()
    out=Dict{Symbol,Vector}();ids=base.table[base.columns.performance];n=length(ids)
    for r in t.specification.decomposition.rules
        x=_numeric_column(table,r.source,n);lookup=Dict(id=>j for (j,id) in enumerate(r.performance_ids))
        all(id->haskey(lookup,id),ids) || throw(ArgumentError("decomposed prediction supports known performances only; new performances require a separate estimand"))
        ix=[lookup[id] for id in ids]
        x==r.values[ix] && base.people[base.person]==r.person_ids[ix] ||
            throw(ArgumentError("prediction changes stored performance ownership or source $(r.source)"))
        out[r.source]=x;_derived_column!(out,table,r.between,r.means[ix]);_derived_column!(out,table,r.within,x.-r.means[ix])
    end
    out
end
