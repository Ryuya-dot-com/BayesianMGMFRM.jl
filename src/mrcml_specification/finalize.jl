# Complete priors before constructing the compressed response operator.
# These operations preserve free-coordinate order and saved specification fields.

function _complete_mrcml_prior_layout!(layout, inputs)
    (;
        J_rows, J_cols, J_vals, xi0_model, free_names, model_names, fixed_model_names, block_meta,
        af_blocks, raw_cursor, eta_cursor, mod_cursor, pending_blocks, facet_mod_ranges,
    ) = layout
    (;
        intercept, transfer, group_levels, supports, categories, is_bayesian, p_is_hyper,
    ) = inputs

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
        if _is_hierarchical_kind(pb.kind)
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

    return merge(layout, (;
        raw_cursor, eta_cursor, mod_cursor, external_columns, p_hyper_idx, final_prior_blocks,
        J_model,
    ))
end

function _build_mrcml_response_operator(inputs, layout)
    (;
        n, group, supports, f_info, intercept,
    ) = inputs
    (;
        facet_mod_ranges, step_mod_ranges, int_model_records, mod_cursor, xi0_model, J_model,
        free_names, model_names, fixed_model_names, block_meta,
    ) = layout

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
            elseif irec.kind === :focal_dff
                fk = get(irec.foc_map, irec.idx1[i], 0)
                gk = get(irec.grp_map, irec.idx2[i], 0)
                if fk > 0 && gk > 0
                    cell_col = irec.model_range[(fk - 1) * irec.n_cmp + gk]
                    for lk in 2:M_g
                        push!(ents, (lk, cell_col, -Float64(lk - 1)))
                    end
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

    return op
end

function _finish_structured_mrcml(inputs, layout, op)
    (;
        person, score, facets, steps, prior_sd, default_prior, category_levels, interactions,
        random_effects, lltm, fixed_calibration, intercept, performance, assessment, missing_audit,
        is_bayesian, lltm_nt, raw, n, p_idx, p_levels, P, p_sd_val, p_logmean, p_logsd,
        p_scale_kind, p_is_hyper, f_info, f_lookup, c_info, role_lookup, owner_sym, group,
        group_levels, cat, categories, supports, transfer, fixed_facets, groups, group_receipt,
        group_dimensions, fixed_steps, int_specs, cells, cell_anchors, cell_dimensions,
    ) = inputs
    (;
        af_blocks, block_meta, p_hyper_idx, final_prior_blocks, external_columns, raw_cursor,
    ) = layout

    columns = (; person, score, facets, performance, assessment)
    grouping = _groups(raw, columns, p_idx, af_blocks)
    category_levels isa AbstractDict && (grouping = merge(grouping, (; category_support_by_owner = true)))

    # If any LLTM block has `center = false`, its uncentered column spans the global intercept -> `:zero_mean_population`
    has_uncentered_lltm = any(bm -> bm.kind === :lltm_weights && !bm.centered, block_meta)
    loc_mode = has_uncentered_lltm || !isnothing(intercept) ? :zero_mean_population : :finite_connected
    n_hyp = (p_hyper_idx > 0 ? 1 : 0) + count(b -> b.hyper_idx > 0, final_prior_blocks)

    alloc = _mrcml_allocation(p_idx, p_levels, af_blocks, op, loc_mode; n_hyper = n_hyp, external_columns, person_estimated=p_hyper_idx>0)
    spec_rec = (; source = :structured_mfrm_spec, steps, has_interactions = interactions !== nothing, has_lltm = lltm !== nothing,
        (default_prior ? (; default_prior = true) : (;))...,
        (isempty(random_effects) ? (;) : (;random_effects=collect(keys(random_effects))))...,
        (p_scale_kind in (:half_normal, :half_student_t) ? (; person_scale_prior = (; kind = p_scale_kind, p1 = p_logmean, p2 = p_logsd)) : (;))...,
        (isempty(c_info) ? (;) : (; context_facets = [(; c.name, levels = deepcopy(c.levels), index = copy(c.index), c.reference) for c in c_info]))...,
        (missing_audit === nothing ? (;) : (; missing_audit = deepcopy(missing_audit)))...)

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
    elseif !isnothing(intercept)
        spec_rec = merge(spec_rec, (; population_intercept = true))
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
    )end
