# Private target, prior comparison and sample records; no public selector/default change.
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

# The same coordinates now feed the existing samplers and diagnostic tables.
_check_source_fixture_raw_vector(target::_MFRMExchangeableRatersLogDensity, values::AbstractVector) =
    _check_source_fixture_raw_vector(target.base, values)
_mfrm_fixed_q_parameter_names(target::_MFRMExchangeableRatersLogDensity) =
    _mfrm_fixed_q_parameter_names(target.base)
_mfrm_fixed_q_model_coordinates(target::_MFRMExchangeableRatersLogDensity, draws::AbstractMatrix{<:Real}) =
    _mfrm_fixed_q_model_coordinates(target.base, draws)
_cmdstan_generalized_initial(target::_MFRMExchangeableRatersLogDensity, values) =
    _cmdstan_generalized_initial(target.base, values)

function _cmdstan_generalized_chain_result(path::AbstractString,
        target::_MFRMExchangeableRatersLogDensity, chain::Int, ndraws::Int; warmup::Int = 0)
    reference = _mfrm_exchangeable_rater_reference(target)
    p = LogDensityProblems.dimension(reference)
    names = ["beta.$i" for i in 1:p]
    target.base isa _MFRMFixedQCorrelated2DLogDensity && push!(names, "zrho")
    evaluate = values -> (;
        pointwise = _mfrm_fixed_q_pointwise(reference, view(values, 1:p)),
        logposterior = LogDensityProblems.logdensity(target, values))
    parsed = _cmdstan_raw_chain_result(path, LogDensityProblems.dimension(target),
        reference.design.spec.data.n, chain, ndraws, evaluate; warmup, parameter_names = names)
    all(isapprox(stat.stan_lp, lp; atol = 1e-8, rtol = 1e-8)
        for (stat, lp) in zip(parsed.stats, parsed.logps)) || throw(CmdStanError(
            :output_parse, :log_posterior_mismatch,
            "CmdStan and Julia exchangeable-rater MFRM log posteriors disagree"))
    return parsed
end

function _mfrm_exchangeable_rater_samples(target::_MFRMExchangeableRatersLogDensity,
        record::NamedTuple)
    correlated = target.base isa _MFRMFixedQCorrelated2DLogDensity
    result = correlated ? _mfrm_correlated_2d_samples(target, record) : _mfrm_fixed_q_samples(target, record)
    return merge(result, (;
        model = correlated ? :mfrm_correlated_2d_exchangeable_raters : :mfrm_fixed_q_exchangeable_raters,
        rater_prior = :normalized_zero_sum_normal))
end

function _mfrm_exchangeable_rater_sample(target::_MFRMExchangeableRatersLogDensity,
        initial::AbstractVector = initial_params(target);
        backend::Symbol = :advancedhmc, record_warmup::Bool = true, kwargs...)
    runner = backend === :advancedhmc ? _run_generalized_candidate_advancedhmc :
        backend === :cmdstan ? _cmdstan_generalized_candidate_run :
        throw(ArgumentError("exchangeable-rater MFRM sampling supports :advancedhmc or :cmdstan"))
    reference = _mfrm_exchangeable_rater_reference(target)
    _require_canonical_design(reference.design, "exchangeable-rater MFRM sampling")
    spec = target.base isa _MFRMFixedQCorrelated2DLogDensity ?
        CorrelatedMFRMSpec(reference.design.spec; lkj_eta = target.base.lkj_eta) : reference.design.spec
    # Rebuild mutable numerical views from the authoritative design and scales.
    target = _MFRMExchangeableRatersLogDensity(spec;
        scales = _mfrm_exchangeable_rater_record(target).scales)
    run = runner(target, initial; record_warmup, kwargs...)
    record = (; schema = "bayesianmgmfrm.exchangeable_rater_mfrm_samples.v1",
        spec = deepcopy(spec), prior = _mfrm_exchangeable_rater_record(target),
        target_identity = _mfrm_exchangeable_rater_identity(target), run)
    record = merge(record, (; content_hash = _mgmfrm_normalized_sample_hash(record)))
    return _mfrm_exchangeable_rater_samples(target, record)
end

function _restore_mfrm_exchangeable_rater_samples(record; expected_identity::AbstractString)
    record isa NamedTuple && keys(record) ==
        (:schema, :spec, :prior, :target_identity, :run, :content_hash) &&
        record.schema == "bayesianmgmfrm.exchangeable_rater_mfrm_samples.v1" &&
        record.spec isa Union{FacetSpec,CorrelatedMFRMSpec} && record.prior isa NamedTuple &&
        record.run isa NamedTuple && record.target_identity == expected_identity ||
        throw(ArgumentError("exchangeable-rater MFRM sample contract or target mismatch"))
    record.content_hash == _mgmfrm_normalized_sample_hash(record) ||
        throw(ArgumentError("exchangeable-rater MFRM sample content hash mismatch"))
    target = _MFRMExchangeableRatersLogDensity(record.spec, record.prior; expected_identity)
    return _mfrm_exchangeable_rater_samples(target, record)
end

# Trusted same-environment Serialization, separate from compatibility/public fit caches.
function _save_mfrm_exchangeable_rater_samples(path::AbstractString, result::NamedTuple;
        overwrite::Bool = false)
    record = result.record
    _restore_mfrm_exchangeable_rater_samples(record; expected_identity = record.target_identity)
    return _save_serialized_record(path, record; overwrite)
end

_load_mfrm_exchangeable_rater_samples(path::AbstractString; expected_identity::AbstractString) =
    _restore_mfrm_exchangeable_rater_samples(open(deserialize, path); expected_identity)
