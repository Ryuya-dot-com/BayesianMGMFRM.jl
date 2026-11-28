# CR5: Unified Pre-Fit Design Validation, 3-Layer Connectedness, Fischer (1981)
# One-Sided Separation Audit & Disjoint-Subset Reporting
#
# Provides a consistent structured pre-fit validation surface across `MRCMLTarget`,
# `MRCMLSpec`, `AdditiveFacets.AbstractTarget`, `FrequentistMFRM.Spec`, and `FacetSpec`
# (including scalar GMFRM) without breaking backward-compatible fields.

function _cr5_connected_components_from_edges(n_nodes::Int, edges::Vector{Tuple{Int,Int}})
    adj = [Int[] for _ in 1:n_nodes]
    for (u, v) in edges
        u == v && continue
        push!(adj[u], v)
        push!(adj[v], u)
    end
    seen = falses(n_nodes)
    comps = Vector{Vector{Int}}()
    for s in 1:n_nodes
        seen[s] && continue
        seen[s] = true
        q = Int[s]
        head = 1
        while head <= length(q)
            cur = q[head]
            head += 1
            for nxt in adj[cur]
                if !seen[nxt]
                    seen[nxt] = true
                    push!(q, nxt)
                end
            end
        end
        sort!(q)
        push!(comps, q)
    end
    sort!(comps; by = c -> (-length(c), first(c)))
    return comps
end

# Tarjan's iterative/recursive strongly connected components on 1:n_nodes directed graph.
function _cr5_tarjan_scc(n_nodes::Int, adj::Vector{Vector{Int}})
    index_counter = Ref(0)
    indices = zeros(Int, n_nodes)
    lowlink = zeros(Int, n_nodes)
    on_stack = falses(n_nodes)
    stack = Int[]
    sccs = Vector{Vector{Int}}()

    for start in 1:n_nodes
        indices[start] != 0 && continue
        # Iterative Tarjan DFS: (node, next_neighbor_idx)
        call_stack = Tuple{Int,Int}[(start, 1)]
        index_counter[] += 1
        indices[start] = index_counter[]
        lowlink[start] = index_counter[]
        push!(stack, start)
        on_stack[start] = true

        while !isempty(call_stack)
            v, ni = call_stack[end]
            nbrs = adj[v]
            if ni <= length(nbrs)
                call_stack[end] = (v, ni + 1)
                w = nbrs[ni]
                if indices[w] == 0
                    index_counter[] += 1
                    indices[w] = index_counter[]
                    lowlink[w] = index_counter[]
                    push!(stack, w)
                    on_stack[w] = true
                    push!(call_stack, (w, 1))
                elseif on_stack[w]
                    lowlink[v] = min(lowlink[v], indices[w])
                end
            else
                pop!(call_stack)
                if !isempty(call_stack)
                    parent = call_stack[end][1]
                    lowlink[parent] = min(lowlink[parent], lowlink[v])
                end
                if lowlink[v] == indices[v]
                    comp = Int[]
                    while true
                        w = pop!(stack)
                        on_stack[w] = false
                        push!(comp, w)
                        w == v && break
                    end
                    sort!(comp)
                    push!(sccs, comp)
                end
            end
        end
    end
    return sccs
end

function _cr5_facet_tuples(facets)
    out = NamedTuple[]
    for b in facets
        sgn = hasproperty(b, :sign) ? Int(b.sign) : -1
        push!(out, (;
            name = Symbol(b.name),
            levels = collect(Any, b.levels),
            index = Int.(b.index),
            sign = sgn,
        ))
    end
    return out
end

function _cr5_disjoint_subsets(
        people::AbstractVector,
        person_idx::AbstractVector{<:Integer},
        facets_meta::Vector{NamedTuple};
        active_rows::Union{Nothing,AbstractVector{<:Integer}} = nothing)
    P = length(people)
    rows = active_rows === nothing ? (1:length(person_idx)) : active_rows

    # When evaluating a residual (active_rows !== nothing) graph, include ONLY persons
    # observed in `active_rows` so excluded extreme persons are never counted as isolated
    # disconnected components, while retaining all declared facet levels so isolated facet
    # levels remain visible.
    if active_rows === nothing
        active_p_list = collect(1:P)
    else
        obs_p_flag = falses(P)
        for n in rows
            obs_p_flag[Int(person_idx[n])] = true
        end
        active_p_list = findall(obs_p_flag)
    end
    n_ap = length(active_p_list)
    p_remap = zeros(Int, P)
    for (k, p) in enumerate(active_p_list)
        p_remap[p] = k
    end

    # 1) Overall hypergraph incidence components
    # When evaluating a residual (active_rows !== nothing) graph, include ONLY active
    # persons and active facet levels observed in `active_rows` so levels losing all active
    # rows do not inflate the observed component count; those levels are reported separately
    # in `isolated_facet_levels`.
    isolated_facet_levels = NamedTuple[]
    active_f_lists = Vector{Vector{Int}}(undef, length(facets_meta))
    f_remaps = Vector{Vector{Int}}(undef, length(facets_meta))
    for (fi, f) in enumerate(facets_meta)
        L = length(f.levels)
        obs_f = falses(L)
        for n in rows
            obs_f[f.index[n]] = true
        end
        miss = Any[f.levels[j] for j in 1:L if !obs_f[j]]
        isempty(miss) || push!(isolated_facet_levels, (; facet = f.name, levels = miss, n_levels = length(miss)))
        alist = active_rows === nothing ? collect(1:L) : findall(obs_f)
        active_f_lists[fi] = alist
        rmap = zeros(Int, L)
        for (k, j) in enumerate(alist)
            rmap[j] = k
        end
        f_remaps[fi] = rmap
    end
    n_isolated_facet_levels = sum(x -> x.n_levels, isolated_facet_levels; init = 0)

    offsets = Dict{Symbol,Int}(:person => 0)
    cursor = n_ap
    for (fi, f) in enumerate(facets_meta)
        offsets[f.name] = cursor
        cursor += length(active_f_lists[fi])
    end
    edges = Tuple{Int,Int}[]
    for n in rows
        pn = p_remap[Int(person_idx[n])]
        pn == 0 && continue
        for (fi, f) in enumerate(facets_meta)
            fj = f_remaps[fi][f.index[n]]
            fj == 0 && continue
            fn_node = offsets[f.name] + fj
            push!(edges, (pn, fn_node))
        end
        for a in 1:(length(facets_meta) - 1)
            fa = f_remaps[a][facets_meta[a].index[n]]
            fa == 0 && continue
            na = offsets[facets_meta[a].name] + fa
            for b in (a + 1):length(facets_meta)
                fb = f_remaps[b][facets_meta[b].index[n]]
                fb == 0 && continue
                nb = offsets[facets_meta[b].name] + fb
                push!(edges, (na, nb))
            end
        end
    end
    raw_overall = cursor == 0 ? Vector{Vector{Int}}() : _cr5_connected_components_from_edges(cursor, edges)
    overall_subsets = NamedTuple[]
    for (k, comp) in enumerate(raw_overall)
        p_ids = Any[people[active_p_list[u]] for u in comp if u <= n_ap]
        f_dict = Dict{Symbol,Vector{Any}}()
        f_counts = Dict{Symbol,Int}()
        for (fi, f) in enumerate(facets_meta)
            off = offsets[f.name]
            alist = active_f_lists[fi]
            L_act = length(alist)
            lvls = Any[f.levels[alist[u - off]] for u in comp if (off < u <= off + L_act)]
            f_dict[f.name] = lvls
            f_counts[f.name] = length(lvls)
        end
        push!(overall_subsets, (;
            subset = k,
            n_nodes = length(comp),
            n_persons = length(p_ids),
            persons = p_ids,
            n_levels_by_facet = f_counts,
            facets = f_dict,
        ))
    end

    # 2) Per-facet person <-> facet bipartite subsets (observed active levels only when residual)
    by_facet = NamedTuple[]
    for (fi, f) in enumerate(facets_meta)
        alist = active_f_lists[fi]
        rmap = f_remaps[fi]
        L_act = length(alist)
        if L_act <= 1
            push!(by_facet, (;
                facet = f.name,
                connected = true,
                n_subsets = (L_act == 0 && n_ap == 0) ? 0 : 1,
                subsets = (L_act == 0 && n_ap == 0) ? NamedTuple[] : [(;
                    subset = 1,
                    levels = Any[f.levels[j] for j in alist],
                    n_levels = L_act,
                    n_persons = n_ap,
                    persons = Any[people[p] for p in active_p_list],
                )],
                bridge_suggestion = nothing,
            ))
            continue
        end
        remapped_edges = Tuple{Int,Int}[]
        for n in rows
            pn = p_remap[Int(person_idx[n])]
            fj = rmap[f.index[n]]
            (pn == 0 || fj == 0) && continue
            push!(remapped_edges, (pn, n_ap + fj))
        end
        bcomps = _cr5_connected_components_from_edges(n_ap + L_act, remapped_edges)
        f_subsets = NamedTuple[]
        for (k, comp) in enumerate(bcomps)
            lvls = Any[f.levels[alist[u - n_ap]] for u in comp if u > n_ap]
            ps = Any[people[active_p_list[u]] for u in comp if u <= n_ap]
            isempty(lvls) && isempty(ps) && continue
            push!(f_subsets, (;
                subset = k,
                levels = lvls,
                n_levels = length(lvls),
                n_persons = length(ps),
                persons = ps,
            ))
        end
        conn = length(f_subsets) <= 1
        suggestion = if conn
            nothing
        else
            l1 = isempty(f_subsets[1].levels) ? "(persons only)" : repr(first(f_subsets[1].levels))
            l2 = isempty(f_subsets[2].levels) ? "(persons only)" : repr(first(f_subsets[2].levels))
            "Facet :$(f.name) splits into $(length(f_subsets)) person-linked subset(s); add overlapping ratings where common examinees are scored across subsets (e.g., bridging $(l1) and $(l2))."
        end
        push!(by_facet, (;
            facet = f.name,
            connected = conn,
            n_subsets = length(f_subsets),
            subsets = f_subsets,
            bridge_suggestion = suggestion,
        ))
    end

    return (;
        overall_connected = length(overall_subsets) <= 1,
        n_overall_subsets = length(overall_subsets),
        n_active_persons = n_ap,
        overall_subsets,
        isolated_facet_levels,
        n_isolated_facet_levels,
        by_facet,
        all_facets_person_connected = all(r -> r.connected, by_facet),
    )
end

function _cr5_row_score_bounds(
        n::Int,
        category_idx::AbstractVector{<:Integer},
        supports::AbstractVector{UnitRange{Int}},
        group_idx::AbstractVector{<:Integer},
        op)
    sup = supports[Int(group_idx[n])]
    if op !== nothing
        prng = op.pattern_ranges[op.pattern_of_row[n]]
        M_g = length(sup)
        yk_loc = Int(category_idx[n]) - first(sup) + 1
        b_min = Inf
        b_max = -Inf
        @inbounds for lk in 1:M_g
            bv = Float64(op.B_pat[prng[lk]])
            bv < b_min && (b_min = bv)
            bv > b_max && (b_max = bv)
        end
        b_obs = Float64(op.B_pat[prng[yk_loc]])
        return (b_obs, b_min, b_max)
    else
        b_min = 0.0
        b_max = Float64(last(sup) - first(sup))
        b_obs = Float64(Int(category_idx[n]) - first(sup))
        return (b_obs, b_min, b_max)
    end
end

function _cr5_fixed_facet_level_lookup(spec)
    fixed_map = Dict{Tuple{Symbol,Any},Bool}()
    if hasproperty(spec, :operator) && spec.operator isa AdditiveFacets.MRCMLOperator
        fset = spec.operator.fixed_model_names
        for b in spec.facets
            for lvl in b.levels
                nm1 = "$(b.name)[$(repr(lvl))]"
                nm2 = "$(b.name)[$(lvl)]"
                if (nm1 in fset) || (nm2 in fset)
                    fixed_map[(Symbol(b.name), lvl)] = true
                end
            end
        end
    elseif spec isa FacetSpec
        for anc in spec.anchors
            role = _stable_anchor_block(anc.block)
            lvl = _anchor_target(anc)
            fixed_map[(role, lvl)] = true
        end
        if spec.family === :mfrm
            # Reference coding fixes first item and first rater when unanchored
            if !any(k -> k[1] === :item, keys(fixed_map)) && !isempty(spec.data.item_levels)
                fixed_map[(:item, first(spec.data.item_levels))] = true
            end
            if spec.data.columns.rater !== nothing &&
                    !any(k -> k[1] === :rater, keys(fixed_map)) && !isempty(spec.data.rater_levels)
                fixed_map[(:rater, first(spec.data.rater_levels))] = true
            end
        end
    end
    return fixed_map
end

function _cr5_extreme_elements(
        people::AbstractVector,
        person_idx::AbstractVector{<:Integer},
        facets_meta::Vector{NamedTuple},
        category_idx::AbstractVector{<:Integer},
        supports::AbstractVector{UnitRange{Int}},
        group_idx::AbstractVector{<:Integer};
        op = nothing,
        fixed_map::Dict{Tuple{Symbol,Any},Bool} = Dict{Tuple{Symbol,Any},Bool}())
    P = length(people)
    n_obs = length(person_idx)

    p_has = falses(P)
    p_inf = falses(P)
    p_min = trues(P)
    p_max = trues(P)
    for n in 1:n_obs
        p = Int(person_idx[n])
        p_has[p] = true
        b_obs, b_min, b_max = _cr5_row_score_bounds(n, category_idx, supports, group_idx, op)
        b_max - b_min <= 1e-14 && continue
        p_inf[p] = true
        abs(b_obs - b_min) <= 1e-14 || (p_min[p] = false)
        abs(b_obs - b_max) <= 1e-14 || (p_max[p] = false)
    end
    person_status = Vector{Symbol}(undef, P)
    p_all_min = Any[]
    p_all_max = Any[]
    p_unobs = Any[]
    for p in 1:P
        if !p_has[p]
            person_status[p] = :unobserved
            push!(p_unobs, people[p])
        elseif !p_inf[p]
            person_status[p] = :unidentified_zero_slope
            push!(p_unobs, people[p])
        elseif p_min[p] && !p_max[p]
            person_status[p] = :all_minimum
            push!(p_all_min, people[p])
        elseif p_max[p] && !p_min[p]
            person_status[p] = :all_maximum
            push!(p_all_max, people[p])
        else
            person_status[p] = :interior
        end
    end

    facet_extremes = NamedTuple[]
    for f in facets_meta
        L = length(f.levels)
        f_has = falses(L)
        f_inf = falses(L)
        f_min = trues(L)
        f_max = trues(L)
        for n in 1:n_obs
            j = f.index[n]
            f_has[j] = true
            b_obs, b_min, b_max = _cr5_row_score_bounds(n, category_idx, supports, group_idx, op)
            b_max - b_min <= 1e-14 && continue
            f_inf[j] = true
            abs(b_obs - b_min) <= 1e-14 || (f_min[j] = false)
            abs(b_obs - b_max) <= 1e-14 || (f_max[j] = false)
        end
        f_all_min = Any[f.levels[j] for j in 1:L if f_has[j] && f_inf[j] && f_min[j]]
        f_all_max = Any[f.levels[j] for j in 1:L if f_has[j] && f_inf[j] && f_max[j] && !f_min[j]]
        f_free_min = Any[lvl for lvl in f_all_min if !get(fixed_map, (f.name, lvl), false)]
        f_free_max = Any[lvl for lvl in f_all_max if !get(fixed_map, (f.name, lvl), false)]
        f_fixed_ext = Any[lvl for lvl in vcat(f_all_min, f_all_max) if get(fixed_map, (f.name, lvl), false)]
        f_unobs = Any[f.levels[j] for j in 1:L if !f_has[j]]
        push!(facet_extremes, (;
            facet = f.name,
            all_minimum = f_all_min,
            all_maximum = f_all_max,
            free_all_minimum = f_free_min,
            free_all_maximum = f_free_max,
            fixed_extreme_levels = f_fixed_ext,
            unobserved = f_unobs,
            n_extreme = length(f_all_min) + length(f_all_max),
            n_free_extreme = length(f_free_min) + length(f_free_max),
        ))
    end

    return (;
        scoring_basis = op === nothing ? :raw_category_support : :mrcml_scoring_operator_B,
        person = (;
            all_minimum = p_all_min,
            all_maximum = p_all_max,
            unobserved = p_unobs,
            n_extreme = length(p_all_min) + length(p_all_max),
            status = person_status,
        ),
        facets = facet_extremes,
    )
end

# Fischer (1981, Psychometrika) directed strong-connectedness separation audit:
# For each facet f with L_f >= 2 and sign s_f (default -1 for severity/difficulty):
# linear predictor is theta_p + s_f * xi_{f,j} = v(p) - v(j) where v(j) = -s_f * xi_{f,j}.
# In a row with score b_obs in [b_min, b_max] (b_max > b_min):
#   - b_obs > b_min: shifting v(j) -> +Inf forces v(p) -> +Inf => directed edge j -> p.
#   - b_obs < b_max: shifting v(p) -> +Inf forces v(j) -> +Inf => directed edge p -> j.
function _cr5_op_is_unconstrained_dichotomous_rasch(op, facets_meta::Vector{NamedTuple}, supports::AbstractVector{UnitRange{Int}})
    length(facets_meta) == 1 || return false
    all(sup -> length(sup) == 2, supports) || return false
    L = length(facets_meta[1].levels)
    L <= 1 && return true
    op === nothing && return true
    op isa AdditiveFacets.MRCMLOperator || return false
    # Unconstrained dichotomous 2-facet Rasch has L - 1 free structural columns (sum-to-zero) or L - n_fixed
    return size(op.A_free, 2) >= L - 1
end

# Verify that a candidate recession direction `(d_theta_by_person, d_eta_free)` (or additive
# `(d_theta_by_person, row_facet_shift, step_shifts)`) strictly increases or preserves the
# exact compiled log-likelihood on EVERY active row without violating any parameter constraints.
function _cr5_verify_compiled_recession(
        person_idx::AbstractVector{<:Integer},
        category_idx::AbstractVector{<:Integer},
        supports::AbstractVector{UnitRange{Int}},
        group_idx::AbstractVector{<:Integer},
        active_rows::AbstractVector{<:Integer},
        d_theta_by_person::Vector{Float64};
        op = nothing,
        d_eta_free::Union{Nothing,Vector{Float64}} = nothing,
        row_facet_shift::Union{Nothing,Vector{Float64}} = nothing,
        step_shifts::Union{Nothing,Vector{Vector{Float64}}} = nothing)
    strict_improve = false
    if op isa AdditiveFacets.MRCMLOperator
        d_eta_free === nothing && return false
        v_shift = op.A_free * d_eta_free
        for n in active_rows
            p = Int(person_idx[n])
            dth = d_theta_by_person[p]
            sup = supports[Int(group_idx[n])]
            prng = op.pattern_ranges[op.pattern_of_row[n]]
            M_g = length(sup)
            yk_loc = Int(category_idx[n]) - first(sup) + 1
            d_obs = op.B_pat[prng[yk_loc]] * dth + v_shift[prng[yk_loc]]
            for lk in 1:M_g
                d_k = op.B_pat[prng[lk]] * dth + v_shift[prng[lk]]
                d_k > d_obs + 1e-8 && return false
                d_k < d_obs - 1e-7 && (strict_improve = true)
            end
        end
        return strict_improve
    else
        for n in active_rows
            p = Int(person_idx[n])
            g = Int(group_idx[n])
            sup = supports[g]
            M_g = length(sup)
            yk = Int(category_idx[n]) - first(sup)
            eta_s = d_theta_by_person[p] + (row_facet_shift === nothing ? 0.0 : row_facet_shift[n])
            st_s = step_shifts === nothing ? nothing : step_shifts[g]
            cum = 0.0
            d_vals = Vector{Float64}(undef, M_g)
            d_vals[1] = 0.0
            for k in 1:(M_g - 1)
                cum += st_s === nothing ? 0.0 : st_s[k]
                d_vals[k + 1] = k * eta_s - cum
            end
            d_obs = d_vals[yk + 1]
            for lk in 1:M_g
                d_vals[lk] > d_obs + 1e-8 && return false
                d_vals[lk] < d_obs - 1e-7 && (strict_improve = true)
            end
        end
        return strict_improve
    end
end

# Project a desired per-pattern-cell logit shift onto the compiled `op.A_free` column space
# over active patterns (relative to each pattern's first cell).
function _cr5_project_pattern_shift_to_mrcml(
        op::AdditiveFacets.MRCMLOperator,
        active_rows::AbstractVector{<:Integer},
        target_cell_shift::Vector{Float64})
    d_xi = size(op.A_free, 2)
    d_xi == 0 && return zeros(Float64, 0)
    act_pats = sort!(unique(Int[op.pattern_of_row[n] for n in active_rows]))
    r_rows = Int[]
    r_cols = Int[]
    r_vals = Float64[]
    rhs = Float64[]
    At = AdditiveFacets.SparseArrays.sparse(transpose(op.A_free))
    rv = AdditiveFacets.SparseArrays.rowvals(At)
    nz = AdditiveFacets.SparseArrays.nonzeros(At)
    eq = 0
    for u in act_pats
        rng = op.pattern_ranges[u]
        m1 = first(rng)
        t1 = target_cell_shift[m1]
        for m in rng[2:end]
            eq += 1
            push!(rhs, target_cell_shift[m] - t1)
            for ptr in AdditiveFacets.SparseArrays.nzrange(At, m)
                push!(r_rows, eq); push!(r_cols, rv[ptr]); push!(r_vals, nz[ptr])
            end
            for ptr in AdditiveFacets.SparseArrays.nzrange(At, m1)
                push!(r_rows, eq); push!(r_cols, rv[ptr]); push!(r_vals, -nz[ptr])
            end
        end
    end
    eq == 0 && return zeros(Float64, d_xi)
    M = Matrix(AdditiveFacets.SparseArrays.sparse(r_rows, r_cols, r_vals, eq, d_xi))
    return M \ rhs
end

# Compiled-model-grounded separation audit:
# 1) Exact necessary & sufficient Fischer (1981) condition ONLY for unconstrained 2-facet
#    dichotomous Rasch models (`:fischer_1981_exact_dichotomous_rasch`).
# 2) For general F-facet, polytomous, or linearly constrained MRCML designs, tests candidate
#    facet-SCC and global-RSM threshold-cut recession directions directly inside the compiled
#    model's actual free person, facet, and threshold coordinates, refusing to block finite
#    optima (such as tied-coefficient TAM designs) when no valid recession direction exists
#    in `A_free`, and reporting clearly that the pre-fit screen is sufficient-only.
function _cr5_fischer_separation_audit(
        people::AbstractVector,
        person_idx::AbstractVector{<:Integer},
        facets_meta::Vector{NamedTuple},
        category_idx::AbstractVector{<:Integer},
        supports::AbstractVector{UnitRange{Int}},
        group_idx::AbstractVector{<:Integer},
        active_rows::AbstractVector{<:Integer};
        op = nothing,
        fixed_map::Dict{Tuple{Symbol,Any},Bool} = Dict{Tuple{Symbol,Any},Bool}())
    P = length(people)
    obs_p_flag = falses(P)
    for n in active_rows
        obs_p_flag[Int(person_idx[n])] = true
    end
    active_p_list = findall(obs_p_flag)
    n_ap = length(active_p_list)
    p_remap = zeros(Int, P)
    for (k, p) in enumerate(active_p_list)
        p_remap[p] = k
    end

    is_exact_fischer = _cr5_op_is_unconstrained_dichotomous_rasch(op, facets_meta, supports)
    scope_sym = is_exact_fischer ? :fischer_1981_exact_dichotomous_rasch : :compiled_free_parameter_recession_screen
    scope_note = is_exact_fischer ?
        "Necessary and sufficient finite-JMLE existence condition for unconstrained 2-facet dichotomous Rasch models (Fischer 1981)." :
        "Sufficient separating-direction screen verified in the compiled model's free person, facet, and threshold coordinates. Not exhaustive for general polytomous (PCM/RSM) or linearly constrained designs; post-fit gradient and Hessian qualification remains an independent gate."

    by_facet = NamedTuple[]
    any_separated = false
    for f in facets_meta
        L = length(f.levels)
        L <= 1 && continue
        obs_f = falses(L)
        for n in active_rows
            obs_f[f.index[n]] = true
        end
        active_f_list = findall(obs_f)
        n_af = length(active_f_list)
        n_af <= 1 && continue
        f_remap = zeros(Int, L)
        for (k, j) in enumerate(active_f_list)
            f_remap[j] = k
        end

        n_nodes = n_ap + n_af
        adj = [Int[] for _ in 1:n_nodes]
        for n in active_rows
            pn = p_remap[Int(person_idx[n])]
            fn = f_remap[f.index[n]]
            (pn == 0 || fn == 0) && continue
            b_obs, b_min, b_max = _cr5_row_score_bounds(n, category_idx, supports, group_idx, op)
            b_max - b_min <= 1e-14 && continue
            f_node = n_ap + fn
            if b_obs > b_min + 1e-14
                push!(adj[f_node], pn)
            end
            if b_obs < b_max - 1e-14
                push!(adj[pn], f_node)
            end
        end
        for u in 1:n_nodes
            length(adj[u]) > 1 && unique!(adj[u])
        end

        sccs = _cr5_tarjan_scc(n_nodes, adj)
        node_to_scc = zeros(Int, n_nodes)
        for (ci, comp) in enumerate(sccs), u in comp
            node_to_scc[u] = ci
        end

        scc_levels = [Any[f.levels[active_f_list[u - n_ap]] for u in comp if u > n_ap] for comp in sccs]
        nonempty_level_sccs = findall(!isempty, scc_levels)

        if length(nonempty_level_sccs) <= 1
            push!(by_facet, (;
                facet = f.name,
                separated = false,
                demonstrated_in_compiled_model = false,
                n_scc = length(sccs),
                n_facet_scc = length(nonempty_level_sccs),
                scc_level_groups = [scc_levels[ci] for ci in nonempty_level_sccs],
                source_levels = Any[],
                sink_levels = Any[],
                anchored_blocks_separation = false,
                constrained_blocks_separation = false,
                reason = nothing,
            ))
            continue
        end

        n_scc = length(sccs)
        dag_out = [Set{Int}() for _ in 1:n_scc]
        for u in 1:n_nodes
            cu = node_to_scc[u]
            for w in adj[u]
                cw = node_to_scc[w]
                cu != cw && push!(dag_out[cu], cw)
            end
        end
        has_fixed_in_scc = [any(lvl -> get(fixed_map, (f.name, lvl), false), scc_levels[ci]) for ci in 1:n_scc]
        any_fixed_facet = any(has_fixed_in_scc)
        sink_candidates = [ci for ci in nonempty_level_sccs if isempty(dag_out[ci])]
        chosen_sink = isempty(sink_candidates) ? first(nonempty_level_sccs) : first(sink_candidates)
        for ci in sink_candidates
            if !has_fixed_in_scc[ci]
                chosen_sink = ci
                break
            end
        end
        sink_lvls = scc_levels[chosen_sink]
        other_lvls = reduce(vcat, [scc_levels[ci] for ci in nonempty_level_sccs if ci != chosen_sink]; init = Any[])
        blocked_by_anchors = any_fixed_facet && has_fixed_in_scc[chosen_sink] &&
            any(lvl -> get(fixed_map, (f.name, lvl), false), other_lvls)

        # Build the exact candidate recession vector `(d_theta, d_facet)` corresponding to the sink cut:
        # Sink SCC has no outgoing edges:
        #   if f_node in sink and p_node not in sink -> no edge f->p -> y == b_min
        #   if p_node in sink and f_node not in sink -> no edge p->f -> y == b_max
        # Setting d_theta = +1 (sink), -1 (other) and d_gamma_f = -1 (sink), +1 (other):
        #   (sink p, sink f) -> 0; (other p, other f) -> 0;
        #   (other p, sink f) -> -2 (y == b_min -> improves!);
        #   (sink p, other f) -> +2 (y == b_max -> improves!).
        sink_nodes = Set{Int}(sccs[chosen_sink])
        d_theta = zeros(Float64, P)
        for (k, p) in enumerate(active_p_list)
            d_theta[p] = (k in sink_nodes) ? 1.0 : -1.0
        end
        d_f_lvl = zeros(Float64, L)
        for (k, j) in enumerate(active_f_list)
            d_f_lvl[j] = ((n_ap + k) in sink_nodes) ? -1.0 : 1.0
        end

        demonstrated = false
        constrained_blocks = false
        if !blocked_by_anchors && !isempty(sink_lvls) && !isempty(other_lvls)
            if op isa AdditiveFacets.MRCMLOperator
                n_cells = length(op.B_pat)
                target_v = zeros(Float64, n_cells)
                pat_seen = falses(op.n_patterns)
                for n in active_rows
                    u = op.pattern_of_row[n]
                    pat_seen[u] && continue
                    pat_seen[u] = true
                    rng = op.pattern_ranges[u]
                    b0 = op.B_pat[first(rng)]
                    dfv = d_f_lvl[f.index[n]]
                    for m in rng
                        target_v[m] = (op.B_pat[m] - b0) * dfv
                    end
                end
                d_eta = _cr5_project_pattern_shift_to_mrcml(op, active_rows, target_v)
                if norm(d_eta) > 1e-10
                    demonstrated = _cr5_verify_compiled_recession(
                        person_idx, category_idx, supports, group_idx, active_rows, d_theta;
                        op, d_eta_free = d_eta)
                end
                constrained_blocks = !demonstrated
            else
                row_sh = Float64[d_f_lvl[f.index[n]] for n in eachindex(person_idx)]
                demonstrated = _cr5_verify_compiled_recession(
                    person_idx, category_idx, supports, group_idx, active_rows, d_theta;
                    op = nothing, row_facet_shift = row_sh)
                constrained_blocks = !demonstrated
            end
        end

        is_sep = demonstrated
        is_sep && (any_separated = true)
        reason = is_sep ?
            "Demonstrated one-sided score separation on facet :$(f.name) in compiled free coordinates: directed comparison graph has $(length(nonempty_level_sccs)) strongly connected level groups with no finite return path from sink levels $(sink_lvls) back to $(other_lvls); finite unpenalized JMLE does not exist." :
            nothing
        push!(by_facet, (;
            facet = f.name,
            separated = is_sep,
            demonstrated_in_compiled_model = demonstrated,
            n_scc = n_scc,
            n_facet_scc = length(nonempty_level_sccs),
            scc_level_groups = [scc_levels[ci] for ci in nonempty_level_sccs],
            source_levels = other_lvls,
            sink_levels = sink_lvls,
            anchored_blocks_separation = blocked_by_anchors,
            constrained_blocks_separation = constrained_blocks,
            reason,
        ))
    end

    # Polytomous global-RSM threshold-cut recession screen (verified in compiled free coordinates):
    # Catches designs like 3-category RSM with pairs (0,1), (1,0), (1,2), (2,1) where all
    # categories and margins are interior yet thresholds diverge to ±Inf.
    threshold_separations = NamedTuple[]
    if length(supports) == 1 && length(supports[1]) >= 3 && !isempty(active_rows)
        sup1 = supports[1]
        K = length(sup1)
        p_min_y = fill(K, P)
        p_max_y = fill(-1, P)
        for n in active_rows
            p = Int(person_idx[n])
            yk = Int(category_idx[n]) - first(sup1)
            yk < p_min_y[p] && (p_min_y[p] = yk)
            yk > p_max_y[p] && (p_max_y[p] = yk)
        end
        for c in 1:(K - 2)
            # Check if every active person observes ONLY <= c or ONLY >= c, with at least one < c and one > c
            all_split = true
            has_low = false
            has_high = false
            for p in active_p_list
                if p_max_y[p] <= c
                    p_min_y[p] < c && (has_low = true)
                elseif p_min_y[p] >= c
                    p_max_y[p] > c && (has_high = true)
                else
                    all_split = false
                    break
                end
            end
            (all_split && has_low && has_high) || continue
            # Sum-to-zero step stretch: dt_j = -1 for j <= c, +1 for j > c, centered by mean_dt
            raw_dt = Float64[j <= c ? -1.0 : 1.0 for j in 1:(K - 1)]
            mean_dt = sum(raw_dt) / length(raw_dt)
            dt = raw_dt .- mean_dt
            d_theta_t = zeros(Float64, P)
            for p in active_p_list
                d_theta_t[p] = (p_max_y[p] <= c ? -1.0 : 1.0) - mean_dt
            end
            demo_t = if op isa AdditiveFacets.MRCMLOperator
                n_cells = length(op.B_pat)
                target_v = zeros(Float64, n_cells)
                pat_seen = falses(op.n_patterns)
                for n in active_rows
                    u = op.pattern_of_row[n]
                    pat_seen[u] && continue
                    pat_seen[u] = true
                    rng = op.pattern_ranges[u]
                    cum = 0.0
                    target_v[rng[1]] = 0.0
                    for k in 1:(K - 1)
                        cum += dt[k]
                        target_v[rng[k + 1]] = -cum
                    end
                end
                d_eta_t = _cr5_project_pattern_shift_to_mrcml(op, active_rows, target_v)
                norm(d_eta_t) > 1e-10 && _cr5_verify_compiled_recession(
                    person_idx, category_idx, supports, group_idx, active_rows, d_theta_t;
                    op, d_eta_free = d_eta_t)
            else
                _cr5_verify_compiled_recession(
                    person_idx, category_idx, supports, group_idx, active_rows, d_theta_t;
                    op = nothing, step_shifts = [dt])
            end
            if demo_t
                any_separated = true
                push!(threshold_separations, (;
                    kind = :threshold_cut_separation,
                    cut_category_index = c,
                    demonstrated_in_compiled_model = true,
                    reason = "Demonstrated threshold-separation recession direction around category index $c in compiled free coordinates: no active person bridges both below and above category index $c, so step thresholds can diverge to ±Inf while strictly improving the unpenalized JMLE log-likelihood.",
                ))
            end
        end
    end

    return (;
        separated = any_separated,
        demonstrated_in_compiled_model = any_separated,
        existence_check_scope = scope_sym,
        existence_check_exhaustive = is_exact_fischer,
        existence_check_note = scope_note,
        by_facet,
        threshold_separations,
    )
end

function _cr5_sorted_intersect_count(a::Vector{Int}, b::Vector{Int})
    i = 1; j = 1; na = length(a); nb = length(b); c = 0
    @inbounds while i <= na && j <= nb
        ai = a[i]; bj = b[j]
        if ai == bj
            c += 1; i += 1; j += 1
        elseif ai < bj
            i += 1
        else
            j += 1
        end
    end
    return c
end

# Exact sparse thin-bridge check with inverted-list threshold verification for wide panels:
# avoids dense O(L^2) overlap matrices AND never emits a false thin-bridge warning from an
# adjacent-only heuristic approximation.
function _cr5_thin_bridges(
        person_idx::AbstractVector{<:Integer},
        facets_meta::Vector{NamedTuple},
        interior_rows::Vector{Int};
        min_bridge_overlap::Int = 2,
        exact_pair_budget::Int = 2_000_000,
        max_probe_pairs::Int = 500_000)
    records = NamedTuple[]
    for f in facets_meta
        L = length(f.levels)
        L <= 1 && continue
        person_levels = Dict{Int,Vector{Int}}()
        level_persons = [Int[] for _ in 1:L]
        for n in interior_rows
            p = Int(person_idx[n])
            j = f.index[n]
            vec = get!(person_levels, p) do
                Int[]
            end
            push!(vec, j)
            push!(level_persons[j], p)
        end
        for j in 1:L
            length(level_persons[j]) > 1 && (sort!(level_persons[j]); unique!(level_persons[j]))
        end
        total_pair_ops = 0
        for (_, lvls) in person_levels
            length(lvls) > 1 && (sort!(lvls); unique!(lvls))
            k = length(lvls)
            total_pair_ops += (k * (k - 1)) ÷ 2
        end

        parent = collect(1:L)
        find_root(x::Int) = begin
            r = x
            while parent[r] != r
                r = parent[r]
            end
            while parent[x] != r
                nxt = parent[x]
                parent[x] = r
                x = nxt
            end
            r
        end

        if total_pair_ops <= exact_pair_budget
            edge_weights = Dict{Tuple{Int,Int},Int}()
            for (_, lvls) in person_levels
                k = length(lvls)
                k <= 1 && continue
                for i in 1:(k - 1)
                    a = lvls[i]
                    for j in (i + 1):k
                        key = (a, lvls[j])
                        edge_weights[key] = get(edge_weights, key, 0) + 1
                    end
                end
            end
            sorted_edges = collect(edge_weights)
            sort!(sorted_edges; by = kv -> -kv[2])
            n_merged = 0
            min_mst_bridge = typemax(Int)
            weakest_pair = nothing
            for ((a, b), w) in sorted_edges
                ra = find_root(a)
                rb = find_root(b)
                ra == rb && continue
                parent[ra] = rb
                n_merged += 1
                if w < min_mst_bridge
                    min_mst_bridge = w
                    weakest_pair = (f.levels[a], f.levels[b])
                end
                n_merged == L - 1 && break
            end
            connected_co = (n_merged == L - 1)
            if !connected_co || min_mst_bridge <= min_bridge_overlap
                push!(records, (;
                    facet = f.name,
                    co_rating_connected = connected_co,
                    bottleneck_shared_interior_persons = connected_co ? min_mst_bridge : 0,
                    weakest_bridge_pair = weakest_pair,
                    threshold = min_bridge_overlap,
                    sparse_edge_count = length(edge_weights),
                    exact = true,
                    status = :thin_bridge_confirmed,
                    high_degree_approximation_used = false,
                ))
            end
        else
            # Ultra-wide dense panel exceeding exact_pair_budget:
            # Verify exact threshold connectivity `w(u, v) > min_bridge_overlap` using union-find
            # with inverted-list intersections. Only emit a thin-bridge record if proven exact;
            # otherwise report an inconclusive approximation without falsely claiming a thin bridge.
            n_merged = 0
            probed = 0
            budget_hit = false
            for u in 1:(L - 1)
                n_merged == L - 1 && break
                pu = level_persons[u]
                length(pu) <= min_bridge_overlap && continue
                for v in (u + 1):L
                    find_root(u) == find_root(v) && continue
                    pv = level_persons[v]
                    length(pv) <= min_bridge_overlap && continue
                    probed += 1
                    if probed > max_probe_pairs
                        budget_hit = true
                        break
                    end
                    if _cr5_sorted_intersect_count(pu, pv) > min_bridge_overlap
                        parent[find_root(u)] = find_root(v)
                        n_merged += 1
                        n_merged == L - 1 && break
                    end
                end
                budget_hit && break
            end
            if n_merged < L - 1
                if !budget_hit
                    # Exhaustively verified that no spanning tree exists with edge weight > min_bridge_overlap!
                    push!(records, (;
                        facet = f.name,
                        co_rating_connected = true,
                        bottleneck_shared_interior_persons = min_bridge_overlap,
                        weakest_bridge_pair = nothing,
                        threshold = min_bridge_overlap,
                        sparse_edge_count = probed,
                        exact = true,
                        status = :thin_bridge_confirmed,
                        high_degree_approximation_used = false,
                    ))
                else
                    push!(records, (;
                        facet = f.name,
                        co_rating_connected = missing,
                        bottleneck_shared_interior_persons = missing,
                        weakest_bridge_pair = nothing,
                        threshold = min_bridge_overlap,
                        sparse_edge_count = probed,
                        exact = false,
                        status = :inconclusive_approximation,
                        high_degree_approximation_used = true,
                    ))
                end
            end
        end
    end
    return records
end

function _cr5_category_sparsity_and_order(
        person_idx::AbstractVector{<:Integer},
        P::Int,
        categories::AbstractVector{Int},
        category_idx::AbstractVector{<:Integer},
        supports::AbstractVector{UnitRange{Int}},
        group_idx::AbstractVector{<:Integer},
        group_levels::AbstractVector,
        owner::Symbol;
        min_category_count::Int = 10)
    n_obs = length(person_idx)
    p_sum = zeros(Float64, P)
    p_cnt = zeros(Int, P)
    for n in 1:n_obs
        sup = supports[Int(group_idx[n])]
        span = max(last(sup) - first(sup), 1)
        p = Int(person_idx[n])
        p_sum[p] += (Int(category_idx[n]) - first(sup)) / span
        p_cnt[p] += 1
    end
    p_mean = [p_cnt[p] > 0 ? p_sum[p] / p_cnt[p] : NaN for p in 1:P]

    sparse_cells = NamedTuple[]
    order_inversions = NamedTuple[]
    for (g, sup) in enumerate(supports)
        K_g = length(sup)
        counts = zeros(Int, K_g)
        score_sums = zeros(Float64, K_g)
        for n in 1:n_obs
            Int(group_idx[n]) == g || continue
            loc = Int(category_idx[n]) - first(sup) + 1
            counts[loc] += 1
            score_sums[loc] += p_mean[Int(person_idx[n])]
        end
        g_lbl = group_levels[g]
        for loc in 1:K_g
            cnt = counts[loc]
            if 0 < cnt < min_category_count
                push!(sparse_cells, (;
                    step_owner = owner,
                    step_level = deepcopy(g_lbl),
                    category = categories[first(sup) + loc - 1],
                    count = cnt,
                    min_category_count,
                ))
            end
        end
        prev_loc = 0
        prev_mean = -Inf
        for loc in 1:K_g
            counts[loc] >= 2 || continue
            m = score_sums[loc] / counts[loc]
            if prev_loc > 0 && m < prev_mean - 1e-12
                push!(order_inversions, (;
                    step_owner = owner,
                    step_level = deepcopy(g_lbl),
                    lower_category = categories[first(sup) + prev_loc - 1],
                    upper_category = categories[first(sup) + loc - 1],
                    lower_mean_ability_proxy = prev_mean,
                    upper_mean_ability_proxy = m,
                    lower_count = counts[prev_loc],
                    upper_count = counts[loc],
                ))
            end
            prev_loc = loc
            prev_mean = m
        end
    end
    return (; sparse_cells, order_inversions)
end

function _cr5_effective_model(spec)
    pkg_ver = try
        v = pkgversion(@__MODULE__)
        v === nothing ? "0.2.0-DEV" : string(v)
    catch
        "0.2.0-DEV"
    end
    if spec isa AdditiveFacets.MRCMLTarget
        sr = spec.spec_record
        is_def = get(sr, :default_prior, false)
        has_int = get(sr, :has_interactions, false)
        has_lltm = get(sr, :has_lltm, false)
        return (;
            package_version = pkg_ver,
            family = :mfrm_mrcml,
            paradigm = :bayesian,
            threshold_owner = spec.owner,
            step_owner_spec = spec.step_owner_spec,
            location_mode = spec.location_mode,
            identification = is_def ? :isometric_helmert_zero_sum_with_population : :mrcml_design_matrix,
            default_prior = is_def,
            has_interactions = has_int,
            has_lltm = has_lltm,
            facet_names = [b.name for b in spec.facets],
            n_categories_by_group = [length(r) for r in spec.supports],
        )
    elseif spec isa AdditiveFacets.MRCMLSpec
        sr = spec.spec_record
        return (;
            package_version = pkg_ver,
            family = :mfrm_mrcml,
            paradigm = :frequentist,
            threshold_owner = spec.owner,
            step_owner_spec = spec.step_owner_spec,
            location_mode = spec.location_mode,
            identification = :mrcml_design_matrix,
            default_prior = false,
            has_interactions = get(sr, :has_interactions, false),
            has_lltm = get(sr, :has_lltm, false),
            facet_names = [b.name for b in spec.facets],
            n_categories_by_group = [length(r) for r in spec.supports],
        )
    elseif spec isa FrequentistMFRM.Spec
        return (;
            package_version = pkg_ver,
            family = spec.owner === :global ? :mfrm_rsm : :mfrm_pcm,
            paradigm = :frequentist,
            threshold_owner = spec.owner,
            step_owner_spec = spec.owner,
            location_mode = :finite_connected,
            identification = :sum_to_zero_facets,
            default_prior = false,
            has_interactions = false,
            has_lltm = false,
            facet_names = [b.name for b in spec.facets],
            n_categories_by_group = [length(r) for r in spec.supports],
        )
    elseif spec isa AdditiveFacets.AbstractTarget
        owner = hasproperty(spec, :owner) ? spec.owner : :none
        fnames = hasproperty(spec, :facets) ? [b.name for b in spec.facets] : Symbol[]
        ncats = hasproperty(spec, :supports) ? [length(r) for r in spec.supports] : Int[]
        return (;
            package_version = pkg_ver,
            family = nameof(typeof(spec)),
            paradigm = :bayesian,
            threshold_owner = owner,
            step_owner_spec = owner,
            location_mode = :additive_target,
            identification = :isometric_helmert_zero_sum,
            default_prior = false,
            has_interactions = false,
            has_lltm = false,
            facet_names = fnames,
            n_categories_by_group = ncats,
        )
    elseif spec isa FacetSpec
        step_c = _model_family_step_contract(spec)
        id_sym = spec.family === :gmfrm ? :gmfrm_item_sum_to_zero :
                 spec.family === :mgmfrm ? :mgmfrm_family_specific :
                 :reference_first
        return (;
            package_version = pkg_ver,
            family = spec.family,
            paradigm = :bayesian_or_frequentist_facetspec,
            threshold_owner = step_c.owner,
            step_owner_spec = spec.thresholds,
            location_mode = id_sym,
            identification = id_sym,
            default_prior = false,
            has_interactions = !isempty(spec.validation_bias_terms),
            has_lltm = false,
            facet_names = isnothing(spec.data.columns.rater) ? [:item] : [:item, :rater],
            n_categories_by_group = [length(spec.data.category_levels)],
        )
    end
    return (; package_version = pkg_ver, family = nameof(typeof(spec)))
end

function _cr5_build_compiled_nullspace(spec, facets_meta::Vector{NamedTuple}, op)
    P = length(spec.people)
    if op isa AdditiveFacets.MRCMLOperator
        d_xi = size(op.A_free, 2)
        (P + d_xi > 1200 || d_xi == 0) && return nothing
        At = AdditiveFacets.SparseArrays.sparse(transpose(op.A_free))
        rv = AdditiveFacets.SparseArrays.rowvals(At)
        nz = AdditiveFacets.SparseArrays.nonzeros(At)
        # Structural pattern contrast matrix
        s_rows = Int[]; s_cols = Int[]; s_vals = Float64[]; s_eq = 0
        for u in 1:op.n_patterns
            rng = op.pattern_ranges[u]
            m1 = first(rng)
            for m in rng[2:end]
                s_eq += 1
                for ptr in AdditiveFacets.SparseArrays.nzrange(At, m)
                    push!(s_rows, s_eq); push!(s_cols, rv[ptr]); push!(s_vals, nz[ptr])
                end
                for ptr in AdditiveFacets.SparseArrays.nzrange(At, m1)
                    push!(s_rows, s_eq); push!(s_cols, rv[ptr]); push!(s_vals, -nz[ptr])
                end
            end
        end
        M_struct = Matrix(AdditiveFacets.SparseArrays.sparse(s_rows, s_cols, s_vals, s_eq, d_xi))
        N_struct = s_eq > 0 ? LinearAlgebra.nullspace(M_struct; atol = 1e-8) : Matrix{Float64}(I, d_xi, d_xi)

        # Joint person + structural contrast matrix
        j_rows = Int[]; j_cols = Int[]; j_vals = Float64[]; j_eq = 0
        seen_pu = Set{Tuple{Int,Int}}()
        for n in eachindex(spec.person)
            p = Int(spec.person[n])
            u = op.pattern_of_row[n]
            (p, u) in seen_pu && continue
            push!(seen_pu, (p, u))
            rng = op.pattern_ranges[u]
            m1 = first(rng)
            b1 = op.B_pat[m1]
            for m in rng[2:end]
                j_eq += 1
                db = op.B_pat[m] - b1
                if db != 0.0
                    push!(j_rows, j_eq); push!(j_cols, p); push!(j_vals, db)
                end
                for ptr in AdditiveFacets.SparseArrays.nzrange(At, m)
                    push!(j_rows, j_eq); push!(j_cols, P + rv[ptr]); push!(j_vals, nz[ptr])
                end
                for ptr in AdditiveFacets.SparseArrays.nzrange(At, m1)
                    push!(j_rows, j_eq); push!(j_cols, P + rv[ptr]); push!(j_vals, -nz[ptr])
                end
            end
        end
        M_joint = Matrix(AdditiveFacets.SparseArrays.sparse(j_rows, j_cols, j_vals, j_eq, P + d_xi))
        N_joint = j_eq > 0 ? LinearAlgebra.nullspace(M_joint; atol = 1e-8) : Matrix{Float64}(I, P + d_xi, P + d_xi)
        # Model-name index lookup for each facet level
        block_ranges = Dict{Symbol,UnitRange{Int}}()
        for bm in op.block_meta
            if hasproperty(bm, :kind) && bm.kind in (:facet_main, :facet_isometric, :facet_calibrated, :facet_grouped, :facet_fixed) &&
                    hasproperty(bm, :model_range)
                block_ranges[Symbol(bm.name)] = bm.model_range
            elseif hasproperty(bm, :model_range) && any(f -> f.name === Symbol(bm.name), facets_meta)
                block_ranges[Symbol(bm.name)] = bm.model_range
            end
        end
        return (; kind = :mrcml, P, d_xi, J_model = Matrix(op.J_model), N_struct, N_joint, block_ranges)
    end
    # For FrequentistMFRM.Spec / AdditiveFacets.Target without MRCMLOperator: build sum-to-zero incidence nullspace
    f_dims = [max(length(f.levels) - 1, 0) for f in facets_meta]
    d_loc = sum(f_dims)
    (P + d_loc > 1200 || d_loc == 0) && return nothing
    n_mod = sum(f -> length(f.levels), facets_meta)
    J_loc = zeros(Float64, n_mod, d_loc)
    block_ranges = Dict{Symbol,UnitRange{Int}}()
    m_cur = 0; c_cur = 0
    for f in facets_meta
        L = length(f.levels)
        block_ranges[f.name] = (m_cur + 1):(m_cur + L)
        if L > 1
            H = AdditiveFacets.MRCML.helmert_basis(L)
            J_loc[(m_cur + 1):(m_cur + L), (c_cur + 1):(c_cur + L - 1)] .= H
            c_cur += L - 1
        end
        m_cur += L
    end
    # Unique observation patterns on location incidence
    seen_rows = Set{Tuple{Int,Vararg{Int}}}()
    M_s_rows = Vector{Float64}[]
    M_j_rows = Vector{Float64}[]
    for n in eachindex(spec.person)
        p = Int(spec.person[n])
        key = (p, (f.index[n] for f in facets_meta)...)
        key in seen_rows && continue
        push!(seen_rows, key)
        r_mod = zeros(Float64, n_mod)
        for f in facets_meta
            rng = block_ranges[f.name]
            r_mod[first(rng) + f.index[n] - 1] = Float64(f.sign)
        end
        r_free = vec(r_mod' * J_loc)
        push!(M_s_rows, r_free)
        rj = zeros(Float64, P + d_loc)
        rj[p] = 1.0
        rj[(P + 1):end] .= r_free
        push!(M_j_rows, rj)
    end
    isempty(M_s_rows) && return nothing
    M_struct = reduce(vcat, permutedims.(M_s_rows))
    M_joint = reduce(vcat, permutedims.(M_j_rows))
    N_struct = LinearAlgebra.nullspace(M_struct; atol = 1e-8)
    N_joint = LinearAlgebra.nullspace(M_joint; atol = 1e-8)
    return (; kind = :additive_location, P, d_xi = d_loc, J_model = J_loc, N_struct, N_joint, block_ranges)
end

function _cr5_eval_contrast_estimability(ns, c_mod::Vector{Float64})
    ns === nothing && return (; structural_estimable = missing, conditional_joint_estimable = missing)
    c_free = ns.J_model' * c_mod
    cn = norm(c_free)
    if cn <= 1e-12
        return (; structural_estimable = true, conditional_joint_estimable = true)
    end
    tol = 1e-7 * max(1.0, cn)
    s_est = isempty(ns.N_struct) || norm(ns.N_struct' * c_free) <= tol
    j_est = isempty(ns.N_joint) || norm(ns.N_joint[(ns.P + 1):end, :]' * c_free) <= tol
    return (; structural_estimable = s_est, conditional_joint_estimable = j_est)
end

# Common-rubric CR5 nesting, aliasing & null-space estimable-vs-aliased contrast audit:
# Separates directional nesting, one-to-one aliasing, higher-order aliasing, and weak overlap;
# uses the compiled constrained design matrix null space to confirm concrete estimable and
# aliased contrasts in original IDs and generate estimand-specific guidance.
function _cr5_nesting_and_aliasing_audit(
        spec,
        people::AbstractVector,
        person_idx::AbstractVector{<:Integer},
        facets_meta::Vector{NamedTuple},
        alloc,
        thin_bridges::Vector{NamedTuple};
        op = nothing)
    roles = NamedTuple[(; name = :person, levels = collect(Any, people), index = Int.(person_idx), sign = 1)]
    append!(roles, facets_meta)
    n_obs = length(person_idx)

    relations = NamedTuple[]
    # Check every ordered pair (child, parent) for directional nesting or one-to-one aliasing
    paired_one_to_one = Set{Tuple{Symbol,Symbol}}()
    for i in eachindex(roles), j in eachindex(roles)
        i == j && continue
        rc = roles[i]; rp = roles[j]
        Lc = length(rc.levels); Lp = length(rp.levels)
        (Lc <= 1 || Lp <= 1) && continue

        parents_of_c = [Set{Int}() for _ in 1:Lc]
        children_of_p = [Set{Int}() for _ in 1:Lp]
        for n in 1:n_obs
            ci = rc.index[n]; pi = rp.index[n]
            push!(parents_of_c[ci], pi)
            push!(children_of_p[pi], ci)
        end
        obs_c = [c for c in 1:Lc if !isempty(parents_of_c[c])]
        obs_p = [p for p in 1:Lp if !isempty(children_of_p[p])]
        (length(obs_c) <= 1 || length(obs_p) <= 1) && continue
        all(c -> length(parents_of_c[c]) == 1, obs_c) || continue

        max_ch = maximum(p -> length(children_of_p[p]), obs_p)
        if max_ch == 1 && length(obs_c) == length(obs_p)
            pair_key = rc.name < rp.name ? (rc.name, rp.name) : (rp.name, rc.name)
            pair_key in paired_one_to_one && continue
            push!(paired_one_to_one, pair_key)
            mapping = [(; parent_level = rp.levels[p], child_levels = Any[rc.levels[c] for c in sort!(collect(children_of_p[p]))],
                n_children = length(children_of_p[p])) for p in obs_p]
            push!(relations, (;
                kind = :one_to_one_aliasing,
                nested_role = rc.name,
                containing_role = rp.name,
                n_nested_observed = length(obs_c),
                n_containing_observed = length(obs_p),
                level_mapping = mapping,
                summary = "Roles :$(rc.name) and :$(rp.name) are in one-to-one aliasing ($(length(obs_c)) levels each); their main effects cannot be separated.",
            ))
        elseif max_ch >= 2
            mapping = [(; parent_level = rp.levels[p], child_levels = Any[rc.levels[c] for c in sort!(collect(children_of_p[p]))],
                n_children = length(children_of_p[p])) for p in obs_p]
            push!(relations, (;
                kind = :directional_nesting,
                nested_role = rc.name,
                containing_role = rp.name,
                n_nested_observed = length(obs_c),
                n_containing_observed = length(obs_p),
                level_mapping = mapping,
                summary = "Role :$(rc.name) ($(length(obs_c)) observed levels) is directionally nested within :$(rp.name) ($(length(obs_p)) observed levels): every :$(rc.name) level appears in only one :$(rp.name) level.",
            ))
        end
    end

    is_struct_id = Bool(get(alloc, :structural_identified, get(alloc, :identified, true)))
    is_joint_id = Bool(get(alloc, :conditional_joint_identified, get(alloc, :identified, true)))
    is_id = Bool(get(alloc, :identified, true))
    has_higher_order_aliasing = (!is_struct_id || !is_joint_id) && isempty(relations)
    has_weak_overlap = any(tb -> get(tb, :status, :thin_bridge_confirmed) === :thin_bridge_confirmed, thin_bridges)

    ns = (!isempty(relations) || !is_id || !is_struct_id || !is_joint_id) ?
        _cr5_build_compiled_nullspace(spec, facets_meta, op) : nothing

    estimable_contrasts = NamedTuple[]
    aliased_contrasts = NamedTuple[]
    recommendations = String[]

    if ns !== nothing
        n_mod = size(ns.J_model, 1)
        f_by_name = Dict{Symbol,NamedTuple}(f.name => f for f in facets_meta)

        function _record_contrast!(label::String, kind::Symbol, c_mod::Vector{Float64})
            res = _cr5_eval_contrast_estimability(ns, c_mod)
            entry = (;
                contrast = label,
                kind,
                structural_estimable = res.structural_estimable,
                conditional_joint_estimable = res.conditional_joint_estimable,
            )
            if res.conditional_joint_estimable === true
                push!(estimable_contrasts, entry)
            else
                push!(aliased_contrasts, entry)
            end
        end

        # 1) Evaluate contrasts directly implicated by each nesting/aliasing relation
        tested_facets = Set{Symbol}()
        for rel in relations
            nr = rel.nested_role
            pr = rel.containing_role
            if haskey(ns.block_ranges, pr) && haskey(f_by_name, pr)
                pf = f_by_name[pr]
                prng = ns.block_ranges[pr]
                if length(pf.levels) >= 2 && length(prng) == length(pf.levels)
                    push!(tested_facets, pr)
                    # Pure parent contrast (e.g., T2 - T1)
                    c_p = zeros(Float64, n_mod)
                    c_p[first(prng) + 1] = 1.0
                    c_p[first(prng)] = -1.0
                    _record_contrast!("$(pr)[$(pf.levels[2])] - $(pr)[$(pf.levels[1])]", :cross_panel_parent_contrast, c_p)

                    # If nested role is also a facet (e.g., rater nested in task):
                    if nr !== :person && haskey(ns.block_ranges, nr) && haskey(f_by_name, nr)
                        nf = f_by_name[nr]
                        nrng = ns.block_ranges[nr]
                        if length(nrng) == length(nf.levels)
                            push!(tested_facets, nr)
                            # Within-panel nested contrast (first two children in the first parent with >= 2 children)
                            for m in rel.level_mapping
                                if length(m.child_levels) >= 2
                                    i1 = findfirst(==(m.child_levels[1]), nf.levels)
                                    i2 = findfirst(==(m.child_levels[2]), nf.levels)
                                    if i1 !== nothing && i2 !== nothing
                                        c_w = zeros(Float64, n_mod)
                                        c_w[first(nrng) + i2 - 1] = 1.0
                                        c_w[first(nrng) + i1 - 1] = -1.0
                                        _record_contrast!(
                                            "$(nr)[$(nf.levels[i2])] - $(nr)[$(nf.levels[i1])] (within $(pr)=$(m.parent_level))",
                                            :within_panel_nested_contrast, c_w)
                                        break
                                    end
                                end
                            end
                            # Combined parent + mean nested-panel contrast: (P2 + mean(N in P2)) - (P1 + mean(N in P1))
                            if length(rel.level_mapping) >= 2
                                m1 = rel.level_mapping[1]; m2 = rel.level_mapping[2]
                                p1i = findfirst(==(m1.parent_level), pf.levels)
                                p2i = findfirst(==(m2.parent_level), pf.levels)
                                c1_idxs = [findfirst(==(cl), nf.levels) for cl in m1.child_levels]
                                c2_idxs = [findfirst(==(cl), nf.levels) for cl in m2.child_levels]
                                if p1i !== nothing && p2i !== nothing && all(!isnothing, c1_idxs) && all(!isnothing, c2_idxs)
                                    c_comb = zeros(Float64, n_mod)
                                    c_comb[first(prng) + p2i - 1] = Float64(pf.sign)
                                    c_comb[first(prng) + p1i - 1] = -Float64(pf.sign)
                                    for ci in c2_idxs
                                        c_comb[first(nrng) + ci - 1] += Float64(nf.sign) / length(c2_idxs)
                                    end
                                    for ci in c1_idxs
                                        c_comb[first(nrng) + ci - 1] -= Float64(nf.sign) / length(c1_idxs)
                                    end
                                    _record_contrast!(
                                        "($(pr)[$(m2.parent_level)] + mean($(nr) in $(m2.parent_level))) - ($(pr)[$(m1.parent_level)] + mean($(nr) in $(m1.parent_level)))",
                                        :combined_parent_plus_panel_contrast, c_comb)
                                end
                            end
                        end
                    end
                end
            end

            # Targeted estimand-based recommendations
            if rel.kind === :directional_nesting && nr !== :person
                push!(recommendations,
                    "Facet :$(nr) is nested within :$(pr): within-panel :$(nr) differences and combined (:$(pr) + :$(nr)-panel) differences are estimable, whereas the pure :$(pr) difference is aliased with the mean :$(nr)-panel severity difference. " *
                    "To separate pure :$(pr) difficulty from :$(nr)-panel severity, either (a) add ratings where at least some :$(nr) levels bridge across :$(pr) levels, " *
                    "(b) supply independently calibrated anchors (`fixed_calibration = (facets = ...)`), " *
                    "(c) impose an explicit within-panel mean convention (`fixed_calibration = (groups = ...)` — note this defines each :$(nr) panel's mean severity to the fixed value on that scale), or " *
                    "(d) collapse (:$(pr), :$(nr)) into a composite facet if the combined condition difference is the intended estimand.")
            elseif rel.kind === :directional_nesting && nr === :person
                push!(recommendations,
                    "Role :person is nested within :$(pr): pure :$(pr) difficulty differences are confounded with mean ability differences between :$(pr) cohorts. " *
                    "To separate :$(pr) difficulty from cohort ability, either (a) add bridging examinees observed across :$(pr) levels, " *
                    "(b) supply independently calibrated anchors (`fixed_calibration` / `calibration`), or " *
                    "(c) if examinees were randomly assigned from a common latent population, opt in explicitly to `population_link = (mode = :common_population, rationale = \"...\")` under MMLE (noting that freeing cohort ability means re-introduces non-identifiability).")
            elseif rel.kind === :one_to_one_aliasing
                push!(recommendations,
                    "Roles :$(nr) and :$(pr) are in one-to-one aliasing; drop one redundant role or collect crossed ratings before separating their main effects.")
            end
        end

        # 2) Also test common (non-nested) facet contrasts (e.g., common rubric criteria C2 - C1)
        for f in facets_meta
            f.name in tested_facets && continue
            haskey(ns.block_ranges, f.name) || continue
            rng = ns.block_ranges[f.name]
            (length(f.levels) >= 2 && length(rng) == length(f.levels)) || continue
            c_f = zeros(Float64, n_mod)
            c_f[first(rng) + 1] = 1.0
            c_f[first(rng)] = -1.0
            _record_contrast!("$(f.name)[$(f.levels[2])] - $(f.name)[$(f.levels[1])]", :common_facet_contrast, c_f)
        end
    end

    return (;
        has_nesting = any(r -> r.kind === :directional_nesting, relations),
        has_one_to_one_aliasing = any(r -> r.kind === :one_to_one_aliasing, relations),
        has_higher_order_aliasing,
        has_weak_overlap,
        relations,
        estimable_contrasts,
        aliased_contrasts,
        spqr_rank = (;
            structural_rank = get(alloc, :structural_rank, get(alloc, :rank, missing)),
            structural_columns = get(alloc, :structural_columns, get(alloc, :columns, missing)),
            conditional_joint_rank = get(alloc, :conditional_joint_rank, get(alloc, :rank, missing)),
            conditional_joint_columns = get(alloc, :conditional_joint_columns, get(alloc, :columns, missing)),
            dependent_structural_columns = get(alloc, :dependent_structural_columns, String[]),
            dependent_reference_columns = get(alloc, :dependent_reference_columns, String[]),
        ),
        recommendations = unique(recommendations),
    )
end

# Common-rubric CR5 dependence-unit audit (independent of identifiability):
# Reports declared response/assessment IDs, criteria per rating event, independently re-rated
# responses, and multi-response replication per person; explicitly marks unknown membership
# when response/assessment IDs are absent or only unique row IDs were supplied.
function _cr5_dependence_unit_audit(spec, facets_meta::Vector{NamedTuple})
    n_obs = spec isa FacetSpec ? spec.data.n : length(spec.person)
    p_idx = spec isa FacetSpec ? Int.(spec.data.person) : Int.(spec.person)

    resp_col = nothing
    assess_col = nothing
    resp_vals = nothing
    assess_vals = nothing

    if spec isa FacetSpec
        d = spec.data
        if haskey(d.optional, :response_id)
            resp_col = :response_id
            resp_vals = d.optional[:response_id]
        elseif haskey(d.optional, :performance)
            resp_col = :performance
            resp_vals = d.optional[:performance]
        end
        if haskey(d.optional, :assessment)
            assess_col = :assessment
            assess_vals = d.optional[:assessment]
        end
    elseif hasproperty(spec, :columns) && hasproperty(spec, :table)
        cols = spec.columns
        tbl = spec.table
        if hasproperty(cols, :performance) && cols.performance !== nothing && haskey(tbl, cols.performance)
            resp_col = cols.performance
            resp_vals = tbl[cols.performance]
        end
        if hasproperty(cols, :assessment) && cols.assessment !== nothing && haskey(tbl, cols.assessment)
            av = tbl[cols.assessment]
            # Auto-generated 1:N row_id (such as from R bridge) does NOT carry event membership!
            is_trivial_rowid = (cols.assessment === :row_id && length(unique(av)) == n_obs)
            if !is_trivial_rowid
                assess_col = cols.assessment
                assess_vals = av
            end
        end
    end

    rater_f = findfirst(f -> f.name === :rater, facets_meta)
    rater_idx = rater_f === nothing ? nothing : facets_meta[rater_f].index
    task_f = findfirst(f -> f.name === :task, facets_meta)
    task_idx = task_f === nothing ? nothing : facets_meta[task_f].index

    # Response/performance IDs establish response-level membership (independent re-rating and
    # multi-response replication per person); assessment IDs establish rating-event membership
    # (criteria scored together in one event) but do NOT identify which events belong to the
    # same underlying response.
    response_id_available = resp_vals !== nothing
    assessment_id_available = assess_vals !== nothing
    event_membership_known = response_id_available || assessment_id_available

    if !event_membership_known
        return (;
            response_id_column = resp_col,
            assessment_id_column = assess_col,
            response_id_available = false,
            assessment_id_available = false,
            event_membership_known = false,
            n_responses = missing,
            n_events = missing,
            min_criteria_per_event = missing,
            max_criteria_per_event = missing,
            mean_criteria_per_event = missing,
            n_independently_rerated_responses = missing,
            n_persons_with_multiple_responses = missing,
            person_response_variance_separable = missing,
            within_event_multi_criterion_detected = false,
            note = "Response and rater-response assessment event IDs were not declared (or only row-level IDs were supplied); event membership and within-event local dependence are unknown/unauditable. Supply `performance = :response_id` (and/or `assessment`) to audit multi-criterion rating events.",
        )
    end

    # Compute rater-response event-level counts (observable from either assessment ID or (response, rater))
    event_counts = Dict{Any,Int}()
    for n in 1:n_obs
        ek = if assessment_id_available
            assess_vals[n]
        elseif rater_idx !== nothing
            (resp_vals[n], rater_idx[n])
        else
            resp_vals[n]
        end
        event_counts[ek] = get(event_counts, ek, 0) + 1
    end

    ev_vals = collect(values(event_counts))
    min_c = isempty(ev_vals) ? 0 : minimum(ev_vals)
    max_c = isempty(ev_vals) ? 0 : maximum(ev_vals)
    mean_c = isempty(ev_vals) ? 0.0 : mean(ev_vals)
    multi_crit = max_c >= 2

    # Compute response-level counts ONLY when response/performance IDs are explicitly declared;
    # assessment IDs alone cannot tell whether two events rated the same response or distinct responses.
    if response_id_available
        resp_raters = Dict{Any,Set{Int}}()
        person_resps = Dict{Int,Set{Any}}()
        for n in 1:n_obs
            rk = resp_vals[n]
            p = p_idx[n]
            push!(get!(person_resps, p) do; Set{Any}(); end, rk)
            if rater_idx !== nothing
                push!(get!(resp_raters, rk) do; Set{Int}(); end, rater_idx[n])
            end
        end
        n_responses = length(resp_raters) > 0 ? length(resp_raters) : length(unique(resp_vals))
        n_rerated = rater_idx === nothing ? 0 : count(s -> length(s) >= 2, values(resp_raters))
        n_multi_p = count(s -> length(s) >= 2, values(person_resps))
        separable_pr = n_multi_p >= 1
    else
        n_responses = missing
        n_rerated = missing
        n_multi_p = missing
        separable_pr = missing
    end

    note_parts = String[]
    if multi_crit
        push!(note_parts, "Multiple ratings ($(min_c)–$(max_c), mean $(round(mean_c; digits=2))) share the same rater-response event under a scalar conditional-independence baseline. Positive within-event residual correlation can deflate total-score SEs without necessarily affecting criterion-contrast SEs in the same direction; within-event association alone does not establish causal halo.")
    end
    if response_id_available
        if !separable_pr
            push!(note_parts, "At most one response per person is observed ($(n_multi_p) person(s) with >= 2 responses), so person ability variance and response-level random-effect variance cannot be separated.")
        end
        if rater_idx !== nothing && n_rerated == 0 && multi_crit
            push!(note_parts, "No response is independently re-rated by multiple raters (n_independently_rerated_responses = 0), so shared response quality cannot be separated from rater-specific event impression.")
        end
    else
        push!(note_parts, "Only assessment event IDs were declared (no response/performance ID); event-level multi-criterion counts are audited ($(length(event_counts)) event(s)), while n_responses, n_independently_rerated_responses, n_persons_with_multiple_responses, and person_response_variance_separable are missing because response membership cannot be inferred from assessment IDs alone. Supply `performance = :response_id` to audit response-level replication and independent re-rating.")
    end
    isempty(note_parts) && push!(note_parts, "Event membership audited: $(length(event_counts)) event(s), $(n_rerated) independently re-rated response(s), $(n_multi_p) person(s) with >= 2 responses.")

    return (;
        response_id_column = resp_col,
        assessment_id_column = assess_col,
        response_id_available,
        assessment_id_available,
        event_membership_known = true,
        n_responses,
        n_events = length(event_counts),
        min_criteria_per_event = min_c,
        max_criteria_per_event = max_c,
        mean_criteria_per_event = mean_c,
        n_independently_rerated_responses = n_rerated,
        n_persons_with_multiple_responses = n_multi_p,
        person_response_variance_separable = separable_pr,
        within_event_multi_criterion_detected = multi_crit,
        note = join(note_parts, " "),
    )
end

function _cr5_extract_missing_audit(spec)
    if hasproperty(spec, :spec_record) && hasproperty(spec.spec_record, :missing_audit)
        return deepcopy(spec.spec_record.missing_audit)
    elseif hasproperty(spec, :columns) && hasproperty(spec.columns, :missing_audit)
        return deepcopy(spec.columns.missing_audit)
    elseif spec isa FacetSpec && hasproperty(spec.data.columns, :missing_audit)
        return deepcopy(spec.data.columns.missing_audit)
    end
    return nothing
end

function _cr5_unified_validate(
        spec;
        min_category_count::Int = 10,
        min_bridge_overlap::Int = 2)
    min_category_count >= 1 || throw(ArgumentError("min_category_count must be >= 1"))
    min_bridge_overlap >= 0 || throw(ArgumentError("min_bridge_overlap must be >= 0"))

    alloc = deepcopy(spec.allocation)
    issues = ValidationIssue[]
    if hasproperty(alloc, :reasons)
        for msg in alloc.reasons
            code = occursin("disconnected", lowercase(msg)) ? :disconnected_design :
                   occursin("rank-deficient", lowercase(msg)) ? :rank_deficient_design :
                   occursin("no observations", lowercase(msg)) ? :unobserved_declared_level :
                   :design_identification_error
            push!(issues, ValidationIssue(code, :error, String(msg)))
        end
    end

    has_facets = hasproperty(spec, :people) && hasproperty(spec, :person) && hasproperty(spec, :facets)
    facets_meta = has_facets ? _cr5_facet_tuples(spec.facets) : NamedTuple[]
    disjoint = has_facets ? _cr5_disjoint_subsets(spec.people, spec.person, facets_meta) : nothing

    if disjoint !== nothing
        if !disjoint.overall_connected
            push!(issues, ValidationIssue(
                :disconnected_design,
                :error,
                "rating design splits into $(disjoint.n_overall_subsets) disjoint overall subset(s)",
                context = Dict{Symbol,Any}(:n_subsets => disjoint.n_overall_subsets),
            ))
        end
        for fr in disjoint.by_facet
            fr.connected && continue
            push!(issues, ValidationIssue(
                :facet_person_disconnected_subsets,
                :warning,
                "facet :$(fr.facet) splits into $(fr.n_subsets) person-linked subset(s): $(fr.bridge_suggestion)",
                context = Dict{Symbol,Any}(:facet => fr.facet, :n_subsets => fr.n_subsets),
            ))
        end
    end

    is_ordinal = has_facets && hasproperty(spec, :categories) && hasproperty(spec, :category) &&
                 hasproperty(spec, :supports) && hasproperty(spec, :group) &&
                 hasproperty(spec, :group_levels) && hasproperty(spec, :owner)
    op = (hasproperty(spec, :operator) && spec.operator isa AdditiveFacets.MRCMLOperator) ? spec.operator : nothing
    fixed_map = _cr5_fixed_facet_level_lookup(spec)

    extreme_elements = nothing
    score_disjoint = nothing
    separation = nothing
    extreme_only_bridges = NamedTuple[]
    thin_bridges = NamedTuple[]
    cat_diag = (; sparse_cells = NamedTuple[], order_inversions = NamedTuple[])
    score_connected = missing

    if is_ordinal
        extreme_elements = _cr5_extreme_elements(
            spec.people, spec.person, facets_meta, spec.category, spec.supports, spec.group;
            op, fixed_map)
        p_status = extreme_elements.person.status
        interior_rows = [n for n in eachindex(spec.person) if p_status[Int(spec.person[n])] === :interior]
        score_disjoint = _cr5_disjoint_subsets(
            spec.people, spec.person, facets_meta; active_rows = interior_rows)
        isolated_levels = score_disjoint.isolated_facet_levels

        separation = _cr5_fischer_separation_audit(
            spec.people, spec.person, facets_meta, spec.category, spec.supports, spec.group,
            interior_rows; op, fixed_map)

        score_connected = !isempty(interior_rows) &&
                          score_disjoint.overall_connected &&
                          score_disjoint.all_facets_person_connected &&
                          isempty(isolated_levels) &&
                          !separation.separated

        if disjoint.overall_connected && !score_disjoint.overall_connected
            push!(extreme_only_bridges, (;
                scope = :overall,
                structural_subsets = disjoint.n_overall_subsets,
                interior_subsets = score_disjoint.n_overall_subsets,
            ))
        end
        for (fr_full, fr_int) in zip(disjoint.by_facet, score_disjoint.by_facet)
            if fr_full.connected && !fr_int.connected
                push!(extreme_only_bridges, (;
                    scope = fr_full.facet,
                    structural_subsets = fr_full.n_subsets,
                    interior_subsets = fr_int.n_subsets,
                ))
            end
        end
        if isempty(interior_rows) || !score_disjoint.overall_connected ||
                !score_disjoint.all_facets_person_connected || !isempty(isolated_levels)
            push!(issues, ValidationIssue(
                :score_conditioned_disconnected_design,
                :warning,
                "excluding extreme-scoring (all-minimum/all-maximum) persons disconnects or isolates the rating design ($(length(interior_rows))/$(length(spec.person)) interior rows retained); unadjusted JMLE cannot link across extreme-only bridges and Bayesian contrasts rely on prior pooling.",
                context = Dict{Symbol,Any}(
                    :n_interior_rows => length(interior_rows),
                    :n_total_rows => length(spec.person),
                    :extreme_only_bridges => extreme_only_bridges,
                    :isolated_facet_levels => isolated_levels,
                ),
            ))
        end
        if separation.separated
            for srec in separation.by_facet
                srec.separated || continue
                push!(issues, ValidationIssue(
                    :one_sided_score_separation,
                    :warning,
                    String(srec.reason),
                    context = Dict{Symbol,Any}(
                        :facet => srec.facet,
                        :source_levels => srec.source_levels,
                        :sink_levels => srec.sink_levels,
                        :n_facet_scc => srec.n_facet_scc,
                        :scope => separation.existence_check_scope,
                    ),
                ))
            end
            for trec in separation.threshold_separations
                push!(issues, ValidationIssue(
                    :one_sided_score_separation,
                    :warning,
                    String(trec.reason),
                    context = Dict{Symbol,Any}(
                        :kind => trec.kind,
                        :cut_category_index => trec.cut_category_index,
                        :scope => separation.existence_check_scope,
                    ),
                ))
            end
        end

        for fe in extreme_elements.facets
            fe.n_extreme == 0 && continue
            sev_msg = fe.n_free_extreme > 0 ?
                "facet :$(fe.facet) has $(fe.n_free_extreme) free extreme level(s) (all-minimum: $(fe.free_all_minimum), all-maximum: $(fe.free_all_maximum)); unpenalized ML estimates are unbounded and Bayesian estimates depend strongly on the prior." :
                "facet :$(fe.facet) has $(fe.n_extreme) anchored/fixed extreme level(s) ($(fe.fixed_extreme_levels)); because these levels are fixed, they do not trigger unbounded free-estimand failure."
            push!(issues, ValidationIssue(
                :extreme_facet_level,
                :warning,
                sev_msg,
                context = Dict{Symbol,Any}(
                    :facet => fe.facet,
                    :all_minimum => fe.all_minimum,
                    :all_maximum => fe.all_maximum,
                    :free_all_minimum => fe.free_all_minimum,
                    :free_all_maximum => fe.free_all_maximum,
                    :fixed_extreme_levels => fe.fixed_extreme_levels,
                ),
            ))
        end

        thin_bridges = _cr5_thin_bridges(spec.person, facets_meta, interior_rows; min_bridge_overlap)
        for tb in thin_bridges
            tb.status === :thin_bridge_confirmed || continue
            push!(issues, ValidationIssue(
                :thin_facet_bridge,
                :warning,
                "facet :$(tb.facet) has a thin interior-person bridge (bottleneck overlap = $(tb.bottleneck_shared_interior_persons) <= $(tb.threshold) shared interior person(s); weakest pair = $(tb.weakest_bridge_pair)). Under generalized/GMFRM slopes, low-consistency judges attenuate bridge Fisher information by alpha_r^2.",
                context = Dict{Symbol,Any}(
                    :facet => tb.facet,
                    :bottleneck_overlap => tb.bottleneck_shared_interior_persons,
                    :weakest_pair => tb.weakest_bridge_pair,
                ),
            ))
        end

        cat_diag = _cr5_category_sparsity_and_order(
            spec.person, length(spec.people), spec.categories, spec.category,
            spec.supports, spec.group, spec.group_levels, spec.owner;
            min_category_count,
        )
        for sc in cat_diag.sparse_cells
            push!(issues, ValidationIssue(
                :sparse_category_cell,
                :warning,
                "steps :$(sc.step_owner)=$(repr(sc.step_level)) category $(sc.category) has only $(sc.count) observation(s) (< $(sc.min_category_count)); threshold estimates may be imprecise or prior-sensitive.",
                context = Dict{Symbol,Any}(
                    :step_owner => sc.step_owner,
                    :step_level => sc.step_level,
                    :category => sc.category,
                    :count => sc.count,
                ),
            ))
        end
        for inv in cat_diag.order_inversions
            push!(issues, ValidationIssue(
                :empirical_category_order_inversion,
                :warning,
                "steps :$(inv.step_owner)=$(repr(inv.step_level)): empirical mean ability proxy drops from $(round(inv.lower_mean_ability_proxy; digits=3)) in category $(inv.lower_category) to $(round(inv.upper_mean_ability_proxy; digits=3)) in category $(inv.upper_category) (potential step-disordering / category collapse risk).",
                context = Dict{Symbol,Any}(
                    :step_owner => inv.step_owner,
                    :step_level => inv.step_level,
                    :lower_category => inv.lower_category,
                    :upper_category => inv.upper_category,
                ),
            ))
        end
    end

    patterns = spec isa AdditiveFacets.AbstractTarget ? AdditiveFacets.response_patterns(spec) :
        (is_ordinal ? AdditiveFacets.response_patterns(spec) : nothing)
    pattern_warnings = patterns === nothing ? String[] : collect(String, patterns.warnings)
    if patterns !== nothing && hasproperty(patterns, :issues)
        for pi in patterns.issues
            push!(issues, ValidationIssue(
                get(pi, :code, :response_pattern_warning),
                get(pi, :severity, :warning),
                String(get(pi, :message, string(pi))),
            ))
        end
    end

    extra_w = String[]
    hasproperty(alloc, :slope_warnings) && append!(extra_w, alloc.slope_warnings)
    hasproperty(spec, :prior_symmetry) && append!(extra_w, spec.prior_symmetry.warnings)
    for w in extra_w
        push!(issues, ValidationIssue(:model_structure_warning, :warning, String(w)))
    end

    nesting_and_aliasing = has_facets ?
        _cr5_nesting_and_aliasing_audit(spec, spec.people, spec.person, facets_meta, alloc, thin_bridges; op) :
        nothing
    if nesting_and_aliasing !== nothing && (nesting_and_aliasing.has_nesting || nesting_and_aliasing.has_one_to_one_aliasing)
        for rel in nesting_and_aliasing.relations
            push!(issues, ValidationIssue(
                :nested_or_aliased_facets,
                :warning,
                String(rel.summary),
                context = Dict{Symbol,Any}(
                    :kind => rel.kind,
                    :nested_role => rel.nested_role,
                    :containing_role => rel.containing_role,
                ),
            ))
        end
    end

    dependence_units = has_facets ? _cr5_dependence_unit_audit(spec, facets_meta) : nothing
    if dependence_units !== nothing && dependence_units.within_event_multi_criterion_detected
        push!(issues, ValidationIssue(
            :within_event_local_dependence_unmodeled,
            :warning,
            String(dependence_units.note),
            context = Dict{Symbol,Any}(
                :n_events => dependence_units.n_events,
                :max_criteria_per_event => dependence_units.max_criteria_per_event,
                :n_independently_rerated_responses => dependence_units.n_independently_rerated_responses,
            ),
        ))
    end

    cr5_warn_msgs = [iss.message for iss in issues if iss.severity === :warning &&
        iss.code in (:facet_person_disconnected_subsets, :score_conditioned_disconnected_design,
                     :one_sided_score_separation, :extreme_facet_level, :thin_facet_bridge,
                     :sparse_category_cell, :empirical_category_order_inversion,
                     :nested_or_aliased_facets, :within_event_local_dependence_unmodeled)]
    all_warnings = unique(vcat(pattern_warnings, extra_w, cr5_warn_msgs))

    connectedness = (;
        structural_identified = Bool(get(alloc, :identified, false)),
        structural_rank_method = get(alloc, :method, :design_rank),
        overall_connected = disjoint === nothing ? missing : disjoint.overall_connected,
        n_overall_subsets = disjoint === nothing ? missing : disjoint.n_overall_subsets,
        all_facets_person_connected = disjoint === nothing ? missing : disjoint.all_facets_person_connected,
        score_conditioned_applicable = is_ordinal,
        score_conditioned_connected = score_connected,
        n_score_conditioned_subsets = score_disjoint === nothing ? missing : score_disjoint.n_overall_subsets,
        isolated_facet_levels = score_disjoint === nothing ? NamedTuple[] : score_disjoint.isolated_facet_levels,
        n_isolated_facet_levels = score_disjoint === nothing ? 0 : score_disjoint.n_isolated_facet_levels,
        one_sided_separated = separation === nothing ? missing : separation.separated,
        existence_check_scope = separation === nothing ? :not_applicable : separation.existence_check_scope,
        existence_check_exhaustive = separation === nothing ? false : separation.existence_check_exhaustive,
        extreme_only_bridges,
        thin_bridges,
    )

    missing_audit = _cr5_extract_missing_audit(spec)
    extra_fields = (;
        schema = "bayesianmgmfrm.design_validation.v2",
        passed = Bool(get(alloc, :passed, get(alloc, :identified, false))),
        issues,
        disjoint_subsets = disjoint,
        score_conditioned_subsets = score_disjoint,
        one_sided_separation = separation,
        connectedness,
        extreme_elements,
        category_diagnostics = cat_diag,
        nesting_and_aliasing,
        dependence_units,
        effective_model = _cr5_effective_model(spec),
        missing_audit,
        warnings = all_warnings,
    )
    if patterns !== nothing
        extra_fields = merge(extra_fields, (; response_patterns = patterns))
    end
    if hasproperty(spec, :prior_symmetry)
        extra_fields = merge(extra_fields, (; prior_symmetry = deepcopy(spec.prior_symmetry)))
    end
    return merge(alloc, extra_fields)
end

function _facet_spec_validation_error(data::FacetData, report::ValidationReport; ids = nothing)
    label(role, levels) = ids === nothing || !hasproperty(ids, role) ? levels :
        [getproperty(ids, role)[Int(level)] for level in levels]
    facets = NamedTuple[(; name = :item, levels = label(:item, data.item_levels), index = data.item)]
    if data.columns.rater !== nothing
        push!(facets, (; name = :rater, levels = label(:rater, data.rater_levels), index = data.rater))
    end
    subsets = _cr5_disjoint_subsets(label(:person, data.person_levels), data.person, facets)
    errors = filter(issue -> issue.severity === :error, report.issues)
    messages = ["cannot construct MFRM spec until validation errors are resolved: $([i.code for i in errors])",
        join((i.message for i in errors), "; ")]
    for block in subsets.by_facet
        block.connected && continue
        push!(messages, "Observed :$(block.facet) subsets: " *
            join((repr(s.levels) for s in block.subsets), " | ") * ". " * block.bridge_suggestion)
    end
    if !subsets.all_facets_person_connected
        push!(messages, "Alternatively, analyze the subsets separately and report within-subset contrasts; shared criteria alone do not identify between-panel severity differences.")
    end
    return ArgumentError(join(messages, " "))
end

function _cr5_validate_facet_spec(
        spec::FacetSpec;
        min_category_count::Int = 10,
        min_bridge_overlap::Int = 2)
    min_category_count >= 1 || throw(ArgumentError("min_category_count must be >= 1"))
    min_bridge_overlap >= 0 || throw(ArgumentError("min_bridge_overlap must be >= 0"))

    vr = spec.validation
    d = spec.data
    facets_meta = NamedTuple[
        (; name = :item, levels = collect(Any, d.item_levels), index = Int.(d.item), sign = -1),
    ]
    if d.columns.rater !== nothing
        push!(facets_meta, (; name = :rater, levels = collect(Any, d.rater_levels), index = Int.(d.rater), sign = -1))
    end
    step_c = _model_family_step_contract(spec)
    owner = step_c.owner
    K = length(d.category_levels)
    group_idx, group_levels = if owner === :global
        (ones(Int, d.n), Any[:global])
    elseif owner === :rater && d.columns.rater !== nothing
        (Int.(d.rater), collect(Any, d.rater_levels))
    else
        (Int.(d.item), collect(Any, d.item_levels))
    end
    supports = [1:K for _ in eachindex(group_levels)]
    fixed_map = _cr5_fixed_facet_level_lookup(spec)

    disjoint = _cr5_disjoint_subsets(d.person_levels, d.person, facets_meta)
    extreme_elements = _cr5_extreme_elements(
        d.person_levels, d.person, facets_meta, d.category, supports, group_idx; fixed_map)
    p_status = extreme_elements.person.status
    interior_rows = [n for n in 1:d.n if p_status[d.person[n]] === :interior]
    score_disjoint = _cr5_disjoint_subsets(d.person_levels, d.person, facets_meta; active_rows = interior_rows)
    separation = _cr5_fischer_separation_audit(
        d.person_levels, d.person, facets_meta, d.category, supports, group_idx, interior_rows; fixed_map)
    thin_bridges = _cr5_thin_bridges(d.person, facets_meta, interior_rows; min_bridge_overlap)
    cat_diag = _cr5_category_sparsity_and_order(
        d.person, length(d.person_levels), d.category_levels, d.category,
        supports, group_idx, group_levels, owner; min_category_count)

    extreme_only_bridges = NamedTuple[]
    if disjoint.overall_connected && !score_disjoint.overall_connected
        push!(extreme_only_bridges, (;
            scope = :overall,
            structural_subsets = disjoint.n_overall_subsets,
            interior_subsets = score_disjoint.n_overall_subsets,
        ))
    end
    for (fr_full, fr_int) in zip(disjoint.by_facet, score_disjoint.by_facet)
        if fr_full.connected && !fr_int.connected
            push!(extreme_only_bridges, (;
                scope = fr_full.facet,
                structural_subsets = fr_full.n_subsets,
                interior_subsets = fr_int.n_subsets,
            ))
        end
    end
    score_connected = !isempty(interior_rows) &&
                      score_disjoint.overall_connected &&
                      score_disjoint.all_facets_person_connected &&
                      isempty(score_disjoint.isolated_facet_levels) &&
                      !separation.separated

    issues = copy(vr.issues)
    for fr in disjoint.by_facet
        fr.connected && continue
        push!(issues, ValidationIssue(
            :facet_person_disconnected_subsets,
            :warning,
            "facet :$(fr.facet) splits into $(fr.n_subsets) person-linked subset(s): $(fr.bridge_suggestion)",
            context = Dict{Symbol,Any}(:facet => fr.facet, :n_subsets => fr.n_subsets),
        ))
    end
    if !isempty(extreme_only_bridges) || !isempty(score_disjoint.isolated_facet_levels)
        push!(issues, ValidationIssue(
            :score_conditioned_disconnected_design,
            :warning,
            "excluding extreme-scoring persons disconnects or isolates the rating design ($(length(interior_rows))/$(d.n) interior rows retained).",
            context = Dict{Symbol,Any}(
                :extreme_only_bridges => extreme_only_bridges,
                :isolated_facet_levels => score_disjoint.isolated_facet_levels,
            ),
        ))
    end
    if separation.separated
        for srec in separation.by_facet
            srec.separated || continue
            push!(issues, ValidationIssue(
                :one_sided_score_separation,
                :warning,
                String(srec.reason),
                context = Dict{Symbol,Any}(
                    :facet => srec.facet,
                    :source_levels => srec.source_levels,
                    :sink_levels => srec.sink_levels,
                    :scope => separation.existence_check_scope,
                ),
            ))
        end
        for trec in separation.threshold_separations
            push!(issues, ValidationIssue(
                :one_sided_score_separation,
                :warning,
                String(trec.reason),
                context = Dict{Symbol,Any}(
                    :kind => trec.kind,
                    :cut_category_index => trec.cut_category_index,
                    :scope => separation.existence_check_scope,
                ),
            ))
        end
    end
    for tb in thin_bridges
        tb.status === :thin_bridge_confirmed || continue
        push!(issues, ValidationIssue(
            :thin_facet_bridge,
            :warning,
            "facet :$(tb.facet) has a thin interior-person bridge (bottleneck overlap = $(tb.bottleneck_shared_interior_persons) <= $(tb.threshold) shared interior person(s); weakest pair = $(tb.weakest_bridge_pair)). Under generalized/GMFRM slopes, low-consistency judges attenuate bridge Fisher information by alpha_r^2.",
            context = Dict{Symbol,Any}(
                :facet => tb.facet,
                :bottleneck_overlap => tb.bottleneck_shared_interior_persons,
                :weakest_pair => tb.weakest_bridge_pair,
            ),
        ))
    end
    for sc in cat_diag.sparse_cells
        push!(issues, ValidationIssue(
            :sparse_category_cell,
            :warning,
            "steps :$(sc.step_owner)=$(repr(sc.step_level)) category $(sc.category) has only $(sc.count) observation(s) (< $(sc.min_category_count)).",
            context = Dict{Symbol,Any}(:step_owner => sc.step_owner, :step_level => sc.step_level, :category => sc.category, :count => sc.count),
        ))
    end
    for inv in cat_diag.order_inversions
        push!(issues, ValidationIssue(
            :empirical_category_order_inversion,
            :warning,
            "steps :$(inv.step_owner)=$(repr(inv.step_level)): empirical mean ability proxy drops from $(round(inv.lower_mean_ability_proxy; digits=3)) in category $(inv.lower_category) to $(round(inv.upper_mean_ability_proxy; digits=3)) in category $(inv.upper_category).",
            context = Dict{Symbol,Any}(:step_owner => inv.step_owner, :step_level => inv.step_level, :lower_category => inv.lower_category, :upper_category => inv.upper_category),
        ))
    end

    nesting_and_aliasing = _cr5_nesting_and_aliasing_audit(
        spec, d.person_levels, d.person, facets_meta, (; identified = vr.passed), thin_bridges; op = nothing)
    if nesting_and_aliasing.has_nesting || nesting_and_aliasing.has_one_to_one_aliasing
        for rel in nesting_and_aliasing.relations
            push!(issues, ValidationIssue(
                :nested_or_aliased_facets,
                :warning,
                String(rel.summary),
                context = Dict{Symbol,Any}(
                    :kind => rel.kind,
                    :nested_role => rel.nested_role,
                    :containing_role => rel.containing_role,
                ),
            ))
        end
    end
    dependence_units = _cr5_dependence_unit_audit(spec, facets_meta)
    if dependence_units.within_event_multi_criterion_detected
        push!(issues, ValidationIssue(
            :within_event_local_dependence_unmodeled,
            :warning,
            String(dependence_units.note),
            context = Dict{Symbol,Any}(
                :n_events => dependence_units.n_events,
                :max_criteria_per_event => dependence_units.max_criteria_per_event,
                :n_independently_rerated_responses => dependence_units.n_independently_rerated_responses,
            ),
        ))
    end

    connectedness = (;
        structural_identified = vr.passed,
        structural_rank_method = :facet_data_minimal_location_rank,
        overall_connected = disjoint.overall_connected,
        n_overall_subsets = disjoint.n_overall_subsets,
        all_facets_person_connected = disjoint.all_facets_person_connected,
        score_conditioned_applicable = true,
        score_conditioned_connected = score_connected,
        n_score_conditioned_subsets = score_disjoint.n_overall_subsets,
        isolated_facet_levels = score_disjoint.isolated_facet_levels,
        n_isolated_facet_levels = score_disjoint.n_isolated_facet_levels,
        one_sided_separated = separation.separated,
        existence_check_scope = separation.existence_check_scope,
        existence_check_exhaustive = separation.existence_check_exhaustive,
        extreme_only_bridges,
        thin_bridges,
    )

    return (;
        schema = "bayesianmgmfrm.design_validation.v2",
        n = vr.n,
        n_observations = vr.n,
        passed = vr.passed,
        identified = vr.passed,
        issues,
        category_counts = vr.category_counts,
        facet_counts = vr.facet_counts,
        components = vr.components,
        dff_counts = vr.dff_counts,
        data_signature = vr.data_signature,
        options_signature = vr.options_signature,
        disjoint_subsets = disjoint,
        score_conditioned_subsets = score_disjoint,
        one_sided_separation = separation,
        connectedness,
        extreme_elements,
        category_diagnostics = cat_diag,
        nesting_and_aliasing,
        dependence_units,
        effective_model = _cr5_effective_model(spec),
        missing_audit = _cr5_extract_missing_audit(spec),
        warnings = [iss.message for iss in issues if iss.severity === :warning],
    )
end

validate_design(t::AdditiveFacets.AbstractTarget; min_category_count::Int = 10, min_bridge_overlap::Int = 2) =
    _cr5_unified_validate(t; min_category_count, min_bridge_overlap)

validate_design(s::Union{FrequentistMFRM.Spec,AdditiveFacets.MRCMLSpec}; min_category_count::Int = 10, min_bridge_overlap::Int = 2) =
    _cr5_unified_validate(s; min_category_count, min_bridge_overlap)

validate_design(spec::FacetSpec; min_category_count::Int = 10, min_bridge_overlap::Int = 2) =
    _cr5_validate_facet_spec(spec; min_category_count, min_bridge_overlap)

validate_design(design::FacetDesign; kwargs...) = validate_design(design.spec; kwargs...)
