# Layer-1 & Layer-2 Unified Dispatch Bridge for FrequentistMFRM (1D RSM & PCM JMLE/MMLE)

function fit(s::Union{FrequentistMFRM.Spec,AdditiveFacets.MRCMLSpec}; method::Union{Nothing,Symbol} = nothing, kwargs...)
    method === nothing && throw(ArgumentError(
        "this mfrm_spec has no Bayesian prior; pass method = :jmle or method = :mmle for frequentist estimation, or supply prior_sd / prior for Bayesian MCMC"))
    any(k -> k in (:target_accept, :adapt_delta, :max_depth, :max_treedepth), keys(kwargs)) &&
        throw(ArgumentError("NUTS controls (`target_accept`/`adapt_delta`, `max_depth`/`max_treedepth`) do not apply to frequentist `method = $(repr(method))`"))
    return FrequentistMFRM.fit(s; method, kwargs...)
end

getdesign(s::Union{FrequentistMFRM.Spec,AdditiveFacets.MRCMLSpec}) = s
design_summary(s::AdditiveFacets.MRCMLSpec) = (;
    schema = "bayesianmgmfrm.mrcml_frequentist_spec_summary.v1",
    (hasproperty(s.spec_record,:population) ? (;population=deepcopy(s.spec_record.population)) : (;))...,
    (hasproperty(s.spec_record,:calibration) ? (;calibration=deepcopy(s.spec_record.calibration)) : (;))...,
    (hasproperty(s.spec_record,:fixed_calibration) ? (;fixed_calibration=deepcopy(s.spec_record.fixed_calibration)) : (;))...,
    n_observations = length(s.person),
    n_persons = length(s.people),
    n_patterns = s.operator.n_patterns,
    n_free_structural = size(s.operator.A_free, 2),
    n_model_structural = size(s.operator.A_model, 2),
    facets = [(; name = b.name, n_levels = length(b.levels)) for b in s.facets],
    step_owner = s.step_owner_spec,
    location_mode = s.location_mode,
    allocation = deepcopy(s.allocation),
)
design_summary(s::FrequentistMFRM.Spec) = (;
    schema = "bayesianmgmfrm.frequentist_spec_design_summary.v1",
    n_observations = length(s.person),
    n_persons = length(s.people),
    facets = [(; name = b.name, n_levels = length(b.levels)) for b in s.facets],
    step_owner = s.owner,
    supports = [(first(r), last(r)) for r in s.supports],
    allocation = deepcopy(s.allocation),
)
validate_design(s::Union{FrequentistMFRM.Spec,AdditiveFacets.MRCMLSpec}) = deepcopy(s.allocation)
contract(s::AdditiveFacets.MRCMLSpec) = (;
    schema = "bayesianmgmfrm.mrcml_frequentist_spec_contract.v1",
    inference_paradigm = :frequentist_1d_mrcml,
    supported_methods = (hasproperty(s.spec_record,:calibration) || hasproperty(s.spec_record,:population)) ? (:mmle,) : (:jmle, :mmle),
    location_mode = s.location_mode,
    step_owner = s.step_owner_spec,
    facet_names = [b.name for b in s.facets],
    structural_blocks = [bm.name for bm in s.operator.block_meta],
    identified = s.allocation.identified,
    structural_identified = s.allocation.structural_identified,
    conditional_joint_identified = s.allocation.conditional_joint_identified,
)
contract(s::FrequentistMFRM.Spec) = (;
    schema = "bayesianmgmfrm.frequentist_spec_contract.v1",
    inference_paradigm = :frequentist_1d_rsm_pcm,
    supported_methods = (:jmle, :mmle),
    model = s.owner === :global ? :rsm : :pcm,
    step_owner = s.owner,
    facet_names = [b.name for b in s.facets],
    identified = s.allocation.identified,
)
function parameter_names(s::AdditiveFacets.MRCMLSpec; scale::Symbol = :model)
    scale in (:raw,:model) || throw(ArgumentError("scale must be :raw or :model"))
    names = copy(scale === :raw ? s.operator.free_names : s.operator.model_names)
    hasproperty(s.spec_record,:population) || return names
    return vcat(names,FrequentistMFRM._grouped_names(s.spec_record.population,scale))
end
prior_draw(::Union{FrequentistMFRM.Spec,AdditiveFacets.MRCMLSpec}; kwargs...) =
    throw(ArgumentError("prior_draw requires an explicit Bayesian prior; supply prior_sd / prior"))
prior_predictive_check(::Union{FrequentistMFRM.Spec,AdditiveFacets.MRCMLSpec}; kwargs...) =
    throw(ArgumentError("prior_predictive_check requires an explicit Bayesian prior; supply prior_sd / prior"))
stan_data(::Union{FrequentistMFRM.Spec,AdditiveFacets.MRCMLSpec}; kwargs...) =
    throw(ArgumentError("stan_data requires a Bayesian specification (`FacetSpec`, `AdditiveFacets.AbstractTarget`, `StarModel`, etc.); supply prior_sd / prior"))

# Fitted object dispatches (Layer 1 & Layer 2)
getdesign(f::FrequentistMFRM.Fit) = FrequentistMFRM.checked(f).problem
design_summary(f::FrequentistMFRM.Fit) = (;
    schema = "bayesianmgmfrm.frequentist_fit_design_summary.v1",
    FrequentistMFRM.checked(f).summary...,
)
validate_design(f::FrequentistMFRM.Fit) = (;
    passed = true,
    identified = true,
    stationarity_qualified = FrequentistMFRM.checked(f).summary.stationarity_qualified,
    extreme_facet_levels = copy(FrequentistMFRM.checked(f).extreme_facet_levels),
)
contract(f::FrequentistMFRM.Fit) = (;
    schema = "bayesianmgmfrm.frequentist_fit_contract.v1",
    inference_paradigm = :frequentist,
    is_bayesian_posterior = false,
    method = FrequentistMFRM.checked(f).summary.method,
    model = FrequentistMFRM.checked(f).summary.model,
    centering = FrequentistMFRM.checked(f).summary.centering,
    noncenter_facet = FrequentistMFRM.checked(f).summary.noncenter_facet,
    step_owner = FrequentistMFRM.checked(f).summary.step_owner,
    uncertainty_basis = :constrained_observed_information_and_conditional_facets_se,
    (hasproperty(f.record.summary,:calibration) ?
        (;calibration_uncertainty=(method=f.record.summary.calibration.method,
            applies_to=hasproperty(f.record.summary,:population) ? :group_reference_contrasts : :population_mean,
            status=f.record.summary.calibration.status)) : (;))...,
)

function parameter_names(f::FrequentistMFRM.Fit; scale::Symbol = :model)
    r = FrequentistMFRM.checked(f)
    scale === :raw && return copy(r.layout.free_names)
    if scale === :model
        hasproperty(r.summary,:population) || return copy(r.layout.full_names)
        return vcat(r.layout.full_names,FrequentistMFRM._grouped_names(r.summary.population.design,:model))
    end
    throw(ArgumentError("scale must be :raw (free coordinates) or :model (expanded facet/step coordinates)"))
end

function coordinates(f::FrequentistMFRM.Fit, u::AbstractVector{<:Real} = FrequentistMFRM.checked(f).u_free)
    r = FrequentistMFRM.checked(f)
    prob = r.problem
    lay = r.layout
    length(u) == lay.n_free || throw(DimensionMismatch("expected $(lay.n_free) free coordinates; got $(length(u))"))
    full = lay.c_vec .+ lay.J_mat * Float64.(u)
    person = prob.method === :jmle ? full[lay.person_full_range] : nothing
    if hasproperty(r, :mrcml_operator)
        op = r.mrcml_operator
        d_xi = size(op.A_free, 2)
        d_th = prob.method === :jmle ? length(lay.person_free_range) : 0
        eta = Float64.(u[(d_th + 1):(d_th + d_xi)])
        xi_mod = op.xi0_model .+ Vector{Float64}(op.J_model * eta)
        blocks = Dict{Symbol,Any}(bm.name => xi_mod[bm.model_range] for bm in op.block_meta)
        result = (; person, structural_free = eta, structural_model = xi_mod, blocks)
        hasproperty(r.summary,:population) || return result
        design = r.summary.population.design
        br = d_xi .+ (1:size(design.X,2))
        return merge(result,(;population=(coefficients=Float64.(u[br]),
                          group_sd=exp.(u[last(br)+1:end]))))
    end
    facets = NamedTuple{Tuple(b.name for b in prob.facets)}(
        Tuple(full[lay.facet_full_ranges[i]] for i in eachindex(prob.facets))
    )
    steps = [full[sr] for sr in lay.step_full_ranges]
    return (; person, facets, steps)
end

loglikelihood(f::FrequentistMFRM.Fit) = FrequentistMFRM.checked(f).summary.loglikelihood
function _mrcml_person_grid(r)
    prob, op = r.problem, r.mrcml_operator
    q = FrequentistMFRM.build_quadrature(r.summary.quadrature, r.summary.quad_points;
        sd=1.0, theta_lim=Float64(r.summary.theta_lim))
    offsets = op.c_pat + op.A_free * r.eta_free
    people = eachindex(prob.person_levels)
    nodes = Matrix{Float64}(undef, length(people), length(q.weights))
    logmass = similar(nodes)
    for p in people
        mu, sd = FrequentistMFRM._mrcml_person_law(r.summary, p)
        nodes[p,:] .= mu .+ sd .* q.std_nodes
        logmass[p,:] .= log.(q.weights)
    end
    for n in 1:prob.n_obs
        p = prob.person_idx[n]
        cells = op.pattern_ranges[op.pattern_of_row[n]]
        observed = cells[prob.score_k[n]+1]
        for h in eachindex(q.weights)
            theta = nodes[p,h]
            logits(k) = op.B_pat[k] * theta + offsets[k]
            peak = maximum(logits, cells)
            logp = (logits(observed) - peak) - log(sum(k -> exp(logits(k) - peak), cells))
            logmass[p,h] += prob.weights[n] * logp
        end
    end
    peak = maximum(logmass; dims=2)
    mass = exp.(logmass .- peak)
    total = sum(mass; dims=2)
    return (; nodes, probabilities=mass ./ total, logevidence=vec(peak .+ log.(total)))
end

function pointwise_loglikelihood(f::FrequentistMFRM.Fit)
    r = FrequentistMFRM.checked(f)
    prob = r.problem
    lay = r.layout
    if hasproperty(r, :mrcml_operator)
        op = r.mrcml_operator
        if prob.method === :jmle
            v_pat = op.c_pat + op.A_free * r.eta_free
            out = zeros(Float64, prob.n_obs)
            for idx in 1:prob.n_obs
                th = Float64(r.person_scores[prob.person_idx[idx]].limit_estimate)
                if !isfinite(th)
                    out[idx] = 0.0
                else
                    prng = op.pattern_ranges[op.pattern_of_row[idx]]
                    sup = prob.supports[prob.step_group[idx]]
                    M_g = length(sup)
                    lvec = [op.B_pat[prng[lk]] * th + v_pat[prng[lk]] for lk in 1:M_g]
                    mmax = maximum(lvec)
                    lse = mmax + log(sum(exp.(lvec .- mmax)))
                    yk_loc = prob.score_k[idx] + 1
                    out[idx] = prob.weights[idx] * (lvec[yk_loc] - lse)
                end
            end
            return out
        else
            return _mrcml_person_grid(r).logevidence
        end
    end
    full = r.full_parameters
    K_max = maximum(length, prob.supports)
    pbuf = zeros(Float64, K_max)
    if prob.method === :jmle
        out = zeros(Float64, prob.n_obs)
        for idx in 1:prob.n_obs
            p = prob.person_idx[idx]
            th = Float64(r.person_scores[p].limit_estimate)
            if !isfinite(th)
                out[idx] = 0.0
            else
                eta = th
                for (fi, fd) in enumerate(prob.facets)
                    eta += fd.sign * full[lay.facet_full_ranges[fi][fd.index[idx]]]
                end
                g = prob.step_group[idx]
                srng = lay.step_full_ranges[g]
                pv = view(pbuf, 1:length(prob.supports[g]))
                ld = FrequentistMFRM._row_probs!(pv, eta, view(full, srng))
                yk = prob.score_k[idx]
                cum_obs = yk == 0 ? 0.0 : sum(view(full, srng)[1:yk])
                out[idx] = prob.weights[idx] * ((yk * eta - cum_obs) - ld)
            end
        end
        return out
    else
        # Person-wise marginal quadrature log-likelihoods (sum equals marginal loglikelihood)
        quad = FrequentistMFRM.build_quadrature(r.summary.quadrature, r.summary.quad_points;
            sd = r.summary.population_sd, theta_lim = Float64(r.summary.theta_lim))
        mu_hat = Float64(r.summary.population_mean)
        log_w = [w > 0.0 ? log(w) : -Inf for w in quad.weights]
        P = length(prob.person_levels)
        Q = length(quad.nodes)
        ll_pq = zeros(Float64, P, Q)
        for q in 1:Q
            log_w[q] == -Inf && continue
            th_q = mu_hat + quad.nodes[q]
            for idx in 1:prob.n_obs
                eta = th_q
                for (fi, fd) in enumerate(prob.facets)
                    eta += fd.sign * full[lay.facet_full_ranges[fi][fd.index[idx]]]
                end
                g = prob.step_group[idx]
                srng = lay.step_full_ranges[g]
                pv = view(pbuf, 1:length(prob.supports[g]))
                ld = FrequentistMFRM._row_probs!(pv, eta, view(full, srng))
                yk = prob.score_k[idx]
                cum_obs = yk == 0 ? 0.0 : sum(view(full, srng)[1:yk])
                ll_pq[prob.person_idx[idx], q] += prob.weights[idx] * ((yk * eta - cum_obs) - ld)
            end
        end
        p_ll = zeros(Float64, P)
        for p in 1:P
            vals = [ll_pq[p, q] + log_w[q] for q in 1:Q if log_w[q] > -Inf]
            mval = maximum(vals)
            p_ll[p] = mval + log(sum(exp(v - mval) for v in vals))
        end
        return p_ll
    end
end

diagnostics(f::FrequentistMFRM.Fit) = FrequentistMFRM.diagnostics(f)
qualify(f::FrequentistMFRM.Fit; kwargs...) = FrequentistMFRM.qualify(f; kwargs...)
fit_report(f::FrequentistMFRM.Fit) = FrequentistMFRM.report(f)
facets_report(f::FrequentistMFRM.Fit) = FrequentistMFRM.report(f)
fit_stats(f::FrequentistMFRM.Fit) = (;
    overall = FrequentistMFRM.checked(f).overall_fit,
    facets = FrequentistMFRM.checked(f).facet_measures,
    persons = FrequentistMFRM.checked(f).person_scores,
)
reliability(f::FrequentistMFRM.Fit) = FrequentistMFRM.checked(f).reliability
criteria(f::FrequentistMFRM.Fit) = FrequentistMFRM.criteria_report(f)
contrast(f::FrequentistMFRM.Fit; kwargs...) = FrequentistMFRM.contrast(f; kwargs...)
predict(f::FrequentistMFRM.Fit; kwargs...) = FrequentistMFRM.predict_rows(f; kwargs...)
event_probabilities(f::FrequentistMFRM.Fit; kwargs...) = FrequentistMFRM.predict_rows(f; kwargs...)

function facet_summary(f::FrequentistMFRM.Fit; facet::Symbol = :person)
    r = FrequentistMFRM.checked(f)
    target = facet === :entity ? :person : facet
    if target === :person
        return (; schema = "bayesianmgmfrm.frequentist_facet_summary.v1",
            inference_paradigm = :frequentist, facet = :person, rows = copy(r.person_scores))
    end
    rows = [x for x in r.facet_measures if x.facet === target]
    isempty(rows) && throw(ArgumentError("unknown facet $(repr(facet)); available: $([:person; [x.name for x in r.problem.facets]])"))
    return (; schema = "bayesianmgmfrm.frequentist_facet_summary.v1",
        inference_paradigm = :frequentist, facet = target, rows)
end

function category_summary(f::FrequentistMFRM.Fit)
    r = FrequentistMFRM.checked(f)
    return (;
        schema = "bayesianmgmfrm.frequentist_category_summary.v1",
        inference_paradigm = :frequentist,
        categories = copy(r.category_usage),
        steps = copy(r.step_measures),
    )
end

save_fit(path::AbstractString, f::FrequentistMFRM.Fit) = FrequentistMFRM.save_result(path, f)

function plot(f::FrequentistMFRM.Fit; kind::Symbol = :posterior, kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError("BayesianMGMFRM.plot requires CairoMakie; run `using CairoMakie`"))
    return extension.plot_frequentist_mfrm(f; kind, kwargs...)
end

# Explicit, honest refusals for Bayesian-only MCMC operations on FrequentistMFRM.Fit
for _bayesian_only_fn in (:posterior_summary, :posterior_mcse, :waic, :psis_loo, :prior_sensitivity, :logprior, :logposterior,
                          :ranking, :posterior_ranking, :classification, :posterior_classification,
                          :predictive_check, :posterior_predictive_check, :sampler_controls, :stan_data, :logdensity_and_gradient)
    @eval function $(_bayesian_only_fn)(f::FrequentistMFRM.Fit, args...; kwargs...)
        throw(ArgumentError(string(
            $(QuoteNode(_bayesian_only_fn)),
            " applies to Bayesian MCMC posteriors or log-density targets, whereas FrequentistMFRM.Fit is a non-Bayesian ",
            uppercase(string(f.record.summary.method)),
            " estimate; use fit_report(fit), facet_summary(fit), reliability(fit), criteria(fit), contrast(fit), or compare_models(...; criterion = :aic | :bic).",
        )))
    end
end

"""
    anchor_linking_summary(fit::FrequentistMFRM.Fit; coordinates)

Extract a named calibration from a qualified first-panel MRCML MMLE fit.
Each coordinate supplies the source `parameter` exactly as reported, and the
receiving `block` and `level`. For a step also supply `owner` and `upper_category`.
Select independent model coordinates on the same logit scale and sign convention.
The returned estimates and covariance axes share that order and can be passed
directly to `mfrm_spec(table; calibration=..., ...)`.
"""
function anchor_linking_summary(f::FrequentistMFRM.Fit; coordinates)
    r = FrequentistMFRM.checked(f)
    r.summary.method === :mmle && hasproperty(r,:mrcml_operator) &&
        !hasproperty(r.summary,:calibration) && r.summary.stationarity_qualified &&
        r.summary.hessian_positive_definite ||
        throw(ArgumentError("export requires a qualified first-panel MRCML MMLE calibration"))
    coordinates isa Union{AbstractVector,Tuple} && !isempty(coordinates) ||
        throw(ArgumentError("specify the labeled independent source coordinates"))
    names = r.mrcml_operator.model_names
    idx = Int[]
    rows = NamedTuple[]
    for coord in coordinates
        coord isa NamedTuple && haskey(coord,:parameter) && coord.parameter isa AbstractString ||
            throw(ArgumentError("each calibration row must name its source parameter"))
        i = findfirst(==(coord.parameter),names)
        isnothing(i) && throw(ArgumentError("unknown source calibration parameter $(repr(coord.parameter))"))
        push!(idx,i)
        push!(rows,(;Base.structdiff(coord,(;parameter=nothing))...,estimate=r.full_parameters[i]))
    end
    allunique(idx) || throw(ArgumentError("source calibration parameters must be distinct"))
    group = findfirst(r->get(r,:block,nothing)===:steps,rows)
    owner = isnothing(group) ? :global : get(rows[group],:owner,nothing)
    # Reject algebraically dependent reconstructed rows before extracting their covariance.
    J = Matrix(r.mrcml_operator.J_model[idx,:])
    rank(J)==length(idx) || throw(ArgumentError("choose independent, estimated source coordinates"))
    input = (;coordinates=rows,covariance=r.covariance.matrix[idx,idx])
    return first(AdditiveFacets._joint_calibration(input,owner))
end

include("mrcml_linking_report.jl")
