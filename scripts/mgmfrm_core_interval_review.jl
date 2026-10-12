module MGMFRMCoreIntervalReview

import BayesianMGMFRM as B
import MCMCDiagnosticTools as M
using Statistics

"""Truth-blind quantile precision for the existing median/90% SBC screens.

Rows are contiguous chain blocks. Empirical posterior mass in the two-MCSE
bands describes where that screen would leave a truth unresolved. Under a
correct continuous posterior it approximates a conditional unresolved
probability; it is not a bound or a forecast across future datasets. Unavailable
MCSE or MCSE/90%-width > .05 makes the corresponding proxy one. Rank Rhat is
reported separately: no convergence qualification or sampling rule is applied.
"""
function quantile_precision(draws::AbstractMatrix{<:Real}; parameter_names, chains::Integer)
    names = String.(collect(parameter_names))
    !isempty(names) && all(n -> !isempty(strip(n)), names) &&
        length(unique(names)) == length(names) ||
        throw(ArgumentError("Unique nonempty parameter names are required"))
    size(draws, 1) > 0 && size(draws, 2) == length(names) &&
        all(x -> !(x isa Bool) && isfinite(x), draws) ||
        throw(ArgumentError("Finite nonempty draws are required"))
    chains isa Bool && throw(ArgumentError("chains must be a positive integer"))
    precision = B.posterior_mcse(draws; chains, parameter_names=names,
        probabilities=(.05, .5, .95))
    finite(x) = x isa Real && isfinite(x) && x >= 0
    rows = map(eachindex(names)) do j
        x = draws[:, j]
        samples = reshape(x, :, chains)
        estimable = chains >= 2 && size(samples, 1) >= 10 && !allequal(x)
        rh = estimable ? M.rhat(samples; kind=:rank, split_chains=2) : missing
        quantiles = map(precision[j].quantiles) do q
            ess = estimable ? M.ess(samples;
                kind=Base.Fix2(Statistics.quantile, q.probability), split_chains=2) : missing
            valid = finite(ess) && ess > 0
            (; q..., ess=valid ? ess : missing,
                probability_mcse=valid ? sqrt(q.probability*(1-q.probability)/ess) : missing)
        end
        lo, med, hi = quantiles
        width = hi.estimate-lo.estimate
        usable(q) = width > 0 && finite(q.mcse) && q.mcse/width <= .05
        near(q, value) = abs(value-q.estimate) <= 2q.mcse
        median_available = usable(med)
        coverage_available = usable(lo) && usable(hi)
        median_mass = median_available ? count(v -> near(med,v), x)/length(x) : missing
        coverage_mass = coverage_available ? count(v -> near(lo,v) || near(hi,v), x)/length(x) : missing
        (; parameter=names[j], quantiles, width_90=width,
            rank_rhat=finite(rh) ? rh : missing, mcse_status=precision[j].mcse_status,
            median_precision_available=median_available,
            coverage_precision_available=coverage_available,
            median_guard_mass=median_mass, coverage_guard_mass=coverage_mass,
            median_unresolved_mass_proxy=median_available ? median_mass : 1.,
            coverage_unresolved_mass_proxy=coverage_available ? coverage_mass : 1.)
    end
    return (; rows, total_draws=size(draws,1), n_chains=Int(chains),
        draws_per_chain=size(draws,1) ÷ chains, truth_used=false,
        diagnostic_qualification_applied=false, probability_bound_verified=false,
        scientific_acceptance=false)
end

"""Inspect intervals and the empirical CDF at named generating truths.

Rows must be contiguous chain blocks. All retained draws are used for quantiles
and autocorrelation-aware MCSE, not treated as independent SBC rank draws.
The two-MCSE boundary flag is a local sensitivity diagnostic, not a confidence
bound, convergence check, eligibility gate or calibration decision. Constant
indicators keep unavailable MCSE, including empirical CDF estimates of 0 or 1.
"""
function interval_review(draws::AbstractMatrix{<:Real}, truth::AbstractDict;
        parameter_names, chains::Integer)
    names = String.(collect(parameter_names))
    !isempty(names) && all(n -> !isempty(strip(n)), names) &&
        length(unique(names)) == length(names) && Set(keys(truth)) == Set(names) ||
        throw(ArgumentError("Unique names and an exact named truth mapping are required"))
    size(draws, 1) > 0 && size(draws, 2) == length(names) &&
        all(x -> !(x isa Bool) && isfinite(x), draws) &&
        all(x -> x isa Real && !(x isa Bool) && isfinite(x), values(truth)) ||
        throw(ArgumentError("Finite nonempty draws and truths are required"))
    chains isa Bool && throw(ArgumentError("chains must be a positive integer"))
    probabilities = (.025, .05, .5, .95, .975)
    precision = B.posterior_mcse(draws; chains, parameter_names=names, probabilities)
    truths = Float64[truth[name] for name in names]
    indicators = Float64.(draws .< permutedims(truths))
    cdf_precision = B.posterior_mcse(indicators; chains, parameter_names=names,
        probabilities=())
    finite(x) = x isa Real && isfinite(x) && x >= 0
    rows = map(eachindex(names)) do j
        x, t, m = draws[:, j], truths[j], precision[j]
        quantiles = Dict(q.probability => q for q in m.quantiles)
        intervals = map(((.9, .05, .95), (.95, .025, .975))) do (level, lo, hi)
            lower, upper = quantiles[lo], quantiles[hi]
            width = upper.estimate - lower.estimate
            available = width > 0 && finite(lower.mcse) && finite(upper.mcse)
            distance = (abs(t - lower.estimate), abs(t - upper.estimate))
            near = available ? any(distance .<= 2 .* (lower.mcse, upper.mcse)) : missing
            (; level, lower=lower.estimate, upper=upper.estimate, width,
                covered=lower.estimate <= t <= upper.estimate,
                lower_mcse=lower.mcse, upper_mcse=upper.mcse,
                maximum_endpoint_mcse_over_width=available ? max(lower.mcse, upper.mcse)/width : missing,
                boundary_sensitivity=ismissing(near) ? :mcse_unavailable :
                    near ? :within_two_mcse : :beyond_two_mcse)
        end
        indicators_j = reshape(indicators[:, j], :, chains)
        c = cdf_precision[j]
        ties = count(==(t), x)
        (; parameter=names[j], truth=t, estimate=mean(x), error=mean(x)-t,
            posterior_sd=std(x), precision=m, intervals,
            cdf=(; strictly_below=mean(indicators_j), ties,
                less_or_equal=mean(indicators_j)+ties/length(x),
                mean_mcse=c.mean_mcse,
                mean_mcse_status=finite(c.mean_mcse) ? :available : c.mcse_status,
                chain_means=vec(mean(indicators_j; dims=1))))
    end
    return (; rows, n_chains=Int(chains), draws_per_chain=size(draws, 1) ÷ chains,
        total_draws=size(draws, 1), quantile_method=:linear_interpolation_type7,
        cdf_method=:strict_indicator_with_ties_reported_separately,
        interval_boundary_mcse_multiplier=2,
        diagnostic_qualification_applied=false, independence_verified=false,
        calibration_verified=false, scientific_acceptance=false)
end

end
