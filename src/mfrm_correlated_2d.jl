# Private density-only extension; the base spec continues to denote independent abilities.
struct _MFRMFixedQCorrelated2DLogDensity
    base::_MFRMFixedQReferenceLogDensity
    blueprint::NamedTuple
    lkj_eta::Int
    log_beta_half_eta::Float64

    function _MFRMFixedQCorrelated2DLogDensity(spec::FacetSpec;
            prior::MFRMPrior = MFRMPrior(), lkj_eta = 2)
        _is_mfrm_fixed_q(spec) && spec.dimensions == 2 || throw(ArgumentError(
            "correlated fixed-coefficient MFRM requires family = :mfrm and exactly two dimensions"))
        eta = _checked_integer_lkj_eta(lkj_eta)
        base = _MFRMFixedQReferenceLogDensity(spec; prior)
        # Reuse the existing conservative simple-Q and person-coverage checks.
        _check_mgmfrm_free_latent_correlation_2d_design(base.base)
        names = [base.blueprint.parameter_names;
            "z_latent_correlation[$(join(spec.dimension_labels, ','))]"]
        blocks = copy(base.blueprint.blocks)
        blocks[:z_latent_correlation] = length(names):length(names)
        blueprint = (; parameter_names = names, blocks, n_parameters = length(names))
        return new(base, blueprint, eta, _log_beta_half_integer(eta))
    end
end

LogDensityProblems.dimension(target::_MFRMFixedQCorrelated2DLogDensity) = target.blueprint.n_parameters
LogDensityProblems.capabilities(::Type{_MFRMFixedQCorrelated2DLogDensity}) = LogDensityProblems.LogDensityOrder{0}()
initial_params(target::_MFRMFixedQCorrelated2DLogDensity) = zeros(LogDensityProblems.dimension(target))

function _mfrm_correlated_2d_coordinates(target::_MFRMFixedQCorrelated2DLogDensity, params::AbstractVector)
    _check_source_fixture_raw_vector(target, params)
    return view(params, 1:(length(params)-1)), last(params)
end

function logprior(target::_MFRMFixedQCorrelated2DLogDensity, params::AbstractVector)
    beta, zrho = _mfrm_correlated_2d_coordinates(target, params)
    person = target.base.blueprint.blocks[:person]
    logdelta = _log_one_minus_tanh_squared(zrho)
    # LKJ density on rho contributes (eta-1)*logdelta; d rho/d z adds logdelta.
    lp = -target.log_beta_half_eta + target.lkj_eta * logdelta
    for i in eachindex(beta)
        _in_range(person, i) && continue
        lp += _normal_logpdf(beta[i], _source_fixture_prior_sd(target.base, i))
    end
    for i in first(person):2:last(person)
        lp += _correlated_person_2d_logpdf(beta[i], beta[i+1],
            target.base.prior.person_sd, zrho, logdelta)
    end
    return lp
end

function LogDensityProblems.logdensity(target::_MFRMFixedQCorrelated2DLogDensity, params::AbstractVector)
    beta, _ = _mfrm_correlated_2d_coordinates(target, params)
    raw = _mfrm_fixed_q_reference_raw(target.base, beta)
    return _source_fixture_loglikelihood(target.base.base, raw) + logprior(target, params)
end

function _mfrm_correlated_2d_contract(target::_MFRMFixedQCorrelated2DLogDensity)
    return (; schema = "bayesianmgmfrm.mfrm_fixed_q_correlated_2d_target.v1",
        model = :mfrm_fixed_q_correlated_2d, base_identity = _mfrm_fixed_q_identity(target.base),
        dimensions = 2, item_structure = :between_item, coefficients = :fixed_q,
        scale_convention = :unit_logit, location = :prior_anchored,
        ability_coordinates = :direct_centered, ability_sd = target.base.prior.person_sd,
        latent_correlation = :free_2d, correlation_transform = :tanh,
        correlation_prior = :lkj_2d, lkj_eta = target.lkj_eta,
        correlation_prior_measure = :d_rho, density_measure = :d_beta_d_zrho,
        correlation_log_jacobian = :log_one_minus_rho_squared,
        fitting_available = false, cache_available = false)
end

_mfrm_correlated_2d_identity(target::_MFRMFixedQCorrelated2DLogDensity) =
    _cache_hash(_mfrm_correlated_2d_contract(target))

# No generalized-family/sampling dispatch: this adapter serves log_prob checks only.
_cmdstan_mfrm_correlated_2d_data(target::_MFRMFixedQCorrelated2DLogDensity) =
    merge(_cmdstan_generalized_data(target.base), (; lkj_eta = target.lkj_eta))
