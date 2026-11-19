# Distributional terms use the same owner/predictor grammar, with positive link signs.
distribution_blocks(t)=hasproperty(t.observation_prior,:regression) ? t.observation_prior.regression : ()
const BOUNDED_PARAMETERS=(:precision,:endpoint_logit,:upper_logit)
function observation_intercept(p)
    p isa NamedTuple || return p
    haskey(p,:intercept) || throw(ArgumentError("distributional block requires an intercept prior"))
    p.intercept
end
function compile_distributional(table,loc,input,prior)
    blocks=NamedTuple[];offset=loc.dimension+3;n=length(loc.person)
    identities=filter(!isnothing,[loc.columns.person,loc.columns.score,values(loc.columns.facets)...,loc.columns.performance,loc.columns.assessment])
    for (k,parameter) in enumerate(BOUNDED_PARAMETERS)
        entry=getproperty(input,parameter);entry isa NamedTuple || continue
        all(c->c in (:intercept,:predictors,:population),keys(entry)) && haskey(entry,:intercept) || throw(ArgumentError("distributional block requires intercept and optional predictors/population"))
        predictors=get(entry,:predictors,(;));population=get(entry,:population,(;))
        _named(predictors,"distributional predictors");_named(population,"distributional population")
        owners=(:person,keys(loc.columns.facets)...)
        all(o->o in (owners...,:response),keys(predictors)) && all(o->o in owners,keys(population)) || throw(ArgumentError("unknown distributional owner"))
        terms=NamedTuple[];residuals=NamedTuple[]
        for (owner,cols) in pairs(predictors)
            _named(cols,"distributional predictors.$owner")
            for (c,pr) in pairs(cols)
                c in identities && throw(ArgumentError("distributional predictor cannot reuse identity/score column"))
                x=haskey(loc.table,c) ? loc.table[c] : _numeric_column(table,c,n)
                loc.table[c]=x;owner===:response || _owned_values(loc,owner,c,x)
                fp=_predictor_prior(pr,owner,loc.columns.facets,"$parameter.$owner.$c")
                by=get(fp,:by,nothing)
                for level in (by===nothing ? [nothing] : _owner_levels(loc,by))
                    offset+=1;push!(terms,(;owner,column=c,mean=fp.mean,sd=fp.sd,raw=offset,by,level))
                end
            end
        end
        for (owner,pr) in pairs(population)
            p=_population_parameters(pr,owner);m=length(_owner_levels(loc,owner))
            p.kind===:lognormal && m<2 && throw(ArgumentError("estimated distributional SD needs at least two owner levels"))
            raw=offset+1:offset+m;offset+=m;hyper=0
            p.kind===:lognormal && (offset+=1;hyper=offset)
            push!(residuals,(;name=owner,raw,hyper,sd=p.kind===:fixed ? p.sd : 1.,
                logmean=p.kind===:fixed ? 0. : p.logmean,logsd=p.kind===:fixed ? 1. : p.logsd))
        end
        isempty(terms) && isempty(residuals) && continue
        push!(blocks,(;parameter,index=k,terms=Tuple(terms),residuals=Tuple(residuals)))
    end
    isempty(blocks) ? prior : merge(prior,(;regression=Tuple(blocks))),offset
end
function distribution_x(t,p,n)
    x=t.table[p.column][n]
    p.by===nothing || (x*=(_owner_levels(t,p.by)[_owner_index(t,p.by)[n]]==p.level))
    x
end
function distribution_coordinates(t,q)
    map(distribution_blocks(t)) do b
        coef=[p.mean+p.sd*q[p.raw] for p in b.terms];lv=sum(log(p.sd) for p in b.terms;init=zero(first(q)))
        residuals=map(b.residuals) do r
            sd=r.hyper==0 ? oftype(first(q),r.sd) : exp(r.logmean+r.logsd*q[r.hyper])
            isfinite(sd) && sd>0 || throw(ArgumentError("unrepresentable distributional SD"))
            (;values=sd.*q[r.raw],sd)
        end
        for (r,s) in zip(b.residuals,residuals)
            lv+=length(r.raw)*log(s.sd)+(r.hyper==0 ? zero(s.sd) : log(r.logsd)+log(s.sd))
        end
        (;coefficients=coef,residuals,log_volume=lv)
    end
end
function observation_values(t,v,n)
    isempty(distribution_blocks(t)) && return v
    pars=[log(v.precision),v.endpoint_logit,v.upper_logit]
    for (b,c) in zip(distribution_blocks(t),v.distributional)
        for (p,beta) in zip(b.terms,c.coefficients);pars[b.index]+=beta*distribution_x(t,p,n);end
        for (r,s) in zip(b.residuals,c.residuals);pars[b.index]+=s.values[_owner_index(t,r.name)[n]];end
    end
    (;precision=exp(pars[1]),endpoint_logit=pars[2],upper_logit=pars[3],
      endpoint_probability=_sigmoid(pars[2]),upper_probability=_sigmoid(pars[3]))
end
function distribution_gradient!(g,t,q,v,derivatives)
    for (b,c) in zip(distribution_blocks(t),v.distributional)
        h=view(derivatives,:,b.index)
        for p in b.terms;g[p.raw]+=p.sd*sum(h[n]*distribution_x(t,p,n) for n in eachindex(h));end
        for (r,s) in zip(b.residuals,c.residuals)
            ids=_owner_index(t,r.name);a=zeros(eltype(g),length(r.raw))
            for n in eachindex(h);a[ids[n]]+=h[n];end
            g[r.raw].+=s.sd.*a
            r.hyper==0 || (g[r.hyper]+=r.logsd*dot(a,s.values))
        end
    end
end
function distribution_term_name(b,p)
    suffix=p.by===nothing ? "" : ",by=$(p.by),level=$(repr(p.level))"
    "coefficient[$(b.parameter),$(p.owner),$(p.column)$suffix]"
end
distribution_sd_name(b,r)="residual_sd[$(b.parameter),$(r.name)]"
function distribution_names(t,scale)
    out=String[]
    for b in distribution_blocks(t)
        append!(out,[distribution_term_name(b,p)*(scale===:raw ? ".white" : "") for p in b.terms])
        for r in b.residuals
            append!(out,scale===:raw ? ["$(b.parameter).$(r.name).white[$j]" for j in eachindex(r.raw)] :
                ["$(b.parameter)[$(r.name),$(repr(id))]" for id in _owner_levels(t,r.name)])
            (scale===:model || r.hyper>0) && push!(out,distribution_sd_name(b,r)*(scale===:raw ? ".white" : ""))
        end
    end
    out
end
function distribution_model_values(v)
    out=eltype(v.person)[]
    hasproperty(v,:distributional) || return out
    for b in v.distributional
        append!(out,b.coefficients)
        for r in b.residuals;append!(out,r.values);push!(out,r.sd);end
    end
    out
end
function restore_observation_prior(p)
    base=(precision=D.LogNormal(p.precision.logmean,p.precision.logsd),endpoint_logit=D.Normal(p.endpoint_logit.mean,p.endpoint_logit.sd),upper_logit=D.Normal(p.upper_logit.mean,p.upper_logit.sd))
    hasproperty(p,:regression) || return base
    out=Dict{Symbol,Any}(pairs(base))
    for b in p.regression
        owners=unique(x.owner for x in b.terms)
        ownerpairs=Pair{Symbol,Any}[]
        for owner in owners
            cols=Pair{Symbol,Any}[]
            for column in unique(x.column for x in b.terms if x.owner===owner)
                term=first(filter(x->x.owner===owner && x.column===column,b.terms));pr=D.Normal(term.mean,term.sd)
                push!(cols,column=>(term.by===nothing ? pr : (;by=term.by,prior=pr)))
            end
            push!(ownerpairs,owner=>(;cols...))
        end
        predictors=(;ownerpairs...)
        population=(;(r.name=>(r.hyper==0 ? r.sd : D.LogNormal(r.logmean,r.logsd)) for r in b.residuals)...)
        out[b.parameter]=(;intercept=getproperty(base,b.parameter),predictors,population)
    end
    (;(k=>out[k] for k in BOUNDED_PARAMETERS)...)
end
function distribution_prediction!(original,loc,data)
    for b in distribution_blocks(original),p in b.terms
        c=p.column;x=haskey(loc.table,c) ? loc.table[c] : _numeric_column(data,c,length(loc.person))
        if p.owner!==:response
            known=_owned_values(original,p.owner,c,original.table[c]);ix=_owner_index(loc,p.owner)
            all(n->x[n]==known[ix[n]],eachindex(x)) || throw(ArgumentError("prediction changes a stored distributional owner attribute"))
        end
        loc.table[c]=x
    end
    loc
end
function distribution_allocation(t,base)
    isempty(distribution_blocks(t)) && return base
    checks=NamedTuple[];reasons=copy(base.reasons);warnings=String[];n=length(t.person)
    for b in distribution_blocks(t)
        terms=[MeanTerm(:response,p.column,p.mean,p.sd,p.raw,[distribution_x(t,p,i) for i in 1:n]) for p in b.terms]
        push!(terms,MeanTerm(:response,nothing,0.,1.,0,ones(n)))
        proxy=(;person=t.person,people=t.people,facets=t.facets,specification=t.specification,residuals=b.residuals,terms)
        check=explanatory_allocation(proxy,(;missing_levels=String[]))
        append!(reasons,["$(b.parameter): $r" for r in check.reasons])
        eligible=b.parameter===:precision ? findall(y->0<y<1,t.y) : b.parameter===:upper_logit ? findall(y->y==0 || y==1,t.y) : collect(eachindex(t.y))
        X=hcat([p.values for p in terms]...);r=isempty(eligible) ? 0 : rank(X[eligible,:];rtol=max(length(eligible),size(X,2))*eps(Float64))
        r<size(X,2) && push!(warnings,"$(b.parameter) has likelihood design rank $r/$(size(X,2)) on $(length(eligible)) contributing rows; some directions are informed only by priors.")
        for res in b.residuals
            ix=_owner_index(t,res.name);m=length(_owner_levels(t,res.name))
            if b.parameter===:upper_logit
                n_zero_rows=count(j->!any(n->ix[n]==j && (t.y[n]==0 || t.y[n]==1),eachindex(t.y)),1:m)
                n_const_dir=count(1:m) do j
                    ys=[t.y[n] for n in eachindex(t.y) if ix[n]==j && (t.y[n]==0 || t.y[n]==1)]
                    !isempty(ys) && (all(iszero,ys) || all(==(1),ys))
                end
                n_zero_rows>0 && push!(warnings,"upper_logit random intercept for $(res.name) has $n_zero_rows/$m levels with zero endpoint observations (informed only by prior).")
                n_const_dir>0 && push!(warnings,"upper_logit random intercept for $(res.name) has $n_const_dir/$m levels with constant endpoint direction (only lower or only upper endpoints).")
            elseif b.parameter===:endpoint_logit
                n_no_end=count(j->!any(n->ix[n]==j && (t.y[n]==0 || t.y[n]==1),eachindex(t.y)),1:m)
                n_no_int=count(j->!any(n->ix[n]==j && 0<t.y[n]<1,eachindex(t.y)),1:m)
                n_no_end>0 && push!(warnings,"endpoint_logit random intercept for $(res.name) has $n_no_end/$m levels with zero endpoint observations.")
                n_no_int>0 && push!(warnings,"endpoint_logit random intercept for $(res.name) has $n_no_int/$m levels with zero interior observations.")
            elseif b.parameter===:precision
                n_sparse_int=count(j->count(n->ix[n]==j && 0<t.y[n]<1,eachindex(t.y))<2,1:m)
                n_sparse_int>0 && push!(warnings,"precision random intercept for $(res.name) has $n_sparse_int/$m levels with fewer than two interior observations.")
            end
        end
        push!(checks,(;parameter=b.parameter,check,likelihood_rows=length(eligible),likelihood_rank=r))
    end
    merge(base,(;identified=isempty(reasons),reasons,distributional=checks,distributional_warnings=warnings))
end
function distribution_stan_data(t)
    raw=Int[];block=Int[];mean=Float64[];sd=Float64[];hyper=Int[];lm=Float64[];ls=Float64[];xs=Vector{Float64}[]
    for b in distribution_blocks(t)
        for p in b.terms
            push!(xs,[distribution_x(t,p,n) for n in eachindex(t.person)]);push!(raw,p.raw);push!(block,b.index)
            push!(mean,p.mean);push!(sd,p.sd);push!(hyper,0);push!(lm,0.);push!(ls,1.)
        end
        for r in b.residuals,j in eachindex(r.raw)
            push!(xs,Float64.(_owner_index(t,r.name).==j));push!(raw,r.raw[j]);push!(block,b.index)
            push!(mean,0.);push!(sd,r.sd);push!(hyper,r.hyper);push!(lm,r.logmean);push!(ls,r.logsd)
        end
    end
    Dict("U"=>length(raw),"UX"=>isempty(xs) ? zeros(length(t.person),0) : hcat(xs...),"u_raw"=>raw,"u_block"=>block,
        "u_mean"=>mean,"u_sd"=>sd,"u_hyper"=>hyper,"u_logmean"=>lm,"u_logsd"=>ls,"observation_offset"=>t.location.dimension)
end
