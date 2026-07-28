#!/usr/bin/env julia

module LocalDependenceCalibrationPilotJobWorker

using BayesianMGMFRM
using Dates
using JSON3
using Random
using SHA

module BatchContract

include(joinpath(@__DIR__, "run_local_dependence_calibration_pilot_batch.jl"))

end

const Batch = BatchContract

export LD1B1StageFailure,
    ld1b1_job_main,
    ld1b1_job_usage,
    ld1b1_parse_job_args,
    ld1b1_production_stages,
    ld1b1_run_stage_adapter,
    ld1b1_validate_job_invocation,
    ld1b1_worker_owns_control_receipts

const LD1B1_JOB_MODES = Set((:status, :execute, :bounded_smoke))
const LD1B1_NONTERMINAL_ARTIFACT_CODES = Set((
    :sampler_diagnostics_unavailable,
    :final_calibration_serialization_failed,
))
const LD1B1_LAUNCH_RECEIPT_TIMEOUT_SECONDS = 30.0
const LD1B1_LAUNCH_RECEIPT_POLL_SECONDS = 0.05
const LD1B1_SOURCE_DIRECTORY = "members"
const LD1B1_EVIDENCE_DIRECTORY = "evidence"
const LD1B1_WORKER_STAGING_DIRECTORY = ".job_worker_staging"

"""A stable failure code injected by a worker stage."""
struct LD1B1StageFailure <: Exception
    code::Symbol
end

Base.showerror(io::IO, error::LD1B1StageFailure) =
    print(io, "LD1b1 stage failure: ", error.code)

struct LD1B1NonterminalArtifactFailure <: Exception
    code::Symbol
    cause
end

function Base.showerror(io::IO, error::LD1B1NonterminalArtifactFailure)
    print(io, "LD1b1 nonterminal artifact failure: ", error.code)
    error.cause === nothing || print(
        io,
        " (",
        Batch.portable_error_message(error.cause),
        ")",
    )
end

ld1b1_worker_owns_control_receipts() = false

function ld1b1_job_usage()
    return """
    Execute or inspect exactly one canonical LD1b1 calibration-pilot job.

    The default mode is read-only status. Execution is impossible unless the
    controller supplies both --controller-readiness-authorized and a canonical
    --reservation-receipt. The worker validates reservation -> owner -> launch
    lineage before starting generation. It never publishes reservation, owner,
    launch, exit, retirement, or completed-attempt seal records.

    Usage:
      julia --project=. scripts/run_local_dependence_calibration_pilot_job.jl [options]

    Required identity options:
      --protocol PATH
      --job-id ID
      --row-index N
      --attempt N
      --attempt-role primary|remediation
      --output PATH
      --plan-id SHA256
      --protocol-plan-id SHA256
      --protocol-file-sha256 SHA256
      --protocol-content-hash SHA256
      --ordered-job-rows-sha256 SHA256
      --batch-runner-source-sha256 SHA256
      --local-json-source-sha256 SHA256
      --attempt-archive-source-sha256 SHA256
      --local-dependence-pilot-recovery-source-sha256 SHA256
      --local-dependence-pilot-calibration-semantics-source-sha256 SHA256
      --runner-source-sha256 SHA256
      --seed N
      --fit-seed N
      --draw-selection-seed N
      --posterior-predictive-seed N

    Execution-only options:
      --mode execute
      --controller-readiness-authorized
      --reservation-receipt PATH

    Verification-only bounded-smoke options:
      --mode bounded-smoke
      --attempt-role verification
      --reservation-receipt PATH
      --bounded-smoke-authorization PATH

    Remediation-only options:
      --retry-of 1
      --retry-reason TEXT
      --primary-result PATH

    There is no test mode, force option, seed override, sampler override, or
    worker-side receipt/seal publication option.
    """
end

const _LD1B1_VALUE_OPTIONS = Dict(
    "--mode" => :mode,
    "--protocol" => :protocol,
    "--job-id" => :job_id,
    "--row-index" => :row_index,
    "--attempt" => :attempt,
    "--attempt-role" => :attempt_role,
    "--output" => :output,
    "--plan-id" => :plan_id,
    "--protocol-plan-id" => :protocol_plan_id,
    "--protocol-file-sha256" => :protocol_file_sha256,
    "--protocol-content-hash" => :protocol_content_hash,
    "--ordered-job-rows-sha256" => :ordered_job_rows_sha256,
    "--batch-runner-source-sha256" => :batch_runner_source_sha256,
    "--local-json-source-sha256" => :local_json_source_sha256,
    "--attempt-archive-source-sha256" => :attempt_archive_source_sha256,
    "--local-dependence-pilot-recovery-source-sha256" =>
        :local_dependence_pilot_recovery_source_sha256,
    "--local-dependence-pilot-calibration-semantics-source-sha256" =>
        :local_dependence_pilot_calibration_semantics_source_sha256,
    "--runner-source-sha256" => :runner_source_sha256,
    "--seed" => :seed,
    "--fit-seed" => :fit_seed,
    "--draw-selection-seed" => :draw_selection_seed,
    "--posterior-predictive-seed" => :posterior_predictive_seed,
    "--reservation-receipt" => :reservation_receipt,
    "--bounded-smoke-authorization" => :bounded_smoke_authorization,
    "--retry-of" => :retry_of,
    "--retry-reason" => :retry_reason,
    "--primary-result" => :primary_result,
)

const _LD1B1_REQUIRED_JOB_FIELDS = (
    :protocol,
    :job_id,
    :row_index,
    :attempt,
    :attempt_role,
    :output,
    :plan_id,
    :protocol_plan_id,
    :protocol_file_sha256,
    :protocol_content_hash,
    :ordered_job_rows_sha256,
    :batch_runner_source_sha256,
    :local_json_source_sha256,
    :attempt_archive_source_sha256,
    :local_dependence_pilot_recovery_source_sha256,
    :local_dependence_pilot_calibration_semantics_source_sha256,
    :runner_source_sha256,
    :seed,
    :fit_seed,
    :draw_selection_seed,
    :posterior_predictive_seed,
)

function ld1b1_strict_integer(value::AbstractString, option::AbstractString)
    occursin(r"^(0|[1-9][0-9]*)$", value) ||
        error("$option requires a canonical nonnegative integer")
    return try
        parse(Int, value)
    catch
        error("$option is outside the supported integer range")
    end
end

function ld1b1_parse_job_args(args)
    values = Dict{Symbol,Any}(:mode => :status)
    seen = Set{Symbol}()
    controller_readiness_authorized = false
    help = false
    index = 1
    while index <= length(args)
        argument = String(args[index])
        if argument in ("-h", "--help")
            help && error("help option was supplied more than once")
            help = true
            index += 1
            continue
        elseif argument == "--controller-readiness-authorized"
            controller_readiness_authorized && error(
                "--controller-readiness-authorized was supplied more than once")
            controller_readiness_authorized = true
            index += 1
            continue
        end
        field = get(_LD1B1_VALUE_OPTIONS, argument, nothing)
        field === nothing && error("unknown argument: $argument")
        field in seen && error("$argument was supplied more than once")
        index < length(args) || error("$argument requires a value")
        raw = String(args[index + 1])
        startswith(raw, "--") && error("$argument requires a value")
        push!(seen, field)
        if field === :mode
            canonical = Symbol(replace(lowercase(strip(raw)), '-' => '_'))
            canonical in LD1B1_JOB_MODES || error(
                "--mode must be status, execute, or bounded-smoke")
            values[field] = canonical
        elseif field in (
                :row_index,
                :attempt,
                :seed,
                :fit_seed,
                :draw_selection_seed,
                :posterior_predictive_seed,
                :retry_of,
            )
            values[field] = ld1b1_strict_integer(raw, argument)
        elseif field === :attempt_role
            role = Symbol(replace(lowercase(strip(raw)), '-' => '_'))
            role in (:primary, :remediation, :verification) || error(
                "--attempt-role must be primary, remediation, or verification")
            values[field] = role
        elseif field in (
                :protocol,
                :output,
                :reservation_receipt,
                :bounded_smoke_authorization,
                :primary_result,
            )
            isempty(strip(raw)) && error("$argument must not be empty")
            values[field] = normpath(abspath(raw))
        else
            text = strip(raw)
            isempty(text) && error("$argument must not be empty")
            values[field] = text
        end
        index += 2
    end

    help && return (; help = true)
    missing_fields = Tuple(field for field in _LD1B1_REQUIRED_JOB_FIELDS
        if !haskey(values, field))
    isempty(missing_fields) || error(
        "missing required worker options: " * join(string.(missing_fields), ", "))

    mode = values[:mode]
    attempt = values[:attempt]
    role = values[:attempt_role]
    1 <= attempt <= 999 || error("--attempt must be in 1:999")
    values[:row_index] >= 1 || error("--row-index must be positive")
    all(values[field] >= 0 for field in (
        :seed,
        :fit_seed,
        :draw_selection_seed,
        :posterior_predictive_seed,
    )) || error("worker seeds must be nonnegative")

    if role === :verification
        mode === :bounded_smoke || error(
            "verification role is available only in bounded-smoke mode")
        attempt == 1 || error(
            "bounded-smoke verification requires --attempt 1")
        for field in (:retry_of, :retry_reason, :primary_result)
            haskey(values, field) && error(
                "bounded-smoke verification cannot use remediation options")
        end
    elseif role === :primary
        attempt == 1 || error("primary execution requires --attempt 1")
        for field in (:retry_of, :retry_reason, :primary_result)
            haskey(values, field) && error(
                "--$(replace(String(field), '_' => '-')) is remediation-only")
        end
    else
        attempt > 1 || error("remediation requires --attempt greater than 1")
        get(values, :retry_of, nothing) == 1 || error(
            "remediation requires --retry-of 1")
        for field in (:retry_reason, :primary_result)
            haskey(values, field) || error(
                "remediation requires --$(replace(String(field), '_' => '-'))")
        end
    end

    if mode === :execute
        controller_readiness_authorized || error(
            "execute mode requires --controller-readiness-authorized")
        haskey(values, :reservation_receipt) || error(
            "execute mode requires --reservation-receipt")
        haskey(values, :bounded_smoke_authorization) && error(
            "execute mode cannot use bounded-smoke authorization")
    elseif mode === :bounded_smoke
        controller_readiness_authorized && error(
            "bounded-smoke cannot use controller readiness authorization")
        role === :verification || error(
            "bounded-smoke requires --attempt-role verification")
        haskey(values, :reservation_receipt) || error(
            "bounded-smoke requires --reservation-receipt")
        haskey(values, :bounded_smoke_authorization) || error(
            "bounded-smoke requires --bounded-smoke-authorization")
    else
        controller_readiness_authorized && error(
            "controller execution authorization is unavailable in status mode")
        haskey(values, :bounded_smoke_authorization) && error(
            "bounded-smoke authorization is unavailable in status mode")
    end

    return (;
        help = false,
        mode,
        protocol = values[:protocol],
        job_id = values[:job_id],
        row_index = values[:row_index],
        attempt,
        attempt_role = role,
        output = values[:output],
        plan_id = values[:plan_id],
        protocol_plan_id = values[:protocol_plan_id],
        protocol_file_sha256 = values[:protocol_file_sha256],
        protocol_content_hash = values[:protocol_content_hash],
        ordered_job_rows_sha256 = values[:ordered_job_rows_sha256],
        batch_runner_source_sha256 = values[:batch_runner_source_sha256],
        local_json_source_sha256 = values[:local_json_source_sha256],
        attempt_archive_source_sha256 =
            values[:attempt_archive_source_sha256],
        local_dependence_pilot_recovery_source_sha256 = values[
            :local_dependence_pilot_recovery_source_sha256],
        local_dependence_pilot_calibration_semantics_source_sha256 = values[
            :local_dependence_pilot_calibration_semantics_source_sha256],
        runner_source_sha256 = values[:runner_source_sha256],
        seed = values[:seed],
        fit_seed = values[:fit_seed],
        draw_selection_seed = values[:draw_selection_seed],
        posterior_predictive_seed = values[:posterior_predictive_seed],
        reservation_receipt = get(values, :reservation_receipt, nothing),
        bounded_smoke_authorization =
            get(values, :bounded_smoke_authorization, nothing),
        retry_of = get(values, :retry_of, nothing),
        retry_reason = get(values, :retry_reason, nothing),
        primary_result = get(values, :primary_result, nothing),
        controller_readiness_authorized,
    )
end

function ld1b1_equal_identity(observed, expected, label::AbstractString)
    observed == expected || error("worker invocation identity mismatch: $label")
    return true
end

function ld1b1_validate_job_invocation(options;
        bounded_smoke_root::AbstractString =
            Batch.LD1B1_DEFAULT_BOUNDED_SMOKE_ROOT)
    runner_path = normpath(abspath(@__FILE__))
    isfile(runner_path) && !islink(runner_path) || error(
        "canonical single-job runner is not a regular file")
    runner_source_sha256 = Batch.ld1b1_file_sha256(runner_path)
    Batch.ld1b1_require_sha256(
        options.runner_source_sha256,
        "invoked runner source SHA-256",
    ) == runner_source_sha256 || error(
        "single-job runner changed after controller planning")

    output = normpath(options.output)
    basename(output) == "job_result.json" || error(
        "worker output must be named job_result.json")
    execution_root = Batch.ld1b1_result_execution_root(output)
    attempt_root = dirname(execution_root)
    checked = Batch.ld1b1_checked_protocol(
        options.protocol;
        job_runner_path = runner_path,
        attempt_root,
    )
    parent_identity = checked.identity
    specs = Batch.ld1b1_job_specs(checked)
    index = findfirst(job -> job.job_id == options.job_id, specs)
    index === nothing && error("worker job id is absent from the canonical plan")
    job = specs[index]
    job.row_index == options.row_index || error(
        "worker row index does not identify the requested job")

    smoke = options.mode === :bounded_smoke ?
        Batch.ld1b1_bounded_smoke_identity(parent_identity, job) : nothing
    identity = smoke === nothing ? parent_identity : smoke.identity
    execution_context = smoke === nothing ?
        Batch.ld1b1_execution_context(:pilot) :
        Batch.ld1b1_execution_context(:bounded_smoke)
    if smoke !== nothing
        job.row_index == Batch.LD1B1_BOUNDED_SMOKE_ROW_INDEX &&
            job.job_id == Batch.LD1B1_BOUNDED_SMOKE_JOB_ID || error(
            "bounded-smoke worker invocation is not the allowlisted row 5")
        normpath(execution_root) == normpath(
            Batch.ld1b1_bounded_smoke_execution_root(
                bounded_smoke_root, smoke.smoke_plan_id)) || error(
            "bounded-smoke worker execution root is not canonical")
    end

    expected_output = Batch.ld1b1_result_path(
        execution_root,
        job.job_id,
        options.attempt,
    )
    output == normpath(expected_output) || error(
        "worker output path does not match plan/job/attempt identity")
    basename(execution_root) == identity.plan_id || error(
        "worker execution root is not plan-scoped")

    for (observed, expected, label) in (
            (options.plan_id, identity.plan_id, "plan id"),
            (options.protocol_plan_id, identity.protocol_plan_id,
                "protocol plan id"),
            (options.protocol_file_sha256, identity.protocol_file_sha256,
                "protocol file SHA-256"),
            (options.protocol_content_hash, identity.protocol_content_hash,
                "protocol content hash"),
            (options.ordered_job_rows_sha256,
                identity.ordered_job_rows_sha256,
                "ordered job rows SHA-256"),
            (options.batch_runner_source_sha256,
                identity.execution_source_identity.batch_runner_source_sha256,
                "batch runner source SHA-256"),
            (options.local_json_source_sha256,
                identity.execution_source_identity.local_json_source_sha256,
                "local JSON source SHA-256"),
            (options.attempt_archive_source_sha256,
                identity.execution_source_identity.attempt_archive_source_sha256,
                "attempt archive source SHA-256"),
            (options.local_dependence_pilot_recovery_source_sha256,
                identity.execution_source_identity.
                    local_dependence_pilot_recovery_source_sha256,
                "recovery source SHA-256"),
            (options.local_dependence_pilot_calibration_semantics_source_sha256,
                identity.execution_source_identity.
                    local_dependence_pilot_calibration_semantics_source_sha256,
                "calibration semantics source SHA-256"),
            (options.runner_source_sha256,
                identity.execution_source_identity.job_runner_source_sha256,
                "job runner source SHA-256"),
            (options.seed, job.seed, "generation seed"),
            (options.fit_seed, job.fit_seed, "fit seed"),
            (options.draw_selection_seed, job.draw_selection_seed,
                "draw-selection seed"),
            (options.posterior_predictive_seed,
                job.posterior_predictive_seed,
                "posterior-predictive seed"),
        )
        ld1b1_equal_identity(observed, expected, label)
    end

    expected_role = Batch.ld1b1_attempt_identity(
        options.attempt, execution_context).role
    options.attempt_role === expected_role || error(
        "attempt role does not match attempt number")
    plan_row = checked.calibration_semantic_context.plan_rows[job.row_index]
    plan_row.row_index == job.row_index &&
        plan_row.scenario_index == job.scenario_index &&
        plan_row.scenario_id === job.scenario_id &&
        plan_row.replication == job.replication &&
        plan_row.seed == job.seed || error(
        "public plan row does not match compact job identity")

    primary_result_sha256 = nothing
    if options.attempt_role === :remediation
        canonical_primary = Batch.ld1b1_result_path(
            execution_root,
            job.job_id,
            1,
        )
        normpath(options.primary_result) == normpath(canonical_primary) || error(
            "remediation primary-result path is not canonical")
        Batch.ld1b1_validate_completed_attempt(
            canonical_primary,
            identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        primary_result_sha256 = Batch.ld1b1_file_sha256(canonical_primary)
    end

    attempt_dir = dirname(output)
    expected_relative_attempt_path = normpath(relpath(
        attempt_dir,
        execution_root,
    ))
    (expected_relative_attempt_path == "." ||
        startswith(expected_relative_attempt_path, "..")) && error(
        "attempt directory escapes its execution root")

    bounded_smoke_authorization = nothing
    if smoke !== nothing
        bounded_smoke_authorization =
            Batch.ld1b1_validate_bounded_smoke_authorization(
                options.bounded_smoke_authorization,
                parent_identity,
                identity,
                job,
                bounded_smoke_root,
            )
    end

    return (;
        options,
        checked,
        parent_identity,
        identity,
        execution_context,
        bounded_smoke_authorization,
        job,
        plan_row,
        execution_root,
        attempt_root,
        attempt_dir,
        output,
        runner_path,
        runner_source_sha256,
        primary_result_sha256,
        expected_relative_attempt_path,
        calibration_contract =
            checked.calibration_semantic_context.calibration_contract,
    )
end

function ld1b1_identity_arguments(context)
    return (;
        plan_identity = Batch.ld1b1_result_plan_identity(context.identity),
        execution_source_identity = context.identity.execution_source_identity,
        job_identity = Batch.ld1b1_result_job_identity(context.job),
        attempt_number = context.options.attempt,
        attempt_role = context.options.attempt_role,
        execution_context = context.execution_context,
    )
end

function ld1b1_launch_child_pid(launch)
    record = hasproperty(launch, :artifact) ? launch.artifact :
        hasproperty(launch, :launch) ? launch.launch : launch
    if record isa AbstractDict &&
            (haskey(record, "launch") || haskey(record, :launch))
        record = haskey(record, "launch") ? record["launch"] : record[:launch]
    end
    if record isa AbstractDict
        value = haskey(record, "child_pid") ? record["child_pid"] :
            haskey(record, :child_pid) ? record[:child_pid] : nothing
    else
        value = hasproperty(record, :child_pid) ? record.child_pid : nothing
    end
    value isa Integer && !(value isa Bool) || error(
        "validated launch receipt lacks child_pid")
    return Int(value)
end

"""
Validate the controller-owned reservation -> owner -> launch barrier.

The reservation API is deliberately invoked here only as a validator. Receipt
publication remains a controller responsibility.
"""
function ld1b1_validate_launch_barrier(context;
        timeout_seconds::Real = LD1B1_LAUNCH_RECEIPT_TIMEOUT_SECONDS,
        poll_seconds::Real = LD1B1_LAUNCH_RECEIPT_POLL_SECONDS)
    options = context.options
    options.mode in (:execute, :bounded_smoke) || error(
        "launch barrier is available only in execute or bounded-smoke mode")
    if options.mode === :execute
        options.controller_readiness_authorized || error(
            "controller readiness authorization is absent")
    else
        !options.controller_readiness_authorized || error(
            "bounded-smoke cannot carry controller readiness authorization")
        context.bounded_smoke_authorization !== nothing &&
            context.bounded_smoke_authorization.valid || error(
            "bounded-smoke authorization did not validate")
    end
    reservation_path = options.reservation_receipt
    reservation_path === nothing && error("reservation receipt is absent")
    isfile(reservation_path) && !islink(reservation_path) || error(
        "reservation receipt is not a regular file")
    isdir(context.attempt_dir) && !islink(context.attempt_dir) || error(
        "attempt directory is not a regular directory")
    Batch.ld1b1_require_realpath_containment(
        context.attempt_dir,
        context.execution_root,
    )

    recovery = Batch.LD1B1Recovery
    isdefined(recovery, :ld1b_validate_attempt_reservation_file) || error(
        "canonical reservation validator is unavailable")
    identity_arguments = ld1b1_identity_arguments(context)
    reservation = recovery.ld1b_validate_attempt_reservation_file(
        reservation_path;
        execution_root = context.execution_root,
        identity_arguments...,
        expected_execution_root_relative_attempt_path =
            context.expected_relative_attempt_path,
    )
    reservation.valid || error("attempt reservation did not validate")

    owner_path = joinpath(
        context.attempt_dir,
        recovery.LD1B_ATTEMPT_OWNER_FILENAME,
    )
    isfile(owner_path) && !islink(owner_path) || error(
        "controller owner precommit is absent before worker start")
    owner = recovery.ld1b_validate_canonical_attempt_owner_file(
        context.attempt_dir;
        reservation_path,
        execution_root = context.execution_root,
        identity_arguments...,
        expected_reservation_id = reservation.reservation_id,
    )
    owner.valid || error("canonical reservation-bound owner did not validate")

    deadline = time() + Float64(timeout_seconds)
    launch_path = joinpath(
        context.attempt_dir,
        recovery.LD1B_CHILD_LAUNCH_FILENAME,
    )
    while !isfile(launch_path)
        islink(launch_path) && error(
            "child-launch receipt must not be a symbolic link")
        time() < deadline || error(
            "timed out waiting for controller child-launch receipt")
        sleep(Float64(poll_seconds))
    end
    islink(launch_path) && error(
        "child-launch receipt must not be a symbolic link")

    # The recovery validator verifies the reservation binding transitively
    # through owner and launch. Its keyword surface is finalized with Gate 5.
    launch = recovery.ld1b_validate_child_launch_file(
        context.attempt_dir;
        identity_arguments...,
        reservation_path,
        execution_root = context.execution_root,
        expected_reservation_id = reservation.reservation_id,
    )
    launch.valid || error("child-launch receipt did not validate")
    ld1b1_launch_child_pid(launch) == getpid() || error(
        "child-launch receipt PID does not identify this worker")
    return (; valid = true, reservation, owner, launch)
end

function ld1b1_stage_error_code(error, fallback::Symbol)
    code = error isa LD1B1StageFailure ? error.code : fallback
    code in LD1B1_NONTERMINAL_ARTIFACT_CODES && return fallback
    return code
end

function ld1b1_nonterminal_outcome(code::Symbol, stage::Symbol, error)
    code in LD1B1_NONTERMINAL_ARTIFACT_CODES || error(
        "unsupported nonterminal artifact-failure code: $code")
    return (;
        terminal = false,
        terminal_status = missing,
        terminal_outcome_code = missing,
        nonterminal_code = code,
        failure_component = missing,
        failure_code = missing,
        failure_stage = stage,
        stage_error = error,
        simulation = nothing,
        fit = nothing,
        fit_artifact = nothing,
        sampler_diagnostics = nothing,
        local_dependence = nothing,
        calibration = nothing,
    )
end

function ld1b1_finalize_terminal(context, stages, status::Symbol;
        simulation = nothing,
        fit = nothing,
        fit_artifact = nothing,
        sampler_diagnostics = nothing,
        local_dependence = nothing,
        failure_component = missing,
        failure_code = missing,
        failure_stage = missing,
        stage_error = nothing)
    status in Batch.LD1B1_TERMINAL_STATUSES || error(
        "stage adapter produced an unsupported terminal status")
    try
        calibration = stages.calibration(
            context,
            status;
            simulation,
            diagnostic = status === :completed ? local_dependence : nothing,
            failure_code,
        )
        return (;
            terminal = true,
            terminal_status = status,
            terminal_outcome_code = Batch.ld1b1_terminal_outcome_code(status),
            nonterminal_code = missing,
            failure_component,
            failure_code,
            failure_stage,
            stage_error,
            simulation,
            fit,
            fit_artifact,
            sampler_diagnostics,
            local_dependence,
            calibration,
        )
    catch error
        return ld1b1_nonterminal_outcome(
            :final_calibration_serialization_failed,
            :calibration,
            error,
        )
    end
end

"""
Run the single-job scientific state machine with dependency-injected stages.

The adapter itself performs no filesystem writes. This is the only surface used
by its MCMC-free tests. Production publication happens after a terminal outcome
has been fully constructed.
"""
function ld1b1_run_stage_adapter(context, stages)
    simulation = try
        stages.generate(context)
    catch error
        failure_code = ld1b1_stage_error_code(error, :generation_exception)
        return ld1b1_finalize_terminal(
            context,
            stages,
            :generation_failed;
            failure_code,
            failure_stage = :generation,
            stage_error = error,
        )
    end

    if context.job.expected_action === :pre_fit_reject
        return ld1b1_finalize_terminal(
            context,
            stages,
            :pre_fit_rejected;
            simulation,
        )
    end
    context.job.expected_action === :fit_and_score_diagnostic || error(
        "canonical job has an unsupported expected action")

    fit = try
        stages.fit(context, simulation)
    catch error
        failure_code = ld1b1_stage_error_code(error, :fit_exception)
        return ld1b1_finalize_terminal(
            context,
            stages,
            :fit_failed;
            simulation,
            failure_code,
            failure_stage = :fit,
            stage_error = error,
        )
    end

    fit_artifact = try
        stages.fit_artifact(context, fit)
    catch error
        failure_code = ld1b1_stage_error_code(
            error,
            :fit_artifact_construction_failed,
        )
        return ld1b1_finalize_terminal(
            context,
            stages,
            :fit_failed;
            simulation,
            fit,
            failure_code,
            failure_stage = :fit,
            stage_error = error,
        )
    end

    sampler_diagnostics = try
        stages.sampler_diagnostics(context, fit, fit_artifact)
    catch error
        return ld1b1_nonterminal_outcome(
            :sampler_diagnostics_unavailable,
            :sampler_diagnostics,
            error,
        )
    end
    sampler_gate_passed = try
        stages.sampler_gate_passed(context, sampler_diagnostics)
    catch error
        return ld1b1_nonterminal_outcome(
            :sampler_diagnostics_unavailable,
            :sampler_diagnostics,
            error,
        )
    end
    sampler_gate_passed isa Bool || return ld1b1_nonterminal_outcome(
        :sampler_diagnostics_unavailable,
        :sampler_diagnostics,
        ArgumentError("sampler gate did not return Bool"),
    )
    if !sampler_gate_passed
        return ld1b1_finalize_terminal(
            context,
            stages,
            :diagnostic_failed;
            simulation,
            fit,
            fit_artifact,
            sampler_diagnostics,
            failure_component = :sampler_quality_gate,
            failure_code = :sampler_quality_gate_failed,
            failure_stage = :diagnostic,
        )
    end

    local_dependence = try
        stages.local_dependence(
            context,
            fit,
            fit_artifact,
            sampler_diagnostics,
        )
    catch error
        failure_code = ld1b1_stage_error_code(
            error,
            :local_dependence_summary_exception,
        )
        return ld1b1_finalize_terminal(
            context,
            stages,
            :diagnostic_failed;
            simulation,
            fit,
            fit_artifact,
            sampler_diagnostics,
            failure_component = :local_dependence_summary,
            failure_code,
            failure_stage = :diagnostic,
            stage_error = error,
        )
    end

    return ld1b1_finalize_terminal(
        context,
        stages,
        :completed;
        simulation,
        fit,
        fit_artifact,
        sampler_diagnostics,
        local_dependence,
    )
end

function ld1b1_hash_record_value(record, label::AbstractString)
    value = record isa AbstractDict ?
        (haskey(record, :value) ? record[:value] : record["value"]) :
        getproperty(record, :value)
    return Batch.ld1b1_require_sha256(value, label)
end

function ld1b1_require_json_safe(value, label::AbstractString = "value")
    if value === nothing || ismissing(value) || value isa Bool ||
            value isa Integer || value isa Symbol || value isa AbstractString
        return true
    elseif value isa AbstractFloat
        isfinite(value) || error("$label contains a non-finite number")
        return true
    elseif value isa NamedTuple || value isa AbstractDict
        for (key, element) in pairs(value)
            ld1b1_require_json_safe(element, string(label, ".", key))
        end
        return true
    elseif value isa AbstractArray || value isa Tuple
        for (index, element) in pairs(value)
            ld1b1_require_json_safe(element, string(label, "[", index, "]"))
        end
        return true
    end
    error("$label contains unsupported JSON value type $(typeof(value))")
end

"""
Project every field named `data_signature` and every unsigned integer above
`typemax(Int64)` to an exact canonical decimal string before JSON content
hashes or evidence-envelope hashes are computed.

JSON3 decodes integers above `typemax(Int64)` as floating-point values, which
would otherwise lose bits from the package's native `UInt64` data signature.
The general unsigned-integer branch also protects fields such as the design
validation `options_signature`. Missing data signatures remain missing for
generation-failure artifacts.
"""
function ld1b1_project_data_signatures(value,
        field::Union{Nothing,Symbol,String} = nothing)
    if field !== nothing && String(field) == "data_signature"
        (value === nothing || ismissing(value)) && return value
        return Batch.ld1b1_data_signature(
            value,
            "data signature";
            allow_native_uint64 = true,
        )
    elseif value isa Unsigned && BigInt(value) > typemax(Int64)
        return string(value)
    elseif value isa NamedTuple
        names = keys(value)
        values = Tuple(ld1b1_project_data_signatures(element, name)
            for (name, element) in pairs(value))
        return NamedTuple{names}(values)
    elseif value isa AbstractDict
        return Dict(key => ld1b1_project_data_signatures(element, key)
            for (key, element) in pairs(value))
    elseif value isa Tuple
        return Tuple(ld1b1_project_data_signatures(element, field)
            for element in value)
    elseif value isa AbstractArray
        return map(element -> ld1b1_project_data_signatures(element, field),
            value)
    end
    return value
end

function ld1b1_simulation_source_projection(simulation)
    future_fit_action = simulation.design_support.future_fit_action
    row_truth = merge(simulation.row_truth, (;
        probabilities = vec(permutedims(
            simulation.row_truth.probabilities,
        )),
    ))
    source = (;
        schema = simulation.schema,
        object = simulation.object,
        status = simulation.status,
        profile = simulation.profile,
        grid_id = simulation.grid_id,
        scenario_id = simulation.scenario_id,
        matched_set_id = simulation.matched_set_id,
        replication = simulation.replication,
        phase = simulation.phase,
        base_seed = simulation.base_seed,
        seed = simulation.seed,
        mechanism = simulation.mechanism,
        magnitude_label = simulation.magnitude_label,
        effect_scale = simulation.effect_scale,
        design = simulation.design,
        assignment = simulation.assignment,
        order = simulation.order,
        generator_contract = (;
            fitted_probability_or_likelihood_dependency = :none,
        ),
        data = (;
            n = simulation.data.n,
            score = simulation.data.score,
        ),
        table = simulation.table,
        truth = simulation.truth,
        row_truth,
        validation = (;
            data_signature = simulation.data_signature,
        ),
        design_support = (;
            requested_targets_eligible =
                simulation.design_support.requested_targets_eligible,
            expected_requested_targets_eligible = simulation.design_support.
                expected_requested_targets_eligible,
            future_fit_action,
        ),
        resource_counts = simulation.resource_counts,
        checks = simulation.checks,
        data_signature = simulation.data_signature,
        testlet_design_signature = simulation.testlet_design_signature,
        score_signature = simulation.score_signature,
        truth_known_by_construction = simulation.truth_known_by_construction,
        calibration_status = simulation.calibration_status,
        calibration_evidence_available =
            simulation.calibration_evidence_available,
        diagnostic_decision_labels_available =
            simulation.diagnostic_decision_labels_available,
        observed_data_mechanism_interpretation_eligible =
            simulation.observed_data_mechanism_interpretation_eligible,
        summary = simulation.summary,
        caveat = simulation.caveat,
    )
    ld1b1_require_json_safe(source, "simulation source projection")
    return source
end

function ld1b1_fit_artifact_stage(context, fit)
    artifact = BayesianMGMFRM.fit_artifact(
        fit;
        include_draws = true,
        include_log_posterior = true,
        include_sampler_stats = true,
        include_environment = false,
        split_chains = context.job.sampler_contract.split_chains,
        rhat_threshold = context.job.quality_contract.maximum_rhat,
        ess_threshold = min(
            context.job.quality_contract.minimum_bulk_ess,
            context.job.quality_contract.minimum_tail_ess,
        ),
    )
    native_hash = BayesianMGMFRM.artifact_content_hash(artifact)
    recorded_hash = ld1b1_hash_record_value(
        artifact.content_hash,
        "native fit-artifact content hash",
    )
    native_hash == recorded_hash || error(
        "native fit-artifact hash failed before JSON projection")

    # JSON projection is intentionally downstream of the native verification.
    projected_artifact = ld1b1_project_data_signatures(
        Batch.ld1b1_json_native(artifact),
    )
    ld1b1_require_json_safe(projected_artifact, "fit-artifact JSON projection")
    json_hash = Batch.ld1b1_json_content_hash_record(
        projected_artifact;
        scope = :fit_artifact_json_payload,
    )
    json_export = (;
        schema =
            "bayesianmgmfrm.local_dependence_pilot_fit_artifact_export.v1",
        object = :fit_artifact_export,
        serialization = (;
            format = :json,
            projection = :ld1b1_json_native_v1,
            symbol_values = :string,
            missing_values = :json_null,
            nonfinite_numbers = :rejected,
        ),
        artifact_content_hash = artifact.content_hash,
        json_content_hash = json_hash,
        artifact = projected_artifact,
    )
    ld1b1_require_json_safe(json_export, "fit-artifact export")
    retained_draw_set_sha256 = Batch.ld1b1_canonical_sha256((;
        draws = projected_artifact["draws"],
        log_posterior = projected_artifact["log_posterior"],
        sampler_stats = projected_artifact["sampler_stats"],
    ))
    return (;
        artifact,
        json_export,
        native_hash,
        native_hash_verified_before_json_projection = true,
        json_content_hash = json_hash.value,
        retained_draw_set_sha256,
    )
end

function ld1b1_sampler_gate_passed(context, diagnostic_surface)
    summary = diagnostic_surface.summary
    required_finite = (
        summary.max_rank_normalized_rhat,
        summary.min_bulk_ess,
        summary.min_tail_ess,
    )
    all(value -> value isa Real && isfinite(value), required_finite) || error(
        "sampler diagnostics do not contain finite convergence extrema")
    e_bfmi = summary.e_bfmi
    e_bfmi_passed = context.job.quality_contract.
        e_bfmi_chain_coverage_required ?
        summary.e_bfmi_complete && !ismissing(e_bfmi) &&
            isfinite(e_bfmi) &&
            e_bfmi >= context.job.quality_contract.minimum_e_bfmi :
        ismissing(e_bfmi) ||
            (isfinite(e_bfmi) &&
                e_bfmi >= context.job.quality_contract.minimum_e_bfmi)
    return summary.max_rank_normalized_rhat <=
            context.job.quality_contract.maximum_rhat &&
        summary.min_bulk_ess >=
            context.job.quality_contract.minimum_bulk_ess &&
        summary.min_tail_ess >=
            context.job.quality_contract.minimum_tail_ess &&
        summary.n_divergences <=
            context.job.quality_contract.maximum_divergences &&
        summary.n_max_treedepth <=
            context.job.quality_contract.maximum_depth_hits &&
        e_bfmi_passed && summary.passed && summary.flag === :ok
end

function ld1b1_local_dependence_stage(context, fit, fit_artifact, diagnostics)
    indices = collect(Batch.ld1b1_expected_draw_indices(
        context.job.draw_selection_seed,
        context.job.sampler_contract.total_retained_draws,
        context.job.sampler_contract.diagnostic_draws,
    ))
    diagnostic = BayesianMGMFRM.local_dependence_summary(
        fit;
        contract = context.calibration_contract.diagnostic_contract,
        draw_indices = indices,
        rng = MersenneTwister(context.job.posterior_predictive_seed),
    )
    source = merge(diagnostic, (;
        schema =
            "bayesianmgmfrm.local_dependence_pilot_summary_bundle.v1",
        object = :local_dependence_pilot_summary_bundle,
        draw_selection_algorithm = Batch.LD1B1_DRAW_SELECTION_ALGORITHM,
        draw_selection_seed = context.job.draw_selection_seed,
        posterior_predictive_seed = context.job.posterior_predictive_seed,
        retained_draw_set_sha256 =
            fit_artifact.retained_draw_set_sha256,
    ))
    ld1b1_require_json_safe(source, "local-dependence summary bundle")
    return (; diagnostic, source)
end

function ld1b1_production_stages()
    return (;
        generate = context -> begin
            simulation = BayesianMGMFRM.simulate_local_dependence(
                context.plan_row;
                max_ratings = context.job.resources.n_ratings,
                max_probability_cells =
                    context.job.resources.n_probability_cells,
                max_truth_cells = context.job.resources.n_truth_cells,
            )
            simulation.summary.passed || throw(
                LD1B1StageFailure(:generation_preflight_failed))
            source = ld1b1_simulation_source_projection(simulation)
            return (; simulation, source)
        end,
        fit = (context, simulation_stage) -> begin
            simulation = simulation_stage.simulation
            spec = BayesianMGMFRM.mfrm_spec(
                simulation.data;
                thresholds = :partial_credit,
            )
            return BayesianMGMFRM.fit(
                spec;
                backend = context.job.sampler_contract.backend,
                ndraws = context.job.sampler_contract.draws_per_chain,
                warmup = context.job.sampler_contract.warmup_per_chain,
                chains = context.job.sampler_contract.chains,
                seed = context.job.fit_seed,
                target_accept = context.job.sampler_contract.target_accept,
                max_depth = context.job.sampler_contract.max_depth,
                metric = context.job.sampler_contract.metric,
                ad_backend = context.job.sampler_contract.ad_backend,
                progress = false,
            )
        end,
        fit_artifact = ld1b1_fit_artifact_stage,
        sampler_diagnostics = (context, fit, fit_artifact) ->
            BayesianMGMFRM.diagnostics(
                fit;
                split_chains = context.job.sampler_contract.split_chains,
                rhat_threshold = context.job.quality_contract.maximum_rhat,
                ess_threshold = min(
                    context.job.quality_contract.minimum_bulk_ess,
                    context.job.quality_contract.minimum_tail_ess,
                ),
            ),
        sampler_gate_passed = ld1b1_sampler_gate_passed,
        local_dependence = ld1b1_local_dependence_stage,
        calibration = (context, status;
                simulation = nothing,
                diagnostic = nothing,
                failure_code = missing) -> begin
            native_simulation = simulation === nothing ? nothing :
                simulation.simulation
            native_diagnostic = diagnostic === nothing ? nothing :
                diagnostic.diagnostic
            calibration = BayesianMGMFRM.local_dependence_calibration_row(
                context.plan_row;
                contract = context.calibration_contract,
                status,
                simulation = native_simulation,
                diagnostic = native_diagnostic,
                failure_code,
            )
            ld1b1_require_json_safe(calibration, "calibration row")
            return calibration
        end,
    )
end

function ld1b1_diagnostics_source(context, outcome, references)
    surface = outcome.sampler_diagnostics
    summary = surface.summary
    fit_reference = references[:fit_result]
    return (;
        schema =
            "bayesianmgmfrm.local_dependence_pilot_sampler_diagnostics_bundle.v1",
        object = :sampler_diagnostics_bundle,
        backend = context.job.sampler_contract.backend,
        sampler = context.job.sampler_contract.algorithm,
        fit_artifact_sha256 = fit_reference.source_sha256,
        fit_artifact_content_hash = outcome.fit_artifact.native_hash,
        data_signature = outcome.fit.design.spec.validation.data_signature,
        retained_draw_set_sha256 =
            outcome.fit_artifact.retained_draw_set_sha256,
        chain_ids = outcome.fit.chain_ids,
        iterations = outcome.fit.iterations,
        summary = (;
            diagnostic_contract = summary.diagnostic_contract,
            diagnostic_contract_details = summary.diagnostic_contract_details,
            flag = summary.flag,
            passed = summary.passed,
            n_chains = summary.n_chains,
            draws_per_chain = summary.draws_per_chain,
            total_draws = summary.total_draws,
            split_chains_requested = summary.split_chains_requested,
            split_chains = summary.split_chains,
            max_rank_normalized_rhat = summary.max_rank_normalized_rhat,
            min_bulk_ess = summary.min_bulk_ess,
            min_tail_ess = summary.min_tail_ess,
            n_divergences = summary.n_divergences,
            n_max_treedepth = summary.n_max_treedepth,
            e_bfmi = summary.e_bfmi,
            n_e_bfmi_expected = summary.n_e_bfmi_expected,
            n_e_bfmi_available = summary.n_e_bfmi_available,
            n_e_bfmi_unavailable = summary.n_e_bfmi_unavailable,
            e_bfmi_complete = summary.e_bfmi_complete,
        ),
    )
end

function ld1b1_failure_source(context, outcome, role::Symbol)
    stage = role === :generation_failure_record ? :generation :
        role === :fit_failure_record ? :fit : :diagnostic
    base = (;
        schema = "bayesianmgmfrm.local_dependence_pilot_failure_record.v1",
        object = role,
        job_id = context.job.job_id,
        row_index = context.job.row_index,
        scenario_id = context.job.scenario_id,
        replication = context.job.replication,
        failure_stage = stage,
    )
    return role === :diagnostic_failure_record ? merge(base, (;
        failure_component = outcome.failure_component,
        error_class = outcome.failure_code,
        failure_recorded = true,
    )) : merge(base, (;
        error_class = outcome.failure_code,
        failure_recorded = true,
    ))
end

function ld1b1_source_value(context, outcome, role::Symbol, references)
    role === :generated_data && return outcome.simulation.source
    role === :fit_result && return outcome.fit_artifact.json_export
    role === :sampler_diagnostics && return ld1b1_diagnostics_source(
        context,
        outcome,
        references,
    )
    role === :local_dependence_summary && return outcome.local_dependence.source
    role === :calibration_row && return outcome.calibration
    if role === :structural_rejection_audit
        generated = references[:generated_data]
        return (;
            schema =
                "bayesianmgmfrm.local_dependence_pilot_structural_rejection_audit.v1",
            object = :structural_rejection_audit,
            job_id = context.job.job_id,
            row_index = context.job.row_index,
            scenario_id = context.job.scenario_id,
            replication = context.job.replication,
            simulation_content_sha256 = generated.source_sha256,
            data_signature = outcome.simulation.simulation.data_signature,
            expected_action = :pre_fit_reject,
            issue_code = :expected_structural_rejection,
            rejection_confirmed = true,
        )
    end
    role in (
        :generation_failure_record,
        :fit_failure_record,
        :diagnostic_failure_record,
    ) && return ld1b1_failure_source(context, outcome, role)
    error("unsupported source-member role: $role")
end

function ld1b1_encode_json(value)
    isequal(ld1b1_project_data_signatures(value), value) || error(
        "lossless integer signatures must be projected before JSON encoding")
    ld1b1_require_json_safe(value)
    io = IOBuffer()
    Batch.write_json(io, value)
    println(io)
    return take!(io)
end

function ld1b1_data_signature(outcome)
    return outcome.simulation.simulation.data_signature
end

function ld1b1_payload(context, outcome, role::Symbol,
        source_sha256::AbstractString, references)
    job = context.job
    if role === :generated_data
        simulation = outcome.simulation.simulation
        return (;
            simulation_content_sha256 = source_sha256,
            n_response_rows = job.resources.n_ratings,
            n_probability_cells = job.resources.n_probability_cells,
            n_truth_cells = job.resources.n_truth_cells,
            data_signature = simulation.data_signature,
            score_signature = simulation.score_signature,
            testlet_design_signature_sha256 = ld1b1_hash_record_value(
                simulation.testlet_design_signature,
                "simulation design signature",
            ),
            generation_completed = true,
        )
    elseif role === :fit_result
        return (;
            fit_artifact_sha256 = source_sha256,
            fit_artifact_content_hash = outcome.fit_artifact.native_hash,
            fit_artifact_json_content_hash =
                outcome.fit_artifact.json_content_hash,
            data_signature = ld1b1_data_signature(outcome),
            retained_draw_set_sha256 =
                outcome.fit_artifact.retained_draw_set_sha256,
            fit_seed = job.fit_seed,
            backend = job.sampler_contract.backend,
            algorithm = job.sampler_contract.algorithm,
            n_chains = job.sampler_contract.chains,
            warmup_per_chain = job.sampler_contract.warmup_per_chain,
            draws_per_chain = job.sampler_contract.draws_per_chain,
            total_retained_draws = job.sampler_contract.total_retained_draws,
            target_accept = job.sampler_contract.target_accept,
            max_depth = job.sampler_contract.max_depth,
            metric = job.sampler_contract.metric,
            ad_backend = job.sampler_contract.ad_backend,
            fit_completed = true,
        )
    elseif role === :sampler_diagnostics
        summary = outcome.sampler_diagnostics.summary
        sampler_gate_passed = ld1b1_sampler_gate_passed(
            context,
            outcome.sampler_diagnostics,
        )
        return (;
            diagnostics_content_sha256 = source_sha256,
            diagnostic_contract = summary.diagnostic_contract,
            diagnostic_contract_details_sha256 =
                job.quality_contract.diagnostic_contract_details_sha256,
            n_chains = summary.n_chains,
            draws_per_chain = summary.draws_per_chain,
            total_draws = summary.total_draws,
            split_chains_requested = summary.split_chains_requested,
            split_chains = summary.split_chains,
            max_rank_normalized_rhat = summary.max_rank_normalized_rhat,
            min_bulk_ess = summary.min_bulk_ess,
            min_tail_ess = summary.min_tail_ess,
            n_divergences = summary.n_divergences,
            n_max_treedepth = summary.n_max_treedepth,
            e_bfmi = summary.e_bfmi,
            n_e_bfmi_expected = summary.n_e_bfmi_expected,
            n_e_bfmi_available = summary.n_e_bfmi_available,
            n_e_bfmi_unavailable = summary.n_e_bfmi_unavailable,
            e_bfmi_complete = summary.e_bfmi_complete,
            diagnostics_passed = summary.passed,
            diagnostics_flag = summary.flag,
            sampler_gate_passed,
            fit_artifact_sha256 = references[:fit_result].source_sha256,
            fit_artifact_content_hash = outcome.fit_artifact.native_hash,
            data_signature = ld1b1_data_signature(outcome),
            retained_draw_set_sha256 =
                outcome.fit_artifact.retained_draw_set_sha256,
        )
    elseif role === :local_dependence_summary
        diagnostic = outcome.local_dependence.diagnostic
        return (;
            summary_content_sha256 = source_sha256,
            diagnostic_computed = true,
            n_diagnostic_draws = diagnostic.n_draws,
            draw_selection_algorithm = Batch.LD1B1_DRAW_SELECTION_ALGORITHM,
            draw_selection_seed = job.draw_selection_seed,
            posterior_predictive_seed = job.posterior_predictive_seed,
            replicates_per_draw =
                diagnostic.replicated_datasets_per_parameter_draw,
            data_signature = diagnostic.data_signature,
            observed_score_signature_sha256 = ld1b1_hash_record_value(
                diagnostic.observed_score_signature,
                "observed-score signature",
            ),
            design_signature_sha256 = ld1b1_hash_record_value(
                diagnostic.design_signature,
                "diagnostic design signature",
            ),
            retained_draw_set_sha256 =
                outcome.fit_artifact.retained_draw_set_sha256,
            diagnostic_decision_labels_available = false,
            mechanism_interpretation_eligible = false,
        )
    elseif role === :calibration_row
        calibration = outcome.calibration
        generated = outcome.terminal_status !== :generation_failed
        observed_score_signature = generated ? ld1b1_hash_record_value(
            calibration.simulation_provenance.observed_score_signature,
            "calibration observed-score signature",
        ) : missing
        design_signature = generated ? ld1b1_hash_record_value(
            calibration.simulation_provenance.testlet_design_signature,
            "calibration design signature",
        ) : missing
        return (;
            calibration_content_sha256 = source_sha256,
            calibration_contract = calibration.schema,
            row_index = job.row_index,
            scenario_index = job.scenario_index,
            scenario_id = job.scenario_id,
            replication = job.replication,
            status = outcome.terminal_status,
            data_signature = generated ?
                calibration.simulation_provenance.data_signature : missing,
            observed_score_signature_sha256 = observed_score_signature,
            design_signature_sha256 = design_signature,
            row_complete = true,
        )
    elseif role === :structural_rejection_audit
        return (;
            audit_content_sha256 = source_sha256,
            simulation_content_sha256 =
                references[:generated_data].source_sha256,
            data_signature = ld1b1_data_signature(outcome),
            issue_code = :expected_structural_rejection,
            expected_action = :pre_fit_reject,
            rejection_confirmed = true,
        )
    end
    stage = role === :generation_failure_record ? :generation :
        role === :fit_failure_record ? :fit : :diagnostic
    base = (;
        failure_content_sha256 = source_sha256,
        failure_stage = stage,
    )
    return role === :diagnostic_failure_record ? merge(base, (;
        failure_component = outcome.failure_component,
        error_class = outcome.failure_code,
        failure_recorded = true,
    )) : merge(base, (;
        error_class = outcome.failure_code,
        failure_recorded = true,
    ))
end

function ld1b1_source_relative_path(role::Symbol)
    return joinpath(
        LD1B1_SOURCE_DIRECTORY,
        string(Batch.ld1b1_evidence_member_role(role), ".json"),
    )
end

function ld1b1_evidence_relative_path(role::Symbol)
    return joinpath(LD1B1_EVIDENCE_DIRECTORY, string(role, ".json"))
end

function ld1b1_prepare_terminal_transaction(context, outcome)
    outcome.terminal || error("cannot prepare a nonterminal job result")
    roles = Batch.ld1b1_required_evidence_roles(outcome.terminal_status)
    references = Dict{Symbol,Any}()
    files = NamedTuple[]
    manifest = NamedTuple[]
    evidence_values = Dict{Symbol,Any}()

    for role in roles
        try
            source_value = ld1b1_project_data_signatures(ld1b1_source_value(
                context,
                outcome,
                role,
                references,
            ))
            source_bytes = ld1b1_encode_json(source_value)
            source_sha256 = bytes2hex(sha256(source_bytes))
            payload = ld1b1_project_data_signatures(ld1b1_payload(
                context,
                outcome,
                role,
                source_sha256,
                references,
            ))
            Batch.ld1b1_validate_source_member_json(
                source_bytes,
                role,
                context.job,
                payload,
                outcome.terminal_status,
            )
            source_relative = ld1b1_source_relative_path(role)
            source_member = (;
                role = Batch.ld1b1_evidence_member_role(role),
                path = source_relative,
                media_type = Batch.ld1b1_evidence_member_media_type(role),
                bytes = length(source_bytes),
                sha256 = source_sha256,
            )
            dependencies = Tuple((;
                role = dependency_role,
                content_hash = references[dependency_role].content_hash,
            ) for dependency_role in
                Batch.ld1b1_expected_evidence_dependencies(
                    outcome.terminal_status,
                    role,
                ))
            evidence = Batch.ld1b1_evidence_envelope(
                context.identity,
                context.job,
                context.options.attempt,
                outcome.terminal_status,
                role,
                payload;
                member = source_member,
                dependencies,
                runner_source_sha256 = context.runner_source_sha256,
                execution_context = context.execution_context,
            )
            evidence_bytes = ld1b1_encode_json(evidence)
            evidence_sha256 = bytes2hex(sha256(evidence_bytes))
            evidence_relative = ld1b1_evidence_relative_path(role)
            push!(files, (;
                kind = :source,
                role,
                relative_path = source_relative,
                bytes = source_bytes,
                sha256 = source_sha256,
            ))
            push!(files, (;
                kind = :evidence,
                role,
                relative_path = evidence_relative,
                bytes = evidence_bytes,
                sha256 = evidence_sha256,
            ))
            push!(manifest, (;
                role,
                path = evidence_relative,
                bytes = length(evidence_bytes),
                sha256 = evidence_sha256,
            ))
            content_hash = ld1b1_hash_record_value(
                evidence.content_hash,
                "prepared evidence content hash",
            )
            references[role] = (;
                source_sha256,
                source_member,
                content_hash,
                evidence_sha256,
            )
            evidence_values[role] = (;
                payload,
                source_value = role === :fit_result ?
                    source_value.artifact : source_value,
                source_snapshot = (; sha256 = source_sha256),
            )
        catch error
            code = role === :sampler_diagnostics ?
                :sampler_diagnostics_unavailable :
                role === :calibration_row ?
                    :final_calibration_serialization_failed : nothing
            code === nothing && rethrow()
            throw(LD1B1NonterminalArtifactFailure(code, error))
        end
    end

    Batch.ld1b1_validate_cross_evidence_lineage(
        evidence_values,
        outcome.terminal_status,
        context.job,
    )
    semantic_inputs = (;
        failure_record = outcome.terminal_status in
                Batch.LD1B1_CATEGORIZED_FAILURE_STATUSES ?
            evidence_values[
                outcome.terminal_status === :generation_failed ?
                    :generation_failure_record :
                outcome.terminal_status === :fit_failed ?
                    :fit_failure_record : :diagnostic_failure_record
            ].source_value : nothing,
        local_dependence_member = outcome.terminal_status === :completed ?
            evidence_values[:local_dependence_summary].source_value : nothing,
        calibration_member = evidence_values[:calibration_row].source_value,
    )
    Batch.ld1b1_validate_calibration_semantics(
        context.checked.calibration_semantic_context,
        semantic_inputs,
        context.job,
        outcome.terminal_status,
    )

    try
        result = Batch.ld1b1_result_envelope(
            context.identity,
            context.job,
            context.options.attempt,
            outcome.terminal_status;
            retry_reason = context.options.retry_reason,
            retry_of_attempt = context.options.retry_of,
            primary_result_sha256 = context.primary_result_sha256,
            file_manifest = Tuple(manifest),
            lineage_valid = true,
            runner_source_sha256 = context.runner_source_sha256,
            execution_context = context.execution_context,
        )
        result_bytes = ld1b1_encode_json(result)
        return (;
            files = Tuple(files),
            manifest = Tuple(manifest),
            result,
            result_bytes,
            result_sha256 = bytes2hex(sha256(result_bytes)),
        )
    catch error
        throw(LD1B1NonterminalArtifactFailure(
            :final_calibration_serialization_failed,
            error,
        ))
    end
end

function ld1b1_atomic_publish_bytes_create_new(
        path::AbstractString,
        bytes::Vector{UInt8},
        staging_dir::AbstractString,
        boundary::AbstractString;
        label::AbstractString)
    target = normpath(path)
    root = normpath(boundary)
    staging = normpath(staging_dir)
    Batch.ld1b1_path_within(target, root) || error(
        "$label target escapes the execution root")
    Batch.ld1b1_path_within(staging, root) || error(
        "$label staging directory escapes the execution root")
    isdir(root) && !islink(root) || error(
        "worker publication boundary is not a regular directory")
    parent = dirname(target)
    Batch.ld1b1_reject_symlink_components(parent, root)
    mkpath(parent)
    Batch.ld1b1_require_realpath_containment(parent, root)
    Batch.ld1b1_reject_symlink_components(staging, root)
    mkpath(staging)
    Batch.ld1b1_require_realpath_containment(staging, root)
    (ispath(target) || islink(target)) && error(
        "refusing to replace existing $label: $target")

    temporary_path, io = mktemp(staging)
    published = false
    try
        write(io, bytes)
        flush(io)
        close(io)
        Batch.ld1b1_file_sha256(temporary_path) ==
            bytes2hex(sha256(bytes)) || error(
            "$label staging bytes changed")
        Batch.ld1b1_reject_symlink_components(parent, root)
        (ispath(target) || islink(target)) && error(
            "$label target became occupied")
        hardlink(temporary_path, target)
        published = true
        rm(temporary_path)
        snapshot = Batch.ld1b1_regular_file_snapshot(
            target,
            root,
            "published $label",
        )
        snapshot.bytes == bytes || error("published $label bytes changed")
        return (;
            path = target,
            file_sha256 = snapshot.sha256,
            nbytes = snapshot.nbytes,
            publication = :same_volume_hardlink_create_new,
            overwrite_allowed = false,
        )
    finally
        isopen(io) && close(io)
        !published && (ispath(temporary_path) || islink(temporary_path)) &&
            rm(temporary_path; force = true)
    end
end

function ld1b1_publish_terminal_transaction(context, transaction)
    staging_dir = joinpath(
        context.execution_root,
        LD1B1_WORKER_STAGING_DIRECTORY,
    )
    publications = NamedTuple[]
    for file in transaction.files
        target = joinpath(context.attempt_dir, file.relative_path)
        push!(publications, ld1b1_atomic_publish_bytes_create_new(
            target,
            file.bytes,
            staging_dir,
            context.execution_root;
            label = string(file.kind, " ", file.role),
        ))
    end
    result_publication = ld1b1_atomic_publish_bytes_create_new(
        context.output,
        transaction.result_bytes,
        staging_dir,
        context.execution_root;
        label = "job result",
    )
    semantic = Batch.ld1b1_validate_result(
        context.output,
        context.identity,
        context.job,
        context.options.attempt;
        calibration_semantic_context =
            context.checked.calibration_semantic_context,
        execution_context = context.execution_context,
    )
    return (;
        publications = Tuple(publications),
        result_publication,
        semantic,
    )
end

function ld1b1_status(context)
    occupied = ispath(context.output) || islink(context.output)
    if !occupied
        return (;
            schema = "bayesianmgmfrm.local_dependence_pilot_job_worker_status.v1",
            object = :local_dependence_pilot_job_worker_status,
            mode = :status,
            read_only = true,
            plan_id = context.identity.plan_id,
            job_id = context.job.job_id,
            row_index = context.job.row_index,
            attempt = context.options.attempt,
            result_state = :absent,
            terminal_status = missing,
            valid = true,
        )
    end
    isfile(context.output) && !islink(context.output) || error(
        "worker result path is occupied by a non-regular file")
    validated = Batch.ld1b1_validate_result(
        context.output,
        context.identity,
        context.job,
        context.options.attempt;
        calibration_semantic_context =
            context.checked.calibration_semantic_context,
        execution_context = context.execution_context,
    )
    return (;
        schema = "bayesianmgmfrm.local_dependence_pilot_job_worker_status.v1",
        object = :local_dependence_pilot_job_worker_status,
        mode = :status,
        read_only = true,
        plan_id = context.identity.plan_id,
        job_id = context.job.job_id,
        row_index = context.job.row_index,
        attempt = context.options.attempt,
        result_state = :verified_terminal_unsealed_or_controller_sealed,
        terminal_status = validated.terminal_status,
        valid = true,
    )
end

function ld1b1_print_json(value; io::IO = stdout)
    Batch.write_json(io, value)
    println(io)
    return nothing
end

function ld1b1_job_main(args = ARGS;
        stages = ld1b1_production_stages(),
        barrier_validator = ld1b1_validate_launch_barrier)
    options = ld1b1_parse_job_args(args)
    if options.help
        println(ld1b1_job_usage())
        return 0
    end
    context = ld1b1_validate_job_invocation(options)
    if options.mode === :status
        ld1b1_print_json(ld1b1_status(context))
        return 0
    end

    readiness = context.parent_identity.readiness
    if options.mode === :execute
        readiness.operational_execution_authorized || error(
            "LD1b1 worker operational execution is blocked before output/attempt " *
            "creation: " * join(string.(readiness.blockers), ", "))
    else
        options.mode === :bounded_smoke || error(
            "unsupported mutating worker mode")
        readiness.protocol_execution_authorized &&
            readiness.canonical_executor_materialized &&
            readiness.final_worker_source_pinned_and_identities_regenerated &&
            readiness.canonical_executor_source_pinned &&
            readiness.completed_attempt_archive_seal_supported || error(
            "bounded-smoke source/receipt prerequisites did not pass")
        !readiness.operational_execution_authorized || error(
            "bounded-smoke cannot substitute for an already authorized pilot")
        context.bounded_smoke_authorization !== nothing &&
            context.bounded_smoke_authorization.valid || error(
            "bounded-smoke authorization did not validate")
        context.job.row_index == Batch.LD1B1_BOUNDED_SMOKE_ROW_INDEX &&
            context.job.job_id == Batch.LD1B1_BOUNDED_SMOKE_JOB_ID &&
            context.options.attempt == 1 &&
            context.options.attempt_role === :verification || error(
            "bounded-smoke worker identity escaped the frozen allowlist")
    end
    (ispath(context.output) || islink(context.output)) && error(
        "refusing to replace existing worker result")
    barrier = barrier_validator(context)
    barrier.valid || error("controller launch barrier did not pass")
    outcome = ld1b1_run_stage_adapter(context, stages)
    if !outcome.terminal
        ld1b1_print_json((;
            schema =
                "bayesianmgmfrm.local_dependence_pilot_job_worker_nonterminal.v2",
            object = :local_dependence_pilot_job_worker_nonterminal,
            execution_context = context.execution_context,
            plan_id = context.identity.plan_id,
            job_id = context.job.job_id,
            row_index = context.job.row_index,
            attempt = context.options.attempt,
            terminal = false,
            nonterminal_code = outcome.nonterminal_code,
            completed_seal_allowed = false,
        ))
        return 3
    end
    transaction = try
        ld1b1_prepare_terminal_transaction(context, outcome)
    catch error
        if error isa LD1B1NonterminalArtifactFailure
            ld1b1_print_json((;
                schema =
                    "bayesianmgmfrm.local_dependence_pilot_job_worker_nonterminal.v2",
                object = :local_dependence_pilot_job_worker_nonterminal,
                execution_context = context.execution_context,
                plan_id = context.identity.plan_id,
                job_id = context.job.job_id,
                row_index = context.job.row_index,
                attempt = context.options.attempt,
                terminal = false,
                nonterminal_code = error.code,
                completed_seal_allowed = false,
            ))
            return 3
        end
        rethrow()
    end
    publication = ld1b1_publish_terminal_transaction(context, transaction)
    ld1b1_print_json((;
        schema =
            "bayesianmgmfrm.local_dependence_pilot_job_worker_completion.v2",
        object = :local_dependence_pilot_job_worker_completion,
        execution_context = context.execution_context,
        plan_id = context.identity.plan_id,
        job_id = context.job.job_id,
        row_index = context.job.row_index,
        attempt = context.options.attempt,
        terminal_status = outcome.terminal_status,
        result_path = Batch.ld1b1_record_path(context.output),
        result_file_sha256 = publication.result_publication.file_sha256,
        controller_seal_required = true,
        worker_published_control_receipt = false,
        worker_published_completed_seal = false,
        official_pilot_scientific_contribution = 0,
    ))
    return 0
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    try
        exit(LocalDependenceCalibrationPilotJobWorker.ld1b1_job_main(ARGS))
    catch error
        println(stderr, "ERROR: ", sprint(showerror, error))
        exit(1)
    end
end
