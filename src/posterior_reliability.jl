function _posterior_reliability_components(values, weights, target)
    target in (:absolute, :centered) || throw(ArgumentError("target must be :absolute or :centered"))
    S, N = size(values)
    S >= 2 && N >= 2 || throw(ArgumentError("reliability requires at least two draws and two selected levels"))
    length(weights) == N && all(w -> w isa Real && !(w isa Bool) && isfinite(w) && w > 0, weights) ||
        throw(ArgumentError("weights must be finite positive real numbers, one per selected level"))
    w = Float64.(weights)
    w ./= maximum(w)
    w ./= sum(w)
    all(x -> isfinite(x) && x > 0, w) || throw(ArgumentError("weights cannot be represented after normalization"))
    x = Float64.(values)
    all(isfinite, x) || throw(ArgumentError("selected draws must be finite"))
    # Subtract a fixed origin before moments; centered targets also remove each joint draw's cohort mean.
    origin = x[1, 1]
    x .-= origin
    target === :centered && (x .-= x * w)
    m = vec(mean(x; dims=1))
    residual = x .- m'
    v = vec(mean(abs2.(residual); dims=1))
    centered_means = m .- sum(w .* m)
    between = sum(w .* abs2.(centered_means))
    within = sum(w .* v)
    total = between + within
    all(isfinite, (between, within, total)) || throw(ArgumentError("posterior variance overflow; rescale the input model"))
    reliability = total > 0 ? between / total : missing
    # Delta-method influence of B/(B+W); dependence across selected levels stays within each row.
    influence = if total > 0
        db = 2 .* (residual * (w .* centered_means))
        dw = abs2.(residual) * w .- within
        ((within / total) .* db .- (between / total) .* dw) ./ total
    else
        zeros(S)
    end
    all(isfinite, influence) || throw(ArgumentError("nonfinite reliability influence values"))
    means = target === :absolute ? m .+ origin : m
    return (; weights=w, means, variances=v, between, within, total, reliability, influence)
end

function _posterior_reliability_mcse(c, chains)
    S = length(c.influence)
    n = div(S, chains)
    status = ismissing(c.reliability) ? :zero_total_variance :
        c.between == 0 || c.within == 0 ? :boundary_delta_unavailable :
        chains < 2 ? :insufficient_chains : n < 10 ? :insufficient_draws :
        allequal(c.influence) ? :degenerate_influence : :available
    value = status === :available ?
        _posterior_mcse_value(reshape(c.influence, n, chains), Statistics.mean) : missing
    status === :available && ismissing(value) && (status = :mcse_unavailable)
    return (; value, status, method=:mcmc_delta_influence, n_chains=chains,
        draws_per_chain=n, convergence_review_required=true, precision_threshold_applied=false)
end

"""
    BayesianMGMFRM.posterior_reliability(fit; parameters, target, weights=nothing)

Summarize finite-cohort posterior reliability from an existing supported fit.
Select at least two estimated location coordinates by exact names from
`recovery_quantities(fit)`, all in the same person/item/rater block and dimension.
Fixed anchors, loadings, thresholds and mixed dimensions are rejected. Optional
positive `weights` follow `parameters` order and are normalized to sum to one;
the default gives each selected level equal weight, not each observed rating.

The required `target=:absolute` uses locations in the fitted coordinate system.
`target=:centered` subtracts the selected cohort's weighted mean *within each
joint draw*, retaining covariance and removing common-location uncertainty.
Subset selection and weights therefore define both the cohort and its reference.

For selected means `mᵢ`, posterior variances `vᵢ`, and normalized weights `wᵢ`,
return `B = sum(wᵢ*(mᵢ-sum(wⱼ*mⱼ))^2)`, `W = sum(wᵢ*vᵢ)` and `B/(B+W)`.
This is the between-level fraction of variance of a weighted mixture of the
selected posterior marginals. Both level and retained-draw moments use normalized
probability weights (no Bessel correction). It is a posterior functional estimated
by pooled complete chains, not a distribution of reliability over draws. No CrI,
FACETS separation/Strata, population, retest or new-design reliability is inferred.
Zero total variance returns `missing`; empirical zero posterior variance is flagged,
never treated as proof that the sampler resolved a parameter exactly.

`mcse` uses the first-order influence of the ratio with the existing chain-aware
asymptotic-variance estimator. It is numerical error, not a credible interval.
It is unavailable at zero between/within variance, for short/single chains or
degenerate influence. Finite-draw bias and convergence are not certified by MCSE.
Sampling warnings, exact selected coordinates, model/prior identity and source
hash status are retained. Shared calibration uncertainty is included only to the
extent represented in the saved joint draws; fixed calibration cannot be restored.
High rater reliability means distinguishable severity, not score agreement.

This qualified candidate entry supports the eight common saved-fit types and
preserves each model's support limits. It does not replace the historical
`separation_reliability_summary` numerically or validate its old interpretation.
"""
function posterior_reliability(fit::PredictionObservationAdapter.SupportedFit;
        parameters, target::Symbol, weights=nothing)
    parameters isa Union{AbstractVector,Tuple} || throw(ArgumentError("parameters must be a vector or tuple of exact coordinate names"))
    names = collect(parameters)
    length(names) >= 2 && all(p -> p isa AbstractString && !isempty(strip(p)), names) &&
        length(unique(names)) == length(names) || throw(ArgumentError("select at least two distinct nonempty coordinate names"))
    context = _recovery_context(fit)
    lookup = Dict(r.parameter => r for r in context.coordinates)
    all(p -> haskey(lookup, p), names) || throw(ArgumentError("unknown reliability coordinate"))
    coordinates = [lookup[p] for p in names]
    descriptions = [_recovery_quantity(r, context.spec) for r in coordinates]
    d = first(descriptions)
    d.block in (:person, :rater, :item) && all(r ->
        (r.block, r.dimension, r.parameter_space) == (d.block, d.dimension, d.parameter_space), descriptions) ||
        throw(ArgumentError("reliability requires one location block, dimension and scale"))
    any(r -> r.fixed, descriptions) && throw(ArgumentError("exclude structurally fixed anchors from the reliability cohort"))
    selected = hcat([r.values for r in coordinates]...)
    weights === nothing || weights isa Union{AbstractVector,Tuple} || throw(ArgumentError("weights must be a vector or tuple"))
    c = _posterior_reliability_components(selected, weights === nothing ? ones(length(names)) : collect(weights), target)
    mcse = _posterior_reliability_mcse(c, length(unique(context.chain_ids)))
    zero_variance = [names[i] for i in eachindex(names) if c.variances[i] == 0]
    rows = [merge(descriptions[i], (; weight=c.weights[i], posterior_mean=c.means[i],
        posterior_variance=c.variances[i], empirical_zero_variance=c.variances[i] == 0)) for i in eachindex(names)]
    sampling_warning = _prediction_sampling_warning(context.quality)
    result = (; schema="bayesianmgmfrm.posterior_reliability.v1", target,
        reliability=c.reliability, between_variance=c.between, within_variance=c.within,
        total_variance=c.total, rows, n_levels=length(names),
        cohort=:explicit_selected_levels, variance_convention=:normalized_finite_mixture,
        interval=:not_computed, strata=:not_computed, separation=:not_computed, mcse,
        empirical_zero_variance_parameters=zero_variance,
        model_contract=_recovery_model_contract(fit, context),
        n_retained_draws=context.total_draws, chain_ids=copy(context.chain_ids), iterations=copy(context.iterations),
        evaluated_draws_hash=_cache_hash((; parameters=names, values=selected)),
        context.source_sample_hash, context.source_hash_status,
        sampling_quality=deepcopy(context.quality), sampling_warning,
        status=sampling_warning || mcse.status !== :available || !isempty(zero_variance) ? :warning : :descriptive,
        scientific_acceptance=:not_established,
        scope=:finite_cohort_posterior_functional_not_design_reliability)
    return _prediction_seal(result)
end
