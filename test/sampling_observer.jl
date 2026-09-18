# Standalone check and part of the generalized test group.
isdefined(@__MODULE__, :MFRMCorrelated2DChecks) || include("mfrm_correlated_2d.jl")
module SamplingObserverChecks
using Test, Random, Logging, BayesianMGMFRM
using ..MFRMCorrelated2DChecks: specification, PRIOR
const B = BayesianMGMFRM

@testset "private sampling observer preserves trajectories" begin
    target = B._MFRMFixedQCorrelated2DLogDensity(specification(); prior=PRIOR)
    initial = initial_params(target)
    for metric in (:diagonal, :dense), warmup in (0, 120), record_warmup in (false, true)
        options = (; metric, warmup, record_warmup, chains=2, ndraws=8,
            max_depth=3, init_jitter=0.1, progress=false)
        plain_rng, observed_rng = MersenneTwister(918), MersenneTwister(918)
        events = NamedTuple[]
        observer = event -> push!(events, event.phase === :transition ?
            (; event.phase, event.chain, iteration=event.stat.iterations,
                is_adapt=event.stat.is_adapt, n_steps=event.stat.n_steps) : event)
        plain, observed = with_logger(NullLogger()) do
            (B._run_generalized_candidate_advancedhmc(target, initial; rng=plain_rng, options...),
             B._run_generalized_candidate_advancedhmc(target, initial; rng=observed_rng,
                options..., _sampling_observer=observer))
        end
        @test isequal(plain, observed)
        @test rand(plain_rng, 10) == rand(observed_rng, 10)
        @test length(events) == 2 * (warmup + 8 + 2)
        for chain in 1:2
            chain_events = filter(e -> e.chain == chain, events)
            @test first(chain_events).phase === :sampling_start
            @test last(chain_events).phase === :sampling_end
            transitions = chain_events[2:end-1]
            @test getproperty.(transitions, :iteration) == 1:(warmup+8)
            @test getproperty.(transitions, :is_adapt) == [trues(warmup); falses(8)]
            retained = filter(r -> r.chain == chain, observed.sampler_stats)
            @test getproperty.(transitions[warmup+1:end], :n_steps) == getproperty.(retained, :n_steps)
        end
    end
    @test_throws ArgumentError B._run_generalized_candidate_advancedhmc(target, initial;
        _sampling_observer=:invalid)
    @test_throws B._SamplerError B._run_generalized_candidate_advancedhmc(target, initial;
        chains=1, warmup=0, ndraws=8, _sampling_observer=event -> error("observer failed"))

    # The same hook reaches the runner through the actual public fitting path.
    model = B.Experimental.correlated(specification())
    options = (; prior=PRIOR, chains=1, warmup=0, ndraws=8, max_depth=3, seed=918)
    events = Symbol[]
    plain = B.Experimental.fit(model; options...)
    observed = B.Experimental.fit(model; options...,
        _sampling_observer=event -> push!(events, event.phase))
    @test isequal(plain.record.run, observed.record.run)
    @test plain.record.content_hash == observed.record.content_hash
    @test events == [:sampling_start; fill(:transition, 8); :sampling_end]
end
end
