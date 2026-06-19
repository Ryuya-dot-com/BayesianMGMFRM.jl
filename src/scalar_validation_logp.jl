# scalar_validation_logp.jl -- scalar D=1/I=1 Uto 2021-style validation target
# ==============================================================================
# Reference implementation used for gradient validation while the public
# model-specification API is being developed.

using LinearAlgebra
import LogDensityProblems

const LOG2PI_FAST = log(2 * pi)
# Logistic-to-normal-ogive approximation scale used in the Uto 2021 MGMFRM/GPCM equations.
const UTO_UENO_LOGISTIC_SCALE = 1.7

Base.@kwdef struct ScalarValidationData
    X::Vector{Int}
    examinee::Vector{Int}
    rater::Vector{Int}
    J::Int
    R::Int
    K::Int
    N::Int
end

function ScalarValidationData(data::FacetData)
    length(data.item_levels) == 1 ||
        throw(ArgumentError("ScalarValidationData only supports one item in the current scalar target"))
    return ScalarValidationData(
        X = data.category,
        examinee = data.person,
        rater = data.rater,
        J = length(data.person_levels),
        R = length(data.rater_levels),
        K = length(data.category_levels),
        N = data.n,
    )
end

function ScalarValidationData(data)
    getproperty(data, :I) == 1 || throw(ArgumentError("ScalarValidationData only supports I=1"))
    getproperty(data, :D) == 1 || throw(ArgumentError("ScalarValidationData only supports D=1"))
    return ScalarValidationData(
        X = data.X,
        examinee = data.examinee,
        rater = data.rater,
        J = data.J,
        R = data.R,
        K = data.K,
        N = data.N,
    )
end

scalar_validation_num_params(d::ScalarValidationData) = d.J + 1 + 1 + (d.R - 1) + (d.R - 1) + (d.K - 2)
scalar_validation_contrast_num_params(d::ScalarValidationData) = scalar_validation_num_params(d)

@inline normal01_logpdf_fast(x) = -0.5 * (LOG2PI_FAST + x * x)

@inline function lognormal01_logpdf_from_log_fast(logx)
    # Density of alpha ~ LogNormal(0, 1), evaluated in log(alpha) coordinates.
    # This intentionally includes the -log(alpha) term and matches the Stan fixture.
    return -logx - 0.5 * (LOG2PI_FAST + logx * logx)
end

function scalar_validation_offsets(d::ScalarValidationData)
    o_theta = 1
    o_log_alpha_i = o_theta + d.J
    o_beta_i = o_log_alpha_i + 1
    o_log_alpha_r = o_beta_i + 1
    o_beta_r = o_log_alpha_r + d.R - 1
    o_beta_ik = o_beta_r + d.R - 1
    return (; o_theta, o_log_alpha_i, o_beta_i, o_log_alpha_r, o_beta_r, o_beta_ik)
end

function zerosum_basis_fast(n::Int)
    n <= 1 && return zeros(Float64, n, max(n - 1, 0))
    A = Matrix{Float64}(I, n, n) .- (1.0 / n)
    F = qr(A)
    Q = Matrix(F.Q)[:, 1:(n - 1)]
    for j in 1:(n - 1)
        Q[:, j] .-= sum(@view Q[:, j]) / n
    end
    return Q
end

function _check_length(name::AbstractString, value, expected::Int)
    length(value) == expected ||
        throw(ArgumentError("$name has length $(length(value)); expected $expected"))
    return nothing
end

function _check_approx_zero(name::AbstractString, value; atol = 1e-8)
    abs(value) <= atol ||
        throw(ArgumentError("$name must be approximately zero under the scalar validation constraints; got $value"))
    return nothing
end

function _check_scalar_validation_truth_constraints(truth, d::ScalarValidationData)
    _check_length("truth.theta", truth.theta, d.J)
    _check_length("truth.trans_alpha_r", truth.trans_alpha_r, d.R)
    _check_length("truth.trans_beta_r", truth.trans_beta_r, d.R)
    _check_length("truth.category_est", truth.category_est, d.K - 1)
    all(>(0), truth.trans_alpha_r) ||
        throw(ArgumentError("truth.trans_alpha_r must be strictly positive"))
    _check_approx_zero("sum(log.(truth.trans_alpha_r))", sum(log.(truth.trans_alpha_r)))
    _check_approx_zero("sum(truth.trans_beta_r)", sum(truth.trans_beta_r))
    _check_approx_zero("sum(truth.category_est)", sum(truth.category_est))
    return nothing
end

function scalar_validation_pack_truth(data, truth)
    d = ScalarValidationData(data)
    _check_scalar_validation_truth_constraints(truth, d)
    x = Vector{Float64}(undef, scalar_validation_num_params(d))
    o = scalar_validation_offsets(d)
    x[o.o_theta:(o.o_theta + d.J - 1)] .= truth.theta
    x[o.o_log_alpha_i] = log(truth.alpha_i)
    x[o.o_beta_i] = truth.beta_i
    x[o.o_log_alpha_r:(o.o_log_alpha_r + d.R - 2)] .= log.(truth.trans_alpha_r[2:end])
    x[o.o_beta_r:(o.o_beta_r + d.R - 2)] .= truth.trans_beta_r[2:end]
    x[o.o_beta_ik:(o.o_beta_ik + d.K - 3)] .= truth.category_est[1:(d.K - 2)]
    return x
end

function scalar_validation_pack_truth_contrast(data, truth)
    d = ScalarValidationData(data)
    _check_scalar_validation_truth_constraints(truth, d)
    Qr = zerosum_basis_fast(d.R)
    Qs = zerosum_basis_fast(d.K - 1)
    x = Vector{Float64}(undef, scalar_validation_contrast_num_params(d))
    o = scalar_validation_offsets(d)
    x[o.o_theta:(o.o_theta + d.J - 1)] .= truth.theta
    x[o.o_log_alpha_i] = log(truth.alpha_i)
    x[o.o_beta_i] = truth.beta_i
    x[o.o_log_alpha_r:(o.o_log_alpha_r + d.R - 2)] .= Qr' * log.(truth.trans_alpha_r)
    x[o.o_beta_r:(o.o_beta_r + d.R - 2)] .= Qr' * truth.trans_beta_r
    x[o.o_beta_ik:(o.o_beta_ik + d.K - 3)] .= Qs' * truth.category_est
    return x
end

function scalar_validation_decode(x, d::ScalarValidationData)
    o = scalar_validation_offsets(d)
    theta = reshape(collect(x[o.o_theta:(o.o_theta + d.J - 1)]), 1, d.J)
    alpha_i = reshape([exp(x[o.o_log_alpha_i])], 1, 1)
    beta_i = [x[o.o_beta_i]]

    log_alpha_raw = collect(x[o.o_log_alpha_r:(o.o_log_alpha_r + d.R - 2)])
    beta_r_raw = collect(x[o.o_beta_r:(o.o_beta_r + d.R - 2)])
    trans_alpha_r = vcat(exp(-sum(log_alpha_raw)), exp.(log_alpha_raw))
    trans_beta_r = vcat(-sum(beta_r_raw), beta_r_raw)

    step_raw = collect(x[o.o_beta_ik:(o.o_beta_ik + d.K - 3)])
    category_est = vcat(step_raw, -sum(step_raw))
    category_prm = [cumsum(vcat(0.0, category_est))]

    return (; theta, alpha_i, beta_i, trans_alpha_r, trans_beta_r, category_prm)
end

function scalar_validation_decode_contrast(x, d::ScalarValidationData)
    o = scalar_validation_offsets(d)
    Qr = zerosum_basis_fast(d.R)
    Qs = zerosum_basis_fast(d.K - 1)

    theta = reshape(collect(x[o.o_theta:(o.o_theta + d.J - 1)]), 1, d.J)
    alpha_i = reshape([exp(x[o.o_log_alpha_i])], 1, 1)
    beta_i = [x[o.o_beta_i]]

    log_alpha = Qr * collect(x[o.o_log_alpha_r:(o.o_log_alpha_r + d.R - 2)])
    trans_beta_r = Qr * collect(x[o.o_beta_r:(o.o_beta_r + d.R - 2)])
    category_est = Qs * collect(x[o.o_beta_ik:(o.o_beta_ik + d.K - 3)])
    category_prm = [cumsum(vcat(0.0, category_est))]

    return (; theta, alpha_i, beta_i,
            trans_alpha_r = exp.(log_alpha),
            trans_beta_r,
            category_prm)
end

function scalar_validation_posterior_means(xs, d::ScalarValidationData; parameterization::Symbol = :raw)
    n = length(xs)
    decode = parameterization == :contrast ? scalar_validation_decode_contrast : scalar_validation_decode
    first_pm = decode(first(xs), d)
    theta = zeros(size(first_pm.theta))
    alpha_i = zeros(size(first_pm.alpha_i))
    beta_i = zeros(length(first_pm.beta_i))
    trans_alpha_r = zeros(length(first_pm.trans_alpha_r))
    trans_beta_r = zeros(length(first_pm.trans_beta_r))
    category_prm = [zeros(length(first_pm.category_prm[1]))]

    for x in xs
        pm = decode(x, d)
        theta .+= pm.theta
        alpha_i .+= pm.alpha_i
        beta_i .+= pm.beta_i
        trans_alpha_r .+= pm.trans_alpha_r
        trans_beta_r .+= pm.trans_beta_r
        category_prm[1] .+= pm.category_prm[1]
    end

    return (; theta = theta ./ n,
            alpha_i = alpha_i ./ n,
            beta_i = beta_i ./ n,
            trans_alpha_r = trans_alpha_r ./ n,
            trans_beta_r = trans_beta_r ./ n,
            category_prm = [category_prm[1] ./ n])
end

@inline function scalar_validation_step_logprob_cp(category_prm, scale, score, y::Int, K::Int)
    eta0 = scale * zero(score)
    eta_y = eta0
    max_eta = -Inf
    @inbounds for k in 1:K
        eta = scale * ((k - 1) * score - category_prm[k])
        max_eta = max(max_eta, eta)
        if k == y
            eta_y = eta
        end
    end
    denom = zero(eta0)
    @inbounds for k in 1:K
        eta = scale * ((k - 1) * score - category_prm[k])
        denom += exp(eta - max_eta)
    end
    return eta_y - (max_eta + log(denom))
end

@inline function scalar_validation_step_logprob(x, o_beta_ik::Int, raw_step_sum, scale, score, y::Int, K::Int)
    eta0 = scale * zero(score)
    eta_y = eta0
    prefix = zero(eta0)
    max_eta = -Inf

    @inbounds for k in 1:K
        if k == 1
            cp = zero(eta0)
        elseif k <= K - 1
            prefix += x[o_beta_ik + k - 2]
            cp = prefix
        else
            cp = prefix - raw_step_sum
        end
        eta = scale * ((k - 1) * score - cp)
        max_eta = max(max_eta, eta)
        if k == y
            eta_y = eta
        end
    end

    denom = zero(eta0)
    prefix = zero(eta0)
    @inbounds for k in 1:K
        if k == 1
            cp = zero(eta0)
        elseif k <= K - 1
            prefix += x[o_beta_ik + k - 2]
            cp = prefix
        else
            cp = prefix - raw_step_sum
        end
        eta = scale * ((k - 1) * score - cp)
        denom += exp(eta - max_eta)
    end
    return eta_y - (max_eta + log(denom))
end

function scalar_validation_logposterior(x, d::ScalarValidationData)
    o = scalar_validation_offsets(d)
    lp = zero(x[1])

    @inbounds for j in 1:d.J
        lp += normal01_logpdf_fast(x[o.o_theta + j - 1])
    end

    log_alpha_i = x[o.o_log_alpha_i]
    alpha_i = exp(log_alpha_i)
    beta_i = x[o.o_beta_i]
    lp += normal01_logpdf_fast(log_alpha_i)
    lp += normal01_logpdf_fast(beta_i)

    log_alpha_r_sum = zero(lp)
    beta_r_sum = zero(lp)
    @inbounds for r in 2:d.R
        log_alpha_r_sum += x[o.o_log_alpha_r + r - 2]
        beta_r_sum += x[o.o_beta_r + r - 2]
    end

    log_alpha_r1 = -log_alpha_r_sum
    beta_r1 = -beta_r_sum
    lp += lognormal01_logpdf_from_log_fast(log_alpha_r1)
    lp += normal01_logpdf_fast(beta_r1)
    @inbounds for r in 2:d.R
        lp += lognormal01_logpdf_from_log_fast(x[o.o_log_alpha_r + r - 2])
        lp += normal01_logpdf_fast(x[o.o_beta_r + r - 2])
    end

    raw_step_sum = zero(lp)
    @inbounds for k in 1:(d.K - 2)
        v = x[o.o_beta_ik + k - 1]
        raw_step_sum += v
        lp += normal01_logpdf_fast(v)
    end
    lp += normal01_logpdf_fast(-raw_step_sum)

    @inbounds for n in 1:d.N
        r = d.rater[n]
        log_alpha_r = r == 1 ? log_alpha_r1 : x[o.o_log_alpha_r + r - 2]
        beta_r = r == 1 ? beta_r1 : x[o.o_beta_r + r - 2]
        theta = x[o.o_theta + d.examinee[n] - 1]
        score = alpha_i * theta - beta_i - beta_r
        scale = UTO_UENO_LOGISTIC_SCALE * exp(log_alpha_r)
        lp += scalar_validation_step_logprob(x, o.o_beta_ik, raw_step_sum, scale, score, d.X[n], d.K)
    end

    return lp
end

function scalar_validation_logposterior_and_gradient(x, d::ScalarValidationData)
    o = scalar_validation_offsets(d)
    lp = zero(x[1])
    g = zeros(eltype(x), length(x))

    gamma = Vector{eltype(x)}(undef, d.R)
    beta_r = Vector{eltype(x)}(undef, d.R)
    category_est = Vector{eltype(x)}(undef, d.K - 1)
    category_prm = Vector{eltype(x)}(undef, d.K)
    g_gamma = zeros(eltype(x), d.R)
    g_beta_r = zeros(eltype(x), d.R)
    g_category_est = zeros(eltype(x), d.K - 1)
    eta = Vector{eltype(x)}(undef, d.K)
    prob = Vector{eltype(x)}(undef, d.K)
    gcp = Vector{eltype(x)}(undef, d.K)

    @inbounds for j in 1:d.J
        theta = x[o.o_theta + j - 1]
        lp += normal01_logpdf_fast(theta)
        g[o.o_theta + j - 1] -= theta
    end

    log_alpha_i = x[o.o_log_alpha_i]
    alpha_i = exp(log_alpha_i)
    beta_i = x[o.o_beta_i]
    lp += normal01_logpdf_fast(log_alpha_i)
    lp += normal01_logpdf_fast(beta_i)
    g[o.o_log_alpha_i] -= log_alpha_i
    g[o.o_beta_i] -= beta_i

    gamma_sum = zero(lp)
    beta_sum = zero(lp)
    @inbounds for r in 2:d.R
        gamma[r] = x[o.o_log_alpha_r + r - 2]
        beta_r[r] = x[o.o_beta_r + r - 2]
        gamma_sum += gamma[r]
        beta_sum += beta_r[r]
    end
    gamma[1] = -gamma_sum
    beta_r[1] = -beta_sum

    @inbounds for r in 1:d.R
        lp += lognormal01_logpdf_from_log_fast(gamma[r])
        lp += normal01_logpdf_fast(beta_r[r])
        g_gamma[r] += -one(lp) - gamma[r]
        g_beta_r[r] += -beta_r[r]
    end

    step_sum = zero(lp)
    @inbounds for k in 1:(d.K - 2)
        category_est[k] = x[o.o_beta_ik + k - 1]
        step_sum += category_est[k]
    end
    category_est[d.K - 1] = -step_sum
    category_prm[1] = zero(lp)
    @inbounds for k in 2:d.K
        category_prm[k] = category_prm[k - 1] + category_est[k - 1]
    end
    @inbounds for k in 1:(d.K - 1)
        lp += normal01_logpdf_fast(category_est[k])
        g_category_est[k] -= category_est[k]
    end

    @inbounds for n in 1:d.N
        r = d.rater[n]
        j = d.examinee[n]
        y = d.X[n]
        theta = x[o.o_theta + j - 1]
        score = alpha_i * theta - beta_i - beta_r[r]
        scale = UTO_UENO_LOGISTIC_SCALE * exp(gamma[r])

        max_eta = -Inf
        for k in 1:d.K
            eta[k] = scale * ((k - 1) * score - category_prm[k])
            max_eta = max(max_eta, eta[k])
        end
        denom = zero(lp)
        for k in 1:d.K
            prob[k] = exp(eta[k] - max_eta)
            denom += prob[k]
        end
        lp += eta[y] - (max_eta + log(denom))

        dscore = zero(lp)
        dscale = zero(lp)
        fill!(gcp, zero(lp))
        for k in 1:d.K
            prob[k] /= denom
            w = (k == y ? one(lp) : zero(lp)) - prob[k]
            k0 = k - 1
            dscore += w * k0
            dscale += w * (k0 * score - category_prm[k])
            gcp[k] = -scale * w
        end
        dscore *= scale

        g[o.o_theta + j - 1] += dscore * alpha_i
        g[o.o_log_alpha_i] += dscore * alpha_i * theta
        g[o.o_beta_i] -= dscore
        g_beta_r[r] -= dscore
        g_gamma[r] += dscale * scale

        suffix = zero(lp)
        for k in d.K:-1:2
            suffix += gcp[k]
            g_category_est[k - 1] += suffix
        end
    end

    @inbounds for r in 2:d.R
        g[o.o_log_alpha_r + r - 2] = g_gamma[r] - g_gamma[1]
        g[o.o_beta_r + r - 2] = g_beta_r[r] - g_beta_r[1]
    end
    @inbounds for k in 1:(d.K - 2)
        g[o.o_beta_ik + k - 1] = g_category_est[k] - g_category_est[d.K - 1]
    end

    return lp, g
end

function scalar_validation_logposterior_contrast(x, d::ScalarValidationData,
                                            Qr = zerosum_basis_fast(d.R),
                                            Qs = zerosum_basis_fast(d.K - 1))
    o = scalar_validation_offsets(d)
    lp = zero(x[1])

    @inbounds for j in 1:d.J
        lp += normal01_logpdf_fast(x[o.o_theta + j - 1])
    end

    log_alpha_i = x[o.o_log_alpha_i]
    alpha_i = exp(log_alpha_i)
    beta_i = x[o.o_beta_i]
    lp += normal01_logpdf_fast(log_alpha_i)
    lp += normal01_logpdf_fast(beta_i)

    z_log_alpha_r = @view x[o.o_log_alpha_r:(o.o_log_alpha_r + d.R - 2)]
    z_beta_r = @view x[o.o_beta_r:(o.o_beta_r + d.R - 2)]
    z_step = @view x[o.o_beta_ik:(o.o_beta_ik + d.K - 3)]

    log_alpha_r = Qr * collect(z_log_alpha_r)
    beta_r = Qr * collect(z_beta_r)
    category_est = Qs * collect(z_step)
    category_prm = cumsum(vcat(zero(lp), category_est))

    @inbounds for r in 1:d.R
        lp += lognormal01_logpdf_from_log_fast(log_alpha_r[r])
        lp += normal01_logpdf_fast(beta_r[r])
    end
    @inbounds for k in 1:(d.K - 1)
        lp += normal01_logpdf_fast(category_est[k])
    end

    @inbounds for n in 1:d.N
        r = d.rater[n]
        theta = x[o.o_theta + d.examinee[n] - 1]
        score = alpha_i * theta - beta_i - beta_r[r]
        scale = UTO_UENO_LOGISTIC_SCALE * exp(log_alpha_r[r])
        lp += scalar_validation_step_logprob_cp(category_prm, scale, score, d.X[n], d.K)
    end

    return lp
end

struct ScalarValidationLogDensity
    data::ScalarValidationData
end

struct ScalarValidationContrastLogDensity
    data::ScalarValidationData
    Qr::Matrix{Float64}
    Qs::Matrix{Float64}
end

struct ScalarValidationAnalyticLogDensity
    data::ScalarValidationData
end

ScalarValidationContrastLogDensity(data::ScalarValidationData) =
    ScalarValidationContrastLogDensity(data, zerosum_basis_fast(data.R), zerosum_basis_fast(data.K - 1))

LogDensityProblems.logdensity(p::ScalarValidationLogDensity, x) = scalar_validation_logposterior(x, p.data)
LogDensityProblems.dimension(p::ScalarValidationLogDensity) = scalar_validation_num_params(p.data)
LogDensityProblems.capabilities(::Type{ScalarValidationLogDensity}) = LogDensityProblems.LogDensityOrder{0}()

LogDensityProblems.logdensity(p::ScalarValidationContrastLogDensity, x) =
    scalar_validation_logposterior_contrast(x, p.data, p.Qr, p.Qs)
LogDensityProblems.dimension(p::ScalarValidationContrastLogDensity) = scalar_validation_contrast_num_params(p.data)
LogDensityProblems.capabilities(::Type{ScalarValidationContrastLogDensity}) = LogDensityProblems.LogDensityOrder{0}()

LogDensityProblems.logdensity(p::ScalarValidationAnalyticLogDensity, x) = scalar_validation_logposterior(x, p.data)
LogDensityProblems.dimension(p::ScalarValidationAnalyticLogDensity) = scalar_validation_num_params(p.data)
LogDensityProblems.capabilities(::Type{ScalarValidationAnalyticLogDensity}) = LogDensityProblems.LogDensityOrder{1}()
LogDensityProblems.logdensity_and_gradient(p::ScalarValidationAnalyticLogDensity, x) =
    scalar_validation_logposterior_and_gradient(x, p.data)

function _scalar_validation_float_vector(name::AbstractString, values)
    out = Float64.(collect(values))
    all(isfinite, out) ||
        throw(ArgumentError("$name must contain only finite values"))
    return out
end

function _scalar_validation_float(name::AbstractString, value)
    out = Float64(value)
    isfinite(out) || throw(ArgumentError("$name must be finite"))
    return out
end

function _scalar_validation_optional_symbol(value)
    value === nothing && return nothing
    value isa Symbol && return value
    return Symbol(value)
end

function _scalar_validation_within_tolerance(actual::Real, expected::Real,
        tolerance::Real)
    return isapprox(Float64(actual), Float64(expected);
        atol = Float64(tolerance), rtol = Float64(tolerance))
end

function _scalar_validation_gradient_difference(julia_gradient::AbstractVector{<:Real},
        reference_gradient, name::AbstractString)
    reference_gradient === nothing && return (;
        checked = false,
        max_abs_error = missing,
        finite_reference = missing,
        n_reference_parameters = 0,
    )
    reference = _scalar_validation_float_vector(name, reference_gradient)
    length(reference) == length(julia_gradient) ||
        throw(ArgumentError("$name has length $(length(reference)); expected $(length(julia_gradient))"))
    return (;
        checked = true,
        max_abs_error = maximum(abs.(julia_gradient .- reference)),
        finite_reference = all(isfinite, reference),
        n_reference_parameters = length(reference),
    )
end

"""
    stan_validation_row(data::ScalarValidationData, x, stan_log_density;
        stan_gradient = nothing, tolerance = 1e-9, label = nothing,
        size = nothing, known_log_density = nothing, known_gradient = nothing,
        known_tolerance = tolerance, fixture_path = nothing,
        known_fixture_path = nothing, stan_model = nothing,
        fixture_sha256 = nothing, known_fixture_sha256 = nothing,
        stan_model_sha256 = nothing)

Return one machine-readable validation row comparing the Julia scalar
GMFRM-style validation log density and analytic gradient with a Stan or
BridgeStan fixture evaluated at the same raw parameter vector.

The function deliberately accepts already parsed numeric fixture values instead
of reading JSON files, so the package does not depend on a JSON parser at
runtime. Use [`stan_validation_summary`](@ref) to aggregate rows for the
predeclared small/medium validation gate.
"""
function stan_validation_row(data::ScalarValidationData, x, stan_log_density;
        stan_gradient = nothing,
        tolerance::Real = 1e-9,
        label = nothing,
        size = nothing,
        known_log_density = nothing,
        known_gradient = nothing,
        known_tolerance::Real = tolerance,
        fixture_path = nothing,
        known_fixture_path = nothing,
        stan_model = nothing,
        fixture_sha256 = nothing,
        known_fixture_sha256 = nothing,
        stan_model_sha256 = nothing)
    x_values = _scalar_validation_float_vector("x", x)
    length(x_values) == scalar_validation_num_params(data) ||
        throw(ArgumentError("x has length $(length(x_values)); expected $(scalar_validation_num_params(data))"))
    stan_lp = _scalar_validation_float("stan_log_density", stan_log_density)
    checked_tolerance = _scalar_validation_float("tolerance", tolerance)
    checked_tolerance >= 0 ||
        throw(ArgumentError("tolerance must be non-negative"))
    checked_known_tolerance = _scalar_validation_float("known_tolerance", known_tolerance)
    checked_known_tolerance >= 0 ||
        throw(ArgumentError("known_tolerance must be non-negative"))

    julia_lp, julia_gradient = scalar_validation_logposterior_and_gradient(x_values, data)
    all(isfinite, julia_gradient) ||
        throw(ArgumentError("Julia analytic gradient contains non-finite values"))

    stan_gradient_diff =
        _scalar_validation_gradient_difference(julia_gradient, stan_gradient, "stan_gradient")
    known_gradient_diff =
        _scalar_validation_gradient_difference(julia_gradient, known_gradient, "known_gradient")

    log_density_abs_error = abs(julia_lp - stan_lp)
    log_density_passed =
        _scalar_validation_within_tolerance(julia_lp, stan_lp, checked_tolerance)
    gradient_tolerance = max(checked_tolerance, 1e-9)
    gradient_passed = stan_gradient_diff.checked ?
        stan_gradient_diff.max_abs_error <= gradient_tolerance : missing

    known_checked = known_log_density !== nothing
    known_lp = known_checked ?
        _scalar_validation_float("known_log_density", known_log_density) : missing
    known_log_density_abs_error = known_checked ? abs(julia_lp - known_lp) : missing
    known_log_density_passed = known_checked ?
        _scalar_validation_within_tolerance(
            julia_lp, known_lp, checked_known_tolerance) : missing
    known_gradient_tolerance = max(checked_known_tolerance, 1e-9)
    known_gradient_passed = known_gradient_diff.checked ?
        known_gradient_diff.max_abs_error <= known_gradient_tolerance : missing

    passed = log_density_passed &&
        (!stan_gradient_diff.checked || gradient_passed === true) &&
        (!known_checked || known_log_density_passed === true) &&
        (!known_gradient_diff.checked || known_gradient_passed === true)

    size_value = _scalar_validation_optional_symbol(size)
    label_value = label === nothing ?
        (size_value === nothing ? :scalar_validation : Symbol("scalar_", size_value)) :
        _scalar_validation_optional_symbol(label)

    return (;
        schema = "bayesianmgmfrm.scalar_stan_validation_row.v1",
        object = :stan_validation_row,
        model_family = :scalar_gmfrm,
        validation_target = :scalar_logdensity_gradient,
        label = label_value,
        size = size_value,
        fixture_path,
        known_fixture_path,
        stan_model,
        fixture_sha256,
        known_fixture_sha256,
        stan_model_sha256,
        n_persons = data.J,
        n_raters = data.R,
        n_categories = data.K,
        n_observations = data.N,
        n_parameters = length(x_values),
        julia_log_density = julia_lp,
        stan_log_density = stan_lp,
        log_density_abs_error,
        log_density_tolerance = checked_tolerance,
        log_density_passed,
        gradient_checked = stan_gradient_diff.checked,
        gradient_max_abs_error = stan_gradient_diff.max_abs_error,
        gradient_tolerance,
        gradient_passed,
        n_gradient_parameters = stan_gradient_diff.n_reference_parameters,
        known_log_density_checked = known_checked,
        known_log_density = known_lp,
        known_log_density_abs_error,
        known_log_density_tolerance = checked_known_tolerance,
        known_log_density_passed,
        known_gradient_checked = known_gradient_diff.checked,
        known_gradient_max_abs_error = known_gradient_diff.max_abs_error,
        known_gradient_tolerance,
        known_gradient_passed,
        finite_julia_log_density = isfinite(julia_lp),
        finite_julia_gradient = all(isfinite, julia_gradient),
        finite_stan_log_density = isfinite(stan_lp),
        finite_stan_gradient = stan_gradient_diff.checked ?
            stan_gradient_diff.finite_reference : missing,
        passed,
        caveat = :fixture_logdensity_gradient_not_full_sampler_comparison,
    )
end

function _stan_validation_summary_row_check(row)
    required = (
        :passed,
        :size,
        :n_observations,
        :n_parameters,
        :log_density_abs_error,
        :gradient_checked,
        :gradient_max_abs_error,
    )
    missing_fields = [name for name in required if !(name in keys(row))]
    isempty(missing_fields) ||
        throw(ArgumentError("stan validation row is missing fields: $(join(missing_fields, ", "))"))
    return nothing
end

function _stan_validation_error_values(rows, field::Symbol)
    values = Float64[]
    for row in rows
        value = getproperty(row, field)
        value === missing && continue
        push!(values, Float64(value))
    end
    return values
end

"""
    stan_validation_summary(rows; required_sizes = (:small, :medium))
    stan_validation_summary(row, rows...; required_sizes = (:small, :medium))

Aggregate `stan_validation_row` results into a gate-level summary. By default,
the gate requires both `:small` and `:medium` scalar Stan/BridgeStan fixtures
to be present and passing. The returned summary explicitly records that this
evidence is a scalar log-density/gradient fixture check, not a broad Stan
sampling or generalized-fit comparison.
"""
function stan_validation_summary(rows::AbstractVector;
        required_sizes = (:small, :medium))
    isempty(rows) && throw(ArgumentError("at least one stan validation row is required"))
    for row in rows
        row isa NamedTuple ||
            throw(ArgumentError("stan validation summary expects NamedTuple rows"))
        _stan_validation_summary_row_check(row)
    end

    observed_sizes = sort([
            getproperty(row, :size)
            for row in rows
            if getproperty(row, :size) !== nothing
        ]; by = string)
    required = sort([
            _scalar_validation_optional_symbol(size)
            for size in collect(required_sizes)
            if _scalar_validation_optional_symbol(size) !== nothing
        ]; by = string)
    missing_required = sort(setdiff(Set(required), Set(observed_sizes)) |> collect;
        by = string)
    passed_rows = count(row -> getproperty(row, :passed) === true, rows)
    log_density_errors = _stan_validation_error_values(rows, :log_density_abs_error)
    gradient_errors = _stan_validation_error_values(rows, :gradient_max_abs_error)

    return (;
        schema = "bayesianmgmfrm.stan_validation_summary.v1",
        object = :stan_validation_summary,
        validation_scope = :scalar_small_medium_bridge_logdensity_gradient,
        n_rows = length(rows),
        n_passed_rows = passed_rows,
        all_rows_passed = passed_rows == length(rows),
        required_sizes = Tuple(required),
        observed_sizes = Tuple(observed_sizes),
        missing_required_sizes = Tuple(missing_required),
        all_required_sizes_present = isempty(missing_required),
        n_observations_minimum = minimum(row.n_observations for row in rows),
        n_observations_maximum = maximum(row.n_observations for row in rows),
        n_parameters_minimum = minimum(row.n_parameters for row in rows),
        n_parameters_maximum = maximum(row.n_parameters for row in rows),
        max_log_density_abs_error = isempty(log_density_errors) ?
            missing : maximum(log_density_errors),
        max_gradient_abs_error = isempty(gradient_errors) ?
            missing : maximum(gradient_errors),
        all_gradient_checked = all(row -> getproperty(row, :gradient_checked), rows),
        passed = passed_rows == length(rows) && isempty(missing_required),
        caveat = :scalar_fixture_logdensity_gradient_not_generalized_fit_claim,
        generalized_fit_comparison_status = :not_claimed,
        next_gate = :generalized_small_medium_fit_comparison,
    )
end

function stan_validation_summary(row::NamedTuple, rows::NamedTuple...;
        required_sizes = (:small, :medium))
    return stan_validation_summary([row; collect(rows)]; required_sizes)
end
