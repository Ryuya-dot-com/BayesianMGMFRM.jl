function location_model(table;person::Symbol,score::Symbol,facets::NamedTuple,population::NamedTuple,
        predictors::NamedTuple=(;),intercept,levels=nothing,performance=nothing,assessment=nothing,decompose=nothing,allow_slopes=false)
    reserved=(:person,:response,:steps,:global,:score,:performance,:assessment)
    all(k->!(k in reserved),keys(facets)) || throw(ArgumentError("reserved facet name"))
    all(x->x isa Symbol,values(facets)) || throw(ArgumentError("facet mappings must name columns"))
    all(x->x===nothing || x isa Symbol,(performance,assessment)) || throw(ArgumentError("performance/assessment must be column symbols"))
    assessment!==nothing && performance===nothing && throw(ArgumentError("assessment requires performance ownership"))
    owners=(:person,keys(facets)...);_keys(population,owners,:population)
    basepop,slopespec=slope_population(population,allow_slopes)
    pop=(;(k=>_population_parameters(v,k) for (k,v) in pairs(basepop))...)
    all(k->k in (owners...,:response),keys(predictors)) || throw(ArgumentError("unknown predictor owner"))
    selected=Symbol[person,score,values(facets)...]
    performance!==nothing && !(performance in values(facets)) && push!(selected,performance)
    assessment!==nothing && push!(selected,assessment)
    allunique(selected) || throw(ArgumentError("selected roles must use distinct columns"))
    raw=Dict{Symbol,Vector}(c=>collect(B._column(table,c)) for c in selected)
    n=length(raw[score]);n>0 || throw(ArgumentError("observations cannot be empty"))
    for (c,x) in raw
        B._check_length!(n,x,c);c===score || _labels(x,c)
    end
    if levels!==nothing
        _keys(levels,(:person,:facets),:levels);_keys(levels.facets,keys(facets),:facet_levels)
    end
    p,ps=_labels(raw[person],:person,levels===nothing ? nothing : levels.person)
    blocks=Block[]
    for (name,c) in pairs(facets)
        ix,lev=_labels(raw[c],name,levels===nothing ? nothing : levels.facets[name])
        push!(blocks,Block(name,c,lev,ix,0.,0.,1:0))
    end
    columns=(;person,score,facets,performance,assessment)
    groups=_groups(raw,columns,p,blocks)
    identity=(;table=raw,columns,person=p,people=ps,facets=blocks)
    derived,dec=decompose===nothing ? (Dict{Symbol,Vector}(),nothing) : decompose_predictors(identity,table,decompose)
    merge!(raw,derived)
    residuals=ResidualBlock[];offset=0
    for owner in owners
        m=length(_owner_levels(identity,owner));pr=pop[owner]
        pr.kind===:lognormal && m<2 && throw(ArgumentError("estimated SD needs at least two owner levels"))
        push!(residuals,ResidualBlock(owner,:iid_population,offset+1:offset+m,pr.kind===:fixed ? pr.sd : 1.,0.,0.,0));offset+=m
    end
    terms=MeanTerm[];predrec=Pair{Symbol,Any}[]
    for (owner,cols) in pairs(predictors)
        _named(cols,"predictors.$owner");crecs=Pair{Symbol,Any}[]
        for (c,pr) in pairs(cols)
            c in selected && throw(ArgumentError("predictor cannot reuse identity/score column"))
            x=haskey(derived,c) ? derived[c] : _numeric_column(table,c,n);raw[c]=x
            fp=_predictor_prior(pr,owner,facets,"$owner.$c")
            if hasproperty(fp,:by)
                ids=_owner_index(identity,fp.by)
                for (j,lev) in enumerate(_owner_levels(identity,fp.by))
                    offset+=1;push!(terms,MeanTerm(owner,c,fp.mean,fp.sd,offset,x.*(ids.==j),fp.by,lev))
                end
            else
                vals=owner===:response ? x : _owned_values(identity,owner,c,x)
                offset+=1;push!(terms,MeanTerm(owner,c,fp.mean,fp.sd,offset,vals))
            end
            push!(crecs,c=>fp)
        end
        push!(predrec,owner=>(;crecs...))
    end
    ip=_normal_parameters(intercept,:intercept);offset+=1
    push!(terms,MeanTerm(:response,nothing,ip.mean,ip.sd,offset,ones(n)))
    for i in eachindex(residuals)
        r=residuals[i];pr=pop[r.name]
        if pr.kind===:lognormal
            offset+=1;residuals[i]=ResidualBlock(r.name,r.kind,r.raw,r.sd,pr.logmean,pr.logsd,offset)
        end
    end
    sblocks,offset=compile_slopes(identity,raw,table,terms,residuals,slopespec,offset)
    spec=(;population=pop,predictors=(;predrec...),intercept=ip)
    isempty(sblocks) || (spec=merge(spec,(;random_slopes=sblocks)))
    dec===nothing || (spec=merge(spec,(;decomposition=dec)))
    loc=LocationDesign(raw,columns,p,ps,blocks,residuals,terms,spec,groups,offset)
    absent=["$o[$(repr(id))]" for o in owners for (j,id) in enumerate(_owner_levels(loc,o)) if !(j in _owner_index(loc,o))]
    alloc=explanatory_allocation(loc,(;missing_levels=absent,method=:declared_owner_incidence))
    loc,slope_allocation(loc,alloc)
end

function location_coordinates(t,q::AbstractVector{<:Real})
    _check(t,q);Z=promote_type(Float64,eltype(q));effects=Dict{Symbol,Vector{Z}}();sd=Dict{Symbol,Z}();lv=zero(Z)
    for b in t.residuals
        s=b.hyper==0 ? Z(b.sd) : exp(b.logmean+b.logsd*q[b.hyper])
        isfinite(s) && s>0 || throw(ArgumentError("unrepresentable residual scale"))
        effects[b.name]=s.*q[b.raw];sd[b.name]=s;lv+=length(b.raw)*log(s)
        b.hyper==0 || (lv+=log(b.logsd)+log(s))
    end
    coef=[p.mean+p.sd*q[p.raw] for p in t.terms]
    for (p,c) in zip(t.terms,coef)
        p.owner===:response || (effects[p.owner].+=p.values.*c);lv+=log(p.sd)
    end
    base=(;person=effects[:person],facets=Dict(b.name=>effects[b.name] for b in t.facets),coefficients=coef,residual_sd=sd,log_volume=lv)
    isempty(slope_blocks(t)) && return base
    sl=slope_coordinates(t,q)
    merge(base,(;random_slopes=sl,log_volume=lv+sum(x.log_volume for x in sl)))
end

function location_gradient(t,q,v,ge,gc)
    Z=promote_type(Float64,eltype(q))
    grad=-Z.(q)
    for b in t.residuals
        g=ge[b.name];s=v.residual_sd[b.name];grad[b.raw].+=s.*g
        b.hyper==0 || (grad[b.hyper]+=b.logsd*s*dot(g,view(q,b.raw)))
    end
    for (j,p) in enumerate(t.terms)
        p.owner===:response || (gc[j]=dot(ge[p.owner],p.values))
        grad[p.raw]+=p.sd*gc[j]
    end
    grad
end

function location_names(t,scale)
    scale in (:raw,:model) || throw(ArgumentError("scale must be :raw or :model"))
    out=String[]
    for b in t.residuals
        append!(out,scale===:raw ? ["$(b.name).white[$j]" for j in eachindex(b.raw)] : ["$(b.name)[$(repr(x))]" for x in _owner_levels(t,b.name)])
    end
    append!(out,[_term_name(p)*(scale===:raw ? ".white" : "") for p in t.terms])
    append!(out,scale===:raw ? ["log_sd[$(b.name)].white" for b in t.residuals if b.hyper>0] : ["residual_sd[$(b.name)]" for b in t.residuals])
    append!(out,slope_names(t,scale))
    out
end

function location_stan_data(t)
    n=length(t.y);R=sum(length(b.raw) for b in t.residuals);T=length(t.terms)
    A=zeros(n,R);rsd=Float64[];hidx=Int[];hp=Tuple{Float64,Float64}[];col=0
    for b in t.residuals
        b.hyper>0 && push!(hp,(b.logmean,b.logsd))
        for j in eachindex(b.raw)
            col+=1;push!(rsd,b.sd);push!(hidx,b.hyper>0 ? length(hp) : 0)
            A[:,col]=(b.name===:person ? 1. : -1.).*(_owner_index(t,b.name).==j)
        end
    end
    X=hcat([(p.owner in (:person,:response) ? 1. : -1.).*(p.owner===:response ? p.values : p.values[_owner_index(t,p.owner)]) for p in t.terms]...)
    Dict("N"=>n,"R"=>R,"T"=>T,"V"=>length(hp),"D"=>t.dimension,
      "A"=>A,"X"=>X,"residual_scale"=>rsd,"hyper_index"=>hidx,"logmean"=>first.(hp),"logsd"=>last.(hp),
      "coefficient_mean"=>[p.mean for p in t.terms],"coefficient_sd"=>[p.sd for p in t.terms])
end
