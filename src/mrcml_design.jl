# FF6a: Sparse Multidimensional Random Coefficients Multinomial Logit (MRCML)
# Design-Matrix Engine, Isometric Interaction/LLTM Compiler & TAM/ConQuest Bridge.
#
# Implements Adams, Wilson & Wang (1997) category log-weights:
#   ell_{n,k} = b_{u(n),k} * theta_{p(n)} + a_{u(n),k}' * eta_xi + c_{u(n),k}
# over compressed unique design patterns using SparseMatrixCSC, shared by
# Bayesian HMC/NUTS (analytic O(N*K + nnz(A)) reverse-mode gradients) and
# 1D frequentist MMLE / JMLE (`src/mrcml_frequentist.jl`).

const MRCML_SCHEMA = "bayesianmgmfrm.mrcml_design.v1"
const MRCML_PERSON_CHART_SCHEMA = "bayesianmgmfrm.mrcml_design.v2"

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
struct MRCMLSpec <: B.AbstractMFRMSpec
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

function _mrcml_fixed_columns(op)
    random = Int[i for b in op.block_meta if get(b,:iid_population,false) for i in b.eta_range]
    setdiff(axes(op.A_free,2),random)
end

function _mrcml_shared_allocation(person,people,facets,op,location_mode;
        n_hyper,external_columns,unreplicated_hyper,person_estimated)
    fixed = _mrcml_fixed_columns(op)
    # Retain the actual conditional aliases separately from the population screen.
    fixed_op = MRCMLOperator((k === :A_free ? op.A_free[:,fixed] :
        k === :free_names ? op.free_names[fixed] : k === :block_meta ? NamedTuple[] :
        getfield(op,k) for k in fieldnames(MRCMLOperator))...)
    random_meta = filter(b->get(b,:iid_population,false),op.block_meta)
    random_names = getproperty.(random_meta,:name)
    conditional_op=MRCMLOperator((k === :block_meta ?
        [merge(b,(;iid_population=false)) for b in op.block_meta] : getfield(op,k)
        for k in fieldnames(MRCMLOperator))...)
    conditional=_mrcml_allocation(person,people,facets,conditional_op,location_mode;
        n_hyper,external_columns,unreplicated_hyper)
    ext = Int[findfirst(isequal(i),fixed) for i in external_columns]
    base = _mrcml_allocation(person,people,filter(b->b.name ∉ random_names,facets),
        fixed_op,location_mode;n_hyper,external_columns=ext,unreplicated_hyper)
    indices = Vector{Int}[]; labels = Symbol[]
    if person_estimated;push!(indices,person);push!(labels,:person);end
    for bm in random_meta
        get(bm,:estimated_sd,true) || continue
        b=only(filter(b->b.name===bm.name,facets))
        push!(indices,b.index);push!(labels,b.name)
    end
    gram=zeros(length(indices),length(indices))
    for a in eachindex(indices), b in eachindex(indices)
        counts=Dict{Tuple{Int,Int},Int}()
        for cell in zip(indices[a],indices[b]);counts[cell]=get(counts,cell,0)+1;end
        gram[a,b]=sum(x->Float64(x)^2,values(counts))
    end
    scales=sqrt.(diag(gram));gram=isempty(scales) ? gram : gram./(scales*scales')
    covariance_rank=isempty(gram) ? 0 : rank(gram)
    unreplicated=[labels[i] for i in eachindex(labels) if allunique(indices[i])]
    reasons=copy(base.reasons)
    covariance_rank<length(labels) && push!(reasons,"Estimated person/shared covariance components are aliased.")
    isempty(unreplicated) || push!(reasons,"Estimated random-effect SDs need repeated observations within levels: $unreplicated.")
    merge(base,(;identified=isempty(reasons),passed=isempty(reasons),reasons,
        method=:population_mean_and_covariance_kernel_screen,
        covariance_rank,covariance_components=labels,normalized_covariance_gram=gram,
        unreplicated_hyper=unreplicated,random_effects=random_names,
        conditional_finite_design=conditional,
        conditional_joint_rank=conditional.conditional_joint_rank,
        conditional_joint_columns=conditional.conditional_joint_columns,
        conditional_joint_identified=conditional.conditional_joint_identified,
        interpretation="Necessary mean-design and covariance-component screen under iid zero-mean population assumptions; not proof of global identification or adequate precision."))
end

function _mrcml_allocation(
        person::Vector{Int},
        people::Vector{Any},
        facets_meta::AbstractVector,
        op::MRCMLOperator,
        location_mode::Symbol;
        n_hyper::Int = 0,
        external_columns::AbstractVector{Int} = 1:0,
        person_estimated::Bool = true,
        unreplicated_hyper::Vector{Symbol} = Symbol[])
    any(b -> get(b,:iid_population,false),op.block_meta) &&
        return _mrcml_shared_allocation(person,people,facets_meta,op,location_mode;
            n_hyper,external_columns,unreplicated_hyper,person_estimated)
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
        elseif b.kind === :hierarchical_half_normal || b.kind === :hierarchical_half_student_t
            s_med = b.marginal_sd * b.iso_factor
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

const _HIERARCHICAL_BLOCK_KINDS = (:hierarchical_lognormal, :hierarchical_half_normal, :hierarchical_half_student_t)
_is_hierarchical_kind(k::Symbol) = k in _HIERARCHICAL_BLOCK_KINDS
function _block_kind_from_scale(k::Symbol)
    k === :lognormal && return :hierarchical_lognormal
    k === :half_normal && return :hierarchical_half_normal
    k === :half_student_t && return :hierarchical_half_student_t
    return :white_scaled
end
_person_scale_kind(t::MRCMLTarget) = t.person_hyper_idx == 0 ? :fixed :
    Symbol(get(get(t.spec_record, :person_scale_prior, (;)), :kind, :lognormal))
_pop_sd_kind(pop) = Symbol(get(pop.sd_prior, :kind, :lognormal))
@inline _pop_sd_idx(pop, p::Int) = length(pop.logsd) == 1 ? 1 : pop.group_index[p]
_has_non_lognormal_scale(t::MRCMLTarget) =
    (_person_scale_kind(t) in (:half_normal, :half_student_t)) ||
    (hasproperty(t.spec_record, :population) && _pop_sd_kind(t.spec_record.population) in (:half_normal, :half_student_t)) ||
    any(b -> b.kind in (:hierarchical_half_normal, :hierarchical_half_student_t), t.prior_blocks)

@inline function _scale_from_raw(kind::Symbol, p1::Float64, p2::Float64, u)
    return kind === :lognormal || kind === :hierarchical_lognormal ? exp(p1 + p2 * u) : exp(u)
end
@inline function _scale_logprior_delta(kind::Symbol, p1::Float64, p2::Float64, u, sig)
    # Returns log p(u) - log N(u; 0, 1) for non-LogNormal positive scale priors on u = log(sig)
    if kind === :half_normal || kind === :hierarchical_half_normal
        r = sig / p2
        return log(2.0) - log(p2) - 0.5 * r * r + u + 0.5 * u * u
    elseif kind === :half_student_t || kind === :hierarchical_half_student_t
        r2 = (sig / p2)^2
        c_t = D.logpdf(D.TDist(p1), 0.0)
        return log(2.0) + c_t + 0.5 * log(2.0 * pi) - log(p2) - 0.5 * (p1 + 1.0) * log1p(r2 / p1) + u + 0.5 * u * u
    end
    return zero(sig)
end
@inline function _scale_dlogprior_du(kind::Symbol, p1::Float64, p2::Float64, u, sig)
    if kind === :half_normal || kind === :hierarchical_half_normal
        r = sig / p2
        return one(sig) - r * r
    elseif kind === :half_student_t || kind === :hierarchical_half_student_t
        r2 = (sig / p2)^2
        return one(sig) - (p1 + 1.0) * r2 / (p1 + r2)
    end
    return -u
end
@inline _scale_dlogsig_du(kind::Symbol, p2::Float64) =
    (kind === :lognormal || kind === :hierarchical_lognormal) ? p2 : 1.0
@inline function _scale_log_volume(kind::Symbol, p2::Float64, sig)
    return (kind === :lognormal || kind === :hierarchical_lognormal) ? (log(typeof(sig)(p2)) + log(sig)) : log(sig)
end

_person_chart(t::MRCMLTarget) = get(get(t.spec_record, :population, (;)), :person_chart, nothing)
function _mrcml_measure(t)
    !isnothing(_person_chart(t)) && return :grouped_person_conditional_with_explicit_block_jacobians
    _has_non_lognormal_scale(t) && return :white_standard_normal_plus_logscale_hyperpriors
    return :white_standard_normal_with_explicit_block_jacobians
end

function _mrcml_unpack(t::MRCMLTarget, q::AbstractVector{<:Real})
    _check(t, q)
    Z = promote_type(Float64, eltype(q))
    P = length(t.people)
    pkind = _person_scale_kind(t)
    s_p = t.person_hyper_idx == 0 ? Z(t.person_sd) :
        _scale_from_raw(pkind, t.person_logmean, t.person_logsd, q[t.person_hyper_idx])
    isfinite(s_p) && s_p > 0 || throw(ArgumentError("unrepresentable person population SD"))
    person = s_p .* q[1:P]
    lv = P * log(s_p)
    pop = get(t.spec_record,:population,nothing)
    chart = _person_chart(t)
    person_z = view(q, 1:P)
    centered_logsd = zero(Z)
    pop_values = if !isnothing(pop)
        cp, sp = pop.coefficient_prior, pop.sd_prior
        gkind = _pop_sd_kind(pop)
        beta = cp.mean .+ cp.sd .* q[pop.beta]
        sd = Z[_scale_from_raw(gkind, sp.logmean, sp.logsd, q[idx]) for idx in pop.logsd]
        all(x -> isfinite(x) && x > 0, sd) || throw(ArgumentError("unrepresentable group SD"))
        mu = pop.X * beta
        if isnothing(chart)
            for p in 1:P
                person[p] = mu[p] + sd[_pop_sd_idx(pop, p)] * person_z[p]
            end
            lv = sum(log(sd[_pop_sd_idx(pop, p)]) for p in 1:P)
        else
            person_z = Z.(person_z)
            lv = zero(Z)
            for p in 1:P
                scale = sd[_pop_sd_idx(pop, p)]
                if chart.centered[p]
                    person[p] = q[p]
                    person_z[p] = (q[p] - mu[p]) / scale
                    centered_logsd += log(scale)
                else
                    person[p] = mu[p] + scale*q[p]
                    lv += log(scale)
                end
            end
        end
        lv = lv + length(beta)*log(cp.sd) + sum(_scale_log_volume(gkind, sp.logsd, s) for s in sd)
        (;coefficients=beta, group_sd=sd)
    else
        nothing
    end
    t.person_hyper_idx == 0 || (lv += _scale_log_volume(pkind, t.person_logsd, s_p))

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
        elseif _is_hierarchical_kind(b.kind)
            sig = _scale_from_raw(b.kind, b.logmean, b.logsd, q[b.hyper_idx])
            isfinite(sig) && sig > 0 || throw(ArgumentError("unrepresentable hierarchical SD for $(b.name)"))
            hyper_sds[b.name] = sig
            eff_s = sig * Z(b.iso_factor)
            for (k, ei) in enumerate(erng)
                eta_xi[ei] = eff_s * q[rrng[k]]
            end
            lv += length(erng) * log(eff_s) + _scale_log_volume(b.kind, b.logsd, sig)
        else
            throw(ArgumentError("unsupported MRCMLPriorBlock kind $(repr(b.kind))"))
        end
    end
    xi_model = Z.(t.operator.xi0_model) .+ (t.operator.J_model * eta_xi)
    return (; person, person_z, centered_logsd, person_sd = s_p, eta_xi, xi_model, hyper_sds, log_volume = lv, population=pop_values)
end

function _mrcml_raw_prior(t, q, u)
    lp = if isnothing(_person_chart(t))
        _white_logprior(q)
    else
        rest = view(q, length(t.people)+1:length(q))
        -length(q)*log(2pi)/2 - (sum(abs2,u.person_z) + sum(abs2,rest))/2 - u.centered_logsd
    end
    if _has_non_lognormal_scale(t)
        pkind = _person_scale_kind(t)
        if pkind in (:half_normal, :half_student_t)
            lp += _scale_logprior_delta(pkind, t.person_logmean, t.person_logsd, q[t.person_hyper_idx], u.person_sd)
        end
        if !isnothing(u.population)
            pop = t.spec_record.population
            gkind = _pop_sd_kind(pop)
            if gkind in (:half_normal, :half_student_t)
                for (k, idx) in enumerate(pop.logsd)
                    lp += _scale_logprior_delta(gkind, pop.sd_prior.logmean, pop.sd_prior.logsd, q[idx], u.population.group_sd[k])
                end
            end
        end
        for b in t.prior_blocks
            if b.kind in (:hierarchical_half_normal, :hierarchical_half_student_t)
                lp += _scale_logprior_delta(b.kind, b.logmean, b.logsd, q[b.hyper_idx], u.hyper_sds[b.name])
            end
        end
    end
    return lp
end

function logprior(t::MRCMLTarget, q)
    _check(t,q)
    if isnothing(_person_chart(t)) && !_has_non_lognormal_scale(t)
        return _white_logprior(q)
    end
    representable_scales(t,q) || return -oftype(float(first(q)),Inf)
    return _mrcml_raw_prior(t,q,_mrcml_unpack(t,q))
end

function _sample_logscale_raw(rng, kind::Symbol, p1::Float64, p2::Float64, z_std::Float64)
    if kind === :half_normal || kind === :hierarchical_half_normal
        return log(max(abs(z_std) * p2, floatmin(Float64)))
    elseif kind === :half_student_t || kind === :hierarchical_half_student_t
        v = rand(rng, D.Chisq(p1))
        t_abs = abs(z_std) / sqrt(v / p1)
        return log(max(t_abs * p2, floatmin(Float64)))
    end
    return z_std
end

function _prior_draw!(rng::AbstractRNG, t::MRCMLTarget)
    q = randn(rng, Float64, t.dimension)
    if _has_non_lognormal_scale(t)
        pkind = _person_scale_kind(t)
        if pkind in (:half_normal, :half_student_t)
            q[t.person_hyper_idx] = _sample_logscale_raw(rng, pkind, t.person_logmean, t.person_logsd, q[t.person_hyper_idx])
        end
        if hasproperty(t.spec_record, :population)
            pop_p = t.spec_record.population
            gkind = _pop_sd_kind(pop_p)
            if gkind in (:half_normal, :half_student_t)
                for idx in pop_p.logsd
                    q[idx] = _sample_logscale_raw(rng, gkind, pop_p.sd_prior.logmean, pop_p.sd_prior.logsd, q[idx])
                end
            end
        end
        for b in t.prior_blocks
            if b.kind in (:hierarchical_half_normal, :hierarchical_half_student_t)
                q[b.hyper_idx] = _sample_logscale_raw(rng, b.kind, b.logmean, b.logsd, q[b.hyper_idx])
            end
        end
    end
    chart = _person_chart(t)
    isnothing(chart) && return q
    pop = t.spec_record.population
    gkind_c = _pop_sd_kind(pop)
    mu = pop.X * (pop.coefficient_prior.mean .+ pop.coefficient_prior.sd .* q[pop.beta])
    sd = Float64[_scale_from_raw(gkind_c, pop.sd_prior.logmean, pop.sd_prior.logsd, q[idx]) for idx in pop.logsd]
    for p in eachindex(chart.centered)
        chart.centered[p] && (q[p] = mu[p] + sd[_pop_sd_idx(pop, p)]*q[p])
    end
    return q
end

prior_draw(t::MRCMLTarget; seed=1) = _prior_draw!(MersenneTwister(_check_seed(seed)), t)

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
        measure = _mrcml_measure(t),
    )
end

function representable_scales(t::MRCMLTarget, q)
    if hasproperty(t.spec_record,:population)
        p = t.spec_record.population
        gkind = _pop_sd_kind(p)
        all(i -> (s=_scale_from_raw(gkind, p.sd_prior.logmean, p.sd_prior.logsd, q[i]); isfinite(s) && s>0), p.logsd) || return false
    end
    if t.person_hyper_idx > 0
        pkind = _person_scale_kind(t)
        sp = _scale_from_raw(pkind, t.person_logmean, t.person_logsd, q[t.person_hyper_idx])
        (isfinite(sp) && sp > 0) || return false
    end
    for b in t.prior_blocks
        if _is_hierarchical_kind(b.kind)
            sb = _scale_from_raw(b.kind, b.logmean, b.logsd, q[b.hyper_idx])
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

# Structured unit-slope location/step models can evaluate each rating in model
# coordinates, then apply the (often dense) contrast basis once per gradient.
struct _ScalarRatingDesign
    locations::Matrix{Int}
    step_start::Vector{Int}
    intercept::Int
    model::Vector{Float64}
    model_score::Vector{Float64}
    loglik::Vector{Float64}
    location_score::Vector{Float64}
    step_score::Matrix{Float64}
end

function _scalar_rating_design(t; force=false)
    op = t.operator
    (force || 2op.n_patterns > op.n_obs) || return nothing
    get(t.spec_record, :source, nothing) === :structured_mfrm_spec || return nothing
    all(b -> b.kind in (:facet_main, :steps, :population_mean), op.block_meta) || return nothing
    all(iszero,op.c0_pat) || return nothing
    facets = filter(b -> b.kind === :facet_main, op.block_meta)
    steps = filter(b -> b.kind === :steps, op.block_meta)
    intercept = findfirst(b -> b.kind === :population_mean, op.block_meta)
    loc = Matrix{Int}(undef, length(facets), op.n_obs)
    for (j,b) in enumerate(facets)
        ids = only(f.index for f in t.facets if f.name === b.name)
        loc[j,:] .= first(b.model_range) .- 1 .+ ids
    end
    starts = [first(b.model_range) for b in steps]
    d = length(op.model_names)
    return _ScalarRatingDesign(loc, starts, isnothing(intercept) ? 0 : first(op.block_meta[intercept].model_range),
        zeros(d), zeros(d), zeros(op.n_obs), zeros(op.n_obs), zeros(maximum(length,t.supports),op.n_obs))
end

function _scalar_rating_loglik!(ds, t, sc, lp, gradient)
    model = copyto!(ds.model, t.operator.xi0_model)
    mul!(model, t.operator.J_model, sc.eta_xi, 1.0, 1.0)
    intercept = ds.intercept == 0 ? 0.0 : model[ds.intercept]
    B._parallel_ranges(t.operator.n_obs, t.operator.n_obs) do rows
        @inbounds for n in rows
            eta = sc.person[t.person[n]] + intercept
            for f in axes(ds.locations,1)
                eta -= model[ds.locations[f,n]]
            end
            g = t.group[n]
            K = length(t.supports[g])
            y = t.category[n] - first(t.supports[g]) + 1
            start = ds.step_start[g]
            ds.step_score[1,n] = 0.0
            hi = 0.0
            cum = 0.0
            for k in 2:K
                cum += model[start+k-2]
                v = (k-1)*eta - cum
                ds.step_score[k,n] = v
                hi = max(hi,v)
            end
            num = ds.step_score[y,n]
            denom = 0.0
            for k in 1:K
                e = exp(ds.step_score[k,n] - hi)
                ds.step_score[k,n] = e
                denom += e
            end
            ds.loglik[n] = num - (hi + log(denom))
            if gradient
                tail = 0.0
                score = 0.0
                for k in K:-1:2
                    tail += ds.step_score[k,n] / denom
                    residual = (y >= k) - tail
                    ds.step_score[k,n] = -residual
                    score += residual
                end
                ds.location_score[n] = score
            end
        end
    end
    gx = ds.model_score
    gradient && fill!(gx, 0.0)
    @inbounds for n in eachindex(t.person)
        lp += ds.loglik[n]
        if gradient
            z = ds.location_score[n]
            sc.gp[t.person[n]] += z
            ds.intercept > 0 && (gx[ds.intercept] += z)
            for f in axes(ds.locations,1)
                gx[ds.locations[f,n]] -= z
            end
            g = t.group[n]
            for k in 2:length(t.supports[g])
                gx[ds.step_start[g]+k-2] += ds.step_score[k,n]
            end
        end
    end
    gradient && mul!(sc.g_eta, transpose(t.operator.J_model), gx)
    return lp
end

mutable struct _MRCMLGradScratch
    target::Union{Nothing,MRCMLTarget}
    pkind::Symbol
    has_pop::Bool
    has_non_ln::Bool
    scalar::Union{Nothing,_ScalarRatingDesign}
    person::Vector{Float64}
    person_z::Vector{Float64}
    pop_beta::Vector{Float64}
    pop_sd::Vector{Float64}
    eta_xi::Vector{Float64}
    hyper_sds::Vector{Float64}
    vp::Vector{Float64}
    gp::Vector{Float64}
    r_pat::Vector{Float64}
    g_eta::Vector{Float64}
    ebuf::Vector{Float64}
end

function _get_mrcml_grad_scratch(t::MRCMLTarget)
    sc = get!(task_local_storage(), :_mrcml_grad_scratch) do
        _MRCMLGradScratch(
            nothing, :fixed, false, false, nothing,
            Float64[], Float64[], Float64[], Float64[],
            Float64[], Float64[], Float64[], Float64[],
            Float64[], Float64[], Float64[],
        )
    end::_MRCMLGradScratch
    if sc.target !== t
        pk = _person_scale_kind(t)::Symbol
        hp = haskey(t.spec_record, :population) && getfield(t.spec_record, :population) !== nothing
        hnl = (pk in (:half_normal, :half_student_t)) ||
            (hp && _pop_sd_kind(getfield(t.spec_record, :population)) in (:half_normal, :half_student_t)) ||
            any(b -> b.kind in (:hierarchical_half_normal, :hierarchical_half_student_t), t.prior_blocks)
        sc.target = t
        sc.pkind = pk
        sc.has_pop = hp
        sc.has_non_ln = hnl
        sc.scalar = _scalar_rating_design(t)
    end
    return sc
end

@noinline function _mrcml_unpack_pop_f64!(sc::_MRCMLGradScratch, pop, chart, q::AbstractVector{Float64}, P::Int)::Tuple{Bool, Bool, Float64, Float64}
    cp, sp = pop.coefficient_prior, pop.sd_prior
    gkind = _pop_sd_kind(pop)
    n_beta = length(pop.beta)
    n_gsd = length(pop.logsd)
    resize!(sc.pop_beta, n_beta)
    resize!(sc.pop_sd, n_gsd)
    @inbounds for j in 1:n_beta
        sc.pop_beta[j] = cp.mean + cp.sd * q[pop.beta[j]]
    end
    pop_prior_delta = 0.0
    @inbounds for g in 1:n_gsd
        ug = q[pop.logsd[g]]
        sg = _scale_from_raw(gkind, sp.logmean, sp.logsd, ug)
        (isfinite(sg) && sg > 0.0) || return (false, false, NaN, NaN)
        sc.pop_sd[g] = sg
        if gkind in (:half_normal, :half_student_t)
            pop_prior_delta += _scale_logprior_delta(gkind, sp.logmean, sp.logsd, ug, sg)
        end
    end
    mul!(sc.person, pop.X, sc.pop_beta)
    if chart === nothing
        @inbounds for p in 1:P
            sc.person[p] += sc.pop_sd[_pop_sd_idx(pop, p)] * q[p]
        end
        return (true, false, 0.0, pop_prior_delta)
    end
    centered_logsd = 0.0
    resize!(sc.person_z, P)
    @inbounds for p in 1:P
        mu_p = sc.person[p]
        scale = sc.pop_sd[_pop_sd_idx(pop, p)]
        if chart.centered[p]
            sc.person[p] = q[p]
            sc.person_z[p] = (q[p] - mu_p) / scale
            centered_logsd += log(scale)
        else
            sc.person[p] = mu_p + scale * q[p]
            sc.person_z[p] = q[p]
        end
    end
    return (true, true, centered_logsd, pop_prior_delta)
end

@noinline function _mrcml_pullback_pop_f64!(grad::Vector{Float64}, sc::_MRCMLGradScratch, pop, chart, gp::Vector{Float64}, q::AbstractVector{Float64}, P::Int)
    sp = pop.sd_prior
    gkind = _pop_sd_kind(pop)
    n_gsd = length(pop.logsd)
    dlog_du = _scale_dlogsig_du(gkind, sp.logsd)
    @inbounds for g in 1:n_gsd
        idx = pop.logsd[g]
        grad[idx] = _scale_dlogprior_du(gkind, sp.logmean, sp.logsd, q[idx], sc.pop_sd[g])
    end
    @inbounds for p in 1:P
        g = _pop_sd_idx(pop, p)
        sd = sc.pop_sd[g]
        if chart !== nothing && chart.centered[p]
            z = sc.person_z[p]
            grad[p] = gp[p] - z / sd
            gp[p] = z / sd
            grad[pop.logsd[g]] += dlog_du * (z * z - 1.0)
        else
            scaled = sd * gp[p]
            grad[p] += scaled
            grad[pop.logsd[g]] += dlog_du * scaled * q[p]
        end
    end
    mul!(view(grad, pop.beta), transpose(pop.X), gp, pop.coefficient_prior.sd, 1.0)
    return nothing
end

function _mrcml_unpack_f64!(sc::_MRCMLGradScratch, t::MRCMLTarget, q::AbstractVector{Float64})::Tuple{Bool, Float64, Float64}
    op = t.operator
    P = length(t.people)
    d_xi = size(op.A_free, 2)
    n_blk = length(t.prior_blocks)
    M_tot = length(op.c_pat)
    resize!(sc.person, P)
    resize!(sc.eta_xi, d_xi)
    resize!(sc.hyper_sds, n_blk)
    resize!(sc.vp, M_tot)

    pkind = sc.pkind
    s_p = t.person_hyper_idx == 0 ? t.person_sd :
        _scale_from_raw(pkind, t.person_logmean, t.person_logsd, q[t.person_hyper_idx])
    (isfinite(s_p) && s_p > 0.0) || return (false, NaN, NaN)

    has_chart = false
    centered_logsd = 0.0
    pop_prior_delta = 0.0
    if !sc.has_pop
        @inbounds for p in 1:P
            sc.person[p] = s_p * q[p]
        end
    else
        pop = getfield(t.spec_record, :population)
        chart = haskey(pop, :person_chart) ? getfield(pop, :person_chart) : nothing
        ok_pop, has_chart, centered_logsd, pop_prior_delta = _mrcml_unpack_pop_f64!(sc, pop, chart, q, P)
        ok_pop || return (false, NaN, NaN)
    end

    @inbounds for bi in 1:n_blk
        b = t.prior_blocks[bi]
        erng = b.eta_range
        rrng = b.raw_range
        if b.kind === :white_scaled
            sc.hyper_sds[bi] = 0.0
            for (k, ei) in enumerate(erng)
                sc.eta_xi[ei] = b.mu[k] + b.scale_vec[k] * q[rrng[k]]
            end
        elseif b.kind === :mvnormal
            sc.hyper_sds[bi] = 0.0
            d_b = length(erng)
            r0 = first(rrng) - 1
            for r in 1:d_b
                acc = b.mu[r]
                for c in 1:r
                    acc += b.chol_L[r, c] * q[r0 + c]
                end
                sc.eta_xi[erng[r]] = acc
            end
        elseif _is_hierarchical_kind(b.kind)
            sig = _scale_from_raw(b.kind, b.logmean, b.logsd, q[b.hyper_idx])
            (isfinite(sig) && sig > 0.0) || return (false, NaN, NaN)
            sc.hyper_sds[bi] = sig
            eff_s = sig * b.iso_factor
            for (k, ei) in enumerate(erng)
                sc.eta_xi[ei] = eff_s * q[rrng[k]]
            end
        else
            throw(ArgumentError("unsupported MRCMLPriorBlock kind $(repr(b.kind))"))
        end
    end

    if isnothing(sc.scalar)
        copyto!(sc.vp, op.c_pat)
        rows = rowvals(op.A_free)
        vals = nonzeros(op.A_free)
        @inbounds for col in 1:d_xi
            ec = sc.eta_xi[col]
            ec == 0.0 && continue
            for ptr in nzrange(op.A_free, col)
                sc.vp[rows[ptr]] += vals[ptr] * ec
            end
        end
    end

    lp::Float64 = if !has_chart
        _white_logprior(q)
    else
        rest_ss = 0.0
        @inbounds for j in (P + 1):length(q)
            qj = q[j]
            rest_ss += qj * qj
        end
        pz_ss = 0.0
        @inbounds for p in 1:P
            zp = sc.person_z[p]
            pz_ss += zp * zp
        end
        -0.5 * Float64(length(q)) * log(2.0 * pi) - 0.5 * (pz_ss + rest_ss) - centered_logsd
    end
    if sc.has_non_ln
        lp += pop_prior_delta
        if pkind in (:half_normal, :half_student_t)
            lp += _scale_logprior_delta(pkind, t.person_logmean, t.person_logsd, q[t.person_hyper_idx], s_p)
        end
        @inbounds for bi in 1:n_blk
            b = t.prior_blocks[bi]
            if b.kind in (:hierarchical_half_normal, :hierarchical_half_student_t)
                lp += _scale_logprior_delta(b.kind, b.logmean, b.logsd, q[b.hyper_idx], sc.hyper_sds[bi])
            end
        end
    end
    return (true, s_p, lp)
end

function L.logdensity(t::MRCMLTarget, q::AbstractVector{<:Real})
    _check(t, q; finite = false)
    Z = promote_type(Float64, eltype(q))
    all(isfinite, q) && representable_scales(t, q) || return -Z(Inf)
    u = _mrcml_unpack(t, q)
    vp = _mrcml_pattern_shifts(t.operator, u.eta_xi)
    a = Vector{Z}(undef, length(t.categories))
    lp = _mrcml_raw_prior(t, q, u)
    for n in eachindex(t.person)
        c = _weights!(a, t, u, n, vp)
        lp += a[t.category[n]] - c
    end
    return isfinite(lp) ? lp : -Z(Inf)
end

function L.logdensity(t::MRCMLTarget, q::AbstractVector{Float64})
    _check(t, q; finite = false)
    all(isfinite, q) || return -Inf
    sc = _get_mrcml_grad_scratch(t)
    ok, _, lp = _mrcml_unpack_f64!(sc, t, q)
    ok || return -Inf
    if !isnothing(sc.scalar)
        value = _scalar_rating_loglik!(sc.scalar, t, sc, lp, false)
        return isfinite(value) ? value : -Inf
    end
    op = t.operator
    person = sc.person
    vp = sc.vp
    B_pat = op.B_pat
    @inbounds for n in 1:op.n_obs
        prng = op.pattern_ranges[op.pattern_of_row[n]]
        sup = t.supports[t.group[n]]
        th = person[t.person[n]]
        yk_loc = t.category[n] - first(sup) + 1
        m1 = first(prng)
        M_g = length(prng)
        mmax = B_pat[m1] * th + vp[m1]
        y_val = yk_loc == 1 ? mmax : 0.0
        for lk in 2:M_g
            m = m1 + lk - 1
            val = B_pat[m] * th + vp[m]
            lk == yk_loc && (y_val = val)
            val > mmax && (mmax = val)
        end
        ssum = 0.0
        for lk in 1:M_g
            m = m1 + lk - 1
            ssum += exp((B_pat[m] * th + vp[m]) - mmax)
        end
        lp += y_val - (mmax + log(ssum))
    end
    return isfinite(lp) ? lp : -Inf
end

function L.logdensity_and_gradient(t::MRCMLTarget, q::AbstractVector{Float64})
    _check(t, q; finite = false)
    rejected() = (-Inf, fill(NaN, length(q)))
    all(isfinite, q) || return rejected()

    sc = _get_mrcml_grad_scratch(t)
    ok, s_p, lp = _mrcml_unpack_f64!(sc, t, q)
    ok || return rejected()

    op = t.operator
    P = length(t.people)
    gp = fill!(resize!(sc.gp, P), 0.0)
    d_xi = size(op.A_free,2)
    g_eta = resize!(sc.g_eta, d_xi)
    if !isnothing(sc.scalar)
        lp = _scalar_rating_loglik!(sc.scalar, t, sc, lp, true)
        isfinite(lp) || return rejected()
    else
        M_tot = length(op.c_pat)
        K = length(t.categories)
        resize!(sc.r_pat, M_tot)
        resize!(sc.ebuf, K)
        r_pat = fill!(sc.r_pat, 0.0)
        ebuf = sc.ebuf
        person = sc.person
        vp = sc.vp
        B_pat = op.B_pat

        @inbounds for n in 1:op.n_obs
            prng = op.pattern_ranges[op.pattern_of_row[n]]
            sup = t.supports[t.group[n]]
            p = t.person[n]
            th = person[p]
            yk_loc = t.category[n] - first(sup) + 1
            m1 = first(prng)
            M_g = length(prng)
            mmax = B_pat[m1] * th + vp[m1]
            ebuf[1] = mmax
            for lk in 2:M_g
                m = m1 + lk - 1
                val = B_pat[m] * th + vp[m]
                ebuf[lk] = val
                val > mmax && (mmax = val)
            end
            y_val = ebuf[yk_loc]
            ssum = 0.0
            for lk in 1:M_g
                ssum += exp(ebuf[lk] - mmax)
            end
            z = mmax + log(ssum)
            lp += y_val - z
            for lk in 1:M_g
                m = m1 + lk - 1
                pk = exp(ebuf[lk] - z)
                rk = (lk == yk_loc ? 1.0 : 0.0) - pk
                r_pat[m] += rk
                gp[p] += B_pat[m] * rk
            end
        end
        isfinite(lp) || return rejected()

        rows = rowvals(op.A_free)
        vals = nonzeros(op.A_free)
        @inbounds for col in 1:d_xi
            acc = 0.0
            for ptr in nzrange(op.A_free, col)
                acc += vals[ptr] * r_pat[rows[ptr]]
            end
            g_eta[col] = acc
        end
    end

    grad = Vector{Float64}(undef, length(q))
    @inbounds for j in eachindex(q)
        grad[j] = -q[j]
    end
    if !sc.has_pop
        @inbounds for p in 1:P
            grad[p] += s_p * gp[p]
        end
    else
        pop = getfield(t.spec_record, :population)
        chart = haskey(pop, :person_chart) ? getfield(pop, :person_chart) : nothing
        _mrcml_pullback_pop_f64!(grad, sc, pop, chart, gp, q, P)
    end
    if t.person_hyper_idx > 0
        pkind = sc.pkind
        dot_pq = 0.0
        @inbounds for p in 1:P
            dot_pq += gp[p] * q[p]
        end
        dlog_du = _scale_dlogsig_du(pkind, t.person_logsd)
        prior_du = _scale_dlogprior_du(pkind, t.person_logmean, t.person_logsd, q[t.person_hyper_idx], s_p)
        grad[t.person_hyper_idx] = prior_du + dlog_du * s_p * dot_pq
    end

    @inbounds for bi in eachindex(t.prior_blocks)
        b = t.prior_blocks[bi]
        erng = b.eta_range
        rrng = b.raw_range
        if b.kind === :white_scaled
            for (k, ei) in enumerate(erng)
                grad[rrng[k]] += b.scale_vec[k] * g_eta[ei]
            end
        elseif b.kind === :mvnormal
            d_b = length(erng)
            for c in 1:d_b
                acc = 0.0
                for r in c:d_b
                    acc += b.chol_L[r, c] * g_eta[erng[r]]
                end
                grad[rrng[c]] += acc
            end
        elseif _is_hierarchical_kind(b.kind)
            sig = sc.hyper_sds[bi]
            eff_s = sig * b.iso_factor
            dot_bq = 0.0
            for (k, ei) in enumerate(erng)
                ge = g_eta[ei]
                grad[rrng[k]] += eff_s * ge
                dot_bq += ge * q[rrng[k]]
            end
            dlog_du = _scale_dlogsig_du(b.kind, b.logsd)
            prior_du = _scale_dlogprior_du(b.kind, b.logmean, b.logsd, q[b.hyper_idx], sig)
            grad[b.hyper_idx] = prior_du + dlog_du * eff_s * dot_bq
        end
    end

    return all(isfinite, grad) ? (lp, grad) : rejected()
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
    lp = _mrcml_raw_prior(t, q, u)

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
        chart = _person_chart(t)
        gkind = _pop_sd_kind(pop)
        sp_pop = pop.sd_prior
        dlog_du_pop = Z(_scale_dlogsig_du(gkind, sp_pop.logsd))
        for (k, idx) in enumerate(pop.logsd)
            grad[idx] = _scale_dlogprior_du(gkind, sp_pop.logmean, sp_pop.logsd, q[idx], u.population.group_sd[k])
        end
        for p in 1:P
            g = _pop_sd_idx(pop, p)
            sd = u.population.group_sd[g]
            if !isnothing(chart) && chart.centered[p]
                z = u.person_z[p]
                grad[p] = gp[p] - z/sd
                gp[p] = z/sd  # derivative with respect to the population mean
                grad[pop.logsd[g]] += dlog_du_pop * (z^2 - 1)
            else
                scaled = sd * gp[p]
                grad[p] += scaled
                grad[pop.logsd[g]] += dlog_du_pop * scaled * q[p]
            end
        end
        grad[pop.beta] .+= pop.coefficient_prior.sd .* (pop.X' * gp)
    end
    if t.person_hyper_idx > 0
        pkind = _person_scale_kind(t)
        dot_pq = zero(Z)
        @inbounds for p in 1:P
            dot_pq += gp[p] * q[p]
        end
        dlog_du = Z(_scale_dlogsig_du(pkind, t.person_logsd))
        prior_du = _scale_dlogprior_du(pkind, t.person_logmean, t.person_logsd, q[t.person_hyper_idx], u.person_sd)
        grad[t.person_hyper_idx] = prior_du + dlog_du * u.person_sd * dot_pq
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
        elseif _is_hierarchical_kind(b.kind)
            sig = u.hyper_sds[b.name]
            eff_s = sig * Z(b.iso_factor)
            dot_bq = zero(Z)
            @inbounds for (k, ei) in enumerate(erng)
                ge = g_eta[ei]
                grad[rrng[k]] += eff_s * ge
                dot_bq += ge * q[rrng[k]]
            end
            dlog_du = Z(_scale_dlogsig_du(b.kind, b.logsd))
            prior_du = _scale_dlogprior_du(b.kind, b.logmean, b.logsd, q[b.hyper_idx], sig)
            grad[b.hyper_idx] = prior_du + dlog_du * eff_s * dot_bq
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
        chart = _person_chart(t)
        for p in 1:P
            out[p] = !isnothing(chart) && chart.centered[p] ? "person.centered[$p]" : "person.white[$p]"
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
            if length(pop.logsd) == 1
                out[pop.logsd[1]] = "log_sd.white[shared]"
            else
                out[pop.logsd] .= ["log_sd.white[$(repr(g))]" for g in pop.groups]
            end
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
        if length(pop.logsd) == 1
            push!(out, "population_sd")
        else
            append!(out, ["population_sd[$(repr(g))]" for g in pop.groups])
        end
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
        schema = isnothing(_person_chart(t)) ? MRCML_SCHEMA : MRCML_PERSON_CHART_SCHEMA,
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
    pop = get(r.spec_record, :population, (;))
    chart = get(pop, :person_chart, nothing)
    expected_schema = isnothing(chart) ? MRCML_SCHEMA : MRCML_PERSON_CHART_SCHEMA
    r.schema == expected_schema || throw(ArgumentError("inconsistent MRCML person coordinate schema"))
    if !isnothing(chart)
        pop.people == r.people && chart.centered isa AbstractVector{Bool} && length(chart.centered)==length(r.people) ||
            throw(ArgumentError("saved person coordinates do not match the modeled roster"))
    end
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
        external_columns=get(r.spec_record,:external_columns,1:0),
        person_estimated=Int(r.person_hyper_idx)>0 || hasproperty(r.spec_record,:population))
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

function _describe_scale_prior(kind::Symbol, sd_val::Float64, p1::Float64, p2::Float64)
    if kind === :fixed
        return (;
            family = :fixed,
            label = "Fixed($(round(sd_val; digits = 4)))",
            median_sd = sd_val,
            rms_sd = sd_val,
            second_moment_finite = isfinite(sd_val),
            prob_sd_le_025 = sd_val <= 0.25 ? 1.0 : 0.0,
            zero_supporting = false,
        )
    elseif kind === :lognormal || kind === :hierarchical_lognormal
        d = D.LogNormal(p1, p2)
        return (;
            family = :LogNormal,
            label = "LogNormal($(round(p1; digits = 4)), $(round(p2; digits = 4)))",
            logmean = p1,
            logsd = p2,
            median_sd = exp(p1),
            rms_sd = exp(p1 + p2^2),
            second_moment_finite = true,
            prob_sd_le_025 = D.cdf(d, 0.25),
            zero_supporting = false,
        )
    elseif kind === :half_normal || kind === :hierarchical_half_normal
        d = D.truncated(D.Normal(0.0, p2), 0.0, Inf)
        return (;
            family = :HalfNormal,
            label = "HalfNormal($(round(p2; digits = 4)))",
            scale = p2,
            median_sd = D.median(d),
            rms_sd = p2,
            second_moment_finite = true,
            prob_sd_le_025 = D.cdf(d, 0.25),
            zero_supporting = true,
        )
    elseif kind === :half_student_t || kind === :hierarchical_half_student_t
        d = D.truncated(D.TDist(p1), 0.0, Inf)
        fin_m2 = p1 > 2.0
        rms = fin_m2 ? p2 * sqrt(p1 / (p1 - 2.0)) : Inf
        return (;
            family = :HalfStudentT,
            label = "HalfStudentT(df=$(round(p1; digits = 4)), scale=$(round(p2; digits = 4)))",
            df = p1,
            scale = p2,
            median_sd = p2 * D.median(d),
            rms_sd = rms,
            second_moment_finite = fin_m2,
            prob_sd_le_025 = D.cdf(d, 0.25 / p2),
            zero_supporting = true,
        )
    end
    return (; family = kind, label = string(kind), median_sd = sd_val, rms_sd = sd_val,
        second_moment_finite = isfinite(sd_val), prob_sd_le_025 = NaN, zero_supporting = false)
end

function _mrcml_prior_summary(t::MRCMLTarget)
    has_pop = hasproperty(t.spec_record, :population)
    pop_summary = nothing
    if has_pop
        pop = t.spec_record.population
        cp = pop.coefficient_prior
        sp = pop.sd_prior
        gkind = _pop_sd_kind(pop)
        eq_sd = length(pop.logsd) == 1
        sd_desc = merge(
            _describe_scale_prior(gkind, get(sp, :sd, exp(sp.logmean)), sp.logmean, sp.logsd),
            (; role = eq_sd ? :shared_group_ability_sd : :group_ability_sd,
               n_groups = length(pop.groups), equal_sd = eq_sd),
        )
        person_desc = sd_desc
        pop_mean_desc = (;
            role = :group_mean_coefficients,
            distribution = "Normal($(round(cp.mean; digits = 4)), $(round(cp.sd; digits = 4)))",
            mean = cp.mean,
            sd = cp.sd,
            reference_group = string(pop.reference),
            n_groups = length(pop.groups),
        )
        pop_summary = (;
            groups = String.(string.(pop.groups)),
            reference = string(pop.reference),
            coefficient_prior = pop_mean_desc,
            sd_prior = sd_desc,
        )
    else
        pkind = _person_scale_kind(t)
        p_role = pkind === :fixed ? :person_ability_fixed_sd : :person_ability_sd
        person_desc = merge(
            _describe_scale_prior(pkind, t.person_sd, t.person_logmean, t.person_logsd),
            (; role = p_role),
        )
        pop_mean_desc = nothing
    end
    blocks_desc = NamedTuple[]
    bm_by_eta = Dict(bm.eta_range => bm for bm in t.operator.block_meta)
    for b in t.prior_blocks
        if b.name === :population_mean
            pop_mean_desc = (;
                role = :population_mean,
                distribution = "Normal($(round(b.mu[1]; digits = 4)), $(round(b.scale_vec[1]; digits = 4)))",
                mean = b.mu[1],
                sd = b.scale_vec[1],
            )
            continue
        end
        bm = get(bm_by_eta, b.eta_range, nothing)
        n_lev = bm === nothing ? length(b.model_range) : length(bm.model_range)
        b_role = bm === nothing ? :custom : bm.kind
        is_oneway = bm !== nothing && bm.kind in (:facet_main, :steps)
        is_interaction = bm !== nothing && bm.kind in (:facet_facet_interaction, :facet_step_interaction)
        is_hier = _is_hierarchical_kind(b.kind)
        scale_info = is_hier ?
            _describe_scale_prior(b.kind, b.marginal_sd, b.logmean, b.logsd) :
            (; family = b.kind, label = b.kind === :mvnormal ? "MvNormal(dim=$(length(b.eta_range)))" :
                isfinite(b.marginal_sd) ? "Normal(0, marginal_sd=$(round(b.marginal_sd; digits = 4)))" : "Normal(elementwise)",
               median_sd = b.marginal_sd, rms_sd = b.marginal_sd,
               second_moment_finite = isfinite(b.marginal_sd), zero_supporting = false)
        is_iso_oneway = is_oneway && b.iso_factor > 1.0 + 1e-12
        is_iso_interaction = is_interaction && b.iso_factor > 1.0 + 1e-12
        # For a zero-sum isometric Helmert block of L levels with conditional SD s:
        # Var(beta_i - beta_j | s) = 2 * s^2 * L / (L - 1) = 2 * s^2 * iso_factor^2.
        # For a doubly centered Kronecker-Helmert interaction block (L1 x L2) with conditional cell SD tau:
        # Var((gamma_{i1,j1} - gamma_{i1,j2}) - (gamma_{i2,j1} - gamma_{i2,j2}) | tau) = 4 * tau^2 * iso_factor^2.
        # Integrating over a hierarchical scale prior uses E[s^2] = rms_sd^2 (Inf when df <= 2, e.g. Half-Cauchy).
        if is_hier
            marg_sd = scale_info.rms_sd
            cond_med_sd = scale_info.median_sd
            pw_sd = is_iso_oneway ? (isfinite(marg_sd) ? sqrt(2.0) * marg_sd * b.iso_factor : Inf) : missing
            cond_pw_sd = is_iso_oneway && isfinite(cond_med_sd) ? sqrt(2.0) * cond_med_sd * b.iso_factor : missing
            tet_sd = is_iso_interaction ? (isfinite(marg_sd) ? 2.0 * marg_sd * b.iso_factor : Inf) : missing
            cond_tet_sd = is_iso_interaction && isfinite(cond_med_sd) ? 2.0 * cond_med_sd * b.iso_factor : missing
            pw_basis = !(is_iso_oneway || is_iso_interaction) ? :not_applicable :
                isfinite(marg_sd) ? :marginal_second_moment : :divergent_second_moment
            marg_field = marg_sd
            cond_med_field = cond_med_sd
        else
            is_iso = is_iso_oneway && isfinite(b.marginal_sd) && b.marginal_sd > 0.0
            is_iso_int = is_iso_interaction && isfinite(b.marginal_sd) && b.marginal_sd > 0.0
            pw_sd = is_iso ? sqrt(2.0) * b.marginal_sd * b.iso_factor : missing
            cond_pw_sd = pw_sd
            tet_sd = is_iso_int ? 2.0 * b.marginal_sd * b.iso_factor : missing
            cond_tet_sd = tet_sd
            pw_basis = (is_iso || is_iso_int) ? :fixed_marginal_sd : :not_applicable
            marg_field = isfinite(b.marginal_sd) ? b.marginal_sd : missing
            cond_med_field = marg_field
        end
        push!(blocks_desc, (;
            name = b.name,
            block_role = b_role,
            kind = b.kind,
            distribution = scale_info.label,
            n_levels = n_lev,
            free_df = length(b.eta_range),
            marginal_sd = marg_field,
            conditional_median_sd = cond_med_field,
            iso_factor = b.iso_factor,
            implied_pairwise_contrast_sd = pw_sd,
            conditional_median_pairwise_contrast_sd = cond_pw_sd,
            (is_interaction ? (;
                implied_tetrad_contrast_sd = tet_sd,
                conditional_median_tetrad_contrast_sd = cond_tet_sd,
            ) : (;))...,
            pairwise_contrast_sd_basis = pw_basis,
            scale_prior = is_hier ? scale_info : nothing,
        ))
    end
    return (;
        default_prior = Bool(get(t.spec_record, :default_prior, false)),
        person = person_desc,
        population_mean = pop_mean_desc,
        (pop_summary === nothing ? (;) : (; population = pop_summary))...,
        structural_blocks = blocks_desc,
        prior_sensitivity_note = "Inspect prior sensitivity for focal contrasts whenever true ability spread may be near zero, scores cluster near floor/ceiling, or a facet has few levels (L <= 4); for isometric zero-sum blocks, implied_pairwise_contrast_sd integrates the scale prior via sqrt(E[sigma^2]) * sqrt(2L/(L-1)) (Inf when df <= 2), while conditional_median_pairwise_contrast_sd conditions on sigma = median(sigma).",
    )
end

function design(t::MRCMLTarget)
    patterns = response_patterns(t)
    psummary = _mrcml_prior_summary(t)
    ws = [
        "Conditional independence given declared latent/structural terms is an assumption, not proven by design rank.",
        "MRCML design-matrix model: inspect prior symmetry and whole-fit/focal MCSE before substantive interpretation.",
        patterns.warnings...,
        t.prior_symmetry.warnings...,
    ]
    chart = _person_chart(t)
    if !isnothing(chart)
        push!(ws, "Person coordinates were selected explicitly. Check group SDs, person intervals and sampler diagnostics for this design.")
    end
    if hasproperty(t.spec_record,:calibration)
        push!(ws,"External Gaussian calibration contributes location information. Inspect receiving_rank for the receiving sample alone.")
    elseif hasproperty(t.spec_record,:fixed_calibration)
        push!(ws,"Uncertainty is conditional on the supplied fixed calibration.")
    end
    for bdesc in psummary.structural_blocks
        if bdesc.block_role in (:facet_facet_interaction, :facet_step_interaction) &&
                bdesc.scale_prior !== nothing && !bdesc.scale_prior.second_moment_finite
            push!(ws, "Interaction block $(bdesc.name) uses heavy-tailed scale prior $(bdesc.distribution) with divergent second moment (df <= 2, e.g. Half-Cauchy); sparse interaction cells can induce HMC funnel divergences. Prefer zero-supporting HalfNormal (`truncated(Normal(0, s), 0, Inf)`) or Half-t (`df = 3–4`, `truncated(LocationScale(0, s, TDist(4)), 0, Inf)`).")
        end
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
        prior_summary = psummary,
        grouping = t.groups,
        (hasproperty(t.spec_record,:population) ? (;population=deepcopy(t.spec_record.population)) : (;))...,
        (hasproperty(t.spec_record,:missing_audit) ? (;missing_audit=deepcopy(t.spec_record.missing_audit)) : (;))...,
        response_patterns = patterns,
        warnings = ws,
    )
    hasproperty(t.spec_record,:calibration) && return merge(summary,(;calibration=deepcopy(t.spec_record.calibration)))
    return hasproperty(t.spec_record,:fixed_calibration) ?
        merge(summary,(;fixed_calibration=deepcopy(t.spec_record.fixed_calibration))) : summary
end

function contract(t::MRCMLTarget)
    is_supported_1d = get(t.spec_record, :source, :custom_mrcml_spec) === :structured_mfrm_spec &&
        !get(t.spec_record, :has_interactions, false) &&
        !get(t.spec_record, :has_lltm, false) &&
        isempty(get(t.spec_record, :random_effects, ())) &&
        !hasproperty(t.spec_record, :population) &&
        !hasproperty(t.spec_record, :calibration)
    return (;
        schema = "bayesianmgmfrm.mrcml_contract.v1",
        status = is_supported_1d ? :supported : :experimental_fitted_workflow,
        family = :mrcml_linear_logit_1d,
        dimensions = 1,
        multiplier = 1,
        facet_names = [b.name for b in t.facets],
        structural_blocks = [bm.name for bm in t.operator.block_meta],
        location_mode = t.location_mode,
        prior_measure = _mrcml_measure(t),
        prior_asymmetry_detected = t.prior_symmetry.prior_asymmetry_detected,
        step_owner = t.step_owner_spec,
        supported_methods = !isempty(get(t.spec_record,:random_effects,())) || hasproperty(t.spec_record,:calibration) || !isnothing(_person_chart(t)) ? (:nuts,) :
            hasproperty(t.spec_record,:population) || !t.allocation.conditional_joint_identified ? (:nuts,:mmle) : (:nuts, :mmle, :jmle),
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
        api = contract(t),
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

function _mrcml_fit_statistics(t::AbstractTarget, f; by::Symbol = :rater, level::Real = 0.95, seed::Integer = 1)
    t isa Union{MRCMLTarget,ExplanatoryTarget} || throw(ArgumentError(
        "Infit/Outfit diagnostics require an ordinal MRCML or explanatory fit; got $(typeof(t))"))
    lo, hi = interval_bounds(level)
    seed isa Integer && !(seed isa Bool) && 0 <= seed <= typemax(Int) ||
        throw(ArgumentError("seed must be a nonnegative integer representable as Int"))
    by_name, idx_vec, levs = if by in (:person, :entity)
        (:person, t.person, t.people)
    else
        bi = findfirst(b -> b.name === by, t.facets)
        bi === nothing && throw(ArgumentError(
            "unknown `by = $(repr(by))` facet; available: :person, $(Tuple(b.name for b in t.facets))"))
        fb = t.facets[bi]
        (fb.name, fb.index, fb.levels)
    end

    L = length(levs)
    obs_counts = [count(==(j), idx_vec) for j in 1:L]
    draws = f.record.run.draws
    S_draws = size(draws, 1)
    chains = f.record.run.controls.chains
    scores = _diagnostic_scores(t)
    mean_logweights = zero(_diagnostic_logweights(t,view(draws,1,:)))

    infit_obs = fill(NaN, S_draws, L)
    outfit_obs = fill(NaN, S_draws, L)
    infit_rep = fill(NaN, S_draws, L)
    outfit_rep = fill(NaN, S_draws, L)

    K_max = maximum(length, t.supports)
    pbuf = zeros(Float64, K_max)
    sum_w = zeros(Float64, L)
    cnt_w = zeros(Int, L)
    sum_e2_obs = zeros(Float64, L)
    sum_z2_obs = zeros(Float64, L)
    sum_e2_rep = zeros(Float64, L)
    sum_z2_rep = zeros(Float64, L)
    rng = MersenneTwister(Int(seed))

    for s in 1:S_draws
        fill!(sum_w, 0.0)
        fill!(cnt_w, 0)
        fill!(sum_e2_obs, 0.0)
        fill!(sum_z2_obs, 0.0)
        fill!(sum_e2_rep, 0.0)
        fill!(sum_z2_rep, 0.0)
        logweights = _diagnostic_logweights(t,view(draws,s,:))
        mean_logweights .+= logweights
        @inbounds for n in eachindex(t.person)
            sup = t.supports[t.group[n]]
            M_g = length(sup)
            eb,wn = _diagnostic_moments!(pbuf,logweights,n,scores[n])
            u_r = rand(rng)
            csum = 0.0
            lk_rep = M_g
            for lk in 1:M_g
                csum += pbuf[lk]
                if u_r <= csum
                    lk_rep = lk
                    break
                end
            end
            if wn > 1e-14
                j = idx_vec[n]
                yk_loc = t.category[n] - first(sup) + 1
                b_obs = scores[n][yk_loc]
                b_rep = scores[n][lk_rep]
                e2_o = (b_obs - eb)^2
                e2_r = (b_rep - eb)^2
                sum_w[j] += wn
                cnt_w[j] += 1
                sum_e2_obs[j] += e2_o
                sum_z2_obs[j] += e2_o / wn
                sum_e2_rep[j] += e2_r
                sum_z2_rep[j] += e2_r / wn
            end
        end
        @inbounds for j in 1:L
            if cnt_w[j] > 0 && sum_w[j] > 0.0
                infit_obs[s, j] = sum_e2_obs[j] / sum_w[j]
                outfit_obs[s, j] = sum_z2_obs[j] / cnt_w[j]
                infit_rep[s, j] = sum_e2_rep[j] / sum_w[j]
                outfit_rep[s, j] = sum_z2_rep[j] / cnt_w[j]
            end
        end
    end

    # Plug-in at mean model predictors, distinct from posterior-integrated MNSQ.
    mean_logweights ./= S_draws
    fill!(sum_w, 0.0)
    fill!(cnt_w, 0)
    fill!(sum_e2_obs, 0.0)
    fill!(sum_z2_obs, 0.0)
    @inbounds for n in eachindex(t.person)
        sup = t.supports[t.group[n]]
        eb,wn = _diagnostic_moments!(pbuf,mean_logweights,n,scores[n])
        if wn > 1e-14
            j = idx_vec[n]
            yk_loc = t.category[n] - first(sup) + 1
            b_obs = scores[n][yk_loc]
            e2_o = (b_obs - eb)^2
            sum_w[j] += wn
            cnt_w[j] += 1
            sum_e2_obs[j] += e2_o
            sum_z2_obs[j] += e2_o / wn
        end
    end

    rows = map(1:L) do j
        pname = "$(by_name)[$(repr(levs[j]))]"
        iv_obs = view(infit_obs, :, j)
        ov_obs = view(outfit_obs, :, j)
        iv_rep = view(infit_rep, :, j)
        ov_rep = view(outfit_rep, :, j)
        valid = all(isfinite, iv_obs) && all(isfinite, ov_obs)
        plug_in = (cnt_w[j] > 0 && sum_w[j] > 0.0) ? (sum_e2_obs[j] / sum_w[j]) : missing
        plug_out = cnt_w[j] > 0 ? (sum_z2_obs[j] / cnt_w[j]) : missing
        if valid
            mc_in = only(B._posterior_mcse_rows(reshape(iv_obs, :, 1), [pname], chains;
                probabilities = (lo, hi), parameter_space = :fit_statistic))
            mc_out = only(B._posterior_mcse_rows(reshape(ov_obs, :, 1), [pname], chains;
                probabilities = (lo, hi), parameter_space = :fit_statistic))
            p_in_up = mean(iv_rep .>= iv_obs)
            p_in_lo = mean(iv_rep .<= iv_obs)
            p_out_up = mean(ov_rep .>= ov_obs)
            p_out_lo = mean(ov_rep .<= ov_obs)
            (;
                parameter = pname,
                level = levs[j],
                n_observations = obs_counts[j],
                infit_mnsq_mean = mean(iv_obs),
                infit_mnsq_lower = quantile(iv_obs, lo),
                infit_mnsq_upper = quantile(iv_obs, hi),
                infit_mnsq_mcse = mc_in.mean_mcse,
                replicated_infit_mnsq_mean = mean(iv_rep),
                ppp_infit = p_in_up,
                ppp_infit_mcse = _diagnostic_tail_mcse(iv_obs, iv_rep, chains),
                ppp_infit_twosided = min(1.0, 2.0 * min(p_in_up, p_in_lo)),
                outfit_mnsq_mean = mean(ov_obs),
                outfit_mnsq_lower = quantile(ov_obs, lo),
                outfit_mnsq_upper = quantile(ov_obs, hi),
                outfit_mnsq_mcse = mc_out.mean_mcse,
                replicated_outfit_mnsq_mean = mean(ov_rep),
                ppp_outfit = p_out_up,
                ppp_outfit_mcse = _diagnostic_tail_mcse(ov_obs, ov_rep, chains),
                ppp_outfit_twosided = min(1.0, 2.0 * min(p_out_up, p_out_lo)),
                plugin_infit_mnsq = plug_in,
                plugin_outfit_mnsq = plug_out,
                plugin_caveat = :posterior_mean_shrinkage_attenuates_mnsq_below_one,
            )
        else
            (;
                parameter = pname,
                level = levs[j],
                n_observations = obs_counts[j],
                infit_mnsq_mean = missing,
                infit_mnsq_lower = missing,
                infit_mnsq_upper = missing,
                infit_mnsq_mcse = missing,
                replicated_infit_mnsq_mean = missing,
                ppp_infit = missing,
                ppp_infit_mcse = (;value=missing,status=:incomplete_draws_mcse_unavailable),
                ppp_infit_twosided = missing,
                outfit_mnsq_mean = missing,
                outfit_mnsq_lower = missing,
                outfit_mnsq_upper = missing,
                outfit_mnsq_mcse = missing,
                replicated_outfit_mnsq_mean = missing,
                ppp_outfit = missing,
                ppp_outfit_mcse = (;value=missing,status=:incomplete_draws_mcse_unavailable),
                ppp_outfit_twosided = missing,
                plugin_infit_mnsq = plug_in,
                plugin_outfit_mnsq = plug_out,
                plugin_caveat = :posterior_mean_shrinkage_attenuates_mnsq_below_one,
            )
        end
    end

    return (;
        schema = "bayesianmgmfrm.mrcml_fit_statistics.v1",
        kind = :fit_statistics,
        conditioning = :posterior_known_effects,
        by = by_name,
        level = Float64(level),
        seed = Int(seed),
        n_levels = L,
        n_draws = S_draws,
        plugin_caveat = :posterior_mean_shrinkage_attenuates_mnsq_below_one,
        cutoff_guidance = :uncalibrated_conventional_cutoffs_not_recommended_for_automatic_exclusion,
        rows,
        qualification = qualify(f),
        source_sample_content_hash = f.record.content_hash,
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
    b_kind = [b.kind === :white_scaled ? 1 :
              b.kind === :mvnormal ? 2 :
              b.kind === :hierarchical_lognormal ? 3 :
              b.kind === :hierarchical_half_normal ? 4 : 5 for b in t.prior_blocks]
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
        elseif _is_hierarchical_kind(b.kind)
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
    if _has_non_lognormal_scale(t)
        pkind = _person_scale_kind(t)
        data["person_scale_kind"] = pkind === :fixed ? 0 :
            pkind === :lognormal ? 1 :
            pkind === :half_normal ? 2 : 3
    end
    if hasproperty(t.spec_record,:population)
        p = t.spec_record.population
        gkind = _pop_sd_kind(p)
        n_gsd = length(p.logsd)
        sd_member = Int[_pop_sd_idx(p, i) for i in 1:length(t.people)]
        delete!(data,"person_sd")
        merge!(data,Dict(
            "G"=>length(p.groups),
            "n_group_sd"=>n_gsd,
            "group_sd_kind"=>(gkind === :lognormal ? 1 : gkind === :half_normal ? 2 : 3),
            "C"=>size(p.X,2),
            "X"=>p.X,
            "member"=>p.group_index,
            "sd_member"=>sd_member,
            "beta_start"=>first(p.beta),
            "sd_start"=>first(p.logsd),
            "beta_mean"=>p.coefficient_prior.mean,
            "beta_sd"=>p.coefficient_prior.sd,
            "logmean"=>p.sd_prior.logmean,
            "logsd"=>p.sd_prior.logsd,
        ))
        hasproperty(p,:person_chart) && (data["centered"] = Int.(p.person_chart.centered))
    end
    return data
end

function _mrcml_stan_code(grouped, person_chart=false, general_scale=false)
    person_data = grouped ? """int<lower=2> G;
  int<lower=1,upper=G> n_group_sd;
  int<lower=1,upper=3> group_sd_kind;
  int<lower=1> C;
  matrix[P,C] X;
  array[P] int<lower=1,upper=G> member;
  array[P] int<lower=1,upper=n_group_sd> sd_member;
  int<lower=1> beta_start, sd_start;
  real beta_mean, logmean;
  real<lower=0> beta_sd, logsd;""" : "real<lower=0> person_sd;"
    if general_scale
        person_data *= "\n  int<lower=0, upper=3> person_scale_kind;"
    end
    person_code = if grouped
        """vector[C] beta = beta_mean + beta_sd * segment(q,beta_start,C);
  vector[n_group_sd] sigma = group_sd_kind == 1 ?
    exp(logmean + logsd * segment(q,sd_start,n_group_sd)) :
    exp(segment(q,sd_start,n_group_sd));
  vector[P] theta = X * beta + sigma[sd_member] .* head(q,P);"""
    elseif general_scale
        """real s_p;
  if (person_hyper_idx == 0) {
    s_p = person_sd;
  } else if (person_scale_kind == 1) {
    s_p = exp(person_logmean + person_logsd * q[person_hyper_idx]);
  } else {
    s_p = exp(q[person_hyper_idx]);
  }
  vector[P] theta = s_p * q[1:P];"""
    else
        "real s_p = person_hyper_idx == 0 ? person_sd : exp(person_logmean + person_logsd * q[person_hyper_idx]);\n  vector[P] theta = s_p * q[1:P];"
    end
    raw_prior = "target += -0.5 * D * log(2 * pi()) - 0.5 * dot_self(q);"
    if person_chart
        person_data *= "\n  array[P] int<lower=0,upper=1> centered;"
        person_code = """vector[C] beta = beta_mean + beta_sd * segment(q,beta_start,C);
  vector[n_group_sd] sigma = group_sd_kind == 1 ?
    exp(logmean + logsd * segment(q,sd_start,n_group_sd)) :
    exp(segment(q,sd_start,n_group_sd));
  vector[P] mu = X * beta;
  vector[P] theta;
  vector[D] white = q;
  for (p in 1:P) {
    if (centered[p] == 1) {
      theta[p] = q[p];
      white[p] = (theta[p] - mu[p]) / sigma[sd_member[p]];
      target += -log(sigma[sd_member[p]]);
    } else {
      theta[p] = mu[p] + sigma[sd_member[p]] * q[p];
    }
  }"""
        raw_prior = "target += -0.5 * D * log(2 * pi()) - 0.5 * dot_self(white);"
    end
    if grouped && general_scale
        raw_prior *= """
  if (group_sd_kind == 2) {
    for (g in 1:n_group_sd) {
      real u = q[sd_start + g - 1];
      target += normal_lpdf(sigma[g] | 0, logsd) + log(2.0) + u - std_normal_lpdf(u);
    }
  } else if (group_sd_kind == 3) {
    for (g in 1:n_group_sd) {
      real u = q[sd_start + g - 1];
      target += student_t_lpdf(sigma[g] | logmean, 0, logsd) + log(2.0) + u - std_normal_lpdf(u);
    }
  }"""
    end
    if !grouped && general_scale
        raw_prior *= """
  if (person_hyper_idx > 0 && person_scale_kind == 2) {
    real u = q[person_hyper_idx];
    target += normal_lpdf(s_p | 0, person_logsd) + log(2.0) + u - std_normal_lpdf(u);
  } else if (person_hyper_idx > 0 && person_scale_kind == 3) {
    real u = q[person_hyper_idx];
    target += student_t_lpdf(s_p | person_logmean, 0, person_logsd) + log(2.0) + u - std_normal_lpdf(u);
  }"""
    end
    b_kind_upper = general_scale ? 5 : 3
    block_loop_hier = if general_scale
        """      } else if (b_kind[b] == 3) {
        real sig = exp(b_logmean[b] + b_logsd[b] * q[b_hyper_idx[b]]);
        eta_xi[es:(es + len - 1)] = (sig * b_iso[b]) * q[rs:(rs + len - 1)];
      } else if (b_kind[b] == 4) {
        real u = q[b_hyper_idx[b]];
        real sig = exp(u);
        eta_xi[es:(es + len - 1)] = (sig * b_iso[b]) * q[rs:(rs + len - 1)];
        target += normal_lpdf(sig | 0, b_logsd[b]) + log(2.0) + u - std_normal_lpdf(u);
      } else {
        real u = q[b_hyper_idx[b]];
        real sig = exp(u);
        eta_xi[es:(es + len - 1)] = (sig * b_iso[b]) * q[rs:(rs + len - 1)];
        target += student_t_lpdf(sig | b_logmean[b], 0, b_logsd[b]) + log(2.0) + u - std_normal_lpdf(u);
      }"""
    else
        """      } else {
        real sig = exp(b_logmean[b] + b_logsd[b] * q[b_hyper_idx[b]]);
        eta_xi[es:(es + len - 1)] = (sig * b_iso[b]) * q[rs:(rs + len - 1)];
      }"""
    end
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
  array[n_blocks] int<lower=1, upper=$b_kind_upper> b_kind;
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
$block_loop_hier
    }
  }
  vector[M_tot] v_pat = c_pat;
  for (nz in 1:nnz_A) {
    v_pat[A_row[nz]] += A_val[nz] * eta_xi[A_col[nz]];
  }
  $raw_prior
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

_is_scale_prior_dist(val) = val isa D.LogNormal || val isa D.Truncated

function _parse_scale_or_lognormal(val, active::Bool, label)
    if val isa D.LogNormal
        active || throw(ArgumentError("$label cannot use a LogNormal hyperprior on an inactive 0-df block"))
        mu, sd = Float64.(D.params(val))
        isfinite(mu) && isfinite(sd) && sd > 0 && isfinite(exp(mu)) && exp(mu) > 0 ||
            throw(ArgumentError("$label LogNormal parameters must be finite with logsd > 0"))
        return (; kind = :lognormal, sd = exp(mu), logmean = mu, logsd = sd)
    elseif val isa D.Truncated
        active || throw(ArgumentError("$label cannot use a zero-supporting scale hyperprior on an inactive 0-df block"))
        lo, hi = Float64(val.lower), Float64(val.upper)
        (lo == 0.0 && isinf(hi) && hi > 0.0) ||
            throw(ArgumentError("$label truncated scale hyperprior must have support [0, Inf); got [$lo, $hi]"))
        u = val.untruncated
        if u isa D.Normal
            mu_u, sc_u = Float64.(D.params(u))
            mu_u == 0.0 && isfinite(sc_u) && sc_u > 0.0 ||
                throw(ArgumentError("$label HalfNormal hyperprior requires Normal(0, scale) with scale > 0"))
            return (; kind = :half_normal, sd = D.median(val), logmean = 0.0, logsd = sc_u)
        elseif u isa D.TDist
            df_u = Float64(D.dof(u))
            isfinite(df_u) && df_u > 0.0 ||
                throw(ArgumentError("$label HalfStudentT hyperprior requires df > 0"))
            return (; kind = :half_student_t, sd = D.median(val), logmean = df_u, logsd = 1.0)
        elseif u isa D.Cauchy
            loc_u, sc_u = Float64.(D.params(u))
            loc_u == 0.0 && isfinite(sc_u) && sc_u > 0.0 ||
                throw(ArgumentError("$label HalfCauchy hyperprior requires Cauchy(0, scale) with scale > 0"))
            return (; kind = :half_student_t, sd = sc_u, logmean = 1.0, logsd = sc_u)
        elseif u isa D.LocationScale && u.ρ isa D.TDist
            loc_u, sc_u = Float64(u.μ), Float64(u.σ)
            df_u = Float64(D.dof(u.ρ))
            loc_u == 0.0 && isfinite(sc_u) && sc_u > 0.0 && isfinite(df_u) && df_u > 0.0 ||
                throw(ArgumentError("$label HalfStudentT hyperprior requires LocationScale(0, scale, TDist(df)) with scale > 0 and df > 0"))
            return (; kind = :half_student_t, sd = sc_u * D.median(D.truncated(D.TDist(df_u), 0.0, Inf)), logmean = df_u, logsd = sc_u)
        end
        throw(ArgumentError("$label unsupported truncated scale hyperprior $(typeof(val)); use LogNormal(mu, sd), truncated(Normal(0, s), 0, Inf), truncated(TDist(df), 0, Inf), truncated(LocationScale(0, s, TDist(df)), 0, Inf), or truncated(Cauchy(0, s), 0, Inf)"))
    end
    s = _sd(val, active, label)
    return (; kind = :fixed, sd = s, logmean = 0.0, logsd = 1.0)
end

function _normalize_interaction_specs(interactions, prior_sd_nt, facet_names::Tuple, context_names::Tuple = ())
    interactions === nothing && return NamedTuple[]
    raw_list = interactions isa Tuple ? collect(Any, interactions) :
               interactions isa AbstractVector ? collect(Any, interactions) :
               throw(ArgumentError("interactions must be a Tuple or Vector of 2-way pairs `(f1, f2)` or `(f1, :step)`"))
    isempty(raw_list) && return NamedTuple[]

    all_roles = (facet_names..., context_names...)
    int_priors = (prior_sd_nt !== nothing && hasproperty(prior_sd_nt, :interactions)) ? prior_sd_nt.interactions : nothing
    parsed = NamedTuple[]
    seen = Set{Tuple{Symbol,Symbol}}()

    for item in raw_list
        pair, inline_prior, focal_val, ref_val = if item isa NamedTuple
            hasproperty(item, :pair) || throw(ArgumentError("NamedTuple interaction entry must specify `pair = (a, b)`"))
            all(k -> k in (:pair, :prior, :focal, :reference), keys(item)) ||
                throw(ArgumentError("NamedTuple interaction entry accepts only `pair`, `prior`, `focal`, and `reference`"))
            (item.pair,
             hasproperty(item, :prior) ? item.prior : nothing,
             hasproperty(item, :focal) ? item.focal : nothing,
             hasproperty(item, :reference) ? item.reference : nothing)
        elseif item isa Tuple && length(item) == 2 && all(x -> x isa Symbol, item)
            (item, nothing, nothing, nothing)
        elseif item isa Pair && item.first isa Tuple && length(item.first) == 2
            (item.first, item.second, nothing, nothing)
        else
            throw(ArgumentError("interaction entry $(repr(item)) must be `(f1, f2)`, `(f1, :step)`, `(f1, f2) => sd`, or `(pair = ..., prior = ..., [focal = ...])`"))
        end
        a, b = Symbol(pair[1]), Symbol(pair[2])
        is_step = b in (:step, :steps) || a in (:step, :steps)
        if is_step
            focal_val === nothing || throw(ArgumentError("`focal` split-level mode applies to 2-way `(facet, group)` interactions, not `:step`"))
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
                elseif int_priors isa Real || _is_scale_prior_dist(int_priors)
                    pr = int_priors
                end
            end
            push!(parsed, (; kind = :facet_step, f1 = f_sym, f2 = :step, key = key_sym, prior = pr))
        elseif focal_val !== nothing
            a in all_roles && b in all_roles ||
                throw(ArgumentError("interaction roles ($a, $b) must belong to declared facets or population group $all_roles"))
            a != b || throw(ArgumentError("self-interaction ($a, $a) is invalid"))
            !(a in context_names && b in context_names) ||
                throw(ArgumentError("focal DFF interaction ($a, $b) must involve at least one substantive facet"))
            f1, f2 = (a in context_names && !(b in context_names)) ? (b, a) : (a, b)
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
                elseif int_priors isa Real || int_priors isa D.Normal || _is_scale_prior_dist(int_priors)
                    pr = int_priors
                end
            end
            push!(parsed, (; kind = :focal_dff, f1, f2, focal = focal_val, reference = ref_val, key = key1, prior = pr))
        else
            a in all_roles && b in all_roles ||
                throw(ArgumentError("interaction facets ($a, $b) must belong to declared facets $all_roles"))
            a != b || throw(ArgumentError("self-interaction ($a, $a) is invalid"))
            !(a in context_names && b in context_names) ||
                throw(ArgumentError("interaction ($a, $b) must involve at least one substantive facet"))
            # Canonicalize order to match declaration order in `all_roles` (substantive facets precede context/population groups)
            ia = findfirst(==(a), all_roles)
            ib = findfirst(==(b), all_roles)
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
                elseif int_priors isa Real || _is_scale_prior_dist(int_priors)
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


include("mrcml_specification.jl")

function _to_mrcml_spec(t::MRCMLTarget)::MRCMLSpec
    isempty(get(t.spec_record,:random_effects,())) || throw(ArgumentError("iid shared effects require method=:nuts"))
    hasproperty(t.spec_record, :calibration) && throw(ArgumentError(
        "two-stage covariance propagation requires a prior-free MMLE specification (`prior = :none`) with estimate_mean=true or a grouped population"))
    pop = get(t.spec_record, :population, nothing)
    srec = if !isnothing(pop)
        hasproperty(pop, :person_chart) && throw(ArgumentError("person_coordinates selects NUTS coordinates; omit it for MMLE"))
        pop_clean = Base.structdiff(pop, (; coefficient_prior = nothing, sd_prior = nothing, beta = nothing, logsd = nothing))
        merge(deepcopy(t.spec_record), (; population = pop_clean))
    else
        deepcopy(t.spec_record)
    end
    f_tuples = [(; name = b.name, column = b.column, levels = deepcopy(b.levels), index = copy(b.index)) for b in t.facets]
    alloc = _mrcml_allocation(t.person, t.people, t.facets, t.operator, t.location_mode; n_hyper = 0)
    return MRCMLSpec(
        deepcopy(t.table), deepcopy(t.columns), copy(t.person), deepcopy(t.people),
        copy(t.category), copy(t.categories), copy(t.supports), f_tuples,
        t.owner, deepcopy(t.step_owner_spec), copy(t.group), deepcopy(t.group_levels),
        t.operator, t.location_mode, alloc, deepcopy(t.groups), srec,
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
stan_code(t::Target) = (hasproperty(t.spec_record,:population) || AF._has_non_lognormal_scale(t)) ?
    AF._mrcml_stan_code(hasproperty(t.spec_record,:population), !isnothing(AF._person_chart(t)), AF._has_non_lognormal_scale(t)) : stan_code()

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
    elseif x isa AF.B.ScaleIdentifiedMGMFRM.Target || x isa AF.B.ScaleIdentifiedMGMFRM.Fit
        return AF.B.ScaleIdentifiedMGMFRM.design_matrices(x)
    end
    throw(ArgumentError("MRCML.design_matrices requires an MRCMLTarget, MRCMLSpec, MRCML Fit, or ScaleIdentifiedMGMFRM Target/Fit; got $(typeof(x))"))
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
    elseif AF._is_scale_prior_dist(prior)
        lp = AF._parse_scale_or_lognormal(prior, true, :prior)
        erng = 1:d_free
        rrng = (raw_start + 1):(raw_start + d_free)
        hidx = raw_start + d_free + 1
        blk = AF.MRCMLPriorBlock(block_name, AF._block_kind_from_scale(lp.kind), erng, erng, rrng, hidx,
            zeros(Float64, d_free), Float64[], zeros(Float64, 0, 0), 1.0, lp.sd, lp.logmean, lp.logsd)
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
    if pspec.kind !== :fixed
        raw_end += 1
        p_hyp = raw_end
    end
    if pspec.kind in (:half_normal, :half_student_t)
        spec_rec = merge(spec_rec, (; person_scale_prior = (; kind = pspec.kind, p1 = pspec.logmean, p2 = pspec.logsd)))
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
