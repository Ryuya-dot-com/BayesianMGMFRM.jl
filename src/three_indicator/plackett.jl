"""Discrete Plackett cell likelihood and analytic logit/association scores.

Cancellation triggers a precision-increasing recalculation from original logits;
no floor, clipping or numerical rejection of valid parameter proposals.
"""
module Plackett
export cell, rawcell
const PRECISION_LOCK=ReentrantLock()

softmax(x) = (v=exp.(x .- maximum(x)); v ./ sum(v))

function root(u,v,δ,θ,s)
    b=1+δ*(u+v)
    if iszero(u) || iszero(v)
        zero(u)
    elseif u==1
        v
    elseif v==1
        u
    elseif iszero(δ)
        u*v
    elseif b>=0
        2θ*u*v/(b+s)
    else
        (b-s)/(2δ)
    end
end

function corner(u,v,ell)
    θ=exp(ell); δ=expm1(ell)
    # Keep the diagonal u=v accurate even for very large association.
    e=(1-u-v)+θ*(u-v)
    f=(1-u-v)+θ*(v-u)
    s=hypot(e,2sqrt(θ*v*(1-v)))
    h=root(u,v,δ,θ,s)
    hu=e>=0 ? 2θ*v*(1-v)/(s*(s+e)) : (1-e/s)/2
    hv=f>=0 ? 2θ*u*(1-u)/(s*(s+f)) : (1-f/s)/2
    # Cross-ratio identity + simultaneous reflection avoid u-h and v-h cancellation.
    he=h*root(1-u,1-v,δ,θ,s)/s
    return (h,hu,hv,he)
end

function rawcell(a,b,k,l,ell)
    pa=softmax(a);pb=softmax(b)
    ua=sum(pa[1:k-1]);ub=k==length(pa) ? one(ell) : sum(pa[1:k])
    va=sum(pb[1:l-1]);vb=l==length(pb) ? one(ell) : sum(pb[1:l])
    # Exact independence value, but retain its nonzero association score.
    if iszero(ell)
        ga=-pa;gb=-pb;ga[k]+=1;gb[l]+=1
        lp=(a[k]-maximum(a)-log(sum(exp.(a .- maximum(a)))))+
           (b[l]-maximum(b)-log(sum(exp.(b .- maximum(b)))))
        return (;lp,ga,gb,ge=(1-ua-ub)*(1-va-vb),screen=true)
    end
    h11=corner(ub,vb,ell);h01=corner(ua,vb,ell)
    h10=corner(ub,va,ell);h00=corner(ua,va,ell)
    mass=(h11[1]-h01[1])-(h10[1]-h00[1])
    da1=h11[2]-h10[2];da0=h00[2]-h01[2]
    db1=h11[3]-h01[3];db0=h00[3]-h10[3]
    de=(h11[4]-h01[4])-(h10[4]-h00[4])
    ga=[pa[i]*(da1*((i<=k)-ub)+da0*((i<k)-ua))/mass for i in eachindex(pa)]
    gb=[pb[i]*(db1*((i<=l)-vb)+db0*((i<l)-va))/mass for i in eachindex(pb)]
    # Conservative cancellation screen, not a probability floor or parameter bound.
    # Screen is numerical; failed points are recomputed, not assigned zero density.
    scale=maximum(abs, (h11...,h01...,h10...,h00...))
    screen=isfinite(mass) && mass>0 && mass>1e8*eps(typeof(ell))*max(one(ell),scale) &&
        all(isfinite,ga) && all(isfinite,gb) && isfinite(de/mass)
    return (;lp=mass>0 ? log(mass) : oftype(mass,NaN),ga,gb,ge=de/mass,screen)
end

function cell(a,b,k,l,ell)
    all(isfinite,a) && all(isfinite,b) && isfinite(ell) || throw(ArgumentError("finite logits and log association required"))
    1<=k<=length(a) && 1<=l<=length(b) || throw(ArgumentError("category outside support"))
    x=try
        rawcell(a,b,k,l,Float64(ell))
    catch err
        err isa DomainError || err isa OverflowError || rethrow()
        nothing
    end
    if x!==nothing && x.screen
        return (;x...,bits=53)
    end
    # BigFloat default precision is process-global; serialize our fallback evaluations.
    lock(PRECISION_LOCK) do
    # Precision includes the marginal dynamic ranges and association; no logit clipping.
    bits=max(256,ceil(Int,(2*(maximum(a)-minimum(a)+maximum(b)-minimum(b))+4abs(ell))/log(2))+128)
    calculate(n)=setprecision(BigFloat,n) do
        rawcell(BigFloat.(a),BigFloat.(b),k,l,BigFloat(ell))
    end
    previous=calculate(bits)
    while true
        bits*=2
        current=calculate(bits)
        values(x)=Float64[x.lp;x.ga;x.gb;x.ge]
        p=values(previous);c=values(current)
        if current.screen && all(isfinite,c) && maximum(abs.(c-p)./(1 .+abs.(c)))<=1e-12
            return (;lp=c[1],ga=c[2:1+length(a)],gb=c[2+length(a):end-1],ge=c[end],screen=true,bits)
        end
        bits<=16384 || error("Plackett precision did not converge; no probability clipping applied")
        previous=current
    end
    end
end
end
