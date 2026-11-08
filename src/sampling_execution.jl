# Keep legacy streams unchanged; threaded runs partition RNGs by chain, never worker.
function _check_chain_execution(mode::Symbol, limit::Int, backend::Symbol=:advancedhmc)
    mode in (:serial, :threads) || throw(ArgumentError("chain_execution must be :serial or :threads"))
    limit >= 1 || throw(ArgumentError("max_parallel_chains must be positive"))
    mode === :threads && backend !== :advancedhmc && throw(ArgumentError(
        "threaded chains currently require backend=:advancedhmc"))
    return nothing
end

function _sampling_chain_schedule(rng, chains, mode, limit)
    _check_chain_execution(mode, limit)
    mode === :serial && return (; mode, workers=1, rngs=nothing, metadata=(;))
    seeds = Int[]
    while length(seeds) < chains
        seed = rand(rng, 0:typemax(Int))
        seed in seeds || push!(seeds, seed)
    end
    workers = min(chains, limit, Threads.nthreads(:default))
    metadata = (; chain_execution=(; mode, workers, rng_partition=:chain_seed_v1,
        chain_seeds=Tuple(seeds)))
    return (; mode, workers, rngs=[MersenneTwister(seed) for seed in seeds], metadata)
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
                        f(chain, schedule.rngs[chain], cancelled)
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
