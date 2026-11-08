"""Isolated correlation mathematics; not included in the package or any fit runner."""
module MGMFRMLKJCholeskyCandidate

using LinearAlgebra

"""
    correlation_state(q, dimensions; eta=2.0)

Stan-order (row-wise strict lower triangle) partial correlations `tanh.(q)`
map to a correlation Cholesky factor L and R = L*L'. `eta` is fixed, positive
and may be noninteger. Returned log kernels omit the normalizing constant
depending on dimensions and eta: they must not be used for estimating eta,
model evidence or prior simulation. No response likelihood or fitting API.

`log_jacobian` is q -> the strict lower triangle of L. The constrained LKJ
kernel uses Lebesgue measure on that triangle, not on R's correlations.
Near-boundary floating-point saturation is rejected, never clipped.
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
    k = 0
    for i in 2:dimensions
        log_remaining = zero(T)
        for j in 1:(i - 1)
            k += 1
            z = tanh(q[k])
            abs(z) < 1 || throw(DomainError(q[k], "partial correlation saturated at the boundary"))
            log_delta = log1p(-z * z)
            L[i, j] = z * exp(log_remaining / 2)
            log_jacobian += log_delta + log_remaining / 2
            log_remaining += log_delta
        end
        L[i, i] = exp(log_remaining / 2)
        L[i, i] > 0 || throw(DomainError(q, "Cholesky diagonal underflow"))
        log_lkj_kernel += (dimensions - i + 2eta - 2) * log_remaining / 2
    end
    return (; L, R=L * L', log_jacobian, log_lkj_kernel,
        logdensity_kernel=log_lkj_kernel + log_jacobian)
end

end
