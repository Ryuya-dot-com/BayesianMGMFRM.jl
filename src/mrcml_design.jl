# FF6a: Sparse Multidimensional Random Coefficients Multinomial Logit (MRCML)
# Design-Matrix Engine, Isometric Interaction/LLTM Compiler & TAM/ConQuest Bridge.
#
# Implements Adams, Wilson & Wang (1997) category log-weights:
#   ell_{n,k} = b_{u(n),k} * theta_{p(n)} + a_{u(n),k}' * eta_xi + c_{u(n),k}
# over compressed unique design patterns using SparseMatrixCSC, shared by
# Bayesian HMC/NUTS (analytic O(N*K + nnz(A)) reverse-mode gradients) and
# 1D frequentist MMLE / JMLE (`src/mrcml_frequentist.jl`).

const MRCML_SCHEMA = "bayesianmgmfrm.mrcml_design.v1"

struct MRCMLPriorBlock
    name::Symbol
    kind::Symbol              # :white_scaled, :mvnormal, :hierarchical_lognormal
    eta_range::UnitRange{Int}
    model_range::UnitRange{Int}
    raw_range::UnitRange{Int}
    hyper_idx::Int            # >0 for :hierarchical_lognormal, else 0
    mu::Vector{Float64}
    scale_vec::Vector{Float64}
    chol_L::Matrix{Float64}   # d x d for :mvnormal, else 0x0
    iso_factor::Float64       # sqrt(J/(J-1)) or Kronecker factor
    marginal_sd::Float64      # declared marginal SD when uniform, else NaN
    logmean::Float64
    logsd::Float64
end

struct MRCMLOperator
    n_obs::Int
    n_patterns::Int
    pattern_of_row::Vector{Int}
    pattern_ranges::Vector{UnitRange{Int}}
    pattern_group::Vector{Int}
    B_pat::Vector{Float64}
    c_pat::Vector{Float64}
    c0_pat::Vector{Float64}
    A_free::SparseMatrixCSC{Float64,Int}
    A_model::SparseMatrixCSC{Float64,Int}
    xi0_model::Vector{Float64}
    J_model::SparseMatrixCSC{Float64,Int}
    free_names::Vector{String}
    model_names::Vector{String}
    fixed_model_names::Set{String}
    block_meta::Vector{NamedTuple}
end

struct MRCMLTarget <: AbstractTarget
    table::Dict{Symbol,Vector}
    columns::NamedTuple
    person::Vector{Int}
    people::Vector{Any}
    category::Vector{Int}
    categories::Vector{Int}
    supports::Vector{UnitRange{Int}}
    facets::Vector{Block}
    owner::Symbol
    step_owner_spec::Any
    group::Vector{Int}
    group_levels::Vector{Any}
    person_sd::Float64
    person_hyper_idx::Int
    person_logmean::Float64
    person_logsd::Float64
    operator::MRCMLOperator
    prior_blocks::Vector{MRCMLPriorBlock}
    dimension::Int
    location_mode::Symbol      # :finite_connected or :zero_mean_population
    allocation::NamedTuple
    prior_symmetry::NamedTuple
    groups::NamedTuple
    spec_record::NamedTuple
end

"""
Prior-free MRCML specification accepted by `fit(spec; method = :mmle | :jmle, ...)`
and Layer-1 / Layer-2 design inspection verbs (`design_summary`, `validate_design`,
`contract`, `getdesign`, `MRCML.design_matrices`, `MRCML.to_tam`).
"""
struct MRCMLSpec
    table::Dict{Symbol,Vector}
    columns::NamedTuple
    person::Vector{Int}
    people::Vector{Any}
    category::Vector{Int}
    categories::Vector{Int}
    supports::Vector{UnitRange{Int}}
    facets::Vector{NamedTuple}
    owner::Symbol
    step_owner_spec::Any
    group::Vector{Int}
    group_levels::Vector{Any}
    operator::MRCMLOperator
    location_mode::Symbol
    allocation::NamedTuple
    groups::NamedTuple
    spec_record::NamedTuple
end

# ---------------------------------------------------------------------------
# 1. Isometric Zero-Sum Bases & Subspace Prior Invariance Helpers
# ---------------------------------------------------------------------------

function _helmert_matrix(J::Int)
    J >= 1 || throw(ArgumentError("basis level count J must be >= 1; got $J"))
    C = zeros(Float64, J, max(J - 1, 0))
    for k in 1:(J - 1)
        inv_norm = 1.0 / sqrt(Float64(k) * Float64(k + 1))
        for i in 1:k
            C[i, k] = inv_norm
        end
        C[k + 1, k] = -Float64(k) * inv_norm
    end
    return C
end

function _kronecker_helmert_matrix(J1::Int, J2::Int)
    C1 = _helmert_matrix(J1)
    C2 = _helmert_matrix(J2)
    return kron(C1, C2)
end

function _subspace_isometric_prior(M::AbstractMatrix{<:Real}, sd::Real)
    sd isa Real && !(sd isa Bool) && isfinite(sd) && sd > 0 ||
        throw(ArgumentError("sd must be a finite positive real number"))
    J, d = size(M)
    J >= 2 && 1 <= d <= J ||
        throw(ArgumentError("basis matrix M must have size (J, d) with J >= 2 and 1 <= d <= J; got ($J, $d)"))
    Mf = Float64.(M)
    all(isfinite, Mf) || throw(ArgumentError("basis matrix M must contain finite entries"))
    G = Symmetric(Mf' * Mf)
    eig = eigen(G)
    minimum(eig.values) > max(J, d) * eps(Float64) * max(maximum(eig.values), 1.0) ||
        throw(ArgumentError("basis matrix M is column rank-deficient; supply linearly independent columns"))
    # Project onto span(M): M * (M'M)^{-1} * M' is the orthogonal projector P_M of trace d.
    # For exchangeable zero-sum subspaces (P_M = I_J - (1/J) 1 1'), diag(P_M) = d / J,
    # so Sigma_eta = sd^2 * (J / d) * (M'M)^{-1} gives exact marginal SD = sd for every row!
    Sigma = (Float64(sd)^2 * (Float64(J) / Float64(d))) .* Symmetric(inv(Matrix(G)))
    return D.MvNormal(zeros(Float64, d), Sigma)
end

# ---------------------------------------------------------------------------
# 2. Compressed Pattern Deduplication & Rank / Prior-Symmetry Auditing
# ---------------------------------------------------------------------------

function _compress_mrcml_patterns(
        n_obs::Int,
        group::Vector{Int},
        supports::Vector{UnitRange{Int}},
        row_B::Vector{Vector{Float64}},
        row_c0::Vector{Vector{Float64}},
        row_A_model_entries::Vector{Vector{Tuple{Int,Int,Float64}}},
        n_model::Int,
        xi0_model::Vector{Float64},
        J_model::SparseMatrixCSC{Float64,Int},
        free_names::Vector{String},
        model_names::Vector{String},
        fixed_model_names::Set{String},
        block_meta::Vector{NamedTuple})
    length(xi0_model) == n_model && size(J_model, 1) == n_model ||
        throw(DimensionMismatch("xi0_model / J_model row dimension mismatch with n_model = $n_model"))

    pat_lookup = Dict{Any,Int}()
    pattern_of_row = Vector{Int}(undef, n_obs)
    pattern_ranges = UnitRange{Int}[]
    pattern_group = Int[]
    B_pat = Float64[]
    c0_pat = Float64[]
    rows_A = Int[]
    cols_A = Int[]
    vals_A = Float64[]
    slot_offset = 0

    for n in 1:n_obs
        g = group[n]
        M_g = length(supports[g])
        b_vec = row_B[n]
        c_vec = row_c0[n]
        ents = sort!(copy(row_A_model_entries[n]))
        # Canonicalize duplicate (local_k, col) entries within row n before hashing
        merged = Tuple{Int,Int,Float64}[]
        for (lk, col, val) in ents
            val == 0.0 && continue
            if !isempty(merged) && merged[end][1] == lk && merged[end][2] == col
                prev = merged[end]
                nv = prev[3] + val
                if nv == 0.0
                    pop!(merged)
                else
                    merged[end] = (lk, col, nv)
                end
            else
                push!(merged, (lk, col, val))
            end
        end
        key = (g, Tuple(b_vec), Tuple(c_vec), Tuple(merged))
        u = get(pat_lookup, key, 0)
        if u == 0
            u = length(pattern_ranges) + 1
            pat_lookup[key] = u
            rng = (slot_offset + 1):(slot_offset + M_g)
            push!(pattern_ranges, rng)
            push!(pattern_group, g)
            append!(B_pat, b_vec)
            append!(c0_pat, c_vec)
            for (lk, col, val) in merged
                1 <= lk <= M_g || throw(ArgumentError("local category slot $lk outside 1:$M_g"))
                1 <= col <= n_model || throw(ArgumentError("model column $col outside 1:$n_model"))
                push!(rows_A, slot_offset + lk)
                push!(cols_A, col)
                push!(vals_A, val)
            end
            slot_offset += M_g
        end
        pattern_of_row[n] = u
    end

    M_tot = slot_offset
    A_model = sparse(rows_A, cols_A, vals_A, M_tot, n_model)
    dropzeros!(A_model)
    A_free = A_model * J_model
    dropzeros!(A_free)
    c_pat = c0_pat .+ Vector{Float64}(A_model * xi0_model)

    return MRCMLOperator(
        n_obs,
        length(pattern_ranges),
        pattern_of_row,
        pattern_ranges,
        pattern_group,
        B_pat,
        c_pat,
        c0_pat,
        A_free,
        A_model,
        copy(xi0_model),
        J_model,
        copy(free_names),
        copy(model_names),
        copy(fixed_model_names),
        deepcopy(block_meta),
    )
end

function _mrcml_spqr_rank(M::SparseMatrixCSC{Float64,Int}, col_names::Vector{String})
    m, n = size(M)
    if n == 0
        return (; rank = 0, columns = 0, full_rank = true, tolerance = 0.0,
            smallest_to_largest_R_diag = 1.0, near_dependence = false, dependent_columns = String[])
    end
    m == 0 && return (; rank = 0, columns = n, full_rank = false, tolerance = 0.0,
        smallest_to_largest_R_diag = 0.0, near_dependence = true, dependent_columns = copy(col_names))

    col_norms = sqrt.(vec(sum(abs2, M; dims = 1)))
    zero_cols = [col_names[j] for j in 1:n if col_norms[j] == 0.0]
    max_norm = maximum(col_norms)
    if max_norm == 0.0
        return (; rank = 0, columns = n, full_rank = false, tolerance = 0.0,
            smallest_to_largest_R_diag = 0.0, near_dependence = true, dependent_columns = copy(col_names))
    end
    # Normalize non-zero columns to unit norm for scale-invariant SPQR rank detection (`C7`-safe)
    inv_scales = [cn > 0.0 ? 1.0 / cn : 1.0 for cn in col_norms]
    Mn = M * spdiagm(0 => inv_scales)
    tol = 20.0 * max(m, n) * eps(Float64)
    F = qr(Mn; tol = tol)
    r = rank(F)
    d = abs.(diag(F.R))
    pos = d[d .> tol]
    ratio = isempty(pos) ? 0.0 : minimum(pos) / maximum(pos)
    dep = if r == n && isempty(zero_cols)
        String[]
    else
        perm = hasproperty(F, :pcol) ? F.pcol : collect(1:n)
        unique(vcat(zero_cols, [col_names[perm[j]] for j in (r + 1):length(perm)]))
    end
    return (;
        rank = r,
        columns = n,
        full_rank = (r == n && isempty(zero_cols)),
        tolerance = tol,
        smallest_to_largest_R_diag = ratio,
        near_dependence = ratio < sqrt(eps(Float64)) || r < n,
        dependent_columns = dep,
    )
end

function _mrcml_allocation(
        person::Vector{Int},
        people::Vector{Any},
        facets_meta::AbstractVector,
        op::MRCMLOperator,
        location_mode::Symbol;
        n_hyper::Int = 0,
        external_columns::UnitRange{Int} = 1:0,
        unreplicated_hyper::Vector{Symbol} = Symbol[])
    P = length(people)
    d_xi = size(op.A_free, 2)
    missing_levels = String[]
    obs_p = Set(person)
    for (j, x) in enumerate(people)
        j in obs_p || push!(missing_levels, "person[$(repr(x))]")
    end
    for b in facets_meta
        obs_f = Set(b.index)
        for (j, x) in enumerate(b.levels)
            j in obs_f || push!(missing_levels, "$(b.name)[$(repr(x))]")
        end
    end

    # Build sparse category-contrast Jacobian rows (slot m_k minus baseline slot m_1 for k >= 2)
    # 1) Structural contrast matrix across observed patterns (for zero-mean MML / population check)
    s_rows = Int[]
    s_cols = Int[]
    s_vals = Float64[]
    obs_patterns = sort!(unique(op.pattern_of_row))
    s_row_idx = 0
    # Pre-index rows of A_free via transpose for O(nnz) extraction
    At = sparse(op.A_free')
    rv = rowvals(At)
    nz = nonzeros(At)
    for u in obs_patterns
        rng = op.pattern_ranges[u]
        m1 = first(rng)
        for m in rng[2:end]
            s_row_idx += 1
            # Add +A_free[m, :] - A_free[m1, :]
            for ptr in nzrange(At, m)
                push!(s_rows, s_row_idx); push!(s_cols, rv[ptr]); push!(s_vals, nz[ptr])
            end
            for ptr in nzrange(At, m1)
                push!(s_rows, s_row_idx); push!(s_cols, rv[ptr]); push!(s_vals, -nz[ptr])
            end
        end
    end
    M_struct = sparse(s_rows, s_cols, s_vals, s_row_idx, d_xi)
    dropzeros!(M_struct)
    struct_audit = _mrcml_spqr_rank(M_struct, op.free_names)

    # 2) Full conditional person + structural contrast matrix across all N observations
    j_rows = Int[]
    j_cols = Int[]
    j_vals = Float64[]
    j_row_idx = 0
    for n in 1:op.n_obs
        u = op.pattern_of_row[n]
        rng = op.pattern_ranges[u]
        m1 = first(rng)
        b1 = op.B_pat[m1]
        p = person[n]
        for m in rng[2:end]
            j_row_idx += 1
            db = op.B_pat[m] - b1
            if db != 0.0
                push!(j_rows, j_row_idx); push!(j_cols, p); push!(j_vals, db)
            end
            for ptr in nzrange(At, m)
                push!(j_rows, j_row_idx); push!(j_cols, P + rv[ptr]); push!(j_vals, nz[ptr])
            end
            for ptr in nzrange(At, m1)
                push!(j_rows, j_row_idx); push!(j_cols, P + rv[ptr]); push!(j_vals, -nz[ptr])
            end
        end
    end
    joint_names = vcat(["person[$(repr(x))]" for x in people], op.free_names)
    M_joint = sparse(j_rows, j_cols, j_vals, j_row_idx, P + d_xi)
    dropzeros!(M_joint)
    joint_audit = _mrcml_spqr_rank(M_joint, joint_names)

    receiving_rank = (structural=struct_audit.rank, conditional_joint=joint_audit.rank)
    if !isempty(external_columns)
        # A full-rank, independent external calibration identifies its own directions.
        E = sparse(1:length(external_columns), collect(external_columns), ones(length(external_columns)),
                   length(external_columns), d_xi)
        struct_audit = _mrcml_spqr_rank(vcat(M_struct,E), op.free_names)
        joint_audit = _mrcml_spqr_rank(vcat(M_joint,hcat(spzeros(size(E,1),P),E)), joint_names)
    end

    # Determine identifiability under declared location_mode
    reasons = String[]
    !isempty(missing_levels) && push!(reasons, "Declared levels have no observations: $(missing_levels).")
    !isempty(unreplicated_hyper) && push!(reasons, "Hierarchical SD block has no replication: $(unreplicated_hyper).")
    if !struct_audit.full_rank
        push!(reasons, "Structural design matrix A is column rank-deficient ($(struct_audit.rank)/$(d_xi)); aliased columns: $(struct_audit.dependent_columns). Silent QR column-dropping is refused because dropping columns changes the Bayesian prior.")
    end
    if location_mode === :finite_connected
        if !joint_audit.full_rank
            push!(reasons, "Joint person + structural design is rank-deficient or disconnected ($(joint_audit.rank)/$(P + d_xi)); aliased columns: $(joint_audit.dependent_columns).")
        end
    elseif location_mode === :zero_mean_population
        # Allow at most the 1D global ability-intercept shift between zero-mean person prior and unconstrained item difficulties
        min_required = P + d_xi - 1
        if joint_audit.rank < min_required
            push!(reasons, "Person-incidence graph has disconnected components or extra aliases beyond the 1D population-mean origin ($(joint_audit.rank) < $(min_required)); aliased columns: $(joint_audit.dependent_columns).")
        end
    else
        throw(ArgumentError("unknown location_mode $(repr(location_mode))"))
    end

    identified = isempty(reasons)
    eff_rank = (location_mode === :zero_mean_population && identified ? P + d_xi : joint_audit.rank) + n_hyper
    total_cols = P + d_xi + n_hyper
    return (;
        (isempty(external_columns) ? (;) : (;receiving_rank, external_calibration_rank=length(external_columns)))...,
        identified,
        passed = identified,
        location_mode,
        rank = eff_rank,
        columns = total_cols,
        structural_rank = struct_audit.rank,
        structural_columns = d_xi,
        structural_identified = struct_audit.full_rank && isempty(missing_levels),
        conditional_joint_rank = joint_audit.rank,
        conditional_joint_columns = P + d_xi,
        conditional_joint_identified = joint_audit.full_rank && isempty(missing_levels),
        method = :sparse_spqr_mrcml_contrast_jacobian,
        tolerance = max(struct_audit.tolerance, joint_audit.tolerance),
        smallest_to_largest_retained_R_diagonal = min(struct_audit.smallest_to_largest_R_diag, joint_audit.smallest_to_largest_R_diag),
        near_dependence = struct_audit.near_dependence || (location_mode === :finite_connected && joint_audit.near_dependence),
        dependent_structural_columns = struct_audit.dependent_columns,
        dependent_reference_columns = location_mode === :finite_connected ? joint_audit.dependent_columns : struct_audit.dependent_columns,
        missing_levels,
        unreplicated_hyper,
        reasons,
        stored_design_nonzeros = nnz(op.A_free),
    )
end

function _mrcml_prior_covariance(op::MRCMLOperator, blocks::Vector{MRCMLPriorBlock})
    d_xi = size(op.A_free, 2)
    Sigma = zeros(Float64, d_xi, d_xi)
    for b in blocks
        rng = b.eta_range
        isempty(rng) && continue
        if b.kind === :white_scaled
            for (k, idx) in enumerate(rng)
                Sigma[idx, idx] = b.scale_vec[k]^2
            end
        elseif b.kind === :mvnormal
            Sigma[rng, rng] .= b.chol_L * b.chol_L'
        elseif b.kind === :hierarchical_lognormal
            # Use prior median SD exp(logmean) * iso_factor for baseline prior-symmetry geometry check
            s_med = exp(b.logmean) * b.iso_factor
            for idx in rng
                Sigma[idx, idx] = s_med^2
            end
        end
    end
    return Sigma
end

function _mrcml_audit_prior_symmetry(op::MRCMLOperator, blocks::Vector{MRCMLPriorBlock})
    d_xi = size(op.A_free, 2)
    if d_xi == 0
        return (; prior_asymmetry_detected = false, max_to_min_variance_ratio = 1.0,
            block_audits = NamedTuple[], pattern_step1_variances = Float64[], warnings = String[])
    end
    Sigma_eta = _mrcml_prior_covariance(op, blocks)
    Sigma_model = Matrix(op.J_model * Sigma_eta * op.J_model')
    model_vars = [max(Sigma_model[i, i], 0.0) for i in 1:size(Sigma_model, 1)]

    block_audits = NamedTuple[]
    warnings = String[]
    max_ratio = 1.0
    asym_detected = false

    for bm in op.block_meta
        mrng = bm.model_range
        isempty(mrng) && continue
        # Exclude structurally fixed coordinates when checking exchangeable variance balance
        active_vars = [model_vars[i] for i in mrng if !(op.model_names[i] in op.fixed_model_names) && model_vars[i] > 0.0]
        length(active_vars) <= 1 && continue
        vmin, vmax = extrema(active_vars)
        ratio = vmin > 0.0 ? vmax / vmin : Inf
        check_sym = get(bm, :check_exchangeable_symmetry, true)
        is_asym = check_sym && ratio > 1.0 + 1e-7
        if is_asym
            asym_detected = true
            max_ratio = max(max_ratio, ratio)
            push!(warnings,
                "[prior_variance_asymmetry] block $(repr(bm.name)) induces unequal marginal prior variances across levels (min = $(round(vmin, sigdigits=5)), max = $(round(vmax, sigdigits=5)), max/min ratio = $(round(ratio, sigdigits=5))). Non-orthogonal sum-to-zero codings (such as TAM's last-level -1 substitution under i.i.d. priors) inflate the omitted level's prior variance by (J - 1)x; use Layer-1 isometric bases or `MRCML.subspace_isometric_prior(M, sd)` when exchangeability is intended.")
        end
        push!(block_audits, (;
            block = bm.name,
            kind = bm.kind,
            n_active_levels = length(active_vars),
            min_marginal_variance = vmin,
            max_marginal_variance = vmax,
            max_to_min_variance_ratio = ratio,
            asymmetric = is_asym,
        ))
    end

    # Also audit pattern-level step-1 linear-predictor variance across observed patterns
    # (catches raw custom `A` imports where J_model = I without explicit facet block expansion!)
    pat_vars = Float64[]
    for u in 1:op.n_patterns
        rng = op.pattern_ranges[u]
        length(rng) >= 2 || continue
        a_diff = Vector(op.A_free[rng[2], :] .- op.A_free[rng[1], :])
        v = dot(a_diff, Sigma_eta * a_diff)
        push!(pat_vars, max(v, 0.0))
    end
    pos_pat = filter(>(1e-14), pat_vars)
    if isempty(op.block_meta) && length(pos_pat) >= 2
        pmin, pmax = extrema(pos_pat)
        pratio = pmax / pmin
        if pratio > 1.0 + 1e-7
            asym_detected = true
            max_ratio = max(max_ratio, pratio)
            push!(warnings,
                "[prior_variance_asymmetry] custom design matrix `A` induces unequal category-1 prior variances across generalized items/patterns (min = $(round(pmin, sigdigits=5)), max = $(round(pmax, sigdigits=5)), max/min ratio = $(round(pratio, sigdigits=5))). Verify whether non-orthogonal sum-to-zero coding (e.g. TAM last-level -1 rows) is distorting level exchangeability.")
        end
    end

    return (;
        prior_asymmetry_detected = asym_detected,
        max_to_min_variance_ratio = max_ratio,
        block_audits,
        pattern_step1_variances = pat_vars,
        warnings,
    )
end

# ---------------------------------------------------------------------------
# 3. Forward Coordinates, Log-Density & Exact Sparse Adjoint Gradient
# ---------------------------------------------------------------------------

function _mrcml_unpack(t::MRCMLTarget, q::AbstractVector{<:Real})
    _check(t, q)
    Z = promote_type(Float64, eltype(q))
    P = length(t.people)
    s_p = t.person_hyper_idx == 0 ? Z(t.person_sd) : exp(t.person_logmean + t.person_logsd * q[t.person_hyper_idx])
    isfinite(s_p) && s_p > 0 || throw(ArgumentError("unrepresentable person population SD"))
    person = s_p .* q[1:P]
    lv = P * log(s_p)
    pop = get(t.spec_record,:population,nothing)
    pop_values = if !isnothing(pop)
        cp, sp = pop.coefficient_prior, pop.sd_prior
        beta = cp.mean .+ cp.sd .* q[pop.beta]
        sd = exp.(sp.logmean .+ sp.logsd .* q[pop.logsd])
        all(x -> isfinite(x) && x > 0, sd) || throw(ArgumentError("unrepresentable group SD"))
        person .= pop.X * beta .+ sd[pop.group_index] .* view(q,1:P)
        lv = sum(log,sd[pop.group_index]) + length(beta)*log(cp.sd) +
             length(sd)*log(sp.logsd) + sum(log,sd)
        (;coefficients=beta, group_sd=sd)
    else
        nothing
    end
    t.person_hyper_idx == 0 || (lv += log(Z(t.person_logsd)) + log(s_p))

    d_xi = size(t.operator.A_free, 2)
    eta_xi = Vector{Z}(undef, d_xi)
    hyper_sds = Dict{Symbol,Z}()
    t.person_hyper_idx == 0 || (hyper_sds[:person] = s_p)

    for b in t.prior_blocks
        erng = b.eta_range
        rrng = b.raw_range
        if b.kind === :white_scaled
            for (k, ei) in enumerate(erng)
                sc = b.scale_vec[k]
                eta_xi[ei] = Z(b.mu[k]) + Z(sc) * q[rrng[k]]
                lv += log(Z(sc))
            end
        elseif b.kind === :mvnormal
            qv = view(q, rrng)
            d_b = length(erng)
            for r in 1:d_b
                acc = Z(b.mu[r])
                @inbounds for c in 1:r
                    acc += Z(b.chol_L[r, c]) * qv[c]
                end
                eta_xi[erng[r]] = acc
                lv += log(Z(b.chol_L[r, r]))
            end
        elseif b.kind === :hierarchical_lognormal
            sig = exp(b.logmean + b.logsd * q[b.hyper_idx])
            isfinite(sig) && sig > 0 || throw(ArgumentError("unrepresentable hierarchical SD for $(b.name)"))
            hyper_sds[b.name] = sig
            eff_s = sig * Z(b.iso_factor)
            for (k, ei) in enumerate(erng)
                eta_xi[ei] = eff_s * q[rrng[k]]
            end
            lv += length(erng) * log(eff_s) + log(Z(b.logsd)) + log(sig)
        else
            throw(ArgumentError("unsupported MRCMLPriorBlock kind $(repr(b.kind))"))
        end
    end
    xi_model = Z.(t.operator.xi0_model) .+ (t.operator.J_model * eta_xi)
    return (; person, person_sd = s_p, eta_xi, xi_model, hyper_sds, log_volume = lv, population=pop_values)
end

function coordinates(t::MRCMLTarget, q::AbstractVector{<:Real})
    u = _mrcml_unpack(t, q)
    blocks = Dict{Symbol,Any}()
    for bm in t.operator.block_meta
        blocks[bm.name] = u.xi_model[bm.model_range]
    end
    return (;
        person = u.person,
        (isnothing(u.population) ? (;) : (;population=u.population))...,
        structural_free = u.eta_xi,
        structural_model = u.xi_model,
        blocks,
        hyper_sds = u.hyper_sds,
        log_volume = u.log_volume,
        measure = :white_standard_normal_with_explicit_block_jacobians,
    )
end

function representable_scales(t::MRCMLTarget, q)
    if hasproperty(t.spec_record,:population)
        p = t.spec_record.population
        all(i -> (s=exp(p.sd_prior.logmean + p.sd_prior.logsd*q[i]); isfinite(s) && s>0), p.logsd) || return false
    end
    if t.person_hyper_idx > 0
        sp = exp(t.person_logmean + t.person_logsd * q[t.person_hyper_idx])
        (isfinite(sp) && sp > 0) || return false
    end
    for b in t.prior_blocks
        if b.kind === :hierarchical_lognormal
            sb = exp(b.logmean + b.logsd * q[b.hyper_idx])
            (isfinite(sb) && sb > 0) || return false
        end
    end
    return true
end

function _mrcml_pattern_shifts(op::MRCMLOperator, eta_xi::AbstractVector{Z}) where {Z}
    v_pat = Z.(op.c_pat)
    rows = rowvals(op.A_free)
    vals = nonzeros(op.A_free)
    @inbounds for col in 1:size(op.A_free, 2)
        ec = eta_xi[col]
        ec == zero(Z) && continue
        for ptr in nzrange(op.A_free, col)
            v_pat[rows[ptr]] += Z(vals[ptr]) * ec
        end
    end
    return v_pat
end

function _weights!(a, t::MRCMLTarget, v_unpack, n::Int, v_pat = nothing)
    op = t.operator
    Z = eltype(v_unpack.person)
    vp = v_pat === nothing ? _mrcml_pattern_shifts(op, v_unpack.eta_xi) : v_pat
    u = op.pattern_of_row[n]
    prng = op.pattern_ranges[u]
    g = t.group[n]
    sup = t.supports[g]
    th = v_unpack.person[t.person[n]]
    fill!(a, oftype(th, -Inf))
    @inbounds for (lk, k) in enumerate(sup)
        m = prng[lk]
        a[k] = Z(op.B_pat[m]) * th + vp[m]
    end
    return B._logsumexp(a)
end

function logprobs(t::MRCMLTarget, q::AbstractVector{<:Real})
    u = _mrcml_unpack(t, q)
    vp = _mrcml_pattern_shifts(t.operator, u.eta_xi)
    Z = eltype(u.person)
    out = Matrix{Z}(undef, length(t.person), length(t.categories))
    for n in eachindex(t.person)
        a = view(out, n, :)
        c = _weights!(a, t, u, n, vp)
        a .-= c
    end
    all(n -> all(isfinite, view(out, n, t.supports[t.group[n]])), eachindex(t.person)) ||
        throw(ArgumentError("unrepresentable category log probabilities in MRCMLTarget"))
    return out
end

function L.logdensity(t::MRCMLTarget, q::AbstractVector{<:Real})
    _check(t, q; finite = false)
    Z = promote_type(Float64, eltype(q))
    all(isfinite, q) && representable_scales(t, q) || return -Z(Inf)
    u = _mrcml_unpack(t, q)
    vp = _mrcml_pattern_shifts(t.operator, u.eta_xi)
    a = Vector{Z}(undef, length(t.categories))
    lp = logprior(t, q)
    for n in eachindex(t.person)
        c = _weights!(a, t, u, n, vp)
        lp += a[t.category[n]] - c
    end
    return isfinite(lp) ? lp : -Z(Inf)
end

function L.logdensity_and_gradient(t::MRCMLTarget, q::AbstractVector{<:Real})
    _check(t, q; finite = false)
    Z = promote_type(Float64, eltype(q))
    rejected() = (-Z(Inf), fill(Z(NaN), length(q)))
    all(isfinite, q) && representable_scales(t, q) || return rejected()

    op = t.operator
    P = length(t.people)
    u = _mrcml_unpack(t, q)
    vp = _mrcml_pattern_shifts(op, u.eta_xi)

    K = length(t.categories)
    a = zeros(Z, K)
    gp = zeros(Z, P)
    r_pat = zeros(Z, length(op.c_pat))
    lp = logprior(t, q)

    @inbounds for n in 1:op.n_obs
        pat = op.pattern_of_row[n]
        prng = op.pattern_ranges[pat]
        g = t.group[n]
        sup = t.supports[g]
        p = t.person[n]
        th = u.person[p]
        fill!(a, -Z(Inf))
        for (lk, k) in enumerate(sup)
            m = prng[lk]
            a[k] = Z(op.B_pat[m]) * th + vp[m]
        end
        z = B._logsumexp(a)
        yk = t.category[n]
        lp += a[yk] - z
        for (lk, k) in enumerate(sup)
            m = prng[lk]
            pk = exp(a[k] - z)
            rk = (k == yk ? one(Z) : zero(Z)) - pk
            r_pat[m] += rk
            gp[p] += Z(op.B_pat[m]) * rk
        end
    end
    isfinite(lp) || return rejected()

    # Single sparse transpose multiply g_eta = A_free' * r_pat in O(nnz(A_free))
    d_xi = size(op.A_free, 2)
    g_eta = zeros(Z, d_xi)
    rows = rowvals(op.A_free)
    vals = nonzeros(op.A_free)
    @inbounds for col in 1:d_xi
        acc = zero(Z)
        for ptr in nzrange(op.A_free, col)
            acc += Z(vals[ptr]) * r_pat[rows[ptr]]
        end
        g_eta[col] = acc
    end

    # Pull back to white coordinates q
    grad = -Z.(q)
    if isnothing(u.population)
        @inbounds for p in 1:P
            grad[p] += u.person_sd * gp[p]
        end
    else
        pop = t.spec_record.population
        grad[pop.beta] .+= pop.coefficient_prior.sd .* (pop.X' * gp)
        for p in 1:P
            g = pop.group_index[p]
            scaled = u.population.group_sd[g] * gp[p]
            grad[p] += scaled
            grad[pop.logsd[g]] += pop.sd_prior.logsd * scaled * q[p]
        end
    end
    if t.person_hyper_idx > 0
        # d(s_p * q_p)/d(q_hyper) = s_p * logsd * q_p
        dot_pq = zero(Z)
        @inbounds for p in 1:P
            dot_pq += gp[p] * q[p]
        end
        grad[t.person_hyper_idx] += Z(t.person_logsd) * u.person_sd * dot_pq
    end

    for b in t.prior_blocks
        erng = b.eta_range
        rrng = b.raw_range
        if b.kind === :white_scaled
            @inbounds for (k, ei) in enumerate(erng)
                grad[rrng[k]] += Z(b.scale_vec[k]) * g_eta[ei]
            end
        elseif b.kind === :mvnormal
            # d(L * q_b)' * g_b = L' * g_b
            d_b = length(erng)
            @inbounds for c in 1:d_b
                acc = zero(Z)
                for r in c:d_b
                    acc += Z(b.chol_L[r, c]) * g_eta[erng[r]]
                end
                grad[rrng[c]] += acc
            end
        elseif b.kind === :hierarchical_lognormal
            sig = u.hyper_sds[b.name]
            eff_s = sig * Z(b.iso_factor)
            dot_bq = zero(Z)
            @inbounds for (k, ei) in enumerate(erng)
                ge = g_eta[ei]
                grad[rrng[k]] += eff_s * ge
                dot_bq += ge * q[rrng[k]]
            end
            grad[b.hyper_idx] += Z(b.logsd) * eff_s * dot_bq
        end
    end

    return all(isfinite, grad) ? (lp, grad) : rejected()
end

# ---------------------------------------------------------------------------
# 4. Parameter Names, Model Draws, Persistence, Contract & Stan Export
# ---------------------------------------------------------------------------

function names(t::MRCMLTarget, scale::Symbol)
    scale in (:raw, :model) || throw(ArgumentError("scale must be :raw or :model"))
    if scale === :raw
        out = Vector{String}(undef, t.dimension)
        P = length(t.people)
        for p in 1:P
            out[p] = "person.white[$p]"
        end
        t.person_hyper_idx > 0 && (out[t.person_hyper_idx] = "log_sd_raw[person]")
        for b in t.prior_blocks
            for (k, ri) in enumerate(b.raw_range)
                out[ri] = "$(b.name).white[$k]"
            end
            b.hyper_idx > 0 && (out[b.hyper_idx] = "log_sd_raw[$(b.name)]")
        end
        if hasproperty(t.spec_record,:population)
            pop = t.spec_record.population
            out[pop.beta] .= ["population.white[$(m.name)]" for m in pop.mean_terms]
            out[pop.logsd] .= ["log_sd.white[$(repr(g))]" for g in pop.groups]
        end
        return out
    end
    out = ["person[$(repr(x))]" for x in t.people]
    t.person_hyper_idx > 0 && push!(out, "residual_sd[person]")
    append!(out, t.operator.model_names)
    for b in t.prior_blocks
        b.hyper_idx > 0 && push!(out, "residual_sd[$(b.name)]")
    end
    if hasproperty(t.spec_record,:population)
        pop = t.spec_record.population
        append!(out, ["population[$(m.name)]" for m in pop.mean_terms])
        append!(out, ["population_sd[$(repr(g))]" for g in pop.groups])
    end
    return out
end

function model_draws(t::MRCMLTarget, raw::AbstractMatrix{<:Real})
    labels = names(t, :model)
    S_draws = size(raw, 1)
    values = Matrix{Float64}(undef, S_draws, length(labels))
    P = length(t.people)
    n_mod = length(t.operator.model_names)
    hyper_blocks = [b for b in t.prior_blocks if b.hyper_idx > 0]
    for i in 1:S_draws
        u = _mrcml_unpack(t, view(raw, i, :))
        col = 0
        values[i, 1:P] .= u.person
        col += P
        if t.person_hyper_idx > 0
            col += 1
            values[i, col] = u.person_sd
        end
        if n_mod > 0
            values[i, (col + 1):(col + n_mod)] .= u.xi_model
            col += n_mod
        end
        for b in hyper_blocks
            col += 1
            values[i, col] = u.hyper_sds[b.name]
        end
        if !isnothing(u.population)
            coeff = u.population.coefficients
            values[i,col .+ eachindex(coeff)] .= coeff
            values[i,col+length(coeff)+1:end] .= u.population.group_sd
        end
    end
    return (; names = labels, values, fixed = copy(t.operator.fixed_model_names))
end

function _serialize_sparse(M::SparseMatrixCSC{Float64,Int})
    I, J, V = findnz(M)
    return (; m = size(M, 1), n = size(M, 2), rows = I, cols = J, vals = V)
end

function _deserialize_sparse(s::NamedTuple)
    return sparse(Int.(s.rows), Int.(s.cols), Float64.(s.vals), Int(s.m), Int(s.n))
end

function record(t::MRCMLTarget)
    op = t.operator
    op_rec = (;
        n_obs = op.n_obs,
        n_patterns = op.n_patterns,
        pattern_of_row = copy(op.pattern_of_row),
        pattern_ranges = copy(op.pattern_ranges),
        pattern_group = copy(op.pattern_group),
        B_pat = copy(op.B_pat),
        c0_pat = copy(op.c0_pat),
        A_model = _serialize_sparse(op.A_model),
        xi0_model = copy(op.xi0_model),
        J_model = _serialize_sparse(op.J_model),
        free_names = copy(op.free_names),
        model_names = copy(op.model_names),
        fixed_model_names = sort!(collect(op.fixed_model_names)),
        block_meta = deepcopy(op.block_meta),
    )
    pblocks = [
        (;
            b.name, b.kind, b.eta_range, b.model_range, b.raw_range, b.hyper_idx,
            mu = copy(b.mu), scale_vec = copy(b.scale_vec), chol_L = copy(b.chol_L),
            b.iso_factor, b.marginal_sd, b.logmean, b.logsd,
        ) for b in t.prior_blocks
    ]
    facets_rec = [(; b.name, b.column, levels = deepcopy(b.levels), index = copy(b.index), b.sd, b.scale, b.raw) for b in t.facets]
    return (;
        schema = MRCML_SCHEMA,
        table = deepcopy(t.table),
        columns = deepcopy(t.columns),
        person = copy(t.person),
        people = deepcopy(t.people),
        category = copy(t.category),
        categories = copy(t.categories),
        supports = copy(t.supports),
        facets = facets_rec,
        owner = t.owner,
        step_owner_spec = deepcopy(t.step_owner_spec),
        group = copy(t.group),
        group_levels = deepcopy(t.group_levels),
        person_sd = t.person_sd,
        person_hyper_idx = t.person_hyper_idx,
        person_logmean = t.person_logmean,
        person_logsd = t.person_logsd,
        operator = op_rec,
        prior_blocks = pblocks,
        dimension = t.dimension,
        location_mode = t.location_mode,
        groups = deepcopy(t.groups),
        spec_record = deepcopy(t.spec_record),
    )
end

function restore_mrcml(r::NamedTuple)
    r.schema == MRCML_SCHEMA || throw(ArgumentError("unsupported MRCML record schema $(repr(r.schema))"))
    opr = r.operator
    A_mod = _deserialize_sparse(opr.A_model)
    J_mod = _deserialize_sparse(opr.J_model)
    A_fr = A_mod * J_mod
    dropzeros!(A_fr)
    xi0 = Float64.(opr.xi0_model)
    c0 = Float64.(opr.c0_pat)
    c_pat = c0 .+ Vector{Float64}(A_mod * xi0)
    op = MRCMLOperator(
        Int(opr.n_obs), Int(opr.n_patterns), Int.(opr.pattern_of_row),
        [ first(rg):last(rg) for rg in opr.pattern_ranges ],
        Int.(opr.pattern_group), Float64.(opr.B_pat), c_pat, c0,
        A_fr, A_mod, xi0, J_mod,
        String.(opr.free_names), String.(opr.model_names),
        Set{String}(String.(opr.fixed_model_names)),
        [ deepcopy(bm) for bm in opr.block_meta ],
    )
    pblocks = [
        MRCMLPriorBlock(
            Symbol(b.name), Symbol(b.kind), first(b.eta_range):last(b.eta_range),
            first(b.model_range):last(b.model_range), first(b.raw_range):last(b.raw_range),
            Int(b.hyper_idx), Float64.(b.mu), Float64.(b.scale_vec), Matrix{Float64}(b.chol_L),
            Float64(b.iso_factor), Float64(b.marginal_sd), Float64(b.logmean), Float64(b.logsd),
        ) for b in r.prior_blocks
    ]
    fblocks = [
        Block(Symbol(f.name), Symbol(f.column), Any[f.levels...], Int.(f.index),
            Float64(f.sd), Float64(f.scale), first(f.raw):last(f.raw)) for f in r.facets
    ]
    n_hyp = (Int(r.person_hyper_idx) > 0 ? 1 : 0) + count(b -> b.hyper_idx > 0, pblocks)
    alloc = _mrcml_allocation(Int.(r.person), Any[r.people...], fblocks, op, Symbol(r.location_mode); n_hyper = n_hyp,
        external_columns=get(r.spec_record,:external_columns,1:0))
    sym = _mrcml_audit_prior_symmetry(op, pblocks)
    return MRCMLTarget(
        deepcopy(r.table), deepcopy(r.columns), Int.(r.person), Any[r.people...],
        Int.(r.category), Int.(r.categories), [ first(s):last(s) for s in r.supports ],
        fblocks, Symbol(r.owner), deepcopy(r.step_owner_spec), Int.(r.group), Any[r.group_levels...],
        Float64(r.person_sd), Int(r.person_hyper_idx), Float64(r.person_logmean), Float64(r.person_logsd),
        op, pblocks, Int(r.dimension), Symbol(r.location_mode), alloc, sym,
        deepcopy(r.groups), deepcopy(r.spec_record),
    )
end

function design(t::MRCMLTarget)
    patterns = response_patterns(t)
    ws = [
        "Conditional independence given declared latent/structural terms is an assumption, not proven by design rank.",
        "MRCML design-matrix model: inspect prior symmetry and whole-fit/focal MCSE before substantive interpretation.",
        patterns.warnings...,
        t.prior_symmetry.warnings...,
    ]
    if hasproperty(t.spec_record,:calibration)
        push!(ws,"External Gaussian calibration contributes location information. Inspect receiving_rank for the receiving sample alone.")
    elseif hasproperty(t.spec_record,:fixed_calibration)
        push!(ws,"Uncertainty is conditional on the supplied fixed calibration.")
    end
    summary = (;
        n_observations = length(t.person),
        n_persons = length(t.people),
        n_patterns = t.operator.n_patterns,
        n_facets = length(t.facets) + 1,
        facets = map(t.facets) do b
            common = (;name=b.name, column=b.column, levels=deepcopy(b.levels),
                observed_levels=length(unique(b.index)))
            if hasproperty(t.spec_record,:calibration)
                cal = t.spec_record.calibration
                idx = findall(r->r.block===b.name,cal.coordinates)
                if !isempty(idx)
                    sd = [(;level=cal.coordinates[i].level,sd=sqrt(cal.covariance[i,i])) for i in idx]
                    return merge(common,(;marginal_prior_sd=missing, residual_prior_sd=b.sd,
                        external_prior_sd=sd, free_parameters=length(b.raw)+length(idx)))
                end
            end
            fixed = get(t.spec_record,:fixed_calibration,(;))
            if any(g -> g.block === b.name, get(fixed,:groups,()))
                prior = findfirst(p -> p.name === b.name, t.prior_blocks)
                hyper = !isnothing(prior) && t.prior_blocks[prior].hyper_idx > 0
                return merge(common,(;marginal_prior_sd=missing, unit_contrast_sd=hyper ? missing : b.sd,
                    unit_contrast_sd_prior_median=hyper ? b.sd : missing, free_parameters=length(b.raw)))
            end
            merge(common,(;marginal_prior_sd=b.sd, free_parameters=length(b.raw)))
        end,
        structural_blocks = deepcopy(t.operator.block_meta),
        categories = copy(t.categories),
        category_counts = [count(==(k), t.category) for k in eachindex(t.categories)],
        category_support = [(; owner = t.owner, level = deepcopy(t.group_levels[g]),
            categories = copy(t.categories[s])) for (g, s) in enumerate(t.supports)],
        step_owner = t.step_owner_spec,
        step_groups = deepcopy(t.group_levels),
        n_parameters = t.dimension,
        n_free_structural = size(t.operator.A_free, 2),
        n_model_structural = size(t.operator.A_model, 2),
        location_mode = t.location_mode,
        allocation = deepcopy(t.allocation),
        prior_symmetry = deepcopy(t.prior_symmetry),
        grouping = t.groups,
        (hasproperty(t.spec_record,:population) ? (;population=deepcopy(t.spec_record.population)) : (;))...,
        response_patterns = patterns,
        warnings = ws,
    )
    hasproperty(t.spec_record,:calibration) && return merge(summary,(;calibration=deepcopy(t.spec_record.calibration)))
    return hasproperty(t.spec_record,:fixed_calibration) ?
        merge(summary,(;fixed_calibration=deepcopy(t.spec_record.fixed_calibration))) : summary
end

function contract(t::MRCMLTarget)
    return (;
        schema = "bayesianmgmfrm.mrcml_contract.v1",
        status = :experimental_fitted_workflow,
        family = :mrcml_linear_logit_1d,
        dimensions = 1,
        multiplier = 1,
        facet_names = [b.name for b in t.facets],
        structural_blocks = [bm.name for bm in t.operator.block_meta],
        location_mode = t.location_mode,
        prior_measure = :white_standard_normal_with_explicit_block_jacobians,
        prior_asymmetry_detected = t.prior_symmetry.prior_asymmetry_detected,
        step_owner = t.step_owner_spec,
        supported_methods = hasproperty(t.spec_record,:calibration) ? (:nuts,) :
            hasproperty(t.spec_record,:population) ? (:nuts,:mmle) : (:nuts, :mmle, :jmle),
        operations = (:mfrm_spec, :getdesign, :design_summary, :validate_design, :contract, :parameter_names,
            :coordinates, :logprior, :loglikelihood, :pointwise_loglikelihood, :logposterior, :logdensity_and_gradient,
            :stan_data, :prior_draw, :simulate, :prior_predictive_check, :predictive_probabilities,
            :fit, :sampler_controls, :diagnostics, :qualify, :posterior_summary, :posterior_mcse,
            :contrast, :posterior_contrast, :fit_report, :predictive_check, :criteria, :waic, :psis_loo,
            :compare_models, :plot, :save_fit, :load_fit, :save_report, :load_report),
        prediction = :known_levels_exact_pattern_logits,
        fit_available = t.allocation.identified,
        scientific_acceptance = false,
        record = record(t),
    )
end

function mrcml_predict(t::MRCMLTarget, f; data = nothing, rows = nothing, interval = 0.95)
    data === nothing || throw(ArgumentError(
        "MRCMLTarget known-row prediction evaluates stored rating rows (`data = nothing`); select subset indices via `rows = ...`"))
    ix = rows === nothing ? collect(eachindex(t.person)) : collect(rows)
    !isempty(ix) && all(i -> i isa Integer && !(i isa Bool) && 1 <= i <= length(t.person), ix) ||
        throw(ArgumentError("rows must select existing observation indices in 1:$(length(t.person))"))
    lo, hi = interval_bounds(interval)
    K = length(t.categories)
    draws = f.record.run.draws
    S_draws = size(draws, 1)
    op = t.operator

    # Precompute pattern shifts and person abilities across all retained draws: O(S * (P + nnz(A)))
    th_draws = Matrix{Float64}(undef, S_draws, length(t.people))
    vp_draws = Matrix{Float64}(undef, S_draws, length(op.c_pat))
    for s in 1:S_draws
        u = _mrcml_unpack(t, view(draws, s, :))
        th_draws[s, :] .= u.person
        vp_draws[s, :] .= _mrcml_pattern_shifts(op, u.eta_xi)
    end

    means = zeros(Float64, length(ix), K)
    lower = similar(means)
    upper = similar(means)
    precision = NamedTuple[]
    a = zeros(Float64, S_draws, K)

    for (j, n) in enumerate(ix)
        pat = op.pattern_of_row[n]
        prng = op.pattern_ranges[pat]
        g = t.group[n]
        sup = t.supports[g]
        p = t.person[n]
        fill!(a, -Inf)
        @inbounds for s in 1:S_draws
            th = th_draws[s, p]
            for (lk, k) in enumerate(sup)
                m = prng[lk]
                a[s, k] = op.B_pat[m] * th + vp_draws[s, m]
            end
            z = B._logsumexp(view(a, s, :))
            for k in 1:K
                a[s, k] = k in sup ? exp(a[s, k] - z) : 0.0
            end
        end
        means[j, :] .= vec(mean(a; dims = 1))
        for k in 1:K
            lower[j, k] = quantile(view(a, :, k), lo)
            upper[j, k] = quantile(view(a, :, k), hi)
        end
        fixed = Set("category[$(t.categories[k])]" for k in 1:K if !(k in sup))
        append!(precision, [(; row = Int(n), category = t.categories[k], structural_zero = !(k in sup), r...)
            for (k, r) in enumerate(B._posterior_mcse_rows(a, ["category[$k]" for k in t.categories],
                f.record.run.controls.chains; probabilities = (lo, hi), parameter_space = :category_probability,
                structurally_fixed_parameters = fixed))])
    end

    cells = [(; position = j, row = Int(n), category = t.categories[k], mean = means[j, k],
        lower = lower[j, k], upper = upper[j, k], structural_zero = !(k in t.supports[t.group[n]]))
        for (j, n) in enumerate(ix) for k in 1:K]
    d = design(t)
    return (;
        schema = PREDICTION_SCHEMA,
        kind = :prediction,
        cells,
        rows = Int.(ix),
        category_levels = copy(t.categories),
        mean = means,
        lower,
        upper,
        interval,
        mcse = precision,
        response_patterns = d.response_patterns,
        warnings = d.warnings,
        target_identity = f.record.target_identity,
        category_support = [copy(t.categories[t.supports[t.group[n]]]) for n in ix],
        selected_columns = Dict(col => copy(values[ix]) for (col, values) in t.table if col != t.columns.score),
        conditioning = :known_finite_panel_levels,
        interval_target = :posterior_category_probability,
        observation_prediction = :posterior_mean_probabilities,
        qualification = qualify(f),
        source_sample_content_hash = f.record.content_hash,
        scientific_acceptance = false,
    )
end

function stan_data(t::MRCMLTarget)
    op = t.operator
    M_tot = length(op.c_pat)
    d_xi = size(op.A_free, 2)
    pat_start = [first(r) for r in op.pattern_ranges]
    pat_len = [length(r) for r in op.pattern_ranges]
    # Local 1-based observed slot index within each row's support
    y_local = [t.category[n] - first(t.supports[t.group[n]]) + 1 for n in 1:op.n_obs]
    # Express affine map eta_xi = eta_mu + L_eta_base * q_struct (for white_scaled & mvnormal)
    # plus hierarchical multiplier blocks so a single clean Stan program evaluates exact density/gradient!
    n_blocks = length(t.prior_blocks)
    b_kind = [b.kind === :white_scaled ? 1 : b.kind === :mvnormal ? 2 : 3 for b in t.prior_blocks]
    b_eta_start = [first(b.eta_range) for b in t.prior_blocks]
    b_eta_len = [length(b.eta_range) for b in t.prior_blocks]
    b_raw_start = [first(b.raw_range) for b in t.prior_blocks]
    b_hyper_idx = [b.hyper_idx for b in t.prior_blocks]
    b_iso = [b.iso_factor for b in t.prior_blocks]
    b_logmean = [b.logmean for b in t.prior_blocks]
    b_logsd = [b.logsd for b in t.prior_blocks]

    eta_mu = zeros(Float64, d_xi)
    L_eta = zeros(Float64, d_xi, d_xi)
    for b in t.prior_blocks
        erng = b.eta_range
        if b.kind === :white_scaled
            eta_mu[erng] .= b.mu
            for (k, ei) in enumerate(erng)
                L_eta[ei, ei] = b.scale_vec[k]
            end
        elseif b.kind === :mvnormal
            eta_mu[erng] .= b.mu
            L_eta[erng, erng] .= b.chol_L
        elseif b.kind === :hierarchical_lognormal
            for ei in erng
                L_eta[ei, ei] = 1.0
            end
        end
    end

    I_a, J_a, V_a = findnz(op.A_free)
    data = Dict{String,Any}(
        "N" => op.n_obs,
        "P" => length(t.people),
        "U" => op.n_patterns,
        "M_tot" => M_tot,
        "D_xi" => d_xi,
        "D" => t.dimension,
        "person" => copy(t.person),
        "pattern_of_row" => copy(op.pattern_of_row),
        "pat_start" => pat_start,
        "pat_len" => pat_len,
        "y_local" => y_local,
        "B_pat" => copy(op.B_pat),
        "c_pat" => copy(op.c_pat),
        "nnz_A" => length(V_a),
        "A_row" => I_a,
        "A_col" => J_a,
        "A_val" => V_a,
        "person_sd" => t.person_sd,
        "person_hyper_idx" => t.person_hyper_idx,
        "person_logmean" => t.person_logmean,
        "person_logsd" => t.person_logsd,
        "n_blocks" => n_blocks,
        "b_kind" => b_kind,
        "b_eta_start" => b_eta_start,
        "b_eta_len" => b_eta_len,
        "b_raw_start" => b_raw_start,
        "b_hyper_idx" => b_hyper_idx,
        "b_iso" => b_iso,
        "b_logmean" => b_logmean,
        "b_logsd" => b_logsd,
        "eta_mu" => eta_mu,
        "L_eta" => L_eta,
    )
    if hasproperty(t.spec_record,:population)
        p = t.spec_record.population
        delete!(data,"person_sd")
        merge!(data,Dict("G"=>length(p.groups),"C"=>size(p.X,2),"X"=>p.X,
            "member"=>p.group_index,"beta_start"=>first(p.beta),"sd_start"=>first(p.logsd),
            "beta_mean"=>p.coefficient_prior.mean,"beta_sd"=>p.coefficient_prior.sd,
            "logmean"=>p.sd_prior.logmean,"logsd"=>p.sd_prior.logsd))
    end
    return data
end

function _mrcml_stan_code(grouped)
    person_data = grouped ? """int<lower=2> G;
  int<lower=1> C;
  matrix[P,C] X;
  array[P] int<lower=1,upper=G> member;
  int<lower=1> beta_start, sd_start;
  real beta_mean, logmean;
  real<lower=0> beta_sd, logsd;""" : "real<lower=0> person_sd;"
    person_code = grouped ? """vector[C] beta = beta_mean + beta_sd * segment(q,beta_start,C);
  vector[G] sigma = exp(logmean + logsd * segment(q,sd_start,G));
  vector[P] theta = X * beta + sigma[member] .* head(q,P);""" :
        "real s_p = person_hyper_idx == 0 ? person_sd : exp(person_logmean + person_logsd * q[person_hyper_idx]);\n  vector[P] theta = s_p * q[1:P];"
    return """
data {
  int<lower=1> N;
  int<lower=1> P;
  int<lower=1> U;
  int<lower=2> M_tot;
  int<lower=0> D_xi;
  int<lower=1> D;
  array[N] int<lower=1, upper=P> person;
  array[N] int<lower=1, upper=U> pattern_of_row;
  array[U] int<lower=1, upper=M_tot> pat_start;
  array[U] int<lower=2, upper=M_tot> pat_len;
  array[N] int<lower=1> y_local;
  vector[M_tot] B_pat;
  vector[M_tot] c_pat;
  int<lower=0> nnz_A;
  array[nnz_A] int<lower=1, upper=M_tot> A_row;
  array[nnz_A] int<lower=1, upper=D_xi> A_col;
  vector[nnz_A] A_val;
  $person_data
  int<lower=0, upper=D> person_hyper_idx;
  real person_logmean;
  real<lower=0> person_logsd;
  int<lower=0> n_blocks;
  array[n_blocks] int<lower=1, upper=3> b_kind;
  array[n_blocks] int<lower=1> b_eta_start;
  array[n_blocks] int<lower=0> b_eta_len;
  array[n_blocks] int<lower=1> b_raw_start;
  array[n_blocks] int<lower=0, upper=D> b_hyper_idx;
  vector[n_blocks] b_iso;
  vector[n_blocks] b_logmean;
  vector[n_blocks] b_logsd;
  vector[D_xi] eta_mu;
  matrix[D_xi, D_xi] L_eta;
}
parameters {
  vector[D] q;
}
model {
  $person_code
  vector[D_xi] eta_xi = eta_mu;
  for (b in 1:n_blocks) {
    int len = b_eta_len[b];
    if (len > 0) {
      int es = b_eta_start[b];
      int rs = b_raw_start[b];
      if (b_kind[b] == 1 || b_kind[b] == 2) {
        eta_xi[es:(es + len - 1)] += L_eta[es:(es + len - 1), es:(es + len - 1)] * q[rs:(rs + len - 1)];
      } else {
        real sig = exp(b_logmean[b] + b_logsd[b] * q[b_hyper_idx[b]]);
        eta_xi[es:(es + len - 1)] = (sig * b_iso[b]) * q[rs:(rs + len - 1)];
      }
    }
  }
  vector[M_tot] v_pat = c_pat;
  for (nz in 1:nnz_A) {
    v_pat[A_row[nz]] += A_val[nz] * eta_xi[A_col[nz]];
  }
  target += -0.5 * D * log(2 * pi()) - 0.5 * dot_self(q);
  for (n in 1:N) {
    int u = pattern_of_row[n];
    int s = pat_start[u];
    int m = pat_len[u];
    vector[m] logits = B_pat[s:(s + m - 1)] * theta[person[n]] + v_pat[s:(s + m - 1)];
    target += logits[y_local[n]] - log_sum_exp(logits);
  }
}
"""
end

const MRCML_STAN_CODE = _mrcml_stan_code(false)

# ---------------------------------------------------------------------------
# 5. Layer-1 Structured MRCML Compiler (`interactions`, `lltm`, tuple `steps`)
# ---------------------------------------------------------------------------

function _parse_scale_or_lognormal(val, active::Bool, label)
    if val isa D.LogNormal
        active || throw(ArgumentError("$label cannot use a LogNormal hyperprior on an inactive 0-df block"))
        mu, sd = Float64.(D.params(val))
        isfinite(mu) && isfinite(sd) && sd > 0 && isfinite(exp(mu)) && exp(mu) > 0 ||
            throw(ArgumentError("$label LogNormal parameters must be finite with logsd > 0"))
        return (; kind = :lognormal, sd = exp(mu), logmean = mu, logsd = sd)
    end
    s = _sd(val, active, label)
    return (; kind = :fixed, sd = s, logmean = 0.0, logsd = 1.0)
end

function _normalize_interaction_specs(interactions, prior_sd_nt, facet_names::Tuple)
    interactions === nothing && return NamedTuple[]
    raw_list = interactions isa Tuple ? collect(Any, interactions) :
               interactions isa AbstractVector ? collect(Any, interactions) :
               throw(ArgumentError("interactions must be a Tuple or Vector of 2-way pairs `(f1, f2)` or `(f1, :step)`"))
    isempty(raw_list) && return NamedTuple[]

    int_priors = (prior_sd_nt !== nothing && hasproperty(prior_sd_nt, :interactions)) ? prior_sd_nt.interactions : nothing
    parsed = NamedTuple[]
    seen = Set{Tuple{Symbol,Symbol}}()

    for item in raw_list
        pair, inline_prior = if item isa NamedTuple
            hasproperty(item, :pair) || throw(ArgumentError("NamedTuple interaction entry must specify `pair = (a, b)`"))
            (item.pair, hasproperty(item, :prior) ? item.prior : nothing)
        elseif item isa Tuple && length(item) == 2 && all(x -> x isa Symbol, item)
            (item, nothing)
        elseif item isa Pair && item.first isa Tuple && length(item.first) == 2
            (item.first, item.second)
        else
            throw(ArgumentError("interaction entry $(repr(item)) must be `(f1, f2)`, `(f1, :step)`, `(f1, f2) => sd`, or `(pair = ..., prior = ...)`"))
        end
        a, b = Symbol(pair[1]), Symbol(pair[2])
        is_step = b in (:step, :steps) || a in (:step, :steps)
        if is_step
            f_sym = a in (:step, :steps) ? b : a
            f_sym in facet_names || throw(ArgumentError("step interaction facet $(repr(f_sym)) is not in declared facets $facet_names"))
            canon = (f_sym, :step)
            canon in seen && throw(ArgumentError("duplicate interaction $(repr(canon))"))
            push!(seen, canon)
            key_sym = Symbol(f_sym, :_step)
            pr = inline_prior
            if pr === nothing && int_priors !== nothing
                if int_priors isa AbstractDict
                    pr = get(int_priors, canon, get(int_priors, key_sym, nothing))
                elseif int_priors isa NamedTuple && hasproperty(int_priors, key_sym)
                    pr = getproperty(int_priors, key_sym)
                elseif int_priors isa Real || int_priors isa D.LogNormal
                    pr = int_priors
                end
            end
            push!(parsed, (; kind = :facet_step, f1 = f_sym, f2 = :step, key = key_sym, prior = pr))
        else
            a in facet_names && b in facet_names ||
                throw(ArgumentError("interaction facets ($a, $b) must belong to declared facets $facet_names"))
            a != b || throw(ArgumentError("self-interaction ($a, $a) is invalid"))
            # Canonicalize order to match declaration order in `facets`
            ia = findfirst(==(a), facet_names)
            ib = findfirst(==(b), facet_names)
            f1, f2 = ia < ib ? (a, b) : (b, a)
            canon = (f1, f2)
            canon in seen && throw(ArgumentError("duplicate interaction ($f1, $f2)"))
            push!(seen, canon)
            key1 = Symbol(f1, :_, f2)
            key2 = Symbol(f2, :_, f1)
            pr = inline_prior
            if pr === nothing && int_priors !== nothing
                if int_priors isa AbstractDict
                    pr = get(int_priors, (f1, f2), get(int_priors, (f2, f1), get(int_priors, key1, nothing)))
                elseif int_priors isa NamedTuple
                    pr = hasproperty(int_priors, key1) ? getproperty(int_priors, key1) :
                         hasproperty(int_priors, key2) ? getproperty(int_priors, key2) : nothing
                elseif int_priors isa Real || int_priors isa D.LogNormal
                    pr = int_priors
                end
            end
            push!(parsed, (; kind = :facet_facet, f1, f2, key = key1, prior = pr))
        end
    end
    return parsed
end

# Resolve external logit locations on their original scale. A centered step block
# retains its sum constraint in the remaining coordinates.
function _calibration_block(levels, values, centered, label)
    n = length(levels)
    if values === nothing
        return zeros(n), _helmert_matrix(n), String[]
    end
    values isa AbstractDict && !isempty(values) ||
        throw(ArgumentError("$label requires a nonempty dictionary keyed by level"))
    base = zeros(n)
    anchored = falses(n)
    for (level, value) in pairs(values)
        idx = findfirst(x -> isequal(x, level), levels)
        idx !== nothing && _valid_facet_label(level) ||
            throw(ArgumentError("unknown $label level $(repr(level))"))
        value isa Real && !(value isa Bool) && isfinite(Float64(value)) ||
            throw(ArgumentError("$label requires finite logit values"))
        base[idx] = Float64(value)
        anchored[idx] = true
    end
    free = findall(!, anchored)
    if centered
        total = sum(base)
        isfinite(total) || throw(ArgumentError("$label sum exceeds the finite logit range"))
        if isempty(free)
            abs(total) <= 32eps(Float64)*max(1.0, maximum(abs, base))*n ||
                throw(ArgumentError("complete $label values must sum to zero"))
        else
            base[free] .= -total / length(free)
        end
        C = zeros(n, max(length(free)-1,0))
        isempty(free) || (C[free,:] = _helmert_matrix(length(free)))
    else
        C = zeros(n, length(free))
        for (j, row) in enumerate(free)
            C[row,j] = 1
        end
    end
    return base, C, [repr(levels[i]) for i in free]
end


# Minimum-norm origin and orthonormal null directions of a set of equalities.
function _affine_coordinates(L,d)
    n = size(L,2)
    F = svd(L;full=size(L,1)<n)
    tol = max(size(L)...) * eps(Float64)
    r = count(>(tol * first(F.S)), F.S)
    origin = F.V[:,1:r] * ((F.U[:,1:r]' * d) ./ F.S[1:r])
    return origin, F.V[:,r+1:end], tol
end

function _calibrated_cells(rows, specs)
    rows isa Union{Tuple,AbstractVector} && !isempty(rows) ||
        throw(ArgumentError("cells must be a nonempty sequence of named interaction cells"))
    by_pair = Dict{Tuple{Symbol,Symbol},Dict{Tuple,Float64}}()
    for row in rows
        row isa NamedTuple && Set(keys(row))==Set((:levels,:value)) &&
            row.levels isa NamedTuple && length(row.levels)==2 ||
            throw(ArgumentError("each cell requires levels=(facet1=id1,facet2=id2) and value"))
        all(_valid_facet_label,values(row.levels)) ||
            throw(ArgumentError("cell levels must be valid facet IDs"))
        a,b = keys(row.levels)
        i = findfirst(x->x.kind===:facet_facet && (x.f1,x.f2) in ((a,b),(b,a)), specs)
        isnothing(i) && throw(ArgumentError("cell ($a,$b) requires a declared facet-by-facet interaction"))
        pair = (specs[i].f1,specs[i].f2)
        levels = (row.levels[pair[1]],row.levels[pair[2]])
        block = get!(by_pair,pair,Dict{Tuple,Float64}())
        haskey(block,levels) && throw(ArgumentError("duplicate interaction cell $pair $levels"))
        row.value isa Real && !(row.value isa Bool) && isfinite(Float64(row.value)) ||
            throw(ArgumentError("interaction cell values must be finite logits"))
        block[levels] = Float64(row.value)
    end
    return by_pair
end

function _interaction_calibration_block(K, b1, b2, cells, receipt)
    pair = (b1.name,b2.name)
    idx = Int[]
    d = Float64[]
    for (i,l1) in enumerate(b1.levels), (j,l2) in enumerate(b2.levels)
        levels = (l1,l2)
        haskey(cells,levels) || continue
        push!(idx,(i-1)*length(b2.levels)+j)
        push!(d,cells[levels])
        push!(receipt,(;kind=:interaction_cell,block=pair,level=levels,
            level_labels=map(label_encoding,levels),value=cells[levels]))
    end
    length(idx)==length(cells) || throw(ArgumentError("unknown level in fixed interaction cells for $pair"))
    if size(K,2)==0
        all(iszero,d) || throw(ArgumentError("a singleton interaction margin forces every cell to zero"))
        return zeros(size(K,1)), K
    end
    L = K[idx,:]
    z, N, tol = _affine_coordinates(L,d)
    origin = K*z
    # Reject conflicting constraints before storing the supplied values exactly.
    all(isfinite,origin) && all(abs.(origin[idx]-d) .<= 32tol .* max.(abs.(d),abs.(L)*abs.(z))) ||
        throw(ArgumentError("fixed cells for $pair conflict with the zero row or column sums"))
    origin[idx] .= d
    C = K*N
    for k in axes(C,1)
        norm(view(C,k,:)) <= 8tol && (C[k,:] .= 0)
    end
    C[idx,:] .= 0
    return origin, C
end

# Combine exact level locations and named subset restrictions on one substantive facet.
# The minimum-norm origin and Euclidean nullspace give the conditional isotropic prior.
function _subset_calibration_block(levels, values, groups, label, receipt)
    n = length(levels)
    nhard = isnothing(values) ? 0 : length(values)
    L = zeros(nhard + length(groups), n)
    d = zeros(size(L,1))
    hard = Int[]
    if !isnothing(values)
        base, _, _ = _calibration_block(levels, values, false, label)
        hard = findall(k -> haskey(values,k), levels)
        for (row, k) in enumerate(hard)
            L[row,k] = 1
            d[row] = base[k]
        end
    end
    for (i, g) in enumerate(groups)
        kind = haskey(g,:mean) ? :mean : :sum
        Set(keys(g)) == Set((:block,:levels,kind)) ||
            throw(ArgumentError("a group requires block, levels and exactly one mean or sum"))
        members = g.levels
        members isa Union{AbstractVector,Tuple} && !isempty(members) && allunique(members) &&
            all(k -> _valid_facet_label(k) && k in levels, members) ||
            throw(ArgumentError("$label group levels must be distinct known level IDs"))
        value = g[kind]
        value isa Real && !(value isa Bool) && isfinite(Float64(value)) ||
            throw(ArgumentError("$label group requires a finite logit value"))
        idx = findall(in(Set(members)), levels)
        scale = sqrt(length(idx))
        row = nhard + i
        L[row,idx] .= inv(scale)
        d[row] = kind === :mean ? Float64(value)*scale : Float64(value)/scale
        isfinite(d[row]) || throw(ArgumentError("$label group target exceeds the finite logit range"))
        push!(receipt,(;block=label, levels=deepcopy(levels[idx]), statistic=kind, value=Float64(value)))
    end
    origin, C, tol = _affine_coordinates(L,d)
    for (row,k) in enumerate(hard)
        origin[k] = d[row]
    end
    # Check consistency on each equation's own scale, including overlapping groups.
    all(isfinite,origin) && all(abs.(L*origin-d) .<= 32tol .* max.(1.,abs.(d),abs.(L)*abs.(origin))) ||
        throw(ArgumentError("incompatible fixed locations or group constraints for $label"))
    for k in axes(C,1)
        norm(view(C,k,:)) <= tol && (C[k,:] .= 0)
    end
    return origin, C, String[]
end


function compile_structured_mrcml(table;
        person::Symbol,
        score::Symbol,
        facets::NamedTuple,
        steps = :global,
        prior_sd = nothing,
        category_levels,
        levels = nothing,
        interactions = nothing,
        lltm = nothing,
        fixed_calibration = nothing,
        calibration = nothing,
        intercept = nothing,
        performance::Union{Nothing,Symbol} = nothing,
        assessment::Union{Nothing,Symbol} = nothing)
    is_bayesian = prior_sd !== nothing
    reserved = (:person, :steps, :step, :global, :score, :performance, :assessment)
    all(k -> !(k in reserved), keys(facets)) ||
        throw(ArgumentError("facet names cannot use reserved roles $reserved"))
    all(x -> x isa Symbol, values(facets)) ||
        throw(ArgumentError("facet mapping values must be column symbols"))

    facet_names = keys(facets)
    # Validate `steps`: `:global`, single facet `Symbol`, or tuple of >=2 facet `Symbol`s
    if steps === :global || steps isa Symbol
        steps === :global || steps in facet_names ||
            throw(ArgumentError("steps must be :global, a declared facet name, or a tuple of declared facet names"))
    elseif steps isa Tuple && length(steps) >= 2 && all(s -> s isa Symbol && s in facet_names, steps)
        length(unique(steps)) == length(steps) ||
            throw(ArgumentError("tuple `steps = $steps` cannot repeat the same facet"))
    else
        throw(ArgumentError("steps must be :global, a declared facet Symbol, or a Tuple of >= 2 declared facet Symbols; got $(repr(steps))"))
    end

    # Parse LLTM feature specifications
    lltm_nt = lltm === nothing ? (;) : _named(lltm, :lltm)
    all(k -> k in facet_names, keys(lltm_nt)) ||
        throw(ArgumentError("lltm keys $(collect(keys(lltm_nt))) must name declared facets in $facet_names"))
    lltm_cols = Symbol[]
    for (fk, lspec) in pairs(lltm_nt)
        lspec isa NamedTuple && hasproperty(lspec, :features) ||
            throw(ArgumentError("lltm.$fk must be a NamedTuple with `features = (:col1, ...)`"))
        fcols = collect(Symbol, lspec.features)
        !isempty(fcols) && allunique(fcols) ||
            throw(ArgumentError("lltm.$fk.features must be nonempty and distinct"))
        append!(lltm_cols, fcols)
    end

    selected = unique(Symbol[person, score, values(facets)..., lltm_cols...])
    performance !== nothing && !(performance in selected) && push!(selected, performance)
    assessment !== nothing && !(assessment in selected) && push!(selected, assessment)

    # Distinct role columns check for person, score, and facets
    core_roles = Symbol[person, score, values(facets)...]
    length(unique(core_roles)) == length(core_roles) ||
        throw(ArgumentError("person, score, and each facet must use distinct columns"))

    raw = Dict{Symbol,Vector}(c => deepcopy(B._column(table, c)) for c in selected)
    n = length(raw[score])
    n > 0 || throw(ArgumentError("ratings cannot be empty"))
    for c in core_roles
        B._check_length!(n, raw[c], c)
        c == score || _labels(raw[c], c)
    end
    for c in lltm_cols
        B._check_length!(n, raw[c], c)
    end

    if levels !== nothing
        _keys(levels, (:person, :facets), :levels)
        _keys(levels.facets, facet_names, :facet_levels)
    end

    p_idx, p_levels = _labels(raw[person], :person, levels === nothing ? nothing : levels.person)
    P = length(p_levels)

    # Parse person prior SD if Bayesian
    p_sd_val = 1.0
    p_logmean = 0.0
    p_logsd = 1.0
    p_is_hyper = false
    if is_bayesian
        prior_sd isa NamedTuple || throw(ArgumentError("prior_sd must be a NamedTuple"))
        hasproperty(prior_sd, :person) && hasproperty(prior_sd, :facets) && hasproperty(prior_sd, :step) ||
            throw(ArgumentError("prior_sd must specify `person`, `facets`, and `step` (plus optional `interactions`)"))
        allowed_psd_keys = (:person, :facets, :step, :interactions)
        all(k -> k in allowed_psd_keys, keys(prior_sd)) ||
            throw(ArgumentError("unexpected keys in prior_sd: $(setdiff(keys(prior_sd), allowed_psd_keys))"))
        pspec = _parse_scale_or_lognormal(prior_sd.person, true, :person_sd)
        p_sd_val = pspec.sd
        p_logmean = pspec.logmean
        p_logsd = pspec.logsd
        p_is_hyper = pspec.kind === :lognormal
    end

    # Build facet index metadata
    f_info = NamedTuple[]
    for (fname, fcol) in pairs(facets)
        idx, lev = _labels(raw[fcol], fname, levels === nothing ? nothing : levels.facets[fname])
        push!(f_info, (; name = fname, column = fcol, levels = lev, index = idx))
    end
    f_lookup = Dict(b.name => b for b in f_info)

    # Step ownership group mapping
    owner_sym, group, group_levels = if steps === :global
        (:global, ones(Int, n), Any[:global])
    elseif steps isa Symbol
        ob = f_lookup[steps]
        (steps, copy(ob.index), deepcopy(ob.levels))
    else
        # Tuple of facets e.g. (:rater, :item) -> Cartesian product of declared levels
        sub_bs = [f_lookup[s] for s in steps]
        dims = Tuple(length(b.levels) for b in sub_bs)
        lin = LinearIndices(dims)
        cart = CartesianIndices(dims)
        g_levs = Any[Tuple(sub_bs[d].levels[ci[d]] for d in 1:length(sub_bs)) for ci in vec(cart)]
        g_idx = [lin[ntuple(d -> sub_bs[d].index[i], length(sub_bs))...] for i in 1:n]
        comb_sym = Symbol(join(String.(collect(steps)), "__"))
        (comb_sym, g_idx, g_levs)
    end

    if category_levels isa AbstractDict && !(steps isa Symbol && steps !== :global)
        throw(ArgumentError("Dict category_levels by owner requires a single declared facet `steps = :facet`"))
    end
    cat, categories, supports = _category_support(raw[score], score, category_levels,
        steps isa Tuple ? owner_sym : steps, group, group_levels)

    transfer = nothing
    if !isnothing(calibration)
        isnothing(fixed_calibration) || throw(ArgumentError("choose fixed_calibration or calibration"))
        transfer, fixed_calibration = _joint_calibration(calibration,steps)
    end
    calibration = isnothing(fixed_calibration) ? (;) : fixed_calibration
    calibration isa NamedTuple && all(k -> k in (:facets,:steps,:groups,:cells), keys(calibration)) ||
        throw(ArgumentError("fixed_calibration accepts named facets, steps, groups and interaction cells"))
    fixed_facets = get(calibration, :facets, (;))
    fixed_facets isa NamedTuple && all(k -> k in facet_names, keys(fixed_facets)) ||
        throw(ArgumentError("calibrated facets must match declared facet roles"))
    all(k -> !haskey(lltm_nt,k), keys(fixed_facets)) ||
        throw(ArgumentError("a fixed facet location cannot also have an LLTM feature model"))
    groups = get(calibration, :groups, ())
    groups isa Union{Tuple,AbstractVector} && (!haskey(calibration,:groups) || !isempty(groups)) &&
        all(g -> g isa NamedTuple && haskey(g,:block) && g.block in facet_names &&
            !haskey(lltm_nt,g.block), groups) ||
        throw(ArgumentError("groups must name declared facet main effects without an LLTM restriction"))
    group_receipt = NamedTuple[]
    group_dimensions = NamedTuple[]
    fixed_steps = if haskey(calibration, :steps)
        declaration = calibration.steps
        valid_owner(x) = (x isa Tuple ? all(_valid_facet_label,x) : _valid_facet_label(x)) && x in group_levels
        declaration isa NamedTuple && Set(keys(declaration)) == Set((:owner,:values)) &&
            isequal(declaration.owner,steps) && declaration.values isa AbstractDict &&
            !isempty(declaration.values) && all(valid_owner, keys(declaration.values)) ||
            throw(ArgumentError("fixed steps require the declared owner and a dictionary by owner level"))
        declaration.values
    else
        Dict()
    end
    if !isnothing(fixed_calibration)
        (!isempty(fixed_facets) || !isempty(fixed_steps) || !isempty(groups) || haskey(calibration,:cells)) || throw(ArgumentError("empty fixed calibration"))
        all(v -> v isa AbstractDict && !isempty(v), values(fixed_facets)) &&
            all(v -> v isa AbstractDict && !isempty(v), values(fixed_steps)) ||
            throw(ArgumentError("each calibrated block requires a nonempty dictionary of values"))
    end
    if !isnothing(intercept)
        !isnothing(fixed_calibration) && is_bayesian && intercept isa D.Normal ||
            throw(ArgumentError("an anchored population intercept requires an explicit Normal prior and prior_sd"))
        :population_mean in facet_names && throw(ArgumentError("population_mean is reserved for the population intercept"))
    end

    int_specs = _normalize_interaction_specs(interactions, prior_sd, facet_names)
    cells = haskey(calibration,:cells) ? _calibrated_cells(calibration.cells,int_specs) : nothing
    cell_anchors = NamedTuple[]
    cell_dimensions = NamedTuple[]
    if any(x -> x.kind === :facet_step && steps === x.f1, int_specs)
        throw(ArgumentError("cannot add `($(repr(steps)), :step)` interaction when `steps = $(repr(steps))` already owns unconstrained per-level steps"))
    end

    # Assemble expanded model coordinates xi_model, J_model, free_names, model_names, and prior_blocks
    J_rows = Int[]
    J_cols = Int[]
    J_vals = Float64[]
    xi0_model = Float64[]
    free_names = String[]
    model_names = String[]
    fixed_model_names = Set{String}()
    block_meta = NamedTuple[]
    af_blocks = Block[]
    raw_cursor = P
    eta_cursor = 0
    mod_cursor = 0

    # Pending prior block descriptors (hyper_idx assigned after all continuous raw coordinates)
    pending_blocks = NamedTuple[]

    # 1) Facet main effects & LLTM feature blocks
    for fb in f_info
        fname = fb.name
        L_f = length(fb.levels)
        has_lltm = haskey(lltm_nt, fname)
        if !has_lltm
            values_f = get(fixed_facets, fname, nothing)
            facet_groups = filter(g -> g.block === fname, groups)
            grouped = !isempty(facet_groups)
            base_f, C_f, free_labels = grouped ?
                _subset_calibration_block(fb.levels, values_f, facet_groups, fname, group_receipt) :
                _calibration_block(fb.levels, values_f, false, fname)
            d_f = size(C_f,2)
            grouped && push!(group_dimensions,(;block=fname,n_levels=L_f,
                constraint_rank=L_f-d_f,free_locations=d_f))
            f_prior = if is_bayesian
                hasproperty(prior_sd.facets, fname) ||
                    throw(ArgumentError("prior_sd.facets is missing entry for facet $(repr(fname))"))
                _parse_scale_or_lognormal(getproperty(prior_sd.facets, fname), d_f > 0, fname)
            else
                (; kind = :fixed, sd = L_f > 1 ? 1.0 : 0.0, logmean = 0.0, logsd = 1.0)
            end
            iso = grouped || !isnothing(values_f) ? 1.0 : L_f > 1 ? sqrt(L_f / (L_f - 1)) : 0.0
            erng = (eta_cursor + 1):(eta_cursor + d_f)
            mrng = (mod_cursor + 1):(mod_cursor + L_f)
            rrng = (raw_cursor + 1):(raw_cursor + d_f)
            for c in 1:d_f, r in 1:L_f
                v = C_f[r, c]
                v == 0.0 && continue
                push!(J_rows, mod_cursor + r); push!(J_cols, eta_cursor + c); push!(J_vals, v)
            end
            append!(xi0_model, base_f)
            append!(free_names, grouped || isnothing(values_f) ? ["$(fname).contrast[$c]" for c in 1:d_f] :
                ["$(fname)[$level]" for level in free_labels])
            mnames_f = ["$(fname)[$(repr(x))]" for x in fb.levels]
            append!(model_names, mnames_f)
            union!(fixed_model_names, mnames_f[vec(all(iszero,C_f; dims=2))])

            push!(af_blocks, Block(fname, fb.column, deepcopy(fb.levels), copy(fb.index), f_prior.sd, f_prior.sd * iso, rrng))
            push!(block_meta, (; name = fname, kind = :facet_main, levels = deepcopy(fb.levels),
                eta_range = erng, model_range = mrng, check_exchangeable_symmetry = !grouped))
            if is_bayesian && d_f > 0
                push!(pending_blocks, (;
                    name = fname,
                    kind = f_prior.kind === :lognormal ? :hierarchical_lognormal : :white_scaled,
                    eta_range = erng, model_range = mrng, raw_range = rrng,
                    mu = zeros(Float64, d_f),
                    scale_vec = fill(f_prior.sd * iso, d_f),
                    chol_L = zeros(Float64, 0, 0),
                    iso_factor = iso, marginal_sd = f_prior.sd,
                    logmean = f_prior.logmean, logsd = f_prior.logsd,
                ))
            end
            eta_cursor += d_f
            mod_cursor += L_f
            raw_cursor += d_f
        else
            # Fischer (1973) LLTM / LRSM / LPCM linear feature restriction (+ optional isometric residual)
            lspec = lltm_nt[fname]
            fcols = collect(Symbol, lspec.features)
            M_feat = length(fcols)
            center_feat = hasproperty(lspec, :center) ? Bool(lspec.center) : true
            W_mat = zeros(Float64, L_f, M_feat)
            for (m_idx, fc) in enumerate(fcols)
                col_vec = _numeric_column(raw, fc, n)
                lev_vals = fill(NaN, L_f)
                for i in 1:n
                    lv = fb.index[i]
                    if isnan(lev_vals[lv])
                        lev_vals[lv] = col_vec[i]
                    elseif lev_vals[lv] != col_vec[i]
                        throw(ArgumentError("LLTM feature $fc varies within facet $fname level $(repr(fb.levels[lv])); LLTM features must be facet-level attributes"))
                    end
                end
                all(isfinite, lev_vals) ||
                    throw(ArgumentError("LLTM feature $fc is unobserved for at least one declared $fname level"))
                W_mat[:, m_idx] .= center_feat ? (lev_vals .- mean(lev_vals)) : lev_vals
            end
            # Check feature matrix column rank <= L_f - 1 when centered
            rank(W_mat; rtol = max(size(W_mat)...) * eps(Float64)) == M_feat ||
                throw(ArgumentError("LLTM feature matrix for facet $fname is column rank-deficient ($(rank(W_mat))/$M_feat); remove collinear or constant feature columns"))

            # Parse LLTM feature weight prior
            w_erng = (eta_cursor + 1):(eta_cursor + M_feat)
            w_mrng = (mod_cursor + 1):(mod_cursor + M_feat)
            w_rrng = (raw_cursor + 1):(raw_cursor + M_feat)
            for m_idx in 1:M_feat
                push!(J_rows, mod_cursor + m_idx); push!(J_cols, eta_cursor + m_idx); push!(J_vals, 1.0)
            end
            append!(xi0_model, zeros(Float64, M_feat))
            w_names = ["lltm[$(fname),$(fc)]" for fc in fcols]
            append!(free_names, w_names)
            append!(model_names, w_names)

            if is_bayesian
                hasproperty(lspec, :prior) ||
                    throw(ArgumentError("Bayesian LLTM for facet $fname requires `prior = Normal(mu, sd)` (or NamedTuple / MvNormal)"))
                lpr = lspec.prior
                if lpr isa D.Normal
                    np = _normal_parameters(lpr, "lltm.$fname.prior")
                    push!(pending_blocks, (;
                        name = Symbol(:lltm_, fname), kind = :white_scaled,
                        eta_range = w_erng, model_range = w_mrng, raw_range = w_rrng,
                        mu = fill(np.mean, M_feat), scale_vec = fill(np.sd, M_feat),
                        chol_L = zeros(Float64, 0, 0), iso_factor = 1.0, marginal_sd = np.sd,
                        logmean = 0.0, logsd = 1.0,
                    ))
                elseif lpr isa NamedTuple
                    _keys(lpr, Tuple(fcols), Symbol(:lltm_prior_, fname))
                    mus = Float64[]; sds = Float64[]
                    for fc in fcols
                        np = _normal_parameters(getproperty(lpr, fc), "lltm.$fname.prior.$fc")
                        push!(mus, np.mean); push!(sds, np.sd)
                    end
                    push!(pending_blocks, (;
                        name = Symbol(:lltm_, fname), kind = :white_scaled,
                        eta_range = w_erng, model_range = w_mrng, raw_range = w_rrng,
                        mu = mus, scale_vec = sds,
                        chol_L = zeros(Float64, 0, 0), iso_factor = 1.0, marginal_sd = NaN,
                        logmean = 0.0, logsd = 1.0,
                    ))
                elseif lpr isa D.AbstractMvNormal
                    length(lpr) == M_feat ||
                        throw(DimensionMismatch("LLTM MvNormal prior length $(length(lpr)) != $M_feat features"))
                    L_c = Matrix(cholesky(Symmetric(Matrix(D.cov(lpr)))).L)
                    push!(pending_blocks, (;
                        name = Symbol(:lltm_, fname), kind = :mvnormal,
                        eta_range = w_erng, model_range = w_mrng, raw_range = w_rrng,
                        mu = Float64.(mean(lpr)), scale_vec = Float64[],
                        chol_L = L_c, iso_factor = 1.0, marginal_sd = NaN,
                        logmean = 0.0, logsd = 1.0,
                    ))
                else
                    throw(ArgumentError("lltm.$fname.prior must be Normal, NamedTuple of Normals, or MvNormal"))
                end
            end
            push!(block_meta, (; name = Symbol(:lltm_, fname), kind = :lltm_weights, facet = fname,
                features = fcols, centered = center_feat, eta_range = w_erng, model_range = w_mrng,
                check_exchangeable_symmetry = false))
            eta_cursor += M_feat
            mod_cursor += M_feat
            raw_cursor += M_feat

            # Optional residual term (LLTM + error) + reconstructed facet difficulty block `fname[level]`
            res_spec = hasproperty(lspec, :residual) ? lspec.residual : false
            has_res = !(res_spec === false || res_spec === nothing || (res_spec isa Real && !(res_spec isa Bool) && Float64(res_spec) == 0.0))
            if is_bayesian && hasproperty(prior_sd.facets, fname) && !has_res
                fv = getproperty(prior_sd.facets, fname)
                (fv isa Real && !(fv isa Bool) && Float64(fv) == 0.0) ||
                    throw(ArgumentError("facet $fname uses strict LLTM (`residual = false`); omit `prior_sd.facets.$fname` or set it to `0.0`"))
            end

            res_erng = 1:0
            res_rrng = 1:0
            res_sd_num = 0.0
            if has_res
                L_f > M_feat + (center_feat ? 1 : 0) ||
                    throw(ArgumentError("LLTM + residual for facet $fname is overparameterized: $L_f levels cannot identify $M_feat features plus $(L_f - 1) unconstrained residuals"))
                # Residual lives in the orthogonal complement of [1, W_mat] so W_mat weights and residual are identifiable!
                basis_null = nullspace(Matrix(hcat(ones(Float64, L_f), W_mat)'))
                d_res = size(basis_null, 2)
                d_res >= 1 || throw(ArgumentError("no residual degrees of freedom remain for LLTM facet $fname"))
                r_prior = is_bayesian ? _parse_scale_or_lognormal(res_spec, true, Symbol(:lltm_residual_, fname)) :
                    (; kind = :fixed, sd = 1.0, logmean = 0.0, logsd = 1.0)
                iso_r = sqrt(Float64(L_f) / Float64(d_res))
                res_erng = (eta_cursor + 1):(eta_cursor + d_res)
                res_rrng = (raw_cursor + 1):(raw_cursor + d_res)
                res_sd_num = r_prior.sd
                # Map both W_mat * eta_lltm and basis_null * eta_res into reconstructed facet difficulties!
                f_mrng = (mod_cursor + 1):(mod_cursor + L_f)
                for m_idx in 1:M_feat, r in 1:L_f
                    v = W_mat[r, m_idx]
                    v == 0.0 && continue
                    push!(J_rows, mod_cursor + r); push!(J_cols, w_erng[m_idx]); push!(J_vals, v)
                end
                for c in 1:d_res, r in 1:L_f
                    v = basis_null[r, c]
                    v == 0.0 && continue
                    push!(J_rows, mod_cursor + r); push!(J_cols, eta_cursor + c); push!(J_vals, v)
                end
                append!(xi0_model, zeros(Float64, L_f))
                append!(free_names, ["$(fname).lltm_residual[$c]" for c in 1:d_res])
                append!(model_names, ["$(fname)[$(repr(x))]" for x in fb.levels])
                if is_bayesian
                    push!(pending_blocks, (;
                        name = Symbol(fname, :_lltm_residual),
                        kind = r_prior.kind === :lognormal ? :hierarchical_lognormal : :white_scaled,
                        eta_range = res_erng, model_range = f_mrng, raw_range = res_rrng,
                        mu = zeros(Float64, d_res), scale_vec = fill(r_prior.sd * iso_r, d_res),
                        chol_L = zeros(Float64, 0, 0), iso_factor = iso_r, marginal_sd = r_prior.sd,
                        logmean = r_prior.logmean, logsd = r_prior.logsd,
                    ))
                end
                push!(block_meta, (; name = fname, kind = :facet_lltm_plus_residual, levels = deepcopy(fb.levels),
                    eta_range = res_erng, model_range = f_mrng, check_exchangeable_symmetry = false))
                eta_cursor += d_res
                mod_cursor += L_f
                raw_cursor += d_res
            else
                # Strict LLTM: reconstructed facet difficulties are deterministic linear combinations W_mat * eta_lltm
                f_mrng = (mod_cursor + 1):(mod_cursor + L_f)
                for m_idx in 1:M_feat, r in 1:L_f
                    v = W_mat[r, m_idx]
                    v == 0.0 && continue
                    push!(J_rows, mod_cursor + r); push!(J_cols, w_erng[m_idx]); push!(J_vals, v)
                end
                append!(xi0_model, zeros(Float64, L_f))
                append!(model_names, ["$(fname)[$(repr(x))]" for x in fb.levels])
                push!(block_meta, (; name = fname, kind = :facet_lltm_strict, levels = deepcopy(fb.levels),
                    eta_range = w_erng, model_range = f_mrng, check_exchangeable_symmetry = false))
                mod_cursor += L_f
            end
            push!(af_blocks, Block(fname, fb.column, deepcopy(fb.levels), copy(fb.index), res_sd_num, res_sd_num, res_rrng))
        end
    end

    # Map facet name -> reconstructed model_range for row linear-predictor assembly
    facet_mod_ranges = Dict{Symbol,UnitRange{Int}}()
    for bm in block_meta
        if bm.kind in (:facet_main, :facet_lltm_strict, :facet_lltm_plus_residual)
            facet_mod_ranges[bm.name] = bm.model_range
        end
    end

    # 2) Baseline step blocks (one zero-sum step vector per group in `group_levels`)
    hs = length.(supports) .- 1
    step_blocks = [_calibration_block(categories[sup][2:end], get(fixed_steps, group_levels[g], nothing),
        true, "steps for $(repr(group_levels[g]))") for (g,sup) in enumerate(supports)]
    step_p = if is_bayesian
        _parse_scale_or_lognormal(prior_sd.step, any(b -> size(b[2],2)>0, step_blocks), :step_sd)
    else
        (; kind = :fixed, sd = 1.0, logmean = 0.0, logsd = 1.0)
    end
    step_mod_ranges = Vector{UnitRange{Int}}(undef, length(supports))
    for (g, sup) in enumerate(supports)
        H_g = length(sup) - 1
        base_g, C_g, _ = step_blocks[g]
        d_g = size(C_g,2)
        iso_g = H_g > 1 ? sqrt(Float64(H_g) / Float64(H_g - 1)) : 0.0
        erng = (eta_cursor + 1):(eta_cursor + d_g)
        mrng = (mod_cursor + 1):(mod_cursor + H_g)
        rrng = (raw_cursor + 1):(raw_cursor + d_g)
        step_mod_ranges[g] = mrng
        for c in 1:d_g, r in 1:H_g
            v = C_g[r, c]
            v == 0.0 && continue
            push!(J_rows, mod_cursor + r); push!(J_cols, eta_cursor + c); push!(J_vals, v)
        end
        append!(xi0_model, base_g)
        g_lbl = group_levels[g]
        append!(free_names, ["steps[$(repr(g_lbl))].contrast[$c]" for c in 1:d_g])
        step_labels = isnothing(fixed_calibration) ? (1:H_g) : categories[sup][2:end]
        s_mnames = ["steps[$(repr(g_lbl)),$h]" for h in step_labels]
        append!(model_names, s_mnames)
        union!(fixed_model_names, s_mnames[vec(all(iszero,C_g; dims=2))])
        if is_bayesian && d_g > 0
            push!(pending_blocks, (;
                name = Symbol("steps_", g),
                kind = step_p.kind === :lognormal ? :hierarchical_lognormal : :white_scaled,
                eta_range = erng, model_range = mrng, raw_range = rrng,
                mu = zeros(Float64, d_g), scale_vec = fill(step_p.sd * iso_g, d_g),
                chol_L = zeros(Float64, 0, 0), iso_factor = iso_g, marginal_sd = step_p.sd,
                logmean = step_p.logmean, logsd = step_p.logsd,
            ))
        end
        push!(block_meta, (; name = Symbol("steps[$(repr(g_lbl))]"), kind = :steps, group_level = deepcopy(g_lbl),
            eta_range = erng, model_range = mrng, check_exchangeable_symmetry = true))
        eta_cursor += d_g
        mod_cursor += H_g
        raw_cursor += d_g
    end

    # 3) Structured 2-way interactions (`facet × facet` and `facet × step`)
    int_model_records = NamedTuple[]
    for ispec in int_specs
        if ispec.kind === :facet_facet
            b1 = f_lookup[ispec.f1]
            b2 = f_lookup[ispec.f2]
            L1, L2 = length(b1.levels), length(b2.levels)
            K = _kronecker_helmert_matrix(L1,L2)
            unrestricted_df = size(K,2)
            pair = (ispec.f1,ispec.f2)
            anchored = !isnothing(cells) && haskey(cells,pair)
            base, C_kr = anchored ? _interaction_calibration_block(K,b1,b2,cells[pair],cell_anchors) :
                                    (zeros(L1*L2),K)
            d_int = size(C_kr,2)
            if anchored
                push!(cell_dimensions,(;facets=pair,locations=L1*L2,centered_df=unrestricted_df,
                    anchor_rank=unrestricted_df-d_int,free_df=d_int))
            end
            active = d_int > 0
            ip = if is_bayesian
                ispec.prior !== nothing ||
                    throw(ArgumentError("Bayesian interaction ($(ispec.f1), $(ispec.f2)) requires a prior SD or LogNormal hyperprior in `prior_sd.interactions` or inline"))
                _parse_scale_or_lognormal(ispec.prior, active, ispec.key)
            else
                (; kind = :fixed, sd = 1.0, logmean = 0.0, logsd = 1.0)
            end
            iso_kr = active ? sqrt(Float64(L1 * L2) / unrestricted_df) : 0.0
            erng = (eta_cursor + 1):(eta_cursor + d_int)
            mrng = (mod_cursor + 1):(mod_cursor + L1 * L2)
            rrng = (raw_cursor + 1):(raw_cursor + d_int)
            for c in 1:d_int, r in 1:(L1 * L2)
                v = C_kr[r, c]
                abs(v) <= 1e-16 && continue
                push!(J_rows, mod_cursor + r); push!(J_cols, eta_cursor + c); push!(J_vals, v)
            end
            append!(xi0_model, base)
            append!(free_names, ["interaction[$(ispec.f1),$(ispec.f2)].contrast[$c]" for c in 1:d_int])
            inames = ["interaction[$(ispec.f1),$(ispec.f2)][$(repr(l1)),$(repr(l2))]"
                for l1 in b1.levels for l2 in b2.levels]
            append!(model_names, inames)
            union!(fixed_model_names,inames[vec(all(iszero,C_kr;dims=2))])
            if is_bayesian && active
                push!(pending_blocks, (;
                    name = ispec.key,
                    kind = ip.kind === :lognormal ? :hierarchical_lognormal : :white_scaled,
                    eta_range = erng, model_range = mrng, raw_range = rrng,
                    mu = zeros(Float64, d_int), scale_vec = fill(ip.sd * iso_kr, d_int),
                    chol_L = zeros(Float64, 0, 0), iso_factor = iso_kr, marginal_sd = anchored ? NaN : ip.sd,
                    logmean = ip.logmean, logsd = ip.logsd,
                ))
            end
            push!(block_meta, (; name = ispec.key, kind = :facet_facet_interaction,
                f1 = ispec.f1, f2 = ispec.f2, levels1 = deepcopy(b1.levels), levels2 = deepcopy(b2.levels),
                eta_range = erng, model_range = mrng, check_exchangeable_symmetry = !anchored))
            push!(int_model_records, (; kind = :facet_facet, f1 = ispec.f1, f2 = ispec.f2,
                L1, L2, idx1 = b1.index, idx2 = b2.index, model_range = mrng))
            eta_cursor += d_int
            mod_cursor += L1 * L2
            raw_cursor += d_int
        else
            # `facet × step` category-use interaction (`rater:step`)
            all(==(first(hs)), hs) ||
                throw(ArgumentError("`($(ispec.f1), :step)` interaction requires uniform category counts across step groups"))
            H = first(hs)
            H >= 2 || throw(ArgumentError("`($(ispec.f1), :step)` interaction requires at least 3 categories (H >= 2 steps)"))
            b1 = f_lookup[ispec.f1]
            L1 = length(b1.levels)
            d_int = max(L1 - 1, 0) * (H - 1)
            active = d_int > 0
            ip = if is_bayesian
                ispec.prior !== nothing ||
                    throw(ArgumentError("Bayesian step interaction ($(ispec.f1), :step) requires a prior SD or LogNormal hyperprior in `prior_sd.interactions` or inline"))
                _parse_scale_or_lognormal(ispec.prior, active, ispec.key)
            else
                (; kind = :fixed, sd = 1.0, logmean = 0.0, logsd = 1.0)
            end
            C_kr = _kronecker_helmert_matrix(L1, H)
            iso_kr = active ? sqrt(Float64(L1 * H) / Float64(d_int)) : 0.0
            erng = (eta_cursor + 1):(eta_cursor + d_int)
            mrng = (mod_cursor + 1):(mod_cursor + L1 * H)
            rrng = (raw_cursor + 1):(raw_cursor + d_int)
            for c in 1:d_int, r in 1:(L1 * H)
                v = C_kr[r, c]
                abs(v) <= 1e-16 && continue
                push!(J_rows, mod_cursor + r); push!(J_cols, eta_cursor + c); push!(J_vals, v)
            end
            append!(xi0_model, zeros(Float64, L1 * H))
            append!(free_names, ["step_interaction[$(ispec.f1)].contrast[$c]" for c in 1:d_int])
            inames = ["step_interaction[$(ispec.f1)][$(repr(l1)),$h]" for l1 in b1.levels for h in 1:H]
            append!(model_names, inames)
            !active && foreach(nm -> push!(fixed_model_names, nm), inames)
            if is_bayesian && active
                push!(pending_blocks, (;
                    name = ispec.key,
                    kind = ip.kind === :lognormal ? :hierarchical_lognormal : :white_scaled,
                    eta_range = erng, model_range = mrng, raw_range = rrng,
                    mu = zeros(Float64, d_int), scale_vec = fill(ip.sd * iso_kr, d_int),
                    chol_L = zeros(Float64, 0, 0), iso_factor = iso_kr, marginal_sd = ip.sd,
                    logmean = ip.logmean, logsd = ip.logsd,
                ))
            end
            push!(block_meta, (; name = ispec.key, kind = :facet_step_interaction,
                f1 = ispec.f1, levels1 = deepcopy(b1.levels), n_steps = H,
                eta_range = erng, model_range = mrng, check_exchangeable_symmetry = true))
            push!(int_model_records, (; kind = :facet_step, f1 = ispec.f1,
                L1, H, idx1 = b1.index, model_range = mrng))
            eta_cursor += d_int
            mod_cursor += L1 * H
            raw_cursor += d_int
        end
    end

    if !isnothing(intercept)
        par = _normal_parameters(intercept, "intercept")
        eta_cursor += 1
        mod_cursor += 1
        raw_cursor += 1
        push!(xi0_model, 0.0)
        push!(free_names,"population_mean")
        push!(model_names,"population_mean")
        push!(J_rows, mod_cursor); push!(J_cols, eta_cursor); push!(J_vals, 1.0)
        er = eta_cursor:eta_cursor
        mr = mod_cursor:mod_cursor
        push!(block_meta,(;name=:population_mean, kind=:population_mean, eta_range=er,
            model_range=mr, check_exchangeable_symmetry=false))
        push!(pending_blocks,(;name=:population_mean, kind=:white_scaled, eta_range=er,
            model_range=mr, raw_range=raw_cursor:raw_cursor, mu=[par.mean], scale_vec=[par.sd],
            chol_L=zeros(0,0), iso_factor=1.0, marginal_sd=par.sd, logmean=0.0, logsd=0.0))
    end

    external_columns = 1:0
    if !isnothing(transfer)
        mapping = _calibration_map(transfer.coordinates, model_names, group_levels, supports, categories)
        if is_bayesian
            :transferred_calibration in (b.name for b in pending_blocks) &&
                throw(ArgumentError("transferred_calibration is reserved for the Gaussian calibration block"))
            n_cal = size(mapping,2)
            external_columns = eta_cursor+1:eta_cursor+n_cal
            ri,ci,vv = findnz(mapping)
            append!(J_rows,ri); append!(J_cols,eta_cursor .+ ci); append!(J_vals,vv)
            setdiff!(fixed_model_names,model_names[unique(ri)])
            for i in eachindex(block_meta)
                bm = block_meta[i]
                if any(in(bm.model_range),ri)
                    block_meta[i] = merge(bm,(;check_exchangeable_symmetry=false,
                        variance_source=:includes_external_calibration))
                end
            end
            append!(free_names,["calibration_shift[$i]" for i in 1:n_cal])
            push!(pending_blocks,(;name=:transferred_calibration,kind=:mvnormal,eta_range=external_columns,
                model_range=1:mod_cursor,raw_range=raw_cursor+1:raw_cursor+n_cal,mu=zeros(n_cal),
                chol_L=Matrix(cholesky(Symmetric(transfer.covariance)).L),scale_vec=Float64[],
                iso_factor=1.,marginal_sd=0.,logmean=0.,logsd=0.))
            eta_cursor += n_cal
            raw_cursor += n_cal
        end
    end

    # Assign hyper_idx positions at the end of `q` for any hierarchical LogNormal SDs
    p_hyper_idx = 0
    if is_bayesian && p_is_hyper
        raw_cursor += 1
        p_hyper_idx = raw_cursor
    end
    final_prior_blocks = MRCMLPriorBlock[]
    for pb in pending_blocks
        hidx = 0
        if pb.kind === :hierarchical_lognormal
            raw_cursor += 1
            hidx = raw_cursor
        end
        push!(final_prior_blocks, MRCMLPriorBlock(
            pb.name, pb.kind, pb.eta_range, pb.model_range, pb.raw_range, hidx,
            pb.mu, pb.scale_vec, pb.chol_L, pb.iso_factor, pb.marginal_sd, pb.logmean, pb.logsd,
        ))
    end

    J_model = sparse(J_rows, J_cols, J_vals, mod_cursor, eta_cursor)
    dropzeros!(J_model)

    # Assemble per-row category log-weight entries in model coordinates:
    # ell_{n, lk} = (lk - 1) * theta_p - (lk - 1) * sum_f beta_{f, idx(n)} - sum_{h=1}^{lk-1} tau_{g(n), h}
    #              - (lk - 1) * sum_{(f1,f2)} gamma_{i1, i2} - sum_{(f1,step)} sum_{h=1}^{lk-1} delta_{i1, h}
    row_B = Vector{Vector{Float64}}(undef, n)
    row_c0 = Vector{Vector{Float64}}(undef, n)
    row_A_ents = Vector{Vector{Tuple{Int,Int,Float64}}}(undef, n)

    for i in 1:n
        g = group[i]
        M_g = length(supports[g])
        row_B[i] = Float64[k - 1 for k in 1:M_g]
        row_c0[i] = zeros(Float64, M_g)
        ents = Tuple{Int,Int,Float64}[]
        for fb in f_info
            f_mrng = facet_mod_ranges[fb.name]
            mcol = f_mrng[fb.index[i]]
            for lk in 2:M_g
                push!(ents, (lk, mcol, -Float64(lk - 1)))
            end
        end
        if !isnothing(intercept)
            for lk in 2:M_g
                push!(ents, (lk, mod_cursor, Float64(lk - 1)))
            end
        end
        s_mrng = step_mod_ranges[g]
        for lk in 2:M_g
            for h in 1:(lk - 1)
                push!(ents, (lk, s_mrng[h], -1.0))
            end
        end
        for irec in int_model_records
            if irec.kind === :facet_facet
                cell_col = irec.model_range[(irec.idx1[i] - 1) * irec.L2 + irec.idx2[i]]
                for lk in 2:M_g
                    push!(ents, (lk, cell_col, -Float64(lk - 1)))
                end
            else
                base_off = (irec.idx1[i] - 1) * irec.H
                for lk in 2:M_g
                    for h in 1:(lk - 1)
                        push!(ents, (lk, irec.model_range[base_off + h], -1.0))
                    end
                end
            end
        end
        row_A_ents[i] = ents
    end

    op = _compress_mrcml_patterns(
        n, group, supports, row_B, row_c0, row_A_ents,
        mod_cursor, xi0_model, J_model, free_names, model_names, fixed_model_names, block_meta,
    )

    columns = (; person, score, facets, performance, assessment)
    grouping = _groups(raw, columns, p_idx, af_blocks)
    category_levels isa AbstractDict && (grouping = merge(grouping, (; category_support_by_owner = true)))

    # If any LLTM block has `center = false`, its uncentered column spans the global intercept -> `:zero_mean_population`
    has_uncentered_lltm = any(bm -> bm.kind === :lltm_weights && !bm.centered, block_meta)
    loc_mode = has_uncentered_lltm || !isnothing(intercept) ? :zero_mean_population : :finite_connected
    n_hyp = (p_hyper_idx > 0 ? 1 : 0) + count(b -> b.hyper_idx > 0, final_prior_blocks)

    alloc = _mrcml_allocation(p_idx, p_levels, af_blocks, op, loc_mode; n_hyper = n_hyp, external_columns)
    spec_rec = (; source = :structured_mfrm_spec, steps, has_interactions = interactions !== nothing, has_lltm = lltm !== nothing)

    if !isnothing(transfer)
        spec_rec = merge(spec_rec,(;calibration=transfer, external_columns, population_intercept=!isnothing(intercept)))
    elseif !isnothing(fixed_calibration)
        anchors = NamedTuple[]
        for fb in f_info
            vals = get(fixed_facets, fb.name, nothing)
            isnothing(vals) && continue
            for level in fb.levels
                haskey(vals,level) && push!(anchors,(; kind=:hard, block=fb.name, level, value=Float64(vals[level])))
            end
        end
        for (g,level) in enumerate(group_levels)
            haskey(fixed_steps,level) || continue
            vals = fixed_steps[level]
            for upper_category in categories[supports[g]][2:end]
                haskey(vals,upper_category) && push!(anchors,(; kind=:step, block=:steps,
                    owner=steps, level, upper_category, value=Float64(vals[upper_category])))
            end
        end
        append!(anchors,cell_anchors)
        receipt = (; anchors, uncertainty=:conditional_on_fixed_calibration)
        isempty(cell_dimensions) || (receipt=merge(receipt,(;interaction_dimensions=cell_dimensions)))
        if !isempty(groups)
            receipt = merge(receipt,(;groups=group_receipt, dimensions=group_dimensions))
        end
        spec_rec = merge(spec_rec, (; fixed_calibration=receipt,
            population_intercept=!isnothing(intercept)))
    end
    if !is_bayesian
        f_tuples = [(; name = b.name, column = b.column, levels = deepcopy(b.levels), index = copy(b.index)) for b in af_blocks]
        return MRCMLSpec(raw, columns, p_idx, p_levels, cat, categories, supports, f_tuples,
            owner_sym, steps, group, group_levels, op, loc_mode, alloc, grouping, spec_rec)
    end

    sym = _mrcml_audit_prior_symmetry(op, final_prior_blocks)
    return MRCMLTarget(
        raw, columns, p_idx, p_levels, cat, categories, supports, af_blocks,
        owner_sym, steps, group, group_levels, p_sd_val, p_hyper_idx, p_logmean, p_logsd,
        op, final_prior_blocks, raw_cursor, loc_mode, alloc, sym, grouping, spec_rec,
    )
end

# ---------------------------------------------------------------------------
# 6. Layer-2 Glass-Box `MRCML` Submodule (Custom `A`, `TAM` & ConQuest Bridges)
# ---------------------------------------------------------------------------

module MRCML
import ..AdditiveFacets as AF
import BayesianMGMFRM as B
import Distributions as D
using LinearAlgebra, SparseArrays, Statistics

const Target = AF.MRCMLTarget
const Spec = AF.MRCMLSpec
const Operator = AF.MRCMLOperator

helmert_basis(J::Int) = AF._helmert_matrix(J)
kronecker_isometric_basis(J1::Int, J2::Int) = AF._kronecker_helmert_matrix(J1, J2)
subspace_isometric_prior(M::AbstractMatrix{<:Real}, sd::Real) = AF._subspace_isometric_prior(M, sd)
stan_code() = AF.MRCML_STAN_CODE
stan_code(::Nothing) = stan_code()
stan_code(t::Target) = hasproperty(t.spec_record,:population) ? AF._mrcml_stan_code(true) : stan_code()

function _extract_operator(x)
    x isa Target && return x.operator
    x isa Spec && return x.operator
    x isa AF.Fit && AF.checked(x) isa Target && return AF.checked(x).operator
    throw(ArgumentError("expected an MRCMLTarget, MRCMLSpec, or fitted MRCML AdditiveFacets.Fit; got $(typeof(x))"))
end

"""
    MRCML.design_matrices(spec_or_fit)

Inspect the exact compressed sparse MRCML representation `(A_pattern, A_model,
B_pattern, offset_pattern, J_model, xi0_model, pattern_of_row, pattern_ranges,
free_names, model_names, prior_symmetry)` for Layer-2 research and external parity checks.
"""
function design_matrices(x)
    if x isa AF.Fit && AF.checked(x) isa Target
        return design_matrices(AF.checked(x))
    elseif x isa Target
        op = x.operator
        return (;
            A_pattern = copy(op.A_free),
            A_model = copy(op.A_model),
            B_pattern = copy(op.B_pat),
            offset_pattern = copy(op.c_pat),
            base_offset_pattern = copy(op.c0_pat),
            xi0_model = copy(op.xi0_model),
            J_model = copy(op.J_model),
            pattern_of_row = copy(op.pattern_of_row),
            pattern_ranges = copy(op.pattern_ranges),
            free_names = copy(op.free_names),
            model_names = copy(op.model_names),
            fixed_model_names = sort!(collect(op.fixed_model_names)),
            location_mode = x.location_mode,
            allocation = deepcopy(x.allocation),
            prior_symmetry = deepcopy(x.prior_symmetry),
        )
    elseif x isa Spec
        op = x.operator
        return (;
            A_pattern = copy(op.A_free),
            A_model = copy(op.A_model),
            B_pattern = copy(op.B_pat),
            offset_pattern = copy(op.c_pat),
            base_offset_pattern = copy(op.c0_pat),
            xi0_model = copy(op.xi0_model),
            J_model = copy(op.J_model),
            pattern_of_row = copy(op.pattern_of_row),
            pattern_ranges = copy(op.pattern_ranges),
            free_names = copy(op.free_names),
            model_names = copy(op.model_names),
            fixed_model_names = sort!(collect(op.fixed_model_names)),
            location_mode = x.location_mode,
            allocation = deepcopy(x.allocation),
            prior_symmetry = nothing,
        )
    end
    throw(ArgumentError("MRCML.design_matrices requires an MRCMLTarget, MRCMLSpec, or MRCML Fit; got $(typeof(x))"))
end

function _parse_xsi_fixed(xsi_fixed, n_pars::Int)
    fixed_vals = fill(NaN, n_pars)
    xsi_fixed === nothing && return fixed_vals
    if xsi_fixed isa AbstractMatrix
        size(xsi_fixed, 2) == 2 ||
            throw(ArgumentError("matrix `xsi_fixed` must have 2 columns `[par_index value]` (TAM convention)"))
        for r in axes(xsi_fixed, 1)
            idx_r = xsi_fixed[r, 1]
            val_r = xsi_fixed[r, 2]
            idx = Int(round(Float64(idx_r)))
            abs(Float64(idx_r) - idx) <= 1e-12 && 1 <= idx <= n_pars ||
                throw(ArgumentError("xsi_fixed parameter index $idx_r outside 1:$n_pars"))
            isfinite(val_r) || throw(ArgumentError("xsi_fixed value at index $idx must be finite"))
            !isnan(fixed_vals[idx]) && fixed_vals[idx] != Float64(val_r) &&
                throw(ArgumentError("conflicting duplicate xsi_fixed entries for index $idx"))
            fixed_vals[idx] = Float64(val_r)
        end
    elseif xsi_fixed isa AbstractDict || xsi_fixed isa AbstractVector{<:Pair}
        for (k, v) in (xsi_fixed isa AbstractDict ? pairs(xsi_fixed) : xsi_fixed)
            idx = Int(k)
            1 <= idx <= n_pars || throw(ArgumentError("xsi_fixed parameter index $idx outside 1:$n_pars"))
            v isa Real && !(v isa Bool) && isfinite(v) ||
                throw(ArgumentError("xsi_fixed value for index $idx must be finite"))
            fixed_vals[idx] = Float64(v)
        end
    else
        throw(ArgumentError("xsi_fixed must be `nothing`, a 2-column matrix `[index value]`, a `Dict(index => value)`, or `Vector{Pair}`"))
    end
    return fixed_vals
end

function _build_custom_prior_blocks(prior, d_free::Int, raw_start::Int, block_name::Symbol = :xsi)
    d_free == 0 && return (AF.MRCMLPriorBlock[], raw_start)
    if prior isa D.Normal
        np = AF._normal_parameters(prior, "prior")
        erng = 1:d_free
        rrng = (raw_start + 1):(raw_start + d_free)
        blk = AF.MRCMLPriorBlock(block_name, :white_scaled, erng, erng, rrng, 0,
            fill(np.mean, d_free), fill(np.sd, d_free), zeros(Float64, 0, 0), 1.0, np.sd, 0.0, 1.0)
        return ([blk], raw_start + d_free)
    elseif prior isa AbstractVector{<:D.Normal}
        length(prior) == d_free ||
            throw(DimensionMismatch("vector `prior` length $(length(prior)) != $d_free free structural parameters"))
        mus = Float64[first(D.params(p)) for p in prior]
        sds = Float64[last(D.params(p)) for p in prior]
        all(isfinite, mus) && all(s -> isfinite(s) && s > 0, sds) ||
            throw(ArgumentError("all Normal priors must have finite mean and positive sd"))
        erng = 1:d_free
        rrng = (raw_start + 1):(raw_start + d_free)
        blk = AF.MRCMLPriorBlock(block_name, :white_scaled, erng, erng, rrng, 0,
            mus, sds, zeros(Float64, 0, 0), 1.0, allequal(sds) ? first(sds) : NaN, 0.0, 1.0)
        return ([blk], raw_start + d_free)
    elseif prior isa D.AbstractMvNormal
        length(prior) == d_free ||
            throw(DimensionMismatch("MvNormal `prior` length $(length(prior)) != $d_free free structural parameters"))
        mu = Float64.(mean(prior))
        Sig = Symmetric(Matrix{Float64}(D.cov(prior)))
        all(isfinite, mu) && all(isfinite, Sig) || throw(ArgumentError("MvNormal parameters must be finite"))
        L_c = Matrix(cholesky(Sig).L)
        erng = 1:d_free
        rrng = (raw_start + 1):(raw_start + d_free)
        blk = AF.MRCMLPriorBlock(block_name, :mvnormal, erng, erng, rrng, 0,
            mu, Float64[], L_c, 1.0, NaN, 0.0, 1.0)
        return ([blk], raw_start + d_free)
    elseif prior isa D.LogNormal
        lp = AF._parse_scale_or_lognormal(prior, true, :prior)
        erng = 1:d_free
        rrng = (raw_start + 1):(raw_start + d_free)
        hidx = raw_start + d_free + 1
        blk = AF.MRCMLPriorBlock(block_name, :hierarchical_lognormal, erng, erng, rrng, hidx,
            zeros(Float64, d_free), Float64[], zeros(Float64, 0, 0), 1.0, NaN, lp.logmean, lp.logsd)
        return ([blk], hidx)
    end
    throw(ArgumentError("unsupported custom MRCML `prior` $(typeof(prior)); supply `Normal(mu, sd)`, `Vector{Normal}`, `MvNormal`, `LogNormal` hyperprior, or `nothing` for frequentist estimation"))
end

"""
    MRCML.custom_spec(table; person, score, category_levels, A, B=nothing, offset=nothing,
                      item_index=nothing, facets=(;), xsi_fixed=nothing, parameter_names=nothing,
                      model_transform=nothing, model_names=nothing, block_meta=nothing,
                      prior=nothing, person_prior_sd=nothing, location_mode=:zero_mean_population)

Construct a Layer-2 Glass-Box MRCML specification directly from a 3D design array
`A` (`n_obs × K × P_par`, or `n_gitems × K × P_par` with `item_index` of length `n_obs`),
optional scoring matrix `B` (`n_obs_or_gitems × K`), optional fixed offset (`offset`)
and/or `TAM`-style fixed parameter constraints (`xsi_fixed`).

When `prior` and `person_prior_sd` are supplied, returns a Bayesian `MRCMLTarget`
(usable with both `fit(spec; chains=..., ...)` and `fit(spec; method=:mmle | :jmle)`).
When `prior === nothing`, returns a prior-free `MRCMLSpec` for `:mmle` / `:jmle`.
"""
function custom_spec(table;
        person::Symbol,
        score::Symbol,
        category_levels,
        A::AbstractArray{<:Real,3},
        B_scores::Union{Nothing,AbstractArray{<:Real}} = nothing,
        B::Union{Nothing,AbstractArray{<:Real}} = B_scores,
        offset::Union{Nothing,AbstractMatrix{<:Real}} = nothing,
        item_index::Union{Nothing,AbstractVector{<:Integer}} = nothing,
        facets::NamedTuple = (;),
        xsi_fixed = nothing,
        parameter_names::Union{Nothing,AbstractVector{<:AbstractString}} = nothing,
        model_transform::Union{Nothing,AbstractMatrix{<:Real}} = nothing,
        model_offset::Union{Nothing,AbstractVector{<:Real}} = nothing,
        model_names::Union{Nothing,AbstractVector{<:AbstractString}} = nothing,
        block_meta::Union{Nothing,AbstractVector{<:NamedTuple}} = nothing,
        prior = nothing,
        person_prior_sd = nothing,
        location_mode::Symbol = :zero_mean_population,
        levels = nothing)
    location_mode in (:finite_connected, :zero_mean_population) ||
        throw(ArgumentError("location_mode must be :finite_connected or :zero_mean_population"))
    selected = unique(Symbol[person, score, values(facets)...])
    raw = Dict{Symbol,Vector}(c => deepcopy(AF.B._column(table, c)) for c in selected)
    n = length(raw[score])
    n > 0 || throw(ArgumentError("ratings cannot be empty"))
    for (c, x) in raw
        AF.B._check_length!(n, x, c)
        c == score || AF._labels(x, c)
    end
    p_idx, p_levels = AF._labels(raw[person], :person, levels === nothing ? nothing : levels.person)
    P = length(p_levels)

    group = ones(Int, n)
    group_levels = Any[:global]
    cat, categories, supports = AF._category_support(raw[score], score, category_levels, :global, group, group_levels)
    K = length(categories)

    n_A1, n_AK, n_pars = size(A)
    n_AK == K || throw(DimensionMismatch("size(A, 2) = $n_AK must equal length(category_levels) = $K"))
    all(isfinite, A) || throw(ArgumentError("design array `A` cannot contain NaN/Inf; encode missing categories via support"))
    gidx = if item_index === nothing
        n_A1 == n || throw(DimensionMismatch("size(A, 1) = $n_A1 must equal n_observations = $n when `item_index` is omitted"))
        collect(1:n)
    else
        length(item_index) == n || throw(DimensionMismatch("length(item_index) = $(length(item_index)) != $n"))
        all(ix -> 1 <= ix <= n_A1, item_index) || throw(ArgumentError("item_index entries outside 1:$n_A1"))
        Int.(item_index)
    end

    B_mat = if B === nothing
        repeat(reshape(Float64[k - 1 for k in 1:K], 1, K), n_A1, 1)
    elseif ndims(B) == 2
        size(B) == (n_A1, K) || throw(DimensionMismatch("2D `B` must have size ($n_A1, $K); got $(size(B))"))
        Float64.(B)
    elseif ndims(B) == 3
        size(B, 1) == n_A1 && size(B, 2) == K && size(B, 3) == 1 ||
            throw(DimensionMismatch("3D `B` must have size ($n_A1, $K, 1) for 1D MRCML; got $(size(B))"))
        Float64.(B[:, :, 1])
    else
        throw(ArgumentError("`B` must be nothing, a 2D matrix, or a 3D `(n_items, K, 1)` array"))
    end
    all(isfinite, B_mat) || throw(ArgumentError("scoring matrix `B` must be finite"))

    off_mat = if offset === nothing
        zeros(Float64, n_A1, K)
    else
        size(offset) == (n_A1, K) || throw(DimensionMismatch("`offset` must have size ($n_A1, $K); got $(size(offset))"))
        all(isfinite, offset) || throw(ArgumentError("`offset` must be finite"))
        Float64.(offset)
    end

    pnames_in = parameter_names === nothing ? ["xsi[$j]" for j in 1:n_pars] : String.(parameter_names)
    length(pnames_in) == n_pars && allunique(pnames_in) ||
        throw(ArgumentError("parameter_names must provide $n_pars distinct names"))

    fixed_vec = _parse_xsi_fixed(xsi_fixed, n_pars)
    free_cols = [j for j in 1:n_pars if isnan(fixed_vec[j])]
    d_free = length(free_cols)

    # Map free columns -> n_pars raw `A` parameters -> optional expanded `model_transform`
    xi_raw0 = [isnan(fixed_vec[j]) ? 0.0 : fixed_vec[j] for j in 1:n_pars]
    J_raw = sparse(free_cols, collect(1:d_free), ones(Float64, d_free), n_pars, d_free)

    xi0_mod, J_mod, mod_names, fixed_mod_set = if model_transform === nothing
        fset = Set{String}([pnames_in[j] for j in 1:n_pars if !isnan(fixed_vec[j])])
        (xi_raw0, J_raw, pnames_in, fset)
    else
        size(model_transform, 2) == n_pars ||
            throw(DimensionMismatch("size(model_transform, 2) = $(size(model_transform, 2)) != $n_pars"))
        M_tr = sparse(Float64.(model_transform))
        n_mod = size(M_tr, 1)
        m_off = model_offset === nothing ? zeros(Float64, n_mod) : Float64.(model_offset)
        length(m_off) == n_mod || throw(DimensionMismatch("length(model_offset) != $n_mod"))
        mnames = model_names === nothing ? ["model[$i]" for i in 1:n_mod] : String.(model_names)
        length(mnames) == n_mod && allunique(mnames) ||
            throw(ArgumentError("model_names must have $n_mod distinct names"))
        Jm = M_tr * J_raw
        dropzeros!(Jm)
        # Any model row with zero row-norm in Jm is structurally fixed!
        rnorms = vec(sum(abs2, Jm; dims = 2))
        fset = Set{String}([mnames[i] for i in 1:n_mod if rnorms[i] == 0.0])
        (m_off .+ Vector{Float64}(M_tr * xi_raw0), Jm, mnames, fset)
    end

    # Notice A_model acts on `model_names` when model_transform === nothing, else we keep A_raw on n_pars
    # Wait: to satisfy A_free == A_model * J_model AND c_pat == c0 + A_model * xi0_model even when
    # model_transform expands parameters (e.g. from 2 raters to 3 raters), if model_transform !== nothing
    # we append the expanded coordinates after `pnames_in` OR represent A_model directly on `xi0_mod`
    # when A_raw factors through model_transform! Even simpler & always exact:
    # When model_transform !== nothing, keep `n_pars` primary A columns AND if model_transform is supplied,
    # test whether `A` is already defined on `n_pars`: we fold `xsi_fixed` into `c0_row` for any extra
    # transformation, OR store `[pnames_in; expanded]`? Wait: if `model_transform` maps `n_pars -> n_mod`
    # (for instance `TAM` maps `[I1,I2,I3, rater1,rater2]` -> `[I1,I2,I3, rater1,rater2,rater3]`),
    # `pnames_in` IS a subset of `mod_names`, or in general `A_raw` acts on `xi_raw = xi_raw0 + J_raw * eta`.
    # If we include a pseudoinverse / left-inverse or simpler: store `n_pars` or `n_mod`?
    # Look! If `model_transform === nothing`, `A_model` has `n_pars` columns (`J_model = J_raw`, `xi0_model = xi_raw0`).
    # If `model_transform !== nothing`, let's check if `M_tr` has full column rank `n_pars`:
    # `M_pinv = pinv(Matrix(model_transform))` satisfies `M_pinv * M_tr == I_{n_pars}`, so setting
    # `A_model = A_raw * M_pinv` gives `A_model * (M_tr * xi_raw) == A_raw * xi_raw` IDENTICALLY!!
    row_B = [Vector{Float64}(B_mat[gidx[i], :]) for i in 1:n]
    row_c0 = [Vector{Float64}(off_mat[gidx[i], :]) for i in 1:n]
    row_A_ents = Vector{Vector{Tuple{Int,Int,Float64}}}(undef, n)

    if model_transform === nothing
        for i in 1:n
            gi = gidx[i]
            ents = Tuple{Int,Int,Float64}[]
            for lk in 1:K, pcol in 1:n_pars
                v = Float64(A[gi, lk, pcol])
                v == 0.0 || push!(ents, (lk, pcol, v))
            end
            row_A_ents[i] = ents
        end
    else
        M_dense = Float64.(model_transform)
        rank(M_dense) == n_pars ||
            throw(ArgumentError("model_transform must have full column rank $n_pars so A_raw factors uniquely through model coordinates"))
        M_pinv = pinv(M_dense) # n_pars x n_mod, exact left inverse: M_pinv * M_dense == I
        # Subtract M_pinv * m_off from row_c0 so A_model * (m_off + M_dense * xi_raw) == A_raw * xi_raw
        m_off = model_offset === nothing ? zeros(Float64, size(M_dense, 1)) : Float64.(model_offset)
        xi_shift = M_pinv * m_off
        # Precompute A_mod_3d[gi, lk, mcol] = sum_p A[gi, lk, p] * M_pinv[p, mcol]
        n_mod = size(M_dense, 1)
        A_mod_3d = zeros(Float64, n_A1, K, n_mod)
        corr_c0 = zeros(Float64, n_A1, K)
        for gi in 1:n_A1, lk in 1:K
            a_slice = view(A, gi, lk, :)
            corr_c0[gi, lk] = dot(a_slice, xi_shift)
            for mc in 1:n_mod
                s = 0.0
                @inbounds for pc in 1:n_pars
                    s += Float64(a_slice[pc]) * M_pinv[pc, mc]
                end
                abs(s) > 1e-15 && (A_mod_3d[gi, lk, mc] = s)
            end
        end
        for i in 1:n
            gi = gidx[i]
            row_c0[i] .-= view(corr_c0, gi, :)
            ents = Tuple{Int,Int,Float64}[]
            for lk in 1:K, mc in 1:n_mod
                v = A_mod_3d[gi, lk, mc]
                v == 0.0 || push!(ents, (lk, mc, v))
            end
            row_A_ents[i] = ents
        end
    end

    free_names = [pnames_in[j] for j in free_cols]
    bmeta = block_meta === nothing ? NamedTuple[] : collect(NamedTuple, block_meta)
    op = AF._compress_mrcml_patterns(
        n, group, supports, row_B, row_c0, row_A_ents,
        length(mod_names), xi0_mod, J_mod, free_names, mod_names, fixed_mod_set, bmeta,
    )

    f_blocks = AF.Block[]
    f_tuples = NamedTuple[]
    for (fname, fcol) in pairs(facets)
        fidx, flev = AF._labels(raw[fcol], fname, levels === nothing ? nothing : levels.facets[fname])
        push!(f_blocks, AF.Block(fname, fcol, flev, fidx, 0.0, 0.0, 1:0))
        push!(f_tuples, (; name = fname, column = fcol, levels = flev, index = fidx))
    end
    columns = (; person, score, facets, performance = nothing, assessment = nothing)
    grouping = isempty(f_blocks) ?
        (; performance_available = false, assessment_available = false, repeated_performances = 0,
           performance_effect = :absent, conditional_independence = :assumed_not_tested) :
        AF._groups(raw, columns, p_idx, f_blocks)
    spec_rec = (; source = :custom_mrcml_spec, n_raw_pars = n_pars, has_xsi_fixed = xsi_fixed !== nothing)

    if prior === nothing && person_prior_sd === nothing
        alloc = AF._mrcml_allocation(p_idx, p_levels, f_blocks, op, location_mode; n_hyper = 0)
        return Spec(raw, columns, p_idx, p_levels, cat, categories, supports, f_tuples,
            :global, :global, group, group_levels, op, location_mode, alloc, grouping, spec_rec)
    end
    (prior !== nothing && person_prior_sd !== nothing) ||
        throw(ArgumentError("supply both `prior` and `person_prior_sd` for a Bayesian custom MRCML target, or omit both for frequentist estimation"))

    pspec = AF._parse_scale_or_lognormal(person_prior_sd, true, :person_prior_sd)
    pblocks, raw_end = _build_custom_prior_blocks(prior, d_free, P, :xsi)
    p_hyp = 0
    if pspec.kind === :lognormal
        raw_end += 1
        p_hyp = raw_end
    end
    n_hyp = (p_hyp > 0 ? 1 : 0) + count(b -> b.hyper_idx > 0, pblocks)
    alloc = AF._mrcml_allocation(p_idx, p_levels, f_blocks, op, location_mode; n_hyper = n_hyp)
    sym = AF._mrcml_audit_prior_symmetry(op, pblocks)

    return Target(
        raw, columns, p_idx, p_levels, cat, categories, supports, f_blocks,
        :global, :global, group, group_levels, pspec.sd, p_hyp, pspec.logmean, pspec.logsd,
        op, pblocks, raw_end, location_mode, alloc, sym, grouping, spec_rec,
    )
end

"""
    MRCML.from_tam(A, resp; facets=nothing, pid=nothing, B=nothing, xsi_fixed=nothing,
                   parameter_names=nothing, item_names=nothing, category_levels=nothing,
                   model_transform=nothing, model_names=nothing, block_meta=nothing,
                   prior=nothing, person_prior_sd=nothing)

Import a `TAM` (`tam.mml` / `tam.mml.mfr`) 3D design array `A` (`n_gitems × maxK × n_pars`),
optional scoring array `B`, optional 2-column `xsi_fixed` (`[par_index value]`), and a
wide response matrix `resp` (`n_rows × n_items`, where `missing` or `NaN` entries denote
unobserved cells). For multifaceted `tam.mml.mfr` designs where `n_gitems = n_items * n_facet_cells`,
supply `facets` (a NamedTuple of equal-length vectors matching `size(resp, 1)`, ordered identically
to `TAM`'s facet-cell expansion) and `pid` (person IDs of length `size(resp, 1)`).
"""
function from_tam(
        A::AbstractArray{<:Real,3},
        resp::AbstractMatrix;
        facets::Union{Nothing,NamedTuple} = nothing,
        pid::Union{Nothing,AbstractVector} = nothing,
        B::Union{Nothing,AbstractArray{<:Real}} = nothing,
        xsi_fixed = nothing,
        parameter_names::Union{Nothing,AbstractVector{<:AbstractString}} = nothing,
        item_names::Union{Nothing,AbstractVector{<:AbstractString}} = nothing,
        category_levels = nothing,
        model_transform::Union{Nothing,AbstractMatrix{<:Real}} = nothing,
        model_names::Union{Nothing,AbstractVector{<:AbstractString}} = nothing,
        block_meta::Union{Nothing,AbstractVector{<:NamedTuple}} = nothing,
        prior = nothing,
        person_prior_sd = nothing,
        location_mode::Symbol = :zero_mean_population)
    n_rows, n_items = size(resp)
    n_gitems, maxK, _ = size(A)
    inames = item_names === nothing ? ["I$j" for j in 1:n_items] : String.(item_names)
    length(inames) == n_items || throw(DimensionMismatch("length(item_names) != $n_items"))
    pids = pid === nothing ? ["P$i" for i in 1:n_rows] : collect(pid)
    length(pids) == n_rows || throw(DimensionMismatch("length(pid) != $n_rows"))

    # Determine generalized-item index per (row, item_col)
    cell_mult, f_cols_dict, f_levels_list = if facets === nothing || isempty(facets)
        n_gitems == n_items ||
            throw(DimensionMismatch("size(A, 1) = $n_gitems != size(resp, 2) = $n_items; supply `facets` when A is expanded over facet cells"))
        (1, Dict{Symbol,Vector}(), Pair{Symbol,Vector}[])
    else
        f_pairs = Pair{Symbol,Vector}[]
        cm = 1
        for (fk, fv) in pairs(facets)
            length(fv) == n_rows || throw(DimensionMismatch("facet $fk length $(length(fv)) != $n_rows"))
            u_levs = AF.B._stable_levels(fv, fk)
            push!(f_pairs, fk => u_levs)
            cm *= length(u_levs)
        end
        n_gitems == n_items * cm ||
            throw(DimensionMismatch("size(A, 1) = $n_gitems != n_items ($n_items) * facet_cells ($cm)"))
        (cm, Dict{Symbol,Vector}(fk => collect(fv) for (fk, fv) in pairs(facets)), f_pairs)
    end

    # Convert wide `resp` (skipping `missing` / `NaN`) into long rating rows!
    p_long = Any[]
    item_long = String[]
    score_long = Int[]
    gitem_idx_long = Int[]
    extra_facets_long = Dict{Symbol,Vector{Any}}(fk => Any[] for (fk, _) in f_levels_list)

    # Precompute facet linear cell index (1..cell_mult) for each row of `resp`
    # In TAM::tam.mml.mfr (`I1-rater1, I1-rater2, I1-rater3, I2-rater1, ...`), item is outer (slowest) and facets vary fastest!
    f_dims = Tuple(length(last(fp)) for fp in f_levels_list)
    f_lin = isempty(f_dims) ? nothing : LinearIndices(reverse(f_dims))
    f_maps = [Dict(x => idx for (idx, x) in enumerate(last(fp))) for fp in f_levels_list]

    for r in 1:n_rows
        f_cell = if f_lin === nothing
            1
        else
            coords_rev = ntuple(d -> begin
                idx_f = length(f_levels_list) - d + 1
                fk = first(f_levels_list[idx_f])
                f_maps[idx_f][f_cols_dict[fk][r]]
            end, length(f_levels_list))
            f_lin[coords_rev...]
        end
        for ic in 1:n_items
            val = resp[r, ic]
            (ismissing(val) || (val isa AbstractFloat && isnan(val))) && continue
            ival = Int(round(Float64(val)))
            abs(Float64(val) - ival) <= 1e-12 || throw(ArgumentError("non-integer score $val at resp[$r, $ic]"))
            gi = (ic - 1) * cell_mult + f_cell
            push!(p_long, pids[r])
            push!(item_long, inames[ic])
            push!(score_long, ival)
            push!(gitem_idx_long, gi)
            for (fk, _) in f_levels_list
                push!(extra_facets_long[fk], f_cols_dict[fk][r])
            end
        end
    end
    !isempty(score_long) || throw(ArgumentError("resp contains no observed ratings"))

    cats = category_levels === nothing ? (0:(maxK - 1)) : category_levels
    length(cats) == maxK || throw(DimensionMismatch("category_levels length $(length(cats)) != size(A, 2) = $maxK"))

    tbl = Dict{Symbol,Vector}(:person => p_long, :item => item_long, :score => score_long)
    facet_map_pairs = Pair{Symbol,Symbol}[:item => :item]
    for (fk, _) in f_levels_list
        col_sym = fk in (:person, :item, :score) ? Symbol(:facet_, fk) : fk
        tbl[col_sym] = extra_facets_long[fk]
        push!(facet_map_pairs, fk => col_sym)
    end
    facets_nt = (; facet_map_pairs...)

    return custom_spec(
        tbl;
        person = :person,
        score = :score,
        category_levels = cats,
        A = A,
        B = B,
        item_index = gitem_idx_long,
        facets = facets_nt,
        xsi_fixed = xsi_fixed,
        parameter_names = parameter_names,
        model_transform = model_transform,
        model_names = model_names,
        block_meta = block_meta,
        prior = prior,
        person_prior_sd = person_prior_sd,
        location_mode = location_mode,
    )
end

"""
    MRCML.to_tam(spec)

Export an `MRCMLTarget` or `MRCMLSpec` into `TAM::tam.mml`-ready arrays:
`(; A, B, offset, resp, pid, pattern_labels, parameter_names, category_levels)`.
Each unique pattern `u in 1:U` becomes a generalized item column in `resp` (with `-99`
or `NaN` for unobserved cells, and person rows aggregated cleanly without losing
repeated person-pattern observations by emitting one row per rating with `pid`!).
"""
function to_tam(x::Union{Target,Spec})
    op = x.operator
    U = op.n_patterns
    K = length(x.categories)
    d_xi = size(op.A_free, 2)
    A_3d = zeros(Float64, U, K, d_xi)
    B_3d = zeros(Float64, U, K, 1)
    off_2d = zeros(Float64, U, K)

    At = sparse(op.A_free')
    rv = rowvals(At)
    nz = nonzeros(At)
    for u in 1:U
        prng = op.pattern_ranges[u]
        g = op.pattern_group[u]
        sup = x.supports[g]
        for (lk, k) in enumerate(sup)
            m = prng[lk]
            B_3d[u, k, 1] = op.B_pat[m]
            off_2d[u, k] = op.c_pat[m]
            for ptr in nzrange(At, m)
                A_3d[u, k, rv[ptr]] = nz[ptr]
            end
        end
    end

    # Emit one row per rating with `pid = person_id` so `TAM::tam.mml(resp, A=A, B=B, pid=pid)`
    # preserves repeated person observations on the same pattern without collisions!
    resp = fill(NaN, op.n_obs, U)
    pid = [x.people[x.person[n]] for n in 1:op.n_obs]
    for n in 1:op.n_obs
        u = op.pattern_of_row[n]
        # 0-based category index for TAM::tam.mml
        resp[n, u] = Float64(x.category[n] - 1)
    end
    return (;
        A = A_3d,
        B = B_3d,
        offset = off_2d,
        resp,
        pid,
        pattern_labels = ["pattern_$u" for u in 1:U],
        parameter_names = copy(op.free_names),
        category_levels = copy(x.categories),
    )
end

include("mrcml_population_design.jl")

end # module MRCML
