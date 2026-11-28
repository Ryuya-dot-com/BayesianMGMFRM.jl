# Included in AdditiveFacets. The old finite-panel Target/record stays intact.
import Distributions as D

struct ResidualBlock
    name::Symbol
    kind::Symbol
    raw::UnitRange{Int}
    sd::Float64
    logmean::Float64
    logsd::Float64
    hyper::Int
    scale_kind::Symbol
end
ResidualBlock(name,kind,raw,sd,logmean,logsd,hyper) =
    ResidualBlock(name,kind,raw,sd,logmean,logsd,hyper,hyper == 0 ? :fixed : :lognormal)
struct MeanTerm
    owner::Symbol
    column::Union{Nothing,Symbol}
    mean::Float64
    sd::Float64
    raw::Int
    values::Vector{Float64}
    by::Union{Nothing,Symbol}
    level::Any
end
MeanTerm(owner,column,mean,sd,raw,values)=MeanTerm(owner,column,mean,sd,raw,values,nothing,nothing)

struct ExplanatoryTarget <: AbstractTarget
    base::Target
    table::Dict{Symbol,Vector}
    residuals::Vector{ResidualBlock}
    terms::Vector{MeanTerm}
    steps::Vector{UnitRange{Int}}
    dimension::Int
    allocation::NamedTuple
    specification::NamedTuple
end

# Common rating identities and step metadata come from the unchanged compiler.
# Explanatory coordinates, table, ranges and admissibility are owned by this type.
function Base.getproperty(t::ExplanatoryTarget,k::Symbol)
    k in fieldnames(ExplanatoryTarget) ? getfield(t,k) : getproperty(getfield(t,:base),k)
end
Base.propertynames(t::ExplanatoryTarget)=unique((fieldnames(ExplanatoryTarget)...,fieldnames(Target)...))

function _normal_parameters(p,label)
    p isa D.Normal || throw(ArgumentError("$label requires an explicit Normal(mean, sd) coefficient prior"))
    mu,sd=Float64.(D.params(p))
    isfinite(mu) && isfinite(sd) && sd>0 || throw(ArgumentError("$label prior parameters must be finite with sd > 0"))
    (;mean=mu,sd)
end
function _population_parameters(p,label; zero_support::Bool=false)
    if p isa Real
        !(p isa Bool) && isfinite(p) || throw(ArgumentError("$label must be a finite real SD"))
        y=Float64(p)
        y==0 && return (;kind=:fixed,sd=0.0)
        return (;kind=:fixed,sd=_sd(p,true,label))
    end
    if zero_support && p isa D.Truncated
        parsed = _parse_scale_or_lognormal(p,true,label)
        return (;kind=parsed.kind,logmean=parsed.logmean,logsd=parsed.logsd)
    end
    p isa D.LogNormal || throw(ArgumentError("$label requires a nonnegative fixed SD or supported residual SD prior"))
    mu,sd=Float64.(D.params(p))
    isfinite(mu) && isfinite(sd) && sd>0 && isfinite(exp(mu)) && exp(mu)>0 ||
        throw(ArgumentError("$label lognormal parameters must be finite and have a representable median and logsd > 0"))
    (;kind=:lognormal,logmean=mu,logsd=sd)
end
function _numeric_column(table,c,n)
    x=collect(B._column(table,c));B._check_length!(n,x,c)
    all(v->v isa Real && !(v isa Bool) && isfinite(v),x) ||
        throw(ArgumentError("predictor $c must contain finite nonmissing real values; encode categories explicitly"))
    y=Float64.(x);all(isfinite,y) || throw(ArgumentError("predictor $c overflows Float64"))
    y
end
_owner_index(t,name)=name===:person ? t.person : only(b.index for b in t.facets if b.name===name)
_owner_levels(t,name)=name===:person ? t.people : only(b.levels for b in t.facets if b.name===name)
function _owned_values(t,name,c,x)
    idx=_owner_index(t,name);out=fill(NaN,length(_owner_levels(t,name)))
    for n in eachindex(x)
        j=idx[n]
        isnan(out[j]) || out[j]==x[n] || throw(ArgumentError("predictor $c changes within $name level $(repr(_owner_levels(t,name)[j])); use the actual owner or an explicit response predictor"))
        out[j]=x[n]
    end
    all(isfinite,out) || throw(ArgumentError("predictor $c is missing for an unobserved declared $name level"))
    out
end
_term_name(x)=x.column===nothing ? "coefficient[intercept]" : x.by===nothing ?
    "coefficient[$(x.owner),$(x.column)]" : "coefficient[$(x.owner),$(x.column);$(x.by)=$(repr(x.level))]"

function _predictor_prior(p,owner,facets,label)
    p isa NamedTuple || return _normal_parameters(p,label)
    _keys(p,(:by,:prior),label)
    owner===:response || throw(ArgumentError("by-facet coefficients must be declared in predictors.response"))
    p.by isa Symbol && p.by in keys(facets) || throw(ArgumentError("by must name a declared facet"))
    merge(_normal_parameters(p.prior,label),(;by=p.by))
end
_expanded_terms(t)=any(p->p.by!==nothing,t.terms)

function explanatory_model(table;person::Symbol,score::Symbol,facets::NamedTuple,steps::Symbol,
        prior_sd::NamedTuple,category_levels,population::NamedTuple=(;),predictors::NamedTuple=(;),
        intercept=nothing,decompose=nothing,levels=nothing,performance=nothing,assessment=nothing,
        missing_audit=nothing)
    :response in keys(facets) && throw(ArgumentError(":response is reserved for response predictors"))
    owners=(:person,keys(facets)...)
    all(k->k in owners,keys(population)) || throw(ArgumentError("population names must be :person or declared facet names"))
    all(k->k in (owners...,:response),keys(predictors)) || throw(ArgumentError("predictor owners must be :person, :response or declared facets"))
    _keys(prior_sd,:person in keys(population) ? (:facets,:step) : (:person,:facets,:step),:prior_sd)
    finite=filter(k->!(k in keys(population)),keys(facets))
    _keys(prior_sd.facets,finite,:facet_prior_sd)
    pop=(;(k=>_population_parameters(v,k;zero_support=true) for (k,v) in pairs(population))...)
    # Placeholder scales compile the unchanged identity/finite-step structure;
    # population coordinates never use the placeholder facet priors.
    fs=(;(k=>(k in keys(pop) ? (length(unique(B._column(table,c)))>1 ? 1. : 0.) : prior_sd.facets[k])
        for (k,c) in pairs(facets))...)
    base=model(table;person,score,facets,steps,category_levels,levels,performance,assessment,missing_audit,
        prior_sd=(person=:person in keys(pop) ? 1. : prior_sd.person,facets=fs,step=prior_sd.step))
    n=length(base.person);raw=deepcopy(base.table);res=ResidualBlock[];offset=0
    derived,decomposition=decompose===nothing ? (Dict{Symbol,Vector}(),nothing) : decompose_predictors(base,table,decompose)
    merge!(raw,derived)
    for owner in owners
        m=length(_owner_levels(base,owner));iid=owner===:person || owner in keys(pop)
        sd=owner===:person ? base.person_sd : only(b.scale for b in base.facets if b.name===owner)
        if owner in keys(pop)
            p=pop[owner];sd=p.kind===:fixed ? p.sd : 1.
            p.kind!==:fixed && m<2 && throw(ArgumentError("estimated population SD for $owner needs at least two observed levels"))
        end
        d=sd==0.0 ? 0 : (iid ? m : m-1)
        push!(res,ResidualBlock(owner,iid ? :iid_population : :finite_sum_zero,offset+1:offset+d,
            sd,0.,0.,0));offset+=d
    end
    ranges=_step_ranges(base.supports,offset)
    offset=last(last(ranges))
    terms=MeanTerm[];predrec=Pair{Symbol,Any}[]
    for (owner,cols) in pairs(predictors)
        _named(cols,"predictors.$owner")
        owner!==:person && owner!==:response && !(owner in keys(pop)) &&
            throw(ArgumentError("mean regression for facet $owner requires declaring it in population; finite zero-sum effects have a different prior"))
        crecs=Pair{Symbol,Any}[]
        for (c,p) in pairs(cols)
            c in keys(base.table) && throw(ArgumentError("predictor $c cannot reuse a score or identity column"))
            x=haskey(derived,c) ? derived[c] : _numeric_column(table,c,n);raw[c]=x;pp=_predictor_prior(p,owner,facets,"$owner.$c")
            if hasproperty(pp,:by)
                ids=_owner_index(base,pp.by)
                for (j,lev) in enumerate(_owner_levels(base,pp.by))
                    push!(terms,MeanTerm(owner,c,pp.mean,pp.sd,offset+1,x.*(ids.==j),pp.by,lev));offset+=1
                end
            else
                values=owner===:response ? x : _owned_values(base,owner,c,x)
                push!(terms,MeanTerm(owner,c,pp.mean,pp.sd,offset+1,values));offset+=1
            end
            push!(crecs,c=>pp)
        end
        push!(predrec,owner=>(;crecs...))
    end
    ip=intercept===nothing ? nothing : _normal_parameters(intercept,:intercept)
    if ip!==nothing
        push!(terms,MeanTerm(:response,nothing,ip.mean,ip.sd,offset+1,ones(n)));offset+=1
    end
    for i in eachindex(res)
        r=res[i]
        if r.name in keys(pop) && pop[r.name].kind!==:fixed
            p=pop[r.name];offset+=1
            res[i]=ResidualBlock(r.name,r.kind,r.raw,r.sd,p.logmean,p.logsd,offset,p.kind)
        end
    end
    spec=(;prior_sd=deepcopy(prior_sd),population=pop,predictors=(;predrec...),intercept=ip)
    decomposition===nothing || (spec=merge(spec,(;decomposition)))
    t=ExplanatoryTarget(base,raw,res,terms,ranges,offset,(;),spec)
    ExplanatoryTarget(base,raw,res,terms,ranges,offset,explanatory_allocation(t),spec)
end

function explanatory_allocation(t, conditional=t.base.allocation)
    # Mean-design rank excludes population residuals: conditional aliases with
    # their incidence columns are intrinsic to latent/population regression.
    n=length(t.person);xs=Vector{Vector{Float64}}();labels=String[]
    for term in t.terms
        x=term.owner===:response ? term.values : term.values[_owner_index(t,term.owner)]
        push!(xs,(term.owner in (:person,:response) ? 1. : -1.).*x);push!(labels,_term_name(term))
    end
    for b in t.facets
        (b.name in keys(t.specification.population) || b.scale==0.0) && continue
        # Same span as the finite-panel zero-sum effects, without their priors.
        m=length(b.levels)
        for j in 1:m-1
            push!(xs,Float64.((b.index.==j).-(b.index.==m)));push!(labels,"finite[$(b.name),$j]")
        end
    end
    X=isempty(xs) ? zeros(n,0) : hcat(xs...)
    scales=sqrt.(vec(sum(abs2,X;dims=1)));Xn=X./reshape(ifelse.(scales.>0,scales,1.),1,:)
    fixed_rank=isempty(Xn) ? 0 : rank(Xn;rtol=max(size(Xn)...)*eps(Float64));estimated=filter(b->b.hyper>0,t.residuals)
    # Frobenius Gram of group-incidence covariance kernels, computed from counts
    # instead of allocating N×N covariance matrices.
    gram=zeros(length(estimated),length(estimated))
    for (a,u) in enumerate(estimated),(b,v) in enumerate(estimated)
        cells=Dict{Tuple{Int,Int},Int}()
        for pair in zip(_owner_index(t,u.name),_owner_index(t,v.name))
            cells[pair]=get(cells,pair,0)+1
        end
        gram[a,b]=sum(x->Float64(x)^2,values(cells))
    end
    norm=sqrt.(diag(gram));normalized=isempty(norm) ? gram : gram./(norm*norm')
    variance_rank=rank(normalized)
    unreplicated=Symbol[]
    for b in estimated
        ids=_owner_index(t,b.name)
        length(unique(ids))==length(ids) && push!(unreplicated,b.name)
    end
    absent=copy(conditional.missing_levels)
    reasons=String[]
    fixed_rank<size(X,2) && push!(reasons,"Mean predictors/finite facet contrasts are aliased; remove duplicate intercepts or common effects.")
    variance_rank<length(estimated) && push!(reasons,"Estimated residual covariance components are aliased; coincident person/performance groupings cannot separate variances.")
    !isempty(unreplicated) && push!(reasons,"Estimated SD has no repeated observations within owner: $(unreplicated). This first-stage fitting domain requires replication.")
    !isempty(absent) && push!(reasons,"Declared levels have no observations: $(absent).")
    (;identified=isempty(reasons),rank=fixed_rank,columns=size(X,2),
      method=:population_mean_and_covariance_kernel_screen,mean_columns=labels,
      covariance_rank=variance_rank,covariance_components=[b.name for b in estimated],
      normalized_covariance_gram=normalized,unreplicated,missing_levels=absent,reasons,
      conditional_finite_design=conditional,
      interpretation="Necessary structural screen under zero-mean population assumptions; not proof of global identification, sufficient information, or model validity.")
end

_explanatory_logscale(t::ExplanatoryTarget) = any(b->b.scale_kind in (:half_normal,:half_student_t),t.residuals)
_residual_scale(b,q) = _scale_from_raw(b.scale_kind,b.logmean,b.logsd,q[b.hyper])
function logprior(t::ExplanatoryTarget,q)
    _check(t,q;finite=false)
    lp=_white_logprior(q)
    for b in t.residuals
        b.hyper==0 && continue
        lp+=_scale_logprior_delta(b.scale_kind,b.logmean,b.logsd,q[b.hyper],_residual_scale(b,q))
    end
    lp
end
function _prior_draw!(rng::AbstractRNG,t::ExplanatoryTarget)
    q=randn(rng,Float64,t.dimension)
    for b in t.residuals
        b.scale_kind===:half_normal && (q[b.hyper]=log(abs(randn(rng))*b.logsd))
        b.scale_kind===:half_student_t && (q[b.hyper]=log(abs(rand(rng,D.TDist(b.logmean)))*b.logsd))
    end
    q
end

function coordinates(t::ExplanatoryTarget,q::AbstractVector{<:Real})
    _check(t,q);Z=promote_type(Float64,eltype(q));effects=Dict{Symbol,Vector{Z}}();sd=Dict{Symbol,Z}();lv=zero(Z)
    for b in t.residuals
        s=b.hyper==0 ? Z(b.sd) : _residual_scale(b,q)
        isfinite(s) && (isempty(b.raw) ? s>=0 : s>0) || throw(ArgumentError("unrepresentable residual scale for $(b.name)"))
        # Finite-block b.sd is the orthonormal scale, already marginal-SD adjusted.
        m_lev=length(_owner_levels(t,b.name))
        effects[b.name]=isempty(b.raw) ? zeros(Z,m_lev) : s.*(b.kind===:iid_population ? q[b.raw] : N._zero_sum(view(q,b.raw)))
        sd[b.name]=isempty(b.raw) ? zero(Z) : (b.kind===:finite_sum_zero ? s/sqrt((length(b.raw)+1)/length(b.raw)) : s)
        isempty(b.raw) || (lv+=length(b.raw)*log(s))
        b.hyper==0 || (lv+=_scale_log_volume(b.scale_kind,b.logsd,s))
    end
    coefficients=[p.mean+p.sd*q[p.raw] for p in t.terms]
    for (p,c) in zip(t.terms,coefficients)
        p.owner===:response || (effects[p.owner].+=p.values.*c)
        lv+=log(p.sd)
    end
    tau=_step_coordinates(t,q)
    lv+=_step_volume(t)
    (;person=effects[:person],facets=Dict(b.name=>effects[b.name] for b in t.facets),
      steps=tau,coefficients,residual_sd=sd,log_volume=lv,
      measure=:iid_residuals_coefficients_positive_sd_and_finite_orthonormal_volume,
      basis=:helmert_ascending_for_finite_blocks)
end
response_shift(t::ExplanatoryTarget,v,n)=sum((v.coefficients[j]*p.values[n] for (j,p) in enumerate(t.terms) if p.owner===:response);init=zero(eltype(v.person)))
representable_scales(t::ExplanatoryTarget,q)=all(b->b.hyper==0 ||
    (isfinite(_residual_scale(b,q)) && _residual_scale(b,q)>0),t.residuals)

@inline function _expl_zero_sum_scaled!(out::AbstractVector{Float64}, v::AbstractVector{Float64}, scale::Float64)
    m = length(v)
    tail = 0.0
    @inbounds for j in m:-1:1
        val = (scale * v[j]) / sqrt(Float64(j * (j + 1)))
        out[j + 1] = tail - Float64(j) * val
        tail += val
    end
    @inbounds out[1] = tail
    return out
end

mutable struct _ExplanatoryGradScratch
    effects::Vector{Vector{Float64}}
    ge::Vector{Vector{Float64}}
    res_sd::Vector{Float64}
    coeffs::Vector{Float64}
    gc::Vector{Float64}
    tau::Matrix{Float64}
    gs::Matrix{Float64}
    ebuf::Vector{Float64}
    resp_shift::Vector{Float64}
end

function _get_explanatory_grad_scratch(n_res::Int, n_terms::Int, G::Int, H_max::Int, K::Int, N::Int)
    sc = get!(task_local_storage(), :_explanatory_grad_scratch) do
        _ExplanatoryGradScratch(
            Vector{Float64}[], Vector{Float64}[],
            Float64[], Float64[], Float64[],
            zeros(Float64, 0, 0), zeros(Float64, 0, 0),
            Float64[], Float64[],
        )
    end::_ExplanatoryGradScratch
    while length(sc.effects) < n_res
        push!(sc.effects, Float64[])
        push!(sc.ge, Float64[])
    end
    resize!(sc.res_sd, n_res)
    resize!(sc.coeffs, n_terms)
    resize!(sc.gc, n_terms)
    if size(sc.tau, 1) < G || size(sc.tau, 2) < H_max
        sc.tau = zeros(Float64, G, H_max)
        sc.gs = zeros(Float64, G, H_max)
    end
    resize!(sc.ebuf, K)
    resize!(sc.resp_shift, N)
    return sc
end

function _explanatory_unpack_f64!(sc::_ExplanatoryGradScratch, t::ExplanatoryTarget, q::AbstractVector{Float64})
    base = getfield(t, :base)
    residuals = getfield(t, :residuals)
    terms = getfield(t, :terms)
    step_ranges = getfield(t, :steps)
    facets_vec = base.facets
    n_res = length(residuals)

    @inbounds for bi in 1:n_res
        b = residuals[bi]
        s = b.hyper == 0 ? b.sd : _residual_scale(b,q)
        (isfinite(s) && (isempty(b.raw) ? s >= 0.0 : s > 0.0)) || return false
        m_lev = bi == 1 ? length(base.people) : length(facets_vec[bi - 1].levels)
        eff = sc.effects[bi]
        resize!(eff, m_lev)
        if isempty(b.raw)
            fill!(eff, 0.0)
            sc.res_sd[bi] = 0.0
        elseif b.kind === :iid_population
            r0 = first(b.raw) - 1
            for j in 1:m_lev
                eff[j] = s * q[r0 + j]
            end
            sc.res_sd[bi] = s
        else
            _expl_zero_sum_scaled!(eff, view(q, b.raw), s)
            nr = length(b.raw)
            sc.res_sd[bi] = s / sqrt(Float64(nr + 1) / Float64(nr))
        end
    end

    fill!(sc.resp_shift, 0.0)
    @inbounds for (j, p) in enumerate(terms)
        c = p.mean + p.sd * q[p.raw]
        sc.coeffs[j] = c
        if p.owner === :response
            vals = p.values
            for n in eachindex(vals)
                sc.resp_shift[n] += c * vals[n]
            end
        else
            bi = p.owner === :person ? 1 : (1 + findfirst(fb -> fb.name === p.owner, facets_vec)::Int)
            eff = sc.effects[bi]
            vals = p.values
            for k in eachindex(vals)
                eff[k] += c * vals[k]
            end
        end
    end

    G = length(step_ranges)
    @inbounds for g in 1:G
        hc = length(base.supports[g]) - 1
        if hc == 1
            sc.tau[g, 1] = 0.0
        elseif hc >= 2
            _expl_zero_sum_scaled!(view(sc.tau, g, 1:hc), view(q, step_ranges[g]), _step_scale(base, g))
        end
    end
    return true
end

function L.logdensity(t::ExplanatoryTarget, q::AbstractVector{Float64})
    base = getfield(t, :base)
    dim = getfield(t, :dimension)
    length(q) == dim || throw(DimensionMismatch("expected $dim white coordinates"))
    all(isfinite, q) || return -Inf
    residuals = getfield(t, :residuals)
    terms = getfield(t, :terms)
    step_ranges = getfield(t, :steps)
    N = length(base.person)
    K = length(base.categories)
    G = length(step_ranges)
    H_max = maximum(length, base.supports) - 1
    sc = _get_explanatory_grad_scratch(length(residuals), length(terms), G, H_max, K, N)
    _explanatory_unpack_f64!(sc, t, q) || return -Inf

    lp = logprior(t,q)
    person_eff = sc.effects[1]
    facets_vec = base.facets
    n_facets = length(facets_vec)
    tau = sc.tau
    ebuf = sc.ebuf
    resp_shift = sc.resp_shift

    @inbounds for n in 1:N
        eta = person_eff[base.person[n]] + resp_shift[n]
        for fi in 1:n_facets
            eta -= sc.effects[fi + 1][facets_vec[fi].index[n]]
        end
        g = base.group[n]
        sup = base.supports[g]
        M_g = length(sup)
        yk_loc = base.category[n] - first(sup) + 1
        ebuf[1] = 0.0
        mmax = 0.0
        for h in 1:(M_g - 1)
            val = ebuf[h] + eta - tau[g, h]
            ebuf[h + 1] = val
            val > mmax && (mmax = val)
        end
        y_val = ebuf[yk_loc]
        ssum = 0.0
        for lk in 1:M_g
            ssum += exp(ebuf[lk] - mmax)
        end
        lp += y_val - (mmax + log(ssum))
    end
    return isfinite(lp) ? lp : -Inf
end

function L.logdensity_and_gradient(t::ExplanatoryTarget, q::AbstractVector{Float64})
    base = getfield(t, :base)
    dim = getfield(t, :dimension)
    length(q) == dim || throw(DimensionMismatch("expected $dim white coordinates"))
    rejected() = (-Inf, fill(NaN, length(q)))
    all(isfinite, q) || return rejected()

    residuals = getfield(t, :residuals)
    terms = getfield(t, :terms)
    step_ranges = getfield(t, :steps)
    facets_vec = base.facets
    n_res = length(residuals)
    n_facets = length(facets_vec)
    N = length(base.person)
    K = length(base.categories)
    G = length(step_ranges)
    H_max = maximum(length, base.supports) - 1

    sc = _get_explanatory_grad_scratch(n_res, length(terms), G, H_max, K, N)
    _explanatory_unpack_f64!(sc, t, q) || return rejected()

    @inbounds for bi in 1:n_res
        ge_b = sc.ge[bi]
        resize!(ge_b, length(sc.effects[bi]))
        fill!(ge_b, 0.0)
    end
    gs = sc.gs
    @inbounds for g in 1:G
        for h in 1:(length(base.supports[g]) - 1)
            gs[g, h] = 0.0
        end
    end
    gc = fill!(sc.gc, 0.0)

    lp = logprior(t,q)
    person_eff = sc.effects[1]
    ge_person = sc.ge[1]
    tau = sc.tau
    ebuf = sc.ebuf
    resp_shift = sc.resp_shift

    @inbounds for n in 1:N
        p = base.person[n]
        eta = person_eff[p] + resp_shift[n]
        for fi in 1:n_facets
            eta -= sc.effects[fi + 1][facets_vec[fi].index[n]]
        end
        g = base.group[n]
        sup = base.supports[g]
        M_g = length(sup)
        yk_loc = base.category[n] - first(sup) + 1
        ebuf[1] = 0.0
        mmax = 0.0
        for h in 1:(M_g - 1)
            val = ebuf[h] + eta - tau[g, h]
            ebuf[h + 1] = val
            val > mmax && (mmax = val)
        end
        y_val = ebuf[yk_loc]
        ssum = 0.0
        for lk in 1:M_g
            ssum += exp(ebuf[lk] - mmax)
        end
        z = mmax + log(ssum)
        lp += y_val - z
        exp_loc = 0.0
        for lk in 1:M_g
            pk = exp(ebuf[lk] - z)
            ebuf[lk] = pk
            exp_loc += Float64(lk - 1) * pk
        end
        de = Float64(yk_loc - 1) - exp_loc
        ge_person[p] += de
        for fi in 1:n_facets
            sc.ge[fi + 1][facets_vec[fi].index[n]] -= de
        end
        resp_shift[n] = de
        tail = 0.0
        for h in (M_g - 1):-1:1
            tail += ebuf[h + 1]
            gs[g, h] += tail - (yk_loc > h ? 1.0 : 0.0)
        end
    end
    isfinite(lp) || return rejected()

    grad = Vector{Float64}(undef, dim)
    @inbounds for j in 1:dim
        grad[j] = -q[j]
    end
    @inbounds for bi in 1:n_res
        b = residuals[bi]
        isempty(b.raw) && continue
        g_vec = sc.ge[bi]
        s = b.hyper == 0 ? b.sd : sc.res_sd[bi]
        if b.kind === :iid_population
            r0 = first(b.raw) - 1
            dot_gq = 0.0
            for k in eachindex(g_vec)
                gk = g_vec[k]
                grad[r0 + k] += s * gk
                dot_gq += gk * q[r0 + k]
            end
            b.hyper == 0 || (grad[b.hyper] = _scale_dlogprior_du(b.scale_kind,b.logmean,b.logsd,q[b.hyper],s) +
                _scale_dlogsig_du(b.scale_kind,b.logsd) * s * dot_gq)
        else
            S._helmert_pullback!(grad, b.raw, g_vec, s)
        end
    end
    @inbounds for (j, p) in enumerate(terms)
        if p.owner === :response
            gc[j] = dot(resp_shift, p.values)
        else
            bi = p.owner === :person ? 1 : (1 + findfirst(fb -> fb.name === p.owner, facets_vec)::Int)
            gc[j] = dot(sc.ge[bi], p.values)
        end
        grad[p.raw] += p.sd * gc[j]
    end
    @inbounds for g in 1:G
        r = step_ranges[g]
        isempty(r) && continue
        S._helmert_pullback!(grad, r, view(gs, g, 1:(length(base.supports[g]) - 1)), _step_scale(base, g))
    end
    return all(isfinite, grad) ? (lp, grad) : rejected()
end

function L.logdensity_and_gradient(t::ExplanatoryTarget,q::AbstractVector{<:Real})
    _check(t,q;finite=false);Z=promote_type(Float64,eltype(q));rejected()=(-Z(Inf),fill(Z(NaN),length(q)))
    all(isfinite,q) || return rejected()
    # Overflow/underflow is outside representable coordinates, not a sampler clamp.
    representable_scales(t,q) || return rejected()
    v=coordinates(t,q);ge=Dict(b.name=>zeros(Z,length(_owner_levels(t,b.name))) for b in t.residuals)
    gs=zeros(Z,size(v.steps));gc=zeros(Z,length(t.terms));K=length(t.categories);a=zeros(Z,K);lp=logprior(t,q)
    for n in eachindex(t.person)
        c=_weights!(a,t,v,n);y=t.category[n];g=t.group[n];lp+=a[y]-c
        a.=exp.(a.-c);de=y-1-sum((k-1)*a[k] for k in 1:K)
        ge[:person][t.person[n]]+=de
        for b in t.facets;ge[b.name][b.index[n]]-=de;end
        for (j,p) in enumerate(t.terms);p.owner===:response && (gc[j]+=de*p.values[n]);end
        _step_score!(gs,a,t,g,y)
    end
    isfinite(lp) || return rejected()
    grad=-Z.(q)
    for b in t.residuals
        isempty(b.raw) && continue
        g=ge[b.name];s=b.hyper==0 ? b.sd : v.residual_sd[b.name]
        if b.kind===:iid_population
            grad[b.raw].+=s.*g
            b.hyper==0 || (grad[b.hyper]=_scale_dlogprior_du(b.scale_kind,b.logmean,b.logsd,q[b.hyper],s)+
                _scale_dlogsig_du(b.scale_kind,b.logsd)*s*dot(g,view(q,b.raw)))
        else
            S._helmert_pullback!(grad,b.raw,g,s)
        end
    end
    for (j,p) in enumerate(t.terms)
        p.owner===:response || (gc[j]=dot(ge[p.owner],p.values))
        grad[p.raw]+=p.sd*gc[j]
    end
    for (g,r) in enumerate(t.steps)
        S._helmert_pullback!(grad,r,view(gs,g,1:_step_count(t,g)),_step_scale(t,g))
    end
    all(isfinite,grad) ? (lp,grad) : rejected()
end

function names(t::ExplanatoryTarget,scale)
    scale in (:raw,:model) || throw(ArgumentError("scale must be :raw or :model"))
    out=String[]
    for b in t.residuals
        append!(out,scale===:raw ? ["$(b.name).white[$j]" for j in eachindex(b.raw)] :
            ["$(b.name)[$(repr(x))]" for x in _owner_levels(t,b.name)])
    end
    for (g,r) in enumerate(t.steps)
        append!(out,["steps[$(repr(t.group_levels[g])),$j]" for j in 1:(scale===:raw ? length(r) : _step_count(t,g))])
    end
    append!(out,[_term_name(p)*(scale===:raw ? ".white" : "") for p in t.terms])
    append!(out,scale===:raw ? ["log_sd[$(b.name)]"*(b.scale_kind===:lognormal ? ".white" : "") for b in t.residuals if b.hyper>0] :
        ["residual_sd[$(b.name)]" for b in t.residuals])
    out
end
function record(t::ExplanatoryTarget)
    (;schema=_explanatory_logscale(t) ? "bayesianmgmfrm.explanatory_facet_design.v4" : (_expanded_terms(t) || _owned_support(t)) ? "bayesianmgmfrm.explanatory_facet_design.v3" : hasproperty(t.specification,:decomposition) ? "bayesianmgmfrm.explanatory_facet_design.v2" : "bayesianmgmfrm.explanatory_facet_design.v1",table=deepcopy(t.table),columns=deepcopy(t.columns),
      category_levels=_category_declaration(t),steps=t.owner,levels=record(t.base).levels,
      specification=deepcopy(t.specification),coordinates=_explanatory_logscale(t) ? :white_normal_and_log_scale : :white_standard_normal,
      population_constraint=:distributional_zero_mean_not_sample_sum_zero,basis=:helmert_ascending)
end
function restore_explanatory(r)
    r.coordinates in (:white_standard_normal,:white_normal_and_log_scale) && r.population_constraint===:distributional_zero_mean_not_sample_sum_zero &&
        r.basis===:helmert_ascending || throw(ArgumentError("unsupported explanatory coordinate/prior record"))
    s=r.specification
    pop=(;(k=>(p.kind===:fixed ? p.sd : p.kind===:lognormal ? D.LogNormal(p.logmean,p.logsd) :
        p.kind===:half_normal ? D.truncated(D.Normal(0,p.logsd),0,Inf) :
        p.kind===:half_student_t ? D.truncated(D.LocationScale(0,p.logsd,D.TDist(p.logmean)),0,Inf) :
        throw(ArgumentError("unsupported population SD prior"))) for (k,p) in pairs(s.population))...)
    preds=(;(k=>(;(c=>(hasproperty(p,:by) ? (;by=p.by,prior=D.Normal(p.mean,p.sd)) : D.Normal(p.mean,p.sd)) for (c,p) in pairs(cols))...) for (k,cols) in pairs(s.predictors))...)
    hasdecomp=hasproperty(s,:decomposition)
    advanced=(r.category_levels isa AbstractDict) || any(hasproperty(p,:by) for cols in values(s.predictors) for p in values(cols))
    logscale=any(p->p.kind in (:half_normal,:half_student_t),values(s.population))
    r.coordinates== (logscale ? :white_normal_and_log_scale : :white_standard_normal) || throw(ArgumentError("population prior/coordinate mismatch"))
    expected=logscale ? "bayesianmgmfrm.explanatory_facet_design.v4" : advanced ? "bayesianmgmfrm.explanatory_facet_design.v3" : hasdecomp ? "bayesianmgmfrm.explanatory_facet_design.v2" : "bayesianmgmfrm.explanatory_facet_design.v1"
    r.schema==expected || throw(ArgumentError("predictor/support schema mismatch"))
    rules=hasdecomp ? (;(d.source=>(;between=d.between,within=d.within) for d in s.decomposition.rules)...) : nothing
    t=explanatory_model(r.table;r.columns...,category_levels=r.category_levels,steps=r.steps,levels=r.levels,
        prior_sd=s.prior_sd,population=pop,predictors=preds,decompose=rules,
        intercept=s.intercept===nothing ? nothing : D.Normal(s.intercept.mean,s.intercept.sd))
    hasdecomp && !isequal(t.specification.decomposition,s.decomposition) && throw(ArgumentError("stored decomposition disagrees with training ownership/values"))
    t
end
function design(t::ExplanatoryTarget)
    base=design(t.base)
    facets=[(;name=b.name,column=b.column,levels=deepcopy(b.levels),
        observed_levels=length(unique(b.index)),residual_kind=r.kind,estimated_sd=r.hyper>0,
        free_residual_parameters=length(r.raw)) for (b,r) in zip(t.facets,t.residuals[2:end])]
    merge(base,(;facets,n_parameters=t.dimension,allocation=deepcopy(t.allocation),
        grouping=merge(t.groups,(;performance_effect=[b.name for b in t.facets if b.column===t.columns.performance])),
        predictors=[(;owner=p.owner,column=p.column,by=p.by,level=deepcopy(p.level),prior=(family=:normal,mean=p.mean,sd=p.sd),
            unique_owner_values=length(p.values),sign=p.owner in (:person,:response) ? :higher_rating : :greater_severity)
            for p in t.terms],population=deepcopy(t.specification.population),
        decomposition=hasproperty(t.specification,:decomposition) ? deepcopy(t.specification.decomposition) : nothing,
        warnings=["explanatory PCM: structural screening is not global identification or scientific acceptance.",
            "Population residuals are iid zero-mean Gaussians, not sample-centered finite-panel effects. Exchangeability conditional on predictors is an assumption.",
            "Residual rater SD measures between-rater severity variation, not within-rater consistency or the Patz HRM.",
            "Coefficients are associations on unit adjacent logits; they do not establish causal effects.",
            "Decomposed means weight unique observed performances equally. They are not latent habitual attributes; deviations are not detrended, and need not sum to zero across rating rows.",
            "With one performance per person, the person effect combines stable person and unique performance; those variances are not separated.",
            "Shared-performance/local dependence beyond declared effects is not modeled. More ratings do not create new independent performances.",
            "Few owners, sparse overlap and weak category information can leave SDs and coefficients prior-sensitive even when the structural screen passes.",base.response_patterns.warnings...] ))
end
function contract(t::ExplanatoryTarget)
    merge(contract(t.base),(;schema="bayesianmgmfrm.explanatory_facet_contract.v1",
        family=t.owner===:global ? :scalar_explanatory_rsm : :scalar_explanatory_pcm,
        constraints=:population_distributional_zero_mean_finite_facets_and_steps_sum_zero,
        prior_scale=:explicit_coefficient_units_and_residual_sd,
        prediction=:posterior_known_owners_fixed_predictors_no_new_population_entities,
        mean_structure=:person_plus_response_minus_named_facets,
        decomposition=hasproperty(t.specification,:decomposition) ? deepcopy(t.specification.decomposition) : nothing,
        supported_priors=(coefficient=:normal,residual_sd=(:nonnegative_fixed,:lognormal,:half_normal,:half_student_t)),
        record=record(t)))
end

function stan_data(t::ExplanatoryTarget)
    # Independent dense residual maps and fixed mean design for a reference target.
    n=length(t.person);R=sum(length(b.raw) for b in t.residuals);T=length(t.terms)
    A=zeros(n,R);rsd=Float64[];hidx=Int[];Hpars=Tuple{Float64,Float64}[];hkinds=Int[];col=0
    for b in t.residuals
        ids=_owner_index(t,b.name);m=length(_owner_levels(t,b.name));sgn=b.name===:person ? 1. : -1.
        if b.hyper>0
            push!(Hpars,(b.logmean,b.logsd));push!(hkinds,b.scale_kind===:lognormal ? 1 : b.scale_kind===:half_normal ? 2 : 3)
        end
        for j in eachindex(b.raw)
            col+=1;push!(rsd,b.sd);push!(hidx,b.hyper>0 ? length(Hpars) : 0)
            for i in 1:n
                A[i,col]=sgn*(b.kind===:iid_population ? Float64(ids[i]==j) :
                    ids[i]<=j ? 1/sqrt(j*(j+1)) : ids[i]==j+1 ? -j/sqrt(j*(j+1)) : 0.)
            end
        end
    end
    X=zeros(n,T)
    for (j,p) in enumerate(t.terms)
        X[:,j]=(p.owner in (:person,:response) ? 1. : -1.).*(p.owner===:response ? p.values : p.values[_owner_index(t,p.owner)])
    end
    if _owned_support(t)
        Hs=[_step_count(t,g) for g in eachindex(t.steps)]
        starts=cumsum([1;Hs[1:end-1]]);Astep=zeros(sum(Hs),sum(length,t.steps));col=0
        for (g,r) in enumerate(t.steps)
            for j in 1:length(r),i in 1:Hs[g]
                Astep[starts[g]+i-1,col+j]=(i<=j ? 1. : i==j+1 ? -j : 0.)*_step_scale(t,g)/sqrt(j*(j+1))
            end
            col+=length(r)
        end
        return Dict("N"=>n,"K"=>length(t.categories),"G"=>length(t.steps),"R"=>R,"T"=>T,"V"=>length(Hpars),
            "D"=>t.dimension,"y"=>copy(t.category),"group"=>copy(t.group),"A"=>A,"X"=>X,
            "residual_scale"=>rsd,"hyper_index"=>hidx,"scale_kind"=>hkinds,"logmean"=>first.(Hpars),"logsd"=>last.(Hpars),
            "coefficient_mean"=>[p.mean for p in t.terms],"coefficient_sd"=>[p.sd for p in t.terms],
            "H"=>sum(Hs),"Qstep"=>sum(length,t.steps),"Astep"=>Astep,"step_begin"=>starts,
            "category_begin"=>first.(t.supports),"support_size"=>length.(t.supports))
    end
    H=length(t.categories)-1;Astep=[(i<=j ? 1. : i==j+1 ? -j : 0.)*t.step_scale/sqrt(j*(j+1)) for i in 1:H,j in 1:H-1]
    Dict("N"=>n,"K"=>H+1,"G"=>length(t.steps),"R"=>R,"T"=>T,"V"=>length(Hpars),
        "D"=>t.dimension,"y"=>copy(t.category),"group"=>copy(t.group),"A"=>A,"X"=>X,
        "residual_scale"=>rsd,"hyper_index"=>hidx,"scale_kind"=>hkinds,"logmean"=>first.(Hpars),"logsd"=>last.(Hpars),
        "coefficient_mean"=>[p.mean for p in t.terms],"coefficient_sd"=>[p.sd for p in t.terms],"Hstep"=>Astep)
end
