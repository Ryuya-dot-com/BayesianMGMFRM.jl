function _recovery_replication_names(values, label)
    names = collect(values)
    !isempty(names) && all(x -> x isa AbstractString && !isempty(strip(x)), names) &&
        length(unique(names)) == length(names) ||
        throw(ArgumentError("$label must contain unique nonempty strings"))
    return String.(names)
end

function _recovery_replication_metric(values, independent)
    n = length(values)
    estimate = n == 0 ? missing : mean(values)
    se = independent && n >= 2 ? std(values) / sqrt(n) : missing
    all(x -> ismissing(x) || isfinite(x), (estimate, se)) ||
        throw(ArgumentError("nonfinite replication aggregate"))
    status = !independent ? :independence_unresolved : n < 2 ? :insufficient_replications :
        iszero(se) ? :empirical_zero_variance : :available
    return (; estimate, replication_se=se, replication_se_status=status)
end

function _recovery_width_confidence(met, n, level, independent)
    status = !independent ? :independence_unresolved : n == 0 ? :no_qualified_datasets : :available
    lower, upper = missing, missing
    if status === :available
        tail = (1-level)/2
        lower = met == 0 ? 0.0 : Distributions.quantile(Distributions.Beta(met,n-met+1),tail)
        upper = met == n ? 1.0 : Distributions.cquantile(Distributions.Beta(met+1,n-met),tail)
    end
    return (; level, lower, upper, status, method=:clopper_pearson,
        conditioning=:numerically_qualified_datasets, simultaneous=false,
        classification_mcmc_error_bound=:not_computed)
end

function _recovery_replication_summary(rows, planned, independent; max_interval_width=nothing,
        width_confidence_level=nothing)
    n = length(rows)
    metric(f) = _recovery_replication_metric(Float64[f(r) for r in rows], independent)
    mse = metric(r -> r.squared_error)
    rmse = ismissing(mse.estimate) ? missing : sqrt(mse.estimate)
    rmse_se = ismissing(mse.replication_se) || iszero(rmse) ? missing : mse.replication_se / (2rmse)
    rmse_status = !ismissing(rmse) && iszero(rmse) ? :zero_mse_delta_unavailable : mse.replication_se_status
    covered = count(r -> r.covered, rows)
    result = (; n_datasets=n, n_planned=planned, n_unresolved=planned-n,
        bias=metric(r -> r.bias), mean_absolute_error=metric(r -> r.absolute_bias), mse,
        rmse=(; estimate=rmse, replication_se=rmse_se, replication_se_status=rmse_status,
            method=:first_order_delta), coverage=metric(r -> r.covered),
        mean_interval_width=metric(r -> r.interval_width),
        all_planned_coverage_bounds=(covered/planned, (covered+planned-n)/planned),
        coverage_bounds_kind=:unresolved_outcome_envelope_not_confidence_interval,
        conditional_on_retained_datasets=n != planned,
        full_planned_continuous_performance_available=n == planned)
    max_interval_width === nothing && return result
    all(r -> r.interval_width >= 0, rows) ||
        throw(ArgumentError("interval width must be nonnegative"))
    met = count(r -> r.interval_width <= max_interval_width, rows)
    target = (; max_interval_width,
        n_planned=planned, n_qualified=n,
        n_meeting_target=met, n_exceeding_target=n-met, n_unresolved=planned-n,
        conditional_frequency=metric(r -> r.interval_width <= max_interval_width),
        all_planned_frequency_bounds=(met/planned, (met+planned-n)/planned),
        bounds_kind=:unresolved_outcome_envelope_not_confidence_interval,
        classification=:estimated_central_interval_width,
        classification_mcmc_error_bound=:not_computed)
    if width_confidence_level !== nothing
        target = merge(target, (; conditional_confidence_interval=
            _recovery_width_confidence(met,n,width_confidence_level,independent)))
    end
    return merge(result, (; width_target=target))
end

# Observed-data target identities vary across replications; model/prior contracts must not.
_recovery_replication_contract(e) = merge(Base.structdiff(e.model_contract, (; fitted_target=nothing)),
    (; fitted_target_kind=e.model_contract.fitted_target.kind))

function _recovery_mcse_limits(limits, names)
    limits === nothing && return nothing
    limits isa AbstractDict && Set(keys(limits)) == Set(names) ||
        throw(ArgumentError("mcse_limits must map every requested parameter name to its limits"))
    normalized = Dict{String,NamedTuple}()
    for name in names
        bound = limits[name]
        bound isa NamedTuple && Set(keys(bound)) == Set((:mean_mcse_max,:endpoint_mcse_max)) ||
            throw(ArgumentError("each MCSE limit needs mean_mcse_max and endpoint_mcse_max"))
        all(x -> x isa Real && !(x isa Bool) && isfinite(x) && x > 0,values(bound)) ||
            throw(ArgumentError("MCSE limits must be finite positive real values"))
        value = (;mean_mcse_max=Float64(bound.mean_mcse_max),endpoint_mcse_max=Float64(bound.endpoint_mcse_max))
        all(x -> isfinite(x) && x > 0,values(value)) ||
            throw(ArgumentError("MCSE limits must remain finite and positive as Float64"))
        normalized[name] = value
    end
    normalized
end

function _recovery_mcse_disposition(evaluation, row, limits)
    lower,upper = _interval_probabilities(evaluation.interval_probability)
    quantiles = hasproperty(row.mcse,:quantiles) ? row.mcse.quantiles : ()
    endpoint(p) = begin
        matches = filter(q -> q.probability == p,quantiles)
        length(matches) == 1 ? only(matches).mcse : missing
    end
    endpoints = (endpoint(lower),endpoint(upper))
    values = (row.mcse.mean_mcse,endpoints...)
    available = row.mcse.mcse_status === :available && all(x ->
        x isa Real && !(x isa Bool) && isfinite(x) && x >= 0,values)
    meets_limits = available && values[1] <= limits.mean_mcse_max &&
        all(x -> x <= limits.endpoint_mcse_max,endpoints)
    mcse_status = !available ? :unavailable : meets_limits ? :passed : :exceeded
    status = evaluation.fixed_truth_mismatch ? :fixed_truth_mismatch :
        evaluation.sampling_warning ? :sampling_warning :
        !available ? :mcse_unavailable : meets_limits ? :passed : :mcse_exceeded
    (;status,passed=status === :passed,mcse_status,mean_mcse=values[1],
        endpoint_mcse=endpoints,endpoint_probabilities=(lower,upper),limits)
end

"""
    BayesianMGMFRM.recovery_replications(evaluations;
        planned_dataset_ids, parameters, scenario_id, dataset_independence,
        failures=Pair[], mcse_limits=nothing, max_interval_widths=nothing,
        width_confidence_level=nothing)

Summarize sealed `recovery_evaluation` records for one declared fixed-truth design
scenario. Declare the full dataset roster and exact focal quantity names before
examining results. Each quantity receives one observation per dataset; quantities,
persons, chains and folds are never pooled as independent replications. Changed
model/prior/scale/interval contracts and varying focal truths are rejected.

`failures` maps planned dataset IDs to nonempty reasons. Missing results, failures,
missing quantities, fixed constants and warnings remain in the output ledger.
`all_completed` includes numerical warnings; `without_warnings` excludes sampling
warnings, unavailable focal MCSE and any fixed-truth mismatch. The latter is a
descriptive subset, not a precision-qualified or scientifically accepted result.
Structural constants receive neither recovery summaries nor coverage credit.

To also require sufficiently small numerical error, specify `mcse_limits` as a
dictionary mapping every requested name to
`(mean_mcse_max=..., endpoint_mcse_max=...)`, in that quantity's native units.
Choose these limits before examining results; no universal limit is supplied.
This adds `summaries[i].precision_qualified` and `precision_dispositions` while
preserving `all_completed` and `without_warnings`. Both central-interval endpoints
and the posterior mean must meet their limits, MCSE must be available, and global
sampling warnings/fixed-truth mismatches must be absent. Fixed coordinates remain
ineligible. Counts retain the entire planned denominator, including failures and
missing results. Omitting the keyword preserves the original output.

Numerical precision is not measurement precision: small MCSE does not imply a
narrow posterior interval, calibrated coverage or an adequate collection design.
The precision-qualified summary is conditional on passing the computational
screen. It does not bound errors in coverage classification near an endpoint.

To summarize a measurement-precision target, also supply `max_interval_widths`
as a dictionary of positive finite widths for every requested parameter, in its
native units. This requires explicit `mcse_limits`. It adds `width_target` to
each non-fixed `precision_qualified` summary: counts meeting/exceeding the width,
the frequency among numerically qualified datasets and its replication SE, and
an unresolved-outcome envelope over all planned datasets. Equality meets the
target; failed, missing or numerically excluded outcomes remain unresolved.
The envelope assigns all unresolved outcomes first failure, then success; it is
not a confidence interval. Width classification uses estimated interval endpoints
and has no MCMC classification-error bound, including close to the threshold.
Zero empirical variance is not certainty about the target-attainment probability.
Prespecify meaningful widths and the desired frequency/replication precision;
this summary makes no design-acceptance or assurance claim. Omitting the keyword
preserves the previous output; no data generation or fitting is invoked.

With width targets, optionally request `width_confidence_level=0.95` for a
two-sided equal-tailed Clopper-Pearson confidence interval for the target-meeting
probability **conditional on numerical qualification**. This requires independent,
identically distributed dataset replications within the declared scenario; the
declaration is not independently verified. Reused evidence or unresolved
independence suppresses the interval. No qualified datasets also leaves it
unavailable. A single qualified dataset is permitted but yields a wide interval;
all-success/all-failure intervals remain nonzero in width even when empirical SE
is zero. The full-planned unresolved-outcome envelope remains a separate
descriptive quantity, not a confidence interval or the conditional probability.
These are per-quantity/scenario intervals, not simultaneous or valid for optional
stopping. Choose the target, scenario, roster and confidence level before looking
at outcomes. They concern estimated-width classifications, do not correct MCMC
classification error and are not Bayesian credible intervals or design approval.
Omitting `width_confidence_level` preserves the previous sealed output exactly.

Supply `dataset_independence=(status=:declared_independent, evidence="...")`, or
`:unresolved` with an explanation. The declaration concerns independent datasets
from the same scenario, not independent chains. Replication SE is sample SD / sqrt(n)
only for declared independence with at least two retained datasets. Reused evaluated
evidence suppresses SE despite a declaration. RMSE uses the first-order delta method;
zero MSE leaves its SE unavailable. Zero empirical variance is explicitly flagged.

Coverage bounds assign unresolved outcomes both 0 and 1 in the planned denominator;
they are not confidence intervals. No MCMC error correction, coverage-decision error
bound, seed/generator/design verification, SBC or design adequacy decision is made.
"""
function recovery_replications(evaluations; planned_dataset_ids, parameters,
        scenario_id::AbstractString, dataset_independence, failures=Pair[], mcse_limits=nothing,
        max_interval_widths=nothing, width_confidence_level=nothing)
    ids = _recovery_replication_names(planned_dataset_ids, "planned_dataset_ids")
    names = _recovery_replication_names(parameters, "parameters")
    limits = _recovery_mcse_limits(mcse_limits,names)
    widths = if max_interval_widths === nothing
        nothing
    else
        limits !== nothing || throw(ArgumentError("width targets require explicit mcse_limits"))
        max_interval_widths isa AbstractDict && Set(keys(max_interval_widths)) == Set(names) ||
            throw(ArgumentError("max_interval_widths must map every requested parameter to its width"))
        all(x -> x isa Real && !(x isa Bool) && isfinite(x) && x > 0, values(max_interval_widths)) ||
            throw(ArgumentError("maximum interval widths must be finite positive real values"))
        normalized = Dict(name => Float64(max_interval_widths[name]) for name in names)
        all(x -> isfinite(x) && x > 0, values(normalized)) ||
            throw(ArgumentError("maximum interval widths must remain finite and positive as Float64"))
        normalized
    end
    confidence = if width_confidence_level === nothing
        nothing
    else
        widths !== nothing || throw(ArgumentError("width confidence intervals require max_interval_widths"))
        width_confidence_level isa Real && !(width_confidence_level isa Bool) &&
            isfinite(width_confidence_level) && 0 < width_confidence_level < 1 ||
            throw(ArgumentError("width_confidence_level must be a finite real value between zero and one"))
        value = Float64(width_confidence_level)
        0 < (1-value)/2 < 0.5 ||
            throw(ArgumentError("width_confidence_level loses its tail probabilities as Float64"))
        value
    end
    isempty(strip(scenario_id)) && throw(ArgumentError("scenario_id must be nonempty"))
    dataset_independence isa NamedTuple && keys(dataset_independence) == (:status, :evidence) &&
        dataset_independence.status in (:unresolved, :declared_independent) &&
        dataset_independence.evidence isa AbstractString && !isempty(strip(dataset_independence.evidence)) ||
        throw(ArgumentError("declare dataset independence status and evidence/reference"))
    records = Dict{String,Any}()
    contract = nothing
    interval = nothing
    evidence_ids = Dict{String,Vector{String}}()
    for e in evaluations
        _prediction_check_seal(e, "bayesianmgmfrm.recovery_evaluation.v1")
        e.dataset_id in ids && !haskey(records, e.dataset_id) ||
            throw(ArgumentError("unplanned or duplicate recovery dataset"))
        current = _recovery_replication_contract(e)
        contract === nothing || _cache_hash(current) == _cache_hash(contract) ||
            throw(ArgumentError("replications must share the analysis model/prior/scale contract"))
        interval === nothing || e.interval_probability == interval ||
            throw(ArgumentError("replications must use the same interval probability"))
        contract, interval = current, e.interval_probability
        records[e.dataset_id] = deepcopy(e)
        if any(r -> !r.fixed, e.rows)
            identity = e.source_sample_hash === nothing ?
                _cache_hash((e.model_contract.fitted_target, e.evaluated_draws_hash)) : e.source_sample_hash
            push!(get!(evidence_ids, identity, String[]), e.dataset_id)
        end
    end
    failed = Dict{String,String}()
    for pair in failures
        pair isa Pair && first(pair) isa AbstractString && last(pair) isa AbstractString &&
            !isempty(strip(last(pair))) || throw(ArgumentError("failures must map IDs to nonempty reasons"))
        id = String(first(pair))
        id in ids && !haskey(failed, id) && !haskey(records, id) ||
            throw(ArgumentError("unplanned, duplicate or already evaluated failure ID"))
        failed[id] = String(last(pair))
    end
    repeated = sort!([sort!(group) for group in values(evidence_ids) if length(group) > 1]; by=first)
    independent = dataset_independence.status === :declared_independent && isempty(repeated)
    ledger = map(ids) do id
        e = get(records, id, nothing)
        (; dataset_id=id, status=e === nothing ? (haskey(failed, id) ? :failed : :missing) : e.status,
            failure_reason=get(failed, id, nothing), evaluation=e)
    end
    summaries = map(names) do name
        available, screened, qualified = NamedTuple[], NamedTuple[], NamedTuple[]
        precision_dispositions = NamedTuple[]
        descriptor = nothing
        truth = nothing
        dispositions = map(ledger) do entry
            e = entry.evaluation
            selected = e === nothing ? [] : filter(r -> r.parameter == name, e.rows)
            if isempty(selected)
                disposition = (;entry.dataset_id,status=e === nothing ? entry.status : :missing_quantity)
                limits === nothing || push!(precision_dispositions,merge(disposition,(;passed=false)))
                return disposition
            end
            row = only(selected)
            current = (; row.parameter, row.block, row.dimension, row.dimension_label,
                row.fixed, row.derived, row.parameter_space)
            descriptor === nothing || isequal(current, descriptor) ||
                throw(ArgumentError("focal quantity metadata differs across datasets: $name"))
            truth === nothing || row.true_value == truth ||
                throw(ArgumentError("fixed-truth replications require identical focal truths: $name"))
            descriptor, truth = current, row.true_value
            if row.fixed
                limits === nothing || push!(precision_dispositions,(;entry.dataset_id,status=:structurally_fixed,passed=false))
                return (;entry.dataset_id,status=:structurally_fixed)
            end
            all(isfinite, (row.bias, row.absolute_bias, row.squared_error, row.interval_width)) &&
                row.covered isa Bool || throw(ArgumentError("nonfinite or invalid recovery row: $name"))
            warning = e.sampling_warning || e.fixed_truth_mismatch || row.mcse.mcse_status !== :available
            push!(available, row)
            warning || push!(screened, row)
            if limits !== nothing
                precision = _recovery_mcse_disposition(e,row,limits[name])
                push!(precision_dispositions,merge((;entry.dataset_id),precision))
                precision.passed && push!(qualified,row)
            end
            return (; entry.dataset_id, status=warning ? :warning : :available_without_warning)
        end
        fixed = descriptor !== nothing && descriptor.fixed
        summary = (; parameter=name, descriptor, true_value=truth, dispositions,
            applicability=fixed ? :structurally_fixed : descriptor === nothing ? :not_observed : :estimated,
            all_completed=fixed ? nothing : _recovery_replication_summary(available, length(ids), independent),
            without_warnings=fixed ? nothing : _recovery_replication_summary(screened, length(ids), independent))
        limits === nothing ? summary : merge(summary,(;precision_dispositions,
            precision_qualified=fixed ? nothing : _recovery_replication_summary(qualified,length(ids),independent;
                max_interval_width=widths === nothing ? nothing : widths[name],
                width_confidence_level=confidence)))
    end
    result = (; schema="bayesianmgmfrm.recovery_replications.v1",
        scenario_id=String(scenario_id), truth_policy=:fixed_focal_truth,
        planned_dataset_ids=ids, parameters=names, n_planned=length(ids),
        n_completed=length(records), n_failed=length(failed), n_missing=length(ids)-length(records)-length(failed),
        model_contract=contract, interval_probability=interval, ledger, summaries,
        dataset_independence=deepcopy(dataset_independence), repeated_evaluation_evidence=repeated,
        replication_se_enabled=independent, evaluation_unit=:dataset_per_named_quantity,
        uncertainty=(; within_fit_mcmc=:retained_in_ledger_not_combined,
            replication_se=:sample_sd_over_sqrt_n, rmse_se=:first_order_delta,
            coverage_decision_error_bound=:not_computed, precision_threshold=:not_applied),
        design_and_generator_verification=:not_established, independence_verified=false,
        calibration_verified=false, sbc=:not_performed, scientific_acceptance=:not_established)
    if limits !== nothing
        result = merge(result,(;mcse_limits=limits,
            uncertainty=merge(result.uncertainty,(;precision_threshold=:absolute_focal_mean_and_central_endpoints))))
    end
    widths === nothing || (result = merge(result, (;max_interval_widths=widths)))
    confidence === nothing || (result = merge(result, (;width_confidence_level=confidence)))
    return _prediction_seal(result)
end

"""
    BayesianMGMFRM.design_precision_plot_data(results; parameter)

Read one or more sealed `recovery_replications` summaries with width targets.
Return one row per scenario for the named quantity, preserving target widths,
qualification counts, conditional confidence intervals (when requested during
aggregation), and the separate full-planned unresolved-outcome envelopes.
Fixed quantities, duplicate scenarios and different observed quantity scales or
central-interval probabilities are rejected. All-failed scenarios remain visible.
Scenario comparability and independence are not established by this display;
model/prior/truth contracts remain in the source summaries. No contrast test,
ranking, generation or fitting is performed. Use these rows for numerical export.
"""
function design_precision_plot_data(results; parameter::AbstractString)
    records = results isa NamedTuple ? [results] : collect(results)
    isempty(records) && throw(ArgumentError("supply at least one recovery summary"))
    ids = String[]
    descriptor, probability, level = nothing, nothing, nothing
    rows = map(records) do result
        _prediction_check_seal(result,"bayesianmgmfrm.recovery_replications.v1")
        result.scenario_id in ids && throw(ArgumentError("scenario IDs must be unique"))
        push!(ids,result.scenario_id)
        hasproperty(result,:max_interval_widths) || throw(ArgumentError("summary has no width targets"))
        matches = filter(s -> s.parameter == parameter,result.summaries)
        length(matches) == 1 || throw(ArgumentError("requested parameter is absent"))
        summary = only(matches)
        summary.applicability === :structurally_fixed &&
            throw(ArgumentError("fixed quantities do not have precision targets"))
        if summary.descriptor !== nothing
            descriptor === nothing || isequal(descriptor,summary.descriptor) ||
                throw(ArgumentError("quantity scales or descriptors differ across scenarios"))
            descriptor = summary.descriptor
        end
        if result.interval_probability !== nothing
            probability === nothing || probability == result.interval_probability ||
                throw(ArgumentError("central-interval probabilities differ across scenarios"))
            probability = result.interval_probability
        end
        q = summary.precision_qualified.width_target
        ci = hasproperty(q,:conditional_confidence_interval) ? q.conditional_confidence_interval :
            (;status=:not_requested,level=nothing,lower=missing,upper=missing)
        if ci.level !== nothing
            level === nothing || level == ci.level ||
                throw(ArgumentError("confidence levels differ across scenarios"))
            level = ci.level
        end
        (; scenario_id=result.scenario_id, result_hash=result.content_hash,
            max_interval_width=q.max_interval_width, n_planned=q.n_planned,
            n_qualified=q.n_qualified, n_meeting_target=q.n_meeting_target,
            n_exceeding_target=q.n_exceeding_target, n_unresolved=q.n_unresolved,
            conditional_frequency=q.conditional_frequency.estimate,
            confidence_interval=ci, all_planned_frequency_bounds=q.all_planned_frequency_bounds)
    end
    return (; parameter=String(parameter), descriptor, interval_probability=probability,
        confidence_level=level, rows,
        bounds_kind=:unresolved_outcome_envelope_not_confidence_interval,
        comparison=:descriptive_not_a_design_selection)
end

"""
    BayesianMGMFRM.plot_design_precision(results; parameter, annotation_io=stdout, size=nothing)

Plot width-target summaries in two panels: conditional frequency with requested
Clopper-Pearson confidence intervals, and full-planned unresolved-outcome bounds
(not confidence intervals). Requires `using CairoMakie`. All-failed scenarios,
unavailable intervals, target widths and qualified/planned counts stay visible.
The figure uses `design_precision_plot_data` without new sampling. Titles and
notes are external by default; `annotation_io=nothing` embeds them.
"""
function plot_design_precision(results; kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError("plot_design_precision requires `using CairoMakie`"))
    return extension.plot_design_precision(results; kwargs...)
end
