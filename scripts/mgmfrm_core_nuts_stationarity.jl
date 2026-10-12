module MGMFRMCoreNUTSStationarity

using BayesianMGMFRM, LinearAlgebra, Random, ForwardDiff
const HMC = BayesianMGMFRM.AdvancedHMC

"""Independent exact-normal starts followed by ONE production-kernel transition.

This analysis helper does not fit MGMFRM or continue a chain. Separate RNG
streams keep starts independent of the variable number of tree RNG calls.
`embedded=true` uses the actual fixed-nuisance density for a numerical bridge;
the default uses its checked Gaussian formula for inexpensive replication.
All starts, outputs and library statistics are returned, including errors.
"""
function probe(section; replicas, input_seed, transition_seed, step_size,
        inverse_mass = ones(length(section.center)), max_depth = 10,
        max_energy_error = 1000.0, embedded = false)
    replicas isa Integer && !(replicas isa Bool) && replicas > 0 ||
        throw(ArgumentError("positive integer replica count required"))
    for seed in (input_seed, transition_seed)
        seed isa Integer && !(seed isa Bool) && seed >= 0 ||
            throw(ArgumentError("nonnegative integer seeds required"))
    end
    input_seed != transition_seed || throw(ArgumentError("distinct RNG seeds required"))
    max_depth isa Integer && !(max_depth isa Bool) && max_depth > 0 ||
        throw(ArgumentError("positive integer tree depth required"))
    for x in (step_size, max_energy_error)
        x isa Real && !(x isa Bool) && isfinite(x) && x > 0 ||
            throw(ArgumentError("positive finite step and energy limit required"))
    end
    m, K = Float64.(section.center), Matrix{Float64}(section.precision)
    D = length(m)
    D > 0 && all(isfinite,m) && size(K) == (D,D) && all(isfinite,K) && issymmetric(K) ||
        throw(ArgumentError("finite mean and symmetric precision required"))
    R = cholesky(Symmetric(K)).U
    length(inverse_mass) == D && all(x -> x isa Real && !(x isa Bool) && isfinite(x) && x > 0, inverse_mass) ||
        throw(ArgumentError("positive finite inverse masses required"))
    gaussian(q) = -dot(q-m, K*(q-m))/2
    density = embedded ? section.logdensity : gaussian
    gradient = embedded ? q -> (density(q), ForwardDiff.gradient(density,q)) :
        q -> (gaussian(q), -K*(q-m))
    h = HMC.Hamiltonian(HMC.DiagEuclideanMetric(Float64.(inverse_mass)), density, gradient)
    kernel = HMC.HMCKernel(HMC.Trajectory{HMC.MultinomialTS}(
        HMC.Leapfrog(Float64(step_size)), HMC.GeneralisedNoUTurn(Int(max_depth),Float64(max_energy_error))))
    starts_rng, transitions_rng = MersenneTwister(input_seed), MersenneTwister(transition_seed)
    zin, zout = zeros(replicas,D), zeros(replicas,D)
    qin, qout = similar(zin), similar(zout)
    stats = NamedTuple[]
    for i in 1:replicas
        z = randn(starts_rng,D)
        q = m + R \ z
        # Placeholder momentum is replaced by HMCKernel's full refreshment.
        # Never pass a previous transition's state into the next replica.
        initial = HMC.phasepoint(h,copy(q),zeros(D))
        moved = HMC.transition(transitions_rng,h,kernel,initial)
        zin[i,:], qin[i,:] = z, q
        qout[i,:], zout[i,:] = moved.z.θ, R*(moved.z.θ-m)
        push!(stats,moved.stat)
    end
    return (; zin, zout, qin, qout, stats)
end

end
