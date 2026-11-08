# Shared with the saved-contrast example; retain its established numerical rules.
function posterior_contrast(left::AbstractVector, right::AbstractVector;
        chains::Int, log_ratio = false,
        interval = 0.9, rope = nothing)
    length(left) == length(right) > 0 || throw(ArgumentError("Draw lengths must match and be nonzero."))
    chains > 0 && length(left) % chains == 0 ||
        throw(ArgumentError("Draws must form equal contiguous chain blocks."))
    isfinite(interval) && 0 < interval < 1 || throw(ArgumentError("interval must be in (0, 1)."))
    a, b = Float64.(left), Float64.(right)
    all(isfinite, a) && all(isfinite, b) || throw(ArgumentError("Draws must be finite."))
    log_ratio && !(all(>(0), a) && all(>(0), b)) &&
        throw(ArgumentError("Log ratios require positive draws."))
    values = log_ratio ? log.(a) .- log.(b) : a .- b
    all(isfinite, values) || throw(ArgumentError("The contrast is nonfinite."))
    bounds = if rope === nothing
        nothing
    else
        length(rope) == 2 || throw(ArgumentError("Supply two ROPE bounds on the contrast scale."))
        lo, hi = Float64.(rope)
        isfinite(lo) && isfinite(hi) && lo <= hi || throw(ArgumentError("Invalid ROPE bounds."))
        (lo, hi)
    end
    probabilities = ((1 - interval) / 2, 0.5, (1 + interval) / 2)
    precision = only(posterior_mcse(reshape(values, :, 1); chains,
        parameter_names = ["contrast"], probabilities))
    lo, med, hi = getproperty.(precision.quantiles, :estimate)

    # Event MCSE uses the ordered indicator draws, including autocorrelation.
    # All-zero/all-one indicators keep unavailable MCSE, not false certainty.
    events = [("above_zero", values .> 0)]
    if bounds !== nothing
        push!(events, ("below_rope", values .< bounds[1]),
            ("inside_rope", (bounds[1] .<= values) .& (values .<= bounds[2])),
            ("above_rope", values .> bounds[2]))
    end
    event_rows = map(events) do (name, indicator)
        mcse = only(posterior_mcse(reshape(Float64.(indicator), :, 1); chains,
            parameter_names = [name], probabilities = ()))
        (; event = name, count = count(indicator), probability = mean(indicator),
            mean_mcse = mcse.mean_mcse,
            mcse_status = ismissing(mcse.mean_mcse) ? mcse.mcse_status : :available)
    end

    n = length(values) ÷ chains
    status = chains < 2 ? :insufficient_chains : n < 10 ? :insufficient_draws :
        allequal(values) ? :degenerate_draws : :available
    rhat = bulk_ess = tail_ess = missing
    if status === :available
        samples = reshape(values, n, chains)
        metrics = MCMCDiagnosticTools.ess_rhat(samples; kind = :rank,
            split_chains = 2, maxlag = n)
        tail = MCMCDiagnosticTools.ess(samples; kind = :tail,
            split_chains = 2, maxlag = n, tail_prob = 0.1)
        rhat, bulk_ess, tail_ess = map(x -> isfinite(x) ? Float64(x) : missing,
            (metrics.rhat, metrics.ess, tail))
        any(ismissing, (rhat, bulk_ess, tail_ess)) && (status = :unavailable)
    end
    ratio_interval = if log_ratio
        transformed = map(x -> isfinite(exp(x)) && exp(x) > 0 ? exp(x) : missing, (med, lo, hi))
        (; median = transformed[1], lower = transformed[2], upper = transformed[3],
            status = any(ismissing, transformed) ? :not_representable : :available,
            method = :exponentiated_log_scale_quantiles)
    else
        nothing
    end
    return (; mean = mean(values), sd = length(values) > 1 ? std(values) : missing, median = med,
        lower = lo, upper = hi, interval, rope = bounds,
        scale = log_ratio ? :log_ratio : :difference,
        ratio_interval,
        precision, event_rows,
        contrast_diagnostics = (; status, rank_normalized_rhat = rhat, bulk_ess, tail_ess,
            split_chains = 2, tail_probability = 0.1, thresholds_applied = false),
        chains, draws_per_chain = n, total_draws = length(values))
end

"""
    BayesianMGMFRM.posterior_contrast(fit; left, right,
        operation=:difference, interval=0.90, rope=nothing)
    BayesianMGMFRM.posterior_contrast(left::AbstractVector, right::AbstractVector;
        chains, log_ratio=false, interval=0.90, rope=nothing)

Compare two named model coordinates within a saved scalar `MFRMFit`, independent
`MGMFRMFit` or `Experimental.NormalizedMGMFRMFit`. Use exact names from
`BayesianMGMFRM.recovery_quantities(fit).rows`, including the dimension label
for multidimensional abilities. `:difference` accepts two persons in the same dimension or two
rater severities. `:log_ratio` accepts two positive rater consistencies. Other
coordinate combinations, repeated names and two structurally fixed quantities
are rejected. Scalar MFRM differences use unit logits, including reference or
hard-anchored raters reconstructed at their fixed values; external anchor
uncertainty is excluded. Its RSM and PCM threshold choices are supported.
GMFRM, fixed-Q multidimensional MFRM and correlated MGMFRM are outside this method.

Compute left minus right, or log(left) minus log(right), at each original joint
posterior draw. Preserve complete chain order and reconstruct constrained model
coordinates, including the final rater. No fitting, resampling, scale linking or
subtraction of marginal interval endpoints occurs. Differences use the fitted
ability/severity units; do not compare different dimensions or different fits.

`summary` retains the mean/SD, central equal-tailed interval, endpoint/mean/SD
MCSE, contrast-specific rank-normalized split R-hat and bulk/tail ESS. It also
reports P(contrast > 0). Optional `rope=(lo,hi)` uses inclusive bounds, on the
difference or log-ratio scale, and reports probabilities below/inside/above.
Constant sampled events have unavailable MCSE, not proof of zero uncertainty.
Log-ratio `ratio_interval` exponentiates the median and interval endpoints;
it is not a mean ratio, and MCSE remains on the log scale.

Whole-fit warnings remain in `whole_fit_diagnostics` and `sampling_warning`;
good contrast diagnostics do not override them. No numerical threshold,
practical-equivalence rule, fairness label or automatic decision is applied.
The result includes coordinate units, model/prior/source identities, original
chain/iteration IDs and an evaluated-draw hash. Save the result with its native
fit and original environment; it is not a portable posterior-draw format.
The vector method preserves the existing paired-summary calculation for
already extracted draws. It returns `summary` directly, requires equal contiguous
chain blocks, and cannot verify source identity, units or whole-fit diagnostics.
The caller must retain joint pairing and supply the complete original chains;
use the fit method when a supported saved fit is available.
This operation does not promote the underlying experimental model to Supported.
"""
function posterior_contrast(fit::Union{MFRMFit,MGMFRMFit,_NormalizedMGMFRMFit};
        left::AbstractString, right::AbstractString, operation::Symbol=:difference,
        interval=0.90, rope=nothing)
    left != right || throw(ArgumentError("choose two distinct coordinate names"))
    operation in (:difference,:log_ratio) || throw(ArgumentError("operation must be difference or log_ratio"))
    context = _recovery_context(fit)
    lookup = Dict(r.parameter=>r for r in context.coordinates)
    haskey(lookup,left) && haskey(lookup,right) || throw(ArgumentError(
        "unknown coordinate; use exact names from recovery_quantities(fit).rows"))
    a, b = lookup[left], lookup[right]
    da, db = _recovery_quantity(a,context.spec), _recovery_quantity(b,context.spec)
    (da.block,da.dimension,da.parameter_space) == (db.block,db.dimension,db.parameter_space) ||
        throw(ArgumentError("contrast coordinates must share a facet, dimension and scale"))
    permitted = operation === :difference ? da.block in (:person,:rater) : da.block === :rater_consistency
    permitted || throw(ArgumentError("use differences for abilities/severities and log_ratio for rater consistency"))
    !(a.fixed && b.fixed) || throw(ArgumentError("both coordinates are fixed by the model; this is not an estimated contrast"))
    summary = posterior_contrast(a.values,b.values;
        chains=length(unique(context.chain_ids)),log_ratio=operation===:log_ratio,interval,rope)
    return _prediction_seal((;schema="bayesianmgmfrm.posterior_contrast.v1",
        left=String(left),right=String(right),operation,coordinates=(;left=da,right=db),summary,
        model_contract=_recovery_model_contract(fit,context),
        whole_fit_diagnostics=deepcopy(context.quality),
        sampling_warning=_prediction_sampling_warning(context.quality),
        n_retained_draws=context.total_draws,chain_ids=copy(context.chain_ids),
        iterations=copy(context.iterations),
        evaluated_draws_hash=_cache_hash((;left=a.values,right=b.values)),
        context.source_sample_hash,context.source_hash_status,
        scientific_acceptance=:not_established,new_fits=0))
end

