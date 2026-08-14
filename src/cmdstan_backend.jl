# cmdstan_backend.jl -- portable CmdStan runtime discovery and release contract.

const _CMDSTAN_BACKEND_FAMILIES = (:mfrm, :gmfrm, :mgmfrm)

"""
    CmdStanError

Typed failure raised by the CmdStan runtime check, model compilation, command
execution, or output parser. `stage` identifies the failed operation, `reason`
is a stable symbolic category, and `detail` contains a concise diagnostic.
"""
struct CmdStanError <: Exception
    stage::Symbol
    reason::Symbol
    detail::String
end

function Base.showerror(io::IO, error::CmdStanError)
    print(io, "CmdStan ", error.stage, " failed (", error.reason, ")")
    isempty(error.detail) || print(io, ": ", error.detail)
end

function _cmdstan_version_from_name(path::AbstractString)
    matched = match(r"^cmdstan-([0-9]+\.[0-9]+(?:\.[0-9]+)?)$", basename(path))
    matched === nothing && return nothing
    return tryparse(VersionNumber, matched.captures[1])
end

function _cmdstan_latest_default_install()
    parent = joinpath(homedir(), ".cmdstan")
    isdir(parent) || return nothing
    candidates = Tuple{VersionNumber,String}[]
    for path in readdir(parent; join = true)
        isdir(path) || continue
        version = _cmdstan_version_from_name(path)
        version === nothing && continue
        push!(candidates, (version, path))
    end
    isempty(candidates) && return nothing
    sort!(candidates; by = first)
    return last(candidates)[2]
end

function _cmdstan_resolve_root(cmdstan_path)
    if cmdstan_path !== nothing
        path = strip(String(cmdstan_path))
        isempty(path) && return (path = nothing, source = :argument)
        return (path = abspath(expanduser(path)), source = :argument)
    end
    for (name, source) in (("CMDSTAN", :env_cmdstan),
            ("CMDSTAN_HOME", :env_cmdstan_home))
        path = strip(get(ENV, name, ""))
        isempty(path) && continue
        return (path = abspath(expanduser(path)), source)
    end
    path = _cmdstan_latest_default_install()
    return (;
        path,
        source = path === nothing ? :not_found : :default_install,
    )
end

function _cmdstan_program(root, name::AbstractString)
    root === nothing && return nothing
    candidates = Sys.iswindows() ?
        (joinpath(root, "bin", name * ".exe"), joinpath(root, "bin", name)) :
        (joinpath(root, "bin", name),)
    index = findfirst(isfile, candidates)
    return index === nothing ? first(candidates) : candidates[index]
end

function _cmdstan_configured_program(environment_name::AbstractString,
        defaults::Tuple)
    configured = strip(get(ENV, environment_name, ""))
    candidates = isempty(configured) ? defaults : (first(split(configured)),)
    for candidate in candidates
        path = Sys.which(candidate)
        path === nothing || return path
    end
    return nothing
end

_cmdstan_check(check::Symbol, passed::Bool, status::Symbol; detail = nothing) =
    (; check, passed, status, detail)

function _cmdstan_stanc_check(path)
    path === nothing && return _cmdstan_check(
        :stanc_execution, false, :missing; detail = nothing)
    isfile(path) || return _cmdstan_check(
        :stanc_execution, false, :missing; detail = nothing)
    try
        output = readchomp(pipeline(`$path --version`; stderr = devnull))
        return _cmdstan_check(
            :stanc_execution,
            true,
            :passed;
            detail = isempty(output) ? nothing : output,
        )
    catch error
        reason = error isa Base.ProcessFailedException ? :command_failed :
            error isa Base.IOError ? :io_error : :unexpected_error
        return _cmdstan_check(
            :stanc_execution,
            false,
            :failed;
            detail = reason,
        )
    end
end

function _cmdstan_version_from_output(output)
    output isa AbstractString || return nothing
    matched = match(r"v([0-9]+\.[0-9]+(?:\.[0-9]+)?)", output)
    return matched === nothing ? nothing : matched.captures[1]
end

function _cmdstan_model_source_status(family::Symbol)
    family === :mfrm && return :package_model_and_cli_adapter
    family === :gmfrm && return :validation_reference_only
    family === :mgmfrm && return :validation_reference_only
    return (
        mfrm = :package_model_and_cli_adapter,
        gmfrm = :validation_reference_only,
        mgmfrm = :validation_reference_only,
    )
end

"""
    cmdstan_backend_contract([family = :all])

Return the implementation and release contract for CmdStan fitting
backend. `family` may be `:mfrm`, `:gmfrm`, `:mgmfrm`, or `:all`.

The contract deliberately distinguishes a working CmdStan installation from a
working package backend. CmdStan fitting is a required gate before stable
promotion, but CmdStan remains an optional external runtime so loading and
using Julia-only package features does not depend on a machine-local install.
Stable MFRM/RSM/PCM designs can be sampled through CmdStan. Generalized
families are not yet connected, and broader same-target recovery,
sparse-design, cache, and analysis-scale evidence is still required;
`release_gate_satisfied` is therefore `false`.
"""
function cmdstan_backend_contract(family::Symbol = :all)
    family === :all || family in _CMDSTAN_BACKEND_FAMILIES ||
        throw(ArgumentError(
            "family must be :mfrm, :gmfrm, :mgmfrm, or :all; got $(repr(family))",
        ))
    return (;
        schema = :bayesian_mgmfrm_cmdstan_backend_contract_v1,
        backend = :cmdstan,
        family,
        supported_families = _CMDSTAN_BACKEND_FAMILIES,
        release_requirement = :required_before_stable_promotion,
        release_gate_satisfied = false,
        implementation_stage = :stable_mfrm_fit_available,
        implemented_families = (:mfrm,),
        fit_backend_implemented = family === :mfrm,
        default_backend = false,
        core_install_requires_cmdstan = false,
        model_source_status = _cmdstan_model_source_status(family),
        remaining_capability = family === :mfrm ?
            :analysis_scale_validation_and_cache_integration :
            :generalized_model_data_csv_fit_adapters,
    )
end

"""
    cmdstan_backend_check(; cmdstan_path = nothing,
        include_paths = false, require_ready = false)

Check whether a local CmdStan toolchain is ready for the package's
`backend = :cmdstan` adapter. Discovery uses an explicit `cmdstan_path` first,
then `CMDSTAN`, `CMDSTAN_HOME`, and finally the newest versioned directory under
`~/.cmdstan`. An explicitly supplied or configured invalid path is reported; it
is not silently replaced by another installation.

The check validates the CmdStan root, makefile, `stanc --version`, `make`, and a
C++ compiler. It does not compile a Stan model or run MCMC. Machine-local paths
are omitted by default. Set `require_ready = true` to throw a
[`CmdStanError`](@ref) when a check fails.
"""
function cmdstan_backend_check(;
        cmdstan_path::Union{Nothing,AbstractString} = nothing,
        include_paths::Bool = false,
        require_ready::Bool = false)
    resolved = _cmdstan_resolve_root(cmdstan_path)
    root = resolved.path
    root_present = root !== nothing && isdir(root)
    makefile_present = root_present && isfile(joinpath(root, "makefile"))
    stanc = _cmdstan_program(root, "stanc")
    stanc_present = stanc !== nothing && isfile(stanc)
    stanc_check = _cmdstan_stanc_check(stanc)
    make_program = _cmdstan_configured_program("MAKE", ("make", "gmake"))
    cxx_program = _cmdstan_configured_program(
        "CXX",
        ("c++", "g++", "clang++"),
    )
    checks = (
        _cmdstan_check(:root_directory, root_present,
            root_present ? :passed : :missing),
        _cmdstan_check(:makefile, makefile_present,
            makefile_present ? :passed : :missing),
        _cmdstan_check(:stanc_program, stanc_present,
            stanc_present ? :passed : :missing),
        stanc_check,
        _cmdstan_check(:make_program, make_program !== nothing,
            make_program === nothing ? :missing : :passed;
            detail = make_program === nothing ? nothing : basename(make_program)),
        _cmdstan_check(:cxx_compiler, cxx_program !== nothing,
            cxx_program === nothing ? :missing : :passed;
            detail = cxx_program === nothing ? nothing : basename(cxx_program)),
    )
    runtime_ready = all(row -> row.passed, checks)
    failed_checks = Tuple(row.check for row in checks if !row.passed)
    result = (;
        schema = :bayesian_mgmfrm_cmdstan_backend_check_v1,
        backend = :cmdstan,
        status = runtime_ready ? :runtime_ready : :runtime_unavailable,
        runtime_ready,
        discovery_source = resolved.source,
        cmdstan_root = include_paths ? root : nothing,
        cmdstan_root_basename = root === nothing ? nothing : basename(normpath(root)),
        cmdstan_version = _cmdstan_version_from_output(stanc_check.detail),
        stanc_path = include_paths && stanc_present ? stanc : nothing,
        checks,
        failed_checks,
        implementation_stage = :stable_mfrm_fit_available,
        implemented_families = (:mfrm,),
        stable_mfrm_fit_implemented = true,
        release_gate_satisfied = false,
    )
    if require_ready && !runtime_ready
        throw(CmdStanError(
            :runtime_check,
            :runtime_unavailable,
            "failed checks: " * join(string.(failed_checks), ", "),
        ))
    end
    return result
end
