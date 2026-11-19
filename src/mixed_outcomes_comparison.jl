# Prior-factor sensitivity, event-wise PSIS-LOO, and held-performance Gauss-Hermite
# latent-integrated PSIS-LOO / model comparison for Stage 4 MixedOutcomeTarget.

const _MIXED_EVENT_CRITERIA_SCHEMA = "bayesianmgmfrm.mixed_event_criteria.v1"
const _MIXED_EVENT_COMPARISON_SCHEMA = "bayesianmgmfrm.mixed_event_comparison.v1"
const _MIXED_PROFILE_CRITERIA_SCHEMA = "bayesianmgmfrm.mixed_profile_criteria.v1"
const _MIXED_PROFILE_COMPARISON_SCHEMA = "bayesianmgmfrm.mixed_profile_comparison.v1"
const _MIXED_COMPARISON_SCHEMAS = (
    _MIXED_EVENT_CRITERIA_SCHEMA,
    _MIXED_EVENT_COMPARISON_SCHEMA,
    _MIXED_PROFILE_CRITERIA_SCHEMA,
    _MIXED_PROFILE_COMPARISON_SCHEMA,
)

function _explanatory_power_definitions(t::AdditiveFacets.MixedOutcomeTarget)
    A = AdditiveFacets; out = NamedTuple[]
    common = (; normalization = :included, jacobian_powered = false)
    out_names = [ch.name for ch in t.outcomes]

    for ob in t.owners
        for d in 1:ob.D_dim
            dname = ob.dim_names[d]
            id_res = ob.D_dim == 1 ? "residual[$(ob.name)]" : "residual[$(ob.name),$dname]"
            id_sd = ob.D_dim == 1 ? "residual_sd[$(ob.name)]" : "residual_sd[$(ob.name),$dname]"
            hyp = ob.hyps[d]
            if d == 1 || isempty(ob.corr_raw)
                push!(out, merge(common, (; id = id_res, family = :normal, owner = ob.name,
                    owner_ids = deepcopy(ob.levels), raw = collect(ob.raws[d]),
                    free_dimension = length(ob.raws[d]), sd = ob.sds_fixed[d], hyper = hyp,
                    logmean = ob.logmeans[d], logsd = ob.logsds[d],
                    measure = :residual_lebesgue, selectable = (hyp == 0),
                    role = hyp == 0 ? :fixed_scale_prior : :conditional_residual)))
            else
                row_start = ((d - 1) * (d - 2)) ÷ 2 + 1
                row_end = (d * (d - 1)) ÷ 2
                row_cr = collect(ob.corr_raw[row_start:row_end])
                push!(out, merge(common, (; id = id_res, family = :conditional_slope_normal, owner = ob.name,
                    owner_ids = deepcopy(ob.levels), raw = collect(ob.raws[d]),
                    free_dimension = length(ob.raws[d]), sd = ob.sds_fixed[d], hyper = hyp,
                    logmean = ob.logmeans[d], logsd = ob.logsds[d], corr_row_raw = row_cr,
                    measure = :residual_lebesgue, selectable = false, role = :conditional_residual)))
            end
            if hyp > 0
                push!(out, merge(common, (; id = id_sd, family = :lognormal, owner = ob.name,
                    raw = [hyp], free_dimension = 1, logmean = ob.logmeans[d], logsd = ob.logsds[d],
                    measure = :positive_sd_lebesgue, selectable = true, role = :hyperprior)))
            end
        end
        if ob.corr_kind === :lkj
            if ob.D_dim == 2
                push!(out, merge(common, (; id = "correlation[$(ob.name)]", family = :lkj2, owner = ob.name,
                    raw = collect(ob.corr_raw), free_dimension = 1, eta = ob.corr_eta,
                    measure = :correlation_interval_lebesgue, selectable = true, role = :correlation_prior)))
            else
                push!(out, merge(common, (; id = "correlation[$(ob.name)]", family = :lkj_corr, owner = ob.name,
                    raw = collect(ob.corr_raw), free_dimension = length(ob.corr_raw), D_dim = ob.D_dim, eta = ob.corr_eta,
                    measure = :correlation_matrix_lebesgue, selectable = true, role = :correlation_prior)))
            end
        end
        for d in 1:ob.D_dim, c in 1:length(out_names)
            le = ob.loadings[c, d]
            le.kind === :fixed && continue
            if le.kind === :normal
                push!(out, merge(common, (; id = "loading[$(ob.name),$(out_names[c]),$(ob.dim_names[d])]",
                    family = :normal, owner = ob.name, raw = [le.raw], free_dimension = 1,
                    mean = le.mean, sd = le.sd, hyper = 0,
                    measure = :loading_lebesgue, selectable = true, role = :loading_prior)))
            else
                push!(out, merge(common, (; id = "loading[$(ob.name),$(out_names[c]),$(ob.dim_names[d])]",
                    family = :lognormal, owner = ob.name, raw = [le.raw], free_dimension = 1,
                    logmean = le.mean, logsd = le.sd,
                    measure = :positive_loading_lebesgue, selectable = true, role = :loading_prior)))
            end
        end
    end

    for ch in t.outcomes
        if ch.family === :ordinal && !isempty(ch.step_raw)
            push!(out, merge(common, (; id = "steps[$(ch.name)]", family = :normal, owner = ch.name,
                raw = collect(ch.step_raw), free_dimension = length(ch.step_raw),
                sd = ch.step_scale, hyper = 0, measure = :finite_orthonormal_volume,
                selectable = true, role = :step_prior)))
        elseif ch.family === :zero_one_inflated_beta
            push!(out,
                merge(common, (; id = "precision[$(ch.name)]", family = :lognormal, owner = ch.name,
                    raw = [ch.prec_raw], free_dimension = 1, logmean = ch.prec_logmean, logsd = ch.prec_logsd,
                    measure = :positive_precision_lebesgue, selectable = true, role = :observation_prior)),
                merge(common, (; id = "endpoint_logit[$(ch.name)]", family = :normal, owner = ch.name,
                    raw = [ch.ep_raw], free_dimension = 1, mean = ch.ep_mean, sd = ch.ep_sd, hyper = 0,
                    measure = :logit_lebesgue, selectable = true, role = :observation_prior)),
                merge(common, (; id = "upper_logit[$(ch.name)]", family = :normal, owner = ch.name,
                    raw = [ch.up_raw], free_dimension = 1, mean = ch.up_mean, sd = ch.up_sd, hyper = 0,
                    measure = :logit_lebesgue, selectable = true, role = :observation_prior)))
        elseif ch.family === :beta_binomial
            push!(out, merge(common, (; id = "precision[$(ch.name)]", family = :lognormal, owner = ch.name,
                raw = [ch.prec_raw], free_dimension = 1, logmean = ch.prec_logmean, logsd = ch.prec_logsd,
                measure = :positive_precision_lebesgue, selectable = true, role = :observation_prior)))
        end
    end

    for tm in t.terms
        push!(out, merge(common, (; id = A._mixed_term_name(tm), family = :normal, owner = tm.owner,
            outcome = tm.outcome, column = tm.column, raw = [tm.raw], free_dimension = 1,
            mean = tm.mean, sd = tm.sd, hyper = 0, measure = :coefficient_lebesgue,
            selectable = true, role = :coefficient_prior)))
    end

    allunique(f.id for f in out) || throw(ArgumentError("ambiguous mixed-outcome scientific factor IDs"))
    out
end

function _mixed_power_estimand(t::AdditiveFacets.MixedOutcomeTarget, run, label, source)
    A = AdditiveFacets
    E = length(t.person)
    if Set(keys(source)) == Set((:row, :outcome, :metric))
        n = source.row; oname = Symbol(source.outcome); mk = Symbol(source.metric)
        n isa Integer && !(n isa Bool) && 1 <= n <= E || throw(ArgumentError("invalid row in mixed prediction estimand"))
        c = findfirst(ch -> ch.name === oname, t.outcomes)
        c === nothing && throw(ArgumentError("unknown outcome $oname in mixed prediction estimand"))
        ch = t.outcomes[c]
        values = Float64[]
        for q in eachrow(run.draws)
            m = getproperty(A.mixed_moments(t, q), oname)
            hasproperty(m, mk) || throw(ArgumentError("metric $mk not available for outcome $oname ($(ch.family))"))
            val = getproperty(m, mk)[n]
            isfinite(val) || throw(ArgumentError("nonfinite mixed prediction estimand value at row $n"))
            push!(values, Float64(val))
        end
        unit = ch.family === :ordinal ? "category score" :
               ch.family === :zero_one_inflated_beta ? replace(string(A.bounded_metric_unit(mk)), "_" => " ") :
               (mk === :expected_count ? "success count" : "probability")
        return (; label = String(label), definition = source, unit, parameter_space = :mixed_prediction,
                  operation = :known_row_moment, fixed = false, values)
    elseif Set(keys(source)) == Set((:row, :outcome, :category))
        n = source.row; oname = Symbol(source.outcome); cat = source.category
        n isa Integer && !(n isa Bool) && 1 <= n <= E || throw(ArgumentError("invalid row in mixed ordinal estimand"))
        c = findfirst(ch -> ch.name === oname, t.outcomes)
        c !== nothing && t.outcomes[c].family === :ordinal || throw(ArgumentError("category estimand requires an :ordinal outcome"))
        ch = t.outcomes[c]
        k = findfirst(==(cat), ch.categories)
        k !== nothing || throw(ArgumentError("undeclared category $cat for outcome $oname"))
        values = [Float64(getproperty(A.mixed_moments(t, q), oname).probabilities[n, k]) for q in eachrow(run.draws)]
        return (; label = String(label), definition = source, unit = "category probability",
                  parameter_space = :probability, operation = :known_row_probability, fixed = false, values)
    end
    nothing
end

function _mixed_observation_binding(t::AdditiveFacets.MixedOutcomeTarget; unit::Symbol, integrate = nothing)
    id_cols = unique([t.columns.person, values(t.columns.facets)...,
        filter(!isnothing, [t.columns.performance, t.columns.assessment])...])
    ids_dict = Dict(c => t.table[c] for c in id_cols)
    outcomes_meta = map(t.outcomes) do ch
        obs_idx = copy(ch.obs_rows)
        if ch.family === :ordinal
            (; name = ch.name, family = :ordinal, categories = copy(ch.categories),
               obs_rows = obs_idx, scores = [Int(t.table[ch.score_col][e]) for e in obs_idx])
        elseif ch.family === :zero_one_inflated_beta
            (; name = ch.name, family = :zero_one_inflated_beta, bounds = ch.bounds,
               obs_rows = obs_idx, scores = [Float64(t.table[ch.score_col][e]) for e in obs_idx])
        else
            (; name = ch.name, family = :count_mass,
               obs_rows = obs_idx, scores = [Int(t.table[ch.score_col][e]) for e in obs_idx],
               trials = [Int(t.table[ch.trials_col][e]) for e in obs_idx])
        end
    end
    binding = _cache_hash((; ids_dict, outcomes_meta, unit, integrate,
        measure = :mixed_outcome_event_joint_density_and_mass))
    (; ids_dict, outcomes_meta, binding)
end

function _mixed_event_criteria(f::AdditiveFacets.Fit, t::AdditiveFacets.MixedOutcomeTarget)
    A = AdditiveFacets; run = f.record.run
    _check_psis_iterations(run.chain_ids, run.iterations)
    S_draws = size(run.draws, 1); E = length(t.person)
    ll_mat = zeros(Float64, S_draws, E)
    for (s, q) in enumerate(eachrow(run.draws))
        ll_mat[s, :] = A.pointwise(t, q)
    end
    rows = NamedTuple[]; influence = zeros(Float64, S_draws)
    for e in 1:E
        x = _CC_MOD._profile_score(view(ll_mat, :, e), -view(ll_mat, :, e), run)
        eligible = x.row.importance_status === :ok && x.row.mcse_status === :available
        push!(rows, (; row = e, n_observed_outcomes = count(ch -> ch.observed[e], t.outcomes),
            log_score = x.row.log_score, eligible, diagnostics = x.row))
        influence .+= x.influence
    end
    quality = qualify(f)
    all_ok = quality.qualified && all(r -> r.eligible, rows)
    precision = _CC_MOD._heldout_precision(influence, run, all_ok)
    avail = all_ok && precision.mcse_status === :available
    bind = _mixed_observation_binding(t; unit = :event)
    pred_cols = Dict(tm.column => t.table[tm.column] for tm in t.terms if tm.column !== nothing)
    _prediction_seal((;
        schema = _MIXED_EVENT_CRITERIA_SCHEMA,
        unit = :event,
        conditioning = :known_owners_observed_covariates,
        measure = :mixed_outcome_event_joint_density_and_mass,
        observation_binding = bind.binding,
        rows,
        elpd = sum(r.log_score for r in rows),
        mcse = avail ? precision.mcse : nothing,
        status = avail ? :estimated : :diagnostic_only,
        precision,
        quality,
        predictor_columns = pred_cols,
        source_sample_hash = f.record.content_hash,
        target_identity = f.record.target_identity,
        multiplier = 1,
        sampling_standard_error = nothing,
        sampling_uncertainty = :unassessed_crossed_design,
        automatic_ranking = false,
        warnings = [A.design(t).warnings;
            "Event-wise PSIS scores held-out rating events with all owner identities known; use unit=:performance with integrate=:recording for held-performance latent integration."],
        scientific_acceptance = false,
    ))
end

function _mixed_profile_design(t::AdditiveFacets.MixedOutcomeTarget, unit, integrate)
    unit === :performance || throw(ArgumentError("mixed-outcome scoring requires unit=:event (integrate=nothing) or unit=:performance (integrate=<performance_facet>)"))
    integrate isa Symbol || throw(ArgumentError("supply integrate=<performance_facet> for unit=:performance"))
    found_f = findall(b -> b.name === integrate, t.facets)
    length(found_f) == 1 || throw(ArgumentError("integrate must name a declared facet"))
    blk = t.facets[only(found_f)]
    t.columns.performance !== nothing && blk.column === t.columns.performance ||
        throw(ArgumentError("integrate=$(repr(integrate)) must match the declared performance column $(repr(t.columns.performance))"))
    ob_idx = only(findall(ob -> ob.name === integrate, t.owners))
    ob = t.owners[ob_idx]
    ob.D_dim in (1, 2) || throw(ArgumentError("Gauss-Hermite held-performance integration supports 1D or 2D performance blocks (got D=$(ob.D_dim))"))
    any(tm -> tm.owner === integrate && tm.column !== nothing, t.terms) # allowed! owner regression stays deterministic on observed covariate!

    groups = [findall(==(g), ob.index) for g in eachindex(ob.levels)]
    all(!isempty, groups) || throw(ArgumentError("every performance must have at least one observed event"))
    E = length(t.person)
    for g_rows in groups
        keep = setdiff(1:E, g_rows)
        for other_ob in t.owners
            other_ob.name === integrate && continue
            Set(other_ob.index[keep]) == Set(other_ob.index) ||
                throw(ArgumentError("withholding performance removes $(other_ob.name) level; other owners must remain observed"))
        end
        for ch in t.outcomes
            any(e -> ch.observed[e], keep) ||
                throw(ArgumentError("withholding performance removes all observations of outcome $(ch.name)"))
        end
    end
    profiles = [(; profile = g, performance = deepcopy(ob.levels[g]), rows = copy(g_rows),
        n_ratings = sum(count(ch -> ch.observed[e], t.outcomes) for e in g_rows),
        n_events = length(g_rows)) for (g, g_rows) in enumerate(groups)]
    bind = _mixed_observation_binding(t; unit = :performance, integrate)
    (; unit = :performance, integrate, profiles, groups, owner_idx = ob_idx, owner_block = ob,
       observation_binding = bind.binding,
       conditioning = :known_other_owners_observed_covariate_roster,
       integration = ob.D_dim == 1 ? :one_iid_performance_residual_joint_mixed_profile : :two_dimensional_performance_factor_joint_mixed_profile,
       multiplier = 1)
end

function _mixed_cell_loglik(ch::AdditiveFacets.MixedOutcomeChannel, ov::NamedTuple, e::Int, eta_ec::Float64, a_buf::Vector{Float64})
    A = AdditiveFacets
    if ch.family === :ordinal
        K = length(ch.categories); H = K - 1
        a_buf[1] = 0.0
        @inbounds for h in 1:H
            a_buf[h + 1] = a_buf[h] + eta_ec - Float64(ov.steps[h])
        end
        z = _logsumexp(view(a_buf, 1:K))
        return a_buf[ch.y_ord[e]] - z
    elseif ch.family === :zero_one_inflated_beta
        lp, _, _, _, _ = A._bounded_cell_scalar(ch.y_zoib[e], eta_ec, Float64(ov.precision), Float64(ov.endpoint_logit), Float64(ov.upper_logit), ch.log_width)
        return lp
    else
        prec = ch.family === :beta_binomial ? Float64(ov.precision) : nothing
        lp, _, _ = A.count_cell(ch.y_count[e], ch.trials[e], eta_ec, prec, ch.logchoose[e])
        return lp
    end
end

@inline function _eval_mixed_h1(t::AdditiveFacets.MixedOutcomeTarget, outcomes_v, eta_base::Matrix{Float64},
        A_int::Matrix{Float64}, g_rows::Vector{Int}, u_val::Float64, a_buf::Vector{Float64})
    M = length(t.outcomes)
    ll = -0.5 * u_val * u_val
    @inbounds for e in g_rows, c in 1:M
        ch = t.outcomes[c]
        ch.observed[e] || continue
        ec = eta_base[e, c] + A_int[c, 1] * u_val
        ll += _mixed_cell_loglik(ch, outcomes_v[c], e, ec, a_buf)
    end
    return ll
end

@inline function _eval_mixed_h2(t::AdditiveFacets.MixedOutcomeTarget, outcomes_v, eta_base::Matrix{Float64},
        A_int::Matrix{Float64}, g_rows::Vector{Int}, u1::Float64, u2::Float64, a_buf::Vector{Float64})
    M = length(t.outcomes)
    ll = -0.5 * (u1 * u1 + u2 * u2)
    @inbounds for e in g_rows, c in 1:M
        ch = t.outcomes[c]
        ch.observed[e] || continue
        ec = eta_base[e, c] + A_int[c, 1] * u1 + A_int[c, 2] * u2
        ll += _mixed_cell_loglik(ch, outcomes_v[c], e, ec, a_buf)
    end
    return ll
end

function _mixed_profile_integrals(t::AdditiveFacets.MixedOutcomeTarget, d, run, quads; training = t, profiles = eachindex(d.groups))
    A = AdditiveFacets
    ids = collect(profiles); S_draws = size(run.draws, 1); M = length(t.outcomes)
    coarse = zeros(Float64, S_draws, length(ids))
    fine = zeros(Float64, S_draws, length(ids))
    ob = d.owner_block; oi_int = d.owner_idx; sgn_int = ob.sign
    max_K = maximum(ch -> ch.family === :ordinal ? length(ch.categories) : 2, t.outcomes)
    a_buf = zeros(Float64, max_K)
    A_int = zeros(Float64, M, ob.D_dim)

    for (s, q_raw) in enumerate(eachrow(run.draws))
        q = training === t ? q_raw : _mixed_transport(training, t, q_raw)
        v = coordinates(t, q)
        ov_int = v.owners[ob.name]
        outcomes_v = v.outcomes
        # Precompute unsigned base eta WITHOUT `integrate` random residual (keeping fixed/owner covariates!)
        eta_base_any = A._mixed_eta_matrix(t, v)
        eta_base = Matrix{Float64}(eta_base_any)
        # Subtract out the current draw's realized `integrate` random effect (which `eta_base` included)
        for (c, ch) in enumerate(t.outcomes)
            dsgn = ch.dir_sign
            for e in 1:length(t.person)
                eta_base[e, c] -= dsgn * sgn_int * Float64(ov_int.projected[ob.index[e], c])
            end
        end

        # Effective signed loading matrix A_int (M x D_int): contribution at standard-normal u is A_int * u
        D_int = ob.D_dim
        for c in 1:M
            dsgn = t.outcomes[c].dir_sign
            for m in 1:D_int
                acc = 0.0
                for dm in m:D_int
                    acc += Float64(ov_int.loadings[c, dm]) * Float64(ov_int.sds[dm]) * Float64(ov_int.L[dm, m])
                end
                A_int[c, m] = dsgn * sgn_int * acc
            end
        end

        # Liu & Pierce (1994, Biometrika 81:624-629) mode-and-curvature adaptive Gauss-Hermite
        # change of variables u = u_hat + L_tau * z (exact Jacobian det(L_tau) * phi(u) / phi(z)),
        # preventing node under-resolution when ZOIB/count profile likelihoods shift or sharpen conditional modes.
        if D_int == 1
            sums1 = Vector{Float64}(undef, length(quads[1].nodes))
            sums2 = Vector{Float64}(undef, length(quads[2].nodes))
            for (gi, g_id) in enumerate(ids)
                g_rows = d.groups[g_id]
                u_hat = 0.0; eps_fd = 1e-3
                for _ in 1:6
                    h0 = _eval_mixed_h1(t, outcomes_v, eta_base, A_int, g_rows, u_hat, a_buf)
                    hp = _eval_mixed_h1(t, outcomes_v, eta_base, A_int, g_rows, u_hat + eps_fd, a_buf)
                    hm = _eval_mixed_h1(t, outcomes_v, eta_base, A_int, g_rows, u_hat - eps_fd, a_buf)
                    g1 = (hp - hm) / (2.0 * eps_fd)
                    neg_h2 = max(1.0, -(hp - 2.0 * h0 + hm) / (eps_fd * eps_fd))
                    step = clamp(g1 / neg_h2, -2.0, 2.0)
                    u_hat += step
                    abs(step) < 1e-6 && break
                end
                h0 = _eval_mixed_h1(t, outcomes_v, eta_base, A_int, g_rows, u_hat, a_buf)
                hp = _eval_mixed_h1(t, outcomes_v, eta_base, A_int, g_rows, u_hat + eps_fd, a_buf)
                hm = _eval_mixed_h1(t, outcomes_v, eta_base, A_int, g_rows, u_hat - eps_fd, a_buf)
                neg_h2 = clamp(-(hp - 2.0 * h0 + hm) / (eps_fd * eps_fd), 0.25, 2500.0)
                tau_hat = 1.0 / sqrt(neg_h2)
                log_tau = log(tau_hat)

                for (qi, quad) in enumerate(quads)
                    nodes = quad.nodes; lw = quad.logweights
                    sums = qi == 1 ? sums1 : sums2
                    @inbounds for jn in eachindex(nodes)
                        zj = nodes[jn]
                        uj = u_hat + tau_hat * zj
                        ll_node = 0.0
                        for e in g_rows, c in 1:M
                            ch = t.outcomes[c]
                            ch.observed[e] || continue
                            ec = eta_base[e, c] + A_int[c, 1] * uj
                            ll_node += _mixed_cell_loglik(ch, outcomes_v[c], e, ec, a_buf)
                        end
                        sums[jn] = lw[jn] + log_tau + 0.5 * (zj * zj - uj * uj) + ll_node
                    end
                    (qi == 1 ? coarse : fine)[s, gi] = _logsumexp(sums)
                end
            end
        else
            sums1 = Vector{Float64}(undef, length(quads[1].nodes)^2)
            sums2 = Vector{Float64}(undef, length(quads[2].nodes)^2)
            for (gi, g_id) in enumerate(ids)
                g_rows = d.groups[g_id]
                u1_h = 0.0; u2_h = 0.0; eps_fd = 1e-3
                for _ in 1:6
                    h00 = _eval_mixed_h2(t, outcomes_v, eta_base, A_int, g_rows, u1_h, u2_h, a_buf)
                    hp0 = _eval_mixed_h2(t, outcomes_v, eta_base, A_int, g_rows, u1_h + eps_fd, u2_h, a_buf)
                    hm0 = _eval_mixed_h2(t, outcomes_v, eta_base, A_int, g_rows, u1_h - eps_fd, u2_h, a_buf)
                    h0p = _eval_mixed_h2(t, outcomes_v, eta_base, A_int, g_rows, u1_h, u2_h + eps_fd, a_buf)
                    h0m = _eval_mixed_h2(t, outcomes_v, eta_base, A_int, g_rows, u1_h, u2_h - eps_fd, a_buf)
                    g1 = (hp0 - hm0) / (2.0 * eps_fd); g2 = (h0p - h0m) / (2.0 * eps_fd)
                    k11 = max(1.0, -(hp0 - 2.0 * h00 + hm0) / (eps_fd * eps_fd))
                    k22 = max(1.0, -(h0p - 2.0 * h00 + h0m) / (eps_fd * eps_fd))
                    st1 = clamp(g1 / k11, -1.5, 1.5); st2 = clamp(g2 / k22, -1.5, 1.5)
                    u1_h += st1; u2_h += st2
                    max(abs(st1), abs(st2)) < 1e-5 && break
                end
                h00 = _eval_mixed_h2(t, outcomes_v, eta_base, A_int, g_rows, u1_h, u2_h, a_buf)
                hp0 = _eval_mixed_h2(t, outcomes_v, eta_base, A_int, g_rows, u1_h + eps_fd, u2_h, a_buf)
                hm0 = _eval_mixed_h2(t, outcomes_v, eta_base, A_int, g_rows, u1_h - eps_fd, u2_h, a_buf)
                h0p = _eval_mixed_h2(t, outcomes_v, eta_base, A_int, g_rows, u1_h, u2_h + eps_fd, a_buf)
                h0m = _eval_mixed_h2(t, outcomes_v, eta_base, A_int, g_rows, u1_h, u2_h - eps_fd, a_buf)
                k11 = clamp(-(hp0 - 2.0 * h00 + hm0) / (eps_fd * eps_fd), 0.25, 2500.0)
                k22 = clamp(-(h0p - 2.0 * h00 + h0m) / (eps_fd * eps_fd), 0.25, 2500.0)
                t1 = 1.0 / sqrt(k11); t2 = 1.0 / sqrt(k22)
                log_jac = log(t1) + log(t2)

                for (qi, quad) in enumerate(quads)
                    nodes = quad.nodes; lw = quad.logweights; nn = length(nodes)
                    sums = qi == 1 ? sums1 : sums2
                    idx_node = 0
                    @inbounds for j1 in 1:nn, j2 in 1:nn
                        idx_node += 1
                        z1 = nodes[j1]; z2 = nodes[j2]
                        u1 = u1_h + t1 * z1; u2 = u2_h + t2 * z2
                        ll_node = 0.0
                        for e in g_rows, c in 1:M
                            ch = t.outcomes[c]
                            ch.observed[e] || continue
                            ec = eta_base[e, c] + A_int[c, 1] * u1 + A_int[c, 2] * u2
                            ll_node += _mixed_cell_loglik(ch, outcomes_v[c], e, ec, a_buf)
                        end
                        sums[idx_node] = lw[j1] + lw[j2] + log_jac + 0.5 * (z1 * z1 + z2 * z2 - u1 * u1 - u2 * u2) + ll_node
                    end
                    (qi == 1 ? coarse : fine)[s, gi] = _logsumexp(sums)
                end
            end
        end
    end
    all(isfinite, coarse) && all(isfinite, fine) || throw(ArgumentError("nonfinite mixed-outcome profile integral"))
    (; coarse, fine)
end

function _mixed_training_target(t::AdditiveFacets.MixedOutcomeTarget, d, perf_id)
    A = AdditiveFacets
    idx = findfirst(p -> isequal(p.performance, perf_id), d.profiles)
    idx === nothing && throw(ArgumentError("unknown withheld performance ID $(repr(perf_id))"))
    keep = setdiff(1:length(t.person), d.groups[idx])
    r = A.record(t)
    drop_cols = hasproperty(r.specification, :decomposition) ?
        Set(rule.source for rule in r.specification.decomposition.rules if !any(tm -> tm.column === rule.source, t.terms)) :
        Set{Symbol}()
    s = hasproperty(r.specification, :decomposition) ? Base.structdiff(r.specification, (; decomposition = nothing)) : r.specification
    new_f_levs = filter(!isequal(perf_id), d.owner_block.levels)
    levels = merge(r.levels, (; facets = merge(r.levels.facets, NamedTuple{(d.integrate,)}((new_f_levs,)))))
    A.restore_mixed(merge(r, (; specification = s, levels, table = Dict(c => v[keep] for (c, v) in t.table if !(c in drop_cols)))))
end

function _mixed_transport(from::AdditiveFacets.MixedOutcomeTarget, to::AdditiveFacets.MixedOutcomeTarget, q)
    A = AdditiveFacets; out = zeros(Float64, to.dimension)
    for ob_f in from.owners
        ob_t = only(o for o in to.owners if o.name === ob_f.name)
        for d in 1:ob_f.D_dim
            for (jf, id) in enumerate(ob_f.levels)
                jt = findfirst(isequal(id), ob_t.levels)
                jt === nothing && continue
                out[ob_t.raws[d][jt]] = q[ob_f.raws[d][jf]]
            end
            ob_f.hyps[d] > 0 && (out[ob_t.hyps[d]] = q[ob_f.hyps[d]])
        end
        !isempty(ob_f.corr_raw) && (out[ob_t.corr_raw] = q[ob_f.corr_raw])
        for d in 1:ob_f.D_dim, c in 1:length(from.outcomes)
            le_f = ob_f.loadings[c, d]; le_t = ob_t.loadings[c, d]
            le_f.kind !== :fixed && (out[le_t.raw] = q[le_f.raw])
        end
    end
    for (ch_f, ch_t) in zip(from.outcomes, to.outcomes)
        if ch_f.family === :ordinal && !isempty(ch_f.step_raw)
            out[ch_t.step_raw] = q[ch_f.step_raw]
        elseif ch_f.family === :zero_one_inflated_beta
            out[ch_t.prec_raw] = q[ch_f.prec_raw]
            out[ch_t.ep_raw] = q[ch_f.ep_raw]
            out[ch_t.up_raw] = q[ch_f.up_raw]
        elseif ch_f.family === :beta_binomial
            out[ch_t.prec_raw] = q[ch_f.prec_raw]
        end
    end
    for tm_f in from.terms
        tm_t = only(tm for tm in to.terms if A._mixed_term_name(tm) == A._mixed_term_name(tm_f))
        out[tm_t.raw] = q[tm_f.raw]
    end
    out
end

function _mixed_profile_criteria(f::AdditiveFacets.Fit, t::AdditiveFacets.MixedOutcomeTarget;
        unit, integrate, refits, independent_refit_rng::Bool, mcse_blocks,
        quadrature_orders, quadrature_tolerance, score_tolerance)
    A = AdditiveFacets; CC = _CC_MOD
    d = _mixed_profile_design(t, unit, integrate)
    q_orders = quadrature_orders === nothing ? (d.owner_block.D_dim == 1 ? (31, 61) : (21, 31)) : quadrature_orders
    quads = _explanatory_quadrature(q_orders, quadrature_tolerance, score_tolerance)
    run = f.record.run; S_draws = size(run.draws, 1)
    _check_psis_iterations(run.chain_ids, run.iterations)
    run.chain_ids == repeat(1:run.controls.chains; inner = S_draws ÷ run.controls.chains) ||
        throw(ArgumentError("stored chain order must remain intact"))
    quality = qualify(f)
    ints = _mixed_profile_integrals(t, d, run, quads)

    supplied = Dict{Any,AdditiveFacets.Fit}()
    for item in collect(refits)
        item isa Pair && last(item) isa AdditiveFacets.Fit || throw(ArgumentError("refits must contain performance_id => fit pairs"))
        id, rf = item
        haskey(supplied, id) && throw(ArgumentError("duplicate refit performance ID"))
        any(p -> isequal(p.performance, id), d.profiles) || throw(ArgumentError("refit ID is not a declared performance"))
        supplied[id] = rf
    end
    independent_refit_rng && length(unique([f.record.content_hash; [rf.record.content_hash for rf in values(supplied)]])) != length(supplied) + 1 &&
        throw(ArgumentError("refit shares sample hash with full fit or another refit"))

    rows = NamedTuple[]; influence = zeros(Float64, S_draws); refit_vars = Float64[]; ref_records = NamedTuple[]
    for (gi, p) in enumerate(d.profiles)
        err = maximum(abs.(view(ints.fine, :, gi) .- view(ints.coarse, :, gi)))
        s_diff = abs((_logsumexp(view(ints.fine, :, gi)) - log(S_draws)) - (_logsumexp(view(ints.coarse, :, gi)) - log(S_draws)))
        q_ok = err <= quadrature_tolerance && s_diff <= score_tolerance
        ps = CC._profile_score(view(ints.fine, :, gi), -view(ints.fine, :, gi), run)
        if haskey(supplied, p.performance)
            rf = supplied[p.performance]; rt = A.checked(rf; full = true)
            expected = _mixed_training_target(t, d, p.performance)
            rf.record.target_identity == _cache_hash(A.record(expected)) ||
                throw(ArgumentError("refit for $(p.performance) does not match loo_refit_plan target"))
            rrun = rf.record.run; _check_psis_iterations(rrun.chain_ids, rrun.iterations)
            rqual = qualify(rf)
            rx = _mixed_profile_integrals(t, d, rrun, quads; training = rt, profiles = [gi])
            fine_v = vec(rx.fine)
            d_score = _logsumexp(fine_v) - log(length(fine_v))
            rerr = maximum(abs.(rx.fine .- rx.coarse))
            rs_diff = abs(d_score - (_logsumexp(vec(rx.coarse)) - log(length(fine_v))))
            rq_ok = rerr <= quadrature_tolerance && rs_diff <= score_tolerance
            direct_prec = CC._heldout_precision(exp.(fine_v .- d_score) .- 1.0, rrun, true)
            ok = rqual.qualified && rq_ok && direct_prec.mcse_status === :available
            ok && push!(refit_vars, direct_prec.mcse^2)
            compact_qual = (; qualified = rqual.qualified, warmup = rqual.warmup)
            push!(ref_records, (; p.profile, p.performance, source_sample_hash = rf.record.content_hash,
                target_identity = rf.record.target_identity, quality = compact_qual, log_score = d_score,
                direct_prec..., quadrature_error = rerr, quadrature_score_error = rs_diff, quadrature_passed = rq_ok))
            push!(rows, (; p..., method = :direct_refit, log_score = d_score,
                mcse = ok ? direct_prec.mcse : nothing, mcse_status = ok ? :available : :unavailable,
                eligible = ok, original = merge(ps.row, (; quadrature_error = err, quadrature_score_error = s_diff, quadrature_passed = q_ok)),
                reference = last(ref_records), pareto_k = ps.row.pareto_k,
                quadrature_error = rerr, score_quadrature_difference = rs_diff, quadrature_passed = rq_ok,
                refit_qualified = rqual.qualified))
        else
            ok = quality.qualified && q_ok && ps.row.importance_status === :ok && ps.row.mcse_status === :available
            influence .+= ps.influence
            push!(rows, (; p..., method = :integrated_psis, log_score = ps.row.log_score,
                mcse = ok ? ps.row.mcse : nothing, mcse_status = ok ? :available : :unavailable,
                eligible = ok, original = merge(ps.row, (; quadrature_error = err, quadrature_score_error = s_diff, quadrature_passed = q_ok)),
                reference = nothing, pareto_k = ps.row.pareto_k, importance_status = ps.row.importance_status,
                r_eff = ps.row.r_eff, quadrature_error = err, score_quadrature_difference = s_diff,
                quadrature_passed = q_ok))
        end
    end

    all_ok = all(r -> r.eligible, rows) && (isempty(supplied) || independent_refit_rng)
    psis_keep = findall(r -> r.method === :integrated_psis, rows)
    psis_used = !isempty(psis_keep)
    total_prec = psis_used ? CC._heldout_precision(influence, run, all_ok && quality.qualified) :
        (; mcse = 0.0, mcse_status = :available, diagnostics = nothing)
    avail = all_ok && total_prec.mcse_status === :available
    mcse_val = avail ? sqrt((psis_used ? total_prec.mcse^2 : 0.0) + sum(refit_vars)) : nothing
    blocks = NamedTuple[]
    for b in mcse_blocks
        _explanatory_check_block(b, S_draws, run.controls.chains)
        if avail
            ps_b = isempty(psis_keep) ? 0.0 : _explanatory_block_mcse(ints.fine[:, psis_keep], [rows[g].original.r_eff for g in psis_keep], b, run.controls.chains).mcse
            push!(blocks, (; block = b, mcse = ps_b, status = :available))
        else
            push!(blocks, (; block = b, mcse = nothing, status = :unavailable))
        end
    end
    pred_cols = Dict(tm.column => copy(t.table[tm.column]) for tm in t.terms if tm.column !== nothing)

    _prediction_seal((;
        schema = _MIXED_PROFILE_CRITERIA_SCHEMA,
        unit = d.unit, integrate = d.integrate, profiles = d.profiles,
        observation_binding = d.observation_binding, conditioning = d.conditioning, integration = d.integration,
        multiplier = 1, criterion = :psis_loo,
        rows, elpd = sum(r.log_score for r in rows), mcse = mcse_val,
        status = avail ? :estimated : :diagnostic_only,
        problem_performances = [r.performance for r in rows if !r.eligible],
        mcse_status = avail ? :available : :unavailable,
        shared_draw_precision = total_prec,
        mcse_blocks = blocks,
        independent_refit_rng, reference_records = ref_records,
        source_sample_hash = f.record.content_hash, target_identity = f.record.target_identity,
        predictor_columns = pred_cols,
        quality, sampling_warning = !quality.qualified, model_warnings = A.design(t).warnings,
        quadrature_orders = q_orders, quadrature_tolerance, score_tolerance,
        sampling_standard_error = nothing, sampling_uncertainty = :unassessed_crossed_design,
        scientific_acceptance = :not_established, automatic_ranking = false, new_fits = 0,
    ))
end

function _check_mixed_comparison_report(r)
    r.schema in _MIXED_COMPARISON_SCHEMAS || throw(ArgumentError("unsupported mixed-outcome criteria/comparison schema"))
    r isa NamedTuple && _prediction_check_seal(r, r.schema)
    _explanatory_absent(r.sampling_standard_error) && string(r.sampling_uncertainty) == "unassessed_crossed_design" && r.automatic_ranking === false ||
        throw(ArgumentError("mixed-outcome comparison contract altered"))
    if r.schema in (_MIXED_EVENT_CRITERIA_SCHEMA, _MIXED_PROFILE_CRITERIA_SCHEMA)
        !isempty(r.rows) && all(x -> isfinite(x.log_score), r.rows) &&
            isapprox(sum(x.log_score for x in r.rows), r.elpd; atol = 1e-8) ||
            throw(ArgumentError("mixed-outcome criteria total mismatch"))
    else
        length(r.models) == 2 || throw(ArgumentError("comparison requires two models"))
        foreach(_check_mixed_comparison_report, r.models)
        r.models[1].observation_binding == r.models[2].observation_binding == r.observation_binding ||
            throw(ArgumentError("mixed-outcome observation binding mismatch"))
        isapprox(r.difference, r.models[1].elpd - r.models[2].elpd; atol = 1e-8) ||
            throw(ArgumentError("mixed-outcome difference mismatch"))
    end
    r
end

function _compare_mixed_scores(models; criterion = :psis_loo, comparison_axis = nothing, independent_model_rng::Bool = false)
    length(models) == 2 && criterion === :psis_loo && comparison_axis in (nothing, :model) ||
        throw(ArgumentError("supply two mixed-outcome criteria reports with criterion=:psis_loo"))
    labels = string.(first.(models))
    allunique(labels) && all(!isempty, labels) || throw(ArgumentError("distinct nonempty model labels required"))
    a, b = last.(models)
    foreach(_check_mixed_comparison_report, (a, b))
    a.schema == b.schema && a.schema in (_MIXED_EVENT_CRITERIA_SCHEMA, _MIXED_PROFILE_CRITERIA_SCHEMA) &&
        a.observation_binding == b.observation_binding ||
        throw(ArgumentError("mixed-outcome models must share the same unit, integration target, observed masks, and outcome measures"))
    for col in intersect(keys(a.predictor_columns), keys(b.predictor_columns))
        collect(a.predictor_columns[col]) == collect(b.predictor_columns[col]) ||
            throw(ArgumentError("shared predictor $col differs between models"))
    end
    independent_model_rng && a.source_sample_hash == b.source_sample_hash &&
        throw(ArgumentError("shared draws cannot be declared independent"))
    avail = independent_model_rng && !_explanatory_absent(a.mcse) && !_explanatory_absent(b.mcse)
    is_prof = a.schema == _MIXED_PROFILE_CRITERIA_SCHEMA
    rows = if is_prof
        [(; profile = x.profile, performance = x.performance, n_ratings = x.n_ratings,
            primary = x.log_score, baseline = y.log_score, difference = x.log_score - y.log_score,
            mcse = independent_model_rng && !_explanatory_absent(x.mcse) && !_explanatory_absent(y.mcse) ? hypot(x.mcse, y.mcse) : nothing,
            eligible = x.eligible && y.eligible,
            reference_used = string(x.method) == "direct_refit" || string(y.method) == "direct_refit") for (x, y) in zip(a.rows, b.rows)]
    else
        [(; row = x.row, primary = x.log_score, baseline = y.log_score, difference = x.log_score - y.log_score,
            eligible = x.eligible && y.eligible) for (x, y) in zip(a.rows, b.rows)]
    end
    blocks = is_prof ? [(; block = x.block, mcse = avail && !_explanatory_absent(x.mcse) && !_explanatory_absent(y.mcse) ? hypot(x.mcse, y.mcse) : nothing)
        for x in a.mcse_blocks for y in b.mcse_blocks if x.block == y.block] : NamedTuple[]
    warns = is_prof ? String[] : unique([a.warnings; b.warnings])
    _prediction_seal((;
        schema = is_prof ? _MIXED_PROFILE_COMPARISON_SCHEMA : _MIXED_EVENT_COMPARISON_SCHEMA,
        names = collect(labels), models = [a, b],
        unit = a.unit, integrate = is_prof ? a.integrate : nothing,
        conditioning = a.conditioning, multiplier = 1, criterion = :psis_loo,
        observation_binding = a.observation_binding,
        difference = a.elpd - b.elpd,
        mean_difference = (a.elpd - b.elpd) / length(rows),
        mcse = avail ? hypot(a.mcse, b.mcse) : nothing,
        status = avail ? :estimated : :diagnostic_only,
        mcse_blocks = blocks, warnings = warns,
        independent_model_rng, rows,
        sampling_standard_error = nothing, sampling_uncertainty = :unassessed_crossed_design,
        scientific_acceptance = :not_established, automatic_ranking = false, new_fits = 0,
    ))
end
