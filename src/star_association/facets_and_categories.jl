function _indicator_mean_mcse(values::AbstractVector, chains::Int; fixed::Bool = false)
    S = length(values)
    n = div(S, max(chains, 1))
    status = if fixed
        :structurally_fixed
    elseif chains < 2
        :insufficient_chains
    elseif n < 10
        :insufficient_draws
    elseif allequal(values)
        :degenerate_draws
    else
        :available
    end
    val = if fixed
        0.0
    elseif status === :available
        B._posterior_mcse_value(reshape(Float64.(values), n, chains), Statistics.mean)
    else
        missing
    end
    if status === :available && (ismissing(val) || val <= 0)
        status = :mcse_unavailable
        val = missing
    end
    return (;
        mean = mean(values),
        mcse = (; value = val, status, method = :mcmc_mean, n_chains = chains, draws_per_chain = n),
    )
end

function _scalar_draw_summary(
    values::AbstractVector{Float64},
    chains::Int,
    interval::Float64;
    space::Symbol = :transformed,
    fixed::Bool = false,
)
    lo, hi = B._interval_probabilities(interval)
    m = mean(values)
    sd = length(values) > 1 ? std(values) : missing
    mc = only(
        B._posterior_mcse_rows(
            reshape(values, :, 1),
            ["q"],
            chains;
            probabilities = (lo, 0.5, hi),
            parameter_space = space,
            structurally_fixed_parameters = fixed ? Set(["q"]) : Set{String}(),
        ),
    )
    return (;
        mean = m,
        sd,
        median = mc.quantiles[2].estimate,
        lower = mc.quantiles[1].estimate,
        upper = mc.quantiles[3].estimate,
        mean_mcse = mc.mean_mcse,
        lower_mcse = mc.quantiles[1].mcse,
        upper_mcse = mc.quantiles[3].mcse,
        mcse_status = mc.mcse_status,
    )
end

function _resolve_facet_selection(m::StarModel, facet::Symbol, ids; min_levels::Int = 1)
    facet in (:entity, :rater) || throw(ArgumentError("facet must be :entity or :rater"))
    levels = facet === :entity ? m.entity_levels : m.rater_levels
    sel = ids === nothing ? copy(levels) : [String(x) for x in collect(ids)]
    (length(sel) >= min_levels && allunique(sel)) ||
        throw(ArgumentError("select at least $min_levels distinct $facet IDs"))
    lmap = Dict(id => i for (i, id) in enumerate(levels))
    all(id -> haskey(lmap, id), sel) || throw(ArgumentError("unknown $facet level ID"))
    idxs = [lmap[id] for id in sel]
    counts = facet === :entity ? m.entity_basis.raw_counts : m.rater_basis.raw_counts
    return sel, idxs, counts
end

function _resolve_criteria_indices(m::StarModel, criteria)
    criteria === nothing && return collect(1:m.D)
    req = criteria isa AbstractString ? [String(criteria)] : [String(x) for x in collect(criteria)]
    (!isempty(req) && allunique(req)) || throw(ArgumentError("criteria must be distinct nonempty names"))
    cmap = Dict(c.id => idx for (idx, c) in enumerate(m.criteria))
    all(id -> haskey(cmap, id), req) || throw(ArgumentError("unknown criterion ID"))
    return [cmap[id] for id in req]
end

function _fill_facet_chunk_draws!(
    eff_buf,
    exp_buf,
    res::StarResult,
    facet::Symbol,
    sub_idxs::Vector{Int},
    c_idxs::Vector{Int},
    inc_exp::Bool,
)
    m = res.model
    S = size(res.draws, 1)
    s_scr = _scratch(m.M, Float64)
    eta = zeros(Float64, m.D)
    raw_vals = [Float64.(m.criteria[c].canonical_to_raw) for c in 1:m.D]
    for s in 1:S
        v = _coordinates(m, view(res.draws, s, :); raw_input = false)
        F = facet === :entity ? v.A : v.S
        for (li, lv_idx) in enumerate(sub_idxs)
            if inc_exp
                for c in 1:m.D
                    eta[c] = facet === :entity ? (v.mu[c] + F[lv_idx, c]) : (v.mu[c] - F[lv_idx, c])
                end
                _event_kernel!(s_scr, eta, v.tau, v.phi, m.M)
            end
            for (ci, c) in enumerate(c_idxs)
                col = (li - 1) * length(c_idxs) + ci
                eff_buf[s, col] = F[lv_idx, c]
                if inc_exp
                    rv = raw_vals[c]
                    es = 0.0
                    for k in 0:m.M[c]
                        es += rv[k + 1] * s_scr.pm[k + 1, c]
                    end
                    exp_buf[s, col] = es
                end
            end
        end
    end
    return nothing
end

function _summarize_facet_chunk(
    eff_buf,
    exp_buf,
    res::StarResult,
    facet::Symbol,
    sub_ids,
    sub_idxs,
    counts,
    c_idxs,
    interval::Float64,
    inc_exp::Bool,
)
    m = res.model
    chains = res.config.chains
    lo, hi = B._interval_probabilities(interval)
    ncols = length(sub_idxs) * length(c_idxs)
    pnames = ["$(facet)[$(sub_ids[li]),$(m.criteria[c].id)]" for li in eachindex(sub_ids) for c in c_idxs]
    post = B._posterior_summary_rows(
        eff_buf,
        pnames;
        lower = lo,
        upper = hi,
        intervals = (interval,),
        reference = 0.0,
        rope = nothing,
        rope_probability_threshold = 0.95,
    )
    mc = B._posterior_mcse_rows(eff_buf, pnames, chains; probabilities = (lo, 0.5, hi), parameter_space = :facet_location)
    dr = B._candidate_mcmc_diagnostic_rows(
        eff_buf,
        pnames,
        chains;
        parameter_space = :facet_location,
        split_chains = true,
        rhat_threshold = 1.01,
        ess_threshold = 400.0,
    )
    exp_post = inc_exp ? B._posterior_summary_rows(
        exp_buf,
        pnames;
        lower = lo,
        upper = hi,
        intervals = (interval,),
        reference = 0.0,
        rope = nothing,
        rope_probability_threshold = 0.95,
    ) : nothing
    exp_mc = inc_exp ? B._posterior_mcse_rows(
        exp_buf,
        pnames,
        chains;
        probabilities = (lo, 0.5, hi),
        parameter_space = :expected_score,
    ) : nothing
    return [
        begin
            li, ci = fldmod1(col, length(c_idxs))
            c = c_idxs[ci]
            pr = post[col]
            mr = mc[col]
            dg = dr[col]
            es_nt = inc_exp ? (;
                mean = exp_post[col].mean,
                sd = exp_post[col].sd,
                median = exp_post[col].median,
                lower = exp_post[col].lower,
                upper = exp_post[col].upper,
                mean_mcse = exp_mc[col].mean_mcse,
            ) : nothing
            (;
                facet,
                id = sub_ids[li],
                criterion = m.criteria[c].id,
                direction = m.criteria[c].direction,
                n_ratings = counts[sub_idxs[li]],
                mean = pr.mean,
                sd = pr.sd,
                median = pr.median,
                lower = pr.lower,
                upper = pr.upper,
                mean_mcse = mr.mean_mcse,
                lower_mcse = mr.quantiles[1].mcse,
                upper_mcse = mr.quantiles[3].mcse,
                rank_normalized_rhat = dg.rank_normalized_rhat,
                bulk_ess = dg.bulk_ess,
                tail_ess = dg.tail_ess,
                reference_partner_expected_score = es_nt,
            )
        end for col in 1:ncols
    ]
end

"""
    facet_summary(res::StarResult; facet=:entity, ids=nothing, criteria=nothing, include_expected_score=true, interval=0.95, chunk_size=256)

Summarize individual entity abilities (`A[i,c]`) or rater severities (`S[r,c]`) along with
reference-partner expected raw scores (Fair Averages), CrIs, MCSEs, and split-R-hat/ESS in memory-bounded chunks.
"""
function facet_summary(
    res::StarResult;
    facet::Symbol = :entity,
    ids = nothing,
    criteria = nothing,
    include_expected_score::Bool = true,
    interval::Real = 0.95,
    chunk_size::Int = 256,
)
    _verify_result(res)
    chunk_size >= 1 || throw(ArgumentError("chunk_size >= 1 required"))
    iv = Float64(interval)
    B._interval_probabilities(iv)
    sel_ids, sel_idxs, counts = _resolve_facet_selection(res.model, facet, ids; min_levels = 1)
    c_idxs = _resolve_criteria_indices(res.model, criteria)
    S = size(res.draws, 1)
    rows = NamedTuple[]
    for start_i in 1:chunk_size:length(sel_idxs)
        end_i = min(start_i + chunk_size - 1, length(sel_idxs))
        sub_ids = sel_ids[start_i:end_i]
        sub_idxs = sel_idxs[start_i:end_i]
        ncols = length(sub_idxs) * length(c_idxs)
        eff_buf = Matrix{Float64}(undef, S, ncols)
        exp_buf = include_expected_score ? Matrix{Float64}(undef, S, ncols) : Matrix{Float64}(undef, 0, 0)
        _fill_facet_chunk_draws!(eff_buf, exp_buf, res, facet, sub_idxs, c_idxs, include_expected_score)
        append!(rows, _summarize_facet_chunk(eff_buf, exp_buf, res, facet, sub_ids, sub_idxs, counts, c_idxs, iv, include_expected_score))
    end
    return _envelope(
        res,
        :facet_summary,
        (;
            facet,
            interval = iv,
            include_expected_score,
            effect_meaning = facet === :entity ? :canonical_ability_sum_to_zero : :canonical_severity_sum_to_zero,
            expected_score_conditioning = facet === :entity ? :reference_rater_zero_severity : :reference_entity_zero_ability,
            n_selected_levels = length(sel_ids),
            rows,
        ),
    )
end

function _threshold_rows_for_scale(res::StarResult, c_idxs::Vector{Int}, iv::Float64, raw_input::Bool)
    m = res.model
    S = size(res.draws, 1)
    chains = res.config.chains
    scale_label = raw_input ? :reference_profile : :raw_model
    step_draws = [Matrix{Float64}(undef, S, m.M[c]) for c in c_idxs]
    for s in 1:S
        q_s = view(res.draws, s, :)
        taus = raw_input ?
            _reference_mu_and_tau(m, q_s).tau :
            _reference_mu_and_tau(m, _transport_reference(m, q_s)).tau
        for (ci, c) in enumerate(c_idxs)
            step_draws[ci][s, :] .= taus[c]
        end
    end
    rows = NamedTuple[]
    for (ci, c) in enumerate(c_idxs), k in 1:m.M[c]
        meta = m.criteria[c]
        fixed_step = (meta.M == 1)
        cur = view(step_draws[ci], :, k)
        sum_k = _scalar_draw_summary(cur, chains, iv; space = :threshold, fixed = fixed_step)
        gap_nt = k == 1 ? nothing : _scalar_draw_summary(
            cur .- view(step_draws[ci], :, k - 1),
            chains,
            iv;
            space = :threshold_gap,
        )
        dis_nt = k == 1 ? nothing : _indicator_mean_mcse(view(step_draws[ci], :, k - 1) .> cur, chains)
        push!(
            rows,
            (;
                scale = scale_label,
                criterion = meta.id,
                step = k,
                from_raw_score = meta.canonical_to_raw[k],
                to_raw_score = meta.canonical_to_raw[k + 1],
                fixed = fixed_step,
                step_estimate = sum_k,
                adjacent_gap = gap_nt,
                disordered_probability = dis_nt,
            ),
        )
    end
    return rows
end

function _category_usage_summary(
    res::StarResult,
    c_idxs::Vector{Int},
    iv::Float64,
    min_count::Int,
    min_prop::Float64,
)
    m = res.model
    S = size(res.draws, 1)
    N = length(m.entity)
    chains = res.config.chains
    exp_sums = [zeros(Float64, S, m.M[c] + 1) for c in 1:m.D]
    s_scr = _scratch(m.M, Float64)
    eta = zeros(Float64, m.D)
    for s in 1:S
        v = _coordinates(m, view(res.draws, s, :); raw_input = false)
        @inbounds for e in 1:N
            i = m.entity[e]
            r = m.rater[e]
            for c in 1:m.D
                eta[c] = v.mu[c] + v.A[i, c] - v.S[r, c]
            end
            _event_kernel!(s_scr, eta, v.tau, v.phi, m.M)
            for c in c_idxs, k in 0:m.M[c]
                exp_sums[c][s, k + 1] += s_scr.pm[k + 1, c]
            end
        end
    end
    rows = NamedTuple[]
    for c in c_idxs, k in 0:m.M[c]
        obs_c = count(==(k), view(m.y, c, :))
        obs_p = obs_c / N
        flag = obs_c == 0 ? :unused : ((obs_c < min_count || obs_p < min_prop) ? :sparse : :ok)
        ep = _scalar_draw_summary(vec(exp_sums[c][:, k + 1] ./ N), chains, iv; space = :probability)
        push!(
            rows,
            (;
                criterion = m.criteria[c].id,
                canonical_index = k,
                raw_score = m.criteria[c].canonical_to_raw[k + 1],
                n_events = N,
                observed_count = obs_c,
                observed_proportion = obs_p,
                observed_flag = flag,
                expected_proportion = ep,
                observed_minus_expected_mean = obs_p - ep.mean,
            ),
        )
    end
    return rows
end

function _category_reference_curves(
    res::StarResult,
    c_idxs::Vector{Int},
    grid::Vector{Float64},
    iv::Float64,
)
    m = res.model
    S = size(res.draws, 1)
    chains = res.config.chains
    lo, hi = B._interval_probabilities(iv)
    s_scr = _scratch(m.M, Float64)
    eta = zeros(Float64, m.D)
    coords = [
        begin
            q_t = _transport_reference(m, view(res.draws, s, :))
            rt = _reference_mu_and_tau(m, q_t)
            phi = m.spec.include_phi ? q_t[_layout(m).phi] : zeros(Float64, m.D - 1)
            (; mu = rt.mu, tau = rt.tau, phi)
        end for s in 1:S
    ]
    ref_coords = [_reference_mu_and_tau(m, view(res.draws, s, :)) for s in 1:S]
    curve_rows = NamedTuple[]
    crossing_rows = NamedTuple[]
    for c in c_idxs
        mc = m.M[c]
        meta = m.criteria[c]
        probs = Matrix{Float64}(undef, S, mc + 1)
        for th in grid
            for s in 1:S
                v = coords[s]
                for d in 1:m.D
                    eta[d] = v.mu[d] + (d == c ? th : 0.0)
                end
                _event_kernel!(s_scr, eta, v.tau, v.phi, m.M)
                for k in 0:mc
                    probs[s, k + 1] = s_scr.pm[k + 1, c]
                end
            end
            for k in 0:mc
                col = view(probs, :, k + 1)
                push!(
                    curve_rows,
                    (;
                        criterion = meta.id,
                        ability = th,
                        canonical_index = k,
                        raw_score = meta.canonical_to_raw[k + 1],
                        mean = mean(col),
                        lower = quantile(col, lo),
                        upper = quantile(col, hi),
                    ),
                )
            end
        end
        for k in 1:mc
            cr_draws = [ref_coords[s].tau[c][k] - ref_coords[s].mu[c] for s in 1:S]
            cond_kind = (c == 1 && m.spec.reference_prior) ? :exact_reference_marginal : :midpoint_root_slice
            push!(
                crossing_rows,
                (;
                    criterion = meta.id,
                    step = k,
                    from_raw_score = meta.canonical_to_raw[k],
                    to_raw_score = meta.canonical_to_raw[k + 1],
                    conditioning = cond_kind,
                    crossing_ability = _scalar_draw_summary(cr_draws, chains, iv),
                ),
            )
        end
    end
    return (; curve_rows, crossing_rows)
end

"""
    category_summary(res::StarResult; criteria=nothing, interval=0.95, ability_grid=-3.0:0.5:3.0, min_count=5, min_proportion=0.01)

Summarize category use, reference & raw step calibrations, adjacent gaps, step-disordering
probabilities `P(step[k-1] > step[k])`, and reference-profile category probability curves/crossings.
"""
function category_summary(
    res::StarResult;
    criteria = nothing,
    interval::Real = 0.95,
    ability_grid = -3.0:0.5:3.0,
    min_count::Int = 5,
    min_proportion::Real = 0.01,
)
    _verify_result(res)
    iv = Float64(interval)
    B._interval_probabilities(iv)
    c_idxs = _resolve_criteria_indices(res.model, criteria)
    grid = ability_grid === nothing ? nothing : Float64.(collect(ability_grid))
    if grid !== nothing
        (length(grid) >= 2 && all(isfinite, grid) && all(>(0), diff(grid))) ||
            throw(ArgumentError("ability_grid must have >= 2 strictly increasing finite values"))
    end
    ref_steps = _threshold_rows_for_scale(res, c_idxs, iv, true)
    raw_steps = _threshold_rows_for_scale(res, c_idxs, iv, false)
    usage = _category_usage_summary(res, c_idxs, iv, min_count, Float64(min_proportion))
    curves = grid === nothing ? nothing : _category_reference_curves(res, c_idxs, grid, iv)
    return _envelope(
        res,
        :category_summary,
        (;
            interval = iv,
            usage,
            reference_thresholds = ref_steps,
            raw_thresholds = raw_steps,
            reference_curves = curves,
        ),
    )
end

function _extract_cohort_matrix(
    res::StarResult,
    facet::Symbol,
    criterion::AbstractString,
    ids;
    min_levels::Int = 2,
    max_cells::Int = 20_000_000,
)
    m = res.model
    S = size(res.draws, 1)
    sel_ids, sel_idxs, counts = _resolve_facet_selection(m, facet, ids; min_levels)
    big(S) * length(sel_idxs) <= max_cells ||
        throw(ArgumentError("selected cohort exceeds max_cells=$max_cells"))
    c_idx = only(_resolve_criteria_indices(m, String(criterion)))
    mat = Matrix{Float64}(undef, S, length(sel_idxs))
    for s in 1:S
        v = _coordinates(m, view(res.draws, s, :); raw_input = false)
        F = facet === :entity ? v.A : v.S
        for (j, idx) in enumerate(sel_idxs)
            mat[s, j] = F[idx, c_idx]
        end
    end
    return (; sel_ids, sel_idxs, counts, c_idx, mat)
end

function _reliability_components(values::Matrix{Float64}, weights, target::Symbol)
    target in (:absolute, :centered) || throw(ArgumentError("target must be :absolute or :centered"))
    S, N = size(values)
    (S >= 2 && N >= 2) || throw(ArgumentError("reliability requires >= 2 draws and >= 2 levels"))
    (length(weights) == N && all(w -> _is_finite_real(w) && w > 0, weights)) ||
        throw(ArgumentError("weights must be positive finite reals"))
    w = Float64.(weights)
    w ./= maximum(w)
    w ./= sum(w)
    x = copy(values)
    origin = x[1, 1]
    x .-= origin
    if target === :centered
        x .-= x * w
    end
    m = vec(mean(x; dims = 1))
    res_m = x .- m'
    v = vec(mean(abs2.(res_m); dims = 1))
    cm = m .- sum(w .* m)
    between = sum(w .* abs2.(cm))
    within = sum(w .* v)
    total = between + within
    rel = total > 0 ? between / total : missing
    infl = if total > 0
        (((within / total) .* (2 .* (res_m * (w .* cm)))) .-
            ((between / total) .* (abs2.(res_m) * w .- within))) ./ total
    else
        zeros(S)
    end
    return (;
        weights = w,
        means = target === :absolute ? (m .+ origin) : m,
        variances = v,
        between,
        within,
        total,
        reliability = rel,
        rmse = sqrt(within),
        separation_ratio_descriptive = within > 0 ? sqrt(between / within) : missing,
        influence = infl,
    )
end

function _reliability_mcse(comp, chains::Int)
    S = length(comp.influence)
    n = div(S, max(chains, 1))
    status = if ismissing(comp.reliability)
        :zero_total_variance
    elseif comp.between == 0 || comp.within == 0
        :boundary_delta_unavailable
    elseif chains < 2
        :insufficient_chains
    elseif n < 10
        :insufficient_draws
    elseif allequal(comp.influence)
        :degenerate_influence
    else
        :available
    end
    val = status === :available ? B._posterior_mcse_value(reshape(comp.influence, n, chains), Statistics.mean) : missing
    if status === :available && ismissing(val)
        status = :mcse_unavailable
    end
    return (; value = val, status, method = :mcmc_delta_influence, n_chains = chains, draws_per_chain = n)
end

"""
    reliability(res::StarResult; facet=:entity, criterion, ids=nothing, target=:centered, weights=nothing)

Compute `BayesianMGMFRM`-standard finite-cohort posterior reliability `B/(B+W)`, `rmse`,
descriptive separation ratio `sqrt(B/W)`, and chain-aware delta-method MCSE.
"""
function reliability(
    res::StarResult;
    facet::Symbol = :entity,
    criterion::AbstractString,
    ids = nothing,
    target::Symbol = :centered,
    weights = nothing,
)
    _verify_result(res)
    coh = _extract_cohort_matrix(res, facet, criterion, ids; min_levels = 2)
    w_in = weights === nothing ? ones(Float64, length(coh.sel_ids)) : collect(weights)
    comp = _reliability_components(coh.mat, w_in, target)
    mcse = _reliability_mcse(comp, res.config.chains)
    zero_var = [coh.sel_ids[i] for i in eachindex(coh.sel_ids) if comp.variances[i] == 0]
    rows = [
        (;
            id = coh.sel_ids[i],
            n_ratings = coh.counts[coh.sel_idxs[i]],
            weight = comp.weights[i],
            posterior_mean = comp.means[i],
            posterior_variance = comp.variances[i],
            empirical_zero_variance = comp.variances[i] == 0,
        ) for i in eachindex(coh.sel_ids)
    ]
    warn = res.sampling_warning || mcse.status !== :available || !isempty(zero_var)
    return _envelope(
        res,
        :reliability,
        (;
            facet,
            criterion = String(criterion),
            target,
            n_levels = length(coh.sel_ids),
            reliability = comp.reliability,
            between_variance = comp.between,
            within_variance = comp.within,
            total_variance = comp.total,
            rmse = comp.rmse,
            separation_ratio_descriptive = comp.separation_ratio_descriptive,
            mcse,
            empirical_zero_variance_ids = zero_var,
            status = warn ? :warning : :descriptive,
            scope = :finite_cohort_posterior_functional_not_design_reliability,
            rows,
        ),
    )
end

function _rank_draws(values::Matrix{Float64}, direction::Symbol, top_k)
    S, N = size(values)
    ranks = Matrix{Float64}(undef, S, N)
    tied = falses(S, N)
    certain = top_k === nothing ? nothing : falses(S, N)
    possible = top_k === nothing ? nothing : falses(S, N)
    for s in 1:S
        ord = sortperm(view(values, s, :); rev = direction === :higher)
        fp = 1
        while fp <= N
            lp = fp
            while lp < N && values[s, ord[lp + 1]] == values[s, ord[fp]]
                lp += 1
            end
            for pos in fp:lp
                i = ord[pos]
                ranks[s, i] = 0.5 * (fp + lp)
                tied[s, i] = lp > fp
                if top_k !== nothing
                    certain[s, i] = lp <= top_k
                    possible[s, i] = fp <= top_k
                end
            end
            fp = lp + 1
        end
    end
    return (; ranks, tied, certain, possible)
end

function _rank_summary(values::AbstractVector{Float64}, chains::Int, interval::Float64)
    lo, hi = B._interval_probabilities(interval)
    sorted = sort(values)
    q_at(p) = sorted[clamp(ceil(Int, p * length(sorted)), 1, length(sorted))]
    return (;
        _indicator_mean_mcse(values, chains)...,
        sd = length(values) > 1 ? std(values) : missing,
        median = q_at(0.5),
        lower = q_at(lo),
        upper = q_at(hi),
        interval_probability = interval,
        interval_method = :equal_tailed_empirical_inverse_cdf,
    )
end

"""
    ranking(res::StarResult; facet=:entity, criterion, ids=nothing, direction=:higher, top_k=nothing, interval=0.90, max_rank_cells=20_000_000)

Compute joint-draw finite-cohort posterior midranks, empirical inverse-CDF rank intervals,
and tie-bounded `top_k_probability` with chain-aware MCSE.
"""
function ranking(
    res::StarResult;
    facet::Symbol = :entity,
    criterion::AbstractString,
    ids = nothing,
    direction::Symbol = :higher,
    top_k = nothing,
    interval::Real = 0.90,
    max_rank_cells::Int = 20_000_000,
)
    _verify_result(res)
    direction in (:higher, :lower) || throw(ArgumentError("direction must be :higher or :lower"))
    iv = Float64(interval)
    B._interval_probabilities(iv)
    coh = _extract_cohort_matrix(res, facet, criterion, ids; min_levels = 2, max_cells = max_rank_cells)
    N = length(coh.sel_ids)
    chains = res.config.chains
    top_k === nothing || (_is_int_score(top_k) && 1 <= top_k <= N) ||
        throw(ArgumentError("top_k must be in 1:$N"))
    tk = top_k === nothing ? nothing : Int(top_k)
    rd = _rank_draws(coh.mat, direction, tk)
    rows = map(1:N) do i
        top_nt = tk === nothing ? nothing : begin
            fx = (tk == N)
            (;
                lower = _indicator_mean_mcse(view(rd.certain, :, i), chains; fixed = fx),
                upper = _indicator_mean_mcse(view(rd.possible, :, i), chains; fixed = fx),
                boundary_tie_probability = _indicator_mean_mcse(
                    rd.possible[:, i] .& .!rd.certain[:, i],
                    chains;
                    fixed = fx,
                ),
            )
        end
        (;
            id = coh.sel_ids[i],
            n_ratings = coh.counts[coh.sel_idxs[i]],
            rank = _rank_summary(view(rd.ranks, :, i), chains, iv),
            tie_probability = _indicator_mean_mcse(view(rd.tied, :, i), chains),
            top_k_probability = top_nt,
        )
    end
    bties = tk !== nothing && any(rd.possible .!= rd.certain)
    return _envelope(
        res,
        :ranking,
        (;
            facet,
            criterion = String(criterion),
            direction,
            top_k = tk,
            n_levels = N,
            interval_probability = iv,
            boundary_ties_observed = bties,
            scope = :conditional_finite_cohort_rank_uncertainty,
            rows,
        ),
    )
end

"""
    classification(res::StarResult; facet=:entity, criterion, ids=nothing, cutoff, pass_probability=0.5, interval=0.90)

Evaluate conditional posterior binary classification risk (`effect >= cutoff`, decision `:pass` when
`P(qualifies) >= pass_probability`) and joint-draw cohort false-pass / false-fail error expectations.
"""
function classification(
    res::StarResult;
    facet::Symbol = :entity,
    criterion::AbstractString,
    ids = nothing,
    cutoff::Real,
    pass_probability::Real = 0.5,
    interval::Real = 0.90,
)
    _verify_result(res)
    (_is_finite_real(cutoff) && _is_finite_real(pass_probability) && 0 < pass_probability < 1) ||
        throw(ArgumentError("cutoff must be finite and pass_probability strictly in (0, 1)"))
    cut = Float64(cutoff)
    pp = Float64(pass_probability)
    iv = Float64(interval)
    B._interval_probabilities(iv)
    coh = _extract_cohort_matrix(res, facet, criterion, ids; min_levels = 1)
    chains = res.config.chains
    qualifies = coh.mat .>= cut
    probs = vec(mean(qualifies; dims = 1))
    pass = probs .>= pp
    f_pass = vec(sum((.!qualifies) .& pass'; dims = 2))
    f_fail = vec(sum(qualifies .& (.!pass)'; dims = 2))
    errs = f_pass .+ f_fail
    rows = map(eachindex(coh.sel_ids)) do i
        q_i = view(qualifies, :, i)
        (;
            id = coh.sel_ids[i],
            n_ratings = coh.counts[coh.sel_idxs[i]],
            effect = _scalar_draw_summary(view(coh.mat, :, i), chains, iv),
            qualification_probability = _indicator_mean_mcse(q_i, chains),
            decision = pass[i] ? :pass : :fail,
            error_probability = _indicator_mean_mcse(pass[i] ? .!q_i : q_i, chains),
        )
    end
    cohort = (;
        expected_false_pass_count = _indicator_mean_mcse(f_pass, chains; fixed = !any(pass)),
        expected_false_fail_count = _indicator_mean_mcse(f_fail, chains; fixed = all(pass)),
        expected_error_count = _indicator_mean_mcse(errs, chains),
        probability_any_error = _indicator_mean_mcse(errs .> 0, chains),
    )
    return _envelope(
        res,
        :classification,
        (;
            facet,
            criterion = String(criterion),
            cutoff = cut,
            pass_probability = pp,
            interval_probability = iv,
            n_levels = length(coh.sel_ids),
            n_pass = count(pass),
            n_fail = count(!, pass),
            cohort,
            rows,
            scope = :conditional_posterior_risk_not_known_truth_error_rate,
        ),
    )
end
