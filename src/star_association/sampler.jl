struct SamplerConfig
    ndraws::Int
    warmup::Int
    chains::Int
    seeds::Vector{Int}
    init::Symbol
    init_radius::Float64
    adaptation::Symbol
    initial_metric::Symbol
    target_accept::Float64
    max_depth::Int
    max_energy_error::Float64
    step_size::Union{Nothing, Float64}
    step_size_bounds::Union{Nothing, Tuple{Float64, Float64}}
    chain_jitters::Vector{Float64}
    warmstart_iters::Int
    init_buffer::Int
    term_buffer::Int
    window_size::Int
    blend_power::Float64
    regularize_min_ratio::Float64
    regularize_max_ratio::Float64
    mu_max_ratio::Float64
    checkpoint_every::Int
end

function _default_stan_windows(warmup::Int)
    if warmup >= 150
        return (75, 50, 25)
    end
    init_b = max(2, round(Int, 0.15 * warmup))
    term_b = max(2, round(Int, 0.10 * warmup))
    win_b = max(2, warmup - init_b - term_b)
    return (init_b, term_b, win_b)
end

function _build_sampler_config(;
    ndraws::Int,
    warmup::Int,
    chains::Int = 4,
    seed::Integer = 20261030,
    seeds::Union{Nothing, AbstractVector{<:Integer}} = nothing,
    init::Symbol = :overdispersed,
    init_radius::Real = 2.0,
    adaptation::Symbol = :stan,
    initial_metric::Symbol = :prior_fisher,
    target_accept::Real = 0.85,
    max_depth::Int = 10,
    max_energy_error::Real = 1000.0,
    step_size::Union{Nothing, Real} = nothing,
    step_size_bounds::Union{Nothing, Tuple{<:Real, <:Real}} = nothing,
    chain_jitters::Union{Nothing, AbstractVector{<:Real}} = nothing,
    warmstart_iters::Union{Nothing, Int} = nothing,
    init_buffer::Union{Nothing, Int} = nothing,
    term_buffer::Union{Nothing, Int} = nothing,
    window_size::Union{Nothing, Int} = nothing,
    blend_power::Real = 0.75,
    regularize_min_ratio::Real = 0.25,
    regularize_max_ratio::Real = 6.0,
    mu_max_ratio::Real = 4.0,
    checkpoint_every::Int = 25,
)
    (ndraws >= 5 && warmup >= 5 && chains >= 1) ||
        throw(ArgumentError("ndraws >= 5, warmup >= 5, chains >= 1 required"))
    init in (:overdispersed, :prior, :stan_uniform, :multipath_lbfgs, :shared_warmstart) ||
        throw(ArgumentError("init must be in (:overdispersed, :prior, :stan_uniform, :multipath_lbfgs, :shared_warmstart)"))
    (isfinite(init_radius) && init_radius > 0) ||
        throw(ArgumentError("init_radius must be finite and strictly positive"))
    adaptation in (:stan, :clamped_regularized) ||
        throw(ArgumentError("adaptation must be :stan or :clamped_regularized"))
    initial_metric in (:prior_fisher, :unit) ||
        throw(ArgumentError("initial_metric must be :prior_fisher or :unit"))
    (isfinite(target_accept) && 0.0 < target_accept < 1.0) ||
        throw(ArgumentError("target_accept must lie strictly in (0, 1)"))
    max_depth >= 1 || throw(ArgumentError("max_depth >= 1 required"))

    s_vec = seeds === nothing ? [Int(seed) + c for c in 1:chains] : Int.(collect(seeds))
    (length(s_vec) == chains && allunique(s_vec)) ||
        throw(ArgumentError("require $chains distinct chain seeds"))

    j_vec = if chain_jitters !== nothing
        Float64.(collect(chain_jitters))
    elseif init === :multipath_lbfgs
        fill(1.25, chains)
    elseif init === :shared_warmstart
        [0.60 + 0.35 * (c - 1) / max(chains - 1, 1) for c in 1:chains]
    else
        zeros(Float64, chains)
    end
    (length(j_vec) == chains && all(x -> isfinite(x) && x >= 0, j_vec)) ||
        throw(ArgumentError("invalid chain_jitters"))

    ws_iters = if warmstart_iters !== nothing
        warmstart_iters
    elseif init === :multipath_lbfgs
        15
    elseif init === :shared_warmstart
        25
    else
        0
    end
    ws_iters >= 0 || throw(ArgumentError("warmstart_iters must be >= 0"))

    eps_val = step_size === nothing ? nothing : Float64(step_size)
    if eps_val !== nothing
        (isfinite(eps_val) && eps_val > 0.0) ||
            throw(ArgumentError("step_size must be positive and finite when provided"))
    end

    bounds_val = if adaptation === :stan
        step_size_bounds !== nothing && throw(ArgumentError(
            "step_size_bounds requires adaptation = :clamped_regularized; default adaptation = :stan uses unclamped dual averaging",
        ))
        nothing
    else
        raw_b = step_size_bounds === nothing ? (0.015, 0.16) : step_size_bounds
        lo_b = Float64(raw_b[1])
        hi_b = Float64(raw_b[2])
        (0.0 < lo_b <= hi_b && isfinite(lo_b) && isfinite(hi_b)) ||
            throw(ArgumentError("invalid step_size_bounds"))
        if eps_val !== nothing && !(lo_b <= eps_val <= hi_b)
            throw(ArgumentError("step_size must lie inside step_size_bounds under :clamped_regularized"))
        end
        (lo_b, hi_b)
    end

    def_init_b, def_term_b, def_win_b = _default_stan_windows(warmup)
    ib = init_buffer === nothing ? def_init_b : init_buffer
    tb = term_buffer === nothing ? def_term_b : term_buffer
    wb = window_size === nothing ? def_win_b : window_size
    (ib >= 1 && tb >= 1 && wb >= 1) ||
        throw(ArgumentError("adaptation window buffers must be >= 1"))

    return SamplerConfig(
        ndraws,
        warmup,
        chains,
        s_vec,
        init,
        Float64(init_radius),
        adaptation,
        initial_metric,
        Float64(target_accept),
        max_depth,
        Float64(max_energy_error),
        eps_val,
        bounds_val,
        j_vec,
        ws_iters,
        ib,
        tb,
        wb,
        Float64(blend_power),
        Float64(regularize_min_ratio),
        Float64(regularize_max_ratio),
        Float64(mu_max_ratio),
        max(checkpoint_every, 1),
    )
end

SamplerConfig(; kwargs...) = _build_sampler_config(; kwargs...)

"""
    sampler_controls(cfg::SamplerConfig)

Return a transparent NamedTuple of all HMC initialization, metric, adaptation, and seed settings.
"""
function sampler_controls(cfg::SamplerConfig)
    return (;
        ndraws = cfg.ndraws,
        warmup = cfg.warmup,
        chains = cfg.chains,
        seeds = copy(cfg.seeds),
        init = cfg.init,
        init_radius = cfg.init_radius,
        adaptation = cfg.adaptation,
        initial_metric = cfg.initial_metric,
        target_accept = cfg.target_accept,
        max_depth = cfg.max_depth,
        max_energy_error = cfg.max_energy_error,
        step_size = cfg.step_size,
        step_size_bounds = cfg.step_size_bounds,
        chain_jitters = copy(cfg.chain_jitters),
        warmstart_iters = cfg.warmstart_iters,
        init_buffer = cfg.init_buffer,
        term_buffer = cfg.term_buffer,
        window_size = cfg.window_size,
        checkpoint_every = cfg.checkpoint_every,
    )
end

function _draw_overdispersed_init(rng::AbstractRNG, m::StarModel, radius::Float64)
    b = _layout(m)
    p = m.prior
    unif(n::Int) = radius .* (2.0 .* rand(rng, Float64, n) .- 1.0)
    q_ncp = zeros(Float64, b.dim)
    q_ncp[b.zi] .= unif(length(b.zi))
    q_ncp[b.zr] .= unif(length(b.zr))
    for c in 1:m.D
        if !isempty(b.steps[c])
            q_ncp[b.steps[c]] .= unif(length(b.steps[c]))
        end
    end
    mu_scale = min(p.mu_sd, 2.0)
    sd_scale = min(p.log_sd_sd, 0.75)
    corr_radius = min(0.5 * radius, 1.25)
    q_ncp[b.mu] .= mu_scale .* unif(m.D)
    q_ncp[b.si] .= p.entity_log_sd_mean .+ sd_scale .* unif(m.D)
    q_ncp[b.sr] .= p.rater_log_sd_mean .+ sd_scale .* unif(m.D)
    q_ncp[b.ci] .= corr_radius .* (2.0 .* rand(rng, Float64, length(b.ci)) .- 1.0)
    q_ncp[b.cr] .= corr_radius .* (2.0 .* rand(rng, Float64, length(b.cr)) .- 1.0)
    if m.spec.include_phi
        phi_scale = min(p.phi_sd, 2.0)
        q_ncp[b.phi] .= phi_scale .* unif(length(b.phi))
    end
    return from_ncp_reference(m, q_ncp)
end

function _draw_stan_uniform_init(rng::AbstractRNG, m::StarModel, radius::Float64)
    return radius .* (2.0 .* rand(rng, Float64, m.dim) .- 1.0)
end

function _zero_initial(m::StarModel)
    b = _layout(m)
    q = zeros(Float64, b.dim)
    q[b.si] .= m.prior.entity_log_sd_mean
    q[b.sr] .= m.prior.rater_log_sd_mean
    return q
end

function _empirical_initial(m::StarModel)
    b = _layout(m)
    p = m.prior
    N = length(m.entity)
    q = _zero_initial(m)
    for c in 1:m.D
        mc = m.M[c]
        yc = view(m.y, c, :)
        pk = [(count(==(k), yc) + 0.5) / (N + 0.5 * (mc + 1)) for k in 0:mc]
        delta = [log(pk[k + 1] / pk[k]) for k in 1:mc]
        mu_c = mean(delta)
        q[b.mu[c]] = mu_c
        if mc > 1
            centered = (mu_c .- delta) .- p.step_spacing .* ((1:mc) .- (mc + 1) / 2)
            q[b.steps[c]] .= _helmert_pullback(centered) ./ p.step_sd
        end
    end
    if m.spec.include_phi
        u0 = (Float64.(view(m.y, 1, :)) ./ m.M[1]) .- 0.5
        u0_m = mean(u0)
        u0_v = max(var(u0; corrected = false), 1e-4)
        for c in 2:m.D
            uc = (Float64.(view(m.y, c, :)) ./ m.M[c]) .- 0.5
            uc_v = max(var(uc; corrected = false), 1e-4)
            cov_0c = mean((u0 .- u0_m) .* (uc .- mean(uc)))
            r2 = clamp((cov_0c * cov_0c) / (u0_v * uc_v), 0.0, 0.85)
            q[b.phi[c - 1]] = clamp(cov_0c / (u0_v * uc_v * (1.0 - r2)), -2.0 * p.phi_sd, 6.0 * p.phi_sd)
        end
    end
    return q
end

# Outcome-free diagonal variance (inverse mass) preconditioning vector derived solely from
# design incidence counts, the exact Rao-Searle Schur-complement contrast effective counts,
# and prior scale hyperparameters.
function _prior_fisher_metric(m::StarModel)
    b = _layout(m)
    p = m.prior
    N = length(m.entity)
    pr = ones(Float64, b.dim)
    vy = [_pcm_reference_fisher(mc, p.step_spacing) for mc in m.M]
    sdi = exp(p.entity_log_sd_mean)
    sdr = exp(p.rater_log_sd_mean)

    for (blk, basis, n, sd) in (
        (b.zi, m.entity_basis, m.I, sdi),
        (b.zr, m.rater_basis, m.R, sdr),
    )
        eff = basis.effective_counts
        for c in 1:m.D, j in 1:(n - 1)
            idx = first(blk) + (c - 1) * (n - 1) + j - 1
            pr[idx] = basis.cp_mask[j] ?
                (1.0 / (sd * sd) + vy[c] * eff[j]) :
                (1.0 + (sd * sd) * vy[c] * eff[j])
        end
    end

    unbal_ent = sum(((cnt / N) - (1.0 / m.I))^2 for cnt in m.entity_basis.raw_counts)
    unbal_rat = sum(((cnt / N) - (1.0 / m.R))^2 for cnt in m.rater_basis.raw_counts)
    shift_var = (sdi * sdi) * unbal_ent + (sdr * sdr) * unbal_rat
    for c in 1:m.D
        cond_var_mu = 1.0 / (1.0 / (p.mu_sd * p.mu_sd) + N * vy[c])
        marg_var_mu = min(p.mu_sd * p.mu_sd, cond_var_mu + shift_var)
        pr[b.mu[c]] = 1.0 / max(marg_var_mu, 1e-8)
    end

    for c in 1:m.D
        mc = m.M[c]
        if mc > 1
            basis = hcat([_helmert([Float64(k == j) for k in 1:(mc - 1)]) for j in 1:(mc - 1)]...)
            scores = vcat(zeros(1, mc - 1), -p.step_sd * cumsum(basis; dims = 1))
            pr[b.steps[c]] .= 1.0 .+ N .* vec(var(scores; dims = 1, corrected = false))
        end
    end

    ncp_i = sum(m.entity_basis.effective_counts[.!m.entity_basis.cp_mask])
    ncp_r = sum(m.rater_basis.effective_counts[.!m.rater_basis.cp_mask])
    n_cp_e = m.entity_basis.n_cp
    n_cp_r = m.rater_basis.n_cp
    for c in 1:m.D
        pr[b.si[c]] = 1.0 / (p.log_sd_sd^2) + 2.0 * n_cp_e + 2.0 * (sdi^2) * vy[c] * ncp_i
        pr[b.sr[c]] = 1.0 / (p.log_sd_sd^2) + 2.0 * n_cp_r + 2.0 * (sdr^2) * vy[c] * ncp_r
    end
    pr[b.ci] .= [
        2.0 * (p.entity_lkj_eta + ((m.D - 1) - j) / 2) + n_cp_e + (sdi^2) * mean(vy) * ncp_i
        for i in 2:m.D for j in 1:(i - 1)
    ]
    pr[b.cr] .= [
        2.0 * (p.rater_lkj_eta + ((m.D - 1) - j) / 2) + n_cp_r + (sdr^2) * mean(vy) * ncp_r
        for i in 2:m.D for j in 1:(i - 1)
    ]
    if m.spec.include_phi
        u0_v = (m.M[1] + 2) / (12.0 * m.M[1])
        uc_v = [(m.M[c] + 2) / (12.0 * m.M[c]) for c in 2:m.D]
        pr[b.phi] .= 1.0 / (p.phi_sd^2) .+ N .* u0_v .* uc_v
    end
    return 1.0 ./ pr
end

function _event_variance_weights(m::StarModel, v)
    w_ent = zeros(Float64, m.I, m.D)
    w_rat = zeros(Float64, m.R, m.D)
    s = _scratch(m.M, Float64)
    eta = zeros(Float64, m.D)
    @inbounds for e in eachindex(m.entity)
        i = m.entity[e]
        r = m.rater[e]
        for c in 1:m.D
            eta[c] = v.mu[c] + v.A[i, c] - v.S[r, c]
        end
        _event_kernel!(s, eta, v.tau, v.phi, m.M)
        for c in 1:m.D
            m1 = 0.0
            m2 = 0.0
            for k in 0:m.M[c]
                pk = s.pm[k + 1, c]
                m1 += k * pk
                m2 += (k * k) * pk
            end
            wec = max(m2 - m1 * m1, 1e-6)
            w_ent[i, c] += wec
            w_rat[r, c] += wec
        end
    end
    return w_ent, w_rat
end

function _basis_weighted_precision(basis::FacetBasis, weights_user::AbstractVector{Float64})
    w_ord = weights_user[basis.perm]
    if basis.basis_order === :descending_schur
        return _schur_harmonic_counts(w_ord)
    end
    return _weighted_helmert_diag(w_ord)
end

function _analytical_metric(m::StarModel, q_ref::AbstractVector{Float64})
    b = _layout(m)
    mk = _cp_masks(m)
    p = m.prior
    v = _coordinates(m, q_ref; raw_input = false)
    pr = 1.0 ./ _prior_fisher_metric(m)
    w_ent, w_rat = _event_variance_weights(m, v)
    prec_i = vec(sum(abs2, v.fi.invL; dims = 1))
    prec_r = vec(sum(abs2, v.fr.invL; dims = 1))
    sc_i = vec(sum(abs2, v.li; dims = 2))
    sc_r = vec(sum(abs2, v.lr; dims = 2))
    for c in 1:m.D
        hd_i = _basis_weighted_precision(m.entity_basis, view(w_ent, :, c))
        hd_r = _basis_weighted_precision(m.rater_basis, view(w_rat, :, c))
        off_i = first(b.zi) + (c - 1) * (m.I - 1) - 1
        off_r = first(b.zr) + (c - 1) * (m.R - 1) - 1
        for j in 1:(m.I - 1)
            pr[off_i + j] = mk.entity_cp[j] ? (prec_i[c] + hd_i[j]) : (1.0 + sc_i[c] * hd_i[j])
        end
        for j in 1:(m.R - 1)
            pr[off_r + j] = mk.rater_cp[j] ? (prec_r[c] + hd_r[j]) : (1.0 + sc_r[c] * hd_r[j])
        end
    end
    ri = C.correlation_state(q_ref[b.ci], m.D; eta = p.entity_lkj_eta).R
    rr = C.correlation_state(q_ref[b.cr], m.D; eta = p.rater_lkj_eta).R
    vif_i = diag(inv(Symmetric(Matrix(ri))))
    vif_r = diag(inv(Symmetric(Matrix(rr))))
    vy = [_pcm_reference_fisher(mc, p.step_spacing) for mc in m.M]
    sdi_v = exp.(q_ref[b.si])
    sdr_v = exp.(q_ref[b.sr])
    ncp_i = sum(m.entity_basis.effective_counts[.!mk.entity_cp])
    ncp_r = sum(m.rater_basis.effective_counts[.!mk.rater_cp])
    for c in 1:m.D
        pr[b.si[c]] = 1.0 / (p.log_sd_sd^2) + mk.n_cp_entity * (1.0 + vif_i[c]) + 2.0 * (sdi_v[c]^2) * vy[c] * ncp_i
        pr[b.sr[c]] = 1.0 / (p.log_sd_sd^2) + mk.n_cp_rater * (1.0 + vif_r[c]) + 2.0 * (sdr_v[c]^2) * vy[c] * ncp_r
    end
    pr[b.ci] .= [
        2.0 * (p.entity_lkj_eta + ((m.D - 1) - j) / 2) + mk.n_cp_entity * mean(vif_i) + mean(sdi_v .^ 2) * mean(vy) * ncp_i
        for i in 2:m.D for j in 1:(i - 1)
    ]
    pr[b.cr] .= [
        2.0 * (p.rater_lkj_eta + ((m.D - 1) - j) / 2) + mk.n_cp_rater * mean(vif_r) + mean(sdr_v .^ 2) * mean(vy) * ncp_r
        for i in 2:m.D for j in 1:(i - 1)
    ]
    inv_m = 1.0 ./ pr
    for c in 1:m.D
        off_r = first(b.zr) + (c - 1) * (m.R - 1) - 1
        v_bar = mean(
            mk.rater_cp[j] ? inv_m[off_r + j] : (sdr_v[c]^2) * inv_m[off_r + j]
            for j in 1:(m.R - 1)
        )
        for j in 1:(m.R - 1)
            if mk.rater_cp[j]
                inv_m[off_r + j] += 0.5 * v_bar / m.R
            end
        end
    end
    return inv_m
end

function _inv_corr_cholesky(L_R::AbstractMatrix{Float64}, D::Int)
    q_corr = Float64[]
    for i in 2:D
        rem = 1.0
        for j in 1:(i - 1)
            z = clamp(L_R[i, j] / max(rem, 1e-8), -0.98, 0.98)
            push!(q_corr, atanh(z))
            rem *= sqrt(max(1.0 - z * z, 1e-8))
        end
    end
    return q_corr
end

function _update_hyperparameters_from_facets!(
    q::Vector{Float64},
    m::StarModel;
    cond_var_entity,
    cond_var_rater,
)
    b = _layout(m)
    p = m.prior
    D = m.D
    li = _cov_root([q[b.si]; q[b.ci]], D, p.entity_lkj_eta)
    lr = _cov_root([q[b.sr]; q[b.cr]], D, p.rater_lkj_eta)
    fi = _unpack_facet(view(q, b.zi), m.entity_basis, D, li)
    fr = _unpack_facet(view(q, b.zr), m.rater_basis, D, lr)
    for (M_mat, n_lv, cvar, si_r, ci_r, mu_log_sd, eta, z_r, cp_mk) in (
        (fi.M_mat, m.I, cond_var_entity, b.si, b.ci, p.entity_log_sd_mean, p.entity_lkj_eta, b.zi, m.entity_basis.cp_mask),
        (fr.M_mat, m.R, cond_var_rater, b.sr, b.cr, p.rater_log_sd_mean, p.rater_lkj_eta, b.zr, m.rater_basis.cp_mask),
    )
        cov_f = Symmetric((M_mat' * M_mat) ./ (n_lv - 1) + Diagonal(cvar) + 1e-4 * I)
        sd_emp = sqrt.(diag(cov_f))
        cor_emp = Symmetric(Diagonal(1.0 ./ sd_emp) * cov_f * Diagonal(1.0 ./ sd_emp))
        w_prior = 1.0 / (p.log_sd_sd * p.log_sd_sd)
        w_data = 0.5 * (n_lv - 1)
        q[si_r] .= (w_prior .* mu_log_sd .+ w_data .* log.(sd_emp)) ./ (w_prior + w_data)
        shrink = (n_lv - 1) / ((n_lv - 1) + 2.0 * max(eta - 0.5, 0.5))
        cor_reg = Symmetric(shrink .* Matrix(cor_emp) .+ (1.0 - shrink) .* Matrix{Float64}(I, D, D))
        q[ci_r] .= _inv_corr_cholesky(cholesky(cor_reg).L, D)
        L_new = _cov_root([q[si_r]; q[ci_r]], D, eta)
        Z_new = M_mat * Matrix(inv(LowerTriangular(L_new)))'
        Q_mat = reshape(view(q, z_r), n_lv - 1, D)
        for c in 1:D, j in 1:(n_lv - 1)
            Q_mat[j, c] = cp_mk[j] ? M_mat[j, c] : Z_new[j, c]
        end
    end
    return q
end

function _lbfgs_two_loop_dir(grad, mask, inv_m, s_hist, y_hist, rho_hist)
    q_vec = (-grad) .* mask
    k_len = length(s_hist)
    alphas = zeros(Float64, k_len)
    for i in k_len:-1:1
        alphas[i] = rho_hist[i] * dot(s_hist[i], q_vec)
        q_vec .-= alphas[i] .* y_hist[i]
    end
    r_vec = inv_m .* q_vec
    if k_len > 0
        sy = dot(s_hist[end], y_hist[end])
        yy = dot(y_hist[end], inv_m .* y_hist[end])
        r_vec .*= (sy > 0 && yy > 0) ? clamp(sy / yy, 0.05, 20.0) : 1.0
    end
    for i in 1:k_len
        r_vec .+= s_hist[i] .* (alphas[i] - rho_hist[i] * dot(y_hist[i], r_vec))
    end
    return (-r_vec) .* mask
end

function _lbfgs_stage!(
    q::Vector{Float64},
    m::StarModel,
    mask::Vector{Float64},
    inv_m::Vector{Float64},
    n_it::Int,
)
    val, grad = _safe_evaluate(m, q; likelihood = true, compute_gradient = true)
    s_hist = Vector{Float64}[]
    y_hist = Vector{Float64}[]
    rho_hist = Float64[]
    for _ in 1:n_it
        dir = _lbfgs_two_loop_dir(grad, mask, inv_m, s_hist, y_hist, rho_hist)
        slope = dot(grad, dir)
        if slope <= 1e-6
            empty!(s_hist)
            empty!(y_hist)
            empty!(rho_hist)
            dir = (inv_m .* grad) .* mask
            slope = dot(grad, dir)
            slope <= 1e-6 && break
        end
        max_rel = maximum(abs, dir ./ sqrt.(inv_m))
        if max_rel > 20.0
            dir .*= 20.0 / max_rel
            slope = dot(grad, dir)
        end
        step = 1.0
        accepted = false
        for _ in 1:6
            q_try = q .+ step .* dir
            v_try, g_try = _safe_evaluate(m, q_try; likelihood = true, compute_gradient = true)
            if isfinite(v_try) && v_try > val + 1e-4 * step * slope
                s_k = q_try .- q
                y_k = (grad .- g_try) .* mask
                sy = dot(s_k, y_k)
                if sy > 1e-10
                    if length(s_hist) >= 6
                        popfirst!(s_hist)
                        popfirst!(y_hist)
                        popfirst!(rho_hist)
                    end
                    push!(s_hist, s_k)
                    push!(y_hist, y_k)
                    push!(rho_hist, 1.0 / sy)
                end
                q .= q_try
                val = v_try
                grad = g_try
                accepted = true
                break
            end
            step *= 0.5
        end
        accepted || break
    end
    return q
end

function _global_prepolish!(q::Vector{Float64}, m::StarModel, inv_m::Vector{Float64}; steps::Int = 4)
    b = _layout(m)
    g_idx = [vcat(collect.(b.steps)...); collect(b.mu); collect(b.phi)]
    val, grad = _safe_evaluate(m, q; likelihood = true, compute_gradient = true)
    dir = zeros(Float64, b.dim)
    for _ in 1:steps
        fill!(dir, 0.0)
        dir[g_idx] .= inv_m[g_idx] .* grad[g_idx]
        slope = dot(grad, dir)
        slope <= 1e-6 && break
        step = 1.0
        for _ in 1:6
            q_try = q .+ step .* dir
            v_try, g_try = _safe_evaluate(m, q_try; likelihood = true, compute_gradient = true)
            if isfinite(v_try) && v_try > val + 1e-4 * step * slope
                q .= q_try
                val = v_try
                grad = g_try
                break
            end
            step *= 0.5
        end
    end
    return q
end

function _lbfgs_polish_from!(q::Vector{Float64}, m::StarModel; max_iter::Int = 25, prepolish::Bool = true)
    if max_iter <= 0
        return q, _analytical_metric(m, q)
    end
    b = _layout(m)
    mk = _cp_masks(m)
    active = [collect(b.zi); collect(b.zr); vcat(collect.(b.steps)...); collect(b.mu); collect(b.phi)]
    mask = zeros(Float64, b.dim)
    mask[active] .= 1.0
    for outer in 1:2
        n_it = outer == 1 ? div(max_iter, 2) : (max_iter - div(max_iter, 2))
        n_it <= 0 && continue
        inv_m = _analytical_metric(m, q)
        if outer == 1 && prepolish
            _global_prepolish!(q, m, inv_m; steps = 4)
        end
        _lbfgs_stage!(q, m, mask, inv_m, n_it)
        inv_cur = _analytical_metric(m, q)
        cvar_i = [
            mean(
                mk.entity_cp[j] ? inv_cur[first(b.zi) + (c - 1) * (m.I - 1) + j - 1] :
                    (exp(2.0 * q[b.si[c]]) * inv_cur[first(b.zi) + (c - 1) * (m.I - 1) + j - 1])
                for j in 1:(m.I - 1)
            ) for c in 1:m.D
        ]
        s_r = exp.(q[b.sr])
        cvar_r = [
            mean(
                mk.rater_cp[j] ? inv_cur[first(b.zr) + (c - 1) * (m.R - 1) + j - 1] :
                    (s_r[c]^2) * inv_cur[first(b.zr) + (c - 1) * (m.R - 1) + j - 1]
                for j in 1:(m.R - 1)
            ) for c in 1:m.D
        ]
        _update_hyperparameters_from_facets!(q, m; cond_var_entity = cvar_i, cond_var_rater = cvar_r)
    end
    return q, _analytical_metric(m, q)
end

function _lbfgs_warmstart(m::StarModel; max_iter::Int = 25)
    q = _empirical_initial(m)
    return _lbfgs_polish_from!(q, m; max_iter, prepolish = true)
end

function _perturb_warmstart(
    rng::AbstractRNG,
    m::StarModel,
    q_center::Vector{Float64},
    mass_ws::Vector{Float64};
    jitter::Float64,
    hyperparameter_scale::Float64 = 1.0,
)
    b = _layout(m)
    mk = _cp_masks(m)
    D = m.D
    q = copy(q_center)
    cor_i = C.correlation_state(q[b.ci], D; eta = m.prior.entity_lkj_eta).R
    cor_r = C.correlation_state(q[b.cr], D; eta = m.prior.rater_lkj_eta).R
    Li = cholesky(Symmetric(0.5 .* Matrix(cor_i) .+ 0.5 .* I(D))).L
    Lr = cholesky(Symmetric(0.5 .* Matrix(cor_r) .+ 0.5 .* I(D))).L

    Zi = randn(rng, m.I - 1, D)
    Mi = reshape(sqrt.(mass_ws[b.zi]), m.I - 1, D)
    Qi = reshape(view(q, b.zi), m.I - 1, D)
    for j in 1:(m.I - 1)
        rn = mk.entity_cp[j] ? vec(Zi[j, :]' * Li') : Zi[j, :]
        Qi[j, :] .+= jitter .* Mi[j, :] .* rn
    end

    Zr = randn(rng, m.R - 1, D)
    Mr = reshape(sqrt.(mass_ws[b.zr]), m.R - 1, D)
    Qr = reshape(view(q, b.zr), m.R - 1, D)
    for j in 1:(m.R - 1)
        rn = mk.rater_cp[j] ? vec(Zr[j, :]' * Lr') : Zr[j, :]
        Qr[j, :] .+= jitter .* Mr[j, :] .* rn
    end

    nf = [
        vcat(collect.(b.steps)...);
        collect(b.mu);
        collect(b.si);
        collect(b.sr);
        collect(b.ci);
        collect(b.cr);
        collect(b.phi);
    ]
    q[nf] .+= (hyperparameter_scale * jitter) .* sqrt.(mass_ws[nf]) .* randn(rng, length(nf))
    return q
end

function _prepare_chain_init_and_metric(
    rng::AbstractRNG,
    m::StarModel,
    cfg::SamplerConfig,
    chain::Int,
    shared_ws::Union{Nothing, NamedTuple},
)
    unit_mass = ones(Float64, m.dim)
    pf_mass = cfg.initial_metric === :unit ? unit_mass : _prior_fisher_metric(m)
    if cfg.init === :overdispersed
        q_init = _draw_overdispersed_init(rng, m, cfg.init_radius)
        return q_init, copy(pf_mass)
    elseif cfg.init === :prior
        q_init = prior_draw(m; rng)
        return q_init, copy(pf_mass)
    elseif cfg.init === :stan_uniform
        q_init = _draw_stan_uniform_init(rng, m, cfg.init_radius)
        return q_init, copy(pf_mass)
    elseif cfg.init === :multipath_lbfgs
        q0 = _draw_overdispersed_init(rng, m, cfg.init_radius)
        q_pol, mass_pol = _lbfgs_polish_from!(q0, m; max_iter = cfg.warmstart_iters, prepolish = false)
        q_init = _perturb_warmstart(
            rng, m, q_pol, mass_pol;
            jitter = cfg.chain_jitters[chain],
            hyperparameter_scale = 1.0,
        )
        m0 = cfg.initial_metric === :unit ? unit_mass : mass_pol
        return q_init, copy(m0)
    else
        ws = shared_ws === nothing ? begin
            q_w, m_w = cfg.warmstart_iters > 0 ?
                _lbfgs_warmstart(m; max_iter = cfg.warmstart_iters) :
                (_empirical_initial(m), _prior_fisher_metric(m))
            (; q_ws = q_w, mass_ws = m_w)
        end : shared_ws
        q_init = _perturb_warmstart(
            rng, m, ws.q_ws, ws.mass_ws;
            jitter = cfg.chain_jitters[chain],
            hyperparameter_scale = 0.5,
        )
        m0 = cfg.initial_metric === :unit ? unit_mass : ws.mass_ws
        return q_init, copy(m0)
    end
end

function _regularize_metric!(
    m_inv::AbstractVector{Float64},
    ref_inv::AbstractVector{Float64},
    cfg::SamplerConfig,
    mu_range::UnitRange{Int},
)
    @inbounds for k in eachindex(m_inv, ref_inv)
        rk = ref_inv[k]
        mk_v = m_inv[k]
        cap = (k in mu_range) ? cfg.mu_max_ratio : cfg.regularize_max_ratio
        if isfinite(mk_v) && mk_v > 0
            blended = (mk_v^cfg.blend_power) * (rk^(1.0 - cfg.blend_power))
            m_inv[k] = clamp(blended, cfg.regularize_min_ratio * rk, cap * rk)
        else
            m_inv[k] = rk
        end
    end
    return m_inv
end

function _clamp_warmup_integrator(kernel, adaptor, cfg::SamplerConfig)
    eps_min, eps_max = cfg.step_size_bounds
    eps_cur = H.nom_step_size(kernel.τ.integrator)
    if !isfinite(eps_cur) || eps_cur < eps_min || eps_cur > eps_max
        fallback = cfg.step_size === nothing ? sqrt(eps_min * eps_max) : cfg.step_size
        eps_safe = isfinite(eps_cur) ? clamp(eps_cur, eps_min, eps_max) : fallback
        tc = H.GeneralisedNoUTurn(cfg.max_depth, cfg.max_energy_error)
        kernel = H.HMCKernel(H.Trajectory{H.MultinomialTS}(H.Leapfrog(eps_safe), tc))
        H.reset!(adaptor.ssa)
        adaptor.ssa.state.μ = log(1.6 * eps_safe)
    end
    return kernel
end

function _hmc_step(
    rng::AbstractRNG,
    h,
    kernel,
    adaptor,
    t,
    iter::Int,
    cfg::SamplerConfig,
    ref_inv_mass::Vector{Float64},
    mu_range::UnitRange{Int},
)
    t = H.transition(rng, h, kernel, t.z)
    stat = H.stat(t)
    if cfg.adaptation === :stan
        h, kernel, is_ad = H.adapt!(h, kernel, adaptor, iter, cfg.warmup, t.z, stat.acceptance_rate)
        return h, kernel, t, merge(stat, (; is_adapt = is_ad))
    end
    prev_m = h.metric.M⁻¹
    eps_before = H.nom_step_size(kernel.τ.integrator)
    h, kernel, is_ad = H.adapt!(h, kernel, adaptor, iter, cfg.warmup, t.z, stat.acceptance_rate)
    if iter <= cfg.warmup
        if is_ad && !(h.metric.M⁻¹ === prev_m)
            _regularize_metric!(h.metric.M⁻¹, ref_inv_mass, cfg, mu_range)
            hasproperty(adaptor.pc, :var) && copyto!(adaptor.pc.var, h.metric.M⁻¹)
            lo_b, hi_b = cfg.step_size_bounds
            adaptor.ssa.state.μ = log(1.4 * clamp(eps_before, lo_b, hi_b))
            h = H.Hamiltonian(H.DiagEuclideanMetric(copy(h.metric.M⁻¹)), h.ℓπ, h.∂ℓπ∂θ)
        end
        kernel = _clamp_warmup_integrator(kernel, adaptor, cfg)
    end
    return h, kernel, t, merge(stat, (; is_adapt = is_ad))
end

function _checked_initial_stepsize(eps_raw::Real, cfg::SamplerConfig)
    eps0 = Float64(eps_raw)
    isfinite(eps0) && eps0 > 0 || throw(ArgumentError(
        "initial step-size search returned a nonfinite or nonpositive value; inspect the initial state and metric",
    ))
    if cfg.adaptation === :clamped_regularized
        return clamp(eps0, cfg.step_size_bounds...)
    end
    return eps0
end

function _find_initial_stepsize(
    rng::AbstractRNG,
    h,
    q_init::Vector{Float64},
    cfg::SamplerConfig,
)
    if cfg.step_size !== nothing
        return cfg.step_size
    end
    return _checked_initial_stepsize(H.find_good_stepsize(rng, h, q_init), cfg)
end

function _setup_hmc(
    rng::AbstractRNG,
    target::_CountedTarget,
    q_init::Vector{Float64},
    ref_inv_mass::Vector{Float64},
    cfg::SamplerConfig,
)
    metric = H.DiagEuclideanMetric(copy(ref_inv_mass))
    h = H.Hamiltonian(
        metric,
        q -> first(_eval_counted(target, q; compute_gradient = false)),
        q -> _eval_counted(target, q; compute_gradient = true),
    )
    eps0 = _find_initial_stepsize(rng, h, q_init, cfg)
    integrator = H.Leapfrog(eps0)
    tc = H.GeneralisedNoUTurn(cfg.max_depth, cfg.max_energy_error)
    kernel = H.HMCKernel(H.Trajectory{H.MultinomialTS}(integrator, tc))
    ssa = H.StepSizeAdaptor(cfg.target_accept, integrator)
    if cfg.adaptation === :clamped_regularized
        ssa.state.μ = log(2.0 * eps0)
    end
    small = cfg.warmup < (cfg.init_buffer + cfg.term_buffer + cfg.window_size)
    ib, tb, wb = small ? _default_stan_windows(cfg.warmup) : (cfg.init_buffer, cfg.term_buffer, cfg.window_size)
    adaptor = H.StanHMCAdaptor(
        H.MassMatrixAdaptor(metric),
        ssa;
        init_buffer = ib,
        term_buffer = tb,
        window_size = wb,
    )
    return h, kernel, adaptor, eps0
end

function _run_single_chain(
    m::StarModel,
    cfg::SamplerConfig,
    chain::Int,
    shared_ws::Union{Nothing, NamedTuple},
)
    rng = Xoshiro(cfg.seeds[chain])
    t0 = time()
    q_init, ref_inv = _prepare_chain_init_and_metric(rng, m, cfg, chain, shared_ws)
    target = _CountedTarget(m, 0, 0)
    h, kernel, adaptor, eps0 = _setup_hmc(rng, target, q_init, ref_inv, cfg)
    h, t = H.sample_init(rng, h, q_init)
    mu_range = _layout(m).mu
    total = cfg.warmup + cfg.ndraws
    draws = Matrix{Float64}(undef, cfg.ndraws, m.dim)
    warm_stats = NamedTuple[]
    ret_stats = NamedTuple[]
    for it in 1:total
        h, kernel, t, st = _hmc_step(rng, h, kernel, adaptor, t, it, cfg, ref_inv, mu_range)
        rec = merge(st, (; chain, iteration = it))
        if it <= cfg.warmup
            push!(warm_stats, rec)
        else
            draws[it - cfg.warmup, :] .= t.z.θ
            push!(ret_stats, rec)
        end
    end
    meta = (;
        chain,
        initial_step_size = eps0,
        elapsed_seconds = time() - t0,
        calls = target.calls,
        numerical_rejections = target.rejected,
    )
    return (; draws, warm_stats, ret_stats, meta)
end

function _save_atomic_jls(path::AbstractString, obj)
    ispath(path) && throw(ArgumentError("refusing to overwrite checkpoint: $path"))
    tmp = path * ".partial"
    open(io -> serialize(io, obj), tmp, "w")
    mv(tmp, path; force = true)
    return path
end

function _save_atomic_json(path::AbstractString, obj)
    ispath(path) && throw(ArgumentError("refusing to overwrite JSON: $path"))
    tmp = path * ".partial"
    open(tmp, "w") do io
        JSON3.write(io, _jsonsafe(obj))
        println(io)
    end
    mv(tmp, path; force = true)
    return path
end

function _init_or_resume_worker(chain_dir::AbstractString, prep, chain::Int)
    m = prep.model
    cfg = prep.config
    paths = isdir(chain_dir) ? sort(filter(x -> endswith(x, ".jls"), readdir(chain_dir; join = true))) : String[]
    target = _CountedTarget(m, 0, 0)
    if isempty(paths)
        mkpath(chain_dir)
        rng = Xoshiro(cfg.seeds[chain])
        q_init, ref_inv = _prepare_chain_init_and_metric(rng, m, cfg, chain, prep.shared_ws)
        h, kernel, adaptor, eps0 = _setup_hmc(rng, target, q_init, ref_inv, cfg)
        h, t = H.sample_init(rng, h, q_init)
        _save_atomic_json(
            joinpath(chain_dir, "initial.json"),
            (;
                chain,
                seed = cfg.seeds[chain],
                init = cfg.init,
                adaptation = cfg.adaptation,
                initial_metric = cfg.initial_metric,
                initial_step_size = eps0,
                log_density = t.z.ℓπ.value,
                inverse_mass_min = minimum(ref_inv),
                inverse_mass_max = maximum(ref_inv),
                dimension = m.dim,
            ),
        )
        return (; rng, h, kernel, adaptor, t, ref_inv, target, completed = 0, prev_sec = 0.0)
    end
    cp = open(deserialize, last(paths))
    target.calls = cp.calls
    target.rejected = cp.rejected
    h = H.Hamiltonian(
        H.DiagEuclideanMetric(copy(cp.metric.M⁻¹)),
        q -> first(_eval_counted(target, q; compute_gradient = false)),
        q -> _eval_counted(target, q; compute_gradient = true),
    )
    return (;
        rng = copy(cp.rng),
        h,
        kernel = cp.kernel,
        adaptor = deepcopy(cp.adaptor),
        t = deepcopy(cp.transition),
        ref_inv = copy(cp.ref_inv_mass),
        target,
        completed = cp.last,
        prev_sec = cp.elapsed_seconds,
    )
end

function _write_worker_block!(
    chain_dir::AbstractString,
    chain::Int,
    it::Int,
    total::Int,
    cfg::SamplerConfig,
    raws,
    stats,
    st_state,
    elapsed::Float64,
    log_io,
)
    bpath = joinpath(chain_dir, "block-" * lpad(it, 6, '0') * ".jls")
    _save_atomic_jls(
        bpath,
        (;
            chain,
            first = it - length(raws) + 1,
            last = it,
            raw = Matrix(hcat(raws...)'),
            stats = copy(stats),
            metric = H.DiagEuclideanMetric(copy(st_state.h.metric.M⁻¹)),
            kernel = st_state.kernel,
            adaptor = deepcopy(st_state.adaptor),
            transition = deepcopy(st_state.t),
            ref_inv_mass = copy(st_state.ref_inv),
            rng = copy(st_state.rng),
            elapsed_seconds = elapsed,
            calls = st_state.target.calls,
            rejected = st_state.target.rejected,
        ),
    )
    s_last = last(stats)
    if log_io !== nothing
        println(
            log_io,
            JSON3.write(
                _jsonsafe(
                    (;
                        chain,
                        iteration = it,
                        total,
                        phase = it <= cfg.warmup ? "warmup" : "retained",
                        elapsed_seconds = elapsed,
                        calls = st_state.target.calls,
                        rejected = st_state.target.rejected,
                        log_density = s_last.log_density,
                        step_size = s_last.step_size,
                        mean_n_steps = mean(x.n_steps for x in stats),
                        max_tree_depth = maximum(x.tree_depth for x in stats),
                        divergences = count(x -> x.numerical_error, stats),
                        depth_hits = count(x -> x.tree_depth >= cfg.max_depth, stats),
                    ),
                ),
            ),
        )
        flush(log_io)
    end
    empty!(raws)
    empty!(stats)
    return bpath
end

function _compute_shared_warmstart_if_needed(m::StarModel, cfg::SamplerConfig)
    if cfg.init !== :shared_warmstart
        return nothing
    end
    q_ws, mass_ws = cfg.warmstart_iters > 0 ?
        _lbfgs_warmstart(m; max_iter = cfg.warmstart_iters) :
        (_empirical_initial(m), _prior_fisher_metric(m))
    return (; q_ws, mass_ws)
end

"""
    fit(m::StarModel; ndraws, warmup, chains=4, seed=20261030, checkpoint_dir=nothing, kwargs...)

Sample the joint posterior of `m` via `AdvancedHMC` NUTS.

Default sampler configuration is 100% literature-grounded:
- `init = :overdispersed` (`init_radius = 2.0`): independent per-chain overdispersed draws
  free of outcome data snooping (Gelman & Rubin, 1992; Vehtari et al., 2021).
- `adaptation = :stan`: unmodified `AdvancedHMC.StanHMCAdaptor` (Stan 3-stage Welford diagonal
  mass adaptation + Hoffman & Gelman, 2014 `find_good_stepsize` and unclamped Nesterov dual averaging).
- `initial_metric = :prior_fisher`: outcome-free Schur-complement design/prior scale preconditioning
  during initial fast window 1 (or `:unit` for identity).

Optional strategies (`init = :prior | :stan_uniform | :multipath_lbfgs | :shared_warmstart`,
`adaptation = :clamped_regularized`) are available via explicit keywords for benchmarking and ablation.
"""
function fit(
    m::StarModel;
    ndraws::Int,
    warmup::Int,
    chains::Int = 4,
    seed::Integer = 20261030,
    checkpoint_dir::Union{Nothing, AbstractString} = nothing,
    log_io = nothing,
    kwargs...,
)
    if checkpoint_dir !== nothing
        prepare_fit(checkpoint_dir, m; ndraws, warmup, chains, seed, kwargs...)
        for c in 1:chains
            run_chain_worker(checkpoint_dir, c; log_io)
        end
        return collect_fit(checkpoint_dir)
    end
    cfg = _build_sampler_config(; ndraws, warmup, chains, seed, kwargs...)
    shared_ws = _compute_shared_warmstart_if_needed(m, cfg)
    chain_runs = [_run_single_chain(m, cfg, c, shared_ws) for c in 1:chains]
    draws = vcat([cr.draws for cr in chain_runs]...)
    warm_stats = vcat([cr.warm_stats for cr in chain_runs]...)
    ret_stats = vcat([cr.ret_stats for cr in chain_runs]...)
    meta = [cr.meta for cr in chain_runs]
    return _build_star_result(
        m,
        cfg,
        draws,
        warm_stats,
        ret_stats;
        provenance = (;
            operation = :fit,
            seed = Int(seed),
            controls = sampler_controls(cfg),
            chain_meta = meta,
        ),
    )
end

function prepare_fit(
    dir::AbstractString,
    m::StarModel;
    ndraws::Int,
    warmup::Int,
    chains::Int = 4,
    seed::Integer = 20261030,
    kwargs...,
)
    ispath(dir) && throw(ArgumentError("refusing to overwrite existing directory: $dir"))
    cfg = _build_sampler_config(; ndraws, warmup, chains, seed, kwargs...)
    shared_ws = _compute_shared_warmstart_if_needed(m, cfg)
    mkpath(dir)
    B._save_serialized_record(
        joinpath(dir, "prepared.jls"),
        (; model = m, config = cfg, shared_ws);
        overwrite = false,
    )
    return dir
end

function run_chain_worker(
    dir::AbstractString,
    chain::Int;
    max_transitions::Union{Nothing, Int} = nothing,
    log_io = stdout,
)
    prep = open(deserialize, joinpath(dir, "prepared.jls"))
    cfg = prep.config
    m = prep.model
    (1 <= chain <= cfg.chains) || throw(ArgumentError("invalid chain index $chain"))
    chain_dir = joinpath(dir, "chain-$chain")
    comp_path = joinpath(chain_dir, "complete.json")
    ispath(comp_path) && throw(ArgumentError("chain $chain already complete"))
    ws = _init_or_resume_worker(chain_dir, prep, chain)
    total = cfg.warmup + cfg.ndraws
    stop_it = max_transitions === nothing ? total : min(total, ws.completed + max(max_transitions, 0))
    mu_range = _layout(m).mu
    raws = Vector{Float64}[]
    stats = NamedTuple[]
    t0 = time()
    rng = ws.rng
    h = ws.h
    kernel = ws.kernel
    adaptor = ws.adaptor
    t = ws.t
    for it in (ws.completed + 1):stop_it
        h, kernel, t, st = _hmc_step(rng, h, kernel, adaptor, t, it, cfg, ws.ref_inv, mu_range)
        push!(raws, copy(t.z.θ))
        push!(stats, merge(st, (; chain, iteration = it)))
        if it % cfg.checkpoint_every == 0 || it == stop_it
            el = ws.prev_sec + (time() - t0)
            st_bundle = (; rng, h, kernel, adaptor, t, ref_inv = ws.ref_inv, target = ws.target)
            _write_worker_block!(chain_dir, chain, it, total, cfg, raws, stats, st_bundle, el, log_io)
        end
    end
    if stop_it == total
        _save_atomic_json(
            comp_path,
            (;
                chain,
                transitions = total,
                warmup = cfg.warmup,
                retained = cfg.ndraws,
                elapsed_seconds = ws.prev_sec + (time() - t0),
                calls = ws.target.calls,
                numerical_rejections = ws.target.rejected,
            ),
        )
    end
    return chain_dir
end

function worker_status(dir::AbstractString)
    prep = open(deserialize, joinpath(dir, "prepared.jls"))
    cfg = prep.config
    total = cfg.warmup + cfg.ndraws
    chains = map(1:cfg.chains) do c
        cdir = joinpath(dir, "chain-$c")
        paths = isdir(cdir) ? sort(filter(x -> endswith(x, ".jls"), readdir(cdir; join = true))) : String[]
        if isempty(paths)
            return (;
                chain = c,
                completed = 0,
                total,
                fraction = 0.0,
                is_complete = false,
                elapsed_seconds = 0.0,
                step_size = NaN,
            )
        end
        cp = open(deserialize, last(paths))
        (;
            chain = c,
            completed = cp.last,
            total,
            fraction = cp.last / total,
            is_complete = isfile(joinpath(cdir, "complete.json")),
            elapsed_seconds = cp.elapsed_seconds,
            calls = cp.calls,
            rejected = cp.rejected,
            step_size = last(cp.stats).step_size,
        )
    end
    return (;
        directory = String(dir),
        total_per_chain = total,
        all_complete = all(x -> x.is_complete, chains),
        chains,
    )
end

function _assemble_chain_blocks(chain_dir::AbstractString, warmup::Int, ndraws::Int, dim::Int)
    paths = sort(filter(x -> endswith(x, ".jls"), readdir(chain_dir; join = true)))
    !isempty(paths) || throw(ArgumentError("no checkpoint blocks in $chain_dir"))
    expected_next = 1
    warm_stats = NamedTuple[]
    ret_stats = NamedTuple[]
    ret_parts = Matrix{Float64}[]
    last_cp = nothing
    for path in paths
        cp = open(deserialize, path)
        cp.first == expected_next || throw(ArgumentError("non-contiguous checkpoint range in $path"))
        expected_next = cp.last + 1
        for (row, st) in enumerate(cp.stats)
            if st.iteration <= warmup
                push!(warm_stats, st)
            else
                push!(ret_stats, st)
                push!(ret_parts, Matrix{Float64}(cp.raw[row:row, :]))
            end
        end
        last_cp = cp
    end
    expected_next - 1 == warmup + ndraws ||
        throw(ArgumentError("incomplete chain in $chain_dir ($(expected_next - 1) / $(warmup + ndraws))"))
    draws = vcat(ret_parts...)
    size(draws) == (ndraws, dim) || throw(ArgumentError("retained draw shape mismatch in $chain_dir"))
    meta = (;
        chain = last_cp.chain,
        elapsed_seconds = last_cp.elapsed_seconds,
        calls = last_cp.calls,
        numerical_rejections = last_cp.rejected,
    )
    return (; draws, warm_stats, ret_stats, meta)
end

function collect_fit(dir::AbstractString)
    prep = open(deserialize, joinpath(dir, "prepared.jls"))
    cfg = prep.config
    m = prep.model
    assembled = [_assemble_chain_blocks(joinpath(dir, "chain-$c"), cfg.warmup, cfg.ndraws, m.dim) for c in 1:cfg.chains]
    draws = vcat([a.draws for a in assembled]...)
    warm_stats = vcat([a.warm_stats for a in assembled]...)
    ret_stats = vcat([a.ret_stats for a in assembled]...)
    meta = [a.meta for a in assembled]
    return _build_star_result(
        m,
        cfg,
        draws,
        warm_stats,
        ret_stats;
        provenance = (;
            operation = :multi_worker_fit,
            seeds = copy(cfg.seeds),
            controls = sampler_controls(cfg),
            chain_meta = meta,
        ),
    )
end
