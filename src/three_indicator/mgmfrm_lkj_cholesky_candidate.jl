"""Private correlation mathematics; not included in the public package."""
module MGMFRMLKJCholeskyCandidate

using LinearAlgebra

"""A mathematically admissible proposal that cannot be represented numerically."""
struct UnrepresentableProposal <: Exception
    message::String
end
Base.showerror(io::IO, e::UnrepresentableProposal) = print(io, e.message)

# Compute the log remainder independently of rounded tanh(q); no clipping.
log_sech2(q) = 2 * (log(2) - abs(q) - log1p(exp(-2abs(q))))

"""
    correlation_state(q, dimensions; eta=2.0)

Stan-order (row-wise strict lower triangle) partial correlations `tanh.(q)`
map to a correlation Cholesky factor L and R = L*L'. `eta` is fixed, positive
and may be noninteger. Returned log kernels omit the normalizing constant
depending on dimensions and eta: they must not be used for estimating eta,
model evidence or prior simulation. No response likelihood or fitting API.

`log_jacobian` is q -> the strict lower triangle of L. The constrained LKJ
kernel uses Lebesgue measure on that triangle, not on R's correlations.
Rounded tanh values use a stable log remainder, never clipping. A positive
Cholesky diagonal must remain representable. R itself can round to singular
near the boundary; consumers must use L rather than refactor R.
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
            log_delta = log_sech2(q[k])
            L[i, j] = z * exp(log_remaining / 2)
            log_jacobian += log_delta + log_remaining / 2
            log_remaining += log_delta
        end
        L[i, i] = exp(log_remaining / 2)
        L[i, i] > 0 || throw(UnrepresentableProposal("Cholesky diagonal underflow"))
        log_lkj_kernel += (dimensions - i + 2eta - 2) * log_remaining / 2
    end
    return (; L, R=L * L', log_jacobian, log_lkj_kernel,
        logdensity_kernel=log_lkj_kernel + log_jacobian)
end

end
