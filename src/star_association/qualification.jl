_is_finite_real(x) = x isa Real && !(x isa Bool) && isfinite(x)

function _diag_row_passes(
    r,
    rhat_max::Float64,
    ess_min::Float64,
    fixed_set::Set{String} = Set{String}(),
)
    r.parameter in fixed_set && return true
    return _is_finite_real(r.rank_normalized_rhat) &&
        r.rank_normalized_rhat <= rhat_max &&
        _is_finite_real(r.bulk_ess) &&
        r.bulk_ess >= ess_min &&
        _is_finite_real(r.tail_ess) &&
        r.tail_ess >= ess_min
end

function _summarize_diag_rows(
    rows,
    rhat_max::Float64,
    ess_min::Float64,
    fixed_set::Set{String} = Set{String}(),
)
    free = [r for r in rows if !(r.parameter in fixed_set)]
    if isempty(free)
        return (;
            count = 0,
            failed = 0,
            failed_rhat = 0,
            failed_bulk_ess = 0,
            failed_tail_ess = 0,
            max_rhat = NaN,
            median_rhat = NaN,
            min_bulk_ess = NaN,
            median_bulk_ess = NaN,
            min_tail_ess = NaN,
            median_tail_ess = NaN,
            worst_rhat = NamedTuple[],
            worst_bulk_ess = NamedTuple[],
        )
    end
    rhats = [_is_finite_real(r.rank_normalized_rhat) ? Float64(r.rank_normalized_rhat) : Inf for r in free]
    bess = [_is_finite_real(r.bulk_ess) ? Float64(r.bulk_ess) : 0.0 for r in free]
    tess = [_is_finite_real(r.tail_ess) ? Float64(r.tail_ess) : 0.0 for r in free]
    w_rh = free[sortperm(rhats; rev = true)[1:min(10, length(free))]]
    w_be = free[sortperm(bess)[1:min(10, length(free))]]
    return (;
        count = length(free),
        failed = count(r -> !_diag_row_passes(r, rhat_max, ess_min, fixed_set), free),
        failed_rhat = count(>(rhat_max), rhats),
        failed_bulk_ess = count(<(ess_min), bess),
        failed_tail_ess = count(<(ess_min), tess),
        max_rhat = maximum(rhats),
        median_rhat = median(rhats),
        min_bulk_ess = minimum(bess),
        median_bulk_ess = median(bess),
        min_tail_ess = minimum(tess),
        median_tail_ess = median(tess),
        worst_rhat = w_rh,
        worst_bulk_ess = w_be,
    )
end

function _raw_block_summaries(m::StarModel, raw_rows, rhat_max::Float64, ess_min::Float64)
    b = _layout(m)
    mk = _cp_masks(m)
    zi_cp = Int[]
    zi_ncp = Int[]
    zr_cp = Int[]
    zr_ncp = Int[]
    for c in 1:m.D, j in 1:(m.I - 1)
        idx = first(b.zi) + (c - 1) * (m.I - 1) + j - 1
        push!(mk.entity_cp[j] ? zi_cp : zi_ncp, idx)
    end
    for c in 1:m.D, j in 1:(m.R - 1)
        idx = first(b.zr) + (c - 1) * (m.R - 1) + j - 1
        push!(mk.rater_cp[j] ? zr_cp : zr_ncp, idx)
    end
    groups = [
        ("zi_cp", zi_cp),
        ("zi_ncp", zi_ncp),
        ("zr_cp", zr_cp),
        ("zr_ncp", zr_ncp),
        ("steps", vcat(collect.(b.steps)...)),
        ("mu", collect(b.mu)),
        ("si", collect(b.si)),
        ("sr", collect(b.sr)),
        ("ci", collect(b.ci)),
        ("cr", collect(b.cr)),
        ("phi", collect(b.phi)),
    ]
    out = NamedTuple[]
    for (gname, idxs) in groups
        isempty(idxs) && continue
        s = _summarize_diag_rows(raw_rows[idxs], rhat_max, ess_min)
        push!(
            out,
            (;
                block = gname,
                s.count,
                s.failed,
                s.max_rhat,
                s.median_rhat,
                s.min_bulk_ess,
                s.median_bulk_ess,
                s.min_tail_ess,
                s.median_tail_ess,
            ),
        )
    end
    return out
end

function _transformed_coord_names(m::StarModel)
    cids = [c.id for c in m.criteria]
    return vcat(
        ["entity_ability[$(m.entity_levels[i]),$(cids[c])]" for c in 1:m.D for i in 1:m.I],
        ["rater_severity[$(m.rater_levels[r]),$(cids[c])]" for c in 1:m.D for r in 1:m.R],
        ["raw_step[$(cids[c]),$k]" for c in 1:m.D for k in 1:m.M[c]],
        ["ref_root_step[$k]" for k in 1:m.M[1]],
        ["ref_mu[$c]" for c in cids],
        ["raw_root_mu"],
        ["entity_sd[$c]" for c in cids],
        ["rater_sd[$c]" for c in cids],
        ["R_entity[$(cids[j]),$(cids[i])]" for i in 2:m.D for j in 1:(i - 1)],
        ["R_rater[$(cids[j]),$(cids[i])]" for i in 2:m.D for j in 1:(i - 1)],
        m.spec.include_phi ? ["phi[$c]" for c in cids[2:end]] : String[],
    )
end

function _transformed_vector(m::StarModel, q)
    v = _coordinates(m, q; raw_input = false)
    v_ref = _reference_mu_and_tau(m, q)
    ri = C.correlation_state(q[v.b.ci], m.D; eta = m.prior.entity_lkj_eta).R
    rr = C.correlation_state(q[v.b.cr], m.D; eta = m.prior.rater_lkj_eta).R
    return vcat(
        vec(v.A),
        vec(v.S),
        vcat(v.tau...),
        v_ref.tau[1],
        q[v.b.mu],
        [v.mu[1]],
        exp.(q[v.b.si]),
        exp.(q[v.b.sr]),
        [ri[i, j] for i in 2:m.D for j in 1:(i - 1)],
        [rr[i, j] for i in 2:m.D for j in 1:(i - 1)],
        m.spec.include_phi ? q[v.b.phi] : Float64[],
    )
end

function _transformed_fixed_names(m::StarModel)
    cids = [c.id for c in m.criteria]
    fixed = Set{String}()
    for c in 1:m.D
        if m.M[c] == 1
            push!(fixed, "raw_step[$(cids[c]),1]")
        end
    end
    if m.M[1] == 1
        push!(fixed, "ref_root_step[1]")
    end
    return fixed
end

function _stream_transformed_diagnostics(
    res::StarResult,
    rhat_max::Float64,
    ess_min::Float64,
    chunk_size::Int,
)
    m = res.model
    S = size(res.draws, 1)
    tnames = _transformed_coord_names(m)
    tfixed = _transformed_fixed_names(m)
    n_tot = length(tnames)
    buf = Matrix{Float64}(undef, S, min(chunk_size, n_tot))
    all_rows = Vector{NamedTuple}(undef, n_tot)
    for c_start in 1:chunk_size:n_tot
        c_end = min(c_start + chunk_size - 1, n_tot)
        c_len = c_end - c_start + 1
        sub_buf = view(buf, 1:S, 1:c_len)
        for s in 1:S
            tv = _transformed_vector(m, view(res.draws, s, :))
            @inbounds sub_buf[s, :] .= view(tv, c_start:c_end)
        end
        all_rows[c_start:c_end] = B._candidate_mcmc_diagnostic_rows(
            sub_buf,
            tnames[c_start:c_end],
            res.config.chains;
            parameter_space = :transformed,
            structurally_fixed_parameters = tfixed,
            split_chains = true,
            rhat_threshold = rhat_max,
            ess_threshold = ess_min,
        )
    end
    return _summarize_diag_rows(all_rows, rhat_max, ess_min, tfixed)
end

function _warmup_chain_rows(cfg::SamplerConfig, warm_stats)
    return map(1:cfg.chains) do c
        cs = filter(x -> x.chain == c, warm_stats)
        post_init = filter(x -> x.iteration > cfg.init_buffer, cs)
        (;
            chain = c,
            iterations = length(cs),
            divergences = count(x -> x.numerical_error, cs),
            post_init_divergences = count(x -> x.numerical_error, post_init),
            depth_hits = count(x -> x.tree_depth >= cfg.max_depth, cs),
            max_tree_depth = isempty(cs) ? 0 : maximum(x.tree_depth for x in cs),
        )
    end
end

function _focal_precision_check(
    res::StarResult,
    rhat_max::Float64,
    ess_min::Float64,
    mean_mcse_max::Float64,
    endpoint_mcse_max::Float64,
)
    sub = _extract_substantive_draws(res.model, res.draws)
    branches = [c.id for c in res.model.criteria[2:end]]
    fnames = ["cor_entity_direct[$b]" for b in branches]
    ix = [only(findall(==(n), sub.names)) for n in fnames]
    fmat = sub.draws[:, ix]
    dr = B._candidate_mcmc_diagnostic_rows(
        fmat,
        fnames,
        res.config.chains;
        parameter_space = :focal_correlation,
        split_chains = true,
        rhat_threshold = rhat_max,
        ess_threshold = ess_min,
    )
    mc = B._posterior_mcse_rows(
        fmat,
        fnames,
        res.config.chains;
        parameter_space = :focal_correlation,
        probabilities = (0.025, 0.5, 0.975),
    )
    return map(eachindex(fnames)) do j
        m_row = mc[j]
        qs = m_row.quantiles
        prec_ok = _is_finite_real(m_row.mean_mcse) &&
            m_row.mean_mcse <= mean_mcse_max &&
            _is_finite_real(qs[1].mcse) &&
            qs[1].mcse <= endpoint_mcse_max &&
            _is_finite_real(qs[3].mcse) &&
            qs[3].mcse <= endpoint_mcse_max
        (;
            parameter = fnames[j],
            mean = mean(view(fmat, :, j)),
            sd = std(view(fmat, :, j)),
            lower = qs[1].estimate,
            median = qs[2].estimate,
            upper = qs[3].estimate,
            mean_mcse = m_row.mean_mcse,
            lower_mcse = qs[1].mcse,
            upper_mcse = qs[3].mcse,
            rank_normalized_rhat = dr[j].rank_normalized_rhat,
            bulk_ess = dr[j].bulk_ess,
            tail_ess = dr[j].tail_ess,
            diagnostic_passed = _diag_row_passes(dr[j], rhat_max, ess_min),
            precision_passed = prec_ok,
        )
    end
end

# Keep the established Star keyword spellings as aliases of the shared controls.
function _qualification_control(value, alias, default, name, alias_name; lower=0.0)
    value !== nothing && alias !== nothing &&
        throw(ArgumentError("supply either $name or $alias_name, not both"))
    x = value === nothing ? (alias === nothing ? default : alias) : value
    _is_finite_real(x) && isfinite(Float64(x)) && x > lower ||
        throw(ArgumentError("$name must be finite and greater than $lower"))
    return Float64(x)
end

function _qualification_telemetry_complete(res::StarResult)
    cfg = res.config
    length(res.retained_stats) == cfg.chains * cfg.ndraws || return false
    return all(eachindex(res.retained_stats)) do i
        row = res.retained_stats[i]
        chain = cld(i, cfg.ndraws)
        iteration = cfg.warmup + mod1(i, cfg.ndraws)
        isequal(get(row, :chain, nothing), chain) &&
            isequal(get(row, :iteration, nothing), iteration) &&
            get(row, :numerical_error, nothing) isa Bool &&
            get(row, :tree_depth, nothing) isa Integer &&
            !(get(row, :tree_depth, nothing) isa Bool) &&
            get(row, :tree_depth, -1) >= 0 &&
            _is_finite_real(get(row, :hamiltonian_energy, nothing)) &&
            _is_finite_real(get(row, :log_density, nothing))
    end
end

"""
    qualify(res::StarResult; max_rhat=1.01, min_ess=400.0, min_bfmi=0.3,
        mean_mcse_max=0.01, endpoint_mcse_max=0.02, check_transformed=true, chunk_size=512)

Check raw and transformed coordinates, complete retained sampler telemetry, and
mean/95% interval-endpoint MCSE for the named finite-entity root/branch correlations
`cor_entity_direct[criterion]`. These focal gates do not cover every population
correlation, residual-association parameter, contrast, rank or event probability.
Inspect their own summaries/MCSE for the application. Numerical qualification
is not scientific model acceptance.

`rhat_max`, `ess_min`, and `ebfmi_min` remain aliases; supplying both names for
one control is an error. All thresholds must be finite positive numbers
(`max_rhat > 1`). `check_transformed=false` provides a partial diagnostic report:
`transformed_passed` is missing and neither whole-fit nor overall qualification
can pass. Missing or misaligned retained telemetry also fails qualification.
`diagnostics` is an alias, with the same controls and report envelope.
"""
function qualify(
    res::StarResult;
    max_rhat::Union{Nothing,Real} = nothing,
    min_ess::Union{Nothing,Real} = nothing,
    min_bfmi::Union{Nothing,Real} = nothing,
    rhat_max::Union{Nothing,Real} = nothing,
    ess_min::Union{Nothing,Real} = nothing,
    ebfmi_min::Union{Nothing,Real} = nothing,
    mean_mcse_max::Real = 0.01,
    endpoint_mcse_max::Real = 0.02,
    check_transformed::Bool = true,
    chunk_size::Int = 512,
)
    rh_m = _qualification_control(max_rhat, rhat_max, 1.01, :max_rhat, :rhat_max; lower=1.0)
    es_m = _qualification_control(min_ess, ess_min, 400.0, :min_ess, :ess_min)
    eb_m = _qualification_control(min_bfmi, ebfmi_min, 0.3, :min_bfmi, :ebfmi_min)
    mm_m = _qualification_control(mean_mcse_max, nothing, 0.01, :mean_mcse_max, nothing)
    em_m = _qualification_control(endpoint_mcse_max, nothing, 0.02, :endpoint_mcse_max, nothing)
    chunk_size >= 16 || throw(ArgumentError("chunk_size >= 16 required"))
    _verify_result(res)
    rrows = B._candidate_mcmc_diagnostic_rows(
        res.draws,
        _raw_names(res.model),
        res.config.chains;
        parameter_space = :raw_unconstrained,
        split_chains = true,
        rhat_threshold = rh_m,
        ess_threshold = es_m,
    )
    rawsum = _summarize_diag_rows(rrows, rh_m, es_m)
    blocks = _raw_block_summaries(res.model, rrows, rh_m, es_m)
    transsum = check_transformed ? _stream_transformed_diagnostics(res, rh_m, es_m, chunk_size) : nothing
    s_rows = _sampler_chain_rows(res.config, res.warmup_stats, res.retained_stats, res.provenance)
    w_rows = _warmup_chain_rows(res.config, res.warmup_stats)
    focal = _focal_precision_check(res, rh_m, es_m, mm_m, em_m)
    telemetry_complete = _qualification_telemetry_complete(res)
    s_pass = telemetry_complete && res.config.chains >= 2 && all(
        x -> x.retained_divergences == 0 &&
            x.retained_depth_hits == 0 &&
            x.nonfinite_logdensity == 0 &&
            _is_finite_real(x.e_bfmi) &&
            x.e_bfmi >= eb_m,
        s_rows,
    )
    t_pass = transsum !== nothing && transsum.failed == 0
    whole = s_pass && rawsum.failed == 0 && t_pass
    f_pass = all(x -> x.diagnostic_passed && x.precision_passed, focal)
    return _envelope(
        res,
        :qualify,
        (;
            numerically_qualified = whole && f_pass,
            qualification_scope = :whole_fit_and_named_focal_correlations,
            focal_precision_qualification = f_pass ? :passed : :failed,
            focal_parameters = getproperty.(focal, :parameter),
            focal_probabilities = (0.025, 0.975),
            transformed_assessed = check_transformed,
            telemetry_complete,
            whole_fit_passed = whole,
            sampler_passed = s_pass,
            raw_passed = rawsum.failed == 0,
            transformed_passed = transsum === nothing ? missing : t_pass,
            focal_passed = f_pass,
            thresholds = (;
                max_rhat = rh_m,
                min_ess = es_m,
                min_bfmi = eb_m,
                rhat_max = rh_m,
                ess_min = es_m,
                ebfmi_min = eb_m,
                mean_mcse_max = mm_m,
                endpoint_mcse_max = em_m,
            ),
            raw_blocks = blocks,
            raw = rawsum,
            transformed = transsum,
            sampler = s_rows,
            warmup = w_rows,
            focal,
        ),
    )
end

diagnostics(res::StarResult; kwargs...) = qualify(res; kwargs...)
