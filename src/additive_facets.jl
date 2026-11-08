# Named additive blocks share one scalar PCM target. No facet name selects behavior.
module AdditiveFacets
import BayesianMGMFRM as B
import LogDensityProblems as L
using LinearAlgebra, SparseArrays, Random, Statistics
const N = B.Experimental.JointRatings.Numerics
const S = B.Experimental.JointRatings.S

struct Block
    name::Symbol
    column::Symbol
    levels::Vector{Any}
    index::Vector{Int}
    sd::Float64
    scale::Float64
    raw::UnitRange{Int}
end

struct Target
    table::Dict{Symbol,Vector}
    columns::NamedTuple
    person::Vector{Int}
    people::Vector{Any}
    category::Vector{Int}
    categories::Vector{Int}
    facets::Vector{Block}
    owner::Symbol
    group::Vector{Int}
    group_levels::Vector{Any}
    steps::Vector{UnitRange{Int}}
    person_sd::Float64
    step_sd::Float64
    step_scale::Float64
    dimension::Int
    allocation::NamedTuple
    groups::NamedTuple
end

function _sd(x, active, name)
    x isa Real && !(x isa Bool) && isfinite(x) || throw(ArgumentError("$name must be a finite real SD"))
    y=Float64(x)
    isfinite(y) && (active ? y>0 : y==0) ||
        throw(ArgumentError("$name must be $(active ? "positive" : "zero for an inactive block") after Float64 conversion"))
    y
end

function _labels(values, name, declared=nothing)
    valid(x) = x isa AbstractString || x isa Symbol || (x isa Integer && !(x isa Bool))
    all(valid,values) || throw(ArgumentError("$name labels must be nonmissing strings, symbols or integers"))
    lev=declared===nothing ? B._stable_levels(values,name) : Any[declared...]
    !isempty(lev) && all(valid,lev) && length(unique(lev))==length(lev) ||
        throw(ArgumentError("$name declared levels must be nonempty, unique valid labels"))
    ix=Dict(x=>i for (i,x) in enumerate(lev))
    all(x->haskey(ix,x),values) || throw(ArgumentError("$name contains labels outside its declared levels"))
    [ix[x] for x in values],lev
end

function _named(x, name)
    x isa NamedTuple || throw(ArgumentError("$name must be a named tuple"))
    x
end

function _keys(x, expected, name)
    Set(keys(_named(x,name)))==Set(expected) || throw(ArgumentError("$name keys must be $(collect(expected)); no missing/extra entries"))
end

# Centered step null directions split exactly from location null directions:
# averaging all adjacent-logit equations removes each zero-sum step vector.
function _allocation(person, people, facets, group, G, K, dimension)
    n=length(person); P=length(people)
    rows=collect(1:n); cols=copy(person); vals=ones(n)
    names=["person[$(repr(x))]" for x in people]; offset=P
    missing=String[]; observed_people=Set(person)
    for (j,x) in enumerate(people)
        j in observed_people || push!(missing,"person[$(repr(x))]")
    end
    for b in facets
        for j in 2:length(b.levels)
            push!(names,"$(b.name)[$(repr(b.levels[j]))] (reference contrast)")
        end
        for i in eachindex(person)
            j=b.index[i]
            if j>1
                push!(rows,i);push!(cols,offset+j-1);push!(vals,-1.)
            end
        end
        observed=Set(b.index)
        for (j,x) in enumerate(b.levels)
            j in observed || push!(missing,"$(b.name)[$(repr(x))]")
        end
        offset+=length(b.levels)-1
    end
    a=sparse(rows,cols,vals,n,offset)
    # SPQR's documented default-scale tolerance, recorded explicitly.
    tol=20*(sum(size(a)))*eps(Float64)*maximum(sqrt.(vec(sum(abs2,a;dims=1))))
    q=qr(a;tol=tol); r=rank(q)
    d=abs.(diag(q.R)); positive=d[d.>tol]
    ratio=isempty(positive) ? 0. : minimum(positive)/maximum(positive)
    step_rank=length(unique(group))*(K-2)
    aliases=r==offset ? String[] : names[q.pcol[r+1:end]]
    (;rank=r+step_rank,columns=dimension,identified=r+step_rank==dimension,
      location_rank=r,location_columns=offset,step_rank,
      step_columns=G*(K-2),method=:sparse_spqr_location_plus_centered_steps,
      tolerance=tol,smallest_to_largest_retained_R_diagonal=ratio,
      near_dependence=ratio<sqrt(eps(Float64)),dependent_reference_columns=aliases,
      missing_levels=missing,stored_design_nonzeros=nnz(a))
end

function _groups(table, columns, person, facets)
    n=length(person); perf=columns.performance; assessment=columns.assessment
    seen=Dict{Any,Int}(); counts=Dict{Any,Int}(); amap=Dict{Any,Any}()
    for i in 1:n
        if perf!==nothing
            id=table[perf][i]
            get(seen,id,person[i])==person[i] || throw(ArgumentError("a performance ID belongs to multiple persons"))
            seen[id]=person[i];counts[id]=get(counts,id,0)+1
            if assessment!==nothing
                aid=table[assessment][i]
                get(amap,aid,id)==id || throw(ArgumentError("an assessment ID belongs to multiple performances"))
                amap[aid]=id
            end
        end
    end
    identities=Set{Tuple}()
    for i in 1:n
        id=(person[i],(b.index[i] for b in facets)...,
            perf===nothing ? nothing : table[perf][i],
            assessment===nothing ? nothing : table[assessment][i])
        id in identities && throw(ArgumentError("duplicate rating identity at row $i; resolve duplicates or supply distinct performance/assessment IDs"))
        push!(identities,id)
    end
    (;performance_available=perf!==nothing,assessment_available=assessment!==nothing,
      repeated_performances=count(>(1),values(counts)),
      performance_effect=:absent,conditional_independence=:assumed_not_tested)
end

function model(table;person::Symbol,score::Symbol,facets::NamedTuple,steps::Symbol,
        prior_sd::NamedTuple,category_levels,levels=nothing,
        performance::Union{Nothing,Symbol}=nothing,assessment::Union{Nothing,Symbol}=nothing)
    reserved=(:person,:steps,:global,:score,:performance,:assessment)
    all(k->!(k in reserved),keys(facets)) || throw(ArgumentError("facet names cannot use reserved roles $reserved"))
    all(x->x isa Symbol,values(facets)) || throw(ArgumentError("facet mapping values must be column symbols"))
    steps===:global || steps in keys(facets) || throw(ArgumentError("steps must be :global or a declared facet name"))
    selected=Symbol[person,score,values(facets)...]
    performance!==nothing && push!(selected,performance)
    assessment!==nothing && push!(selected,assessment)
    length(unique(selected))==length(selected) || throw(ArgumentError("each selected role must use a distinct column"))
    raw=Dict{Symbol,Vector}(c=>deepcopy(B._column(table,c)) for c in selected)
    n=length(raw[score]);n>0 || throw(ArgumentError("ratings cannot be empty"))
    for (c,x) in raw
        B._check_length!(n,x,c)
        c==score || _labels(x,c)
    end
    _,cat,categories=B._encode_scores(raw[score],score,category_levels)
    _keys(prior_sd,(:person,:facets,:step),:prior_sd)
    _keys(prior_sd.facets,keys(facets),:facet_prior_sd)
    if levels!==nothing
        _keys(levels,(:person,:facets),:levels)
        _keys(levels.facets,keys(facets),:facet_levels)
    end
    p,ps=_labels(raw[person],:person,levels===nothing ? nothing : levels.person)
    person_sd=_sd(prior_sd.person,true,:person_sd)
    blocks=Block[];offset=length(ps)
    for (name,c) in pairs(facets)
        index,lev=_labels(raw[c],name,levels===nothing ? nothing : levels.facets[name])
        m=length(lev);sd=_sd(prior_sd.facets[name],m>1,name)
        scale=m>1 ? sd*sqrt(m/(m-1)) : 0.
        isfinite(scale) || throw(ArgumentError("$name prior transform scale overflows"))
        push!(blocks,Block(name,c,lev,index,sd,scale,offset+1:offset+m-1));offset+=m-1
    end
    owner=steps===:global ? nothing : only(filter(b->b.name==steps,blocks))
    group=owner===nothing ? ones(Int,n) : copy(owner.index)
    groups=owner===nothing ? Any[:global] : deepcopy(owner.levels)
    K=length(categories); H=K-1; G=length(groups)
    sd=_sd(prior_sd.step,H>1,:step_sd); scale=H>1 ? sd*sqrt(H/(H-1)) : 0.
    isfinite(scale) || throw(ArgumentError("step prior transform scale overflows"))
    ranges=[offset+(g-1)*(K-2)+1:offset+g*(K-2) for g in 1:G]
    dimension=offset+G*(K-2)
    columns=(;person,score,facets,performance,assessment)
    grouping=_groups(raw,columns,p,blocks)
    allocation=_allocation(p,ps,blocks,group,G,K,dimension)
    Target(raw,columns,p,ps,cat,categories,blocks,steps,group,groups,ranges,
        person_sd,sd,scale,dimension,allocation,grouping)
end

L.dimension(t::Target)=t.dimension
L.capabilities(::Type{Target})=L.LogDensityOrder{1}()
function _check(t,q;finite=true)
    length(q)==t.dimension || throw(DimensionMismatch("expected $(t.dimension) white coordinates"))
    finite && !all(isfinite,q) && throw(ArgumentError("coordinates must be finite"))
    nothing
end

function coordinates(t::Target,q::AbstractVector{<:Real})
    _check(t,q); person=t.person_sd.*q[1:length(t.people)]
    fs=Dict(b.name=>b.scale.*N._zero_sum(view(q,b.raw)) for b in t.facets)
    tau=permutedims(hcat([t.step_scale.*N._zero_sum(view(q,r)) for r in t.steps]...))
    lv=length(t.people)*log(t.person_sd)
    for b in t.facets
        isempty(b.raw) || (lv+=length(b.raw)*log(b.scale))
    end
    isempty(first(t.steps)) || (lv+=sum(length,t.steps)*log(t.step_scale))
    (;person,facets=fs,steps=tau,log_volume=lv,
      measure=:orthonormal_subspace_volume,basis=:helmert_ascending)
end

function _weights!(a,t,v,n)
    eta=v.person[t.person[n]]
    for b in t.facets;eta-=v.facets[b.name][b.index[n]];end
    a[1]=zero(eta)
    for k in 2:length(a);a[k]=a[k-1]+eta-v.steps[t.group[n],k-1];end
    B._logsumexp(a)
end

function logprior(t,q)
    _check(t,q)
    -length(q)*log(2pi)/2-sum(abs2,q)/2
end
function logprobs(t,q)
    v=coordinates(t,q); out=Matrix{eltype(v.person)}(undef,length(t.person),length(t.categories))
    for n in eachindex(t.person)
        a=view(out,n,:);c=_weights!(a,t,v,n);a.-=c
    end
    all(isfinite,out) || throw(ArgumentError("unrepresentable category log probabilities"))
    out
end
function pointwise(t,q)
    a=logprobs(t,q); [a[n,t.category[n]] for n in eachindex(t.person)]
end
function L.logdensity(t::Target,q::AbstractVector{<:Real})
    _check(t,q;finite=false)
    all(isfinite,q) || return oftype(float(q[1]),-Inf)
    v=coordinates(t,q); a=similar(v.person,length(t.categories));lp=logprior(t,q)
    for n in eachindex(t.person)
        c=_weights!(a,t,v,n);lp+=a[t.category[n]]-c
    end
    isfinite(lp) ? lp : oftype(lp,-Inf)
end
function L.logdensity_and_gradient(t::Target,q::AbstractVector{<:Real})
    _check(t,q;finite=false); Z=promote_type(Float64,eltype(q))
    rejected()=(-Z(Inf),fill(Z(NaN),length(q)))
    all(isfinite,q) || return rejected()
    v=coordinates(t,q); gp=zeros(Z,length(t.people))
    gf=Dict(b.name=>zeros(Z,length(b.levels)) for b in t.facets)
    gs=zeros(Z,size(v.steps));K=length(t.categories);a=zeros(Z,K);lp=logprior(t,q)
    for n in eachindex(t.person)
        c=_weights!(a,t,v,n);y=t.category[n];g=t.group[n];lp+=a[y]-c
        a.=exp.(a.-c);de=y-1-sum((k-1)*a[k] for k in 1:K)
        gp[t.person[n]]+=de
        for b in t.facets;gf[b.name][b.index[n]]-=de;end
        tail=zero(Z)
        for h in K-1:-1:1
            tail+=a[h+1];gs[g,h]+=tail-(y>h)
        end
    end
    isfinite(lp) || return rejected()
    grad=-Z.(q);grad[1:length(t.people)].+=t.person_sd.*gp
    for b in t.facets;S._helmert_pullback!(grad,b.raw,gf[b.name],b.scale);end
    for (g,r) in enumerate(t.steps);S._helmert_pullback!(grad,r,view(gs,g,:),t.step_scale);end
    all(isfinite,grad) ? (lp,grad) : rejected()
end

function names(t,scale)
    scale in (:raw,:model) || throw(ArgumentError("scale must be :raw or :model"))
    out=["person[$(repr(x))]" for x in t.people]
    for b in t.facets
        append!(out,scale===:raw ? ["$(b.name).white[$j]" for j in eachindex(b.raw)] :
            ["$(b.name)[$(repr(x))]" for x in b.levels])
    end
    for (g,r) in enumerate(t.steps)
        append!(out,["steps[$(repr(t.group_levels[g])),$j]" for j in 1:(scale===:raw ? length(r) : length(t.categories)-1)])
    end
    out
end

function record(t)
    (;schema="bayesianmgmfrm.additive_facet_design.v1",table=deepcopy(t.table),columns=deepcopy(t.columns),
      category_levels=copy(t.categories),steps=t.owner,
      levels=(;person=deepcopy(t.people),facets=(;(b.name=>deepcopy(b.levels) for b in t.facets)...)),
      prior_sd=(;person=t.person_sd,facets=(;(b.name=>b.sd for b in t.facets)...),step=t.step_sd),
      coordinates=:white,prior_scale=:reconstructed_marginal_sd,basis=:helmert_ascending)
end
function restore(r)
    r.schema=="bayesianmgmfrm.additive_facet_design.v1" && r.coordinates===:white &&
        r.prior_scale===:reconstructed_marginal_sd && r.basis===:helmert_ascending ||
        throw(ArgumentError("unsupported additive design record"))
    model(r.table;r.columns...,category_levels=r.category_levels,steps=r.steps,levels=r.levels,prior_sd=r.prior_sd)
end
function design(t)
    (;n_observations=length(t.person),n_persons=length(t.people),n_facets=length(t.facets)+1,
      facets=[(;name=b.name,column=b.column,levels=deepcopy(b.levels),observed_levels=length(unique(b.index)),
                marginal_prior_sd=b.sd,free_parameters=length(b.raw)) for b in t.facets],
      categories=copy(t.categories),category_counts=[count(==(k),t.category) for k in eachindex(t.categories)],
      step_owner=t.owner,step_groups=deepcopy(t.group_levels),n_parameters=t.dimension,
      allocation=deepcopy(t.allocation),grouping=t.groups,
      warnings=["Conditional independence and one stable trait are assumptions, not validated by rank.",
        "Experimental additive model: numerical qualification does not establish scientific validity or calibration.",
        (t.groups.performance_available ? "No residual performance effect is modeled." : "No performance IDs: repeated-performance dependence cannot be audited.")])
end

function contract(t)
    (;schema="bayesianmgmfrm.additive_facet_contract.v1",status=:experimental_fitted_workflow,
      family=t.owner===:global ? :scalar_additive_rsm : :scalar_additive_pcm,dimensions=1,multiplier=1,
      facet_names=[b.name for b in t.facets],facet_orientation=:higher_is_harder,
      constraints=:facet_and_step_sum_zero_person_free,prior_measure=:white_standard_normal,
      prior_scale=:reconstructed_marginal_sd,basis=:helmert_ascending,
      conditional_independence=:assumed,step_owner=t.owner,
      operations=(:mfrm_spec,:getdesign,:design_summary,:validate_design,:contract,:parameter_names,
          :coordinates,:logprior,:pointwise_loglikelihood,:logposterior,:logdensity_and_gradient,
          :stan_data,:prior_draw,:simulate,:prior_predictive_check,:predictive_probabilities,
          :fit,:sampler_controls,:diagnostics,:qualify,:posterior_summary,:posterior_mcse,
          :posterior_contrast,:fit_report,:save_fit,:load_fit,:save_report,:load_report),
      prediction=:fixed_coordinates_or_posterior_known_levels,fit_available=true,
      scientific_acceptance=false,record=record(t))
end

function prior_draw(t;seed=1)
    seed isa Integer && !(seed isa Bool) && 0<=seed<=typemax(Int) || throw(ArgumentError("seed must be a nonnegative integer representable as Int"))
    randn(MersenneTwister(Int(seed)),t.dimension)
end
function simulate(t;seed=1,q=nothing)
    # One common parameter draw per whole replicate preserves shared effects.
    prior=prior_draw(t;seed);truth=q===nothing ? prior : collect(q)
    probs=exp.(logprobs(t,truth));rng=MersenneTwister(Int(seed))
    # Advance past the prior draw consistently whether truth is supplied or not.
    randn(rng,t.dimension)
    cat=[min(searchsortedfirst(cumsum(view(probs,n,:)),rand(rng)),length(t.categories)) for n in eachindex(t.person)]
    data=deepcopy(t.table);data[t.columns.score]=t.categories[cat]
    (;seed=Int(seed),truth,simulated=data,category=cat,design=record(t),conditioning=:all_declared_effects)
end
function prior_check(t;ndraws=50,seed=1)
    ndraws isa Integer && !(ndraws isa Bool) && 1<=ndraws<=typemax(Int) || throw(ArgumentError("ndraws must be a positive integer"))
    prior_draw(t;seed) # validate before arithmetic
    ndraws-1<=typemax(Int)-seed || throw(ArgumentError("seed sequence overflows"))
    out=zeros(Int,Int(ndraws),length(t.categories))
    for j in 1:Int(ndraws)
        s=simulate(t;seed=seed+j-1)
        for k in eachindex(t.categories);out[j,k]=count(==(k),s.category);end
    end
    (;category_levels=copy(t.categories),replicated_counts=out,seed=Int(seed),ndraws=Int(ndraws),
      design=design(t),interpretation="Prior category-use simulation, not evidence of prior suitability or calibration.")
end

function stan_data(t)
    # Small independent-reference export. The native target uses direct dense
    # Helmert matrices, deliberately distinct from Julia's linear-time transform.
    P=length(t.people);F=length(t.facets);G=length(t.steps);H=length(t.categories)-1
    M=sum(b->length(b.levels),t.facets;init=0)
    Q=sum(b->length(b.raw),t.facets;init=0)
    A=zeros(M,Q);ix=zeros(Int,length(t.person),F);off=0;col=0
    for (j,b) in enumerate(t.facets)
        m=length(b.levels)
        for k in 1:m-1
            A[off+1:off+k,col+k].=b.scale/sqrt(k*(k+1))
            A[off+k+1,col+k]=-k*b.scale/sqrt(k*(k+1))
        end
        ix[:,j].=off.+b.index;off+=m;col+=m-1
    end
    Hstep=zeros(H,H-1)
    for k in 1:H-1
        Hstep[1:k,k].=t.step_scale/sqrt(k*(k+1));Hstep[k+1,k]=-k*t.step_scale/sqrt(k*(k+1))
    end
    Dict("N"=>length(t.person),"P"=>P,"F"=>F,"G"=>G,"K"=>H+1,"M"=>M,"Q"=>Q,
        "D"=>t.dimension,"person"=>copy(t.person),"facet_index"=>ix,"group"=>copy(t.group),
        "y"=>copy(t.category),"person_sd"=>t.person_sd,"A"=>A,"Hstep"=>Hstep)
end
include("additive_facets_workflow.jl")
end # module

"""
    mfrm_spec(table; person, score, facets, steps, prior_sd, category_levels,
              levels=nothing, performance=nothing, assessment=nothing)

Compile an experimental scalar additive RSM/PCM with any number of user-named
facets. `facets=(judge=:who, session=:when)` names effects and selects columns;
neither name has special behavior. `steps=:global` shares steps, while
`steps=:judge` assigns a centered step vector to each level of that named facet.
All slopes and the logit multiplier are one. Supply fixed prior SDs as
`(person=..., facets=(judge=..., session=...), step=...)`; they describe the
marginal SDs of reconstructed effects. An inactive singleton/binary-step block
requires zero SD. Active scales must be positive. No scientific defaults.

Inspect `design_summary`, `contract`, and `getdesign`, or use `prior_draw`,
`simulate`, `prior_predictive_check`, and the mathematical inspection functions.
Rank-deficient designs remain inspectable/generatable; fitting refuses them.
Use the shared fit, summary, prediction and save/load verbs for the experimental
fitted workflow. Check whole-fit diagnostics and focal MCSE separately. The existing
`mfrm_spec(::FacetData)` fitting route and its prior semantics are unchanged.

Input columns must be equally long; labels must be nonmissing strings, symbols
or integers. Categories are explicitly declared consecutive integer labels.
`levels=(person=[...], facets=(judge=[...], session=[...]))` preserves full panels
in subsets. Grouping IDs are retained, but do not add residual performance effects.
See the additive-facets guide for constraints, examples and unsupported combinations.
"""
mfrm_spec(table;kwargs...)=AdditiveFacets.model(table;kwargs...)
getdesign(t::AdditiveFacets.Target)=t
design_summary(t::AdditiveFacets.Target)=AdditiveFacets.design(t)
validate_design(t::AdditiveFacets.Target)=deepcopy(t.allocation)
contract(t::AdditiveFacets.Target)=AdditiveFacets.contract(t)
parameter_names(t::AdditiveFacets.Target;scale::Symbol=:raw)=AdditiveFacets.names(t,scale)
coordinates(t::AdditiveFacets.Target,q::AbstractVector{<:Real})=AdditiveFacets.coordinates(t,q)
logprior(t::AdditiveFacets.Target,q::AbstractVector{<:Real})=AdditiveFacets.logprior(t,q)
pointwise_loglikelihood(t::AdditiveFacets.Target,q::AbstractVector{<:Real})=AdditiveFacets.pointwise(t,q)
logposterior(t::AdditiveFacets.Target,q::AbstractVector{<:Real})=LogDensityProblems.logdensity(t,q)
prior_draw(t::AdditiveFacets.Target;kwargs...)=AdditiveFacets.prior_draw(t;kwargs...)
simulate(t::AdditiveFacets.Target;kwargs...)=AdditiveFacets.simulate(t;kwargs...)
prior_predictive_check(t::AdditiveFacets.Target;kwargs...)=AdditiveFacets.prior_check(t;kwargs...)
predictive_probabilities(t::AdditiveFacets.Target,q::AbstractVector{<:Real})=exp.(AdditiveFacets.logprobs(t,q))
stan_data(t::AdditiveFacets.Target)=AdditiveFacets.stan_data(t)
"""
    fit(spec::AdditiveFacets.Target; ndraws, warmup, chains, seed, kwargs...)

Fit an identified user-named scalar additive model with analytic-gradient NUTS.
Required counts and seed are explicit. Controls: target_accept=.9, max_depth=10,
step_size=.03, init_jitter=.1, metric=:diagonal, progress=false,
chain_execution=:serial, max_parallel_chains=chains. Inspect sampler_controls,
diagnostics, qualify and posterior_mcse; no retry or scientific acceptance is automatic.
"""
fit(t::AdditiveFacets.Target;kwargs...)=AdditiveFacets.fit(t;kwargs...)
getdesign(f::AdditiveFacets.Fit)=AdditiveFacets.checked(f)
design_summary(f::AdditiveFacets.Fit)=design_summary(getdesign(f))
validate_design(f::AdditiveFacets.Fit)=validate_design(getdesign(f))
contract(f::AdditiveFacets.Fit)=contract(getdesign(f))
parameter_names(f::AdditiveFacets.Fit;scale=:model)=parameter_names(getdesign(f);scale)
sampler_controls(f::AdditiveFacets.Fit)=(AdditiveFacets.checked(f);deepcopy(f.record.run.controls))
diagnostics(f::AdditiveFacets.Fit)=AdditiveFacets.diagnostics(f)
qualify(f::AdditiveFacets.Fit;kwargs...)=AdditiveFacets.qualify(f;kwargs...)
posterior_summary(f::AdditiveFacets.Fit;kwargs...)=AdditiveFacets.summary(f;kwargs...)
posterior_mcse(f::AdditiveFacets.Fit;kwargs...)=AdditiveFacets.mcse(f;kwargs...)
posterior_contrast(f::AdditiveFacets.Fit;kwargs...)=AdditiveFacets.contrast(f;kwargs...)
predictive_probabilities(f::AdditiveFacets.Fit;kwargs...)=AdditiveFacets.predict(f;kwargs...)
fit_report(f::AdditiveFacets.Fit;kwargs...)=AdditiveFacets.report(f;kwargs...)
save_fit(path::AbstractString,f::AdditiveFacets.Fit)=AdditiveFacets.save_result(path,f)
_save_report(path::AbstractString,f::AdditiveFacets.Fit;kwargs...)=
    AdditiveFacets.save_computed(path,fit_report(f;kwargs...))
