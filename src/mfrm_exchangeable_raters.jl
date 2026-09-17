# Private density reference. No fitting/cache selector or change to existing defaults.
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
