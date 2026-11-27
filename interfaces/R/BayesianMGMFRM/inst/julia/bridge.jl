module MGMFRMRBridge
using BayesianMGMFRM
using BayesianMGMFRM.Legacy: MFRMPrior
using SHA

_json_safe(x::AbstractFloat) = isfinite(x) ? Float64(x) : (isinf(x) ? (x > 0 ? "Inf" : "-Inf") : nothing)
_json_safe(x::Missing) = nothing
_json_safe(x::Symbol) = String(x)
_json_safe(x::Union{Integer, Bool, AbstractString, Nothing}) = x
_json_safe(x::AbstractVector) = [_json_safe(v) for v in x]
_json_safe(x::Tuple) = [_json_safe(v) for v in x]
function _json_safe(x::NamedTuple)
    return Dict{String, Any}(String(k) => _json_safe(getfield(x, k)) for k in keys(x))
end
function _json_safe(x::AbstractDict)
    return Dict{String, Any}(string(k) => _json_safe(v) for (k, v) in pairs(x))
end
_json_safe(x) = string(x)

function _compact_reliability(r)
    r isa NamedTuple || return r
    ks = [k for k in keys(r) if k !== :qualification && k !== :parameters]
    base = NamedTuple{Tuple(ks)}(Tuple(getfield(r, k) for k in ks))
    if hasproperty(r, :qualification) && r.qualification isa NamedTuple &&
            hasproperty(r.qualification, :scientific_acceptance)
        return merge(base, (; scientific_acceptance = r.qualification.scientific_acceptance))
    end
    return base
end

function _bridge_provenance()
    ap = Base.active_project()
    bs_file = ap === nothing ? nothing : joinpath(dirname(ap), "bridge-source.txt")
    mf_file = ap === nothing ? nothing : Base.project_file_manifest_path(ap)
    pkg_ver = try
        v = pkgversion(BayesianMGMFRM)
        v === nothing ? "0.2.0-DEV" : string(v)
    catch
        "0.2.0-DEV"
    end
    return (;
        package_version = pkg_ver,
        julia_version = string(VERSION),
        source = pkgdir(BayesianMGMFRM),
        bridge_source = (bs_file !== nothing && isfile(bs_file)) ? read(bs_file, String) : "",
        manifest_sha256 = (mf_file !== nothing && isfile(mf_file)) ? bytes2hex(sha256(read(mf_file))) : "",
    )
end

function _compact_pair_bias_basis(
        p_vec::Vector{Int},
        facet_names::Vector{String},
        facet_cols::Vector{Vector{Int}},
        s_vec::Vector{Int},
        steps_str::String,
        has_group::Bool,
        grp_vec)
    f_dict = Dict{String, Vector{Int}}()
    for (k, fn) in enumerate(facet_names)
        f_dict[fn] = facet_cols[k]
    end
    if has_group && grp_vec !== nothing
        f_dict["group"] = Int.(grp_vec)
    end
    sg_vec = if steps_str == "global"
        ones(Int, length(s_vec))
    else
        pos = findfirst(==(steps_str), facet_names)
        pos === nothing ? ones(Int, length(s_vec)) : facet_cols[pos]
    end
    return (;
        schema = "bayesianmgmfrm.pair_bias_basis.v1",
        person = p_vec,
        facets = f_dict,
        step_group = sg_vec,
        score = s_vec,
    )
end

function _bayesian_payload(rec, variables, sampler, identification::String, model::String,
                           steps::String, fit_statistics, reliability_records;
                           effective_model = nothing, design_validation = nothing,
                           prior_summary = nothing, fixed_calibration = nothing,
                           residual_correlation = nothing,
                           fair_reference_basis = nothing,
                           pair_bias_basis = nothing,
                           weighted_sufficient_score = nothing)
    names = isnothing(variables) ? collect(String, rec.parameter_names) :
        variables isa AbstractString ? [String(variables)] : collect(String, variables)
    columns = indexin(names, rec.parameter_names)
    all(!isnothing, columns) ||
        throw(ArgumentError("Unknown draw variable; available: " * join(rec.parameter_names, ", ")))
    indexes = Int.(columns)
    values = Array{Float64}(undef, rec.draws_per_chain, rec.n_chains, length(names))
    for (i, row) in enumerate(rec.draws), (v, col) in enumerate(indexes)
        values[rec.iterations[i], rec.chain_ids[i], v] = row[col]
    end
    prov = _bridge_provenance()
    pr_rec = rec.prior_and_reference
    pop_loc = (pr_rec !== nothing && hasproperty(pr_rec, :population_location_mode)) ? pr_rec.population_location_mode :
        ((pr_rec !== nothing && hasproperty(pr_rec, :location_mode)) ? pr_rec.location_mode : nothing)
    metadata = _json_safe((;
        rec.schema,
        rec.scale,
        model,
        method = "nuts",
        steps,
        identification,
        population_location_mode = pop_loc,
        effective_model,
        design_validation,
        fixed_calibration,
        rec.producer,
        rec.handoff_hash,
        parameter_blocks = rec.parameter_blocks[indexes],
        rec.fixed_parameters,
        rec.warnings,
        sampler,
        rec.sampler_controls,
        rec.qualification,
        rec.prior_and_reference,
        prior_summary,
        fit_statistics,
        reliability = reliability_records,
        residual_correlation,
        fair_reference_basis,
        pair_bias_basis,
        weighted_sufficient_score,
        prov.package_version,
        prov.julia_version,
        prov.source,
        prov.bridge_source,
        prov.manifest_sha256,
    ))
    return (;
        kind = "bayesian",
        values,
        names,
        estimates = Float64[],
        se = Float64[],
        vcov = zeros(Float64, 0, 0),
        vcov_names = String[],
        metadata = String(BayesianMGMFRM.JSON3.write(metadata)),
    )
end

function _compact_validation(val)
    iss_list = if hasproperty(val, :issues) && val.issues !== nothing
        [(;
            code = String(iss.code),
            severity = String(iss.severity),
            message = String(iss.message),
            context = hasproperty(iss, :context) ? iss.context : Dict{String,Any}(),
        ) for iss in val.issues]
    else
        NamedTuple[]
    end
    return (;
        passed = Bool(get(val, :passed, get(val, :identified, false))),
        identified = Bool(get(val, :identified, get(val, :passed, false))),
        rank = hasproperty(val, :rank) ? val.rank : nothing,
        columns = hasproperty(val, :columns) ? val.columns : nothing,
        connectedness = hasproperty(val, :connectedness) ? val.connectedness : nothing,
        disjoint_subsets = hasproperty(val, :disjoint_subsets) ? val.disjoint_subsets : nothing,
        score_conditioned_subsets = hasproperty(val, :score_conditioned_subsets) ? val.score_conditioned_subsets : nothing,
        one_sided_separation = hasproperty(val, :one_sided_separation) ? val.one_sided_separation : nothing,
        nesting_and_aliasing = hasproperty(val, :nesting_and_aliasing) ? val.nesting_and_aliasing : nothing,
        dependence_units = hasproperty(val, :dependence_units) ? val.dependence_units : nothing,
        missing_audit = hasproperty(val, :missing_audit) ? val.missing_audit : nothing,
        issues = iss_list,
        warnings = hasproperty(val, :warnings) ? collect(String, val.warnings) : String[],
    )
end

function _frequentist_payload(fit, variables, method::String, identification::String, steps::String;
                              effective_model = nothing, design_validation = nothing,
                              fixed_calibration = nothing, fixed_parameters = NamedTuple[],
                              pair_bias_basis = nothing)
    rec = fit.record
    s = rec.summary
    base_names = collect(String, rec.layout.full_names)
    base_est = collect(Float64, rec.full_parameters)
    base_se = collect(Float64, rec.full_se)
    offset = Int(rec.covariance.offset)

    all_names, full_est, full_se, vcov_names_all, vcov_mat_all = if hasproperty(s, :population) && hasproperty(rec, :mrcml_operator)
        pop_des = s.population.design
        op = rec.mrcml_operator
        d_xi = size(op.A_free, 2)
        n_mod = length(op.model_names)
        n_free = length(rec.u_free)
        br = (d_xi + 1):(d_xi + size(pop_des.X, 2))
        sr = (last(br) + 1):n_free
        pop_names = BayesianMGMFRM.FrequentistMFRM._grouped_names(pop_des, :model)
        sd_vals = exp.(Float64.(rec.u_free[sr]))
        pop_ests = vcat(Float64.(rec.u_free[br]), sd_vals)
        n_pop_par = length(pop_ests)
        J_all = zeros(Float64, n_mod + n_pop_par, n_free)
        J_all[1:n_mod, 1:d_xi] .= Matrix(op.J_model)
        for (k, idx) in enumerate(br)
            J_all[n_mod + k, idx] = 1.0
        end
        for (k, idx) in enumerate(sr)
            J_all[n_mod + length(br) + k, idx] = sd_vals[k]
        end
        V_all = Matrix(J_all * rec.covariance.free_covariance * transpose(J_all))
        pop_ses = Float64[sqrt(max(V_all[n_mod + j, n_mod + j], 0.0)) for j in 1:n_pop_par]
        comb_names = vcat(base_names, pop_names)
        comb_est = vcat(base_est, pop_ests)
        comb_se = vcat(base_se, pop_ses)
        (comb_names, comb_est, comb_se, comb_names[(offset + 1):end], V_all)
    else
        (base_names, base_est, base_se, base_names[(offset + 1):end], Matrix{Float64}(rec.covariance.matrix))
    end

    names = isnothing(variables) ? all_names :
        variables isa AbstractString ? [String(variables)] : collect(String, variables)
    columns = indexin(names, all_names)
    all(!isnothing, columns) ||
        throw(ArgumentError("Unknown parameter; available: " * join(all_names, ", ")))
    indexes = Int.(columns)
    estimates = Float64[full_est[i] for i in indexes]
    se = Float64[full_se[i] for i in indexes]
    blocks = String[split(nm, '[')[1] for nm in names]
    vcov_names = vcov_names_all
    vcov_mat = vcov_mat_all
    if !isnothing(variables)
        keep_vc = [i for (i, nm) in enumerate(vcov_names) if nm in names]
        vcov_names = vcov_names[keep_vc]
        vcov_mat = vcov_mat[keep_vc, keep_vc]
    end
    q = BayesianMGMFRM.qualify(fit)
    qual = (;
        qualified = Bool(q.qualified),
        converged = Bool(q.converged),
        stationarity_qualified = Bool(s.stationarity_qualified),
        gradient_gate_passed = Bool(q.gradient_gate_passed),
        hessian_gate_passed = Bool(q.hessian_gate_passed),
        boundary_gate_passed = Bool(q.boundary_gate_passed),
        hessian_positive_definite = Bool(q.hessian_positive_definite),
        min_hessian_eigenvalue = Float64(q.min_hessian_eigenvalue),
        hessian_condition_number = Float64(q.hessian_condition_number),
        max_abs_gradient = Float64(q.max_abs_gradient),
        thresholds = q.thresholds,
        warnings = q.warnings,
        s.loglikelihood,
        s.deviance,
        s.aic,
        s.bic_persons,
        s.bic_observations,
        s.n_iterations,
        s.population_mean,
        s.population_sd,
    )
    by_facet = Dict{String, Any}()
    by_facet["person"] = collect(rec.person_scores)
    for fn in s.facet_names
        fn_str = String(fn)
        by_facet[fn_str] = [row for row in rec.facet_measures if row.facet === fn]
    end
    prov = _bridge_provenance()
    metadata = _json_safe((;
        rec.schema,
        scale = "model",
        model = "mfrm",
        method,
        steps,
        identification,
        effective_model,
        design_validation,
        fixed_calibration,
        fixed_parameters,
        handoff_hash = rec.content_hash,
        parameter_blocks = blocks,
        warnings = unique(vcat(collect(String, rec.warnings), collect(String, q.warnings))),
        qualification = qual,
        overall_fit = rec.overall_fit,
        fit_statistics = by_facet,
        reliability = rec.reliability,
        fair_reference_basis = try
            BayesianMGMFRM.AdditiveFacets.fair_reference_basis(fit)
        catch e
            e isa ArgumentError || rethrow()
            (;available=false,reason=sprint(showerror,e))
        end,
        pair_bias_basis,
        step_measures = rec.step_measures,
        extreme_facet_levels = rec.extreme_facet_levels,
        prov.package_version,
        prov.julia_version,
        prov.source,
        prov.bridge_source,
        prov.manifest_sha256,
    ))
    return (;
        kind = "frequentist",
        values = zeros(Float64, 0, 0, 0),
        names,
        estimates,
        se,
        vcov = vcov_mat,
        vcov_names,
        metadata = String(BayesianMGMFRM.JSON3.write(metadata)),
    )
end

_as_int_vec(x) = x === nothing ? Int[] : (x isa Integer ? Int[Int(x)] : Int[Int(v) for v in x])

function _parse_cat_levels_json(cat_json::AbstractString, lvl_vec::Vector{Int})
    isempty(cat_json) && return lvl_vec
    parsed = BayesianMGMFRM.JSON3.read(cat_json)
    return Dict{Int, Vector{Int}}(parse(Int, String(k)) => Int[Int(x) for x in v] for (k, v) in pairs(parsed))
end

function _parse_fixed_calibration_json(fc_json::AbstractString)
    isempty(fc_json) && return (nothing, nothing)
    parsed = BayesianMGMFRM.JSON3.read(fc_json)
    f_part = if haskey(parsed, :facets) && parsed[:facets] !== nothing && !isempty(parsed[:facets])
        f_pairs = Pair{Symbol, Any}[]
        for (fn, fmap) in pairs(parsed[:facets])
            push!(f_pairs, Symbol(fn) => Dict{Int, Float64}(
                parse(Int, String(lk)) => Float64(lv) for (lk, lv) in pairs(fmap)))
        end
        (; f_pairs...)
    else
        nothing
    end
    g_part = if haskey(parsed, :groups) && parsed[:groups] !== nothing && !isempty(parsed[:groups])
        g_vec = NamedTuple[]
        for g in parsed[:groups]
            blk = Symbol(g[:block])
            raw_lvs = g[:levels]
            lvs = raw_lvs isa Integer ? Int[Int(raw_lvs)] : Int[Int(x) for x in raw_lvs]
            stat = Symbol(g[:statistic])
            val = Float64(g[:value])
            push!(g_vec, stat === :mean ? (; block = blk, levels = lvs, mean = val) : (; block = blk, levels = lvs, sum = val))
        end
        g_vec
    else
        nothing
    end
    fc_nt = merge(
        f_part === nothing ? (;) : (; facets = f_part),
        g_part === nothing ? (;) : (; groups = g_part),
    )
    receipt = haskey(parsed, :receipt) ? parsed[:receipt] : nothing
    return (fc_nt, receipt)
end

function _build_roster_and_dff(p_vec::Vector{Int}, group_col, method::String,
                               group_equal_sd::Bool, group_sd_prior::String,
                               dff_facet::String, dff_mode::String, dff_focal_idx::Vector{Int})
    g_obs = Int.(group_col)
    P = maximum(p_vec)
    p_group = zeros(Int, P)
    for idx in eachindex(p_vec)
        pid = p_vec[idx]
        gid = g_obs[idx]
        (p_group[pid] == 0 || p_group[pid] == gid) ||
            throw(ArgumentError("Each person must belong to a single group"))
        p_group[pid] = gid
    end
    any(==(0), p_group) && throw(ArgumentError("Every modeled person must have a group"))
    D = BayesianMGMFRM.Distributions
    pop = if method == "nuts"
        sd_pr = if group_sd_prior == "lognormal"
            D.LogNormal(0.0, 0.5)
        elseif group_sd_prior == "half_normal"
            D.truncated(D.Normal(0.0, 1.0), 0.0, Inf)
        elseif group_sd_prior == "half_t"
            D.truncated(D.LocationScale(0.0, 1.0, D.TDist(4.0)), 0.0, Inf)
        else
            throw(ArgumentError("Unsupported group_sd_prior: $group_sd_prior"))
        end
        (;
            roster = (; person = collect(1:P), group = p_group),
            person = :person,
            group = :group,
            reference = 1,
            coefficient_prior = D.Normal(0.0, 2.5),
            sd_prior = sd_pr,
            (group_equal_sd ? (; equal_sd = true) : (;))...,
        )
    else
        (;
            roster = (; person = collect(1:P), group = p_group),
            person = :person,
            group = :group,
            reference = 1,
            (group_equal_sd ? (; equal_sd = true) : (;))...,
        )
    end
    int_kw = if isempty(dff_facet)
        (;)
    else
        f_sym = Symbol(dff_facet)
        dff_pr = D.truncated(D.LocationScale(0.0, 0.5, D.TDist(4.0)), 0.0, Inf)
        if dff_mode == "doubly_centered"
            method == "nuts" ?
                (; interactions = ((f_sym, :group) => dff_pr,)) :
                (; interactions = ((f_sym, :group),))
        elseif dff_mode == "split_rater"
            !isempty(dff_focal_idx) || throw(ArgumentError("dff_focal is required when dff_mode = \"split_rater\""))
            foc_arg = length(dff_focal_idx) == 1 ? dff_focal_idx[1] : dff_focal_idx
            method == "nuts" ?
                (; interactions = ((; pair = (f_sym, :group), focal = foc_arg, prior = D.Normal(0.0, 1.0)),)) :
                (; interactions = ((; pair = (f_sym, :group), focal = foc_arg),))
        else
            throw(ArgumentError("Unsupported dff_mode: $dff_mode"))
        end
    end
    return pop, int_kw
end

function _resolve_ability_sd_prior(ability_sd_prior::String)
    D = BayesianMGMFRM.Distributions
    if ability_sd_prior == "half_normal"
        return D.truncated(D.Normal(0.0, 1.0), 0.0, Inf)
    elseif ability_sd_prior == "lognormal"
        return D.LogNormal(0.0, 0.5)
    elseif ability_sd_prior == "half_t"
        return D.truncated(D.LocationScale(0.0, 1.0, D.TDist(4.0)), 0.0, Inf)
    else
        throw(ArgumentError("Unsupported ability_sd_prior: $ability_sd_prior"))
    end
end

function _compact_residual_correlation(fit, facet_names::Vector{String}, seed::Int)
    target_facet = if "item" in facet_names
        :item
    elseif "criterion" in facet_names
        :criterion
    else
        return nothing
    end
    n_draws = size(fit.record.run.draws, 1)
    rc = try
        BayesianMGMFRM.diagnostics(fit;
            kind = :residual_correlation,
            by = target_facet,
            unit = :auto,
            min_common_units = 3,
            max_draws = min(500, n_draws),
            seed = seed)
    catch
        return nothing
    end
    return (;
        schema = rc.schema,
        facet = rc.by,
        unit = rc.unit,
        unit_binding = rc.unit_binding,
        n_units = rc.n_units,
        level = rc.level,
        n_draws_evaluated = rc.n_draws_evaluated,
        pairs = rc.rows,
        summary = rc.global_summary,
    )
end

function fit_model(person, facet_names_in, facet_cols_flat, score, levels, group_col,
                   model_in, method_in, steps_in, identification_in,
                   q_flat, q_ncol, scale_id_in, anchor_dims, anchor_items,
                   chains, warmup, ndraws, seed, variables, handoff_path_in,
                   orig_ids_json_in = "", cat_levels_json_in = "",
                   fixed_cal_json_in = "", perf_col = Int[], assess_col = Int[],
                   group_equal_sd_in = false, group_sd_prior_in = "lognormal",
                   dff_facet_in = "", dff_mode_in = "doubly_centered", dff_focal_in = Int[],
                   slope_in = "", correlation_in = "independent", lkj_eta_in = 2.0,
                   ability_sd_prior_in = "half_normal",
                   location_id_in = "centered_items_free_mean",
                   random_effects_in = String[], random_sd_prior_in = "half_normal",
                   random_sd_scale_in = 1.0,
                   logit_scale_in = 0.0,
                   rater_slope_scope_in = "entire_linear_predictor",
                   aggregation_in = "additive",
                   softmin_kappa_in = 0.0,
                   cross_loading_avg_in = -1,
                   q_dim_labels_in = String[])
    model = String(model_in)
    method = String(method_in)
    steps = String(steps_in)
    identification = String(identification_in)
    scale_id = String(scale_id_in)
    handoff_path = isnothing(handoff_path_in) ? "" : String(handoff_path_in)
    orig_ids_json = isnothing(orig_ids_json_in) ? "" : String(orig_ids_json_in)
    cat_levels_json = isnothing(cat_levels_json_in) ? "" : String(cat_levels_json_in)
    fixed_cal_json = isnothing(fixed_cal_json_in) ? "" : String(fixed_cal_json_in)
    orig_ids = if isempty(orig_ids_json)
        nothing
    else
        parsed_ids = BayesianMGMFRM.JSON3.read(orig_ids_json)
        (; (Symbol(k) => String[x isa AbstractVector ? String(first(x)) : String(x) for x in parsed_ids[k]] for k in keys(parsed_ids))...)
    end

    fc_nt, fc_receipt = _parse_fixed_calibration_json(fixed_cal_json)
    facet_names = facet_names_in isa AbstractString ? [String(facet_names_in)] : collect(String, facet_names_in)
    random_effects = random_effects_in isa AbstractString ? [String(random_effects_in)] : collect(String, random_effects_in)
    shared = !isempty(random_effects)
    if shared
        allunique(random_effects) && all(in(facet_names),random_effects) ||
            throw(ArgumentError("random_effects must name distinct declared facets"))
        model == "mfrm" && method == "nuts" && identification == "isometric" &&
            String(location_id_in) == "centered_items_free_mean" ||
            throw(ArgumentError("unsupported shared random-effect combination"))
    end
    p_vec = _as_int_vec(person)
    s_vec = _as_int_vec(score)
    lvl_vec = _as_int_vec(levels)
    cat_spec = _parse_cat_levels_json(cat_levels_json, lvl_vec)
    f_mat = reshape(_as_int_vec(facet_cols_flat), length(s_vec), length(facet_names))
    facet_cols = [collect(Int, view(f_mat, :, k)) for k in eachindex(facet_names)]
    grp_vec = _as_int_vec(group_col)
    perf_vec = _as_int_vec(perf_col)
    assess_vec = _as_int_vec(assess_col)
    has_group = !isempty(grp_vec)
    # A constructor can reject the design before the R payload relabels its IDs.
    gen_it_pos = findfirst(fn -> fn in ("item", "criterion"), facet_names)
    gen_rt_pos = findfirst(==("rater"), facet_names)
    if model in ("gmfrm", "mgmfrm") && length(facet_names) == 2 && gen_it_pos !== nothing && gen_rt_pos !== nothing
        check_data = FacetData((; person=p_vec, item=facet_cols[gen_it_pos], rater=facet_cols[gen_rt_pos], score=s_vec);
            person=:person, item=:item, rater=:rater, score=:score, category_levels=lvl_vec)
        check_report = BayesianMGMFRM.validate_design(check_data)
        check_report.passed || throw(BayesianMGMFRM._facet_spec_validation_error(check_data, check_report; ids=orig_ids))
    end
    has_perf = !isempty(perf_vec)
    has_assess = !isempty(assess_vec)

    if model == "mfrm"
        if method == "nuts"
            if identification == "isometric"
                pairs_list = Pair{Symbol, Any}[
                    :person => p_vec,
                    :score => s_vec,
                ]
                has_perf && push!(pairs_list, :performance => perf_vec)
                has_assess && push!(pairs_list, :assessment => assess_vec)
                for (k, fn) in enumerate(facet_names)
                    push!(pairs_list, Symbol(fn) => facet_cols[k])
                end
                table = (; pairs_list...)
                facets_nt = (; (Symbol(fn) => Symbol(fn) for fn in facet_names)...)
                ev_kw = merge(
                    has_perf ? (; performance = :performance) : (;),
                    has_assess ? (; assessment = :assessment) : (;),
                    fc_nt === nothing ? (;) : (; fixed_calibration = fc_nt),
                )
                if shared
                    for (key,ids) in ((:performance,perf_vec),(:assessment,assess_vec))
                        isempty(ids) && continue
                        k=findfirst(i->facet_names[i] in random_effects && facet_cols[i]==ids,eachindex(facet_names))
                        k===nothing || (ev_kw=merge(ev_kw,NamedTuple{(key,)}((Symbol(facet_names[k]),))))
                    end
                end
                group_equal_sd = Bool(group_equal_sd_in)
                group_sd_prior = String(group_sd_prior_in)
                dff_facet = isnothing(dff_facet_in) ? "" : String(dff_facet_in)
                dff_mode = String(dff_mode_in)
                dff_focal_idx = _as_int_vec(dff_focal_in)
                random_kw = if shared
                    D = BayesianMGMFRM.Distributions
                    sd_scale = Float64(random_sd_scale_in)
                    isfinite(sd_scale) && sd_scale > 0 || throw(ArgumentError("random_sd_scale must be finite and positive"))
                    sd_prior = String(random_sd_prior_in) == "half_normal" ? D.truncated(D.Normal(0,sd_scale),0,Inf) :
                        String(random_sd_prior_in) == "half_t" ? D.truncated(D.LocationScale(0,sd_scale,D.TDist(4)),0,Inf) :
                        throw(ArgumentError("random_sd_prior must be half_normal or half_t"))
                    (;random_effects=(;(Symbol(fn)=>sd_prior for fn in random_effects)...))

                else
                    (;)
                end
                spec = if has_group
                    pop, int_kw = _build_roster_and_dff(
                        p_vec, grp_vec, "nuts", group_equal_sd, group_sd_prior,
                        dff_facet, dff_mode, dff_focal_idx,
                    )
                    facets_sd = (; (Symbol(fn) => 1.0 for fn in facet_names)...)
                    mfrm_spec(table; person=:person, score=:score, facets=facets_nt,
                        steps=Symbol(steps), category_levels=cat_spec,
                        population=pop, prior_sd=(; facets=facets_sd, step=1.0), int_kw..., random_kw..., ev_kw...)
                elseif shared
                    fs = (;(Symbol(fn)=>1.0 for fn in facet_names if fn ∉ random_effects)...)
                    mfrm_spec(table; person=:person, score=:score, facets=facets_nt,
                        steps=Symbol(steps), category_levels=cat_spec,
                        prior_sd=(;person=_resolve_ability_sd_prior(String(ability_sd_prior_in)),facets=fs,step=1.0),
                        intercept=BayesianMGMFRM.Distributions.Normal(0,2.5), random_kw..., ev_kw...)
                else
                    mfrm_spec(table; person=:person, score=:score, facets=facets_nt,
                        steps=Symbol(steps), category_levels=cat_spec,
                        prior=:default, random_kw..., ev_kw...)
                end
                val = BayesianMGMFRM.validate_design(spec)
                eff_steps = String(spec.owner)
                eff_id_iso = fc_nt === nothing ? "isometric" : "isometric_fixed_calibration"
                fit = BayesianMGMFRM.fit(spec; chains=Int(chains), warmup=Int(warmup),
                    ndraws=Int(ndraws), seed=Int(seed), progress=false)
                diag = BayesianMGMFRM.diagnostics(fit)
                sampler = (; retained = diag.sampler, warmup = diag.warmup)
                fit_stats = Dict{String, Any}()
                for fn in facet_names
                    fs = BayesianMGMFRM.diagnostics(fit; kind=:fit_statistics, by=Symbol(fn))
                    fit_stats[fn] = fs.rows
                end
                rels = [_compact_reliability(BayesianMGMFRM.reliability(fit))]
                rc_rep = _compact_residual_correlation(fit, facet_names, Int(seed))
                ho = BayesianMGMFRM.PortableHandoff.export_handoff(fit; scale=:model, ids=orig_ids)
                !isempty(handoff_path) && BayesianMGMFRM.PortableHandoff.save_handoff(handoff_path, ho)
                dv = _compact_validation(val)
                ps = BayesianMGMFRM.design_summary(spec).prior_summary
                fair_basis = try
                    BayesianMGMFRM.AdditiveFacets.fair_reference_basis(spec)
                catch e
                    e isa ArgumentError || rethrow()
                    (; available=false, reason=sprint(showerror,e))
                end
                eff_model = shared ? merge(val.effective_model,(;random_effects)) : val.effective_model
                pb_basis = _compact_pair_bias_basis(p_vec, facet_names, facet_cols, s_vec, eff_steps, has_group, grp_vec)
                return _bayesian_payload(ho.record, variables, sampler, eff_id_iso, model, eff_steps, fit_stats, rels;
                    effective_model = eff_model, design_validation = dv,
                    prior_summary = ps, fixed_calibration = fc_receipt,
                    fair_reference_basis = fair_basis,
                    pair_bias_basis = pb_basis,
                    residual_correlation = rc_rep)
            elseif identification == "reference"
                facet_names == ["item", "rater"] && !has_group ||
                    throw(ArgumentError("identification=\"reference\" supports only 3-facet (person, item, rater) MFRM without group"))
                steps in ("global", "item") ||
                    throw(ArgumentError("identification=\"reference\" supports steps = \"global\" or \"item\""))
                thresh = steps == "global" ? :rating_scale : :partial_credit
                data = FacetData((; person=p_vec, item=facet_cols[1], rater=facet_cols[2], score=s_vec);
                    person=:person, item=:item, rater=:rater, score=:score, category_levels=lvl_vec)
                spec = mfrm_spec(data; thresholds=thresh)
                val = BayesianMGMFRM.validate_design(spec)
                eff_m = val.effective_model
                eff_steps = String(eff_m.threshold_owner)
                fit = BayesianMGMFRM.fit(spec;
                    prior=MFRMPrior(person_sd=1.5, rater_sd=1.0, item_sd=1.0, step_sd=1.0),
                    backend=:advancedhmc, chains=Int(chains), warmup=Int(warmup),
                    ndraws=Int(ndraws), seed=Int(seed), chain_execution=:auto, progress=false)
                sampler = (;
                    retained = BayesianMGMFRM.sampler_diagnostics(fit; phase=:retained),
                    warmup = BayesianMGMFRM.sampler_diagnostics(fit; phase=:warmup),
                )
                ho = BayesianMGMFRM.PortableHandoff.export_handoff(fit; scale=:model, ids=orig_ids)
                !isempty(handoff_path) && BayesianMGMFRM.PortableHandoff.save_handoff(handoff_path, ho)
                dv = _compact_validation(val)
                ps_ref = hasproperty(ho.record, :prior_summary) ? ho.record.prior_summary : nothing
                eff_id_ref = String(eff_m.identification)
                return _bayesian_payload(ho.record, variables, sampler, eff_id_ref, model, eff_steps, Dict{String, Any}(), Any[];
                    effective_model = eff_m, design_validation = dv, prior_summary = ps_ref)
            else
                throw(ArgumentError("identification must be \"isometric\" or \"reference\""))
            end
        elseif method in ("mmle", "jmle")
            identification == "isometric" ||
                throw(ArgumentError("Frequentist estimation requires identification=\"isometric\""))
            if has_group && method != "mmle"
                throw(ArgumentError("group requires method=\"nuts\" or method=\"mmle\" (JMLE cannot identify free person abilities jointly with group means)"))
            end
            isempty(handoff_path) ||
                throw(ArgumentError("handoff_path is only supported for Bayesian posterior fits (method=\"nuts\")"))
            pairs_list = Pair{Symbol, Any}[
                :person => p_vec,
                :score => s_vec,
            ]
            has_perf && push!(pairs_list, :performance => perf_vec)
            has_assess && push!(pairs_list, :assessment => assess_vec)
            for (k, fn) in enumerate(facet_names)
                push!(pairs_list, Symbol(fn) => facet_cols[k])
            end
            table = (; pairs_list...)
            facets_nt = (; (Symbol(fn) => Symbol(fn) for fn in facet_names)...)
            ev_kw = merge(
                has_perf ? (; performance = :performance) : (;),
                has_assess ? (; assessment = :assessment) : (;),
                fc_nt === nothing ? (;) : (; fixed_calibration = fc_nt),
            )
            group_equal_sd = Bool(group_equal_sd_in)
            group_sd_prior = String(group_sd_prior_in)
            dff_facet = isnothing(dff_facet_in) ? "" : String(dff_facet_in)
            dff_mode = String(dff_mode_in)
            dff_focal_idx = _as_int_vec(dff_focal_in)
            spec = if has_group
                pop_f, int_kw_f = _build_roster_and_dff(
                    p_vec, grp_vec, method, group_equal_sd, group_sd_prior,
                    dff_facet, dff_mode, dff_focal_idx,
                )
                mfrm_spec(table; person=:person, score=:score, facets=facets_nt,
                    steps=Symbol(steps), category_levels=cat_spec,
                    population=pop_f, prior=:none, int_kw_f..., ev_kw...)
            else
                mfrm_spec(table; person=:person, score=:score, facets=facets_nt,
                    steps=Symbol(steps), category_levels=cat_spec, prior=:none, ev_kw...)
            end
            val = BayesianMGMFRM.validate_design(spec)
            eff_steps = String(spec.owner)
            eff_id_freq = fc_nt === nothing ? "isometric" : "isometric_fixed_calibration"
            fit = BayesianMGMFRM.fit(spec; method=Symbol(method))
            dv = _compact_validation(val)
            fp_freq = if fc_nt !== nothing
                rec_f = fit.record
                off_f = Int(rec_f.covariance.offset)
                NamedTuple[
                    (; block = String(split(rec_f.layout.full_names[i], '[')[1]),
                       name = String(rec_f.layout.full_names[i]),
                       value = Float64(rec_f.full_parameters[i]))
                    for i in (off_f + 1):length(rec_f.layout.full_names)
                    if rec_f.full_se[i] == 0.0
                ]
            else
                NamedTuple[]
            end
            pb_basis_f = _compact_pair_bias_basis(p_vec, facet_names, facet_cols, s_vec, eff_steps, has_group, grp_vec)
            return _frequentist_payload(fit, variables, method, eff_id_freq, eff_steps;
                effective_model = val.effective_model, design_validation = dv,
                fixed_calibration = fc_receipt, fixed_parameters = fp_freq,
                pair_bias_basis = pb_basis_f)
        else
            throw(ArgumentError("Unsupported method: $method"))
        end
    elseif model == "gmfrm"
        method == "nuts" || throw(ArgumentError("model=\"gmfrm\" requires method=\"nuts\""))
        identification == "isometric" ||
            throw(ArgumentError("model=\"gmfrm\" requires identification=\"isometric\"; identification = $(repr(identification)) is not supported."))
        slope_str = isnothing(slope_in) ? "" : String(slope_in)
        if isempty(slope_str)
            facet_names == ["item", "rater"] && !has_group ||
                throw(ArgumentError("model=\"gmfrm\" without explicit `slope` requires facets (item, rater) without group"))
            data = FacetData((; person=p_vec, item=facet_cols[1], rater=facet_cols[2], score=s_vec);
                person=:person, item=:item, rater=:rater, score=:score, category_levels=lvl_vec)
            steps == "rater" ||
                throw(ArgumentError("model=\"gmfrm\" without explicit `slope` supports only rater-owned partial-credit thresholds (steps = \"rater\"); pass slope = \"rater\", \"item\", or \"both\" for scale-identified GMFRM with steps = \"global\", \"item\", or \"rater\"."))
            spec = mfrm_spec(data; family=:gmfrm, discrimination=:rater, thresholds=:partial_credit)
            val = BayesianMGMFRM.validate_design(spec)
            eff_m = val.effective_model
            eff_m.threshold_owner === :rater ||
                throw(ArgumentError("Compiled GMFRM threshold owner $(eff_m.threshold_owner) does not match requested steps = $(repr(steps))."))
            eff_steps = String(eff_m.threshold_owner)
            eff_id = String(eff_m.identification)
            fit = BayesianMGMFRM.Experimental.fit(spec; chains=Int(chains), warmup=Int(warmup),
                ndraws=Int(ndraws), seed=Int(seed), chain_execution=:auto, progress=false)
            sampler = (;
                retained = BayesianMGMFRM.sampler_diagnostics(fit; phase=:retained),
                warmup = BayesianMGMFRM.sampler_diagnostics(fit; phase=:warmup),
            )
            wss = BayesianMGMFRM.diagnostics(fit; kind=:weighted_sufficient_score)
            ho = BayesianMGMFRM.PortableHandoff.export_handoff(fit; scale=:model, ids=orig_ids)
            !isempty(handoff_path) && BayesianMGMFRM.PortableHandoff.save_handoff(handoff_path, ho)
            dv = _compact_validation(val)
            ps_gm = hasproperty(ho.record, :prior_summary) ? ho.record.prior_summary : nothing
            return _bayesian_payload(ho.record, variables, sampler, eff_id, model, eff_steps, Dict{String, Any}(), Any[];
                effective_model = eff_m, design_validation = dv, prior_summary = ps_gm,
                weighted_sufficient_score = [wss])
        else
            (length(facet_names) == 2 && gen_it_pos !== nothing && gen_rt_pos !== nothing && !has_group) ||
                throw(ArgumentError("model=\"gmfrm\" requires facets (item/criterion, rater) without group"))
            item_role_sym = Symbol(facet_names[gen_it_pos])
            data = FacetData((; person=p_vec, item=facet_cols[gen_it_pos], rater=facet_cols[gen_rt_pos], score=s_vec);
                person=:person, item=:item, rater=:rater, score=:score, category_levels=lvl_vec)
            slope_sym = Symbol(slope_str)
            steps_sym = (steps == "criterion" && item_role_sym === :criterion) ? :item : Symbol(steps)
            ab_sd_pr = _resolve_ability_sd_prior(String(ability_sd_prior_in))
            loc_sym = Symbol(String(location_id_in))
            ls_gm = Float64(logit_scale_in) > 0.0 ? Float64(logit_scale_in) : 1.0
            rs_scope_sym = Symbol(String(rater_slope_scope_in))
            anc_gm = if scale_id == "anchor_item"
                d_vec_g = _as_int_vec(anchor_dims)
                i_vec_g = _as_int_vec(anchor_items)
                isempty(d_vec_g) ? :first_pure : Dict{Int, Int}(d_vec_g[k] => i_vec_g[k] for k in eachindex(d_vec_g))
            else
                nothing
            end
            target_gm = BayesianMGMFRM.ScaleIdentifiedMGMFRM.gmfrm_model(
                data;
                slope = slope_sym,
                steps = steps_sym,
                logit_scale = ls_gm,
                scale_identification = Symbol(scale_id),
                anchor_items = anc_gm,
                location_identification = loc_sym,
                rater_slope_scope = rs_scope_sym,
                ability_sd_prior = ab_sd_pr,
                item_role = item_role_sym,
            )
            val = BayesianMGMFRM.validate_design(target_gm)
            eff_m = val.effective_model
            eff_steps = (target_gm.step_owner === :item && item_role_sym === :criterion) ? "criterion" : String(target_gm.step_owner)
            eff_id = String(target_gm.prior.scale_identification)
            fit = BayesianMGMFRM.fit(target_gm; chains=Int(chains), warmup=Int(warmup),
                ndraws=Int(ndraws), seed=Int(seed), progress=false)
            diag = BayesianMGMFRM.diagnostics(fit)
            sampler = hasproperty(diag, :sampler) ? (; retained = diag.sampler) : diag
            rels = [_compact_reliability(BayesianMGMFRM.reliability(fit; dimension=1))]
            wss = BayesianMGMFRM.diagnostics(fit; kind=:weighted_sufficient_score, dimension=1)
            ho = BayesianMGMFRM.PortableHandoff.export_handoff(fit; scale=:model, ids=orig_ids)
            !isempty(handoff_path) && BayesianMGMFRM.PortableHandoff.save_handoff(handoff_path, ho)
            dv = _compact_validation(val)
            ps_gm = hasproperty(ho.record, :prior_summary) ? ho.record.prior_summary : nothing
            return _bayesian_payload(ho.record, variables, sampler, eff_id, model, eff_steps, Dict{String, Any}(), rels;
                effective_model = eff_m, design_validation = dv, prior_summary = ps_gm,
                fair_reference_basis = BayesianMGMFRM.AdditiveFacets.fair_reference_basis(target_gm),
                weighted_sufficient_score = [wss])
        end
    elseif model == "mgmfrm"
        method == "nuts" || throw(ArgumentError("model=\"mgmfrm\" requires method=\"nuts\""))
        identification == "isometric" ||
            throw(ArgumentError("model=\"mgmfrm\" is identified via scale_identification (\"geometric_mean_one\" or \"anchor_item\"); identification = $(repr(identification)) is not supported."))
        (length(facet_names) == 2 && gen_it_pos !== nothing && gen_rt_pos !== nothing && !has_group) ||
            throw(ArgumentError("model=\"mgmfrm\" requires facets (item/criterion, rater) without group"))
        item_role_sym = Symbol(facet_names[gen_it_pos])
        steps_sym = (steps == "criterion" && item_role_sym === :criterion) ? :item : Symbol(steps)
        steps_sym in (:global, :item, :rater) ||
            throw(ArgumentError("model=\"mgmfrm\" supports steps = \"global\", \"$(facet_names[gen_it_pos])\", or \"rater\"; got steps = $(repr(steps))."))
        D = Int(q_ncol)
        q_vec = _as_int_vec(q_flat)
        D >= 1 && !isempty(q_vec) || throw(ArgumentError("Supply a nonempty Q matrix for model=\"mgmfrm\""))
        Q_mat = reshape(q_vec, :, D)
        dim_lbls_in = q_dim_labels_in isa AbstractString ? [String(q_dim_labels_in)] : collect(String, q_dim_labels_in)
        dim_lbls_arg = isempty(dim_lbls_in) ? nothing : dim_lbls_in
        data = FacetData((; person=p_vec, item=facet_cols[gen_it_pos], rater=facet_cols[gen_rt_pos], score=s_vec);
            person=:person, item=:item, rater=:rater, score=:score, category_levels=lvl_vec)
        spec = mfrm_spec(data; family=:mgmfrm, dimensions=D, discrimination=:rater_item,
            q_matrix=Q_mat, dimension_labels=dim_lbls_arg,
            thresholds=(steps_sym === :global ? :rating_scale : :partial_credit))
        slope_str = isnothing(slope_in) ? "" : String(slope_in)
        rc_mode = slope_str == "item" ? :fixed_one : :estimated_positive
        it_mode = slope_str == "rater" ? :fixed_one : :estimated_positive
        corr_str = String(correlation_in)
        corr_sym = corr_str in ("independent", "identity_fixed") ? :identity_fixed : Symbol(corr_str)
        ab_sd_pr = _resolve_ability_sd_prior(String(ability_sd_prior_in))
        loc_sym = Symbol(String(location_id_in))
        ls_mg = Float64(logit_scale_in) > 0.0 ? Float64(logit_scale_in) : 1.7
        rs_scope_sym = Symbol(String(rater_slope_scope_in))
        agg_sym = Symbol(String(aggregation_in))
        sk_arg = agg_sym === :softmin ? (Float64(softmin_kappa_in) > 0.0 ? Float64(softmin_kappa_in) : :estimated) : nothing
        cl_avg_arg = Int(cross_loading_avg_in) < 0 ? nothing : (Int(cross_loading_avg_in) == 1)
        anc_arg = if scale_id == "anchor_item"
            d_vec = _as_int_vec(anchor_dims)
            i_vec = _as_int_vec(anchor_items)
            Dict{Int, Int}(d_vec[k] => i_vec[k] for k in eachindex(d_vec))
        elseif scale_id == "geometric_mean_one"
            nothing
        else
            throw(ArgumentError("scale_identification must be \"geometric_mean_one\" or \"anchor_item\""))
        end
        pr_mg = BayesianMGMFRM.ScaleIdentifiedMGMFRM.Prior(;
            scale_identification = Symbol(scale_id),
            location_identification = loc_sym,
            logit_scale = ls_mg,
            anchor_items = anc_arg,
            rater_consistency = rc_mode,
            rater_slope_scope = rs_scope_sym,
            item_slopes = it_mode,
            ability_sd_prior = ab_sd_pr,
            ability_mean_sd = 2.5,
            log_loading_sd = 0.35,
            item_sd = 1.5,
            rater_sd = 1.0,
            log_consistency_sd = 0.35,
            step_sd = 1.5,
            latent_correlation = corr_sym,
            lkj_eta = Float64(lkj_eta_in),
            step_owner = steps_sym,
            family_tag = :mgmfrm,
            item_role = item_role_sym,
            aggregation = agg_sym,
            cross_loading_average = cl_avg_arg,
            softmin_kappa = sk_arg,
        )
        target = BayesianMGMFRM.ScaleIdentifiedMGMFRM.model(spec; prior = pr_mg)
        val = BayesianMGMFRM.validate_design(target)
        eff_m = val.effective_model
        eff_steps = (target.step_owner === :item && item_role_sym === :criterion) ? "criterion" : String(target.step_owner)
        eff_id = String(target.prior.scale_identification)
        fit = BayesianMGMFRM.fit(target; chains=Int(chains), warmup=Int(warmup),
            ndraws=Int(ndraws), seed=Int(seed), progress=false)
        diag = BayesianMGMFRM.diagnostics(fit)
        sampler = hasproperty(diag, :sampler) ? (; retained = diag.sampler) : diag
        rels = [_compact_reliability(BayesianMGMFRM.reliability(fit; dimension=d)) for d in 1:D]
        wss_list = [BayesianMGMFRM.diagnostics(fit; kind=:weighted_sufficient_score, dimension=d) for d in 1:D]
        ho = BayesianMGMFRM.PortableHandoff.export_handoff(fit; scale=:model, ids=orig_ids)
        !isempty(handoff_path) && BayesianMGMFRM.PortableHandoff.save_handoff(handoff_path, ho)
        dv = _compact_validation(val)
        ps_mg = hasproperty(ho.record, :prior_summary) ? ho.record.prior_summary : nothing
        return _bayesian_payload(ho.record, variables, sampler, eff_id, model, eff_steps, Dict{String, Any}(), rels;
            effective_model = eff_m, design_validation = dv, prior_summary = ps_mg,
            fair_reference_basis = BayesianMGMFRM.AdditiveFacets.fair_reference_basis(target),
            weighted_sufficient_score = wss_list)
    else
        throw(ArgumentError("Unsupported model: $model"))
    end
end

function fit_pcm(person, item, rater, score, levels, chains, warmup, ndraws, seed, variables, identification="isometric")
    steps = length(levels) > 2 ? "item" : "global"
    return fit_model(person, ["item", "rater"], vcat(Int.(item), Int.(rater)), score, levels, Int[],
        "mfrm", "nuts", steps, String(identification), Int[], 0, "geometric_mean_one",
        Int[], Int[], chains, warmup, ndraws, seed, variables, "")
end

function load_handoff_file(path::AbstractString, variables=nothing)
    parsed = BayesianMGMFRM.JSON3.read(read(String(path), String))
    ho = BayesianMGMFRM.PortableHandoff.load_handoff(parsed)
    rec = ho.record
    model_fam = hasproperty(rec, :source_family) && rec.source_family !== nothing ?
        String(rec.source_family) :
        (hasproperty(rec, :producer) && hasproperty(rec.producer, :model_family) ?
            String(rec.producer.model_family) : "mfrm")
    ps_ho = hasproperty(rec, :prior_summary) ? rec.prior_summary : nothing
    return _bayesian_payload(rec, variables, nothing, "handoff", model_fam, "handoff", Dict{String, Any}(), Any[];
        prior_summary = ps_ho)
end

include("generalizability.jl")

end
