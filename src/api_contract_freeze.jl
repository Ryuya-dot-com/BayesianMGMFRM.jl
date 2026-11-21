# FF4a: Complete Layer-1 & Layer-2 `model × operation` Contract Alignment
# Ensures every offered Supported and Experimental model route implements its
# documented Layer-1 and Layer-2 Glass-Box verbs or raises an explicit,
# mathematically informative `ArgumentError` (never an accidental `MethodError`
# on a supported positional signature), while preserving strict keyword rejection.

# ---------------------------------------------------------------------------
# 1. Layer-2 Glass-Box Target & Fitted-Object Completeness
# ---------------------------------------------------------------------------

initial_params(t::AdditiveFacets.AbstractTarget) = zeros(Float64, LogDensityProblems.dimension(t))
initial_params(m::_SA_MOD.StarModel; empirical::Bool = false) =
    empirical ? _SA_MOD._empirical_initial(m) : zeros(Float64, m.dim)
function initial_params(t::_RD_MOD.M.Target)
    q = zeros(Float64, LogDensityProblems.dimension(t))
    if !t.static
        q[(end - t.R + 1):end] .= t.mu_sigma
    end
    return q
end

# Design validation & summaries across targets and fitted objects
validate_design(t::_C3D_MOD.Target) = validate_design(t.independent.base.design)
validate_design(t::_JR_MOD.S.Target) = (; passed = true, identified = true, design_summary(t)...)
validate_design(t::_OA_MOD.Target) = (; passed = true, identified = true, design_summary(t)...)
validate_design(t::_RGE_MOD.Target) = (;
    passed = t.allocation.identified && t.allocation.complete_cells,
    identified = t.allocation.identified,
    _RGE_MOD.design(t)...,
)
validate_design(t::_RII_MOD.Target) = (;
    passed = t.allocation.connected && t.allocation.complete_cells,
    identified = t.allocation.connected,
    _RII_MOD.design(t)...,
)
validate_design(t::_RD_MOD.M.Target) = (;
    passed = true,
    reference = t.time_labels[1],
    _RD_MOD.M.design_review(t; reference = 1)...,
)
validate_design(t::_TIC.Target) = (; passed = true, identified = true, design_summary(t)...)
validate_design(t::_TIC.AssociationTarget) = (; passed = true, identified = true, design_summary(t)...)

_supported_common_design(fit::_SupportedCommonFit) =
    fit isa MFRMFit ? fit.design :
        PredictionObservationAdapter._context(fit, nothing, nothing, Random.default_rng()).design

validate_design(fit::_SupportedCommonFit) = validate_design(_supported_common_design(fit))
validate_design(res::_SA_MOD.StarResult; kwargs...) = validate_design(res.model; kwargs...)
validate_design(f::_TICW.Fit) = validate_design(getdesign(f))
function validate_design(r::NamedTuple)
    _sample_schema_symbol(r) !== nothing ||
        throw(ArgumentError("unsupported NamedTuple record for validate_design"))
    return validate_design(getdesign(r))
end

design_summary(fit::_SupportedCommonFit) = design_summary(_supported_common_design(fit))
design_summary(res::_SA_MOD.StarResult) = design_summary(res.model)
function design_summary(r::NamedTuple)
    _sample_schema_symbol(r) !== nothing ||
        throw(ArgumentError("unsupported NamedTuple record for design_summary"))
    return design_summary(getdesign(r))
end

# Missing parameter_names(; scale = :raw | :model) dispatches
function parameter_names(t::_RGE_MOD.Target; scale::Symbol = :raw)
    scale in (:raw, :model) || throw(ArgumentError("scale must be :raw or :model"))
    scale === :raw && return ["raw[$j]" for j in 1:LogDensityProblems.dimension(t)]
    return _RGE_MOD._draws(t, permutedims(_RGE_MOD.initial(t))).names
end

function parameter_names(t::_RII_MOD.Target; scale::Symbol = :raw)
    scale in (:raw, :model) || throw(ArgumentError("scale must be :raw or :model"))
    scale === :raw && return ["raw[$j]" for j in 1:LogDensityProblems.dimension(t)]
    return _RII_MOD._draws(t, permutedims(_RII_MOD.initial(t))).names
end

function parameter_names(t::_RD_MOD.M.Target; scale::Symbol = :raw)
    scale in (:raw, :model) || throw(ArgumentError("scale must be :raw or :model"))
    T = length(t.time_ticks)
    nt = t.static ? 1 : T
    if scale === :raw
        return vcat(
            ["theta[$p]" for p in 1:t.P],
            ["raw_state[$r,$j]" for j in 1:nt for r in 1:t.R],
            ["free_step[$r,$k]" for k in 1:(t.K - 2) for r in 1:t.R],
            t.static ? String[] : ["log_innovation_sd[$r]" for r in 1:t.R],
        )
    end
    return vcat(
        ["theta[$p]" for p in 1:t.P],
        ["severity[$r,$j]" for j in 1:T for r in 1:t.R],
        ["step[$r,$k]" for k in 1:(t.K - 1) for r in 1:t.R],
        t.static ? String[] : ["innovation_sd[$r]" for r in 1:t.R],
    )
end

# Exact target logprior / loglikelihood / pointwise_loglikelihood / stan_data completions
loglikelihood(t::AdditiveFacets.AbstractTarget, q::AbstractVector{<:Real}) =
    sum(AdditiveFacets.pointwise(t, q))

coordinates(f::AdditiveFacets.Fit, q::AbstractVector{<:Real}) = coordinates(getdesign(f), q)
logprior(f::AdditiveFacets.Fit, q::AbstractVector{<:Real}) = logprior(getdesign(f), q)
loglikelihood(f::AdditiveFacets.Fit, q::AbstractVector{<:Real}) = loglikelihood(getdesign(f), q)
pointwise_loglikelihood(f::AdditiveFacets.Fit, q::AbstractVector{<:Real}) = pointwise_loglikelihood(getdesign(f), q)
logposterior(f::AdditiveFacets.Fit, q::AbstractVector{<:Real}) = logposterior(getdesign(f), q)
logdensity_and_gradient(f::AdditiveFacets.Fit, q::AbstractVector{<:Real}) = logdensity_and_gradient(getdesign(f), q)
stan_data(f::AdditiveFacets.Fit) = stan_data(getdesign(f))

function logprior(t::_JR_MOD.S.Target, q::AbstractVector{<:Real})
    _JR_MOD.S.check_vector(t, q)
    return _JR_MOD.S.logprior(t, q)
end
pointwise_loglikelihood(t::_JR_MOD.S.Target, q::AbstractVector{<:Real}) =
    _JR_MOD.S.pointwise_loglikelihood(t, q)
loglikelihood(t::_JR_MOD.S.Target, q::AbstractVector{<:Real}) =
    sum(_JR_MOD.S.pointwise_loglikelihood(t, q))
stan_data(t::_JR_MOD.S.Target) = _JR_MOD.S.stan_data(t)

function logprior(t::_OA_MOD.Target, x::AbstractVector{<:Real})
    length(x) == LogDensityProblems.dimension(t) && all(isfinite, x) ||
        throw(ArgumentError("invalid OrdinalAssociation parameter vector"))
    h = t.layout
    base = h.original.base
    b = base.blocks
    s = base.prior.task_sd
    v = _OA_MOD.representative(t, x)
    q = v.q
    prior = _OA_MOD.S.logprior(base, view(q, 1:LogDensityProblems.dimension(base)), v.coordinates) +
        _OA_MOD.H.gaussian_logpdf([q[end]], h.original.lambda_sd) +
        _OA_MOD.H.gaussian_logpdf(view(x, 1:last(h.difference))) -
        _OA_MOD.H.gaussian_logpdf(view(q, b.person_white)) -
        _OA_MOD.H.gaussian_logpdf(view(q, b.task), s)
    if t.estimated_scale
        prior += _OA_MOD.H.gaussian_logpdf(x[(end - 1):end] .- t.log_sd_mean, t.log_sd_sd)
    end
    return prior
end

function pointwise_loglikelihood(t::_OA_MOD.Target, x::AbstractVector{<:Real}; unit::Symbol = :event)
    unit === :event || throw(ArgumentError(
        "OrdinalAssociation couples paired criteria within each event via lambda; rating-wise pointwise_loglikelihood is undefined — use unit = :event"))
    length(x) == LogDensityProblems.dimension(t) && all(isfinite, x) ||
        throw(ArgumentError("invalid OrdinalAssociation parameter vector"))
    orig = t.layout.original
    K = orig.base.sizes[5]
    v = _OA_MOD.representative(t, x).coordinates
    Z = promote_type(Float64, eltype(x))
    a = zeros(Z, K)
    bb = zeros(Z, K)
    da = zeros(Z, K)
    db = zeros(Z, K)
    joint = zeros(Z, K, K)
    out = Vector{Z}(undef, length(orig.events))
    for (idx, (n, ya, yb)) in enumerate(orig.events)
        _OA_MOD.C.category_logits!(a, orig, v, n, 1)
        _OA_MOD.C.category_logits!(bb, orig, v, n, 2)
        lp, _ = _OA_MOD.C.pair_terms!(joint, da, db, a, bb, v.lambda, ya, yb)
        out[idx] = lp
    end
    return out
end

loglikelihood(t::_OA_MOD.Target, x::AbstractVector{<:Real}) =
    sum(pointwise_loglikelihood(t, x; unit = :event))

function logprior(t::_RGE_MOD.Target, q::AbstractVector{<:Real})
    _check_source_fixture_raw_vector(t, q)
    return _RGE_MOD._logprior(t, q)
end
function pointwise_loglikelihood(t::_RGE_MOD.Target, q::AbstractVector{<:Real})
    _check_source_fixture_raw_vector(t, q)
    lp = _RGE_MOD.category_logprobs(t, q)
    return [lp[n, t.data.category[n]] for n in 1:t.data.n]
end
loglikelihood(t::_RGE_MOD.Target, q::AbstractVector{<:Real}) = sum(pointwise_loglikelihood(t, q))

function logprior(t::_RII_MOD.Target, q::AbstractVector{<:Real})
    _check_source_fixture_raw_vector(t, q)
    z = (q[end] - t.prior.interaction_logmean) / t.prior.interaction_logsd
    return -(sum(abs2, view(q, 1:(length(q) - 1))) + z^2) / 2 -
        length(q) * log(2pi) / 2 - log(t.prior.interaction_logsd)
end
function pointwise_loglikelihood(t::_RII_MOD.Target, q::AbstractVector{<:Real})
    _check_source_fixture_raw_vector(t, q)
    lp = _RII_MOD.category_logprobs(t, q)
    return [lp[n, t.data.category[n]] for n in 1:t.data.n]
end
loglikelihood(t::_RII_MOD.Target, q::AbstractVector{<:Real}) = sum(pointwise_loglikelihood(t, q))

function pointwise_loglikelihood(t::Union{_CC_MOD.Target, _CC_MOD.MaskedTarget}, q::AbstractVector{<:Real})
    throw(ArgumentError(
        "row-wise pointwise_loglikelihood(target, q) is undefined for CriterionCollapse because persistent rater class z_r couples all criteria rated by rater r; use loglikelihood(target, q) for the exact rater-marginalized log-likelihood or pointwise_loglikelihood(fit; unit = :performance_rater) for held-out profile densities."))
end

coordinates(t::_RD_MOD.M.Target, q::AbstractVector{<:Real}) = _RD_MOD.M.coordinates(t, q)
logprior(t::_RD_MOD.M.Target, q::AbstractVector{<:Real}) = _RD_MOD.M.logprior(t, q)
function pointwise_loglikelihood(t::_RD_MOD.M.Target, q::AbstractVector{<:Real})
    probs = _RD_MOD.M.category_logprobs(t, q)
    return [probs[n, t.score[n] + 1] for n in eachindex(t.score)]
end
loglikelihood(t::_RD_MOD.M.Target, q::AbstractVector{<:Real}) = _RD_MOD.M.loglikelihood(t, q)
logposterior(t::_RD_MOD.M.Target, q::AbstractVector{<:Real}) = LogDensityProblems.logdensity(t, q)
stan_data(t::_RD_MOD.M.Target) = _RD_MOD.M.stan_data(t)

# Informative stan_data refusals for Julia-only specialized experimental targets
for (_NoStanType, _NoStanLabel) in (
    (:(_OA_MOD.Target), "OrdinalAssociation.Target"),
    (:(_RGE_MOD.Target), "RaterGroupEffects.Target"),
    (:(_RII_MOD.Target), "RaterItemInteractions.Target"),
    (:(_CC_MOD.Target), "CriterionCollapse.Target"),
    (:(_CC_MOD.MaskedTarget), "CriterionCollapse.MaskedTarget"),
)
    @eval function stan_data(t::$_NoStanType; kwargs...)
        throw(ArgumentError(string(
            "stan_data is not bundled for ", $_NoStanLabel,
            " because it uses a dedicated Julia analytic/exact-marginal kernel; ",
            "to run a custom Stan program and analyze its draws in BayesianMGMFRM, use `BayesianMGMFRM.StanAdapter.fit_stan` or `StanAdapter.import_csv`.",
        )))
    end
end

# Fitted-object Layer-2 delegations (`StarResult`, `MFRMFit`, `_TICW.Fit`, Experimental `NamedTuple`)
coordinates(res::_SA_MOD.StarResult, q::AbstractVector{<:Real}) = coordinates(res.model, q)
logprior(res::_SA_MOD.StarResult, q::AbstractVector{<:Real}) = logprior(res.model, q)
loglikelihood(res::_SA_MOD.StarResult, q::AbstractVector{<:Real}) = loglikelihood(res.model, q)
pointwise_loglikelihood(res::_SA_MOD.StarResult, q::AbstractVector{<:Real}) = pointwise_loglikelihood(res.model, q)
logposterior(res::_SA_MOD.StarResult, q::AbstractVector{<:Real}) = logposterior(res.model, q)
logdensity_and_gradient(res::_SA_MOD.StarResult, q::AbstractVector{<:Real}) = logdensity_and_gradient(res.model, q)

coordinates(fit::MFRMFit, q::AbstractVector{<:Real}) = coordinates(fit.design, q)
logprior(fit::MFRMFit, q::AbstractVector{<:Real}) = logprior(fit.design, q, fit.prior)
loglikelihood(fit::MFRMFit, q::AbstractVector{<:Real}) = loglikelihood(fit.design, q)
pointwise_loglikelihood(fit::MFRMFit, q::AbstractVector{<:Real}) = pointwise_loglikelihood(fit.design, q)
logposterior(fit::MFRMFit, q::AbstractVector{<:Real}) = logposterior(fit.design, q, fit.prior)
logdensity_and_gradient(fit::MFRMFit, q::AbstractVector{<:Real}) =
    logdensity_and_gradient(MFRMLogDensity(fit.design, fit.prior), q)
stan_data(fit::MFRMFit) = stan_data(MFRMLogDensity(fit.design, fit.prior))

logprior(f::_TICW.Fit, q::AbstractVector{<:Real}) =
    (t = getdesign(f); logprior(t, _TICW.native_point(f.plan, t, q)))
loglikelihood(f::_TICW.Fit, q::AbstractVector{<:Real}) =
    (t = getdesign(f); loglikelihood(t, _TICW.native_point(f.plan, t, q)))
pointwise_loglikelihood(f::_TICW.Fit, q::AbstractVector{<:Real}) =
    (t = getdesign(f); pointwise_loglikelihood(t, _TICW.native_point(f.plan, t, q)))
stan_data(f::_TICW.Fit) = stan_data(getdesign(f))

for _l2_fn in (:coordinates, :logprior, :loglikelihood, :logposterior, :logdensity_and_gradient)
    @eval function $(_l2_fn)(r::NamedTuple, q::AbstractVector{<:Real})
        _sample_schema_symbol(r) !== nothing ||
            throw(ArgumentError(string("unsupported NamedTuple record for ", $(QuoteNode(_l2_fn)))))
        return $(_l2_fn)(getdesign(r), q)
    end
end
function pointwise_loglikelihood(r::NamedTuple, q::AbstractVector{<:Real}; kwargs...)
    _sample_schema_symbol(r) !== nothing ||
        throw(ArgumentError("unsupported NamedTuple record for pointwise_loglikelihood"))
    return pointwise_loglikelihood(getdesign(r), q; kwargs...)
end
function stan_data(r::NamedTuple; kwargs...)
    _sample_schema_symbol(r) !== nothing ||
        throw(ArgumentError("unsupported NamedTuple record for stan_data"))
    return stan_data(getdesign(r); kwargs...)
end

# ---------------------------------------------------------------------------
# 2. Layer-1 `AdditiveFacets.Fit` Completions & Guarded Refusals
# ---------------------------------------------------------------------------

function waic(f::AdditiveFacets.Fit)
    t = AdditiveFacets.checked(f; full = true)
    if t isa Union{AdditiveFacets.Target, AdditiveFacets.MRCMLTarget}
        ll = pointwise_loglikelihood(f).log_density
        return waic(ll)
    elseif t isa AdditiveFacets.ExplanatoryTarget
        throw(ArgumentError(
            "waic is undefined for ExplanatoryTarget because iid performance/owner residuals couple ratings across rows; use criteria(fit; unit = :performance, integrate = :<facet>) for Gauss-Hermite integrated PSIS-LOO."))
    elseif t isa AdditiveFacets.MixedOutcomeTarget
        throw(ArgumentError(
            "waic is not offered for MixedOutcomeTarget; use criteria(fit; unit = :event) for known-owner event PSIS-LOO or criteria(fit; unit = :performance, integrate = :<owner>) for held-performance integrated PSIS-LOO."))
    else
        throw(ArgumentError(
            "waic is not offered for BoundedTarget/CountTarget; use criteria(fit; unit = :rating) for observation-bound PSIS-LOO with joint-draw influence MCSE."))
    end
end

function psis_loo(f::AdditiveFacets.Fit; pareto_k_threshold::Real = 0.7)
    t = AdditiveFacets.checked(f; full = true)
    if t isa Union{AdditiveFacets.Target, AdditiveFacets.MRCMLTarget}
        run = f.record.run
        _check_psis_iterations(run.chain_ids, run.iterations)
        ll = pointwise_loglikelihood(f).log_density
        return psis_loo(ll; chain_ids = run.chain_ids, pareto_k_threshold)
    elseif t isa AdditiveFacets.ExplanatoryTarget
        throw(ArgumentError(
            "rating-wise psis_loo is undefined for ExplanatoryTarget because iid performance/owner residuals couple rows; use criteria(fit; unit = :performance, integrate = :<facet>)."))
    elseif t isa AdditiveFacets.MixedOutcomeTarget
        throw(ArgumentError(
            "specify the prediction unit explicitly for MixedOutcomeTarget via criteria(fit; unit = :event) or criteria(fit; unit = :performance, integrate = :<owner>)."))
    else
        throw(ArgumentError(
            "use criteria(fit; unit = :rating) for BoundedTarget/CountTarget observation-bound PSIS-LOO."))
    end
end

function event_probabilities(f::AdditiveFacets.Fit; kwargs...)
    return predictive_probabilities(f; kwargs...)
end

function facet_summary(f::AdditiveFacets.Fit; facet::Symbol = :person, interval::Real = 0.95)
    t = AdditiveFacets.checked(f; full = true)
    target = facet === :entity ? :person : facet
    pnames = parameter_names(t; scale = :model)
    prefixes = target === :person ? ("person[", "residual[person") :
        ("$(target)[", "residual[$(target)")
    selected = [nm for nm in pnames if any(p -> startswith(nm, p), prefixes)]
    isempty(selected) && throw(ArgumentError(
        "no reconstructed parameters found for facet $(repr(facet)) in AdditiveFacets.Fit; inspect parameter_names(fit; scale = :model)"))
    sub = posterior_summary(f; parameters = selected, scale = :model, interval)
    return (;
        schema = "bayesianmgmfrm.additive_facet_summary.v1",
        facet = target,
        interval = Float64(interval),
        n_levels = length(sub.rows),
        rows = sub.rows,
        source_content_hash = f.record.content_hash,
    )
end

function category_summary(f::AdditiveFacets.Fit; interval::Real = 0.95)
    t = AdditiveFacets.checked(f; full = true)
    if t isa Union{AdditiveFacets.BoundedTarget, AdditiveFacets.CountTarget, AdditiveFacets.MixedOutcomeTarget}
        throw(ArgumentError(
            "category_summary applies to ordinal rating scales; use predict(fit) or predictive_check(fit) for bounded, count, or mixed-outcome AdditiveFacets fits."))
    end
    step_names = [nm for nm in parameter_names(t; scale = :model) if startswith(nm, "step[") || startswith(nm, "steps[")]
    step_rows = isempty(step_names) ? NamedTuple[] : posterior_summary(f; parameters = step_names, scale = :model, interval).rows
    patterns = AdditiveFacets.response_patterns(t)
    return (;
        schema = "bayesianmgmfrm.additive_category_summary.v1",
        interval = Float64(interval),
        response_patterns = patterns,
        steps = step_rows,
        source_content_hash = f.record.content_hash,
    )
end

function _additive_cohort_draws(f::AdditiveFacets.Fit; facet::Symbol = :person, parameters = nothing,
        location::Symbol = :parameter)
    location in (:parameter, :linked) || throw(ArgumentError("location must be :parameter or :linked"))
    t = AdditiveFacets.checked(f; full = true)
    m = AdditiveFacets.model_draws(t, f.record.run.draws)
    chosen = if parameters !== nothing
        [String(p) for p in parameters]
    else
        target = facet === :entity ? :person : facet
        prefix = target === :person ? "person[" : "$(target)["
        cand = [nm for nm in m.names if startswith(nm, prefix) && !(nm in m.fixed)]
        isempty(cand) && throw(ArgumentError(
            "no free finite-cohort parameters matching $(repr(prefix * "...")) in AdditiveFacets.Fit; supply explicit `parameters = [...]`"))
        cand
    end
    !isempty(chosen) && allunique(chosen) || throw(ArgumentError("select distinct cohort parameter names"))
    idx = Int[]
    for nm in chosen
        k = findfirst(==(nm), m.names)
        k === nothing && throw(ArgumentError("unknown AdditiveFacets model parameter $(repr(nm))"))
        nm in m.fixed && throw(ArgumentError("fixed parameter $(repr(nm)) cannot be included in cohort ranking/reliability/classification"))
        push!(idx, k)
    end
    values = m.values[:, idx]
    if location === :linked
        t isa AdditiveFacets.MRCMLTarget && get(t.spec_record, :population_intercept, false) ||
            throw(ArgumentError("linked person locations require a scalar MRCML fit with a population intercept"))
        facet in (:entity, :person) && all(i -> i <= length(t.people), idx) ||
            throw(ArgumentError("linked locations apply to person coordinates only"))
        shift = only(findall(==("population_mean"), m.names))
        values .+= view(m.values, :, shift)
    end
    return (; names = chosen, values, chains = f.record.run.controls.chains)
end

function ranking(f::AdditiveFacets.Fit; facet::Symbol = :person, parameters = nothing,
        direction::Symbol = :higher, top_k = nothing, interval::Real = 0.90,
        max_rank_cells::Int = 20_000_000)
    direction in (:higher, :lower) || throw(ArgumentError("direction must be :higher or :lower"))
    sel = _additive_cohort_draws(f; facet, parameters)
    N = length(sel.names)
    N >= 2 || throw(ArgumentError("ranking requires at least two cohort parameters"))
    S = size(sel.values, 1)
    S * N <= max_rank_cells || throw(ArgumentError("selected draw-by-cohort matrix exceeds max_rank_cells = $max_rank_cells"))
    if top_k !== nothing
        top_k isa Integer && !(top_k isa Bool) && 1 <= top_k <= N ||
            throw(ArgumentError("top_k must be an integer between 1 and $N"))
    end
    _interval_probabilities(Float64(interval))
    rk = _posterior_rank_draws(sel.values, direction, top_k)
    rows = map(1:N) do i
        rs = _posterior_rank_summary(view(rk.ranks, :, i), sel.chains, Float64(interval))
        tk = if top_k === nothing
            nothing
        elseif top_k == N
            (; lower = (; mean = 1.0, mcse = (; value = 0.0, status = :structural_certainty)),
               upper = (; mean = 1.0, mcse = (; value = 0.0, status = :structural_certainty)),
               boundary_tie_probability = (; mean = 0.0, mcse = (; value = 0.0, status = :structural_certainty)))
        else
            c_v = Float64.(view(rk.certain, :, i))
            p_v = Float64.(view(rk.possible, :, i))
            (; lower = _classification_mean(c_v, sel.chains),
               upper = _classification_mean(p_v, sel.chains),
               boundary_tie_probability = _classification_mean(p_v .- c_v, sel.chains))
        end
        (; parameter = sel.names[i], rs..., tie_probability = Statistics.mean(view(rk.tied, :, i)), top_k_probability = tk)
    end
    return (;
        schema = "bayesianmgmfrm.additive_ranking.v1",
        direction,
        top_k,
        interval = Float64(interval),
        n_levels = N,
        n_draws = S,
        rows,
        qualification = qualify(f),
        source_content_hash = f.record.content_hash,
    )
end
posterior_ranking(f::AdditiveFacets.Fit; kwargs...) = ranking(f; kwargs...)

function reliability(f::AdditiveFacets.Fit; facet::Symbol = :person, parameters = nothing,
        target::Symbol = :centered, weights = nothing)
    sel = _additive_cohort_draws(f; facet, parameters)
    N = length(sel.names)
    w = weights === nothing ? ones(Float64, N) : weights
    comp = _posterior_reliability_components(sel.values, w, target)
    mcse_r = _posterior_reliability_mcse(comp, sel.chains)
    return (;
        schema = "bayesianmgmfrm.additive_reliability.v1",
        target,
        parameters = sel.names,
        n_levels = N,
        n_draws = size(sel.values, 1),
        between_variance = comp.between,
        within_variance = comp.within,
        total_variance = comp.total,
        reliability = comp.reliability,
        mcse = mcse_r,
        qualification = qualify(f),
        source_content_hash = f.record.content_hash,
    )
end
posterior_reliability(f::AdditiveFacets.Fit; kwargs...) = reliability(f; kwargs...)

"""
    classification(fit::AdditiveFacets.Fit; cutoff, pass_probability=0.5, location=:parameter, ...)

Compare named model coordinates to a cutoff. For scalar anchored MRCML fits
with a population intercept, `location=:linked` compares each person's deviation
plus the receiving population mean to the cutoff within each joint draw.
The default `:parameter` compares each selected coordinate directly.
"""
function classification(f::AdditiveFacets.Fit; cutoff::Real, pass_probability::Real = 0.5,
        facet::Symbol = :person, parameters = nothing, interval::Real = 0.90,
        location::Symbol = :parameter)
    all(x -> x isa Real && !(x isa Bool) && isfinite(x), (cutoff, pass_probability, interval)) ||
        throw(ArgumentError("cutoff, pass_probability, and interval must be finite real numbers"))
    0.0 < Float64(pass_probability) < 1.0 || throw(ArgumentError("pass_probability must lie strictly in (0, 1)"))
    lo, hi = _interval_probabilities(Float64(interval))
    sel = _additive_cohort_draws(f; facet, parameters, location)
    ev = _classification_events(sel.values, Float64(cutoff), Float64(pass_probability))
    rows = map(eachindex(sel.names)) do i
        vals = view(sel.values, :, i)
        q_ind = Float64.(view(ev.qualifies, :, i))
        q_stat = _classification_mean(q_ind, sel.chains)
        dec = ev.pass[i] ? :pass : :fail
        err_ind = ev.pass[i] ? (1.0 .- q_ind) : q_ind
        err_stat = _classification_mean(err_ind, sel.chains)
        (;
            parameter = sel.names[i],
            mean = Statistics.mean(vals),
            sd = Statistics.std(vals),
            lower = Statistics.quantile(vals, lo),
            upper = Statistics.quantile(vals, hi),
            qualifying_probability = q_stat.mean,
            qualifying_mcse = q_stat.mcse,
            decision = dec,
            error_probability = err_stat.mean,
            error_mcse = err_stat.mcse,
        )
    end
    n_pass = count(ev.pass)
    n_fail = length(ev.pass) - n_pass
    cohort = (;
        n_people = length(sel.names),
        n_pass,
        n_fail,
        expected_false_pass = _classification_mean(Float64.(ev.false_pass), sel.chains; fixed = n_pass == 0),
        expected_false_fail = _classification_mean(Float64.(ev.false_fail), sel.chains; fixed = n_fail == 0),
        expected_total_errors = _classification_mean(Float64.(ev.errors), sel.chains; fixed = isempty(sel.names)),
        any_error_probability = _classification_mean(Float64.(ev.errors .> 0), sel.chains; fixed = isempty(sel.names)),
    )
    return (;
        schema = "bayesianmgmfrm.additive_classification.v1",
        (location === :linked ? (; location, shift_parameter="population_mean") : (;))...,
        cutoff = Float64(cutoff),
        pass_probability = Float64(pass_probability),
        interval = Float64(interval),
        rows,
        cohort,
        qualification = qualify(f),
        source_content_hash = f.record.content_hash,
    )
end
posterior_classification(f::AdditiveFacets.Fit; kwargs...) = classification(f; kwargs...)

# ---------------------------------------------------------------------------
# 3. Layer-1 Experimental `NamedTuple` & Concurrent / Drift Completions & Refusals
# ---------------------------------------------------------------------------

function _experimental_model_draws(r::NamedTuple)
    tag = _sample_schema_symbol(r)
    t = getdesign(r)
    if tag === :correlated_3d
        m = _C3D_MOD.model_draws(t, r.run.draws)
        return (; names = m.names, values = m.values, fixed = Set{String}(), chains = r.run.controls.chains)
    elseif tag === :rater_group_effects
        m = _RGE_MOD._draws(t, r.run.draws)
        return (; names = m.names, values = m.values, fixed = m.fixed, chains = r.run.controls.chains)
    elseif tag === :rater_item_interactions
        m = _RII_MOD._draws(t, r.run.draws)
        return (; names = m.names, values = m.values, fixed = m.fixed, chains = r.run.controls.chains)
    elseif tag === :criterion_collapse
        m = _CC_MOD._draws(t, r.run.draws)
        return (; names = m.names, values = m.values, fixed = Set{String}(), chains = r.run.controls.chains)
    elseif tag === :joint_ratings
        m = _JR_MOD.W.model_draws(t, r.run.draws)
        return (; names = m.names, values = m.values, fixed = Set{String}(), chains = r.run.controls.chains)
    elseif tag === :ordinal_association
        P = t.layout.original.base.sizes[1]
        S = size(r.run.draws, 1)
        th = zeros(Float64, S, 2 * P)
        for s in 1:S
            v = _OA_MOD.representative(t, view(r.run.draws, s, :))
            th[s, :] .= vec(v.theta)
        end
        m = _OA_MOD.model_draws(t, r.run.draws, th)
        return (; names = m.names, values = m.values, fixed = Set{String}(), chains = r.run.controls.chains)
    end
    throw(ArgumentError("reconstructed model draws are not defined for record schema $(repr(tag))"))
end

function facet_summary(r::NamedTuple; facet::Symbol = :person, interval::Real = 0.95)
    tag = _sample_schema_symbol(r)
    tag !== nothing || throw(ArgumentError("unsupported NamedTuple record for facet_summary"))
    lo, hi = _interval_probabilities(Float64(interval))
    m = _experimental_model_draws(r)
    target = facet === :entity ? :person : facet
    prefixes = target === :person ? ("person[", "theta[") :
        target === :rater ? ("rater[", "severity[") :
        target === :item ? ("item[", "task[") : ("$(target)[",)
    idx = [i for i in eachindex(m.names) if any(p -> startswith(m.names[i], p), prefixes)]
    isempty(idx) && throw(ArgumentError(
        "no parameters matching facet $(repr(facet)) in $(tag) record; inspect parameter_names(record; scale = :model)"))
    sub_vals = m.values[:, idx]
    sub_names = m.names[idx]
    srows = _posterior_summary_rows(sub_vals, sub_names;
        lower = lo, upper = hi, intervals = (Float64(interval),),
        reference = 0.0, rope = nothing, rope_probability_threshold = 0.95)
    mrows = _posterior_mcse_rows(sub_vals, sub_names, m.chains;
        probabilities = (lo, 0.5, hi), parameter_space = :model,
        structurally_fixed_parameters = m.fixed)
    rows = [
        (;
            parameter = srows[i].parameter,
            block = target,
            fixed = srows[i].parameter in m.fixed,
            mean = srows[i].mean,
            sd = srows[i].sd,
            median = srows[i].median,
            lower = srows[i].lower,
            upper = srows[i].upper,
            mean_mcse = mrows[i].mean_mcse,
            mcse_status = mrows[i].mcse_status,
        ) for i in eachindex(srows)
    ]
    return (;
        schema = "bayesianmgmfrm.experimental_facet_summary.v1",
        source_family = tag,
        facet = target,
        interval = Float64(interval),
        n_levels = length(rows),
        rows,
        source_content_hash = r.content_hash,
    )
end

function _experimental_cohort_draws(r::NamedTuple; facet::Symbol = :person, parameters = nothing)
    tag = _sample_schema_symbol(r)
    tag !== nothing || throw(ArgumentError("unsupported NamedTuple record"))
    m = _experimental_model_draws(r)
    chosen = if parameters !== nothing
        [String(p) for p in parameters]
    else
        if tag in (:correlated_3d, :joint_ratings, :ordinal_association)
            throw(ArgumentError(
                "$(tag) is multidimensional across criteria/dimensions; pass explicit scalar cohort `parameters = [...]` (inspect parameter_names(record; scale = :model))"))
        end
        target = facet === :entity ? :person : facet
        prefixes = target === :person ? ("person[", "theta[") :
            target === :rater ? ("rater[", "severity[") : ("item[",)
        cand = [nm for nm in m.names if any(p -> startswith(nm, p), prefixes) && !(nm in m.fixed)]
        isempty(cand) && throw(ArgumentError("no free cohort parameters found for facet $(repr(facet)) in $(tag)"))
        cand
    end
    !isempty(chosen) && allunique(chosen) || throw(ArgumentError("select distinct parameter names"))
    idx = Int[]
    for nm in chosen
        k = findfirst(==(nm), m.names)
        k === nothing && throw(ArgumentError("unknown $(tag) model parameter $(repr(nm))"))
        nm in m.fixed && throw(ArgumentError("fixed parameter $(repr(nm)) cannot be included in cohort summaries"))
        push!(idx, k)
    end
    return (; tag, names = chosen, values = m.values[:, idx], chains = m.chains)
end

function ranking(r::NamedTuple; facet::Symbol = :person, parameters = nothing,
        direction::Symbol = :higher, top_k = nothing, interval::Real = 0.90,
        max_rank_cells::Int = 20_000_000)
    direction in (:higher, :lower) || throw(ArgumentError("direction must be :higher or :lower"))
    sel = _experimental_cohort_draws(r; facet, parameters)
    N = length(sel.names)
    N >= 2 || throw(ArgumentError("ranking requires at least two cohort parameters"))
    S = size(sel.values, 1)
    S * N <= max_rank_cells || throw(ArgumentError("selected draw-by-cohort matrix exceeds max_rank_cells = $max_rank_cells"))
    if top_k !== nothing
        top_k isa Integer && !(top_k isa Bool) && 1 <= top_k <= N ||
            throw(ArgumentError("top_k must be an integer between 1 and $N"))
    end
    _interval_probabilities(Float64(interval))
    rk = _posterior_rank_draws(sel.values, direction, top_k)
    rows = map(1:N) do i
        rs = _posterior_rank_summary(view(rk.ranks, :, i), sel.chains, Float64(interval))
        tk = if top_k === nothing
            nothing
        elseif top_k == N
            (; lower = (; mean = 1.0, mcse = (; value = 0.0, status = :structural_certainty)),
               upper = (; mean = 1.0, mcse = (; value = 0.0, status = :structural_certainty)),
               boundary_tie_probability = (; mean = 0.0, mcse = (; value = 0.0, status = :structural_certainty)))
        else
            c_v = Float64.(view(rk.certain, :, i))
            p_v = Float64.(view(rk.possible, :, i))
            (; lower = _classification_mean(c_v, sel.chains),
               upper = _classification_mean(p_v, sel.chains),
               boundary_tie_probability = _classification_mean(p_v .- c_v, sel.chains))
        end
        (; parameter = sel.names[i], rs..., tie_probability = Statistics.mean(view(rk.tied, :, i)), top_k_probability = tk)
    end
    return (;
        schema = "bayesianmgmfrm.experimental_ranking.v1",
        source_family = sel.tag,
        direction,
        top_k,
        interval = Float64(interval),
        n_levels = N,
        n_draws = S,
        rows,
        qualification = qualify(r),
        source_content_hash = r.content_hash,
    )
end

function reliability(r::NamedTuple; facet::Symbol = :person, parameters = nothing,
        target::Symbol = :centered, weights = nothing)
    sel = _experimental_cohort_draws(r; facet, parameters)
    N = length(sel.names)
    w = weights === nothing ? ones(Float64, N) : weights
    comp = _posterior_reliability_components(sel.values, w, target)
    mcse_r = _posterior_reliability_mcse(comp, sel.chains)
    return (;
        schema = "bayesianmgmfrm.experimental_reliability.v1",
        source_family = sel.tag,
        target,
        parameters = sel.names,
        n_levels = N,
        n_draws = size(sel.values, 1),
        between_variance = comp.between,
        within_variance = comp.within,
        total_variance = comp.total,
        reliability = comp.reliability,
        mcse = mcse_r,
        qualification = qualify(r),
        source_content_hash = r.content_hash,
    )
end

function classification(r::NamedTuple; cutoff::Real, pass_probability::Real = 0.5,
        facet::Symbol = :person, parameters = nothing, interval::Real = 0.90)
    all(x -> x isa Real && !(x isa Bool) && isfinite(x), (cutoff, pass_probability, interval)) ||
        throw(ArgumentError("cutoff, pass_probability, and interval must be finite real numbers"))
    0.0 < Float64(pass_probability) < 1.0 || throw(ArgumentError("pass_probability must lie strictly in (0, 1)"))
    lo, hi = _interval_probabilities(Float64(interval))
    sel = _experimental_cohort_draws(r; facet, parameters)
    ev = _classification_events(sel.values, Float64(cutoff), Float64(pass_probability))
    rows = map(eachindex(sel.names)) do i
        vals = view(sel.values, :, i)
        q_ind = Float64.(view(ev.qualifies, :, i))
        q_stat = _classification_mean(q_ind, sel.chains)
        dec = ev.pass[i] ? :pass : :fail
        err_ind = ev.pass[i] ? (1.0 .- q_ind) : q_ind
        err_stat = _classification_mean(err_ind, sel.chains)
        (;
            parameter = sel.names[i],
            mean = Statistics.mean(vals),
            sd = Statistics.std(vals),
            lower = Statistics.quantile(vals, lo),
            upper = Statistics.quantile(vals, hi),
            qualifying_probability = q_stat.mean,
            qualifying_mcse = q_stat.mcse,
            decision = dec,
            error_probability = err_stat.mean,
            error_mcse = err_stat.mcse,
        )
    end
    n_pass = count(ev.pass)
    n_fail = length(ev.pass) - n_pass
    cohort = (;
        n_people = length(sel.names),
        n_pass,
        n_fail,
        expected_false_pass = _classification_mean(Float64.(ev.false_pass), sel.chains; fixed = n_pass == 0),
        expected_false_fail = _classification_mean(Float64.(ev.false_fail), sel.chains; fixed = n_fail == 0),
        expected_total_errors = _classification_mean(Float64.(ev.errors), sel.chains; fixed = isempty(sel.names)),
        any_error_probability = _classification_mean(Float64.(ev.errors .> 0), sel.chains; fixed = isempty(sel.names)),
    )
    return (;
        schema = "bayesianmgmfrm.experimental_classification.v1",
        source_family = sel.tag,
        cutoff = Float64(cutoff),
        pass_probability = Float64(pass_probability),
        interval = Float64(interval),
        rows,
        cohort,
        qualification = qualify(r),
        source_content_hash = r.content_hash,
    )
end

function prior_sensitivity(r::NamedTuple, args...; kwargs...)
    tag = _sample_schema_symbol(r)
    tag !== nothing || throw(ArgumentError("unsupported NamedTuple record for prior_sensitivity"))
    throw(ArgumentError(
        "built-in power-scaling prior_sensitivity is not defined directly on $(tag) records; export with `PortableHandoff.export_handoff(record; include_log_prior = true)` and evaluate custom alternative log-priors via `prior_sensitivity(handoff, alt_log_prior_fn)`."))
end

for _concurrent_unsupported in (:waic, :psis_loo, :criteria, :prior_sensitivity,
                                :facet_summary, :category_summary,
                                :ranking, :posterior_ranking,
                                :reliability, :posterior_reliability,
                                :classification, :posterior_classification)
    @eval function $(_concurrent_unsupported)(f::_TICW.Fit, args...; kwargs...)
        throw(ArgumentError(string(
            $(QuoteNode(_concurrent_unsupported)),
            " is outside the 3-channel 9/9/2 ConcurrentWorkflow.Fit contract (repeated-measures listener/word/recording events with shared random effects); ",
            "use posterior_summary(fit), contrast(fit), event_probabilities(fit; panel = :observed | :eng_reference), or predictive_check(fit; seed = ...).",
        )))
    end
end

# ---------------------------------------------------------------------------
# 4. Machine-Readable Frozen `model × operation` Contract Matrix (`FF4a`)
# ---------------------------------------------------------------------------

module ModelOperationMatrix

const MATRIX_SCHEMA = "bayesianmgmfrm.model_operation_matrix.v1"

const LAYER1_OPERATIONS = (
    :design_summary,
    :validate_design,
    :prior_draw,
    :simulate,
    :prior_predictive_check,
    :fit,
    :diagnostics,
    :qualify,
    :posterior_summary,
    :posterior_mcse,
    :facet_summary,
    :category_summary,
    :contrast,
    :event_probabilities,
    :ranking,
    :reliability,
    :classification,
    :predictive_check,
    :waic,
    :psis_loo,
    :criteria,
    :compare_models,
    :prior_sensitivity,
    :plot,
    :save_fit,
    :load_fit,
    :save_report,
    :load_report,
)

const LAYER2_OPERATIONS = (
    :contract,
    :initial_params,
    :parameter_names,
    :coordinates,
    :logprior,
    :loglikelihood,
    :pointwise_loglikelihood,
    :logposterior,
    :logdensity_and_gradient,
    :stan_data,
    :sampler_controls,
    :portable_handoff,
)

function audit()
    rows = [
        (;
            route = :common_mfrm_1d,
            tier = :supported,
            inference = :bayesian_nuts,
            criterion_unit = :rating,
            psis_estimator = :zhang_stephens_gpd,
            layer1 = :all_supported,
            layer2 = :all_supported,
            notes = "Supported 1D RSM/PCM MFRM (`FacetSpec` -> `MFRMFit`); `:hill_smoothed_loo` remains opt-in.",
        ),
        (;
            route = :experimental_gmfrm_mgmfrm,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :rating,
            psis_estimator = :zhang_stephens_gpd,
            layer1 = :all_supported,
            layer2 = :supported_via_experimental_targets,
            notes = "Scalar GMFRM, fixed-Q MGMFRM, NormalizedMGMFRMPrior, and correlated 2D MGMFRM.",
        ),
        (;
            route = :additive_facets_finite,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :rating,
            psis_estimator = :zhang_stephens_gpd,
            layer1 = :all_supported_except_compare_models_direct,
            layer2 = :all_supported,
            notes = "User-named finite-panel ordinal RSM/PCM (`AdditiveFacets.Target`).",
        ),
        (;
            route = :additive_facets_explanatory,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :performance,
            psis_estimator = :gauss_hermite_profile_psis,
            layer1 = :conditional_unit_performance_waic_refused,
            layer2 = :all_supported,
            notes = "Explanatory ordinal with iid performance/owner residuals (`unit = :performance, integrate = :<facet>`).",
        ),
        (;
            route = :additive_facets_bounded_count,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :rating,
            psis_estimator = :influence_mcse_psis,
            layer1 = :conditional_predict_and_rating_criteria,
            layer2 = :all_supported,
            notes = "ZOIB bounded and Binomial/Beta-Binomial count scores (`predict(fit)`, `criteria(fit; unit = :rating)`).",
        ),
        (;
            route = :additive_facets_mixed_outcomes,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :event_or_performance,
            psis_estimator = :event_or_gauss_hermite_profile_psis,
            layer1 = :conditional_event_or_performance_criteria,
            layer2 = :all_supported,
            notes = "Joint multi-outcome speaking/assessment events (`unit = :event` or `unit = :performance`).",
        ),
        (;
            route = :frequentist_mfrm,
            tier = :supported_frequentist_1d,
            inference = :jmle_and_mmle,
            criterion_unit = :rating_jmle_or_person_mmle,
            psis_estimator = :not_applicable_frequentist,
            layer1 = :frequentist_verbs_supported_bayesian_verbs_refused,
            layer2 = :frequentist_likelihood_and_coordinates_supported,
            notes = "1D RSM/PCM JMLE & Gauss-Hermite MMLE; Bayesian-only verbs throw informative `ArgumentError`.",
        ),
        (;
            route = :star_association,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :event,
            psis_estimator = :zhang_stephens_gpd,
            layer1 = :all_supported,
            layer2 = :all_supported_with_ncp_bijections,
            notes = "Star-structured multi-criterion latent & illusory halo model (`unit = :event`).",
        ),
        (;
            route = :correlated_3d,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :rating,
            psis_estimator = :zhang_stephens_gpd,
            layer1 = :supported_explicit_cohort_parameters,
            layer2 = :all_supported,
            notes = "3D correlated-ability MGMFRM (`Experimental.Correlated3D`).",
        ),
        (;
            route = :joint_ratings,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :coupled_occasion_refused_rowwise,
            psis_estimator = :not_applicable_coupled_occasions,
            layer1 = :summary_contrast_event_probabilities_supported_waic_loo_refused,
            layer2 = :all_supported,
            notes = "Paired criteria with shared response/occasion random effects (`Experimental.JointRatings`).",
        ),
        (;
            route = :ordinal_association,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :event,
            psis_estimator = :not_applicable_shared_occasion,
            layer1 = :summary_contrast_event_probabilities_supported_waic_loo_refused,
            layer2 = :supported_julia_analytic_kernel,
            notes = "Bivariate paired ordinal association with explicit mean/scale layout (`unit = :event` pointwise target).",
        ),
        (;
            route = :rater_group_effects,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :coupled_interaction_cells,
            psis_estimator = :not_applicable_cell_coupling,
            layer1 = :summary_contrast_cohort_ppc_supported_waic_loo_refused,
            layer2 = :supported_julia_analytic_kernel,
            notes = "Observed-group rater severity shifts (`Experimental.RaterGroupEffects`).",
        ),
        (;
            route = :rater_item_interactions,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :coupled_interaction_cells,
            psis_estimator = :not_applicable_cell_coupling,
            layer1 = :summary_contrast_cohort_supported_waic_loo_refused,
            layer2 = :supported_julia_kernel,
            notes = "Partially pooled rater-by-item severity interactions (`Experimental.RaterItemInteractions`).",
        ),
        (;
            route = :criterion_collapse,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :performance_rater,
            psis_estimator = :conditional_profile_psis_and_savage_dickey,
            layer1 = :profile_criteria_compare_ppc_cohort_supported_rowwise_waic_refused,
            layer2 = :exact_rater_marginal_loglikelihood_supported,
            notes = "Discrete rater latent-class criterion collapse (`unit = :performance_rater`).",
        ),
        (;
            route = :rater_drift,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :time_linked_trajectory,
            psis_estimator = :not_applicable_temporal_state_space,
            layer1 = :prepare_fit_trajectory_compare_plot_save_load_supported,
            layer2 = :all_supported,
            notes = "Dynamic RW1 / static rater-severity trajectories (`Experimental.RaterDrift`).",
        ),
        (;
            route = :concurrent_three_indicator,
            tier = :experimental,
            inference = :bayesian_nuts,
            criterion_unit = :event,
            psis_estimator = :not_applicable_three_channel_crossed,
            layer1 = :prepare_fit_summary_contrast_probabilities_ppc_plot_save_load_supported,
            layer2 = :all_supported,
            notes = "Concurrent 9/9/2 multi-channel model (`Experimental.ThreeIndicator`).",
        ),
        (;
            route = :stan_adapter,
            tier = :supported_adapter,
            inference = :cmdstan_or_csv_explicit_roles,
            criterion_unit = :declared_in_roles,
            psis_estimator = :zhang_stephens_gpd,
            layer1 = :all_post_estimation_verbs_supported_generative_verbs_refused,
            layer2 = :draws_contracts_and_declared_log_densities_supported,
            notes = "Explicit-role `.stan` / CmdStan `.csv` post-estimation adapter (`BayesianMGMFRM.StanAdapter`).",
        ),
        (;
            route = :portable_handoff,
            tier = :supported_interchange,
            inference = :portable_joint_draws_v1,
            criterion_unit = :preserved_from_source,
            psis_estimator = :zhang_stephens_gpd,
            layer1 = :all_post_estimation_verbs_supported_with_sha256_receipt,
            layer2 = :bit_exact_ieee754_draws_and_telemetry_preserved,
            notes = "Cross-process/cross-Julia versioned joint-draw handoff (`BayesianMGMFRM.PortableHandoff`).",
        ),
    ]
    return (;
        schema = MATRIX_SCHEMA,
        n_routes = length(rows),
        layer1_operations = LAYER1_OPERATIONS,
        layer2_operations = LAYER2_OPERATIONS,
        rows,
    )
end

end # module ModelOperationMatrix
