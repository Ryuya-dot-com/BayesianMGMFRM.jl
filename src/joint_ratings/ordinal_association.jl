"""Experimental paired ordinal ratings with explicit means, estimated person scales
and within-event association. Use `model`, `fit`, `report`, `contrast`,
`save_result` and `load_result`. Read `contract()` before use."""
module OrdinalAssociation
using LinearAlgebra
import LogDensityProblems as L
include("association_kernel.jl")
include("mean_scale_layout.jl")
const C=AssociationKernel
const H=MeanScaleLayout
const S=C.S

struct Target{T}
    layout::T
    intercept_sd::Float64
    estimated_scale::Bool
    log_sd_mean::Float64
    log_sd_sd::Float64
end
function Target(original;intercept_sd,estimated_scale=true,log_sd_mean,log_sd_sd)
    all(isfinite,(intercept_sd,log_sd_mean,log_sd_sd)) && intercept_sd>0 && log_sd_sd>0 ||
        throw(ArgumentError("finite mean and positive prior widths required"))
    Target(H.Target(original),Float64(intercept_sd),Bool(estimated_scale),Float64(log_sd_mean),Float64(log_sd_sd))
end
L.dimension(t::Target)=L.dimension(t.layout)+2t.estimated_scale
L.capabilities(::Type{<:Target})=L.LogDensityOrder{1}()
function geometry(t,x)
    h=t.layout;base=h.original.base;P=base.sizes[1]
    z=x[base.blocks.correlation[1]-2]
    cp=S.C.correlation_state([z],2;eta=base.prior.person_lkj_eta)
    sd=t.estimated_scale ? exp.(x[end-1:end]) : ones(eltype(x),2)
    root=Diagonal(sd)*cp.L;sigma=root*root'
    # Avoid subtracting almost equal variances in finite but adverse proposals.
    a1=sd[1]/sqrt(P);a2=sd[2]/sqrt(P);la=hypot(a1,t.intercept_sd)
    r=a1/la;fraction=t.intercept_sd/la;lb=r*a2*cp.L[2,1]
    independent=a2*hypot(fraction,r*cp.L[2,2]);lc=hypot(t.intercept_sd,independent)
    location_root=[la zero(z);lb lc]
    delta=exp(C.B._log_one_minus_tanh_squared(z))
    dzb=r*a2*delta;d1b=lb*fraction^2
    derivatives=([zero(z) zero(z);dzb -(lb/lc)*dzb],
                 [a1*r zero(z);d1b -(lb/lc)*d1b],
                 [zero(z) zero(z);lb (independent/lc)*independent])
    (;cp,sd,root,sigma,location_root,derivatives,delta,d=location_root*x[h.difference])
end
function representative(t,x)
    length(x)==L.dimension(t) || throw(ArgumentError("wrong mean/scale dimension"))
    h=t.layout;base=h.original.base;P,T=base.sizes;b=base.blocks
    g=geometry(t,x);white=reshape(x[h.person],2,P-1)*h.hp'
    theta=g.root*white
    q=zeros(eltype(x),L.dimension(h.original));q[H.tail(h)]=x[h.tail]
    q[b.task]=vec(base.prior.task_sd*reshape(x[h.task],2,T-1)*h.ht'.-g.d)
    # Supply physical effects directly to the checked score kernel. Mapping them
    # back through the old unit-SD Cholesky factor loses precision near |rho|=1.
    coordinates=merge(C.coordinates(h.original,q),(;theta))
    (;q,g,white,theta,coordinates)
end
function evaluate(t,x,with_gradient)
    length(x)==L.dimension(t) || throw(ArgumentError("wrong mean/scale dimension"))
    reject()=(-oftype(first(x),Inf),fill(oftype(first(x),NaN),length(x)))
    all(isfinite,x) || return reject()
    if t.estimated_scale
        sd=exp.(x[end-1:end]);all(y->isfinite(y) && y>0 && isfinite(y*y),sd) || return reject()
    end
    h=t.layout;base=h.original.base;b=base.blocks;P,T=base.sizes;s=base.prior.task_sd
    z=x[b.correlation[1]-2]
    exp(C.B._log_one_minus_tanh_squared(z)/2)>0 || return reject()
    v=representative(t,x);q=v.q;geom=v.g
    prior=S.logprior(base,view(q,1:L.dimension(base)),v.coordinates)+H.gaussian_logpdf([q[end]],h.original.lambda_sd)
    value,g=C.score_coordinates(h.original,q,v.coordinates,prior,with_gradient)
    isfinite(value) || return reject()
    value+=H.gaussian_logpdf(view(x,1:last(h.difference)))-
           H.gaussian_logpdf(view(q,b.person_white))-H.gaussian_logpdf(view(q,b.task),s)
    t.estimated_scale && (value+=H.gaussian_logpdf(x[end-1:end].-t.log_sd_mean,t.log_sd_sd))
    with_gradient || return value,similar(x,0)
    gtheta=geom.cp.L'\reshape(g[b.person_white]+q[b.person_white],2,P)
    gt=reshape(g[b.task]+q[b.task]/s^2,2,T)
    gd=-vec(sum(gt;dims=2));out=similar(x)
    out[h.person]=vec(geom.root'*gtheta*h.hp)-x[h.person]
    out[h.task]=vec(s*gt*h.ht)-x[h.task]
    out[h.difference]=geom.location_root'*gd-x[h.difference]
    out[h.tail]=g[H.tail(h)]
    rho=geom.cp.R[1,2];zder=geom.sd[2]*(geom.delta*v.white[1,:]-rho*geom.cp.L[2,2]*v.white[2,:])
    out[b.correlation[1]-2]=-2base.prior.person_lkj_eta*rho+dot(gtheta[2,:],zder)+
        dot(gd,geom.derivatives[1]*x[h.difference])
    if t.estimated_scale
        for c in 1:2
            out[end-2+c]=-(x[end-2+c]-t.log_sd_mean)/t.log_sd_sd^2+
                dot(gtheta[c,:],v.theta[c,:])+dot(gd,geom.derivatives[c+1]*x[h.difference])
        end
    end
    all(isfinite,out) || return reject()
    value,out
end
L.logdensity(t::Target,x::AbstractVector{<:Real})=first(evaluate(t,x,false))
L.logdensity_and_gradient(t::Target,x::AbstractVector{<:Real})=evaluate(t,x,true)

"""Map physical effects of an old saved point into new coordinates, never a posterior migration."""
function from_original(t,q;sd=(1.,1.))
    all(y->isfinite(y) && y>0,sd) || throw(ArgumentError("positive finite speaker SDs required"))
    !t.estimated_scale && sd!=(1.,1.) && throw(ArgumentError("fixed-scale target requires SD1"))
    h=t.layout;base=h.original.base;P,T=base.sizes
    v=C.coordinates(h.original,q);x=zeros(eltype(q),L.dimension(t));x[h.tail]=q[H.tail(h)]
    t.estimated_scale && (x[end-1:end]=log.(collect(sd)))
    geom=geometry(t,x)
    # Solve L_new * Z_new = L_old * Z_old algebraically before multiplying
    # by Z_old, preserving the tiny independent coordinate at extreme rho.
    white=reshape(q[base.blocks.person_white],2,P)
    converted=copy(white);converted[1,:]./=sd[1]
    converted[2,:]=white[2,:]/sd[2]+(geom.cp.L[2,1]/geom.cp.L[2,2])*(1/sd[2]-1/sd[1])*white[1,:]
    x[h.person]=vec(converted*h.hp)
    x[h.task]=vec(v.task*h.ht/base.prior.task_sd)
    d=vec(sum(v.theta;dims=2))/P-vec(sum(v.task;dims=2))/T
    x[h.difference]=geom.location_root\d
    x
end

function conditional(t,geom)
    P=t.layout.original.base.sizes[1];root=geom.root/sqrt(P)
    covariance=inv(Symmetric(I+root'*root/t.intercept_sd^2))
    white_mean=covariance*(root'*geom.d)/t.intercept_sd^2
    white_root=Matrix(cholesky(Symmetric(covariance)).L)
    (;mean=root*white_mean,root=root*white_root,white_mean,white_root)
end

"""Restore model effects for explicit conditional white location u; no RNG here."""
function effects(t,x,u)
    length(u)==2 || throw(ArgumentError("two location coordinates required"))
    h=t.layout;base=h.original.base;P,T=base.sizes;v=representative(t,x);g=v.g
    cond=conditional(t,g);m=cond.mean+cond.root*u
    word=base.prior.task_sd*reshape(x[h.task],2,T-1)*h.ht'
    (;theta=v.theta.+m,word,intercept=g.d-m,speaker_sd=g.sd,
      speaker_correlation=g.cp.R[1,2],conditional_mean=cond.mean,conditional_covariance=cond.root*cond.root')
end
include("ordinal_association_workflow.jl")
end
