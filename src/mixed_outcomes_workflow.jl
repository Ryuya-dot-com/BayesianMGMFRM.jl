# Lifecycle workflow, joint paired PPC, and distinct known-owner vs. new-owner prediction
# for Stage 4 MixedOutcomeTarget (and owner-aware new_owners extension for scalar population targets).

const MIXED_PPC_SCHEMA = "bayesianmgmfrm.mixed_outcome_predictive.v1"
const MIXED_PREDICTION_SCHEMA = "bayesianmgmfrm.mixed_outcome_prediction.v1"

function model_draws(t::MixedOutcomeTarget, raw)
    labels = names(t, :model)
    S_draws = size(raw, 1)
    values = Matrix{Float64}(undef, S_draws, length(labels))
    out_names = [ch.name for ch in t.outcomes]
    for (s, q) in enumerate(eachrow(raw))
        v = coordinates(t, q)
        row_vals = Float64[]
        for ob in t.owners
            b_lat = v.owners[ob.name].latent
            for d in 1:ob.D_dim
                append!(row_vals, view(b_lat, :, d))
            end
        end
        append!(row_vals, v.coefficients)
        for ob in t.owners
            ov = v.owners[ob.name]
            append!(row_vals, ov.sds)
            ob.D_dim >= 2 && append!(row_vals, ov.correlations)
            for d in 1:ob.D_dim, c in 1:length(out_names)
                le = ob.loadings[c, d]
                (ob.declaration_kind === :loaded_1d || le.kind !== :fixed) && push!(row_vals, ov.loadings[c, d])
            end
        end
        for (c, ch) in enumerate(t.outcomes)
            ov = v.outcomes[c]
            if ch.family === :ordinal
                append!(row_vals, ov.steps)
            elseif ch.family === :zero_one_inflated_beta
                push!(row_vals, ov.precision, ov.endpoint_logit, ov.upper_logit)
            elseif ch.family === :beta_binomial
                push!(row_vals, ov.precision)
            end
        end
        values[s, :] = row_vals
    end

    fixed = Set{String}()
    for ob in t.owners
        for d in 1:ob.D_dim
            ob.hyps[d] == 0 && push!(fixed, ob.D_dim == 1 ? "residual_sd[$(ob.name)]" : "residual_sd[$(ob.name),$(ob.dim_names[d])]")
        end
        if ob.D_dim >= 2 && ob.corr_kind === :fixed
            for i in 2:ob.D_dim, j in 1:(i - 1)
                push!(fixed, "correlation[$(ob.name),$(ob.dim_names[j]),$(ob.dim_names[i])]")
            end
        end
        for d in 1:ob.D_dim, c in 1:length(out_names)
            le = ob.loadings[c, d]
            ob.declaration_kind === :loaded_1d && le.kind === :fixed &&
                push!(fixed, "loading[$(ob.name),$(out_names[c]),$(ob.dim_names[d])]")
        end
    end
    for ch in t.outcomes
        ch.family === :ordinal && length(ch.categories) == 2 && push!(fixed, "steps[$(ch.name),1]")
    end
    (; names = labels, values, fixed)
end

allocation_error(t::MixedOutcomeTarget) = join(t.allocation.reasons, " ")
summary_unit(t::MixedOutcomeTarget, scale) = scale === :raw ?
    (any(ob -> !isempty(ob.corr_raw), t.owners) ? :white_normal_and_cpc_correlation : :white_standard_normal) :
    :outcome_specific_links_loadings_and_family_parameters
prediction_conditioning(::MixedOutcomeTarget) = :known_owners_and_stored_owner_attributes

function contrast_unit(t::MixedOutcomeTarget, left, right)
    # Allow contrasts within the same owner & dimension
    for ob in t.owners, d in 1:ob.D_dim
        dtag = ob.D_dim == 1 ? "" : ",$(ob.dim_names[d])]"
        valid_set = Set(ob.D_dim == 1 ? ["$(ob.name)[$(repr(id))]" for id in ob.levels] :
                                        ["$(ob.name)[$(repr(id)),$(ob.dim_names[d])]" for id in ob.levels])
        (left in valid_set && right in valid_set) && return :latent_owner_dimension_unit
    end
    # Allow contrasts between decomposed between/within coefficients on the SAME outcome
    if hasproperty(t.specification, :decomposition)
        for ch in t.outcomes, d in t.specification.decomposition.rules
            bname = "coefficient[$(ch.name),response,$(d.between)]"
            wname = "coefficient[$(ch.name),response,$(d.within)]"
            ((left == bname && right == wname) || (left == wname && right == bname)) &&
                return Symbol("$(ch.name)_link_per_decomposed_predictor_unit")
        end
    end
    throw(ArgumentError("contrasts in MixedOutcomeTarget require matching owner/dimension coordinates or decomposed predictors on the same outcome; raw parameters across distinct outcome links are not commensurable"))
end

function logprobs(::MixedOutcomeTarget, q)
    throw(ArgumentError("mixed-outcome targets combine distinct measures; use predict(spec, q) or predict(fit)"))
end

function mixed_moments(t::MixedOutcomeTarget, q::AbstractVector)
    v = coordinates(t, q); eta = _mixed_eta_matrix(t, v)
    E = length(t.person)
    out_pairs = Pair{Symbol,Any}[]
    for (c, ch) in enumerate(t.outcomes)
        ov = v.outcomes[c]
        if ch.family === :ordinal
            K = length(ch.categories); H = K - 1
            probs = zeros(Float64, E, K); exp_score = zeros(Float64, E)
            a = zeros(Float64, K)
            for e in 1:E
                a[1] = 0.0
                for h in 1:H
                    a[h + 1] = a[h] + Float64(eta[e, c]) - Float64(ov.steps[h])
                end
                z = B._logsumexp(a)
                s_mean = 0.0
                for k in 1:K
                    pk = exp(a[k] - z)
                    probs[e, k] = pk
                    s_mean += ch.categories[k] * pk
                end
                exp_score[e] = s_mean
            end
            push!(out_pairs, ch.name => (; family = :ordinal, categories = copy(ch.categories), probabilities = probs, expected_score = exp_score))
        elseif ch.family === :zero_one_inflated_beta
            lo, hi = ch.bounds; w_span = hi - lo
            prec = Float64(ov.precision); z_p = Float64(ov.endpoint_probability); h_p = Float64(ov.upper_probability)
            mu = [_sigmoid(Float64(eta[e, c])) for e in 1:E]
            wm = [_sigmoid(-Float64(eta[e, c])) for e in 1:E]
            iv = mu .* wm ./ (prec + 1.0)
            tv = (1.0 - z_p) .* iv .+ z_p * h_p * (1.0 - h_p) .+ (1.0 - z_p) * z_p .* (mu .- h_p) .^ 2
            push!(out_pairs, ch.name => (; family = :zero_one_inflated_beta, bounds = ch.bounds,
                expected_score = lo .+ w_span .* ((1.0 - z_p) .* mu .+ z_p * h_p),
                interior_mean = lo .+ w_span .* mu,
                lower_probability = fill(z_p * (1.0 - h_p), E),
                upper_probability = fill(z_p * h_p, E),
                score_sd = w_span .* sqrt.(tv)))
        else
            bb = ch.family === :beta_binomial
            prec = bb ? Float64(ov.precision) : nothing
            exp_cnt = fill(NaN, E); exp_prop = fill(NaN, E); p_zero = fill(NaN, E); p_perf = fill(NaN, E)
            for e in 1:E
                tr_val = t.table[ch.trials_col][e]
                _mixed_absent(tr_val) && continue
                nt = Int(tr_val)
                ec = Float64(eta[e, c]); p = _sigmoid(ec)
                exp_cnt[e] = nt * p; exp_prop[e] = p
                p_zero[e] = exp(first(count_cell(0, nt, ec, prec, 0.0)))
                p_perf[e] = exp(first(count_cell(nt, nt, ec, prec, 0.0)))
            end
            push!(out_pairs, ch.name => (; family = ch.family, expected_count = exp_cnt, expected_proportion = exp_prop,
                zero_probability = p_zero, perfect_probability = p_perf))
        end
    end
    (; out_pairs...)
end

function mixed_simulate(t::MixedOutcomeTarget, q, rng::AbstractRNG; complete::Bool = false)
    v = coordinates(t, q); eta = _mixed_eta_matrix(t, v)
    E = length(t.person)
    sim_cols = Dict{Symbol,Vector}()
    for (c, ch) in enumerate(t.outcomes)
        ov = v.outcomes[c]
        if ch.family === :ordinal
            K = length(ch.categories); H = K - 1
            col = Vector{Union{Missing,Int}}(missing, E)
            a = zeros(Float64, K)
            rows_to_sim = complete ? (1:E) : ch.obs_rows
            for e in rows_to_sim
                a[1] = 0.0
                for h in 1:H
                    a[h + 1] = a[h] + Float64(eta[e, c]) - Float64(ov.steps[h])
                end
                z = B._logsumexp(a)
                u = rand(rng); cum = 0.0; chosen = K
                for k in 1:K
                    cum += exp(a[k] - z)
                    if u <= cum
                        chosen = k; break
                    end
                end
                col[e] = ch.categories[chosen]
            end
            sim_cols[ch.name] = complete ? Int.(col) : col
        elseif ch.family === :zero_one_inflated_beta
            lo, hi = ch.bounds; w_span = hi - lo
            prec = Float64(ov.precision); z_p = Float64(ov.endpoint_probability); h_p = Float64(ov.upper_probability)
            col = Vector{Union{Missing,Float64}}(missing, E)
            rows_to_sim = complete ? (1:E) : ch.obs_rows
            for e in rows_to_sim
                if rand(rng) < z_p
                    col[e] = rand(rng) < h_p ? hi : lo
                else
                    ec = Float64(eta[e, c])
                    a_sh = prec * _sigmoid(ec); b_sh = prec * _sigmoid(-ec)
                    isfinite(a_sh + b_sh) && a_sh > 0 && b_sh > 0 || throw(ArgumentError("beta shapes are not representable"))
                    y01 = rand(rng, D.Beta(a_sh, b_sh))
                    yv = lo + w_span * y01
                    lo < yv < hi || throw(ArgumentError("interior beta draw rounded to a bound; review extreme priors/precision"))
                    col[e] = yv
                end
            end
            sim_cols[ch.name] = complete ? Float64.(col) : col
        else
            bb = ch.family === :beta_binomial
            prec = bb ? Float64(ov.precision) : nothing
            col = Vector{Union{Missing,Int}}(missing, E)
            rows_to_sim = complete ? (1:E) : ch.obs_rows
            for e in rows_to_sim
                tr_val = t.table[ch.trials_col][e]
                _mixed_absent(tr_val) && throw(ArgumentError("cannot simulate count outcome $(ch.name) at row $e with missing trials"))
                nt = Int(tr_val); ec = Float64(eta[e, c])
                if !bb
                    col[e] = rand(rng, D.Binomial(nt, _sigmoid(ec)))
                else
                    a_sh = prec * _sigmoid(ec); b_sh = prec * _sigmoid(-ec)
                    isfinite(a_sh + b_sh) && a_sh > 0 && b_sh > 0 || throw(ArgumentError("beta-binomial shapes are not representable"))
                    p_draw = rand(rng, D.Beta(a_sh, b_sh))
                    0.0 <= p_draw <= 1.0 || throw(ArgumentError("invalid beta probability draw"))
                    col[e] = rand(rng, D.Binomial(nt, p_draw))
                end
            end
            sim_cols[ch.name] = complete ? Int.(col) : col
        end
    end
    sim_cols
end

function simulate(t::MixedOutcomeTarget; seed = 1, q = nothing, complete::Bool = false)
    seed isa Integer && !(seed isa Bool) && 0 <= seed <= typemax(Int) || throw(ArgumentError("invalid seed"))
    rng = MersenneTwister(Int(seed))
    truth = q === nothing ? _mixed_prior_draw(t, rng) : collect(q)
    sim_outcomes = mixed_simulate(t, truth, rng; complete)
    data = deepcopy(t.table)
    for ch in t.outcomes
        data[ch.score_col] = sim_outcomes[ch.name]
    end
    (; seed = Int(seed), truth, simulated = data, outcomes = sim_outcomes,
       measure = :mixed_outcome_event_joint_density_and_mass)
end

function _avg_ranks(x::AbstractVector{Float64})
    n = length(x); perm = sortperm(x); r = Vector{Float64}(undef, n)
    i = 1
    while i <= n
        j = i
        while j < n && x[perm[j + 1]] == x[perm[i]]
            j += 1
        end
        avg = (i + j) / 2.0
        for k in i:j
            r[perm[k]] = avg
        end
        i = j + 1
    end
    r
end

function _paired_association_stats(x::AbstractVector{Float64}, y::AbstractVector{Float64})
    n = length(x)
    n >= 2 || return (; centered_covariance = nothing, pearson_r = nothing, spearman_rho = nothing)
    mx = mean(x); my = mean(y)
    dx = x .- mx; dy = y .- my
    cov_xy = sum(dx .* dy) / n
    sx = sqrt(sum(abs2, dx) / n); sy = sqrt(sum(abs2, dy) / n)
    pr = (sx > 0 && sy > 0) ? clamp(cov_xy / (sx * sy), -1.0, 1.0) : nothing
    rx = _avg_ranks(x); ry = _avg_ranks(y)
    drx = rx .- mean(rx); dry = ry .- mean(ry)
    srx = sqrt(sum(abs2, drx) / n); sry = sqrt(sum(abs2, dry) / n)
    sr = (srx > 0 && sry > 0) ? clamp((sum(drx .* dry) / n) / (srx * sry), -1.0, 1.0) : nothing
    (; centered_covariance = cov_xy, pearson_r = pr, spearman_rho = sr)
end

function _outcome_numeric_for_pair(ch::MixedOutcomeChannel, col_vals, rows::Vector{Int}, trials_vec::Vector{Int})
    if ch.family in (:binomial, :beta_binomial)
        return Float64[Float64(col_vals[e]) / Float64(trials_vec[e]) for e in rows]
    end
    Float64[Float64(col_vals[e]) for e in rows]
end

function _outcome_marginal_metrics(ch::MixedOutcomeChannel)
    if ch.family === :ordinal
        return [:mean_score; [Symbol("category_rate_$(k)") for k in ch.categories]]
    elseif ch.family === :zero_one_inflated_beta
        return [:lower_rate, :upper_rate, :mean_score, :sd_score, :interior_mean]
    else
        return [:zero_rate, :perfect_rate, :mean_count, :mean_proportion, :sd_proportion]
    end
end

function _outcome_marginal_stats(ch::MixedOutcomeChannel, col_vals, rows::Vector{Int}, trials_vec::Vector{Int})
    isempty(rows) && return Dict{Symbol,Union{Nothing,Float64}}()
    d = Dict{Symbol,Union{Nothing,Float64}}()
    if ch.family === :ordinal
        ys = Int[Int(col_vals[e]) for e in rows]
        d[:mean_score] = mean(ys)
        for k in ch.categories
            d[Symbol("category_rate_$(k)")] = mean(ys .== k)
        end
    elseif ch.family === :zero_one_inflated_beta
        ys = Float64[Float64(col_vals[e]) for e in rows]
        lo, hi = ch.bounds
        inside = ys[(lo .< ys) .& (ys .< hi)]
        d[:lower_rate] = mean(ys .== lo)
        d[:upper_rate] = mean(ys .== hi)
        d[:mean_score] = mean(ys)
        d[:sd_score] = std(ys; corrected = false)
        d[:interior_mean] = isempty(inside) ? nothing : mean(inside)
    else
        ys = Int[Int(col_vals[e]) for e in rows]
        ns = Int[trials_vec[e] for e in rows]
        props = ys ./ ns
        d[:zero_rate] = mean(ys .== 0)
        d[:perfect_rate] = mean(ys .== ns)
        d[:mean_count] = mean(ys)
        d[:mean_proportion] = mean(props)
        d[:sd_proportion] = std(props; corrected = false)
    end
    d
end

function mixed_check(t::MixedOutcomeTarget; fit = nothing, ndraws = 100, seed = 1, groupby = nothing, interval = 0.95)
    ndraws isa Integer && !(ndraws isa Bool) && ndraws > 0 || throw(ArgumentError("ndraws must be positive"))
    seed isa Integer && !(seed isa Bool) && 0 <= seed <= typemax(Int) || throw(ArgumentError("invalid seed"))
    lo, hi = interval_bounds(interval)
    groupby === nothing || groupby in (:person, keys(t.columns.facets)...) || throw(ArgumentError("groupby must be a declared owner"))
    E = length(t.person); M = length(t.outcomes)
    ids = groupby === nothing ? ones(Int, E) : _owner_index(t, groupby)
    labels = groupby === nothing ? Any["all"] : _owner_levels(t, groupby)
    group_rows = [findall(==(g), ids) for g in eachindex(labels)]
    all(!isempty, group_rows) || throw(ArgumentError("empty predictive group"))

    # Precompute outcome x group observed row subsets
    marg_specs = Tuple{Int,Int,Symbol}[]
    obs_rows_og = Matrix{Vector{Int}}(undef, M, length(labels))
    for (c, ch) in enumerate(t.outcomes)
        m_list = _outcome_marginal_metrics(ch)
        for g in eachindex(labels)
            sub = [e for e in group_rows[g] if ch.observed[e]]
            obs_rows_og[c, g] = sub
            isempty(sub) && continue
            for m_sym in m_list
                push!(marg_specs, (c, g, m_sym))
            end
        end
    end

    # Precompute co-observed pairs (c1 < c2) across whole event table (and per group when groupby !== nothing)
    pair_specs = NamedTuple[]
    for c1 in 1:M, c2 in (c1 + 1):M
        co_all = [e for e in 1:E if t.outcomes[c1].observed[e] && t.outcomes[c2].observed[e]]
        length(co_all) >= 2 && push!(pair_specs, (; c1, c2, group = "all", rows = co_all))
        if groupby !== nothing
            for (g, glabel) in enumerate(labels)
                co_g = [e for e in group_rows[g] if t.outcomes[c1].observed[e] && t.outcomes[c2].observed[e]]
                length(co_g) >= 2 && push!(pair_specs, (; c1, c2, group = repr(glabel), rows = co_g))
            end
        end
    end
    pair_metrics = (:pearson_r, :spearman_rho, :centered_covariance)

    rng = MersenneTwister(Int(seed))
    draw_indices = fit === nothing ? Int[] : rand(rng, axes(fit.record.run.draws, 1), Int(ndraws))
    marg_vals = Matrix{Union{Nothing,Float64}}(nothing, Int(ndraws), length(marg_specs))
    pair_vals = Array{Union{Nothing,Float64}}(nothing, Int(ndraws), length(pair_specs), length(pair_metrics))
    failures = NamedTuple[]

    for s in 1:Int(ndraws)
        q = fit === nothing ? _mixed_prior_draw(t, rng) : view(fit.record.run.draws, draw_indices[s], :)
        rep_outcomes = try
            mixed_simulate(t, q, rng; complete = false)
        catch err
            err isa ArgumentError && err.msg in (
                "beta shapes are not representable",
                "interior beta draw rounded to a bound; review extreme priors/precision",
                "beta-binomial shapes are not representable",
                "invalid beta probability draw",
            ) || rethrow()
            push!(failures, (; replica = s, reason = err.msg)); continue
        end

        # Fill marginal stats
        stat_cache = Dict{Tuple{Int,Int},Dict{Symbol,Union{Nothing,Float64}}}()
        for (k_idx, (c, g, m_sym)) in enumerate(marg_specs)
            st = get!(stat_cache, (c, g)) do
                ch = t.outcomes[c]
                _outcome_marginal_stats(ch, rep_outcomes[ch.name], obs_rows_og[c, g], ch.trials)
            end
            marg_vals[s, k_idx] = st[m_sym]
        end

        # Fill within-event paired outcome stats
        for (p_idx, ps) in enumerate(pair_specs)
            ch1 = t.outcomes[ps.c1]; ch2 = t.outcomes[ps.c2]
            x1 = _outcome_numeric_for_pair(ch1, rep_outcomes[ch1.name], ps.rows, ch1.trials)
            x2 = _outcome_numeric_for_pair(ch2, rep_outcomes[ch2.name], ps.rows, ch2.trials)
            pst = _paired_association_stats(x1, x2)
            for (m_i, pm) in enumerate(pair_metrics)
                pair_vals[s, p_idx, m_i] = getproperty(pst, pm)
            end
        end
    end

    # Summarize marginal cells
    obs_stat_cache = Dict{Tuple{Int,Int},Dict{Symbol,Union{Nothing,Float64}}}()
    cells = NamedTuple[]
    for (k_idx, (c, g, m_sym)) in enumerate(marg_specs)
        ch = t.outcomes[c]; sub = obs_rows_og[c, g]
        obs_val = if fit === nothing
            nothing
        else
            ost = get!(obs_stat_cache, (c, g)) do
                _outcome_marginal_stats(ch, t.table[ch.score_col], sub, ch.trials)
            end
            ost[m_sym]
        end
        x = Float64[v for v in marg_vals[:, k_idx] if v !== nothing]
        push!(cells, (; outcome = ch.name, family = ch.family, label = repr(labels[g]), metric = m_sym,
            n = length(sub), defined_replicas = length(x), observed = obs_val,
            median = isempty(x) ? nothing : median(x),
            lower = isempty(x) ? nothing : quantile(x, lo),
            upper = isempty(x) ? nothing : quantile(x, hi)))
    end

    # Summarize paired within-event cells
    paired_cells = NamedTuple[]
    for (p_idx, ps) in enumerate(pair_specs)
        ch1 = t.outcomes[ps.c1]; ch2 = t.outcomes[ps.c2]
        obs_pst = if fit === nothing
            (; centered_covariance = nothing, pearson_r = nothing, spearman_rho = nothing)
        else
            ox1 = _outcome_numeric_for_pair(ch1, t.table[ch1.score_col], ps.rows, ch1.trials)
            ox2 = _outcome_numeric_for_pair(ch2, t.table[ch2.score_col], ps.rows, ch2.trials)
            _paired_association_stats(ox1, ox2)
        end
        for (m_i, pm) in enumerate(pair_metrics)
            x = Float64[v for v in pair_vals[:, p_idx, m_i] if v !== nothing]
            push!(paired_cells, (; outcome_left = ch1.name, outcome_right = ch2.name, group = ps.group,
                metric = pm, n_co_observed = length(ps.rows), defined_replicas = length(x),
                observed = getproperty(obs_pst, pm),
                median = isempty(x) ? nothing : median(x),
                lower = isempty(x) ? nothing : quantile(x, lo),
                upper = isempty(x) ? nothing : quantile(x, hi)))
        end
    end

    failure_warnings = isempty(failures) ? String[] : [
        "$(length(failures)) of $ndraws replications failed numerical representation. Intervals condition on successfully represented replicas; no values were clipped or redrawn."
    ]
    (; schema = MIXED_PPC_SCHEMA,
       kind = fit === nothing ? :prior_predictive : :posterior_predictive,
       cells, paired_cells, groupby, interval = Float64(interval), ndraws = Int(ndraws), seed = Int(seed),
       draw_indices, numerical_failures = failures, replications_complete = isempty(failures),
       interval_conditioning = isempty(failures) ? :requested_predictive_distribution : :numerically_representable_replicas_only,
       conditioning = fit === nothing ? :declared_design_not_scores : prediction_conditioning(t),
       target_identity = B._cache_hash(record(t)),
       source_sample_content_hash = fit === nothing ? nothing : fit.record.content_hash,
       qualification = fit === nothing ? nothing : qualify(fit),
       warnings = [design(t).warnings; failure_warnings;
           "Marginal PPC cells do not test conditional within-event independence; inspect paired_cells (pearson_r, spearman_rho, centered_covariance across co-observed event pairs)."],
       scientific_acceptance = false)
end

prior_check(t::MixedOutcomeTarget; kwargs...) = mixed_check(t; kwargs...)

function check_mixed_report(rep)
    interval_bounds(rep.interval)
    !isempty(rep.cells) || throw(ArgumentError("empty mixed-outcome report"))
    for r in rep.cells
        if r.lower !== nothing || r.upper !== nothing
            isfinite(r.lower) && isfinite(r.upper) && r.lower <= r.upper || throw(ArgumentError("invalid mixed-outcome interval"))
        end
    end
    if rep.schema == MIXED_PPC_SCHEMA && hasproperty(rep, :paired_cells)
        for r in rep.paired_cells
            if r.lower !== nothing || r.upper !== nothing
                isfinite(r.lower) && isfinite(r.upper) && r.lower <= r.upper || throw(ArgumentError("invalid paired-outcome PPC interval"))
            end
        end
    end
    rep
end

# Owner-aware prediction design & strict C6 known-owner vs. new-owner validation
function _validate_new_owners_list(new_owners, all_owner_syms::Vector{Symbol}, mode::Symbol, data, seed)
    if mode === :known_owners
        isempty(new_owners) || throw(ArgumentError("new_owners can only be supplied when mode=:new_owners"))
        return Symbol[]
    elseif mode === :new_owners
        data !== nothing || throw(ArgumentError("mode=:new_owners requires explicit prediction data"))
        seed isa Integer && !(seed isa Bool) && 0 <= seed <= typemax(Int) ||
            throw(ArgumentError("mode=:new_owners requires an explicit nonnegative integer seed for population draws"))
        nos = Symbol[Symbol(x) for x in new_owners]
        !isempty(nos) && allunique(nos) && all(x -> x in all_owner_syms, nos) ||
            throw(ArgumentError("new_owners must name one or more distinct declared owners from $all_owner_syms"))
        return nos
    end
    throw(ArgumentError("prediction mode must be :known_owners or :new_owners"))
end

function mixed_predict(t::MixedOutcomeTarget, f::Fit; data = nothing, rows = nothing, outcomes = nothing,
        interval = 0.95, mode::Symbol = :known_owners, new_owners = (), seed = nothing,
        include_predictive::Bool = false)
    lo, hi = interval_bounds(interval)
    all_owner_syms = [ob.name for ob in t.owners]
    nos = _validate_new_owners_list(new_owners, all_owner_syms, mode, data, seed)
    new_set = Set(nos)
    include_predictive && (seed === nothing || !(seed isa Integer) || seed isa Bool || seed < 0) &&
        throw(ArgumentError("include_predictive=true requires a nonnegative integer seed"))

    # Hierarchy check: if :person is new and performance is a declared facet, that performance facet must also be new
    if :person in new_set && t.columns.performance !== nothing
        perf_facets = [b.name for b in t.facets if b.column === t.columns.performance]
        for pf in perf_facets
            pf in new_set || throw(ArgumentError("predicting for a new :person requires declaring performance facet $(repr(pf)) in new_owners as well"))
        end
    end

    # Select outcomes
    req_outcomes = if outcomes === nothing
        [ch.name for ch in t.outcomes]
    else
        os = Symbol[Symbol(x) for x in outcomes]
        !isempty(os) && allunique(os) && all(o -> any(ch -> ch.name === o, t.outcomes), os) ||
            throw(ArgumentError("outcomes must select distinct declared outcome names"))
        os
    end

    # Build prediction event table & owner index mappings
    src_table = data === nothing ? t.table : data
    E_pred = length(B._column(src_table, t.columns.person))
    E_pred > 0 || throw(ArgumentError("prediction data cannot be empty"))
    ix = rows === nothing ? collect(1:E_pred) : collect(Int, rows)
    !isempty(ix) && allunique(ix) && all(r -> 1 <= r <= E_pred, ix) ||
        throw(ArgumentError("rows must select distinct valid prediction row indices"))
    N_sel = length(ix)

    # Map each owner on selected rows: for known owners, index into 1..L_o; for new owners, index into 1..G_new
    owner_sel_idx = Vector{Vector{Int}}(undef, length(t.owners))
    owner_new_levels = Vector{Vector{Any}}(undef, length(t.owners))
    raw_pred_ids = Dict{Symbol,Vector}()

    for (oi, ob) in enumerate(t.owners)
        col_sym = ob.name === :person ? t.columns.person : only(b.column for b in t.facets if b.name === ob.name)
        cvals = collect(B._column(src_table, col_sym))
        B._check_length!(E_pred, cvals, col_sym)
        sel_vals = cvals[ix]
        _labels(sel_vals, ob.name) # check valid nonmissing label types
        raw_pred_ids[col_sym] = sel_vals
        train_map = Dict(lvl => j for (j, lvl) in enumerate(ob.levels))
        if ob.name in new_set
            for v_id in sel_vals
                haskey(train_map, v_id) &&
                    throw(ArgumentError("new_owners column $(ob.name) contains stored training ID $(repr(v_id)); supply fresh IDs for new owners or use mode=:known_owners"))
            end
            n_idx, n_levs = _labels(sel_vals, ob.name)
            owner_sel_idx[oi] = n_idx
            owner_new_levels[oi] = n_levs
        else
            k_idx = Vector{Int}(undef, N_sel)
            for (pos, v_id) in enumerate(sel_vals)
                haskey(train_map, v_id) ||
                    throw(ArgumentError("unknown $(ob.name) ID $(repr(v_id)) under mode=:known_owners; zero-effect substitution is refused. Declare mode=:new_owners, new_owners=($(repr(ob.name)), ...), and seed=... to integrate over the population distribution"))
                k_idx[pos] = train_map[v_id]
            end
            owner_sel_idx[oi] = k_idx
            owner_new_levels[oi] = Any[]
        end
    end

    # Ownership consistency check for performance -> person when performance column is present
    if t.columns.performance !== nothing && data !== nothing
        pcol = t.columns.performance; per_col = t.columns.person
        pvals = collect(B._column(src_table, pcol))[ix]
        per_vals = raw_pred_ids[per_col]
        # Consistent within prediction data
        seen_perf = Dict{Any,Any}()
        for pos in 1:N_sel
            get!(seen_perf, pvals[pos], per_vals[pos]) == per_vals[pos] ||
                throw(ArgumentError("a performance ID belongs to multiple persons in prediction data"))
        end
        # If performance owner is known, must match stored person
        perf_facets = [b.name for b in t.facets if b.column === pcol]
        if isempty(perf_facets) || !(only(perf_facets) in new_set)
            known_links = Dict(zip(t.table[pcol], t.table[per_col]))
            for pos in 1:N_sel
                haskey(known_links, pvals[pos]) && known_links[pvals[pos]] == per_vals[pos] ||
                    throw(ArgumentError("known-performance prediction requires stored performance-to-person ownership"))
            end
        end
    end

    # Evaluate predictor term values on selected rows
    derived_pred = Dict{Symbol,Vector{Float64}}()
    if data !== nothing && hasproperty(t.specification, :decomposition)
        # If performance & person are known, reuse prediction_decomposition; if new_owners, compute decomposition across supplied data!
        if isempty(new_set)
            # Build full-data identity for prediction_decomposition
            p_all, _ = _labels(collect(B._column(src_table, t.columns.person)), :person, t.people)
            b_all = [Block(b.name, b.column, b.levels, first(_labels(collect(B._column(src_table, b.column)), b.name, b.levels)), 0.0, 0.0, 1:0) for b in t.facets]
            ids_tmp = (; table = Dict(t.columns.person => collect(B._column(src_table, t.columns.person)),
                (b.column => collect(B._column(src_table, b.column)) for b in t.facets)...,
                (t.columns.performance === nothing ? () : (t.columns.performance => collect(B._column(src_table, t.columns.performance)),))...),
                columns = t.columns, person = p_all, people = t.people, facets = b_all)
            d_full = prediction_decomposition(t, ids_tmp, src_table)
            for (k, v) in d_full; derived_pred[k] = Float64.(v[ix]); end
        else
            p_all, ps_all = _labels(collect(B._column(src_table, t.columns.person)), :person)
            b_all = [begin i_b, l_b = _labels(collect(B._column(src_table, b.column)), b.name); Block(b.name, b.column, l_b, i_b, 0.0, 0.0, 1:0) end for b in t.facets]
            raw_tmp = Dict{Symbol,Vector}(t.columns.person => collect(B._column(src_table, t.columns.person)))
            for b in t.facets; raw_tmp[b.column] = collect(B._column(src_table, b.column)); end
            t.columns.performance !== nothing && (raw_tmp[t.columns.performance] = collect(B._column(src_table, t.columns.performance)))
            ids_tmp = (; table = raw_tmp, columns = t.columns, person = p_all, people = ps_all, facets = b_all)
            rules = (;(d.source => (; between = d.between, within = d.within) for d in t.specification.decomposition.rules)...)
            d_full, _ = decompose_predictors(ids_tmp, src_table, rules)
            for (k, v) in d_full; derived_pred[k] = Float64.(v[ix]); end
        end
    end

    term_pred_vals = Vector{Vector{Float64}}(undef, length(t.terms))
    for (ti, tm) in enumerate(t.terms)
        if tm.column === nothing
            term_pred_vals[ti] = ones(Float64, N_sel)
        elseif data === nothing
            term_pred_vals[ti] = tm.values[ix]
        else
            x_sel = haskey(derived_pred, tm.column) ? derived_pred[tm.column] : _numeric_column(src_table, tm.column, E_pred)[ix]
            if tm.owner === :response
                term_pred_vals[ti] = x_sel
            else
                oi = only(findall(ob -> ob.name === tm.owner, t.owners))
                osgn = tm.owner === :person ? 1.0 : -1.0
                if tm.owner in new_set
                    # Check constant within each new owner ID in selected rows
                    seen_cov = Dict{Int,Float64}()
                    for pos in 1:N_sel
                        gid = owner_sel_idx[oi][pos]
                        val_prev = get!(seen_cov, gid, x_sel[pos])
                        val_prev == x_sel[pos] || throw(ArgumentError("new $(tm.owner) predictor $(tm.column) varies within the same new ID"))
                    end
                    term_pred_vals[ti] = osgn .* x_sel
                else
                    for pos in 1:N_sel
                        kid = owner_sel_idx[oi][pos]
                        tm.owner_values[kid] == x_sel[pos] ||
                            throw(ArgumentError("known-owner prediction changes stored $(tm.owner) attribute $(tm.column)"))
                    end
                    term_pred_vals[ti] = osgn .* x_sel
                end
            end
        end
    end

    # Check count trials for requested count outcomes on selected rows
    trials_sel = Dict{Symbol,Vector{Int}}()
    for oname in req_outcomes
        ch = only(c for c in t.outcomes if c.name === oname)
        if ch.family in (:binomial, :beta_binomial)
            tvals = collect(B._column(src_table, ch.trials_col))[ix]
            trials_sel[oname] = count_integers(tvals, Symbol("$(oname)_trials"); positive = true)
        end
    end

    S_draws = size(f.record.run.draws, 1)
    M = length(t.outcomes)
    rng = (mode === :new_owners || include_predictive) ? MersenneTwister(Int(seed)) : nothing

    # Pre-allocate draw-wise linear predictor storage: S_draws x N_sel x length(req_outcomes)
    req_c_indices = [only(findall(ch -> ch.name === oname, t.outcomes)) for oname in req_outcomes]
    eta_draws = zeros(Float64, S_draws, N_sel, length(req_outcomes))
    out_param_draws = [Vector{NamedTuple}(undef, S_draws) for _ in req_outcomes]

    for (s, q) in enumerate(eachrow(f.record.run.draws))
        v = coordinates(t, q)
        for (ri, c) in enumerate(req_c_indices)
            out_param_draws[ri][s] = v.outcomes[c]
        end
        # Accumulate owner contributions (known posterior vs. freshly drawn population for new_owners)
        for (oi, ob) in enumerate(t.owners)
            ov = v.owners[ob.name]; sgn = ob.sign
            proj_mat = if ob.name in new_set
                G_new = length(owner_new_levels[oi])
                z_new = randn(rng, G_new, ob.D_dim)
                b_new = (z_new * transpose(ov.L)) .* reshape(ov.sds, 1, ob.D_dim)
                b_new * transpose(ov.loadings) # G_new x M
            else
                ov.projected # L_o x M
            end
            s_idx = owner_sel_idx[oi]
            for (ri, c) in enumerate(req_c_indices)
                dsgn = t.outcomes[c].dir_sign
                for pos in 1:N_sel
                    eta_draws[s, pos, ri] += dsgn * sgn * proj_mat[s_idx[pos], c]
                end
            end
        end
        # Accumulate fixed/covariate terms
        for (ti, tm) in enumerate(t.terms)
            ri = findfirst(==(tm.outcome_idx), req_c_indices)
            ri === nothing && continue
            dsgn = t.outcomes[tm.outcome_idx].dir_sign
            bval = v.coefficients[ti]; x_sel = term_pred_vals[ti]
            for pos in 1:N_sel
                eta_draws[s, pos, ri] += dsgn * bval * x_sel[pos]
            end
        end
    end

    # Summarize per-(row, outcome, metric) in original observed units + MCSE + optional predictive intervals
    cells = NamedTuple[]; precision = NamedTuple[]; predictive_cells = NamedTuple[]
    for (ri, c) in enumerate(req_c_indices)
        ch = t.outcomes[c]
        if ch.family === :ordinal
            K = length(ch.categories); H = K - 1
            m_names = ["expected_score"; ["category_probability[$(ch.categories[k])]" for k in 1:K]]
            for pos in 1:N_sel
                vals = zeros(Float64, S_draws, K + 1)
                sim_y = include_predictive ? Vector{Int}(undef, S_draws) : Int[]
                a = zeros(Float64, K)
                for s in 1:S_draws
                    ov = out_param_draws[ri][s]; ec = eta_draws[s, pos, ri]
                    a[1] = 0.0
                    for h in 1:H; a[h + 1] = a[h] + ec - ov.steps[h]; end
                    z = B._logsumexp(a); es = 0.0
                    for k in 1:K
                        pk = exp(a[k] - z)
                        vals[s, k + 1] = pk
                        es += ch.categories[k] * pk
                    end
                    vals[s, 1] = es
                    if include_predictive
                        u = rand(rng); cum = 0.0; chosen = K
                        for k in 1:K
                            cum += vals[s, k + 1]
                            if u <= cum; chosen = k; break; end
                        end
                        sim_y[s] = ch.categories[chosen]
                    end
                end
                x_es = view(vals, :, 1)
                push!(cells, (; row = ix[pos], outcome = ch.name, family = :ordinal, metric = :expected_score,
                    category = nothing, mean = mean(x_es), median = median(x_es),
                    lower = quantile(x_es, lo), upper = quantile(x_es, hi), unit = :category_score))
                for k in 1:K
                    xk = view(vals, :, k + 1)
                    push!(cells, (; row = ix[pos], outcome = ch.name, family = :ordinal, metric = :category_probability,
                        category = ch.categories[k], mean = mean(xk), median = median(xk),
                        lower = quantile(xk, lo), upper = quantile(xk, hi), unit = :probability))
                end
                append!(precision, [(; row = ix[pos], outcome = ch.name, r...) for r in B._posterior_mcse_rows(
                    vals, m_names, f.record.run.controls.chains; probabilities = (lo, hi), parameter_space = :mixed_prediction)])
                if include_predictive
                    push!(predictive_cells, (; row = ix[pos], outcome = ch.name, family = :ordinal,
                        mean = mean(sim_y), median = Float64(median(sim_y)),
                        lower = Float64(quantile(sim_y, lo)), upper = Float64(quantile(sim_y, hi)), unit = :category_score))
                end
            end
        elseif ch.family === :zero_one_inflated_beta
            blo, bhi = ch.bounds; w_span = bhi - blo
            b_metrics = (:expected_score, :interior_mean, :lower_probability, :upper_probability)
            for pos in 1:N_sel
                vals = zeros(Float64, S_draws, 4)
                sim_y = Float64[]
                for s in 1:S_draws
                    ov = out_param_draws[ri][s]; ec = eta_draws[s, pos, ri]
                    mu = _sigmoid(ec); z_p = ov.endpoint_probability; h_p = ov.upper_probability
                    vals[s, 1] = blo + w_span * ((1.0 - z_p) * mu + z_p * h_p)
                    vals[s, 2] = blo + w_span * mu
                    vals[s, 3] = z_p * (1.0 - h_p)
                    vals[s, 4] = z_p * h_p
                    if include_predictive
                        if rand(rng) < z_p
                            push!(sim_y, rand(rng) < h_p ? bhi : blo)
                        else
                            a_sh = ov.precision * mu; b_sh = ov.precision * _sigmoid(-ec)
                            if isfinite(a_sh + b_sh) && a_sh > 0 && b_sh > 0
                                push!(sim_y, blo + w_span * rand(rng, D.Beta(a_sh, b_sh)))
                            end
                        end
                    end
                end
                for (mj, mk) in enumerate(b_metrics)
                    xv = view(vals, :, mj)
                    push!(cells, (; row = ix[pos], outcome = ch.name, family = :zero_one_inflated_beta, metric = mk,
                        category = nothing, mean = mean(xv), median = median(xv),
                        lower = quantile(xv, lo), upper = quantile(xv, hi), unit = bounded_metric_unit(mk)))
                end
                append!(precision, [(; row = ix[pos], outcome = ch.name, r...) for r in B._posterior_mcse_rows(
                    vals, string.(collect(b_metrics)), f.record.run.controls.chains; probabilities = (lo, hi), parameter_space = :mixed_prediction)])
                if include_predictive && !isempty(sim_y)
                    push!(predictive_cells, (; row = ix[pos], outcome = ch.name, family = :zero_one_inflated_beta,
                        mean = mean(sim_y), median = median(sim_y),
                        lower = quantile(sim_y, lo), upper = quantile(sim_y, hi), unit = :original_score,
                        defined_draws = length(sim_y)))
                end
            end
        else
            bb = ch.family === :beta_binomial
            c_metrics = (:expected_count, :expected_proportion, :zero_probability, :perfect_probability)
            t_vec = trials_sel[ch.name]
            for pos in 1:N_sel
                nt = t_vec[pos]
                vals = zeros(Float64, S_draws, 4)
                sim_y = Float64[]
                for s in 1:S_draws
                    ov = out_param_draws[ri][s]; ec = eta_draws[s, pos, ri]
                    prec = bb ? ov.precision : nothing
                    p = _sigmoid(ec)
                    vals[s, 1] = nt * p
                    vals[s, 2] = p
                    vals[s, 3] = exp(first(count_cell(0, nt, ec, prec, 0.0)))
                    vals[s, 4] = exp(first(count_cell(nt, nt, ec, prec, 0.0)))
                    if include_predictive
                        if !bb
                            push!(sim_y, Float64(rand(rng, D.Binomial(nt, p))))
                        else
                            a_sh = prec * p; b_sh = prec * _sigmoid(-ec)
                            if isfinite(a_sh + b_sh) && a_sh > 0 && b_sh > 0
                                p_draw = rand(rng, D.Beta(a_sh, b_sh))
                                0.0 <= p_draw <= 1.0 && push!(sim_y, Float64(rand(rng, D.Binomial(nt, p_draw))))
                            end
                        end
                    end
                end
                for (mj, mk) in enumerate(c_metrics)
                    xv = view(vals, :, mj)
                    push!(cells, (; row = ix[pos], outcome = ch.name, family = ch.family, metric = mk,
                        category = nothing, trials = nt, mean = mean(xv), median = median(xv),
                        lower = quantile(xv, lo), upper = quantile(xv, hi),
                        unit = mk === :expected_count ? :success_count : :probability))
                end
                append!(precision, [(; row = ix[pos], outcome = ch.name, r...) for r in B._posterior_mcse_rows(
                    vals, string.(collect(c_metrics)), f.record.run.controls.chains; probabilities = (lo, hi), parameter_space = :mixed_prediction)])
                if include_predictive && !isempty(sim_y)
                    push!(predictive_cells, (; row = ix[pos], outcome = ch.name, family = ch.family, trials = nt,
                        mean = mean(sim_y), median = median(sim_y),
                        lower = quantile(sim_y, lo), upper = quantile(sim_y, hi), unit = :success_count,
                        defined_draws = length(sim_y)))
                end
            end
        end
    end

    cond_sym = mode === :known_owners ? :known_owners_and_stored_owner_attributes :
               :new_declared_owners_population_drawn_known_other_owners
    itarget = mode === :known_owners ? :posterior_expected_outcome_given_known_owners :
              :new_owner_conditional_expectation_or_probability
    mode_warn = mode === :known_owners ?
        "Known-owner prediction conditions on fitted posterior owner effects; do not interpret as generalization to unseen speakers, recordings, or listeners." :
        "New-owner prediction draws fresh latent effects from the fitted population distributions for $(nos) (seed = $(Int(seed))); zero-effect substitution was NOT used."

    rep = (; schema = MIXED_PREDICTION_SCHEMA, kind = :prediction, mode, new_owners = nos,
        seed = seed === nothing ? nothing : Int(seed),
        outcomes = req_outcomes, rows = ix, interval = Float64(interval),
        cells, mcse = precision,
        conditioning = cond_sym, interval_target = itarget,
        qualification = qualify(f),
        source_sample_content_hash = f.record.content_hash,
        target_identity = f.record.target_identity,
        warnings = [design(t).warnings; mode_warn],
        scientific_acceptance = false)
    include_predictive ? merge(rep, (; predictive_cells)) : rep
end

function scalar_new_owner_predict(t::Union{BoundedTarget,CountTarget}, f::Fit;
        data, rows = nothing, interval = 0.95, new_owners = (), seed = nothing, metrics = nothing)
    lo, hi = interval_bounds(interval)
    all_owner_syms = [:person; [b.name for b in t.facets]]
    nos = _validate_new_owners_list(new_owners, all_owner_syms, :new_owners, data, seed)
    new_set = Set(nos)

    if :person in new_set && t.columns.performance !== nothing
        for b in t.facets
            b.column === t.columns.performance && !(b.name in new_set) &&
                throw(ArgumentError("predicting for a new :person requires declaring performance facet $(repr(b.name)) in new_owners as well"))
        end
    end

    E_pred = length(B._column(data, t.columns.person))
    E_pred > 0 || throw(ArgumentError("prediction data cannot be empty"))
    ix = rows === nothing ? collect(1:E_pred) : collect(Int, rows)
    !isempty(ix) && allunique(ix) && all(r -> 1 <= r <= E_pred, ix) ||
        throw(ArgumentError("rows must select distinct valid prediction row indices"))
    N_sel = length(ix)

    owner_sel_idx = Dict{Symbol,Vector{Int}}()
    owner_new_count = Dict{Symbol,Int}()
    for oname in all_owner_syms
        col_sym = oname === :person ? t.columns.person : only(b.column for b in t.facets if b.name === oname)
        cvals = collect(B._column(data, col_sym))
        B._check_length!(E_pred, cvals, col_sym)
        sel_vals = cvals[ix]
        _labels(sel_vals, oname)
        tlevs = _owner_levels(t, oname)
        tmap = Dict(lvl => j for (j, lvl) in enumerate(tlevs))
        if oname in new_set
            for v_id in sel_vals
                haskey(tmap, v_id) &&
                    throw(ArgumentError("new_owners column $oname contains stored training ID $(repr(v_id)); supply fresh IDs or use mode=:known_owners"))
            end
            n_idx, n_levs = _labels(sel_vals, oname)
            owner_sel_idx[oname] = n_idx
            owner_new_count[oname] = length(n_levs)
        else
            k_idx = Vector{Int}(undef, N_sel)
            for (pos, v_id) in enumerate(sel_vals)
                haskey(tmap, v_id) ||
                    throw(ArgumentError("unknown $oname ID $(repr(v_id)); include $(repr(oname)) in new_owners"))
                k_idx[pos] = tmap[v_id]
            end
            owner_sel_idx[oname] = k_idx
            owner_new_count[oname] = 0
        end
    end

    # Decompose predictors if present
    derived_pred = Dict{Symbol,Vector{Float64}}()
    if hasproperty(t.specification, :decomposition)
        p_all, ps_all = _labels(collect(B._column(data, t.columns.person)), :person)
        b_all = [begin i_b, l_b = _labels(collect(B._column(data, b.column)), b.name); Block(b.name, b.column, l_b, i_b, 0.0, 0.0, 1:0) end for b in t.facets]
        raw_tmp = Dict{Symbol,Vector}(t.columns.person => collect(B._column(data, t.columns.person)))
        for b in t.facets; raw_tmp[b.column] = collect(B._column(data, b.column)); end
        t.columns.performance !== nothing && (raw_tmp[t.columns.performance] = collect(B._column(data, t.columns.performance)))
        ids_tmp = (; table = raw_tmp, columns = t.columns, person = p_all, people = ps_all, facets = b_all)
        rules = (;(d.source => (; between = d.between, within = d.within) for d in t.specification.decomposition.rules)...)
        d_full, _ = decompose_predictors(ids_tmp, data, rules)
        for (k, v) in d_full; derived_pred[k] = Float64.(v[ix]); end
    end

    term_x = Vector{Vector{Float64}}(undef, length(t.terms))
    for (ti, tm) in enumerate(t.terms)
        if tm.column === nothing
            term_x[ti] = ones(Float64, N_sel)
        else
            x_sel = haskey(derived_pred, tm.column) ? derived_pred[tm.column] : _numeric_column(data, tm.column, E_pred)[ix]
            if tm.owner !== :response && !(tm.owner in new_set)
                for pos in 1:N_sel
                    tm.values[owner_sel_idx[tm.owner][pos]] == x_sel[pos] ||
                        throw(ArgumentError("known-owner prediction changes stored $(tm.owner) attribute $(tm.column)"))
                end
            elseif tm.owner !== :response && (tm.owner in new_set)
                seen_cov = Dict{Int,Float64}()
                for pos in 1:N_sel
                    gid = owner_sel_idx[tm.owner][pos]
                    get!(seen_cov, gid, x_sel[pos]) == x_sel[pos] ||
                        throw(ArgumentError("new $(tm.owner) predictor $(tm.column) varies within the same new ID"))
                end
            end
            if tm.owner === :response && tm.by !== nothing
                tm.by in new_set && throw(ArgumentError("by-owner fixed coefficient $(tm.column) by $(tm.by) requires known $(tm.by) levels"))
                by_levs = _owner_levels(t, tm.by)
                by_target_j = only(findall(==(tm.level), by_levs))
                term_x[ti] = Float64[x_sel[pos] * (owner_sel_idx[tm.by][pos] == by_target_j) for pos in 1:N_sel]
            else
                term_x[ti] = x_sel
            end
        end
    end

    sbs = slope_blocks(t)
    slope_x = Dict{Symbol,Vector{Float64}}()
    for sb in sbs, col in _sb_cols(sb)
        haskey(slope_x, col) && continue
        slope_x[col] = haskey(derived_pred, col) ? derived_pred[col] : _numeric_column(data, col, E_pred)[ix]
    end

    # Also evaluate ZOIB distributional blocks if present on BoundedTarget
    dbs = t isa BoundedTarget ? distribution_blocks(t) : ()
    dist_term_x = [[begin
        col_x = haskey(derived_pred, p.column) ? derived_pred[p.column] : _numeric_column(data, p.column, E_pred)[ix]
        if p.by === nothing
            col_x
        else
            p.by in new_set && throw(ArgumentError("distributional by-owner term on $(p.by) requires known levels"))
            by_j = only(findall(==(p.level), _owner_levels(t, p.by)))
            Float64[col_x[pos] * (owner_sel_idx[p.by][pos] == by_j) for pos in 1:N_sel]
        end
    end for p in b.terms] for b in dbs]

    rng = MersenneTwister(Int(seed))
    S_draws = size(f.record.run.draws, 1)
    eta_mat = zeros(Float64, S_draws, N_sel)
    prec_mat = zeros(Float64, S_draws, N_sel)
    ep_mat = zeros(Float64, S_draws, N_sel)
    up_mat = zeros(Float64, S_draws, N_sel)

    for (s, q) in enumerate(eachrow(f.record.run.draws))
        v = coordinates(t, q)
        # Draw new owner intercepts (and correlated random slopes if present!)
        sb_map = Dict(sb.owner => (bi, sb) for (bi, sb) in enumerate(sbs))
        for oname in all_owner_syms
            sgn = oname === :person ? 1.0 : -1.0
            s_idx = owner_sel_idx[oname]
            if oname in new_set
                G_new = owner_new_count[oname]
                sd0 = Float64(v.residual_sd[oname])
                z0 = randn(rng, G_new)
                int_new = sd0 .* z0
                for pos in 1:N_sel
                    eta_mat[s, pos] += sgn * int_new[s_idx[pos]]
                end
                if haskey(sb_map, oname)
                    bi, sb = sb_map[oname]
                    sv = v.random_slopes[bi]
                    cols = _sb_cols(sb); K = length(cols)
                    if !_sb_is_multi(sb)
                        z1 = randn(rng, G_new)
                        sl_new = Float64(sv.sd) .* (Float64(sv.rho) .* z0 .+ Float64(sv.complement) .* z1)
                        xv = slope_x[only(cols)]
                        for pos in 1:N_sel
                            eta_mat[s, pos] += sgn * sl_new[s_idx[pos]] * xv[pos]
                        end
                    else
                        Z_all = hcat(z0, randn(rng, G_new, K)) # G_new x (K+1)
                        W_all = Z_all * transpose(sv.L)
                        for (k_sl, col) in enumerate(cols)
                            sd_k = Float64(sv.sds[k_sl])
                            xv = slope_x[col]
                            for pos in 1:N_sel
                                eta_mat[s, pos] += sgn * sd_k * W_all[s_idx[pos], k_sl + 1] * xv[pos]
                            end
                        end
                    end
                end
            else
                known_vec = oname === :person ? v.person : v.facets[oname]
                # Note: v.person / v.facets ALREADY contain owner-level regression terms!
                for pos in 1:N_sel
                    eta_mat[s, pos] += sgn * Float64(known_vec[s_idx[pos]])
                end
                if haskey(sb_map, oname)
                    bi, sb = sb_map[oname]
                    sv = v.random_slopes[bi]
                    cols = _sb_cols(sb)
                    if !_sb_is_multi(sb)
                        xv = slope_x[only(cols)]
                        for pos in 1:N_sel
                            eta_mat[s, pos] += sgn * Float64(sv.values[s_idx[pos]]) * xv[pos]
                        end
                    else
                        for (k_sl, col) in enumerate(cols)
                            xv = slope_x[col]; slv = sv.values[k_sl]
                            for pos in 1:N_sel
                                eta_mat[s, pos] += sgn * Float64(slv[s_idx[pos]]) * xv[pos]
                            end
                        end
                    end
                end
            end
        end
        # Add :response terms AND new-owner regression terms (known-owner regressions are already inside v.person / v.facets!)
        for (ti, tm) in enumerate(t.terms)
            if tm.owner === :response
                bval = Float64(v.coefficients[ti]); xv = term_x[ti]
                for pos in 1:N_sel
                    eta_mat[s, pos] += bval * xv[pos]
                end
            elseif tm.owner in new_set
                sgn = tm.owner === :person ? 1.0 : -1.0
                bval = Float64(v.coefficients[ti]); xv = term_x[ti]
                for pos in 1:N_sel
                    eta_mat[s, pos] += sgn * bval * xv[pos]
                end
            end
        end

        if t isa BoundedTarget
            lp0 = log(Float64(v.precision)); ep0 = Float64(v.endpoint_logit); up0 = Float64(v.upper_logit)
            for pos in 1:N_sel
                prec_mat[s, pos] = lp0; ep_mat[s, pos] = ep0; up_mat[s, pos] = up0
            end
            for (dbi, b) in enumerate(dbs)
                dv = v.distributional[dbi]
                target_mat = b.index == 1 ? prec_mat : b.index == 2 ? ep_mat : up_mat
                for (pti, cval) in enumerate(dv.coefficients)
                    xv = dist_term_x[dbi][pti]
                    for pos in 1:N_sel
                        target_mat[s, pos] += Float64(cval) * xv[pos]
                    end
                end
                for r in b.residuals
                    s_idx = owner_sel_idx[r.name]
                    if r.name in new_set
                        sd_d = Float64(dv.residual_sd[r.name])
                        z_d = sd_d .* randn(rng, owner_new_count[r.name])
                        for pos in 1:N_sel
                            target_mat[s, pos] += z_d[s_idx[pos]]
                        end
                    else
                        ev = dv.effects[r.name]
                        for pos in 1:N_sel
                            target_mat[s, pos] += Float64(ev[s_idx[pos]])
                        end
                    end
                end
            end
            for pos in 1:N_sel
                prec_mat[s, pos] = exp(prec_mat[s, pos])
            end
        elseif is_beta_binomial(t)
            for pos in 1:N_sel
                prec_mat[s, pos] = Float64(v.precision)
            end
        end
    end

    if t isa BoundedTarget
        req_m = metrics === nothing ? BOUNDED_DEFAULT_METRICS : metrics
        !isempty(req_m) && allunique(req_m) && all(k -> k in BOUNDED_METRICS, req_m) ||
            throw(ArgumentError("select distinct supported bounded metrics"))
        blo, bhi = t.observation.bounds; w_span = bhi - blo
        cells = NamedTuple[]; precision = NamedTuple[]
        for pos in 1:N_sel
            vals = zeros(Float64, S_draws, length(req_m))
            for s in 1:S_draws
                ec = eta_mat[s, pos]; mu = _sigmoid(ec); wm = _sigmoid(-ec)
                phi = prec_mat[s, pos]; z_p = _sigmoid(ep_mat[s, pos]); h_p = _sigmoid(up_mat[s, pos])
                iv = mu * wm / (phi + 1.0)
                tv = (1.0 - z_p) * iv + z_p * h_p * (1.0 - h_p) + (1.0 - z_p) * z_p * (mu - h_p)^2
                all_m = (; interior_mean = blo + w_span * mu,
                    expected_score = blo + w_span * ((1.0 - z_p) * mu + z_p * h_p),
                    lower_probability = z_p * (1.0 - h_p), upper_probability = z_p * h_p,
                    precision = phi, endpoint_probability = z_p, upper_given_endpoint_probability = h_p,
                    interior_sd = w_span * sqrt(iv), score_sd = w_span * sqrt(tv))
                for (mj, mk) in enumerate(req_m)
                    vals[s, mj] = getproperty(all_m, mk)
                end
            end
            for (mj, mk) in enumerate(req_m)
                xv = view(vals, :, mj)
                push!(cells, (; row = ix[pos], metric = mk, mean = mean(xv), median = median(xv),
                    lower = quantile(xv, lo), upper = quantile(xv, hi), unit = bounded_metric_unit(mk)))
            end
            append!(precision, [(; row = ix[pos], r...) for r in B._posterior_mcse_rows(
                vals, string.(collect(req_m)), f.record.run.controls.chains; probabilities = (lo, hi), parameter_space = :bounded_prediction)])
        end
        return (; schema = BOUNDED_PREDICTION_SCHEMA, kind = :prediction, mode = :new_owners, new_owners = nos, seed = Int(seed),
            cells, rows = ix, interval = Float64(interval), mcse = precision, bounds = t.observation.bounds,
            interval_target = :new_owner_conditional_expectation_or_probability,
            conditioning = :new_declared_owners_population_drawn_known_other_owners,
            qualification = qualify(f), source_sample_content_hash = f.record.content_hash,
            target_identity = f.record.target_identity,
            warnings = [design(t).warnings; "New-owner prediction draws fresh latent effects from fitted population priors for $(nos) (seed = $(Int(seed))); zero-effect substitution was NOT used."],
            scientific_acceptance = false)
    else
        metrics === nothing || throw(ArgumentError("metrics selection is currently available for bounded-score predictions"))
        trials_vec = count_integers(collect(B._column(data, t.observation.trials))[ix], :trials; positive = true)
        bb = is_beta_binomial(t)
        cells = NamedTuple[]; precision = NamedTuple[]
        for pos in 1:N_sel
            nt = trials_vec[pos]; vals = zeros(Float64, S_draws, 4)
            for s in 1:S_draws
                ec = eta_mat[s, pos]; p = _sigmoid(ec); phi = bb ? prec_mat[s, pos] : nothing
                vals[s, 1] = p; vals[s, 2] = nt * p
                vals[s, 3] = exp(first(count_cell(0, nt, ec, phi, 0.0)))
                vals[s, 4] = exp(first(count_cell(nt, nt, ec, phi, 0.0)))
            end
            for (mj, mk) in enumerate(COUNT_METRICS)
                xv = view(vals, :, mj)
                push!(cells, (; row = ix[pos], trials = nt, metric = mk, mean = mean(xv), median = median(xv),
                    lower = quantile(xv, lo), upper = quantile(xv, hi), unit = mk === :expected_count ? :success_count : :probability))
            end
            append!(precision, [(; row = ix[pos], r...) for r in B._posterior_mcse_rows(
                vals, string.(collect(COUNT_METRICS)), f.record.run.controls.chains; probabilities = (lo, hi), parameter_space = :count_prediction)])
        end
        return (; schema = COUNT_PREDICTION_SCHEMA, kind = :prediction, mode = :new_owners, new_owners = nos, seed = Int(seed),
            cells, rows = ix, interval = Float64(interval), mcse = precision,
            interval_target = :new_owner_conditional_expectation_or_probability,
            conditioning = :new_declared_owners_population_drawn_known_other_owners,
            observation = t.observation, measure = :success_count_given_trials,
            qualification = qualify(f), source_sample_content_hash = f.record.content_hash,
            target_identity = f.record.target_identity,
            warnings = [design(t).warnings; "New-owner prediction draws fresh latent effects from fitted population priors for $(nos) (seed = $(Int(seed))); zero-effect substitution was NOT used."],
            scientific_acceptance = false)
    end
end
