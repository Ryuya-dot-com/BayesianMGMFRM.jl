const RESULT_SCHEMA = "bayesianmgmfrm.star_association_samples.v3"
const REPORT_SCHEMA = "bayesianmgmfrm.star_association_report.v3"
const JSON_ENVELOPE_SCHEMA = "bayesianmgmfrm.star_association_report_json.v3"

struct StarResult
    schema::String
    model::StarModel
    config::SamplerConfig
    draws::Matrix{Float64}
    logdensities::Vector{Float64}
    warmup_stats::Vector{NamedTuple}
    retained_stats::Vector{NamedTuple}
    sampling_quality::NamedTuple
    sampling_warning::Bool
    target_identity::String
    source::NamedTuple
    provenance::NamedTuple
    warnings::Vector{String}
    substantive_hash::String
    content_hash::String
end

sampler_controls(res::StarResult) = sampler_controls(res.config)

_jsonsafe(x::NamedTuple) = NamedTuple{keys(x)}(map(_jsonsafe, values(x)))
_jsonsafe(x::Union{Tuple, AbstractArray}) = map(_jsonsafe, x)
_jsonsafe(x::AbstractFloat) = isfinite(x) ? x : (; nonfinite = string(x))
_jsonsafe(x::Symbol) = String(x)
_jsonsafe(x) = x

function _source_signature()
    src_dir = @__DIR__
    files = Dict{String, String}()
    for name in sort(filter(f -> endswith(f, ".jl"), readdir(src_dir)))
        files[name] = bytes2hex(sha256(read(joinpath(src_dir, name))))
    end
    files["lkj_kernel"] = bytes2hex(sha256(read(LKJ_SOURCE)))
    proj = Base.active_project()
    man = proj === nothing ? nothing : joinpath(dirname(proj), "Manifest.toml")
    return (;
        source_hash = B._cache_hash(files),
        julia = string(VERSION),
        platform = Sys.MACHINE,
        project = proj === nothing ? nothing : bytes2hex(sha256(read(proj))),
        manifest = (man !== nothing && isfile(man)) ? bytes2hex(sha256(read(man))) : nothing,
    )
end

function _target_identity_payload(m::StarModel)
    return (;
        I = m.I,
        R = m.R,
        D = m.D,
        M = m.M,
        entity = m.entity,
        rater = m.rater,
        y = m.y,
        entity_levels = m.entity_levels,
        rater_levels = m.rater_levels,
        event_ids = m.event_ids,
        criteria = [(; c.id, c.role, c.levels, c.direction, c.threshold_group) for c in m.criteria],
        prior = _prior_namedtuple(m.prior),
        spec = (;
            m.spec.entity_mode,
            m.spec.rater_mode,
            m.spec.entity_cp_min_hd,
            m.spec.rater_cp_min_hd,
            m.spec.basis_order,
            m.spec.include_phi,
            m.spec.reference_prior,
        ),
    )
end

function _partial_correlations_from_R(R_mat::AbstractMatrix{Float64})
    L_R = cholesky(Symmetric(Matrix(R_mat))).L
    invL = Matrix(inv(LowerTriangular(L_R)))
    P = invL' * invL
    D = size(P, 1)
    return [-P[i, j] / sqrt(max(P[i, i] * P[j, j], eps(Float64))) for i in 2:D for j in 1:(i - 1)]
end

function _substantive_names_and_fixed(m::StarModel)
    cids = [c.id for c in m.criteria]
    branches = cids[2:end]
    names = String[]
    append!(names, ["cor_entity_direct[$b]" for b in branches])
    append!(names, ["cor_entity_ref_expected_score[$b]" for b in branches])
    for c1 in 2:m.D, c2 in 2:(c1 - 1)
        push!(names, "cor_entity_inter_branch[$(cids[c2]),$(cids[c1])]")
    end
    for i in 2:m.D, j in 1:(i - 1)
        push!(names, "R_entity[$(cids[j]),$(cids[i])]")
    end
    for i in 2:m.D, j in 1:(i - 1)
        push!(names, "partial_corr_entity[$(cids[j]),$(cids[i])]")
    end
    for i in 2:m.D, j in 1:(i - 1)
        push!(names, "R_rater[$(cids[j]),$(cids[i])]")
    end
    for i in 2:m.D, j in 1:(i - 1)
        push!(names, "partial_corr_rater[$(cids[j]),$(cids[i])]")
    end
    append!(names, ["cor_rater_severity[$b]" for b in branches])
    append!(names, ["phi[$b]" for b in branches])
    append!(names, ["entity_sd[$c]" for c in cids])
    append!(names, ["rater_sd[$c]" for c in cids])
    append!(names, ["mu[$c]" for c in cids])
    for c in 1:m.D, k in 1:m.M[c]
        push!(names, "ref_step[$(cids[c]),$k]")
    end
    positive = Set(vcat(["entity_sd[$c]" for c in cids], ["rater_sd[$c]" for c in cids]))
    fixed = Set{String}()
    if !m.spec.include_phi
        union!(fixed, ("phi[$b]" for b in branches))
    end
    for c in 1:m.D
        if m.M[c] == 1
            push!(fixed, "ref_step[$(cids[c]),1]")
        end
    end
    return names, positive, fixed
end

function _raw_names(m::StarModel)
    b = _layout(m)
    names = fill("", b.dim)
    for blk in (:zi, :zr, :mu, :si, :sr, :ci, :cr, :phi)
        for (j, k) in enumerate(getproperty(b, blk))
            names[k] = "$blk[$j]"
        end
    end
    for c in 1:m.D, (j, k) in enumerate(b.steps[c])
        names[k] = "step_white[$c,$j]"
    end
    return names
end

"""
    parameter_names(m::StarModel; space=:substantive)

List parameter names in `:substantive`, `:raw`, or `:transformed` coordinate space.
"""
function parameter_names(m::StarModel; space::Symbol = :substantive)
    if space === :substantive
        return first(_substantive_names_and_fixed(m))
    elseif space === :raw
        return _raw_names(m)
    elseif space === :transformed
        return _transformed_coord_names(m)
    end
    throw(ArgumentError("space must be :substantive, :raw, or :transformed"))
end

function _extract_substantive_draws(m::StarModel, draws::AbstractMatrix{Float64})
    S = size(draws, 1)
    D = m.D
    names, positive, fixed = _substantive_names_and_fixed(m)
    mat = Matrix{Float64}(undef, S, length(names))
    s_scr = _scratch(m.M, Float64)
    eta = zeros(Float64, D)
    exp_sc = Matrix{Float64}(undef, m.I, D)
    score_vals = [
        m.criteria[c].direction === :higher_is_more ? Float64.(m.criteria[c].canonical_to_raw) : Float64.(0:m.M[c])
        for c in 1:D
    ]
    for s in 1:S
        q_s = view(draws, s, :)
        v = _coordinates(m, q_s; raw_input = false)
        v_ref = _reference_mu_and_tau(m, q_s)
        ri = Matrix(C.correlation_state(q_s[v.b.ci], D; eta = m.prior.entity_lkj_eta).R)
        rr = Matrix(C.correlation_state(q_s[v.b.cr], D; eta = m.prior.rater_lkj_eta).R)
        @inbounds for i in 1:m.I
            for c in 1:D
                eta[c] = v.mu[c] + v.A[i, c]
            end
            _event_kernel!(s_scr, eta, v.tau, v.phi, m.M)
            for c in 1:D
                sv = score_vals[c]
                es = 0.0
                for k in 0:m.M[c]
                    es += sv[k + 1] * s_scr.pm[k + 1, c]
                end
                exp_sc[i, c] = es
            end
        end
        mat[s, :] .= vcat(
            [cor(view(v.A, :, 1), view(v.A, :, c)) for c in 2:D],
            [cor(view(exp_sc, :, 1), view(exp_sc, :, c)) for c in 2:D],
            [cor(view(v.A, :, c2), view(v.A, :, c1)) for c1 in 2:D for c2 in 2:(c1 - 1)],
            [ri[i, j] for i in 2:D for j in 1:(i - 1)],
            _partial_correlations_from_R(ri),
            [rr[i, j] for i in 2:D for j in 1:(i - 1)],
            _partial_correlations_from_R(rr),
            [cor(view(v.S, :, 1), view(v.S, :, c)) for c in 2:D],
            v.phi,
            exp.(q_s[v.b.si]),
            exp.(q_s[v.b.sr]),
            v_ref.mu,
            vcat(v_ref.tau...),
        )
    end
    return (; names, draws = mat, positive, fixed)
end

function _sampler_chain_rows(cfg::SamplerConfig, warm_stats, ret_stats, provenance)
    cmeta = hasproperty(provenance, :chain_meta) ? provenance.chain_meta : nothing
    return map(1:cfg.chains) do c
        rs = filter(x -> x.chain == c, ret_stats)
        ws = filter(x -> x.chain == c, warm_stats)
        e = isempty(rs) ? Float64[] : [Float64(x.hamiltonian_energy) for x in rs]
        bfmi = length(e) >= 2 ? mean(abs2, diff(e)) / max(var(e; corrected = false), eps(Float64)) : NaN
        cm = cmeta === nothing ? nothing : findfirst(x -> x.chain == c, cmeta)
        nonfin = count(x -> hasproperty(x, :log_density) && !isfinite(x.log_density), rs)
        init_eps = if cm !== nothing && hasproperty(cmeta[cm], :initial_step_size)
            cmeta[cm].initial_step_size
        elseif !isempty(ws)
            first(ws).step_size
        else
            missing
        end
        (;
            chain = c,
            warmup_iterations = length(ws),
            retained_draws = length(rs),
            warmup_divergences = count(x -> x.numerical_error, ws),
            retained_divergences = count(x -> x.numerical_error, rs),
            retained_depth_hits = count(x -> x.tree_depth >= cfg.max_depth, rs),
            nonfinite_logdensity = nonfin,
            e_bfmi = bfmi,
            mean_acceptance = isempty(rs) ? NaN : mean(x.acceptance_rate for x in rs),
            initial_step_size = init_eps,
            final_step_size = isempty(rs) ? NaN : last(rs).step_size,
            mean_n_steps = isempty(rs) ? NaN : mean(x.n_steps for x in rs),
            gradient_calls = cm === nothing ? missing : cmeta[cm].calls,
            numerical_rejections = cm === nothing ? missing : cmeta[cm].numerical_rejections,
            elapsed_seconds = cm === nothing ? missing : cmeta[cm].elapsed_seconds,
        )
    end
end

function _compute_sampling_quality(cfg::SamplerConfig, sub, warm_stats, ret_stats, provenance)
    s_rows = _sampler_chain_rows(cfg, warm_stats, ret_stats, provenance)
    sub_diag = B._candidate_mcmc_diagnostic_rows(
        sub.draws,
        sub.names,
        cfg.chains;
        parameter_space = :substantive,
        structurally_fixed_parameters = sub.fixed,
        split_chains = true,
        rhat_threshold = 1.01,
        ess_threshold = 400.0,
    )
    fin(x) = x isa Real && isfinite(x)
    function pass_row(r)
        r.parameter in sub.fixed && return true
        return fin(r.rank_normalized_rhat) && r.rank_normalized_rhat <= 1.01 &&
            fin(r.bulk_ess) && r.bulk_ess >= 400.0 &&
            fin(r.tail_ess) && r.tail_ess >= 400.0
    end
    s_ok = all(
        r -> r.retained_divergences == 0 &&
            r.retained_depth_hits == 0 &&
            r.nonfinite_logdensity == 0 &&
            fin(r.e_bfmi) && r.e_bfmi >= 0.3,
        s_rows,
    )
    d_ok = cfg.chains >= 2 && all(pass_row, sub_diag)
    free_rows = [r for r in sub_diag if !(r.parameter in sub.fixed)]
    mx_rh = isempty(free_rows) ? NaN : maximum(
        fin(r.rank_normalized_rhat) ? Float64(r.rank_normalized_rhat) : Inf for r in free_rows
    )
    mn_ess = isempty(free_rows) ? NaN : minimum(
        fin(r.bulk_ess) ? Float64(r.bulk_ess) : 0.0 for r in free_rows
    )
    qual = (;
        sampler_ok = s_ok,
        substantive_diagnostics_ok = d_ok,
        chains = cfg.chains,
        retained_draws = size(sub.draws, 1),
        retained_divergences = sum(r.retained_divergences for r in s_rows),
        retained_depth_hits = sum(r.retained_depth_hits for r in s_rows),
        min_e_bfmi = minimum(r.e_bfmi for r in s_rows),
        max_substantive_rhat = mx_rh,
        min_substantive_bulk_ess = mn_ess,
    )
    return qual, !(s_ok && d_ok)
end

function _stat_logdensity(x)
    hasproperty(x, :log_density) && return Float64(x.log_density)
    hasproperty(x, :lp) && return Float64(x.lp)
    return NaN
end

function _retained_logdensities(m::StarModel, draws::Matrix{Float64}, ret_stats)
    S = size(draws, 1)
    if length(ret_stats) == S
        lds = [_stat_logdensity(x) for x in ret_stats]
        if all(isfinite, lds)
            check_idxs = unique((1, cld(S, 3), cld(2 * S, 3), S))
            ok = all(check_idxs) do idx
                ref_ld = L.logdensity(m, view(draws, idx, :))
                abs(lds[idx] - ref_ld) / max(1.0, abs(lds[idx])) <= 1e-10
            end
            ok && return lds
        end
    end
    return [L.logdensity(m, view(draws, s, :)) for s in 1:S]
end

function _build_star_result(
    m::StarModel,
    cfg::SamplerConfig,
    draws::Matrix{Float64},
    warm_stats,
    ret_stats;
    provenance = (; operation = :fit),
    warnings::Vector{String} = ["Experimental model; scientific prior choice, fit and sensitivity require assessment."],
)
    (size(draws) == (cfg.chains * cfg.ndraws, m.dim) && all(isfinite, draws)) ||
        throw(ArgumentError("invalid draws shape or nonfinite values"))
    lds = _retained_logdensities(m, draws, ret_stats)
    all(isfinite, lds) || throw(ArgumentError("nonfinite retained log-density"))
    t_id = B._cache_hash(_target_identity_payload(m))
    src = _source_signature()
    sub = _extract_substantive_draws(m, draws)
    qual, swarn = _compute_sampling_quality(cfg, sub, warm_stats, ret_stats, provenance)
    w_out = copy(warnings)
    if m.spec.basis_order === :legacy_lexicographic
        push!(w_out, "Legacy lexicographic Helmert basis used; contrast CP/NCP assignment is not label-permutation invariant.")
    end
    if cfg.init === :shared_warmstart
        push!(w_out, "Shared single-mode warm-start initialization used; between-chain R-hat may underestimate non-convergence on multimodal or weakly identified posteriors.")
    end
    if cfg.adaptation === :clamped_regularized
        push!(w_out, "Experimental clamped_regularized warmup adaptation used; step-size bounds and metric ratio caps may cause divergences on high-curvature or misspecified-scale posteriors.")
    end
    if swarn
        push!(w_out, "Sampling warning: MCMC diagnostics below qualification thresholds (inspect qualify/diagnostics).")
    end
    sub_hash = B._cache_hash((; names = sub.names, draws = sub.draws))
    body = (;
        schema = RESULT_SCHEMA,
        target_identity = t_id,
        source = src,
        provenance,
        warnings = w_out,
        sampling_quality = qual,
        sampling_warning = swarn,
        draws_hash = B._cache_hash(draws),
        logdensities_hash = B._cache_hash(lds),
        substantive_hash = sub_hash,
    )
    res = StarResult(
        RESULT_SCHEMA,
        m,
        cfg,
        draws,
        lds,
        warm_stats,
        ret_stats,
        qual,
        swarn,
        t_id,
        src,
        provenance,
        w_out,
        sub_hash,
        B._cache_hash(body),
    )
    return _verify_result(res)
end

function _verify_result(res::StarResult)
    res.schema == RESULT_SCHEMA || throw(ArgumentError("unsupported StarResult schema"))
    isequal(res.source, _source_signature()) || throw(ArgumentError("source or environment changed"))
    B._cache_hash(_target_identity_payload(res.model)) == res.target_identity ||
        throw(ArgumentError("target identity mismatch"))
    S = res.config.chains * res.config.ndraws
    (size(res.draws) == (S, res.model.dim) &&
        all(isfinite, res.draws) &&
        length(res.logdensities) == S &&
        all(isfinite, res.logdensities)) ||
        throw(ArgumentError("corrupted draws or logdensities"))
    body = (;
        schema = res.schema,
        target_identity = res.target_identity,
        source = res.source,
        provenance = res.provenance,
        warnings = res.warnings,
        sampling_quality = res.sampling_quality,
        sampling_warning = res.sampling_warning,
        draws_hash = B._cache_hash(res.draws),
        logdensities_hash = B._cache_hash(res.logdensities),
        substantive_hash = res.substantive_hash,
    )
    B._cache_hash(body) == res.content_hash || throw(ArgumentError("result content checksum mismatch"))
    for idx in unique((1, cld(S, 2), S))
        ld = L.logdensity(res.model, view(res.draws, idx, :))
        (isfinite(ld) && abs(ld - res.logdensities[idx]) / max(1.0, abs(ld)) <= 1e-10) ||
            throw(ArgumentError("stored log-density mismatch at draw $idx"))
    end
    return res
end

"""
    save_fit(path, res::StarResult)

Save a checksum-verified `StarResult` atomically (`save_result` is provided as an alias).
"""
function save_fit(path::AbstractString, res::StarResult)
    _verify_result(res)
    return B._save_serialized_record(path, res; overwrite = false)
end

save_result(path::AbstractString, res::StarResult) = save_fit(path, res)

"""
    load_fit(path)

Restore and checksum-verify a saved `StarResult` (`load_result` is provided as an alias).
"""
function load_fit(path::AbstractString)
    res = open(deserialize, path)
    res isa StarResult || throw(ArgumentError("file does not contain a StarResult"))
    return _verify_result(res)
end

load_result(path::AbstractString) = load_fit(path)

function from_saved_blocks(
    m::StarModel,
    dir::AbstractString;
    warmup::Int,
    ndraws::Int,
    chains::Int = 4,
    seed::Integer = 20261030,
    kwargs...,
)
    cfg = _build_sampler_config(; ndraws, warmup, chains, seed, kwargs...)
    assembled = [_assemble_chain_blocks(joinpath(dir, "chain-$c"), warmup, ndraws, m.dim) for c in 1:chains]
    draws = vcat([a.draws for a in assembled]...)
    warm_stats = vcat([a.warm_stats for a in assembled]...)
    ret_stats = vcat([a.ret_stats for a in assembled]...)
    meta = [a.meta for a in assembled]
    return _build_star_result(
        m,
        cfg,
        draws,
        warm_stats,
        ret_stats;
        provenance = (;
            operation = :from_saved_blocks,
            source_directory = basename(normpath(dir)),
            controls = sampler_controls(cfg),
            chain_meta = meta,
        ),
    )
end

"""
    reparameterize_draws(res::StarResult, target_model::StarModel)

Transform all retained posterior draws of `res` into `target_model`'s coordinate chart
(supporting both `:cp`/`:ncp`/`:cp_ncp` and `:descending_schur`/`:legacy_lexicographic` changes)
while preserving identical physical coordinates `(A, S, mu, tau, phi)` and substantive posteriors.
"""
function reparameterize_draws(res::StarResult, target_model::StarModel)
    _verify_result(res)
    m = res.model
    (m.I == target_model.I &&
        m.R == target_model.R &&
        m.D == target_model.D &&
        m.M == target_model.M &&
        m.entity == target_model.entity &&
        m.rater == target_model.rater &&
        m.y == target_model.y &&
        m.spec.include_phi == target_model.spec.include_phi &&
        m.spec.reference_prior == target_model.spec.reference_prior &&
        _prior_namedtuple(m.prior) == _prior_namedtuple(target_model.prior)) ||
        throw(ArgumentError("target_model must share identical data, prior, association, and reference_prior"))
    S = size(res.draws, 1)
    new_draws = Matrix{Float64}(undef, S, target_model.dim)
    new_lds = Vector{Float64}(undef, S)
    for s in 1:S
        q_old = view(res.draws, s, :)
        q_new = reparameterize_point(target_model, m, q_old)
        new_draws[s, :] .= q_new
        new_lds[s] = res.logdensities[s] + log_jacobian_to_ncp(target_model, q_new) - log_jacobian_to_ncp(m, q_old)
    end
    new_ret_stats = if length(res.retained_stats) == S
        [merge(res.retained_stats[s], (; log_density = new_lds[s])) for s in 1:S]
    else
        NamedTuple[]
    end
    return _build_star_result(
        target_model,
        res.config,
        new_draws,
        res.warmup_stats,
        new_ret_stats;
        provenance = (;
            operation = :reparameterize_draws,
            parent_hash = res.content_hash,
            chain_meta = hasproperty(res.provenance, :chain_meta) ? res.provenance.chain_meta : nothing,
        ),
    )
end

function _envelope(res::StarResult, operation::Symbol, payload)
    return (;
        schema = REPORT_SCHEMA,
        operation,
        api = contract(),
        target_identity = res.target_identity,
        source_sample_content_hash = res.content_hash,
        sampling_warning = res.sampling_warning,
        sampling_quality = res.sampling_quality,
        provenance = deepcopy(res.provenance),
        warnings = copy(res.warnings),
        result = payload,
    )
end

function _sanitize_scale_direction(row, positive_set::Set{String}, fixed_set::Set{String})
    if row.parameter in positive_set
        return merge(
            row,
            (;
                reference = missing,
                probability_positive = missing,
                probability_negative = missing,
                probability_equal = missing,
                probability_of_direction = missing,
                direction = :not_applicable_positive_scale,
            ),
        )
    end
    if row.parameter in fixed_set
        return merge(
            row,
            (;
                reference = 0.0,
                probability_positive = missing,
                probability_negative = missing,
                probability_equal = 1.0,
                probability_of_direction = missing,
                direction = :structurally_fixed,
            ),
        )
    end
    return row
end

"""
    posterior_summary(res::StarResult; parameters=nothing, interval=0.95, intervals=nothing, rope=nothing, include_raw_diagnostics=false)

Summarize substantive model estimands with posterior means, SDs, credible intervals,
chain-aware MCSEs, and split-R-hat/ESS diagnostics (`report` is provided as an alias).
"""
function posterior_summary(
    res::StarResult;
    parameters = nothing,
    interval::Real = 0.95,
    intervals = nothing,
    rope = nothing,
    include_raw_diagnostics::Bool = false,
)
    (isfinite(interval) && 0 < interval < 1) || throw(ArgumentError("interval must be in (0, 1)"))
    _verify_result(res)
    sub = _extract_substantive_draws(res.model, res.draws)
    B._cache_hash((; names = sub.names, draws = sub.draws)) == res.substantive_hash ||
        throw(ArgumentError("substantive draws hash mismatch"))
    sel = parameters === nothing ? sub.names : collect(String, parameters)
    (!isempty(sel) && allunique(sel) && all(n -> n in sub.names, sel)) ||
        throw(ArgumentError("parameters must be distinct names in substantive estimands"))
    ix = [only(findall(==(n), sub.names)) for n in sel]
    vals = sub.draws[:, ix]
    lo = (1.0 - Float64(interval)) / 2.0
    hi = 1.0 - lo
    ivs = intervals === nothing ? (Float64(interval),) : Tuple(Float64.(collect(intervals)))
    raw_post = B._posterior_summary_rows(
        vals,
        sel;
        lower = lo,
        upper = hi,
        intervals = ivs,
        reference = 0.0,
        rope,
        rope_probability_threshold = 0.95,
    )
    post = [_sanitize_scale_direction(r, sub.positive, sub.fixed) for r in raw_post]
    probs = Tuple(
        sort(unique([lo, 0.5, hi, [p for m_iv in ivs for p in ((1.0 - m_iv) / 2.0, (1.0 + m_iv) / 2.0)]...]))
    )
    mcse = B._posterior_mcse_rows(
        vals,
        sel,
        res.config.chains;
        probabilities = probs,
        parameter_space = :substantive,
        structurally_fixed_parameters = sub.fixed,
    )
    sub_diag = B._candidate_mcmc_diagnostic_rows(
        sub.draws,
        sub.names,
        res.config.chains;
        parameter_space = :substantive,
        structurally_fixed_parameters = sub.fixed,
        split_chains = true,
        rhat_threshold = 1.01,
        ess_threshold = 400.0,
    )
    raw_diag = include_raw_diagnostics ? B._candidate_mcmc_diagnostic_rows(
        res.draws,
        _raw_names(res.model),
        res.config.chains;
        parameter_space = :raw_unconstrained,
        split_chains = true,
        rhat_threshold = 1.01,
        ess_threshold = 400.0,
    ) : nothing
    sampler = _sampler_chain_rows(res.config, res.warmup_stats, res.retained_stats, res.provenance)
    return _envelope(
        res,
        :report,
        (;
            posterior = post,
            mcse,
            scale_evidence = :positive_support_is_not_evidence_against_zero,
            diagnostics = (; substantive = sub_diag, raw = raw_diag, sampler),
            parameter_names = sub.names,
        ),
    )
end

report(res::StarResult; kwargs...) = posterior_summary(res; kwargs...)

function contrast(
    res::StarResult;
    facet::Symbol,
    criterion::AbstractString,
    left::AbstractString,
    right::AbstractString,
    interval::Real = 0.95,
    rope = nothing,
)
    _verify_result(res)
    m = res.model
    (facet in (:entity, :rater) && left != right) ||
        throw(ArgumentError("facet must be :entity or :rater with distinct IDs"))
    c_idx = findfirst(c -> c.id == criterion, m.criteria)
    c_idx !== nothing || throw(ArgumentError("unknown criterion '$criterion'"))
    levels = facet === :entity ? m.entity_levels : m.rater_levels
    i_l = findfirst(==(left), levels)
    i_r = findfirst(==(right), levels)
    (i_l !== nothing && i_r !== nothing) || throw(ArgumentError("unknown $facet level ID"))
    S = size(res.draws, 1)
    v_l = Vector{Float64}(undef, S)
    v_r = Vector{Float64}(undef, S)
    for s in 1:S
        coords = _coordinates(m, view(res.draws, s, :); raw_input = false)
        F = facet === :entity ? coords.A : coords.S
        v_l[s] = F[i_l, c_idx]
        v_r[s] = F[i_r, c_idx]
    end
    summary = B.posterior_contrast(v_l, v_r; chains = res.config.chains, interval = Float64(interval), rope)
    return _envelope(
        res,
        :facet_contrast,
        (;
            facet,
            criterion = String(criterion),
            left = String(left),
            right = String(right),
            direction = m.criteria[c_idx].direction,
            positive_difference = facet === :entity ? :higher_canonical_trait : :greater_severity,
            summary,
        ),
    )
end

function _shift_mcse_bound(pm, bm, p_fixed::Bool, b_fixed::Bool)
    (p_fixed && b_fixed) && return missing
    vp = p_fixed ? 0.0 : ((pm.mean_mcse isa Real && isfinite(pm.mean_mcse)) ? Float64(pm.mean_mcse) : NaN)
    vb = b_fixed ? 0.0 : ((bm.mean_mcse isa Real && isfinite(bm.mean_mcse)) ? Float64(bm.mean_mcse) : NaN)
    return isfinite(vp + vb) ? (vp + vb) : missing
end

function contrast(primary::StarResult, baseline::StarResult; interval::Real = 0.95)
    _verify_result(primary)
    _verify_result(baseline)
    p_rep = posterior_summary(primary; interval).result
    b_rep = posterior_summary(baseline; interval).result
    p_rep.parameter_names == b_rep.parameter_names ||
        throw(ArgumentError("estimand sets do not match between models"))
    _, _, p_fix = _substantive_names_and_fixed(primary.model)
    _, _, b_fix = _substantive_names_and_fixed(baseline.model)
    rows = map(eachindex(p_rep.posterior)) do j
        pr = p_rep.posterior[j]
        br = b_rep.posterior[j]
        pm = p_rep.mcse[j]
        bm = b_rep.mcse[j]
        (;
            parameter = pr.parameter,
            primary_mean = pr.mean,
            primary_lower = pr.lower,
            primary_upper = pr.upper,
            baseline_mean = br.mean,
            baseline_lower = br.lower,
            baseline_upper = br.upper,
            mean_shift_primary_minus_baseline = pr.mean - br.mean,
            conservative_mean_shift_mcse_bound = _shift_mcse_bound(
                pm, bm, pr.parameter in p_fix, br.parameter in b_fix,
            ),
        )
    end
    return _envelope(
        primary,
        :model_contrast,
        (;
            baseline_content_hash = baseline.content_hash,
            baseline_sampling_warning = baseline.sampling_warning,
            any_sampling_warning = primary.sampling_warning || baseline.sampling_warning,
            shifts = rows,
        ),
    )
end

function _event_prob_columns(
    m::StarModel,
    include_joint::Bool,
    include_conditional::Bool,
    include_full_cartesian::Bool,
)
    names = ["marginal[$(m.criteria[c].id),$(m.criteria[c].canonical_to_raw[k + 1])]" for c in 1:m.D for k in 0:m.M[c]]
    push!(names, "observed_event_joint_prob")
    r_meta = m.criteria[1]
    if include_joint
        for c in 2:m.D, k in 0:m.M[1], l in 0:m.M[c]
            push!(names, "joint[$(r_meta.id)=$(r_meta.canonical_to_raw[k + 1]),$(m.criteria[c].id)=$(m.criteria[c].canonical_to_raw[l + 1])]")
        end
    end
    if include_conditional
        for c in 2:m.D, k in 0:m.M[1], l in 0:m.M[c]
            push!(names, "cond[$(m.criteria[c].id)=$(m.criteria[c].canonical_to_raw[l + 1])|$(r_meta.id)=$(r_meta.canonical_to_raw[k + 1])]")
        end
    end
    if include_full_cartesian
        n_cart = prod(mc + 1 for mc in m.M)
        n_cart <= 4096 || throw(ArgumentError("full Cartesian table has $n_cart > 4096 cells; use root-branch joint tables"))
        for idx in CartesianIndices(Tuple((0:mc) for mc in m.M))
            lbl = join(["$(m.criteria[c].id)=$(m.criteria[c].canonical_to_raw[idx[c] + 1])" for c in 1:m.D], ",")
            push!(names, "cartesian[$lbl]")
        end
    end
    return names
end

function _fill_event_prob_row!(
    dest,
    m::StarModel,
    e_idx::Int,
    s_scr,
    include_joint::Bool,
    include_conditional::Bool,
    include_full_cartesian::Bool,
)
    pos = 0
    for c in 1:m.D, k in 0:m.M[c]
        pos += 1
        dest[pos] = s_scr.pm[k + 1, c]
    end
    y0 = m.y[1, e_idx]
    p_obs = s_scr.pm[y0 + 1, 1]
    for c in 2:m.D
        p_obs *= s_scr.cond[m.y[c, e_idx] + 1, y0 + 1, c - 1]
    end
    pos += 1
    dest[pos] = p_obs
    if include_joint
        for c in 2:m.D, k in 0:m.M[1], l in 0:m.M[c]
            pos += 1
            dest[pos] = s_scr.pm[k + 1, 1] * s_scr.cond[l + 1, k + 1, c - 1]
        end
    end
    if include_conditional
        for c in 2:m.D, k in 0:m.M[1], l in 0:m.M[c]
            pos += 1
            dest[pos] = s_scr.cond[l + 1, k + 1, c - 1]
        end
    end
    if include_full_cartesian
        for idx in CartesianIndices(Tuple((0:mc) for mc in m.M))
            pr = s_scr.pm[idx[1] + 1, 1]
            for c in 2:m.D
                pr *= s_scr.cond[idx[c] + 1, idx[1] + 1, c - 1]
            end
            pos += 1
            dest[pos] = pr
        end
    end
    return dest
end

function event_probabilities(
    res::StarResult;
    rating_event_id::AbstractString,
    interval::Real = 0.95,
    include_joint::Bool = true,
    include_conditional::Bool = true,
    include_full_cartesian::Bool = false,
)
    (isfinite(interval) && 0 < interval < 1) || throw(ArgumentError("interval must be in (0, 1)"))
    _verify_result(res)
    m = res.model
    e_idx = findfirst(==(String(rating_event_id)), m.event_ids)
    e_idx !== nothing || throw(ArgumentError("unknown rating_event_id '$rating_event_id'"))
    S = size(res.draws, 1)
    i = m.entity[e_idx]
    r = m.rater[e_idx]
    col_names = _event_prob_columns(m, include_joint, include_conditional, include_full_cartesian)
    vals = Matrix{Float64}(undef, S, length(col_names))
    s_scr = _scratch(m.M, Float64)
    eta = zeros(Float64, m.D)
    for s in 1:S
        v = _coordinates(m, view(res.draws, s, :); raw_input = false)
        for c in 1:m.D
            eta[c] = v.mu[c] + v.A[i, c] - v.S[r, c]
        end
        _event_kernel!(s_scr, eta, v.tau, v.phi, m.M)
        _fill_event_prob_row!(view(vals, s, :), m, e_idx, s_scr, include_joint, include_conditional, include_full_cartesian)
    end
    lo = (1.0 - Float64(interval)) / 2.0
    hi = 1.0 - lo
    post = B._posterior_summary_rows(
        vals,
        col_names;
        lower = lo,
        upper = hi,
        intervals = (Float64(interval),),
        reference = 0.0,
        rope = nothing,
        rope_probability_threshold = 0.95,
    )
    mcse = B._posterior_mcse_rows(
        vals,
        col_names,
        res.config.chains;
        probabilities = (lo, 0.5, hi),
        parameter_space = :event_joint_and_marginal_probability,
    )
    obs_raw = [m.criteria[c].canonical_to_raw[m.y[c, e_idx] + 1] for c in 1:m.D]
    return _envelope(
        res,
        :event_probabilities,
        (;
            rating_event_id = String(rating_event_id),
            entity = m.entity_levels[i],
            rater = m.rater_levels[r],
            observed_raw = obs_raw,
            conditioning = :existing_entity_and_rater_in_sample,
            posterior = post,
            mcse,
        ),
    )
end

function save_report(path::AbstractString, rep)
    (ispath(path) || islink(path)) && throw(ArgumentError("refusing to overwrite existing report: $path"))
    rep.schema == REPORT_SCHEMA || throw(ArgumentError("invalid report schema"))
    mkpath(dirname(path))
    env = (;
        schema = JSON_ENVELOPE_SCHEMA,
        encoding = "RFC-8259 JSON; NaN/Inf/-Inf encoded as {nonfinite: ...}; missing encoded as null.",
        data = _jsonsafe(rep),
    )
    return _save_atomic_json(path, env)
end

function load_report(path::AbstractString)
    parsed = JSON3.read(read(path, String))
    String(parsed.schema) == JSON_ENVELOPE_SCHEMA ||
        throw(ArgumentError("invalid JSON report envelope schema"))
    return parsed.data
end
