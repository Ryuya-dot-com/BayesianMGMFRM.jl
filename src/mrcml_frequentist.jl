# FF6a: Frequentist 1D MMLE & JMLE Estimation on Sparse MRCML Design Matrices
# Included inside `module FrequentistMFRM` (`src/frequentist_mfrm.jl`).
#
# Runs on the exact same `MRCMLOperator` (`A_free`, `A_model`, `B_pat`, `c_pat`, `J_model`)
# as Bayesian HMC/NUTS (`MRCMLTarget`), providing:
# - Exact quadrature MMLE (fixed `(mu, sigma)`, TAM-style free `sigma`, or free `(mu, sigma)`)
# - Exact unadjusted / FACETS-adjusted JMLE with O(N + d_xi^3) Schur-complement Hessian SEs
# - Both coordinate-invariant observed-information SE (`se`) and TAM/FACETS M-step diagonal
#   conditional SE (`conditional_se`)
# - EAP, Warm WLE, and fixed-calibration MLE person scoring, plus AIC/BIC/LRT `compare_models`.

const MRCML_FREQ_FIT_TAG = :mrcml_design_matrix
include("mrcml_grouped_mmle.jl")

function _mrcml_person_extremes(
        op::B.AdditiveFacets.MRCMLOperator,
        n_obs::Int, P::Int, person_idx::Vector{Int}, group::Vector{Int},
        supports::Vector{UnitRange{Int}}, category::Vector{Int})
    has_obs = falses(P)
    has_informative = falses(P)
    all_min = trues(P)
    all_max = trues(P)
    for n in 1:n_obs
        p = person_idx[n]
        has_obs[p] = true
        sup = supports[group[n]]
        M_g = length(sup)
        prng = op.pattern_ranges[op.pattern_of_row[n]]
        yk_loc = category[n] - first(sup) + 1
        b_min = Inf
        b_max = -Inf
        @inbounds for lk in 1:M_g
            bv = op.B_pat[prng[lk]]
            bv < b_min && (b_min = bv)
            bv > b_max && (b_max = bv)
        end
        b_max - b_min <= 1e-14 && continue
        has_informative[p] = true
        b_obs = op.B_pat[prng[yk_loc]]
        abs(b_obs - b_min) <= 1e-14 || (all_min[p] = false)
        abs(b_obs - b_max) <= 1e-14 || (all_max[p] = false)
    end
    status = Vector{Symbol}(undef, P)
    for p in 1:P
        status[p] = !has_obs[p] ? :unobserved :
                    !has_informative[p] ? :unidentified_zero_slope :
                    all_min[p] ? :all_minimum :
                    all_max[p] ? :all_maximum : :interior
    end
    return status
end

function _mrcml_extreme_facet_levels(spec)
    out = NamedTuple[]
    op = spec.operator
    fset = op.fixed_model_names
    n_obs = length(spec.person)
    for f in spec.facets
        L = length(f.levels)
        has_o = falses(L)
        has_inf = falses(L)
        is_min = trues(L)
        is_max = trues(L)
        for i in 1:n_obs
            j = f.index[i]
            has_o[j] = true
            sup = spec.supports[spec.group[i]]
            prng = op.pattern_ranges[op.pattern_of_row[i]]
            M_g = length(sup)
            yk_loc = spec.category[i] - first(sup) + 1
            b_min = Inf
            b_max = -Inf
            @inbounds for lk in 1:M_g
                bv = op.B_pat[prng[lk]]
                bv < b_min && (b_min = bv)
                bv > b_max && (b_max = bv)
            end
            b_max - b_min <= 1e-14 && continue
            has_inf[j] = true
            b_obs = op.B_pat[prng[yk_loc]]
            abs(b_obs - b_min) <= 1e-14 || (is_min[j] = false)
            abs(b_obs - b_max) <= 1e-14 || (is_max[j] = false)
        end
        for j in 1:L
            (has_o[j] && has_inf[j]) || continue
            lvl = f.levels[j]
            nm1 = "$(f.name)[$(repr(lvl))]"
            nm2 = "$(f.name)[$(lvl)]"
            is_fix = (nm1 in fset) || (nm2 in fset)
            if is_min[j]
                push!(out, (; facet = f.name, level = deepcopy(lvl), direction = :all_minimum, fixed = is_fix))
            elseif is_max[j]
                push!(out, (; facet = f.name, level = deepcopy(lvl), direction = :all_maximum, fixed = is_fix))
            end
        end
    end
    return out
end

struct _MRCMLMMLEScratch
    ordinal_rows::Bool
    obs_slot::Vector{Int}
    log_w::Vector{Float64}
    v_pat::Vector{Float64}
    logp_slot::Vector{Float64}
    prob_slot::Vector{Float64}
    ll_pq::Matrix{Float64}
    post_w::Matrix{Float64}
    slot_acc::Vector{Float64}
    pat_w::Vector{Float64}
    r_pat::Vector{Float64}
end

function _build_mrcml_mmle_scratch(
        op::B.AdditiveFacets.MRCMLOperator,
        P::Int,
        group::Vector{Int},
        supports::Vector{UnitRange{Int}},
        category::Vector{Int},
        base_quad)
    M_tot = length(op.c_pat)
    Q = length(base_quad.std_nodes)
    obs_slot = Vector{Int}(undef, op.n_obs)
    @inbounds for n in 1:op.n_obs
        prng = op.pattern_ranges[op.pattern_of_row[n]]
        yk_loc = category[n] - first(supports[group[n]]) + 1
        obs_slot[n] = prng[yk_loc]
    end
    log_w = Float64[w > 0.0 ? log(w) : -Inf for w in base_quad.weights]
    ordinal_rows = 2op.n_patterns > op.n_obs && all(op.pattern_ranges) do rng
        all(k -> op.B_pat[rng[k]] == k-1, eachindex(rng))
    end
    return _MRCMLMMLEScratch(
        ordinal_rows, obs_slot,
        log_w,
        Vector{Float64}(undef, M_tot),
        Vector{Float64}(undef, M_tot),
        Vector{Float64}(undef, M_tot),
        Matrix{Float64}(undef, P, Q),
        Matrix{Float64}(undef, P, Q),
        Vector{Float64}(undef, M_tot),
        Vector{Float64}(undef, op.n_patterns),
        Vector{Float64}(undef, M_tot),
    )
end

function _mrcml_mmle_nll_and_grad!(
        grad_out::Union{Nothing,AbstractVector},
        u_vec::AbstractVector{TU},
        op::B.AdditiveFacets.MRCMLOperator,
        P::Int,
        person_idx::Vector{Int},
        group::Vector{Int},
        supports::Vector{UnitRange{Int}},
        category::Vector{Int},
        weights::Vector{Float64},
        base_quad,
        mu_fixed::Float64,
        sigma_fixed::Float64,
        mu_idx::Int,
        lsig_idx::Int,
        offset = op.c_pat,
        scratch::Union{Nothing,_MRCMLMMLEScratch} = nothing) where {TU<:Real}
    T = promote_type(TU, eltype(offset))
    d_xi = size(op.A_free, 2)
    eta_xi = view(u_vec, 1:d_xi)
    mu = mu_idx > 0 ? T(u_vec[mu_idx]) : T(mu_fixed)
    sigma = lsig_idx > 0 ? exp(T(u_vec[lsig_idx])) : T(sigma_fixed)
    !(isfinite(sigma) && 1e-8 <= sigma <= 1e4) && return T(Inf)

    M_tot = length(op.c_pat)
    Q = length(base_quad.std_nodes)
    use_f64_scratch = (T === Float64) && (scratch !== nothing) && (grad_out === nothing || eltype(grad_out) === Float64)

    obs_slot = if scratch !== nothing
        scratch.obs_slot
    else
        os = Vector{Int}(undef, op.n_obs)
        @inbounds for n in 1:op.n_obs
            prng = op.pattern_ranges[op.pattern_of_row[n]]
            os[n] = prng[category[n] - first(supports[group[n]]) + 1]
        end
        os
    end
    log_w = scratch !== nothing ? scratch.log_w : Float64[w > 0.0 ? log(w) : -Inf for w in base_quad.weights]

    v_pat = use_f64_scratch ? scratch.v_pat : Vector{T}(undef, M_tot)
    @inbounds for m in 1:M_tot
        v_pat[m] = T(offset[m])
    end
    rows = rowvals(op.A_free)
    vals = nonzeros(op.A_free)
    scalar = use_f64_scratch && scratch.ordinal_rows
    if scalar
        mul!(v_pat, op.A_model, op.J_model * eta_xi, 1.0, 1.0)
        value = _mrcml_scalar_mmle!(grad_out, op, person_idx, weights, base_quad, mu, sigma,
                                    mu_idx, lsig_idx, scratch)
        isnothing(value) || return value
    else
        @inbounds for col in 1:d_xi
            ec = eta_xi[col]
            ec == zero(T) && continue
            for ptr in nzrange(op.A_free, col)
                v_pat[rows[ptr]] += T(vals[ptr]) * ec
            end
        end

    end

    logp_slot = use_f64_scratch ? scratch.logp_slot : Vector{T}(undef, M_tot)
    ll_pq = use_f64_scratch ? fill!(scratch.ll_pq, 0.0) : zeros(T, P, Q)

    @inbounds for q in 1:Q
        log_w[q] == -Inf && continue
        th_q = mu + sigma * T(base_quad.std_nodes[q])
        # Evaluate log-softmax once per unique pattern (n_patterns << n_obs)
        for u in 1:op.n_patterns
            prng = op.pattern_ranges[u]
            m1 = first(prng)
            mmax = T(op.B_pat[m1]) * th_q + v_pat[m1]
            logp_slot[m1] = mmax
            for m in (m1 + 1):last(prng)
                val = T(op.B_pat[m]) * th_q + v_pat[m]
                logp_slot[m] = val
                val > mmax && (mmax = val)
            end
            ssum = zero(T)
            for m in prng
                ssum += exp(logp_slot[m] - mmax)
            end
            lse = mmax + log(ssum)
            for m in prng
                logp_slot[m] -= lse
            end
        end
        for n in 1:op.n_obs
            ll_pq[person_idx[n], q] += T(weights[n]) * logp_slot[obs_slot[n]]
        end
    end

    total_ll = zero(T)
    post_w = grad_out === nothing ? nothing : (use_f64_scratch ? scratch.post_w : Matrix{T}(undef, P, Q))
    @inbounds for p in 1:P
        mval = T(-Inf)
        for q in 1:Q
            log_w[q] == -Inf && continue
            cand = ll_pq[p, q] + T(log_w[q])
            cand > mval && (mval = cand)
        end
        s_exp = zero(T)
        for q in 1:Q
            log_w[q] == -Inf && continue
            s_exp += exp(ll_pq[p, q] + T(log_w[q]) - mval)
        end
        lp = mval + log(s_exp)
        total_ll += lp
        if post_w !== nothing
            for q in 1:Q
                post_w[p, q] = log_w[q] == -Inf ? zero(T) : exp(ll_pq[p, q] + T(log_w[q]) - lp)
            end
        end
    end

    if grad_out !== nothing
        prob_slot = use_f64_scratch ? scratch.prob_slot : Vector{T}(undef, M_tot)
        slot_acc = use_f64_scratch ? scratch.slot_acc : Vector{T}(undef, M_tot)
        pat_w = use_f64_scratch ? scratch.pat_w : Vector{T}(undef, op.n_patterns)
        r_pat = use_f64_scratch ? fill!(scratch.r_pat, 0.0) : zeros(T, M_tot)
        g_mu = zero(T)
        g_lsig = zero(T)

        @inbounds for q in 1:Q
            log_w[q] == -Inf && continue
            zq = base_quad.std_nodes[q]
            t_shift = sigma * T(zq)
            th_q = mu + t_shift

            fill!(slot_acc, zero(T))
            fill!(pat_w, zero(T))
            for n in 1:op.n_obs
                pw = post_w[person_idx[n], q]
                pw == zero(T) && continue
                w_pw = T(weights[n]) * pw
                slot_acc[obs_slot[n]] += w_pw
                pat_w[op.pattern_of_row[n]] += w_pw
            end

            b_res_q = zero(T)
            for u in 1:op.n_patterns
                wu = pat_w[u]
                prng = op.pattern_ranges[u]
                if wu == zero(T)
                    for m in prng
                        sa = slot_acc[m]
                        if sa != zero(T)
                            r_pat[m] += sa
                            b_res_q += T(op.B_pat[m]) * sa
                        end
                    end
                    continue
                end
                m1 = first(prng)
                mmax = T(op.B_pat[m1]) * th_q + v_pat[m1]
                prob_slot[m1] = mmax
                for m in (m1 + 1):last(prng)
                    val = T(op.B_pat[m]) * th_q + v_pat[m]
                    prob_slot[m] = val
                    val > mmax && (mmax = val)
                end
                ssum = zero(T)
                for m in prng
                    e = exp(prob_slot[m] - mmax)
                    prob_slot[m] = e
                    ssum += e
                end
                inv_s = inv(ssum)
                for m in prng
                    pk = prob_slot[m] * inv_s
                    rk = slot_acc[m] - wu * pk
                    r_pat[m] += rk
                    b_res_q += T(op.B_pat[m]) * rk
                end
            end
            g_mu += b_res_q
            g_lsig += b_res_q * t_shift
        end

        fill!(grad_out, zero(T))
        # Negative log-likelihood gradient = -A_free' * r_pat
        @inbounds for col in 1:d_xi
            acc = zero(T)
            for ptr in nzrange(op.A_free, col)
                acc += T(vals[ptr]) * r_pat[rows[ptr]]
            end
            grad_out[col] = -acc
        end
        mu_idx > 0 && (grad_out[mu_idx] = -g_mu)
        lsig_idx > 0 && (grad_out[lsig_idx] = -g_lsig)
    end
    return -total_ll
end

function _mrcml_jmle_nll_and_grad!(
        grad_out::Union{Nothing,Vector{Float64}},
        u_vec::AbstractVector{T},
        op::B.AdditiveFacets.MRCMLOperator,
        interior_persons::Vector{Int},
        p_to_free::Vector{Int},
        active_rows::Vector{Int},
        person_idx::Vector{Int},
        group::Vector{Int},
        supports::Vector{UnitRange{Int}},
        category::Vector{Int},
        weights::Vector{Float64},
        extreme_adjustment::Float64) where {T<:Real}
    d_theta = length(interior_persons)
    d_xi = size(op.A_free, 2)
    theta_free = view(u_vec, 1:d_theta)
    eta_xi = view(u_vec, (d_theta + 1):(d_theta + d_xi))

    M_tot = length(op.c_pat)
    v_pat = T.(op.c_pat)
    rows = rowvals(op.A_free)
    vals = nonzeros(op.A_free)
    @inbounds for col in 1:d_xi
        ec = eta_xi[col]
        ec == zero(T) && continue
        for ptr in nzrange(op.A_free, col)
            v_pat[rows[ptr]] += T(vals[ptr]) * ec
        end
    end

    # Precompute person score adjustment delta_b per active person when extreme_adjustment > 0
    # Adjusts each person's total score slightly inward from min/max when extreme!
    K_max = maximum(length, supports)
    lbuf = zeros(T, K_max)
    r_pat = grad_out !== nothing ? zeros(Float64, M_tot) : nothing
    g_theta = grad_out !== nothing ? zeros(Float64, d_theta) : nothing
    n_obs_per_p = zeros(Int, length(p_to_free))
    if extreme_adjustment > 0.0
        for n in active_rows
            n_obs_per_p[person_idx[n]] += 1
        end
    end

    total_ll = zero(T)
    @inbounds for n in active_rows
        p = person_idx[n]
        fp = p_to_free[p]
        th = theta_free[fp]
        pat = op.pattern_of_row[n]
        prng = op.pattern_ranges[pat]
        sup = supports[group[n]]
        M_g = length(sup)
        mmax = T(-Inf)
        for lk in 1:M_g
            m = prng[lk]
            val = T(op.B_pat[m]) * th + v_pat[m]
            lbuf[lk] = val
            val > mmax && (mmax = val)
        end
        ssum = zero(T)
        for lk in 1:M_g
            ssum += exp(lbuf[lk] - mmax)
        end
        lse = mmax + log(ssum)
        yk_loc = category[n] - first(sup) + 1
        wn = weights[n]

        if extreme_adjustment > 0.0
            # Check if person is all-min or all-max; shift effective weight across endpoints
            # Only alters extreme persons:
            b_min = op.B_pat[first(prng)]
            b_max = op.B_pat[last(prng)]
            # Simple exact log-likelihood when interior:
            ll_row = lbuf[yk_loc] - lse
            total_ll += T(wn) * ll_row
        else
            total_ll += T(wn) * (lbuf[yk_loc] - lse)
        end

        if grad_out !== nothing
            lse_f = Float64(lse)
            for lk in 1:M_g
                m = prng[lk]
                pk = exp(Float64(lbuf[lk]) - lse_f)
                rk = wn * ((lk == yk_loc ? 1.0 : 0.0) - pk)
                r_pat[m] += rk
                g_theta[fp] += op.B_pat[m] * rk
            end
        end
    end

    # Apply FACETS extreme_adjustment shift to extreme persons' sufficient statistics if active
    if extreme_adjustment > 0.0
        p_ext = _mrcml_person_extremes(op, op.n_obs, length(p_to_free), person_idx, group, supports, category)
        for p in eachindex(p_ext)
            fp = p_to_free[p]
            fp == 0 && continue
            if p_ext[p] === :all_minimum
                total_ll += extreme_adjustment * theta_free[fp]
                grad_out !== nothing && (g_theta[fp] += extreme_adjustment)
            elseif p_ext[p] === :all_maximum
                total_ll -= extreme_adjustment * theta_free[fp]
                grad_out !== nothing && (g_theta[fp] -= extreme_adjustment)
            end
        end
    end

    if grad_out !== nothing
        fill!(grad_out, 0.0)
        grad_out[1:d_theta] .= .-g_theta
        @inbounds for col in 1:d_xi
            acc = 0.0
            for ptr in nzrange(op.A_free, col)
                acc += vals[ptr] * r_pat[rows[ptr]]
            end
            grad_out[d_theta + col] = -acc
        end
    end
    return -total_ll
end

function _mrcml_person_scores_from_calibration(
        eta_xi::Vector{Float64},
        op::B.AdditiveFacets.MRCMLOperator,
        people::Vector{Any},
        person_idx::Vector{Int},
        group::Vector{Int},
        supports::Vector{UnitRange{Int}},
        categories::Vector{Int},
        category::Vector{Int},
        weights::Vector{Float64};
        method::Symbol,
        quad = nothing,
        mu_hat::Float64 = 0.0,
        sigma_hat::Float64 = 1.0,
        jmle_theta::Union{Nothing,Vector{Float64}} = nothing,
        jmle_se::Union{Nothing,Vector{Float64}} = nothing)
    P = length(people)
    v_pat = copy(op.c_pat)
    mul!(v_pat, op.A_free, eta_xi, 1.0, 1.0)
    p_rows = [Int[] for _ in 1:P]
    for n in 1:op.n_obs
        push!(p_rows[person_idx[n]], n)
    end
    p_ext = _mrcml_person_extremes(op, op.n_obs, P, person_idx, group, supports, category)

    # Helper: evaluate person log-likelihood, 1st, 2nd, and 3rd derivatives wrt theta
    function person_derivs(p::Int, th::Float64)
        ll = 0.0; d1 = 0.0; info = 0.0; d3 = 0.0
        for n in p_rows[p]
            wn = weights[n]
            prng = op.pattern_ranges[op.pattern_of_row[n]]
            sup = supports[group[n]]
            M_g = length(sup)
            lvec = [op.B_pat[prng[lk]] * th + v_pat[prng[lk]] for lk in 1:M_g]
            bvec = [op.B_pat[prng[lk]] for lk in 1:M_g]
            mmax = maximum(lvec)
            pvec = exp.(lvec .- mmax)
            ssum = sum(pvec)
            pvec ./= ssum
            yk_loc = category[n] - first(sup) + 1
            ll += wn * (lvec[yk_loc] - (mmax + log(ssum)))
            eb1 = sum(pvec[lk] * bvec[lk] for lk in 1:M_g)
            var_b = sum(pvec[lk] * (bvec[lk] - eb1)^2 for lk in 1:M_g)
            mu3_b = sum(pvec[lk] * (bvec[lk] - eb1)^3 for lk in 1:M_g)
            d1 += wn * (bvec[yk_loc] - eb1)
            info += wn * var_b
            d3 -= wn * mu3_b
        end
        return (; ll, d1, info, d3)
    end

    function solve_person_wle_mle(p::Int; wle::Bool)
        th = 0.0
        for _ in 1:50
            dv = person_derivs(p, th)
            dv.info <= 1e-12 && break
            # Warm (1989) WLE bias correction term: -d3 / (2 * info) = +mu3 / (2 * info)
            score_w = wle ? (dv.d1 + (-dv.d3) / (2.0 * dv.info)) : dv.d1
            step = clamp(score_w / dv.info, -2.0, 2.0)
            th += step
            abs(step) <= 1e-10 && break
        end
        dv = person_derivs(p, th)
        se = dv.info > 1e-12 ? 1.0 / sqrt(dv.info) : NaN
        return (th, se)
    end

    rows = NamedTuple[]
    for p in 1:P
        obs_cnt = length(p_rows[p])
        raw_sum = sum(categories[category[n]] for n in p_rows[p]; init = 0)
        ext = p_ext[p]
        wle_est, wle_se = ext === :unidentified_zero_slope ? (NaN, NaN) : solve_person_wle_mle(p; wle = true)
        mle_est, mle_se = ext === :interior ? solve_person_wle_mle(p; wle = false) :
            ext === :all_minimum ? (-Inf, NaN) :
            ext === :all_maximum ? (Inf, NaN) : (NaN, NaN)

        if method === :mmle
            Q = length(quad.nodes)
            l_posts = [quad.weights[q] > 0 ? person_derivs(p, mu_hat + quad.nodes[q]).ll + log(quad.weights[q]) : -Inf for q in 1:Q]
            mmax = maximum(l_posts)
            pw = [isfinite(lp) ? exp(lp - mmax) : 0.0 for lp in l_posts]
            pw ./= sum(pw)
            ths = [mu_hat + quad.nodes[q] for q in 1:Q]
            eap = sum(pw[q] * ths[q] for q in 1:Q)
            psd = sqrt(max(sum(pw[q] * (ths[q] - eap)^2 for q in 1:Q), 0.0))
            push!(rows, (;
                person = people[p],
                n_ratings = obs_cnt,
                raw_score = raw_sum,
                extreme = ext,
                estimate = eap,
                se = psd,
                eap,
                posterior_sd = psd,
                wle = wle_est,
                wle_se,
                mle = mle_est,
                mle_se,
            ))
        else
            lim_est = jmle_theta[p]
            lim_se = jmle_se[p]
            lim_info = isfinite(lim_est) ? person_derivs(p, lim_est).info : 0.0
            push!(rows, (;
                person = people[p],
                n_ratings = obs_cnt,
                raw_score = raw_sum,
                extreme = ext,
                estimate = lim_est,
                limit_estimate = lim_est,
                se = lim_se,
                conditional_se = lim_info > 1e-12 ? 1.0 / sqrt(lim_info) : NaN,
                wle = wle_est,
                wle_se,
            ))
        end
    end
    return rows
end

function _mrcml_reliability_rows(
        facet_names::Vector{Symbol},
        facet_levels_len::Dict{Symbol,Int},
        op::B.AdditiveFacets.MRCMLOperator,
        method::Symbol,
        has_grouped_pop::Bool,
        extreme_adjusted::Bool,
        person_rows::AbstractVector{<:NamedTuple},
        facet_rows::AbstractVector{<:NamedTuple},
        ext_facets;
        variance::Symbol = :sample,
        se::Symbol = :default,
        nonextreme_only::Bool = false)
    rel_rows = NamedTuple[]
    push!(rel_rows, _frequentist_person_reliability_row(
        person_rows;
        is_eap = method === :mmle,
        grouped = has_grouped_pop,
        extreme_adjusted,
        variance,
        se,
        nonextreme_only,
    ))
    bm_by_facet = Dict{Symbol,NamedTuple}()
    for bm in op.block_meta
        if bm.kind in (:facet_main, :facet_lltm_strict, :facet_lltm_plus_residual)
            bm_by_facet[bm.name] = bm
        end
    end
    for fname in facet_names
        L_f = get(facet_levels_len, fname, 0)
        bm = get(bm_by_facet, fname, nothing)
        if bm === nothing
            push!(rel_rows, _unavailable_reliability_row(
                fname, L_f, 0;
                basis = :unstructured_mrcml_design_matrix,
                status = :not_applicable_custom_design_matrix,
                variance_definition = variance,
            ))
        elseif bm.kind !== :facet_main
            push!(rel_rows, _unavailable_reliability_row(
                fname, L_f, L_f;
                basis = bm.kind === :facet_lltm_strict ? :not_applicable_strict_lltm_subspace : :not_applicable_lltm_plus_residual,
                status = :not_applicable_lltm_subspace,
                variance_definition = variance,
            ))
        else
            frows = [r for r in facet_rows if r.facet === fname]
            push!(rel_rows, _frequentist_facet_reliability_row(
                fname, frows;
                method, variance, se, nonextreme_only, extreme_levels = ext_facets,
            ))
        end
    end
    return rel_rows
end

function recompute_reliability(
        f::Fit;
        variance::Symbol = :sample,
        se::Symbol = :default,
        nonextreme_only::Bool = false)
    r = checked(f)
    variance in (:sample, :population) ||
        throw(ArgumentError("variance must be :sample or :population; got $(repr(variance))"))
    se in (:default, :observed, :conditional, :real) ||
        throw(ArgumentError("se must be :default, :observed, :conditional, or :real; got $(repr(se))"))
    if variance === :sample && se === :default && !nonextreme_only
        return copy(r.reliability)
    end
    s = r.summary
    prob = r.problem
    ext_adj = s.method === :jmle && !(s.extreme_adjustment === missing) && Float64(s.extreme_adjustment) > 0.0
    if hasproperty(r, :mrcml_operator)
        flens = Dict(fd.name => length(fd.levels) for fd in prob.facets)
        return _mrcml_reliability_rows(
            Symbol[fd.name for fd in prob.facets],
            flens,
            r.mrcml_operator,
            s.method,
            hasproperty(s, :population),
            ext_adj,
            r.person_scores,
            r.facet_measures,
            r.extreme_facet_levels;
            variance, se, nonextreme_only,
        )
    end
    out = NamedTuple[]
    push!(out, _frequentist_person_reliability_row(
        r.person_scores;
        is_eap = s.method === :mmle,
        grouped = false,
        extreme_adjusted = ext_adj,
        variance, se, nonextreme_only,
    ))
    for fd in prob.facets
        frows = [row for row in r.facet_measures if row.facet === fd.name]
        push!(out, _frequentist_facet_reliability_row(
            fd.name, frows;
            method = s.method, variance, se, nonextreme_only, extreme_levels = r.extreme_facet_levels,
        ))
    end
    return out
end

function _mrcml_compute_diagnostics_and_tables(
        spec,
        prob::Problem,
        op::B.AdditiveFacets.MRCMLOperator,
        cat_labels_by_group::Vector{Vector{Int}},
        eta_hat::Vector{Float64},
        xi_model_hat::Vector{Float64},
        se_model::Vector{Float64},
        cond_se_model::Vector{Float64},
        sand_se_model::Union{Nothing,Vector{Float64}},
        pscores_raw::Vector{NamedTuple},
        w::Vector{Float64},
        ll::Float64,
        n_free::Int,
        ext_facets;
        has_grouped_pop::Bool = false,
        extreme_adjusted::Bool = false,
        interval::Float64 = 0.95,
        zstd_cap::Union{Nothing,Float64} = 9.0,
        whexact::Bool = true)
    n = op.n_obs
    P = length(spec.people)
    m = prob.method
    v_pat = copy(op.c_pat)
    mul!(v_pat, op.A_free, eta_hat, 1.0, 1.0)

    facet_mrngs = Dict{Symbol,UnitRange{Int}}()
    for bm in op.block_meta
        if bm.kind in (:facet_main, :facet_lltm_strict, :facet_lltm_plus_residual)
            facet_mrngs[bm.name] = bm.model_range
        end
    end
    has_all_facet_mrngs = !isempty(spec.facets) && all(f -> haskey(facet_mrngs, f.name), spec.facets)

    obs_exp_raw = zeros(Float64, n)
    obs_var = zeros(Float64, n)
    obs_m4 = zeros(Float64, n)
    obs_z2 = fill(NaN, n)
    obs_bzero = falses(n)
    obs_eta_eff = zeros(Float64, n)
    obs_target_diff = zeros(Float64, n)
    p_probs_row = Vector{Vector{Float64}}(undef, n)
    K_max = maximum(length, spec.supports)
    lbuf = zeros(Float64, K_max)
    lbuf0 = zeros(Float64, K_max)

    for r in 1:n
        p = spec.person[r]
        th = Float64(pscores_raw[p].estimate)
        g = spec.group[r]
        sup = spec.supports[g]
        M_g = length(sup)
        prng = op.pattern_ranges[op.pattern_of_row[r]]
        yk_loc = spec.category[r] - first(sup) + 1

        if has_all_facet_mrngs
            d_sum = 0.0
            for f in spec.facets
                d_sum += xi_model_hat[facet_mrngs[f.name][f.index[r]]]
            end
            obs_target_diff[r] = d_sum
        else
            m0 = -Inf
            for lk in 1:M_g
                vv = v_pat[prng[lk]]
                lbuf0[lk] = vv
                vv > m0 && (m0 = vv)
            end
            s0 = 0.0
            e0 = 0.0
            for lk in 1:M_g
                ew = exp(lbuf0[lk] - m0)
                s0 += ew
                e0 += ew * Float64(spec.categories[sup[lk]])
            end
            obs_target_diff[r] = -(e0 / s0)
        end

        if !isfinite(th)
            obs_bzero[r] = true
            obs_var[r] = 0.0
            obs_m4[r] = 0.0
            obs_z2[r] = 0.0
            b_idx = th < 0 ? argmin(view(op.B_pat, prng)) : argmax(view(op.B_pat, prng))
            obs_exp_raw[r] = Float64(spec.categories[sup[b_idx]])
            obs_eta_eff[r] = th
            pv_b = zeros(Float64, M_g)
            pv_b[b_idx] = 1.0
            p_probs_row[r] = pv_b
        else
            mmax = -Inf
            for lk in 1:M_g
                vv = op.B_pat[prng[lk]] * th + v_pat[prng[lk]]
                lbuf[lk] = vv
                vv > mmax && (mmax = vv)
            end
            ssum = 0.0
            pv = Vector{Float64}(undef, M_g)
            for lk in 1:M_g
                ew = exp(lbuf[lk] - mmax)
                pv[lk] = ew
                ssum += ew
            end
            inv_s = 1.0 / ssum
            eb = 0.0
            eraw = 0.0
            for lk in 1:M_g
                pk = pv[lk] * inv_s
                pv[lk] = pk
                eb += pk * op.B_pat[prng[lk]]
                eraw += pk * Float64(spec.categories[sup[lk]])
            end
            vk = 0.0
            m4k = 0.0
            for lk in 1:M_g
                db = op.B_pat[prng[lk]] - eb
                db2 = db * db
                vk += pv[lk] * db2
                m4k += pv[lk] * db2 * db2
            end
            b_obs = op.B_pat[prng[yk_loc]]
            obs_exp_raw[r] = eraw
            obs_var[r] = vk
            obs_m4[r] = m4k
            obs_z2[r] = vk > 1e-10 ? (b_obs - eb)^2 / vk : NaN
            obs_eta_eff[r] = th - obs_target_diff[r]
            p_probs_row[r] = pv
        end
    end

    z_crit = quantile(Normal(), 0.5 * (1.0 + interval))
    overall_fit = merge(
        _summarize_fit_rows(collect(1:n), obs_var, obs_m4, obs_z2, obs_bzero, w;
            has_boundary_proxy = any(obs_bzero), zstd_cap, whexact),
        (; loglikelihood = ll, deviance = -2.0 * ll, n_free_parameters = n_free, whexact, zstd_cap),
    )

    p_grp = [Int[] for _ in 1:P]
    for r in 1:n
        push!(p_grp[spec.person[r]], r)
    end
    # Precompute FACETS-style marginal Fair(M) and Fair(Z) baselines when structured step blocks exist
    step_bms_fa = [bm for bm in op.block_meta if bm.kind === :steps]
    pop_bms_fa = [bm for bm in op.block_meta if bm.kind === :population_mean]
    step_int_fa = Dict{Symbol,NamedTuple}(bm.f1 => bm for bm in op.block_meta if bm.kind === :facet_step_interaction)
    has_struct_steps_fa = !isempty(step_bms_fa) && length(step_bms_fa) == length(spec.supports)
    same_sup_fa = has_struct_steps_fa && allequal(spec.supports)
    mu_int_fa = isempty(pop_bms_fa) ? 0.0 : xi_model_hat[first(only(pop_bms_fa).model_range)]
    fin_th_fa = Float64[Float64(pscores_raw[p].estimate) for p in 1:P if isfinite(Float64(pscores_raw[p].estimate))]
    th_bar_fa = (isempty(fin_th_fa) ? 0.0 : mean(fin_th_fa)) + mu_int_fa
    f_means_fa = Dict{Symbol,Float64}(fn => mean(view(xi_model_hat, mrng)) for (fn, mrng) in facet_mrngs)
    f_sum_means_fa = sum(values(f_means_fa); init = 0.0)
    tau_groups_fa = has_struct_steps_fa ? [Float64[xi_model_hat[idx] for idx in step_bms_fa[g].model_range] for g in eachindex(step_bms_fa)] : Vector{Float64}[]
    cat_groups_fa = [Float64.(cat_labels_by_group[g]) for g in eachindex(cat_labels_by_group)]
    tau_mean_fa = same_sup_fa ?
        Float64[mean(tau_groups_fa[g][h] for g in eachindex(tau_groups_fa)) for h in 1:length(tau_groups_fa[1])] :
        Float64[]

    person_scores = Vector{NamedTuple}(undef, P)
    for p in 1:P
        rs = p_grp[p]
        pr = pscores_raw[p]
        th_p = Float64(pr.estimate)
        finite_est = isfinite(th_p)
        single_free = m === :jmle && length(rs) == 1
        has_b = any(r -> obs_bzero[r], rs)
        fstat = (!finite_est && m === :jmle) ?
            (; infit = missing, outfit = missing, infit_zstd = missing, outfit_zstd = missing,
               df_infit = missing, df_outfit = missing, infit_zstd_engine = missing,
               outfit_zstd_engine = missing, df_infit_engine = missing, df_outfit_engine = missing,
               status = :unavailable_extreme_boundary) :
            _summarize_fit_rows(rs, obs_var, obs_m4, obs_z2, obs_bzero, w;
                has_boundary_proxy = has_b, single_obs_free_jmle = single_free, zstd_cap, whexact)
        info_sum = sum((obs_bzero[r] ? 0.0 : w[r] * obs_var[r]) for r in rs; init = 0.0)
        cond_se_val = (!finite_est && m === :jmle) ? missing : (info_sum > 0.0 ? 1.0 / sqrt(info_sum) : missing)
        base_se_real = m === :mmle ? Float64(pr.posterior_sd) :
            (_finite_pos_num(cond_se_val) ? Float64(cond_se_val) : NaN)
        real_se = (isfinite(base_se_real) && !(fstat.infit === missing)) ?
            base_se_real * sqrt(max(1.0, Float64(fstat.infit))) : missing
        se_p = Float64(pr.se)
        lo = (finite_est && isfinite(se_p) && se_p > 0.0) ? th_p - z_crit * se_p : missing
        hi = (finite_est && isfinite(se_p) && se_p > 0.0) ? th_p + z_crit * se_p : missing
        t_scores = Float64[prob.raw_score[r] for r in rs]
        t_diff = Float64[obs_target_diff[r] for r in rs]
        ptm = _ptmea_corr(t_scores, t_diff)
        p_fair_m, p_fair_z = if same_sup_fa
            eta_m_p = finite_est ? ((th_p + mu_int_fa) - f_sum_means_fa) : th_p
            eta_z_p = finite_est ? (th_p + mu_int_fa) : th_p
            fm_p = first(_freq_adjacent_expected_score_and_slope(eta_m_p, tau_mean_fa, cat_groups_fa[1]))
            fz_p = first(_freq_adjacent_expected_score_and_slope(eta_z_p, tau_mean_fa, cat_groups_fa[1]))
            (isfinite(fm_p) ? fm_p : missing, isfinite(fz_p) ? fz_p : missing)
        else
            (missing, missing)
        end
        se_extra = m === :mmle ? (; eap_sd = pr.posterior_sd, conditional_se = cond_se_val) : (; conditional_se = cond_se_val)
        person_scores[p] = merge(pr, se_extra, (;
            facet = :person,
            level = spec.people[p],
            fixed = false,
            fair_m = p_fair_m,
            fair_z = p_fair_z,
            real_se,
            lower = lo,
            upper = hi,
            interval,
            infit = fstat.infit,
            outfit = fstat.outfit,
            infit_zstd = fstat.infit_zstd,
            outfit_zstd = fstat.outfit_zstd,
            df_infit = fstat.df_infit,
            df_outfit = fstat.df_outfit,
            infit_zstd_engine = fstat.infit_zstd_engine,
            outfit_zstd_engine = fstat.outfit_zstd_engine,
            fit_status = fstat.status,
            ptmea = ptm,
        ))
    end

    f_grp = Dict{Symbol,Vector{Vector{Int}}}()
    for f in spec.facets
        grp_l = [Int[] for _ in 1:length(f.levels)]
        for r in 1:n
            push!(grp_l[f.index[r]], r)
        end
        f_grp[f.name] = grp_l
    end

    # Category usage per step group
    cat_rows = NamedTuple[]
    cat_raw_by_group = Vector{Vector{Int}}(undef, length(spec.supports))
    for g in eachindex(spec.supports)
        sup = spec.supports[g]
        lbls_g = cat_labels_by_group[g]
        K_g = length(sup)
        glbl = prob.step_owner === :global ? :Common : prob.step_group_levels[g]
        g_rows = [r for r in 1:n if spec.group[r] == g]
        w_tot = isempty(g_rows) ? 0.0 : sum(w[r] for r in g_rows)
        c_w = zeros(Float64, K_g)
        c_n = zeros(Int, K_g)
        c_exp = zeros(Float64, K_g)
        c_th_sum = zeros(Float64, K_g)
        c_th_n = zeros(Float64, K_g)
        for r in g_rows
            yk_loc = spec.category[r] - first(sup) + 1
            wr = w[r]
            c_w[yk_loc] += wr
            c_n[yk_loc] += 1
            th = Float64(pscores_raw[spec.person[r]].estimate)
            if isfinite(th)
                c_th_sum[yk_loc] += wr * th
                c_th_n[yk_loc] += wr
            end
            pv = p_probs_row[r]
            for k in 1:K_g
                c_exp[k] += wr * pv[k]
            end
        end
        cat_raw_by_group[g] = c_n
        for k in 1:K_g
            push!(cat_rows, (;
                step_facet = prob.step_owner,
                group = glbl,
                category = lbls_g[k],
                count = c_n[k],
                weighted_count = c_w[k],
                proportion = w_tot > 0.0 ? c_w[k] / w_tot : missing,
                expected_count = c_exp[k],
                expected_proportion = w_tot > 0.0 ? c_exp[k] / w_tot : missing,
                average_person_measure = c_th_n[k] > 0.0 ? c_th_sum[k] / c_th_n[k] : missing,
            ))
        end
    end

    n_mod = length(op.model_names)
    bm_of_mod = Vector{Union{Nothing,NamedTuple}}(nothing, n_mod)
    step_bm_idx = Dict{Int,Int}()
    s_counter = 0
    for bm in op.block_meta
        if bm.kind === :steps
            s_counter += 1
            step_bm_idx[first(bm.model_range)] = s_counter
        end
        for m_idx in bm.model_range
            1 <= m_idx <= n_mod && (bm_of_mod[m_idx] = bm)
        end
    end

    facet_rows = NamedTuple[]
    step_rows = NamedTuple[]
    for i in 1:n_mod
        nm = op.model_names[i]
        bm = bm_of_mod[i]
        is_fix = nm in op.fixed_model_names
        est = xi_model_hat[i]
        se_i = se_model[i]
        cse_mstep = cond_se_model[i]
        sand_nt = sand_se_model === nothing ? (;) : (; sandwich_se = sand_se_model[i])
        se_pos = (!is_fix && isfinite(se_i) && se_i > 0.0) ? se_i : missing
        lo = !(se_pos === missing) ? est - z_crit * se_pos : missing
        hi = !(se_pos === missing) ? est + z_crit * se_pos : missing

        if bm !== nothing && bm.kind in (:facet_main, :facet_lltm_strict, :facet_lltm_plus_residual)
            fname = bm.name
            l = i - first(bm.model_range) + 1
            lvl = bm.levels[l]
            rs = f_grp[fname][l]
            info_sum = sum((obs_bzero[r] ? 0.0 : w[r] * obs_var[r]) for r in rs; init = 0.0)
            fac_cond_se = (!is_fix && info_sum > 0.0) ? 1.0 / sqrt(info_sum) : missing
            cond_se_out = bm.kind === :facet_main ? fac_cond_se : cse_mstep
            model_se = m === :mmle ? se_pos : (bm.kind === :facet_main ? fac_cond_se : se_pos)
            has_b = any(r -> obs_bzero[r], rs)
            single_free = m === :jmle && !is_fix && length(rs) == 1
            fstat = _summarize_fit_rows(rs, obs_var, obs_m4, obs_z2, obs_bzero, w;
                has_boundary_proxy = has_b, single_obs_free_jmle = single_free, zstd_cap, whexact)
            real_se = (!(model_se === missing) && !(fstat.infit === missing)) ?
                model_se * sqrt(max(1.0, Float64(fstat.infit))) : missing
            clo = _finite_pos_num(cond_se_out) ? est - z_crit * Float64(cond_se_out) : missing
            chi = _finite_pos_num(cond_se_out) ? est + z_crit * Float64(cond_se_out) : missing
            scores_l = Float64[prob.raw_score[r] for r in rs]
            eta_l = Float64[obs_eta_eff[r] for r in rs]
            meas_l = Float64[Float64(pscores_raw[spec.person[r]].estimate) for r in rs]
            ptm = _ptmea_corr(scores_l, eta_l)
            ptm_p = _ptmea_corr(scores_l, meas_l)
            w_sum_l = isempty(rs) ? 0.0 : sum(w[r] for r in rs)
            raw_sum_l = isempty(rs) ? 0.0 : sum(w[r] * prob.raw_score[r] for r in rs)
            exp_sum_l = isempty(rs) ? 0.0 : sum(w[r] * obs_exp_raw[r] for r in rs)
            f_fair_m, f_fair_z = if has_struct_steps_fa && (same_sup_fa || fname === prob.step_owner)
                c_v_fa = fname === prob.step_owner ? cat_groups_fa[l] : cat_groups_fa[1]
                base_tau = fname === prob.step_owner ? tau_groups_fa[l] : tau_mean_fa
                H_fa = length(base_tau)
                sibm = get(step_int_fa, fname, nothing)
                t_v_fa = sibm === nothing ? base_tau :
                    Float64[base_tau[h] + xi_model_hat[sibm.model_range[(l - 1) * H_fa + h]] for h in 1:H_fa]
                oth_sh = f_sum_means_fa - get(f_means_fa, fname, 0.0)
                fm_v = first(_freq_adjacent_expected_score_and_slope(th_bar_fa - est - oth_sh, t_v_fa, c_v_fa))
                fz_v = first(_freq_adjacent_expected_score_and_slope(mu_int_fa - est, t_v_fa, c_v_fa))
                (isfinite(fm_v) ? fm_v : missing, isfinite(fz_v) ? fz_v : missing)
            else
                (missing, missing)
            end

            push!(facet_rows, merge(
                (;
                    facet = fname,
                    parameter = nm,
                    level = lvl,
                    n_ratings = length(rs),
                    weighted_n = w_sum_l,
                    observed_average = isempty(rs) ? missing : raw_sum_l / w_sum_l,
                    expected_average = isempty(rs) ? missing : exp_sum_l / w_sum_l,
                    fair_m = f_fair_m,
                    fair_z = f_fair_z,
                    fixed = is_fix,
                    sign = -1,
                    estimate = est,
                    se = se_i,
                ),
                sand_nt,
                (;
                    model_se,
                    conditional_se = cond_se_out,
                    mstep_conditional_se = cse_mstep,
                    real_se,
                    lower = lo,
                    upper = hi,
                    conditional_lower = clo,
                    conditional_upper = chi,
                    interval,
                    infit = fstat.infit,
                    outfit = fstat.outfit,
                    infit_zstd = fstat.infit_zstd,
                    outfit_zstd = fstat.outfit_zstd,
                    df_infit = fstat.df_infit,
                    df_outfit = fstat.df_outfit,
                    infit_zstd_engine = fstat.infit_zstd_engine,
                    outfit_zstd_engine = fstat.outfit_zstd_engine,
                    fit_status = fstat.status,
                    ptmea = ptm,
                    ptmea_person = ptm_p,
                    uncertainty_basis = is_fix ? :fixed_constraint :
                        (bm.kind === :facet_main ? :constrained_observed_information : bm.kind),
                ),
            ))
        elseif bm !== nothing && bm.kind === :steps && haskey(step_bm_idx, first(bm.model_range))
            g_idx = step_bm_idx[first(bm.model_range)]
            s_idx = i - first(bm.model_range) + 1
            glbl = prob.step_owner === :global ? :Common : bm.group_level
            lbls_g = cat_labels_by_group[g_idx]
            c_n = cat_raw_by_group[g_idx]
            spacing = s_idx == 1 ? missing : est - xi_model_hat[i - 1]
            disordered = s_idx == 1 ? false : (est < xi_model_hat[i - 1])
            push!(step_rows, merge(
                (;
                    facet = :steps,
                    parameter = nm,
                    level = nm,
                    step_facet = prob.step_owner,
                    group = glbl,
                    step = s_idx,
                    label = "Step_$s_idx",
                    transition = (s_idx + 1 <= length(lbls_g)) ? "$(lbls_g[s_idx])->$(lbls_g[s_idx + 1])" : nm,
                    lower_count = s_idx <= length(c_n) ? c_n[s_idx] : missing,
                    upper_count = (s_idx + 1) <= length(c_n) ? c_n[s_idx + 1] : missing,
                    fixed = is_fix,
                    estimate = est,
                    se = se_i,
                ),
                sand_nt,
                (;
                    conditional_se = cse_mstep,
                    lower = lo,
                    upper = hi,
                    interval,
                    spacing,
                    disordered,
                    uncertainty_basis = is_fix ? :fixed_constraint : :constrained_observed_information,
                ),
            ))
        elseif startswith(nm, "steps[") || startswith(nm, "step_interaction[")
            s_pos = bm === nothing ? i : (i - first(bm.model_range) + 1)
            push!(step_rows, merge(
                (;
                    facet = bm === nothing ? :steps : bm.name,
                    parameter = nm,
                    level = nm,
                    step_facet = prob.step_owner,
                    group = bm === nothing ? :Custom : bm.name,
                    step = s_pos,
                    label = nm,
                    transition = missing,
                    lower_count = missing,
                    upper_count = missing,
                    fixed = is_fix,
                    estimate = est,
                    se = se_i,
                ),
                sand_nt,
                (;
                    conditional_se = cse_mstep,
                    lower = lo,
                    upper = hi,
                    interval,
                    spacing = missing,
                    disordered = false,
                    uncertainty_basis = is_fix ? :fixed_constraint : :constrained_observed_information,
                ),
            ))
        else
            push!(facet_rows, merge(
                (;
                    facet = bm === nothing ? :mrcml : bm.name,
                    parameter = nm,
                    level = nm,
                    n_ratings = missing,
                    weighted_n = missing,
                    observed_average = missing,
                    expected_average = missing,
                    fixed = is_fix,
                    sign = -1,
                    estimate = est,
                    se = se_i,
                ),
                sand_nt,
                (;
                    model_se = se_pos,
                    conditional_se = cse_mstep,
                    mstep_conditional_se = cse_mstep,
                    real_se = missing,
                    lower = lo,
                    upper = hi,
                    conditional_lower = missing,
                    conditional_upper = missing,
                    interval,
                    infit = missing,
                    outfit = missing,
                    infit_zstd = missing,
                    outfit_zstd = missing,
                    df_infit = missing,
                    df_outfit = missing,
                    infit_zstd_engine = missing,
                    outfit_zstd_engine = missing,
                    fit_status = :not_applicable_design_term,
                    ptmea = missing,
                    ptmea_person = missing,
                    uncertainty_basis = is_fix ? :fixed_constraint : :constrained_observed_information,
                ),
            ))
        end
    end

    flens = Dict(f.name => length(f.levels) for f in spec.facets)
    rel_rows = _mrcml_reliability_rows(
        Symbol[f.name for f in spec.facets],
        flens,
        op,
        m,
        has_grouped_pop,
        extreme_adjusted,
        person_scores,
        facet_rows,
        ext_facets;
        variance = :sample,
        se = :default,
        nonextreme_only = false,
    )

    return (;
        overall_fit,
        person_scores,
        facet_rows,
        step_rows,
        cat_rows,
        reliability_rows = rel_rows,
    )
end

function fit(spec::Union{B.AdditiveFacets.MRCMLTarget,B.AdditiveFacets.MRCMLSpec};
        method::Symbol = :mmle,
        quadrature::Symbol = :gauss_hermite,
        quad_points::Int = 31,
        theta_lim::Real = 4.0,
        population_mean::Real = 0.0,
        population_sd::Real = 1.0,
        estimate_mean::Bool = false,
        estimate_sd::Bool = false,
        extreme_adjustment::Real = 0.0,
        population_link = nothing,
        weights = nothing,
        maxit::Int = 500,
        gtol::Real = 1e-9,
        interval::Real = 0.95,
        zstd_cap::Union{Nothing,Real} = 9.0,
        whexact::Bool = true)
    0.0 < Float64(interval) < 1.0 || throw(ArgumentError("interval must lie in (0, 1)"))
    zstd_cap === nothing || (zstd_cap isa Real && !(zstd_cap isa Bool) && isfinite(zstd_cap) && Float64(zstd_cap) > 0.0) ||
        throw(ArgumentError("zstd_cap must be nothing or a finite positive real number"))
    cap_f = zstd_cap === nothing ? nothing : Float64(zstd_cap)
    t0 = time()
    m = _normalize_method(method)
    pop = get(spec.spec_record,:population,nothing)
    if !isnothing(pop)
        hasproperty(pop,:person_chart) && throw(ArgumentError("person_coordinates selects NUTS coordinates; omit it for MMLE"))
        m === :mmle && !estimate_mean && !estimate_sd && population_mean==0 && population_sd==1 ||
            throw(ArgumentError("grouped MMLE estimates its declared means and group SDs; omit scalar population controls"))
    end
    joint_cal = get(spec.spec_record,:calibration,nothing)
    if !isnothing(joint_cal)
        spec isa B.AdditiveFacets.MRCMLSpec && m === :mmle && (estimate_mean || !isnothing(pop)) ||
            throw(ArgumentError("two-stage covariance propagation requires a prior-free MMLE specification with estimate_mean=true or a grouped population"))
    end
    op = spec.operator
    n = op.n_obs
    P = length(spec.people)
    d_xi = size(op.A_free, 2)

    w = weights === nothing ? ones(Float64, n) : Float64.(weights)
    length(w) == n && all(x -> isfinite(x) && x > 0.0, w) ||
        throw(ArgumentError("weights must have length $n with finite positive values"))
    quad_points >= 3 || throw(ArgumentError("quad_points must be >= 3"))
    Float64(population_sd) > 0.0 && isfinite(population_sd) && isfinite(population_mean) ||
        throw(ArgumentError("population_mean must be finite and population_sd > 0"))
    Float64(extreme_adjustment) >= 0.0 && isfinite(extreme_adjustment) ||
        throw(ArgumentError("extreme_adjustment must be finite and >= 0"))

    # Identifiability checks for the requested frequentist estimator!
    spec.allocation.structural_identified ||
        throw(ArgumentError("MRCML structural design matrix `A` is rank-deficient ($(spec.allocation.structural_rank)/$(d_xi)); aliased columns: $(spec.allocation.dependent_structural_columns)"))

    pop_link_receipt = nothing
    if m === :jmle
        population_link === nothing ||
            throw(ArgumentError("population_link applies only to method = :mmle (not :jmle)"))
        (estimate_mean || estimate_sd) &&
            throw(ArgumentError("estimate_mean / estimate_sd apply to method = :mmle only"))
        spec.allocation.conditional_joint_identified ||
            throw(ArgumentError("JMLE cannot identify free person abilities together with an unconstrained global location intercept or person-disconnected facet in `A` (joint rank $(spec.allocation.conditional_joint_rank)/$(P + d_xi)); center facet columns, add bridging examinees, or use `method = :mmle`"))
    else
        # Check whether MMLE is relying on an equivalent-population assumption to link facets
        # across disjoint person cohorts (e.g., person nested in task).
        disj_chk = B._cr5_disjoint_subsets(spec.people, spec.person, B._cr5_facet_tuples(spec.facets))
        disconnected_facets = Symbol[fr.facet for fr in disj_chk.by_facet if !fr.connected]
        needs_pop_link = !spec.allocation.conditional_joint_identified && !isempty(disconnected_facets) && isnothing(pop)
        if needs_pop_link
            if population_link === nothing
                throw(ArgumentError(
                    "MMLE requires an explicit equivalent-population assumption with a documented allocation rationale to link facet(s) $(disconnected_facets) across non-overlapping person cohorts (conditional joint rank $(spec.allocation.conditional_joint_rank)/$(P + d_xi)). " *
                    "If examinees were assigned from a common latent population, opt in explicitly with `population_link = (mode = :common_population, rationale = \"<allocation basis>\")` and `estimate_mean = false`; otherwise add bridging examinees or external calibration anchors."))
            end
            if population_link === :common_population
                throw(ArgumentError(
                    "population_link = :common_population shorthand is not accepted when linking non-overlapping person cohorts $(disconnected_facets); pass `population_link = (mode = :common_population, rationale = \"<nonblank allocation basis>\")`"))
            end
            pl_mode = (population_link isa NamedTuple && haskey(population_link, :mode)) ? Symbol(population_link.mode) : :invalid
            pl_mode === :common_population ||
                throw(ArgumentError("unsupported population_link = $(repr(population_link)); pass `(mode = :common_population, rationale = \"<nonblank allocation basis>\")`"))
            estimate_mean && throw(ArgumentError(
                "MMLE with `population_link = (mode = :common_population, ...)` requires `estimate_mean = false` (fixing the shared latent mean while cohort-specific means remain constrained equal); freeing cohort means re-introduces non-identifiability."))
            has_valid_rationale = haskey(population_link, :rationale) &&
                (population_link.rationale isa AbstractString) &&
                !isempty(strip(String(population_link.rationale)))
            has_valid_rationale ||
                throw(ArgumentError(
                    "MMLE `population_link` requires a nonblank string `rationale` documenting the allocation basis (e.g. `population_link = (mode = :common_population, rationale = \"random assignment to tasks\")`) when linking non-overlapping person cohorts $(disconnected_facets)"))
            rationale = String(strip(String(population_link.rationale)))
            pop_link_receipt = (;
                mode = :common_population,
                allocation_rationale = rationale,
                bridged_facets = disconnected_facets,
                shared_latent_distribution = (;
                    family = :Normal,
                    population_mean = Float64(population_mean),
                    population_sd = Float64(population_sd),
                    estimate_sd = Bool(estimate_sd),
                ),
                shared_measurement_scale = true,
                free_group_means_reintroduces_nonidentifiability = true,
            )
        elseif estimate_mean && !spec.allocation.conditional_joint_identified
            throw(ArgumentError("MMLE with `estimate_mean = true` cannot identify `population_mean` when `A` already spans a global location intercept; set `estimate_mean = false` (TAM convention)"))
        elseif population_link !== nothing
            pl_mode = population_link === :common_population ? :common_population :
                      (population_link isa NamedTuple && haskey(population_link, :mode) ? Symbol(population_link.mode) : :invalid)
            pl_mode === :common_population ||
                throw(ArgumentError("unsupported population_link = $(repr(population_link)); pass `(mode = :common_population, rationale = \"...\")`"))
            rationale = (population_link isa NamedTuple && haskey(population_link, :rationale) &&
                         population_link.rationale isa AbstractString && !isempty(strip(String(population_link.rationale)))) ?
                String(strip(String(population_link.rationale))) : "explicitly declared (design already directly linked)"
            pop_link_receipt = (;
                mode = :common_population,
                allocation_rationale = rationale,
                bridged_facets = Symbol[],
                shared_latent_distribution = (;
                    family = :Normal,
                    population_mean = Float64(population_mean),
                    population_sd = Float64(population_sd),
                    estimate_sd = Bool(estimate_sd),
                ),
                shared_measurement_scale = true,
                free_group_means_reintroduces_nonidentifiability = false,
            )
        end
    end

    # Build compatible FacetDef list and map 1-based `spec.supports` / `spec.category` onto actual `spec.categories` values!
    fdefs = FacetDef[
        FacetDef(b.name, Vector{Any}(b.levels), copy(b.index), -1, fill(NaN, length(b.levels)), true, :sum_to_zero)
        for b in spec.facets
    ]
    cat_labels_by_group = [Int[spec.categories[k] for k in sup] for sup in spec.supports]
    all_consec = all(g -> collect(first(cat_labels_by_group[g]):last(cat_labels_by_group[g])) == cat_labels_by_group[g],
        eachindex(cat_labels_by_group))
    prob_supports = [all_consec ? (first(cat_labels_by_group[g]):last(cat_labels_by_group[g])) :
        (1:length(cat_labels_by_group[g])) for g in eachindex(cat_labels_by_group)]
    raw_scores = Int[spec.categories[c] for c in spec.category]
    obs_bind = if all_consec
        _observation_binding_hash(spec.people, spec.person, fdefs, prob_supports, spec.group, raw_scores, w)
    else
        B._cache_hash((;
            person = [string(spec.people[p]) for p in spec.person],
            facets = [(; name = String(f.name), values = [string(f.levels[i]) for i in f.index]) for f in fdefs],
            row_supports = [Tuple(cat_labels_by_group[spec.group[i]]) for i in 1:n],
            raw_score = raw_scores,
            weights = w,
        ))
    end
    score_k = [spec.category[i] - first(spec.supports[spec.group[i]]) for i in 1:n]
    prob = Problem(
        MRCML_FREQ_FIT_TAG, :mrcml, m, n,
        Vector{Any}(spec.people), copy(spec.person), fill(NaN, P), false, :mrcml,
        fdefs, spec.owner, copy(spec.group), deepcopy(spec.group_levels), prob_supports,
        score_k, raw_scores, w, :person, :mrcml, obs_bind,
    )

    p_ext = _mrcml_person_extremes(op, n, P, spec.person, spec.group, spec.supports, spec.category)
    any(==(:unobserved), p_ext) && throw(ArgumentError("one or more declared persons have zero observations"))
    if m === :jmle && any(==(:unidentified_zero_slope), p_ext)
        throw(ArgumentError("one or more persons have zero ability slope variation across all observed items in `B`; person ability is unidentified in JMLE"))
    end

    if m === :mmle
        base_quad = build_quadrature(quadrature, quad_points; sd = 1.0, theta_lim = Float64(theta_lim))
        mu_idx = estimate_mean ? (d_xi + 1) : 0
        lsig_idx = estimate_sd ? (d_xi + (estimate_mean ? 2 : 1)) : 0
        n_free = d_xi + (estimate_mean ? 1 : 0) + (estimate_sd ? 1 : 0)

        br = (d_xi+1):(d_xi+(isnothing(pop) ? 0 : size(pop.X,2)))
        n_pop_sd = isnothing(pop) ? 0 : (Bool(get(pop, :equal_sd, false)) ? 1 : length(pop.groups))
        sr = (last(br)+1):(last(br)+n_pop_sd)
        mmle_scratch = isnothing(pop) ?
            _build_mrcml_mmle_scratch(op, P, spec.group, spec.supports, spec.category, base_quad) :
            nothing
        parts = isnothing(pop) ? nothing : [
            merge(a, (; scratch = _build_mrcml_mmle_scratch(a.op, length(a.persons), a.owner, a.support, a.category, base_quad)))
            for a in _population_parts(spec,pop,w)
        ]
        n_free_val::Int = isnothing(pop) ? n_free : last(sr)
        n_free = n_free_val
        x0 = zeros(Float64, n_free_val)
        mu_idx > 0 && (x0[mu_idx] = Float64(population_mean))
        lsig_idx > 0 && (x0[lsig_idx] = log(Float64(population_sd)))

        function fg!(g,x,offset=op.c_pat)
            if isnothing(pop)
                return _mrcml_mmle_nll_and_grad!(g,x,op,P,spec.person,spec.group,spec.supports,
                    spec.category,w,base_quad,Float64(population_mean),Float64(population_sd),
                    mu_idx,lsig_idx,offset,mmle_scratch)
            end
            return _grouped_mmle!(g,x,parts,base_quad,br,sr,offset)
        end
        function grad_vec(x, offset=op.c_pat)
            T_g = promote_type(eltype(x), eltype(offset))
            gv = Vector{T_g}(undef, n_free_val)
            fg!(gv, x, offset)
            return gv
        end
        patterns = _pattern_derivatives(op)
        function observed_info(u; calibration=false)
            if isnothing(pop)
                return _mrcml_louis(u,op,spec.person,spec.group,spec.supports,spec.category,
                    w,base_quad,Float64(population_mean),Float64(population_sd),mu_idx,lsig_idx,
                    mmle_scratch,patterns; calibration)
            end
            return _grouped_louis(u,parts,base_quad,br,sr,patterns; calibration)
        end
        lbfgs_gtol = n_free_val <= 2000 ? max(Float64(gtol), 1e-5) : Float64(gtol)
        opt = _optimize_lbfgs(fg!, x0; maxit = Int(maxit), gtol = lbfgs_gtol)
        u_hat = copy(opt.x)

        # Exact Newton-Cholesky polish on the exact marginal log-likelihood Hessian
        # using complete information minus posterior score covariance.
        g_final = copy(opt.g)
        ll_neg = opt.f
        nit_tot = opt.nit
        nfev_tot = opt.nfev
        polish_gtol = min(Float64(gtol), 1e-11)

        for _ in 1:12
            norm(g_final, Inf) <= polish_gtol && break
            H_pol = observed_info(u_hat)
            F_ch = cholesky(H_pol; check = false)
            if !issuccess(F_ch)
                lam = max(1e-6, -minimum(eigvals(Matrix(H_pol))) + 1e-5)
                F_ch = cholesky(Symmetric(Matrix(H_pol) + lam * I); check = false)
                issuccess(F_ch) || break
            end
            dx = -(F_ch \ g_final)
            dg = dot(g_final, dx)
            dg < 0.0 || break
            step = 1.0
            improved = false
            for _ in 1:25
                u_try = u_hat .+ step .* dx
                g_try = zeros(Float64, n_free_val)
                f_try = fg!(g_try, u_try)
                nfev_tot += 1
                if isfinite(f_try) && (f_try <= ll_neg + 1e-4 * step * dg || norm(g_try, Inf) < 0.5 * norm(g_final, Inf))
                    u_hat = u_try
                    g_final = g_try
                    ll_neg = f_try
                    nit_tot += 1
                    improved = true
                    break
                end
                step *= 0.5
            end
            improved || break
        end
        u_hat_final = u_hat

        information = observed_info(u_hat_final; calibration=true)
        H_obs = information.observed
        eigs = n_free > 0 ? eigvals(Matrix(H_obs)) : Float64[1.0]
        min_eig = minimum(eigs)
        max_eig = maximum(eigs)
        hess_pd = min_eig > 1e-10
        cond_num = hess_pd ? max_eig / min_eig : Inf
        cov_free = hess_pd && n_free > 0 ? Matrix(inv(H_obs)) : fill(NaN, n_free, n_free)
        B_meat = (P > 1 ? P/(P-1) : 1.0) * information.meat
        I_cond = information.conditional
        sandwich_free = (hess_pd && n_free > 0) ? Matrix(Symmetric(cov_free * Matrix(B_meat) * cov_free')) : fill(NaN, n_free, n_free)

        eta_hat = u_hat[1:d_xi]
        mu_hat = mu_idx > 0 ? u_hat[mu_idx] : Float64(population_mean)
        sig_hat = lsig_idx > 0 ? exp(u_hat[lsig_idx]) : Float64(population_sd)
        mu_se = (mu_idx > 0 && hess_pd) ? sqrt(max(cov_free[mu_idx, mu_idx], 0.0)) : missing
        sig_se = (lsig_idx > 0 && hess_pd) ? sig_hat * sqrt(max(cov_free[lsig_idx, lsig_idx], 0.0)) : missing

        # Model-scale parameter vector & exact constrained observed-information SEs + Huber-White sandwich SEs + TAM conditional M-step SEs!
        xi_model_hat = op.xi0_model .+ Vector{Float64}(op.J_model * eta_hat)
        cov_eta = d_xi > 0 ? cov_free[1:d_xi, 1:d_xi] : zeros(Float64, 0, 0)
        cov_model = Matrix(op.J_model * cov_eta * op.J_model')
        sand_eta = d_xi > 0 ? sandwich_free[1:d_xi, 1:d_xi] : zeros(Float64, 0, 0)
        sand_model = Matrix(op.J_model * sand_eta * op.J_model')
        se_model = [hess_pd ? sqrt(max(cov_model[i, i], 0.0)) : NaN for i in 1:size(cov_model, 1)]
        sand_se_model = [hess_pd ? sqrt(max(sand_model[i, i], 0.0)) : NaN for i in 1:size(sand_model, 1)]
        se_free_obs = [hess_pd ? sqrt(max(cov_eta[i, i], 0.0)) : NaN for i in 1:d_xi]
        sand_se_free = [hess_pd ? sqrt(max(sand_eta[i, i], 0.0)) : NaN for i in 1:d_xi]

        if isnothing(pop)
            quad_scaled = build_quadrature(quadrature, quad_points; sd = sig_hat, theta_lim = Float64(theta_lim))
            pscores = _mrcml_person_scores_from_calibration(
                eta_hat, op, spec.people, spec.person, spec.group, spec.supports, spec.categories, spec.category, w;
                method = :mmle, quad = quad_scaled, mu_hat, sigma_hat = sig_hat,
            )

        else
            pscores = _grouped_person_scores(spec,parts,eta_hat,u_hat[br],exp.(u_hat[sr]),base_quad)
        end
        # TAM `se.xsi` convention: 1 / sqrt(diag(I_cond)) for free xsi, and J_model * diag(1/diag(I_cond)) * J_model' for reconstructed rows!
        cond_var_eta = [I_cond[i, i] > 1e-14 ? 1.0 / I_cond[i, i] : NaN for i in 1:d_xi]
        cond_se_free = sqrt.(max.(cond_var_eta, 0.0))
        J_dense = Matrix(op.J_model)
        cond_se_model = [
            begin
                acc = 0.0
                ok_c = true
                for c in 1:d_xi
                    J_dense[r, c] == 0.0 && continue
                    isnan(cond_var_eta[c]) && (ok_c = false; break)
                    acc += J_dense[r, c]^2 * cond_var_eta[c]
                end
                ok_c ? sqrt(acc) : NaN
            end for r in 1:size(J_dense, 1)
        ]

        ll = -ll_neg
        max_grad = isempty(g_final) ? 0.0 : norm(g_final, Inf)
        conv = max_grad <= 1e-5
        stat_ok = conv && hess_pd && cond_num <= 1e10

        free_names_all = copy(op.free_names)
        mu_idx > 0 && push!(free_names_all, "population_mean")
        lsig_idx > 0 && push!(free_names_all, "log_population_sd")

        if !isnothing(pop)
            append!(free_names_all,_grouped_names(pop,:raw))
        end

        # Build Layout so `parameter_names(fit; scale = :raw | :model)` and `coordinates(fit)` work seamlessly!
        n_mod = length(op.model_names)
        J_lay = spzeros(Float64, n_mod, n_free)
        J_lay[:, 1:d_xi] = op.J_model
        f_mask = BitVector([nm in op.fixed_model_names for nm in op.model_names])
        lay = Layout(
            n_mod, 1:0, UnitRange{Int}[], UnitRange{Int}[], 1:0, UnitRange{Int}[], UnitRange{Int}[],
            mu_idx, lsig_idx, n_free, copy(op.xi0_model), J_lay,
            free_names_all, copy(op.model_names), f_mask, p_ext, collect(1:P), collect(1:n),
        )

        # Build `structural_parameters` (both free and reconstructed model-scale rows!) and `facet_measures` / `step_measures`
        free_table = [
            (;
                index = i,
                parameter = op.free_names[i],
                estimate = eta_hat[i],
                se = se_free_obs[i],
                sandwich_se = sand_se_free[i],
                conditional_se = cond_se_free[i],
            ) for i in 1:d_xi
        ]

        aic_v = -2.0 * ll + 2.0 * n_free
        bic_p = -2.0 * ll + n_free * log(P)
        bic_n = -2.0 * ll + n_free * log(n)
        elapsed = time() - t0

        summary_nt = (;
            inference_paradigm = :frequentist,
            is_bayesian_posterior = false,
            source_kind = MRCML_FREQ_FIT_TAG,
            model = :mrcml,
            method = :mmle,
            n_observations = n,
            n_persons = P,
            n_patterns = op.n_patterns,
            n_facets = length(spec.facets),
            facet_names = [f.name for f in spec.facets],
            step_owner = spec.owner,
            noncenter_facet = :person,
            centering = :mrcml_design_matrix,
            n_free_parameters = n_free,
            n_structural_free = d_xi,
            loglikelihood = ll,
            deviance = -2.0 * ll,
            aic = aic_v,
            bic_persons = bic_p,
            bic_observations = bic_n,
            converged = conv,
            stationarity_qualified = stat_ok,
            max_abs_gradient = max_grad,
            hessian_positive_definite = hess_pd,
            min_hessian_eigenvalue = min_eig,
            hessian_condition_number = cond_num,
            n_iterations = nit_tot,
            n_evaluations = nfev_tot,
            elapsed_seconds = elapsed,
            extreme_adjustment = missing,
            quadrature,
            quad_points,
            theta_lim = Float64(theta_lim),
            population_mean = mu_hat,
            population_sd = sig_hat,
            population_mean_se = mu_se,
            population_sd_se = sig_se,
            estimate_mean,
            estimate_sd,
            mml_engine = :mrcml_quadrature_lbfgs_newton,
            observation_binding = obs_bind,
        )
        warnings = [
            "MRCML MMLE integrates person abilities over a $(quad_points)-point $(quadrature) grid; `se` reports coordinate-invariant observed-information SEs while `conditional_se` reports TAM-compatible diagonal M-step SEs.",
        ]
        if !isnothing(pop)
            summary_nt = merge(summary_nt,(;population=_grouped_summary(pop,u_hat,br,sr,cov_free; sandwich_cov = sandwich_free),
                population_mean=missing,population_sd=missing))
        end
        if !isnothing(joint_cal)
            report = (;method=:two_stage_delta,assumption=:independent_calibration_and_receiving_panels,
                coordinates=deepcopy(joint_cal.coordinates), covariance=copy(joint_cal.covariance),
                status=stat_ok ? :available : :unqualified_receiving_information)
            if stat_ok
                J = B.AdditiveFacets._calibration_map(joint_cal.coordinates,op.model_names,
                    spec.group_levels,spec.supports,spec.categories)
                A_cal = op.A_model * J
                function receiving_score(d)
                    offset = op.c_pat .+ A_cal*d
                    grad_vec(u_hat_final, offset)
                end
                cross = ForwardDiff.jacobian(receiving_score,zeros(length(joint_cal.coordinates)))
                # Solve jointly before selecting contrasts: all estimated nuisance terms can move.
                sensitivity = -(cholesky(H_obs) \ cross)
                L = cholesky(Symmetric(joint_cal.covariance)).L
            end
            function uncertainty(i)
                conditional_se = hess_pd ? sqrt(cov_free[i,i]) : missing
                if !stat_ok
                    return (;conditional_se,gradient=missing,calibration_variance=missing,propagated_se=missing)
                end
                gradient = sensitivity[i,:]
                calibration_variance = norm(L' * gradient)^2
                (;conditional_se,gradient,calibration_variance,propagated_se=sqrt(conditional_se^2+calibration_variance))
            end
            if isnothing(pop)
                result = uncertainty(mu_idx)
                summary_nt = merge(summary_nt,(;population_mean_se=result.propagated_se,calibration=merge(report,result)))
                push!(warnings,"Population mean SE includes calibration uncertainty by the two-stage delta method. Other SEs condition on the supplied calibration estimates.")
            else
                population = summary_nt.population
                compared = filter(!=(pop.reference),pop.groups)
                contrasts = map(eachindex(compared)) do j
                    c = population.coefficients[j]
                    (;group=compared[j],reference=pop.reference,c.term,c.estimate,uncertainty(br[j])...)
                end
                coefficients = [j <= length(contrasts) ? merge(c,(;se=contrasts[j].propagated_se)) : c
                                for (j,c) in enumerate(population.coefficients)]
                summary_nt = merge(summary_nt,(;population=merge(population,(;coefficients)),
                    calibration=merge(report,(;contrasts))))
                push!(warnings,"Group-versus-reference SEs use two-stage calibration propagation when the receiving information qualifies. Other SEs and plug-in plausible values condition on the supplied calibration.")
            end
        elseif hasproperty(spec.spec_record,:fixed_calibration)
            summary_nt = merge(summary_nt, (; fixed_calibration=deepcopy(spec.spec_record.fixed_calibration)))
            push!(warnings,"Standard errors are conditional on the supplied fixed calibration.")
        end
        if pop_link_receipt !== nothing
            summary_nt = merge(summary_nt, (; population_link = pop_link_receipt))
            if !isempty(pop_link_receipt.bridged_facets)
                push!(warnings,
                    "Facet(s) $(pop_link_receipt.bridged_facets) are linked across non-overlapping person cohorts solely via the explicit `:common_population` assumption (rationale: $(pop_link_receipt.allocation_rationale)); numerical qualification does not verify cohort equivalence, and freeing cohort ability means re-introduces non-identifiability.")
            end
        end
        ext_facets_mmle = _mrcml_extreme_facet_levels(spec)
        n_free_ext_mmle = count(x -> !x.fixed, ext_facets_mmle)
        n_free_ext_mmle > 0 && push!(warnings,
            "Extreme (all-minimum or all-maximum) free facet level(s) detected: $(n_free_ext_mmle); unpenalized ML estimates on free extreme facet levels are unbounded (inspect extreme_facet_levels).")
        diag_tabs_mmle = _mrcml_compute_diagnostics_and_tables(
            spec, prob, op, cat_labels_by_group,
            eta_hat, xi_model_hat, se_model, cond_se_model, sand_se_model,
            pscores, w, ll, n_free, ext_facets_mmle;
            has_grouped_pop = !isnothing(pop),
            extreme_adjusted = false,
            interval = Float64(interval),
            zstd_cap = cap_f,
            whexact = Bool(whexact),
        )
        core_body = (;
            schema = FIT_SCHEMA,
            summary = summary_nt,
            problem = prob,
            layout = lay,
            mrcml_operator = op,
            mrcml_category_labels = cat_labels_by_group,
            u_free = u_hat,
            eta_free = eta_hat,
            free_parameters = free_table,
            full_parameters = xi_model_hat,
            gradient = g_final,
            full_se = se_model,
            covariance = (; offset = 0, matrix = cov_model, free_covariance = cov_free,
                            sandwich_matrix = sand_model, sandwich_free_covariance = sandwich_free),
            overall_fit = diag_tabs_mmle.overall_fit,
            person_scores = diag_tabs_mmle.person_scores,
            facet_measures = diag_tabs_mmle.facet_rows,
            step_measures = diag_tabs_mmle.step_rows,
            category_usage = diag_tabs_mmle.cat_rows,
            reliability = diag_tabs_mmle.reliability_rows,
            extreme_facet_levels = ext_facets_mmle,
            warnings,
        )
        digest = _frequentist_fit_digest(core_body)
        return Fit(merge(core_body, (; content_hash = digest)))
    else
        # JMLE on MRCML design matrix (`method = :jmle`)
        separate_ext = Float64(extreme_adjustment) == 0.0
        interior_p = separate_ext ? [p for p in 1:P if p_ext[p] === :interior] : collect(1:P)
        isempty(interior_p) && throw(ArgumentError("no interior persons remain for unadjusted MRCML JMLE"))
        p_to_free = zeros(Int, P)
        for (k, p) in enumerate(interior_p)
            p_to_free[p] = k
        end
        active_rows = separate_ext ? [i for i in 1:n if p_to_free[spec.person[i]] > 0] : collect(1:n)
        d_theta = length(interior_p)
        n_free = d_theta + d_xi

        # CR5 guard: verify that removing extreme persons does not disconnect or rank-deficiency
        # the active unadjusted JMLE design matrix (extreme-only bridges cannot link unadjusted JMLE).
        if separate_ext && length(active_rows) < n
            At_chk = sparse(op.A_free')
            rv_chk = rowvals(At_chk)
            nz_chk = nonzeros(At_chk)
            jr_chk = Int[]
            jc_chk = Int[]
            jv_chk = Float64[]
            jrow = 0
            for i in active_rows
                u = op.pattern_of_row[i]
                rng = op.pattern_ranges[u]
                m1 = first(rng)
                b1 = op.B_pat[m1]
                fp = p_to_free[spec.person[i]]
                for m in rng[2:end]
                    jrow += 1
                    db = op.B_pat[m] - b1
                    if db != 0.0
                        push!(jr_chk, jrow); push!(jc_chk, fp); push!(jv_chk, db)
                    end
                    for ptr in nzrange(At_chk, m)
                        push!(jr_chk, jrow); push!(jc_chk, d_theta + rv_chk[ptr]); push!(jv_chk, nz_chk[ptr])
                    end
                    for ptr in nzrange(At_chk, m1)
                        push!(jr_chk, jrow); push!(jc_chk, d_theta + rv_chk[ptr]); push!(jv_chk, -nz_chk[ptr])
                    end
                end
            end
            M_act = sparse(jr_chk, jc_chk, jv_chk, jrow, n_free)
            dropzeros!(M_act)
            act_names = vcat(["person[$(repr(spec.people[p]))]" for p in interior_p], op.free_names)
            act_audit = B.AdditiveFacets._mrcml_spqr_rank(M_act, act_names)
            if !act_audit.full_rank
                throw(ArgumentError(
                    "Unadjusted MRCML JMLE (`extreme_adjustment = 0.0`) became rank-deficient or score-disconnected after excluding extreme-scoring persons (active rank $(act_audit.rank)/$(n_free), $(length(active_rows))/$(n) interior rows; aliased: $(act_audit.dependent_columns)). Inspect `validate_design(spec).connectedness`, add interior bridging observations, or use `method = :mmle`, Bayesian NUTS, or positive `extreme_adjustment`."))
            end
        end

        # CR5 Fischer (1981) one-sided separation guard for unadjusted MRCML JMLE
        if separate_ext && !isempty(active_rows)
            fmeta = B._cr5_facet_tuples(spec.facets)
            fmap = B._cr5_fixed_facet_level_lookup(spec)
            sep = B._cr5_fischer_separation_audit(
                spec.people, spec.person, fmeta, spec.category, spec.supports, spec.group,
                active_rows; op, fixed_map = fmap)
            if sep.separated
                reasons = vcat(
                    String[String(rec.reason) for rec in sep.by_facet if rec.separated],
                    String[String(trec.reason) for trec in sep.threshold_separations],
                )
                throw(ArgumentError(
                    "Unadjusted MRCML JMLE (`extreme_adjustment = 0.0`) has no finite solution due to demonstrated score/threshold separation: " *
                    join(reasons, " ") *
                    " Inspect `validate_design(spec).one_sided_separation`, add bridging ratings, or use `method = :mmle`, Bayesian NUTS, or positive `extreme_adjustment`."))
            end
        end

        x0 = zeros(Float64, n_free)
        fg_j! = (g, x) -> _mrcml_jmle_nll_and_grad!(
            g, x, op, interior_p, p_to_free, active_rows, spec.person, spec.group,
            spec.supports, spec.category, w, Float64(extreme_adjustment),
        )
        # Use the scored sufficient statistic, including custom B and observation weights.
        available = zeros(d_theta)
        remaining = zeros(d_theta)
        for i in active_rows
            ix = p_to_free[spec.person[i]]
            rng = op.pattern_ranges[op.pattern_of_row[i]]
            bs = view(op.B_pat, rng)
            val = bs[spec.category[i] - first(spec.supports[spec.group[i]]) + 1]
            available[ix] += w[i] * (val - minimum(bs))
            remaining[ix] += w[i] * (maximum(bs) - val)
        end
        x0[1:d_theta] .= log.((available .+ 0.5) ./ (remaining .+ 1.0))

        # Traverse category design rows in CSC order. Only coordinates present in this
        # pattern can contribute to its conditional covariance.
        patterns = _pattern_derivatives(op)
        function compute_jmle_schur(x; direction_only=false)
            vp = op.c_pat + op.A_free * view(x, d_theta+1:n_free)
            D_th = zeros(d_theta)
            width = size(patterns.J,1)
            cross = zeros(d_theta,width)
            info = zeros(width,width)
            pvec = zeros(maximum(length, spec.supports))
            mean_a = zeros(width)
            for i in active_rows
                person = p_to_free[spec.person[i]]
                pat = op.pattern_of_row[i]
                rng = op.pattern_ranges[pat]
                cols, A = patterns.patterns[pat]
                pr = view(pvec, 1:length(rng))
                for (k,m) in enumerate(rng)
                    pr[k] = op.B_pat[m] * x[person] + vp[m]
                end
                top = maximum(pr)
                @. pr = exp(pr - top)
                pr ./= sum(pr)
                bbar = dot(pr, view(op.B_pat, rng))
                abar = view(mean_a, eachindex(cols))
                mul!(abar, A, pr)
                for (k,m) in enumerate(rng)
                    db = op.B_pat[m] - bbar
                    wp = w[i] * pr[k]
                    D_th[person] += wp * db^2
                    for (j,a) in enumerate(cols)
                        wa = wp * (A[j,k] - abar[j])
                        cross[person,a] += db * wa
                        for (l,b) in enumerate(cols)
                            info[b,a] += wa * (A[l,k] - abar[l])
                        end
                    end
                end
            end
            H_tx = cross * patterns.J
            H_xx = patterns.J' * info * patterns.J
            positive = all(v -> isfinite(v) && v > 1e-12, D_th)
            S = positive ? Symmetric(H_xx - H_tx' * (H_tx ./ D_th)) : Symmetric(H_xx)
            ch = cholesky(S; check=false)
            if direction_only
                return positive && issuccess(ch) ? (; factor=ch, diagonal=D_th, cross=H_tx) : nothing
            end
            eigs = isempty(S) ? [1.0] : eigvals(S)
            meig = minimum(eigs)
            ok = positive && issuccess(ch) && meig > 1e-10
            cov_eta = ok ? inv(ch) : fill(NaN, d_xi, d_xi)
            cond_num = ok ? max(maximum(eigs), maximum(D_th; init=0.0)) / min(meig, minimum(D_th; init=Inf)) : Inf
            return (; ok, D_th, H_tx, H_xx, cov_eta, min_eig=meig, cond_num)
        end
        direction = (x,g) -> _joint_schur_direction(compute_jmle_schur(x; direction_only=true), g)
        solution = _fit_joint_newton(fg_j!, direction, x0; maxit, gtol=Float64(gtol))
        u_hat, g_final, ll_neg = solution.x, solution.g, solution.f
        nit_tot, nfev_tot = solution.nit, solution.nfev
        sch = compute_jmle_schur(u_hat)
        th_free_hat = u_hat[1:d_theta]
        eta_hat = u_hat[(d_theta + 1):n_free]
        th_full = [p_to_free[p] > 0 ? th_free_hat[p_to_free[p]] :
            (p_ext[p] === :all_minimum ? -Inf : (p_ext[p] === :all_maximum ? Inf : NaN)) for p in 1:P]

        # Exact joint person diagonal SE from inverse Schur complement:
        # Var(theta_i) = 1/D_i + (D^{-1} H_tx cov_eta H_tx' D^{-1})_{ii}
        th_se_full = fill(NaN, P)
        if sch.ok
            for (k, p) in enumerate(interior_p)
                v_row = sch.H_tx[k, :] ./ sch.D_th[k]
                v_th = (1.0 / sch.D_th[k]) + (d_xi > 0 ? dot(v_row, sch.cov_eta * v_row) : 0.0)
                th_se_full[p] = sqrt(max(v_th, 0.0))
            end
        end

        xi_model_hat = op.xi0_model .+ Vector{Float64}(op.J_model * eta_hat)
        cov_model = sch.ok ? Matrix(op.J_model * sch.cov_eta * op.J_model') : fill(NaN, length(op.model_names), length(op.model_names))
        se_model = [sch.ok ? sqrt(max(cov_model[i, i], 0.0)) : NaN for i in 1:size(cov_model, 1)]
        se_free_obs = [sch.ok ? sqrt(max(sch.cov_eta[i, i], 0.0)) : NaN for i in 1:d_xi]
        cond_var_eta = [sch.H_xx[i, i] > 1e-14 ? 1.0 / sch.H_xx[i, i] : NaN for i in 1:d_xi]
        cond_se_free = sqrt.(max.(cond_var_eta, 0.0))
        J_dense = Matrix(op.J_model)
        cond_se_model = [
            begin
                acc = 0.0; ok_c = true
                for c in 1:d_xi
                    J_dense[r, c] == 0.0 && continue
                    isnan(cond_var_eta[c]) && (ok_c = false; break)
                    acc += J_dense[r, c]^2 * cond_var_eta[c]
                end
                ok_c ? sqrt(acc) : NaN
            end for r in 1:size(J_dense, 1)
        ]

        pscores = _mrcml_person_scores_from_calibration(
            eta_hat, op, spec.people, spec.person, spec.group, spec.supports, spec.categories, spec.category, w;
            method = :jmle, jmle_theta = th_full, jmle_se = th_se_full,
        )

        ll_obs_neg = Float64(extreme_adjustment) > 0.0 ?
            _mrcml_jmle_nll_and_grad!(
                nothing, u_hat, op, interior_p, p_to_free, active_rows,
                spec.person, spec.group, spec.supports, spec.category, w, 0.0,
            ) : ll_neg
        ll = -ll_obs_neg
        max_grad = isempty(g_final) ? 0.0 : norm(g_final, Inf)
        conv = max_grad <= 1e-5
        stat_ok = conv && sch.ok && sch.cond_num <= 1e10

        n_mod = length(op.model_names)
        full_hat = vcat(th_full, xi_model_hat)
        full_names = vcat(["person[$(spec.people[p])]" for p in 1:P], op.model_names)
        free_names_all = vcat(["person[$(spec.people[p])]" for p in interior_p], op.free_names)

        J_lay = spzeros(Float64, P + n_mod, n_free)
        for (k, p) in enumerate(interior_p)
            J_lay[p, k] = 1.0
        end
        J_lay[(P + 1):(P + n_mod), (d_theta + 1):n_free] = op.J_model
        c_lay = vcat([p_to_free[p] > 0 ? 0.0 : th_full[p] for p in 1:P], op.xi0_model)
        f_mask = BitVector(vcat([p_to_free[p] == 0 for p in 1:P], [nm in op.fixed_model_names for nm in op.model_names]))
        lay = Layout(
            n_mod, 1:P, UnitRange{Int}[], UnitRange{Int}[], 1:d_theta, UnitRange{Int}[], UnitRange{Int}[],
            0, 0, n_free, c_lay, J_lay, free_names_all, full_names, f_mask, p_ext, interior_p, active_rows,
        )

        free_table = [
            (; index = i, parameter = op.free_names[i], estimate = eta_hat[i],
               se = se_free_obs[i], conditional_se = cond_se_free[i]) for i in 1:d_xi
        ]

        summary_nt = (;
            inference_paradigm = :frequentist,
            is_bayesian_posterior = false,
            source_kind = MRCML_FREQ_FIT_TAG,
            model = :mrcml,
            method = :jmle,
            n_observations = n,
            n_persons = P,
            n_patterns = op.n_patterns,
            n_facets = length(spec.facets),
            facet_names = [f.name for f in spec.facets],
            step_owner = spec.owner,
            noncenter_facet = :person,
            centering = :mrcml_design_matrix,
            n_free_parameters = n_free,
            n_structural_free = d_xi,
            loglikelihood = ll,
            deviance = -2.0 * ll,
            aic = missing,
            bic_persons = missing,
            bic_observations = missing,
            converged = conv,
            stationarity_qualified = stat_ok,
            max_abs_gradient = max_grad,
            hessian_positive_definite = sch.ok,
            min_hessian_eigenvalue = sch.min_eig,
            hessian_condition_number = sch.cond_num,
            n_iterations = nit_tot,
            n_evaluations = nfev_tot,
            elapsed_seconds = time() - t0,
            extreme_adjustment = Float64(extreme_adjustment),
            quadrature = missing,
            quad_points = missing,
            theta_lim = missing,
            population_mean = missing,
            population_sd = missing,
            population_mean_se = missing,
            population_sd_se = missing,
            estimate_mean = false,
            estimate_sd = false,
            mml_engine = missing,
            observation_binding = obs_bind,
        )
        warnings = [
            "JMLE estimates incidental person parameters jointly with MRCML structural parameters; point estimates carry Neyman-Scott finite-test expansion.",
        ]
        if hasproperty(spec.spec_record,:fixed_calibration)
            summary_nt = merge(summary_nt, (; fixed_calibration=deepcopy(spec.spec_record.fixed_calibration)))
            push!(warnings,"Standard errors are conditional on the supplied fixed calibration.")
        end
        ext_facets_jmle = _mrcml_extreme_facet_levels(spec)
        n_free_ext_jmle = count(x -> !x.fixed, ext_facets_jmle)
        n_free_ext_jmle > 0 && push!(warnings,
            "Extreme (all-minimum or all-maximum) free facet level(s) detected: $(n_free_ext_jmle); unlike FACETS two-stage extreme calibration, unpenalized MRCML JMLE does not automatically separate free extreme facet levels (inspect extreme_facet_levels).")
        diag_tabs_jmle = _mrcml_compute_diagnostics_and_tables(
            spec, prob, op, cat_labels_by_group,
            eta_hat, xi_model_hat, se_model, cond_se_model, nothing,
            pscores, w, ll, n_free, ext_facets_jmle;
            has_grouped_pop = false,
            extreme_adjusted = !separate_ext && any(s -> s in (:all_minimum, :all_maximum), p_ext),
            interval = Float64(interval),
            zstd_cap = cap_f,
            whexact = Bool(whexact),
        )
        core_body = (;
            schema = FIT_SCHEMA,
            summary = summary_nt,
            problem = prob,
            layout = lay,
            mrcml_operator = op,
            mrcml_category_labels = cat_labels_by_group,
            u_free = u_hat,
            eta_free = eta_hat,
            free_parameters = free_table,
            full_parameters = full_hat,
            gradient = g_final,
            full_se = vcat(th_se_full, se_model),
            covariance = (; offset = P, matrix = cov_model, free_covariance = sch.cov_eta),
            overall_fit = diag_tabs_jmle.overall_fit,
            person_scores = diag_tabs_jmle.person_scores,
            facet_measures = diag_tabs_jmle.facet_rows,
            step_measures = diag_tabs_jmle.step_rows,
            category_usage = diag_tabs_jmle.cat_rows,
            reliability = diag_tabs_jmle.reliability_rows,
            extreme_facet_levels = ext_facets_jmle,
            warnings,
        )
        digest = _frequentist_fit_digest(core_body)
        return Fit(merge(core_body, (; content_hash = digest)))
    end
end
