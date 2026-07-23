#!/usr/bin/env julia

include(joinpath(@__DIR__,
    "generate_mgmfrm_tam_direct_agreement_multireplication.jl"))

const DIRECT_MULTIREP_AGGREGATE_REFINEMENT_SNAPSHOT = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_tam_direct_agreement_policy_refinement_execution_snapshot.json")
const DIRECT_MULTIREP_AGGREGATE_REFINEMENT_SNAPSHOT_SHA256 =
    "03fe1a903d4fd218b5ab3e5ad51f5133ec1d8f274fafcea0bf8ac330876d8f4e"
const DIRECT_MULTIREP_AGGREGATE_REFINEMENT_SNAPSHOT_BYTES = 51_684
const DIRECT_MULTIREP_EXECUTION_GENERATOR = joinpath(
    ROOT, "scripts",
    "generate_mgmfrm_tam_direct_agreement_multireplication.jl")
const DIRECT_MULTIREP_EXECUTION_GENERATOR_SHA256 =
    "09df8a5138d40e533ed3f8c7fbf85e2fe885e645cf758e16628ac4516800caae"

function direct_multirep_aggregate_usage()
    return """
    Aggregate the 10 selected package-versus-TAM jobs without running MCMC.

    The refinement input defaults to the byte-exact policy snapshot used by
    the selected executions. Before writing the output, this wrapper validates
    the selected jobs' input, seed, generator, Project.toml, and Manifest.toml
    lineage and then adds aggregate-only provenance to the legacy result.

    Usage:
      julia --project=. scripts/generate_mgmfrm_tam_direct_agreement_multireplication_aggregate.jl [options]

    Options:
      --aggregate-only            Accepted for compatibility; always enabled.
      --baseline PATH
      --policy PATH
      --refinement PATH           Must match the execution snapshot byte-for-byte.
      --recovery-policy PATH
      --raw-root PATH
      --output PATH               Defaults to the legacy aggregate output.
      --progress                  Accepted for compatibility; no sampler is run.
    """
end

function direct_multirep_aggregate_parse_args(args)
    if any(arg -> arg in ("-h", "--help"), args)
        println(direct_multirep_aggregate_usage())
        exit(0)
    end
    any(==("--job"), args) &&
        error("--job is unavailable: this wrapper is aggregate-only and never runs MCMC")
    any(==("--infrastructure-retry"), args) &&
        error("--infrastructure-retry is unavailable in aggregate-only mode")
    parsed = direct_multirep_parse_args(vcat(
        ["--aggregate-only", "--refinement",
            DIRECT_MULTIREP_AGGREGATE_REFINEMENT_SNAPSHOT],
        collect(args)))
    parsed.aggregate_only || error("aggregate-only mode must remain enabled")
    parsed.job === nothing || error("aggregate-only mode cannot select a job")
    return parsed
end

function direct_multirep_aggregate_require(condition::Bool,
        message::AbstractString)
    condition || error("selected-job lineage validation failed: $message")
    return nothing
end

function direct_multirep_aggregate_resolve_root_path(path::AbstractString)
    return normpath(isabspath(path) ? path : joinpath(ROOT, path))
end

function direct_multirep_aggregate_expected_seeds(refinement)
    expected_pairs = Set((n_persons, replication)
        for n_persons in DIRECT_MULTIREP_PERSON_COUNTS
        for replication in 1:DIRECT_MULTIREP_REPLICATIONS)
    rows = refinement[:data_and_input_contract][:seed_registry_rows]
    direct_multirep_aggregate_require(length(rows) == length(expected_pairs),
        "execution snapshot must contain exactly 10 seed rows")
    seeds = Dict{Tuple{Int,Int},NamedTuple}()
    for row in rows
        key = (as_int(row[:n_persons]), as_int(row[:replication]))
        direct_multirep_aggregate_require(key in expected_pairs,
            "unexpected seed-registry key $(key)")
        direct_multirep_aggregate_require(!haskey(seeds, key),
            "duplicate seed-registry key $(key)")
        seeds[key] = (;
            ability_seed = as_int(row[:ability_seed]),
            response_seed = as_int(row[:response_seed]),
            package_fit_seed = as_int(row[:package_fit_seed]),
        )
    end
    direct_multirep_aggregate_require(Set(keys(seeds)) == expected_pairs,
        "seed registry does not cover the 10 scheduled jobs")
    return seeds
end

function direct_multirep_aggregate_validate_inputs(parsed)
    snapshot = parsed.refinement
    direct_multirep_aggregate_require(isfile(snapshot),
        "execution refinement snapshot is missing")
    direct_multirep_aggregate_require(
        filesize(snapshot) ==
            DIRECT_MULTIREP_AGGREGATE_REFINEMENT_SNAPSHOT_BYTES,
        "execution refinement snapshot byte count changed")
    direct_multirep_aggregate_require(
        file_sha256(snapshot) ==
            DIRECT_MULTIREP_AGGREGATE_REFINEMENT_SNAPSHOT_SHA256,
        "execution refinement snapshot SHA-256 changed")
    direct_multirep_aggregate_require(
        file_sha256(DIRECT_MULTIREP_EXECUTION_GENERATOR) ==
            DIRECT_MULTIREP_EXECUTION_GENERATOR_SHA256,
        "execution generator SHA-256 changed")

    refinement = direct_multirep_checked_artifact(
        snapshot, DIRECT_MULTIREP_REFINEMENT_SCHEMA)
    direct_multirep_aggregate_require(
        as_bool(refinement[:summary][:frozen_primary_gate_unchanged]),
        "snapshot does not preserve the frozen primary gate")
    direct_multirep_aggregate_require(
        !as_bool(refinement[:summary][
            :direct_multireplication_execution_completed]),
        "snapshot must remain the pre-execution refinement record")

    input_rows = (
        (label = "baseline", path = parsed.baseline,
            expected = as_string(refinement[:source_artifacts][
                :baseline_sha256])),
        (label = "frozen policy", path = parsed.policy,
            expected = as_string(refinement[:source_artifacts][
                :frozen_policy_sha256])),
        (label = "recovery policy", path = parsed.recovery_policy,
            expected = as_string(refinement[:source_artifacts][
                :recovery_policy_sha256])),
    )
    for row in input_rows
        direct_multirep_aggregate_require(isfile(row.path),
            "$(row.label) artifact is missing")
        direct_multirep_aggregate_require(file_sha256(row.path) == row.expected,
            "$(row.label) artifact SHA-256 does not match the execution snapshot")
    end

    environment = refinement[:environment_contract]
    expected_environment = (;
        project_toml_sha256 = as_string(environment[:project_toml_sha256]),
        manifest_toml_sha256 = as_string(environment[:manifest_toml_sha256]),
    )
    seeds = direct_multirep_aggregate_expected_seeds(refinement)
    expected_inputs = (;
        refinement_sha256 =
            DIRECT_MULTIREP_AGGREGATE_REFINEMENT_SNAPSHOT_SHA256,
        baseline_sha256 = file_sha256(parsed.baseline),
        frozen_policy_sha256 = file_sha256(parsed.policy),
        recovery_policy_sha256 = file_sha256(parsed.recovery_policy),
        truth_sha256 = as_string(
            refinement[:data_and_input_contract][:fixed_truth_sha256]),
    )
    return (; refinement, expected_environment, seeds, expected_inputs)
end

function direct_multirep_aggregate_manifest_file(job, filename::String,
        expected_path::AbstractString, expected_sha256::AbstractString)
    rows = [row for row in job[:raw_file_manifest_rows]
        if basename(as_string(row[:path])) == filename]
    direct_multirep_aggregate_require(length(rows) == 1,
        "$(as_string(job[:job_id])) must record exactly one $filename")
    row = only(rows)
    recorded_path = direct_multirep_aggregate_resolve_root_path(
        as_string(row[:path]))
    direct_multirep_aggregate_require(recorded_path == normpath(expected_path),
        "$(as_string(job[:job_id])) $filename path does not identify the selected attempt")
    direct_multirep_aggregate_require(isfile(recorded_path),
        "$(as_string(job[:job_id])) $filename is missing")
    actual_bytes = filesize(recorded_path)
    actual_sha256 = file_sha256(recorded_path)
    direct_multirep_aggregate_require(actual_bytes == as_int(row[:bytes]),
        "$(as_string(job[:job_id])) $filename byte count differs from its raw manifest")
    direct_multirep_aggregate_require(actual_sha256 == as_string(row[:sha256]),
        "$(as_string(job[:job_id])) $filename SHA-256 differs from its raw manifest")
    direct_multirep_aggregate_require(actual_sha256 == expected_sha256,
        "$(as_string(job[:job_id])) $filename SHA-256 differs from the execution snapshot")
    return (;
        path = relpath(recorded_path, ROOT),
        bytes = actual_bytes,
        sha256 = actual_sha256,
    )
end

function direct_multirep_aggregate_validate_jobs(artifact, parsed, expected)
    jobs = artifact.replication_rows
    pointers = artifact.selected_attempt_rows
    direct_multirep_aggregate_require(length(jobs) == 10,
        "aggregate must contain exactly 10 selected jobs")
    direct_multirep_aggregate_require(length(pointers) == 10,
        "aggregate must contain exactly 10 selected-attempt pointers")

    expected_pairs = Set((n_persons, replication)
        for n_persons in DIRECT_MULTIREP_PERSON_COUNTS
        for replication in 1:DIRECT_MULTIREP_REPLICATIONS)
    pointer_map = Dict{String,Any}()
    for pointer in pointers
        job_id = as_string(pointer.job_id)
        direct_multirep_aggregate_require(!haskey(pointer_map, job_id),
            "duplicate selected-attempt pointer for $job_id")
        pointer_map[job_id] = pointer
    end

    protocol = artifact.protocol
    direct_multirep_aggregate_require(
        as_string(protocol.generator) == relpath(
            DIRECT_MULTIREP_EXECUTION_GENERATOR, ROOT),
        "legacy protocol generator path changed")
    direct_multirep_aggregate_require(
        as_string(protocol.generator_source_sha256) ==
            DIRECT_MULTIREP_EXECUTION_GENERATOR_SHA256,
        "legacy protocol generator SHA-256 changed")
    direct_multirep_aggregate_require(
        as_string(protocol.refinement_artifact_sha256) ==
            expected.expected_inputs.refinement_sha256,
        "aggregate refinement SHA-256 does not identify the execution snapshot")
    for (protocol_field, input_field) in (
            (:baseline_artifact_sha256, :baseline_sha256),
            (:frozen_policy_artifact_sha256, :frozen_policy_sha256),
            (:recovery_policy_artifact_sha256, :recovery_policy_sha256))
        direct_multirep_aggregate_require(
            as_string(protocol[protocol_field]) ==
                getproperty(expected.expected_inputs, input_field),
            "aggregate $(protocol_field) lineage mismatch")
    end

    lineage_rows = NamedTuple[]
    observed_pairs = Set{Tuple{Int,Int}}()
    for job in jobs
        n_persons = as_int(job[:n_persons])
        replication = as_int(job[:replication])
        key = (n_persons, replication)
        direct_multirep_aggregate_require(key in expected_pairs,
            "unexpected selected job key $(key)")
        direct_multirep_aggregate_require(!(key in observed_pairs),
            "duplicate selected job key $(key)")
        push!(observed_pairs, key)
        job_id = direct_multirep_job_id(n_persons, replication)
        direct_multirep_aggregate_require(as_string(job[:job_id]) == job_id,
            "job identity does not match N/replication for $job_id")
        direct_multirep_aggregate_require(as_bool(job[:execution_completed]),
            "$job_id is not a completed selected execution")
        direct_multirep_aggregate_require(haskey(pointer_map, job_id),
            "selected-attempt pointer is missing for $job_id")

        pointer = pointer_map[job_id]
        selected_attempt = as_int(pointer.selected_attempt)
        direct_multirep_aggregate_require(
            selected_attempt == as_int(job[:attempt]),
            "$job_id selected attempt differs from the job record")
        pointer_path = direct_multirep_aggregate_resolve_root_path(
            as_string(pointer.pointer_path))
        expected_pointer_path = direct_multirep_selected_path(
            parsed.raw_root, n_persons, replication)
        direct_multirep_aggregate_require(
            pointer_path == normpath(expected_pointer_path),
            "$job_id selected-attempt pointer path is misplaced")
        direct_multirep_aggregate_require(isfile(pointer_path),
            "$job_id selected-attempt pointer is missing")
        direct_multirep_aggregate_require(
            file_sha256(pointer_path) == as_string(pointer.pointer_sha256),
            "$job_id selected-attempt pointer SHA-256 changed")
        pointer_artifact = load_json(pointer_path)
        direct_multirep_aggregate_require(
            as_string(pointer_artifact[:schema]) ==
                "bayesianmgmfrm.mgmfrm_tam_direct_agreement_selected_attempt.v1",
            "$job_id selected-attempt pointer schema changed")
        direct_multirep_aggregate_require(
            as_string(pointer_artifact[:job_id]) == job_id &&
            as_int(pointer_artifact[:selected_attempt]) == selected_attempt,
            "$job_id selected-attempt pointer identity changed")
        expected_directory = joinpath(direct_multirep_job_root(
            parsed.raw_root, n_persons, replication),
            @sprintf("attempt_%02d", selected_attempt))
        result_path = direct_multirep_aggregate_resolve_root_path(
            as_string(pointer.result_path))
        direct_multirep_aggregate_require(
            result_path == normpath(joinpath(expected_directory,
                "job_result.json")),
            "$job_id result path is outside its selected attempt")
        direct_multirep_aggregate_require(isfile(result_path),
            "$job_id result file is missing")
        direct_multirep_aggregate_require(
            file_sha256(result_path) == as_string(pointer.result_sha256),
            "$job_id result SHA-256 differs from the selected pointer")
        direct_multirep_aggregate_require(
            direct_multirep_aggregate_resolve_root_path(as_string(
                pointer_artifact[:selected_job_result])) == result_path &&
            as_string(pointer_artifact[:selected_job_result_sha256]) ==
                as_string(pointer.result_sha256),
            "$job_id selected-attempt pointer result lineage changed")

        job_protocol = job[:protocol]
        direct_multirep_aggregate_require(
            as_string(job_protocol[:generator]) == relpath(
                DIRECT_MULTIREP_EXECUTION_GENERATOR, ROOT),
            "$job_id execution generator path changed")
        direct_multirep_aggregate_require(
            as_string(job_protocol[:generator_source_sha256]) ==
                DIRECT_MULTIREP_EXECUTION_GENERATOR_SHA256,
            "$job_id execution generator SHA-256 changed")
        for field in (:refinement_sha256, :baseline_sha256,
                :frozen_policy_sha256, :recovery_policy_sha256,
                :truth_sha256)
            direct_multirep_aggregate_require(
                as_string(job_protocol[field]) ==
                    getproperty(expected.expected_inputs, field),
                "$job_id $(field) lineage mismatch")
        end
        seed = expected.seeds[key]
        for field in (:ability_seed, :response_seed, :package_fit_seed)
            direct_multirep_aggregate_require(
                as_int(job_protocol[field]) == getproperty(seed, field),
                "$job_id $(field) lineage mismatch")
        end

        project = direct_multirep_aggregate_manifest_file(
            job, "Project.toml", joinpath(expected_directory, "Project.toml"),
            expected.expected_environment.project_toml_sha256)
        manifest = direct_multirep_aggregate_manifest_file(
            job, "Manifest.toml", joinpath(expected_directory, "Manifest.toml"),
            expected.expected_environment.manifest_toml_sha256)
        push!(lineage_rows, (;
            job_id = Symbol(job_id),
            n_persons,
            replication,
            selected_attempt,
            selected_attempt_pointer_path = relpath(pointer_path, ROOT),
            selected_attempt_pointer_sha256 = file_sha256(pointer_path),
            result_path = relpath(result_path, ROOT),
            result_sha256 = file_sha256(result_path),
            execution_generator_source_sha256 =
                as_string(job_protocol[:generator_source_sha256]),
            refinement_snapshot_sha256 =
                as_string(job_protocol[:refinement_sha256]),
            baseline_sha256 = as_string(job_protocol[:baseline_sha256]),
            frozen_policy_sha256 =
                as_string(job_protocol[:frozen_policy_sha256]),
            recovery_policy_sha256 =
                as_string(job_protocol[:recovery_policy_sha256]),
            truth_sha256 = as_string(job_protocol[:truth_sha256]),
            ability_seed = as_int(job_protocol[:ability_seed]),
            response_seed = as_int(job_protocol[:response_seed]),
            package_fit_seed = as_int(job_protocol[:package_fit_seed]),
            project_toml = project,
            manifest_toml = manifest,
            passed = true,
        ))
    end
    direct_multirep_aggregate_require(observed_pairs == expected_pairs,
        "selected jobs do not cover the 10 scheduled N/replication cells")
    return sort(lineage_rows; by = row -> (row.n_persons, row.replication))
end

function direct_multirep_aggregate_overlay(artifact, parsed, expected,
        lineage_rows)
    original_generator = as_string(artifact.protocol.generator)
    original_generator_sha256 =
        as_string(artifact.protocol.generator_source_sha256)
    aggregation_generator = relpath(@__FILE__, ROOT)
    aggregation_generator_sha256 = file_sha256(@__FILE__)
    provenance = (;
        mode = :aggregate_only_from_selected_attempts,
        mcmc_executed = false,
        generator = aggregation_generator,
        generator_source_sha256 = aggregation_generator_sha256,
        wrapped_execution_generator = original_generator,
        wrapped_execution_generator_source_sha256 =
            original_generator_sha256,
        protocol_generator_fields_preserved =
            original_generator == relpath(
                DIRECT_MULTIREP_EXECUTION_GENERATOR, ROOT) &&
            original_generator_sha256 ==
                DIRECT_MULTIREP_EXECUTION_GENERATOR_SHA256,
        refinement_execution_snapshot = relpath(parsed.refinement, ROOT),
        refinement_execution_snapshot_bytes = filesize(parsed.refinement),
        refinement_execution_snapshot_sha256 = file_sha256(parsed.refinement),
        expected_project_toml_sha256 =
            expected.expected_environment.project_toml_sha256,
        expected_manifest_toml_sha256 =
            expected.expected_environment.manifest_toml_sha256,
        fail_closed = true,
        n_selected_jobs_expected = 10,
        n_selected_jobs_validated = length(lineage_rows),
        all_selected_job_lineage_valid =
            length(lineage_rows) == 10 && all(row -> row.passed, lineage_rows),
        selected_job_lineage_rows = lineage_rows,
    )
    direct_multirep_aggregate_require(
        provenance.protocol_generator_fields_preserved,
        "legacy protocol generator fields were not preserved")
    direct_multirep_aggregate_require(
        provenance.all_selected_job_lineage_valid,
        "not all selected-job lineage rows passed")

    policy_integrity = merge(artifact.policy_integrity, (;
        execution_refinement_snapshot_validated = true,
        selected_job_input_lineage_validated = true,
        selected_job_seed_lineage_validated = true,
        selected_job_environment_lineage_validated = true,
    ))
    summary = merge(artifact.summary, (;
        aggregate_only = true,
        mcmc_executed = false,
        selected_job_lineage_validation_passed = true,
        n_selected_job_lineage_rows = length(lineage_rows),
    ))
    return merge(artifact, (;
        aggregation_provenance = provenance,
        policy_integrity,
        summary,
    ))
end

function direct_multirep_aggregate_main(args)
    parsed = direct_multirep_aggregate_parse_args(args)
    expected = direct_multirep_aggregate_validate_inputs(parsed)
    artifact = mktempdir() do directory
        legacy_output = joinpath(directory, "legacy_aggregate.json")
        legacy_parsed = merge(parsed, (; output = legacy_output))
        direct_multirep_aggregate(legacy_parsed)
    end
    lineage_rows = direct_multirep_aggregate_validate_jobs(
        artifact, parsed, expected)
    overlaid = direct_multirep_aggregate_overlay(
        artifact, parsed, expected, lineage_rows)
    write_artifact(parsed.output, overlaid)
    println("wrote ", relpath(parsed.output, ROOT))
    println("aggregate_only=true mcmc_executed=false lineage_validated=",
        overlaid.summary.n_selected_job_lineage_rows,
        " protocol_generator_sha256=",
        overlaid.protocol.generator_source_sha256,
        " aggregation_generator_sha256=",
        overlaid.aggregation_provenance.generator_source_sha256)
    return overlaid
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) &&
    direct_multirep_aggregate_main(ARGS)
