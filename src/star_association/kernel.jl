function _helmert(z)
    a = zeros(eltype(z), length(z) + 1)
    tail = zero(eltype(z))
    @inbounds for j in length(z):-1:1
        v = z[j] / sqrt(j * (j + 1))
        a[j + 1] = tail - j * v
        tail += v
    end
    a[1] = tail
    return a
end

function _helmert_pullback(g)
    a = zeros(eltype(g), length(g) - 1)
    prefix = zero(eltype(g))
    @inbounds for j in eachindex(a)
        prefix += g[j]
        a[j] = (prefix - j * g[j + 1]) / sqrt(j * (j + 1))
    end
    return a
end

@inline function _cp_masks(m::StarModel)
    return (;
        entity_cp = m.entity_basis.cp_mask,
        rater_cp = m.rater_basis.cp_mask,
        n_cp_entity = m.entity_basis.n_cp,
        n_cp_rater = m.rater_basis.n_cp,
    )
end

function _cov_root(q_sc, D::Int, eta::Real)
    n_corr = (D * (D - 1)) ÷ 2
    return Diagonal(exp.(q_sc[1:D])) * C.correlation_state(q_sc[(D + 1):(D + n_corr)], D; eta).L
end

function _lkj_logprior_and_grad(q_corr, D::Int, eta::Real)
    val = zero(eltype(q_corr))
    g = similar(q_corr)
    k = 0
    for i in 2:D, j in 1:(i - 1)
        k += 1
        a = eta + ((D - 1) - j) / 2
        z = tanh(q_corr[k])
        abs(z) < 1 || throw(DomainError(q_corr[k], "saturated partial correlation"))
        val += a * log1p(-z * z) - logbeta(0.5, a)
        g[k] = -2 * a * z
    end
    return val, g
end

function _logsumexp_generic(v)
    mx = maximum(v)
    s = zero(eltype(v))
    for x in v
        s += exp(x - mx)
    end
    return mx + log(s)
end

function _reference_shifts(side, p::PriorConfig, M::AbstractVector{Int})
    T = eltype(side)
    D = length(M)
    m0 = M[1]
    n_branch = D - 1
    branch = zeros(T, m0 + 1)
    phi_offset = n_branch + sum(M[c] - 1 for c in 2:D)
    pos = n_branch
    for b_idx in 1:n_branch
        mc = M[b_idx + 1]
        steps_c = if mc == 1
            zeros(T, 1)
        else
            sc = side[(pos + 1):(pos + mc - 1)]
            pos += mc - 1
            p.step_sd * _helmert(sc) + p.step_spacing .* ((1:mc) .- (mc + 1) / 2)
        end
        u = [zero(T); cumsum(side[b_idx] .- steps_c)]
        phi_c = side[phi_offset + b_idx]
        for k in 0:m0
            branch[k + 1] += _logsumexp_generic(
                [u[l + 1] + phi_c * (k / m0 - 0.5) * (l / mc - 0.5) for l in 0:mc]
            )
        end
    end
    slope = (branch[m0 + 1] - branch[1]) / m0
    return [-slope; _helmert_pullback(diff(branch) .- slope) ./ p.step_sd]
end

function _reference_blocks(m::StarModel)
    b = _layout(m)
    changed = [first(b.mu); collect(b.steps[1])]
    side = [collect(b.mu)[2:m.D]; vcat(collect.(b.steps[2:m.D])...); collect(b.phi)]
    return changed, side
end

function _transport_reference(m::StarModel, q; inverse::Bool = false)
    if !m.spec.reference_prior || !m.spec.include_phi
        return copy(q)
    end
    changed, side = _reference_blocks(m)
    out = copy(q)
    sign_mult = inverse ? -1 : 1
    out[changed] .+= sign_mult .* _reference_shifts(q[side], m.prior, m.M)
    return out
end

function from_ncp_reference(m::StarModel, q_ncp::AbstractVector)
    b = _layout(m)
    mk = _cp_masks(m)
    length(q_ncp) == b.dim || throw(DimensionMismatch("expected length $(b.dim)"))
    q_raw = _transport_reference(m, q_ncp)
    li = _cov_root([q_raw[b.si]; q_raw[b.ci]], m.D, m.prior.entity_lkj_eta)
    lr = _cov_root([q_raw[b.sr]; q_raw[b.cr]], m.D, m.prior.rater_lkj_eta)
    out = copy(q_ncp)
    for (blk, n, L_fac, cp_mk) in ((b.zi, m.I, li, mk.entity_cp), (b.zr, m.R, lr, mk.rater_cp))
        Z = reshape(view(q_ncp, blk), n - 1, m.D)
        Q = reshape(view(out, blk), n - 1, m.D)
        Z_Lt = Z * L_fac'
        @inbounds for c in 1:m.D, j in 1:(n - 1)
            Q[j, c] = cp_mk[j] ? Z_Lt[j, c] : Z[j, c]
        end
    end
    return out
end

function to_ncp_reference(m::StarModel, q_spec::AbstractVector)
    b = _layout(m)
    mk = _cp_masks(m)
    length(q_spec) == b.dim || throw(DimensionMismatch("expected length $(b.dim)"))
    q_raw = _transport_reference(m, q_spec)
    li = _cov_root([q_raw[b.si]; q_raw[b.ci]], m.D, m.prior.entity_lkj_eta)
    lr = _cov_root([q_raw[b.sr]; q_raw[b.cr]], m.D, m.prior.rater_lkj_eta)
    out = copy(q_spec)
    for (blk, n, L_fac, cp_mk) in ((b.zi, m.I, li, mk.entity_cp), (b.zr, m.R, lr, mk.rater_cp))
        invL = Matrix(inv(LowerTriangular(L_fac)))
        Q = reshape(view(q_spec, blk), n - 1, m.D)
        Z = reshape(view(out, blk), n - 1, m.D)
        Q_invLt = Q * invL'
        @inbounds for c in 1:m.D, j in 1:(n - 1)
            Z[j, c] = cp_mk[j] ? Q_invLt[j, c] : Q[j, c]
        end
    end
    return out
end

function log_jacobian_to_ncp(m::StarModel, q_spec::AbstractVector)
    b = _layout(m)
    mk = _cp_masks(m)
    length(q_spec) == b.dim || throw(DimensionMismatch("expected length $(b.dim)"))
    q_raw = _transport_reference(m, q_spec)
    li = _cov_root([q_raw[b.si]; q_raw[b.ci]], m.D, m.prior.entity_lkj_eta)
    lr = _cov_root([q_raw[b.sr]; q_raw[b.cr]], m.D, m.prior.rater_lkj_eta)
    return -mk.n_cp_entity * sum(log, diag(li)) - mk.n_cp_rater * sum(log, diag(lr))
end

function _unpack_facet(q_block, basis::FacetBasis, D::Int, L_fac::AbstractMatrix)
    T = promote_type(eltype(q_block), eltype(L_fac))
    n = length(basis.perm)
    Q = reshape(q_block, n - 1, D)
    M_mat = Matrix{T}(undef, n - 1, D)
    Z_mat = Matrix{T}(undef, n - 1, D)
    invL = Matrix(inv(LowerTriangular(L_fac)))
    Q_invLt = Q * invL'
    Q_Lt = Q * L_fac'
    @inbounds for c in 1:D, j in 1:(n - 1)
        if basis.cp_mask[j]
            M_mat[j, c] = Q[j, c]
            Z_mat[j, c] = Q_invLt[j, c]
        else
            M_mat[j, c] = Q_Lt[j, c]
            Z_mat[j, c] = Q[j, c]
        end
    end
    E = Matrix{T}(undef, n, D)
    @inbounds for c in 1:D
        e_ord = _helmert(view(M_mat, :, c))
        for j in 1:n
            E[basis.perm[j], c] = e_ord[j]
        end
    end
    return (; Q, M_mat, Z_mat, E, invL)
end

function _coordinates(m::StarModel, q; raw_input::Bool = false)
    b = _layout(m)
    length(q) == b.dim && all(isfinite, q) || throw(ArgumentError("invalid parameter vector"))
    mk = _cp_masks(m)
    q_raw = raw_input ? q : _transport_reference(m, q)
    li = _cov_root([q_raw[b.si]; q_raw[b.ci]], m.D, m.prior.entity_lkj_eta)
    lr = _cov_root([q_raw[b.sr]; q_raw[b.cr]], m.D, m.prior.rater_lkj_eta)
    fi = _unpack_facet(view(q_raw, b.zi), m.entity_basis, m.D, li)
    fr = _unpack_facet(view(q_raw, b.zr), m.rater_basis, m.D, lr)
    tau = [
        m.M[c] == 1 ? zeros(eltype(q_raw), 1) :
            (m.prior.step_sd * _helmert(view(q_raw, b.steps[c])) +
                m.prior.step_spacing .* ((1:m.M[c]) .- (m.M[c] + 1) / 2))
        for c in 1:m.D
    ]
    phi = m.spec.include_phi ? q_raw[b.phi] : zeros(eltype(q_raw), m.D - 1)
    return (;
        b,
        mk,
        li,
        lr,
        fi,
        fr,
        A = fi.E,
        S = fr.E,
        tau,
        mu = q_raw[b.mu],
        reference_mu = q[b.mu],
        phi,
    )
end

function _reference_mu_and_tau(m::StarModel, q)
    b = _layout(m)
    tau = [
        m.M[c] == 1 ? zeros(eltype(q), 1) :
            (m.prior.step_sd * _helmert(view(q, b.steps[c])) +
                m.prior.step_spacing .* ((1:m.M[c]) .- (m.M[c] + 1) / 2))
        for c in 1:m.D
    ]
    return (; mu = q[b.mu], tau)
end

"""
    coordinates(m::StarModel, q::AbstractVector)

Unpack unconstrained parameter vector `q` into named physical model parameters
(`A`, `S`, `mu`, `reference_mu`, `tau`, `reference_tau`, `phi`, `entity_sd`, `rater_sd`,
`L_entity`, `L_rater`, `R_entity`, `R_rater`).
"""
function coordinates(m::StarModel, q::AbstractVector)
    v = _coordinates(m, q; raw_input = false)
    v_ref = _reference_mu_and_tau(m, q)
    ri = Matrix(C.correlation_state(q[v.b.ci], m.D; eta = m.prior.entity_lkj_eta).R)
    rr = Matrix(C.correlation_state(q[v.b.cr], m.D; eta = m.prior.rater_lkj_eta).R)
    return (;
        A = v.A,
        S = v.S,
        mu = v.mu,
        reference_mu = v_ref.mu,
        tau = v.tau,
        reference_tau = v_ref.tau,
        phi = v.phi,
        entity_sd = exp.(q[v.b.si]),
        rater_sd = exp.(q[v.b.sr]),
        L_entity = Matrix(v.li),
        L_rater = Matrix(v.lr),
        R_entity = ri,
        R_rater = rr,
    )
end

"""
    reparameterize_point(target_model::StarModel, source_model::StarModel, q_src::AbstractVector)

Exact coordinate bijection mapping a parameter vector `q_src` from `source_model` into
`target_model` while preserving identical physical abilities `A`, severities `S`,
thresholds `tau`, intercepts `mu`, associations `phi`, scales, and correlation matrices.
Works seamlessly across `:cp`, `:ncp`, `:cp_ncp`, `cp_min_hd`, and `basis_order`
(`:descending_schur` <-> `:legacy_lexicographic`).
"""
function reparameterize_point(
    target_model::StarModel,
    source_model::StarModel,
    q_src::AbstractVector,
)
    (source_model.I == target_model.I &&
        source_model.R == target_model.R &&
        source_model.D == target_model.D &&
        source_model.M == target_model.M &&
        source_model.spec.include_phi == target_model.spec.include_phi &&
        source_model.spec.reference_prior == target_model.spec.reference_prior &&
        _prior_namedtuple(source_model.prior) == _prior_namedtuple(target_model.prior)) ||
        throw(ArgumentError("source_model and target_model must share dimensions, prior, association, and reference_prior"))
    v = _coordinates(source_model, q_src; raw_input = false)
    b = v.b
    out = copy(Float64.(q_src))
    for (blk, E_phys, basis_tgt, invL) in (
        (b.zi, v.A, target_model.entity_basis, v.fi.invL),
        (b.zr, v.S, target_model.rater_basis, v.fr.invL),
    )
        n = length(basis_tgt.perm)
        M_tgt = Matrix{Float64}(undef, n - 1, target_model.D)
        e_ord = Vector{Float64}(undef, n)
        @inbounds for c in 1:target_model.D
            for j in 1:n
                e_ord[j] = E_phys[basis_tgt.perm[j], c]
            end
            M_tgt[:, c] .= _helmert_pullback(e_ord)
        end
        Z_tgt = M_tgt * invL'
        Q_tgt = reshape(view(out, blk), n - 1, target_model.D)
        @inbounds for c in 1:target_model.D, j in 1:(n - 1)
            Q_tgt[j, c] = basis_tgt.cp_mask[j] ? M_tgt[j, c] : Z_tgt[j, c]
        end
    end
    return out
end

function _scratch(M::AbstractVector{Int}, ::Type{T} = Float64) where {T}
    D = length(M)
    max_M = maximum(M)
    max_bM = maximum(view(M, 2:D))
    return (
        u = zeros(T, max_M + 1, D),
        cond = zeros(T, max_bM + 1, M[1] + 1, D - 1),
        logs = zeros(T, M[1] + 1),
        pm = zeros(T, max_M + 1, D),
        edge = zeros(T, D - 1),
        tmp = zeros(T, max_bM + 1),
    )
end

@inline function _lse_prefix(buf, len::Int)
    vmax = buf[1]
    @inbounds for i in 2:len
        buf[i] > vmax && (vmax = buf[i])
    end
    den = zero(eltype(buf))
    @inbounds for i in 1:len
        den += exp(buf[i] - vmax)
    end
    return vmax + log(den)
end

function _event_kernel!(s, eta, tau, phi, M::AbstractVector{Int})
    T = eltype(s.u)
    D = length(M)
    m0 = M[1]
    u = s.u
    cond = s.cond
    logs = s.logs
    pm = s.pm
    edge = s.edge
    tmp = s.tmp
    fill!(pm, zero(T))
    fill!(edge, zero(T))
    @inbounds for c in 1:D
        u[1, c] = zero(T)
        for k in 1:M[c]
            u[k + 1, c] = u[k, c] + eta[c] - tau[c][k]
        end
    end
    @inbounds for k in 0:m0
        logs[k + 1] = u[k + 1, 1]
        hk = k / m0 - 0.5
        for c in 2:D
            mc = M[c]
            phic = phi[c - 1]
            for l in 0:mc
                tmp[l + 1] = u[l + 1, c] + phic * hk * (l / mc - 0.5)
            end
            zc = _lse_prefix(tmp, mc + 1)
            logs[k + 1] += zc
            for l in 0:mc
                cond[l + 1, k + 1, c - 1] = exp(tmp[l + 1] - zc)
            end
        end
    end
    z = _lse_prefix(logs, m0 + 1)
    @inbounds for k in 0:m0
        pk = exp(logs[k + 1] - z)
        pm[k + 1, 1] = pk
        hk = k / m0 - 0.5
        for c in 2:D, l in 0:M[c]
            prob = pk * cond[l + 1, k + 1, c - 1]
            pm[l + 1, c] += prob
            edge[c - 1] += prob * hk * (l / M[c] - 0.5)
        end
    end
    return z
end

function _prior_and_jacobian!(g, m::StarModel, q, v)
    T = eltype(q)
    b = v.b
    p = m.prior
    mk = v.mk
    val = zero(T)
    function gauss_block!(rng, mu_b, sd_b)
        for j in rng
            z = (q[j] - mu_b) / sd_b
            val += -0.5 * (LOG2PI + z * z) - log(sd_b)
            g[j] = -z / sd_b
        end
    end
    for c in 1:m.D
        gauss_block!(b.steps[c], 0.0, 1.0)
    end
    gauss_block!(b.mu, 0.0, p.mu_sd)
    gauss_block!(b.si, p.entity_log_sd_mean, p.log_sd_sd)
    gauss_block!(b.sr, p.rater_log_sd_mean, p.log_sd_sd)
    if m.spec.include_phi
        gauss_block!(b.phi, 0.0, p.phi_sd)
    end
    ve, ge = _lkj_logprior_and_grad(q[b.ci], m.D, p.entity_lkj_eta)
    val += ve
    g[b.ci] .= ge
    vr, gr = _lkj_logprior_and_grad(q[b.cr], m.D, p.rater_lkj_eta)
    val += vr
    g[b.cr] .= gr
    for fi in (v.fi, v.fr)
        val += -0.5 * (m.D * size(fi.Z_mat, 1) * LOG2PI + sum(abs2, fi.Z_mat))
    end
    val += -mk.n_cp_entity * sum(log, diag(v.li)) - mk.n_cp_rater * sum(log, diag(v.lr))
    return val
end

function _accumulate_likelihood_value(m::StarModel, v)
    T = eltype(v.mu)
    s = _scratch(m.M, T)
    eta = zeros(T, m.D)
    m0 = m.M[1]
    val = zero(T)
    @inbounds for e in eachindex(m.entity)
        i = m.entity[e]
        r = m.rater[e]
        for c in 1:m.D
            eta[c] = v.mu[c] + v.A[i, c] - v.S[r, c]
        end
        z = _event_kernel!(s, eta, v.tau, v.phi, m.M)
        obs = zero(T)
        for c in 1:m.D
            obs += s.u[m.y[c, e] + 1, c]
        end
        for c in 2:m.D
            obs += v.phi[c - 1] * (m.y[1, e] / m0 - 0.5) * (m.y[c, e] / m.M[c] - 0.5)
        end
        val += obs - z
    end
    return val
end

function _accumulate_likelihood_and_scores!(ga, gs, gt, gm, gp, m::StarModel, v)
    T = eltype(v.mu)
    s = _scratch(m.M, T)
    eta = zeros(T, m.D)
    m0 = m.M[1]
    val = zero(T)
    @inbounds for e in eachindex(m.entity)
        i = m.entity[e]
        r = m.rater[e]
        for c in 1:m.D
            eta[c] = v.mu[c] + v.A[i, c] - v.S[r, c]
        end
        z = _event_kernel!(s, eta, v.tau, v.phi, m.M)
        obs = zero(T)
        for c in 1:m.D
            mc = m.M[c]
            yc = m.y[c, e]
            obs += s.u[yc + 1, c]
            expected = zero(T)
            for k in 1:mc
                expected += k * s.pm[k + 1, c]
            end
            h = yc - expected
            ga[i, c] += h
            gs[r, c] -= h
            gm[c] += h
            tail = zero(T)
            for k in mc:-1:1
                tail += s.pm[k + 1, c]
                gt[c][k] += tail - (yc >= k)
            end
        end
        for c in 2:m.D
            h_edge = (m.y[1, e] / m0 - 0.5) * (m.y[c, e] / m.M[c] - 0.5)
            obs += v.phi[c - 1] * h_edge
            gp[c - 1] += h_edge - s.edge[c - 1]
        end
        val += obs - z
    end
    return val
end

function _pullback_facet_block!(
    g,
    q,
    block,
    scale,
    corr,
    fi,
    basis::FacetBasis,
    L_fac,
    ge,
    D::Int,
    eta::Float64,
)
    T = eltype(q)
    n_rows = size(fi.Q, 1)
    n = n_rows + 1
    cp_mask = basis.cp_mask
    n_cp = basis.n_cp
    gM = Matrix{T}(undef, n_rows, D)
    ge_ord = Vector{T}(undef, n)
    @inbounds for c in 1:D
        for j in 1:n
            ge_ord[j] = ge[basis.perm[j], c]
        end
        gM[:, c] .= _helmert_pullback(ge_ord)
    end
    gQ = reshape(view(g, block), n_rows, D)
    Z_invL = fi.Z_mat * fi.invL
    gM_L = gM * L_fac
    S_C = zeros(T, D, D)
    gl_ncp = zeros(T, D, D)
    @inbounds for c in 1:D, j in 1:n_rows
        gQ[j, c] = cp_mask[j] ? (gM[j, c] - Z_invL[j, c]) : (gM_L[j, c] - fi.Z_mat[j, c])
    end
    @inbounds for b_col in 1:D, a in 1:D
        sc = zero(T)
        gl = zero(T)
        for j in 1:n_rows
            if cp_mask[j]
                sc += fi.Q[j, a] * fi.Q[j, b_col]
            else
                gl += gM[j, a] * fi.Q[j, b_col]
            end
        end
        S_C[a, b_col] = sc
        gl_ncp[a, b_col] = gl
    end
    ix = [collect(scale); collect(corr)]
    g[ix] .+= ForwardDiff.gradient(q[ix]) do x
        Lx = _cov_root(x, D, eta)
        invLx = inv(LowerTriangular(Lx))
        v_hyper = n_cp > 0 ? (-0.5 * dot(invLx * S_C, invLx) - n_cp * sum(log, diag(Lx))) : zero(eltype(x))
        if n_cp < n_rows
            v_hyper += dot(gl_ncp, Lx)
        end
        return v_hyper
    end
    return nothing
end

function _apply_reference_transport_pullback!(score_mu, score_steps, score_phi, m::StarModel, q)
    if !m.spec.reference_prior || !m.spec.include_phi
        return nothing
    end
    _, side = _reference_blocks(m)
    score_changed = [score_mu[1]; score_steps[1]]
    corr = ForwardDiff.gradient(
        x -> dot(score_changed, _reference_shifts(x, m.prior, m.M)),
        q[side],
    )
    n_branch = m.D - 1
    pos = n_branch
    for b_idx in 1:n_branch
        score_mu[b_idx + 1] += corr[b_idx]
        mc = m.M[b_idx + 1]
        if mc > 1
            score_steps[b_idx + 1] .+= corr[(pos + 1):(pos + mc - 1)]
            pos += mc - 1
        end
    end
    score_phi .+= corr[(pos + 1):(pos + n_branch)]
    return nothing
end

function evaluate_density_gradient(
    m::StarModel,
    q;
    likelihood::Bool = true,
    compute_gradient::Bool = true,
)
    T = eltype(q)
    v = _coordinates(m, q; raw_input = false)
    g = zeros(T, v.b.dim)
    value = _prior_and_jacobian!(g, m, q, v)
    if !compute_gradient
        if likelihood
            value += _accumulate_likelihood_value(m, v)
        end
        return value, T[]
    end
    ga = zeros(T, m.I, m.D)
    gs = zeros(T, m.R, m.D)
    gt = [zeros(T, mc) for mc in m.M]
    gm = zeros(T, m.D)
    gp = zeros(T, m.D - 1)
    if likelihood
        value += _accumulate_likelihood_and_scores!(ga, gs, gt, gm, gp, m, v)
    end
    _pullback_facet_block!(
        g, q, v.b.zi, v.b.si, v.b.ci, v.fi, m.entity_basis, v.li, ga, m.D, m.prior.entity_lkj_eta,
    )
    _pullback_facet_block!(
        g, q, v.b.zr, v.b.sr, v.b.cr, v.fr, m.rater_basis, v.lr, gs, m.D, m.prior.rater_lkj_eta,
    )
    score_steps = [m.M[c] == 1 ? T[] : (m.prior.step_sd * _helmert_pullback(gt[c])) for c in 1:m.D]
    score_mu = copy(gm)
    score_phi = copy(gp)
    if likelihood
        _apply_reference_transport_pullback!(score_mu, score_steps, score_phi, m, q)
    end
    for c in 1:m.D
        if m.M[c] > 1
            g[v.b.steps[c]] .+= score_steps[c]
        end
    end
    g[v.b.mu] .+= score_mu
    if m.spec.include_phi
        g[v.b.phi] .+= score_phi
    end
    return value, g
end

function _safe_evaluate(
    m::StarModel,
    q::AbstractVector{<:Real};
    likelihood::Bool = true,
    compute_gradient::Bool,
)
    length(q) == m.dim || throw(DimensionMismatch("expected dimension $(m.dim), got $(length(q))"))
    reject() = (-Inf, compute_gradient ? zeros(Float64, m.dim) : Float64[])
    all(isfinite, q) || return reject()
    b = _layout(m)
    all(x -> abs(tanh(x)) < 1, q[[collect(b.ci); collect(b.cr)]]) || return reject()
    all(x -> isfinite(exp(x)) && exp(x) > 0, q[[collect(b.si); collect(b.sr)]]) || return reject()
    qf = Float64.(q)
    all(isfinite, _transport_reference(m, qf)) || return reject()
    val, grad = try
        evaluate_density_gradient(m, qf; likelihood, compute_gradient)
    catch err
        if err isa DomainError || (err isa ArgumentError && occursin("invalid", err.msg))
            return reject()
        end
        rethrow()
    end
    if !isfinite(val) || (compute_gradient && !all(isfinite, grad))
        return reject()
    end
    return val, grad
end

"""
    logprior(m::StarModel, q::AbstractVector)

Return the exact normalized log-prior plus active CP/NCP coordinate log-Jacobian at `q`.
"""
function logprior(m::StarModel, q::AbstractVector{<:Real})
    return first(_safe_evaluate(m, q; likelihood = false, compute_gradient = false))
end

"""
    loglikelihood(m::StarModel, q::AbstractVector)

Return the total log-likelihood across all observed rating events at `q`.
"""
function loglikelihood(m::StarModel, q::AbstractVector{<:Real})
    v = _coordinates(m, q; raw_input = false)
    return _accumulate_likelihood_value(m, v)
end

"""
    pointwise_loglikelihood(m::StarModel, q::AbstractVector)

Return the exact length-`N` vector of per-event conditional log-likelihoods at `q`.
"""
function pointwise_loglikelihood(m::StarModel, q::AbstractVector{<:Real})
    v = _coordinates(m, Float64.(q); raw_input = false)
    N = length(m.entity)
    m0 = m.M[1]
    out = Vector{Float64}(undef, N)
    s = _scratch(m.M, Float64)
    eta = zeros(Float64, m.D)
    @inbounds for e in 1:N
        i = m.entity[e]
        r = m.rater[e]
        for c in 1:m.D
            eta[c] = v.mu[c] + v.A[i, c] - v.S[r, c]
        end
        z = _event_kernel!(s, eta, v.tau, v.phi, m.M)
        obs = 0.0
        for c in 1:m.D
            obs += s.u[m.y[c, e] + 1, c]
        end
        for c in 2:m.D
            obs += v.phi[c - 1] * (m.y[1, e] / m0 - 0.5) * (m.y[c, e] / m.M[c] - 0.5)
        end
        out[e] = obs - z
    end
    return out
end

"""
    logposterior(m::StarModel, q::AbstractVector)

Return the exact joint unnormalized log-posterior density in `m`'s active coordinate chart.
"""
function logposterior(m::StarModel, q::AbstractVector{<:Real})
    return first(_safe_evaluate(m, q; likelihood = true, compute_gradient = false))
end

"""
    logdensity_and_gradient(m::StarModel, q::AbstractVector; likelihood=true)

Return `(value, gradient)` for `m` at `q` using the analytical reverse-mode kernel.
"""
function logdensity_and_gradient(m::StarModel, q::AbstractVector{<:Real}; likelihood::Bool = true)
    return _safe_evaluate(m, q; likelihood, compute_gradient = true)
end

mutable struct _CountedTarget
    model::StarModel
    calls::Int
    rejected::Int
end

function _eval_counted(t::_CountedTarget, q::AbstractVector{<:Real}; compute_gradient::Bool)
    t.calls += 1
    val, grad = _safe_evaluate(t.model, q; likelihood = true, compute_gradient)
    !isfinite(val) && (t.rejected += 1)
    return val, grad
end

L.dimension(m::StarModel) = m.dim
L.capabilities(::Type{StarModel}) = L.LogDensityOrder{1}()
L.logdensity(m::StarModel, q::AbstractVector{<:Real}) = logposterior(m, q)
L.logdensity_and_gradient(m::StarModel, q::AbstractVector{<:Real}) = logdensity_and_gradient(m, q)
