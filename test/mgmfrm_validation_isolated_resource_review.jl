using Test
using BayesianMGMFRM

function _isolated_review_receipt_json(
        cell_id;
        n_completed = 1,
        mcmc_executed = true,
        memory_preflight_passed = true,
        free_memory_bytes_observed = Int64(4 * 1024^3),
        status =
            :short_nuts_resource_probe_complete_operational_metadata_only)
    return String(BayesianMGMFRM.JSON3.write((;
        schema =
            "bayesianmgmfrm.mgmfrm_validation_isolated_worker_receipt.v1",
        object = :mgmfrm_validation_isolated_worker_receipt,
        cell_id,
        status,
        mcmc_executed,
        n_completed,
        denominator_preserved = true,
        free_memory_bytes_observed,
        available_memory_bytes_observed = free_memory_bytes_observed,
        raw_free_memory_bytes_observed = free_memory_bytes_observed,
        memory_availability_basis = :injected_available_memory_bytes,
        memory_pressure_free_percent = nothing,
        memory_pressure_preflight_passed = true,
        minimum_free_memory_bytes_required = Int64(2 * 1024^3),
        memory_preflight_passed,
        process_peak_rss_bytes = 456_789,
        process_peak_rss_attributable_to_worker = true,
        julia_version = string(VERSION),
        os = string(Sys.KERNEL),
        arch = string(Sys.ARCH),
        n_threads = 1,
        scientific_execution_authorized = false,
        final_resource_policy_frozen = false,
    )))
end

function _isolated_review_result(cell_id;
        n_completed = 1,
        mcmc_executed = true,
        memory_preflight_passed = true,
        free_memory_bytes_observed = Int64(4 * 1024^3),
        status =
            :short_nuts_resource_probe_complete_operational_metadata_only)
    cell = BayesianMGMFRM._mgmfrm_validation_isolated_resource_cell(cell_id)
    maximum_observations = max(
        1_000,
        BayesianMGMFRM._mgmfrm_validation_probe_expected_observations(cell),
    )
    launcher = (command, timeout) -> (;
        started = true,
        timed_out = false,
        exit_code = 0,
        elapsed_seconds = 0.25,
        stdout = _isolated_review_receipt_json(
            cell_id;
            n_completed,
            mcmc_executed,
            memory_preflight_passed,
            free_memory_bytes_observed,
            status,
        ),
        stderr = "",
        error_type = missing,
        error_message = missing,
        error = missing,
    )
    return BayesianMGMFRM._mgmfrm_validation_isolated_resource_probe(
        cell_id;
        execute_measurement = true,
        timeout_seconds = 30.0,
        minimum_free_memory_bytes = 2 * 1024^3,
        maximum_observations_per_cell = maximum_observations,
        truth_scale = 0.15,
        launcher,
        parent_free_memory_provider = () -> Int64(4 * 1024^3),
    )
end

@testset "MGMFRM isolated resource review" begin
    empty_review = mgmfrm_validation_isolated_resource_review(())
    @test empty_review.schema ==
        "bayesianmgmfrm.mgmfrm_validation_isolated_resource_review.v1"
    @test empty_review.object ===
        :mgmfrm_validation_isolated_resource_review
    @test empty_review.status === :no_isolated_resource_results
    @test isempty(empty_review.rows)
    @test empty_review.summary.n_submitted == 0
    @test empty_review.summary.denominator_preserved
    @test empty_review.summary.denominator_scope === :submitted_results
    @test !empty_review.summary.full_resource_sequence_complete
    @test empty_review.next_gate ===
        :run_isolated_default_short_nuts_resource_probe

    planned = mgmfrm_validation_isolated_resource_probe()
    planned_review = mgmfrm_validation_isolated_resource_review((planned,))
    @test planned_review.status ===
        :isolated_resource_results_require_attention
    @test planned_review.summary.n_worker_processes_started == 0
    @test planned_review.summary.n_receipts_recorded == 0
    @test planned_review.summary.n_child_completed == 0
    @test planned_review.summary.n_mcmc_executed == 0
    @test planned_review.summary.n_attention_required == 1
    @test only(planned_review.rows).stop_before_next_cell
    @test !only(planned_review.rows).receipt_recorded

    default_result = _isolated_review_result(
        :default_sparse_short_nuts)
    scaled_result = _isolated_review_result(
        :scaled_resource_01_dense_small)
    review = mgmfrm_validation_isolated_resource_review(
        [default_result, scaled_result],
    )
    @test review.status ===
        :isolated_resource_receipts_ready_for_manual_review
    @test review.submitted_order == (
        :default_sparse_short_nuts,
        :scaled_resource_01_dense_small,
    )
    @test review.submitted_order_matches_plan
    @test review.summary.n_submitted == 2
    @test review.summary.n_worker_processes_started == 2
    @test review.summary.n_receipts_recorded == 2
    @test review.summary.n_child_completed == 2
    @test review.summary.n_mcmc_executed == 2
    @test review.summary.n_attention_required == 0
    @test review.summary.denominator_scope === :submitted_results
    @test !review.summary.full_resource_sequence_complete
    @test !review.automatic_progression_allowed
    @test review.manual_review_required
    @test !review.resource_thresholds_applied
    @test !review.final_resource_policy_frozen
    @test !review.convergence_assessed
    @test !review.scientific_execution_authorized
    @test review.scientific_decision === :not_applied
    @test review.next_gate ===
        :manually_review_worker_metrics_before_next_cell_or_policy

    row = first(review.rows)
    @test row.parent_memory_preflight_passed
    @test row.child_memory_preflight_passed
    @test row.child_free_memory_bytes_observed == 4 * 1024^3
    @test row.child_available_memory_bytes_observed == 4 * 1024^3
    @test row.child_raw_free_memory_bytes_observed == 4 * 1024^3
    @test row.child_memory_availability_basis ===
        :injected_available_memory_bytes
    @test row.child_memory_pressure_preflight_passed
    @test row.process_peak_rss_bytes == 456_789
    @test row.worker_elapsed_seconds == 0.25
    @test row.julia_version == string(VERSION)
    @test row.n_threads == 1
    @test row.child_completed
    @test row.child_denominator_preserved
    @test !row.stop_before_next_cell
    @test row.manual_review_required
    @test !row.resource_threshold_applied
    @test row.scientific_decision === :not_applied

    full_order = (
        :default_sparse_short_nuts,
        mgmfrm_validation_scaled_resource_plan().execution_order...,
    )
    full_review = mgmfrm_validation_isolated_resource_review(Tuple(
        _isolated_review_result(cell_id) for cell_id in full_order
    ))
    @test full_review.submitted_order == full_order
    @test full_review.submitted_order_matches_plan
    @test full_review.summary.full_resource_sequence_complete
    @test full_review.summary.n_submitted == 5
    @test full_review.summary.n_child_completed == 5

    reversed = mgmfrm_validation_isolated_resource_review(
        (scaled_result, default_result),
    )
    @test !reversed.submitted_order_matches_plan
    @test reversed.status === :isolated_resource_results_require_attention
    @test reversed.next_gate ===
        :stop_and_review_incomplete_or_out_of_order_results
    scaled_only = mgmfrm_validation_isolated_resource_review((scaled_result,))
    @test !scaled_only.submitted_order_matches_plan
    @test scaled_only.status ===
        :isolated_resource_results_require_attention

    child_rejected = _isolated_review_result(
        :default_sparse_short_nuts;
        n_completed = 0,
        mcmc_executed = false,
        memory_preflight_passed = false,
        free_memory_bytes_observed = Int64(512 * 1024^2),
        status = :short_nuts_resource_probe_memory_preflight_rejected,
    )
    rejected_review = mgmfrm_validation_isolated_resource_review(
        (child_rejected,),
    )
    rejected_row = only(rejected_review.rows)
    @test !rejected_row.child_memory_preflight_passed
    @test !rejected_row.child_completed
    @test !rejected_row.mcmc_executed
    @test rejected_row.stop_before_next_cell
    @test rejected_review.summary.n_attention_required == 1

    @test_throws ArgumentError mgmfrm_validation_isolated_resource_review(
        planned)
    @test_throws ArgumentError mgmfrm_validation_isolated_resource_review(
        (planned, planned))
    @test_throws ArgumentError mgmfrm_validation_isolated_resource_review((
        merge(planned, (; object = :wrong_object)),
    ))
    @test_throws ArgumentError mgmfrm_validation_isolated_resource_review((
        merge(planned, (;
            cell = merge(planned.cell, (; attempt_id = :wrong_cell)),
        )),
    ))
end
