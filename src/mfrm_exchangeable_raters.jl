# Private prior reference/comparison. No fitting/cache selector or default change.
struct _MFRMExchangeableRatersLogDensity{T}
    base::T

    function _MFRMExchangeableRatersLogDensity(spec::Union{FacetSpec,CorrelatedMFRMSpec};
            scales::NamedTuple)
        Set(keys(scales)) == Set((:person_sd, :rater_kernel_sd, :item_sd, :step_sd)) &&
            all(x -> x isa Real && !(x isa Bool), values(scales)) ||
            throw(ArgumentError("specify person_sd, rater_kernel_sd, item_sd and step_sd"))
        prior = MFRMPrior(; person_sd = scales.person_sd, rater_sd = scales.rater_kernel_sd,
            item_sd = scales.item_sd, step_sd = scales.step_sd)
        base = _fixed_q_prior_target(spec, prior)
        return new{typeof(base)}(base)
    end
end

_mfrm_exchangeable_rater_reference(target::_MFRMExchangeableRatersLogDensity) =
    target.base isa _MFRMFixedQCorrelated2DLogDensity ? target.base.base : target.base

LogDensityProblems.dimension(target::_MFRMExchangeableRatersLogDensity) =
    LogDensityProblems.dimension(target.base)
LogDensityProblems.capabilities(::Type{<:_MFRMExchangeableRatersLogDensity}) =
    LogDensityProblems.LogDensityOrder{0}()
initial_params(target::_MFRMExchangeableRatersLogDensity) = initial_params(target.base)

function _mfrm_exchangeable_rater_correction(target::_MFRMExchangeableRatersLogDensity, params)
    reference = _mfrm_exchangeable_rater_reference(target)
    return _zero_sum_prior_correction(view(params, reference.blueprint.blocks[:rater_free]),
        reference.prior.rater_sd)
end

# Evaluate the base first: it validates coordinates and retains the original
# ability, item, ordered-step and (when present) correlation/Jacobian terms.
logprior(target::_MFRMExchangeableRatersLogDensity, params::AbstractVector) =
    logprior(target.base, params) + _mfrm_exchangeable_rater_correction(target, params)
LogDensityProblems.logdensity(target::_MFRMExchangeableRatersLogDensity, params::AbstractVector) =
    LogDensityProblems.logdensity(target.base, params) + _mfrm_exchangeable_rater_correction(target, params)

function _mfrm_exchangeable_rater_record(target::_MFRMExchangeableRatersLogDensity)
    reference = _mfrm_exchangeable_rater_reference(target)
    prior = reference.prior
    R = length(reference.design.spec.data.rater_levels)
    base_identity = target.base isa _MFRMFixedQCorrelated2DLogDensity ?
        _mfrm_correlated_2d_identity(target.base) : _mfrm_fixed_q_identity(target.base)
    return (; schema = "bayesianmgmfrm.mfrm_exchangeable_raters.v1", base_identity,
        rater_prior = :normalized_zero_sum_normal, rater_scale_convention = :kernel_sd,
        parameter_measure = :same_free_coordinates_as_base,
        scales = (; prior.person_sd, rater_kernel_sd = prior.rater_sd, prior.item_sd, prior.step_sd),
        rater_marginal_sd = prior.rater_sd * sqrt((R-1)/R),
        rater_contrast_sd = prior.rater_sd * sqrt(2.0),
        item_step_prior = :unchanged_from_base)
end

_mfrm_exchangeable_rater_identity(target::_MFRMExchangeableRatersLogDensity) =
    _cache_hash(_mfrm_exchangeable_rater_record(target))

# Verify a persisted mathematical target record; this is not a saved-fit loader.
function _MFRMExchangeableRatersLogDensity(spec::Union{FacetSpec,CorrelatedMFRMSpec},
        record::NamedTuple; expected_identity::AbstractString)
    hasproperty(record, :scales) && record.scales isa NamedTuple ||
        throw(ArgumentError("invalid exchangeable-rater target record"))
    target = _MFRMExchangeableRatersLogDensity(spec; scales = record.scales)
    isequal(record, _mfrm_exchangeable_rater_record(target)) &&
        _mfrm_exchangeable_rater_identity(target) == expected_identity ||
        throw(ArgumentError("exchangeable-rater target contract or identity mismatch"))
    return target
end

_cmdstan_generalized_family(target::_MFRMExchangeableRatersLogDensity) =
    _cmdstan_generalized_family(target.base)
_cmdstan_generalized_data(target::_MFRMExchangeableRatersLogDensity) =
    merge(_cmdstan_generalized_data(target.base), (; exchangeable_raters = 1))

function _fixed_q_prior_draws(target::_MFRMExchangeableRatersLogDensity,
        ndraws::Int, rng::AbstractRNG)
    draws = _fixed_q_prior_draws(target.base, ndraws, rng)
    block = _mfrm_exchangeable_rater_reference(target).blueprint.blocks[:rater_free]
    n = length(block)
    # The first R-1 coordinates have covariance tau^2 (I - 11'/R).
    # Reuse the independent normal draws; all nonrater draws/RNG steps stay fixed.
    factor = cholesky(Symmetric(Matrix{Float64}(I,n,n) - ones(n,n)/(n+1))).L
    for row in eachrow(draws)
        row[block] .= factor * row[block]
    end
    all(isfinite, draws) || throw(ArgumentError("exchangeable-rater prior generated nonfinite coordinates"))
    return draws
end

function _mfrm_exchangeable_prior_check(target::_MFRMExchangeableRatersLogDensity;
        ndraws::Int = 1000, rng::AbstractRNG = Random.default_rng())
    draws = _fixed_q_prior_draws(target, ndraws, rng)
    base = _mfrm_exchangeable_rater_reference(target)
    direct = _mfrm_fixed_q_predictive_draws(base, view(draws, :, 1:LogDensityProblems.dimension(base)))
    prior = _mfrm_exchangeable_rater_record(target)
    check = _fixed_q_prior_check_from_bundle((; target = target.base, base, draws, direct);
        rng, prior_record = prior)
    return merge(check, (; target_identity = _mfrm_exchangeable_rater_identity(target),
        prior_label = "Rater prior: exchangeable; kernel SD = $(round(prior.scales.rater_kernel_sd; sigdigits=5))."))
end

# Private prior-only comparison. Matching is an explicit variance criterion,
# not a claim that every legacy rater marginal or contrast can be preserved.
function _mfrm_rater_prior_comparison(spec::Union{FacetSpec,CorrelatedMFRMSpec};
        prior::MFRMPrior, matching::Symbol, seed::Integer, ndraws::Int = 1000)
    matching in (:mean_contrast_variance, :free_rater_marginal_sd) ||
        throw(ArgumentError("matching must be :mean_contrast_variance or :free_rater_marginal_sd"))
    seed isa Bool && throw(ArgumentError("seed must be an integer, not Bool"))
    old_target = _fixed_q_prior_target(spec, prior)
    base = old_target isa _MFRMFixedQCorrelated2DLogDensity ? old_target.base : old_target
    R = length(base.design.spec.data.rater_levels)
    # Legacy mean pairwise contrast variance = 4*sigma^2 for every R>=2.
    tau = prior.rater_sd * (matching === :mean_contrast_variance ? sqrt(2.0) : sqrt(R/(R-1)))
    target = _MFRMExchangeableRatersLogDensity(spec; scales = (;
        prior.person_sd, rater_kernel_sd = tau, prior.item_sd, prior.step_sd))
    rng, rng_control = _fit_rng(Random.default_rng(), seed)
    old = _fixed_q_prior_predictive_check(spec; prior, ndraws, rng = copy(rng))
    exchangeable = _mfrm_exchangeable_prior_check(target; ndraws, rng)
    description = matching === :mean_contrast_variance ?
        "Matching: mean pairwise contrast variance." : "Matching: free-rater marginal SD."
    old_identity = old_target isa _MFRMFixedQCorrelated2DLogDensity ?
        _mfrm_correlated_2d_identity(old_target) : _mfrm_fixed_q_identity(old_target)
    old = merge(old, (; target_identity = old_identity,
        prior_label = "Rater prior: independent free severities; SD = $(round(prior.rater_sd; sigdigits=5)).\n" * description))
    exchangeable = merge(exchangeable, (; prior_label = exchangeable.prior_label * "\n" * description))
    sigma2 = prior.rater_sd^2
    scales = [
        (; model = :independent_free, free_or_kernel_sd = prior.rater_sd,
            first_rater_sd = prior.rater_sd, last_rater_sd = prior.rater_sd*sqrt(R-1),
            free_pair_contrast_sd = R > 2 ? sqrt(2.0)*prior.rater_sd : missing,
            last_pair_contrast_sd = prior.rater_sd*sqrt(R+2),
            mean_marginal_variance = 2*(R-1)/R*sigma2, mean_contrast_variance = 4sigma2),
        (; model = :exchangeable, free_or_kernel_sd = tau,
            first_rater_sd = exchangeable.prior.rater_marginal_sd,
            last_rater_sd = exchangeable.prior.rater_marginal_sd,
            free_pair_contrast_sd = R > 2 ? exchangeable.prior.rater_contrast_sd : missing,
            last_pair_contrast_sd = exchangeable.prior.rater_contrast_sd,
            mean_marginal_variance = tau^2*(R-1)/R, mean_contrast_variance = 2tau^2)]
    return (; schema = "bayesianmgmfrm.mfrm_rater_prior_comparison.v1", matching, scales,
        rng = merge(rng_control, (; coupling = :shared_nonrater_draws_and_predictive_uniforms)),
        independent_free = old, exchangeable)
end
