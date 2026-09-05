using Test

if !isdefined(@__MODULE__, :LocalDependenceCalibrationPilotJobWorker)
    include(joinpath(
        @__DIR__,
        "..",
        "scripts",
        "run_local_dependence_calibration_pilot_job.jl",
    ))
end

const LD1B1JobWorker = LocalDependenceCalibrationPilotJobWorker

function ld1b1_fake_context(expected_action::Symbol)
    return (;
        job = (; expected_action),
    )
end

function ld1b1_fake_stages(;
        generation_error = nothing,
        fit_error = nothing,
        fit_artifact_error = nothing,
        diagnostics_error = nothing,
        sampler_gate = true,
        sampler_gate_error = nothing,
        local_error = nothing,
        calibration_error = nothing,
        trace = Symbol[])
    maybe_throw(error) = error === nothing ? nothing : throw(error)
    return (;
        generate = context -> begin
            push!(trace, :generation)
            maybe_throw(generation_error)
            :simulation
        end,
        fit = (context, simulation) -> begin
            push!(trace, :fit)
            simulation === :simulation || error("wrong fake simulation")
            maybe_throw(fit_error)
            :fit
        end,
        fit_artifact = (context, fit) -> begin
            push!(trace, :fit_artifact)
            fit === :fit || error("wrong fake fit")
            maybe_throw(fit_artifact_error)
            :fit_artifact
        end,
        sampler_diagnostics = (context, fit, fit_artifact) -> begin
            push!(trace, :sampler_diagnostics)
            maybe_throw(diagnostics_error)
            :sampler_diagnostics
        end,
        sampler_gate_passed = (context, diagnostics) -> begin
            push!(trace, :sampler_gate)
            maybe_throw(sampler_gate_error)
            sampler_gate
        end,
        local_dependence = (context, fit, fit_artifact, diagnostics) -> begin
            push!(trace, :local_dependence)
            maybe_throw(local_error)
            :local_dependence
        end,
        calibration = (context, status;
                simulation = nothing,
                diagnostic = nothing,
                failure_code = missing) -> begin
            push!(trace, :calibration)
            maybe_throw(calibration_error)
            (; status, simulation, diagnostic, failure_code)
        end,
    )
end

function ld1b1_primary_cli_args(root::AbstractString; mode = nothing)
    hex(character) = repeat(String(character), 64)
    args = String[]
    mode === nothing || append!(args, ["--mode", String(mode)])
    append!(args, [
        "--protocol", joinpath(root, "protocol.json"),
        "--job-id", "ld1b1_pilot__rep01__s01__null_same_rater",
        "--row-index", "1",
        "--attempt", "1",
        "--attempt-role", "primary",
        "--output", joinpath(root, "plan", "jobs", "job", "attempt_001",
            "job_result.json"),
        "--plan-id", hex("1"),
        "--protocol-plan-id", hex("2"),
        "--protocol-file-sha256", hex("3"),
        "--protocol-content-hash", hex("4"),
        "--ordered-job-rows-sha256", hex("5"),
        "--batch-runner-source-sha256", hex("6"),
        "--local-json-source-sha256", hex("7"),
        "--attempt-archive-source-sha256", hex("8"),
        "--local-dependence-pilot-recovery-source-sha256", hex("9"),
        "--local-dependence-pilot-calibration-semantics-source-sha256",
            hex("a"),
        "--runner-source-sha256", hex("b"),
        "--seed", "101",
        "--fit-seed", "102",
        "--draw-selection-seed", "103",
        "--posterior-predictive-seed", "104",
    ])
    return args
end

function ld1b1_canonical_worker_args(worker, checked, job,
        attempt_root::AbstractString; mode::Symbol = :status,
        reservation_receipt = nothing)
    identity = checked.identity
    execution_root = worker.Batch.ld1b1_execution_root(
        attempt_root,
        identity.plan_id,
    )
    output = worker.Batch.ld1b1_result_path(
        execution_root,
        job.job_id,
        1,
    )
    args = String[
        "--mode", String(mode),
        "--protocol", worker.Batch.LD1B1_DEFAULT_PROTOCOL,
        "--job-id", job.job_id,
        "--row-index", string(job.row_index),
        "--attempt", "1",
        "--attempt-role", "primary",
        "--output", output,
        "--plan-id", identity.plan_id,
        "--protocol-plan-id", identity.protocol_plan_id,
        "--protocol-file-sha256", identity.protocol_file_sha256,
        "--protocol-content-hash", identity.protocol_content_hash,
        "--ordered-job-rows-sha256", identity.ordered_job_rows_sha256,
        "--batch-runner-source-sha256",
            identity.execution_source_identity.batch_runner_source_sha256,
        "--local-json-source-sha256",
            identity.execution_source_identity.local_json_source_sha256,
        "--attempt-archive-source-sha256",
            identity.execution_source_identity.attempt_archive_source_sha256,
        "--local-dependence-pilot-recovery-source-sha256",
            identity.execution_source_identity.
                local_dependence_pilot_recovery_source_sha256,
        "--local-dependence-pilot-calibration-semantics-source-sha256",
            identity.execution_source_identity.
                local_dependence_pilot_calibration_semantics_source_sha256,
        "--runner-source-sha256",
            identity.execution_source_identity.job_runner_source_sha256,
        "--seed", string(job.seed),
        "--fit-seed", string(job.fit_seed),
        "--draw-selection-seed", string(job.draw_selection_seed),
        "--posterior-predictive-seed",
            string(job.posterior_predictive_seed),
    ]
    reservation_receipt === nothing || append!(args, [
        "--reservation-receipt",
        String(reservation_receipt),
    ])
    mode === :execute && push!(args, "--controller-readiness-authorized")
    return (; args, execution_root, output)
end

function ld1b1_replace_cli_value(args, option::AbstractString, value)
    changed = copy(args)
    index = findfirst(==(option), changed)
    index === nothing && error("test option is absent: $option")
    index < length(changed) || error("test option has no value: $option")
    changed[index + 1] = String(value)
    return changed
end

function ld1b1_controller_launch_fixture(worker, checked, job,
        attempt_root::AbstractString, child_pid::Integer)
    identity = checked.identity
    execution_root = worker.Batch.ld1b1_execution_root(
        attempt_root,
        identity.plan_id,
    )
    reservation = worker.Batch.ld1b1_publish_attempt_reservation_create_new(
        execution_root,
        identity,
        job,
        1,
        string("worker-test-", job.row_index),
    )
    attempt_dir = worker.Batch.ld1b1_attempt_dir(
        execution_root,
        job.job_id,
        1,
    )
    mkpath(dirname(attempt_dir))
    mkdir(attempt_dir)
    owner = worker.Batch.ld1b1_publish_canonical_owner_create_new(
        reservation.lineage,
        execution_root,
    )
    launch = worker.Batch.ld1b1_publish_child_launch_create_new(
        reservation.lineage,
        owner.owner,
        Int(child_pid),
        execution_root,
    )
    return (;
        execution_root,
        attempt_dir,
        reservation,
        owner,
        launch,
    )
end

@testset "LD1b1 single-job worker strict CLI remains read-only by default" begin
    mktempdir() do root
        base = ld1b1_primary_cli_args(root)
        status = LD1B1JobWorker.ld1b1_parse_job_args(base)
        @test status.mode === :status
        @test !status.controller_readiness_authorized
        @test status.reservation_receipt === nothing
        @test status.attempt_role === :primary

        @test_throws Exception LD1B1JobWorker.ld1b1_parse_job_args(vcat(
            base,
            ["--mode", "execute"],
        ))
        execute = LD1B1JobWorker.ld1b1_parse_job_args(vcat(
            ld1b1_primary_cli_args(root; mode = :execute),
            [
                "--controller-readiness-authorized",
                "--reservation-receipt",
                joinpath(root, "reservations", "attempt_reservation.json"),
            ],
        ))
        @test execute.mode === :execute
        @test execute.controller_readiness_authorized
        @test basename(execute.reservation_receipt) ==
            "attempt_reservation.json"

        @test_throws Exception LD1B1JobWorker.ld1b1_parse_job_args(vcat(
            base,
            ["--job-id", "duplicate"],
        ))
        @test_throws Exception LD1B1JobWorker.ld1b1_parse_job_args(vcat(
            base,
            ["--test-mode"],
        ))
        @test_throws Exception LD1B1JobWorker.ld1b1_parse_job_args(vcat(
            base,
            ["--controller-readiness-authorized"],
        ))

        remediation = copy(base)
        attempt_index = findfirst(==("--attempt"), remediation)
        role_index = findfirst(==("--attempt-role"), remediation)
        output_index = findfirst(==("--output"), remediation)
        remediation[attempt_index + 1] = "2"
        remediation[role_index + 1] = "remediation"
        remediation[output_index + 1] = joinpath(
            root,
            "plan",
            "jobs",
            "job",
            "attempt_002",
            "job_result.json",
        )
        append!(remediation, [
            "--retry-of", "1",
            "--retry-reason", "prespecified remediation",
            "--primary-result", joinpath(
                root,
                "plan",
                "jobs",
                "job",
                "attempt_001",
                "job_result.json",
            ),
        ])
        parsed_remediation =
            LD1B1JobWorker.ld1b1_parse_job_args(remediation)
        @test parsed_remediation.attempt == 2
        @test parsed_remediation.attempt_role === :remediation
        @test parsed_remediation.retry_of == 1
    end
end

@testset "LD1b1 stage adapter routes all terminal statuses" begin
    worker = LD1B1JobWorker
    fit_context = ld1b1_fake_context(:fit_and_score_diagnostic)
    rejection_context = ld1b1_fake_context(:pre_fit_reject)

    trace = Symbol[]
    completed = worker.ld1b1_run_stage_adapter(
        fit_context,
        ld1b1_fake_stages(; trace),
    )
    @test completed.terminal
    @test completed.terminal_status === :completed
    @test completed.calibration.status === :completed
    @test trace == [
        :generation,
        :fit,
        :fit_artifact,
        :sampler_diagnostics,
        :sampler_gate,
        :local_dependence,
        :calibration,
    ]

    trace = Symbol[]
    rejected = worker.ld1b1_run_stage_adapter(
        rejection_context,
        ld1b1_fake_stages(; trace),
    )
    @test rejected.terminal_status === :pre_fit_rejected
    @test trace == [:generation, :calibration]

    generation_failed = worker.ld1b1_run_stage_adapter(
        fit_context,
        ld1b1_fake_stages(;
            generation_error = worker.LD1B1StageFailure(
                :synthetic_generation_failure),
        ),
    )
    @test generation_failed.terminal_status === :generation_failed
    @test generation_failed.failure_stage === :generation
    @test generation_failed.failure_code === :synthetic_generation_failure

    fit_failed = worker.ld1b1_run_stage_adapter(
        fit_context,
        ld1b1_fake_stages(;
            fit_error = worker.LD1B1StageFailure(:synthetic_fit_failure),
        ),
    )
    @test fit_failed.terminal_status === :fit_failed
    @test fit_failed.failure_stage === :fit
    @test fit_failed.failure_code === :synthetic_fit_failure

    fit_artifact_failed = worker.ld1b1_run_stage_adapter(
        fit_context,
        ld1b1_fake_stages(;
            fit_artifact_error = ErrorException("projection failed"),
        ),
    )
    @test fit_artifact_failed.terminal_status === :fit_failed
    @test fit_artifact_failed.failure_code ===
        :fit_artifact_construction_failed

    sampler_failed = worker.ld1b1_run_stage_adapter(
        fit_context,
        ld1b1_fake_stages(; sampler_gate = false),
    )
    @test sampler_failed.terminal_status === :diagnostic_failed
    @test sampler_failed.failure_component === :sampler_quality_gate
    @test sampler_failed.failure_code === :sampler_quality_gate_failed

    local_failed = worker.ld1b1_run_stage_adapter(
        fit_context,
        ld1b1_fake_stages(;
            local_error = worker.LD1B1StageFailure(
                :synthetic_local_summary_failure),
        ),
    )
    @test local_failed.terminal_status === :diagnostic_failed
    @test local_failed.failure_component === :local_dependence_summary
    @test local_failed.failure_code === :synthetic_local_summary_failure

    @test Set((
        completed.terminal_status,
        rejected.terminal_status,
        generation_failed.terminal_status,
        fit_failed.terminal_status,
        sampler_failed.terminal_status,
    )) == worker.Batch.LD1B1_TERMINAL_STATUSES
    @test Set(worker.Batch.ld1b1_required_evidence_roles(
        sampler_failed.terminal_status)) == Set((
        :generated_data,
        :fit_result,
        :sampler_diagnostics,
        :diagnostic_failure_record,
        :calibration_row,
    ))
end

@testset "LD1b1 canonical invocation identity is reconstructed fail-closed" begin
    worker = LD1B1JobWorker
    mktempdir() do attempt_root
        runner_path = abspath(joinpath(
            @__DIR__,
            "..",
            "scripts",
            "run_local_dependence_calibration_pilot_job.jl",
        ))
        checked = worker.Batch.ld1b1_checked_protocol(
            worker.Batch.LD1B1_DEFAULT_PROTOCOL;
            job_runner_path = runner_path,
            attempt_root,
        )
        job = first(worker.Batch.ld1b1_job_specs(checked))
        command = ld1b1_canonical_worker_args(
            worker,
            checked,
            job,
            attempt_root,
        )
        context = worker.ld1b1_validate_job_invocation(
            worker.ld1b1_parse_job_args(command.args),
        )
        @test context.job.job_id == job.job_id
        @test context.job.row_index == job.row_index
        @test context.runner_source_sha256 ==
            checked.identity.execution_source_identity.job_runner_source_sha256

        @test !ispath(command.execution_root)
        status = worker.ld1b1_status(context)
        @test status.read_only
        @test status.result_state === :absent
        @test !ispath(command.execution_root)

        tamper_cases = (
            ("--row-index", string(job.row_index + 1)),
            ("--seed", string(job.seed + 1)),
            ("--runner-source-sha256", repeat("0", 64)),
            ("--batch-runner-source-sha256", repeat("f", 64)),
        )
        for (option, value) in tamper_cases
            tampered = ld1b1_replace_cli_value(
                command.args,
                option,
                value,
            )
            @test_throws Exception worker.ld1b1_validate_job_invocation(
                worker.ld1b1_parse_job_args(tampered),
            )
        end
    end
end

@testset "LD1b1 execute rejects unfulfilled operational readiness before effects" begin
    worker = LD1B1JobWorker
    mktempdir() do attempt_root
        runner_path = abspath(joinpath(
            @__DIR__,
            "..",
            "scripts",
            "run_local_dependence_calibration_pilot_job.jl",
        ))
        checked = worker.Batch.ld1b1_checked_protocol(
            worker.Batch.LD1B1_DEFAULT_PROTOCOL;
            job_runner_path = runner_path,
            attempt_root,
        )
        @test checked.identity.readiness.canonical_executor_source_pinned
        @test !checked.identity.readiness.bounded_canonical_smoke_passed
        @test !checked.identity.readiness.
            interrupted_attempt_recovery_review_passed
        @test !checked.identity.readiness.operational_execution_authorized

        job = first(worker.Batch.ld1b1_job_specs(checked))
        expected_execution_root = worker.Batch.ld1b1_execution_root(
            attempt_root,
            checked.identity.plan_id,
        )
        reservation_receipt = worker.Batch.ld1b1_attempt_reservation_path(
            expected_execution_root,
            job.job_id,
            1,
        )
        command = ld1b1_canonical_worker_args(
            worker,
            checked,
            job,
            attempt_root;
            mode = :execute,
            reservation_receipt,
        )
        @test command.execution_root == expected_execution_root
        barrier_called = Ref(false)
        stage_trace = Symbol[]
        fake_barrier = context -> begin
            barrier_called[] = true
            (; valid = true)
        end
        error = try
            worker.ld1b1_job_main(
                command.args;
                stages = ld1b1_fake_stages(; trace = stage_trace),
                barrier_validator = fake_barrier,
            )
            nothing
        catch caught
            caught
        end
        @test error isa ErrorException
        message = sprint(showerror, error)
        @test occursin(
            "operational execution is blocked before output/attempt creation",
            message,
        )
        @test occursin("bounded_canonical_smoke_passed", message)
        @test occursin(
            "interrupted_attempt_recovery_review_passed",
            message,
        )
        @test !barrier_called[]
        @test isempty(stage_trace)
        @test !ispath(command.execution_root)
        @test !ispath(command.output)
        @test isempty(readdir(attempt_root))
    end
end

@testset "LD1b1 reservation-owner-launch barrier binds this child PID" begin
    worker = LD1B1JobWorker
    mktempdir() do attempt_root
        runner_path = abspath(joinpath(
            @__DIR__,
            "..",
            "scripts",
            "run_local_dependence_calibration_pilot_job.jl",
        ))
        checked = worker.Batch.ld1b1_checked_protocol(
            worker.Batch.LD1B1_DEFAULT_PROTOCOL;
            job_runner_path = runner_path,
            attempt_root,
        )
        jobs = worker.Batch.ld1b1_job_specs(checked)

        job = jobs[1]
        fixture = ld1b1_controller_launch_fixture(
            worker,
            checked,
            job,
            attempt_root,
            getpid(),
        )
        command = ld1b1_canonical_worker_args(
            worker,
            checked,
            job,
            attempt_root;
            mode = :execute,
            reservation_receipt =
                fixture.reservation.lineage.reservation_path,
        )
        context = worker.ld1b1_validate_job_invocation(
            worker.ld1b1_parse_job_args(command.args),
        )
        barrier = worker.ld1b1_validate_launch_barrier(
            context;
            timeout_seconds = 0.1,
            poll_seconds = 0.01,
        )
        @test barrier.valid
        @test barrier.reservation.reservation_id ==
            fixture.reservation.lineage.reservation.reservation_id
        @test worker.ld1b1_launch_child_pid(barrier.launch) == getpid()

        wrong_job = jobs[2]
        wrong_fixture = ld1b1_controller_launch_fixture(
            worker,
            checked,
            wrong_job,
            attempt_root,
            getpid() + 100_000,
        )
        wrong_command = ld1b1_canonical_worker_args(
            worker,
            checked,
            wrong_job,
            attempt_root;
            mode = :execute,
            reservation_receipt =
                wrong_fixture.reservation.lineage.reservation_path,
        )
        wrong_context = worker.ld1b1_validate_job_invocation(
            worker.ld1b1_parse_job_args(wrong_command.args),
        )
        @test_throws Exception worker.ld1b1_validate_launch_barrier(
            wrong_context;
            timeout_seconds = 0.1,
            poll_seconds = 0.01,
        )
    end
end

@testset "LD1b1 pre-fit terminal transaction is MCMC-free and complete" begin
    worker = LD1B1JobWorker
    mktempdir() do attempt_root
        runner_path = abspath(joinpath(
            @__DIR__,
            "..",
            "scripts",
            "run_local_dependence_calibration_pilot_job.jl",
        ))
        checked = worker.Batch.ld1b1_checked_protocol(
            worker.Batch.LD1B1_DEFAULT_PROTOCOL;
            job_runner_path = runner_path,
            attempt_root,
        )
        job = first(job for job in worker.Batch.ld1b1_job_specs(checked)
            if job.expected_action === :pre_fit_reject)
        command = ld1b1_canonical_worker_args(
            worker,
            checked,
            job,
            attempt_root,
        )
        context = worker.ld1b1_validate_job_invocation(
            worker.ld1b1_parse_job_args(command.args),
        )
        outcome = worker.ld1b1_run_stage_adapter(
            context,
            worker.ld1b1_production_stages(),
        )
        @test outcome.terminal
        @test outcome.terminal_status === :pre_fit_rejected
        @test outcome.fit === nothing
        transaction = worker.ld1b1_prepare_terminal_transaction(
            context,
            outcome,
        )
        @test Set(row.role for row in transaction.manifest) == Set((
            :generated_data,
            :structural_rejection_audit,
            :calibration_row,
        ))
        @test length(transaction.files) == 6
        @test transaction.result.terminal_status === :pre_fit_rejected
        generated_source = only(file for file in transaction.files
            if file.kind === :source && file.role === :generated_data)
        generated = worker.JSON3.read(String(generated_source.bytes))
        @test generated[:data_signature] isa AbstractString
        @test generated[:validation][:data_signature] ==
            generated[:data_signature]
        @test worker.Batch.ld1b1_data_signature(
            generated[:data_signature],
            "generated-data signature",
        ) == generated[:data_signature]
    end
end

@testset "LD1b1 data signatures survive JSON exactly" begin
    worker = LD1B1JobWorker
    signature = typemax(UInt64)
    projected = worker.ld1b1_project_data_signatures((;
        data_signature = signature,
        options_signature = signature,
        nested = (;
            data_signature = signature,
            unsigned_above_int64 = signature,
            small_unsigned = UInt8(7),
        ),
    ))
    expected = string(signature)
    @test projected.data_signature == expected
    @test projected.options_signature == expected
    @test projected.nested.data_signature == expected
    @test projected.nested.unsigned_above_int64 == expected
    @test projected.nested.small_unsigned == UInt8(7)
    bytes = worker.ld1b1_encode_json(projected)
    decoded = worker.JSON3.read(String(bytes))
    @test decoded[:data_signature] == expected
    @test decoded[:options_signature] == expected
    @test decoded[:nested][:data_signature] == expected
    @test decoded[:nested][:unsigned_above_int64] == expected
    before = worker.Batch.ld1b1_json_content_hash_record(
        projected; scope = :fit_artifact_json_payload)
    after = worker.Batch.ld1b1_json_content_hash_record(
        decoded; scope = :fit_artifact_json_payload)
    @test before.value == after.value
    @test before.n_canonical_bytes == after.n_canonical_bytes
    @test worker.Batch.ld1b1_data_signature(
        signature,
        "signature";
        allow_native_uint64 = true,
    ) == expected
    @test worker.Batch.ld1b1_data_signature(expected, "signature") == expected
    @test_throws Exception worker.Batch.ld1b1_data_signature(
        signature, "persisted signature")
    @test_throws Exception worker.Batch.ld1b1_data_signature(
        typemax(Int64), "native signed signature";
        allow_native_uint64 = true)
    @test_throws Exception worker.Batch.ld1b1_data_signature(
        "0$(expected)", "signature")
    @test_throws Exception worker.Batch.ld1b1_data_signature(
        string(BigInt(typemax(UInt64)) + 1), "signature")
    @test_throws Exception worker.Batch.ld1b1_data_signature(
        Float64(signature), "signature")
    @test_throws Exception worker.ld1b1_encode_json((;
        data_signature = signature,
    ))
    @test_throws Exception worker.ld1b1_encode_json((;
        options_signature = signature,
    ))
    @test_throws Exception worker.ld1b1_encode_json((;
        unsigned_above_int64 = signature,
    ))
end

@testset "LD1b1 reserved artifact failures remain nonterminal" begin
    worker = LD1B1JobWorker
    context = ld1b1_fake_context(:fit_and_score_diagnostic)

    unavailable = worker.ld1b1_run_stage_adapter(
        context,
        ld1b1_fake_stages(;
            diagnostics_error = ErrorException("diagnostics unavailable"),
        ),
    )
    @test !unavailable.terminal
    @test ismissing(unavailable.terminal_status)
    @test unavailable.nonterminal_code ===
        :sampler_diagnostics_unavailable

    gate_unavailable = worker.ld1b1_run_stage_adapter(
        context,
        ld1b1_fake_stages(;
            sampler_gate_error = ErrorException("incomplete diagnostics"),
        ),
    )
    @test !gate_unavailable.terminal
    @test gate_unavailable.nonterminal_code ===
        :sampler_diagnostics_unavailable

    calibration_unavailable = worker.ld1b1_run_stage_adapter(
        context,
        ld1b1_fake_stages(;
            calibration_error = ErrorException("serialization unavailable"),
        ),
    )
    @test !calibration_unavailable.terminal
    @test calibration_unavailable.nonterminal_code ===
        :final_calibration_serialization_failed

    reserved_injected_at_generation = worker.ld1b1_run_stage_adapter(
        context,
        ld1b1_fake_stages(;
            generation_error = worker.LD1B1StageFailure(
                :sampler_diagnostics_unavailable),
        ),
    )
    @test reserved_injected_at_generation.terminal
    @test reserved_injected_at_generation.terminal_status ===
        :generation_failed
    @test reserved_injected_at_generation.failure_code ===
        :generation_exception

    @test !worker.ld1b1_worker_owns_control_receipts()
    @test worker.ld1b1_parse_job_args(["--help"]).help
    @test worker.ld1b1_production_stages() isa NamedTuple
end
