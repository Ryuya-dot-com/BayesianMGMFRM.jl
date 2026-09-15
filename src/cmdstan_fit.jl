# cmdstan_fit.jl -- direct CmdStan CLI adapters for supported fit surfaces.

import JSON3

function _cmdstan_model_source(family::Symbol)
    family in (:mfrm, :gmfrm, :mgmfrm, :mfrm_fixed_q, :mfrm_correlated_2d) || throw(ArgumentError(
        "CmdStan has no package-owned model for family = $(repr(family))",
    ))
    module_path = pathof(BayesianMGMFRM)
    module_path === nothing && throw(CmdStanError(
        :model_compile,
        :package_path_unavailable,
        "the loaded package source path is unavailable",
    ))
    return joinpath(dirname(module_path), "stan", string(family) * ".stan")
end

_cmdstan_mfrm_source() = _cmdstan_model_source(:mfrm)
_cmdstan_gmfrm_source() = _cmdstan_model_source(:gmfrm)
_cmdstan_mgmfrm_source() = _cmdstan_model_source(:mgmfrm)

function _cmdstan_failure_reason(error)
    error isa Base.ProcessFailedException && return :command_failed
    error isa Base.IOError && return :io_error
    error isa ArgumentError && return :invalid_value
    return :unexpected_error
end

function _cmdstan_error_detail(error)
    # Base.showerror(CompositeException) hides every cause after the first.
    return error isa CompositeException ?
        join((sprint(showerror, cause) for cause in error.exceptions), "\nAdditional exception:\n") :
        sprint(showerror, error)
end

function _cmdstan_short_detail(text::AbstractString; limit::Int = 2000)
    cleaned = strip(text)
    isempty(cleaned) && return "no command diagnostic was produced"
    length(cleaned) <= limit && return cleaned
    return "…" * last(cleaned, limit)
end

const _CMDSTAN_ACTIVE_COMMANDS = Dict{Base.Process,Int}()
const _CMDSTAN_PROCESS_LOCK = ReentrantLock()
const _CMDSTAN_EXIT_HOOK = Ref(false)

function _cmdstan_stop(process::Base.Process, group::Int)
    if Sys.isunix()
        # Never address Julia's group or POSIX's special all/current-process targets.
        group > 1 && group != ccall(:getpgrp, Cint, ()) ||
            throw(ArgumentError("invalid owned CmdStan process group"))
        # ponytail: owned POSIX group; setsid/setpgid escape needs OS job containment.
        code = ccall(:uv_kill, Cint, (Cint, Cint), -group, Base.SIGKILL)
        code in (0, Base.UV_ESRCH) || throw(Base.IOError(
            "could not terminate owned CmdStan process group", code))
    else
        kill(process, Base.SIGKILL)
    end
    wait(process)
    return nothing
end

function _cmdstan_exit_cleanup()
    active = lock(_CMDSTAN_PROCESS_LOCK) do
        commands = collect(_CMDSTAN_ACTIVE_COMMANDS)
        empty!(_CMDSTAN_ACTIVE_COMMANDS)
        commands
    end
    failures = Any[]
    for (process, group) in active
        try
            _cmdstan_stop(process, group)
        catch err
            push!(failures, CapturedException(err, catch_backtrace()))
        end
    end
    isempty(failures) || throw(CompositeException(failures))
    return nothing
end

function _cmdstan_wait(command::Cmd, output::IO, error_output::IO)
    # Own/register the process before delivering SIGINT; protect cleanup from a second signal.
    return Base.disable_sigint() do
        owned = Sys.isunix() ? detach(command) : command
        process = run(pipeline(ignorestatus(owned);
            stdin = stdin, stdout = output, stderr = error_output); wait = false)
        group = try
            Sys.isunix() ? Int(getpid(process)) : 0
        catch
            kill(process, Base.SIGKILL)
            wait(process)
            rethrow()
        end
        try
            try
                lock(_CMDSTAN_PROCESS_LOCK) do
                    if !_CMDSTAN_EXIT_HOOK[]
                        atexit(_cmdstan_exit_cleanup)
                        _CMDSTAN_EXIT_HOOK[] = true
                    end
                    _CMDSTAN_ACTIVE_COMMANDS[process] = group
                end
                Base.reenable_sigint() do
                    wait(process)
                end
            catch err
                original = CapturedException(err, catch_backtrace())
                try
                    _cmdstan_stop(process, group)
                catch cleanup_error
                    throw(CompositeException([original,
                        CapturedException(cleanup_error, catch_backtrace())]))
                end
                rethrow()
            end
            # A wrapper may exit before its workers; clean the group on completion too.
            _cmdstan_stop(process, group)
            return process
        finally
            lock(_CMDSTAN_PROCESS_LOCK) do
                delete!(_CMDSTAN_ACTIVE_COMMANDS, process)
            end
        end
    end
end

function _cmdstan_run(command::Cmd, stage::Symbol; show_output::Bool = false)
    if show_output
        process = try
            _cmdstan_wait(command, stdout, stderr)
        catch error
            _fatal_exception(error) && rethrow()
            throw(CmdStanError(
                stage,
                _cmdstan_failure_reason(error),
                _cmdstan_error_detail(error),
            ))
        end
        success(process) || throw(CmdStanError(
            stage,
            :command_failed,
            "the command diagnostic was written to the active terminal",
        ))
        return nothing
    end
    mktempdir() do directory
        log_path = joinpath(directory, "command.log")
        process = try
            open(log_path, "w") do io
                _cmdstan_wait(command, io, io)
            end
        catch error
            _fatal_exception(error) && rethrow()
            throw(CmdStanError(
                stage,
                _cmdstan_failure_reason(error),
                _cmdstan_error_detail(error),
            ))
        end
        success(process) && return nothing
        detail = try
            read(log_path, String)
        catch error
            _fatal_exception(error) && rethrow()
            throw(CmdStanError(
                stage,
                _cmdstan_failure_reason(error),
                "command failed and its diagnostic could not be read",
            ))
        end
        throw(CmdStanError(stage, :command_failed, _cmdstan_short_detail(detail)))
    end
end

function _cmdstan_mfrm_data(design::FacetDesign, prior::MFRMPrior)
    _check_fit_supported_mfrm(design, "CmdStan data encoding")
    data = design.spec.data
    J = length(data.person_levels)
    R = length(data.rater_levels)
    I = length(data.item_levels)
    K = length(data.category_levels)
    free_steps = max(K - 2, 0)
    threshold_model = design.spec.thresholds === :rating_scale ? 1 : 2
    expected_parameters = J + (R - 1) + (I - 1) +
        (threshold_model == 1 ? free_steps : I * free_steps)
    expected_parameters == length(design.parameter_names) ||
        throw(CmdStanError(
            :data_encode,
            :parameter_layout_mismatch,
            "Stan expected $expected_parameters identified parameters; " *
            "the Julia design has $(length(design.parameter_names))",
        ))
    prior_sd = [
        _prior_sd(design, prior, index)
        for index in eachindex(design.parameter_names)
    ]
    return (;
        J,
        R,
        I,
        K,
        N = data.n,
        P = expected_parameters,
        free_steps,
        threshold_model,
        PersonID = copy(data.person),
        RaterID = copy(data.rater),
        ItemID = copy(data.item),
        X = copy(data.category),
        prior_sd,
    )
end

function _cmdstan_gmfrm_data(
        target::_GMFRMPromotionCandidateLogDensity)
    design = target.design
    data = design.spec.data
    J = length(data.person_levels)
    R = length(data.rater_levels)
    I = length(data.item_levels)
    K = length(data.category_levels)
    free_steps = K - 2
    expected_parameters = J + R + 2 * (I - 1) + R + R * free_steps
    expected_parameters == target.blueprint.n_parameters ||
        throw(CmdStanError(
            :data_encode,
            :parameter_layout_mismatch,
            "Stan expected $expected_parameters GMFRM raw parameters; " *
            "the Julia target has $(target.blueprint.n_parameters)",
        ))
    prior_sd = [
        _source_fixture_prior_sd(target, index)
        for index in 1:expected_parameters
    ]
    return (;
        J,
        R,
        I,
        K,
        N = data.n,
        P = expected_parameters,
        free_steps,
        PersonID = copy(data.person),
        RaterID = copy(data.rater),
        ItemID = copy(data.item),
        X = copy(data.category),
        prior_sd,
    )
end

function _cmdstan_mgmfrm_data(
        target::_MGMFRMGuardedLocalFitLogDensity)
    design = target.design
    data = design.spec.data
    q = design.spec.q_matrix
    q === nothing && throw(CmdStanError(
        :data_encode,
        :q_matrix_missing,
        "the guarded MGMFRM CmdStan adapter requires a fixed Q matrix",
    ))
    J = length(data.person_levels)
    R = length(data.rater_levels)
    I = length(data.item_levels)
    K = length(data.category_levels)
    D = design.spec.dimensions
    free_steps = K - 2
    LoadingItem = Int[]
    LoadingDim = Int[]
    for item in axes(q, 1), dimension in axes(q, 2)
        q[item, dimension] || continue
        push!(LoadingItem, item)
        push!(LoadingDim, dimension)
    end
    NLoadings = length(LoadingItem)
    expected_parameters = J * D + (R - 1) + I + NLoadings +
        (R - 1) + I * free_steps
    expected_parameters == target.blueprint.n_parameters ||
        throw(CmdStanError(
            :data_encode,
            :parameter_layout_mismatch,
            "Stan expected $expected_parameters MGMFRM raw parameters; " *
            "the Julia target has $(target.blueprint.n_parameters)",
        ))
    NLoadings == length(design.blocks[:item_dimension_discrimination]) ||
        throw(CmdStanError(
            :data_encode,
            :q_loading_layout_mismatch,
            "fixed-Q active cells do not match the Julia loading block",
        ))
    prior_sd = [
        _source_fixture_prior_sd(target, index)
        for index in 1:expected_parameters
    ]
    return (;
        J,
        R,
        I,
        K,
        D,
        N = data.n,
        P = expected_parameters,
        NLoadings,
        free_steps,
        PersonID = copy(data.person),
        RaterID = copy(data.rater),
        ItemID = copy(data.item),
        X = copy(data.category),
        LoadingItem,
        LoadingDim,
        prior_sd,
        prior_model = 0,
        source_rater = 0,
    )
end

function _cmdstan_write_json(path::AbstractString, value, stage::Symbol)
    try
        open(path, "w") do io
            JSON3.write(io, value)
        end
    catch error
        _fatal_exception(error) && rethrow()
        throw(CmdStanError(
            stage,
            _cmdstan_failure_reason(error),
            sprint(showerror, error),
        ))
    end
    return path
end

function _cmdstan_metric(metric::Symbol)
    metric === :diagonal && return "diag_e"
    metric === :dense && return "dense_e"
    metric === :unit && return "unit_e"
    throw(ArgumentError("metric must be :diagonal, :dense, or :unit"))
end

function _cmdstan_cache_root(check, cache_dir)
    if cache_dir !== nothing
        path = strip(String(cache_dir))
        isempty(path) && throw(ArgumentError("cmdstan_cache_dir must not be empty"))
        return abspath(expanduser(path))
    end
    version = something(check.cmdstan_version, check.cmdstan_root_basename, "unknown")
    safe_version = replace(String(version), r"[^A-Za-z0-9_.-]" => "_")
    return joinpath(tempdir(), "BayesianMGMFRM-cmdstan", safe_version)
end

function _cmdstan_executable_path(model_stem::AbstractString)
    return Sys.iswindows() ? model_stem * ".exe" : model_stem
end

function _cmdstan_executable_sha256(executable::AbstractString, stage::Symbol)
    # ponytail: observed file bytes, not build provenance; stable local paths only.
    try
        isabspath(executable) && !islink(executable) || throw(CmdStanError(
            stage,
            :executable_invalid,
            "the model executable must have an absolute path without a symbolic-link leaf",
        ))
        ispath(executable) || throw(CmdStanError(
            stage,
            :executable_missing,
            "the model executable is missing",
        ))
        isfile(executable) && filesize(executable) > 0 && Sys.isexecutable(executable) ||
            throw(CmdStanError(
                stage,
                :executable_invalid,
                "the model executable must be a nonempty regular file with executable permission",
            ))
        return open(executable, "r") do io
            bytes2hex(sha256(io))
        end
    catch error
        _fatal_exception(error) && rethrow()
        error isa CmdStanError && rethrow()
        throw(CmdStanError(stage, _cmdstan_failure_reason(error), sprint(showerror, error)))
    end
end

function _cmdstan_compile_model(check, family::Symbol; cache_dir = nothing)
    source = _cmdstan_model_source(family)
    isfile(source) || throw(CmdStanError(
        :model_compile,
        :model_source_missing,
        "the package-owned $(uppercase(string(family))) Stan source is unavailable",
    ))
    root = check.cmdstan_root
    root isa AbstractString || throw(CmdStanError(
        :model_compile,
        :runtime_unavailable,
        "CmdStan root was not retained by the runtime check",
    ))
    # ponytail: reject inherited options, including jobserver flags; extend only for a reviewed build profile.
    for name in ("MAKEFILES", "MAKEFLAGS", "GNUMAKEFLAGS")
        isempty(get(ENV, name, "")) || throw(CmdStanError(
            :model_compile,
            :unsupported_make_environment,
            "$name must be unset or empty; inherited Make settings are unsupported",
        ))
    end
    make_program = _cmdstan_configured_program("MAKE", ("make", "gmake"))
    make_program === nothing && throw(CmdStanError(
        :model_compile,
        :make_unavailable,
        "make or gmake was not found; MAKE must name one executable, not a command with arguments",
    ))
    # Strip trailing separators so a root symlink is still checked as a link.
    build_root = joinpath(splitpath(_cmdstan_cache_root(check, cache_dir))...)
    # ponytail: refuse reuse until build-input/binary evidence exists; stable local paths only.
    cache_unverified = try
        islink(build_root) || (ispath(build_root) &&
            (!isdir(build_root) || !isempty(readdir(build_root))))
    catch error
        _fatal_exception(error) && rethrow()
        throw(CmdStanError(
            :model_compile,
            _cmdstan_failure_reason(error),
            sprint(showerror, error),
        ))
    end
    cache_unverified && throw(CmdStanError(
        :model_compile,
        :cache_unverified,
        "CmdStan cache reuse is disabled without verified build evidence; " *
        "retain the existing path and explicitly select a new empty cmdstan_cache_dir",
    ))
    try
        mkpath(build_root)
    catch error
        _fatal_exception(error) && rethrow()
        throw(CmdStanError(
            :model_compile,
            _cmdstan_failure_reason(error),
            sprint(showerror, error),
        ))
    end
    model_stem = joinpath(build_root, "bayesian_mgmfrm_" * string(family))
    copied_source = model_stem * ".stan"
    executable = _cmdstan_executable_path(model_stem)
    try
        if family in (:mgmfrm, :mfrm_fixed_q, :mfrm_correlated_2d)
            # Flatten the one package-owned include; no external include search path.
            shared = read(joinpath(dirname(source), "mgmfrm_functions.stan"), String)
            contents = replace(read(source, String), "#include mgmfrm_functions.stan\n" => shared)
            mktemp() do path, io
                write(io, contents)
                close(io)
                cp(path, copied_source; force = false)
            end
        else
            cp(source, copied_source; force = false)
        end
    catch error
        _fatal_exception(error) && rethrow()
        throw(CmdStanError(
            :model_compile,
            _cmdstan_failure_reason(error),
            sprint(showerror, error),
        ))
    end
    command = Cmd(`$make_program -f makefile $model_stem`; dir = root)
    _cmdstan_run(command, :model_compile)
    return (; path = executable, sha256 = _cmdstan_executable_sha256(executable, :model_compile))
end

_cmdstan_compile_mfrm(check; cache_dir = nothing) =
    _cmdstan_compile_model(check, :mfrm; cache_dir)

_cmdstan_compile_gmfrm(check; cache_dir = nothing) =
    _cmdstan_compile_model(check, :gmfrm; cache_dir)

_cmdstan_compile_mgmfrm(check; cache_dir = nothing) =
    _cmdstan_compile_model(check, :mgmfrm; cache_dir)

function _cmdstan_parse_number(value::AbstractString, row::Int, column::Int)
    normalized = lowercase(strip(value))
    normalized in ("nan", "+nan", "-nan") && return NaN
    normalized in ("inf", "+inf", "infinity", "+infinity") && return Inf
    normalized in ("-inf", "-infinity") && return -Inf
    parsed = tryparse(Float64, normalized)
    parsed === nothing && throw(CmdStanError(
        :output_parse,
        :invalid_numeric_value,
        "CSV row $row column $column is not numeric",
    ))
    return parsed
end

function _cmdstan_read_csv(path::AbstractString, expected_draws::Int; warmup::Int = 0)
    warmup >= 0 || throw(ArgumentError("warmup must be nonnegative"))
    header = nothing
    rows = Vector{Vector{Float64}}()
    adaptation_end = nothing
    try
        for line in eachline(path)
            stripped = strip(line)
            isempty(stripped) && continue
            if warmup > 0 && stripped == "# Adaptation terminated"
                adaptation_end === nothing || throw(CmdStanError(
                    :output_parse, :warmup_boundary_mismatch, "duplicate warmup boundary"))
                adaptation_end = length(rows)
            end
            startswith(stripped, '#') && continue
            fields = split(stripped, ',')
            if header === nothing
                header = String.(strip.(fields))
                length(unique(header)) == length(header) ||
                    throw(CmdStanError(
                        :output_parse,
                        :duplicate_columns,
                        "CmdStan CSV contains duplicate column names",
                    ))
                continue
            end
            length(fields) == length(header) || throw(CmdStanError(
                :output_parse,
                :column_count_mismatch,
                "CSV draw row $(length(rows) + 1) has $(length(fields)) " *
                "columns; expected $(length(header))",
            ))
            push!(rows, [
                _cmdstan_parse_number(value, length(rows) + 1, column)
                for (column, value) in pairs(fields)
            ])
        end
    catch error
        _fatal_exception(error) && rethrow()
        error isa CmdStanError && rethrow()
        throw(CmdStanError(
            :output_parse,
            _cmdstan_failure_reason(error),
            sprint(showerror, error),
        ))
    end
    header === nothing && throw(CmdStanError(
        :output_parse,
        :header_missing,
        "CmdStan CSV has no header",
    ))
    warmup == 0 || adaptation_end == warmup || throw(CmdStanError(
        :output_parse, :warmup_boundary_mismatch,
        "CmdStan CSV warmup boundary does not match $warmup iterations"))
    length(rows) == expected_draws + warmup || throw(CmdStanError(
        :output_parse,
        :draw_count_mismatch,
        "CmdStan CSV has $(length(rows)) rows; expected $expected_draws retained and $warmup warmup",
    ))
    parsed = (;
        header,
        values = isempty(rows) ? zeros(Float64, 0, length(header)) :
            reduce(vcat, permutedims.(rows)),
    )
    warmup == 0 && return parsed
    return (; header, values = parsed.values[(warmup + 1):end, :],
        warmup_values = parsed.values[1:warmup, :])
end

function _cmdstan_required_column(header::Vector{String}, name::String)
    index = findfirst(==(name), header)
    index === nothing && throw(CmdStanError(
        :output_parse,
        :required_column_missing,
        "CmdStan CSV is missing column $name",
    ))
    return index
end

function _cmdstan_integer_stat(value::Float64, name::String)
    isinteger(value) || throw(CmdStanError(
        :output_parse,
        :invalid_sampler_statistic,
        "CmdStan CSV column $name must contain integer values",
    ))
    try
        return Int(value)
    catch error
        _fatal_exception(error) && rethrow()
        throw(CmdStanError(
            :output_parse,
            _cmdstan_failure_reason(error),
            "CmdStan CSV column $name is outside the supported integer range",
        ))
    end
end

function _cmdstan_raw_chain_result(path::AbstractString,
        nparams::Int,
        nobservations::Int,
        chain::Int,
        ndraws::Int,
        evaluate_draw::Function; warmup::Int = 0)
    parsed = _cmdstan_read_csv(path, ndraws; warmup)
    header = parsed.header
    values = parsed.values
    beta_columns = [
        _cmdstan_required_column(header, "beta.$index")
        for index in 1:nparams
    ]
    log_lik_columns = [
        _cmdstan_required_column(header, "log_lik.$observation")
        for observation in 1:nobservations
    ]
    stat_columns = Dict(
        name => _cmdstan_required_column(header, name)
        for name in (
            "lp__",
            "accept_stat__",
            "stepsize__",
            "treedepth__",
            "n_leapfrog__",
            "divergent__",
            "energy__",
        )
    )
    for (name, column) in stat_columns
        all(isfinite, @view values[:, column]) || throw(CmdStanError(
            :output_parse,
            :nonfinite_sampler_statistic,
            "CmdStan CSV column $name contains a non-finite value",
        ))
    end
    draws = Matrix{Float64}(values[:, beta_columns])
    all(isfinite, draws) || throw(CmdStanError(
        :output_parse,
        :nonfinite_draw,
        "CmdStan returned a non-finite parameter draw",
    ))
    logps = Vector{Float64}(undef, ndraws)
    for row in 1:ndraws
        evaluated = evaluate_draw(@view(draws[row, :]))
        pointwise = evaluated.pointwise
        length(pointwise) == nobservations || throw(CmdStanError(
            :output_parse,
            :pointwise_loglikelihood_length_mismatch,
            "Julia returned $(length(pointwise)) pointwise values; " *
            "expected $nobservations",
        ))
        stan_pointwise = @view values[row, log_lik_columns]
        all(isapprox.(pointwise, stan_pointwise; atol = 1e-8, rtol = 1e-8)) ||
            throw(CmdStanError(
                :output_parse,
                :pointwise_loglikelihood_mismatch,
                "CmdStan and Julia pointwise log likelihoods disagree at " *
                "retained draw $row",
            ))
        logps[row] = evaluated.logposterior
    end
    all(isfinite, logps) || throw(CmdStanError(
        :output_parse,
        :nonfinite_log_posterior,
        "a CmdStan draw has a non-finite Julia log posterior",
    ))
    stats = NamedTuple[]
    for iteration in 1:ndraws
        value(name) = values[iteration, stat_columns[name]]
        push!(stats, (;
            chain,
            iteration,
            is_adapt = false,
            is_accept = missing,
            acceptance_rate = value("accept_stat__"),
            log_density = logps[iteration],
            hamiltonian_energy = value("energy__"),
            hamiltonian_energy_error = missing,
            max_hamiltonian_energy_error = missing,
            n_steps = _cmdstan_integer_stat(
                value("n_leapfrog__"),
                "n_leapfrog__",
            ),
            tree_depth = _cmdstan_integer_stat(
                value("treedepth__"),
                "treedepth__",
            ),
            numerical_error = _cmdstan_integer_stat(
                value("divergent__"),
                "divergent__",
            ) != 0,
            step_size = value("stepsize__"),
            nom_step_size = value("stepsize__"),
            stan_lp = value("lp__"),
        ))
    end
    result = (; draws, logps, stats)
    warmup == 0 && return result
    warmup_stats = [begin
        value(name) = parsed.warmup_values[iteration, stat_columns[name]]
        divergent = _cmdstan_integer_stat(value("divergent__"), "divergent__")
        divergent in (0, 1) || throw(CmdStanError(
            :output_parse, :invalid_sampler_statistic, "warmup divergent__ must be 0 or 1"))
        _warmup_stat_row((; is_adapt = true, numerical_error = divergent == 1,
            tree_depth = _cmdstan_integer_stat(value("treedepth__"), "treedepth__"),
            log_density = value("lp__")), chain, iteration)
    end for iteration in 1:warmup]
    return merge(result, (; warmup_stats))
end

function _cmdstan_chain_result(path::AbstractString,
        design::FacetDesign,
        prior::MFRMPrior,
        chain::Int,
        ndraws::Int; warmup::Int = 0)
    evaluate_draw = function(raw)
        pointwise = _pointwise_loglikelihood_unchecked(design, raw)
        return (;
            pointwise,
            logposterior = sum(pointwise) +
                _logprior_unchecked(design, raw, prior),
        )
    end
    return _cmdstan_raw_chain_result(
        path,
        length(design.parameter_names),
        design.spec.data.n,
        chain,
        ndraws,
        evaluate_draw; warmup,
    )
end

function _cmdstan_gmfrm_chain_result(path::AbstractString,
        target::_GMFRMPromotionCandidateLogDensity,
        chain::Int,
        ndraws::Int; warmup::Int = 0)
    evaluate_draw = function(raw)
        pointwise = _gmfrm_source_pointwise_loglikelihood_from_unconstrained(
            target.design,
            raw,
        )
        return (;
            pointwise,
            logposterior = LogDensityProblems.logdensity(target, raw),
        )
    end
    return _cmdstan_raw_chain_result(
        path,
        target.blueprint.n_parameters,
        target.design.spec.data.n,
        chain,
        ndraws,
        evaluate_draw; warmup,
    )
end

function _cmdstan_mgmfrm_chain_result(path::AbstractString,
        target::_MGMFRMGuardedLocalFitLogDensity,
        chain::Int,
        ndraws::Int;
        density_target = target, warmup::Int = 0)
    evaluate_draw = function(raw)
        pointwise = _mgmfrm_source_pointwise_loglikelihood_from_unconstrained(
            target.design,
            raw,
        )
        return (;
            pointwise,
            logposterior = LogDensityProblems.logdensity(density_target, raw),
        )
    end
    return _cmdstan_raw_chain_result(
        path,
        target.blueprint.n_parameters,
        target.design.spec.data.n,
        chain,
        ndraws,
        evaluate_draw; warmup,
    )
end

function _cmdstan_chain_seeds(rng::AbstractRNG, chains::Int)
    seeds = Int[]
    used = Set{UInt32}()
    while length(seeds) < chains
        candidate = rand(rng, UInt32)
        candidate == 0 && continue
        candidate in used && continue
        push!(used, candidate)
        push!(seeds, Int(candidate))
    end
    return seeds
end

function _cmdstan_sample_command(executable::AbstractString;
        expected_sha256::AbstractString,
        ndraws::Int,
        warmup::Int,
        step_size::Float64,
        target_accept::Float64,
        max_depth::Int,
        metric::String,
        data_path::AbstractString,
        init_path::AbstractString,
        output_path::AbstractString,
        seed::Int,
        chain::Int,
        progress::Bool, record_warmup::Bool = false)
    _cmdstan_executable_sha256(executable, :sampling) == expected_sha256 ||
        throw(CmdStanError(:sampling, :executable_changed,
            "the model executable does not match its observed compile-output SHA-256"))
    arguments = String[
        executable,
        "sample",
        "num_samples=$ndraws",
        "num_warmup=$warmup",
        "save_warmup=$(record_warmup ? 1 : 0)",
        "thin=1",
        "adapt",
        "engaged=$(warmup > 0 ? 1 : 0)",
    ]
    warmup > 0 && push!(arguments, "delta=$target_accept")
    append!(arguments, (
        "algorithm=hmc",
        "engine=nuts",
        "max_depth=$max_depth",
        "metric=$metric",
        "stepsize=$step_size",
        "data",
        "file=$data_path",
        "init=$init_path",
        "random",
        "seed=$seed",
        "id=$chain",
        "output",
        "file=$output_path",
        "refresh=$(progress ? max(1, div(ndraws + warmup, 10)) : 0)",
        "sig_figs=18",
    ))
    return Cmd(arguments)
end

function _cmdstan_sample_chains(
        executable::AbstractString,
        payload,
        initial::Vector{Float64},
        rng::AbstractRNG,
        evaluate_initial::Function,
        parse_chain::Function;
        expected_sha256::AbstractString,
        ndraws::Int,
        warmup::Int,
        chains::Int,
        step_size::Float64,
        target_accept::Float64,
        max_depth::Int,
        metric::String,
        init_jitter::Float64,
        progress::Bool, record_warmup::Bool = false)
    _cmdstan_executable_sha256(executable, :sampling) == expected_sha256 ||
        throw(CmdStanError(:sampling, :executable_changed,
            "the model executable does not match its observed compile-output SHA-256"))
    chain_seeds = _cmdstan_chain_seeds(rng, chains)
    total_draws = ndraws * chains
    nparams = length(initial)
    draws = Matrix{Float64}(undef, total_draws, nparams)
    logdensities = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    chain_acceptance = Vector{Float64}(undef, chains)
    sampler_stats = NamedTuple[]
    warmup_stats = record_warmup ? NamedTuple[] : nothing

    mktempdir() do directory
        data_path = _cmdstan_write_json(
            joinpath(directory, "data.json"),
            payload,
            :data_write,
        )
        for chain in 1:chains
            chain_initial = _with_sampler_context(:cmdstan, chain, :initialization) do
                values = _advancedhmc_initial(initial, rng, init_jitter)
                isfinite(evaluate_initial(values)) || throw(ArgumentError(
                    "chain $chain initial parameter vector has non-finite log density",
                ))
                values
            end
            init_path = _with_sampler_context(:cmdstan, chain, :initialization_write) do
                _cmdstan_write_json(
                    joinpath(directory, "init-$chain.json"),
                    (; beta = chain_initial),
                    :initialization_write,
                )
            end
            output_path = joinpath(directory, "chain-$chain.csv")
            command = _cmdstan_sample_command(executable;
                expected_sha256,
                ndraws,
                warmup,
                step_size,
                target_accept,
                max_depth,
                metric,
                data_path,
                init_path,
                output_path,
                seed = chain_seeds[chain],
                chain,
                progress,
                record_warmup,
            )
            _with_sampler_context(:cmdstan, chain, :sampling) do
                _cmdstan_run(command, :sampling; show_output = progress)
            end
            result = _with_sampler_context(:cmdstan, chain, :output_parse) do
                parse_chain(output_path, chain, ndraws)
            end
            _with_sampler_context(:cmdstan, chain, :output_validation) do
                size(result.draws) == (ndraws, nparams) || throw(ArgumentError(
                    "CmdStan draws have size $(size(result.draws)); expected ($ndraws, $nparams)"))
                length(result.logps) == ndraws && length(result.stats) == ndraws ||
                    throw(ArgumentError("CmdStan log density and sampler statistics must each have $ndraws rows"))
                rows = ((chain - 1) * ndraws + 1):(chain * ndraws)
                draws[rows, :] .= result.draws
                logdensities[rows] .= result.logps
                all(isfinite, @view draws[rows, :]) && all(isfinite, @view logdensities[rows]) ||
                    throw(ArgumentError("CmdStan retained output contains non-finite values"))
                chain_ids[rows] .= chain
                iterations[rows] .= 1:ndraws
                append!(sampler_stats, result.stats)
                chain_acceptance[chain] =
                    _stat_mean(result.stats, :acceptance_rate)
                if record_warmup && warmup > 0
                    length(result.warmup_stats) == warmup ||
                        throw(ArgumentError("CmdStan warmup statistic count mismatch"))
                    append!(warmup_stats, result.warmup_stats)
                end
            end
        end
    end
    result = (;
        chain_seeds,
        draws,
        logdensities,
        chain_ids,
        iterations,
        chain_acceptance,
        sampler_stats,
    )
    return record_warmup ? merge(result, (; warmup_stats)) : result
end

function _fit_cmdstan(design::FacetDesign,
        prior::MFRMPrior,
        ndraws::Int,
        warmup::Int,
        chains::Int,
        step::Float64,
        initial::Vector{Float64},
        rng::AbstractRNG,
        rng_control::NamedTuple;
        target_accept::Real,
        max_depth::Int,
        max_energy_error::Real,
        metric::Symbol,
        ad_backend::Symbol,
        init_jitter::Real,
        progress::Bool,
        cmdstan_path,
        cmdstan_cache_dir,
        record_warmup::Bool = false)
    max_energy_error == 1000.0 || throw(ArgumentError(
        "backend = :cmdstan uses Stan's fixed divergence threshold; " *
        "max_energy_error must remain 1000.0",
    ))
    ad_backend === :ForwardDiff || throw(ArgumentError(
        "ad_backend does not select CmdStan's automatic differentiation; " *
        "leave ad_backend = :ForwardDiff for backend = :cmdstan",
    ))
    target_accept, max_energy_error, init_jitter =
        _check_nuts_controls(target_accept, max_depth, max_energy_error, init_jitter)
    metric_name = _cmdstan_metric(metric)
    isfinite(_logposterior_unchecked(design, initial, prior)) ||
        throw(ArgumentError("initial parameter vector has non-finite log posterior"))
    check = cmdstan_backend_check(;
        cmdstan_path,
        include_paths = true,
        require_ready = true,
    )
    compiled = _cmdstan_compile_mfrm(check; cache_dir = cmdstan_cache_dir)
    payload = _cmdstan_mfrm_data(design, prior)
    evaluate_initial = raw -> _logposterior_unchecked(design, raw, prior)
    parse_chain = (path, chain, count) ->
        _cmdstan_chain_result(path, design, prior, chain, count;
            warmup = record_warmup ? warmup : 0)
    run = _cmdstan_sample_chains(
        compiled.path,
        payload,
        initial,
        rng,
        evaluate_initial,
        parse_chain;
        expected_sha256 = compiled.sha256,
        ndraws,
        warmup,
        chains,
        step_size = step,
        target_accept = Float64(target_accept),
        max_depth,
        metric = metric_name,
        init_jitter = Float64(init_jitter),
        progress,
        (record_warmup ? (; record_warmup = true) : NamedTuple())...,
    )

    controls = (;
        ndraws,
        warmup,
        chains,
        step_size = step,
        target_accept = Float64(target_accept),
        max_depth,
        max_energy_error = 1000.0,
        metric,
        ad_backend = :stan_reverse_mode,
        gradient_backend = :stan_autodiff,
        rng = merge(rng_control, (; chain_seeds = Tuple(run.chain_seeds))),
        init_jitter = Float64(init_jitter),
        thinning = 1,
        cmdstan_version = check.cmdstan_version,
        cmdstan_executable_sha256 = compiled.sha256,
        execution = :cmdstan_cli,
    )
    return MFRMFit(
        design,
        prior,
        run.draws,
        run.logdensities,
        _column_mean(run.chain_acceptance),
        run.chain_ids,
        run.iterations,
        run.chain_acceptance,
        :cmdstan,
        :nuts,
        warmup,
        _stat_mean(run.sampler_stats, :step_size),
        run.sampler_stats,
        record_warmup ? _with_warmup_diagnostics(controls, run.warmup_stats, :cmdstan) : controls,
    )
end

_cmdstan_generalized_family(::_GMFRMPromotionCandidateLogDensity) = :gmfrm
_cmdstan_generalized_family(::_MGMFRMGuardedLocalFitLogDensity) = :mgmfrm

_cmdstan_generalized_data(target::_GMFRMPromotionCandidateLogDensity) =
    _cmdstan_gmfrm_data(target)

_cmdstan_generalized_data(target::_MGMFRMGuardedLocalFitLogDensity) =
    _cmdstan_mgmfrm_data(target)

_cmdstan_generalized_chain_result(path::AbstractString,
        target::_GMFRMPromotionCandidateLogDensity,
        chain::Int,
        ndraws::Int; warmup::Int = 0) =
    _cmdstan_gmfrm_chain_result(path, target, chain, ndraws; warmup)

_cmdstan_generalized_chain_result(path::AbstractString,
        target::_MGMFRMGuardedLocalFitLogDensity,
        chain::Int,
        ndraws::Int; warmup::Int = 0) =
    _cmdstan_mgmfrm_chain_result(path, target, chain, ndraws; warmup)

function _cmdstan_generalized_candidate_run(
        target,
        raw_initial::AbstractVector = initial_params(target);
        ndraws::Int = _GENERALIZED_DEFAULT_RETAINED_DRAWS_PER_CHAIN,
        warmup::Int = _GENERALIZED_DEFAULT_WARMUP_PER_CHAIN,
        chains::Int = _GENERALIZED_DEFAULT_CHAINS,
        step_size::Real = 0.03,
        rng::AbstractRNG = Random.default_rng(),
        seed = nothing,
        target_accept::Real = 0.8,
        max_depth::Int = 10,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400,
        progress::Bool = false,
        cmdstan_path::Union{Nothing,AbstractString} = nothing,
        cmdstan_cache_dir::Union{Nothing,AbstractString} = nothing,
        record_warmup::Bool = false)
    step_size = _check_fit_controls(ndraws, warmup, chains, step_size)

    max_energy_error == 1000.0 || throw(ArgumentError(
        "backend = :cmdstan uses Stan's fixed divergence threshold; " *
        "max_energy_error must remain 1000.0",
    ))
    ad_backend === :ForwardDiff || throw(ArgumentError(
        "ad_backend does not select CmdStan's automatic differentiation; " *
        "leave ad_backend = :ForwardDiff for backend = :cmdstan",
    ))
    target_accept, max_energy_error, init_jitter =
        _check_nuts_controls(target_accept, max_depth, max_energy_error, init_jitter)
    checked = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    _check_source_fixture_raw_vector(target, raw_initial)
    metric_name = _cmdstan_metric(metric)

    initial = Float64.(collect(raw_initial))
    initial_logdensity = LogDensityProblems.logdensity(target, initial)
    isfinite(initial_logdensity) || throw(ArgumentError(
        "initial raw parameter vector has non-finite log density",
    ))
    fit_rng, rng_control = _fit_rng(rng, seed)
    check = cmdstan_backend_check(;
        cmdstan_path,
        include_paths = true,
        require_ready = true,
    )
    compiled = _cmdstan_compile_model(
        check,
        _cmdstan_generalized_family(target);
        cache_dir = cmdstan_cache_dir,
    )
    payload = _cmdstan_generalized_data(target)
    nparams = LogDensityProblems.dimension(target)
    total_draws = ndraws * chains
    evaluate_initial = raw -> LogDensityProblems.logdensity(target, raw)
    parse_chain = (path, chain, count) ->
        _cmdstan_generalized_chain_result(path, target, chain, count;
            warmup = record_warmup ? warmup : 0)
    sampled = _cmdstan_sample_chains(
        compiled.path,
        payload,
        initial,
        fit_rng,
        evaluate_initial,
        parse_chain;
        expected_sha256 = compiled.sha256,
        ndraws,
        warmup,
        chains,
        step_size = Float64(step_size),
        target_accept = Float64(target_accept),
        max_depth,
        metric = metric_name,
        init_jitter = Float64(init_jitter),
        progress,
        (record_warmup ? (; record_warmup = true) : (;))...,
    )

    controls = (;
        ndraws,
        warmup,
        chains,
        step_size = Float64(step_size),
        target_accept = Float64(target_accept),
        max_depth,
        max_energy_error = 1000.0,
        metric,
        ad_backend = :stan_reverse_mode,
        gradient_backend = :stan_autodiff,
        rng = merge(rng_control, (; chain_seeds = Tuple(sampled.chain_seeds))),
        init_jitter = Float64(init_jitter),
        thinning = 1,
        cmdstan_version = check.cmdstan_version,
        cmdstan_executable_sha256 = compiled.sha256,
        execution = :cmdstan_cli,
    )
    sampler_rows = _generalized_candidate_sampler_rows(
        sampled.logdensities,
        sampled.iterations,
        sampled.chain_acceptance,
        sampled.sampler_stats,
        controls,
        :cmdstan,
    )
    run = (;
        checked,
        nparams,
        initial,
        initial_logdensity,
        total_draws,
        draws = sampled.draws,
        logdensities = sampled.logdensities,
        chain_ids = sampled.chain_ids,
        iterations = sampled.iterations,
        chain_acceptance = sampled.chain_acceptance,
        sampler_stats = sampled.sampler_stats,
        controls,
        sampler_rows,
        backend = :cmdstan,
        sampler = :nuts,
        split_chains_requested = split_chains,
        actual_split = split_chains && chains >= 2 && ndraws >= 4,
    )
    return record_warmup ? merge(run, (; warmup_stats = sampled.warmup_stats)) : run
end

function _cmdstan_gmfrm_sampler_diagnostics(
        target::_GMFRMPromotionCandidateLogDensity,
        raw_initial::AbstractVector = initial_params(target);
        kwargs...)
    run = _cmdstan_generalized_candidate_run(target, raw_initial; kwargs...)
    return _gmfrm_promotion_candidate_diagnostic_surface(target, run)
end

function _cmdstan_mgmfrm_sampler_diagnostics(
        target::_MGMFRMGuardedLocalFitLogDensity,
        raw_initial::AbstractVector = initial_params(target);
        initial_source::Symbol = :sampler_raw_initial_argument,
        kwargs...)
    run = _cmdstan_generalized_candidate_run(target, raw_initial; kwargs...)
    return _mgmfrm_guarded_local_fit_diagnostic_surface(
        target,
        run;
        initial_source,
    )
end
