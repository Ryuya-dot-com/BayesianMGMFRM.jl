using BayesianMGMFRM, Serialization

"""
    saved_recovery_replications(paths; kwargs...)

Reload serialized `recovery_evaluation` records and summarize a predeclared
fixed-truth scenario. Supply the complete planned roster even if files are
missing or fits failed. Independent datasets and their generation must be
documented separately; this example does not generate data or run fits.
Pass `mcse_limits=Dict("parameter_name" =>
    (mean_mcse_max=..., endpoint_mcse_max=...))` to also summarize the subset
meeting explicit computational precision limits. Include every requested name;
limits use its native units. This does not specify an acceptable interval width
or establish adequate precision for a data-collection decision.
Also pass `max_interval_widths=Dict("parameter_name" => width)` to summarize
width-target frequencies among numerically qualified datasets and unresolved
outcome bounds over the complete planned roster. This requires `mcse_limits`;
neither the conditional frequency nor its bounds constitute design acceptance.
"""
function saved_recovery_replications(paths; kwargs...)
    return BayesianMGMFRM.recovery_replications(deserialize.(paths); kwargs...)
end

"""
    saved_recovery_width_review(paths; parameter, max_interval_width,
                                mcse_limits, kwargs...)

Review one named quantity's central-interval width against an explicit target
in its native units. Forward the complete planned roster, scenario and
independence declaration to `saved_recovery_replications`. `mcse_limits` is
required; it must specify limits for this one parameter.

Return the unchanged recovery summary and a `width_review` row for every planned
dataset. `width_margin = max_interval_width - interval_width` is positive when
the observed interval is narrower than the target. `observed_width_within_target`
is `missing` for numerical exclusions, failed/missing datasets, absent quantities
and fixed coordinates. Their statuses remain visible; exclusions are not false
precision outcomes. Available widths are retained even with numerical warnings.

This example does not select a design, estimate assurance or apply an MCMC
classification-error bound. Inspect endpoint MCSE when the width is close to the
target; the two endpoint errors can be correlated. Prespecify a scientifically
meaningful target and use adequate independent replication for a design study.
No interval width or numerical tolerance is recommended by this example.
"""
function saved_recovery_width_review(paths; parameter, max_interval_width,
        mcse_limits, kwargs...)
    max_interval_width isa Real && !(max_interval_width isa Bool) &&
        isfinite(max_interval_width) && max_interval_width > 0 ||
        throw(ArgumentError("max_interval_width must be finite and positive in the parameter's native units"))
    limit = Float64(max_interval_width)
    isfinite(limit) && limit > 0 ||
        throw(ArgumentError("max_interval_width must be representable as a positive finite Float64"))
    mcse_limits === nothing && throw(ArgumentError("explicit mcse_limits are required for the width review"))
    recovery = saved_recovery_replications(paths; parameters=[parameter], mcse_limits, kwargs...)
    quantity = only(recovery.summaries)
    width_review = map(recovery.ledger, quantity.precision_dispositions) do entry, precision
        selected = entry.evaluation === nothing ? [] :
            filter(r -> r.parameter == parameter, entry.evaluation.rows)
        width = isempty(selected) || only(selected).fixed ? missing : only(selected).interval_width
        ismissing(width) || width >= 0 || throw(ArgumentError("interval width must be nonnegative"))
        (; entry.dataset_id, numerical_status=precision.status,
            numerically_qualified=precision.passed, interval_width=width,
            width_margin=ismissing(width) ? missing : limit-width,
            observed_width_within_target=precision.passed ? width <= limit : missing,
            mean_mcse=get(precision, :mean_mcse, missing),
            endpoint_mcse=get(precision, :endpoint_mcse, missing))
    end
    return (; parameter, max_interval_width=limit,
        interval_probability=recovery.interval_probability,
        parameter_space=quantity.descriptor === nothing ? nothing : quantity.descriptor.parameter_space,
        n_planned=recovery.n_planned, width_review, recovery)
end
