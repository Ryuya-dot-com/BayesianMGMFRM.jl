# Count observations reuse location design; no ordinal steps or continuous bounds.
struct CountTarget <: AbstractTarget
    location::LocationDesign
    observation::NamedTuple
    observation_prior::NamedTuple
    y::Vector{Int}
    trials::Vector{Int}
    logchoose::Vector{Float64}
    dimension::Int
    allocation::NamedTuple
end
Base.getproperty(t::CountTarget,k::Symbol)=k in fieldnames(CountTarget) ? getfield(t,k) : getproperty(getfield(t,:location),k)
Base.propertynames(::CountTarget)=unique((fieldnames(CountTarget)...,fieldnames(LocationDesign)...))
const COUNT_SCHEMA="bayesianmgmfrm.count_facet_design.v1"
is_beta_binomial(t::CountTarget)=t.observation.family===:beta_binomial
function count_integers(x,name;positive=false)
    all(v->v isa Real && !(v isa Bool) && isfinite(v) && isinteger(v) && v>=(positive ? 1 : 0),x) ||
        throw(ArgumentError("$name must contain nonmissing $(positive ? "positive" : "nonnegative") integers; do not round proportions"))
    try Int.(x) catch e
        e isa InexactError || e isa OverflowError || rethrow()
        throw(ArgumentError("$name integers are not representable"))
    end
end
function count_model(table;person::Symbol,score::Symbol,facets::NamedTuple,
        observation::NamedTuple,population::NamedTuple,observation_prior=(;),
        predictors::NamedTuple=(;),intercept,levels=nothing,performance=nothing,assessment=nothing,decompose=nothing,missing_audit=nothing)
    _keys(observation,(:family,:trials),:observation)
    :trials in keys(facets) && throw(ArgumentError("trials is reserved for denominator grouping in count models"))
    observation.family in (:binomial,:beta_binomial) || throw(ArgumentError("count family must be :binomial or :beta_binomial"))
    tc=observation.trials;tc isa Symbol || throw(ArgumentError("observation.trials must name the denominator column"))
    tc in (person,score,values(facets)...,performance,assessment) && throw(ArgumentError("trial column must be distinct from score and owner IDs"))
    any(cols->tc in keys(cols),values(predictors)) && throw(ArgumentError("use a separately justified predictor column rather than reusing the trials role"))
    bb=observation.family===:beta_binomial
    observation_prior isa NamedTuple || throw(ArgumentError("observation_prior must be a named tuple"))
    _keys(observation_prior,bb ? (:precision,) : (),:observation_prior)
    pr=if bb
        p=_population_parameters(observation_prior.precision,:precision)
        p.kind===:lognormal || throw(ArgumentError("beta-binomial precision requires an explicit LogNormal prior"))
        (;precision=p)
    else
        (;)
    end
    y=count_integers(collect(B._column(table,score)),:successes)
    n=count_integers(collect(B._column(table,tc)),:trials;positive=true)
    length(y)==length(n) && !isempty(y) || throw(ArgumentError("successes and trials need equal nonzero lengths"))
    all(y.<=n) || throw(ArgumentError("successes exceed declared trials"))
    loc,alloc=location_model(table;person,score,facets,population,predictors,intercept,levels,performance,assessment,decompose,allow_slopes=true,missing_audit)
    loc.table[score]=y;loc.table[tc]=n
    lc=[SF.loggamma(Float64(m)+1)-SF.loggamma(Float64(k)+1)-SF.loggamma(Float64(m-k)+1) for (k,m) in zip(y,n)]
    CountTarget(loc,observation,pr,y,n,lc,loc.dimension+Int(bb),alloc)
end
function logprior(t::CountTarget,q)
    _check(t,q);slope_prior(t,q)
end
function prior_draw(t::CountTarget;seed=1)
    seed isa Integer && !(seed isa Bool) && 0<=seed<=typemax(Int) || throw(ArgumentError("invalid seed"))
    location_prior_draw(t,MersenneTwister(Int(seed)))
end
function coordinates(t::CountTarget,q::AbstractVector{<:Real})
    common=location_coordinates(t,q)
    has_sl=!isempty(slope_blocks(t))
    if is_beta_binomial(t)
        p=t.observation_prior.precision;ph=exp(p.logmean+p.logsd*q[end])
        isfinite(ph) && ph>0 || throw(ArgumentError("unrepresentable beta-binomial precision"))
        return merge(common,(;precision=ph,log_volume=common.log_volume+log(p.logsd)+log(ph),
            measure=has_sl ? :residuals_coefficients_sd_precision_and_correlation : :residuals_coefficients_sd_precision))
    end
    merge(common,(;measure=has_sl ? :residuals_coefficients_sd_and_correlation : :residuals_coefficients_sd))
end
# Exact integer rising products avoid log-beta/digamma subtraction at high precision.
# Work is linear in the trials for this scalar count baseline, not in a draw cube.
function count_cell(y,n,eta,phi,lc)
    u=_sigmoid(eta);v=_sigmoid(-eta)
    lp=lc-y*_softplus(-eta)-(n-y)*_softplus(eta)
    de=y*v-(n-y)*u;dp=zero(eta)
    phi===nothing && return lp,de,dp
    logph=log(phi);la=logph-_softplus(-eta);lb=logph-_softplus(eta)
    for k in 1:y-1
        z=log(k)-la;lp+=_softplus(z);r=_sigmoid(z);de-=v*r;dp-=r
    end
    for k in 1:n-y-1
        z=log(k)-lb;lp+=_softplus(z);r=_sigmoid(z);de+=u*r;dp-=r
    end
    for k in 1:n-1
        z=log(k)-logph;lp-=_softplus(z);dp+=_sigmoid(z)
    end
    lp,de,dp
end
count_cell(t::CountTarget,v,n)=count_cell(t.y[n],t.trials[n],bounded_eta(t,v,n),is_beta_binomial(t) ? v.precision : nothing,t.logchoose[n])
function L.logdensity_and_gradient(t::CountTarget,q::AbstractVector{<:Real})
    _check(t,q;finite=false);Z=promote_type(Float64,eltype(q));reject()=(-Z(Inf),fill(Z(NaN),length(q)))
    all(isfinite,q) || return reject()
    v=try coordinates(t,q) catch e;e isa ArgumentError || rethrow();return reject();end
    ge=Dict(b.name=>zeros(Z,length(_owner_levels(t,b.name))) for b in t.residuals)
    gc=zeros(Z,length(t.terms));gp=zero(Z);lp=logprior(t,q)
    sbs=slope_blocks(t)
    gs=[[zeros(Z,length(b.intercept_raw)) for _ in _sb_cols(b)] for b in sbs]
    for n in eachindex(t.y)
        l,de,dp=count_cell(t,v,n);lp+=l;gp+=dp
        isfinite(lp) || return reject()
        ge[:person][t.person[n]]+=de
        for b in t.facets;ge[b.name][b.index[n]]-=de;end
        for (j,p) in enumerate(t.terms);p.owner===:response && (gc[j]+=de*p.values[n]);end
        for (bi,b) in enumerate(sbs)
            sgn=b.owner===:person ? 1 : -1;p_idx=_owner_index(t,b.owner)[n]
            for (k_sl,col) in enumerate(_sb_cols(b))
                gs[bi][k_sl][p_idx]+=sgn*de*t.table[col][n]
            end
        end
    end
    g=location_gradient(t,q,v,ge,gc)
    isempty(sbs) || slope_gradient!(g,t,q,v,gs)
    is_beta_binomial(t) && (g[end]+=gp*t.observation_prior.precision.logsd)
    lp,g
end
L.logdensity(t::CountTarget,q::AbstractVector{<:Real})=first(L.logdensity_and_gradient(t,q))
function pointwise(t::CountTarget,q)
    v=coordinates(t,q);[first(count_cell(t,v,n)) for n in eachindex(t.y)]
end
function names(t::CountTarget,scale)
    out=location_names(t,scale)
    is_beta_binomial(t) && push!(out,scale===:raw ? "log_precision.white" : "precision")
    out
end
function record(t::CountTarget)
    (;schema=COUNT_SCHEMA,table=deepcopy(t.table),columns=t.columns,observation=t.observation,observation_prior=t.observation_prior,
      levels=(;person=copy(t.people),facets=(;(b.name=>copy(b.levels) for b in t.facets)...)),specification=t.specification,
      coordinates=isempty(slope_blocks(t)) ? :white_standard_normal : :white_normal_and_fisher_correlation,measure=:success_count_given_trials)
end
function restore_count(r)
    r.coordinates in (:white_standard_normal,:white_normal_and_fisher_correlation) && r.measure===:success_count_given_trials || throw(ArgumentError("unsupported count measure/coordinates"))
    s=r.specification
    pop=slope_population_restore(s)
    preds=(;(k=>(;(c=>(hasproperty(v,:by) ? (;by=v.by,prior=D.Normal(v.mean,v.sd)) : D.Normal(v.mean,v.sd)) for (c,v) in pairs(cols))...) for (k,cols) in pairs(s.predictors))...)
    rules=hasproperty(s,:decomposition) ? (;(d.source=>(;between=d.between,within=d.within) for d in s.decomposition.rules)...) : nothing
    p=r.observation_prior;op=isempty(p) ? (;) : (;precision=D.LogNormal(p.precision.logmean,p.precision.logsd))
    t=count_model(r.table;r.columns...,observation=r.observation,levels=r.levels,population=pop,predictors=preds,
        intercept=D.Normal(s.intercept.mean,s.intercept.sd),decompose=rules,observation_prior=op)
    record(t)==r || throw(ArgumentError("count design record is not reproducible"));t
end
function response_patterns(t::CountTarget)
    warnings=String[];all_binary=all(==(1),t.trials)
    is_beta_binomial(t) && all_binary && push!(warnings,"All trial counts are one: precision is informed only by its prior; the likelihood is exactly Bernoulli.")
    nz=count(iszero,t.y);nf=count(t.y.==t.trials)
    (nz==length(t.y) || nf==length(t.y)) && push!(warnings,"All responses are zero or all are perfect: mean effects can be weakly informed.")
    constant=NamedTuple[]
    for owner in (:person,keys(t.columns.facets)...)
        ix=_owner_index(t,owner)
        for (j,id) in enumerate(_owner_levels(t,owner))
            inds=findall(==(j),ix);isempty(inds) && continue
            prop=t.y[inds]./t.trials[inds]
            all(==(first(prop)),prop) && push!(constant,(;owner,id,n=length(inds),proportion=first(prop)))
        end
    end
    isempty(constant) || push!(warnings,"Constant observed proportions in $(length(constant)) owner levels; inspect response_patterns.constant_levels for IDs.")
    (;n=length(t.y),zero=nz,perfect=nf,all_binary,trial_counts=sort(unique(t.trials)),constant_levels=constant,warnings)
end
warn_patterns(t::CountTarget)=foreach(w->@warn(w),response_patterns(t).warnings)
function design(t::CountTarget)
    pat=response_patterns(t)
    (;n_observations=length(t.y),n_persons=length(t.people),n_facets=length(t.facets)+1,n_parameters=t.dimension,
      observation=t.observation,allocation=t.allocation,grouping=t.groups,population=t.specification.population,response_patterns=pat,
      warnings=[pat.warnings;hasproperty(t.allocation,:slope_warnings) ? t.allocation.slope_warnings : String[];"scalar count model: named owner effects and conditional response independence; not a word-specific difficulty model.";
      "Beta-binomial precision, when present, is intercept-only; within-response exchangeability does not establish rater reliability or Rasch specific objectivity.";
      "Population mean/covariance screening does not establish sufficient information, causal effects or general identification."],scientific_acceptance=false)
end
function contract(t::CountTarget)
    (;schema="bayesianmgmfrm.count_facet_contract.v1",family=:scalar_explanatory_count,dimensions=1,multiplier=1.,
      observation=t.observation,measure=:success_count_given_trials,mean_structure=:person_plus_response_minus_named_facets,
      constraints=:population_distributional_zero_mean,precision_structure=is_beta_binomial(t) ? :intercept_only : :absent,
      prediction=:known_owners_and_stored_attributes,record=record(t))
end
function stan_data(t::CountTarget)
    p=is_beta_binomial(t) ? t.observation_prior.precision : (;logmean=0.,logsd=1.)
    merge(location_stan_data(t),slope_stan_data(t),Dict("y"=>t.y,"trials"=>t.trials,"beta_binomial"=>Int(is_beta_binomial(t)),"precision_mean"=>p.logmean,"precision_sd"=>p.logsd,"location_dimension"=>t.location.dimension))
end

function observation_model(table;observation,kwargs...)
    observation isa NamedTuple && hasproperty(observation,:family) || throw(ArgumentError("observation needs a declared family"))
    observation.family in (:binomial,:beta_binomial) && return count_model(table;observation,kwargs...)
    bounded_model(table;observation,kwargs...)
end
