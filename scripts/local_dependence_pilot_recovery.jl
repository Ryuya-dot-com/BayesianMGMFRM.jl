module LocalDependencePilotRecovery

using SHA

include(joinpath(@__DIR__, "local_dependence_pilot_attempt_archive.jl"))
using .LocalDependencePilotAttemptArchive
const Archive = LocalDependencePilotAttemptArchive

export LD1B_ATTEMPT_OWNER_FILENAME,
    LD1B_ATTEMPT_OWNER_SCHEMA,
    LD1B_ATTEMPT_RESERVATION_FILENAME,
    LD1B_ATTEMPT_RESERVATION_SCHEMA,
    LD1B_CANONICAL_ATTEMPT_OWNER_SCHEMA,
    LD1B_CHILD_LAUNCH_FILENAME,
    LD1B_CHILD_LAUNCH_SCHEMA,
    LD1B_CHILD_EXIT_FILENAME,
    LD1B_CHILD_EXIT_SCHEMA,
    LD1B_INTERRUPTION_REVIEW_FILENAME,
    LD1B_INTERRUPTION_REVIEW_SCHEMA,
    LD1B_PRECOMMIT_INTERRUPTION_REVIEW_FILENAME,
    LD1B_PRECOMMIT_INTERRUPTION_REVIEW_SCHEMA,
    LD1B_PILOT_EXECUTION_CONTEXT,
    LD1B_BOUNDED_SMOKE_EXECUTION_CONTEXT,
    ld1b_execution_context,
    ld1b_recovery_source_sha256,
    ld1b_attempt_reservation,
    ld1b_validate_attempt_reservation,
    ld1b_publish_attempt_reservation,
    ld1b_validate_attempt_reservation_file,
    ld1b_canonical_attempt_owner_precommit,
    ld1b_validate_canonical_attempt_owner_precommit,
    ld1b_publish_canonical_attempt_owner,
    ld1b_validate_canonical_attempt_owner_file,
    ld1b_precommit_interruption_review,
    ld1b_validate_precommit_interruption_review,
    ld1b_inventory_before_precommit_interruption_review,
    ld1b_publish_precommit_interruption_review,
    ld1b_reuse_existing_precommit_interruption_review,
    ld1b_validate_precommit_interruption_review_file,
    ld1b_attempt_owner_precommit,
    ld1b_child_launch_receipt,
    ld1b_child_exit_receipt,
    ld1b_stopped_process_interruption_review,
    ld1b_validate_attempt_owner_precommit,
    ld1b_validate_child_launch_receipt,
    ld1b_validate_child_exit_receipt,
    ld1b_validate_stopped_process_interruption_review,
    ld1b_inventory_before_interruption_review,
    ld1b_validate_attempt_owner_file,
    ld1b_validate_child_launch_file,
    ld1b_validate_child_exit_file,
    ld1b_validate_interruption_review_file,
    ld1b_publish_interruption_review

const LD1B_ATTEMPT_OWNER_FILENAME = "attempt_owner.json"
const LD1B_ATTEMPT_RESERVATION_FILENAME = "attempt_reservation.json"
const LD1B_CHILD_LAUNCH_FILENAME = "attempt_launch.json"
const LD1B_CHILD_EXIT_FILENAME = "attempt_exit.json"
const LD1B_INTERRUPTION_REVIEW_FILENAME = "interruption_review.json"
const LD1B_PRECOMMIT_INTERRUPTION_REVIEW_FILENAME =
    "precommit_interruption_review.json"

const LD1B_ATTEMPT_OWNER_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_attempt_owner.v2"
const LD1B_ATTEMPT_RESERVATION_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_attempt_reservation.v2"
const LD1B_CANONICAL_ATTEMPT_OWNER_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_reserved_attempt_owner.v2"
const LD1B_CHILD_LAUNCH_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_child_launch.v2"
const LD1B_CHILD_EXIT_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_child_exit.v2"
const LD1B_INTERRUPTION_REVIEW_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_interruption_review.v2"
const LD1B_PRECOMMIT_INTERRUPTION_REVIEW_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_precommit_interruption_review.v2"

const LD1B_PILOT_EXECUTION_CONTEXT = (;
    execution_scope = :pilot,
    root_namespace = :local_dependence_pilot,
    official_pilot_denominator_eligible = true,
)
const LD1B_BOUNDED_SMOKE_EXECUTION_CONTEXT = (;
    execution_scope = :bounded_smoke,
    root_namespace = :local_dependence_pilot_bounded_smoke_v1,
    official_pilot_denominator_eligible = false,
)

const _SHA256_PATTERN = r"^[0-9a-f]{64}$"
const _PLAN_FIELDS = (
    "plan_id", "protocol_plan_id", "protocol_file_sha256",
    "protocol_content_hash", "ordered_job_rows_sha256",
    "pilot_contract_sha256",
)
const _EXECUTION_FIELDS = (
    "batch_runner_source_sha256", "local_json_source_sha256",
    "job_runner_source_sha256", "attempt_archive_source_sha256",
    "local_dependence_pilot_recovery_source_sha256",
    "local_dependence_pilot_calibration_semantics_source_sha256",
)
const _JOB_FIELDS = (
    "job_id", "row_index", "scenario_index", "scenario_id",
    "replication", "expected_action", "seed", "fit_seed",
    "draw_selection_seed", "posterior_predictive_seed",
)
const _EXECUTION_CONTEXT_FIELDS = (
    "execution_scope", "root_namespace",
    "official_pilot_denominator_eligible",
)
const _COMMON_FIELDS = (
    "schema", "object", "scope", "recovery_source_sha256",
    "plan_identity", "plan_identity_sha256",
    "execution_source_identity", "execution_source_identity_sha256",
    "execution_context", "execution_context_sha256",
    "job_identity", "job_identity_sha256", "attempt",
)
const _REVIEW_INVENTORY_EXCLUSIONS = (
    Archive.LD1B_ATTEMPT_SEAL_FILENAME,
    Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
    LD1B_INTERRUPTION_REVIEW_FILENAME,
)
const _PRECOMMIT_REVIEW_INVENTORY_EXCLUSIONS = (
    Archive.LD1B_ATTEMPT_SEAL_FILENAME,
    Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
    LD1B_PRECOMMIT_INTERRUPTION_REVIEW_FILENAME,
)
const _PRECOMMIT_REVIEW_REASONS = (
    :interrupted_after_reservation_before_owner,
    :interrupted_after_owner_before_launch_receipt,
)
const _REVIEW_MODES = (
    :validated_exit_receipt,
    :external_process_identity_review,
)
const _RETIREMENT_REASON_ASSESSMENTS = Dict(
    :interrupted_without_result => :result_absent,
    :interrupted_with_semantically_valid_unsealed_result =>
        :semantically_valid_unsealed_result,
    :interrupted_with_invalid_unsealed_result => :invalid_unsealed_result,
)
const _RESULT_FILENAME = "job_result.json"

ld1b_recovery_source_sha256() = bytes2hex(open(sha256, @__FILE__))

function _native(value)
    if value isa NamedTuple || value isa AbstractDict
        result = Dict{String,Any}()
        for (key, element) in pairs(value)
            key isa Symbol || key isa AbstractString ||
                error("JSON object keys must be strings or symbols")
            canonical = String(key)
            haskey(result, canonical) &&
                error("JSON object contains colliding key $canonical")
            result[canonical] = _native(element)
        end
        return result
    elseif value isa AbstractArray || value isa Tuple
        return [_native(element) for element in value]
    elseif value isa Symbol
        return String(value)
    elseif ismissing(value)
        return nothing
    end
    return value
end

function _object(value, label::AbstractString)
    native = _native(value)
    native isa AbstractDict || error("$label must be a JSON object")
    return native
end

function _exact(value, fields, label::AbstractString)
    native = _object(value, label)
    Set(keys(native)) == Set(String(field) for field in fields) ||
        error("$label has an unexpected field set")
    return native
end

function _string(value, label::AbstractString)
    value isa AbstractString || error("$label must be a string")
    result = String(value)
    isempty(strip(result)) && error("$label must not be empty")
    return result
end

function _integer(value, label::AbstractString; minimum = nothing)
    value isa Integer && !(value isa Bool) ||
        error("$label must be an integer")
    result = Int(value)
    minimum === nothing || result >= minimum ||
        error("$label must be at least $minimum")
    return result
end

function _boolean(value, label::AbstractString)
    value isa Bool || error("$label must be Bool")
    return value
end

function _sha256(value, label::AbstractString)
    result = _string(value, label)
    occursin(_SHA256_PATTERN, result) ||
        error("$label must be a lowercase SHA-256 digest")
    return result
end

function _symbol(value, label::AbstractString)
    return Symbol(_string(value isa Symbol ? String(value) : value, label))
end

function ld1b_execution_context(execution_scope::Symbol)
    execution_scope === :pilot && return LD1B_PILOT_EXECUTION_CONTEXT
    execution_scope === :bounded_smoke &&
        return LD1B_BOUNDED_SMOKE_EXECUTION_CONTEXT
    error("unsupported LD1b execution scope: $execution_scope")
end

function _execution_context(value)
    native = _exact(value, _EXECUTION_CONTEXT_FIELDS, "execution context")
    context = (;
        execution_scope = _symbol(
            native["execution_scope"], "execution context scope"),
        root_namespace = _symbol(
            native["root_namespace"], "execution context root namespace"),
        official_pilot_denominator_eligible = _boolean(
            native["official_pilot_denominator_eligible"],
            "execution context official-pilot denominator eligibility"),
    )
    expected = ld1b_execution_context(context.execution_scope)
    context == expected || error(
        "execution context differs from the exact $(context.execution_scope) contract")
    return expected
end

function _identity_context(plan_identity, execution_source_identity,
        job_identity, attempt_number, attempt_role;
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    plan = _exact(plan_identity, _PLAN_FIELDS, "plan identity")
    for field in _PLAN_FIELDS
        _sha256(plan[field], "plan identity $field")
    end
    execution = _exact(execution_source_identity, _EXECUTION_FIELDS,
        "execution source identity")
    for field in _EXECUTION_FIELDS
        _sha256(execution[field], "execution source identity $field")
    end
    execution["attempt_archive_source_sha256"] ==
        Archive.ld1b_attempt_archive_source_sha256() || error(
        "execution source identity does not match the attempt-archive source")
    execution["local_json_source_sha256"] == bytes2hex(open(sha256,
        joinpath(@__DIR__, "local_json.jl"))) || error(
        "execution source identity does not match local_json.jl")
    execution["local_dependence_pilot_recovery_source_sha256"] ==
        ld1b_recovery_source_sha256() || error(
        "execution source identity does not match the recovery source")

    job = _exact(job_identity, _JOB_FIELDS, "job identity")
    job_id = _string(job["job_id"], "job identity job_id")
    (occursin('/', job_id) || occursin('\\', job_id)) &&
        error("job identity job_id must not contain a path separator")
    _integer(job["row_index"], "job identity row_index"; minimum = 1)
    _integer(job["scenario_index"], "job identity scenario_index";
        minimum = 1)
    _string(job["scenario_id"], "job identity scenario_id")
    _integer(job["replication"], "job identity replication"; minimum = 1)
    _string(job["expected_action"], "job identity expected_action")
    for field in ("seed", "fit_seed", "draw_selection_seed",
            "posterior_predictive_seed")
        _integer(job[field], "job identity $field"; minimum = 1)
    end

    checked_execution_context = _execution_context(execution_context)
    number = _integer(attempt_number, "attempt number"; minimum = 1)
    role = _symbol(attempt_role, "attempt role")
    if checked_execution_context.execution_scope === :pilot
        expected_role = number == 1 ? :primary : :remediation
        role === expected_role ||
            error("pilot attempt role does not match its number")
        counts_toward_primary = number == 1
    else
        number == 1 || error("bounded-smoke execution does not allow retries")
        role === :verification || error(
            "bounded-smoke attempt role must be verification")
        counts_toward_primary = false
    end
    attempt = (;
        number,
        role,
        counts_toward_primary,
    )
    return (;
        plan,
        plan_sha256 = Archive.ld1b_archive_canonical_sha256(plan),
        execution,
        execution_sha256 = Archive.ld1b_archive_canonical_sha256(execution),
        execution_context = checked_execution_context,
        execution_context_sha256 = Archive.ld1b_archive_canonical_sha256(
            checked_execution_context),
        job,
        job_sha256 = Archive.ld1b_archive_canonical_sha256(job),
        attempt,
    )
end

function _common_material(context, schema::AbstractString,
        object::Symbol, scope::Symbol)
    return (;
        schema,
        object,
        scope,
        recovery_source_sha256 = ld1b_recovery_source_sha256(),
        plan_identity = context.plan,
        plan_identity_sha256 = context.plan_sha256,
        execution_source_identity = context.execution,
        execution_source_identity_sha256 = context.execution_sha256,
        execution_context = context.execution_context,
        execution_context_sha256 = context.execution_context_sha256,
        job_identity = context.job,
        job_identity_sha256 = context.job_sha256,
        attempt = context.attempt,
    )
end

function _validate_common(native, context, schema, object, scope, label)
    _string(native["schema"], "$label schema") == schema ||
        error("unexpected $label schema")
    _symbol(native["object"], "$label object") === object ||
        error("unexpected $label object")
    _symbol(native["scope"], "$label scope") === scope ||
        error("unexpected $label scope")
    _sha256(native["recovery_source_sha256"],
        "$label recovery source SHA-256") == ld1b_recovery_source_sha256() ||
        error("$label recovery source identity mismatch")
    observed_execution_context = _execution_context(
        native["execution_context"])
    observed_execution_context == context.execution_context ||
        error("$label execution context mismatch")
    for (field, expected, digest_field, expected_digest) in (
            ("plan_identity", context.plan, "plan_identity_sha256",
                context.plan_sha256),
            ("execution_source_identity", context.execution,
                "execution_source_identity_sha256", context.execution_sha256),
            ("execution_context", context.execution_context,
                "execution_context_sha256",
                context.execution_context_sha256),
            ("job_identity", context.job, "job_identity_sha256",
                context.job_sha256),
        )
        observed = _object(native[field], "$label $field")
        Archive.ld1b_archive_canonical_sha256(observed) == expected_digest &&
            Archive.ld1b_archive_canonical_sha256(expected) ==
                expected_digest &&
            _sha256(native[digest_field], "$label $digest_field") ==
                expected_digest || error("$label $field mismatch")
    end
    attempt = _exact(native["attempt"],
        ("number", "role", "counts_toward_primary"), "$label attempt")
    _integer(attempt["number"], "$label attempt number") ==
        context.attempt.number &&
        _symbol(attempt["role"], "$label attempt role") ===
            context.attempt.role &&
        _boolean(attempt["counts_toward_primary"],
            "$label primary contribution") ==
            context.attempt.counts_toward_primary ||
        error("$label attempt identity mismatch")
    return true
end

function _receipt_reference(filename, file_sha256, content_hash)
    return (;
        filename,
        file_sha256 = _sha256(file_sha256, "$filename file SHA-256"),
        content_hash = _sha256(content_hash, "$filename content hash"),
    )
end

function _validate_receipt_reference(value, expected_filename,
        expected_file_sha256, expected_content_hash, label)
    reference = _exact(value,
        ("filename", "file_sha256", "content_hash"), label)
    _string(reference["filename"], "$label filename") == expected_filename &&
        _sha256(reference["file_sha256"], "$label file SHA-256") ==
            _sha256(expected_file_sha256, "expected $label file SHA-256") &&
        _sha256(reference["content_hash"], "$label content hash") ==
            _sha256(expected_content_hash, "expected $label content hash") ||
        error("$label mismatch")
    return reference
end

function _relative_archive_path(value, label::AbstractString)
    path = _string(value, label)
    isabspath(path) && error("$label must be relative")
    normalized = normpath(path)
    normalized == path && normalized != "." && normalized != ".." &&
        !startswith(normalized,
            string("..", Base.Filesystem.path_separator)) ||
        error("$label must be a normalized path within the execution root")
    return path
end

function _execution_root_relative_path(execution_root::AbstractString,
        path::AbstractString, label::AbstractString; require_file_name = nothing)
    root = normpath(abspath(execution_root))
    target = normpath(abspath(path))
    isdir(root) && !islink(root) ||
        error("execution root is not a regular directory")
    Archive._ld1b_path_within(target, root) ||
        error("$label escapes the execution root")
    require_file_name === nothing || basename(target) == require_file_name ||
        error("$label must use filename $require_file_name")
    return _relative_archive_path(relpath(target, root), label)
end

function _path_receipt_reference(filename, execution_root_relative_path,
        file_sha256, content_hash)
    return (;
        filename,
        execution_root_relative_path = _relative_archive_path(
            execution_root_relative_path,
            "$filename execution-root-relative path"),
        file_sha256 = _sha256(file_sha256, "$filename file SHA-256"),
        content_hash = _sha256(content_hash, "$filename content hash"),
    )
end

function _validate_path_receipt_reference(value, expected_filename,
        expected_execution_root_relative_path, expected_file_sha256,
        expected_content_hash, label)
    reference = _exact(value, (
        "filename", "execution_root_relative_path", "file_sha256",
        "content_hash",
    ), label)
    _string(reference["filename"], "$label filename") == expected_filename &&
        _relative_archive_path(reference["execution_root_relative_path"],
            "$label execution-root-relative path") ==
            _relative_archive_path(expected_execution_root_relative_path,
                "expected $label execution-root-relative path") &&
        _sha256(reference["file_sha256"], "$label file SHA-256") ==
            _sha256(expected_file_sha256,
                "expected $label file SHA-256") &&
        _sha256(reference["content_hash"], "$label content hash") ==
            _sha256(expected_content_hash,
                "expected $label content hash") ||
        error("$label mismatch")
    return reference
end

function ld1b_attempt_reservation(; plan_identity,
        execution_source_identity, job_identity, attempt_number, attempt_role,
        reservation_id, execution_root_relative_reservation_path,
        execution_root_relative_attempt_path, controller_host,
        controller_run_id, controller_pid, recorded_at_utc,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    context = _identity_context(plan_identity, execution_source_identity,
        job_identity, attempt_number, attempt_role; execution_context)
    checked_reservation_id = _string(reservation_id, "reservation id")
    (occursin('/', checked_reservation_id) ||
        occursin('\\', checked_reservation_id)) &&
        error("reservation id must not contain a path separator")
    relative_reservation_path = _relative_archive_path(
        execution_root_relative_reservation_path,
        "execution-root-relative reservation path")
    basename(relative_reservation_path) == LD1B_ATTEMPT_RESERVATION_FILENAME ||
        error("reservation path has the wrong filename")
    reservation = (;
        reservation_id = checked_reservation_id,
        execution_root_relative_attempt_path = _relative_archive_path(
            execution_root_relative_attempt_path,
            "execution-root-relative attempt path"),
        controller_host = _string(controller_host, "controller host"),
        controller_run_id = _string(controller_run_id, "controller run id"),
        controller_pid = _integer(controller_pid, "controller PID";
            minimum = 1),
        recorded_at_utc = _string(recorded_at_utc,
            "reservation recorded time"),
    )
    publication_contract = (;
        execution_root_relative_reservation_path = relative_reservation_path,
        exclusive_create_new = true,
        overwrite_allowed = false,
        immutable_after_publication = true,
    )
    material = merge(_common_material(context,
        LD1B_ATTEMPT_RESERVATION_SCHEMA,
        :local_dependence_pilot_attempt_reservation,
        :ld1b_attempt_path_reservation), (;
        reservation,
        publication_contract,
    ))
    return Archive.ld1b_archive_with_content_hash(material)
end

function ld1b_validate_attempt_reservation(value; plan_identity,
        execution_source_identity, job_identity, attempt_number, attempt_role,
        expected_reservation_id = nothing,
        expected_execution_root_relative_reservation_path = nothing,
        expected_execution_root_relative_attempt_path = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    native = _exact(value, (_COMMON_FIELDS..., "reservation",
        "publication_contract", "content_hash"), "attempt reservation")
    content_hash = Archive.ld1b_verify_archive_content_hash(native;
        label = "attempt reservation")
    context = _identity_context(plan_identity, execution_source_identity,
        job_identity, attempt_number, attempt_role; execution_context)
    _validate_common(native, context, LD1B_ATTEMPT_RESERVATION_SCHEMA,
        :local_dependence_pilot_attempt_reservation,
        :ld1b_attempt_path_reservation, "attempt reservation")
    reservation = _exact(native["reservation"], (
        "reservation_id", "execution_root_relative_attempt_path",
        "controller_host", "controller_run_id", "controller_pid",
        "recorded_at_utc",
    ), "attempt reservation body")
    reservation_id = _string(reservation["reservation_id"],
        "reservation id")
    (occursin('/', reservation_id) || occursin('\\', reservation_id)) &&
        error("reservation id must not contain a path separator")
    attempt_path = _relative_archive_path(
        reservation["execution_root_relative_attempt_path"],
        "execution-root-relative attempt path")
    _string(reservation["controller_host"], "controller host")
    _string(reservation["controller_run_id"], "controller run id")
    _integer(reservation["controller_pid"], "controller PID"; minimum = 1)
    _string(reservation["recorded_at_utc"], "reservation recorded time")
    contract = _exact(native["publication_contract"], (
        "execution_root_relative_reservation_path", "exclusive_create_new",
        "overwrite_allowed", "immutable_after_publication",
    ), "reservation publication contract")
    reservation_path = _relative_archive_path(
        contract["execution_root_relative_reservation_path"],
        "execution-root-relative reservation path")
    basename(reservation_path) == LD1B_ATTEMPT_RESERVATION_FILENAME ||
        error("reservation path has the wrong filename")
    _boolean(contract["exclusive_create_new"],
        "reservation exclusive CREATE_NEW contract") ||
        error("reservation does not require exclusive CREATE_NEW publication")
    !_boolean(contract["overwrite_allowed"],
        "reservation overwrite contract") ||
        error("reservation allows overwrite")
    _boolean(contract["immutable_after_publication"],
        "reservation immutability contract") ||
        error("reservation is not immutable after publication")
    expected_reservation_id === nothing || reservation_id ==
        _string(expected_reservation_id, "expected reservation id") ||
        error("reservation id mismatch")
    expected_execution_root_relative_reservation_path === nothing ||
        reservation_path == _relative_archive_path(
            expected_execution_root_relative_reservation_path,
            "expected execution-root-relative reservation path") ||
        error("reservation publication path mismatch")
    expected_execution_root_relative_attempt_path === nothing ||
        attempt_path == _relative_archive_path(
            expected_execution_root_relative_attempt_path,
            "expected execution-root-relative attempt path") ||
        error("reserved attempt path mismatch")
    return (; valid = true, native, content_hash, context, reservation,
        publication_contract = contract, reservation_id,
        execution_root_relative_reservation_path = reservation_path,
        execution_root_relative_attempt_path = attempt_path)
end

function ld1b_validate_attempt_reservation_file(
        reservation_path::AbstractString; execution_root::AbstractString,
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, expected_reservation_id = nothing,
        expected_execution_root_relative_attempt_path = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    relative_reservation_path = _execution_root_relative_path(
        execution_root, reservation_path, "attempt reservation path";
        require_file_name = LD1B_ATTEMPT_RESERVATION_FILENAME)
    snapshot = Archive._ld1b_read_json_snapshot(normpath(reservation_path),
        normpath(execution_root), "attempt reservation")
    validated = ld1b_validate_attempt_reservation(snapshot.parsed;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, expected_reservation_id,
        expected_execution_root_relative_reservation_path =
            relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    return merge(_file_result(LD1B_ATTEMPT_RESERVATION_FILENAME, snapshot,
        validated, :attempt_reserved), (;
        reservation_id = validated.reservation_id,
        execution_root_relative_reservation_path = relative_reservation_path,
        execution_root_relative_attempt_path =
            validated.execution_root_relative_attempt_path,
        controller = validated.reservation,
        context = validated.context,
    ))
end

function ld1b_publish_attempt_reservation(
        reservation_path::AbstractString; execution_root::AbstractString,
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_id,
        execution_root_relative_attempt_path, controller_host,
        controller_run_id, controller_pid, recorded_at_utc,
        staging_dir::AbstractString, _fault_injection_stage = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    relative_reservation_path = _execution_root_relative_path(
        execution_root, reservation_path, "attempt reservation path";
        require_file_name = LD1B_ATTEMPT_RESERVATION_FILENAME)
    artifact = ld1b_attempt_reservation(;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_id,
        execution_root_relative_reservation_path = relative_reservation_path,
        execution_root_relative_attempt_path, controller_host,
        controller_run_id, controller_pid, recorded_at_utc,
        execution_context)
    validator = value -> ld1b_validate_attempt_reservation(value;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role,
        expected_reservation_id = reservation_id,
        expected_execution_root_relative_reservation_path =
            relative_reservation_path,
        expected_execution_root_relative_attempt_path =
            execution_root_relative_attempt_path,
        execution_context)
    publication = Archive.ld1b_atomic_publish_json_create_new(
        reservation_path, artifact, staging_dir, execution_root;
        semantic_validator = validator,
        artifact_label = "attempt reservation",
        _fault_injection_stage)
    validated = ld1b_validate_attempt_reservation_file(reservation_path;
        execution_root, plan_identity, execution_source_identity,
        job_identity, attempt_number, attempt_role,
        expected_reservation_id = reservation_id,
        expected_execution_root_relative_attempt_path =
            execution_root_relative_attempt_path,
        execution_context)
    return (; publication...,
        reservation_id = validated.reservation_id,
        execution_root_relative_reservation_path =
            validated.execution_root_relative_reservation_path,
        execution_root_relative_attempt_path =
            validated.execution_root_relative_attempt_path,
        artifact = validated.artifact)
end

function ld1b_canonical_attempt_owner_precommit(; plan_identity,
        execution_source_identity, job_identity, attempt_number, attempt_role,
        reservation_artifact, reservation_receipt_sha256,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path, recorded_at_utc,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    reservation = ld1b_validate_attempt_reservation(reservation_artifact;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    reservation_reference = _path_receipt_reference(
        LD1B_ATTEMPT_RESERVATION_FILENAME,
        reservation.execution_root_relative_reservation_path,
        reservation_receipt_sha256, reservation.content_hash)
    owner = (;
        controller_host = _string(
            reservation.reservation["controller_host"], "controller host"),
        controller_run_id = _string(
            reservation.reservation["controller_run_id"],
            "controller run id"),
        controller_pid = _integer(
            reservation.reservation["controller_pid"], "controller PID";
            minimum = 1),
        recorded_at_utc = _string(recorded_at_utc, "owner recorded time"),
        published_after_reservation = true,
        published_before_child_launch = true,
    )
    material = merge(_common_material(reservation.context,
        LD1B_CANONICAL_ATTEMPT_OWNER_SCHEMA,
        :local_dependence_pilot_reserved_attempt_owner_precommit,
        :ld1b_attempt_process_ownership), (;
        reservation_receipt = reservation_reference,
        owner,
    ))
    return Archive.ld1b_archive_with_content_hash(material)
end

function ld1b_validate_canonical_attempt_owner_precommit(value;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_artifact,
        reservation_receipt_sha256, expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    native = _exact(value, (_COMMON_FIELDS..., "reservation_receipt",
        "owner", "content_hash"), "canonical attempt-owner precommit")
    content_hash = Archive.ld1b_verify_archive_content_hash(native;
        label = "canonical attempt-owner precommit")
    reservation = ld1b_validate_attempt_reservation(reservation_artifact;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    _validate_common(native, reservation.context,
        LD1B_CANONICAL_ATTEMPT_OWNER_SCHEMA,
        :local_dependence_pilot_reserved_attempt_owner_precommit,
        :ld1b_attempt_process_ownership,
        "canonical attempt-owner precommit")
    reservation_reference = _validate_path_receipt_reference(
        native["reservation_receipt"], LD1B_ATTEMPT_RESERVATION_FILENAME,
        reservation.execution_root_relative_reservation_path,
        reservation_receipt_sha256, reservation.content_hash,
        "reservation receipt reference")
    owner = _exact(native["owner"], (
        "controller_host", "controller_run_id", "controller_pid",
        "recorded_at_utc", "published_after_reservation",
        "published_before_child_launch",
    ), "canonical attempt owner")
    for field in ("controller_host", "controller_run_id")
        _string(owner[field], "owner $field") ==
            _string(reservation.reservation[field], "reservation $field") ||
            error("canonical owner does not match its reservation")
    end
    _integer(owner["controller_pid"], "owner controller PID"; minimum = 1) ==
        _integer(reservation.reservation["controller_pid"],
            "reservation controller PID"; minimum = 1) ||
        error("canonical owner does not match its reservation")
    _string(owner["recorded_at_utc"], "owner recorded time")
    _boolean(owner["published_after_reservation"],
        "owner post-reservation publication") ||
        error("canonical owner was not published after reservation")
    _boolean(owner["published_before_child_launch"],
        "owner pre-launch publication") ||
        error("canonical owner was not published before child launch")
    return (; valid = true, native, content_hash,
        context = reservation.context, owner, reservation,
        reservation_reference)
end

function _validate_attempt_owner_precommit_lineage(value; plan_identity,
        execution_source_identity, job_identity, attempt_number, attempt_role,
        reservation_artifact = nothing, reservation_receipt_sha256 = nothing,
        expected_reservation_id = nothing,
        expected_execution_root_relative_reservation_path = nothing,
        expected_execution_root_relative_attempt_path = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    native = _object(value, "attempt-owner precommit")
    schema = _string(get(native, "schema", nothing),
        "attempt-owner precommit schema")
    reservation_arguments = (
        reservation_artifact,
        reservation_receipt_sha256,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
    )
    if schema == LD1B_ATTEMPT_OWNER_SCHEMA
        all(isnothing, reservation_arguments) || error(
            "unreserved owner cannot be validated as reservation-bound")
        return ld1b_validate_attempt_owner_precommit(value;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role, execution_context)
    elseif schema == LD1B_CANONICAL_ATTEMPT_OWNER_SCHEMA
        all(argument -> argument !== nothing, reservation_arguments) || error(
            "canonical owner validation requires complete reservation lineage")
        return ld1b_validate_canonical_attempt_owner_precommit(value;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role, reservation_artifact,
            reservation_receipt_sha256, expected_reservation_id,
            expected_execution_root_relative_reservation_path,
            expected_execution_root_relative_attempt_path,
            execution_context)
    end
    error("unsupported attempt-owner precommit schema")
end

function ld1b_attempt_owner_precommit(; plan_identity,
        execution_source_identity, job_identity, attempt_number, attempt_role,
        controller_host, controller_run_id, controller_pid,
        recorded_at_utc,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    context = _identity_context(plan_identity, execution_source_identity,
        job_identity, attempt_number, attempt_role; execution_context)
    owner = (;
        controller_host = _string(controller_host, "controller host"),
        controller_run_id = _string(controller_run_id, "controller run id"),
        controller_pid = _integer(controller_pid, "controller PID";
            minimum = 1),
        recorded_at_utc = _string(recorded_at_utc, "owner recorded time"),
        published_before_child_launch = true,
    )
    material = merge(_common_material(context, LD1B_ATTEMPT_OWNER_SCHEMA,
        :local_dependence_pilot_attempt_owner_precommit,
        :ld1b_attempt_process_ownership), (; owner))
    return Archive.ld1b_archive_with_content_hash(material)
end

function ld1b_validate_attempt_owner_precommit(value; plan_identity,
        execution_source_identity, job_identity, attempt_number, attempt_role,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    fields = (_COMMON_FIELDS..., "owner", "content_hash")
    native = _exact(value, fields, "attempt-owner precommit")
    content_hash = Archive.ld1b_verify_archive_content_hash(native;
        label = "attempt-owner precommit")
    context = _identity_context(plan_identity, execution_source_identity,
        job_identity, attempt_number, attempt_role; execution_context)
    _validate_common(native, context, LD1B_ATTEMPT_OWNER_SCHEMA,
        :local_dependence_pilot_attempt_owner_precommit,
        :ld1b_attempt_process_ownership, "attempt-owner precommit")
    owner = _exact(native["owner"], (
        "controller_host", "controller_run_id", "controller_pid",
        "recorded_at_utc", "published_before_child_launch",
    ), "attempt owner")
    _string(owner["controller_host"], "controller host")
    _string(owner["controller_run_id"], "controller run id")
    _integer(owner["controller_pid"], "controller PID"; minimum = 1)
    _string(owner["recorded_at_utc"], "owner recorded time")
    _boolean(owner["published_before_child_launch"],
        "owner pre-launch publication") ||
        error("owner receipt was not published before child launch")
    return (; valid = true, native, content_hash, context, owner)
end

function ld1b_child_launch_receipt(; plan_identity,
        execution_source_identity, job_identity, attempt_number, attempt_role,
        owner_artifact, owner_receipt_sha256, child_pid, recorded_at_utc,
        reservation_artifact = nothing, reservation_receipt_sha256 = nothing,
        expected_reservation_id = nothing,
        expected_execution_root_relative_reservation_path = nothing,
        expected_execution_root_relative_attempt_path = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    owner = _validate_attempt_owner_precommit_lineage(owner_artifact;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_artifact,
        reservation_receipt_sha256, expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    context = owner.context
    owner_reference = _receipt_reference(LD1B_ATTEMPT_OWNER_FILENAME,
        owner_receipt_sha256, owner.content_hash)
    launch = (;
        controller_host = _string(owner.owner["controller_host"],
            "controller host"),
        controller_run_id = _string(owner.owner["controller_run_id"],
            "controller run id"),
        controller_pid = _integer(owner.owner["controller_pid"],
            "controller PID"; minimum = 1),
        child_pid = _integer(child_pid, "child PID"; minimum = 1),
        recorded_at_utc = _string(recorded_at_utc, "launch recorded time"),
        child_launch_observed = true,
    )
    material = merge(_common_material(context, LD1B_CHILD_LAUNCH_SCHEMA,
        :local_dependence_pilot_child_launch_receipt,
        :ld1b_attempt_child_launch), (; owner_receipt = owner_reference, launch))
    return Archive.ld1b_archive_with_content_hash(material)
end

function ld1b_validate_child_launch_receipt(value; plan_identity,
        execution_source_identity, job_identity, attempt_number, attempt_role,
        owner_artifact, owner_receipt_sha256,
        reservation_artifact = nothing, reservation_receipt_sha256 = nothing,
        expected_reservation_id = nothing,
        expected_execution_root_relative_reservation_path = nothing,
        expected_execution_root_relative_attempt_path = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    native = _exact(value,
        (_COMMON_FIELDS..., "owner_receipt", "launch", "content_hash"),
        "child-launch receipt")
    content_hash = Archive.ld1b_verify_archive_content_hash(native;
        label = "child-launch receipt")
    owner = _validate_attempt_owner_precommit_lineage(owner_artifact;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_artifact,
        reservation_receipt_sha256, expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    context = owner.context
    _validate_common(native, context, LD1B_CHILD_LAUNCH_SCHEMA,
        :local_dependence_pilot_child_launch_receipt,
        :ld1b_attempt_child_launch, "child-launch receipt")
    owner_reference = _validate_receipt_reference(native["owner_receipt"],
        LD1B_ATTEMPT_OWNER_FILENAME, owner_receipt_sha256,
        owner.content_hash, "owner receipt reference")
    launch = _exact(native["launch"], (
        "controller_host", "controller_run_id", "controller_pid",
        "child_pid", "recorded_at_utc", "child_launch_observed",
    ), "child launch")
    _string(launch["controller_host"], "launch controller host") ==
        _string(owner.owner["controller_host"], "owner controller host") &&
        _string(launch["controller_run_id"], "launch controller run id") ==
            _string(owner.owner["controller_run_id"], "owner run id") &&
        _integer(launch["controller_pid"], "launch controller PID";
            minimum = 1) == _integer(owner.owner["controller_pid"],
            "owner controller PID"; minimum = 1) ||
        error("child launch does not match its owner")
    _integer(launch["child_pid"], "child PID"; minimum = 1)
    _string(launch["recorded_at_utc"], "launch recorded time")
    _boolean(launch["child_launch_observed"], "child launch observation") ||
        error("child launch was not observed")
    return (; valid = true, native, content_hash, context, owner_reference,
        launch)
end

function ld1b_child_exit_receipt(; plan_identity,
        execution_source_identity, job_identity, attempt_number, attempt_role,
        owner_artifact, owner_receipt_sha256, launch_artifact,
        launch_receipt_sha256, exit_code, recorded_at_utc,
        reservation_artifact = nothing, reservation_receipt_sha256 = nothing,
        expected_reservation_id = nothing,
        expected_execution_root_relative_reservation_path = nothing,
        expected_execution_root_relative_attempt_path = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    launch = ld1b_validate_child_launch_receipt(launch_artifact;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, owner_artifact, owner_receipt_sha256,
        reservation_artifact, reservation_receipt_sha256,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    owner_reference = _receipt_reference(LD1B_ATTEMPT_OWNER_FILENAME,
        owner_receipt_sha256,
        Archive.ld1b_verify_archive_content_hash(owner_artifact;
            label = "attempt-owner precommit"))
    launch_reference = _receipt_reference(LD1B_CHILD_LAUNCH_FILENAME,
        launch_receipt_sha256, launch.content_hash)
    exit = (;
        controller_host = _string(launch.launch["controller_host"],
            "controller host"),
        controller_run_id = _string(launch.launch["controller_run_id"],
            "controller run id"),
        controller_pid = _integer(launch.launch["controller_pid"],
            "controller PID"; minimum = 1),
        child_pid = _integer(launch.launch["child_pid"], "child PID";
            minimum = 1),
        exit_code = _integer(exit_code, "child exit code"),
        recorded_at_utc = _string(recorded_at_utc, "exit recorded time"),
        controller_wait_observed = true,
        child_exit_observed = true,
    )
    material = merge(_common_material(launch.context,
        LD1B_CHILD_EXIT_SCHEMA, :local_dependence_pilot_child_exit_receipt,
        :ld1b_attempt_child_exit), (;
        owner_receipt = owner_reference,
        launch_receipt = launch_reference,
        exit,
    ))
    return Archive.ld1b_archive_with_content_hash(material)
end

function ld1b_validate_child_exit_receipt(value; plan_identity,
        execution_source_identity, job_identity, attempt_number, attempt_role,
        owner_artifact, owner_receipt_sha256, launch_artifact,
        launch_receipt_sha256, reservation_artifact = nothing,
        reservation_receipt_sha256 = nothing,
        expected_reservation_id = nothing,
        expected_execution_root_relative_reservation_path = nothing,
        expected_execution_root_relative_attempt_path = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    native = _exact(value, (_COMMON_FIELDS..., "owner_receipt",
        "launch_receipt", "exit", "content_hash"), "child-exit receipt")
    content_hash = Archive.ld1b_verify_archive_content_hash(native;
        label = "child-exit receipt")
    owner = _validate_attempt_owner_precommit_lineage(owner_artifact;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_artifact,
        reservation_receipt_sha256, expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    launch = ld1b_validate_child_launch_receipt(launch_artifact;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, owner_artifact, owner_receipt_sha256,
        reservation_artifact, reservation_receipt_sha256,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    _validate_common(native, launch.context, LD1B_CHILD_EXIT_SCHEMA,
        :local_dependence_pilot_child_exit_receipt,
        :ld1b_attempt_child_exit, "child-exit receipt")
    owner_reference = _validate_receipt_reference(native["owner_receipt"],
        LD1B_ATTEMPT_OWNER_FILENAME, owner_receipt_sha256,
        owner.content_hash, "owner receipt reference")
    launch_reference = _validate_receipt_reference(native["launch_receipt"],
        LD1B_CHILD_LAUNCH_FILENAME, launch_receipt_sha256,
        launch.content_hash, "launch receipt reference")
    exit = _exact(native["exit"], (
        "controller_host", "controller_run_id", "controller_pid", "child_pid",
        "exit_code", "recorded_at_utc", "controller_wait_observed",
        "child_exit_observed",
    ), "child exit")
    for field in ("controller_host", "controller_run_id")
        _string(exit[field], "exit $field") ==
            _string(launch.launch[field], "launch $field") ||
            error("child exit does not match its launch")
    end
    for field in ("controller_pid", "child_pid")
        _integer(exit[field], "exit $field"; minimum = 1) ==
            _integer(launch.launch[field], "launch $field"; minimum = 1) ||
            error("child exit does not match its launch")
    end
    exit_code = _integer(exit["exit_code"], "child exit code")
    _string(exit["recorded_at_utc"], "exit recorded time")
    _boolean(exit["controller_wait_observed"],
        "controller wait observation") || error("child wait was not observed")
    _boolean(exit["child_exit_observed"], "child exit observation") ||
        error("child exit was not observed")
    return (; valid = true, native, content_hash, context = launch.context,
        owner_reference, launch_reference, exit, exit_code)
end

function ld1b_inventory_before_interruption_review(
        attempt_dir::AbstractString)
    rows = Archive.ld1b_attempt_inventory(attempt_dir;
        exclude = _REVIEW_INVENTORY_EXCLUSIONS)
    return (;
        excluded_control_files = _REVIEW_INVENTORY_EXCLUSIONS,
        n_files = count(row -> row.kind === :file, rows),
        n_directories = count(row -> row.kind === :directory, rows),
        total_file_bytes = sum((row.bytes for row in rows
            if row.kind === :file); init = 0),
        rows = Tuple(rows),
        rows_sha256 = Archive.ld1b_archive_canonical_sha256(rows),
    )
end

function _validate_inventory(value;
        expected_exclusions = _REVIEW_INVENTORY_EXCLUSIONS,
        label::AbstractString = "pre-review inventory")
    inventory = _exact(value, (
        "excluded_control_files", "n_files", "n_directories",
        "total_file_bytes", "rows", "rows_sha256",
    ), label)
    Tuple(_string(item, "inventory exclusion")
        for item in inventory["excluded_control_files"]) ==
        expected_exclusions ||
        error("pre-review inventory has the wrong exclusions")
    rows = Any[]
    keys_seen = Set{Tuple{String,Symbol}}()
    for (index, value) in pairs(inventory["rows"])
        row = _exact(value,
            ("path", "kind", "bytes", "sha256", "link_count"),
            "inventory row $index")
        path = _string(row["path"], "inventory path")
        isabspath(path) && error("inventory path must be relative")
        normalized = normpath(path)
        normalized == path && normalized != ".." &&
            !startswith(normalized,
                string("..", Base.Filesystem.path_separator)) ||
            error("inventory path escapes the attempt")
        kind = _symbol(row["kind"], "inventory kind")
        kind in (:file, :directory) || error("unsupported inventory kind")
        key = (path, kind)
        key in keys_seen && error("duplicate pre-review inventory row")
        push!(keys_seen, key)
        bytes = _integer(row["bytes"], "inventory bytes"; minimum = 0)
        if kind === :file
            sha = _sha256(row["sha256"], "inventory file SHA-256")
            link_count = _integer(row["link_count"], "inventory link count";
                minimum = 1)
            link_count == 1 || error("inventory file must not be hard linked")
            push!(rows, (; path, kind, bytes, sha256 = sha, link_count))
        else
            bytes == 0 && row["sha256"] === nothing &&
                row["link_count"] === nothing ||
                error("directory inventory row has file metadata")
            push!(rows, (; path, kind, bytes, sha256 = nothing,
                link_count = nothing))
        end
    end
    sort_keys = [(row.path, String(row.kind)) for row in rows]
    issorted(sort_keys) || error("pre-review inventory rows are not sorted")
    n_files = count(row -> row.kind === :file, rows)
    n_directories = count(row -> row.kind === :directory, rows)
    total_file_bytes = sum((row.bytes for row in rows
        if row.kind === :file); init = 0)
    _integer(inventory["n_files"], "inventory file count"; minimum = 0) ==
        n_files && _integer(inventory["n_directories"],
        "inventory directory count"; minimum = 0) == n_directories &&
        _integer(inventory["total_file_bytes"], "inventory total bytes";
            minimum = 0) == total_file_bytes ||
        error("pre-review inventory counts do not match its rows")
    rows_sha256 = _sha256(inventory["rows_sha256"],
        "inventory rows SHA-256")
    rows_sha256 == Archive.ld1b_archive_canonical_sha256(rows) ||
        error("pre-review inventory rows SHA-256 mismatch")
    return (; native = inventory, rows = Tuple(rows), rows_sha256,
        n_files, n_directories, total_file_bytes)
end

function ld1b_inventory_before_precommit_interruption_review(
        attempt_dir::AbstractString)
    rows = Archive.ld1b_attempt_inventory(attempt_dir;
        exclude = _PRECOMMIT_REVIEW_INVENTORY_EXCLUSIONS)
    return (;
        excluded_control_files = _PRECOMMIT_REVIEW_INVENTORY_EXCLUSIONS,
        n_files = count(row -> row.kind === :file, rows),
        n_directories = count(row -> row.kind === :directory, rows),
        total_file_bytes = sum((row.bytes for row in rows
            if row.kind === :file); init = 0),
        rows = Tuple(rows),
        rows_sha256 = Archive.ld1b_archive_canonical_sha256(rows),
    )
end

function _require_precommit_inventory_state(inventory, owner_present::Bool)
    owner_rows = [row for row in inventory.rows
        if row.kind === :file && row.path == LD1B_ATTEMPT_OWNER_FILENAME]
    length(owner_rows) == (owner_present ? 1 : 0) || error(
        "precommit inventory owner presence disagrees with review state")
    forbidden = (
        LD1B_CHILD_LAUNCH_FILENAME,
        LD1B_CHILD_EXIT_FILENAME,
        _RESULT_FILENAME,
        Archive.LD1B_ATTEMPT_SEAL_FILENAME,
        Archive.LD1B_ATTEMPT_RETIREMENT_FILENAME,
        LD1B_INTERRUPTION_REVIEW_FILENAME,
    )
    for filename in forbidden
        any(row -> row.kind === :file && row.path == filename,
            inventory.rows) && error(
            "precommit interruption inventory contains forbidden $filename")
    end
    return true
end

function _precommit_reason(reason, owner_present::Bool)
    checked = _symbol(reason, "precommit interruption reason code")
    checked in _PRECOMMIT_REVIEW_REASONS ||
        error("unsupported precommit interruption reason")
    expected = owner_present ?
        :interrupted_after_owner_before_launch_receipt :
        :interrupted_after_reservation_before_owner
    checked === expected || error(
        "precommit interruption reason disagrees with owner presence")
    return checked
end

function ld1b_precommit_interruption_review(; plan_identity,
        execution_source_identity, job_identity, attempt_number, attempt_role,
        reservation_artifact, reservation_receipt_sha256,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        owner_artifact = nothing, owner_receipt_sha256 = nothing,
        inventory_before_review, reason_code, review_host, reviewer,
        reviewed_at_utc, controller_confirmed_stopped::Bool,
        child_launch_receipt_confirmed_absent::Bool,
        child_process_confirmed_stopped::Bool,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    controller_confirmed_stopped ||
        error("precommit review requires a stopped controller confirmation")
    child_launch_receipt_confirmed_absent || error(
        "precommit review requires launch-receipt absence confirmation")
    child_process_confirmed_stopped || error(
        "precommit review requires a stopped child-process confirmation")
    reservation = ld1b_validate_attempt_reservation(reservation_artifact;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    reservation_reference = _path_receipt_reference(
        LD1B_ATTEMPT_RESERVATION_FILENAME,
        reservation.execution_root_relative_reservation_path,
        reservation_receipt_sha256, reservation.content_hash)
    owner_inputs_present = owner_artifact !== nothing ||
        owner_receipt_sha256 !== nothing
    (owner_artifact === nothing) == (owner_receipt_sha256 === nothing) ||
        error("owner artifact and file SHA-256 must be supplied together")
    owner = nothing
    owner_reference = nothing
    if owner_inputs_present
        owner = ld1b_validate_canonical_attempt_owner_precommit(
            owner_artifact;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role, reservation_artifact,
            reservation_receipt_sha256, expected_reservation_id,
            expected_execution_root_relative_reservation_path,
            expected_execution_root_relative_attempt_path,
            execution_context)
        owner_reference = _receipt_reference(LD1B_ATTEMPT_OWNER_FILENAME,
            owner_receipt_sha256, owner.content_hash)
    end
    inventory = _validate_inventory(inventory_before_review;
        expected_exclusions = _PRECOMMIT_REVIEW_INVENTORY_EXCLUSIONS,
        label = "precommit review inventory")
    _require_precommit_inventory_state(inventory, owner_inputs_present)
    if owner_reference !== nothing
        _require_receipt_inventory_row(inventory,
            _native(owner_reference), "canonical owner receipt")
    end
    checked_reason = _precommit_reason(reason_code, owner_inputs_present)
    receipt_lineage = (;
        reservation = reservation_reference,
        owner = owner_reference,
    )
    attempt_state = (;
        reservation_present = true,
        owner_present = owner_inputs_present,
        child_launch_receipt_present = false,
        science_execution_authorized = false,
        job_result_present = false,
        scientific_contribution = 0,
    )
    review = (;
        reason_code = checked_reason,
        review_host = _string(review_host, "precommit review host"),
        reviewer = _string(reviewer, "precommit reviewer"),
        reviewed_at_utc = _string(reviewed_at_utc,
            "precommit review time"),
        controller_confirmed_stopped = true,
        child_launch_receipt_confirmed_absent = true,
        child_process_confirmed_stopped = true,
        os_process_inspection_performed_by_artifact_code = false,
    )
    material = merge(_common_material(reservation.context,
        LD1B_PRECOMMIT_INTERRUPTION_REVIEW_SCHEMA,
        :local_dependence_pilot_precommit_interruption_review,
        :ld1b_precommit_interruption_recovery), (;
        receipt_lineage,
        attempt_state,
        inventory_before_review = inventory.native,
        review,
    ))
    return Archive.ld1b_archive_with_content_hash(material)
end

function ld1b_validate_precommit_interruption_review(value;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_artifact,
        reservation_receipt_sha256, expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        owner_artifact = nothing, owner_receipt_sha256 = nothing,
        expected_inventory_before_review = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    native = _exact(value, (_COMMON_FIELDS..., "receipt_lineage",
        "attempt_state", "inventory_before_review", "review",
        "content_hash"), "precommit interruption review")
    content_hash = Archive.ld1b_verify_archive_content_hash(native;
        label = "precommit interruption review")
    reservation = ld1b_validate_attempt_reservation(reservation_artifact;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    _validate_common(native, reservation.context,
        LD1B_PRECOMMIT_INTERRUPTION_REVIEW_SCHEMA,
        :local_dependence_pilot_precommit_interruption_review,
        :ld1b_precommit_interruption_recovery,
        "precommit interruption review")
    lineage = _exact(native["receipt_lineage"],
        ("reservation", "owner"), "precommit receipt lineage")
    reservation_reference = _validate_path_receipt_reference(
        lineage["reservation"], LD1B_ATTEMPT_RESERVATION_FILENAME,
        reservation.execution_root_relative_reservation_path,
        reservation_receipt_sha256, reservation.content_hash,
        "reservation receipt reference")
    state = _exact(native["attempt_state"], (
        "reservation_present", "owner_present",
        "child_launch_receipt_present", "science_execution_authorized",
        "job_result_present", "scientific_contribution",
    ), "precommit attempt state")
    _boolean(state["reservation_present"], "reservation presence") ||
        error("precommit review does not record a reservation")
    owner_present = _boolean(state["owner_present"], "owner presence")
    !_boolean(state["child_launch_receipt_present"],
        "child-launch receipt presence") ||
        error("precommit review records a child-launch receipt")
    !_boolean(state["science_execution_authorized"],
        "science execution authorization") ||
        error("precommit interruption cannot authorize science execution")
    !_boolean(state["job_result_present"], "job-result presence") ||
        error("precommit review records a job result")
    _integer(state["scientific_contribution"],
        "precommit scientific contribution"; minimum = 0) == 0 ||
        error("precommit interruption must contribute zero scientific jobs")
    owner_inputs_present = owner_artifact !== nothing ||
        owner_receipt_sha256 !== nothing
    (owner_artifact === nothing) == (owner_receipt_sha256 === nothing) ||
        error("owner artifact and file SHA-256 must be supplied together")
    owner_inputs_present == owner_present ||
        error("owner lineage disagrees with precommit attempt state")
    owner_reference = nothing
    if owner_present
        owner = ld1b_validate_canonical_attempt_owner_precommit(
            owner_artifact;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role, reservation_artifact,
            reservation_receipt_sha256, expected_reservation_id,
            expected_execution_root_relative_reservation_path,
            expected_execution_root_relative_attempt_path,
            execution_context)
        owner_reference = _validate_receipt_reference(lineage["owner"],
            LD1B_ATTEMPT_OWNER_FILENAME, owner_receipt_sha256,
            owner.content_hash, "canonical owner receipt reference")
    else
        lineage["owner"] === nothing ||
            error("reservation-only review contains an owner reference")
    end
    inventory = _validate_inventory(native["inventory_before_review"];
        expected_exclusions = _PRECOMMIT_REVIEW_INVENTORY_EXCLUSIONS,
        label = "precommit review inventory")
    _require_precommit_inventory_state(inventory, owner_present)
    if owner_reference !== nothing
        _require_receipt_inventory_row(inventory, owner_reference,
            "canonical owner receipt")
    end
    review = _exact(native["review"], (
        "reason_code", "review_host", "reviewer", "reviewed_at_utc",
        "controller_confirmed_stopped",
        "child_launch_receipt_confirmed_absent",
        "child_process_confirmed_stopped",
        "os_process_inspection_performed_by_artifact_code",
    ), "precommit review body")
    reason_code = _precommit_reason(review["reason_code"], owner_present)
    _string(review["review_host"], "precommit review host")
    _string(review["reviewer"], "precommit reviewer")
    _string(review["reviewed_at_utc"], "precommit review time")
    _boolean(review["controller_confirmed_stopped"],
        "controller stopped confirmation") ||
        error("precommit controller is not confirmed stopped")
    _boolean(review["child_launch_receipt_confirmed_absent"],
        "child-launch receipt absence confirmation") ||
        error("child-launch receipt is not confirmed absent")
    _boolean(review["child_process_confirmed_stopped"],
        "child-process stopped confirmation") ||
        error("child process is not confirmed stopped")
    !_boolean(review["os_process_inspection_performed_by_artifact_code"],
        "precommit artifact OS inspection claim") ||
        error("precommit artifact must not claim OS process inspection")
    if expected_inventory_before_review !== nothing
        expected = _validate_inventory(expected_inventory_before_review;
            expected_exclusions = _PRECOMMIT_REVIEW_INVENTORY_EXCLUSIONS,
            label = "expected precommit review inventory")
        Archive.ld1b_archive_canonical_sha256(inventory.native) ==
            Archive.ld1b_archive_canonical_sha256(expected.native) ||
            error("precommit inventory differs from the expected snapshot")
    end
    return (; valid = true, native, content_hash,
        context = reservation.context, reservation_reference,
        owner_reference, owner_present, reason_code,
        scientific_contribution = 0,
        inventory_rows_sha256 = inventory.rows_sha256)
end

function _require_receipt_inventory_row(inventory, reference, label)
    filename = String(reference["filename"])
    matches = [row for row in inventory.rows
        if row.kind === :file && row.path == filename]
    length(matches) == 1 || error("$label is absent from pre-review inventory")
    only(matches).sha256 == String(reference["file_sha256"]) ||
        error("$label inventory SHA-256 mismatch")
    return true
end

function _validate_observed_attempt_state(value)
    state = _exact(value, (
        "result_present", "result_file_sha256",
        "result_semantic_assessment",
    ), "observed attempt state")
    result_present = _boolean(state["result_present"],
        "observed result presence")
    assessment = _symbol(state["result_semantic_assessment"],
        "result semantic assessment")
    assessment in values(_RETIREMENT_REASON_ASSESSMENTS) ||
        error("unsupported result semantic assessment")
    result_sha256 = if result_present
        _sha256(state["result_file_sha256"], "observed result file SHA-256")
    else
        state["result_file_sha256"] === nothing ||
            error("absent result must not have a file SHA-256")
        nothing
    end
    (assessment === :result_absent) == !result_present ||
        error("result presence and semantic assessment disagree")
    return (; native = state, result_present,
        result_file_sha256 = result_sha256,
        result_semantic_assessment = assessment)
end

function _validate_reason_state(reason, state)
    checked_reason = _symbol(reason, "retirement reason code")
    haskey(_RETIREMENT_REASON_ASSESSMENTS, checked_reason) ||
        error("unsupported launched-attempt retirement reason")
    _RETIREMENT_REASON_ASSESSMENTS[checked_reason] ===
        state.result_semantic_assessment ||
        error("retirement reason disagrees with the observed attempt state")
    return checked_reason
end

function _require_result_inventory_state(inventory, state)
    matches = [row for row in inventory.rows
        if row.kind === :file && row.path == _RESULT_FILENAME]
    if state.result_present
        length(matches) == 1 ||
            error("observed job result is absent from pre-review inventory")
        only(matches).sha256 == state.result_file_sha256 ||
            error("observed job-result inventory SHA-256 mismatch")
    else
        isempty(matches) ||
            error("result-absent review contains a job result in inventory")
    end
    return true
end

function _snapshot_observed_attempt_state(attempt_dir::AbstractString,
        result_semantic_assessment)
    assessment = _symbol(result_semantic_assessment,
        "result semantic assessment")
    assessment in values(_RETIREMENT_REASON_ASSESSMENTS) ||
        error("unsupported result semantic assessment")
    result_path = joinpath(attempt_dir, _RESULT_FILENAME)
    occupied = ispath(result_path) || islink(result_path)
    if assessment === :result_absent
        occupied && error("result-absent assessment conflicts with job_result.json")
        return (;
            result_present = false,
            result_file_sha256 = nothing,
            result_semantic_assessment = assessment,
        )
    end
    occupied || error("result-present assessment lacks job_result.json")
    snapshot = Archive._ld1b_regular_file_snapshot(
        result_path, attempt_dir, "observed unsealed job result")
    return (;
        result_present = true,
        result_file_sha256 = snapshot.sha256,
        result_semantic_assessment = assessment,
    )
end

function _external_review(value)
    review = _exact(value, (
        "evidence_source", "controller_process_identity",
        "child_process_identity", "observed_at_utc",
    ), "external process-identity review")
    for field in keys(review)
        _string(review[field], "external process review $field")
    end
    return review
end

function ld1b_stopped_process_interruption_review(; plan_identity,
        execution_source_identity, job_identity, attempt_number, attempt_role,
        owner_artifact, owner_receipt_sha256, launch_artifact,
        launch_receipt_sha256, inventory_before_review,
        mode, review_host, reviewer, reviewed_at_utc,
        retirement_reason_code, observed_attempt_state,
        controller_confirmed_stopped::Bool,
        child_confirmed_stopped::Bool,
        exit_artifact = nothing, exit_receipt_sha256 = nothing,
        external_process_identity_review = nothing,
        reservation_artifact = nothing, reservation_receipt_sha256 = nothing,
        expected_reservation_id = nothing,
        expected_execution_root_relative_reservation_path = nothing,
        expected_execution_root_relative_attempt_path = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    controller_confirmed_stopped && child_confirmed_stopped ||
        error("interruption review requires both stopped confirmations")
    owner = _validate_attempt_owner_precommit_lineage(owner_artifact;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_artifact,
        reservation_receipt_sha256, expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    launch = ld1b_validate_child_launch_receipt(launch_artifact;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, owner_artifact, owner_receipt_sha256,
        reservation_artifact, reservation_receipt_sha256,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    owner_reference = _receipt_reference(LD1B_ATTEMPT_OWNER_FILENAME,
        owner_receipt_sha256, owner.content_hash)
    launch_reference = _receipt_reference(LD1B_CHILD_LAUNCH_FILENAME,
        launch_receipt_sha256, launch.content_hash)
    checked_mode = _symbol(mode, "interruption review mode")
    checked_mode in _REVIEW_MODES || error("unsupported review mode")
    exit_reference = nothing
    external = nothing
    if checked_mode === :validated_exit_receipt
        exit_artifact === nothing && error("validated exit receipt is missing")
        exit_receipt_sha256 === nothing && error(
            "validated exit-receipt file SHA-256 is missing")
        external_process_identity_review === nothing || error(
            "validated-exit mode cannot contain external process review")
        exit = ld1b_validate_child_exit_receipt(exit_artifact;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role, owner_artifact,
            owner_receipt_sha256, launch_artifact, launch_receipt_sha256,
            reservation_artifact, reservation_receipt_sha256,
            expected_reservation_id,
            expected_execution_root_relative_reservation_path,
            expected_execution_root_relative_attempt_path,
            execution_context)
        exit_reference = _receipt_reference(LD1B_CHILD_EXIT_FILENAME,
            exit_receipt_sha256, exit.content_hash)
    else
        exit_artifact === nothing && exit_receipt_sha256 === nothing ||
            error("external-review mode cannot bind an exit receipt")
        external_process_identity_review === nothing &&
            error("external process-identity review is missing")
        external = _external_review(external_process_identity_review)
    end
    inventory = _validate_inventory(inventory_before_review)
    observed_state = _validate_observed_attempt_state(observed_attempt_state)
    reason = _validate_reason_state(retirement_reason_code, observed_state)
    _require_receipt_inventory_row(inventory, _native(owner_reference),
        "owner receipt")
    _require_receipt_inventory_row(inventory, _native(launch_reference),
        "launch receipt")
    if exit_reference === nothing
        any(row -> row.kind === :file &&
            row.path == LD1B_CHILD_EXIT_FILENAME, inventory.rows) &&
            error("external review cannot ignore an exit receipt")
    else
        _require_receipt_inventory_row(inventory, _native(exit_reference),
            "exit receipt")
    end
    _require_result_inventory_state(inventory, observed_state)
    review = (;
        mode = checked_mode,
        retirement_reason_code = reason,
        review_host = _string(review_host, "review host"),
        reviewer = _string(reviewer, "reviewer"),
        reviewed_at_utc = _string(reviewed_at_utc, "review time"),
        controller_confirmed_stopped = true,
        child_confirmed_stopped = true,
        external_process_identity_review = external,
        os_process_inspection_performed_by_artifact_code = false,
    )
    receipt_lineage = (;
        owner = owner_reference,
        launch = launch_reference,
        exit = exit_reference,
    )
    material = merge(_common_material(launch.context,
        LD1B_INTERRUPTION_REVIEW_SCHEMA,
        :local_dependence_pilot_stopped_process_interruption_review,
        :ld1b_interrupted_attempt_review), (;
        receipt_lineage,
        observed_attempt_state = observed_state.native,
        inventory_before_review = inventory.native,
        review,
    ))
    return Archive.ld1b_archive_with_content_hash(material)
end

function ld1b_validate_stopped_process_interruption_review(value;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, owner_artifact,
        owner_receipt_sha256, launch_artifact, launch_receipt_sha256,
        exit_artifact = nothing, exit_receipt_sha256 = nothing,
        expected_inventory_before_review = nothing,
        reservation_artifact = nothing, reservation_receipt_sha256 = nothing,
        expected_reservation_id = nothing,
        expected_execution_root_relative_reservation_path = nothing,
        expected_execution_root_relative_attempt_path = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    native = _exact(value, (_COMMON_FIELDS..., "receipt_lineage",
        "observed_attempt_state", "inventory_before_review", "review",
        "content_hash"),
        "stopped-process interruption review")
    content_hash = Archive.ld1b_verify_archive_content_hash(native;
        label = "stopped-process interruption review")
    owner = _validate_attempt_owner_precommit_lineage(owner_artifact;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_artifact,
        reservation_receipt_sha256, expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    launch = ld1b_validate_child_launch_receipt(launch_artifact;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, owner_artifact, owner_receipt_sha256,
        reservation_artifact, reservation_receipt_sha256,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path,
        execution_context)
    _validate_common(native, launch.context, LD1B_INTERRUPTION_REVIEW_SCHEMA,
        :local_dependence_pilot_stopped_process_interruption_review,
        :ld1b_interrupted_attempt_review,
        "stopped-process interruption review")
    lineage = _exact(native["receipt_lineage"],
        ("owner", "launch", "exit"), "review receipt lineage")
    owner_reference = _validate_receipt_reference(lineage["owner"],
        LD1B_ATTEMPT_OWNER_FILENAME, owner_receipt_sha256,
        owner.content_hash, "owner receipt reference")
    launch_reference = _validate_receipt_reference(lineage["launch"],
        LD1B_CHILD_LAUNCH_FILENAME, launch_receipt_sha256,
        launch.content_hash, "launch receipt reference")
    review = _exact(native["review"], (
        "mode", "retirement_reason_code", "review_host", "reviewer",
        "reviewed_at_utc",
        "controller_confirmed_stopped", "child_confirmed_stopped",
        "external_process_identity_review",
        "os_process_inspection_performed_by_artifact_code",
    ), "interruption review")
    mode = _symbol(review["mode"], "interruption review mode")
    mode in _REVIEW_MODES || error("unsupported review mode")
    _string(review["review_host"], "review host")
    _string(review["reviewer"], "reviewer")
    _string(review["reviewed_at_utc"], "review time")
    _boolean(review["controller_confirmed_stopped"],
        "controller stopped confirmation") ||
        error("controller is not confirmed stopped")
    _boolean(review["child_confirmed_stopped"],
        "child stopped confirmation") || error("child is not confirmed stopped")
    !_boolean(review["os_process_inspection_performed_by_artifact_code"],
        "artifact OS process inspection claim") ||
        error("recovery artifact must not claim OS process inspection")
    observed_state =
        _validate_observed_attempt_state(native["observed_attempt_state"])
    retirement_reason_code = _validate_reason_state(
        review["retirement_reason_code"], observed_state)
    exit_reference = nothing
    if mode === :validated_exit_receipt
        review["external_process_identity_review"] === nothing || error(
            "validated-exit mode contains external process review")
        exit_artifact === nothing && error("validated exit receipt is missing")
        exit_receipt_sha256 === nothing && error(
            "validated exit-receipt file SHA-256 is missing")
        exit = ld1b_validate_child_exit_receipt(exit_artifact;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role, owner_artifact,
            owner_receipt_sha256, launch_artifact, launch_receipt_sha256,
            reservation_artifact, reservation_receipt_sha256,
            expected_reservation_id,
            expected_execution_root_relative_reservation_path,
            expected_execution_root_relative_attempt_path,
            execution_context)
        exit_reference = _validate_receipt_reference(lineage["exit"],
            LD1B_CHILD_EXIT_FILENAME, exit_receipt_sha256,
            exit.content_hash, "exit receipt reference")
    else
        lineage["exit"] === nothing ||
            error("external-review mode contains an exit receipt")
        exit_artifact === nothing && exit_receipt_sha256 === nothing ||
            error("external-review validation received an exit receipt")
        _external_review(review["external_process_identity_review"])
    end
    inventory = _validate_inventory(native["inventory_before_review"])
    _require_receipt_inventory_row(inventory, owner_reference, "owner receipt")
    _require_receipt_inventory_row(inventory, launch_reference, "launch receipt")
    if exit_reference === nothing
        any(row -> row.kind === :file &&
            row.path == LD1B_CHILD_EXIT_FILENAME, inventory.rows) &&
            error("external review cannot ignore an exit receipt")
    else
        _require_receipt_inventory_row(inventory, exit_reference,
            "exit receipt")
    end
    _require_result_inventory_state(inventory, observed_state)
    if expected_inventory_before_review !== nothing
        expected = _validate_inventory(expected_inventory_before_review)
        Archive.ld1b_archive_canonical_sha256(inventory.native) ==
            Archive.ld1b_archive_canonical_sha256(expected.native) ||
            error("pre-review inventory differs from the expected snapshot")
    end
    return (; valid = true, native, content_hash, mode,
        retirement_reason_code, observed_attempt_state = observed_state.native,
        inventory_rows_sha256 = inventory.rows_sha256,
        context = launch.context)
end

function _snapshot(attempt_dir::AbstractString, filename, label)
    root = normpath(attempt_dir)
    isdir(root) && !islink(root) ||
        error("attempt directory is not a regular directory")
    path = joinpath(root, filename)
    return Archive._ld1b_read_json_snapshot(path, root, label)
end

function _file_result(filename, snapshot, validated, state)
    return (; valid = true, state, filename,
        file_sha256 = snapshot.sha256,
        canonical_sha256 = validated.content_hash,
        content_hash = validated.content_hash,
        artifact = validated.native)
end

function _validated_reservation_for_attempt(reservation_path::AbstractString,
        attempt_dir::AbstractString; execution_root::AbstractString,
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, expected_reservation_id,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    relative_attempt_path = _execution_root_relative_path(
        execution_root, attempt_dir, "reserved attempt path")
    reservation = ld1b_validate_attempt_reservation_file(reservation_path;
        execution_root, plan_identity, execution_source_identity,
        job_identity, attempt_number, attempt_role,
        expected_reservation_id,
        expected_execution_root_relative_attempt_path = relative_attempt_path,
        execution_context)
    return (; reservation, relative_attempt_path)
end

function ld1b_validate_attempt_owner_file(attempt_dir::AbstractString;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_path = nothing,
        execution_root = nothing, expected_reservation_id = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    snapshot = _snapshot(attempt_dir, LD1B_ATTEMPT_OWNER_FILENAME,
        "attempt-owner receipt")
    owner_native = _object(snapshot.parsed, "attempt-owner receipt")
    schema = _string(get(owner_native, "schema", nothing),
        "attempt-owner receipt schema")
    if schema == LD1B_ATTEMPT_OWNER_SCHEMA
        reservation_path === nothing && execution_root === nothing &&
            expected_reservation_id === nothing || error(
            "unreserved owner file cannot be validated as reservation-bound")
        validated = ld1b_validate_attempt_owner_precommit(snapshot.parsed;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role, execution_context)
        return _file_result(LD1B_ATTEMPT_OWNER_FILENAME, snapshot, validated,
            :owner_precommitted)
    elseif schema == LD1B_CANONICAL_ATTEMPT_OWNER_SCHEMA
        reservation_path isa AbstractString &&
            execution_root isa AbstractString &&
            expected_reservation_id !== nothing || error(
            "canonical owner file validation requires reservation lineage")
        lineage = _validated_reservation_for_attempt(
            String(reservation_path), attempt_dir;
            execution_root = String(execution_root), plan_identity,
            execution_source_identity, job_identity, attempt_number,
            attempt_role, expected_reservation_id, execution_context)
        reservation = lineage.reservation
        validated = ld1b_validate_canonical_attempt_owner_precommit(
            snapshot.parsed;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role,
            reservation_artifact = reservation.artifact,
            reservation_receipt_sha256 = reservation.file_sha256,
            expected_reservation_id,
            expected_execution_root_relative_reservation_path =
                reservation.execution_root_relative_reservation_path,
            expected_execution_root_relative_attempt_path =
                lineage.relative_attempt_path,
            execution_context)
        return merge(_file_result(LD1B_ATTEMPT_OWNER_FILENAME, snapshot,
            validated, :canonical_owner_precommitted), (;
            reservation,
            execution_root_relative_attempt_path =
                lineage.relative_attempt_path,
        ))
    end
    error("unsupported attempt-owner receipt schema")
end

function ld1b_validate_canonical_attempt_owner_file(
        attempt_dir::AbstractString; reservation_path::AbstractString,
        execution_root::AbstractString, plan_identity,
        execution_source_identity, job_identity, attempt_number,
        attempt_role, expected_reservation_id,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    result = ld1b_validate_attempt_owner_file(attempt_dir;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_path, execution_root,
        expected_reservation_id, execution_context)
    result.state === :canonical_owner_precommitted ||
        error("attempt owner is not the canonical reservation-bound schema")
    return result
end

function ld1b_publish_canonical_attempt_owner(
        attempt_dir::AbstractString; reservation_path::AbstractString,
        execution_root::AbstractString, plan_identity,
        execution_source_identity, job_identity, attempt_number,
        attempt_role, expected_reservation_id, recorded_at_utc,
        staging_dir::AbstractString, _fault_injection_stage = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    lineage = _validated_reservation_for_attempt(reservation_path,
        attempt_dir; execution_root, plan_identity,
        execution_source_identity, job_identity, attempt_number,
        attempt_role, expected_reservation_id, execution_context)
    reservation = lineage.reservation
    artifact = ld1b_canonical_attempt_owner_precommit(;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role,
        reservation_artifact = reservation.artifact,
        reservation_receipt_sha256 = reservation.file_sha256,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path =
            reservation.execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path =
            lineage.relative_attempt_path,
        recorded_at_utc,
        execution_context)
    validator = value -> ld1b_validate_canonical_attempt_owner_precommit(
        value;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role,
        reservation_artifact = reservation.artifact,
        reservation_receipt_sha256 = reservation.file_sha256,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path =
            reservation.execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path =
            lineage.relative_attempt_path,
        execution_context)
    publication = Archive.ld1b_atomic_publish_json_create_new(
        joinpath(attempt_dir, LD1B_ATTEMPT_OWNER_FILENAME), artifact,
        staging_dir, execution_root; semantic_validator = validator,
        artifact_label = "canonical attempt-owner precommit",
        _fault_injection_stage)
    validated = ld1b_validate_canonical_attempt_owner_file(attempt_dir;
        reservation_path, execution_root, plan_identity,
        execution_source_identity, job_identity, attempt_number,
        attempt_role, expected_reservation_id, execution_context)
    return (; publication..., artifact = validated.artifact,
        owner_file_sha256 = validated.file_sha256,
        owner_content_hash = validated.content_hash,
        reservation_file_sha256 = reservation.file_sha256,
        reservation_content_hash = reservation.content_hash)
end

function ld1b_validate_child_launch_file(attempt_dir::AbstractString;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_path = nothing,
        execution_root = nothing, expected_reservation_id = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    owner = ld1b_validate_attempt_owner_file(attempt_dir;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_path, execution_root,
        expected_reservation_id, execution_context)
    snapshot = _snapshot(attempt_dir, LD1B_CHILD_LAUNCH_FILENAME,
        "child-launch receipt")
    if owner.state === :canonical_owner_precommitted
        reservation = owner.reservation
        validated = ld1b_validate_child_launch_receipt(snapshot.parsed;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role, owner_artifact = owner.artifact,
            owner_receipt_sha256 = owner.file_sha256,
            reservation_artifact = reservation.artifact,
            reservation_receipt_sha256 = reservation.file_sha256,
            expected_reservation_id,
            expected_execution_root_relative_reservation_path =
                reservation.execution_root_relative_reservation_path,
            expected_execution_root_relative_attempt_path =
                owner.execution_root_relative_attempt_path,
            execution_context)
    else
        validated = ld1b_validate_child_launch_receipt(snapshot.parsed;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role, owner_artifact = owner.artifact,
            owner_receipt_sha256 = owner.file_sha256,
            execution_context)
    end
    return merge(_file_result(LD1B_CHILD_LAUNCH_FILENAME, snapshot, validated,
        :child_launched), (; owner))
end

function ld1b_validate_child_exit_file(attempt_dir::AbstractString;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_path = nothing,
        execution_root = nothing, expected_reservation_id = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    launch = ld1b_validate_child_launch_file(attempt_dir;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_path, execution_root,
        expected_reservation_id, execution_context)
    snapshot = _snapshot(attempt_dir, LD1B_CHILD_EXIT_FILENAME,
        "child-exit receipt")
    if launch.owner.state === :canonical_owner_precommitted
        reservation = launch.owner.reservation
        validated = ld1b_validate_child_exit_receipt(snapshot.parsed;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role,
            owner_artifact = launch.owner.artifact,
            owner_receipt_sha256 = launch.owner.file_sha256,
            launch_artifact = launch.artifact,
            launch_receipt_sha256 = launch.file_sha256,
            reservation_artifact = reservation.artifact,
            reservation_receipt_sha256 = reservation.file_sha256,
            expected_reservation_id,
            expected_execution_root_relative_reservation_path =
                reservation.execution_root_relative_reservation_path,
            expected_execution_root_relative_attempt_path =
                launch.owner.execution_root_relative_attempt_path,
            execution_context)
    else
        validated = ld1b_validate_child_exit_receipt(snapshot.parsed;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role,
            owner_artifact = launch.owner.artifact,
            owner_receipt_sha256 = launch.owner.file_sha256,
            launch_artifact = launch.artifact,
            launch_receipt_sha256 = launch.file_sha256,
            execution_context)
    end
    return merge(_file_result(LD1B_CHILD_EXIT_FILENAME, snapshot, validated,
        :child_exit_observed), (; launch))
end

function ld1b_validate_precommit_interruption_review_file(
        attempt_dir::AbstractString; reservation_path::AbstractString,
        execution_root::AbstractString, plan_identity,
        execution_source_identity, job_identity, attempt_number,
        attempt_role, expected_reservation_id,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    lineage = _validated_reservation_for_attempt(reservation_path,
        attempt_dir; execution_root, plan_identity,
        execution_source_identity, job_identity, attempt_number,
        attempt_role, expected_reservation_id, execution_context)
    reservation = lineage.reservation
    review_snapshot = _snapshot(attempt_dir,
        LD1B_PRECOMMIT_INTERRUPTION_REVIEW_FILENAME,
        "precommit interruption review")
    review_native = _object(review_snapshot.parsed,
        "precommit interruption review")
    state = _object(get(review_native, "attempt_state", nothing),
        "precommit attempt state")
    owner_present = _boolean(get(state, "owner_present", nothing),
        "precommit owner presence")
    owner_path = joinpath(attempt_dir, LD1B_ATTEMPT_OWNER_FILENAME)
    owner = nothing
    if owner_present
        owner = ld1b_validate_canonical_attempt_owner_file(attempt_dir;
            reservation_path, execution_root, plan_identity,
            execution_source_identity, job_identity, attempt_number,
            attempt_role, expected_reservation_id, execution_context)
    elseif ispath(owner_path) || islink(owner_path)
        error("reservation-only review unexpectedly contains an owner receipt")
    end
    inventory = ld1b_inventory_before_precommit_interruption_review(
        attempt_dir)
    validated = ld1b_validate_precommit_interruption_review(
        review_snapshot.parsed;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role,
        reservation_artifact = reservation.artifact,
        reservation_receipt_sha256 = reservation.file_sha256,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path =
            reservation.execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path =
            lineage.relative_attempt_path,
        owner_artifact = owner === nothing ? nothing : owner.artifact,
        owner_receipt_sha256 = owner === nothing ? nothing : owner.file_sha256,
        expected_inventory_before_review = inventory,
        execution_context)
    return merge(_file_result(
        LD1B_PRECOMMIT_INTERRUPTION_REVIEW_FILENAME,
        review_snapshot, validated, :precommit_interruption_review_validated),
        (;
            reason_code = validated.reason_code,
            owner_present = validated.owner_present,
            scientific_contribution = validated.scientific_contribution,
            inventory_rows_sha256 = validated.inventory_rows_sha256,
            reservation_file_sha256 = reservation.file_sha256,
            reservation_content_hash = reservation.content_hash,
            owner_file_sha256 = owner === nothing ? nothing : owner.file_sha256,
        ))
end

function ld1b_publish_precommit_interruption_review(
        attempt_dir::AbstractString; reservation_path::AbstractString,
        execution_root::AbstractString, plan_identity,
        execution_source_identity, job_identity, attempt_number,
        attempt_role, expected_reservation_id, reason_code, review_host,
        reviewer, reviewed_at_utc, controller_confirmed_stopped::Bool,
        child_launch_receipt_confirmed_absent::Bool,
        child_process_confirmed_stopped::Bool,
        staging_dir::AbstractString,
        _fault_injection_stage = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    lineage = _validated_reservation_for_attempt(reservation_path,
        attempt_dir; execution_root, plan_identity,
        execution_source_identity, job_identity, attempt_number,
        attempt_role, expected_reservation_id, execution_context)
    reservation = lineage.reservation
    owner_path = joinpath(attempt_dir, LD1B_ATTEMPT_OWNER_FILENAME)
    owner = if ispath(owner_path) || islink(owner_path)
        ld1b_validate_canonical_attempt_owner_file(attempt_dir;
            reservation_path, execution_root, plan_identity,
            execution_source_identity, job_identity, attempt_number,
            attempt_role, expected_reservation_id, execution_context)
    else
        nothing
    end
    inventory = ld1b_inventory_before_precommit_interruption_review(
        attempt_dir)
    artifact = ld1b_precommit_interruption_review(;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role,
        reservation_artifact = reservation.artifact,
        reservation_receipt_sha256 = reservation.file_sha256,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path =
            reservation.execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path =
            lineage.relative_attempt_path,
        owner_artifact = owner === nothing ? nothing : owner.artifact,
        owner_receipt_sha256 = owner === nothing ? nothing : owner.file_sha256,
        inventory_before_review = inventory, reason_code, review_host,
        reviewer, reviewed_at_utc, controller_confirmed_stopped,
        child_launch_receipt_confirmed_absent,
        child_process_confirmed_stopped,
        execution_context)
    validator = value -> ld1b_validate_precommit_interruption_review(value;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role,
        reservation_artifact = reservation.artifact,
        reservation_receipt_sha256 = reservation.file_sha256,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path =
            reservation.execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path =
            lineage.relative_attempt_path,
        owner_artifact = owner === nothing ? nothing : owner.artifact,
        owner_receipt_sha256 = owner === nothing ? nothing : owner.file_sha256,
        expected_inventory_before_review = inventory,
        execution_context)
    publication = Archive.ld1b_atomic_publish_json_create_new(
        joinpath(attempt_dir,
            LD1B_PRECOMMIT_INTERRUPTION_REVIEW_FILENAME),
        artifact, staging_dir, execution_root;
        semantic_validator = validator,
        artifact_label = "precommit interruption review",
        _fault_injection_stage)
    validated = ld1b_validate_precommit_interruption_review_file(
        attempt_dir; reservation_path, execution_root, plan_identity,
        execution_source_identity, job_identity, attempt_number,
        attempt_role, expected_reservation_id, execution_context)
    return (; publication...,
        artifact = validated.artifact,
        review_file_sha256 = validated.file_sha256,
        review_content_hash = validated.content_hash,
        reason_code = validated.reason_code,
        owner_present = validated.owner_present,
        scientific_contribution = validated.scientific_contribution)
end

function ld1b_reuse_existing_precommit_interruption_review(
        attempt_dir::AbstractString; reservation_path::AbstractString,
        execution_root::AbstractString, plan_identity,
        execution_source_identity, job_identity, attempt_number,
        attempt_role, expected_reservation_id, reason_code, review_host,
        reviewer, reviewed_at_utc, controller_confirmed_stopped::Bool,
        child_launch_receipt_confirmed_absent::Bool,
        child_process_confirmed_stopped::Bool,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    lineage = _validated_reservation_for_attempt(reservation_path,
        attempt_dir; execution_root, plan_identity,
        execution_source_identity, job_identity, attempt_number,
        attempt_role, expected_reservation_id, execution_context)
    reservation = lineage.reservation
    owner_path = joinpath(attempt_dir, LD1B_ATTEMPT_OWNER_FILENAME)
    owner = if ispath(owner_path) || islink(owner_path)
        ld1b_validate_canonical_attempt_owner_file(attempt_dir;
            reservation_path, execution_root, plan_identity,
            execution_source_identity, job_identity, attempt_number,
            attempt_role, expected_reservation_id, execution_context)
    else
        nothing
    end
    inventory = ld1b_inventory_before_precommit_interruption_review(
        attempt_dir)
    expected_artifact = ld1b_precommit_interruption_review(;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role,
        reservation_artifact = reservation.artifact,
        reservation_receipt_sha256 = reservation.file_sha256,
        expected_reservation_id,
        expected_execution_root_relative_reservation_path =
            reservation.execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path =
            lineage.relative_attempt_path,
        owner_artifact = owner === nothing ? nothing : owner.artifact,
        owner_receipt_sha256 = owner === nothing ? nothing : owner.file_sha256,
        inventory_before_review = inventory, reason_code, review_host,
        reviewer, reviewed_at_utc, controller_confirmed_stopped,
        child_launch_receipt_confirmed_absent,
        child_process_confirmed_stopped,
        execution_context)
    snapshot = _snapshot(attempt_dir,
        LD1B_PRECOMMIT_INTERRUPTION_REVIEW_FILENAME,
        "existing precommit interruption review")
    snapshot.bytes == Archive._ld1b_encode_json_bytes(expected_artifact) ||
        error("existing precommit review differs from the expected artifact")
    existing_content_hash = Archive.ld1b_verify_archive_content_hash(
        snapshot.parsed; label = "existing precommit interruption review")
    expected_content_hash = Archive.ld1b_verify_archive_content_hash(
        expected_artifact; label = "expected precommit interruption review")
    existing_content_hash == expected_content_hash || error(
        "existing precommit review content hash differs from expected")
    validated = ld1b_validate_precommit_interruption_review_file(
        attempt_dir; reservation_path, execution_root, plan_identity,
        execution_source_identity, job_identity, attempt_number,
        attempt_role, expected_reservation_id, execution_context)
    return (;
        path = joinpath(attempt_dir,
            LD1B_PRECOMMIT_INTERRUPTION_REVIEW_FILENAME),
        file_sha256 = snapshot.sha256,
        content_hash = existing_content_hash,
        nbytes = snapshot.nbytes,
        publication = :existing_identical_create_new_artifact,
        published = false,
        reused = true,
        overwrite_allowed = false,
        artifact = validated.artifact,
        reason_code = validated.reason_code,
        owner_present = validated.owner_present,
        scientific_contribution = validated.scientific_contribution,
    )
end

function _reservation_lineage_keywords(owner_file)
    if owner_file.state === :canonical_owner_precommitted
        reservation = owner_file.reservation
        return (;
            reservation_artifact = reservation.artifact,
            reservation_receipt_sha256 = reservation.file_sha256,
            expected_reservation_id = reservation.reservation_id,
            expected_execution_root_relative_reservation_path =
                reservation.execution_root_relative_reservation_path,
            expected_execution_root_relative_attempt_path =
                owner_file.execution_root_relative_attempt_path,
        )
    end
    return (;
        reservation_artifact = nothing,
        reservation_receipt_sha256 = nothing,
        expected_reservation_id = nothing,
        expected_execution_root_relative_reservation_path = nothing,
        expected_execution_root_relative_attempt_path = nothing,
    )
end

function ld1b_validate_interruption_review_file(attempt_dir::AbstractString;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_path = nothing,
        execution_root = nothing, expected_reservation_id = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    launch = ld1b_validate_child_launch_file(attempt_dir;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_path, execution_root,
        expected_reservation_id, execution_context)
    reservation_lineage = _reservation_lineage_keywords(launch.owner)
    review_snapshot = _snapshot(attempt_dir, LD1B_INTERRUPTION_REVIEW_FILENAME,
        "stopped-process interruption review")
    review_native = _object(review_snapshot.parsed,
        "stopped-process interruption review")
    review_body = _object(get(review_native, "review", nothing),
        "interruption review")
    mode = _symbol(get(review_body, "mode", nothing),
        "interruption review mode")
    observed_body = _object(get(review_native, "observed_attempt_state", nothing),
        "observed attempt state")
    semantic_assessment = _symbol(get(observed_body,
        "result_semantic_assessment", nothing), "result semantic assessment")
    exit = nothing
    if mode === :validated_exit_receipt
        exit = ld1b_validate_child_exit_file(attempt_dir;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role, reservation_path, execution_root,
            expected_reservation_id, execution_context)
    elseif mode === :external_process_identity_review
        exit_path = joinpath(attempt_dir, LD1B_CHILD_EXIT_FILENAME)
        (ispath(exit_path) || islink(exit_path)) && error(
            "external-review attempt unexpectedly contains an exit receipt")
    else
        error("unsupported review mode")
    end
    inventory = ld1b_inventory_before_interruption_review(attempt_dir)
    observed_state = _snapshot_observed_attempt_state(
        attempt_dir, semantic_assessment)
    validated = ld1b_validate_stopped_process_interruption_review(
        review_snapshot.parsed;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role,
        owner_artifact = launch.owner.artifact,
        owner_receipt_sha256 = launch.owner.file_sha256,
        launch_artifact = launch.artifact,
        launch_receipt_sha256 = launch.file_sha256,
        exit_artifact = exit === nothing ? nothing : exit.artifact,
        exit_receipt_sha256 = exit === nothing ? nothing : exit.file_sha256,
        expected_inventory_before_review = inventory,
        execution_context,
        reservation_lineage...)
    Archive.ld1b_archive_canonical_sha256(observed_state) ==
        Archive.ld1b_archive_canonical_sha256(
            validated.observed_attempt_state) ||
        error("observed attempt state differs from the current result snapshot")
    return merge(_file_result(LD1B_INTERRUPTION_REVIEW_FILENAME,
        review_snapshot, validated, :interruption_review_validated), (;
        mode = validated.mode,
        retirement_reason_code = validated.retirement_reason_code,
        observed_attempt_state = validated.observed_attempt_state,
        review_file_sha256 = review_snapshot.sha256,
        review_content_hash = validated.content_hash,
        owner_file_sha256 = launch.owner.file_sha256,
        launch_file_sha256 = launch.file_sha256,
        exit_file_sha256 = exit === nothing ? nothing : exit.file_sha256,
        inventory_rows_sha256 = validated.inventory_rows_sha256,
    ))
end

function ld1b_publish_interruption_review(attempt_dir::AbstractString;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, mode, review_host, reviewer,
        reviewed_at_utc, retirement_reason_code,
        result_semantic_assessment, controller_confirmed_stopped::Bool,
        child_confirmed_stopped::Bool,
        external_process_identity_review = nothing,
        staging_dir::AbstractString, boundary::AbstractString,
        reservation_path = nothing, execution_root = nothing,
        expected_reservation_id = nothing,
        _fault_injection_stage = nothing,
        execution_context = LD1B_PILOT_EXECUTION_CONTEXT)
    launch = ld1b_validate_child_launch_file(attempt_dir;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_path, execution_root,
        expected_reservation_id, execution_context)
    reservation_lineage = _reservation_lineage_keywords(launch.owner)
    checked_mode = _symbol(mode, "interruption review mode")
    exit = checked_mode === :validated_exit_receipt ?
        ld1b_validate_child_exit_file(attempt_dir;
            plan_identity, execution_source_identity, job_identity,
            attempt_number, attempt_role, reservation_path, execution_root,
            expected_reservation_id, execution_context) : nothing
    inventory = ld1b_inventory_before_interruption_review(attempt_dir)
    observed_attempt_state = _snapshot_observed_attempt_state(
        attempt_dir, result_semantic_assessment)
    artifact = ld1b_stopped_process_interruption_review(;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role,
        owner_artifact = launch.owner.artifact,
        owner_receipt_sha256 = launch.owner.file_sha256,
        launch_artifact = launch.artifact,
        launch_receipt_sha256 = launch.file_sha256,
        exit_artifact = exit === nothing ? nothing : exit.artifact,
        exit_receipt_sha256 = exit === nothing ? nothing : exit.file_sha256,
        inventory_before_review = inventory,
        mode = checked_mode, review_host, reviewer, reviewed_at_utc,
        retirement_reason_code, observed_attempt_state,
        controller_confirmed_stopped, child_confirmed_stopped,
        external_process_identity_review,
        execution_context,
        reservation_lineage...)
    validator = value -> ld1b_validate_stopped_process_interruption_review(
        value;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role,
        owner_artifact = launch.owner.artifact,
        owner_receipt_sha256 = launch.owner.file_sha256,
        launch_artifact = launch.artifact,
        launch_receipt_sha256 = launch.file_sha256,
        exit_artifact = exit === nothing ? nothing : exit.artifact,
        exit_receipt_sha256 = exit === nothing ? nothing : exit.file_sha256,
        expected_inventory_before_review = inventory,
        execution_context,
        reservation_lineage...)
    publication = Archive.ld1b_atomic_publish_json_create_new(
        joinpath(attempt_dir, LD1B_INTERRUPTION_REVIEW_FILENAME), artifact,
        staging_dir, boundary;
        semantic_validator = validator,
        artifact_label = "stopped-process interruption review",
        _fault_injection_stage)
    validated = ld1b_validate_interruption_review_file(attempt_dir;
        plan_identity, execution_source_identity, job_identity,
        attempt_number, attempt_role, reservation_path, execution_root,
        expected_reservation_id, execution_context)
    return (; publication..., review_file_sha256 = validated.file_sha256,
        review_content_hash = validated.content_hash,
        review_mode = validated.mode,
        retirement_reason_code = validated.retirement_reason_code,
        observed_attempt_state = validated.observed_attempt_state)
end

end # module
