module MGMFRMCoreLocationConditional

using LinearAlgebra, Statistics

"""Gaussian location conditional under independent zero-mean normal raw priors.

The likelihood must be invariant under theta[p,:] += shift, b += A*shift.
Condition on centered persons, offsets b-A*mean(theta), loadings A and the other
coordinates. This pure algebra helper does not establish model applicability,
fit convergence or calibration. It changes no draw or prior. Correlated person
priors, anchors and non-normal priors require a different conditional.
"""
function location_conditional(theta::AbstractMatrix{<:Real},
        A::AbstractMatrix{<:Real}, b::AbstractVector{<:Real};
        person_sd::Real, item_sd::Real)
    n, D = size(theta)
    n > 0 && D > 0 && size(A,1) == length(b) > 0 && size(A,2) == D ||
        throw(ArgumentError("Nonempty compatible person, loading and item arrays required"))
    all(x -> !(x isa Bool) && isfinite(x), theta) &&
        all(x -> !(x isa Bool) && isfinite(x), A) &&
        all(x -> !(x isa Bool) && isfinite(x), b) &&
        all(s -> !(s isa Bool) && isfinite(s) && s > 0, (person_sd,item_sd)) ||
        throw(ArgumentError("Finite coordinates and positive finite prior SDs required"))
    persons, loadings, items = Float64.(theta), Float64.(A), Float64.(b)
    observed_mean = vec(mean(persons; dims=1))
    offsets = items-loadings*observed_mean
    precision = Matrix{Float64}(I,D,D) .* (n/person_sd^2) + loadings'loadings/item_sd^2
    factor = cholesky(Symmetric(precision))
    covariance = Matrix(inv(factor))
    conditional_mean = -(factor \ (loadings'offsets/item_sd^2))
    standardized_residual = factor.U*(observed_mean-conditional_mean)
    all(isfinite, covariance) && all(isfinite, conditional_mean) &&
        all(isfinite, standardized_residual) || throw(ArgumentError("Nonfinite conditional calculation"))
    return (;observed_mean, offsets, precision, covariance, conditional_mean,
        standardized_residual)
end

end
