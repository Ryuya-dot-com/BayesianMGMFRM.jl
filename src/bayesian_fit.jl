# bayesian_fit.jl -- minimal Bayesian MFRM fitting for the v0.1 design scaffold.

using Random
using SHA
using Serialization
import AdvancedHMC
import ForwardDiff
import JSON3
import LogDensityProblems
import LogDensityProblemsAD
import Turing

const LOG2PI_BAYES = log(2 * pi)

"""
    MFRMPrior(; person_sd = 1.5, rater_sd = 1.0, item_sd = 1.0, step_sd = 1.0)

Independent zero-centered normal priors for the identified minimal MFRM
parameter vector returned by `getdesign`. The scales apply to person, rater,
item, and threshold-step blocks after the current reference and sum-to-zero
constraints have been imposed.
"""
struct MFRMPrior
    person_sd::Float64
    rater_sd::Float64
    item_sd::Float64
    step_sd::Float64

    function MFRMPrior(person_sd::Real, rater_sd::Real, item_sd::Real, step_sd::Real)
        values = (person_sd, rater_sd, item_sd, step_sd)
        all(x -> isfinite(x) && x > 0, values) ||
            throw(ArgumentError("all prior standard deviations must be finite and positive"))
        return new(Float64(person_sd), Float64(rater_sd), Float64(item_sd), Float64(step_sd))
    end
end

MFRMPrior(; person_sd::Real = 1.5,
            rater_sd::Real = 1.0,
            item_sd::Real = 1.0,
            step_sd::Real = 1.0) =
    MFRMPrior(person_sd, rater_sd, item_sd, step_sd)

"""
    MFRMFit

Posterior draws and sampler metadata returned by `fit` for the minimal MFRM
design scaffold. `draws` is a matrix with one posterior draw per row and one
identified design parameter per column, in `fit.design.parameter_names` order.
When multiple chains are requested, rows are grouped by chain and recorded in
`chain_ids` and `iterations`.
"""
struct MFRMFit
    design::FacetDesign
    prior::MFRMPrior
    draws::Matrix{Float64}
    log_posterior::Vector{Float64}
    acceptance_rate::Float64
    chain_ids::Vector{Int}
    iterations::Vector{Int}
    chain_acceptance_rate::Vector{Float64}
    backend::Symbol
    sampler::Symbol
    warmup::Int
    step_size::Float64
    sampler_stats::Vector{NamedTuple}
    sampler_controls::NamedTuple
end

MFRMFit(design::FacetDesign,
        prior::MFRMPrior,
        draws::Matrix{Float64},
        log_posterior::Vector{Float64},
        acceptance_rate::Float64,
        chain_ids::Vector{Int},
        iterations::Vector{Int},
        chain_acceptance_rate::Vector{Float64},
        backend::Symbol,
        sampler::Symbol,
        warmup::Int,
        step_size::Float64) =
    MFRMFit(design, prior, draws, log_posterior, acceptance_rate, chain_ids,
        iterations, chain_acceptance_rate, backend, sampler, warmup, step_size,
        NamedTuple[], NamedTuple())

function Base.show(io::IO, fit::MFRMFit)
    print(io, "MFRMFit(",
        size(fit.draws, 1), " draw(s), ",
        size(fit.draws, 2), " parameter(s), backend = :",
        fit.backend, ", sampler = :", fit.sampler,
        ", chains = ", length(fit.chain_acceptance_rate),
        ", acceptance_rate = ",
        round(fit.acceptance_rate; digits = 3), ")")
end

@inline function _normal_logpdf(x::Real, sd::Float64)
    z = x / sd
    return -log(sd) - 0.5 * (LOG2PI_BAYES + z * z)
end

function _in_range(range::UnitRange{Int}, index::Int)
    return first(range) <= index <= last(range)
end

function _prior_sd(design::FacetDesign, prior::MFRMPrior, index::Int)
    _in_range(design.blocks[:person], index) && return prior.person_sd
    _in_range(design.blocks[:rater], index) && return prior.rater_sd
    _in_range(design.blocks[:item], index) && return prior.item_sd
    _in_range(design.blocks[:thresholds], index) && return prior.step_sd
    throw(ArgumentError("parameter index $index is not covered by any design block"))
end

function _check_parameter_vector(design::FacetDesign, params::AbstractVector)
    expected = length(design.parameter_names)
    length(params) == expected ||
        throw(ArgumentError("parameter vector has length $(length(params)); expected $expected"))
    try
        all(isfinite, params) ||
            throw(ArgumentError("parameter vector contains non-finite values"))
    catch err
        err isa ArgumentError && rethrow()
        throw(ArgumentError("parameter vector contains values that cannot be checked as finite"))
    end
    return nothing
end

"""
    logprior(design::FacetDesign, params, prior = MFRMPrior())
    logprior(spec::FacetSpec, params, prior = MFRMPrior())

Evaluate the independent normal log prior for the identified minimal MFRM
parameter vector returned by `getdesign`.
"""
function logprior(design::FacetDesign, params::AbstractVector, prior::MFRMPrior = MFRMPrior())
    _check_parameter_vector(design, params)
    lp = _param_zero(params)
    for index in eachindex(params)
        lp += _normal_logpdf(params[index], _prior_sd(design, prior, index))
    end
    return lp
end

logprior(spec::FacetSpec, params::AbstractVector, prior::MFRMPrior = MFRMPrior()) =
    logprior(getdesign(spec), params, prior)

"""
    loglikelihood(design::FacetDesign, params)
    loglikelihood(spec::FacetSpec, params)

Evaluate the total minimal additive MFRM/RSM/PCM log likelihood for the
identified parameter vector returned by `getdesign`, without Bayesian priors.
"""
function loglikelihood(design::FacetDesign, params::AbstractVector)
    _check_parameter_vector(design, params)
    return sum(pointwise_loglikelihood(design, params))
end

loglikelihood(spec::FacetSpec, params::AbstractVector) =
    loglikelihood(getdesign(spec), params)

"""
    logposterior(design::FacetDesign, params, prior = MFRMPrior())
    logposterior(spec::FacetSpec, params, prior = MFRMPrior())

Evaluate the log posterior for the minimal additive MFRM/RSM/PCM design:
the sum of `loglikelihood(design, params)` plus `logprior(design, params,
prior)` on the identified parameter vector.
"""
function logposterior(design::FacetDesign, params::AbstractVector, prior::MFRMPrior = MFRMPrior())
    return loglikelihood(design, params) + logprior(design, params, prior)
end

logposterior(spec::FacetSpec, params::AbstractVector, prior::MFRMPrior = MFRMPrior()) =
    logposterior(getdesign(spec), params, prior)

"""
    MFRMLogDensity(design::FacetDesign; prior = MFRMPrior())
    MFRMLogDensity(spec::FacetSpec; prior = MFRMPrior())

`LogDensityProblems.jl` target for the current minimal Bayesian MFRM/RSM/PCM
posterior. This object exposes the same log posterior as `logposterior` through
`LogDensityProblems.logdensity`, so external samplers and automatic
differentiation wrappers can use the package's design compiler without relying
on the internal random-walk Metropolis sampler.
"""
struct MFRMLogDensity
    design::FacetDesign
    prior::MFRMPrior
end

MFRMLogDensity(design::FacetDesign; prior::MFRMPrior = MFRMPrior()) =
    MFRMLogDensity(design, prior)

MFRMLogDensity(spec::FacetSpec; prior::MFRMPrior = MFRMPrior()) =
    MFRMLogDensity(getdesign(spec), prior)

function Base.show(io::IO, target::MFRMLogDensity)
    print(io, "MFRMLogDensity(",
        length(target.design.parameter_names), " parameter(s), thresholds = :",
        target.design.spec.thresholds, ")")
end

LogDensityProblems.logdensity(target::MFRMLogDensity, params) =
    logposterior(target.design, params, target.prior)

LogDensityProblems.dimension(target::MFRMLogDensity) =
    length(target.design.parameter_names)

LogDensityProblems.capabilities(::Type{MFRMLogDensity}) =
    LogDensityProblems.LogDensityOrder{0}()

const _AD_GRADIENT_BACKENDS = (:ForwardDiff, :ReverseDiff)

function _gradient_backend_kind(ad_backend::Symbol)
    ad_backend === :analytic && return :analytic
    ad_backend in _AD_GRADIENT_BACKENDS && return :ad
    throw(ArgumentError(
        "ad_backend must be :ForwardDiff, :ReverseDiff, or :analytic",
    ))
end

function _check_logdensity_gradient_result(logdensity,
        gradient,
        nparams::Int,
        ad_backend::Symbol)
    isfinite(logdensity) ||
        throw(ArgumentError("ad_backend = :$ad_backend returned a non-finite log density"))
    length(gradient) == nparams ||
        throw(ArgumentError(
            "ad_backend = :$ad_backend returned a gradient of length $(length(gradient)); expected $nparams",
        ))
    all(isfinite, gradient) ||
        throw(ArgumentError("ad_backend = :$ad_backend returned a non-finite gradient"))
    return nothing
end

function _gradient_target_error(ad_backend::Symbol, err)
    message = sprint(showerror, err)
    if ad_backend === :analytic
        return ArgumentError(
            "ad_backend = :analytic requires a target with a valid " *
            "LogDensityProblems.logdensity_and_gradient method; use an AD backend " *
            "such as :ForwardDiff for order-0 targets. Original error: $message",
        )
    end
    return ArgumentError(
        "ad_backend = :$ad_backend could not initialize or evaluate " *
        "LogDensityProblemsAD.ADgradient. Ensure the AD package is available " *
        "and the target supports it. Original error: $message",
    )
end

function _logdensity_gradient_target(target, initial::AbstractVector, ad_backend::Symbol)
    nparams = LogDensityProblems.dimension(target)
    length(initial) == nparams ||
        throw(ArgumentError("initial parameter vector has length $(length(initial)); expected $nparams"))
    kind = _gradient_backend_kind(ad_backend)
    if kind === :analytic
        try
            logdensity, gradient = LogDensityProblems.logdensity_and_gradient(target, initial)
            _check_logdensity_gradient_result(logdensity, gradient, nparams, ad_backend)
            return (;
                target,
                ad_backend,
                gradient_backend = :analytic,
            )
        catch err
            err isa ArgumentError && rethrow()
            throw(_gradient_target_error(ad_backend, err))
        end
    end

    try
        adtarget = LogDensityProblemsAD.ADgradient(ad_backend, target; x = initial)
        logdensity, gradient = LogDensityProblems.logdensity_and_gradient(adtarget, initial)
        _check_logdensity_gradient_result(logdensity, gradient, nparams, ad_backend)
        return (;
            target = adtarget,
            ad_backend,
            gradient_backend = :ad,
        )
    catch err
        err isa ArgumentError && rethrow()
        throw(_gradient_target_error(ad_backend, err))
    end
end

struct _SourceFixturePrior
    person_sd::Float64
    rater_sd::Float64
    item_sd::Float64
    log_discrimination_sd::Float64
    log_consistency_sd::Float64
    step_sd::Float64

    function _SourceFixturePrior(person_sd::Real,
            rater_sd::Real,
            item_sd::Real,
            log_discrimination_sd::Real,
            log_consistency_sd::Real,
            step_sd::Real)
        for (name, value) in (
                (:person_sd, person_sd),
                (:rater_sd, rater_sd),
                (:item_sd, item_sd),
                (:log_discrimination_sd, log_discrimination_sd),
                (:log_consistency_sd, log_consistency_sd),
                (:step_sd, step_sd),
            )
            isfinite(value) && value > 0 ||
                throw(ArgumentError("$name must be a finite positive scale"))
        end
        return new(
            Float64(person_sd),
            Float64(rater_sd),
            Float64(item_sd),
            Float64(log_discrimination_sd),
            Float64(log_consistency_sd),
            Float64(step_sd),
        )
    end
end

_SourceFixturePrior(; person_sd::Real = 1.0,
    rater_sd::Real = 1.0,
    item_sd::Real = 1.0,
    log_discrimination_sd::Real = 0.5,
    log_consistency_sd::Real = 0.5,
    step_sd::Real = 1.0) =
    _SourceFixturePrior(
        person_sd,
        rater_sd,
        item_sd,
        log_discrimination_sd,
        log_consistency_sd,
        step_sd,
    )

"""
    GMFRMFit

Experimental scalar GMFRM fit result returned only by
`fit(spec; experimental = true)` for the one-dimensional rater-discrimination
promotion candidate.
Raw draws are stored in `draws`, constrained direct draws in `direct_draws`, and
observation-ordered direct pointwise log likelihoods in
`direct_pointwise_loglikelihood`.
"""
struct GMFRMFit
    design::FacetDesign
    prior::_SourceFixturePrior
    draws::Matrix{Float64}
    log_posterior::Vector{Float64}
    direct_draws::Matrix{Float64}
    direct_loglikelihood::Vector{Float64}
    direct_pointwise_loglikelihood::Matrix{Float64}
    chain_ids::Vector{Int}
    iterations::Vector{Int}
    chain_acceptance_rate::Vector{Float64}
    backend::Symbol
    sampler::Symbol
    warmup::Int
    step_size::Float64
    sampler_stats::Vector{NamedTuple}
    sampler_controls::NamedTuple
    diagnostic_surface::NamedTuple
end

"""
    MGMFRMFit

Guarded experimental MGMFRM fit result returned by
`fit(spec; experimental = true)` for the fixed-Q, two-dimensional confirmatory
candidate. Raw draws are stored in `draws`, constrained direct draws in
`direct_draws`, and observation-ordered direct pointwise log likelihoods in
`direct_pointwise_loglikelihood`.
"""
struct MGMFRMFit
    design::FacetDesign
    prior::_SourceFixturePrior
    draws::Matrix{Float64}
    log_posterior::Vector{Float64}
    direct_draws::Matrix{Float64}
    direct_loglikelihood::Vector{Float64}
    direct_pointwise_loglikelihood::Matrix{Float64}
    chain_ids::Vector{Int}
    iterations::Vector{Int}
    chain_acceptance_rate::Vector{Float64}
    backend::Symbol
    sampler::Symbol
    warmup::Int
    step_size::Float64
    sampler_stats::Vector{NamedTuple}
    sampler_controls::NamedTuple
    diagnostic_surface::NamedTuple
end

const _ModelComparisonFit = Union{MFRMFit,GMFRMFit,MGMFRMFit}
const _MODEL_COMPARISON_CONTRACT = :same_observation_data_same_latent_dimensions
const _KFOLD_COMPARISON_CONTRACT = :same_heldout_observation_folds

function Base.show(io::IO, fit::GMFRMFit)
    print(io, "GMFRMFit(",
        size(fit.draws, 1), " raw draw(s), ",
        size(fit.draws, 2), " raw parameter(s), backend = :",
        fit.backend, ", sampler = :", fit.sampler,
        ", chains = ", length(fit.chain_acceptance_rate),
        ", experimental_public = true)")
end

function Base.show(io::IO, fit::MGMFRMFit)
    print(io, "MGMFRMFit(",
        size(fit.draws, 1), " raw draw(s), ",
        size(fit.draws, 2), " raw parameter(s), backend = :",
        fit.backend, ", sampler = :", fit.sampler,
        ", chains = ", length(fit.chain_acceptance_rate),
        ", experimental_public = true, guarded_local_fit = true)")
end

struct _SourceFixtureLogDensity
    design::FacetDesign
    blueprint::NamedTuple
    prior::_SourceFixturePrior
end

struct _GMFRMPromotionCandidateLogDensity
    design::FacetDesign
    blueprint::NamedTuple
    prior::_SourceFixturePrior
end

struct _MGMFRMGuardedLocalFitLogDensity
    design::FacetDesign
    blueprint::NamedTuple
    prior::_SourceFixturePrior
end

function _source_fixture_blueprint(design::FacetDesign)
    design.spec.family === :gmfrm &&
        return _gmfrm_source_unconstrained_blueprint(design)
    design.spec.family === :mgmfrm &&
        return _mgmfrm_source_unconstrained_blueprint(design)
    throw(ArgumentError("_source_fixture_logdensity is only for specified-only GMFRM/MGMFRM preview designs"))
end

function _source_fixture_logdensity(design::FacetDesign;
        prior::_SourceFixturePrior = _SourceFixturePrior())
    blueprint = _source_fixture_blueprint(design)
    return _SourceFixtureLogDensity(design, blueprint, prior)
end

function _source_fixture_logdensity(spec::FacetSpec;
        prior::_SourceFixturePrior = _SourceFixturePrior())
    return _source_fixture_logdensity(getdesign(spec; preview = true); prior)
end

function Base.show(io::IO, target::_SourceFixtureLogDensity)
    print(io, "SourceFixtureLogDensity(",
        target.blueprint.family, ", ",
        target.blueprint.n_parameters, " raw parameter(s), fixture_only = true)")
end

function Base.show(io::IO, target::_GMFRMPromotionCandidateLogDensity)
    print(io, "GMFRMPromotionCandidateLogDensity(",
        target.blueprint.n_parameters,
        " raw parameter(s), public_fit = false)")
end

function Base.show(io::IO, target::_MGMFRMGuardedLocalFitLogDensity)
    print(io, "MGMFRMGuardedLocalFitLogDensity(",
        target.blueprint.n_parameters,
        " raw parameter(s), public_fit = false)")
end

function _gmfrm_promotion_candidate_logdensity(design::FacetDesign;
        prior::_SourceFixturePrior = _SourceFixturePrior())
    design.spec.family === :gmfrm &&
        design.spec.estimation_status === :specified_only ||
        throw(ArgumentError("_gmfrm_promotion_candidate_logdensity is only for specified-only GMFRM preview designs"))
    blueprint = _gmfrm_fit_ready_candidate_blueprint(design)
    return _GMFRMPromotionCandidateLogDensity(design, blueprint, prior)
end

function _gmfrm_promotion_candidate_logdensity(spec::FacetSpec;
        prior::_SourceFixturePrior = _SourceFixturePrior())
    return _gmfrm_promotion_candidate_logdensity(getdesign(spec; preview = true); prior)
end

function _mgmfrm_guarded_local_fit_logdensity(design::FacetDesign;
        prior::_SourceFixturePrior = _SourceFixturePrior())
    design.spec.family === :mgmfrm &&
        design.spec.estimation_status === :specified_only ||
        throw(ArgumentError("_mgmfrm_guarded_local_fit_logdensity is only for specified-only MGMFRM preview designs"))
    design.spec.dimensions == 2 ||
        throw(ArgumentError("_mgmfrm_guarded_local_fit_logdensity currently supports only dimensions = 2"))
    design.spec.q_matrix !== nothing ||
        throw(ArgumentError("_mgmfrm_guarded_local_fit_logdensity requires a fixed confirmatory q_matrix"))
    blueprint = _mgmfrm_fit_ready_candidate_blueprint(design)
    return _MGMFRMGuardedLocalFitLogDensity(design, blueprint, prior)
end

function _mgmfrm_guarded_local_fit_logdensity(spec::FacetSpec;
        prior::_SourceFixturePrior = _SourceFixturePrior())
    return _mgmfrm_guarded_local_fit_logdensity(getdesign(spec; preview = true); prior)
end

function _check_source_fixture_raw_vector(target, raw_params::AbstractVector)
    expected = target.blueprint.n_parameters
    length(raw_params) == expected ||
        throw(ArgumentError("raw parameter vector has length $(length(raw_params)); expected $expected"))
    try
        all(isfinite, raw_params) ||
            throw(ArgumentError("raw parameter vector contains non-finite values"))
    catch err
        err isa ArgumentError && rethrow()
        throw(ArgumentError("raw parameter vector contains values that cannot be checked as finite"))
    end
    return nothing
end

function _source_fixture_prior_sd(target, index::Int)
    blocks = target.blueprint.blocks
    haskey(blocks, :person) && _in_range(blocks[:person], index) &&
        return target.prior.person_sd
    (haskey(blocks, :rater) && _in_range(blocks[:rater], index) ||
        haskey(blocks, :rater_free) && _in_range(blocks[:rater_free], index)) &&
        return target.prior.rater_sd
    (haskey(blocks, :item) && _in_range(blocks[:item], index) ||
        haskey(blocks, :item_free) && _in_range(blocks[:item_free], index)) &&
        return target.prior.item_sd
    (haskey(blocks, :log_item_discrimination_free) && _in_range(blocks[:log_item_discrimination_free], index) ||
        haskey(blocks, :log_item_dimension_discrimination) && _in_range(blocks[:log_item_dimension_discrimination], index)) &&
        return target.prior.log_discrimination_sd
    (haskey(blocks, :log_rater_consistency) && _in_range(blocks[:log_rater_consistency], index) ||
        haskey(blocks, :log_rater_consistency_free) && _in_range(blocks[:log_rater_consistency_free], index)) &&
        return target.prior.log_consistency_sd
    (haskey(blocks, :rater_steps) && _in_range(blocks[:rater_steps], index) ||
        haskey(blocks, :item_steps) && _in_range(blocks[:item_steps], index)) &&
        return target.prior.step_sd
    throw(ArgumentError("raw parameter index $index is not covered by any source-fixture prior block"))
end

function _source_fixture_logprior(target, raw_params::AbstractVector)
    _check_source_fixture_raw_vector(target, raw_params)
    lp = _param_zero(raw_params)
    for index in eachindex(raw_params)
        lp += _normal_logpdf(raw_params[index], _source_fixture_prior_sd(target, index))
    end
    return lp
end

function _source_fixture_loglikelihood(target, raw_params::AbstractVector)
    _check_source_fixture_raw_vector(target, raw_params)
    if target.blueprint.family === :gmfrm
        return _gmfrm_source_loglikelihood_from_unconstrained(target.design, raw_params)
    elseif target.blueprint.family === :mgmfrm
        return _mgmfrm_source_loglikelihood_from_unconstrained(target.design, raw_params)
    end
    throw(ArgumentError("unsupported source-fixture family $(target.blueprint.family)"))
end

function _source_fixture_logposterior(target, raw_params::AbstractVector)
    return _source_fixture_loglikelihood(target, raw_params) +
        _source_fixture_logprior(target, raw_params)
end

LogDensityProblems.logdensity(target::_SourceFixtureLogDensity, raw_params) =
    _source_fixture_logposterior(target, raw_params)

LogDensityProblems.logdensity(target::_GMFRMPromotionCandidateLogDensity, raw_params) =
    _source_fixture_logposterior(target, raw_params)

LogDensityProblems.logdensity(target::_MGMFRMGuardedLocalFitLogDensity, raw_params) =
    _source_fixture_logposterior(target, raw_params)

LogDensityProblems.dimension(target::_SourceFixtureLogDensity) =
    target.blueprint.n_parameters

LogDensityProblems.dimension(target::_GMFRMPromotionCandidateLogDensity) =
    target.blueprint.n_parameters

LogDensityProblems.dimension(target::_MGMFRMGuardedLocalFitLogDensity) =
    target.blueprint.n_parameters

LogDensityProblems.capabilities(::Type{_SourceFixtureLogDensity}) =
    LogDensityProblems.LogDensityOrder{0}()

LogDensityProblems.capabilities(::Type{_GMFRMPromotionCandidateLogDensity}) =
    LogDensityProblems.LogDensityOrder{0}()

LogDensityProblems.capabilities(::Type{_MGMFRMGuardedLocalFitLogDensity}) =
    LogDensityProblems.LogDensityOrder{0}()

function _central_difference_logdensity(target, raw_params::Vector{Float64}, index::Int, eps::Float64)
    xp = copy(raw_params)
    xm = copy(raw_params)
    xp[index] += eps
    xm[index] -= eps
    return (LogDensityProblems.logdensity(target, xp) -
        LogDensityProblems.logdensity(target, xm)) / (2eps)
end

function _checked_gradient_coordinates(coords, nparams::Int)
    coords === nothing && return collect(1:nparams)
    checked = Int.(collect(coords))
    all(index -> 1 <= index <= nparams, checked) ||
        throw(ArgumentError("finite_difference_coords must contain indexes in 1:$nparams"))
    return checked
end

function _gmfrm_promotion_candidate_flag(n_failed::Int, finite_logdensity::Bool,
        finite_gradient::Bool)
    finite_logdensity || return :nonfinite_logdensity
    finite_gradient || return :nonfinite_gradient
    n_failed == 0 || return :gradient_mismatch
    return :ok
end

function _gmfrm_promotion_candidate_diagnostics(
        target::_GMFRMPromotionCandidateLogDensity,
        raw_params::AbstractVector;
        finite_difference_coords = nothing,
        finite_difference_eps::Real = 1e-5,
        gradient_atol::Real = 1e-4,
        gradient_rtol::Real = 1e-4)
    finite_difference_eps > 0 ||
        throw(ArgumentError("finite_difference_eps must be positive"))
    gradient_atol >= 0 ||
        throw(ArgumentError("gradient_atol must be non-negative"))
    gradient_rtol >= 0 ||
        throw(ArgumentError("gradient_rtol must be non-negative"))
    _check_source_fixture_raw_vector(target, raw_params)
    raw = Float64.(collect(raw_params))
    nparams = LogDensityProblems.dimension(target)
    coords = _checked_gradient_coordinates(finite_difference_coords, nparams)
    logdensity = LogDensityProblems.logdensity(target, raw)
    gradient = ForwardDiff.gradient(x -> LogDensityProblems.logdensity(target, x), raw)
    finite_gradient = all(isfinite, gradient)
    rows = NamedTuple[]
    for index in coords
        finite_difference = _central_difference_logdensity(
            target,
            raw,
            index,
            Float64(finite_difference_eps),
        )
        automatic = gradient[index]
        scale = max(abs(automatic), abs(finite_difference), 1.0)
        abs_error = abs(automatic - finite_difference)
        tolerance = Float64(gradient_atol) + Float64(gradient_rtol) * scale
        push!(rows, (;
            index,
            parameter = target.blueprint.parameter_names[index],
            automatic,
            finite_difference,
            abs_error,
            tolerance,
            passed = isfinite(automatic) && isfinite(finite_difference) && abs_error <= tolerance,
        ))
    end
    n_failed = count(row -> !row.passed, rows)
    flag = _gmfrm_promotion_candidate_flag(n_failed, isfinite(logdensity), finite_gradient)
    return (;
        schema = "bayesianmgmfrm.gmfrm_promotion_candidate_diagnostics.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_source_aligned,
        status = :internal_promotion_candidate,
        public_fit = false,
        fit_ready = false,
        target = :_gmfrm_promotion_candidate_logdensity,
        n_raw_parameters = nparams,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        logdensity,
        gradient = copy(gradient),
        finite_difference_rows = rows,
        summary = (;
            flag,
            passed = flag === :ok,
            n_checked = length(rows),
            n_failed,
            finite_logdensity = isfinite(logdensity),
            finite_gradient,
            max_abs_error = isempty(rows) ? missing : maximum(row.abs_error for row in rows),
            max_tolerance = isempty(rows) ? missing : maximum(row.tolerance for row in rows),
        ),
    )
end

function _gmfrm_promotion_candidate_diagnostics(
        design::FacetDesign,
        raw_params::AbstractVector;
        prior::_SourceFixturePrior = _SourceFixturePrior(),
        kwargs...)
    target = _gmfrm_promotion_candidate_logdensity(design; prior)
    return _gmfrm_promotion_candidate_diagnostics(target, raw_params; kwargs...)
end

function _gmfrm_promotion_candidate_diagnostics(
        spec::FacetSpec,
        raw_params::AbstractVector;
        prior::_SourceFixturePrior = _SourceFixturePrior(),
        kwargs...)
    target = _gmfrm_promotion_candidate_logdensity(spec; prior)
    return _gmfrm_promotion_candidate_diagnostics(target, raw_params; kwargs...)
end

function _candidate_block_value_rows(blocks::Dict{Symbol,UnitRange{Int}},
        parameter_names::Vector{String},
        values::AbstractVector)
    rows = NamedTuple[]
    for block in sort(collect(keys(blocks)); by = string)
        range = blocks[block]
        indices = collect(range)
        push!(rows, (;
            block,
            first_parameter = isempty(indices) ? missing : first(indices),
            last_parameter = isempty(indices) ? missing : last(indices),
            n_parameters = length(indices),
            parameter_names = isempty(indices) ? String[] : copy(parameter_names[indices]),
            values = isempty(indices) ? Float64[] : Float64.(values[indices]),
        ))
    end
    return rows
end

function _gmfrm_direct_constraint_rows(design::FacetDesign, direct_params::AbstractVector)
    data = design.spec.data
    item_values = direct_params[design.blocks[:item]]
    item_discrimination_values = direct_params[design.blocks[:item_discrimination]]
    rater_consistency_values = direct_params[design.blocks[:rater_consistency]]
    rater_step_values = direct_params[design.blocks[:rater_steps]]
    rows = [
        (constraint = :item_sum_to_zero, block = :item,
            value = Float64(sum(item_values)), target = 0.0,
            tolerance = 1e-8, passed = abs(sum(item_values)) <= 1e-8),
        (constraint = :item_discrimination_positive, block = :item_discrimination,
            value = Float64(minimum(item_discrimination_values)), target = 0.0,
            tolerance = 0.0, passed = all(>(0), item_discrimination_values)),
        (constraint = :item_discrimination_product_one, block = :item_discrimination,
            value = Float64(prod(item_discrimination_values)), target = 1.0,
            tolerance = 1e-8, passed = abs(prod(item_discrimination_values) - 1) <= 1e-8),
        (constraint = :rater_consistency_positive, block = :rater_consistency,
            value = Float64(minimum(rater_consistency_values)), target = 0.0,
            tolerance = 0.0, passed = all(>(0), rater_consistency_values)),
    ]
    if length(data.category_levels) >= 3 && !isempty(rater_step_values)
        free_steps = max(length(data.category_levels) - 2, 0)
        for rater_index in eachindex(data.rater_levels)
            step_sum = sum(rater_step_values[((rater_index - 1) * free_steps + 1):(rater_index * free_steps)];
                init = _param_zero(direct_params))
            push!(rows, (constraint = :rater_step_last_derived_sum_to_zero,
                block = :rater_steps,
                value = Float64(step_sum + (-step_sum)),
                target = 0.0,
                tolerance = 1e-8,
                passed = true))
        end
    end
    return rows
end

function _gmfrm_promotion_candidate_pointwise_fixture(
        design::FacetDesign,
        direct_params::AbstractVector)
    _check_gmfrm_source_fixture_design(design, "_gmfrm_promotion_candidate_pointwise_fixture")
    _check_parameter_vector_length(design, direct_params)
    _gmfrm_source_fixture_constraints(design, direct_params)
    direct = Float64.(collect(direct_params))
    rows = _gmfrm_source_fixture_values(design, direct)
    pointwise = [Float64(row.log_probability) for row in rows if row.observed]
    constraint_rows = _gmfrm_direct_constraint_rows(design, direct)
    n_failed_constraints = count(row -> !row.passed, constraint_rows)
    loglikelihood = sum(pointwise; init = 0.0)
    passed = length(pointwise) == design.spec.data.n && n_failed_constraints == 0 &&
        all(isfinite, pointwise)
    return (;
        schema = "bayesianmgmfrm.gmfrm_promotion_candidate_pointwise_fixture.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_source_aligned,
        status = :internal_promotion_candidate,
        public_fit = false,
        fit_ready = false,
        density_space = :constrained_direct,
        parameter_layout = fit_ready_parameter_layout(design),
        parameter_names = copy(design.parameter_names),
        parameter_values = copy(direct),
        blocks = _candidate_block_value_rows(design.blocks, design.parameter_names, direct),
        constraint_rows,
        rows,
        pointwise_loglikelihood = pointwise,
        loglikelihood,
        summary = (;
            flag = passed ? :ok : :pointwise_fixture_mismatch,
            passed,
            n_parameters = length(direct),
            n_observations = design.spec.data.n,
            n_categories = length(design.spec.data.category_levels),
            n_rows = length(rows),
            n_pointwise = length(pointwise),
            n_constraints = length(constraint_rows),
            n_failed_constraints,
            loglikelihood,
        ),
    )
end

function _gmfrm_promotion_candidate_pointwise_fixture(
        spec::FacetSpec,
        direct_params::AbstractVector)
    return _gmfrm_promotion_candidate_pointwise_fixture(
        getdesign(spec; preview = true),
        direct_params,
    )
end

function _gmfrm_promotion_candidate_pointwise_fixture(
        target::_GMFRMPromotionCandidateLogDensity,
        raw_params::AbstractVector)
    _check_source_fixture_raw_vector(target, raw_params)
    raw = Float64.(collect(raw_params))
    direct = _gmfrm_source_constrained_params_from_unconstrained(target.design, raw)
    direct_fixture = _gmfrm_promotion_candidate_pointwise_fixture(target.design, direct)
    return merge(direct_fixture, (;
        raw_parameter_names = copy(target.blueprint.parameter_names),
        raw_parameter_values = copy(raw),
        raw_blocks = _candidate_block_value_rows(
            target.blueprint.blocks,
            target.blueprint.parameter_names,
            raw,
        ),
    ))
end

function _gmfrm_promotion_candidate_transform_diagnostics(
        target::_GMFRMPromotionCandidateLogDensity,
        raw_params::AbstractVector)
    _check_source_fixture_raw_vector(target, raw_params)
    raw = Float64.(collect(raw_params))
    direct_params = _gmfrm_source_constrained_params_from_unconstrained(target.design, raw)
    raw_pointwise =
        _gmfrm_source_pointwise_loglikelihood_from_unconstrained(target.design, raw)
    direct_pointwise =
        _gmfrm_source_pointwise_loglikelihood(target.design, direct_params)
    pointwise_abs_error = abs.(raw_pointwise .- direct_pointwise)
    max_pointwise_abs_error = isempty(pointwise_abs_error) ? 0.0 : maximum(pointwise_abs_error)
    constraint_rows = _gmfrm_direct_constraint_rows(target.design, direct_params)
    n_failed_constraints = count(row -> !row.passed, constraint_rows)
    passed = max_pointwise_abs_error <= 1e-10 && n_failed_constraints == 0
    return (;
        schema = "bayesianmgmfrm.gmfrm_promotion_candidate_transform_diagnostics.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_source_aligned,
        status = :internal_promotion_candidate,
        public_fit = false,
        fit_ready = false,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        raw_parameter_values = copy(raw),
        direct_parameter_names = copy(target.blueprint.constrained_parameter_names),
        direct_parameter_values = copy(direct_params),
        raw_blocks = _candidate_block_value_rows(
            target.blueprint.blocks,
            target.blueprint.parameter_names,
            raw,
        ),
        direct_blocks = _candidate_block_value_rows(
            target.blueprint.constrained_blocks,
            target.blueprint.constrained_parameter_names,
            direct_params,
        ),
        constraint_rows,
        raw_pointwise_loglikelihood = copy(raw_pointwise),
        direct_pointwise_loglikelihood = copy(direct_pointwise),
        summary = (;
            flag = passed ? :ok : :transform_mismatch,
            passed,
            n_raw_parameters = target.blueprint.n_parameters,
            n_direct_parameters = length(direct_params),
            n_constraints = length(constraint_rows),
            n_failed_constraints,
            max_pointwise_abs_error,
        ),
    )
end

function _gmfrm_promotion_candidate_transform_diagnostics(
        design::FacetDesign,
        raw_params::AbstractVector;
        prior::_SourceFixturePrior = _SourceFixturePrior())
    target = _gmfrm_promotion_candidate_logdensity(design; prior)
    return _gmfrm_promotion_candidate_transform_diagnostics(target, raw_params)
end

function _gmfrm_promotion_candidate_transform_diagnostics(
        spec::FacetSpec,
        raw_params::AbstractVector;
        prior::_SourceFixturePrior = _SourceFixturePrior())
    target = _gmfrm_promotion_candidate_logdensity(spec; prior)
    return _gmfrm_promotion_candidate_transform_diagnostics(target, raw_params)
end

"""
    initial_params(design_or_spec_or_target; value = 0.0)

Return a deterministic finite initial parameter vector in the same ordering as
`getdesign(...).parameter_names`. The helper is intentionally simple so external
samplers can start from a known point while model-specific initialization
heuristics are developed.
"""
function initial_params(design::FacetDesign; value::Real = 0.0)
    isfinite(value) || throw(ArgumentError("value must be finite"))
    return fill(Float64(value), length(design.parameter_names))
end

initial_params(spec::FacetSpec; value::Real = 0.0) =
    initial_params(getdesign(spec); value)

initial_params(target::MFRMLogDensity; value::Real = 0.0) =
    initial_params(target.design; value)

function initial_params(target::_SourceFixtureLogDensity; value::Real = 0.0)
    isfinite(value) || throw(ArgumentError("value must be finite"))
    return fill(Float64(value), LogDensityProblems.dimension(target))
end

function initial_params(target::_GMFRMPromotionCandidateLogDensity; value::Real = 0.0)
    isfinite(value) || throw(ArgumentError("value must be finite"))
    return fill(Float64(value), LogDensityProblems.dimension(target))
end

function initial_params(target::_MGMFRMGuardedLocalFitLogDensity; value::Real = 0.0)
    isfinite(value) || throw(ArgumentError("value must be finite"))
    return fill(Float64(value), LogDensityProblems.dimension(target))
end

function _fit_initial_params(design::FacetDesign, init)
    nparams = length(design.parameter_names)
    if init === nothing
        return zeros(Float64, nparams)
    end
    length(init) == nparams ||
        throw(ArgumentError("init has length $(length(init)); expected $nparams"))
    out = Float64.(collect(init))
    all(isfinite, out) || throw(ArgumentError("init contains non-finite values"))
    return out
end

function _fit_rng(rng::AbstractRNG, seed)
    if seed === nothing
        return rng, (;
            algorithm = Symbol(nameof(typeof(rng))),
            seed = missing,
            replayable = false,
        )
    end
    seed isa Integer ||
        throw(ArgumentError("seed must be an integer or nothing"))
    seed_value = try
        Int(seed)
    catch
        throw(ArgumentError("seed must fit in Int"))
    end
    seeded_rng = MersenneTwister(seed_value)
    return seeded_rng, (;
        algorithm = :MersenneTwister,
        seed = seed_value,
        replayable = true,
    )
end

"""
    fit(spec_or_design; prior = MFRMPrior(), backend = :julia, ndraws = 1000,
        warmup = 1000, chains = 1, step_size = 0.05, init = nothing,
        rng = Random.default_rng(), seed = nothing, target_accept = 0.8,
        max_depth = 10, max_energy_error = 1000.0, metric = :diagonal,
        ad_backend = :ForwardDiff, init_jitter = 0.0, progress = false)
    fit(spec; experimental = true, backend = :advancedhmc, ...)

Fit the current minimal Bayesian MFRM/RSM/PCM scaffold with the selected
backend. `backend = :julia` uses a random-walk Metropolis kernel,
`backend = :advancedhmc` uses AdvancedHMC/NUTS directly, and
`backend = :turing` wraps the same `MFRMLogDensity` target in a Turing/NUTS
model. Supplying `seed` uses a local `MersenneTwister(seed)` and records the
seed in `sampler_controls`; otherwise the supplied `rng` is used without a
replayable seed record.

The AdvancedHMC backend accepts `ad_backend = :ForwardDiff` by default.
`ad_backend = :ReverseDiff` can be used when the corresponding AD package is
available in the active environment, and `ad_backend = :analytic` uses a
target-provided `LogDensityProblems.logdensity_and_gradient` method when one
exists. The Turing backend currently accepts `ad_backend = :ForwardDiff`;
analytic target gradients are not consumed by Turing's model trace, and the
ReverseDiff path is left to a future adapter after the Turing AD interface can
support this wrapped target reliably.

The `experimental = true` keyword is intentionally narrow. It is accepted for
the scalar source-aligned GMFRM promotion candidate with `family = :gmfrm`,
`dimensions = 1`, and `discrimination = :rater`, returning [`GMFRMFit`](@ref),
and for the fixed-Q two-dimensional confirmatory MGMFRM candidate with
`family = :mgmfrm`, `dimensions = 2`, and a fixed `q_matrix`, returning
[`MGMFRMFit`](@ref). Multidimensional GMFRM, exploratory MGMFRM loadings,
free latent correlations, non-rater GMFRM discrimination, dimensions beyond
two for MGMFRM, and public `MFRMPrior` priors for generalized raw-coordinate
fits are rejected on those guarded paths.
"""
function fit(design::FacetDesign;
        prior::MFRMPrior = MFRMPrior(),
        backend::Symbol = :julia,
        ndraws::Int = 1000,
        warmup::Int = 1000,
        chains::Int = 1,
        step_size::Real = 0.05,
        init = nothing,
        rng::AbstractRNG = Random.default_rng(),
        seed = nothing,
        target_accept::Real = 0.8,
        max_depth::Int = 10,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        progress::Bool = false)
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    warmup >= 0 || throw(ArgumentError("warmup must be non-negative"))
    chains >= 1 || throw(ArgumentError("chains must be positive"))
    isfinite(step_size) && step_size > 0 ||
        throw(ArgumentError("step_size must be finite and positive"))
    initial = _fit_initial_params(design, init)
    fit_rng, rng_control = _fit_rng(rng, seed)

    if backend === :julia
        return _fit_random_walk(design, prior, ndraws, warmup, chains,
            Float64(step_size), initial, fit_rng, rng_control)
    elseif backend === :advancedhmc
        return _fit_advancedhmc(design, prior, ndraws, warmup, chains,
            Float64(step_size), initial, fit_rng, rng_control;
            target_accept,
            max_depth,
            max_energy_error,
            metric,
            ad_backend,
            init_jitter,
            progress)
    elseif backend === :turing
        return _fit_turing(design, prior, ndraws, warmup, chains,
            Float64(step_size), initial, fit_rng, rng_control;
            target_accept,
            max_depth,
            max_energy_error,
            metric,
            ad_backend,
            init_jitter,
            progress)
    else
        throw(ArgumentError("backend must be :julia, :advancedhmc, or :turing"))
    end
end

function _random_walk_stat_row(;
        chain::Int,
        iteration::Int,
        accepted::Bool,
        step_size::Float64,
        log_density::Float64)
    return (;
        chain,
        iteration,
        is_adapt = false,
        is_accept = accepted,
        acceptance_rate = accepted ? 1.0 : 0.0,
        log_density,
        hamiltonian_energy = missing,
        hamiltonian_energy_error = missing,
        max_hamiltonian_energy_error = missing,
        n_steps = missing,
        tree_depth = missing,
        numerical_error = false,
        step_size,
        nom_step_size = step_size,
    )
end

function _fit_random_walk(design::FacetDesign,
        prior::MFRMPrior,
        ndraws::Int,
        warmup::Int,
        chains::Int,
        step::Float64,
        initial::Vector{Float64},
        rng::AbstractRNG,
        rng_control::NamedTuple)
    nparams = length(design.parameter_names)
    total_draws = ndraws * chains
    draws = Matrix{Float64}(undef, total_draws, nparams)
    logps = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    chain_acceptance = Vector{Float64}(undef, chains)
    sampler_stats = NamedTuple[]
    total = warmup + ndraws
    total_accepted = 0

    for chain in 1:chains
        current = copy(initial)
        current_lp = logposterior(design, current, prior)
        isfinite(current_lp) || throw(ArgumentError("initial parameter vector has non-finite log posterior"))
        proposal = similar(current)
        accepted = 0
        for iter in 1:total
            @inbounds for j in 1:nparams
                proposal[j] = current[j] + step * randn(rng)
            end
            proposal_lp = logposterior(design, proposal, prior)
            is_accepted = false
            if log(rand(rng)) < proposal_lp - current_lp
                current .= proposal
                current_lp = proposal_lp
                accepted += 1
                is_accepted = true
            end
            if iter > warmup
                iteration = iter - warmup
                row = (chain - 1) * ndraws + iteration
                draws[row, :] .= current
                logps[row] = current_lp
                chain_ids[row] = chain
                iterations[row] = iteration
                push!(sampler_stats, _random_walk_stat_row(;
                    chain,
                    iteration,
                    accepted = is_accepted,
                    step_size = step,
                    log_density = current_lp))
            end
        end
        chain_acceptance[chain] = accepted / total
        total_accepted += accepted
    end

    return MFRMFit(design, prior, draws, logps, total_accepted / (total * chains),
        chain_ids, iterations, chain_acceptance, :julia, :random_walk_metropolis,
        warmup, step, sampler_stats, (;
            ndraws,
            warmup,
            chains,
            step_size = step,
            rng = rng_control,
            init_jitter = 0.0,
        ))
end

function _advancedhmc_metric(metric::Symbol, nparams::Int)
    metric === :diagonal && return AdvancedHMC.DiagEuclideanMetric(nparams)
    metric === :unit && return AdvancedHMC.UnitEuclideanMetric(nparams)
    metric === :dense && return AdvancedHMC.DenseEuclideanMetric(nparams)
    throw(ArgumentError("metric must be :diagonal, :unit, or :dense"))
end

function _advancedhmc_initial(initial::Vector{Float64},
        rng::AbstractRNG,
        init_jitter::Float64)
    init_jitter == 0.0 && return copy(initial)
    out = copy(initial)
    for index in eachindex(out)
        out[index] += init_jitter * randn(rng)
    end
    return out
end

function _advancedhmc_stat_row(stat::NamedTuple, chain::Int, iteration::Int)
    getstat(name, default) = hasproperty(stat, name) ? getproperty(stat, name) : default
    return (;
        chain,
        iteration,
        is_adapt = Bool(getstat(:is_adapt, false)),
        is_accept = Bool(getstat(:is_accept, true)),
        acceptance_rate = Float64(getstat(:acceptance_rate, NaN)),
        log_density = Float64(getstat(:log_density, getstat(:logjoint, NaN))),
        hamiltonian_energy = Float64(getstat(:hamiltonian_energy, NaN)),
        hamiltonian_energy_error = Float64(getstat(:hamiltonian_energy_error, NaN)),
        max_hamiltonian_energy_error = Float64(getstat(:max_hamiltonian_energy_error, NaN)),
        n_steps = Int(getstat(:n_steps, 0)),
        tree_depth = Int(getstat(:tree_depth, 0)),
        numerical_error = Bool(getstat(:numerical_error, false)),
        step_size = Float64(getstat(:step_size, NaN)),
        nom_step_size = Float64(getstat(:nom_step_size, NaN)),
    )
end

Turing.@model function _turing_mfrm_logdensity_model(target::MFRMLogDensity,
        nparams::Int)
    params ~ Turing.filldist(Turing.Flat(), nparams)
    Turing.@addlogprob! LogDensityProblems.logdensity(target, params)
    return params
end

function _turing_metric_type(metric::Symbol)
    metric === :diagonal && return AdvancedHMC.DiagEuclideanMetric
    metric === :unit && return AdvancedHMC.UnitEuclideanMetric
    metric === :dense && return AdvancedHMC.DenseEuclideanMetric
    throw(ArgumentError("metric must be :diagonal, :unit, or :dense"))
end

function _turing_adtype(ad_backend::Symbol)
    ad_backend === :ForwardDiff && return Turing.AutoForwardDiff()
    ad_backend === :ReverseDiff &&
        throw(ArgumentError("ad_backend = :ReverseDiff is not supported for backend = :turing"))
    ad_backend === :analytic &&
        throw(ArgumentError("ad_backend = :analytic is not supported for backend = :turing"))
    throw(ArgumentError("ad_backend must be :ForwardDiff for backend = :turing"))
end

function _turing_params(transition, nparams::Int)
    values = getproperty(transition, :params)[Turing.@varname(params)]
    length(values) == nparams ||
        throw(ArgumentError("Turing returned $(length(values)) parameter(s); expected $nparams"))
    return values
end

_turing_discard_initial(warmup::Int) = warmup == 0 ? 1 : warmup

function _fit_turing(design::FacetDesign,
        prior::MFRMPrior,
        ndraws::Int,
        warmup::Int,
        chains::Int,
        step::Float64,
        initial::Vector{Float64},
        rng::AbstractRNG,
        rng_control::NamedTuple;
        target_accept::Real,
        max_depth::Int,
        max_energy_error::Real,
        metric::Symbol,
        ad_backend::Symbol,
        init_jitter::Real,
        progress::Bool)
    0 < target_accept < 1 ||
        throw(ArgumentError("target_accept must be in (0, 1)"))
    max_depth >= 1 || throw(ArgumentError("max_depth must be positive"))
    isfinite(max_energy_error) && max_energy_error > 0 ||
        throw(ArgumentError("max_energy_error must be finite and positive"))
    isfinite(init_jitter) && init_jitter >= 0 ||
        throw(ArgumentError("init_jitter must be finite and non-negative"))

    nparams = length(design.parameter_names)
    nparams >= 1 || throw(ArgumentError("at least one parameter is required for Turing fitting"))
    adtype = _turing_adtype(ad_backend)
    metric_type = _turing_metric_type(metric)
    total_draws = ndraws * chains
    draws = Matrix{Float64}(undef, total_draws, nparams)
    logps = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    chain_acceptance = Vector{Float64}(undef, chains)
    sampler_stats = NamedTuple[]
    target = MFRMLogDensity(design; prior)
    model = _turing_mfrm_logdensity_model(target, nparams)
    sampler = Turing.NUTS(-1, Float64(target_accept), max_depth,
        Float64(max_energy_error), step, metric_type; adtype)
    discard_initial = _turing_discard_initial(warmup)
    controls = (;
        ndraws,
        warmup,
        chains,
        step_size = step,
        target_accept = Float64(target_accept),
        max_depth,
        max_energy_error = Float64(max_energy_error),
        metric,
        ad_backend,
        gradient_backend = :ad,
        rng = rng_control,
        init_jitter = Float64(init_jitter),
        turing_model = :mfrm_logdensity_flat_parameter_model,
        chain_type = :raw_transitions,
        discard_initial,
    )

    for chain in 1:chains
        chain_initial = _advancedhmc_initial(initial, rng, Float64(init_jitter))
        current_lp = logposterior(design, chain_initial, prior)
        isfinite(current_lp) || throw(ArgumentError("initial parameter vector has non-finite log posterior"))
        transitions = Turing.sample(
            rng,
            model,
            sampler,
            ndraws;
            num_warmup = warmup,
            discard_initial,
            progress,
            verbose = false,
            initial_params = Turing.InitFromParams((params = copy(chain_initial),)),
            chain_type = Any,
        )
        length(transitions) == ndraws ||
            throw(ArgumentError("Turing returned $(length(transitions)) draw(s); expected $ndraws"))
        chain_stats = NamedTuple[]
        for iteration in 1:ndraws
            row = (chain - 1) * ndraws + iteration
            values = _turing_params(transitions[iteration], nparams)
            draws[row, :] .= values
            stat_row = _advancedhmc_stat_row(transitions[iteration].stats, chain, iteration)
            logps[row] = stat_row.log_density
            chain_ids[row] = chain
            iterations[row] = iteration
            push!(chain_stats, stat_row)
            push!(sampler_stats, stat_row)
        end
        chain_acceptance[chain] = _stat_mean(chain_stats, :acceptance_rate)
    end

    return MFRMFit(design, prior, draws, logps, _column_mean(chain_acceptance),
        chain_ids, iterations, chain_acceptance, :turing, :nuts, warmup,
        _stat_mean(sampler_stats, :step_size), sampler_stats, controls)
end

function _stat_mean(rows, field::Symbol)
    values = Float64[]
    for row in rows
        value = getproperty(row, field)
        ismissing(value) && continue
        isfinite(value) && push!(values, Float64(value))
    end
    isempty(values) && return NaN
    return _column_mean(values)
end

function _fit_advancedhmc(design::FacetDesign,
        prior::MFRMPrior,
        ndraws::Int,
        warmup::Int,
        chains::Int,
        step::Float64,
        initial::Vector{Float64},
        rng::AbstractRNG,
        rng_control::NamedTuple;
        target_accept::Real,
        max_depth::Int,
        max_energy_error::Real,
        metric::Symbol,
        ad_backend::Symbol,
        init_jitter::Real,
        progress::Bool)
    0 < target_accept < 1 ||
        throw(ArgumentError("target_accept must be in (0, 1)"))
    max_depth >= 1 || throw(ArgumentError("max_depth must be positive"))
    isfinite(max_energy_error) && max_energy_error > 0 ||
        throw(ArgumentError("max_energy_error must be finite and positive"))
    isfinite(init_jitter) && init_jitter >= 0 ||
        throw(ArgumentError("init_jitter must be finite and non-negative"))
    gradient_backend = _gradient_backend_kind(ad_backend)

    nparams = length(design.parameter_names)
    nparams >= 1 || throw(ArgumentError("at least one parameter is required for AdvancedHMC fitting"))
    total_draws = ndraws * chains
    draws = Matrix{Float64}(undef, total_draws, nparams)
    logps = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    chain_acceptance = Vector{Float64}(undef, chains)
    sampler_stats = NamedTuple[]
    target = MFRMLogDensity(design; prior)
    controls = (;
        ndraws,
        warmup,
        chains,
        step_size = step,
        target_accept = Float64(target_accept),
        max_depth,
        max_energy_error = Float64(max_energy_error),
        metric,
        ad_backend,
        gradient_backend,
        rng = rng_control,
        init_jitter = Float64(init_jitter),
    )

    for chain in 1:chains
        chain_initial = _advancedhmc_initial(initial, rng, Float64(init_jitter))
        current_lp = logposterior(design, chain_initial, prior)
        isfinite(current_lp) || throw(ArgumentError("initial parameter vector has non-finite log posterior"))
        gradient_target = _logdensity_gradient_target(target, chain_initial, ad_backend).target
        metric_object = _advancedhmc_metric(metric, nparams)
        hamiltonian = AdvancedHMC.Hamiltonian(
            metric_object,
            x -> LogDensityProblems.logdensity(gradient_target, x),
            x -> LogDensityProblems.logdensity_and_gradient(gradient_target, x),
        )
        integrator = AdvancedHMC.Leapfrog(step)
        kernel = AdvancedHMC.HMCKernel(AdvancedHMC.Trajectory{AdvancedHMC.MultinomialTS}(
            integrator,
            AdvancedHMC.GeneralisedNoUTurn(max_depth, Float64(max_energy_error)),
        ))
        adaptor = warmup > 0 ?
            AdvancedHMC.StanHMCAdaptor(
                AdvancedHMC.MassMatrixAdaptor(metric_object),
                AdvancedHMC.StepSizeAdaptor(Float64(target_accept), integrator),
            ) :
            AdvancedHMC.NoAdaptation()
        samples, stats = AdvancedHMC.sample(
            rng,
            hamiltonian,
            kernel,
            chain_initial,
            warmup + ndraws,
            adaptor,
            warmup;
            drop_warmup = warmup > 0,
            verbose = false,
            progress,
        )
        length(samples) == ndraws ||
            throw(ArgumentError("AdvancedHMC returned $(length(samples)) draw(s); expected $ndraws"))
        chain_stats = NamedTuple[]
        for iteration in 1:ndraws
            row = (chain - 1) * ndraws + iteration
            draws[row, :] .= samples[iteration]
            stat_row = _advancedhmc_stat_row(stats[iteration], chain, iteration)
            logps[row] = stat_row.log_density
            chain_ids[row] = chain
            iterations[row] = iteration
            push!(chain_stats, stat_row)
            push!(sampler_stats, stat_row)
        end
        chain_acceptance[chain] = _stat_mean(chain_stats, :acceptance_rate)
    end

    return MFRMFit(design, prior, draws, logps, _column_mean(chain_acceptance),
        chain_ids, iterations, chain_acceptance, :advancedhmc, :nuts, warmup,
        _stat_mean(sampler_stats, :step_size), sampler_stats, controls)
end

function _fit_draws_per_chain(fit::MFRMFit)
    nchains = length(fit.chain_acceptance_rate)
    nchains >= 1 || throw(ArgumentError("fit has no chain metadata"))
    total = size(fit.draws, 1)
    total == length(fit.chain_ids) == length(fit.iterations) == length(fit.log_posterior) ||
        throw(ArgumentError("fit draw metadata length does not match draws"))
    total % nchains == 0 ||
        throw(ArgumentError("fit has uneven chain draw counts"))
    draws_per_chain = div(total, nchains)
    for chain in 1:nchains
        rows = ((chain - 1) * draws_per_chain + 1):(chain * draws_per_chain)
        all(==(chain), @view fit.chain_ids[rows]) ||
            throw(ArgumentError("fit draws are not grouped by chain"))
        all(fit.iterations[row] == row - first(rows) + 1 for row in rows) ||
            throw(ArgumentError("fit iterations are not consecutive within chain"))
    end
    return draws_per_chain
end

function _fit_draws_per_chain(fit::GMFRMFit)
    nchains = length(fit.chain_acceptance_rate)
    nchains >= 1 || throw(ArgumentError("fit has no chain metadata"))
    total = size(fit.draws, 1)
    total == length(fit.chain_ids) == length(fit.iterations) == length(fit.log_posterior) ||
        throw(ArgumentError("fit draw metadata length does not match draws"))
    total % nchains == 0 ||
        throw(ArgumentError("fit has uneven chain draw counts"))
    draws_per_chain = div(total, nchains)
    for chain in 1:nchains
        rows = ((chain - 1) * draws_per_chain + 1):(chain * draws_per_chain)
        all(==(chain), @view fit.chain_ids[rows]) ||
            throw(ArgumentError("fit draws are not grouped by chain"))
        all(fit.iterations[row] == row - first(rows) + 1 for row in rows) ||
            throw(ArgumentError("fit iterations are not consecutive within chain"))
    end
    return draws_per_chain
end

function _fit_draws_per_chain(fit::MGMFRMFit)
    nchains = length(fit.chain_acceptance_rate)
    nchains >= 1 || throw(ArgumentError("fit has no chain metadata"))
    total = size(fit.draws, 1)
    total == length(fit.chain_ids) == length(fit.iterations) == length(fit.log_posterior) ||
        throw(ArgumentError("fit draw metadata length does not match draws"))
    total % nchains == 0 ||
        throw(ArgumentError("fit has uneven chain draw counts"))
    draws_per_chain = div(total, nchains)
    for chain in 1:nchains
        rows = ((chain - 1) * draws_per_chain + 1):(chain * draws_per_chain)
        all(==(chain), @view fit.chain_ids[rows]) ||
            throw(ArgumentError("fit draws are not grouped by chain"))
        all(fit.iterations[row] == row - first(rows) + 1 for row in rows) ||
            throw(ArgumentError("fit iterations are not consecutive within chain"))
    end
    return draws_per_chain
end

function _chain_draw_array(fit::MFRMFit)
    draws_per_chain = _fit_draws_per_chain(fit)
    nchains = length(fit.chain_acceptance_rate)
    nparams = size(fit.draws, 2)
    out = Array{Float64}(undef, draws_per_chain, nchains, nparams)
    for chain in 1:nchains
        rows = ((chain - 1) * draws_per_chain + 1):(chain * draws_per_chain)
        for param in 1:nparams
            out[:, chain, param] .= fit.draws[rows, param]
        end
    end
    return out
end

function _split_chain_array(values::Array{Float64,3})
    niterations, nchains, nparams = size(values)
    if niterations < 4
        return values
    end
    half = div(niterations, 2)
    out = Array{Float64}(undef, half, 2 * nchains, nparams)
    for chain in 1:nchains
        out[:, 2 * chain - 1, :] .= values[1:half, chain, :]
        out[:, 2 * chain, :] .= values[(niterations - half + 1):niterations, chain, :]
    end
    return out
end

function _chain_variance(values::AbstractVector{<:Real})
    n = length(values)
    n <= 1 && return NaN
    mean_value = _column_mean(values)
    ss = 0.0
    for value in values
        d = Float64(value) - mean_value
        ss += d * d
    end
    return ss / (n - 1)
end

function _rhat_and_ess(values::Array{Float64,3}, param::Int)
    niterations, nchains, _ = size(values)
    total_draws = niterations * nchains
    if nchains < 2 || niterations < 2
        return (rhat = NaN, ess = NaN, flag = :insufficient_chains)
    end

    chain_means = Vector{Float64}(undef, nchains)
    chain_vars = Vector{Float64}(undef, nchains)
    for chain in 1:nchains
        vals = @view values[:, chain, param]
        chain_means[chain] = _column_mean(vals)
        chain_vars[chain] = _chain_variance(vals)
    end
    W = _column_mean(chain_vars)
    B = niterations * _chain_variance(chain_means)
    if !(isfinite(W) && isfinite(B)) || W < 0 || B < 0
        return (rhat = NaN, ess = NaN, flag = :degenerate_draws)
    end
    if W == 0
        rhat = B == 0 ? 1.0 : Inf
        ess = B == 0 ? Float64(total_draws) : NaN
        flag = isfinite(rhat) ? :ok : :degenerate_draws
        return (rhat = rhat, ess = ess, flag = flag)
    end

    var_plus = ((niterations - 1) / niterations) * W + B / niterations
    rhat = sqrt(max(var_plus / W, 0.0))
    autocorrelations = Float64[]
    max_lag = niterations - 1
    for lag in 1:max_lag
        autocov = 0.0
        for chain in 1:nchains
            mean_value = chain_means[chain]
            s = 0.0
            for iteration in 1:(niterations - lag)
                s += (values[iteration, chain, param] - mean_value) *
                    (values[iteration + lag, chain, param] - mean_value)
            end
            autocov += s / (niterations - 1)
        end
        push!(autocorrelations, autocov / (nchains * W))
    end
    positive_sum = 0.0
    lag = 1
    while lag <= length(autocorrelations)
        if lag == length(autocorrelations)
            autocorrelations[lag] > 0 && (positive_sum += autocorrelations[lag])
            break
        end
        pair_sum = autocorrelations[lag] + autocorrelations[lag + 1]
        pair_sum > 0 || break
        positive_sum += pair_sum
        lag += 2
    end
    tau = max(1.0, 1 + 2 * positive_sum)
    ess = clamp(total_draws / tau, 1.0, Float64(total_draws))
    flag = isfinite(rhat) && isfinite(ess) ? :ok : :degenerate_draws
    return (rhat = rhat, ess = ess, flag = flag)
end

function _draw_matrix_to_chain_array(draws::AbstractMatrix{<:Real}, chains::Int)
    chains >= 1 || throw(ArgumentError("chains must be positive"))
    total_draws, nparams = size(draws)
    total_draws % chains == 0 ||
        throw(ArgumentError("draw matrix has uneven chain draw counts"))
    draws_per_chain = div(total_draws, chains)
    out = Array{Float64}(undef, draws_per_chain, chains, nparams)
    for chain in 1:chains
        rows = ((chain - 1) * draws_per_chain + 1):(chain * draws_per_chain)
        for param in 1:nparams
            out[:, chain, param] .= Float64.(@view draws[rows, param])
        end
    end
    return out
end

function _candidate_mcmc_diagnostic_rows(draws::AbstractMatrix{<:Real},
        parameter_names::Vector{String},
        chains::Int;
        split_chains::Bool,
        rhat_threshold::Float64,
        ess_threshold::Float64)
    values = _draw_matrix_to_chain_array(draws, chains)
    original_iterations, original_chains, nparams = size(values)
    length(parameter_names) == nparams ||
        throw(ArgumentError("parameter name count does not match draw columns"))
    diagnostic_values = split_chains && original_chains >= 2 ?
        _split_chain_array(values) :
        values
    diagnostic_iterations, diagnostic_chains, _ = size(diagnostic_values)
    actual_split = split_chains && original_chains >= 2 && original_iterations >= 4
    rows = NamedTuple[]
    for param in 1:nparams
        diagnostic = _rhat_and_ess(diagnostic_values, param)
        push!(rows, (;
            parameter = parameter_names[param],
            rhat = diagnostic.rhat,
            ess = diagnostic.ess,
            n_chains = original_chains,
            draws_per_chain = original_iterations,
            diagnostic_chains,
            diagnostic_draws_per_chain = diagnostic_iterations,
            total_draws = size(draws, 1),
            split_chains = actual_split,
            flag = _mcmc_parameter_flag(
                diagnostic,
                rhat_threshold,
                ess_threshold,
            ),
        ))
    end
    return rows
end

function _candidate_parameter_block_diagnostics(blocks::Dict{Symbol,UnitRange{Int}},
        parameter_names::Vector{String},
        parameter_rows;
        chains::Int,
        draws_per_chain::Int,
        total_draws::Int,
        split_chains::Bool,
        rhat_threshold::Float64,
        ess_threshold::Float64)
    row_by_name = Dict(row.parameter => row for row in parameter_rows)
    rows = NamedTuple[]
    for block in sort(collect(keys(blocks)); by = string)
        range = blocks[block]
        indices = collect(range)
        names = isempty(indices) ? String[] : copy(parameter_names[indices])
        block_rows = [row_by_name[name] for name in names]
        n_parameters = length(names)
        n_insufficient = count(row -> row.flag === :insufficient_chains, block_rows)
        n_degenerate = count(row -> row.flag === :degenerate_draws, block_rows)
        n_bad_rhat = count(row -> isfinite(row.rhat) && row.rhat > rhat_threshold, block_rows)
        n_low_ess = count(row -> isfinite(row.ess) && row.ess < ess_threshold, block_rows)
        push!(rows, (;
            block,
            first_parameter = isempty(indices) ? missing : first(indices),
            last_parameter = isempty(indices) ? missing : last(indices),
            n_parameters,
            parameter_names = names,
            n_chains = chains,
            draws_per_chain,
            total_draws,
            split_chains,
            rhat_threshold,
            ess_threshold,
            max_rhat = n_parameters == 0 ? missing :
                _finite_extreme((row.rhat for row in block_rows), maximum),
            min_ess = n_parameters == 0 ? missing :
                _finite_extreme((row.ess for row in block_rows), minimum),
            n_bad_rhat,
            n_low_ess,
            n_insufficient_chains = n_insufficient,
            n_degenerate_parameters = n_degenerate,
            flag = _parameter_block_flag(
                n_parameters,
                n_insufficient,
                n_degenerate,
                n_bad_rhat,
                n_low_ess,
            ),
        ))
    end
    return rows
end

function _candidate_chain_sampler_summary(rows, max_depth::Int)
    return (;
        n_divergences = _maybe_count(rows, row -> row.numerical_error),
        n_max_treedepth =
            _maybe_count(rows, row -> !ismissing(row.tree_depth) && row.tree_depth >= max_depth),
        mean_n_steps = _maybe_mean(rows, :n_steps),
        mean_tree_depth = _maybe_mean(rows, :tree_depth),
        max_tree_depth = _maybe_max_int(rows, :tree_depth),
        mean_step_size = _maybe_mean(rows, :step_size),
        e_bfmi = _ebfmi((row.hamiltonian_energy for row in rows)),
    )
end

function _gmfrm_candidate_direct_draw_values(
        target::_GMFRMPromotionCandidateLogDensity,
        raw_draws::AbstractMatrix{<:Real})
    n_draws = size(raw_draws, 1)
    n_direct = length(target.blueprint.constrained_parameter_names)
    n_observations = target.design.spec.data.n
    direct_draws = Matrix{Float64}(undef, n_draws, n_direct)
    pointwise = Matrix{Float64}(undef, n_draws, n_observations)
    loglikelihood = Vector{Float64}(undef, n_draws)
    for draw in 1:n_draws
        raw = collect(@view raw_draws[draw, :])
        direct = _gmfrm_source_constrained_params_from_unconstrained(target.design, raw)
        direct_pointwise = _gmfrm_source_pointwise_loglikelihood(target.design, direct)
        direct_draws[draw, :] .= direct
        pointwise[draw, :] .= direct_pointwise
        loglikelihood[draw] = sum(direct_pointwise; init = 0.0)
    end
    return (;
        direct_draws,
        pointwise_loglikelihood = pointwise,
        loglikelihood,
    )
end

function _gmfrm_candidate_direct_draw_constraint_rows(
        design::FacetDesign,
        direct_draws::AbstractMatrix{<:Real})
    n_draws = size(direct_draws, 1)
    n_draws == 0 && return NamedTuple[]
    template = _gmfrm_direct_constraint_rows(design, @view direct_draws[1, :])
    values = [Float64[] for _ in template]
    n_failed = zeros(Int, length(template))
    for draw in 1:n_draws
        rows = _gmfrm_direct_constraint_rows(design, @view direct_draws[draw, :])
        length(rows) == length(template) ||
            throw(ArgumentError("direct constraint row count changed across draws"))
        for index in eachindex(rows)
            rows[index].constraint === template[index].constraint &&
                rows[index].block === template[index].block ||
                throw(ArgumentError("direct constraint row identity changed across draws"))
            push!(values[index], Float64(rows[index].value))
            rows[index].passed || (n_failed[index] += 1)
        end
    end
    rows = NamedTuple[]
    for index in eachindex(template)
        row_values = values[index]
        target = Float64(template[index].target)
        push!(rows, (;
            constraint_index = index,
            constraint = template[index].constraint,
            block = template[index].block,
            target,
            tolerance = Float64(template[index].tolerance),
            n_draws,
            n_failed = n_failed[index],
            minimum_value = minimum(row_values),
            maximum_value = maximum(row_values),
            max_abs_target_error =
                maximum(abs(value - target) for value in row_values),
            passed = n_failed[index] == 0,
        ))
    end
    return rows
end

function _mgmfrm_direct_constraint_rows(design::FacetDesign, direct_params::AbstractVector)
    data = design.spec.data
    rater_values = direct_params[design.blocks[:rater]]
    item_dimension_discrimination_values =
        direct_params[design.blocks[:item_dimension_discrimination]]
    rater_consistency_values = direct_params[design.blocks[:rater_consistency]]
    item_step_values = direct_params[design.blocks[:item_steps]]
    rows = [
        (constraint = :rater_sum_to_zero, block = :rater,
            value = Float64(sum(rater_values)), target = 0.0,
            tolerance = 1e-8, passed = abs(sum(rater_values)) <= 1e-8),
        (constraint = :item_dimension_discrimination_positive,
            block = :item_dimension_discrimination,
            value = Float64(minimum(item_dimension_discrimination_values)),
            target = 0.0,
            tolerance = 0.0,
            passed = all(>(0), item_dimension_discrimination_values)),
        (constraint = :rater_consistency_positive, block = :rater_consistency,
            value = Float64(minimum(rater_consistency_values)), target = 0.0,
            tolerance = 0.0, passed = all(>(0), rater_consistency_values)),
        (constraint = :rater_consistency_product_one, block = :rater_consistency,
            value = Float64(prod(rater_consistency_values)), target = 1.0,
            tolerance = 1e-8,
            passed = abs(prod(rater_consistency_values) - 1) <= 1e-8),
    ]
    if length(data.category_levels) >= 3 && !isempty(item_step_values)
        free_steps = max(length(data.category_levels) - 2, 0)
        for item_index in eachindex(data.item_levels)
            step_sum = sum(item_step_values[((item_index - 1) * free_steps + 1):(item_index * free_steps)];
                init = _param_zero(direct_params))
            push!(rows, (constraint = :item_step_last_derived_sum_to_zero,
                block = :item_steps,
                value = Float64(step_sum + (-step_sum)),
                target = 0.0,
                tolerance = 1e-8,
                passed = true))
        end
    end
    return rows
end

function _mgmfrm_confirmatory_candidate_pointwise_fixture(
        design::FacetDesign,
        direct_params::AbstractVector)
    _check_mgmfrm_source_fixture_design(design, "_mgmfrm_confirmatory_candidate_pointwise_fixture")
    design.spec.dimensions == 2 ||
        throw(ArgumentError("_mgmfrm_confirmatory_candidate_pointwise_fixture currently supports dimensions = 2"))
    _check_parameter_vector_length(design, direct_params)
    _mgmfrm_source_fixture_constraints(design, direct_params)
    direct = Float64.(collect(direct_params))
    rows = _mgmfrm_source_fixture_values(design, direct)
    pointwise = [Float64(row.log_probability) for row in rows if row.observed]
    constraint_rows = _mgmfrm_direct_constraint_rows(design, direct)
    n_failed_constraints = count(row -> !row.passed, constraint_rows)
    loglikelihood = sum(pointwise; init = 0.0)
    passed = length(pointwise) == design.spec.data.n && n_failed_constraints == 0 &&
        all(isfinite, pointwise)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_confirmatory_candidate_pointwise_fixture.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :internal_fit_ready_candidate,
        public_fit = false,
        fit_ready = false,
        density_space = :constrained_direct,
        q_matrix = _q_matrix_manifest(design.spec.q_matrix),
        latent_correlation = :identity_fixed,
        ability_scale = :standard_normal_by_dimension,
        parameter_layout = fit_ready_parameter_layout(design),
        parameter_names = copy(design.parameter_names),
        parameter_values = copy(direct),
        blocks = _candidate_block_value_rows(design.blocks, design.parameter_names, direct),
        constraint_rows,
        rows,
        pointwise_loglikelihood = pointwise,
        loglikelihood,
        summary = (;
            flag = passed ? :ok : :pointwise_fixture_mismatch,
            passed,
            n_parameters = length(direct),
            n_observations = design.spec.data.n,
            n_categories = length(design.spec.data.category_levels),
            n_rows = length(rows),
            n_pointwise = length(pointwise),
            n_constraints = length(constraint_rows),
            n_failed_constraints,
            loglikelihood,
        ),
    )
end

function _mgmfrm_confirmatory_candidate_pointwise_fixture(
        spec::FacetSpec,
        direct_params::AbstractVector)
    return _mgmfrm_confirmatory_candidate_pointwise_fixture(
        getdesign(spec; preview = true),
        direct_params,
    )
end

function _mgmfrm_confirmatory_candidate_pointwise_fixture(
        target::_MGMFRMGuardedLocalFitLogDensity,
        raw_params::AbstractVector)
    _check_source_fixture_raw_vector(target, raw_params)
    raw = Float64.(collect(raw_params))
    direct = _mgmfrm_source_constrained_params_from_unconstrained(target.design, raw)
    direct_fixture = _mgmfrm_confirmatory_candidate_pointwise_fixture(target.design, direct)
    return merge(direct_fixture, (;
        raw_parameter_names = copy(target.blueprint.parameter_names),
        raw_parameter_values = copy(raw),
        raw_blocks = _candidate_block_value_rows(
            target.blueprint.blocks,
            target.blueprint.parameter_names,
            raw,
        ),
    ))
end

function _mgmfrm_guarded_local_fit_direct_draw_values(
        target::_MGMFRMGuardedLocalFitLogDensity,
        raw_draws::AbstractMatrix{<:Real})
    n_draws = size(raw_draws, 1)
    n_direct = length(target.blueprint.constrained_parameter_names)
    n_observations = target.design.spec.data.n
    direct_draws = Matrix{Float64}(undef, n_draws, n_direct)
    pointwise = Matrix{Float64}(undef, n_draws, n_observations)
    loglikelihood = Vector{Float64}(undef, n_draws)
    for draw in 1:n_draws
        raw = collect(@view raw_draws[draw, :])
        direct = _mgmfrm_source_constrained_params_from_unconstrained(target.design, raw)
        direct_pointwise = _mgmfrm_source_pointwise_loglikelihood(target.design, direct)
        direct_draws[draw, :] .= direct
        pointwise[draw, :] .= direct_pointwise
        loglikelihood[draw] = sum(direct_pointwise; init = 0.0)
    end
    return (;
        direct_draws,
        pointwise_loglikelihood = pointwise,
        loglikelihood,
    )
end

function _mgmfrm_guarded_local_fit_direct_draw_constraint_rows(
        design::FacetDesign,
        direct_draws::AbstractMatrix{<:Real})
    n_draws = size(direct_draws, 1)
    n_draws == 0 && return NamedTuple[]
    template = _mgmfrm_direct_constraint_rows(design, @view direct_draws[1, :])
    values = [Float64[] for _ in template]
    n_failed = zeros(Int, length(template))
    for draw in 1:n_draws
        rows = _mgmfrm_direct_constraint_rows(design, @view direct_draws[draw, :])
        length(rows) == length(template) ||
            throw(ArgumentError("MGMFRM direct constraint row count changed across draws"))
        for index in eachindex(rows)
            rows[index].constraint === template[index].constraint &&
                rows[index].block === template[index].block ||
                throw(ArgumentError("MGMFRM direct constraint row identity changed across draws"))
            push!(values[index], Float64(rows[index].value))
            rows[index].passed || (n_failed[index] += 1)
        end
    end
    rows = NamedTuple[]
    for index in eachindex(template)
        row_values = values[index]
        target = Float64(template[index].target)
        push!(rows, (;
            constraint_index = index,
            constraint = template[index].constraint,
            block = template[index].block,
            target,
            tolerance = Float64(template[index].tolerance),
            n_draws,
            n_failed = n_failed[index],
            minimum_value = minimum(row_values),
            maximum_value = maximum(row_values),
            max_abs_target_error =
                maximum(abs(value - target) for value in row_values),
            passed = n_failed[index] == 0,
        ))
    end
    return rows
end

function _gmfrm_promotion_candidate_summary_flag(n_sampler_warnings::Int,
        n_nonfinite_logdensity::Int,
        n_failed_direct_constraints::Int,
        n_nonfinite_direct_loglikelihood::Int,
        n_insufficient::Int,
        n_degenerate::Int,
        n_bad_rhat::Int,
        n_low_ess::Int)
    (n_failed_direct_constraints > 0 || n_nonfinite_direct_loglikelihood > 0) &&
        return :direct_transform_warning
    (n_sampler_warnings > 0 || n_nonfinite_logdensity > 0) &&
        return :sampler_warning
    n_insufficient > 0 && return :insufficient_chains
    (n_degenerate > 0 || n_bad_rhat > 0 || n_low_ess > 0) &&
        return :mcmc_warning
    return :ok
end

function _gmfrm_promotion_candidate_sampler_diagnostics(
        target::_GMFRMPromotionCandidateLogDensity,
        raw_initial::AbstractVector = initial_params(target);
        ndraws::Int = 100,
        warmup::Int = 100,
        chains::Int = 2,
        step_size::Real = 0.03,
        rng::AbstractRNG = Random.default_rng(),
        seed = nothing,
        target_accept::Real = 0.8,
        max_depth::Int = 10,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400,
        progress::Bool = false)
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    warmup >= 0 || throw(ArgumentError("warmup must be non-negative"))
    chains >= 1 || throw(ArgumentError("chains must be positive"))
    isfinite(step_size) && step_size > 0 ||
        throw(ArgumentError("step_size must be finite and positive"))
    0 < target_accept < 1 ||
        throw(ArgumentError("target_accept must be in (0, 1)"))
    max_depth >= 1 || throw(ArgumentError("max_depth must be positive"))
    isfinite(max_energy_error) && max_energy_error > 0 ||
        throw(ArgumentError("max_energy_error must be finite and positive"))
    isfinite(init_jitter) && init_jitter >= 0 ||
        throw(ArgumentError("init_jitter must be finite and non-negative"))
    gradient_backend = _gradient_backend_kind(ad_backend)
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    _check_source_fixture_raw_vector(target, raw_initial)

    nparams = LogDensityProblems.dimension(target)
    nparams >= 1 || throw(ArgumentError("at least one parameter is required for AdvancedHMC diagnostics"))
    initial = Float64.(collect(raw_initial))
    initial_logdensity = LogDensityProblems.logdensity(target, initial)
    isfinite(initial_logdensity) ||
        throw(ArgumentError("initial raw parameter vector has non-finite log density"))
    fit_rng, rng_control = _fit_rng(rng, seed)
    total_draws = ndraws * chains
    draws = Matrix{Float64}(undef, total_draws, nparams)
    logdensities = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    chain_acceptance = Vector{Float64}(undef, chains)
    sampler_stats = NamedTuple[]
    controls = (;
        ndraws,
        warmup,
        chains,
        step_size = Float64(step_size),
        target_accept = Float64(target_accept),
        max_depth,
        max_energy_error = Float64(max_energy_error),
        metric,
        ad_backend,
        gradient_backend,
        rng = rng_control,
        init_jitter = Float64(init_jitter),
    )

    for chain in 1:chains
        chain_initial = _advancedhmc_initial(initial, fit_rng, Float64(init_jitter))
        chain_logdensity = LogDensityProblems.logdensity(target, chain_initial)
        isfinite(chain_logdensity) ||
            throw(ArgumentError("chain $chain initial raw parameter vector has non-finite log density"))
        gradient_target = _logdensity_gradient_target(target, chain_initial, ad_backend).target
        metric_object = _advancedhmc_metric(metric, nparams)
        hamiltonian = AdvancedHMC.Hamiltonian(
            metric_object,
            x -> LogDensityProblems.logdensity(gradient_target, x),
            x -> LogDensityProblems.logdensity_and_gradient(gradient_target, x),
        )
        integrator = AdvancedHMC.Leapfrog(Float64(step_size))
        kernel = AdvancedHMC.HMCKernel(AdvancedHMC.Trajectory{AdvancedHMC.MultinomialTS}(
            integrator,
            AdvancedHMC.GeneralisedNoUTurn(max_depth, Float64(max_energy_error)),
        ))
        adaptor = warmup > 0 ?
            AdvancedHMC.StanHMCAdaptor(
                AdvancedHMC.MassMatrixAdaptor(metric_object),
                AdvancedHMC.StepSizeAdaptor(Float64(target_accept), integrator),
            ) :
            AdvancedHMC.NoAdaptation()
        samples, stats = AdvancedHMC.sample(
            fit_rng,
            hamiltonian,
            kernel,
            chain_initial,
            warmup + ndraws,
            adaptor,
            warmup;
            drop_warmup = warmup > 0,
            verbose = false,
            progress,
        )
        length(samples) == ndraws ||
            throw(ArgumentError("AdvancedHMC returned $(length(samples)) draw(s); expected $ndraws"))
        chain_stats = NamedTuple[]
        for iteration in 1:ndraws
            row = (chain - 1) * ndraws + iteration
            draws[row, :] .= samples[iteration]
            stat_row = _advancedhmc_stat_row(stats[iteration], chain, iteration)
            logdensities[row] = stat_row.log_density
            chain_ids[row] = chain
            iterations[row] = iteration
            push!(chain_stats, stat_row)
            push!(sampler_stats, stat_row)
        end
        chain_acceptance[chain] = _stat_mean(chain_stats, :acceptance_rate)
    end

    sampler_rows = NamedTuple[]
    for chain in 1:chains
        draw_rows = ((chain - 1) * ndraws + 1):(chain * ndraws)
        logps = @view logdensities[draw_rows]
        logdensity_summary = _finite_log_posterior_summary(logps)
        n_finite = count(isfinite, logps)
        n_nonfinite = length(logps) - n_finite
        chain_stats = [row for row in sampler_stats if row.chain == chain]
        sampler_summary = _candidate_chain_sampler_summary(chain_stats, max_depth)
        push!(sampler_rows, (;
            chain,
            backend = :advancedhmc,
            sampler = :nuts,
            n_draws = ndraws,
            warmup,
            step_size = Float64(step_size),
            first_iteration = first(@view iterations[draw_rows]),
            last_iteration = last(@view iterations[draw_rows]),
            acceptance_rate = chain_acceptance[chain],
            mean_logdensity = logdensity_summary.mean,
            minimum_logdensity = logdensity_summary.minimum,
            maximum_logdensity = logdensity_summary.maximum,
            n_finite_logdensity = n_finite,
            n_nonfinite_logdensity = n_nonfinite,
            n_divergences = sampler_summary.n_divergences,
            n_max_treedepth = sampler_summary.n_max_treedepth,
            mean_n_steps = sampler_summary.mean_n_steps,
            mean_tree_depth = sampler_summary.mean_tree_depth,
            max_tree_depth = sampler_summary.max_tree_depth,
            mean_step_size = sampler_summary.mean_step_size,
            e_bfmi = sampler_summary.e_bfmi,
            flag = _sampler_diagnostic_flag(chain_acceptance[chain],
                n_nonfinite,
                sampler_summary.n_divergences,
                sampler_summary.n_max_treedepth),
        ))
    end

    actual_split = split_chains && chains >= 2 && ndraws >= 4
    parameter_rows = _candidate_mcmc_diagnostic_rows(
        draws,
        target.blueprint.parameter_names,
        chains;
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold,
    )
    block_rows = _candidate_parameter_block_diagnostics(
        target.blueprint.blocks,
        target.blueprint.parameter_names,
        parameter_rows;
        chains,
        draws_per_chain = ndraws,
        total_draws,
        split_chains = actual_split,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold,
    )
    direct_values = _gmfrm_candidate_direct_draw_values(target, draws)
    direct_constraint_rows =
        _gmfrm_candidate_direct_draw_constraint_rows(target.design, direct_values.direct_draws)
    direct_parameter_rows = _candidate_mcmc_diagnostic_rows(
        direct_values.direct_draws,
        target.blueprint.constrained_parameter_names,
        chains;
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold,
    )
    direct_block_rows = _candidate_parameter_block_diagnostics(
        target.blueprint.constrained_blocks,
        target.blueprint.constrained_parameter_names,
        direct_parameter_rows;
        chains,
        draws_per_chain = ndraws,
        total_draws,
        split_chains = actual_split,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold,
    )

    n_sampler_warnings = count(row -> row.flag !== :ok, sampler_rows)
    n_block_warnings = count(row -> row.flag in (:insufficient_chains, :degenerate_draws, :mcmc_warning), block_rows)
    n_direct_block_warnings = count(row -> row.flag in (:insufficient_chains, :degenerate_draws, :mcmc_warning), direct_block_rows)
    n_nonfinite_logdensity = sum(row.n_nonfinite_logdensity for row in sampler_rows)
    n_nonfinite_direct_loglikelihood =
        count(!isfinite, direct_values.loglikelihood) +
        count(!isfinite, direct_values.pointwise_loglikelihood)
    n_failed_direct_constraints = sum(row.n_failed for row in direct_constraint_rows)
    n_divergences = _sum_nonmissing(row.n_divergences for row in sampler_rows)
    n_max_treedepth = _sum_nonmissing(row.n_max_treedepth for row in sampler_rows)
    e_bfmi = _min_nonmissing(row.e_bfmi for row in sampler_rows)
    n_insufficient = count(row -> row.flag === :insufficient_chains, parameter_rows)
    n_degenerate = count(row -> row.flag === :degenerate_draws, parameter_rows)
    n_bad_rhat = count(row -> isfinite(row.rhat) && row.rhat > checked.rhat_threshold, parameter_rows)
    n_low_ess = count(row -> isfinite(row.ess) && row.ess < checked.ess_threshold, parameter_rows)
    max_rhat = _finite_extreme((row.rhat for row in parameter_rows), maximum)
    min_ess = _finite_extreme((row.ess for row in parameter_rows), minimum)
    flag = _gmfrm_promotion_candidate_summary_flag(
        n_sampler_warnings,
        n_nonfinite_logdensity,
        n_failed_direct_constraints,
        n_nonfinite_direct_loglikelihood,
        n_insufficient,
        n_degenerate,
        n_bad_rhat,
        n_low_ess,
    )
    initial_direct = _gmfrm_source_constrained_params_from_unconstrained(target.design, initial)

    return (;
        schema = "bayesianmgmfrm.gmfrm_promotion_candidate_sampler_diagnostics.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_source_aligned,
        status = :internal_promotion_candidate,
        public_fit = false,
        fit_ready = false,
        target = :_gmfrm_promotion_candidate_logdensity,
        density_space = :raw_unconstrained,
        backend = :advancedhmc,
        sampler = :nuts,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        raw_blocks = _candidate_block_value_rows(
            target.blueprint.blocks,
            target.blueprint.parameter_names,
            initial,
        ),
        direct_parameter_names = copy(target.blueprint.constrained_parameter_names),
        direct_blocks = _candidate_block_value_rows(
            target.blueprint.constrained_blocks,
            target.blueprint.constrained_parameter_names,
            initial_direct,
        ),
        initial_raw_parameter_values = copy(initial),
        initial_direct_parameter_values = copy(initial_direct),
        initial_logdensity,
        draws,
        logdensity = logdensities,
        direct_draws = direct_values.direct_draws,
        direct_pointwise_loglikelihood = direct_values.pointwise_loglikelihood,
        direct_loglikelihood = direct_values.loglikelihood,
        chain_ids,
        iterations,
        chain_acceptance_rate = chain_acceptance,
        sampler_controls = controls,
        sampler_stats,
        sampler_rows,
        parameter_rows,
        block_rows,
        direct_constraint_rows,
        direct_parameter_rows,
        direct_block_rows,
        summary = (;
            flag,
            passed = flag === :ok,
            n_chains = chains,
            draws_per_chain = ndraws,
            total_draws,
            n_parameters = nparams,
            n_direct_parameters = size(direct_values.direct_draws, 2),
            split_chains = actual_split,
            rhat_threshold = checked.rhat_threshold,
            ess_threshold = checked.ess_threshold,
            max_rhat,
            min_ess,
            n_bad_rhat,
            n_low_ess,
            n_insufficient_chains = n_insufficient,
            n_degenerate_parameters = n_degenerate,
            n_block_warnings,
            n_direct_block_warnings,
            n_sampler_warnings,
            n_nonfinite_logdensity,
            n_nonfinite_direct_loglikelihood,
            n_direct_constraints = length(direct_constraint_rows),
            n_failed_direct_constraints,
            n_divergences,
            n_max_treedepth,
            e_bfmi,
        ),
    )
end

function _gmfrm_promotion_candidate_sampler_diagnostics(
        design::FacetDesign,
        raw_initial::AbstractVector = initial_params(_gmfrm_promotion_candidate_logdensity(design));
        prior::_SourceFixturePrior = _SourceFixturePrior(),
        kwargs...)
    target = _gmfrm_promotion_candidate_logdensity(design; prior)
    return _gmfrm_promotion_candidate_sampler_diagnostics(target, raw_initial; kwargs...)
end

function _gmfrm_promotion_candidate_sampler_diagnostics(
        spec::FacetSpec,
        raw_initial::AbstractVector = initial_params(_gmfrm_promotion_candidate_logdensity(spec));
        prior::_SourceFixturePrior = _SourceFixturePrior(),
        kwargs...)
    target = _gmfrm_promotion_candidate_logdensity(spec; prior)
    return _gmfrm_promotion_candidate_sampler_diagnostics(target, raw_initial; kwargs...)
end

function _mgmfrm_guarded_local_fit_sampler_diagnostics(
        target::_MGMFRMGuardedLocalFitLogDensity,
        raw_initial::AbstractVector = initial_params(target);
        ndraws::Int = 100,
        warmup::Int = 100,
        chains::Int = 2,
        step_size::Real = 0.03,
        rng::AbstractRNG = Random.default_rng(),
        seed = nothing,
        target_accept::Real = 0.8,
        max_depth::Int = 10,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400,
        progress::Bool = false)
    target.blueprint.family === :mgmfrm ||
        throw(ArgumentError("_mgmfrm_guarded_local_fit_sampler_diagnostics requires an MGMFRM guarded target"))
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    warmup >= 0 || throw(ArgumentError("warmup must be non-negative"))
    chains >= 1 || throw(ArgumentError("chains must be positive"))
    isfinite(step_size) && step_size > 0 ||
        throw(ArgumentError("step_size must be finite and positive"))
    0 < target_accept < 1 ||
        throw(ArgumentError("target_accept must be in (0, 1)"))
    max_depth >= 1 || throw(ArgumentError("max_depth must be positive"))
    isfinite(max_energy_error) && max_energy_error > 0 ||
        throw(ArgumentError("max_energy_error must be finite and positive"))
    isfinite(init_jitter) && init_jitter >= 0 ||
        throw(ArgumentError("init_jitter must be finite and non-negative"))
    gradient_backend = _gradient_backend_kind(ad_backend)
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    _check_source_fixture_raw_vector(target, raw_initial)

    nparams = LogDensityProblems.dimension(target)
    nparams >= 1 || throw(ArgumentError("at least one parameter is required for AdvancedHMC diagnostics"))
    initial = Float64.(collect(raw_initial))
    initial_logdensity = LogDensityProblems.logdensity(target, initial)
    isfinite(initial_logdensity) ||
        throw(ArgumentError("initial raw parameter vector has non-finite log density"))
    fit_rng, rng_control = _fit_rng(rng, seed)
    total_draws = ndraws * chains
    draws = Matrix{Float64}(undef, total_draws, nparams)
    logdensities = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    chain_acceptance = Vector{Float64}(undef, chains)
    sampler_stats = NamedTuple[]
    controls = (;
        ndraws,
        warmup,
        chains,
        step_size = Float64(step_size),
        target_accept = Float64(target_accept),
        max_depth,
        max_energy_error = Float64(max_energy_error),
        metric,
        ad_backend,
        gradient_backend,
        rng = rng_control,
        init_jitter = Float64(init_jitter),
    )

    for chain in 1:chains
        chain_initial = _advancedhmc_initial(initial, fit_rng, Float64(init_jitter))
        chain_logdensity = LogDensityProblems.logdensity(target, chain_initial)
        isfinite(chain_logdensity) ||
            throw(ArgumentError("chain $chain initial raw parameter vector has non-finite log density"))
        gradient_target = _logdensity_gradient_target(target, chain_initial, ad_backend).target
        metric_object = _advancedhmc_metric(metric, nparams)
        hamiltonian = AdvancedHMC.Hamiltonian(
            metric_object,
            x -> LogDensityProblems.logdensity(gradient_target, x),
            x -> LogDensityProblems.logdensity_and_gradient(gradient_target, x),
        )
        integrator = AdvancedHMC.Leapfrog(Float64(step_size))
        kernel = AdvancedHMC.HMCKernel(AdvancedHMC.Trajectory{AdvancedHMC.MultinomialTS}(
            integrator,
            AdvancedHMC.GeneralisedNoUTurn(max_depth, Float64(max_energy_error)),
        ))
        adaptor = warmup > 0 ?
            AdvancedHMC.StanHMCAdaptor(
                AdvancedHMC.MassMatrixAdaptor(metric_object),
                AdvancedHMC.StepSizeAdaptor(Float64(target_accept), integrator),
            ) :
            AdvancedHMC.NoAdaptation()
        samples, stats = AdvancedHMC.sample(
            fit_rng,
            hamiltonian,
            kernel,
            chain_initial,
            warmup + ndraws,
            adaptor,
            warmup;
            drop_warmup = warmup > 0,
            verbose = false,
            progress,
        )
        length(samples) == ndraws ||
            throw(ArgumentError("AdvancedHMC returned $(length(samples)) draw(s); expected $ndraws"))
        chain_stats = NamedTuple[]
        for iteration in 1:ndraws
            row = (chain - 1) * ndraws + iteration
            draws[row, :] .= samples[iteration]
            stat_row = _advancedhmc_stat_row(stats[iteration], chain, iteration)
            logdensities[row] = stat_row.log_density
            chain_ids[row] = chain
            iterations[row] = iteration
            push!(chain_stats, stat_row)
            push!(sampler_stats, stat_row)
        end
        chain_acceptance[chain] = _stat_mean(chain_stats, :acceptance_rate)
    end

    sampler_rows = NamedTuple[]
    for chain in 1:chains
        draw_rows = ((chain - 1) * ndraws + 1):(chain * ndraws)
        logps = @view logdensities[draw_rows]
        logdensity_summary = _finite_log_posterior_summary(logps)
        n_finite = count(isfinite, logps)
        n_nonfinite = length(logps) - n_finite
        chain_stats = [row for row in sampler_stats if row.chain == chain]
        sampler_summary = _candidate_chain_sampler_summary(chain_stats, max_depth)
        push!(sampler_rows, (;
            chain,
            backend = :advancedhmc,
            sampler = :nuts,
            n_draws = ndraws,
            warmup,
            step_size = Float64(step_size),
            first_iteration = first(@view iterations[draw_rows]),
            last_iteration = last(@view iterations[draw_rows]),
            acceptance_rate = chain_acceptance[chain],
            mean_logdensity = logdensity_summary.mean,
            minimum_logdensity = logdensity_summary.minimum,
            maximum_logdensity = logdensity_summary.maximum,
            n_finite_logdensity = n_finite,
            n_nonfinite_logdensity = n_nonfinite,
            n_divergences = sampler_summary.n_divergences,
            n_max_treedepth = sampler_summary.n_max_treedepth,
            mean_n_steps = sampler_summary.mean_n_steps,
            mean_tree_depth = sampler_summary.mean_tree_depth,
            max_tree_depth = sampler_summary.max_tree_depth,
            mean_step_size = sampler_summary.mean_step_size,
            e_bfmi = sampler_summary.e_bfmi,
            flag = _sampler_diagnostic_flag(chain_acceptance[chain],
                n_nonfinite,
                sampler_summary.n_divergences,
                sampler_summary.n_max_treedepth),
        ))
    end

    actual_split = split_chains && chains >= 2 && ndraws >= 4
    parameter_rows = _candidate_mcmc_diagnostic_rows(
        draws,
        target.blueprint.parameter_names,
        chains;
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold,
    )
    block_rows = _candidate_parameter_block_diagnostics(
        target.blueprint.blocks,
        target.blueprint.parameter_names,
        parameter_rows;
        chains,
        draws_per_chain = ndraws,
        total_draws,
        split_chains = actual_split,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold,
    )
    direct_values = _mgmfrm_guarded_local_fit_direct_draw_values(target, draws)
    direct_constraint_rows =
        _mgmfrm_guarded_local_fit_direct_draw_constraint_rows(
            target.design,
            direct_values.direct_draws,
        )
    direct_parameter_rows = _candidate_mcmc_diagnostic_rows(
        direct_values.direct_draws,
        target.blueprint.constrained_parameter_names,
        chains;
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold,
    )
    direct_block_rows = _candidate_parameter_block_diagnostics(
        target.blueprint.constrained_blocks,
        target.blueprint.constrained_parameter_names,
        direct_parameter_rows;
        chains,
        draws_per_chain = ndraws,
        total_draws,
        split_chains = actual_split,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold,
    )

    n_sampler_warnings = count(row -> row.flag !== :ok, sampler_rows)
    n_block_warnings = count(row -> row.flag in (:insufficient_chains, :degenerate_draws, :mcmc_warning), block_rows)
    n_direct_block_warnings = count(row -> row.flag in (:insufficient_chains, :degenerate_draws, :mcmc_warning), direct_block_rows)
    n_nonfinite_logdensity = sum(row.n_nonfinite_logdensity for row in sampler_rows)
    n_nonfinite_direct_loglikelihood =
        count(!isfinite, direct_values.loglikelihood) +
        count(!isfinite, direct_values.pointwise_loglikelihood)
    n_failed_direct_constraints = sum(row.n_failed for row in direct_constraint_rows)
    n_divergences = _sum_nonmissing(row.n_divergences for row in sampler_rows)
    n_max_treedepth = _sum_nonmissing(row.n_max_treedepth for row in sampler_rows)
    e_bfmi = _min_nonmissing(row.e_bfmi for row in sampler_rows)
    n_insufficient = count(row -> row.flag === :insufficient_chains, parameter_rows)
    n_degenerate = count(row -> row.flag === :degenerate_draws, parameter_rows)
    n_bad_rhat = count(row -> isfinite(row.rhat) && row.rhat > checked.rhat_threshold, parameter_rows)
    n_low_ess = count(row -> isfinite(row.ess) && row.ess < checked.ess_threshold, parameter_rows)
    max_rhat = _finite_extreme((row.rhat for row in parameter_rows), maximum)
    min_ess = _finite_extreme((row.ess for row in parameter_rows), minimum)
    flag = _gmfrm_promotion_candidate_summary_flag(
        n_sampler_warnings,
        n_nonfinite_logdensity,
        n_failed_direct_constraints,
        n_nonfinite_direct_loglikelihood,
        n_insufficient,
        n_degenerate,
        n_bad_rhat,
        n_low_ess,
    )
    initial_direct = _mgmfrm_source_constrained_params_from_unconstrained(
        target.design,
        initial,
    )

    return (;
        schema = "bayesianmgmfrm.mgmfrm_guarded_local_fit_sampler_diagnostics.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :guarded_local_fit,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        target = :_mgmfrm_guarded_local_fit_logdensity,
        density_space = :raw_unconstrained,
        backend = :advancedhmc,
        sampler = :nuts,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        raw_blocks = _candidate_block_value_rows(
            target.blueprint.blocks,
            target.blueprint.parameter_names,
            initial,
        ),
        direct_parameter_names = copy(target.blueprint.constrained_parameter_names),
        direct_blocks = _candidate_block_value_rows(
            target.blueprint.constrained_blocks,
            target.blueprint.constrained_parameter_names,
            initial_direct,
        ),
        initial_raw_parameter_values = copy(initial),
        initial_direct_parameter_values = copy(initial_direct),
        initial_logdensity,
        draws,
        logdensity = logdensities,
        direct_draws = direct_values.direct_draws,
        direct_pointwise_loglikelihood = direct_values.pointwise_loglikelihood,
        direct_loglikelihood = direct_values.loglikelihood,
        chain_ids,
        iterations,
        chain_acceptance_rate = chain_acceptance,
        sampler_controls = controls,
        sampler_stats,
        sampler_rows,
        parameter_rows,
        block_rows,
        direct_constraint_rows,
        direct_parameter_rows,
        direct_block_rows,
        summary = (;
            flag,
            passed = flag === :ok,
            n_chains = chains,
            draws_per_chain = ndraws,
            total_draws,
            n_parameters = nparams,
            n_direct_parameters = size(direct_values.direct_draws, 2),
            split_chains = actual_split,
            rhat_threshold = checked.rhat_threshold,
            ess_threshold = checked.ess_threshold,
            max_rhat,
            min_ess,
            n_bad_rhat,
            n_low_ess,
            n_insufficient_chains = n_insufficient,
            n_degenerate_parameters = n_degenerate,
            n_block_warnings,
            n_direct_block_warnings,
            n_sampler_warnings,
            n_nonfinite_logdensity,
            n_nonfinite_direct_loglikelihood,
            n_direct_constraints = length(direct_constraint_rows),
            n_failed_direct_constraints,
            n_divergences,
            n_max_treedepth,
            e_bfmi,
        ),
    )
end

function _mgmfrm_guarded_local_fit_sampler_diagnostics(
        design::FacetDesign,
        raw_initial::AbstractVector = initial_params(_mgmfrm_guarded_local_fit_logdensity(design));
        prior::_SourceFixturePrior = _SourceFixturePrior(),
        kwargs...)
    target = _mgmfrm_guarded_local_fit_logdensity(design; prior)
    return _mgmfrm_guarded_local_fit_sampler_diagnostics(target, raw_initial; kwargs...)
end

function _mgmfrm_guarded_local_fit_sampler_diagnostics(
        spec::FacetSpec,
        raw_initial::AbstractVector = initial_params(_mgmfrm_guarded_local_fit_logdensity(spec));
        prior::_SourceFixturePrior = _SourceFixturePrior(),
        kwargs...)
    target = _mgmfrm_guarded_local_fit_logdensity(spec; prior)
    return _mgmfrm_guarded_local_fit_sampler_diagnostics(target, raw_initial; kwargs...)
end

function _experimental_gmfrm_prior(prior)
    prior === nothing && return _SourceFixturePrior()
    prior isa _SourceFixturePrior && return prior
    throw(ArgumentError(
        "experimental scalar GMFRM fitting currently uses the internal " *
        "raw-coordinate prior contract; omit `prior` or pass the internal " *
        "_SourceFixturePrior for local validation",
    ))
end

function _check_experimental_gmfrm_spec(spec::FacetSpec)
    spec.family === :gmfrm ||
        throw(ArgumentError("experimental fitting currently supports only family = :gmfrm"))
    spec.dimensions == 1 ||
        throw(ArgumentError("experimental GMFRM fitting currently supports only dimensions = 1"))
    spec.discrimination === :rater ||
        throw(ArgumentError("experimental GMFRM fitting currently supports only discrimination = :rater"))
    spec.estimation_status === :specified_only ||
        throw(ArgumentError("experimental GMFRM fitting expects the specified-only scalar GMFRM manifest path"))
    return nothing
end

function _experimental_gmfrm_initial(target::_GMFRMPromotionCandidateLogDensity, init)
    init === nothing && return initial_params(target)
    length(init) == LogDensityProblems.dimension(target) ||
        throw(ArgumentError("init has length $(length(init)); expected $(LogDensityProblems.dimension(target))"))
    out = Float64.(collect(init))
    all(isfinite, out) || throw(ArgumentError("init contains non-finite values"))
    return out
end

function _gmfrm_fit_from_sampler_diagnostics(
        design::FacetDesign,
        prior::_SourceFixturePrior,
        diagnostic_surface)
    step = _stat_mean(diagnostic_surface.sampler_stats, :step_size)
    isfinite(step) || (step = Float64(diagnostic_surface.sampler_controls.step_size))
    return GMFRMFit(
        design,
        prior,
        Matrix{Float64}(diagnostic_surface.draws),
        Vector{Float64}(diagnostic_surface.logdensity),
        Matrix{Float64}(diagnostic_surface.direct_draws),
        Vector{Float64}(diagnostic_surface.direct_loglikelihood),
        Matrix{Float64}(diagnostic_surface.direct_pointwise_loglikelihood),
        Vector{Int}(diagnostic_surface.chain_ids),
        Vector{Int}(diagnostic_surface.iterations),
        Vector{Float64}(diagnostic_surface.chain_acceptance_rate),
        diagnostic_surface.backend,
        diagnostic_surface.sampler,
        Int(diagnostic_surface.sampler_controls.warmup),
        step,
        Vector{NamedTuple}(diagnostic_surface.sampler_stats),
        diagnostic_surface.sampler_controls,
        diagnostic_surface,
    )
end

function _fit_experimental_gmfrm(spec::FacetSpec;
        prior = nothing,
        backend::Symbol = :advancedhmc,
        init = nothing,
        kwargs...)
    _check_experimental_gmfrm_spec(spec)
    backend === :advancedhmc ||
        throw(ArgumentError("experimental scalar GMFRM fitting currently supports only backend = :advancedhmc"))
    gmfrm_prior = _experimental_gmfrm_prior(prior)
    design = getdesign(spec; preview = true)
    target = _gmfrm_promotion_candidate_logdensity(design; prior = gmfrm_prior)
    raw_initial = _experimental_gmfrm_initial(target, init)
    diagnostic_surface = _gmfrm_promotion_candidate_sampler_diagnostics(
        target,
        raw_initial;
        kwargs...,
    )
    return _gmfrm_fit_from_sampler_diagnostics(design, gmfrm_prior, diagnostic_surface)
end

function _guarded_mgmfrm_prior(prior)
    prior === nothing && return _SourceFixturePrior()
    prior isa _SourceFixturePrior && return prior
    throw(ArgumentError(
        "guarded local MGMFRM fitting currently uses the internal " *
        "raw-coordinate prior contract; omit `prior` or pass the internal " *
        "_SourceFixturePrior for local validation",
    ))
end

function _check_guarded_mgmfrm_spec(spec::FacetSpec)
    spec.family === :mgmfrm ||
        throw(ArgumentError("guarded local MGMFRM fitting supports only family = :mgmfrm"))
    spec.dimensions == 2 ||
        throw(ArgumentError("guarded local MGMFRM fitting currently supports only dimensions = 2"))
    spec.q_matrix !== nothing ||
        throw(ArgumentError("guarded local MGMFRM fitting requires a fixed confirmatory q_matrix"))
    spec.estimation_status === :specified_only ||
        throw(ArgumentError("guarded local MGMFRM fitting expects the specified-only MGMFRM manifest path"))
    return nothing
end

function _guarded_mgmfrm_initial(target::_MGMFRMGuardedLocalFitLogDensity, init)
    init === nothing && return initial_params(target)
    length(init) == LogDensityProblems.dimension(target) ||
        throw(ArgumentError("init has length $(length(init)); expected $(LogDensityProblems.dimension(target))"))
    out = Float64.(collect(init))
    all(isfinite, out) || throw(ArgumentError("init contains non-finite values"))
    return out
end

function _mgmfrm_fit_from_sampler_diagnostics(
        design::FacetDesign,
        prior::_SourceFixturePrior,
        diagnostic_surface)
    step = _stat_mean(diagnostic_surface.sampler_stats, :step_size)
    isfinite(step) || (step = Float64(diagnostic_surface.sampler_controls.step_size))
    return MGMFRMFit(
        design,
        prior,
        Matrix{Float64}(diagnostic_surface.draws),
        Vector{Float64}(diagnostic_surface.logdensity),
        Matrix{Float64}(diagnostic_surface.direct_draws),
        Vector{Float64}(diagnostic_surface.direct_loglikelihood),
        Matrix{Float64}(diagnostic_surface.direct_pointwise_loglikelihood),
        Vector{Int}(diagnostic_surface.chain_ids),
        Vector{Int}(diagnostic_surface.iterations),
        Vector{Float64}(diagnostic_surface.chain_acceptance_rate),
        diagnostic_surface.backend,
        diagnostic_surface.sampler,
        Int(diagnostic_surface.sampler_controls.warmup),
        step,
        Vector{NamedTuple}(diagnostic_surface.sampler_stats),
        diagnostic_surface.sampler_controls,
        diagnostic_surface,
    )
end

function _fit_guarded_mgmfrm(spec::FacetSpec;
        prior = nothing,
        backend::Symbol = :advancedhmc,
        init = nothing,
        kwargs...)
    _check_guarded_mgmfrm_spec(spec)
    backend === :advancedhmc ||
        throw(ArgumentError("guarded local MGMFRM fitting currently supports only backend = :advancedhmc"))
    mgmfrm_prior = _guarded_mgmfrm_prior(prior)
    design = getdesign(spec; preview = true)
    target = _mgmfrm_guarded_local_fit_logdensity(design; prior = mgmfrm_prior)
    raw_initial = _guarded_mgmfrm_initial(target, init)
    diagnostic_surface = _mgmfrm_guarded_local_fit_sampler_diagnostics(
        target,
        raw_initial;
        kwargs...,
    )
    return _mgmfrm_fit_from_sampler_diagnostics(design, mgmfrm_prior, diagnostic_surface)
end

function _fit_experimental_mgmfrm(spec::FacetSpec; kwargs...)
    return _fit_guarded_mgmfrm(spec; kwargs...)
end

function fit(spec::FacetSpec; experimental::Bool = false, kwargs...)
    if experimental
        spec.family === :gmfrm && return _fit_experimental_gmfrm(spec; kwargs...)
        spec.family === :mgmfrm && return _fit_experimental_mgmfrm(spec; kwargs...)
        throw(ArgumentError(
            "experimental fitting currently supports only family = :gmfrm or :mgmfrm",
        ))
    end
    return fit(getdesign(spec); kwargs...)
end

"""
    fit_metadata(fit::MFRMFit)

Return report-ready metadata for a fitted minimal MFRM object, including data
dimensions, model family, threshold structure, posterior draw dimensions,
backend, sampler, warmup, step size, sampler controls, and prior scales. This
metadata helper does not itself report chain-aware convergence diagnostics; use
`diagnostics`, `sampler_diagnostics`, and `mcmc_diagnostics` for sampler and
R-hat/ESS summaries.
"""
function fit_metadata(fit::MFRMFit)
    data = fit.design.spec.data
    return (;
        n_observations = data.n,
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        n_categories = length(data.category_levels),
        category_levels = copy(data.category_levels),
        optional_facets = sort(collect(keys(data.optional)); by = string),
        family = fit.design.spec.family,
        dimensions = fit.design.spec.dimensions,
        discrimination = fit.design.spec.discrimination,
        thresholds = fit.design.spec.thresholds,
        estimation_status = fit.design.spec.estimation_status,
        n_parameters = length(fit.design.parameter_names),
        n_draws = size(fit.draws, 1),
        n_chains = length(fit.chain_acceptance_rate),
        draws_per_chain = _fit_draws_per_chain(fit),
        n_log_posterior = length(fit.log_posterior),
        backend = fit.backend,
        sampler = fit.sampler,
        warmup = fit.warmup,
        step_size = fit.step_size,
        acceptance_rate = fit.acceptance_rate,
        chain_acceptance_rate = copy(fit.chain_acceptance_rate),
        sampler_controls = fit.sampler_controls,
        n_sampler_stats = length(fit.sampler_stats),
        prior = (;
            person_sd = fit.prior.person_sd,
            rater_sd = fit.prior.rater_sd,
            item_sd = fit.prior.item_sd,
            step_sd = fit.prior.step_sd,
        ),
        data_signature = fit.design.spec.validation.data_signature,
    )
end

function fit_metadata(fit::GMFRMFit)
    data = fit.design.spec.data
    diagnostic = fit.diagnostic_surface
    return (;
        n_observations = data.n,
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        n_categories = length(data.category_levels),
        category_levels = copy(data.category_levels),
        optional_facets = sort(collect(keys(data.optional)); by = string),
        family = fit.design.spec.family,
        dimensions = fit.design.spec.dimensions,
        discrimination = fit.design.spec.discrimination,
        thresholds = fit.design.spec.thresholds,
        estimation_status = fit.design.spec.estimation_status,
        scope = :scalar_gmfrm_fit_ready_candidate,
        public_fit = true,
        experimental_public = true,
        density_space = :raw_unconstrained,
        n_parameters = size(fit.draws, 2),
        n_direct_parameters = size(fit.direct_draws, 2),
        raw_parameter_names = copy(diagnostic.raw_parameter_names),
        direct_parameter_names = copy(diagnostic.direct_parameter_names),
        n_draws = size(fit.draws, 1),
        n_chains = length(fit.chain_acceptance_rate),
        draws_per_chain = _fit_draws_per_chain(fit),
        n_log_posterior = length(fit.log_posterior),
        backend = fit.backend,
        sampler = fit.sampler,
        warmup = fit.warmup,
        step_size = fit.step_size,
        acceptance_rate = _column_mean(fit.chain_acceptance_rate),
        chain_acceptance_rate = copy(fit.chain_acceptance_rate),
        sampler_controls = fit.sampler_controls,
        n_sampler_stats = length(fit.sampler_stats),
        prior = (;
            person_sd = fit.prior.person_sd,
            rater_sd = fit.prior.rater_sd,
            item_sd = fit.prior.item_sd,
            log_discrimination_sd = fit.prior.log_discrimination_sd,
            log_consistency_sd = fit.prior.log_consistency_sd,
            step_sd = fit.prior.step_sd,
        ),
        data_signature = fit.design.spec.validation.data_signature,
    )
end

function fit_metadata(fit::MGMFRMFit)
    data = fit.design.spec.data
    diagnostic = fit.diagnostic_surface
    return (;
        n_observations = data.n,
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        n_categories = length(data.category_levels),
        category_levels = copy(data.category_levels),
        optional_facets = sort(collect(keys(data.optional)); by = string),
        family = fit.design.spec.family,
        dimensions = fit.design.spec.dimensions,
        discrimination = fit.design.spec.discrimination,
        thresholds = fit.design.spec.thresholds,
        estimation_status = fit.design.spec.estimation_status,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        guarded_local_fit = true,
        density_space = :raw_unconstrained,
        n_parameters = size(fit.draws, 2),
        n_direct_parameters = size(fit.direct_draws, 2),
        raw_parameter_names = copy(diagnostic.raw_parameter_names),
        direct_parameter_names = copy(diagnostic.direct_parameter_names),
        n_draws = size(fit.draws, 1),
        n_chains = length(fit.chain_acceptance_rate),
        draws_per_chain = _fit_draws_per_chain(fit),
        n_log_posterior = length(fit.log_posterior),
        backend = fit.backend,
        sampler = fit.sampler,
        warmup = fit.warmup,
        step_size = fit.step_size,
        acceptance_rate = _column_mean(fit.chain_acceptance_rate),
        chain_acceptance_rate = copy(fit.chain_acceptance_rate),
        sampler_controls = fit.sampler_controls,
        n_sampler_stats = length(fit.sampler_stats),
        q_matrix = _q_matrix_manifest(fit.design.spec.q_matrix),
        latent_correlation = :identity_fixed,
        prior = (;
            person_sd = fit.prior.person_sd,
            rater_sd = fit.prior.rater_sd,
            item_sd = fit.prior.item_sd,
            log_discrimination_sd = fit.prior.log_discrimination_sd,
            log_consistency_sd = fit.prior.log_consistency_sd,
            step_sd = fit.prior.step_sd,
        ),
        data_signature = fit.design.spec.validation.data_signature,
    )
end

function _sampler_diagnostic_flag(acceptance_rate::Float64,
        n_nonfinite::Int,
        n_divergences,
        n_max_treedepth)
    n_nonfinite > 0 && return :nonfinite_log_posterior
    isfinite(acceptance_rate) && 0 <= acceptance_rate <= 1 ||
        return :invalid_acceptance_rate
    !ismissing(n_divergences) && n_divergences > 0 && return :divergent_transitions
    !ismissing(n_max_treedepth) && n_max_treedepth > 0 && return :max_treedepth
    acceptance_rate == 0.0 && return :zero_acceptance
    acceptance_rate == 1.0 && return :all_accepted
    return :ok
end

function _finite_log_posterior_summary(logps)
    finite_values = Float64[]
    for value in logps
        isfinite(value) && push!(finite_values, Float64(value))
    end
    isempty(finite_values) && return (mean = NaN, minimum = NaN, maximum = NaN)
    return (;
        mean = _column_mean(finite_values),
        minimum = minimum(finite_values),
        maximum = maximum(finite_values),
    )
end

function _nt_get(nt::NamedTuple, key::Symbol, default)
    return haskey(nt, key) ? getproperty(nt, key) : default
end

function _chain_sampler_stats(fit::MFRMFit, chain::Int)
    return [row for row in fit.sampler_stats if row.chain == chain]
end

function _maybe_count(rows, predicate)
    isempty(rows) && return missing
    return count(predicate, rows)
end

function _maybe_mean(rows, field::Symbol)
    isempty(rows) && return missing
    value = _stat_mean(rows, field)
    return isfinite(value) ? value : missing
end

function _maybe_max_int(rows, field::Symbol)
    isempty(rows) && return missing
    values = Int[]
    for row in rows
        value = getproperty(row, field)
        ismissing(value) && continue
        push!(values, Int(value))
    end
    isempty(values) && return missing
    return maximum(values)
end

function _ebfmi(energies)
    values = [Float64(value) for value in energies if !ismissing(value) && isfinite(value)]
    length(values) >= 3 || return missing
    mean_energy = _column_mean(values)
    denom = sum((value - mean_energy)^2 for value in values) / (length(values) - 1)
    denom > 0 || return missing
    numerator = sum((values[i] - values[i - 1])^2 for i in 2:length(values)) / (length(values) - 1)
    return numerator / denom
end

function _chain_sampler_summary(fit::MFRMFit, chain::Int)
    rows = _chain_sampler_stats(fit, chain)
    max_depth = _nt_get(fit.sampler_controls, :max_depth, missing)
    return (;
        n_divergences = _maybe_count(rows, row -> row.numerical_error),
        n_max_treedepth = ismissing(max_depth) ?
            missing :
            _maybe_count(rows, row -> !ismissing(row.tree_depth) && row.tree_depth >= max_depth),
        mean_n_steps = _maybe_mean(rows, :n_steps),
        mean_tree_depth = _maybe_mean(rows, :tree_depth),
        max_tree_depth = _maybe_max_int(rows, :tree_depth),
        mean_step_size = _maybe_mean(rows, :step_size),
        e_bfmi = _ebfmi((row.hamiltonian_energy for row in rows)),
    )
end

"""
    sampler_diagnostics(fit::MFRMFit)

Return chain-level sampler diagnostics for a fitted minimal MFRM object.
Rows include retained draw counts, warmup, step size, chain acceptance rate,
finite log-posterior counts, and log-posterior summaries. This complements
`mcmc_diagnostics`, which reports parameter-level R-hat and ESS. When the
AdvancedHMC/NUTS backend is used, rows also include divergent-transition,
tree-depth, step-size, and E-BFMI fields where available.
"""
function sampler_diagnostics(fit::MFRMFit)
    draws_per_chain = _fit_draws_per_chain(fit)
    nchains = length(fit.chain_acceptance_rate)
    rows = NamedTuple[]
    for chain in 1:nchains
        draw_rows = ((chain - 1) * draws_per_chain + 1):(chain * draws_per_chain)
        logps = @view fit.log_posterior[draw_rows]
        summary = _finite_log_posterior_summary(logps)
        n_finite = count(isfinite, logps)
        n_nonfinite = length(logps) - n_finite
        sampler_summary = _chain_sampler_summary(fit, chain)
        push!(rows, (;
            chain,
            backend = fit.backend,
            sampler = fit.sampler,
            n_draws = draws_per_chain,
            warmup = fit.warmup,
            step_size = fit.step_size,
            first_iteration = first(@view fit.iterations[draw_rows]),
            last_iteration = last(@view fit.iterations[draw_rows]),
            acceptance_rate = fit.chain_acceptance_rate[chain],
            mean_log_posterior = summary.mean,
            minimum_log_posterior = summary.minimum,
            maximum_log_posterior = summary.maximum,
            n_finite_log_posterior = n_finite,
            n_nonfinite_log_posterior = n_nonfinite,
            n_divergences = sampler_summary.n_divergences,
            n_max_treedepth = sampler_summary.n_max_treedepth,
            mean_n_steps = sampler_summary.mean_n_steps,
            mean_tree_depth = sampler_summary.mean_tree_depth,
            max_tree_depth = sampler_summary.max_tree_depth,
            mean_step_size = sampler_summary.mean_step_size,
            e_bfmi = sampler_summary.e_bfmi,
            flag = _sampler_diagnostic_flag(fit.chain_acceptance_rate[chain],
                n_nonfinite,
                sampler_summary.n_divergences,
                sampler_summary.n_max_treedepth),
        ))
    end
    return rows
end

function _mcmc_parameter_flag(diagnostic,
        rhat_threshold::Float64,
        ess_threshold::Float64)
    diagnostic.flag === :ok || return diagnostic.flag
    isfinite(diagnostic.rhat) && diagnostic.rhat > rhat_threshold &&
        return :mcmc_warning
    isfinite(diagnostic.ess) && diagnostic.ess < ess_threshold &&
        return :mcmc_warning
    return :ok
end

"""
    mcmc_diagnostics(fit::MFRMFit; split_chains = true,
                     rhat_threshold = 1.01, ess_threshold = 400)

Return parameter-level convergence diagnostics for the current fitted draws.
Rows include classical split R-hat and an autocorrelation-based effective
sample size estimate. These diagnostics require at least two independent
chains; single-chain fits return `NaN` diagnostics with
`flag = :insufficient_chains`. Finite rows whose R-hat or ESS fail the supplied
thresholds return `flag = :mcmc_warning`. Use `sampler_diagnostics` for
backend-specific sampler fields such as divergent transitions and tree depth.
"""
function mcmc_diagnostics(fit::MFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    values = _chain_draw_array(fit)
    original_iterations, original_chains, nparams = size(values)
    diagnostic_values = split_chains && original_chains >= 2 ?
        _split_chain_array(values) :
        values
    diagnostic_iterations, diagnostic_chains, _ = size(diagnostic_values)
    rows = NamedTuple[]
    for param in 1:nparams
        diagnostic = _rhat_and_ess(diagnostic_values, param)
        push!(rows, (;
            parameter = fit.design.parameter_names[param],
            rhat = diagnostic.rhat,
            ess = diagnostic.ess,
            n_chains = original_chains,
            draws_per_chain = original_iterations,
            diagnostic_chains,
            diagnostic_draws_per_chain = diagnostic_iterations,
            total_draws = size(fit.draws, 1),
            split_chains = split_chains && original_chains >= 2 && original_iterations >= 4,
            flag = _mcmc_parameter_flag(
                diagnostic,
                checked.rhat_threshold,
                checked.ess_threshold,
            ),
        ))
    end
    return rows
end

function _check_diagnostic_thresholds(rhat_threshold::Real, ess_threshold::Real)
    rhat_threshold > 1 || throw(ArgumentError("rhat_threshold must be greater than 1"))
    ess_threshold > 0 || throw(ArgumentError("ess_threshold must be positive"))
    return (rhat_threshold = Float64(rhat_threshold), ess_threshold = Float64(ess_threshold))
end

function _finite_extreme(values, reducer)
    finite_values = [Float64(value) for value in values if isfinite(value)]
    isempty(finite_values) && return NaN
    return reducer(finite_values)
end

function _parameter_block_flag(n_parameters::Int,
        n_insufficient::Int,
        n_degenerate::Int,
        n_bad_rhat::Int,
        n_low_ess::Int)
    n_parameters == 0 && return :empty_block
    n_insufficient > 0 && return :insufficient_chains
    n_degenerate > 0 && return :degenerate_draws
    (n_bad_rhat > 0 || n_low_ess > 0) && return :mcmc_warning
    return :ok
end

function _parameter_block_diagnostics(fit::MFRMFit,
        parameter_rows;
        split_chains::Bool,
        rhat_threshold::Float64,
        ess_threshold::Float64)
    row_by_name = Dict(row.parameter => row for row in parameter_rows)
    blocks = sort(collect(keys(fit.design.blocks)); by = string)
    rows = NamedTuple[]
    for block in blocks
        range = fit.design.blocks[block]
        indices = collect(range)
        names = isempty(indices) ? String[] : copy(fit.design.parameter_names[indices])
        block_rows = [row_by_name[name] for name in names]
        n_parameters = length(names)
        n_insufficient = count(row -> row.flag === :insufficient_chains, block_rows)
        n_degenerate = count(row -> row.flag === :degenerate_draws, block_rows)
        n_bad_rhat = count(row -> isfinite(row.rhat) && row.rhat > rhat_threshold, block_rows)
        n_low_ess = count(row -> isfinite(row.ess) && row.ess < ess_threshold, block_rows)
        push!(rows, (;
            block,
            first_parameter = isempty(indices) ? missing : first(indices),
            last_parameter = isempty(indices) ? missing : last(indices),
            n_parameters,
            parameter_names = names,
            n_chains = length(fit.chain_acceptance_rate),
            draws_per_chain = _fit_draws_per_chain(fit),
            total_draws = size(fit.draws, 1),
            split_chains = split_chains && length(fit.chain_acceptance_rate) >= 2,
            rhat_threshold,
            ess_threshold,
            max_rhat = n_parameters == 0 ? missing :
                _finite_extreme((row.rhat for row in block_rows), maximum),
            min_ess = n_parameters == 0 ? missing :
                _finite_extreme((row.ess for row in block_rows), minimum),
            n_bad_rhat,
            n_low_ess,
            n_insufficient_chains = n_insufficient,
            n_degenerate_parameters = n_degenerate,
            flag = _parameter_block_flag(
                n_parameters,
                n_insufficient,
                n_degenerate,
                n_bad_rhat,
                n_low_ess,
            ),
        ))
    end
    return rows
end

"""
    parameter_block_diagnostics(fit::MFRMFit; split_chains = true,
                                rhat_threshold = 1.01,
                                ess_threshold = 400)

Summarize MCMC convergence diagnostics by identified parameter block. Rows
aggregate the parameter-level R-hat and ESS diagnostics for blocks such as
`:person`, `:rater`, `:item`, and `:thresholds`, while retaining block
parameter names and machine-readable pass/fail counts. Empty blocks are
returned with `flag = :empty_block` so reports can distinguish absent design
terms from failed diagnostics.
"""
function parameter_block_diagnostics(fit::MFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    parameter_rows = mcmc_diagnostics(fit;
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold)
    return _parameter_block_diagnostics(fit, parameter_rows;
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold)
end


function _sum_nonmissing(values)
    total = 0
    seen = false
    for value in values
        ismissing(value) && continue
        total += Int(value)
        seen = true
    end
    return seen ? total : missing
end

function _min_nonmissing(values)
    finite_values = [Float64(value) for value in values if !ismissing(value) && isfinite(value)]
    isempty(finite_values) && return missing
    return minimum(finite_values)
end

"""
    diagnostics(fit::MFRMFit; split_chains = true, rhat_threshold = 1.01,
                ess_threshold = 400)

Return a single diagnostic surface for the current minimal Bayesian fitting
path. The result includes chain-level sampler rows from `sampler_diagnostics`,
parameter-level rows from `mcmc_diagnostics`, block-level rows from
`parameter_block_diagnostics`, and a compact machine-readable summary with
pass/fail counts. For the AdvancedHMC-backed NUTS path, the summary also
reports divergent-transition counts, max-tree-depth hits, and the minimum
available E-BFMI estimate across chains.
"""
function diagnostics(fit::MFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)

    sampler_rows = sampler_diagnostics(fit)
    parameter_rows = mcmc_diagnostics(fit;
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold)
    block_rows = _parameter_block_diagnostics(fit, parameter_rows;
        split_chains,
        rhat_threshold = checked.rhat_threshold,
        ess_threshold = checked.ess_threshold)
    n_sampler_warnings = count(row -> row.flag !== :ok, sampler_rows)
    n_block_warnings = count(row -> row.flag in (:insufficient_chains, :degenerate_draws, :mcmc_warning), block_rows)
    n_empty_blocks = count(row -> row.flag === :empty_block, block_rows)
    n_nonfinite_log_posterior = sum(row.n_nonfinite_log_posterior for row in sampler_rows)
    n_divergences = _sum_nonmissing(row.n_divergences for row in sampler_rows)
    n_max_treedepth = _sum_nonmissing(row.n_max_treedepth for row in sampler_rows)
    e_bfmi = _min_nonmissing(row.e_bfmi for row in sampler_rows)
    n_insufficient = count(row -> row.flag === :insufficient_chains, parameter_rows)
    n_degenerate = count(row -> row.flag === :degenerate_draws, parameter_rows)
    n_bad_rhat = count(row -> isfinite(row.rhat) && row.rhat > rhat_threshold, parameter_rows)
    n_low_ess = count(row -> isfinite(row.ess) && row.ess < ess_threshold, parameter_rows)
    max_rhat = _finite_extreme((row.rhat for row in parameter_rows), maximum)
    min_ess = _finite_extreme((row.ess for row in parameter_rows), minimum)

    flag = if n_sampler_warnings > 0 || n_nonfinite_log_posterior > 0
        :sampler_warning
    elseif n_insufficient > 0
        :insufficient_chains
    elseif n_degenerate > 0 || n_bad_rhat > 0 || n_low_ess > 0
        :mcmc_warning
    else
        :ok
    end

    return (;
        schema = "bayesianmgmfrm.diagnostics.v1",
        backend = fit.backend,
        sampler = fit.sampler,
        summary = (;
            flag,
            passed = flag === :ok,
            n_chains = length(fit.chain_acceptance_rate),
            draws_per_chain = _fit_draws_per_chain(fit),
            total_draws = size(fit.draws, 1),
            n_parameters = length(fit.design.parameter_names),
            split_chains = split_chains && length(fit.chain_acceptance_rate) >= 2,
            rhat_threshold = checked.rhat_threshold,
            ess_threshold = checked.ess_threshold,
            max_rhat,
            min_ess,
            n_bad_rhat,
            n_low_ess,
            n_insufficient_chains = n_insufficient,
            n_degenerate_parameters = n_degenerate,
            n_block_warnings,
            n_empty_blocks,
            n_sampler_warnings,
            n_nonfinite_log_posterior,
            n_divergences,
            n_max_treedepth,
            e_bfmi,
        ),
        sampler_rows,
        parameter_rows,
        block_rows,
    )
end

sampler_diagnostics(fit::GMFRMFit) = fit.diagnostic_surface.sampler_rows

function _check_gmfrm_fit_diagnostic_policy(fit::GMFRMFit;
        split_chains::Bool,
        rhat_threshold::Real,
        ess_threshold::Real)
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    summary = fit.diagnostic_surface.summary
    actual_split = split_chains &&
        length(fit.chain_acceptance_rate) >= 2 &&
        _fit_draws_per_chain(fit) >= 4
    summary.split_chains == actual_split &&
        summary.rhat_threshold == checked.rhat_threshold &&
        summary.ess_threshold == checked.ess_threshold ||
        throw(ArgumentError(
            "experimental GMFRM fit diagnostics are recorded at fit time; " *
            "use the original split_chains, rhat_threshold, and ess_threshold",
        ))
    return checked
end

function mcmc_diagnostics(fit::GMFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    _check_gmfrm_fit_diagnostic_policy(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    return fit.diagnostic_surface.parameter_rows
end

function parameter_block_diagnostics(fit::GMFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    _check_gmfrm_fit_diagnostic_policy(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    return fit.diagnostic_surface.block_rows
end

function diagnostics(fit::GMFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    _check_gmfrm_fit_diagnostic_policy(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    surface = fit.diagnostic_surface
    return (;
        schema = "bayesianmgmfrm.gmfrm_experimental_fit_diagnostics.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        public_fit = true,
        experimental_public = true,
        backend = fit.backend,
        sampler = fit.sampler,
        summary = surface.summary,
        sampler_rows = surface.sampler_rows,
        parameter_rows = surface.parameter_rows,
        block_rows = surface.block_rows,
        direct_constraint_rows = surface.direct_constraint_rows,
        direct_parameter_rows = surface.direct_parameter_rows,
        direct_block_rows = surface.direct_block_rows,
    )
end

sampler_diagnostics(fit::MGMFRMFit) = fit.diagnostic_surface.sampler_rows

function _check_mgmfrm_fit_diagnostic_policy(fit::MGMFRMFit;
        split_chains::Bool,
        rhat_threshold::Real,
        ess_threshold::Real)
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    summary = fit.diagnostic_surface.summary
    actual_split = split_chains &&
        length(fit.chain_acceptance_rate) >= 2 &&
        _fit_draws_per_chain(fit) >= 4
    summary.split_chains == actual_split &&
        summary.rhat_threshold == checked.rhat_threshold &&
        summary.ess_threshold == checked.ess_threshold ||
        throw(ArgumentError(
            "guarded MGMFRM fit diagnostics are recorded at fit time; " *
            "use the original split_chains, rhat_threshold, and ess_threshold",
        ))
    return checked
end

function mcmc_diagnostics(fit::MGMFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    _check_mgmfrm_fit_diagnostic_policy(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    return fit.diagnostic_surface.parameter_rows
end

function parameter_block_diagnostics(fit::MGMFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    _check_mgmfrm_fit_diagnostic_policy(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    return fit.diagnostic_surface.block_rows
end

function diagnostics(fit::MGMFRMFit;
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    _check_mgmfrm_fit_diagnostic_policy(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    surface = fit.diagnostic_surface
    return (;
        schema = "bayesianmgmfrm.mgmfrm_guarded_local_fit_diagnostics.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        guarded_local_fit = true,
        backend = fit.backend,
        sampler = fit.sampler,
        summary = surface.summary,
        sampler_rows = surface.sampler_rows,
        parameter_rows = surface.parameter_rows,
        block_rows = surface.block_rows,
        direct_constraint_rows = surface.direct_constraint_rows,
        direct_parameter_rows = surface.direct_parameter_rows,
        direct_block_rows = surface.direct_block_rows,
    )
end

function _model_manifest(fit::MFRMFit, diagnostic_summary)
    base = model_manifest(fit.design)
    return (;
        schema = "bayesianmgmfrm.model_manifest.v1",
        object = :fit,
        data = base.data,
        validation = base.validation,
        spec = base.spec,
        design = base.design,
        fit = fit_metadata(fit),
        diagnostics = diagnostic_summary,
    )
end

function model_manifest(fit::MFRMFit)
    return _model_manifest(fit, diagnostics(fit).summary)
end

function _model_manifest(fit::GMFRMFit, diagnostic_summary)
    base = model_manifest(fit.design)
    return (;
        schema = "bayesianmgmfrm.model_manifest.v1",
        object = :fit,
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        data = base.data,
        validation = base.validation,
        spec = base.spec,
        design = base.design,
        fit = fit_metadata(fit),
        diagnostics = diagnostic_summary,
    )
end

function model_manifest(fit::GMFRMFit)
    return _model_manifest(fit, diagnostics(fit).summary)
end

function _model_manifest(fit::MGMFRMFit, diagnostic_summary)
    base = model_manifest(fit.design)
    return (;
        schema = "bayesianmgmfrm.model_manifest.v1",
        object = :fit,
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        public_fit = true,
        experimental_public = true,
        guarded_local_fit = true,
        fit_ready = true,
        data = base.data,
        validation = base.validation,
        spec = base.spec,
        design = base.design,
        fit = fit_metadata(fit),
        diagnostics = diagnostic_summary,
    )
end

function model_manifest(fit::MGMFRMFit)
    return _model_manifest(fit, diagnostics(fit).summary)
end

function _fit_rng_control(fit)
    controls = fit.sampler_controls
    haskey(controls, :rng) && return controls.rng
    return (;
        algorithm = missing,
        seed = missing,
        replayable = false,
    )
end

function _artifact_inclusion_flag(include::Bool)
    return include ? :included : :omitted
end

"""
    fit_artifact(fit::MFRMFit; include_draws = false,
                 include_log_posterior = include_draws,
                 include_sampler_stats = false,
                 include_environment = true,
                 include_packages = false,
                 split_chains = true,
                 rhat_threshold = 1.01,
                 ess_threshold = 400)

Return a reproducibility artifact for a fitted minimal MFRM object. The artifact
combines the model manifest, selected diagnostic surface, posterior summary,
sampler controls, RNG replay metadata, and optional environment metadata. Draws,
log-posterior values, and sampler-stat rows are omitted by default to keep the
artifact compact; set the corresponding `include_*` keyword to retain them for a
cached-draw report path.
"""
function fit_artifact(fit::MFRMFit;
        include_draws::Bool = false,
        include_log_posterior::Bool = include_draws,
        include_sampler_stats::Bool = false,
        include_environment::Bool = true,
        include_packages::Bool = false,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    diagnostic_surface = diagnostics(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    manifest = _model_manifest(fit, diagnostic_surface.summary)
    rng = _fit_rng_control(fit)
    artifact_policy = (;
        draws = _artifact_inclusion_flag(include_draws),
        log_posterior = _artifact_inclusion_flag(include_log_posterior),
        sampler_stats = _artifact_inclusion_flag(include_sampler_stats),
        environment = _artifact_inclusion_flag(include_environment),
        package_status = include_environment && include_packages ? :included : :omitted,
    )
    reproducibility = (;
        data_signature = fit.design.spec.validation.data_signature,
        rng,
        replayable_rng = _nt_get(rng, :replayable, false) === true,
        sampler_controls = fit.sampler_controls,
        diagnostic_policy = (;
            split_chains = diagnostic_surface.summary.split_chains,
            rhat_threshold = diagnostic_surface.summary.rhat_threshold,
            ess_threshold = diagnostic_surface.summary.ess_threshold,
        ),
        artifact_policy,
    )
    environment = include_environment ?
        evidence_metadata(; include_packages) :
        nothing
    return _with_archive_metadata((;
        schema = "bayesianmgmfrm.fit_artifact.v1",
        object = :fit_artifact,
        created_at = string(now()),
        manifest,
        diagnostics = diagnostic_surface,
        posterior_summary = posterior_summary(fit),
        reproducibility,
        environment,
        draws = include_draws ? copy(fit.draws) : nothing,
        log_posterior = include_log_posterior ? copy(fit.log_posterior) : nothing,
        sampler_stats = include_sampler_stats ? copy(fit.sampler_stats) : nothing,
    ); label = :fit_artifact)
end

function fit_artifact(fit::GMFRMFit;
        include_draws::Bool = false,
        include_log_posterior::Bool = include_draws,
        include_sampler_stats::Bool = false,
        include_environment::Bool = true,
        include_packages::Bool = false,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    diagnostic_surface = diagnostics(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    manifest = _model_manifest(fit, diagnostic_surface.summary)
    base_manifest = model_manifest(fit.design)
    raw_manifest = base_manifest.design.raw_parameterization
    promotion = raw_manifest.promotion_candidate
    experimental_decision = promotion.experimental_public_api
    rng = _fit_rng_control(fit)
    artifact_policy = (;
        raw_draws = _artifact_inclusion_flag(include_draws),
        direct_draws = _artifact_inclusion_flag(include_draws),
        log_posterior = _artifact_inclusion_flag(include_log_posterior),
        sampler_stats = _artifact_inclusion_flag(include_sampler_stats),
        environment = _artifact_inclusion_flag(include_environment),
        package_status = include_environment && include_packages ? :included : :omitted,
    )
    reproducibility = (;
        data_signature = fit.design.spec.validation.data_signature,
        rng,
        replayable_rng = _nt_get(rng, :replayable, false) === true,
        sampler_controls = fit.sampler_controls,
        diagnostic_policy = (;
            split_chains = diagnostic_surface.summary.split_chains,
            rhat_threshold = diagnostic_surface.summary.rhat_threshold,
            ess_threshold = diagnostic_surface.summary.ess_threshold,
        ),
        artifact_policy,
    )
    environment = include_environment ?
        evidence_metadata(; include_packages) :
        nothing
    return _with_archive_metadata((;
        schema = "bayesianmgmfrm.gmfrm_experimental_fit_artifact.v1",
        object = :fit_artifact,
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :experimental_public_fit_artifact,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        created_at = string(now()),
        density_space = :raw_unconstrained,
        raw_parameter_names = copy(fit.diagnostic_surface.raw_parameter_names),
        direct_parameter_names =
            copy(fit.diagnostic_surface.direct_parameter_names),
        raw_to_direct_transform = raw_manifest.transforms,
        sampler_controls = fit.sampler_controls,
        diagnostics = diagnostic_surface,
        pointwise_loglikelihood = copy(fit.direct_pointwise_loglikelihood),
        caveat_docs_artifact = experimental_decision.caveat_docs_artifact,
        fixture_provenance = experimental_decision.fit_artifact_contract.provenance_rows,
        manifest,
        posterior_summary = posterior_summary(fit),
        direct_posterior_summary = direct_posterior_summary(fit),
        reproducibility,
        environment,
        raw_draws = include_draws ? copy(fit.draws) : nothing,
        direct_draws = include_draws ? copy(fit.direct_draws) : nothing,
        log_posterior = include_log_posterior ? copy(fit.log_posterior) : nothing,
        sampler_stats = include_sampler_stats ? copy(fit.sampler_stats) : nothing,
    ); label = :gmfrm_experimental_fit_artifact)
end

function fit_artifact(fit::MGMFRMFit;
        include_draws::Bool = false,
        include_log_posterior::Bool = include_draws,
        include_sampler_stats::Bool = false,
        include_environment::Bool = true,
        include_packages::Bool = false,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    diagnostic_surface = diagnostics(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    manifest = _model_manifest(fit, diagnostic_surface.summary)
    base_manifest = model_manifest(fit.design)
    raw_manifest = base_manifest.design.raw_parameterization
    confirmatory = raw_manifest.confirmatory_candidate
    experimental_decision = confirmatory.experimental_public_api_decision
    rng = _fit_rng_control(fit)
    artifact_policy = (;
        raw_draws = _artifact_inclusion_flag(include_draws),
        direct_draws = _artifact_inclusion_flag(include_draws),
        log_posterior = _artifact_inclusion_flag(include_log_posterior),
        sampler_stats = _artifact_inclusion_flag(include_sampler_stats),
        environment = _artifact_inclusion_flag(include_environment),
        package_status = include_environment && include_packages ? :included : :omitted,
    )
    reproducibility = (;
        data_signature = fit.design.spec.validation.data_signature,
        rng,
        replayable_rng = _nt_get(rng, :replayable, false) === true,
        sampler_controls = fit.sampler_controls,
        diagnostic_policy = (;
            split_chains = diagnostic_surface.summary.split_chains,
            rhat_threshold = diagnostic_surface.summary.rhat_threshold,
            ess_threshold = diagnostic_surface.summary.ess_threshold,
        ),
        artifact_policy,
    )
    environment = include_environment ?
        evidence_metadata(; include_packages) :
        nothing
    return _with_archive_metadata((;
        schema = "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1",
        object = :fit_artifact,
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :experimental_public_fit_artifact,
        public_fit = true,
        experimental_public = true,
        guarded_local_fit = true,
        fit_ready = true,
        created_at = string(now()),
        density_space = :raw_unconstrained,
        entrypoint = "fit(spec; experimental = true)",
        guarded_local_entrypoint = :_fit_guarded_mgmfrm,
        target = :_mgmfrm_guarded_local_fit_logdensity,
        q_matrix = _q_matrix_manifest(fit.design.spec.q_matrix),
        latent_correlation = :identity_fixed,
        raw_parameter_names = copy(fit.diagnostic_surface.raw_parameter_names),
        direct_parameter_names =
            copy(fit.diagnostic_surface.direct_parameter_names),
        raw_to_direct_transform = raw_manifest.transforms,
        sampler_controls = fit.sampler_controls,
        diagnostics = diagnostic_surface,
        pointwise_loglikelihood = copy(fit.direct_pointwise_loglikelihood),
        caveat_docs_artifact = experimental_decision.caveat_docs_artifact,
        fixture_provenance = experimental_decision.fit_artifact_contract.provenance_rows,
        manifest,
        posterior_summary = posterior_summary(fit),
        direct_posterior_summary = direct_posterior_summary(fit),
        reproducibility,
        environment,
        raw_draws = include_draws ? copy(fit.draws) : nothing,
        direct_draws = include_draws ? copy(fit.direct_draws) : nothing,
        log_posterior = include_log_posterior ? copy(fit.log_posterior) : nothing,
        sampler_stats = include_sampler_stats ? copy(fit.sampler_stats) : nothing,
    ); label = :mgmfrm_experimental_fit_artifact)
end

function _fit_report_on_section_error(on_section_error::Symbol)
    on_section_error in (:capture, :throw) ||
        throw(ArgumentError("on_section_error must be :capture or :throw"))
    return on_section_error
end

function _fit_report_section(thunk, on_section_error::Symbol)
    try
        return merge((; status = :computed), thunk())
    catch err
        on_section_error === :throw && rethrow()
        return (;
            status = :error,
            exception = Symbol(nameof(typeof(err))),
            message = sprint(showerror, err),
        )
    end
end

_fit_report_not_requested() = (; status = :not_requested)

function _fit_report_unsupported(reason::AbstractString)
    return (;
        status = :unsupported,
        reason = String(reason),
    )
end

function _fit_report_prior_predictive(fit::MFRMFit;
        include_prior_predictive::Bool,
        prior_predictive_ndraws::Int,
        prior_predictive_rng::AbstractRNG,
        predictive_interval::Real,
        include_grouped_predictive::Bool,
        on_section_error::Symbol)
    include_prior_predictive || return _fit_report_not_requested()
    return _fit_report_section(on_section_error) do
        check = prior_predictive_check(fit.design;
            prior = fit.prior,
            ndraws = prior_predictive_ndraws,
            rng = prior_predictive_rng)
        rows = predictive_check_summary(check;
            interval = predictive_interval,
            include_grouped = include_grouped_predictive)
        (;
            ndraws = prior_predictive_ndraws,
            rows,
            n_rows = length(rows),
            implication_diagnostics = check.implication_diagnostics,
        )
    end
end

function _fit_report_prior_predictive(fit::_ModelComparisonFit;
        include_prior_predictive::Bool,
        kwargs...)
    include_prior_predictive || return _fit_report_not_requested()
    return _fit_report_unsupported(
        "prior predictive reporting is currently implemented for MFRMFit only",
    )
end

function _fit_report_direct_posterior(fit::MFRMFit; include_direct_posterior::Bool,
        kwargs...)
    include_direct_posterior || return _fit_report_not_requested()
    return _fit_report_unsupported(
        "direct constrained posterior rows are only available for guarded generalized fits",
    )
end

function _fit_report_direct_posterior(fit::Union{GMFRMFit,MGMFRMFit};
        include_direct_posterior::Bool,
        posterior_lower::Real,
        posterior_upper::Real,
        posterior_intervals,
        posterior_reference::Real,
        posterior_rope,
        posterior_rope_probability_threshold::Real,
        on_section_error::Symbol)
    include_direct_posterior || return _fit_report_not_requested()
    return _fit_report_section(on_section_error) do
        rows = direct_posterior_summary(fit;
            lower = posterior_lower,
            upper = posterior_upper,
            intervals = posterior_intervals,
            reference = posterior_reference,
            rope = posterior_rope,
            rope_probability_threshold = posterior_rope_probability_threshold)
        (;
            rows,
            n_rows = length(rows),
        )
    end
end

function _fit_report_dff(fit::MFRMFit;
        include_dff::Bool,
        dff_terms,
        dff_interval::Real,
        dff_min_n::Int,
        dff_expected_score_practical_threshold,
        dff_logit_practical_threshold,
        dff_practical_probability_threshold::Real,
        ndraws,
        draw_indices,
        rng::AbstractRNG,
        on_section_error::Symbol)
    include_dff || return _fit_report_not_requested()
    return _fit_report_section(on_section_error) do
        rows = dff_report(fit;
            terms = dff_terms,
            interval = dff_interval,
            min_n = dff_min_n,
            expected_score_practical_threshold =
                dff_expected_score_practical_threshold,
            logit_practical_threshold = dff_logit_practical_threshold,
            practical_probability_threshold = dff_practical_probability_threshold,
            ndraws,
            draw_indices,
            rng)
        (;
            rows,
            n_rows = length(rows),
        )
    end
end

function _fit_report_dff(fit::_ModelComparisonFit; include_dff::Bool, kwargs...)
    include_dff || return _fit_report_not_requested()
    return _fit_report_unsupported(
        "DFF screening report rows are currently implemented for MFRMFit only",
    )
end

"""
    fit_report(fit; kwargs...)

Build a compact, machine-readable report bundle for a fitted MFRM, guarded
GMFRM, or guarded MGMFRM object. The report combines fit metadata, provenance,
diagnostics, posterior summaries, posterior predictive summaries, calibration
rows, WAIC/LOO summaries and diagnostics, optional DFF rows, and a compact
archive manifest. Section-level failures are captured by default with
`status = :error`; use `on_section_error = :throw` to make the first failing
section raise.

Set `include_prior_predictive = true` for MFRM fits to include prior predictive
summary rows. Use `include_full_artifact = true` to embed the full compact
`fit_artifact`; otherwise only the artifact schema, content hash, and archive
manifest are included in the report.
"""
function fit_report(fit::_ModelComparisonFit;
        include_prior_predictive::Bool = false,
        prior_predictive_ndraws::Int = 100,
        prior_predictive_rng::AbstractRNG = Random.default_rng(),
        include_posterior_predictive::Bool = true,
        include_grouped_predictive::Bool = true,
        predictive_interval::Real = 0.9,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        posterior_lower::Real = 0.025,
        posterior_upper::Real = 0.975,
        posterior_intervals = (0.66, 0.9, 0.95),
        posterior_reference::Real = 0.0,
        posterior_rope = nothing,
        posterior_rope_probability_threshold::Real = 0.95,
        include_direct_posterior::Bool = fit isa Union{GMFRMFit,MGMFRMFit},
        include_calibration::Bool = true,
        calibration_target::Symbol = :expected_score,
        calibration_category = nothing,
        calibration_bins::Int = 10,
        calibration_interval::Real = 0.9,
        include_waic::Bool = true,
        waic_threshold::Real = 0.4,
        include_loo::Bool = true,
        loo_threshold::Real = 0.7,
        loo_tail_fraction::Real = 0.2,
        loo_min_tail_draws::Int = 5,
        include_dff::Bool = false,
        dff_terms = :validation,
        dff_interval::Real = 0.95,
        dff_min_n::Int = 1,
        dff_expected_score_practical_threshold = nothing,
        dff_logit_practical_threshold = nothing,
        dff_practical_probability_threshold::Real = 0.8,
        include_artifact::Bool = true,
        include_full_artifact::Bool = false,
        artifact_include_draws::Bool = false,
        artifact_include_log_posterior::Bool = artifact_include_draws,
        artifact_include_sampler_stats::Bool = false,
        artifact_include_environment::Bool = false,
        artifact_include_packages::Bool = false,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400,
        on_section_error::Symbol = :capture)
    checked_on_error = _fit_report_on_section_error(on_section_error)
    diagnostic_surface = diagnostics(fit;
        split_chains,
        rhat_threshold,
        ess_threshold)
    manifest = _model_manifest(fit, diagnostic_surface.summary)
    metadata = fit_metadata(fit)
    report_draw_indices = ndraws === nothing && draw_indices === nothing ?
        nothing : _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    checked_dff_expected_score_practical_threshold = _dff_practical_threshold(
        dff_expected_score_practical_threshold,
        "dff_expected_score_practical_threshold",
    )
    checked_dff_logit_practical_threshold = _dff_practical_threshold(
        dff_logit_practical_threshold,
        "dff_logit_practical_threshold",
    )
    checked_dff_practical_probability_threshold =
        _dff_practical_probability_threshold(dff_practical_probability_threshold)

    posterior = _fit_report_section(checked_on_error) do
        rows = posterior_summary(fit;
            lower = posterior_lower,
            upper = posterior_upper,
            intervals = posterior_intervals,
            reference = posterior_reference,
            rope = posterior_rope,
            rope_probability_threshold = posterior_rope_probability_threshold)
        (;
            rows,
            n_rows = length(rows),
        )
    end

    direct_posterior = _fit_report_direct_posterior(fit;
        include_direct_posterior,
        posterior_lower,
        posterior_upper,
        posterior_intervals,
        posterior_reference,
        posterior_rope,
        posterior_rope_probability_threshold,
        on_section_error = checked_on_error)

    prior_predictive = _fit_report_prior_predictive(fit;
        include_prior_predictive,
        prior_predictive_ndraws,
        prior_predictive_rng,
        predictive_interval,
        include_grouped_predictive,
        on_section_error = checked_on_error)

    posterior_predictive = include_posterior_predictive ?
        _fit_report_section(checked_on_error) do
            check = posterior_predictive_check(fit;
                ndraws = nothing,
                draw_indices = report_draw_indices,
                rng)
            rows = predictive_check_summary(check;
                interval = predictive_interval,
                include_grouped = include_grouped_predictive)
            (;
                rows,
                n_rows = length(rows),
                draw_indices = hasproperty(check, :draw_indices) ?
                    copy(check.draw_indices) : nothing,
            )
        end :
        _fit_report_not_requested()

    calibration = include_calibration ?
        _fit_report_section(checked_on_error) do
            rows = calibration_table(fit;
                target = calibration_target,
                category = calibration_category,
                bins = calibration_bins,
                interval = calibration_interval,
                ndraws = nothing,
                draw_indices = report_draw_indices,
                rng)
            (;
                rows,
                n_rows = length(rows),
            )
        end :
        _fit_report_not_requested()

    waic_section = include_waic ?
        _fit_report_section(checked_on_error) do
            stat = waic(fit;
                ndraws = nothing,
                draw_indices = report_draw_indices,
                rng)
            diagnostic_rows = waic_diagnostics(fit;
                threshold = waic_threshold,
                ndraws = nothing,
                draw_indices = report_draw_indices,
                rng)
            (;
                stat,
                diagnostic_rows,
                n_diagnostic_rows = length(diagnostic_rows),
            )
        end :
        _fit_report_not_requested()

    loo_section = include_loo ?
        _fit_report_section(checked_on_error) do
            stat = loo(fit;
                ndraws = nothing,
                draw_indices = report_draw_indices,
                rng,
                pareto_k_threshold = loo_threshold,
                tail_fraction = loo_tail_fraction,
                min_tail_draws = loo_min_tail_draws)
            diagnostic_rows = loo_diagnostics(fit;
                threshold = loo_threshold,
                ndraws = nothing,
                draw_indices = report_draw_indices,
                rng,
                tail_fraction = loo_tail_fraction,
                min_tail_draws = loo_min_tail_draws)
            (;
                stat,
                diagnostic_rows,
                n_diagnostic_rows = length(diagnostic_rows),
            )
        end :
        _fit_report_not_requested()

    dff = _fit_report_dff(fit;
        include_dff,
        dff_terms,
        dff_interval,
        dff_min_n,
        dff_expected_score_practical_threshold =
            checked_dff_expected_score_practical_threshold,
        dff_logit_practical_threshold =
            checked_dff_logit_practical_threshold,
        dff_practical_probability_threshold =
            checked_dff_practical_probability_threshold,
        ndraws = nothing,
        draw_indices = report_draw_indices,
        rng,
        on_section_error = checked_on_error)

    artifact = include_artifact ?
        _fit_report_section(checked_on_error) do
            value = fit_artifact(fit;
                include_draws = artifact_include_draws,
                include_log_posterior = artifact_include_log_posterior,
                include_sampler_stats = artifact_include_sampler_stats,
                include_environment = artifact_include_environment,
                include_packages = artifact_include_packages,
                split_chains,
                rhat_threshold,
                ess_threshold)
            (;
                schema = value.schema,
                content_hash = value.content_hash,
                archive_manifest = value.archive_manifest,
                artifact = include_full_artifact ? value : nothing,
            )
        end :
        _fit_report_not_requested()

    return (;
        schema = "bayesianmgmfrm.fit_report.v1",
        object = :fit_report,
        created_at = string(now()),
        family = fit.design.spec.family,
        thresholds = fit.design.spec.thresholds,
        dimensions = fit.design.spec.dimensions,
        estimation_status = fit.design.spec.estimation_status,
        report_policy = (;
            include_prior_predictive,
            include_posterior_predictive,
            include_grouped_predictive,
            predictive_interval = Float64(predictive_interval),
            ndraws,
            draw_indices = draw_indices === nothing ? nothing : collect(draw_indices),
            resolved_draw_indices = report_draw_indices === nothing ?
                nothing : collect(report_draw_indices),
            posterior_intervals,
            include_direct_posterior,
            include_calibration,
            calibration_target,
            calibration_category,
            calibration_bins,
            calibration_interval = Float64(calibration_interval),
            include_waic,
            waic_threshold = Float64(waic_threshold),
            include_loo,
            loo_threshold = Float64(loo_threshold),
            loo_tail_fraction = Float64(loo_tail_fraction),
            loo_min_tail_draws,
            include_dff,
            dff_terms,
            dff_interval = Float64(dff_interval),
            dff_min_n,
            dff_expected_score_practical_threshold =
                checked_dff_expected_score_practical_threshold,
            dff_logit_practical_threshold =
                checked_dff_logit_practical_threshold,
            dff_practical_probability_threshold =
                checked_dff_practical_probability_threshold,
            include_artifact,
            include_full_artifact,
            on_section_error = checked_on_error,
        ),
        metadata,
        manifest,
        diagnostics = diagnostic_surface,
        prior_predictive,
        posterior,
        direct_posterior,
        posterior_predictive,
        calibration,
        waic = waic_section,
        loo = loo_section,
        dff,
        artifact,
    )
end

function _json_export_array(value::AbstractArray)
    if ndims(value) == 1
        return [_json_export_value(item) for item in value]
    elseif ndims(value) == 2
        return [[_json_export_value(value[i, j]) for j in axes(value, 2)]
                for i in axes(value, 1)]
    end
    return Dict{String,Any}(
        "shape" => collect(size(value)),
        "values" => [_json_export_value(item) for item in vec(value)],
    )
end

function _json_export_number(value::Number)
    if value isa AbstractFloat
        return isfinite(value) ? Float64(value) : string(value)
    elseif value isa Integer
        return value
    elseif value isa Real
        return isfinite(value) ? Float64(value) : string(value)
    end
    return string(value)
end

function _json_export_value(value)
    if value isa NamedTuple
        return Dict{String,Any}(
            String(name) => _json_export_value(getproperty(value, name))
            for name in keys(value)
        )
    elseif value isa AbstractDict
        return Dict{String,Any}(
            string(key) => _json_export_value(item)
            for (key, item) in value
        )
    elseif value isa Tuple
        return [_json_export_value(item) for item in value]
    elseif value isa AbstractArray
        return _json_export_array(value)
    elseif value isa Symbol
        return String(value)
    elseif value isa AbstractString
        return String(value)
    elseif value === missing || value === nothing
        return nothing
    elseif value isa Bool
        return value
    elseif value isa Number
        return _json_export_number(value)
    end
    return string(value)
end

function _json_hash_value(value)
    if value isa NamedTuple
        return NamedTuple{keys(value)}(
            Tuple(_json_hash_value(getproperty(value, name)) for name in keys(value)),
        )
    elseif value isa AbstractDict
        return Dict{Any,Any}(
            key => _json_hash_value(item)
            for (key, item) in value
        )
    elseif value isa Tuple
        return map(_json_hash_value, value)
    elseif value isa AbstractArray
        return [_json_hash_value(item) for item in value]
    elseif value isa Bool
        return value
    elseif value isa Real
        return isfinite(value) ? Float64(value) : string(value)
    elseif value isa Number
        return string(value)
    end
    return value
end

function _fit_report_json_hash_record(payload)
    hash_payload = _json_hash_value(_artifact_hash_payload(payload))
    canonical = _cache_stable_string(hash_payload)
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(codeunits(canonical))),
        scope = :json_report_without_hash_metadata,
        canonicalization = :cache_stable_string,
        n_canonical_bytes = sizeof(canonical),
    )
end

function _fit_report_export_record(report;
        label = nothing,
        source_path = nothing)
    _check_fit_report_payload(report)
    json_report = _json_export_value(report)
    return (;
        schema = "bayesianmgmfrm.fit_report_export.v1",
        object = :fit_report_export,
        created_at = string(now()),
        label = label === nothing ? missing : label,
        source_path = source_path === nothing ? missing : String(source_path),
        serialization = (;
            format = :json,
            writer = :JSON3,
            portability = :cross_tool_json_payload,
            missing_values = :json_null,
            nonfinite_numbers = :string,
        ),
        report_schema = _report_lookup(report, :schema, missing),
        report_object = _report_symbol_value(_report_lookup(report, :object, missing)),
        report_content_hash = _artifact_content_hash_record(report),
        json_content_hash = _fit_report_json_hash_record(json_report),
        report = json_report,
    )
end

"""
    save_fit_report(path, report; overwrite = false, label = nothing)
    save_fit_report(path, fit; overwrite = false, label = nothing, kwargs...)

Write a `fit_report` bundle to a JSON export record at `path`. Passing a fit
object first builds `fit_report(fit; kwargs...)`. The saved record includes the
original report content hash and a JSON-payload hash that [`load_fit_report`](@ref)
verifies by default.
"""
function save_fit_report(path::AbstractString,
        report;
        overwrite::Bool = false,
        label = nothing)
    isfile(path) && !overwrite &&
        throw(ArgumentError("fit report export already exists at $path; pass overwrite = true to replace it"))
    record = _fit_report_export_record(report;
        label,
        source_path = path)
    mkpath(dirname(path))
    open(path, "w") do io
        JSON3.write(io, _json_export_value(record))
        write(io, "\n")
    end
    return record
end

function save_fit_report(path::AbstractString,
        fit::_ModelComparisonFit;
        overwrite::Bool = false,
        label = nothing,
        kwargs...)
    report = fit_report(fit; kwargs...)
    return save_fit_report(path, report; overwrite = overwrite, label = label)
end

function _check_fit_report_export_hash_record(record,
        field::AbstractString,
        path::AbstractString,
        expected_scope::AbstractString)
    return _check_fit_report_hash_record(record, Symbol(field),
        "fit report export at $path";
        expected_scope = Symbol(expected_scope),
        expected_canonicalization = :cache_stable_string)
end

function _check_fit_report_export_record(record, path)
    record isa AbstractDict ||
        throw(ArgumentError("fit report export at $path does not contain a JSON object"))
    get(record, "schema", nothing) == "bayesianmgmfrm.fit_report_export.v1" ||
        throw(ArgumentError("fit report export at $path has an unsupported schema"))
    get(record, "object", nothing) == "fit_report_export" ||
        throw(ArgumentError("fit report export at $path has an unsupported object"))
    get(record, "report", nothing) isa AbstractDict ||
        throw(ArgumentError("fit report export at $path does not contain a report object"))
    _check_fit_report_export_hash_record(record, "report_content_hash", path,
        "artifact_without_hash_metadata")
    _check_fit_report_export_hash_record(record, "json_content_hash", path,
        "json_report_without_hash_metadata")
    return record
end

function _verify_fit_report_export_record(record, path)
    expected = get(record["json_content_hash"], "value", nothing)
    actual = _fit_report_json_hash_record(record["report"]).value
    isequal(expected, actual) ||
        throw(ArgumentError("fit report export content hash mismatch for $path"))
    return record
end

"""
    load_fit_report(path; verify_hash = true, return_record = false)

Load a JSON fit-report export written by [`save_fit_report`](@ref). The JSON
payload hash is verified by default, and the export/hash metadata shape is
always checked. The report payload is returned as `Dict{String,Any}` /
`Vector{Any}` data; set `return_record = true` to inspect the export metadata
and hash records as well.
"""
function load_fit_report(path::AbstractString;
        verify_hash::Bool = true,
        return_record::Bool = false)
    isfile(path) ||
        throw(ArgumentError("fit report export does not exist at $path"))
    record = JSON3.read(read(path, String), Dict{String,Any})
    record = _check_fit_report_export_record(record, path)
    verify_hash && _verify_fit_report_export_record(record, path)
    return return_record ? record : record["report"]
end

const _FIT_REPORT_LOOKUP_MISSING = Ref(:fit_report_lookup_missing)
const _FIT_REPORT_SECTION_ORDER = (
    :diagnostics,
    :prior_predictive,
    :posterior,
    :direct_posterior,
    :posterior_predictive,
    :calibration,
    :waic,
    :loo,
    :dff,
    :artifact,
)
const _FIT_REPORT_ROW_FIELD_ORDER = (
    :rows,
    :diagnostic_rows,
    :sampler_rows,
    :parameter_rows,
    :block_rows,
)

function _report_key_symbol(key::Symbol)
    return key
end

function _report_key_symbol(key::AbstractString)
    return Symbol(key)
end

function _report_key_symbol(key)
    throw(ArgumentError("fit report keys must be Symbols or strings; got $(typeof(key))"))
end

function _report_lookup(container::NamedTuple, key::Symbol, default)
    return key in keys(container) ? getproperty(container, key) : default
end

function _report_lookup(container::AbstractDict, key::Symbol, default)
    if haskey(container, key)
        return container[key]
    end
    string_key = String(key)
    return haskey(container, string_key) ? container[string_key] : default
end

function _report_lookup(container, key::Symbol, default)
    return default
end

function _report_lookup(container, key, default)
    return _report_lookup(container, _report_key_symbol(key), default)
end

function _report_keys(container::NamedTuple)
    return collect(keys(container))
end

function _report_keys(container::AbstractDict)
    return unique!([_report_key_symbol(key) for key in keys(container)])
end

function _report_keys(container)
    return Symbol[]
end

function _check_fit_report_payload(report)
    (report isa NamedTuple || report isa AbstractDict) ||
        throw(ArgumentError("expected a fit_report payload as a NamedTuple or Dict"))
    schema = _report_lookup(report, :schema, _FIT_REPORT_LOOKUP_MISSING)
    schema == "bayesianmgmfrm.fit_report.v1" ||
        throw(ArgumentError("expected a bayesianmgmfrm.fit_report.v1 payload"))
    return report
end

function _report_status(section)
    status = _report_lookup(section, :status, missing)
    status === missing && return missing
    status isa Symbol && return status
    status isa AbstractString && return Symbol(status)
    return status
end

function _report_row_fields(section)
    fields = Symbol[]
    for field in _FIT_REPORT_ROW_FIELD_ORDER
        rows = _report_lookup(section, field, _FIT_REPORT_LOOKUP_MISSING)
        rows isa AbstractVector && push!(fields, field)
    end
    known = Set(fields)
    extra = Symbol[]
    for field in _report_keys(section)
        field in known && continue
        endswith(String(field), "_rows") || continue
        rows = _report_lookup(section, field, _FIT_REPORT_LOOKUP_MISSING)
        rows isa AbstractVector && push!(extra, field)
    end
    append!(fields, sort(extra; by = String))
    return fields
end

function _report_row_count(section, row_field::Symbol, rows)
    count_key = row_field == :rows ? :n_rows : Symbol("n_", String(row_field))
    count = _report_lookup(section, count_key, _FIT_REPORT_LOOKUP_MISSING)
    count isa Integer && count >= 0 && return Int(count)
    return length(rows)
end

function _report_total_row_count(section, row_fields)
    total = 0
    for row_field in row_fields
        rows = _report_lookup(section, row_field, _FIT_REPORT_LOOKUP_MISSING)
        rows isa AbstractVector || continue
        total += _report_row_count(section, row_field, rows)
    end
    return total
end

function _auto_report_row_field(section, section_name::Symbol)
    row_fields = _report_row_fields(section)
    isempty(row_fields) &&
        throw(ArgumentError("fit report section $(String(section_name)) does not contain row fields"))
    :rows in row_fields && return :rows
    :diagnostic_rows in row_fields && return :diagnostic_rows
    return first(row_fields)
end

"""
    fit_report_sections(report)

Return a compact summary of the tabular/status-bearing sections in a
`fit_report` payload. `report` may be the original `NamedTuple` returned by
[`fit_report`](@ref) or the `Dict{String,Any}` payload returned by
[`load_fit_report`](@ref).

Each returned row includes `section`, `status`, `row_fields`, and `n_rows`.
JSON-loaded status strings are normalized to symbols.
"""
function fit_report_sections(report)
    _check_fit_report_payload(report)
    summaries = NamedTuple[]
    for section_name in _FIT_REPORT_SECTION_ORDER
        section = _report_lookup(report, section_name, _FIT_REPORT_LOOKUP_MISSING)
        section === _FIT_REPORT_LOOKUP_MISSING && continue
        row_fields = _report_row_fields(section)
        push!(summaries, (;
            section = section_name,
            status = _report_status(section),
            row_fields,
            n_rows = _report_total_row_count(section, row_fields),
        ))
    end
    return summaries
end

"""
    fit_report_section(report, section)

Return one section from a `fit_report` payload. `section` may be a `Symbol` or
string, and `report` may be either the in-memory report `NamedTuple` or a
JSON-loaded `Dict{String,Any}`.
"""
function fit_report_section(report, section)
    _check_fit_report_payload(report)
    section_name = _report_key_symbol(section)
    value = _report_lookup(report, section_name, _FIT_REPORT_LOOKUP_MISSING)
    value === _FIT_REPORT_LOOKUP_MISSING &&
        throw(ArgumentError("fit report section $(String(section_name)) was not found"))
    return value
end

"""
    fit_report_rows(report, section; row_field = :auto)

Return rows from one `fit_report` section. By default, `:auto` selects `:rows`
when present and otherwise selects `:diagnostic_rows`; pass `row_field` to
request a specific row field such as `:parameter_rows` from the diagnostics
section.
"""
function fit_report_rows(report, section; row_field = :auto)
    section_name = _report_key_symbol(section)
    section_value = fit_report_section(report, section_name)
    requested = _report_key_symbol(row_field)
    resolved = requested == :auto ?
        _auto_report_row_field(section_value, section_name) : requested
    rows = _report_lookup(section_value, resolved, _FIT_REPORT_LOOKUP_MISSING)
    rows isa AbstractVector ||
        throw(ArgumentError("fit report section $(String(section_name)) does not contain row field $(String(resolved))"))
    return rows
end

function _report_symbol_value(value)
    value isa Symbol && return value
    value isa AbstractString && return Symbol(value)
    return value
end

function _fit_report_file_component(name::Symbol)
    component = replace(String(name), r"[^A-Za-z0-9_]+" => "_")
    return isempty(component) ? "field" : component
end

function _fit_report_table_filename(section::Symbol, row_field::Symbol)
    return string(_fit_report_file_component(section), "__",
        _fit_report_file_component(row_field), ".json")
end

function _fit_report_table_hash_record(payload; scope::Symbol)
    hash_payload = _json_hash_value(_artifact_hash_payload(_json_export_value(payload)))
    canonical = _cache_stable_string(hash_payload)
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(codeunits(canonical))),
        scope,
        canonicalization = :cache_stable_string,
        n_canonical_bytes = sizeof(canonical),
    )
end

function _fit_report_table_record(report, section_name::Symbol, row_field::Symbol)
    rows = fit_report_rows(report, section_name; row_field)
    payload = (;
        schema = "bayesianmgmfrm.fit_report_table.v1",
        object = :fit_report_table,
        section = section_name,
        row_field,
        n_rows = length(rows),
        rows,
    )
    return merge(payload, (;
        content_hash = _fit_report_table_hash_record(payload;
            scope = :fit_report_table_without_hash_metadata),
    ))
end

function _fit_report_table_records(report)
    _check_fit_report_payload(report)
    records = NamedTuple[]
    for section in fit_report_sections(report)
        for row_field in section.row_fields
            push!(records, _fit_report_table_record(report, section.section, row_field))
        end
    end
    return records
end

function _fit_report_table_manifest(report, table_records;
        label = nothing,
        source_path = nothing)
    table_rows = NamedTuple[]
    total_rows = 0
    for record in table_records
        total_rows += record.n_rows
        push!(table_rows, (;
            section = record.section,
            row_field = record.row_field,
            filename = _fit_report_table_filename(record.section, record.row_field),
            n_rows = record.n_rows,
            content_hash = record.content_hash,
        ))
    end
    payload = (;
        schema = "bayesianmgmfrm.fit_report_table_export.v1",
        object = :fit_report_table_export,
        created_at = string(now()),
        label = label === nothing ? missing : label,
        source_path = source_path === nothing ? missing : String(source_path),
        report_schema = _report_lookup(report, :schema, missing),
        report_object = _report_symbol_value(_report_lookup(report, :object, missing)),
        report_content_hash = _artifact_content_hash_record(report),
        table_format = :json,
        manifest_filename = "manifest.json",
        n_tables = length(table_rows),
        n_rows = total_rows,
        tables = table_rows,
    )
    return merge(payload, (;
        content_hash = _fit_report_table_hash_record(payload;
            scope = :fit_report_table_export_without_hash_metadata),
    ))
end

function _check_fit_report_table_export_directory(directory::AbstractString,
        table_records;
        overwrite::Bool)
    if ispath(directory) && !isdir(directory)
        throw(ArgumentError("fit report table export path exists and is not a directory: $directory"))
    end
    if isdir(directory) && !overwrite && !isempty(readdir(directory))
        throw(ArgumentError("fit report table export directory is not empty at $directory; pass overwrite = true to replace export files"))
    end
    seen = Set{String}()
    for record in table_records
        filename = _fit_report_table_filename(record.section, record.row_field)
        filename in seen &&
            throw(ArgumentError("fit report table export filename collision for $filename"))
        push!(seen, filename)
    end
    return true
end

function _write_json_record(path::AbstractString, record)
    open(path, "w") do io
        JSON3.write(io, _json_export_value(record))
        write(io, "\n")
    end
    return path
end

"""
    save_fit_report_tables(directory, report; overwrite = false, label = nothing)
    save_fit_report_tables(directory, fit; overwrite = false, label = nothing, kwargs...)

Write every tabular row field from a `fit_report` payload into a directory of
portable JSON table files plus `manifest.json`. The returned manifest records
the exported table filenames, row counts, and table content hashes. `report` may
be an in-memory `fit_report` `NamedTuple` or a JSON-loaded report payload from
[`load_fit_report`](@ref). Passing a fit object first builds
`fit_report(fit; kwargs...)`.
"""
function save_fit_report_tables(directory::AbstractString,
        report;
        overwrite::Bool = false,
        label = nothing)
    _check_fit_report_payload(report)
    table_records = _fit_report_table_records(report)
    _check_fit_report_table_export_directory(directory, table_records;
        overwrite)
    mkpath(directory)
    for record in table_records
        path = joinpath(directory,
            _fit_report_table_filename(record.section, record.row_field))
        _write_json_record(path, record)
    end
    manifest = _fit_report_table_manifest(report, table_records;
        label,
        source_path = directory)
    _write_json_record(joinpath(directory, "manifest.json"), manifest)
    return manifest
end

function save_fit_report_tables(directory::AbstractString,
        fit::_ModelComparisonFit;
        overwrite::Bool = false,
        label = nothing,
        kwargs...)
    report = fit_report(fit; kwargs...)
    return save_fit_report_tables(directory, report; overwrite = overwrite, label = label)
end

function _fit_report_markdown_hash_record(markdown::AbstractString)
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(codeunits(markdown))),
        scope = :fit_report_markdown,
        canonicalization = :raw_markdown_string,
        n_canonical_bytes = sizeof(markdown),
    )
end

function _markdown_plain_value(value)
    value === missing && return ""
    value === nothing && return ""
    value isa Symbol && return String(value)
    value isa AbstractString && return String(value)
    value isa Bool && return string(value)
    value isa Number && return string(value)
    json_value = _json_export_value(value)
    if json_value isa AbstractString
        return String(json_value)
    end
    return JSON3.write(json_value)
end

function _markdown_cell(value; max_cell_chars::Int = 96)
    text = replace(_markdown_plain_value(value), '\n' => " ")
    text = replace(text, '\r' => " ")
    text = replace(text, "|" => "\\|")
    if max_cell_chars > 0 && lastindex(text) > max_cell_chars
        return string(first(text, max_cell_chars), "...")
    end
    return text
end

function _markdown_row_fields(rows, max_rows::Int)
    fields = Symbol[]
    seen = Set{Symbol}()
    for row in Iterators.take(rows, max_rows)
        for field in _report_keys(row)
            field in seen && continue
            push!(fields, field)
            push!(seen, field)
        end
    end
    return fields
end

function _write_markdown_table(io::IO, rows;
        fields = nothing,
        max_rows::Int = 6,
        max_cell_chars::Int = 96)
    row_vector = collect(rows)
    display_rows = collect(Iterators.take(row_vector, max_rows))
    resolved_fields = fields === nothing ?
        _markdown_row_fields(display_rows, max(1, length(display_rows))) :
        collect(fields)
    if isempty(resolved_fields)
        println(io, "_No rows to preview._")
        return
    end
    header_cells = [String(field) for field in resolved_fields]
    println(io, "| ", join(header_cells, " | "), " |")
    println(io, "| ", join(fill("---", length(resolved_fields)), " | "), " |")
    for row in display_rows
        cells = [
            _markdown_cell(_report_lookup(row, field, missing);
                max_cell_chars = max_cell_chars)
            for field in resolved_fields
        ]
        println(io, "| ", join(cells, " | "), " |")
    end
    if length(row_vector) > length(display_rows)
        println(io)
        println(io, "_", length(row_vector) - length(display_rows),
            " additional row(s) omitted._")
    end
    return
end

function _fit_report_metadata_rows(report)
    fields = (:schema, :object, :created_at, :family, :thresholds,
        :dimensions, :estimation_status)
    rows = NamedTuple[]
    for field in fields
        value = _report_lookup(report, field, _FIT_REPORT_LOOKUP_MISSING)
        value === _FIT_REPORT_LOOKUP_MISSING && continue
        push!(rows, (; field, value = _report_symbol_value(value)))
    end
    return rows
end

"""
    fit_report_markdown(report; title = "BayesianMGMFRM fit report",
        max_rows = 6, include_empty = false)

Render a portable Markdown review draft from a `fit_report` payload. The output
includes report metadata, section status/row counts, and table previews for
each tabular row field. `report` may be the in-memory `NamedTuple` returned by
[`fit_report`](@ref) or a JSON-loaded payload from [`load_fit_report`](@ref).
"""
function fit_report_markdown(report;
        title::AbstractString = "BayesianMGMFRM fit report",
        max_rows::Integer = 6,
        include_empty::Bool = false)
    max_rows >= 0 ||
        throw(ArgumentError("max_rows must be non-negative"))
    _check_fit_report_payload(report)
    io = IOBuffer()
    println(io, "# ", title)
    println(io)
    println(io, "Generated from `bayesianmgmfrm.fit_report.v1`.")
    println(io)
    report_hash = _artifact_content_hash_record(report)
    println(io, "- Report content hash: `", report_hash.value, "`")
    println(io, "- Markdown preview rows per table: ", max_rows)
    println(io)
    println(io, "## Report Metadata")
    println(io)
    _write_markdown_table(io, _fit_report_metadata_rows(report);
        fields = (:field, :value),
        max_rows = typemax(Int),
        max_cell_chars = 160)
    println(io)
    println(io, "## Section Summary")
    println(io)
    _write_markdown_table(io, fit_report_sections(report);
        fields = (:section, :status, :row_fields, :n_rows),
        max_rows = typemax(Int),
        max_cell_chars = 160)
    println(io)
    println(io, "## Table Previews")
    sections = fit_report_sections(report)
    wrote_preview = false
    for section in sections
        for row_field in section.row_fields
            rows = fit_report_rows(report, section.section; row_field)
            if isempty(rows) && !include_empty
                continue
            end
            wrote_preview = true
            println(io)
            println(io, "### ", String(section.section), " / ", String(row_field))
            println(io)
            println(io, "- Rows: ", length(rows))
            println(io, "- Preview rows: ", min(length(rows), Int(max_rows)))
            println(io)
            _write_markdown_table(io, rows;
                max_rows = Int(max_rows),
                max_cell_chars = 120)
        end
    end
    if !wrote_preview
        println(io)
        println(io, "_No tabular report rows are available._")
    end
    return String(take!(io))
end

function _fit_report_markdown_export_record(path::AbstractString,
        report,
        markdown::AbstractString;
        label = nothing,
        title::AbstractString,
        max_rows::Integer,
        include_empty::Bool)
    return (;
        schema = "bayesianmgmfrm.fit_report_markdown_export.v1",
        object = :fit_report_markdown_export,
        created_at = string(now()),
        label = label === nothing ? missing : label,
        source_path = String(path),
        report_schema = _report_lookup(report, :schema, missing),
        report_object = _report_symbol_value(_report_lookup(report, :object, missing)),
        report_content_hash = _artifact_content_hash_record(report),
        markdown_content_hash = _fit_report_markdown_hash_record(markdown),
        format = :markdown,
        title = String(title),
        max_rows = Int(max_rows),
        include_empty,
        n_bytes = sizeof(markdown),
    )
end

"""
    save_fit_report_markdown(path, report; overwrite = false,
        title = "BayesianMGMFRM fit report", max_rows = 6,
        include_empty = false, label = nothing)
    save_fit_report_markdown(path, fit; overwrite = false,
        title = "BayesianMGMFRM fit report", max_rows = 6,
        include_empty = false, label = nothing, kwargs...)

Write a Markdown review draft for a `fit_report` payload and return an export
record with report and Markdown content hashes. Passing a fit object first
builds `fit_report(fit; kwargs...)`.
"""
function save_fit_report_markdown(path::AbstractString,
        report;
        overwrite::Bool = false,
        title::AbstractString = "BayesianMGMFRM fit report",
        max_rows::Integer = 6,
        include_empty::Bool = false,
        label = nothing)
    isfile(path) && !overwrite &&
        throw(ArgumentError("fit report markdown already exists at $path; pass overwrite = true to replace it"))
    markdown = fit_report_markdown(report;
        title,
        max_rows,
        include_empty)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, markdown)
    end
    return _fit_report_markdown_export_record(path, report, markdown;
        label,
        title,
        max_rows,
        include_empty)
end

function save_fit_report_markdown(path::AbstractString,
        fit::_ModelComparisonFit;
        overwrite::Bool = false,
        title::AbstractString = "BayesianMGMFRM fit report",
        max_rows::Integer = 6,
        include_empty::Bool = false,
        label = nothing,
        kwargs...)
    report = fit_report(fit; kwargs...)
    return save_fit_report_markdown(path, report;
        overwrite,
        title,
        max_rows,
        include_empty,
        label)
end

function _check_fit_report_bundle_directory(directory::AbstractString;
        overwrite::Bool)
    if ispath(directory) && !isdir(directory)
        throw(ArgumentError("fit report bundle path exists and is not a directory: $directory"))
    end
    if isdir(directory) && !overwrite && !isempty(readdir(directory))
        throw(ArgumentError("fit report bundle directory is not empty at $directory; pass overwrite = true to replace export files"))
    end
    return true
end

function _fit_report_bundle_hash_record(payload)
    return _fit_report_table_hash_record(payload;
        scope = :fit_report_bundle_export_without_hash_metadata)
end

function _fit_report_bundle_file_rows(report_export, table_manifest,
        markdown_export)
    return [
        (;
            role = :report_json,
            path = "fit_report.json",
            schema = report_export.schema,
            object = report_export.object,
            content_hash = report_export.json_content_hash,
        ),
        (;
            role = :table_manifest,
            path = "tables/manifest.json",
            schema = table_manifest.schema,
            object = table_manifest.object,
            content_hash = table_manifest.content_hash,
            n_tables = table_manifest.n_tables,
            n_rows = table_manifest.n_rows,
        ),
        (;
            role = :markdown,
            path = "fit_report.md",
            schema = markdown_export.schema,
            object = markdown_export.object,
            content_hash = markdown_export.markdown_content_hash,
            n_bytes = markdown_export.n_bytes,
        ),
    ]
end

function _fit_report_bundle_manifest(directory::AbstractString,
        report_export,
        table_manifest,
        markdown_export;
        label = nothing)
    payload = (;
        schema = "bayesianmgmfrm.fit_report_bundle_export.v1",
        object = :fit_report_bundle_export,
        created_at = string(now()),
        label = label === nothing ? missing : label,
        source_path = String(directory),
        report_schema = report_export.report_schema,
        report_object = report_export.report_object,
        report_content_hash = report_export.report_content_hash,
        formats = (:json_report, :json_tables, :markdown),
        report_filename = "fit_report.json",
        table_directory = "tables",
        markdown_filename = "fit_report.md",
        manifest_filename = "manifest.json",
        n_tables = table_manifest.n_tables,
        n_rows = table_manifest.n_rows,
        files = _fit_report_bundle_file_rows(report_export, table_manifest,
            markdown_export),
    )
    return merge(payload, (;
        content_hash = _fit_report_bundle_hash_record(payload),
    ))
end

"""
    save_fit_report_bundle(directory, report; overwrite = false,
        label = nothing, title = "BayesianMGMFRM fit report",
        max_rows = 6, include_empty = false)
    save_fit_report_bundle(directory, fit; overwrite = false,
        label = nothing, title = "BayesianMGMFRM fit report",
        max_rows = 6, include_empty = false, kwargs...)

Write a portable fit-report bundle directory containing a JSON report export,
JSON table files, a Markdown review draft, and a bundle `manifest.json` with
the nested content hashes. `report` may be the in-memory [`fit_report`](@ref)
payload or a JSON-loaded payload from [`load_fit_report`](@ref). Passing a fit
object first builds `fit_report(fit; kwargs...)`.
"""
function save_fit_report_bundle(directory::AbstractString,
        report;
        overwrite::Bool = false,
        label = nothing,
        title::AbstractString = "BayesianMGMFRM fit report",
        max_rows::Integer = 6,
        include_empty::Bool = false)
    _check_fit_report_payload(report)
    _check_fit_report_bundle_directory(directory; overwrite)
    mkpath(directory)
    report_path = joinpath(directory, "fit_report.json")
    table_directory = joinpath(directory, "tables")
    markdown_path = joinpath(directory, "fit_report.md")
    report_export = save_fit_report(report_path, report;
        overwrite = true,
        label)
    table_manifest = save_fit_report_tables(table_directory, report;
        overwrite = true,
        label)
    markdown_export = save_fit_report_markdown(markdown_path, report;
        overwrite = true,
        title,
        max_rows,
        include_empty,
        label)
    manifest = _fit_report_bundle_manifest(directory, report_export,
        table_manifest, markdown_export;
        label)
    _write_json_record(joinpath(directory, "manifest.json"), manifest)
    return manifest
end

function save_fit_report_bundle(directory::AbstractString,
        fit::_ModelComparisonFit;
        overwrite::Bool = false,
        label = nothing,
        title::AbstractString = "BayesianMGMFRM fit report",
        max_rows::Integer = 6,
        include_empty::Bool = false,
        kwargs...)
    report = fit_report(fit; kwargs...)
    return save_fit_report_bundle(directory, report;
        overwrite,
        label,
        title,
        max_rows,
        include_empty)
end

function _fit_report_bundle_manifest_path(directory::AbstractString)
    return joinpath(directory, "manifest.json")
end

function _read_json_dict(path::AbstractString, label::AbstractString)
    isfile(path) ||
        throw(ArgumentError("$label does not exist at $path"))
    value = JSON3.read(read(path, String), Dict{String,Any})
    value isa AbstractDict ||
        throw(ArgumentError("$label at $path does not contain a JSON object"))
    return value
end

function _check_fit_report_hash_record(record, field::Symbol, context::AbstractString;
        expected_scope = nothing,
        expected_canonicalization = nothing)
    hash_record = _report_lookup(record, field, _FIT_REPORT_LOOKUP_MISSING)
    (hash_record isa NamedTuple || hash_record isa AbstractDict) ||
        throw(ArgumentError("$context does not contain $(String(field))"))
    algorithm = _report_symbol_value(_report_lookup(hash_record, :algorithm,
        _FIT_REPORT_LOOKUP_MISSING))
    algorithm === :sha256 ||
        throw(ArgumentError("$context has an unsupported $(String(field)) algorithm"))
    value = _report_lookup(hash_record, :value, _FIT_REPORT_LOOKUP_MISSING)
    value isa AbstractString && occursin(r"^[0-9a-f]{64}$", value) ||
        throw(ArgumentError("$context has an invalid $(String(field)) value"))
    if expected_scope !== nothing
        scope = _report_symbol_value(_report_lookup(hash_record, :scope,
            _FIT_REPORT_LOOKUP_MISSING))
        scope === expected_scope ||
            throw(ArgumentError("$context has an unsupported $(String(field)) scope"))
    end
    if expected_canonicalization !== nothing
        canonicalization = _report_symbol_value(_report_lookup(hash_record,
            :canonicalization, _FIT_REPORT_LOOKUP_MISSING))
        canonicalization === expected_canonicalization ||
            throw(ArgumentError("$context has an unsupported $(String(field)) canonicalization"))
    end
    return hash_record
end

function _fit_report_hash_value(record, field::Symbol, context::AbstractString;
        expected_scope = nothing,
        expected_canonicalization = nothing)
    hash_record = _check_fit_report_hash_record(record, field, context;
        expected_scope,
        expected_canonicalization)
    value = _report_lookup(hash_record, :value, _FIT_REPORT_LOOKUP_MISSING)
    return value
end

function _fit_report_bundle_file_record(manifest, role::Symbol,
        context::AbstractString)
    files = _report_lookup(manifest, :files, _FIT_REPORT_LOOKUP_MISSING)
    files isa AbstractVector ||
        throw(ArgumentError("$context does not contain bundle file rows"))
    for file in files
        file_role = _report_symbol_value(_report_lookup(file, :role, missing))
        file_role === role && return file
    end
    throw(ArgumentError("$context does not contain a $(String(role)) file row"))
end

function _fit_report_bundle_file_path(directory::AbstractString, file_record,
        context::AbstractString)
    path = _report_lookup(file_record, :path, _FIT_REPORT_LOOKUP_MISSING)
    path isa AbstractString ||
        throw(ArgumentError("$context file row does not contain a path"))
    if isabspath(path) || occursin('\\', path) || occursin("\0", path)
        throw(ArgumentError("$context file row contains an unsafe path: $path"))
    end
    parts = split(path, '/')
    if isempty(parts) || any(part -> isempty(part) || part == "." || part == "..", parts)
        throw(ArgumentError("$context file row contains an unsafe path: $path"))
    end
    return joinpath(directory, parts...)
end

function _check_fit_report_bundle_manifest(manifest, path)
    manifest isa AbstractDict ||
        throw(ArgumentError("fit report bundle manifest at $path does not contain a JSON object"))
    get(manifest, "schema", nothing) ==
        "bayesianmgmfrm.fit_report_bundle_export.v1" ||
        throw(ArgumentError("fit report bundle manifest at $path has an unsupported schema"))
    _report_symbol_value(get(manifest, "object", nothing)) ===
        :fit_report_bundle_export ||
        throw(ArgumentError("fit report bundle manifest at $path has an unsupported object"))
    _fit_report_hash_value(manifest, :content_hash,
        "fit report bundle manifest at $path";
        expected_scope = :fit_report_bundle_export_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    _fit_report_hash_value(manifest, :report_content_hash,
        "fit report bundle manifest at $path";
        expected_scope = :artifact_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    for (role, scope, canonicalization) in (
        (:report_json, :json_report_without_hash_metadata, :cache_stable_string),
        (:table_manifest, :fit_report_table_export_without_hash_metadata,
            :cache_stable_string),
        (:markdown, :fit_report_markdown, :raw_markdown_string),
    )
        file_record = _fit_report_bundle_file_record(manifest, role,
            "fit report bundle manifest at $path")
        _fit_report_hash_value(file_record, :content_hash,
            "fit report bundle $(String(role)) row at $path";
            expected_scope = scope,
            expected_canonicalization = canonicalization)
    end
    return manifest
end

function _verify_fit_report_bundle_manifest(manifest,
        directory::AbstractString,
        manifest_path::AbstractString)
    expected_manifest_hash = _fit_report_hash_value(manifest, :content_hash,
        "fit report bundle manifest at $manifest_path";
        expected_scope = :fit_report_bundle_export_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    actual_manifest_hash = _fit_report_bundle_hash_record(manifest).value
    isequal(expected_manifest_hash, actual_manifest_hash) ||
        throw(ArgumentError("fit report bundle manifest content hash mismatch for $manifest_path"))

    report_file = _fit_report_bundle_file_record(manifest, :report_json,
        "fit report bundle manifest at $manifest_path")
    report_path = _fit_report_bundle_file_path(directory, report_file,
        "fit report bundle manifest at $manifest_path")
    report_record = load_fit_report(report_path;
        verify_hash = true,
        return_record = true)
    expected_report_json_hash = _fit_report_hash_value(report_file,
        :content_hash, "fit report bundle report_json row at $manifest_path";
        expected_scope = :json_report_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    actual_report_json_hash = _fit_report_hash_value(report_record,
        :json_content_hash, "fit report export at $report_path";
        expected_scope = :json_report_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    isequal(expected_report_json_hash, actual_report_json_hash) ||
        throw(ArgumentError("fit report bundle report JSON hash mismatch for $report_path"))
    expected_report_hash = _fit_report_hash_value(manifest,
        :report_content_hash, "fit report bundle manifest at $manifest_path";
        expected_scope = :artifact_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    actual_report_hash = _fit_report_hash_value(report_record,
        :report_content_hash, "fit report export at $report_path";
        expected_scope = :artifact_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    isequal(expected_report_hash, actual_report_hash) ||
        throw(ArgumentError("fit report bundle report content hash mismatch for $report_path"))

    table_file = _fit_report_bundle_file_record(manifest, :table_manifest,
        "fit report bundle manifest at $manifest_path")
    table_path = _fit_report_bundle_file_path(directory, table_file,
        "fit report bundle manifest at $manifest_path")
    expected_table_path = _fit_report_table_export_manifest_path(dirname(table_path))
    isequal(table_path, expected_table_path) ||
        throw(ArgumentError("fit report bundle table manifest path must resolve to $expected_table_path"))
    table_manifest = load_fit_report_tables(dirname(table_path);
        verify_hash = true,
        return_manifest = true)
    expected_table_hash = _fit_report_hash_value(table_file, :content_hash,
        "fit report bundle table_manifest row at $manifest_path";
        expected_scope = :fit_report_table_export_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    actual_table_hash = _fit_report_hash_value(table_manifest, :content_hash,
        "fit report table manifest at $table_path";
        expected_scope = :fit_report_table_export_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    isequal(expected_table_hash, actual_table_hash) ||
        throw(ArgumentError("fit report bundle table manifest hash mismatch for $table_path"))

    markdown_file = _fit_report_bundle_file_record(manifest, :markdown,
        "fit report bundle manifest at $manifest_path")
    markdown_path = _fit_report_bundle_file_path(directory, markdown_file,
        "fit report bundle manifest at $manifest_path")
    isfile(markdown_path) ||
        throw(ArgumentError("fit report markdown file does not exist at $markdown_path"))
    expected_markdown_hash = _fit_report_hash_value(markdown_file,
        :content_hash, "fit report bundle markdown row at $manifest_path";
        expected_scope = :fit_report_markdown,
        expected_canonicalization = :raw_markdown_string)
    actual_markdown_hash =
        _fit_report_markdown_hash_record(read(markdown_path, String)).value
    isequal(expected_markdown_hash, actual_markdown_hash) ||
        throw(ArgumentError("fit report bundle markdown hash mismatch for $markdown_path"))
    return manifest
end

function _fit_report_bundle_report_path(directory::AbstractString, manifest,
        manifest_path::AbstractString)
    report_file = _fit_report_bundle_file_record(manifest, :report_json,
        "fit report bundle manifest at $manifest_path")
    return _fit_report_bundle_file_path(directory, report_file,
        "fit report bundle manifest at $manifest_path")
end

"""
    load_fit_report_bundle(directory; verify_hash = true,
        return_manifest = false)

Load a fit-report bundle written by [`save_fit_report_bundle`](@ref). By
default this verifies the bundle manifest hash, JSON report export hash, table
manifest and table-file hashes, and Markdown content hash before returning the
loaded `fit_report` payload. Set `return_manifest = true` to inspect the
bundle manifest instead.
"""
function load_fit_report_bundle(directory::AbstractString;
        verify_hash::Bool = true,
        return_manifest::Bool = false)
    isdir(directory) ||
        throw(ArgumentError("fit report bundle directory does not exist at $directory"))
    manifest_path = _fit_report_bundle_manifest_path(directory)
    manifest = _read_json_dict(manifest_path, "fit report bundle manifest")
    manifest = _check_fit_report_bundle_manifest(manifest, manifest_path)
    verify_hash &&
        _verify_fit_report_bundle_manifest(manifest, directory, manifest_path)
    return_manifest && return manifest
    report_path = _fit_report_bundle_report_path(directory, manifest,
        manifest_path)
    return load_fit_report(report_path; verify_hash)
end

function _fit_report_table_export_manifest_path(directory::AbstractString)
    return joinpath(directory, "manifest.json")
end

function _fit_report_table_manifest_rows(manifest, context::AbstractString)
    rows = _report_lookup(manifest, :tables, _FIT_REPORT_LOOKUP_MISSING)
    rows isa AbstractVector ||
        throw(ArgumentError("$context does not contain table rows"))
    return rows
end

function _fit_report_table_manifest_filename(row, context::AbstractString)
    filename = _report_lookup(row, :filename, _FIT_REPORT_LOOKUP_MISSING)
    filename isa AbstractString ||
        throw(ArgumentError("$context table row does not contain a filename"))
    if isempty(filename) || isabspath(filename) || occursin("/", filename) ||
            occursin("\\", filename) || occursin("\0", filename) ||
            filename == "." || filename == ".."
        throw(ArgumentError("$context table row contains an unsafe filename: $filename"))
    end
    return filename
end

function _check_fit_report_table_manifest(manifest, path)
    manifest isa AbstractDict ||
        throw(ArgumentError("fit report table manifest at $path does not contain a JSON object"))
    get(manifest, "schema", nothing) ==
        "bayesianmgmfrm.fit_report_table_export.v1" ||
        throw(ArgumentError("fit report table manifest at $path has an unsupported schema"))
    _report_symbol_value(get(manifest, "object", nothing)) ===
        :fit_report_table_export ||
        throw(ArgumentError("fit report table manifest at $path has an unsupported object"))
    _fit_report_hash_value(manifest, :content_hash,
        "fit report table manifest at $path";
        expected_scope = :fit_report_table_export_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    rows = _fit_report_table_manifest_rows(manifest,
        "fit report table manifest at $path")
    n_tables = _report_lookup(manifest, :n_tables, _FIT_REPORT_LOOKUP_MISSING)
    n_tables isa Integer && n_tables == length(rows) ||
        throw(ArgumentError("fit report table manifest at $path has inconsistent n_tables"))
    seen = Set{String}()
    for row in rows
        filename = _fit_report_table_manifest_filename(row,
            "fit report table manifest at $path")
        filename in seen &&
            throw(ArgumentError("fit report table manifest at $path contains duplicate filename $filename"))
        _fit_report_hash_value(row, :content_hash,
            "fit report table manifest row at $path";
            expected_scope = :fit_report_table_without_hash_metadata,
            expected_canonicalization = :cache_stable_string)
        push!(seen, filename)
    end
    return manifest
end

function _check_fit_report_table_record(record, path)
    record isa AbstractDict ||
        throw(ArgumentError("fit report table at $path does not contain a JSON object"))
    get(record, "schema", nothing) == "bayesianmgmfrm.fit_report_table.v1" ||
        throw(ArgumentError("fit report table at $path has an unsupported schema"))
    _report_symbol_value(get(record, "object", nothing)) === :fit_report_table ||
        throw(ArgumentError("fit report table at $path has an unsupported object"))
    section = _report_symbol_value(_report_lookup(record, :section,
        _FIT_REPORT_LOOKUP_MISSING))
    section isa Symbol ||
        throw(ArgumentError("fit report table at $path does not contain a section"))
    row_field = _report_symbol_value(_report_lookup(record, :row_field,
        _FIT_REPORT_LOOKUP_MISSING))
    row_field isa Symbol ||
        throw(ArgumentError("fit report table at $path does not contain a row_field"))
    rows = _report_lookup(record, :rows, _FIT_REPORT_LOOKUP_MISSING)
    rows isa AbstractVector ||
        throw(ArgumentError("fit report table at $path does not contain rows"))
    n_rows = _report_lookup(record, :n_rows, _FIT_REPORT_LOOKUP_MISSING)
    n_rows isa Integer && n_rows == length(rows) ||
        throw(ArgumentError("fit report table at $path has inconsistent n_rows"))
    _fit_report_hash_value(record, :content_hash,
        "fit report table at $path";
        expected_scope = :fit_report_table_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    return record
end

function _verify_fit_report_table_record(record, path)
    expected = _fit_report_hash_value(record, :content_hash,
        "fit report table at $path";
        expected_scope = :fit_report_table_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    actual = _fit_report_table_hash_record(record;
        scope = :fit_report_table_without_hash_metadata).value
    isequal(expected, actual) ||
        throw(ArgumentError("fit report table content hash mismatch for $path"))
    return record
end

function _verify_fit_report_table_manifest(manifest, path)
    expected = _fit_report_hash_value(manifest, :content_hash,
        "fit report table manifest at $path";
        expected_scope = :fit_report_table_export_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    actual = _fit_report_table_hash_record(manifest;
        scope = :fit_report_table_export_without_hash_metadata).value
    isequal(expected, actual) ||
        throw(ArgumentError("fit report table manifest content hash mismatch for $path"))
    return manifest
end

function _fit_report_table_matches_manifest_row(record, row,
        table_path::AbstractString,
        manifest_path::AbstractString)
    for field in (:section, :row_field)
        expected = _report_symbol_value(_report_lookup(row, field,
            _FIT_REPORT_LOOKUP_MISSING))
        actual = _report_symbol_value(_report_lookup(record, field,
            _FIT_REPORT_LOOKUP_MISSING))
        expected === actual ||
            throw(ArgumentError("fit report table $table_path does not match $(String(field)) in manifest $manifest_path"))
    end
    expected_rows = _report_lookup(row, :n_rows, _FIT_REPORT_LOOKUP_MISSING)
    actual_rows = _report_lookup(record, :n_rows, _FIT_REPORT_LOOKUP_MISSING)
    expected_rows isa Integer && actual_rows isa Integer &&
        expected_rows == actual_rows ||
        throw(ArgumentError("fit report table $table_path does not match n_rows in manifest $manifest_path"))
    expected_hash = _fit_report_hash_value(row, :content_hash,
        "fit report table manifest row at $manifest_path";
        expected_scope = :fit_report_table_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    actual_hash = _fit_report_hash_value(record, :content_hash,
        "fit report table at $table_path";
        expected_scope = :fit_report_table_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    isequal(expected_hash, actual_hash) ||
        throw(ArgumentError("fit report table $table_path does not match content hash in manifest $manifest_path"))
    return true
end

function _load_fit_report_table_records(directory::AbstractString, manifest,
        manifest_path::AbstractString;
        verify_hash::Bool)
    records = Any[]
    total_rows = 0
    for row in _fit_report_table_manifest_rows(manifest,
            "fit report table manifest at $manifest_path")
        filename = _fit_report_table_manifest_filename(row,
            "fit report table manifest at $manifest_path")
        table_path = joinpath(directory, filename)
        record = _read_json_dict(table_path, "fit report table")
        record = _check_fit_report_table_record(record, table_path)
        _fit_report_table_matches_manifest_row(record, row, table_path,
            manifest_path)
        verify_hash && _verify_fit_report_table_record(record, table_path)
        total_rows += _report_lookup(record, :n_rows, 0)
        push!(records, record)
    end
    expected_total_rows = _report_lookup(manifest, :n_rows,
        _FIT_REPORT_LOOKUP_MISSING)
    expected_total_rows isa Integer && expected_total_rows == total_rows ||
        throw(ArgumentError("fit report table manifest at $manifest_path has inconsistent n_rows"))
    return records
end

"""
    load_fit_report_tables(directory; verify_hash = true,
        return_manifest = false)

Load a fit-report table export written by [`save_fit_report_tables`](@ref).
By default this verifies the table manifest hash and each table file hash, then
returns a vector of JSON-loaded table records. Set `return_manifest = true` to
inspect the export manifest instead.
"""
function load_fit_report_tables(directory::AbstractString;
        verify_hash::Bool = true,
        return_manifest::Bool = false)
    isdir(directory) ||
        throw(ArgumentError("fit report table export directory does not exist at $directory"))
    manifest_path = _fit_report_table_export_manifest_path(directory)
    manifest = _read_json_dict(manifest_path, "fit report table manifest")
    manifest = _check_fit_report_table_manifest(manifest, manifest_path)
    verify_hash && _verify_fit_report_table_manifest(manifest, manifest_path)
    records = if verify_hash || !return_manifest
        _load_fit_report_table_records(directory, manifest, manifest_path;
            verify_hash)
    else
        nothing
    end
    return_manifest && return manifest
    return records
end

function _cache_stable_write(io::IO, value)
    if value isa NamedTuple
        print(io, "NamedTuple(")
        first_field = true
        for name in keys(value)
            first_field || print(io, ",")
            first_field = false
            print(io, String(name), "=")
            _cache_stable_write(io, getproperty(value, name))
        end
        print(io, ")")
    elseif value isa AbstractDict
        print(io, "Dict(")
        pairs = collect(value)
        sort!(pairs; by = pair -> _cache_stable_string(first(pair)))
        for (index, pair) in enumerate(pairs)
            index == 1 || print(io, ",")
            _cache_stable_write(io, first(pair))
            print(io, "=>")
            _cache_stable_write(io, last(pair))
        end
        print(io, ")")
    elseif value isa Tuple
        print(io, "(")
        for index in eachindex(value)
            index == firstindex(value) || print(io, ",")
            _cache_stable_write(io, value[index])
        end
        print(io, ")")
    elseif value isa AbstractArray
        print(io, "Array(size=")
        _cache_stable_write(io, size(value))
        print(io, ",values=[")
        values = collect(value)
        for index in eachindex(values)
            index == firstindex(values) || print(io, ",")
            _cache_stable_write(io, values[index])
        end
        print(io, "])")
    elseif value isa Symbol
        print(io, ":", String(value))
    elseif value isa AbstractString
        show(io, value)
    elseif value === missing
        print(io, "missing")
    elseif value === nothing
        print(io, "nothing")
    elseif value isa Bool || value isa Number
        show(io, value)
    else
        show(io, value)
    end
    return nothing
end

function _cache_stable_string(value)
    io = IOBuffer()
    _cache_stable_write(io, value)
    return String(take!(io))
end

function _cache_hash(value)
    return bytes2hex(sha256(codeunits(_cache_stable_string(value))))
end

const _ARTIFACT_HASH_METADATA_FIELDS = (:content_hash, :archive_manifest)

function _artifact_hash_payload(value)
    if value isa NamedTuple
        names = Symbol[]
        values = Any[]
        for name in keys(value)
            name in _ARTIFACT_HASH_METADATA_FIELDS && continue
            push!(names, name)
            push!(values, _artifact_hash_payload(getproperty(value, name)))
        end
        return NamedTuple{Tuple(names)}(Tuple(values))
    elseif value isa AbstractDict
        out = Dict{Any,Any}()
        for (key, item) in value
            (key === :content_hash || key === :archive_manifest ||
                key == "content_hash" || key == "archive_manifest") && continue
            out[key] = _artifact_hash_payload(item)
        end
        return out
    elseif value isa Tuple
        return map(_artifact_hash_payload, value)
    elseif value isa AbstractArray
        return map(_artifact_hash_payload, value)
    end
    return value
end

"""
    artifact_content_hash(artifact)

Return a stable SHA-256 content hash for an exported fit artifact or report
bundle. The hash is computed from the package's cache-stable representation
after recursively removing `content_hash` and `archive_manifest` metadata
fields, so the value can be stored with an export and recomputed later for
verification.
"""
function artifact_content_hash(artifact)
    return _cache_hash(_artifact_hash_payload(artifact))
end

function _artifact_content_hash_record(artifact)
    payload = _artifact_hash_payload(artifact)
    canonical = _cache_stable_string(payload)
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(codeunits(canonical))),
        scope = :artifact_without_hash_metadata,
        canonicalization = :cache_stable_string,
        n_canonical_bytes = sizeof(canonical),
    )
end

function _artifact_summary(artifact)
    return (;
        schema = _nt_get(artifact, :schema, missing),
        object = _nt_get(artifact, :object, missing),
        family = _nt_get(artifact, :family, missing),
        scope = _nt_get(artifact, :scope, missing),
        status = _nt_get(artifact, :status, missing),
        created_at = _nt_get(artifact, :created_at, missing),
    )
end

function _manifest_archive_summary(artifact)
    manifest = _nt_get(artifact, :manifest, nothing)
    manifest isa NamedTuple || return nothing
    fit_record = _nt_get(manifest, :fit, NamedTuple())
    diagnostics = _nt_get(manifest, :diagnostics, NamedTuple())
    return (;
        schema = _nt_get(manifest, :schema, missing),
        object = _nt_get(manifest, :object, missing),
        family = _nt_get(manifest, :family, _nt_get(fit_record, :family, missing)),
        scope = _nt_get(manifest, :scope, _nt_get(fit_record, :scope, missing)),
        data_signature =
            _nt_get(_nt_get(manifest, :validation, NamedTuple()), :data_signature,
                _nt_get(fit_record, :data_signature, missing)),
        n_draws = _nt_get(fit_record, :n_draws, missing),
        n_chains = _nt_get(fit_record, :n_chains, missing),
        backend = _nt_get(fit_record, :backend, missing),
        sampler = _nt_get(fit_record, :sampler, missing),
        diagnostic_flag = _nt_get(diagnostics, :flag,
            _nt_get(_nt_get(_nt_get(artifact, :diagnostics, NamedTuple()), :summary, NamedTuple()),
                :flag, missing)),
    )
end

"""
    fit_archive_manifest(artifact; label = nothing, source_path = nothing)
    fit_archive_manifest(fit; kwargs...)

Return a compact long-term archive manifest for a fit artifact. The manifest
records the artifact schema, an embedded SHA-256 content hash, selected
fit/diagnostic metadata, and optional archive labels or source paths. Passing a
fit object first builds its `fit_artifact` with the supplied artifact keywords.
"""
function fit_archive_manifest(artifact::NamedTuple;
        label = nothing,
        source_path = nothing)
    hash_record = _artifact_content_hash_record(artifact)
    return (;
        schema = "bayesianmgmfrm.fit_archive_manifest.v1",
        object = :fit_archive_manifest,
        created_at = string(now()),
        label = label === nothing ? missing : label,
        source_path = source_path === nothing ? missing : String(source_path),
        content_hash = hash_record,
        artifact = _artifact_summary(artifact),
        manifest = _manifest_archive_summary(artifact),
        reproducibility = _nt_get(artifact, :reproducibility, missing),
        archive_policy = (;
            intended_use = :long_term_export_manifest,
            includes_draws =
                _nt_get(_nt_get(artifact, :reproducibility, NamedTuple()),
                    :artifact_policy, NamedTuple()),
            cache_portability = :manifest_and_tables_preferred_cross_version,
        ),
    )
end

function _with_archive_metadata(artifact::NamedTuple;
        label = nothing,
        source_path = nothing)
    archive = fit_archive_manifest(artifact; label, source_path)
    return merge(artifact, (;
        content_hash = archive.content_hash,
        archive_manifest = archive,
    ))
end

function fit_archive_manifest(fit;
        label = nothing,
        source_path = nothing,
        artifact = nothing,
        include_draws::Bool = false,
        include_log_posterior::Bool = include_draws,
        include_sampler_stats::Bool = false,
        include_environment::Bool = true,
        include_packages::Bool = false,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    fit_artifact_value = artifact === nothing ?
        fit_artifact(fit;
            include_draws,
            include_log_posterior,
            include_sampler_stats,
            include_environment,
            include_packages,
            split_chains,
            rhat_threshold,
            ess_threshold) :
        artifact
    return fit_archive_manifest(fit_artifact_value; label, source_path)
end

function _prior_cache_record(prior::MFRMPrior)
    return (;
        person_sd = prior.person_sd,
        rater_sd = prior.rater_sd,
        item_sd = prior.item_sd,
        step_sd = prior.step_sd,
    )
end

function _require_cache_replayable_rng(rng_control::NamedTuple)
    _nt_get(rng_control, :replayable, false) === true ||
        throw(ArgumentError(
            "fit cache keys require a replayable RNG seed; pass seed = <integer> " *
            "or use fit/save_fit_cache manually for unseeded exploratory fits",
        ))
    return nothing
end

function _fit_cache_controls(backend::Symbol,
        ndraws::Int,
        warmup::Int,
        chains::Int,
        step_size::Real,
        rng_control::NamedTuple,
        initial::Vector{Float64};
        target_accept::Real,
        max_depth::Int,
        max_energy_error::Real,
        metric::Symbol,
        ad_backend::Symbol,
        init_jitter::Real)
    initialization = (;
        n_parameters = length(initial),
        hash = _cache_hash(initial),
    )
    if backend === :julia
        return (;
            backend,
            sampler = :random_walk_metropolis,
            ndraws,
            warmup,
            chains,
            step_size = Float64(step_size),
            rng = rng_control,
            initialization,
            init_jitter = 0.0,
        )
    elseif backend === :advancedhmc
        gradient_backend = _gradient_backend_kind(ad_backend)
        return (;
            backend,
            sampler = :nuts,
            ndraws,
            warmup,
            chains,
            step_size = Float64(step_size),
            target_accept = Float64(target_accept),
            max_depth,
            max_energy_error = Float64(max_energy_error),
            metric,
            ad_backend,
            gradient_backend,
            rng = rng_control,
            initialization,
            init_jitter = Float64(init_jitter),
        )
    elseif backend === :turing
        _turing_adtype(ad_backend)
        _turing_metric_type(metric)
        return (;
            backend,
            sampler = :nuts,
            ndraws,
            warmup,
            chains,
            step_size = Float64(step_size),
            target_accept = Float64(target_accept),
            max_depth,
            max_energy_error = Float64(max_energy_error),
            metric,
            ad_backend,
            gradient_backend = :ad,
            rng = rng_control,
            initialization,
            init_jitter = Float64(init_jitter),
            turing_model = :mfrm_logdensity_flat_parameter_model,
            chain_type = :raw_transitions,
            discard_initial = _turing_discard_initial(warmup),
        )
    end
    throw(ArgumentError("backend must be :julia, :advancedhmc, or :turing"))
end

function _fit_cache_request(design::FacetDesign;
        prior::MFRMPrior = MFRMPrior(),
        backend::Symbol = :julia,
        ndraws::Int = 1000,
        warmup::Int = 1000,
        chains::Int = 1,
        step_size::Real = 0.05,
        init = nothing,
        rng::AbstractRNG = Random.default_rng(),
        seed = nothing,
        target_accept::Real = 0.8,
        max_depth::Int = 10,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        progress::Bool = false)
    initial = _fit_initial_params(design, init)
    _, rng_control = _fit_rng(rng, seed)
    _require_cache_replayable_rng(rng_control)
    controls = _fit_cache_controls(backend, ndraws, warmup, chains, step_size,
        rng_control, initial;
        target_accept,
        max_depth,
        max_energy_error,
        metric,
        ad_backend,
        init_jitter)
    return (;
        schema = "bayesianmgmfrm.fit_request.v1",
        julia_version = string(VERSION),
        data_signature = design.spec.validation.data_signature,
        manifest = model_manifest(design),
        prior = _prior_cache_record(prior),
        controls,
    )
end

"""
    fit_cache_key(spec_or_design; kwargs...)

Return the deterministic cache key used by [`cached_fit`](@ref). The key hashes
the data/spec/design manifest, prior scales, backend-specific sampler controls,
RNG seed metadata, Julia version, and initial-parameter hash. The `progress`
keyword is accepted for API symmetry with [`fit`](@ref) but is not included in
the key because it does not affect posterior draws. Cache keys require
`seed = <integer>` so automatic cache reuse is tied to a replayable fit request.
"""
function fit_cache_key(design::FacetDesign; kwargs...)
    return _cache_hash(_fit_cache_request(design; kwargs...))
end

fit_cache_key(spec::FacetSpec; kwargs...) =
    fit_cache_key(getdesign(spec); kwargs...)

function _fit_cache_record(fit::MFRMFit;
        cache_key,
        artifact,
        source_path = nothing)
    archive_manifest = fit_archive_manifest(artifact;
        label = :fit_cache_artifact,
        source_path)
    return (;
        schema = "bayesianmgmfrm.fit_cache.v1",
        object = :fit_cache,
        created_at = string(now()),
        serialization = (;
            format = :julia_serialization,
            julia_version = string(VERSION),
            portability = :same_julia_major_minor_recommended,
        ),
        cache_key = cache_key === nothing ? missing : String(cache_key),
        artifact_content_hash = archive_manifest.content_hash,
        archive_manifest,
        fit,
        artifact,
    )
end

function _fit_cache_artifact(fit::MFRMFit;
        artifact_include_draws::Bool,
        artifact_include_log_posterior::Bool,
        artifact_include_sampler_stats::Bool,
        artifact_include_environment::Bool,
        artifact_include_packages::Bool,
        artifact_split_chains::Bool,
        artifact_rhat_threshold::Real,
        artifact_ess_threshold::Real)
    return fit_artifact(fit;
        include_draws = artifact_include_draws,
        include_log_posterior = artifact_include_log_posterior,
        include_sampler_stats = artifact_include_sampler_stats,
        include_environment = artifact_include_environment,
        include_packages = artifact_include_packages,
        split_chains = artifact_split_chains,
        rhat_threshold = artifact_rhat_threshold,
        ess_threshold = artifact_ess_threshold)
end

"""
    save_fit_cache(path, fit::MFRMFit; cache_key = nothing, overwrite = false,
                   artifact = nothing, ...)

Serialize a fitted object and a reproducibility artifact to `path` using
Julia's standard `Serialization` format. This is intended as an RDS-like cache
for avoiding recomputation in the same Julia analysis environment. The cache
contains the full `MFRMFit` object; artifact draw duplication is omitted by
default unless requested with the `artifact_include_*` keywords.
"""
function save_fit_cache(path::AbstractString,
        fit::MFRMFit;
        cache_key = nothing,
        overwrite::Bool = false,
        artifact = nothing,
        artifact_include_draws::Bool = false,
        artifact_include_log_posterior::Bool = artifact_include_draws,
        artifact_include_sampler_stats::Bool = false,
        artifact_include_environment::Bool = false,
        artifact_include_packages::Bool = false,
        artifact_split_chains::Bool = true,
        artifact_rhat_threshold::Real = 1.01,
        artifact_ess_threshold::Real = 400)
    isfile(path) && !overwrite &&
        throw(ArgumentError("fit cache already exists at $path; pass overwrite = true to replace it"))
    cache_artifact = artifact === nothing ?
        _fit_cache_artifact(fit;
            artifact_include_draws,
            artifact_include_log_posterior,
            artifact_include_sampler_stats,
            artifact_include_environment,
            artifact_include_packages,
            artifact_split_chains,
            artifact_rhat_threshold,
            artifact_ess_threshold) :
        artifact
    record = _fit_cache_record(fit;
        cache_key,
        artifact = cache_artifact,
        source_path = path)
    mkpath(dirname(path))
    open(path, "w") do io
        serialize(io, record)
    end
    return record
end

function _check_fit_cache_record(record, path)
    record isa NamedTuple ||
        throw(ArgumentError("fit cache at $path does not contain a NamedTuple record"))
    _nt_get(record, :schema, nothing) == "bayesianmgmfrm.fit_cache.v1" ||
        throw(ArgumentError("fit cache at $path has an unsupported schema"))
    _nt_get(record, :object, nothing) === :fit_cache ||
        throw(ArgumentError("fit cache at $path has an unsupported object"))
    _nt_get(record, :fit, nothing) isa MFRMFit ||
        throw(ArgumentError("fit cache at $path does not contain an MFRMFit"))
    _nt_get(record, :artifact, nothing) isa NamedTuple ||
        throw(ArgumentError("fit cache at $path does not contain a fit artifact"))
    _cache_hash_value(record, :artifact_content_hash,
        "fit cache at $path")
    archive = _nt_get(record, :archive_manifest, nothing)
    archive isa NamedTuple ||
        throw(ArgumentError("fit cache at $path does not contain an archive manifest"))
    _cache_hash_value(archive, :content_hash,
        "fit cache archive manifest at $path")
    _check_optional_cache_hash_value(record.artifact, :content_hash,
        "fit cache artifact at $path")
    artifact_archive = _nt_get(record.artifact, :archive_manifest, nothing)
    if artifact_archive !== nothing
        artifact_archive isa NamedTuple ||
            throw(ArgumentError("fit cache artifact at $path has an invalid archive manifest"))
        _cache_hash_value(artifact_archive, :content_hash,
            "fit cache artifact archive manifest at $path")
    end
    return record
end

function _cache_hash_value(record::NamedTuple,
        field::Symbol,
        context::AbstractString;
        expected_scope::Symbol = :artifact_without_hash_metadata,
        expected_canonicalization::Symbol = :cache_stable_string)
    hash_record = _nt_get(record, field, nothing)
    hash_record isa NamedTuple ||
        throw(ArgumentError("$context does not contain $(String(field))"))
    _nt_get(hash_record, :algorithm, nothing) === :sha256 ||
        throw(ArgumentError("$context has an unsupported $(String(field)) algorithm"))
    value = _nt_get(hash_record, :value, nothing)
    value isa AbstractString && occursin(r"^[0-9a-f]{64}$", value) ||
        throw(ArgumentError("$context has an invalid $(String(field)) value"))
    _nt_get(hash_record, :scope, nothing) === expected_scope ||
        throw(ArgumentError("$context has an unsupported $(String(field)) scope"))
    _nt_get(hash_record, :canonicalization, nothing) === expected_canonicalization ||
        throw(ArgumentError("$context has an unsupported $(String(field)) canonicalization"))
    return value
end

function _check_optional_cache_hash_value(record::NamedTuple,
        field::Symbol,
        context::AbstractString)
    _nt_get(record, field, nothing) === nothing && return nothing
    _cache_hash_value(record, field, context)
    return nothing
end

function _verify_fit_cache_record(record::NamedTuple, path::AbstractString)
    expected = _cache_hash_value(record, :artifact_content_hash,
        "fit cache at $path")
    actual = artifact_content_hash(record.artifact)
    isequal(expected, actual) ||
        throw(ArgumentError("fit cache artifact content hash mismatch for $path"))
    embedded_hash = _nt_get(record.artifact, :content_hash, nothing)
    if embedded_hash isa NamedTuple
        embedded = _cache_hash_value(record.artifact, :content_hash,
            "fit cache artifact at $path")
        isequal(embedded, actual) ||
            throw(ArgumentError("fit cache embedded artifact hash mismatch for $path"))
    end
    archive = _nt_get(record, :archive_manifest, nothing)
    archive isa NamedTuple ||
        throw(ArgumentError("fit cache at $path does not contain an archive manifest"))
    archive_hash = _cache_hash_value(archive, :content_hash,
        "fit cache archive manifest at $path")
    isequal(archive_hash, actual) ||
        throw(ArgumentError("fit cache archive manifest hash mismatch for $path"))
    artifact_archive = _nt_get(record.artifact, :archive_manifest, nothing)
    if artifact_archive isa NamedTuple
        artifact_archive_hash = _cache_hash_value(artifact_archive,
            :content_hash, "fit cache artifact archive manifest at $path")
        isequal(artifact_archive_hash, actual) ||
            throw(ArgumentError("fit cache artifact archive manifest hash mismatch for $path"))
    end
    return record
end

"""
    load_fit_cache(path; expected_cache_key = nothing, verify_hash = true,
                   return_record = false)

Load a serialized fit cache. By default the cached `MFRMFit` is returned. Set
`return_record = true` to inspect the cache metadata and artifact. When
`expected_cache_key` is supplied, loading fails unless the stored key matches.
By default loading also verifies the stored artifact content hash and archive
manifest hashes, while cache/hash metadata shape is always checked. Set
`verify_hash = false` to inspect an older or exploratory cache record with an
artifact payload hash mismatch.
"""
function load_fit_cache(path::AbstractString;
        expected_cache_key = nothing,
        verify_hash::Bool = true,
        return_record::Bool = false)
    isfile(path) ||
        throw(ArgumentError("fit cache does not exist at $path"))
    record = open(path, "r") do io
        deserialize(io)
    end
    record = _check_fit_cache_record(record, path)
    if expected_cache_key !== nothing && !isequal(record.cache_key, String(expected_cache_key))
        throw(ArgumentError("fit cache key mismatch for $path; pass refresh = true to recompute and replace it"))
    end
    verify_hash && _verify_fit_cache_record(record, path)
    return return_record ? record : record.fit
end

function _check_cache_path(cache_path)
    cache_path === nothing &&
        throw(ArgumentError("cache_path is required"))
    return String(cache_path)
end

"""
    cached_fit(spec_or_design; cache_path, refresh = false, return_record = false,
               kwargs...)

Fit with an RDS-like serialized cache. Automatic cache keys require
`seed = <integer>` so cache reuse is tied to replayable posterior draws. If
`cache_path` exists and its cache key matches the current data/spec/design,
prior, sampler controls, seed, Julia version, and initialization hash, the
cached fit is returned without recomputation. If the file is absent, or
`refresh = true`, the model is fit and the result is saved. A key mismatch
raises an error rather than silently reusing stale draws.
"""
function cached_fit(design::FacetDesign;
        cache_path = nothing,
        refresh::Bool = false,
        return_record::Bool = false,
        prior::MFRMPrior = MFRMPrior(),
        backend::Symbol = :julia,
        ndraws::Int = 1000,
        warmup::Int = 1000,
        chains::Int = 1,
        step_size::Real = 0.05,
        init = nothing,
        rng::AbstractRNG = Random.default_rng(),
        seed = nothing,
        target_accept::Real = 0.8,
        max_depth::Int = 10,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        progress::Bool = false,
        artifact_include_draws::Bool = false,
        artifact_include_log_posterior::Bool = artifact_include_draws,
        artifact_include_sampler_stats::Bool = false,
        artifact_include_environment::Bool = false,
        artifact_include_packages::Bool = false,
        artifact_split_chains::Bool = true,
        artifact_rhat_threshold::Real = 1.01,
        artifact_ess_threshold::Real = 400)
    path = _check_cache_path(cache_path)
    key = fit_cache_key(design;
        prior,
        backend,
        ndraws,
        warmup,
        chains,
        step_size,
        init,
        rng,
        seed,
        target_accept,
        max_depth,
        max_energy_error,
        metric,
        ad_backend,
        init_jitter,
        progress)
    if isfile(path) && !refresh
        record = load_fit_cache(path; expected_cache_key = key, return_record = true)
        return return_record ? record : record.fit
    end
    fit_result = fit(design;
        prior,
        backend,
        ndraws,
        warmup,
        chains,
        step_size,
        init,
        rng,
        seed,
        target_accept,
        max_depth,
        max_energy_error,
        metric,
        ad_backend,
        init_jitter,
        progress)
    record = save_fit_cache(path, fit_result;
        cache_key = key,
        overwrite = true,
        artifact_include_draws,
        artifact_include_log_posterior,
        artifact_include_sampler_stats,
        artifact_include_environment,
        artifact_include_packages,
        artifact_split_chains,
        artifact_rhat_threshold,
        artifact_ess_threshold)
    return return_record ? record : fit_result
end

cached_fit(spec::FacetSpec; kwargs...) =
    cached_fit(getdesign(spec); kwargs...)

function _column_mean(xs::AbstractVector{<:Real})
    isempty(xs) && return NaN
    return sum(Float64, xs) / length(xs)
end

function _column_sd(xs::AbstractVector{<:Real}, mean::Float64)
    n = length(xs)
    n <= 1 && return NaN
    ss = 0.0
    for x in xs
        d = Float64(x) - mean
        ss += d * d
    end
    return sqrt(ss / (n - 1))
end

function _quantile_sorted(sorted::Vector{Float64}, p::Real)
    0 <= p <= 1 || throw(ArgumentError("quantile probabilities must be in [0, 1]"))
    n = length(sorted)
    n == 0 && return NaN
    n == 1 && return sorted[1]
    pos = 1 + (n - 1) * Float64(p)
    lo = floor(Int, pos)
    hi = ceil(Int, pos)
    lo == hi && return sorted[lo]
    w = pos - lo
    return (1 - w) * sorted[lo] + w * sorted[hi]
end

function _check_posterior_summary_bounds(lower::Real, upper::Real)
    0 <= lower < 0.5 || throw(ArgumentError("lower must be in [0, 0.5)"))
    0.5 < upper <= 1 || throw(ArgumentError("upper must be in (0.5, 1]"))
    return Float64(lower), Float64(upper)
end

function _posterior_interval_probabilities(intervals::Nothing)
    return Float64[]
end

function _posterior_interval_probabilities(intervals::Real)
    isfinite(intervals) && 0 < intervals < 1 ||
        throw(ArgumentError("interval probabilities must be finite and in (0, 1)"))
    return [Float64(intervals)]
end

function _posterior_interval_probabilities(intervals)
    probabilities = Float64[]
    for interval in intervals
        isfinite(interval) && 0 < interval < 1 ||
            throw(ArgumentError("interval probabilities must be finite and in (0, 1)"))
        push!(probabilities, Float64(interval))
    end
    return probabilities
end

function _posterior_interval_rows(sorted::Vector{Float64},
        probabilities::AbstractVector{Float64})
    rows = NamedTuple[]
    for probability in probabilities
        lower_probability = (1 - probability) / 2
        upper_probability = 1 - lower_probability
        lower = _quantile_sorted(sorted, lower_probability)
        upper = _quantile_sorted(sorted, upper_probability)
        push!(rows, (;
            probability,
            lower,
            upper,
            lower_probability,
            upper_probability,
            width = upper - lower,
        ))
    end
    return Tuple(rows)
end

function _posterior_direction_summary(values::AbstractVector{Float64},
        reference::Float64)
    n = length(values)
    positive = count(>(reference), values) / n
    negative = count(<(reference), values) / n
    equal = 1 - positive - negative
    direction = positive == negative ? :undetermined :
        (positive > negative ? :positive : :negative)
    return (;
        reference,
        probability_positive = positive,
        probability_negative = negative,
        probability_equal = equal,
        probability_of_direction = max(positive, negative),
        direction,
    )
end

function _posterior_rope_bounds(rope::Nothing)
    return nothing
end

function _posterior_rope_bounds(rope::Real)
    isfinite(rope) && rope >= 0 ||
        throw(ArgumentError("rope must be nothing, a finite non-negative radius, or a finite two-value interval"))
    radius = Float64(rope)
    return (-radius, radius)
end

function _posterior_rope_bounds(rope::Pair)
    return _posterior_rope_bounds((rope.first, rope.second))
end

function _posterior_rope_bounds(rope)
    length(rope) == 2 ||
        throw(ArgumentError("rope interval must contain exactly two values"))
    lower, upper = Float64(rope[1]), Float64(rope[2])
    isfinite(lower) && isfinite(upper) && lower <= upper ||
        throw(ArgumentError("rope interval must be finite with lower <= upper"))
    return (lower, upper)
end

function _posterior_rope_summary(values::AbstractVector{Float64},
        rope_bounds,
        rope_probability_threshold::Float64)
    rope_bounds === nothing && return (;
        rope_lower = nothing,
        rope_upper = nothing,
        probability_in_rope = nothing,
        probability_below_rope = nothing,
        probability_above_rope = nothing,
        practical_equivalence = :not_requested,
    )

    lower, upper = rope_bounds
    n = length(values)
    in_rope = count(value -> lower <= value <= upper, values) / n
    below_rope = count(<(lower), values) / n
    above_rope = count(>(upper), values) / n
    practical_equivalence =
        in_rope >= rope_probability_threshold ? :inside_rope :
        max(below_rope, above_rope) >= rope_probability_threshold ? :outside_rope :
        :mixed
    return (;
        rope_lower = lower,
        rope_upper = upper,
        probability_in_rope = in_rope,
        probability_below_rope = below_rope,
        probability_above_rope = above_rope,
        practical_equivalence,
    )
end

function _posterior_summary_rows(draws::AbstractMatrix{<:Real},
        parameter_names;
        lower::Real,
        upper::Real,
        intervals,
        reference::Real,
        rope,
        rope_probability_threshold::Real)
    lower_probability, upper_probability =
        _check_posterior_summary_bounds(lower, upper)
    interval_probabilities = _posterior_interval_probabilities(intervals)
    isfinite(reference) ||
        throw(ArgumentError("reference must be finite"))
    isfinite(rope_probability_threshold) && 0 < rope_probability_threshold <= 1 ||
        throw(ArgumentError("rope_probability_threshold must be finite and in (0, 1]"))
    reference_value = Float64(reference)
    rope_bounds = _posterior_rope_bounds(rope)
    checked_rope_probability_threshold = Float64(rope_probability_threshold)
    size(draws, 2) == length(parameter_names) ||
        throw(ArgumentError("parameter name count does not match draw columns"))
    rows = NamedTuple[]
    for j in axes(draws, 2)
        vals = Float64.(draws[:, j])
        sorted = sort(vals)
        m = _column_mean(vals)
        push!(rows, (;
            parameter = parameter_names[j],
            mean = m,
            sd = _column_sd(vals, m),
            median = _quantile_sorted(sorted, 0.5),
            lower = _quantile_sorted(sorted, lower_probability),
            upper = _quantile_sorted(sorted, upper_probability),
            lower_probability,
            upper_probability,
            intervals = _posterior_interval_rows(sorted, interval_probabilities),
            _posterior_direction_summary(vals, reference_value)...,
            _posterior_rope_summary(
                vals,
                rope_bounds,
                checked_rope_probability_threshold,
            )...,
            rope_probability_threshold =
                rope_bounds === nothing ? nothing : checked_rope_probability_threshold,
            n_draws = length(vals),
        ))
    end
    return rows
end

"""
    posterior_summary(fit; lower = 0.025, upper = 0.975,
        intervals = (0.66, 0.9, 0.95), reference = 0.0,
        rope = nothing, rope_probability_threshold = 0.95)

Summarize posterior draws for each parameter. Rows retain the legacy
`lower`/`upper` interval columns and also include central credible intervals,
probability of direction relative to `reference`, and optional ROPE/practical
equivalence probabilities. Pass `rope = r` for a symmetric `[-r, r]` ROPE or
`rope = (lower, upper)` for an explicit interval.
"""
function posterior_summary(fit::MFRMFit;
        lower::Real = 0.025,
        upper::Real = 0.975,
        intervals = (0.66, 0.9, 0.95),
        reference::Real = 0.0,
        rope = nothing,
        rope_probability_threshold::Real = 0.95)
    return _posterior_summary_rows(
        fit.draws,
        fit.design.parameter_names;
        lower,
        upper,
        intervals,
        reference,
        rope,
        rope_probability_threshold,
    )
end

function posterior_summary(fit::GMFRMFit;
        lower::Real = 0.025,
        upper::Real = 0.975,
        intervals = (0.66, 0.9, 0.95),
        reference::Real = 0.0,
        rope = nothing,
        rope_probability_threshold::Real = 0.95)
    return _posterior_summary_rows(
        fit.draws,
        fit.diagnostic_surface.raw_parameter_names;
        lower,
        upper,
        intervals,
        reference,
        rope,
        rope_probability_threshold,
    )
end

function direct_posterior_summary(fit::GMFRMFit;
        lower::Real = 0.025,
        upper::Real = 0.975,
        intervals = (0.66, 0.9, 0.95),
        reference::Real = 0.0,
        rope = nothing,
        rope_probability_threshold::Real = 0.95)
    return _posterior_summary_rows(
        fit.direct_draws,
        fit.diagnostic_surface.direct_parameter_names;
        lower,
        upper,
        intervals,
        reference,
        rope,
        rope_probability_threshold,
    )
end

function posterior_summary(fit::MGMFRMFit;
        lower::Real = 0.025,
        upper::Real = 0.975,
        intervals = (0.66, 0.9, 0.95),
        reference::Real = 0.0,
        rope = nothing,
        rope_probability_threshold::Real = 0.95)
    return _posterior_summary_rows(
        fit.draws,
        fit.diagnostic_surface.raw_parameter_names;
        lower,
        upper,
        intervals,
        reference,
        rope,
        rope_probability_threshold,
    )
end

function direct_posterior_summary(fit::MGMFRMFit;
        lower::Real = 0.025,
        upper::Real = 0.975,
        intervals = (0.66, 0.9, 0.95),
        reference::Real = 0.0,
        rope = nothing,
        rope_probability_threshold::Real = 0.95)
    return _posterior_summary_rows(
        fit.direct_draws,
        fit.diagnostic_surface.direct_parameter_names;
        lower,
        upper,
        intervals,
        reference,
        rope,
        rope_probability_threshold,
    )
end

"""
    pointwise_loglikelihood_matrix(fit::MFRMFit)
    pointwise_loglikelihood_matrix(design::FacetDesign, draws)

Evaluate a draws-by-observations pointwise log-likelihood matrix for posterior
summaries, posterior predictive checks, and future model-comparison helpers.
"""
function pointwise_loglikelihood_matrix(design::FacetDesign, draws::AbstractMatrix)
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    out = Matrix{Float64}(undef, size(draws, 1), design.spec.data.n)
    for i in axes(draws, 1)
        out[i, :] .= pointwise_loglikelihood(design, @view draws[i, :])
    end
    return out
end

pointwise_loglikelihood_matrix(fit::MFRMFit) =
    pointwise_loglikelihood_matrix(fit.design, fit.draws)

pointwise_loglikelihood_matrix(fit::GMFRMFit) =
    copy(fit.direct_pointwise_loglikelihood)

pointwise_loglikelihood_matrix(fit::MGMFRMFit) =
    copy(fit.direct_pointwise_loglikelihood)

function _logmeanexp(values::AbstractVector{<:Real})
    isempty(values) && throw(ArgumentError("values must not be empty"))
    vals = Float64.(values)
    all(isfinite, vals) || throw(ArgumentError("values contain non-finite entries"))
    max_value = maximum(vals)
    return max_value + log(sum(exp(value - max_value) for value in vals) / length(vals))
end

function _sample_variance(values::AbstractVector{<:Real})
    n = length(values)
    n >= 2 || throw(ArgumentError("at least two posterior draws are required"))
    mean_value = _column_mean(values)
    ss = 0.0
    for value in values
        d = Float64(value) - mean_value
        ss += d * d
    end
    return ss / (n - 1)
end

function _pointwise_se(values::AbstractVector{<:Real})
    n = length(values)
    n <= 1 && return NaN
    return sqrt(n * _sample_variance(values))
end

"""
    waic(fit::MFRMFit; ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    waic(design::FacetDesign, draws)
    waic(loglik::AbstractMatrix)

Compute the widely applicable information criterion (WAIC) from posterior
pointwise log-likelihood draws. The log-likelihood matrix must have dimensions
draws-by-observations. The returned named tuple includes `elpd_waic`,
`p_waic`, `lppd`, `waic`, standard errors, and pointwise components.
"""
function waic(loglik::AbstractMatrix)
    n_draws, n_observations = size(loglik)
    n_draws >= 2 || throw(ArgumentError("WAIC requires at least two posterior draws"))
    n_observations >= 1 || throw(ArgumentError("WAIC requires at least one observation"))
    all(value -> isfinite(Float64(value)), loglik) ||
        throw(ArgumentError("loglik contains non-finite values"))

    point_lppd = Vector{Float64}(undef, n_observations)
    point_p_waic = Vector{Float64}(undef, n_observations)
    point_elpd = Vector{Float64}(undef, n_observations)
    point_waic = Vector{Float64}(undef, n_observations)

    for observation in 1:n_observations
        values = @view loglik[:, observation]
        point_lppd[observation] = _logmeanexp(values)
        point_p_waic[observation] = _sample_variance(values)
        point_elpd[observation] = point_lppd[observation] - point_p_waic[observation]
        point_waic[observation] = -2 * point_elpd[observation]
    end

    lppd = sum(point_lppd)
    p_waic = sum(point_p_waic)
    elpd_waic = sum(point_elpd)
    waic_value = sum(point_waic)
    high_variance_count = count(>(0.4), point_p_waic)
    return (;
        criterion = :waic,
        elpd_waic,
        p_waic,
        lppd,
        waic = waic_value,
        se_elpd_waic = _pointwise_se(point_elpd),
        se_waic = _pointwise_se(point_waic),
        pointwise = (;
            elpd_waic = point_elpd,
            p_waic = point_p_waic,
            lppd = point_lppd,
            waic = point_waic,
        ),
        n_draws,
        n_observations,
        high_variance_count,
        warning = high_variance_count == 0 ? :ok : :high_loglik_variance,
    )
end

function waic(design::FacetDesign, draws::AbstractMatrix)
    return waic(pointwise_loglikelihood_matrix(design, draws))
end

function waic(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return waic(fit.design, fit.draws[indices, :])
end

function waic(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return waic(fit.direct_pointwise_loglikelihood[indices, :])
end

function waic(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return waic(fit.direct_pointwise_loglikelihood[indices, :])
end

function _check_loo_controls(;
        pareto_k_threshold::Real,
        tail_fraction::Real,
        min_tail_draws::Int)
    isfinite(pareto_k_threshold) && pareto_k_threshold >= 0 ||
        throw(ArgumentError("pareto_k_threshold must be finite and non-negative"))
    isfinite(tail_fraction) && 0 < tail_fraction < 1 ||
        throw(ArgumentError("tail_fraction must be finite and in (0, 1)"))
    min_tail_draws >= 1 ||
        throw(ArgumentError("min_tail_draws must be positive"))
    return (;
        pareto_k_threshold = Float64(pareto_k_threshold),
        tail_fraction = Float64(tail_fraction),
        min_tail_draws,
    )
end

function _loo_tail_draws(n_draws::Int, tail_fraction::Float64, min_tail_draws::Int)
    n_draws >= 3 || throw(ArgumentError("LOO requires at least three posterior draws"))
    fraction_tail = ceil(Int, tail_fraction * n_draws)
    return min(max(fraction_tail, min_tail_draws), n_draws - 1)
end

function _hill_log_tail_pareto_k(log_ratios::AbstractVector{Float64},
        tail_draws::Int)
    sorted = sort(log_ratios)
    n = length(sorted)
    threshold = sorted[n - tail_draws]
    total_excess = 0.0
    for index in (n - tail_draws + 1):n
        total_excess += max(sorted[index] - threshold, 0.0)
    end
    return max(total_excess / tail_draws, 0.0)
end

function _raw_importance_effective_sample_size(log_ratios::AbstractVector{Float64})
    log_total = _logsumexp(log_ratios)
    sum_squared = sum(exp(2 * (value - log_total)) for value in log_ratios)
    return 1 / sum_squared
end

function _loo_diagnostic_flag(pareto_k::Float64, threshold::Float64)
    return pareto_k > threshold ? :high_pareto_k : :ok
end

"""
    loo(fit::MFRMFit; ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng(), pareto_k_threshold = 0.7,
        tail_fraction = 0.2, min_tail_draws = 5)
    loo(design::FacetDesign, draws; kwargs...)
    loo(loglik::AbstractMatrix; kwargs...)

Compute a raw importance-sampling leave-one-out (LOO) estimate from posterior
pointwise log-likelihood draws. The log-likelihood matrix must have dimensions
draws-by-observations. The returned named tuple includes `elpd_loo`, `p_loo`,
`lppd`, `looic`, standard errors, raw-importance effective sample sizes, and a
Hill-estimated Pareto-k diagnostic for each observation.

This helper does not perform PSIS smoothing. Treat rows with `pareto_k` above
`pareto_k_threshold` as unstable and prefer exact LOO, K-fold cross-validation,
or model-specific follow-up before making strong model-comparison claims.
"""
function loo(loglik::AbstractMatrix;
        pareto_k_threshold::Real = 0.7,
        tail_fraction::Real = 0.2,
        min_tail_draws::Int = 5)
    controls = _check_loo_controls(;
        pareto_k_threshold,
        tail_fraction,
        min_tail_draws)
    n_draws, n_observations = size(loglik)
    n_draws >= 3 || throw(ArgumentError("LOO requires at least three posterior draws"))
    n_observations >= 1 || throw(ArgumentError("LOO requires at least one observation"))
    all(value -> isfinite(Float64(value)), loglik) ||
        throw(ArgumentError("loglik contains non-finite values"))
    tail_draws = _loo_tail_draws(
        n_draws,
        controls.tail_fraction,
        controls.min_tail_draws,
    )

    point_lppd = Vector{Float64}(undef, n_observations)
    point_elpd = Vector{Float64}(undef, n_observations)
    point_p_loo = Vector{Float64}(undef, n_observations)
    point_looic = Vector{Float64}(undef, n_observations)
    point_pareto_k = Vector{Float64}(undef, n_observations)
    point_ess = Vector{Float64}(undef, n_observations)
    point_tail_draws = fill(tail_draws, n_observations)

    log_ratios = Vector{Float64}(undef, n_draws)
    for observation in 1:n_observations
        values = @view loglik[:, observation]
        point_lppd[observation] = _logmeanexp(values)
        for draw in 1:n_draws
            log_ratios[draw] = -Float64(loglik[draw, observation])
        end
        point_elpd[observation] = -_logmeanexp(log_ratios)
        point_p_loo[observation] =
            point_lppd[observation] - point_elpd[observation]
        point_looic[observation] = -2 * point_elpd[observation]
        point_pareto_k[observation] =
            _hill_log_tail_pareto_k(log_ratios, tail_draws)
        point_ess[observation] =
            _raw_importance_effective_sample_size(log_ratios)
    end

    elpd_loo = sum(point_elpd)
    p_loo = sum(point_p_loo)
    lppd = sum(point_lppd)
    looic_value = sum(point_looic)
    bad_pareto_k_count = count(>(controls.pareto_k_threshold), point_pareto_k)
    min_effective_sample_size = minimum(point_ess)
    return (;
        criterion = :loo,
        method = :raw_importance_sampling,
        psis_smoothing = false,
        pareto_k_estimator = :hill_log_tail,
        elpd_loo,
        p_loo,
        lppd,
        looic = looic_value,
        se_elpd_loo = _pointwise_se(point_elpd),
        se_looic = _pointwise_se(point_looic),
        pointwise = (;
            elpd_loo = point_elpd,
            p_loo = point_p_loo,
            lppd = point_lppd,
            looic = point_looic,
            pareto_k = point_pareto_k,
            effective_sample_size = point_ess,
            tail_draws = point_tail_draws,
        ),
        n_draws,
        n_observations,
        pareto_k_threshold = controls.pareto_k_threshold,
        tail_fraction = controls.tail_fraction,
        min_tail_draws = controls.min_tail_draws,
        bad_pareto_k_count,
        max_pareto_k = maximum(point_pareto_k),
        min_effective_sample_size,
        warning = bad_pareto_k_count == 0 ? :ok : :high_pareto_k,
    )
end

function loo(design::FacetDesign, draws::AbstractMatrix; kwargs...)
    return loo(pointwise_loglikelihood_matrix(design, draws); kwargs...)
end

function loo(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        kwargs...)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return loo(fit.design, fit.draws[indices, :]; kwargs...)
end

function loo(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        kwargs...)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return loo(fit.direct_pointwise_loglikelihood[indices, :]; kwargs...)
end

function loo(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        kwargs...)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return loo(fit.direct_pointwise_loglikelihood[indices, :]; kwargs...)
end

function _check_kfold_loglik(loglik::AbstractMatrix, fold_index::Int)
    n_draws, n_heldout = size(loglik)
    n_draws >= 1 ||
        throw(ArgumentError("K-fold fold $fold_index requires at least one posterior draw"))
    n_heldout >= 1 ||
        throw(ArgumentError("K-fold fold $fold_index requires at least one heldout observation"))
    all(value -> isfinite(Float64(value)), loglik) ||
        throw(ArgumentError("K-fold fold $fold_index contains non-finite log-likelihood values"))
    return n_draws, n_heldout
end

function _kfold_fold_ids(n_folds::Int, fold_ids)
    if fold_ids === nothing
        return collect(1:n_folds)
    end
    collected = collect(fold_ids)
    length(collected) == n_folds ||
        throw(ArgumentError("fold_ids has length $(length(collected)); expected $n_folds"))
    length(unique(collected)) == length(collected) ||
        throw(ArgumentError("fold_ids must be unique"))
    return Any[collected...]
end

function _kfold_observation_indices(
        n_heldout_by_fold::AbstractVector{Int},
        observation_indices)
    total_heldout = sum(n_heldout_by_fold)
    if observation_indices === nothing
        return collect(1:total_heldout)
    end

    collected = collect(observation_indices)
    if length(collected) == length(n_heldout_by_fold) &&
            all(index_set -> index_set isa AbstractVector, collected)
        out = Any[]
        for (fold_index, index_set) in pairs(collected)
            fold_indices = collect(index_set)
            expected = n_heldout_by_fold[fold_index]
            length(fold_indices) == expected ||
                throw(ArgumentError(
                    "observation_indices for fold $fold_index has length " *
                    "$(length(fold_indices)); expected $expected"))
            append!(out, fold_indices)
        end
        length(unique(out)) == length(out) ||
            throw(ArgumentError("observation_indices must be unique across folds"))
        return out
    end

    length(collected) == total_heldout ||
        throw(ArgumentError(
            "observation_indices has length $(length(collected)); expected $total_heldout"))
    length(unique(collected)) == length(collected) ||
        throw(ArgumentError("observation_indices must be unique across folds"))
    return Any[collected...]
end

function _kfold_plan_group_indices(data::FacetData, group_by::Union{Nothing,Symbol})
    group_by === nothing && return :observation, collect(1:data.n), collect(1:data.n)
    group_by === :observation && return :observation, collect(1:data.n), collect(1:data.n)
    group_by === :person && return :person, data.person, data.person_levels
    group_by === :rater && return :rater, data.rater, data.rater_levels
    group_by === :item && return :item, data.item, data.item_levels
    group_by === :category && return :category, data.category, data.category_levels
    if haskey(data.optional, group_by)
        return group_by, data.optional[group_by], data.optional_levels[group_by]
    end
    throw(ArgumentError(
        "group_by = :$group_by is not :observation, a required facet, or an optional facet"))
end

function _kfold_plan_units(data::FacetData, group_by::Union{Nothing,Symbol})
    role, unit_indices, levels = _kfold_plan_group_indices(data, group_by)
    unit_rows = [Int[] for _ in eachindex(levels)]
    for (observation, unit_index) in pairs(unit_indices)
        1 <= unit_index <= length(unit_rows) ||
            throw(ArgumentError(
                "group_by = :$role produced invalid unit index $unit_index at observation $observation"))
        push!(unit_rows[unit_index], observation)
    end

    nonempty = findall(!isempty, unit_rows)
    isempty(nonempty) &&
        throw(ArgumentError("K-fold planning requires at least one observation"))
    return (;
        group_by = role,
        rows = [unit_rows[index] for index in nonempty],
        levels = Any[levels[index] for index in nonempty],
    )
end

function _least_loaded_fold_index(fold_observation_counts::AbstractVector{Int})
    best_index = firstindex(fold_observation_counts)
    best_count = fold_observation_counts[best_index]
    for index in Iterators.drop(eachindex(fold_observation_counts), 1)
        count = fold_observation_counts[index]
        if count < best_count
            best_index = index
            best_count = count
        end
    end
    return best_index
end

"""
    kfold_plan(data::FacetData; k, group_by = nothing, shuffle = false,
        rng = Random.default_rng(), fold_ids = nothing)
    kfold_plan(spec::FacetSpec; kwargs...)
    kfold_plan(design::FacetDesign; kwargs...)

Construct deterministic heldout-fold assignments for later K-fold refits. By
default observations are assigned directly to balanced folds. With
`group_by = :person`, `:rater`, `:item`, `:category`, or an optional facet such
as `:group`, all observations for each level are kept in the same heldout fold.

The returned named tuple includes `fold_rows`, `folds`, and
`heldout_observation_indices`; pass the latter two to [`kfold`](@ref) after
fitting each training fold and collecting fold-specific heldout log-likelihood
matrices. This helper builds the fold plan only. It does not refit models.
"""
function kfold_plan(data::FacetData;
        k::Integer,
        group_by::Union{Nothing,Symbol} = nothing,
        shuffle::Bool = false,
        rng::AbstractRNG = Random.default_rng(),
        fold_ids = nothing)
    data.n >= 1 || throw(ArgumentError("K-fold planning requires at least one observation"))
    k_int = Int(k)
    k_int >= 2 || throw(ArgumentError("K-fold planning requires k >= 2"))

    units = _kfold_plan_units(data, group_by)
    n_units = length(units.rows)
    k_int <= n_units ||
        throw(ArgumentError(
            "K-fold planning with group_by = :$(units.group_by) has $n_units heldout units; " *
            "expected at least k = $k_int"))

    checked_fold_ids = _kfold_fold_ids(k_int, fold_ids)
    unit_order = collect(1:n_units)
    shuffle && Random.shuffle!(rng, unit_order)

    fold_observation_counts = zeros(Int, k_int)
    heldout_by_fold = [Int[] for _ in 1:k_int]
    units_by_fold = [Any[] for _ in 1:k_int]
    for unit_index in unit_order
        fold_index = _least_loaded_fold_index(fold_observation_counts)
        rows = units.rows[unit_index]
        append!(heldout_by_fold[fold_index], rows)
        push!(units_by_fold[fold_index], units.levels[unit_index])
        fold_observation_counts[fold_index] += length(rows)
    end

    observation_fold = Vector{Any}(undef, data.n)
    fold_rows = NamedTuple[]
    all_observations = collect(1:data.n)
    for fold_index in 1:k_int
        heldout_observations = sort(heldout_by_fold[fold_index])
        heldout_set = Set(heldout_observations)
        training_observations =
            [observation for observation in all_observations if !(observation in heldout_set)]
        fold_id = checked_fold_ids[fold_index]
        for observation in heldout_observations
            observation_fold[observation] = fold_id
        end
        heldout_units = copy(units_by_fold[fold_index])
        push!(fold_rows, (;
            fold = fold_id,
            n_heldout_observations = length(heldout_observations),
            n_training_observations = length(training_observations),
            heldout_observations,
            training_observations,
            heldout_units,
            n_heldout_units = length(heldout_units),
        ))
    end

    return (;
        schema = "bayesianmgmfrm.kfold_plan.v1",
        object = :kfold_plan,
        method = shuffle ? :randomized_balanced_fold_plan : :deterministic_balanced_fold_plan,
        comparison_contract = :same_heldout_observation_folds,
        group_by = units.group_by,
        k = k_int,
        n_observations = data.n,
        n_units,
        n_folds = k_int,
        folds = copy(checked_fold_ids),
        observation_fold,
        heldout_observation_indices =
            [copy(row.heldout_observations) for row in fold_rows],
        n_heldout_by_fold = copy(fold_observation_counts),
        fold_rows,
        refits_per_model_required = k_int,
        warning = :ok,
    )
end

kfold_plan(spec::FacetSpec; kwargs...) = kfold_plan(spec.data; kwargs...)
kfold_plan(design::FacetDesign; kwargs...) = kfold_plan(design.spec.data; kwargs...)

function _loo_refit_plan_from_observations(
        data::FacetData,
        heldout_observations::Vector{Int},
        fold_ids,
        warning::Symbol)
    n_refits = length(heldout_observations)
    checked_fold_ids = fold_ids === nothing ?
        Any[heldout_observations...] :
        _kfold_fold_ids(n_refits, fold_ids)

    all_observations = collect(1:data.n)
    observation_fold = Vector{Any}(undef, data.n)
    fill!(observation_fold, missing)
    fold_rows = NamedTuple[]
    for (index, observation) in pairs(heldout_observations)
        fold_id = checked_fold_ids[index]
        training_observations = [row for row in all_observations if row != observation]
        observation_fold[observation] = fold_id
        push!(fold_rows, (;
            fold = fold_id,
            n_heldout_observations = 1,
            n_training_observations = length(training_observations),
            heldout_observations = [observation],
            training_observations,
            heldout_units = [observation],
            n_heldout_units = 1,
        ))
    end

    return (;
        schema = "bayesianmgmfrm.loo_refit_plan.v1",
        object = :loo_refit_plan,
        method = :deterministic_leave_one_observation_out_plan,
        comparison_contract = :same_heldout_observation_folds,
        group_by = :observation,
        n_observations = data.n,
        n_refits,
        n_folds = n_refits,
        folds = copy(checked_fold_ids),
        observation_fold,
        heldout_observation_indices =
            [copy(row.heldout_observations) for row in fold_rows],
        n_heldout_by_fold = fill(1, n_refits),
        fold_rows,
        refits_per_model_required = n_refits,
        warning,
    )
end

"""
    loo_refit_plan(data::FacetData; observations = nothing, fold_ids = nothing)
    loo_refit_plan(data::FacetData, stat; threshold = nothing,
        only_flagged = true, fold_ids = nothing)
    loo_refit_plan(spec::FacetSpec; kwargs...)
    loo_refit_plan(design::FacetDesign; kwargs...)

Construct a deterministic leave-one-observation-out refit plan. Each returned
fold row holds out exactly one observation and lists the complementary training
observations. Pass `observations` to plan exact-refit follow-up for a subset,
such as flagged raw-importance LOO rows. When a raw LOO summary is supplied,
`only_flagged = true` selects observations whose Pareto-k exceeds `threshold`;
by default the threshold is read from the summary. This helper builds the refit
plan only. It does not refit models.
"""
function loo_refit_plan(data::FacetData;
        observations = nothing,
        fold_ids = nothing)
    heldout_observations =
        _check_observation_indices(data, observations, "loo_refit_plan")
    isempty(heldout_observations) &&
        throw(ArgumentError("loo_refit_plan requires at least one heldout observation"))
    return _loo_refit_plan_from_observations(
        data,
        heldout_observations,
        fold_ids,
        observations === nothing ? :ok : :subset,
    )
end

loo_refit_plan(spec::FacetSpec; kwargs...) = loo_refit_plan(spec.data; kwargs...)
loo_refit_plan(design::FacetDesign; kwargs...) =
    loo_refit_plan(design.spec.data; kwargs...)

function _loo_refit_plan_stat_observations(data::FacetData, stat;
        threshold,
        only_flagged::Bool)
    hasproperty(stat, :criterion) && stat.criterion === :loo ||
        throw(ArgumentError("loo_refit_plan requires a raw LOO summary"))
    hasproperty(stat, :n_observations) && stat.n_observations isa Integer ||
        throw(ArgumentError("LOO summary must contain integer n_observations"))
    n_observations = Int(stat.n_observations)
    n_observations == data.n ||
        throw(ArgumentError("LOO summary n_observations does not match the supplied data"))
    hasproperty(stat, :pointwise) && hasproperty(stat.pointwise, :pareto_k) ||
        throw(ArgumentError("LOO summary must contain pointwise Pareto-k diagnostics"))
    length(stat.pointwise.pareto_k) == n_observations ||
        throw(ArgumentError("LOO summary pointwise Pareto-k length does not match n_observations"))
    checked_threshold = threshold === nothing ?
        _check_loo_threshold(
            hasproperty(stat, :pareto_k_threshold) ? stat.pareto_k_threshold : 0.7) :
        _check_loo_threshold(threshold)

    observations = Int[]
    for observation in 1:n_observations
        pareto_k = Float64(stat.pointwise.pareto_k[observation])
        isfinite(pareto_k) ||
            throw(ArgumentError("LOO summary pointwise Pareto-k values must be finite"))
        flag = _loo_diagnostic_flag(pareto_k, checked_threshold)
        (!only_flagged || flag !== :ok) && push!(observations, observation)
    end
    return observations
end

function loo_refit_plan(data::FacetData, stat;
        threshold = nothing,
        only_flagged::Bool = true,
        fold_ids = nothing)
    observations = _loo_refit_plan_stat_observations(
        data,
        stat;
        threshold,
        only_flagged,
    )
    warning = only_flagged ?
        (isempty(observations) ? :no_refits_required : :subset) :
        :ok
    return _loo_refit_plan_from_observations(data, observations, fold_ids, warning)
end

loo_refit_plan(spec::FacetSpec, stat; kwargs...) =
    loo_refit_plan(spec.data, stat; kwargs...)
loo_refit_plan(design::FacetDesign, stat; kwargs...) =
    loo_refit_plan(design.spec.data, stat; kwargs...)

function _kfold_plan_diagnostic_facet_groups(data::FacetData, facet::Symbol)
    facet === :person && return data.person, data.person_levels
    facet === :rater && return data.rater, data.rater_levels
    facet === :item && return data.item, data.item_levels
    facet === :category && return data.category, data.category_levels
    if haskey(data.optional, facet)
        return data.optional[facet], data.optional_levels[facet]
    end
    throw(ArgumentError(
        "facets contains :$facet, which is not a required or optional facet"))
end

function _kfold_plan_diagnostic_facets(data::FacetData, facets)
    requested = if facets === :all
        Symbol[:person, :rater, :item, :category,
            sort(collect(keys(data.optional)); by = string)...]
    elseif facets isa Symbol
        Symbol[facets]
    else
        Symbol[facet for facet in facets]
    end
    isempty(requested) &&
        throw(ArgumentError("facets must contain at least one facet"))
    length(unique(requested)) == length(requested) ||
        throw(ArgumentError("facets must not contain duplicates"))
    for facet in requested
        _kfold_plan_diagnostic_facet_groups(data, facet)
    end
    return Tuple(requested)
end

function _kfold_plan_checked_observations(data::FacetData, observations, context)
    return _check_observation_indices(data, observations, context)
end

function _kfold_plan_present_levels(index::AbstractVector{Int},
        levels::AbstractVector,
        observations::AbstractVector{Int})
    present = falses(length(levels))
    for observation in observations
        present[index[observation]] = true
    end
    return Tuple(levels[level_index] for level_index in eachindex(levels)
        if present[level_index])
end

function _check_kfold_plan_for_diagnostics(data::FacetData, plan)
    hasproperty(plan, :fold_rows) ||
        throw(ArgumentError("kfold_plan_diagnostics requires a kfold_plan result with fold_rows"))
    hasproperty(plan, :n_observations) &&
        Int(plan.n_observations) == data.n ||
        throw(ArgumentError("kfold_plan n_observations does not match the supplied data"))
    return plan
end

"""
    kfold_plan_diagnostics(data::FacetData, plan; facets = :all)
    kfold_plan_diagnostics(spec::FacetSpec, plan; kwargs...)
    kfold_plan_diagnostics(design::FacetDesign, plan; kwargs...)

Check whether each training fold in a [`kfold_plan`](@ref) retains the levels
needed to score its heldout observations. Rows are reported by fold and facet
for person, rater, item, score category, and optional facets by default. A row
with `refit_blocker = true` has heldout-only levels for that facet, so an
external refit using only that training fold would need a fixed level map,
pooled treatment, or a different fold assignment before heldout scoring.
"""
function kfold_plan_diagnostics(data::FacetData, plan; facets = :all)
    checked_plan = _check_kfold_plan_for_diagnostics(data, plan)
    checked_facets = _kfold_plan_diagnostic_facets(data, facets)
    rows = NamedTuple[]
    for fold_row in checked_plan.fold_rows
        hasproperty(fold_row, :fold) ||
            throw(ArgumentError("kfold_plan fold_rows must contain :fold"))
        training_observations = _kfold_plan_checked_observations(
            data,
            fold_row.training_observations,
            "kfold_plan_diagnostics training_observations",
        )
        heldout_observations = _kfold_plan_checked_observations(
            data,
            fold_row.heldout_observations,
            "kfold_plan_diagnostics heldout_observations",
        )
        for facet in checked_facets
            index, levels = _kfold_plan_diagnostic_facet_groups(data, facet)
            training_levels = _kfold_plan_present_levels(
                index,
                levels,
                training_observations,
            )
            heldout_levels = _kfold_plan_present_levels(
                index,
                levels,
                heldout_observations,
            )
            training_set = Set(training_levels)
            heldout_only_levels =
                Tuple(level for level in heldout_levels if !(level in training_set))
            status = isempty(heldout_only_levels) ? :ok : :heldout_only_levels
            push!(rows, (;
                fold = fold_row.fold,
                facet,
                n_levels = length(levels),
                n_training_observations = length(training_observations),
                n_heldout_observations = length(heldout_observations),
                n_training_levels = length(training_levels),
                n_heldout_levels = length(heldout_levels),
                n_heldout_only_levels = length(heldout_only_levels),
                heldout_only_levels,
                training_levels,
                heldout_levels,
                refit_blocker = !isempty(heldout_only_levels),
                status,
            ))
        end
    end
    n_blocking_rows = count(row -> row.refit_blocker, rows)
    return (;
        schema = "bayesianmgmfrm.kfold_plan_diagnostics.v1",
        object = :kfold_plan_diagnostics,
        plan_schema = hasproperty(checked_plan, :schema) ? checked_plan.schema : missing,
        group_by = hasproperty(checked_plan, :group_by) ? checked_plan.group_by : missing,
        n_folds = length(checked_plan.fold_rows),
        n_observations = data.n,
        facets = checked_facets,
        rows,
        n_rows = length(rows),
        n_blocking_rows,
        passed = n_blocking_rows == 0,
        warning = n_blocking_rows == 0 ? :ok : :heldout_only_levels,
    )
end

kfold_plan_diagnostics(spec::FacetSpec, plan; kwargs...) =
    kfold_plan_diagnostics(spec.data, plan; kwargs...)
kfold_plan_diagnostics(design::FacetDesign, plan; kwargs...) =
    kfold_plan_diagnostics(design.spec.data, plan; kwargs...)

"""
    kfold(fold_logliks; fold_ids = nothing, observation_indices = nothing)
    kfold(loglik::AbstractMatrix; fold_ids = nothing, observation_indices = nothing)

Summarize heldout K-fold log predictive density from fold-specific refits. Each
fold log-likelihood matrix must be draws-by-heldout-observations and contain
posterior pointwise log-likelihood draws for observations that were not used to
fit that fold. The returned named tuple includes `elpd_kfold`, `kfoldic`,
standard errors, fold sizes, observation identifiers, and pointwise heldout
components.

This helper does not refit models. Use [`kfold_plan`](@ref) to construct
observation or grouped heldout folds, then use `kfold` to record exact
heldout-refit or K-fold follow-up evidence after fitting each training fold.
"""
function kfold(fold_logliks::Union{Tuple,AbstractVector};
        fold_ids = nothing,
        observation_indices = nothing)
    matrices = collect(fold_logliks)
    n_folds = length(matrices)
    n_folds >= 1 || throw(ArgumentError("K-fold requires at least one fold"))
    all(matrix -> matrix isa AbstractMatrix, matrices) ||
        throw(ArgumentError("K-fold inputs must be log-likelihood matrices"))

    n_draws_by_fold = Int[]
    n_heldout_by_fold = Int[]
    for (fold_index, matrix) in pairs(matrices)
        n_draws, n_heldout = _check_kfold_loglik(matrix, fold_index)
        push!(n_draws_by_fold, n_draws)
        push!(n_heldout_by_fold, n_heldout)
    end

    checked_fold_ids = _kfold_fold_ids(n_folds, fold_ids)
    checked_observation_indices =
        _kfold_observation_indices(n_heldout_by_fold, observation_indices)

    point_elpd = Float64[]
    point_kfoldic = Float64[]
    point_fold = Any[]
    point_observation = Any[]
    observation_offset = 0
    for (fold_index, matrix) in pairs(matrices)
        fold_id = checked_fold_ids[fold_index]
        n_heldout = n_heldout_by_fold[fold_index]
        for heldout_index in 1:n_heldout
            observation_offset += 1
            heldout_elpd = _logmeanexp(@view matrix[:, heldout_index])
            push!(point_elpd, heldout_elpd)
            push!(point_kfoldic, -2 * heldout_elpd)
            push!(point_fold, fold_id)
            push!(point_observation, checked_observation_indices[observation_offset])
        end
    end

    elpd_kfold = sum(point_elpd)
    kfoldic_value = sum(point_kfoldic)
    return (;
        criterion = :kfold,
        method = :heldout_refit_log_score,
        prediction_target = :heldout_observation_log_score,
        elpd_kfold,
        kfoldic = kfoldic_value,
        se_elpd_kfold = _pointwise_se(point_elpd),
        se_kfoldic = _pointwise_se(point_kfoldic),
        pointwise = (;
            elpd_heldout = point_elpd,
            kfoldic = point_kfoldic,
            fold = point_fold,
            observation = point_observation,
        ),
        n_folds,
        n_observations = length(point_elpd),
        n_draws_by_fold,
        n_heldout_by_fold,
        folds = copy(checked_fold_ids),
        observation_indices = copy(point_observation),
        warning = :ok,
    )
end

function kfold(loglik::AbstractMatrix;
        fold_ids = nothing,
        observation_indices = nothing)
    return kfold([loglik]; fold_ids, observation_indices)
end

function _check_waic_threshold(threshold::Real)
    isfinite(threshold) && threshold >= 0 ||
        throw(ArgumentError("threshold must be finite and non-negative"))
    return Float64(threshold)
end

_check_loo_threshold(threshold::Real) = _check_waic_threshold(threshold)

function _optional_observation_labels(data::FacetData, observation::Int)
    facets = Tuple(sort(collect(keys(data.optional)); by = string))
    values = Tuple(data.optional_levels[facet][data.optional[facet][observation]]
        for facet in facets)
    return NamedTuple{facets}(values)
end

function _waic_diagnostic_flag(p_waic::Float64, threshold::Float64)
    return p_waic > threshold ? :high_loglik_variance : :ok
end

function _waic_diagnostics_rows(stat;
        threshold::Float64,
        only_flagged::Bool)
    rows = NamedTuple[]
    for observation in 1:stat.n_observations
        p_waic = stat.pointwise.p_waic[observation]
        flag = _waic_diagnostic_flag(p_waic, threshold)
        only_flagged && flag === :ok && continue
        push!(rows, (;
            observation,
            criterion = :waic,
            lppd = stat.pointwise.lppd[observation],
            p_waic,
            elpd_waic = stat.pointwise.elpd_waic[observation],
            waic = stat.pointwise.waic[observation],
            threshold,
            flag,
        ))
    end
    return rows
end

function _waic_diagnostics_rows(design::FacetDesign, stat;
        threshold::Float64,
        only_flagged::Bool)
    data = design.spec.data
    rows = NamedTuple[]
    for observation in 1:stat.n_observations
        p_waic = stat.pointwise.p_waic[observation]
        flag = _waic_diagnostic_flag(p_waic, threshold)
        only_flagged && flag === :ok && continue
        push!(rows, (;
            observation,
            person = data.person_levels[data.person[observation]],
            rater = data.rater_levels[data.rater[observation]],
            item = data.item_levels[data.item[observation]],
            score = data.score[observation],
            category = data.category_levels[data.category[observation]],
            optional = _optional_observation_labels(data, observation),
            criterion = :waic,
            lppd = stat.pointwise.lppd[observation],
            p_waic,
            elpd_waic = stat.pointwise.elpd_waic[observation],
            waic = stat.pointwise.waic[observation],
            threshold,
            flag,
        ))
    end
    return rows
end

function _loo_diagnostics_rows(stat;
        threshold::Float64,
        only_flagged::Bool)
    rows = NamedTuple[]
    for observation in 1:stat.n_observations
        pareto_k = stat.pointwise.pareto_k[observation]
        flag = _loo_diagnostic_flag(pareto_k, threshold)
        only_flagged && flag === :ok && continue
        push!(rows, (;
            observation,
            criterion = :loo,
            method = stat.method,
            psis_smoothing = stat.psis_smoothing,
            lppd = stat.pointwise.lppd[observation],
            p_loo = stat.pointwise.p_loo[observation],
            elpd_loo = stat.pointwise.elpd_loo[observation],
            looic = stat.pointwise.looic[observation],
            pareto_k,
            effective_sample_size =
                stat.pointwise.effective_sample_size[observation],
            tail_draws = stat.pointwise.tail_draws[observation],
            threshold,
            flag,
        ))
    end
    return rows
end

function _loo_diagnostics_rows(design::FacetDesign, stat;
        threshold::Float64,
        only_flagged::Bool)
    data = design.spec.data
    rows = NamedTuple[]
    for observation in 1:stat.n_observations
        pareto_k = stat.pointwise.pareto_k[observation]
        flag = _loo_diagnostic_flag(pareto_k, threshold)
        only_flagged && flag === :ok && continue
        push!(rows, (;
            observation,
            person = data.person_levels[data.person[observation]],
            rater = data.rater_levels[data.rater[observation]],
            item = data.item_levels[data.item[observation]],
            score = data.score[observation],
            category = data.category_levels[data.category[observation]],
            optional = _optional_observation_labels(data, observation),
            criterion = :loo,
            method = stat.method,
            psis_smoothing = stat.psis_smoothing,
            lppd = stat.pointwise.lppd[observation],
            p_loo = stat.pointwise.p_loo[observation],
            elpd_loo = stat.pointwise.elpd_loo[observation],
            looic = stat.pointwise.looic[observation],
            pareto_k,
            effective_sample_size =
                stat.pointwise.effective_sample_size[observation],
            tail_draws = stat.pointwise.tail_draws[observation],
            threshold,
            flag,
        ))
    end
    return rows
end

function _check_kfold_diagnostic_stat(stat)
    checked = _check_kfold_stat(stat)
    if hasproperty(checked.pointwise, :observation)
        length(checked.pointwise.observation) == checked.n_observations ||
            throw(ArgumentError(
                "K-fold pointwise observation length does not match n_observations"))
    end
    if hasproperty(checked.pointwise, :kfoldic)
        length(checked.pointwise.kfoldic) == checked.n_observations ||
            throw(ArgumentError(
                "K-fold pointwise K-fold IC length does not match n_observations"))
        all(value -> isfinite(Float64(value)), checked.pointwise.kfoldic) ||
            throw(ArgumentError("K-fold pointwise K-fold IC values must be finite"))
    end
    return checked
end

function _kfold_diagnostic_observation(stat, index::Int)
    return hasproperty(stat.pointwise, :observation) ?
        stat.pointwise.observation[index] :
        stat.observation_indices[index]
end

function _kfold_diagnostic_kfoldic(stat, index::Int)
    return hasproperty(stat.pointwise, :kfoldic) ?
        Float64(stat.pointwise.kfoldic[index]) :
        -2 * Float64(stat.pointwise.elpd_heldout[index])
end

function _kfold_diagnostics_rows(stat)
    checked = _check_kfold_diagnostic_stat(stat)
    rows = NamedTuple[]
    for index in 1:checked.n_observations
        push!(rows, (;
            heldout_index = index,
            observation = _kfold_diagnostic_observation(checked, index),
            fold = checked.pointwise.fold[index],
            criterion = :kfold,
            method = checked.method,
            prediction_target = checked.prediction_target,
            elpd_heldout = Float64(checked.pointwise.elpd_heldout[index]),
            kfoldic = _kfold_diagnostic_kfoldic(checked, index),
            flag = checked.warning,
        ))
    end
    return rows
end

function _kfold_diagnostics_rows(data::FacetData, stat)
    checked = _check_kfold_diagnostic_stat(stat)
    observations = _check_observation_indices(
        data,
        checked.observation_indices,
        "kfold_diagnostics observation_indices",
    )
    rows = NamedTuple[]
    for index in 1:checked.n_observations
        observation = observations[index]
        push!(rows, (;
            heldout_index = index,
            observation,
            person = data.person_levels[data.person[observation]],
            rater = data.rater_levels[data.rater[observation]],
            item = data.item_levels[data.item[observation]],
            score = data.score[observation],
            category = data.category_levels[data.category[observation]],
            optional = _optional_observation_labels(data, observation),
            fold = checked.pointwise.fold[index],
            criterion = :kfold,
            method = checked.method,
            prediction_target = checked.prediction_target,
            elpd_heldout = Float64(checked.pointwise.elpd_heldout[index]),
            kfoldic = _kfold_diagnostic_kfoldic(checked, index),
            flag = checked.warning,
        ))
    end
    return rows
end

"""
    waic_diagnostics(fit::MFRMFit; threshold = 0.4, only_flagged = false,
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng())
    waic_diagnostics(design::FacetDesign, draws; threshold = 0.4,
        only_flagged = false)
    waic_diagnostics(loglik::AbstractMatrix; threshold = 0.4,
        only_flagged = false)

Return observation-level WAIC diagnostics. Rows include pointwise `lppd`,
`p_waic`, `elpd_waic`, WAIC contribution, and a flag for observations whose
`p_waic` exceeds `threshold`. When a `FacetDesign` or `MFRMFit` is supplied,
rows also include person, rater, item, score, category, and optional facet
labels. Use this helper to locate observations behind a WAIC
`:high_loglik_variance` warning before interpreting model-comparison rows.
"""
function waic_diagnostics(loglik::AbstractMatrix;
        threshold::Real = 0.4,
        only_flagged::Bool = false)
    checked_threshold = _check_waic_threshold(threshold)
    return _waic_diagnostics_rows(waic(loglik);
        threshold = checked_threshold,
        only_flagged)
end

function waic_diagnostics(design::FacetDesign,
        draws::AbstractMatrix;
        threshold::Real = 0.4,
        only_flagged::Bool = false)
    checked_threshold = _check_waic_threshold(threshold)
    return _waic_diagnostics_rows(design, waic(design, draws);
        threshold = checked_threshold,
        only_flagged)
end

function waic_diagnostics(fit::MFRMFit;
        threshold::Real = 0.4,
        only_flagged::Bool = false,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    checked_threshold = _check_waic_threshold(threshold)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _waic_diagnostics_rows(fit.design, waic(fit.design, fit.draws[indices, :]);
        threshold = checked_threshold,
        only_flagged)
end

function waic_diagnostics(fit::GMFRMFit;
        threshold::Real = 0.4,
        only_flagged::Bool = false,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    checked_threshold = _check_waic_threshold(threshold)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _waic_diagnostics_rows(
        fit.design,
        waic(fit.direct_pointwise_loglikelihood[indices, :]);
        threshold = checked_threshold,
        only_flagged)
end

function waic_diagnostics(fit::MGMFRMFit;
        threshold::Real = 0.4,
        only_flagged::Bool = false,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    checked_threshold = _check_waic_threshold(threshold)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _waic_diagnostics_rows(
        fit.design,
        waic(fit.direct_pointwise_loglikelihood[indices, :]);
        threshold = checked_threshold,
        only_flagged)
end

"""
    loo_diagnostics(fit::MFRMFit; threshold = 0.7, only_flagged = false,
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng(),
        tail_fraction = 0.2, min_tail_draws = 5)
    loo_diagnostics(design::FacetDesign, draws; threshold = 0.7,
        only_flagged = false, tail_fraction = 0.2, min_tail_draws = 5)
    loo_diagnostics(loglik::AbstractMatrix; threshold = 0.7,
        only_flagged = false, tail_fraction = 0.2, min_tail_draws = 5)

Return observation-level raw importance-sampling LOO diagnostics. Rows include
pointwise `lppd`, `p_loo`, `elpd_loo`, LOOIC contribution, raw-importance
effective sample size, a Hill-estimated `pareto_k`, and a flag for observations
whose `pareto_k` exceeds `threshold`. When a `FacetDesign` or `MFRMFit` is
supplied, rows also include person, rater, item, score, category, and optional
facet labels.
"""
function loo_diagnostics(loglik::AbstractMatrix;
        threshold::Real = 0.7,
        only_flagged::Bool = false,
        tail_fraction::Real = 0.2,
        min_tail_draws::Int = 5)
    checked_threshold = _check_loo_threshold(threshold)
    return _loo_diagnostics_rows(
        loo(loglik;
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws);
        threshold = checked_threshold,
        only_flagged)
end

function loo_diagnostics(design::FacetDesign,
        draws::AbstractMatrix;
        threshold::Real = 0.7,
        only_flagged::Bool = false,
        tail_fraction::Real = 0.2,
        min_tail_draws::Int = 5)
    checked_threshold = _check_loo_threshold(threshold)
    return _loo_diagnostics_rows(
        design,
        loo(design, draws;
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws);
        threshold = checked_threshold,
        only_flagged)
end

function loo_diagnostics(fit::MFRMFit;
        threshold::Real = 0.7,
        only_flagged::Bool = false,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        tail_fraction::Real = 0.2,
        min_tail_draws::Int = 5)
    checked_threshold = _check_loo_threshold(threshold)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _loo_diagnostics_rows(
        fit.design,
        loo(fit.design, fit.draws[indices, :];
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws);
        threshold = checked_threshold,
        only_flagged)
end

function loo_diagnostics(fit::GMFRMFit;
        threshold::Real = 0.7,
        only_flagged::Bool = false,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        tail_fraction::Real = 0.2,
        min_tail_draws::Int = 5)
    checked_threshold = _check_loo_threshold(threshold)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _loo_diagnostics_rows(
        fit.design,
        loo(fit.direct_pointwise_loglikelihood[indices, :];
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws);
        threshold = checked_threshold,
        only_flagged)
end

function loo_diagnostics(fit::MGMFRMFit;
        threshold::Real = 0.7,
        only_flagged::Bool = false,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        tail_fraction::Real = 0.2,
        min_tail_draws::Int = 5)
    checked_threshold = _check_loo_threshold(threshold)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _loo_diagnostics_rows(
        fit.design,
        loo(fit.direct_pointwise_loglikelihood[indices, :];
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws);
        threshold = checked_threshold,
        only_flagged)
end

"""
    kfold_diagnostics(stat)
    kfold_diagnostics(data::FacetData, stat)
    kfold_diagnostics(spec::FacetSpec, stat)
    kfold_diagnostics(design::FacetDesign, stat)

Return observation-level heldout K-fold rows from a [`kfold`](@ref) result.
Rows include heldout index, observation identifier, fold, heldout ELPD, K-fold
information-criterion contribution, method, prediction target, and flag. When
`FacetData`, `FacetSpec`, or `FacetDesign` is supplied, observation identifiers
must be valid data row indices and rows also include person, rater, item, score,
category, and optional facet labels.
"""
function kfold_diagnostics(stat)
    return _kfold_diagnostics_rows(stat)
end

function kfold_diagnostics(data::FacetData, stat)
    return _kfold_diagnostics_rows(data, stat)
end

kfold_diagnostics(spec::FacetSpec, stat) =
    kfold_diagnostics(spec.data, stat)
kfold_diagnostics(design::FacetDesign, stat) =
    kfold_diagnostics(design.spec.data, stat)

function _compare_model_names(names, n_models::Int)
    labels = names === nothing ?
        ["model_$i" for i in 1:n_models] :
        [string(name) for name in names]
    length(labels) == n_models ||
        throw(ArgumentError("names has length $(length(labels)); expected $n_models"))
    length(unique(labels)) == length(labels) ||
        throw(ArgumentError("model names must be unique"))
    return labels
end

function _check_kfold_stat(stat)
    required_fields = (
        :criterion,
        :method,
        :prediction_target,
        :elpd_kfold,
        :kfoldic,
        :se_elpd_kfold,
        :se_kfoldic,
        :pointwise,
        :n_folds,
        :n_observations,
        :n_draws_by_fold,
        :n_heldout_by_fold,
        :folds,
        :observation_indices,
        :warning,
    )
    for field in required_fields
        hasproperty(stat, field) ||
            throw(ArgumentError("K-fold statistic is missing field :$field"))
    end
    stat.criterion === :kfold ||
        throw(ArgumentError("K-fold statistic must have criterion = :kfold"))
    hasproperty(stat.pointwise, :elpd_heldout) ||
        throw(ArgumentError("K-fold statistic pointwise data is missing :elpd_heldout"))
    hasproperty(stat.pointwise, :fold) ||
        throw(ArgumentError("K-fold statistic pointwise data is missing :fold"))
    length(stat.pointwise.elpd_heldout) == stat.n_observations ||
        throw(ArgumentError("K-fold pointwise length does not match n_observations"))
    length(stat.pointwise.fold) == stat.n_observations ||
        throw(ArgumentError("K-fold fold length does not match n_observations"))
    length(stat.observation_indices) == stat.n_observations ||
        throw(ArgumentError("K-fold observation_indices length does not match n_observations"))
    isfinite(Float64(stat.elpd_kfold)) && isfinite(Float64(stat.kfoldic)) ||
        throw(ArgumentError("K-fold aggregate values must be finite"))
    all(value -> isfinite(Float64(value)), stat.pointwise.elpd_heldout) ||
        throw(ArgumentError("K-fold pointwise ELPD values must be finite"))
    return stat
end

function _require_kfold_comparison_compatibility(stats::AbstractVector)
    isempty(stats) && return nothing
    first_stat = stats[1]
    first_n_observations = first_stat.n_observations
    first_observation_indices = first_stat.observation_indices
    first_folds = first_stat.pointwise.fold
    first_prediction_target = first_stat.prediction_target
    all(stat -> stat.n_observations == first_n_observations, stats) ||
        throw(ArgumentError("all K-fold statistics must have the same number of heldout observations"))
    all(stat -> isequal(stat.observation_indices, first_observation_indices), stats) ||
        throw(ArgumentError("all K-fold statistics must use the same heldout observation order"))
    all(stat -> isequal(stat.pointwise.fold, first_folds), stats) ||
        throw(ArgumentError("all K-fold statistics must use the same fold assignment order"))
    all(stat -> stat.prediction_target === first_prediction_target, stats) ||
        throw(ArgumentError("all K-fold statistics must use the same prediction target"))
    return nothing
end

function _kfold_comparison_rows(labels::AbstractVector{<:AbstractString},
        stats::AbstractVector)
    n_models = length(stats)
    n_models >= 2 || throw(ArgumentError("at least two models are required"))
    length(labels) == n_models ||
        throw(ArgumentError("labels has length $(length(labels)); expected $n_models"))
    checked_stats = [_check_kfold_stat(stat) for stat in stats]
    _require_kfold_comparison_compatibility(checked_stats)

    order = sortperm(1:n_models; by = i -> checked_stats[i].elpd_kfold, rev = true)
    best = checked_stats[order[1]]
    unnormalized_weights =
        [exp(stat.elpd_kfold - best.elpd_kfold) for stat in checked_stats]
    weight_total = sum(unnormalized_weights)
    rows = NamedTuple[]
    for (rank, index) in pairs(order)
        stat = checked_stats[index]
        pointwise_difference =
            stat.pointwise.elpd_heldout .- best.pointwise.elpd_heldout
        push!(rows, (;
            model = labels[index],
            rank,
            criterion = :kfold,
            comparison_contract = _KFOLD_COMPARISON_CONTRACT,
            method = stat.method,
            prediction_target = stat.prediction_target,
            elpd_kfold = stat.elpd_kfold,
            elpd_difference = stat.elpd_kfold - best.elpd_kfold,
            se_elpd_difference = _pointwise_se(pointwise_difference),
            se_elpd_kfold = stat.se_elpd_kfold,
            kfoldic = stat.kfoldic,
            kfoldic_difference = stat.kfoldic - best.kfoldic,
            se_kfoldic = stat.se_kfoldic,
            relative_weight = unnormalized_weights[index] / weight_total,
            n_folds = stat.n_folds,
            n_observations = stat.n_observations,
            n_draws_by_fold = copy(stat.n_draws_by_fold),
            n_heldout_by_fold = copy(stat.n_heldout_by_fold),
            folds = copy(stat.folds),
            observation_indices = copy(stat.observation_indices),
            warning = stat.warning,
        ))
    end
    return rows
end

"""
    compare_kfold(stats...; names = nothing)
    compare_kfold(models::Pair...)

Compare heldout K-fold summaries returned by [`kfold`](@ref). Rows are sorted
by `elpd_kfold` in descending order and include differences relative to the
best model, K-fold information-criterion differences, normalized
expected-log-predictive-density weights, and a comparison contract requiring
the same heldout observation order and fold assignment order across models.

This helper compares already computed K-fold summaries. It does not construct
folds or refit models.
"""
function compare_kfold(; names = nothing)
    labels = _compare_model_names(names, 0)
    return _kfold_comparison_rows(labels, Any[])
end

function compare_kfold(stats::NamedTuple...; names = nothing)
    labels = _compare_model_names(names, length(stats))
    return _kfold_comparison_rows(labels, Any[stats...])
end

function compare_kfold(models::Pair...)
    stats = Any[]
    labels = String[]
    for model in models
        push!(labels, string(model.first))
        push!(stats, model.second)
    end
    _compare_model_names(labels, length(labels))
    return _kfold_comparison_rows(labels, stats)
end

function _compare_criterion(criterion::Symbol)
    criterion in (:waic, :loo) ||
        throw(ArgumentError("criterion must be :waic or :loo"))
    return criterion
end

function _model_comparison_contract(fit::_ModelComparisonFit)
    spec = fit.design.spec
    data = spec.data
    return (;
        comparison_contract = _MODEL_COMPARISON_CONTRACT,
        model_family = spec.family,
        thresholds = spec.thresholds,
        dimensions = spec.dimensions,
        discrimination = spec.discrimination,
        q_matrix = _q_matrix_manifest(spec.q_matrix),
        estimation_status = spec.estimation_status,
        data_signature = spec.validation.data_signature,
        n_observations = data.n,
        n_categories = length(data.category_levels),
        category_levels = copy(data.category_levels),
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        optional_facets = sort(collect(keys(data.optional)); by = string),
    )
end

function _require_same_contract_field(
        contracts::AbstractVector,
        field::Symbol,
        message::AbstractString)
    isempty(contracts) && return nothing
    first_value = getproperty(contracts[1], field)
    all(contract -> isequal(getproperty(contract, field), first_value), contracts) ||
        throw(ArgumentError(message))
    return nothing
end

function _require_model_comparison_compatibility(contracts::AbstractVector)
    isempty(contracts) && return nothing
    _require_same_contract_field(contracts, :data_signature,
        "all models must be fit to the same observation data and row order; call waic on each model separately for different data")
    _require_same_contract_field(contracts, :n_observations,
        "all models must have the same number of observations")
    _require_same_contract_field(contracts, :category_levels,
        "all models must use the same ordinal category levels")
    _require_same_contract_field(contracts, :optional_facets,
        "all models must use the same optional facet roles")
    _require_same_contract_field(contracts, :dimensions,
        "all models must use the same latent dimensionality; use a predeclared sensitivity workflow for dimensionality comparisons")
    _require_same_contract_field(contracts, :q_matrix,
        "all multidimensional models must use the same fixed Q-matrix for direct compare_models output")
    return nothing
end

function _require_sensitivity_comparison_compatibility(contracts::AbstractVector,
        axis::Symbol)
    isempty(contracts) && return nothing
    _require_same_contract_field(contracts, :data_signature,
        "all sensitivity candidates must be fit to the same observation data and row order")
    _require_same_contract_field(contracts, :n_observations,
        "all sensitivity candidates must have the same number of observations")
    _require_same_contract_field(contracts, :category_levels,
        "all sensitivity candidates must use the same ordinal category levels")
    _require_same_contract_field(contracts, :optional_facets,
        "all sensitivity candidates must use the same optional facet roles")
    if axis !== :dimensions
        _require_same_contract_field(contracts, :dimensions,
            "all sensitivity candidates must use the same latent dimensionality unless axis = :dimensions")
    end
    if !(axis in (:dimensions, :q_matrix))
        _require_same_contract_field(contracts, :q_matrix,
            "all sensitivity candidates must use the same fixed Q-matrix unless axis = :q_matrix or :dimensions")
    end
    return nothing
end

function _comparison_contract_fields(contract::NamedTuple)
    return (;
        comparison_contract = contract.comparison_contract,
        model_family = contract.model_family,
        thresholds = contract.thresholds,
        dimensions = contract.dimensions,
        discrimination = contract.discrimination,
        q_matrix = contract.q_matrix,
        estimation_status = contract.estimation_status,
        data_signature = contract.data_signature,
        n_categories = contract.n_categories,
        category_levels = copy(contract.category_levels),
        n_persons = contract.n_persons,
        n_raters = contract.n_raters,
        n_items = contract.n_items,
        optional_facets = copy(contract.optional_facets),
    )
end

function _waic_comparison_rows(labels::AbstractVector{<:AbstractString}, stats,
        contracts::AbstractVector)
    n_models = length(stats)
    n_models >= 2 || throw(ArgumentError("at least two models are required"))
    length(contracts) == n_models ||
        throw(ArgumentError("contracts has length $(length(contracts)); expected $n_models"))
    n_observations = stats[1].n_observations
    all(stat -> stat.n_observations == n_observations, stats) ||
        throw(ArgumentError("all models must have the same number of observations"))

    order = sortperm(1:n_models; by = i -> stats[i].elpd_waic, rev = true)
    best = stats[order[1]]
    unnormalized_weights = [exp(stat.elpd_waic - best.elpd_waic) for stat in stats]
    weight_total = sum(unnormalized_weights)
    rows = NamedTuple[]
    for (rank, index) in pairs(order)
        stat = stats[index]
        pointwise_difference = stat.pointwise.elpd_waic .- best.pointwise.elpd_waic
        push!(rows, merge((;
                model = labels[index],
                rank,
                criterion = :waic,
            ),
            _comparison_contract_fields(contracts[index]),
            (;
                elpd_waic = stat.elpd_waic,
                elpd_difference = stat.elpd_waic - best.elpd_waic,
                se_elpd_difference = _pointwise_se(pointwise_difference),
                se_elpd_waic = stat.se_elpd_waic,
                waic = stat.waic,
                waic_difference = stat.waic - best.waic,
                se_waic = stat.se_waic,
                relative_weight = unnormalized_weights[index] / weight_total,
                p_waic = stat.p_waic,
                lppd = stat.lppd,
                n_draws = stat.n_draws,
                n_observations = stat.n_observations,
                high_variance_count = stat.high_variance_count,
                warning = stat.warning,
            )))
    end
    return rows
end

function _loo_comparison_rows(labels::AbstractVector{<:AbstractString}, stats,
        contracts::AbstractVector)
    n_models = length(stats)
    n_models >= 2 || throw(ArgumentError("at least two models are required"))
    length(contracts) == n_models ||
        throw(ArgumentError("contracts has length $(length(contracts)); expected $n_models"))
    n_observations = stats[1].n_observations
    all(stat -> stat.n_observations == n_observations, stats) ||
        throw(ArgumentError("all models must have the same number of observations"))

    order = sortperm(1:n_models; by = i -> stats[i].elpd_loo, rev = true)
    best = stats[order[1]]
    unnormalized_weights = [exp(stat.elpd_loo - best.elpd_loo) for stat in stats]
    weight_total = sum(unnormalized_weights)
    rows = NamedTuple[]
    for (rank, index) in pairs(order)
        stat = stats[index]
        pointwise_difference = stat.pointwise.elpd_loo .- best.pointwise.elpd_loo
        push!(rows, merge((;
                model = labels[index],
                rank,
                criterion = :loo,
            ),
            _comparison_contract_fields(contracts[index]),
            (;
                method = stat.method,
                psis_smoothing = stat.psis_smoothing,
                elpd_loo = stat.elpd_loo,
                elpd_difference = stat.elpd_loo - best.elpd_loo,
                se_elpd_difference = _pointwise_se(pointwise_difference),
                se_elpd_loo = stat.se_elpd_loo,
                looic = stat.looic,
                looic_difference = stat.looic - best.looic,
                se_looic = stat.se_looic,
                relative_weight = unnormalized_weights[index] / weight_total,
                p_loo = stat.p_loo,
                lppd = stat.lppd,
                n_draws = stat.n_draws,
                n_observations = stat.n_observations,
                max_pareto_k = stat.max_pareto_k,
                bad_pareto_k_count = stat.bad_pareto_k_count,
                min_effective_sample_size = stat.min_effective_sample_size,
                warning = stat.warning,
            )))
    end
    return rows
end

function _compare_models_waic(fits::AbstractVector{<:_ModelComparisonFit},
        labels::AbstractVector{<:AbstractString};
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    length(fits) >= 2 || throw(ArgumentError("at least two models are required"))
    length(labels) == length(fits) ||
        throw(ArgumentError("labels has length $(length(labels)); expected $(length(fits))"))
    contracts = [_model_comparison_contract(fit) for fit in fits]
    _require_model_comparison_compatibility(contracts)
    stats = [waic(fit; ndraws, draw_indices, rng) for fit in fits]
    return _waic_comparison_rows(labels, stats, contracts)
end

function _compare_models_loo(fits::AbstractVector{<:_ModelComparisonFit},
        labels::AbstractVector{<:AbstractString};
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    length(fits) >= 2 || throw(ArgumentError("at least two models are required"))
    length(labels) == length(fits) ||
        throw(ArgumentError("labels has length $(length(labels)); expected $(length(fits))"))
    contracts = [_model_comparison_contract(fit) for fit in fits]
    _require_model_comparison_compatibility(contracts)
    stats = [loo(fit; ndraws, draw_indices, rng) for fit in fits]
    return _loo_comparison_rows(labels, stats, contracts)
end

function _sensitivity_compare_models_waic(fits::AbstractVector{<:_ModelComparisonFit},
        labels::AbstractVector{<:AbstractString},
        axis::Symbol;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    length(fits) >= 2 || throw(ArgumentError("at least two models are required"))
    length(labels) == length(fits) ||
        throw(ArgumentError("labels has length $(length(labels)); expected $(length(fits))"))
    contracts = [_model_comparison_contract(fit) for fit in fits]
    _require_sensitivity_comparison_compatibility(contracts, axis)
    stats = [waic(fit; ndraws, draw_indices, rng) for fit in fits]
    return _waic_comparison_rows(labels, stats, contracts)
end

function _sensitivity_compare_models_loo(fits::AbstractVector{<:_ModelComparisonFit},
        labels::AbstractVector{<:AbstractString},
        axis::Symbol;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    length(fits) >= 2 || throw(ArgumentError("at least two models are required"))
    length(labels) == length(fits) ||
        throw(ArgumentError("labels has length $(length(labels)); expected $(length(fits))"))
    contracts = [_model_comparison_contract(fit) for fit in fits]
    _require_sensitivity_comparison_compatibility(contracts, axis)
    stats = [loo(fit; ndraws, draw_indices, rng) for fit in fits]
    return _loo_comparison_rows(labels, stats, contracts)
end

"""
    compare_models(fits...; names = nothing, criterion = :waic,
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng())
    compare_models(models::Pair...; criterion = :waic, ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())

Compare fitted models with WAIC (`criterion = :waic`) or raw
importance-sampling LOO (`criterion = :loo`). MFRM, scalar GMFRM, and internal
guarded MGMFRM fit objects can be compared when they share the same observation
data, row order, ordinal category levels, latent dimensionality, and fixed
Q-matrix contract. Rows are sorted by expected log predictive density in
descending order. `elpd_difference` is relative to the best model and is
therefore zero for the top row and non-positive for lower-ranked rows.
`relative_weight` is a normalized Akaike-style weight computed from the
selected expected log predictive density values. Each row carries the model
family, thresholds, discrimination mode, dimensionality, Q-matrix, and data
signature used by the compatibility check.
"""
function compare_models(fits::_ModelComparisonFit...;
        names = nothing,
        criterion::Symbol = :waic,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    checked_criterion = _compare_criterion(criterion)
    labels = _compare_model_names(names, length(fits))
    collected_fits = _ModelComparisonFit[fits...]
    return checked_criterion === :waic ?
        _compare_models_waic(collected_fits, labels; ndraws, draw_indices, rng) :
        _compare_models_loo(collected_fits, labels; ndraws, draw_indices, rng)
end

function compare_models(models::Pair...;
        criterion::Symbol = :waic,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    checked_criterion = _compare_criterion(criterion)
    fits = _ModelComparisonFit[]
    labels = String[]
    for model in models
        model.second isa _ModelComparisonFit ||
            throw(ArgumentError("model pair :$(model.first) does not contain a comparable fitted model"))
        push!(labels, string(model.first))
        push!(fits, model.second)
    end
    _compare_model_names(labels, length(labels))
    return checked_criterion === :waic ?
        _compare_models_waic(fits, labels; ndraws, draw_indices, rng) :
        _compare_models_loo(fits, labels; ndraws, draw_indices, rng)
end

function _sensitivity_axis(axis::Symbol)
    axis === :threshold && return :thresholds
    axis === :family && return :model_family
    axis === :dimensionality && return :dimensions
    return axis
end

function _sensitivity_prior_value(fit::MFRMFit)
    return (;
        person_sd = fit.prior.person_sd,
        rater_sd = fit.prior.rater_sd,
        item_sd = fit.prior.item_sd,
        step_sd = fit.prior.step_sd,
    )
end

function _sensitivity_prior_value(fit::Union{GMFRMFit,MGMFRMFit})
    return (;
        person_sd = fit.prior.person_sd,
        rater_sd = fit.prior.rater_sd,
        item_sd = fit.prior.item_sd,
        log_discrimination_sd = fit.prior.log_discrimination_sd,
        log_consistency_sd = fit.prior.log_consistency_sd,
        step_sd = fit.prior.step_sd,
    )
end

function _default_sensitivity_value(fit::_ModelComparisonFit,
        label::AbstractString,
        axis::Symbol)
    spec = fit.design.spec
    axis === :model && return String(label)
    axis === :model_family && return spec.family
    axis === :thresholds && return spec.thresholds
    axis === :discrimination && return spec.discrimination
    axis === :dimensions && return spec.dimensions
    axis === :q_matrix && return _q_matrix_manifest(spec.q_matrix)
    axis === :estimation_status && return spec.estimation_status
    axis === :prior && return _sensitivity_prior_value(fit)
    axis === :backend && return fit.backend
    axis === :sampler && return fit.sampler
    throw(ArgumentError(
        "axis = :$axis requires explicit values; supported inferred axes are " *
        ":model, :model_family, :thresholds, :discrimination, :dimensions, " *
        ":q_matrix, :estimation_status, :prior, :backend, and :sampler"))
end

function _explicit_sensitivity_values(
        labels::AbstractVector{<:AbstractString},
        values::NamedTuple)
    out = Any[]
    names = propertynames(values)
    for label in labels
        key = Symbol(label)
        key in names ||
            throw(ArgumentError("values does not contain a value for model $label"))
        push!(out, getproperty(values, key))
    end
    return out
end

function _explicit_sensitivity_values(
        labels::AbstractVector{<:AbstractString},
        values::AbstractDict)
    out = Any[]
    for label in labels
        if haskey(values, label)
            push!(out, values[label])
        elseif haskey(values, Symbol(label))
            push!(out, values[Symbol(label)])
        else
            throw(ArgumentError("values does not contain a value for model $label"))
        end
    end
    return out
end

function _explicit_sensitivity_values(
        labels::AbstractVector{<:AbstractString},
        values)
    collected = collect(values)
    length(collected) == length(labels) ||
        throw(ArgumentError(
            "values has length $(length(collected)); expected $(length(labels))"))
    return Any[collected...]
end

function _sensitivity_value_map(fits::AbstractVector{<:_ModelComparisonFit},
        labels::AbstractVector{<:AbstractString},
        axis::Symbol,
        values)
    resolved_values = values === nothing ?
        [_default_sensitivity_value(fit, label, axis)
            for (fit, label) in zip(fits, labels)] :
        _explicit_sensitivity_values(labels, values)
    return Dict{String,Any}(labels[index] => resolved_values[index]
        for index in eachindex(labels))
end

function _sensitivity_baseline_label(
        labels::AbstractVector{<:AbstractString},
        baseline)
    isempty(labels) && throw(ArgumentError("at least two models are required"))
    baseline === nothing && return labels[1]
    label = string(baseline)
    label in labels ||
        throw(ArgumentError("baseline model $label is not present in the comparison"))
    return label
end

function _sensitivity_baseline_difference(row::NamedTuple, baseline_row::NamedTuple)
    row.criterion === :waic && return (;
        baseline_elpd = baseline_row.elpd_waic,
        baseline_information_criterion = baseline_row.waic,
        elpd_difference_from_baseline = row.elpd_waic - baseline_row.elpd_waic,
        information_criterion_difference_from_baseline = row.waic - baseline_row.waic,
    )
    row.criterion === :loo && return (;
        baseline_elpd = baseline_row.elpd_loo,
        baseline_information_criterion = baseline_row.looic,
        elpd_difference_from_baseline = row.elpd_loo - baseline_row.elpd_loo,
        information_criterion_difference_from_baseline = row.looic - baseline_row.looic,
    )
    row.criterion === :kfold && return (;
        baseline_elpd = baseline_row.elpd_kfold,
        baseline_information_criterion = baseline_row.kfoldic,
        elpd_difference_from_baseline = row.elpd_kfold - baseline_row.elpd_kfold,
        information_criterion_difference_from_baseline =
            row.kfoldic - baseline_row.kfoldic,
    )
    throw(ArgumentError("unsupported comparison criterion $(row.criterion)"))
end

function _sensitivity_comparison_rows(comparison_rows::AbstractVector,
        axis::Symbol,
        value_map::AbstractDict{String,Any},
        baseline_label::AbstractString)
    baseline_index = findfirst(row -> row.model == baseline_label, comparison_rows)
    baseline_index === nothing &&
        throw(ArgumentError("baseline model $baseline_label is not present in comparison rows"))
    baseline_row = comparison_rows[baseline_index]
    baseline_value = value_map[String(baseline_label)]
    rows = NamedTuple[]
    for row in comparison_rows
        value = value_map[row.model]
        is_baseline = row.model == baseline_label
        push!(rows, merge((;
                sensitivity_axis = axis,
                sensitivity_value = value,
                baseline_model = String(baseline_label),
                baseline_value,
                is_baseline,
                sensitivity_contrast = (candidate = value, baseline = baseline_value),
                contrast = is_baseline ? :baseline : :candidate_vs_baseline,
            ),
            row,
            _sensitivity_baseline_difference(row, baseline_row)))
    end
    return rows
end

function _sensitivity_comparison(fits::AbstractVector{<:_ModelComparisonFit},
        labels::AbstractVector{<:AbstractString};
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing,
        criterion::Symbol = :waic,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    checked_axis = _sensitivity_axis(axis)
    checked_criterion = _compare_criterion(criterion)
    _compare_model_names(labels, length(labels))
    value_map = _sensitivity_value_map(fits, labels, checked_axis, values)
    baseline_label = _sensitivity_baseline_label(labels, baseline)
    comparison_rows = checked_criterion === :waic ?
        _sensitivity_compare_models_waic(fits, labels, checked_axis;
            ndraws, draw_indices, rng) :
        _sensitivity_compare_models_loo(fits, labels, checked_axis;
            ndraws, draw_indices, rng)
    return _sensitivity_comparison_rows(
        comparison_rows,
        checked_axis,
        value_map,
        baseline_label,
    )
end

"""
    sensitivity_comparison(fits...; names = nothing, axis = :model,
        values = nothing, baseline = nothing, criterion = :waic,
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng())
    sensitivity_comparison(models::Pair...; axis = :model, values = nothing,
        baseline = nothing, criterion = :waic, ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())

Return report-ready sensitivity comparison rows for already fitted candidate
models. The function uses the same WAIC and raw-importance LOO scoring rows as
[`compare_models`](@ref), while applying sensitivity-specific compatibility
checks. Additional columns identify the requested
`sensitivity_axis`, the per-model `sensitivity_value`, the baseline model and
value, and expected-log-predictive-density and information-criterion
differences relative to that baseline.

When `values` is omitted, values are inferred for common axes: `:model`,
`:model_family`, `:thresholds`, `:discrimination`, `:dimensions`, `:q_matrix`,
`:estimation_status`, `:prior`, `:backend`, and `:sampler`. Pass a vector,
tuple, dictionary, or named tuple to `values` for custom axes such as
`:anchor`, `:dff`, or externally defined prior regimes. `baseline` names the
baseline model label and defaults to the first supplied model. Direct
`compare_models` output still requires matching dimensions and Q-matrices;
declared `sensitivity_comparison` rows allow dimensionality differences for
`axis = :dimensions`, and fixed-Q differences for `axis = :q_matrix` or
`:dimensions`, while retaining same-data and same-category checks.
"""
function sensitivity_comparison(fits::_ModelComparisonFit...;
        names = nothing,
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing,
        criterion::Symbol = :waic,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    labels = _compare_model_names(names, length(fits))
    collected_fits = _ModelComparisonFit[fits...]
    return _sensitivity_comparison(collected_fits, labels;
        axis,
        values,
        baseline,
        criterion,
        ndraws,
        draw_indices,
        rng)
end

function sensitivity_comparison(models::Pair...;
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing,
        criterion::Symbol = :waic,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    fits = _ModelComparisonFit[]
    labels = String[]
    for model in models
        model.second isa _ModelComparisonFit ||
            throw(ArgumentError("model pair :$(model.first) does not contain a comparable fitted model"))
        push!(labels, string(model.first))
        push!(fits, model.second)
    end
    _compare_model_names(labels, length(labels))
    return _sensitivity_comparison(fits, labels;
        axis,
        values,
        baseline,
        criterion,
        ndraws,
        draw_indices,
        rng)
end

function _kfold_sensitivity_value_map(labels::AbstractVector{<:AbstractString},
        axis::Symbol,
        values)
    resolved_values = if values === nothing
        axis === :model ||
            throw(ArgumentError(
                "axis = :$axis requires explicit values for K-fold sensitivity rows"))
        Any[String(label) for label in labels]
    else
        _explicit_sensitivity_values(labels, values)
    end
    return Dict{String,Any}(labels[index] => resolved_values[index]
        for index in eachindex(labels))
end

function _kfold_sensitivity_comparison(stats::AbstractVector,
        labels::AbstractVector{<:AbstractString};
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing)
    checked_axis = _sensitivity_axis(axis)
    _compare_model_names(labels, length(labels))
    value_map = _kfold_sensitivity_value_map(labels, checked_axis, values)
    baseline_label = _sensitivity_baseline_label(labels, baseline)
    comparison_rows = _kfold_comparison_rows(labels, stats)
    return _sensitivity_comparison_rows(
        comparison_rows,
        checked_axis,
        value_map,
        baseline_label,
    )
end

"""
    kfold_sensitivity_comparison(stats...; names = nothing, axis = :model,
        values = nothing, baseline = nothing)
    kfold_sensitivity_comparison(models::Pair...; axis = :model,
        values = nothing, baseline = nothing)

Return report-ready sensitivity rows for supplied heldout K-fold summaries.
This helper uses [`compare_kfold`](@ref) compatibility checks, then adds the
declared sensitivity axis, per-model values, baseline label, baseline value,
and baseline-relative heldout ELPD and K-fold information-criterion
differences. It does not construct folds or refit models. For axes other than
`:model`, pass explicit `values`.
"""
function kfold_sensitivity_comparison(stats::NamedTuple...;
        names = nothing,
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing)
    labels = _compare_model_names(names, length(stats))
    return _kfold_sensitivity_comparison(Any[stats...], labels;
        axis,
        values,
        baseline)
end

function kfold_sensitivity_comparison(;
        names = nothing,
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing)
    labels = _compare_model_names(names, 0)
    return _kfold_sensitivity_comparison(Any[], labels;
        axis,
        values,
        baseline)
end

function kfold_sensitivity_comparison(models::Pair...;
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing)
    stats = Any[]
    labels = String[]
    for model in models
        push!(labels, string(model.first))
        push!(stats, model.second)
    end
    _compare_model_names(labels, length(labels))
    return _kfold_sensitivity_comparison(stats, labels;
        axis,
        values,
        baseline)
end

const _DEFAULT_SENSITIVITY_REQUIRED_AXES = (
    :thresholds,
    :discrimination,
    :rater_pooling,
    :dff,
    :anchor,
    :dimensions,
    :prior_regime,
)

function _sensitivity_summary_axis(axis::Symbol)
    checked = _sensitivity_axis(axis)
    checked === :prior && return :prior_regime
    checked in (:anchors, :anchoring) && return :anchor
    checked in (:pooling, :rater_effects, :rater_pooling) && return :rater_pooling
    checked in (:dff_on_off, :dff_effects) && return :dff
    return checked
end

function _sensitivity_summary_axis(axis)
    axis isa Symbol ||
        throw(ArgumentError("sensitivity axes must be Symbols"))
    return _sensitivity_summary_axis(axis)
end

function _sensitivity_axis_tuple(axes)
    out = Symbol[]
    for axis in axes
        canonical = _sensitivity_summary_axis(axis)
        canonical in out || push!(out, canonical)
    end
    return Tuple(out)
end

function _sensitivity_axis_tuple(axis::Symbol)
    return (_sensitivity_summary_axis(axis),)
end

function _sensitivity_unique_tuple(values)
    collected = collect(Set(values))
    sort!(collected; by = string)
    return Tuple(collected)
end

function _sensitivity_summary_row_check(row::NamedTuple)
    required = (
        :sensitivity_axis,
        :sensitivity_value,
        :baseline_value,
        :model,
        :baseline_model,
        :is_baseline,
        :contrast,
        :criterion,
        :elpd_difference_from_baseline,
        :information_criterion_difference_from_baseline,
    )
    fields = propertynames(row)
    missing_fields = [field for field in required if !(field in fields)]
    isempty(missing_fields) ||
        throw(ArgumentError("sensitivity comparison row is missing fields: $(join(missing_fields, ", "))"))
    row.sensitivity_axis isa Symbol ||
        throw(ArgumentError("sensitivity_axis must be a Symbol"))
    row.is_baseline isa Bool ||
        throw(ArgumentError("is_baseline must be a Bool"))
    row.criterion isa Symbol ||
        throw(ArgumentError("criterion must be a Symbol"))
    return nothing
end

function _sensitivity_axis_summary_row(axis::Symbol, rows::AbstractVector)
    if isempty(rows)
        return (;
            axis,
            present = false,
            status = :missing,
            n_rows = 0,
            n_models = 0,
            models = (),
            n_values = 0,
            sensitivity_values = (),
            has_baseline = false,
            n_baseline_rows = 0,
            n_candidate_rows = 0,
            baseline_models = (),
            criteria = (),
            warnings = (),
        )
    end

    models = _sensitivity_unique_tuple(String(string(row.model)) for row in rows)
    values = _sensitivity_unique_tuple(row.sensitivity_value for row in rows)
    baseline_models =
        _sensitivity_unique_tuple(String(string(row.baseline_model)) for row in rows)
    criteria = _sensitivity_unique_tuple(row.criterion for row in rows)
    n_baseline_rows = count(row -> row.is_baseline, rows)
    n_candidate_rows = length(rows) - n_baseline_rows
    has_baseline = n_baseline_rows > 0
    has_candidate = n_candidate_rows > 0
    warnings = Symbol[]
    length(criteria) > 1 && push!(warnings, :mixed_criteria)
    length(baseline_models) > 1 && push!(warnings, :multiple_baselines)
    status = has_baseline && has_candidate ? :complete : :incomplete

    return (;
        axis,
        present = true,
        status,
        n_rows = length(rows),
        n_models = length(models),
        models,
        n_values = length(values),
        sensitivity_values = values,
        has_baseline,
        n_baseline_rows,
        n_candidate_rows,
        baseline_models,
        criteria,
        warnings = Tuple(warnings),
    )
end

"""
    sensitivity_comparison_summary(rows; required_axes =
        (:thresholds, :discrimination, :rater_pooling, :dff, :anchor,
         :dimensions, :prior_regime))
    sensitivity_comparison_summary(row, rows...; required_axes = ...)

Summarize report-ready sensitivity comparison rows and check whether the
declared sensitivity table covers the package's default critical-review axes:
threshold family, discrimination on/off, pooled versus unpooled rater effects,
DFF on/off, anchor choice, dimensionality, and prior regime. Rows are expected
to come from [`sensitivity_comparison`](@ref) or an equivalent same-schema
external comparison table.

The summary records observed axes, missing required axes, per-axis model and
baseline coverage, criteria used, and whether every required axis has both a
baseline and at least one candidate row. It audits declared comparison rows; it
does not create refits, fit unsupported generalized/DFF/anchor models, or
replace predeclared simulation and case-study protocols.
"""
function sensitivity_comparison_summary(rows::AbstractVector;
        required_axes = _DEFAULT_SENSITIVITY_REQUIRED_AXES)
    isempty(rows) &&
        throw(ArgumentError("at least one sensitivity comparison row is required"))
    for row in rows
        row isa NamedTuple ||
            throw(ArgumentError("sensitivity comparison summary expects NamedTuple rows"))
        _sensitivity_summary_row_check(row)
    end

    checked_required = _sensitivity_axis_tuple(required_axes)
    observed_axes = _sensitivity_unique_tuple(
        _sensitivity_summary_axis(row.sensitivity_axis) for row in rows)
    observed_set = Set(observed_axes)
    missing_required_axes =
        Tuple(axis for axis in checked_required if !(axis in observed_set))
    extra_axes = sort(
        [axis for axis in observed_axes if !(axis in checked_required)];
        by = string)
    reported_axes = (checked_required..., extra_axes...)
    axis_rows = NamedTuple[]
    for axis in reported_axes
        axis_specific_rows = NamedTuple[
            row for row in rows
            if _sensitivity_summary_axis(row.sensitivity_axis) === axis
        ]
        push!(axis_rows, _sensitivity_axis_summary_row(axis, axis_specific_rows))
    end

    required_axis_rows = filter(row -> row.axis in checked_required, axis_rows)
    incomplete_required_axes = Tuple(row.axis for row in required_axis_rows
        if row.status !== :complete)
    complete_required_axes = Tuple(row.axis for row in required_axis_rows
        if row.status === :complete)
    criteria = _sensitivity_unique_tuple(row.criterion for row in rows)
    baseline_models =
        _sensitivity_unique_tuple(String(string(row.baseline_model)) for row in rows)
    n_baseline_rows = count(row -> row.is_baseline, rows)

    return (;
        schema = "bayesianmgmfrm.sensitivity_comparison_summary.v1",
        object = :sensitivity_comparison_summary,
        comparison_scope = :declared_same_data_sensitivity_rows,
        coverage_contract = :required_axes_need_baseline_and_candidate_rows,
        required_axes = checked_required,
        observed_axes,
        missing_required_axes,
        complete_required_axes,
        incomplete_required_axes,
        passed = isempty(missing_required_axes) && isempty(incomplete_required_axes),
        n_rows = length(rows),
        n_axes = length(observed_axes),
        n_required_axes = length(checked_required),
        n_complete_required_axes = length(complete_required_axes),
        n_baseline_rows,
        n_candidate_rows = length(rows) - n_baseline_rows,
        criteria,
        baseline_models,
        axis_rows = Tuple(axis_rows),
        caveat = :summary_of_declared_rows_not_refit_orchestration,
        next_gate = :predeclared_case_study_sensitivity_grid,
    )
end

function sensitivity_comparison_summary(row::NamedTuple, rows::NamedTuple...;
        required_axes = _DEFAULT_SENSITIVITY_REQUIRED_AXES)
    return sensitivity_comparison_summary([row; collect(rows)]; required_axes)
end

const _DEFAULT_COMPARISON_EVIDENCE_CLASSES = (
    :stan_faithful,
    :r_frequentist,
    :nested_model,
)

function _comparison_evidence_class(class::Symbol)
    class in (:stan, :bridge_stan, :bridgestan, :stan_faithful, :faithful_stan) &&
        return :stan_faithful
    class in (:r, :frequentist, :r_frequentist, :overlapping_r,
        :overlapping_frequentist, :facets, :tam, :sirt, :immer, :mirt) &&
        return :r_frequentist
    class in (:nested, :nested_model, :simpler_nested, :baseline,
        :baseline_model, :mfrm_baseline, :pcm_baseline, :rsm_baseline) &&
        return :nested_model
    return class
end

function _comparison_class_tuple(classes)
    out = Symbol[]
    for class in classes
        class isa Symbol ||
            throw(ArgumentError("comparison evidence classes must be Symbols"))
        canonical = _comparison_evidence_class(class)
        canonical in out || push!(out, canonical)
    end
    return Tuple(out)
end

_comparison_class_tuple(class::Symbol) = (_comparison_evidence_class(class),)

function _comparison_finite_float(value::Real, name::Symbol; minimum = nothing)
    checked = Float64(value)
    isfinite(checked) ||
        throw(ArgumentError("$name must be finite"))
    if minimum !== nothing
        checked >= Float64(minimum) ||
            throw(ArgumentError("$name must be >= $minimum"))
    end
    return checked
end

function _comparison_pass_if(pass_if::Symbol)
    pass_if in (:within_tolerance, :greater_equal, :less_equal) ||
        throw(ArgumentError(
            "pass_if must be :within_tolerance, :greater_equal, or :less_equal",
        ))
    return pass_if
end

function _comparison_evidence_passed(difference::Float64,
        tolerance::Float64,
        pass_if::Symbol)
    pass_if === :within_tolerance && return abs(difference) <= tolerance
    pass_if === :greater_equal && return difference >= -tolerance
    return difference <= tolerance
end

"""
    comparison_evidence_row(; comparison_class, target_model, comparator,
        metric, estimate, reference, tolerance = 0.0,
        pass_if = :within_tolerance, evidence = :declared_comparison,
        label = nothing, artifact = nothing, source = nothing)

Return one machine-readable comparison-evidence row for a precomputed result
against a faithful Stan/BridgeStan model, an overlapping R/frequentist tool, or a
simpler nested model. `estimate` is the focal Julia/Bayesian value and
`reference` is the comparator value. `pass_if = :within_tolerance` checks
absolute agreement, while `:greater_equal` and `:less_equal` check directional
comparisons such as heldout ELPD gains.

This helper records already computed evidence; it does not run Stan, call R,
fit nested models, or refit heldout folds.
"""
function comparison_evidence_row(;
        comparison_class::Symbol,
        target_model::Symbol,
        comparator::Symbol,
        metric::Symbol,
        estimate::Real,
        reference::Real,
        tolerance::Real = 0.0,
        pass_if::Symbol = :within_tolerance,
        evidence::Symbol = :declared_comparison,
        label = nothing,
        artifact = nothing,
        source = nothing)
    checked_class = _comparison_evidence_class(comparison_class)
    checked_estimate = _comparison_finite_float(estimate, :estimate)
    checked_reference = _comparison_finite_float(reference, :reference)
    checked_tolerance =
        _comparison_finite_float(tolerance, :tolerance; minimum = 0)
    checked_pass_if = _comparison_pass_if(pass_if)
    difference = checked_estimate - checked_reference
    passed = _comparison_evidence_passed(difference, checked_tolerance, checked_pass_if)
    return (;
        schema = "bayesianmgmfrm.comparison_evidence_row.v1",
        object = :comparison_evidence_row,
        label = label === nothing ? comparator : label,
        comparison_class = checked_class,
        target_model,
        comparator,
        metric,
        estimate = checked_estimate,
        reference = checked_reference,
        difference,
        absolute_difference = abs(difference),
        tolerance = checked_tolerance,
        pass_if = checked_pass_if,
        passed,
        status = passed ? :passed : :failed,
        evidence,
        artifact,
        source,
        caveat = :declared_comparison_evidence_not_runner,
    )
end

function _comparison_evidence_summary_row_check(row::NamedTuple)
    required = (
        :comparison_class,
        :target_model,
        :comparator,
        :metric,
        :passed,
        :status,
        :evidence,
    )
    fields = propertynames(row)
    missing_fields = [field for field in required if !(field in fields)]
    isempty(missing_fields) ||
        throw(ArgumentError("comparison evidence row is missing fields: $(join(missing_fields, ", "))"))
    return nothing
end

function _comparison_evidence_class_summary(class::Symbol, rows::AbstractVector)
    class_rows = [row for row in rows
        if _comparison_evidence_class(row.comparison_class) === class]
    if isempty(class_rows)
        return (;
            comparison_class = class,
            present = false,
            status = :missing,
            n_rows = 0,
            n_passed_rows = 0,
            n_failed_rows = 0,
            target_models = (),
            comparators = (),
            metrics = (),
            evidence = (),
            artifacts = (),
        )
    end
    n_passed = count(row -> row.passed === true, class_rows)
    n_failed = length(class_rows) - n_passed
    artifacts = _sensitivity_unique_tuple(
        row.artifact for row in class_rows
        if hasproperty(row, :artifact) && row.artifact !== nothing)
    return (;
        comparison_class = class,
        present = true,
        status = n_failed == 0 ? :passed : :failed,
        n_rows = length(class_rows),
        n_passed_rows = n_passed,
        n_failed_rows = n_failed,
        target_models = _sensitivity_unique_tuple(row.target_model for row in class_rows),
        comparators = _sensitivity_unique_tuple(row.comparator for row in class_rows),
        metrics = _sensitivity_unique_tuple(row.metric for row in class_rows),
        evidence = _sensitivity_unique_tuple(row.evidence for row in class_rows),
        artifacts,
    )
end

"""
    comparison_evidence_summary(rows; required_classes =
        (:stan_faithful, :r_frequentist, :nested_model))
    comparison_evidence_summary(row, rows...; required_classes = ...)

Summarize declared comparison-evidence rows and check whether the default
critical-review comparison classes are present and passing: faithful
Stan/BridgeStan models, overlapping R/frequentist tools, and simpler nested
models. The summary is a coverage check over recorded comparison rows; it does
not execute external tools or refit models.
"""
function comparison_evidence_summary(rows::AbstractVector;
        required_classes = _DEFAULT_COMPARISON_EVIDENCE_CLASSES)
    isempty(rows) &&
        throw(ArgumentError("at least one comparison evidence row is required"))
    for row in rows
        row isa NamedTuple ||
            throw(ArgumentError("comparison evidence summary expects NamedTuple rows"))
        _comparison_evidence_summary_row_check(row)
    end

    checked_required = _comparison_class_tuple(required_classes)
    observed_classes = _sensitivity_unique_tuple(
        _comparison_evidence_class(row.comparison_class) for row in rows)
    observed_set = Set(observed_classes)
    missing_required_classes = Tuple(class for class in checked_required
        if !(class in observed_set))
    class_rows = [_comparison_evidence_class_summary(class, rows)
        for class in checked_required]
    failed_required_classes = Tuple(row.comparison_class for row in class_rows
        if row.status === :failed)
    passed_required_classes = Tuple(row.comparison_class for row in class_rows
        if row.status === :passed)
    n_passed_rows = count(row -> row.passed === true, rows)

    return (;
        schema = "bayesianmgmfrm.comparison_evidence_summary.v1",
        object = :comparison_evidence_summary,
        comparison_scope = :stan_r_frequentist_nested_evidence,
        coverage_contract = :required_classes_present_and_passing,
        required_classes = checked_required,
        observed_classes,
        missing_required_classes,
        passed_required_classes,
        failed_required_classes,
        n_rows = length(rows),
        n_passed_rows,
        n_failed_rows = length(rows) - n_passed_rows,
        n_classes = length(observed_classes),
        class_rows = Tuple(class_rows),
        passed = isempty(missing_required_classes) && isempty(failed_required_classes),
        status = isempty(missing_required_classes) && isempty(failed_required_classes) ?
            :complete : :incomplete,
        caveat = :summary_of_declared_comparison_rows_not_external_runner,
        next_gate = :idle_machine_repeated_benchmarks,
    )
end

function comparison_evidence_summary(row::NamedTuple, rows::NamedTuple...;
        required_classes = _DEFAULT_COMPARISON_EVIDENCE_CLASSES)
    return comparison_evidence_summary([row; collect(rows)]; required_classes)
end

const _DEFAULT_BENCHMARK_REQUIRED_ENGINES = (
    :julia,
    :stan,
)

function _benchmark_engine(engine::Symbol)
    engine in (:julia, :advancedhmc, :turing, :native_julia) && return :julia
    engine in (:stan, :cmdstan, :bridge_stan, :bridgestan) && return :stan
    return engine
end

function _benchmark_engine_tuple(engines)
    out = Symbol[]
    for engine in engines
        engine isa Symbol ||
            throw(ArgumentError("benchmark engines must be Symbols"))
        canonical = _benchmark_engine(engine)
        canonical in out || push!(out, canonical)
    end
    return Tuple(out)
end

_benchmark_engine_tuple(engine::Symbol) = (_benchmark_engine(engine),)

function _benchmark_numeric_tuple(values, name::Symbol; minimum::Real = 0)
    out = if values isa Number
        (values,)
    else
        Tuple(values)
    end
    isempty(out) &&
        throw(ArgumentError("$name must contain at least one value"))
    checked = Float64[]
    for value in out
        numeric = Float64(value)
        isfinite(numeric) ||
            throw(ArgumentError("$name values must be finite"))
        numeric >= Float64(minimum) ||
            throw(ArgumentError("$name values must be >= $minimum"))
        push!(checked, numeric)
    end
    return Tuple(checked)
end

function _benchmark_iqr(values::Tuple)
    sorted = sort(collect(Float64, values))
    return _quantile_sorted(sorted, 0.75) - _quantile_sorted(sorted, 0.25)
end

function _benchmark_median(values::Tuple)
    return _quantile_sorted(sort(collect(Float64, values)), 0.5)
end

function _benchmark_optional_threshold(value)
    value === nothing && return missing
    return _benchmark_numeric_tuple(value, :time_to_quality_threshold_seconds)[1]
end

"""
    benchmark_result_row(; benchmark, engine, model, elapsed_seconds,
        effective_sample_sizes = nothing, time_to_quality_seconds = elapsed_seconds,
        time_to_quality_threshold_seconds = nothing, idle_machine = true,
        target_quality = :predeclared_quality_gate, hardware = nothing,
        software = nothing, artifact = nothing)

Summarize one repeated benchmark result row. `elapsed_seconds` must contain one
or more repeated timings and is summarized with median and IQR. When
`effective_sample_sizes` is supplied, the row also reports median/IQR ESS/sec.
`time_to_quality_seconds` records repeated time-to-quality measurements, checked
against `time_to_quality_threshold_seconds` when provided.

This helper records benchmark evidence from an idle-machine run; it does not run
the benchmark itself or enforce hardware isolation.
"""
function benchmark_result_row(;
        benchmark::Symbol,
        engine::Symbol,
        model::Symbol,
        elapsed_seconds,
        effective_sample_sizes = nothing,
        time_to_quality_seconds = elapsed_seconds,
        time_to_quality_threshold_seconds = nothing,
        idle_machine::Bool = true,
        target_quality::Symbol = :predeclared_quality_gate,
        hardware = nothing,
        software = nothing,
        artifact = nothing)
    elapsed = _benchmark_numeric_tuple(elapsed_seconds, :elapsed_seconds; minimum = eps())
    n_repetitions = length(elapsed)
    time_to_quality = _benchmark_numeric_tuple(
        time_to_quality_seconds,
        :time_to_quality_seconds;
        minimum = eps(),
    )
    length(time_to_quality) == n_repetitions ||
        throw(ArgumentError("time_to_quality_seconds must have the same length as elapsed_seconds"))
    threshold = _benchmark_optional_threshold(time_to_quality_threshold_seconds)

    ess_values = effective_sample_sizes === nothing ?
        nothing :
        _benchmark_numeric_tuple(effective_sample_sizes, :effective_sample_sizes)
    if ess_values !== nothing && length(ess_values) != n_repetitions
        throw(ArgumentError("effective_sample_sizes must have the same length as elapsed_seconds"))
    end
    ess_per_second = ess_values === nothing ?
        nothing :
        Tuple(ess_values[index] / elapsed[index] for index in eachindex(elapsed))
    time_to_quality_median = _benchmark_median(time_to_quality)
    threshold_passed = threshold === missing ?
        missing :
        time_to_quality_median <= threshold
    status = !idle_machine ? :not_idle :
        threshold_passed === false ? :failed :
        threshold_passed === true ? :passed :
        :recorded

    return (;
        schema = "bayesianmgmfrm.benchmark_result_row.v1",
        object = :benchmark_result_row,
        benchmark,
        engine = _benchmark_engine(engine),
        reported_engine = engine,
        model,
        n_repetitions,
        idle_machine,
        target_quality,
        elapsed_seconds = elapsed,
        elapsed_median_seconds = _benchmark_median(elapsed),
        elapsed_iqr_seconds = _benchmark_iqr(elapsed),
        effective_sample_sizes = ess_values === nothing ? missing : ess_values,
        ess_per_second = ess_per_second === nothing ? missing : ess_per_second,
        ess_per_second_median =
            ess_per_second === nothing ? missing : _benchmark_median(ess_per_second),
        ess_per_second_iqr =
            ess_per_second === nothing ? missing : _benchmark_iqr(ess_per_second),
        time_to_quality_seconds = time_to_quality,
        time_to_quality_median_seconds = time_to_quality_median,
        time_to_quality_iqr_seconds = _benchmark_iqr(time_to_quality),
        time_to_quality_threshold_seconds = threshold,
        time_to_quality_passed = threshold_passed,
        status,
        hardware,
        software,
        artifact,
        caveat = :local_idle_machine_benchmark_not_portable,
    )
end

function _benchmark_summary_row_check(row::NamedTuple)
    required = (
        :benchmark,
        :engine,
        :model,
        :n_repetitions,
        :idle_machine,
        :elapsed_median_seconds,
        :elapsed_iqr_seconds,
        :ess_per_second_median,
        :time_to_quality_median_seconds,
        :time_to_quality_passed,
        :status,
    )
    fields = propertynames(row)
    missing_fields = [field for field in required if !(field in fields)]
    isempty(missing_fields) ||
        throw(ArgumentError("benchmark row is missing fields: $(join(missing_fields, ", "))"))
    return nothing
end

function _benchmark_median_field(rows::AbstractVector, field::Symbol)
    values = Float64[]
    for row in rows
        value = getproperty(row, field)
        value === missing && continue
        push!(values, Float64(value))
    end
    isempty(values) && return missing
    return _benchmark_median(Tuple(values))
end

function _benchmark_engine_rows(rows::AbstractVector, engine::Symbol)
    return [row for row in rows if _benchmark_engine(row.engine) === engine]
end

function _benchmark_ratio_row(benchmark, rows::AbstractVector, required_engines::Tuple,
        min_repetitions::Int)
    observed_engines = _sensitivity_unique_tuple(_benchmark_engine(row.engine) for row in rows)
    missing_required_engines = Tuple(engine for engine in required_engines
        if !(engine in observed_engines))
    julia_rows = _benchmark_engine_rows(rows, :julia)
    stan_rows = _benchmark_engine_rows(rows, :stan)
    julia_elapsed = isempty(julia_rows) ?
        missing :
        _benchmark_median_field(julia_rows, :elapsed_median_seconds)
    stan_elapsed = isempty(stan_rows) ?
        missing :
        _benchmark_median_field(stan_rows, :elapsed_median_seconds)
    julia_ess = isempty(julia_rows) ?
        missing :
        _benchmark_median_field(julia_rows, :ess_per_second_median)
    stan_ess = isempty(stan_rows) ?
        missing :
        _benchmark_median_field(stan_rows, :ess_per_second_median)
    stan_to_julia_elapsed_ratio =
        julia_elapsed === missing || stan_elapsed === missing ?
        missing :
        stan_elapsed / julia_elapsed
    julia_to_stan_ess_per_second_ratio =
        julia_ess === missing || stan_ess === missing || iszero(stan_ess) ?
        missing :
        julia_ess / stan_ess
    rows_with_few_repetitions =
        count(row -> Int(row.n_repetitions) < min_repetitions, rows)
    failed_time_to_quality =
        count(row -> row.time_to_quality_passed === false, rows)
    all_idle = all(row -> row.idle_machine === true, rows)
    status = isempty(missing_required_engines) &&
        rows_with_few_repetitions == 0 &&
        failed_time_to_quality == 0 &&
        all_idle ? :complete : :incomplete

    return (;
        benchmark,
        status,
        n_rows = length(rows),
        observed_engines,
        missing_required_engines,
        rows_with_few_repetitions,
        min_repetitions,
        all_idle,
        failed_time_to_quality,
        julia_elapsed_median_seconds = julia_elapsed,
        stan_elapsed_median_seconds = stan_elapsed,
        stan_to_julia_elapsed_ratio,
        julia_ess_per_second_median = julia_ess,
        stan_ess_per_second_median = stan_ess,
        julia_to_stan_ess_per_second_ratio,
    )
end

"""
    benchmark_summary(rows; required_engines = (:julia, :stan),
        min_repetitions = 3)
    benchmark_summary(row, rows...; required_engines = ..., min_repetitions = 3)

Summarize repeated idle-machine benchmark rows. The summary checks required
engine coverage, minimum repetitions, idle-machine flags, time-to-quality
threshold failures, and per-benchmark Stan/Julia elapsed-time and ESS/sec ratios.
It aggregates recorded benchmark rows; it does not run benchmarks.
"""
function benchmark_summary(rows::AbstractVector;
        required_engines = _DEFAULT_BENCHMARK_REQUIRED_ENGINES,
        min_repetitions::Integer = 3)
    isempty(rows) &&
        throw(ArgumentError("at least one benchmark row is required"))
    checked_min_repetitions =
        _simulation_positive_integer(min_repetitions, :min_repetitions)
    for row in rows
        row isa NamedTuple ||
            throw(ArgumentError("benchmark summary expects NamedTuple rows"))
        _benchmark_summary_row_check(row)
    end
    checked_required = _benchmark_engine_tuple(required_engines)
    observed_engines = _sensitivity_unique_tuple(_benchmark_engine(row.engine) for row in rows)
    missing_required_engines = Tuple(engine for engine in checked_required
        if !(engine in observed_engines))
    benchmarks = _sensitivity_unique_tuple(row.benchmark for row in rows)
    benchmark_rows = NamedTuple[]
    for benchmark in benchmarks
        benchmark_specific = [row for row in rows if row.benchmark === benchmark]
        push!(benchmark_rows, _benchmark_ratio_row(
            benchmark,
            benchmark_specific,
            checked_required,
            checked_min_repetitions,
        ))
    end
    incomplete_benchmarks = Tuple(row.benchmark for row in benchmark_rows
        if row.status !== :complete)
    rows_with_few_repetitions =
        count(row -> Int(row.n_repetitions) < checked_min_repetitions, rows)
    failed_time_to_quality =
        count(row -> row.time_to_quality_passed === false, rows)
    all_idle = all(row -> row.idle_machine === true, rows)
    passed = isempty(missing_required_engines) &&
        isempty(incomplete_benchmarks) &&
        rows_with_few_repetitions == 0 &&
        failed_time_to_quality == 0 &&
        all_idle

    return (;
        schema = "bayesianmgmfrm.benchmark_summary.v1",
        object = :benchmark_summary,
        benchmark_scope = :idle_machine_repeated_benchmarks,
        coverage_contract = :required_engines_repeated_idle_and_quality_checked,
        required_engines = checked_required,
        observed_engines,
        missing_required_engines,
        n_rows = length(rows),
        n_benchmarks = length(benchmarks),
        min_repetitions = checked_min_repetitions,
        rows_with_few_repetitions,
        all_idle,
        failed_time_to_quality,
        incomplete_benchmarks,
        benchmark_rows = Tuple(benchmark_rows),
        passed,
        status = passed ? :complete : :incomplete,
        caveat = :local_benchmark_summary_not_portable_performance_claim,
        next_gate = :external_release_decision,
    )
end

function benchmark_summary(row::NamedTuple, rows::NamedTuple...;
        required_engines = _DEFAULT_BENCHMARK_REQUIRED_ENGINES,
        min_repetitions::Integer = 3)
    return benchmark_summary([row; collect(rows)]; required_engines, min_repetitions)
end

function _draw_indices(fit, ndraws::Union{Nothing,Int}, rng::AbstractRNG)
    total = size(fit.draws, 1)
    if ndraws === nothing
        return collect(1:total)
    end
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    return rand(rng, 1:total, ndraws)
end

function _validate_draw_indices(fit, draw_indices)
    indices = collect(Int, draw_indices)
    isempty(indices) && throw(ArgumentError("draw_indices must not be empty"))
    total = size(fit.draws, 1)
    all(index -> 1 <= index <= total, indices) ||
        throw(ArgumentError("draw_indices are out of bounds"))
    return indices
end

function _posterior_draw_indices(fit, ndraws::Union{Nothing,Int}, draw_indices, rng::AbstractRNG)
    if draw_indices !== nothing && ndraws !== nothing
        throw(ArgumentError("pass either ndraws or draw_indices, not both"))
    end
    return draw_indices === nothing ?
        _draw_indices(fit, ndraws, rng) :
        _validate_draw_indices(fit, draw_indices)
end

function _category_probabilities!(probs::AbstractVector{Float64},
        design::FacetDesign,
        params::AbstractVector,
        row::Int)
    _linear_predictors!(probs, design, params, row)
    return _softmax_eta!(probs)
end

function _softmax_eta!(probs::AbstractVector{Float64})
    max_eta = maximum(probs)

    denom = 0.0
    for category in eachindex(probs)
        p = exp(probs[category] - max_eta)
        probs[category] = p
        denom += p
    end
    probs ./= denom
    return probs
end

function _gmfrm_direct_draws_for_prediction(
        design::FacetDesign,
        direct_draws::AbstractMatrix,
        caller::AbstractString)
    _check_gmfrm_source_fixture_design(design, caller)
    size(direct_draws, 1) >= 1 ||
        throw(ArgumentError("$caller requires at least one draw"))
    expected = length(design.parameter_names)
    size(direct_draws, 2) == expected ||
        throw(ArgumentError("direct_draws has $(size(direct_draws, 2)) column(s); expected $expected"))
    all(value -> isfinite(Float64(value)), direct_draws) ||
        throw(ArgumentError("direct_draws contain non-finite values"))
    for draw in axes(direct_draws, 1)
        _gmfrm_source_fixture_constraints(design, @view direct_draws[draw, :])
    end
    return direct_draws
end

function _mgmfrm_direct_draws_for_prediction(
        design::FacetDesign,
        direct_draws::AbstractMatrix,
        caller::AbstractString)
    _check_mgmfrm_source_fixture_design(design, caller)
    size(direct_draws, 1) >= 1 ||
        throw(ArgumentError("$caller requires at least one draw"))
    expected = length(design.parameter_names)
    size(direct_draws, 2) == expected ||
        throw(ArgumentError("direct_draws has $(size(direct_draws, 2)) column(s); expected $expected"))
    all(value -> isfinite(Float64(value)), direct_draws) ||
        throw(ArgumentError("direct_draws contain non-finite values"))
    for draw in axes(direct_draws, 1)
        _mgmfrm_source_fixture_constraints(design, @view direct_draws[draw, :])
    end
    return direct_draws
end

function _gmfrm_category_probabilities!(probs::AbstractVector{Float64},
        design::FacetDesign,
        direct_params::AbstractVector,
        row::Int)
    _gmfrm_source_linear_predictors!(probs, design, direct_params, row)
    return _softmax_eta!(probs)
end

function _mgmfrm_category_probabilities!(probs::AbstractVector{Float64},
        design::FacetDesign,
        index_by_name,
        direct_params::AbstractVector,
        row::Int)
    _mgmfrm_source_linear_predictors!(probs, design, index_by_name, direct_params, row)
    return _softmax_eta!(probs)
end

function _gmfrm_predictive_probabilities_direct(
        design::FacetDesign,
        direct_draws::AbstractMatrix)
    checked = _gmfrm_direct_draws_for_prediction(
        design,
        direct_draws,
        "predictive_probabilities",
    )
    data = design.spec.data
    K = length(data.category_levels)
    out = Array{Float64}(undef, size(checked, 1), data.n, K)
    probs = zeros(Float64, K)

    for draw in axes(checked, 1)
        direct_params = @view checked[draw, :]
        for row in 1:data.n
            _gmfrm_category_probabilities!(probs, design, direct_params, row)
            for category in 1:K
                out[draw, row, category] = probs[category]
            end
        end
    end
    return out
end

function _mgmfrm_predictive_probabilities_direct(
        design::FacetDesign,
        direct_draws::AbstractMatrix)
    checked = _mgmfrm_direct_draws_for_prediction(
        design,
        direct_draws,
        "predictive_probabilities",
    )
    data = design.spec.data
    K = length(data.category_levels)
    out = Array{Float64}(undef, size(checked, 1), data.n, K)
    probs = zeros(Float64, K)
    index_by_name = _parameter_index_map(design)

    for draw in axes(checked, 1)
        direct_params = @view checked[draw, :]
        for row in 1:data.n
            _mgmfrm_category_probabilities!(probs, design, index_by_name, direct_params, row)
            for category in 1:K
                out[draw, row, category] = probs[category]
            end
        end
    end
    return out
end

"""
    predictive_probabilities(fit::MFRMFit; ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())
    predictive_probabilities(design::FacetDesign, draws)

Return observation-level category probabilities for posterior or supplied
parameter draws. The returned array has dimensions draws-by-observations-by-
categories, with categories ordered as `fit.design.spec.data.category_levels`.
"""
function predictive_probabilities(design::FacetDesign, draws::AbstractMatrix)
    _check_fit_supported_mfrm(design, "predictive_probabilities")
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    data = design.spec.data
    K = length(data.category_levels)
    out = Array{Float64}(undef, size(draws, 1), data.n, K)
    probs = zeros(Float64, K)

    for draw in axes(draws, 1)
        params = @view draws[draw, :]
        for row in 1:data.n
            _category_probabilities!(probs, design, params, row)
            for category in 1:K
                out[draw, row, category] = probs[category]
            end
        end
    end
    return out
end

function predictive_probabilities(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return predictive_probabilities(fit.design, fit.draws[indices, :])
end

function predictive_probabilities(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _gmfrm_predictive_probabilities_direct(
        fit.design,
        fit.direct_draws[indices, :],
    )
end

function predictive_probabilities(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _mgmfrm_predictive_probabilities_direct(
        fit.design,
        fit.direct_draws[indices, :],
    )
end

function _expected_scores_from_probabilities(probabilities::AbstractArray{<:Real,3},
        levels::AbstractVector{<:Real})
    size(probabilities, 3) == length(levels) ||
        throw(ArgumentError("probabilities has $(size(probabilities, 3)) category column(s); expected $(length(levels))"))
    expected = zeros(Float64, size(probabilities, 1), size(probabilities, 2))
    for category in eachindex(levels)
        expected .+= Float64(levels[category]) .* @view probabilities[:, :, category]
    end
    return expected
end

"""
    expected_scores(fit::MFRMFit; ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    expected_scores(design::FacetDesign, draws)

Return observation-level expected scores for each posterior or supplied
parameter draw. The returned matrix has dimensions draws-by-observations.
"""
function expected_scores(design::FacetDesign, draws::AbstractMatrix)
    probabilities = predictive_probabilities(design, draws)
    return _expected_scores_from_probabilities(probabilities, design.spec.data.category_levels)
end

function expected_scores(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    return _expected_scores_from_probabilities(probabilities, fit.design.spec.data.category_levels)
end

function expected_scores(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    return _expected_scores_from_probabilities(probabilities, fit.design.spec.data.category_levels)
end

function expected_scores(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    return _expected_scores_from_probabilities(probabilities, fit.design.spec.data.category_levels)
end

function _fair_average_groups(data::FacetData, by::Symbol)
    by === :person && return data.person, data.person_levels
    by === :rater && return data.rater, data.rater_levels
    by === :item && return data.item, data.item_levels
    throw(ArgumentError("fair_average_summary currently supports by = :person, :rater, or :item"))
end

function _fair_average_reference_rows(data::FacetData, by::Symbol, level_index::Int)
    rows = NTuple{3,Int}[]
    if by === :person
        for rater in eachindex(data.rater_levels), item in eachindex(data.item_levels)
            push!(rows, (level_index, rater, item))
        end
    elseif by === :rater
        for person in eachindex(data.person_levels), item in eachindex(data.item_levels)
            push!(rows, (person, level_index, item))
        end
    elseif by === :item
        for person in eachindex(data.person_levels), rater in eachindex(data.rater_levels)
            push!(rows, (person, rater, level_index))
        end
    else
        throw(ArgumentError("fair_average_summary currently supports by = :person, :rater, or :item"))
    end
    return rows
end

function _hypothetical_mfrm_category_probabilities!(
        probs::AbstractVector{Float64},
        design::FacetDesign,
        params::AbstractVector,
        person::Int,
        rater::Int,
        item::Int)
    length(probs) == length(design.spec.data.category_levels) ||
        throw(ArgumentError("probability work vector has the wrong length"))
    person_value = params[design.blocks[:person][person]]
    rater_value = _reference_value(params, design.blocks[:rater], rater)
    item_value = _reference_value(params, design.blocks[:item], item)
    location = person_value - rater_value - item_value
    step_sum = _param_zero(params)
    for category_index in eachindex(probs)
        if category_index > 1
            step_sum += _threshold_step(design, params, item, category_index - 1)
        end
        probs[category_index] = Float64((category_index - 1) * location - step_sum)
    end
    return _softmax_eta!(probs)
end

function _hypothetical_mfrm_expected_score(
        design::FacetDesign,
        params::AbstractVector,
        person::Int,
        rater::Int,
        item::Int,
        probs::AbstractVector{Float64})
    _hypothetical_mfrm_category_probabilities!(probs, design, params, person, rater, item)
    expected = 0.0
    for category_index in eachindex(probs)
        expected += Float64(design.spec.data.category_levels[category_index]) *
            probs[category_index]
    end
    return expected
end

function _fair_average_by_draw(
        design::FacetDesign,
        draws::AbstractMatrix,
        reference_rows::AbstractVector{<:Tuple{Int,Int,Int}})
    !isempty(reference_rows) ||
        throw(ArgumentError("fair_average_summary reference grid is empty"))
    out = Vector{Float64}(undef, size(draws, 1))
    probs = zeros(Float64, length(design.spec.data.category_levels))
    for draw in axes(draws, 1)
        params = @view draws[draw, :]
        total = 0.0
        for (person, rater, item) in reference_rows
            total += _hypothetical_mfrm_expected_score(
                design,
                params,
                person,
                rater,
                item,
                probs,
            )
        end
        out[draw] = total / length(reference_rows)
    end
    return out
end

"""
    fair_average_summary(fit::MFRMFit; by = :person, interval = 0.95,
        min_n = 1, ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    fair_average_summary(design::FacetDesign, draws; by = :person,
        interval = 0.95, min_n = 1)

Return posterior fair-average expected-score summaries for a focal MFRM facet.
Rows use an equal-weight balanced reference grid over the non-focal core
facets, so `by = :person` averages each person over all observed raters and
items, `by = :rater` averages each rater over all persons and items, and
`by = :item` averages each item over all persons and raters. Rows include the
observed mean score for the focal level, fair-average and expected-score
intervals, the fair-minus-observed adjustment, and a caveat that the balanced
grid is a reporting standardization rather than a population-weighted target.
"""
function fair_average_summary(design::FacetDesign,
        draws::AbstractMatrix;
        by::Symbol = :person,
        interval::Real = 0.95,
        min_n::Int = 1)
    _check_fit_supported_mfrm(design, "fair_average_summary")
    min_n >= 1 || throw(ArgumentError("min_n must be positive"))
    size(draws, 1) >= 1 ||
        throw(ArgumentError("fair_average_summary requires at least one posterior draw"))
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    all(value -> isfinite(Float64(value)), draws) ||
        throw(ArgumentError("draws contain non-finite values"))

    lower_probability, upper_probability = _interval_probabilities(interval)
    data = design.spec.data
    group_index, group_levels = _fair_average_groups(data, by)
    rows = NamedTuple[]
    for (level_index, level) in pairs(group_levels)
        observations = findall(==(level_index), group_index)
        observed_mean = _mean_at_indices(data.score, observations)
        reference_rows = _fair_average_reference_rows(data, by, level_index)
        fair_by_draw = _fair_average_by_draw(design, draws, reference_rows)
        adjustment_by_draw = fair_by_draw .- observed_mean
        fair_summary = _finite_draw_summary(
            fair_by_draw,
            lower_probability,
            upper_probability,
        )
        adjustment_summary = _finite_draw_summary(
            adjustment_by_draw,
            lower_probability,
            upper_probability,
        )
        n_observations = length(observations)
        push!(rows, (;
            facet = by,
            level,
            n_observations,
            n_reference_rows = length(reference_rows),
            n_draws = size(draws, 1),
            method = :posterior_expected_score,
            reference = :balanced_facet_grid,
            interval_probability = Float64(interval),
            lower_probability,
            upper_probability,
            observed_mean,
            fair_average_mean = fair_summary.mean,
            fair_average_median = fair_summary.median,
            fair_average_lower = fair_summary.lower,
            fair_average_upper = fair_summary.upper,
            expected_score_mean = fair_summary.mean,
            expected_score_median = fair_summary.median,
            expected_score_lower = fair_summary.lower,
            expected_score_upper = fair_summary.upper,
            adjustment_mean = adjustment_summary.mean,
            adjustment_median = adjustment_summary.median,
            adjustment_lower = adjustment_summary.lower,
            adjustment_upper = adjustment_summary.upper,
            caveat = :balanced_reference_grid_not_population_standardization,
            flag = n_observations < min_n ? :below_min_n : :ok,
        ))
    end
    return rows
end

function fair_average_summary(fit::MFRMFit;
        by::Symbol = :person,
        interval::Real = 0.95,
        min_n::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return fair_average_summary(fit.design, fit.draws[indices, :];
        by,
        interval,
        min_n)
end

function _separation_reliability_facets(facets::Symbol)
    facets === :all && return (:person, :rater, :item)
    return _separation_reliability_facets((facets,))
end

function _separation_reliability_facets(facets)
    out = Symbol[]
    for facet in facets
        facet isa Symbol ||
            throw(ArgumentError("facets must contain symbols"))
        facet in (:person, :rater, :item) ||
            throw(ArgumentError("separation_reliability_summary supports facets :person, :rater, and :item"))
        facet in out &&
            throw(ArgumentError("facets must not contain duplicates"))
        push!(out, facet)
    end
    isempty(out) &&
        throw(ArgumentError("facets must contain at least one facet"))
    return Tuple(out)
end

function _separation_reliability_levels(data::FacetData, facet::Symbol)
    facet === :person && return data.person_levels
    facet === :rater && return data.rater_levels
    facet === :item && return data.item_levels
    throw(ArgumentError("separation_reliability_summary supports facets :person, :rater, and :item"))
end

function _mfrm_facet_value(design::FacetDesign,
        params::AbstractVector,
        facet::Symbol,
        level_index::Int)
    if facet === :person
        return Float64(params[design.blocks[:person][level_index]])
    elseif facet === :rater
        return Float64(_reference_value(params, design.blocks[:rater], level_index))
    elseif facet === :item
        return Float64(_reference_value(params, design.blocks[:item], level_index))
    end
    throw(ArgumentError("separation_reliability_summary supports facets :person, :rater, and :item"))
end

function _mfrm_facet_value_matrix(design::FacetDesign,
        draws::AbstractMatrix,
        facet::Symbol)
    levels = _separation_reliability_levels(design.spec.data, facet)
    values = Matrix{Float64}(undef, size(draws, 1), length(levels))
    for draw in axes(draws, 1)
        params = @view draws[draw, :]
        for level_index in eachindex(levels)
            values[draw, level_index] =
                _mfrm_facet_value(design, params, facet, level_index)
        end
    end
    return values
end

function _sample_variance_or_nan(values::AbstractVector{<:Real})
    length(values) >= 2 || return NaN
    mean_value = _column_mean(values)
    ss = 0.0
    for value in values
        d = Float64(value) - mean_value
        ss += d * d
    end
    return ss / (length(values) - 1)
end

function _mean_level_posterior_variance(values::AbstractMatrix{Float64})
    size(values, 1) >= 2 ||
        throw(ArgumentError("separation_reliability_summary requires at least two posterior draws"))
    size(values, 2) >= 1 ||
        throw(ArgumentError("separation_reliability_summary requires at least one level"))
    total = 0.0
    for level in axes(values, 2)
        total += _sample_variance_or_nan(@view values[:, level])
    end
    return total / size(values, 2)
end

function _separation_reliability_row(
        design::FacetDesign,
        draws::AbstractMatrix,
        facet::Symbol,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64)
    values = _mfrm_facet_value_matrix(design, draws, facet)
    n_draws, n_levels = size(values)
    observed_variance = Vector{Float64}(undef, n_draws)
    observed_sd = Vector{Float64}(undef, n_draws)
    adjusted_variance = Vector{Float64}(undef, n_draws)
    adjusted_sd = Vector{Float64}(undef, n_draws)
    separation = Vector{Float64}(undef, n_draws)
    reliability = Vector{Float64}(undef, n_draws)

    posterior_error_variance =
        n_levels < 2 ? NaN : _mean_level_posterior_variance(values)
    error_variance = fill(posterior_error_variance, n_draws)
    eps_var = eps(Float64)
    for draw in axes(values, 1)
        level_values = @view values[draw, :]
        raw_variance = _sample_variance_or_nan(level_values)
        observed_variance[draw] = raw_variance
        observed_sd[draw] = isfinite(raw_variance) ? sqrt(max(raw_variance, 0.0)) : NaN
        adjusted = isfinite(raw_variance) && isfinite(posterior_error_variance) ?
            max(raw_variance - posterior_error_variance, 0.0) : NaN
        adjusted_variance[draw] = adjusted
        adjusted_sd[draw] = isfinite(adjusted) ? sqrt(adjusted) : NaN
        if isfinite(adjusted) && posterior_error_variance > eps_var
            separation[draw] = sqrt(adjusted / posterior_error_variance)
            reliability[draw] = adjusted / (adjusted + posterior_error_variance)
        else
            separation[draw] = NaN
            reliability[draw] = NaN
        end
    end

    observed_variance_summary =
        _finite_draw_summary(observed_variance, lower_probability, upper_probability)
    observed_sd_summary =
        _finite_draw_summary(observed_sd, lower_probability, upper_probability)
    error_variance_summary =
        _finite_draw_summary(error_variance, lower_probability, upper_probability)
    adjusted_variance_summary =
        _finite_draw_summary(adjusted_variance, lower_probability, upper_probability)
    adjusted_sd_summary =
        _finite_draw_summary(adjusted_sd, lower_probability, upper_probability)
    separation_summary =
        _finite_draw_summary(separation, lower_probability, upper_probability)
    reliability_summary =
        _finite_draw_summary(reliability, lower_probability, upper_probability)

    flag = n_levels < 2 ? :single_level :
        !(posterior_error_variance > eps_var) ? :zero_posterior_error_variance :
        all(value -> isfinite(value) && value == 0.0, adjusted_variance) ?
        :no_adjusted_separation : :ok

    return (;
        facet,
        n_levels,
        n_draws,
        method = :posterior_empirical_reliability,
        scale = :logit,
        interval_probability = Float64(interval),
        lower_probability,
        upper_probability,
        observed_variance_mean = observed_variance_summary.mean,
        observed_variance_median = observed_variance_summary.median,
        observed_variance_lower = observed_variance_summary.lower,
        observed_variance_upper = observed_variance_summary.upper,
        observed_sd_mean = observed_sd_summary.mean,
        observed_sd_median = observed_sd_summary.median,
        observed_sd_lower = observed_sd_summary.lower,
        observed_sd_upper = observed_sd_summary.upper,
        error_variance_mean = error_variance_summary.mean,
        error_variance_median = error_variance_summary.median,
        error_variance_lower = error_variance_summary.lower,
        error_variance_upper = error_variance_summary.upper,
        adjusted_variance_mean = adjusted_variance_summary.mean,
        adjusted_variance_median = adjusted_variance_summary.median,
        adjusted_variance_lower = adjusted_variance_summary.lower,
        adjusted_variance_upper = adjusted_variance_summary.upper,
        adjusted_sd_mean = adjusted_sd_summary.mean,
        adjusted_sd_median = adjusted_sd_summary.median,
        adjusted_sd_lower = adjusted_sd_summary.lower,
        adjusted_sd_upper = adjusted_sd_summary.upper,
        separation_mean = separation_summary.mean,
        separation_median = separation_summary.median,
        separation_lower = separation_summary.lower,
        separation_upper = separation_summary.upper,
        reliability_mean = reliability_summary.mean,
        reliability_median = reliability_summary.median,
        reliability_lower = reliability_summary.lower,
        reliability_upper = reliability_summary.upper,
        caveat = :posterior_empirical_reliability_screening_not_generalizability_coefficient,
        flag,
    )
end

"""
    separation_reliability_summary(fit::MFRMFit; facets = (:person, :rater, :item),
        interval = 0.95, ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    separation_reliability_summary(design::FacetDesign, draws;
        facets = (:person, :rater, :item), interval = 0.95)

Return posterior separation and empirical reliability summaries for MFRM
person, rater, and item measures. For each requested facet, rows summarize the
posterior distribution of level dispersion, mean posterior error variance,
error-adjusted dispersion, separation, and reliability. Reliability is computed
as adjusted variance divided by adjusted-plus-error variance; use the included
caveat flag because these rows are practical screening summaries rather than
full generalizability-study coefficients.
"""
function separation_reliability_summary(design::FacetDesign,
        draws::AbstractMatrix;
        facets = (:person, :rater, :item),
        interval::Real = 0.95)
    _check_fit_supported_mfrm(design, "separation_reliability_summary")
    size(draws, 1) >= 2 ||
        throw(ArgumentError("separation_reliability_summary requires at least two posterior draws"))
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    all(value -> isfinite(Float64(value)), draws) ||
        throw(ArgumentError("draws contain non-finite values"))
    lower_probability, upper_probability = _interval_probabilities(interval)
    requested_facets = _separation_reliability_facets(facets)
    return [
        _separation_reliability_row(
            design,
            draws,
            facet,
            interval,
            lower_probability,
            upper_probability,
        )
        for facet in requested_facets
    ]
end

function separation_reliability_summary(fit::MFRMFit;
        facets = (:person, :rater, :item),
        interval::Real = 0.95,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return separation_reliability_summary(fit.design, fit.draws[indices, :];
        facets,
        interval)
end

function _wright_map_facets(facets::Symbol)
    facets === :all && return (:person, :rater, :item)
    return _wright_map_facets((facets,))
end

function _wright_map_facets(facets)
    out = Symbol[]
    for facet in facets
        facet isa Symbol ||
            throw(ArgumentError("facets must contain symbols"))
        facet in (:person, :rater, :item) ||
            throw(ArgumentError("wright_map_data supports facets :person, :rater, and :item"))
        facet in out &&
            throw(ArgumentError("facets must not contain duplicates"))
        push!(out, facet)
    end
    isempty(out) &&
        throw(ArgumentError("facets must contain at least one facet"))
    return Tuple(out)
end

function _wright_map_facet_index(data::FacetData, facet::Symbol)
    facet === :person && return data.person, data.person_levels
    facet === :rater && return data.rater, data.rater_levels
    facet === :item && return data.item, data.item_levels
    throw(ArgumentError("wright_map_data supports facets :person, :rater, and :item"))
end

function _wright_map_check_draws(design::FacetDesign, draws::AbstractMatrix)
    _check_fit_supported_mfrm(design, "wright_map_data")
    size(draws, 1) >= 1 ||
        throw(ArgumentError("wright_map_data requires at least one posterior draw"))
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    all(value -> isfinite(Float64(value)), draws) ||
        throw(ArgumentError("draws contain non-finite values"))
    return draws
end

function _wright_map_facet_parameter(design::FacetDesign,
        facet::Symbol,
        level_index::Int)
    if facet === :person
        parameter_index = design.blocks[:person][level_index]
        return (;
            parameter_index,
            parameter_name = design.parameter_names[parameter_index],
            status = :estimated,
        )
    elseif facet === :rater
        level_index == 1 && return (;
            parameter_index = missing,
            parameter_name = missing,
            status = :reference_zero,
        )
        parameter_index = design.blocks[:rater][level_index - 1]
        return (;
            parameter_index,
            parameter_name = design.parameter_names[parameter_index],
            status = :estimated,
        )
    elseif facet === :item
        level_index == 1 && return (;
            parameter_index = missing,
            parameter_name = missing,
            status = :reference_zero,
        )
        parameter_index = design.blocks[:item][level_index - 1]
        return (;
            parameter_index,
            parameter_name = design.parameter_names[parameter_index],
            status = :estimated,
        )
    end
    throw(ArgumentError("wright_map_data supports facets :person, :rater, and :item"))
end

function _wright_map_facet_values(design::FacetDesign,
        draws::AbstractMatrix,
        facet::Symbol,
        level_index::Int)
    values = Vector{Float64}(undef, size(draws, 1))
    for draw in axes(draws, 1)
        values[draw] = _mfrm_facet_value(
            design,
            @view(draws[draw, :]),
            facet,
            level_index,
        )
    end
    return values
end

function _wright_map_threshold_values(design::FacetDesign,
        draws::AbstractMatrix,
        item_index::Int,
        step::Int)
    item_values = Vector{Float64}(undef, size(draws, 1))
    step_values = Vector{Float64}(undef, size(draws, 1))
    positions = Vector{Float64}(undef, size(draws, 1))
    for draw in axes(draws, 1)
        params = @view draws[draw, :]
        item_value = _mfrm_facet_value(design, params, :item, item_index)
        step_value = Float64(_threshold_step(design, params, item_index, step))
        item_values[draw] = item_value
        step_values[draw] = step_value
        positions[draw] = item_value + step_value
    end
    return item_values, step_values, positions
end

function _wright_map_facet_row(design::FacetDesign,
        draws::AbstractMatrix,
        facet::Symbol,
        level,
        level_index::Int,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64)
    data = design.spec.data
    facet_index, _ = _wright_map_facet_index(data, facet)
    n_observations = count(==(level_index), facet_index)
    parameter = _wright_map_facet_parameter(design, facet, level_index)
    values = _wright_map_facet_values(design, draws, facet, level_index)
    position_summary = _finite_draw_summary(values, lower_probability, upper_probability)

    return (;
        component = :facet_measure,
        facet,
        level,
        level_index,
        item = missing,
        item_index = missing,
        step = missing,
        from_category = missing,
        to_category = missing,
        thresholds = design.spec.thresholds,
        parameter.parameter_index,
        parameter.parameter_name,
        item_parameter_index = missing,
        item_parameter_name = missing,
        threshold_parameter_index = missing,
        threshold_parameter_name = missing,
        status = parameter.status,
        n_observations,
        n_draws = size(draws, 1),
        scale = :logit,
        position_mean = position_summary.mean,
        position_median = position_summary.median,
        position_lower = position_summary.lower,
        position_upper = position_summary.upper,
        item_measure_mean = missing,
        item_measure_median = missing,
        item_measure_lower = missing,
        item_measure_upper = missing,
        threshold_step_mean = missing,
        threshold_step_median = missing,
        threshold_step_lower = missing,
        threshold_step_upper = missing,
        interval_probability = Float64(interval),
        lower_probability,
        upper_probability,
        label = string(facet, "=", level),
        caveat = :wright_map_data_not_backend_rendering,
        flag = n_observations == 0 ? :empty_level : :ok,
    )
end

function _wright_map_threshold_row(design::FacetDesign,
        draws::AbstractMatrix,
        item,
        item_index::Int,
        step::Int,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64)
    metadata = _threshold_step_metadata(design, item_index, step)
    item_parameter = _wright_map_facet_parameter(design, :item, item_index)
    item_values, step_values, positions =
        _wright_map_threshold_values(design, draws, item_index, step)
    item_summary = _finite_draw_summary(item_values, lower_probability, upper_probability)
    step_summary = _finite_draw_summary(step_values, lower_probability, upper_probability)
    position_summary = _finite_draw_summary(positions, lower_probability, upper_probability)

    return (;
        component = :threshold,
        facet = :threshold,
        level = missing,
        level_index = missing,
        item,
        item_index,
        step = metadata.step,
        from_category = metadata.from_category,
        to_category = metadata.to_category,
        thresholds = design.spec.thresholds,
        parameter_index = metadata.parameter_index,
        parameter_name = metadata.parameter_name,
        item_parameter_index = item_parameter.parameter_index,
        item_parameter_name = item_parameter.parameter_name,
        threshold_parameter_index = metadata.parameter_index,
        threshold_parameter_name = metadata.parameter_name,
        status = metadata.status,
        n_observations = missing,
        n_draws = size(draws, 1),
        scale = :logit,
        position_mean = position_summary.mean,
        position_median = position_summary.median,
        position_lower = position_summary.lower,
        position_upper = position_summary.upper,
        item_measure_mean = item_summary.mean,
        item_measure_median = item_summary.median,
        item_measure_lower = item_summary.lower,
        item_measure_upper = item_summary.upper,
        threshold_step_mean = step_summary.mean,
        threshold_step_median = step_summary.median,
        threshold_step_lower = step_summary.lower,
        threshold_step_upper = step_summary.upper,
        interval_probability = Float64(interval),
        lower_probability,
        upper_probability,
        label = string("item=", item, ", step=", metadata.step),
        caveat = :wright_map_data_not_backend_rendering,
        flag = :ok,
    )
end

function _wright_map_threshold_rows(design::FacetDesign,
        draws::AbstractMatrix,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64)
    data = design.spec.data
    nsteps = max(length(data.category_levels) - 1, 0)
    rows = NamedTuple[]
    for (item_index, item) in pairs(data.item_levels), step in 1:nsteps
        push!(rows, _wright_map_threshold_row(
            design,
            draws,
            item,
            item_index,
            step,
            interval,
            lower_probability,
            upper_probability,
        ))
    end
    return rows
end

"""
    wright_map_data(fit::MFRMFit; facets = :all, include_thresholds = true,
        interval = 0.95, ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    wright_map_data(design::FacetDesign, draws; facets = :all,
        include_thresholds = true, interval = 0.95)

Return plotting-backend-independent Wright-map rows for the current
fit-supported MFRM/RSM/PCM design. Facet rows summarize posterior person,
rater, and item measures on the logit scale. Threshold rows summarize item-step
positions as `item measure + threshold step`, which puts category boundaries on
the same latent scale as person measures. The returned rows are intended for
Quarto, Makie, AlgebraOfGraphics, ggplot, or CSV workflows and do not commit
the package to a specific plotting backend.
"""
function wright_map_data(design::FacetDesign,
        draws::AbstractMatrix;
        facets = :all,
        include_thresholds::Bool = true,
        interval::Real = 0.95)
    _wright_map_check_draws(design, draws)
    lower_probability, upper_probability = _interval_probabilities(interval)
    requested_facets = _wright_map_facets(facets)
    data = design.spec.data
    rows = NamedTuple[]
    for facet in requested_facets
        _, levels = _wright_map_facet_index(data, facet)
        for (level_index, level) in pairs(levels)
            push!(rows, _wright_map_facet_row(
                design,
                draws,
                facet,
                level,
                level_index,
                interval,
                lower_probability,
                upper_probability,
            ))
        end
    end
    if include_thresholds
        append!(rows, _wright_map_threshold_rows(
            design,
            draws,
            interval,
            lower_probability,
            upper_probability,
        ))
    end
    return rows
end

function wright_map_data(fit::MFRMFit;
        facets = :all,
        include_thresholds::Bool = true,
        interval::Real = 0.95,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return wright_map_data(fit.design, fit.draws[indices, :];
        facets,
        include_thresholds,
        interval)
end

function _predictive_variances_from_probabilities(probabilities::AbstractArray{<:Real,3},
        levels::AbstractVector{<:Real})
    expected = _expected_scores_from_probabilities(probabilities, levels)
    second = zeros(Float64, size(probabilities, 1), size(probabilities, 2))
    for category in eachindex(levels)
        score = Float64(levels[category])
        second .+= (score * score) .* @view probabilities[:, :, category]
    end
    variances = second .- expected .* expected
    return max.(variances, 0.0)
end

"""
    predictive_variances(fit::MFRMFit; ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())
    predictive_variances(design::FacetDesign, draws)

Return observation-level conditional predictive score variances for each
posterior or supplied parameter draw. The returned matrix has dimensions
draws-by-observations.
"""
function predictive_variances(design::FacetDesign, draws::AbstractMatrix)
    probabilities = predictive_probabilities(design, draws)
    return _predictive_variances_from_probabilities(probabilities, design.spec.data.category_levels)
end

function predictive_variances(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    return _predictive_variances_from_probabilities(probabilities, fit.design.spec.data.category_levels)
end

function predictive_variances(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    return _predictive_variances_from_probabilities(probabilities, fit.design.spec.data.category_levels)
end

function predictive_variances(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    return _predictive_variances_from_probabilities(probabilities, fit.design.spec.data.category_levels)
end

"""
    predictive_residuals(fit::MFRMFit; ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())
    predictive_residuals(design::FacetDesign, draws)

Return observation-level observed-minus-expected score residuals for each
posterior or supplied parameter draw. The returned matrix has dimensions
draws-by-observations.
"""
function predictive_residuals(design::FacetDesign, draws::AbstractMatrix)
    expected = expected_scores(design, draws)
    data = design.spec.data
    residuals = similar(expected)
    for draw in axes(expected, 1), row in axes(expected, 2)
        residuals[draw, row] = data.score[row] - expected[draw, row]
    end
    return residuals
end

function predictive_residuals(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return predictive_residuals(fit.design, fit.draws[indices, :])
end

function predictive_residuals(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    expected = expected_scores(fit; ndraws, draw_indices, rng)
    data = fit.design.spec.data
    residuals = similar(expected)
    for draw in axes(expected, 1), row in axes(expected, 2)
        residuals[draw, row] = data.score[row] - expected[draw, row]
    end
    return residuals
end

function predictive_residuals(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    expected = expected_scores(fit; ndraws, draw_indices, rng)
    data = fit.design.spec.data
    residuals = similar(expected)
    for draw in axes(expected, 1), row in axes(expected, 2)
        residuals[draw, row] = data.score[row] - expected[draw, row]
    end
    return residuals
end

function _fit_stat_groups(data::FacetData, by::Symbol)
    by === :person && return data.person, data.person_levels
    by === :rater && return data.rater, data.rater_levels
    by === :item && return data.item, data.item_levels
    by === :category && return data.category, data.category_levels
    if haskey(data.optional, by)
        return data.optional[by], data.optional_levels[by]
    end
    throw(ArgumentError("by = :$by is not a facet in this design"))
end

function _interval_probabilities(interval::Real)
    0 < interval < 1 || throw(ArgumentError("interval must be in (0, 1)"))
    lower = (1 - Float64(interval)) / 2
    return lower, 1 - lower
end

function _finite_draw_summary(values::AbstractVector{<:Real}, lower::Float64, upper::Float64)
    finite = [Float64(value) for value in values if isfinite(value)]
    if isempty(finite)
        return (mean = NaN, median = NaN, lower = NaN, upper = NaN)
    end
    sorted = sort(finite)
    return (;
        mean = _column_mean(finite),
        median = _quantile_sorted(sorted, 0.5),
        lower = _quantile_sorted(sorted, lower),
        upper = _quantile_sorted(sorted, upper),
    )
end

function _expected_score_calibration_target(data::FacetData,
        probabilities::AbstractArray{<:Real,3})
    return (;
        target = :expected_score,
        category = missing,
        predicted = _expected_scores_from_probabilities(
            probabilities,
            data.category_levels,
        ),
        observed = Float64.(data.score),
    )
end

function _category_probability_calibration_target(data::FacetData,
        probabilities::AbstractArray{<:Real,3},
        category)
    category_index = findfirst(==(category), data.category_levels)
    category_index === nothing &&
        throw(ArgumentError("category $category is not an observed score category"))
    level = data.category_levels[category_index]
    return (;
        target = :category_probability,
        category = level,
        predicted = @view(probabilities[:, :, category_index]),
        observed = [score == level ? 1.0 : 0.0 for score in data.score],
    )
end

function _calibration_targets_from_probabilities(data::FacetData,
        probabilities::AbstractArray{<:Real,3},
        target::Symbol,
        category)
    size(probabilities, 1) >= 1 ||
        throw(ArgumentError("calibration_table requires at least one posterior draw"))
    size(probabilities, 2) == data.n ||
        throw(ArgumentError("probabilities observation count does not match data"))
    size(probabilities, 3) == length(data.category_levels) ||
        throw(ArgumentError("probabilities category count does not match data"))

    if target === :expected_score
        category === nothing ||
            throw(ArgumentError("category is only supported with target = :category_probability"))
        return [_expected_score_calibration_target(data, probabilities)]
    elseif target === :category_probability
        if category === :all
            return [
                _category_probability_calibration_target(data, probabilities, level)
                for level in data.category_levels
            ]
        end
        chosen_category = category === nothing ? last(data.category_levels) : category
        return [_category_probability_calibration_target(data, probabilities, chosen_category)]
    elseif target === :all
        (category === nothing || category === :all) ||
            throw(ArgumentError("category is not supported with target = :all except category = :all"))
        targets = NamedTuple[_expected_score_calibration_target(data, probabilities)]
        append!(targets, [
            _category_probability_calibration_target(data, probabilities, level)
            for level in data.category_levels
        ])
        return targets
    end

    throw(ArgumentError("target must be :expected_score, :category_probability, or :all"))
end

function _calibration_targets(design::FacetDesign,
        draws::AbstractMatrix,
        target::Symbol,
        category)
    probabilities = predictive_probabilities(design, draws)
    return _calibration_targets_from_probabilities(
        design.spec.data,
        probabilities,
        target,
        category,
    )
end

function _calibration_column_means(predicted::AbstractMatrix{<:Real})
    means = Vector{Float64}(undef, size(predicted, 2))
    for row in axes(predicted, 2)
        means[row] = _column_mean(@view predicted[:, row])
    end
    all(isfinite, means) ||
        throw(ArgumentError("predicted calibration values contain non-finite entries"))
    return means
end

function _calibration_bin_assignments(predicted_mean::AbstractVector{<:Real}, bins::Int)
    bins >= 1 || throw(ArgumentError("bins must be positive"))
    n = length(predicted_mean)
    n >= 1 || throw(ArgumentError("calibration_table requires at least one observation"))
    nbins = min(bins, n)
    order = sortperm(predicted_mean; alg = MergeSort)
    assignments = Vector{Int}(undef, n)
    for (rank, row) in pairs(order)
        assignments[row] = min(nbins, fld((rank - 1) * nbins, n) + 1)
    end
    return assignments, nbins
end

function _mean_at_indices(values::AbstractVector{<:Real}, indices::AbstractVector{Int})
    isempty(indices) && return NaN
    return sum(Float64(values[index]) for index in indices) / length(indices)
end

"""
    calibration_table(fit::MFRMFit; target = :expected_score,
        category = nothing, bins = 10, interval = 0.9, ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())
    calibration_table(design::FacetDesign, draws; target = :expected_score,
        category = nothing, bins = 10, interval = 0.9)

Return binned observed-vs-predicted calibration rows from posterior draws.
The default `target = :expected_score` compares observed scores with posterior
expected scores. With `target = :category_probability`, the table compares the
observed proportion of `category` with the posterior probability of that
category; when `category` is omitted, the highest score category is used. Use
`category = :all` to return one category-probability calibration block for each
ordinal score category. Use `target = :all` to return expected-score rows plus
all ordinal category-probability rows.
"""
function calibration_table(design::FacetDesign,
        draws::AbstractMatrix;
        target::Symbol = :expected_score,
        category = nothing,
        bins::Int = 10,
        interval::Real = 0.9)
    lower_probability, upper_probability = _interval_probabilities(interval)
    calibration_targets = _calibration_targets(design, draws, target, category)
    return _calibration_table_from_targets(
        calibration_targets;
        bins,
        interval,
        lower_probability,
        upper_probability,
    )
end

function _calibration_table_from_targets(
        calibration_targets;
        bins::Int,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64)
    rows = NamedTuple[]
    for calibration_target in calibration_targets
        append!(rows, _calibration_table_from_target(
            calibration_target;
            bins,
            interval,
            lower_probability,
            upper_probability,
        ))
    end
    return rows
end

function _calibration_table_from_target(
        calibration_target;
        bins::Int,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64)
    predicted = calibration_target.predicted
    observed = calibration_target.observed
    predicted_mean = _calibration_column_means(predicted)
    assignments, nbins = _calibration_bin_assignments(predicted_mean, bins)
    rows = NamedTuple[]

    for bin in 1:nbins
        obs = findall(==(bin), assignments)
        predicted_by_draw = Vector{Float64}(undef, size(predicted, 1))
        for draw in axes(predicted, 1)
            predicted_by_draw[draw] = _mean_at_indices(@view(predicted[draw, :]), obs)
        end
        predicted_summary = _finite_draw_summary(predicted_by_draw,
            lower_probability, upper_probability)
        observed_mean = _mean_at_indices(observed, obs)
        bin_predicted_means = predicted_mean[obs]
        outside = isfinite(observed_mean) &&
            (observed_mean < predicted_summary.lower || observed_mean > predicted_summary.upper)
        calibration_error = observed_mean - predicted_summary.mean
        push!(rows, (;
            target = calibration_target.target,
            category = calibration_target.category,
            bin,
            n_observations = length(obs),
            n_draws = size(predicted, 1),
            predicted_bin_lower = minimum(bin_predicted_means),
            predicted_bin_upper = maximum(bin_predicted_means),
            observed_mean,
            predicted_mean = predicted_summary.mean,
            predicted_median = predicted_summary.median,
            predicted_lower = predicted_summary.lower,
            predicted_upper = predicted_summary.upper,
            interval_probability = Float64(interval),
            lower_probability,
            upper_probability,
            calibration_error,
            absolute_calibration_error = abs(calibration_error),
            flag = outside ? :outside_interval : :ok,
        ))
    end

    return rows
end

function calibration_table(fit::MFRMFit;
        target::Symbol = :expected_score,
        category = nothing,
        bins::Int = 10,
        interval::Real = 0.9,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return calibration_table(fit.design, fit.draws[indices, :];
        target, category, bins, interval)
end

function calibration_table(fit::GMFRMFit;
        target::Symbol = :expected_score,
        category = nothing,
        bins::Int = 10,
        interval::Real = 0.9,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    lower_probability, upper_probability = _interval_probabilities(interval)
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    calibration_targets = _calibration_targets_from_probabilities(
        fit.design.spec.data,
        probabilities,
        target,
        category,
    )
    return _calibration_table_from_targets(
        calibration_targets;
        bins,
        interval,
        lower_probability,
        upper_probability,
    )
end

function calibration_table(fit::MGMFRMFit;
        target::Symbol = :expected_score,
        category = nothing,
        bins::Int = 10,
        interval::Real = 0.9,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    lower_probability, upper_probability = _interval_probabilities(interval)
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    calibration_targets = _calibration_targets_from_probabilities(
        fit.design.spec.data,
        probabilities,
        target,
        category,
    )
    return _calibration_table_from_targets(
        calibration_targets;
        bins,
        interval,
        lower_probability,
        upper_probability,
    )
end

"""
    fit_stats(fit::MFRMFit; by = :rater, method = :posterior,
        interval = 0.95, min_n = 1, ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    fit_stats(design::FacetDesign, draws; by = :rater, interval = 0.95,
        min_n = 1)

Return posterior summaries of observation-level infit and outfit mean-square
statistics by facet level. This initial implementation uses posterior draws and
the current minimal MFRM predictive variances; `method = :posterior` is the only
supported method.
"""
function fit_stats(design::FacetDesign,
        draws::AbstractMatrix;
        by::Symbol = :rater,
        interval::Real = 0.95,
        min_n::Int = 1)
    min_n >= 1 || throw(ArgumentError("min_n must be positive"))
    lower_probability, upper_probability = _interval_probabilities(interval)
    residuals = predictive_residuals(design, draws)
    variances = predictive_variances(design, draws)
    data = design.spec.data
    group_index, group_levels = _fit_stat_groups(data, by)
    rows = NamedTuple[]
    eps_var = eps(Float64)

    for (level_index, level) in pairs(group_levels)
        obs = findall(==(level_index), group_index)
        n_obs = length(obs)
        infit = Vector{Float64}(undef, size(draws, 1))
        outfit = Vector{Float64}(undef, size(draws, 1))
        tiny_variance_count = 0

        if n_obs < min_n
            fill!(infit, NaN)
            fill!(outfit, NaN)
            flag = :below_min_n
        else
            for draw in axes(draws, 1)
                residual_ss = 0.0
                variance_sum = 0.0
                standardized_sum = 0.0
                for row in obs
                    r = residuals[draw, row]
                    v = variances[draw, row]
                    if v <= eps_var
                        tiny_variance_count += 1
                    end
                    residual_ss += r * r
                    variance_sum += v
                    standardized_sum += r * r / max(v, eps_var)
                end
                infit[draw] = residual_ss / max(variance_sum, eps_var)
                outfit[draw] = standardized_sum / n_obs
            end
            flag = tiny_variance_count == 0 ? :ok : :tiny_predictive_variance
        end

        infit_summary = _finite_draw_summary(infit, lower_probability, upper_probability)
        outfit_summary = _finite_draw_summary(outfit, lower_probability, upper_probability)
        push!(rows, (;
            facet = by,
            level,
            n_obs,
            method = :posterior,
            interval_probability = Float64(interval),
            lower_probability,
            upper_probability,
            infit_mean = infit_summary.mean,
            infit_median = infit_summary.median,
            infit_lower = infit_summary.lower,
            infit_upper = infit_summary.upper,
            outfit_mean = outfit_summary.mean,
            outfit_median = outfit_summary.median,
            outfit_lower = outfit_summary.lower,
            outfit_upper = outfit_summary.upper,
            tiny_variance_count,
            flag,
        ))
    end
    return rows
end

function fit_stats(fit::MFRMFit;
        by::Symbol = :rater,
        method::Symbol = :posterior,
        interval::Real = 0.95,
        min_n::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    method === :posterior ||
        throw(ArgumentError("only method = :posterior is currently supported"))
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return fit_stats(fit.design, fit.draws[indices, :]; by, interval, min_n)
end

function _residual_summary_groups(data::FacetData, by::Symbol)
    by === :observation && return collect(1:data.n), collect(1:data.n)
    return _fit_stat_groups(data, by)
end

function _posterior_group_mean(values::AbstractMatrix{<:Real},
        observations::AbstractVector{Int})
    out = Vector{Float64}(undef, size(values, 1))
    for draw in axes(values, 1)
        out[draw] = _mean_at_indices(@view(values[draw, :]), observations)
    end
    return out
end

function _posterior_group_absolute_mean(values::AbstractMatrix{<:Real},
        observations::AbstractVector{Int})
    out = Vector{Float64}(undef, size(values, 1))
    for draw in axes(values, 1)
        total = 0.0
        for observation in observations
            total += abs(Float64(values[draw, observation]))
        end
        out[draw] = total / length(observations)
    end
    return out
end

function _posterior_group_rmse(values::AbstractMatrix{<:Real},
        observations::AbstractVector{Int})
    out = Vector{Float64}(undef, size(values, 1))
    for draw in axes(values, 1)
        total = 0.0
        for observation in observations
            value = Float64(values[draw, observation])
            total += value * value
        end
        out[draw] = sqrt(total / length(observations))
    end
    return out
end

function _residual_summary_rows(data::FacetData,
        expected::AbstractMatrix{<:Real},
        residuals::AbstractMatrix{<:Real};
        by::Symbol,
        interval::Real,
        min_n::Int)
    min_n >= 1 || throw(ArgumentError("min_n must be positive"))
    size(expected) == size(residuals) ||
        throw(ArgumentError("expected and residual matrices must have the same shape"))
    size(expected, 1) >= 1 ||
        throw(ArgumentError("residual_summary requires at least one posterior draw"))
    size(expected, 2) == data.n ||
        throw(ArgumentError("residual_summary observation count does not match data"))
    all(value -> isfinite(Float64(value)), expected) ||
        throw(ArgumentError("expected score matrix contains non-finite values"))
    all(value -> isfinite(Float64(value)), residuals) ||
        throw(ArgumentError("residual matrix contains non-finite values"))

    lower_probability, upper_probability = _interval_probabilities(interval)
    group_index, group_levels = _residual_summary_groups(data, by)
    rows = NamedTuple[]
    for (level_index, level) in pairs(group_levels)
        observations = findall(==(level_index), group_index)
        n_observations = length(observations)
        expected_by_draw = _posterior_group_mean(expected, observations)
        residual_by_draw = _posterior_group_mean(residuals, observations)
        absolute_residual_by_draw =
            _posterior_group_absolute_mean(residuals, observations)
        rmse_by_draw = _posterior_group_rmse(residuals, observations)

        expected_summary = _finite_draw_summary(
            expected_by_draw,
            lower_probability,
            upper_probability,
        )
        residual_summary = _finite_draw_summary(
            residual_by_draw,
            lower_probability,
            upper_probability,
        )
        absolute_residual_summary = _finite_draw_summary(
            absolute_residual_by_draw,
            lower_probability,
            upper_probability,
        )
        rmse_summary = _finite_draw_summary(
            rmse_by_draw,
            lower_probability,
            upper_probability,
        )
        residual_interval_excludes_zero =
            isfinite(residual_summary.lower) &&
            isfinite(residual_summary.upper) &&
            (residual_summary.lower > 0 || residual_summary.upper < 0)
        flag = n_observations < min_n ? :below_min_n :
            residual_interval_excludes_zero ? :residual_interval_excludes_zero : :ok

        push!(rows, (;
            facet = by,
            level,
            n_observations,
            n_draws = size(expected, 1),
            method = :posterior_expected_score,
            interval_probability = Float64(interval),
            lower_probability,
            upper_probability,
            observed_mean = _mean_at_indices(data.score, observations),
            expected_mean = expected_summary.mean,
            expected_median = expected_summary.median,
            expected_lower = expected_summary.lower,
            expected_upper = expected_summary.upper,
            residual_mean = residual_summary.mean,
            residual_median = residual_summary.median,
            residual_lower = residual_summary.lower,
            residual_upper = residual_summary.upper,
            absolute_residual_mean = absolute_residual_summary.mean,
            absolute_residual_median = absolute_residual_summary.median,
            absolute_residual_lower = absolute_residual_summary.lower,
            absolute_residual_upper = absolute_residual_summary.upper,
            rmse_mean = rmse_summary.mean,
            rmse_median = rmse_summary.median,
            rmse_lower = rmse_summary.lower,
            rmse_upper = rmse_summary.upper,
            residual_interval_excludes_zero,
            caveat = :posterior_predictive_residual_screening_not_confirmatory,
            flag,
        ))
    end
    return rows
end

"""
    residual_summary(fit::MFRMFit; by = :observation, interval = 0.95,
        min_n = 1, ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    residual_summary(design::FacetDesign, draws; by = :observation,
        interval = 0.95, min_n = 1)

Return posterior summaries of observed-minus-expected score residuals by
observation or facet level. Rows include observed mean score, posterior
expected-score intervals, residual intervals, mean absolute residual, RMSE, and
a screening caveat flag. Use `by = :person`, `:rater`, `:item`, `:category`, or
an optional facet name to aggregate rows; `by = :observation` returns one row
per original response. Fitted-object methods are available for MFRM and guarded
scalar GMFRM fit objects.
"""
function residual_summary(design::FacetDesign,
        draws::AbstractMatrix;
        by::Symbol = :observation,
        interval::Real = 0.95,
        min_n::Int = 1)
    expected = expected_scores(design, draws)
    residuals = predictive_residuals(design, draws)
    return _residual_summary_rows(design.spec.data, expected, residuals;
        by,
        interval,
        min_n)
end

function residual_summary(fit::MFRMFit;
        by::Symbol = :observation,
        interval::Real = 0.95,
        min_n::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return residual_summary(fit.design, fit.draws[indices, :];
        by,
        interval,
        min_n)
end

function residual_summary(fit::GMFRMFit;
        by::Symbol = :observation,
        interval::Real = 0.95,
        min_n::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    expected = expected_scores(fit; draw_indices = indices)
    residuals = predictive_residuals(fit; draw_indices = indices)
    return _residual_summary_rows(fit.design.spec.data, expected, residuals;
        by,
        interval,
        min_n)
end

function _dff_report_terms(design::FacetDesign, terms)
    data = design.spec.data
    if terms === :validation
        out = Tuple{Symbol,Symbol}[design.spec.validation_bias_terms...]
        isempty(out) &&
            throw(ArgumentError("dff_report requires declared validation DFF terms; pass terms explicitly for an ad hoc report"))
    elseif terms isa Tuple && length(terms) == 2 &&
            first(terms) isa Symbol && last(terms) isa Symbol
        out = Tuple{Symbol,Symbol}[(first(terms), last(terms))]
    elseif terms isa Symbol
        throw(ArgumentError("terms must be :validation, one two-facet tuple, or a collection of two-facet tuples"))
    else
        out = Tuple{Symbol,Symbol}[]
        for term in terms
            term isa Tuple && length(term) == 2 &&
                first(term) isa Symbol && last(term) isa Symbol ||
                throw(ArgumentError("terms must be :validation, one two-facet tuple, or a collection of two-facet tuples"))
            normalized = (first(term), last(term))
            normalized in out &&
                throw(ArgumentError("terms must not contain duplicates"))
            push!(out, normalized)
        end
        isempty(out) &&
            throw(ArgumentError("terms must contain at least one DFF term"))
    end
    for term in out
        _fit_stat_groups(data, term[1])
        _fit_stat_groups(data, term[2])
    end
    return Tuple(out)
end

function _dff_observations(index::AbstractVector{Int}, level_index::Int)
    return findall(==(level_index), index)
end

function _dff_observations(index_a::AbstractVector{Int},
        level_a::Int,
        index_b::AbstractVector{Int},
        level_b::Int)
    return findall(row -> index_a[row] == level_a && index_b[row] == level_b,
        eachindex(index_a))
end

function _dff_logit_shift_draws(residuals::AbstractVector{<:Real},
        slopes::AbstractVector{<:Real})
    length(residuals) == length(slopes) ||
        throw(ArgumentError("residual and slope vectors must have the same length"))
    out = Vector{Float64}(undef, length(residuals))
    eps_slope = eps(Float64)
    for index in eachindex(residuals)
        slope = Float64(slopes[index])
        residual = Float64(residuals[index])
        out[index] = isfinite(slope) && abs(slope) > eps_slope ?
            residual / slope : NaN
    end
    return out
end

function _dff_group_draws(expected::AbstractMatrix{<:Real},
        residuals::AbstractMatrix{<:Real},
        slopes::AbstractMatrix{<:Real},
        observations::AbstractVector{Int})
    expected_by_draw = _posterior_group_mean(expected, observations)
    residual_by_draw = _posterior_group_mean(residuals, observations)
    slope_by_draw = _posterior_group_mean(slopes, observations)
    logit_shift_by_draw = _dff_logit_shift_draws(residual_by_draw, slope_by_draw)
    return (;
        expected = expected_by_draw,
        residual = residual_by_draw,
        slope = slope_by_draw,
        logit_shift = logit_shift_by_draw,
    )
end

function _dff_interval_excludes_zero(summary)
    return isfinite(summary.lower) &&
        isfinite(summary.upper) &&
        (summary.lower > 0 || summary.upper < 0)
end

function _dff_practical_threshold(value, name::AbstractString)
    value === nothing && return nothing
    value isa Real ||
        throw(ArgumentError("$name must be nothing or a finite non-negative number"))
    checked = Float64(value)
    isfinite(checked) && checked >= 0 ||
        throw(ArgumentError("$name must be nothing or a finite non-negative number"))
    return checked
end

function _dff_practical_probability_threshold(value::Real)
    checked = Float64(value)
    isfinite(checked) && 0 < checked <= 1 ||
        throw(ArgumentError("practical_probability_threshold must be finite and in (0, 1]"))
    return checked
end

function _dff_practical_magnitude_summary(values::AbstractVector{<:Real},
        threshold,
        probability_threshold::Float64)
    threshold === nothing && return (;
        practical_threshold = nothing,
        probability_practically_positive = nothing,
        probability_practically_negative = nothing,
        probability_practically_negligible = nothing,
        probability_practically_large = nothing,
        practical_magnitude = :not_requested,
    )

    finite = [Float64(value) for value in values if isfinite(value)]
    if isempty(finite)
        return (;
            practical_threshold = threshold,
            probability_practically_positive = NaN,
            probability_practically_negative = NaN,
            probability_practically_negligible = NaN,
            probability_practically_large = NaN,
            practical_magnitude = :not_estimable,
        )
    end

    n = length(finite)
    positive = count(>(threshold), finite) / n
    negative = count(<(-threshold), finite) / n
    negligible = count(value -> -threshold <= value <= threshold, finite) / n
    large = positive + negative
    practical_magnitude =
        positive >= probability_threshold ? :practically_positive :
        negative >= probability_threshold ? :practically_negative :
        negligible >= probability_threshold ? :practically_negligible :
        :mixed
    return (;
        practical_threshold = threshold,
        probability_practically_positive = positive,
        probability_practically_negative = negative,
        probability_practically_negligible = negligible,
        probability_practically_large = large,
        practical_magnitude,
    )
end

function _dff_cell_flag(n_observations::Int,
        min_n::Int,
        expected_score_dff_summary,
        logit_dff_summary)
    n_observations == 0 && return :empty_cell
    n_observations < min_n && return :below_min_n
    !isfinite(logit_dff_summary.mean) && return :logit_scale_unstable
    (_dff_interval_excludes_zero(expected_score_dff_summary) ||
        _dff_interval_excludes_zero(logit_dff_summary)) &&
        return :dff_interval_excludes_zero
    return :ok
end

function _dff_report_rows_for_term(design::FacetDesign,
        expected::AbstractMatrix{<:Real},
        residuals::AbstractMatrix{<:Real},
        slopes::AbstractMatrix{<:Real},
        term::Tuple{Symbol,Symbol};
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64,
        min_n::Int,
        expected_score_practical_threshold,
        logit_practical_threshold,
        practical_probability_threshold::Float64)
    data = design.spec.data
    focal_facet, comparison_facet = term
    focal_index, focal_levels = _fit_stat_groups(data, focal_facet)
    comparison_index, comparison_levels = _fit_stat_groups(data, comparison_facet)
    validation_counts = get(design.spec.validation.dff_counts, term, nothing)
    validation_status = term in design.spec.validation_bias_terms ?
        :declared_validation_term : :ad_hoc_term
    all_observations = collect(1:data.n)
    grand = _dff_group_draws(expected, residuals, slopes, all_observations)
    focal_draws = [
        _dff_group_draws(
            expected,
            residuals,
            slopes,
            _dff_observations(focal_index, focal_level),
        )
        for focal_level in eachindex(focal_levels)
    ]
    comparison_draws = [
        _dff_group_draws(
            expected,
            residuals,
            slopes,
            _dff_observations(comparison_index, comparison_level),
        )
        for comparison_level in eachindex(comparison_levels)
    ]

    rows = NamedTuple[]
    for (focal_level_index, focal_level) in pairs(focal_levels),
            (comparison_level_index, comparison_level) in pairs(comparison_levels)
        observations = _dff_observations(
            focal_index,
            focal_level_index,
            comparison_index,
            comparison_level_index,
        )
        cell = _dff_group_draws(expected, residuals, slopes, observations)
        focal = focal_draws[focal_level_index]
        comparison = comparison_draws[comparison_level_index]
        expected_score_dff = cell.residual .- focal.residual .-
            comparison.residual .+ grand.residual
        logit_dff = cell.logit_shift .- focal.logit_shift .-
            comparison.logit_shift .+ grand.logit_shift

        expected_summary = _finite_draw_summary(
            cell.expected,
            lower_probability,
            upper_probability,
        )
        residual_summary = _finite_draw_summary(
            cell.residual,
            lower_probability,
            upper_probability,
        )
        logit_summary = _finite_draw_summary(
            cell.logit_shift,
            lower_probability,
            upper_probability,
        )
        expected_score_dff_summary = _finite_draw_summary(
            expected_score_dff,
            lower_probability,
            upper_probability,
        )
        logit_dff_summary = _finite_draw_summary(
            logit_dff,
            lower_probability,
            upper_probability,
        )
        expected_score_practical_summary = _dff_practical_magnitude_summary(
            expected_score_dff,
            expected_score_practical_threshold,
            practical_probability_threshold,
        )
        logit_practical_summary = _dff_practical_magnitude_summary(
            logit_dff,
            logit_practical_threshold,
            practical_probability_threshold,
        )
        n_observations = length(observations)
        expected_score_dff_interval_excludes_zero =
            _dff_interval_excludes_zero(expected_score_dff_summary)
        logit_dff_interval_excludes_zero =
            _dff_interval_excludes_zero(logit_dff_summary)
        validation_cell_count = validation_counts === nothing ? missing :
            get(validation_counts, (focal_level, comparison_level), missing)

        push!(rows, (;
            term,
            focal_facet,
            focal_level,
            focal_level_index,
            comparison_facet,
            comparison_level,
            comparison_level_index,
            n_observations,
            validation_cell_count,
            n_draws = size(expected, 1),
            method = :posterior_predictive_interaction_residual,
            logit_method = :local_expected_score_residual_divided_by_predictive_variance,
            scale = :expected_score_and_logit,
            interval_probability = Float64(interval),
            lower_probability,
            upper_probability,
            observed_mean = _mean_at_indices(data.score, observations),
            expected_score_mean = expected_summary.mean,
            expected_score_median = expected_summary.median,
            expected_score_lower = expected_summary.lower,
            expected_score_upper = expected_summary.upper,
            expected_score_residual_mean = residual_summary.mean,
            expected_score_residual_median = residual_summary.median,
            expected_score_residual_lower = residual_summary.lower,
            expected_score_residual_upper = residual_summary.upper,
            logit_residual_mean = logit_summary.mean,
            logit_residual_median = logit_summary.median,
            logit_residual_lower = logit_summary.lower,
            logit_residual_upper = logit_summary.upper,
            expected_score_dff_mean = expected_score_dff_summary.mean,
            expected_score_dff_median = expected_score_dff_summary.median,
            expected_score_dff_lower = expected_score_dff_summary.lower,
            expected_score_dff_upper = expected_score_dff_summary.upper,
            logit_dff_mean = logit_dff_summary.mean,
            logit_dff_median = logit_dff_summary.median,
            logit_dff_lower = logit_dff_summary.lower,
            logit_dff_upper = logit_dff_summary.upper,
            expected_score_dff_interval_excludes_zero,
            logit_dff_interval_excludes_zero,
            practical_probability_threshold,
            expected_score_dff_practical_threshold =
                expected_score_practical_summary.practical_threshold,
            expected_score_dff_probability_practically_positive =
                expected_score_practical_summary.probability_practically_positive,
            expected_score_dff_probability_practically_negative =
                expected_score_practical_summary.probability_practically_negative,
            expected_score_dff_probability_practically_negligible =
                expected_score_practical_summary.probability_practically_negligible,
            expected_score_dff_probability_practically_large =
                expected_score_practical_summary.probability_practically_large,
            expected_score_dff_practical_magnitude =
                expected_score_practical_summary.practical_magnitude,
            logit_dff_practical_threshold =
                logit_practical_summary.practical_threshold,
            logit_dff_probability_practically_positive =
                logit_practical_summary.probability_practically_positive,
            logit_dff_probability_practically_negative =
                logit_practical_summary.probability_practically_negative,
            logit_dff_probability_practically_negligible =
                logit_practical_summary.probability_practically_negligible,
            logit_dff_probability_practically_large =
                logit_practical_summary.probability_practically_large,
            logit_dff_practical_magnitude =
                logit_practical_summary.practical_magnitude,
            validation_status,
            caveat = :dff_screening_not_fitted_dff_effect,
            flag = _dff_cell_flag(
                n_observations,
                min_n,
                expected_score_dff_summary,
                logit_dff_summary,
            ),
        ))
    end
    return rows
end

"""
    dff_report(fit::MFRMFit; terms = :validation, interval = 0.95,
        min_n = 1, expected_score_practical_threshold = nothing,
        logit_practical_threshold = nothing,
        practical_probability_threshold = 0.8, ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())
    dff_report(design::FacetDesign, draws; terms = :validation,
        interval = 0.95, min_n = 1,
        expected_score_practical_threshold = nothing,
        logit_practical_threshold = nothing,
        practical_probability_threshold = 0.8)

Return screening rows for declared or ad hoc differential facet functioning
(DFF) terms. The default `terms = :validation` uses DFF/bias terms retained in
the `FacetSpec` by `mfrm_spec(...; bias = ...)` or a matching validation
report. Each row is one cell of a two-facet term and reports observed mean
score, posterior expected-score residuals, and a two-way interaction residual
on both expected-score and local logit-approximation scales.

Pass `expected_score_practical_threshold` and/or `logit_practical_threshold`
to add estimand-specific practical-magnitude probabilities and classification.
Rows classify a DFF contrast as `:practically_positive`,
`:practically_negative`, `:practically_negligible`, or `:mixed` when the
corresponding posterior probability is at least
`practical_probability_threshold`; otherwise the practical-magnitude status is
`:not_requested`.

These rows are not fitted DFF model effects. The logit scale is a local
screening approximation that divides expected-score residuals by posterior
predictive variance, so results should be used for fairness review triage and
sensitivity planning rather than confirmatory unfairness claims.
"""
function dff_report(design::FacetDesign,
        draws::AbstractMatrix;
        terms = :validation,
        interval::Real = 0.95,
        min_n::Int = 1,
        expected_score_practical_threshold = nothing,
        logit_practical_threshold = nothing,
        practical_probability_threshold::Real = 0.8)
    _check_fit_supported_mfrm(design, "dff_report")
    min_n >= 1 || throw(ArgumentError("min_n must be positive"))
    lower_probability, upper_probability = _interval_probabilities(interval)
    checked_expected_score_threshold = _dff_practical_threshold(
        expected_score_practical_threshold,
        "expected_score_practical_threshold",
    )
    checked_logit_threshold = _dff_practical_threshold(
        logit_practical_threshold,
        "logit_practical_threshold",
    )
    checked_practical_probability_threshold =
        _dff_practical_probability_threshold(practical_probability_threshold)
    requested_terms = _dff_report_terms(design, terms)
    expected = expected_scores(design, draws)
    residuals = predictive_residuals(design, draws)
    slopes = predictive_variances(design, draws)
    rows = NamedTuple[]
    for term in requested_terms
        append!(rows, _dff_report_rows_for_term(
            design,
            expected,
            residuals,
            slopes,
            term;
            interval,
            lower_probability,
            upper_probability,
            min_n,
            expected_score_practical_threshold =
                checked_expected_score_threshold,
            logit_practical_threshold = checked_logit_threshold,
            practical_probability_threshold =
                checked_practical_probability_threshold,
        ))
    end
    return rows
end

function dff_report(fit::MFRMFit;
        terms = :validation,
        interval::Real = 0.95,
        min_n::Int = 1,
        expected_score_practical_threshold = nothing,
        logit_practical_threshold = nothing,
        practical_probability_threshold::Real = 0.8,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return dff_report(fit.design, fit.draws[indices, :];
        terms,
        interval,
        min_n,
        expected_score_practical_threshold,
        logit_practical_threshold,
        practical_probability_threshold)
end

function _check_rater_diagnostic_draws(design::FacetDesign,
        draws::AbstractMatrix,
        caller::AbstractString)
    size(draws, 1) >= 1 ||
        throw(ArgumentError("$caller requires at least one posterior draw"))
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    all(value -> isfinite(Float64(value)), draws) ||
        throw(ArgumentError("draws contain non-finite values"))
    return draws
end

function _category_use_rows(data::FacetData,
        counts::AbstractVector{<:Integer},
        n_observations::Int)
    category_counts = [
        (category = data.category_levels[index], count = Int(counts[index]))
        for index in eachindex(data.category_levels)
    ]
    category_proportions = [
        (category = data.category_levels[index],
            proportion = n_observations == 0 ? NaN : counts[index] / n_observations)
        for index in eachindex(data.category_levels)
    ]
    unused_categories = [
        data.category_levels[index]
        for index in eachindex(data.category_levels)
        if counts[index] == 0
    ]
    return category_counts, category_proportions, unused_categories
end

function _central_category_summary(data::FacetData,
        counts::AbstractVector{<:Integer},
        n_observations::Int)
    score_minimum = minimum(data.category_levels)
    score_maximum = maximum(data.category_levels)
    midpoint = (Float64(score_minimum) + Float64(score_maximum)) / 2
    distances = [abs(Float64(level) - midpoint) for level in data.category_levels]
    closest = minimum(distances)
    central_indices = findall(==(closest), distances)
    central_categories = [data.category_levels[index] for index in central_indices]
    central_count = sum(counts[index] for index in central_indices)
    return (;
        scale_midpoint = midpoint,
        central_categories,
        central_category_count = Int(central_count),
        central_category_proportion =
            n_observations == 0 ? NaN : central_count / n_observations,
    )
end

function _rater_observed_diagnostic_summary(data::FacetData, rater_index::Int)
    observations = findall(==(rater_index), data.rater)
    n_observations = length(observations)
    counts = zeros(Int, length(data.category_levels))
    for observation in observations
        counts[data.category[observation]] += 1
    end
    category_counts, category_proportions, unused_categories =
        _category_use_rows(data, counts, n_observations)
    central = _central_category_summary(data, counts, n_observations)
    score_values = [Float64(data.score[observation]) for observation in observations]
    score_mean = _mean_at_indices(data.score, observations)
    score_sd = length(score_values) >= 2 ?
        sqrt(_sample_variance_or_nan(score_values)) : NaN
    score_minimum = isempty(score_values) ? missing : minimum(score_values)
    score_maximum = isempty(score_values) ? missing : maximum(score_values)
    score_range = isempty(score_values) ? missing : score_maximum - score_minimum

    return (;
        n_observations,
        n_categories = length(data.category_levels),
        n_categories_used = count(>(0), counts),
        category_counts,
        category_proportions,
        unused_categories,
        mean_score = score_mean,
        score_sd,
        min_score = score_minimum,
        max_score = score_maximum,
        score_range,
        central.scale_midpoint,
        central.central_categories,
        central.central_category_count,
        central.central_category_proportion,
    )
end

function _rater_mfrm_severity_draws(design::FacetDesign,
        draws::AbstractMatrix,
        rater_index::Int)
    values = Vector{Float64}(undef, size(draws, 1))
    for draw in axes(draws, 1)
        values[draw] = Float64(_reference_value(
            @view(draws[draw, :]),
            design.blocks[:rater],
            rater_index,
        ))
    end
    return values
end

function _rater_direct_block_draws(design::FacetDesign,
        direct_draws::AbstractMatrix,
        block::Symbol,
        rater_index::Int)
    haskey(design.blocks, block) || return nothing
    block_range = design.blocks[block]
    1 <= rater_index <= length(block_range) || return nothing
    values = Vector{Float64}(undef, size(direct_draws, 1))
    column = block_range[rater_index]
    for draw in axes(direct_draws, 1)
        values[draw] = Float64(direct_draws[draw, column])
    end
    return values
end

function _maybe_finite_draw_summary(values,
        lower_probability::Float64,
        upper_probability::Float64)
    values === nothing &&
        return (mean = missing, median = missing, lower = missing, upper = missing)
    return _finite_draw_summary(values, lower_probability, upper_probability)
end

function _rater_diagnostics_flag(n_observations::Int,
        min_n::Int,
        residual_flag,
        fit_flag)
    n_observations < min_n && return :below_min_n
    residual_flag !== :ok && return residual_flag
    fit_flag !== missing && fit_flag !== :ok && return fit_flag
    return :ok
end

function _row_by_level(rows)
    return Dict(row.level => row for row in rows)
end

function _rater_diagnostic_row(;
        data::FacetData,
        model_family::Symbol,
        level_index::Int,
        level,
        n_draws::Int,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64,
        severity_parameter_name,
        severity_values,
        discrimination_modeled::Bool,
        discrimination_parameter,
        discrimination_parameter_name,
        discrimination_scale::Symbol,
        discrimination_values,
        residual_row,
        fit_row,
        fit_statistics_available::Bool,
        min_n::Int)
    observed = _rater_observed_diagnostic_summary(data, level_index)
    severity_summary =
        _finite_draw_summary(severity_values, lower_probability, upper_probability)
    discrimination_summary =
        _maybe_finite_draw_summary(
            discrimination_values,
            lower_probability,
            upper_probability,
        )
    fit_flag = fit_statistics_available ? fit_row.flag : missing
    flag = _rater_diagnostics_flag(
        observed.n_observations,
        min_n,
        residual_row.flag,
        fit_flag,
    )

    return (;
        facet = :rater,
        level,
        rater = level,
        rater_index = level_index,
        model_family,
        method = :posterior_rater_diagnostics,
        n_draws,
        interval_probability = Float64(interval),
        lower_probability,
        upper_probability,
        observed.n_observations,
        observed.n_categories,
        observed.n_categories_used,
        observed.category_counts,
        observed.category_proportions,
        observed.unused_categories,
        observed.mean_score,
        observed.score_sd,
        observed.min_score,
        observed.max_score,
        observed.score_range,
        observed.scale_midpoint,
        observed.central_categories,
        observed.central_category_count,
        observed.central_category_proportion,
        severity_parameter_name,
        severity_reference = severity_parameter_name === missing,
        severity_mean = severity_summary.mean,
        severity_median = severity_summary.median,
        severity_lower = severity_summary.lower,
        severity_upper = severity_summary.upper,
        discrimination_modeled,
        discrimination_parameter,
        discrimination_parameter_name,
        discrimination_scale,
        discrimination_mean = discrimination_summary.mean,
        discrimination_median = discrimination_summary.median,
        discrimination_lower = discrimination_summary.lower,
        discrimination_upper = discrimination_summary.upper,
        residual_mean = residual_row.residual_mean,
        residual_median = residual_row.residual_median,
        residual_lower = residual_row.residual_lower,
        residual_upper = residual_row.residual_upper,
        absolute_residual_mean = residual_row.absolute_residual_mean,
        absolute_residual_median = residual_row.absolute_residual_median,
        absolute_residual_lower = residual_row.absolute_residual_lower,
        absolute_residual_upper = residual_row.absolute_residual_upper,
        rmse_mean = residual_row.rmse_mean,
        rmse_median = residual_row.rmse_median,
        rmse_lower = residual_row.rmse_lower,
        rmse_upper = residual_row.rmse_upper,
        residual_interval_excludes_zero = residual_row.residual_interval_excludes_zero,
        residual_flag = residual_row.flag,
        fit_statistics_available,
        infit_mean = fit_statistics_available ? fit_row.infit_mean : missing,
        infit_median = fit_statistics_available ? fit_row.infit_median : missing,
        infit_lower = fit_statistics_available ? fit_row.infit_lower : missing,
        infit_upper = fit_statistics_available ? fit_row.infit_upper : missing,
        outfit_mean = fit_statistics_available ? fit_row.outfit_mean : missing,
        outfit_median = fit_statistics_available ? fit_row.outfit_median : missing,
        outfit_lower = fit_statistics_available ? fit_row.outfit_lower : missing,
        outfit_upper = fit_statistics_available ? fit_row.outfit_upper : missing,
        fit_flag,
        caveat = :rater_diagnostics_screening_not_confirmatory,
        flag,
    )
end

"""
    rater_diagnostics(fit::MFRMFit; interval = 0.95, min_n = 1,
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng())
    rater_diagnostics(fit::GMFRMFit; interval = 0.95, min_n = 1,
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng())
    rater_diagnostics(design::FacetDesign, draws; interval = 0.95, min_n = 1)

Return one posterior diagnostic row per rater. Rows combine observed category
use, score range and central-category use, posterior rater severity intervals,
posterior residual summaries, and MFRM infit/outfit summaries where available.
For the fit-supported minimal MFRM, rater discrimination is not modeled and the
discrimination fields are marked missing. For the guarded scalar GMFRM
experimental fit object, the `rater_consistency` multiplier is summarized as
the current positive rater-discrimination/consistency parameter; infit/outfit
statistics are not yet available for that experimental path.
"""
function rater_diagnostics(design::FacetDesign,
        draws::AbstractMatrix;
        interval::Real = 0.95,
        min_n::Int = 1)
    _check_fit_supported_mfrm(design, "rater_diagnostics")
    min_n >= 1 || throw(ArgumentError("min_n must be positive"))
    _check_rater_diagnostic_draws(design, draws, "rater_diagnostics")
    lower_probability, upper_probability = _interval_probabilities(interval)
    data = design.spec.data
    residual_by_level = _row_by_level(residual_summary(design, draws;
        by = :rater,
        interval,
        min_n))
    fit_by_level = _row_by_level(fit_stats(design, draws;
        by = :rater,
        interval,
        min_n))
    rows = NamedTuple[]

    for (level_index, level) in pairs(data.rater_levels)
        severity_values = _rater_mfrm_severity_draws(design, draws, level_index)
        severity_parameter_name = level_index == 1 ? missing :
            design.parameter_names[design.blocks[:rater][level_index - 1]]
        push!(rows, _rater_diagnostic_row(;
            data,
            model_family = :mfrm,
            level_index,
            level,
            n_draws = size(draws, 1),
            interval,
            lower_probability,
            upper_probability,
            severity_parameter_name,
            severity_values,
            discrimination_modeled = false,
            discrimination_parameter = missing,
            discrimination_parameter_name = missing,
            discrimination_scale = :not_modeled,
            discrimination_values = nothing,
            residual_row = residual_by_level[level],
            fit_row = fit_by_level[level],
            fit_statistics_available = true,
            min_n,
        ))
    end
    return rows
end

function rater_diagnostics(fit::MFRMFit;
        interval::Real = 0.95,
        min_n::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return rater_diagnostics(fit.design, fit.draws[indices, :];
        interval,
        min_n)
end

function rater_diagnostics(fit::GMFRMFit;
        interval::Real = 0.95,
        min_n::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    min_n >= 1 || throw(ArgumentError("min_n must be positive"))
    lower_probability, upper_probability = _interval_probabilities(interval)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    direct_draws = _gmfrm_direct_draws_for_prediction(
        fit.design,
        fit.direct_draws[indices, :],
        "rater_diagnostics",
    )
    data = fit.design.spec.data
    residual_by_level = _row_by_level(residual_summary(fit;
        by = :rater,
        interval,
        min_n,
        draw_indices = indices))
    rows = NamedTuple[]

    for (level_index, level) in pairs(data.rater_levels)
        severity_values =
            _rater_direct_block_draws(fit.design, direct_draws, :rater, level_index)
        severity_values === nothing &&
            throw(ArgumentError("rater_diagnostics requires a direct rater block"))
        severity_index = fit.design.blocks[:rater][level_index]
        discrimination_values = _rater_direct_block_draws(
            fit.design,
            direct_draws,
            :rater_consistency,
            level_index,
        )
        discrimination_modeled = discrimination_values !== nothing
        discrimination_index = discrimination_modeled ?
            fit.design.blocks[:rater_consistency][level_index] : missing

        push!(rows, _rater_diagnostic_row(;
            data,
            model_family = :gmfrm,
            level_index,
            level,
            n_draws = size(direct_draws, 1),
            interval,
            lower_probability,
            upper_probability,
            severity_parameter_name = fit.design.parameter_names[severity_index],
            severity_values,
            discrimination_modeled,
            discrimination_parameter = discrimination_modeled ?
                :rater_consistency : missing,
            discrimination_parameter_name = discrimination_modeled ?
                fit.design.parameter_names[discrimination_index] : missing,
            discrimination_scale = discrimination_modeled ?
                :positive_consistency_multiplier : :not_modeled,
            discrimination_values,
            residual_row = residual_by_level[level],
            fit_row = missing,
            fit_statistics_available = false,
            min_n,
        ))
    end
    return rows
end

function _sample_category_index(rng::AbstractRNG, probs::AbstractVector{Float64})
    u = rand(rng)
    cumulative = 0.0
    for category in eachindex(probs)
        cumulative += probs[category]
        u <= cumulative && return category
    end
    return lastindex(probs)
end

function _replicate_scores(design::FacetDesign, draws::AbstractMatrix, rng::AbstractRNG)
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    data = design.spec.data
    K = length(data.category_levels)
    replicated = Matrix{Int}(undef, size(draws, 1), data.n)
    probs = zeros(Float64, K)

    for replication in axes(draws, 1)
        params = @view draws[replication, :]
        for row in 1:data.n
            _category_probabilities!(probs, design, params, row)
            category = _sample_category_index(rng, probs)
            replicated[replication, row] = data.category_levels[category]
        end
    end
    return replicated
end

function _replicate_scores_gmfrm_direct(
        design::FacetDesign,
        direct_draws::AbstractMatrix,
        rng::AbstractRNG,
        caller::AbstractString = "posterior_predict")
    checked = _gmfrm_direct_draws_for_prediction(
        design,
        direct_draws,
        caller,
    )
    data = design.spec.data
    K = length(data.category_levels)
    replicated = Matrix{Int}(undef, size(checked, 1), data.n)
    probs = zeros(Float64, K)

    for replication in axes(checked, 1)
        direct_params = @view checked[replication, :]
        for row in 1:data.n
            _gmfrm_category_probabilities!(probs, design, direct_params, row)
            category = _sample_category_index(rng, probs)
            replicated[replication, row] = data.category_levels[category]
        end
    end
    return replicated
end

function _replicate_scores_mgmfrm_direct(
        design::FacetDesign,
        direct_draws::AbstractMatrix,
        rng::AbstractRNG,
        caller::AbstractString = "posterior_predict")
    checked = _mgmfrm_direct_draws_for_prediction(
        design,
        direct_draws,
        caller,
    )
    data = design.spec.data
    K = length(data.category_levels)
    replicated = Matrix{Int}(undef, size(checked, 1), data.n)
    probs = zeros(Float64, K)
    index_by_name = _parameter_index_map(design)

    for replication in axes(checked, 1)
        direct_params = @view checked[replication, :]
        for row in 1:data.n
            _mgmfrm_category_probabilities!(probs, design, index_by_name, direct_params, row)
            category = _sample_category_index(rng, probs)
            replicated[replication, row] = data.category_levels[category]
        end
    end
    return replicated
end

function _prior_parameter_draws(design::FacetDesign,
        prior::MFRMPrior,
        ndraws::Int,
        rng::AbstractRNG)
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    nparams = length(design.parameter_names)
    draws = Matrix{Float64}(undef, ndraws, nparams)
    for draw in 1:ndraws, param in 1:nparams
        draws[draw, param] = _prior_sd(design, prior, param) * randn(rng)
    end
    return draws
end

"""
    prior_predict(spec_or_design; prior = MFRMPrior(), ndraws = 1000,
        rng = Random.default_rng())

Generate replicated score matrices from prior draws for the minimal MFRM
design. The returned matrix has one replicated dataset per row and one rating
observation per column, with entries on the original integer score scale.
"""
function prior_predict(design::FacetDesign;
        prior::MFRMPrior = MFRMPrior(),
        ndraws::Int = 1000,
        rng::AbstractRNG = Random.default_rng())
    draws = _prior_parameter_draws(design, prior, ndraws, rng)
    return _replicate_scores(design, draws, rng)
end

prior_predict(spec::FacetSpec; kwargs...) = prior_predict(getdesign(spec); kwargs...)

"""
    posterior_predict(fit::MFRMFit; ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())

Generate replicated score matrices from posterior draws. The returned matrix
has one replicated dataset per row and one rating observation per column, with
entries on the original integer score scale.
"""
function posterior_predict(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _replicate_scores(fit.design, fit.draws[indices, :], rng)
end

function posterior_predict(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _replicate_scores_gmfrm_direct(
        fit.design,
        fit.direct_draws[indices, :],
        rng,
    )
end

function posterior_predict(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _replicate_scores_mgmfrm_direct(
        fit.design,
        fit.direct_draws[indices, :],
        rng,
    )
end

function _mean_score(scores::AbstractVector{<:Integer})
    isempty(scores) && return NaN
    return sum(Float64, scores) / length(scores)
end

function _category_proportions(scores::AbstractVector{<:Integer}, levels::AbstractVector{Int})
    counts = zeros(Float64, length(levels))
    level_index = Dict(level => index for (index, level) in pairs(levels))
    for score in scores
        counts[level_index[score]] += 1
    end
    if !isempty(scores)
        counts ./= length(scores)
    end
    return counts
end

function _facet_mean_scores(scores::AbstractVector{<:Integer},
        index::AbstractVector{Int},
        levels::AbstractVector)
    sums = zeros(Float64, length(levels))
    counts = zeros(Int, length(levels))
    for row in eachindex(scores)
        facet_index = index[row]
        sums[facet_index] += scores[row]
        counts[facet_index] += 1
    end
    return [counts[i] == 0 ? NaN : sums[i] / counts[i] for i in eachindex(levels)]
end

function _predictive_summary(data::FacetData, scores::AbstractVector{<:Integer})
    length(scores) == data.n ||
        throw(ArgumentError("scores has length $(length(scores)); expected $(data.n)"))
    optional_mean = Dict{Symbol,Vector{Float64}}()
    for facet in sort(collect(keys(data.optional)); by = string)
        optional_mean[facet] = _facet_mean_scores(scores,
            data.optional[facet],
            data.optional_levels[facet])
    end
    return (;
        mean_score = _mean_score(scores),
        category_proportions = _category_proportions(scores, data.category_levels),
        person_mean = _facet_mean_scores(scores, data.person, data.person_levels),
        rater_mean = _facet_mean_scores(scores, data.rater, data.rater_levels),
        item_mean = _facet_mean_scores(scores, data.item, data.item_levels),
        optional_mean,
    )
end

function _replicated_summaries(data::FacetData, replicated::AbstractMatrix{<:Integer})
    nrep = size(replicated, 1)
    ncategory = length(data.category_levels)
    nperson = length(data.person_levels)
    nrater = length(data.rater_levels)
    nitem = length(data.item_levels)
    mean_score = Vector{Float64}(undef, nrep)
    category_proportions = Matrix{Float64}(undef, nrep, ncategory)
    person_mean = Matrix{Float64}(undef, nrep, nperson)
    rater_mean = Matrix{Float64}(undef, nrep, nrater)
    item_mean = Matrix{Float64}(undef, nrep, nitem)
    optional_mean = Dict{Symbol,Matrix{Float64}}(
        facet => Matrix{Float64}(undef, nrep, length(data.optional_levels[facet]))
        for facet in sort(collect(keys(data.optional)); by = string)
    )

    for replication in 1:nrep
        summary = _predictive_summary(data, vec(replicated[replication, :]))
        mean_score[replication] = summary.mean_score
        category_proportions[replication, :] .= summary.category_proportions
        person_mean[replication, :] .= summary.person_mean
        rater_mean[replication, :] .= summary.rater_mean
        item_mean[replication, :] .= summary.item_mean
        for facet in keys(optional_mean)
            optional_mean[facet][replication, :] .= summary.optional_mean[facet]
        end
    end
    return (;
        mean_score,
        category_proportions,
        person_mean,
        rater_mean,
        item_mean,
        optional_mean,
    )
end

function _cell_mean_score(scores::AbstractVector{<:Integer},
        observations::AbstractVector{Int})
    isempty(observations) && return NaN
    total = 0.0
    @inbounds for observation in observations
        total += scores[observation]
    end
    return total / length(observations)
end

function _replicated_cell_mean_scores(replicated::AbstractMatrix{<:Integer},
        observations::AbstractVector{Int})
    means = Vector{Float64}(undef, size(replicated, 1))
    if isempty(observations)
        fill!(means, NaN)
        return means
    end
    @inbounds for replication in axes(replicated, 1)
        total = 0.0
        for observation in observations
            total += replicated[replication, observation]
        end
        means[replication] = total / length(observations)
    end
    return means
end

function _dff_cell_observations(data::FacetData,
        index_a::AbstractVector{Int},
        level_a::Int,
        index_b::AbstractVector{Int},
        level_b::Int)
    observations = Int[]
    for observation in 1:data.n
        if index_a[observation] == level_a && index_b[observation] == level_b
            push!(observations, observation)
        end
    end
    return observations
end

function _push_dff_predictive_group_rows!(rows::Vector{NamedTuple},
        data::FacetData,
        replicated::AbstractMatrix{<:Integer},
        term::Tuple{Symbol,Symbol})
    facet_a = _facet(data, term[1])
    facet_b = _facet(data, term[2])
    facet_a === nothing &&
        throw(ArgumentError("DFF term $(term) references unknown facet :$(term[1])"))
    facet_b === nothing &&
        throw(ArgumentError("DFF term $(term) references unknown facet :$(term[2])"))
    index_a, levels_a = facet_a
    index_b, levels_b = facet_b
    for level_a_index in eachindex(levels_a), level_b_index in eachindex(levels_b)
        observations = _dff_cell_observations(
            data,
            index_a,
            level_a_index,
            index_b,
            level_b_index,
        )
        level_a = levels_a[level_a_index]
        level_b = levels_b[level_b_index]
        push!(rows, (;
            statistic = :dff_cell_mean,
            level = (term = term, cell = (level_a, level_b)),
            facet_a = term[1],
            facet_b = term[2],
            level_a,
            level_b,
            n_observations = length(observations),
            observed = _cell_mean_score(data.score, observations),
            replicated = _replicated_cell_mean_scores(replicated, observations),
        ))
    end
    return rows
end

function _push_sparse_design_block_predictive_rows!(rows::Vector{NamedTuple},
        data::FacetData,
        replicated::AbstractMatrix{<:Integer})
    cells = Dict{Tuple{Int,Int,Int},Vector{Int}}()
    for observation in 1:data.n
        key = (data.person[observation], data.rater[observation], data.item[observation])
        push!(get!(cells, key, Int[]), observation)
    end
    ordered_keys = sort(collect(keys(cells)); by = key -> string((
        data.person_levels[key[1]],
        data.rater_levels[key[2]],
        data.item_levels[key[3]],
    )))
    for key in ordered_keys
        observations = cells[key]
        person = data.person_levels[key[1]]
        rater = data.rater_levels[key[2]]
        item = data.item_levels[key[3]]
        push!(rows, (;
            statistic = :sparse_design_block_mean,
            level = (person = person, rater = rater, item = item),
            block = :person_rater_item,
            person,
            rater,
            item,
            n_observations = length(observations),
            observed = _cell_mean_score(data.score, observations),
            replicated = _replicated_cell_mean_scores(replicated, observations),
        ))
    end
    return rows
end

function _predictive_grouped_summary(spec::FacetSpec,
        replicated::AbstractMatrix{<:Integer})
    data = spec.data
    rows = NamedTuple[]
    for term in sort(copy(spec.validation_bias_terms); by = string)
        _push_dff_predictive_group_rows!(rows, data, replicated, term)
    end
    n_dff_cells = length(rows)
    _push_sparse_design_block_predictive_rows!(rows, data, replicated)
    return (;
        schema = "bayesianmgmfrm.predictive_grouped_summary.v1",
        rows,
        n_dff_terms = length(spec.validation_bias_terms),
        n_dff_cells,
        n_sparse_design_blocks = length(rows) - n_dff_cells,
    )
end

function _check_prior_implication_controls(;
        min_category_probability::Real,
        prior_warning_probability::Real,
        wide_facet_range_fraction::Real)
    isfinite(min_category_probability) && 0 <= min_category_probability <= 1 ||
        throw(ArgumentError("min_category_probability must be finite and in [0, 1]"))
    isfinite(prior_warning_probability) && 0 < prior_warning_probability <= 1 ||
        throw(ArgumentError("prior_warning_probability must be finite and in (0, 1]"))
    isfinite(wide_facet_range_fraction) && wide_facet_range_fraction >= 0 ||
        throw(ArgumentError("wide_facet_range_fraction must be finite and non-negative"))
    return (;
        min_category_probability = Float64(min_category_probability),
        prior_warning_probability = Float64(prior_warning_probability),
        wide_facet_range_fraction = Float64(wide_facet_range_fraction),
    )
end

function _finite_range(values::AbstractVector{<:Real})
    finite = [Float64(value) for value in values if isfinite(value)]
    isempty(finite) && return NaN
    length(finite) == 1 && return 0.0
    return maximum(finite) - minimum(finite)
end

function _row_ranges(values::AbstractMatrix{<:Real})
    ranges = Vector{Float64}(undef, size(values, 1))
    for row in axes(values, 1)
        ranges[row] = _finite_range(@view values[row, :])
    end
    return ranges
end

function _prior_category_implication_rows(data::FacetData,
        replicated_summary,
        controls)
    rows = NamedTuple[]
    lower_probability, upper_probability = _interval_probabilities(0.9)
    for (index, category) in pairs(data.category_levels)
        replicated = @view replicated_summary.category_proportions[:, index]
        summary = _finite_draw_summary(replicated, lower_probability, upper_probability)
        probability_empty = count(==(0.0), replicated) / length(replicated)
        probability_below_min =
            count(<(controls.min_category_probability), replicated) / length(replicated)
        flag =
            probability_empty >= controls.prior_warning_probability ? :prior_category_nonuse :
            probability_below_min >= controls.prior_warning_probability ? :prior_category_sparse :
            :ok
        push!(rows, (;
            category,
            observed_proportion =
                _category_proportions(data.score, data.category_levels)[index],
            observed_empty =
                _category_proportions(data.score, data.category_levels)[index] == 0.0,
            replicated_mean_proportion = summary.mean,
            replicated_median_proportion = summary.median,
            replicated_lower_proportion = summary.lower,
            replicated_upper_proportion = summary.upper,
            interval_probability = 0.9,
            lower_probability,
            upper_probability,
            min_category_probability = controls.min_category_probability,
            probability_empty,
            probability_below_min_category_probability = probability_below_min,
            prior_warning_probability = controls.prior_warning_probability,
            n_replicates = length(replicated),
            flag,
        ))
    end
    return rows
end

function _prior_facet_range_row(facet::Symbol,
        levels,
        observed_means::AbstractVector{<:Real},
        replicated_means::AbstractMatrix{<:Real},
        score_range::Float64,
        controls)
    lower_probability, upper_probability = _interval_probabilities(0.9)
    ranges = _row_ranges(replicated_means)
    summary = _finite_draw_summary(ranges, lower_probability, upper_probability)
    wide_range_threshold = score_range * controls.wide_facet_range_fraction
    probability_wide_range = count(>=(wide_range_threshold), ranges) / length(ranges)
    return (;
        facet,
        n_levels = length(levels),
        observed_range = _finite_range(observed_means),
        replicated_mean_range = summary.mean,
        replicated_median_range = summary.median,
        replicated_lower_range = summary.lower,
        replicated_upper_range = summary.upper,
        interval_probability = 0.9,
        lower_probability,
        upper_probability,
        score_range,
        wide_facet_range_fraction = controls.wide_facet_range_fraction,
        wide_range_threshold,
        probability_wide_range,
        prior_warning_probability = controls.prior_warning_probability,
        n_replicates = length(ranges),
        flag = probability_wide_range >= controls.prior_warning_probability ?
            :prior_wide_facet_range : :ok,
    )
end

function _prior_facet_range_rows(data::FacetData,
        observed_summary,
        replicated_summary,
        controls)
    score_range = Float64(maximum(data.category_levels) - minimum(data.category_levels))
    rows = NamedTuple[]
    push!(rows, _prior_facet_range_row(:person,
        data.person_levels,
        observed_summary.person_mean,
        replicated_summary.person_mean,
        score_range,
        controls))
    push!(rows, _prior_facet_range_row(:rater,
        data.rater_levels,
        observed_summary.rater_mean,
        replicated_summary.rater_mean,
        score_range,
        controls))
    push!(rows, _prior_facet_range_row(:item,
        data.item_levels,
        observed_summary.item_mean,
        replicated_summary.item_mean,
        score_range,
        controls))
    for facet in sort(collect(keys(data.optional)); by = string)
        push!(rows, _prior_facet_range_row(facet,
            data.optional_levels[facet],
            observed_summary.optional_mean[facet],
            replicated_summary.optional_mean[facet],
            score_range,
            controls))
    end
    return rows
end

function _prior_category_use_summary(data::FacetData,
        replicated_summary,
        controls)
    used_by_replication = [
        count(>(0.0), @view replicated_summary.category_proportions[replication, :])
        for replication in axes(replicated_summary.category_proportions, 1)
    ]
    lower_probability, upper_probability = _interval_probabilities(0.9)
    summary = _finite_draw_summary(used_by_replication, lower_probability, upper_probability)
    n_categories = length(data.category_levels)
    probability_all_categories_used = count(==(n_categories), used_by_replication) /
        length(used_by_replication)
    probability_missing_any_category = 1 - probability_all_categories_used
    return (;
        observed_n_categories_used =
            count(>(0.0), _category_proportions(data.score, data.category_levels)),
        replicated_mean_n_categories_used = summary.mean,
        replicated_median_n_categories_used = summary.median,
        replicated_lower_n_categories_used = summary.lower,
        replicated_upper_n_categories_used = summary.upper,
        interval_probability = 0.9,
        lower_probability,
        upper_probability,
        n_categories,
        probability_all_categories_used,
        probability_missing_any_category,
        prior_warning_probability = controls.prior_warning_probability,
        n_replicates = length(used_by_replication),
        flag = probability_missing_any_category >= controls.prior_warning_probability ?
            :prior_category_collapse : :ok,
    )
end

function _prior_predictive_implication_diagnostics(data::FacetData,
        observed_summary,
        replicated_summary;
        min_category_probability::Real,
        prior_warning_probability::Real,
        wide_facet_range_fraction::Real)
    controls = _check_prior_implication_controls(;
        min_category_probability,
        prior_warning_probability,
        wide_facet_range_fraction)
    category_rows = _prior_category_implication_rows(
        data,
        replicated_summary,
        controls,
    )
    facet_range_rows = _prior_facet_range_rows(
        data,
        observed_summary,
        replicated_summary,
        controls,
    )
    category_use = _prior_category_use_summary(data, replicated_summary, controls)
    flag = any(row -> row.flag !== :ok, category_rows) ||
        any(row -> row.flag !== :ok, facet_range_rows) ||
        category_use.flag !== :ok ? :prior_implication_warning : :ok
    return (;
        schema = "bayesianmgmfrm.prior_predictive_implication_diagnostics.v1",
        flag,
        controls,
        category_use,
        category_rows,
        facet_range_rows,
    )
end

function _tail_probabilities(values::AbstractVector{<:Real}, observed::Real)
    obs = Float64(observed)
    vals = [Float64(value) for value in values if isfinite(value)]
    isempty(vals) && return (lower = NaN, upper = NaN, two_sided = NaN)
    if !isfinite(obs)
        return (lower = NaN, upper = NaN, two_sided = NaN)
    end
    lower = count(<=(obs), vals) / length(vals)
    upper = count(>=(obs), vals) / length(vals)
    return (;
        lower,
        upper,
        two_sided = min(1.0, 2 * min(lower, upper)),
    )
end

function _predictive_check_row(statistic::Symbol,
        level,
        observed::Real,
        replicated::AbstractVector{<:Real},
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64;
        metadata = NamedTuple())
    summary = _finite_draw_summary(replicated, lower_probability, upper_probability)
    tails = _tail_probabilities(replicated, observed)
    obs = Float64(observed)
    outside = isfinite(obs) &&
        (obs < summary.lower || obs > summary.upper)
    return merge((;
        statistic,
        level,
        observed = obs,
        replicated_mean = summary.mean,
        replicated_median = summary.median,
        replicated_lower = summary.lower,
        replicated_upper = summary.upper,
        interval_probability = Float64(interval),
        lower_probability,
        upper_probability,
        lower_tail_probability = tails.lower,
        upper_tail_probability = tails.upper,
        two_sided_tail_probability = tails.two_sided,
        n_replicates = count(value -> isfinite(Float64(value)), replicated),
        flag = outside ? :outside_interval : :ok,
    ), metadata)
end

function _require_predictive_check_fields(check)
    for field in (:observed, :replicated, :category_levels, :person_levels, :rater_levels, :item_levels, :optional_levels)
        hasproperty(check, field) ||
            throw(ArgumentError("predictive check object is missing .$field"))
    end
    return nothing
end

function _require_predictive_grouped_fields(check)
    hasproperty(check, :grouped) ||
        throw(ArgumentError("predictive check object is missing .grouped"))
    hasproperty(check.grouped, :rows) ||
        throw(ArgumentError("predictive check grouped object is missing .rows"))
    return nothing
end

function _predictive_grouped_row_metadata(row)
    if row.statistic === :dff_cell_mean
        return (;
            n_observations = row.n_observations,
            facet_a = row.facet_a,
            facet_b = row.facet_b,
            level_a = row.level_a,
            level_b = row.level_b,
        )
    elseif row.statistic === :sparse_design_block_mean
        return (;
            n_observations = row.n_observations,
            block = row.block,
            person = row.person,
            rater = row.rater,
            item = row.item,
        )
    end
    return (; n_observations = row.n_observations)
end

"""
    predictive_check_summary(check; interval = 0.9, include_grouped = false)

Summarize a `prior_predictive_check` or `posterior_predictive_check` result as
rows with observed values, replicated means, replicated intervals, and tail
probabilities. The current summary covers overall mean score, category
proportions, person-level mean scores, rater-level mean scores, item-level mean
scores, and optional facet mean scores. Set `include_grouped = true` to append
DFF-cell and observed sparse-design-block mean-score rows from checks generated
by current `prior_predictive_check` or `posterior_predictive_check` objects.
"""
function predictive_check_summary(check; interval::Real = 0.9,
        include_grouped::Bool = false)
    _require_predictive_check_fields(check)
    include_grouped && _require_predictive_grouped_fields(check)
    lower_probability, upper_probability = _interval_probabilities(interval)
    observed = check.observed
    replicated = check.replicated
    rows = NamedTuple[]

    push!(rows, _predictive_check_row(:mean_score, missing,
        observed.mean_score,
        replicated.mean_score,
        interval,
        lower_probability,
        upper_probability))

    for (index, level) in pairs(check.category_levels)
        push!(rows, _predictive_check_row(:category_proportion, level,
            observed.category_proportions[index],
            @view(replicated.category_proportions[:, index]),
            interval,
            lower_probability,
            upper_probability))
    end

    for (index, level) in pairs(check.person_levels)
        push!(rows, _predictive_check_row(:person_mean, level,
            observed.person_mean[index],
            @view(replicated.person_mean[:, index]),
            interval,
            lower_probability,
            upper_probability))
    end

    for (index, level) in pairs(check.rater_levels)
        push!(rows, _predictive_check_row(:rater_mean, level,
            observed.rater_mean[index],
            @view(replicated.rater_mean[:, index]),
            interval,
            lower_probability,
            upper_probability))
    end

    for (index, level) in pairs(check.item_levels)
        push!(rows, _predictive_check_row(:item_mean, level,
            observed.item_mean[index],
            @view(replicated.item_mean[:, index]),
            interval,
            lower_probability,
            upper_probability))
    end

    for facet in sort(collect(keys(check.optional_levels)); by = string)
        levels = check.optional_levels[facet]
        for (index, level) in pairs(levels)
            push!(rows, _predictive_check_row(Symbol(facet, :_mean), level,
                observed.optional_mean[facet][index],
                @view(replicated.optional_mean[facet][:, index]),
                interval,
                lower_probability,
                upper_probability))
        end
    end

    if include_grouped
        for row in check.grouped.rows
            push!(rows, _predictive_check_row(row.statistic,
                row.level,
                row.observed,
                row.replicated,
                interval,
                lower_probability,
                upper_probability;
                metadata = _predictive_grouped_row_metadata(row)))
        end
    end

    return rows
end

"""
    prior_predictive_check(spec_or_design; prior = MFRMPrior(), ndraws = 1000,
        rng = Random.default_rng(), min_category_probability = 0.01,
        prior_warning_probability = 0.95, wide_facet_range_fraction = 0.8)

Generate prior predictive replicated scores and compact observed-vs-replicated
summaries for the minimal MFRM design. The returned object includes the prior
parameter draws used to generate `replicated_scores` and prior-implication
diagnostics for category use and facet-score ranges. It also includes grouped
DFF-cell and observed sparse-design-block mean-score summaries for
`predictive_check_summary(...; include_grouped = true)`.
"""
function prior_predictive_check(design::FacetDesign;
        prior::MFRMPrior = MFRMPrior(),
        ndraws::Int = 1000,
        rng::AbstractRNG = Random.default_rng(),
        min_category_probability::Real = 0.01,
        prior_warning_probability::Real = 0.95,
        wide_facet_range_fraction::Real = 0.8)
    draws = _prior_parameter_draws(design, prior, ndraws, rng)
    replicated = _replicate_scores(design, draws, rng)
    data = design.spec.data
    observed = _predictive_summary(data, data.score)
    replicated_summary = _replicated_summaries(data, replicated)
    grouped = _predictive_grouped_summary(design.spec, replicated)
    implication_diagnostics = _prior_predictive_implication_diagnostics(
        data,
        observed,
        replicated_summary;
        min_category_probability,
        prior_warning_probability,
        wide_facet_range_fraction,
    )
    return (;
        observed,
        replicated = replicated_summary,
        grouped,
        replicated_scores = replicated,
        parameter_draws = draws,
        implication_diagnostics,
        category_levels = copy(data.category_levels),
        person_levels = copy(data.person_levels),
        rater_levels = copy(data.rater_levels),
        item_levels = copy(data.item_levels),
        optional_levels = Dict(facet => copy(levels) for (facet, levels) in data.optional_levels),
    )
end

prior_predictive_check(spec::FacetSpec; kwargs...) =
    prior_predictive_check(getdesign(spec); kwargs...)

"""
    posterior_predictive_check(fit::MFRMFit; ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())

Generate posterior predictive replicated scores and compact observed-vs-
replicated summaries for the minimal MFRM design. The summary currently covers
overall mean score, category proportions, person-level mean scores, rater-level
mean scores, item-level mean scores, optional facet mean scores, and grouped
DFF-cell and observed sparse-design-block mean-score rows for
`predictive_check_summary(...; include_grouped = true)`.
"""
function posterior_predictive_check(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    replicated = posterior_predict(fit; draw_indices = indices, rng)
    data = fit.design.spec.data
    observed = _predictive_summary(data, data.score)
    replicated_summary = _replicated_summaries(data, replicated)
    grouped = _predictive_grouped_summary(fit.design.spec, replicated)
    return (;
        observed,
        replicated = replicated_summary,
        grouped,
        replicated_scores = replicated,
        draw_indices = indices,
        category_levels = copy(data.category_levels),
        person_levels = copy(data.person_levels),
        rater_levels = copy(data.rater_levels),
        item_levels = copy(data.item_levels),
        optional_levels = Dict(facet => copy(levels) for (facet, levels) in data.optional_levels),
    )
end

function posterior_predictive_check(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    replicated = posterior_predict(fit; draw_indices = indices, rng)
    data = fit.design.spec.data
    observed = _predictive_summary(data, data.score)
    replicated_summary = _replicated_summaries(data, replicated)
    grouped = _predictive_grouped_summary(fit.design.spec, replicated)
    return (;
        observed,
        replicated = replicated_summary,
        grouped,
        replicated_scores = replicated,
        draw_indices = indices,
        category_levels = copy(data.category_levels),
        person_levels = copy(data.person_levels),
        rater_levels = copy(data.rater_levels),
        item_levels = copy(data.item_levels),
        optional_levels = Dict(facet => copy(levels) for (facet, levels) in data.optional_levels),
    )
end

function posterior_predictive_check(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    replicated = posterior_predict(fit; draw_indices = indices, rng)
    data = fit.design.spec.data
    observed = _predictive_summary(data, data.score)
    replicated_summary = _replicated_summaries(data, replicated)
    grouped = _predictive_grouped_summary(fit.design.spec, replicated)
    return (;
        observed,
        replicated = replicated_summary,
        grouped,
        replicated_scores = replicated,
        draw_indices = indices,
        category_levels = copy(data.category_levels),
        person_levels = copy(data.person_levels),
        rater_levels = copy(data.rater_levels),
        item_levels = copy(data.item_levels),
        optional_levels = Dict(facet => copy(levels) for (facet, levels) in data.optional_levels),
    )
end

function _check_simulation_output(output::Symbol)
    output in (:data, :table, :scores) ||
        throw(ArgumentError("output must be :data, :table, or :scores"))
    return output
end

function _simulated_response_table(data::FacetData, scores::AbstractVector{<:Integer})
    names = Symbol[:person, :rater, :item, :score]
    values = Any[
        [data.person_levels[index] for index in data.person],
        [data.rater_levels[index] for index in data.rater],
        [data.item_levels[index] for index in data.item],
        collect(Int, scores),
    ]
    for facet in sort(collect(keys(data.optional)); by = string)
        push!(names, facet)
        push!(values, [data.optional_levels[facet][index] for index in data.optional[facet]])
    end
    return NamedTuple{Tuple(names)}(Tuple(values))
end

function _facet_data_with_scores(data::FacetData, scores::AbstractVector{<:Integer})
    length(scores) == data.n ||
        throw(ArgumentError("scores has length $(length(scores)); expected $(data.n)"))
    category_index = Dict(level => index for (index, level) in pairs(data.category_levels))
    all(score -> haskey(category_index, score), scores) ||
        throw(ArgumentError("scores contain values outside the design category levels"))
    return FacetData(
        data.n,
        copy(data.person),
        copy(data.rater),
        copy(data.item),
        collect(Int, scores),
        [category_index[score] for score in scores],
        copy(data.person_levels),
        copy(data.rater_levels),
        copy(data.item_levels),
        copy(data.category_levels),
        Dict(facet => copy(index) for (facet, index) in data.optional),
        Dict(facet => copy(levels) for (facet, levels) in data.optional_levels),
        data.columns,
    )
end

function _check_simulation_parameter_space(parameter_space::Symbol)
    parameter_space in (:direct, :raw) ||
        throw(ArgumentError("parameter_space must be :direct or :raw"))
    return parameter_space
end

function _check_finite_parameter_values(params::AbstractVector, caller::AbstractString)
    all(value -> isfinite(Float64(value)), params) ||
        throw(ArgumentError("$caller parameter vector contains non-finite values"))
    return params
end

function _generalized_simulation_direct_params(design::FacetDesign,
        params::AbstractVector,
        parameter_space::Symbol,
        caller::AbstractString)
    _check_finite_parameter_values(params, caller)
    if design.spec.family === :gmfrm && design.spec.estimation_status === :specified_only
        direct = parameter_space === :raw ?
            _gmfrm_source_constrained_params_from_unconstrained(design, params) :
            collect(Float64, params)
        _gmfrm_direct_draws_for_prediction(design, reshape(direct, 1, :), caller)
        return direct
    elseif design.spec.family === :mgmfrm && design.spec.estimation_status === :specified_only
        direct = parameter_space === :raw ?
            _mgmfrm_source_constrained_params_from_unconstrained(design, params) :
            collect(Float64, params)
        _mgmfrm_direct_draws_for_prediction(design, reshape(direct, 1, :), caller)
        return direct
    end
    throw(ArgumentError(
        "$caller currently supports fit-supported MFRM/RSM/PCM designs and " *
        "specified-only GMFRM/MGMFRM preview designs",
    ))
end

"""
    simulate_responses(spec_or_design, params; rng = Random.default_rng(),
        output = :data, parameter_space = :direct, preview = false)

Simulate one response dataset from the current fit-supported MFRM/RSM/PCM
likelihood, or from a specified-only GMFRM/MGMFRM preview design for internal
simulation/recovery scaffolding. MFRM/RSM/PCM designs use direct identified
parameters. GMFRM/MGMFRM previews accept constrained direct parameters by
default, or raw fit-ready candidate parameters with `parameter_space = :raw`.
`output = :data` returns a `FacetData` object with the same
person/rater/item/optional facet structure and category levels as the original
design. Use `output = :table` for a column-oriented named tuple, or
`output = :scores` for just the simulated score vector.
"""
function simulate_responses(design::FacetDesign,
        params::AbstractVector;
        rng::AbstractRNG = Random.default_rng(),
        output::Symbol = :data,
        parameter_space::Symbol = :direct)
    checked_output = _check_simulation_output(output)
    checked_space = _check_simulation_parameter_space(parameter_space)
    if design.spec.family === :mfrm && design.spec.estimation_status === :fit_supported
        checked_space === :direct ||
            throw(ArgumentError("fit-supported MFRM/RSM/PCM simulation only accepts parameter_space = :direct"))
        _check_parameter_vector(design, params)
        draws = reshape(collect(Float64, params), 1, :)
        scores = vec(_replicate_scores(design, draws, rng))
    elseif design.spec.family === :gmfrm && design.spec.estimation_status === :specified_only
        direct = _generalized_simulation_direct_params(
            design,
            params,
            checked_space,
            "simulate_responses",
        )
        scores = vec(_replicate_scores_gmfrm_direct(
            design,
            reshape(direct, 1, :),
            rng,
            "simulate_responses",
        ))
    elseif design.spec.family === :mgmfrm && design.spec.estimation_status === :specified_only
        direct = _generalized_simulation_direct_params(
            design,
            params,
            checked_space,
            "simulate_responses",
        )
        scores = vec(_replicate_scores_mgmfrm_direct(
            design,
            reshape(direct, 1, :),
            rng,
            "simulate_responses",
        ))
    else
        throw(ArgumentError(
            "simulate_responses currently supports fit-supported MFRM/RSM/PCM " *
            "designs and specified-only GMFRM/MGMFRM preview designs",
        ))
    end
    checked_output === :scores && return scores
    checked_output === :table && return _simulated_response_table(design.spec.data, scores)
    return _facet_data_with_scores(design.spec.data, scores)
end

simulate_responses(spec::FacetSpec,
        params::AbstractVector;
        preview::Bool = false,
        kwargs...) =
    simulate_responses(getdesign(spec; preview), params; kwargs...)

function _check_recovery_inputs(parameter_names::AbstractVector{String},
        draws::AbstractMatrix,
        truth::AbstractVector,
        caller::AbstractString)
    nparams = length(parameter_names)
    size(draws, 1) >= 1 ||
        throw(ArgumentError("$caller requires at least one draw"))
    size(draws, 2) == nparams ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $nparams"))
    length(truth) == nparams ||
        throw(ArgumentError("truth has length $(length(truth)); expected $nparams"))
    all(value -> isfinite(Float64(value)), draws) ||
        throw(ArgumentError("draws contain non-finite values"))
    all(value -> isfinite(Float64(value)), truth) ||
        throw(ArgumentError("truth contains non-finite values"))
    return nothing
end

function _check_recovery_inputs(design::FacetDesign,
        draws::AbstractMatrix,
        truth::AbstractVector,
        caller::AbstractString = "parameter recovery")
    return _check_recovery_inputs(design.parameter_names, draws, truth, caller)
end

function _parameter_block_name(blocks, index::Int)
    for block in sort(collect(keys(blocks)); by = string)
        _in_range(blocks[block], index) && return block
    end
    return :unknown
end

_parameter_block_name(design::FacetDesign, index::Int) =
    _parameter_block_name(design.blocks, index)

function _block_ranges_from_value_rows(rows)
    blocks = Dict{Symbol,UnitRange{Int}}()
    for row in rows
        Int(row.n_parameters) == 0 && continue
        blocks[row.block] = Int(row.first_parameter):Int(row.last_parameter)
    end
    return blocks
end

function _check_recovery_parameter_space(parameter_space::Symbol)
    parameter_space in (:direct, :raw) ||
        throw(ArgumentError("parameter_space must be :direct or :raw"))
    return parameter_space
end

function _recovery_metadata(;
        model_family::Symbol,
        parameter_space::Symbol,
        density_space::Symbol,
        scope,
        fit_ready::Bool,
        public_fit::Bool,
        experimental_public::Bool,
        guarded_local_fit::Bool)
    return (;
        model_family,
        parameter_space,
        density_space,
        scope,
        fit_ready,
        public_fit,
        experimental_public,
        guarded_local_fit,
    )
end

function _parameter_recovery_rows(parameter_names::AbstractVector{String},
        blocks,
        draws::AbstractMatrix,
        truth::AbstractVector;
        interval::Real,
        metadata)
    lower_probability, upper_probability = _interval_probabilities(interval)
    _check_recovery_inputs(parameter_names, draws, truth, "parameter_recovery")
    rows = NamedTuple[]
    for index in 1:length(parameter_names)
        vals = Float64.(draws[:, index])
        sorted = sort(vals)
        posterior_mean = _column_mean(vals)
        posterior_sd = _column_sd(vals, posterior_mean)
        posterior_median = _quantile_sorted(sorted, 0.5)
        posterior_lower = _quantile_sorted(sorted, lower_probability)
        posterior_upper = _quantile_sorted(sorted, upper_probability)
        true_value = Float64(truth[index])
        bias = posterior_mean - true_value
        relative_bias = iszero(true_value) ? NaN : bias / abs(true_value)
        covered = posterior_lower <= true_value <= posterior_upper
        push!(rows, merge((;
            parameter = parameter_names[index],
            parameter_index = index,
            block = _parameter_block_name(blocks, index),
            true_value,
            posterior_mean,
            posterior_sd,
            posterior_median,
            posterior_lower,
            posterior_upper,
            interval_probability = Float64(interval),
            lower_probability,
            upper_probability,
            bias,
            absolute_bias = abs(bias),
            squared_error = bias * bias,
            relative_bias,
            interval_width = posterior_upper - posterior_lower,
            covered,
            flag = covered ? :covered : :missed_interval,
        ), metadata))
    end
    return rows
end

function _design_recovery_metadata(design::FacetDesign, parameter_space::Symbol)
    if design.spec.family === :mfrm && design.spec.estimation_status === :fit_supported
        parameter_space === :direct ||
            throw(ArgumentError("fit-supported MFRM/RSM/PCM recovery only accepts parameter_space = :direct"))
        return _recovery_metadata(;
            model_family = :mfrm,
            parameter_space = :direct,
            density_space = :constrained_direct,
            scope = _spec_scope(design.spec.family, design.spec.estimation_status),
            fit_ready = true,
            public_fit = true,
            experimental_public = false,
            guarded_local_fit = false,
        )
    elseif design.spec.family === :gmfrm && design.spec.estimation_status === :specified_only
        return _recovery_metadata(;
            model_family = :gmfrm,
            parameter_space,
            density_space = parameter_space === :direct ? :constrained_direct : :raw_unconstrained,
            scope = :scalar_gmfrm_fit_ready_candidate,
            fit_ready = false,
            public_fit = false,
            experimental_public = true,
            guarded_local_fit = false,
        )
    elseif design.spec.family === :mgmfrm && design.spec.estimation_status === :specified_only
        return _recovery_metadata(;
            model_family = :mgmfrm,
            parameter_space,
            density_space = parameter_space === :direct ? :constrained_direct : :raw_unconstrained,
            scope = :minimal_confirmatory_mgmfrm_candidate,
            fit_ready = true,
            public_fit = true,
            experimental_public = true,
            guarded_local_fit = true,
        )
    end
    throw(ArgumentError(
        "parameter_recovery currently supports fit-supported MFRM/RSM/PCM " *
        "designs and specified-only GMFRM/MGMFRM preview designs",
    ))
end

function _design_recovery_layout(design::FacetDesign, parameter_space::Symbol)
    metadata = _design_recovery_metadata(design, parameter_space)
    if design.spec.family === :mfrm
        return (; parameter_names = design.parameter_names, blocks = design.blocks, metadata)
    elseif parameter_space === :direct
        return (; parameter_names = design.parameter_names, blocks = design.blocks, metadata)
    elseif design.spec.family === :gmfrm
        blueprint = _gmfrm_fit_ready_candidate_blueprint(design)
        return (; parameter_names = blueprint.parameter_names, blocks = blueprint.blocks, metadata)
    elseif design.spec.family === :mgmfrm
        blueprint = _mgmfrm_fit_ready_candidate_blueprint(design)
        return (; parameter_names = blueprint.parameter_names, blocks = blueprint.blocks, metadata)
    end
    throw(ArgumentError("unsupported recovery layout"))
end

function _fit_recovery_layout(fit::GMFRMFit, parameter_space::Symbol)
    metadata = _recovery_metadata(;
        model_family = :gmfrm,
        parameter_space,
        density_space = parameter_space === :direct ? :constrained_direct : :raw_unconstrained,
        scope = :scalar_gmfrm_fit_ready_candidate,
        fit_ready = true,
        public_fit = true,
        experimental_public = true,
        guarded_local_fit = false,
    )
    if parameter_space === :direct
        return (;
            parameter_names = fit.diagnostic_surface.direct_parameter_names,
            blocks = _block_ranges_from_value_rows(fit.diagnostic_surface.direct_blocks),
            draws = fit.direct_draws,
            metadata,
        )
    end
    return (;
        parameter_names = fit.diagnostic_surface.raw_parameter_names,
        blocks = _block_ranges_from_value_rows(fit.diagnostic_surface.raw_blocks),
        draws = fit.draws,
        metadata,
    )
end

function _fit_recovery_layout(fit::MGMFRMFit, parameter_space::Symbol)
    metadata = _recovery_metadata(;
        model_family = :mgmfrm,
        parameter_space,
        density_space = parameter_space === :direct ? :constrained_direct : :raw_unconstrained,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        fit_ready = true,
        public_fit = true,
        experimental_public = true,
        guarded_local_fit = true,
    )
    if parameter_space === :direct
        return (;
            parameter_names = fit.diagnostic_surface.direct_parameter_names,
            blocks = _block_ranges_from_value_rows(fit.diagnostic_surface.direct_blocks),
            draws = fit.direct_draws,
            metadata,
        )
    end
    return (;
        parameter_names = fit.diagnostic_surface.raw_parameter_names,
        blocks = _block_ranges_from_value_rows(fit.diagnostic_surface.raw_blocks),
        draws = fit.draws,
        metadata,
    )
end

"""
    parameter_recovery(fit::MFRMFit, truth; interval = 0.95)
    parameter_recovery(fit::GMFRMFit, truth; interval = 0.95,
        parameter_space = :direct)
    parameter_recovery(design::FacetDesign, draws, truth; interval = 0.95,
        parameter_space = :direct)

Compare posterior draws with known simulation truth. Rows include the true
value, posterior mean/median/interval, bias, absolute bias, squared error,
relative bias, interval width, and whether the posterior interval covers the
true value. MFRM/RSM/PCM rows use the fit-supported direct parameterization.
GMFRM/MGMFRM fit objects and preview designs use direct constrained parameters
by default; pass `parameter_space = :raw` to evaluate raw fit-ready candidate
coordinates.
"""
function parameter_recovery(design::FacetDesign,
        draws::AbstractMatrix,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct)
    checked_space = _check_recovery_parameter_space(parameter_space)
    layout = _design_recovery_layout(design, checked_space)
    if design.spec.family === :gmfrm && checked_space === :direct
        _gmfrm_direct_draws_for_prediction(design, draws, "parameter_recovery")
    elseif design.spec.family === :mgmfrm && checked_space === :direct
        _mgmfrm_direct_draws_for_prediction(design, draws, "parameter_recovery")
    end
    return _parameter_recovery_rows(
        layout.parameter_names,
        layout.blocks,
        draws,
        truth;
        interval,
        metadata = layout.metadata,
    )
end

parameter_recovery(fit::MFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct) =
    parameter_recovery(fit.design, fit.draws, truth; interval, parameter_space)

function parameter_recovery(fit::GMFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct)
    checked_space = _check_recovery_parameter_space(parameter_space)
    layout = _fit_recovery_layout(fit, checked_space)
    return _parameter_recovery_rows(
        layout.parameter_names,
        layout.blocks,
        layout.draws,
        truth;
        interval,
        metadata = layout.metadata,
    )
end

function parameter_recovery(fit::MGMFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct)
    checked_space = _check_recovery_parameter_space(parameter_space)
    layout = _fit_recovery_layout(fit, checked_space)
    return _parameter_recovery_rows(
        layout.parameter_names,
        layout.blocks,
        layout.draws,
        truth;
        interval,
        metadata = layout.metadata,
    )
end

function _recovery_group_key(row, by::Symbol)
    by === :all && return :all
    hasproperty(row, by) ||
        throw(ArgumentError("recovery rows do not contain grouping field :$by"))
    return getproperty(row, by)
end

"""
    parameter_recovery_summary(recovery_rows; by = :block)
    parameter_recovery_summary(fit::MFRMFit, truth; interval = 0.95,
        by = :block)

Aggregate parameter-recovery rows by block, or use `by = :all` for a single
overall row. Summaries include mean bias, mean absolute error, RMSE, median
absolute error, max absolute error, interval coverage, and mean interval width.
"""
function parameter_recovery_summary(recovery_rows; by::Symbol = :block)
    isempty(recovery_rows) &&
        throw(ArgumentError("recovery_rows must not be empty"))
    groups = Dict{Any,Vector{Any}}()
    order = Any[]
    for row in recovery_rows
        key = _recovery_group_key(row, by)
        if !haskey(groups, key)
            groups[key] = Any[]
            push!(order, key)
        end
        push!(groups[key], row)
    end

    rows = NamedTuple[]
    for key in order
        group_rows = groups[key]
        n = length(group_rows)
        biases = [Float64(row.bias) for row in group_rows]
        absolute_biases = [Float64(row.absolute_bias) for row in group_rows]
        squared_errors = [Float64(row.squared_error) for row in group_rows]
        widths = [Float64(row.interval_width) for row in group_rows]
        n_covered = count(row -> row.covered, group_rows)
        nominal = Float64(group_rows[1].interval_probability)
        sorted_abs = sort(absolute_biases)
        push!(rows, (;
            by,
            group = key,
            n_parameters = n,
            mean_bias = sum(biases) / n,
            mean_absolute_error = sum(absolute_biases) / n,
            rmse = sqrt(sum(squared_errors) / n),
            median_absolute_error = _quantile_sorted(sorted_abs, 0.5),
            max_absolute_error = maximum(absolute_biases),
            coverage_rate = n_covered / n,
            nominal_coverage = nominal,
            coverage_gap = n_covered / n - nominal,
            mean_interval_width = sum(widths) / n,
            n_covered,
            flag = n_covered / n >= nominal ? :ok : :coverage_below_nominal,
        ))
    end
    return rows
end

parameter_recovery_summary(fit::MFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        by::Symbol = :block,
        parameter_space::Symbol = :direct) =
    parameter_recovery_summary(
        parameter_recovery(fit, truth; interval, parameter_space);
        by)

parameter_recovery_summary(fit::GMFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        by::Symbol = :block,
        parameter_space::Symbol = :direct) =
    parameter_recovery_summary(
        parameter_recovery(fit, truth; interval, parameter_space);
        by)

parameter_recovery_summary(fit::MGMFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        by::Symbol = :block,
        parameter_space::Symbol = :direct) =
    parameter_recovery_summary(
        parameter_recovery(fit, truth; interval, parameter_space);
        by)

"""
    parameter_recovery_plot_data(recovery_rows)
    parameter_recovery_plot_data(fit::MFRMFit, truth; interval = 0.95)

Return plotting-ready rows for a parameter-recovery scatter/interval plot
without depending on a plotting package. Suggested mappings are
`x = true_value`, `y = estimate`, and `ymin/ymax = interval_lower/interval_upper`;
the diagonal reference line is `y = x`.
"""
function parameter_recovery_plot_data(recovery_rows)
    return [(;
        parameter = row.parameter,
        parameter_index = row.parameter_index,
        block = row.block,
        true_value = row.true_value,
        estimate = row.posterior_mean,
        interval_lower = row.posterior_lower,
        interval_upper = row.posterior_upper,
        error = row.bias,
        absolute_error = row.absolute_bias,
        covered = row.covered,
        flag = row.flag,
        reference = row.true_value,
    ) for row in recovery_rows]
end

parameter_recovery_plot_data(fit::MFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct) =
    parameter_recovery_plot_data(
        parameter_recovery(fit, truth; interval, parameter_space))

parameter_recovery_plot_data(fit::GMFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct) =
    parameter_recovery_plot_data(
        parameter_recovery(fit, truth; interval, parameter_space))

parameter_recovery_plot_data(fit::MGMFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct) =
    parameter_recovery_plot_data(
        parameter_recovery(fit, truth; interval, parameter_space))

const _DEFAULT_SIMULATION_GRID_REQUIRED_AXES = (
    :density,
    :anchor_size,
    :ratings_per_target,
    :category_pathology,
    :rater_noise,
    :dff,
    :dimensionality,
    :misspecification,
)

function _simulation_axis_tuple(values, name::Symbol)
    out = if values isa Symbol || values isa AbstractString ||
            values isa Number || values isa Bool
        (values,)
    else
        Tuple(values)
    end
    isempty(out) &&
        throw(ArgumentError("simulation grid axis :$name must contain at least one value"))
    return out
end

function _simulation_integer_axis(values, name::Symbol; minimum::Int = 1)
    axis = _simulation_axis_tuple(values, name)
    out = Int[]
    for value in axis
        value isa Integer ||
            throw(ArgumentError("simulation grid axis :$name must contain integers"))
        Int(value) >= minimum ||
            throw(ArgumentError("simulation grid axis :$name values must be >= $minimum"))
        push!(out, Int(value))
    end
    return Tuple(out)
end

function _simulation_symbol_axis(values, name::Symbol)
    axis = _simulation_axis_tuple(values, name)
    out = Symbol[]
    for value in axis
        value isa Symbol ||
            throw(ArgumentError("simulation grid axis :$name must contain Symbols"))
        push!(out, value)
    end
    return Tuple(out)
end

function _simulation_positive_integer(value::Integer, name::Symbol; minimum::Int = 1)
    Int(value) >= minimum ||
        throw(ArgumentError("$name must be >= $minimum"))
    return Int(value)
end

function _simulation_density_target(density)
    density === :sparse && return 0.15
    density === :moderate && return 0.50
    density === :near_complete && return 0.90
    if density isa Real
        value = Float64(density)
        isfinite(value) && 0 < value <= 1 ||
            throw(ArgumentError("numeric density values must be finite and in (0, 1]"))
        return value
    end
    throw(ArgumentError("density values must be :sparse, :moderate, :near_complete, or numeric proportions"))
end

function _simulation_rater_noise_sd(noise)
    noise === :low && return 0.25
    noise === :moderate && return 0.75
    noise === :high && return 1.50
    if noise isa Real
        value = Float64(noise)
        isfinite(value) && value >= 0 ||
            throw(ArgumentError("numeric rater_noise values must be finite and nonnegative"))
        return value
    end
    throw(ArgumentError("rater_noise values must be :low, :moderate, :high, or numeric standard deviations"))
end

_simulation_axis_active(value, inactive::Tuple) =
    !(value in inactive)

function _simulation_validation_focus(density, anchor_size::Int,
        category_pathology, rater_noise, dff, dimensionality::Int,
        misspecification)
    focus = Symbol[]
    density_target = _simulation_density_target(density)
    density_target <= 0.25 && push!(focus, :connectedness_and_sparse_cells)
    anchor_size > 0 && push!(focus, :anchor_linking)
    _simulation_axis_active(category_pathology, (:none, :balanced)) &&
        push!(focus, :category_pathology)
    _simulation_rater_noise_sd(rater_noise) >= 1.0 && push!(focus, :rater_noise)
    _simulation_axis_active(dff, (:none, :absent, false)) &&
        push!(focus, :dff_decision_stability)
    dimensionality > 1 && push!(focus, :multidimensional_gauge)
    _simulation_axis_active(misspecification, (:none, :well_specified, false)) &&
        push!(focus, :misspecification)
    isempty(focus) && push!(focus, :baseline_recovery)
    return Tuple(focus)
end

function _simulation_fit_surface(dimensionality::Int, misspecification)
    if dimensionality > 1
        return :guarded_mgmfrm_preview
    elseif _simulation_axis_active(misspecification, (:none, :well_specified, false))
        return :public_mfrm_baseline_or_guarded_gmfrm_comparison
    end
    return :public_mfrm_baseline
end

"""
    simulation_grid(; densities = (:sparse, :moderate, :near_complete),
        anchor_sizes = (0, 2, 5), ratings_per_target = (1, 2, 4),
        category_pathologies = (:none, :skipped_middle, :top_set),
        rater_noise = (:low, :moderate, :high), dff = (:none, :rater_by_group),
        dimensionalities = (1, 2),
        misspecifications = (:none, :wrong_thresholds, :omitted_dff),
        repetitions = 1, base_seed = 20260620, grid_id = "default",
        n_persons = 48, n_items = 12, n_raters = 6, n_categories = 4)

Return predeclared simulation-study rows that cross sparse-to-near-complete
design density, anchor size, ratings per target, category pathologies, rater
noise, DFF patterns, dimensionality, and misspecification. Rows are planning
metadata for reproducible simulation/recovery studies; this helper does not
simulate responses, fit models, or evaluate claims. Use the rows with
[`simulate_responses`](@ref), [`parameter_recovery`](@ref), calibration,
predictive-check, and model-comparison helpers when executing a study.
"""
function simulation_grid(; densities = (:sparse, :moderate, :near_complete),
        anchor_sizes = (0, 2, 5),
        ratings_per_target = (1, 2, 4),
        category_pathologies = (:none, :skipped_middle, :top_set),
        rater_noise = (:low, :moderate, :high),
        dff = (:none, :rater_by_group),
        dimensionalities = (1, 2),
        misspecifications = (:none, :wrong_thresholds, :omitted_dff),
        repetitions::Integer = 1,
        base_seed::Integer = 20260620,
        grid_id::AbstractString = "default",
        n_persons::Integer = 48,
        n_items::Integer = 12,
        n_raters::Integer = 6,
        n_categories::Integer = 4)
    density_axis = _simulation_axis_tuple(densities, :density)
    anchor_axis = _simulation_integer_axis(anchor_sizes, :anchor_size; minimum = 0)
    ratings_axis = _simulation_integer_axis(ratings_per_target, :ratings_per_target)
    category_axis = _simulation_symbol_axis(category_pathologies, :category_pathology)
    noise_axis = _simulation_axis_tuple(rater_noise, :rater_noise)
    dff_axis = _simulation_axis_tuple(dff, :dff)
    dimensionality_axis =
        _simulation_integer_axis(dimensionalities, :dimensionality)
    misspecification_axis =
        _simulation_axis_tuple(misspecifications, :misspecification)
    checked_repetitions =
        _simulation_positive_integer(repetitions, :repetitions)
    checked_persons = _simulation_positive_integer(n_persons, :n_persons)
    checked_items = _simulation_positive_integer(n_items, :n_items)
    checked_raters = _simulation_positive_integer(n_raters, :n_raters)
    checked_categories = _simulation_positive_integer(n_categories, :n_categories; minimum = 2)
    all(rating -> rating <= checked_raters, ratings_axis) ||
        throw(ArgumentError("ratings_per_target values cannot exceed n_raters"))

    target_units = checked_persons * checked_items
    max_ratings = target_units * checked_raters
    rows = NamedTuple[]
    scenario_index = 0
    for density in density_axis, anchor_size in anchor_axis,
            ratings in ratings_axis, category_pathology in category_axis,
            noise in noise_axis, dff_pattern in dff_axis,
            dimensionality in dimensionality_axis,
            misspecification in misspecification_axis
        scenario_index += 1
        density_target = _simulation_density_target(density)
        planned_density = ratings / checked_raters
        planned_n_ratings = target_units * ratings
        validation_focus = _simulation_validation_focus(
            density,
            anchor_size,
            category_pathology,
            noise,
            dff_pattern,
            dimensionality,
            misspecification,
        )
        for replication in 1:checked_repetitions
            row_index = length(rows) + 1
            push!(rows, (;
                schema = "bayesianmgmfrm.simulation_grid.v1",
                object = :simulation_grid_row,
                grid_id = String(grid_id),
                row_index,
                scenario_index,
                replication,
                seed = Int(base_seed) + row_index - 1,
                n_persons = checked_persons,
                n_items = checked_items,
                n_raters = checked_raters,
                n_categories = checked_categories,
                target_units,
                max_ratings,
                planned_n_ratings,
                density,
                density_target,
                planned_density,
                density_gap = planned_density - density_target,
                anchor_size,
                ratings_per_target = ratings,
                category_pathology,
                rater_noise = noise,
                rater_noise_sd = _simulation_rater_noise_sd(noise),
                dff = dff_pattern,
                dff_active = _simulation_axis_active(dff_pattern, (:none, :absent, false)),
                dimensionality,
                misspecification,
                misspecified =
                    _simulation_axis_active(misspecification, (:none, :well_specified, false)),
                validation_focus,
                fit_surface = _simulation_fit_surface(dimensionality, misspecification),
                simulation_status = :predeclared_not_run,
                caveat = :simulation_grid_not_runner_or_evidence,
                next_gate = :run_predeclared_grid_and_apply_falsification_rules,
            ))
        end
    end
    return rows
end

function _simulation_grid_axis(axis::Symbol)
    axis in (:density, :design_density) && return :density
    axis in (:anchor, :anchors, :anchor_size) && return :anchor_size
    axis in (:ratings, :ratings_per_target, :ratings_per_target_unit) &&
        return :ratings_per_target
    axis in (:category, :category_pathology, :category_pathologies) &&
        return :category_pathology
    axis in (:noise, :rater_noise) && return :rater_noise
    axis in (:dff, :dff_pattern, :dff_effects) && return :dff
    axis in (:dimensions, :dimensionality) && return :dimensionality
    axis in (:misspecification, :misspecifications, :model_misspecification) &&
        return :misspecification
    return axis
end

function _simulation_grid_axis_tuple(axes)
    out = Symbol[]
    for axis in axes
        axis isa Symbol ||
            throw(ArgumentError("simulation grid axes must be Symbols"))
        canonical = _simulation_grid_axis(axis)
        canonical in out || push!(out, canonical)
    end
    return Tuple(out)
end

_simulation_grid_axis_tuple(axis::Symbol) = (_simulation_grid_axis(axis),)

function _simulation_grid_axis_summary(axis::Symbol, rows::AbstractVector)
    values = Any[]
    for row in rows
        hasproperty(row, axis) || continue
        push!(values, getproperty(row, axis))
    end
    unique_values = _sensitivity_unique_tuple(values)
    present = !isempty(values)
    status = !present ? :missing : length(unique_values) >= 2 ? :varied : :single_value
    return (;
        axis,
        present,
        status,
        n_values = length(unique_values),
        values = unique_values,
    )
end

"""
    simulation_grid_summary(rows; required_axes =
        (:density, :anchor_size, :ratings_per_target, :category_pathology,
         :rater_noise, :dff, :dimensionality, :misspecification))

Summarize whether predeclared simulation-grid rows cover the default critical axes
for sparse Bayesian MFRM/GMFRM/MGMFRM validation. The summary reports missing
required axes, single-value axes, varied axes, row/scenario counts, and the
repetition/seed envelope. It is a coverage check for a planned grid, not
evidence that the grid has been run.
"""
function simulation_grid_summary(rows::AbstractVector;
        required_axes = _DEFAULT_SIMULATION_GRID_REQUIRED_AXES)
    isempty(rows) &&
        throw(ArgumentError("at least one simulation grid row is required"))
    for row in rows
        row isa NamedTuple ||
            throw(ArgumentError("simulation grid summary expects NamedTuple rows"))
    end
    checked_required = _simulation_grid_axis_tuple(required_axes)
    axis_rows = [_simulation_grid_axis_summary(axis, rows)
        for axis in checked_required]
    missing_required_axes = Tuple(row.axis for row in axis_rows
        if row.status === :missing)
    single_value_required_axes = Tuple(row.axis for row in axis_rows
        if row.status === :single_value)
    varied_required_axes = Tuple(row.axis for row in axis_rows
        if row.status === :varied)
    scenario_values = _sensitivity_unique_tuple(
        hasproperty(row, :scenario_index) ? row.scenario_index : missing
        for row in rows)
    repetition_values = _sensitivity_unique_tuple(
        hasproperty(row, :replication) ? row.replication : missing
        for row in rows)
    seed_values = [Int(row.seed) for row in rows if hasproperty(row, :seed)]

    return (;
        schema = "bayesianmgmfrm.simulation_grid_summary.v1",
        object = :simulation_grid_summary,
        required_axes = checked_required,
        n_rows = length(rows),
        n_scenarios = length(scenario_values),
        n_repetitions = length(repetition_values),
        first_seed = isempty(seed_values) ? missing : minimum(seed_values),
        last_seed = isempty(seed_values) ? missing : maximum(seed_values),
        missing_required_axes,
        single_value_required_axes,
        varied_required_axes,
        axis_rows = Tuple(axis_rows),
        passed = isempty(missing_required_axes) &&
            isempty(single_value_required_axes),
        caveat = :simulation_grid_summary_not_run_evidence,
        next_gate = :run_predeclared_grid_and_apply_falsification_rules,
    )
end

simulation_grid_summary(row, rows...; kwargs...) =
    simulation_grid_summary([row; rows...]; kwargs...)

const _DEFAULT_FALSIFICATION_RULE_DOMAINS = (
    :simulation_grid,
    :design_validation,
    :computation,
    :recovery,
    :calibration,
    :predictive_check,
    :decision_stability,
    :sensitivity,
    :baseline_comparison,
    :reproducibility,
)

function _finite_rule_threshold(value::Real, name::Symbol;
        minimum = nothing,
        maximum = nothing)
    checked = Float64(value)
    isfinite(checked) ||
        throw(ArgumentError("$name must be finite"))
    if minimum !== nothing
        checked >= Float64(minimum) ||
            throw(ArgumentError("$name must be >= $minimum"))
    end
    if maximum !== nothing
        checked <= Float64(maximum) ||
            throw(ArgumentError("$name must be <= $maximum"))
    end
    return checked
end

function _falsification_rule(; claim::Symbol, rule_index::Int, rule_id::Symbol,
        domain::Symbol, metric::Symbol, fail_if::Symbol, threshold,
        required_evidence::Symbol, action_if_triggered::Symbol)
    return (;
        schema = "bayesianmgmfrm.falsification_rule.v1",
        object = :falsification_rule,
        claim,
        rule_index,
        rule_id,
        domain,
        metric,
        fail_if,
        threshold,
        required_evidence,
        status = :predeclared_not_evaluated,
        action_if_triggered,
        manuscript_claim_allowed_if_triggered = false,
        caveat = :rule_predeclared_not_evidence,
    )
end

"""
    falsification_rules(; claim = :sparse_hierarchical_priors_stabilize_mgmfrm,
        max_rhat = 1.01, min_bulk_ess = 400, max_divergences = 0,
        max_max_treedepth_hits = 0, min_interval_coverage = 0.90,
        max_block_mean_absolute_error = 0.35,
        max_parameter_absolute_error = 0.75,
        max_expected_score_calibration_error = 0.25,
        max_category_probability_error = 0.10,
        min_predictive_tail_probability = 0.05,
        max_decision_flip_rate = 0.10,
        max_prior_sensitivity_shift = 0.25,
        min_heldout_elpd_gain = 0.0,
        required_grid_axes = ...)

Return predeclared falsification-rule rows for the claim that hierarchical
priors stabilize sparse MGMFRM designs. Rules cover simulation-grid coverage,
design validation, computation, recovery, calibration, predictive checks,
decision stability, sensitivity, baseline comparison, and reproducibility.

The rows are a claim contract, not run evidence. A triggered rule should narrow
or block the corresponding sparse-stability claim until the study is revised
or new evidence is generated.
"""
function falsification_rules(;
        claim::Symbol = :sparse_hierarchical_priors_stabilize_mgmfrm,
        max_rhat::Real = 1.01,
        min_bulk_ess::Real = 400,
        max_divergences::Integer = 0,
        max_max_treedepth_hits::Integer = 0,
        min_interval_coverage::Real = 0.90,
        max_block_mean_absolute_error::Real = 0.35,
        max_parameter_absolute_error::Real = 0.75,
        max_expected_score_calibration_error::Real = 0.25,
        max_category_probability_error::Real = 0.10,
        min_predictive_tail_probability::Real = 0.05,
        max_decision_flip_rate::Real = 0.10,
        max_prior_sensitivity_shift::Real = 0.25,
        min_heldout_elpd_gain::Real = 0.0,
        required_grid_axes = _DEFAULT_SIMULATION_GRID_REQUIRED_AXES)
    checked_max_rhat = _finite_rule_threshold(max_rhat, :max_rhat; minimum = 1)
    checked_min_bulk_ess =
        _finite_rule_threshold(min_bulk_ess, :min_bulk_ess; minimum = 1)
    checked_min_interval_coverage =
        _finite_rule_threshold(min_interval_coverage, :min_interval_coverage;
            minimum = 0, maximum = 1)
    checked_max_block_mae =
        _finite_rule_threshold(max_block_mean_absolute_error,
            :max_block_mean_absolute_error; minimum = 0)
    checked_max_parameter_abs =
        _finite_rule_threshold(max_parameter_absolute_error,
            :max_parameter_absolute_error; minimum = 0)
    checked_expected_score_error =
        _finite_rule_threshold(max_expected_score_calibration_error,
            :max_expected_score_calibration_error; minimum = 0)
    checked_category_error =
        _finite_rule_threshold(max_category_probability_error,
            :max_category_probability_error; minimum = 0)
    checked_tail_probability =
        _finite_rule_threshold(min_predictive_tail_probability,
            :min_predictive_tail_probability; minimum = 0, maximum = 1)
    checked_decision_flip =
        _finite_rule_threshold(max_decision_flip_rate, :max_decision_flip_rate;
            minimum = 0, maximum = 1)
    checked_prior_shift =
        _finite_rule_threshold(max_prior_sensitivity_shift,
            :max_prior_sensitivity_shift; minimum = 0)
    checked_elpd_gain =
        _finite_rule_threshold(min_heldout_elpd_gain, :min_heldout_elpd_gain)
    checked_grid_axes = _simulation_grid_axis_tuple(required_grid_axes)
    checked_divergences =
        _simulation_positive_integer(max_divergences, :max_divergences; minimum = 0)
    checked_treedepth =
        _simulation_positive_integer(max_max_treedepth_hits,
            :max_max_treedepth_hits; minimum = 0)

    specs = (
        (rule_id = :grid_axes_incomplete,
            domain = :simulation_grid,
            metric = :required_grid_axes_present,
            fail_if = :missing_any,
            threshold = checked_grid_axes,
            required_evidence = :simulation_grid_summary,
            action_if_triggered = :expand_predeclared_grid_before_claim),
        (rule_id = :design_disconnected,
            domain = :design_validation,
            metric = :n_rater_components,
            fail_if = :greater_than,
            threshold = 1,
            required_evidence = :validate_design_and_anchor_linking_summary,
            action_if_triggered = :narrow_to_connected_designs_or_collect_links),
        (rule_id = :rhat_too_high,
            domain = :computation,
            metric = :max_rhat,
            fail_if = :greater_than,
            threshold = checked_max_rhat,
            required_evidence = :diagnostics,
            action_if_triggered = :do_not_report_sparse_stability_claim),
        (rule_id = :bulk_ess_too_low,
            domain = :computation,
            metric = :min_bulk_ess,
            fail_if = :less_than,
            threshold = checked_min_bulk_ess,
            required_evidence = :diagnostics,
            action_if_triggered = :increase_sampling_or_simplify_model),
        (rule_id = :divergences_or_treedepth,
            domain = :computation,
            metric = :n_divergences_or_max_treedepth_hits,
            fail_if = :greater_than,
            threshold = (divergences = checked_divergences,
                max_treedepth_hits = checked_treedepth),
            required_evidence = :sampler_diagnostics,
            action_if_triggered = :treat_posterior_geometry_as_unresolved),
        (rule_id = :interval_coverage_low,
            domain = :recovery,
            metric = :interval_coverage_rate,
            fail_if = :less_than,
            threshold = checked_min_interval_coverage,
            required_evidence = :parameter_recovery_summary,
            action_if_triggered = :narrow_recovery_claim_or_revise_priors),
        (rule_id = :recovery_error_large,
            domain = :recovery,
            metric = :recovery_error,
            fail_if = :greater_than,
            threshold = (block_mean_absolute_error = checked_max_block_mae,
                parameter_absolute_error = checked_max_parameter_abs),
            required_evidence = :parameter_recovery_summary,
            action_if_triggered = :report_sparse_recovery_failure),
        (rule_id = :calibration_error_large,
            domain = :calibration,
            metric = :calibration_error,
            fail_if = :greater_than,
            threshold = (expected_score = checked_expected_score_error,
                category_probability = checked_category_error),
            required_evidence = :calibration_table,
            action_if_triggered = :block_predictive_stability_claim),
        (rule_id = :predictive_tail_mismatch,
            domain = :predictive_check,
            metric = :minimum_two_sided_tail_probability,
            fail_if = :less_than,
            threshold = checked_tail_probability,
            required_evidence = :predictive_check_summary,
            action_if_triggered = :report_predictive_misfit_before_claim),
        (rule_id = :decision_instability,
            domain = :decision_stability,
            metric = :max_decision_flip_rate,
            fail_if = :greater_than,
            threshold = checked_decision_flip,
            required_evidence = :dff_and_sparse_decision_grid,
            action_if_triggered = :frame_outputs_as_screening_only),
        (rule_id = :prior_sensitivity_large,
            domain = :sensitivity,
            metric = :max_focal_shift_across_prior_regimes,
            fail_if = :greater_than,
            threshold = checked_prior_shift,
            required_evidence = :sensitivity_comparison_summary,
            action_if_triggered = :treat_sparse_claim_as_prior_dependent),
        (rule_id = :heldout_baseline_not_improved,
            domain = :baseline_comparison,
            metric = :hierarchical_minus_baseline_heldout_elpd,
            fail_if = :less_than,
            threshold = checked_elpd_gain,
            required_evidence = :compare_kfold,
            action_if_triggered = :avoid_superiority_language),
        (rule_id = :reproduction_bundle_incomplete,
            domain = :reproducibility,
            metric = :all_required_artifacts_present,
            fail_if = :not_equal,
            threshold = true,
            required_evidence = :fit_archive_manifest,
            action_if_triggered = :do_not_publish_claim_until_rerunnable),
    )

    return [_falsification_rule(;
        claim,
        rule_index = index,
        spec...)
        for (index, spec) in pairs(specs)]
end

function _falsification_rule_domain(axis::Symbol)
    axis in (:grid, :simulation_grid) && return :simulation_grid
    axis in (:validation, :design_validation) && return :design_validation
    axis in (:sampler, :sampling, :computation) && return :computation
    axis in (:recovery, :parameter_recovery) && return :recovery
    axis in (:calibration, :predictive_calibration) && return :calibration
    axis in (:ppc, :predictive_check) && return :predictive_check
    axis in (:decision, :decision_stability) && return :decision_stability
    axis in (:sensitivity, :prior_sensitivity) && return :sensitivity
    axis in (:baseline, :baseline_comparison) && return :baseline_comparison
    axis in (:reproduction, :reproducibility) && return :reproducibility
    return axis
end

function _falsification_domain_tuple(domains)
    out = Symbol[]
    for domain in domains
        domain isa Symbol ||
            throw(ArgumentError("falsification rule domains must be Symbols"))
        canonical = _falsification_rule_domain(domain)
        canonical in out || push!(out, canonical)
    end
    return Tuple(out)
end

_falsification_domain_tuple(domain::Symbol) = (_falsification_rule_domain(domain),)

function _falsification_domain_summary(domain::Symbol, rows::AbstractVector)
    domain_rows = [row for row in rows if hasproperty(row, :domain) &&
        _falsification_rule_domain(row.domain) === domain]
    rule_ids = _sensitivity_unique_tuple(row.rule_id for row in domain_rows)
    return (;
        domain,
        present = !isempty(domain_rows),
        n_rules = length(domain_rows),
        rule_ids,
        status = isempty(domain_rows) ? :missing : :present,
    )
end

"""
    falsification_rule_summary(rows; required_domains =
        (:simulation_grid, :design_validation, :computation, :recovery,
         :calibration, :predictive_check, :decision_stability, :sensitivity,
         :baseline_comparison, :reproducibility))

Summarize predeclared falsification-rule rows and check whether every required
claim domain is represented. This is a rule-coverage summary; it does not
evaluate study results or decide whether a claim has passed.
"""
function falsification_rule_summary(rows::AbstractVector;
        required_domains = _DEFAULT_FALSIFICATION_RULE_DOMAINS)
    isempty(rows) &&
        throw(ArgumentError("at least one falsification rule row is required"))
    for row in rows
        row isa NamedTuple ||
            throw(ArgumentError("falsification rule summary expects NamedTuple rows"))
    end
    checked_required = _falsification_domain_tuple(required_domains)
    domain_rows = [_falsification_domain_summary(domain, rows)
        for domain in checked_required]
    missing_required_domains = Tuple(row.domain for row in domain_rows
        if row.status === :missing)
    present_required_domains = Tuple(row.domain for row in domain_rows
        if row.status === :present)
    return (;
        schema = "bayesianmgmfrm.falsification_rule_summary.v1",
        object = :falsification_rule_summary,
        required_domains = checked_required,
        n_rules = length(rows),
        n_domains = length(_sensitivity_unique_tuple(
            _falsification_rule_domain(row.domain) for row in rows
            if hasproperty(row, :domain))),
        missing_required_domains,
        present_required_domains,
        domain_rows = Tuple(domain_rows),
        passed = isempty(missing_required_domains),
        status = isempty(missing_required_domains) ? :complete : :incomplete,
        caveat = :rule_summary_not_study_result,
        next_gate = :evaluate_rules_on_predeclared_simulation_grid,
    )
end

falsification_rule_summary(row, rows...; kwargs...) =
    falsification_rule_summary([row; rows...]; kwargs...)

"""
    calibration_plot_data(calibration_rows)

Return plotting-ready rows from [`calibration_table`](@ref). Suggested mappings
are `x = predicted_mean`, `y = observed_mean`, with `reference = predicted_mean`
for the ideal calibration diagonal. The predicted interval fields can be used
as horizontal uncertainty bars.
"""
function calibration_plot_data(calibration_rows)
    return [(;
        target = row.target,
        category = row.category,
        bin = row.bin,
        predicted_mean = row.predicted_mean,
        observed_mean = row.observed_mean,
        predicted_lower = row.predicted_lower,
        predicted_upper = row.predicted_upper,
        predicted_bin_lower = row.predicted_bin_lower,
        predicted_bin_upper = row.predicted_bin_upper,
        calibration_error = row.calibration_error,
        absolute_calibration_error = row.absolute_calibration_error,
        flag = row.flag,
        reference = row.predicted_mean,
    ) for row in calibration_rows]
end

"""
    predictive_check_plot_data(summary_rows)

Return plotting-ready rows from [`predictive_check_summary`](@ref). Suggested
mappings are `y = observed`, `ymin/ymax = replicated_lower/replicated_upper`,
and `replicated_mean` as the model-implied center for each statistic/level.
"""
function predictive_check_plot_data(summary_rows)
    return [(;
        statistic = row.statistic,
        level = row.level,
        observed = row.observed,
        replicated_mean = row.replicated_mean,
        replicated_lower = row.replicated_lower,
        replicated_upper = row.replicated_upper,
        lower_tail_probability = row.lower_tail_probability,
        upper_tail_probability = row.upper_tail_probability,
        two_sided_tail_probability = row.two_sided_tail_probability,
        n_replicates = row.n_replicates,
        flag = row.flag,
    ) for row in summary_rows]
end
