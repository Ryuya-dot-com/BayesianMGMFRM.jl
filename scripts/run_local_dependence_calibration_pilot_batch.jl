#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using Sockets
using TOML

const LD1B1_ROOT = normpath(joinpath(@__DIR__, ".."))
const LD1B1_DEFAULT_PROTOCOL = joinpath(
    LD1B1_ROOT,
    "test",
    "fixtures",
    "local_dependence_pilot_protocol_preflight.json",
)
const LD1B1_DEFAULT_ATTEMPT_ROOT = joinpath(
    LD1B1_ROOT,
    "artifacts",
    "local_dependence_pilot",
)
const LD1B1_DEFAULT_BOUNDED_SMOKE_ROOT = joinpath(
    LD1B1_ROOT,
    "artifacts",
    "local_dependence_pilot_bounded_smoke_v1",
)
const LD1B1_DEFAULT_BOUNDED_SMOKE_RECEIPT = joinpath(
    LD1B1_ROOT,
    "test",
    "fixtures",
    "local_dependence_pilot_bounded_canonical_smoke_receipt.json",
)
const LD1B1_DEFAULT_INDEPENDENT_RECOVERY_READINESS_REVIEW = joinpath(
    LD1B1_ROOT,
    "test",
    "fixtures",
    "local_dependence_pilot_independent_recovery_readiness_review.json",
)
const LD1B1_DEFAULT_JOB_RUNNER = joinpath(
    LD1B1_ROOT,
    "scripts",
    "run_local_dependence_calibration_pilot_job.jl",
)
const LD1B1_PROTOCOL_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_protocol_preflight.v1"
const LD1B1_HARNESS_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_batch_execution_harness.v3"
const LD1B1_CHECKPOINT_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_batch_checkpoint.v3"
const LD1B1_JOB_RESULT_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_job_result.v3"
const LD1B1_EVIDENCE_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_job_evidence.v3"
const LD1B1_BOUNDED_SMOKE_AUTHORIZATION_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_bounded_smoke_authorization.v1"
const LD1B1_BOUNDED_SMOKE_RECEIPT_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_bounded_canonical_smoke_receipt.v1"
const LD1B1_INDEPENDENT_RECOVERY_READINESS_REVIEW_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_independent_recovery_readiness_review.v1"
const LD1B1_CANONICAL_EXECUTOR_SOURCE_PIN_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_canonical_executor_source_pin.v1"
const LD1B1_CANONICAL_MANIFEST = "Manifest-v1.10.toml"
const LD1B1_EXPECTED_JOBS = 660
const LD1B1_EXPECTED_FIT_JOBS = 540
const LD1B1_EXPECTED_REJECTION_JOBS = 120
const LD1B1_BOUNDED_SMOKE_ROW_INDEX = 5
const LD1B1_BOUNDED_SMOKE_JOB_ID =
    "ld1b1_pilot__rep01__s05__null_support_at_minimum"
const LD1B1_BOUNDED_SMOKE_TIMEOUT_SECONDS = 7_200
const LD1B1_BOUNDED_SMOKE_TERMINATION_GRACE_SECONDS = 10
const LD1B1_BOUNDED_SMOKE_MAX_RSS_BYTES = 8 * 1024^3
const LD1B1_BOUNDED_SMOKE_MAX_ARCHIVE_BYTES = 1024^3
const LD1B1_BOUNDED_SMOKE_AUTHORIZATION_FILENAME =
    "bounded_smoke_authorization.json"
const LD1B1_MINIMUM_COMPLETED_PER_ELIGIBLE_SCENARIO = 27
const LD1B1_MAXIMUM_FAILURES_PER_ELIGIBLE_SCENARIO = 3
const LD1B1_REQUIRED_REJECTIONS_PER_REJECTION_SCENARIO = 30
const LD1B1_PILOT_CONTRACT_SHA256 =
    "a651515317e0b7636ce47d4e56776c4017d1e6293e3185607c377915f6ad2e5a"
const LD1B1_ORDERED_JOB_ROWS_SHA256 =
    "71eb1f33bb2bdc05495b748608c32af50334216ae607e6ae2be8d50cbf9be574"
const LD1B1_DIAGNOSTIC_CONTRACT_DETAILS_SHA256 =
    "b5877d521d77bbc3b25287a9348d871415460c608f987ea59a7b9992076e9df5"
const LD1B1_DRAW_SELECTION_ALGORITHM =
    :sha256_seeded_rank_without_replacement_v1
const LD1B1_CANONICAL_EXECUTOR_SOURCE_ROWS = (
    (role = :batch_controller,
        path = "scripts/run_local_dependence_calibration_pilot_batch.jl"),
    (role = :canonical_json,
        path = "scripts/local_json.jl"),
    (role = :single_job_worker,
        path = "scripts/run_local_dependence_calibration_pilot_job.jl"),
    (role = :attempt_archive,
        path = "scripts/local_dependence_pilot_attempt_archive.jl"),
    (role = :interruption_recovery,
        path = "scripts/local_dependence_pilot_recovery.jl"),
    (role = :calibration_semantics,
        path = "scripts/local_dependence_pilot_calibration_semantics.jl"),
    (role = :batch_harness_generator,
        path =
            "scripts/generate_local_dependence_pilot_batch_execution_harness.jl"),
)
const LD1B1_TERMINAL_STATUSES = Set((
    :completed,
    :pre_fit_rejected,
    :generation_failed,
    :fit_failed,
    :diagnostic_failed,
))
const LD1B1_CATEGORIZED_FAILURE_STATUSES = Set((
    :generation_failed,
    :fit_failed,
    :diagnostic_failed,
))
const LD1B1_TERMINAL_OUTCOME_CODES = (;
    completed = :completed,
    pre_fit_rejected = :pre_fit_rejected,
    generation_failed = :generation_failed,
    fit_failed = :fit_failed,
    diagnostic_failed = :diagnostic_failed,
)

function ld1b1_execution_context(scope::Symbol = :pilot)
    scope === :pilot && return (;
        execution_scope = :pilot,
        root_namespace = :local_dependence_pilot,
        official_pilot_denominator_eligible = true,
    )
    scope === :bounded_smoke && return (;
        execution_scope = :bounded_smoke,
        root_namespace = :local_dependence_pilot_bounded_smoke_v1,
        official_pilot_denominator_eligible = false,
    )
    error("unsupported LD1b1 execution scope: $scope")
end

function ld1b1_validate_execution_context(value;
        expected_scope::Union{Nothing,Symbol} = nothing)
    ld1b1_require_only_keys(value, (
        :execution_scope,
        :root_namespace,
        :official_pilot_denominator_eligible,
    ), "execution context")
    scope = ld1b1_symbol(value[:execution_scope])
    expected = ld1b1_execution_context(scope)
    observed = (;
        execution_scope = scope,
        root_namespace = ld1b1_symbol(value[:root_namespace]),
        official_pilot_denominator_eligible =
            ld1b1_bool(value[:official_pilot_denominator_eligible]),
    )
    observed == expected || error(
        "execution context differs from the frozen $scope contract")
    expected_scope === nothing || scope === expected_scope || error(
        "execution context has scope $scope; expected $expected_scope")
    return observed
end

function ld1b1_attempt_identity(attempt::Int, execution_context)
    attempt >= 1 || error("attempt number must be positive")
    context = ld1b1_validate_execution_context(execution_context)
    if context.execution_scope === :bounded_smoke
        attempt == 1 || error("bounded smoke permits only verification attempt 1")
        return (;
            number = 1,
            role = :verification,
            counts_toward_primary = false,
        )
    end
    return (;
        number = attempt,
        role = attempt == 1 ? :primary : :remediation,
        counts_toward_primary = attempt == 1,
    )
end

function ld1b1_required_evidence_roles(status::Symbol)
    status === :completed && return (
        :generated_data,
        :fit_result,
        :sampler_diagnostics,
        :local_dependence_summary,
        :calibration_row,
    )
    status === :pre_fit_rejected && return (
        :generated_data,
        :structural_rejection_audit,
        :calibration_row,
    )
    status === :generation_failed && return (
        :generation_failure_record,
        :calibration_row,
    )
    status === :fit_failed && return (
        :generated_data,
        :fit_failure_record,
        :calibration_row,
    )
    status === :diagnostic_failed && return (
        :generated_data,
        :fit_result,
        :sampler_diagnostics,
        :diagnostic_failure_record,
        :calibration_row,
    )
    error("unsupported LD1b1 terminal status: $status")
end

function ld1b1_failure_semantics()
    semantics = (;
        schema =
            "bayesianmgmfrm.local_dependence_pilot_failure_semantics.v1",
        terminal_diagnostic_failures = (;
            sampler_quality_gate = (;
                terminal_status = :diagnostic_failed,
                diagnostics_bundle_required = true,
                sampler_gate_passed = false,
            ),
            local_dependence_summary = (;
                terminal_status = :diagnostic_failed,
                diagnostics_bundle_required = true,
                sampler_gate_passed = true,
            ),
        ),
        nonterminal_artifact_failures = (;
            sampler_diagnostics_unavailable = (;
                terminal_status = missing,
                archive_state = :partial_attempt,
                recovery_action = :review_then_retire_interruption,
                fabricated_diagnostics_bundle_allowed = false,
            ),
            final_calibration_serialization_failed = (;
                terminal_status = missing,
                archive_state = :partial_attempt,
                recovery_action = :review_then_retire_interruption,
                fabricated_calibration_row_allowed = false,
            ),
        ),
        incomplete_artifact_failure_counts_toward_scientific_denominator =
            false,
        incomplete_artifact_failure_may_publish_completed_seal = false,
    )
    declared_nonterminal_codes = Set(propertynames(
        semantics.nonterminal_artifact_failures))
    canonical_nonterminal_codes = Set(LD1B1CalibrationSemantics.
        ld1b1_nonterminal_artifact_failure_codes())
    declared_nonterminal_codes == canonical_nonterminal_codes || error(
        "LD1b1 nonterminal artifact-failure semantics drifted from calibration replay")
    return semantics
end

include(joinpath(@__DIR__, "local_json.jl"))
include(joinpath(@__DIR__, "local_dependence_pilot_attempt_archive.jl"))
include(joinpath(@__DIR__, "local_dependence_pilot_recovery.jl"))
include(joinpath(
    @__DIR__,
    "local_dependence_pilot_calibration_semantics.jl",
))
const LD1B1AttemptArchive = LocalDependencePilotAttemptArchive
const LD1B1Recovery = LocalDependencePilotRecovery
const LD1B1CalibrationSemantics =
    LocalDependencePilotCalibrationSemantics
const LD1B1_CALIBRATION_SEMANTIC_IDENTITY_CACHE =
    Dict{Tuple{String,String},Any}()
const LD1B1_CALIBRATION_SEMANTIC_IDENTITY_CACHE_LOCK = ReentrantLock()
const LD1B1_COMPLETED_ATTEMPT_ARCHIVE_SEAL_SUPPORTED = true
const LD1B1_RETIREMENT_REASON_CODES = Set((
    :interrupted_after_reservation_before_owner,
    :interrupted_after_owner_before_launch_receipt,
    :interrupted_without_result,
    :interrupted_with_semantically_valid_unsealed_result,
    :interrupted_with_invalid_unsealed_result,
))

function ld1b1_batch_usage()
    return """
    Inspect or orchestrate the LD1b1 local-dependence calibration pilot batch.

    The default status mode is read-only. Dry-run mode records deterministic
    selection, command, path, resume, and append-only retry information without
    generating responses or running a model. Aggregate-only mode reads existing
    attempt records and never invokes the job runner.

    Usage:
      julia --project=. scripts/run_local_dependence_calibration_pilot_batch.jl [options]

    Options:
      --mode MODE             status (default), dry-run, execute-primary,
                              execute-retry, bounded-smoke,
                              retire-interrupted, or aggregate-only.
      --protocol PATH         LD1b1 protocol-preflight artifact.
      --attempt-root PATH     Root for plan-scoped job attempts.
      --runner PATH           Single-job runner used only by execute modes.
      --output PATH           Optional batch manifest output.
      --checkpoint PATH       Optional derived checkpoint path.
      --write-checkpoint      Atomically refresh the derived checkpoint.
      --resume                Rescan jobs, then verify/compare the checkpoint.
      --job-id ID             Select a job; repeatable.
      --row-index CSV         Select canonical row indexes.
      --scenario CSV          Select scenario ids.
      --replication CSV       Select pilot replications.
      --max-jobs N            Limit the selected jobs.
      --all                   Explicitly select every matching job.
      --attempt N             Retry or retirement attempt number; default 1.
      --retry-of N            Required in retry mode and must identify attempt 1.
      --retry-reason TEXT     Required nonempty remediation reason.
      --retirement-reason CODE
                              Frozen interruption reason; required only by
                              retire-interrupted.
      --stopped-process-review PATH
                              Externally prepared stopped-process review;
                              required only by retire-interrupted.
      --continue-on-error     Continue after a failed subprocess.

    There is deliberately no force, seed-override, or sampler-override option.
    """
end

ld1b1_file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
ld1b1_project_version() = String(TOML.parsefile(
    joinpath(LD1B1_ROOT, "Project.toml"))["version"])

function ld1b1_json_native(value)
    if value isa NamedTuple || value isa AbstractDict
        return Dict(String(key) => ld1b1_json_native(element)
            for (key, element) in pairs(value))
    elseif value isa AbstractArray || value isa Tuple
        return [ld1b1_json_native(element) for element in value]
    end
    return value
end

function ld1b1_field(value, field::Symbol)
    if value isa NamedTuple
        hasproperty(value, field) || throw(KeyError(field))
        return getproperty(value, field)
    elseif value isa AbstractDict
        haskey(value, field) && return value[field]
        string_field = String(field)
        haskey(value, string_field) && return value[string_field]
    end
    throw(KeyError(field))
end

function ld1b1_canonical_sha256(value)
    io = IOBuffer()
    write_canonical_json(io, value)
    return bytes2hex(sha256(take!(io)))
end

function ld1b1_json_content_hash_record(value; scope::Symbol)
    io = IOBuffer()
    write_canonical_json(io, ld1b1_json_native(value))
    canonical = take!(io)
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(canonical)),
        scope,
        canonicalization = :local_json_sorted_compact,
        n_canonical_bytes = length(canonical),
    )
end

function ld1b1_expected_draw_indices(seed::Int, total::Int, selected::Int)
    seed >= 0 || error("draw-selection seed must be nonnegative")
    total >= 1 || error("total retained draws must be positive")
    1 <= selected <= total || error(
        "selected draw count must be between one and the retained total")
    ranked = [(;
        digest = ld1b1_canonical_sha256((;
            algorithm = LD1B1_DRAW_SELECTION_ALGORITHM,
            seed,
            total_retained_draws = total,
            retained_draw_index = index,
        )),
        index,
    ) for index in 1:total]
    sort!(ranked; by = row -> (row.digest, row.index))
    return Tuple(row.index for row in ranked[1:selected])
end

function ld1b1_with_content_hash(artifact)
    base = artifact isa NamedTuple ? artifact : ld1b1_json_native(artifact)
    return merge(base, (;
        content_hash = (;
            algorithm = :sha256,
            value = ld1b1_canonical_sha256(base),
            covers = :artifact_without_content_hash,
            canonical_format = :local_json_sorted_compact,
        ),
    ))
end

function ld1b1_verify_content_hash(value; label::AbstractString)
    native = ld1b1_json_native(value)
    haskey(native, "content_hash") ||
        error("$label does not contain a content hash")
    record = native["content_hash"]
    record isa AbstractDict || error("$label has an invalid content-hash record")
    ld1b1_require_only_keys(record,
        (:algorithm, :value, :covers, :canonical_format),
        "$label content-hash record")
    String(record["algorithm"]) == "sha256" ||
        error("$label does not use SHA-256 content hashing")
    String(record["covers"]) == "artifact_without_content_hash" ||
        error("$label content hash has the wrong coverage")
    String(record["canonical_format"]) == "local_json_sorted_compact" ||
        error("$label content hash has the wrong canonical format")
    stored = ld1b1_require_sha256(record["value"],
        "$label content hash")
    delete!(native, "content_hash")
    recomputed = ld1b1_canonical_sha256(native)
    stored == recomputed || error("$label content hash does not match its contents")
    return stored
end

ld1b1_string(value) = String(value)
function ld1b1_int(value)
    value isa Integer && !(value isa Bool) ||
        error("expected an integer JSON value")
    return Int(value)
end

function ld1b1_bool(value)
    value isa Bool || error("expected a boolean JSON value")
    return value
end

function ld1b1_float(value)
    value isa Real && !(value isa Bool) ||
        error("expected a numeric JSON value")
    result = Float64(value)
    isfinite(result) || error("expected a finite numeric JSON value")
    return result
end

function ld1b1_optional_float(value)
    (value === nothing || ismissing(value)) && return missing
    return ld1b1_float(value)
end
ld1b1_symbol(value) = Symbol(String(value))

function ld1b1_get(object, key::Symbol, default = missing)
    haskey(object, key) || return default
    value = object[key]
    value === nothing && return default
    ismissing(value) && return default
    return value
end

function ld1b1_split_strings!(values::Vector{String}, text::AbstractString)
    for part in split(text, ",")
        value = strip(part)
        isempty(value) || push!(values, String(value))
    end
    return values
end

function ld1b1_split_ints!(values::Vector{Int}, text::AbstractString)
    for part in split(text, ",")
        value = strip(part)
        isempty(value) || push!(values, parse(Int, value))
    end
    return values
end

function ld1b1_parse_mode(value::AbstractString)
    normalized = replace(lowercase(String(value)), '_' => '-')
    normalized in (
        "status",
        "dry-run",
        "execute-primary",
        "execute-retry",
        "bounded-smoke",
        "retire-interrupted",
        "aggregate-only",
    ) || error("unsupported --mode: $value")
    return Symbol(replace(normalized, '-' => '_'))
end

function ld1b1_parse_args(args)
    mode = :status
    protocol = LD1B1_DEFAULT_PROTOCOL
    attempt_root = LD1B1_DEFAULT_ATTEMPT_ROOT
    attempt_root_supplied = false
    runner = LD1B1_DEFAULT_JOB_RUNNER
    output = nothing
    output_supplied = false
    checkpoint = nothing
    write_checkpoint = false
    resume = false
    job_ids = String[]
    row_indexes = Int[]
    scenarios = String[]
    replications = Int[]
    max_jobs = nothing
    run_all = false
    attempt = 1
    retry_of = nothing
    retry_reason = nothing
    retirement_reason = nothing
    stopped_process_review = nothing
    stop_on_error = true

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--mode"
            index < length(args) || error("--mode requires a value")
            mode = ld1b1_parse_mode(args[index + 1])
            index += 2
        elseif arg == "--protocol"
            index < length(args) || error("--protocol requires a path")
            protocol = abspath(args[index + 1])
            index += 2
        elseif arg == "--attempt-root"
            index < length(args) || error("--attempt-root requires a path")
            attempt_root = abspath(args[index + 1])
            attempt_root_supplied = true
            index += 2
        elseif arg == "--runner"
            index < length(args) || error("--runner requires a path")
            runner = abspath(args[index + 1])
            index += 2
        elseif arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            output_supplied = true
            index += 2
        elseif arg == "--checkpoint"
            index < length(args) || error("--checkpoint requires a path")
            checkpoint = abspath(args[index + 1])
            index += 2
        elseif arg == "--write-checkpoint"
            write_checkpoint = true
            index += 1
        elseif arg == "--resume"
            resume = true
            index += 1
        elseif arg == "--job-id"
            index < length(args) || error("--job-id requires an id")
            push!(job_ids, String(args[index + 1]))
            index += 2
        elseif arg == "--row-index"
            index < length(args) || error("--row-index requires a CSV value")
            ld1b1_split_ints!(row_indexes, args[index + 1])
            index += 2
        elseif arg == "--scenario"
            index < length(args) || error("--scenario requires a CSV value")
            ld1b1_split_strings!(scenarios, args[index + 1])
            index += 2
        elseif arg == "--replication"
            index < length(args) || error("--replication requires a CSV value")
            ld1b1_split_ints!(replications, args[index + 1])
            index += 2
        elseif arg == "--max-jobs"
            index < length(args) || error("--max-jobs requires an integer")
            max_jobs = parse(Int, args[index + 1])
            max_jobs >= 0 || error("--max-jobs must be non-negative")
            index += 2
        elseif arg == "--all"
            run_all = true
            index += 1
        elseif arg == "--attempt"
            index < length(args) || error("--attempt requires an integer")
            attempt = parse(Int, args[index + 1])
            1 <= attempt <= 999 || error("--attempt must be in 1:999")
            index += 2
        elseif arg == "--retry-of"
            index < length(args) || error("--retry-of requires an integer")
            retry_of = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--retry-reason"
            index < length(args) || error("--retry-reason requires text")
            retry_reason = strip(String(args[index + 1]))
            isempty(retry_reason) && error("--retry-reason must not be empty")
            index += 2
        elseif arg == "--retirement-reason"
            index < length(args) || error(
                "--retirement-reason requires a value")
            retirement_reason = Symbol(replace(
                lowercase(strip(String(args[index + 1]))), '-' => '_'))
            retirement_reason in LD1B1_RETIREMENT_REASON_CODES || error(
                "unsupported --retirement-reason: $(args[index + 1])")
            index += 2
        elseif arg == "--stopped-process-review"
            index < length(args) || error(
                "--stopped-process-review requires a path")
            stopped_process_review = abspath(args[index + 1])
            index += 2
        elseif arg == "--continue-on-error"
            stop_on_error = false
            index += 1
        elseif arg in ("-h", "--help")
            println(ld1b1_batch_usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end

    selectors_present = !isempty(job_ids) || !isempty(row_indexes) ||
        !isempty(scenarios) || !isempty(replications)
    execute_mode = mode in (:execute_primary, :execute_retry)
    if execute_mode && !run_all && max_jobs === nothing && !selectors_present
        error("execution requires --all, --max-jobs, or an explicit selector")
    end
    if mode === :execute_primary
        attempt == 1 || error("execute-primary always uses attempt 1")
        retry_of === nothing || error("--retry-of is unavailable in primary mode")
        retry_reason === nothing ||
            error("--retry-reason is unavailable in primary mode")
    elseif mode === :execute_retry
        attempt > 1 || error("execute-retry requires --attempt greater than 1")
        retry_of == 1 || error("execute-retry requires --retry-of 1")
        retry_reason === nothing && error("execute-retry requires --retry-reason")
        run_all && error("execute-retry cannot use --all")
        max_jobs === nothing || max_jobs == 1 ||
            error("execute-retry may select only one job")
    elseif mode === :bounded_smoke
        selectors_present && error(
            "bounded-smoke uses only the frozen canonical row 5")
        run_all && error("bounded-smoke does not accept --all")
        max_jobs === nothing || error(
            "bounded-smoke freezes max-jobs at one internally")
        attempt_root_supplied && error(
            "bounded-smoke uses its dedicated fixed attempt root")
        output_supplied && error(
            "bounded-smoke uses its fixed immutable receipt path")
        !resume || error("bounded-smoke does not accept --resume")
        !write_checkpoint || error(
            "bounded-smoke never writes a pilot checkpoint")
        stop_on_error || error(
            "bounded-smoke cannot continue after an error")
        attempt_root = LD1B1_DEFAULT_BOUNDED_SMOKE_ROOT
        output = LD1B1_DEFAULT_BOUNDED_SMOKE_RECEIPT
    elseif mode === :retire_interrupted
        length(job_ids) == 1 || error(
            "retire-interrupted requires exactly one --job-id")
        isempty(row_indexes) && isempty(scenarios) && isempty(replications) ||
            error("retire-interrupted accepts only --job-id selection")
        !run_all || error("retire-interrupted cannot use --all")
        max_jobs === nothing || error(
            "retire-interrupted cannot use --max-jobs")
        retry_of === nothing || error(
            "--retry-of is unavailable in retire-interrupted mode")
        retry_reason === nothing || error(
            "--retry-reason is unavailable in retire-interrupted mode")
        retirement_reason === nothing && error(
            "retire-interrupted requires --retirement-reason")
        stopped_process_review === nothing && error(
            "retire-interrupted requires --stopped-process-review")
        !resume || error("retire-interrupted cannot use --resume")
        !write_checkpoint || error(
            "retire-interrupted cannot use --write-checkpoint")
    else
        attempt == 1 || error("--attempt is available only in execute-retry mode")
        retry_of === nothing || error("--retry-of is available only in execute-retry mode")
        retry_reason === nothing ||
            error("--retry-reason is available only in execute-retry mode")
        retirement_reason === nothing || error(
            "--retirement-reason is available only in retire-interrupted mode")
        stopped_process_review === nothing || error(
            "--stopped-process-review is available only in retire-interrupted mode")
    end
    if mode === :aggregate_only && selectors_present
        error("aggregate-only mode always audits the complete canonical batch")
    end
    if mode === :dry_run && write_checkpoint
        error("dry-run mode does not materialize checkpoints")
    end
    resume && mode === :dry_run &&
        error("dry-run mode does not consume a checkpoint")

    return (;
        mode,
        protocol,
        attempt_root,
        runner,
        output,
        checkpoint,
        write_checkpoint = write_checkpoint || execute_mode,
        resume,
        job_ids,
        row_indexes,
        scenarios,
        replications,
        max_jobs,
        run_all,
        attempt,
        retry_of,
        retry_reason,
        retirement_reason,
        stopped_process_review,
        stop_on_error,
    )
end

function ld1b1_record_path(path::AbstractString)
    relative = relpath(normpath(path), LD1B1_ROOT)
    return startswith(relative, "..") ? normpath(path) : relative
end

function ld1b1_archive_record_path(path::AbstractString,
        execution_root::AbstractString)
    normalized = normpath(path)
    root = normpath(execution_root)
    if ld1b1_path_within(normalized, root)
        relative = relpath(normalized, root)
        return relative == "." ? "." : relative
    end
    return ld1b1_record_path(normalized)
end

function ld1b1_path_within(path::AbstractString, boundary::AbstractString)
    relative = relpath(normpath(path), normpath(boundary))
    return relative == "." ||
        !(relative == ".." || startswith(relative, string("..", Base.Filesystem.path_separator)))
end

function ld1b1_reject_symlink_components(path::AbstractString,
        boundary::AbstractString)
    target = normpath(path)
    root = normpath(boundary)
    ld1b1_path_within(target, root) ||
        error("path escapes its declared execution boundary")
    current = target
    while ld1b1_path_within(current, root)
        ispath(current) && islink(current) &&
            error("symbolic links are not allowed in the execution tree: $current")
        current == root && break
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    return true
end

function ld1b1_unexpected_inventory_rows(path::AbstractString)
    root = normpath(path)
    rows = NamedTuple[]
    function visit(current::String, relative::String)
        if islink(current)
            target = readlink(current)
            push!(rows, (;
                path = relative,
                kind = :symbolic_link,
                bytes = ncodeunits(target),
                sha256 = bytes2hex(sha256(codeunits(target))),
            ))
        elseif isfile(current)
            push!(rows, (;
                path = relative,
                kind = :file,
                bytes = filesize(current),
                sha256 = ld1b1_file_sha256(current),
            ))
        elseif isdir(current)
            push!(rows, (;
                path = relative,
                kind = :directory,
                bytes = 0,
                sha256 = ld1b1_canonical_sha256((;
                    kind = :directory,
                    path = relative,
                )),
            ))
            for name in sort(readdir(current))
                child_relative = relative == "." ? name :
                    joinpath(relative, name)
                visit(joinpath(current, name), child_relative)
            end
        elseif ispath(current)
            metadata = lstat(current)
            material = (;
                kind = :other,
                mode = metadata.mode,
                size = metadata.size,
            )
            push!(rows, (;
                path = relative,
                kind = :other,
                bytes = Int(metadata.size),
                sha256 = ld1b1_canonical_sha256(material),
            ))
        else
            push!(rows, (;
                path = relative,
                kind = :missing,
                bytes = 0,
                sha256 = ld1b1_canonical_sha256((; kind = :missing)),
            ))
        end
        return nothing
    end
    visit(root, ".")
    sort!(rows; by = row -> (row.path, string(row.kind)))
    return Tuple(rows)
end

function ld1b1_unexpected_entry(path::AbstractString,
        execution_root::AbstractString)
    inventory = ld1b1_unexpected_inventory_rows(path)
    root = only(row for row in inventory if row.path == ".")
    directory = root.kind === :directory
    return (;
        path = ld1b1_archive_record_path(path, execution_root),
        kind = root.kind,
        bytes = directory ? sum(row.bytes for row in inventory) : root.bytes,
        sha256 = directory ? ld1b1_canonical_sha256(inventory) : root.sha256,
    )
end

function ld1b1_unexpected_marker(path::AbstractString,
        execution_root::AbstractString, marker::AbstractString)
    label = String(marker)
    return (;
        path = string(ld1b1_archive_record_path(path, execution_root),
            "/<", label, ">"),
        kind = :logical_marker,
        bytes = ncodeunits(label),
        sha256 = bytes2hex(sha256(codeunits(label))),
    )
end

function ld1b1_sorted_unexpected(entries)
    rows = unique(collect(entries))
    sort!(rows; by = row ->
        (row.path, string(row.kind), row.bytes, row.sha256))
    return Tuple(rows)
end

function ld1b1_require_realpath_containment(path::AbstractString,
        boundary::AbstractString)
    ld1b1_reject_symlink_components(path, boundary)
    ispath(path) || error("contained path does not exist")
    ispath(boundary) || error("containment boundary does not exist")
    ld1b1_path_within(realpath(path), realpath(boundary)) ||
        error("resolved path escapes its declared execution boundary")
    return true
end

function ld1b1_require_exact_keys(object, keys::Tuple, label::AbstractString)
    return ld1b1_require_only_keys(object, keys, label)
end

function ld1b1_require_keys(object, keys::Tuple, label::AbstractString)
    all(key -> haskey(object, key), keys) || error("$label is incomplete")
    return nothing
end

function ld1b1_require_only_keys(object, keys::Tuple, label::AbstractString)
    observed = Set(String(key) for key in Base.keys(object))
    expected = Set(String(key) for key in keys)
    observed == expected || error("$label has an unexpected field set")
    return nothing
end

function ld1b1_require_sha256(value, label::AbstractString)
    text = ld1b1_string(value)
    occursin(r"^[0-9a-f]{64}$", text) || error("$label is not a SHA-256 digest")
    return text
end

# Canonical evidence and archive validation accepts only the lossless decimal
# string projection. `allow_native_uint64` is reserved for the worker's
# in-memory projection boundary, before JSON serialization.
function ld1b1_data_signature(value, label::AbstractString;
        allow_native_uint64::Bool = false)
    if value isa AbstractString
        text = String(value)
        occursin(r"^(0|[1-9][0-9]*)$", text) || error(
            "$label is not a canonical decimal data signature")
        tryparse(UInt64, text) === nothing && error(
            "$label is outside the UInt64 data-signature range")
        return text
    elseif allow_native_uint64 && value isa UInt64
        return string(value)
    end
    error(allow_native_uint64 ?
        "$label is neither a canonical decimal string nor a native UInt64" :
        "$label is not a canonical decimal string data signature")
end

const LD1B1_CANONICAL_FIT_ARTIFACT_DATA_SIGNATURE_PATHS = (
    ("manifest", "data", "data_signature"),
    ("manifest", "validation", "data_signature"),
    ("manifest", "fit", "data_signature"),
    ("manifest", "fit", "design_identity", "data_signature"),
    ("manifest", "rating_design", "data_signature"),
    ("manifest", "rating_design", "anchor_linking", "data_signature"),
    ("reproducibility", "data_signature"),
    ("archive_manifest", "manifest", "data_signature"),
    ("archive_manifest", "reproducibility", "data_signature"),
)

function ld1b1_collect_data_signature_fields(value,
        path::Tuple = ())
    rows = NamedTuple[]
    if value isa NamedTuple
        for field in keys(value)
            field_name = String(field)
            child_path = (path..., field_name)
            child = getproperty(value, field)
            if field_name == "data_signature"
                push!(rows, (; path = child_path, value = child))
            else
                append!(rows,
                    ld1b1_collect_data_signature_fields(child, child_path))
            end
        end
    elseif value isa AbstractDict
        for (field, child) in pairs(value)
            field_name = String(field)
            child_path = (path..., field_name)
            if field_name == "data_signature"
                push!(rows, (; path = child_path, value = child))
            else
                append!(rows,
                    ld1b1_collect_data_signature_fields(child, child_path))
            end
        end
    elseif value isa AbstractArray || value isa Tuple
        for (index, child) in pairs(value)
            child_path = (path..., "[$index]")
            append!(rows,
                ld1b1_collect_data_signature_fields(child, child_path))
        end
    end
    sort!(rows; by = row -> join(row.path, '.'))
    return rows
end

function ld1b1_validate_canonical_fit_artifact_data_signatures(
        artifact, payload_data_signature)
    payload_signature = ld1b1_data_signature(
        payload_data_signature, "fit-result payload data signature")
    rows = ld1b1_collect_data_signature_fields(artifact)
    expected = Set(LD1B1_CANONICAL_FIT_ARTIFACT_DATA_SIGNATURE_PATHS)
    observed = Set(row.path for row in rows)
    if observed != expected || length(rows) != length(expected)
        missing_paths = sort!(collect(setdiff(expected, observed));
            by = path -> join(path, '.'))
        additional_paths = sort!(collect(setdiff(observed, expected));
            by = path -> join(path, '.'))
        error(string(
            "fit-artifact data-signature path set is noncanonical; missing=",
            join((join(path, '.') for path in missing_paths), ','),
            "; additional=",
            join((join(path, '.') for path in additional_paths), ','),
        ))
    end
    for row in rows
        signature = ld1b1_data_signature(
            row.value, "fit-artifact $(join(row.path, '.'))")
        signature == payload_signature || error(
            "fit-artifact $(join(row.path, '.')) differs from its evidence payload")
    end
    return (;
        data_signature = payload_signature,
        paths = LD1B1_CANONICAL_FIT_ARTIFACT_DATA_SIGNATURE_PATHS,
        n_paths = length(expected),
    )
end

function ld1b1_sha256_record_value(record, label::AbstractString)
    ld1b1_require_only_keys(record, (:algorithm, :value), label)
    ld1b1_symbol(record[:algorithm]) === :sha256 ||
        error("$label does not use SHA-256")
    return ld1b1_require_sha256(record[:value], "$label value")
end

function ld1b1_job_id(row)
    scenario = ld1b1_string(row[:scenario_id])
    occursin(r"^[a-z0-9_]+$", scenario) ||
        error("scenario id is not path-safe: $scenario")
    replication = lpad(string(ld1b1_int(row[:replication])), 2, '0')
    scenario_index = lpad(string(ld1b1_int(row[:scenario_index])), 2, '0')
    return string(
        "ld1b1_pilot__rep", replication,
        "__s", scenario_index,
        "__", scenario,
    )
end

function ld1b1_source_identity(protocol)
    generator = protocol[:generator]
    rows = (
        (field = :script_source_sha256,
            path = "scripts/generate_local_dependence_pilot_protocol_preflight.jl"),
        (field = :pilot_source_sha256,
            path = "src/local_dependence_calibration_pilot.jl"),
        (field = :diagnostic_source_sha256,
            path = "src/bayesian_fit.jl"),
        (field = :calibration_source_sha256,
            path = "src/local_dependence_calibration.jl"),
        (field = :simulation_source_sha256,
            path = "src/local_dependence_simulation.jl"),
    )
    source_rows = Tuple((function ()
        absolute = joinpath(LD1B1_ROOT, row.path)
        isfile(absolute) || error("required source is missing: $(row.path)")
        recorded = ld1b1_string(generator[row.field])
        actual = ld1b1_file_sha256(absolute)
        recorded == actual ||
            error("protocol source identity mismatch: $(row.path)")
        (;
            path = row.path,
            recorded_sha256 = recorded,
            actual_sha256 = actual,
            matches = true,
        )
    end)() for row in rows)

    environment = generator[:environment_provenance]
    project_path = joinpath(LD1B1_ROOT, "Project.toml")
    manifest_toml = ld1b1_string(environment[:manifest])
    manifest_toml == basename(manifest_toml) ||
        error("protocol manifest identity must be a repository-root basename")
    manifest_toml == LD1B1_CANONICAL_MANIFEST || error(
        "protocol manifest identity must use $(LD1B1_CANONICAL_MANIFEST)")
    manifest_path = joinpath(LD1B1_ROOT, manifest_toml)
    isfile(manifest_path) ||
        error("protocol manifest identity is missing: $manifest_toml")
    project_sha = ld1b1_file_sha256(project_path)
    manifest_sha = ld1b1_file_sha256(manifest_path)
    project_sha == ld1b1_string(environment[:project_sha256]) ||
        error("Project.toml differs from the protocol-preflight identity")
    manifest_sha == ld1b1_string(environment[:manifest_sha256]) ||
        error("$manifest_toml differs from the protocol-preflight identity")
    return (;
        source_rows,
        project_toml_sha256 = project_sha,
        manifest_toml,
        manifest_toml_sha256 = manifest_sha,
        all_sources_match = true,
        environment_matches = true,
    )
end

function ld1b1_is_canonical_repository_relative_path(path::AbstractString)
    value = String(path)
    isempty(value) && return false
    startswith(value, "/") && return false
    occursin('\\', value) && return false
    occursin(r"^[A-Za-z]:", value) && return false
    segments = split(value, '/'; keepempty = true)
    return all(segment ->
        !isempty(segment) && segment != "." && segment != "..",
        segments)
end

function ld1b1_validate_canonical_executor_source_pin(protocol)
    haskey(protocol, :canonical_executor_source_pin) || error(
        "protocol does not contain the canonical executor source pin")
    pin = protocol[:canonical_executor_source_pin]
    ld1b1_require_only_keys(pin, (
        :schema,
        :status,
        :source_rows,
        :checks,
        :evidence_boundary,
        :pin_id,
    ), "canonical executor source pin")
    ld1b1_string(pin[:schema]) ==
        LD1B1_CANONICAL_EXECUTOR_SOURCE_PIN_SCHEMA || error(
        "canonical executor source pin has an unexpected schema")
    ld1b1_symbol(pin[:status]) ===
        :canonical_executor_source_pin_recorded || error(
        "canonical executor source pin was not recorded")

    rows = collect(pin[:source_rows])
    length(rows) == length(LD1B1_CANONICAL_EXECUTOR_SOURCE_ROWS) || error(
        "canonical executor source pin must contain exactly seven source rows")
    verified_rows = NamedTuple[]
    digests = Dict{Symbol,String}()
    for (index, (row, expected)) in enumerate(zip(
            rows, LD1B1_CANONICAL_EXECUTOR_SOURCE_ROWS))
        label = "canonical executor source-pin row $index"
        ld1b1_require_only_keys(row, (:role, :path, :sha256), label)
        role = ld1b1_symbol(row[:role])
        path = ld1b1_string(row[:path])
        role === expected.role || error(
            "$label has the wrong role")
        path == expected.path || error(
            "$label has the wrong canonical path")
        ld1b1_is_canonical_repository_relative_path(path) || error(
            "$label is not repository relative")
        absolute = joinpath(LD1B1_ROOT, path)
        isfile(absolute) && !islink(absolute) || error(
            "canonical executor source is not a regular file: $path")
        recorded = ld1b1_require_sha256(
            row[:sha256], "$label SHA-256")
        actual = ld1b1_file_sha256(absolute)
        recorded == actual || error(
            "canonical executor source pin mismatch: $path")
        haskey(digests, role) && error(
            "canonical executor source pin repeats role $role")
        digests[role] = actual
        push!(verified_rows, (;
            role,
            path,
            recorded_sha256 = recorded,
            actual_sha256 = actual,
            matches = true,
        ))
    end

    checks = pin[:checks]
    check_fields = (
        :exact_source_count,
        :canonical_source_order,
        :unique_roles,
        :unique_paths,
        :repository_relative_paths,
        :regular_files_present,
        :source_sha256_matches,
    )
    ld1b1_require_only_keys(
        checks, check_fields, "canonical executor source-pin checks")
    all(field -> ld1b1_bool(checks[field]), check_fields) || error(
        "canonical executor source pin contains a failed check")

    boundary = pin[:evidence_boundary]
    boundary_fields = (
        :authorization_scope,
        :canonical_executor_source_pinned,
        :bounded_canonical_smoke_passed,
        :independent_recovery_readiness_review_passed,
        :operational_execution_authorized,
        :response_data_generated,
        :model_fit_run,
        :mcmc_run,
        :pilot_execution_started,
        :pilot_execution_completed,
        :scientific_pilot_outcomes,
        :scientific_pilot_denominator,
    )
    ld1b1_require_only_keys(boundary, boundary_fields,
        "canonical executor source-pin evidence boundary")
    ld1b1_symbol(boundary[:authorization_scope]) ===
        :source_identity_only || error(
        "canonical executor source pin has the wrong authorization scope")
    ld1b1_bool(boundary[:canonical_executor_source_pinned]) || error(
        "canonical executor source pin does not claim its source-only boundary")
    for field in (
            :bounded_canonical_smoke_passed,
            :independent_recovery_readiness_review_passed,
            :operational_execution_authorized,
            :response_data_generated,
            :model_fit_run,
            :mcmc_run,
            :pilot_execution_started,
            :pilot_execution_completed,
        )
        !ld1b1_bool(boundary[field]) || error(
            "canonical executor source pin exceeds its evidence boundary: $field")
    end
    ld1b1_int(boundary[:scientific_pilot_outcomes]) == 0 || error(
        "canonical executor source pin cannot contain pilot outcomes")
    ld1b1_int(boundary[:scientific_pilot_denominator]) ==
        LD1B1_EXPECTED_JOBS || error(
        "canonical executor source pin has the wrong pilot denominator")

    pin_id = pin[:pin_id]
    ld1b1_require_only_keys(pin_id, (
        :algorithm,
        :value,
        :covers,
        :canonical_format,
    ), "canonical executor source-pin id")
    ld1b1_symbol(pin_id[:algorithm]) === :sha256 || error(
        "canonical executor source pin does not use SHA-256")
    ld1b1_symbol(pin_id[:covers]) ===
        :canonical_executor_source_pin_without_pin_id || error(
        "canonical executor source pin has the wrong hash coverage")
    ld1b1_symbol(pin_id[:canonical_format]) ===
        :local_json_sorted_compact || error(
        "canonical executor source pin has the wrong canonical format")
    recorded_pin_id = ld1b1_require_sha256(
        pin_id[:value], "canonical executor source-pin id")
    pin_material = ld1b1_json_native(pin)
    delete!(pin_material, "pin_id")
    recorded_pin_id == ld1b1_canonical_sha256(pin_material) || error(
        "canonical executor source-pin id does not match its contents")

    execution_source_identity = (;
        batch_runner_source_sha256 = digests[:batch_controller],
        local_json_source_sha256 = digests[:canonical_json],
        job_runner_source_sha256 = digests[:single_job_worker],
        attempt_archive_source_sha256 = digests[:attempt_archive],
        local_dependence_pilot_recovery_source_sha256 =
            digests[:interruption_recovery],
        local_dependence_pilot_calibration_semantics_source_sha256 =
            digests[:calibration_semantics],
    )
    return (;
        pin_id = recorded_pin_id,
        source_rows = Tuple(verified_rows),
        execution_source_identity,
        batch_harness_generator_source_sha256 =
            digests[:batch_harness_generator],
        valid = true,
    )
end

function ld1b1_validate_frozen_pilot_contract(protocol)
    contract = protocol[:pilot_contract]
    ld1b1_canonical_sha256(ld1b1_json_native(contract)) ==
        LD1B1_PILOT_CONTRACT_SHA256 ||
        error("LD1b1 pilot contract differs from the frozen canonical contract")
    sampler = contract[:sampler]
    ld1b1_require_only_keys(sampler, (
        :backend,
        :algorithm,
        :chains,
        :warmup_per_chain,
        :draws_per_chain,
        :total_retained_draws,
        :target_accept,
        :max_depth,
        :metric,
        :ad_backend,
        :split_chains,
        :diagnostic_draws,
        :diagnostic_draw_policy,
        :posterior_predictive_replicates_per_draw,
    ), "frozen LD1b1 sampler contract")
    observed_sampler = (;
        backend = ld1b1_symbol(sampler[:backend]),
        algorithm = ld1b1_symbol(sampler[:algorithm]),
        chains = ld1b1_int(sampler[:chains]),
        warmup_per_chain = ld1b1_int(sampler[:warmup_per_chain]),
        draws_per_chain = ld1b1_int(sampler[:draws_per_chain]),
        total_retained_draws = ld1b1_int(sampler[:total_retained_draws]),
        target_accept = ld1b1_float(sampler[:target_accept]),
        max_depth = ld1b1_int(sampler[:max_depth]),
        metric = ld1b1_symbol(sampler[:metric]),
        ad_backend = ld1b1_symbol(sampler[:ad_backend]),
        split_chains = ld1b1_bool(sampler[:split_chains]),
        diagnostic_draws = ld1b1_int(sampler[:diagnostic_draws]),
        diagnostic_draw_policy =
            ld1b1_symbol(sampler[:diagnostic_draw_policy]),
        posterior_predictive_replicates_per_draw = ld1b1_int(
            sampler[:posterior_predictive_replicates_per_draw]),
    )
    expected_sampler = (;
        backend = :advancedhmc,
        algorithm = :nuts,
        chains = 4,
        warmup_per_chain = 500,
        draws_per_chain = 500,
        total_retained_draws = 2_000,
        target_accept = 0.9,
        max_depth = 10,
        metric = :diagonal,
        ad_backend = :ForwardDiff,
        split_chains = true,
        diagnostic_draws = 250,
        diagnostic_draw_policy = :distinct_without_replacement,
        posterior_predictive_replicates_per_draw = 1,
    )
    observed_sampler == expected_sampler ||
        error("LD1b1 sampler contract differs from the frozen pilot profile")

    quality = contract[:quality_requirements]
    ld1b1_require_only_keys(quality, (
        :diagnostic_contract,
        :diagnostic_contract_details,
        :rhat_method,
        :primary_rhat_field,
        :maximum_rhat,
        :ess_method,
        :primary_ess_fields,
        :primary_flag_field,
        :tail_probability,
        :minimum_bulk_ess,
        :minimum_tail_ess,
        :maximum_divergences,
        :maximum_depth_hits,
        :e_bfmi_field,
        :e_bfmi_completeness_field,
        :e_bfmi_chain_coverage_required,
        :minimum_e_bfmi,
    ), "frozen LD1b1 sampler-quality contract")
    ld1b1_symbol(quality[:diagnostic_contract]) ===
        :rank_normalized_rhat_bulk_tail_ess_v1 ||
        error("LD1b1 diagnostic contract differs from the frozen profile")
    ld1b1_canonical_sha256(ld1b1_json_native(
        quality[:diagnostic_contract_details])) ==
        LD1B1_DIAGNOSTIC_CONTRACT_DETAILS_SHA256 || error(
        "LD1b1 diagnostic-contract details differ from the frozen profile")
    checks = (
        ld1b1_symbol(quality[:rhat_method]) === :rank_normalized,
        ld1b1_symbol(quality[:primary_rhat_field]) ===
            :rank_normalized_rhat,
        ld1b1_float(quality[:maximum_rhat]) == 1.01,
        ld1b1_symbol(quality[:ess_method]) === :bulk_and_tail,
        Tuple(ld1b1_symbol(value) for value in
            quality[:primary_ess_fields]) == (:bulk_ess, :tail_ess),
        ld1b1_symbol(quality[:primary_flag_field]) ===
            :rank_normalized_flag,
        ld1b1_float(quality[:tail_probability]) == 0.1,
        ld1b1_float(quality[:minimum_bulk_ess]) == 400.0,
        ld1b1_float(quality[:minimum_tail_ess]) == 400.0,
        ld1b1_int(quality[:maximum_divergences]) == 0,
        ld1b1_int(quality[:maximum_depth_hits]) == 0,
        ld1b1_symbol(quality[:e_bfmi_field]) === :e_bfmi,
        ld1b1_symbol(quality[:e_bfmi_completeness_field]) ===
            :e_bfmi_complete,
        ld1b1_bool(quality[:e_bfmi_chain_coverage_required]),
        ld1b1_float(quality[:minimum_e_bfmi]) == 0.3,
    )
    all(checks) ||
        error("LD1b1 sampler-quality gates differ from the frozen pilot profile")
    return true
end

function ld1b1_execution_readiness(;
        protocol_execution_authorized::Bool,
        job_runner_path::AbstractString,
        attempt_root::AbstractString,
        canonical_executor_source_pin_validated::Bool = false,
        bounded_canonical_smoke_passed::Bool = false,
        completed_attempt_archive_seal_supported::Bool = false,
        interrupted_attempt_recovery_review_passed::Bool = false)
    job_runner_materialized = isfile(job_runner_path) && !islink(job_runner_path)
    canonical_executor_materialized = job_runner_materialized &&
        normpath(job_runner_path) == normpath(LD1B1_DEFAULT_JOB_RUNNER)
    final_worker_source_pinned_and_identities_regenerated =
        canonical_executor_materialized &&
        canonical_executor_source_pin_validated
    canonical_executor_source_pinned =
        final_worker_source_pinned_and_identities_regenerated
    canonical_execution_root_bound =
        normpath(attempt_root) == normpath(LD1B1_DEFAULT_ATTEMPT_ROOT)
    checks = (;
        protocol_execution_authorized,
        canonical_executor_materialized,
        final_worker_source_pinned_and_identities_regenerated,
        bounded_canonical_smoke_passed,
        completed_attempt_archive_seal_supported,
        interrupted_attempt_recovery_review_passed,
        canonical_execution_root_bound,
    )
    operational_blockers = Tuple(field for field in propertynames(checks)
        if !getproperty(checks, field))
    blockers = canonical_executor_source_pinned ? operational_blockers :
        (operational_blockers..., :canonical_executor_source_pinned)
    return merge(checks, (;
        canonical_executor_source_pinned,
        operational_execution_authorized = isempty(operational_blockers),
        blockers,
    ))
end

function ld1b1_checked_protocol(path::AbstractString;
        job_runner_path::AbstractString = LD1B1_DEFAULT_JOB_RUNNER,
        attempt_root::AbstractString = LD1B1_DEFAULT_ATTEMPT_ROOT,
        consume_bounded_smoke_receipt::Bool = true)
    isfile(path) || error("protocol artifact is missing: $path")
    protocol = JSON3.read(read(path, String))
    ld1b1_string(protocol[:schema]) == LD1B1_PROTOCOL_SCHEMA ||
        error("unexpected LD1b1 protocol schema")
    ld1b1_string(protocol[:scope]) ==
        "ld1b1_pilot_execution_protocol_preflight_noncalibration" ||
        error("unexpected LD1b1 protocol scope")
    ld1b1_string(protocol[:status]) == "pilot_protocol_preflight_passed" ||
        error("LD1b1 protocol preflight did not pass")
    ld1b1_bool(protocol[:summary][:passed]) ||
        error("LD1b1 protocol summary did not pass")
    ld1b1_bool(protocol[:summary][:pilot_execution_authorized]) ||
        error("LD1b1 protocol does not authorize pilot execution")
    !ld1b1_bool(protocol[:summary][:pilot_execution_completed]) ||
        error("protocol preflight must not claim completed pilot execution")
    ld1b1_validate_frozen_pilot_contract(protocol)
    protocol_content_hash = ld1b1_verify_content_hash(
        protocol; label = "LD1b1 protocol")
    protocol_file_sha256 = ld1b1_file_sha256(path)
    executor_source_pin =
        ld1b1_validate_canonical_executor_source_pin(protocol)
    calibration_semantic_context = try
        LD1B1CalibrationSemantics.
            ld1b1_load_calibration_semantic_context(path)
    catch err
        error(
            "LD1b1 calibration semantic context validation failed: " *
            sprint(showerror, err),
        )
    end

    preflight = protocol[:pilot_preflight]
    jobs = collect(preflight[:job_rows])
    length(jobs) == LD1B1_EXPECTED_JOBS ||
        error("LD1b1 protocol must contain exactly 660 job rows")
    ordered_job_rows_sha256 = ld1b1_canonical_sha256(
        ld1b1_json_native(preflight[:job_rows]))
    ordered_job_rows_sha256 == LD1B1_ORDERED_JOB_ROWS_SHA256 ||
        error("LD1b1 job rows differ from the frozen canonical plan")
    [ld1b1_int(row[:row_index]) for row in jobs] ==
        collect(1:LD1B1_EXPECTED_JOBS) ||
        error("LD1b1 job rows are not in canonical consecutive order")
    count(row -> ld1b1_string(row[:expected_action]) ==
        "fit_and_score_diagnostic", jobs) == LD1B1_EXPECTED_FIT_JOBS ||
        error("LD1b1 fit-job count differs from the frozen contract")
    count(row -> ld1b1_string(row[:expected_action]) ==
        "pre_fit_reject", jobs) == LD1B1_EXPECTED_REJECTION_JOBS ||
        error("LD1b1 rejection-job count differs from the frozen contract")
    all(row -> (ld1b1_string(row[:expected_action]) ==
            "fit_and_score_diagnostic") ==
        ld1b1_bool(row[:expected_structural_eligibility]), jobs) ||
        error("LD1b1 job action differs from structural eligibility")
    all(row -> ld1b1_int(row[:primary_attempt]) == 1, jobs) ||
        error("LD1b1 jobs must use primary attempt 1")
    all(row -> !ld1b1_bool(
        row[:primary_outcome_overwritable_by_retries]), jobs) ||
        error("LD1b1 jobs must prohibit retry replacement")
    all(row -> ld1b1_string(row[:execution_status]) == "not_executed", jobs) ||
        error("protocol preflight job rows must remain unexecuted")
    all(replication -> count(row ->
        ld1b1_int(row[:replication]) == replication, jobs) == 22, 1:30) ||
        error("each pilot replication must contain all 22 scenarios")
    scenarios = unique(ld1b1_string(row[:scenario_id]) for row in jobs)
    length(scenarios) == 22 || error("LD1b1 protocol must contain 22 scenarios")
    all(scenario -> count(row ->
        ld1b1_string(row[:scenario_id]) == scenario, jobs) == 30,
        scenarios) || error("each LD1b1 scenario must contain 30 replications")

    job_ids = ld1b1_job_id.(jobs)
    length(unique(job_ids)) == LD1B1_EXPECTED_JOBS ||
        error("canonical LD1b1 job ids are not unique")
    source_identity = ld1b1_source_identity(protocol)
    pilot_contract_sha256 = ld1b1_canonical_sha256(
        ld1b1_json_native(protocol[:pilot_contract]))
    protocol_plan_material = (;
        protocol_file_sha256,
        protocol_content_hash,
        ordered_job_rows_sha256,
        pilot_contract_sha256,
        canonical_executor_source_pin_id = executor_source_pin.pin_id,
        project_toml_sha256 = source_identity.project_toml_sha256,
        manifest_toml = source_identity.manifest_toml,
        manifest_toml_sha256 = source_identity.manifest_toml_sha256,
        source_rows = source_identity.source_rows,
    )
    protocol_plan_id = ld1b1_canonical_sha256(protocol_plan_material)
    job_runner_materialized = isfile(job_runner_path) && !islink(job_runner_path)
    execution_source_identity = (;
        batch_runner_source_sha256 = ld1b1_file_sha256(@__FILE__),
        local_json_source_sha256 = ld1b1_file_sha256(
            joinpath(@__DIR__, "local_json.jl")),
        job_runner_source_sha256 = job_runner_materialized ?
            ld1b1_file_sha256(job_runner_path) : missing,
        attempt_archive_source_sha256 =
            LD1B1AttemptArchive.ld1b_attempt_archive_source_sha256(),
        local_dependence_pilot_recovery_source_sha256 =
            ld1b1_file_sha256(joinpath(
                @__DIR__,
                "local_dependence_pilot_recovery.jl",
            )),
        local_dependence_pilot_calibration_semantics_source_sha256 =
            ld1b1_file_sha256(joinpath(
                @__DIR__,
                "local_dependence_pilot_calibration_semantics.jl",
            )),
    )
    canonical_executor_source_pin_validated =
        normpath(job_runner_path) == normpath(LD1B1_DEFAULT_JOB_RUNNER) &&
        ld1b1_canonical_sha256(execution_source_identity) ==
            ld1b1_canonical_sha256(
                executor_source_pin.execution_source_identity)
    plan_id = ld1b1_canonical_sha256((;
        protocol_plan_id,
        execution_source_identity,
    ))
    readiness = ld1b1_execution_readiness(;
        protocol_execution_authorized = true,
        job_runner_path,
        attempt_root,
        canonical_executor_source_pin_validated,
        bounded_canonical_smoke_passed = false,
        completed_attempt_archive_seal_supported =
            LD1B1_COMPLETED_ATTEMPT_ARCHIVE_SEAL_SUPPORTED,
        interrupted_attempt_recovery_review_passed = false,
    )
    identity = merge(protocol_plan_material, (;
        protocol_plan_id,
        execution_source_identity,
        plan_id,
        protocol_schema = LD1B1_PROTOCOL_SCHEMA,
        protocol_scope = ld1b1_symbol(protocol[:scope]),
        canonical_executor_source_pin_source_rows =
            executor_source_pin.source_rows,
        batch_harness_generator_source_sha256 =
            executor_source_pin.batch_harness_generator_source_sha256,
        n_jobs = length(jobs),
        plan_identity_valid = true,
        readiness,
        execution_plan_complete = readiness.operational_execution_authorized,
        execution_plan_assessment = readiness.operational_execution_authorized ?
            :complete : :incomplete_operational_readiness,
    ))
    checked = (;
        protocol,
        preflight,
        jobs,
        job_ids,
        identity,
        calibration_semantic_context,
    )
    smoke_receipt_validation = (;
        present = false,
        valid = false,
        assessment = :not_present,
        error = missing,
    )
    should_consume_smoke = consume_bounded_smoke_receipt &&
        normpath(job_runner_path) == normpath(LD1B1_DEFAULT_JOB_RUNNER) &&
        normpath(attempt_root) == normpath(LD1B1_DEFAULT_ATTEMPT_ROOT) &&
        (ispath(LD1B1_DEFAULT_BOUNDED_SMOKE_RECEIPT) ||
            islink(LD1B1_DEFAULT_BOUNDED_SMOKE_RECEIPT))
    if should_consume_smoke
        smoke_receipt_validation = try
            validation = ld1b1_validate_bounded_smoke_receipt(
                LD1B1_DEFAULT_BOUNDED_SMOKE_RECEIPT,
                checked,
            )
            (;
                present = true,
                valid = validation.valid,
                assessment = :passed,
                error = missing,
                validation,
            )
        catch err
            (;
                present = true,
                valid = false,
                assessment = :invalid_fail_closed,
                error = portable_error_message(err),
            )
        end
    end
    independent_review_validation = (;
        present = false,
        valid = false,
        assessment = :not_present,
        error = missing,
    )
    review_present = ispath(
        LD1B1_DEFAULT_INDEPENDENT_RECOVERY_READINESS_REVIEW) || islink(
        LD1B1_DEFAULT_INDEPENDENT_RECOVERY_READINESS_REVIEW)
    if consume_bounded_smoke_receipt && review_present
        if smoke_receipt_validation.valid
            independent_review_validation = try
                validation =
                    ld1b1_validate_independent_recovery_readiness_review(
                        LD1B1_DEFAULT_INDEPENDENT_RECOVERY_READINESS_REVIEW,
                        checked,
                        smoke_receipt_validation.validation,
                    )
                (;
                    present = true,
                    valid = validation.valid,
                    assessment = :passed,
                    error = missing,
                    validation,
                )
            catch err
                (;
                    present = true,
                    valid = false,
                    assessment = :invalid_fail_closed,
                    error = portable_error_message(err),
                )
            end
        else
            independent_review_validation = (;
                present = true,
                valid = false,
                assessment = :blocked_by_missing_or_invalid_smoke,
                error = missing,
            )
        end
    end
    readiness = ld1b1_execution_readiness(;
        protocol_execution_authorized = true,
        job_runner_path,
        attempt_root,
        canonical_executor_source_pin_validated,
        bounded_canonical_smoke_passed = smoke_receipt_validation.valid,
        completed_attempt_archive_seal_supported =
            LD1B1_COMPLETED_ATTEMPT_ARCHIVE_SEAL_SUPPORTED,
        interrupted_attempt_recovery_review_passed =
            independent_review_validation.valid,
    )
    identity = merge(identity, (;
        readiness,
        bounded_smoke_receipt_validation = smoke_receipt_validation,
        independent_recovery_readiness_review_validation =
            independent_review_validation,
        execution_plan_complete = readiness.operational_execution_authorized,
        execution_plan_assessment = readiness.operational_execution_authorized ?
            :complete : :incomplete_operational_readiness,
    ))
    return merge(checked, (; identity))
end

function ld1b1_job_specs(checked)
    sampler = checked.protocol[:pilot_contract][:sampler]
    quality = checked.protocol[:pilot_contract][:quality_requirements]
    calibration_contract =
        checked.protocol[:pilot_contract][:calibration_contract]
    sampler_contract = (;
        backend = ld1b1_symbol(sampler[:backend]),
        algorithm = ld1b1_symbol(sampler[:algorithm]),
        chains = ld1b1_int(sampler[:chains]),
        warmup_per_chain = ld1b1_int(sampler[:warmup_per_chain]),
        draws_per_chain = ld1b1_int(sampler[:draws_per_chain]),
        total_retained_draws = ld1b1_int(sampler[:total_retained_draws]),
        target_accept = ld1b1_float(sampler[:target_accept]),
        max_depth = ld1b1_int(sampler[:max_depth]),
        metric = ld1b1_symbol(sampler[:metric]),
        ad_backend = ld1b1_symbol(sampler[:ad_backend]),
        split_chains = ld1b1_bool(sampler[:split_chains]),
        diagnostic_draws = ld1b1_int(sampler[:diagnostic_draws]),
        diagnostic_draw_policy =
            ld1b1_symbol(sampler[:diagnostic_draw_policy]),
        posterior_predictive_replicates_per_draw = ld1b1_int(
            sampler[:posterior_predictive_replicates_per_draw]),
    )
    quality_contract = (;
        diagnostic_contract = ld1b1_symbol(quality[:diagnostic_contract]),
        diagnostic_contract_details_sha256 = ld1b1_canonical_sha256(
            ld1b1_json_native(quality[:diagnostic_contract_details])),
        maximum_rhat = ld1b1_float(quality[:maximum_rhat]),
        minimum_bulk_ess = ld1b1_float(quality[:minimum_bulk_ess]),
        minimum_tail_ess = ld1b1_float(quality[:minimum_tail_ess]),
        maximum_divergences = ld1b1_int(quality[:maximum_divergences]),
        maximum_depth_hits = ld1b1_int(quality[:maximum_depth_hits]),
        e_bfmi_chain_coverage_required =
            ld1b1_bool(quality[:e_bfmi_chain_coverage_required]),
        minimum_e_bfmi = ld1b1_float(quality[:minimum_e_bfmi]),
        local_dependence_contract_sha256 = ld1b1_canonical_sha256(
            ld1b1_json_native(calibration_contract[:diagnostic_contract])),
        calibration_contract_sha256 = ld1b1_canonical_sha256(
            ld1b1_json_native(calibration_contract)),
    )
    return [(;
        job_id = checked.job_ids[index],
        row_index = ld1b1_int(row[:row_index]),
        scenario_index = ld1b1_int(row[:scenario_index]),
        scenario_id = ld1b1_symbol(row[:scenario_id]),
        matched_set_id = ld1b1_symbol(row[:matched_set_id]),
        replication = ld1b1_int(row[:replication]),
        phase = ld1b1_symbol(row[:phase]),
        seed = ld1b1_int(row[:seed]),
        fit_seed = ld1b1_int(row[:fit_seed]),
        draw_selection_seed = ld1b1_int(row[:draw_selection_seed]),
        posterior_predictive_seed =
            ld1b1_int(row[:posterior_predictive_seed]),
        expected_action = ld1b1_symbol(row[:expected_action]),
        expected_structural_eligibility =
            ld1b1_bool(row[:expected_structural_eligibility]),
        resources = (;
            n_ratings = ld1b1_int(row[:resources][:n_ratings]),
            n_probability_cells =
                ld1b1_int(row[:resources][:n_probability_cells]),
            n_truth_cells = ld1b1_int(row[:resources][:n_truth_cells]),
        ),
        sampler_contract,
        quality_contract,
        primary_attempt = 1,
        primary_outcome_overwritable_by_retries = false,
    ) for (index, row) in pairs(checked.jobs)]
end

function ld1b1_bounded_smoke_job(specs)
    matches = [job for job in specs if
        job.row_index == LD1B1_BOUNDED_SMOKE_ROW_INDEX]
    length(matches) == 1 || error(
        "bounded smoke row is not unique in the canonical plan")
    job = only(matches)
    job.job_id == LD1B1_BOUNDED_SMOKE_JOB_ID || error(
        "bounded smoke row has the wrong canonical job id")
    job.scenario_id === :null_support_at_minimum || error(
        "bounded smoke row has the wrong scenario")
    job.replication == 1 || error(
        "bounded smoke row has the wrong replication")
    job.expected_action === :fit_and_score_diagnostic || error(
        "bounded smoke must exercise the complete fit-and-score path")
    job.expected_structural_eligibility || error(
        "bounded smoke job is not structurally eligible")
    job.resources == (;
        n_ratings = 240,
        n_probability_cells = 960,
        n_truth_cells = 6_376,
    ) || error("bounded smoke resource caps differ from the frozen row")
    return job
end

function ld1b1_bounded_smoke_contract(parent_identity, job;
        timeout_seconds::Int = LD1B1_BOUNDED_SMOKE_TIMEOUT_SECONDS,
        termination_grace_seconds::Int =
            LD1B1_BOUNDED_SMOKE_TERMINATION_GRACE_SECONDS,
        max_rss_bytes::Int = LD1B1_BOUNDED_SMOKE_MAX_RSS_BYTES,
        max_archive_bytes::Int = LD1B1_BOUNDED_SMOKE_MAX_ARCHIVE_BYTES)
    job.row_index == LD1B1_BOUNDED_SMOKE_ROW_INDEX &&
        job.job_id == LD1B1_BOUNDED_SMOKE_JOB_ID &&
        job.expected_action === :fit_and_score_diagnostic || error(
        "bounded smoke contract requires the canonical allowlisted job")
    timeout_seconds >= 1 || error("bounded smoke timeout must be positive")
    termination_grace_seconds >= 1 || error(
        "bounded smoke termination grace must be positive")
    max_rss_bytes >= 1 || error("bounded smoke RSS cap must be positive")
    max_archive_bytes >= 1 || error(
        "bounded smoke archive cap must be positive")
    return (;
        schema = "bayesianmgmfrm.local_dependence_pilot_bounded_smoke_contract.v1",
        scope = :verification_only_nonpilot,
        execution_context = ld1b1_execution_context(:bounded_smoke),
        canonical_parent_plan_id = parent_identity.plan_id,
        canonical_executor_source_pin_id =
            parent_identity.canonical_executor_source_pin_id,
        job = merge(ld1b1_result_job_identity(job), (;
            resources = job.resources,
        )),
        sampler_contract = job.sampler_contract,
        quality_contract = job.quality_contract,
        bounds = (;
            max_jobs = 1,
            timeout_seconds,
            termination_grace_seconds,
            max_rss_bytes,
            max_archive_bytes,
            maximum_child_processes = 1,
        ),
        restrictions = (;
            attempt = 1,
            attempt_role = :verification,
            retries_allowed = false,
            resume_allowed = false,
            sampler_overrides_allowed = false,
            seed_overrides_allowed = false,
            canonical_pilot_root_writes_allowed = false,
            official_pilot_denominator_eligible = false,
            scientific_contribution = 0,
        ),
    )
end

function ld1b1_bounded_smoke_identity(parent_identity, job; kwargs...)
    contract = ld1b1_bounded_smoke_contract(
        parent_identity, job; kwargs...)
    smoke_plan_id = ld1b1_canonical_sha256((;
        domain = :ld1b1_bounded_canonical_smoke_plan_v1,
        parent_plan_identity = ld1b1_result_plan_identity(parent_identity),
        execution_source_identity = parent_identity.execution_source_identity,
        contract,
    ))
    identity = merge(parent_identity, (;
        plan_id = smoke_plan_id,
        parent_plan_id = parent_identity.plan_id,
        bounded_smoke_contract = contract,
    ))
    return (; identity, contract, smoke_plan_id)
end

function ld1b1_bounded_smoke_authorization_path(
        smoke_root::AbstractString, smoke_plan_id::AbstractString)
    return joinpath(
        normpath(smoke_root),
        String(smoke_plan_id),
        LD1B1_BOUNDED_SMOKE_AUTHORIZATION_FILENAME,
    )
end

function ld1b1_bounded_smoke_execution_root(
        smoke_root::AbstractString, smoke_plan_id::AbstractString)
    return joinpath(
        normpath(smoke_root),
        String(smoke_plan_id),
        "attempts",
        String(smoke_plan_id),
    )
end

function ld1b1_bounded_smoke_authorization(parent_identity, smoke_identity,
        job, smoke_root::AbstractString)
    smoke_identity.parent_plan_id == parent_identity.plan_id || error(
        "bounded smoke identity has the wrong parent plan")
    smoke_identity.bounded_smoke_contract.canonical_parent_plan_id ==
        parent_identity.plan_id || error(
        "bounded smoke contract has the wrong parent plan")
    base = (;
        schema = LD1B1_BOUNDED_SMOKE_AUTHORIZATION_SCHEMA,
        object = :local_dependence_pilot_bounded_smoke_authorization,
        status = :verification_only_authorized,
        execution_context = ld1b1_execution_context(:bounded_smoke),
        parent_plan_identity = ld1b1_result_plan_identity(parent_identity),
        smoke_plan_identity = ld1b1_result_plan_identity(smoke_identity),
        canonical_executor_source_pin_id =
            parent_identity.canonical_executor_source_pin_id,
        execution_source_identity = parent_identity.execution_source_identity,
        contract = smoke_identity.bounded_smoke_contract,
        path_contract = (;
            root_namespace = :local_dependence_pilot_bounded_smoke_v1,
            smoke_root = ld1b1_record_path(smoke_root),
            authorization_path = ld1b1_record_path(
                ld1b1_bounded_smoke_authorization_path(
                    smoke_root, smoke_identity.plan_id)),
            execution_root = ld1b1_record_path(
                ld1b1_bounded_smoke_execution_root(
                    smoke_root, smoke_identity.plan_id)),
            official_pilot_root = ld1b1_record_path(
                LD1B1_DEFAULT_ATTEMPT_ROOT),
            roots_disjoint = true,
        ),
        evidence_boundary = (;
            response_data_generated = false,
            model_fit_run = false,
            mcmc_run = false,
            bounded_smoke_passed = false,
            independent_recovery_readiness_review_passed = false,
            operational_execution_authorized = false,
            pilot_execution_started = false,
            pilot_execution_completed = false,
            scientific_pilot_outcomes = 0,
            scientific_pilot_denominator = LD1B1_EXPECTED_JOBS,
        ),
    )
    return ld1b1_with_content_hash(base)
end

function ld1b1_validate_bounded_smoke_authorization(path::AbstractString,
        parent_identity, smoke_identity, job, smoke_root::AbstractString)
    expected_path = ld1b1_bounded_smoke_authorization_path(
        smoke_root, smoke_identity.plan_id)
    normpath(path) == normpath(expected_path) || error(
        "bounded smoke authorization path is not canonical")
    isfile(path) && !islink(path) || error(
        "bounded smoke authorization is not a regular file")
    observed = JSON3.read(read(path, String))
    ld1b1_verify_content_hash(
        observed; label = "bounded smoke authorization")
    expected = ld1b1_bounded_smoke_authorization(
        parent_identity, smoke_identity, job, smoke_root)
    ld1b1_canonical_sha256(ld1b1_json_native(observed)) ==
        ld1b1_canonical_sha256(ld1b1_json_native(expected)) || error(
        "bounded smoke authorization differs from the reconstructed contract")
    return (;
        valid = true,
        file_sha256 = ld1b1_file_sha256(path),
        content_hash = ld1b1_string(observed[:content_hash][:value]),
        artifact = observed,
    )
end

ld1b1_execution_root(attempt_root::AbstractString, plan_id::AbstractString) =
    joinpath(normpath(attempt_root), String(plan_id))

function ld1b1_attempt_dir(execution_root::AbstractString, job_id::AbstractString,
        attempt::Int)
    1 <= attempt <= 999 || error("attempt must be in 1:999")
    return joinpath(execution_root, "jobs", String(job_id),
        string("attempt_", lpad(string(attempt), 3, '0')))
end

ld1b1_result_path(execution_root::AbstractString, job_id::AbstractString,
    attempt::Int) = joinpath(
        ld1b1_attempt_dir(execution_root, job_id, attempt), "job_result.json")

function ld1b1_attempt_reservation_path(execution_root::AbstractString,
        job_id::AbstractString, attempt::Int)
    1 <= attempt <= 999 || error("attempt must be in 1:999")
    return joinpath(
        normpath(execution_root),
        "attempt_reservations",
        String(job_id),
        string("attempt_", lpad(string(attempt), 3, '0')),
        LD1B1Recovery.LD1B_ATTEMPT_RESERVATION_FILENAME,
    )
end

ld1b1_attempt_reservations_root(execution_root::AbstractString) =
    joinpath(normpath(execution_root), "attempt_reservations")

ld1b1_attempt_reservation_staging_dir(execution_root::AbstractString) =
    joinpath(normpath(execution_root), ".attempt_reservation_staging")

ld1b1_receipt_staging_dir(execution_root::AbstractString) =
    joinpath(normpath(execution_root), ".attempt_receipt_staging")

ld1b1_seal_path(execution_root::AbstractString, job_id::AbstractString,
    attempt::Int) = joinpath(
        ld1b1_attempt_dir(execution_root, job_id, attempt),
        LD1B1AttemptArchive.LD1B_ATTEMPT_SEAL_FILENAME,
    )

ld1b1_seal_staging_dir(execution_root::AbstractString) =
    joinpath(normpath(execution_root), ".attempt_seal_staging")

ld1b1_retirement_path(execution_root::AbstractString,
    job_id::AbstractString, attempt::Int) = joinpath(
        ld1b1_attempt_dir(execution_root, job_id, attempt),
        LD1B1AttemptArchive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
    )

ld1b1_interruption_review_path(execution_root::AbstractString,
    job_id::AbstractString, attempt::Int) = joinpath(
        ld1b1_attempt_dir(execution_root, job_id, attempt),
        LD1B1Recovery.LD1B_INTERRUPTION_REVIEW_FILENAME,
    )

ld1b1_precommit_interruption_review_path(execution_root::AbstractString,
    job_id::AbstractString, attempt::Int) = joinpath(
        ld1b1_attempt_dir(execution_root, job_id, attempt),
        LD1B1Recovery.LD1B_PRECOMMIT_INTERRUPTION_REVIEW_FILENAME,
    )

ld1b1_retirement_staging_dir(execution_root::AbstractString) =
    joinpath(normpath(execution_root), ".attempt_retirement_staging")

ld1b1_recovery_staging_dir(execution_root::AbstractString) =
    joinpath(normpath(execution_root), ".attempt_recovery_staging")

ld1b1_result_execution_root(path::AbstractString) =
    dirname(dirname(dirname(dirname(normpath(path)))))

function ld1b1_selected_jobs(specs, options)
    job_filter = Set(options.job_ids)
    row_filter = Set(options.row_indexes)
    scenario_filter = Set(options.scenarios)
    replication_filter = Set(options.replications)
    valid_job_ids = Set(job.job_id for job in specs)
    valid_rows = Set(job.row_index for job in specs)
    valid_scenarios = Set(String(job.scenario_id) for job in specs)
    valid_replications = Set(job.replication for job in specs)
    for (requested, valid, label) in (
            (job_filter, valid_job_ids, "job id"),
            (row_filter, valid_rows, "row index"),
            (scenario_filter, valid_scenarios, "scenario"),
            (replication_filter, valid_replications, "replication"),
        )
        missing_values = setdiff(requested, valid)
        isempty(missing_values) || error(
            "selected $label is absent from the canonical plan: $(first(missing_values))")
    end
    matching = [job for job in specs if
        (isempty(job_filter) || job.job_id in job_filter) &&
        (isempty(row_filter) || job.row_index in row_filter) &&
        (isempty(scenario_filter) || String(job.scenario_id) in scenario_filter) &&
        (isempty(replication_filter) || job.replication in replication_filter)]
    limit = options.run_all || options.max_jobs === nothing ?
        length(matching) : Int(options.max_jobs)
    selected = matching[1:min(limit, length(matching))]
    options.mode in (:execute_primary, :execute_retry) && isempty(selected) &&
        error("execution selection must contain at least one canonical job")
    options.mode === :execute_retry && length(selected) != 1 &&
        error("execute-retry must select exactly one canonical job")
    return (; matching, selected)
end

function ld1b1_expected_job_runner_sha256(identity)
    value = getproperty(
        identity.execution_source_identity,
        :job_runner_source_sha256,
    )
    ismissing(value) && error(
        "execution plan does not contain a materialized single-job runner identity")
    return ld1b1_require_sha256(value, "single-job runner source identity")
end

function ld1b1_terminal_outcome_code(status::Symbol)
    status in LD1B1_TERMINAL_STATUSES ||
        error("unsupported LD1b1 terminal status: $status")
    return getproperty(LD1B1_TERMINAL_OUTCOME_CODES, status)
end

function ld1b1_result_plan_identity(identity)
    return (;
        plan_id = identity.plan_id,
        protocol_plan_id = identity.protocol_plan_id,
        protocol_file_sha256 = identity.protocol_file_sha256,
        protocol_content_hash = identity.protocol_content_hash,
        ordered_job_rows_sha256 = identity.ordered_job_rows_sha256,
        pilot_contract_sha256 = identity.pilot_contract_sha256,
    )
end

function ld1b1_result_job_identity(job)
    return (;
        job_id = job.job_id,
        row_index = job.row_index,
        scenario_index = job.scenario_index,
        scenario_id = job.scenario_id,
        replication = job.replication,
        expected_action = job.expected_action,
        seed = job.seed,
        fit_seed = job.fit_seed,
        draw_selection_seed = job.draw_selection_seed,
        posterior_predictive_seed = job.posterior_predictive_seed,
    )
end

function ld1b1_evidence_payload_schema(role::Symbol)
    role === :generated_data && return :generated_data_v2
    role === :fit_result && return :fit_result_v2
    role === :sampler_diagnostics && return :sampler_diagnostics_v2
    role === :local_dependence_summary && return :local_dependence_summary_v2
    role === :calibration_row && return :calibration_row_v2
    role === :structural_rejection_audit &&
        return :structural_rejection_audit_v2
    role === :generation_failure_record && return :generation_failure_record_v2
    role === :fit_failure_record && return :fit_failure_record_v2
    role === :diagnostic_failure_record && return :diagnostic_failure_record_v2
    error("unsupported LD1b1 evidence role: $role")
end

function ld1b1_evidence_member_role(role::Symbol)
    role === :generated_data && return :simulation_bundle
    role === :fit_result && return :fit_artifact_export
    role === :sampler_diagnostics && return :diagnostics_bundle
    role === :local_dependence_summary && return :local_dependence_summary
    role === :calibration_row && return :calibration_row
    role === :structural_rejection_audit && return :structural_rejection_audit
    role === :generation_failure_record && return :generation_failure_record
    role === :fit_failure_record && return :fit_failure_record
    role === :diagnostic_failure_record && return :diagnostic_failure_record
    error("unsupported LD1b1 evidence role: $role")
end

function ld1b1_evidence_member_media_type(role::Symbol)
    return :application_json
end

function ld1b1_expected_evidence_dependencies(status::Symbol, role::Symbol)
    role in ld1b1_required_evidence_roles(status) ||
        error("evidence role does not belong to terminal status $status")
    role in (:generated_data, :generation_failure_record) && return ()
    role === :structural_rejection_audit && return (:generated_data,)
    role === :fit_result && return (:generated_data,)
    role === :sampler_diagnostics && return (:fit_result,)
    role === :local_dependence_summary && return (
        :generated_data,
        :fit_result,
        :sampler_diagnostics,
    )
    if role === :calibration_row
        status === :completed && return (
            :generated_data,
            :local_dependence_summary,
        )
        status === :pre_fit_rejected && return (
            :generated_data,
            :structural_rejection_audit,
        )
        status === :generation_failed && return (
            :generation_failure_record,
        )
        status === :fit_failed && return (
            :generated_data,
            :fit_failure_record,
        )
        status === :diagnostic_failed && return (
            :generated_data,
            :fit_result,
            :sampler_diagnostics,
            :diagnostic_failure_record,
        )
    end
    role === :fit_failure_record && return (:generated_data,)
    role === :diagnostic_failure_record && return (
        :generated_data,
        :fit_result,
        :sampler_diagnostics,
    )
    error("unsupported evidence dependency contract for $role")
end

function ld1b1_validate_evidence_payload(payload, role::Symbol, job,
        terminal_status::Symbol)
    if role === :generated_data
        keys = (:simulation_content_sha256, :n_response_rows,
            :n_probability_cells, :n_truth_cells, :data_signature,
            :score_signature, :testlet_design_signature_sha256,
            :generation_completed)
        ld1b1_require_only_keys(payload, keys, "generated-data evidence payload")
        ld1b1_require_sha256(payload[:simulation_content_sha256],
            "simulation-bundle digest")
        ld1b1_int(payload[:n_response_rows]) == job.resources.n_ratings ||
            error("generated-data rating count differs from the frozen job")
        ld1b1_int(payload[:n_probability_cells]) ==
            job.resources.n_probability_cells || error(
            "generated-data probability-cell count differs from the frozen job")
        ld1b1_int(payload[:n_truth_cells]) == job.resources.n_truth_cells ||
            error("generated-data truth-cell count differs from the frozen job")
        ld1b1_data_signature(payload[:data_signature],
            "generated-data data signature")
        for field in (:score_signature, :testlet_design_signature_sha256)
            ld1b1_require_sha256(payload[field],
                "generated-data $(replace(String(field), '_' => '-'))")
        end
        ld1b1_bool(payload[:generation_completed]) ||
            error("generated-data evidence is not complete")
    elseif role === :fit_result
        keys = (:fit_artifact_sha256, :fit_artifact_content_hash,
            :fit_artifact_json_content_hash, :data_signature,
            :retained_draw_set_sha256,
            :fit_seed, :backend, :algorithm,
            :n_chains, :warmup_per_chain, :draws_per_chain,
            :total_retained_draws, :target_accept, :max_depth,
            :metric, :ad_backend, :fit_completed)
        ld1b1_require_only_keys(payload, keys, "fit-result evidence payload")
        ld1b1_data_signature(payload[:data_signature],
            "fit-result data signature")
        for field in (:fit_artifact_sha256, :fit_artifact_content_hash,
                :fit_artifact_json_content_hash, :retained_draw_set_sha256)
            ld1b1_require_sha256(payload[field],
                "fit-result $(replace(String(field), '_' => '-'))")
        end
        ld1b1_int(payload[:fit_seed]) == job.fit_seed ||
            error("fit-result evidence has the wrong fit seed")
        sampler = job.sampler_contract
        for field in (:backend, :algorithm, :metric, :ad_backend)
            ld1b1_symbol(payload[field]) === getproperty(sampler, field) ||
                error("fit-result evidence differs from sampler contract: $field")
        end
        for field in (:chains, :warmup_per_chain, :draws_per_chain,
                :total_retained_draws, :max_depth)
            payload_field = field === :chains ? :n_chains : field
            ld1b1_int(payload[payload_field]) == getproperty(sampler, field) ||
                error("fit-result evidence differs from sampler contract: $field")
        end
        ld1b1_float(payload[:target_accept]) == sampler.target_accept ||
            error("fit-result target acceptance differs from the frozen contract")
        ld1b1_bool(payload[:fit_completed]) ||
            error("fit-result evidence is not complete")
    elseif role === :sampler_diagnostics
        keys = (:diagnostics_content_sha256, :diagnostic_contract,
            :diagnostic_contract_details_sha256, :n_chains,
            :draws_per_chain, :total_draws, :split_chains_requested,
            :split_chains, :max_rank_normalized_rhat, :min_bulk_ess,
            :min_tail_ess, :n_divergences, :n_max_treedepth,
            :e_bfmi, :n_e_bfmi_expected, :n_e_bfmi_available,
            :n_e_bfmi_unavailable, :e_bfmi_complete, :diagnostics_passed,
            :diagnostics_flag, :sampler_gate_passed,
            :fit_artifact_sha256, :fit_artifact_content_hash,
            :data_signature, :retained_draw_set_sha256)
        ld1b1_require_only_keys(payload, keys,
            "sampler-diagnostic evidence payload")
        ld1b1_require_sha256(payload[:diagnostics_content_sha256],
            "diagnostics-bundle digest")
        ld1b1_data_signature(payload[:data_signature],
            "sampler-diagnostic data signature")
        for field in (:fit_artifact_sha256, :fit_artifact_content_hash,
                :retained_draw_set_sha256)
            ld1b1_require_sha256(payload[field],
                "sampler-diagnostic $(replace(String(field), '_' => '-'))")
        end
        quality = job.quality_contract
        sampler = job.sampler_contract
        ld1b1_symbol(payload[:diagnostic_contract]) ===
            quality.diagnostic_contract ||
            error("sampler-diagnostic evidence uses the wrong contract")
        ld1b1_require_sha256(payload[:diagnostic_contract_details_sha256],
            "diagnostic-contract-details digest") ==
            quality.diagnostic_contract_details_sha256 || error(
            "sampler-diagnostic contract details differ from the frozen contract")
        ld1b1_int(payload[:n_chains]) == sampler.chains ||
            error("sampler-diagnostic chain count differs from the frozen contract")
        ld1b1_int(payload[:draws_per_chain]) == sampler.draws_per_chain ||
            error("sampler-diagnostic draw count differs from the frozen contract")
        ld1b1_int(payload[:total_draws]) == sampler.total_retained_draws ||
            error("sampler-diagnostic total draws differ from the frozen contract")
        ld1b1_bool(payload[:split_chains_requested]) == sampler.split_chains ||
            error("sampler-diagnostic split request differs from the frozen contract")
        ld1b1_bool(payload[:split_chains]) == sampler.split_chains ||
            error("sampler-diagnostic split application differs from the frozen contract")
        rhat_passed = ld1b1_float(payload[:max_rank_normalized_rhat]) <=
            quality.maximum_rhat
        bulk_ess_passed =
            ld1b1_float(payload[:min_bulk_ess]) >= quality.minimum_bulk_ess
        tail_ess_passed =
            ld1b1_float(payload[:min_tail_ess]) >= quality.minimum_tail_ess
        divergences = ld1b1_int(payload[:n_divergences])
        divergences >= 0 || error("divergence count must be nonnegative")
        divergences_passed = divergences <= quality.maximum_divergences
        depth_hits = ld1b1_int(payload[:n_max_treedepth])
        depth_hits >= 0 || error("maximum-tree-depth count must be nonnegative")
        depth_passed = depth_hits <= quality.maximum_depth_hits
        n_e_bfmi_expected = ld1b1_int(payload[:n_e_bfmi_expected])
        n_e_bfmi_available = ld1b1_int(payload[:n_e_bfmi_available])
        n_e_bfmi_unavailable = ld1b1_int(payload[:n_e_bfmi_unavailable])
        n_e_bfmi_expected == sampler.chains &&
            0 <= n_e_bfmi_available <= n_e_bfmi_expected &&
            0 <= n_e_bfmi_unavailable <= n_e_bfmi_expected &&
            n_e_bfmi_available + n_e_bfmi_unavailable ==
                n_e_bfmi_expected ||
            error("E-BFMI chain counts are inconsistent")
        e_bfmi_complete = ld1b1_bool(payload[:e_bfmi_complete])
        e_bfmi_complete == (n_e_bfmi_expected > 0 &&
            n_e_bfmi_unavailable == 0) ||
            error("E-BFMI completeness flag differs from chain counts")
        e_bfmi = ld1b1_optional_float(payload[:e_bfmi])
        ismissing(e_bfmi) && n_e_bfmi_available > 0 &&
            error("available E-BFMI chains require a finite minimum")
        e_bfmi_passed = quality.e_bfmi_chain_coverage_required ?
            e_bfmi_complete && !ismissing(e_bfmi) &&
                e_bfmi >= quality.minimum_e_bfmi :
            ismissing(e_bfmi) || e_bfmi >= quality.minimum_e_bfmi
        diagnostics_passed = ld1b1_bool(payload[:diagnostics_passed])
        diagnostics_flag_ok =
            ld1b1_symbol(payload[:diagnostics_flag]) === :ok
        sampler_gate_passed = rhat_passed && bulk_ess_passed &&
            tail_ess_passed && divergences_passed && depth_passed &&
            e_bfmi_passed && diagnostics_passed && diagnostics_flag_ok
        ld1b1_bool(payload[:sampler_gate_passed]) == sampler_gate_passed ||
            error("sampler-gate flag differs from the recorded diagnostics")
        terminal_status === :completed && !sampler_gate_passed &&
            error("completed result did not pass the sampler gate")
    elseif role === :local_dependence_summary
        keys = (:summary_content_sha256, :diagnostic_computed,
            :n_diagnostic_draws, :draw_selection_algorithm,
            :draw_selection_seed,
            :posterior_predictive_seed, :replicates_per_draw,
            :data_signature, :observed_score_signature_sha256,
            :design_signature_sha256, :retained_draw_set_sha256,
            :diagnostic_decision_labels_available,
            :mechanism_interpretation_eligible)
        ld1b1_require_only_keys(payload, keys,
            "local-dependence-summary evidence payload")
        ld1b1_require_sha256(payload[:summary_content_sha256],
            "local-dependence-summary content digest")
        ld1b1_bool(payload[:diagnostic_computed]) ||
            error("local-dependence summary was not computed")
        ld1b1_int(payload[:n_diagnostic_draws]) ==
            job.sampler_contract.diagnostic_draws || error(
            "local-dependence draw count differs from the frozen contract")
        ld1b1_symbol(payload[:draw_selection_algorithm]) ===
            LD1B1_DRAW_SELECTION_ALGORITHM || error(
            "local-dependence summary has the wrong draw-selection algorithm")
        ld1b1_int(payload[:draw_selection_seed]) == job.draw_selection_seed ||
            error("local-dependence summary has the wrong draw-selection seed")
        ld1b1_int(payload[:posterior_predictive_seed]) ==
            job.posterior_predictive_seed || error(
            "local-dependence summary has the wrong predictive seed")
        ld1b1_int(payload[:replicates_per_draw]) ==
            job.sampler_contract.posterior_predictive_replicates_per_draw ||
            error("local-dependence replication count differs from the contract")
        ld1b1_data_signature(payload[:data_signature],
            "local-dependence data signature")
        for field in (:observed_score_signature_sha256,
                :design_signature_sha256, :retained_draw_set_sha256)
            ld1b1_require_sha256(payload[field],
                "local-dependence $(replace(String(field), '_' => '-'))")
        end
        !ld1b1_bool(payload[:diagnostic_decision_labels_available]) ||
            error("pilot evidence must not contain diagnostic decision labels")
        !ld1b1_bool(payload[:mechanism_interpretation_eligible]) ||
            error("pilot evidence must not claim mechanism interpretation")
    elseif role === :calibration_row
        keys = (:calibration_content_sha256, :calibration_contract,
            :row_index, :scenario_index, :scenario_id, :replication,
            :status, :data_signature, :observed_score_signature_sha256,
            :design_signature_sha256, :row_complete)
        ld1b1_require_only_keys(payload, keys,
            "calibration-row evidence payload")
        ld1b1_require_sha256(payload[:calibration_content_sha256],
            "calibration-row digest")
        ld1b1_string(payload[:calibration_contract]) ==
            "bayesianmgmfrm.local_dependence_calibration_row.v1" ||
            error("calibration-row evidence uses the wrong contract")
        ld1b1_int(payload[:row_index]) == job.row_index ||
            error("calibration-row evidence has the wrong row index")
        ld1b1_int(payload[:scenario_index]) == job.scenario_index ||
            error("calibration-row evidence has the wrong scenario index")
        ld1b1_symbol(payload[:scenario_id]) === job.scenario_id ||
            error("calibration-row evidence has the wrong scenario")
        ld1b1_int(payload[:replication]) == job.replication ||
            error("calibration-row evidence has the wrong replication")
        ld1b1_symbol(payload[:status]) === terminal_status ||
            error("calibration-row evidence has the wrong status")
        signature_fields = (:data_signature,
            :observed_score_signature_sha256, :design_signature_sha256)
        if terminal_status === :generation_failed
            for field in signature_fields
                ismissing(ld1b1_get(payload, field, missing)) || error(
                    "generation-failure calibration row contains $field")
            end
        else
            ld1b1_data_signature(payload[:data_signature],
                "calibration-row data signature")
            for field in (:observed_score_signature_sha256,
                    :design_signature_sha256)
                ld1b1_require_sha256(payload[field],
                    "calibration-row $(replace(String(field), '_' => '-'))")
            end
        end
        ld1b1_bool(payload[:row_complete]) ||
            error("calibration-row evidence is incomplete")
    elseif role === :structural_rejection_audit
        keys = (:audit_content_sha256, :simulation_content_sha256,
            :data_signature, :issue_code, :expected_action,
            :rejection_confirmed)
        ld1b1_require_only_keys(payload, keys,
            "structural-rejection evidence payload")
        ld1b1_require_sha256(payload[:audit_content_sha256],
            "structural-rejection audit digest")
        ld1b1_require_sha256(payload[:simulation_content_sha256],
            "structural-rejection simulation digest")
        ld1b1_data_signature(payload[:data_signature],
            "structural-rejection data signature")
        isempty(strip(ld1b1_string(payload[:issue_code]))) &&
            error("structural-rejection evidence has an empty issue code")
        ld1b1_symbol(payload[:expected_action]) === :pre_fit_reject ||
            error("structural-rejection evidence has the wrong expected action")
        job.expected_action === :pre_fit_reject ||
            error("structural-rejection evidence belongs to an eligible fit job")
        ld1b1_bool(payload[:rejection_confirmed]) ||
            error("structural rejection was not confirmed")
    elseif role === :diagnostic_failure_record
        keys = (:failure_content_sha256, :failure_stage,
            :failure_component, :error_class, :failure_recorded)
        ld1b1_require_only_keys(payload, keys, "diagnostic-failure payload")
        ld1b1_require_sha256(payload[:failure_content_sha256],
            "failure-record digest")
        ld1b1_symbol(payload[:failure_stage]) === :diagnostic ||
            error("diagnostic-failure evidence has the wrong stage")
        component = ld1b1_symbol(payload[:failure_component])
        component in (:sampler_quality_gate, :local_dependence_summary) ||
            error("diagnostic-failure evidence has an unsupported component")
        isempty(strip(ld1b1_string(payload[:error_class]))) &&
            error("diagnostic-failure evidence has an empty error class")
        ld1b1_bool(payload[:failure_recorded]) ||
            error("diagnostic-failure evidence is not recorded")
    else
        keys = (:failure_content_sha256, :failure_stage, :error_class,
            :failure_recorded)
        ld1b1_require_only_keys(payload, keys, "failure evidence payload")
        ld1b1_require_sha256(payload[:failure_content_sha256],
            "failure-record digest")
        expected_stage = role === :generation_failure_record ? :generation :
            role === :fit_failure_record ? :fit :
            role === :diagnostic_failure_record ? :diagnostic :
            error("unsupported failure evidence role: $role")
        ld1b1_symbol(payload[:failure_stage]) === expected_stage ||
            error("failure evidence has the wrong stage")
        isempty(strip(ld1b1_string(payload[:error_class]))) &&
            error("failure evidence has an empty error class")
        ld1b1_bool(payload[:failure_recorded]) ||
            error("failure evidence is not recorded")
    end
    return true
end

function ld1b1_evidence_envelope(identity, job, attempt::Int,
        terminal_status::Symbol, role::Symbol, payload;
        member,
        dependencies = (),
        runner_source_sha256,
        execution_context = ld1b1_execution_context())
    role in ld1b1_required_evidence_roles(terminal_status) ||
        error("evidence role does not belong to terminal status $terminal_status")
    expected_runner_sha256 = ld1b1_expected_job_runner_sha256(identity)
    ld1b1_require_sha256(runner_source_sha256,
        "evidence producer runner source identity") == expected_runner_sha256 ||
        error("evidence producer runner identity differs from the execution plan")
    ld1b1_validate_evidence_payload(payload, role, job, terminal_status)
    ld1b1_require_only_keys(member,
        (:role, :path, :media_type, :bytes, :sha256),
        "job-evidence source member")
    ld1b1_symbol(member[:role]) === ld1b1_evidence_member_role(role) ||
        error("job-evidence source member has the wrong role")
    ld1b1_symbol(member[:media_type]) ===
        ld1b1_evidence_member_media_type(role) ||
        error("job-evidence source member has the wrong media type")
    ld1b1_int(member[:bytes]) > 0 ||
        error("job-evidence source member is empty")
    ld1b1_require_sha256(member[:sha256], "job-evidence source member digest")
    expected_dependencies = Set(
        ld1b1_expected_evidence_dependencies(terminal_status, role))
    dependency_roles = Set{Symbol}()
    for dependency in dependencies
        ld1b1_require_only_keys(dependency, (:role, :content_hash),
            "job-evidence dependency")
        dependency_role = ld1b1_symbol(dependency[:role])
        dependency_role in dependency_roles &&
            error("job-evidence dependency roles must be unique")
        push!(dependency_roles, dependency_role)
        ld1b1_require_sha256(dependency[:content_hash],
            "job-evidence dependency content hash")
    end
    dependency_roles == expected_dependencies ||
        error("job-evidence dependency roles do not match the frozen contract")
    context = ld1b1_validate_execution_context(execution_context)
    attempt_identity = ld1b1_attempt_identity(attempt, context)
    artifact = (;
        schema = LD1B1_EVIDENCE_SCHEMA,
        family = :mfrm,
        scope = context.execution_scope === :pilot ?
            :ld1b1_pilot_job_evidence :
            :ld1b1_bounded_smoke_job_evidence,
        execution_context = context,
        plan_identity = (;
            plan_id = identity.plan_id,
            protocol_plan_id = identity.protocol_plan_id,
            protocol_content_hash = identity.protocol_content_hash,
        ),
        execution_source_identity = identity.execution_source_identity,
        job = (;
            job_id = job.job_id,
            row_index = job.row_index,
            scenario_id = job.scenario_id,
            replication = job.replication,
            seed = job.seed,
            fit_seed = job.fit_seed,
            draw_selection_seed = job.draw_selection_seed,
            posterior_predictive_seed = job.posterior_predictive_seed,
        ),
        attempt = (;
            number = attempt_identity.number,
            role = attempt_identity.role,
            counts_toward_primary =
                attempt_identity.counts_toward_primary,
        ),
        terminal_status,
        evidence_role = role,
        payload_schema = ld1b1_evidence_payload_schema(role),
        source_member = member,
        dependencies = Tuple(dependencies),
        payload,
    )
    return ld1b1_with_content_hash(artifact)
end

function ld1b1_result_envelope(identity, job, attempt::Int,
        terminal_status::Symbol;
        terminal_outcome_code::Symbol =
            ld1b1_terminal_outcome_code(terminal_status),
        retry_reason = nothing,
        retry_of_attempt = nothing,
        primary_result_sha256 = nothing,
        file_manifest = (),
        lineage_valid::Bool = true,
        runner_source_sha256,
        execution_context = ld1b1_execution_context())
    terminal_status in LD1B1_TERMINAL_STATUSES ||
        error("unsupported LD1b1 terminal status: $terminal_status")
    terminal_outcome_code === ld1b1_terminal_outcome_code(terminal_status) ||
        error("terminal outcome code does not match terminal status")
    if job.expected_action === :pre_fit_reject
        terminal_status in (:pre_fit_rejected, :generation_failed) ||
            error("a pre-fit rejection job must reject before fit or record generation failure")
    else
        terminal_status === :pre_fit_rejected &&
            error("an eligible fit job cannot terminate as pre_fit_rejected")
    end
    context = ld1b1_validate_execution_context(execution_context)
    attempt_identity = ld1b1_attempt_identity(attempt, context)
    role = attempt_identity.role
    if context.execution_scope === :bounded_smoke
        retry_reason === nothing || error(
            "bounded smoke cannot have a retry reason")
        retry_of_attempt === nothing || error(
            "bounded smoke cannot identify retry_of")
        primary_result_sha256 === nothing || error(
            "bounded smoke cannot identify a primary-result digest")
    elseif attempt == 1
        retry_reason === nothing || error("primary result cannot have a retry reason")
        retry_of_attempt === nothing || error("primary result cannot identify retry_of")
        primary_result_sha256 === nothing ||
            error("primary result cannot identify a primary-result digest")
    else
        retry_of_attempt == 1 || error("remediation must identify primary attempt 1")
        retry_reason isa AbstractString && !isempty(strip(retry_reason)) ||
            error("remediation requires a nonempty retry reason")
        primary_result_sha256 isa AbstractString &&
            !isempty(primary_result_sha256) ||
            error("remediation requires the primary result SHA-256")
    end
    expected_runner_sha256 = ld1b1_expected_job_runner_sha256(identity)
    ld1b1_require_sha256(runner_source_sha256,
        "job-result runner source identity") == expected_runner_sha256 ||
        error("job-result runner identity differs from the execution plan")
    artifact = (;
        schema = LD1B1_JOB_RESULT_SCHEMA,
        family = :mfrm,
        scope = context.execution_scope === :pilot ?
            :ld1b1_pilot_job_result :
            :ld1b1_bounded_smoke_job_result,
        execution_context = context,
        plan_identity = ld1b1_result_plan_identity(identity),
        execution_source_identity = identity.execution_source_identity,
        job = ld1b1_result_job_identity(job),
        attempt = (;
            number = attempt,
            role,
            counts_toward_primary =
                attempt_identity.counts_toward_primary,
            retry_of_attempt,
            retry_reason,
            primary_result_sha256,
            same_seed_contract = true,
        ),
        terminal_status,
        terminal_outcome_code,
        lineage_valid,
        file_manifest = Tuple(file_manifest),
        primary_outcome_replaced = false,
        pilot_execution_completed = false,
        evaluation_profile_frozen = false,
        calibration_evidence_available = false,
        diagnostic_decision_labels_available = false,
        mechanism_interpretation_eligible = false,
    )
    return ld1b1_with_content_hash(artifact)
end

function ld1b1_regular_file_snapshot(path::AbstractString,
        boundary::AbstractString, label::AbstractString)
    isfile(path) || error("$label is missing")
    islink(path) && error("$label must not be a symbolic link")
    ld1b1_require_realpath_containment(path, boundary)
    bytes, opened = open(path, "r") do io
        metadata = stat(io)
        metadata.nlink == 1 || error("$label must not be hard linked")
        content = read(io)
        return content, metadata
    end
    observed = lstat(path)
    isfile(path) && !islink(path) ||
        error("$label changed type while it was being read")
    observed.nlink == 1 || error("$label must not be hard linked")
    opened.device == observed.device && opened.inode == observed.inode ||
        error("$label was replaced while it was being read")
    opened.size == observed.size == length(bytes) ||
        error("$label changed size while it was being read")
    return (;
        bytes,
        nbytes = length(bytes),
        sha256 = bytes2hex(sha256(bytes)),
        device = opened.device,
        inode = opened.inode,
        nlink = opened.nlink,
    )
end

function ld1b1_portable_inventory_relative_path(
        relative::AbstractString,
        separator = Base.Filesystem.path_separator)
    separator == '/' && return String(relative)
    return replace(String(relative), separator => '/')
end

function ld1b1_attempt_inventory_rows(attempt_dir::AbstractString)
    isdir(attempt_dir) || return ()
    control_files = Set((
        LD1B1AttemptArchive.LD1B_ATTEMPT_SEAL_FILENAME,
        LD1B1AttemptArchive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
    ))
    rows = NamedTuple[]
    for (root, directories, files) in walkdir(attempt_dir;
            follow_symlinks = false)
        for name in sort(directories)
            path = joinpath(root, name)
            relative = ld1b1_portable_inventory_relative_path(
                relpath(path, attempt_dir))
            relative in control_files && continue
            if islink(path)
                push!(rows, (;
                    path = relative,
                    kind = :symbolic_link,
                    bytes = 0,
                    sha256 = bytes2hex(sha256(codeunits(readlink(path)))),
                    link_count = missing,
                ))
            else
                push!(rows, (;
                    path = relative,
                    kind = :directory,
                    bytes = 0,
                    sha256 = missing,
                    link_count = missing,
                ))
            end
        end
        for name in sort(files)
            path = joinpath(root, name)
            relative = ld1b1_portable_inventory_relative_path(
                relpath(path, attempt_dir))
            relative in control_files && continue
            if islink(path)
                push!(rows, (;
                    path = relative,
                    kind = :symbolic_link,
                    bytes = 0,
                    sha256 = bytes2hex(sha256(codeunits(readlink(path)))),
                    link_count = missing,
                ))
            else
                metadata = stat(path)
                push!(rows, (;
                    path = relative,
                    kind = :file,
                    bytes = filesize(path),
                    sha256 = ld1b1_file_sha256(path),
                    link_count = metadata.nlink,
                ))
            end
        end
    end
    sort!(rows; by = row -> (row.path, string(row.kind)))
    return Tuple(rows)
end

function ld1b1_attempt_inventory_sha256(attempt_dir::AbstractString)
    return ld1b1_canonical_sha256(
        ld1b1_attempt_inventory_rows(attempt_dir))
end

function ld1b1_observed_helper_inventory_sha256(
        attempt_dir::AbstractString)
    try
        return LD1B1AttemptArchive.ld1b_attempt_inventory_sha256(
            attempt_dir)
    catch
        return missing
    end
end

function ld1b1_observed_semantic_inventory_sha256(
        attempt_dir::AbstractString)
    try
        return ld1b1_attempt_inventory_sha256(attempt_dir)
    catch
        return missing
    end
end

function ld1b1_observed_path_sha256(path::AbstractString)
    (ispath(path) || islink(path)) || return missing
    islink(path) &&
        return bytes2hex(sha256(codeunits(readlink(path))))
    isfile(path) && return ld1b1_file_sha256(path)
    return ld1b1_canonical_sha256(
        ld1b1_unexpected_inventory_rows(path))
end

function ld1b1_expected_manifest_directories(paths)
    directories = Set{String}()
    for relative in paths
        components = split(String(relative), '/'; keepempty = false)
        for depth in 1:(length(components) - 1)
            push!(directories, join(components[1:depth], '/'))
        end
    end
    return directories
end

function ld1b1_payload_member_sha256(payload, role::Symbol)
    field = role === :generated_data ? :simulation_content_sha256 :
        role === :fit_result ? :fit_artifact_sha256 :
        role === :sampler_diagnostics ? :diagnostics_content_sha256 :
        role === :local_dependence_summary ? :summary_content_sha256 :
        role === :calibration_row ? :calibration_content_sha256 :
        role === :structural_rejection_audit ? :audit_content_sha256 :
        role in (:generation_failure_record, :fit_failure_record,
            :diagnostic_failure_record) ? :failure_content_sha256 :
        error("unsupported evidence-member digest role: $role")
    return ld1b1_require_sha256(payload[field],
        "job-evidence payload source-member digest")
end

function ld1b1_observed_score_signature_from_simulation_source(member)
    table = member[:table]
    fields = (:person, :rater, :item, :response_id, :testlet_id, :score)
    lengths = Tuple(length(table[field]) for field in fields)
    length(unique(lengths)) == 1 || error(
        "simulation table cannot define an observed-score signature with unequal column lengths")
    records = Tuple[]
    for row in 1:first(lengths)
        push!(records, (
            repr(table[:person][row]),
            repr(table[:rater][row]),
            repr(table[:item][row]),
            repr(table[:response_id][row]),
            repr(table[:testlet_id][row]),
            ld1b1_int(table[:score][row]),
        ))
    end
    sort!(records; by = repr)
    return bytes2hex(sha256(codeunits(repr(Tuple(records)))))
end

function ld1b1_validate_source_member_json(bytes, role::Symbol, job, payload,
        terminal_status::Symbol)
    # `String(::Vector{UInt8})` may take ownership of and empty the vector.
    # Validation must not consume bytes that the worker still has to hash and
    # publish in its CREATE_NEW transaction.
    member = JSON3.read(String(copy(bytes)))
    if role === :generated_data
        ld1b1_require_exact_keys(member, (
            :schema, :object, :status, :profile, :grid_id, :scenario_id,
            :matched_set_id, :replication, :phase, :base_seed, :seed,
            :mechanism, :magnitude_label, :effect_scale, :design,
            :assignment, :order, :generator_contract, :data, :table,
            :truth, :row_truth, :validation, :design_support,
            :resource_counts, :checks, :data_signature,
            :testlet_design_signature, :score_signature,
            :truth_known_by_construction, :calibration_status,
            :calibration_evidence_available,
            :diagnostic_decision_labels_available,
            :observed_data_mechanism_interpretation_eligible, :summary,
            :caveat,
        ), "simulation source member")
        ld1b1_string(member[:schema]) ==
            "bayesianmgmfrm.local_dependence_simulation.v1" ||
            error("simulation source member has the wrong schema")
        ld1b1_symbol(member[:object]) === :local_dependence_simulation ||
            error("simulation source member has the wrong object")
        ld1b1_symbol(member[:status]) === :known_truth_generated ||
            error("simulation source member did not complete generation")
        ld1b1_symbol(member[:scenario_id]) === job.scenario_id &&
            ld1b1_symbol(member[:matched_set_id]) === job.matched_set_id &&
            ld1b1_int(member[:replication]) == job.replication &&
            ld1b1_symbol(member[:phase]) === job.phase &&
            ld1b1_int(member[:seed]) == job.seed ||
            error("simulation source member has the wrong job identity")
        for field in (:profile, :grid_id, :mechanism, :magnitude_label,
                :design, :assignment, :order)
            isempty(strip(ld1b1_string(member[field]))) &&
                error("simulation source member has an empty $field")
        end
        ld1b1_int(member[:base_seed]) >= 0 ||
            error("simulation source member has a negative base seed")
        ld1b1_float(member[:effect_scale]) >= 0 ||
            error("simulation source member has a negative effect scale")
        resources = member[:resource_counts]
        ld1b1_require_keys(resources,
            (:n_ratings, :n_probability_cells, :n_truth_cells),
            "simulation resource counts")
        for field in (:n_ratings, :n_probability_cells, :n_truth_cells)
            ld1b1_int(resources[field]) == getproperty(job.resources, field) ||
                error("simulation source member resource mismatch: $field")
        end
        ld1b1_bool(member[:truth_known_by_construction]) &&
            ld1b1_symbol(member[:calibration_status]) ===
                :evaluation_not_run &&
            !ld1b1_bool(member[:calibration_evidence_available]) &&
            !ld1b1_bool(member[:diagnostic_decision_labels_available]) &&
            !ld1b1_bool(
                member[:observed_data_mechanism_interpretation_eligible]) ||
            error("simulation source member exceeds its evidence boundary")
        summary = member[:summary]
        ld1b1_require_exact_keys(summary, (
            :passed, :n_ratings, :n_persons, :n_raters, :n_items,
            :n_testlets, :intended_categories, :realized_categories,
            :category_support_complete, :requested_targets_eligible,
            :future_fit_action,
        ), "simulation summary")
        ld1b1_bool(summary[:passed]) ||
            error("simulation source member did not pass its checks")
        ld1b1_int(summary[:n_ratings]) == job.resources.n_ratings ||
            error("simulation source member summary has the wrong rating count")
        ld1b1_bool(summary[:requested_targets_eligible]) ==
            job.expected_structural_eligibility ||
            error("simulation summary has the wrong structural eligibility")
        ld1b1_require_keys(member[:generator_contract],
            (:fitted_probability_or_likelihood_dependency,),
            "simulation generator contract")
        ld1b1_symbol(member[:generator_contract][
            :fitted_probability_or_likelihood_dependency]) === :none ||
            error("simulation source member depends on a fitted likelihood")
        data = member[:data]
        ld1b1_require_keys(data, (:n, :score), "simulation data")
        ld1b1_int(data[:n]) == job.resources.n_ratings &&
            length(data[:score]) == job.resources.n_ratings ||
            error("simulation data row count is inconsistent")
        data_scores = Tuple(ld1b1_int(value) for value in data[:score])
        table = member[:table]
        table_fields = (
            :person, :rater, :item, :score, :task, :occasion,
            :response_id, :testlet_id, :sequence_index,
            :sequence_fraction, :sequence_phase, :event_id,
            :assignment_reason,
        )
        ld1b1_require_exact_keys(table, table_fields, "simulation table")
        all(field -> length(table[field]) == job.resources.n_ratings,
            table_fields) || error("simulation table columns have wrong lengths")
        Tuple(ld1b1_int(value) for value in table[:score]) == data_scores ||
            error("simulation table scores differ from simulation data")
        length(unique(table[:event_id])) == job.resources.n_ratings ||
            error("simulation event ids are not unique")
        row_truth = member[:row_truth]
        row_truth_fields = (
            :event_id, :canonical_row, :person_index, :rater_index,
            :item_index, :testlet_index, :response_index,
            :sequence_index, :sequence_fraction, :response_uniform,
            :missingness_uniform, :observed_mask, :baseline_location,
            :person_testlet_shift, :response_occasion_shift,
            :rater_response_halo_shift, :rater_task_severity_shift,
            :multidimensional_shift, :temporal_severity_shift,
            :total_location, :probabilities,
        )
        ld1b1_require_exact_keys(
            row_truth, row_truth_fields, "simulation row truth")
        all(field -> field === :probabilities ||
            length(row_truth[field]) == job.resources.n_ratings,
            row_truth_fields) ||
            error("simulation row-truth columns have wrong lengths")
        length(row_truth[:probabilities]) ==
            job.resources.n_probability_cells ||
            error("simulation probability cells have the wrong length")
        Tuple(row_truth[:event_id]) == Tuple(table[:event_id]) ||
            error("simulation row truth is not aligned to event ids")
        all(ld1b1_bool(value) for value in row_truth[:observed_mask]) ||
            error("simulation source member contains unobserved rows")
        probability_values = [
            ld1b1_float(value) for value in row_truth[:probabilities]]
        all(value -> value >= 0, probability_values) ||
            error("simulation source member contains negative probabilities")
        n_categories, remainder = divrem(
            job.resources.n_probability_cells, job.resources.n_ratings)
        remainder == 0 && n_categories >= 2 ||
            error("simulation probability-cell shape is invalid")
        all(row -> abs(sum(@view probability_values[
                ((row - 1) * n_categories + 1):(row * n_categories)]) - 1) <=
                1.0e-12,
            1:job.resources.n_ratings) ||
            error("simulation probability rows do not sum to one")
        truth = member[:truth]
        ld1b1_require_keys(truth, (
            :schema, :generating_mechanism, :active_mechanisms,
            :component_scales, :component_seeds, :person_labels, :testlet_labels,
            :item_labels, :rater_labels, :intended_category_levels,
            :realized_category_levels, :category_support_complete,
        ), "simulation truth")
        ld1b1_string(truth[:schema]) ==
            "bayesianmgmfrm.local_dependence_known_truth.v1" ||
            error("simulation source member has the wrong truth schema")
        intended_categories = Set(
            ld1b1_int(value) for value in truth[:intended_category_levels])
        length(intended_categories) == n_categories &&
            all(score -> score in intended_categories, data_scores) ||
            error("simulation responses differ from intended category support")
        ld1b1_require_keys(member[:validation], (:data_signature,),
            "simulation validation")
        data_signature = ld1b1_data_signature(
            member[:data_signature], "simulation data signature")
        data_signature == ld1b1_data_signature(
            member[:validation][:data_signature],
            "simulation validation data signature") ==
            ld1b1_data_signature(payload[:data_signature],
            "generated-data payload data signature") ||
            error("simulation data signatures are inconsistent")
        ld1b1_require_sha256(member[:score_signature],
            "simulation score signature") ==
            ld1b1_string(payload[:score_signature]) ||
            error("simulation score signature differs from its payload")
        bytes2hex(sha256(codeunits(join(data_scores, ',')))) ==
            ld1b1_string(member[:score_signature]) ||
            error("simulation score signature does not match the responses")
        ld1b1_sha256_record_value(member[:testlet_design_signature],
            "simulation testlet-design signature") ==
            ld1b1_string(payload[:testlet_design_signature_sha256]) ||
            error("simulation design signature differs from its payload")
        ld1b1_require_keys(member[:design_support], (
            :requested_targets_eligible,
            :expected_requested_targets_eligible, :future_fit_action,
        ), "simulation design support")
        ld1b1_bool(member[:design_support][
            :requested_targets_eligible]) ==
            job.expected_structural_eligibility &&
            ld1b1_bool(member[:design_support][
                :expected_requested_targets_eligible]) ==
                job.expected_structural_eligibility ||
            error("simulation design support differs from the frozen job")
        expected_future_action = job.expected_structural_eligibility ?
            :structurally_eligible_for_future_candidate :
            :do_not_fit_underidentified_design
        ld1b1_symbol(member[:design_support][:future_fit_action]) ===
            expected_future_action ||
            error("simulation future-fit action differs from eligibility")
        ld1b1_symbol(summary[:future_fit_action]) === expected_future_action ||
            error("simulation summary future-fit action differs from eligibility")
        ld1b1_bool(summary[:category_support_complete]) || error(
            "pilot simulation source member lacks complete category support")
        ld1b1_int(summary[:n_persons]) == length(truth[:person_labels]) &&
            ld1b1_int(summary[:n_testlets]) ==
                length(truth[:testlet_labels]) &&
            ld1b1_int(summary[:n_items]) == length(truth[:item_labels]) &&
            ld1b1_int(summary[:n_raters]) == length(truth[:rater_labels]) &&
            ld1b1_int(summary[:intended_categories]) ==
                length(truth[:intended_category_levels]) &&
            ld1b1_int(summary[:realized_categories]) ==
                length(truth[:realized_category_levels]) || error(
            "simulation summary dimensions differ from known truth")
        ld1b1_require_keys(member[:checks], (
            :probabilities_finite, :probabilities_nonnegative,
            :score_support_valid, :all_rows_observed,
            :generator_checks_passed,
        ), "simulation checks")
        all(ld1b1_bool(member[:checks][field]) for field in (
            :probabilities_finite, :probabilities_nonnegative,
            :score_support_valid, :all_rows_observed,
            :generator_checks_passed,
        )) || error("simulation source-member checks did not pass")
    elseif role === :fit_result
        ld1b1_require_exact_keys(member, (
            :schema, :object, :serialization, :artifact_content_hash,
            :json_content_hash, :artifact,
        ), "fit-artifact export source member")
        ld1b1_string(member[:schema]) ==
            "bayesianmgmfrm.local_dependence_pilot_fit_artifact_export.v1" &&
            ld1b1_symbol(member[:object]) === :fit_artifact_export ||
            error("fit-artifact export has the wrong schema")
        serialization = member[:serialization]
        ld1b1_require_exact_keys(serialization, (
            :format, :projection, :symbol_values, :missing_values,
            :nonfinite_numbers,
        ), "fit-artifact export serialization")
        ld1b1_symbol(serialization[:format]) === :json &&
            ld1b1_symbol(serialization[:projection]) ===
                :ld1b1_json_native_v1 &&
            ld1b1_symbol(serialization[:symbol_values]) === :string &&
            ld1b1_symbol(serialization[:missing_values]) === :json_null &&
            ld1b1_symbol(serialization[:nonfinite_numbers]) === :rejected ||
            error("fit-artifact export has the wrong serialization contract")
        json_hash = member[:json_content_hash]
        ld1b1_require_exact_keys(json_hash, (
            :algorithm, :value, :scope, :canonicalization,
            :n_canonical_bytes,
        ), "fit-artifact JSON content hash")
        ld1b1_symbol(json_hash[:algorithm]) === :sha256 &&
            ld1b1_symbol(json_hash[:scope]) === :fit_artifact_json_payload &&
            ld1b1_symbol(json_hash[:canonicalization]) ===
                :local_json_sorted_compact ||
            error("fit-artifact JSON content-hash metadata is invalid")
        recomputed_json_hash = ld1b1_json_content_hash_record(
            member[:artifact]; scope = :fit_artifact_json_payload)
        ld1b1_require_sha256(json_hash[:value],
            "fit-artifact JSON content hash") ==
                recomputed_json_hash.value &&
            ld1b1_int(json_hash[:n_canonical_bytes]) ==
                recomputed_json_hash.n_canonical_bytes ||
            error("fit-artifact JSON content hash does not match its payload")
        recomputed_json_hash.value ==
            ld1b1_string(payload[:fit_artifact_json_content_hash]) ||
            error("fit-artifact JSON content hash differs from its evidence payload")
        export_native_hash = member[:artifact_content_hash]
        ld1b1_require_exact_keys(export_native_hash, (
            :algorithm, :value, :scope, :canonicalization,
            :n_canonical_bytes,
        ), "exported native fit-artifact content hash")
        member = member[:artifact]
        ld1b1_require_exact_keys(member, (
            :schema, :object, :created_at,
            :evidence_artifact_schema_policy, :manifest, :diagnostics,
            :posterior_summary, :reproducibility, :environment, :draws,
            :log_posterior, :sampler_stats, :content_hash,
            :archive_manifest,
        ), "fit-artifact source member")
        ld1b1_string(member[:schema]) ==
            "bayesianmgmfrm.fit_artifact.v1" &&
            ld1b1_symbol(member[:object]) === :fit_artifact ||
            error("fit-artifact source member has the wrong schema")
        ld1b1_validate_canonical_fit_artifact_data_signatures(
            member, payload[:data_signature])
        content_hash = member[:content_hash]
        ld1b1_require_exact_keys(content_hash, (
            :algorithm, :value, :scope, :canonicalization,
            :n_canonical_bytes,
        ), "fit-artifact content hash")
        ld1b1_symbol(content_hash[:algorithm]) === :sha256 &&
            ld1b1_symbol(content_hash[:scope]) ===
                :artifact_without_hash_metadata &&
            ld1b1_symbol(content_hash[:canonicalization]) ===
                :cache_stable_string &&
            ld1b1_int(content_hash[:n_canonical_bytes]) > 0 ||
            error("fit-artifact content-hash metadata is invalid")
        artifact_content_hash = ld1b1_require_sha256(
            content_hash[:value], "fit-artifact content hash")
        artifact_content_hash ==
            ld1b1_string(payload[:fit_artifact_content_hash]) ||
            error("fit-artifact content hash differs from its payload")
        ld1b1_canonical_sha256(ld1b1_json_native(export_native_hash)) ==
            ld1b1_canonical_sha256(ld1b1_json_native(content_hash)) ||
            error("exported native fit-artifact hash differs from the artifact")
        archive = member[:archive_manifest]
        ld1b1_require_keys(archive,
            (:schema, :object, :content_hash, :artifact, :manifest,
                :reproducibility, :archive_policy),
            "fit-artifact archive manifest")
        ld1b1_string(archive[:schema]) ==
            "bayesianmgmfrm.fit_archive_manifest.v1" &&
            ld1b1_symbol(archive[:object]) === :fit_archive_manifest ||
            error("fit-artifact archive manifest has the wrong schema")
        ld1b1_require_exact_keys(archive[:content_hash], (
            :algorithm, :value, :scope, :canonicalization,
            :n_canonical_bytes,
        ), "fit-artifact archive content hash")
        ld1b1_require_sha256(archive[:content_hash][:value],
            "fit-artifact archive content hash") == artifact_content_hash ||
            error("fit-artifact archive content hash is inconsistent")
        ld1b1_canonical_sha256(ld1b1_json_native(
            archive[:content_hash])) ==
            ld1b1_canonical_sha256(ld1b1_json_native(content_hash)) ||
            error("fit-artifact archive content-hash record is inconsistent")
        manifest = member[:manifest]
        ld1b1_require_keys(manifest,
            (:schema, :object, :validation, :fit, :diagnostics),
            "fit-artifact model manifest")
        ld1b1_string(manifest[:schema]) ==
            "bayesianmgmfrm.model_manifest.v1" &&
            ld1b1_symbol(manifest[:object]) === :fit ||
            error("fit-artifact model manifest has the wrong schema")
        fit = manifest[:fit]
        ld1b1_require_keys(fit, (
            :n_observations, :family, :n_parameters, :n_draws,
            :n_chains, :draws_per_chain, :n_log_posterior, :backend,
            :sampler, :warmup, :sampler_controls, :n_sampler_stats,
            :data_signature,
        ), "fit-artifact fit metadata")
        sampler = job.sampler_contract
        ld1b1_int(fit[:n_observations]) == job.resources.n_ratings &&
            ld1b1_symbol(fit[:family]) === :mfrm &&
            ld1b1_int(fit[:n_parameters]) >= 1 &&
            ld1b1_int(fit[:n_draws]) == sampler.total_retained_draws &&
            ld1b1_int(fit[:n_chains]) == sampler.chains &&
            ld1b1_int(fit[:draws_per_chain]) == sampler.draws_per_chain &&
            ld1b1_int(fit[:n_log_posterior]) ==
                sampler.total_retained_draws &&
            ld1b1_symbol(fit[:backend]) === sampler.backend &&
            ld1b1_symbol(fit[:sampler]) === sampler.algorithm &&
            ld1b1_int(fit[:warmup]) == sampler.warmup_per_chain &&
            ld1b1_int(fit[:n_sampler_stats]) ==
                sampler.total_retained_draws ||
            error("fit-artifact metadata differs from the frozen job")
        data_signature = ld1b1_data_signature(fit[:data_signature],
            "fit-artifact data signature")
        data_signature == ld1b1_data_signature(
            manifest[:validation][:data_signature],
            "fit-artifact validation data signature") ==
            ld1b1_data_signature(payload[:data_signature],
                "fit-result payload data signature") ||
            error("fit-artifact data signatures are inconsistent")
        controls = fit[:sampler_controls]
        ld1b1_require_keys(controls, (
            :ndraws, :warmup, :chains, :target_accept, :max_depth,
            :metric, :ad_backend, :rng,
        ), "fit-artifact sampler controls")
        ld1b1_int(controls[:ndraws]) == sampler.draws_per_chain &&
            ld1b1_int(controls[:warmup]) == sampler.warmup_per_chain &&
            ld1b1_int(controls[:chains]) == sampler.chains &&
            ld1b1_float(controls[:target_accept]) == sampler.target_accept &&
            ld1b1_int(controls[:max_depth]) == sampler.max_depth &&
            ld1b1_symbol(controls[:metric]) === sampler.metric &&
            ld1b1_symbol(controls[:ad_backend]) === sampler.ad_backend ||
            error("fit-artifact sampler controls differ from the frozen job")
        rng = controls[:rng]
        ld1b1_require_keys(rng, (:seed, :replayable),
            "fit-artifact RNG controls")
        ld1b1_int(rng[:seed]) == job.fit_seed &&
            ld1b1_bool(rng[:replayable]) ||
            error("fit-artifact RNG controls are not replayable")
        reproducibility = member[:reproducibility]
        ld1b1_require_keys(reproducibility, (
            :data_signature, :rng, :replayable_rng, :sampler_controls,
            :diagnostic_policy, :artifact_policy,
        ), "fit-artifact reproducibility record")
        ld1b1_data_signature(reproducibility[:data_signature],
            "fit-artifact reproducibility data signature") ==
            data_signature &&
            ld1b1_int(reproducibility[:rng][:seed]) == job.fit_seed &&
            ld1b1_bool(reproducibility[:replayable_rng]) ||
            error("fit-artifact reproducibility record is inconsistent")
        policy = reproducibility[:artifact_policy]
        for field in (:draws, :log_posterior, :sampler_stats)
            ld1b1_symbol(policy[field]) === :included ||
                error("fit-artifact omits required $field")
        end
        n_draws = sampler.total_retained_draws
        n_parameters = ld1b1_int(fit[:n_parameters])
        length(member[:posterior_summary]) == n_parameters ||
            error("fit-artifact posterior summary has the wrong length")
        length(member[:draws]) == n_draws * n_parameters &&
            length(member[:log_posterior]) == n_draws &&
            length(member[:sampler_stats]) == n_draws ||
            error("fit-artifact retained arrays have wrong lengths")
        for (index, stat) in pairs(member[:sampler_stats])
            ld1b1_require_keys(stat, (:chain, :iteration),
                "fit-artifact sampler-stat row")
            expected_chain = div(index - 1, sampler.draws_per_chain) + 1
            expected_iteration = mod(index - 1, sampler.draws_per_chain) + 1
            ld1b1_int(stat[:chain]) == expected_chain &&
                ld1b1_int(stat[:iteration]) == expected_iteration ||
                error("fit-artifact sampler-stat identities are not canonical")
        end
        retained_draw_set_sha256 = ld1b1_canonical_sha256((;
            draws = ld1b1_json_native(member[:draws]),
            log_posterior = ld1b1_json_native(member[:log_posterior]),
            sampler_stats = ld1b1_json_native(member[:sampler_stats]),
        ))
        retained_draw_set_sha256 ==
            ld1b1_string(payload[:retained_draw_set_sha256]) ||
            error("fit-artifact retained-draw digest differs from its payload")
    elseif role === :sampler_diagnostics
        ld1b1_require_exact_keys(member,
            (:schema, :object, :backend, :sampler, :fit_artifact_sha256,
                :fit_artifact_content_hash, :data_signature,
                :retained_draw_set_sha256, :chain_ids, :iterations,
                :summary),
            "diagnostics source member")
        ld1b1_string(member[:schema]) ==
            "bayesianmgmfrm.local_dependence_pilot_sampler_diagnostics_bundle.v1" &&
            ld1b1_symbol(member[:object]) === :sampler_diagnostics_bundle ||
            error("diagnostics source member has the wrong schema")
        ld1b1_symbol(member[:backend]) === job.sampler_contract.backend &&
            ld1b1_symbol(member[:sampler]) === job.sampler_contract.algorithm ||
            error("diagnostics source member has the wrong sampler identity")
        for field in (:fit_artifact_sha256, :fit_artifact_content_hash,
                :retained_draw_set_sha256)
            ld1b1_require_sha256(member[field],
                "diagnostics source-member $field") ==
                ld1b1_string(payload[field]) ||
                error("diagnostics source-member $field differs from its payload")
        end
        ld1b1_data_signature(member[:data_signature],
            "diagnostics source-member data signature") ==
            ld1b1_data_signature(payload[:data_signature],
                "diagnostics payload data signature") ||
            error("diagnostics data signature differs from its payload")
        sampler = job.sampler_contract
        total_draws = sampler.total_retained_draws
        chain_ids = Tuple(ld1b1_int(value) for value in member[:chain_ids])
        iterations = Tuple(ld1b1_int(value) for value in member[:iterations])
        length(chain_ids) == length(iterations) == total_draws ||
            error("diagnostics retained-draw identities have wrong lengths")
        all(1 <= value <= sampler.chains for value in chain_ids) &&
            all(1 <= value <= sampler.draws_per_chain for value in iterations) ||
            error("diagnostics retained-draw identities are out of range")
        expected_draw_identities = Tuple((chain, iteration)
            for chain in 1:sampler.chains
            for iteration in 1:sampler.draws_per_chain)
        Tuple(zip(chain_ids, iterations)) == expected_draw_identities ||
            error("diagnostics retained-draw identities are not canonical")
        summary = member[:summary]
        ld1b1_require_exact_keys(summary, (
            :diagnostic_contract, :diagnostic_contract_details, :flag,
            :passed, :n_chains, :draws_per_chain, :total_draws,
            :split_chains_requested, :split_chains,
            :max_rank_normalized_rhat, :min_bulk_ess, :min_tail_ess,
            :n_divergences, :n_max_treedepth, :e_bfmi,
            :n_e_bfmi_expected, :n_e_bfmi_available,
            :n_e_bfmi_unavailable, :e_bfmi_complete,
        ), "diagnostics source-member summary")
        comparisons = (
            ld1b1_symbol(summary[:diagnostic_contract]) ===
                ld1b1_symbol(payload[:diagnostic_contract]),
            ld1b1_canonical_sha256(ld1b1_json_native(
                summary[:diagnostic_contract_details])) ==
                ld1b1_string(payload[:diagnostic_contract_details_sha256]),
            ld1b1_symbol(summary[:flag]) ===
                ld1b1_symbol(payload[:diagnostics_flag]),
            ld1b1_bool(summary[:passed]) ==
                ld1b1_bool(payload[:diagnostics_passed]),
            ld1b1_int(summary[:n_chains]) == ld1b1_int(payload[:n_chains]),
            ld1b1_int(summary[:draws_per_chain]) ==
                ld1b1_int(payload[:draws_per_chain]),
            ld1b1_int(summary[:total_draws]) ==
                ld1b1_int(payload[:total_draws]),
            ld1b1_bool(summary[:split_chains_requested]) ==
                ld1b1_bool(payload[:split_chains_requested]),
            ld1b1_bool(summary[:split_chains]) ==
                ld1b1_bool(payload[:split_chains]),
            ld1b1_float(summary[:max_rank_normalized_rhat]) ==
                ld1b1_float(payload[:max_rank_normalized_rhat]),
            ld1b1_float(summary[:min_bulk_ess]) ==
                ld1b1_float(payload[:min_bulk_ess]),
            ld1b1_float(summary[:min_tail_ess]) ==
                ld1b1_float(payload[:min_tail_ess]),
            ld1b1_int(summary[:n_divergences]) ==
                ld1b1_int(payload[:n_divergences]),
            ld1b1_int(summary[:n_max_treedepth]) ==
                ld1b1_int(payload[:n_max_treedepth]),
            isequal(ld1b1_optional_float(summary[:e_bfmi]),
                ld1b1_optional_float(payload[:e_bfmi])),
            ld1b1_int(summary[:n_e_bfmi_expected]) ==
                ld1b1_int(payload[:n_e_bfmi_expected]),
            ld1b1_int(summary[:n_e_bfmi_available]) ==
                ld1b1_int(payload[:n_e_bfmi_available]),
            ld1b1_int(summary[:n_e_bfmi_unavailable]) ==
                ld1b1_int(payload[:n_e_bfmi_unavailable]),
            ld1b1_bool(summary[:e_bfmi_complete]) ==
                ld1b1_bool(payload[:e_bfmi_complete]),
        )
        all(comparisons) ||
            error("diagnostics source member differs from its evidence payload")
    elseif role === :local_dependence_summary
        ld1b1_require_exact_keys(member, (
            :schema, :object, :status, :family, :model_thresholds,
            :profile, :frozen_profile, :calibration_status,
            :calibration_required, :decision_labels_available,
            :mechanism_interpretation_eligible, :conditioning,
            :prediction_target, :draw_source, :draw_selection_algorithm,
            :draw_selection_seed, :posterior_predictive_seed,
            :draw_indices, :chain_ids,
            :iterations, :n_draws,
            :replicated_datasets_per_parameter_draw, :replication_source,
            :interval_probability, :data_signature,
            :observed_score_signature, :design_signature, :contract,
            :retained_draw_set_sha256,
            :diagnostic_thresholds, :computational_support,
            :design_support, :selected_families, :family_rows,
            :family_testlet_rows, :pair_rows, :family_max_rows,
            :global_evidence, :residual_support, :n_pair_rows,
            :n_summary_supported_pairs, :decision, :caveats,
        ), "local-dependence-summary source member")
        ld1b1_string(member[:schema]) ==
            "bayesianmgmfrm.local_dependence_pilot_summary_bundle.v1" &&
            ld1b1_symbol(member[:object]) ===
                :local_dependence_pilot_summary_bundle ||
            error("local-dependence-summary source member has the wrong schema")
        draw_indices = Tuple(ld1b1_int(value) for value in member[:draw_indices])
        length(draw_indices) == length(unique(draw_indices)) ==
            job.sampler_contract.diagnostic_draws || error(
            "local-dependence-summary source member has invalid draw indices")
        all(1 <= value <= job.sampler_contract.total_retained_draws
            for value in draw_indices) || error(
            "local-dependence-summary draw indices are out of range")
        ld1b1_symbol(member[:draw_selection_algorithm]) ===
            LD1B1_DRAW_SELECTION_ALGORITHM || error(
            "local-dependence-summary source member has the wrong draw-selection algorithm")
        draw_indices == ld1b1_expected_draw_indices(
            job.draw_selection_seed,
            job.sampler_contract.total_retained_draws,
            job.sampler_contract.diagnostic_draws,
        ) || error(
            "local-dependence-summary draw indices do not match the frozen seed")
        chain_ids = Tuple(ld1b1_int(value) for value in member[:chain_ids])
        iterations = Tuple(ld1b1_int(value) for value in member[:iterations])
        length(chain_ids) == length(iterations) == length(draw_indices) ||
            error("local-dependence-summary draw identities are incomplete")
        all(1 <= value <= job.sampler_contract.chains for value in chain_ids) &&
            all(1 <= value <= job.sampler_contract.draws_per_chain
                for value in iterations) ||
            error("local-dependence-summary draw identities are out of range")
        ld1b1_int(member[:n_draws]) == length(draw_indices) &&
            ld1b1_int(member[:replicated_datasets_per_parameter_draw]) ==
                job.sampler_contract.posterior_predictive_replicates_per_draw ||
            error("local-dependence-summary source member has wrong draw counts")
        ld1b1_int(member[:draw_selection_seed]) == job.draw_selection_seed ==
            ld1b1_int(payload[:draw_selection_seed]) &&
            ld1b1_int(member[:posterior_predictive_seed]) ==
                job.posterior_predictive_seed ==
                ld1b1_int(payload[:posterior_predictive_seed]) ||
            error("local-dependence-summary source member has wrong execution seeds")
        !ld1b1_bool(member[:decision_labels_available]) &&
            !ld1b1_bool(member[:mechanism_interpretation_eligible]) ||
            error("local-dependence-summary source member exceeds its boundary")
        ld1b1_symbol(member[:family]) === :mfrm &&
            ld1b1_symbol(member[:model_thresholds]) === :partial_credit &&
            ld1b1_bool(member[:frozen_profile]) &&
            ld1b1_symbol(member[:calibration_status]) ===
                :pending_independent_known_truth_simulation &&
            ld1b1_bool(member[:calibration_required]) &&
            ld1b1_symbol(member[:draw_source]) ===
                :distinct_posterior_draws ||
            error("local-dependence-summary contract fields are invalid")
        ismissing(ld1b1_get(member, :decision, missing)) ||
            error("pilot local-dependence summary contains a decision label")
        ld1b1_data_signature(member[:data_signature],
            "local-dependence-summary data signature") ==
            ld1b1_data_signature(payload[:data_signature],
                "local-dependence payload data signature") ||
            error("local-dependence data signature differs from its payload")
        ld1b1_sha256_record_value(member[:observed_score_signature],
            "local-dependence observed-score signature") ==
            ld1b1_string(payload[:observed_score_signature_sha256]) ||
            error("local-dependence score signature differs from its payload")
        ld1b1_sha256_record_value(member[:design_signature],
            "local-dependence design signature") ==
            ld1b1_string(payload[:design_signature_sha256]) ||
            error("local-dependence design signature differs from its payload")
        ld1b1_canonical_sha256(ld1b1_json_native(member[:contract])) ==
            job.quality_contract.local_dependence_contract_sha256 ||
            error("local-dependence summary uses the wrong frozen contract")
        ld1b1_require_sha256(member[:retained_draw_set_sha256],
            "local-dependence retained-draw digest") ==
            ld1b1_string(payload[:retained_draw_set_sha256]) ||
            error("local-dependence retained-draw digest differs from its payload")
        Tuple(ld1b1_symbol(value) for value in member[:selected_families]) == (
            :single_rating_item_q3,
            :within_rater_item_q3,
            :rater_on_shared_response_criterion,
        ) || error("local-dependence selected-family contract was modified")
        ld1b1_int(member[:n_pair_rows]) == length(member[:pair_rows]) ||
            error("local-dependence pair-row count is inconsistent")
        0 <= ld1b1_int(member[:n_summary_supported_pairs]) <=
            ld1b1_int(member[:n_pair_rows]) ||
            error("local-dependence supported-pair count is inconsistent")
        ld1b1_symbol(member[:status]) in (
            :report_only,
            :undefined_residual_variation,
            :insufficient_draw_support,
            :no_eligible_pairs,
        ) || error("local-dependence-summary source member has invalid status")
    elseif role === :calibration_row
        required = (
            :schema, :object, :profile, :planning_profile, :protocol_status,
            :status, :contract, :grid_id, :row_index, :scenario_index,
            :scenario_id, :matched_set_id, :replication, :phase, :base_seed,
            :seed, :component_seeds, :mechanism, :magnitude_label,
            :effect_scale, :design, :assignment, :order,
            :expected_structural_eligibility, :planning_shape, :truth,
            :execution_seeds, :failure_code, :simulation_provenance,
            :diagnostic_provenance, :n_pair_evidence, :pair_evidence,
            :family_evidence, :global_evidence, :target_evidence,
            :target_evidence_available, :pair_truth_oracle_available,
            :pairwise_power_available, :repeated_calibration_completed,
            :calibration_evidence_available,
            :diagnostic_decision_labels_available,
            :mechanism_interpretation_eligible, :caveat,
        )
        ld1b1_require_exact_keys(member, required,
            "calibration-row source member")
        ld1b1_string(member[:schema]) ==
            "bayesianmgmfrm.local_dependence_calibration_row.v1" &&
            ld1b1_symbol(member[:object]) === :local_dependence_calibration_row ||
            error("calibration-row source member has the wrong schema or status")
        expected_status = ld1b1_symbol(payload[:status])
        expected_status in LD1B1_TERMINAL_STATUSES &&
            expected_status === terminal_status &&
            ld1b1_symbol(member[:status]) === expected_status ||
            error("calibration-row source member has the wrong status")
        ld1b1_int(member[:row_index]) == job.row_index &&
            ld1b1_int(member[:scenario_index]) == job.scenario_index &&
            ld1b1_symbol(member[:scenario_id]) === job.scenario_id &&
            ld1b1_symbol(member[:matched_set_id]) === job.matched_set_id &&
            ld1b1_int(member[:replication]) == job.replication &&
            ld1b1_symbol(member[:phase]) === job.phase &&
            ld1b1_int(member[:seed]) == job.seed &&
            ld1b1_bool(member[:expected_structural_eligibility]) ==
                job.expected_structural_eligibility ||
            error("calibration-row source member has the wrong job identity")
        ld1b1_symbol(member[:protocol_status]) === :protocol_preflight_only ||
            error("calibration-row source member has the wrong protocol status")
        for field in (:profile, :planning_profile, :grid_id, :mechanism,
                :magnitude_label, :design, :assignment, :order)
            isempty(strip(ld1b1_string(member[field]))) &&
                error("calibration-row source member has an empty $field")
        end
        ld1b1_float(member[:effect_scale]) >= 0 ||
            error("calibration-row source member has a negative effect scale")
        ld1b1_canonical_sha256(ld1b1_json_native(member[:contract])) ==
            job.quality_contract.calibration_contract_sha256 ||
            error("calibration-row source member uses the wrong contract")
        for field in (:component_seeds, :planning_shape, :truth)
            ismissing(ld1b1_get(member, field, missing)) &&
                error("calibration-row source member lacks $field")
        end
        failure_code = ld1b1_get(member, :failure_code, missing)
        if expected_status in LD1B1_CATEGORIZED_FAILURE_STATUSES
            ismissing(failure_code) &&
                error("failed calibration row lacks a failure code")
            isempty(strip(ld1b1_string(failure_code))) &&
                error("failed calibration row has an empty failure code")
        else
            ismissing(failure_code) ||
                error("non-failed calibration row contains a failure code")
        end
        execution_seeds = member[:execution_seeds]
        ld1b1_require_exact_keys(execution_seeds,
            (:fit, :draw_selection, :posterior_predictive, :contract),
            "calibration-row execution seeds")
        ld1b1_int(execution_seeds[:fit]) == job.fit_seed &&
            ld1b1_int(execution_seeds[:draw_selection]) ==
                job.draw_selection_seed &&
            ld1b1_int(execution_seeds[:posterior_predictive]) ==
                job.posterior_predictive_seed ||
            error("calibration-row source member has the wrong execution seeds")
        ld1b1_canonical_sha256(ld1b1_json_native(
            execution_seeds[:contract])) ==
            ld1b1_canonical_sha256(ld1b1_json_native(
                member[:contract][:seed_contract])) ||
            error("calibration-row execution seed contract is inconsistent")
        simulation_provenance = ld1b1_get(
            member, :simulation_provenance, missing)
        data_signature = missing
        if expected_status === :generation_failed
            ismissing(simulation_provenance) || error(
                "generation-failure calibration row contains simulation provenance")
        else
            ismissing(simulation_provenance) &&
                error("calibration row lacks simulation provenance")
            ld1b1_require_exact_keys(simulation_provenance, (
                :status, :data_signature, :score_signature,
                :observed_score_signature, :testlet_design_signature,
                :n_ratings, :planning_shape, :observed_shape,
                :requested_targets_eligible, :future_fit_action,
            ), "calibration-row simulation provenance")
            ld1b1_symbol(simulation_provenance[:status]) ===
                :known_truth_generated &&
                ld1b1_int(simulation_provenance[:n_ratings]) ==
                    job.resources.n_ratings &&
                ld1b1_bool(simulation_provenance[
                    :requested_targets_eligible]) ==
                    job.expected_structural_eligibility ||
                error("calibration-row simulation provenance is inconsistent")
            data_signature = ld1b1_data_signature(
                simulation_provenance[:data_signature],
                "calibration-row simulation data signature")
            data_signature == ld1b1_data_signature(payload[:data_signature],
                "calibration-row payload data signature") ||
                error("calibration-row data signature differs from its payload")
            ld1b1_sha256_record_value(
                simulation_provenance[:observed_score_signature],
                "calibration-row observed-score signature") ==
                ld1b1_string(payload[:observed_score_signature_sha256]) ||
                error("calibration-row score signature differs from its payload")
            ld1b1_sha256_record_value(
                simulation_provenance[:testlet_design_signature],
                "calibration-row design signature") ==
                ld1b1_string(payload[:design_signature_sha256]) ||
                error("calibration-row design signature differs from its payload")
        end
        diagnostic_provenance = ld1b1_get(
            member, :diagnostic_provenance, missing)
        if expected_status === :completed
            ismissing(diagnostic_provenance) &&
                error("completed calibration row lacks diagnostic provenance")
            ld1b1_require_exact_keys(diagnostic_provenance, (
                :status, :profile, :n_draws, :data_signature,
                :observed_score_signature, :design_signature,
            ), "calibration-row diagnostic provenance")
            ld1b1_data_signature(diagnostic_provenance[:data_signature],
                "calibration-row diagnostic data signature") ==
                data_signature &&
                ld1b1_int(diagnostic_provenance[:n_draws]) ==
                    job.sampler_contract.diagnostic_draws ||
                error("calibration-row diagnostic provenance is inconsistent")
            ld1b1_sha256_record_value(
                diagnostic_provenance[:observed_score_signature],
                "calibration-row diagnostic score signature") ==
                ld1b1_string(payload[:observed_score_signature_sha256]) &&
                ld1b1_sha256_record_value(
                    diagnostic_provenance[:design_signature],
                    "calibration-row diagnostic design signature") ==
                    ld1b1_string(payload[:design_signature_sha256]) ||
                error("calibration-row diagnostic signatures are inconsistent")
        else
            ismissing(diagnostic_provenance) ||
                error("non-completed calibration row contains diagnostic provenance")
            isempty(member[:pair_evidence]) &&
                isempty(member[:family_evidence]) &&
                ismissing(ld1b1_get(member, :global_evidence, missing)) ||
                error("non-completed calibration row contains diagnostic evidence")
        end
        ld1b1_int(member[:n_pair_evidence]) == length(member[:pair_evidence]) ||
            error("calibration-row pair evidence count is inconsistent")
        ismissing(ld1b1_get(member, :target_evidence, missing)) ||
            error("calibration row contains target evidence")
        !ld1b1_bool(member[:target_evidence_available]) &&
            !ld1b1_bool(member[:pair_truth_oracle_available]) &&
            !ld1b1_bool(member[:pairwise_power_available]) &&
            !ld1b1_bool(member[:repeated_calibration_completed]) &&
            !ld1b1_bool(member[:calibration_evidence_available]) &&
            !ld1b1_bool(member[:diagnostic_decision_labels_available]) &&
            !ld1b1_bool(member[:mechanism_interpretation_eligible]) ||
            error("calibration-row source member exceeds its evidence boundary")
        ld1b1_symbol(member[:caveat]) ===
            :candidate_diagnostic_decisions_for_protocol_preflight_only ||
            error("calibration-row caveat was modified")
    elseif role === :structural_rejection_audit
        ld1b1_require_only_keys(member, (
            :schema, :object, :job_id, :row_index, :scenario_id,
            :replication, :simulation_content_sha256, :data_signature,
            :expected_action, :issue_code, :rejection_confirmed,
        ), "structural-rejection source member")
        ld1b1_string(member[:schema]) ==
            "bayesianmgmfrm.local_dependence_pilot_structural_rejection_audit.v1" &&
            ld1b1_symbol(member[:object]) === :structural_rejection_audit ||
            error("structural-rejection source member has the wrong schema")
        ld1b1_string(member[:job_id]) == job.job_id &&
            ld1b1_int(member[:row_index]) == job.row_index &&
            ld1b1_symbol(member[:scenario_id]) === job.scenario_id &&
            ld1b1_int(member[:replication]) == job.replication &&
            ld1b1_require_sha256(member[:simulation_content_sha256],
                "structural-rejection simulation digest") ==
                ld1b1_string(payload[:simulation_content_sha256]) &&
            ld1b1_data_signature(member[:data_signature],
                "structural-rejection data signature") ==
                ld1b1_data_signature(payload[:data_signature],
                    "structural-rejection payload data signature") &&
            ld1b1_symbol(member[:expected_action]) === :pre_fit_reject &&
            ld1b1_symbol(member[:issue_code]) ===
                ld1b1_symbol(payload[:issue_code]) &&
            ld1b1_bool(member[:rejection_confirmed]) ||
            error("structural-rejection source member is inconsistent")
    else
        failure_keys = role === :diagnostic_failure_record ? (
            :schema, :object, :job_id, :row_index, :scenario_id,
            :replication, :failure_stage, :failure_component,
            :error_class, :failure_recorded,
        ) : (
            :schema, :object, :job_id, :row_index, :scenario_id,
            :replication, :failure_stage, :error_class, :failure_recorded,
        )
        ld1b1_require_only_keys(
            member, failure_keys, "failure-record source member")
        ld1b1_string(member[:schema]) ==
            "bayesianmgmfrm.local_dependence_pilot_failure_record.v1" &&
            ld1b1_symbol(member[:object]) === role ||
            error("failure-record source member has the wrong schema")
        ld1b1_string(member[:job_id]) == job.job_id &&
            ld1b1_int(member[:row_index]) == job.row_index &&
            ld1b1_symbol(member[:scenario_id]) === job.scenario_id &&
            ld1b1_int(member[:replication]) == job.replication &&
            ld1b1_symbol(member[:failure_stage]) ===
                ld1b1_symbol(payload[:failure_stage]) &&
            (role !== :diagnostic_failure_record ||
                ld1b1_symbol(member[:failure_component]) ===
                    ld1b1_symbol(payload[:failure_component])) &&
            ld1b1_symbol(member[:error_class]) ===
                ld1b1_symbol(payload[:error_class]) &&
            ld1b1_bool(member[:failure_recorded]) ||
            error("failure-record source member is inconsistent")
    end
    return member
end

function ld1b1_validate_cross_evidence_lineage(evidence_by_role,
        terminal_status::Symbol, job)
    if terminal_status in LD1B1_CATEGORIZED_FAILURE_STATUSES
        failure_role = terminal_status === :generation_failed ?
            :generation_failure_record : terminal_status === :fit_failed ?
                :fit_failure_record : :diagnostic_failure_record
        haskey(evidence_by_role, failure_role) || error(
            "failed calibration result lacks its failure record")
        haskey(evidence_by_role, :calibration_row) || error(
            "failed calibration result lacks its calibration row")
        calibration = evidence_by_role[:calibration_row]
        ld1b1_symbol(calibration.payload[:status]) === terminal_status &&
            ld1b1_symbol(calibration.source_value[:status]) ===
                terminal_status ||
            error("failed calibration row has the wrong terminal status")
        ld1b1_symbol(calibration.source_value[:failure_code]) ===
            ld1b1_symbol(evidence_by_role[
                failure_role].payload[:error_class]) || error(
            "calibration failure code is not linked to its failure record")
    end

    haskey(evidence_by_role, :generated_data) || return true
    generated = evidence_by_role[:generated_data]
    generated_payload = generated.payload
    generated_source = generated.source_value
    data_signature = ld1b1_data_signature(
        generated_payload[:data_signature], "generated-data lineage signature")

    if haskey(evidence_by_role, :fit_result)
        fit = evidence_by_role[:fit_result]
        fit_payload = fit.payload
        ld1b1_data_signature(fit_payload[:data_signature],
            "fit lineage data signature") == data_signature ||
            error("fit result is not linked to the generated dataset")
        if haskey(evidence_by_role, :sampler_diagnostics)
            sampler = evidence_by_role[:sampler_diagnostics]
            sampler_payload = sampler.payload
            for field in (:fit_artifact_content_hash,
                    :retained_draw_set_sha256)
                ld1b1_string(sampler_payload[field]) ==
                    ld1b1_string(fit_payload[field]) ||
                    error("sampler diagnostics are not linked to fit field $field")
            end
            ld1b1_string(sampler_payload[:fit_artifact_sha256]) ==
                fit.source_snapshot.sha256 ||
                error("sampler diagnostics are not linked to the fit artifact")
            ld1b1_data_signature(sampler_payload[:data_signature],
                "sampler lineage data signature") == data_signature ||
                error("sampler diagnostics are not linked to the generated dataset")
            fit_stats = ld1b1_field(fit.source_value, :sampler_stats)
            sampler_source = sampler.source_value
            sampler_chain_ids = ld1b1_field(sampler_source, :chain_ids)
            sampler_iterations = ld1b1_field(sampler_source, :iterations)
            Tuple(ld1b1_int(ld1b1_field(row, :chain))
                for row in fit_stats) ==
                Tuple(ld1b1_int(value) for value in sampler_chain_ids) &&
                Tuple(ld1b1_int(ld1b1_field(row, :iteration))
                    for row in fit_stats) ==
                Tuple(ld1b1_int(value) for value in sampler_iterations) ||
                error("sampler draw identities do not match the fit artifact")
        end
    end

    if haskey(evidence_by_role, :local_dependence_summary)
        local_evidence = evidence_by_role[:local_dependence_summary]
        local_payload = local_evidence.payload
        ld1b1_data_signature(local_payload[:data_signature],
            "local-dependence lineage data signature") == data_signature ||
            error("local-dependence summary is not linked to the generated dataset")
        ld1b1_string(local_payload[:design_signature_sha256]) ==
            ld1b1_string(generated_payload[
                :testlet_design_signature_sha256]) ||
            error("local-dependence summary is not linked to the generated design")
        fit_payload = evidence_by_role[:fit_result].payload
        ld1b1_string(local_payload[:retained_draw_set_sha256]) ==
            ld1b1_string(fit_payload[:retained_draw_set_sha256]) ||
            error("local-dependence summary is not linked to the retained draws")
        sampler_source =
            evidence_by_role[:sampler_diagnostics].source_value
        local_source = local_evidence.source_value
        draw_indices = Tuple(ld1b1_int(value) for value in
            ld1b1_field(local_source, :draw_indices))
        sampler_chain_ids = ld1b1_field(sampler_source, :chain_ids)
        sampler_iterations = ld1b1_field(sampler_source, :iterations)
        selected_chain_ids = Tuple(ld1b1_int(
            sampler_chain_ids[index]) for index in draw_indices)
        selected_iterations = Tuple(ld1b1_int(
            sampler_iterations[index]) for index in draw_indices)
        Tuple(ld1b1_int(value) for value in
                ld1b1_field(local_source, :chain_ids)) ==
            selected_chain_ids &&
            Tuple(ld1b1_int(value) for value in
                ld1b1_field(local_source, :iterations)) ==
                selected_iterations ||
            error("local-dependence draw identities do not match sampler draws")
    end

    if haskey(evidence_by_role, :structural_rejection_audit)
        rejection_payload =
            evidence_by_role[:structural_rejection_audit].payload
        ld1b1_string(rejection_payload[:simulation_content_sha256]) ==
            generated.source_snapshot.sha256 ||
            error("structural rejection is not linked to its simulation")
        ld1b1_data_signature(rejection_payload[:data_signature],
            "structural-rejection lineage signature") == data_signature ||
            error("structural rejection is not linked to the generated dataset")
    end

    if haskey(evidence_by_role, :calibration_row)
        calibration = evidence_by_role[:calibration_row]
        calibration_payload = calibration.payload
        calibration_source = calibration.source_value
        ld1b1_data_signature(calibration_payload[:data_signature],
            "calibration lineage data signature") == data_signature ||
            error("calibration row is not linked to the generated dataset")
        ld1b1_symbol(calibration_source[:planning_profile]) ===
            ld1b1_symbol(generated_source[:profile]) ||
            error("calibration row is not linked to the simulation profile")
        for field in (:grid_id, :matched_set_id, :phase, :base_seed,
                :mechanism, :magnitude_label, :effect_scale, :design,
                :assignment, :order)
            left = calibration_source[field]
            right = generated_source[field]
            matches = field === :effect_scale ?
                ld1b1_float(left) == ld1b1_float(right) :
                field === :base_seed ?
                    ld1b1_int(left) == ld1b1_int(right) :
                    ld1b1_string(left) == ld1b1_string(right)
            matches || error(
                "calibration row is not linked to simulation field $field")
        end
        ld1b1_canonical_sha256(ld1b1_json_native(
            calibration_source[:component_seeds])) ==
            ld1b1_canonical_sha256(ld1b1_json_native(
                generated_source[:truth][:component_seeds])) ||
            error("calibration row is not linked to simulation component seeds")
        ld1b1_string(calibration_source[:truth][
            :generating_mechanism]) ==
            ld1b1_string(generated_source[:truth][
                :generating_mechanism]) ||
            error("calibration row is not linked to simulation truth")
        simulation_provenance = calibration_source[:simulation_provenance]
        ld1b1_symbol(simulation_provenance[:status]) ===
            ld1b1_symbol(generated_source[:status]) ||
            error("calibration simulation status is not linked to its source")
        ld1b1_string(simulation_provenance[:score_signature]) ==
            ld1b1_string(generated_source[:score_signature]) ||
            error("calibration score signature is not linked to its source")
        ld1b1_sha256_record_value(
            simulation_provenance[:observed_score_signature],
            "calibration observed-score signature",
        ) == ld1b1_observed_score_signature_from_simulation_source(
            generated_source) || error(
            "calibration observed-score signature is not linked to its source")
        ld1b1_sha256_record_value(
            simulation_provenance[:testlet_design_signature],
            "calibration simulation design signature",
        ) == ld1b1_sha256_record_value(
            generated_source[:testlet_design_signature],
            "generated simulation design signature",
        ) || error(
            "calibration design signature is not linked to its source")
        ld1b1_canonical_sha256(ld1b1_json_native(
            simulation_provenance[:planning_shape])) ==
            ld1b1_canonical_sha256(ld1b1_json_native(
                calibration_source[:planning_shape])) || error(
            "calibration simulation shape is not linked to its plan")
        generated_summary = generated_source[:summary]
        ld1b1_int(simulation_provenance[:n_ratings]) ==
            ld1b1_int(generated_summary[:n_ratings]) &&
            ld1b1_bool(simulation_provenance[
                :requested_targets_eligible]) ==
                ld1b1_bool(generated_source[:design_support][
                    :requested_targets_eligible]) &&
            ld1b1_symbol(simulation_provenance[:future_fit_action]) ===
                ld1b1_symbol(generated_source[:design_support][
                    :future_fit_action]) || error(
            "calibration simulation provenance differs from its source")
        observed_shape = simulation_provenance[:observed_shape]
        ld1b1_require_exact_keys(observed_shape, (
            :n_persons, :n_testlets, :n_items, :n_raters, :n_categories,
        ), "calibration observed simulation shape")
        for (field, summary_field) in (
                (:n_persons, :n_persons),
                (:n_testlets, :n_testlets),
                (:n_items, :n_items),
                (:n_raters, :n_raters),
                (:n_categories, :realized_categories),
            )
            ld1b1_int(observed_shape[field]) ==
                ld1b1_int(generated_summary[summary_field]) || error(
                "calibration observed shape is not linked to simulation field $field")
        end
        if terminal_status === :completed
            local_payload =
                evidence_by_role[:local_dependence_summary].payload
            local_source =
                evidence_by_role[:local_dependence_summary].source_value
            for field in (:observed_score_signature_sha256,
                    :design_signature_sha256)
                ld1b1_string(calibration_payload[field]) ==
                    ld1b1_string(local_payload[field]) ||
                    error("calibration row is not linked to local field $field")
            end
            execution_seeds = calibration_source[:execution_seeds]
            for field in (:draw_selection_seed, :posterior_predictive_seed)
                calibration_field = field === :draw_selection_seed ?
                    :draw_selection : :posterior_predictive
                ld1b1_int(ld1b1_field(local_source, field)) ==
                    ld1b1_int(execution_seeds[calibration_field]) ||
                    error("calibration row is not linked to local seed $field")
            end
        else
            ld1b1_string(calibration_payload[:design_signature_sha256]) ==
                ld1b1_string(generated_payload[
                    :testlet_design_signature_sha256]) ||
                error("calibration row is not linked to the generated design")
        end
    end

    if terminal_status === :diagnostic_failed
        failure_component = ld1b1_symbol(evidence_by_role[
            :diagnostic_failure_record].payload[:failure_component])
        sampler_gate_passed = ld1b1_bool(evidence_by_role[
            :sampler_diagnostics].payload[:sampler_gate_passed])
        failure_component === :sampler_quality_gate && sampler_gate_passed &&
            error("sampler-quality failure contains a passing sampler gate")
        failure_component === :local_dependence_summary &&
            !sampler_gate_passed && error(
            "local-dependence-summary failure contains a failed sampler gate")
    end

    return true
end

function ld1b1_validate_calibration_semantics(
        calibration_semantic_context, semantic_inputs, job,
        terminal_status::Symbol)
    calibration_semantic_context === nothing && error(
        "calibration validation lacks the canonical semantic context")
    semantic_inputs === nothing && error(
        "calibration validation lacks loaded semantic source members")
    try
        if terminal_status === :completed
            link = LD1B1CalibrationSemantics.
                ld1b1_validate_completed_diagnostic_calibration_link(
                    semantic_inputs.calibration_member,
                    semantic_inputs.local_dependence_member,
                )
            link.valid || error(
                "completed diagnostic-to-calibration evidence link did not pass")
        end
        validation = LD1B1CalibrationSemantics.
            ld1b1_validate_calibration_member(
                calibration_semantic_context,
                job.row_index,
                semantic_inputs.calibration_member;
                expected_status = terminal_status,
                failure_record = semantic_inputs.failure_record,
            )
        validation.valid || error(
            "canonical calibration semantic replay did not pass")
    catch err
        error(
            "calibration semantic replay failed for $terminal_status: " *
            sprint(showerror, err),
        )
    end
    return true
end

function ld1b1_canonical_calibration_semantic_identity(
        protocol_path::AbstractString, expected_file_sha256::AbstractString)
    path = normpath(abspath(protocol_path))
    expected_sha256 = String(expected_file_sha256)
    ld1b1_file_sha256(path) == expected_sha256 || error(
        "calibration semantic context has the wrong protocol file identity")
    key = (path, expected_sha256)
    return lock(LD1B1_CALIBRATION_SEMANTIC_IDENTITY_CACHE_LOCK) do
        get!(LD1B1_CALIBRATION_SEMANTIC_IDENTITY_CACHE, key) do
            canonical = try
                LD1B1CalibrationSemantics.
                    ld1b1_load_calibration_semantic_context(path)
            catch err
                error(
                    "canonical calibration semantic context reconstruction failed: " *
                    sprint(showerror, err),
                )
            end
            return (;
                pilot_contract = canonical.pilot_contract,
                calibration_contract = canonical.calibration_contract,
                plan_rows = canonical.plan_rows,
                public_preflight = canonical.public_preflight,
                pilot_contract_sha256 = ld1b1_canonical_sha256(
                    ld1b1_json_native(canonical.pilot_contract)),
                calibration_contract_sha256 = ld1b1_canonical_sha256(
                    ld1b1_json_native(canonical.calibration_contract)),
                plan_rows_sha256 = ld1b1_canonical_sha256(
                    ld1b1_json_native(canonical.plan_rows)),
                public_preflight_sha256 = ld1b1_canonical_sha256(
                    ld1b1_json_native(canonical.public_preflight)),
                protocol_content_hash =
                    String(canonical.protocol_content_hash),
                public_contract_sha256 =
                    String(canonical.public_contract_sha256),
                artifact_contract_sha256 =
                    String(canonical.artifact_contract_sha256),
                public_job_rows_sha256 =
                    String(canonical.public_job_rows_sha256),
                artifact_job_rows_sha256 =
                    String(canonical.artifact_job_rows_sha256),
            )
        end
    end
end

function ld1b1_validate_calibration_semantic_context_identity(
        calibration_semantic_context, identity, job)
    calibration_semantic_context === nothing && error(
        "calibration semantic context is missing")
    for field in (
            :protocol_path,
            :protocol_content_hash,
            :pilot_contract,
            :calibration_contract,
            :plan_rows,
            :public_preflight,
            :public_contract_sha256,
            :artifact_contract_sha256,
            :public_job_rows_sha256,
            :artifact_job_rows_sha256,
        )
        hasproperty(calibration_semantic_context, field) || error(
            "calibration semantic context lacks identity field $field")
    end
    ld1b1_string(calibration_semantic_context.protocol_content_hash) ==
        String(identity.protocol_content_hash) || error(
        "calibration semantic context has the wrong protocol content hash")
    ld1b1_string(calibration_semantic_context.public_contract_sha256) ==
        String(identity.pilot_contract_sha256) || error(
        "calibration semantic context has the wrong pilot-contract hash")
    ld1b1_string(calibration_semantic_context.public_job_rows_sha256) ==
        String(identity.ordered_job_rows_sha256) || error(
        "calibration semantic context has the wrong ordered-job hash")
    canonical_identity = ld1b1_canonical_calibration_semantic_identity(
        calibration_semantic_context.protocol_path,
        String(identity.protocol_file_sha256),
    )
    ld1b1_string(calibration_semantic_context.protocol_content_hash) ==
        canonical_identity.protocol_content_hash || error(
        "calibration semantic context differs from the canonical protocol hash")
    ld1b1_string(calibration_semantic_context.public_contract_sha256) ==
        canonical_identity.public_contract_sha256 || error(
        "calibration semantic context differs from the canonical public contract hash")
    ld1b1_string(calibration_semantic_context.artifact_contract_sha256) ==
        canonical_identity.artifact_contract_sha256 || error(
        "calibration semantic context differs from the canonical artifact contract hash")
    ld1b1_string(calibration_semantic_context.public_job_rows_sha256) ==
        canonical_identity.public_job_rows_sha256 || error(
        "calibration semantic context differs from the canonical public job-row hash")
    ld1b1_string(calibration_semantic_context.artifact_job_rows_sha256) ==
        canonical_identity.artifact_job_rows_sha256 || error(
        "calibration semantic context differs from the canonical artifact job-row hash")
    isequal(calibration_semantic_context.pilot_contract,
        canonical_identity.pilot_contract) || error(
        "calibration semantic context pilot contract is not canonical")
    isequal(calibration_semantic_context.calibration_contract,
        canonical_identity.calibration_contract) || error(
        "calibration semantic context has the wrong calibration contract")
    isequal(calibration_semantic_context.plan_rows,
        canonical_identity.plan_rows) || error(
        "calibration semantic context plan rows are not canonical")
    isequal(calibration_semantic_context.public_preflight,
        canonical_identity.public_preflight) || error(
        "calibration semantic context preflight is not canonical")
    canonical_identity.pilot_contract_sha256 ==
        String(identity.pilot_contract_sha256) || error(
        "canonical calibration semantic context has the wrong pilot-contract hash")
    canonical_identity.calibration_contract_sha256 ==
        String(job.quality_contract.calibration_contract_sha256) || error(
        "canonical calibration semantic context has the wrong calibration contract")

    1 <= job.row_index <= length(calibration_semantic_context.plan_rows) ||
        error("calibration semantic context lacks the requested plan row")
    length(calibration_semantic_context.plan_rows) == LD1B1_EXPECTED_JOBS ||
        error("calibration semantic context has the wrong plan-row count")
    length(calibration_semantic_context.public_preflight.job_rows) ==
        LD1B1_EXPECTED_JOBS || error(
        "calibration semantic context has the wrong public job-row count")
    plan = calibration_semantic_context.plan_rows[job.row_index]
    compact = calibration_semantic_context.public_preflight.job_rows[
        job.row_index]
    for field in (
            :row_index,
            :scenario_index,
            :scenario_id,
            :matched_set_id,
            :replication,
            :phase,
            :seed,
        )
        expected = getproperty(job, field)
        plan_value = getproperty(plan, field)
        compact_value = getproperty(compact, field)
        isequal(plan_value, expected) && isequal(compact_value, expected) ||
            error("calibration semantic context differs from job field $field")
    end
    plan.expected_requested_targets_eligible ===
        job.expected_structural_eligibility &&
        compact.expected_structural_eligibility ===
            job.expected_structural_eligibility &&
        compact.expected_action === job.expected_action || error(
        "calibration semantic context differs from the job routing")
    for field in (
            :fit_seed,
            :draw_selection_seed,
            :posterior_predictive_seed,
        )
        getproperty(compact, field) == getproperty(job, field) || error(
            "calibration semantic context differs from execution seed $field")
    end
    for field in (:n_ratings, :n_probability_cells, :n_truth_cells)
        getproperty(compact.resources, field) ==
            getproperty(job.resources, field) || error(
            "calibration semantic context differs from job resource $field")
    end
    return true
end

function ld1b1_validate_evidence_file(path::AbstractString, identity, job,
        attempt_number::Int, terminal_status::Symbol, role::Symbol,
        attempt_dir::AbstractString, expected_bytes::Int,
        expected_sha256::AbstractString;
        execution_context = ld1b1_execution_context())
    snapshot = ld1b1_regular_file_snapshot(
        path, attempt_dir, "job-evidence envelope")
    snapshot.nbytes == expected_bytes ||
        error("file-manifest byte count mismatch: $(relpath(path, attempt_dir))")
    snapshot.sha256 == expected_sha256 ||
        error("file-manifest SHA-256 mismatch: $(relpath(path, attempt_dir))")
    evidence = JSON3.read(String(snapshot.bytes))
    ld1b1_require_only_keys(evidence, (
        :schema,
        :family,
        :scope,
        :execution_context,
        :plan_identity,
        :execution_source_identity,
        :job,
        :attempt,
        :terminal_status,
        :evidence_role,
        :payload_schema,
        :source_member,
        :dependencies,
        :payload,
        :content_hash,
    ), "job-evidence envelope")
    ld1b1_string(evidence[:schema]) == LD1B1_EVIDENCE_SCHEMA ||
        error("unexpected job-evidence schema")
    ld1b1_string(evidence[:family]) == "mfrm" ||
        error("unexpected job-evidence family")
    expected_context = ld1b1_validate_execution_context(execution_context)
    observed_context = ld1b1_validate_execution_context(
        evidence[:execution_context];
        expected_scope = expected_context.execution_scope,
    )
    observed_context == expected_context || error(
        "job-evidence execution context mismatch")
    expected_evidence_scope = expected_context.execution_scope === :pilot ?
        "ld1b1_pilot_job_evidence" :
        "ld1b1_bounded_smoke_job_evidence"
    ld1b1_string(evidence[:scope]) == expected_evidence_scope ||
        error("unexpected job-evidence scope")
    content_hash = ld1b1_verify_content_hash(
        evidence; label = "LD1b1 job evidence")
    plan = evidence[:plan_identity]
    ld1b1_require_only_keys(plan,
        (:plan_id, :protocol_plan_id, :protocol_content_hash),
        "job-evidence plan identity")
    for field in (:plan_id, :protocol_plan_id, :protocol_content_hash)
        ld1b1_string(plan[field]) == String(getproperty(identity, field)) ||
            error("job-evidence plan identity mismatch: $field")
    end
    execution_source_identity = evidence[:execution_source_identity]
    ld1b1_require_only_keys(execution_source_identity, (
        :batch_runner_source_sha256,
        :local_json_source_sha256,
        :job_runner_source_sha256,
        :attempt_archive_source_sha256,
        :local_dependence_pilot_recovery_source_sha256,
        :local_dependence_pilot_calibration_semantics_source_sha256,
    ), "job-evidence execution source identity")
    ld1b1_canonical_sha256(ld1b1_json_native(execution_source_identity)) ==
        ld1b1_canonical_sha256(identity.execution_source_identity) ||
        error("job-evidence execution source identity mismatch")
    observed_job = evidence[:job]
    ld1b1_require_only_keys(observed_job, (
        :job_id,
        :row_index,
        :scenario_id,
        :replication,
        :seed,
        :fit_seed,
        :draw_selection_seed,
        :posterior_predictive_seed,
    ), "job-evidence job identity")
    for field in (
            :job_id,
            :row_index,
            :scenario_id,
            :replication,
            :seed,
            :fit_seed,
            :draw_selection_seed,
            :posterior_predictive_seed,
        )
        expected = getproperty(job, field)
        observed = observed_job[field]
        matches = expected isa Symbol ?
            ld1b1_symbol(observed) === expected :
            expected isa AbstractString ?
                ld1b1_string(observed) == expected :
                ld1b1_int(observed) == expected
        matches || error("job-evidence identity mismatch: $field")
    end
    observed_attempt = evidence[:attempt]
    ld1b1_require_only_keys(observed_attempt,
        (:number, :role, :counts_toward_primary),
        "job-evidence attempt identity")
    ld1b1_int(observed_attempt[:number]) == attempt_number ||
        error("job-evidence attempt number mismatch")
    expected_attempt = ld1b1_attempt_identity(
        attempt_number, expected_context)
    ld1b1_symbol(observed_attempt[:role]) === expected_attempt.role ||
        error("job-evidence attempt role mismatch")
    ld1b1_bool(observed_attempt[:counts_toward_primary]) ===
        expected_attempt.counts_toward_primary || error(
        "job-evidence primary-denominator eligibility mismatch")
    ld1b1_symbol(evidence[:terminal_status]) === terminal_status ||
        error("job-evidence terminal status mismatch")
    ld1b1_symbol(evidence[:evidence_role]) === role ||
        error("job-evidence role mismatch")
    ld1b1_symbol(evidence[:payload_schema]) ===
        ld1b1_evidence_payload_schema(role) ||
        error("job-evidence payload schema mismatch")
    ld1b1_validate_evidence_payload(
        evidence[:payload], role, job, terminal_status)
    source_member = evidence[:source_member]
    ld1b1_require_only_keys(source_member,
        (:role, :path, :media_type, :bytes, :sha256),
        "job-evidence source member")
    ld1b1_symbol(source_member[:role]) === ld1b1_evidence_member_role(role) ||
        error("job-evidence source member has the wrong role")
    ld1b1_symbol(source_member[:media_type]) ===
        ld1b1_evidence_member_media_type(role) ||
        error("job-evidence source member has the wrong media type")
    ld1b1_int(source_member[:bytes]) > 0 ||
        error("job-evidence source member is empty")
    member_sha256 = ld1b1_require_sha256(source_member[:sha256],
        "job-evidence source-member digest")
    ld1b1_payload_member_sha256(evidence[:payload], role) == member_sha256 ||
        error("evidence payload is not bound to its source member")
    dependencies = Tuple(evidence[:dependencies])
    expected_dependency_roles =
        ld1b1_expected_evidence_dependencies(terminal_status, role)
    length(dependencies) == length(expected_dependency_roles) ||
        error("job-evidence dependency count differs from the contract")
    for (dependency, expected_role) in
            zip(dependencies, expected_dependency_roles)
        ld1b1_require_only_keys(dependency, (:role, :content_hash),
            "job-evidence dependency")
        ld1b1_symbol(dependency[:role]) === expected_role ||
            error("job-evidence dependencies are not in canonical order")
        ld1b1_require_sha256(dependency[:content_hash],
            "job-evidence dependency content hash")
    end
    return (;
        content_hash,
        snapshot,
        source_member,
        dependencies,
        payload = evidence[:payload],
    )
end

function ld1b1_validate_manifest_files(result, result_path::AbstractString,
        identity, job, attempt_number::Int, terminal_status::Symbol,
        result_snapshot; allow_interruption_review::Bool = false,
        require_canonical_controller_receipts::Bool = false,
        execution_context = ld1b1_execution_context())
    rows = result[:file_manifest]
    isempty(rows) && error("job-result file manifest must not be empty")
    attempt_dir = dirname(result_path)
    seen = Set{String}()
    roles = Set{Symbol}()
    evidence_rows = NamedTuple[]
    evidence_by_role = Dict{Symbol,Any}()
    snapshots = Dict{String,Any}()
    for row in rows
        ld1b1_require_only_keys(row, (:role, :path, :bytes, :sha256),
            "job-result file-manifest row")
        role = ld1b1_symbol(row[:role])
        role in roles && error("file-manifest roles must be unique")
        push!(roles, role)
        relative = ld1b1_string(row[:path])
        isabspath(relative) && error("file-manifest path must be relative")
        normalized = normpath(relative)
        (normalized == "." || startswith(normalized, "..")) &&
            error("file-manifest path escapes its attempt directory")
        portable = ld1b1_portable_inventory_relative_path(normalized)
        portable == "job_result.json" &&
            error("job-result file must not appear in its own manifest")
        portable in seen && error("file-manifest paths must be unique")
        push!(seen, portable)
        absolute = normpath(joinpath(attempt_dir, normalized))
        ld1b1_path_within(absolute, attempt_dir) ||
            error("file-manifest path escapes its attempt directory")
        isfile(absolute) || error("file-manifest member is missing: $relative")
        islink(absolute) &&
            error("file-manifest member must not be a symbolic link: $relative")
        ld1b1_require_realpath_containment(absolute, attempt_dir)
        expected_bytes = ld1b1_int(row[:bytes])
        expected_sha256 = ld1b1_require_sha256(row[:sha256],
            "file-manifest SHA-256")
        validated_evidence = ld1b1_validate_evidence_file(
            absolute,
            identity,
            job,
            attempt_number,
            terminal_status,
            role,
            attempt_dir,
            expected_bytes,
            expected_sha256,
            ; execution_context,
        )
        evidence_by_role[role] = validated_evidence
        snapshots[portable] = validated_evidence.snapshot
        push!(evidence_rows, (;
            role,
            path = portable,
            bytes = expected_bytes,
            sha256 = expected_sha256,
            content_hash = validated_evidence.content_hash,
        ))
    end
    required_roles = Set(ld1b1_required_evidence_roles(terminal_status))
    roles == required_roles || error(
        "job result evidence roles do not exactly match terminal status $terminal_status")

    member_roles = Set{Symbol}()
    for role in ld1b1_required_evidence_roles(terminal_status)
        validated = evidence_by_role[role]
        expected_dependencies =
            ld1b1_expected_evidence_dependencies(terminal_status, role)
        for (dependency, dependency_role) in
                zip(validated.dependencies, expected_dependencies)
            haskey(evidence_by_role, dependency_role) ||
                error("job-evidence dependency is absent from the result")
            ld1b1_string(dependency[:content_hash]) ==
                evidence_by_role[dependency_role].content_hash ||
                error("job-evidence dependency content hash mismatch")
        end

        member = validated.source_member
        member_role = ld1b1_symbol(member[:role])
        member_role in member_roles &&
            error("source-member roles must be unique within an attempt")
        push!(member_roles, member_role)
        relative = ld1b1_string(member[:path])
        isabspath(relative) && error("source-member path must be relative")
        normalized = normpath(relative)
        (normalized == "." || startswith(normalized, "..")) &&
            error("source-member path escapes its attempt directory")
        portable = ld1b1_portable_inventory_relative_path(normalized)
        portable == "job_result.json" &&
            error("job-result file cannot be an evidence source member")
        portable in seen &&
            error("source-member and evidence paths must be unique")
        push!(seen, portable)
        absolute = normpath(joinpath(attempt_dir, normalized))
        ld1b1_path_within(absolute, attempt_dir) ||
            error("source-member path escapes its attempt directory")
        member_snapshot = ld1b1_regular_file_snapshot(
            absolute, attempt_dir, "job-evidence source member")
        member_snapshot.nbytes == ld1b1_int(member[:bytes]) ||
            error("source-member byte count mismatch: $relative")
        member_snapshot.sha256 == ld1b1_string(member[:sha256]) ||
            error("source-member SHA-256 mismatch: $relative")
        snapshots[portable] = member_snapshot
        source_value = ld1b1_validate_source_member_json(
            member_snapshot.bytes, role, job, validated.payload,
            terminal_status)
        evidence_by_role[role] = merge(validated, (;
            source_value,
            source_snapshot = member_snapshot,
        ))
        index = findfirst(row -> row.role === role, evidence_rows)
        evidence_rows[index] = merge(evidence_rows[index], (;
            source_member_role = member_role,
            source_member_path = portable,
            source_member_bytes = member_snapshot.nbytes,
            source_member_sha256 = member_snapshot.sha256,
            dependency_chain_sha256 = ld1b1_canonical_sha256(
                ld1b1_json_native(validated.dependencies)),
        ))
    end

    ld1b1_validate_cross_evidence_lineage(
        evidence_by_role, terminal_status, job)

    failure_role = terminal_status === :generation_failed ?
        :generation_failure_record : terminal_status === :fit_failed ?
        :fit_failure_record : terminal_status === :diagnostic_failed ?
        :diagnostic_failure_record : nothing
    calibration_semantic_inputs = (;
        failure_record = failure_role === nothing ? nothing :
            evidence_by_role[failure_role].source_value,
        local_dependence_member = terminal_status === :completed ?
            evidence_by_role[:local_dependence_summary].source_value : nothing,
        calibration_member = evidence_by_role[:calibration_row].source_value,
    )

    recovery_receipt_filenames = (
        LD1B1Recovery.LD1B_ATTEMPT_OWNER_FILENAME,
        LD1B1Recovery.LD1B_CHILD_LAUNCH_FILENAME,
        LD1B1Recovery.LD1B_CHILD_EXIT_FILENAME,
    )
    present_recovery_receipts = Tuple(filename for filename in
        recovery_receipt_filenames if ispath(joinpath(attempt_dir, filename)) ||
            islink(joinpath(attempt_dir, filename)))
    execution_root = ld1b1_result_execution_root(result_path)
    reservation_path = ld1b1_attempt_reservation_path(
        execution_root, job.job_id, attempt_number)
    reservation_present = ispath(reservation_path) || islink(reservation_path)
    controller_receipts = nothing
    if require_canonical_controller_receipts
        Set(present_recovery_receipts) == Set(recovery_receipt_filenames) ||
            error("canonical terminal admission requires owner, launch, and exit receipts")
        controller_receipts =
            ld1b1_validate_canonical_terminal_admission_receipts(
            attempt_dir, identity, job, attempt_number;
            execution_context)
    elseif reservation_present || !isempty(present_recovery_receipts)
        required_receipts = Set((
            LD1B1Recovery.LD1B_ATTEMPT_OWNER_FILENAME,
            LD1B1Recovery.LD1B_CHILD_LAUNCH_FILENAME,
        ))
        issubset(required_receipts, Set(present_recovery_receipts)) || error(
            "attempt recovery receipts are incomplete")
        identity_args = ld1b1_controller_receipt_identity(
            identity, job, attempt_number; execution_context)
        lineage = reservation_present ? ld1b1_reservation_lineage(
            execution_root, identity, job, attempt_number;
            execution_context) : nothing
        launch = lineage === nothing ?
            LD1B1Recovery.ld1b_validate_child_launch_file(
                attempt_dir; identity_args...) :
            LD1B1Recovery.ld1b_validate_child_launch_file(
                attempt_dir;
                identity_args...,
                reservation_path = lineage.reservation_path,
                execution_root,
                expected_reservation_id =
                    lineage.reservation.reservation_id,
            )
        launch.valid || error("child-launch receipt did not validate")
        if LD1B1Recovery.LD1B_CHILD_EXIT_FILENAME in
                present_recovery_receipts
            exit = lineage === nothing ?
                LD1B1Recovery.ld1b_validate_child_exit_file(
                    attempt_dir; identity_args...) :
                LD1B1Recovery.ld1b_validate_child_exit_file(
                    attempt_dir;
                    identity_args...,
                    reservation_path = lineage.reservation_path,
                    execution_root,
                    expected_reservation_id =
                        lineage.reservation.reservation_id,
                )
            exit.valid || error("child-exit receipt did not validate")
        end
    end
    for filename in present_recovery_receipts
        filename in seen && error(
            "recovery receipt cannot also be a result-manifest member")
        snapshots[filename] = ld1b1_regular_file_snapshot(
            joinpath(attempt_dir, filename),
            attempt_dir,
            "attempt recovery receipt",
        )
    end
    allowed_interruption_review_files = String[]
    interruption_review_path = joinpath(
        attempt_dir, LD1B1Recovery.LD1B_INTERRUPTION_REVIEW_FILENAME)
    if allow_interruption_review &&
            (ispath(interruption_review_path) ||
                islink(interruption_review_path))
        snapshots[LD1B1Recovery.LD1B_INTERRUPTION_REVIEW_FILENAME] =
            ld1b1_regular_file_snapshot(
                interruption_review_path,
                attempt_dir,
                "interruption review during result semantic validation",
            )
        push!(allowed_interruption_review_files,
            LD1B1Recovery.LD1B_INTERRUPTION_REVIEW_FILENAME)
    end

    inventory = ld1b1_attempt_inventory_rows(attempt_dir)
    any(row -> row.kind === :symbolic_link, inventory) &&
        error("attempt tree must not contain symbolic links")
    any(row -> row.kind === :file && row.link_count != 1, inventory) &&
        error("attempt tree must not contain hard-linked files")
    snapshots["job_result.json"] = result_snapshot
    actual_files = Set(row.path for row in inventory if row.kind === :file)
    expected_files = union(
        Set(seen),
        Set(["job_result.json"]),
        Set(present_recovery_receipts),
        Set(allowed_interruption_review_files),
    )
    actual_files == expected_files ||
        error("attempt tree contains unmanifested or missing files")
    actual_directories = Set(
        row.path for row in inventory if row.kind === :directory)
    expected_directories = ld1b1_expected_manifest_directories(expected_files)
    actual_directories == expected_directories ||
        error("attempt tree contains unmanifested or missing directories")
    inventory_by_path = Dict(row.path => row for row in inventory
        if row.kind === :file)
    for (relative, snapshot) in snapshots
        row = inventory_by_path[relative]
        row.bytes == snapshot.nbytes && row.sha256 == snapshot.sha256 &&
            row.link_count == 1 || error(
            "attempt inventory changed during validation: $relative")
    end

    sort!(evidence_rows; by = row -> string(row.role))
    return (;
        roles,
        evidence_rows = Tuple(evidence_rows),
        evidence_manifest_sha256 = ld1b1_canonical_sha256(evidence_rows),
        attempt_inventory_sha256 = ld1b1_canonical_sha256(inventory),
        calibration_semantic_inputs,
        canonical_controller_receipts_verified =
            controller_receipts !== nothing,
        child_exit_code = controller_receipts === nothing ? missing :
            controller_receipts.exit_code,
    )
end

function ld1b1_validate_result(path::AbstractString, identity, job,
        expected_attempt::Int;
        calibration_semantic_context = nothing,
        allow_interruption_review::Bool = false,
        require_canonical_controller_receipts::Bool = false,
        execution_context = ld1b1_execution_context())
    calibration_semantic_context === nothing && error(
        "terminal-result validation requires the canonical calibration semantic context")
    ld1b1_validate_calibration_semantic_context_identity(
        calibration_semantic_context, identity, job)
    isfile(path) || error("job result is missing")
    islink(path) && error("job result must not be a symbolic link")
    result_execution_root = ld1b1_result_execution_root(path)
    result_snapshot = ld1b1_regular_file_snapshot(
        path, result_execution_root, "job-result envelope")
    result = JSON3.read(String(result_snapshot.bytes))
    ld1b1_require_only_keys(result, (
        :schema,
        :family,
        :scope,
        :execution_context,
        :plan_identity,
        :execution_source_identity,
        :job,
        :attempt,
        :terminal_status,
        :terminal_outcome_code,
        :lineage_valid,
        :file_manifest,
        :primary_outcome_replaced,
        :pilot_execution_completed,
        :evaluation_profile_frozen,
        :calibration_evidence_available,
        :diagnostic_decision_labels_available,
        :mechanism_interpretation_eligible,
        :content_hash,
    ), "job-result envelope")
    ld1b1_string(result[:schema]) == LD1B1_JOB_RESULT_SCHEMA ||
        error("unexpected job-result schema")
    ld1b1_string(result[:family]) == "mfrm" ||
        error("unexpected job-result family")
    expected_context = ld1b1_validate_execution_context(execution_context)
    observed_context = ld1b1_validate_execution_context(
        result[:execution_context];
        expected_scope = expected_context.execution_scope,
    )
    observed_context == expected_context || error(
        "job-result execution context mismatch")
    expected_result_scope = expected_context.execution_scope === :pilot ?
        "ld1b1_pilot_job_result" :
        "ld1b1_bounded_smoke_job_result"
    ld1b1_string(result[:scope]) == expected_result_scope ||
        error("unexpected job-result scope")
    ld1b1_verify_content_hash(result; label = "LD1b1 job result")
    plan = result[:plan_identity]
    ld1b1_require_only_keys(plan, (
        :plan_id,
        :protocol_plan_id,
        :protocol_file_sha256,
        :protocol_content_hash,
        :ordered_job_rows_sha256,
        :pilot_contract_sha256,
    ), "job-result plan identity")
    for field in (
            :plan_id,
            :protocol_plan_id,
            :protocol_file_sha256,
            :protocol_content_hash,
            :ordered_job_rows_sha256,
            :pilot_contract_sha256,
        )
        ld1b1_string(plan[field]) == String(getproperty(identity, field)) ||
            error("job-result plan identity mismatch: $field")
    end
    result_execution_source_identity = result[:execution_source_identity]
    ld1b1_require_only_keys(result_execution_source_identity, (
        :batch_runner_source_sha256,
        :local_json_source_sha256,
        :job_runner_source_sha256,
        :attempt_archive_source_sha256,
        :local_dependence_pilot_recovery_source_sha256,
        :local_dependence_pilot_calibration_semantics_source_sha256,
    ), "job-result execution source identity")
    ld1b1_canonical_sha256(ld1b1_json_native(
        result_execution_source_identity)) ==
        ld1b1_canonical_sha256(identity.execution_source_identity) ||
        error("job-result execution source identity mismatch")
    runner_source_sha256 = ld1b1_require_sha256(
        result_execution_source_identity[:job_runner_source_sha256],
        "job-result runner source identity",
    )
    runner_source_sha256 == ld1b1_expected_job_runner_sha256(identity) ||
        error("job-result runner source identity differs from the execution plan")
    observed_job = result[:job]
    ld1b1_require_only_keys(observed_job, (
        :job_id,
        :row_index,
        :scenario_index,
        :scenario_id,
        :replication,
        :expected_action,
        :seed,
        :fit_seed,
        :draw_selection_seed,
        :posterior_predictive_seed,
    ), "job-result job identity")
    for field in (
            :job_id,
            :row_index,
            :scenario_index,
            :scenario_id,
            :replication,
            :expected_action,
            :seed,
            :fit_seed,
            :draw_selection_seed,
            :posterior_predictive_seed,
        )
        expected = getproperty(job, field)
        observed = observed_job[field]
        matches = expected isa Symbol ?
            ld1b1_symbol(observed) === expected :
            expected isa AbstractString ?
                ld1b1_string(observed) == expected :
                ld1b1_int(observed) == expected
        matches || error("job-result identity mismatch: $field")
    end
    attempt = result[:attempt]
    ld1b1_require_only_keys(attempt, (
        :number,
        :role,
        :counts_toward_primary,
        :retry_of_attempt,
        :retry_reason,
        :primary_result_sha256,
        :same_seed_contract,
    ), "job-result attempt identity")
    number = ld1b1_int(attempt[:number])
    number == expected_attempt || error("job-result attempt number mismatch")
    expected_attempt_identity = ld1b1_attempt_identity(
        number, expected_context)
    expected_role = expected_attempt_identity.role
    ld1b1_symbol(attempt[:role]) === expected_role ||
        error("job-result attempt role mismatch")
    ld1b1_bool(attempt[:counts_toward_primary]) ===
        expected_attempt_identity.counts_toward_primary ||
        error("job-result primary-denominator role mismatch")
    ld1b1_bool(attempt[:same_seed_contract]) ||
        error("job-result retry changed the frozen seed contract")
    !ld1b1_bool(result[:primary_outcome_replaced]) ||
        error("job result claims that remediation replaced the primary outcome")
    for field in (
            :pilot_execution_completed,
            :evaluation_profile_frozen,
            :calibration_evidence_available,
            :diagnostic_decision_labels_available,
            :mechanism_interpretation_eligible,
        )
        !ld1b1_bool(result[field]) ||
            error("job result exceeds its evidence boundary: $field")
    end
    ld1b1_bool(result[:lineage_valid]) || error("job-result lineage is invalid")
    status = ld1b1_symbol(result[:terminal_status])
    status in LD1B1_TERMINAL_STATUSES ||
        error("job result has a nonterminal status")
    outcome = ld1b1_symbol(result[:terminal_outcome_code])
    outcome === ld1b1_terminal_outcome_code(status) ||
        error("job-result terminal outcome code does not match its status")
    if job.expected_action === :pre_fit_reject
        status in (:pre_fit_rejected, :generation_failed) ||
            error("pre-fit rejection job has the wrong terminal status")
    elseif status === :pre_fit_rejected
        error("eligible fit job was recorded as a pre-fit rejection")
    end
    if number == 1
        ismissing(ld1b1_get(attempt, :retry_of_attempt, missing)) ||
            error("primary job result identifies a retry target")
        ismissing(ld1b1_get(attempt, :retry_reason, missing)) ||
            error("primary job result contains a retry reason")
        ismissing(ld1b1_get(attempt, :primary_result_sha256, missing)) ||
            error("primary job result contains a primary-result digest")
    else
        ld1b1_int(attempt[:retry_of_attempt]) == 1 ||
            error("remediation must point to primary attempt 1")
        reason = strip(ld1b1_string(attempt[:retry_reason]))
        isempty(reason) && error("remediation reason is empty")
        # The canonical path is derived from the observed result location to
        # avoid trusting any mutable pointer or selected-attempt record.
        primary_path = joinpath(dirname(dirname(path)), "attempt_001", "job_result.json")
        isfile(primary_path) || error("remediation exists without a primary result")
        ld1b1_string(attempt[:primary_result_sha256]) ==
            ld1b1_file_sha256(primary_path) ||
            error("remediation primary-result digest mismatch")
    end
    manifest = ld1b1_validate_manifest_files(
        result,
        path,
        identity,
        job,
        number,
        status,
        result_snapshot,
        ; allow_interruption_review,
        require_canonical_controller_receipts,
        execution_context = expected_context,
    )
    ld1b1_validate_calibration_semantics(
        calibration_semantic_context,
        manifest.calibration_semantic_inputs,
        job,
        status,
    )
    return (;
        valid = true,
        terminal_status = status,
        terminal_outcome_code = outcome,
        result_sha256 = result_snapshot.sha256,
        content_hash = ld1b1_string(result[:content_hash][:value]),
        runner_source_sha256,
        evidence_roles = Tuple(sort!(collect(manifest.roles); by = string)),
        evidence_manifest_sha256 = manifest.evidence_manifest_sha256,
        attempt_inventory_sha256 = manifest.attempt_inventory_sha256,
        calibration_semantic_replay_verified = true,
        canonical_controller_receipts_verified =
            manifest.canonical_controller_receipts_verified,
        child_exit_code = manifest.child_exit_code,
    )
end

function ld1b1_validate_completed_attempt(path::AbstractString,
        identity, job, expected_attempt::Int;
        calibration_semantic_context = nothing,
        execution_context = ld1b1_execution_context())
    calibration_semantic_context === nothing && error(
        "completed-attempt validation requires the canonical calibration semantic context")
    execution_root = ld1b1_result_execution_root(path)
    expected_path = ld1b1_result_path(
        execution_root, job.job_id, expected_attempt)
    normpath(path) == normpath(expected_path) ||
        error("completed-attempt result path does not match its identity")
    semantic = ld1b1_validate_result(
        path,
        identity,
        job,
        expected_attempt;
        calibration_semantic_context,
        require_canonical_controller_receipts = true,
        execution_context,
    )
    context = ld1b1_validate_execution_context(execution_context)
    attempt_role = ld1b1_attempt_identity(
        expected_attempt, context).role
    seal = LD1B1AttemptArchive.ld1b_validate_completed_attempt_seal(
        dirname(path);
        plan_identity = ld1b1_result_plan_identity(identity),
        execution_source_identity = identity.execution_source_identity,
        job_identity = ld1b1_result_job_identity(job),
        attempt_number = expected_attempt,
        attempt_role,
        execution_context = context,
        terminal_status = semantic.terminal_status,
        terminal_outcome_code = semantic.terminal_outcome_code,
    )
    seal.result_file_sha256 == semantic.result_sha256 ||
        error("completed-attempt seal has the wrong result SHA-256")
    seal.result_content_hash == semantic.content_hash ||
        error("completed-attempt seal has the wrong result content hash")
    seal.evidence_manifest_sha256 == semantic.evidence_manifest_sha256 ||
        error("completed-attempt seal has the wrong evidence-manifest SHA-256")
    seal.attempt_inventory_sha256 ==
        semantic.attempt_inventory_sha256 || error(
        "completed-attempt helper inventory differs from semantic validation")
    return merge(semantic, (;
        archive_state = :verified_terminal,
        seal_file_sha256 = seal.seal_file_sha256,
        seal_content_hash = seal.seal_content_hash,
        helper_attempt_inventory_sha256 =
            seal.attempt_inventory_sha256,
    ))
end

function ld1b1_publish_completed_attempt_seal(path::AbstractString,
        identity, job, expected_attempt::Int;
        staging_dir::AbstractString = ld1b1_seal_staging_dir(
            ld1b1_result_execution_root(path)),
        calibration_semantic_context = nothing,
        execution_context = ld1b1_execution_context())
    calibration_semantic_context === nothing && error(
        "completed-attempt sealing requires the canonical calibration semantic context")
    execution_root = ld1b1_result_execution_root(path)
    expected_path = ld1b1_result_path(
        execution_root, job.job_id, expected_attempt)
    normpath(path) == normpath(expected_path) ||
        error("completed-attempt result path does not match its identity")
    semantic = ld1b1_validate_result(
        path,
        identity,
        job,
        expected_attempt;
        calibration_semantic_context,
        require_canonical_controller_receipts = true,
        execution_context,
    )
    context = ld1b1_validate_execution_context(execution_context)
    attempt_role = ld1b1_attempt_identity(
        expected_attempt, context).role
    publication =
        LD1B1AttemptArchive.ld1b_publish_completed_attempt_seal(
            dirname(path);
            plan_identity = ld1b1_result_plan_identity(identity),
            execution_source_identity = identity.execution_source_identity,
            job_identity = ld1b1_result_job_identity(job),
            attempt_number = expected_attempt,
            attempt_role,
            execution_context = context,
            terminal_status = semantic.terminal_status,
            terminal_outcome_code = semantic.terminal_outcome_code,
            evidence_manifest_sha256 =
                semantic.evidence_manifest_sha256,
            staging_dir,
            boundary = execution_root,
        )
    validation = ld1b1_validate_completed_attempt(
        path,
        identity,
        job,
        expected_attempt;
        calibration_semantic_context,
        execution_context = context,
    )
    return (;
        artifact = publication.artifact,
        publication = publication.publication,
        validation,
    )
end

function ld1b1_validate_retired_attempt(execution_root::AbstractString,
        identity, job, expected_attempt::Int)
    attempt_dir = ld1b1_attempt_dir(
        execution_root, job.job_id, expected_attempt)
    attempt_role = expected_attempt == 1 ? :primary : :remediation
    launched_review_path = ld1b1_interruption_review_path(
        execution_root, job.job_id, expected_attempt)
    precommit_review_path = ld1b1_precommit_interruption_review_path(
        execution_root, job.job_id, expected_attempt)
    launched_review_present = ispath(launched_review_path) ||
        islink(launched_review_path)
    precommit_review_present = ispath(precommit_review_path) ||
        islink(precommit_review_path)
    xor(launched_review_present, precommit_review_present) || error(
        "retired attempt requires exactly one interruption-review kind")
    review = if precommit_review_present
        validated = ld1b1_validate_precommit_interruption_review_record(
            attempt_dir, execution_root, identity, job, expected_attempt)
        (;
            retirement_reason_code = validated.reason_code,
            review_file_sha256 = validated.file_sha256,
            review_content_hash = validated.content_hash,
            review_kind = :precommit_interruption,
            scientific_contribution = validated.scientific_contribution,
        )
    else
        recovery = ld1b1_recovery_reservation_context(
            attempt_dir, identity, job, expected_attempt)
        validated = LD1B1Recovery.ld1b_validate_interruption_review_file(
            attempt_dir;
            plan_identity = ld1b1_result_plan_identity(identity),
            execution_source_identity = identity.execution_source_identity,
            job_identity = ld1b1_result_job_identity(job),
            attempt_number = expected_attempt,
            attempt_role,
            recovery.file_kwargs...,
        )
        (;
            retirement_reason_code = validated.retirement_reason_code,
            review_file_sha256 = validated.review_file_sha256,
            review_content_hash = validated.review_content_hash,
            review_kind = :launched_interruption,
            scientific_contribution = 0,
        )
    end
    review.scientific_contribution == 0 || error(
        "retired interruption cannot contribute a scientific job")
    retirement = LD1B1AttemptArchive.
        ld1b_validate_attempt_retirement_marker(
            attempt_dir;
            plan_identity = ld1b1_result_plan_identity(identity),
            execution_source_identity = identity.execution_source_identity,
            job_identity = ld1b1_result_job_identity(job),
            attempt_number = expected_attempt,
            attempt_role,
            expected_reason_code = review.retirement_reason_code,
            expected_review_record_sha256 = review.review_file_sha256,
        )
    retirement.retirement_counts_toward_primary && error(
        "retired interruption must not count toward the scientific denominator")
    return (;
        archive_state = :retired_interrupted,
        terminal_status = missing,
        terminal_outcome_code =
            retirement.terminal_outcome_code,
        retirement_reason_code = retirement.retirement_reason_code,
        review_file_sha256 = review.review_file_sha256,
        review_content_hash = review.review_content_hash,
        review_kind = review.review_kind,
        retirement_file_sha256 = retirement.retirement_file_sha256,
        retirement_content_hash = retirement.retirement_content_hash,
        attempt_inventory_sha256 =
            retirement.attempt_inventory_sha256,
        original_slot_counts_toward_primary =
            retirement.original_slot_counts_toward_primary,
        retirement_counts_toward_primary =
            retirement.retirement_counts_toward_primary,
    )
end

function ld1b1_interrupted_attempt_observation(
        execution_root::AbstractString, identity, job, attempt::Int;
        calibration_semantic_context = nothing)
    calibration_semantic_context === nothing && error(
        "interrupted-attempt observation requires the canonical calibration semantic context")
    attempt_dir = ld1b1_attempt_dir(execution_root, job.job_id, attempt)
    isdir(attempt_dir) && !islink(attempt_dir) || error(
        "interrupted-attempt directory is missing or unsafe")
    seal_path = ld1b1_seal_path(execution_root, job.job_id, attempt)
    retirement_path = ld1b1_retirement_path(
        execution_root, job.job_id, attempt)
    (ispath(seal_path) || islink(seal_path)) && error(
        "sealed terminal attempt cannot be retired")
    (ispath(retirement_path) || islink(retirement_path)) && error(
        "attempt already contains a retirement disposition")
    result_path = ld1b1_result_path(execution_root, job.job_id, attempt)
    result_present = ispath(result_path) || islink(result_path)
    if !result_present
        return (;
            retirement_reason_code = :interrupted_without_result,
            result_present = false,
            result_file_sha256 = nothing,
            result_semantic_assessment = :result_absent,
        )
    end
    try
        semantic = ld1b1_validate_result(
            result_path,
            identity,
            job,
            attempt;
            calibration_semantic_context,
            allow_interruption_review = true,
        )
        return (;
            retirement_reason_code =
                :interrupted_with_semantically_valid_unsealed_result,
            result_present = true,
            result_file_sha256 = semantic.result_sha256,
            result_semantic_assessment = :semantically_valid_unsealed_result,
        )
    catch
        return (;
            retirement_reason_code =
                :interrupted_with_invalid_unsealed_result,
            result_present = true,
            result_file_sha256 =
                ld1b1_observed_path_sha256(result_path),
            result_semantic_assessment = :invalid_unsealed_result,
        )
    end
end

function ld1b1_recovery_reservation_context(attempt_dir::AbstractString,
        identity, job, attempt::Int)
    execution_root = ld1b1_result_execution_root(
        joinpath(attempt_dir, "job_result.json"))
    reservation_path = ld1b1_attempt_reservation_path(
        execution_root, job.job_id, attempt)
    if !(ispath(reservation_path) || islink(reservation_path))
        return (;
            execution_root,
            lineage = nothing,
            file_kwargs = (;),
            artifact_kwargs = (;),
        )
    end
    lineage = ld1b1_reservation_lineage(
        execution_root, identity, job, attempt)
    return (;
        execution_root,
        lineage,
        file_kwargs = (;
            reservation_path = lineage.reservation_path,
            execution_root,
            expected_reservation_id =
                lineage.reservation.reservation_id,
        ),
        artifact_kwargs = lineage.lineage_args,
    )
end

function ld1b1_interruption_review_validation_context(
        attempt_dir::AbstractString, review_artifact,
        identity, job, attempt::Int)
    attempt_role = attempt == 1 ? :primary : :remediation
    identity_args = (;
        plan_identity = ld1b1_result_plan_identity(identity),
        execution_source_identity = identity.execution_source_identity,
        job_identity = ld1b1_result_job_identity(job),
        attempt_number = attempt,
        attempt_role,
    )
    recovery = ld1b1_recovery_reservation_context(
        attempt_dir, identity, job, attempt)
    launch = LD1B1Recovery.ld1b_validate_child_launch_file(
        attempt_dir; identity_args..., recovery.file_kwargs...)
    native = ld1b1_json_native(review_artifact)
    haskey(native, "review") || error(
        "external stopped-process review lacks its review block")
    review = native["review"]
    review isa AbstractDict || error(
        "external stopped-process review has an invalid review block")
    haskey(review, "mode") || error(
        "external stopped-process review lacks its review mode")
    mode = ld1b1_symbol(review["mode"])
    exit = if mode === :validated_exit_receipt
        LD1B1Recovery.ld1b_validate_child_exit_file(
            attempt_dir; identity_args..., recovery.file_kwargs...)
    elseif mode === :external_process_identity_review
        exit_path = joinpath(
            attempt_dir, LD1B1Recovery.LD1B_CHILD_EXIT_FILENAME)
        (ispath(exit_path) || islink(exit_path)) && error(
            "external process-identity review cannot ignore an exit receipt")
        nothing
    else
        error("external stopped-process review has an unsupported mode")
    end
    inventory = LD1B1Recovery.
        ld1b_inventory_before_interruption_review(attempt_dir)
    validator = value -> LD1B1Recovery.
        ld1b_validate_stopped_process_interruption_review(
            value;
            identity_args...,
            owner_artifact = launch.owner.artifact,
            owner_receipt_sha256 = launch.owner.file_sha256,
            launch_artifact = launch.artifact,
            launch_receipt_sha256 = launch.file_sha256,
            exit_artifact = exit === nothing ? nothing : exit.artifact,
            exit_receipt_sha256 =
                exit === nothing ? nothing : exit.file_sha256,
            expected_inventory_before_review = inventory,
            recovery.artifact_kwargs...,
        )
    return (;
        identity_args,
        launch,
        exit,
        inventory,
        validator,
        recovery,
    )
end

function ld1b1_validate_external_interruption_review(
        source_path::AbstractString, attempt_dir::AbstractString,
        identity, job, attempt::Int)
    source = LD1B1AttemptArchive._ld1b_read_json_snapshot(
        normpath(source_path),
        dirname(normpath(source_path)),
        "external stopped-process interruption review",
    )
    context = ld1b1_interruption_review_validation_context(
        attempt_dir, source.parsed, identity, job, attempt)
    validation = context.validator(source.parsed)
    return (; source, context, validation)
end

function ld1b1_publish_external_interruption_review(
        source_path::AbstractString, attempt_dir::AbstractString,
        execution_root::AbstractString, identity, job, attempt::Int)
    external = ld1b1_validate_external_interruption_review(
        source_path, attempt_dir, identity, job, attempt)
    target = joinpath(
        attempt_dir, LD1B1Recovery.LD1B_INTERRUPTION_REVIEW_FILENAME)
    publication = if ispath(target) || islink(target)
        existing = LD1B1Recovery.ld1b_validate_interruption_review_file(
            attempt_dir;
            external.context.identity_args...,
            external.context.recovery.file_kwargs...,
        )
        existing.review_content_hash == external.validation.content_hash ||
            error("existing interruption review differs from the supplied review")
        (;
            published = false,
            reused_existing = true,
            path = target,
            review_file_sha256 = existing.review_file_sha256,
            review_content_hash = existing.review_content_hash,
        )
    else
        published = LD1B1AttemptArchive.
            ld1b_atomic_publish_json_create_new(
                target,
                external.source.parsed,
                ld1b1_recovery_staging_dir(execution_root),
                execution_root;
                semantic_validator = external.context.validator,
                artifact_label =
                    "externally prepared stopped-process interruption review",
            )
        validated = LD1B1Recovery.ld1b_validate_interruption_review_file(
            attempt_dir;
            external.context.identity_args...,
            external.context.recovery.file_kwargs...,
        )
        (;
            published = true,
            reused_existing = false,
            path = target,
            review_file_sha256 = validated.review_file_sha256,
            review_content_hash = validated.review_content_hash,
            publication = published.publication,
        )
    end
    validation = LD1B1Recovery.ld1b_validate_interruption_review_file(
        attempt_dir;
        external.context.identity_args...,
        external.context.recovery.file_kwargs...,
    )
    return (; external, publication, validation)
end

function ld1b1_precommit_interruption_review_validation_context(
        attempt_dir::AbstractString, review_artifact,
        execution_root::AbstractString, identity, job, attempt::Int)
    lineage = ld1b1_reservation_lineage(
        execution_root, identity, job, attempt)
    normpath(attempt_dir) == normpath(lineage.attempt_dir) || error(
        "precommit review belongs to the wrong reserved attempt path")
    owner_path = joinpath(
        attempt_dir, LD1B1Recovery.LD1B_ATTEMPT_OWNER_FILENAME)
    owner = if ispath(owner_path) || islink(owner_path)
        LD1B1Recovery.ld1b_validate_canonical_attempt_owner_file(
            attempt_dir;
            reservation_path = lineage.reservation_path,
            execution_root,
            lineage.identity_args...,
            expected_reservation_id =
                lineage.reservation.reservation_id,
        )
    else
        nothing
    end
    for forbidden in (
            LD1B1Recovery.LD1B_CHILD_LAUNCH_FILENAME,
            LD1B1Recovery.LD1B_CHILD_EXIT_FILENAME,
            "job_result.json",
            LD1B1AttemptArchive.LD1B_ATTEMPT_SEAL_FILENAME,
        )
        path = joinpath(attempt_dir, forbidden)
        !(ispath(path) || islink(path)) || error(
            "precommit recovery cannot ignore $forbidden")
    end
    inventory = LD1B1Recovery.
        ld1b_inventory_before_precommit_interruption_review(attempt_dir)
    validator = value -> LD1B1Recovery.
        ld1b_validate_precommit_interruption_review(
            value;
            lineage.identity_args...,
            lineage.lineage_args...,
            owner_artifact = owner === nothing ? nothing : owner.artifact,
            owner_receipt_sha256 = owner === nothing ?
                nothing : owner.file_sha256,
            expected_inventory_before_review = inventory,
        )
    validation = validator(review_artifact)
    validation.scientific_contribution == 0 || error(
        "precommit review has a nonzero scientific contribution")
    return (; lineage, owner, inventory, validator, validation)
end

function ld1b1_validate_external_precommit_interruption_review(
        source_path::AbstractString, attempt_dir::AbstractString,
        execution_root::AbstractString, identity, job, attempt::Int)
    source = LD1B1AttemptArchive._ld1b_read_json_snapshot(
        normpath(source_path),
        dirname(normpath(source_path)),
        "external precommit interruption review",
    )
    context = ld1b1_precommit_interruption_review_validation_context(
        attempt_dir, source.parsed, execution_root, identity, job, attempt)
    return (; source, context, validation = context.validation)
end

function ld1b1_publish_external_precommit_interruption_review(
        source_path::AbstractString, attempt_dir::AbstractString,
        execution_root::AbstractString, identity, job, attempt::Int)
    external = ld1b1_validate_external_precommit_interruption_review(
        source_path, attempt_dir, execution_root, identity, job, attempt)
    target = joinpath(
        attempt_dir,
        LD1B1Recovery.LD1B_PRECOMMIT_INTERRUPTION_REVIEW_FILENAME,
    )
    publication = if ispath(target) || islink(target)
        native = ld1b1_json_native(external.source.parsed)
        review = native["review"]
        validation = LD1B1Recovery.
            ld1b_reuse_existing_precommit_interruption_review(
                attempt_dir;
                external.context.lineage.identity_args...,
                reservation_path =
                    external.context.lineage.reservation_path,
                execution_root,
                expected_reservation_id = external.context.lineage.
                    reservation.reservation_id,
                reason_code = external.validation.reason_code,
                review_host = ld1b1_string(review["review_host"]),
                reviewer = ld1b1_string(review["reviewer"]),
                reviewed_at_utc =
                    ld1b1_string(review["reviewed_at_utc"]),
                controller_confirmed_stopped = ld1b1_bool(
                    review["controller_confirmed_stopped"]),
                child_launch_receipt_confirmed_absent = ld1b1_bool(
                    review["child_launch_receipt_confirmed_absent"]),
                child_process_confirmed_stopped = ld1b1_bool(
                    review["child_process_confirmed_stopped"]),
            )
        validation.content_hash == external.validation.content_hash || error(
            "existing precommit review differs from the supplied review")
        (;
            reused_existing = true,
            published = false,
            path = target,
            file_sha256 = validation.file_sha256,
            content_hash = validation.content_hash,
        )
    else
        created = LD1B1AttemptArchive.ld1b_atomic_publish_json_create_new(
            target,
            external.source.parsed,
            ld1b1_recovery_staging_dir(execution_root),
            execution_root;
            semantic_validator = external.context.validator,
            artifact_label =
                "externally prepared precommit interruption review",
        )
        merge(created, (; reused_existing = false))
    end
    validation = ld1b1_validate_precommit_interruption_review_record(
        attempt_dir, execution_root, identity, job, attempt)
    validation.content_hash == external.validation.content_hash || error(
        "published precommit review differs from the supplied review")
    return (; external, publication, validation)
end

function ld1b1_validate_precommit_interruption_review_record(
        attempt_dir::AbstractString, execution_root::AbstractString,
        identity, job, attempt::Int)
    lineage = ld1b1_reservation_lineage(
        execution_root, identity, job, attempt)
    owner_path = joinpath(
        attempt_dir, LD1B1Recovery.LD1B_ATTEMPT_OWNER_FILENAME)
    owner = if ispath(owner_path) || islink(owner_path)
        LD1B1Recovery.ld1b_validate_canonical_attempt_owner_file(
            attempt_dir;
            reservation_path = lineage.reservation_path,
            execution_root,
            lineage.identity_args...,
            expected_reservation_id =
                lineage.reservation.reservation_id,
        )
    else
        nothing
    end
    review_path = joinpath(
        attempt_dir,
        LD1B1Recovery.LD1B_PRECOMMIT_INTERRUPTION_REVIEW_FILENAME,
    )
    snapshot = LD1B1AttemptArchive._ld1b_read_json_snapshot(
        review_path, attempt_dir, "precommit interruption review")
    validation = LD1B1Recovery.ld1b_validate_precommit_interruption_review(
        snapshot.parsed;
        lineage.identity_args...,
        lineage.lineage_args...,
        owner_artifact = owner === nothing ? nothing : owner.artifact,
        owner_receipt_sha256 = owner === nothing ? nothing : owner.file_sha256,
    )
    validation.scientific_contribution == 0 || error(
        "precommit review has a nonzero scientific contribution")
    return (;
        valid = true,
        file_sha256 = snapshot.sha256,
        content_hash = validation.content_hash,
        reason_code = validation.reason_code,
        owner_present = validation.owner_present,
        scientific_contribution = validation.scientific_contribution,
        artifact = validation.native,
        lineage,
    )
end

function ld1b1_attempt_numbers(job_dir::AbstractString)
    (!isdir(job_dir) || islink(job_dir)) && return Int[], String[]
    numbers = Int[]
    unexpected = String[]
    for entry in sort(readdir(job_dir))
        path = joinpath(job_dir, entry)
        matched = match(r"^attempt_([0-9]{3})$", entry)
        if matched === nothing || !isdir(path) || islink(path)
            push!(unexpected, entry)
            continue
        end
        attempt = parse(Int, matched.captures[1])
        attempt >= 1 ? push!(numbers, attempt) : push!(unexpected, entry)
    end
    return sort(numbers), unexpected
end

function ld1b1_scan_attempt_reservations(specs, identity,
        execution_root::AbstractString)
    root = ld1b1_attempt_reservations_root(execution_root)
    rows = NamedTuple[]
    unexpected_entries = NamedTuple[]
    unexpected_plan_entries = NamedTuple[]
    by_job = Dict(job.job_id => job for job in specs)
    if !ispath(root) && !islink(root)
        return (;
            active = false,
            rows = (),
            by_key = Dict{Tuple{String,Int},Any}(),
            unexpected_entries = (),
            unexpected_plan_entries = (),
        )
    end
    if !isdir(root) || islink(root)
        entry = ld1b1_unexpected_entry(root, execution_root)
        return (;
            active = true,
            rows = (),
            by_key = Dict{Tuple{String,Int},Any}(),
            unexpected_entries = (entry,),
            unexpected_plan_entries = (entry,),
        )
    end
    ld1b1_reject_symlink_components(root, execution_root)
    for job_entry in sort(readdir(root))
        job_path = joinpath(root, job_entry)
        if !haskey(by_job, job_entry) || !isdir(job_path) || islink(job_path)
            entry = ld1b1_unexpected_entry(job_path, execution_root)
            push!(unexpected_entries, entry)
            push!(unexpected_plan_entries, entry)
            continue
        end
        job = by_job[job_entry]
        for attempt_entry in sort(readdir(job_path))
            attempt_path = joinpath(job_path, attempt_entry)
            matched = match(r"^attempt_([0-9]{3})$", attempt_entry)
            if matched === nothing || !isdir(attempt_path) ||
                    islink(attempt_path)
                push!(unexpected_entries,
                    ld1b1_unexpected_entry(attempt_path, execution_root))
                continue
            end
            attempt = parse(Int, only(matched.captures))
            expected_receipt = ld1b1_attempt_reservation_path(
                execution_root, job.job_id, attempt)
            entries = sort(readdir(attempt_path))
            if entries != [LD1B1Recovery.LD1B_ATTEMPT_RESERVATION_FILENAME]
                push!(unexpected_entries,
                    ld1b1_unexpected_entry(attempt_path, execution_root))
                push!(rows, (;
                    job_id = job.job_id,
                    attempt,
                    reservation_path = ld1b1_record_path(expected_receipt),
                    reservation_valid = false,
                    attempt_directory_present = isdir(ld1b1_attempt_dir(
                        execution_root, job.job_id, attempt)),
                    reservation_id = missing,
                    reservation_file_sha256 =
                        ld1b1_observed_path_sha256(expected_receipt),
                    reservation_content_hash = missing,
                    assessment = :invalid_reservation_directory,
                    error = "reservation directory has a noncanonical inventory",
                ))
                continue
            end
            try
                lineage = ld1b1_reservation_lineage(
                    execution_root, identity, job, attempt)
                attempt_present = isdir(lineage.attempt_dir) &&
                    !islink(lineage.attempt_dir)
                push!(rows, (;
                    job_id = job.job_id,
                    attempt,
                    reservation_path =
                        ld1b1_record_path(lineage.reservation_path),
                    reservation_valid = true,
                    attempt_directory_present = attempt_present,
                    reservation_id =
                        lineage.reservation.reservation_id,
                    reservation_file_sha256 =
                        lineage.reservation.file_sha256,
                    reservation_content_hash =
                        lineage.reservation.content_hash,
                    assessment = attempt_present ? :bound_to_attempt_directory :
                        :reserved_before_attempt_directory,
                    error = missing,
                ))
                attempt_present || push!(unexpected_entries,
                    ld1b1_unexpected_marker(
                        lineage.reservation_path,
                        execution_root,
                        "reservation_without_attempt_directory",
                    ))
            catch err
                push!(rows, (;
                    job_id = job.job_id,
                    attempt,
                    reservation_path = ld1b1_record_path(expected_receipt),
                    reservation_valid = false,
                    attempt_directory_present = isdir(ld1b1_attempt_dir(
                        execution_root, job.job_id, attempt)),
                    reservation_id = missing,
                    reservation_file_sha256 =
                        ld1b1_observed_path_sha256(expected_receipt),
                    reservation_content_hash = missing,
                    assessment = :invalid_reservation,
                    error = portable_error_message(err),
                ))
                push!(unexpected_entries,
                    ld1b1_unexpected_entry(expected_receipt, execution_root))
            end
        end
    end
    sort!(rows; by = row -> (row.job_id, row.attempt))
    by_key = Dict((row.job_id, row.attempt) => row for row in rows)
    return (;
        active = true,
        rows = Tuple(rows),
        by_key,
        unexpected_entries = Tuple(unexpected_entries),
        unexpected_plan_entries = Tuple(unexpected_plan_entries),
    )
end

function ld1b1_empty_scan(specs, identity)
    return (;
        job_state_rows = (),
        scenario_status_rows = (),
        attempt_reservation_scan_active = false,
        attempt_reservation_rows = (),
        attempt_reservation_state_digest = missing,
        unexpected_entries = (),
        unexpected_plan_entries = (),
        state_digest = missing,
        observed_primary_result_set_sha256 = missing,
        observed_primary_disposition_set_sha256 = missing,
        summary = (;
            n_jobs = length(specs),
            scan_assessment = :not_scanned,
            n_primary_attempts_observed = missing,
            n_completed_primary_outcomes = missing,
            n_pre_fit_rejected_primary_outcomes = missing,
            n_categorized_primary_failures = missing,
            n_missing_primary_outcomes = missing,
            n_retry_attempts_observed = missing,
            n_invalid_attempts = missing,
            n_partial_attempts = missing,
            n_retired_attempts = missing,
            n_retired_primary_attempts = missing,
            n_retired_remediation_attempts = missing,
            n_reviewed_pending_retirement_attempts = missing,
            n_disposition_conflicts = missing,
            n_lineage_mismatches = missing,
            n_invalid_primary_attempts = missing,
            n_invalid_remediation_attempts = missing,
            n_partial_primary_attempts = missing,
            n_partial_remediation_attempts = missing,
            n_primary_lineage_mismatches = missing,
            n_remediation_lineage_mismatches = missing,
            n_attempt_sequence_gaps = missing,
            n_unexpected_attempt_tree_entries = missing,
            n_unexpected_plan_entries = missing,
            all_primary_outcomes_recorded = missing,
            all_primary_attempts_disposed = missing,
            primary_attempt_tree_clean = missing,
            remediation_archive_clean = missing,
            clean_attempt_tree = missing,
            attempt_archive_integrity_passed = missing,
            primary_tree_assessment = :not_assessed,
            remediation_archive_assessment = :not_assessed,
            attempt_archive_assessment = :not_assessed,
            pilot_execution_completed = false,
            operational_gate_passed = false,
            aggregate_ready = false,
            aggregate_assessment = :not_assessed,
            execution_plan_id = identity.plan_id,
        ),
    )
end

function ld1b1_scan_attempts(specs, identity, execution_root::AbstractString;
        calibration_semantic_context = nothing)
    calibration_semantic_context === nothing && error(
        "attempt scanning requires the canonical calibration semantic context")
    expected_ids = Set(job.job_id for job in specs)
    jobs_root = joinpath(execution_root, "jobs")
    unexpected_entries = NamedTuple[]
    unexpected_plan_entries = NamedTuple[]
    jobs_root_safe = false
    if islink(jobs_root)
        entry = ld1b1_unexpected_entry(jobs_root, execution_root)
        push!(unexpected_entries, entry)
        push!(unexpected_plan_entries, entry)
    elseif !ispath(jobs_root)
        jobs_root_safe = true
    elseif isdir(jobs_root)
        ld1b1_reject_symlink_components(jobs_root, execution_root)
        jobs_root_safe = true
        for entry in sort(readdir(jobs_root))
            path = joinpath(jobs_root, entry)
            if !(entry in expected_ids) || !isdir(path) || islink(path)
                unexpected = ld1b1_unexpected_entry(path, execution_root)
                push!(unexpected_entries, unexpected)
                push!(unexpected_plan_entries, unexpected)
            end
        end
    else
        entry = ld1b1_unexpected_entry(jobs_root, execution_root)
        push!(unexpected_entries, entry)
        push!(unexpected_plan_entries, entry)
    end
    reservation_scan = ld1b1_scan_attempt_reservations(
        specs, identity, execution_root)
    append!(unexpected_entries, reservation_scan.unexpected_entries)
    append!(unexpected_plan_entries,
        reservation_scan.unexpected_plan_entries)

    rows = NamedTuple[]
    for job in specs
        job_dir = joinpath(jobs_root, job.job_id)
        attempts, unexpected = jobs_root_safe ?
            ld1b1_attempt_numbers(job_dir) : (Int[], String[])
        reservation_rows = [row for row in reservation_scan.rows
            if row.job_id == job.job_id]
        reserved_attempts = [row.attempt for row in reservation_rows]
        observed_attempts = sort!(unique(vcat(attempts, reserved_attempts)))
        append!(unexpected_entries,
            [ld1b1_unexpected_entry(
                joinpath(job_dir, entry), execution_root)
                for entry in unexpected])
        contiguous_attempts = isempty(observed_attempts) ||
            observed_attempts == collect(1:maximum(observed_attempts))
        contiguous_attempts || push!(unexpected_entries,
            ld1b1_unexpected_marker(job_dir, execution_root,
                "noncontiguous_attempt_sequence"))
        invalid = 0
        partial = 0
        lineage = 0
        invalid_primary = 0
        invalid_remediation = 0
        partial_primary = 0
        partial_remediation = 0
        retired = 0
        retired_primary = 0
        retired_remediation = 0
        reviewed_pending_retirement = 0
        disposition_conflicts = 0
        primary_lineage = 0
        remediation_lineage = 0
        statuses = Dict{Int,Symbol}()
        outcomes = Dict{Int,Symbol}()
        attempt_result_rows = NamedTuple[]
        for attempt in attempts
            if reservation_scan.active &&
                    !haskey(reservation_scan.by_key, (job.job_id, attempt))
                push!(unexpected_entries, ld1b1_unexpected_marker(
                    ld1b1_attempt_dir(
                        execution_root, job.job_id, attempt),
                    execution_root,
                    "attempt_directory_without_reservation",
                ))
            end
            attempt_dir = ld1b1_attempt_dir(
                execution_root, job.job_id, attempt)
            result_path = ld1b1_result_path(execution_root, job.job_id, attempt)
            seal_path = ld1b1_seal_path(
                execution_root, job.job_id, attempt)
            launched_review_path = ld1b1_interruption_review_path(
                execution_root, job.job_id, attempt)
            precommit_review_path =
                ld1b1_precommit_interruption_review_path(
                    execution_root, job.job_id, attempt)
            retirement_path = ld1b1_retirement_path(
                execution_root, job.job_id, attempt)
            result_present = ispath(result_path) || islink(result_path)
            seal_present = ispath(seal_path) || islink(seal_path)
            launched_review_present = ispath(launched_review_path) ||
                islink(launched_review_path)
            precommit_review_present = ispath(precommit_review_path) ||
                islink(precommit_review_path)
            review_present = launched_review_present ||
                precommit_review_present
            review_path = precommit_review_present ?
                precommit_review_path : launched_review_path
            launched_review_present && precommit_review_present &&
                (disposition_conflicts += 1)
            retirement_present =
                ispath(retirement_path) || islink(retirement_path)
            if retirement_present
                seal_present && (disposition_conflicts += 1)
                try
                    validated = ld1b1_validate_retired_attempt(
                        execution_root, identity, job, attempt)
                    retired += 1
                    attempt == 1 ? (retired_primary += 1) :
                        (retired_remediation += 1)
                    push!(attempt_result_rows, (;
                        attempt_number = attempt,
                        attempt_role =
                            attempt == 1 ? :primary : :remediation,
                        validated...,
                        result_sha256 = result_present ?
                            ld1b1_observed_path_sha256(result_path) : missing,
                        result_content_hash = missing,
                        runner_source_sha256 = missing,
                        evidence_manifest_sha256 = missing,
                        seal_file_sha256 = seal_present ?
                            ld1b1_observed_path_sha256(seal_path) : missing,
                        seal_content_hash = missing,
                        helper_attempt_inventory_sha256 =
                            validated.attempt_inventory_sha256,
                    ))
                catch err
                    invalid += 1
                    attempt == 1 ? (invalid_primary += 1) :
                        (invalid_remediation += 1)
                    push!(attempt_result_rows, (;
                        attempt_number = attempt,
                        attempt_role =
                            attempt == 1 ? :primary : :remediation,
                        archive_state = :invalid,
                        terminal_status = missing,
                        terminal_outcome_code = missing,
                        result_sha256 = result_present ?
                            ld1b1_observed_path_sha256(result_path) : missing,
                        result_content_hash = missing,
                        runner_source_sha256 = missing,
                        evidence_manifest_sha256 = missing,
                        seal_file_sha256 = seal_present ?
                            ld1b1_observed_path_sha256(seal_path) : missing,
                        seal_content_hash = missing,
                        review_file_sha256 = review_present ?
                            ld1b1_observed_path_sha256(review_path) : missing,
                        retirement_file_sha256 =
                            ld1b1_observed_path_sha256(retirement_path),
                        attempt_inventory_sha256 =
                            ld1b1_observed_semantic_inventory_sha256(
                                attempt_dir),
                        helper_attempt_inventory_sha256 =
                            ld1b1_observed_helper_inventory_sha256(
                                attempt_dir),
                    ))
                end
                continue
            end

            if (review_present && seal_present) ||
                    (launched_review_present && precommit_review_present)
                disposition_conflicts += 1
                invalid += 1
                attempt == 1 ? (invalid_primary += 1) :
                    (invalid_remediation += 1)
                push!(attempt_result_rows, (;
                    attempt_number = attempt,
                    attempt_role = attempt == 1 ? :primary : :remediation,
                    archive_state = :invalid_disposition_conflict,
                    terminal_status = missing,
                    terminal_outcome_code = missing,
                    result_sha256 = result_present ?
                        ld1b1_observed_path_sha256(result_path) : missing,
                    result_content_hash = missing,
                    runner_source_sha256 = missing,
                    evidence_manifest_sha256 = missing,
                    seal_file_sha256 =
                        ld1b1_observed_path_sha256(seal_path),
                    seal_content_hash = missing,
                    review_file_sha256 =
                        ld1b1_observed_path_sha256(review_path),
                    retirement_file_sha256 = missing,
                    attempt_inventory_sha256 =
                        ld1b1_observed_semantic_inventory_sha256(attempt_dir),
                    helper_attempt_inventory_sha256 =
                        ld1b1_observed_helper_inventory_sha256(attempt_dir),
                ))
                continue
            end

            if review_present
                try
                    reviewed = if precommit_review_present
                        validated =
                            ld1b1_validate_precommit_interruption_review_record(
                                attempt_dir,
                                execution_root,
                                identity,
                                job,
                                attempt,
                            )
                        (;
                            kind = :precommit_interruption,
                            reason = validated.reason_code,
                            scientific_contribution =
                                validated.scientific_contribution,
                        )
                    else
                        recovery = ld1b1_recovery_reservation_context(
                            attempt_dir, identity, job, attempt)
                        validated = LD1B1Recovery.
                            ld1b_validate_interruption_review_file(
                                attempt_dir;
                                plan_identity =
                                    ld1b1_result_plan_identity(identity),
                                execution_source_identity =
                                    identity.execution_source_identity,
                                job_identity =
                                    ld1b1_result_job_identity(job),
                                attempt_number = attempt,
                                attempt_role = attempt == 1 ?
                                    :primary : :remediation,
                                recovery.file_kwargs...,
                            )
                        (;
                            kind = :launched_interruption,
                            reason = validated.retirement_reason_code,
                            scientific_contribution = 0,
                        )
                    end
                    reviewed.scientific_contribution == 0 || error(
                        "pending interruption review contributes science")
                    reviewed_pending_retirement += 1
                    partial += 1
                    attempt == 1 ? (partial_primary += 1) :
                        (partial_remediation += 1)
                    push!(attempt_result_rows, (;
                        attempt_number = attempt,
                        attempt_role = attempt == 1 ?
                            :primary : :remediation,
                        archive_state = :reviewed_pending_retirement,
                        terminal_status = missing,
                        terminal_outcome_code = missing,
                        result_sha256 = result_present ?
                            ld1b1_observed_path_sha256(result_path) : missing,
                        result_content_hash = missing,
                        runner_source_sha256 = missing,
                        evidence_manifest_sha256 = missing,
                        seal_file_sha256 = missing,
                        seal_content_hash = missing,
                        review_kind = reviewed.kind,
                        retirement_reason_code = reviewed.reason,
                        scientific_contribution = 0,
                        review_file_sha256 =
                            ld1b1_observed_path_sha256(review_path),
                        retirement_file_sha256 = missing,
                        attempt_inventory_sha256 =
                            ld1b1_observed_semantic_inventory_sha256(
                                attempt_dir),
                        helper_attempt_inventory_sha256 =
                            ld1b1_observed_helper_inventory_sha256(
                                attempt_dir),
                    ))
                catch err
                    invalid += 1
                    attempt == 1 ? (invalid_primary += 1) :
                        (invalid_remediation += 1)
                    push!(attempt_result_rows, (;
                        attempt_number = attempt,
                        attempt_role = attempt == 1 ?
                            :primary : :remediation,
                        archive_state = :invalid_interruption_review,
                        terminal_status = missing,
                        terminal_outcome_code = missing,
                        result_sha256 = result_present ?
                            ld1b1_observed_path_sha256(result_path) : missing,
                        result_content_hash = missing,
                        runner_source_sha256 = missing,
                        evidence_manifest_sha256 = missing,
                        seal_file_sha256 = missing,
                        seal_content_hash = missing,
                        review_file_sha256 =
                            ld1b1_observed_path_sha256(review_path),
                        retirement_file_sha256 = missing,
                        review_validation_error = portable_error_message(err),
                        attempt_inventory_sha256 =
                            ld1b1_observed_semantic_inventory_sha256(
                                attempt_dir),
                        helper_attempt_inventory_sha256 =
                            ld1b1_observed_helper_inventory_sha256(
                                attempt_dir),
                    ))
                end
                continue
            end
            if !result_present && !seal_present
                partial += 1
                attempt == 1 ? (partial_primary += 1) :
                    (partial_remediation += 1)
                push!(attempt_result_rows, (;
                    attempt_number = attempt,
                    attempt_role = attempt == 1 ? :primary : :remediation,
                    archive_state = :partial,
                    terminal_status = missing,
                    terminal_outcome_code = missing,
                    result_sha256 = missing,
                    result_content_hash = missing,
                    runner_source_sha256 = missing,
                    evidence_manifest_sha256 = missing,
                    seal_file_sha256 = missing,
                    seal_content_hash = missing,
                    attempt_inventory_sha256 =
                        ld1b1_observed_semantic_inventory_sha256(attempt_dir),
                    helper_attempt_inventory_sha256 =
                        ld1b1_observed_helper_inventory_sha256(attempt_dir),
                ))
                continue
            end

            if result_present && !seal_present
                try
                    semantic = ld1b1_validate_result(
                        result_path,
                        identity,
                        job,
                        attempt;
                        calibration_semantic_context,
                    )
                    partial += 1
                    attempt == 1 ? (partial_primary += 1) :
                        (partial_remediation += 1)
                    push!(attempt_result_rows, (;
                        attempt_number = attempt,
                        attempt_role =
                            attempt == 1 ? :primary : :remediation,
                        archive_state = :partial,
                        terminal_status = missing,
                        terminal_outcome_code = missing,
                        result_sha256 = semantic.result_sha256,
                        result_content_hash = semantic.content_hash,
                        runner_source_sha256 =
                            semantic.runner_source_sha256,
                        evidence_manifest_sha256 =
                            semantic.evidence_manifest_sha256,
                        seal_file_sha256 = missing,
                        seal_content_hash = missing,
                        attempt_inventory_sha256 =
                            semantic.attempt_inventory_sha256,
                        helper_attempt_inventory_sha256 =
                            ld1b1_observed_helper_inventory_sha256(
                                attempt_dir),
                    ))
                    continue
                catch err
                    invalid += 1
                    attempt == 1 ? (invalid_primary += 1) :
                        (invalid_remediation += 1)
                    message = sprint(showerror, err)
                    if occursin("identity", message) ||
                            occursin("lineage", message) ||
                            occursin("seed contract", message)
                        lineage += 1
                        attempt == 1 ? (primary_lineage += 1) :
                            (remediation_lineage += 1)
                    end
                    push!(attempt_result_rows, (;
                        attempt_number = attempt,
                        attempt_role =
                            attempt == 1 ? :primary : :remediation,
                        archive_state = :invalid,
                        terminal_status = missing,
                        terminal_outcome_code = missing,
                        result_sha256 =
                            ld1b1_observed_path_sha256(result_path),
                        result_content_hash = missing,
                        runner_source_sha256 = missing,
                        evidence_manifest_sha256 = missing,
                        seal_file_sha256 = missing,
                        seal_content_hash = missing,
                        attempt_inventory_sha256 =
                            ld1b1_observed_semantic_inventory_sha256(
                                attempt_dir),
                        helper_attempt_inventory_sha256 =
                            ld1b1_observed_helper_inventory_sha256(
                                attempt_dir),
                    ))
                    continue
                end
            end

            if !result_present && seal_present
                invalid += 1
                attempt == 1 ? (invalid_primary += 1) :
                    (invalid_remediation += 1)
                push!(attempt_result_rows, (;
                    attempt_number = attempt,
                    attempt_role = attempt == 1 ? :primary : :remediation,
                    archive_state = :invalid,
                    terminal_status = missing,
                    terminal_outcome_code = missing,
                    result_sha256 = missing,
                    result_content_hash = missing,
                    runner_source_sha256 = missing,
                    evidence_manifest_sha256 = missing,
                    seal_file_sha256 =
                        ld1b1_observed_path_sha256(seal_path),
                    seal_content_hash = missing,
                    attempt_inventory_sha256 =
                        ld1b1_observed_semantic_inventory_sha256(attempt_dir),
                    helper_attempt_inventory_sha256 =
                        ld1b1_observed_helper_inventory_sha256(attempt_dir),
                ))
                continue
            end

            try
                validated = ld1b1_validate_completed_attempt(
                    result_path,
                    identity,
                    job,
                    attempt;
                    calibration_semantic_context,
                )
                statuses[attempt] = validated.terminal_status
                outcomes[attempt] = validated.terminal_outcome_code
                push!(attempt_result_rows, (;
                    attempt_number = attempt,
                    attempt_role = attempt == 1 ? :primary : :remediation,
                    archive_state = :verified_terminal,
                    terminal_status = validated.terminal_status,
                    terminal_outcome_code =
                        validated.terminal_outcome_code,
                    result_sha256 = validated.result_sha256,
                    result_content_hash = validated.content_hash,
                    runner_source_sha256 = validated.runner_source_sha256,
                    evidence_manifest_sha256 =
                        validated.evidence_manifest_sha256,
                    seal_file_sha256 = validated.seal_file_sha256,
                    seal_content_hash = validated.seal_content_hash,
                    attempt_inventory_sha256 =
                        validated.attempt_inventory_sha256,
                    helper_attempt_inventory_sha256 =
                        validated.helper_attempt_inventory_sha256,
                ))
            catch err
                invalid += 1
                attempt == 1 ? (invalid_primary += 1) :
                    (invalid_remediation += 1)
                message = sprint(showerror, err)
                if occursin("identity", message) ||
                        occursin("lineage", message) ||
                        occursin("seed contract", message)
                    lineage += 1
                    attempt == 1 ? (primary_lineage += 1) :
                        (remediation_lineage += 1)
                end
                push!(attempt_result_rows, (;
                    attempt_number = attempt,
                    attempt_role = attempt == 1 ? :primary : :remediation,
                    archive_state = :invalid,
                    terminal_status = missing,
                    terminal_outcome_code = missing,
                    result_sha256 =
                        ld1b1_observed_path_sha256(result_path),
                    result_content_hash = missing,
                    runner_source_sha256 = missing,
                    evidence_manifest_sha256 = missing,
                    seal_file_sha256 =
                        ld1b1_observed_path_sha256(seal_path),
                    seal_content_hash = missing,
                    attempt_inventory_sha256 =
                        ld1b1_observed_semantic_inventory_sha256(attempt_dir),
                    helper_attempt_inventory_sha256 =
                        ld1b1_observed_helper_inventory_sha256(attempt_dir),
                ))
            end
        end
        for reservation in reservation_rows
            reservation.attempt_directory_present && continue
            partial += 1
            reservation.attempt == 1 ? (partial_primary += 1) :
                (partial_remediation += 1)
            push!(attempt_result_rows, (;
                attempt_number = reservation.attempt,
                attempt_role = reservation.attempt == 1 ?
                    :primary : :remediation,
                archive_state = reservation.reservation_valid ?
                    :reserved_precommit_partial :
                    :invalid_reserved_precommit,
                terminal_status = missing,
                terminal_outcome_code = missing,
                result_sha256 = missing,
                result_content_hash = missing,
                runner_source_sha256 = missing,
                evidence_manifest_sha256 = missing,
                seal_file_sha256 = missing,
                seal_content_hash = missing,
                reservation_path = reservation.reservation_path,
                reservation_id = reservation.reservation_id,
                reservation_file_sha256 =
                    reservation.reservation_file_sha256,
                reservation_content_hash =
                    reservation.reservation_content_hash,
                scientific_contribution = 0,
                attempt_inventory_sha256 = missing,
                helper_attempt_inventory_sha256 = missing,
            ))
        end
        sort!(attempt_result_rows; by = row -> row.attempt_number)
        primary_present = 1 in attempts && isfile(
            ld1b1_result_path(execution_root, job.job_id, 1))
        primary_valid = haskey(statuses, 1)
        state = isempty(observed_attempts) ? :absent :
            !contiguous_attempts ? :noncontiguous_attempts :
            reviewed_pending_retirement > 0 && partial_primary > 0 ?
                :reviewed_pending_retirement :
            partial_primary > 0 ? :partial :
            primary_lineage > 0 ? :lineage_mismatch :
            invalid_primary > 0 ? :corrupt :
            retired_primary > 0 ? :primary_retired_interrupted :
            !primary_valid ? :missing_primary :
            reviewed_pending_retirement > 0 && partial_remediation > 0 ?
                :remediation_reviewed_pending_retirement :
            partial_remediation > 0 ? :remediation_partial :
            remediation_lineage > 0 ? :remediation_lineage_mismatch :
            invalid_remediation > 0 ? :remediation_corrupt :
            retired_remediation > 0 ?
                :complete_verified_with_retired_remediation :
            length(observed_attempts) == 1 ? :complete_verified :
            :complete_verified_with_remediation
        push!(rows, (;
            job_id = job.job_id,
            row_index = job.row_index,
            scenario_id = job.scenario_id,
            replication = job.replication,
            expected_action = job.expected_action,
            state,
            attempt_numbers = observed_attempts,
            n_attempts = length(observed_attempts),
            primary_present,
            primary_valid,
            primary_disposed = primary_valid || retired_primary == 1,
            primary_terminal_status = primary_valid ? statuses[1] : missing,
            primary_terminal_outcome_code =
                primary_valid ? outcomes[1] : missing,
            retry_attempts = count(>(1), observed_attempts),
            retired_attempts = retired,
            retired_primary_attempts = retired_primary,
            retired_remediation_attempts = retired_remediation,
            reviewed_pending_retirement_attempts =
                reviewed_pending_retirement,
            disposition_conflicts,
            invalid_attempts = invalid,
            partial_attempts = partial,
            lineage_mismatches = lineage,
            invalid_primary_attempts = invalid_primary,
            invalid_remediation_attempts = invalid_remediation,
            partial_primary_attempts = partial_primary,
            partial_remediation_attempts = partial_remediation,
            primary_lineage_mismatches = primary_lineage,
            remediation_lineage_mismatches = remediation_lineage,
            attempt_sequence_gap = !contiguous_attempts,
            attempt_result_rows = Tuple(attempt_result_rows),
        ))
    end
    summary = ld1b1_scan_summary(
        rows,
        unexpected_entries,
        unexpected_plan_entries;
        execution_plan_id = identity.plan_id,
    )
    reservation_state_digest = ld1b1_canonical_sha256((;
        active = reservation_scan.active,
        rows = reservation_scan.rows,
    ))
    state_digest = ld1b1_canonical_sha256((;
        attempt_tree_state_digest = summary.state_digest,
        attempt_reservation_state_digest = reservation_state_digest,
    ))
    return merge(summary, (;
        state_digest,
        attempt_reservation_scan_active = reservation_scan.active,
        attempt_reservation_rows = reservation_scan.rows,
        attempt_reservation_state_digest = reservation_state_digest,
    ))
end

function ld1b1_scan_summary(rows, unexpected_entries,
        unexpected_plan_entries;
        execution_plan_id)
    unexpected_entries = ld1b1_sorted_unexpected(unexpected_entries)
    unexpected_plan_entries =
        ld1b1_sorted_unexpected(unexpected_plan_entries)
    n_primary = count(row -> row.primary_valid, rows)
    n_completed = count(row -> row.primary_valid &&
        row.primary_terminal_status === :completed, rows)
    n_rejected = count(row -> row.primary_valid &&
        row.primary_terminal_status === :pre_fit_rejected, rows)
    n_failures = count(row -> row.primary_valid &&
        row.primary_terminal_status in LD1B1_CATEGORIZED_FAILURE_STATUSES, rows)
    n_missing = length(rows) - n_primary
    n_retry = sum(row.retry_attempts for row in rows)
    n_invalid = sum(row.invalid_attempts for row in rows)
    n_partial = sum(row.partial_attempts for row in rows)
    n_retired = sum(row.retired_attempts for row in rows)
    n_retired_primary = sum(row.retired_primary_attempts for row in rows)
    n_retired_remediation =
        sum(row.retired_remediation_attempts for row in rows)
    n_reviewed_pending_retirement = sum(
        row.reviewed_pending_retirement_attempts for row in rows)
    n_disposition_conflicts = sum(row.disposition_conflicts for row in rows)
    n_lineage = sum(row.lineage_mismatches for row in rows)
    n_invalid_primary = sum(row.invalid_primary_attempts for row in rows)
    n_invalid_remediation =
        sum(row.invalid_remediation_attempts for row in rows)
    n_partial_primary = sum(row.partial_primary_attempts for row in rows)
    n_partial_remediation =
        sum(row.partial_remediation_attempts for row in rows)
    n_primary_lineage = sum(row.primary_lineage_mismatches for row in rows)
    n_remediation_lineage =
        sum(row.remediation_lineage_mismatches for row in rows)
    n_sequence_gaps = count(row -> row.attempt_sequence_gap, rows)

    scenario_ids = unique(row.scenario_id for row in rows)
    scenario_rows = Tuple((function ()
        selected = [row for row in rows if row.scenario_id === scenario_id]
        expected_action = only(unique(row.expected_action for row in selected))
        completed = count(row -> row.primary_valid &&
            row.primary_terminal_status === :completed, selected)
        rejected = count(row -> row.primary_valid &&
            row.primary_terminal_status === :pre_fit_rejected, selected)
        failures = count(row -> row.primary_valid &&
            row.primary_terminal_status in LD1B1_CATEGORIZED_FAILURE_STATUSES,
            selected)
        missing = count(row -> !row.primary_valid, selected)
        gate_passed = expected_action === :pre_fit_reject ?
            rejected == LD1B1_REQUIRED_REJECTIONS_PER_REJECTION_SCENARIO &&
                missing == 0 :
            completed >= LD1B1_MINIMUM_COMPLETED_PER_ELIGIBLE_SCENARIO &&
                failures <=
                    LD1B1_MAXIMUM_FAILURES_PER_ELIGIBLE_SCENARIO &&
                missing == 0
        (;
            scenario_id,
            expected_action,
            planned = length(selected),
            completed,
            pre_fit_rejected = rejected,
            categorized_failures = failures,
            missing_primary = missing,
            operational_gate_passed = gate_passed,
        )
    end)() for scenario_id in scenario_ids)
    all_primary_recorded = n_primary == length(rows)
    all_primary_disposed = count(row -> row.primary_disposed, rows) ==
        length(rows)
    primary_attempt_tree_clean = n_invalid_primary == 0 &&
        n_partial_primary == 0 && n_primary_lineage == 0 &&
        isempty(unexpected_plan_entries)
    remediation_archive_clean = n_invalid_remediation == 0 &&
        n_partial_remediation == 0 && n_remediation_lineage == 0 &&
        n_sequence_gaps == 0 && isempty(unexpected_entries)
    clean_attempt_tree = primary_attempt_tree_clean &&
        remediation_archive_clean
    pilot_execution_completed = all_primary_recorded &&
        primary_attempt_tree_clean
    operational_gate_passed = pilot_execution_completed &&
        all(row -> row.operational_gate_passed, scenario_rows)
    observed_primary_result_rows = Tuple((;
        job_id = row.job_id,
        row_index = row.row_index,
        terminal_status = row.primary_terminal_status,
        terminal_outcome_code = row.primary_terminal_outcome_code,
        result_sha256 = only(attempt.result_sha256 for attempt in
            row.attempt_result_rows if attempt.attempt_number == 1),
        result_content_hash = only(attempt.result_content_hash for attempt in
            row.attempt_result_rows if attempt.attempt_number == 1),
        runner_source_sha256 = only(attempt.runner_source_sha256 for attempt in
            row.attempt_result_rows if attempt.attempt_number == 1),
        evidence_manifest_sha256 = only(
            attempt.evidence_manifest_sha256 for attempt in
            row.attempt_result_rows if attempt.attempt_number == 1),
        seal_file_sha256 = only(attempt.seal_file_sha256 for attempt in
            row.attempt_result_rows if attempt.attempt_number == 1),
        seal_content_hash = only(attempt.seal_content_hash for attempt in
            row.attempt_result_rows if attempt.attempt_number == 1),
        helper_attempt_inventory_sha256 = only(
            attempt.helper_attempt_inventory_sha256 for attempt in
            row.attempt_result_rows if attempt.attempt_number == 1),
    ) for row in rows if row.primary_valid)
    observed_primary_result_set_sha256 = ld1b1_canonical_sha256(
        observed_primary_result_rows)
    observed_primary_disposition_rows = Tuple(begin
        attempt = only(attempt for attempt in row.attempt_result_rows
            if attempt.attempt_number == 1)
        if row.primary_valid
            (;
                job_id = row.job_id,
                row_index = row.row_index,
                disposition_kind = :sealed_terminal,
                control_file_sha256 = attempt.seal_file_sha256,
                control_content_hash = attempt.seal_content_hash,
                attempt_inventory_sha256 =
                    attempt.helper_attempt_inventory_sha256,
            )
        else
            (;
                job_id = row.job_id,
                row_index = row.row_index,
                disposition_kind = :retired_interrupted,
                control_file_sha256 = attempt.retirement_file_sha256,
                control_content_hash = attempt.retirement_content_hash,
                attempt_inventory_sha256 =
                    attempt.helper_attempt_inventory_sha256,
            )
        end
    end for row in rows if row.primary_disposed)
    observed_primary_disposition_set_sha256 = ld1b1_canonical_sha256(
        observed_primary_disposition_rows)
    state_digest = ld1b1_canonical_sha256((;
        execution_plan_id,
        scan_assessment = :completed,
        rows,
        unexpected_entries,
        unexpected_plan_entries,
    ))
    primary_tree_assessment = primary_attempt_tree_clean ? :passed : :failed
    remediation_archive_assessment =
        remediation_archive_clean ? :passed : :failed
    attempt_archive_assessment = clean_attempt_tree ? :passed : :failed
    aggregate_assessment = pilot_execution_completed &&
        operational_gate_passed ? :ready : :not_ready
    return (;
        job_state_rows = Tuple(rows),
        scenario_status_rows = scenario_rows,
        unexpected_entries,
        unexpected_plan_entries,
        state_digest,
        observed_primary_result_set_sha256,
        observed_primary_disposition_set_sha256,
        summary = (;
            n_jobs = length(rows),
            scan_assessment = :completed,
            n_primary_attempts_observed = n_primary,
            n_completed_primary_outcomes = n_completed,
            n_pre_fit_rejected_primary_outcomes = n_rejected,
            n_categorized_primary_failures = n_failures,
            n_missing_primary_outcomes = n_missing,
            n_retry_attempts_observed = n_retry,
            n_invalid_attempts = n_invalid,
            n_partial_attempts = n_partial,
            n_retired_attempts = n_retired,
            n_retired_primary_attempts = n_retired_primary,
            n_retired_remediation_attempts = n_retired_remediation,
            n_reviewed_pending_retirement_attempts =
                n_reviewed_pending_retirement,
            n_disposition_conflicts,
            n_lineage_mismatches = n_lineage,
            n_invalid_primary_attempts = n_invalid_primary,
            n_invalid_remediation_attempts = n_invalid_remediation,
            n_partial_primary_attempts = n_partial_primary,
            n_partial_remediation_attempts = n_partial_remediation,
            n_primary_lineage_mismatches = n_primary_lineage,
            n_remediation_lineage_mismatches = n_remediation_lineage,
            n_attempt_sequence_gaps = n_sequence_gaps,
            n_unexpected_attempt_tree_entries = length(unexpected_entries),
            n_unexpected_plan_entries = length(unexpected_plan_entries),
            all_primary_outcomes_recorded = all_primary_recorded,
            all_primary_attempts_disposed = all_primary_disposed,
            primary_attempt_tree_clean,
            remediation_archive_clean,
            clean_attempt_tree,
            attempt_archive_integrity_passed = clean_attempt_tree,
            primary_tree_assessment,
            remediation_archive_assessment,
            attempt_archive_assessment,
            pilot_execution_completed,
            operational_gate_passed,
            aggregate_ready = pilot_execution_completed &&
                operational_gate_passed,
            aggregate_assessment,
            execution_plan_id,
        ),
    )
end

function ld1b1_checkpoint_artifact(identity, scan; generated_at = string(Dates.now()))
    scan.summary.scan_assessment === :completed ||
        error("checkpoint requires a completed attempt-tree scan")
    artifact = (;
        schema = LD1B1_CHECKPOINT_SCHEMA,
        family = :mfrm,
        scope = :ld1b1_pilot_batch_derived_checkpoint,
        generated_at,
        plan_identity = identity,
        state_digest = scan.state_digest,
        observed_primary_result_set_sha256 =
            scan.observed_primary_result_set_sha256,
        observed_primary_disposition_set_sha256 =
            scan.observed_primary_disposition_set_sha256,
        summary = scan.summary,
        source_of_truth = :immutable_job_attempt_records,
        checkpoint_role = :derived_resume_index_only,
        chain_level_sampler_resume_supported = false,
    )
    return ld1b1_with_content_hash(artifact)
end

function ld1b1_resume_state(checkpoint_path::AbstractString, identity, scan)
    isfile(checkpoint_path) || error("--resume requires an existing checkpoint")
    checkpoint = JSON3.read(read(checkpoint_path, String))
    ld1b1_string(checkpoint[:schema]) == LD1B1_CHECKPOINT_SCHEMA ||
        error("resume checkpoint has an unexpected schema")
    ld1b1_verify_content_hash(checkpoint; label = "LD1b1 checkpoint")
    plan = checkpoint[:plan_identity]
    for field in (
            :plan_id,
            :protocol_plan_id,
            :protocol_file_sha256,
            :protocol_content_hash,
            :ordered_job_rows_sha256,
            :pilot_contract_sha256,
            :canonical_executor_source_pin_id,
        )
        ld1b1_string(plan[field]) == String(getproperty(identity, field)) ||
            error("resume checkpoint plan identity mismatch: $field")
    end
    ld1b1_canonical_sha256(ld1b1_json_native(
        plan[:execution_source_identity])) ==
        ld1b1_canonical_sha256(identity.execution_source_identity) || error(
        "resume checkpoint execution source identity mismatch")
    ld1b1_string(plan[:batch_harness_generator_source_sha256]) ==
        String(identity.batch_harness_generator_source_sha256) || error(
        "resume checkpoint harness-generator source identity mismatch")
    stored_digest = ld1b1_string(checkpoint[:state_digest])
    return (;
        checkpoint_present = true,
        checkpoint_verified = true,
        stored_state_digest = stored_digest,
        rescanned_state_digest = scan.state_digest,
        checkpoint_stale = stored_digest != scan.state_digest,
        resume_uses_rescanned_attempts = true,
    )
end

function ld1b1_no_resume_state(scan)
    return (;
        checkpoint_present = false,
        checkpoint_verified = false,
        stored_state_digest = missing,
        rescanned_state_digest = scan.state_digest,
        checkpoint_stale = false,
        resume_uses_rescanned_attempts = true,
    )
end

function ld1b1_atomic_write_artifact(path::AbstractString, artifact;
        overwrite::Bool)
    directory = dirname(path)
    mkpath(directory)
    temporary_path, io = mktemp(directory)
    try
        write_json(io, artifact)
        println(io)
        flush(io)
        close(io)
        if ispath(path) && !overwrite
            error("refusing to overwrite existing artifact: $path")
        end
        mv(temporary_path, path; force = overwrite)
    catch
        isopen(io) && close(io)
        ispath(temporary_path) && rm(temporary_path; force = true)
        rethrow()
    end
    return path
end

function ld1b1_julia_executable()
    return joinpath(Sys.BINDIR, Base.julia_exename())
end

function ld1b1_shell_quote(value::AbstractString)
    return "'" * replace(value, "'" => "'\\''") * "'"
end

ld1b1_command_string(args::Vector{String}) =
    join(ld1b1_shell_quote.(args), " ")

function ld1b1_portable_command_args(args::Vector{String})
    julia_executable = normpath(ld1b1_julia_executable())
    return [begin
        if normpath(value) == julia_executable
            "julia"
        elseif startswith(value, "--project=") &&
                normpath(value[(length("--project=") + 1):end]) == LD1B1_ROOT
            "--project=."
        elseif isabspath(value)
            ld1b1_record_path(value)
        else
            value
        end
    end for value in args]
end

ld1b1_portable_command_string(args::Vector{String}) =
    ld1b1_command_string(ld1b1_portable_command_args(args))

function ld1b1_job_command(job, identity, execution_root, options;
        runner_source_sha256 = nothing,
        controller_readiness_authorized::Bool = false,
        bounded_smoke_authorization = nothing)
    controller_readiness_authorized &&
        bounded_smoke_authorization !== nothing && error(
        "job command cannot combine pilot and bounded-smoke authorization")
    worker_mode = bounded_smoke_authorization !== nothing ?
        "bounded-smoke" :
        controller_readiness_authorized ? "execute" : "status"
    result_path = ld1b1_result_path(
        execution_root, job.job_id, options.attempt)
    args = String[
        ld1b1_julia_executable(),
        string("--project=", LD1B1_ROOT),
        options.runner,
        "--mode", worker_mode,
        "--protocol", options.protocol,
        "--job-id", job.job_id,
        "--row-index", string(job.row_index),
        "--attempt", string(options.attempt),
        "--output", result_path,
        "--reservation-receipt", ld1b1_attempt_reservation_path(
            execution_root, job.job_id, options.attempt),
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
        "--seed", string(job.seed),
        "--fit-seed", string(job.fit_seed),
        "--draw-selection-seed", string(job.draw_selection_seed),
        "--posterior-predictive-seed",
            string(job.posterior_predictive_seed),
    ]
    if bounded_smoke_authorization !== nothing
        append!(args, [
            "--attempt-role", "verification",
            "--bounded-smoke-authorization",
            String(bounded_smoke_authorization),
        ])
    elseif options.mode === :execute_retry
        append!(args, [
            "--attempt-role", "remediation",
            "--retry-of", string(options.retry_of),
            "--retry-reason", String(options.retry_reason),
            "--primary-result",
                ld1b1_result_path(execution_root, job.job_id, 1),
        ])
    else
        append!(args, ["--attempt-role", "primary"])
    end
    runner_source_sha256 === nothing || append!(args, [
        "--runner-source-sha256", String(runner_source_sha256),
    ])
    controller_readiness_authorized &&
        push!(args, "--controller-readiness-authorized")
    return (;
        args,
        result_path,
        controller_readiness_authorized,
        bounded_smoke_authorization,
        worker_mode = Symbol(replace(worker_mode, '-' => '_')),
    )
end

function ld1b1_require_attempt_available(job, identity, execution_root, options;
        calibration_semantic_context = nothing)
    calibration_semantic_context === nothing && error(
        "attempt admission requires the canonical calibration semantic context")
    attempt = options.attempt
    target_dir = ld1b1_attempt_dir(execution_root, job.job_id, attempt)
    reservation_path = ld1b1_attempt_reservation_path(
        execution_root, job.job_id, attempt)
    ld1b1_reject_symlink_components(target_dir, execution_root)
    ispath(target_dir) && error(
        "refusing to overwrite existing attempt directory: $target_dir")
    (ispath(reservation_path) || islink(reservation_path)) && error(
        "refusing to overwrite existing attempt reservation: $reservation_path")
    job_dir = dirname(target_dir)
    attempts, unexpected = ld1b1_attempt_numbers(job_dir)
    isempty(unexpected) || error("job directory contains noncanonical entries")
    if attempt == 1
        isempty(attempts) || error(
            "primary attempt cannot be added after another attempt exists")
    else
        attempts == collect(1:(attempt - 1)) || error(
            "remediation attempts must be contiguous and append-only")
        for previous_attempt in attempts
            previous_path = ld1b1_result_path(
                execution_root, job.job_id, previous_attempt)
            ld1b1_validate_completed_attempt(
                previous_path,
                identity,
                job,
                previous_attempt;
                calibration_semantic_context,
            )
        end
    end
    return target_dir
end

ld1b1_receipt_recorded_at_utc() = Dates.format(
    Dates.now(Dates.UTC), dateformat"yyyy-mm-ddTHH:MM:SS.sssZ")

function ld1b1_controller_receipt_identity(identity, job, attempt::Int;
        execution_context = ld1b1_execution_context())
    context = ld1b1_validate_execution_context(execution_context)
    return (;
        plan_identity = ld1b1_result_plan_identity(identity),
        execution_source_identity = identity.execution_source_identity,
        job_identity = ld1b1_result_job_identity(job),
        attempt_number = attempt,
        attempt_role = ld1b1_attempt_identity(attempt, context).role,
        execution_context = context,
    )
end

function ld1b1_attempt_reservation_id(identity, job, attempt::Int,
        controller_run_id::AbstractString)
    digest = ld1b1_canonical_sha256((;
        identity.plan_id,
        job.job_id,
        attempt,
        controller_run_id = String(controller_run_id),
    ))
    return string("ld1b1_", digest)
end

function ld1b1_reservation_lineage(execution_root::AbstractString,
        identity, job, attempt::Int; expected_reservation_id = nothing,
        execution_context = ld1b1_execution_context())
    attempt_dir = ld1b1_attempt_dir(
        execution_root, job.job_id, attempt)
    reservation_path = ld1b1_attempt_reservation_path(
        execution_root, job.job_id, attempt)
    identity_args = ld1b1_controller_receipt_identity(
        identity, job, attempt; execution_context)
    relative_attempt_path = relpath(attempt_dir, execution_root)
    reservation = LD1B1Recovery.ld1b_validate_attempt_reservation_file(
        reservation_path;
        execution_root,
        identity_args...,
        expected_reservation_id,
        expected_execution_root_relative_attempt_path =
            relative_attempt_path,
    )
    lineage_args = (;
        reservation_artifact = reservation.artifact,
        reservation_receipt_sha256 = reservation.file_sha256,
        expected_reservation_id = reservation.reservation_id,
        expected_execution_root_relative_reservation_path =
            reservation.execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path =
            relative_attempt_path,
    )
    return (;
        attempt_dir,
        reservation_path,
        relative_attempt_path,
        identity_args,
        lineage_args,
        reservation,
    )
end

function ld1b1_publish_attempt_reservation_create_new(
        execution_root::AbstractString, identity, job, attempt::Int,
        controller_run_id::AbstractString;
        execution_context = ld1b1_execution_context())
    mkpath(execution_root)
    isdir(execution_root) && !islink(execution_root) || error(
        "execution root is not a regular directory")
    attempt_dir = ld1b1_attempt_dir(
        execution_root, job.job_id, attempt)
    reservation_path = ld1b1_attempt_reservation_path(
        execution_root, job.job_id, attempt)
    mkpath(dirname(reservation_path))
    reservation_id = ld1b1_attempt_reservation_id(
        identity, job, attempt, controller_run_id)
    identity_args = ld1b1_controller_receipt_identity(
        identity, job, attempt; execution_context)
    publication = LD1B1Recovery.ld1b_publish_attempt_reservation(
        reservation_path;
        execution_root,
        identity_args...,
        reservation_id,
        execution_root_relative_attempt_path =
            relpath(attempt_dir, execution_root),
        controller_host = Sockets.gethostname(),
        controller_run_id,
        controller_pid = getpid(),
        recorded_at_utc = ld1b1_receipt_recorded_at_utc(),
        staging_dir =
            ld1b1_attempt_reservation_staging_dir(execution_root),
    )
    lineage = ld1b1_reservation_lineage(
        execution_root, identity, job, attempt; expected_reservation_id =
            reservation_id, execution_context)
    return (; publication, lineage)
end

function ld1b1_publish_receipt_create_new(path::AbstractString, artifact,
        execution_root::AbstractString; semantic_validator,
        artifact_label::AbstractString)
    return LD1B1AttemptArchive.ld1b_atomic_publish_json_create_new(
        path,
        artifact,
        ld1b1_receipt_staging_dir(execution_root),
        execution_root;
        semantic_validator,
        artifact_label,
    )
end

function ld1b1_publish_canonical_owner_create_new(lineage,
        execution_root::AbstractString)
    artifact = LD1B1Recovery.ld1b_canonical_attempt_owner_precommit(;
        lineage.identity_args...,
        lineage.lineage_args...,
        recorded_at_utc = ld1b1_receipt_recorded_at_utc(),
    )
    validator = value -> LD1B1Recovery.
        ld1b_validate_canonical_attempt_owner_precommit(
            value;
            lineage.identity_args...,
            lineage.lineage_args...,
        )
    path = joinpath(
        lineage.attempt_dir, LD1B1Recovery.LD1B_ATTEMPT_OWNER_FILENAME)
    publication = ld1b1_publish_receipt_create_new(
        path,
        artifact,
        execution_root;
        semantic_validator = validator,
        artifact_label = "canonical attempt-owner precommit",
    )
    owner = LD1B1Recovery.ld1b_validate_canonical_attempt_owner_file(
        lineage.attempt_dir;
        lineage.identity_args...,
        reservation_path = lineage.reservation_path,
        execution_root,
        expected_reservation_id =
            lineage.reservation.reservation_id,
    )
    return (; publication, owner)
end

function ld1b1_publish_child_launch_create_new(lineage, owner,
        child_pid::Integer, execution_root::AbstractString)
    child_pid = Int(child_pid)
    artifact = LD1B1Recovery.ld1b_child_launch_receipt(;
        lineage.identity_args...,
        lineage.lineage_args...,
        owner_artifact = owner.artifact,
        owner_receipt_sha256 = owner.file_sha256,
        child_pid,
        recorded_at_utc = ld1b1_receipt_recorded_at_utc(),
    )
    validator = value -> LD1B1Recovery.ld1b_validate_child_launch_receipt(
        value;
        lineage.identity_args...,
        lineage.lineage_args...,
        owner_artifact = owner.artifact,
        owner_receipt_sha256 = owner.file_sha256,
    )
    path = joinpath(
        lineage.attempt_dir, LD1B1Recovery.LD1B_CHILD_LAUNCH_FILENAME)
    publication = ld1b1_publish_receipt_create_new(
        path,
        artifact,
        execution_root;
        semantic_validator = validator,
        artifact_label = "child-launch receipt",
    )
    launch = LD1B1Recovery.ld1b_validate_child_launch_file(
        lineage.attempt_dir;
        lineage.identity_args...,
        reservation_path = lineage.reservation_path,
        execution_root,
        expected_reservation_id =
            lineage.reservation.reservation_id,
    )
    ld1b1_int(launch.artifact["launch"]["child_pid"]) == child_pid || error(
        "published child-launch receipt has the wrong PID")
    return (; publication, launch)
end

function ld1b1_publish_child_exit_create_new(lineage, launch,
        exit_code::Integer, execution_root::AbstractString)
    exit_code = Int(exit_code)
    artifact = LD1B1Recovery.ld1b_child_exit_receipt(;
        lineage.identity_args...,
        lineage.lineage_args...,
        owner_artifact = launch.owner.artifact,
        owner_receipt_sha256 = launch.owner.file_sha256,
        launch_artifact = launch.artifact,
        launch_receipt_sha256 = launch.file_sha256,
        exit_code,
        recorded_at_utc = ld1b1_receipt_recorded_at_utc(),
    )
    validator = value -> LD1B1Recovery.ld1b_validate_child_exit_receipt(
        value;
        lineage.identity_args...,
        lineage.lineage_args...,
        owner_artifact = launch.owner.artifact,
        owner_receipt_sha256 = launch.owner.file_sha256,
        launch_artifact = launch.artifact,
        launch_receipt_sha256 = launch.file_sha256,
    )
    path = joinpath(
        lineage.attempt_dir, LD1B1Recovery.LD1B_CHILD_EXIT_FILENAME)
    publication = ld1b1_publish_receipt_create_new(
        path,
        artifact,
        execution_root;
        semantic_validator = validator,
        artifact_label = "child-exit receipt",
    )
    exit = LD1B1Recovery.ld1b_validate_child_exit_file(
        lineage.attempt_dir;
        lineage.identity_args...,
        reservation_path = lineage.reservation_path,
        execution_root,
        expected_reservation_id =
            lineage.reservation.reservation_id,
    )
    observed_exit_code = ld1b1_int(exit.artifact["exit"]["exit_code"])
    observed_exit_code == exit_code || error(
        "published child-exit receipt has the wrong exit code")
    return (; publication, exit, exit_code = observed_exit_code)
end

function ld1b1_validate_canonical_controller_receipts(
        attempt_dir::AbstractString, identity, job, attempt::Int;
        execution_context = ld1b1_execution_context())
    execution_root = ld1b1_result_execution_root(
        joinpath(attempt_dir, "job_result.json"))
    expected_attempt_dir = ld1b1_attempt_dir(
        execution_root, job.job_id, attempt)
    normpath(attempt_dir) == normpath(expected_attempt_dir) || error(
        "controller receipts belong to the wrong attempt directory")
    lineage = ld1b1_reservation_lineage(
        execution_root, identity, job, attempt; execution_context)
    owner = LD1B1Recovery.ld1b_validate_canonical_attempt_owner_file(
        attempt_dir;
        lineage.identity_args...,
        reservation_path = lineage.reservation_path,
        execution_root,
        expected_reservation_id =
            lineage.reservation.reservation_id,
    )
    launch = LD1B1Recovery.ld1b_validate_child_launch_file(
        attempt_dir;
        lineage.identity_args...,
        reservation_path = lineage.reservation_path,
        execution_root,
        expected_reservation_id =
            lineage.reservation.reservation_id,
    )
    exit = LD1B1Recovery.ld1b_validate_child_exit_file(
        attempt_dir;
        lineage.identity_args...,
        reservation_path = lineage.reservation_path,
        execution_root,
        expected_reservation_id =
            lineage.reservation.reservation_id,
    )
    launch.owner.file_sha256 == owner.file_sha256 || error(
        "child-launch receipt does not reference the canonical owner")
    exit.launch.file_sha256 == launch.file_sha256 || error(
        "child-exit receipt does not reference the canonical launch")
    exit_code = ld1b1_int(exit.artifact["exit"]["exit_code"])
    return (;
        reservation = lineage.reservation,
        owner,
        launch,
        exit,
        exit_code,
        receipt_order = (:reservation, :owner, :launch, :exit),
    )
end

function ld1b1_validate_canonical_terminal_admission_receipts(
        attempt_dir::AbstractString, identity, job, attempt::Int;
        execution_context = ld1b1_execution_context())
    receipts = ld1b1_validate_canonical_controller_receipts(
        attempt_dir, identity, job, attempt; execution_context)
    receipts.exit_code == 0 || error(
        "canonical terminal admission requires child exit code 0")
    return receipts
end

function ld1b1_run_command(args::Vector{String}, log_path::AbstractString)
    mkpath(dirname(log_path))
    started_at = Dates.now()
    ok = false
    message = missing
    try
        ispath(log_path) && error("refusing to overwrite existing log: $log_path")
        open(log_path, "w") do io
            println(io, "command=", ld1b1_command_string(args))
            println(io, "started_at=", started_at)
            flush(io)
            run(pipeline(Cmd(args); stdout = io, stderr = io))
        end
        ok = true
    catch err
        message = portable_error_message(err)
    end
    finished_at = Dates.now()
    return (;
        ok,
        started_at = string(started_at),
        finished_at = string(finished_at),
        elapsed_ms = Dates.value(finished_at - started_at),
        error = message,
    )
end

function ld1b1_observed_process_rss_bytes(pid::Integer)
    ps = Sys.which("ps")
    ps === nothing && return missing
    text = try
        read(pipeline(
            Cmd([String(ps), "-o", "rss=", "-p", string(Int(pid))]);
            stderr = devnull,
        ), String)
    catch
        return missing
    end
    stripped = strip(text)
    isempty(stripped) && return missing
    value = tryparse(Int, first(split(stripped)))
    value === nothing && return missing
    value >= 0 || return missing
    return value * 1024
end

function ld1b1_observed_tree_bytes(root::AbstractString)
    (ispath(root) || islink(root)) || return 0
    isdir(root) && !islink(root) || error(
        "bounded resource root is not a regular directory")
    total = 0
    for (directory, directories, files) in walkdir(root; follow_symlinks = false)
        for name in directories
            path = joinpath(directory, name)
            islink(path) && error(
                "bounded resource tree contains a symbolic-link directory")
        end
        for name in files
            path = joinpath(directory, name)
            isfile(path) && !islink(path) || error(
                "bounded resource tree contains a non-regular file")
            metadata = stat(path)
            metadata.nlink == 1 || error(
                "bounded resource tree contains a hard-linked file")
            total += metadata.size
        end
    end
    return total
end

function ld1b1_terminate_bounded_process(process;
        grace_seconds::Real)
    term_sent = false
    kill_sent = false
    if !process_exited(process)
        try
            kill(process)
            term_sent = true
        catch
        end
    end
    if !process_exited(process)
        state = timedwait(
            () -> process_exited(process),
            Float64(grace_seconds);
            pollint = 0.05,
        )
        if state === :timed_out && !process_exited(process)
            try
                kill(process, Base.SIGKILL)
                kill_sent = true
            catch
            end
        end
    end
    try
        wait(process)
    catch
    end
    return (; term_sent, kill_sent)
end

function ld1b1_run_command_with_controller_receipts(
        args::Vector{String}, log_path::AbstractString, lineage, owner,
        execution_root::AbstractString;
        timeout_seconds = nothing,
        termination_grace_seconds::Real =
            LD1B1_BOUNDED_SMOKE_TERMINATION_GRACE_SECONDS,
        max_rss_bytes = nothing,
        max_archive_bytes = nothing,
        monitored_archive_root::AbstractString = execution_root,
        poll_seconds::Real = 0.5,
        rss_observer::Function = ld1b1_observed_process_rss_bytes)
    mkpath(dirname(log_path))
    ispath(log_path) && error("refusing to overwrite existing log: $log_path")
    started_at = Dates.now()
    process = nothing
    child_pid = missing
    launch_publication = nothing
    exit_publication = nothing
    exit_code = missing
    message = missing
    timed_out = false
    resource_limit_exceeded = false
    resource_limit_code = missing
    peak_rss_bytes = 0
    peak_archive_bytes = 0
    rss_monitor_available = true
    termination = (term_sent = false, kill_sent = false)
    try
        open(log_path, "w") do io
            println(io, "command=", ld1b1_command_string(args))
            println(io, "started_at=", started_at)
            flush(io)
            process = run(
                pipeline(Cmd(args); stdout = io, stderr = io);
                wait = false,
            )
            child_pid = getpid(process)
            launch_publication = ld1b1_publish_child_launch_create_new(
                lineage, owner, child_pid, execution_root)
            if timeout_seconds === nothing && max_rss_bytes === nothing &&
                    max_archive_bytes === nothing
                wait(process)
            else
                timeout_seconds isa Real && timeout_seconds > 0 || error(
                    "bounded command timeout must be positive")
                max_rss_bytes isa Integer && max_rss_bytes > 0 || error(
                    "bounded command RSS cap must be a positive integer")
                max_archive_bytes isa Integer && max_archive_bytes > 0 || error(
                    "bounded command archive cap must be a positive integer")
                started_monotonic = time()
                while !process_exited(process)
                    rss = rss_observer(child_pid)
                    if ismissing(rss)
                        if !process_exited(process)
                            rss_monitor_available = false
                            resource_limit_exceeded = true
                            resource_limit_code = :rss_monitor_unavailable
                        end
                    else
                        peak_rss_bytes = max(peak_rss_bytes, rss)
                        if rss > max_rss_bytes
                            resource_limit_exceeded = true
                            resource_limit_code = :rss_cap_exceeded
                        end
                    end
                    archive_bytes = ld1b1_observed_tree_bytes(
                        monitored_archive_root)
                    peak_archive_bytes = max(
                        peak_archive_bytes, archive_bytes)
                    if archive_bytes > max_archive_bytes
                        resource_limit_exceeded = true
                        resource_limit_code = :archive_cap_exceeded
                    end
                    if time() - started_monotonic >= timeout_seconds
                        timed_out = true
                        resource_limit_code = :wall_time_cap_exceeded
                    end
                    if timed_out || resource_limit_exceeded
                        termination = ld1b1_terminate_bounded_process(
                            process; grace_seconds = termination_grace_seconds)
                        break
                    end
                    sleep(Float64(poll_seconds))
                end
                if !process_exited(process)
                    wait(process)
                end
                final_archive_bytes = ld1b1_observed_tree_bytes(
                    monitored_archive_root)
                peak_archive_bytes = max(
                    peak_archive_bytes, final_archive_bytes)
                if final_archive_bytes > max_archive_bytes
                    resource_limit_exceeded = true
                    resource_limit_code = :archive_cap_exceeded
                end
            end
            exit_code = process.exitcode
            exit_publication = ld1b1_publish_child_exit_create_new(
                lineage, launch_publication.launch, exit_code,
                execution_root)
            println(io, "finished_at=", Dates.now())
            println(io, "exit_code=", exit_code)
            flush(io)
        end
        if timed_out
            message = "single-job runner exceeded the bounded wall-time cap"
        elseif resource_limit_exceeded
            message = "single-job runner exceeded or could not verify resource cap: " *
                string(resource_limit_code)
        elseif exit_code != 0
            message = "single-job runner exited with code $exit_code"
        end
    catch err
        message = portable_error_message(err)
        if process !== nothing && !process_exited(process)
            try
                wait(process)
            catch
            end
        end
    end
    finished_at = Dates.now()
    return (;
        ok = !ismissing(exit_code) && exit_code == 0 &&
            exit_publication !== nothing && !timed_out &&
            !resource_limit_exceeded,
        subprocess_started = process !== nothing,
        child_pid,
        exit_code,
        started_at = string(started_at),
        finished_at = string(finished_at),
        elapsed_ms = Dates.value(finished_at - started_at),
        error = message,
        timed_out,
        resource_limit_exceeded,
        resource_limit_code,
        peak_rss_bytes,
        peak_archive_bytes,
        rss_monitor_available,
        termination,
        launch_publication,
        exit_publication,
        receipt_order = exit_publication === nothing ?
            (:reservation, :attempt_directory, :owner,
                :launch_or_exit_incomplete) :
            (:reservation, :attempt_directory, :owner, :launch, :exit),
    )
end

function ld1b1_execute_selected(selection, checked, specs, execution_root,
        checkpoint_path, options)
    readiness = checked.identity.readiness
    readiness.operational_execution_authorized || error(
        "LD1b1 operational execution is blocked before attempt creation: " *
        join(string.(readiness.blockers), ", "))
    isfile(options.runner) || error(
        "single-job runner is not materialized: $(options.runner)")
    !islink(options.runner) || error(
        "single-job runner must not be a symbolic link")
    normpath(options.runner) == normpath(LD1B1_DEFAULT_JOB_RUNNER) ||
        error("execute modes require the canonical LD1b1 single-job runner")
    runner_source_sha256 = ld1b1_file_sha256(options.runner)
    runner_source_sha256 ==
        checked.identity.execution_source_identity.job_runner_source_sha256 ||
        error("single-job runner differs from the execution-plan identity")
    LD1B1AttemptArchive.ld1b_attempt_archive_source_sha256() ==
        checked.identity.execution_source_identity.
            attempt_archive_source_sha256 || error(
        "attempt-archive helper differs from the execution-plan identity")
    ld1b1_file_sha256(joinpath(
        @__DIR__,
        "local_dependence_pilot_recovery.jl",
    )) == checked.identity.execution_source_identity.
        local_dependence_pilot_recovery_source_sha256 || error(
        "interruption-recovery helper differs from the execution-plan identity")
    ld1b1_file_sha256(joinpath(
        @__DIR__,
        "local_dependence_pilot_calibration_semantics.jl",
    )) == checked.identity.execution_source_identity.
        local_dependence_pilot_calibration_semantics_source_sha256 || error(
        "calibration-semantics helper differs from the execution-plan identity")
    run_id = string(
        Dates.format(Dates.now(), dateformat"yyyymmdd_HHMMSS_sss"),
        "_pid", getpid(),
    )
    run_root = joinpath(execution_root, "batch_runs", run_id)
    rows = NamedTuple[]
    stopped = false
    current_scan = ld1b1_scan_attempts(
        specs,
        checked.identity,
        execution_root;
        calibration_semantic_context =
            checked.calibration_semantic_context,
    )
    state_by_job = Dict(row.job_id => row for row in current_scan.job_state_rows)
    for job in selection.selected
        if stopped
            push!(rows, (;
                job_id = job.job_id,
                attempt = options.attempt,
                action_status = :skipped_after_failure,
                command = missing,
                result_path = ld1b1_record_path(ld1b1_result_path(
                    execution_root, job.job_id, options.attempt)),
                log_path = missing,
                subprocess_started = false,
                error = missing,
            ))
            continue
        end
        current_state = state_by_job[job.job_id]
        if options.resume && options.mode === :execute_primary &&
                current_state.primary_valid
            push!(rows, (;
                job_id = job.job_id,
                attempt = options.attempt,
                action_status = :skipped_verified_terminal_primary,
                command = missing,
                result_path = ld1b1_record_path(ld1b1_result_path(
                    execution_root, job.job_id, 1)),
                log_path = missing,
                subprocess_started = false,
                error = missing,
            ))
            continue
        end
        target_dir = ld1b1_require_attempt_available(
            job,
            checked.identity,
            execution_root,
            options;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        reservation_setup = ld1b1_publish_attempt_reservation_create_new(
            execution_root,
            checked.identity,
            job,
            options.attempt,
            run_id,
        )
        mkpath(dirname(target_dir))
        mkdir(target_dir)
        ld1b1_require_realpath_containment(target_dir, execution_root)
        owner_setup = ld1b1_publish_canonical_owner_create_new(
            reservation_setup.lineage, execution_root)
        command = ld1b1_job_command(
            job, checked.identity, execution_root, options;
            runner_source_sha256,
            controller_readiness_authorized = true,
        )
        ld1b1_file_sha256(options.runner) == runner_source_sha256 ||
            error("single-job runner changed before invocation")
        log_path = joinpath(run_root, "logs", string(
            job.job_id, "__attempt_",
            lpad(string(options.attempt), 3, '0'), ".log"))
        result = ld1b1_run_command_with_controller_receipts(
            command.args,
            log_path,
            reservation_setup.lineage,
            owner_setup.owner,
            execution_root,
        )
        ld1b1_file_sha256(options.runner) == runner_source_sha256 ||
            error("single-job runner changed during invocation")
        action_status = :runner_failed
        error_message = result.error
        if result.ok
            try
                receipts = ld1b1_validate_canonical_controller_receipts(
                    target_dir,
                    checked.identity,
                    job,
                    options.attempt,
                )
                receipts.exit_code == 0 || error(
                    "successful runner admission has a nonzero exit receipt")
                ld1b1_publish_completed_attempt_seal(
                    command.result_path,
                    checked.identity,
                    job,
                    options.attempt;
                    calibration_semantic_context =
                        checked.calibration_semantic_context,
                )
                action_status = :terminal_result_verified
            catch err
                action_status = :invalid_or_missing_terminal_result
                error_message = portable_error_message(err)
            end
        end
        push!(rows, (;
            job_id = job.job_id,
            attempt = options.attempt,
            action_status,
            command = ld1b1_portable_command_string(command.args),
            result_path = ld1b1_record_path(command.result_path),
            log_path = ld1b1_record_path(log_path),
            reservation_path = ld1b1_record_path(
                reservation_setup.lineage.reservation_path),
            owner_receipt_path = ld1b1_record_path(joinpath(
                target_dir, LD1B1Recovery.LD1B_ATTEMPT_OWNER_FILENAME)),
            launch_receipt_path = ld1b1_record_path(joinpath(
                target_dir, LD1B1Recovery.LD1B_CHILD_LAUNCH_FILENAME)),
            exit_receipt_path = ld1b1_record_path(joinpath(
                target_dir, LD1B1Recovery.LD1B_CHILD_EXIT_FILENAME)),
            controller_readiness_authorized =
                command.controller_readiness_authorized,
            receipt_order = result.receipt_order,
            child_pid = result.child_pid,
            child_exit_code = result.exit_code,
            subprocess_started = result.subprocess_started,
            error = error_message,
        ))
        scan = ld1b1_scan_attempts(
            specs,
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        state_by_job = Dict(row.job_id => row for row in scan.job_state_rows)
        if options.write_checkpoint
            checkpoint = ld1b1_checkpoint_artifact(checked.identity, scan)
            ld1b1_atomic_write_artifact(
                checkpoint_path, checkpoint; overwrite = true)
        end
        if action_status !== :terminal_result_verified && options.stop_on_error
            stopped = true
        end
    end
    return Tuple(rows)
end

function ld1b1_bounded_smoke_official_state(checked, specs)
    official_execution_root = ld1b1_execution_root(
        LD1B1_DEFAULT_ATTEMPT_ROOT, checked.identity.plan_id)
    scan = ld1b1_scan_attempts(
        specs,
        checked.identity,
        official_execution_root;
        calibration_semantic_context = checked.calibration_semantic_context,
    )
    summary = scan.summary
    summary.n_primary_attempts_observed == 0 || error(
        "bounded smoke requires an untouched official primary-attempt tree")
    summary.n_retry_attempts_observed == 0 || error(
        "bounded smoke requires an untouched official remediation tree")
    summary.n_partial_attempts == 0 || error(
        "bounded smoke requires no partial official attempts")
    summary.n_retired_attempts == 0 || error(
        "bounded smoke requires no retired official attempts")
    summary.n_missing_primary_outcomes == LD1B1_EXPECTED_JOBS || error(
        "bounded smoke official denominator state is not 0/660")
    return (;
        execution_root = official_execution_root,
        state_digest = scan.state_digest,
        observed_primary_result_set_sha256 =
            scan.observed_primary_result_set_sha256,
        observed_primary_disposition_set_sha256 =
            scan.observed_primary_disposition_set_sha256,
        n_primary_attempts_observed = summary.n_primary_attempts_observed,
        n_retry_attempts_observed = summary.n_retry_attempts_observed,
        n_partial_attempts = summary.n_partial_attempts,
        n_retired_attempts = summary.n_retired_attempts,
        scientific_pilot_outcomes = 0,
        scientific_pilot_denominator = LD1B1_EXPECTED_JOBS,
    )
end

function ld1b1_bounded_smoke_receipt(checked, smoke_identity, job,
        smoke_root::AbstractString, authorization, command, run_result,
        controller_receipts, terminal_validation, official_before,
        official_after, log_path::AbstractString)
    context = ld1b1_execution_context(:bounded_smoke)
    execution_root = ld1b1_bounded_smoke_execution_root(
        smoke_root, smoke_identity.plan_id)
    attempt_dir = ld1b1_attempt_dir(execution_root, job.job_id, 1)
    result_path = ld1b1_result_path(execution_root, job.job_id, 1)
    inventory = LD1B1AttemptArchive.ld1b_attempt_inventory(
        attempt_dir; exclude = ())
    inventory_sha256 = ld1b1_canonical_sha256(inventory)
    total_file_bytes = sum(row.bytes for row in inventory
        if row.kind === :file)
    log_snapshot = ld1b1_regular_file_snapshot(
        log_path, dirname(log_path), "bounded-smoke worker log")
    receipt_rows = (
        (role = :reservation,
            path = ld1b1_record_path(ld1b1_attempt_reservation_path(
                execution_root, job.job_id, 1)),
            sha256 = controller_receipts.reservation.file_sha256),
        (role = :owner,
            path = ld1b1_record_path(joinpath(
                attempt_dir, LD1B1Recovery.LD1B_ATTEMPT_OWNER_FILENAME)),
            sha256 = controller_receipts.owner.file_sha256),
        (role = :launch,
            path = ld1b1_record_path(joinpath(
                attempt_dir, LD1B1Recovery.LD1B_CHILD_LAUNCH_FILENAME)),
            sha256 = controller_receipts.launch.file_sha256),
        (role = :exit,
            path = ld1b1_record_path(joinpath(
                attempt_dir, LD1B1Recovery.LD1B_CHILD_EXIT_FILENAME)),
            sha256 = controller_receipts.exit.file_sha256),
    )
    base = (;
        schema = LD1B1_BOUNDED_SMOKE_RECEIPT_SCHEMA,
        object = :local_dependence_pilot_bounded_canonical_smoke_receipt,
        package = (;
            name = :BayesianMGMFRM,
            version = ld1b1_project_version(),
        ),
        family = :mfrm,
        scope = :ld1b1_bounded_canonical_smoke_nonpilot,
        status = :bounded_canonical_smoke_passed,
        execution_context = context,
        protocol_artifact = (;
            path = ld1b1_record_path(checked.calibration_semantic_context.
                protocol_path),
            schema = LD1B1_PROTOCOL_SCHEMA,
            file_sha256 = checked.identity.protocol_file_sha256,
            content_hash = checked.identity.protocol_content_hash,
        ),
        parent_plan_identity = ld1b1_result_plan_identity(checked.identity),
        smoke_plan_identity = ld1b1_result_plan_identity(smoke_identity),
        canonical_executor_source_pin = (;
            schema = LD1B1_CANONICAL_EXECUTOR_SOURCE_PIN_SCHEMA,
            pin_id = checked.identity.canonical_executor_source_pin_id,
            source_rows = checked.identity.
                canonical_executor_source_pin_source_rows,
        ),
        smoke_contract = smoke_identity.bounded_smoke_contract,
        authorization = (;
            path = ld1b1_record_path(authorization.path),
            file_sha256 = authorization.file_sha256,
            content_hash = authorization.content_hash,
        ),
        execution = (;
            command = ld1b1_portable_command_string(command.args),
            command_sha256 = ld1b1_canonical_sha256(
                ld1b1_portable_command_args(command.args)),
            worker_mode = command.worker_mode,
            subprocesses_started = 1,
            child_pid = run_result.child_pid,
            exit_code = run_result.exit_code,
            elapsed_ms = run_result.elapsed_ms,
            timed_out = run_result.timed_out,
            resource_limit_exceeded = run_result.resource_limit_exceeded,
            resource_limit_code = run_result.resource_limit_code,
            peak_rss_bytes = run_result.peak_rss_bytes,
            peak_archive_bytes = run_result.peak_archive_bytes,
            rss_monitor_available = run_result.rss_monitor_available,
            termination = run_result.termination,
            log = (;
                path = ld1b1_record_path(log_path),
                bytes = log_snapshot.nbytes,
                sha256 = log_snapshot.sha256,
            ),
            controller_receipts = receipt_rows,
            receipt_order = run_result.receipt_order,
        ),
        raw_evidence = (;
            attempt_directory = ld1b1_record_path(attempt_dir),
            result_path = ld1b1_record_path(result_path),
            result_file_sha256 = terminal_validation.result_sha256,
            result_content_hash = terminal_validation.content_hash,
            evidence_roles = terminal_validation.evidence_roles,
            evidence_manifest_sha256 =
                terminal_validation.evidence_manifest_sha256,
            inventory,
            inventory_sha256,
            total_file_bytes,
        ),
        completion_seal = (;
            path = ld1b1_record_path(ld1b1_seal_path(
                execution_root, job.job_id, 1)),
            file_sha256 = terminal_validation.seal_file_sha256,
            content_hash = terminal_validation.seal_content_hash,
            attempt_inventory_sha256 =
                terminal_validation.attempt_inventory_sha256,
            helper_attempt_inventory_sha256 =
                terminal_validation.helper_attempt_inventory_sha256,
            terminal_status = terminal_validation.terminal_status,
            terminal_outcome_code =
                terminal_validation.terminal_outcome_code,
        ),
        official_pilot_state = (;
            before = merge(official_before, (;
                execution_root =
                    ld1b1_record_path(official_before.execution_root),
            )),
            after = merge(official_after, (;
                execution_root =
                    ld1b1_record_path(official_after.execution_root),
            )),
            unchanged = official_before == official_after,
        ),
        checks = (;
            exact_allowlisted_job = true,
            frozen_sampler_controls_used = true,
            frozen_quality_contract_used = true,
            exact_seeds_used = true,
            one_subprocess_started = true,
            timeout_cap_enforced = true,
            rss_cap_enforced = true,
            archive_cap_enforced = true,
            child_exit_zero = controller_receipts.exit_code == 0,
            terminal_status_completed =
                terminal_validation.terminal_status === :completed,
            canonical_controller_receipts_verified =
                terminal_validation.canonical_controller_receipts_verified,
            completed_attempt_seal_verified = true,
            execution_source_unchanged = true,
            official_pilot_state_unchanged =
                official_before == official_after,
            official_pilot_denominator_unchanged = true,
            smoke_artifacts_scanner_ineligible = true,
        ),
        evidence_boundary = (;
            response_data_generated = true,
            model_fit_run = true,
            mcmc_run = true,
            bounded_canonical_smoke_passed = true,
            counts_toward_scientific_denominator = false,
            pilot_execution_started = false,
            pilot_execution_completed = false,
            scientific_pilot_outcomes = 0,
            scientific_pilot_denominator = LD1B1_EXPECTED_JOBS,
            independent_recovery_readiness_review_passed = false,
            operational_execution_authorized = false,
            evaluation_profile_frozen = false,
            repeated_calibration_completed = false,
            pairwise_power_available = false,
            diagnostic_decision_labels_available = false,
            mechanism_interpretation_eligible = false,
            tracked_release_lineage_verified = false,
        ),
        summary = (;
            passed = true,
            assessment = :bounded_canonical_smoke_passed,
            integration_gate = 7,
            integration_gates_complete = 7,
            integration_gates_total = 9,
            integration_progress_percent = 100 * 7 / 9,
            next_gate = :independent_pinned_recovery_readiness_review,
            operational_execution_authorized = false,
            scientific_pilot_outcomes = 0,
            scientific_pilot_denominator = LD1B1_EXPECTED_JOBS,
        ),
    )
    return ld1b1_with_content_hash(base)
end

function ld1b1_validate_bounded_smoke_receipt(path::AbstractString, checked;
        smoke_root::AbstractString = LD1B1_DEFAULT_BOUNDED_SMOKE_ROOT)
    isfile(path) && !islink(path) || error(
        "bounded-smoke receipt is not a regular file")
    receipt = JSON3.read(read(path, String))
    ld1b1_require_only_keys(receipt, (
        :schema,
        :object,
        :package,
        :family,
        :scope,
        :status,
        :execution_context,
        :protocol_artifact,
        :parent_plan_identity,
        :smoke_plan_identity,
        :canonical_executor_source_pin,
        :smoke_contract,
        :authorization,
        :execution,
        :raw_evidence,
        :completion_seal,
        :official_pilot_state,
        :checks,
        :evidence_boundary,
        :summary,
        :content_hash,
    ), "bounded-smoke receipt")
    ld1b1_string(receipt[:schema]) ==
        LD1B1_BOUNDED_SMOKE_RECEIPT_SCHEMA || error(
        "unexpected bounded-smoke receipt schema")
    ld1b1_symbol(receipt[:object]) ===
        :local_dependence_pilot_bounded_canonical_smoke_receipt || error(
        "unexpected bounded-smoke receipt object")
    ld1b1_string(receipt[:family]) == "mfrm" || error(
        "unexpected bounded-smoke receipt family")
    ld1b1_symbol(receipt[:scope]) ===
        :ld1b1_bounded_canonical_smoke_nonpilot || error(
        "unexpected bounded-smoke receipt scope")
    ld1b1_symbol(receipt[:status]) ===
        :bounded_canonical_smoke_passed || error(
        "bounded-smoke receipt does not record a pass")
    content_hash = ld1b1_verify_content_hash(
        receipt; label = "bounded-smoke receipt")
    context = ld1b1_validate_execution_context(
        receipt[:execution_context]; expected_scope = :bounded_smoke)

    package = receipt[:package]
    ld1b1_require_only_keys(package, (:name, :version),
        "bounded-smoke package")
    ld1b1_symbol(package[:name]) === :BayesianMGMFRM &&
        ld1b1_string(package[:version]) == ld1b1_project_version() || error(
        "bounded-smoke package identity mismatch")

    specs = ld1b1_job_specs(checked)
    job = ld1b1_bounded_smoke_job(specs)
    smoke = ld1b1_bounded_smoke_identity(checked.identity, job)
    ld1b1_canonical_sha256(ld1b1_json_native(
        receipt[:parent_plan_identity])) == ld1b1_canonical_sha256(
        ld1b1_result_plan_identity(checked.identity)) || error(
        "bounded-smoke parent plan identity mismatch")
    ld1b1_canonical_sha256(ld1b1_json_native(
        receipt[:smoke_plan_identity])) == ld1b1_canonical_sha256(
        ld1b1_result_plan_identity(smoke.identity)) || error(
        "bounded-smoke plan identity mismatch")
    ld1b1_canonical_sha256(ld1b1_json_native(
        receipt[:smoke_contract])) == ld1b1_canonical_sha256(
        smoke.contract) || error("bounded-smoke contract mismatch")

    protocol = receipt[:protocol_artifact]
    ld1b1_require_only_keys(protocol,
        (:path, :schema, :file_sha256, :content_hash),
        "bounded-smoke protocol binding")
    ld1b1_string(protocol[:path]) == ld1b1_record_path(
        checked.calibration_semantic_context.protocol_path) &&
        ld1b1_string(protocol[:schema]) == LD1B1_PROTOCOL_SCHEMA &&
        ld1b1_string(protocol[:file_sha256]) ==
            checked.identity.protocol_file_sha256 &&
        ld1b1_string(protocol[:content_hash]) ==
            checked.identity.protocol_content_hash || error(
        "bounded-smoke protocol binding mismatch")

    source_pin = receipt[:canonical_executor_source_pin]
    ld1b1_require_only_keys(source_pin, (:schema, :pin_id, :source_rows),
        "bounded-smoke source pin")
    ld1b1_string(source_pin[:schema]) ==
        LD1B1_CANONICAL_EXECUTOR_SOURCE_PIN_SCHEMA &&
        ld1b1_string(source_pin[:pin_id]) ==
            checked.identity.canonical_executor_source_pin_id &&
        ld1b1_canonical_sha256(ld1b1_json_native(
            source_pin[:source_rows])) == ld1b1_canonical_sha256(
            checked.identity.canonical_executor_source_pin_source_rows) ||
        error("bounded-smoke source pin mismatch")

    authorization_path = ld1b1_bounded_smoke_authorization_path(
        smoke_root, smoke.smoke_plan_id)
    authorization = ld1b1_validate_bounded_smoke_authorization(
        authorization_path,
        checked.identity,
        smoke.identity,
        job,
        smoke_root,
    )
    authorization_record = receipt[:authorization]
    ld1b1_require_only_keys(authorization_record,
        (:path, :file_sha256, :content_hash),
        "bounded-smoke authorization binding")
    ld1b1_string(authorization_record[:path]) ==
        ld1b1_record_path(authorization_path) &&
        ld1b1_string(authorization_record[:file_sha256]) ==
            authorization.file_sha256 &&
        ld1b1_string(authorization_record[:content_hash]) ==
            authorization.content_hash || error(
        "bounded-smoke authorization binding mismatch")

    execution_root = ld1b1_bounded_smoke_execution_root(
        smoke_root, smoke.smoke_plan_id)
    attempt_dir = ld1b1_attempt_dir(execution_root, job.job_id, 1)
    result_path = ld1b1_result_path(execution_root, job.job_id, 1)
    terminal = ld1b1_validate_completed_attempt(
        result_path,
        smoke.identity,
        job,
        1;
        calibration_semantic_context = checked.calibration_semantic_context,
        execution_context = context,
    )
    terminal.terminal_status === :completed || error(
        "bounded-smoke terminal status is not completed")
    controller_receipts = ld1b1_validate_canonical_controller_receipts(
        attempt_dir,
        smoke.identity,
        job,
        1;
        execution_context = context,
    )
    controller_receipts.exit_code == 0 || error(
        "bounded-smoke controller exit receipt is nonzero")

    execution = receipt[:execution]
    ld1b1_require_only_keys(execution, (
        :command,
        :command_sha256,
        :worker_mode,
        :subprocesses_started,
        :child_pid,
        :exit_code,
        :elapsed_ms,
        :timed_out,
        :resource_limit_exceeded,
        :resource_limit_code,
        :peak_rss_bytes,
        :peak_archive_bytes,
        :rss_monitor_available,
        :termination,
        :log,
        :controller_receipts,
        :receipt_order,
    ), "bounded-smoke execution record")
    command_options = (;
        attempt = 1,
        mode = :bounded_smoke,
        runner = LD1B1_DEFAULT_JOB_RUNNER,
        protocol = LD1B1_DEFAULT_PROTOCOL,
    )
    expected_command = ld1b1_job_command(
        job,
        smoke.identity,
        execution_root,
        command_options;
        runner_source_sha256 = checked.identity.execution_source_identity.
            job_runner_source_sha256,
        bounded_smoke_authorization = authorization_path,
    )
    portable_args = ld1b1_portable_command_args(expected_command.args)
    ld1b1_string(execution[:command]) ==
        ld1b1_portable_command_string(expected_command.args) &&
        ld1b1_string(execution[:command_sha256]) ==
            ld1b1_canonical_sha256(portable_args) &&
        ld1b1_symbol(execution[:worker_mode]) === :bounded_smoke || error(
        "bounded-smoke command identity mismatch")
    ld1b1_int(execution[:subprocesses_started]) == 1 &&
        ld1b1_int(execution[:child_pid]) > 0 &&
        ld1b1_int(execution[:exit_code]) == 0 &&
        ld1b1_int(execution[:elapsed_ms]) >= 0 &&
        !ld1b1_bool(execution[:timed_out]) &&
        !ld1b1_bool(execution[:resource_limit_exceeded]) &&
        (execution[:resource_limit_code] === nothing ||
            ismissing(execution[:resource_limit_code])) &&
        ld1b1_int(execution[:peak_rss_bytes]) <=
            LD1B1_BOUNDED_SMOKE_MAX_RSS_BYTES &&
        ld1b1_int(execution[:peak_archive_bytes]) <=
            LD1B1_BOUNDED_SMOKE_MAX_ARCHIVE_BYTES &&
        ld1b1_bool(execution[:rss_monitor_available]) || error(
        "bounded-smoke resource/exit record did not pass")
    current_archive_bytes = ld1b1_observed_tree_bytes(
        dirname(dirname(execution_root)))
    current_archive_bytes <= LD1B1_BOUNDED_SMOKE_MAX_ARCHIVE_BYTES &&
        ld1b1_int(execution[:peak_archive_bytes]) >= current_archive_bytes ||
        error("bounded-smoke sealed archive exceeds its recorded cap")
    termination = execution[:termination]
    ld1b1_require_only_keys(termination, (:term_sent, :kill_sent),
        "bounded-smoke termination record")
    !ld1b1_bool(termination[:term_sent]) &&
        !ld1b1_bool(termination[:kill_sent]) || error(
        "bounded-smoke required forced termination")

    log_path = joinpath(dirname(dirname(execution_root)),
        "logs", "bounded_smoke_worker.log")
    log = execution[:log]
    ld1b1_require_only_keys(log, (:path, :bytes, :sha256),
        "bounded-smoke log binding")
    log_snapshot = ld1b1_regular_file_snapshot(
        log_path, dirname(log_path), "bounded-smoke log")
    ld1b1_string(log[:path]) == ld1b1_record_path(log_path) &&
        ld1b1_int(log[:bytes]) == log_snapshot.nbytes &&
        ld1b1_string(log[:sha256]) == log_snapshot.sha256 || error(
        "bounded-smoke log binding mismatch")

    expected_receipt_rows = (
        (role = :reservation,
            path = ld1b1_record_path(ld1b1_attempt_reservation_path(
                execution_root, job.job_id, 1)),
            sha256 = controller_receipts.reservation.file_sha256),
        (role = :owner,
            path = ld1b1_record_path(joinpath(
                attempt_dir, LD1B1Recovery.LD1B_ATTEMPT_OWNER_FILENAME)),
            sha256 = controller_receipts.owner.file_sha256),
        (role = :launch,
            path = ld1b1_record_path(joinpath(
                attempt_dir, LD1B1Recovery.LD1B_CHILD_LAUNCH_FILENAME)),
            sha256 = controller_receipts.launch.file_sha256),
        (role = :exit,
            path = ld1b1_record_path(joinpath(
                attempt_dir, LD1B1Recovery.LD1B_CHILD_EXIT_FILENAME)),
            sha256 = controller_receipts.exit.file_sha256),
    )
    ld1b1_canonical_sha256(ld1b1_json_native(
        execution[:controller_receipts])) == ld1b1_canonical_sha256(
        expected_receipt_rows) || error(
        "bounded-smoke controller receipt binding mismatch")
    Tuple(ld1b1_symbol(value) for value in execution[:receipt_order]) ==
        (:reservation, :attempt_directory, :owner, :launch, :exit) || error(
        "bounded-smoke receipt order mismatch")

    raw = receipt[:raw_evidence]
    ld1b1_require_only_keys(raw, (
        :attempt_directory,
        :result_path,
        :result_file_sha256,
        :result_content_hash,
        :evidence_roles,
        :evidence_manifest_sha256,
        :inventory,
        :inventory_sha256,
        :total_file_bytes,
    ), "bounded-smoke raw evidence")
    inventory = LD1B1AttemptArchive.ld1b_attempt_inventory(
        attempt_dir; exclude = ())
    ld1b1_string(raw[:attempt_directory]) ==
        ld1b1_record_path(attempt_dir) &&
        ld1b1_string(raw[:result_path]) == ld1b1_record_path(result_path) &&
        ld1b1_string(raw[:result_file_sha256]) == terminal.result_sha256 &&
        ld1b1_string(raw[:result_content_hash]) == terminal.content_hash &&
        Tuple(ld1b1_symbol(value) for value in raw[:evidence_roles]) ==
            terminal.evidence_roles &&
        ld1b1_string(raw[:evidence_manifest_sha256]) ==
            terminal.evidence_manifest_sha256 &&
        ld1b1_canonical_sha256(ld1b1_json_native(raw[:inventory])) ==
            ld1b1_canonical_sha256(inventory) &&
        ld1b1_string(raw[:inventory_sha256]) ==
            ld1b1_canonical_sha256(inventory) &&
        ld1b1_int(raw[:total_file_bytes]) == sum(
            row.bytes for row in inventory if row.kind === :file) || error(
        "bounded-smoke raw evidence binding mismatch")

    seal = receipt[:completion_seal]
    ld1b1_require_only_keys(seal, (
        :path,
        :file_sha256,
        :content_hash,
        :attempt_inventory_sha256,
        :helper_attempt_inventory_sha256,
        :terminal_status,
        :terminal_outcome_code,
    ), "bounded-smoke completion seal")
    ld1b1_string(seal[:path]) == ld1b1_record_path(ld1b1_seal_path(
        execution_root, job.job_id, 1)) &&
        ld1b1_string(seal[:file_sha256]) == terminal.seal_file_sha256 &&
        ld1b1_string(seal[:content_hash]) == terminal.seal_content_hash &&
        ld1b1_string(seal[:attempt_inventory_sha256]) ==
            terminal.attempt_inventory_sha256 &&
        ld1b1_string(seal[:helper_attempt_inventory_sha256]) ==
            terminal.helper_attempt_inventory_sha256 &&
        ld1b1_symbol(seal[:terminal_status]) === :completed &&
        ld1b1_symbol(seal[:terminal_outcome_code]) === :completed || error(
        "bounded-smoke completion-seal binding mismatch")

    official = receipt[:official_pilot_state]
    ld1b1_require_only_keys(official, (:before, :after, :unchanged),
        "bounded-smoke official pilot state")
    current_official = ld1b1_bounded_smoke_official_state(checked, specs)
    expected_official = merge(current_official, (;
        execution_root = ld1b1_record_path(current_official.execution_root),
    ))
    for field in (:before, :after)
        ld1b1_canonical_sha256(ld1b1_json_native(official[field])) ==
            ld1b1_canonical_sha256(expected_official) || error(
            "bounded-smoke official pilot state mismatch: $field")
    end
    ld1b1_bool(official[:unchanged]) || error(
        "bounded-smoke official pilot state changed")

    checks = receipt[:checks]
    check_fields = (
        :exact_allowlisted_job,
        :frozen_sampler_controls_used,
        :frozen_quality_contract_used,
        :exact_seeds_used,
        :one_subprocess_started,
        :timeout_cap_enforced,
        :rss_cap_enforced,
        :archive_cap_enforced,
        :child_exit_zero,
        :terminal_status_completed,
        :canonical_controller_receipts_verified,
        :completed_attempt_seal_verified,
        :execution_source_unchanged,
        :official_pilot_state_unchanged,
        :official_pilot_denominator_unchanged,
        :smoke_artifacts_scanner_ineligible,
    )
    ld1b1_require_only_keys(checks, check_fields,
        "bounded-smoke checks")
    all(field -> ld1b1_bool(checks[field]), check_fields) || error(
        "bounded-smoke receipt contains a failed check")

    boundary = receipt[:evidence_boundary]
    boundary_fields = (
        :response_data_generated,
        :model_fit_run,
        :mcmc_run,
        :bounded_canonical_smoke_passed,
        :counts_toward_scientific_denominator,
        :pilot_execution_started,
        :pilot_execution_completed,
        :scientific_pilot_outcomes,
        :scientific_pilot_denominator,
        :independent_recovery_readiness_review_passed,
        :operational_execution_authorized,
        :evaluation_profile_frozen,
        :repeated_calibration_completed,
        :pairwise_power_available,
        :diagnostic_decision_labels_available,
        :mechanism_interpretation_eligible,
        :tracked_release_lineage_verified,
    )
    ld1b1_require_only_keys(boundary, boundary_fields,
        "bounded-smoke evidence boundary")
    for field in (
            :response_data_generated,
            :model_fit_run,
            :mcmc_run,
            :bounded_canonical_smoke_passed,
        )
        ld1b1_bool(boundary[field]) || error(
            "bounded-smoke evidence boundary lacks $field")
    end
    for field in setdiff(collect(boundary_fields), [
            :response_data_generated,
            :model_fit_run,
            :mcmc_run,
            :bounded_canonical_smoke_passed,
            :scientific_pilot_outcomes,
            :scientific_pilot_denominator,
        ])
        !ld1b1_bool(boundary[field]) || error(
            "bounded-smoke evidence boundary exceeds scope: $field")
    end
    ld1b1_int(boundary[:scientific_pilot_outcomes]) == 0 &&
        ld1b1_int(boundary[:scientific_pilot_denominator]) ==
            LD1B1_EXPECTED_JOBS || error(
        "bounded-smoke scientific denominator boundary mismatch")

    summary = receipt[:summary]
    ld1b1_require_only_keys(summary, (
        :passed,
        :assessment,
        :integration_gate,
        :integration_gates_complete,
        :integration_gates_total,
        :integration_progress_percent,
        :next_gate,
        :operational_execution_authorized,
        :scientific_pilot_outcomes,
        :scientific_pilot_denominator,
    ), "bounded-smoke summary")
    ld1b1_bool(summary[:passed]) &&
        ld1b1_symbol(summary[:assessment]) ===
            :bounded_canonical_smoke_passed &&
        ld1b1_int(summary[:integration_gate]) == 7 &&
        ld1b1_int(summary[:integration_gates_complete]) == 7 &&
        ld1b1_int(summary[:integration_gates_total]) == 9 &&
        !ld1b1_bool(summary[:operational_execution_authorized]) &&
        ld1b1_int(summary[:scientific_pilot_outcomes]) == 0 &&
        ld1b1_int(summary[:scientific_pilot_denominator]) ==
            LD1B1_EXPECTED_JOBS || error(
        "bounded-smoke summary mismatch")

    return (;
        valid = true,
        bounded_canonical_smoke_passed = true,
        content_hash,
        file_sha256 = ld1b1_file_sha256(path),
        smoke_plan_id = smoke.smoke_plan_id,
        terminal_status = terminal.terminal_status,
        scientific_contribution = 0,
        operational_execution_authorized = false,
    )
end

function ld1b1_independent_recovery_readiness_review_artifact(
        checked, smoke_validation;
        reviewer_id::AbstractString,
        reviewed_at_utc::AbstractString)
    reviewer = strip(String(reviewer_id))
    isempty(reviewer) && error("independent reviewer id must not be empty")
    reviewed_at = strip(String(reviewed_at_utc))
    occursin(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$",
        reviewed_at) || error(
        "independent review time must use canonical UTC format")
    smoke_validation.valid &&
        smoke_validation.bounded_canonical_smoke_passed || error(
        "independent review requires a valid bounded-smoke receipt")
    smoke_receipt_sha256 = ld1b1_file_sha256(
        LD1B1_DEFAULT_BOUNDED_SMOKE_RECEIPT)
    findings = (
        (component = :pinned_worker_and_controller_source,
            assessment = :passed),
        (component = :reservation_owner_launch_exit_lineage,
            assessment = :passed),
        (component = :precommit_and_launched_interruption_recovery,
            assessment = :passed),
        (component = :status_specific_result_and_evidence_semantics,
            assessment = :passed),
        (component = :completed_attempt_seal_and_inventory,
            assessment = :passed),
        (component = :bounded_timeout_rss_and_archive_limits,
            assessment = :passed),
        (component = :bounded_smoke_raw_evidence_and_seed_replay,
            assessment = :passed),
        (component = :official_pilot_denominator_isolation,
            assessment = :passed),
    )
    reviewed_material = (;
        parent_plan_id = checked.identity.plan_id,
        canonical_executor_source_pin_id =
            checked.identity.canonical_executor_source_pin_id,
        canonical_executor_source_pin_source_rows =
            checked.identity.canonical_executor_source_pin_source_rows,
        bounded_smoke_receipt = (;
            path = ld1b1_record_path(
                LD1B1_DEFAULT_BOUNDED_SMOKE_RECEIPT),
            file_sha256 = smoke_receipt_sha256,
            content_hash = smoke_validation.content_hash,
            smoke_plan_id = smoke_validation.smoke_plan_id,
        ),
        findings,
        decision = :accept_pinned_worker_recovery_readiness,
    )
    attestation_material = (;
        reviewer_id = reviewer,
        reviewer_role = :independent_recovery_readiness_reviewer,
        independent_from_smoke_executor = true,
        pinned_source_author = false,
        smoke_execution_operator = false,
        reviewed_at_utc = reviewed_at,
        reviewed_material_sha256 =
            ld1b1_canonical_sha256(reviewed_material),
    )
    base = (;
        schema = LD1B1_INDEPENDENT_RECOVERY_READINESS_REVIEW_SCHEMA,
        object = :local_dependence_pilot_independent_recovery_readiness_review,
        scope = :ld1b1_independent_pinned_recovery_readiness_review,
        status = :independent_recovery_readiness_review_passed,
        reviewer = merge(attestation_material, (;
            attestation = (;
                algorithm = :sha256,
                value = ld1b1_canonical_sha256(attestation_material),
                covers = :reviewer_attestation_without_attestation,
                canonical_format = :local_json_sorted_compact,
            ),
        )),
        reviewed_material,
        checks = (;
            reviewer_independence_attested = true,
            exact_pinned_source_reviewed = true,
            bounded_smoke_receipt_revalidated = true,
            receipt_lineage_reviewed = true,
            precommit_recovery_reviewed = true,
            launched_recovery_reviewed = true,
            result_evidence_semantics_reviewed = true,
            seal_inventory_reviewed = true,
            resource_bounds_reviewed = true,
            denominator_isolation_reviewed = true,
            all_findings_passed = true,
        ),
        evidence_boundary = (;
            bounded_canonical_smoke_passed = true,
            independent_recovery_readiness_review_passed = true,
            operational_execution_authorized = true,
            pilot_execution_started = false,
            pilot_execution_completed = false,
            scientific_pilot_outcomes = 0,
            scientific_pilot_denominator = LD1B1_EXPECTED_JOBS,
            tracked_release_lineage_verified = false,
        ),
    )
    return ld1b1_with_content_hash(base)
end

function ld1b1_validate_independent_recovery_readiness_review(
        path::AbstractString, checked, smoke_validation)
    isfile(path) && !islink(path) || error(
        "independent recovery/readiness review is not a regular file")
    review = JSON3.read(read(path, String))
    ld1b1_require_only_keys(review, (
        :schema,
        :object,
        :scope,
        :status,
        :reviewer,
        :reviewed_material,
        :checks,
        :evidence_boundary,
        :content_hash,
    ), "independent recovery/readiness review")
    ld1b1_string(review[:schema]) ==
        LD1B1_INDEPENDENT_RECOVERY_READINESS_REVIEW_SCHEMA &&
        ld1b1_symbol(review[:object]) ===
            :local_dependence_pilot_independent_recovery_readiness_review &&
        ld1b1_symbol(review[:scope]) ===
            :ld1b1_independent_pinned_recovery_readiness_review &&
        ld1b1_symbol(review[:status]) ===
            :independent_recovery_readiness_review_passed || error(
        "independent recovery/readiness review identity mismatch")
    content_hash = ld1b1_verify_content_hash(
        review; label = "independent recovery/readiness review")
    smoke_validation.valid &&
        smoke_validation.bounded_canonical_smoke_passed || error(
        "independent review cannot validate without bounded smoke")

    reviewer = review[:reviewer]
    ld1b1_require_only_keys(reviewer, (
        :reviewer_id,
        :reviewer_role,
        :independent_from_smoke_executor,
        :pinned_source_author,
        :smoke_execution_operator,
        :reviewed_at_utc,
        :reviewed_material_sha256,
        :attestation,
    ), "independent reviewer attestation")
    reviewer_id = strip(ld1b1_string(reviewer[:reviewer_id]))
    isempty(reviewer_id) && error("independent reviewer id is empty")
    ld1b1_symbol(reviewer[:reviewer_role]) ===
        :independent_recovery_readiness_reviewer &&
        ld1b1_bool(reviewer[:independent_from_smoke_executor]) &&
        !ld1b1_bool(reviewer[:pinned_source_author]) &&
        !ld1b1_bool(reviewer[:smoke_execution_operator]) || error(
        "independent reviewer attestation does not establish separation")
    reviewed_at = ld1b1_string(reviewer[:reviewed_at_utc])
    occursin(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$",
        reviewed_at) || error("independent review time is not canonical UTC")
    reviewed_material_hash = ld1b1_canonical_sha256(
        ld1b1_json_native(review[:reviewed_material]))
    ld1b1_string(reviewer[:reviewed_material_sha256]) ==
        reviewed_material_hash || error(
        "independent review material hash mismatch")
    attestation = reviewer[:attestation]
    ld1b1_require_only_keys(attestation,
        (:algorithm, :value, :covers, :canonical_format),
        "independent review attestation hash")
    ld1b1_symbol(attestation[:algorithm]) === :sha256 &&
        ld1b1_symbol(attestation[:covers]) ===
            :reviewer_attestation_without_attestation &&
        ld1b1_symbol(attestation[:canonical_format]) ===
            :local_json_sorted_compact || error(
        "independent review attestation hash contract mismatch")
    attestation_material = ld1b1_json_native(reviewer)
    delete!(attestation_material, "attestation")
    ld1b1_string(attestation[:value]) ==
        ld1b1_canonical_sha256(attestation_material) || error(
        "independent reviewer attestation hash mismatch")

    expected_review = ld1b1_independent_recovery_readiness_review_artifact(
        checked,
        smoke_validation;
        reviewer_id,
        reviewed_at_utc = reviewed_at,
    )
    ld1b1_canonical_sha256(ld1b1_json_native(review)) ==
        ld1b1_canonical_sha256(ld1b1_json_native(expected_review)) || error(
        "independent recovery/readiness review differs from the frozen contract")
    return (;
        valid = true,
        independent_recovery_readiness_review_passed = true,
        reviewer_id,
        content_hash,
        file_sha256 = ld1b1_file_sha256(path),
        operational_execution_authorized = true,
    )
end

function ld1b1_execute_bounded_smoke(options)
    normpath(options.protocol) == normpath(LD1B1_DEFAULT_PROTOCOL) || error(
        "bounded-smoke requires the canonical protocol artifact")
    normpath(options.runner) == normpath(LD1B1_DEFAULT_JOB_RUNNER) || error(
        "bounded-smoke requires the canonical single-job worker")
    normpath(options.attempt_root) ==
        normpath(LD1B1_DEFAULT_BOUNDED_SMOKE_ROOT) || error(
        "bounded-smoke requires the dedicated fixed root")
    normpath(options.output) ==
        normpath(LD1B1_DEFAULT_BOUNDED_SMOKE_RECEIPT) || error(
        "bounded-smoke requires the fixed immutable receipt path")
    (ispath(options.output) || islink(options.output)) && error(
        "refusing to replace an existing bounded-smoke receipt")
    normpath(options.attempt_root) != normpath(LD1B1_DEFAULT_ATTEMPT_ROOT) ||
        error("bounded-smoke root collides with the official pilot root")

    checked = ld1b1_checked_protocol(
        options.protocol;
        job_runner_path = options.runner,
        attempt_root = LD1B1_DEFAULT_ATTEMPT_ROOT,
    )
    readiness = checked.identity.readiness
    readiness.protocol_execution_authorized &&
        readiness.canonical_executor_materialized &&
        readiness.final_worker_source_pinned_and_identities_regenerated &&
        readiness.canonical_executor_source_pinned &&
        readiness.completed_attempt_archive_seal_supported &&
        readiness.canonical_execution_root_bound || error(
        "bounded-smoke source/receipt prerequisites did not pass")
    !readiness.bounded_canonical_smoke_passed || error(
        "bounded canonical smoke is already recorded")
    !readiness.operational_execution_authorized || error(
        "bounded-smoke cannot substitute for an authorized pilot")

    specs = ld1b1_job_specs(checked)
    job = ld1b1_bounded_smoke_job(specs)
    official_before = ld1b1_bounded_smoke_official_state(checked, specs)
    smoke = ld1b1_bounded_smoke_identity(checked.identity, job)
    execution_root = ld1b1_bounded_smoke_execution_root(
        options.attempt_root, smoke.smoke_plan_id)
    authorization_path = ld1b1_bounded_smoke_authorization_path(
        options.attempt_root, smoke.smoke_plan_id)
    (ispath(execution_root) || islink(execution_root) ||
        ispath(authorization_path) || islink(authorization_path)) && error(
        "bounded-smoke plan root is already occupied")
    authorization_artifact = ld1b1_bounded_smoke_authorization(
        checked.identity, smoke.identity, job, options.attempt_root)
    ld1b1_atomic_write_artifact(
        authorization_path, authorization_artifact; overwrite = false)
    authorization = merge(
        ld1b1_validate_bounded_smoke_authorization(
            authorization_path,
            checked.identity,
            smoke.identity,
            job,
            options.attempt_root,
        ),
        (; path = authorization_path),
    )

    target_dir = ld1b1_require_attempt_available(
        job,
        smoke.identity,
        execution_root,
        options;
        calibration_semantic_context = checked.calibration_semantic_context,
    )
    run_id = string("bounded-smoke-", smoke.smoke_plan_id)
    context = ld1b1_execution_context(:bounded_smoke)
    reservation_setup = ld1b1_publish_attempt_reservation_create_new(
        execution_root,
        smoke.identity,
        job,
        1,
        run_id;
        execution_context = context,
    )
    mkpath(dirname(target_dir))
    mkdir(target_dir)
    ld1b1_require_realpath_containment(target_dir, execution_root)
    owner_setup = ld1b1_publish_canonical_owner_create_new(
        reservation_setup.lineage, execution_root)
    runner_source_sha256 = ld1b1_file_sha256(options.runner)
    command = ld1b1_job_command(
        job,
        smoke.identity,
        execution_root,
        options;
        runner_source_sha256,
        bounded_smoke_authorization = authorization_path,
    )
    run_root = dirname(dirname(execution_root))
    log_path = joinpath(run_root, "logs", "bounded_smoke_worker.log")
    result = ld1b1_run_command_with_controller_receipts(
        command.args,
        log_path,
        reservation_setup.lineage,
        owner_setup.owner,
        execution_root;
        timeout_seconds = LD1B1_BOUNDED_SMOKE_TIMEOUT_SECONDS,
        termination_grace_seconds =
            LD1B1_BOUNDED_SMOKE_TERMINATION_GRACE_SECONDS,
        max_rss_bytes = LD1B1_BOUNDED_SMOKE_MAX_RSS_BYTES,
        max_archive_bytes = LD1B1_BOUNDED_SMOKE_MAX_ARCHIVE_BYTES,
        monitored_archive_root = run_root,
    )
    ld1b1_file_sha256(options.runner) == runner_source_sha256 || error(
        "single-job worker changed during bounded smoke")
    result.ok || error(
        "bounded-smoke worker did not pass: " * string(result.error))
    controller_receipts = ld1b1_validate_canonical_controller_receipts(
        target_dir,
        smoke.identity,
        job,
        1;
        execution_context = context,
    )
    controller_receipts.exit_code == 0 || error(
        "bounded-smoke child exit receipt is nonzero")
    sealed = ld1b1_publish_completed_attempt_seal(
        command.result_path,
        smoke.identity,
        job,
        1;
        calibration_semantic_context = checked.calibration_semantic_context,
        execution_context = context,
    )
    terminal = sealed.validation
    terminal.terminal_status === :completed || error(
        "bounded-smoke terminal status is not completed: " *
        string(terminal.terminal_status))
    final_archive_bytes = ld1b1_observed_tree_bytes(run_root)
    final_archive_bytes <= LD1B1_BOUNDED_SMOKE_MAX_ARCHIVE_BYTES || error(
        "bounded-smoke sealed archive exceeds the fixed archive cap")
    result = merge(result, (;
        peak_archive_bytes = max(
            result.peak_archive_bytes, final_archive_bytes),
    ))
    official_after = ld1b1_bounded_smoke_official_state(checked, specs)
    official_before == official_after || error(
        "official pilot tree changed during bounded smoke")
    receipt = ld1b1_bounded_smoke_receipt(
        checked,
        smoke.identity,
        job,
        options.attempt_root,
        authorization,
        command,
        result,
        controller_receipts,
        terminal,
        official_before,
        official_after,
        log_path,
    )
    ld1b1_atomic_write_artifact(options.output, receipt; overwrite = false)
    validated = ld1b1_validate_bounded_smoke_receipt(
        options.output,
        checked;
        smoke_root = options.attempt_root,
    )
    return (; receipt, validated)
end

function ld1b1_retire_interrupted_selected(selection, checked,
        execution_root::AbstractString, options)
    length(selection.selected) == 1 || error(
        "retire-interrupted must select exactly one canonical job")
    job = only(selection.selected)
    attempt = options.attempt
    attempt_dir = ld1b1_attempt_dir(
        execution_root, job.job_id, attempt)
    source = LD1B1AttemptArchive._ld1b_read_json_snapshot(
        normpath(options.stopped_process_review),
        dirname(normpath(options.stopped_process_review)),
        "external stopped-process review",
    )
    source_native = ld1b1_json_native(source.parsed)
    haskey(source_native, "schema") || error(
        "external stopped-process review lacks a schema")
    source_schema = ld1b1_string(source_native["schema"])
    precommit_review = source_schema ==
        LD1B1Recovery.LD1B_PRECOMMIT_INTERRUPTION_REVIEW_SCHEMA
    launched_review = source_schema ==
        LD1B1Recovery.LD1B_INTERRUPTION_REVIEW_SCHEMA
    xor(precommit_review, launched_review) || error(
        "unsupported external stopped-process review schema")
    if !ispath(attempt_dir) && !islink(attempt_dir)
        precommit_review || error(
            "launched-attempt retirement requires an existing attempt directory")
        # Validate the immutable reservation before materializing the reserved
        # directory.  The external review must still independently attest that
        # both controller and any child process are stopped.
        lineage = ld1b1_reservation_lineage(
            execution_root, checked.identity, job, attempt)
        normpath(lineage.attempt_dir) == normpath(attempt_dir) || error(
            "reservation is bound to a different attempt directory")
        prevalidation = LD1B1Recovery.
            ld1b_validate_precommit_interruption_review(
                source.parsed;
                lineage.identity_args...,
                lineage.lineage_args...,
                owner_artifact = nothing,
                owner_receipt_sha256 = nothing,
            )
        prevalidation.reason_code === options.retirement_reason || error(
            "precommit review reason differs from --retirement-reason")
        prevalidation.scientific_contribution == 0 || error(
            "precommit review has a nonzero scientific contribution")
        mkpath(dirname(attempt_dir))
        mkdir(attempt_dir)
    end
    isdir(attempt_dir) && !islink(attempt_dir) || error(
        "retire-interrupted requires a regular reserved attempt directory")
    ld1b1_reject_symlink_components(attempt_dir, execution_root)

    retirement_path = ld1b1_retirement_path(
        execution_root, job.job_id, attempt)
    retirement_already_present =
        ispath(retirement_path) || islink(retirement_path)
    external = precommit_review ?
        ld1b1_validate_external_precommit_interruption_review(
            options.stopped_process_review,
            attempt_dir,
            execution_root,
            checked.identity,
            job,
            attempt,
        ) :
        ld1b1_validate_external_interruption_review(
            options.stopped_process_review,
            attempt_dir,
            checked.identity,
            job,
            attempt,
        )
    external_reason = precommit_review ?
        external.validation.reason_code :
        external.validation.retirement_reason_code
    external_reason ===
        options.retirement_reason || error(
        "supplied review retirement reason differs from --retirement-reason")

    if retirement_already_present
        retired = ld1b1_validate_retired_attempt(
            execution_root, checked.identity, job, attempt)
        retired.retirement_reason_code === options.retirement_reason || error(
            "existing retirement reason differs from --retirement-reason")
        existing_review = if precommit_review
            ld1b1_validate_precommit_interruption_review_record(
                attempt_dir, execution_root, checked.identity, job, attempt)
        else
            recovery = ld1b1_recovery_reservation_context(
                attempt_dir, checked.identity, job, attempt)
            LD1B1Recovery.ld1b_validate_interruption_review_file(
                attempt_dir;
                plan_identity = ld1b1_result_plan_identity(checked.identity),
                execution_source_identity =
                    checked.identity.execution_source_identity,
                job_identity = ld1b1_result_job_identity(job),
                attempt_number = attempt,
                attempt_role = attempt == 1 ? :primary : :remediation,
                recovery.file_kwargs...,
            )
        end
        existing_content_hash = precommit_review ?
            existing_review.content_hash : existing_review.review_content_hash
        existing_content_hash ==
            external.validation.content_hash || error(
            "existing retirement review differs from the supplied review")
        return ((;
            job_id = job.job_id,
            attempt,
            action_status = :retired_interruption_verified,
            review_publication = :reused_existing,
            retirement_publication = :reused_existing,
            review_mode = precommit_review ?
                :precommit_process_stop_review : existing_review.mode,
            retirement_reason_code = retired.retirement_reason_code,
            review_file_sha256 = retired.review_file_sha256,
            retirement_file_sha256 = retired.retirement_file_sha256,
            subprocess_started = false,
            response_data_generated = false,
            model_fit_run = false,
            mcmc_run = false,
        ),)
    end

    if !precommit_review
        observation = ld1b1_interrupted_attempt_observation(
            execution_root,
            checked.identity,
            job,
            attempt;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        observation.retirement_reason_code ===
            options.retirement_reason || error(
            "current attempt state differs from --retirement-reason")
        reviewed_state = external.validation.observed_attempt_state
        ld1b1_bool(reviewed_state["result_present"]) ==
            observation.result_present || error(
                "stopped-process review result presence differs from the attempt")
        reviewed_result_sha256 = reviewed_state["result_file_sha256"]
        if observation.result_file_sha256 === nothing
            reviewed_result_sha256 === nothing || error(
                "stopped-process review unexpectedly binds a result SHA-256")
        else
            ld1b1_string(reviewed_result_sha256) ==
                observation.result_file_sha256 || error(
                "stopped-process review result SHA-256 differs from the attempt")
        end
        ld1b1_symbol(reviewed_state["result_semantic_assessment"]) ===
            observation.result_semantic_assessment || error(
            "stopped-process review semantic assessment differs from the controller")
    end

    review = precommit_review ?
        ld1b1_publish_external_precommit_interruption_review(
            options.stopped_process_review,
            attempt_dir,
            execution_root,
            checked.identity,
            job,
            attempt,
        ) :
        ld1b1_publish_external_interruption_review(
            options.stopped_process_review,
            attempt_dir,
            execution_root,
            checked.identity,
            job,
            attempt,
        )
    published_reason = precommit_review ? review.validation.reason_code :
        review.validation.retirement_reason_code
    published_reason ===
        options.retirement_reason || error(
        "published review retirement reason changed during publication")
    attempt_role = attempt == 1 ? :primary : :remediation
    marker = LD1B1AttemptArchive.ld1b_publish_attempt_retirement_marker(
        attempt_dir;
        plan_identity = ld1b1_result_plan_identity(checked.identity),
        execution_source_identity =
            checked.identity.execution_source_identity,
        job_identity = ld1b1_result_job_identity(job),
        attempt_number = attempt,
        attempt_role,
        retirement_reason_code = options.retirement_reason,
        review_record_sha256 = precommit_review ?
            review.validation.file_sha256 :
            review.validation.review_file_sha256,
        # This is derived only after strict receipt/review validation above.
        process_confirmed_stopped = true,
        staging_dir = ld1b1_retirement_staging_dir(execution_root),
        boundary = execution_root,
    )
    retired = ld1b1_validate_retired_attempt(
        execution_root, checked.identity, job, attempt)
    return ((;
        job_id = job.job_id,
        attempt,
        action_status = :retired_interruption_verified,
        review_publication = review.publication.reused_existing ?
            :reused_existing : :create_new,
        retirement_publication = marker.publication.publication,
        review_mode = precommit_review ?
            :precommit_process_stop_review : review.validation.mode,
        retirement_reason_code = retired.retirement_reason_code,
        review_file_sha256 = retired.review_file_sha256,
        retirement_file_sha256 = retired.retirement_file_sha256,
        subprocess_started = false,
        response_data_generated = false,
        model_fit_run = false,
        mcmc_run = false,
    ),)
end

function ld1b1_command_rows(selection, identity, execution_root, options)
    return Tuple((function ()
        planned_runner_sha256 =
            identity.execution_source_identity.job_runner_source_sha256
        command = ld1b1_job_command(
            job,
            identity,
            execution_root,
            options;
            runner_source_sha256 = ismissing(planned_runner_sha256) ?
                nothing : planned_runner_sha256,
            controller_readiness_authorized = false,
        )
        (;
            job_id = job.job_id,
            row_index = job.row_index,
            scenario_id = job.scenario_id,
            replication = job.replication,
            expected_action = job.expected_action,
            attempt = options.attempt,
            attempt_role = options.attempt == 1 ? :primary : :remediation,
            counts_toward_primary = options.attempt == 1,
            retry_of_attempt = options.retry_of,
            retry_reason = options.retry_reason,
            result_path = ld1b1_record_path(command.result_path),
            command = ld1b1_portable_command_string(command.args),
            controller_readiness_authorized =
                command.controller_readiness_authorized,
        )
    end)() for job in selection.selected)
end

function ld1b1_harness_job_rows(specs, execution_root)
    return Tuple((;
        job_id = job.job_id,
        row_index = job.row_index,
        scenario_index = job.scenario_index,
        scenario_id = job.scenario_id,
        matched_set_id = job.matched_set_id,
        replication = job.replication,
        phase = job.phase,
        seed = job.seed,
        fit_seed = job.fit_seed,
        draw_selection_seed = job.draw_selection_seed,
        posterior_predictive_seed = job.posterior_predictive_seed,
        expected_action = job.expected_action,
        expected_structural_eligibility =
            job.expected_structural_eligibility,
        resources = job.resources,
        primary_attempt = job.primary_attempt,
        primary_outcome_overwritable_by_retries =
            job.primary_outcome_overwritable_by_retries,
        primary_attempt_dir = ld1b1_record_path(
            ld1b1_attempt_dir(execution_root, job.job_id, 1)),
        primary_attempt_reservation_path = ld1b1_record_path(
            ld1b1_attempt_reservation_path(
                execution_root, job.job_id, 1)),
        primary_result_path = ld1b1_record_path(
            ld1b1_result_path(execution_root, job.job_id, 1)),
        primary_interruption_review_path = ld1b1_record_path(
            ld1b1_interruption_review_path(
                execution_root, job.job_id, 1)),
        primary_precommit_interruption_review_path = ld1b1_record_path(
            ld1b1_precommit_interruption_review_path(
                execution_root, job.job_id, 1)),
        primary_retirement_path = ld1b1_record_path(
            ld1b1_retirement_path(execution_root, job.job_id, 1)),
        remediation_attempt_path_template = ld1b1_record_path(joinpath(
            execution_root,
            "jobs",
            job.job_id,
            "attempt_{NNN}",
            "job_result.json",
        )),
        remediation_interruption_review_path_template =
            ld1b1_record_path(joinpath(
                execution_root,
                "jobs",
                job.job_id,
                "attempt_{NNN}",
                LD1B1Recovery.LD1B_INTERRUPTION_REVIEW_FILENAME,
            )),
        remediation_retirement_path_template = ld1b1_record_path(joinpath(
            execution_root,
            "jobs",
            job.job_id,
            "attempt_{NNN}",
            LD1B1AttemptArchive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
        )),
        execution_status = :not_executed,
    ) for job in specs)
end

function ld1b1_validate_harness_generator_metadata(
        metadata, identity)
    ld1b1_require_only_keys(metadata, (
        :path,
        :source_sha256,
        :batch_runner_path,
        :batch_runner_source_sha256,
    ), "batch harness generator metadata")
    path = ld1b1_string(metadata[:path])
    path ==
        "scripts/generate_local_dependence_pilot_batch_execution_harness.jl" ||
        error("batch harness generator metadata has the wrong canonical path")
    source_sha256 = ld1b1_require_sha256(
        metadata[:source_sha256],
        "batch harness generator source identity",
    )
    source_sha256 == identity.batch_harness_generator_source_sha256 || error(
        "batch harness generator differs from the canonical executor source pin")
    batch_runner_path = ld1b1_string(metadata[:batch_runner_path])
    batch_runner_path ==
        "scripts/run_local_dependence_calibration_pilot_batch.jl" || error(
        "batch harness generator metadata has the wrong batch-runner path")
    batch_runner_source_sha256 = ld1b1_require_sha256(
        metadata[:batch_runner_source_sha256],
        "batch harness generator batch-runner source identity",
    )
    batch_runner_source_sha256 ==
        identity.execution_source_identity.batch_runner_source_sha256 || error(
        "batch harness generator metadata has the wrong batch-runner source identity")
    return (;
        path,
        source_sha256,
        batch_runner_path,
        batch_runner_source_sha256,
    )
end

function ld1b1_build_harness(options;
        scan_results::Bool = true,
        generated_at = nothing,
        artifact_generator = nothing,
        consume_bounded_smoke_receipt::Bool = true)
    checked = ld1b1_checked_protocol(
        options.protocol;
        job_runner_path = options.runner,
        attempt_root = options.attempt_root,
        consume_bounded_smoke_receipt,
    )
    artifact_generator === nothing ||
        (artifact_generator = ld1b1_validate_harness_generator_metadata(
            artifact_generator, checked.identity))
    specs = ld1b1_job_specs(checked)
    selection = ld1b1_selected_jobs(specs, options)
    execution_root = ld1b1_execution_root(
        options.attempt_root, checked.identity.plan_id)
    checkpoint_path = options.checkpoint === nothing ?
        joinpath(execution_root, "checkpoint.json") : options.checkpoint
    scan = scan_results ?
        ld1b1_scan_attempts(
            specs,
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        ) : ld1b1_empty_scan(specs, checked.identity)
    resume_state = options.resume ?
        ld1b1_resume_state(checkpoint_path, checked.identity, scan) :
        ld1b1_no_resume_state(scan)

    execution_rows = ()
    recovery_rows = ()
    if options.mode in (:execute_primary, :execute_retry)
        execution_rows = ld1b1_execute_selected(
            selection,
            checked,
            specs,
            execution_root,
            checkpoint_path,
            options,
        )
        scan = ld1b1_scan_attempts(
            specs,
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
    elseif options.mode === :retire_interrupted
        recovery_rows = ld1b1_retire_interrupted_selected(
            selection,
            checked,
            execution_root,
            options,
        )
        scan = ld1b1_scan_attempts(
            specs,
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
    end
    if options.write_checkpoint
        checkpoint = ld1b1_checkpoint_artifact(checked.identity, scan)
        ld1b1_atomic_write_artifact(
            checkpoint_path, checkpoint; overwrite = true)
    end

    command_rows = options.mode in (:aggregate_only, :retire_interrupted) ? () :
        ld1b1_command_rows(selection, checked.identity, execution_root, options)
    aggregate_passed = scan.summary.aggregate_assessment === :ready &&
        scan.summary.attempt_archive_assessment === :passed
    execution_failed = any(row -> !(row.action_status in (
        :terminal_result_verified,
        :skipped_verified_terminal_primary,
    )), execution_rows)
    recovery_failed = any(row -> row.action_status !==
        :retired_interruption_verified, recovery_rows)
    passed = options.mode === :aggregate_only ? aggregate_passed :
        options.mode in (:execute_primary, :execute_retry) ? !execution_failed :
        options.mode === :retire_interrupted ? !recovery_failed :
        true
    runner_materialized = isfile(options.runner) && !islink(options.runner)
    execute_mode_requested = options.mode in (:execute_primary, :execute_retry)
    n_job_runner_subprocesses_started = count(
        row -> row.subprocess_started,
        execution_rows,
    )
    invokes_job_runner = n_job_runner_subprocesses_started > 0
    invocation_activity = invokes_job_runner ? missing : false
    pass_scope = options.mode === :aggregate_only ?
        :aggregate_integrity_and_operational_gate :
        options.mode === :retire_interrupted ?
            :interrupted_attempt_recovery_disposition :
        execute_mode_requested ? :batch_controller_invocation :
        :harness_contract_only
    base = (;
        schema = LD1B1_HARNESS_SCHEMA,
        family = :mfrm,
        scope = :ld1b1_pilot_batch_harness_preflight_noncalibration,
        status = passed ? :pilot_batch_harness_recorded :
            :pilot_batch_harness_incomplete_or_blocked,
        package = (;
            name = :BayesianMGMFRM,
            version = ld1b1_project_version(),
        ),
        protocol_artifact = (;
            path = ld1b1_record_path(options.protocol),
            schema = LD1B1_PROTOCOL_SCHEMA,
            file_sha256 = checked.identity.protocol_file_sha256,
            content_hash = checked.identity.protocol_content_hash,
        ),
        plan_identity = checked.identity,
        harness_contract = (;
            mode = options.mode,
            primary_attempt = 1,
            primary_attempt_role = :primary,
            primary_counts_toward_scientific_denominator = true,
            primary_outcomes_overwritable = false,
            remediation_attempt_minimum = 2,
            remediation_attempt_role = :remediation,
            remediation_counts_toward_scientific_denominator = false,
            remediation_requires_primary_result_sha256 = true,
            remediation_requires_same_seed_contract = true,
            remediation_may_replace_primary_outcome = false,
            mutable_selected_attempt_pointer_used = false,
            attempt_directory_digits = 3,
            exclusive_attempt_directory_reservation = true,
            result_schema = LD1B1_JOB_RESULT_SCHEMA,
            evidence_schema = LD1B1_EVIDENCE_SCHEMA,
            status_specific_hashed_evidence_roles_required = true,
            status_specific_semantic_evidence_envelopes_required = true,
            terminal_evidence_role_sets_must_match_exactly = true,
            one_source_artifact_required_per_evidence_role = true,
            source_artifact_bytes_and_sha256_verified = true,
            evidence_payload_digest_must_match_source_artifact = true,
            evidence_dependency_content_hashes_required = true,
            evidence_dependency_roles_and_order_frozen = true,
            frozen_pilot_contract_sha256_verified = true,
            frozen_ordered_job_rows_sha256_verified = true,
            generated_resource_counts_must_match_frozen_jobs = true,
            generated_response_probability_and_truth_arrays_validated = true,
            fit_source_requires_structured_json_artifact = true,
            fit_source_requires_native_and_json_content_hashes = true,
            fit_json_content_hash_recomputed = true,
            fit_native_hash_pre_projection_executor_verification_required = true,
            cross_evidence_data_design_draw_lineage_validated = true,
            local_summary_execution_seeds_source_bound = true,
            draw_selection_seed_to_indices_recomputed = true,
            posterior_predictive_seed_to_result_replay_verified = false,
            pre_fit_rejection_requires_simulation_and_calibration_provenance = true,
            diagnostic_failure_component_must_match_sampler_gate = true,
            failure_semantics = ld1b1_failure_semantics(),
            unavailable_sampler_diagnostics_is_terminal = false,
            final_calibration_serialization_failure_is_terminal = false,
            incomplete_artifact_failure_requires_recovery_disposition = true,
            sampler_controls_and_quality_gates_frozen = true,
            diagnostic_summary_metrics_individually_validated = true,
            empty_file_manifest_accepted = false,
            unmanifested_attempt_files_accepted = false,
            symbolic_links_allowed_in_attempt_tree = false,
            hard_links_allowed_in_attempt_tree = false,
            file_snapshot_rechecked_against_attempt_inventory = true,
            archive_validation_is_atomic = false,
            completed_attempt_archive_seal_supported =
                LD1B1_COMPLETED_ATTEMPT_ARCHIVE_SEAL_SUPPORTED,
            completed_attempt_seal_create_new_publication_required = true,
            result_without_completed_attempt_seal_is_terminal = false,
            completed_attempt_seal_and_result_semantics_both_required = true,
            operational_readiness_conjunction_required = true,
            protocol_execution_authorization_required = true,
            canonical_executor_source_pin_required = true,
            bounded_canonical_smoke_receipt_required = true,
            interrupted_attempt_recovery_review_required = true,
            interruption_review_schema =
                LD1B1Recovery.LD1B_INTERRUPTION_REVIEW_SCHEMA,
            interruption_review_create_new_publication_required = true,
            validated_review_required_before_retirement = true,
            review_file_sha256_must_match_retirement_marker = true,
            retirement_is_nonterminal = true,
            retirement_counts_toward_scientific_denominator = false,
            retirement_may_replace_primary_outcome = false,
            retired_attempt_same_slot_restart_allowed = false,
            retired_predecessor_remediation_supported = false,
            completed_seal_and_retirement_are_mutually_exclusive = true,
            canonical_execution_root_binding_required = true,
            execute_path_checks_readiness_before_attempt_creation = true,
            canonical_job_runner_required_for_execution = true,
            execute_path_verifies_runner_sha256_around_each_subprocess = true,
            execute_path_passes_expected_source_identity = true,
            execute_path_plan_identity_includes_runner_source_sha256 = true,
            execute_path_requires_result_and_evidence_source_identity_binding = true,
            verified_terminal_statuses = Tuple(sort!(collect(
                LD1B1_TERMINAL_STATUSES); by = string)),
            terminal_evidence_roles = (;
                completed = ld1b1_required_evidence_roles(:completed),
                pre_fit_rejected =
                    ld1b1_required_evidence_roles(:pre_fit_rejected),
                generation_failed =
                    ld1b1_required_evidence_roles(:generation_failed),
                fit_failed = ld1b1_required_evidence_roles(:fit_failed),
                diagnostic_failed =
                    ld1b1_required_evidence_roles(:diagnostic_failed),
            ),
            checkpoint_role = :derived_resume_index_only,
            resume_source_of_truth = :immutable_job_attempt_records,
            resume_skips_only_verified_terminal_primary = true,
            invalid_primary_attempt_blocks_primary_aggregate = true,
            invalid_remediation_attempt_blocks_attempt_archive = true,
            invalid_remediation_attempt_replaces_primary = false,
            invalid_remediation_attempt_blocks_primary_denominator = false,
            chain_level_sampler_resume_supported = false,
            aggregate_uses_primary_attempts_only = true,
            aggregate_preserves_remediation_rows_separately = true,
            aggregate_binds_primary_result_and_evidence_digests = true,
            aggregate_only_invokes_job_runner = false,
            interrupted_partial_attempt_restart_supported = false,
        ),
        path_contract = (;
            attempt_root = ld1b1_record_path(options.attempt_root),
            plan_execution_root = ld1b1_record_path(execution_root),
            checkpoint_path = ld1b1_record_path(checkpoint_path),
            job_directory_pattern = "jobs/<job_id>/attempt_<NNN>",
            primary_result_filename = "job_result.json",
            interruption_review_filename =
                LD1B1Recovery.LD1B_INTERRUPTION_REVIEW_FILENAME,
            attempt_retirement_filename =
                LD1B1AttemptArchive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
        ),
        runner = (;
            path = ld1b1_record_path(options.runner),
            availability = !runner_materialized ? :unavailable_missing_file :
                normpath(options.runner) == normpath(LD1B1_DEFAULT_JOB_RUNNER) ?
                    :available : :unavailable_identity_mismatch,
            execution_mode_requested = execute_mode_requested,
            subprocesses_started = n_job_runner_subprocesses_started,
            source_sha256 = runner_materialized ?
                ld1b1_file_sha256(options.runner) : missing,
        ),
        selection = (;
            n_matching_jobs = length(selection.matching),
            n_selected_jobs = length(selection.selected),
            job_ids = options.job_ids,
            row_indexes = options.row_indexes,
            scenarios = options.scenarios,
            replications = options.replications,
            max_jobs = options.max_jobs,
            all = options.run_all,
            attempt = options.attempt,
            retry_of_attempt = options.retry_of,
            retry_reason = options.retry_reason,
            retirement_reason = options.retirement_reason,
            stopped_process_review = options.stopped_process_review === nothing ?
                nothing : ld1b1_record_path(options.stopped_process_review),
        ),
        job_rows = ld1b1_harness_job_rows(specs, execution_root),
        command_rows,
        execution_rows,
        recovery_rows,
        resume = resume_state,
        aggregate = (;
            aggregate_only = options.mode === :aggregate_only,
            attempt_tree_scanned = scan_results ||
                options.mode in (
                    :execute_primary,
                    :execute_retry,
                    :retire_interrupted,
                ),
            scan_assessment = scan.summary.scan_assessment,
            state_digest = scan.state_digest,
            observed_primary_result_set_sha256 =
                scan.observed_primary_result_set_sha256,
            observed_primary_disposition_set_sha256 =
                scan.observed_primary_disposition_set_sha256,
            attempt_reservation_scan_active =
                scan.attempt_reservation_scan_active,
            attempt_reservation_rows = scan.attempt_reservation_rows,
            attempt_reservation_state_digest =
                scan.attempt_reservation_state_digest,
            job_state_rows = scan_results ||
                options.mode in (:execute_primary, :execute_retry) ?
                    scan.job_state_rows : (),
            scenario_status_rows = scan.scenario_status_rows,
            unexpected_entries = scan.unexpected_entries,
            unexpected_plan_entries = scan.unexpected_plan_entries,
            summary = scan.summary,
        ),
        evidence_boundary = (;
            activity_scope = :current_batch_controller_invocation,
            job_runner_subprocesses_started =
                n_job_runner_subprocesses_started,
            response_data_generated = invocation_activity,
            model_fit_run = invocation_activity,
            mcmc_run = invocation_activity,
            pilot_execution_completed = scan.summary.pilot_execution_completed,
            evaluation_profile_frozen = false,
            repeated_calibration_completed = false,
            calibration_evidence_available = false,
            pairwise_power_available = false,
            diagnostic_decision_labels_available = false,
            mechanism_interpretation_eligible = false,
        ),
        checks = (;
            plan_identity_valid = checked.identity.plan_identity_valid,
            execution_plan_complete =
                checked.identity.execution_plan_complete,
            canonical_job_matrix_valid = length(specs) == LD1B1_EXPECTED_JOBS &&
                length(unique(job.job_id for job in specs)) ==
                    LD1B1_EXPECTED_JOBS,
            exact_fit_job_count = count(job -> job.expected_action ===
                :fit_and_score_diagnostic, specs) == LD1B1_EXPECTED_FIT_JOBS,
            exact_pre_fit_rejection_count = count(job ->
                job.expected_action === :pre_fit_reject, specs) ==
                    LD1B1_EXPECTED_REJECTION_JOBS,
            nonoverwrite_enforced = true,
            additive_retry_semantics_enforced = true,
            resume_contract_valid = true,
            aggregate_only_executes_jobs = false,
        ),
        summary = (;
            passed,
            pass_scope,
            harness_contract_assessment = :passed,
            mode_assessment = passed ? :passed : :failed,
            mode = options.mode,
            plan_identity_valid = true,
            execution_plan_complete =
                checked.identity.execution_plan_complete,
            execution_plan_assessment =
                checked.identity.execution_plan_assessment,
            operational_execution_authorized = checked.identity.readiness.
                operational_execution_authorized,
            operational_execution_blockers =
                checked.identity.readiness.blockers,
            protocol_execution_authorized = checked.identity.readiness.
                protocol_execution_authorized,
            canonical_executor_materialized = checked.identity.readiness.
                canonical_executor_materialized,
            final_worker_source_pinned_and_identities_regenerated =
                checked.identity.readiness.
                    final_worker_source_pinned_and_identities_regenerated,
            canonical_executor_source_pinned = checked.identity.readiness.
                canonical_executor_source_pinned,
            bounded_canonical_smoke_passed = checked.identity.readiness.
                bounded_canonical_smoke_passed,
            completed_attempt_archive_seal_supported = checked.identity.
                readiness.completed_attempt_archive_seal_supported,
            interrupted_attempt_recovery_review_passed = checked.identity.
                readiness.interrupted_attempt_recovery_review_passed,
            canonical_execution_root_bound = checked.identity.readiness.
                canonical_execution_root_bound,
            canonical_job_matrix_valid = true,
            n_plan_jobs = length(specs),
            n_fit_jobs = LD1B1_EXPECTED_FIT_JOBS,
            n_pre_fit_rejection_jobs = LD1B1_EXPECTED_REJECTION_JOBS,
            n_duplicate_job_ids = length(specs) -
                length(unique(job.job_id for job in specs)),
            job_runner_availability = !runner_materialized ?
                :unavailable_missing_file :
                normpath(options.runner) == normpath(LD1B1_DEFAULT_JOB_RUNNER) ?
                    :available : :unavailable_identity_mismatch,
            execution_capability_status = runner_materialized &&
                normpath(options.runner) == normpath(LD1B1_DEFAULT_JOB_RUNNER) ?
                    :available : :unavailable,
            n_primary_attempts_observed =
                scan.summary.n_primary_attempts_observed,
            n_retry_attempts_observed =
                scan.summary.n_retry_attempts_observed,
            n_partial_attempts = scan.summary.n_partial_attempts,
            n_retired_attempts = scan.summary.n_retired_attempts,
            n_retired_primary_attempts =
                scan.summary.n_retired_primary_attempts,
            n_retired_remediation_attempts =
                scan.summary.n_retired_remediation_attempts,
            n_reviewed_pending_retirement_attempts =
                scan.summary.n_reviewed_pending_retirement_attempts,
            n_disposition_conflicts =
                scan.summary.n_disposition_conflicts,
            n_corrupt_attempts = scan.summary.n_invalid_attempts,
            n_invalid_primary_attempts =
                scan.summary.n_invalid_primary_attempts,
            n_invalid_remediation_attempts =
                scan.summary.n_invalid_remediation_attempts,
            n_missing_primary_outcomes =
                scan.summary.n_missing_primary_outcomes,
            nonoverwrite_enforced = true,
            additive_retry_semantics_enforced = true,
            resume_contract_valid = true,
            aggregate_ready = scan.summary.aggregate_ready,
            scan_assessment = scan.summary.scan_assessment,
            primary_attempt_tree_clean =
                scan.summary.primary_attempt_tree_clean,
            remediation_archive_clean =
                scan.summary.remediation_archive_clean,
            attempt_archive_integrity_passed =
                scan.summary.attempt_archive_integrity_passed,
            primary_tree_assessment =
                scan.summary.primary_tree_assessment,
            remediation_archive_assessment =
                scan.summary.remediation_archive_assessment,
            attempt_archive_assessment =
                scan.summary.attempt_archive_assessment,
            aggregate_assessment = scan.summary.aggregate_assessment,
            observed_primary_result_set_sha256 =
                scan.observed_primary_result_set_sha256,
            observed_primary_disposition_set_sha256 =
                scan.observed_primary_disposition_set_sha256,
            aggregate_only_executes_jobs = false,
            activity_scope = :current_batch_controller_invocation,
            job_runner_subprocesses_started =
                n_job_runner_subprocesses_started,
            response_data_generated = invocation_activity,
            model_fit_run = invocation_activity,
            mcmc_run = invocation_activity,
            pilot_execution_completed =
                scan.summary.pilot_execution_completed,
            evaluation_profile_frozen = false,
            calibration_evidence_available = false,
            diagnostic_decision_labels_available = false,
            mechanism_interpretation_eligible = false,
        ),
    )
    generated_at === nothing ||
        (base = merge(base, (; generated_at = String(generated_at))))
    artifact_generator === nothing ||
        (base = merge(base, (; artifact_generator = merge(
            artifact_generator,
            (; canonical_executor_source_pin_id =
                checked.identity.canonical_executor_source_pin_id),
        ))))
    return ld1b1_with_content_hash(base)
end

function ld1b1_default_output(options, plan_id::AbstractString)
    execution_root = ld1b1_execution_root(options.attempt_root, plan_id)
    if options.mode === :aggregate_only
        return joinpath(execution_root, "aggregate_runs", string(
            Dates.format(Dates.now(), dateformat"yyyymmdd_HHMMSS_sss"),
            "_aggregate.json"))
    elseif options.mode in (:execute_primary, :execute_retry)
        return joinpath(execution_root, "batch_runs", string(
            Dates.format(Dates.now(), dateformat"yyyymmdd_HHMMSS_sss"),
            "_orchestrator.json"))
    elseif options.mode === :retire_interrupted
        return joinpath(execution_root, "recovery_runs", string(
            Dates.format(Dates.now(), dateformat"yyyymmdd_HHMMSS_sss"),
            "_retirement.json"))
    elseif options.mode === :dry_run
        return joinpath(execution_root, "dry_runs", string(
            Dates.format(Dates.now(), dateformat"yyyymmdd_HHMMSS_sss"),
            "_dry_run.json"))
    end
    return nothing
end

function ld1b1_batch_main(args)
    options = ld1b1_parse_args(args)
    if options.mode === :bounded_smoke
        result = ld1b1_execute_bounded_smoke(options)
        println(
            "mode=bounded_smoke passed=", result.validated.valid,
            " smoke_plan_id=", result.validated.smoke_plan_id,
            " pilot_outcomes=0/", LD1B1_EXPECTED_JOBS,
            " operational_execution_authorized=false",
        )
        return nothing
    end
    artifact = ld1b1_build_harness(
        options; generated_at = string(Dates.now()))
    output = options.output === nothing ?
        ld1b1_default_output(options, artifact.plan_identity.plan_id) :
        options.output
    if output !== nothing
        ld1b1_atomic_write_artifact(output, artifact; overwrite = false)
        println("wrote ", ld1b1_record_path(output))
    end
    println(
        "mode=", artifact.summary.mode,
        " jobs=", artifact.summary.n_plan_jobs,
        " primary=", artifact.summary.n_primary_attempts_observed,
        " retries=", artifact.summary.n_retry_attempts_observed,
        " missing=", artifact.summary.n_missing_primary_outcomes,
        " aggregate_ready=", artifact.summary.aggregate_ready,
        " mcmc_run=", ismissing(artifact.summary.mcmc_run) ?
            "not_asserted_for_execute_mode" : artifact.summary.mcmc_run,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && ld1b1_batch_main(ARGS)
