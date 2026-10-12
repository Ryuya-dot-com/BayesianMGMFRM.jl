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

function _recovery_replication_summary(rows, planned, independent)
    n = length(rows)
    metric(f) = _recovery_replication_metric(Float64[f(r) for r in rows], independent)
    mse = metric(r -> r.squared_error)
    rmse = ismissing(mse.estimate) ? missing : sqrt(mse.estimate)
    rmse_se = ismissing(mse.replication_se) || iszero(rmse) ? missing : mse.replication_se / (2rmse)
    rmse_status = !ismissing(rmse) && iszero(rmse) ? :zero_mse_delta_unavailable : mse.replication_se_status
    covered = count(r -> r.covered, rows)
    return (; n_datasets=n, n_planned=planned, n_unresolved=planned-n,
        bias=metric(r -> r.bias), mean_absolute_error=metric(r -> r.absolute_bias), mse,
        rmse=(; estimate=rmse, replication_se=rmse_se, replication_se_status=rmse_status,
            method=:first_order_delta), coverage=metric(r -> r.covered),
        mean_interval_width=metric(r -> r.interval_width),
        all_planned_coverage_bounds=(covered/planned, (covered+planned-n)/planned),
        coverage_bounds_kind=:unresolved_outcome_envelope_not_confidence_interval,
        conditional_on_retained_datasets=n != planned,
        full_planned_continuous_performance_available=n == planned)
end

# Observed-data target identities vary across replications; model/prior contracts must not.
_recovery_replication_contract(e) = merge(Base.structdiff(e.model_contract, (; fitted_target=nothing)),
    (; fitted_target_kind=e.model_contract.fitted_target.kind))

"""
    BayesianMGMFRM.recovery_replications(evaluations;
        planned_dataset_ids, parameters, scenario_id, dataset_independence, failures=Pair[])

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
        scenario_id::AbstractString, dataset_independence, failures=Pair[])
    ids = _recovery_replication_names(planned_dataset_ids, "planned_dataset_ids")
    names = _recovery_replication_names(parameters, "parameters")
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
        available, screened = NamedTuple[], NamedTuple[]
        descriptor = nothing
        truth = nothing
        dispositions = map(ledger) do entry
            e = entry.evaluation
            selected = e === nothing ? [] : filter(r -> r.parameter == name, e.rows)
            isempty(selected) && return (; entry.dataset_id,
                status=e === nothing ? entry.status : :missing_quantity)
            row = only(selected)
            current = (; row.parameter, row.block, row.dimension, row.dimension_label,
                row.fixed, row.derived, row.parameter_space)
            descriptor === nothing || isequal(current, descriptor) ||
                throw(ArgumentError("focal quantity metadata differs across datasets: $name"))
            truth === nothing || row.true_value == truth ||
                throw(ArgumentError("fixed-truth replications require identical focal truths: $name"))
            descriptor, truth = current, row.true_value
            row.fixed && return (; entry.dataset_id, status=:structurally_fixed)
            all(isfinite, (row.bias, row.absolute_bias, row.squared_error, row.interval_width)) &&
                row.covered isa Bool || throw(ArgumentError("nonfinite or invalid recovery row: $name"))
            warning = e.sampling_warning || e.fixed_truth_mismatch || row.mcse.mcse_status !== :available
            push!(available, row)
            warning || push!(screened, row)
            return (; entry.dataset_id, status=warning ? :warning : :available_without_warning)
        end
        fixed = descriptor !== nothing && descriptor.fixed
        (; parameter=name, descriptor, true_value=truth, dispositions,
            applicability=fixed ? :structurally_fixed : descriptor === nothing ? :not_observed : :estimated,
            all_completed=fixed ? nothing : _recovery_replication_summary(available, length(ids), independent),
            without_warnings=fixed ? nothing : _recovery_replication_summary(screened, length(ids), independent))
    end
    return _prediction_seal((; schema="bayesianmgmfrm.recovery_replications.v1",
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
        calibration_verified=false, sbc=:not_performed, scientific_acceptance=:not_established))
end
