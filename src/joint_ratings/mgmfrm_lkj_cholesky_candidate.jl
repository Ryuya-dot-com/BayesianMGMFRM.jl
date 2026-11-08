"""Isolated correlation mathematics; not included in the package or any fit runner."""
module MGMFRMLKJCholeskyCandidate

using LinearAlgebra
import BayesianMGMFRM as B

# expm1 preserves small values and derivatives after tanh itself rounds to +/-1.
function stable_tanh(z::Real)
    z >= zero(z) && return -expm1(-2z)/(1+exp(-2z))
    return expm1(2z)/(1+exp(2z))
end

"""
    correlation_state(q, dimensions; eta=2.0)

Stan-order (row-wise strict lower triangle) partial correlations `tanh.(q)`
map to a correlation Cholesky factor L and R = L*L'. `eta` is fixed, positive
and may be noninteger. Returned log kernels omit the normalizing constant
depending on dimensions and eta: they must not be used for estimating eta,
model evidence or prior simulation. No response likelihood or fitting API.

`log_jacobian` is q -> the strict lower triangle of L. The constrained LKJ
kernel uses Lebesgue measure on that triangle, not on R's correlations.
The log complement is evaluated from q, never from the rounded correlation.
At extreme q, dense R may round singular and L's diagonal may underflow. Flags
describe those representational limits; log kernels do not use the rounded L.
No clipping is applied. Full native/integration evidence is limited to D=2.
"""
function correlation_state(q::AbstractVector{<:Real}, dimensions::Integer; eta::Real=2.0)
    !(dimensions isa Bool) && dimensions >= 2 || throw(ArgumentError("dimensions must be at least two"))
    n = Base.checked_mul(dimensions, dimensions - 1) ÷ 2
    length(q) == n || throw(ArgumentError("expected D(D-1)/2 correlation coordinates"))
    !(eta isa Bool) && isfinite(eta) && eta > 0 || throw(ArgumentError("eta must be finite and positive"))
    all(isfinite, q) || throw(ArgumentError("correlation coordinates must be finite"))
    T = promote_type(Float64, eltype(q), typeof(eta))
    L = zeros(T, dimensions, dimensions)
    L[1, 1] = one(T)
    log_jacobian = zero(T)
    log_lkj_kernel = zero(T)
    partial_saturation = false
    k = 0
    for i in 2:dimensions
        log_remaining = zero(T)
        for j in 1:(i - 1)
            k += 1
            z = stable_tanh(q[k])
            partial_saturation |= abs(z) == 1
            log_delta = B._log_one_minus_tanh_squared(q[k])
            L[i, j] = z * exp(log_remaining / 2)
            log_jacobian += log_delta + log_remaining / 2
            log_remaining += log_delta
        end
        L[i, i] = exp(log_remaining / 2)
        log_lkj_kernel += (dimensions - i + 2eta - 2) * log_remaining / 2
    end
    return (; L, R=L * L', partial_saturation, diagonal_underflow=any(iszero,diag(L)),
        log_jacobian, log_lkj_kernel,
        logdensity_kernel=log_lkj_kernel + log_jacobian)
end

end
