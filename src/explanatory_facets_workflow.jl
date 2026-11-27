# Included after the common additive lifecycle; Fit and persisted run checks are shared.
function model_draws(t::ExplanatoryTarget,raw)
    labels=names(t,:model);values=Matrix{Float64}(undef,size(raw,1),length(labels))
    for (i,q) in enumerate(eachrow(raw))
        v=coordinates(t,q)
        values[i,:]=[v.person;reduce(vcat,(v.facets[b.name] for b in t.facets);init=Float64[]);
            _step_values(t,v.steps);v.coefficients;[v.residual_sd[b.name] for b in t.residuals]]
    end
    fixed=Set{String}()
    for b in t.residuals
        b.hyper==0 && push!(fixed,"residual_sd[$(b.name)]")
        if isempty(b.raw)
            for lvl in _owner_levels(t,b.name)
                push!(fixed,"$(b.name)[$(repr(lvl))]")
            end
        end
    end
    union!(fixed,["steps[$(repr(t.group_levels[g])),1]" for g in eachindex(t.steps) if _step_count(t,g)==1])
    (;names=labels,values,fixed)
end
summary_unit(t::ExplanatoryTarget,scale)=scale===:raw ? (_explanatory_logscale(t) ? :white_normal_and_log_scale : :white_standard_normal) : :parameter_specific_unit_logits_and_predictor_units
allocation_error(t::ExplanatoryTarget)=join(t.allocation.reasons," ") * " Inspect design_summary(spec)."
prediction_conditioning(t::ExplanatoryTarget)=:known_owners_and_stored_owner_attributes
function contrast_unit(t::ExplanatoryTarget,left,right)
    a=findfirst(p->_term_name(p)==left,t.terms);b=findfirst(p->_term_name(p)==right,t.terms)
    if a!==nothing && b!==nothing
        x,y=t.terms[a],t.terms[b]
        x.by!==nothing && x.by===y.by && x.column===y.column && x.owner===y.owner &&
            return :unit_logit_per_shared_predictor_unit
    end
    if hasproperty(t.specification,:decomposition)
        for d in t.specification.decomposition.rules
            bs=[_term_name(p) for p in t.terms if p.owner in (:person,:response) && p.column===d.between && p.by===nothing]
            ws=[_term_name(p) for p in t.terms if p.owner in (:person,:response) && p.column===d.within && p.by===nothing]
            ((left in bs && right in ws) || (left in ws && right in bs)) && return :unit_logit_per_decomposed_predictor_unit
        end
    end
    # Different named predictor units cannot be inferred to be commensurable.
    any(x->startswith(x,"coefficient["),(left,right)) && throw(ArgumentError(
        "Use posterior_summary for coefficients; named predictor units need not be commensurable for subtraction."))
    :unit_logit
end

function prediction_target(t::ExplanatoryTarget,data)
    data===nothing && return t
    base=prediction_target(t.base,data);n=length(base.person);raw=deepcopy(base.table);terms=MeanTerm[]
    derived=prediction_decomposition(t,base,data);merge!(raw,derived)
    for p in t.terms
        x=p.column===nothing ? ones(n) : haskey(derived,p.column) ? derived[p.column] : _numeric_column(data,p.column,n)
        p.column===nothing || (raw[p.column]=x)
        if p.owner===:response
            values=p.by===nothing ? x : x.*(_owner_index(base,p.by).==only(findall(==(p.level),_owner_levels(base,p.by))))
        else
            values=p.values
            # Known-owner predictions retain the fitted population covariate.
            # Counterfactual changes to owner attributes require a separate estimand.
            ix=_owner_index(base,p.owner)
            all(i->values[ix[i]]==x[i],1:n) ||
                throw(ArgumentError("prediction changes stored $(p.owner) predictor $(p.column); known-owner prediction preserves owner attributes"))
        end
        push!(terms,MeanTerm(p.owner,p.column,p.mean,p.sd,p.raw,values,p.by,p.level))
    end
    ExplanatoryTarget(base,raw,t.residuals,terms,t.steps,t.dimension,t.allocation,t.specification)
end
function response_shift(t::ExplanatoryTarget,p,values,s,n)
    offset=length(t.people)+sum(length(b.levels) for b in t.facets;init=0)+sum(length(r)+1 for r in t.steps)
    sum((values[s,offset+j]*term.values[n] for (j,term) in enumerate(p.terms) if term.owner===:response);init=0.)
end

function explanatory_new_owner_predict(t::ExplanatoryTarget, f::Fit;
        data, rows = nothing, interval = 0.95, new_owners = (), seed = nothing)
    lo, hi = interval_bounds(interval)
    all_owner_syms = [:person; [b.name for b in t.facets]]
    nos = _validate_new_owners_list(new_owners, all_owner_syms, :new_owners, data, seed)
    new_set = Set(nos)

    for oname in nos
        rb = only(r for r in t.residuals if r.name === oname)
        rb.kind === :iid_population ||
            throw(ArgumentError("owner $(repr(oname)) is a finite sum-zero panel, not an iid population; unseen levels require declaring $(repr(oname)) in population"))
        t.owner === oname &&
            throw(ArgumentError("step-threshold owner $(repr(oname)) must remain known to identify category thresholds"))
    end

    if :person in new_set && t.columns.performance !== nothing
        for b in t.facets
            b.column === t.columns.performance && !(b.name in new_set) &&
                throw(ArgumentError("predicting for a new :person requires declaring performance/cluster facet $(repr(b.name)) in new_owners as well"))
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
    selected_columns = Dict{Symbol,Vector}()
    for oname in all_owner_syms
        col_sym = oname === :person ? t.columns.person : only(b.column for b in t.facets if b.name === oname)
        cvals = collect(B._column(data, col_sym))
        B._check_length!(E_pred, cvals, col_sym)
        sel_vals = cvals[ix]
        selected_columns[col_sym] = copy(sel_vals)
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

    # Enforce performance-to-person nesting consistency when performance is declared
    if t.columns.performance !== nothing
        pcol = t.columns.performance
        pvals_all = collect(B._column(data, pcol))
        B._check_length!(E_pred, pvals_all, pcol)
        pvals = pvals_all[ix]
        selected_columns[pcol] = copy(pvals)
        per_vals = collect(B._column(data, t.columns.person))[ix]
        seen_perf = Dict{Any,Any}()
        for pos in 1:N_sel
            get!(seen_perf, pvals[pos], per_vals[pos]) == per_vals[pos] ||
                throw(ArgumentError("a performance/cluster ID belongs to multiple persons in prediction data"))
        end
        perf_facets = [b.name for b in t.facets if b.column === pcol]
        if isempty(perf_facets) || !(only(perf_facets) in new_set)
            known_links = Dict(zip(t.table[pcol], t.table[t.columns.person]))
            for pos in 1:N_sel
                haskey(known_links, pvals[pos]) && known_links[pvals[pos]] == per_vals[pos] ||
                    throw(ArgumentError("known-performance prediction requires stored performance-to-person ownership"))
            end
        end
    end

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
        for (k, v) in d_full
            derived_pred[k] = Float64.(v[ix])
            selected_columns[k] = copy(derived_pred[k])
        end
    end

    term_x = Vector{Vector{Float64}}(undef, length(t.terms))
    for (ti, tm) in enumerate(t.terms)
        if tm.column === nothing
            term_x[ti] = ones(Float64, N_sel)
        else
            x_sel = haskey(derived_pred, tm.column) ? derived_pred[tm.column] : _numeric_column(data, tm.column, E_pred)[ix]
            selected_columns[tm.column] = copy(x_sel)
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

    group_sel = t.owner === :global ? ones(Int, N_sel) : copy(owner_sel_idx[t.owner])
    rng = MersenneTwister(Int(seed))
    S_draws = size(f.record.run.draws, 1)
    K = length(t.categories)
    eta_mat = zeros(Float64, S_draws, N_sel)
    step_draws = Array{Float64}(undef, S_draws, size(t.steps, 1), maximum(_step_count(t, g) for g in eachindex(t.steps)))

    for (s, q) in enumerate(eachrow(f.record.run.draws))
        v = coordinates(t, q)
        for g in eachindex(t.steps), h in 1:_step_count(t, g)
            step_draws[s, g, h] = Float64(v.steps[g, h])
        end
        for oname in all_owner_syms
            sgn = oname === :person ? 1.0 : -1.0
            s_idx = owner_sel_idx[oname]
            if oname in new_set
                G_new = owner_new_count[oname]
                sd0 = Float64(v.residual_sd[oname])
                int_new = sd0 .* randn(rng, G_new)
                for pos in 1:N_sel
                    eta_mat[s, pos] += sgn * int_new[s_idx[pos]]
                end
            else
                known_vec = oname === :person ? v.person : v.facets[oname]
                for pos in 1:N_sel
                    eta_mat[s, pos] += sgn * Float64(known_vec[s_idx[pos]])
                end
            end
        end
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
    end

    means = zeros(Float64, N_sel, K)
    lower = zeros(Float64, N_sel, K)
    upper = zeros(Float64, N_sel, K)
    precision = NamedTuple[]
    expected_score_cells = NamedTuple[]
    a = zeros(Float64, S_draws, K)
    es = zeros(Float64, S_draws)

    for pos in 1:N_sel
        g = group_sel[pos]; support = t.supports[g]
        for s in 1:S_draws
            ec = eta_mat[s, pos]
            a[s, :] .= -Inf; a[s, first(support)] = 0.0
            for (h, k) in enumerate(support[2:end])
                a[s, k] = a[s, k - 1] + ec - step_draws[s, g, h]
            end
            z = B._logsumexp(view(a, s, :))
            a[s, :] .= exp.(view(a, s, :) .- z)
            es[s] = sum(t.categories[k] * a[s, k] for k in support)
        end
        means[pos, :] = vec(mean(a; dims = 1))
        for k in 1:K
            lower[pos, k] = quantile(view(a, :, k), lo)
            upper[pos, k] = quantile(view(a, :, k), hi)
        end
        push!(expected_score_cells, (; position = pos, row = ix[pos], mean = mean(es), median = median(es),
            lower = quantile(es, lo), upper = quantile(es, hi)))
        fixed = Set("category[$(t.categories[k])]" for k in 1:K if !(k in support))
        append!(precision, [(; row = ix[pos], category = t.categories[k], structural_zero = !(k in support), r...) for (k, r) in enumerate(
            B._posterior_mcse_rows(a, ["category[$k]" for k in t.categories], f.record.run.controls.chains;
                probabilities = (lo, hi), parameter_space = :category_probability, structurally_fixed_parameters = fixed))])
    end

    cells = [(; position = pos, row = ix[pos], category = t.categories[k], mean = means[pos, k],
        lower = lower[pos, k], upper = upper[pos, k], structural_zero = !(k in t.supports[group_sel[pos]]))
        for pos in 1:N_sel for k in 1:K]
    d = design(t)
    w_new = vcat(d.warnings, [
        "New-owner prediction draws fresh latent effects from the fitted population distributions for $(collect(nos)) (seed = $(Int(seed))); zero-effect substitution was NOT used.",
    ])
    (; schema = PREDICTION_SCHEMA, kind = :prediction, mode = :new_owners, new_owners = nos, seed = Int(seed),
       zero_effect_substitution = false, cells, expected_score_cells, rows = ix,
       category_levels = copy(t.categories), mean = means, lower, upper, interval = Float64(interval), mcse = precision,
       response_patterns = d.response_patterns, warnings = w_new, target_identity = f.record.target_identity,
       category_support = [copy(t.categories[t.supports[group_sel[pos]]]) for pos in 1:N_sel],
       selected_columns, conditioning = :new_owners_population_integrated,
       interval_target = :posterior_category_probability,
       observation_prediction = :posterior_mean_probabilities, qualification = qualify(f),
       source_sample_content_hash = f.record.content_hash, scientific_acceptance = false)
end
