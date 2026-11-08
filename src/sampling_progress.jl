"""
    SamplingProgress(; io=stderr, path=nothing, interval=1.0)

Track one AdvancedHMC fit with `fit(...; backend=:advancedhmc,
progress=monitor)` or the shared `Experimental.fit` routes. Print a compact
bar to `io` (use `nothing` for silence) and optionally update a JSON file at
`path`. The file must not already exist. Create a new monitor for each fit.

The percentage counts warmup and retained transitions across all chains. It
does not measure convergence, time remaining, diagnostics or saving. At 100%,
`status=:sampling_complete` means the sampler finished; review the fit's
diagnostics separately. Output errors disable the affected output and warn,
without discarding sampling. `progress_snapshot(monitor)` remains available.

`interval` throttles output in seconds; phase changes and termination are
always emitted. Terminals update one line; redirected output uses plain lines.
Boolean `progress=true/false` retains the backend's original behavior. JointRatings
Julia fits also accept this monitor. Other backends and experimental modules
without an explicit progress keyword do not promise this API.
"""
mutable struct SamplingProgress
    io::Union{Nothing,IO}
    path::Union{Nothing,String}
    interval::Float64
    published::Bool
    state::NamedTuple
    started::UInt64
    emitted::UInt64
    guard::ReentrantLock
    function SamplingProgress(; io::Union{Nothing,IO}=stderr, path=nothing,
            interval::Real=1.0)
        dt = Float64(interval)
        isfinite(dt) && dt >= 0 || throw(ArgumentError("interval must be finite and nonnegative"))
        path === nothing || path isa AbstractString || throw(ArgumentError("path must be a string or nothing"))
        path === nothing || !isempty(strip(path)) || throw(ArgumentError("path must not be empty"))
        destination = path === nothing ? nothing : abspath(path)
        destination === nothing || !(ispath(destination) || islink(destination)) ||
            throw(ArgumentError("progress path already exists; choose a new file"))
        state = (; schema="bayesianmgmfrm.sampling_progress.v1", status=:idle,
            phase=:initialization, chain=0, chains=0, iteration=0, chain_total=0,
            phase_completed=0, phase_total=0, completed=0, total=0, percent=0.0,
            chain_completed=(),
            elapsed_seconds=0.0, updated_at_unix=time(), output_errors=())
        new(io, destination, dt, false, state, UInt64(0), UInt64(0), ReentrantLock())
    end
end

"""
    progress_snapshot(monitor::SamplingProgress)

Return an immutable, thread-safe snapshot of the last reported sampling event:
status, chain, warmup/sampling phase, phase and overall counts, percent, elapsed
seconds and update timestamp. Read this from another task while fitting, or
read the monitor's optional JSON file from another process. No posterior values
are included. The snapshot is not a convergence diagnostic or resumable fit.
"""
progress_snapshot(p::SamplingProgress) = lock(p.guard) do
    p.state
end

_check_sampling_progress(::Bool, backend) = nothing
function _check_sampling_progress(::SamplingProgress, backend)
    backend === :advancedhmc || throw(ArgumentError(
        "SamplingProgress requires backend=:advancedhmc; use Boolean progress for other backends"))
    return nothing
end

function _progress_output_error!(p, sink, err)
    _fatal_exception(err) && throw(err)
    p.state = merge(p.state, (; output_errors=(p.state.output_errors...,
        "$sink: $(sprint(showerror, err))")))
    @warn "Sampling progress output failed; sampling continues." output=sink exception=err
end

function _publish_progress!(p; force=false)
    now = time_ns()
    !force && p.emitted != 0 && (now-p.emitted)/1e9 < p.interval && return nothing
    p.emitted = now
    s = p.state
    if p.io !== nothing
        try
            filled = clamp(floor(Int, s.percent/5), 0, 20)
            bar = repeat("#", filled)*repeat("-", 20-filled)
            line = "Sampling [$bar] $(round(s.percent; digits=1))% | chain $(s.chain)/$(s.chains) | " *
                "$(s.phase) $(s.phase_completed)/$(s.phase_total) | $(round(s.elapsed_seconds; digits=1))s | $(s.status)"
            terminal = p.io isa Base.TTY
            print(p.io, terminal ? "\r\e[K" : "", line)
            (!terminal || s.status !== :running) && println(p.io)
            flush(p.io)
        catch err
            _progress_output_error!(p, :io, err)
            p.io = nothing
        end
    end
    if p.path !== nothing
        temporary = nothing
        try
            mkpath(dirname(p.path))
            temporary, io = mktemp(dirname(p.path))
            try
                JSON3.write(io, p.state)
                println(io)
            finally
                close(io)
            end
            if p.published
                # Match native cache publication; never copy/remove on failure.
                err = ccall(:jl_fs_rename, Int32, (Cstring, Cstring), temporary, p.path)
                err < 0 && Base.uv_error("sampling progress rename", err)
            else
                # Claim a new destination without overwriting a racing writer.
                hardlink(temporary, p.path)
                p.published = true
            end
        catch err
            _progress_output_error!(p, :file, err)
            p.path = nothing
        finally
            if temporary !== nothing && isfile(temporary)
                try
                    rm(temporary)
                catch err
                    _progress_output_error!(p, :temporary_file, err)
                end
            end
        end
    end
    return nothing
end

function _progress_state!(p; force=false, kwargs...)
    lock(p.guard) do
        previous_phase = p.state.phase
        p.state = merge(p.state, (; kwargs...),
            (; elapsed_seconds=(time_ns()-p.started)/1e9, updated_at_unix=time()))
        _publish_progress!(p; force=force || p.state.phase !== previous_phase)
    end
    return nothing
end

_with_sampling_progress(f, ::Bool, chains, warmup, ndraws) = f()
function _with_sampling_progress(f, p::SamplingProgress, chains, warmup, ndraws)
    lock(p.guard) do
        p.state.status === :idle || throw(ArgumentError("use a new SamplingProgress for each fit"))
        p.path === nothing || !(ispath(p.path) || islink(p.path)) ||
            throw(ArgumentError("progress path already exists; choose a new file"))
        p.started = time_ns()
        _progress_state!(p; force=true, status=:running, chains,
            chain_total=warmup+ndraws, total=chains*(warmup+ndraws),
            chain_completed=ntuple(_ -> 0, chains))
    end
    try
        result = f()
        _progress_state!(p; force=true, status=:sampling_complete)
        return result
    catch err
        _progress_state!(p; force=true, status=err isa InterruptException ? :interrupted : :failed)
        rethrow()
    end
end

_progress_chain!(::Bool, chain, warmup, ndraws) = nothing
function _progress_chain!(p::SamplingProgress, chain, warmup, ndraws)
    _progress_state!(p; force=true, chain, iteration=0, phase=:initialization,
        phase_completed=0, phase_total=0)
end

function _progress_transition!(p::SamplingProgress, chain, iteration, warmup, ndraws)
    lock(p.guard) do
        1 <= chain <= p.state.chains || throw(ArgumentError("invalid progress chain"))
        0 <= iteration <= warmup+ndraws || throw(ArgumentError("invalid progress iteration"))
        counts = Base.setindex(p.state.chain_completed,
            max(p.state.chain_completed[chain], iteration), chain)
        completed = sum(counts)
        phase = iteration <= warmup ? :warmup : :sampling
        _progress_state!(p; phase, chain, iteration, completed, chain_completed=counts,
            phase_completed=phase === :warmup ? iteration : iteration-warmup,
            phase_total=phase === :warmup ? warmup : ndraws,
            percent=100*completed/p.state.total,
            force=iteration == warmup || iteration == warmup+ndraws)
    end
end

function _advancedhmc_progress_options(progress, chain, warmup, ndraws, observer=nothing)
    progress isa Bool && observer === nothing && return (; progress)
    notify = function(pm, stat)
        observer === nothing || observer((; phase=:transition, chain, stat))
        if progress isa SamplingProgress
            _progress_transition!(progress, chain, stat.iterations, warmup, ndraws)
        elseif progress
            AdvancedHMC.pm_next!(pm, stat)
        end
        return nothing
    end
    return (; progress=true, pm_next! = notify)
end
