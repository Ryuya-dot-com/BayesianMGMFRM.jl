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
const DEFAULT_EXECUTION_SNAPSHOT = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_tam_direct_agreement_policy_refinement_execution_snapshot.json")
const DEFAULT_OUTPUT = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_tam_direct_agreement_raw_archive_audit.json")

const RESULT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_multireplication.v1"
const JOB_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_multireplication_job.v1"
const SELECTED_ATTEMPT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_selected_attempt.v1"
const REFINEMENT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy_refinement.v1"
const AUDIT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_raw_archive_audit.v1"
const EXPECTED_EXECUTION_SNAPSHOT_SHA256 =
    "03fe1a903d4fd218b5ab3e5ad51f5133ec1d8f274fafcea0bf8ac330876d8f4e"
const EXPECTED_RETAINED_FAILED_GENERATOR_SHA256 =
    "18da6449e71cf078dbbfc5d675a82c79e7a1b7d4e1cb8624b1101bf20c73e6a2"
const EXPECTED_RETAINED_ATTEMPTS = 11
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
      --execution-snapshot PATH
      --output PATH
    """
end

function parse_args(args)
    raw_root = DEFAULT_RAW_ROOT
    result = DEFAULT_RESULT
    execution_snapshot = DEFAULT_EXECUTION_SNAPSHOT
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
        elseif arg == "--execution-snapshot"
            index < length(args) ||
                error("--execution-snapshot requires a path")
            execution_snapshot = abspath(args[index + 1])
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
    return (; raw_root, result, execution_snapshot, output)
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

function execution_source_row(snapshot, name::Symbol,
        protocol_field::Symbol)
    sources = snapshot[:source_artifacts]
    path = path_from_root(as_string(sources[name]))
    expected_sha256 = as_string(sources[Symbol(string(name), "_sha256")])
    present = isfile(path)
    actual_sha256 = present ? file_sha256(path) : nothing
    return (;
        source = name,
        protocol_field,
        path = relpath(path, ROOT),
        expected_sha256,
        present,
        actual_sha256,
        artifact_sha256_matches = present &&
            actual_sha256 == expected_sha256,
    )
end

function execution_lineage_contract(path::AbstractString)
    isfile(path) || error("execution snapshot missing: $path")
    snapshot = load_json(path)
    as_string(snapshot[:schema]) == REFINEMENT_SCHEMA ||
        error("unexpected execution-snapshot schema")
    snapshot_sha256 = file_sha256(path)
    snapshot_sha256_matches_pinned =
        snapshot_sha256 == EXPECTED_EXECUTION_SNAPSHOT_SHA256
    source_rows = [
        execution_source_row(snapshot, :baseline, :baseline_sha256),
        execution_source_row(
            snapshot, :frozen_policy, :frozen_policy_sha256),
        execution_source_row(
            snapshot, :recovery_policy, :recovery_policy_sha256),
    ]
    seed_rows = snapshot[:data_and_input_contract][:seed_registry_rows]
    seed_keys = [
        "n$(lpad(as_int(row[:n_persons]), 3, '0'))_rep$(lpad(as_int(row[:replication]), 2, '0'))"
        for row in seed_rows
    ]
    seed_registry_exact = length(seed_rows) == length(EXPECTED_JOB_IDS) &&
        length(unique(seed_keys)) == length(seed_keys) &&
        Set(seed_keys) == Set(EXPECTED_JOB_IDS)
    expected_truth_sha256 = as_string(
        snapshot[:data_and_input_contract][:fixed_truth_sha256])
    baseline_source_row = only(row for row in source_rows
        if row.source === :baseline)
    baseline_artifact = baseline_source_row.present ?
        load_json(path_from_root(baseline_source_row.path)) : nothing
    baseline_truth_sha256 = baseline_artifact === nothing ? nothing :
        as_string(baseline_artifact[:checksums][:truth_sha256])
    fixed_truth_source_lineage_exact =
        baseline_source_row.artifact_sha256_matches &&
        baseline_truth_sha256 == expected_truth_sha256
    environment = snapshot[:environment_contract]
    project_toml_sha256 = as_string(environment[:project_toml_sha256])
    manifest_toml_sha256 = as_string(environment[:manifest_toml_sha256])
    return (;
        snapshot,
        snapshot_path = path,
        snapshot_sha256,
        snapshot_sha256_matches_pinned,
        source_rows,
        all_source_artifacts_present_exact = all(
            row -> row.artifact_sha256_matches, source_rows),
        seed_rows,
        seed_registry_exact,
        expected_truth_sha256,
        baseline_truth_sha256,
        fixed_truth_source_lineage_exact,
        project_toml_sha256,
        manifest_toml_sha256,
    )
end

function lineage_seed_row(lineage, n_persons::Int, replication::Int)
    rows = [row for row in lineage.seed_rows
        if as_int(row[:n_persons]) == n_persons &&
            as_int(row[:replication]) == replication]
    return length(rows) == 1 ? only(rows) : nothing
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
        selected_attempt::Int, lineage)
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
    protocol = result[:protocol]
    n_persons = as_int(result[:n_persons])
    replication = as_int(result[:replication])
    engine_failure = as_bool(result[:engine_failure])
    expected_job_id_from_design =
        "n$(lpad(n_persons, 3, '0'))_rep$(lpad(replication, 2, '0'))"
    job_design_identity_exact = job_id == expected_job_id_from_design
    retained_failed_attempt_expected_row =
        job_id == "n040_rep01" && attempt == 1 &&
        attempt != selected_attempt && engine_failure &&
        !as_bool(result[:execution_completed])
    refinement_snapshot_sha256_matches =
        as_string(protocol[:refinement_sha256]) == lineage.snapshot_sha256
    recorded_truth_sha256 = nullable_string(protocol, :truth_sha256)
    truth_sha256_recorded = recorded_truth_sha256 !== nothing
    truth_sha256_matches = truth_sha256_recorded ?
        recorded_truth_sha256 == lineage.expected_truth_sha256 :
        retained_failed_attempt_expected_row &&
            lineage.fixed_truth_source_lineage_exact
    truth_lineage_source = truth_sha256_recorded ?
        :attempt_protocol : retained_failed_attempt_expected_row ?
        :pinned_baseline_checksum_for_retained_failed_attempt :
        :missing
    source_input_rows = [(;
        source = row.source,
        protocol_field = row.protocol_field,
        expected_sha256 = row.expected_sha256,
        recorded_sha256 = as_string(protocol[row.protocol_field]),
        recorded_sha256_matches =
            as_string(protocol[row.protocol_field]) == row.expected_sha256,
        source_artifact_present = row.present,
        source_artifact_sha256 = row.actual_sha256,
        source_artifact_sha256_matches = row.artifact_sha256_matches,
    ) for row in lineage.source_rows]
    source_input_lineage_exact =
        lineage.all_source_artifacts_present_exact &&
        all(row -> row.recorded_sha256_matches, source_input_rows)
    seed_row = lineage_seed_row(lineage, n_persons, replication)
    seed_registry_row_present = seed_row !== nothing
    ability_seed_matches = seed_registry_row_present &&
        as_int(protocol[:ability_seed]) == as_int(seed_row[:ability_seed])
    response_seed_matches = seed_registry_row_present &&
        as_int(protocol[:response_seed]) == as_int(seed_row[:response_seed])
    package_fit_seed_matches = seed_registry_row_present &&
        as_int(protocol[:package_fit_seed]) ==
            as_int(seed_row[:package_fit_seed])
    seed_registry_lineage_exact = lineage.seed_registry_exact &&
        job_design_identity_exact &&
        ability_seed_matches && response_seed_matches &&
        package_fit_seed_matches
    project_path = joinpath(directory, "Project.toml")
    manifest_path = joinpath(directory, "Manifest.toml")
    project_toml_present = isfile(project_path)
    manifest_toml_present = isfile(manifest_path)
    project_toml_sha256 = project_toml_present ?
        file_sha256(project_path) : nothing
    manifest_toml_sha256 = manifest_toml_present ?
        file_sha256(manifest_path) : nothing
    project_toml_lineage_exact = project_toml_present &&
        project_toml_sha256 == lineage.project_toml_sha256
    manifest_toml_lineage_exact = manifest_toml_present &&
        manifest_toml_sha256 == lineage.manifest_toml_sha256
    environment_input_lineage_exact = project_toml_lineage_exact &&
        manifest_toml_lineage_exact
    current_generator = joinpath(
        ROOT, "scripts", "generate_mgmfrm_tam_direct_agreement_multireplication.jl")
    generator_path_matches = as_string(protocol[:generator]) ==
        relpath(current_generator, ROOT)
    generator_source_sha256 =
        as_string(protocol[:generator_source_sha256])
    generator_source_sha256_present = !isempty(generator_source_sha256)
    generator_source_sha256_matches_current =
        generator_source_sha256 == file_sha256(current_generator)
    generator_source_sha256_matches_retained_failed_version =
        generator_source_sha256 == EXPECTED_RETAINED_FAILED_GENERATOR_SHA256
    generator_current_match_required = !engine_failure
    retained_failed_generator_exception_expected_row =
        retained_failed_attempt_expected_row
    generator_lineage_accepted = generator_path_matches &&
        generator_source_sha256_present &&
        (generator_source_sha256_matches_current ||
            (retained_failed_generator_exception_expected_row &&
                generator_source_sha256_matches_retained_failed_version))
    execution_input_lineage_exact =
        lineage.snapshot_sha256_matches_pinned &&
        refinement_snapshot_sha256_matches &&
        source_input_lineage_exact && truth_sha256_matches &&
        seed_registry_lineage_exact && job_design_identity_exact &&
        environment_input_lineage_exact && generator_lineage_accepted
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
            generator_source_sha256,
            generator_path_matches,
            generator_source_sha256_present,
            generator_source_sha256_matches_current,
            generator_source_sha256_matches_retained_failed_version,
            generator_current_match_required,
            retained_failed_generator_exception_expected_row,
            generator_lineage_accepted,
            expected_job_id_from_design = Symbol(expected_job_id_from_design),
            job_design_identity_exact,
            refinement_snapshot_sha256 = lineage.snapshot_sha256,
            refinement_snapshot_sha256_matches,
            expected_truth_sha256 = lineage.expected_truth_sha256,
            recorded_truth_sha256,
            truth_sha256_recorded,
            truth_sha256_matches,
            truth_lineage_source,
            source_input_rows,
            source_input_lineage_exact,
            seed_registry_row_present,
            ability_seed_matches,
            response_seed_matches,
            package_fit_seed_matches,
            seed_registry_lineage_exact,
            project_toml_present,
            project_toml_sha256,
            expected_project_toml_sha256 = lineage.project_toml_sha256,
            project_toml_lineage_exact,
            manifest_toml_present,
            manifest_toml_sha256,
            expected_manifest_toml_sha256 = lineage.manifest_toml_sha256,
            manifest_toml_lineage_exact,
            environment_input_lineage_exact,
            execution_input_lineage_exact,
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

function job_record(raw_root::AbstractString, job_id::AbstractString,
        lineage)
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
    attempts = [attempt_record(directory, job_id, selected_attempt, lineage)
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
    all_attempt_execution_input_lineage_exact = all(
        row -> row.execution_input_lineage_exact, attempt_rows)
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
            all_attempt_execution_input_lineage_exact,
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
    lineage = execution_lineage_contract(parsed.execution_snapshot)
    records = [job_record(parsed.raw_root, job_id, lineage)
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
    all_retained_refinement_lineage_exact = all(row ->
        row.refinement_snapshot_sha256_matches, attempt_rows)
    all_retained_job_design_identity_exact = all(row ->
        row.job_design_identity_exact, attempt_rows)
    all_retained_truth_lineage_exact = all(row ->
        row.truth_sha256_matches, attempt_rows)
    all_retained_source_input_lineage_exact = all(row ->
        row.source_input_lineage_exact, attempt_rows)
    all_retained_seed_registry_lineage_exact = all(row ->
        row.seed_registry_lineage_exact, attempt_rows)
    all_retained_project_toml_lineage_exact = all(row ->
        row.project_toml_lineage_exact, attempt_rows)
    all_retained_manifest_toml_lineage_exact = all(row ->
        row.manifest_toml_lineage_exact, attempt_rows)
    all_retained_environment_input_lineage_exact = all(row ->
        row.environment_input_lineage_exact, attempt_rows)
    all_retained_generator_lineage_accepted = all(row ->
        row.generator_lineage_accepted, attempt_rows)
    retained_failed_generator_exception_rows = [row for row in attempt_rows
        if row.generator_source_sha256_matches_retained_failed_version]
    retained_failed_generator_exception_row =
        length(retained_failed_generator_exception_rows) == 1 ?
        only(retained_failed_generator_exception_rows) : nothing
    retained_failed_generator_exception_exact =
        retained_failed_generator_exception_row !== nothing &&
        getproperty(retained_failed_generator_exception_row,
            :retained_failed_generator_exception_expected_row) &&
        getproperty(retained_failed_generator_exception_row,
            :generator_lineage_accepted)
    all_retained_execution_input_lineage_exact = all(row ->
        row.execution_input_lineage_exact, attempt_rows)
    n_execution_input_lineage_failures = count(row ->
        !row.execution_input_lineage_exact, attempt_rows)
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
        length(attempt_rows) == EXPECTED_RETAINED_ATTEMPTS &&
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
        lineage.snapshot_sha256_matches_pinned &&
        lineage.all_source_artifacts_present_exact &&
        lineage.seed_registry_exact &&
        lineage.fixed_truth_source_lineage_exact &&
        all_retained_refinement_lineage_exact &&
        all_retained_job_design_identity_exact &&
        all_retained_truth_lineage_exact &&
        all_retained_source_input_lineage_exact &&
        all_retained_seed_registry_lineage_exact &&
        all_retained_project_toml_lineage_exact &&
        all_retained_manifest_toml_lineage_exact &&
        all_retained_environment_input_lineage_exact &&
        all_retained_generator_lineage_accepted &&
        retained_failed_generator_exception_exact &&
        all_retained_execution_input_lineage_exact &&
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
            expected_retained_failed_generator_source_sha256 =
                EXPECTED_RETAINED_FAILED_GENERATOR_SHA256,
            result_artifact = relpath(parsed.result, ROOT),
            result_artifact_sha256 = file_sha256(parsed.result),
            result_schema = RESULT_SCHEMA,
            execution_refinement_snapshot =
                relpath(lineage.snapshot_path, ROOT),
            execution_refinement_snapshot_schema = REFINEMENT_SCHEMA,
            execution_refinement_snapshot_sha256 =
                lineage.snapshot_sha256,
            expected_execution_refinement_snapshot_sha256 =
                EXPECTED_EXECUTION_SNAPSHOT_SHA256,
            execution_refinement_snapshot_sha256_matches_pinned =
                lineage.snapshot_sha256_matches_pinned,
            execution_source_rows = lineage.source_rows,
            all_execution_source_artifacts_present_exact =
                lineage.all_source_artifacts_present_exact,
            execution_seed_registry_exact = lineage.seed_registry_exact,
            expected_truth_sha256 = lineage.expected_truth_sha256,
            baseline_truth_sha256 = lineage.baseline_truth_sha256,
            fixed_truth_source_lineage_exact =
                lineage.fixed_truth_source_lineage_exact,
            expected_project_toml_sha256 =
                lineage.project_toml_sha256,
            expected_manifest_toml_sha256 =
                lineage.manifest_toml_sha256,
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
            n_expected_retained_attempts = EXPECTED_RETAINED_ATTEMPTS,
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
            execution_refinement_snapshot_sha256 =
                lineage.snapshot_sha256,
            execution_refinement_snapshot_sha256_matches_pinned =
                lineage.snapshot_sha256_matches_pinned,
            all_execution_source_artifacts_present_exact =
                lineage.all_source_artifacts_present_exact,
            execution_seed_registry_exact = lineage.seed_registry_exact,
            fixed_truth_source_lineage_exact =
                lineage.fixed_truth_source_lineage_exact,
            all_retained_refinement_lineage_exact,
            all_retained_job_design_identity_exact,
            all_retained_truth_lineage_exact,
            all_retained_source_input_lineage_exact,
            all_retained_seed_registry_lineage_exact,
            all_retained_project_toml_lineage_exact,
            all_retained_manifest_toml_lineage_exact,
            all_retained_environment_input_lineage_exact,
            all_retained_generator_lineage_accepted,
            retained_failed_generator_exception_exact,
            n_retained_failed_generator_exceptions =
                length(retained_failed_generator_exception_rows),
            all_retained_execution_input_lineage_exact,
            n_execution_input_lineage_failures,
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
