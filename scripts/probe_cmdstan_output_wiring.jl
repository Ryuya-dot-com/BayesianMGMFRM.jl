"""
Manual SYNTHETIC wiring check, not a native build, posterior fit or research attempt.
Run with --project=. in a fresh Julia process; use installed dependencies only.
Four local substitutes surround unchanged source bodies and real package types.
Only owned temporary fixtures are written; returned objects must never be saved.
Re-audit source before running: module isolation is not an OS sandbox.
"""
module CmdStanOutputWiringProbe

using Test, SHA, Random
import BayesianMGMFRM as B
import LogDensityProblems
using BayesianMGMFRM: CmdStanError, FacetDesign, MFRMPrior, MFRMFit,
    _GeneralizedCandidateLogDensity, initial_params,
    _GENERALIZED_DEFAULT_RETAINED_DRAWS_PER_CHAIN, _GENERALIZED_DEFAULT_WARMUP_PER_CHAIN,
    _GENERALIZED_DEFAULT_CHAINS, _cmdstan_model_source, _cmdstan_configured_program,
    _fatal_exception, _cmdstan_failure_reason, _cmdstan_executable_path, _cmdstan_executable_sha256,
    _cmdstan_metric, _cmdstan_mfrm_data, _logposterior_unchecked, _cmdstan_chain_result,
    _cmdstan_generalized_family, _cmdstan_generalized_data, _cmdstan_generalized_chain_result,
    _check_fit_controls, _check_nuts_controls,
    _check_diagnostic_thresholds, _check_source_fixture_raw_vector, _fit_rng,
    _generalized_candidate_sampler_rows, _column_mean, _stat_mean

const source_root = normpath(joinpath(@__DIR__, "..", "src"))
const wanted = (:_cmdstan_compile_model, :_cmdstan_compile_mfrm,
    :_fit_cmdstan, :_cmdstan_generalized_candidate_run)
const substituted = (:cmdstan_backend_check, :_cmdstan_cache_root, :_cmdstan_run,
    :_cmdstan_sample_chains)
const protected_names = (wanted..., substituted...)
const package_methods = map(name -> collect(methods(getfield(B, name))), protected_names)
const selected = Symbol[]
Base.include(@__MODULE__, joinpath(source_root, "cmdstan_fit.jl")) do expression
    signature = expression isa Expr && expression.head in (:function, :(=)) ? expression.args[1] : nothing
    name = signature isa Expr && signature.head === :call ? signature.args[1] : nothing
    if name in wanted
        push!(selected, name)
        return expression # Unmodified long/short-form method; no other definition/import.
    end
    return nothing
end
@assert Tuple(selected) == wanted

# ponytail: one serial owned fixture at a time; not a general backend simulator.
const active = Ref{Any}(nothing)
const calls = Symbol[]
const sampled = NamedTuple[]
const environment_names = ("MAKE", "MAKEFILES", "MAKEFLAGS", "GNUMAKEFLAGS")

function cmdstan_backend_check(; cmdstan_path, include_paths, require_ready)
    case = active[]
    case !== nothing && cmdstan_path == case.root && include_paths && require_ready ||
        error("unexpected synthetic runtime request")
    push!(calls, :runtime)
    return (; cmdstan_root = case.root, cmdstan_version = "synthetic-only",
        cmdstan_root_basename = basename(case.root))
end

function _cmdstan_cache_root(check, cache_dir)
    case = active[]
    case !== nothing && cache_dir == case.cache && check.cmdstan_root == case.root ||
        error("synthetic check refuses default or non-owned cache paths")
    push!(calls, :cache)
    return B._cmdstan_cache_root(check, cache_dir)
end

function _cmdstan_run(command::Cmd, stage::Symbol; kwargs...)
    case = active[]
    case !== nothing && stage === :model_compile && isempty(kwargs) ||
        error("synthetic check refuses non-compile commands")
    collect(command) == [case.program, "-f", "makefile", case.stem] &&
        command.dir == case.root && command.env === nothing ||
        error("unexpected synthetic compile command")
    all(isempty(get(ENV, name, "")) for name in environment_names[2:4]) ||
        error("unexpected inherited Make settings")
    isdir(case.cache) && !islink(case.cache) &&
        readdir(case.cache) == [basename(case.stem) * ".stan"] ||
        error("unexpected synthetic cache contents")
    read(case.stem * ".stan") == read(_cmdstan_model_source(case.family)) ||
        error("unexpected copied Stan source")
    case.fault in (nothing, :command, :missing, :empty, :nonexecutable, :symlink) ||
        error("unknown synthetic fault")
    push!(calls, :compile)
    case.fault === :command && throw(CmdStanError(:model_compile, :command_failed,
        "synthetic command failure; no command executed"))
    case.fault === :missing && return nothing
    # This fixed output is inside our fresh cache, never taken from unchecked argv.
    (ispath(case.output) || islink(case.output)) && error("output already exists")
    if case.fault === :symlink
        symlink(case.reference, case.output)
    else
        write(case.output, case.fault === :empty ? "" : case.bytes)
        chmod(case.output, case.fault === :nonexecutable ? 0o600 : 0o700)
    end
    return nothing # Synthetic completion only; never delegate to run/pipeline.
end

mutable struct NoDrawRNG <: AbstractRNG
    requests::Int
end
function Random.rand(rng::NoDrawRNG, ::Type{T}) where {T}
    rng.requests += 1
    error("synthetic wiring must not request random values")
end

function _cmdstan_sample_chains(executable::AbstractString, payload, initial::Vector{Float64},
        rng::AbstractRNG, evaluate_initial::Function, parse_chain::Function;
        expected_sha256::AbstractString, kwargs...)
    case = active[]
    case !== nothing && executable == case.output && expected_sha256 == case.expected &&
        rng === case.rng && initial == case.initial || error("incorrect synthetic handoff")
    options = (; kwargs...)
    Dict(pairs(options)) == Dict(pairs(case.options)) || error("incorrect sampler controls")
    payload.P == case.nparams && payload.N == 9 || error("incorrect payload dimensions")
    push!(calls, :sample)
    push!(sampled, (; executable, expected_sha256, options, nparams = payload.P))
    stats = NamedTuple[(; chain = 1, acceptance_rate = 0.5, step_size = 0.03,
        numerical_error = false, tree_depth = 1, n_steps = 1, hamiltonian_energy = Float64(i))
        for i in 1:2]
    return (; chain_seeds = [17], draws = repeat(reshape(initial, 1, :), 2, 1),
        logdensities = [-1.0, -1.0], chain_ids = [1, 1], iterations = [1, 2],
        chain_acceptance = [0.5], sampler_stats = stats)
end

function main()
    Sys.isunix() || error("synthetic fixture permissions are scoped to local POSIX filesystems")
    realpath(pathof(B)) == realpath(joinpath(source_root, "BayesianMGMFRM.jl")) ||
        error("the loaded package is not this checkout")
    watched = [joinpath(source_root, name) for name in
        ("cmdstan_backend.jl", "cmdstan_fit.jl", "bayesian_fit.jl", "stan/mfrm.stan",
            "stan/gmfrm.stan", "stan/mgmfrm.stan")]
    append!(watched, [joinpath(source_root, "..", name) for name in
        ("Project.toml", "Manifest.toml", "scripts/probe_cmdstan_cache_identity.jl",
            "scripts/probe_cmdstan_output_wiring.jl")])
    digest(path) = bytes2hex(sha256(read(path)))
    before = Dict(path => digest(path) for path in watched)
    inherited = map(name -> get(ENV, name, nothing), environment_names)
    function snapshot(path)
        islink(path) && return (:link, readlink(path))
        isfile(path) && return (:file, read(path), stat(path).mode, mtime(path))
        isdir(path) && return (:directory,
            [(name, snapshot(joinpath(path, name))) for name in readdir(path)])
        return (:absent,)
    end
    capture(operation) = try
        operation()
    catch error
        error
    end
    table = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2", "E3", "E3", "E3"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2, 1, 2, 0])
    data = B.FacetData(table; person = :examinee, rater = :rater, item = :item, score = :score)
    specifications = (
        (:pcm, B.mfrm_spec(data; thresholds = :partial_credit), 7),
        (:rsm, B.mfrm_spec(data; thresholds = :rating_scale), 6),
        (:gmfrm, B.mfrm_spec(data; family = :gmfrm, thresholds = :partial_credit,
            discrimination = :rater), 11),
        (:mgmfrm, B.mfrm_spec(data; family = :mgmfrm, dimensions = 2,
            thresholds = :partial_credit, discrimination = :none, q_matrix = Bool[1 0; 0 1]), 14))
    println("Julia ", VERSION, "; SYNTHETIC wiring only; no native process or scientific draws")
    @testset "CmdStan synthetic producer and control wiring" begin
        @test all(getfield(@__MODULE__, name) !== getfield(B, name) for name in protected_names)
        @test map(name -> collect(methods(getfield(B, name))), protected_names) == package_methods
        mktempdir() do temporary
            root = mkpath(joinpath(temporary, "toolchain fixture"))
            program = joinpath(root, "make fixture")
            write(program, "inert Make placeholder; never execute\n")
            chmod(program, 0o700)
            write(joinpath(root, "makefile"), "# inert fixture\n")
            reference = joinpath(root, "reference fixture")
            write(reference, "inert retained reference\n")
            toolchain = snapshot(root)
            withenv("MAKE" => program, "MAKEFILES" => nothing, "MAKEFLAGS" => nothing,
                    "GNUMAKEFLAGS" => nothing) do
                for (label, specification, nparams) in specifications
                    family = specification.family
                    design = family === :mfrm ? B.getdesign(specification) :
                        B.getdesign(specification; preview = true)
                    target = family === :mfrm ? nothing : family === :gmfrm ?
                        B._gmfrm_promotion_candidate_logdensity(design) :
                        B._mgmfrm_guarded_local_fit_logdensity(design)
                    initial = family === :mfrm ? zeros(length(design.parameter_names)) :
                        Float64.(initial_params(target))
                    @test length(initial) == nparams
                    for mode in (:direct, :fit, :command, :missing, :empty, :nonexecutable, :symlink)
                        cache = mktempdir(temporary)
                        stem = joinpath(cache, "bayesian_mgmfrm_" * string(family))
                        output = _cmdstan_executable_path(stem)
                        bytes = "synthetic $label output; never execute\n"
                        expected = bytes2hex(sha256(bytes))
                        rng = NoDrawRNG(0)
                        options = (; ndraws = 2, warmup = 0, chains = 1, step_size = 0.03,
                            target_accept = 0.8, max_depth = 10, metric = "diag_e",
                            init_jitter = 0.0, progress = false)
                        active[] = (; root, program, cache, stem, output, bytes, expected, reference,
                            family, initial, nparams, rng, options,
                            fault = mode in (:direct, :fit) ? nothing : mode)
                        empty!(calls)
                        empty!(sampled)
                        check = (; cmdstan_root = root, cmdstan_version = "synthetic-only")
                        invoke() = family === :mfrm ?
                            _fit_cmdstan(design, MFRMPrior(), 2, 0, 1, 0.03, initial, rng,
                                last(_fit_rng(rng, nothing)); target_accept = 0.8, max_depth = 10,
                                max_energy_error = 1000.0, metric = :diagonal, ad_backend = :ForwardDiff,
                                init_jitter = 0.0, progress = false, cmdstan_path = root,
                                cmdstan_cache_dir = cache) :
                            _cmdstan_generalized_candidate_run(target, initial; ndraws = 2,
                                warmup = 0, chains = 1, rng, seed = nothing, cmdstan_path = root,
                                cmdstan_cache_dir = cache)
                        result = mode === :direct ? _cmdstan_compile_model(check, family; cache_dir = cache) :
                            capture(invoke)
                        @test count(==(:compile), calls) == 1
                        @test count(==(:runtime), calls) == (mode === :direct ? 0 : 1)
                        @test count(==(:sample), calls) == (mode === :fit ? 1 : 0)
                        @test rng.requests == 0
                        @test snapshot(root) == toolchain
                        @test read(stem * ".stan") == read(_cmdstan_model_source(family))
                        if mode === :direct
                            @test result == (; path = output, sha256 = expected)
                        elseif mode === :fit
                            @test family === :mfrm ? result isa MFRMFit : result isa NamedTuple
                            controls = family === :mfrm ? result.sampler_controls : result.controls
                            @test controls.cmdstan_executable_sha256 == expected
                            @test controls.cmdstan_version == "synthetic-only"
                            @test controls.execution === :cmdstan_cli # Still synthetic; never save this object.
                            @test controls.rng.chain_seeds == (17,)
                            @test !occursin(temporary, repr(controls))
                            @test size(result.draws) == (2, nparams)
                            @test result.draws == repeat(reshape(initial, 1, :), 2, 1)
                            @test result.chain_ids == [1, 1] && result.iterations == [1, 2]
                            @test only(sampled) == (; executable = output, expected_sha256 = expected,
                                options, nparams)
                            if family === :mfrm
                                @test B.fit_metadata(result).sampler_controls.cmdstan_executable_sha256 == expected
                            else
                                @test result.nparams == nparams && result.total_draws == 2
                                @test length(result.sampler_rows) == 1
                            end
                        else
                            reason = mode === :command ? :command_failed : mode === :missing ?
                                :executable_missing : :executable_invalid
                            @test result isa CmdStanError && result.stage === :model_compile &&
                                result.reason === reason
                            @test isempty(sampled)
                        end
                        @test sort(readdir(cache)) == sort(mode in (:command, :missing) ?
                            [basename(stem) * ".stan"] : [basename(stem), basename(stem) * ".stan"])
                        retained = snapshot(temporary)
                        counts = (count(==(:compile), calls), length(sampled))
                        repeated = capture(invoke)
                        @test repeated isa CmdStanError && repeated.reason === :cache_unverified
                        @test (count(==(:compile), calls), length(sampled)) == counts
                        @test snapshot(temporary) == retained
                        @test rng.requests == 0
                        if mode === :fit
                            @test_throws ErrorException _cmdstan_cache_root(check, nothing)
                            @test_throws ErrorException _cmdstan_cache_root(check, joinpath(temporary, "not-owned"))
                            @test_throws ErrorException _cmdstan_run(Cmd([program, "unknown"]), :model_compile)
                            @test_throws ErrorException _cmdstan_run(Cmd([output, "sample"]), :sampling)
                            @test snapshot(temporary) == retained
                            @test (count(==(:compile), calls), length(sampled)) == counts
                        end
                    end
                end
            end
        end
        active[] = nothing
        @test map(name -> get(ENV, name, nothing), environment_names) == inherited
        @test all(digest(path) == expected for (path, expected) in before)
        @test map(name -> collect(methods(getfield(B, name))), protected_names) == package_methods
    end
    println("SYNTHETIC ONLY: 4 direct producer returns; 4 routed fixed results; 20 injected compile failures; zero native execution or RNG requests")
    for path in watched
        println(relpath(path, joinpath(source_root, "..")), " sha256=", before[path])
    end
    return nothing
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    CmdStanOutputWiringProbe.main()
end
