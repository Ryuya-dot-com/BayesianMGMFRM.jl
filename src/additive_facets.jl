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

abstract type AbstractTarget end

struct Target <: AbstractTarget
    table::Dict{Symbol,Vector}
    columns::NamedTuple
    person::Vector{Int}
    people::Vector{Any}
    category::Vector{Int}
    categories::Vector{Int}
    supports::Vector{UnitRange{Int}}
    facets::Vector{Block}
    owner::Symbol
    group::Vector{Int}
    group_levels::Vector{Any}
    steps::Vector{UnitRange{Int}}
    person_sd::Float64
    step_sd::Float64
    step_scale::Union{Float64,Vector{Float64}}
    dimension::Int
    allocation::NamedTuple
    groups::NamedTuple
end

include("additive_facets_support.jl")
include("additive_facets_patterns.jl")

function _sd(x, active, name)
    x isa Real && !(x isa Bool) && isfinite(x) || throw(ArgumentError("$name must be a finite real SD"))
    y=Float64(x)
    isfinite(y) && (active ? y>0 : y==0) ||
        throw(ArgumentError("$name must be $(active ? "positive" : "zero for an inactive block") after Float64 conversion"))
    y
end

_valid_facet_label(x) = x isa AbstractString || x isa Symbol || (x isa Integer && !(x isa Bool))

function _labels(values, name, declared=nothing)
    all(_valid_facet_label,values) || throw(ArgumentError("$name labels must be nonmissing strings, symbols or integers"))
    lev=declared===nothing ? B._stable_levels(values,name) : Any[declared...]
    !isempty(lev) && all(_valid_facet_label,lev) && length(unique(lev))==length(lev) ||
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
function _allocation(person, people, facets, group, supports, dimension)
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
    step_rank=sum(length(supports[g])-2 for g in unique(group))
    aliases=r==offset ? String[] : names[q.pcol[r+1:end]]
    (;rank=r+step_rank,columns=dimension,identified=r+step_rank==dimension,
      location_rank=r,location_columns=offset,step_rank,
      step_columns=sum(length(s)-2 for s in supports),method=:sparse_spqr_location_plus_centered_steps,
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
      performance_effect=any(b->b.column===perf,facets) ? [b.name for b in facets if b.column===perf] : :absent,conditional_independence=:assumed_not_tested)
end

function model(table;person::Symbol,score::Symbol,facets::NamedTuple,steps::Symbol,
        prior_sd::NamedTuple,category_levels,levels=nothing,
        performance::Union{Nothing,Symbol}=nothing,assessment::Union{Nothing,Symbol}=nothing)
    reserved=(:person,:steps,:global,:score,:performance,:assessment)
    all(k->!(k in reserved),keys(facets)) || throw(ArgumentError("facet names cannot use reserved roles $reserved"))
    all(x->x isa Symbol,values(facets)) || throw(ArgumentError("facet mapping values must be column symbols"))
    steps===:global || steps in keys(facets) || throw(ArgumentError("steps must be :global or a declared facet name"))
    selected=Symbol[person,score,values(facets)...]
    # Performance metadata may also name its explicitly declared residual facet.
    performance!==nothing && !(performance in values(facets)) && push!(selected,performance)
    assessment!==nothing && push!(selected,assessment)
    length(unique(selected))==length(selected) || throw(ArgumentError("each selected role must use a distinct column"))
    raw=Dict{Symbol,Vector}(c=>deepcopy(B._column(table,c)) for c in selected)
    n=length(raw[score]);n>0 || throw(ArgumentError("ratings cannot be empty"))
    for (c,x) in raw
        B._check_length!(n,x,c)
        c==score || _labels(x,c)
    end
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
    cat,categories,supports=_category_support(raw[score],score,category_levels,steps,group,groups)
    hs=length.(supports).-1
    sd=_sd(prior_sd.step,any(>(1),hs),:step_sd)
    scales=[h>1 ? sd*sqrt(h/(h-1)) : 0. for h in hs]
    all(isfinite,scales) || throw(ArgumentError("step prior transform scale overflows"))
    scale=all(==(first(scales)),scales) ? first(scales) : scales
    ranges=_step_ranges(supports,offset);dimension=last(last(ranges))
    columns=(;person,score,facets,performance,assessment)
    grouping=_groups(raw,columns,p,blocks)
    category_levels isa AbstractDict && (grouping=merge(grouping,(;category_support_by_owner=true)))
    allocation=_allocation(p,ps,blocks,group,supports,dimension)
    Target(raw,columns,p,ps,cat,categories,supports,blocks,steps,group,groups,ranges,
        person_sd,sd,scale,dimension,allocation,grouping)
end

L.dimension(t::AbstractTarget)=t.dimension
L.capabilities(::Type{<:AbstractTarget})=L.LogDensityOrder{1}()
function _check(t,q;finite=true)
    length(q)==t.dimension || throw(DimensionMismatch("expected $(t.dimension) white coordinates"))
    finite && !all(isfinite,q) && throw(ArgumentError("coordinates must be finite"))
    nothing
end

function coordinates(t::Target,q::AbstractVector{<:Real})
    _check(t,q); person=t.person_sd.*q[1:length(t.people)]
    fs=Dict(b.name=>b.scale.*N._zero_sum(view(q,b.raw)) for b in t.facets)
    tau=_step_coordinates(t,q)
    lv=length(t.people)*log(t.person_sd)
    for b in t.facets
        isempty(b.raw) || (lv+=length(b.raw)*log(b.scale))
    end
    lv+=_step_volume(t)
    (;person,facets=fs,steps=tau,log_volume=lv,
      measure=:orthonormal_subspace_volume,basis=:helmert_ascending)
end

response_shift(t,v,n)=zero(eltype(v.person))
function _weights!(a,t,v,n)
    eta=v.person[t.person[n]]+response_shift(t,v,n)
    for b in t.facets;eta-=v.facets[b.name][b.index[n]];end
    g=t.group[n];support=t.supports[g]
    fill!(a,oftype(eta,-Inf));a[first(support)]=zero(eta)
    for (h,k) in enumerate(support[2:end]);a[k]=a[k-1]+eta-v.steps[g,h];end
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
    all(n->all(isfinite,view(out,n,t.supports[t.group[n]])),eachindex(t.person)) ||
        throw(ArgumentError("unrepresentable category log probabilities"))
    out
end
function pointwise(t,q)
    a=logprobs(t,q); [a[n,t.category[n]] for n in eachindex(t.person)]
end
representable_scales(t,q)=true
function L.logdensity(t::AbstractTarget,q::AbstractVector{<:Real})
    _check(t,q;finite=false)
    all(isfinite,q) && representable_scales(t,q) || return oftype(float(q[1]),-Inf)
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
        _step_score!(gs,a,t,g,y)
    end
    isfinite(lp) || return rejected()
    grad=-Z.(q);grad[1:length(t.people)].+=t.person_sd.*gp
    for b in t.facets;S._helmert_pullback!(grad,b.raw,gf[b.name],b.scale);end
    for (g,r) in enumerate(t.steps)
        S._helmert_pullback!(grad,r,view(gs,g,1:_step_count(t,g)),_step_scale(t,g))
    end
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
        append!(out,["steps[$(repr(t.group_levels[g])),$j]" for j in 1:(scale===:raw ? length(r) : _step_count(t,g))])
    end
    out
end

function record(t)
    (;schema=_owned_support(t) ? "bayesianmgmfrm.additive_facet_design.v2" : "bayesianmgmfrm.additive_facet_design.v1",table=deepcopy(t.table),columns=deepcopy(t.columns),
      category_levels=_category_declaration(t),steps=t.owner,
      levels=(;person=deepcopy(t.people),facets=(;(b.name=>deepcopy(b.levels) for b in t.facets)...)),
      prior_sd=(;person=t.person_sd,facets=(;(b.name=>b.sd for b in t.facets)...),step=t.step_sd),
      coordinates=:white,prior_scale=:reconstructed_marginal_sd,basis=:helmert_ascending)
end
function restore(r)
    r.schema==MRCML_SCHEMA && return restore_mrcml(r)
    r.schema==MIXED_SCHEMA && return restore_mixed(r)
    r.schema==BOUNDED_SCHEMA && return restore_bounded(r)
    r.schema==COUNT_SCHEMA && return restore_count(r)
    r.schema in ("bayesianmgmfrm.explanatory_facet_design.v1","bayesianmgmfrm.explanatory_facet_design.v2","bayesianmgmfrm.explanatory_facet_design.v3") && return restore_explanatory(r)
    r.schema in ("bayesianmgmfrm.additive_facet_design.v1","bayesianmgmfrm.additive_facet_design.v2") && r.coordinates===:white &&
        r.prior_scale===:reconstructed_marginal_sd && r.basis===:helmert_ascending ||
        throw(ArgumentError("unsupported additive design record"))
    (r.schema=="bayesianmgmfrm.additive_facet_design.v2")== (r.category_levels isa AbstractDict) ||
        throw(ArgumentError("category support schema mismatch"))
    model(r.table;r.columns...,category_levels=r.category_levels,steps=r.steps,levels=r.levels,prior_sd=r.prior_sd)
end
function design(t)
    patterns=response_patterns(t)
    (;n_observations=length(t.person),n_persons=length(t.people),n_facets=length(t.facets)+1,
      facets=[(;name=b.name,column=b.column,levels=deepcopy(b.levels),observed_levels=length(unique(b.index)),
                marginal_prior_sd=b.sd,free_parameters=length(b.raw)) for b in t.facets],
      categories=copy(t.categories),category_counts=[count(==(k),t.category) for k in eachindex(t.categories)],
      category_support=[(;owner=t.owner,level=deepcopy(t.group_levels[g]),categories=copy(t.categories[s])) for (g,s) in enumerate(t.supports)],
      step_owner=t.owner,step_groups=deepcopy(t.group_levels),n_parameters=t.dimension,
      allocation=deepcopy(t.allocation),grouping=t.groups,response_patterns=patterns,
      warnings=["Conditional independence and one stable trait are assumptions, not validated by rank.",
        "Experimental additive model: numerical qualification does not establish scientific validity or calibration.",
        (t.groups.performance_effect!==:absent ? "Performance effects are declared explicitly; their dependence and information still require checking." : t.groups.performance_available ? "No residual performance effect is modeled." : "No performance IDs: repeated-performance dependence cannot be audited."),patterns.warnings...])
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
          :contrast,:posterior_contrast,:fit_report,:predictive_check,:plot,:save_fit,:load_fit,:save_report,:load_report),
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
    cat=[_sample_category(t,n,view(probs,n,:),rand(rng)) for n in eachindex(t.person)]
    data=deepcopy(t.table);data[t.columns.score]=t.categories[cat]
    (;seed=Int(seed),truth,simulated=data,category=cat,design=record(t),conditioning=:all_declared_effects)
end
function prior_check(t;ndraws=50,seed=1,interval=.95)
    interval_bounds(interval)
    ndraws isa Integer && !(ndraws isa Bool) && 1<=ndraws<=typemax(Int) || throw(ArgumentError("ndraws must be a positive integer"))
    prior_draw(t;seed) # validate before arithmetic
    ndraws-1<=typemax(Int)-seed || throw(ArgumentError("seed sequence overflows"))
    out=zeros(Int,Int(ndraws),length(t.categories))
    cells=[(g,k) for g in eachindex(t.supports) for k in t.supports[g]]
    owners=_owned_support(t) ? zeros(Int,Int(ndraws),length(cells)) : nothing
    for j in 1:Int(ndraws)
        s=simulate(t;seed=seed+j-1)
        for k in eachindex(t.categories);out[j,k]=count(==(k),s.category);end
        if owners!==nothing
            for (h,(g,k)) in enumerate(cells)
                owners[j,h]=count(i->t.group[i]==g && s.category[i]==k,eachindex(t.person))
            end
        end
    end
    prior_report(t,out;seed,interval,owner_counts=owners)
end

function stan_data(t)
    _owned_support(t) && throw(ArgumentError("Use mfrm_spec with category_levels by owner for the explanatory mixed-support Stan reference."))
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
include("explanatory_decomposition.jl")
include("explanatory_facets.jl")
include("bounded_facets.jl")
include("location_facets.jl")
include("location_slopes.jl")
include("bounded_distributional.jl")
include("count_facets.jl")
include("mixed_outcomes.jl")
include("mrcml_calibration.jl")
include("mrcml_design.jl")
include("additive_facets_workflow.jl")
include("explanatory_facets_workflow.jl")
include("bounded_facets_workflow.jl")
include("count_facets_workflow.jl")
include("mixed_outcomes_workflow.jl")
include("additive_facets_predictive.jl")
include("additive_facets_plot_reports.jl")
end # module

const MRCML = AdditiveFacets.MRCML

"""
    mfrm_spec(table; person, score, facets, steps, prior_sd, category_levels,
              levels=nothing, performance=nothing, assessment=nothing,
              population=nothing, predictors=nothing, intercept=nothing, decompose=nothing)

Compile an experimental scalar additive RSM/PCM with any number of user-named
facets. `facets=(judge=:who, session=:when)` names effects and selects columns;
neither name has special behavior. `steps=:global` shares steps, while
`steps=:judge` assigns a centered step vector to each level of that named facet.
All slopes and the logit multiplier are one. Supply fixed prior SDs as
`(person=..., facets=(judge=..., session=...), step=...)`; they describe the
marginal SDs of reconstructed effects. An inactive singleton/binary-step block
requires zero SD. Active scales must be positive. No scientific defaults.

Optional `population=(judge=LogNormal(logmedian, logsd),)` estimates an iid
residual SD instead of a finite sum-zero facet prior; a positive number fixes
that iid SD. Omit that owner's competing `prior_sd` entry. A `person` entry
similarly replaces `prior_sd.person`. `predictors=(person=(rate=Normal(mu,sd),),
judge=(experience=Normal(mu,sd),), response=(product=Normal(mu,sd),))` declares
numeric columns, ownership and coefficient priors. Owner columns must be constant
within that owner; named facet mean regressions require `population`. An optional
Normal `intercept` adds a global intercept. Units, centering and products are
user supplied. Positive facet coefficients increase severity; positive person/
response coefficients raise ratings. This additive population-severity hierarchy
is not Patz's ideal-rating HRM. See the explanatory-ratings guide for assumptions,
structural screens, prediction restrictions and the first-stage boundary.

With `performance=:talk_id`, `decompose=(rate=(between=:mean_rate,
within=:rate_change),)` creates person means over unique performances and deviations
in the original source units. Declare their coefficient priors in `predictors`.
The source must be constant within each performance. No implicit global centering,
scaling, detrending or residual performance effect is added. Known-performance
prediction preserves the training means. See the repeated-performances guide.

For coefficients of one numeric source that differ across a named facet, declare
`predictors=(response=(rate=(by=:rubric, prior=Normal(0,sd)),),)` with `rubric`
in `facets`. This expands full level-specific coefficients with independent copies
of the prior, retaining common source units for joint posterior contrasts. Do not
also add an unrestricted common coefficient for that same source. Facet names
remain user-defined; this is fixed moderation, not random slopes.

`category_levels=Dict("content"=>0:1, "delivery"=>1:5)` declares complete supports
for levels of the `steps` facet. Each support is consecutive and contains at least
two categories; shared global steps require a common vector instead. Binary
groups have a fixed zero centered step. Probabilities use the union of category
labels with structural zeros outside each row's support. Prediction/PPC retain
that support; raw-score means from different supports are not comparable.
See the criterion-effects guide for identification, priors and interpretation.

`validate_design(spec).response_patterns` reports unused interior/end categories
and constant person/facet scores within each steps-owner group, with IDs and
counts. These descriptive warnings retain all rows/categories and do not change
structural identification or numerical qualification. New fit/PPC reports retain
the audit; old saved reports retain their original contents.

Inspect `design_summary`, `contract`, and `getdesign`, or use `prior_draw`,
`simulate`, `prior_predictive_check`, and the mathematical inspection functions.
Rank-deficient designs remain inspectable/generatable; fitting refuses them.
Use the shared fit, summary, prediction and save/load verbs for the experimental
fitted workflow. Check whole-fit diagnostics and focal MCSE separately. The existing
`mfrm_spec(::FacetData)` fitting route and its prior semantics are unchanged.

For a bounded score, supply `observation=(family=:zero_one_inflated_beta, bounds=(lo,hi))`,
`observation_prior=(precision=LogNormal(...), endpoint_logit=Normal(...), upper_logit=Normal(...))`,
and explicit `population` SDs for every owner, predictors and an intercept prior.
Entries in `observation_prior` may instead declare `(intercept=prior,
predictors=(owner=(x=Normal(...),),), population=(owner=SDprior,))`.
Precision uses a log link; endpoint/conditional-upper probabilities use logits.
All distributional effects add, including facet effects; blocks are independent.
Do not supply categories/steps to that route. See the bounded-scores guide; it
uses original-unit densities plus endpoint atoms, not ordinal probabilities.
For scalar ZOIB only, replace an owner's population SD with
`(intercept=LogNormal(...), slopes=(rate_change=LogNormal(...),), correlation=LKJ(2,2))`
to add one correlated random slope. Numeric `correlation=0` fixes independence.
Declare the same column's common response coefficient in `predictors`.
Any owner name is allowed, but only one slope per owner in this combination.
Slopes act on the interior-mean link, not rater discrimination. See random-slopes.

For correct counts, use `observation=(family=:binomial, trials=:total_column)`
or `family=:beta_binomial` with `observation_prior=(precision=LogNormal(...),)`.
The score column holds integer successes, not proportions. Positive integer trial
counts are required; no automatic rounding or denominator reconstruction occurs.

For multi-outcome speaking/assessment events combining `:ordinal`, `:zero_one_inflated_beta`,
`:binomial`, and `:beta_binomial` channels on the same event table (with optional `missing`
partial-outcome cells), supply `outcomes=(accent=(family=:zero_one_inflated_beta, ...),
comp=(family=:ordinal, ...), intel=(family=:beta_binomial, ...))` and matrix-driven
or shared owner declarations in `population`. See the mixed-outcomes guide for
loading/correlation identification, joint paired PPC, held-performance integration,
and distinct `mode=:known_owners` vs. `mode=:new_owners` prediction contracts.

For a scalar ordinal transfer, `fixed_calibration=(facets=(item=locations,),
steps=(owner=:global, values=Dict(:global=>steps_by_upper_score)))` fixes external
logit locations and centered adjacent-category steps by label. Optional blocks
can be omitted. Supply `estimate_mean=true` to marginal maximum likelihood, or
declare an `intercept=Normal(mu,sd)` and explicit `prior_sd` for the Bayesian
population mean. Uncertainty is conditional on the supplied fixed calibration.
Use `fixed_calibration=(groups=[(block=:item, levels=["a","b"], mean=0.4)],)`
to fix an equally weighted subset mean while estimating its member contrasts.
Use `sum` for a fixed total. The facet SD applies to a unit-length free contrast.
To fix a doubly centered interaction residual, declare its facet pair in
`interactions` and supply e.g. `fixed_calibration=(cells=[(levels=(rater="R1",
item="I1"),value=0.6)],)`. Positive residuals lower the adjacent-category logit.
Use `calibration=(coordinates=rows, covariance=V)` for uncertainty transfer.
Each row names its facet block, level and estimate. A step also names its owner
and upper category. List independent coordinates in the order of the axes of V.
For independently sampled panels, MMLE propagates this covariance to the
receiving population mean or to each group-versus-reference contrast in a
grouped population. See `design_summary(fit_result).calibration` for conditional
and propagated SEs. In the single-panel Bayesian mean model, NUTS uses the
joint Gaussian calibration distribution when the other model priors are supplied.

Use `population=(roster=people, person=:id, group=:study, reference="first",
covariates=(:practice,))` for linked group means, common slopes and group-specific
SDs. For NUTS, add independent `coefficient_prior=Normal(...)` and
`sd_prior=LogNormal(...)` to that declaration and supply the measurement priors.

Input columns must be equally long; labels must be nonmissing strings, symbols
or integers. For ordinal scores, categories are explicitly declared consecutive integer labels.
`levels=(person=[...], facets=(judge=[...], session=[...]))` preserves full panels
in subsets. Grouping IDs are retained, but do not add residual performance effects.
See the additive-facets guide for constraints, examples and unsupported combinations.
"""
function mfrm_spec(table;outcomes=nothing,observation=nothing,population=nothing,predictors=nothing,intercept=nothing,decompose=nothing,interactions=nothing,lltm=nothing,design_matrix=nothing,fixed_calibration=nothing,calibration=nothing,kwargs...)
    if population isa NamedTuple && haskey(population,:roster) && get(population,:group,nothing) isa Symbol
        all(isnothing,(outcomes,observation,predictors,intercept,decompose)) ||
            throw(ArgumentError("a roster population supplies the scalar location and common person covariates"))
        if !isnothing(design_matrix)
            isempty(kwargs) && all(isnothing,(interactions,lltm,fixed_calibration,calibration)) ||
                throw(ArgumentError("an explicit design_matrix already defines its measurement model"))
            return mfrm_spec(design_matrix; population)
        end
        opt = (;kwargs...)
        if !isnothing(get(opt,:prior_sd,nothing))
            pri = opt.prior_sd
            pri isa NamedTuple || throw(ArgumentError("prior_sd must declare the scalar measurement scales"))
            opt = merge(opt,(;prior_sd=merge((person=1.0,),pri)))
        end
        s = AdditiveFacets.compile_structured_mrcml(table; fixed_calibration,calibration,
            interactions,lltm,opt...)
        return mfrm_spec(s; population)
    end
    if design_matrix!==nothing
        (outcomes===nothing && observation===nothing && population===nothing && predictors===nothing && intercept===nothing && decompose===nothing && interactions===nothing && lltm===nothing && fixed_calibration===nothing && calibration===nothing) ||
            throw(ArgumentError("design_matrix=... supplies an explicit MRCML specification and cannot be combined with structured outcomes, predictors, interactions, or lltm"))
        design_matrix isa Union{AdditiveFacets.MRCMLTarget,AdditiveFacets.MRCMLSpec} ||
            throw(ArgumentError("design_matrix must be an MRCMLTarget or MRCMLSpec built with `BayesianMGMFRM.MRCML`"))
        return design_matrix
    end
    if fixed_calibration !== nothing || calibration !== nothing
        all(isnothing,(outcomes,observation,population,predictors,decompose)) ||
            throw(ArgumentError("fixed_calibration requires the scalar ordinal MRCML specification"))
        return AdditiveFacets.compile_structured_mrcml(table; fixed_calibration, calibration, intercept, interactions, lltm, kwargs...)
    end
    if interactions!==nothing || lltm!==nothing || (haskey(kwargs,:steps) && kwargs[:steps] isa Tuple)
        (outcomes===nothing && observation===nothing && population===nothing && predictors===nothing && intercept===nothing && decompose===nothing) ||
            throw(ArgumentError("structured MRCML `interactions`, `lltm`, and tuple `steps` apply to 1D ordinal facet models without `outcomes`, `observation`, `population`, or `predictors`; supply hierarchical interaction SDs inside `prior_sd`"))
        return AdditiveFacets.compile_structured_mrcml(table;interactions,lltm,kwargs...)
    end
    if outcomes!==nothing
        observation===nothing && intercept===nothing || throw(ArgumentError("outcomes=... cannot be combined with scalar observation=... or scalar intercept=...; declare per-outcome intercepts in outcomes or predictors"))
        population!==nothing || throw(ArgumentError("outcomes=... requires explicit population declarations for every owner"))
        return AdditiveFacets.mixed_outcome_model(table;outcomes,population,predictors=predictors===nothing ? (;) : predictors,decompose,kwargs...)
    end
    observation!==nothing ? AdditiveFacets.observation_model(table;observation,population,
        predictors=predictors===nothing ? (;) : predictors,intercept,decompose,kwargs...) :
    population===nothing && predictors===nothing && intercept===nothing && decompose===nothing && !(get(kwargs,:category_levels,nothing) isa AbstractDict) ?
    (haskey(kwargs,:prior_sd) ? AdditiveFacets.model(table;kwargs...) : FrequentistMFRM.build_spec(table;kwargs...)) :
    AdditiveFacets.explanatory_model(table;
        population=population===nothing ? (;) : population,
        predictors=predictors===nothing ? (;) : predictors,intercept,decompose,kwargs...)
end
mfrm_spec(s::Union{AdditiveFacets.MRCMLSpec,AdditiveFacets.MRCMLTarget}; population::NamedTuple) =
    MRCML._with_population(s,population)

"""
    mfrm_spec(spec::FacetSpec; fixed_calibration, prior_sd=nothing, intercept=nothing, interactions=nothing)

Build a scalar MRCML equating specification from the labeled persons, raters,
items and category scale in a Rasch facet specification. Named location anchors
are absolute logit locations. A cell in a declared facet-by-facet interaction
fixes its additional severity after the main effects and retains both zero
margins. Unanchored facets use the structured sum-zero coding. Supply Bayesian
priors explicitly for the free coordinates.
"""
function mfrm_spec(spec::FacetSpec; fixed_calibration=nothing, calibration=nothing, prior_sd=nothing, intercept=nothing, interactions=nothing)
    isnothing(fixed_calibration) && isnothing(calibration) && throw(ArgumentError("supply fixed_calibration or calibration"))
    spec.family === :mfrm && spec.dimensions == 1 && spec.discrimination === :none &&
        isnothing(spec.q_matrix) && isempty(spec.validation_bias_terms) ||
        throw(ArgumentError("named fixed calibration requires a scalar unit-slope MFRM without Q or DFF"))
    if !isempty(spec.anchors)
        isnothing(calibration) || throw(ArgumentError("declare the joint transfer on a FacetSpec without existing fixed anchors"))
        fixed_calibration isa NamedTuple || throw(ArgumentError("fixed_calibration must be a named tuple"))
        declared = get(fixed_calibration, :facets, (;))
        declared isa NamedTuple && all(v -> v isa AbstractDict, values(declared)) ||
            throw(ArgumentError("fixed_calibration.facets must map facet roles to dictionaries"))
        combined = Dict{Symbol,Dict{Any,Any}}(k => Dict{Any,Any}(pairs(v)) for (k,v) in pairs(declared))
        for anchor in spec.anchors
            role = _stable_anchor_block(anchor.block)
            role in (:rater,:item) && anchor.anchor_type === :hard_anchor && ismissing(anchor.anchor_scale) ||
                throw(ArgumentError("only fixed rater and item locations can be imported from FacetSpec.anchors"))
            level = _anchor_target(anchor)
            dict = get!(combined, role, Dict{Any,Any}())
            haskey(dict,level) && dict[level] != anchor.value &&
                throw(ArgumentError("conflicting calibrations for $role level $(repr(level))"))
            dict[level] = anchor.value
        end
        fixed_calibration = merge(fixed_calibration, (; facets=(; combined...)))
    end
    d = spec.data
    facets = isnothing(d.columns.rater) ? (item=:item,) : (rater=:rater, item=:item)
    facet_levels = isnothing(d.columns.rater) ? (item=d.item_levels,) : (rater=d.rater_levels, item=d.item_levels)
    table = (person=d.person_levels[d.person], item=d.item_levels[d.item], score=d.score)
    if !isnothing(d.columns.rater)
        table = merge(table, (rater=d.rater_levels[d.rater],))
    end
    assessment = nothing
    if haskey(d.optional,:response_id)
        table = merge(table, (response_id=d.optional_levels[:response_id][d.optional[:response_id]],))
        assessment = :response_id
    end
    levels = (person=d.person_levels, facets=facet_levels)
    return mfrm_spec(table; person=:person, score=:score, facets,
        steps=spec.thresholds === :rating_scale ? :global : :item, category_levels=d.category_levels,
        levels, fixed_calibration, calibration, prior_sd, intercept, assessment, interactions)
end

getdesign(t::AdditiveFacets.AbstractTarget)=t
design_summary(t::AdditiveFacets.AbstractTarget)=AdditiveFacets.design(t)
function validate_design(t::AdditiveFacets.AbstractTarget)
    patterns=AdditiveFacets.response_patterns(t)
    extra_w=String[]
    hasproperty(t.allocation,:slope_warnings) && append!(extra_w,t.allocation.slope_warnings)
    hasproperty(t,:prior_symmetry) && append!(extra_w,t.prior_symmetry.warnings)
    base=merge(deepcopy(t.allocation),(;response_patterns=patterns,warnings=[patterns.warnings;extra_w]))
    hasproperty(t,:prior_symmetry) ? merge(base,(;prior_symmetry=deepcopy(t.prior_symmetry))) : base
end
contract(t::AdditiveFacets.AbstractTarget)=AdditiveFacets.contract(t)
parameter_names(t::AdditiveFacets.AbstractTarget;scale::Symbol=:raw)=AdditiveFacets.names(t,scale)
coordinates(t::AdditiveFacets.AbstractTarget,q::AbstractVector{<:Real})=AdditiveFacets.coordinates(t,q)
logprior(t::AdditiveFacets.AbstractTarget,q::AbstractVector{<:Real})=AdditiveFacets.logprior(t,q)
pointwise_loglikelihood(t::AdditiveFacets.AbstractTarget,q::AbstractVector{<:Real})=AdditiveFacets.pointwise(t,q)
logposterior(t::AdditiveFacets.AbstractTarget,q::AbstractVector{<:Real})=LogDensityProblems.logdensity(t,q)
prior_draw(t::AdditiveFacets.AbstractTarget;kwargs...)=AdditiveFacets.prior_draw(t;kwargs...)
simulate(t::AdditiveFacets.AbstractTarget;kwargs...)=AdditiveFacets.simulate(t;kwargs...)
"""
    prior_predictive_check(target::AdditiveFacets.AbstractTarget; ndraws=50, seed=1, interval=.95)

Generate predictive statistics from the declared prior at the declared design.
This uses new random draws, not a fitted posterior. Ordinal models report category
counts, with mixed supports separated by steps owner. Bounded models report
endpoint rates and overall/interior score moments. Count models summarize zero/
perfect rates and counts/proportions, grouped by trial count by default. Reports retain the replicated
statistics, grouping, declared units and warnings;
`plot(report; kind=:predictive)`, `save_report` and `load_report` reuse it without
regeneration. Prior predictive intervals are not posterior intervals; predictive
endpoint MCSE and prior suitability are not established by this operation.
"""
prior_predictive_check(t::AdditiveFacets.AbstractTarget;kwargs...)=AdditiveFacets.prior_check(t;kwargs...)
predictive_probabilities(t::AdditiveFacets.AbstractTarget,q::AbstractVector{<:Real})=exp.(AdditiveFacets.logprobs(t,q))
stan_data(t::AdditiveFacets.AbstractTarget)=AdditiveFacets.stan_data(t)
"""
    fit(spec::AdditiveFacets.Target; ndraws, warmup, chains, seed, kwargs...)

Fit an identified user-named scalar additive model with analytic-gradient NUTS.
Required counts and seed are explicit. Controls: target_accept=.9, max_depth=10,
step_size=.03, init_jitter=.1, metric=:diagonal, progress=false,
chain_execution=:serial, max_parallel_chains=chains. Inspect sampler_controls,
diagnostics, qualify and posterior_mcse; no retry or scientific acceptance is automatic.
"""
function fit(t::AdditiveFacets.AbstractTarget;method::Union{Nothing,Symbol}=nothing,kwargs...)
    (method===nothing || (method===:nuts && t isa AdditiveFacets.MRCMLTarget)) && return AdditiveFacets.fit(t;kwargs...)
    any(k->k in (:target_accept,:adapt_delta,:max_depth,:max_treedepth),keys(kwargs)) &&
        throw(ArgumentError("NUTS controls (`target_accept`/`adapt_delta`, `max_depth`/`max_treedepth`) do not apply to frequentist `method = $(repr(method))`"))
    return FrequentistMFRM.fit(t;method,kwargs...)
end
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
contrast(f::AdditiveFacets.Fit;kwargs...)=posterior_contrast(f;kwargs...)
"""
    predictive_probabilities(fit::AdditiveFacets.Fit; rows=nothing, data=nothing, interval=.95)

Summarize category probabilities over retained joint draws for known owners and
stored attributes. `rows` selects input rating rows. `cells` retains means and
pointwise credible intervals, category order and structural zeros; `mcse` keeps
probability precision and `selected_columns` retains row attributes. These are
probability intervals, not future-rating predictive intervals. Save/reopen the
computed report, then `plot(report; kind=:prediction)` without simulation.
No new-owner or changed owner-attribute prediction is implied.
"""
function predictive_probabilities(f::AdditiveFacets.Fit;kwargs...)
    getdesign(f) isa Union{AdditiveFacets.BoundedTarget,AdditiveFacets.CountTarget,AdditiveFacets.MixedOutcomeTarget} && throw(ArgumentError("use predict(fit) for bounded, count, or mixed-outcome moments and endpoint probabilities"))
    AdditiveFacets.predict(f;kwargs...)
end
"""
    fit_report(fit::AdditiveFacets.Fit; parameters=nothing, scale=:model,
               interval=.95, include_draws=false)

Keep summaries, MCSE, whole-fit diagnostics and model warnings. With
`include_draws=true`, also keep selected parameter traces in original retained
chain/iteration order for `plot(report; kind=:diagnostics)`. Select a small set of named
parameters to control report size. Warmup telemetry remains in diagnostics but
warmup states are not plotted. Saving/reopening the report does not refit or
thin draws. A trace plot does not establish convergence or scientific adequacy.
"""
fit_report(f::AdditiveFacets.Fit;kwargs...)=AdditiveFacets.report(f;kwargs...)
predictive_check(f::AdditiveFacets.Fit;kwargs...)=AdditiveFacets.posterior_check(f;kwargs...)
plot(f::AdditiveFacets.Fit;kind=:posterior,kwargs...)=_plot_additive_report(f;kind,kwargs...)

function _plot_additive_report(x;kind=:posterior,return_data=false,size=nothing,annotation_io=stdout,reference=nothing,interval_colors=nothing,kwargs...)
    kind in (:posterior,:predictive,:diagnostics,:prediction) || throw(ArgumentError("additive plot kind must be :posterior, :predictive, :diagnostics or :prediction"))
    kind===:posterior || (reference===nothing && interval_colors===nothing) ||
        throw(ArgumentError("reference coloring applies to posterior parameter CrIs, not predictive intervals"))
    rep=if x isa AdditiveFacets.Fit
        if kind in (:posterior,:diagnostics)
            kind===:diagnostics && !haskey(kwargs,:parameters) && throw(ArgumentError("select parameters explicitly for a trace plot"))
            t=getdesign(x)
            defaults=t isa AdditiveFacets.MixedOutcomeTarget ?
                (;parameters=[n for n in parameter_names(x) if startswith(n,"intercept[") || startswith(n,"coefficient[") || startswith(n,"residual_sd[") || startswith(n,"correlation[") || startswith(n,"loading[")]) :
                t isa Union{AdditiveFacets.ExplanatoryTarget,AdditiveFacets.BoundedTarget,AdditiveFacets.CountTarget} ?
                (;parameters=[n for n in parameter_names(x) if startswith(n,"coefficient[") || startswith(n,"residual_sd[")]) : (;)
            kind===:diagnostics && (defaults=merge(defaults,(;include_draws=true)))
            fit_report(x;merge(defaults,(;kwargs...))...)
        elseif kind===:prediction
            predict(x;kwargs...)
        else
            predictive_check(x;kwargs...)
        end
    else
        isempty(kwargs) || throw(ArgumentError("saved additive plots accept no numerical controls; compute a new report from the native fit"))
        x
    end
    expected=kind in (:posterior,:diagnostics) ? (AdditiveFacets.REPORT_SCHEMA,) : kind===:prediction ?
        (AdditiveFacets.PREDICTION_SCHEMA,AdditiveFacets.BOUNDED_PREDICTION_SCHEMA,AdditiveFacets.COUNT_PREDICTION_SCHEMA,AdditiveFacets.MIXED_PREDICTION_SCHEMA) : (AdditiveFacets.PPC_SCHEMA,AdditiveFacets.PRIOR_SCHEMA,AdditiveFacets.BOUNDED_PPC_SCHEMA,AdditiveFacets.COUNT_PPC_SCHEMA,AdditiveFacets.MIXED_PPC_SCHEMA)
    rep.schema in expected || throw(ArgumentError("report schema does not match plot kind"))
    kind===:diagnostics && !hasproperty(rep,:traces) && throw(ArgumentError("trace plotting needs fit_report(...;include_draws=true)"))
    AdditiveFacets.check_plot_report(rep)
    style=kind===:posterior ? AdditiveFacets.interval_style(rep.summary.rows;reference,interval_colors) : nothing
    extension=Base.get_extension(@__MODULE__,:BayesianMGMFRMCairoMakieExt)
    extension===nothing && throw(ArgumentError("plot requires `using CairoMakie`"))
    figure=extension.plot_additive_report(rep;kind,size,annotation_io,style)
    return_data ? (;figure,data=rep) : figure
end
save_fit(path::AbstractString,f::AdditiveFacets.Fit)=AdditiveFacets.save_result(path,f)
_save_report(path::AbstractString,f::AdditiveFacets.Fit;kwargs...)=
    AdditiveFacets.save_computed(path,fit_report(f;kwargs...))

"""
    predict(spec::Union{AdditiveFacets.BoundedTarget,AdditiveFacets.CountTarget}, q)
    predict(fit::AdditiveFacets.Fit; rows, data=nothing, interval=.95)

For bounded scores, `metrics` also selects `:precision`, `:endpoint_probability`,
`:upper_given_endpoint_probability`, `:interior_sd`, or `:score_sd`. These are
conditional parameters; their CrIs are not individual prediction intervals.
By default return original-unit total/interior means and both endpoint
probabilities. For counts, return expected correct counts/proportions and zero/
perfect probabilities at the declared trial counts. Fit reports retain posterior credible intervals and MCSE for known
owners; these are not future-score predictive intervals. For ordinal fits this
uses the existing category-probability operation.
"""
predict(t::AdditiveFacets.BoundedTarget,q::AbstractVector;metrics=(:interior_mean,:expected_score,:lower_probability,:upper_probability))=
    AdditiveFacets.bounded_moments(t,q;metrics)
predict(f::AdditiveFacets.Fit;kwargs...)=AdditiveFacets.predict(f;kwargs...)

predict(t::AdditiveFacets.CountTarget,q::AbstractVector)=AdditiveFacets.count_moments(t,q)
predict(t::AdditiveFacets.MixedOutcomeTarget,q::AbstractVector)=AdditiveFacets.mixed_moments(t,q)
