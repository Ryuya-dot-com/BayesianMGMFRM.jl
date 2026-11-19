# Included in AdditiveFacets. Identity/effect design contains no ordinal support.
import SpecialFunctions as SF
struct LocationDesign
    table::Dict{Symbol,Vector}
    columns::NamedTuple
    person::Vector{Int}
    people::Vector{Any}
    facets::Vector{Block}
    residuals::Vector{ResidualBlock}
    terms::Vector{MeanTerm}
    specification::NamedTuple
    groups::NamedTuple
    dimension::Int
end

struct CompiledLocOwnerTerm
    owner_slot::Int
    mean::Float64
    sd::Float64
    raw::Int
    values::Vector{Float64}
    sign::Float64
    ws_slot::Int
end

struct CompiledRowTerm
    mean::Float64
    sd::Float64
    raw::Int
    values::Vector{Float64}
    ws_slot::Int
end

struct CompiledResidual
    index::Vector{Int}
    raw::UnitRange{Int}
    sd::Float64
    logmean::Float64
    logsd::Float64
    hyper::Int
    sign::Float64
    ws_slot::Int
end

struct CompiledSlope
    index::Vector{Int}
    xs::Vector{Vector{Float64}}
    sign::Float64
    raws::Vector{UnitRange{Int}}
    intercept_raw::UnitRange{Int}
    hyps::Vector{Int}
    corr_raw::UnitRange{Int}
    sds_fixed::Vector{Float64}
    logmeans::Vector{Float64}
    logsds::Vector{Float64}
    D_dim::Int
    alphas::Vector{Float64}
    logbetas::Vector{Float64}
    ws_sds::UnitRange{Int}
    ws_u::UnitRange{Int}
    ws_c::UnitRange{Int}
    ws_r::UnitRange{Int}
    ws_L_base::Int
    ws_Lbar_base::Int
end

struct BoundedKernel
    n_workspace::Int
    loc_dimension::Int
    has_distributional::Bool
    width::Float64
    log_width::Float64
    prec_logmean::Float64
    prec_logsd::Float64
    ep_mean::Float64
    ep_sd::Float64
    up_mean::Float64
    up_sd::Float64
    loc_residuals::Vector{CompiledResidual}
    loc_owner_terms::Vector{CompiledLocOwnerTerm}
    loc_row_terms::Vector{CompiledRowTerm}
    slopes::Vector{CompiledSlope}
    dist_terms_1::Vector{CompiledRowTerm}
    dist_terms_2::Vector{CompiledRowTerm}
    dist_terms_3::Vector{CompiledRowTerm}
    dist_residuals_1::Vector{CompiledResidual}
    dist_residuals_2::Vector{CompiledResidual}
    dist_residuals_3::Vector{CompiledResidual}
end

struct BoundedTarget <: AbstractTarget
    location::LocationDesign
    observation::NamedTuple
    observation_prior::NamedTuple
    y::Vector{Float64}
    dimension::Int
    allocation::NamedTuple
    kernel::BoundedKernel
end
BoundedTarget(loc::LocationDesign,obs::NamedTuple,obsprior::NamedTuple,y::Vector{Float64},dimension::Int,alloc::NamedTuple)=
    BoundedTarget(loc,obs,obsprior,y,dimension,alloc,compile_bounded_kernel(loc,obs,obsprior))
Base.getproperty(t::BoundedTarget,k::Symbol)=k in fieldnames(BoundedTarget) ? getfield(t,k) : getproperty(getfield(t,:location),k)
Base.propertynames(::BoundedTarget)=unique((filter(!=(:kernel),fieldnames(BoundedTarget))...,fieldnames(LocationDesign)...))
const BOUNDED_SCHEMA="bayesianmgmfrm.bounded_facet_design.v1"

@inline _L_slot(base::Int,D_dim::Int,i::Int,j::Int)=base+(j-1)*D_dim+i

function compile_bounded_kernel(loc::LocationDesign,obs::NamedTuple,obsprior::NamedTuple)
    n=length(loc.person);width=Float64(obs.bounds[2]-obs.bounds[1]);log_width=log(width);ws=0
    owner_slots=Dict{Symbol,Int}();loc_res=CompiledResidual[]
    for (i,b) in enumerate(loc.residuals)
        ws+=1;owner_slots[b.name]=i
        push!(loc_res,CompiledResidual(Int.(_owner_index(loc,b.name)),b.raw,b.sd,b.logmean,b.logsd,b.hyper,b.name===:person ? 1.0 : -1.0,ws))
    end
    owner_terms=CompiledLocOwnerTerm[];row_terms=CompiledRowTerm[]
    for p in loc.terms
        ws+=1
        if p.owner===:response
            push!(row_terms,CompiledRowTerm(p.mean,p.sd,p.raw,Float64.(p.values),ws))
        else
            push!(owner_terms,CompiledLocOwnerTerm(owner_slots[p.owner],p.mean,p.sd,p.raw,Float64.(p.values),p.owner===:person ? 1.0 : -1.0,ws))
        end
    end
    slopes=CompiledSlope[]
    for sb in (hasproperty(loc.specification,:random_slopes) ? loc.specification.random_slopes : ())
        cols=_sb_cols(sb);raws=collect(_sb_raws(sb));hyps=Int[h for h in _sb_hyps(sb)]
        scales=_sb_scales(sb);cr=_sb_corr_range(sb);K=length(cols);D_dim=K+1;mc=length(cr)
        sds_fixed=Float64[hyps[k]==0 ? Float64(scales[k].sd) : 1.0 for k in 1:K]
        logmeans=Float64[hyps[k]==0 ? 0.0 : Float64(scales[k].logmean) for k in 1:K]
        logsds=Float64[hyps[k]==0 ? 1.0 : Float64(scales[k].logsd) for k in 1:K]
        alphas=Float64[];logbetas=Float64[]
        if mc>0
            eta_val=Float64(sb.correlation.eta)
            for i in 2:D_dim,j in 1:(i-1)
                al=eta_val+(D_dim-1-j)/2
                push!(alphas,al);push!(logbetas,SF.logbeta(0.5,al))
            end
        end
        ws_sds=(ws+1):(ws+K);ws+=K
        ws_u=mc>0 ? ((ws+1):(ws+mc)) : (1:0);ws+=mc
        ws_c=mc>0 ? ((ws+1):(ws+mc)) : (1:0);ws+=mc
        ws_r=mc>0 ? ((ws+1):(ws+mc)) : (1:0);ws+=mc
        ws_L_base=ws;ws+=D_dim*D_dim
        ws_Lbar_base=ws;ws+=D_dim*D_dim
        xs=Vector{Float64}[Float64.(loc.table[c]) for c in cols]
        push!(slopes,CompiledSlope(Int.(_owner_index(loc,sb.owner)),xs,sb.owner===:person ? 1.0 : -1.0,
            raws,sb.intercept_raw,hyps,cr,sds_fixed,logmeans,logsds,D_dim,alphas,logbetas,
            ws_sds,ws_u,ws_c,ws_r,ws_L_base,ws_Lbar_base))
    end
    dt1=CompiledRowTerm[];dt2=CompiledRowTerm[];dt3=CompiledRowTerm[]
    dr1=CompiledResidual[];dr2=CompiledResidual[];dr3=CompiledResidual[]
    dbs=hasproperty(obsprior,:regression) ? obsprior.regression : ()
    for b in dbs
        dt=b.index==1 ? dt1 : b.index==2 ? dt2 : dt3
        dr=b.index==1 ? dr1 : b.index==2 ? dr2 : dr3
        for p in b.terms
            ws+=1;col=Float64.(loc.table[p.column])
            vals=if p.by===nothing
                col
            else
                by_lev=_owner_levels(loc,p.by);by_ix=_owner_index(loc,p.by)
                Float64[col[i]*(by_lev[by_ix[i]]==p.level) for i in 1:n]
            end
            push!(dt,CompiledRowTerm(Float64(p.mean),Float64(p.sd),Int(p.raw),vals,ws))
        end
        for r in b.residuals
            ws+=1
            push!(dr,CompiledResidual(Int.(_owner_index(loc,r.name)),r.raw,Float64(r.sd),Float64(r.logmean),Float64(r.logsd),Int(r.hyper),1.0,ws))
        end
    end
    BoundedKernel(ws,loc.dimension,!isempty(dbs),width,log_width,
        Float64(obsprior.precision.logmean),Float64(obsprior.precision.logsd),
        Float64(obsprior.endpoint_logit.mean),Float64(obsprior.endpoint_logit.sd),
        Float64(obsprior.upper_logit.mean),Float64(obsprior.upper_logit.sd),
        loc_res,owner_terms,row_terms,slopes,dt1,dt2,dt3,dr1,dr2,dr3)
end

function bounded_model(table;person::Symbol,score::Symbol,facets::NamedTuple,
        observation::NamedTuple,observation_prior::NamedTuple,population::NamedTuple,
        predictors::NamedTuple=(;),intercept,levels=nothing,performance=nothing,assessment=nothing,
        decompose=nothing)
    _keys(observation,(:family,:bounds),:observation)
    observation.family===:zero_one_inflated_beta || throw(ArgumentError("bounded observation family must be :zero_one_inflated_beta"))
    bounds=observation.bounds
    bounds isa Tuple && length(bounds)==2 && all(x->x isa Real && !(x isa Bool) && isfinite(x),bounds) || throw(ArgumentError("bounds must be two finite real numbers"))
    lo,hi=Float64.(bounds);isfinite(hi-lo) && hi>lo || throw(ArgumentError("bounds must have finite positive width"))
    _keys(observation_prior,(:precision,:endpoint_logit,:upper_logit),:observation_prior)
    pp=_population_parameters(observation_intercept(observation_prior.precision),:precision)
    pp.kind===:lognormal || throw(ArgumentError("precision requires an explicit LogNormal prior"))
    zp=_normal_parameters(observation_intercept(observation_prior.endpoint_logit),:endpoint_logit)
    hp=_normal_parameters(observation_intercept(observation_prior.upper_logit),:upper_logit)
    obsprior=(;precision=pp,endpoint_logit=zp,upper_logit=hp)
    loc,alloc=location_model(table;person,score,facets,population,predictors,intercept,levels,performance,assessment,decompose,allow_slopes=true)
    raw=loc.table;n=length(raw[score])
    all(x->x isa Real && !(x isa Bool) && isfinite(x) && lo<=x<=hi,raw[score]) || throw(ArgumentError("scores must be finite, nonmissing and within bounds"))
    raw[score]=Float64.(raw[score]);y=(raw[score].-lo)./(hi-lo)
    all(i->(raw[score][i]==lo)==(y[i]==0) && (raw[score][i]==hi)==(y[i]==1),1:n) || throw(ArgumentError("score normalization loses endpoint identity"))
    obsprior,dimension=compile_distributional(table,loc,observation_prior,obsprior)
    t=BoundedTarget(loc,(;family=:zero_one_inflated_beta,bounds=(lo,hi)),obsprior,y,dimension,alloc)
    BoundedTarget(loc,t.observation,obsprior,y,dimension,distribution_allocation(t,alloc),t.kernel)
end

_softplus(x)=x>zero(x) ? x+log1p(exp(-x)) : log1p(exp(x))
_sigmoid(x)=exp(-_softplus(-x))
function coordinates(t::BoundedTarget,q::AbstractVector{<:Real})
    common=location_coordinates(t,q);lv=common.log_volume
    pr=t.observation_prior;off=t.location.dimension
    precision=exp(pr.precision.logmean+pr.precision.logsd*q[off+1])
    endpoint_logit=pr.endpoint_logit.mean+pr.endpoint_logit.sd*q[off+2]
    upper_logit=pr.upper_logit.mean+pr.upper_logit.sd*q[off+3]
    lv+=log(pr.precision.logsd)+log(precision)+log(pr.endpoint_logit.sd)+log(pr.upper_logit.sd)
    base=(;common...,precision,endpoint_logit,upper_logit,endpoint_probability=_sigmoid(endpoint_logit),upper_probability=_sigmoid(upper_logit),
      log_volume=lv,measure=isempty(slope_blocks(t)) ? :residuals_coefficients_sd_precision_and_endpoint_logits : :residuals_coefficients_sd_precision_endpoint_logits_and_correlation)
    isempty(distribution_blocks(t)) && return base
    blocks=distribution_coordinates(t,q)
    merge(base,(;distributional=blocks,log_volume=lv+sum(b.log_volume for b in blocks)))
end
function bounded_eta(t,v,n)
    e=v.person[t.person[n]]
    for b in t.facets;e-=v.facets[b.name][b.index[n]];end
    for (j,p) in enumerate(t.terms);p.owner===:response && (e+=v.coefficients[j]*p.values[n]);end
    isempty(slope_blocks(t)) ? e : e+slope_eta(t,v,n)
end
# Beta shapes are computed separately to avoid 1-logistic(eta) cancellation.
function bounded_cell(y,eta,v,width)
    z,h=v.endpoint_logit,v.upper_logit
    if y==0 || y==1
        lp=-_softplus(-z)-(y==1 ? _softplus(-h) : _softplus(h))
        return lp,zero(eta),zero(eta),1-_sigmoid(z),y-_sigmoid(h)
    end
    u=_sigmoid(eta);w=_sigmoid(-eta);a=v.precision*u;b=v.precision*w
    isfinite(a+b) && a>0 && b>0 || return (-Inf,NaN,NaN,NaN,NaN)
    ly=log(y);lc=log1p(-y)
    lp=-_softplus(z)+(a-1)*ly+(b-1)*lc-SF.logbeta(a,b)-log(width)
    da=SF.digamma(a);db=SF.digamma(b)
    de=v.precision*u*w*(ly-lc-da+db)
    dp=v.precision*(SF.digamma(a+b)-u*da-w*db+u*ly+w*lc)
    lp,de,dp,-_sigmoid(z),zero(eta)
end
_bounded_reject(::Type{Z},d::Int) where {Z}=(-Z(Inf),fill(Z(NaN),d))

@inline function _bounded_cell_scalar(y::Float64,eta::Z,prec::Z,z::Z,h::Z,log_width::Float64) where {Z}
    if y==0.0 || y==1.0
        lp=-_softplus(-z)-(y==1.0 ? _softplus(-h) : _softplus(h))
        return lp,zero(Z),zero(Z),one(Z)-_sigmoid(z),Z(y)-_sigmoid(h)
    end
    u=_sigmoid(eta);w=_sigmoid(-eta);a=prec*u;b=prec*w
    isfinite(a+b) && a>zero(Z) && b>zero(Z) || return (Z(-Inf),Z(NaN),Z(NaN),Z(NaN),Z(NaN))
    ly=log(y);lc=log1p(-y)
    lp=-_softplus(z)+(a-one(Z))*ly+(b-one(Z))*lc-SF.logbeta(a,b)-log_width
    da=SF.digamma(a);db=SF.digamma(b)
    de=prec*u*w*(ly-lc-da+db)
    dp=prec*(SF.digamma(a+b)-u*da-w*db+u*ly+w*lc)
    return lp,de,dp,-_sigmoid(z),zero(Z)
end

function _bounded_fill_workspace!(ws::Vector{Z},k::BoundedKernel,q::AbstractVector{<:Real}) where {Z}
    @inbounds for r in k.loc_residuals
        s=r.hyper==0 ? Z(r.sd) : exp(r.logmean+r.logsd*q[r.hyper])
        isfinite(s) && s>zero(Z) || return false
        ws[r.ws_slot]=s
    end
    @inbounds for p in k.loc_owner_terms;ws[p.ws_slot]=p.mean+p.sd*q[p.raw];end
    @inbounds for p in k.loc_row_terms;ws[p.ws_slot]=p.mean+p.sd*q[p.raw];end
    @inbounds for sb in k.slopes
        D_s=sb.D_dim;K_s=D_s-1;L_base=sb.ws_L_base
        for k_sl in 1:K_s
            h_idx=sb.hyps[k_sl]
            s=h_idx==0 ? Z(sb.sds_fixed[k_sl]) : exp(sb.logmeans[k_sl]+sb.logsds[k_sl]*q[h_idx])
            isfinite(s) && s>zero(Z) || return false
            ws[sb.ws_sds[k_sl]]=s
        end
        for idx in 1:(D_s*D_s);ws[L_base+idx]=zero(Z);end
        for i in 1:D_s;ws[_L_slot(L_base,D_s,i,i)]=one(Z);end
        if !isempty(sb.corr_raw)
            c_idx=0
            for i in 2:D_s
                log_rem=zero(Z)
                for j in 1:(i-1)
                    c_idx+=1;a=Z(q[sb.corr_raw[c_idx]])
                    u=tanh(a);ls=_logsech2(a);c=exp(ls/2);r_prev=exp(log_rem/2)
                    isfinite(c) && c>zero(Z) || return false
                    ws[sb.ws_u[c_idx]]=u;ws[sb.ws_c[c_idx]]=c;ws[sb.ws_r[c_idx]]=r_prev
                    ws[_L_slot(L_base,D_s,i,j)]=u*r_prev
                    log_rem+=ls
                end
                diag_ii=exp(log_rem/2)
                isfinite(diag_ii) && diag_ii>zero(Z) || return false
                ws[_L_slot(L_base,D_s,i,i)]=diag_ii
            end
        end
    end
    if k.has_distributional
        @inbounds for p in k.dist_terms_1;ws[p.ws_slot]=p.mean+p.sd*q[p.raw];end
        @inbounds for p in k.dist_terms_2;ws[p.ws_slot]=p.mean+p.sd*q[p.raw];end
        @inbounds for p in k.dist_terms_3;ws[p.ws_slot]=p.mean+p.sd*q[p.raw];end
        @inbounds for dr in (k.dist_residuals_1,k.dist_residuals_2,k.dist_residuals_3),r in dr
            s=r.hyper==0 ? Z(r.sd) : exp(r.logmean+r.logsd*q[r.hyper])
            isfinite(s) && s>zero(Z) || return false
            ws[r.ws_slot]=s
        end
    end
    return true
end

function _bounded_logprior(k::BoundedKernel,q::AbstractVector{<:Real})
    half_log2pi=log(2pi)/2
    lp=-length(q)*half_log2pi-sum(abs2,q)/2
    @inbounds for sb in k.slopes
        isempty(sb.corr_raw) && continue
        for c_idx in eachindex(sb.corr_raw)
            a=q[sb.corr_raw[c_idx]]
            lp+=a^2/2+half_log2pi+sb.alphas[c_idx]*_logsech2(a)-sb.logbetas[c_idx]
        end
    end
    return lp
end

function L.logdensity_and_gradient(t::BoundedTarget,q::AbstractVector{<:Real})
    _check(t,q;finite=false);Z=promote_type(Float64,eltype(q));d=length(q)
    all(isfinite,q) || return _bounded_reject(Z,d)
    k=getfield(t,:kernel);y=getfield(t,:y);off=k.loc_dimension
    prec0=exp(k.prec_logmean+k.prec_logsd*q[off+1])
    isfinite(prec0) && prec0>zero(Z) || return _bounded_reject(Z,d)
    ep0=Z(k.ep_mean+k.ep_sd*q[off+2])
    up0=Z(k.up_mean+k.up_sd*q[off+3])
    log_prec0=k.has_distributional ? log(prec0) : zero(Z)
    ws=Vector{Z}(undef,k.n_workspace)
    _bounded_fill_workspace!(ws,k,q) || return _bounded_reject(Z,d)
    grad=zeros(Z,d)
    lp=Z(_bounded_logprior(k,q))
    go1=zero(Z);go2=zero(Z);go3=zero(Z)
    @inbounds for n in eachindex(y)
        eta=zero(Z)
        for r in k.loc_residuals
            idx=r.index[n];eta+=r.sign*(ws[r.ws_slot]*q[r.raw[idx]])
        end
        for p in k.loc_owner_terms
            idx=k.loc_residuals[p.owner_slot].index[n];eta+=p.sign*(ws[p.ws_slot]*p.values[idx])
        end
        for p in k.loc_row_terms
            eta+=ws[p.ws_slot]*p.values[n]
        end
        for sb in k.slopes
            p_idx=sb.index[n];D_s=sb.D_dim;L_base=sb.ws_L_base
            z0_p=q[sb.intercept_raw[p_idx]]
            for k_sl in 1:(D_s-1)
                i_sl=k_sl+1
                wi=ws[_L_slot(L_base,D_s,i_sl,1)]*z0_p
                for j_sl in 2:i_sl
                    wi+=ws[_L_slot(L_base,D_s,i_sl,j_sl)]*q[sb.raws[j_sl-1][p_idx]]
                end
                eta+=sb.sign*(ws[sb.ws_sds[k_sl]]*wi)*sb.xs[k_sl][n]
            end
        end
        if k.has_distributional
            p1=log_prec0;p2=ep0;p3=up0
            for p in k.dist_terms_1;p1+=ws[p.ws_slot]*p.values[n];end
            for r in k.dist_residuals_1;p1+=ws[r.ws_slot]*q[r.raw[r.index[n]]];end
            for p in k.dist_terms_2;p2+=ws[p.ws_slot]*p.values[n];end
            for r in k.dist_residuals_2;p2+=ws[r.ws_slot]*q[r.raw[r.index[n]]];end
            for p in k.dist_terms_3;p3+=ws[p.ws_slot]*p.values[n];end
            for r in k.dist_residuals_3;p3+=ws[r.ws_slot]*q[r.raw[r.index[n]]];end
            ov_prec=exp(p1);ov_ep=p2;ov_up=p3
            isfinite(ov_prec) && ov_prec>zero(Z) || return _bounded_reject(Z,d)
        else
            ov_prec=Z(prec0);ov_ep=ep0;ov_up=up0
        end
        l,de,dp,dz,dh=_bounded_cell_scalar(y[n],eta,ov_prec,ov_ep,ov_up,k.log_width)
        lp+=l
        isfinite(lp) || return _bounded_reject(Z,d)
        for r in k.loc_residuals;grad[r.raw[r.index[n]]]+=r.sign*de;end
        for p in k.loc_row_terms;grad[p.raw]+=de*p.values[n];end
        for sb in k.slopes
            p_idx=sb.index[n]
            for k_sl in 1:(sb.D_dim-1)
                grad[sb.raws[k_sl][p_idx]]+=sb.sign*de*sb.xs[k_sl][n]
            end
        end
        go1+=dp;go2+=dz;go3+=dh
        if k.has_distributional
            for p in k.dist_terms_1;grad[p.raw]+=dp*p.values[n];end
            for r in k.dist_residuals_1;grad[r.raw[r.index[n]]]+=dp;end
            for p in k.dist_terms_2;grad[p.raw]+=dz*p.values[n];end
            for r in k.dist_residuals_2;grad[r.raw[r.index[n]]]+=dz;end
            for p in k.dist_terms_3;grad[p.raw]+=dh*p.values[n];end
            for r in k.dist_residuals_3;grad[r.raw[r.index[n]]]+=dh;end
        end
    end
    @inbounds for p in k.loc_owner_terms
        r_own=k.loc_residuals[p.owner_slot];acc=zero(Z)
        for j in eachindex(r_own.raw);acc+=grad[r_own.raw[j]]*p.values[j];end
        grad[p.raw]=-Z(q[p.raw])+p.sd*acc
    end
    @inbounds for p in k.loc_row_terms
        grad[p.raw]=-Z(q[p.raw])+p.sd*grad[p.raw]
    end
    @inbounds for r in k.loc_residuals
        s_r=ws[r.ws_slot]
        if r.hyper>0
            acc=zero(Z)
            for idx in r.raw;acc+=grad[idx]*q[idx];end
            grad[r.hyper]=-Z(q[r.hyper])+r.logsd*s_r*acc
        end
        for idx in r.raw;grad[idx]=-Z(q[idx])+s_r*grad[idx];end
    end
    @inbounds for sb in k.slopes
        D_s=sb.D_dim;K_s=D_s-1;L_base=sb.ws_L_base;Lbar_base=sb.ws_Lbar_base
        for idx in 1:(D_s*D_s);ws[Lbar_base+idx]=zero(Z);end
        for k_sl in 1:K_s
            h_idx=sb.hyps[k_sl]
            if h_idx>0
                i_sl=k_sl+1;s_k=ws[sb.ws_sds[k_sl]];acc_h=zero(Z)
                for p in eachindex(sb.intercept_raw)
                    wi=ws[_L_slot(L_base,D_s,i_sl,1)]*q[sb.intercept_raw[p]]
                    for j_sl in 2:i_sl
                        wi+=ws[_L_slot(L_base,D_s,i_sl,j_sl)]*q[sb.raws[j_sl-1][p]]
                    end
                    acc_h+=grad[sb.raws[k_sl][p]]*(s_k*wi)
                end
                grad[h_idx]=-Z(q[h_idx])+sb.logsds[k_sl]*acc_h
            end
        end
        if !isempty(sb.corr_raw)
            for p in eachindex(sb.intercept_raw)
                z0_p=q[sb.intercept_raw[p]]
                for i_sl in 2:D_s
                    wbar_ip=ws[sb.ws_sds[i_sl-1]]*grad[sb.raws[i_sl-1][p]]
                    ws[_L_slot(Lbar_base,D_s,i_sl,1)]+=wbar_ip*z0_p
                    for j_sl in 2:i_sl
                        ws[_L_slot(Lbar_base,D_s,i_sl,j_sl)]+=wbar_ip*q[sb.raws[j_sl-1][p]]
                    end
                end
            end
        end
        for p in eachindex(sb.intercept_raw)
            acc0=zero(Z)
            for i_sl in 2:D_s
                acc0+=ws[_L_slot(L_base,D_s,i_sl,1)]*(ws[sb.ws_sds[i_sl-1]]*grad[sb.raws[i_sl-1][p]])
            end
            grad[sb.intercept_raw[p]]+=acc0
            for j_sl in 2:D_s
                accj=zero(Z)
                for i_sl in j_sl:D_s
                    accj+=ws[_L_slot(L_base,D_s,i_sl,j_sl)]*(ws[sb.ws_sds[i_sl-1]]*grad[sb.raws[i_sl-1][p]])
                end
                r_pj=sb.raws[j_sl-1][p]
                grad[r_pj]=-Z(q[r_pj])+accj
            end
        end
        if !isempty(sb.corr_raw)
            k_off=0
            for i_sl in 2:D_s
                len_i=i_sl-1
                rbar=ws[_L_slot(Lbar_base,D_s,i_sl,i_sl)]
                for j_sl in len_i:-1:1
                    c_idx=k_off+j_sl
                    u=ws[sb.ws_u[c_idx]];c=ws[sb.ws_c[c_idx]];r_prev=ws[sb.ws_r[c_idx]]
                    Lbar_ij=ws[_L_slot(Lbar_base,D_s,i_sl,j_sl)]
                    grad[sb.corr_raw[c_idx]]=-2*sb.alphas[c_idx]*u+r_prev*c*(Lbar_ij*c-rbar*u)
                    rbar=Lbar_ij*u+rbar*c
                end
                k_off+=len_i
            end
        end
    end
    @inbounds begin
        grad[off+1]=-Z(q[off+1])+k.prec_logsd*go1
        grad[off+2]=-Z(q[off+2])+k.ep_sd*go2
        grad[off+3]=-Z(q[off+3])+k.up_sd*go3
    end
    if k.has_distributional
        @inbounds for dt in (k.dist_terms_1,k.dist_terms_2,k.dist_terms_3),p in dt
            grad[p.raw]=-Z(q[p.raw])+p.sd*grad[p.raw]
        end
        @inbounds for dr in (k.dist_residuals_1,k.dist_residuals_2,k.dist_residuals_3),r in dr
            s_r=ws[r.ws_slot]
            if r.hyper>0
                acc=zero(Z)
                for idx in r.raw;acc+=grad[idx]*q[idx];end
                grad[r.hyper]=-Z(q[r.hyper])+r.logsd*s_r*acc
            end
            for idx in r.raw;grad[idx]=-Z(q[idx])+s_r*grad[idx];end
        end
    end
    return lp,grad
end
L.logdensity(t::BoundedTarget,q::AbstractVector{<:Real})=first(L.logdensity_and_gradient(t,q))
function pointwise(t::BoundedTarget,q)
    v=coordinates(t,q);width=t.observation.bounds[2]-t.observation.bounds[1]
    [first(bounded_cell(t.y[n],bounded_eta(t,v,n),observation_values(t,v,n),width)) for n in eachindex(t.y)]
end
function names(t::BoundedTarget,scale)
    out=location_names(t,scale)
    append!(out,scale===:raw ? ["log_precision.white","endpoint_logit.white","upper_logit.white"] : ["precision","endpoint_logit","upper_logit"])
    append!(out,distribution_names(t,scale))
    out
end
function record(t::BoundedTarget)
    (;schema=BOUNDED_SCHEMA,table=deepcopy(t.table),columns=t.columns,observation=t.observation,observation_prior=t.observation_prior,
      levels=(;person=copy(t.people),facets=(;(b.name=>copy(b.levels) for b in t.facets)...)),specification=t.specification,
      coordinates=isempty(slope_blocks(t)) ? :white_standard_normal : :white_normal_and_fisher_correlation,measure=:original_score_density_and_endpoint_atoms)
end
function restore_bounded(r)
    r.coordinates in (:white_standard_normal,:white_normal_and_fisher_correlation) && r.measure===:original_score_density_and_endpoint_atoms || throw(ArgumentError("unsupported bounded measure/coordinates"))
    s=r.specification;p=r.observation_prior
    pop=slope_population_restore(s)
    preds=(;(k=>(;(c=>(hasproperty(v,:by) ? (;by=v.by,prior=D.Normal(v.mean,v.sd)) : D.Normal(v.mean,v.sd)) for (c,v) in pairs(cols))...) for (k,cols) in pairs(s.predictors))...)
    rules=hasproperty(s,:decomposition) ? (;(d.source=>(;between=d.between,within=d.within) for d in s.decomposition.rules)...) : nothing
    t=bounded_model(r.table;r.columns...,observation=r.observation,levels=r.levels,population=pop,predictors=preds,
      intercept=D.Normal(s.intercept.mean,s.intercept.sd),decompose=rules,
      observation_prior=restore_observation_prior(p))
    record(t)==r || throw(ArgumentError("bounded design record is not reproducible"));t
end
function response_patterns(t::BoundedTarget)
    n=length(t.y);ni=count(x->0<x<1,t.y);nz=count(iszero,t.y);no=count(==(1),t.y);warnings=String[]
    ni==0 && push!(warnings,"No interior observations: interior mean, precision and their effects are informed only by priors.")
    nz+no==0 && push!(warnings,"No endpoints: the conditional upper-endpoint probability is informed only by its prior.")
    (nz==0 || no==0) && push!(warnings,"One or both endpoints are unused; endpoint probabilities may be weakly informed.")
    constant=NamedTuple[]
    for owner in (:person,keys(t.columns.facets)...)
        ix=_owner_index(t,owner)
        for (j,id) in enumerate(_owner_levels(t,owner))
            ys=t.y[ix.==j]
            !isempty(ys) && all(==(first(ys)),ys) && push!(constant,(;owner,id,n=length(ys),normalized_score=first(ys)))
        end
    end
    !isempty(constant) && push!(warnings,"Constant scores in $(length(constant)) owner levels; inspect response_patterns.constant_levels for IDs.")
    (;n,interior=ni,lower_endpoint=nz,upper_endpoint=no,constant_levels=constant,warnings)
end
warn_patterns(t::BoundedTarget)=foreach(w->@warn(w),response_patterns(t).warnings)
function design(t::BoundedTarget)
    pat=response_patterns(t)
    (;n_observations=length(t.y),n_persons=length(t.people),n_facets=length(t.facets)+1,n_parameters=t.dimension,
      observation=t.observation,allocation=t.allocation,grouping=t.groups,population=t.specification.population,
      response_patterns=pat,warnings=[pat.warnings;hasproperty(t.allocation,:slope_warnings) ? t.allocation.slope_warnings : String[];"Experimental scalar ZOIB: conditional independence beyond declared owners; not Rasch specific objectivity.";
      isempty(distribution_blocks(t)) ? "Interior mean is not total expected score. Endpoint/precision predictors are intercept-only. Integer-grid scores are treated as a continuous interior approximation." : "Distributional terms add on log precision or endpoint logits; baseline precision/logits refer to zero predictors and zero residuals. Parameter blocks are independent a priori; precision is not rating reliability. Integer-grid interiors are a continuous approximation.";
      hasproperty(t.allocation,:distributional_warnings) ? t.allocation.distributional_warnings : String[];
      "Population mean/covariance screening does not establish sufficient information, causal effects or general identification."],scientific_acceptance=false)
end
function contract(t::BoundedTarget)
    (;schema="bayesianmgmfrm.bounded_facet_contract.v1",family=:scalar_explanatory_zoib,dimensions=1,multiplier=1.,
      observation=t.observation,measure=:original_score_density_and_endpoint_atoms,
      mean_structure=:person_plus_response_minus_named_facets,constraints=:population_distributional_zero_mean,
      endpoint_structure=any(b->b.parameter!==:precision,distribution_blocks(t)) ? :declared_predictors_and_population_intercepts : :intercept_only,
      precision_structure=any(b->b.parameter===:precision,distribution_blocks(t)) ? :declared_predictors_and_population_intercepts : :intercept_only,
      prediction=:known_owners_and_stored_attributes,record=record(t))
end

function stan_data(t::BoundedTarget)
    d=merge(location_stan_data(t),slope_stan_data(t),distribution_stan_data(t))
    pr=t.observation_prior
    merge(d,Dict("y"=>copy(t.y),"width"=>t.observation.bounds[2]-t.observation.bounds[1],
      "observation_mean"=>[pr.precision.logmean,pr.endpoint_logit.mean,pr.upper_logit.mean],
      "observation_sd"=>[pr.precision.logsd,pr.endpoint_logit.sd,pr.upper_logit.sd]))
end
