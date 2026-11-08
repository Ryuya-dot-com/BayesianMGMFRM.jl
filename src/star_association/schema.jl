struct CriterionMeta
    id::String
    role::Symbol
    levels::Vector{Int}
    direction::Symbol
    threshold_group::String
    M::Int
    canonical_to_raw::Vector{Int}
end

struct PriorConfig
    entity_log_sd_mean::Float64
    rater_log_sd_mean::Float64
    log_sd_sd::Float64
    entity_lkj_eta::Float64
    rater_lkj_eta::Float64
    mu_sd::Float64
    step_sd::Float64
    step_spacing::Float64
    phi_sd::Float64
end

struct ParameterizationConfig
    entity_mode::Symbol
    rater_mode::Symbol
    entity_cp_min_hd::Float64
    rater_cp_min_hd::Float64
    basis_order::Symbol
    include_phi::Bool
    reference_prior::Bool
end

"""
    FacetBasis

Precomputed zero-sum orthonormal Helmert basis mapping and Schur-complement effective
contrast counts for one facet (`:entity` or `:rater`).

Under `basis_order = :descending_schur` (default):
- Levels are ordered by non-increasing observation count (`perm`), ensuring that
  contrasts `1:(k-1)` span exclusively the `k` most-observed levels and put exact weight `0`
  on sparser levels.
- `effective_counts[j]` equals the exact Rao-Searle Schur-complement contrast precision
  `[(H' * W^{-1} * H)_{jj}]^{-1} = j*(j+1) / (sum_{m=1}^j c_{(m)}^{-1} + j^2 * c_{(j+1)}^{-1})`
  in a Gaussian working design with diagonal count weights `W`, after profiling
  out its intercept and all other `n - 2` contrasts. It is not the marginal
  posterior precision of the full crossed ordinal model.
  This quantity depends solely on the sorted count multiset (100% invariant to all `n!`
  permutations of user level IDs, including ties) and satisfies `c_{(j+1)} <= eff[j] < 2 * c_{(j+1)}`.
"""
struct FacetBasis
    basis_order::Symbol
    perm::Vector{Int}
    inv_perm::Vector{Int}
    raw_counts::Vector{Int}
    sorted_counts::Vector{Float64}
    effective_counts::Vector{Float64}
    cp_mask::BitVector
    n_cp::Int
end

struct StarModel
    I::Int
    R::Int
    D::Int
    M::Vector{Int}
    entity::Vector{Int}
    rater::Vector{Int}
    y::Matrix{Int}
    entity_levels::Vector{String}
    rater_levels::Vector{String}
    event_ids::Vector{String}
    criteria::Vector{CriterionMeta}
    prior::PriorConfig
    spec::ParameterizationConfig
    entity_basis::FacetBasis
    rater_basis::FacetBasis
    dim::Int
end

const RATER_COUNT_STRATA = (
    (; label = "1", min_n = 1, max_n = 1),
    (; label = "2-4", min_n = 2, max_n = 4),
    (; label = "5-26", min_n = 5, max_n = 26),
    (; label = ">=27", min_n = 27, max_n = typemax(Int)),
)

_nonempty_str(x) = x isa AbstractString && !isempty(strip(x))
_is_int_score(x) = x isa Integer && !(x isa Bool)

function _weighted_helmert_diag(weights::AbstractVector{Float64})
    n = length(weights)
    out = Vector{Float64}(undef, n - 1)
    prefix = 0.0
    for j in 1:(n - 1)
        prefix += weights[j]
        out[j] = (prefix + j * j * weights[j + 1]) / (j * (j + 1))
    end
    return out
end

function _schur_harmonic_counts(sorted_counts::AbstractVector{Float64})
    n = length(sorted_counts)
    eff = Vector{Float64}(undef, n - 1)
    inv_prefix = 0.0
    has_zero = false
    for j in 1:(n - 1)
        cj = sorted_counts[j]
        c_next = sorted_counts[j + 1]
        if cj <= 0.0
            has_zero = true
        else
            inv_prefix += 1.0 / cj
        end
        if has_zero || c_next <= 0.0
            eff[j] = 0.0
        else
            denom = inv_prefix + (j * j) / c_next
            eff[j] = (j * (j + 1)) / denom
        end
    end
    return eff
end

function _build_facet_basis(
    ids::AbstractVector{Int},
    n::Int,
    mode::Symbol,
    min_hd::Float64,
    basis_order::Symbol,
)
    basis_order in (:descending_schur, :legacy_lexicographic) ||
        throw(ArgumentError("basis_order must be :descending_schur or :legacy_lexicographic"))
    raw_counts = zeros(Int, n)
    @inbounds for id in ids
        raw_counts[id] += 1
    end
    if basis_order === :descending_schur
        perm = sortperm(1:n; by = u -> (-raw_counts[u], u))
        inv_perm = invperm(perm)
        sorted_counts = Float64.(raw_counts[perm])
        eff_counts = _schur_harmonic_counts(sorted_counts)
    else
        perm = collect(1:n)
        inv_perm = collect(1:n)
        sorted_counts = Float64.(raw_counts)
        eff_counts = _weighted_helmert_diag(sorted_counts)
    end
    cp_mask = if mode === :cp
        trues(n - 1)
    elseif mode === :ncp
        falses(n - 1)
    else
        BitVector(eff_counts .>= min_hd)
    end
    return FacetBasis(basis_order, perm, inv_perm, raw_counts, sorted_counts, eff_counts, cp_mask, count(cp_mask))
end

function _layout(I::Int, R::Int, M::AbstractVector{Int}, include_phi::Bool)
    D = length(M)
    n_corr = (D * (D - 1)) ÷ 2
    offset = 0
    function take(n::Int)
        rng = (offset + 1):(offset + n)
        offset += n
        return rng
    end
    zi = take(D * (I - 1))
    zr = take(D * (R - 1))
    steps = [take(mc - 1) for mc in M]
    mu = take(D)
    si = take(D)
    sr = take(D)
    ci = take(n_corr)
    cr = take(n_corr)
    phi = include_phi ? take(D - 1) : (offset + 1):offset
    return (; zi, zr, steps, mu, si, sr, ci, cr, phi, D_criteria = D, n_corr, n_branch = D - 1, dim = offset)
end

_layout(m::StarModel) = _layout(m.I, m.R, m.M, m.spec.include_phi)

function _build_criterion_meta(c, role::Symbol)
    hasproperty(c, :criterion) && hasproperty(c, :levels) ||
        throw(ArgumentError("each criterion requires :criterion and :levels"))
    cid = String(strip(String(c.criterion)))
    _nonempty_str(cid) || throw(ArgumentError("criterion ID must be a nonempty string"))
    dir = hasproperty(c, :direction) ? c.direction : :higher_is_more
    dir in (:higher_is_more, :higher_is_less) ||
        throw(ArgumentError("criterion '$cid' direction must be :higher_is_more or :higher_is_less"))
    tgroup = hasproperty(c, :threshold_group) ? String(strip(String(c.threshold_group))) : cid
    _nonempty_str(tgroup) || throw(ArgumentError("threshold_group must be a nonempty string"))
    lvs = collect(c.levels)
    length(lvs) >= 2 && all(_is_int_score, lvs) && issorted(lvs) && allunique(lvs) ||
        throw(ArgumentError("criterion '$cid' levels must be >= 2 strictly increasing integers"))
    lv_int = Int.(lvs)
    can2raw = dir === :higher_is_more ? lv_int : reverse(lv_int)
    return CriterionMeta(cid, role, lv_int, dir, tgroup, length(lv_int) - 1, can2raw)
end

function _parse_criteria(criteria, root::AbstractString)
    length(criteria) >= 2 || throw(ArgumentError("at least 2 criteria are required"))
    root_id = String(strip(root))
    raw_ids = [hasproperty(c, :criterion) ? String(strip(String(c.criterion))) : "" for c in criteria]
    length(unique(raw_ids)) == length(raw_ids) || throw(ArgumentError("duplicate criterion ID"))
    root_pos = findfirst(==(root_id), raw_ids)
    root_pos !== nothing || throw(ArgumentError("root criterion '$root_id' not found in criteria"))
    ordered = vcat([criteria[root_pos]], [criteria[i] for i in eachindex(criteria) if i != root_pos])
    metas = [_build_criterion_meta(ordered[i], i == 1 ? :root : :branch) for i in eachindex(ordered)]
    length(unique(m.threshold_group for m in metas)) == length(metas) ||
        throw(ArgumentError("StarAssociation requires distinct threshold_group per criterion"))
    return metas
end

@inline function _encode_raw_score(c::CriterionMeta, raw_val::Integer)
    _is_int_score(raw_val) || throw(ArgumentError("score must be an integer (not Bool)"))
    idx = searchsortedfirst(c.levels, Int(raw_val))
    (idx <= length(c.levels) && c.levels[idx] == raw_val) ||
        throw(ArgumentError("score $raw_val outside declared levels for criterion '$(c.id)'"))
    return c.direction === :higher_is_more ? (idx - 1) : (c.M + 1 - idx)
end

function _parse_prior(nt, include_phi::Bool)
    nt isa PriorConfig && return nt
    nt isa NamedTuple || throw(ArgumentError("prior must be an explicit NamedTuple"))
    ent_m = if haskey(nt, :entity_log_sd_mean)
        nt.entity_log_sd_mean
    elseif haskey(nt, :image_log_sd_mean)
        nt.image_log_sd_mean
    else
        throw(ArgumentError("missing entity_log_sd_mean"))
    end
    mu_s = if haskey(nt, :mu_sd)
        nt.mu_sd
    elseif haskey(nt, :intercept_sd)
        nt.intercept_sd
    else
        throw(ArgumentError("missing mu_sd"))
    end
    eta_e = haskey(nt, :entity_lkj_eta) ? nt.entity_lkj_eta : nt.lkj_eta
    eta_r = haskey(nt, :rater_lkj_eta) ? nt.rater_lkj_eta : nt.lkj_eta
    phi_s = (include_phi || haskey(nt, :phi_sd)) ? nt.phi_sd : 1.0
    vals = Float64.((ent_m, nt.rater_log_sd_mean, nt.log_sd_sd, eta_e, eta_r, mu_s, nt.step_sd, nt.step_spacing, phi_s))
    all(isfinite, vals) || throw(ArgumentError("all prior parameters must be finite"))
    (vals[3] > 0 && vals[4] > 0 && vals[5] > 0 && vals[6] > 0 && vals[7] > 0 && vals[9] > 0) ||
        throw(ArgumentError("prior scale and LKJ shape parameters must be strictly positive"))
    return PriorConfig(vals...)
end

PriorConfig(; kwargs...) = _parse_prior((; kwargs...), true)

function _prior_namedtuple(p::PriorConfig)
    return (;
        entity_log_sd_mean = p.entity_log_sd_mean,
        rater_log_sd_mean = p.rater_log_sd_mean,
        log_sd_sd = p.log_sd_sd,
        entity_lkj_eta = p.entity_lkj_eta,
        rater_lkj_eta = p.rater_lkj_eta,
        mu_sd = p.mu_sd,
        step_sd = p.step_sd,
        step_spacing = p.step_spacing,
        phi_sd = p.phi_sd,
    )
end

const DEFAULT_CP_MIN_INFO_RATIO = 8.0

# Clipped reference-profile variance used for routing/preconditioning, not full
# posterior Fisher information. The cutoff above is an engineering tuning choice.
function _pcm_reference_fisher(mc::Int, step_spacing::Float64)
    mc == 1 && return 0.25
    u = zeros(Float64, mc + 1)
    acc = 0.0
    for k in 1:mc
        acc -= step_spacing * (k - 0.5 * (mc + 1))
        u[k + 1] = acc
    end
    umax = maximum(u)
    p = exp.(u .- umax)
    p ./= sum(p)
    m1 = sum(k * p[k + 1] for k in 0:mc)
    m2 = sum((k * k) * p[k + 1] for k in 0:mc)
    v_ref = max(m2 - m1 * m1, 1e-6)
    v_unif = mc * (mc + 2) / 12.0
    return min(v_ref, v_unif)
end

function _prs_min_effective_count(
    log_sd_mean::Float64,
    step_spacing::Float64,
    M_vec::AbstractVector{Int},
    info_ratio::Float64,
)
    v_min = minimum(_pcm_reference_fisher(mc, step_spacing) for mc in M_vec)
    prior_var = exp(2.0 * log_sd_mean)
    return info_ratio / max(prior_var * v_min, eps(Float64))
end

function _parse_parameterization(
    param,
    association::Bool,
    reference_prior::Bool,
    pr::PriorConfig,
    M_vec::AbstractVector{Int};
    basis_order::Union{Nothing, Symbol} = nothing,
)
    if param isa ParameterizationConfig
        bo = basis_order === nothing ? param.basis_order : basis_order
        bo in (:descending_schur, :legacy_lexicographic) ||
            throw(ArgumentError("basis_order must be :descending_schur or :legacy_lexicographic"))
        return ParameterizationConfig(
            param.entity_mode,
            param.rater_mode,
            param.entity_cp_min_hd,
            param.rater_cp_min_hd,
            bo,
            association,
            reference_prior,
        )
    elseif param isa Symbol
        e_mode = param
        r_mode = param
        bo = basis_order === nothing ? :descending_schur : basis_order
        bo in (:descending_schur, :legacy_lexicographic) ||
            throw(ArgumentError("basis_order must be :descending_schur or :legacy_lexicographic"))
        if bo === :descending_schur
            e_hd = _prs_min_effective_count(pr.entity_log_sd_mean, pr.step_spacing, M_vec, DEFAULT_CP_MIN_INFO_RATIO)
            r_hd = _prs_min_effective_count(pr.rater_log_sd_mean, pr.step_spacing, M_vec, DEFAULT_CP_MIN_INFO_RATIO)
        else
            e_hd = 27.0
            r_hd = 27.0
        end
    elseif param isa NamedTuple
        e_mode = get(param, :entity, get(param, :entity_mode, :cp_ncp))
        r_mode = get(param, :rater, get(param, :rater_mode, :cp_ncp))
        bo = basis_order === nothing ? Symbol(get(param, :basis_order, :descending_schur)) : basis_order
        bo in (:descending_schur, :legacy_lexicographic) ||
            throw(ArgumentError("basis_order must be :descending_schur or :legacy_lexicographic"))
        info_ratio = Float64(get(param, :cp_min_info_ratio, DEFAULT_CP_MIN_INFO_RATIO))
        (isfinite(info_ratio) && info_ratio >= 0.0) ||
            throw(ArgumentError("cp_min_info_ratio must be finite and >= 0"))
        has_base_hd = haskey(param, :cp_min_hd)
        def_e_hd = if has_base_hd
            Float64(param.cp_min_hd)
        elseif bo === :descending_schur
            _prs_min_effective_count(pr.entity_log_sd_mean, pr.step_spacing, M_vec, info_ratio)
        else
            27.0
        end
        def_r_hd = if has_base_hd
            Float64(param.cp_min_hd)
        elseif bo === :descending_schur
            _prs_min_effective_count(pr.rater_log_sd_mean, pr.step_spacing, M_vec, info_ratio)
        else
            27.0
        end
        e_hd = Float64(get(param, :entity_cp_min_hd, def_e_hd))
        r_hd = Float64(get(param, :rater_cp_min_hd, def_r_hd))
    else
        throw(ArgumentError("parameterization must be :cp, :ncp, :cp_ncp, or a NamedTuple"))
    end
    (e_mode in (:cp, :ncp, :cp_ncp) && r_mode in (:cp, :ncp, :cp_ncp)) ||
        throw(ArgumentError("modes must be in (:cp, :ncp, :cp_ncp)"))
    (isfinite(e_hd) && e_hd >= 0 && isfinite(r_hd) && r_hd >= 0) ||
        throw(ArgumentError("cp_min_hd thresholds must be finite and >= 0"))
    return ParameterizationConfig(e_mode, r_mode, e_hd, r_hd, bo, association, reference_prior)
end

function _construct_star_model(
    I::Int,
    R::Int,
    D::Int,
    M_vec::Vector{Int},
    ent_v::Vector{Int},
    rat_v::Vector{Int},
    y_mat::Matrix{Int},
    entity_levels::Vector{String},
    rater_levels::Vector{String},
    event_ids::Vector{String},
    metas::Vector{CriterionMeta},
    pr::PriorConfig,
    spec::ParameterizationConfig,
)
    eb = _build_facet_basis(ent_v, I, spec.entity_mode, spec.entity_cp_min_hd, spec.basis_order)
    rb = _build_facet_basis(rat_v, R, spec.rater_mode, spec.rater_cp_min_hd, spec.basis_order)
    dim = _layout(I, R, M_vec, spec.include_phi).dim
    return StarModel(
        I, R, D, M_vec, ent_v, rat_v, y_mat,
        entity_levels, rater_levels, event_ids, metas,
        pr, spec, eb, rb, dim,
    )
end

function _bipartite_components(entity::AbstractVector{Int}, rater::AbstractVector{Int}, I::Int, R::Int)
    parent = collect(1:(I + R))
    function find_root(x::Int)
        while parent[x] != x
            parent[x] = parent[parent[x]]
            x = parent[x]
        end
        return x
    end
    for e in eachindex(entity)
        ri = find_root(entity[e])
        rr = find_root(I + rater[e])
        if ri != rr
            parent[rr] = ri
        end
    end
    comp_map = Dict{Int, Int}()
    ent_comp = [get!(comp_map, find_root(i)) do; length(comp_map) + 1; end for i in 1:I]
    rat_comp = [get!(comp_map, find_root(I + r)) do; length(comp_map) + 1; end for r in 1:R]
    n_comp = length(comp_map)
    sizes = [
        (;
            component = c,
            n_entities = count(==(c), ent_comp),
            n_raters = count(==(c), rat_comp),
            n_events = count(e -> ent_comp[entity[e]] == c, eachindex(entity)),
        ) for c in 1:n_comp
    ]
    return (;
        is_connected = n_comp == 1,
        n_components = n_comp,
        entity_component = ent_comp,
        rater_component = rat_comp,
        components = sizes,
    )
end

function _normalize_row_columns(data, entity_key::Symbol)
    if data isa NamedTuple
        for k in (:observation_id, :rating_event_id, entity_key, :rater, :criterion, :score)
            haskey(data, k) || throw(ArgumentError("missing required column :$k"))
        end
        return (;
            obs = data.observation_id,
            ev = data.rating_event_id,
            ent = getproperty(data, entity_key),
            rat = data.rater,
            crit = data.criterion,
            score = data.score,
        )
    end
    !isempty(data) || throw(ArgumentError("observed rows must not be empty"))
    for r in data, k in (:observation_id, :rating_event_id, entity_key, :rater, :criterion, :score)
        hasproperty(r, k) || throw(ArgumentError("row missing required field :$k"))
    end
    return (;
        obs = [r.observation_id for r in data],
        ev = [r.rating_event_id for r in data],
        ent = [getproperty(r, entity_key) for r in data],
        rat = [r.rater for r in data],
        crit = [r.criterion for r in data],
        score = [r.score for r in data],
    )
end

function _assemble_events_from_columns(cols, metas::Vector{CriterionMeta})
    n_rows = length(cols.obs)
    D = length(metas)
    n_rows > 0 || throw(ArgumentError("observed rows must not be empty"))
    crit_idx_map = Dict(m.id => idx for (idx, m) in enumerate(metas))
    seen_obs = Set{String}()
    event_order = String[]
    event_slot = Dict{String, Int}()
    ev_owners = Tuple{String, String}[]
    scores_list = Vector{Int}[]
    for r_i in 1:n_rows
        oid = String(cols.obs[r_i])
        eid = String(cols.ev[r_i])
        ent = String(cols.ent[r_i])
        rat = String(cols.rat[r_i])
        cid = String(cols.crit[r_i])
        all(_nonempty_str, (oid, eid, ent, rat, cid)) ||
            throw(ArgumentError("all IDs must be nonempty strings"))
        oid in seen_obs && throw(ArgumentError("duplicate observation_id '$oid'"))
        push!(seen_obs, oid)
        c_idx = get(crit_idx_map, cid, 0)
        c_idx > 0 || throw(ArgumentError("undeclared criterion '$cid'"))
        slot = get!(event_slot, eid) do
            push!(event_order, eid)
            push!(ev_owners, (ent, rat))
            push!(scores_list, fill(-1, D))
            return length(event_order)
        end
        ev_owners[slot] == (ent, rat) ||
            throw(ArgumentError("rating_event_id '$eid' changes entity or rater"))
        scores_list[slot][c_idx] == -1 ||
            throw(ArgumentError("duplicate ($eid, $cid) rating"))
        scores_list[slot][c_idx] = _encode_raw_score(metas[c_idx], cols.score[r_i])
    end
    all(s -> all(>=(0), s), scores_list) ||
        throw(ArgumentError("every rating_event_id must observe all $D declared criteria"))
    return event_order, ev_owners, scores_list
end

function model_from_indexed(
    entity::AbstractVector{<:Integer},
    rater::AbstractVector{<:Integer},
    y_in,
    metas::Vector{CriterionMeta};
    prior,
    entity_levels::Vector{String},
    rater_levels::Vector{String},
    event_ids::Vector{String},
    parameterization = :cp_ncp,
    basis_order::Union{Nothing, Symbol} = nothing,
    association::Bool = true,
    reference_prior::Bool = true,
    require_connected::Bool = false,
)
    I = length(entity_levels)
    R = length(rater_levels)
    D = length(metas)
    N = length(entity)
    (I >= 2 && R >= 2 && D >= 2 && N >= 1) ||
        throw(ArgumentError("invalid dataset dimensions"))
    (length(rater) == N && length(event_ids) == N && allunique(event_ids)) ||
        throw(ArgumentError("mismatched or duplicate event_ids"))
    ent_v = Int.(entity)
    rat_v = Int.(rater)
    (all(i -> 1 <= i <= I, ent_v) && all(r -> 1 <= r <= R, rat_v)) ||
        throw(ArgumentError("entity or rater index out of bounds"))
    if require_connected && !_bipartite_components(ent_v, rat_v, I, R).is_connected
        throw(ArgumentError("entity-rater design graph is disconnected; inspect validate_design or set require_connected=false"))
    end
    M_vec = [m.M for m in metas]
    y_mat = y_in isa AbstractMatrix ? Int.(y_in) : [Int(y_in[e][c]) for c in 1:D, e in 1:N]
    size(y_mat) == (D, N) || throw(ArgumentError("y must have shape (D=$D, N=$N)"))
    for e in 1:N, c in 1:D
        0 <= y_mat[c, e] <= M_vec[c] ||
            throw(ArgumentError("canonical score out of 0:$(M_vec[c])"))
    end
    pr = _parse_prior(prior, association)
    spec = _parse_parameterization(parameterization, association, reference_prior, pr, M_vec; basis_order)
    return _construct_star_model(
        I, R, D, M_vec, ent_v, rat_v, y_mat,
        entity_levels, rater_levels, event_ids, metas, pr, spec,
    )
end

function model(
    rows;
    criteria,
    root::AbstractString,
    prior,
    entity_key::Symbol = :entity,
    parameterization = :cp_ncp,
    basis_order::Union{Nothing, Symbol} = nothing,
    association::Bool = true,
    reference_prior::Bool = true,
    require_connected::Bool = false,
)
    metas = _parse_criteria(criteria, root)
    cols = _normalize_row_columns(rows, entity_key)
    event_ids, owners, scores_list = _assemble_events_from_columns(cols, metas)
    ent_levels = sort(unique(first.(owners)))
    rat_levels = sort(unique(last.(owners)))
    ent_map = Dict(id => i for (i, id) in enumerate(ent_levels))
    rat_map = Dict(id => r for (r, id) in enumerate(rat_levels))
    return model_from_indexed(
        [ent_map[o[1]] for o in owners],
        [rat_map[o[2]] for o in owners],
        scores_list,
        metas;
        prior,
        entity_levels = ent_levels,
        rater_levels = rat_levels,
        event_ids,
        parameterization,
        basis_order,
        association,
        reference_prior,
        require_connected,
    )
end

function _extract_event_score(rec, c::CriterionMeta, c_idx::Int)
    if hasproperty(rec, :scores)
        sc = rec.scores
        raw_val = sc isa AbstractVector ? sc[c_idx] : getproperty(sc, Symbol(c.id))
        return _encode_raw_score(c, raw_val)
    end
    hasproperty(rec, Symbol(c.id)) ||
        throw(ArgumentError("event record missing :scores or criterion column :$(c.id)"))
    return _encode_raw_score(c, getproperty(rec, Symbol(c.id)))
end

function model_from_events(
    events;
    criteria,
    root::AbstractString,
    prior,
    entity_key::Symbol = :entity,
    rater_key::Symbol = :rater,
    event_key::Symbol = :rating_event_id,
    parameterization = :cp_ncp,
    basis_order::Union{Nothing, Symbol} = nothing,
    association::Bool = true,
    reference_prior::Bool = true,
    require_connected::Bool = false,
)
    metas = _parse_criteria(criteria, root)
    if events isa NamedTuple
        evs = getproperty(events, event_key)
        ents = getproperty(events, entity_key)
        rats = getproperty(events, rater_key)
        N = length(evs)
        ev_ids = [String(evs[e]) for e in 1:N]
        owners = [(String(ents[e]), String(rats[e])) for e in 1:N]
        scores_list = [
            [_encode_raw_score(metas[c], getproperty(events, Symbol(metas[c].id))[e]) for c in eachindex(metas)]
            for e in 1:N
        ]
    else
        !isempty(events) || throw(ArgumentError("events must not be empty"))
        ev_ids = [String(getproperty(e, event_key)) for e in events]
        owners = [(String(getproperty(e, entity_key)), String(getproperty(e, rater_key))) for e in events]
        scores_list = [[_extract_event_score(e, metas[c], c) for c in eachindex(metas)] for e in events]
    end
    all(_nonempty_str, ev_ids) && all(o -> _nonempty_str(o[1]) && _nonempty_str(o[2]), owners) ||
        throw(ArgumentError("all event, entity, and rater IDs must be nonempty strings"))
    ent_levels = sort(unique(first.(owners)))
    rat_levels = sort(unique(last.(owners)))
    ent_map = Dict(id => i for (i, id) in enumerate(ent_levels))
    rat_map = Dict(id => r for (r, id) in enumerate(rat_levels))
    return model_from_indexed(
        [ent_map[o[1]] for o in owners],
        [rat_map[o[2]] for o in owners],
        scores_list,
        metas;
        prior,
        entity_levels = ent_levels,
        rater_levels = rat_levels,
        event_ids = ev_ids,
        parameterization,
        basis_order,
        association,
        reference_prior,
        require_connected,
    )
end

function with_options(
    m::StarModel;
    prior = m.prior,
    parameterization = nothing,
    basis_order::Union{Nothing, Symbol} = nothing,
    association::Bool = m.spec.include_phi,
    reference_prior::Bool = m.spec.reference_prior,
)
    p_base = parameterization === nothing ? m.spec : parameterization
    bo = if basis_order !== nothing
        basis_order
    elseif parameterization isa NamedTuple && haskey(parameterization, :basis_order)
        Symbol(parameterization.basis_order)
    else
        m.spec.basis_order
    end
    pr = _parse_prior(prior, association)
    spec = _parse_parameterization(p_base, association, reference_prior, pr, m.M; basis_order = bo)
    return _construct_star_model(
        m.I, m.R, m.D, m.M, m.entity, m.rater, m.y,
        m.entity_levels, m.rater_levels, m.event_ids, m.criteria, pr, spec,
    )
end

"""
    facet_basis(m::StarModel)

Return the glass-box zero-sum basis permutations, raw counts, Schur-complement effective
contrast counts, and CP/NCP masks for `:entity` and `:rater`.
"""
function facet_basis(m::StarModel)
    return (;
        basis_order = m.spec.basis_order,
        entity = (;
            levels = copy(m.entity_levels),
            ordered_levels = m.entity_levels[m.entity_basis.perm],
            perm = copy(m.entity_basis.perm),
            inv_perm = copy(m.entity_basis.inv_perm),
            raw_counts = copy(m.entity_basis.raw_counts),
            effective_counts = copy(m.entity_basis.effective_counts),
            cp_mask = copy(m.entity_basis.cp_mask),
            n_cp = m.entity_basis.n_cp,
            n_ncp = (m.I - 1) - m.entity_basis.n_cp,
        ),
        rater = (;
            levels = copy(m.rater_levels),
            ordered_levels = m.rater_levels[m.rater_basis.perm],
            perm = copy(m.rater_basis.perm),
            inv_perm = copy(m.rater_basis.inv_perm),
            raw_counts = copy(m.rater_basis.raw_counts),
            effective_counts = copy(m.rater_basis.effective_counts),
            cp_mask = copy(m.rater_basis.cp_mask),
            n_cp = m.rater_basis.n_cp,
            n_ncp = (m.R - 1) - m.rater_basis.n_cp,
        ),
    )
end

function facet_basis(m::StarModel, facet::Symbol)
    if facet === :entity
        return m.entity_basis
    elseif facet === :rater
        return m.rater_basis
    end
    throw(ArgumentError("facet must be :entity or :rater"))
end

function _midranks(v::AbstractVector{Float64})
    n = length(v)
    ord = sortperm(v)
    r = Vector{Float64}(undef, n)
    i = 1
    while i <= n
        j = i
        while j < n && v[ord[j + 1]] == v[ord[i]]
            j += 1
        end
        mr = 0.5 * (i + j)
        for k in i:j
            r[ord[k]] = mr
        end
        i = j + 1
    end
    return r
end

function _descriptive_correlations(m::StarModel)
    N = length(m.entity)
    raw_ev = Matrix{Float64}(undef, N, m.D)
    ent_sum = zeros(Float64, m.I, m.D)
    ent_cnt = zeros(Int, m.I)
    for e in 1:N
        i = m.entity[e]
        ent_cnt[i] += 1
        for c in 1:m.D
            rv = Float64(m.criteria[c].canonical_to_raw[m.y[c, e] + 1])
            raw_ev[e, c] = rv
            ent_sum[i, c] += rv
        end
    end
    act = findall(>(0), ent_cnt)
    ent_means = ent_sum[act, :] ./ ent_cnt[act]
    ent_ranks = hcat([_midranks(view(ent_means, :, c)) for c in 1:m.D]...)
    cids = [c.id for c in m.criteria]
    pairs_out = [
        (;
            left = cids[c1],
            right = cids[c2],
            event_pearson = cor(view(raw_ev, :, c1), view(raw_ev, :, c2)),
            entity_mean_pearson = length(act) >= 2 ? cor(view(ent_means, :, c1), view(ent_means, :, c2)) : NaN,
            entity_mean_spearman = length(act) >= 2 ? cor(view(ent_ranks, :, c1), view(ent_ranks, :, c2)) : NaN,
        ) for c1 in 1:m.D for c2 in (c1 + 1):m.D
    ]
    return (; n_active_entities = length(act), pairs = pairs_out)
end

function design_summary(m::StarModel; min_category_count::Int = 5)
    N = length(m.entity)
    ec = m.entity_basis.raw_counts
    rc = m.rater_basis.raw_counts
    comp = _bipartite_components(m.entity, m.rater, m.I, m.R)
    strata = [
        (;
            stratum = st.label,
            n_raters = count(c -> st.min_n <= c <= st.max_n, rc),
            n_events = count(e -> st.min_n <= rc[m.rater[e]] <= st.max_n, 1:N),
        ) for st in RATER_COUNT_STRATA
    ]
    cat_usage = [
        begin
            cnt = count(==(k), view(m.y, c, :))
            flag = cnt == 0 ? :unused : (cnt < min_category_count ? :sparse : :ok)
            (;
                criterion = m.criteria[c].id,
                canonical_index = k,
                raw_score = m.criteria[c].canonical_to_raw[k + 1],
                count = cnt,
                proportion = cnt / N,
                flag,
            )
        end for c in 1:m.D for k in 0:m.M[c]
    ]
    deg_stat(v) = (;
        min = minimum(v),
        median = median(v),
        mean = mean(v),
        max = maximum(v),
        zero_count = count(==(0), v),
    )
    eff_stat(v) = (; min = minimum(v), median = median(v), mean = mean(v), max = maximum(v))
    return (;
        n_events = N,
        n_entities = m.I,
        n_raters = m.R,
        n_criteria = m.D,
        dimension = m.dim,
        basis_order = m.spec.basis_order,
        connectivity = (; comp.is_connected, comp.n_components, comp.components),
        entity_ratings = deg_stat(ec),
        rater_ratings = deg_stat(rc),
        rater_strata = strata,
        helmert_split = (;
            basis_order = m.spec.basis_order,
            n_cp_entity = m.entity_basis.n_cp,
            n_ncp_entity = (m.I - 1) - m.entity_basis.n_cp,
            n_cp_rater = m.rater_basis.n_cp,
            n_ncp_rater = (m.R - 1) - m.rater_basis.n_cp,
            entity_effective_counts = eff_stat(m.entity_basis.effective_counts),
            rater_effective_counts = eff_stat(m.rater_basis.effective_counts),
        ),
        category_usage = cat_usage,
        descriptive_correlations = _descriptive_correlations(m),
    )
end

"""
    validate_design(m::StarModel; min_category_count=5, require_connected=false)

Unified pre-estimation design, connectivity, category-support, and Schur-complement CP/NCP audit.
"""
function validate_design(
    m::StarModel;
    min_category_count::Int = 5,
    require_connected::Bool = false,
)
    summary = design_summary(m; min_category_count)
    if require_connected && !summary.connectivity.is_connected
        throw(ArgumentError("entity-rater design graph has $(summary.connectivity.n_components) disconnected components"))
    end
    advisories = Symbol[]
    !summary.connectivity.is_connected && push!(advisories, :disconnected_design_prior_identified_only)
    summary.entity_ratings.zero_count > 0 && push!(advisories, :unobserved_entity_levels)
    summary.rater_ratings.zero_count > 0 && push!(advisories, :unobserved_rater_levels)
    any(r -> r.flag === :unused, summary.category_usage) && push!(advisories, :unused_score_categories)
    any(r -> r.flag === :sparse, summary.category_usage) && push!(advisories, :sparse_score_categories)
    m.spec.basis_order === :legacy_lexicographic && push!(advisories, :legacy_lexicographic_basis_order)
    return merge(summary, (; passed = summary.connectivity.is_connected, advisories))
end

"""
    stan_data(m::StarModel; likelihood=true)

Export an exact CmdStan / BridgeStan data NamedTuple for `general_star.stan`.
Entity and rater event indices are mapped through `m.entity_basis.inv_perm` and
`m.rater_basis.inv_perm` so `general_star.stan` matches both `:descending_schur`
and `:legacy_lexicographic` to machine precision without modifying Stan code.
"""
function stan_data(m::StarModel; likelihood::Bool = true)
    m.prior.entity_lkj_eta == m.prior.rater_lkj_eta ||
        throw(ArgumentError("general_star.stan uses a shared lkj_eta; entity_lkj_eta and rater_lkj_eta must match"))
    return (;
        D_crit = m.D,
        M = copy(m.M),
        I = m.I,
        R = m.R,
        N = length(m.entity),
        entity = m.entity_basis.inv_perm[m.entity],
        rater = m.rater_basis.inv_perm[m.rater],
        y = [collect(view(m.y, :, e)) for e in eachindex(m.entity)],
        likelihood_on = Int(likelihood),
        include_phi = Int(m.spec.include_phi),
        reference_prior = Int(m.spec.reference_prior),
        entity_cp = Int.(m.entity_basis.cp_mask),
        rater_cp = Int.(m.rater_basis.cp_mask),
        mu_sd = m.prior.mu_sd,
        entity_log_sd_mean = m.prior.entity_log_sd_mean,
        rater_log_sd_mean = m.prior.rater_log_sd_mean,
        log_sd_sd = m.prior.log_sd_sd,
        step_sd = m.prior.step_sd,
        step_spacing = m.prior.step_spacing,
        lkj_eta = m.prior.entity_lkj_eta,
        phi_sd = m.prior.phi_sd,
    )
end
