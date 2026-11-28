# Practitioner-facing Fair Average Score & Pair-Level Residual / DFF Bias Reports
# Included inside `module AdditiveFacets`.

const FAIR_AVERAGE_SCHEMA = "bayesianmgmfrm.mrcml_fair_average.v1"
const PAIR_BIAS_SCHEMA = "bayesianmgmfrm.mrcml_pair_bias.v1"
const RESIDUAL_CORR_SCHEMA = "bayesianmgmfrm.mrcml_residual_correlation.v1"

@inline function _adjacent_expected_score(
        eta::Float64,
        steps_vec::AbstractVector{<:Real},
        cat_vals::AbstractVector{<:Real})
    M = length(cat_vals)
    H = length(steps_vec)
    H == M - 1 || throw(DimensionMismatch("steps_vec length ($H) must equal length(cat_vals) - 1 ($(M - 1))"))
    mmax = 0.0
    csum_tau = 0.0
    for lk in 2:M
        csum_tau += Float64(steps_vec[lk - 1])
        v = Float64(lk - 1) * eta - csum_tau
        v > mmax && (mmax = v)
    end
    wsum = exp(-mmax)
    esum = Float64(cat_vals[1]) * wsum
    csum_tau = 0.0
    for lk in 2:M
        csum_tau += Float64(steps_vec[lk - 1])
        v = Float64(lk - 1) * eta - csum_tau
        w = exp(v - mmax)
        wsum += w
        esum += Float64(cat_vals[lk]) * w
    end
    return esum / wsum
end

function _mrcml_fair_average(
        t::AbstractTarget,
        f::Fit;
        by::Symbol = :rater,
        level::Real = 0.95,
        baseline::Symbol = :sample_mean,
        step_group = nothing)
    t isa MRCMLTarget || throw(ArgumentError(
        "Fair Average Score (`diagnostics(fit; kind = :fair_average)`) requires an MRCMLTarget fit; got $(typeof(t))"))
    lo, hi = interval_bounds(level)
    baseline in (:sample_mean, :zero_origin) || throw(ArgumentError(
        "baseline must be :sample_mean (FACETS Fair-M) or :zero_origin (FACETS Fair-Z); got $(repr(baseline))"))

    op = t.operator
    step_bms = [bm for bm in op.block_meta if bm.kind === :steps]
    !isempty(step_bms) && length(step_bms) == length(t.supports) || throw(ArgumentError(
        "Fair Average Score requires structured step blocks matching category supports; custom unstructured design matrices without step block metadata are not supported"))

    facet_bms = Dict{Symbol, NamedTuple}()
    pop_mean_mrng = nothing
    step_int_bms = Dict{Symbol, NamedTuple}()
    for bm in op.block_meta
        if bm.kind in (:facet_main, :facet_lltm_strict, :facet_lltm_plus_residual)
            facet_bms[bm.name] = bm
        elseif bm.kind === :population_mean
            pop_mean_mrng = bm.model_range
        elseif bm.kind === :facet_step_interaction
            step_int_bms[bm.f1] = bm
        end
    end

    by_sym = by === :entity ? :person : by
    is_person = by_sym === :person
    if !is_person
        haskey(facet_bms, by_sym) || throw(ArgumentError(
            "unknown `by = $(repr(by))` facet for Fair Average Score; available: :person, $(Tuple(keys(facet_bms)))"))
    end

    mixed = _owned_support(t)
    chosen_g = nothing
    if step_group !== nothing
        gi = findfirst(gl -> isequal(gl, step_group) || string(gl) == string(step_group), t.group_levels)
        gi === nothing && throw(ArgumentError(
            "unknown `step_group = $(repr(step_group))`; available step groups: $(t.group_levels)"))
        chosen_g = gi
    elseif mixed && by_sym !== t.owner
        throw(ArgumentError(
            "Fair Average Score for `by = $(repr(by_sym))` under mixed category supports requires an explicit `step_group = ...` (available: $(t.group_levels)) because raw scores across unequal category ranges are not commensurable; or inspect `by = $(repr(t.owner))`."))
    end

    levs, idx_vec = if is_person
        (t.people, t.person)
    else
        fb = t.facets[only(findall(b -> b.name === by_sym, t.facets))]
        (fb.levels, fb.index)
    end
    L = length(levs)
    P = length(t.people)
    draws = f.record.run.draws
    S_draws = size(draws, 1)
    chains = f.record.run.controls.chains

    # Unpack posterior draws of person locations and model-scale structural parameters
    th_draws = Matrix{Float64}(undef, S_draws, P)
    xi_draws = Matrix{Float64}(undef, S_draws, length(op.model_names))
    for s in 1:S_draws
        u = _mrcml_unpack(t, view(draws, s, :))
        th_draws[s, :] .= u.person
        xi_draws[s, :] .= u.xi_model
    end

    focal_logit_draws = Matrix{Float64}(undef, S_draws, L)
    fair_draws = Matrix{Float64}(undef, S_draws, L)
    eta_eff_draws = Matrix{Float64}(undef, S_draws, L)

    G_step = length(step_bms)
    has_focal_step_int = !is_person && haskey(step_int_bms, by_sym)
    sibm = has_focal_step_int ? step_int_bms[by_sym] : nothing

    for s in 1:S_draws
        mu_int = pop_mean_mrng === nothing ? 0.0 : xi_draws[s, first(pop_mean_mrng)]
        person_cohort_base = baseline === :sample_mean ?
            (mu_int + mean(view(th_draws, s, :))) : mu_int

        other_facet_shift = 0.0
        if baseline === :sample_mean
            for (fn, fbm) in facet_bms
                (!is_person && fn === by_sym) && continue
                other_facet_shift += mean(view(xi_draws, s, fbm.model_range))
            end
        end

        for j in 1:L
            if is_person
                f_logit = th_draws[s, j]
                eta_j = (th_draws[s, j] + mu_int) - other_facet_shift
            else
                fbm = facet_bms[by_sym]
                f_logit = xi_draws[s, fbm.model_range[j]]
                eta_j = person_cohort_base - f_logit - other_facet_shift
            end
            focal_logit_draws[s, j] = f_logit
            eta_eff_draws[s, j] = eta_j

            if chosen_g !== nothing
                sup = t.supports[chosen_g]
                c_vals = view(t.categories, sup)
                H = length(sup) - 1
                s_mrng = step_bms[chosen_g].model_range
                tau_vec = [xi_draws[s, s_mrng[h]] +
                    (has_focal_step_int ? xi_draws[s, sibm.model_range[(j - 1) * H + h]] : 0.0)
                    for h in 1:H]
                fair_draws[s, j] = _adjacent_expected_score(eta_j, tau_vec, c_vals)
            elseif !is_person && by_sym === t.owner
                sup = t.supports[j]
                c_vals = view(t.categories, sup)
                H = length(sup) - 1
                s_mrng = step_bms[j].model_range
                tau_vec = [xi_draws[s, s_mrng[h]] +
                    (has_focal_step_int ? xi_draws[s, sibm.model_range[(j - 1) * H + h]] : 0.0)
                    for h in 1:H]
                fair_draws[s, j] = _adjacent_expected_score(eta_j, tau_vec, c_vals)
            else
                # Uniform category support across all step groups: average step profile
                sup = t.supports[1]
                c_vals = view(t.categories, sup)
                H = length(sup) - 1
                tau_vec = zeros(Float64, H)
                for g in 1:G_step
                    s_mrng = step_bms[g].model_range
                    for h in 1:H
                        tau_vec[h] += xi_draws[s, s_mrng[h]]
                    end
                end
                tau_vec ./= Float64(G_step)
                if has_focal_step_int
                    for h in 1:H
                        tau_vec[h] += xi_draws[s, sibm.model_range[(j - 1) * H + h]]
                    end
                end
                fair_draws[s, j] = _adjacent_expected_score(eta_j, tau_vec, c_vals)
            end
        end
    end

    # Compute posterior-mean plug-in Fair Average for explicit Jensen/shrinkage comparison
    xi_mean = vec(mean(xi_draws; dims = 1))
    eta_mean = vec(mean(eta_eff_draws; dims = 1))
    pnames = ["$(by_sym)[$(repr(levs[j]))]" for j in 1:L]
    mc_fair = B._posterior_mcse_rows(fair_draws, pnames, chains;
        probabilities = (lo, hi), parameter_space = :expected_category_score)

    rows = map(1:L) do j
        obs_ix = findall(==(j), idx_vec)
        n_obs_j = length(obs_ix)
        same_sup = !isempty(obs_ix) && allequal(t.supports[t.group[n]] for n in obs_ix)
        obs_avg = same_sup ? mean(Float64(t.categories[t.category[n]]) for n in obs_ix) : missing

        g_ref = chosen_g !== nothing ? chosen_g : ((!is_person && by_sym === t.owner) ? j : 1)
        sup_j = t.supports[g_ref]
        c_vals_j = view(t.categories, sup_j)
        H_j = length(sup_j) - 1
        tau_plug = if chosen_g !== nothing || (!is_person && by_sym === t.owner)
            s_mrng = step_bms[g_ref].model_range
            [xi_mean[s_mrng[h]] + (has_focal_step_int ? xi_mean[sibm.model_range[(j - 1) * H_j + h]] : 0.0)
                for h in 1:H_j]
        else
            tv = [mean(xi_mean[step_bms[g].model_range[h]] for g in 1:G_step) for h in 1:H_j]
            if has_focal_step_int
                for h in 1:H_j
                    tv[h] += xi_mean[sibm.model_range[(j - 1) * H_j + h]]
                end
            end
            tv
        end
        plug_fa = _adjacent_expected_score(eta_mean[j], tau_plug, c_vals_j)

        fv = view(fair_draws, :, j)
        lv = view(focal_logit_draws, :, j)
        mc_j = mc_fair[j]
        (;
            parameter = pnames[j],
            level = levs[j],
            n_observations = n_obs_j,
            observed_average = obs_avg,
            logit_mean = mean(lv),
            logit_median = median(lv),
            logit_sd = std(lv),
            logit_lower = quantile(lv, lo),
            logit_upper = quantile(lv, hi),
            fair_average_mean = mean(fv),
            fair_average_median = median(fv),
            fair_average_sd = std(fv),
            fair_average_lower = quantile(fv, lo),
            fair_average_upper = quantile(fv, hi),
            fair_average_mcse_mean = mc_j.mean_mcse,
            fair_average_mcse_lower = mc_j.quantiles[1].mcse,
            fair_average_mcse_upper = mc_j.quantiles[2].mcse,
            plugin_fair_average = plug_fa,
            min_category = Int(first(c_vals_j)),
            max_category = Int(last(c_vals_j)),
        )
    end

    return (;
        schema = FAIR_AVERAGE_SCHEMA,
        kind = :fair_average,
        by = by_sym,
        baseline,
        step_group = chosen_g === nothing ? (by_sym === t.owner ? :own_step_group : :mean_step_profile) : t.group_levels[chosen_g],
        level = Float64(level),
        n_levels = L,
        n_draws = S_draws,
        orientation_note = is_person ?
            "Higher person ability logits map to higher Fair Average scores." :
            "Higher facet severity/difficulty logits map to LOWER Fair Average scores at fixed reference ability and other-facet means.",
        plugin_note = "fair_average_mean integrates over full joint posterior uncertainty; plugin_fair_average substitutes posterior-mean parameters.",
        rows,
        qualification = qualify(f),
        source_sample_content_hash = f.record.content_hash,
    )
end

function _resolve_pair_role(t::MRCMLTarget, r::Symbol)
    r_norm = r === :entity ? :person : r
    r_norm === :person && return (:person, t.person, t.people)
    bi = findfirst(b -> b.name === r_norm, t.facets)
    if bi !== nothing
        fb = t.facets[bi]
        return (fb.name, fb.index, fb.levels)
    end
    if hasproperty(t.spec_record, :context_facets)
        ci = findfirst(c -> c.name === r_norm, t.spec_record.context_facets)
        if ci !== nothing
            cf = t.spec_record.context_facets[ci]
            return (cf.name, cf.index, cf.levels)
        end
    end
    if hasproperty(t.spec_record, :population)
        pop = t.spec_record.population
        if r_norm === pop.group_column || r_norm === :group
            obs_gidx = Int[pop.group_index[p] for p in t.person]
            return (pop.group_column, obs_gidx, pop.groups)
        end
    end
    avail = Any[:person, (b.name for b in t.facets)...]
    hasproperty(t.spec_record, :population) && push!(avail, t.spec_record.population.group_column)
    throw(ArgumentError("unknown role $(repr(r)) in `pair`; available: $(Tuple(unique(avail)))"))
end

function _mrcml_pair_bias(
        t::AbstractTarget,
        f::Fit;
        pair = nothing,
        level::Real = 0.95,
        min_obs::Integer = 1)
    t isa MRCMLTarget || throw(ArgumentError(
        "Pair-level DFF / residual bias table (`diagnostics(fit; kind = :pair_bias)`) requires an MRCMLTarget fit; got $(typeof(t))"))
    lo, hi = interval_bounds(level)
    min_obs isa Integer && !(min_obs isa Bool) && min_obs >= 1 ||
        throw(ArgumentError("min_obs must be a positive integer"))

    fnames = [b.name for b in t.facets]
    raw_pair = if pair === nothing
        (:rater in fnames && :item in fnames) ? (:rater, :item) :
            length(fnames) >= 2 ? (fnames[1], fnames[2]) : (:person, fnames[1])
    else
        pair isa Tuple && length(pair) == 2 && all(x -> x isa Symbol, pair) ||
            throw(ArgumentError("pair must be a 2-Tuple of Symbols such as `(:rater, :item)`; got $(repr(pair))"))
        pair
    end

    r1, idx1, levs1 = _resolve_pair_role(t, raw_pair[1])
    r2, idx2, levs2 = _resolve_pair_role(t, raw_pair[2])
    r1 != r2 || throw(ArgumentError("pair roles must be distinct; got ($r1, $r2)"))

    op = t.operator
    # Check whether this exact pair was jointly modeled as a 2-way or focal DFF interaction block!
    joint_bm = nothing
    joint_flipped = false
    for bm in op.block_meta
        if bm.kind in (:facet_facet_interaction, :focal_dff_interaction)
            if bm.f1 === r1 && bm.f2 === r2
                joint_bm = bm
                joint_flipped = false
                break
            elseif bm.f1 === r2 && bm.f2 === r1
                joint_bm = bm
                joint_flipped = true
                break
            end
        end
    end
    analysis_mode = joint_bm === nothing ? :secondary_residual_screen :
        (joint_bm.kind === :focal_dff_interaction ? :focal_dff_model : :joint_interaction_model)

    # Group observation indices by observed (i1, i2) cell
    cell_obs = Dict{Tuple{Int,Int}, Vector{Int}}()
    for n in 1:op.n_obs
        key = (idx1[n], idx2[n])
        push!(get!(cell_obs, key, Int[]), n)
    end
    cell_keys = sort!([k for (k, ns) in cell_obs if length(ns) >= min_obs])
    C_cells = length(cell_keys)

    draws = f.record.run.draws
    S_draws = size(draws, 1)
    chains = f.record.run.controls.chains
    P = length(t.people)

    th_draws = Matrix{Float64}(undef, S_draws, P)
    vp_draws = Matrix{Float64}(undef, S_draws, length(op.c_pat))
    vp_main_draws = joint_bm === nothing ? Matrix{Float64}(undef, 0, 0) : Matrix{Float64}(undef, S_draws, length(op.c_pat))
    joint_gamma_draws = joint_bm === nothing ? Matrix{Float64}(undef, 0, 0) : Matrix{Float64}(undef, S_draws, C_cells)

    for s in 1:S_draws
        u = _mrcml_unpack(t, view(draws, s, :))
        th_draws[s, :] .= u.person
        vp_draws[s, :] .= _mrcml_pattern_shifts(op, u.eta_xi)
        if joint_bm !== nothing
            eta_no_int = copy(u.eta_xi)
            eta_no_int[joint_bm.eta_range] .= 0.0
            vp_main_draws[s, :] .= _mrcml_pattern_shifts(op, eta_no_int)
            if joint_bm.kind === :facet_facet_interaction
                L2_bm = length(joint_bm.levels2)
                for (c_idx, (i1, i2)) in enumerate(cell_keys)
                    b_i1, b_i2 = joint_flipped ? (i2, i1) : (i1, i2)
                    mcol = joint_bm.model_range[(b_i1 - 1) * L2_bm + b_i2]
                    joint_gamma_draws[s, c_idx] = u.xi_model[mcol]
                end
            else
                n_cmp_bm = length(joint_bm.compare_groups)
                for (c_idx, (i1, i2)) in enumerate(cell_keys)
                    b_i1, b_i2 = joint_flipped ? (i2, i1) : (i1, i2)
                    fl_v = joint_bm.levels1[b_i1]
                    gl_v = joint_bm.levels2[b_i2]
                    fk = findfirst(x -> isequal(x, fl_v), joint_bm.focal_levels)
                    gk = findfirst(x -> isequal(x, gl_v), joint_bm.compare_groups)
                    joint_gamma_draws[s, c_idx] = (fk !== nothing && gk !== nothing) ?
                        u.xi_model[joint_bm.model_range[(fk - 1) * n_cmp_bm + gk]] : 0.0
                end
            end
        end
    end

    if C_cells == 0
        return (;
            schema = PAIR_BIAS_SCHEMA,
            kind = :pair_bias,
            analysis_mode,
            pair = (r1, r2),
            level = Float64(level),
            min_obs = Int(min_obs),
            n_cells = 0,
            n_draws = S_draws,
            rows = NamedTuple[],
            qualification = qualify(f),
            source_sample_content_hash = f.record.content_hash,
        )
    end

    y_actual = [Float64(t.categories[t.category[n]]) for n in 1:op.n_obs]
    cell_obs_sum = [sum(y_actual[n] for n in cell_obs[k]) for k in cell_keys]
    cell_same_sup = [allequal(t.supports[t.group[n]] for n in cell_obs[k]) for k in cell_keys]

    exp_mean_mat = fill(NaN, S_draws, C_cells)
    main_exp_mean_mat = joint_bm === nothing ? Matrix{Float64}(undef, 0, 0) : fill(NaN, S_draws, C_cells)
    resid_mean_mat = fill(NaN, S_draws, C_cells)
    approx_bias_mat = fill(NaN, S_draws, C_cells)
    z_resid_mat = fill(NaN, S_draws, C_cells)

    K_max = maximum(length, t.supports)
    lbuf = zeros(Float64, K_max)
    pbuf = zeros(Float64, K_max)

    @inline function _row_score_mean_var!(vp_row, n::Int, th::Float64)
        pat = op.pattern_of_row[n]
        prng = op.pattern_ranges[pat]
        sup = t.supports[t.group[n]]
        M_g = length(sup)
        mmax = -Inf
        @inbounds for lk in 1:M_g
            m = prng[lk]
            v = op.B_pat[m] * th + vp_row[m]
            lbuf[lk] = v
            v > mmax && (mmax = v)
        end
        ssum = 0.0
        @inbounds for lk in 1:M_g
            e = exp(lbuf[lk] - mmax)
            pbuf[lk] = e
            ssum += e
        end
        inv_s = 1.0 / ssum
        es = 0.0
        @inbounds for lk in 1:M_g
            pk = pbuf[lk] * inv_s
            pbuf[lk] = pk
            es += pk * Float64(t.categories[sup[lk]])
        end
        vs = 0.0
        @inbounds for lk in 1:M_g
            d = Float64(t.categories[sup[lk]]) - es
            vs += pbuf[lk] * d * d
        end
        return es, vs
    end

    for s in 1:S_draws
        vp_s = view(vp_draws, s, :)
        vp_m = joint_bm === nothing ? vp_s : view(vp_main_draws, s, :)
        for (c_idx, k) in enumerate(cell_keys)
            ns = cell_obs[k]
            N_c = length(ns)
            esum = 0.0
            vsum = 0.0
            msum = 0.0
            for n in ns
                th = th_draws[s, t.person[n]]
                es, vs = _row_score_mean_var!(vp_s, n, th)
                esum += es
                vsum += vs
                if joint_bm !== nothing
                    es_m, _ = _row_score_mean_var!(vp_m, n, th)
                    msum += es_m
                end
            end
            diff_sum = cell_obs_sum[c_idx] - esum
            if cell_same_sup[c_idx]
                em = esum / N_c
                exp_mean_mat[s, c_idx] = em
                resid_mean_mat[s, c_idx] = (cell_obs_sum[c_idx] / N_c) - em
                if joint_bm !== nothing
                    main_exp_mean_mat[s, c_idx] = msum / N_c
                end
            end
            if vsum > 1e-14
                # Severity/difficulty sign convention: positive bias logit = cell scored LOWER (more severe/harder) than expected
                approx_bias_mat[s, c_idx] = -diff_sum / vsum
                z_resid_mat[s, c_idx] = diff_sum / sqrt(vsum)
            end
        end
    end

    cnames = ["pair[$r1=$(repr(levs1[i1])),$r2=$(repr(levs2[i2]))]" for (i1, i2) in cell_keys]
    mc_bias = B._posterior_mcse_rows(approx_bias_mat, cnames, chains;
        probabilities = (lo, hi), parameter_space = :approx_bias_logit)
    mc_joint = joint_bm === nothing ? nothing :
        B._posterior_mcse_rows(joint_gamma_draws, cnames, chains;
            probabilities = (lo, hi), parameter_space = :interaction_logit)

    rows = map(1:C_cells) do c_idx
        i1, i2 = cell_keys[c_idx]
        ns = cell_obs[(i1, i2)]
        N_c = length(ns)
        same_s = cell_same_sup[c_idx]
        obs_sum = same_s ? cell_obs_sum[c_idx] : missing
        obs_mean = same_s ? (cell_obs_sum[c_idx] / N_c) : missing

        ev = view(exp_mean_mat, :, c_idx)
        rv = view(resid_mean_mat, :, c_idx)
        bv = view(approx_bias_mat, :, c_idx)
        zv = view(z_resid_mat, :, c_idx)
        valid_b = all(isfinite, bv)

        exp_fields = same_s && all(isfinite, ev) ? (;
            expected_score_mean = mean(ev),
            expected_score_lower = quantile(ev, lo),
            expected_score_upper = quantile(ev, hi),
            baseline_main_effects_expected_mean = joint_bm === nothing ? missing : mean(view(main_exp_mean_mat, :, c_idx)),
            score_residual_mean = mean(rv),
            score_residual_lower = quantile(rv, lo),
            score_residual_upper = quantile(rv, hi),
            prob_score_residual_gt_0 = mean(rv .> 0.0),
            prob_score_residual_lt_0 = mean(rv .< 0.0),
        ) : (;
            expected_score_mean = missing,
            expected_score_lower = missing,
            expected_score_upper = missing,
            baseline_main_effects_expected_mean = missing,
            score_residual_mean = missing,
            score_residual_lower = missing,
            score_residual_upper = missing,
            prob_score_residual_gt_0 = valid_b ? mean(zv .> 0.0) : missing,
            prob_score_residual_lt_0 = valid_b ? mean(zv .< 0.0) : missing,
        )

        bias_fields = valid_b ? (;
            approx_severity_bias_logit_mean = mean(bv),
            approx_severity_bias_logit_sd = std(bv),
            approx_severity_bias_logit_lower = quantile(bv, lo),
            approx_severity_bias_logit_upper = quantile(bv, hi),
            approx_severity_bias_logit_mcse = mc_bias[c_idx].mean_mcse,
            z_residual_mean = mean(zv),
            z_residual_lower = quantile(zv, lo),
            z_residual_upper = quantile(zv, hi),
        ) : (;
            approx_severity_bias_logit_mean = missing,
            approx_severity_bias_logit_sd = missing,
            approx_severity_bias_logit_lower = missing,
            approx_severity_bias_logit_upper = missing,
            approx_severity_bias_logit_mcse = missing,
            z_residual_mean = missing,
            z_residual_lower = missing,
            z_residual_upper = missing,
        )

        joint_fields = if joint_bm !== nothing
            gv = view(joint_gamma_draws, :, c_idx)
            mc_g = mc_joint[c_idx]
            (;
                joint_interaction_logit_mean = mean(gv),
                joint_interaction_logit_median = median(gv),
                joint_interaction_logit_sd = std(gv),
                joint_interaction_logit_lower = quantile(gv, lo),
                joint_interaction_logit_upper = quantile(gv, hi),
                joint_interaction_mcse_mean = mc_g.mean_mcse,
                joint_interaction_mcse_lower = mc_g.quantiles[1].mcse,
                joint_interaction_mcse_upper = mc_g.quantiles[2].mcse,
                prob_interaction_gt_0 = mean(gv .> 0.0),
                prob_interaction_lt_0 = mean(gv .< 0.0),
            )
        else
            (;
                joint_interaction_logit_mean = missing,
                joint_interaction_logit_median = missing,
                joint_interaction_logit_sd = missing,
                joint_interaction_logit_lower = missing,
                joint_interaction_logit_upper = missing,
                joint_interaction_mcse_mean = missing,
                joint_interaction_mcse_lower = missing,
                joint_interaction_mcse_upper = missing,
                prob_interaction_gt_0 = missing,
                prob_interaction_lt_0 = missing,
            )
        end

        merge(
            (;
                cell = cnames[c_idx],
                role_1 = r1,
                level_1 = levs1[i1],
                role_2 = r2,
                level_2 = levs2[i2],
                n_observations = N_c,
                observed_score_sum = obs_sum,
                observed_score_mean = obs_mean,
            ),
            exp_fields,
            bias_fields,
            joint_fields,
        )
    end

    interp = analysis_mode === :joint_interaction_model ?
        "Joint interaction model (`analysis_mode = :joint_interaction_model`): `joint_interaction_logit_*` summarizes posterior draws of the doubly centered Kronecker-Helmert interaction gamma[level_1, level_2] (+ > 0 means greater severity/difficulty, lowering scores), while `approx_severity_bias_logit_*` reflects only remaining post-interaction cell residuals." :
        analysis_mode === :focal_dff_model ?
        "Focal split-level DFF model (`analysis_mode = :focal_dff_model`): `joint_interaction_logit_*` summarizes posterior draws of focal differential severity relative to the invariant anchor panel (+ > 0 means greater severity/difficulty on the comparison group)." :
        "Secondary post-hoc residual screen (`analysis_mode = :secondary_residual_screen`): no interaction block for ($r1, $r2) was estimated in this fit. `score_residual_*` (obs - exp) and `approx_severity_bias_logit_*` (-(obs - exp)/info; + > 0 means cell scored lower / more severe than main-effects expectation) are exploratory Table-14-style screens conditional on main-effects draws and do NOT replace fitting an explicit `interactions = (($r1, $r2) => prior,)` model."

    return (;
        schema = PAIR_BIAS_SCHEMA,
        kind = :pair_bias,
        analysis_mode,
        pair = (r1, r2),
        level = Float64(level),
        min_obs = Int(min_obs),
        n_cells = C_cells,
        n_draws = S_draws,
        sign_convention = (;
            score_residual = "observed_score_mean - expected_score_mean (+ > 0 means higher observed score / more lenient)",
            severity_bias_and_interaction_logit = "+ > 0 means greater severity / difficulty (lower scores), matching MRCML facet sign convention",
        ),
        interpretation = interp,
        rows,
        qualification = qualify(f),
        source_sample_content_hash = f.record.content_hash,
    )
end

function _resolve_dff_linear_weights(
        op::MRCMLOperator,
        interaction;
        focal = nothing,
        level_1 = nothing,
        group,
        reference,
        estimand::Symbol = :vs_rest_of_panel)
    interaction isa Tuple && length(interaction) == 2 && all(x -> x isa Symbol, interaction) ||
        throw(ArgumentError("interaction must be a 2-Tuple of Symbols such as `(:rater, :group)`; got $(repr(interaction))"))
    estimand in (:vs_rest_of_panel, :panel_centered) ||
        throw(ArgumentError("estimand must be `:vs_rest_of_panel` or `:panel_centered`; got $(repr(estimand))"))
    (focal !== nothing && level_1 !== nothing) &&
        throw(ArgumentError("supply either `focal` or `level_1`, not both"))
    target_val = focal !== nothing ? focal : level_1

    r1, r2 = Symbol(interaction[1]), Symbol(interaction[2])
    bm_found = nothing
    flipped = false
    for bm in op.block_meta
        if bm.kind in (:facet_facet_interaction, :focal_dff_interaction)
            if bm.f1 === r1 && bm.f2 === r2
                bm_found = bm
                flipped = false
                break
            elseif bm.f1 === r2 && bm.f2 === r1
                bm_found = bm
                flipped = true
                break
            end
        end
    end
    bm_found === nothing && throw(ArgumentError(
        "no modeled interaction block found for ($r1, $r2) in operator block_meta"))

    levs_f = flipped ? bm_found.levels2 : bm_found.levels1
    levs_g = flipped ? bm_found.levels1 : bm_found.levels2
    ig_a = findfirst(x -> isequal(x, group), levs_g)
    ig_b = findfirst(x -> isequal(x, reference), levs_g)
    (ig_a !== nothing && ig_b !== nothing) ||
        throw(ArgumentError("unknown group/reference ($(repr(group)), $(repr(reference))) in $(levs_g)"))
    ig_a != ig_b || throw(ArgumentError("group and reference must be distinct levels"))

    g_a = levs_g[ig_a]
    g_b = levs_g[ig_b]
    n_mod = length(op.model_names)
    R_tot = length(levs_f)

    function _weights_for_level(if_idx::Int)
        fl = levs_f[if_idx]
        w = zeros(Float64, n_mod)
        if bm_found.kind === :focal_dff_interaction
            flipped && throw(ArgumentError("focal DFF interaction order must be `(facet, group)`"))
            fk = findfirst(x -> isequal(x, fl), bm_found.focal_levels)
            fk === nothing && throw(ArgumentError(
                "level $(repr(fl)) was held invariant (not in modeled focal_levels = $(bm_found.focal_levels))"))
            n_cmp = length(bm_found.compare_groups)
            sf = estimand === :vs_rest_of_panel ? 1.0 :
                (length(bm_found.focal_levels) == 1 && R_tot >= 2 ? Float64(R_tot - 1) / Float64(R_tot) :
                 throw(ArgumentError("panel_centered estimand on multi-focal split model is ambiguous; use estimand = :vs_rest_of_panel or doubly centered interactions")))
            if !isequal(g_a, bm_found.reference_group)
                gk_a = only(findall(x -> isequal(x, g_a), bm_found.compare_groups))
                w[bm_found.model_range[(fk - 1) * n_cmp + gk_a]] += sf
            end
            if !isequal(g_b, bm_found.reference_group)
                gk_b = only(findall(x -> isequal(x, g_b), bm_found.compare_groups))
                w[bm_found.model_range[(fk - 1) * n_cmp + gk_b]] -= sf
            end
            return (; target_level = fl, weights = w, scale_factor = sf, mode = :focal_split_rater)
        else
            R_tot >= 2 || throw(ArgumentError("DFF contrast requires at least 2 levels"))
            sf = estimand === :vs_rest_of_panel ? (Float64(R_tot) / Float64(R_tot - 1)) : 1.0
            L2_bm = length(bm_found.levels2)
            m_a = flipped ? bm_found.model_range[(ig_a - 1) * L2_bm + if_idx] :
                            bm_found.model_range[(if_idx - 1) * L2_bm + ig_a]
            m_b = flipped ? bm_found.model_range[(ig_b - 1) * L2_bm + if_idx] :
                            bm_found.model_range[(if_idx - 1) * L2_bm + ig_b]
            w[m_a] += sf
            w[m_b] -= sf
            return (; target_level = fl, weights = w, scale_factor = sf, mode = :doubly_centered_kronecker_helmert)
        end
    end

    if target_val !== nothing
        if_idx = findfirst(x -> isequal(x, target_val), levs_f)
        if_idx === nothing && throw(ArgumentError("unknown target level $(repr(target_val)) in $(levs_f)"))
        spec_1 = _weights_for_level(if_idx)
        return (; single = true, facet = r1, group_role = r2, group = g_a, reference = g_b,
                  estimand, entries = [spec_1])
    else
        idxs = bm_found.kind === :focal_dff_interaction ?
            [only(findall(x -> isequal(x, fl), levs_f)) for fl in bm_found.focal_levels] :
            collect(1:R_tot)
        return (; single = false, facet = r1, group_role = r2, group = g_a, reference = g_b,
                  estimand, entries = [_weights_for_level(i) for i in idxs])
    end
end

function _mrcml_dff_contrast(
        t::AbstractTarget,
        f::Fit;
        interaction,
        focal = nothing,
        level_1 = nothing,
        group,
        reference,
        estimand::Symbol = :vs_rest_of_panel,
        interval::Union{Nothing,Real} = nothing,
        level::Union{Nothing,Real} = nothing,
        rope = nothing)
    t isa MRCMLTarget || throw(ArgumentError("DFF interaction contrast requires an MRCMLTarget fit"))
    (interval !== nothing && level !== nothing) &&
        throw(ArgumentError("supply either `interval` or `level`, not both"))
    iv = Float64(something(interval, level, 0.95))
    interval_bounds(iv)

    resolved = _resolve_dff_linear_weights(
        t.operator, interaction; focal, level_1, group, reference, estimand,
    )
    draws = f.record.run.draws
    S_draws = size(draws, 1)
    chains = f.record.run.controls.chains
    n_mod = length(t.operator.model_names)
    xi_draws = Matrix{Float64}(undef, S_draws, n_mod)
    for s in 1:S_draws
        xi_draws[s, :] .= _mrcml_unpack(t, view(draws, s, :)).xi_model
    end
    zeros_vec = zeros(Float64, S_draws)
    qual = qualify(f)

    rows = map(resolved.entries) do ent
        vals = xi_draws * ent.weights
        res = B.posterior_contrast(vals, zeros_vec; chains, interval = iv, rope)
        p_pos = only(filter(e -> e.event == "above_zero", res.event_rows))
        (;
            facet = resolved.facet,
            target_level = ent.target_level,
            group = resolved.group,
            reference = resolved.reference,
            estimand = resolved.estimand,
            parameterization = ent.mode,
            scale_factor = ent.scale_factor,
            mean = res.mean,
            sd = res.sd,
            median = res.median,
            lower = res.lower,
            upper = res.upper,
            prob_positive = p_pos.probability,
            prob_positive_mcse = p_pos.mean_mcse,
            mean_mcse = res.precision.mean_mcse,
            lower_mcse = res.precision.quantiles[1].mcse,
            upper_mcse = res.precision.quantiles[3].mcse,
            result = res,
        )
    end

    if resolved.single
        r1 = only(rows)
        return merge(r1, (;
            interval = iv,
            level = iv,
            qualification = qual,
            source_sample_content_hash = f.record.content_hash,
            scientific_acceptance = false,
        ))
    end
    return (;
        schema = "bayesianmgmfrm.mrcml_dff_contrasts.v1",
        interaction = (resolved.facet, resolved.group_role),
        group = resolved.group,
        reference = resolved.reference,
        estimand = resolved.estimand,
        interval = iv,
        level = iv,
        rows,
        qualification = qual,
        source_sample_content_hash = f.record.content_hash,
        scientific_acceptance = false,
    )
end

function _diagnostic_scores(t::MRCMLTarget)
    op=t.operator
    [op.B_pat[op.pattern_ranges[op.pattern_of_row[n]]] for n in eachindex(t.person)]
end
_diagnostic_scores(t::ExplanatoryTarget) = [Float64.(0:length(t.supports[g])-1) for g in t.group]

function _diagnostic_logweights(t::MRCMLTarget,q)
    u=_mrcml_unpack(t,q);op=t.operator;shift=_mrcml_pattern_shifts(op,u.eta_xi)
    out=zeros(length(t.person),maximum(length,t.supports))
    for n in eachindex(t.person), (k,m) in enumerate(op.pattern_ranges[op.pattern_of_row[n]])
        out[n,k]=op.B_pat[m]*u.person[t.person[n]]+shift[m]
    end
    out
end
function _diagnostic_logweights(t::ExplanatoryTarget,q)
    v=coordinates(t,q);out=zeros(length(t.person),maximum(length,t.supports))
    for n in eachindex(t.person)
        eta=v.person[t.person[n]]+response_shift(t,v,n)-sum(v.facets[b.name][b.index[n]] for b in t.facets)
        for k in 2:length(t.supports[t.group[n]])
            out[n,k]=out[n,k-1]+eta-v.steps[t.group[n],k-1]
        end
    end
    out
end
function _diagnostic_moments!(prob,logweights,n,scores)
    K=length(scores);mx=maximum(view(logweights,n,1:K));total=0.
    for k in 1:K;prob[k]=exp(logweights[n,k]-mx);total+=prob[k];end
    mu=0.
    for k in 1:K;prob[k]/=total;mu+=prob[k]*scores[k];end
    variance=sum(prob[k]*(scores[k]-mu)^2 for k in 1:K)
    mu,variance
end

@inline function _pearson_corr_subset(
        x::AbstractMatrix{Float64},
        y::AbstractMatrix{Float64},
        col_a::Int,
        col_b::Int,
        units::Vector{Int})
    m = length(units)
    m >= 2 || return NaN
    sx = 0.0
    sy = 0.0
    @inbounds for u in units
        xu = x[u, col_a]
        yu = y[u, col_b]
        (isfinite(xu) && isfinite(yu)) || return NaN
        sx += xu
        sy += yu
    end
    mx = sx / m
    my = sy / m
    vx = 0.0
    vy = 0.0
    cov = 0.0
    @inbounds for u in units
        dx = x[u, col_a] - mx
        dy = y[u, col_b] - my
        vx += dx * dx
        vy += dy * dy
        cov += dx * dy
    end
    (vx > 1e-18 && vy > 1e-18) || return NaN
    return clamp(cov / sqrt(vx * vy), -1.0, 1.0)
end

function _q3_assessment_ids(t::Union{MRCMLTarget,ExplanatoryTarget})
    column = t.columns.assessment
    column === nothing && return nothing
    ids = t.table[column]
    return column === :row_id && length(unique(ids)) == length(ids) ? nothing : ids
end

function _build_q3_unit_cells(
        t::Union{MRCMLTarget,ExplanatoryTarget},
        by_fb::Block,
        other_fbs::Vector{Block},
        unit_mode::Symbol)
    n_obs = length(t.person)
    L = length(by_fb.levels)
    perf = t.columns.performance
    perf_ids = perf === nothing ? nothing : t.table[perf]
    assess_ids = _q3_assessment_ids(t)
    rater = findfirst(f -> f.name === :rater, t.facets)
    binding = if unit_mode === :person
        :person
    elseif assess_ids !== nothing
        :assessment_id
    elseif perf_ids !== nothing
        rater === nothing ? :performance_id : :performance_and_rater
    else
        :person_and_other_facets
    end
    unit_map = Dict{Any, Int}()
    obs_unit = Vector{Int}(undef, n_obs)
    for n in 1:n_obs
        key = if binding === :person
            t.person[n]
        elseif binding === :assessment_id
            assess_ids[n]
        elseif binding === :performance_id
            perf_ids[n]
        elseif binding === :performance_and_rater
            (perf_ids[n], t.facets[rater].index[n])
        else
            (t.person[n], Tuple(f.index[n] for f in other_fbs))
        end
        uid = get!(unit_map, key, length(unit_map) + 1)
        obs_unit[n] = uid
    end
    U = length(unit_map)
    cell_obs = [Int[] for _ in 1:U, _ in 1:L]
    for n in 1:n_obs
        push!(cell_obs[obs_unit[n], by_fb.index[n]], n)
    end
    max_cell = maximum(length, cell_obs)
    return (; U, cell_obs, max_cell, binding)
end

function _diagnostic_tail_mcse(observed, replicated, chains; complete_chains=true)
    complete_chains || return (;value=missing,status=:subsampled_chain_mcse_unavailable)
    all(isfinite, observed) && all(isfinite, replicated) ||
        return (;value=missing,status=:incomplete_draws_mcse_unavailable)
    return B._classification_mean(replicated .>= observed, chains).mcse
end

function _mrcml_residual_correlation(
        t::AbstractTarget,
        f::Fit;
        by::Union{Nothing, Symbol} = :auto,
        unit::Symbol = :auto,
        level::Real = 0.95,
        seed::Integer = 1,
        min_common_units::Integer = 5,
        max_draws::Union{Nothing, Integer} = 1000)
    t isa Union{MRCMLTarget,ExplanatoryTarget} || throw(ArgumentError(
        "Residual correlation requires an ordinal MRCML or explanatory fit; got $(typeof(t))"))
    seed isa Integer && !(seed isa Bool) || throw(ArgumentError("seed must be an integer"))
    min_cu = Int(min_common_units)
    min_cu >= 3 || throw(ArgumentError("min_common_units must be >= 3"))
    unit in (:auto, :event, :person) || throw(ArgumentError(
        "unit must be :auto, :event, or :person; got $(repr(unit))"))
    lo, hi = interval_bounds(level)

    fnames = [b.name for b in t.facets]
    !isempty(fnames) || throw(ArgumentError("residual_correlation requires at least one declared facet"))
    by_sym = if by === nothing || by === :auto
        :criterion in fnames ? :criterion : (:item in fnames ? :item : fnames[1])
    else
        by in fnames || throw(ArgumentError(
            "unknown `by = $(repr(by))` facet for residual_correlation; available: $(Tuple(fnames))"))
        by
    end
    by_fb = t.facets[only(findall(b -> b.name === by_sym, t.facets))]
    L = length(by_fb.levels)
    L >= 2 || throw(ArgumentError("residual_correlation requires at least 2 levels in facet :$(by_sym)"))
    other_fbs = Block[b for b in t.facets if b.name !== by_sym]

    can_bind_event = !isempty(other_fbs) || t.columns.performance !== nothing || _q3_assessment_ids(t) !== nothing
    resolved_unit, cells_info = if unit === :person || !can_bind_event
        unit === :event && throw(ArgumentError(
            "unit = :event requires a declared assessment/performance ID or a non-`by` facet alongside :$(by_sym)"))
        (:person, _build_q3_unit_cells(t, by_fb, other_fbs, :person))
    elseif unit === :event
        (:event, _build_q3_unit_cells(t, by_fb, other_fbs, :event))
    else
        ev_c = _build_q3_unit_cells(t, by_fb, other_fbs, :event)
        max_ev_common = 0
        for a in 1:(L - 1), b in (a + 1):L
            cnt = count(u -> !isempty(ev_c.cell_obs[u, a]) && !isempty(ev_c.cell_obs[u, b]), 1:ev_c.U)
            cnt > max_ev_common && (max_ev_common = cnt)
        end
        if max_ev_common >= min_cu
            (:event, ev_c)
        else
            (:person, _build_q3_unit_cells(t, by_fb, other_fbs, :person))
        end
    end

    U = cells_info.U
    cell_obs = cells_info.cell_obs
    agg_mode = cells_info.max_cell <= 1 ? :none : :sqrt_n_standardized_sum

    pair_list = Tuple{Int, Int}[]
    pair_units = Vector{Vector{Int}}()
    for a in 1:(L - 1), b in (a + 1):L
        cu = Int[u for u in 1:U if !isempty(cell_obs[u, a]) && !isempty(cell_obs[u, b])]
        if length(cu) >= min_cu
            push!(pair_list, (a, b))
            push!(pair_units, cu)
        end
    end
    n_pairs = length(pair_list)
    n_pairs >= 1 || throw(ArgumentError(
        "no facet pairs in :$(by_sym) share at least min_common_units = $min_cu common $(resolved_unit) units"))

    n_obs = length(t.person)
    scores = _diagnostic_scores(t)
    obs_b = [scores[n][t.category[n] - first(t.supports[t.group[n]]) + 1] for n in 1:n_obs]

    draws = f.record.run.draws
    S_tot = size(draws, 1)
    eval_indices = if max_draws === nothing || S_tot <= Int(max_draws)
        collect(1:S_tot)
    else
        md = Int(max_draws)
        md >= 10 || throw(ArgumentError("max_draws must be >= 10 when specified"))
        unique!(Int[round(Int, 1 + (k - 1) * (S_tot - 1) / (md - 1)) for k in 1:md])
    end
    n_eval = length(eval_indices)
    tail_mcse(obs, rep) = _diagnostic_tail_mcse(obs, rep, f.record.run.controls.chains;
        complete_chains=n_eval==S_tot)

    # Averaging logits preserves the posterior-mean model predictor; averaging
    # raw noncentered coordinates would replace E[sigma*z] by E[sigma]*E[z].
    logweights = _diagnostic_logweights(t, view(draws,1,:))
    mean_logweights = zero(logweights)
    for q in eachrow(draws);mean_logweights .+= _diagnostic_logweights(t,q);end
    mean_logweights ./= S_tot
    pbuf = zeros(maximum(length,t.supports))
    z_obs_n = Vector{Float64}(undef, n_obs)
    z_rep_n = Vector{Float64}(undef, n_obs)
    cell_obs_mat = Matrix{Float64}(undef, U, L)
    cell_rep_mat = Matrix{Float64}(undef, U, L)

    q3_obs_draws = fill(NaN, n_eval, n_pairs)
    q3_rep_draws = fill(NaN, n_eval, n_pairs)
    adj_obs_draws = fill(NaN, n_eval, n_pairs)
    adj_rep_draws = fill(NaN, n_eval, n_pairs)

    mean_q3_obs = fill(NaN, n_eval)
    mean_q3_rep = fill(NaN, n_eval)
    max_q3_obs = fill(NaN, n_eval)
    max_q3_rep = fill(NaN, n_eval)
    max_adj_obs = fill(NaN, n_eval)
    max_adj_rep = fill(NaN, n_eval)
    max_abs_adj_obs = fill(NaN, n_eval)
    max_abs_adj_rep = fill(NaN, n_eval)

    rng = Random.MersenneTwister(Int(seed))

    for (e_idx, s_idx) in enumerate(eval_indices)
        logweights = _diagnostic_logweights(t, view(draws,s_idx,:))
        @inbounds for n in 1:n_obs
            M_g = length(scores[n])
            eb,wn = _diagnostic_moments!(pbuf,logweights,n,scores[n])
            u_rand = rand(rng)
            cum_p = 0.0
            chosen_lk = M_g
            for lk in 1:M_g
                cum_p += pbuf[lk]
                if u_rand <= cum_p
                    chosen_lk = lk
                    break
                end
            end
            rep_b = scores[n][chosen_lk]
            if wn > 1e-12
                inv_sd = inv(sqrt(wn))
                z_obs_n[n] = (obs_b[n] - eb) * inv_sd
                z_rep_n[n] = (rep_b - eb) * inv_sd
            else
                z_obs_n[n] = NaN
                z_rep_n[n] = NaN
            end
        end

        @inbounds for c in 1:L, u_id in 1:U
            ns = cell_obs[u_id, c]
            if isempty(ns)
                cell_obs_mat[u_id, c] = NaN
                cell_rep_mat[u_id, c] = NaN
            elseif length(ns) == 1
                n1 = ns[1]
                cell_obs_mat[u_id, c] = z_obs_n[n1]
                cell_rep_mat[u_id, c] = z_rep_n[n1]
            else
                so = 0.0; sr = 0.0; cnt = 0
                for n_k in ns
                    zo = z_obs_n[n_k]; zr = z_rep_n[n_k]
                    if isfinite(zo) && isfinite(zr)
                        so += zo; sr += zr; cnt += 1
                    end
                end
                if cnt > 0
                    inv_rt = inv(sqrt(Float64(cnt)))
                    cell_obs_mat[u_id, c] = so * inv_rt
                    cell_rep_mat[u_id, c] = sr * inv_rt
                else
                    cell_obs_mat[u_id, c] = NaN
                    cell_rep_mat[u_id, c] = NaN
                end
            end
        end

        for p_idx in 1:n_pairs
            ca, cb = pair_list[p_idx]
            cu = pair_units[p_idx]
            q3_obs_draws[e_idx, p_idx] = _pearson_corr_subset(cell_obs_mat, cell_obs_mat, ca, cb, cu)
            q3_rep_draws[e_idx, p_idx] = _pearson_corr_subset(cell_rep_mat, cell_rep_mat, ca, cb, cu)
        end

        obs_row = view(q3_obs_draws, e_idx, :)
        rep_row = view(q3_rep_draws, e_idx, :)
        if all(isfinite, obs_row) && all(isfinite, rep_row)
            mo = mean(obs_row)
            mr = mean(rep_row)
            mean_q3_obs[e_idx] = mo
            mean_q3_rep[e_idx] = mr
            max_q3_obs[e_idx] = maximum(obs_row)
            max_q3_rep[e_idx] = maximum(rep_row)
            for p_idx in 1:n_pairs
                adj_obs_draws[e_idx, p_idx] = obs_row[p_idx] - mo
                adj_rep_draws[e_idx, p_idx] = rep_row[p_idx] - mr
            end
            adj_o = view(adj_obs_draws, e_idx, :)
            adj_r = view(adj_rep_draws, e_idx, :)
            max_adj_obs[e_idx] = maximum(adj_o)
            max_adj_rep[e_idx] = maximum(adj_r)
            max_abs_adj_obs[e_idx] = maximum(abs, adj_o)
            max_abs_adj_rep[e_idx] = maximum(abs, adj_r)
        end
    end

    # Plug-in residuals at the posterior mean of model-scale logit predictors.
    @inbounds for n in 1:n_obs
        eb,wn = _diagnostic_moments!(pbuf,mean_logweights,n,scores[n])
        z_obs_n[n] = wn > 1e-12 ? (obs_b[n] - eb) / sqrt(wn) : NaN
    end
    @inbounds for c in 1:L, u_id in 1:U
        ns = cell_obs[u_id, c]
        if isempty(ns)
            cell_obs_mat[u_id, c] = NaN
        elseif length(ns) == 1
            cell_obs_mat[u_id, c] = z_obs_n[ns[1]]
        else
            so = 0.0; cnt = 0
            for n_k in ns
                zo = z_obs_n[n_k]
                if isfinite(zo)
                    so += zo; cnt += 1
                end
            end
            cell_obs_mat[u_id, c] = cnt > 0 ? so / sqrt(Float64(cnt)) : NaN
        end
    end
    plugin_q3_vec = Float64[_pearson_corr_subset(cell_obs_mat, cell_obs_mat, pair_list[p_idx][1], pair_list[p_idx][2], pair_units[p_idx]) for p_idx in 1:n_pairs]
    plugin_mean_q3 = all(isfinite, plugin_q3_vec) ? mean(plugin_q3_vec) : NaN
    plugin_adj_vec = Float64[isfinite(plugin_mean_q3) ? (plugin_q3_vec[p_idx] - plugin_mean_q3) : NaN for p_idx in 1:n_pairs]

    rows = map(1:n_pairs) do p_idx
        ca, cb = pair_list[p_idx]
        vo = Float64[x for x in view(q3_obs_draws, :, p_idx) if isfinite(x)]
        vr = Float64[x for x in view(q3_rep_draws, :, p_idx) if isfinite(x)]
        ao = Float64[x for x in view(adj_obs_draws, :, p_idx) if isfinite(x)]
        ar = Float64[x for x in view(adj_rep_draws, :, p_idx) if isfinite(x)]
        valid_pairs_s = Int[s for s in 1:n_eval if isfinite(q3_obs_draws[s, p_idx]) && isfinite(q3_rep_draws[s, p_idx])]
        ppp_hi = isempty(valid_pairs_s) ? NaN : mean(q3_rep_draws[s, p_idx] >= q3_obs_draws[s, p_idx] for s in valid_pairs_s)
        ppp_lo = isempty(valid_pairs_s) ? NaN : mean(q3_rep_draws[s, p_idx] <= q3_obs_draws[s, p_idx] for s in valid_pairs_s)
        ppp_2 = isfinite(ppp_hi) ? min(1.0, 2.0 * min(ppp_hi, ppp_lo)) : NaN

        valid_adj_s = Int[s for s in 1:n_eval if isfinite(adj_obs_draws[s, p_idx]) && isfinite(adj_rep_draws[s, p_idx])]
        ppp_adj_hi = isempty(valid_adj_s) ? NaN : mean(adj_rep_draws[s, p_idx] >= adj_obs_draws[s, p_idx] for s in valid_adj_s)
        ppp_adj_lo = isempty(valid_adj_s) ? NaN : mean(adj_rep_draws[s, p_idx] <= adj_obs_draws[s, p_idx] for s in valid_adj_s)
        ppp_adj_2 = isfinite(ppp_adj_hi) ? min(1.0, 2.0 * min(ppp_adj_hi, ppp_adj_lo)) : NaN

        (;
            level_1 = by_fb.levels[ca],
            level_2 = by_fb.levels[cb],
            n_common_units = length(pair_units[p_idx]),
            q3_mean = isempty(vo) ? NaN : mean(vo),
            q3_sd = length(vo) >= 2 ? std(vo) : NaN,
            q3_lower = isempty(vo) ? NaN : quantile(vo, lo),
            q3_upper = isempty(vo) ? NaN : quantile(vo, hi),
            replicated_q3_mean = isempty(vr) ? NaN : mean(vr),
            ppp_q3_upper = ppp_hi,
            ppp_q3_upper_mcse = tail_mcse(view(q3_obs_draws,:,p_idx),view(q3_rep_draws,:,p_idx)),
            ppp_q3_twosided = ppp_2,
            adjusted_q3_mean = isempty(ao) ? NaN : mean(ao),
            adjusted_q3_lower = isempty(ao) ? NaN : quantile(ao, lo),
            adjusted_q3_upper = isempty(ao) ? NaN : quantile(ao, hi),
            replicated_adjusted_q3_mean = isempty(ar) ? NaN : mean(ar),
            ppp_adjusted_q3_upper = ppp_adj_hi,
            ppp_adjusted_q3_upper_mcse = tail_mcse(view(adj_obs_draws,:,p_idx),view(adj_rep_draws,:,p_idx)),
            ppp_adjusted_q3_twosided = ppp_adj_2,
            plugin_q3 = plugin_q3_vec[p_idx],
            plugin_adjusted_q3 = plugin_adj_vec[p_idx],
            plugin_caveat = :posterior_mean_plugin_ignores_parameter_uncertainty,
        )
    end

    val_g = Int[s for s in 1:n_eval if isfinite(mean_q3_obs[s]) && isfinite(mean_q3_rep[s])]
    global_summary = (;
        mean_q3_obs = isempty(val_g) ? NaN : mean(mean_q3_obs[s] for s in val_g),
        mean_q3_rep = isempty(val_g) ? NaN : mean(mean_q3_rep[s] for s in val_g),
        ppp_mean_q3 = isempty(val_g) ? NaN : mean(mean_q3_rep[s] >= mean_q3_obs[s] for s in val_g),
        ppp_mean_q3_mcse = tail_mcse(mean_q3_obs, mean_q3_rep),
        max_q3_obs = isempty(val_g) ? NaN : mean(max_q3_obs[s] for s in val_g),
        max_q3_rep = isempty(val_g) ? NaN : mean(max_q3_rep[s] for s in val_g),
        ppp_max_q3 = isempty(val_g) ? NaN : mean(max_q3_rep[s] >= max_q3_obs[s] for s in val_g),
        ppp_max_q3_mcse = tail_mcse(max_q3_obs, max_q3_rep),
        max_adjusted_q3_obs = isempty(val_g) ? NaN : mean(max_adj_obs[s] for s in val_g),
        max_adjusted_q3_rep = isempty(val_g) ? NaN : mean(max_adj_rep[s] for s in val_g),
        ppp_max_adjusted_q3 = isempty(val_g) ? NaN : mean(max_adj_rep[s] >= max_adj_obs[s] for s in val_g),
        ppp_max_adjusted_q3_mcse = tail_mcse(max_adj_obs, max_adj_rep),
        max_abs_adjusted_q3_obs = isempty(val_g) ? NaN : mean(max_abs_adj_obs[s] for s in val_g),
        max_abs_adjusted_q3_rep = isempty(val_g) ? NaN : mean(max_abs_adj_rep[s] for s in val_g),
        ppp_max_abs_adjusted_q3 = isempty(val_g) ? NaN : mean(max_abs_adj_rep[s] >= max_abs_adj_obs[s] for s in val_g),
        ppp_max_abs_adjusted_q3_mcse = tail_mcse(max_abs_adj_obs, max_abs_adj_rep),
        plugin_mean_q3,
        plugin_max_q3 = all(isfinite, plugin_q3_vec) ? maximum(plugin_q3_vec) : NaN,
        plugin_max_adjusted_q3 = all(isfinite, plugin_adj_vec) ? maximum(plugin_adj_vec) : NaN,
        plugin_max_abs_adjusted_q3 = all(isfinite, plugin_adj_vec) ? maximum(abs, plugin_adj_vec) : NaN,
        expected_null_mean_q3_approx = -1.0 / Float64(L - 1),
    )

    return (;
        schema = RESIDUAL_CORR_SCHEMA,
        kind = :residual_correlation,
        conditioning = :posterior_known_effects,
        residual_target = :remaining_dependence_given_fitted_effects,
        by = by_sym,
        unit = resolved_unit,
        unit_binding = cells_info.binding,
        aggregation = agg_mode,
        level = Float64(level),
        seed = Int(seed),
        min_common_units = min_cu,
        n_units = U,
        n_levels = L,
        n_pairs,
        n_draws_evaluated = n_eval,
        plugin_caveat = :posterior_mean_plugin_ignores_parameter_uncertainty,
        cutoff_guidance = :inspect_posterior_predictive_p_values_rather_than_fixed_0_20_cutoff,
        global_summary,
        rows,
        qualification = qualify(f),
        source_sample_content_hash = f.record.content_hash,
    )
end
