#!/usr/bin/env julia

using BayesianMGMFRM
using Dates
using JSON3
using LinearAlgebra
using Pkg
using SHA
using Statistics
using TOML

include(joinpath(@__DIR__, "local_json.jl"))

const FREECORR_RUNNER_ROOT = normpath(joinpath(@__DIR__, ".."))
const FREECORR_RUNNER_PATH = normpath(@__FILE__)
const FREECORR_LOCAL_JSON_PATH = normpath(joinpath(@__DIR__, "local_json.jl"))
const FREECORR_DEFAULT_ATTEMPT_ROOT = joinpath(
    FREECORR_RUNNER_ROOT,
    "artifacts",
    "mgmfrm_free_latent_correlation_2d_study",
)
const FREECORR_TEST_ROOT_ENV =
    "BAYESIANMGMFRM_FREECORR_RUNNER_ALLOW_TEST_ROOT"

const FREECORR_DRY_RUN_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_archive_dry_run.v1"
const FREECORR_STATUS_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_archive_status.v1"
const FREECORR_SOURCE_RECEIPT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_source_snapshot.v1"
const FREECORR_ENVIRONMENT_RECEIPT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_environment_snapshot.v1"
const FREECORR_RESOURCE_PROBE_RECEIPT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_resource_probe_receipt.v1"
const FREECORR_RESOURCE_PROBE_RESERVATION_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_resource_probe_reservation.v1"
const FREECORR_RESOURCE_PROBE_FAILURE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_resource_probe_failure.v1"
const FREECORR_CANONICAL_FORMAT =
    :freecorr_local_json_sorted_compact_v1
const FREECORR_UNSUPPORTED_SCIENTIFIC_STATE =
    :unsupported_scientific_attempt_for_preexecution_runner_v1
const FREECORR_STAGING_DIRECTORY = ".preexecution_staging"
const FREECORR_ATTEMPT_DIRECTORY = "attempt_001"
const FREECORR_RESOURCE_PROBE_DIRECTORY = "resource_probes"
const FREECORR_RESOURCE_PROBE_FILENAME =
    "initial_gradient_probe_attempt_001.json"
const FREECORR_RESOURCE_PROBE_RESERVATION_FILENAME =
    "initial_gradient_probe_attempt_001.reservation.json"
const FREECORR_RESOURCE_PROBE_FAILURE_FILENAME =
    "initial_gradient_probe_attempt_001.failure.json"
const FREECORR_RESOURCE_PROBE_REPETITIONS = 3
const FREECORR_SCIENTIFIC_STATE_FILENAMES = (
    "started.json",
    "generation_completed.json",
    "terminal_result.json",
    "worker_exit.json",
    "worker.log",
)

function freecorr_runner_usage()
    return """
    Inspect and run MCMC-free prerequisites for the quarantined
    free-correlation single-unit archive.

    Usage:
      julia --project=. scripts/run_mgmfrm_free_latent_correlation_2d_study_unit.jl [options]

    Options:
      --mode MODE          status (default), dry-run, resource-probe,
                           validate, or execute-primary.
      --unit-id ID         Exactly one canonical v2 study unit id.
      --artifact PATH      Validate one dry-run artifact or the fixed
                           resource-probe receipt.
      --attempt-root PATH  Archive root. Production use is fixed to the default.
      --confirm-scientific-mcmc
                           Recognized only by execute-primary. Execution remains
                           blocked before archive reservation.
      --allow-test-root    Permit a root below the system temp directory only
                           when $FREECORR_TEST_ROOT_ENV=1.

    The resource-probe mode is fixed to the first feasibility unit and three
    initial-gradient repetitions. It never runs MCMC and first publishes an
    immutable reservation outside the scientific attempt tree. The reservation
    permanently consumes attempt 001, including after interruption or failure.
    This v1 runner never interprets or creates scientific attempt state. Any
    unit/attempt directory is invalid. There is no batch, retry, resume, force,
    seed, sampler, or raw-sample option.
    """
end

function freecorr_json_native(value; path::AbstractString = "\$")
    if value isa NamedTuple || value isa AbstractDict
        result = Dict{String,Any}()
        original_keys = Dict{String,Any}()
        for (key, element) in pairs(value)
            key isa Symbol || key isa AbstractString || error(
                "JSON object key at $path must be String or Symbol",
            )
            normalized = String(key)
            if haskey(result, normalized)
                error(
                    "JSON key collision at $path after String/Symbol normalization: " *
                    repr(original_keys[normalized]) * " and " * repr(key),
                )
            end
            original_keys[normalized] = key
            result[normalized] = freecorr_json_native(
                element;
                path = string(path, ".", normalized),
            )
        end
        return result
    elseif value isa AbstractArray || value isa Tuple
        return [freecorr_json_native(
            element;
            path = string(path, "[", index, "]"),
        ) for (index, element) in pairs(value)]
    elseif value isa AbstractFloat
        isfinite(value) || error("non-finite JSON number is forbidden at $path")
        return value
    elseif value isa Symbol
        return String(value)
    elseif ismissing(value)
        return nothing
    elseif value === nothing || value isa Bool || value isa Integer ||
            value isa AbstractString
        return value
    end
    error("unsupported JSON value type at $path: $(typeof(value))")
end

function freecorr_canonical_sha256(value)
    native = freecorr_json_native(value)
    io = IOBuffer()
    write_canonical_json(io, native)
    return bytes2hex(sha256(take!(io)))
end

function freecorr_content_hash_record(value; covers::Symbol)
    return (;
        algorithm = :sha256,
        value = freecorr_canonical_sha256(value),
        covers,
        canonical_format = FREECORR_CANONICAL_FORMAT,
    )
end

function freecorr_with_content_hash(value)
    return merge(value, (;
        content_hash = freecorr_content_hash_record(
            value;
            covers = :artifact_without_content_hash,
        ),
    ))
end

function freecorr_exact_keys(value, expected, label::AbstractString)
    value isa AbstractDict || error("$label must be a JSON object")
    observed = Set(String(key) for key in keys(value))
    required = Set(String(key) for key in expected)
    observed == required || error("$label has an unexpected field set")
    return value
end

function freecorr_require_string(value, label::AbstractString)
    value isa AbstractString && !isempty(value) ||
        error("$label must be a nonempty string")
    return String(value)
end

function freecorr_require_sha256(value, label::AbstractString)
    text = freecorr_require_string(value, label)
    occursin(r"^[0-9a-f]{64}$", text) ||
        error("$label must be a lowercase SHA-256 digest")
    return text
end

function freecorr_require_int(value, label::AbstractString)
    value isa Integer && !(value isa Bool) ||
        error("$label must be an integer")
    return Int(value)
end

function freecorr_require_finite_real(value, label::AbstractString)
    value isa Real && !(value isa Bool) ||
        error("$label must be a real number")
    converted = Float64(value)
    isfinite(converted) || error("$label must be finite")
    return converted
end

function freecorr_require_bool(value, label::AbstractString)
    value isa Bool || error("$label must be Bool")
    return value
end

freecorr_json_missing(value) = value === nothing || ismissing(value)

function freecorr_verify_content_hash(value; label::AbstractString)
    native = freecorr_json_native(value)
    haskey(native, "content_hash") || error("$label lacks a content hash")
    record = freecorr_exact_keys(
        native["content_hash"],
        ("algorithm", "value", "covers", "canonical_format"),
        "$label content hash",
    )
    record["algorithm"] == "sha256" ||
        error("$label content hash algorithm is not SHA-256")
    record["covers"] == "artifact_without_content_hash" ||
        error("$label content hash has the wrong coverage")
    record["canonical_format"] == String(FREECORR_CANONICAL_FORMAT) ||
        error("$label canonical format is not the frozen v1 format")
    stored = freecorr_require_sha256(
        record["value"],
        "$label content hash",
    )
    delete!(native, "content_hash")
    stored == freecorr_canonical_sha256(native) ||
        error("$label content hash does not match its contents")
    return stored
end

function freecorr_encode_json_bytes(value)
    native = freecorr_json_native(value)
    io = IOBuffer()
    write_json(io, native)
    println(io)
    return take!(io)
end

function freecorr_json_skip_whitespace(bytes, index::Int)
    while index <= length(bytes) &&
            bytes[index] in (UInt8(' '), UInt8('\t'), UInt8('\r'), UInt8('\n'))
        index += 1
    end
    return index
end

function freecorr_json_scan_string(bytes, index::Int, label::AbstractString)
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
            catch error
                throw(ErrorException(
                    "$label contains an invalid JSON string: " *
                    portable_error_message(error),
                ))
            end
            return decoded, index + 1
        elseif byte == UInt8('\\')
            index += 1
            index <= length(bytes) ||
                error("$label contains an unterminated JSON escape")
            if bytes[index] == UInt8('u')
                index + 4 <= length(bytes) ||
                    error("$label contains a truncated JSON Unicode escape")
                index += 5
            else
                index += 1
            end
        else
            byte >= 0x20 || error(
                "$label contains an unescaped control byte in a JSON string",
            )
            index += 1
        end
    end
    error("$label contains an unterminated JSON string")
end

function freecorr_json_scan_value(
        bytes,
        index::Int,
        label::AbstractString,
        depth::Int)
    depth <= 256 || error("$label exceeds the JSON nesting limit")
    index = freecorr_json_skip_whitespace(bytes, index)
    index <= length(bytes) || error("$label contains truncated JSON")
    byte = bytes[index]
    if byte == UInt8('{')
        seen_keys = Set{String}()
        index = freecorr_json_skip_whitespace(bytes, index + 1)
        index <= length(bytes) || error("$label contains an unterminated object")
        bytes[index] == UInt8('}') && return index + 1
        while true
            key, index = freecorr_json_scan_string(bytes, index, label)
            key in seen_keys && error(
                "$label contains a duplicate JSON object key: $(repr(key))",
            )
            push!(seen_keys, key)
            index = freecorr_json_skip_whitespace(bytes, index)
            index <= length(bytes) && bytes[index] == UInt8(':') ||
                error("$label contains an object key without a colon")
            index = freecorr_json_scan_value(bytes, index + 1, label, depth + 1)
            index = freecorr_json_skip_whitespace(bytes, index)
            index <= length(bytes) ||
                error("$label contains an unterminated object")
            bytes[index] == UInt8('}') && return index + 1
            bytes[index] == UInt8(',') ||
                error("$label contains malformed object separators")
            index = freecorr_json_skip_whitespace(bytes, index + 1)
        end
    elseif byte == UInt8('[')
        index = freecorr_json_skip_whitespace(bytes, index + 1)
        index <= length(bytes) || error("$label contains an unterminated array")
        bytes[index] == UInt8(']') && return index + 1
        while true
            index = freecorr_json_scan_value(bytes, index, label, depth + 1)
            index = freecorr_json_skip_whitespace(bytes, index)
            index <= length(bytes) ||
                error("$label contains an unterminated array")
            bytes[index] == UInt8(']') && return index + 1
            bytes[index] == UInt8(',') ||
                error("$label contains malformed array separators")
            index = freecorr_json_skip_whitespace(bytes, index + 1)
        end
    elseif byte == UInt8('"')
        _, index = freecorr_json_scan_string(bytes, index, label)
        return index
    end

    first_index = index
    while index <= length(bytes) && !(bytes[index] in (
            UInt8(' '), UInt8('\t'), UInt8('\r'), UInt8('\n'), UInt8(','),
            UInt8(']'), UInt8('}'),
        ))
        index += 1
    end
    index > first_index || error("$label contains an empty JSON value")
    return index
end

function freecorr_reject_duplicate_json_keys(bytes, label::AbstractString)
    index = freecorr_json_scan_value(bytes, 1, label, 0)
    index = freecorr_json_skip_whitespace(bytes, index)
    index == length(bytes) + 1 ||
        error("$label contains trailing data after its JSON value")
    return true
end

function freecorr_read_json_once(path::AbstractString, label::AbstractString)
    isfile(path) && !islink(path) || error("$label is not a regular file")
    bytes = read(path)
    nbytes = length(bytes)
    file_sha256 = bytes2hex(sha256(bytes))
    freecorr_reject_duplicate_json_keys(bytes, label)
    parsed = try
        JSON3.read(String(copy(bytes)))
    catch error
        throw(ErrorException(
            "$label is not valid JSON: $(portable_error_message(error))",
        ))
    end
    return (; bytes, nbytes, file_sha256, parsed)
end

function freecorr_file_snapshot_bytes(
        path::AbstractString,
        recorded_path::AbstractString)
    freecorr_path_within(path, FREECORR_RUNNER_ROOT) || error(
        "snapshot source escapes the workspace: $recorded_path",
    )
    freecorr_reject_link_components(path, FREECORR_RUNNER_ROOT)
    policy = freecorr_windows_reparse_policy(path)
    policy.permitted || error(
        "snapshot source has a forbidden Windows reparse tag: $recorded_path",
    )
    isfile(path) && !islink(path) ||
        error("required snapshot source is unavailable: $recorded_path")
    bytes = read(path)
    snapshot = (;
        path = String(recorded_path),
        bytes = length(bytes),
        sha256 = bytes2hex(sha256(bytes)),
    )
    return (; snapshot, bytes)
end

function freecorr_file_snapshot(
        path::AbstractString,
        recorded_path::AbstractString)
    return freecorr_file_snapshot_bytes(path, recorded_path).snapshot
end

function freecorr_path_within(path::AbstractString, boundary::AbstractString)
    relative = try
        relpath(normpath(path), normpath(boundary))
    catch
        return false
    end
    separator = string(Base.Filesystem.path_separator)
    return relative == "." || !(
        relative == ".." ||
        startswith(relative, string("..", separator)) ||
        startswith(relative, "../") ||
        startswith(relative, "..\\")
    )
end

function freecorr_windows_attribute_result_occupied(
        attributes::UInt32,
        last_error::UInt32,
        path::AbstractString)
    attributes != typemax(UInt32) && return true
    last_error in (UInt32(2), UInt32(3)) && return false
    error(
        "could not determine whether archive path is occupied " *
        "(Windows error code $last_error): $path",
    )
end

function freecorr_windows_path_occupied(path::AbstractString)
    query_path = freecorr_windows_extended_path(path)
    attributes = ccall(
        (:GetFileAttributesW, "kernel32"),
        UInt32,
        (Cwstring,),
        query_path,
    )
    last_error = attributes == typemax(UInt32) ? ccall(
        (:GetLastError, "kernel32"),
        UInt32,
        (),
    ) : UInt32(0)
    return freecorr_windows_attribute_result_occupied(
        attributes,
        last_error,
        path,
    )
end

function freecorr_path_occupied(path::AbstractString)
    ispath(path) && return true
    islink(path) && return true
    Sys.iswindows() && return freecorr_windows_path_occupied(path)
    metadata = lstat(path)
    ispath(metadata) && return true
    if hasproperty(metadata, :ioerrno)
        metadata.ioerrno in (Base.UV_ENOENT, Base.UV_ENOTDIR) && return false
        error("could not determine whether archive path is occupied: $path")
    end
    return false
end

function freecorr_windows_reparse_point(path::AbstractString)
    policy = freecorr_windows_reparse_policy(path)
    return policy.reparse_present && !policy.permitted
end

function freecorr_windows_extended_path(path::AbstractString)
    Sys.iswindows() || return String(path)
    absolute = abspath(path)
    startswith(absolute, "\\\\?\\") && return absolute
    if startswith(absolute, "\\\\")
        return "\\\\?\\UNC\\" * absolute[3:end]
    end
    return "\\\\?\\" * absolute
end

function freecorr_windows_fsutil_reparse_tag(path::AbstractString)
    system_root = get(ENV, "SystemRoot", "")
    isempty(system_root) && error(
        "SystemRoot is unavailable for Cloud Files reparse inspection",
    )
    fsutil = joinpath(system_root, "System32", "fsutil.exe")
    isfile(fsutil) || error(
        "the Windows fsutil reparse inspector is unavailable",
    )
    raw_output = read(pipeline(
        ignorestatus(Cmd([
            fsutil,
            "reparsepoint",
            "query",
            abspath(path),
        ])),
        stderr = devnull,
    ))
    text = String(UInt8[
        byte for byte in raw_output
        if byte in (UInt8('\t'), UInt8('\r'), UInt8('\n')) ||
            UInt8(0x20) <= byte <= UInt8(0x7e)
    ])
    matched = match(r"0x[0-9A-Fa-f]{8}", text)
    matched === nothing && error(
        "fsutil did not return a machine-readable reparse tag",
    )
    return parse(UInt32, matched.match[3:end]; base = 16)
end

function freecorr_windows_reparse_tag(path::AbstractString)
    Sys.iswindows() || return missing
    freecorr_path_occupied(path) || return missing
    query_path = String(path)
    while (endswith(query_path, '\\') || endswith(query_path, '/')) &&
            dirname(query_path) != query_path
        query_path = chop(query_path)
    end
    query_path = freecorr_windows_extended_path(query_path)
    attribute_data = zeros(UInt8, 36)
    attributes_ok = GC.@preserve attribute_data ccall(
        (:GetFileAttributesExW, "kernel32"),
        Int32,
        (Cwstring, Int32, Ptr{Cvoid}),
        query_path,
        Int32(0),
        pointer(attribute_data),
    )
    attributes_ok != 0 || error(
        "could not inspect Windows file attributes: $path",
    )
    attributes = GC.@preserve attribute_data unsafe_load(
        Ptr{UInt32}(pointer(attribute_data)),
    )
    find_data = zeros(UInt8, 592)
    handle = GC.@preserve find_data ccall(
        (:FindFirstFileW, "kernel32"),
        Ptr{Cvoid},
        (Cwstring, Ptr{Cvoid}),
        query_path,
        pointer(find_data),
    )
    handle == Ptr{Cvoid}(typemax(UInt)) && error(
        "could not inspect Windows directory entry: $path",
    )
    try
        find_attributes = GC.@preserve find_data unsafe_load(
            Ptr{UInt32}(pointer(find_data)),
        )
        reparse_present = (
            (attributes | find_attributes) & UInt32(0x00000400)
        ) != 0
        if !reparse_present
            cloud_attribute_hint = (
                (attributes | find_attributes) &
                UInt32(0x00040000 | 0x00100000 | 0x00400000)
            ) != 0
            same_workspace_root = lowercase(normpath(abspath(path))) ==
                lowercase(normpath(abspath(FREECORR_RUNNER_ROOT)))
            cloud_attribute_hint && same_workspace_root || return missing
            return freecorr_windows_fsutil_reparse_tag(path)
        end
        tag = GC.@preserve find_data unsafe_load(
            Ptr{UInt32}(pointer(find_data) + 36),
        )
        tag != UInt32(0) || error(
            "Windows reparse entry has no observable reparse tag: $path",
        )
        return tag
    finally
        ccall((:FindClose, "kernel32"), Int32, (Ptr{Cvoid},), handle)
    end
end

function freecorr_windows_reparse_policy(path::AbstractString)
    if !Sys.iswindows()
        return (;
            platform = :non_windows,
            reparse_present = false,
            reparse_tag = missing,
            classification = :not_applicable,
            permitted = true,
        )
    end
    freecorr_path_occupied(path) || return (;
        platform = :windows,
        reparse_present = false,
        reparse_tag = missing,
        classification = :path_absent,
        permitted = true,
    )
    tag = freecorr_windows_reparse_tag(path)
    ismissing(tag) && return (;
        platform = :windows,
        reparse_present = false,
        reparse_tag = missing,
        classification = :ordinary_filesystem_entry,
        permitted = true,
    )
    tag_text = "0x" * lowercase(string(tag; base = 16, pad = 8))
    cloud_family = (tag & UInt32(0xffff0fff)) == UInt32(0x9000001a)
    name_surrogate = (tag & UInt32(0x20000000)) != 0
    classification = cloud_family ? :windows_cloud_files_family :
        name_surrogate ? :windows_name_surrogate :
        :unknown_windows_reparse_tag
    return (;
        platform = :windows,
        reparse_present = true,
        reparse_tag = tag_text,
        classification,
        permitted = cloud_family,
    )
end

function freecorr_reject_link_components(
        path::AbstractString,
        boundary::AbstractString)
    target = normpath(path)
    root = normpath(boundary)
    freecorr_path_within(target, root) ||
        error("archive path escapes its declared boundary")
    current = target
    while freecorr_path_within(current, root)
        if freecorr_path_occupied(current)
            islink(current) && error(
                "symbolic links are forbidden in the archive path: $current",
            )
            freecorr_windows_reparse_point(current) && error(
                "Windows reparse points/junctions are forbidden: $current",
            )
        end
        current == root && break
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    return true
end

function freecorr_directory_identity(path::AbstractString)
    isdir(path) && !islink(path) ||
        error("archive parent is not a regular directory: $path")
    freecorr_windows_reparse_point(path) &&
        error("archive parent is a Windows reparse point")
    metadata = lstat(path)
    return (;
        realpath = realpath(path),
        device = hasproperty(metadata, :device) ? metadata.device : missing,
        inode = hasproperty(metadata, :inode) ? metadata.inode : missing,
    )
end

function freecorr_ensure_directory(
        path::AbstractString,
        boundary::AbstractString)
    freecorr_reject_link_components(path, boundary)
    mkpath(path)
    freecorr_reject_link_components(path, boundary)
    isdir(path) && !islink(path) ||
        error("archive directory could not be created safely")
    return freecorr_directory_identity(path)
end

function freecorr_record_path(path::AbstractString)
    relative = relpath(normpath(path), FREECORR_RUNNER_ROOT)
    return freecorr_path_within(path, FREECORR_RUNNER_ROOT) ? relative :
        normpath(path)
end

function freecorr_filesystem_policy_snapshot(path::AbstractString)
    policy = freecorr_windows_reparse_policy(path)
    return (;
        path = freecorr_record_path(path),
        platform = policy.platform,
        reparse_present = policy.reparse_present,
        reparse_tag = policy.reparse_tag,
        classification = policy.classification,
        permitted = policy.permitted,
    )
end

function freecorr_safe_filesystem_policy_snapshot(path::AbstractString)
    try
        return merge(
            freecorr_filesystem_policy_snapshot(path),
            (;
                inspection_passed = true,
                inspection_error = missing,
            ),
        )
    catch error
        return (;
            path = freecorr_record_path(path),
            platform = Sys.iswindows() ? :windows : :non_windows,
            reparse_present = missing,
            reparse_tag = missing,
            classification = :inspection_failed,
            permitted = false,
            inspection_passed = false,
            inspection_error = portable_error_message(error),
        )
    end
end

function freecorr_validate_filesystem_policy_snapshot(value, label::AbstractString)
    native = freecorr_json_native(value)
    freecorr_exact_keys(native, (
        "path", "platform", "reparse_present", "reparse_tag",
        "classification", "permitted",
    ), label)
    freecorr_require_string(native["path"], "$label path")
    platform = freecorr_require_string(native["platform"], "$label platform")
    present = freecorr_require_bool(
        native["reparse_present"],
        "$label reparse-present flag",
    )
    permitted = freecorr_require_bool(
        native["permitted"],
        "$label permitted flag",
    )
    classification = freecorr_require_string(
        native["classification"],
        "$label classification",
    )
    permitted || error("$label records a forbidden filesystem entry")
    if platform == "windows" && present
        occursin(r"^0x[0-9a-f]{8}$", native["reparse_tag"]) || error(
            "$label Windows reparse tag is malformed",
        )
        classification == "windows_cloud_files_family" || error(
            "$label permits a non-cloud Windows reparse tag",
        )
    else
        freecorr_json_missing(native["reparse_tag"]) || error(
            "$label unexpectedly records a reparse tag",
        )
    end
    return true
end

function freecorr_self_consistency_boundary()
    return (;
        self_consistency_only = true,
        authenticity_attested = false,
        external_anchor_present = false,
        timestamp_attested = false,
    )
end

function freecorr_validate_self_consistency_boundary(value, label::AbstractString)
    expected = freecorr_json_native(freecorr_self_consistency_boundary())
    for (key, expected_value) in expected
        haskey(value, key) || error("$label lacks threat-boundary field $key")
        value[key] === expected_value || error(
            "$label overstates content-hash authenticity or timestamp evidence",
        )
    end
    return true
end

function freecorr_manifest_path()
    versioned = joinpath(
        FREECORR_RUNNER_ROOT,
        "Manifest-v$(VERSION.major).$(VERSION.minor).toml",
    )
    result = isfile(versioned) ? versioned :
        joinpath(FREECORR_RUNNER_ROOT, "Manifest.toml")
    isfile(result) || error(
        "the Julia-version-appropriate Manifest is unavailable",
    )
    return normpath(result)
end

function freecorr_source_receipt(plan)
    source_paths = Tuple(String(path)
        for path in plan.unit_result_contract.source_paths)
    length(unique(source_paths)) == length(source_paths) ||
        error("core provenance source roster contains duplicates")
    core_sources = Tuple(freecorr_file_snapshot(
        joinpath(FREECORR_RUNNER_ROOT, split(path, '/')...),
        path,
    ) for path in source_paths)
    harness_sources = (
        freecorr_file_snapshot(
            FREECORR_RUNNER_PATH,
            "scripts/run_mgmfrm_free_latent_correlation_2d_study_unit.jl",
        ),
        freecorr_file_snapshot(
            FREECORR_LOCAL_JSON_PATH,
            "scripts/local_json.jl",
        ),
    )
    material = (;
        schema = FREECORR_SOURCE_RECEIPT_SCHEMA,
        scope = :current_diagnostic_snapshot_not_loaded_code_attestation,
        scientific_execution_receipt = false,
        loaded_code_attested = false,
        source_bytes_read_once_per_file = true,
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        core_source_roster = source_paths,
        core_sources,
        harness_sources,
        aggregate_sha256 = freecorr_canonical_sha256((;
            plan_id = plan.plan_id,
            plan_fingerprint = plan.plan_fingerprint,
            core_sources,
            harness_sources,
        )),
    )
    return freecorr_with_content_hash(material)
end

function freecorr_project_resolve_hash(project_bytes)
    project = Pkg.Types.read_project(IOBuffer(project_bytes))
    if !hasproperty(project, :workspace)
        io = IOBuffer()
        for (name, uuid) in sort!(collect(project.deps); by = first)
            println(io, name, "=", uuid)
        end
        for (name, compat) in sort!(collect(project.compat); by = first)
            println(io, name, "=", compat.val)
        end
        return bytes2hex(sha1(take!(io)))
    end
    workspace_projects = hasproperty(project, :workspace) ?
        get(project.workspace, "projects", nothing) : nothing
    (workspace_projects === nothing || isempty(workspace_projects)) || error(
        "workspace projects are unsupported by this frozen environment check",
    )
    deps = Dict{String,Any}(project.deps)
    if project.name !== nothing && project.uuid !== nothing
        deps[project.name] = project.uuid
    end
    weakdeps = Dict{String,Any}(project.weakdeps)
    all_names = union(keys(deps), keys(weakdeps))
    compats = Dict(
        name => haskey(project.compat, name) ?
            project.compat[name].val : Pkg.Types.VersionSpec()
        for name in all_names
    )
    io = IOBuffer()
    for (name, uuid) in sort!(collect(deps); by = first)
        println(io, name, "=", uuid)
    end
    println(io)
    for (name, uuid) in sort!(collect(weakdeps); by = first)
        println(io, name, "=", uuid)
    end
    println(io)
    for (name, compat) in sort!(collect(compats); by = first)
        println(io, name, "=", compat)
    end
    return bytes2hex(sha1(take!(io)))
end

function freecorr_manifest_header(manifest_bytes, project_bytes)
    raw = try
        TOML.parse(String(Vector{UInt8}(manifest_bytes)))
    catch error
        throw(ErrorException(
            "selected Manifest is not valid TOML: " *
            portable_error_message(error),
        ))
    end
    all(haskey(raw, key) for key in
        ("julia_version", "manifest_format", "project_hash")) || error(
        "selected Manifest lacks a required v2 header field",
    )
    julia_version = freecorr_require_string(
        raw["julia_version"],
        "Manifest julia_version",
    )
    manifest_format = freecorr_require_string(
        raw["manifest_format"],
        "Manifest manifest_format",
    )
    project_hash = freecorr_require_string(
        raw["project_hash"],
        "Manifest project_hash",
    )
    manifest_julia_version = VersionNumber(julia_version)
    manifest_julia_version.major == VERSION.major &&
        manifest_julia_version.minor == VERSION.minor || error(
        "selected Manifest julia_version does not match the runtime major/minor",
    )
    VersionNumber(manifest_format) == v"2.0.0" || error(
        "selected Manifest is not frozen manifest format 2.0",
    )
    occursin(r"^[0-9a-f]{40}$", project_hash) || error(
        "selected Manifest project_hash is not a lowercase SHA-1 digest",
    )
    computed_project_hash = freecorr_project_resolve_hash(project_bytes)
    project_hash == computed_project_hash || error(
        "selected Manifest project_hash does not match Project.toml",
    )
    return (;
        julia_version,
        manifest_format,
        project_hash,
        project_resolve_hash_verified = true,
        manifest_patch_matches_runtime = manifest_julia_version == VERSION,
    )
end

function freecorr_runtime_snapshot()
    return (;
        julia_version = string(VERSION),
        n_threads = Threads.nthreads(),
        os = string(Sys.KERNEL),
        arch = string(Sys.ARCH),
        word_size = Sys.WORD_SIZE,
        cpu_threads = Sys.CPU_THREADS,
        blas_vendor = string(LinearAlgebra.BLAS.vendor()),
        blas_threads = LinearAlgebra.BLAS.get_num_threads(),
    )
end

function freecorr_thread_environment_snapshot()
    return (;
        julia_num_threads = get(ENV, "JULIA_NUM_THREADS", missing),
        openblas_num_threads = get(ENV, "OPENBLAS_NUM_THREADS", missing),
    )
end

function freecorr_environment_stable_material(
        runtime,
        active_project,
        environment_files,
        manifest_header,
        environment_variables,
        workspace_filesystem)
    return (;
        runtime,
        active_project,
        environment_files,
        manifest_header,
        environment_variables,
        workspace_filesystem,
    )
end

function freecorr_environment_receipt(plan)
    project_path = normpath(joinpath(FREECORR_RUNNER_ROOT, "Project.toml"))
    manifest_path = freecorr_manifest_path()
    project_file = freecorr_file_snapshot_bytes(
        project_path,
        basename(project_path),
    )
    manifest_file = freecorr_file_snapshot_bytes(
        manifest_path,
        basename(manifest_path),
    )
    environment_files = (;
        project = project_file.snapshot,
        manifest = manifest_file.snapshot,
    )
    runtime = freecorr_runtime_snapshot()
    active_project = Base.active_project() === nothing ? missing :
        freecorr_record_path(Base.active_project())
    manifest_header = freecorr_manifest_header(
        manifest_file.bytes,
        project_file.bytes,
    )
    environment_variables = freecorr_thread_environment_snapshot()
    workspace_filesystem = freecorr_filesystem_policy_snapshot(
        FREECORR_RUNNER_ROOT,
    )
    material = (;
        schema = FREECORR_ENVIRONMENT_RECEIPT_SCHEMA,
        scope = :current_diagnostic_snapshot_not_scientific_execution_receipt,
        scientific_execution_receipt = false,
        environment_bytes_read_once_per_file = true,
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        runtime,
        active_project,
        environment_files,
        manifest_header,
        workspace_filesystem,
        stable_identity_sha256 = freecorr_canonical_sha256(
            freecorr_environment_stable_material(
                runtime,
                active_project,
                environment_files,
                manifest_header,
                environment_variables,
                workspace_filesystem,
            ),
        ),
        resource_snapshot = (;
            free_memory_bytes = Int(Sys.free_memory()),
            total_memory_bytes = Int(Sys.total_memory()),
        ),
        environment_variables,
    )
    return freecorr_with_content_hash(material)
end

function freecorr_validate_snapshot_rows(rows, paths, label::AbstractString)
    rows isa AbstractVector && length(rows) == length(paths) ||
        error("$label has the wrong length")
    for (row, expected_path) in zip(rows, paths)
        freecorr_exact_keys(row, ("path", "bytes", "sha256"), "$label row")
        row["path"] == expected_path || error("$label path roster was modified")
        freecorr_require_int(row["bytes"], "$label byte count") >= 0 ||
            error("$label byte count must be nonnegative")
        freecorr_require_sha256(row["sha256"], "$label SHA-256")
    end
    return true
end

function freecorr_validate_source_receipt(value, plan; require_current::Bool)
    native = freecorr_json_native(value)
    freecorr_exact_keys(native, (
        "schema", "scope", "scientific_execution_receipt",
        "loaded_code_attested", "source_bytes_read_once_per_file",
        "plan_id", "plan_fingerprint", "core_source_roster",
        "core_sources", "harness_sources", "aggregate_sha256",
        "content_hash",
    ), "source snapshot")
    content_sha256 = freecorr_verify_content_hash(
        native;
        label = "source snapshot",
    )
    native["schema"] == FREECORR_SOURCE_RECEIPT_SCHEMA &&
        native["scope"] ==
            "current_diagnostic_snapshot_not_loaded_code_attestation" ||
        error("source snapshot has the wrong scope")
    native["scientific_execution_receipt"] === false &&
        native["loaded_code_attested"] === false &&
        native["source_bytes_read_once_per_file"] === true ||
        error("source snapshot overstates its attestation scope")
    native["plan_id"] == plan.plan_id &&
        native["plan_fingerprint"] == plan.plan_fingerprint ||
        error("source snapshot has the wrong plan identity")
    expected_roster = [String(path)
        for path in plan.unit_result_contract.source_paths]
    native["core_source_roster"] == expected_roster ||
        error("source snapshot does not preserve the core source roster")
    freecorr_validate_snapshot_rows(
        native["core_sources"],
        expected_roster,
        "core source snapshot",
    )
    harness_paths = [
        "scripts/run_mgmfrm_free_latent_correlation_2d_study_unit.jl",
        "scripts/local_json.jl",
    ]
    freecorr_validate_snapshot_rows(
        native["harness_sources"],
        harness_paths,
        "harness source snapshot",
    )
    aggregate = freecorr_require_sha256(
        native["aggregate_sha256"],
        "source snapshot aggregate",
    )
    aggregate == freecorr_canonical_sha256((;
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        core_sources = native["core_sources"],
        harness_sources = native["harness_sources"],
    )) || error("source snapshot aggregate does not bind its file rows")
    current_matches = aggregate == freecorr_source_receipt(plan).aggregate_sha256
    require_current && !current_matches &&
        error("source snapshot differs from the current files")
    return (; content_sha256, aggregate_sha256 = aggregate, current_matches)
end

function freecorr_validate_environment_receipt(value, plan; require_current::Bool)
    native = freecorr_json_native(value)
    freecorr_exact_keys(native, (
        "schema", "scope", "scientific_execution_receipt",
        "environment_bytes_read_once_per_file", "plan_id",
        "plan_fingerprint", "runtime", "active_project",
        "environment_files", "manifest_header", "stable_identity_sha256",
        "resource_snapshot", "environment_variables", "workspace_filesystem",
        "content_hash",
    ), "environment snapshot")
    content_sha256 = freecorr_verify_content_hash(
        native;
        label = "environment snapshot",
    )
    native["schema"] == FREECORR_ENVIRONMENT_RECEIPT_SCHEMA &&
        native["scope"] ==
            "current_diagnostic_snapshot_not_scientific_execution_receipt" ||
        error("environment snapshot has the wrong scope")
    native["scientific_execution_receipt"] === false &&
        native["environment_bytes_read_once_per_file"] === true ||
        error("environment snapshot overstates its receipt scope")
    native["plan_id"] == plan.plan_id &&
        native["plan_fingerprint"] == plan.plan_fingerprint ||
        error("environment snapshot has the wrong plan identity")
    runtime = freecorr_exact_keys(native["runtime"], (
        "julia_version", "n_threads", "os", "arch", "word_size",
        "cpu_threads", "blas_vendor", "blas_threads",
    ), "environment runtime")
    VersionNumber(freecorr_require_string(
        runtime["julia_version"],
        "Julia version",
    ))
    freecorr_require_int(runtime["n_threads"], "Julia threads") >= 1 ||
        error("Julia thread count must be positive")
    freecorr_require_string(runtime["os"], "runtime OS")
    freecorr_require_string(runtime["arch"], "runtime architecture")
    freecorr_require_int(runtime["word_size"], "word size") in (32, 64) ||
        error("word size must be 32 or 64")
    freecorr_require_int(runtime["cpu_threads"], "CPU threads") >= 1 ||
        error("CPU thread count must be positive")
    freecorr_require_string(runtime["blas_vendor"], "BLAS vendor")
    freecorr_require_int(runtime["blas_threads"], "BLAS threads") >= 1 ||
        error("BLAS thread count must be positive")
    native["active_project"] == "Project.toml" || error(
        "runner must use the workspace Project.toml",
    )
    files = freecorr_exact_keys(
        native["environment_files"],
        ("project", "manifest"),
        "environment files",
    )
    manifest_name = basename(freecorr_manifest_path())
    freecorr_validate_snapshot_rows(
        [files["project"], files["manifest"]],
        ["Project.toml", manifest_name],
        "environment file snapshot",
    )
    manifest_header = freecorr_exact_keys(native["manifest_header"], (
        "julia_version", "manifest_format", "project_hash",
        "project_resolve_hash_verified", "manifest_patch_matches_runtime",
    ), "Manifest header")
    manifest_julia_version = VersionNumber(freecorr_require_string(
        manifest_header["julia_version"],
        "Manifest julia_version",
    ))
    VersionNumber(freecorr_require_string(
        manifest_header["manifest_format"],
        "Manifest manifest_format",
    )) == v"2.0.0" || error("Manifest format is not 2.0")
    occursin(
        r"^[0-9a-f]{40}$",
        freecorr_require_string(
            manifest_header["project_hash"],
            "Manifest project_hash",
        ),
    ) || error("Manifest project_hash is not a lowercase SHA-1 digest")
    manifest_header["project_resolve_hash_verified"] === true || error(
        "Manifest header does not attest its Project.toml cross-check",
    )
    runtime_version = VersionNumber(runtime["julia_version"])
    manifest_julia_version.major == runtime_version.major &&
        manifest_julia_version.minor == runtime_version.minor || error(
        "Manifest julia_version differs from the runtime major/minor",
    )
    manifest_header["manifest_patch_matches_runtime"] ===
        (manifest_julia_version == VersionNumber(runtime["julia_version"])) ||
        error("Manifest/runtime patch-match flag is inconsistent")
    variables = freecorr_exact_keys(native["environment_variables"], (
        "julia_num_threads", "openblas_num_threads",
    ), "environment variables")
    all(value -> freecorr_json_missing(value) || value isa AbstractString,
        values(variables)) || error("environment variable snapshot is invalid")
    workspace_filesystem = native["workspace_filesystem"]
    freecorr_validate_filesystem_policy_snapshot(
        workspace_filesystem,
        "workspace filesystem policy snapshot",
    )
    stable = freecorr_require_sha256(
        native["stable_identity_sha256"],
        "environment stable identity",
    )
    stable == freecorr_canonical_sha256(
        freecorr_environment_stable_material(
            runtime,
            native["active_project"],
            files,
            manifest_header,
            variables,
            workspace_filesystem,
        ),
    ) || error("environment stable identity is inconsistent")
    resources = freecorr_exact_keys(
        native["resource_snapshot"],
        ("free_memory_bytes", "total_memory_bytes"),
        "resource snapshot",
    )
    free_memory = freecorr_require_int(
        resources["free_memory_bytes"],
        "free memory",
    )
    total_memory = freecorr_require_int(
        resources["total_memory_bytes"],
        "total memory",
    )
    0 <= free_memory <= total_memory || error("memory snapshot is inconsistent")
    current_matches = stable ==
        freecorr_environment_receipt(plan).stable_identity_sha256
    require_current && !current_matches &&
        error("environment snapshot differs from the current environment")
    return (; content_sha256, stable_identity_sha256 = stable, current_matches)
end

function freecorr_execution_root(attempt_root::AbstractString, plan)
    return joinpath(
        normpath(attempt_root),
        plan.plan_id,
        plan.plan_fingerprint,
    )
end

function freecorr_unit_root(attempt_root::AbstractString, plan, unit)
    return joinpath(
        freecorr_execution_root(attempt_root, plan),
        "units",
        unit.unit_id,
    )
end


function freecorr_attempt_dir(attempt_root::AbstractString, plan, unit)
    return joinpath(
        freecorr_unit_root(attempt_root, plan, unit),
        FREECORR_ATTEMPT_DIRECTORY,
    )
end

function freecorr_dry_run_dir(attempt_root::AbstractString, plan, unit)
    return joinpath(
        freecorr_execution_root(attempt_root, plan),
        "dry_runs",
        unit.unit_id,
    )
end

function freecorr_resource_probe_dir(attempt_root::AbstractString, plan, unit)
    return joinpath(
        freecorr_execution_root(attempt_root, plan),
        FREECORR_RESOURCE_PROBE_DIRECTORY,
        unit.unit_id,
    )
end

function freecorr_resource_probe_path(
        attempt_root::AbstractString,
        plan,
        unit)
    return joinpath(
        freecorr_resource_probe_dir(attempt_root, plan, unit),
        FREECORR_RESOURCE_PROBE_FILENAME,
    )
end

function freecorr_resource_probe_reservation_path(
        attempt_root::AbstractString,
        plan,
        unit)
    return joinpath(
        freecorr_resource_probe_dir(attempt_root, plan, unit),
        FREECORR_RESOURCE_PROBE_RESERVATION_FILENAME,
    )
end

function freecorr_resource_probe_failure_path(
        attempt_root::AbstractString,
        plan,
        unit)
    return joinpath(
        freecorr_resource_probe_dir(attempt_root, plan, unit),
        FREECORR_RESOURCE_PROBE_FAILURE_FILENAME,
    )
end

function freecorr_staging_dir(attempt_root::AbstractString, plan)
    return joinpath(
        freecorr_execution_root(attempt_root, plan),
        FREECORR_STAGING_DIRECTORY,
    )
end

function freecorr_parse_mode(value::AbstractString)
    normalized = replace(lowercase(String(value)), '_' => '-')
    normalized in (
        "status",
        "dry-run",
        "resource-probe",
        "validate",
        "execute-primary",
    ) ||
        error("unsupported --mode: $value")
    return Symbol(replace(normalized, '-' => '_'))
end

function freecorr_parse_args(args)
    mode = :status
    unit_id = nothing
    artifact = nothing
    attempt_root = FREECORR_DEFAULT_ATTEMPT_ROOT
    confirm_scientific_mcmc = false
    allow_test_root = false
    seen = Set{String}()

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg in ("--mode", "--unit-id", "--artifact", "--attempt-root")
            arg in seen && error("duplicate single-value option: $arg")
            push!(seen, arg)
            index < length(args) || error("$arg requires a value")
            value = args[index + 1]
            if arg == "--mode"
                mode = freecorr_parse_mode(value)
            elseif arg == "--unit-id"
                unit_id = String(value)
                isempty(unit_id) && error("--unit-id must not be empty")
            elseif arg == "--artifact"
                artifact = abspath(value)
            else
                attempt_root = abspath(value)
            end
            index += 2
        elseif arg == "--confirm-scientific-mcmc"
            arg in seen && error("duplicate flag: $arg")
            push!(seen, arg)
            confirm_scientific_mcmc = true
            index += 1
        elseif arg == "--allow-test-root"
            arg in seen && error("duplicate flag: $arg")
            push!(seen, arg)
            allow_test_root = true
            index += 1
        elseif arg in ("-h", "--help")
            return (; help = true)
        else
            error("unknown argument: $arg")
        end
    end

    unit_id === nothing && error("exactly one --unit-id is required")
    artifact !== nothing && mode !== :validate &&
        error("--artifact is available only in validate mode")
    confirm_scientific_mcmc && mode !== :execute_primary && error(
        "--confirm-scientific-mcmc is available only in execute-primary mode",
    )
    allow_test_root && get(ENV, FREECORR_TEST_ROOT_ENV, "") != "1" && error(
        "--allow-test-root requires $FREECORR_TEST_ROOT_ENV=1",
    )
    normalized_root = normpath(attempt_root)
    default_root = normpath(FREECORR_DEFAULT_ATTEMPT_ROOT)
    test_override = normalized_root != default_root
    if test_override
        allow_test_root || error(
            "nondefault --attempt-root requires the test-only override",
        )
        freecorr_path_within(normalized_root, tempdir()) || error(
            "test-only attempt root must remain below the system temp directory",
        )
    else
        freecorr_path_within(normalized_root, FREECORR_RUNNER_ROOT) || error(
            "production attempt root must remain inside the workspace",
        )
    end
    return (;
        help = false,
        mode,
        unit_id,
        artifact,
        attempt_root = normalized_root,
        confirm_scientific_mcmc,
        test_root_override = test_override,
    )
end

function freecorr_plan_and_unit(unit_id::AbstractString)
    plan = BayesianMGMFRM.Experimental.
        free_latent_correlation_2d_study_plan()
    plan.version == 2 && endswith(plan.schema, ".v2") || error(
        "pre-execution runner v1 requires the frozen v2 study plan",
    )
    matches = [unit for unit in plan.units if unit.unit_id == unit_id]
    length(matches) == 1 || error(
        "--unit-id must identify exactly one canonical v2 study unit",
    )
    return plan, only(matches)
end

function freecorr_preflight(plan, unit)
    return BayesianMGMFRM.Experimental.
        free_latent_correlation_2d_study_unit_preflight(
            plan,
            unit.unit_id,
        )
end

function freecorr_gate_status(
        protocol_execution_authorized::Bool,
        operational_execution_authorized::Bool,
        execution_authorized::Bool)
    execution_authorized === (
        protocol_execution_authorized && operational_execution_authorized
    ) || error(
        "preflight execution_authorized must equal protocol && operational",
    )
    if protocol_execution_authorized && operational_execution_authorized
        return :preexecution_dry_run_core_authorized_runner_blocked
    elseif protocol_execution_authorized
        return :preexecution_dry_run_protocol_authorized_operational_blocked
    elseif operational_execution_authorized
        return :preexecution_dry_run_protocol_blocked_operational_authorized
    end
    return :preexecution_dry_run_protocol_and_operational_blocked
end

function freecorr_utc_timestamp()
    return Dates.format(
        Dates.now(Dates.UTC),
        dateformat"yyyy-mm-ddTHH:MM:SS.sss",
    ) * "Z"
end

function freecorr_validate_utc_timestamp(value)
    text = freecorr_require_string(value, "dry-run timestamp")
    occursin(
        r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$",
        text,
    ) || error("dry-run timestamp is not canonical UTC")
    try
        DateTime(text[1:(end - 1)], dateformat"yyyy-mm-ddTHH:MM:SS.sss")
    catch error
        throw(ErrorException(
            "dry-run timestamp is not a valid UTC DateTime: " *
            portable_error_message(error),
        ))
    end
    return text
end

function freecorr_archive_contract()
    return (;
        runner_version = 1,
        scope = :preexecution_dry_run_only,
        scientific_attempt_creation_supported = false,
        scientific_attempt_interpretation_supported = false,
        scientific_state_disposition = FREECORR_UNSUPPORTED_SCIENTIFIC_STATE,
        execute_primary_available = false,
        batch_execution_supported = false,
        retry_supported = false,
        resume_supported = false,
        atomic_publish = :same_volume_hardlink_create_new,
        hardlink_fallback_allowed = false,
        overwrite_allowed = false,
        staging_directory = FREECORR_STAGING_DIRECTORY,
        staging_orphans_are_status_inputs = false,
        self_consistency_only = true,
        authenticity_attested = false,
        external_anchor_present = false,
        timestamp_attested = false,
        duplicate_json_object_keys_rejected_preparse = true,
        windows_cloud_files_reparse_family_allowed = true,
        windows_name_surrogate_reparse_allowed = false,
        unknown_windows_reparse_tag_allowed = false,
        windows_flush_file_buffers_requested = true,
        postpublish_validation_failure_target_disposition =
            :left_in_place_for_forensic_review,
        postpublish_failure_requires_operator_review = true,
        remaining_toctou_risk =
            :path_and_leaf_races_without_handle_relative_io,
    )
end

function freecorr_resource_probe_contract()
    return (;
        runner_version = 1,
        scope = :mcmc_free_initial_gradient_resource_probe_only,
        unit_selection = :first_frozen_feasibility_unit,
        repetitions = FREECORR_RESOURCE_PROBE_REPETITIONS,
        operation = :initial_logdensity_and_gradient,
        resource_probe_attempt = 1,
        target_filename = FREECORR_RESOURCE_PROBE_FILENAME,
        reservation_filename = FREECORR_RESOURCE_PROBE_RESERVATION_FILENAME,
        terminal_failure_filename = FREECORR_RESOURCE_PROBE_FAILURE_FILENAME,
        reservation_required_before_measurement = true,
        reservation_permanently_consumes_attempt = true,
        interrupted_reservation_requires_operator_review = true,
        pre_reservation_runtime_initialization = :one_by_one_blas_gemm,
        runtime_initialization_result_checked = true,
        runtime_initialization_mcmc = false,
        reservation_binds_source_aggregate = true,
        reservation_binds_stable_environment_identity = true,
        terminal_cross_binding_required = true,
        scientific_attempt_tree_separate = true,
        scientific_attempt_creation_supported = false,
        execute_primary_available = false,
        mcmc_allowed = false,
        recovery_evidence_allowed = false,
        threshold_failure_receipt_persisted = true,
        threshold_failure_exit_code = 5,
        retry_supported = false,
        overwrite_allowed = false,
        atomic_publish = :same_volume_hardlink_create_new,
        hardlink_fallback_allowed = false,
        staging_directory = FREECORR_STAGING_DIRECTORY,
        serialized_package_provenance_digests_recomputed = true,
        serialized_package_artifact_hash_recomputed = true,
        serialized_package_artifact_hash_validation =
            :fully_recomputed_after_schema_specific_type_restoration,
        power_loss_durability_attested = false,
        remaining_durability_risk =
            :nonwindows_file_and_parent_directory_fsync_not_requested,
        self_consistency_only = true,
        authenticity_attested = false,
        external_anchor_present = false,
        timestamp_attested = false,
    )
end

freecorr_resource_probe_exit_code(profile_thresholds_passed::Bool) =
    profile_thresholds_passed ? 0 : 5

function freecorr_initialize_resource_probe_runtime()
    left = ones(Float64, 1, 1)
    right = ones(Float64, 1, 1)
    result = zeros(Float64, 1, 1)
    LinearAlgebra.BLAS.gemm!(
        'N',
        'N',
        1.0,
        left,
        right,
        0.0,
        result,
    )
    result[1] == 1.0 && isfinite(result[1]) ||
        error("resource-probe BLAS runtime initialization failed")
    return (;
        operation = :one_by_one_blas_gemm,
        result_checked = true,
        blas_threads = LinearAlgebra.BLAS.get_num_threads(),
        mcmc_executed = false,
    )
end

function freecorr_fixed_resource_probe_unit(plan, unit)
    expected = first(plan.units)
    expected.phase === :feasibility || error(
        "the frozen first resource-probe unit is not a feasibility unit",
    )
    unit.unit_id == expected.unit_id &&
        freecorr_canonical_sha256(unit) ==
            freecorr_canonical_sha256(expected) || error(
        "resource-probe mode is fixed to the first feasibility unit: " *
        expected.unit_id,
    )
    return expected
end

function freecorr_measure_resource_probe(plan, unit)
    fixed_unit = freecorr_fixed_resource_probe_unit(plan, unit)
    probe = BayesianMGMFRM.Experimental.
        free_latent_correlation_2d_study_resource_probe(
            plan,
            fixed_unit.unit_id;
            execute_measurement = true,
            repetitions = FREECORR_RESOURCE_PROBE_REPETITIONS,
        )
    getfield(
        BayesianMGMFRM,
        :_validate_free_correlation_study_resource_probe,
    )(probe, plan, fixed_unit.unit_id)
    return probe
end

function freecorr_resource_probe_reservation(plan, unit)
    fixed_unit = freecorr_fixed_resource_probe_unit(plan, unit)
    freecorr_initialize_resource_probe_runtime()
    source = freecorr_source_receipt(plan)
    environment = freecorr_environment_receipt(plan)
    return freecorr_with_content_hash((;
        schema = FREECORR_RESOURCE_PROBE_RESERVATION_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_resource_probe_reservation,
        status = :resource_probe_attempt_001_reserved,
        scope = :mcmc_free_initial_gradient_resource_probe_only,
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        unit_id = fixed_unit.unit_id,
        unit_sha256 = freecorr_canonical_sha256(fixed_unit),
        resource_probe_contract_sha256 = freecorr_canonical_sha256(
            freecorr_resource_probe_contract(),
        ),
        source_aggregate_sha256 = source.aggregate_sha256,
        stable_environment_identity_sha256 =
            environment.stable_identity_sha256,
        resource_probe_attempt = 1,
        terminal_receipt_filename = FREECORR_RESOURCE_PROBE_FILENAME,
        terminal_failure_filename = FREECORR_RESOURCE_PROBE_FAILURE_FILENAME,
        retry_allowed = false,
        scientific_execution_receipt = false,
        mcmc_executed = false,
        recovery_evidence_available = false,
        self_consistency_only = true,
        authenticity_attested = false,
        external_anchor_present = false,
        timestamp_attested = false,
    ))
end

function freecorr_validate_resource_probe_reservation(value, plan, unit)
    fixed_unit = freecorr_fixed_resource_probe_unit(plan, unit)
    native = freecorr_json_native(value)
    freecorr_exact_keys(native, (
        "schema", "object", "status", "scope", "plan_id",
        "plan_fingerprint", "unit_id", "unit_sha256",
        "resource_probe_contract_sha256", "source_aggregate_sha256",
        "stable_environment_identity_sha256", "resource_probe_attempt",
        "terminal_receipt_filename", "terminal_failure_filename",
        "retry_allowed", "scientific_execution_receipt", "mcmc_executed",
        "recovery_evidence_available", "self_consistency_only",
        "authenticity_attested", "external_anchor_present",
        "timestamp_attested", "content_hash",
    ), "resource-probe reservation")
    content_sha256 = freecorr_verify_content_hash(
        native;
        label = "resource-probe reservation",
    )
    native["schema"] == FREECORR_RESOURCE_PROBE_RESERVATION_SCHEMA &&
        native["object"] ==
            "mgmfrm_free_latent_correlation_2d_resource_probe_reservation" &&
        native["status"] == "resource_probe_attempt_001_reserved" &&
        native["scope"] == "mcmc_free_initial_gradient_resource_probe_only" &&
        native["plan_id"] == plan.plan_id &&
        native["plan_fingerprint"] == plan.plan_fingerprint &&
        native["unit_id"] == fixed_unit.unit_id &&
        native["unit_sha256"] == freecorr_canonical_sha256(fixed_unit) &&
        native["resource_probe_contract_sha256"] ==
            freecorr_canonical_sha256(freecorr_resource_probe_contract()) &&
        freecorr_require_int(
            native["resource_probe_attempt"],
            "resource-probe reservation attempt",
        ) == 1 &&
        native["terminal_receipt_filename"] ==
            FREECORR_RESOURCE_PROBE_FILENAME &&
        native["terminal_failure_filename"] ==
            FREECORR_RESOURCE_PROBE_FAILURE_FILENAME ||
        error("resource-probe reservation binding is invalid")
    source_aggregate_sha256 = freecorr_require_sha256(
        native["source_aggregate_sha256"],
        "resource-probe reservation source aggregate",
    )
    stable_environment_identity_sha256 = freecorr_require_sha256(
        native["stable_environment_identity_sha256"],
        "resource-probe reservation environment identity",
    )
    native["retry_allowed"] === false &&
        native["scientific_execution_receipt"] === false &&
        native["mcmc_executed"] === false &&
        native["recovery_evidence_available"] === false ||
        error("resource-probe reservation overstates its scope")
    freecorr_validate_self_consistency_boundary(
        native,
        "resource-probe reservation",
    )
    return (;
        content_sha256,
        source_aggregate_sha256,
        stable_environment_identity_sha256,
        validated = true,
    )
end

function freecorr_resource_probe_failure(
        plan,
        unit,
        reservation_file_sha256::AbstractString,
        reservation_content_sha256::AbstractString,
        failure)
    fixed_unit = freecorr_fixed_resource_probe_unit(plan, unit)
    message = portable_error_message(failure)
    isempty(message) && (message = string(typeof(failure)))
    return freecorr_with_content_hash((;
        schema = FREECORR_RESOURCE_PROBE_FAILURE_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_resource_probe_failure,
        status = :resource_probe_attempt_001_terminal_failure,
        scope = :mcmc_free_initial_gradient_resource_probe_only,
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        unit_id = fixed_unit.unit_id,
        unit_sha256 = freecorr_canonical_sha256(fixed_unit),
        resource_probe_attempt = 1,
        reservation_file_sha256,
        reservation_content_sha256,
        failure_type = string(typeof(failure)),
        failure_message = message,
        retry_allowed = false,
        scientific_execution_receipt = false,
        mcmc_executed = false,
        recovery_evidence_available = false,
        self_consistency_only = true,
        authenticity_attested = false,
        external_anchor_present = false,
        timestamp_attested = false,
    ))
end

function freecorr_validate_resource_probe_failure(value, plan, unit)
    fixed_unit = freecorr_fixed_resource_probe_unit(plan, unit)
    native = freecorr_json_native(value)
    freecorr_exact_keys(native, (
        "schema", "object", "status", "scope", "plan_id",
        "plan_fingerprint", "unit_id", "unit_sha256",
        "resource_probe_attempt", "reservation_file_sha256",
        "reservation_content_sha256",
        "failure_type", "failure_message", "retry_allowed",
        "scientific_execution_receipt", "mcmc_executed",
        "recovery_evidence_available", "self_consistency_only",
        "authenticity_attested", "external_anchor_present",
        "timestamp_attested", "content_hash",
    ), "resource-probe terminal failure")
    content_sha256 = freecorr_verify_content_hash(
        native;
        label = "resource-probe terminal failure",
    )
    native["schema"] == FREECORR_RESOURCE_PROBE_FAILURE_SCHEMA &&
        native["object"] ==
            "mgmfrm_free_latent_correlation_2d_resource_probe_failure" &&
        native["status"] == "resource_probe_attempt_001_terminal_failure" &&
        native["scope"] == "mcmc_free_initial_gradient_resource_probe_only" &&
        native["plan_id"] == plan.plan_id &&
        native["plan_fingerprint"] == plan.plan_fingerprint &&
        native["unit_id"] == fixed_unit.unit_id &&
        native["unit_sha256"] == freecorr_canonical_sha256(fixed_unit) &&
        freecorr_require_int(
            native["resource_probe_attempt"],
            "resource-probe failure attempt",
        ) == 1 || error("resource-probe terminal failure binding is invalid")
    reservation_file_sha256 = freecorr_require_sha256(
        native["reservation_file_sha256"],
        "resource-probe failure reservation file hash",
    )
    reservation_content_sha256 = freecorr_require_sha256(
        native["reservation_content_sha256"],
        "resource-probe failure reservation hash",
    )
    freecorr_require_string(
        native["failure_type"],
        "resource-probe failure type",
    )
    freecorr_require_string(
        native["failure_message"],
        "resource-probe failure message",
    )
    native["retry_allowed"] === false &&
        native["scientific_execution_receipt"] === false &&
        native["mcmc_executed"] === false &&
        native["recovery_evidence_available"] === false ||
        error("resource-probe terminal failure overstates its scope")
    freecorr_validate_self_consistency_boundary(
        native,
        "resource-probe terminal failure",
    )
    return (;
        content_sha256,
        reservation_file_sha256,
        reservation_content_sha256,
        validated = true,
    )
end

function freecorr_resource_probe_receipt(
        plan,
        unit,
        probe;
        test_root_override::Bool,
        reservation_file_sha256::AbstractString,
        reservation_content_sha256::AbstractString)
    fixed_unit = freecorr_fixed_resource_probe_unit(plan, unit)
    freecorr_initialize_resource_probe_runtime()
    getfield(
        BayesianMGMFRM,
        :_validate_free_correlation_study_resource_probe,
    )(probe, plan, fixed_unit.unit_id)
    probe_native = freecorr_json_native(probe)
    profile_passed = probe.profile_thresholds_passed === true
    status = profile_passed ?
        :initial_gradient_resource_probe_receipt_passed_scientific_execution_still_blocked :
        :initial_gradient_resource_probe_receipt_failed_scientific_execution_blocked
    material = (;
        schema = FREECORR_RESOURCE_PROBE_RECEIPT_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_resource_probe_receipt,
        status,
        scope = :mcmc_free_initial_gradient_resource_probe_only,
        scientific_execution_receipt = false,
        loaded_code_attestation = false,
        self_consistency_only = true,
        authenticity_attested = false,
        external_anchor_present = false,
        timestamp_attested = false,
        plan = (;
            schema = plan.schema,
            plan_id = plan.plan_id,
            version = plan.version,
            plan_fingerprint = plan.plan_fingerprint,
            unit_roster_sha256 = plan.unit_roster_sha256,
        ),
        unit = fixed_unit,
        resource_probe_contract = freecorr_resource_probe_contract(),
        reservation_file_sha256,
        reservation_content_sha256,
        resource_probe_artifact = probe_native,
        resource_probe_artifact_sha256 = probe.artifact_sha256,
        resource_probe_json_sha256 = freecorr_canonical_sha256(probe_native),
        profile_thresholds_passed = profile_passed,
        operational_execution_authorized = false,
        scientific_execution_authorized = false,
        scientific_attempt_created = false,
        mcmc_executed = false,
        recovery_evidence_available = false,
        short_nuts_resource_profile_completed = false,
        atomic_scientific_runner_ready = false,
        source_snapshot = freecorr_source_receipt(plan),
        environment_snapshot = freecorr_environment_receipt(plan),
        activity = (;
            resource_probe_attempt = 1,
            fixture_generated = true,
            gradient_executed = true,
            model_fit_run = false,
            mcmc_executed = false,
            scientific_state_written = false,
            recovery_evidence_available = false,
        ),
        next_gate = profile_passed ?
            :bounded_short_nuts_resource_profile :
            :resource_policy_review_without_v2_mutation,
        test_root_override,
        created_at_utc = freecorr_utc_timestamp(),
    )
    return freecorr_with_content_hash(material)
end

function freecorr_validate_resource_probe_payload(value, plan, unit)
    fixed_unit = freecorr_fixed_resource_probe_unit(plan, unit)
    probe = freecorr_json_native(value)
    planned = freecorr_json_native(
        BayesianMGMFRM.Experimental.
            free_latent_correlation_2d_study_resource_probe(
                plan,
                fixed_unit.unit_id;
                execute_measurement = false,
                repetitions = FREECORR_RESOURCE_PROBE_REPETITIONS,
            ),
    )
    freecorr_exact_keys(probe, keys(planned), "resource-probe payload")
    probe["execute_measurement"] === true ||
        error("resource-probe receipt must contain an executed measurement")
    freecorr_require_int(
        probe["repetitions"],
        "resource-probe repetitions",
    ) == FREECORR_RESOURCE_PROBE_REPETITIONS ||
        error("resource-probe repetitions were modified")

    to_uint64(value, label) = begin
        value isa Integer && !(value isa Bool) ||
            error("$label must be an integer")
        0 <= value <= typemax(UInt64) ||
            error("$label is outside the UInt64 range")
        UInt64(value)
    end
    restore_digest_row(value, label) = begin
        row = freecorr_exact_keys(value, ("path", "sha256"), label)
        return (;
            path = freecorr_require_string(row["path"], "$label path"),
            sha256 = freecorr_require_sha256(
                row["sha256"],
                "$label SHA-256",
            ),
        )
    end

    runtime_row = freecorr_exact_keys(probe["runtime"], (
        "julia_version", "n_threads", "os", "arch",
        "free_memory_bytes_before", "free_memory_bytes_after",
        "minimum_free_memory_bytes_observed", "total_memory_bytes",
    ), "resource-probe runtime")
    runtime = (;
        julia_version = freecorr_require_string(
            runtime_row["julia_version"],
            "resource-probe Julia version",
        ),
        n_threads = freecorr_require_int(
            runtime_row["n_threads"],
            "resource-probe thread count",
        ),
        os = freecorr_require_string(
            runtime_row["os"],
            "resource-probe operating system",
        ),
        arch = freecorr_require_string(
            runtime_row["arch"],
            "resource-probe architecture",
        ),
        free_memory_bytes_before = to_uint64(
            runtime_row["free_memory_bytes_before"],
            "resource-probe free memory before",
        ),
        free_memory_bytes_after = to_uint64(
            runtime_row["free_memory_bytes_after"],
            "resource-probe free memory after",
        ),
        minimum_free_memory_bytes_observed = to_uint64(
            runtime_row["minimum_free_memory_bytes_observed"],
            "resource-probe minimum free memory",
        ),
        total_memory_bytes = to_uint64(
            runtime_row["total_memory_bytes"],
            "resource-probe total memory",
        ),
    )

    provenance_row = freecorr_exact_keys(probe["provenance"], (
        "runtime", "environment", "sources", "environment_sha256",
        "sources_sha256", "provenance_sha256",
    ), "resource-probe provenance")
    freecorr_canonical_sha256(provenance_row["runtime"]) ==
        freecorr_canonical_sha256(runtime) ||
        error("resource-probe runtime is not bound into provenance")
    environment_row = freecorr_exact_keys(
        provenance_row["environment"],
        ("project", "manifest"),
        "resource-probe provenance environment",
    )
    environment = (;
        project = restore_digest_row(
            environment_row["project"],
            "resource-probe Project provenance",
        ),
        manifest = restore_digest_row(
            environment_row["manifest"],
            "resource-probe Manifest provenance",
        ),
    )
    source_rows = provenance_row["sources"]
    source_rows isa AbstractVector ||
        error("resource-probe provenance sources must be an array")
    sources = Tuple(
        restore_digest_row(
            row,
            "resource-probe source provenance row",
        ) for row in source_rows
    )
    provenance = (;
        runtime,
        environment,
        sources,
        environment_sha256 = freecorr_require_sha256(
            provenance_row["environment_sha256"],
            "resource-probe environment digest",
        ),
        sources_sha256 = freecorr_require_sha256(
            provenance_row["sources_sha256"],
            "resource-probe sources digest",
        ),
        provenance_sha256 = freecorr_require_sha256(
            provenance_row["provenance_sha256"],
            "resource-probe provenance digest",
        ),
    )

    measurement_row = freecorr_exact_keys(probe["measurement"], (
        "fixture", "data_counts", "gradient_profile",
    ), "resource-probe measurement")
    fixture_row = freecorr_exact_keys(measurement_row["fixture"], (
        "schema", "status", "data_signature", "realized_latent_correlation",
        "maximum_closed_form_oracle_error",
    ), "resource-probe fixture")
    fixture_status = freecorr_require_string(
        fixture_row["status"],
        "resource-probe fixture status",
    )
    fixture_status == "known_truth_generated" ||
        error("resource-probe fixture status was modified")
    fixture = (;
        schema = freecorr_require_string(
            fixture_row["schema"],
            "resource-probe fixture schema",
        ),
        status = :known_truth_generated,
        data_signature = freecorr_require_string(
            fixture_row["data_signature"],
            "resource-probe data signature",
        ),
        realized_latent_correlation = freecorr_require_finite_real(
            fixture_row["realized_latent_correlation"],
            "resource-probe realized latent correlation",
        ),
        maximum_closed_form_oracle_error = freecorr_require_finite_real(
            fixture_row["maximum_closed_form_oracle_error"],
            "resource-probe closed-form oracle error",
        ),
    )
    counts_row = freecorr_exact_keys(measurement_row["data_counts"], (
        "n_observations", "n_probability_cells",
    ), "resource-probe data counts")
    data_counts = (;
        n_observations = freecorr_require_int(
            counts_row["n_observations"],
            "resource-probe observation count",
        ),
        n_probability_cells = freecorr_require_int(
            counts_row["n_probability_cells"],
            "resource-probe probability-cell count",
        ),
    )

    profile_row = freecorr_exact_keys(
        measurement_row["gradient_profile"],
        (
            "initial_parameter_dimension", "adapter_validation_evaluations",
            "warmup_evaluations", "timed_evaluations",
            "free_memory_bytes_before", "free_memory_bytes_after",
            "minimum_free_memory_bytes_observed", "total_memory_bytes",
            "timed_rows", "median_gradient_seconds",
            "median_allocated_bytes", "median_gc_time_fraction",
        ),
        "resource-probe gradient profile",
    )
    timed_rows_json = profile_row["timed_rows"]
    timed_rows_json isa AbstractVector ||
        error("resource-probe timed rows must be an array")
    timed_rows = Tuple(map(timed_rows_json) do value
        row = freecorr_exact_keys(value, (
            "repetition", "elapsed_seconds", "allocated_bytes", "gc_seconds",
            "gc_time_fraction", "logdensity", "gradient_length",
            "gradient_finite", "maximum_absolute_gradient",
        ), "resource-probe timed row")
        return (;
            repetition = freecorr_require_int(
                row["repetition"],
                "resource-probe repetition",
            ),
            elapsed_seconds = freecorr_require_finite_real(
                row["elapsed_seconds"],
                "resource-probe elapsed seconds",
            ),
            allocated_bytes = freecorr_require_int(
                row["allocated_bytes"],
                "resource-probe allocated bytes",
            ),
            gc_seconds = freecorr_require_finite_real(
                row["gc_seconds"],
                "resource-probe GC seconds",
            ),
            gc_time_fraction = freecorr_require_finite_real(
                row["gc_time_fraction"],
                "resource-probe GC fraction",
            ),
            logdensity = freecorr_require_finite_real(
                row["logdensity"],
                "resource-probe log density",
            ),
            gradient_length = freecorr_require_int(
                row["gradient_length"],
                "resource-probe gradient length",
            ),
            gradient_finite = freecorr_require_bool(
                row["gradient_finite"],
                "resource-probe gradient-finite flag",
            ),
            maximum_absolute_gradient = freecorr_require_finite_real(
                row["maximum_absolute_gradient"],
                "resource-probe maximum gradient",
            ),
        )
    end)
    gradient_profile = (;
        initial_parameter_dimension = freecorr_require_int(
            profile_row["initial_parameter_dimension"],
            "resource-probe parameter dimension",
        ),
        adapter_validation_evaluations = freecorr_require_int(
            profile_row["adapter_validation_evaluations"],
            "resource-probe adapter validation count",
        ),
        warmup_evaluations = freecorr_require_int(
            profile_row["warmup_evaluations"],
            "resource-probe warmup count",
        ),
        timed_evaluations = freecorr_require_int(
            profile_row["timed_evaluations"],
            "resource-probe timed evaluation count",
        ),
        free_memory_bytes_before = to_uint64(
            profile_row["free_memory_bytes_before"],
            "resource-probe profile free memory before",
        ),
        free_memory_bytes_after = to_uint64(
            profile_row["free_memory_bytes_after"],
            "resource-probe profile free memory after",
        ),
        minimum_free_memory_bytes_observed = to_uint64(
            profile_row["minimum_free_memory_bytes_observed"],
            "resource-probe profile minimum free memory",
        ),
        total_memory_bytes = to_uint64(
            profile_row["total_memory_bytes"],
            "resource-probe profile total memory",
        ),
        timed_rows,
        median_gradient_seconds = freecorr_require_finite_real(
            profile_row["median_gradient_seconds"],
            "resource-probe median gradient seconds",
        ),
        median_allocated_bytes = freecorr_require_finite_real(
            profile_row["median_allocated_bytes"],
            "resource-probe median allocated bytes",
        ),
        median_gc_time_fraction = freecorr_require_finite_real(
            profile_row["median_gc_time_fraction"],
            "resource-probe median GC fraction",
        ),
    )
    measurement = (; fixture, data_counts, gradient_profile)

    expected = getfield(
        BayesianMGMFRM,
        :_free_correlation_resource_probe_artifact,
    )(
        plan,
        fixed_unit,
        FREECORR_RESOURCE_PROBE_REPETITIONS;
        runtime,
        provenance,
        measurement,
    )
    getfield(
        BayesianMGMFRM,
        :_validate_free_correlation_study_resource_probe,
    )(expected, plan, fixed_unit.unit_id)
    freecorr_canonical_sha256(probe) ==
        freecorr_canonical_sha256(expected) ||
        error(
            "serialized resource-probe payload differs from its " *
            "package-native reconstruction",
        )
    return (;
        profile_thresholds_passed = expected.profile_thresholds_passed,
        status = expected.status,
        free_memory_passed = expected.checks.free_memory_passed,
        estimated_full_unit_seconds =
            expected.checks.estimated_full_unit_seconds,
        package_provenance_digests_recomputed = true,
        package_artifact_sha256_recomputed = true,
        package_artifact_sha256_validation =
            :fully_recomputed_after_schema_specific_type_restoration,
        package_native_artifact = expected,
        validated = true,
    )
end
function freecorr_validate_resource_probe_receipt(
        value,
        plan,
        unit;
        require_current::Bool = true)
    fixed_unit = freecorr_fixed_resource_probe_unit(plan, unit)
    freecorr_initialize_resource_probe_runtime()
    native = freecorr_json_native(value)
    freecorr_exact_keys(native, (
        "schema", "object", "status", "scope",
        "scientific_execution_receipt", "loaded_code_attestation",
        "self_consistency_only", "authenticity_attested",
        "external_anchor_present", "timestamp_attested", "plan", "unit",
        "resource_probe_contract", "reservation_file_sha256",
        "reservation_content_sha256",
        "resource_probe_artifact",
        "resource_probe_artifact_sha256", "resource_probe_json_sha256",
        "profile_thresholds_passed", "operational_execution_authorized",
        "scientific_execution_authorized", "scientific_attempt_created",
        "mcmc_executed", "recovery_evidence_available",
        "short_nuts_resource_profile_completed",
        "atomic_scientific_runner_ready", "source_snapshot",
        "environment_snapshot", "activity", "next_gate",
        "test_root_override", "created_at_utc", "content_hash",
    ), "resource-probe receipt")
    content_sha256 = freecorr_verify_content_hash(
        native;
        label = "resource-probe receipt",
    )
    native["schema"] == FREECORR_RESOURCE_PROBE_RECEIPT_SCHEMA &&
        native["object"] ==
            "mgmfrm_free_latent_correlation_2d_resource_probe_receipt" &&
        native["scope"] == "mcmc_free_initial_gradient_resource_probe_only" ||
        error("resource-probe receipt identity/scope is invalid")
    native["scientific_execution_receipt"] === false &&
        native["loaded_code_attestation"] === false ||
        error("resource-probe receipt overstates its evidence scope")
    freecorr_validate_self_consistency_boundary(
        native,
        "resource-probe receipt",
    )
    plan_row = freecorr_exact_keys(native["plan"], (
        "schema", "plan_id", "version", "plan_fingerprint",
        "unit_roster_sha256",
    ), "resource-probe plan")
    plan_row["schema"] == plan.schema &&
        plan_row["plan_id"] == plan.plan_id &&
        plan_row["version"] == plan.version &&
        plan_row["plan_fingerprint"] == plan.plan_fingerprint &&
        plan_row["unit_roster_sha256"] == plan.unit_roster_sha256 ||
        error("resource-probe plan identity was modified")
    freecorr_canonical_sha256(native["unit"]) ==
        freecorr_canonical_sha256(fixed_unit) ||
        error("resource-probe unit was modified")
    freecorr_canonical_sha256(native["resource_probe_contract"]) ==
        freecorr_canonical_sha256(freecorr_resource_probe_contract()) ||
        error("resource-probe receipt contract was modified")
    reservation_file_sha256 = freecorr_require_sha256(
        native["reservation_file_sha256"],
        "resource-probe receipt reservation file hash",
    )
    reservation_content_sha256 = freecorr_require_sha256(
        native["reservation_content_sha256"],
        "resource-probe receipt reservation hash",
    )
    probe_validation = freecorr_validate_resource_probe_payload(
        native["resource_probe_artifact"],
        plan,
        fixed_unit,
    )
    package_artifact_sha256 = freecorr_require_sha256(
        native["resource_probe_artifact_sha256"],
        "resource-probe receipt package artifact hash",
    )
    package_artifact_sha256 ==
        native["resource_probe_artifact"]["artifact_sha256"] ||
        error("resource-probe package artifact hash binding was modified")
    probe_json_sha256 = freecorr_require_sha256(
        native["resource_probe_json_sha256"],
        "resource-probe receipt JSON hash",
    )
    probe_json_sha256 == freecorr_canonical_sha256(
        native["resource_probe_artifact"],
    ) || error("resource-probe JSON hash binding was modified")
    passed = probe_validation.profile_thresholds_passed
    native["profile_thresholds_passed"] === passed ||
        error("resource-probe receipt threshold result was modified")
    expected_status = passed ?
        "initial_gradient_resource_probe_receipt_passed_scientific_execution_still_blocked" :
        "initial_gradient_resource_probe_receipt_failed_scientific_execution_blocked"
    native["status"] == expected_status ||
        error("resource-probe receipt status is inconsistent")
    expected_next_gate = passed ?
        "bounded_short_nuts_resource_profile" :
        "resource_policy_review_without_v2_mutation"
    native["next_gate"] == expected_next_gate ||
        error("resource-probe receipt next gate is inconsistent")
    for field in (
            "operational_execution_authorized",
            "scientific_execution_authorized",
            "scientific_attempt_created",
            "mcmc_executed",
            "recovery_evidence_available",
            "short_nuts_resource_profile_completed",
            "atomic_scientific_runner_ready")
        native[field] === false ||
            error("resource-probe receipt quarantine flag $field was modified")
    end
    activity = freecorr_exact_keys(native["activity"], (
        "resource_probe_attempt", "fixture_generated", "gradient_executed",
        "model_fit_run", "mcmc_executed", "scientific_state_written",
        "recovery_evidence_available",
    ), "resource-probe activity")
    freecorr_require_int(
        activity["resource_probe_attempt"],
        "resource-probe attempt",
    ) == 1 || error("resource-probe attempt number was modified")
    activity["fixture_generated"] === true &&
        activity["gradient_executed"] === true &&
        activity["model_fit_run"] === false &&
        activity["mcmc_executed"] === false &&
        activity["scientific_state_written"] === false &&
        activity["recovery_evidence_available"] === false ||
        error("resource-probe activity was modified")
    source = freecorr_validate_source_receipt(
        native["source_snapshot"],
        plan;
        require_current,
    )
    environment = freecorr_validate_environment_receipt(
        native["environment_snapshot"],
        plan;
        require_current,
    )
    probe_sources = native["resource_probe_artifact"]["provenance"]["sources"]
    receipt_sources = native["source_snapshot"]["core_sources"]
    length(probe_sources) == length(receipt_sources) ||
        error("resource-probe source snapshots have different lengths")
    for index in eachindex(probe_sources)
        probe_sources[index]["path"] == receipt_sources[index]["path"] &&
            probe_sources[index]["sha256"] ==
                receipt_sources[index]["sha256"] ||
            error("resource-probe source snapshots do not match")
    end
    probe_environment =
        native["resource_probe_artifact"]["provenance"]["environment"]
    receipt_environment = native["environment_snapshot"]["environment_files"]
    for field in ("project", "manifest")
        probe_environment[field]["path"] ==
            receipt_environment[field]["path"] &&
            probe_environment[field]["sha256"] ==
                receipt_environment[field]["sha256"] ||
            error("resource-probe environment snapshots do not match")
    end
    freecorr_require_bool(native["test_root_override"], "test-root flag")
    freecorr_validate_utc_timestamp(native["created_at_utc"])
    return (;
        content_sha256,
        reservation_file_sha256,
        reservation_content_sha256,
        package_artifact_sha256,
        probe_json_sha256,
        profile_thresholds_passed = passed,
        probe_status = probe_validation.status,
        package_provenance_digests_recomputed =
            probe_validation.package_provenance_digests_recomputed,
        package_artifact_sha256_recomputed =
            probe_validation.package_artifact_sha256_recomputed,
        package_artifact_sha256_validation =
            probe_validation.package_artifact_sha256_validation,
        source,
        environment,
        scientific_execution_receipt = false,
        mcmc_executed = false,
        recovery_evidence_available = false,
        validated = true,
    )
end

function freecorr_dry_run_artifact(plan, unit; test_root_override::Bool)
    preflight = freecorr_preflight(plan, unit)
    protocol = preflight.protocol_execution_authorized
    operational = preflight.operational_execution_authorized
    execution = preflight.execution_authorized
    status = freecorr_gate_status(protocol, operational, execution)
    material = (;
        schema = FREECORR_DRY_RUN_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_archive_dry_run,
        status,
        scope = :preexecution_diagnostic_only,
        scientific_execution_receipt = false,
        loaded_code_attestation = false,
        self_consistency_only = true,
        authenticity_attested = false,
        external_anchor_present = false,
        timestamp_attested = false,
        plan = (;
            schema = plan.schema,
            plan_id = plan.plan_id,
            version = plan.version,
            plan_fingerprint = plan.plan_fingerprint,
            unit_roster_sha256 = plan.unit_roster_sha256,
        ),
        unit,
        preflight,
        preflight_sha256 = freecorr_canonical_sha256(preflight),
        source_snapshot = freecorr_source_receipt(plan),
        environment_snapshot = freecorr_environment_receipt(plan),
        execution_gates = (;
            protocol_execution_authorized = protocol,
            operational_execution_authorized = operational,
            execution_authorized = execution,
            archive_runner_execution_authorized = false,
        ),
        archive_contract = freecorr_archive_contract(),
        activity = (;
            attempt_reserved = false,
            fixture_generated = false,
            response_data_generated = false,
            model_fit_run = false,
            mcmc_executed = false,
            scientific_state_written = false,
            recovery_evidence_available = false,
        ),
        test_root_override,
        created_at_utc = freecorr_utc_timestamp(),
    )
    return freecorr_with_content_hash(material)
end

function freecorr_validate_dry_run_artifact(
        value,
        plan,
        unit;
        require_current::Bool = true)
    native = freecorr_json_native(value)
    freecorr_exact_keys(native, (
        "schema", "object", "status", "scope",
        "scientific_execution_receipt", "loaded_code_attestation",
        "self_consistency_only", "authenticity_attested",
        "external_anchor_present", "timestamp_attested", "plan",
        "unit", "preflight", "preflight_sha256", "source_snapshot",
        "environment_snapshot", "execution_gates", "archive_contract",
        "activity", "test_root_override", "created_at_utc", "content_hash",
    ), "dry-run artifact")
    artifact_sha256 = freecorr_verify_content_hash(
        native;
        label = "dry-run artifact",
    )
    native["schema"] == FREECORR_DRY_RUN_SCHEMA &&
        native["object"] ==
            "mgmfrm_free_latent_correlation_2d_archive_dry_run" &&
        native["scope"] == "preexecution_diagnostic_only" ||
        error("dry-run artifact identity/scope is invalid")
    native["scientific_execution_receipt"] === false &&
        native["loaded_code_attestation"] === false ||
        error("dry-run artifact overstates its evidence scope")
    freecorr_validate_self_consistency_boundary(native, "dry-run artifact")
    plan_row = freecorr_exact_keys(native["plan"], (
        "schema", "plan_id", "version", "plan_fingerprint",
        "unit_roster_sha256",
    ), "dry-run plan")
    plan_row["schema"] == plan.schema &&
        plan_row["plan_id"] == plan.plan_id &&
        plan_row["version"] == plan.version &&
        plan_row["plan_fingerprint"] == plan.plan_fingerprint &&
        plan_row["unit_roster_sha256"] == plan.unit_roster_sha256 ||
        error("dry-run plan identity was modified")
    freecorr_canonical_sha256(native["unit"]) ==
        freecorr_canonical_sha256(unit) || error("dry-run unit was modified")
    preflight = freecorr_preflight(plan, unit)
    preflight_sha256 = freecorr_canonical_sha256(preflight)
    native["preflight_sha256"] == preflight_sha256 &&
        freecorr_canonical_sha256(native["preflight"]) == preflight_sha256 ||
        error("dry-run preflight was modified")
    source = freecorr_validate_source_receipt(
        native["source_snapshot"],
        plan;
        require_current,
    )
    environment = freecorr_validate_environment_receipt(
        native["environment_snapshot"],
        plan;
        require_current,
    )
    gates = freecorr_exact_keys(native["execution_gates"], (
        "protocol_execution_authorized", "operational_execution_authorized",
        "execution_authorized", "archive_runner_execution_authorized",
    ), "dry-run execution gates")
    protocol = freecorr_require_bool(
        gates["protocol_execution_authorized"],
        "protocol execution gate",
    )
    operational = freecorr_require_bool(
        gates["operational_execution_authorized"],
        "operational execution gate",
    )
    execution = freecorr_require_bool(
        gates["execution_authorized"],
        "combined execution gate",
    )
    protocol === preflight.protocol_execution_authorized &&
        operational === preflight.operational_execution_authorized &&
        execution === preflight.execution_authorized ||
        error("dry-run gates differ from the frozen preflight")
    gates["archive_runner_execution_authorized"] === false ||
        error("pre-execution runner must remain blocked")
    expected_status = freecorr_gate_status(protocol, operational, execution)
    native["status"] == String(expected_status) ||
        error("dry-run status is inconsistent with its gate truth table")
    freecorr_canonical_sha256(native["archive_contract"]) ==
        freecorr_canonical_sha256(freecorr_archive_contract()) ||
        error("dry-run archive contract was modified")
    activity = freecorr_exact_keys(native["activity"], (
        "attempt_reserved", "fixture_generated", "response_data_generated",
        "model_fit_run", "mcmc_executed", "scientific_state_written",
        "recovery_evidence_available",
    ), "dry-run activity")
    all(value === false for value in values(activity)) ||
        error("dry-run artifact claims scientific activity")
    freecorr_require_bool(native["test_root_override"], "test-root flag")
    freecorr_validate_utc_timestamp(native["created_at_utc"])
    return (;
        artifact_sha256,
        source,
        environment,
        protocol_execution_authorized = protocol,
        operational_execution_authorized = operational,
        execution_authorized = execution,
        archive_runner_execution_authorized = false,
        validated = true,
    )
end

function freecorr_prepare_archive_root(
        attempt_root::AbstractString;
        test_root_override::Bool,
        create::Bool)
    boundary = test_root_override ? normpath(tempdir()) : FREECORR_RUNNER_ROOT
    freecorr_path_within(attempt_root, boundary) ||
        error("archive root escapes its permitted boundary")
    freecorr_reject_link_components(attempt_root, boundary)
    create && freecorr_ensure_directory(attempt_root, boundary)
    return normpath(boundary)
end

function freecorr_flush_file_buffers(io)
    flush(io)
    if Sys.iswindows()
        descriptor = reinterpret(Cint, Base.RawFD(Base.fd(io)))
        handle = ccall(:_get_osfhandle, Int, (Cint,), descriptor)
        handle == -1 && error("_get_osfhandle failed for staging file")
        succeeded = ccall(
            (:FlushFileBuffers, "kernel32"),
            Int32,
            (Ptr{Cvoid},),
            Ptr{Cvoid}(handle),
        )
        succeeded != 0 || error("FlushFileBuffers failed for staging file")
        return :flush_and_windows_flush_file_buffers
    end
    return :flush_only_nonwindows
end

function freecorr_atomic_publish_json(
        path::AbstractString,
        artifact,
        staging_dir::AbstractString,
        boundary::AbstractString;
        semantic_validator,
        artifact_label::AbstractString = "dry-run artifact")
    target = normpath(path)
    staging = normpath(staging_dir)
    freecorr_path_within(target, boundary) ||
        error("publish target escapes its permitted boundary")
    freecorr_path_within(staging, boundary) ||
        error("staging directory escapes its permitted boundary")
    freecorr_verify_content_hash(
        freecorr_json_native(artifact);
        label = "proposed $artifact_label",
    )
    bytes = freecorr_encode_json_bytes(artifact)

    target_parent = dirname(target)
    freecorr_ensure_directory(target_parent, boundary)
    freecorr_ensure_directory(staging, boundary)
    target_parent_identity = freecorr_directory_identity(target_parent)
    staging_identity = freecorr_directory_identity(staging)
    if !ismissing(target_parent_identity.device) &&
            !ismissing(staging_identity.device)
        target_parent_identity.device == staging_identity.device || error(
            "staging and target directories are not on the same volume",
        )
    end
    freecorr_path_occupied(target) && error(
        "refusing to replace an existing file, directory, or link: $target",
    )

    temporary_path, io = mktemp(staging)
    published = false
    durability = :not_flushed
    try
        write(io, bytes)
        durability = freecorr_flush_file_buffers(io)
        close(io)

        temporary_snapshot = freecorr_read_json_once(
            temporary_path,
            "staging artifact",
        )
        temporary_snapshot.nbytes == length(bytes) ||
            error(
                "staging artifact byte count changed: expected " *
                "$(length(bytes)), observed $(temporary_snapshot.nbytes)",
            )
        freecorr_verify_content_hash(
            temporary_snapshot.parsed;
            label = "staging artifact",
        )
        semantic_validator(temporary_snapshot.parsed)

        freecorr_reject_link_components(target_parent, boundary)
        freecorr_directory_identity(target_parent) == target_parent_identity ||
            error("target parent identity changed before publish")
        freecorr_path_occupied(target) && error(
            "publish target became occupied before hardlink publication",
        )
        try
            hardlink(temporary_path, target)
        catch error
            throw(ErrorException(
                "hardlink CREATE_NEW publication failed closed: " *
                portable_error_message(error),
            ))
        end
        published = true

        freecorr_directory_identity(target_parent) == target_parent_identity ||
            error("target parent identity changed during publish")
        isfile(target) && !islink(target) ||
            error("published target is not a regular file")
        freecorr_windows_reparse_point(target) &&
            error("published target is a Windows reparse point")
        target_snapshot = freecorr_read_json_once(
            target,
            "published $artifact_label",
        )
        target_snapshot.file_sha256 == temporary_snapshot.file_sha256 ||
            error("published target bytes differ from staging bytes")
        content_sha256 = freecorr_verify_content_hash(
            target_snapshot.parsed;
            label = "published $artifact_label",
        )
        validation = semantic_validator(target_snapshot.parsed)
        return (;
            path = target,
            file_sha256 = target_snapshot.file_sha256,
            content_sha256,
            nbytes = target_snapshot.nbytes,
            validation,
            durability,
            publication = :hardlink_create_new,
            published,
        )
    finally
        isopen(io) && close(io)
        freecorr_path_occupied(temporary_path) &&
            rm(temporary_path; force = true)
    end
end

function freecorr_write_dry_run(options, plan, unit)
    boundary = freecorr_prepare_archive_root(
        options.attempt_root;
        test_root_override = options.test_root_override,
        create = true,
    )
    artifact = freecorr_dry_run_artifact(
        plan,
        unit;
        test_root_override = options.test_root_override,
    )
    directory = freecorr_dry_run_dir(options.attempt_root, plan, unit)
    filename = string(
        Dates.format(Dates.now(Dates.UTC), dateformat"yyyymmddTHHMMSSsss"),
        "_pid", getpid(), "_dry_run.json",
    )
    path = joinpath(directory, filename)
    result = freecorr_atomic_publish_json(
        path,
        artifact,
        freecorr_staging_dir(options.attempt_root, plan),
        boundary;
        semantic_validator = value -> freecorr_validate_dry_run_artifact(
            value,
            plan,
            unit;
            require_current = true,
        ),
    )
    return merge(result, (; artifact))
end

function freecorr_write_resource_probe(
        options,
        plan,
        unit;
        measure_probe = freecorr_measure_resource_probe)
    fixed_unit = freecorr_fixed_resource_probe_unit(plan, unit)
    boundary = freecorr_prepare_archive_root(
        options.attempt_root;
        test_root_override = options.test_root_override,
        create = true,
    )
    path = freecorr_resource_probe_path(
        options.attempt_root,
        plan,
        fixed_unit,
    )
    reservation_path = freecorr_resource_probe_reservation_path(
        options.attempt_root,
        plan,
        fixed_unit,
    )
    failure_path = freecorr_resource_probe_failure_path(
        options.attempt_root,
        plan,
        fixed_unit,
    )
    all(candidate -> freecorr_path_within(candidate, boundary), (
        path,
        reservation_path,
        failure_path,
    )) || error("resource-probe path escapes its permitted boundary")

    prior_state = freecorr_resource_probe_archive_status(options, plan)
    prior_state.state === :absent || error(
        "immutable resource-probe attempt 001 is already consumed or " *
        "invalid; refusing a retry or replacement " *
        "(state=$(prior_state.state))",
    )
    reservation = freecorr_resource_probe_reservation(plan, fixed_unit)
    reservation_result = freecorr_atomic_publish_json(
        reservation_path,
        reservation,
        freecorr_staging_dir(options.attempt_root, plan),
        boundary;
        semantic_validator = value ->
            freecorr_validate_resource_probe_reservation(
                value,
                plan,
                fixed_unit,
            ),
        artifact_label = "resource-probe reservation",
    )

    try
        probe = measure_probe(plan, fixed_unit)
        receipt = freecorr_resource_probe_receipt(
            plan,
            fixed_unit,
            probe;
            test_root_override = options.test_root_override,
            reservation_file_sha256 = reservation_result.file_sha256,
            reservation_content_sha256 =
                reservation_result.content_sha256,
        )
        result = freecorr_atomic_publish_json(
            path,
            receipt,
            freecorr_staging_dir(options.attempt_root, plan),
            boundary;
            semantic_validator = value ->
                freecorr_validate_resource_probe_receipt(
                    value,
                    plan,
                    fixed_unit;
                    require_current = true,
                ),
            artifact_label = "resource-probe receipt",
        )
        terminal_state = freecorr_resource_probe_archive_status(options, plan)
        terminal_state.state === :valid &&
            terminal_state.outcome in (:threshold_pass, :threshold_fail) ||
            error(
                "published resource-probe receipt did not form a valid " *
                "reservation/terminal tree: state=$(terminal_state.state), " *
                "disposition=$(terminal_state.disposition), " *
                "details=$(terminal_state.details)",
            )
        return merge(result, (;
            receipt,
            probe,
            reservation_result,
            terminal_state,
        ))
    catch error
        if !freecorr_path_occupied(path) &&
                !freecorr_path_occupied(failure_path)
            failure = freecorr_resource_probe_failure(
                plan,
                fixed_unit,
                reservation_result.file_sha256,
                reservation_result.content_sha256,
                error,
            )
            marker_result = try
                freecorr_atomic_publish_json(
                    failure_path,
                    failure,
                    freecorr_staging_dir(options.attempt_root, plan),
                    boundary;
                    semantic_validator = value ->
                        freecorr_validate_resource_probe_failure(
                            value,
                            plan,
                            fixed_unit,
                        ),
                    artifact_label = "resource-probe terminal failure",
                )
            catch marker_error
                throw(ErrorException(
                    "resource-probe attempt 001 remains permanently " *
                    "reserved after failure, and terminal failure marker " *
                    "publication also failed: " *
                    portable_error_message(marker_error),
                ))
            end
            throw(ErrorException(
                "resource-probe attempt 001 terminally failed after its " *
                "immutable reservation; failure marker persisted at " *
                "$(marker_result.path): " * portable_error_message(error),
            ))
        end
        rethrow()
    end
end

function freecorr_scientific_paths(attempt_root, plan, unit)
    unit_root = freecorr_unit_root(attempt_root, plan, unit)
    attempt_dir = freecorr_attempt_dir(attempt_root, plan, unit)
    return (;
        unit_root,
        attempt_dir,
        state_paths = Tuple(joinpath(attempt_dir, filename)
            for filename in FREECORR_SCIENTIFIC_STATE_FILENAMES),
    )
end

function freecorr_validate_scientific_parent_chain(
        unit_root::AbstractString,
        boundary::AbstractString)
    parent = dirname(normpath(unit_root))
    freecorr_path_within(parent, boundary) || error(
        "scientific archive parent escapes its permitted boundary",
    )
    freecorr_reject_link_components(parent, boundary)
    current = parent
    while freecorr_path_within(current, boundary)
        if freecorr_path_occupied(current)
            isdir(current) && !islink(current) || error(
                "scientific archive parent is not a regular directory: $current",
            )
            policy = freecorr_windows_reparse_policy(current)
            policy.permitted || error(
                "scientific archive parent has a forbidden reparse tag: $current",
            )
            freecorr_directory_identity(current)
        end
        current == normpath(boundary) && break
        next_parent = dirname(current)
        next_parent == current && break
        current = next_parent
    end
    return true
end

function freecorr_attempt_status(options, plan, unit)
    boundary = try
        freecorr_prepare_archive_root(
            options.attempt_root;
            test_root_override = options.test_root_override,
            create = false,
        )
    catch error
        return (;
            state = :archive_security_invalid,
            archive_integrity_passed = false,
            disposition = :path_security_validation_failed,
            details = (portable_error_message(error),),
        )
    end
    paths = freecorr_scientific_paths(options.attempt_root, plan, unit)
    freecorr_path_within(paths.unit_root, boundary) || return (;
        state = :archive_security_invalid,
        archive_integrity_passed = false,
        disposition = :path_escaped_boundary,
        details = (),
    )
    try
        freecorr_validate_scientific_parent_chain(paths.unit_root, boundary)
    catch error
        return (;
            state = :archive_security_invalid,
            archive_integrity_passed = false,
            disposition = :scientific_parent_chain_security_validation_failed,
            details = (portable_error_message(error),),
        )
    end
    unit_path_present = freecorr_path_occupied(paths.unit_root)
    if unit_path_present
        if islink(paths.unit_root)
            return (;
                state = :archive_security_invalid,
                archive_integrity_passed = false,
                disposition = :scientific_unit_root_link_forbidden,
                details = (;
                    unit_path_present = true,
                    child_paths_inspected = false,
                    contents_interpreted = false,
                ),
            )
        end
        unit_policy = try
            freecorr_windows_reparse_policy(paths.unit_root)
        catch error
            return (;
                state = :archive_security_invalid,
                archive_integrity_passed = false,
                disposition = :scientific_unit_root_reparse_inspection_failed,
                details = (portable_error_message(error),),
            )
        end
        unit_policy.permitted || return (;
            state = :archive_security_invalid,
            archive_integrity_passed = false,
            disposition = :scientific_unit_root_reparse_forbidden,
            details = (;
                unit_path_present = true,
                reparse_tag = unit_policy.reparse_tag,
                reparse_classification = unit_policy.classification,
                child_paths_inspected = false,
                contents_interpreted = false,
            ),
        )
        return (;
            state = FREECORR_UNSUPPORTED_SCIENTIFIC_STATE,
            archive_integrity_passed = false,
            disposition = FREECORR_UNSUPPORTED_SCIENTIFIC_STATE,
            details = (;
                unit_path_present = true,
                unit_entry_reparse_classification =
                    unit_policy.classification,
                child_paths_inspected = false,
                contents_interpreted = false,
            ),
        )
    end
    return (;
        state = :absent,
        archive_integrity_passed = true,
        disposition = :no_scientific_attempt_materialized,
        details = (),
    )
end

function freecorr_resource_probe_archive_status(options, plan)
    fixed_unit = freecorr_fixed_resource_probe_unit(plan, first(plan.units))
    invalid(disposition, details = ()) = (;
        state = :invalid,
        archive_integrity_passed = false,
        disposition,
        attempt_consumed = true,
        outcome = nothing,
        profile_thresholds_passed = nothing,
        initial_gradient_probe_thresholds_passed = false,
        details,
    )
    partial(disposition, details = ()) = (;
        state = :partial,
        archive_integrity_passed = false,
        disposition,
        attempt_consumed = true,
        outcome = nothing,
        profile_thresholds_passed = nothing,
        initial_gradient_probe_thresholds_passed = false,
        details,
    )
    boundary = try
        freecorr_prepare_archive_root(
            options.attempt_root;
            test_root_override = options.test_root_override,
            create = false,
        )
    catch error
        return invalid(
            :resource_probe_path_security_validation_failed,
            (portable_error_message(error),),
        )
    end
    tree_root = joinpath(
        freecorr_execution_root(options.attempt_root, plan),
        FREECORR_RESOURCE_PROBE_DIRECTORY,
    )
    unit_root = freecorr_resource_probe_dir(
        options.attempt_root,
        plan,
        fixed_unit,
    )
    reservation_path = freecorr_resource_probe_reservation_path(
        options.attempt_root,
        plan,
        fixed_unit,
    )
    receipt_path = freecorr_resource_probe_path(
        options.attempt_root,
        plan,
        fixed_unit,
    )
    failure_path = freecorr_resource_probe_failure_path(
        options.attempt_root,
        plan,
        fixed_unit,
    )
    freecorr_path_occupied(tree_root) || return (;
        state = :absent,
        archive_integrity_passed = true,
        disposition = :no_resource_probe_attempt_materialized,
        attempt_consumed = false,
        outcome = nothing,
        profile_thresholds_passed = nothing,
        initial_gradient_probe_thresholds_passed = false,
        details = (),
    )

    try
        freecorr_reject_link_components(tree_root, boundary)
        isdir(tree_root) && !islink(tree_root) ||
            error("resource-probe root is not a regular directory")
        tree_names = sort(readdir(tree_root))
        isempty(tree_names) && return partial(
            :resource_probe_tree_materialized_incomplete,
        )
        tree_names == [fixed_unit.unit_id] ||
            error("resource-probe root has a partial or unexpected layout")
        freecorr_reject_link_components(unit_root, boundary)
        isdir(unit_root) && !islink(unit_root) ||
            error("resource-probe unit root is not a regular directory")
        names = sort(readdir(unit_root))
        isempty(names) && return partial(
            :resource_probe_unit_tree_materialized_incomplete,
        )
        allowed = Set((
            FREECORR_RESOURCE_PROBE_RESERVATION_FILENAME,
            FREECORR_RESOURCE_PROBE_FILENAME,
            FREECORR_RESOURCE_PROBE_FAILURE_FILENAME,
        ))
        all(name -> name in allowed, names) ||
            error("resource-probe unit root has an unexpected entry")

        has_reservation = FREECORR_RESOURCE_PROBE_RESERVATION_FILENAME in names
        has_receipt = FREECORR_RESOURCE_PROBE_FILENAME in names
        has_failure = FREECORR_RESOURCE_PROBE_FAILURE_FILENAME in names
        has_reservation || return invalid(
            :resource_probe_terminal_without_reservation,
            (; has_receipt, has_failure),
        )
        has_receipt && has_failure && return invalid(
            :resource_probe_ambiguous_terminal_state,
            (; has_receipt, has_failure),
        )

        freecorr_reject_link_components(reservation_path, boundary)
        reservation_snapshot = freecorr_read_json_once(
            reservation_path,
            "resource-probe reservation",
        )
        reservation = freecorr_validate_resource_probe_reservation(
            reservation_snapshot.parsed,
            plan,
            fixed_unit,
        )
        if !has_receipt && !has_failure
            return partial(
                :resource_probe_reserved_incomplete,
                (;
                    reservation_content_sha256 =
                        reservation.content_sha256,
                ),
            )
        elseif has_receipt
            freecorr_reject_link_components(receipt_path, boundary)
            receipt_snapshot = freecorr_read_json_once(
                receipt_path,
                "resource-probe receipt",
            )
            receipt = freecorr_validate_resource_probe_receipt(
                receipt_snapshot.parsed,
                plan,
                fixed_unit;
                require_current = false,
            )
            receipt.reservation_file_sha256 ==
                reservation_snapshot.file_sha256 &&
                receipt.reservation_content_sha256 ==
                    reservation.content_sha256 || error(
                "resource-probe receipt is not bound to its reservation",
            )
            receipt.source.aggregate_sha256 ==
                reservation.source_aggregate_sha256 &&
                receipt.environment.stable_identity_sha256 ==
                    reservation.stable_environment_identity_sha256 || error(
                "resource-probe receipt source/environment differs from " *
                "its pre-measurement reservation",
            )
            return (;
                state = :valid,
                archive_integrity_passed = true,
                disposition = receipt.profile_thresholds_passed ?
                    :thresholds_passed_scientific_execution_still_blocked :
                    :thresholds_failed_scientific_execution_blocked,
                attempt_consumed = true,
                outcome = receipt.profile_thresholds_passed ?
                    :threshold_pass : :threshold_fail,
                profile_thresholds_passed =
                    receipt.profile_thresholds_passed,
                initial_gradient_probe_thresholds_passed =
                    receipt.profile_thresholds_passed,
                details = (;
                    reservation_content_sha256 =
                        reservation.content_sha256,
                    receipt_content_sha256 = receipt.content_sha256,
                    current_source_snapshot_matched =
                        receipt.source.current_matches,
                    current_stable_environment_identity_matched =
                        receipt.environment.current_matches,
                ),
            )
        end

        freecorr_reject_link_components(failure_path, boundary)
        failure_snapshot = freecorr_read_json_once(
            failure_path,
            "resource-probe terminal failure",
        )
        failure = freecorr_validate_resource_probe_failure(
            failure_snapshot.parsed,
            plan,
            fixed_unit,
        )
        failure.reservation_file_sha256 ==
            reservation_snapshot.file_sha256 &&
            failure.reservation_content_sha256 ==
                reservation.content_sha256 || error(
            "resource-probe failure is not bound to its reservation",
        )
        return (;
            state = :valid,
            archive_integrity_passed = true,
            disposition = :measurement_failed_attempt_consumed,
            attempt_consumed = true,
            outcome = :operational_failure,
            profile_thresholds_passed = nothing,
            initial_gradient_probe_thresholds_passed = false,
            details = (;
                reservation_content_sha256 = reservation.content_sha256,
                failure_content_sha256 = failure.content_sha256,
            ),
        )
    catch error
        return invalid(
            :resource_probe_validation_failed,
            (portable_error_message(error),),
        )
    end
end

function freecorr_status_artifact(options, plan, unit)
    state = freecorr_attempt_status(options, plan, unit)
    resource_probe_state = freecorr_resource_probe_archive_status(
        options,
        plan,
    )
    workspace_filesystem = freecorr_safe_filesystem_policy_snapshot(
        FREECORR_RUNNER_ROOT,
    )
    attempt_root_filesystem = freecorr_safe_filesystem_policy_snapshot(
        options.attempt_root,
    )
    if !workspace_filesystem.inspection_passed ||
            !attempt_root_filesystem.inspection_passed
        state = (;
            state = :archive_security_invalid,
            archive_integrity_passed = false,
            disposition = :filesystem_policy_snapshot_failed,
            details = (;
                workspace_inspection_passed =
                    workspace_filesystem.inspection_passed,
                attempt_root_inspection_passed =
                    attempt_root_filesystem.inspection_passed,
            ),
        )
    end
    archive_integrity_passed = state.archive_integrity_passed &&
        resource_probe_state.archive_integrity_passed
    material = (;
        schema = FREECORR_STATUS_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_archive_status,
        status = archive_integrity_passed ?
            :archive_state_valid : :archive_state_invalid,
        mode = options.mode,
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        unit_id = unit.unit_id,
        phase = unit.phase,
        state,
        resource_probe_state,
        initial_gradient_probe_thresholds_passed =
            resource_probe_state.initial_gradient_probe_thresholds_passed,
        operational_execution_authorized = false,
        archive_integrity_passed,
        self_consistency_only = true,
        authenticity_attested = false,
        external_anchor_present = false,
        timestamp_attested = false,
        workspace_filesystem,
        attempt_root_filesystem,
        scientific_execution_available = false,
        scientific_execution_blocker = :preexecution_runner_v1,
        batch_execution_supported = false,
        dry_run_artifacts_inspected_by_status = false,
        resource_probe_artifacts_inspected_by_status = true,
        staging_orphans_are_status_inputs = false,
        postpublish_validation_failure_target_disposition =
            :left_in_place_for_forensic_review,
        archive_tree_modified = false,
        mcmc_started_by_this_invocation = false,
        test_root_override = options.test_root_override,
    )
    return freecorr_with_content_hash(material)
end

function freecorr_validate_artifact_path(options, plan, unit)
    path = normpath(options.artifact)
    boundary = freecorr_prepare_archive_root(
        options.attempt_root;
        test_root_override = options.test_root_override,
        create = false,
    )
    freecorr_path_within(path, boundary) ||
        error("--artifact escapes its permitted boundary")
    freecorr_reject_link_components(path, options.attempt_root)
    snapshot = freecorr_read_json_once(path, "validation artifact")
    fixed_resource_path = normpath(freecorr_resource_probe_path(
        options.attempt_root,
        plan,
        freecorr_fixed_resource_probe_unit(plan, first(plan.units)),
    ))
    if path == fixed_resource_path
        fixed_unit = freecorr_fixed_resource_probe_unit(plan, unit)
        tree_state = freecorr_resource_probe_archive_status(options, plan)
        tree_state.state === :valid &&
            tree_state.outcome in (:threshold_pass, :threshold_fail) || error(
            "resource-probe receipt is not part of a complete valid " *
            "reservation/terminal tree (state=$(tree_state.state), " *
            "disposition=$(tree_state.disposition))",
        )
        validation = freecorr_validate_resource_probe_receipt(
            snapshot.parsed,
            plan,
            fixed_unit;
            require_current = true,
        )
        return freecorr_with_content_hash((;
            schema = FREECORR_STATUS_SCHEMA,
            object =
                :mgmfrm_free_latent_correlation_2d_artifact_validation,
            status =
                :resource_probe_receipt_package_native_reconstruction_validated_current_snapshot,
            artifact_path = freecorr_record_path(path),
            artifact_schema = FREECORR_RESOURCE_PROBE_RECEIPT_SCHEMA,
            artifact_file_sha256 = snapshot.file_sha256,
            artifact_content_sha256 = validation.content_sha256,
            artifact_bytes_read_once = true,
            plan_id = plan.plan_id,
            plan_fingerprint = plan.plan_fingerprint,
            unit_id = fixed_unit.unit_id,
            profile_thresholds_passed =
                validation.profile_thresholds_passed,
            package_provenance_digests_recomputed =
                validation.package_provenance_digests_recomputed,
            package_artifact_sha256_recomputed =
                validation.package_artifact_sha256_recomputed,
            package_artifact_sha256_validation =
                validation.package_artifact_sha256_validation,
            scientific_execution_receipt = false,
            self_consistency_only = true,
            authenticity_attested = false,
            external_anchor_present = false,
            timestamp_attested = false,
            current_source_snapshot_matched =
                validation.source.current_matches,
            current_stable_environment_identity_matched =
                validation.environment.current_matches,
            mcmc_started_by_this_invocation = false,
            recovery_evidence_available = false,
        ))
    end

    dry_run_root = freecorr_dry_run_dir(options.attempt_root, plan, unit)
    freecorr_path_within(path, dry_run_root) || error(
        "--artifact must be a dry-run artifact for the selected unit or " *
        "the fixed resource-probe receipt",
    )
    validation = freecorr_validate_dry_run_artifact(
        snapshot.parsed,
        plan,
        unit;
        require_current = true,
    )
    return freecorr_with_content_hash((;
        schema = FREECORR_STATUS_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_artifact_validation,
        status =
            :dry_run_artifact_self_consistency_verified_current_snapshot,
        artifact_path = freecorr_record_path(path),
        artifact_schema = FREECORR_DRY_RUN_SCHEMA,
        artifact_file_sha256 = snapshot.file_sha256,
        artifact_content_sha256 = validation.artifact_sha256,
        artifact_bytes_read_once = true,
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        unit_id = unit.unit_id,
        scientific_execution_receipt = false,
        self_consistency_only = true,
        authenticity_attested = false,
        external_anchor_present = false,
        timestamp_attested = false,
        current_source_snapshot_matched = validation.source.current_matches,
        current_stable_environment_identity_matched =
            validation.environment.current_matches,
        mcmc_started_by_this_invocation = false,
    ))
end

function freecorr_execute_blocked_artifact(options, plan, unit)
    preflight = freecorr_preflight(plan, unit)
    freecorr_gate_status(
        preflight.protocol_execution_authorized,
        preflight.operational_execution_authorized,
        preflight.execution_authorized,
    )
    return freecorr_with_content_hash((;
        schema = FREECORR_STATUS_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_execution_block,
        status = :scientific_execution_blocked_pending_resource_profile,
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        unit_id = unit.unit_id,
        phase = unit.phase,
        confirmation_present = options.confirm_scientific_mcmc,
        self_consistency_only = true,
        authenticity_attested = false,
        external_anchor_present = false,
        timestamp_attested = false,
        protocol_execution_authorized =
            preflight.protocol_execution_authorized,
        operational_execution_authorized =
            preflight.operational_execution_authorized,
        execution_authorized = preflight.execution_authorized,
        archive_runner_execution_authorized = false,
        attempt_reserved = false,
        archive_tree_modified = false,
        fixture_generated = false,
        response_data_generated = false,
        model_fit_run = false,
        mcmc_executed = false,
        blocker = :preexecution_runner_v1_has_no_scientific_execution_path,
    ))
end

function freecorr_print_json(io, value)
    write_json(io, value)
    println(io)
    return nothing
end


function freecorr_runner_main(
        args;
        output_io = stdout,
        error_io = stderr,
        measure_probe = freecorr_measure_resource_probe)
    options = try
        freecorr_parse_args(args)
    catch error
        println(error_io, "error: ", portable_error_message(error))
        return 2
    end
    if options.help
        print(output_io, freecorr_runner_usage())
        return 0
    end
    plan, unit = try
        freecorr_plan_and_unit(options.unit_id)
    catch error
        println(error_io, "error: ", portable_error_message(error))
        return 2
    end
    if options.mode === :execute_primary
        freecorr_print_json(
            output_io,
            freecorr_execute_blocked_artifact(options, plan, unit),
        )
        return 3
    elseif options.mode === :resource_probe
        result = try
            freecorr_write_resource_probe(
                options,
                plan,
                unit;
                measure_probe,
            )
        catch error
            println(error_io, "error: ", portable_error_message(error))
            return 4
        end
        passed = result.receipt.profile_thresholds_passed
        freecorr_print_json(output_io, (;
            status = result.receipt.status,
            probe_status = result.probe.status,
            path = freecorr_record_path(result.path),
            reservation_path = freecorr_record_path(
                freecorr_resource_probe_reservation_path(
                    options.attempt_root,
                    plan,
                    unit,
                ),
            ),
            reservation_file_sha256 =
                result.reservation_result.file_sha256,
            reservation_content_sha256 =
                result.reservation_result.content_sha256,
            file_sha256 = result.file_sha256,
            content_sha256 = result.content_sha256,
            package_artifact_sha256 = result.probe.artifact_sha256,
            package_provenance_digests_recomputed_after_json = true,
            package_artifact_sha256_recomputed_after_json = true,
            package_artifact_sha256_validation =
                :fully_recomputed_after_schema_specific_type_restoration,
            publication = result.publication,
            durability = result.durability,
            profile_thresholds_passed = passed,
            initial_gradient_probe_thresholds_passed = passed,
            operational_execution_authorized = false,
            resource_probe_receipt_persisted = true,
            scientific_execution_receipt = false,
            self_consistency_only = true,
            authenticity_attested = false,
            external_anchor_present = false,
            timestamp_attested = false,
            scientific_attempt_created = false,
            mcmc_executed = false,
            recovery_evidence_available = false,
        ))
        return freecorr_resource_probe_exit_code(passed)
    elseif options.mode === :dry_run
        result = try
            freecorr_write_dry_run(options, plan, unit)
        catch error
            println(error_io, "error: ", portable_error_message(error))
            return 4
        end
        freecorr_print_json(output_io, (;
            status = result.artifact.status,
            path = freecorr_record_path(result.path),
            file_sha256 = result.file_sha256,
            content_sha256 = result.content_sha256,
            publication = result.publication,
            durability = result.durability,
            self_consistency_only = true,
            authenticity_attested = false,
            external_anchor_present = false,
            timestamp_attested = false,
            attempt_reserved = false,
            mcmc_executed = false,
        ))
        return 0
    elseif options.mode === :validate && options.artifact !== nothing
        artifact = try
            freecorr_validate_artifact_path(options, plan, unit)
        catch error
            println(error_io, "error: ", portable_error_message(error))
            return 4
        end
        freecorr_print_json(output_io, artifact)
        return 0
    end

    artifact = freecorr_status_artifact(options, plan, unit)
    freecorr_print_json(output_io, artifact)
    if options.mode === :validate &&
            artifact.status === :archive_state_invalid
        return 4
    end
    return 0
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    exit(freecorr_runner_main(ARGS))
end
