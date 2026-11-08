# Exact score for the existing D1 slope restriction; the canonical density,
# parameter chart, prior normalizers and saved target identity stay unchanged.
function LogDensityProblems.logdensity_and_gradient(t::_MGMFRMSlopeLogDensity,
        raw::AbstractVector)
    full = _slope_full_raw(t, raw)
    design = t.base.design
    params = _mgmfrm_source_constrained_params_from_unconstrained(
        design, full, t.base.blueprint)
    value, gradient = _slope_likelihood_gradient(
        design, params, t.blueprint.blocks, t.item_slopes === :estimated_positive)
    _slope_prior_gradient!(gradient, raw, t.mean_shift,
        t.blueprint.blocks, t.base.prior, length(design.spec.data.category_levels)-2)
    return value + logprior(t, raw), gradient
end

function _slope_likelihood_gradient(design::FacetDesign, params::AbstractVector{T},
        blocks::Dict{Symbol,UnitRange{Int}}, estimated_slopes::Bool) where {T}
    data = design.spec.data
    K = length(data.category_levels)
    R, I = length(data.rater_levels), length(data.item_levels)
    person = design.blocks[:person]
    rater = design.blocks[:rater]
    item = design.blocks[:item]
    slope = design.blocks[:item_dimension_discrimination]
    raw_person, raw_item = blocks[:person], blocks[:item]
    raw_rater, raw_slope, raw_steps = blocks[:rater_free],
        blocks[:log_item_dimension_discrimination], blocks[:item_steps]
    nparams = sum(length, values(blocks))
    gradient = zeros(T, nparams)
    rater_gradient = zeros(T, R)
    steps = T[_source_step_value(design, params, :item_steps, i, k)
        for k in 1:K, i in 1:I]
    logits, probabilities = zeros(T, K), zeros(T, K)
    total = zero(T)
    for row in 1:data.n
        p, r, i, y = data.person[row], data.rater[row], data.item[row], data.category[row]
        theta, a = params[person[p]], params[slope[i]]
        location = a*theta - params[item[i]] - params[rater[r]]
        logits[1] = zero(T)
        for k in 2:K
            logits[k] = logits[k-1] + 1.7*(location - steps[k,i])
        end
        m = maximum(logits)
        for k in 1:K
            probabilities[k] = exp(logits[k]-m)
        end
        denominator = sum(probabilities)
        total += logits[y] - (m + log(denominator))
        expected_category = zero(T)
        for k in 1:K
            probabilities[k] /= denominator
            expected_category += (k-1)*probabilities[k]
        end
        # Derivative with respect to a*theta - item - severity.
        score = 1.7*((y-1) - expected_category)
        gradient[raw_person[p]] += a*score
        gradient[raw_item[i]] -= score
        rater_gradient[r] -= score
        if estimated_slopes
            gradient[raw_slope[i]] += a*theta*score
        end
        # Last step = -sum(free steps): its contribution cancels that of
        # category K. Accumulate only categories h+1,...,K-1 for free step h.
        tail_score = zero(T)
        offset = first(raw_steps) + (i-1)*(K-2) - 1
        for h in (K-2):-1:1
            tail_score += (y == h+1) - probabilities[h+1]
            gradient[offset+h] -= 1.7*tail_score
        end
    end
    # Last severity = -sum(free severities), including the R=1 empty chart.
    for r in 1:(R-1)
        gradient[raw_rater[r]] = rater_gradient[r] - rater_gradient[R]
    end
    return total, gradient
end

function _slope_prior_gradient!(gradient, raw, means, blocks, prior, nsteps)
    for (block, sd) in ((:person, prior.person_sd), (:item, prior.item_sd),
            (:log_item_dimension_discrimination, prior.log_discrimination_sd))
        for j in blocks[block]
            gradient[j] -= ((raw[j]-means[j])/sd)/sd
        end
    end
    _slope_centered_prior_gradient!(gradient, raw, means,
        blocks[:rater_free], prior.rater_sd)
    if nsteps > 0
        indices = blocks[:item_steps]
        for start in first(indices):nsteps:last(indices)
            _slope_centered_prior_gradient!(gradient, raw, means,
                start:(start+nsteps-1), prior.step_sd)
        end
    end
    return gradient
end

function _slope_centered_prior_gradient!(gradient, raw, means, indices, sd)
    residual_sum = zero(eltype(gradient))
    for j in indices
        residual_sum += raw[j]-means[j]
    end
    for j in indices
        gradient[j] -= (((raw[j]-means[j])+residual_sum)/sd)/sd
    end
    return gradient
end
