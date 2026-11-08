function _map_to_same_physical_q(
    m_base::StarModel,
    m_alt::StarModel,
    q_base::AbstractVector{Float64},
)
    b = _layout(m_base)
    q_raw_base = _transport_reference(m_base, q_base)
    q_raw_alt = copy(q_raw_base)
    log_jac = 0.0
    if m_alt.prior.step_sd != m_base.prior.step_sd || m_alt.prior.step_spacing != m_base.prior.step_spacing
        scale = m_base.prior.step_sd / m_alt.prior.step_sd
        delta_sp = m_base.prior.step_spacing - m_alt.prior.step_spacing
        n_coords = 0
        for c in 1:m_base.D
            mc = m_base.M[c]
            if mc > 1
                v_lin = collect(Float64, (1:mc) .- (mc + 1) / 2)
                shift = (delta_sp / m_alt.prior.step_sd) .* _helmert_pullback(v_lin)
                q_raw_alt[b.steps[c]] .= scale .* q_raw_base[b.steps[c]] .+ shift
                n_coords += length(b.steps[c])
            end
        end
        log_jac += n_coords * log(scale)
    end
    q_alt = _transport_reference(m_alt, q_raw_alt; inverse = true)
    return q_alt, log_jac
end

function _check_physical_invariance(
    m_base::StarModel,
    m_alt::StarModel,
    q_base::AbstractVector{Float64},
    q_alt::AbstractVector{Float64},
    log_jac::Float64,
    lr_s::Float64,
)
    c0 = _coordinates(m_base, q_base; raw_input = false)
    c1 = _coordinates(m_alt, q_alt; raw_input = false)
    phys_err = max(
        maximum(abs, c0.A .- c1.A),
        maximum(abs, c0.S .- c1.S),
        maximum(abs, c0.mu .- c1.mu),
        maximum(abs, c0.phi .- c1.phi),
        maximum(maximum(abs, c0.tau[c] .- c1.tau[c]) for c in 1:m_base.D),
    )
    full_base, _ = evaluate_density_gradient(m_base, q_base; likelihood = true, compute_gradient = false)
    full_alt, _ = evaluate_density_gradient(m_alt, q_alt; likelihood = true, compute_gradient = false)
    ll_err = abs(((full_alt + log_jac) - full_base) - lr_s)
    return phys_err, ll_err
end

function _weighted_quantiles(
    vals::AbstractVector{Float64},
    norm_lw::AbstractVector{Float64},
    probs::Tuple{Vararg{Float64}},
)
    ord = sortperm(vals)
    vs = vals[ord]
    ws = exp.(norm_lw[ord])
    ws ./= sum(ws)
    cw = cumsum(ws)
    return map(p -> vs[clamp(searchsortedfirst(cw, p), 1, length(vs))], probs)
end

function _default_focal_sensitivity_names(m::StarModel)
    cids = [c.id for c in m.criteria]
    root = cids[1]
    branches = cids[2:end]
    names = vcat(
        ["cor_entity_direct[$b]" for b in branches],
        ["cor_entity_ref_expected_score[$b]" for b in branches],
        ["R_entity[$root,$b]" for b in branches],
    )
    if m.spec.include_phi
        append!(names, ["phi[$b]" for b in branches])
    end
    return names
end

function _evaluate_single_prior_variant(
    res::StarResult,
    sub,
    base_lp::Vector{Float64},
    f_idxs::Vector{Int},
    vid,
    pr_alt,
    verify_draws::Int,
    retain_weights::Bool,
)
    m_base = res.model
    draws = res.draws
    n_chains = res.config.chains
    S = size(draws, 1)
    k_th = _ps_khat_threshold(S)
    m_alt = with_options(m_base; prior = pr_alt)
    # Establish target identity from every declared prior parameter, never from
    # observed weights: a different prior can have constant ratios on poor draws.
    unchanged = _prior_namedtuple(m_alt.prior) == _prior_namedtuple(m_base.prior)
    lr = zeros(Float64, S)
    max_p_err = 0.0
    max_l_err = 0.0
    n_verify = clamp(verify_draws, 1, S)
    for s in (unchanged ? (1:0) : (1:S))
        qb = view(draws, s, :)
        qa, ljac = _map_to_same_physical_q(m_base, m_alt, qb)
        alt_lp, _ = evaluate_density_gradient(m_alt, qa; likelihood = false, compute_gradient = false)
        lr[s] = (alt_lp + ljac) - base_lp[s]
        if s <= n_verify
            pe, le = _check_physical_invariance(m_base, m_alt, qb, qa, ljac, lr[s])
            max_p_err = max(max_p_err, pe)
            max_l_err = max(max_l_err, le)
        end
    end
    (max_p_err <= 1e-10 && max_l_err <= 1e-9) || throw(
        ErrorException(
            "prior_sensitivity physical invariance check failed for variant '$vid': " *
            "max_physical_coord_error=$max_p_err, max_likelihood_invariance_error=$max_l_err",
        ),
    )
    reff = unchanged ? nothing : _relative_eff_exp_ll(lr, n_chains)
    ps = unchanged ? (norm_log_weights = fill(-log(S), S), pareto_k = nothing, n_eff = nothing) :
        _psis_smooth_log_ratios(lr; r_eff = reff)
    w = exp.(ps.norm_log_weights)
    w ./= sum(w)
    st = if unchanged
        :unchanged_prior
    elseif ps.pareto_k <= 0.5
        :psis_qualified_good_k
    elseif ps.pareto_k <= k_th
        :psis_qualified_ok_k
    else
        :refit_required_high_pareto_k
    end
    est_rows = map(f_idxs) do j
        col = view(sub.draws, :, j)
        bm = mean(col)
        wm = unchanged ? bm : dot(w, col)
        qs = _weighted_quantiles(col, ps.norm_log_weights, (0.025, 0.5, 0.975))
        (;
            parameter = sub.names[j],
            baseline_mean = bm,
            alt_psis_mean = wm,
            mean_shift = wm - bm,
            alt_psis_sd = sqrt(max(dot(w, (col .- wm).^2), 0.0)),
            alt_psis_q025 = qs[1],
            alt_psis_median = qs[2],
            alt_psis_q975 = qs[3],
        )
    end
    base_rec = (;
        variant_id = String(vid),
        prior = _prior_namedtuple(m_alt.prior),
        pareto_k = ps.pareto_k,
        pareto_k_threshold = k_th,
        r_eff = reff,
        psis_n_eff = ps.n_eff,
        status = st,
        max_physical_coord_error = max_p_err,
        max_likelihood_invariance_error = max_l_err,
        estimands = est_rows,
    )
    if retain_weights
        return merge(
            base_rec,
            (; raw_log_ratios = lr, smoothed_norm_log_weights = ps.norm_log_weights),
        )
    end
    return base_rec
end

"""
    prior_sensitivity(res::StarResult, variants; parameters=nothing, verify_draws=5, retain_weights=false)

Evaluate Pareto-smoothed importance-sampling (PSIS) prior sensitivity across alternative
`PriorConfig` specifications while holding physical coordinates `(A, S, mu, tau, phi)`
and conditional event likelihoods invariant to machine precision.

An exactly identical resolved prior returns `status = :unchanged_prior`, with the
baseline empirical distribution and exactly zero mean shifts. PSIS is unnecessary:
`pareto_k`, `r_eff` and `psis_n_eff` are `nothing` (JSON `null`). The existing
`alt_psis_*` fields retain their names; quantiles use the weighted empirical CDF.
This status does not qualify the original fit: its sampling warnings, diagnostics
and uncertainty remain relevant. No focal MCMC MCSE is computed here. Constant
weights alone do not establish prior identity or suppress PSIS failures.
"""
function prior_sensitivity(
    res::StarResult,
    variants;
    parameters = nothing,
    verify_draws::Int = 5,
    retain_weights::Bool = false,
)
    _verify_result(res)
    m_base = res.model
    draws = res.draws
    S = size(draws, 1)
    sub = _extract_substantive_draws(m_base, draws)
    focal = parameters === nothing ? _default_focal_sensitivity_names(m_base) : collect(String, parameters)
    lookup = Dict(n => j for (j, n) in enumerate(sub.names))
    all(n -> haskey(lookup, n), focal) || throw(ArgumentError("unknown focal parameter in prior_sensitivity"))
    f_idxs = [lookup[n] for n in focal]
    base_lp = [
        first(evaluate_density_gradient(m_base, view(draws, s, :); likelihood = false, compute_gradient = false))
        for s in 1:S
    ]
    out_variants = [
        _evaluate_single_prior_variant(res, sub, base_lp, f_idxs, vid, pr_alt, verify_draws, retain_weights)
        for (vid, pr_alt) in variants
    ]
    return _envelope(
        res,
        :prior_sensitivity,
        (; baseline_prior = _prior_namedtuple(m_base.prior), variants = out_variants),
    )
end
