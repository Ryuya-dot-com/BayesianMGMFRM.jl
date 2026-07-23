# mgmfrm_free_correlation_candidate.jl -- quarantined 2D correlation slice.

const _MAX_INTEGER_LKJ_ETA = 10_000

function _logfactorial_integer(n::Int)
    n >= 0 || throw(ArgumentError("log-factorial requires n >= 0"))
    return sum(log(Float64(value)) for value in 2:n; init = 0.0)
end

function _checked_integer_lkj_eta(value)
    value isa Bool &&
        throw(ArgumentError("lkj_eta must be a positive integer, not Bool"))
    value isa Real ||
        throw(ArgumentError("lkj_eta must be a positive integer"))
    original_is_positive_integer = try
        isfinite(value) && value > zero(value) && isinteger(value)
    catch
        false
    end
    original_is_positive_integer || throw(ArgumentError(
        "the initial dependency-free candidate requires lkj_eta to be " *
        "a finite positive integer",
    ))
    eta_value = try
        Float64(value)
    catch
        throw(ArgumentError("lkj_eta must be convertible to Float64"))
    end
    isfinite(eta_value) && eta_value > 0 && isinteger(eta_value) ||
        throw(ArgumentError(
            "the initial dependency-free candidate requires lkj_eta to be " *
            "a finite positive integer",
        ))
    eta_value <= _MAX_INTEGER_LKJ_ETA || throw(ArgumentError(
        "lkj_eta must not exceed $_MAX_INTEGER_LKJ_ETA in the initial candidate",
    ))
    return Int(eta_value)
end

function _log_beta_half_integer(eta::Int)
    # B(1/2, eta) = 4^eta * eta! * (eta - 1)! / (2eta)!.
    return eta * log(4.0) +
        _logfactorial_integer(eta) +
        _logfactorial_integer(eta - 1) -
        _logfactorial_integer(2 * eta)
end

struct _MGMFRMFreeLatentCorrelation2DPrior
    source_prior::_SourceFixturePrior
    lkj_eta::Int
    log_beta_half_eta::Float64
end

function _MGMFRMFreeLatentCorrelation2DPrior(
        source_prior::_SourceFixturePrior,
        lkj_eta)
    eta = _checked_integer_lkj_eta(lkj_eta)
    log_beta = _log_beta_half_integer(eta)
    isfinite(log_beta) ||
        throw(ArgumentError("lkj_eta produced a non-finite normalizer"))
    return _MGMFRMFreeLatentCorrelation2DPrior(
        source_prior,
        eta,
        log_beta,
    )
end

"""
Immutable-by-convention integer layout for the scalar simple-Q likelihood.

The public pointwise implementation remains the source-aligned reference path.  This
layout only removes repeated name lookup and per-observation container construction
from the quarantined candidate's scalar log-density hot path.
"""
struct _MGMFRMFreeLatentCorrelation2DScalarKernel
    person_parameter_index::Vector{Int}
    item_parameter_index::Vector{Int}
    rater_parameter_index::Vector{Int}
    loading_parameter_index::Vector{Int}
    consistency_parameter_index::Vector{Int}
    first_step_parameter_index::Vector{Int}
    observed_category::Vector{Int}
    n_categories::Int
    free_steps_per_item::Int
end

struct _MGMFRMFreeLatentCorrelation2DLogDensity
    base::_MGMFRMGuardedLocalFitLogDensity
    blueprint::NamedTuple
    prior::_MGMFRMFreeLatentCorrelation2DPrior
    scalar_kernel::_MGMFRMFreeLatentCorrelation2DScalarKernel
end

function Base.show(
        io::IO,
        target::_MGMFRMFreeLatentCorrelation2DLogDensity)
    print(io,
        "MGMFRMFreeLatentCorrelation2DLogDensity(",
        target.blueprint.n_parameters,
        " raw parameter(s), lkj_eta = ",
        target.prior.lkj_eta,
        ", public_fit = false)")
end

function _mgmfrm_free_latent_correlation_2d_blueprint(
        base::_MGMFRMGuardedLocalFitLogDensity)
    old = base.blueprint
    nbase = old.n_parameters
    zrho_index = nbase + 1
    labels = base.design.spec.dimension_labels
    parameter_names = copy(old.parameter_names)
    push!(parameter_names,
        "z_latent_correlation[$(labels[1]),$(labels[2])]")
    blocks = copy(old.blocks)
    blocks[:z_latent_correlation] = zrho_index:zrho_index
    return merge(old, (;
        scope = :mgmfrm_2d_free_latent_correlation_candidate,
        status = :internal_free_latent_correlation_candidate,
        compiler_stage = :free_latent_correlation_candidate,
        fit_ready = false,
        fixture_only = false,
        public_fit = false,
        cache_enabled = false,
        parameter_names,
        blocks,
        n_parameters = zrho_index,
        base_parameter_range = 1:nbase,
        zrho_index,
        derived_parameter_names =
            ["latent_correlation[$(labels[1]),$(labels[2])]"],
        latent_correlation_parameterization = :tanh_unconstrained,
        latent_correlation_prior = :lkj_2d,
    ))
end

function _check_mgmfrm_free_latent_correlation_2d_design(
        base::_MGMFRMGuardedLocalFitLogDensity)
    spec = base.design.spec
    spec.dimensions == 2 || throw(ArgumentError(
        "the free latent-correlation candidate requires dimensions == 2; " *
        "higher-dimensional correlation requires a positive-definite " *
        "LKJ-Cholesky parameterization",
    ))
    validation = q_matrix_validation(
        spec;
        cross_loading_policy = :blocked_simple_structure,
    )
    validation.passed || begin
        failing = Tuple(row.check for row in validation.rows
            if row.severity === :error)
        throw(ArgumentError(
            "the initial free latent-correlation candidate requires a " *
            "fixed simple-structure Q-matrix; failing_checks=$(repr(failing))",
        ))
    end
    q_matrix = spec.q_matrix
    pure_items_per_dimension = Tuple(
        count(item -> q_matrix[item, dimension] &&
            count(@view q_matrix[item, :]) == 1,
            axes(q_matrix, 1))
        for dimension in 1:2
    )
    all(>=(2), pure_items_per_dimension) || throw(ArgumentError(
        "the initial free latent-correlation candidate requires at least " *
        "two pure items per dimension; observed " *
        repr(pure_items_per_dimension),
    ))
    person_dimension_observed = falses(length(spec.data.person_levels), 2)
    for row in 1:spec.data.n
        person = spec.data.person[row]
        item = spec.data.item[row]
        for dimension in 1:2
            q_matrix[item, dimension] &&
                (person_dimension_observed[person, dimension] = true)
        end
    end
    incomplete_people = Tuple(
        spec.data.person_levels[person]
        for person in axes(person_dimension_observed, 1)
        if !all(@view person_dimension_observed[person, :])
    )
    isempty(incomplete_people) || throw(ArgumentError(
        "the initial free latent-correlation candidate requires every " *
        "person to have observations connected to both dimensions; " *
        "incomplete_people=$(repr(incomplete_people))",
    ))
    person_block = base.blueprint.blocks[:person]
    expected_people = length(spec.data.person_levels)
    length(person_block) == 2 * expected_people || throw(ArgumentError(
        "unexpected 2D person block layout in free-correlation candidate",
    ))
    return (;
        q_matrix_validation = validation,
        pure_items_per_dimension,
        person_dimension_observed,
    )
end

function _mgmfrm_free_latent_correlation_2d_scalar_kernel(
        base::_MGMFRMGuardedLocalFitLogDensity)
    design = base.design
    spec = design.spec
    data = spec.data
    q_matrix = spec.q_matrix
    n_rows = data.n
    n_items = length(data.item_levels)
    n_categories = length(data.category_levels)
    free_steps = max(n_categories - 2, 0)

    # Resolve the constrained loading index once.  For the admitted simple-Q
    # designs there is exactly one active dimension and one loading per item.
    index_by_name = _parameter_index_map(design)
    active_dimension_by_item = Vector{Int}(undef, n_items)
    loading_index_by_item = Vector{Int}(undef, n_items)
    for item in 1:n_items
        active_dimensions = findall(@view q_matrix[item, :])
        length(active_dimensions) == 1 || throw(ArgumentError(
            "the scalar free-correlation kernel requires one active dimension per item",
        ))
        loading_indices =
            _loading_parameter_indices(design, index_by_name, item)
        length(loading_indices) == 1 || throw(ArgumentError(
            "the scalar free-correlation kernel requires one loading parameter per item",
        ))
        active_dimension_by_item[item] = only(active_dimensions)
        loading_index_by_item[item] = only(loading_indices)
    end

    person_block = design.blocks[:person]
    item_block = design.blocks[:item]
    rater_block = design.blocks[:rater]
    consistency_block = design.blocks[:rater_consistency]
    step_block = design.blocks[:item_steps]
    person_parameter_index = Vector{Int}(undef, n_rows)
    item_parameter_index = Vector{Int}(undef, n_rows)
    rater_parameter_index = Vector{Int}(undef, n_rows)
    loading_parameter_index = Vector{Int}(undef, n_rows)
    consistency_parameter_index = Vector{Int}(undef, n_rows)
    first_step_parameter_index = Vector{Int}(undef, n_rows)
    observed_category = Int.(data.category)
    for row in 1:n_rows
        item = data.item[row]
        rater = data.rater[row]
        person_offset = (data.person[row] - 1) * 2
        person_parameter_index[row] =
            person_block[person_offset + active_dimension_by_item[item]]
        item_parameter_index[row] = item_block[item]
        rater_parameter_index[row] = rater_block[rater]
        loading_parameter_index[row] = loading_index_by_item[item]
        consistency_parameter_index[row] = consistency_block[rater]
        first_step_parameter_index[row] = free_steps == 0 ? 0 :
            first(step_block) + (item - 1) * free_steps
    end
    all(category -> 1 <= category <= n_categories, observed_category) ||
        throw(ArgumentError(
            "the scalar free-correlation kernel found an invalid category index",
        ))
    return _MGMFRMFreeLatentCorrelation2DScalarKernel(
        person_parameter_index,
        item_parameter_index,
        rater_parameter_index,
        loading_parameter_index,
        consistency_parameter_index,
        first_step_parameter_index,
        observed_category,
        n_categories,
        free_steps,
    )
end

function _mgmfrm_free_latent_correlation_2d_logdensity(
        base::_MGMFRMGuardedLocalFitLogDensity;
        lkj_eta = 2)
    _check_mgmfrm_free_latent_correlation_2d_design(base)
    prior = _MGMFRMFreeLatentCorrelation2DPrior(base.prior, lkj_eta)
    blueprint = _mgmfrm_free_latent_correlation_2d_blueprint(base)
    scalar_kernel =
        _mgmfrm_free_latent_correlation_2d_scalar_kernel(base)
    return _MGMFRMFreeLatentCorrelation2DLogDensity(
        base,
        blueprint,
        prior,
        scalar_kernel,
    )
end

function _mgmfrm_free_latent_correlation_2d_logdensity(
        design::FacetDesign;
        prior::_SourceFixturePrior = _SourceFixturePrior(),
        lkj_eta = 2)
    base = _mgmfrm_guarded_local_fit_logdensity(design; prior)
    return _mgmfrm_free_latent_correlation_2d_logdensity(base; lkj_eta)
end

function _mgmfrm_free_latent_correlation_2d_logdensity(
        spec::FacetSpec;
        prior::_SourceFixturePrior = _SourceFixturePrior(),
        lkj_eta = 2)
    base = _mgmfrm_guarded_local_fit_logdensity(spec; prior)
    return _mgmfrm_free_latent_correlation_2d_logdensity(base; lkj_eta)
end

function _mgmfrm_free_latent_correlation_2d_coordinates(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity,
        raw_params::AbstractVector)
    _check_source_fixture_raw_vector(target, raw_params)
    base_raw = view(raw_params, target.blueprint.base_parameter_range)
    zrho = raw_params[target.blueprint.zrho_index]
    return base_raw, zrho
end

@inline function _log_one_minus_tanh_squared(z::Real)
    two = one(z) + one(z)
    logtwo = log(two)
    if z >= zero(z)
        return two * (logtwo - z - log1p(exp(-two * z)))
    end
    return two * (logtwo + z - log1p(exp(two * z)))
end

@inline function _negative_half_log_one_minus_tanh_squared(z::Real)
    two = one(z) + one(z)
    logtwo = log(two)
    if z >= zero(z)
        return z + log1p(exp(-two * z)) - logtwo
    end
    return -z + log1p(exp(two * z)) - logtwo
end

_free_correlation_primal(value) = value
_free_correlation_primal(value::ForwardDiff.Dual) = ForwardDiff.value(value)

@inline function _safe_dual_partial_product(coefficient, seed)
    iszero(seed) && return zero(coefficient)
    return coefficient * seed
end

@inline function _binary_dual_result(
        primal,
        derivative_first,
        derivative_second,
        first::ForwardDiff.Dual{T,V,N},
        second::ForwardDiff.Dual{T,V,N}) where {T,V,N}
    first_partials = ForwardDiff.partials(first)
    second_partials = ForwardDiff.partials(second)
    partials = ntuple(Val(N)) do index
        _safe_dual_partial_product(
            derivative_first,
            first_partials[index],
        ) + _safe_dual_partial_product(
            derivative_second,
            second_partials[index],
        )
    end
    return ForwardDiff.Dual{T}(primal, partials)
end

@inline function _binary_dual_result(
        primal,
        derivative_first,
        derivative_second,
        first::ForwardDiff.Dual{T,V,N},
        second::Real) where {T,V,N}
    first_partials = ForwardDiff.partials(first)
    partials = ntuple(Val(N)) do index
        _safe_dual_partial_product(
            derivative_first,
            first_partials[index],
        )
    end
    return ForwardDiff.Dual{T}(primal, partials)
end

@inline function _binary_dual_result(
        primal,
        derivative_first,
        derivative_second,
        first::Real,
        second::ForwardDiff.Dual{T,V,N}) where {T,V,N}
    second_partials = ForwardDiff.partials(second)
    partials = ntuple(Val(N)) do index
        _safe_dual_partial_product(
            derivative_second,
            second_partials[index],
        )
    end
    return ForwardDiff.Dual{T}(primal, partials)
end

@inline function _scaled_square_primal(value::Real, log_scale::Real)
    iszero(value) && return zero(value + log_scale)
    scale = exp(log_scale)
    if isfinite(scale) && !iszero(scale)
        return value * (value * scale)
    end
    return exp(2 * log(abs(value)) + log_scale)
end

@inline function _scaled_square_first_derivative_primal(
        value::Real,
        log_scale::Real)
    iszero(value) && return zero(value + log_scale)
    return sign(value) *
        exp(log(one(value) + one(value)) + log(abs(value)) + log_scale)
end

@inline function _zero_primal_scaled_square(
        value::Real,
        log_scale::Real)
    return _scaled_square_primal(value, log_scale)
end

@inline function _zero_primal_scaled_square(
        value::ForwardDiff.Dual{T,V,N},
        log_scale::ForwardDiff.Dual{T,V,N}) where {T,V,N}
    primal_value = ForwardDiff.value(value)
    primal_log_scale = ForwardDiff.value(log_scale)
    primal = _scaled_square_primal(primal_value, primal_log_scale)
    derivative_value = _scaled_square_first_derivative_primal(
        primal_value,
        primal_log_scale,
    )
    return _binary_dual_result(
        primal,
        derivative_value,
        primal,
        value,
        log_scale,
    )
end

@inline function _zero_primal_scaled_square(
        value::ForwardDiff.Dual,
        log_scale::Real)
    primal_value = ForwardDiff.value(value)
    primal_log_scale = _free_correlation_primal(log_scale)
    primal = _scaled_square_primal(primal_value, primal_log_scale)
    derivative_value = _scaled_square_first_derivative_primal(
        primal_value,
        primal_log_scale,
    )
    return _binary_dual_result(
        primal,
        derivative_value,
        primal,
        value,
        log_scale,
    )
end

@inline function _zero_primal_scaled_square(
        value::Real,
        log_scale::ForwardDiff.Dual)
    primal_value = _free_correlation_primal(value)
    primal_log_scale = ForwardDiff.value(log_scale)
    primal = _scaled_square_primal(primal_value, primal_log_scale)
    derivative_value = _scaled_square_first_derivative_primal(
        primal_value,
        primal_log_scale,
    )
    return _binary_dual_result(
        primal,
        derivative_value,
        primal,
        value,
        log_scale,
    )
end

@inline function _signed_scaled_primal(value::Real, log_scale::Real)
    iszero(value) && return zero(value + log_scale)
    scale = exp(log_scale)
    if isfinite(scale) && !iszero(scale)
        return value * scale
    end
    return sign(value) * exp(log(abs(value)) + log_scale)
end

@inline function _signed_primal_log_scaled(
        value::Real,
        log_scale::Real)
    return _signed_scaled_primal(value, log_scale)
end

@inline function _signed_primal_log_scaled(
        value::ForwardDiff.Dual{T,V,N},
        log_scale::ForwardDiff.Dual{T,V,N}) where {T,V,N}
    primal_value = ForwardDiff.value(value)
    primal_log_scale = ForwardDiff.value(log_scale)
    primal = _signed_scaled_primal(primal_value, primal_log_scale)
    derivative_value = exp(primal_log_scale)
    return _binary_dual_result(
        primal,
        derivative_value,
        primal,
        value,
        log_scale,
    )
end

@inline function _signed_primal_log_scaled(
        value::ForwardDiff.Dual,
        log_scale::Real)
    primal_value = ForwardDiff.value(value)
    primal_log_scale = _free_correlation_primal(log_scale)
    primal = _signed_scaled_primal(primal_value, primal_log_scale)
    derivative_value = exp(primal_log_scale)
    return _binary_dual_result(
        primal,
        derivative_value,
        primal,
        value,
        log_scale,
    )
end

@inline function _signed_primal_log_scaled(
        value::Real,
        log_scale::ForwardDiff.Dual)
    primal_value = _free_correlation_primal(value)
    primal_log_scale = ForwardDiff.value(log_scale)
    primal = _signed_scaled_primal(primal_value, primal_log_scale)
    derivative_value = exp(primal_log_scale)
    return _binary_dual_result(
        primal,
        derivative_value,
        primal,
        value,
        log_scale,
    )
end

@inline function _correlated_conditional_residual(
        u1::Real,
        u2::Real,
        zrho::Real)
    rho = tanh(zrho)
    rho_primal = _free_correlation_primal(rho)
    complement = one(rho_primal) - abs(rho_primal)
    near_saturation = complement <= sqrt(eps(one(rho_primal)))
    residual = if near_saturation && rho_primal >= zero(rho_primal)
        # 1 - tanh(z) = 2exp(-2z) / (1 + exp(-2z)). Reconstruct
        # the small term in log space instead of subtracting a rho rounded to
        # one. This also preserves nonzero derivatives for near-equal u1/u2.
        two = one(zrho) + one(zrho)
        logepsilon = log(two) - two * zrho -
            log1p(exp(-two * zrho))
        (u2 - u1) + _signed_primal_log_scaled(u1, logepsilon)
    elseif near_saturation
        # 1 + tanh(z) = 2exp(2z) / (1 + exp(2z)).
        two = one(zrho) + one(zrho)
        logepsilon = log(two) + two * zrho -
            log1p(exp(two * zrho))
        (u2 + u1) - _signed_primal_log_scaled(u1, logepsilon)
    else
        u2 - rho * u1
    end
    return residual
end

@inline function _correlated_conditional_square(
        u1::Real,
        u2::Real,
        zrho::Real)
    logdelta = _log_one_minus_tanh_squared(zrho)
    return _correlated_conditional_square(
        u1,
        u2,
        zrho,
        logdelta,
        zero(logdelta),
    )
end

@inline function _correlated_conditional_square(
        u1::Real,
        u2::Real,
        zrho::Real,
        logdelta::Real)
    return _correlated_conditional_square(
        u1,
        u2,
        zrho,
        logdelta,
        zero(logdelta),
    )
end

@inline function _correlated_conditional_square(
        u1::Real,
        u2::Real,
        zrho::Real,
        logdelta::Real,
        log_weight::Real)
    rho_primal = _free_correlation_primal(tanh(zrho))
    difference = u2 - u1
    sum_value = u2 + u1
    exact_zero_slice = (
        (rho_primal >= zero(rho_primal) &&
            iszero(_free_correlation_primal(difference))) ||
        (rho_primal < zero(rho_primal) &&
            iszero(_free_correlation_primal(sum_value)))
    )
    if exact_zero_slice
        two = one(zrho) + one(zrho)
        two_z = two * zrho
        logfour = log(two + two)
        cross_weight = exp(log_weight - log(two))
        return _zero_primal_scaled_square(
            difference,
            log_weight + two_z - logfour,
        ) +
            (cross_weight * difference) * sum_value +
            _zero_primal_scaled_square(
                sum_value,
                log_weight - two_z - logfour,
            )
    end
    residual = _correlated_conditional_residual(u1, u2, zrho)
    return _zero_primal_scaled_square(
        residual,
        log_weight - logdelta,
    )
end

@inline function _correlated_person_2d_logpdf(
        theta1::Real,
        theta2::Real,
        sd::Float64,
        zrho::Real)
    logdelta = _log_one_minus_tanh_squared(zrho)
    return _correlated_person_2d_logpdf(
        theta1,
        theta2,
        sd,
        zrho,
        logdelta,
    )
end

@inline function _correlated_person_2d_logpdf(
        theta1::Real,
        theta2::Real,
        sd::Float64,
        zrho::Real,
        logdelta::Real)
    u1 = theta1 / sd
    u2 = theta2 / sd
    loghalf = -log(one(zrho) + one(zrho))
    half_u1_square = _zero_primal_scaled_square(u1, loghalf)
    half_conditional_square = _correlated_conditional_square(
        u1,
        u2,
        zrho,
        logdelta,
        loghalf,
    )
    log_normalizer =
        _negative_half_log_one_minus_tanh_squared(zrho)
    return -LOG2PI_BAYES - 2log(sd) + log_normalizer -
        half_u1_square - half_conditional_square
end

@inline function _lkj2_zrho_logpdf(
        zrho::Real,
        prior::_MGMFRMFreeLatentCorrelation2DPrior)
    return _lkj2_zrho_logpdf(
        zrho,
        prior,
        _log_one_minus_tanh_squared(zrho),
    )
end


@inline function _lkj2_zrho_logpdf(
        zrho::Real,
        prior::_MGMFRMFreeLatentCorrelation2DPrior,
        logdelta::Real)
    return -prior.log_beta_half_eta + prior.lkj_eta * logdelta
end

function _mgmfrm_free_latent_correlation_2d_logprior(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity,
        raw_params::AbstractVector)
    base_raw, zrho =
        _mgmfrm_free_latent_correlation_2d_coordinates(target, raw_params)
    person_block = target.base.blueprint.blocks[:person]
    person_sd = target.prior.source_prior.person_sd
    logdelta = _log_one_minus_tanh_squared(zrho)
    lp = _param_zero(raw_params)
    for index in eachindex(base_raw)
        _in_range(person_block, index) && continue
        lp += _normal_logpdf(
            base_raw[index],
            _source_fixture_prior_sd(target.base, index),
        )
    end
    for index in first(person_block):2:last(person_block)
        theta1 = base_raw[index]
        theta2 = base_raw[index + 1]
        lp += _correlated_person_2d_logpdf(
            theta1,
            theta2,
            person_sd,
            zrho,
            logdelta,
        )
    end
    return lp + _lkj2_zrho_logpdf(zrho, target.prior, logdelta)
end

@inline function _mgmfrm_free_latent_correlation_2d_scalar_row_loglikelihood!(
        etas::AbstractVector,
        params::AbstractVector,
        kernel::_MGMFRMFreeLatentCorrelation2DScalarKernel,
        row::Int)
    @inbounds begin
        ability_score =
            params[kernel.loading_parameter_index[row]] *
            params[kernel.person_parameter_index[row]]
        location_value = ability_score -
            params[kernel.item_parameter_index[row]] -
            params[kernel.rater_parameter_index[row]]
        scale_value = 1.7 * params[kernel.consistency_parameter_index[row]]
        etas[1] = zero(scale_value * location_value)
        cumulative = zero(etas[1])
        derived_step_total = zero(etas[1])
        if kernel.free_steps_per_item > 0
            first_step = kernel.first_step_parameter_index[row]
            for offset in 0:(kernel.free_steps_per_item - 1)
                derived_step_total += params[first_step + offset]
            end
        end
        for category_index in 2:kernel.n_categories
            step_value = if kernel.free_steps_per_item == 0
                zero(etas[1])
            elseif category_index <= kernel.n_categories - 1
                params[kernel.first_step_parameter_index[row] +
                    category_index - 2]
            else
                -derived_step_total
            end
            cumulative += scale_value * (location_value - step_value)
            etas[category_index] = cumulative
        end
        return etas[kernel.observed_category[row]] - _logsumexp(etas)
    end
end

function _mgmfrm_free_latent_correlation_2d_constrained_params(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity,
        base_raw::AbstractVector)
    # The base target already owns the validated unconstrained blueprint.  Reusing
    # its ranges avoids rebuilding hundreds of parameter names on every gradient
    # evaluation while preserving the source transform and constraint check.
    raw_blocks = target.base.blueprint.blocks
    design = target.base.design
    constrained_blocks = design.blocks
    T = typeof(_param_zero(base_raw) + 0.0)
    params = Vector{T}(undef, length(design.parameter_names))

    for (raw_block_name, constrained_block_name) in (
            (:person, :person),
            (:item, :item),
            (:item_steps, :item_steps))
        raw_block = raw_blocks[raw_block_name]
        constrained_block = constrained_blocks[constrained_block_name]
        length(raw_block) == length(constrained_block) ||
            throw(ArgumentError(
                "the cached free-correlation transform found a block-length mismatch",
            ))
        @inbounds for offset in 0:(length(raw_block) - 1)
            params[first(constrained_block) + offset] =
                base_raw[first(raw_block) + offset]
        end
    end

    raw_rater = raw_blocks[:rater_free]
    constrained_rater = constrained_blocks[:rater]
    length(raw_rater) + 1 == length(constrained_rater) ||
        throw(ArgumentError(
            "the cached free-correlation transform found an invalid rater block",
        ))
    rater_total = _param_zero(base_raw)
    @inbounds for offset in 0:(length(raw_rater) - 1)
        value = base_raw[first(raw_rater) + offset]
        params[first(constrained_rater) + offset] = value
        rater_total += value
    end
    params[last(constrained_rater)] = -rater_total

    raw_loading = raw_blocks[:log_item_dimension_discrimination]
    constrained_loading =
        constrained_blocks[:item_dimension_discrimination]
    length(raw_loading) == length(constrained_loading) ||
        throw(ArgumentError(
            "the cached free-correlation transform found an invalid loading block",
        ))
    @inbounds for offset in 0:(length(raw_loading) - 1)
        params[first(constrained_loading) + offset] =
            exp(base_raw[first(raw_loading) + offset])
    end

    raw_consistency = raw_blocks[:log_rater_consistency_free]
    constrained_consistency = constrained_blocks[:rater_consistency]
    length(raw_consistency) + 1 == length(constrained_consistency) ||
        throw(ArgumentError(
            "the cached free-correlation transform found an invalid consistency block",
        ))
    log_consistency_total = _param_zero(base_raw)
    @inbounds for offset in 0:(length(raw_consistency) - 1)
        value = base_raw[first(raw_consistency) + offset]
        params[first(constrained_consistency) + offset] = exp(value)
        log_consistency_total += value
    end
    params[last(constrained_consistency)] = exp(-log_consistency_total)

    _mgmfrm_source_fixture_constraints(design, params)
    return params
end

function _mgmfrm_free_latent_correlation_2d_loglikelihood(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity,
        raw_params::AbstractVector)
    base_raw, _ =
        _mgmfrm_free_latent_correlation_2d_coordinates(target, raw_params)
    params = _mgmfrm_free_latent_correlation_2d_constrained_params(
        target,
        base_raw,
    )
    kernel = target.scalar_kernel
    T = typeof(_param_zero(params) + 0.0)
    etas = Vector{T}(undef, kernel.n_categories)
    loglikelihood = _param_zero(params)
    for row in eachindex(kernel.observed_category)
        loglikelihood +=
            _mgmfrm_free_latent_correlation_2d_scalar_row_loglikelihood!(
                etas,
                params,
                kernel,
                row,
            )
    end
    return loglikelihood
end

function _mgmfrm_free_latent_correlation_2d_pointwise_loglikelihood(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity,
        raw_params::AbstractVector)
    base_raw, _ =
        _mgmfrm_free_latent_correlation_2d_coordinates(target, raw_params)
    return _mgmfrm_source_pointwise_loglikelihood_from_unconstrained(
        target.base.design,
        base_raw,
    )
end

function _mgmfrm_free_latent_correlation_2d_logposterior(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity,
        raw_params::AbstractVector)
    return _mgmfrm_free_latent_correlation_2d_loglikelihood(
        target,
        raw_params,
    ) + _mgmfrm_free_latent_correlation_2d_logprior(target, raw_params)
end

LogDensityProblems.logdensity(
    target::_MGMFRMFreeLatentCorrelation2DLogDensity,
    raw_params,
) = _mgmfrm_free_latent_correlation_2d_logposterior(target, raw_params)

LogDensityProblems.dimension(
    target::_MGMFRMFreeLatentCorrelation2DLogDensity,
) = target.blueprint.n_parameters

LogDensityProblems.capabilities(
    ::Type{_MGMFRMFreeLatentCorrelation2DLogDensity},
) = LogDensityProblems.LogDensityOrder{0}()

function initial_params(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity;
        value::Real = 0.0,
        zrho::Real = 0.0)
    isfinite(value) || throw(ArgumentError("value must be finite"))
    zrho isa Bool && throw(ArgumentError("zrho must be a finite real value"))
    isfinite(zrho) || throw(ArgumentError("zrho must be finite"))
    return vcat(
        initial_params(target.base; value),
        Float64(zrho),
    )
end

function _mgmfrm_free_latent_correlation_2d_state(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity,
        raw_params::AbstractVector)
    _, zrho =
        _mgmfrm_free_latent_correlation_2d_coordinates(target, raw_params)
    rho = tanh(zrho)
    log_determinant = _log_one_minus_tanh_squared(zrho)
    numerically_saturated = abs(rho) == one(rho)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_state.v1",
        parameterization = :tanh_unconstrained,
        zrho,
        rho,
        log_determinant,
        numerically_saturated,
        correlation_matrix = numerically_saturated ? missing :
            [one(rho) rho; rho one(rho)],
        lkj_eta = target.prior.lkj_eta,
        log_beta_half_eta = target.prior.log_beta_half_eta,
    )
end

function _mgmfrm_free_latent_correlation_2d_diagnostics(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity,
        raw_params::AbstractVector;
        ad_backend::Symbol = :ForwardDiff,
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
    adapter = _logdensity_gradient_target(target, raw, ad_backend)
    logdensity, gradient = LogDensityProblems.logdensity_and_gradient(
        adapter.target,
        raw,
    )
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
            passed = isfinite(automatic) && isfinite(finite_difference) &&
                abs_error <= tolerance,
        ))
    end
    base_raw, _ =
        _mgmfrm_free_latent_correlation_2d_coordinates(target, raw)
    base_loglikelihood = _source_fixture_loglikelihood(target.base, base_raw)
    candidate_loglikelihood =
        _mgmfrm_free_latent_correlation_2d_loglikelihood(target, raw)
    likelihood_abs_error =
        abs(candidate_loglikelihood - base_loglikelihood)
    n_failed = count(row -> !row.passed, rows)
    passed = isfinite(logdensity) && finite_gradient && n_failed == 0 &&
        likelihood_abs_error <= 1e-12
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_diagnostics.v1",
        family = :mgmfrm,
        scope = :mgmfrm_2d_free_latent_correlation_candidate,
        status = :internal_free_latent_correlation_candidate,
        public_fit = false,
        fit_ready = false,
        cache_enabled = false,
        target = :_mgmfrm_free_latent_correlation_2d_logdensity,
        ad_backend,
        n_raw_parameters = nparams,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        correlation = _mgmfrm_free_latent_correlation_2d_state(target, raw),
        logdensity,
        gradient = copy(gradient),
        finite_difference_rows = rows,
        likelihood_identity = (;
            base = base_loglikelihood,
            candidate = candidate_loglikelihood,
            abs_error = likelihood_abs_error,
            passed = likelihood_abs_error <= 1e-12,
        ),
        summary = (;
            flag = passed ? :ok : :candidate_diagnostic_failure,
            passed,
            n_checked = length(rows),
            n_failed,
            finite_logdensity = isfinite(logdensity),
            finite_gradient,
            max_abs_error = isempty(rows) ? missing :
                maximum(row.abs_error for row in rows),
            max_tolerance = isempty(rows) ? missing :
                maximum(row.tolerance for row in rows),
        ),
    )
end

function _mgmfrm_free_latent_correlation_2d_diagnostics(
        spec::FacetSpec,
        raw_params::AbstractVector;
        prior::_SourceFixturePrior = _SourceFixturePrior(),
        lkj_eta = 2,
        kwargs...)
    target = _mgmfrm_free_latent_correlation_2d_logdensity(
        spec;
        prior,
        lkj_eta,
    )
    return _mgmfrm_free_latent_correlation_2d_diagnostics(
        target,
        raw_params;
        kwargs...,
    )
end

function _mgmfrm_free_latent_correlation_2d_sample_bundle(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity,
        raw_initial::AbstractVector = initial_params(target);
        ndraws::Int = 8,
        warmup::Int = 8,
        chains::Int = 1,
        step_size::Real = 0.03,
        rng::AbstractRNG = Random.default_rng(),
        seed = nothing,
        target_accept::Real = 0.8,
        max_depth::Int = 4,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :unit,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        chain_initials = nothing,
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
        throw(ArgumentError(
            "max_energy_error must be finite and positive",
        ))
    isfinite(init_jitter) && init_jitter >= 0 ||
        throw(ArgumentError("init_jitter must be finite and non-negative"))
    gradient_backend = _gradient_backend_kind(ad_backend)
    _check_source_fixture_raw_vector(target, raw_initial)
    initial = Float64.(collect(raw_initial))
    initial_logdensity = LogDensityProblems.logdensity(target, initial)
    isfinite(initial_logdensity) || throw(ArgumentError(
        "initial raw parameter vector has non-finite log density",
    ))

    fit_rng, rng_control = _fit_rng(rng, seed)
    nparams = LogDensityProblems.dimension(target)
    supplied_chain_initials = if chain_initials === nothing
        nothing
    else
        chain_initials isa AbstractMatrix || throw(ArgumentError(
            "chain_initials must be nothing or a chains-by-parameters matrix",
        ))
        size(chain_initials) == (chains, nparams) || throw(ArgumentError(
            "chain_initials has size $(size(chain_initials)); expected " *
            "($chains, $nparams)",
        ))
        iszero(init_jitter) || throw(ArgumentError(
            "init_jitter must be zero when explicit chain_initials are supplied",
        ))
        converted = try
            Matrix{Float64}(chain_initials)
        catch
            throw(ArgumentError(
                "chain_initials must contain values convertible to Float64",
            ))
        end
        all(isfinite, converted) || throw(ArgumentError(
            "chain_initials contains non-finite values",
        ))
        converted
    end
    total_draws = ndraws * chains
    draws = Matrix{Float64}(undef, total_draws, nparams)
    logdensities = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    chain_acceptance_rate = Vector{Float64}(undef, chains)
    actual_chain_initials = Matrix{Float64}(undef, chains, nparams)
    chain_initial_logdensity = Vector{Float64}(undef, chains)
    sampler_stats = NamedTuple[]

    for chain in 1:chains
        chain_initial = supplied_chain_initials === nothing ?
            _advancedhmc_initial(
                initial,
                fit_rng,
                Float64(init_jitter),
            ) : copy(@view supplied_chain_initials[chain, :])
        actual_chain_initials[chain, :] .= chain_initial
        chain_initial_logdensity[chain] =
            LogDensityProblems.logdensity(target, chain_initial)
        isfinite(chain_initial_logdensity[chain]) ||
            throw(ArgumentError(
                "chain $chain initial raw parameter vector has non-finite " *
                "log density",
            ))
        gradient_target = _logdensity_gradient_target(
            target,
            chain_initial,
            ad_backend,
        ).target
        metric_object = _advancedhmc_metric(metric, nparams)
        hamiltonian = AdvancedHMC.Hamiltonian(
            metric_object,
            x -> LogDensityProblems.logdensity(gradient_target, x),
            x -> LogDensityProblems.logdensity_and_gradient(
                gradient_target,
                x,
            ),
        )
        integrator = AdvancedHMC.Leapfrog(Float64(step_size))
        kernel = AdvancedHMC.HMCKernel(
            AdvancedHMC.Trajectory{AdvancedHMC.MultinomialTS}(
                integrator,
                AdvancedHMC.GeneralisedNoUTurn(
                    max_depth,
                    Float64(max_energy_error),
                ),
            ),
        )
        adaptor = warmup > 0 ?
            AdvancedHMC.StanHMCAdaptor(
                AdvancedHMC.MassMatrixAdaptor(metric_object),
                AdvancedHMC.StepSizeAdaptor(
                    Float64(target_accept),
                    integrator,
                ),
            ) : AdvancedHMC.NoAdaptation()
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
        length(samples) == ndraws || throw(ArgumentError(
            "AdvancedHMC returned $(length(samples)) draw(s); " *
            "expected $ndraws",
        ))
        length(stats) == ndraws || throw(ArgumentError(
            "AdvancedHMC returned $(length(stats)) sampler-stat row(s); " *
            "expected $ndraws",
        ))
        chain_stats = NamedTuple[]
        for iteration in 1:ndraws
            row = (chain - 1) * ndraws + iteration
            draws[row, :] .= samples[iteration]
            stat_row = _advancedhmc_stat_row(
                stats[iteration],
                chain,
                iteration,
            )
            logdensities[row] = stat_row.log_density
            chain_ids[row] = chain
            iterations[row] = iteration
            push!(chain_stats, stat_row)
            push!(sampler_stats, stat_row)
        end
        chain_acceptance_rate[chain] =
            _stat_mean(chain_stats, :acceptance_rate)
    end

    base_draws = Matrix(@view draws[:, target.blueprint.base_parameter_range])
    direct = _mgmfrm_guarded_local_fit_direct_draw_values(
        target.base,
        base_draws,
    )
    direct_constraint_rows =
        _mgmfrm_guarded_local_fit_direct_draw_constraint_rows(
            target.base.design,
            direct.direct_draws,
        )
    zrho_draws = copy(@view draws[:, target.blueprint.zrho_index])
    rho_draws = tanh.(zrho_draws)
    pointwise_loglikelihood = Matrix{Float64}(
        undef,
        total_draws,
        target.base.design.spec.data.n,
    )
    candidate_loglikelihood = [
        begin
            raw_draw = @view draws[row, :]
            pointwise =
                _mgmfrm_free_latent_correlation_2d_pointwise_loglikelihood(
                    target,
                    raw_draw,
                )
            pointwise_loglikelihood[row, :] .= pointwise
            _mgmfrm_free_latent_correlation_2d_loglikelihood(
                target,
                raw_draw,
            )
        end
        for row in axes(draws, 1)
    ]
    pointwise_sum_abs_error = [
        abs(
            sum(@view(pointwise_loglikelihood[row, :]); init = 0.0) -
            candidate_loglikelihood[row],
        )
        for row in axes(draws, 1)
    ]
    direct_pointwise_abs_error = abs.(
        pointwise_loglikelihood .- direct.pointwise_loglikelihood,
    )
    likelihood_abs_error = abs.(
        candidate_loglikelihood .- direct.loglikelihood,
    )
    reevaluated_logdensity = [
        LogDensityProblems.logdensity(target, @view(draws[row, :]))
        for row in axes(draws, 1)
    ]
    logdensity_revalidation_rows = [
        begin
            sampled = logdensities[row]
            reevaluated = reevaluated_logdensity[row]
            abs_error = abs(sampled - reevaluated)
            tolerance = 1e-10 + 1e-10 *
                max(abs(sampled), abs(reevaluated), 1.0)
            (;
                row,
                sampled,
                reevaluated,
                abs_error,
                tolerance,
                passed = isfinite(sampled) && isfinite(reevaluated) &&
                    abs_error <= tolerance,
            )
        end
        for row in eachindex(logdensities)
    ]
    sampler_rows = [
        merge((; chain), _candidate_chain_sampler_summary(
            [row for row in sampler_stats if row.chain == chain],
            max_depth,
        ))
        for chain in 1:chains
    ]
    n_numerical_errors = count(row -> row.numerical_error, sampler_stats)
    n_failed_direct_constraints =
        sum(row.n_failed for row in direct_constraint_rows)
    sampler_stats_length_valid = length(sampler_stats) == total_draws
    sampler_stats_layout_valid = sampler_stats_length_valid && all(
        index -> sampler_stats[index].chain == chain_ids[index] &&
            sampler_stats[index].iteration == iterations[index],
        eachindex(sampler_stats),
    )
    chain_acceptance_rate_finite =
        length(chain_acceptance_rate) == chains && all(
            value -> isfinite(value) && 0 <= value <= 1,
            chain_acceptance_rate,
        )
    sampler_telemetry_finite = sampler_stats_length_valid && all(
        row -> all(isfinite, (
            row.acceptance_rate,
            row.log_density,
            row.hamiltonian_energy,
            row.hamiltonian_energy_error,
            row.max_hamiltonian_energy_error,
            row.step_size,
            row.nom_step_size,
        )),
        sampler_stats,
    )
    sampler_telemetry_valid = sampler_telemetry_finite && all(
        row -> 0 <= row.acceptance_rate <= 1 && row.n_steps >= 1 &&
            row.tree_depth >= 0 && row.step_size > 0 &&
            row.nom_step_size > 0,
        sampler_stats,
    )
    logdensity_revalidation_passed =
        all(row -> row.passed, logdensity_revalidation_rows)
    raw_draws_finite = all(isfinite, draws)
    logdensity_finite = all(isfinite, logdensities)
    reevaluated_logdensity_finite = all(isfinite, reevaluated_logdensity)
    pointwise_loglikelihood_finite = all(isfinite, pointwise_loglikelihood)
    chain_initials_finite = all(isfinite, actual_chain_initials)
    chain_initial_logdensity_finite = all(isfinite, chain_initial_logdensity)
    chain_initials_shape_valid =
        size(actual_chain_initials) == (chains, nparams)
    direct_payload_finite = all(isfinite, direct.direct_draws) &&
        all(isfinite, direct.pointwise_loglikelihood) &&
        all(isfinite, direct.loglikelihood)
    finite_payload = raw_draws_finite && logdensity_finite &&
        reevaluated_logdensity_finite &&
        pointwise_loglikelihood_finite && direct_payload_finite
    rho_in_bounds = all(value -> -1 < value < 1, rho_draws)
    maximum_likelihood_abs_error = maximum(likelihood_abs_error)
    maximum_pointwise_sum_abs_error = maximum(pointwise_sum_abs_error)
    maximum_direct_pointwise_abs_error = maximum(direct_pointwise_abs_error)
    passed = finite_payload && chain_initials_finite &&
        chain_initial_logdensity_finite && chain_initials_shape_valid &&
        rho_in_bounds && n_numerical_errors == 0 &&
        n_failed_direct_constraints == 0 &&
        sampler_stats_length_valid && sampler_stats_layout_valid &&
        chain_acceptance_rate_finite && sampler_telemetry_valid &&
        logdensity_revalidation_passed &&
        maximum_likelihood_abs_error <= 1e-10 &&
        maximum_pointwise_sum_abs_error <= 1e-10 &&
        maximum_direct_pointwise_abs_error <= 1e-10
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
        chain_initial_policy = supplied_chain_initials === nothing ?
            :shared_base_with_optional_rng_jitter : :explicit_matrix,
        chain_initials_supplied = supplied_chain_initials !== nothing,
    )
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_sample_bundle.v1",
        family = :mgmfrm,
        scope = :mgmfrm_2d_free_latent_correlation_candidate,
        status = :internal_execution_smoke,
        backend = :advancedhmc,
        sampler = :nuts,
        diagnostic_status = :not_evaluable_smoke,
        claim_scope = :execution_smoke_not_recovery,
        public_fit = false,
        fit_ready = false,
        cache_enabled = false,
        result_type = :named_tuple_only,
        convergence_evaluated = false,
        recovery_verified = false,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        initial_raw_parameter_values = copy(initial),
        initial_logdensity,
        chain_initials = actual_chain_initials,
        chain_initial_logdensity,
        draws,
        base_draws,
        zrho_draws,
        rho_draws,
        logdensity = logdensities,
        reevaluated_logdensity,
        pointwise_loglikelihood,
        direct_draws = direct.direct_draws,
        direct_pointwise_loglikelihood = direct.pointwise_loglikelihood,
        direct_loglikelihood = direct.loglikelihood,
        candidate_loglikelihood,
        chain_ids,
        iterations,
        chain_acceptance_rate,
        sampler_controls = controls,
        sampler_stats,
        sampler_rows,
        logdensity_revalidation = (;
            rows = logdensity_revalidation_rows,
            max_abs_error = maximum(
                row.abs_error for row in logdensity_revalidation_rows
            ),
            passed = logdensity_revalidation_passed,
        ),
        direct_constraint_rows,
        likelihood_identity = (;
            max_abs_error = maximum_likelihood_abs_error,
            passed = maximum_likelihood_abs_error <= 1e-10,
        ),
        pointwise_identity = (;
            max_sum_abs_error = maximum_pointwise_sum_abs_error,
            max_direct_abs_error = maximum_direct_pointwise_abs_error,
            passed = maximum_pointwise_sum_abs_error <= 1e-10 &&
                maximum_direct_pointwise_abs_error <= 1e-10,
        ),
        summary = (;
            flag = passed ? :ok : :execution_smoke_failure,
            passed,
            total_draws,
            n_parameters = nparams,
            finite_payload,
            raw_draws_finite,
            logdensity_finite,
            reevaluated_logdensity_finite,
            pointwise_loglikelihood_finite,
            chain_initials_finite,
            chain_initial_logdensity_finite,
            chain_initials_shape_valid,
            direct_payload_finite,
            rho_in_bounds,
            n_numerical_errors,
            n_failed_direct_constraints,
            sampler_stats_length_valid,
            sampler_stats_layout_valid,
            chain_acceptance_rate_finite,
            sampler_telemetry_finite,
            sampler_telemetry_valid,
            logdensity_revalidation_passed,
        ),
    )
end

function _free_correlation_weighted_quantile(
        values::AbstractVector{<:Real},
        weights::AbstractVector{<:Real},
        probability::Float64)
    cumulative = 0.0
    for index in eachindex(values, weights)
        cumulative += Float64(weights[index])
        cumulative >= probability && return Float64(values[index])
    end
    return Float64(last(values))
end

function _mgmfrm_free_latent_correlation_2d_oracle_profile(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity,
        base_raw::AbstractVector;
        zrho_grid = range(-4.0, 4.0; length = 1601),
        interval::Real = 0.9,
        truth_rho = nothing)
    _check_source_fixture_raw_vector(target.base, base_raw)
    checked_interval = Float64(interval)
    0 < checked_interval < 1 ||
        throw(ArgumentError("interval must be in (0, 1)"))
    grid = Float64.(collect(zrho_grid))
    length(grid) >= 3 ||
        throw(ArgumentError("zrho_grid must contain at least three points"))
    all(isfinite, grid) ||
        throw(ArgumentError("zrho_grid must contain only finite values"))
    all(>(0), diff(grid)) ||
        throw(ArgumentError("zrho_grid must be strictly increasing"))
    checked_truth = if truth_rho === nothing
        nothing
    else
        truth_rho isa Bool &&
            throw(ArgumentError("truth_rho must be a real value in (-1, 1)"))
        truth_rho isa Real ||
            throw(ArgumentError("truth_rho must be a real value in (-1, 1)"))
        value = Float64(truth_rho)
        isfinite(value) && -1 < value < 1 ||
            throw(ArgumentError("truth_rho must be finite and in (-1, 1)"))
        value
    end

    quadrature_width = Vector{Float64}(undef, length(grid))
    quadrature_width[1] = 0.5 * (grid[2] - grid[1])
    quadrature_width[end] = 0.5 * (grid[end] - grid[end - 1])
    for index in 2:(length(grid) - 1)
        quadrature_width[index] = 0.5 * (grid[index + 1] - grid[index - 1])
    end
    log_profile = Vector{Float64}(undef, length(grid))
    raw = Vector{Float64}(undef, target.blueprint.n_parameters)
    raw[target.blueprint.base_parameter_range] .= base_raw
    for index in eachindex(grid)
        raw[target.blueprint.zrho_index] = grid[index]
        log_profile[index] =
            _mgmfrm_free_latent_correlation_2d_logprior(target, raw)
    end
    log_mass = log_profile .+ log.(quadrature_width)
    maximum_log_mass = maximum(log_mass)
    mass = exp.(log_mass .- maximum_log_mass)
    weights = mass ./ sum(mass; init = 0.0)
    rho_grid = tanh.(grid)
    log_determinant_grid = _log_one_minus_tanh_squared.(grid)
    rho_density_log_profile = log_profile .- log_determinant_grid
    alpha = (1 - checked_interval) / 2
    posterior_mean = sum(weights .* rho_grid; init = 0.0)
    posterior_median =
        _free_correlation_weighted_quantile(rho_grid, weights, 0.5)
    posterior_lower =
        _free_correlation_weighted_quantile(rho_grid, weights, alpha)
    posterior_upper = _free_correlation_weighted_quantile(
        rho_grid,
        weights,
        1 - alpha,
    )
    strict_positive_probability = sum(
        weights[index]
        for index in eachindex(weights)
        if rho_grid[index] > 0;
        init = 0.0,
    )
    strict_negative_probability = sum(
        weights[index]
        for index in eachindex(weights)
        if rho_grid[index] < 0;
        init = 0.0,
    )
    zero_node_mass = sum(
        weights[index]
        for index in eachindex(weights)
        if iszero(rho_grid[index]);
        init = 0.0,
    )
    positive_probability = strict_positive_probability + 0.5 * zero_node_mass
    negative_probability = strict_negative_probability + 0.5 * zero_node_mass
    person_block = target.base.blueprint.blocks[:person]
    theta1 = Float64[base_raw[index]
        for index in first(person_block):2:last(person_block)]
    theta2 = Float64[base_raw[index + 1]
        for index in first(person_block):2:last(person_block)]
    length(theta1) >= 2 && maximum(theta1) > minimum(theta1) &&
        maximum(theta2) > minimum(theta2) || throw(ArgumentError(
        "oracle profile requires variation in both complete latent dimensions",
    ))
    realized_latent_correlation = cor(theta1, theta2)
    isfinite(realized_latent_correlation) || throw(ArgumentError(
        "oracle profile could not compute a finite realized latent correlation",
    ))
    boundary_mass = weights[1] + weights[end]
    truth_in_interval = checked_truth === nothing ? missing :
        posterior_lower <= checked_truth <= posterior_upper
    direction_matches_truth = checked_truth === nothing || checked_truth == 0 ?
        missing : sign(posterior_median) == sign(checked_truth)
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_oracle_profile.v1",
        family = :mgmfrm,
        scope = :mgmfrm_2d_free_latent_correlation_candidate,
        status = :internal_oracle_profile,
        claim_scope = :oracle_complete_latent_profile_not_response_recovery,
        public_fit = false,
        fit_ready = false,
        cache_enabled = false,
        promotion_effect = :none,
        truth_rho = checked_truth,
        realized_latent_correlation,
        interval = checked_interval,
        zrho_grid = grid,
        rho_grid,
        log_determinant_grid,
        log_profile,
        rho_density_log_profile,
        weights,
        boundary_mass,
        posterior = (;
            mean = posterior_mean,
            median = posterior_median,
            lower = posterior_lower,
            upper = posterior_upper,
            mode = rho_grid[argmax(rho_density_log_profile)],
            mode_measure = :rho_density,
            transformed_z_mode = rho_grid[argmax(log_profile)],
            positive_probability,
            negative_probability,
            zero_node_mass,
        ),
        summary = (;
            profile_valid = all(isfinite, weights) &&
                abs(sum(weights; init = 0.0) - 1) <= 1e-12 &&
                boundary_mass <= 1e-4,
            truth_in_interval,
            direction_matches_truth,
            response_recovery_verified = false,
            next_gate = :end_to_end_response_recovery_pilot,
        ),
    )
end
