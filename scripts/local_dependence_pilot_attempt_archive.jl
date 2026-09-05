module LocalDependencePilotAttemptArchive

using JSON3
using SHA

include(joinpath(@__DIR__, "local_json.jl"))

export LD1B_ATTEMPT_RETIREMENT_FILENAME,
    LD1B_ATTEMPT_RETIREMENT_SCHEMA,
    LD1B_ATTEMPT_SEAL_FILENAME,
    LD1B_ATTEMPT_SEAL_SCHEMA,
    ld1b_archive_canonical_sha256,
    ld1b_archive_with_content_hash,
    ld1b_attempt_archive_source_sha256,
    ld1b_attempt_inventory,
    ld1b_attempt_inventory_sha256,
    ld1b_atomic_publish_json_create_new,
    ld1b_completed_attempt_seal,
    ld1b_execution_context,
    ld1b_publish_attempt_retirement_marker,
    ld1b_publish_completed_attempt_seal,
    ld1b_reconcile_json_create_new_staging_alias,
    ld1b_retirement_marker,
    ld1b_validate_attempt_retirement_marker,
    ld1b_validate_completed_attempt_seal,
    ld1b_validate_execution_context,
    ld1b_verify_archive_content_hash

const LD1B_ATTEMPT_SEAL_FILENAME = "attempt_seal.json"
const LD1B_ATTEMPT_RETIREMENT_FILENAME = "attempt_retirement.json"
const LD1B_ATTEMPT_SEAL_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_attempt_seal.v2"
const LD1B_ATTEMPT_RETIREMENT_SCHEMA =
    "bayesianmgmfrm.local_dependence_pilot_attempt_retirement.v2"
const LD1B_ARCHIVE_CANONICAL_FORMAT = :local_json_sorted_compact
const LD1B_RESULT_FILENAME = "job_result.json"
const _LD1B_SHA256_PATTERN = r"^[0-9a-f]{64}$"
const _LD1B_CONTROL_FILENAMES = (
    LD1B_ATTEMPT_SEAL_FILENAME,
    LD1B_ATTEMPT_RETIREMENT_FILENAME,
)
const _LD1B_PUBLICATION_FAULT_STAGES = (
    :pre_link,
    :post_link_pre_unlink,
    :post_unlink_pre_validation,
)
const _LD1B_PLAN_REQUIRED_SHA_FIELDS = (
    "plan_id",
    "protocol_plan_id",
    "protocol_file_sha256",
    "protocol_content_hash",
    "ordered_job_rows_sha256",
    "pilot_contract_sha256",
)
const _LD1B_EXECUTION_REQUIRED_SHA_FIELDS = (
    "batch_runner_source_sha256",
    "local_json_source_sha256",
    "job_runner_source_sha256",
    "attempt_archive_source_sha256",
)

ld1b_attempt_archive_source_sha256() =
    bytes2hex(open(sha256, @__FILE__))

function _ld1b_json_native(value)
    if value isa NamedTuple || value isa AbstractDict
        result = Dict{String,Any}()
        for (key, element) in pairs(value)
            canonical = String(key)
            haskey(result, canonical) && error(
                "JSON object contains colliding key $canonical")
            result[canonical] = _ld1b_json_native(element)
        end
        return result
    elseif value isa AbstractArray || value isa Tuple
        return [_ld1b_json_native(element) for element in value]
    elseif value isa Symbol
        return String(value)
    elseif ismissing(value)
        return nothing
    end
    return value
end

function _ld1b_validate_json_value(value, label::AbstractString = "value")
    if value === nothing || value isa Bool || value isa Integer ||
            value isa AbstractString
        return true
    elseif value isa AbstractFloat
        isfinite(value) || error("$label contains a non-finite number")
        return true
    elseif value isa AbstractDict
        for (key, element) in pairs(value)
            key isa AbstractString || error("$label contains a non-string key")
            _ld1b_validate_json_value(element, string(label, ".", key))
        end
        return true
    elseif value isa AbstractArray
        for (index, element) in pairs(value)
            _ld1b_validate_json_value(element, string(label, "[", index, "]"))
        end
        return true
    end
    error("$label contains unsupported value type $(typeof(value))")
end

function _ld1b_object(value, label::AbstractString)
    native = _ld1b_json_native(value)
    native isa AbstractDict || error("$label must be a JSON object")
    _ld1b_validate_json_value(native, label)
    return native
end

function _ld1b_exact_keys(value, expected, label::AbstractString)
    native = _ld1b_object(value, label)
    observed = Set(String(key) for key in keys(native))
    required = Set(String(key) for key in expected)
    observed == required || error("$label has an unexpected field set")
    return native
end

function _ld1b_require_keys(value, expected, label::AbstractString)
    native = _ld1b_object(value, label)
    all(key -> haskey(native, String(key)), expected) ||
        error("$label is incomplete")
    return native
end

function _ld1b_string(value, label::AbstractString; nonempty::Bool = true)
    value isa AbstractString || error("$label must be a string")
    text = String(value)
    nonempty && isempty(strip(text)) && error("$label must not be empty")
    return text
end

function _ld1b_int(value, label::AbstractString; minimum = nothing)
    value isa Integer && !(value isa Bool) || error("$label must be an integer")
    checked = Int(value)
    minimum === nothing || checked >= minimum ||
        error("$label must be at least $minimum")
    return checked
end

function _ld1b_bool(value, label::AbstractString)
    value isa Bool || error("$label must be Bool")
    return value
end

function _ld1b_sha256(value, label::AbstractString)
    text = _ld1b_string(value, label)
    occursin(_LD1B_SHA256_PATTERN, text) ||
        error("$label must be a lowercase SHA-256 digest")
    return text
end

function ld1b_archive_canonical_sha256(value)
    native = _ld1b_json_native(value)
    _ld1b_validate_json_value(native)
    io = IOBuffer()
    write_canonical_json(io, native)
    return bytes2hex(sha256(take!(io)))
end

function ld1b_archive_with_content_hash(artifact)
    native = _ld1b_object(artifact, "archive artifact")
    haskey(native, "content_hash") &&
        error("archive artifact already contains content_hash")
    record = (;
        algorithm = :sha256,
        value = ld1b_archive_canonical_sha256(native),
        covers = :artifact_without_content_hash,
        canonical_format = LD1B_ARCHIVE_CANONICAL_FORMAT,
    )
    return artifact isa NamedTuple ? merge(artifact, (; content_hash = record)) :
        merge(native, Dict("content_hash" => _ld1b_json_native(record)))
end

function ld1b_verify_archive_content_hash(value;
        label::AbstractString = "archive artifact")
    native = _ld1b_object(value, label)
    haskey(native, "content_hash") || error("$label lacks content_hash")
    record = _ld1b_exact_keys(native["content_hash"],
        ("algorithm", "value", "covers", "canonical_format"),
        "$label content_hash")
    _ld1b_string(record["algorithm"], "$label content-hash algorithm") ==
        "sha256" || error("$label content hash does not use SHA-256")
    _ld1b_string(record["covers"], "$label content-hash coverage") ==
        "artifact_without_content_hash" ||
        error("$label content hash has the wrong coverage")
    _ld1b_string(record["canonical_format"],
        "$label canonical format") == String(LD1B_ARCHIVE_CANONICAL_FORMAT) ||
        error("$label content hash has the wrong canonical format")
    stored = _ld1b_sha256(record["value"], "$label content hash")
    delete!(native, "content_hash")
    stored == ld1b_archive_canonical_sha256(native) ||
        error("$label content hash does not match its contents")
    return stored
end

function _ld1b_encode_json_bytes(value)
    native = _ld1b_json_native(value)
    _ld1b_validate_json_value(native)
    io = IOBuffer()
    write_json(io, native)
    println(io)
    return take!(io)
end

function _ld1b_json_skip_whitespace(bytes, index::Int)
    while index <= length(bytes) && bytes[index] in
            (UInt8(' '), UInt8('\t'), UInt8('\r'), UInt8('\n'))
        index += 1
    end
    return index
end

function _ld1b_json_scan_string(bytes, index::Int, label::AbstractString)
    index <= length(bytes) && bytes[index] == UInt8('"') ||
        error("$label contains malformed JSON string syntax")
    first_index = index
    index += 1
    while index <= length(bytes)
        byte = bytes[index]
        if byte == UInt8('"')
            token = String(Vector{UInt8}(bytes[first_index:index]))
            decoded = try
                JSON3.read(token, String)
            catch err
                error("$label contains an invalid JSON string: " *
                    portable_error_message(err))
            end
            return decoded, index + 1
        elseif byte == UInt8('\\')
            index += 1
            index <= length(bytes) ||
                error("$label contains an unterminated JSON escape")
            if bytes[index] == UInt8('u')
                index + 4 <= length(bytes) ||
                    error("$label contains a truncated Unicode escape")
                index += 5
            else
                index += 1
            end
        else
            byte >= 0x20 || error(
                "$label contains an unescaped control byte")
            index += 1
        end
    end
    error("$label contains an unterminated JSON string")
end

function _ld1b_json_scan_value(bytes, index::Int,
        label::AbstractString, depth::Int)
    depth <= 256 || error("$label exceeds the JSON nesting limit")
    index = _ld1b_json_skip_whitespace(bytes, index)
    index <= length(bytes) || error("$label contains truncated JSON")
    byte = bytes[index]
    if byte == UInt8('{')
        seen_keys = Set{String}()
        index = _ld1b_json_skip_whitespace(bytes, index + 1)
        index <= length(bytes) || error("$label contains an unterminated object")
        bytes[index] == UInt8('}') && return index + 1
        while true
            key, index = _ld1b_json_scan_string(bytes, index, label)
            key in seen_keys && error(
                "$label contains a duplicate JSON object key: $(repr(key))")
            push!(seen_keys, key)
            index = _ld1b_json_skip_whitespace(bytes, index)
            index <= length(bytes) && bytes[index] == UInt8(':') ||
                error("$label contains an object key without a colon")
            index = _ld1b_json_scan_value(bytes, index + 1, label, depth + 1)
            index = _ld1b_json_skip_whitespace(bytes, index)
            index <= length(bytes) || error("$label contains an unterminated object")
            bytes[index] == UInt8('}') && return index + 1
            bytes[index] == UInt8(',') ||
                error("$label contains malformed object separators")
            index = _ld1b_json_skip_whitespace(bytes, index + 1)
        end
    elseif byte == UInt8('[')
        index = _ld1b_json_skip_whitespace(bytes, index + 1)
        index <= length(bytes) || error("$label contains an unterminated array")
        bytes[index] == UInt8(']') && return index + 1
        while true
            index = _ld1b_json_scan_value(bytes, index, label, depth + 1)
            index = _ld1b_json_skip_whitespace(bytes, index)
            index <= length(bytes) || error("$label contains an unterminated array")
            bytes[index] == UInt8(']') && return index + 1
            bytes[index] == UInt8(',') ||
                error("$label contains malformed array separators")
            index = _ld1b_json_skip_whitespace(bytes, index + 1)
        end
    elseif byte == UInt8('"')
        _, index = _ld1b_json_scan_string(bytes, index, label)
        return index
    end
    first_index = index
    while index <= length(bytes) && !(bytes[index] in (
            UInt8(' '), UInt8('\t'), UInt8('\r'), UInt8('\n'), UInt8(','),
            UInt8(']'), UInt8('}')))
        index += 1
    end
    index > first_index || error("$label contains an empty JSON value")
    return index
end

function _ld1b_reject_duplicate_json_keys(bytes, label::AbstractString)
    index = _ld1b_json_scan_value(bytes, 1, label, 0)
    index = _ld1b_json_skip_whitespace(bytes, index)
    index == length(bytes) + 1 ||
        error("$label contains trailing data after its JSON value")
    return true
end

function _ld1b_path_within(path::AbstractString, boundary::AbstractString)
    relative = relpath(normpath(path), normpath(boundary))
    separator = Base.Filesystem.path_separator
    return relative == "." ||
        !(relative == ".." || startswith(relative, string("..", separator)))
end

_ld1b_path_occupied(path::AbstractString) = ispath(path) || islink(path)

function _ld1b_reject_symlink_components(path::AbstractString,
        boundary::AbstractString)
    target = normpath(path)
    root = normpath(boundary)
    _ld1b_path_within(target, root) ||
        error("path escapes its declared archive boundary")
    current = target
    while _ld1b_path_within(current, root)
        islink(current) && error(
            "symbolic links are not allowed in the archive tree: $current")
        current == root && break
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    return true
end

function _ld1b_require_directory(path::AbstractString,
        boundary::AbstractString, label::AbstractString)
    normalized = normpath(path)
    _ld1b_reject_symlink_components(normalized, boundary)
    isdir(normalized) && !islink(normalized) ||
        error("$label is not a regular directory")
    _ld1b_path_within(realpath(normalized), realpath(boundary)) ||
        error("$label resolves outside its archive boundary")
    return normalized
end

function _ld1b_ensure_directory(path::AbstractString,
        boundary::AbstractString, label::AbstractString)
    normalized = normpath(path)
    _ld1b_reject_symlink_components(normalized, boundary)
    mkpath(normalized)
    return _ld1b_require_directory(normalized, boundary, label)
end

function _ld1b_directory_identity(path::AbstractString)
    metadata = lstat(path)
    return (device = metadata.device, inode = metadata.inode)
end

function _ld1b_regular_file_snapshot(path::AbstractString,
        boundary::AbstractString, label::AbstractString;
        require_single_link::Bool = true)
    normalized = normpath(path)
    _ld1b_reject_symlink_components(normalized, boundary)
    isfile(normalized) && !islink(normalized) ||
        error("$label is not a regular file")
    _ld1b_path_within(realpath(normalized), realpath(boundary)) ||
        error("$label resolves outside its archive boundary")
    bytes, opened = open(normalized, "r") do io
        metadata = stat(io)
        require_single_link && metadata.nlink != 1 &&
            error("$label must not be hard linked")
        return read(io), metadata
    end
    observed = lstat(normalized)
    isfile(normalized) && !islink(normalized) ||
        error("$label changed type while it was read")
    require_single_link && observed.nlink != 1 &&
        error("$label must not be hard linked")
    opened.device == observed.device && opened.inode == observed.inode ||
        error("$label was replaced while it was read")
    opened.size == observed.size == length(bytes) ||
        error("$label changed size while it was read")
    return (;
        bytes,
        nbytes = length(bytes),
        sha256 = bytes2hex(sha256(bytes)),
        device = opened.device,
        inode = opened.inode,
        nlink = observed.nlink,
    )
end

function _ld1b_read_json_snapshot(path::AbstractString,
        boundary::AbstractString, label::AbstractString;
        require_single_link::Bool = true)
    snapshot = _ld1b_regular_file_snapshot(path, boundary, label;
        require_single_link)
    _ld1b_reject_duplicate_json_keys(snapshot.bytes, label)
    parsed = try
        JSON3.read(String(copy(snapshot.bytes)))
    catch err
        error("$label is not valid JSON: " * portable_error_message(err))
    end
    return merge(snapshot, (; parsed = _ld1b_json_native(parsed)))
end

function _ld1b_portable_relative(path::AbstractString,
        root::AbstractString)
    relative = relpath(path, root)
    separator = Base.Filesystem.path_separator
    return separator == '/' ? relative : replace(relative, separator => '/')
end

function _ld1b_checked_exclusions(exclude)
    values = Set{String}()
    for value in exclude
        name = String(value)
        basename(name) == name && normpath(name) == name && name != "." ||
            error("inventory exclusions must be root-level basenames")
        push!(values, name)
    end
    return values
end

function ld1b_attempt_inventory(attempt_dir::AbstractString;
        exclude = _LD1B_CONTROL_FILENAMES)
    root = normpath(attempt_dir)
    isdir(root) && !islink(root) ||
        error("attempt directory is not a regular directory")
    _ld1b_reject_symlink_components(root, root)
    exclusions = _ld1b_checked_exclusions(exclude)
    rows = NamedTuple[]

    function visit(directory::String)
        for name in sort(readdir(directory))
            path = joinpath(directory, name)
            relative = _ld1b_portable_relative(path, root)
            relative in exclusions && continue
            islink(path) && error(
                "attempt inventory contains symbolic link: $relative")
            if isdir(path)
                push!(rows, (;
                    path = relative,
                    kind = :directory,
                    bytes = 0,
                    sha256 = nothing,
                    link_count = nothing,
                ))
                visit(path)
            elseif isfile(path)
                snapshot = _ld1b_regular_file_snapshot(
                    path, root, "attempt inventory file $relative")
                push!(rows, (;
                    path = relative,
                    kind = :file,
                    bytes = snapshot.nbytes,
                    sha256 = snapshot.sha256,
                    link_count = snapshot.nlink,
                ))
            elseif _ld1b_path_occupied(path)
                error("attempt inventory contains unsupported entry: $relative")
            else
                error("attempt inventory entry disappeared: $relative")
            end
        end
        return nothing
    end

    visit(root)
    sort!(rows; by = row -> (row.path, String(row.kind)))
    return Tuple(rows)
end

ld1b_attempt_inventory_sha256(attempt_dir::AbstractString;
    exclude = _LD1B_CONTROL_FILENAMES) =
    ld1b_archive_canonical_sha256(
        ld1b_attempt_inventory(attempt_dir; exclude))

function _ld1b_inventory_record(attempt_dir::AbstractString)
    rows = ld1b_attempt_inventory(attempt_dir;
        exclude = _LD1B_CONTROL_FILENAMES)
    return (;
        excluded_control_files = _LD1B_CONTROL_FILENAMES,
        n_files = count(row -> row.kind === :file, rows),
        n_directories = count(row -> row.kind === :directory, rows),
        total_file_bytes = sum(row.bytes for row in rows
            if row.kind === :file),
        rows_sha256 = ld1b_archive_canonical_sha256(rows),
    )
end

function _ld1b_plan_identity(value)
    native = _ld1b_require_keys(
        value, _LD1B_PLAN_REQUIRED_SHA_FIELDS, "plan identity")
    for field in _LD1B_PLAN_REQUIRED_SHA_FIELDS
        _ld1b_sha256(native[field], "plan identity $field")
    end
    return native, ld1b_archive_canonical_sha256(native)
end

function _ld1b_execution_source_identity(value)
    native = _ld1b_require_keys(value,
        _LD1B_EXECUTION_REQUIRED_SHA_FIELDS, "execution source identity")
    isempty(native) && error("execution source identity must not be empty")
    for (field, digest) in pairs(native)
        endswith(field, "sha256") || error(
            "execution source identity field must end in sha256: $field")
        _ld1b_sha256(digest, "execution source identity $field")
    end
    native["attempt_archive_source_sha256"] ==
        ld1b_attempt_archive_source_sha256() || error(
        "execution source identity does not match the attempt-archive source")
    local_json_sha256 = bytes2hex(open(sha256,
        joinpath(@__DIR__, "local_json.jl")))
    native["local_json_source_sha256"] == local_json_sha256 || error(
        "execution source identity does not match local_json.jl")
    return native, ld1b_archive_canonical_sha256(native)
end

function _ld1b_job_identity(value)
    native = _ld1b_require_keys(value,
        ("job_id", "row_index", "scenario_id", "replication"),
        "job identity")
    job_id = _ld1b_string(native["job_id"], "job identity job_id")
    (occursin('/', job_id) || occursin('\\', job_id)) &&
        error("job identity job_id must not contain a path separator")
    _ld1b_int(native["row_index"], "job identity row_index"; minimum = 1)
    _ld1b_string(native["scenario_id"], "job identity scenario_id")
    _ld1b_int(native["replication"], "job identity replication"; minimum = 1)
    return native, ld1b_archive_canonical_sha256(native)
end

function ld1b_execution_context(scope::Symbol = :pilot)
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
    error("unsupported LD1b execution scope: $scope")
end

function ld1b_validate_execution_context(value = ld1b_execution_context();
        expected_scope::Union{Nothing,Symbol} = nothing)
    if value isa Symbol
        value = ld1b_execution_context(value)
    end
    native = _ld1b_exact_keys(value, (
        "execution_scope",
        "root_namespace",
        "official_pilot_denominator_eligible",
    ), "execution context")
    scope = Symbol(_ld1b_string(
        native["execution_scope"], "execution scope"))
    expected = ld1b_execution_context(scope)
    observed = (;
        execution_scope = scope,
        root_namespace = Symbol(_ld1b_string(
            native["root_namespace"], "execution root namespace")),
        official_pilot_denominator_eligible = _ld1b_bool(
            native["official_pilot_denominator_eligible"],
            "official-pilot denominator eligibility",
        ),
    )
    observed == expected || error(
        "execution context differs from the frozen $scope contract")
    expected_scope === nothing || scope === expected_scope || error(
        "execution context has scope $scope; expected $expected_scope")
    return observed
end

function _ld1b_attempt_identity(number, role;
        execution_context = ld1b_execution_context())
    context = ld1b_validate_execution_context(execution_context)
    checked_number = _ld1b_int(number, "attempt number"; minimum = 1)
    checked_role = Symbol(_ld1b_string(String(role), "attempt role"))
    if context.execution_scope === :bounded_smoke
        checked_number == 1 || error(
            "bounded smoke permits only verification attempt 1")
        checked_role === :verification || error(
            "bounded-smoke attempt 1 must use the verification role")
        return (;
            number = 1,
            role = :verification,
            counts_toward_primary = false,
        )
    end
    expected_role = checked_number == 1 ? :primary : :remediation
    checked_role === expected_role ||
        error("attempt role does not match its number")
    return (;
        number = checked_number,
        role = checked_role,
        counts_toward_primary = checked_number == 1,
    )
end

function _ld1b_result_content_hash(value, label::AbstractString)
    return ld1b_verify_archive_content_hash(value; label)
end

function _ld1b_validate_result_binding(result,
        plan_sha256::AbstractString,
        execution_sha256::AbstractString,
        job_sha256::AbstractString,
        execution_context,
        attempt,
        terminal_status::Symbol,
        terminal_outcome_code::Symbol)
    native = _ld1b_require_keys(result, (
        "execution_context",
        "plan_identity",
        "execution_source_identity",
        "job",
        "attempt",
        "terminal_status",
        "terminal_outcome_code",
        "content_hash",
    ), "job result")
    expected_context = ld1b_validate_execution_context(execution_context)
    observed_context = ld1b_validate_execution_context(
        native["execution_context"];
        expected_scope = expected_context.execution_scope,
    )
    observed_context == expected_context || error(
        "job result execution context does not match the seal")
    ld1b_archive_canonical_sha256(native["plan_identity"]) == plan_sha256 ||
        error("job result plan identity does not match the seal")
    ld1b_archive_canonical_sha256(native["execution_source_identity"]) ==
        execution_sha256 || error(
        "job result execution source identity does not match the seal")
    ld1b_archive_canonical_sha256(native["job"]) == job_sha256 ||
        error("job result job identity does not match the seal")
    result_attempt = _ld1b_require_keys(native["attempt"],
        ("number", "role", "counts_toward_primary"),
        "job-result attempt identity")
    _ld1b_int(result_attempt["number"], "job-result attempt number") ==
        attempt.number || error("job result has the wrong attempt number")
    Symbol(_ld1b_string(result_attempt["role"],
        "job-result attempt role")) === attempt.role ||
        error("job result has the wrong attempt role")
    _ld1b_bool(result_attempt["counts_toward_primary"],
        "job-result primary contribution") ==
        attempt.counts_toward_primary || error(
        "job result has the wrong primary contribution")
    Symbol(_ld1b_string(native["terminal_status"],
        "job-result terminal status")) === terminal_status ||
        error("job result terminal status does not match the seal")
    Symbol(_ld1b_string(native["terminal_outcome_code"],
        "job-result terminal outcome code")) === terminal_outcome_code ||
        error("job result terminal outcome code does not match the seal")
    return _ld1b_result_content_hash(native, "job result")
end

function _ld1b_control_paths(attempt_dir::AbstractString)
    return (;
        seal = joinpath(attempt_dir, LD1B_ATTEMPT_SEAL_FILENAME),
        retirement = joinpath(attempt_dir, LD1B_ATTEMPT_RETIREMENT_FILENAME),
    )
end

function _ld1b_require_unfinalized(attempt_dir::AbstractString)
    paths = _ld1b_control_paths(attempt_dir)
    _ld1b_path_occupied(paths.seal) &&
        error("attempt already contains a completed-attempt seal")
    _ld1b_path_occupied(paths.retirement) &&
        error("attempt already contains a retirement marker")
    return paths
end

function _ld1b_seal_contract()
    return (;
        seal_is_terminal_visibility_boundary = true,
        execution_context_bound = true,
        execution_root_namespace_bound = true,
        published_after_result_validation = true,
        overwrite_allowed = false,
        seal_and_retirement_may_coexist = false,
        postseal_mutation_allowed = false,
        hardlinks_allowed = false,
        symlinks_allowed = false,
    )
end

function _ld1b_retirement_contract()
    return (;
        disposition_is_append_only = true,
        overwrite_allowed = false,
        seal_and_retirement_may_coexist = false,
        same_attempt_restart_allowed = false,
        chain_level_resume_allowed = false,
        retirement_counts_toward_primary = false,
        remediation_may_replace_primary = false,
        postretirement_mutation_allowed = false,
        hardlinks_allowed = false,
        symlinks_allowed = false,
    )
end

function ld1b_completed_attempt_seal(attempt_dir::AbstractString;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        terminal_status,
        terminal_outcome_code,
        evidence_manifest_sha256,
        execution_context = ld1b_execution_context(),
        result_filename::AbstractString = LD1B_RESULT_FILENAME)
    root = normpath(attempt_dir)
    isdir(root) && !islink(root) ||
        error("attempt directory is not a regular directory")
    _ld1b_require_unfinalized(root)
    result_filename == basename(result_filename) &&
        !(result_filename in _LD1B_CONTROL_FILENAMES) ||
        error("result filename must be a non-control basename")
    plan, plan_sha256 = _ld1b_plan_identity(plan_identity)
    execution, execution_sha256 =
        _ld1b_execution_source_identity(execution_source_identity)
    job, job_sha256 = _ld1b_job_identity(job_identity)
    context = ld1b_validate_execution_context(execution_context)
    attempt = _ld1b_attempt_identity(
        attempt_number,
        attempt_role;
        execution_context = context,
    )
    status = Symbol(_ld1b_string(String(terminal_status), "terminal status"))
    outcome = Symbol(_ld1b_string(String(terminal_outcome_code),
        "terminal outcome code"))
    evidence_sha256 = _ld1b_sha256(evidence_manifest_sha256,
        "evidence-manifest SHA-256")
    result_path = joinpath(root, result_filename)
    result_snapshot = _ld1b_read_json_snapshot(
        result_path, root, "job result")
    result_content_hash = _ld1b_validate_result_binding(
        result_snapshot.parsed,
        plan_sha256,
        execution_sha256,
        job_sha256,
        context,
        attempt,
        status,
        outcome,
    )
    inventory = _ld1b_inventory_record(root)
    result_relative = _ld1b_portable_relative(result_path, root)
    result_row = only(row for row in ld1b_attempt_inventory(root)
        if row.kind === :file && row.path == result_relative)
    result_row.bytes == result_snapshot.nbytes &&
        result_row.sha256 == result_snapshot.sha256 ||
        error("job result changed while the seal was constructed")
    material = (;
        schema = LD1B_ATTEMPT_SEAL_SCHEMA,
        object = :local_dependence_pilot_attempt_seal,
        scope = :ld1b_completed_attempt_terminal_boundary,
        execution_context = context,
        plan_identity = plan,
        plan_identity_sha256 = plan_sha256,
        execution_source_identity = execution,
        execution_source_identity_sha256 = execution_sha256,
        job_identity = job,
        job_identity_sha256 = job_sha256,
        attempt,
        terminal_status = status,
        terminal_outcome_code = outcome,
        result = (;
            path = result_relative,
            bytes = result_snapshot.nbytes,
            sha256 = result_snapshot.sha256,
            content_hash = result_content_hash,
        ),
        evidence_manifest_sha256 = evidence_sha256,
        inventory,
        contract = _ld1b_seal_contract(),
    )
    return ld1b_archive_with_content_hash(material)
end

function _ld1b_validate_seal_artifact(value;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        terminal_status,
        terminal_outcome_code,
        execution_context = ld1b_execution_context())
    native = _ld1b_exact_keys(value, (
        "schema", "object", "scope", "execution_context", "plan_identity",
        "plan_identity_sha256", "execution_source_identity",
        "execution_source_identity_sha256", "job_identity",
        "job_identity_sha256", "attempt", "terminal_status",
        "terminal_outcome_code", "result", "evidence_manifest_sha256",
        "inventory", "contract", "content_hash",
    ), "completed-attempt seal")
    content_hash = ld1b_verify_archive_content_hash(
        native; label = "completed-attempt seal")
    _ld1b_string(native["schema"], "seal schema") ==
        LD1B_ATTEMPT_SEAL_SCHEMA || error("unexpected attempt-seal schema")
    _ld1b_string(native["object"], "seal object") ==
        "local_dependence_pilot_attempt_seal" ||
        error("unexpected attempt-seal object")
    _ld1b_string(native["scope"], "seal scope") ==
        "ld1b_completed_attempt_terminal_boundary" ||
        error("unexpected attempt-seal scope")
    expected_context = ld1b_validate_execution_context(execution_context)
    observed_context = ld1b_validate_execution_context(
        native["execution_context"];
        expected_scope = expected_context.execution_scope,
    )
    observed_context == expected_context || error(
        "completed-attempt seal has the wrong execution context")
    plan, plan_sha256 = _ld1b_plan_identity(plan_identity)
    execution, execution_sha256 =
        _ld1b_execution_source_identity(execution_source_identity)
    job, job_sha256 = _ld1b_job_identity(job_identity)
    ld1b_archive_canonical_sha256(native["plan_identity"]) == plan_sha256 &&
        _ld1b_sha256(native["plan_identity_sha256"],
            "seal plan identity SHA-256") == plan_sha256 ||
        error("seal plan identity mismatch")
    ld1b_archive_canonical_sha256(native["execution_source_identity"]) ==
        execution_sha256 && _ld1b_sha256(
            native["execution_source_identity_sha256"],
            "seal execution source identity SHA-256") == execution_sha256 ||
        error("seal execution source identity mismatch")
    ld1b_archive_canonical_sha256(native["job_identity"]) == job_sha256 &&
        _ld1b_sha256(native["job_identity_sha256"],
            "seal job identity SHA-256") == job_sha256 ||
        error("seal job identity mismatch")
    attempt = _ld1b_attempt_identity(
        attempt_number,
        attempt_role;
        execution_context = expected_context,
    )
    observed_attempt = _ld1b_exact_keys(native["attempt"],
        ("number", "role", "counts_toward_primary"), "seal attempt")
    _ld1b_int(observed_attempt["number"], "seal attempt number") ==
        attempt.number && Symbol(_ld1b_string(observed_attempt["role"],
            "seal attempt role")) === attempt.role &&
        _ld1b_bool(observed_attempt["counts_toward_primary"],
            "seal primary role") == attempt.counts_toward_primary ||
        error("seal attempt identity mismatch")
    status = Symbol(_ld1b_string(String(terminal_status), "terminal status"))
    outcome = Symbol(_ld1b_string(String(terminal_outcome_code),
        "terminal outcome code"))
    Symbol(_ld1b_string(native["terminal_status"], "seal terminal status")) ===
        status || error("seal terminal status mismatch")
    Symbol(_ld1b_string(native["terminal_outcome_code"],
        "seal terminal outcome code")) === outcome ||
        error("seal terminal outcome code mismatch")
    result = _ld1b_exact_keys(native["result"],
        ("path", "bytes", "sha256", "content_hash"), "seal result")
    result_path = _ld1b_string(result["path"], "seal result path")
    isabspath(result_path) && error("seal result path must be relative")
    normpath(result_path) == result_path && !startswith(result_path, "..") ||
        error("seal result path escapes the attempt")
    _ld1b_int(result["bytes"], "seal result bytes"; minimum = 1)
    _ld1b_sha256(result["sha256"], "seal result SHA-256")
    _ld1b_sha256(result["content_hash"], "seal result content hash")
    evidence_manifest_sha256 = _ld1b_sha256(
        native["evidence_manifest_sha256"], "seal evidence-manifest SHA-256")
    inventory = _ld1b_exact_keys(native["inventory"], (
        "excluded_control_files", "n_files", "n_directories",
        "total_file_bytes", "rows_sha256",
    ), "seal inventory")
    Tuple(String(value) for value in inventory["excluded_control_files"]) ==
        _LD1B_CONTROL_FILENAMES ||
        error("seal inventory excludes the wrong control files")
    _ld1b_int(inventory["n_files"], "seal inventory file count"; minimum = 1)
    _ld1b_int(inventory["n_directories"],
        "seal inventory directory count"; minimum = 0)
    _ld1b_int(inventory["total_file_bytes"],
        "seal inventory byte count"; minimum = 1)
    _ld1b_sha256(inventory["rows_sha256"], "seal inventory SHA-256")
    contract = _ld1b_exact_keys(native["contract"], keys(_ld1b_seal_contract()),
        "seal contract")
    ld1b_archive_canonical_sha256(contract) ==
        ld1b_archive_canonical_sha256(_ld1b_seal_contract()) ||
        error("seal contract was modified")
    return (;
        native,
        content_hash,
        plan,
        plan_sha256,
        execution,
        execution_sha256,
        job,
        job_sha256,
        execution_context = observed_context,
        attempt,
        terminal_status = status,
        terminal_outcome_code = outcome,
        result,
        evidence_manifest_sha256,
        inventory,
    )
end

function ld1b_validate_completed_attempt_seal(attempt_dir::AbstractString;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        terminal_status,
        terminal_outcome_code,
        execution_context = ld1b_execution_context())
    root = normpath(attempt_dir)
    isdir(root) && !islink(root) ||
        error("attempt directory is not a regular directory")
    paths = _ld1b_control_paths(root)
    _ld1b_path_occupied(paths.retirement) && error(
        "completed seal and retirement marker must not coexist")
    snapshot = _ld1b_read_json_snapshot(
        paths.seal, root, "completed-attempt seal")
    seal = _ld1b_validate_seal_artifact(snapshot.parsed;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        terminal_status,
        terminal_outcome_code,
        execution_context,
    )
    result_path = normpath(joinpath(root, String(seal.result["path"])))
    _ld1b_path_within(result_path, root) ||
        error("sealed job-result path escapes the attempt")
    result_snapshot = _ld1b_read_json_snapshot(
        result_path, root, "sealed job result")
    result_content_hash = _ld1b_validate_result_binding(
        result_snapshot.parsed,
        seal.plan_sha256,
        seal.execution_sha256,
        seal.job_sha256,
        seal.execution_context,
        seal.attempt,
        seal.terminal_status,
        seal.terminal_outcome_code,
    )
    result_snapshot.nbytes == _ld1b_int(
        seal.result["bytes"], "sealed result bytes") &&
        result_snapshot.sha256 == String(seal.result["sha256"]) &&
        result_content_hash == String(seal.result["content_hash"]) ||
        error("sealed job result differs from the seal")
    inventory = _ld1b_inventory_record(root)
    ld1b_archive_canonical_sha256(inventory) ==
        ld1b_archive_canonical_sha256(seal.inventory) ||
        error("attempt inventory differs from the completed seal")
    return (;
        valid = true,
        state = :sealed_terminal,
        terminal_status = seal.terminal_status,
        terminal_outcome_code = seal.terminal_outcome_code,
        execution_context = seal.execution_context,
        counts_toward_primary = seal.attempt.counts_toward_primary,
        seal_file_sha256 = snapshot.sha256,
        seal_content_hash = seal.content_hash,
        result_file_sha256 = result_snapshot.sha256,
        result_content_hash,
        evidence_manifest_sha256 = seal.evidence_manifest_sha256,
        attempt_inventory_sha256 = String(inventory.rows_sha256),
        n_inventory_files = inventory.n_files,
        n_inventory_directories = inventory.n_directories,
    )
end

function ld1b_retirement_marker(attempt_dir::AbstractString;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        retirement_reason_code,
        review_record_sha256,
        process_confirmed_stopped::Bool)
    root = normpath(attempt_dir)
    isdir(root) && !islink(root) ||
        error("attempt directory is not a regular directory")
    _ld1b_require_unfinalized(root)
    process_confirmed_stopped ||
        error("retirement requires confirmation that the process stopped")
    plan, plan_sha256 = _ld1b_plan_identity(plan_identity)
    execution, execution_sha256 =
        _ld1b_execution_source_identity(execution_source_identity)
    job, job_sha256 = _ld1b_job_identity(job_identity)
    attempt = _ld1b_attempt_identity(attempt_number, attempt_role)
    reason = Symbol(_ld1b_string(String(retirement_reason_code),
        "retirement reason code"))
    review_sha256 = _ld1b_sha256(review_record_sha256,
        "retirement review-record SHA-256")
    material = (;
        schema = LD1B_ATTEMPT_RETIREMENT_SCHEMA,
        object = :local_dependence_pilot_attempt_retirement,
        scope = :ld1b_interrupted_attempt_append_only_disposition,
        plan_identity = plan,
        plan_identity_sha256 = plan_sha256,
        execution_source_identity = execution,
        execution_source_identity_sha256 = execution_sha256,
        job_identity = job,
        job_identity_sha256 = job_sha256,
        attempt,
        terminal_status = nothing,
        terminal_outcome_code = :interrupted_attempt_retired_nonterminal,
        retirement = (;
            reason_code = reason,
            review_record_sha256 = review_sha256,
            process_confirmed_stopped = true,
            retirement_counts_toward_primary = false,
        ),
        observed_inventory = _ld1b_inventory_record(root),
        contract = _ld1b_retirement_contract(),
    )
    return ld1b_archive_with_content_hash(material)
end

function _ld1b_validate_retirement_artifact(value;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        expected_reason_code = nothing,
        expected_review_record_sha256 = nothing)
    native = _ld1b_exact_keys(value, (
        "schema", "object", "scope", "plan_identity",
        "plan_identity_sha256", "execution_source_identity",
        "execution_source_identity_sha256", "job_identity",
        "job_identity_sha256", "attempt", "terminal_status",
        "terminal_outcome_code", "retirement", "observed_inventory",
        "contract", "content_hash",
    ), "attempt-retirement marker")
    content_hash = ld1b_verify_archive_content_hash(
        native; label = "attempt-retirement marker")
    _ld1b_string(native["schema"], "retirement schema") ==
        LD1B_ATTEMPT_RETIREMENT_SCHEMA ||
        error("unexpected attempt-retirement schema")
    _ld1b_string(native["object"], "retirement object") ==
        "local_dependence_pilot_attempt_retirement" ||
        error("unexpected attempt-retirement object")
    _ld1b_string(native["scope"], "retirement scope") ==
        "ld1b_interrupted_attempt_append_only_disposition" ||
        error("unexpected attempt-retirement scope")
    plan, plan_sha256 = _ld1b_plan_identity(plan_identity)
    execution, execution_sha256 =
        _ld1b_execution_source_identity(execution_source_identity)
    job, job_sha256 = _ld1b_job_identity(job_identity)
    ld1b_archive_canonical_sha256(native["plan_identity"]) == plan_sha256 &&
        _ld1b_sha256(native["plan_identity_sha256"],
            "retirement plan identity SHA-256") == plan_sha256 ||
        error("retirement plan identity mismatch")
    ld1b_archive_canonical_sha256(native["execution_source_identity"]) ==
        execution_sha256 && _ld1b_sha256(
            native["execution_source_identity_sha256"],
            "retirement execution identity SHA-256") == execution_sha256 ||
        error("retirement execution source identity mismatch")
    ld1b_archive_canonical_sha256(native["job_identity"]) == job_sha256 &&
        _ld1b_sha256(native["job_identity_sha256"],
            "retirement job identity SHA-256") == job_sha256 ||
        error("retirement job identity mismatch")
    attempt = _ld1b_attempt_identity(attempt_number, attempt_role)
    observed_attempt = _ld1b_exact_keys(native["attempt"],
        ("number", "role", "counts_toward_primary"), "retirement attempt")
    _ld1b_int(observed_attempt["number"], "retirement attempt number") ==
        attempt.number && Symbol(_ld1b_string(observed_attempt["role"],
            "retirement attempt role")) === attempt.role &&
        _ld1b_bool(observed_attempt["counts_toward_primary"],
            "retirement original primary role") ==
            attempt.counts_toward_primary ||
        error("retirement attempt identity mismatch")
    native["terminal_status"] === nothing ||
        error("retired interruption must remain nonterminal")
    _ld1b_string(native["terminal_outcome_code"],
        "retirement outcome code") ==
        "interrupted_attempt_retired_nonterminal" ||
        error("retirement outcome code was modified")
    retirement = _ld1b_exact_keys(native["retirement"],
        ("reason_code", "review_record_sha256", "process_confirmed_stopped",
            "retirement_counts_toward_primary"),
        "retirement review")
    reason = Symbol(_ld1b_string(retirement["reason_code"],
        "retirement reason code"))
    review_sha256 = _ld1b_sha256(retirement["review_record_sha256"],
        "retirement review-record SHA-256")
    _ld1b_bool(retirement["process_confirmed_stopped"],
        "retirement process confirmation") ||
        error("retirement lacks stopped-process confirmation")
    retirement_counts_toward_primary = _ld1b_bool(
        retirement["retirement_counts_toward_primary"],
        "retirement scientific contribution")
    retirement_counts_toward_primary && error(
        "retirement must not count toward the primary scientific outcome")
    expected_reason_code === nothing ||
        reason === Symbol(expected_reason_code) ||
        error("retirement reason code mismatch")
    expected_review_record_sha256 === nothing ||
        review_sha256 == _ld1b_sha256(expected_review_record_sha256,
            "expected retirement review-record SHA-256") ||
        error("retirement review-record SHA-256 mismatch")
    inventory = _ld1b_exact_keys(native["observed_inventory"], (
        "excluded_control_files", "n_files", "n_directories",
        "total_file_bytes", "rows_sha256",
    ), "retirement inventory")
    Tuple(String(value) for value in inventory["excluded_control_files"]) ==
        _LD1B_CONTROL_FILENAMES ||
        error("retirement inventory excludes the wrong control files")
    _ld1b_int(inventory["n_files"], "retirement file count"; minimum = 0)
    _ld1b_int(inventory["n_directories"],
        "retirement directory count"; minimum = 0)
    _ld1b_int(inventory["total_file_bytes"],
        "retirement byte count"; minimum = 0)
    _ld1b_sha256(inventory["rows_sha256"], "retirement inventory SHA-256")
    contract = _ld1b_exact_keys(native["contract"],
        keys(_ld1b_retirement_contract()), "retirement contract")
    ld1b_archive_canonical_sha256(contract) ==
        ld1b_archive_canonical_sha256(_ld1b_retirement_contract()) ||
        error("retirement contract was modified")
    return (;
        native,
        content_hash,
        plan,
        plan_sha256,
        execution,
        execution_sha256,
        job,
        job_sha256,
        attempt,
        reason,
        review_sha256,
        retirement_counts_toward_primary,
        inventory,
    )
end

function ld1b_validate_attempt_retirement_marker(attempt_dir::AbstractString;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        expected_reason_code = nothing,
        expected_review_record_sha256 = nothing)
    root = normpath(attempt_dir)
    isdir(root) && !islink(root) ||
        error("attempt directory is not a regular directory")
    paths = _ld1b_control_paths(root)
    _ld1b_path_occupied(paths.seal) && error(
        "completed seal and retirement marker must not coexist")
    snapshot = _ld1b_read_json_snapshot(
        paths.retirement, root, "attempt-retirement marker")
    retirement = _ld1b_validate_retirement_artifact(snapshot.parsed;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        expected_reason_code,
        expected_review_record_sha256,
    )
    inventory = _ld1b_inventory_record(root)
    ld1b_archive_canonical_sha256(inventory) ==
        ld1b_archive_canonical_sha256(retirement.inventory) ||
        error("attempt inventory differs from the retirement marker")
    return (;
        valid = true,
        state = :retired_interrupted,
        terminal_status = nothing,
        terminal_outcome_code = :interrupted_attempt_retired_nonterminal,
        retirement_reason_code = retirement.reason,
        retirement_file_sha256 = snapshot.sha256,
        retirement_content_hash = retirement.content_hash,
        review_record_sha256 = retirement.review_sha256,
        attempt_inventory_sha256 = String(inventory.rows_sha256),
        n_inventory_files = inventory.n_files,
        n_inventory_directories = inventory.n_directories,
        original_slot_counts_toward_primary =
            retirement.attempt.counts_toward_primary,
        retirement_counts_toward_primary =
            retirement.retirement_counts_toward_primary,
        same_attempt_restart_allowed = false,
        remediation_may_replace_primary = false,
    )
end

function ld1b_atomic_publish_json_create_new(path::AbstractString,
        artifact, staging_dir::AbstractString, boundary::AbstractString;
        semantic_validator,
        artifact_label::AbstractString = "archive artifact",
        _fault_injection_stage = nothing)
    target = normpath(path)
    staging = normpath(staging_dir)
    root = normpath(boundary)
    isdir(root) && !islink(root) ||
        error("archive publication boundary is not a regular directory")
    _ld1b_path_within(target, root) ||
        error("publish target escapes its archive boundary")
    _ld1b_path_within(staging, root) ||
        error("staging directory escapes its archive boundary")
    ld1b_verify_archive_content_hash(artifact;
        label = "proposed $artifact_label")
    bytes = _ld1b_encode_json_bytes(artifact)
    target_parent = dirname(target)
    _ld1b_require_directory(target_parent, root, "publish target parent")
    _ld1b_ensure_directory(staging, root, "publication staging directory")
    target_parent_identity = _ld1b_directory_identity(target_parent)
    staging_identity = _ld1b_directory_identity(staging)
    target_parent_identity.device == staging_identity.device ||
        error("staging and target directories are not on the same volume")
    (_fault_injection_stage === nothing ||
        _fault_injection_stage in _LD1B_PUBLICATION_FAULT_STAGES) || error(
        "unknown publication fault-injection stage")
    _ld1b_path_occupied(target) &&
        error("refusing to replace an existing publication target")

    temporary_path, io = mktemp(staging)
    published = false
    fault_injected = false
    function inject_fault(stage::Symbol)
        if _fault_injection_stage === stage
            fault_injected = true
            error("injected CREATE_NEW publication fault at $(String(stage))")
        end
        return nothing
    end
    try
        write(io, bytes)
        flush(io)
        close(io)
        temporary_snapshot = _ld1b_read_json_snapshot(
            temporary_path, root, "staging $artifact_label")
        temporary_snapshot.nbytes == length(bytes) ||
            error("staging artifact byte count changed")
        ld1b_verify_archive_content_hash(temporary_snapshot.parsed;
            label = "staging $artifact_label")
        semantic_validator(temporary_snapshot.parsed)
        _ld1b_reject_symlink_components(target_parent, root)
        _ld1b_directory_identity(target_parent) == target_parent_identity ||
            error("target parent identity changed before publication")
        _ld1b_path_occupied(target) &&
            error("publication target became occupied")
        inject_fault(:pre_link)
        try
            hardlink(temporary_path, target)
        catch err
            error("hardlink CREATE_NEW publication failed closed: " *
                portable_error_message(err))
        end
        published = true
        inject_fault(:post_link_pre_unlink)
        rm(temporary_path)
        _ld1b_path_occupied(temporary_path) && error(
            "staging link remained occupied after publication unlink")
        inject_fault(:post_unlink_pre_validation)
        _ld1b_directory_identity(target_parent) == target_parent_identity ||
            error("target parent identity changed during publication")
        _ld1b_directory_identity(staging) == staging_identity ||
            error("staging directory identity changed during publication")
        target_snapshot = _ld1b_read_json_snapshot(
            target, root, "published $artifact_label")
        target_snapshot.sha256 == temporary_snapshot.sha256 &&
            target_snapshot.nbytes == temporary_snapshot.nbytes ||
            error("published artifact differs from staging bytes")
        content_hash = ld1b_verify_archive_content_hash(target_snapshot.parsed;
            label = "published $artifact_label")
        semantic_validation = semantic_validator(target_snapshot.parsed)
        return (;
            path = target,
            file_sha256 = target_snapshot.sha256,
            content_hash,
            nbytes = target_snapshot.nbytes,
            publication = :same_volume_hardlink_create_new,
            overwrite_allowed = false,
            published,
            semantic_validation,
        )
    finally
        isopen(io) && close(io)
        !fault_injected && _ld1b_path_occupied(temporary_path) &&
            rm(temporary_path; force = true)
    end
end

function ld1b_reconcile_json_create_new_staging_alias(
        path::AbstractString,
        artifact,
        staging_dir::AbstractString,
        boundary::AbstractString;
        semantic_validator,
        artifact_label::AbstractString = "archive artifact")
    target = normpath(path)
    staging = normpath(staging_dir)
    root = normpath(boundary)
    isdir(root) && !islink(root) ||
        error("archive reconciliation boundary is not a regular directory")
    _ld1b_path_within(target, root) ||
        error("reconciliation target escapes its archive boundary")
    _ld1b_path_within(staging, root) ||
        error("reconciliation staging directory escapes its archive boundary")
    ld1b_verify_archive_content_hash(artifact;
        label = "expected $artifact_label")
    expected_bytes = _ld1b_encode_json_bytes(artifact)
    target_parent = dirname(target)
    _ld1b_require_directory(
        target_parent, root, "reconciliation target parent")
    _ld1b_require_directory(
        staging, root, "reconciliation staging directory")
    target_parent_identity = _ld1b_directory_identity(target_parent)
    staging_identity = _ld1b_directory_identity(staging)
    target_parent_identity.device == staging_identity.device || error(
        "reconciliation staging and target directories are not on the same volume")

    target_snapshot = _ld1b_read_json_snapshot(
        target, root, "reconciliation target $artifact_label";
        require_single_link = false)
    target_snapshot.nlink == 2 || error(
        "reconciliation requires exactly one target and one staging hardlink")
    target_snapshot.bytes == expected_bytes || error(
        "reconciliation target differs from the expected artifact bytes")
    ld1b_verify_archive_content_hash(target_snapshot.parsed;
        label = "reconciliation target $artifact_label")
    semantic_validator(target_snapshot.parsed)

    aliases = String[]
    for name in sort(readdir(staging))
        candidate = joinpath(staging, name)
        _ld1b_path_occupied(candidate) || error(
            "reconciliation staging entry disappeared")
        islink(candidate) && continue
        isfile(candidate) || continue
        metadata = lstat(candidate)
        if metadata.device == target_snapshot.device &&
                metadata.inode == target_snapshot.inode
            push!(aliases, candidate)
        end
    end
    length(aliases) == 1 || error(
        "reconciliation requires exactly one matching staging alias")
    alias = only(aliases)
    alias_snapshot = _ld1b_regular_file_snapshot(
        alias, root, "reconciliation staging alias";
        require_single_link = false)
    alias_snapshot.device == target_snapshot.device &&
        alias_snapshot.inode == target_snapshot.inode &&
        alias_snapshot.nlink == 2 &&
        alias_snapshot.bytes == target_snapshot.bytes &&
        alias_snapshot.bytes == expected_bytes || error(
        "reconciliation staging alias identity or bytes changed")
    _ld1b_directory_identity(target_parent) == target_parent_identity ||
        error("target parent identity changed during reconciliation")
    _ld1b_directory_identity(staging) == staging_identity ||
        error("staging directory identity changed during reconciliation")
    alias_identity = lstat(alias)
    alias_identity.device == target_snapshot.device &&
        alias_identity.inode == target_snapshot.inode || error(
        "reconciliation staging alias was replaced before unlink")

    rm(alias)
    _ld1b_path_occupied(alias) && error(
        "reconciliation staging alias remained occupied after unlink")
    reconciled_snapshot = _ld1b_read_json_snapshot(
        target, root, "reconciled $artifact_label")
    reconciled_snapshot.bytes == expected_bytes &&
        reconciled_snapshot.device == target_snapshot.device &&
        reconciled_snapshot.inode == target_snapshot.inode || error(
        "reconciled target identity or bytes changed")
    content_hash = ld1b_verify_archive_content_hash(
        reconciled_snapshot.parsed; label = "reconciled $artifact_label")
    semantic_validation = semantic_validator(reconciled_snapshot.parsed)
    _ld1b_directory_identity(target_parent) == target_parent_identity ||
        error("target parent identity changed after reconciliation")
    _ld1b_directory_identity(staging) == staging_identity ||
        error("staging directory identity changed after reconciliation")
    return (;
        path = target,
        file_sha256 = reconciled_snapshot.sha256,
        content_hash,
        nbytes = reconciled_snapshot.nbytes,
        publication = :same_volume_hardlink_create_new,
        reconciled = true,
        staging_alias_removed = true,
        semantic_validation,
    )
end

function ld1b_publish_completed_attempt_seal(attempt_dir::AbstractString;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        terminal_status,
        terminal_outcome_code,
        evidence_manifest_sha256,
        staging_dir::AbstractString,
        boundary::AbstractString,
        execution_context = ld1b_execution_context(),
        result_filename::AbstractString = LD1B_RESULT_FILENAME)
    artifact = ld1b_completed_attempt_seal(attempt_dir;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        terminal_status,
        terminal_outcome_code,
        evidence_manifest_sha256,
        execution_context,
        result_filename,
    )
    path = joinpath(attempt_dir, LD1B_ATTEMPT_SEAL_FILENAME)
    publication = ld1b_atomic_publish_json_create_new(
        path, artifact, staging_dir, boundary;
        artifact_label = "completed-attempt seal",
        semantic_validator = value -> _ld1b_validate_seal_artifact(value;
            plan_identity,
            execution_source_identity,
            job_identity,
            attempt_number,
            attempt_role,
            terminal_status,
            terminal_outcome_code,
            execution_context,
        ),
    )
    validation = ld1b_validate_completed_attempt_seal(attempt_dir;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        terminal_status,
        terminal_outcome_code,
        execution_context,
    )
    return (; artifact, publication, validation)
end

function ld1b_publish_attempt_retirement_marker(attempt_dir::AbstractString;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        retirement_reason_code,
        review_record_sha256,
        process_confirmed_stopped::Bool,
        staging_dir::AbstractString,
        boundary::AbstractString)
    artifact = ld1b_retirement_marker(attempt_dir;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        retirement_reason_code,
        review_record_sha256,
        process_confirmed_stopped,
    )
    path = joinpath(attempt_dir, LD1B_ATTEMPT_RETIREMENT_FILENAME)
    publication = ld1b_atomic_publish_json_create_new(
        path, artifact, staging_dir, boundary;
        artifact_label = "attempt-retirement marker",
        semantic_validator = value -> _ld1b_validate_retirement_artifact(value;
            plan_identity,
            execution_source_identity,
            job_identity,
            attempt_number,
            attempt_role,
            expected_reason_code = retirement_reason_code,
            expected_review_record_sha256 = review_record_sha256,
        ),
    )
    validation = ld1b_validate_attempt_retirement_marker(attempt_dir;
        plan_identity,
        execution_source_identity,
        job_identity,
        attempt_number,
        attempt_role,
        expected_reason_code = retirement_reason_code,
        expected_review_record_sha256 = review_record_sha256,
    )
    return (; artifact, publication, validation)
end

end # module
