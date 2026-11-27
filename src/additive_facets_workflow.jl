# Included inside AdditiveFacets; the package's lifecycle verbs dispatch below.
const FIT_SCHEMA = "bayesianmgmfrm.additive_facet_fit.v1"
const REPORT_SCHEMA = "bayesianmgmfrm.additive_facet_report.v1"

struct Fit <: B.AbstractMFRMFit
    record::NamedTuple
end

B._check_source_fixture_raw_vector(t::AbstractTarget,q::AbstractVector)=_check(t,q)

function checked(f::Fit; full = false)
    stored = f.record
    keys(stored) == (:schema, :target, :target_identity, :run, :producer, :content_hash) &&
        stored.schema == FIT_SCHEMA || throw(ArgumentError("unsupported additive fit record"))

    # Verify record integrity before rebuilding the target or using draws.
    body = (; stored.schema, stored.target, stored.target_identity, stored.run, stored.producer)
    B._cache_hash(body) == stored.content_hash &&
        B._cache_hash(stored.target) == stored.target_identity ||
        throw(ArgumentError("additive fit content/target checksum mismatch"))
    target = restore(stored.target)
    target.allocation.identified ||
        throw(ArgumentError("stored additive fit design is rank deficient"))
    if full
        B._check_generalized_sample_run(target, stored.run)
        length(stored.run.warmup_stats) == stored.run.controls.chains * stored.run.controls.warmup ||
            throw(ArgumentError("incomplete additive warmup telemetry"))
        B._warmup_diagnostic_rows(stored.run.warmup_stats, stored.run.controls, stored.run.backend)
    end
    return target
end

allocation_error(t)="additive facet design has rank $(t.allocation.rank)/$(t.dimension); inspect design_summary"
prediction_conditioning(t)=:known_finite_panel_levels
contrast_unit(t,left,right)=:unit_logit

# Exact volume-preserving (log|det J| === 0) Givens orthogonalization between
# the sample mean of person white-noise coordinates (1/sqrt(P) * sum(z_p)) and
# `population_mean` on standard 1D MRCMLTarget. Eliminates the (population_mean,
# mean(person_z)) posterior ridge under diagonal NUTS while reducing smoothly to
# the identity as residual_sd[person] -> 0 (zero funnel, zero outcome dependence,
# label-permutation invariant, identical target distribution and logdensity).
struct _GivensMeanBlock
    persons::Vector{Int}
    inv_sqrtP::Float64
    idx_mu::Int
    sd_mu::Float64
    idx_h::Int
    pkind::Symbol
    logmean::Float64
    logsd::Float64
    fixed_sd::Float64
end

struct _MRCMLMeanGivensTarget
    base::MRCMLTarget
    blocks::Vector{_GivensMeanBlock}
    single_full_panel::Bool
    dimension::Int
end

B._check_source_fixture_raw_vector(t::_MRCMLMeanGivensTarget, q::AbstractVector) = _check(t, q)

function _maybe_mrcml_givens_target(t::AbstractTarget)
    t isa MRCMLTarget || return nothing
    P = length(t.people)
    P >= 2 || return nothing
    isnothing(_person_chart(t)) || return nothing
    pop = get(t.spec_record, :population, nothing)
    if pop !== nothing
        sd_mu = Float64(pop.coefficient_prior.sd)
        sd_mu > 0.0 || return nothing
        sp = pop.sd_prior
        pkind = Symbol(get(sp, :kind, :lognormal))
        sp_lm = Float64(sp.logmean)
        sp_ls = Float64(sp.logsd)
        sp_fix = Float64(get(sp, :sd, 1.0))
        eq_sd = length(pop.logsd) == 1
        ref_g = only(findall(==(pop.reference), pop.groups))
        other_gs = findall(!=(pop.reference), pop.groups)
        has_int = Bool(get(pop, :has_intercept, false))
        int_off = has_int ? 1 : 0
        gblocks = _GivensMeanBlock[]
        if has_int
            ps_ref = findall(==(ref_g), pop.group_index)
            if !isempty(ps_ref)
                idx_h_ref = eq_sd ? first(pop.logsd) : pop.logsd[ref_g]
                push!(gblocks, _GivensMeanBlock(
                    ps_ref, inv(sqrt(Float64(length(ps_ref)))),
                    pop.beta[1], sd_mu, idx_h_ref, pkind, sp_lm, sp_ls, sp_fix,
                ))
            end
        end
        for (k, g_idx) in enumerate(other_gs)
            ps_g = findall(==(g_idx), pop.group_index)
            isempty(ps_g) && continue
            idx_h_g = eq_sd ? first(pop.logsd) : pop.logsd[g_idx]
            push!(gblocks, _GivensMeanBlock(
                ps_g, inv(sqrt(Float64(length(ps_g)))),
                pop.beta[int_off + k], sd_mu, idx_h_g, pkind, sp_lm, sp_ls, sp_fix,
            ))
        end
        isempty(gblocks) && return nothing
        return _MRCMLMeanGivensTarget(t, gblocks, false, t.dimension)
    end
    (t.person_hyper_idx > 0 || t.person_sd > 0) || return nothing
    mu_blocks = [b for b in t.prior_blocks if b.name === :population_mean &&
        b.kind === :white_scaled && length(b.raw_range) == 1 && length(b.eta_range) == 1 &&
        b.scale_vec[1] > 0.0]
    length(mu_blocks) == 1 || return nothing
    bmu = mu_blocks[1]
    ei = first(bmu.eta_range)
    col_ok = all(r -> t.operator.A_free[r, ei] == t.operator.B_pat[r], eachindex(t.operator.B_pat))
    col_ok || return nothing
    blk = _GivensMeanBlock(
        collect(1:P), inv(sqrt(Float64(P))), first(bmu.raw_range), Float64(bmu.scale_vec[1]),
        t.person_hyper_idx, _person_scale_kind(t), t.person_logmean, t.person_logsd, t.person_sd,
    )
    return _MRCMLMeanGivensTarget(t, [blk], true, t.dimension)
end

@inline function _givens_block_coeffs(blk::_GivensMeanBlock, u::AbstractVector{T}) where {T}
    if blk.idx_h > 0
        s_p = _scale_from_raw(blk.pkind, blk.logmean, blk.logsd, u[blk.idx_h])
        ds_dq = s_p * _scale_dlogsig_du(blk.pkind, blk.logsd)
    else
        s_p = T(blk.fixed_sd)
        ds_dq = zero(T)
    end
    inv_sqrtP = blk.inv_sqrtP
    alpha = s_p * inv_sqrtP
    r = hypot(T(blk.sd_mu), alpha)
    c = T(blk.sd_mu) / r
    g = alpha / r
    inv_r_sqrtP = inv_sqrtP / r
    dc_dq = (-c * g * inv_r_sqrtP) * ds_dq
    dg_dq = (c * c * inv_r_sqrtP) * ds_dq
    return (c, g, dc_dq, dg_dq)
end

function _givens_to_raw(gt::_MRCMLMeanGivensTarget, u::AbstractVector{T}) where {T}
    q = Vector{T}(u)
    if gt.single_full_panel
        blk = gt.blocks[1]
        P = length(blk.persons)
        c, g, _, _ = _givens_block_coeffs(blk, u)
        inv_sqrtP = blk.inv_sqrtP
        a = sum(view(u, 1:P)) * inv_sqrtP
        b = u[blk.idx_mu]
        w = g * b + c * a
        shift = (w - a) * inv_sqrtP
        @inbounds for p in 1:P
            q[p] = u[p] + shift
        end
        q[blk.idx_mu] = c * b - g * a
        return q
    end
    for blk in gt.blocks
        c, g, _, _ = _givens_block_coeffs(blk, u)
        inv_sqrtP = blk.inv_sqrtP
        s_u = zero(T)
        @inbounds for p in blk.persons
            s_u += u[p]
        end
        a = s_u * inv_sqrtP
        b = u[blk.idx_mu]
        w = g * b + c * a
        shift = (w - a) * inv_sqrtP
        @inbounds for p in blk.persons
            q[p] = u[p] + shift
        end
        q[blk.idx_mu] = c * b - g * a
    end
    return q
end

function _givens_from_raw(gt::_MRCMLMeanGivensTarget, q::AbstractVector{T}) where {T}
    u = Vector{T}(q)
    for blk in gt.blocks
        c, g, _, _ = _givens_block_coeffs(blk, q)
        inv_sqrtP = blk.inv_sqrtP
        s_q = zero(T)
        @inbounds for p in blk.persons
            s_q += q[p]
        end
        w = s_q * inv_sqrtP
        qmu = q[blk.idx_mu]
        a = c * w - g * qmu
        shift = (a - w) * inv_sqrtP
        @inbounds for p in blk.persons
            u[p] = q[p] + shift
        end
        u[blk.idx_mu] = g * w + c * qmu
    end
    return u
end

_check(gt::_MRCMLMeanGivensTarget, u::AbstractVector) = _check(gt.base, u)
names(gt::_MRCMLMeanGivensTarget, s::Symbol) = names(gt.base, s)
L.dimension(gt::_MRCMLMeanGivensTarget) = gt.dimension
L.capabilities(::Type{_MRCMLMeanGivensTarget}) = L.LogDensityOrder{1}()
function _givens_to_raw_buf!(q::Vector{Float64}, gt::_MRCMLMeanGivensTarget, u::AbstractVector{Float64})
    resize!(q, gt.dimension)
    copyto!(q, u)
    if gt.single_full_panel
        blk = gt.blocks[1]
        P = length(blk.persons)
        c, g, _, _ = _givens_block_coeffs(blk, u)
        inv_sqrtP = blk.inv_sqrtP
        a = sum(view(u, 1:P)) * inv_sqrtP
        b = u[blk.idx_mu]
        w = g * b + c * a
        shift = (w - a) * inv_sqrtP
        @inbounds for p in 1:P
            q[p] = u[p] + shift
        end
        q[blk.idx_mu] = c * b - g * a
        return q
    end
    for blk in gt.blocks
        c, g, _, _ = _givens_block_coeffs(blk, u)
        inv_sqrtP = blk.inv_sqrtP
        s_u = 0.0
        @inbounds for p in blk.persons
            s_u += u[p]
        end
        a = s_u * inv_sqrtP
        b = u[blk.idx_mu]
        w = g * b + c * a
        shift = (w - a) * inv_sqrtP
        @inbounds for p in blk.persons
            q[p] = u[p] + shift
        end
        q[blk.idx_mu] = c * b - g * a
    end
    return q
end

L.logdensity(gt::_MRCMLMeanGivensTarget, u::AbstractVector{<:Real}) =
    L.logdensity(gt.base, _givens_to_raw(gt, u))

function L.logdensity(gt::_MRCMLMeanGivensTarget, u::AbstractVector{Float64})
    _check(gt.base, u; finite = false)
    all(isfinite, u) || return -Inf
    q_buf = get!(() -> Vector{Float64}(undef, gt.dimension), task_local_storage(), :_mrcml_givens_q_buf)::Vector{Float64}
    return L.logdensity(gt.base, _givens_to_raw_buf!(q_buf, gt, u))
end

function L.logdensity_and_gradient(gt::_MRCMLMeanGivensTarget, u::AbstractVector{<:Real})
    _check(gt.base, u; finite = false)
    if !all(isfinite, u)
        Z = promote_type(Float64, eltype(u))
        return (-Z(Inf), fill(Z(NaN), length(u)))
    end
    q = if eltype(u) === Float64
        q_buf = get!(() -> Vector{Float64}(undef, gt.dimension), task_local_storage(), :_mrcml_givens_q_buf)::Vector{Float64}
        resize!(q_buf, gt.dimension)
        copyto!(q_buf, u)
        q_buf
    else
        Float64.(u)
    end
    if gt.single_full_panel
        blk = gt.blocks[1]
        P = length(blk.persons)
        c, g, dc_dq, dg_dq = _givens_block_coeffs(blk, u)
        inv_sqrtP = blk.inv_sqrtP
        a = sum(view(u, 1:P)) * inv_sqrtP
        b = Float64(u[blk.idx_mu])
        w = g * b + c * a
        shift = (w - a) * inv_sqrtP
        @inbounds for p in 1:P
            q[p] = Float64(u[p]) + shift
        end
        q[blk.idx_mu] = c * b - g * a
        val, gq = L.logdensity_and_gradient(gt.base, q)
        !isfinite(val) && return (val, gq)
        dw = sum(view(gq, 1:P)) * inv_sqrtP
        dqmu = gq[blk.idx_mu]
        gu = gq
        da = c * dw - g * dqmu
        gshift = (da - dw) * inv_sqrtP
        @inbounds for p in 1:P
            gu[p] += gshift
        end
        gu[blk.idx_mu] = g * dw + c * dqmu
        if blk.idx_h > 0
            gu[blk.idx_h] += dw * (dg_dq * b + dc_dq * a) + dqmu * (dc_dq * b - dg_dq * a)
        end
        return val, gu
    end
    for blk in gt.blocks
        c, g, _, _ = _givens_block_coeffs(blk, u)
        inv_sqrtP = blk.inv_sqrtP
        s_u = 0.0
        @inbounds for p in blk.persons
            s_u += Float64(u[p])
        end
        a = s_u * inv_sqrtP
        b = Float64(u[blk.idx_mu])
        w = g * b + c * a
        shift = (w - a) * inv_sqrtP
        @inbounds for p in blk.persons
            q[p] = Float64(u[p]) + shift
        end
        q[blk.idx_mu] = c * b - g * a
    end
    val, gq = L.logdensity_and_gradient(gt.base, q)
    !isfinite(val) && return (val, gq)
    gu = gq
    for blk in gt.blocks
        c, g, dc_dq, dg_dq = _givens_block_coeffs(blk, u)
        inv_sqrtP = blk.inv_sqrtP
        s_u = 0.0
        s_gq = 0.0
        @inbounds for p in blk.persons
            s_u += Float64(u[p])
            s_gq += gq[p]
        end
        a = s_u * inv_sqrtP
        b = Float64(u[blk.idx_mu])
        dw = s_gq * inv_sqrtP
        dqmu = gq[blk.idx_mu]
        da = c * dw - g * dqmu
        gshift = (da - dw) * inv_sqrtP
        @inbounds for p in blk.persons
            gu[p] += gshift
        end
        gu[blk.idx_mu] = g * dw + c * dqmu
        if blk.idx_h > 0
            gu[blk.idx_h] += dw * (dg_dq * b + dc_dq * a) + dqmu * (dc_dq * b - dg_dq * a)
        end
    end
    return val, gu
end

function _map_givens_run_to_raw(gt::_MRCMLMeanGivensTarget, run::NamedTuple)
    n_rows, d = size(run.draws)
    q_draws = Matrix{Float64}(undef, n_rows, d)
    for row in 1:n_rows
        q_draws[row, :] = _givens_to_raw(gt, view(run.draws, row, :))
    end
    q_init = _givens_to_raw(gt, run.initial)
    return merge(run, (; initial = q_init, draws = q_draws))
end

function fit(target::AbstractTarget;
        ndraws::Int, warmup::Int, chains::Int, seed,
        target_accept::Union{Nothing,Real} = nothing,
        adapt_delta::Union{Nothing,Real} = nothing,
        max_depth::Union{Nothing,Int} = nothing,
        max_treedepth::Union{Nothing,Int} = nothing,
        step_size = .03, init_jitter = .1, metric = :diagonal,
        mean_orthogonalization::Symbol = :auto,
        progress = false, chain_execution = :auto, max_parallel_chains = chains)
    mean_orthogonalization in (:auto, :none) || throw(ArgumentError(
        "mean_orthogonalization must be :auto or :none; got $(repr(mean_orthogonalization))"))
    target_accept, max_depth = B._resolve_stan_nuts_aliases(;
        target_accept, adapt_delta, default_target_accept = .9,
        max_depth, max_treedepth, default_max_depth = 10,
        caller = "fit", backend = :advancedhmc,
    )

    # Reconstruct from the record so fitting uses the same validation as reopening.
    canonical_target = restore(record(target))
    canonical_target.allocation.identified ||
        throw(ArgumentError(allocation_error(canonical_target)))
    seed isa Integer && !(seed isa Bool) && 0 <= seed <= typemax(Int) ||
        throw(ArgumentError("seed must be a nonnegative integer representable as Int"))
    warn_patterns(canonical_target)

    # The sampler chart may differ; the posterior target and stored chart do not.
    orthogonal_target = mean_orthogonalization === :auto ?
        _maybe_mrcml_givens_target(canonical_target) : nothing
    sampler_target = orthogonal_target === nothing ? canonical_target : orthogonal_target
    run = B._run_generalized_candidate_advancedhmc(
        sampler_target, zeros(canonical_target.dimension);
        ndraws, warmup, chains, seed = Int(seed), target_accept, max_depth,
        step_size, init_jitter, metric, progress, chain_execution, max_parallel_chains,
        ad_backend = :analytic, record_warmup = true,
    )
    if orthogonal_target !== nothing
        run = _map_givens_run_to_raw(orthogonal_target, run)
    end

    # Hash canonical draws and their provenance only after mapping back from HMC.
    target_record = record(canonical_target)
    producer = (;
        julia = string(VERSION), package = string(Base.pkgversion(B)),
        advancedhmc = string(Base.pkgversion(B.AdvancedHMC)),
        diagnostic_tools = string(Base.pkgversion(B.MCMCDiagnosticTools)),
        sampling_chart = orthogonal_target === nothing ? :raw : :givens_mean_orthogonal,
    )
    body = (; schema = FIT_SCHEMA, target = target_record,
        target_identity = B._cache_hash(target_record), run, producer)
    fitted = Fit(merge(body, (; content_hash = B._cache_hash(body))))
    checked(fitted; full = true)
    return fitted
end

function model_draws(target, raw)
    labels = names(target, :model)
    values = Matrix{Float64}(undef, size(raw, 1), length(labels))
    for (row, raw_draw) in enumerate(eachrow(raw))
        effects = coordinates(target, raw_draw)
        values[row, :] = [
            effects.person;
            reduce(vcat, (effects.facets[facet.name] for facet in target.facets); init = Float64[]);
            _step_values(target, effects.steps)
        ]
    end

    # Singleton blocks are structurally fixed, not poorly mixed parameters.
    fixed = Set{String}()
    offset = length(target.people)
    for facet in target.facets
        length(facet.levels) == 1 && push!(fixed, labels[offset + 1])
        offset += length(facet.levels)
    end
    for (group, step_range) in enumerate(target.steps)
        _step_count(target, group) == 1 && push!(fixed, labels[offset + 1])
        offset += _step_count(target, group)
    end
    return (; names = labels, values, fixed)
end

function selected(target, run; scale = :model, parameters = nothing)
    scale in (:raw, :model) || throw(ArgumentError("scale must be :raw or :model"))
    draws = scale === :model ? model_draws(target, run.draws) :
        (; names = names(target, :raw), values = run.draws, fixed = Set{String}())
    chosen = parameters === nothing ? draws.names : collect(parameters)
    !isempty(chosen) && allunique(chosen) && all(name -> name in draws.names, chosen) ||
        throw(ArgumentError("select distinct parameter_names from the requested scale"))
    columns = [only(findall(==(name), draws.names)) for name in chosen]
    return (; names = chosen, values = draws.values[:, columns], fixed = draws.fixed)
end

function diagnostics(f::Fit)
    target = checked(f)
    run = f.record.run
    model = model_draws(target, run.draws)
    diagnose(values, labels; space, fixed = Set{String}()) = B._candidate_mcmc_diagnostic_rows(
        values, labels, run.controls.chains;
        parameter_space = space, structurally_fixed_parameters = fixed,
        split_chains = run.split_chains_requested,
        rhat_threshold = run.checked.rhat_threshold, ess_threshold = run.checked.ess_threshold,
    )
    raw_space = if target isa MRCMLTarget && !isnothing(_person_chart(target))
        :grouped_person_coordinates
    elseif (target isa MRCMLTarget && _has_non_lognormal_scale(target)) ||
           (target isa ExplanatoryTarget && _explanatory_logscale(target))
        :parameter_specific
    else
        :white
    end

    # Parameter diagnostics use stored draws; energy diagnostics retain HMC telemetry.
    return (;
        raw = diagnose(run.draws, names(target, :raw); space = raw_space),
        model = diagnose(model.values, model.names; space = :model, fixed = model.fixed),
        sampler = deepcopy(run.sampler_rows),
        warmup = B._warmup_diagnostic_rows(run.warmup_stats, run.controls, run.backend),
        thresholds = (; run.checked..., minimum_chains = 4), scientific_acceptance = false,
    )
end

function qualify(f::Fit; max_rhat = 1.01, min_ess = 400., min_bfmi = .30)
    thresholds = B._check_diagnostic_thresholds(max_rhat, min_ess)
    min_ess isa Bool && throw(ArgumentError("min_ess must be a finite positive number"))
    min_bfmi isa Real && !(min_bfmi isa Bool) && isfinite(min_bfmi) && min_bfmi > 0 ||
        throw(ArgumentError("min_bfmi must be a finite positive number"))
    return B._qualify_experimental_diagnostics(diagnostics(f), f.record.run, thresholds, Float64(min_bfmi))
end

function interval_bounds(interval)
    interval isa Real && !(interval isa Bool) && isfinite(interval) && 0 < interval < 1 ||
        throw(ArgumentError("interval must be in (0,1)"))
    lower = (1 - Float64(interval)) / 2
    return lower, 1 - lower
end

summary_unit(t,scale)=scale===:model ? :unit_logit : :white_standard_normal
summary_unit(t::MRCMLTarget,scale) = scale === :model ? :unit_logit :
    (isnothing(_person_chart(t)) && !_has_non_lognormal_scale(t)) ? :white_standard_normal : :parameter_specific

function summary(f::Fit; scale = :model, parameters = nothing, interval = .95)
    target = checked(f)
    draws = selected(target, f.record.run; scale, parameters)
    lower, upper = interval_bounds(interval)
    rows = B._posterior_summary_rows(draws.values, draws.names;
        lower, upper, intervals = (interval,),
        reference = 0., rope = nothing, rope_probability_threshold = .95)
    return (;
        scale, unit = summary_unit(target, scale), interval,
        rows = [(; row.parameter, row.mean, row.sd, row.median, row.lower, row.upper,
            structurally_fixed = row.parameter in draws.fixed) for row in rows],
        source_sample_content_hash = f.record.content_hash, scientific_acceptance = false,
    )
end

function mcse(f::Fit; scale = :model, parameters = nothing, probabilities = (.025, .5, .975))
    target = checked(f)
    draws = selected(target, f.record.run; scale, parameters)
    return B._posterior_mcse_rows(draws.values, draws.names, f.record.run.controls.chains;
        probabilities, parameter_space = scale, structurally_fixed_parameters = draws.fixed)
end

function _resolve_facet_level(levs::AbstractVector, val, fname::Symbol)
    idx = findfirst(x -> isequal(x, val), levs)
    idx !== nothing && return levs[idx]
    if val isa Integer && !(val isa Bool) && !any(x -> x isa Integer, levs) && 1 <= Int(val) <= length(levs)
        return levs[Int(val)]
    end
    throw(ArgumentError("unknown level $(repr(val)) for facet $(repr(fname)); available levels: $(levs)"))
end

function contrast(f::Fit; facet::Union{Nothing,Symbol} = nothing, left, right,
        interval::Union{Nothing,Real} = nothing, level::Union{Nothing,Real} = nothing, rope = nothing)
    (interval !== nothing && level !== nothing) &&
        throw(ArgumentError("supply either `interval` or `level` to contrast, not both"))
    iv = interval !== nothing ? interval : level !== nothing ? level : 0.95
    t = checked(f)
    if facet === nothing
        left != right || throw(ArgumentError("choose distinct named parameters"))
        m = selected(t, f.record.run; parameters = [left, right])
        result = B.posterior_contrast(m.values[:, 1], m.values[:, 2];
            chains = f.record.run.controls.chains, interval = iv, rope)
        return (; left, right, unit = contrast_unit(t, left, right), result,
            source_sample_content_hash = f.record.content_hash,
            qualification = qualify(f), conditioning = :joint_posterior_same_draws,
            scientific_acceptance = false)
    end
    fname, levs = if facet in (:person, :entity)
        (:person, t.people)
    else
        bi = findfirst(b -> b.name === facet, t.facets)
        bi === nothing && throw(ArgumentError(
            "unknown facet $(repr(facet)); available: :person, $(Tuple(b.name for b in t.facets))"))
        (t.facets[bi].name, t.facets[bi].levels)
    end
    l_lev = _resolve_facet_level(levs, left, fname)
    r_lev = _resolve_facet_level(levs, right, fname)
    isequal(l_lev, r_lev) && throw(ArgumentError("choose distinct facet levels for contrast"))
    lname = "$(fname)[$(repr(l_lev))]"
    rname = "$(fname)[$(repr(r_lev))]"
    m = selected(t, f.record.run; parameters = [lname, rname])
    res = B.posterior_contrast(m.values[:, 1], m.values[:, 2];
        chains = f.record.run.controls.chains, interval = iv, rope)
    p_row = only(filter(e -> e.event == "above_zero", res.event_rows))
    return (;
        facet = fname,
        left = lname,
        right = rname,
        left_level = l_lev,
        right_level = r_lev,
        level = Float64(iv),
        interval = Float64(iv),
        unit = contrast_unit(t, lname, rname),
        mean = res.mean,
        sd = res.sd,
        median = res.median,
        lower = res.lower,
        upper = res.upper,
        eti = (res.lower, res.upper),
        prob_positive = p_row.probability,
        prob_positive_mcse = p_row.mean_mcse,
        mean_mcse = res.precision.mean_mcse,
        median_mcse = res.precision.quantiles[2].mcse,
        lower_mcse = res.precision.quantiles[1].mcse,
        upper_mcse = res.precision.quantiles[3].mcse,
        mcse = (;
            mean = res.precision.mean_mcse,
            sd = res.precision.sd_mcse,
            lower = res.precision.quantiles[1].mcse,
            median = res.precision.quantiles[2].mcse,
            upper = res.precision.quantiles[3].mcse,
            prob_positive = p_row.mean_mcse,
            status = res.precision.mcse_status,
        ),
        result = res,
        source_sample_content_hash = f.record.content_hash,
        qualification = qualify(f),
        conditioning = :joint_posterior_same_draws,
        scientific_acceptance = false,
    )
end

function prediction_target(t,data)
    data===nothing && return t
    # Reconstruct with the ORIGINAL panel and prior; never recenter a subset.
    n=length(B._column(data,t.columns.person))
    table=Dict{Symbol,Vector}()
    for col in keys(t.table)
        table[col]=col==t.columns.score ? fill(first(t.categories),n) : collect(B._column(data,col))
        B._check_length!(n,table[col],col)
    end
    table[t.columns.score]=_prediction_scores(t,table,n)
    perf,assessment=t.columns.performance,t.columns.assessment
    if perf!==nothing
        links=Dict(zip(t.table[perf],t.table[t.columns.person]))
        all(i->!haskey(links,table[perf][i]) || links[table[perf][i]]==table[t.columns.person][i],1:n) ||
            throw(ArgumentError("prediction changes the person of a stored performance ID"))
        if assessment!==nothing
            links=Dict(zip(t.table[assessment],t.table[perf]))
            all(i->!haskey(links,table[assessment][i]) || links[table[assessment][i]]==table[perf][i],1:n) ||
                throw(ArgumentError("prediction changes the performance of a stored assessment ID"))
        end
    end
    r=record(t)
    model(table;r.columns...,category_levels=r.category_levels,steps=r.steps,
        levels=r.levels,prior_sd=r.prior_sd)
end

response_shift(t,p,values,s,n)=0.

function predict(f::Fit;data=nothing,rows=nothing,interval=.95,metrics=nothing,outcomes=nothing,
        mode::Symbol=:known_owners,new_owners=(),seed=nothing,include_predictive::Bool=false)
    t=checked(f)
    if t isa MixedOutcomeTarget
        metrics===nothing || throw(ArgumentError("metrics selection is for scalar BoundedTarget; use outcomes=(...) on MixedOutcomeTarget"))
        return mixed_predict(t,f;data,rows,outcomes,interval,mode,new_owners,seed,include_predictive)
    end
    outcomes===nothing || throw(ArgumentError("outcomes selection applies to MixedOutcomeTarget fits"))
    !include_predictive || throw(ArgumentError("include_predictive applies to MixedOutcomeTarget fits"))
    mode in (:known_owners,:new_owners) || throw(ArgumentError("prediction mode must be :known_owners or :new_owners"))
    if mode===:new_owners
        t isa ExplanatoryTarget && return explanatory_new_owner_predict(t,f;data,rows,interval,new_owners,seed)
        t isa Union{BoundedTarget,CountTarget} || throw(ArgumentError("mode=:new_owners requires iid population owners (ExplanatoryTarget, BoundedTarget, CountTarget, or MixedOutcomeTarget)"))
        return scalar_new_owner_predict(t,f;data,rows,interval,new_owners,seed,metrics)
    end
    isempty(new_owners) && seed===nothing || throw(ArgumentError("new_owners and seed apply only when mode=:new_owners (or include_predictive=true on MixedOutcomeTarget)"))
    t isa BoundedTarget && return bounded_predict(t,f;data,rows,interval,metrics=metrics===nothing ? BOUNDED_DEFAULT_METRICS : metrics)
    metrics===nothing || throw(ArgumentError("metrics selection is currently available for bounded-score predictions"))
    t isa CountTarget && return count_predict(t,f;data,rows,interval)
    t isa MRCMLTarget && return mrcml_predict(t,f;data,rows,interval)
    p=prediction_target(t,data);m=model_draws(t,f.record.run.draws)
    ix=rows===nothing ? collect(eachindex(p.person)) : collect(rows)
    !isempty(ix) && all(i->i isa Integer && !(i isa Bool) && 1<=i<=length(p.person),ix) ||
        throw(ArgumentError("rows must select existing prediction rows"))
    lo,hi=interval_bounds(interval);K=length(t.categories);S=size(m.values,1)
    means=zeros(length(ix),K);lower=similar(means);upper=similar(means);precision=NamedTuple[]
    offsets=cumsum([length(t.people);[length(b.levels) for b in t.facets]])
    a=zeros(S,K);step_offsets=cumsum([last(offsets);[_step_count(t,g) for g in eachindex(t.steps)]])
    for (j,n) in enumerate(ix)
        for s in 1:S
            eta=m.values[s,p.person[n]]+response_shift(t,p,m.values,s,n)
            for (b,off) in zip(p.facets,offsets)
                eta-=m.values[s,off+b.index[n]]
            end
            g=p.group[n];support=p.supports[g]
            a[s,:].=-Inf;a[s,first(support)]=0.
            for (h,k) in enumerate(support[2:end])
                a[s,k]=a[s,k-1]+eta-m.values[s,step_offsets[g]+h]
            end
            z=B._logsumexp(view(a,s,:));a[s,:].=exp.(view(a,s,:).-z)
        end
        means[j,:]=vec(mean(a;dims=1))
        for k in 1:K;lower[j,k]=quantile(view(a,:,k),lo);upper[j,k]=quantile(view(a,:,k),hi);end
        fixed=Set("category[$(t.categories[k])]" for k in 1:K if !(k in p.supports[p.group[n]]))
        append!(precision,[(;row=Int(n),category=p.categories[k],structural_zero=!(k in p.supports[p.group[n]]),r...) for (k,r) in enumerate(
            B._posterior_mcse_rows(a,["category[$k]" for k in t.categories],f.record.run.controls.chains;
                probabilities=(lo,hi),parameter_space=:category_probability,structurally_fixed_parameters=fixed))])
    end
    cells=[(;position=j,row=Int(n),category=p.categories[k],mean=means[j,k],lower=lower[j,k],upper=upper[j,k],
        structural_zero=!(k in p.supports[p.group[n]])) for (j,n) in enumerate(ix) for k in 1:K]
    d=design(t)
    (;schema=PREDICTION_SCHEMA,kind=:prediction,api=contract(t),cells,rows=Int.(ix),category_levels=copy(p.categories),mean=means,lower,upper,interval,mcse=precision,
      response_patterns=d.response_patterns,warnings=d.warnings,target_identity=f.record.target_identity,
      category_support=[copy(p.categories[p.supports[p.group[n]]]) for n in ix],
      selected_columns=Dict(col=>copy(values[ix]) for (col,values) in p.table if col!=p.columns.score),
      conditioning=prediction_conditioning(t),interval_target=:posterior_category_probability,
      observation_prediction=:posterior_mean_probabilities,qualification=qualify(f),
      source_sample_content_hash=f.record.content_hash,scientific_acceptance=false)
end

# JSON reports retain typed label encodings; they do not reconstruct native fits.
label_encoding(x)=(ismissing(x) || x===nothing) ? (;kind=:missing,value="missing",julia_type=string(typeof(x))) :
    (;kind=x isa Symbol ? :symbol : x isa AbstractString ? :string :
    x isa Integer ? :integer : :float,
    value=string(x),julia_type=string(typeof(x)))
function report(f::Fit;
        scale = :model, parameters = nothing, interval = .95, include_draws::Bool = false)
    target = checked(f)
    lower, upper = interval_bounds(interval)
    design_report = design(target)
    computed = (;
        schema = REPORT_SCHEMA, api = contract(target),
        summary = summary(f; scale, parameters, interval),
        mcse = mcse(f; scale, parameters, probabilities = (lower, .5, upper)),
        qualification = qualify(f),
        controls = deepcopy(f.record.run.controls), producer = f.record.producer,
        source_sample_content_hash = f.record.content_hash,
        target_identity = f.record.target_identity,
        input_labels = Dict(column => label_encoding.(values) for (column, values) in target.table),
        (hasproperty(design_report, :prior_summary) ? (; prior_summary = design_report.prior_summary) : (;))...,
        response_patterns = design_report.response_patterns, warnings = design_report.warnings,
        scientific_acceptance = false,
    )
    return include_draws ?
        merge(computed, (; traces = trace_payload(target, f.record.run; scale, parameters))) : computed
end

function save_result(path, f::Fit)
    checked(f; full = true)
    return B._save_serialized_record(path, f; overwrite = false)
end

function load_result(f::Fit)
    checked(f; full = true)
    return f
end

function _report_population(population)
    return merge(population, (;
        X = collect.(eachrow(population.X)), person_labels = label_encoding.(population.people),
        group_labels = label_encoding.(population.groups),
        reference_label = label_encoding(population.reference),
    ))
end

function save_computed(path, computed)
    check_plot_report(computed)
    (ispath(path) || islink(path)) && throw(ArgumentError("report already exists: $path"))
    if hasproperty(computed, :api) && hasproperty(computed.api, :record) &&
       hasproperty(computed.api.record, :spec_record)
        spec = computed.api.record.spec_record
        if hasproperty(spec, :population)
            spec = merge(spec, (; population = _report_population(spec.population)))
        end
        if hasproperty(spec, :calibration)
            spec = merge(spec, (; calibration = _report_calibration(spec.calibration)))
        elseif hasproperty(get(spec, :fixed_calibration, (;)), :groups)
            spec = merge(spec, (; fixed_calibration = _report_calibration_groups(spec.fixed_calibration)))
        end
        api = merge(computed.api, (; record = merge(computed.api.record, (; spec_record = spec))))
        computed = merge(computed, (; api))
    end

    # Publish a complete JSON file without replacing an existing path, even in a race.
    mkpath(dirname(path))
    mktemp(dirname(path)) do temporary, io
        B.JSON3.write(io, B.Experimental.JointRatings.W.jsonsafe(computed))
        close(io)
        hardlink(temporary, path)
    end
    return computed
end
