# Columns of probability matrices are the union of supplied category labels.
# Unsupported cells are structural zeros; centered steps use local category order.
function _category_support(scores,name,declared,owner,group,levels)
    if !(declared isa AbstractDict)
        _,y,categories=B._encode_scores(scores,name,declared)
        return y,categories,fill(1:length(categories),length(levels))
    end
    owner!==:global || throw(ArgumentError("category_levels by owner requires a declared steps facet"))
    Set(keys(declared))==Set(levels) || throw(ArgumentError("category_levels must map every declared steps-facet level exactly once"))
    sets=[B._normalize_category_levels(declared[x]) for x in levels]
    categories=sort!(unique(vcat(sets...)));index=Dict(x=>i for (i,x) in enumerate(categories))
    supports=[index[first(x)]:index[last(x)] for x in sets]
    y=Int[]
    for n in eachindex(scores)
        score=B._score_to_int(scores[n],name)
        score in sets[group[n]] || throw(ArgumentError("score at row $n is outside its steps owner's category support"))
        push!(y,index[score])
    end
    y,categories,supports
end
_owned_support(t)=hasproperty(t.groups,:category_support_by_owner)
_category_declaration(t)=_owned_support(t) ? Dict(g=>copy(t.categories[s]) for (g,s) in zip(t.group_levels,t.supports)) : copy(t.categories)
_step_scale(t,g)=t.step_scale isa Real ? t.step_scale : t.step_scale[g]
_step_count(t,g)=length(t.supports[g])-1
function _step_ranges(supports,offset)
    out=UnitRange{Int}[]
    for s in supports
        d=length(s)-2;push!(out,offset+1:offset+d);offset+=d
    end
    out
end
function _step_coordinates(t,q)
    tau=zeros(promote_type(Float64,eltype(q)),length(t.steps),maximum(length,t.supports)-1)
    for (g,r) in enumerate(t.steps)
        tau[g,1:_step_count(t,g)]=_step_scale(t,g).*N._zero_sum(view(q,r))
    end
    tau
end
_step_volume(t)=sum((length(r)*log(_step_scale(t,g)) for (g,r) in enumerate(t.steps) if !isempty(r));init=0.)
_step_values(t,tau)=reduce(vcat,(tau[g,1:_step_count(t,g)] for g in eachindex(t.steps));init=eltype(tau)[])
function _step_score!(gs,a,t,g,y)
    support=t.supports[g];tail=zero(eltype(a))
    for h in length(support)-1:-1:1
        tail+=a[support[h+1]];gs[g,h]+=tail-(y>support[h])
    end
end
function _sample_category(t,n,p,u)
    s=t.supports[t.group[n]]
    s[min(searchsortedfirst(cumsum(view(p,s)),u),length(s))]
end
function _prediction_scores(t,table,n)
    if !_owned_support(t)
        return fill(first(t.categories),n)
    end
    b=only(b for b in t.facets if b.name===t.owner)
    index=Dict(g=>i for (i,g) in enumerate(t.group_levels))
    all(x->haskey(index,x),table[b.column]) || throw(ArgumentError("prediction contains a new steps-facet level"))
    [t.categories[first(t.supports[index[x]])] for x in table[b.column]]
end
