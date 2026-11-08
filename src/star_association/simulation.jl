function _rand_gamma(rng::AbstractRNG, alpha::Float64)
    alpha > 0.0 || throw(ArgumentError("alpha must be > 0"))
    if alpha < 1.0
        u = clamp(rand(rng, Float64), floatmin(Float64), 1.0)
        return _rand_gamma(rng, alpha + 1.0) * (u^(1.0 / alpha))
    end
    d = alpha - 1.0 / 3.0
    c = 1.0 / sqrt(9.0 * d)
    while true
        x = randn(rng, Float64)
        v = 1.0 + c * x
        v <= 0.0 && continue
        v3 = v * v * v
        u = clamp(rand(rng, Float64), floatmin(Float64), 1.0)
        if u < 1.0 - 0.0331 * (x^4) || log(u) < 0.5 * x * x + d * (1.0 - v3 + log(v3))
            return d * v3
        end
    end
end

function _sample_lkj_unconstrained!(
    rng::AbstractRNG,
    dest::AbstractVector{Float64},
    D::Int,
    eta::Float64,
)
    k = 0
    for i in 2:D, j in 1:(i - 1)
        k += 1
        a = eta + ((D - 1) - j) / 2.0
        g1 = _rand_gamma(rng, a)
        g2 = _rand_gamma(rng, a)
        u = clamp(g1 / (g1 + g2), 1e-15, 1.0 - 1e-15)
        dest[k] = atanh(2.0 * u - 1.0)
    end
    return dest
end

"""
    prior_draw(m::StarModel; seed=nothing, rng=nothing)

Draw an exact sample `q` from the normalized joint prior of `m` under its active
parameterization (`:cp`, `:ncp`, or `:cp_ncp`), `basis_order`, and `reference_prior` setting.
"""
function prior_draw(
    m::StarModel;
    seed::Union{Nothing, Integer} = nothing,
    rng::Union{Nothing, AbstractRNG} = nothing,
)
    gen = rng !== nothing ? rng : (seed !== nothing ? Xoshiro(Int(seed)) : Xoshiro(20261030))
    b = _layout(m)
    p = m.prior
    q_ncp = zeros(Float64, b.dim)
    q_ncp[b.zi] .= randn(gen, length(b.zi))
    q_ncp[b.zr] .= randn(gen, length(b.zr))
    for c in 1:m.D
        if !isempty(b.steps[c])
            q_ncp[b.steps[c]] .= randn(gen, length(b.steps[c]))
        end
    end
    q_ncp[b.mu] .= p.mu_sd .* randn(gen, m.D)
    q_ncp[b.si] .= p.entity_log_sd_mean .+ p.log_sd_sd .* randn(gen, m.D)
    q_ncp[b.sr] .= p.rater_log_sd_mean .+ p.log_sd_sd .* randn(gen, m.D)
    _sample_lkj_unconstrained!(gen, view(q_ncp, b.ci), m.D, p.entity_lkj_eta)
    _sample_lkj_unconstrained!(gen, view(q_ncp, b.cr), m.D, p.rater_lkj_eta)
    if m.spec.include_phi
        q_ncp[b.phi] .= p.phi_sd .* randn(gen, length(b.phi))
    end
    return from_ncp_reference(m, q_ncp)
end

function _sample_categorical_rng(rng::AbstractRNG, probs::AbstractVector{Float64}, K::Int)
    u = rand(rng, Float64)
    cum = 0.0
    @inbounds for k in 1:(K - 1)
        cum += probs[k]
        u <= cum && return k - 1
    end
    return K - 1
end

function _simulate_dataset_from_coords(rng::AbstractRNG, m::StarModel, v)
    N = length(m.entity)
    m0 = m.M[1]
    y_can = Matrix{Int}(undef, m.D, N)
    s_scr = _scratch(m.M, Float64)
    eta = zeros(Float64, m.D)
    @inbounds for e in 1:N
        i = m.entity[e]
        r = m.rater[e]
        for c in 1:m.D
            eta[c] = v.mu[c] + v.A[i, c] - v.S[r, c]
        end
        _event_kernel!(s_scr, eta, v.tau, v.phi, m.M)
        y0 = _sample_categorical_rng(rng, view(s_scr.pm, 1:(m0 + 1), 1), m0 + 1)
        y_can[1, e] = y0
        for c in 2:m.D
            mc = m.M[c]
            y_can[c, e] = _sample_categorical_rng(
                rng,
                view(s_scr.cond, 1:(mc + 1), y0 + 1, c - 1),
                mc + 1,
            )
        end
    end
    return y_can
end

function _simulated_long_rows(m::StarModel, y_can::Matrix{Int})
    N = length(m.entity)
    rows = Vector{NamedTuple}(undef, N * m.D)
    pos = 0
    for e in 1:N, c in 1:m.D
        pos += 1
        rows[pos] = (;
            observation_id = "$(m.event_ids[e])::$(m.criteria[c].id)",
            rating_event_id = m.event_ids[e],
            entity = m.entity_levels[m.entity[e]],
            rater = m.rater_levels[m.rater[e]],
            criterion = m.criteria[c].id,
            score = m.criteria[c].canonical_to_raw[y_can[c, e] + 1],
        )
    end
    return rows
end

"""
    simulate(m::StarModel; seed=20261030, q=nothing, include_rows=true)

Simulate a synthetic dataset on `m`'s exact rating design mask from supplied `q` or a fresh
`prior_draw`, returning `(; seed, model, q, y_canonical, rows, truth)` for recovery or SBC studies.
`generate` is provided as a backward-compatible alias.
"""
function simulate(
    m::StarModel;
    seed::Integer = 20261030,
    q::Union{Nothing, AbstractVector{<:Real}} = nothing,
    include_rows::Bool = true,
)
    rng = Xoshiro(Int(seed))
    q_vec = q === nothing ? prior_draw(m; rng) : Float64.(collect(q))
    length(q_vec) == m.dim || throw(DimensionMismatch("expected q of length $(m.dim)"))
    v = _coordinates(m, q_vec; raw_input = false)
    v_ref = _coordinates(m, q_vec; raw_input = true)
    y_can = _simulate_dataset_from_coords(rng, m, v)
    sim_model = StarModel(
        m.I, m.R, m.D, m.M, m.entity, m.rater, y_can,
        m.entity_levels, m.rater_levels, m.event_ids, m.criteria,
        m.prior, m.spec, m.entity_basis, m.rater_basis, m.dim,
    )
    ri = Matrix(C.correlation_state(q_vec[v.b.ci], m.D; eta = m.prior.entity_lkj_eta).R)
    rr = Matrix(C.correlation_state(q_vec[v.b.cr], m.D; eta = m.prior.rater_lkj_eta).R)
    truth = (;
        A = v.A,
        S = v.S,
        tau = v.tau,
        reference_tau = v_ref.tau,
        mu = v.mu,
        reference_mu = v_ref.mu,
        phi = v.phi,
        entity_sd = exp.(q_vec[v.b.si]),
        rater_sd = exp.(q_vec[v.b.sr]),
        R_entity = ri,
        R_rater = rr,
    )
    return (;
        seed = Int(seed),
        model = sim_model,
        q = q_vec,
        y_canonical = y_can,
        rows = include_rows ? _simulated_long_rows(m, y_can) : nothing,
        truth,
    )
end

generate(m::StarModel; kwargs...) = simulate(m; kwargs...)

function _accumulate_prior_draw!(
    ref_pm,
    cat_rates,
    cross_covs,
    r_ent_1c,
    rng::AbstractRNG,
    m::StarModel,
    s::Int,
    q_s::Vector{Float64},
)
    N = length(m.entity)
    m0 = m.M[1]
    v = _coordinates(m, q_s; raw_input = false)
    s_scr = _scratch(m.M, Float64)
    _event_kernel!(s_scr, v.mu, v.tau, v.phi, m.M)
    for c in 1:m.D, k in 0:m.M[c]
        ref_pm[c][s, k + 1] = s_scr.pm[k + 1, c]
    end
    y_can = _simulate_dataset_from_coords(rng, m, v)
    for c in 1:m.D, k in 0:m.M[c]
        cat_rates[c][s, k + 1] = count(==(k), view(y_can, c, :)) / N
    end
    for c in 2:m.D
        mc = m.M[c]
        cross_covs[s, c - 1] = mean(
            (y_can[1, e] / m0 - 0.5) * (y_can[c, e] / mc - 0.5) for e in 1:N
        )
    end
    ri = C.correlation_state(q_s[v.b.ci], m.D; eta = m.prior.entity_lkj_eta).R
    for c in 2:m.D
        r_ent_1c[s, c - 1] = ri[c, 1]
    end
    return nothing
end

"""
    prior_predictive_check(m::StarModel; ndraws=100, seed=20261030)

Evaluate prior predictive category rates, reference-profile (`A=0, S=0`) category probabilities,
within-event cross-covariances, and root-branch trait correlations before running MCMC.
"""
function prior_predictive_check(m::StarModel; ndraws::Int = 100, seed::Integer = 20261030)
    ndraws >= 5 || throw(ArgumentError("ndraws >= 5 required"))
    rng = Xoshiro(Int(seed))
    ref_pm = [zeros(Float64, ndraws, m.M[c] + 1) for c in 1:m.D]
    cat_rates = [zeros(Float64, ndraws, m.M[c] + 1) for c in 1:m.D]
    cross_covs = zeros(Float64, ndraws, m.D - 1)
    r_ent_1c = zeros(Float64, ndraws, m.D - 1)
    for s in 1:ndraws
        _accumulate_prior_draw!(ref_pm, cat_rates, cross_covs, r_ent_1c, rng, m, s, prior_draw(m; rng))
    end
    categories = [
        (;
            criterion = m.criteria[c].id,
            raw_score = m.criteria[c].canonical_to_raw[k + 1],
            reference_prob_mean = mean(view(ref_pm[c], :, k + 1)),
            pred_rate_mean = mean(view(cat_rates[c], :, k + 1)),
            pred_rate_q05 = quantile(view(cat_rates[c], :, k + 1), 0.05),
            pred_rate_q50 = quantile(view(cat_rates[c], :, k + 1), 0.50),
            pred_rate_q95 = quantile(view(cat_rates[c], :, k + 1), 0.95),
        ) for c in 1:m.D for k in 0:m.M[c]
    ]
    branches = [
        (;
            branch = m.criteria[c].id,
            cross_cov_mean = mean(view(cross_covs, :, c - 1)),
            cross_cov_q05 = quantile(view(cross_covs, :, c - 1), 0.05),
            cross_cov_q95 = quantile(view(cross_covs, :, c - 1), 0.95),
            prior_R_entity_mean = mean(view(r_ent_1c, :, c - 1)),
            prior_R_entity_sd = std(view(r_ent_1c, :, c - 1)),
        ) for c in 2:m.D
    ]
    return (;
        ndraws,
        seed = Int(seed),
        prior = _prior_namedtuple(m.prior),
        reference_prior = m.spec.reference_prior,
        include_phi = m.spec.include_phi,
        categories,
        branches,
    )
end
