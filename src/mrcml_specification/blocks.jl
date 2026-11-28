# Build xi_model = xi0_model + J_model * eta in declared block order.
# q/raw, eta/free, and reconstructed model ranges have separate cursors.
# Helpers append to local buffers/receipts and return updated scalar cursors.

function _build_mrcml_facet_layout!(inputs)
    (;
        P, f_info, random_effects, lltm_nt, steps, int_specs, fixed_facets, groups, group_receipt,
        group_dimensions, default_prior, is_bayesian, prior_sd, raw, n,
    ) = inputs

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
        is_random = haskey(random_effects, fname)
        is_random && (has_lltm || fname in (steps isa Tuple ? steps : (steps,)) ||
            any(x -> x.f1 === fname || x.f2 === fname, int_specs)) &&
            throw(ArgumentError("an iid shared facet cannot also own thresholds, LLTM terms, or fixed interactions"))
        if !has_lltm
            values_f = get(fixed_facets, fname, nothing)
            facet_groups = filter(g -> g.block === fname, groups)
            grouped = !isempty(facet_groups)
            is_random && (grouped || values_f !== nothing) &&
                throw(ArgumentError("iid shared effects cannot be fixed calibration anchors"))
            base_f, C_f, free_labels = is_random ?
                (zeros(L_f), Matrix{Float64}(I,L_f,L_f), fb.levels) : grouped ?
                _subset_calibration_block(fb.levels, values_f, facet_groups, fname, group_receipt) :
                _calibration_block(fb.levels, values_f, false, fname)
            d_f = size(C_f,2)
            grouped && push!(group_dimensions,(;block=fname,n_levels=L_f,
                constraint_rank=L_f-d_f,free_locations=d_f))
            f_prior = if is_random
                _parse_scale_or_lognormal(random_effects[fname], true, fname)
            elseif default_prior
                (; kind = :fixed, sd = d_f > 0 ? 1.0 : 0.0, logmean = 0.0, logsd = 1.0)
            elseif is_bayesian
                hasproperty(prior_sd.facets, fname) ||
                    throw(ArgumentError("prior_sd.facets is missing entry for facet $(repr(fname))"))
                _parse_scale_or_lognormal(getproperty(prior_sd.facets, fname), d_f > 0, fname)
            else
                (; kind = :fixed, sd = L_f > 1 ? 1.0 : 0.0, logmean = 0.0, logsd = 1.0)
            end
            iso = is_random || grouped || !isnothing(values_f) ? 1.0 : L_f > 1 ? sqrt(L_f / (L_f - 1)) : 0.0
            erng = (eta_cursor + 1):(eta_cursor + d_f)
            mrng = (mod_cursor + 1):(mod_cursor + L_f)
            rrng = (raw_cursor + 1):(raw_cursor + d_f)
            for c in 1:d_f, r in 1:L_f
                v = C_f[r, c]
                v == 0.0 && continue
                push!(J_rows, mod_cursor + r); push!(J_cols, eta_cursor + c); push!(J_vals, v)
            end
            append!(xi0_model, base_f)
            append!(free_names, !is_random && (grouped || isnothing(values_f)) ? ["$(fname).contrast[$c]" for c in 1:d_f] :
                ["$(fname)[$level]" for level in free_labels])
            mnames_f = ["$(fname)[$(repr(x))]" for x in fb.levels]
            append!(model_names, mnames_f)
            union!(fixed_model_names, mnames_f[vec(all(iszero,C_f; dims=2))])

            push!(af_blocks, Block(fname, fb.column, deepcopy(fb.levels), copy(fb.index), f_prior.sd, f_prior.sd * iso, rrng))
            push!(block_meta, (; name = fname, kind = :facet_main, iid_population = is_random, levels = deepcopy(fb.levels),
                estimated_sd = f_prior.kind !== :fixed,
                eta_range = erng, model_range = mrng, check_exchangeable_symmetry = !grouped))
            if is_bayesian && d_f > 0
                push!(pending_blocks, (;
                    name = fname,
                    kind = _block_kind_from_scale(f_prior.kind),
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
            if is_bayesian && !default_prior && hasproperty(prior_sd.facets, fname) && !has_res
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
                        kind = _block_kind_from_scale(r_prior.kind),
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

    return (;
        J_rows, J_cols, J_vals, xi0_model, free_names, model_names, fixed_model_names, block_meta,
        af_blocks, raw_cursor, eta_cursor, mod_cursor, pending_blocks, facet_mod_ranges,
    )
end

function _append_mrcml_steps!(layout, inputs)
    (;
        J_rows, J_cols, J_vals, xi0_model, free_names, model_names, fixed_model_names, block_meta,
        af_blocks, raw_cursor, eta_cursor, mod_cursor, pending_blocks, facet_mod_ranges,
    ) = layout
    (;
        supports, categories, fixed_steps, group_levels, default_prior, is_bayesian, prior_sd,
        fixed_calibration,
    ) = inputs

    # 2) Baseline step blocks (one zero-sum step vector per group in `group_levels`)
    hs = length.(supports) .- 1
    step_blocks = [_calibration_block(categories[sup][2:end], get(fixed_steps, group_levels[g], nothing),
        true, "steps for $(repr(group_levels[g]))") for (g,sup) in enumerate(supports)]
    any_active_step = any(b -> size(b[2], 2) > 0, step_blocks)
    step_p = if default_prior
        (; kind = :fixed, sd = any_active_step ? 1.0 : 0.0, logmean = 0.0, logsd = 1.0)
    elseif is_bayesian
        _parse_scale_or_lognormal(prior_sd.step, any_active_step, :step_sd)
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
                kind = _block_kind_from_scale(step_p.kind),
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

    return merge(layout, (;
        raw_cursor, eta_cursor, mod_cursor, hs, step_mod_ranges,
    ))
end

function _append_mrcml_interactions!(layout, inputs)
    (;
        J_rows, J_cols, J_vals, xi0_model, free_names, model_names, fixed_model_names, block_meta,
        af_blocks, raw_cursor, eta_cursor, mod_cursor, pending_blocks, facet_mod_ranges, hs,
    ) = layout
    (;
        int_specs, role_lookup, cells, cell_anchors, cell_dimensions, is_bayesian, f_lookup,
    ) = inputs

    # 3) Structured 2-way interactions (`facet × facet`, `focal_dff`, and `facet × step`)
    int_model_records = NamedTuple[]
    for ispec in int_specs
        if ispec.kind === :facet_facet
            b1 = role_lookup[ispec.f1]
            b2 = role_lookup[ispec.f2]
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
                    throw(ArgumentError("Bayesian interaction ($(ispec.f1), $(ispec.f2)) requires an explicit prior SD or hyperprior (`truncated(Normal(0, s), 0, Inf)`, `truncated(LocationScale(0, s, TDist(df)), 0, Inf)`, or `LogNormal(mu, sd)`) in `prior_sd.interactions` or inline (`(f1, f2) => prior`)"))
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
                    kind = _block_kind_from_scale(ip.kind),
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
        elseif ispec.kind === :focal_dff
            b1 = role_lookup[ispec.f1]
            b2 = role_lookup[ispec.f2]
            length(b2.levels) >= 2 ||
                throw(ArgumentError("focal DFF interaction ($(ispec.f1), $(ispec.f2)) requires >= 2 group levels"))
            ref_lvl = something(ispec.reference, get(b2, :reference, nothing), first(b2.levels))
            any(x -> isequal(x, ref_lvl), b2.levels) ||
                throw(ArgumentError("unknown focal DFF reference level $(repr(ref_lvl)) for $(ispec.f2); available: $(b2.levels)"))
            cmp_groups = [g for g in b2.levels if !isequal(g, ref_lvl)]
            raw_foc = (ispec.focal isa Union{AbstractVector, Tuple} && !(ispec.focal isa AbstractString)) ?
                collect(ispec.focal) : [ispec.focal]
            !isempty(raw_foc) || throw(ArgumentError("focal DFF `focal` levels cannot be empty"))
            foc_idx = Int[]
            for fv in raw_foc
                fi = findfirst(x -> isequal(x, fv), b1.levels)
                fi === nothing && throw(ArgumentError("unknown focal level $(repr(fv)) for $(ispec.f1); available: $(b1.levels)"))
                push!(foc_idx, fi)
            end
            allunique(foc_idx) || throw(ArgumentError("duplicate focal levels in $(repr(raw_foc))"))
            length(foc_idx) < length(b1.levels) ||
                throw(ArgumentError("focal split-level DFF cannot split all $(length(b1.levels)) levels of $(ispec.f1) simultaneously (leaves zero invariant anchor levels); leave at least one anchor level invariant or use doubly centered `interactions = (($(repr(ispec.f1)), $(repr(ispec.f2))),)`"))
            focal_levels = [b1.levels[fi] for fi in foc_idx]
            d_foc = length(foc_idx) * length(cmp_groups)
            erng = (eta_cursor + 1):(eta_cursor + d_foc)
            mrng = (mod_cursor + 1):(mod_cursor + d_foc)
            rrng = (raw_cursor + 1):(raw_cursor + d_foc)
            for c in 1:d_foc
                push!(J_rows, mod_cursor + c); push!(J_cols, eta_cursor + c); push!(J_vals, 1.0)
            end
            append!(xi0_model, zeros(Float64, d_foc))
            fnames_foc = ["focal_dff[$(ispec.f1)=$(repr(fl)),$(ispec.f2)=$(repr(gl))]"
                for fl in focal_levels for gl in cmp_groups]
            append!(free_names, fnames_foc)
            append!(model_names, fnames_foc)
            if is_bayesian
                ispec.prior !== nothing ||
                    throw(ArgumentError("Bayesian focal DFF interaction ($(ispec.f1), $(ispec.f2)) requires an explicit `prior` (e.g. `Normal(0, 1.0)`, `1.0`, `truncated(Normal(0, s), 0, Inf)`, or `truncated(LocationScale(0, s, TDist(df)), 0, Inf)`)"))
                if ispec.prior isa D.Normal
                    np = _normal_parameters(ispec.prior, string(ispec.key))
                    push!(pending_blocks, (;
                        name = ispec.key, kind = :white_scaled,
                        eta_range = erng, model_range = mrng, raw_range = rrng,
                        mu = fill(np.mean, d_foc), scale_vec = fill(np.sd, d_foc),
                        chol_L = zeros(Float64, 0, 0), iso_factor = 1.0, marginal_sd = np.sd,
                        logmean = 0.0, logsd = 1.0,
                    ))
                else
                    ip = _parse_scale_or_lognormal(ispec.prior, true, ispec.key)
                    push!(pending_blocks, (;
                        name = ispec.key, kind = _block_kind_from_scale(ip.kind),
                        eta_range = erng, model_range = mrng, raw_range = rrng,
                        mu = zeros(Float64, d_foc), scale_vec = fill(ip.sd, d_foc),
                        chol_L = zeros(Float64, 0, 0), iso_factor = 1.0, marginal_sd = ip.sd,
                        logmean = ip.logmean, logsd = ip.logsd,
                    ))
                end
            end
            push!(block_meta, (; name = ispec.key, kind = :focal_dff_interaction,
                f1 = ispec.f1, f2 = ispec.f2,
                focal_levels = deepcopy(focal_levels),
                compare_groups = deepcopy(cmp_groups),
                reference_group = deepcopy(ref_lvl),
                levels1 = deepcopy(b1.levels), levels2 = deepcopy(b2.levels),
                eta_range = erng, model_range = mrng, check_exchangeable_symmetry = false))
            foc_map = Dict{Int,Int}(fi => k for (k, fi) in enumerate(foc_idx))
            grp_map = Dict{Int,Int}(only(findall(x -> isequal(x, gl), b2.levels)) => k for (k, gl) in enumerate(cmp_groups))
            push!(int_model_records, (; kind = :focal_dff, f1 = ispec.f1, f2 = ispec.f2,
                foc_map, grp_map, n_cmp = length(cmp_groups),
                idx1 = b1.index, idx2 = b2.index, model_range = mrng))
            eta_cursor += d_foc
            mod_cursor += d_foc
            raw_cursor += d_foc
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
                    throw(ArgumentError("Bayesian step interaction ($(ispec.f1), :step) requires an explicit prior SD or hyperprior (`truncated(Normal(0, s), 0, Inf)`, `truncated(LocationScale(0, s, TDist(df)), 0, Inf)`, or `LogNormal(mu, sd)`) in `prior_sd.interactions` or inline (`(f1, :step) => prior`)"))
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
                    kind = _block_kind_from_scale(ip.kind),
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

    return merge(layout, (;
        raw_cursor, eta_cursor, mod_cursor, int_model_records,
    ))
end
