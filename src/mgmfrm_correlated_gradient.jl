# Exact score for the existing pure-Q 2D target. The density, raw prior measure,
# reconstructed constraints and saved target identity remain canonical.
function LogDensityProblems.logdensity_and_gradient(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity, raw::AbstractVector)
    base_raw, z = _mgmfrm_free_latent_correlation_2d_coordinates(target, raw)
    params = _mgmfrm_free_latent_correlation_2d_constrained_params(target, base_raw)
    value, gradient = _mgmfrm_correlated_likelihood_gradient(target, params, target.base.blueprint.blocks)
    prior = _mgmfrm_free_latent_correlation_2d_logprior(target, raw)
    _mgmfrm_correlated_prior_gradient!(gradient, target, base_raw, z)
    return value + prior, gradient
end

# The blueprint is stored as an abstract NamedTuple; expose its concrete block
# map at this boundary so coordinate lookups do not box values in the row loop.
function _mgmfrm_correlated_likelihood_gradient(target, params::AbstractVector{T},
        raw::Dict{Symbol,UnitRange{Int}}) where {T}
    kernel = target.scalar_kernel
    blocks = target.base.design.blocks
    categories = kernel.n_categories
    R = length(blocks[:rater])
    gradient = zeros(T, target.blueprint.n_parameters::Int)
    severity, log_consistency = zeros(T, R), zeros(T, R)
    logits, probabilities = zeros(T, categories), zeros(T, categories)
    person_offset = first(raw[:person]) - first(blocks[:person])
    item_offset = first(raw[:item]) - first(blocks[:item])
    loading_offset = first(raw[:log_item_dimension_discrimination]) - first(blocks[:item_dimension_discrimination])
    step_offset = first(raw[:item_steps]) - first(blocks[:item_steps])
    rater_offset = 1 - first(blocks[:rater])
    total = zero(T)
    for row in eachindex(kernel.observed_category)
        total += _mgmfrm_free_latent_correlation_2d_scalar_row_loglikelihood!(
            logits, params, kernel, row)
        y = kernel.observed_category[row]
        m = maximum(logits)
        for k in 1:categories
            probabilities[k] = exp(logits[k] - m)
        end
        denominator = sum(probabilities)
        expected_category, expected_logit = zero(T), zero(T)
        for k in 1:categories
            probabilities[k] /= denominator
            expected_category += (k-1)*probabilities[k]
            expected_logit += (logits[k]-m)*probabilities[k]
        end
        pi = kernel.person_parameter_index[row]
        ai = kernel.loading_parameter_index[row]
        r = kernel.rater_parameter_index[row] + rater_offset
        scale = 1.7*params[kernel.consistency_parameter_index[row]]
        score = scale*((y-1)-expected_category)
        gradient[pi+person_offset] += params[ai]*score
        gradient[kernel.item_parameter_index[row]+item_offset] -= score
        gradient[ai+loading_offset] += params[ai]*params[pi]*score
        severity[r] -= score
        # Log consistency multiplies every adjacent-category logit, including
        # the steps. Center before subtracting expectations to avoid cancellation.
        log_consistency[r] += (logits[y]-m)-expected_logit
        tail_score = zero(T)
        for h in kernel.free_steps_per_item:-1:1
            tail_score += (y == h+1)-probabilities[h+1]
            gradient[kernel.first_step_parameter_index[row]+step_offset+h-1] -= scale*tail_score
        end
    end
    for r in 1:(R-1)
        gradient[raw[:rater_free][r]] = severity[r]-severity[R]
        gradient[raw[:log_rater_consistency_free][r]] = log_consistency[r]-log_consistency[R]
    end
    return total, gradient
end

function _mgmfrm_correlated_prior_gradient!(gradient, target, raw, z)
    person = target.base.blueprint.blocks[:person]::UnitRange{Int}
    for i in eachindex(raw)
        _in_range(person, i) && continue
        sd = _source_fixture_prior_sd(target.base, i)
        gradient[i] -= (raw[i]/sd)/sd
    end
    sd = target.prior.source_prior.person_sd
    rho = tanh(z)
    dz = -2target.prior.lkj_eta*rho
    logfour = log(4.0)
    for i in first(person):2:last(person)
        u1, u2 = raw[i]/sd, raw[i+1]/sd
        plus, minus = u1+u2, u1-u2
        # 1/(1±rho) = (1+exp(∓2z))/2. Signed/log-scaled helpers preserve
        # exact zero slices and subnormal derivatives even when tanh(z) rounds ±1.
        gp = _signed_scaled_primal(plus, -2z-logfour-log(sd))
        gm = _signed_scaled_primal(minus, 2z-logfour-log(sd))
        gradient[i] += -(u1/2)/sd-gp-gm
        gradient[i+1] += -(u2/2)/sd-gp+gm
        dz += rho + _zero_primal_scaled_square(plus, -2z-logfour) -
            _zero_primal_scaled_square(minus, 2z-logfour)
    end
    gradient[target.blueprint.zrho_index::Int] = dz
    return gradient
end

_correlated_mgmfrm_gradient_backend(requested::Symbol) = requested === :auto ? :analytic : requested
