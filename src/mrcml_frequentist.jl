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

function _mrcml_mmle_nll_and_grad!(
        grad_out::Union{Nothing,Vector{Float64}},
        u_vec::AbstractVector{T},
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
        lsig_idx::Int, offset=op.c_pat) where {T<:Real}
    d_xi = size(op.A_free, 2)
    eta_xi = view(u_vec, 1:d_xi)
    mu = mu_idx > 0 ? u_vec[mu_idx] : T(mu_fixed)
    sigma = lsig_idx > 0 ? exp(u_vec[lsig_idx]) : T(sigma_fixed)
    !(isfinite(sigma) && 1e-8 <= sigma <= 1e4) && return T(Inf)

    # Precompute pattern shifts v_pat = c_pat + A_free * eta_xi
    M_tot = length(op.c_pat)
    v_pat = T.(offset)
    rows = rowvals(op.A_free)
    vals = nonzeros(op.A_free)
    @inbounds for col in 1:d_xi
        ec = eta_xi[col]
        ec == zero(T) && continue
        for ptr in nzrange(op.A_free, col)
            v_pat[rows[ptr]] += T(vals[ptr]) * ec
        end
    end

    Q = length(base_quad.std_nodes)
    log_w = [w > 0.0 ? log(w) : -Inf for w in base_quad.weights]
    ll_pq = zeros(T, P, Q)
    K_max = maximum(length, supports)
    lbuf = zeros(T, K_max)

    @inbounds for q in 1:Q
        log_w[q] == -Inf && continue
        th_q = mu + sigma * T(base_quad.std_nodes[q])
        for n in 1:op.n_obs
            pat = op.pattern_of_row[n]
            prng = op.pattern_ranges[pat]
            g = group[n]
            sup = supports[g]
            M_g = length(sup)
            for lk in 1:M_g
                m = prng[lk]
                lbuf[lk] = T(op.B_pat[m]) * th_q + v_pat[m]
            end
            # logsumexp over 1:M_g
            mmax = lbuf[1]
            for lk in 2:M_g
                lbuf[lk] > mmax && (mmax = lbuf[lk])
            end
            ssum = zero(T)
            for lk in 1:M_g
                ssum += exp(lbuf[lk] - mmax)
            end
            lse = mmax + log(ssum)
            yk_loc = category[n] - first(sup) + 1
            ll_pq[person_idx[n], q] += T(weights[n]) * (lbuf[yk_loc] - lse)
        end
    end

    total_ll = zero(T)
    post_w = grad_out !== nothing ? zeros(Float64, P, Q) : nothing
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
            lp_f = Float64(lp)
            for q in 1:Q
                post_w[p, q] = log_w[q] == -Inf ? 0.0 : exp(Float64(ll_pq[p, q]) + log_w[q] - lp_f)
            end
        end
    end

    if grad_out !== nothing
        r_pat = zeros(Float64, M_tot)
        g_mu = 0.0
        g_lsig = 0.0
        pbuf = zeros(Float64, K_max)
        vp_f = Float64.(v_pat)
        mu_f = Float64(mu)
        sig_f = Float64(sigma)

        @inbounds for q in 1:Q
            zq = base_quad.std_nodes[q]
            t_shift = sig_f * zq
            th_q = mu_f + t_shift
            for n in 1:op.n_obs
                pw = post_w[person_idx[n], q]
                pw == 0.0 && continue
                w_pw = weights[n] * pw
                pat = op.pattern_of_row[n]
                prng = op.pattern_ranges[pat]
                g = group[n]
                sup = supports[g]
                M_g = length(sup)
                mmax = -Inf
                for lk in 1:M_g
                    m = prng[lk]
                    val = op.B_pat[m] * th_q + vp_f[m]
                    pbuf[lk] = val
                    val > mmax && (mmax = val)
                end
                ssum = 0.0
                for lk in 1:M_g
                    e = exp(pbuf[lk] - mmax)
                    pbuf[lk] = e
                    ssum += e
                end
                inv_s = 1.0 / ssum
                yk_loc = category[n] - first(sup) + 1
                b_res = 0.0
                for lk in 1:M_g
                    m = prng[lk]
                    pk = pbuf[lk] * inv_s
                    rk = w_pw * ((lk == yk_loc ? 1.0 : 0.0) - pk)
                    r_pat[m] += rk
                    b_res += op.B_pat[m] * rk
                end
                g_mu += b_res
                g_lsig += b_res * t_shift
            end
        end

        fill!(grad_out, 0.0)
        # Negative log-likelihood gradient = -A_free' * r_pat
        @inbounds for col in 1:d_xi
            acc = 0.0
            for ptr in nzrange(op.A_free, col)
                acc += vals[ptr] * r_pat[rows[ptr]]
            end
            grad_out[col] = -acc
        end
        mu_idx > 0 && (grad_out[mu_idx] = -g_mu)
        lsig_idx > 0 && (grad_out[lsig_idx] = -g_lsig)
    end
    return -total_ll
end

function _mrcml_mmle_conditional_info(
        eta_xi::Vector{Float64},
        mu::Float64,
        sigma::Float64,
        op::B.AdditiveFacets.MRCMLOperator,
        P::Int,
        person_idx::Vector{Int},
        group::Vector{Int},
        supports::Vector{UnitRange{Int}},
        category::Vector{Int},
        weights::Vector{Float64},
        base_quad)
    # Computes the exact conditional M-step information matrix A' * W * A (whose diagonal
    # entries match TAM's `se.xsi = 1 / sqrt(diag(I_Mstep))` convention!).
    M_tot = length(op.c_pat)
    v_pat = copy(op.c_pat)
    mul!(v_pat, op.A_free, eta_xi, 1.0, 1.0)
    Q = length(base_quad.std_nodes)
    log_w = [w > 0.0 ? log(w) : -Inf for w in base_quad.weights]
    ll_pq = zeros(Float64, P, Q)
    K_max = maximum(length, supports)
    lbuf = zeros(Float64, K_max)

    for q in 1:Q
        log_w[q] == -Inf && continue
        th_q = mu + sigma * base_quad.std_nodes[q]
        for n in 1:op.n_obs
            prng = op.pattern_ranges[op.pattern_of_row[n]]
            sup = supports[group[n]]
            M_g = length(sup)
            mmax = -Inf
            for lk in 1:M_g
                m = prng[lk]
                v = op.B_pat[m] * th_q + v_pat[m]
                lbuf[lk] = v
                v > mmax && (mmax = v)
            end
            ssum = sum(exp(lbuf[lk] - mmax) for lk in 1:M_g)
            yk_loc = category[n] - first(sup) + 1
            ll_pq[person_idx[n], q] += weights[n] * (lbuf[yk_loc] - (mmax + log(ssum)))
        end
    end

    post_w = zeros(Float64, P, Q)
    for p in 1:P
        mval = maximum(ll_pq[p, q] + log_w[q] for q in 1:Q if log_w[q] > -Inf)
        s_exp = sum(exp(ll_pq[p, q] + log_w[q] - mval) for q in 1:Q if log_w[q] > -Inf)
        lp = mval + log(s_exp)
        for q in 1:Q
            post_w[p, q] = log_w[q] == -Inf ? 0.0 : exp(ll_pq[p, q] + log_w[q] - lp)
        end
    end

    # Accumulate M-step multinomial information I_cond = sum_{n,q} w_n * post_w[p,q] * Cov_p(A_u)
    d_xi = size(op.A_free, 2)
    I_cond = zeros(Float64, d_xi, d_xi)
    A_dense = Matrix(op.A_free)
    pvec = zeros(Float64, K_max)
    abar = zeros(Float64, d_xi)

    for q in 1:Q
        log_w[q] == -Inf && continue
        th_q = mu + sigma * base_quad.std_nodes[q]
        # Aggregate total posterior weight per pattern u at quadrature node q!
        pat_w = zeros(Float64, op.n_patterns)
        for n in 1:op.n_obs
            pat_w[op.pattern_of_row[n]] += weights[n] * post_w[person_idx[n], q]
        end
        for u in 1:op.n_patterns
            wu = pat_w[u]
            wu == 0.0 && continue
            prng = op.pattern_ranges[u]
            M_g = length(prng)
            mmax = -Inf
            for lk in 1:M_g
                m = prng[lk]
                v = op.B_pat[m] * th_q + v_pat[m]
                pvec[lk] = v
                v > mmax && (mmax = v)
            end
            ssum = 0.0
            for lk in 1:M_g
                e = exp(pvec[lk] - mmax)
                pvec[lk] = e
                ssum += e
            end
            pvec[1:M_g] ./= ssum
            fill!(abar, 0.0)
            for lk in 1:M_g
                pk = pvec[lk]
                m = prng[lk]
                @inbounds for c in 1:d_xi
                    abar[c] += pk * A_dense[m, c]
                end
            end
            for lk in 1:M_g
                w_pk = wu * pvec[lk]
                m = prng[lk]
                @inbounds for c1 in 1:d_xi
                    d1 = A_dense[m, c1] - abar[c1]
                    d1 == 0.0 && continue
                    for c2 in 1:d_xi
                        I_cond[c1, c2] += w_pk * d1 * (A_dense[m, c2] - abar[c2])
                    end
                end
            end
        end
    end
    return Symmetric(I_cond)
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
            push!(rows, (;
                person = people[p],
                n_ratings = obs_cnt,
                raw_score = raw_sum,
                extreme = ext,
                estimate = lim_est,
                limit_estimate = lim_est,
                se = lim_se,
                conditional_se = isfinite(lim_est) ? solve_person_wle_mle(p; wle = false)[2] : NaN,
                wle = wle_est,
                wle_se,
            ))
        end
    end
    return rows
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
        weights = nothing,
        maxit::Int = 500,
        gtol::Real = 1e-9)
    t0 = time()
    m = _normalize_method(method)
    pop = get(spec.spec_record,:population,nothing)
    if !isnothing(pop)
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

    if m === :jmle
        (estimate_mean || estimate_sd) &&
            throw(ArgumentError("estimate_mean / estimate_sd apply to method = :mmle only"))
        spec.allocation.conditional_joint_identified ||
            throw(ArgumentError("JMLE cannot identify free person abilities together with an unconstrained global location intercept in `A` (joint rank $(spec.allocation.conditional_joint_rank)/$(P + d_xi)); center facet columns or use `method = :mmle` with fixed `population_mean = 0`"))
    elseif estimate_mean && !spec.allocation.conditional_joint_identified
        throw(ArgumentError("MMLE with `estimate_mean = true` cannot identify `population_mean` when `A` already spans a global location intercept; set `estimate_mean = false` (TAM convention)"))
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
        sr = (last(br)+1):(last(br)+(isnothing(pop) ? 0 : length(pop.groups)))
        parts = isnothing(pop) ? nothing : _population_parts(spec,pop,w)
        isnothing(pop) || (n_free = last(sr))
        x0 = zeros(Float64, n_free)
        mu_idx > 0 && (x0[mu_idx] = Float64(population_mean))
        lsig_idx > 0 && (x0[lsig_idx] = log(Float64(population_sd)))

        function fg!(g,x,offset=op.c_pat)
            if isnothing(pop)
                return _mrcml_mmle_nll_and_grad!(g,x,op,P,spec.person,spec.group,spec.supports,
                    spec.category,w,base_quad,Float64(population_mean),Float64(population_sd),
                    mu_idx,lsig_idx,offset)
            end
            return _grouped_mmle!(g,x,parts,base_quad,br,sr,offset)
        end
        opt = _optimize_lbfgs(fg!, x0; maxit = Int(maxit), gtol = Float64(gtol))
        u_hat = copy(opt.x)

        # Exact Newton-Cholesky polish on the exact marginal log-likelihood Hessian!
        nll_only = x -> fg!(nothing,x)
        g_final = copy(opt.g)
        ll_neg = opt.f
        nit_tot = opt.nit
        nfev_tot = opt.nfev

        for _ in 1:6
            norm(g_final, Inf) <= 1e-11 && break
            H_pol = Symmetric(ForwardDiff.hessian(nll_only, u_hat))
            F_ch = cholesky(H_pol; check = false)
            issuccess(F_ch) || break
            dx = -(F_ch \ g_final)
            step = 1.0
            improved = false
            for _ in 1:20
                u_try = u_hat .+ step .* dx
                g_try = zeros(Float64, n_free)
                f_try = fg!(g_try, u_try)
                nfev_tot += 1
                if isfinite(f_try) && f_try <= ll_neg + 1e-12
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

        H_obs = n_free > 0 ? Symmetric(ForwardDiff.hessian(nll_only, u_hat)) : Symmetric(zeros(Float64, 0, 0))
        eigs = n_free > 0 ? eigvals(Matrix(H_obs)) : Float64[1.0]
        min_eig = minimum(eigs)
        max_eig = maximum(eigs)
        hess_pd = min_eig > 1e-10
        cond_num = hess_pd ? max_eig / min_eig : Inf
        cov_free = hess_pd && n_free > 0 ? Matrix(inv(H_obs)) : fill(NaN, n_free, n_free)

        eta_hat = u_hat[1:d_xi]
        mu_hat = mu_idx > 0 ? u_hat[mu_idx] : Float64(population_mean)
        sig_hat = lsig_idx > 0 ? exp(u_hat[lsig_idx]) : Float64(population_sd)
        mu_se = (mu_idx > 0 && hess_pd) ? sqrt(max(cov_free[mu_idx, mu_idx], 0.0)) : missing
        sig_se = (lsig_idx > 0 && hess_pd) ? sig_hat * sqrt(max(cov_free[lsig_idx, lsig_idx], 0.0)) : missing

        # Model-scale parameter vector & exact constrained observed-information SEs + TAM conditional M-step SEs!
        xi_model_hat = op.xi0_model .+ Vector{Float64}(op.J_model * eta_hat)
        cov_eta = d_xi > 0 ? cov_free[1:d_xi, 1:d_xi] : zeros(Float64, 0, 0)
        cov_model = Matrix(op.J_model * cov_eta * op.J_model')
        se_model = [hess_pd ? sqrt(max(cov_model[i, i], 0.0)) : NaN for i in 1:size(cov_model, 1)]
        se_free_obs = [hess_pd ? sqrt(max(cov_eta[i, i], 0.0)) : NaN for i in 1:d_xi]

        if isnothing(pop)
            I_cond = _mrcml_mmle_conditional_info(
                eta_hat, mu_hat, sig_hat, op, P, spec.person, spec.group, spec.supports, spec.category, w, base_quad,
            )
            quad_scaled = build_quadrature(quadrature, quad_points; sd = sig_hat, theta_lim = Float64(theta_lim))
            pscores = _mrcml_person_scores_from_calibration(
                eta_hat, op, spec.people, spec.person, spec.group, spec.supports, spec.categories, spec.category, w;
                method = :mmle, quad = quad_scaled, mu_hat, sigma_hat = sig_hat,
            )

        else
            I_cond,pscores = _grouped_calibration(spec,parts,eta_hat,u_hat[br],exp.(u_hat[sr]),base_quad)
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
                conditional_se = cond_se_free[i],
            ) for i in 1:d_xi
        ]
        facet_rows = NamedTuple[]
        step_rows = NamedTuple[]
        for i in 1:n_mod
            nm = op.model_names[i]
            row_nt = (;
                facet = :mrcml,
                parameter = nm,
                level = nm,
                estimate = xi_model_hat[i],
                se = se_model[i],
                conditional_se = cond_se_model[i],
                fixed = nm in op.fixed_model_names,
            )
            if startswith(nm, "steps[") || startswith(nm, "step_interaction[")
                push!(step_rows, row_nt)
            else
                push!(facet_rows, row_nt)
            end
        end
        cat_rows = [
            (; category = spec.categories[k], count = count(==(k), spec.category), proportion = count(==(k), spec.category) / n)
            for k in eachindex(spec.categories)
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
            summary_nt = merge(summary_nt,(;population=_grouped_summary(pop,u_hat,br,sr,cov_free),
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
                    ForwardDiff.gradient(u -> fg!(nothing,u,offset), eltype(d).(u_hat))
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
            covariance = (; offset = 0, matrix = cov_model, free_covariance = cov_free),
            overall_fit = (; loglikelihood = ll, deviance = -2.0 * ll, n_free_parameters = n_free),
            person_scores = pscores,
            facet_measures = facet_rows,
            step_measures = step_rows,
            category_usage = cat_rows,
            reliability = NamedTuple[],
            extreme_facet_levels = NamedTuple[],
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

        x0 = zeros(Float64, n_free)
        fg_j! = (g, x) -> _mrcml_jmle_nll_and_grad!(
            g, x, op, interior_p, p_to_free, active_rows, spec.person, spec.group,
            spec.supports, spec.category, w, Float64(extreme_adjustment),
        )
        opt = _optimize_lbfgs(fg_j!, x0; maxit = Int(maxit), gtol = Float64(gtol))
        u_hat = copy(opt.x)
        g_final = copy(opt.g)
        ll_neg = opt.f
        nit_tot = opt.nit
        nfev_tot = opt.nfev

        # Exact O(N + d_xi^3) Schur-complement Hessian & Newton polish!
        function compute_jmle_schur(x_vec::Vector{Float64})
            th_f = view(x_vec, 1:d_theta)
            et_f = view(x_vec, (d_theta + 1):n_free)
            vp = copy(op.c_pat)
            mul!(vp, op.A_free, et_f, 1.0, 1.0)
            D_th = zeros(Float64, d_theta)
            H_tx = zeros(Float64, d_theta, d_xi)
            H_xx = zeros(Float64, d_xi, d_xi)
            A_d = Matrix(op.A_free)
            K_max = maximum(length, spec.supports)
            pvec = zeros(Float64, K_max)
            abar = zeros(Float64, d_xi)

            for i in active_rows
                wn = w[i]
                fp = p_to_free[spec.person[i]]
                th = th_f[fp]
                prng = op.pattern_ranges[op.pattern_of_row[i]]
                M_g = length(prng)
                mmax = -Inf
                for lk in 1:M_g
                    m = prng[lk]
                    v = op.B_pat[m] * th + vp[m]
                    pvec[lk] = v
                    v > mmax && (mmax = v)
                end
                ssum = 0.0
                for lk in 1:M_g
                    e = exp(pvec[lk] - mmax)
                    pvec[lk] = e
                    ssum += e
                end
                pvec[1:M_g] ./= ssum
                bbar = sum(pvec[lk] * op.B_pat[prng[lk]] for lk in 1:M_g)
                fill!(abar, 0.0)
                for lk in 1:M_g
                    pk = pvec[lk]
                    m = prng[lk]
                    for c in 1:d_xi
                        abar[c] += pk * A_d[m, c]
                    end
                end
                for lk in 1:M_g
                    wp = wn * pvec[lk]
                    m = prng[lk]
                    db = op.B_pat[m] - bbar
                    D_th[fp] += wp * db^2
                    for c1 in 1:d_xi
                        da1 = A_d[m, c1] - abar[c1]
                        H_tx[fp, c1] += wp * db * da1
                        da1 == 0.0 && continue
                        for c2 in 1:d_xi
                            H_xx[c1, c2] += wp * da1 * (A_d[m, c2] - abar[c2])
                        end
                    end
                end
            end
            all(>(1e-12), D_th) || return (; ok = false, D_th, H_tx, H_xx, S_xx = Symmetric(H_xx), cov_eta = fill(NaN, d_xi, d_xi), min_eig = 0.0, cond_num = Inf)
            invD = 1.0 ./ D_th
            S_mat = Symmetric(H_xx .- H_tx' * (invD .* H_tx))
            eigs = d_xi > 0 ? eigvals(Matrix(S_mat)) : Float64[1.0]
            meig = minimum(eigs)
            xeig = maximum(eigs)
            ok = meig > 1e-10
            cov_e = ok && d_xi > 0 ? Matrix(inv(S_mat)) : fill(NaN, d_xi, d_xi)
            return (; ok, D_th, H_tx, H_xx, S_xx = S_mat, cov_eta = cov_e, min_eig = meig, cond_num = ok ? max(xeig, maximum(D_th)) / min(meig, minimum(D_th)) : Inf)
        end

        for _ in 1:8
            norm(g_final, Inf) <= 1e-11 && break
            sch = compute_jmle_schur(u_hat)
            sch.ok || break
            gt = view(g_final, 1:d_theta)
            gx = view(g_final, (d_theta + 1):n_free)
            invD = 1.0 ./ sch.D_th
            rhs_x = -(gx .- sch.H_tx' * (invD .* gt))
            dx_x = sch.cov_eta * rhs_x
            dx_t = -(invD .* (gt .+ sch.H_tx * dx_x))
            dx = vcat(dx_t, dx_x)
            step = 1.0
            improved = false
            for _ in 1:20
                u_try = u_hat .+ step .* dx
                g_try = zeros(Float64, n_free)
                f_try = fg_j!(g_try, u_try)
                nfev_tot += 1
                if isfinite(f_try) && f_try <= ll_neg + 1e-12
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

        ll = -ll_neg
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
        facet_rows = NamedTuple[]
        step_rows = NamedTuple[]
        for i in 1:n_mod
            nm = op.model_names[i]
            row_nt = (; facet = :mrcml, parameter = nm, level = nm, estimate = xi_model_hat[i],
                se = se_model[i], conditional_se = cond_se_model[i], fixed = nm in op.fixed_model_names)
            if startswith(nm, "steps[") || startswith(nm, "step_interaction[")
                push!(step_rows, row_nt)
            else
                push!(facet_rows, row_nt)
            end
        end
        cat_rows = [
            (; category = spec.categories[k], count = count(==(k), spec.category), proportion = count(==(k), spec.category) / n)
            for k in eachindex(spec.categories)
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
            overall_fit = (; loglikelihood = ll, deviance = -2.0 * ll, n_free_parameters = n_free),
            person_scores = pscores,
            facet_measures = facet_rows,
            step_measures = step_rows,
            category_usage = cat_rows,
            reliability = NamedTuple[],
            extreme_facet_levels = NamedTuple[],
            warnings,
        )
        digest = _frequentist_fit_digest(core_body)
        return Fit(merge(core_body, (; content_hash = digest)))
    end
end
