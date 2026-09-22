"""
Manual regression for CmdStan cache containment, invocation and output handoff, NOT acceptance
of reusable binaries or scientific execution. Run directly with Julia.
Only owned temporary fixtures are changed. The BayesianMGMFRM package is not
loaded; no sampler, compiler, stanc, or cached model is launched. Re-audit changed source before rerunning:
the isolated command guard is not an OS sandbox.
"""
module CmdStanCacheIdentityProbe

using Test, SHA, Random

const source_root = normpath(joinpath(@__DIR__, "..", "src"))
include(joinpath(source_root, "cmdstan_backend.jl")) # Definitions only; no discovery call.
const selected = Symbol[]
const wanted = (:_cmdstan_failure_reason, :_cmdstan_cache_root,
    :_cmdstan_executable_path, :_cmdstan_executable_sha256, :_cmdstan_compile_model,
    :_cmdstan_chain_seeds, :_cmdstan_sample_command, :_cmdstan_sample_chains)
Base.include(@__MODULE__, joinpath(source_root, "cmdstan_fit.jl")) do expression
    signature = expression isa Expr && expression.head === :function ? expression.args[1] : nothing
    name = signature isa Expr && signature.head === :call ? signature.args[1] : nothing
    if name in wanted
        push!(selected, name)
        return expression # Unmodified function body; skip imports and all other definitions.
    end
    return nothing
end
@assert Tuple(selected) == wanted

# ponytail: isolated helper rejection only; public-fit integration needs a separately authorized check.
# Explicit seams: fixed source lookup, command/JSON traps, and a no-draw RNG.
_cmdstan_model_source(family) = joinpath(source_root, "stan", string(family) * ".stan")
struct BuildRequested <: Exception end
const requests = NamedTuple[]
const environment_names = ("MAKEFILES", "MAKEFLAGS", "GNUMAKEFLAGS", "MAKE",
    "CXX", "PATH", "STAN_THREADS", "SDKROOT")
function _cmdstan_run(command::Cmd, stage::Symbol; kwargs...)
    @test command.env === nothing # Inheritance, not a silently sanitized child environment.
    push!(requests, (; stage, argv = collect(command), directory = command.dir,
        environment = map(name -> get(ENV, name, nothing), environment_names)))
    throw(BuildRequested())
end
struct SeedRequested <: Exception end
mutable struct NoDrawRNG <: AbstractRNG
    requests::Int
end
function Random.rand(rng::NoDrawRNG, ::Type{UInt32})
    rng.requests += 1
    throw(SeedRequested()) # Never produce a seed, even on the matching-evidence path.
end
_cmdstan_write_json(args...) = error("unexpected JSON write in no-draw probe")

function main()
    Sys.isunix() || error("this permission/fixture probe is scoped to local POSIX filesystems")
    watched = [joinpath(source_root, name) for name in ("cmdstan_backend.jl", "cmdstan_fit.jl")]
    append!(watched, [_cmdstan_model_source(family) for family in (:mfrm, :gmfrm, :mgmfrm)])
    digest(path) = bytes2hex(sha256(read(path)))
    function snapshot(path)
        islink(path) && return (:link, readlink(path))
        isfile(path) && return (:file, read(path), stat(path).mode, mtime(path))
        isdir(path) && return (:directory,
            [(name, snapshot(joinpath(path, name))) for name in readdir(path)])
        return (:absent,)
    end
    before = Dict(path => digest(path) for path in watched)
    inherited_before = map(name -> get(ENV, name, nothing), environment_names)
    empty!(requests)
    println("Julia ", VERSION, "; cache containment and output handoff only; no external execution")
    @testset "CmdStan cache containment and output handoff (guarded source probe)" begin
        mktempdir() do temporary
            root_a, root_b = [mkpath(joinpath(temporary, name)) for name in ("toolchain-a", "toolchain-b")]
            make_a, make_b, cxx_a, cxx_b = [joinpath(temporary, name) for name in
                ("make-a", "make-b", "cxx-a", "cxx-b")]
            make_spaced = joinpath(mkpath(joinpath(temporary, "tools with spaces")), "make fixture")
            for path in (make_a, make_b, cxx_a, cxx_b, make_spaced)
                write(path, "fixture only: must never be executed\n")
                chmod(path, 0o700) # Let Sys.which discover this fixture, never run it.
            end
            write(joinpath(root_a, "makefile"), "# selected Makefile fixture\n")
            write(joinpath(root_a, "GNUmakefile"), "# competing Makefile fixture\n")
            local_make = joinpath(mkpath(joinpath(root_a, "make")), "local")
            stanc = joinpath(mkpath(joinpath(root_a, "bin")), "stanc")
            write(local_make, "STAN_THREADS=false\n")
            write(stanc, "stanc fixture A\n")
            check_a = (; cmdstan_root = root_a, cmdstan_version = "probe-same-version",
                cmdstan_root_basename = basename(root_a))
            check_b = merge(check_a, (; cmdstan_root = root_b, cmdstan_root_basename = basename(root_b)))
            @test _cmdstan_cache_root(check_a, nothing) == _cmdstan_cache_root(check_b, nothing)
            # Never write to that shared default path; every call gets our private directory.
            missing_make = joinpath(temporary, "missing-make")
            invalid_make = (make_a * " -n", make_a * " -j2", make_a * " --file=GNUmakefile",
                make_a * "\t-n", make_a * "\n-n", "\"" * make_spaced * "\"", missing_make)
            for selection in (nothing, " \t ")
                withenv("MAKE" => selection) do
                    @test _cmdstan_configured_program("MAKE", (missing_make, make_a)) == make_a
                end
            end
            withenv("MAKE" => basename(make_a), "PATH" => temporary) do
                @test _cmdstan_configured_program("MAKE", (missing_make,)) == make_a
            end
            for selection in invalid_make
                withenv("MAKE" => selection) do
                    @test _cmdstan_configured_program("MAKE", (make_a,)) === nothing
                end
            end
            withenv("MAKE" => make_spaced, "CXX" => cxx_a * " -O2") do
                @test _cmdstan_configured_program("MAKE", (make_a,)) == make_spaced
                @test _cmdstan_configured_program("CXX", (cxx_b,)) == cxx_a
            end
            withenv("MAKE" => make_a, "CXX" => cxx_a, "STAN_THREADS" => "false",
                    "SDKROOT" => joinpath(temporary, "sdk fixture"),
                    "MAKEFILES" => nothing, "MAKEFLAGS" => nothing, "GNUMAKEFLAGS" => nothing) do
                @test _cmdstan_configured_program("MAKE", ("make",)) == make_a
                @test _cmdstan_configured_program("CXX", ("c++",)) == cxx_a
                for family in (:mfrm, :gmfrm, :mgmfrm)
                    function rejected(cache; check = check_a, reason = :cache_unverified,
                            variable = nothing, selected_family = family)
                        retained = snapshot(temporary)
                        environment = map(name -> get(ENV, name, nothing), environment_names)
                        count = length(requests)
                        result = try
                            _cmdstan_compile_model(check, selected_family; cache_dir = cache)
                        catch error
                            error
                        end
                        @test result isa CmdStanError && result.stage === :model_compile &&
                            result.reason === reason
                        if reason === :unsupported_make_environment
                            @test result isa CmdStanError && result.detail ==
                                "$variable must be unset or empty; inherited Make settings are unsupported"
                            @test !occursin("probe-private-environment-value", sprint(showerror, result))
                        else
                            guidance = reason === :cache_unverified ? "new empty cmdstan_cache_dir" :
                                reason === :runtime_unavailable ? "CmdStan root was not retained" :
                                reason === :model_source_missing ? "Stan source is unavailable" :
                                "MAKE must name one executable"
                            @test result isa CmdStanError && occursin(guidance, result.detail)
                        end
                        @test length(requests) == count
                        @test snapshot(temporary) == retained
                        @test map(name -> get(ENV, name, nothing), environment_names) == environment
                    end
                    cache = mkpath(joinpath(temporary, "cache-$(family)"))
                    stem = joinpath(cache, "bayesian_mgmfrm_" * string(family))
                    copied = stem * ".stan"
                    executable = _cmdstan_executable_path(stem)
                    cp(_cmdstan_model_source(family), copied)
                    write(executable, "model fixture A, not a binary\n")
                    chmod(executable, 0o700)
                    @test mtime(executable) >= mtime(copied)
                    @test stat(executable).mode & 0o111 != 0
                    first_digest = digest(executable)
                    empty_cache = mktempdir(temporary)
                    absent_cache = joinpath(temporary, "uncreated-$family")
                    linked_cache = joinpath(temporary, "environment-link-$family")
                    symlink(empty_cache, linked_cache)
                    make_names = environment_names[1:3]
                    flag_values = ("n", "-q", "-t", "-e", "-j2", " -j --jobserver-auth=3,4",
                        "--no-print-directory", "CXX=probe-private-environment-value",
                        "--unknown-probe-flag", " \t\n", "\u00a0")
                    for variable in make_names
                        values = variable == "MAKEFILES" ?
                            (local_make, absent_cache, local_make * " " * absent_cache,
                                "probe-private-environment-value", " \t\n", "\u00a0") : flag_values
                        for value in values
                            withenv(variable => value) do
                                for target in (absent_cache, empty_cache, cache, linked_cache)
                                    rejected(target; reason = :unsupported_make_environment, variable)
                                end
                            end
                            @test all(!haskey(ENV, name) for name in make_names)
                        end
                    end
                    for mask in 1:7
                        settings = ntuple(i -> make_names[i] =>
                            (mask & (1 << (i - 1)) != 0 ? "probe-private-environment-value" : nothing), 3)
                        variable = first(pair.first for pair in settings if pair.second !== nothing)
                        withenv(settings..., "MAKE" => missing_make) do
                            for target in (absent_cache, empty_cache, cache, linked_cache)
                                rejected(target; reason = :unsupported_make_environment, variable)
                            end
                            rejected(cache; check = merge(check_a, (; cmdstan_root = nothing)),
                                reason = :runtime_unavailable)
                            rejected(cache; selected_family = :probe_missing_source,
                                reason = :model_source_missing)
                        end
                        @test all(!haskey(ENV, name) for name in make_names)
                        @test ENV["MAKE"] == make_a
                    end
                    for selection in invalid_make
                        withenv("MAKE" => selection) do
                            rejected(cache; reason = :make_unavailable)
                            rejected(joinpath(temporary, "uncreated-$family"); reason = :make_unavailable)
                        end
                    end
                    rejected(cache)
                    rejected(cache; check = check_b) # Different root, same explicit cache.
                    for (key, value) in (("CXX", cxx_b), ("MAKE", make_b), ("STAN_THREADS", "true"))
                        withenv(key => value) do
                            rejected(cache)
                        end
                    end
                    for path in (local_make, stanc, cxx_a, make_a)
                        original = read(path)
                        try
                            write(path, path == local_make ? collect(codeunits("STAN_THREADS=true\n")) :
                                [original; UInt8('\n')])
                            @test digest(path) != bytes2hex(sha256(original))
                            rejected(cache)
                        finally
                            write(path, original)
                        end
                    end
                    write(executable, "different nonempty model fixture\n")
                    @test digest(executable) != first_digest
                    rejected(cache)
                    chmod(executable, 0o600)
                    rejected(cache)
                    write(executable, "")
                    rejected(cache)
                    write(copied, "changed source fixture\n")
                    rejected(cache)
                    for path in (copied, executable)
                        backup = joinpath(temporary, basename(path) * ".test-backup")
                        mv(path, backup)
                        try
                            rejected(cache)
                        finally
                            mv(backup, path)
                        end
                    end

                    for name in ("bayesian_mgmfrm_$family.hpp", "bayesian_mgmfrm_$family.o",
                            ".DS_Store", "unrelated.txt")
                        partial = mktempdir(temporary)
                        write(joinpath(partial, name), "retained fixture\n")
                        rejected(partial)
                    end
                    child_root = mktempdir(temporary)
                    mkpath(joinpath(child_root, "nested"))
                    rejected(child_root)
                    file_root = joinpath(temporary, "file-root-$family")
                    write(file_root, "retained root file\n")
                    rejected(file_root)
                    for (name, target) in (("occupied", cache), ("empty", mktempdir(temporary)),
                            ("file", file_root), ("dangling", joinpath(temporary, "absent-$family")))
                        alias = joinpath(temporary, "$name-link-$family")
                        symlink(target, alias)
                        rejected(alias)
                        rejected(alias * "/")
                        rejected(joinpath(alias, "."))
                    end
                    link_entry = mktempdir(temporary)
                    symlink(file_root, joinpath(link_entry, "retained-link"))
                    rejected(link_entry)

                    # Only fresh roots reach the command trap; a repeated call must reject.
                    fresh_cases = [(mktempdir(temporary), make_a),
                            (joinpath(temporary, "new-$family", "cache"), make_a),
                            (mktempdir(temporary), make_spaced)]
                    append!(fresh_cases, [(mktempdir(temporary), make_a) for _ in 0:7])
                    for (case, (fresh, program)) in enumerate(fresh_cases)
                        count = length(requests)
                        toolchain_before = snapshot(root_a)
                        mask = case <= 3 ? 0 : case - 4
                        settings = ntuple(i -> make_names[i] =>
                            (mask & (1 << (i - 1)) != 0 ? "" : nothing), 3)
                        environment = nothing
                        withenv("MAKE" => program, settings...) do
                            environment = map(name -> get(ENV, name, nothing), environment_names)
                            @test_throws BuildRequested _cmdstan_compile_model(check_a, family; cache_dir = fresh)
                            @test map(name -> get(ENV, name, nothing), environment_names) == environment
                        end
                        @test all(!haskey(ENV, name) for name in make_names)
                        @test ENV["MAKE"] == make_a
                        fresh_stem = joinpath(fresh, "bayesian_mgmfrm_" * string(family))
                        @test readdir(fresh) == [basename(fresh_stem) * ".stan"]
                        @test read(fresh_stem * ".stan") == read(_cmdstan_model_source(family))
                        @test length(requests) == count + 1
                        @test requests[end] == (; stage = :model_compile,
                            argv = [program, "-f", "makefile", fresh_stem], directory = root_a,
                            environment)
                        @test snapshot(root_a) == toolchain_before
                        rejected(fresh)
                    end
                end
            end

            @testset "Output file, sampler entry and command construction" begin
                handoff = mktempdir(temporary)
                sampler_options = (; ndraws = 2, warmup = 2, chains = 2, step_size = 0.03,
                    target_accept = 0.8, max_depth = 10, metric = "diag_e", init_jitter = 0.0,
                    progress = false)
                command_options = (; ndraws = 2, warmup = 2, step_size = 0.03, target_accept = 0.8,
                    max_depth = 10, metric = "diag_e", data_path = joinpath(handoff, "data.json"),
                    init_path = joinpath(handoff, "init.json"), output_path = joinpath(handoff, "out.csv"),
                    seed = 17, chain = 1, progress = false) # Inert command argument, not an allocated seed.
                sample(path, rng; kwargs...) = _cmdstan_sample_chains(path, nothing, [0.0], rng,
                    _ -> error("unexpected initialization"), (args...) -> error("unexpected parse");
                    sampler_options..., kwargs...)
                command(path; kwargs...) = _cmdstan_sample_command(path; command_options..., kwargs...)
                function rejection(operation, reason; stage = :sampling)
                    retained = snapshot(temporary)
                    count = length(requests)
                    result = try
                        operation()
                    catch error
                        error
                    end
                    @test result isa CmdStanError && result.stage === stage && result.reason === reason
                    @test snapshot(temporary) == retained
                    @test length(requests) == count
                end
                for family in (:mfrm, :gmfrm, :mgmfrm)
                    output = joinpath(handoff, "$family model fixture")
                    contents = "inert $family fixture A, never execute\n"
                    write(output, contents)
                    chmod(output, 0o700)
                    expected = bytes2hex(sha256(contents))
                    retained = snapshot(temporary)
                    for stage in (:model_compile, :sampling)
                        @test _cmdstan_executable_sha256(output, stage) == expected
                    end
                    rng = NoDrawRNG(0)
                    @test_throws SeedRequested sample(output, rng; expected_sha256 = expected)
                    @test rng.requests == 1
                    @test snapshot(temporary) == retained

                    for warmup in (0, 2), progress in (false, true)
                        built = command(output; expected_sha256 = expected, warmup, progress)
                        expected_argv = [output, "sample", "num_samples=2", "num_warmup=$warmup",
                            "save_warmup=0", "thin=1", "adapt", "engaged=$(warmup > 0 ? 1 : 0)"]
                        warmup > 0 && push!(expected_argv, "delta=0.8")
                        append!(expected_argv, ["algorithm=hmc", "engine=nuts", "max_depth=10",
                            "metric=diag_e", "stepsize=0.03", "data", "file=$(command_options.data_path)",
                            "init=$(command_options.init_path)", "random", "seed=17", "id=1", "output",
                            "file=$(command_options.output_path)", "refresh=$(progress ? 1 : 0)", "sig_figs=18"])
                        @test collect(built) == expected_argv
                        @test built.env === nothing
                        @test snapshot(temporary) == retained
                    end
                    rng = NoDrawRNG(0)
                    @test_throws UndefKeywordError sample(output, rng)
                    @test_throws UndefKeywordError command(output)
                    @test rng.requests == 0
                    @test snapshot(temporary) == retained
                    for wrong in ("", "not-a-digest", uppercase(expected), " " * expected, "0"^64)
                        rejection(() -> sample(output, rng; expected_sha256 = wrong), :executable_changed)
                        rejection(() -> command(output; expected_sha256 = wrong), :executable_changed)
                        @test rng.requests == 0
                    end

                    # Same-length bytes changed after the matching sampler-entry check above.
                    write(output, replace(contents, "fixture A" => "fixture B"))
                    @test filesize(output) == sizeof(contents)
                    @test _cmdstan_executable_sha256(output, :model_compile) != expected
                    rejection(() -> sample(output, rng; expected_sha256 = expected), :executable_changed)
                    rejection(() -> command(output; expected_sha256 = expected), :executable_changed)
                    @test rng.requests == 0

                    missing = joinpath(handoff, "missing-$family")
                    directory = mktempdir(handoff)
                    empty_output = joinpath(handoff, "empty-$family")
                    write(empty_output, "")
                    chmod(empty_output, 0o700)
                    non_executable = joinpath(handoff, "non-executable-$family")
                    write(non_executable, contents)
                    chmod(non_executable, 0o600)
                    linked, dangling = joinpath(handoff, "link-$family"), joinpath(handoff, "dangling-$family")
                    symlink(output, linked)
                    symlink(missing, dangling)
                    for (path, reason) in ((missing, :executable_missing), (directory, :executable_invalid),
                            (empty_output, :executable_invalid), (non_executable, :executable_invalid),
                            (linked, :executable_invalid), (dangling, :executable_invalid),
                            (relpath(output), :executable_invalid), ("", :executable_invalid))
                        for stage in (:model_compile, :sampling)
                            rejection(() -> _cmdstan_executable_sha256(path, stage), reason; stage)
                        end
                        rejection(() -> sample(path, rng; expected_sha256 = expected), reason)
                        rejection(() -> command(path; expected_sha256 = expected), reason)
                        @test rng.requests == 0
                    end
                end
            end
        end
        @test length(requests) == 33 && all(request.stage === :model_compile for request in requests)
        @test map(name -> get(ENV, name, nothing), environment_names) == inherited_before
        @test all(digest(path) == expected for (path, expected) in before)
    end
    println("CONTAINED, REUSE DISABLED: 3 families; invalid MAKE, inherited settings and occupied/symlink roots rejected unchanged; 33 explicit-Makefile build requests trapped")
    for path in watched
        println(relpath(path, source_root), " sha256=", before[path])
    end
    return nothing
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    CmdStanCacheIdentityProbe.main()
end
