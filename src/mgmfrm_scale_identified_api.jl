# Layer-1 Practitioner, Layer-2 Glass-Box & PortableHandoff Dispatches
# for `ScaleIdentifiedMGMFRM.Target` and `ScaleIdentifiedMGMFRM.Fit` (`CR4`)

const _SIM_MOD = ScaleIdentifiedMGMFRM

getdesign(t::_SIM_MOD.Target) = t
getdesign(f::_SIM_MOD.Fit) = _SIM_MOD.checked(f)

initial_params(t::_SIM_MOD.Target) = zeros(Float64, LogDensityProblems.dimension(t))
initial_params(f::_SIM_MOD.Fit) = initial_params(getdesign(f))

design_summary(t::_SIM_MOD.Target) = _SIM_MOD.design_summary(t)
design_summary(f::_SIM_MOD.Fit) = _SIM_MOD.design_summary(getdesign(f))

validate_design(t::_SIM_MOD.Target; kwargs...) = _SIM_MOD.validate_design(t; kwargs...)
validate_design(f::_SIM_MOD.Fit; kwargs...) = _SIM_MOD.validate_design(getdesign(f); kwargs...)

function _canonical_sim_spec(spec::FacetSpec, family_tag::Symbol, step_owner::Symbol,
        D::Int, q_matrix, dimension_labels)
    want_thresh = (family_tag === :mgmfrm && step_owner === :global) ? :rating_scale : :partial_credit
    spec.thresholds === want_thresh && return spec
    return mfrm_spec(
        spec.data;
        family = :mgmfrm,
        dimensions = D,
        thresholds = want_thresh,
        q_matrix,
        dimension_labels,
    )
end

function with_options(t::_SIM_MOD.Target; prior::Union{Nothing, _SIM_MOD.Prior} = nothing, kwargs...)
    if prior !== nothing
        isempty(kwargs) || throw(ArgumentError("supply either `prior` or prior keyword overrides in with_options, not both"))
        eff_pr = _SIM_MOD._with_item_role(prior, t.prior.item_role)
        spec_p = _canonical_sim_spec(t.spec, eff_pr.family_tag, eff_pr.step_owner, t.D, t.q_matrix, t.dimension_labels)
        return _SIM_MOD.model(spec_p; prior = eff_pr)
    end
    tp = t.prior
    kw = (; kwargs...)
    if haskey(kw, :slope) && any(k -> haskey(kw, k), (:item_slopes, :rater_consistency, :item_slope_scope))
        throw(ArgumentError("supply either high-level `slope` or low-level `item_slopes` / `rater_consistency` / `item_slope_scope` in with_options, not both"))
    end
    if haskey(kw, :steps) && haskey(kw, :step_owner)
        throw(ArgumentError("supply either `steps` or `step_owner` in with_options, not both"))
    end
    slope_overrides = if haskey(kw, :slope)
        sl = kw[:slope]
        sl in (:rater, :item, :both) || throw(ArgumentError("`slope` must be `:rater`, `:item`, or `:both`; got $(repr(sl))"))
        kw = Base.structdiff(kw, (; slope = nothing))
        (;
            item_slopes = sl === :rater ? :fixed_one : :estimated_positive,
            rater_consistency = sl === :item ? :fixed_one : :estimated_positive,
            (tp.family_tag === :gmfrm ? (; item_slope_scope = sl === :item ? :entire_linear_predictor : :ability_only) : (;))...,
        )
    else
        (;)
    end
    steps_overrides = if haskey(kw, :steps) || haskey(kw, :step_owner)
        has_st = haskey(kw, :steps)
        st_in = has_st ? kw[:steps] : kw[:step_owner]
        if st_in === :criterion
            tp.item_role === :criterion || throw(ArgumentError("`$(has_st ? :steps : :step_owner) = :criterion` requires a criterion-role specification"))
        end
        st_sym = (st_in === :criterion && tp.item_role === :criterion) ? :item : st_in
        st_sym in (:global, :item, :rater) || throw(ArgumentError("`$(has_st ? :steps : :step_owner)` must be `:global`, `:item`, or `:rater`; got $(repr(st_in))"))
        kw = Base.structdiff(kw, (; steps = nothing, step_owner = nothing))
        (; step_owner = st_sym)
    else
        (;)
    end
    anc = tp.anchor_items isa AbstractVector{<:Pair} ? Dict(tp.anchor_items) : tp.anchor_items
    sd_base = if tp.ability_sd_family === :half_normal
        (; ability_sd_prior = Distributions.truncated(Distributions.Normal(0.0, tp.ability_sd_scale), 0.0, Inf))
    elseif tp.ability_sd_family === :half_t
        (; ability_sd_prior = Distributions.truncated(
            Distributions.LocationScale(0.0, tp.ability_sd_scale, Distributions.TDist(tp.ability_sd_df)), 0.0, Inf))
    else
        (; ability_logsd_mean = tp.ability_logsd_mean, ability_logsd_sd = tp.ability_logsd_sd)
    end
    if haskey(kw, :ability_sd_prior) || haskey(kw, :ability_logsd_prior) ||
       haskey(kw, :ability_logsd_mean) || haskey(kw, :ability_logsd_sd)
        sd_base = (;)
    end
    ll_base = haskey(kw, :log_discrimination_sd) ? (;) : (; log_loading_sd = tp.log_loading_sd)
    corr_base = haskey(kw, :correlation) ? (;) : (; latent_correlation = tp.latent_correlation)
    sk_base = if haskey(kw, :softmin_kappa) || (get(kw, :aggregation, tp.aggregation) === :additive)
        (;)
    else
        (; softmin_kappa = tp.softmin_kappa_mode === :fixed ? tp.softmin_kappa : :estimated)
    end
    cl_base = if haskey(kw, :cross_loading_average)
        (;)
    elseif haskey(kw, :aggregation) && kw[:aggregation] !== tp.aggregation
        (;)
    else
        (; cross_loading_average = tp.cross_loading_average)
    end
    merged = merge(
        (;
            scale_identification = tp.scale_identification,
            location_identification = tp.location_identification,
            logit_scale = tp.logit_scale,
            rater_consistency = tp.rater_consistency,
            anchor_items = anc,
            ability_mean_sd = tp.ability_mean_sd,
            item_sd = tp.item_sd,
            rater_sd = tp.rater_sd,
            log_consistency_sd = tp.log_consistency_sd,
            step_sd = tp.step_sd,
            lkj_eta = tp.lkj_eta,
            item_slopes = tp.item_slopes,
            item_slope_scope = tp.item_slope_scope,
            step_owner = tp.step_owner,
            family_tag = tp.family_tag,
            item_role = tp.item_role,
            rater_slope_scope = tp.rater_slope_scope,
            aggregation = tp.aggregation,
            softmin_log_kappa_mean = tp.softmin_log_kappa_mean,
            softmin_log_kappa_sd = tp.softmin_log_kappa_sd,
        ),
        ll_base,
        sd_base,
        corr_base,
        sk_base,
        cl_base,
        slope_overrides,
        steps_overrides,
        kw,
    )
    if merged.scale_identification === :geometric_mean_one && !haskey(kw, :anchor_items)
        merged = merge(merged, (; anchor_items = nothing))
    end
    pr_out = _SIM_MOD.Prior(; merged...)
    spec_out = _canonical_sim_spec(t.spec, pr_out.family_tag, pr_out.step_owner, t.D, t.q_matrix, t.dimension_labels)
    return _SIM_MOD.model(spec_out; prior = pr_out)
end

prior_draw(t::_SIM_MOD.Target; seed::Integer = 1, kwargs...) =
    _SIM_MOD.prior_draw(t; seed, kwargs...)
simulate(t::_SIM_MOD.Target; seed::Integer = 1, kwargs...) =
    _SIM_MOD.simulate(t; seed, kwargs...)
prior_predictive_check(t::_SIM_MOD.Target; kwargs...) =
    _SIM_MOD.prior_predictive_check(t; kwargs...)

function fit(t::_SIM_MOD.Target; method::Symbol = :nuts, kwargs...)
    method === :nuts || throw(ArgumentError(
        "ScaleIdentifiedMGMFRM / GMFRM supports Bayesian `method = :nuts` only; got `method = $(repr(method))`"))
    return _SIM_MOD.fit(t; kwargs...)
end

contract(t::_SIM_MOD.Target) = _SIM_MOD.contract(t)
contract(f::_SIM_MOD.Fit) = _SIM_MOD.contract(getdesign(f))
constraint_table(t::_SIM_MOD.Target) = _SIM_MOD.constraint_table(t)
constraint_table(f::_SIM_MOD.Fit) = _SIM_MOD.constraint_table(f)

function parameter_names(t::_SIM_MOD.Target; scale::Symbol = :raw)
    scale === :raw && return copy(t.raw_names)
    scale === :model && return copy(t.model_names)
    throw(ArgumentError("scale must be :raw or :model"))
end
parameter_names(f::_SIM_MOD.Fit; scale::Symbol = :raw) =
    parameter_names(getdesign(f); scale)

coordinates(t::_SIM_MOD.Target, q::AbstractVector{<:Real}) = _SIM_MOD.coordinates(t, q)
coordinates(f::_SIM_MOD.Fit, q::AbstractVector{<:Real}) = _SIM_MOD.coordinates(getdesign(f), q)

logprior(t::_SIM_MOD.Target, q::AbstractVector{<:Real}) = _SIM_MOD.logprior(t, q)
logprior(f::_SIM_MOD.Fit, q::AbstractVector{<:Real}) = _SIM_MOD.logprior(getdesign(f), q)

loglikelihood(t::_SIM_MOD.Target, q::AbstractVector{<:Real}) = _SIM_MOD.loglikelihood(t, q)
loglikelihood(f::_SIM_MOD.Fit, q::AbstractVector{<:Real}) = _SIM_MOD.loglikelihood(getdesign(f), q)

pointwise_loglikelihood(t::_SIM_MOD.Target, q::AbstractVector{<:Real}) =
    _SIM_MOD.pointwise_loglikelihood(t, q)
pointwise_loglikelihood(f::_SIM_MOD.Fit, q::AbstractVector{<:Real}) =
    _SIM_MOD.pointwise_loglikelihood(getdesign(f), q)

function pointwise_loglikelihood(f::_SIM_MOD.Fit)
    ll = _SIM_MOD.pointwise_loglikelihood_matrix(f)
    return (;
        log_density = ll,
        unit = :rating,
        observation_binding = f.record.target_identity,
        observation_ids = ["obs_$n" for n in 1:size(ll, 2)],
    )
end
pointwise_loglikelihood_matrix(f::_SIM_MOD.Fit) = _SIM_MOD.pointwise_loglikelihood_matrix(f)

logposterior(t::_SIM_MOD.Target, q::AbstractVector{<:Real}) =
    LogDensityProblems.logdensity(t, q)
logposterior(f::_SIM_MOD.Fit, q::AbstractVector{<:Real}) =
    LogDensityProblems.logdensity(getdesign(f), q)

logdensity_and_gradient(t::_SIM_MOD.Target, q::AbstractVector{<:Real}) =
    LogDensityProblems.logdensity_and_gradient(t, q)
logdensity_and_gradient(f::_SIM_MOD.Fit, q::AbstractVector{<:Real}) =
    LogDensityProblems.logdensity_and_gradient(getdesign(f), q)

stan_data(t::_SIM_MOD.Target) = _SIM_MOD.stan_data(t)
stan_data(f::_SIM_MOD.Fit) = _SIM_MOD.stan_data(getdesign(f))

sampler_controls(f::_SIM_MOD.Fit) = (_SIM_MOD.checked(f); deepcopy(f.record.run.controls))

function diagnostics(f::_SIM_MOD.Fit; kind::Symbol=:mcmc,kwargs...)
    kind === :fair_average && return AdditiveFacets._mrcml_fair_reference(getdesign(f),f;kwargs...)
    _SIM_MOD.diagnostics(f;kind,kwargs...)
end
qualify(f::_SIM_MOD.Fit; kwargs...) = _SIM_MOD.qualify(f; kwargs...)
posterior_summary(f::_SIM_MOD.Fit; kwargs...) = _SIM_MOD.summary(f; kwargs...)
posterior_mcse(f::_SIM_MOD.Fit; kwargs...) = _SIM_MOD.mcse(f; kwargs...)
fit_report(f::_SIM_MOD.Fit; kwargs...) = _SIM_MOD.report(f; kwargs...)

function facet_summary(f::_SIM_MOD.Fit; facet::Symbol = :person, interval::Real = 0.95, centered::Bool = false)
    t = _SIM_MOD.checked(f)
    blk = facet === :entity ? :person : (facet === :correlation ? :latent_correlation : (facet === :criterion ? :item : facet))
    prefix = blk in (:person, :item, :rater, :consistency, :loading, :standardized_loading,
                     :ability_sd, :ability_mean, :latent_correlation, :partial_correlation) ?
        "$(blk)[" :
        throw(ArgumentError("facet must be :person, :item, :criterion, :rater, :consistency, :loading, :standardized_loading, :ability_sd, :ability_mean, :latent_correlation, or :partial_correlation"))
    if centered && blk !== :person
        throw(ArgumentError("`centered = true` applies only to `facet = :person` (subtracting draw-wise `ability_mean[dim=d]` to obtain centered deviations)"))
    end
    pnames = [nm for nm in t.model_names if startswith(nm, prefix)]
    rows_out = if blk === :person && centered
        lo, hi = _SIM_MOD._interval_bounds(interval)
        m = _SIM_MOD.model_draws(t, f.record.run.draws)
        col_map = Dict(nm => j for (j, nm) in enumerate(m.names))
        dev_mat = Matrix{Float64}(undef, size(m.values, 1), length(pnames))
        idx_col = 0
        for p in 1:t.P, d in 1:t.D
            idx_col += 1
            jp = col_map[pnames[idx_col]]
            jm = col_map["ability_mean[dim=$d]"]
            @views dev_mat[:, idx_col] .= m.values[:, jp] .- m.values[:, jm]
        end
        raw_rows = _posterior_summary_rows(
            dev_mat, pnames;
            lower = lo, upper = hi, intervals = (Float64(interval),),
            reference = 0.0, rope = nothing, rope_probability_threshold = 0.95,
        )
        [(; r.parameter, r.mean, r.sd, r.median, r.lower, r.upper, structurally_fixed = false) for r in raw_rows]
    else
        _SIM_MOD.summary(f; scale = :model, parameters = pnames, interval).rows
    end
    scale_meta = blk === :person ? (; person_scale = centered ? :centered_deviation : :absolute) : (;)
    return merge((;
        schema = "bayesianmgmfrm.scale_identified_mgmfrm_facet_summary.v1",
        facet = facet === :criterion ? :criterion : blk,
        interval = Float64(interval),
        n_levels = length(rows_out),
        rows = rows_out,
        source_sample_content_hash = f.record.content_hash,
    ), scale_meta)
end

function category_summary(f::_SIM_MOD.Fit; interval::Real = 0.95)
    t = _SIM_MOD.checked(f)
    step_names = [nm for nm in t.model_names if startswith(nm, "step[")]
    step_rows = _SIM_MOD.summary(f; scale = :model, parameters = step_names, interval).rows
    obs_counts = [count(==(k), t.category) for k in 1:t.K]
    category_rows = [
        (;
            category = t.category_levels[k],
            count = obs_counts[k],
            proportion = obs_counts[k] / t.N,
        ) for k in 1:t.K
    ]
    return (;
        schema = "bayesianmgmfrm.scale_identified_mgmfrm_category_summary.v1",
        interval = Float64(interval),
        categories = category_rows,
        steps = step_rows,
        source_sample_content_hash = f.record.content_hash,
    )
end

contrast(f::_SIM_MOD.Fit; kwargs...) = _SIM_MOD.contrast(f; kwargs...)
contrast(f::_SIM_MOD.Fit, facet::Symbol, left, right; kwargs...) = _SIM_MOD.contrast(f; facet, left, right, kwargs...)
posterior_contrast(f::_SIM_MOD.Fit; kwargs...) = _SIM_MOD.contrast(f; kwargs...)

predict(f::_SIM_MOD.Fit; kwargs...) = _SIM_MOD.predict(f; kwargs...)
event_probabilities(f::_SIM_MOD.Fit; kwargs...) = _SIM_MOD.predict(f; kwargs...)

predictive_check(f::_SIM_MOD.Fit; kwargs...) = _SIM_MOD.posterior_predictive_check(f; kwargs...)
posterior_predictive_check(f::_SIM_MOD.Fit; kwargs...) = _SIM_MOD.posterior_predictive_check(f; kwargs...)

function waic(f::_SIM_MOD.Fit)
    return waic(_SIM_MOD.pointwise_loglikelihood_matrix(f))
end

function psis_loo(f::_SIM_MOD.Fit; pareto_k_threshold::Real = 0.7)
    _SIM_MOD.checked(f)
    run = f.record.run
    _check_psis_iterations(run.chain_ids, run.iterations)
    return psis_loo(_SIM_MOD.pointwise_loglikelihood_matrix(f);
        chain_ids = run.chain_ids, pareto_k_threshold)
end

function criteria(f::_SIM_MOD.Fit;
        criteria::Tuple = (:waic, :psis_loo),
        pareto_k_threshold::Real = 0.7)
    !isempty(criteria) && allunique(criteria) && all(in((:waic, :psis_loo)), criteria) ||
        throw(ArgumentError("choose distinct criteria from :waic, :psis_loo"))
    ll = _SIM_MOD.pointwise_loglikelihood_matrix(f)
    run = f.record.run
    :psis_loo in criteria && _check_psis_iterations(run.chain_ids, run.iterations)
    vals = map(criteria) do c
        c === :waic ? waic(ll) : psis_loo(ll; chain_ids = run.chain_ids, pareto_k_threshold)
    end
    return NamedTuple{criteria}(vals)
end

function _sim_cohort_draws(f::_SIM_MOD.Fit; dimension::Int = 1, parameters = nothing)
    t = _SIM_MOD.checked(f)
    m = _SIM_MOD.model_draws(t, f.record.run.draws)
    chosen = if parameters !== nothing
        [String(p) for p in parameters]
    else
        1 <= dimension <= t.D || throw(ArgumentError("dimension must be in 1:$(t.D)"))
        suffix = ", dim=$dimension]"
        [nm for nm in m.names if startswith(nm, "person[") && endswith(nm, suffix)]
    end
    !isempty(chosen) && allunique(chosen) || throw(ArgumentError("select distinct cohort parameter names"))
    idx = Int[]
    for nm in chosen
        k = findfirst(==(nm), m.names)
        k === nothing && throw(ArgumentError("unknown model parameter $(repr(nm))"))
        nm in m.fixed && throw(ArgumentError("structurally fixed parameter $(repr(nm)) cannot enter cohort summaries"))
        push!(idx, k)
    end
    return (; names = chosen, values = m.values[:, idx], chains = f.record.run.controls.chains)
end

function ranking(f::_SIM_MOD.Fit;
        dimension::Int = 1,
        parameters = nothing,
        direction::Symbol = :higher,
        top_k = nothing,
        interval::Real = 0.90,
        max_rank_cells::Int = 20_000_000)
    direction in (:higher, :lower) || throw(ArgumentError("direction must be :higher or :lower"))
    sel = _sim_cohort_draws(f; dimension, parameters)
    N = length(sel.names)
    N >= 2 || throw(ArgumentError("ranking requires at least two cohort parameters"))
    S = size(sel.values, 1)
    S * N <= max_rank_cells || throw(ArgumentError("selected draw-by-cohort matrix exceeds max_rank_cells"))
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
        schema = "bayesianmgmfrm.scale_identified_mgmfrm_ranking.v1",
        dimension,
        direction,
        top_k,
        interval = Float64(interval),
        n_levels = N,
        n_draws = S,
        rows,
        qualification = qualify(f),
        source_sample_content_hash = f.record.content_hash,
    )
end
posterior_ranking(f::_SIM_MOD.Fit; kwargs...) = ranking(f; kwargs...)

function reliability(f::_SIM_MOD.Fit;
        dimension::Int = 1,
        parameters = nothing,
        target::Symbol = :centered,
        weights = nothing,
        level::Real = 0.95)
    _interval_probabilities(Float64(level))
    sel = _sim_cohort_draws(f; dimension, parameters)
    N = length(sel.names)
    S = size(sel.values, 1)
    w = weights === nothing ? ones(Float64, N) : Float64.(collect(weights))
    comp = _posterior_reliability_components(sel.values, w, target)
    mcse_r = _posterior_reliability_mcse(comp, sel.chains)
    return (;
        schema = "bayesianmgmfrm.scale_identified_mgmfrm_reliability.v1",
        dimension,
        target,
        level = Float64(level),
        n_levels = N,
        reliability = comp.reliability,
        reliability_lower = missing,
        reliability_upper = missing,
        interval_status = :not_defined_for_posterior_functional,
        separation = missing,
        strata = missing,
        scope = :finite_cohort_posterior_functional_not_design_reliability,
        between_variance = comp.between,
        within_variance = comp.within,
        rmse = sqrt(comp.within),
        mcse = mcse_r,
        qualification = qualify(f),
        source_sample_content_hash = f.record.content_hash,
    )
end
posterior_reliability(f::_SIM_MOD.Fit; kwargs...) = reliability(f; kwargs...)

function classification(f::_SIM_MOD.Fit;
        dimension::Int = 1,
        parameters = nothing,
        cutoff::Real,
        pass_probability::Real = 0.5,
        interval::Real = 0.90)
    sel = _sim_cohort_draws(f; dimension, parameters)
    st = PortableHandoff.to_fit(PortableHandoff.export_handoff(f; scale = :model))
    return StanAdapter.classification(st; parameters = sel.names, cutoff, pass_probability, interval)
end
posterior_classification(f::_SIM_MOD.Fit; kwargs...) = classification(f; kwargs...)

save_fit(path::AbstractString, f::_SIM_MOD.Fit) = _SIM_MOD.save_result(path, f)
save_fit_cache(path::AbstractString, f::_SIM_MOD.Fit) = _SIM_MOD.save_result(path, f)

function PortableHandoff.export_handoff(
        f::_SIM_MOD.Fit;
        scale::Symbol = :model,
        include_log_lik::Bool = false,
        include_log_prior::Bool = false,
        ids = nothing)
    scale in (:model, :raw) || throw(ArgumentError("scale must be :model or :raw"))
    t = _SIM_MOD.checked(f; full = true)
    run = f.record.run
    q = qualify(f)
    if scale === :model
        m = _SIM_MOD.model_draws(t, run.draws)
        pnames = m.names
        draws = m.values
        pblocks = map(pnames) do nm
            startswith(nm, "person[") && return :person
            startswith(nm, "ability_") && return :population
            startswith(nm, "loading[") && return :loading
            startswith(nm, "standardized_loading[") && return :standardized_loading
            startswith(nm, "item[") && return :item
            startswith(nm, "rater[") && return :rater
            startswith(nm, "consistency[") && return :consistency
            startswith(nm, "step[") && return :thresholds
            startswith(nm, "latent_correlation[") && return :correlation
            startswith(nm, "partial_correlation[") && return :partial_correlation
            nm == "softmin_kappa" && return :aggregation
            return :parameter
        end
        fixed = NamedTuple[(; block = pblocks[i], name = nm, value = draws[1, i])
            for (i, nm) in enumerate(pnames) if nm in m.fixed]
    else
        pnames = copy(t.raw_names)
        draws = copy(run.draws)
        pblocks = fill(:raw, length(pnames))
        fixed = NamedTuple[]
    end
    tp = t.prior
    src_fam = tp.family_tag === :gmfrm ? "gmfrm" : "scale_identified_mgmfrm"
    ll_p = if include_log_lik
        ll_m = _SIM_MOD.pointwise_loglikelihood_matrix(f)
        (;
            unit = :rating,
            dataset_id = src_fam,
            observation_binding = _cache_hash((;
                unit = :rating,
                n = t.N,
                person = t.person,
                item = t.item,
                rater = t.rater,
                category = t.category,
                category_levels = t.category_levels,
            )),
            observation_ids = ["obs_$n" for n in 1:t.N],
            matrix = ll_m,
        )
    else
        nothing
    end
    lp_v = if include_log_prior
        if scale === :model
            [Float64(_SIM_MOD.constrained_subspace_logprior(t, _SIM_MOD.coordinates(t, view(run.draws, s, :))))
             for s in 1:size(run.draws, 1)]
        else
            [logprior(t, view(run.draws, s, :)) for s in 1:size(run.draws, 1)]
        end
    else
        nothing
    end
    ids_nt = ids !== nothing ? ids : NamedTuple{(:person, tp.item_role, :rater, :dimension)}((
        String.(string.(t.person_levels)),
        String.(string.(t.item_levels)),
        String.(string.(t.rater_levels)),
        String.(t.dimension_labels),
    ))
    ma = hasproperty(t.spec.data.columns, :missing_audit) ? deepcopy(t.spec.data.columns.missing_audit) : nothing
    eff_step_str = (t.step_owner === :item && tp.item_role === :criterion) ? "criterion" : String(t.step_owner)
    ab_sd_info = if tp.ability_sd_family === :half_normal
        (; role = "ability_sd", family = "HalfNormal", label = "HalfNormal($(tp.ability_sd_scale))", scale = tp.ability_sd_scale)
    elseif tp.ability_sd_family === :half_t
        (; role = "ability_sd", family = "HalfStudentT", label = "HalfStudentT($(tp.ability_sd_df), $(tp.ability_sd_scale))",
           df = tp.ability_sd_df, scale = tp.ability_sd_scale)
    else
        (; role = "ability_sd", family = "LogNormal", label = "LogNormal($(tp.ability_logsd_mean), $(tp.ability_logsd_sd))",
           logmean = tp.ability_logsd_mean, logsd = tp.ability_logsd_sd)
    end
    ps_mg = (;
        family = src_fam,
        scale_identification = String(tp.scale_identification),
        location_identification = String(tp.location_identification),
        latent_correlation = String(tp.latent_correlation),
        lkj_eta = tp.latent_correlation === :lkj ? tp.lkj_eta : nothing,
        step_owner = eff_step_str,
        logit_scale = tp.logit_scale,
        item_slopes = String(tp.item_slopes),
        rater_consistency = String(tp.rater_consistency),
        rater_slope_scope = String(tp.rater_slope_scope),
        aggregation = String(tp.aggregation),
        cross_loading_average = tp.cross_loading_average,
        softmin_kappa_mode = String(tp.softmin_kappa_mode),
        ability_sd = ab_sd_info,
        log_loading_sd = tp.log_loading_sd,
        item_sd = tp.item_sd,
        rater_sd = tp.rater_sd,
        log_consistency_sd = tp.log_consistency_sd,
        step_sd = tp.step_sd,
        estimator = "nuts_only",
    )
    ct_base = merge(contract(t), (;
        category_levels = Int.(t.category_levels),
        n_categories = length(t.category_levels),
    ))
    pr_ref = if tp.family_tag === :gmfrm
        merge(ct_base, (;
            step_owner = eff_step_str,
            threshold_owner = eff_step_str,
            identification = tp.scale_identification === :anchor_item ?
                "gmfrm_anchor_item" : "gmfrm_isometric_geometric_mean_one",
        ))
    elseif tp.item_role === :criterion && t.step_owner === :item
        merge(ct_base, (;
            step_owner = "criterion",
            threshold_owner = "criterion",
        ))
    else
        ct_base
    end
    return PortableHandoff._assemble_handoff(;
        source_family = src_fam,
        source_schema = f.record.schema,
        source_content_hash = f.record.content_hash,
        scale,
        chain_ids = copy(run.chain_ids),
        iterations = copy(run.iterations),
        parameter_names = pnames,
        parameter_blocks = pblocks,
        fixed_parameters = fixed,
        draws,
        logdensities = copy(run.logdensities),
        sampler_stats_raw = run.sampler_stats,
        sampler_controls = run.controls,
        prior_and_reference = pr_ref,
        qualification_snapshot = (;
            q.qualified, q.max_rhat, q.min_bulk_ess, q.min_tail_ess, q.n_divergences,
            q.parameter_gate_passed, q.sampler_gate_passed, q.telemetry_complete,
        ),
        log_lik_payload = ll_p,
        log_prior_vec = lp_v,
        ids = ids_nt,
        missing_audit = ma,
        prior_summary = ps_mg,
    )
end

function _canonical_rating_row_binding(f::_SIM_MOD.Fit)
    t = _SIM_MOD.checked(f)
    p_lbl = String[string(t.person_levels[t.person[n]]) for n in 1:t.N]
    i_lbl = String[string(t.item_levels[t.item[n]]) for n in 1:t.N]
    r_lbl = String[string(t.rater_levels[t.rater[n]]) for n in 1:t.N]
    s_val = Int[Int(t.category_levels[t.category[n]]) for n in 1:t.N]
    sup = Vector{Int}[copy(t.category_levels) for _ in 1:t.N]
    return _cache_hash((; unit = :rating, n = t.N, p_lbl, i_lbl, r_lbl, s_val, sup))
end

function _canonical_rating_row_binding(f::AdditiveFacets.Fit)
    t = AdditiveFacets.checked(f; full = true)
    t isa AdditiveFacets.MRCMLTarget || throw(ArgumentError(
        "cross-family PSIS-LOO comparison requires a rating-unit MRCMLTarget fit; got $(typeof(t))"))
    N = length(t.person)
    item_fb = findfirst(b -> b.name === :item, t.facets)
    item_fb === nothing && (item_fb = findfirst(b -> b.name === :criterion, t.facets))
    rater_fb = findfirst(b -> b.name === :rater, t.facets)
    p_lbl = String[string(t.people[t.person[n]]) for n in 1:N]
    i_lbl = item_fb === nothing ? fill("", N) :
        String[string(t.facets[item_fb].levels[t.facets[item_fb].index[n]]) for n in 1:N]
    r_lbl = rater_fb === nothing ? fill("", N) :
        String[string(t.facets[rater_fb].levels[t.facets[rater_fb].index[n]]) for n in 1:N]
    s_val = Int[Int(t.categories[t.category[n]]) for n in 1:N]
    sup = Vector{Int}[Int[t.categories[k] for k in t.supports[t.group[n]]] for n in 1:N]
    return _cache_hash((; unit = :rating, n = N, p_lbl, i_lbl, r_lbl, s_val, sup))
end

function _canonical_rating_row_binding(f::Union{MFRMFit, GMFRMFit, MGMFRMFit})
    d = f.design.spec.data
    p_lbl = String[string(d.person_levels[d.person[n]]) for n in 1:d.n]
    i_lbl = d.columns.item === nothing ? fill("", d.n) : String[string(d.item_levels[d.item[n]]) for n in 1:d.n]
    r_lbl = d.columns.rater === nothing ? fill("", d.n) : String[string(d.rater_levels[d.rater[n]]) for n in 1:d.n]
    s_val = Int[Int(d.score[n]) for n in 1:d.n]
    sup = Vector{Int}[copy(d.category_levels) for _ in 1:d.n]
    return _cache_hash((; unit = :rating, n = d.n, p_lbl, i_lbl, r_lbl, s_val, sup))
end

function _rebind_stan_fit_observation_hash(sf::StanAdapter.Fit, common_binding::String)
    r = sf.record
    meta = r.log_lik_meta
    meta.observation_binding == common_binding && return sf
    new_meta = merge(meta, (; observation_binding = common_binding))
    new_hash = _cache_hash((;
        schema = StanAdapter.FIT_SCHEMA,
        parameter_names = r.parameter_names,
        parameter_blocks = r.parameter_blocks,
        fixed_parameters = r.fixed_parameters,
        chain_ids = r.run.chain_ids,
        iterations = r.run.iterations,
        draws = r.run.draws,
        logdensities = r.run.logdensities,
        log_lik_meta = new_meta,
        log_lik = r.log_lik,
        log_prior = r.log_prior,
        provenance_hashes = (;
            csv_hashes = r.provenance.csv_sha256,
            stan_source_sha256 = r.provenance.stan_source_sha256,
            data_json_sha256 = r.provenance.data_json_sha256,
            executable_sha256 = r.provenance.executable_sha256,
        ),
    ))
    return StanAdapter.Fit(merge(r, (; log_lik_meta = new_meta, content_hash = new_hash)))
end

function _compare_aligned_rating_fits(fits::AbstractVector{<:Pair}; kwargs...)
    length(fits) >= 2 || throw(ArgumentError("supply at least two labeled fitted models to compare_models"))
    b0 = _canonical_rating_row_binding(last(fits[1]))
    st_pairs = Pair{Any, StanAdapter.Fit}[]
    for p in fits
        lbl, fk = first(p), last(p)
        bk = _canonical_rating_row_binding(fk)
        bk == b0 || throw(ArgumentError(
            "model $(repr(lbl)) does not bind the exact same rating observations (person, item/criterion, rater, score, category_levels)"))
        sf = PortableHandoff.to_fit(PortableHandoff.export_handoff(fk; scale = :model, include_log_lik = true))
        push!(st_pairs, lbl => _rebind_stan_fit_observation_hash(sf, b0))
    end
    return StanAdapter.compare_models(st_pairs; kwargs...)
end

function compare_models(fits::AbstractVector{<:Pair{<:Any, _SIM_MOD.Fit}}; kwargs...)
    return _compare_aligned_rating_fits(fits; kwargs...)
end

function compare_models(
        primary::Pair{<:Any, _SIM_MOD.Fit},
        baseline::Pair{<:Any, <:Union{_SIM_MOD.Fit, AdditiveFacets.Fit, MFRMFit, GMFRMFit, MGMFRMFit}},
        rest::Pair...;
        kwargs...)
    return _compare_aligned_rating_fits([primary, baseline, rest...]; kwargs...)
end

function compare_models(
        primary::Pair{<:Any, <:Union{AdditiveFacets.Fit, MFRMFit, GMFRMFit, MGMFRMFit}},
        baseline::Pair{<:Any, _SIM_MOD.Fit},
        rest::Pair...;
        kwargs...)
    return _compare_aligned_rating_fits([primary, baseline, rest...]; kwargs...)
end

const _V02ComparableFit = Union{AdditiveFacets.Fit, _SIM_MOD.Fit, FrequentistMFRM.Fit}

function compare_models(
        f1::_V02ComparableFit,
        f2::_V02ComparableFit,
        rest::_V02ComparableFit...;
        names = nothing,
        kwargs...)
    all_fits = (f1, f2, rest...)
    lbls = _compare_model_names(names, length(all_fits))
    pairs_vec = [Symbol(lbls[i]) => all_fits[i] for i in eachindex(all_fits)]
    return compare_models(pairs_vec...; kwargs...)
end

for _sim_unsupported in (:plausible_values, :anchor_linking_summary)
    @eval function $(_sim_unsupported)(f::_SIM_MOD.Fit, args...; kwargs...)
        throw(ArgumentError(string(
            $(QuoteNode(_sim_unsupported)),
            " is not defined directly on ScaleIdentifiedMGMFRM.Fit; inspect posterior_summary(fit), contrast(fit), criteria(fit), or export via PortableHandoff.export_handoff(fit).",
        )))
    end
end

function _sim_resolve_alt_target(t::_SIM_MOD.Target, alt_spec)
    t_alt = if alt_spec isa _SIM_MOD.Target
        alt_spec
    elseif alt_spec isa _SIM_MOD.Prior
        with_options(t; prior = alt_spec)
    elseif alt_spec isa NamedTuple
        with_options(t; alt_spec...)
    else
        throw(ArgumentError(
            "alternative prior for ScaleIdentifiedMGMFRM.Fit must be a ScaleIdentifiedMGMFRM.Prior, a NamedTuple of prior hyperparameter overrides, a `label => alt` Pair, or a Vector of Pairs"))
    end
    p0, p1 = t.prior, t_alt.prior
    (t.spec.validation.data_signature == t_alt.spec.validation.data_signature &&
     t.q_matrix == t_alt.q_matrix &&
     p0.scale_identification === p1.scale_identification &&
     p0.location_identification === p1.location_identification &&
     p0.logit_scale == p1.logit_scale &&
     t.anchor_item_indices == t_alt.anchor_item_indices &&
     p0.rater_consistency === p1.rater_consistency &&
     p0.item_slopes === p1.item_slopes &&
     p0.item_slope_scope === p1.item_slope_scope &&
     p0.rater_slope_scope === p1.rater_slope_scope &&
     p0.step_owner === p1.step_owner &&
     p0.latent_correlation === p1.latent_correlation &&
     p0.aggregation === p1.aggregation &&
     p0.cross_loading_average == p1.cross_loading_average &&
     p0.softmin_kappa_mode === p1.softmin_kappa_mode &&
     (p0.softmin_kappa_mode !== :fixed || p0.softmin_kappa == p1.softmin_kappa)) ||
        throw(ArgumentError(
            "importance-sampling prior_sensitivity requires an alternative prior on the same likelihood and constrained support manifold (same scale/location identification, logit_scale, slope/step structure, latent_correlation topology, and aggregation mode); refit separate models and use compare_models(...) when changing structural equations"))
    return t_alt
end

function prior_sensitivity(f::_SIM_MOD.Fit; kwargs...)
    throw(ArgumentError(
        "prior_sensitivity on ScaleIdentifiedMGMFRM.Fit requires an alternative prior specification as the second argument (for example, `prior_sensitivity(fit, (log_consistency_sd = 0.5,))` or `prior_sensitivity(fit, [\"wide\" => (item_sd = 2.0,)])`)."))
end

function prior_sensitivity(
        f::_SIM_MOD.Fit,
        alt;
        parameters = nothing,
        interval::Real = 0.95,
        pareto_k_threshold::Real = 0.7)
    t = _SIM_MOD.checked(f; full = true)
    draws = f.record.run.draws
    S = size(draws, 1)
    coords_vec = [_SIM_MOD.coordinates(t, view(draws, s, :)) for s in 1:S]
    sf = PortableHandoff.to_fit(PortableHandoff.export_handoff(f; scale = :model, include_log_prior = true))

    eval_one(lbl::AbstractString, spec_one) = begin
        t_alt = _sim_resolve_alt_target(t, spec_one)
        alt_lp = Float64[Float64(_SIM_MOD.constrained_subspace_logprior(t_alt, coords_vec[s])) for s in 1:S]
        StanAdapter.prior_sensitivity(sf, String(lbl) => alt_lp; parameters, interval, pareto_k_threshold)
    end

    if alt isa Pair
        return eval_one(string(first(alt)), last(alt))
    elseif alt isa AbstractVector
        !isempty(alt) && all(x -> x isa Pair, alt) ||
            throw(ArgumentError("vector `alt` in prior_sensitivity must be a nonempty vector of `label => prior` Pairs"))
        labels = [string(first(p)) for p in alt]
        allunique(labels) || throw(ArgumentError("duplicate variant labels in prior_sensitivity"))
        variants = [eval_one(string(first(p)), last(p)) for p in alt]
        return (;
            schema = "bayesianmgmfrm.scale_identified_mgmfrm_prior_sensitivity_suite.v1",
            interval = Float64(interval),
            pareto_k_threshold = Float64(pareto_k_threshold),
            n_variants = length(variants),
            variants,
            source_sample_content_hash = f.record.content_hash,
        )
    else
        return eval_one("alternative", alt)
    end
end

# ---------------------------------------------------------------------------
# Unified Layer-1 `mfrm_spec` & `fit` Dispatch Helpers (`P2-2`)
# ---------------------------------------------------------------------------

_is_scale_identified_prior(x) = x isa _SIM_MOD.Prior

function _fit_scale_identified_facet_spec(spec::FacetSpec; method::Union{Nothing, Symbol} = nothing, kwargs...)
    (method === nothing || method === :nuts) || throw(ArgumentError(
        "ScaleIdentifiedMGMFRM / GMFRM supports Bayesian `method = :nuts` only; got `method = $(repr(method))`"))
    pr = kwargs[:prior]
    rest = Base.structdiff((; kwargs...), (; prior = nothing))
    if spec.family === :mgmfrm
        return _SIM_MOD.fit(_SIM_MOD.model(spec; prior = pr); rest...)
    elseif spec.family === :gmfrm
        return _SIM_MOD.fit(_SIM_MOD.gmfrm_model(spec.data; prior = pr); rest...)
    end
    throw(ArgumentError("ScaleIdentifiedMGMFRMPrior requires a FacetSpec with family = :mgmfrm or :gmfrm; got $(repr(spec.family))"))
end

function _resolve_generalized_prior_scales(prior_sd, is_mgmfrm::Bool, intercept)
    default_item_sd = is_mgmfrm ? 1.5 : 1.0
    default_step_sd = is_mgmfrm ? 1.5 : 1.0
    mean_sd = intercept isa Distributions.Normal ? Float64(Distributions.std(intercept)) : 2.5
    if prior_sd === nothing
        return (;
            ability_sd_prior = Distributions.truncated(Distributions.Normal(0.0, 1.0), 0.0, Inf),
            item_sd = default_item_sd,
            rater_sd = 1.0,
            step_sd = default_step_sd,
            log_loading_sd = 0.35,
            log_consistency_sd = 0.35,
            ability_mean_sd = mean_sd,
        )
    end
    prior_sd isa NamedTuple || throw(ArgumentError(
        "`prior_sd` for GMFRM / ScaleIdentifiedMGMFRM must be a NamedTuple"))
    ps_facets = get(prior_sd, :facets, (;))
    ps_facets isa NamedTuple || throw(ArgumentError("`prior_sd.facets` must be a NamedTuple"))
    p_person = get(prior_sd, :person, nothing)
    ab_sd = if p_person === nothing
        Distributions.truncated(Distributions.Normal(0.0, 1.0), 0.0, Inf)
    elseif p_person isa Real
        p_person > 0 && isfinite(p_person) || throw(ArgumentError("`prior_sd.person` must be finite and > 0"))
        Distributions.truncated(Distributions.Normal(0.0, Float64(p_person)), 0.0, Inf)
    elseif p_person isa Distributions.Distribution
        p_person
    else
        throw(ArgumentError("`prior_sd.person` must be a positive Real scale or a positive-support Distribution"))
    end
    item_sd = Float64(get(ps_facets, :item, get(ps_facets, :criterion,
        get(prior_sd, :item, get(prior_sd, :criterion, default_item_sd)))))
    rater_sd = Float64(get(ps_facets, :rater, get(prior_sd, :rater, 1.0)))
    step_sd = Float64(get(prior_sd, :step, default_step_sd))
    slope_sd = Float64(get(prior_sd, :slope, 0.35))
    load_sd = Float64(get(prior_sd, :log_loading, slope_sd))
    cons_sd = Float64(get(prior_sd, :log_consistency, slope_sd))
    eff_mean_sd = Float64(get(prior_sd, :intercept, mean_sd))
    return (;
        ability_sd_prior = ab_sd,
        item_sd,
        rater_sd,
        step_sd,
        log_loading_sd = load_sd,
        log_consistency_sd = cons_sd,
        ability_mean_sd = eff_mean_sd,
    )
end

const _GENERALIZED_TABLE_SPEC_KEYS = (
    :person, :score, :facets, :item, :criterion, :rater, :steps, :category_levels, :missing_policy,
    :prior_sd, :slope, :q_matrix, :dimension_labels, :correlation, :latent_correlation,
    :lkj_eta, :scale_identification, :location_identification, :anchor_items,
    :logit_scale, :ability_sd_prior, :rater_consistency, :rater_slope_scope,
    :aggregation, :cross_loading_average, :softmin_kappa, :softmin_log_kappa_mean, :softmin_log_kappa_sd,
)

const _GENERALIZED_PRIOR_OPTIONS = (
    :prior_sd, :intercept, :scale_identification, :location_identification, :anchor_items,
    :logit_scale, :ability_sd_prior, :rater_consistency, :correlation, :latent_correlation, :lkj_eta,
    :rater_slope_scope, :aggregation, :cross_loading_average, :softmin_kappa,
    :softmin_log_kappa_mean, :softmin_log_kappa_sd,
)

function _check_generalized_prior_options(prior::_SIM_MOD.Prior, family, steps, slope, options)
    prior.family_tag === family || throw(ArgumentError("explicit prior must have family_tag = $(repr(family))"))
    steps === nothing || steps === prior.step_owner || throw(ArgumentError(
        "`steps` conflicts with the explicit prior's `step_owner = $(repr(prior.step_owner))`"))
    if slope !== nothing
        item = prior.item_slopes === :estimated_positive
        rater = prior.rater_consistency === :estimated_positive
        matches = (slope === :both && item && rater) || (slope === :item && item && !rater) ||
            (slope === :rater && !item && rater)
        matches || throw(ArgumentError("`slope` conflicts with the explicit prior's slope structure"))
    end
    overrides = [key for key in _GENERALIZED_PRIOR_OPTIONS if get(options, key, nothing) !== nothing]
    isempty(overrides) || throw(ArgumentError("set $(overrides) on the explicit prior instead of supplying separate options"))
end

function _check_gmfrm_options(options)
    correlation = get(options, :correlation, get(options, :latent_correlation, nothing))
    correlation in (nothing, :independent, :identity_fixed) ||
        throw(ArgumentError("latent correlation requires a multidimensional `q_matrix`"))
    agg = get(options, :aggregation, nothing)
    agg in (nothing, :additive) ||
        throw(ArgumentError("`aggregation = $(repr(agg))` requires a multidimensional `q_matrix` with cross-loaded items"))
    overrides = [key for key in (:lkj_eta, :rater_consistency, :cross_loading_average, :softmin_kappa,
                                 :softmin_log_kappa_mean, :softmin_log_kappa_sd)
                 if get(options, key, nothing) !== nothing]
    isempty(overrides) || throw(ArgumentError("unsupported GMFRM options $(overrides)"))
end

function _compile_generalized_table_spec(table; prior = nothing, intercept = nothing, missing_audit = nothing, kwargs...)
    unknown_keys = [k for k in keys(kwargs) if !(k in _GENERALIZED_TABLE_SPEC_KEYS)]
    isempty(unknown_keys) || throw(ArgumentError(
        "unrecognized keyword(s) $(unknown_keys) in generalized `mfrm_spec` (`slope = ...` / `q_matrix = ...`)"))

    prior_sd = get(kwargs, :prior_sd, nothing)
    if prior === :none
        throw(ArgumentError(
            "`prior = :none` frequentist specifications apply to 1D unit-slope MFRM; GMFRM (`slope = ...`) and MGMFRM (`q_matrix = ...`) require Bayesian estimation (`prior = :default` or `prior_sd = ...`)"))
    elseif prior === nothing && prior_sd === nothing
        throw(ArgumentError(_EXPLICIT_PARADIGM_MSG))
    elseif prior === :default && prior_sd !== nothing
        throw(ArgumentError(
            "cannot combine `prior = :default` with `prior_sd`; omit `prior_sd` to use the standard isometric + HalfNormal(1.0) prior or omit `prior` when supplying custom `prior_sd`"))
    elseif !(prior === nothing || prior === :default || prior isa _SIM_MOD.Prior)
        throw(ArgumentError(
            "unsupported `prior = $(repr(prior))` in generalized `mfrm_spec`; supply `prior = :default`, `prior_sd = ...`, or `ScaleIdentifiedMGMFRM.Prior(...)`"))
    end

    q_mat_in = get(kwargs, :q_matrix, nothing)
    slope_kw = get(kwargs, :slope, nothing)
    steps_arg = get(kwargs, :steps, nothing)
    is_mgmfrm = q_mat_in !== nothing
    haskey(kwargs, :correlation) && haskey(kwargs, :latent_correlation) && throw(ArgumentError(
        "supply either `correlation` or `latent_correlation`"))

    person_col = get(kwargs, :person, :person)
    score_col = get(kwargs, :score, :score)
    facets_kw = get(kwargs, :facets, nothing)
    item_col, rater_col, item_role = if facets_kw !== nothing
        facets_kw isa NamedTuple || throw(ArgumentError("`facets` must be a NamedTuple such as `(item = :item, rater = :rater)`"))
        fkeys = keys(facets_kw)
        (:rater in fkeys && length(fkeys) == 2 && (:item in fkeys || :criterion in fkeys)) || throw(ArgumentError(
            "GMFRM / ScaleIdentifiedMGMFRM requires two non-person facets `(item = ..., rater = ...)` or `(criterion = ..., rater = ...)`; got `facets = $(repr(facets_kw))`"))
        has_it = haskey(facets_kw, :item)
        ic = has_it ? facets_kw[:item] : facets_kw[:criterion]
        (ic, facets_kw[:rater], has_it ? :item : :criterion)
    else
        has_crit_only = !haskey(kwargs, :item) && haskey(kwargs, :criterion)
        ic = get(kwargs, :item, get(kwargs, :criterion, :item))
        rc = get(kwargs, :rater, :rater)
        (ic, rc, has_crit_only ? :criterion : :item)
    end
    if steps_arg === :criterion && item_role !== :criterion
        throw(ArgumentError("`steps = :criterion` requires facets declaring `criterion`"))
    end
    norm_steps_arg = (steps_arg === :criterion && item_role === :criterion) ? :item : steps_arg
    options = (; intercept, kwargs...)
    if prior isa _SIM_MOD.Prior
        _check_generalized_prior_options(prior, is_mgmfrm ? :mgmfrm : :gmfrm, norm_steps_arg, slope_kw, options)
    elseif !is_mgmfrm
        _check_gmfrm_options(options)
    end

    cat_levels = get(kwargs, :category_levels, nothing)
    miss_pol = get(kwargs, :missing_policy, :error)
    fd_raw = cat_levels === nothing ?
        FacetData(table; person = person_col, item = item_col, rater = rater_col, score = score_col, missing_policy = miss_pol) :
        FacetData(table; person = person_col, item = item_col, rater = rater_col, score = score_col, category_levels = cat_levels, missing_policy = miss_pol)
    fd = (missing_audit !== nothing && !hasproperty(fd_raw.columns, :missing_audit)) ?
        FacetData(
            (getfield(fd_raw, i) for i in 1:(fieldcount(FacetData) - 1))...,
            merge(fd_raw.columns, (; missing_audit = deepcopy(missing_audit))),
        ) : fd_raw

    steps_kw = something(norm_steps_arg, prior isa _SIM_MOD.Prior ? prior.step_owner : :item)
    steps_kw in (:global, :item, :rater) || throw(ArgumentError(
        "`steps` in generalized `mfrm_spec` must be `:global`, `:item`, or `:rater`; got $(repr(steps_arg))"))

    loc_default = (intercept === :zero || intercept === false) ? :zero_mean_population : :centered_items_free_mean
    loc_id = get(kwargs, :location_identification, loc_default)
    scales = _resolve_generalized_prior_scales(prior_sd, is_mgmfrm, intercept)
    eff_ab_sd = something(get(kwargs, :ability_sd_prior, nothing), scales.ability_sd_prior)
    logit_scale_kw = get(kwargs, :logit_scale, nothing)
    rs_scope_kw = get(kwargs, :rater_slope_scope, :entire_linear_predictor)
    scale_id_kw = get(kwargs, :scale_identification, :geometric_mean_one)
    anchor_items_kw = get(kwargs, :anchor_items, nothing)

    if !is_mgmfrm
        eff_slope = something(slope_kw, :rater)
        if prior isa _SIM_MOD.Prior
            return _SIM_MOD.gmfrm_model(fd; prior, slope = eff_slope, steps = steps_kw, item_role)
        end
        return _SIM_MOD.gmfrm_model(
            fd;
            slope = eff_slope,
            steps = steps_kw,
            logit_scale = something(logit_scale_kw, 1.0),
            scale_identification = scale_id_kw,
            anchor_items = anchor_items_kw,
            location_identification = loc_id,
            rater_slope_scope = rs_scope_kw,
            ability_sd_prior = eff_ab_sd,
            ability_mean_sd = scales.ability_mean_sd,
            log_loading_sd = scales.log_loading_sd,
            log_consistency_sd = scales.log_consistency_sd,
            item_sd = scales.item_sd,
            rater_sd = scales.rater_sd,
            step_sd = scales.step_sd,
            item_role,
        )
    end

    q_res = _resolve_q_matrix_input(q_mat_in, fd.item_levels; item_role)
    q_mat = q_res.matrix
    q_mat isa AbstractMatrix || throw(ArgumentError(
        "`q_matrix` must be an item × dimension matrix or a label-keyed Dict/Vector{Pair}/NamedTuple mapping each $item_role to its loading vector"))
    D_q = size(q_mat, 2)
    dim_labels = something(get(kwargs, :dimension_labels, nothing), q_res.dimension_labels, Some(nothing))
    sp_mg = mfrm_spec(
        fd;
        family = :mgmfrm,
        dimensions = D_q,
        thresholds = (steps_kw === :global ? :rating_scale : :partial_credit),
        q_matrix = q_mat,
        dimension_labels = dim_labels,
    )
    if prior isa _SIM_MOD.Prior
        return _SIM_MOD.model(sp_mg; prior = _SIM_MOD._with_item_role(prior, item_role))
    end

    rater_cons_kw = get(kwargs, :rater_consistency, nothing)
    if slope_kw !== nothing
        slope_kw in (:rater, :item, :both) || throw(ArgumentError("`slope` must be `:rater`, `:item`, or `:both`"))
        if rater_cons_kw !== nothing
            expected_rc = slope_kw === :item ? :fixed_one : :estimated_positive
            rater_cons_kw === expected_rc || throw(ArgumentError(
                "`slope = $(repr(slope_kw))` conflicts with `rater_consistency = $(repr(rater_cons_kw))`"))
        end
    end
    eff_rc = if rater_cons_kw !== nothing
        rater_cons_kw
    elseif slope_kw !== nothing
        slope_kw === :item ? :fixed_one : :estimated_positive
    else
        :estimated_positive
    end
    eff_item_slopes = slope_kw === :rater ? :fixed_one : :estimated_positive
    has_corr_kw = haskey(kwargs, :correlation)
    corr_kw = has_corr_kw ? kwargs[:correlation] : get(kwargs, :latent_correlation, :identity_fixed)
    lkj_eta_kw = get(kwargs, :lkj_eta, 2.0)
    agg_kw = get(kwargs, :aggregation, :additive)
    cl_avg_kw = get(kwargs, :cross_loading_average, nothing)
    sk_kw = get(kwargs, :softmin_kappa, nothing)
    sk_lm_kw = get(kwargs, :softmin_log_kappa_mean, 0.0)
    sk_lsd_kw = get(kwargs, :softmin_log_kappa_sd, 1.0)

    p_mg = _SIM_MOD.Prior(;
        scale_identification = scale_id_kw,
        location_identification = loc_id,
        logit_scale = something(logit_scale_kw, 1.7),
        rater_consistency = eff_rc,
        rater_slope_scope = rs_scope_kw,
        anchor_items = anchor_items_kw,
        ability_sd_prior = eff_ab_sd,
        ability_mean_sd = scales.ability_mean_sd,
        log_loading_sd = scales.log_loading_sd,
        item_sd = scales.item_sd,
        rater_sd = scales.rater_sd,
        log_consistency_sd = scales.log_consistency_sd,
        step_sd = scales.step_sd,
        latent_correlation = (corr_kw === :independent ? :identity_fixed : corr_kw),
        lkj_eta = lkj_eta_kw,
        item_slopes = eff_item_slopes,
        step_owner = steps_kw,
        family_tag = :mgmfrm,
        item_role,
        aggregation = agg_kw,
        cross_loading_average = cl_avg_kw,
        softmin_kappa = sk_kw,
        softmin_log_kappa_mean = sk_lm_kw,
        softmin_log_kappa_sd = sk_lsd_kw,
    )
    return _SIM_MOD.model(sp_mg; prior = p_mg)
end

function _facet_data_to_generalized_target(
        data::FacetData;
        thresholds::Symbol = :partial_credit,
        family::Symbol = :mgmfrm,
        dimensions::Union{Nothing, Int} = nothing,
        discrimination::Symbol = :none,
        q_matrix = nothing,
        dimension_labels = nothing,
        bias = Tuple{Symbol, Symbol}[],
        anchors = NamedTuple[],
        validation_report::Union{Nothing, ValidationReport} = nothing,
        prior = nothing,
        prior_sd = nothing,
        identification::Union{Nothing, Symbol} = nothing,
        intercept = nothing,
        slope::Union{Nothing, Symbol} = nothing,
        steps::Union{Nothing, Symbol} = nothing,
        correlation::Union{Nothing, Symbol} = nothing,
        lkj_eta::Union{Nothing, Real} = nothing,
        scale_identification::Union{Nothing, Symbol} = nothing,
        location_identification::Union{Nothing, Symbol} = nothing,
        anchor_items = nothing,
        logit_scale::Union{Nothing, Real} = nothing,
        ability_sd_prior = nothing,
        rater_consistency = nothing,
        rater_slope_scope::Union{Nothing, Symbol} = nothing,
        aggregation::Union{Nothing, Symbol} = nothing,
        cross_loading_average::Union{Nothing, Bool} = nothing,
        softmin_kappa = nothing,
        softmin_log_kappa_mean::Union{Nothing, Real} = nothing,
        softmin_log_kappa_sd::Union{Nothing, Real} = nothing)
    isempty(bias) && isempty(anchors) || throw(ArgumentError(
        "isometric generalized `mfrm_spec` on FacetData manages anchors and constraints via `scale_identification` / `anchor_items` and does not accept legacy `bias` or `anchors`"))
    eff_prior = prior === nothing ? :default : prior
    eff_prior === :none && throw(ArgumentError(
        "`prior = :none` frequentist specifications apply to 1D unit-slope MFRM; GMFRM and MGMFRM require Bayesian estimation"))
    (eff_prior === :default && prior_sd !== nothing && prior !== nothing) && throw(ArgumentError(
        "cannot combine `prior = :default` with `prior_sd`"))
    (eff_prior === :default || eff_prior isa _SIM_MOD.Prior) || throw(ArgumentError(
        "unsupported `prior = $(repr(eff_prior))` on generalized FacetData specification"))
    options = (; prior_sd, intercept, correlation, lkj_eta, scale_identification, location_identification,
        anchor_items, logit_scale, ability_sd_prior, rater_consistency, rater_slope_scope,
        aggregation, cross_loading_average, softmin_kappa, softmin_log_kappa_mean, softmin_log_kappa_sd)
    if eff_prior isa _SIM_MOD.Prior
        _check_generalized_prior_options(eff_prior, family, steps, slope, options)
    elseif family === :gmfrm
        _check_gmfrm_options(options)
    end
    default_steps = thresholds === :rating_scale ? :global : (family === :gmfrm ? :rater : :item)
    eff_steps = something(steps, eff_prior isa _SIM_MOD.Prior ? eff_prior.step_owner : default_steps)
    loc_default = (intercept === :zero || intercept === false) ? :zero_mean_population : :centered_items_free_mean
    loc_id = something(location_identification, loc_default)
    scales = _resolve_generalized_prior_scales(prior_sd, family === :mgmfrm, intercept)
    ab_sd = something(ability_sd_prior, scales.ability_sd_prior)
    rs_scope = something(rater_slope_scope, :entire_linear_predictor)

    if family === :gmfrm
        eff_dims_gm = something(dimensions, 1)
        eff_dims_gm == 1 && q_matrix === nothing || throw(ArgumentError("GMFRM requires dimensions = 1 without q_matrix"))
        eff_slope = slope !== nothing ? slope : (discrimination === :item ? :item : (discrimination === :both ? :both : :rater))
        if eff_prior isa _SIM_MOD.Prior
            return _SIM_MOD.gmfrm_model(data; prior = eff_prior, slope = eff_slope, steps = eff_steps)
        end
        return _SIM_MOD.gmfrm_model(
            data;
            slope = eff_slope,
            steps = eff_steps,
            logit_scale = something(logit_scale, 1.0),
            scale_identification = something(scale_identification, :geometric_mean_one),
            anchor_items,
            location_identification = loc_id,
            rater_slope_scope = rs_scope,
            ability_sd_prior = ab_sd,
            ability_mean_sd = scales.ability_mean_sd,
            log_loading_sd = scales.log_loading_sd,
            log_consistency_sd = scales.log_consistency_sd,
            item_sd = scales.item_sd,
            rater_sd = scales.rater_sd,
            step_sd = scales.step_sd,
        )
    elseif family === :mgmfrm
        q_res = _resolve_q_matrix_input(q_matrix, data.item_levels)
        q_mat_resolved = q_res.matrix
        eff_dims = something(dimensions, q_mat_resolved isa AbstractMatrix ? size(q_mat_resolved, 2) : 1)
        eff_dlabels = something(dimension_labels, q_res.dimension_labels, Some(nothing))
        sp_mg = mfrm_spec(
            data;
            family = :mgmfrm,
            dimensions = eff_dims,
            thresholds = (eff_steps === :global ? :rating_scale : :partial_credit),
            q_matrix = q_mat_resolved,
            dimension_labels = eff_dlabels,
            validation_report,
        )
        if eff_prior isa _SIM_MOD.Prior
            return _SIM_MOD.model(sp_mg; prior = eff_prior)
        end
        eff_rc = rater_consistency !== nothing ? rater_consistency :
            (slope === :item ? :fixed_one : :estimated_positive)
        eff_item_slopes = slope === :rater ? :fixed_one : :estimated_positive
        p_mg = _SIM_MOD.Prior(;
            scale_identification = something(scale_identification, :geometric_mean_one),
            location_identification = loc_id,
            logit_scale = something(logit_scale, 1.7),
            rater_consistency = eff_rc,
            rater_slope_scope = rs_scope,
            anchor_items,
            ability_sd_prior = ab_sd,
            ability_mean_sd = scales.ability_mean_sd,
            log_loading_sd = scales.log_loading_sd,
            item_sd = scales.item_sd,
            rater_sd = scales.rater_sd,
            log_consistency_sd = scales.log_consistency_sd,
            step_sd = scales.step_sd,
            latent_correlation = correlation in (nothing, :independent) ? :identity_fixed : correlation,
            lkj_eta = something(lkj_eta, 2.0),
            item_slopes = eff_item_slopes,
            step_owner = eff_steps,
            family_tag = :mgmfrm,
            aggregation = something(aggregation, :additive),
            cross_loading_average,
            softmin_kappa,
            softmin_log_kappa_mean = something(softmin_log_kappa_mean, 0.0),
            softmin_log_kappa_sd = something(softmin_log_kappa_sd, 1.0),
        )
        return _SIM_MOD.model(sp_mg; prior = p_mg)
    end
    throw(ArgumentError("unsupported `family = $(repr(family))` in isometric generalized FacetData specification"))
end
