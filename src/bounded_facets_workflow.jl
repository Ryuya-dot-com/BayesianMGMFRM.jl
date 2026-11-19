const BOUNDED_PPC_SCHEMA="bayesianmgmfrm.bounded_predictive.v1"
const BOUNDED_PREDICTION_SCHEMA="bayesianmgmfrm.bounded_prediction.v1"
function model_draws(t::BoundedTarget,raw)
    values=Matrix{Float64}(undef,size(raw,1),length(names(t,:model)))
    for (i,q) in enumerate(eachrow(raw))
        v=coordinates(t,q)
        values[i,:]=[v.person;reduce(vcat,(v.facets[b.name] for b in t.facets);init=Float64[]);
            v.coefficients;[v.residual_sd[b.name] for b in t.residuals];
            slope_model_values(v);v.precision;v.endpoint_logit;v.upper_logit;distribution_model_values(v)]
    end
    (;names=names(t,:model),values,fixed=union(Set("residual_sd[$(b.name)]" for b in t.residuals if b.hyper==0),slope_fixed_names(t),Set(distribution_sd_name(b,r) for b in distribution_blocks(t) for r in b.residuals if r.hyper==0)))
end
allocation_error(t::BoundedTarget)=join(t.allocation.reasons," ")
summary_unit(t::BoundedTarget,scale)=scale===:raw ? (isempty(slope_blocks(t)) ? :white_standard_normal : :white_normal_and_fisher_correlation) : :parameter_specific_interior_logits_precision_and_endpoint_logits
prediction_conditioning(::BoundedTarget)=:known_owners_and_stored_owner_attributes
function contrast_unit(t::BoundedTarget,left,right)
    for b in distribution_blocks(t)
        sd_prefix="residual_sd[$(b.parameter),"
        if startswith(left,sd_prefix) || startswith(right,sd_prefix)
            startswith(left,sd_prefix) && startswith(right,sd_prefix) || throw(ArgumentError("distributional SD contrasts require the same parameter link"))
            return b.parameter===:precision ? :log_precision : :logit
        end
        prefix="$(b.parameter)["
        startswith(left,prefix) && startswith(right,prefix) && return b.parameter===:precision ? :log_precision : :logit
    end
    any(x->any(k->startswith(x,"$k["),BOUNDED_PARAMETERS),(left,right)) && throw(ArgumentError("distributional contrasts require matching parameter blocks"))
    for b in slope_blocks(t),col in _sb_cols(b),id in _owner_levels(t,b.owner)
        pair=("coefficient[response,$col]","slope[$(b.owner),$col,$(repr(id))]")
        (left,right) in (pair,reverse(pair)) && return :interior_mean_logit_per_declared_predictor_unit
    end
    any(x->startswith(x,"slope[") || startswith(x,"slope_sd[") || startswith(x,"correlation[") || startswith(x,"coefficient[") || x in ("precision","endpoint_logit","upper_logit"),(left,right)) &&
        throw(ArgumentError("use a declared-unit joint-draw estimand for coefficients or observation parameters; units differ"))
    startswith(left,"residual_sd[")==startswith(right,"residual_sd[") || throw(ArgumentError("cannot subtract a residual SD from a location"))
    :interior_mean_logit
end
const BOUNDED_DEFAULT_METRICS=(:expected_score,:interior_mean,:lower_probability,:upper_probability)
const BOUNDED_METRICS=(BOUNDED_DEFAULT_METRICS...,:precision,:endpoint_probability,:upper_given_endpoint_probability,:interior_sd,:score_sd)
bounded_metric_unit(k)=k===:precision ? :beta_concentration : k in (:expected_score,:interior_mean,:interior_sd,:score_sd) ? :original_score : :probability
function bounded_moments(t,q;metrics=BOUNDED_DEFAULT_METRICS)
    !isempty(metrics) && allunique(metrics) && all(k->k in BOUNDED_METRICS,metrics) || throw(ArgumentError("select distinct supported bounded metrics"))
    v=coordinates(t,q);lo,hi=t.observation.bounds
    cells=[observation_values(t,v,n) for n in eachindex(t.person)]
    phi=[c.precision for c in cells];z=[c.endpoint_probability for c in cells];h=[c.upper_probability for c in cells]
    all(x->isfinite(x) && x>0,phi) || throw(ArgumentError("unrepresentable predicted precision"))
    mu=[_sigmoid(bounded_eta(t,v,n)) for n in eachindex(t.person)]
    w=[_sigmoid(-bounded_eta(t,v,n)) for n in eachindex(t.person)]
    iv=mu.*w./(phi.+1);tv=(1 .-z).*iv.+z.*h.*(1 .-h).+(1 .-z).*z.*(mu.-h).^2
    values=(;interior_mean=lo.+(hi-lo).*mu,expected_score=lo.+(hi-lo).*((1 .-z).*mu.+z.*h),
      lower_probability=z.*(1 .-h),upper_probability=z.*h,precision=phi,endpoint_probability=z,
      upper_given_endpoint_probability=h,interior_sd=(hi-lo).*sqrt.(iv),score_sd=(hi-lo).*sqrt.(tv))
    (;(k=>getproperty(values,k) for k in metrics)...)
end
function logprobs(::BoundedTarget,q)
    throw(ArgumentError("continuous densities are not category probabilities; use predict(spec, q) or predict(fit)"))
end
function simulate(t::BoundedTarget;seed,q=nothing)
    seed isa Integer && !(seed isa Bool) && 0<=seed<=typemax(Int) || throw(ArgumentError("invalid seed"))
    rng=MersenneTwister(Int(seed));truth=q===nothing ? location_prior_draw(t,rng) : collect(q)
    vals=bounded_simulate(t,truth,rng)
    (;simulated=vals,truth,seed=Int(seed),observation=t.observation,measure=:original_score_with_endpoint_atoms)
end
function bounded_simulate(t,q,rng)
    v=coordinates(t,q);lo,hi=t.observation.bounds;out=Vector{Float64}(undef,length(t.y))
    for n in eachindex(out)
        c=observation_values(t,v,n)
        if rand(rng)<c.endpoint_probability
            out[n]=rand(rng)<c.upper_probability ? hi : lo
        else
            e=bounded_eta(t,v,n);a=c.precision*_sigmoid(e);b=c.precision*_sigmoid(-e)
            # Reject nonrepresentable beta shapes; do not silently clip draws into endpoints.
            isfinite(a+b) && a>0 && b>0 || throw(ArgumentError("beta shapes are not representable"))
            y=rand(rng,D.Beta(a,b));out[n]=lo+(hi-lo)*y
            lo<out[n]<hi || throw(ArgumentError("interior beta draw rounded to a bound; review extreme priors/precision"))
        end
    end
    out
end
function prediction_location(t,data)
    data===nothing && return t.location
    n=length(B._column(data,t.columns.person));raw=Dict{Symbol,Vector}()
    # Prediction design uses only known identities; scores are absent, not dummy categories.
    for c in unique([t.columns.person;collect(values(t.columns.facets));filter(!isnothing,[t.columns.performance,t.columns.assessment])])
        raw[c]=collect(B._column(data,c));B._check_length!(n,raw[c],c)
    end
    p,_=_labels(raw[t.columns.person],:person,t.people);blocks=Block[]
    for b in t.facets
        ix,_=_labels(raw[b.column],b.name,b.levels)
        push!(blocks,Block(b.name,b.column,b.levels,ix,b.sd,b.scale,b.raw))
    end
    groups=_groups(raw,t.columns,p,blocks)
    for (child,parent) in ((t.columns.performance,t.columns.person),(t.columns.assessment,t.columns.performance))
        child===nothing && continue
        known=Dict(zip(t.table[child],t.table[parent]))
        all(i->haskey(known,raw[child][i]) && known[raw[child][i]]==raw[parent][i],1:n) || throw(ArgumentError("prediction requires known $child with stored ownership"))
    end
    ids=(;table=raw,columns=t.columns,person=p,people=t.people,facets=blocks)
    derived=prediction_decomposition(t,ids,data);merge!(raw,derived);terms=MeanTerm[]
    for term in t.terms
        x=term.column===nothing ? ones(n) : haskey(derived,term.column) ? derived[term.column] : _numeric_column(data,term.column,n)
        term.column===nothing || (raw[term.column]=x)
        if term.owner===:response
            vals=term.by===nothing ? x : x.*(_owner_index(ids,term.by).==only(findall(==(term.level),_owner_levels(ids,term.by))))
        else
            vals=term.values;ix=_owner_index(ids,term.owner)
            all(i->vals[ix[i]]==x[i],1:n) || throw(ArgumentError("prediction changes a stored owner attribute"))
        end
        push!(terms,MeanTerm(term.owner,term.column,term.mean,term.sd,term.raw,vals,term.by,term.level))
    end
    loc=LocationDesign(raw,t.columns,p,t.people,blocks,t.residuals,terms,t.specification,groups,t.location.dimension)
    t isa BoundedTarget ? distribution_prediction!(t,loc,data) : loc
end
function bounded_prediction_target(t,data)
    data===nothing && return t
    BoundedTarget(prediction_location(t,data),t.observation,t.observation_prior,Float64[],t.dimension,t.allocation)
end
function bounded_predict(t,f;data=nothing,rows=nothing,interval=.95,metrics=BOUNDED_DEFAULT_METRICS)
    p=bounded_prediction_target(t,data);lo,hi=interval_bounds(interval)
    ix=rows===nothing ? collect(eachindex(p.person)) : collect(rows)
    !isempty(ix) && allunique(ix) && all(n->n isa Integer && !(n isa Bool) && 1<=n<=length(p.person),ix) || throw(ArgumentError("rows must select distinct prediction rows"))
    !isempty(metrics) && allunique(metrics) && all(k->k in BOUNDED_METRICS,metrics) || throw(ArgumentError("select distinct supported bounded metrics"))
    cells=NamedTuple[];precision=NamedTuple[];S=size(f.record.run.draws,1)
    # Bounded memory: requested estimands for one requested observation at a time.
    for n in ix
        sub=bounded_prediction_target(t,Dict(k=>v[[n]] for (k,v) in p.table))
        vals=zeros(S,length(metrics))
        for (s,q) in enumerate(eachrow(f.record.run.draws))
            m=bounded_moments(sub,q;metrics);vals[s,:]=[only(getproperty(m,k)) for k in metrics]
        end
        for (j,k) in enumerate(metrics)
            x=view(vals,:,j);push!(cells,(;row=Int(n),metric=k,mean=mean(x),median=median(x),lower=quantile(x,lo),upper=quantile(x,hi),unit=bounded_metric_unit(k)))
        end
        append!(precision,[(;row=Int(n),r...) for r in B._posterior_mcse_rows(vals,string.(collect(metrics)),f.record.run.controls.chains;
            probabilities=(lo,hi),parameter_space=:bounded_prediction)])
    end
    (;schema=BOUNDED_PREDICTION_SCHEMA,kind=:prediction,cells,rows=Int.(ix),interval,mcse=precision,bounds=t.observation.bounds,
      interval_target=all(k->k in BOUNDED_DEFAULT_METRICS,metrics) ? :posterior_expected_score_or_probability : :posterior_conditional_distribution_parameter,conditioning=prediction_conditioning(t),qualification=qualify(f),
      source_sample_content_hash=f.record.content_hash,target_identity=f.record.target_identity,warnings=design(t).warnings,scientific_acceptance=false)
end
function bounded_stats(y,bounds)
    lo,hi=bounds;inside=y[(lo.<y).&(y.<hi)]
    # Missing interiors are represented explicitly, never as an invented interior mean.
    (;lower_rate=mean(y.==lo),upper_rate=mean(y.==hi),mean_score=mean(y),sd_score=std(y;corrected=false),
      interior_mean=isempty(inside) ? nothing : mean(inside),interior_sd=isempty(inside) ? nothing : std(inside;corrected=false))
end
function bounded_check(t;fit=nothing,ndraws=100,seed,groupby=nothing,interval=.95)
    ndraws isa Integer && !(ndraws isa Bool) && ndraws>0 || throw(ArgumentError("ndraws must be positive"))
    seed isa Integer && !(seed isa Bool) && 0<=seed<=typemax(Int) || throw(ArgumentError("invalid seed"))
    lo,hi=interval_bounds(interval)
    groupby===nothing || groupby in (:person,keys(t.columns.facets)...) || throw(ArgumentError("groupby must be a declared owner"))
    ids=groupby===nothing ? ones(Int,length(t.y)) : _owner_index(t,groupby)
    labels=groupby===nothing ? Any["all"] : _owner_levels(t,groupby)
    indices=[findall(==(g),ids) for g in eachindex(labels)];all(!isempty,indices) || throw(ArgumentError("empty predictive group"))
    rng=MersenneTwister(Int(seed));draw_indices=fit===nothing ? Int[] : rand(rng,axes(fit.record.run.draws,1),ndraws)
    metrics=(:lower_rate,:upper_rate,:mean_score,:sd_score,:interior_mean,:interior_sd)
    values=Array{Union{Nothing,Float64}}(nothing,ndraws,length(labels),length(metrics))
    failures=NamedTuple[]
    for s in 1:ndraws
        q=fit===nothing ? location_prior_draw(t,rng) : view(fit.record.run.draws,draw_indices[s],:)
        replica=try
            bounded_simulate(t,q,rng)
        catch e
            e isa ArgumentError && e.msg in ("beta shapes are not representable", "interior beta draw rounded to a bound; review extreme priors/precision") || rethrow()
            push!(failures,(;replica=s,reason=e.msg));continue
        end
        for (g,ix) in enumerate(indices)
            stats=bounded_stats(replica[ix],t.observation.bounds)
            for (j,k) in enumerate(metrics);values[s,g,j]=getproperty(stats,k);end
        end
    end
    cells=NamedTuple[]
    for (g,label) in enumerate(labels)
        obs=bounded_stats(t.table[t.columns.score][indices[g]],t.observation.bounds)
        for (j,k) in enumerate(metrics)
            x=Float64[v for v in values[:,g,j] if v!==nothing]
            push!(cells,(;label=repr(label),metric=k,n=length(indices[g]),defined_replicas=length(x),
              observed=fit===nothing ? nothing : getproperty(obs,k),
              median=isempty(x) ? nothing : median(x),lower=isempty(x) ? nothing : quantile(x,lo),upper=isempty(x) ? nothing : quantile(x,hi)))
        end
    end
    failure_warnings=isempty(failures) ? String[] : ["$(length(failures)) of $ndraws replications failed numerical representation. Intervals condition on successfully represented replicas, not the full predictive distribution; adequacy is unresolved. No values were clipped and no replacement replicas were drawn."]
    (;schema=BOUNDED_PPC_SCHEMA,kind=fit===nothing ? :prior_predictive : :posterior_predictive,cells,groupby,interval,ndraws=Int(ndraws),seed=Int(seed),draw_indices,
      replicated_statistics=values,statistics_shape=size(values),metric_order=metrics,group_labels=repr.(labels),storage_order=:julia_column_major,
      numerical_failures=failures,replications_complete=isempty(failures),interval_conditioning=isempty(failures) ? :requested_predictive_distribution : :numerically_representable_replicas_only,
      bounds=t.observation.bounds,conditioning=fit===nothing ? :declared_design_not_scores : prediction_conditioning(t),
      target_identity=B._cache_hash(record(t)),source_sample_content_hash=fit===nothing ? nothing : fit.record.content_hash,
      qualification=fit===nothing ? nothing : qualify(fit),warnings=[design(t).warnings;failure_warnings;"Intervals describe replicated statistics; interior statistics condition on at least one interior draw. Predictive endpoint MCSE is unassessed."],scientific_acceptance=false)
end
prior_check(t::BoundedTarget;kwargs...)=bounded_check(t;kwargs...)
function check_bounded_report(rep)
    interval_bounds(rep.interval);!isempty(rep.cells) || throw(ArgumentError("empty bounded report"))
    lo,hi=rep.bounds;isfinite(lo) && isfinite(hi) && hi>lo || throw(ArgumentError("invalid bounds"))
    if rep.schema==BOUNDED_PPC_SCHEMA && hasproperty(rep,:statistics_shape)
        collect(rep.statistics_shape)==[rep.ndraws,length(rep.group_labels),length(rep.metric_order)] &&
            length(rep.replicated_statistics)==prod(rep.statistics_shape) && string(rep.storage_order)=="julia_column_major" || throw(ArgumentError("predictive statistics layout mismatch"))
        if hasproperty(rep,:numerical_failures)
            ix=[f.replica for f in rep.numerical_failures]
            allunique(ix) && all(i->i isa Integer && !(i isa Bool) && 1<=i<=rep.ndraws,ix) || throw(ArgumentError("invalid failed-replication indices"))
            rep.replications_complete==isempty(ix) || throw(ArgumentError("inconsistent replication-completion flag"))
            string(rep.interval_conditioning)==(isempty(ix) ? "requested_predictive_distribution" : "numerically_representable_replicas_only") || throw(ArgumentError("incorrect predictive interval conditioning"))
            vals=reshape(collect(rep.replicated_statistics),Tuple(rep.statistics_shape))
            all(i->all(isnothing,vals[i,:,:]),ix) || throw(ArgumentError("failed replica contains represented statistics"))
        end
    end
    for r in rep.cells
        if r.lower===nothing || r.upper===nothing
            rep.schema==BOUNDED_PPC_SCHEMA && r.lower===r.upper===r.median===nothing && r.defined_replicas==0 || throw(ArgumentError("incomplete interval"))
        else
            isfinite(r.lower) && isfinite(r.upper) && r.lower<=r.upper || throw(ArgumentError("invalid bounded interval"))
        end
    end
    rep
end
