const _PRIOR_POWER_SCHEMA = "bayesianmgmfrm.prior_power_sensitivity.v1"

function _pcm_power_target(fit::_NormalizedMGMFRMFit)
    _sensitivity_prior_contract(fit, :mean_profile) # Fail before interpreting raw coordinates.
    return _normalized_mgmfrm_target(fit)
end

function _pcm_power_factors(t::_MGMFRMSlopeLogDensity)
    spec, blocks = t.base.design.spec, t.blueprint.blocks
    d = length(spec.data.category_levels)-2
    steps = blocks[:item_steps]
    groups = d == 0 ? UnitRange{Int}[] : [s:s+d-1 for s in first(steps):d:last(steps)]
    common = (; family=:zero_sum_gaussian, measure=:last_reconstructed_free_coordinates,
        scale_convention=:kernel_sd_for_centered_blocks, units=:model_coordinate,
        normalization=:included, jacobian_powered=false,
        reconstruction=:last_equals_negative_sum_of_free,
        power_equivalence=:fixed_sd_divided_by_sqrt_alpha)
    return [merge(common, (; id="rater_severity", facet=:rater,
                owner_ids=copy(spec.data.rater_levels), groups=[blocks[:rater_free]],
                means=zeros(length(t.mean_shift)), sd=t.base.prior.rater_sd,
                free_dimension=length(blocks[:rater_free]))),
            merge(common, (; id="item_step_residual", facet=:item,
                owner_ids=copy(spec.data.item_levels), category_levels=copy(spec.data.category_levels),
                groups, means=copy(t.mean_shift), sd=t.base.prior.step_sd,
                free_dimension=length(steps)))]
end

function _pcm_factor_record(fit, t)
    definitions = _pcm_power_factors(t)
    draws = fit.record.run.draws
    factors = map(definitions) do f
        values = [sum((_slope_normal_block_logprior(row, f.means, ix, f.sd, true)
            for ix in f.groups); init=0.0) for row in eachrow(draws)]
        all(isfinite, values) || throw(ArgumentError("nonfinite scientific prior factor"))
        merge(f, (; log_density=values))
    end
    return (; schema="bayesianmgmfrm.pcm_prior_factors.v1", factors,
        coordinate_names=copy(t.blueprint.parameter_names),
        spec_hash=_cache_hash(fit.record.spec), target_identity=fit.record.target_identity,
        source_sample_hash=fit.record.content_hash,
        chain_ids=copy(fit.record.run.chain_ids), iterations=copy(fit.record.run.iterations))
end

"""
    logprior(fit::Experimental.NormalizedMGMFRMFit; components=:factors)

Inspect normalized scientific Gaussian prior factors for independent D1,
fixed-one partial-credit `MeanProfilePrior` fits. Returns factor IDs, facet/owner
labels, free-coordinate groups/names, means, fixed kernel SDs, normalized densities,
measure and saved-target/sample binding. Both factors use last-reconstructed
zero-sum coordinates; constants include `log(n)/2` for each n-member block.
No sampler Jacobian is powered. This bounded inspection rejects other models.
Use returned factor IDs in `prior_sensitivity(fit; powers=...)`.
"""
function logprior(fit::_NormalizedMGMFRMFit; components=:factors)
    components === :factors || throw(ArgumentError("use components=:factors"))
    t = _pcm_power_target(fit)
    _recovery_context(fit) # Validate the sealed samples and complete chain layout.
    return _pcm_factor_record(fit, t)
end

function _power_mean_mcse(x, nchains; fixed=false)
    fixed && return 0.0
    length(x) % nchains == 0 || throw(ArgumentError("incomplete mean-MCSE chains"))
    length(x) ÷ nchains >= 8 && !allequal(x) || return nothing
    v = MCMCDiagnosticTools.mcse(reshape(x, :, nchains); kind=mean, split_chains=2)
    return isfinite(v) && v >= 0 ? Float64(v) : nothing
end

function _power_weights(lp, alpha, nchains, max_k; r_eff=nothing, analytic_constant=false)
    S = length(lp)
    lr = (alpha-1).*lp
    all(isfinite, lr) || throw(ArgumentError("nonfinite prior power ratios"))
    raw = exp.(lr .- maximum(lr)); raw ./= sum(raw)
    threshold = min(max_k, 1-1/log10(S))
    identity = alpha == 1 || analytic_constant
    if identity
        return (; raw_log_ratios=lr, raw_weights=fill(1/S,S), weights=fill(1/S,S),
            identity=true, status=:analytic_identity, reliable=true, pareto_k=nothing,
            r_eff=nothing, r_eff_method=:not_needed, tail_len=0, threshold,
            weight_ess=Float64(S), method=:exact_identity)
    end
    constant = allequal(lr)
    reff = r_eff === nothing && !constant && S÷nchains >= 8 ?
        MCMCDiagnosticTools.ess(reshape(lr,:,nchains); kind=:tail, split_chains=2)/S : r_eff
    valid = reff !== nothing && isfinite(reff) && reff > 0
    ps = valid && !constant ? Experimental.StarAssociation._psis_smooth_log_ratios(lr; r_eff=reff) : nothing
    k = constant ? Inf : ps === nothing ? nothing : ps.pareto_k
    reliable = k !== nothing && isfinite(k) && k < threshold
    weights = ps === nothing ? raw : exp.(ps.norm_log_weights)
    return (; raw_log_ratios=lr, raw_weights=raw, weights, identity=false,
        status=constant ? :empirical_constant_not_identity : ps === nothing ? :tail_ess_unavailable :
            reliable ? :weight_screen_passed : :unreliable_reweighting,
        reliable, pareto_k=k, r_eff=valid ? Float64(reff) : nothing,
        r_eff_method=r_eff === nothing ? :tail_ess_of_log_ratios : :explicit,
        tail_len=ps === nothing ? 0 : ps.tail_len, threshold,
        weight_ess=1/sum(abs2,weights), method=ps === nothing ? :raw_only : :psis)
end

function _power_estimands(estimands, context, scale)
    scale in (:model, :unit_logit) || throw(ArgumentError("scale must be :model or :unit_logit"))
    return map(_sensitivity_estimands(estimands, context)) do e
        convert = scale === :unit_logit && e.parameter_space === :model_coordinate
        merge(e, (; values=convert ? 1.7.*e.values : e.values,
            parameter_space=convert ? :unit_logit : e.parameter_space))
    end
end

function _power_focal(e, weights, nchains, max_mcse, sampling_warning)
    g, S = e.values, length(e.values)
    base = mean(g)
    mu = weights.identity || e.fixed ? base : sum(weights.weights.*g)
    base_mcse = _power_mean_mcse(g,nchains; fixed=e.fixed)
    z = S.*weights.weights.*(g.-mu)
    mcse = weights.identity ? base_mcse : weights.reliable ?
        _power_mean_mcse(z,nchains; fixed=e.fixed) : nothing
    shift_mcse = weights.identity ? 0.0 : weights.reliable ?
        _power_mean_mcse(z.-(g.-base),nchains; fixed=e.fixed) : nothing
    return merge(Base.structdiff(e,(;values=nothing)), (; baseline_mean=base,
        baseline_mean_mcse=base_mcse, mean=mu, mean_shift=weights.identity ? 0.0 : mu-base,
        mean_mcse=mcse, paired_shift_mcse=shift_mcse,
        precision_status=mcse === nothing ? :unavailable : weights.identity ? :baseline : :plugin_delta_not_calibrated,
        precision_qualified=max_mcse === nothing ? nothing :
            !sampling_warning && weights.reliable && mcse !== nothing && mcse <= max_mcse,
        quantile_precision=:not_computed, decision_precision=:not_computed))
end

function _power_alternative(reference, alternative, selected, alpha, estimands, scale, max_mcse, baseline_rows)
    alternative isa _NormalizedMGMFRMFit || throw(ArgumentError("alternatives must be saved normalized fits"))
    _pcm_power_target(alternative)
    _cache_hash(reference.record.spec) == _cache_hash(alternative.record.spec) || throw(ArgumentError(
        "alternative observations, categories, labels and model must match the baseline"))
    p = reference.record.prior
    expected = merge(p,(;scales=merge(p.scales,(;
        rater_sd=p.scales.rater_sd/("rater_severity" in selected ? sqrt(alpha) : 1),
        step_sd=p.scales.step_sd/("item_step_residual" in selected ? sqrt(alpha) : 1)))))
    isequal(expected,alternative.record.prior) || throw(ArgumentError(
        "alternative must match the exact powered fixed-scale Gaussian prior; means and other factors must agree"))
    context = _recovery_context(alternative)
    warning = _prediction_sampling_warning(context.quality)
    rows = map(_power_estimands(estimands,context,scale)) do e
        m = _power_mean_mcse(e.values,length(unique(context.chain_ids)); fixed=e.fixed)
        b = only(row for row in baseline_rows if row.label == e.label)
        merge(Base.structdiff(e,(;values=nothing)),(;mean=mean(e.values),mean_mcse=m,
            mean_shift=mean(e.values)-b.baseline_mean,
            mean_shift_mcse_upper_bound=m === nothing || b.baseline_mean_mcse === nothing ? nothing : m+b.baseline_mean_mcse,
            precision_qualified=max_mcse === nothing ? nothing : !warning && m !== nothing && m<=max_mcse))
    end
    return (; target_identity=alternative.record.target_identity,
        source_sample_hash=alternative.record.content_hash, prior=deepcopy(context.prior),
        sampling_quality=deepcopy(context.quality), sampling_warning=warning,
        chain_ids=copy(context.chain_ids), iterations=copy(context.iterations), rows,
        paired_with_baseline=false, cross_fit_covariance=:unknown)
end

"""
    prior_sensitivity(fit::Experimental.NormalizedMGMFRMFit; powers, estimands,
        scale, dataset_id, observation_ids, alternatives=Pair[],
        max_pareto_k=0.7, max_mean_mcse=nothing, r_eff=nothing)

Reweight a saved independent D1 fixed-one PCM `MeanProfilePrior` fit. Declare
`powers=["wide" => (factors=["rater_severity"], alpha=0.25)]`; inspect factor
IDs with `logprior(fit; components=:factors)`. Selected Gaussian factors have
fixed means/SDs: power alpha equals SD/sqrt(alpha), up to a constant. Hierarchical
scales and other models are rejected. Alpha must be positive. Estimands use the
same coordinate names or paired contrasts as the saved-fit sensitivity method.
Specify `scale=:model` or `:unit_logit` (D=1.7 applied to draws and MCSE together).

Tail ESS of log ratios supplies PSIS relative efficiency unless explicitly set.
The existing loo-style ceil-tail kernel is used, not priorsense's floor-tail rule.
The Pareto screen is min(max_pareto_k, 1-1/log10(S)); it never clears baseline
sampling warnings. Exact alpha=1/structurally constant factors bypass smoothing;
empirically constant ratios under a changed prior do not establish identity.

Mean and paired-shift MCSE use chain-aware plug-in delta influence sequences,
excluding PSIS tail-fit uncertainty. They are unavailable for failed weights;
quantile/decision precision and scientific acceptance are not established.
`max_mean_mcse` is an optional numerical bound in the requested estimand units,
not a practical-sensitivity threshold. `alternatives=["wide"=>saved_fit]` checks
the full data/model and exact powered prior. Reports retain failed weights and
supplied fits separately, selecting the supplied fit for display when weights
fail. Its own warnings remain. No automatic refitting or random generation.
Save/reopen with `save_report(...; return_receipt=true)` and `load_report` with
the separately retained `expected_sha256`; the reopened JSON is computed data.
"""
function prior_sensitivity(fit::_NormalizedMGMFRMFit; powers, estimands, scale,
        dataset_id::AbstractString, observation_ids, alternatives=Pair[],
        max_pareto_k=0.7, max_mean_mcse=nothing, r_eff=nothing)
    !isempty(strip(dataset_id)) || throw(ArgumentError("dataset_id must be nonempty"))
    max_pareto_k isa Real && !(max_pareto_k isa Bool) && isfinite(max_pareto_k) &&
        0 < max_pareto_k <= .7 || throw(ArgumentError("max_pareto_k must be in (0, 0.7]"))
    max_mean_mcse === nothing || (max_mean_mcse isa Real && !(max_mean_mcse isa Bool) &&
        isfinite(max_mean_mcse) && max_mean_mcse>0) || throw(ArgumentError("invalid max_mean_mcse"))
    r_eff === nothing || (r_eff isa Real && !(r_eff isa Bool) && isfinite(r_eff) && r_eff>0) ||
        throw(ArgumentError("r_eff must be a finite positive number"))
    t = _pcm_power_target(fit)
    context = _recovery_context(fit)
    context.total_draws >= 5 || throw(ArgumentError("at least five retained draws required"))
    observations = PredictionObservationAdapter._ids(observation_ids,context.spec.data.n,"observation_ids")
    factors = _pcm_factor_record(fit,t)
    es = _power_estimands(estimands,context,scale)
    specs = collect(powers)
    all(p -> p isa Pair,specs) || throw(ArgumentError("powers must contain named pairs"))
    ids = _recovery_replication_names(first.(specs),"power IDs")
    altpairs = collect(alternatives)
    all(p -> p isa Pair && first(p) in ids,altpairs) &&
        length(unique(first.(altpairs))) == length(altpairs) || throw(ArgumentError("unknown or duplicate alternative ID"))
    alts = Dict(altpairs)
    lookup = Dict(f.id=>f for f in factors.factors)
    nchains = length(unique(context.chain_ids))
    warning = _prediction_sampling_warning(context.quality)
    cases = map(specs) do entry
        id, choice = entry
        choice isa NamedTuple && Set(keys(choice)) == Set((:factors,:alpha)) ||
            throw(ArgumentError("each power needs exactly factors and alpha"))
        choice.factors isa AbstractVector || throw(ArgumentError("factors must be a vector of IDs"))
        selected = _recovery_replication_names(choice.factors,"factor IDs")
        all(haskey(lookup,f) for f in selected) || throw(ArgumentError("unknown scientific factor"))
        alpha = choice.alpha
        alpha isa Real && !(alpha isa Bool) && isfinite(alpha) && alpha>0 || throw(ArgumentError("alpha must be finite and positive"))
        alpha = Float64(alpha)
        isfinite(alpha) && alpha>0 || throw(ArgumentError("alpha must remain finite and positive in Float64"))
        lp = zeros(context.total_draws)
        for f in selected
            lp .+= lookup[f].log_density
        end
        weights = _power_weights(lp,Float64(alpha),nchains,max_pareto_k; r_eff,
            analytic_constant=all(lookup[f].free_dimension==0 for f in selected))
        rows = [_power_focal(e,weights,nchains,max_mean_mcse,warning) for e in es]
        alternative = haskey(alts,id) ? _power_alternative(fit,alts[id],selected,alpha,estimands,scale,max_mean_mcse,rows) : nothing
        use_alternative = !weights.reliable && alternative !== nothing
        return (; id=String(id), factors=selected, alpha=Float64(alpha), reweighting=weights, rows,
            alternative, selected_source=use_alternative ? :supplied_alternative : weights.reliable ? :reweighting : :unavailable,
            sampling_warning=warning, refit_performed=false)
    end
    return _prediction_seal((;schema=_PRIOR_POWER_SCHEMA, scope=:normalized_d1_fixed_one_pcm,
        dataset_id=String(dataset_id), observation_ids=observations, scale,
        baseline=(;target_identity=fit.record.target_identity,source_sample_hash=fit.record.content_hash,
            prior=deepcopy(context.prior),sampling_quality=deepcopy(context.quality),sampling_warning=warning),
        factor_record=factors, cases, max_mean_mcse, max_pareto_k,
        precision_method=:chain_aware_plugin_delta_ignores_tail_fit_uncertainty,
        kernel=(;method=:zhang_stephens_psis, tail_rule=:ceil_min_point2S_3sqrtS_over_reff,
            diagnostic_package_version=string(Base.pkgversion(MCMCDiagnosticTools))),
        quantile_precision=:not_computed,decision_precision=:not_computed,
        scientific_acceptance=:not_established,new_fits=0,new_random_draws=0))
end
