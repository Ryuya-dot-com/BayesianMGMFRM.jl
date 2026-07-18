#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_RAW_ROOT = joinpath(
    ROOT, "artifacts", "mgmfrm_tam_direct_agreement_multireplication")
const DEFAULT_RESULT = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_tam_direct_agreement_multireplication.json")
const DEFAULT_OUTPUT = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_tam_direct_agreement_raw_archive_audit.json")

const RESULT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_multireplication.v1"
const JOB_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_multireplication_job.v1"
const SELECTED_ATTEMPT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_selected_attempt.v1"
const AUDIT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_raw_archive_audit.v1"
const EXPECTED_JOB_IDS = [
    "n$(lpad(n, 3, '0'))_rep$(lpad(replication, 2, '0'))"
    for n in (40, 100) for replication in 1:5
]

include(joinpath(@__DIR__, "local_json.jl"))

function usage()
    return """
    Audit every retained attempt from the frozen package-versus-TAM direct run.

    The committed audit covers selected and non-selected attempts. It hashes the
    ignored raw archive without copying raw draws into the repository, verifies
    each selected pointer and selected job result, and checks every file row
    already recorded by the committed multireplication result.

    Usage:
      julia --project=. scripts/generate_mgmfrm_tam_direct_agreement_raw_archive_audit.jl [options]

    Options:
      --raw-root PATH
      --result PATH
      --output PATH
    """
end

function parse_args(args)
    raw_root = DEFAULT_RAW_ROOT
    result = DEFAULT_RESULT
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--raw-root"
            index < length(args) || error("--raw-root requires a path")
            raw_root = abspath(args[index + 1])
            index += 2
        elseif arg == "--result"
            index < length(args) || error("--result requires a path")
            result = abspath(args[index + 1])
            index += 2
        elseif arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; raw_root, result, output)
end

load_json(path::AbstractString) = JSON3.read(read(path, String))
as_string(value) = String(value)
as_bool(value) = Bool(value)
as_int(value) = Int(value)

function nullable_string(object, key::Symbol)
    return !haskey(object, key) || object[key] === nothing ? nothing :
        as_string(object[key])
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])

function file_sha256(path::AbstractString)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

function path_from_root(path::AbstractString)
    return isabspath(path) ? normpath(path) : normpath(joinpath(ROOT, path))
end

function manifest_fingerprint(rows)
    payload = join([
        string(row.path, '|', row.bytes, '|', row.sha256)
        for row in rows
    ], "\n")
    return bytes2hex(sha256(payload))
end

manifest_tuple(row) =
    (as_string(row[:path]), as_int(row[:bytes]), as_string(row[:sha256]))
manifest_tuple(row::NamedTuple) =
    (String(row.path), Int(row.bytes), String(row.sha256))

function attempt_number(path::AbstractString)
    matched = match(r"^attempt_(\d+)$", basename(path))
    matched === nothing && error("invalid attempt directory: $path")
    return parse(Int, matched.captures[1])
end

function directory_file_rows(directory::AbstractString, job_id::AbstractString,
        attempt::Int)
    paths = String[]
    for (root, _, files) in walkdir(directory)
        append!(paths, [joinpath(root, file) for file in files])
    end
    sort!(paths)
    return [(;
        job_id = Symbol(job_id),
        attempt,
        path = relpath(path, ROOT),
        bytes = filesize(path),
        sha256 = file_sha256(path),
        role = basename(path) == "job_result.json" ?
            :attempt_job_result : :attempt_raw_file,
    ) for path in paths]
end

function attempt_record(directory::AbstractString, job_id::AbstractString,
        selected_attempt::Int)
    attempt = attempt_number(directory)
    result_path = joinpath(directory, "job_result.json")
    isfile(result_path) || error("missing job result: $result_path")
    result = load_json(result_path)
    as_string(result[:schema]) == JOB_SCHEMA ||
        error("unexpected job-result schema: $result_path")
    as_string(result[:job_id]) == job_id ||
        error("job id mismatch: $result_path")
    as_int(result[:attempt]) == attempt ||
        error("attempt mismatch: $result_path")
    retry = result[:retry]
    files = directory_file_rows(directory, job_id, attempt)
    payload_files = [row for row in files
        if row.role !== :attempt_job_result]
    recorded_rows = haskey(result, :raw_file_manifest_rows) ?
        result[:raw_file_manifest_rows] : Any[]
    recorded_tuples = Set(manifest_tuple(row) for row in recorded_rows)
    actual_payload_tuples = Set(manifest_tuple(row) for row in payload_files)
    recorded_file_rows_match_actual =
        length(recorded_rows) == length(payload_files) &&
        recorded_tuples == actual_payload_tuples
    recorded_fingerprint = nullable_string(
        result, :raw_file_manifest_sha256)
    recorded_fingerprint_present = recorded_fingerprint !== nothing
    recorded_fingerprint_matches = recorded_fingerprint_present ?
        recorded_fingerprint == manifest_fingerprint([(
            path = as_string(row[:path]),
            bytes = as_int(row[:bytes]),
            sha256 = as_string(row[:sha256]),
        ) for row in recorded_rows]) : nothing
    engine_failure = as_bool(result[:engine_failure])
    missing_recorded_fingerprint_allowed =
        !recorded_fingerprint_present && engine_failure
    retry_attempt_matches = as_int(retry[:attempt]) == attempt
    safe_manifest_paths = all(row ->
        !occursin('|', row.path) && !occursin('\n', row.path) &&
            !occursin('\r', row.path), files)
    attempt_integrity_passed =
        recorded_file_rows_match_actual &&
        (recorded_fingerprint_matches === true ||
            missing_recorded_fingerprint_allowed) &&
        retry_attempt_matches && safe_manifest_paths
    return (;
        attempt_row = (;
            job_id = Symbol(job_id),
            attempt,
            selected = attempt == selected_attempt,
            path = relpath(directory, ROOT),
            result_path = relpath(result_path, ROOT),
            result_sha256 = file_sha256(result_path),
            execution_completed = as_bool(result[:execution_completed]),
            engine_failure,
            infrastructure_retry = as_bool(retry[:infrastructure_retry]),
            infrastructure_retry_reason = nullable_string(
                retry, :infrastructure_retry_reason),
            retry_attempt_matches,
            error_type = nullable_string(result, :error_type),
            error_message = nullable_string(result, :error_message),
            generator_source_sha256 =
                as_string(result[:protocol][:generator_source_sha256]),
            n_files = length(files),
            file_manifest_sha256 = manifest_fingerprint(files),
            n_recorded_payload_files = length(recorded_rows),
            n_actual_payload_files = length(payload_files),
            recorded_file_rows_match_actual,
            recorded_manifest_fingerprint_present =
                recorded_fingerprint_present,
            recorded_manifest_fingerprint = recorded_fingerprint,
            recorded_manifest_fingerprint_matches =
                recorded_fingerprint_matches,
            recorded_manifest_fingerprint_status =
                recorded_fingerprint_matches === true ? :matched :
                missing_recorded_fingerprint_allowed ?
                :missing_from_engine_failure_record_recomputed_by_audit :
                recorded_fingerprint_present ? :mismatch : :missing,
            safe_manifest_paths,
            attempt_integrity_passed,
        ),
        file_rows = files,
        result,
    )
end

function job_record(raw_root::AbstractString, job_id::AbstractString)
    job_root = joinpath(raw_root, job_id)
    isdir(job_root) || error("missing job directory: $job_root")
    selected_path = joinpath(job_root, "selected_attempt.json")
    isfile(selected_path) || error("missing selected pointer: $selected_path")
    pointer = load_json(selected_path)
    pointer_schema_matches =
        as_string(pointer[:schema]) == SELECTED_ATTEMPT_SCHEMA
    pointer_job_matches = as_string(pointer[:job_id]) == job_id
    selected_attempt = as_int(pointer[:selected_attempt])
    attempt_directories = sort(filter(isdir,
        [joinpath(job_root, name) for name in readdir(job_root)
            if startswith(name, "attempt_")]); by = attempt_number)
    attempts = [attempt_record(directory, job_id, selected_attempt)
        for directory in attempt_directories]
    attempt_rows = [record.attempt_row for record in attempts]
    file_rows = reduce(vcat, [record.file_rows for record in attempts];
        init = NamedTuple[])
    selected_records = [record for record in attempts
        if record.attempt_row.selected]
    length(selected_records) == 1 ||
        error("expected one selected attempt for $job_id")
    selected = only(selected_records)
    selected_result_path = path_from_root(
        as_string(pointer[:selected_job_result]))
    selected_result_exists = isfile(selected_result_path)
    selected_result_hash_matches = selected_result_exists &&
        file_sha256(selected_result_path) ==
        as_string(pointer[:selected_job_result_sha256])
    selected_result_path_matches = selected_result_exists &&
        normpath(selected_result_path) == path_from_root(
            selected.attempt_row.result_path)
    pointer_retry_reason = nullable_string(
        pointer, :infrastructure_retry_reason)
    selected_retry_documented = selected_attempt == 1 ||
        (pointer_retry_reason !== nothing &&
            selected.attempt_row.infrastructure_retry &&
            pointer_retry_reason ==
                selected.attempt_row.infrastructure_retry_reason)
    selected_attempt_is_latest =
        selected_attempt == maximum(row.attempt for row in attempt_rows)
    pointer_hash_and_path_valid = pointer_schema_matches &&
        pointer_job_matches && selected_result_exists &&
        selected_result_path_matches && selected_result_hash_matches
    selected_pointer_valid = pointer_hash_and_path_valid &&
        selected_retry_documented && selected_attempt_is_latest
    pointer_row = (;
        job_id = Symbol(job_id),
        path = relpath(selected_path, ROOT),
        sha256 = file_sha256(selected_path),
        schema_matches = pointer_schema_matches,
        job_id_matches = pointer_job_matches,
        selected_attempt,
        selected_attempt_is_latest,
        selected_result_path = relpath(selected_result_path, ROOT),
        selected_result_exists,
        selected_result_path_matches,
        selected_result_hash_matches,
        pointer_hash_and_path_valid,
        selected_execution_completed =
            selected.attempt_row.execution_completed,
        selected_engine_failure = selected.attempt_row.engine_failure,
        selected_retry_documented,
        infrastructure_retry_reason = pointer_retry_reason,
    )
    attempt_numbers = sort([row.attempt for row in attempt_rows])
    attempts_are_contiguous = attempt_numbers == collect(1:maximum(
        attempt_numbers))
    all_attempt_integrity_passed = all(
        row -> row.attempt_integrity_passed, attempt_rows)
    pointer_file_row = (;
        job_id = Symbol(job_id),
        attempt = 0,
        path = relpath(selected_path, ROOT),
        bytes = filesize(selected_path),
        sha256 = file_sha256(selected_path),
        role = :selected_attempt_pointer,
    )
    return (;
        job_row = (;
            job_id = Symbol(job_id),
            n_attempts = length(attempt_rows),
            n_selected_attempts = count(row -> row.selected, attempt_rows),
            n_completed_attempts = count(
                row -> row.execution_completed, attempt_rows),
            n_failed_attempts = count(row -> row.engine_failure, attempt_rows),
            attempts_are_contiguous,
            all_attempts_retained = attempts_are_contiguous &&
                length(attempt_rows) == length(attempt_directories),
            all_attempt_integrity_passed,
            selected_attempt,
            selected_execution_completed =
                selected.attempt_row.execution_completed,
            selected_pointer_valid,
        ),
        pointer_row,
        attempt_rows,
        file_rows = vcat(file_rows, [pointer_file_row]),
        selected_file_rows = selected.file_rows,
    )
end

function recorded_result_manifest_rows(result)
    rows = result[:raw_archive_manifest][:file_rows]
    return [(;
        job_id = Symbol(as_string(row[:job_id])),
        path = as_string(row[:path]),
        recorded_bytes = as_int(row[:bytes]),
        recorded_sha256 = as_string(row[:sha256]),
        exists = isfile(path_from_root(as_string(row[:path]))),
        bytes_match = isfile(path_from_root(as_string(row[:path]))) &&
            filesize(path_from_root(as_string(row[:path]))) ==
            as_int(row[:bytes]),
        sha256_matches = isfile(path_from_root(as_string(row[:path]))) &&
            file_sha256(path_from_root(as_string(row[:path]))) ==
            as_string(row[:sha256]),
    ) for row in rows]
end

function build_artifact(parsed)
    isdir(parsed.raw_root) || error("raw root missing: $(parsed.raw_root)")
    isfile(parsed.result) || error("result missing: $(parsed.result)")
    result = load_json(parsed.result)
    as_string(result[:schema]) == RESULT_SCHEMA ||
        error("unexpected multireplication result schema")
    records = [job_record(parsed.raw_root, job_id)
        for job_id in EXPECTED_JOB_IDS]
    job_rows = [record.job_row for record in records]
    pointer_rows = [record.pointer_row for record in records]
    attempt_rows = reduce(vcat,
        [record.attempt_rows for record in records]; init = NamedTuple[])
    file_rows = reduce(vcat,
        [record.file_rows for record in records]; init = NamedTuple[])
    sort!(file_rows; by = row -> row.path)
    result_manifest_rows = recorded_result_manifest_rows(result)
    recorded_manifest = result[:raw_archive_manifest]
    recorded_rows_for_fingerprint = [(;
        path = as_string(row[:path]),
        bytes = as_int(row[:bytes]),
        sha256 = as_string(row[:sha256]),
    ) for row in recorded_manifest[:file_rows]]
    recorded_manifest_fingerprint_matches =
        manifest_fingerprint(recorded_rows_for_fingerprint) ==
        as_string(recorded_manifest[:manifest_sha256])
    selected_file_rows = reduce(vcat,
        [record.selected_file_rows for record in records]; init = NamedTuple[])
    selected_file_tuples = Set(manifest_tuple(row)
        for row in selected_file_rows)
    recorded_result_file_tuples = Set(manifest_tuple(row)
        for row in recorded_manifest[:file_rows])
    selected_attempt_files_match_result_manifest =
        length(selected_file_rows) ==
            length(recorded_manifest[:file_rows]) &&
        selected_file_tuples == recorded_result_file_tuples
    result_selected_pointer_tuples = Set((
        as_string(row[:job_id]),
        as_string(row[:pointer_path]),
        as_string(row[:pointer_sha256]),
        as_string(row[:result_path]),
        as_string(row[:result_sha256]),
        as_int(row[:selected_attempt]),
    ) for row in result[:selected_attempt_rows])
    audit_selected_pointer_tuples = Set((
        String(row.job_id),
        row.path,
        row.sha256,
        row.selected_result_path,
        as_string(load_json(path_from_root(row.path))[
            :selected_job_result_sha256]),
        row.selected_attempt,
    ) for row in pointer_rows)
    result_selected_attempt_rows_match_audit =
        result_selected_pointer_tuples == audit_selected_pointer_tuples
    result_selected_paths = Set(tuple[4]
        for tuple in result_selected_pointer_tuples)
    audit_selected_paths = Set(tuple[4]
        for tuple in audit_selected_pointer_tuples)
    selected_result_sets_match = result_selected_paths == audit_selected_paths
    selected_generator_hashes = unique(row.generator_source_sha256
        for row in attempt_rows if row.selected)
    current_generator = joinpath(
        ROOT, "scripts", "generate_mgmfrm_tam_direct_agreement_multireplication.jl")
    all_selected_generator_hashes_match_current =
        length(selected_generator_hashes) == 1 &&
        only(selected_generator_hashes) == file_sha256(current_generator)
    all_paths_unique = length(unique(row.path for row in file_rows)) ==
        length(file_rows)
    all_selected_pointers_valid = all(row -> row.selected_pointer_valid,
        job_rows)
    all_attempt_integrity_passed = all(
        row -> row.all_attempt_integrity_passed, job_rows)
    all_result_manifest_files_match = all(row ->
        row.exists && row.bytes_match && row.sha256_matches,
        result_manifest_rows)
    nonselected_rows = [row for row in attempt_rows if !row.selected]
    failed_rows = [row for row in attempt_rows if row.engine_failure]
    retry_rows = [row for row in attempt_rows
        if row.selected && row.attempt > 1]
    result_execution_completed =
        as_bool(result[:summary][:execution_completed])
    all_selected_execution_completed = all(
        row -> row.selected_execution_completed, job_rows)
    n_selected_engine_failures = count(
        row -> row.selected_engine_failure, pointer_rows)
    gitignore_path = joinpath(ROOT, ".gitignore")
    raw_root_is_gitignored = isfile(gitignore_path) &&
        any(line -> strip(line) in ("artifacts", "artifacts/"),
            eachline(gitignore_path)) &&
        startswith(relpath(parsed.raw_root, ROOT), "artifacts")
    audit_passed = length(job_rows) == 10 &&
        Set(String(row.job_id) for row in job_rows) == Set(EXPECTED_JOB_IDS) &&
        length(pointer_rows) == 10 &&
        length(attempt_rows) >= 10 &&
        all_selected_pointers_valid &&
        all_attempt_integrity_passed &&
        all(row -> row.all_attempts_retained, job_rows) &&
        all(row -> !isempty(row.sha256), file_rows) &&
        all_paths_unique &&
        selected_result_sets_match &&
        result_selected_attempt_rows_match_audit &&
        selected_attempt_files_match_result_manifest &&
        recorded_manifest_fingerprint_matches &&
        all_result_manifest_files_match &&
        all_selected_generator_hashes_match_current &&
        raw_root_is_gitignored
    return (;
        schema = AUDIT_SCHEMA,
        family = :mfrm,
        scope = :tam_direct_agreement_all_attempt_raw_archive_audit,
        status = :all_attempt_archive_audited,
        decision = :retain_all_attempts_commit_hash_manifest_only,
        local_only = true,
        raw_archive_committed = false,
        raw_archive_hash_manifest_committed = true,
        publication_or_registration_action = false,
        public_claim_release_allowed = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = (;
            protocol_id = :mgmfrm_tam_direct_agreement_raw_archive_audit_v1,
            generator =
                "scripts/generate_mgmfrm_tam_direct_agreement_raw_archive_audit.jl",
            generator_source_sha256 = file_sha256(@__FILE__),
            execution_generator =
                "scripts/generate_mgmfrm_tam_direct_agreement_multireplication.jl",
            execution_generator_source_sha256 = file_sha256(current_generator),
            result_artifact = relpath(parsed.result, ROOT),
            result_artifact_sha256 = file_sha256(parsed.result),
            result_schema = RESULT_SCHEMA,
            raw_root = relpath(parsed.raw_root, ROOT),
            raw_root_is_gitignored,
            selected_and_nonselected_attempts_in_scope = true,
            manifest_fingerprint_format =
                :newline_joined_path_pipe_bytes_pipe_sha256_v1_order_preserving,
            audit_file_order = :lexicographic_path,
            repository_generated_paths_exclude_pipe_and_newline = true,
        ),
        job_rows,
        selected_pointer_rows = pointer_rows,
        attempt_rows,
        raw_file_rows = file_rows,
        result_manifest_verification_rows = result_manifest_rows,
        archive_manifest = (;
            n_files = length(file_rows),
            manifest_sha256 = manifest_fingerprint(file_rows),
            fingerprint_format =
                :newline_joined_path_pipe_bytes_pipe_sha256_v1_order_preserving,
            file_order = :lexicographic_path,
            includes_selected_attempt_pointers = true,
            includes_selected_attempts = true,
            includes_nonselected_attempts = true,
            includes_failed_attempts = true,
        ),
        failure_and_retry_accounting = (;
            n_failed_attempts = length(failed_rows),
            failed_attempt_rows = failed_rows,
            n_nonselected_attempts = length(nonselected_rows),
            nonselected_attempt_rows = nonselected_rows,
            n_documented_selected_retries = length(retry_rows),
            documented_selected_retry_rows = retry_rows,
            failed_attempts_excluded_from_archive = false,
            selected_attempt_denominator_reduced = false,
            replacement_seed_used = false,
        ),
        claim_limits = [
            :raw_archive_is_local_and_gitignored,
            :hashes_verify_bytes_but_do_not_replace_independent_reexecution,
            :failed_attempt_retention_does_not_convert_failure_to_evidence,
            :selected_retry_is_an_infrastructure_retry_not_a_seed_replacement,
            :audit_does_not_release_public_claims,
        ],
        summary = (;
            passed = audit_passed,
            archive_integrity_passed = audit_passed,
            n_expected_jobs = length(EXPECTED_JOB_IDS),
            n_job_rows = length(job_rows),
            n_selected_pointers = length(pointer_rows),
            n_attempts = length(attempt_rows),
            n_selected_attempts = count(row -> row.selected, attempt_rows),
            n_nonselected_attempts = length(nonselected_rows),
            n_failed_attempts = length(failed_rows),
            n_files = length(file_rows),
            all_selected_pointers_valid,
            all_attempt_integrity_passed,
            all_attempts_retained = all(row -> row.all_attempts_retained,
                job_rows),
            selected_result_sets_match,
            result_selected_attempt_rows_match_audit,
            selected_attempt_files_match_result_manifest,
            recorded_result_manifest_fingerprint_matches =
                recorded_manifest_fingerprint_matches,
            all_recorded_result_manifest_files_match =
                all_result_manifest_files_match,
            all_selected_generator_hashes_match_current,
            all_file_paths_unique = all_paths_unique,
            raw_root_is_gitignored,
            result_execution_completed,
            all_selected_execution_completed,
            n_selected_engine_failures,
            raw_archive_committed = false,
            hash_manifest_committed = true,
            public_claim_release_allowed = false,
            next_gate =
                :generate_independent_post_execution_tam_direct_review_packet,
        ),
    )
end

function main(args)
    parsed = parse_args(args)
    artifact = build_artifact(parsed)
    write_artifact(parsed.output, artifact)
    println("wrote ", relpath(parsed.output, ROOT))
    println("passed=", artifact.summary.passed,
        " jobs=", artifact.summary.n_job_rows,
        " attempts=", artifact.summary.n_attempts,
        " failed_attempts=", artifact.summary.n_failed_attempts,
        " files=", artifact.summary.n_files)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
