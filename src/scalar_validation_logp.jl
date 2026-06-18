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
