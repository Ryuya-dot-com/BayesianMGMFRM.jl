"""Sampler-only 132 coordinates; the scientific target remains in native coordinates."""
module ConcurrentCoordinates
import BayesianMGMFRM as B
import ..Concurrent as C
const L=C.L
struct Target{T}
    native::T
    function Target(t::Union{C.Target,C.AssociationTarget})
        C.require(C.native_target(t).interaction==:full,"132 chart requires full pair correlation")
        new{typeof(t)}(t)
    end
end
B._check_source_fixture_raw_vector(t::Target,q::AbstractVector)=B._check_source_fixture_raw_vector(t.native,q)
L.dimension(t::Target)=L.dimension(t.native)
L.capabilities(::Type{<:Target})=L.LogDensityOrder{1}()

# This orthogonal involution avoids factoring R after correlations round to ±1.
function convert_coordinates(t::Target,v::AbstractVector)
    b=C.native_target(t.native);C.require(length(v)==L.dimension(t) && all(isfinite,v),"finite coordinates of declared size required")
    q=copy(v);z=reshape(view(q,b.blocks[:pair_q]),:,3)
    u=tanh(v[last(b.blocks[:pair_correlation])]);s=exp(C.C.log_sech2(v[last(b.blocks[:pair_correlation])])/2)
    for i in axes(z,1)
        a,c=z[i,2],z[i,3];z[i,2]=u*a+s*c;z[i,3]=s*a-u*c
    end
    q
end
function L.logdensity(t::Target,v::AbstractVector)
    C.require(length(v)==L.dimension(t),"invalid parameter dimension")
    all(isfinite,v) || return oftype(first(v),-Inf)
    L.logdensity(t.native,convert_coordinates(t,v))
end
function L.logdensity_and_gradient(t::Target,v::AbstractVector{<:Real})
    b=C.native_target(t.native);C.require(length(v)==L.dimension(t),"invalid parameter dimension")
    all(isfinite,v) || return (-Inf,zeros(L.dimension(t)))
    q=convert_coordinates(t,Float64.(v));value,g=L.logdensity_and_gradient(t.native,q)
    isfinite(value) || return (-Inf,zeros(L.dimension(t)))
    z=reshape(view(q,b.blocks[:pair_q]),:,3);gz=reshape(view(g,b.blocks[:pair_q]),:,3)
    ix=last(b.blocks[:pair_correlation]);u=tanh(q[ix]);s=exp(C.C.log_sech2(q[ix])/2)
    correction=0.
    for i in axes(z,1)
        a,c=gz[i,2],gz[i,3]
        correction+=s*(a*z[i,3]-c*z[i,2])
        gz[i,2]=u*a+s*c;gz[i,3]=s*a-u*c
    end
    g[ix]+=correction
    all(isfinite,g) ? (value,g) : (-Inf,zeros(L.dimension(t)))
end
end
