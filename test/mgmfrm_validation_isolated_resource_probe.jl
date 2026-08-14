using Test
using BayesianMGMFRM

function _isolated_probe_launch_result(;
        started = true,
        timed_out = false,
        exit_code = 0,
        stdout = "",
        stderr = "",
        error_type = missing,
        error_message = missing,
        error = missing)
    return (;
        started,
        timed_out,
        exit_code,
        elapsed_seconds = 0.1,
        stdout,
        stderr,
        error_type,
        error_message,
        error,
    )
end

function _isolated_probe_receipt_json(
        cell_id = :default_sparse_short_nuts;
        mcmc_executed = true,
        n_completed = 1,
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
        minimum_free_memory_bytes_required = Int64(2 * 1024^3),
        memory_preflight_passed,
        process_peak_rss_bytes = 123_456,
        process_peak_rss_attributable_to_worker = true,
        scientific_execution_authorized = false,
        final_resource_policy_frozen = false,
    )))
end

function _isolated_probe_internal(;
        launcher,
        free_memory_bytes = Int64(4 * 1024^3),
        cell_id = :default_sparse_short_nuts)
    return BayesianMGMFRM._mgmfrm_validation_isolated_resource_probe(
        cell_id;
        execute_measurement = true,
        timeout_seconds = 30.0,
        minimum_free_memory_bytes = 2 * 1024^3,
        maximum_observations_per_cell = 1_000,
        truth_scale = 0.15,
        launcher,
        parent_free_memory_provider = () -> free_memory_bytes,
    )
end

@testset "MGMFRM process-isolated resource probe" begin
    planned = mgmfrm_validation_isolated_resource_probe()
    @test planned.schema ==
        "bayesianmgmfrm.mgmfrm_validation_isolated_resource_probe.v1"
    @test planned.object === :mgmfrm_validation_isolated_resource_probe
    @test planned.status ===
        :isolated_resource_probe_planned_not_executed
    @test !planned.execute_measurement
    @test !planned.worker_process_started
    @test ismissing(planned.worker_elapsed_seconds)
    @test !planned.mcmc_executed
    @test planned.cell_id === :default_sparse_short_nuts
    @test BayesianMGMFRM._mgmfrm_validation_probe_expected_observations(
        planned.cell) == 96
    @test planned.command isa Cmd
    @test :explicit_execution_not_requested in planned.blockers
    @test !planned.scientific_execution_authorized
    @test !planned.final_resource_policy_frozen

    policy = planned.policy
    @test policy.cell_execution === :exactly_one
    @test policy.parent_memory_preflight_required
    @test policy.child_memory_preflight_required
    @test policy.child_stdout === :single_json_receipt
    @test policy.worker_threads == 1
    @test policy.project_resolution === :active_project_at_invocation
    @test policy.process_peak_rss_scope ===
        :dedicated_worker_including_startup_compilation_and_probe
    @test !policy.process_peak_rss_attributable_to_sampler_only

    command_text = join(planned.command.exec, " ")
    @test occursin("--startup-file=no", command_text)
    @test occursin("--threads=1", command_text)
    @test occursin("--project=", command_text)
    @test occursin(
        "_mgmfrm_validation_isolated_resource_worker_json",
        command_text,
    )

    @test_throws ArgumentError mgmfrm_validation_isolated_resource_probe(
        :unknown_cell)
    @test_throws ArgumentError mgmfrm_validation_isolated_resource_probe(
        timeout_seconds = 0)
    @test_throws ArgumentError mgmfrm_validation_isolated_resource_probe(
        timeout_seconds = 901)
    @test_throws ArgumentError mgmfrm_validation_isolated_resource_probe(
        minimum_free_memory_bytes = 1024^3 - 1)
    @test_throws ArgumentError mgmfrm_validation_isolated_resource_probe(
        maximum_observations_per_cell = 95)
    @test_throws ArgumentError mgmfrm_validation_isolated_resource_probe(
        truth_scale = 0)

    scaled = mgmfrm_validation_scaled_resource_plan()
    for (row, expected_observations) in
            zip(scaled.rows, scaled.expected_observations)
        selected = mgmfrm_validation_isolated_resource_probe(
            row.attempt_id;
            maximum_observations_per_cell =
                max(1_000, expected_observations),
        )
        @test selected.cell.attempt_id === row.attempt_id
        @test BayesianMGMFRM.
            _mgmfrm_validation_probe_expected_observations(selected.cell) ==
            expected_observations
        @test !selected.worker_process_started
    end

    launcher_calls = Ref(0)
    forbidden_launcher = (command, timeout) -> begin
        launcher_calls[] += 1
        error("launcher must not be called")
    end
    rejected = _isolated_probe_internal(
        launcher = forbidden_launcher,
        free_memory_bytes = Int64(512 * 1024^2),
    )
    @test rejected.status ===
        :isolated_resource_probe_parent_memory_rejected
    @test !rejected.worker_process_started
    @test !rejected.mcmc_executed
    @test :insufficient_parent_free_memory in rejected.blockers
    @test launcher_calls[] == 0

    successful_launcher = (command, timeout) ->
        _isolated_probe_launch_result(
            stdout = _isolated_probe_receipt_json(),
        )
    completed = _isolated_probe_internal(launcher = successful_launcher)
    @test completed.status === :isolated_resource_probe_receipt_recorded
    @test completed.worker_process_started
    @test !completed.timed_out
    @test completed.exit_code == 0
    @test completed.worker_elapsed_seconds == 0.1
    @test completed.mcmc_executed
    @test completed.child_probe_completed
    @test completed.child_probe_status ===
        :short_nuts_resource_probe_complete_operational_metadata_only
    @test completed.child_receipt.cell_id ==
        "default_sparse_short_nuts"
    @test !completed.scientific_execution_authorized
    @test !completed.final_resource_policy_frozen

    child_rejected = _isolated_probe_internal(
        launcher = (command, timeout) ->
            _isolated_probe_launch_result(stdout =
                _isolated_probe_receipt_json(
                    mcmc_executed = false,
                    n_completed = 0,
                    status =
                        :short_nuts_resource_probe_memory_preflight_rejected,
                )),
    )
    @test child_rejected.status ===
        :isolated_resource_probe_receipt_recorded
    @test !child_rejected.child_probe_completed
    @test !child_rejected.mcmc_executed
    @test :child_probe_not_completed in child_rejected.blockers

    timed_out = _isolated_probe_internal(
        launcher = (command, timeout) ->
            _isolated_probe_launch_result(
                timed_out = true,
                exit_code = -15,
                stderr = "worker timed out",
            ),
    )
    @test timed_out.status === :isolated_resource_probe_timed_out
    @test timed_out.worker_process_started
    @test timed_out.timed_out
    @test :worker_wall_time_exceeded in timed_out.blockers

    launch_error = ErrorException("injected launch failure")
    launch_failed = _isolated_probe_internal(
        launcher = (command, timeout) ->
            _isolated_probe_launch_result(
                started = false,
                exit_code = missing,
                error_type = "ErrorException",
                error_message = "injected launch failure",
                error = launch_error,
            ),
    )
    @test launch_failed.status === :isolated_resource_probe_launch_failed
    @test !launch_failed.worker_process_started
    @test launch_failed.error === launch_error
    @test occursin("injected launch failure", launch_failed.error_message)

    thrown_launch = _isolated_probe_internal(
        launcher = (command, timeout) ->
            error("injected thrown launch failure"),
    )
    @test thrown_launch.status === :isolated_resource_probe_launch_failed
    @test thrown_launch.error isa ErrorException
    @test occursin("injected thrown launch failure",
        thrown_launch.error_message)

    child_failed = _isolated_probe_internal(
        launcher = (command, timeout) ->
            _isolated_probe_launch_result(
                exit_code = 1,
                stderr = "injected child failure",
            ),
    )
    @test child_failed.status === :isolated_resource_probe_child_failed
    @test child_failed.stderr == "injected child failure"
    @test :worker_nonzero_exit in child_failed.blockers

    invalid_receipt = _isolated_probe_internal(
        launcher = (command, timeout) ->
            _isolated_probe_launch_result(stdout = "not JSON"),
    )
    @test invalid_receipt.status ===
        :isolated_resource_probe_receipt_invalid
    @test invalid_receipt.error isa Exception
    @test :invalid_worker_receipt in invalid_receipt.blockers

    inconsistent_memory = _isolated_probe_internal(
        launcher = (command, timeout) ->
            _isolated_probe_launch_result(stdout =
                _isolated_probe_receipt_json(
                    memory_preflight_passed = false,
                )),
    )
    @test inconsistent_memory.status ===
        :isolated_resource_probe_receipt_invalid
    @test occursin("inconsistent memory preflight",
        inconsistent_memory.error_message)

    fake_short_result = (;
        status = :short_nuts_resource_probe_complete_operational_metadata_only,
        execution_started = true,
        mcmc_execution_state = :executed,
        mcmc_executed = true,
        fit_attempt_rows = ((;
            terminal_status = :completed,
            error_type = missing,
            error_message = missing,
        ),),
        summary = (;
            n_completed = 1,
            denominator_preserved = true,
        ),
        preflight = (;
            free_memory_bytes_observed = Int64(4 * 1024^3),
            minimum_free_memory_bytes_required = Int64(2 * 1024^3),
            memory_preflight_passed = true,
            maximum_observations_per_cell = 1_000,
            workload_preflight_passed = true,
        ),
        measurement = (;
            elapsed_seconds = 1.25,
            allocated_bytes = 4096,
            free_memory_bytes_after = Int64(3 * 1024^3),
        ),
    )
    worker_receipt =
        BayesianMGMFRM._mgmfrm_validation_isolated_worker_receipt(
            :default_sparse_short_nuts,
            fake_short_result,
        )
    @test worker_receipt.process_peak_rss_bytes >= 0
    @test worker_receipt.julia_version == string(VERSION)
    @test !isempty(worker_receipt.os)
    @test !isempty(worker_receipt.arch)
    @test worker_receipt.n_threads >= 1
    @test worker_receipt.process_peak_rss_attributable_to_worker
    @test !worker_receipt.process_peak_rss_attributable_to_sampler_only
    @test worker_receipt.elapsed_seconds == 1.25
    @test worker_receipt.cumulative_allocated_bytes == 4096
    @test worker_receipt.memory_preflight_passed
    @test worker_receipt.free_memory_bytes_observed == 4 * 1024^3
    @test worker_receipt.claim_scope ===
        :isolated_process_operational_metadata_only
    @test BayesianMGMFRM._mgmfrm_validation_isolated_receipt(
        String(BayesianMGMFRM.JSON3.write(worker_receipt)),
        :default_sparse_short_nuts,
    ).schema ==
        "bayesianmgmfrm.mgmfrm_validation_isolated_worker_receipt.v1"
end
