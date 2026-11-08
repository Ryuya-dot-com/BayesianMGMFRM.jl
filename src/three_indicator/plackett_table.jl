"""Probability-table specialization of the same Plackett likelihood law.

An exact divided-difference identity removes small cell widths before subtracting
radicals. No quadrature, probability floor, clipping or joint renormalization.
"""
module PlackettTable
using ..Plackett: PRECISION_LOCK
export Workspace, probabilities!

struct Workspace{T}
    p::Vector{T}; q::Vector{T}; lp::Vector{T}; lq::Vector{T}
    u::Vector{T}; v::Vector{T}
    r::Matrix{T}; e::Matrix{T}; f::Matrix{T}
    logp::Matrix{T}; probability::Matrix{T}
end
Workspace(::Type{T},K,L) where T=Workspace(zeros(T,K),zeros(T,L),zeros(T,K),zeros(T,L),
    zeros(T,K+1),zeros(T,L+1),zeros(T,K+1,L+1),zeros(T,K+1,L+1),zeros(T,K+1,L+1),
    zeros(T,K,L),zeros(T,K,L))
Workspace(K,L)=Workspace(Float64,K,L)

function marginal!(p,lp,a)
    m=maximum(a);z=zero(eltype(p))
    for i in eachindex(p);p[i]=exp(a[i]-m);z+=p[i];end
    lz=log(z)
    for i in eachindex(p);lp[i]=(a[i]-m)-lz;p[i]/=z;end
end

function cuts!(u,p)
    u[1]=0;total=zero(eltype(u))
    for i in eachindex(p);total+=p[i];u[i+1]=total;end
    tail=zero(eltype(u));u[end]=1
    for i in length(p):-1:2
        tail+=p[i]
        if u[i]>one(total)/2;u[i]=1-tail;end
    end
end

function logtable!(w,a,b,ell)
    marginal!(w.p,w.lp,a);marginal!(w.q,w.lq,b)
    if iszero(ell)
        for j in eachindex(w.q),i in eachindex(w.p);w.logp[i,j]=w.lp[i]+w.lq[j];end
        return true
    end
    cuts!(w.u,w.p);cuts!(w.v,w.q)
    θ=exp(ell);δ=expm1(ell)
    # Conservative numerical condition screen, not a bound on the statistical parameter.
    64*(length(a)+length(b))*eps(typeof(ell))*exp(abs(ell))<=1e-10 || return false
    for j in eachindex(w.v),i in eachindex(w.u)
        u=w.u[i];v=w.v[j]
        e=(1-u-v)+θ*(u-v);f=(1-u-v)+θ*(v-u)
        w.e[i,j]=e;w.f[i,j]=f;w.r[i,j]=hypot(e,2sqrt(θ*v*(1-v)))
    end
    for j in eachindex(w.q),i in eachindex(w.p)
        r00=w.r[i,j];r10=w.r[i+1,j];r01=w.r[i,j+1];r11=w.r[i+1,j+1]
        z=(w.e[i+1,j]+w.e[i,j])/(r10+r00)
        x=(w.f[i+1,j+1]+w.f[i+1,j])/(r11+r10)
        y=(w.f[i,j+1]+w.f[i,j])/(r01+r00)
        numerator=(θ+1)+(δ/2)*z*(x+y)
        multiplier=numerator/(r11+r01)
        isfinite(multiplier) && multiplier>0 || return false
        w.logp[i,j]=w.lp[i]+w.lq[j]+log(multiplier)
    end
    all(isfinite,w.logp)
end

function highprecision(a,b,ell)
    lock(PRECISION_LOCK) do
    bits=max(128,ceil(Int,4abs(ell)/log(2))+128)
    calculate(n)=setprecision(BigFloat,n) do
        w=Workspace(BigFloat,length(a),length(b))
        passed=logtable!(w,BigFloat.(a),BigFloat.(b),BigFloat(ell))
        passed ? Float64.(w.logp) : nothing
    end
    bits<=8192 || error("table precision exceeds resource range; no parameter truncation applied")
    previous=calculate(bits)
    while true
        bits*=2;current=calculate(bits)
        if current!==nothing && previous!==nothing && all(isfinite,current) &&
            maximum(abs.(current-previous))<=1e-12
            return current,bits
        end
        bits<=16384 || error("table precision did not converge; no probability clipping applied")
        previous=current
    end
    end
end

function probabilities!(w::Workspace{Float64},a,b,ell::Real)
    length(a)==length(w.p) && length(b)==length(w.q) && !isempty(a) && !isempty(b) ||
        throw(ArgumentError("logit lengths must match nonempty workspace"))
    all(isfinite,a) && all(isfinite,b) && isfinite(ell) || throw(ArgumentError("finite inputs required"))
    passed=logtable!(w,a,b,Float64(ell));bits=53
    if !passed
        lp,bits=highprecision(a,b,Float64(ell));copyto!(w.logp,lp)
    end
    for i in eachindex(w.logp)
        p=exp(w.logp[i])
        isfinite(p) && p>0 || error("positive table cell not representable in Float64; log probabilities retained")
        w.probability[i]=p
    end
    return bits
end
end
