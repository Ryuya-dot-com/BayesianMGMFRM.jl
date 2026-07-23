#!/usr/bin/env julia

const LD1B1_HARNESS_GENERATOR_PATH =
    "scripts/generate_local_dependence_pilot_batch_execution_harness.jl"

include(joinpath(@__DIR__,
    "run_local_dependence_calibration_pilot_batch.jl"))

const LD1B1_HARNESS_OUTPUT = joinpath(
    LD1B1_ROOT,
    "test",
    "fixtures",
    "local_dependence_pilot_batch_execution_harness.json",
)

function ld1b1_harness_generator_usage()
    return """
    Generate the deterministic, MCMC-free LD1b1 batch execution harness.

    The tracked artifact records all 660 dry-run command and path rows without
    scanning or materializing attempt directories, checkpoints, response data,
    fits, or MCMC output.

    Usage:
      julia --project=. scripts/generate_local_dependence_pilot_batch_execution_harness.jl [--output PATH]
    """
end

function ld1b1_harness_generator_parse_args(args)
    output = LD1B1_HARNESS_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(ld1b1_harness_generator_usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return output
end

function ld1b1_portable_harness_command(command::AbstractString)
    portable = replace(
        String(command),
        ld1b1_shell_quote(ld1b1_julia_executable()) =>
            ld1b1_shell_quote("julia"),
    )
    portable = replace(portable, string(LD1B1_ROOT, Base.Filesystem.path_separator) => "")
    portable = replace(portable, LD1B1_ROOT => ".")
    occursin(LD1B1_ROOT, portable) &&
        error("portable harness command retains the repository absolute path")
    return portable
end

function ld1b1_without_content_hash(artifact::NamedTuple)
    names = Tuple(name for name in keys(artifact) if name !== :content_hash)
    return NamedTuple{names}(Tuple(getproperty(artifact, name) for name in names))
end

function ld1b1_portable_harness(artifact::NamedTuple)
    command_rows = Tuple(merge(row, (;
        command = ld1b1_portable_harness_command(row.command),
    )) for row in artifact.command_rows)
    base = merge(
        ld1b1_without_content_hash(artifact),
        (; command_rows),
    )
    return ld1b1_with_content_hash(base)
end

function ld1b1_assert_tracked_harness(value, path::String = "artifact")
    if value isa NamedTuple || value isa AbstractDict
        for (key, element) in pairs(value)
            name = String(key)
            lowered = lowercase(name)
            name in ("generated_at", "started_at", "finished_at", "timestamp",
                "internal", "local_only", "next_gate") &&
                error("tracked harness contains prohibited field $path.$name")
            occursin(r"internal|local[_-]?only|public[_-]?claim|next[_-]?gate|private|worklog|todo",
                lowered) &&
                error("tracked harness contains prohibited field $path.$name")
            ld1b1_assert_tracked_harness(element, string(path, ".", name))
        end
    elseif value isa AbstractArray || value isa Tuple
        for (index, element) in pairs(value)
            ld1b1_assert_tracked_harness(element, string(path, "[", index, "]"))
        end
    elseif value isa AbstractString
        text = String(value)
        isabspath(text) &&
            error("tracked harness contains an absolute path at $path")
        occursin(LD1B1_ROOT, text) &&
            error("tracked harness contains the repository absolute path at $path")
        occursin(r"(?:^|[='\"])/(?:[^'\" ]*)", text) &&
            error("tracked harness contains an absolute command path at $path")
        occursin(r"^[A-Za-z]:[\\/]", text) &&
            error("tracked harness contains a Windows absolute path at $path")
        startswith(text, "\\\\") &&
            error("tracked harness contains a UNC path at $path")
        occursin(r"(?i)\binternal(?:[-_ ]only)?\b|\blocal[-_ ]only\b|\bworklog\b|\bnext[-_ ]gate\b|\bprivate\b|\btodo\b",
            text) &&
            error("tracked harness contains nonpublic wording at $path")
    end
    return nothing
end

function ld1b1_harness_generator_main(args)
    output = ld1b1_harness_generator_parse_args(args)
    options = ld1b1_parse_args(["--mode", "dry-run", "--all"])
    generator_path = joinpath(LD1B1_ROOT, LD1B1_HARNESS_GENERATOR_PATH)
    batch_runner_path = joinpath(
        LD1B1_ROOT,
        "scripts",
        "run_local_dependence_calibration_pilot_batch.jl",
    )
    artifact = ld1b1_build_harness(
        options;
        scan_results = false,
        artifact_generator = (;
            path = LD1B1_HARNESS_GENERATOR_PATH,
            source_sha256 = ld1b1_file_sha256(generator_path),
            batch_runner_path =
                "scripts/run_local_dependence_calibration_pilot_batch.jl",
            batch_runner_source_sha256 =
                ld1b1_file_sha256(batch_runner_path),
        ),
    )
    artifact = ld1b1_portable_harness(artifact)
    ld1b1_assert_tracked_harness(artifact)
    ld1b1_atomic_write_artifact(output, artifact; overwrite = true)
    println("wrote ", ld1b1_record_path(output))
    println(
        "mode=", artifact.summary.mode,
        " jobs=", artifact.summary.n_plan_jobs,
        " commands=", length(artifact.command_rows),
        " fit=", artifact.summary.n_fit_jobs,
        " pre_fit_reject=", artifact.summary.n_pre_fit_rejection_jobs,
        " mcmc_run=", artifact.summary.mcmc_run,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) &&
    ld1b1_harness_generator_main(ARGS)
