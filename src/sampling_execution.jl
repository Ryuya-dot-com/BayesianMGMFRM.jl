# Keep legacy streams unchanged; threaded runs partition RNGs by chain, never worker.
function _check_chain_execution(mode::Symbol, limit::Int, backend::Symbol=:advancedhmc; allow_auto::Bool=false)
    valid = allow_auto ? (mode in (:serial, :threads, :auto)) : (mode in (:serial, :threads))
    valid || throw(ArgumentError(allow_auto ?
        "chain_execution must be :serial, :threads, or :auto" :
        "chain_execution must be :serial or :threads"))
    limit >= 1 || throw(ArgumentError("max_parallel_chains must be positive"))
    mode === :threads && backend !== :advancedhmc && throw(ArgumentError(
        "threaded chains currently require backend=:advancedhmc"))
    return nothing
end

function _resolve_chain_execution(mode::Symbol, chains::Int, limit::Int, backend::Symbol=:advancedhmc)
    mode === :auto || return mode
    return (backend === :advancedhmc && chains > 1 && limit > 1 && Threads.nthreads(:default) > 1) ? :threads : :serial
end

function _sampling_chain_schedule(rng, chains, mode, limit, backend::Symbol=:advancedhmc)
    _check_chain_execution(mode, limit, backend; allow_auto=true)
    eff_mode = _resolve_chain_execution(mode, chains, limit, backend)
    eff_mode === :serial && return (; mode=eff_mode, workers=1, rngs=nothing, metadata=(;))
    seeds = Int[]
    while length(seeds) < chains
        seed = rand(rng, 0:typemax(Int))
        seed in seeds || push!(seeds, seed)
    end
    workers = min(chains, limit, Threads.nthreads(:default))
    metadata = (; chain_execution=(; mode=eff_mode, workers, rng_partition=:chain_seed_v1,
        chain_seeds=Tuple(seeds)))
    return (; mode=eff_mode, workers, rngs=[MersenneTwister(seed) for seed in seeds], metadata)
end

function _foreach_sampling_chain(f, schedule, chains, serial_rng)
    if schedule.mode === :serial
        for chain in 1:chains
            f(chain, serial_rng, nothing)
        end
        return nothing
    end
    cancelled = Threads.Atomic{Bool}(false)
    next_chain = Threads.Atomic{Int}(1)
    failure = Ref{Any}(nothing)
    guard = ReentrantLock()
    tasks = Task[]
    try
        for _ in 1:schedule.workers
            push!(tasks, Threads.@spawn begin
                while !cancelled[]
                    chain = Threads.atomic_add!(next_chain, 1)
                    chain > chains && break
                    try
                        task_local_storage(:bayesianmgmfrm_active_chains, schedule.workers) do
                            f(chain, schedule.rngs[chain], cancelled)
                        end
                    catch err
                        lock(guard) do
                            failure[] === nothing && (failure[] = err)
                            cancelled[] = true
                        end
                        break
                    end
                end
            end)
        end
        foreach(fetch, tasks)
    finally
        # Also join after a caller interruption; no sampler may outlive its fit.
        cancelled[] = true
        foreach(wait, tasks)
    end
    failure[] === nothing || throw(failure[])
    return nothing
end

# Independent ranges write disjoint outputs; reductions retain their original row order.
function _parallel_ranges(f, n::Int, n_obs::Int)
    chains = get(task_local_storage(), :bayesianmgmfrm_active_chains, 1)::Int
    workers = n_obs < 8000 ? 1 : min(n, max(1, Threads.nthreads(:default) ÷ chains))
    if workers <= 1
        f(1:n)
    else
        @sync for j in 1:workers
            rows = (fld((j-1)*n, workers)+1):fld(j*n, workers)
            Threads.@spawn f(rows)
        end
    end
    return nothing
end

function _sampling_chain_observer(observer, cancelled, guard)
    cancelled === nothing && return observer
    return event -> begin
        cancelled[] && throw(InterruptException())
        observer === nothing || lock(guard) do
            observer(event)
        end
        nothing
    end
end

_threaded_progress(progress, mode) = mode === :threads && progress === true ? SamplingProgress() : progress
