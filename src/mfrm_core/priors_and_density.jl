# priors_and_density.jl -- MFRM prior/fit types, log-densities, analytic gradients, and initialization.

const LOG2PI_BAYES = log(2 * pi)

function _ensure_docs_doc_loaded()
    if isempty(methods(Base.Docs.doc))
        Base.require(Base.PkgId(Base.UUID("3fa0cd96-eef1-5676-8a61-b3b8758bbffb"), "REPL"))
    end
    return nothing
end

function _binding_doc(mod::Module, name::Symbol)
    _ensure_docs_doc_loaded()
    return Base.invokelatest(Base.Docs.doc, Base.Docs.Binding(mod, name))
end

"""
    MFRMPrior(; person_sd = 1.5, rater_sd = 1.0, item_sd = 1.0, step_sd = 1.0)

Independent zero-centered normal priors for the identified minimal MFRM
parameter vector returned by `getdesign`, available as `Legacy.MFRMPrior`.
This prior belongs to the reference-coded compatibility route; standard
`mfrm_spec` calls use `prior = :default` or explicit distribution declarations.
The scales apply to free person,
rater, item, and threshold-step coordinates after reference, exact hard-anchor,
and sum-to-zero constraints have been imposed. Fixed anchors receive no prior
density contribution. The prior centers are not shifted when a hard-anchor
value changes, so likelihood-equivalent anchor reparameterizations are not in
general prior- or posterior-invariant. All scales must remain finite and
strictly positive after conversion to `Float64`.
"""
struct MFRMPrior
    person_sd::Float64
    rater_sd::Float64
    item_sd::Float64
    step_sd::Float64

    function MFRMPrior(person_sd::Real, rater_sd::Real, item_sd::Real, step_sd::Real)
        values = Float64.((person_sd, rater_sd, item_sd, step_sd))
        all(x -> isfinite(x) && x > 0, values) ||
            throw(ArgumentError("all prior standard deviations must be finite and positive after Float64 conversion"))
        return new(values...)
    end
end

MFRMPrior(; person_sd::Real = 1.5,
            rater_sd::Real = 1.0,
            item_sd::Real = 1.0,
            step_sd::Real = 1.0) =
    MFRMPrior(person_sd, rater_sd, item_sd, step_sd)

"""
    MFRMFit

Concrete fit for reference-coded `0.1.x` MFRM/RSM/PCM workflows, available as
`BayesianMGMFRM.Legacy.MFRMFit` (also `BayesianMGMFRM.MFRMFit`). Use
[`AbstractMFRMFit`](@ref) for type annotations covering standard v0.2 fits.
Warmup draws are excluded. `draws` is a matrix with one
retained posterior draw per row and one
identified design parameter per column, in `fit.design.parameter_names` order.
When multiple chains are requested, rows are grouped by chain and recorded in
`chain_ids` and `iterations`.
"""
struct MFRMFit <: AbstractMFRMFit
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
        _fatal_exception(err) && rethrow()
        err isa ArgumentError && rethrow()
        throw(ArgumentError("parameter vector contains values that cannot be checked as finite"))
    end
    return nothing
end

function _logprior_unchecked(
        design::FacetDesign,
        params::AbstractVector,
        prior::MFRMPrior)
    lp = _param_zero(params)
    for index in eachindex(params)
        lp += _normal_logpdf(params[index], _prior_sd(design, prior, index))
    end
    return lp
end

"""
    logprior(design::FacetDesign, params, prior = MFRMPrior())
    logprior(spec::FacetSpec, params, prior = MFRMPrior())
    logprior(fit::MFRMFit; ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    logprior(fit::Union{GMFRMFit,MGMFRMFit}; ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())

Evaluate the independent normal log prior for the identified minimal MFRM
parameter vector returned by `getdesign`. For fit objects, return one log-prior
value per selected posterior draw. Guarded generalized fits report the raw-prior
contribution implied by their stored log posterior minus direct log likelihood.
"""
function logprior(design::FacetDesign, params::AbstractVector, prior::MFRMPrior = MFRMPrior())
    _check_fit_supported_mfrm(design, "logprior")
    _check_parameter_vector(design, params)
    return _logprior_unchecked(design, params, prior)
end

logprior(spec::FacetSpec, params::AbstractVector, prior::MFRMPrior = MFRMPrior()) =
    logprior(getdesign(spec), params, prior)

function _loglikelihood_unchecked(
        design::FacetDesign,
        params::AbstractVector)
    return sum(_pointwise_loglikelihood_unchecked(design, params))
end

"""
    loglikelihood(design::FacetDesign, params)
    loglikelihood(spec::FacetSpec, params)
    loglikelihood(fit::MFRMFit; ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    loglikelihood(fit::Union{GMFRMFit,MGMFRMFit}; ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())

Evaluate the total minimal additive MFRM/RSM/PCM log likelihood for the
identified parameter vector returned by `getdesign`, without Bayesian priors.
For fit objects, return one total log-likelihood value per selected posterior
draw. Guarded generalized fits use their stored constrained direct
log-likelihood values.
"""
function loglikelihood(design::FacetDesign, params::AbstractVector)
    _check_fit_supported_mfrm(design, "loglikelihood")
    _check_parameter_vector(design, params)
    return _loglikelihood_unchecked(design, params)
end

loglikelihood(spec::FacetSpec, params::AbstractVector) =
    loglikelihood(getdesign(spec), params)

function _logposterior_unchecked(
        design::FacetDesign,
        params::AbstractVector,
        prior::MFRMPrior)
    return _loglikelihood_unchecked(design, params) +
        _logprior_unchecked(design, params, prior)
end

"""
    logposterior(design::FacetDesign, params, prior = MFRMPrior())
    logposterior(spec::FacetSpec, params, prior = MFRMPrior())
    logposterior(fit::Union{MFRMFit,GMFRMFit,MGMFRMFit}; ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())

Evaluate the log posterior for the minimal additive MFRM/RSM/PCM design:
the sum of `loglikelihood(design, params)` plus `logprior(design, params,
prior)` on the identified parameter vector. For fit objects, return the stored
log posterior for each selected posterior draw.
"""
function logposterior(design::FacetDesign, params::AbstractVector, prior::MFRMPrior = MFRMPrior())
    _check_fit_supported_mfrm(design, "logposterior")
    _check_parameter_vector(design, params)
    return _logposterior_unchecked(design, params, prior)
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
on the built-in random-walk Metropolis sampler.
"""
struct MFRMLogDensity
    design::FacetDesign
    prior::MFRMPrior
    function MFRMLogDensity(design::FacetDesign, prior::MFRMPrior)
        snapshot = _validated_design_snapshot(design, "MFRMLogDensity")
        return new(snapshot, prior)
    end
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
    (_check_parameter_vector(target.design, params);
        _logposterior_unchecked(target.design, params, target.prior))

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
            _fatal_exception(err) && rethrow()
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
        _fatal_exception(err) && rethrow()
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
        values = (;
            person_sd = Float64(person_sd),
            rater_sd = Float64(rater_sd),
            item_sd = Float64(item_sd),
            log_discrimination_sd = Float64(log_discrimination_sd),
            log_consistency_sd = Float64(log_consistency_sd),
            step_sd = Float64(step_sd),
        )
        for (name, value) in pairs(values)
            isfinite(value) && value > 0 ||
                throw(ArgumentError("$name must be a finite positive scale after Float64 conversion"))
        end
        return new(values...)
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
    BayesianMGMFRM.Experimental.GeneralizedPrior(;
        person_sd = 1.0,
        rater_sd = 1.0,
        item_sd = 1.0,
        log_discrimination_sd = 0.5,
        log_consistency_sd = 0.5,
        step_sd = 1.0,
    )

Construct the typed prior-scale contract accepted by the guarded GMFRM and
MGMFRM fitting APIs. Every argument is the standard deviation of an independent
zero-centered normal prior on the model's **raw unconstrained coordinates**.
In particular, `log_discrimination_sd` and `log_consistency_sd` act on log
coordinates before the positive identification transforms.

This contract does not define priors directly on transformed
item discrimination, rater consistency, sum-to-zero severity, or constrained
step parameters, and therefore does not add a change-of-variables Jacobian.
All scales must remain finite and strictly positive after conversion to `Float64`.
"""
struct GeneralizedPrior
    person_sd::Float64
    rater_sd::Float64
    item_sd::Float64
    log_discrimination_sd::Float64
    log_consistency_sd::Float64
    step_sd::Float64

    function GeneralizedPrior(person_sd::Real,
            rater_sd::Real,
            item_sd::Real,
            log_discrimination_sd::Real,
            log_consistency_sd::Real,
            step_sd::Real)
        internal = _SourceFixturePrior(
            person_sd,
            rater_sd,
            item_sd,
            log_discrimination_sd,
            log_consistency_sd,
            step_sd,
        )
        return new(
            internal.person_sd,
            internal.rater_sd,
            internal.item_sd,
            internal.log_discrimination_sd,
            internal.log_consistency_sd,
            internal.step_sd,
        )
    end
end

GeneralizedPrior(; person_sd::Real = 1.0,
    rater_sd::Real = 1.0,
    item_sd::Real = 1.0,
    log_discrimination_sd::Real = 0.5,
    log_consistency_sd::Real = 0.5,
    step_sd::Real = 1.0) =
    GeneralizedPrior(
        person_sd,
        rater_sd,
        item_sd,
        log_discrimination_sd,
        log_consistency_sd,
        step_sd,
    )

_source_fixture_prior(prior::GeneralizedPrior) =
    _SourceFixturePrior(
        prior.person_sd,
        prior.rater_sd,
        prior.item_sd,
        prior.log_discrimination_sd,
        prior.log_consistency_sd,
        prior.step_sd,
    )

function _source_fixture_prior_values(prior::_SourceFixturePrior)
    return (;
        person_sd = prior.person_sd,
        rater_sd = prior.rater_sd,
        item_sd = prior.item_sd,
        log_discrimination_sd = prior.log_discrimination_sd,
        log_consistency_sd = prior.log_consistency_sd,
        step_sd = prior.step_sd,
    )
end

function _source_fixture_prior_scale_value(prior::_SourceFixturePrior,
        scale_parameter)
    values = _source_fixture_prior_values(prior)
    scale_parameter isa Symbol || return missing
    scale_parameter in keys(values) || return missing
    return getproperty(values, scale_parameter)
end

function _resolved_generalized_raw_prior_control_manifest(control_manifest,
        prior::_SourceFixturePrior)
    rows = [
        merge(row, (;
            scale = _source_fixture_prior_scale_value(prior, row.scale_parameter),
            scale_status = row.status === :active &&
                !ismissing(_source_fixture_prior_scale_value(prior, row.scale_parameter)) ?
                :resolved_from_source_fixture_prior :
                row.scale_status,
        ))
        for row in control_manifest.rows
    ]
    return merge(control_manifest, (;
        resolved = true,
        prior_values = _source_fixture_prior_values(prior),
        rows,
        summary = merge(control_manifest.summary, (;
            all_active_scales_resolved =
                all(row -> row.status !== :active || !ismissing(row.scale), rows),
        )),
    ))
end

"""
    GMFRMFit

scalar GMFRM fit result returned only by
`BayesianMGMFRM.Experimental.fit(spec)` (or the legacy
`fit(spec; experimental = true)` spelling) for the one-dimensional rater-consistency
configuration with `thresholds = :partial_credit`,
`discrimination = :rater`, and no anchors or fitted DFF terms.
Raw draws are stored in `draws`, constrained direct draws in `direct_draws`, and
observation-ordered direct pointwise log likelihoods in
`direct_pointwise_loglikelihood`.
"""
struct GMFRMFit <: AbstractMFRMFit
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

Guarded MGMFRM fit result returned by
`BayesianMGMFRM.Experimental.fit(spec)` (or the legacy
`fit(spec; experimental = true)` spelling) for the fixed-Q confirmatory candidate with
`dimensions >= 1`, `thresholds = :partial_credit`, the generic compatibility
selector `discrimination = :none`, and no anchors or fitted DFF terms. The
kernel still contains Q-masked item-dimension discrimination parameters;
`:none` means that the broader generic discrimination selector is not used.
Raw draws are stored in `draws`, constrained direct draws in
`direct_draws`, and observation-ordered direct pointwise log likelihoods in
`direct_pointwise_loglikelihood`.
"""
struct MGMFRMFit <: AbstractMFRMFit
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
        ")")
end

function Base.show(io::IO, fit::MGMFRMFit)
    print(io, "MGMFRMFit(",
        size(fit.draws, 1), " raw draw(s), ",
        size(fit.draws, 2), " raw parameter(s), backend = :",
        fit.backend, ", sampler = :", fit.sampler,
        ", chains = ", length(fit.chain_acceptance_rate),
        ")")
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

# Private numerical reference: unit Q loadings/consistency and unit-logit
# coordinates. No public fitting, result or cache dispatch is implied.
struct _MFRMFixedQReferenceLogDensity
    base::_MGMFRMGuardedLocalFitLogDensity
    blueprint::NamedTuple
    prior::MFRMPrior
    design::FacetDesign

    function _MFRMFixedQReferenceLogDensity(spec::FacetSpec; prior::MFRMPrior)
        design = _is_mfrm_fixed_q(spec) ?
            _validated_design_snapshot(getdesign(spec; preview = true), "fixed-Q MFRM density") : nothing
        base = _mgmfrm_guarded_local_fit_logdensity(design === nothing ? spec :
            _mfrm_fixed_q_reference_spec(design.spec))
        return new(base, _mfrm_fixed_q_blueprint(base.blueprint), prior,
            design === nothing ? base.design : design)
    end
end

function _mfrm_fixed_q_reference_raw(target::_MFRMFixedQReferenceLogDensity,
        params::AbstractVector)
    _check_source_fixture_raw_vector(target, params)
    raw = zeros(typeof(_param_zero(params) + 0.0), target.base.blueprint.n_parameters)
    # Only evaluate the existing 1.7 likelihood in unit-logit coordinates.
    # Omitted log coefficients stay exactly zero and are never sampled.
    raw[target.blueprint.base_indices] .= params ./ 1.7
    return raw
end

LogDensityProblems.dimension(target::_MFRMFixedQReferenceLogDensity) =
    target.blueprint.n_parameters
LogDensityProblems.capabilities(::Type{_MFRMFixedQReferenceLogDensity}) =
    LogDensityProblems.LogDensityOrder{0}()
initial_params(target::_MFRMFixedQReferenceLogDensity) =
    zeros(LogDensityProblems.dimension(target))
logprior(target::_MFRMFixedQReferenceLogDensity, params::AbstractVector) =
    _source_fixture_logprior(target, params)
function LogDensityProblems.logdensity(target::_MFRMFixedQReferenceLogDensity,
        params::AbstractVector)
    raw = _mfrm_fixed_q_reference_raw(target, params)
    # Prior is declared directly on the reduced unit-logit coordinates, not on
    # a full positive-parameter vector; no change-of-measure term is needed.
    return _source_fixture_loglikelihood(target.base, raw) + logprior(target, params)
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
    snapshot = _validated_design_snapshot(design, "_source_fixture_logdensity")
    blueprint = _source_fixture_blueprint(snapshot)
    return _SourceFixtureLogDensity(snapshot, blueprint, prior)
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
    snapshot = _validated_design_snapshot(
        design,
        "_gmfrm_promotion_candidate_logdensity",
    )
    snapshot.spec.family === :gmfrm &&
        snapshot.spec.estimation_status === :specified_only ||
        throw(ArgumentError("_gmfrm_promotion_candidate_logdensity is only for specified-only GMFRM preview designs"))
    blueprint = _gmfrm_fit_ready_candidate_blueprint(snapshot)
    return _GMFRMPromotionCandidateLogDensity(snapshot, blueprint, prior)
end

function _gmfrm_promotion_candidate_logdensity(spec::FacetSpec;
        prior::_SourceFixturePrior = _SourceFixturePrior())
    return _gmfrm_promotion_candidate_logdensity(getdesign(spec; preview = true); prior)
end

function _mgmfrm_guarded_local_fit_logdensity(design::FacetDesign;
        prior::_SourceFixturePrior = _SourceFixturePrior())
    snapshot = _validated_design_snapshot(
        design,
        "_mgmfrm_guarded_local_fit_logdensity",
    )
    snapshot.spec.family === :mgmfrm &&
        snapshot.spec.estimation_status === :specified_only ||
        throw(ArgumentError("_mgmfrm_guarded_local_fit_logdensity is only for specified-only MGMFRM preview designs"))
    snapshot.spec.dimensions >= 1 ||
        throw(ArgumentError("_mgmfrm_guarded_local_fit_logdensity requires dimensions >= 1"))
    snapshot.spec.q_matrix !== nothing ||
        throw(ArgumentError("_mgmfrm_guarded_local_fit_logdensity requires a fixed confirmatory q_matrix"))
    blueprint = _mgmfrm_fit_ready_candidate_blueprint(snapshot)
    return _MGMFRMGuardedLocalFitLogDensity(snapshot, blueprint, prior)
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
        _fatal_exception(err) && rethrow()
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
        return _mgmfrm_source_loglikelihood_from_unconstrained(
            target.design, raw_params, target.blueprint)
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
    discrimination_product = _positive_product(item_discrimination_values)
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
            value = Float64(discrimination_product), target = 1.0,
            tolerance = 1e-8, passed = abs(discrimination_product - 1) <= 1e-8),
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

Return a parameter vector filled with `Float64(value)`. The converted value must
be finite. For a design or specification, entries follow
`getdesign(...).parameter_names`; log-density targets use their own parameter
ordering.
"""
function initial_params(design::FacetDesign; value::Real = 0.0)
    _require_canonical_design(design, "initial_params")
    value = Float64(value)
    isfinite(value) || throw(ArgumentError("value must be finite after Float64 conversion"))
    return fill(value, length(design.parameter_names))
end

initial_params(spec::FacetSpec; value::Real = 0.0) =
    initial_params(getdesign(spec); value)

initial_params(target::MFRMLogDensity; value::Real = 0.0) =
    initial_params(target.design; value)

function initial_params(target::_SourceFixtureLogDensity; value::Real = 0.0)
    value = Float64(value)
    isfinite(value) || throw(ArgumentError("value must be finite after Float64 conversion"))
    return fill(value, LogDensityProblems.dimension(target))
end

function initial_params(target::_GMFRMPromotionCandidateLogDensity; value::Real = 0.0)
    value = Float64(value)
    isfinite(value) || throw(ArgumentError("value must be finite after Float64 conversion"))
    return fill(value, LogDensityProblems.dimension(target))
end

function initial_params(target::_MGMFRMGuardedLocalFitLogDensity; value::Real = 0.0)
    value = Float64(value)
    isfinite(value) || throw(ArgumentError("value must be finite after Float64 conversion"))
    return fill(value, LogDensityProblems.dimension(target))
end
