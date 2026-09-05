#!/usr/bin/env julia

# Build the package candidate from Git-visible worktree files, then verify the
# result from a temporary directory that has no repository metadata or ignored
# local artifacts. Git is used only to select the candidate files; every package
# operation below runs against the copied tree.

using Printf

const ROOT = abspath(normpath(joinpath(@__DIR__, "..")))
const JULIA = joinpath(Sys.BINDIR, Base.julia_exename())

const STEP_BUDGET_SECONDS = (
    assemble = 30.0,
    instantiate = 600.0,
    first_load = 300.0,
    warm_load = 120.0,
    minimal_fit = 300.0,
    docs = 600.0,
)

function candidate_paths()
    command = Cmd(`git ls-files -co --exclude-standard -z`; dir = ROOT)
    paths = sort!(filter(!isempty, split(String(read(command)), '\0')))
    isempty(paths) && error("distribution candidate contains no files")
    for path in paths
        isabspath(path) && error("distribution path is absolute: $path")
        normalized = normpath(path)
        first(splitpath(normalized)) == ".." &&
            error("distribution path escapes the repository: $path")
    end
    return unique(paths)
end

function copy_candidate(paths, destination::AbstractString)
    for relative in paths
        source = joinpath(ROOT, relative)
        target = joinpath(destination, relative)
        mkpath(dirname(target))
        if islink(source)
            symlink(readlink(source), target)
        else
            cp(source, target)
        end
    end
    return nothing
end

function assert_clean_candidate(paths, destination::AbstractString)
    forbidden = (
        ".git",
        ".DS_Store",
        "Manifest.toml",
        joinpath("docs", "Manifest.toml"),
        joinpath("docs", "build"),
        "artifacts",
        "results",
    )
    for relative in forbidden
        !ispath(joinpath(destination, relative)) ||
            error("distribution candidate contains ignored/local path: $relative")
    end

    private_markers = unique(filter(!isempty, (ROOT, homedir())))
    private_hits = String[]
    for relative in paths
        path = joinpath(destination, relative)
        isfile(path) || continue
        bytes = read(path)
        isvalid(String, bytes) || continue
        text = String(bytes)
        any(marker -> occursin(marker, text), private_markers) &&
            push!(private_hits, relative)
    end
    isempty(private_hits) || error(
        "distribution candidate contains current-machine private paths: " *
        join(private_hits, ", "),
    )
    return nothing
end

function smoke_environment()
    environment = Dict{String,String}()
    for key in (
            "HOME",
            "HTTP_PROXY",
            "HTTPS_PROXY",
            "JULIA_DEPOT_PATH",
            "JULIA_PKG_SERVER",
            "JULIA_SSL_CA_ROOTS_PATH",
            "LANG",
            "LC_ALL",
            "LC_CTYPE",
            "LOGNAME",
            "NO_PROXY",
            "SSL_CERT_DIR",
            "SSL_CERT_FILE",
            "TEMP",
            "TMP",
            "TMPDIR",
            "USER",
        )
        haskey(ENV, key) && (environment[key] = ENV[key])
    end
    environment["BAYESIANMGMFRM_RESEARCH_EVIDENCE_TESTS"] = "false"
    environment["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
    environment["OPENBLAS_NUM_THREADS"] = "1"
    # Use an absolute Julia executable and hide optional command-line backends.
    environment["PATH"] = Sys.BINDIR
    return environment
end

function run_budgeted(label::AbstractString,
        budget_seconds::Real,
        command::Cmd;
        directory::AbstractString,
        environment)
    started = time_ns()
    failure = nothing
    try
        run(setenv(Cmd(command; dir = directory), environment))
    catch err
        failure = err
    end
    elapsed = (time_ns() - started) / 1e9
    @printf("distribution smoke: %-12s %8.3f s (budget %.0f s)\n",
        label, elapsed, budget_seconds)
    failure === nothing || error(
        "$label failed in the clean distribution candidate; " *
        "see the subprocess output above",
    )
    elapsed <= budget_seconds || error(
        "$label exceeded its distribution budget: " *
        "$(round(elapsed; digits = 3)) s > $budget_seconds s",
    )
    return elapsed
end

function main()
    paths = candidate_paths()
    total_bytes = sum(paths) do path
        source = joinpath(ROOT, path)
        return isfile(source) ? filesize(source) : 0
    end
    environment = smoke_environment()

    timings = mktempdir() do parent
        candidate = joinpath(parent, "BayesianMGMFRM.jl")
        mkpath(candidate)

        assembly_started = time_ns()
        copy_candidate(paths, candidate)
        assert_clean_candidate(paths, candidate)
        assembly_elapsed = (time_ns() - assembly_started) / 1e9
        assembly_elapsed <= STEP_BUDGET_SECONDS.assemble || error(
            "candidate assembly exceeded its distribution budget: " *
            "$(round(assembly_elapsed; digits = 3)) s > " *
            "$(STEP_BUDGET_SECONDS.assemble) s",
        )
        @printf("distribution smoke: %-12s %8.3f s (budget %.0f s)\n",
            "assemble", assembly_elapsed, STEP_BUDGET_SECONDS.assemble)

        instantiate = run_budgeted(
            "instantiate",
            STEP_BUDGET_SECONDS.instantiate,
            `$JULIA --startup-file=no --project=. -e "using Pkg; Pkg.instantiate()"`;
            directory = candidate,
            environment,
        )
        first_load = run_budgeted(
            "first load",
            STEP_BUDGET_SECONDS.first_load,
            `$JULIA --startup-file=no --project=. -e "using BayesianMGMFRM"`;
            directory = candidate,
            environment,
        )
        warm_load = run_budgeted(
            "warm load",
            STEP_BUDGET_SECONDS.warm_load,
            `$JULIA --startup-file=no --project=. -e "using BayesianMGMFRM"`;
            directory = candidate,
            environment,
        )
        minimal_fit = run_budgeted(
            "minimal fit",
            STEP_BUDGET_SECONDS.minimal_fit,
            `$JULIA --startup-file=no --project=. scripts/platform_smoke.jl`;
            directory = candidate,
            environment,
        )
        docs = run_budgeted(
            "docs",
            STEP_BUDGET_SECONDS.docs,
            `$JULIA --startup-file=no --project=docs docs/build.jl`;
            directory = candidate,
            environment,
        )
        return (;
            assemble = assembly_elapsed,
            instantiate,
            first_load,
            warm_load,
            minimal_fit,
            docs,
        )
    end

    println(
        "Clean distribution candidate passed: ",
        length(paths),
        " files, ",
        total_bytes,
        " bytes; no Git metadata, ignored artifacts, current-machine paths, ",
        "optional research results, CmdStan environment, or R environment ",
        "required.",
    )
    return timings
end

main()
