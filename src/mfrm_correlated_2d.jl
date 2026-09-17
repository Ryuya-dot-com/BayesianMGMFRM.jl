# Private correlated target; the base spec continues to denote independent abilities.
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
        # Frozen v1 flags describe public fitting/fit-cache availability.
        fitting_available = false, cache_available = false)
end

_mfrm_correlated_2d_identity(target::_MFRMFixedQCorrelated2DLogDensity) =
    _cache_hash(_mfrm_correlated_2d_contract(target))

_cmdstan_mfrm_correlated_2d_data(target::_MFRMFixedQCorrelated2DLogDensity) =
    merge(_cmdstan_generalized_data(target.base), (; lkj_eta = target.lkj_eta))

_cmdstan_generalized_family(::_MFRMFixedQCorrelated2DLogDensity) = :mfrm_correlated_2d
_cmdstan_generalized_data(target::_MFRMFixedQCorrelated2DLogDensity) =
    _cmdstan_mfrm_correlated_2d_data(target)
function _cmdstan_generalized_initial(target::_MFRMFixedQCorrelated2DLogDensity, values)
    beta, zrho = _mfrm_correlated_2d_coordinates(target, values)
    return (; beta = collect(beta), zrho)
end

function _cmdstan_generalized_chain_result(path::AbstractString,
        target::_MFRMFixedQCorrelated2DLogDensity, chain::Int, ndraws::Int; warmup::Int = 0)
    n = LogDensityProblems.dimension(target)
    evaluate = params -> (; pointwise = _mfrm_fixed_q_pointwise(target.base, view(params, 1:(n-1))),
        logposterior = LogDensityProblems.logdensity(target, params))
    parsed = _cmdstan_raw_chain_result(path, n, target.base.design.spec.data.n,
        chain, ndraws, evaluate; warmup,
        parameter_names = [["beta.$i" for i in 1:(n-1)]; "zrho"])
    all(isapprox(stat.stan_lp, lp; atol = 1e-8, rtol = 1e-8)
        for (stat, lp) in zip(parsed.stats, parsed.logps)) || throw(CmdStanError(
            :output_parse, :log_posterior_mismatch,
            "CmdStan and Julia correlated fixed-Q MFRM log posteriors disagree"))
    return parsed
end

function _mfrm_fixed_q_model_coordinates(target::_MFRMFixedQCorrelated2DLogDensity,
        draws::AbstractMatrix{<:Real})
    size(draws, 2) == LogDensityProblems.dimension(target) && all(isfinite, draws) ||
        throw(ArgumentError("invalid correlated fixed-Q MFRM draw matrix"))
    rows = _mfrm_fixed_q_model_coordinates(target.base, view(draws, :, 1:(size(draws,2)-1)))
    rows = [merge(row, (; parameter_space = row.block in
        (:item_dimension_discrimination, :rater_consistency) ? :dimensionless : :unit_logit)) for row in rows]
    push!(rows, (; parameter = "latent_correlation[$(join(target.base.design.spec.dimension_labels, ','))]",
        values = tanh.(draws[:,end]), block = :latent_correlation, dimension = nothing,
        fixed = false, derived = true, parameter_space = :correlation))
    return rows
end

_mfrm_correlated_2d_prior_record(target::_MFRMFixedQCorrelated2DLogDensity) =
    (; base = _mfrm_fixed_q_prior_record(target.base), correlation = _mfrm_correlated_2d_contract(target))

function _mfrm_correlated_2d_samples(target, record::NamedTuple)
    result = _mfrm_fixed_q_samples(target, record; model = :mfrm_fixed_q_correlated_2d,
        parameter_space = :unit_logit_and_fisher_z,
        model_parameter_space = :unit_logit_with_fixed_coefficients_and_correlation)
    spaces = [fill(:unit_logit, length(result.parameter_names)-1); :fisher_z]
    model_spaces = getproperty.(result.model_coordinates, :parameter_space)
    annotate(rows, labels) = [merge(row, (; parameter_space = label)) for (row,label) in zip(rows,labels)]
    return merge(result, (; parameter_spaces = spaces,
        posterior_summary = annotate(result.posterior_summary, spaces),
        model_posterior_summary = annotate(result.model_posterior_summary, model_spaces),
        diagnostics = merge(result.diagnostics, (;
            parameter_rows = annotate(result.diagnostics.parameter_rows, spaces),
            model_parameter_rows = annotate(result.diagnostics.model_parameter_rows, model_spaces)))))
end

function _mfrm_correlated_2d_sample(target::_MFRMFixedQCorrelated2DLogDensity,
        initial::AbstractVector = initial_params(target);
        backend::Symbol = :advancedhmc, record_warmup::Bool = true, kwargs...)
    runner = backend === :advancedhmc ? _run_generalized_candidate_advancedhmc :
        backend === :cmdstan ? _cmdstan_generalized_candidate_run :
        throw(ArgumentError("correlated fixed-Q MFRM sampling supports :advancedhmc or :cmdstan"))
    _require_canonical_design(target.base.design, "correlated fixed-Q MFRM sampling")
    target = _MFRMFixedQCorrelated2DLogDensity(target.base.design.spec;
        prior = target.base.prior, lkj_eta = target.lkj_eta)
    run = runner(target, initial; record_warmup, kwargs...)
    record = (; schema = "bayesianmgmfrm.correlated_fixed_q_mfrm_samples.v1",
        base_spec = deepcopy(target.base.design.spec), prior = _mfrm_correlated_2d_prior_record(target),
        target_identity = _mfrm_correlated_2d_identity(target), run)
    record = merge(record, (; content_hash = _mgmfrm_normalized_sample_hash(record)))
    return _mfrm_correlated_2d_samples(target, record)
end

function _restore_mfrm_correlated_2d_samples(record; expected_identity::AbstractString)
    record isa NamedTuple && keys(record) ==
        (:schema, :base_spec, :prior, :target_identity, :run, :content_hash) &&
        record.schema == "bayesianmgmfrm.correlated_fixed_q_mfrm_samples.v1" &&
        record.base_spec isa FacetSpec && record.prior isa NamedTuple && record.run isa NamedTuple &&
        record.target_identity == expected_identity ||
        throw(ArgumentError("correlated fixed-Q MFRM sample contract or target mismatch"))
    record.content_hash == _mgmfrm_normalized_sample_hash(record) ||
        throw(ArgumentError("correlated fixed-Q MFRM sample content hash mismatch"))
    prior = record.prior
    keys(prior) == (:base, :correlation) && prior.base isa NamedTuple && prior.correlation isa NamedTuple &&
        hasproperty(prior.base, :scales) && prior.base.scales isa NamedTuple &&
        Set(keys(prior.base.scales)) == Set(fieldnames(MFRMPrior)) &&
        all(x -> x isa Real, values(prior.base.scales)) && hasproperty(prior.correlation, :lkj_eta) ||
        throw(ArgumentError("invalid correlated fixed-Q MFRM prior"))
    target = _MFRMFixedQCorrelated2DLogDensity(record.base_spec;
        prior = MFRMPrior(; prior.base.scales...), lkj_eta = prior.correlation.lkj_eta)
    isequal(prior, _mfrm_correlated_2d_prior_record(target)) &&
        _mfrm_correlated_2d_identity(target) == expected_identity ||
        throw(ArgumentError("correlated fixed-Q MFRM prior, measure or design mismatch"))
    return _mfrm_correlated_2d_samples(target, record)
end

# Trusted same-environment Serialization, separate from independent samples and public fit caches.
function _save_mfrm_correlated_2d_samples(path::AbstractString, result::NamedTuple;
        overwrite::Bool = false)
    record = result.record
    _restore_mfrm_correlated_2d_samples(record; expected_identity = record.target_identity)
    return _save_serialized_record(path, record; overwrite)
end

_load_mfrm_correlated_2d_samples(path::AbstractString; expected_identity::AbstractString) =
    _restore_mfrm_correlated_2d_samples(open(deserialize, path); expected_identity)
