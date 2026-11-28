# With a fixed quadrature grid, Louis' missing-information term is the
# posterior covariance of each person's complete-data score across the nodes.
function _subtract_missing_information!(info, scores, posterior, meat=nothing)
    d, Q, P = size(scores)
    center = zeros(d)
    for p in 1:P
        per_person = view(scores, :, :, p)
        mul!(center, per_person, view(posterior,p,:))
        isnothing(meat) || BLAS.ger!(1.0,center,center,meat)
        for q in 1:Q
            a = sqrt(posterior[p,q])
            @inbounds for j in 1:d
                per_person[j,q] = a * (per_person[j,q] - center[j])
            end
        end
    end
    flat = reshape(scores, d, Q*P)
    mul!(info, flat, transpose(flat), -1.0, 1.0)
    return info
end

# On sparse panels a dense parameter × node × person cube can dwarf the data.
# Store node scores only for parameters occurring in each person's rows.
struct _SparsePersonScores
    by_person::Vector{Dict{Int,Vector{Float64}}}
    nodes::Int
end

function _person_score_storage(d,Q,P)
    d * Q * P <= 4_000_000 && return zeros(d,Q,P)
    return _SparsePersonScores([Dict{Int,Vector{Float64}}() for _ in 1:P], Q)
end

@inline function _add_node_score!(scores::Array, j,q,p,v)
    @inbounds scores[j,q,p] += v
end

@inline function _add_node_score!(scores::_SparsePersonScores, j,q,p,v)
    nodes = get!(scores.by_person[p],j) do
        zeros(scores.nodes)
    end
    @inbounds nodes[q] += v
end

function _subtract_missing_information!(info, scores::_SparsePersonScores, posterior, meat=nothing)
    for (p,group) in enumerate(scores.by_person)
        isempty(group) && continue
        cols = sort!(collect(keys(group)))
        centered = stack(group[c] for c in cols)
        weights = view(posterior,p,:)
        mean_score = transpose(centered) * weights
        if !isnothing(meat)
            meat[cols,cols] .+= mean_score * transpose(mean_score)
        end
        centered .-= transpose(mean_score)
        centered .*= sqrt.(weights)
        info[cols,cols] .-= transpose(centered) * centered
    end
    return info
end

function _marginal_and_weights!(post, ll, log_w)
    total = 0.0
    for p in axes(ll,1)
        hi = maximum(ll[p,q] + log_w[q] for q in eachindex(log_w))
        s = 0.0
        for q in eachindex(log_w)
            v = exp(ll[p,q] + log_w[q] - hi)
            post[p,q] = v
            s += v
        end
        total += hi + log(s)
        for q in eachindex(log_w)
            post[p,q] /= s
        end
    end
    return total
end

function _ordinal_louis(x, prob, lay, quad, sd, sc)
    mmle_nll_and_grad!(nothing, x, prob, lay, quad; fixed_sd=sd, scratch=sc)
    post = sc.post_w
    _marginal_and_weights!(post, sc.ll_pq, sc.log_w)
    P, Q = size(post)
    width = lay.n_full_structural
    has_mu = lay.mu_free_idx > 0
    has_sd = lay.log_sigma_free_idx > 0
    d = width + has_mu + has_sd
    sigma = has_sd ? exp(x[lay.log_sigma_free_idx]) : sd
    scores = _person_score_storage(d,Q,P)
    return _ordinal_information!(scores, prob, lay, quad, sc, post, sigma, width, has_mu, has_sd, d)
end

function _ordinal_information!(scores, prob, lay, quad, sc, post, sigma, width, has_mu, has_sd, d)
    Q = length(quad.std_nodes)
    H = zeros(d,d)
    K = maximum(length,prob.supports)
    pr, tail, k_tail = zeros(K), zeros(K), zeros(K)
    F = length(prob.facets)
    cols = zeros(Int,F + has_mu + has_sd)
    coeff = ones(length(cols))
    for f in 1:F
        coeff[f] = prob.facets[f].sign
    end
    has_mu && (cols[F+1] = width+1)
    has_sd && (cols[end] = d)
    # Compute the conditional covariance just once per pattern and node.
    # Linked lists avoid a separate heap allocation for every singleton pattern.
    head = zeros(Int,sc.n_patterns)
    after = similar(sc.pat_of_row)
    for r in reverse(eachindex(after))
        u = sc.pat_of_row[r]
        after[r], head[u] = head[u], r
    end
    @inbounds for u in eachindex(head)
        for f in 1:F
            cols[f] = sc.pat_facet_full[f,u]
        end
        steps = lay.step_full_ranges[sc.pat_group[u]]
        h = length(steps)
        for q in 1:Q
            weight = 0.0
            observed = 0.0
            r = head[u]
            while r != 0
                w = prob.weights[r] * post[prob.person_idx[r],q]
                weight += w
                observed += w * prob.score_k[r]
                r = after[r]
            end
            iszero(weight) && continue
            shift = sigma * quad.std_nodes[q]
            has_sd && (coeff[end] = shift)
            _row_probs!(view(pr,1:h+1), sc.pat_eta[u]+shift, view(sc.full_buf,steps))
            pt = kt = 0.0
            for k in h:-1:1
                pt += pr[k+1]
                kt += k * pr[k+1]
                tail[k], k_tail[k] = pt, kt
            end
            variance = 0.0
            for k in 0:h
                variance += pr[k+1] * (k - kt)^2
            end
            for a in eachindex(cols)
                ia = cols[a]
                for b in eachindex(cols)
                    H[cols[b],ia] += weight * variance * coeff[a] * coeff[b]
                end
                for k in 1:h
                    cross = -weight * coeff[a] * (k_tail[k] - kt * tail[k])
                    H[steps[k],ia] += cross
                    H[ia,steps[k]] += cross
                end
            end
            for k in 1:h, j in 1:h
                H[steps[j],steps[k]] += weight * (tail[max(j,k)] - tail[j]*tail[k])
            end
            has_sd && (H[d,d] -= shift * (observed - weight*kt))
            r = head[u]
            while r != 0
                p, y, w = prob.person_idx[r], prob.score_k[r], prob.weights[r]
                residual = w * (y-kt)
                for a in eachindex(cols)
                    _add_node_score!(scores,cols[a],q,p,residual * coeff[a])
                end
                for k in 1:h
                    _add_node_score!(scores,steps[k],q,p,w * (tail[k] - (y >= k)))
                end
                r = after[r]
            end
        end
    end
    _subtract_missing_information!(H, scores, post)
    pop_cols = filter(>(0), [lay.mu_free_idx, lay.log_sigma_free_idx])
    J = vcat(lay.J_mat, sparse(eachindex(pop_cols), pop_cols, ones(length(pop_cols)), length(pop_cols), lay.n_free))
    return Symmetric(Matrix(J' * H * J))
end

# Factor exp(k * eta - cumulative_step[k]) across nodes. Outside the safe
# exponent range use the general log-sum-exp kernel, including for AD inputs.
function _ordinal_scalar_mmle!(gradient, prob, lay, sc, sigma)
    K = length(sc.pbuf)
    h = K - 1
    max_location = maximum(abs, sc.pat_eta) + sigma * maximum(abs, sc.std_nodes)
    h * max_location <= 240 || return nothing
    cumulative = zeros(K, length(prob.supports))
    step_factor = ones(size(cumulative))
    for (g, steps) in enumerate(lay.step_full_ranges), (k, i) in enumerate(steps)
        v = cumulative[k,g] + sc.full_buf[i]
        abs(v) <= 240 || return nothing
        cumulative[k+1,g] = v
        step_factor[k+1,g] = exp(-v)
    end
    base = exp.(sc.pat_eta)
    shifts = sigma .* sc.std_nodes
    exp_shift = exp.(shifts)
    ll = fill!(sc.ll_pq, 0.0)
    @inbounds for q in eachindex(shifts)
        for r in eachindex(prob.person_idx)
            u, g, y = sc.pat_of_row[r], prob.step_group[r], prob.score_k[r]
            z = base[u] * exp_shift[q]
            power = denom = 1.0
            for k in 2:length(prob.supports[g])
                power *= z
                denom += power * step_factor[k,g]
            end
            logp = y * (sc.pat_eta[u] + shifts[q]) - cumulative[y+1,g] - log(denom)
            ll[prob.person_idx[r],q] += prob.weights[r] * logp
        end
    end
    post = sc.post_w
    total = _marginal_and_weights!(post,ll,sc.log_w)
    isnothing(gradient) && return -total
    gx = fill!(sc.g_full, 0.0)
    g_mu = g_sd = 0.0
    @inbounds for q in eachindex(shifts), r in eachindex(prob.person_idx)
        weight = prob.weights[r] * post[prob.person_idx[r],q]
        iszero(weight) && continue
        u, g, y = sc.pat_of_row[r], prob.step_group[r], prob.score_k[r]
        steps = lay.step_full_ranges[g]
        z = base[u] * exp_shift[q]
        power = denom = 1.0
        for k in eachindex(steps)
            power *= z
            sc.pbuf[k+1] = power * step_factor[k+1,g]
            denom += sc.pbuf[k+1]
        end
        tail = residual = 0.0
        for k in length(steps):-1:1
            tail += sc.pbuf[k+1] / denom
            delta = weight * (tail - (y >= k))
            gx[steps[k]] -= delta
            residual += delta
        end
        for f in eachindex(sc.facet_signs)
            gx[sc.pat_facet_full[f,u]] += sc.facet_signs[f] * residual
        end
        g_mu += residual
        g_sd += residual * shifts[q]
    end
    mul!(gradient, transpose(lay.J_mat), gx)
    lay.mu_free_idx > 0 && (gradient[lay.mu_free_idx] = g_mu)
    lay.log_sigma_free_idx > 0 && (gradient[lay.log_sigma_free_idx] = g_sd)
    return -total
end

# Coordinates absent throughout a pattern have zero conditional covariance.
# Subtracting the reference category also removes arbitrary common offsets.
function _pattern_derivatives(op)
    # Fixed calibrations may have many reported levels but very few free columns.
    free = size(op.A_free,2)
    use_free = size(op.A_model,2) > 2 * free
    J = use_free ? sparse(1.0I,free,free) : op.J_model
    At = sparse(transpose(use_free ? op.A_free : op.A_model))
    patterns = map(op.pattern_ranges) do rng
        cols = sort!(unique!([rowvals(At)[i] for r in rng for i in nzrange(At,r)]))
        A = zeros(length(cols), length(rng))
        for (k,r) in enumerate(rng), i in nzrange(At,r)
            A[searchsortedfirst(cols, rowvals(At)[i]), k] = nonzeros(At)[i]
        end
        A .-= A[:,1]
        (; cols, A)
    end
    return (; patterns, J)
end

function _mrcml_louis(u, op, person, owner, support, category, weights, quad,
                      mu_fixed, sd_fixed, mu_idx, sd_idx, sc, patterns; calibration=false)
    P, Q = size(sc.ll_pq)
    _mrcml_mmle_nll_and_grad!(nothing,u,op,P,person,owner,support,category,weights,
                              quad,mu_fixed,sd_fixed,mu_idx,sd_idx,op.c_pat,sc)
    post = sc.post_w
    _marginal_and_weights!(post, sc.ll_pq, sc.log_w)
    mu = mu_idx > 0 ? u[mu_idx] : mu_fixed
    sigma = sd_idx > 0 ? exp(u[sd_idx]) : sd_fixed
    structural = size(patterns.J,1)
    pop = filter(>(0), [mu_idx, sd_idx])
    d = structural + length(pop)
    scores = _person_score_storage(d,Q,P)
    return _mrcml_information!(scores,op,person,support,weights,quad,sc,patterns,post,mu,sigma,mu_idx,sd_idx,structural,pop,d,calibration)
end

function _mrcml_information!(scores,op,person,support,weights,quad,sc,patterns,post,mu,sigma,mu_idx,sd_idx,structural,pop,d,calibration)
    Q = length(quad.std_nodes)
    H = zeros(d,d)
    design = patterns.patterns
    width = maximum(length(p.cols) for p in design) + length(pop)
    K = maximum(length, support)
    cols = zeros(Int,width)
    centered = zeros(width,K)
    pr = zeros(K)
    means = zeros(width)
    rows = [Int[] for _ in design]
    for (r,pat) in enumerate(op.pattern_of_row)
        push!(rows[pat], r)
    end
    @inbounds for (i,pattern) in enumerate(design)
        isempty(rows[i]) && continue
        rng = op.pattern_ranges[i]
        n = length(pattern.cols)
        m = n + length(pop)
        cols[1:n] .= pattern.cols
        for j in eachindex(pop)
            cols[n+j] = structural+j
        end
        for q in 1:Q
            shift = sigma * quad.std_nodes[q]
            top = -Inf
            for (k,r) in enumerate(rng)
                v = sc.v_pat[r] + (mu+shift)*op.B_pat[r]
                pr[k] = v
                top = max(top,v)
                for a in 1:n
                    centered[a,k] = pattern.A[a,k]
                end
                b = op.B_pat[r] - op.B_pat[first(rng)]
                mu_idx > 0 && (centered[n+1,k] = b)
                sd_idx > 0 && (centered[m,k] = shift*b)
            end
            denom = 0.0
            for k in eachindex(rng)
                pr[k] = exp(pr[k]-top)
                denom += pr[k]
            end
            fill!(means,0.0)
            for k in eachindex(rng)
                pr[k] /= denom
                for a in 1:m
                    means[a] += pr[k]*centered[a,k]
                end
            end
            for k in eachindex(rng), a in 1:m
                centered[a,k] -= means[a]
            end
            total_weight = 0.0
            for r in rows[i]
                p = person[r]
                k = sc.obs_slot[r] - first(rng) + 1
                w = weights[r]
                posterior_weight = w*post[p,q]
                total_weight += posterior_weight
                for a in 1:m
                    _add_node_score!(scores,cols[a],q,p,w*centered[a,k])
                end
                sd_idx > 0 && (H[d,d] -= posterior_weight*centered[m,k])
            end
            for k in eachindex(rng), a in 1:m
                v = total_weight * pr[k] * centered[a,k]
                for b in 1:m
                    H[cols[b],cols[a]] += v*centered[b,k]
                end
            end
        end
    end
    J = blockdiag(patterns.J, sparse(I, length(pop), length(pop)))
    conditional = calibration ? Symmetric(patterns.J' * view(H,1:structural,1:structural) * patterns.J) : nothing
    meat = calibration ? zeros(d,d) : nothing
    _subtract_missing_information!(H, scores, post, meat)
    observed = Symmetric(Matrix(J' * H * J))
    return calibration ? (; observed, conditional, meat=Symmetric(J' * meat * J)) : observed
end

# For arbitrary structural designs with ordinal ability slopes, only the
# node multiplier changes between integrations of the same category offset.
function _mrcml_scalar_mmle!(gradient, op, person, weights, quad, mu, sigma,
                             mu_idx, sd_idx, sc)
    shifts = sigma .* quad.std_nodes
    nodes = mu .+ shifts
    maximum(length,op.pattern_ranges) * maximum(abs,nodes) <= 240 || return nothing
    multiplier = exp.(nodes)
    base, v = sc.prob_slot, sc.v_pat
    for rng in op.pattern_ranges, m in rng
        diff = v[m] - v[first(rng)]
        abs(diff) <= 240 || return nothing
        base[m] = exp(diff)
    end
    ll = fill!(sc.ll_pq,0.0)
    @inbounds for q in eachindex(nodes), r in eachindex(person)
        rng = op.pattern_ranges[op.pattern_of_row[r]]
        first_m = first(rng)
        y = sc.obs_slot[r]
        denom = power = 1.0
        for m in first_m+1:last(rng)
            power *= multiplier[q]
            denom += base[m]*power
        end
        ll[person[r],q] += weights[r]*((y-first_m)*nodes[q] + (v[y]-v[first_m]) - log(denom))
    end
    total = _marginal_and_weights!(sc.post_w,ll,sc.log_w)
    isnothing(gradient) && return -total
    residuals = fill!(sc.r_pat,0.0)
    g_mu = g_sd = 0.0
    @inbounds for q in eachindex(nodes), r in eachindex(person)
        w = weights[r] * sc.post_w[person[r],q]
        iszero(w) && continue
        rng = op.pattern_ranges[op.pattern_of_row[r]]
        first_m = first(rng)
        y = sc.obs_slot[r]
        power = denom = 1.0
        sc.logp_slot[first_m] = 1.0
        for m in first_m+1:last(rng)
            power *= multiplier[q]
            sc.logp_slot[m] = power * base[m]
            denom += sc.logp_slot[m]
        end
        residuals[y] += w
        residual_b = w * (y-first_m)
        for m in rng
            wk = w * (sc.logp_slot[m] / denom)
            residuals[m] -= wk
            residual_b -= (m-first_m)*wk
        end
        g_mu += residual_b
        g_sd += residual_b * shifts[q]
    end
    d = size(op.A_free,2)
    mul!(view(gradient,1:d), transpose(op.J_model), transpose(op.A_model) * residuals,-1.0,0.0)
    mu_idx > 0 && (gradient[mu_idx] = -g_mu)
    sd_idx > 0 && (gradient[sd_idx] = -g_sd)
    return -total
end
