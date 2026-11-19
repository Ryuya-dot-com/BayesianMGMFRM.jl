const COUNT_PPC_SCHEMA="bayesianmgmfrm.count_predictive.v1"
const COUNT_PREDICTION_SCHEMA="bayesianmgmfrm.count_prediction.v1"
const COUNT_METRICS=(:expected_proportion,:expected_count,:zero_probability,:perfect_probability)
function model_draws(t::CountTarget,raw)
    values=Matrix{Float64}(undef,size(raw,1),length(names(t,:model)))
    for (i,q) in enumerate(eachrow(raw))
        v=coordinates(t,q)
        values[i,:]=[v.person;reduce(vcat,(v.facets[b.name] for b in t.facets);init=Float64[]);
            v.coefficients;[v.residual_sd[b.name] for b in t.residuals];
            slope_model_values(v);is_beta_binomial(t) ? [v.precision] : Float64[]]
    end
    (;names=names(t,:model),values,fixed=union(Set("residual_sd[$(b.name)]" for b in t.residuals if b.hyper==0),slope_fixed_names(t)))
end
allocation_error(t::CountTarget)=join(t.allocation.reasons," ")
summary_unit(t::CountTarget,scale)=scale===:raw ? (isempty(slope_blocks(t)) ? :white_standard_normal : :white_normal_and_fisher_correlation) : :parameter_specific_success_logits_and_precision
prediction_conditioning(::CountTarget)=:known_owners_stored_attributes_and_declared_trials
function contrast_unit(t::CountTarget,left,right)
    for b in slope_blocks(t),col in _sb_cols(b),id in _owner_levels(t,b.owner)
        pair=("coefficient[response,$col]","slope[$(b.owner),$col,$(repr(id))]")
        (left,right) in (pair,reverse(pair)) && return :success_probability_logit_per_declared_predictor_unit
    end
    any(x->startswith(x,"slope[") || startswith(x,"slope_sd[") || startswith(x,"correlation[") || startswith(x,"coefficient[") || x=="precision",(left,right)) && throw(ArgumentError("use a declared-unit joint-draw estimand for coefficients or precision"))
    startswith(left,"residual_sd[")==startswith(right,"residual_sd[") || throw(ArgumentError("cannot subtract an SD from a location"))
    :success_probability_logit
end
function count_moments(t,q)
    v=coordinates(t,q);eta=[bounded_eta(t,v,n) for n in eachindex(t.person)];p=_sigmoid.(eta)
    phi=is_beta_binomial(t) ? v.precision : nothing
    zero_probability=[exp(first(count_cell(0,m,e,phi,0.))) for (m,e) in zip(t.trials,eta)]
    perfect_probability=[exp(first(count_cell(m,m,e,phi,0.))) for (m,e) in zip(t.trials,eta)]
    (;expected_proportion=p,expected_count=t.trials.*p,zero_probability,perfect_probability,
      variance_count=t.trials.*p.*_sigmoid.(-eta).*(phi===nothing ? ones(length(p)) : 1 .+(t.trials.-1)./(1+phi)))
end
function logprobs(::CountTarget,q)
    throw(ArgumentError("count supports vary with trials; use predict(spec,q) for moments/endpoints or pointwise_loglikelihood for observed counts"))
end
function count_simulate(t,q,rng)
    v=coordinates(t,q);out=Vector{Int}(undef,length(t.trials))
    for n in eachindex(out)
        e=bounded_eta(t,v,n);p=_sigmoid(e)
        if is_beta_binomial(t) && t.trials[n]>1
            a=v.precision*p;b=v.precision*_sigmoid(-e)
            isfinite(a+b) && a>0 && b>0 || throw(ArgumentError("beta shapes are not representable; review extreme priors"))
            out[n]=rand(rng,D.BetaBinomial(t.trials[n],a,b))
        else
            out[n]=rand(rng,D.Binomial(t.trials[n],p))
        end
    end
    out
end
function simulate(t::CountTarget;seed,q=nothing)
    seed isa Integer && !(seed isa Bool) && 0<=seed<=typemax(Int) || throw(ArgumentError("invalid seed"))
    rng=MersenneTwister(Int(seed));truth=q===nothing ? location_prior_draw(t,rng) : collect(q)
    (;simulated=count_simulate(t,truth,rng),trials=copy(t.trials),truth,seed=Int(seed),observation=t.observation,measure=:success_count_given_trials)
end
function count_prediction_target(t,data)
    data===nothing && return t
    loc=prediction_location(t,data)
    trials=count_integers(collect(B._column(data,t.observation.trials)),:trials;positive=true)
    B._check_length!(length(loc.person),trials,:trials);loc.table[t.observation.trials]=trials
    CountTarget(loc,t.observation,t.observation_prior,Int[],trials,Float64[],t.dimension,t.allocation)
end
function count_predict(t,f;data=nothing,rows=nothing,interval=.95)
    p=count_prediction_target(t,data);lo,hi=interval_bounds(interval)
    ix=rows===nothing ? collect(eachindex(p.person)) : collect(rows)
    !isempty(ix) && allunique(ix) && all(n->n isa Integer && !(n isa Bool) && 1<=n<=length(p.person),ix) || throw(ArgumentError("rows must select distinct prediction rows"))
    cells=NamedTuple[];precision=NamedTuple[];S=size(f.record.run.draws,1)
    for n in ix
        sub=count_prediction_target(t,Dict(k=>v[[n]] for (k,v) in p.table))
        vals=zeros(S,4)
        for (s,q) in enumerate(eachrow(f.record.run.draws))
            m=count_moments(sub,q);vals[s,:]=[only(getproperty(m,k)) for k in COUNT_METRICS]
        end
        for (j,k) in enumerate(COUNT_METRICS)
            x=view(vals,:,j);push!(cells,(;row=Int(n),trials=p.trials[n],metric=k,mean=mean(x),median=median(x),lower=quantile(x,lo),upper=quantile(x,hi),unit=k===:expected_count ? :success_count : :probability))
        end
        append!(precision,[(;row=Int(n),r...) for r in B._posterior_mcse_rows(vals,string.(collect(COUNT_METRICS)),f.record.run.controls.chains;probabilities=(lo,hi),parameter_space=:count_prediction)])
    end
    (;schema=COUNT_PREDICTION_SCHEMA,kind=:prediction,cells,rows=Int.(ix),interval,mcse=precision,
      interval_target=:posterior_expected_count_or_probability,conditioning=prediction_conditioning(t),observation=t.observation,measure=:success_count_given_trials,
      qualification=qualify(f),source_sample_content_hash=f.record.content_hash,target_identity=f.record.target_identity,warnings=design(t).warnings,scientific_acceptance=false)
end
function count_stats(y,n)
    z=y./n
    (;zero_rate=mean(iszero,y),perfect_rate=mean(y.==n),mean_proportion=mean(z),pooled_proportion=sum(y)/sum(n),sd_proportion=std(z;corrected=false),mean_count=mean(y))
end
function count_check(t;fit=nothing,ndraws=100,seed,groupby=nothing,interval=.95)
    ndraws isa Integer && !(ndraws isa Bool) && ndraws>0 || throw(ArgumentError("ndraws must be positive"))
    seed isa Integer && !(seed isa Bool) && 0<=seed<=typemax(Int) || throw(ArgumentError("invalid seed"))
    lo,hi=interval_bounds(interval)
    groupby===nothing && (groupby=:trials)
    groupby in (:trials,:person,keys(t.columns.facets)...) || throw(ArgumentError("groupby must be :trials or a declared owner"))
    labels=groupby===:trials ? sort(unique(t.trials)) : _owner_levels(t,groupby)
    ids=groupby===:trials ? [findfirst(==(n),labels) for n in t.trials] : _owner_index(t,groupby)
    indices=[findall(==(g),ids) for g in eachindex(labels)];all(!isempty,indices) || throw(ArgumentError("empty predictive group"))
    rng=MersenneTwister(Int(seed));draw_indices=fit===nothing ? Int[] : rand(rng,axes(fit.record.run.draws,1),ndraws)
    metrics=(:zero_rate,:perfect_rate,:mean_proportion,:pooled_proportion,:sd_proportion,:mean_count)
    values=zeros(ndraws,length(labels),length(metrics))
    for s in 1:ndraws
        q=fit===nothing ? location_prior_draw(t,rng) : view(fit.record.run.draws,draw_indices[s],:)
        replica=count_simulate(t,q,rng)
        for (g,ix) in enumerate(indices)
            stats=count_stats(replica[ix],t.trials[ix])
            for (j,k) in enumerate(metrics);values[s,g,j]=getproperty(stats,k);end
        end
    end
    cells=NamedTuple[]
    for (g,label) in enumerate(labels)
        ix=indices[g];obs=count_stats(t.y[ix],t.trials[ix])
        for (j,k) in enumerate(metrics)
            x=view(values,:,g,j)
            push!(cells,(;label=repr(label),metric=k,n=length(ix),trials=sort(unique(t.trials[ix])),observed=fit===nothing ? nothing : getproperty(obs,k),median=median(x),lower=quantile(x,lo),upper=quantile(x,hi)))
        end
    end
    (;schema=COUNT_PPC_SCHEMA,kind=fit===nothing ? :prior_predictive : :posterior_predictive,cells,groupby,interval,ndraws=Int(ndraws),seed=Int(seed),draw_indices,
      replicated_statistics=values,statistics_shape=size(values),metric_order=metrics,group_labels=repr.(labels),storage_order=:julia_column_major,
      observation=t.observation,measure=:success_count_given_trials,conditioning=fit===nothing ? :declared_design_and_trials_not_scores : prediction_conditioning(t),
      target_identity=B._cache_hash(record(t)),source_sample_content_hash=fit===nothing ? nothing : fit.record.content_hash,qualification=fit===nothing ? nothing : qualify(fit),
      warnings=[design(t).warnings;"Equal-response and pooled word proportions are distinct. Intervals describe replicated statistics; predictive endpoint MCSE is unassessed."],scientific_acceptance=false)
end
prior_check(t::CountTarget;kwargs...)=count_check(t;kwargs...)
function check_count_report(rep)
    interval_bounds(rep.interval);!isempty(rep.cells) && string(rep.measure)=="success_count_given_trials" || throw(ArgumentError("invalid count report"))
    if rep.schema==COUNT_PPC_SCHEMA
        collect(rep.statistics_shape)==[rep.ndraws,length(rep.group_labels),length(rep.metric_order)] &&
            length(rep.replicated_statistics)==prod(rep.statistics_shape) && string(rep.storage_order)=="julia_column_major" || throw(ArgumentError("predictive statistics layout mismatch"))
    end
    for r in rep.cells
        isfinite(r.lower) && isfinite(r.upper) && 0<=r.lower<=r.upper || throw(ArgumentError("invalid count interval"))
    end
    rep
end
