# Process-isolated execution for one bounded MGMFRM resource cell.

const _MGMFRM_VALIDATION_ISOLATED_RESOURCE_PROBE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_validation_isolated_resource_probe.v1"
const _MGMFRM_VALIDATION_ISOLATED_WORKER_RECEIPT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_validation_isolated_worker_receipt.v1"

function _mgmfrm_validation_isolated_resource_probe_policy()
    return (;
        default_timeout_seconds = 300.0,
        maximum_timeout_seconds = 900.0,
        cell_execution = :exactly_one,
        accepted_cell_collections = (
            :stress_default_and_scaled,
            :primary_resource_short_nuts_subset,
        ),
        parent_memory_preflight_required = true,
        child_memory_preflight_required = true,
        child_stdout = :single_json_receipt,
        child_stderr = :captured_diagnostic_text,
        worker_threads = 1,
        project_resolution = :active_project_at_invocation,
        process_peak_rss_scope =
            :dedicated_worker_including_startup_compilation_and_probe,
        process_peak_rss_attributable_to_sampler_only = false,
        scientific_execution_authorized = false,
    )
end

function _mgmfrm_validation_isolated_resource_cell(cell_id::Symbol)
    if cell_id === :default_sparse_short_nuts
        source = only(
            _mgmfrm_validation_default_short_nuts_resource_probe_plan())
        return merge(source, (;
            attempt_id = cell_id,
            resource_sequence = 0,
            resource_role = :default_sparse_short_nuts_baseline,
        ))
    end
    scaled = mgmfrm_validation_scaled_resource_plan()
    index = findfirst(row -> row.attempt_id === cell_id, scaled.rows)
    index === nothing || return scaled.rows[index]
    primary = mgmfrm_validation_primary_resource_plan()
    primary_index = findfirst(
        row -> row.cell_id === cell_id,
        primary.rows,
    )
    primary_index === nothing && throw(ArgumentError(
        "unknown isolated resource cell :$cell_id",
    ))
    return primary.rows[primary_index]
end

function _mgmfrm_validation_isolated_resource_collection(cell)
    cell.object === :mgmfrm_validation_primary_grid_candidate &&
        return :primary_resource_short_nuts_subset
    cell.object === :mgmfrm_response_stress_plan_row &&
        return :stress_default_and_scaled
    throw(ArgumentError("unsupported isolated resource cell object"))
end

function _mgmfrm_validation_isolated_resource_command(
        cell_id::Symbol,
        minimum_free_memory_bytes::Int,
        maximum_observations_per_cell::Int,
        truth_scale::Float64)
    project_file = Base.active_project()
    project_file === nothing && throw(ArgumentError(
        "an active Julia project is required for isolated resource probing",
    ))
    code = "using BayesianMGMFRM; print(" *
        "BayesianMGMFRM._mgmfrm_validation_isolated_resource_worker_json(" *
        repr(cell_id) * ", " * string(minimum_free_memory_bytes) * ", " *
        string(maximum_observations_per_cell) * ", " *
        repr(truth_scale) * "))"
    return `$(Base.julia_cmd()) --startup-file=no --threads=1 \
        --project=$(dirname(project_file)) -e $code`
end

function _mgmfrm_validation_isolated_worker_receipt(
        cell_id::Symbol,
        result)
    runtime = _mgmfrm_validation_resource_probe_runtime()
    attempt = isempty(result.fit_attempt_rows) ? nothing :
        only(result.fit_attempt_rows)
    measurement = ismissing(result.measurement) ? nothing : result.measurement
    error_type = hasproperty(result, :error_type) ? result.error_type :
        attempt === nothing ? missing : attempt.error_type
    error_message = hasproperty(result, :error_message) ?
        result.error_message :
        attempt === nothing ? missing : attempt.error_message
    return (;
        schema = _MGMFRM_VALIDATION_ISOLATED_WORKER_RECEIPT_SCHEMA,
        object = :mgmfrm_validation_isolated_worker_receipt,
        cell_id,
        status = result.status,
        execution_started = result.execution_started,
        mcmc_execution_state = result.mcmc_execution_state,
        mcmc_executed = result.mcmc_executed,
        terminal_status = attempt === nothing ? missing :
            attempt.terminal_status,
        n_completed = result.summary.n_completed,
        denominator_preserved = result.summary.denominator_preserved,
        free_memory_bytes_observed =
            result.preflight.free_memory_bytes_observed,
        available_memory_bytes_observed =
            result.preflight.available_memory_bytes_observed,
        raw_free_memory_bytes_observed =
            result.preflight.raw_free_memory_bytes_observed,
        memory_availability_basis =
            result.preflight.memory_availability_basis,
        memory_pressure_free_percent =
            result.preflight.memory_pressure_free_percent,
        memory_pressure_preflight_passed =
            result.preflight.memory_pressure_preflight_passed,
        memory_observation_status =
            result.preflight.memory_observation_status,
        minimum_free_memory_bytes_required =
            result.preflight.minimum_free_memory_bytes_required,
        memory_preflight_passed =
            result.preflight.memory_preflight_passed,
        maximum_observations_per_cell =
            result.preflight.maximum_observations_per_cell,
        workload_preflight_passed =
            result.preflight.workload_preflight_passed,
        elapsed_seconds = measurement === nothing ? missing :
            measurement.elapsed_seconds,
        cumulative_allocated_bytes = measurement === nothing ? missing :
            measurement.allocated_bytes,
        endpoint_free_memory_bytes = measurement === nothing ? missing :
            measurement.free_memory_bytes_after,
        endpoint_available_memory_bytes = measurement === nothing ? missing :
            measurement.available_memory_bytes_after,
        julia_version = runtime.julia_version,
        os = runtime.os,
        arch = runtime.arch,
        n_threads = runtime.n_threads,
        cpu_threads = runtime.cpu_threads,
        total_memory_bytes = runtime.total_memory_bytes,
        process_peak_rss_bytes = Int64(Sys.maxrss()),
        process_peak_rss_scope =
            :dedicated_worker_including_startup_compilation_and_probe,
        process_peak_rss_attributable_to_worker = true,
        process_peak_rss_attributable_to_sampler_only = false,
        error_type,
        error_message,
        convergence_assessed = false,
        recovery_evidence_available = false,
        scientific_execution_authorized = false,
        final_resource_policy_frozen = false,
        claim_scope = :isolated_process_operational_metadata_only,
    )
end

function _mgmfrm_validation_isolated_resource_worker_json(
        cell_id::Symbol,
        minimum_free_memory_bytes::Integer,
        maximum_observations_per_cell::Integer,
        truth_scale::Real)
    cell = _mgmfrm_validation_isolated_resource_cell(cell_id)
    result = mgmfrm_validation_short_nuts_resource_probe(
        cell;
        execute_measurement = true,
        minimum_free_memory_bytes,
        maximum_observations_per_cell,
        truth_scale,
    )
    receipt = _mgmfrm_validation_isolated_worker_receipt(cell_id, result)
    return String(JSON3.write(receipt))
end

function _mgmfrm_validation_launch_isolated_command(
        command::Cmd,
        timeout_seconds::Float64)
    stdout_pipe = Pipe()
    stderr_pipe = Pipe()
    started = time_ns()
    process = try
        run(pipeline(
            command;
            stdout = stdout_pipe,
            stderr = stderr_pipe,
        ); wait = false)
    catch err
        close(stdout_pipe)
        close(stderr_pipe)
        _mgmfrm_stress_fatal_exception(err) && rethrow()
        return (;
            started = false,
            timed_out = false,
            exit_code = missing,
            elapsed_seconds = (time_ns() - started) / 1.0e9,
            stdout = "",
            stderr = "",
            error_type = string(typeof(err)),
            error_message = sprint(showerror, err),
            error = err,
        )
    end
    close(stdout_pipe.in)
    close(stderr_pipe.in)
    stdout_reader = @async read(stdout_pipe, String)
    stderr_reader = @async read(stderr_pipe, String)
    wait_state = timedwait(
        () -> process_exited(process),
        timeout_seconds;
        pollint = 0.05,
    )
    timed_out = wait_state === :timed_out
    if timed_out && !process_exited(process)
        kill(process)
    end
    wait(process)
    return (;
        started = true,
        timed_out,
        exit_code = process.exitcode,
        elapsed_seconds = (time_ns() - started) / 1.0e9,
        stdout = fetch(stdout_reader),
        stderr = fetch(stderr_reader),
        error_type = missing,
        error_message = missing,
        error = missing,
    )
end

function _mgmfrm_validation_isolated_receipt(stdout::AbstractString,
        cell_id::Symbol)
    receipt = JSON3.read(stdout)
    hasproperty(receipt, :schema) &&
        String(receipt.schema) ==
            _MGMFRM_VALIDATION_ISOLATED_WORKER_RECEIPT_SCHEMA ||
        throw(ArgumentError("isolated worker receipt has the wrong schema"))
    hasproperty(receipt, :cell_id) &&
        Symbol(receipt.cell_id) === cell_id || throw(ArgumentError(
        "isolated worker receipt has the wrong cell_id",
    ))
    hasproperty(receipt, :scientific_execution_authorized) &&
        receipt.scientific_execution_authorized === false ||
        throw(ArgumentError(
            "isolated worker receipt changed the scientific guard",
        ))
    hasproperty(receipt, :final_resource_policy_frozen) &&
        receipt.final_resource_policy_frozen === false ||
        throw(ArgumentError(
            "isolated worker receipt changed the resource-policy guard",
        ))
    hasproperty(receipt, :object) &&
        Symbol(receipt.object) ===
            :mgmfrm_validation_isolated_worker_receipt ||
        throw(ArgumentError("isolated worker receipt has the wrong object"))
    hasproperty(receipt, :status) || throw(ArgumentError(
        "isolated worker receipt has no child status",
    ))
    hasproperty(receipt, :mcmc_executed) || throw(ArgumentError(
        "isolated worker receipt has no MCMC execution state",
    ))
    hasproperty(receipt, :n_completed) &&
        receipt.n_completed isa Integer && 0 <= receipt.n_completed <= 1 ||
        throw(ArgumentError(
            "isolated worker receipt has invalid completion count",
        ))
    hasproperty(receipt, :denominator_preserved) &&
        receipt.denominator_preserved isa Bool || throw(ArgumentError(
        "isolated worker receipt has invalid denominator state",
    ))
    hasproperty(receipt, :free_memory_bytes_observed) &&
        receipt.free_memory_bytes_observed isa Integer &&
        receipt.free_memory_bytes_observed >= 0 || throw(ArgumentError(
            "isolated worker receipt has invalid observed free memory",
    ))
    hasproperty(receipt, :available_memory_bytes_observed) &&
        receipt.available_memory_bytes_observed isa Integer &&
        receipt.available_memory_bytes_observed >= 0 || throw(ArgumentError(
            "isolated worker receipt has invalid observed available memory",
        ))
    hasproperty(receipt, :raw_free_memory_bytes_observed) &&
        receipt.raw_free_memory_bytes_observed isa Integer &&
        receipt.raw_free_memory_bytes_observed >= 0 || throw(ArgumentError(
            "isolated worker receipt has invalid observed raw free memory",
        ))
    receipt.free_memory_bytes_observed ==
        receipt.raw_free_memory_bytes_observed || throw(ArgumentError(
            "isolated worker receipt has inconsistent raw free memory",
        ))
    hasproperty(receipt, :memory_availability_basis) || throw(ArgumentError(
        "isolated worker receipt has no memory-availability basis",
    ))
    hasproperty(receipt, :memory_pressure_preflight_passed) &&
        receipt.memory_pressure_preflight_passed isa Bool ||
        throw(ArgumentError(
            "isolated worker receipt has invalid memory-pressure state",
        ))
    hasproperty(receipt, :minimum_free_memory_bytes_required) &&
        receipt.minimum_free_memory_bytes_required isa Integer &&
        receipt.minimum_free_memory_bytes_required >= 0 ||
        throw(ArgumentError(
            "isolated worker receipt has invalid required free memory",
        ))
    hasproperty(receipt, :memory_preflight_passed) &&
        receipt.memory_preflight_passed isa Bool || throw(ArgumentError(
        "isolated worker receipt has invalid memory-preflight state",
    ))
    receipt.memory_preflight_passed ==
        (receipt.available_memory_bytes_observed >=
            receipt.minimum_free_memory_bytes_required &&
        receipt.memory_pressure_preflight_passed) ||
        throw(ArgumentError(
            "isolated worker receipt has inconsistent memory preflight",
        ))
    hasproperty(receipt, :process_peak_rss_bytes) &&
        receipt.process_peak_rss_bytes isa Integer &&
        receipt.process_peak_rss_bytes >= 0 || throw(ArgumentError(
        "isolated worker receipt has invalid process peak RSS",
    ))
    hasproperty(receipt, :process_peak_rss_attributable_to_worker) &&
        receipt.process_peak_rss_attributable_to_worker === true ||
        throw(ArgumentError(
            "isolated worker receipt changed the worker RSS attribution",
        ))
    return receipt
end

function _mgmfrm_validation_isolated_resource_probe(
        cell_id;
        execute_measurement::Bool,
        timeout_seconds::Real,
        minimum_free_memory_bytes::Integer,
        maximum_observations_per_cell::Integer,
        truth_scale::Real,
        launcher = _mgmfrm_validation_launch_isolated_command,
        parent_free_memory_provider =
            _mgmfrm_validation_default_memory_observation)
    checked_cell_id = Symbol(cell_id)
    cell = _mgmfrm_validation_isolated_resource_cell(checked_cell_id)
    policy = _mgmfrm_validation_isolated_resource_probe_policy()
    isfinite(timeout_seconds) && 0 < timeout_seconds <=
        policy.maximum_timeout_seconds || throw(ArgumentError(
        "timeout_seconds must be positive and no greater than " *
        "$(policy.maximum_timeout_seconds)",
    ))
    short_plan = _mgmfrm_validation_short_nuts_resource_probe(
        (cell,);
        execute_measurement = false,
        minimum_free_memory_bytes,
        maximum_observations_per_cell,
        truth_scale,
        free_memory_provider = parent_free_memory_provider,
    )
    command = _mgmfrm_validation_isolated_resource_command(
        checked_cell_id,
        Int(minimum_free_memory_bytes),
        Int(maximum_observations_per_cell),
        Float64(truth_scale),
    )
    base = (;
        schema = _MGMFRM_VALIDATION_ISOLATED_RESOURCE_PROBE_SCHEMA,
        object = :mgmfrm_validation_isolated_resource_probe,
        cell_id = checked_cell_id,
        cell,
        resource_collection =
            _mgmfrm_validation_isolated_resource_collection(cell),
        policy,
        command,
        timeout_seconds = Float64(timeout_seconds),
        parent_preflight = short_plan.preflight,
    )
    if !execute_measurement ||
            !short_plan.preflight.memory_preflight_passed
        return merge(base, (;
            status = !execute_measurement ?
                :isolated_resource_probe_planned_not_executed :
                :isolated_resource_probe_parent_memory_rejected,
            execute_measurement,
            worker_process_started = false,
            timed_out = false,
            exit_code = missing,
            child_receipt = missing,
            worker_elapsed_seconds = missing,
            stdout = "",
            stderr = "",
            blockers = execute_measurement ?
                (:unsafe_parent_memory_preflight,) :
                (:explicit_execution_not_requested,),
            mcmc_executed = false,
            scientific_execution_authorized = false,
            final_resource_policy_frozen = false,
            claim_scope = :isolated_process_plan_not_validation_evidence,
        ))
    end

    launch = try
        launcher(command, Float64(timeout_seconds))
    catch err
        _mgmfrm_stress_fatal_exception(err) && rethrow()
        (;
            started = false,
            timed_out = false,
            exit_code = missing,
            elapsed_seconds = missing,
            stdout = "",
            stderr = "",
            error_type = string(typeof(err)),
            error_message = sprint(showerror, err),
            error = err,
        )
    end
    if !launch.started || launch.timed_out || launch.exit_code != 0
        return merge(base, (;
            status = !launch.started ?
                :isolated_resource_probe_launch_failed :
                launch.timed_out ?
                    :isolated_resource_probe_timed_out :
                    :isolated_resource_probe_child_failed,
            execute_measurement = true,
            worker_process_started = launch.started,
            timed_out = launch.timed_out,
            exit_code = launch.exit_code,
            child_receipt = missing,
            worker_elapsed_seconds = launch.elapsed_seconds,
            stdout = launch.stdout,
            stderr = launch.stderr,
            blockers = (!launch.started ? :worker_launch_failed :
                launch.timed_out ? :worker_wall_time_exceeded :
                :worker_nonzero_exit,),
            error_type = launch.error_type,
            error_message = launch.error_message,
            error = launch.error,
            mcmc_executed = launch.started ? missing : false,
            scientific_execution_authorized = false,
            final_resource_policy_frozen = false,
            claim_scope = :failed_isolated_operational_probe,
        ))
    end

    receipt = try
        _mgmfrm_validation_isolated_receipt(
            launch.stdout, checked_cell_id)
    catch err
        _mgmfrm_stress_fatal_exception(err) && rethrow()
        err
    end
    if receipt isa Exception
        return merge(base, (;
            status = :isolated_resource_probe_receipt_invalid,
            execute_measurement = true,
            worker_process_started = true,
            timed_out = false,
            exit_code = launch.exit_code,
            child_receipt = missing,
            worker_elapsed_seconds = launch.elapsed_seconds,
            stdout = launch.stdout,
            stderr = launch.stderr,
            blockers = (:invalid_worker_receipt,),
            error_type = string(typeof(receipt)),
            error_message = sprint(showerror, receipt),
            error = receipt,
            mcmc_executed = missing,
            scientific_execution_authorized = false,
            final_resource_policy_frozen = false,
            claim_scope = :invalid_isolated_operational_receipt,
        ))
    end
    child_probe_completed = receipt.n_completed == 1
    review_blocker = cell.object ===
        :mgmfrm_validation_primary_grid_candidate ?
        :primary_resource_review_pending :
        :scaled_resource_review_pending
    return merge(base, (;
        status = :isolated_resource_probe_receipt_recorded,
        execute_measurement = true,
        worker_process_started = true,
        timed_out = false,
        exit_code = launch.exit_code,
        child_receipt = receipt,
        worker_elapsed_seconds = launch.elapsed_seconds,
        stdout = launch.stdout,
        stderr = launch.stderr,
        child_probe_status = Symbol(receipt.status),
        child_probe_completed,
        blockers = child_probe_completed ?
            (review_blocker,) :
            (:child_probe_not_completed,),
        error_type = missing,
        error_message = missing,
        error = missing,
        mcmc_executed = receipt.mcmc_executed,
        scientific_execution_authorized = false,
        final_resource_policy_frozen = false,
        claim_scope = :isolated_process_operational_metadata_only,
    ))
end

"""
    mgmfrm_validation_isolated_resource_probe(
        cell_id = :default_sparse_short_nuts;
        execute_measurement = false, timeout_seconds = 300,
        minimum_free_memory_bytes = 2 * 1024^3,
        maximum_observations_per_cell = 1_000, truth_scale = 0.15)

Plan or explicitly launch one stress/scaling or primary-grid short-NUTS
resource cell in a dedicated Julia process. Parent and child memory preflights
run before MCMC, and the parent
terminates a worker that exceeds the wall-time bound. The child returns one
small JSON receipt through stdout; stderr is retained separately.

Primary rows are selected by the cell identifiers returned from
[`mgmfrm_validation_primary_resource_plan`](@ref). Only rows inside the current
short-NUTS workload bound can execute; larger gradient-only rows fail before a
worker is started.

The recorded peak RSS belongs to the dedicated worker process as a whole,
including startup, package loading, compilation, generation, sampling, and
diagnostics. It is not sampler-only peak memory, and the result cannot
establish convergence, recovery, performance superiority, or scientific
thresholds.
"""
function mgmfrm_validation_isolated_resource_probe(
        cell_id = :default_sparse_short_nuts;
        execute_measurement::Bool = false,
        timeout_seconds::Real = 300.0,
        minimum_free_memory_bytes::Integer = 2 * 1024^3,
        maximum_observations_per_cell::Integer = 1_000,
        truth_scale::Real = 0.15)
    return _mgmfrm_validation_isolated_resource_probe(
        cell_id;
        execute_measurement,
        timeout_seconds,
        minimum_free_memory_bytes,
        maximum_observations_per_cell,
        truth_scale,
    )
end
