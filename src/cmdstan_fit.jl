# cmdstan_fit.jl -- direct CmdStan CLI adapter for stable MFRM/RSM/PCM fits.

import JSON3

function _cmdstan_mfrm_source()
    module_path = pathof(BayesianMGMFRM)
    module_path === nothing && throw(CmdStanError(
        :model_compile,
        :package_path_unavailable,
        "the loaded package source path is unavailable",
    ))
    return joinpath(dirname(module_path), "stan", "mfrm.stan")
end

function _cmdstan_failure_reason(error)
    error isa Base.ProcessFailedException && return :command_failed
    error isa Base.IOError && return :io_error
    error isa ArgumentError && return :invalid_value
    return :unexpected_error
end

function _cmdstan_short_detail(text::AbstractString; limit::Int = 2000)
    cleaned = strip(text)
    isempty(cleaned) && return "no command diagnostic was produced"
    length(cleaned) <= limit && return cleaned
    return "…" * last(cleaned, limit)
end

function _cmdstan_run(command::Cmd, stage::Symbol; show_output::Bool = false)
    if show_output
        process = try
            run(ignorestatus(command))
        catch error
            throw(CmdStanError(
                stage,
                _cmdstan_failure_reason(error),
                sprint(showerror, error),
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
                run(pipeline(ignorestatus(command); stdout = io, stderr = io))
            end
        catch error
            throw(CmdStanError(
                stage,
                _cmdstan_failure_reason(error),
                sprint(showerror, error),
            ))
        end
        success(process) && return nothing
        detail = try
            read(log_path, String)
        catch error
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

function _cmdstan_write_json(path::AbstractString, value, stage::Symbol)
    try
        open(path, "w") do io
            JSON3.write(io, value)
        end
    catch error
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

function _cmdstan_compile_mfrm(check; cache_dir = nothing)
    source = _cmdstan_mfrm_source()
    isfile(source) || throw(CmdStanError(
        :model_compile,
        :model_source_missing,
        "the package-owned MFRM Stan source is unavailable",
    ))
    root = check.cmdstan_root
    root isa AbstractString || throw(CmdStanError(
        :model_compile,
        :runtime_unavailable,
        "CmdStan root was not retained by the runtime check",
    ))
    make_program = _cmdstan_configured_program("MAKE", ("make", "gmake"))
    make_program === nothing && throw(CmdStanError(
        :model_compile,
        :make_unavailable,
        "make or gmake was not found",
    ))
    build_root = _cmdstan_cache_root(check, cache_dir)
    try
        mkpath(build_root)
    catch error
        throw(CmdStanError(
            :model_compile,
            _cmdstan_failure_reason(error),
            sprint(showerror, error),
        ))
    end
    model_stem = joinpath(build_root, "bayesian_mgmfrm_mfrm")
    copied_source = model_stem * ".stan"
    executable = _cmdstan_executable_path(model_stem)
    source_is_current = try
        isfile(copied_source) && read(copied_source) == read(source)
    catch error
        throw(CmdStanError(
            :model_compile,
            _cmdstan_failure_reason(error),
            sprint(showerror, error),
        ))
    end
    executable_is_current = try
        source_is_current && isfile(executable) &&
            mtime(executable) >= mtime(copied_source)
    catch error
        throw(CmdStanError(
            :model_compile,
            _cmdstan_failure_reason(error),
            sprint(showerror, error),
        ))
    end
    executable_is_current && return executable
    try
        cp(source, copied_source; force = true)
    catch error
        throw(CmdStanError(
            :model_compile,
            _cmdstan_failure_reason(error),
            sprint(showerror, error),
        ))
    end
    command = Cmd(`$make_program $model_stem`; dir = root)
    _cmdstan_run(command, :model_compile)
    isfile(executable) || throw(CmdStanError(
        :model_compile,
        :executable_missing,
        "CmdStan reported success without producing the model executable",
    ))
    return executable
end

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

function _cmdstan_read_csv(path::AbstractString, expected_draws::Int)
    header = nothing
    rows = Vector{Vector{Float64}}()
    try
        for line in eachline(path)
            stripped = strip(line)
            isempty(stripped) && continue
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
    length(rows) == expected_draws || throw(CmdStanError(
        :output_parse,
        :draw_count_mismatch,
        "CmdStan CSV has $(length(rows)) retained draws; expected $expected_draws",
    ))
    return (;
        header,
        values = isempty(rows) ? zeros(Float64, 0, length(header)) :
            reduce(vcat, permutedims.(rows)),
    )
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
        throw(CmdStanError(
            :output_parse,
            _cmdstan_failure_reason(error),
            "CmdStan CSV column $name is outside the supported integer range",
        ))
    end
end

function _cmdstan_chain_result(path::AbstractString,
        design::FacetDesign,
        prior::MFRMPrior,
        chain::Int,
        ndraws::Int)
    parsed = _cmdstan_read_csv(path, ndraws)
    header = parsed.header
    values = parsed.values
    nparams = length(design.parameter_names)
    beta_columns = [
        _cmdstan_required_column(header, "beta.$index")
        for index in 1:nparams
    ]
    log_lik_columns = [
        _cmdstan_required_column(header, "log_lik.$observation")
        for observation in 1:design.spec.data.n
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
        "CmdStan returned a non-finite identified parameter draw",
    ))
    logps = Vector{Float64}(undef, ndraws)
    for row in 1:ndraws
        pointwise = _pointwise_loglikelihood_unchecked(
            design,
            @view(draws[row, :]),
        )
        stan_pointwise = @view values[row, log_lik_columns]
        all(isapprox.(pointwise, stan_pointwise; atol = 1e-8, rtol = 1e-8)) ||
            throw(CmdStanError(
                :output_parse,
                :pointwise_loglikelihood_mismatch,
                "CmdStan and Julia pointwise log likelihoods disagree at " *
                "retained draw $row",
            ))
        logps[row] = sum(pointwise) +
            _logprior_unchecked(design, @view(draws[row, :]), prior)
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
    return (; draws, logps, stats)
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
        progress::Bool)
    arguments = String[
        executable,
        "sample",
        "num_samples=$ndraws",
        "num_warmup=$warmup",
        "save_warmup=0",
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
        cmdstan_cache_dir)
    0 < target_accept < 1 ||
        throw(ArgumentError("target_accept must be in (0, 1)"))
    max_depth >= 1 || throw(ArgumentError("max_depth must be positive"))
    max_energy_error == 1000.0 || throw(ArgumentError(
        "backend = :cmdstan uses Stan's fixed divergence threshold; " *
        "max_energy_error must remain 1000.0",
    ))
    ad_backend === :ForwardDiff || throw(ArgumentError(
        "ad_backend does not select CmdStan's automatic differentiation; " *
        "leave ad_backend = :ForwardDiff for backend = :cmdstan",
    ))
    isfinite(init_jitter) && init_jitter >= 0 ||
        throw(ArgumentError("init_jitter must be finite and non-negative"))
    metric_name = _cmdstan_metric(metric)
    check = cmdstan_backend_check(;
        cmdstan_path,
        include_paths = true,
        require_ready = true,
    )
    executable = _cmdstan_compile_mfrm(check; cache_dir = cmdstan_cache_dir)
    payload = _cmdstan_mfrm_data(design, prior)
    chain_seeds = _cmdstan_chain_seeds(rng, chains)
    total_draws = ndraws * chains
    nparams = length(design.parameter_names)
    draws = Matrix{Float64}(undef, total_draws, nparams)
    logps = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    chain_acceptance = Vector{Float64}(undef, chains)
    sampler_stats = NamedTuple[]

    mktempdir() do directory
        data_path = _cmdstan_write_json(
            joinpath(directory, "data.json"),
            payload,
            :data_write,
        )
        for chain in 1:chains
            chain_initial = _advancedhmc_initial(initial, rng, Float64(init_jitter))
            isfinite(_logposterior_unchecked(design, chain_initial, prior)) ||
                throw(ArgumentError(
                    "initial parameter vector has non-finite log posterior",
                ))
            init_path = _cmdstan_write_json(
                joinpath(directory, "init-$chain.json"),
                (; beta = chain_initial),
                :initialization_write,
            )
            output_path = joinpath(directory, "chain-$chain.csv")
            command = _cmdstan_sample_command(executable;
                ndraws,
                warmup,
                step_size = step,
                target_accept = Float64(target_accept),
                max_depth,
                metric = metric_name,
                data_path,
                init_path,
                output_path,
                seed = chain_seeds[chain],
                chain,
                progress,
            )
            _cmdstan_run(command, :sampling; show_output = progress)
            result = _cmdstan_chain_result(
                output_path,
                design,
                prior,
                chain,
                ndraws,
            )
            rows = ((chain - 1) * ndraws + 1):(chain * ndraws)
            draws[rows, :] .= result.draws
            logps[rows] .= result.logps
            chain_ids[rows] .= chain
            iterations[rows] .= 1:ndraws
            append!(sampler_stats, result.stats)
            chain_acceptance[chain] = _stat_mean(result.stats, :acceptance_rate)
        end
    end

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
        rng = merge(rng_control, (; chain_seeds = Tuple(chain_seeds))),
        init_jitter = Float64(init_jitter),
        thinning = 1,
        cmdstan_version = check.cmdstan_version,
        execution = :cmdstan_cli,
    )
    return MFRMFit(
        design,
        prior,
        draws,
        logps,
        _column_mean(chain_acceptance),
        chain_ids,
        iterations,
        chain_acceptance,
        :cmdstan,
        :nuts,
        warmup,
        _stat_mean(sampler_stats, :step_size),
        sampler_stats,
        controls,
    )
end
