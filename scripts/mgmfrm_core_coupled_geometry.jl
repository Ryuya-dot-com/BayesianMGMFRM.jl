module MGMFRMCoreCoupledGeometry

using BayesianMGMFRM, ForwardDiff, LinearAlgebra
const B = BayesianMGMFRM
const L = B.LogDensityProblems

"""Dense analytic derivatives of the existing location map, for checking only.

The loading-dependent item translation has unit determinant but nonzero
second derivatives. This is not a new parameterization or fitting path.
"""
function geometry(target::B._MGMFRMLocationLogDensity, q)
    base = target.base
    B._check_source_fixture_raw_vector(base,q)
    blocks, Q = base.blueprint.blocks, base.design.spec.q_matrix
    n, D = length(base.design.spec.data.person_levels), size(Q,2)
    J = Matrix{Float64}(I,length(q),length(q))
    # Dense construction independent of the production in-place reflector.
    e = zeros(n); e[1] = 1
    v = e .- 1/sqrt(n)
    H = n == 1 ? ones(1,1) : Matrix{Float64}(I,n,n) - 2(v*v')/dot(v,v)
    J[blocks[:person],blocks[:person]] = kron(H,Matrix{Float64}(I,D,D))
    active = [(i,d) for i in axes(Q,1) for d in 1:D if Q[i,d]]
    for ((i,d),l) in zip(active,blocks[:log_item_dimension_discrimination])
        b, u = blocks[:item][i], blocks[:person][d]
        a = exp(q[l])
        J[b,u] += a/sqrt(n)
        J[b,l] += a*q[u]/sqrt(n)
    end
    function second(v,w)
        length(v) == length(w) == length(q) || throw(ArgumentError("direction size mismatch"))
        out = zeros(length(q))
        for ((i,d),l) in zip(active,blocks[:log_item_dimension_discrimination])
            b, u = blocks[:item][i], blocks[:person][d]
            out[b] += exp(q[l])*(q[u]*v[l]*w[l]+v[u]*w[l]+w[u]*v[l])/sqrt(n)
        end
        out
    end
    return (;jacobian=J,second)
end

function direction_pairs(base)
    Q, blocks = base.design.spec.q_matrix, base.blueprint.blocks
    n = L.dimension(base)
    active = [(i,d) for i in axes(Q,1) for d in axes(Q,2) if Q[i,d]]
    loading = zeros(n)
    loading[blocks[:log_item_dimension_discrimination]] = cos.(.4 .* (1:length(active)))
    pairs = NamedTuple[]
    for d in axes(Q,2)
        v,w = zeros(n),copy(loading)
        v[blocks[:person][d]] = 1
        for (k,(_,dimension)) in zip(blocks[:log_item_dimension_discrimination],active)
            dimension == d || (w[k] = 0)
        end
        push!(pairs,(;name="mean_loading_D$d",v,w=w/norm(w)))
    end
    loading /= norm(loading)
    dense = [sin(.37j)+cos(.19j) for j in 1:n]; dense /= norm(dense)
    append!(pairs,[(;name="loading_self",v=loading,w=loading),(;name="dense_self",v=dense,w=dense)])
    pairs
end

mixed(f,x,v,w) = ForwardDiff.hessian(t -> f(x+t[1]*v+t[2]*w),zeros(2))[1,2]

"""All-coordinate sampler gradients plus selected mixed-curvature checks; no RNG."""
function probe(base,raw)
    target = B._MGMFRMLocationLogDensity(base)
    q = B._mgmfrm_location_from_raw(target,raw)
    f = x -> L.logdensity(base,x)
    g = x -> L.logdensity(target,x)
    raw_lp,raw_gradient = L.logdensity_and_gradient(B._logdensity_gradient_target(base,raw,:ForwardDiff).target,raw)
    lp,gradient = L.logdensity_and_gradient(B._logdensity_gradient_target(target,q,:ForwardDiff).target,q)
    geo = geometry(target,q)
    J = geo.jacobian
    pairs = map(direction_pairs(base)) do pair
        v,w = pair.v,pair.w
        curvature = mixed(g,q,v,w)
        raw_curvature = mixed(f,raw,J*v,J*w)
        second = geo.second(v,w)
        nonlinear_term = dot(raw_gradient,second)
        (;pair...,curvature,raw_curvature,second,nonlinear_term,
            chain_rule_error=abs(curvature-raw_curvature-nonlinear_term))
    end
    return (;raw=copy(raw),q,raw_lp,lp,raw_gradient,gradient,
        jacobian=J,automatic_jacobian=ForwardDiff.jacobian(x -> B._mgmfrm_location_to_raw(target,x),q),
        restored=B._mgmfrm_location_to_raw(target,q),pairs)
end

end
