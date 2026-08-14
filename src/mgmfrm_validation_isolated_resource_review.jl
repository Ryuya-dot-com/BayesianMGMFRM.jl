# Threshold-free review of bounded isolated MGMFRM resource receipts.

const _MGMFRM_VALIDATION_ISOLATED_RESOURCE_REVIEW_SCHEMA =
    "bayesianmgmfrm.mgmfrm_validation_isolated_resource_review.v1"

function _mgmfrm_validation_isolated_resource_review_result(result)
    hasproperty(result, :schema) &&
        String(result.schema) ==
            _MGMFRM_VALIDATION_ISOLATED_RESOURCE_PROBE_SCHEMA ||
        throw(ArgumentError(
            "resource review requires isolated resource-probe results",
        ))
    hasproperty(result, :object) &&
        Symbol(result.object) === :mgmfrm_validation_isolated_resource_probe ||
        throw(ArgumentError(
            "resource review received the wrong result object",
        ))
    required = (
        :cell_id,
        :status,
        :worker_process_started,
        :timed_out,
        :exit_code,
        :worker_elapsed_seconds,
        :child_receipt,
        :mcmc_executed,
        :parent_preflight,
        :cell,
        :scientific_execution_authorized,
        :final_resource_policy_frozen,
    )
    all(field -> hasproperty(result, field), required) ||
        throw(ArgumentError(
            "isolated resource-probe result is missing review fields",
        ))

    cell_id = Symbol(result.cell_id)
    expected = _mgmfrm_validation_isolated_resource_cell(cell_id)
    _mgmfrm_validation_probe_cell_id(result.cell) === cell_id ||
        throw(ArgumentError(
        "isolated resource-probe cell does not match its cell_id",
        ))
    result.scientific_execution_authorized === false || throw(ArgumentError(
        "isolated resource-probe result changed the scientific guard",
    ))
    result.final_resource_policy_frozen === false || throw(ArgumentError(
        "isolated resource-probe result changed the resource-policy guard",
    ))
    receipt_recorded = !ismissing(result.child_receipt)
    receipt = receipt_recorded ? result.child_receipt : nothing
    receipt_required = (
        :status,
        :n_completed,
        :denominator_preserved,
        :free_memory_bytes_observed,
        :available_memory_bytes_observed,
        :raw_free_memory_bytes_observed,
        :memory_availability_basis,
        :memory_pressure_preflight_passed,
        :minimum_free_memory_bytes_required,
        :memory_preflight_passed,
        :process_peak_rss_bytes,
    )
    receipt_recorded &&
        !all(field -> hasproperty(receipt, field), receipt_required) &&
        throw(ArgumentError(
            "isolated worker receipt is missing review fields",
        ))
    child_completed = receipt_recorded && receipt.n_completed == 1
    return (;
        cell_id,
        resource_sequence = expected.resource_sequence,
        resource_collection =
            _mgmfrm_validation_isolated_resource_collection(expected),
        result_status = Symbol(result.status),
        worker_process_started = result.worker_process_started,
        timed_out = result.timed_out,
        exit_code = result.exit_code,
        worker_elapsed_seconds = result.worker_elapsed_seconds,
        parent_free_memory_bytes_observed =
            result.parent_preflight.free_memory_bytes_observed,
        parent_available_memory_bytes_observed =
            result.parent_preflight.available_memory_bytes_observed,
        parent_raw_free_memory_bytes_observed =
            result.parent_preflight.raw_free_memory_bytes_observed,
        parent_memory_availability_basis =
            result.parent_preflight.memory_availability_basis,
        parent_memory_pressure_free_percent =
            result.parent_preflight.memory_pressure_free_percent,
        parent_memory_pressure_preflight_passed =
            result.parent_preflight.memory_pressure_preflight_passed,
        parent_minimum_free_memory_bytes_required =
            result.parent_preflight.minimum_free_memory_bytes_required,
        parent_memory_preflight_passed =
            result.parent_preflight.memory_preflight_passed,
        receipt_recorded,
        child_status = receipt_recorded ? Symbol(receipt.status) : missing,
        child_free_memory_bytes_observed = receipt_recorded ?
            receipt.free_memory_bytes_observed : missing,
        child_available_memory_bytes_observed = receipt_recorded ?
            receipt.available_memory_bytes_observed : missing,
        child_raw_free_memory_bytes_observed = receipt_recorded ?
            receipt.raw_free_memory_bytes_observed : missing,
        child_memory_availability_basis = receipt_recorded ?
            Symbol(receipt.memory_availability_basis) : missing,
        child_memory_pressure_free_percent = receipt_recorded &&
            hasproperty(receipt, :memory_pressure_free_percent) ?
            receipt.memory_pressure_free_percent : missing,
        child_memory_pressure_preflight_passed = receipt_recorded ?
            receipt.memory_pressure_preflight_passed : missing,
        child_minimum_free_memory_bytes_required = receipt_recorded ?
            receipt.minimum_free_memory_bytes_required : missing,
        child_memory_preflight_passed = receipt_recorded ?
            receipt.memory_preflight_passed : missing,
        child_completed,
        child_denominator_preserved = receipt_recorded ?
            receipt.denominator_preserved : missing,
        mcmc_executed = result.mcmc_executed,
        process_peak_rss_bytes = receipt_recorded ?
            receipt.process_peak_rss_bytes : missing,
        julia_version = receipt_recorded &&
            hasproperty(receipt, :julia_version) ?
            String(receipt.julia_version) : missing,
        os = receipt_recorded && hasproperty(receipt, :os) ?
            String(receipt.os) : missing,
        arch = receipt_recorded && hasproperty(receipt, :arch) ?
            String(receipt.arch) : missing,
        n_threads = receipt_recorded && hasproperty(receipt, :n_threads) ?
            Int(receipt.n_threads) : missing,
        stop_before_next_cell = !child_completed,
        manual_review_required = true,
        resource_threshold_applied = false,
        scientific_decision = :not_applied,
    )
end

function _mgmfrm_validation_isolated_review_sequence(cell_ids)
    stress_sequence = (
        :default_sparse_short_nuts,
        mgmfrm_validation_scaled_resource_plan().execution_order...,
    )
    primary_sequence = Tuple(
        row.cell_id for row in mgmfrm_validation_primary_resource_plan().rows
        if row.within_current_short_nuts_probe_bound
    )
    isempty(cell_ids) && return (;
        resource_collection = :not_applicable,
        full_sequence = (),
        submitted_order_matches_plan = true,
    )
    collection = all(cell_id -> cell_id in stress_sequence, cell_ids) ?
        :stress_default_and_scaled :
        all(cell_id -> cell_id in primary_sequence, cell_ids) ?
            :primary_resource_short_nuts_subset :
            :mixed_or_unknown
    full_sequence = collection === :stress_default_and_scaled ?
        stress_sequence :
        collection === :primary_resource_short_nuts_subset ?
            primary_sequence : ()
    prefix_matches = collection !== :mixed_or_unknown &&
        length(cell_ids) <= length(full_sequence) &&
        cell_ids == full_sequence[1:length(cell_ids)]
    return (;
        resource_collection = collection,
        full_sequence,
        submitted_order_matches_plan = prefix_matches,
    )
end

function _mgmfrm_validation_isolated_resource_review(results)
    results isa Tuple || results isa AbstractVector || throw(ArgumentError(
        "results must be a tuple or vector of isolated resource-probe results",
    ))
    rows = Tuple(
        _mgmfrm_validation_isolated_resource_review_result(result)
        for result in results
    )
    cell_ids = Tuple(row.cell_id for row in rows)
    length(unique(cell_ids)) == length(cell_ids) || throw(ArgumentError(
        "isolated resource review cell_id values must be unique",
    ))
    sequence = _mgmfrm_validation_isolated_review_sequence(cell_ids)
    submitted_order_matches_plan =
        sequence.submitted_order_matches_plan
    full_resource_sequence_complete =
        !isempty(cell_ids) && cell_ids == sequence.full_sequence
    n_receipts_recorded = count(row -> row.receipt_recorded, rows)
    n_child_completed = count(row -> row.child_completed, rows)
    n_attention_required = count(row -> row.stop_before_next_cell, rows)
    all_completed = !isempty(rows) && n_child_completed == length(rows)
    status = isempty(rows) ? :no_isolated_resource_results :
        all_completed && submitted_order_matches_plan ?
            :isolated_resource_receipts_ready_for_manual_review :
            :isolated_resource_results_require_attention
    next_gate = isempty(rows) ?
        :run_isolated_default_short_nuts_resource_probe :
        all_completed && submitted_order_matches_plan ?
            :manually_review_worker_metrics_before_next_cell_or_policy :
            :stop_and_review_incomplete_or_out_of_order_results
    return (;
        schema = _MGMFRM_VALIDATION_ISOLATED_RESOURCE_REVIEW_SCHEMA,
        object = :mgmfrm_validation_isolated_resource_review,
        status,
        rows,
        submitted_order = cell_ids,
        submitted_order_matches_plan,
        resource_collection = sequence.resource_collection,
        full_resource_sequence = sequence.full_sequence,
        summary = (;
            n_submitted = length(rows),
            n_worker_processes_started = count(
                row -> row.worker_process_started, rows),
            n_receipts_recorded,
            n_child_completed,
            n_mcmc_executed = count(
                row -> row.mcmc_executed === true, rows),
            n_attention_required,
            denominator_preserved = true,
            denominator_scope = :submitted_results,
            full_resource_sequence_complete,
        ),
        automatic_progression_allowed = false,
        manual_review_required = true,
        resource_thresholds_applied = false,
        final_resource_policy_frozen = false,
        convergence_assessed = false,
        scientific_execution_authorized = false,
        scientific_decision = :not_applied,
        next_gate,
        claim_scope = :threshold_free_operational_resource_review,
    )
end

"""
    mgmfrm_validation_isolated_resource_review(results)

Summarize a tuple or vector of results returned by
[`mgmfrm_validation_isolated_resource_probe`](@ref). The review preserves each
parent/child memory preflight, worker outcome, elapsed time, and worker-process
peak RSS. It checks submitted cell order within either the stress/scaling
sequence or the primary short-NUTS subset. Duplicate cell IDs are rejected;
mixed collections are retained as requiring attention.

This function runs no process or MCMC, applies no resource or scientific
threshold, and never advances automatically to another cell. Peak RSS remains
whole-worker memory, including startup and compilation, rather than sampler-
only memory.
"""
function mgmfrm_validation_isolated_resource_review(results)
    return _mgmfrm_validation_isolated_resource_review(results)
end
