module SamplingExecutionChecks
using Test, Random, BayesianMGMFRM
const B=BayesianMGMFRM
@testset "Bounded chain scheduling and failure joining" begin
    @test_throws ArgumentError B._check_chain_execution(:invalid,1)
    @test_throws ArgumentError B._check_chain_execution(:threads,0)
    @test_throws ArgumentError B._check_chain_execution(:threads,1,:turing)
    a=B._sampling_chain_schedule(MersenneTwister(12),4,:threads,1)
    b=B._sampling_chain_schedule(MersenneTwister(12),4,:threads,4)
    @test a.metadata.chain_execution.chain_seeds==b.metadata.chain_execution.chain_seeds
    @test length(unique(a.metadata.chain_execution.chain_seeds))==4
    @test a.workers==1 && b.workers==min(4,Threads.nthreads(:default))
    draws=zeros(4,4)
    B._foreach_sampling_chain(b,4,nothing) do chain,rng,cancelled
        draws[chain,:]=rand(rng,4)
    end
    @test draws==reduce(vcat,[permutedims(rand(rng,4)) for rng in a.rngs])
    rng=MersenneTwister(12);before=copy(rng)
    s=B._sampling_chain_schedule(rng,4,:serial,4)
    @test s.rngs===nothing && isempty(s.metadata) && rand(rng)==rand(before)

    if Threads.nthreads(:default)>=2
        started=Channel{Int}(2);release=Channel{Nothing}(2)
        schedule=B._sampling_chain_schedule(MersenneTwister(23),4,:threads,2)
        visited=zeros(Int,4)
        job=Threads.@spawn B._foreach_sampling_chain(schedule,4,nothing) do chain,rng,cancelled
            visited[chain]+=1
            if chain<=2
                put!(started,chain);take!(release)
            end
        end
        @test sort([take!(started),take!(started)])==[1,2]
        @test visited==[1,1,0,0] # both workers overlap, later chains stay queued
        put!(release,nothing);put!(release,nothing);fetch(job)
        @test visited==ones(Int,4)

        for failure in (ErrorException("chain failure"),InterruptException())
            active=Threads.Atomic{Int}(0);entered=Channel{Nothing}(1)
            schedule=B._sampling_chain_schedule(MersenneTwister(42),4,:threads,2)
            caught=try
                B._foreach_sampling_chain(schedule,4,nothing) do chain,rng,cancelled
                    Threads.atomic_add!(active,1)
                    try
                        if chain==1
                            take!(entered);throw(failure)
                        else
                            put!(entered,nothing)
                            while !cancelled[];yield();end
                        end
                    finally
                        Threads.atomic_add!(active,-1)
                    end
                end
                nothing
            catch err
                err
            end
            @test caught===failure
            @test active[]==0
        end
    end
end

@testset "Interleaved progress counts every chain" begin
    p=B.SamplingProgress(io=nothing)
    B._with_sampling_progress(p,3,2,3) do
        B._progress_transition!(p,3,1,2,3)
        @test B.progress_snapshot(p).completed==1
        B._progress_transition!(p,1,3,2,3)
        B._progress_transition!(p,2,2,2,3)
        @test B.progress_snapshot(p).completed==6
        @test B.progress_snapshot(p).chain_completed==(3,2,1)
        B._progress_transition!(p,1,2,2,3)
        @test B.progress_snapshot(p).completed==6
        @test_throws ArgumentError B._progress_transition!(p,4,1,2,3)
        @test_throws ArgumentError B._progress_transition!(p,1,6,2,3)
        @sync for c in 1:3
            Threads.@spawn B._progress_transition!(p,c,5,2,3)
        end
        @test B.progress_snapshot(p).completed==15
    end
    @test B.progress_snapshot(p).status===:sampling_complete
    @test B.progress_snapshot(p).percent==100
end
end
