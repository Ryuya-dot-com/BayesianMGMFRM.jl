# Include this file, load an existing cache, then call saved_mgmfrm_contrast.
# These helpers summarize joint draws; they never fit, resample or change a cache.
using BayesianMGMFRM, Statistics
import MCMCDiagnosticTools

function paired_contrast_summary(left::AbstractVector, right::AbstractVector;
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

function saved_mgmfrm_contrast(fit::BayesianMGMFRM.Experimental.MGMFRMFit;
        kind::Symbol, left::AbstractString, right::AbstractString,
        dimension = nothing, interval = 0.9, rope = nothing)
    kind in (:ability, :severity, :log_consistency_ratio) ||
        throw(ArgumentError("Choose :ability, :severity, or :log_consistency_ratio."))
    left != right || throw(ArgumentError("Choose two distinct fitted levels."))
    spec = fit.design.spec
    labels = kind === :ability ? spec.data.person_levels : spec.data.rater_levels
    a, b = findfirst(==(left), labels), findfirst(==(right), labels)
    a !== nothing && b !== nothing || throw(ArgumentError("Both labels must occur in the saved fit."))
    if kind === :ability
        d = findfirst(==(dimension), spec.dimension_labels)
        d !== nothing || throw(ArgumentError("Supply a stored dimension label for ability differences."))
        indices = fit.design.blocks[:person]
        ia, ib = indices[(a - 1) * spec.dimensions + d], indices[(b - 1) * spec.dimensions + d]
    else
        dimension === nothing || throw(ArgumentError("Rater parameters have no dimension selector."))
        indices = fit.design.blocks[kind === :severity ? :rater : :rater_consistency]
        ia, ib = indices[a], indices[b]
    end
    chains = length(fit.chain_acceptance_rate)
    n = size(fit.direct_draws, 1) ÷ chains
    fit.chain_ids == repeat(1:chains; inner = n) && fit.iterations == repeat(1:n; outer = chains) ||
        throw(ArgumentError("Saved chain and iteration order must be intact."))
    check = diagnostics(fit; view = :public)
    summary = paired_contrast_summary(fit.direct_draws[:, ia], fit.direct_draws[:, ib];
        chains, log_ratio = kind === :log_consistency_ratio, interval, rope)
    return (; kind, left, right, dimension, summary,
        whole_fit_diagnostics = check.summary,
        interpretation = "Left minus right; consistency uses log(left) minus log(right). Positive means higher ability, greater severity, or larger consistency. Ability-difference magnitudes and nonzero ROPE bounds use the saved model's ability unit. Contrasts remain conditional on its prior and rating design. Whole-fit warnings remain applicable; no practical-equivalence or reliability decision is made.")
end
