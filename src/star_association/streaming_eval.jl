function _logsumexp_f64(x::AbstractVector{Float64})
    isempty(x) && return -Inf
    m = maximum(x)
    isfinite(m) || return m
    s = 0.0
    @inbounds for v in x
        s += exp(v - m)
    end
    return m + log(s)
end

_logmeanexp_f64(x::AbstractVector{Float64}) = _logsumexp_f64(x) - log(length(x))
_ps_khat_threshold(S::Int) = S > 1 ? min(1.0 - 1.0 / log10(Float64(S)), 0.7) : 0.7

function _n_pareto_tail(r_eff::Real, S::Int)
    reff_safe = (isfinite(r_eff) && r_eff > 0) ? Float64(r_eff) : 1.0
    return ceil(Int, min(0.2 * S, 3.0 * sqrt(S / reff_safe)))
end

function _qgeneralized_pareto(p::Float64, mu::Float64, sigma::Float64, k::Float64)
    (!isfinite(sigma) || sigma <= 0.0) && return NaN
    if k == 0.0
        return mu - sigma * log1p(-p)
    end
    return mu + sigma * expm1(-k * log1p(-p)) / k
end

function _gpdfit_zhang_stephens(
    x_sorted::AbstractVector{Float64};
    wip::Bool = true,
    min_grid_pts::Int = 30,
)
    N = length(x_sorted)
    N == 0 && return (; k = Inf, sigma = NaN)
    xstar = x_sorted[floor(Int, N / 4 + 0.5)]
    xstar <= x_sorted[1] && return (; k = Inf, sigma = NaN)
    M = min_grid_pts + floor(Int, sqrt(Float64(N)))
    xN = x_sorted[N]
    theta = Vector{Float64}(undef, M)
    l_theta = Vector{Float64}(undef, M)
    @inbounds for j in 1:M
        th = 1.0 / xN + (1.0 - sqrt(M / (j - 0.5))) / (3.0 * xstar)
        theta[j] = th
        kj = sum(log1p(-th * x_sorted[i]) for i in 1:N) / N
        l_theta[j] = N * (log(-th / kj) - kj - 1.0)
    end
    lse = _logsumexp_f64(l_theta)
    theta_hat = sum(theta[j] * exp(l_theta[j] - lse) for j in 1:M)
    k_hat = sum(log1p(-theta_hat * x_sorted[i]) for i in 1:N) / N
    sigma_hat = -k_hat / theta_hat
    if wip
        k_hat = (k_hat * N + 5.0) / (N + 10.0)
    end
    return isfinite(k_hat) ? (; k = k_hat, sigma = sigma_hat) : (; k = Inf, sigma = NaN)
end

function _psis_smooth_log_ratios(log_ratios::AbstractVector{Float64}; r_eff::Real = 1.0)
    S = length(log_ratios)
    S >= 5 || throw(ArgumentError("PSIS requires >= 5 draws"))
    reff = (isfinite(r_eff) && r_eff > 0) ? Float64(r_eff) : 1.0
    tail_len = _n_pareto_tail(reff, S)
    max_lr = maximum(log_ratios)
    lw = [log_ratios[s] - max_lr for s in 1:S]
    khat = Inf
    if 5 <= tail_len < S
        ord = sortperm(lw; alg = MergeSort)
        ts = S - tail_len + 1
        if abs(lw[ord[S]] - lw[ord[ts]]) >= eps(Float64) / 100.0
            exp_cut = exp(lw[ord[ts - 1]])
            x_ex = [exp(lw[ord[ts + t - 1]]) - exp_cut for t in 1:tail_len]
            fit = _gpdfit_zhang_stephens(x_ex)
            khat = fit.k
            if isfinite(khat)
                @inbounds for t in 1:tail_len
                    q_val = _qgeneralized_pareto((t - 0.5) / tail_len, 0.0, fit.sigma, khat)
                    lw[ord[ts + t - 1]] = log(q_val + exp_cut)
                end
            end
        end
    end
    @inbounds for s in 1:S
        lw[s] = min(lw[s], 0.0) + max_lr
    end
    lse = _logsumexp_f64(lw)
    norm_lw = [lw[s] - lse for s in 1:S]
    n_eff_raw = 1.0 / sum(exp(2.0 * v) for v in norm_lw)
    return (;
        log_weights = lw,
        norm_log_weights = norm_lw,
        pareto_k = khat,
        tail_len,
        r_eff = reff,
        n_eff_raw,
        n_eff = n_eff_raw * reff,
    )
end

function _relative_eff_exp_ll(ll_col::AbstractVector{Float64}, n_chains::Int)
    S = length(ll_col)
    dpc = div(S, n_chains)
    dpc < 4 && return 1.0
    mx = maximum(ll_col)
    arr = [exp(ll_col[(ch - 1) * dpc + it] - mx) for it in 1:dpc, ch in 1:n_chains]
    ev = Float64(MCMCDiagnosticTools.ess(arr; kind = :basic, split_chains = dpc >= 8 ? 2 : 1))
    return (isfinite(ev) && ev > 0.0) ? (ev / S) : 1.0
end

function _event_rater_strata(m::StarModel)
    rc = copy(m.rater_basis.raw_counts)
    ev_st = [
        something(
            findfirst(st -> st.min_n <= rc[m.rater[e]] <= st.max_n, RATER_COUNT_STRATA),
            length(RATER_COUNT_STRATA),
        )
        for e in eachindex(m.rater)
    ]
    return (; rater_counts = rc, event_stratum = ev_st)
end

function _one_way_cluster_se(
    values::AbstractVector{Float64},
    group_ids::AbstractVector{Int},
    n_groups::Int,
)
    N = length(values)
    N <= 1 && return 0.0
    counts = zeros(Int, n_groups)
    sums = zeros(Float64, n_groups)
    @inbounds for e in 1:N
        g = group_ids[e]
        counts[g] += 1
        sums[g] += values[e]
    end
    act = findall(>(0), counts)
    G_act = length(act)
    G_act <= 1 && return sqrt(N * var(values; corrected = true))
    v_bar = mean(values)
    ss = sum((sums[g] - counts[g] * v_bar)^2 for g in act)
    return sqrt((G_act / (G_act - 1.0)) * ss)
end

function _crossed_sum_se(
    values::AbstractVector{Float64},
    ent_ids::AbstractVector{Int},
    I::Int,
    rat_ids::AbstractVector{Int},
    R::Int,
)
    N = length(values)
    se_obs = N > 1 ? sqrt(N * var(values; corrected = true)) : 0.0
    se_ent = _one_way_cluster_se(values, ent_ids, I)
    se_rat = _one_way_cluster_se(values, rat_ids, R)
    v_raw = se_ent^2 + se_rat^2 - se_obs^2
    return (;
        se_observation = se_obs,
        se_entity_cluster = se_ent,
        se_rater_cluster = se_rat,
        se_twoway_crossed = sqrt(max(v_raw, se_obs^2)),
        twoway_variance_clipped = v_raw < se_obs^2,
    )
end

@inline function _splitmix64_u01(state::UInt64)
    ns = state + 0x9e3779b97f4a7c15
    z = (ns ⊻ (ns >>> 30)) * 0xbf58476d1ce4e5b9
    z = (z ⊻ (z >>> 27)) * 0x94d049bb133111eb
    z = z ⊻ (z >>> 31)
    return Float64(z >>> 11) * (1.0 / 9007199254740992.0), ns
end

@inline function _sample_cat_u01(u::Float64, probs::AbstractVector{Float64}, K::Int)
    cum = 0.0
    @inbounds for k in 1:(K - 1)
        cum += probs[k]
        u <= cum && return k - 1
    end
    return K - 1
end

@inline function _simulate_star_event!(
    y_sim::Vector{Int},
    s_scr,
    M::Vector{Int},
    seed::Int,
    s::Int,
    e::Int,
)
    m0 = M[1]
    st = UInt64(seed) ⊻ (UInt64(s) * 0xd1342543de82ef95) ⊻ (UInt64(e) * 0xbf58476d1ce4e5b9)
    u0, st = _splitmix64_u01(st)
    y0 = _sample_cat_u01(u0, view(s_scr.pm, 1:(m0 + 1), 1), m0 + 1)
    y_sim[1] = y0
    @inbounds for c in 2:length(M)
        mc = M[c]
        uc, st = _splitmix64_u01(st)
        y_sim[c] = _sample_cat_u01(uc, view(s_scr.cond, 1:(mc + 1), y0 + 1, c - 1), mc + 1)
    end
    return y_sim
end

struct _CriteriaAcc
    ll_buf::Matrix{Float64}
    full_ll::Union{Nothing, Matrix{Float64}}
    r_eff_override::Union{Nothing, Vector{Float64}}
    n_chains::Int
    lppd::Vector{Float64}
    p_waic::Vector{Float64}
    elpd_waic::Vector{Float64}
    elpd_raw_loo::Vector{Float64}
    elpd_hill_loo::Vector{Float64}
    hill_k::Vector{Float64}
    elpd_psis::Vector{Float64}
    p_psis::Vector{Float64}
    pareto_k::Vector{Float64}
    psis_neff::Vector{Float64}
    r_eff::Vector{Float64}
end

function _make_criteria_acc(
    S::Int,
    N::Int,
    n_chains::Int,
    chunk_size::Int,
    r_eff_ov,
    retain_mat::Bool,
)
    r_ov = r_eff_ov === nothing ? nothing : Float64.(collect(r_eff_ov))
    r_ov === nothing || length(r_ov) == N || throw(ArgumentError("r_eff_override length != $N"))
    return _CriteriaAcc(
        Matrix{Float64}(undef, S, min(chunk_size, N)),
        retain_mat ? Matrix{Float64}(undef, S, N) : nothing,
        r_ov,
        n_chains,
        Vector{Float64}(undef, N),
        Vector{Float64}(undef, N),
        Vector{Float64}(undef, N),
        Vector{Float64}(undef, N),
        Vector{Float64}(undef, N),
        Vector{Float64}(undef, N),
        Vector{Float64}(undef, N),
        Vector{Float64}(undef, N),
        Vector{Float64}(undef, N),
        Vector{Float64}(undef, N),
        Vector{Float64}(undef, N),
    )
end

_needs_sim(::_CriteriaAcc) = false

@inline function _acc_event!(
    a::_CriteriaAcc,
    s::Int,
    idx::Int,
    ::Int,
    ::StarModel,
    ::Any,
    ll_se::Float64,
    ::Any,
)
    a.ll_buf[s, idx] = ll_se
    return nothing
end

function _acc_chunk!(a::_CriteriaAcc, chunk_start::Int, chunk_len::Int)
    S = size(a.ll_buf, 1)
    if a.full_ll !== nothing
        a.full_ll[:, chunk_start:(chunk_start + chunk_len - 1)] .= view(a.ll_buf, 1:S, 1:chunk_len)
    end
    lr = Vector{Float64}(undef, S)
    hill_tail = B._loo_tail_draws(S, 0.2, 5)
    for idx in 1:chunk_len
        e = chunk_start + idx - 1
        col = view(a.ll_buf, :, idx)
        lppd_e = _logmeanexp_f64(col)
        pw_e = var(col; corrected = true)
        a.lppd[e] = lppd_e
        a.p_waic[e] = pw_e
        a.elpd_waic[e] = lppd_e - pw_e
        @inbounds for s in 1:S
            lr[s] = -col[s]
        end
        a.elpd_raw_loo[e] = -_logmeanexp_f64(lr)
        hs, hk = B._pareto_smoothed_log_ratios(lr, hill_tail)
        a.elpd_hill_loo[e] = B._self_normalized_importance_log_score(col, hs)
        a.hill_k[e] = hk
        reff_e = a.r_eff_override === nothing ? _relative_eff_exp_ll(col, a.n_chains) : a.r_eff_override[e]
        a.r_eff[e] = reff_e
        ps = _psis_smooth_log_ratios(lr; r_eff = reff_e)
        elpd_p = _logsumexp_f64(col .+ ps.norm_log_weights)
        a.elpd_psis[e] = elpd_p
        a.p_psis[e] = lppd_e - elpd_p
        a.pareto_k[e] = ps.pareto_k
        a.psis_neff[e] = ps.n_eff
    end
    return nothing
end

# Bind observations, not priors, dependence choices or parameter coordinates.
function _criteria_comparison_data(m::StarModel)
    ci = sortperm([c.id for c in m.criteria])
    ei = sortperm(m.event_ids)
    observations = (;
        criteria = [(;c.id, levels=copy(c.levels), c.direction) for c in m.criteria[ci]],
        events = [(m.event_ids[e], m.entity_levels[m.entity[e]], m.rater_levels[m.rater[e]],
                   Tuple(m.y[ci,e])) for e in ei],
    )
    binding = B._cache_hash(observations)
    ids = copy(m.event_ids)
    layout = B._cache_hash((;event_ids=ids, entity=m.entity, rater=m.rater, I=m.I, R=m.R))
    return (;event_ids=ids, observation_binding=binding, layout_binding=layout,
        evaluation_unit=:rating_event, conditioning=:joint_posterior_existing_entity_and_rater,
        loo_target=:single_event_omission_fixed_specification, weighting=:equal_event)
end

function _checked_comparison_criteria(record)
    get(record,:schema,nothing)==REPORT_SCHEMA && get(record,:operation,nothing)===:criteria ||
        throw(ArgumentError("compare_models requires Star criteria records"))
    p=record.result
    hasproperty(p,:comparison_data) || throw(ArgumentError(
        "criteria record lacks observed-event identity; use criteria from a fit verified by the current source"))
    d=p.comparison_data
    d.evaluation_unit===:rating_event && d.conditioning===:joint_posterior_existing_entity_and_rater &&
        d.loo_target===:single_event_omission_fixed_specification && d.weighting===:equal_event ||
        throw(ArgumentError("incompatible prediction unit, conditioning or weighting"))
    length(d.event_ids)==p.n_events && all(_nonempty_str,d.event_ids) && allunique(d.event_ids) ||
        throw(ArgumentError("criteria need one distinct ID per rating event"))
    d.observation_binding isa AbstractString && occursin(r"^[0-9a-f]{64}$",d.observation_binding) ||
        throw(ArgumentError("invalid observation binding"))
    d.layout_binding==B._cache_hash((;event_ids=d.event_ids,entity=p.entity,rater=p.rater,I=p.I,R=p.R)) ||
        throw(ArgumentError("criteria event/cluster layout changed"))
    all(length(v)==p.n_events for v in (p.entity,p.rater,p.event_stratum,
        p.pointwise.elpd_waic,p.pointwise.elpd_psis_loo,p.pointwise.pareto_k)) ||
        throw(ArgumentError("criteria pointwise arrays do not match rating events"))
    all(isfinite,p.pointwise.elpd_waic) && all(isfinite,p.pointwise.elpd_psis_loo) ||
        throw(ArgumentError("comparison requires finite pointwise ELPD"))
    return p
end

_criteria_uncertainty(entity,rater) = (
    standard_error=:existing_crossed_variance_approximation,
    variance_formula=:entity_plus_rater_minus_observation,
    variance_floor=:observation_variance, mcmc_mcse=:not_computed,
    repeated_entity_rater_pairs=length(unique(zip(entity,rater)))<length(entity),
    intersection_cluster_adjustment=:not_computed,
)

function _finalize_criteria(a::_CriteriaAcc, m::StarModel)
    S = size(a.ll_buf, 1)
    N = length(m.entity)
    k_th = _ps_khat_threshold(S)
    st_info = _event_rater_strata(m)
    strata_rows = map(eachindex(RATER_COUNT_STRATA)) do st
        info = RATER_COUNT_STRATA[st]
        idxs = findall(==(st), st_info.event_stratum)
        n_rat = count(c -> info.min_n <= c <= info.max_n, st_info.rater_counts)
        if isempty(idxs)
            return (;
                stratum = info.label,
                n_raters = n_rat,
                n_events = 0,
                elpd_waic = 0.0,
                p_waic = 0.0,
                high_p_waic_gt_0_4 = 0,
                elpd_psis_loo = 0.0,
                p_psis_loo = 0.0,
                k_good_le_0_5 = 0,
                k_ok_0_5_to_thresh = 0,
                k_bad_gt_thresh = 0,
                k_very_bad_gt_1 = 0,
                max_pareto_k = NaN,
                median_pareto_k = NaN,
                status = :empty,
            )
        end
        pk = a.pareto_k[idxs]
        pw = a.p_waic[idxs]
        nb = count(>(k_th), pk)
        (;
            stratum = info.label,
            n_raters = n_rat,
            n_events = length(idxs),
            elpd_waic = sum(a.elpd_waic[idxs]),
            p_waic = sum(pw),
            high_p_waic_gt_0_4 = count(>(0.4), pw),
            elpd_psis_loo = sum(a.elpd_psis[idxs]),
            p_psis_loo = sum(a.p_psis[idxs]),
            k_good_le_0_5 = count(<=(0.5), pk),
            k_ok_0_5_to_thresh = count(x -> 0.5 < x <= k_th, pk),
            k_bad_gt_thresh = nb,
            k_very_bad_gt_1 = count(>(1.0), pk),
            max_pareto_k = maximum(pk),
            median_pareto_k = median(pk),
            status = nb == 0 ? :ok : :diagnostic_only_high_pareto_k,
        )
    end
    bad_k = count(>(k_th), a.pareto_k)
    return (;
        n_events = N,
        comparison_data = _criteria_comparison_data(m),
        uncertainty = _criteria_uncertainty(m.entity,m.rater),
        entity = copy(m.entity),
        rater = copy(m.rater),
        I = m.I,
        R = m.R,
        event_stratum = st_info.event_stratum,
        waic = (;
            elpd_waic = sum(a.elpd_waic),
            p_waic = sum(a.p_waic),
            lppd = sum(a.lppd),
            waic = -2.0 * sum(a.elpd_waic),
            high_p_waic_gt_0_4_count = count(>(0.4), a.p_waic),
            se = _crossed_sum_se(a.elpd_waic, m.entity, m.I, m.rater, m.R),
        ),
        psis_loo = (;
            estimator = :vehtari_zhang_stephens_gpd_wip,
            elpd_loo = sum(a.elpd_psis),
            p_loo = sum(a.p_psis),
            lppd = sum(a.lppd),
            looic = -2.0 * sum(a.elpd_psis),
            pareto_k_threshold = k_th,
            k_good_le_0_5 = count(<=(0.5), a.pareto_k),
            k_ok_0_5_to_thresh = count(x -> 0.5 < x <= k_th, a.pareto_k),
            bad_pareto_k_count = bad_k,
            very_bad_pareto_k_gt_1_count = count(>(1.0), a.pareto_k),
            max_pareto_k = maximum(a.pareto_k),
            median_pareto_k = median(a.pareto_k),
            min_n_eff = minimum(a.psis_neff),
            status = bad_k == 0 ? :ok : :diagnostic_only_high_pareto_k,
            se = _crossed_sum_se(a.elpd_psis, m.entity, m.I, m.rater, m.R),
        ),
        native_candidates = (;
            elpd_raw_loo = sum(a.elpd_raw_loo),
            elpd_hill_smoothed_loo = sum(a.elpd_hill_loo),
            max_hill_pareto_k = maximum(a.hill_k),
        ),
        rater_stratum_criteria = strata_rows,
        pointwise = (;
            lppd = a.lppd,
            p_waic = a.p_waic,
            elpd_waic = a.elpd_waic,
            elpd_psis_loo = a.elpd_psis,
            p_psis_loo = a.p_psis,
            pareto_k = a.pareto_k,
            r_eff = a.r_eff,
            psis_n_eff = a.psis_neff,
        ),
        pointwise_matrix = a.full_ll,
    )
end

struct _MarginalPPCAcc
    obs::Vector{Vector{Int}}
    exp_cnt::Vector{Matrix{Float64}}
    sim_cnt::Vector{Matrix{Int}}
end

function _make_marginal_ppc_acc(m::StarModel, S::Int)
    obs = [zeros(Int, m.M[c] + 1) for c in 1:m.D]
    for e in eachindex(m.entity), c in 1:m.D
        obs[c][m.y[c, e] + 1] += 1
    end
    return _MarginalPPCAcc(
        obs,
        [zeros(Float64, S, m.M[c] + 1) for c in 1:m.D],
        [zeros(Int, S, m.M[c] + 1) for c in 1:m.D],
    )
end

_needs_sim(::_MarginalPPCAcc) = true
_acc_chunk!(::_MarginalPPCAcc, ::Int, ::Int) = nothing

@inline function _acc_event!(
    a::_MarginalPPCAcc,
    s::Int,
    ::Int,
    ::Int,
    m::StarModel,
    s_scr,
    ::Float64,
    y_sim::Vector{Int},
)
    @inbounds for c in 1:m.D
        for k in 0:m.M[c]
            a.exp_cnt[c][s, k + 1] += s_scr.pm[k + 1, c]
        end
        a.sim_cnt[c][s, y_sim[c] + 1] += 1
    end
    return nothing
end

function _finalize_marginal_ppc(a::_MarginalPPCAcc, m::StarModel)
    N = length(m.entity)
    rows = NamedTuple[]
    for c in 1:m.D, k in 0:m.M[c]
        obs_c = a.obs[c][k + 1]
        sc = view(a.sim_cnt[c], :, k + 1)
        ec = view(a.exp_cnt[c], :, k + 1)
        push!(
            rows,
            (;
                criterion = m.criteria[c].id,
                canonical_index = k,
                display_score = m.criteria[c].canonical_to_raw[k + 1],
                observed_count = obs_c,
                observed_rate = obs_c / N,
                expected_count_mean = mean(ec),
                expected_rate_mean = mean(ec) / N,
                pred_count_q025 = quantile(sc, 0.025),
                pred_count_q500 = quantile(sc, 0.500),
                pred_count_q975 = quantile(sc, 0.975),
                pred_rate_q025 = quantile(sc, 0.025) / N,
                pred_rate_q975 = quantile(sc, 0.975) / N,
                ppp_ge_obs = mean(sc .>= obs_c),
                ppp_le_obs = mean(sc .<= obs_c),
            ),
        )
    end
    return rows
end

struct _JointPairPPCAcc
    obs_tab::Vector{Matrix{Int}}
    obs_cross::Vector{Float64}
    exp_tab::Vector{Array{Float64, 3}}
    sim_tab::Vector{Array{Int, 3}}
    exp_cross::Matrix{Float64}
    sim_cross::Matrix{Float64}
end

function _make_joint_pair_ppc_acc(m::StarModel, S::Int)
    m0 = m.M[1]
    obs_tab = [zeros(Int, m0 + 1, m.M[c] + 1) for c in 2:m.D]
    obs_cross = zeros(Float64, m.D - 1)
    for e in eachindex(m.entity)
        y0 = m.y[1, e]
        h0 = y0 / m0 - 0.5
        for c in 2:m.D
            yc = m.y[c, e]
            obs_tab[c - 1][y0 + 1, yc + 1] += 1
            obs_cross[c - 1] += h0 * (yc / m.M[c] - 0.5)
        end
    end
    return _JointPairPPCAcc(
        obs_tab,
        obs_cross,
        [zeros(Float64, S, m0 + 1, m.M[c] + 1) for c in 2:m.D],
        [zeros(Int, S, m0 + 1, m.M[c] + 1) for c in 2:m.D],
        zeros(Float64, S, m.D - 1),
        zeros(Float64, S, m.D - 1),
    )
end

_needs_sim(::_JointPairPPCAcc) = true
_acc_chunk!(::_JointPairPPCAcc, ::Int, ::Int) = nothing

@inline function _acc_event!(
    a::_JointPairPPCAcc,
    s::Int,
    ::Int,
    ::Int,
    m::StarModel,
    s_scr,
    ::Float64,
    y_sim::Vector{Int},
)
    m0 = m.M[1]
    @inbounds for k in 0:m0
        pk = s_scr.pm[k + 1, 1]
        for c in 2:m.D, l in 0:m.M[c]
            a.exp_tab[c - 1][s, k + 1, l + 1] += pk * s_scr.cond[l + 1, k + 1, c - 1]
        end
    end
    y0_s = y_sim[1]
    h0_s = y0_s / m0 - 0.5
    @inbounds for c in 2:m.D
        yc_s = y_sim[c]
        a.exp_cross[s, c - 1] += s_scr.edge[c - 1]
        a.sim_tab[c - 1][s, y0_s + 1, yc_s + 1] += 1
        a.sim_cross[s, c - 1] += h0_s * (yc_s / m.M[c] - 0.5)
    end
    return nothing
end

function _finalize_joint_pair_ppc(a::_JointPairPPCAcc, m::StarModel)
    N = length(m.entity)
    S = size(a.exp_cross, 1)
    m0 = m.M[1]
    root_meta = m.criteria[1]
    return map(2:m.D) do c
        bi = c - 1
        mc = m.M[c]
        br_meta = m.criteria[c]
        l1_o = zeros(Float64, S)
        l1_r = zeros(Float64, S)
        c2_o = zeros(Float64, S)
        c2_r = zeros(Float64, S)
        max_z = 0.0
        worst = (root_meta.canonical_to_raw[1], br_meta.canonical_to_raw[1])
        cells = NamedTuple[]
        for k in 0:m0, l in 0:mc
            oc = a.obs_tab[bi][k + 1, l + 1]
            sc = view(a.sim_tab[bi], :, k + 1, l + 1)
            ec = view(a.exp_tab[bi], :, k + 1, l + 1)
            zc = (oc - mean(sc)) / max(std(sc; corrected = true), 1e-6)
            if abs(zc) > abs(max_z)
                max_z = zc
                worst = (root_meta.canonical_to_raw[k + 1], br_meta.canonical_to_raw[l + 1])
            end
            push!(
                cells,
                (;
                    root_score = root_meta.canonical_to_raw[k + 1],
                    branch_score = br_meta.canonical_to_raw[l + 1],
                    observed_count = oc,
                    expected_mean = mean(ec),
                    pred_q025 = quantile(sc, 0.025),
                    pred_q975 = quantile(sc, 0.975),
                    standardized_residual = zc,
                ),
            )
            @inbounds for s in 1:S
                ex_s = max(ec[s], 1e-9)
                sm_s = sc[s]
                l1_o[s] += 0.5 * abs(oc - ex_s) / N
                l1_r[s] += 0.5 * abs(sm_s - ex_s) / N
                c2_o[s] += (oc - ex_s)^2 / ex_s
                c2_r[s] += (sm_s - ex_s)^2 / ex_s
            end
        end
        sc_cov = view(a.sim_cross, :, bi) ./ N
        ec_cov = view(a.exp_cross, :, bi) ./ N
        oc_cov = a.obs_cross[bi] / N
        (;
            root = root_meta.id,
            branch = br_meta.id,
            n_cells = (m0 + 1) * (mc + 1),
            l1_tv_obs_mean = mean(l1_o),
            l1_tv_rep_mean = mean(l1_r),
            l1_tv_ppp = mean(l1_r .>= l1_o),
            pearson_chi2_obs_mean = mean(c2_o),
            pearson_chi2_rep_mean = mean(c2_r),
            pearson_chi2_ppp = mean(c2_r .>= c2_o),
            cross_cov_obs = oc_cov,
            cross_cov_expected_mean = mean(ec_cov),
            cross_cov_pred_q025 = quantile(sc_cov, 0.025),
            cross_cov_pred_q975 = quantile(sc_cov, 0.975),
            cross_cov_ppp = mean(sc_cov .>= oc_cov),
            max_abs_cell_z = max_z,
            worst_cell = worst,
            cells,
        )
    end
end

struct _RaterStrataPPCAcc
    ev_stratum::Vector{Int}
    root_focal_can::Int
    obs_ev::Vector{Int}
    obs_root_foc::Vector{Int}
    obs_root_ext::Vector{Int}
    obs_br_ext::Vector{Int}
    sim_root_foc::Matrix{Int}
    sim_root_ext::Matrix{Int}
    sim_br_ext::Matrix{Int}
end

function _make_rater_strata_ppc_acc(m::StarModel, S::Int, focal_root_raw::Union{Nothing, Int})
    st_info = _event_rater_strata(m)
    ns = length(RATER_COUNT_STRATA)
    m0 = m.M[1]
    foc_can = if focal_root_raw !== nothing
        _encode_raw_score(m.criteria[1], focal_root_raw)
    elseif m0 >= 2 && iseven(m0)
        div(m0, 2)
    else
        -1
    end
    obs_ev = zeros(Int, ns)
    obs_rf = zeros(Int, ns)
    obs_re = zeros(Int, ns)
    obs_be = zeros(Int, ns)
    for e in eachindex(m.entity)
        st = st_info.event_stratum[e]
        y0 = m.y[1, e]
        obs_ev[st] += 1
        if y0 == foc_can
            obs_rf[st] += 1
        end
        if y0 == 0 || y0 == m0
            obs_re[st] += 1
        end
        for c in 2:m.D
            if m.y[c, e] == 0 || m.y[c, e] == m.M[c]
                obs_be[st] += 1
            end
        end
    end
    return _RaterStrataPPCAcc(
        st_info.event_stratum,
        foc_can,
        obs_ev,
        obs_rf,
        obs_re,
        obs_be,
        zeros(Int, S, ns),
        zeros(Int, S, ns),
        zeros(Int, S, ns),
    )
end

_needs_sim(::_RaterStrataPPCAcc) = true
_acc_chunk!(::_RaterStrataPPCAcc, ::Int, ::Int) = nothing

@inline function _acc_event!(
    a::_RaterStrataPPCAcc,
    s::Int,
    ::Int,
    e::Int,
    m::StarModel,
    ::Any,
    ::Float64,
    y_sim::Vector{Int},
)
    st = a.ev_stratum[e]
    y0 = y_sim[1]
    m0 = m.M[1]
    if y0 == a.root_focal_can
        a.sim_root_foc[s, st] += 1
    end
    if y0 == 0 || y0 == m0
        a.sim_root_ext[s, st] += 1
    end
    @inbounds for c in 2:m.D
        yc = y_sim[c]
        if yc == 0 || yc == m.M[c]
            a.sim_br_ext[s, st] += 1
        end
    end
    return nothing
end

function _finalize_rater_strata_ppc(a::_RaterStrataPPCAcc, m::StarModel)
    n_br = m.D - 1
    foc_raw = a.root_focal_can >= 0 ? m.criteria[1].canonical_to_raw[a.root_focal_can + 1] : nothing
    return map(eachindex(RATER_COUNT_STRATA)) do st
        nev = a.obs_ev[st]
        lbl = RATER_COUNT_STRATA[st].label
        nev == 0 && return (; stratum = lbl, n_events = 0, root_focal_raw = foc_raw)
        rf_o = a.obs_root_foc[st] / nev
        re_o = a.obs_root_ext[st] / nev
        be_o = a.obs_br_ext[st] / (n_br * nev)
        rf_s = view(a.sim_root_foc, :, st) ./ nev
        re_s = view(a.sim_root_ext, :, st) ./ nev
        be_s = view(a.sim_br_ext, :, st) ./ (n_br * nev)
        (;
            stratum = lbl,
            n_events = nev,
            root_focal_raw = foc_raw,
            root_focal_obs_rate = a.root_focal_can >= 0 ? rf_o : NaN,
            root_focal_pred_q025 = a.root_focal_can >= 0 ? quantile(rf_s, 0.025) : NaN,
            root_focal_pred_q975 = a.root_focal_can >= 0 ? quantile(rf_s, 0.975) : NaN,
            root_focal_ppp = a.root_focal_can >= 0 ? mean(rf_s .>= rf_o) : NaN,
            root_extreme_obs_rate = re_o,
            root_extreme_pred_q025 = quantile(re_s, 0.025),
            root_extreme_pred_q975 = quantile(re_s, 0.975),
            root_extreme_ppp = mean(re_s .>= re_o),
            branch_extreme_obs_rate = be_o,
            branch_extreme_pred_q025 = quantile(be_s, 0.025),
            branch_extreme_pred_q975 = quantile(be_s, 0.975),
            branch_extreme_ppp = mean(be_s .>= be_o),
        )
    end
end

function _stream_events!(
    accs::Tuple,
    res::StarResult;
    chunk_size::Int = 4096,
    seed::Int = 20261030,
)
    m = res.model
    draws = res.draws
    S = size(draws, 1)
    N = length(m.entity)
    m0 = m.M[1]
    chunk_size >= 1 || throw(ArgumentError("chunk_size must be >= 1"))
    need_sim = any(_needs_sim, accs)
    use_cache = N > chunk_size
    coord_cache = if use_cache
        [
            begin
                cs = _coordinates(m, view(draws, s, :); raw_input = false)
                (; A = cs.A, S = cs.S, tau = cs.tau, mu = cs.mu, phi = cs.phi)
            end
            for s in 1:S
        ]
    else
        nothing
    end
    s_scr = _scratch(m.M, Float64)
    eta = zeros(Float64, m.D)
    y_sim = zeros(Int, m.D)
    for c_start in 1:chunk_size:N
        c_len = min(c_start + chunk_size - 1, N) - c_start + 1
        for s in 1:S
            v = if use_cache
                coord_cache[s]
            else
                cs = _coordinates(m, view(draws, s, :); raw_input = false)
                (; A = cs.A, S = cs.S, tau = cs.tau, mu = cs.mu, phi = cs.phi)
            end
            for idx in 1:c_len
                e = c_start + idx - 1
                i = m.entity[e]
                r = m.rater[e]
                @inbounds for c in 1:m.D
                    eta[c] = v.mu[c] + v.A[i, c] - v.S[r, c]
                end
                z = _event_kernel!(s_scr, eta, v.tau, v.phi, m.M)
                obs_lp = 0.0
                @inbounds for c in 1:m.D
                    obs_lp += s_scr.u[m.y[c, e] + 1, c]
                end
                @inbounds for c in 2:m.D
                    obs_lp += v.phi[c - 1] * (m.y[1, e] / m0 - 0.5) * (m.y[c, e] / m.M[c] - 0.5)
                end
                ll_se = obs_lp - z
                if need_sim
                    _simulate_star_event!(y_sim, s_scr, m.M, seed, s, e)
                end
                for acc in accs
                    _acc_event!(acc, s, idx, e, m, s_scr, ll_se, y_sim)
                end
            end
        end
        for acc in accs
            _acc_chunk!(acc, c_start, c_len)
        end
    end
    return nothing
end

"""
    criteria(res::StarResult; chunk_size=4096, r_eff_override=nothing, retain_pointwise_matrix=false)

Compute streaming rating-event WAIC and Vehtari-Zhang-Stephens PSIS-LOO,
retaining observed-event bindings and rater-sparsity diagnostics. `uncertainty`
identifies the existing entity + rater - observation variance approximation,
its observation-variance floor and the absence of MCMC MCSE. Repeated
entity/rater pairs lack an intersection-cluster adjustment; these SEs are not
a general calibration guarantee.
"""
function criteria(
    res::StarResult;
    chunk_size::Int = 4096,
    r_eff_override = nothing,
    retain_pointwise_matrix::Bool = false,
)
    _verify_result(res)
    acc = _make_criteria_acc(
        size(res.draws, 1),
        length(res.model.entity),
        res.config.chains,
        chunk_size,
        r_eff_override,
        retain_pointwise_matrix,
    )
    _stream_events!((acc,), res; chunk_size)
    return _envelope(res, :criteria, _finalize_criteria(acc, res.model))
end

"""
    waic(res::StarResult; chunk_size=4096)

Compute streaming rating-event WAIC (`elpd_waic`, `p_waic`, `waic`, stratum
breakdown and pointwise terms). The reported SEs use the approximation and
variance floor documented by `criteria`, not MCMC MCSE.
"""
function waic(res::StarResult; chunk_size::Int = 4096)
    crit = criteria(res; chunk_size).result
    payload = merge(
        crit.waic,
        (;
            n_events = crit.n_events,
            rater_stratum_criteria = crit.rater_stratum_criteria,
            pointwise = (;
                lppd = crit.pointwise.lppd,
                p_waic = crit.pointwise.p_waic,
                elpd_waic = crit.pointwise.elpd_waic,
            ),
        ),
    )
    return _envelope(res, :waic, payload)
end

"""
    psis_loo(res::StarResult; chunk_size=4096, r_eff_override=nothing)

Compute streaming rating-event Vehtari-Zhang-Stephens PSIS-LOO (`elpd_loo`, `p_loo`, `looic`,
Pareto-`k` diagnostics, stratum breakdown and pointwise terms). The reported
SEs use the approximation and variance floor documented by `criteria`, not
MCMC MCSE.
"""
function psis_loo(res::StarResult; chunk_size::Int = 4096, r_eff_override = nothing)
    crit = criteria(res; chunk_size, r_eff_override).result
    payload = merge(
        crit.psis_loo,
        (;
            n_events = crit.n_events,
            rater_stratum_criteria = crit.rater_stratum_criteria,
            pointwise = (;
                lppd = crit.pointwise.lppd,
                elpd_psis_loo = crit.pointwise.elpd_psis_loo,
                p_psis_loo = crit.pointwise.p_psis_loo,
                pareto_k = crit.pointwise.pareto_k,
                r_eff = crit.pointwise.r_eff,
                psis_n_eff = crit.pointwise.psis_n_eff,
            ),
        ),
    )
    return _envelope(res, :psis_loo, payload)
end

"""
    compare_models(primary, baseline; chunk_size=4096, names=("primary", "baseline"))

Compare two `StarResult` fits, or two current precomputed `criteria` records,
on the same observed rating events. IDs, actual entity/rater labels, scores,
criterion IDs, supports and scoring directions must match. Align event order
by ID automatically; priors, the root and dependence specification may differ.
Older criteria without observed-event bindings are refused. Shared IDs alone
cannot establish that two datasets were measured comparably.

Both WAIC and PSIS differences are primary minus baseline, without ranking or
model weights. Preserve sampling/Pareto-k warnings and source identities.
Reported SEs retain the existing entity + rater - observation variance
approximation with an observation-variance floor. They are not MCMC MCSE;
repeated entity/rater pairs do not receive an intersection-cluster adjustment.
`compare` is an alias. See `comparison_data` and `uncertainty` in the result.
"""
function compare_models(primary_ic::NamedTuple, baseline_ic::NamedTuple; names=("primary", "baseline"))
    labels = B._compare_model_names(names,2)
    all(_nonempty_str,labels) || throw(ArgumentError("model names must be nonempty"))
    p = _checked_comparison_criteria(primary_ic)
    b = _checked_comparison_criteria(baseline_ic)
    p.comparison_data.observation_binding==b.comparison_data.observation_binding ||
        throw(ArgumentError("models must use the same observed events, labels, scores and category definitions"))
    p.psis_loo.estimator==b.psis_loo.estimator || throw(ArgumentError("LOO estimators differ"))
    ids = p.comparison_data.event_ids
    slots = Dict(id=>i for (i,id) in enumerate(b.comparison_data.event_ids))
    p.n_events==b.n_events && all(haskey(slots,id) for id in ids) ||
        throw(ArgumentError("criteria rating-event IDs differ"))
    order = [slots[id] for id in ids]
    p.event_stratum==b.event_stratum[order] || throw(ArgumentError("rater-count strata differ"))
    dw = p.pointwise.elpd_waic .- b.pointwise.elpd_waic[order]
    dp = p.pointwise.elpd_psis_loo .- b.pointwise.elpd_psis_loo[order]
    strata = map(eachindex(RATER_COUNT_STRATA)) do st
        idxs = findall(==(st), p.event_stratum)
        (;
            stratum = RATER_COUNT_STRATA[st].label,
            n_events = length(idxs),
            elpd_waic_diff = isempty(idxs) ? 0.0 : sum(dw[idxs]),
            elpd_psis_loo_diff = isempty(idxs) ? 0.0 : sum(dp[idxs]),
            primary_bad_k = isempty(idxs) ? 0 : count(>(p.psis_loo.pareto_k_threshold), p.pointwise.pareto_k[idxs]),
            baseline_bad_k = isempty(idxs) ? 0 : count(>(b.psis_loo.pareto_k_threshold), b.pointwise.pareto_k[order[idxs]]),
        )
    end
    any_bad = p.psis_loo.bad_pareto_k_count > 0 || b.psis_loo.bad_pareto_k_count > 0
    pw = hasproperty(primary_ic, :sampling_warning) ? primary_ic.sampling_warning : false
    bw = hasproperty(baseline_ic, :sampling_warning) ? baseline_ic.sampling_warning : false
    return (;
        schema = REPORT_SCHEMA,
        operation = :criteria_comparison,
        direction = :primary_minus_baseline,
        primary_name = labels[1], baseline_name = labels[2],
        comparison_data = deepcopy(p.comparison_data),
        primary_source_sample_content_hash = primary_ic.source_sample_content_hash,
        baseline_source_sample_content_hash = baseline_ic.source_sample_content_hash,
        primary_warnings = copy(primary_ic.warnings), baseline_warnings = copy(baseline_ic.warnings),
        model_selection = :not_performed,
        uncertainty = _criteria_uncertainty(p.entity,p.rater),
        n_events = p.n_events,
        primary_sampling_warning = pw,
        baseline_sampling_warning = bw,
        any_sampling_warning = pw || bw,
        waic_diff = (;
            elpd_diff = sum(dw),
            waic_diff = -2.0 * sum(dw),
            se = _crossed_sum_se(dw, p.entity, p.I, p.rater, p.R),
        ),
        psis_loo_diff = (;
            elpd_diff = sum(dp),
            looic_diff = -2.0 * sum(dp),
            se = _crossed_sum_se(dp, p.entity, p.I, p.rater, p.R),
            primary_bad_pareto_k_count = p.psis_loo.bad_pareto_k_count,
            baseline_bad_pareto_k_count = b.psis_loo.bad_pareto_k_count,
            interpretation_scope = any_bad ?
                :diagnostic_only_sparse_rater_high_pareto_k :
                :existing_level_conditional_event_prediction,
        ),
        stratum_diffs = strata,
    )
end

function compare_models(primary::StarResult, baseline::StarResult; chunk_size::Int = 4096,
        names=("primary", "baseline"))
    labels=B._compare_model_names(names,2)
    all(_nonempty_str,labels) || throw(ArgumentError("model names must be nonempty"))
    _criteria_comparison_data(primary.model).observation_binding ==
        _criteria_comparison_data(baseline.model).observation_binding || throw(ArgumentError(
            "models must use the same observed events, labels, scores and category definitions"))
    return compare_models(criteria(primary; chunk_size), criteria(baseline; chunk_size);names=labels)
end

compare(primary, baseline; kwargs...) = compare_models(primary, baseline; kwargs...)

"""
    predictive_check(res::StarResult; checks=(:marginal, :joint_pairs, :rater_strata), focal_root_score=nothing, chunk_size=4096, seed=20261030)

Run streaming posterior predictive checks on marginal category frequencies, joint root-branch
contingency tables, and rater-sparsity strata (`ppc` is provided as an alias).
"""
function predictive_check(
    res::StarResult;
    checks = (:marginal, :joint_pairs, :rater_strata),
    focal_root_score::Union{Nothing, Int} = nothing,
    chunk_size::Int = 4096,
    seed::Int = 20261030,
)
    _verify_result(res)
    S = size(res.draws, 1)
    m = res.model
    chk_set = Set(Symbol.(collect(checks)))
    issubset(chk_set, Set((:marginal, :joint_pairs, :rater_strata))) ||
        throw(ArgumentError("unknown PPC check name"))
    m_acc = :marginal in chk_set ? _make_marginal_ppc_acc(m, S) : nothing
    j_acc = :joint_pairs in chk_set ? _make_joint_pair_ppc_acc(m, S) : nothing
    s_acc = :rater_strata in chk_set ? _make_rater_strata_ppc_acc(m, S, focal_root_score) : nothing
    active = Tuple(x for x in (m_acc, j_acc, s_acc) if x !== nothing)
    if !isempty(active)
        _stream_events!(active, res; chunk_size, seed)
    end
    return _envelope(
        res,
        :ppc,
        (;
            marginal_categories = m_acc === nothing ? nothing : _finalize_marginal_ppc(m_acc, m),
            joint_root_branch_tables = j_acc === nothing ? nothing : _finalize_joint_pair_ppc(j_acc, m),
            rater_strata = s_acc === nothing ? nothing : _finalize_rater_strata_ppc(s_acc, m),
        ),
    )
end

ppc(res::StarResult; kwargs...) = predictive_check(res; kwargs...)

"""
    evaluate(res::StarResult; criteria_check=true, ppc_checks=(:marginal, :joint_pairs, :rater_strata), ...)

Single-pass streaming evaluation computing both information criteria (`WAIC`, `PSIS-LOO`) and
posterior predictive checks simultaneously without storing the `S x N` pointwise matrix unless requested.
"""
function evaluate(
    res::StarResult;
    criteria_check::Bool = true,
    ppc_checks = (:marginal, :joint_pairs, :rater_strata),
    focal_root_score::Union{Nothing, Int} = nothing,
    chunk_size::Int = 4096,
    seed::Int = 20261030,
    r_eff_override = nothing,
    retain_pointwise_matrix::Bool = false,
)
    _verify_result(res)
    S = size(res.draws, 1)
    m = res.model
    c_acc = if criteria_check
        _make_criteria_acc(
            S,
            length(m.entity),
            res.config.chains,
            chunk_size,
            r_eff_override,
            retain_pointwise_matrix,
        )
    else
        nothing
    end
    chk_set = Set(Symbol.(collect(ppc_checks)))
    issubset(chk_set, Set((:marginal, :joint_pairs, :rater_strata))) ||
        throw(ArgumentError("unknown PPC check name"))
    m_acc = :marginal in chk_set ? _make_marginal_ppc_acc(m, S) : nothing
    j_acc = :joint_pairs in chk_set ? _make_joint_pair_ppc_acc(m, S) : nothing
    s_acc = :rater_strata in chk_set ? _make_rater_strata_ppc_acc(m, S, focal_root_score) : nothing
    active = Tuple(x for x in (c_acc, m_acc, j_acc, s_acc) if x !== nothing)
    if !isempty(active)
        _stream_events!(active, res; chunk_size, seed)
    end
    return _envelope(
        res,
        :evaluate,
        (;
            criteria = c_acc === nothing ? nothing : _finalize_criteria(c_acc, m),
            ppc = (;
                marginal_categories = m_acc === nothing ? nothing : _finalize_marginal_ppc(m_acc, m),
                joint_root_branch_tables = j_acc === nothing ? nothing : _finalize_joint_pair_ppc(j_acc, m),
                rater_strata = s_acc === nothing ? nothing : _finalize_rater_strata_ppc(s_acc, m),
            ),
        ),
    )
end
