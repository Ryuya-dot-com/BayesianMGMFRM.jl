module MGMFRMCoreLocationSection

using BayesianMGMFRM, LinearAlgebra, Statistics, ForwardDiff
const B = BayesianMGMFRM
const HMC = B.AdvancedHMC
const LDP = B.LogDensityProblems
include("mgmfrm_core_location_conditional.jl")

"""Fixed-nuisance Gaussian section of the independent normal-prior MGMFRM.

Move all person abilities and the matching item locations together. This is
an analysis target, not the full fitted posterior or a replacement sampler.
The orthogonal section uses the package's actual coordinate transform;
whitening is an analysis-only reference. No RNG, fit or stored-draw mutation.
"""
function location_section(base::B._MGMFRMGuardedLocalFitLogDensity, raw::AbstractVector;
        coordinates::Symbol = :person_mean)
    coordinates in (:person_mean, :orthogonal_person_mean, :whitened) ||
        throw(ArgumentError("unknown conditional coordinates"))
    B._check_source_fixture_raw_vector(base, raw)
    raw = Float64.(raw)
    D = base.design.spec.dimensions
    blocks = base.blueprint.blocks
    theta = Matrix(reshape(raw[blocks[:person]], D, :)')
    n = size(theta, 1)
    direct = B._mgmfrm_source_constrained_params_from_unconstrained(base.design, raw)
    indices = B._mgmfrm_source_loading_index_matrix(base.design)
    A = [i == 0 ? 0.0 : direct[i] for i in indices]
    conditional = MGMFRMCoreLocationConditional.location_conditional(
        theta, A, raw[blocks[:item]];
        person_sd = base.prior.person_sd, item_sd = base.prior.item_sd)
    function embed_mean(mu)
        length(mu) == D && all(isfinite, mu) || throw(ArgumentError("invalid location vector"))
        out = raw .+ zero(eltype(mu))
        shift = mu - conditional.observed_mean
        out[blocks[:person]] .+= repeat(shift, n)
        out[blocks[:item]] .+= A * shift
        out
    end
    center, precision = conditional.conditional_mean, conditional.precision
    raw_at = embed_mean
    density = q -> LDP.logdensity(base, raw_at(q))
    if coordinates === :orthogonal_person_mean
        transformed = B._MGMFRMLocationLogDensity(base)
        fixed = B._mgmfrm_location_from_raw(transformed, raw)
        function sampling_at(q)
            length(q) == D && all(isfinite, q) || throw(ArgumentError("invalid location vector"))
            point = fixed .+ zero(eltype(q))
            point[blocks[:person][1:D]] = q
            point
        end
        raw_at = q -> B._mgmfrm_location_to_raw(transformed, sampling_at(q))
        density = q -> LDP.logdensity(transformed, sampling_at(q))
        center, precision = sqrt(n) * center, precision / n
    elseif coordinates === :whitened
        R = cholesky(Symmetric(precision)).U
        m = copy(center)
        raw_at = q -> embed_mean(m + R \ q)
        density = q -> LDP.logdensity(base, raw_at(q))
        center, precision = zeros(D), Matrix{Float64}(I, D, D)
    end
    return (; coordinates, center, precision, covariance = inv(Symmetric(precision)),
        raw_at, logdensity = density, conditional, loadings = A, n)
end

"""Closed-form map for a centered Gaussian leapfrog trajectory; no sampling."""
function leapfrog_matrix(precision, inverse_mass, step_size, steps)
    D = size(precision, 1)
    E = Matrix{Float64}(I, D, D)
    W, K = Diagonal(inverse_mass), precision
    h = steps > 0 ? step_size : -step_size
    step = [E-h^2/2*W*K h*W; -h*K+h^3/4*K*W*K E-h^2/2*K*W]
    return step^abs(steps)
end

"""Compare deterministic library integration with the Gaussian reference.

Explicit momenta replace random momentum generation. The origin and basis
vectors identify the affine map because this conditional is Gaussian; an
additional off-basis point checks that inference. Exact-flow stationarity is
an algebra check. Unadjusted leapfrog need not preserve the target covariance.
No NUTS tree, accept/selection rule, adaptation or full-posterior fit is run.
"""
function dynamics_probe(section; inverse_mass = ones(length(section.center)),
        step_size = 0.03, steps = 3)
    D = length(section.center)
    length(inverse_mass) == D && all(x -> x isa Real && !(x isa Bool) && isfinite(x) && x > 0, inverse_mass) ||
        throw(ArgumentError("positive finite inverse masses required"))
    step_size isa Real && !(step_size isa Bool) && isfinite(step_size) && step_size > 0 ||
        throw(ArgumentError("positive finite step size required"))
    steps isa Integer && !(steps isa Bool) && steps != 0 ||
        throw(ArgumentError("nonzero integer step count required"))
    inverse_mass = Float64.(inverse_mass)
    density = section.logdensity
    gradient = q -> (density(q), ForwardDiff.gradient(density, q))
    hamiltonian = HMC.Hamiltonian(HMC.DiagEuclideanMetric(inverse_mass), density, gradient)
    integrator = HMC.Leapfrog(Float64(step_size))
    function actual(state)
        q, p = state[1:D] + section.center, state[D+1:2D]
        finish = HMC.step(integrator, hamiltonian, HMC.phasepoint(hamiltonian, q, p), Int(steps))
        vcat(finish.θ - section.center, finish.r)
    end
    E = Matrix{Float64}(I, 2D, 2D)
    origin = actual(zeros(2D))
    observed_map = hcat([actual(e) - origin for e in eachcol(E)]...)
    expected_map = leapfrog_matrix(section.precision, inverse_mass, step_size, steps)
    point = [(-1.)^i * (0.2 + i/10) for i in 1:2D]
    moved = actual(point)
    flip = Diagonal(vcat(ones(D), -ones(D)))
    Z = zeros(D, D)
    phase_covariance = [section.covariance Z; Z Diagonal(1 ./ inverse_mass)]
    phase_precision = [section.precision Z; Z Diagonal(inverse_mass)]
    generator = [Z Diagonal(inverse_mass); -section.precision Z]
    exact_map = exp((step_size * steps) * generator)
    energy(x) = dot(x, phase_precision*x)/2
    return (; coordinates = section.coordinates, inverse_mass, step_size, steps,
        center = section.center, precision = section.precision, covariance = section.covariance,
        observed_map, expected_map, exact_map, phase_covariance, point, moved,
        origin_error = maximum(abs, origin),
        map_error = maximum(abs, observed_map - expected_map),
        off_basis_error = maximum(abs, moved - expected_map*point),
        reversal_error = maximum(abs, flip*actual(flip*moved) - point),
        volume_error = abs(det(observed_map) - 1),
        energy_change = energy(moved) - energy(point),
        energy_reference = energy(expected_map*point) - energy(point),
        exact_covariance_error = maximum(abs, exact_map*phase_covariance*exact_map' - phase_covariance),
        unadjusted_covariance_change = maximum(abs, observed_map*phase_covariance*observed_map' - phase_covariance))
end

end
