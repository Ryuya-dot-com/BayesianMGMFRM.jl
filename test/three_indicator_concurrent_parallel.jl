module ThreeIndicatorConcurrentParallelChecks
using BayesianMGMFRM, Test, Serialization, JSON3
import ..ThreeIndicatorConcurrentWorkflowChecks as Fixtures
const B=BayesianMGMFRM
const F=B.Experimental.ThreeIndicator.ConcurrentWorkflow

function checks()
    @testset "Concurrent execution controls and effective limits" begin
        t=Fixtures.target()
        base=(;ndraws=10,warmup=150,chains=4,seed=29)
        serial=prepare_fit(t;base...)
        for mode in (:serial,:threads),cap in (1,2,8)
            p=prepare_fit(t;base...,chain_execution=mode,max_parallel_chains=cap)
            e=fit_report(p).execution
            @test e.workers==(mode===:serial ? 1 : min(cap,4,Threads.nthreads(:default)))
            @test e.mode==mode && e.rng_partition==:prepared_chain_seeds
            @test p.record.chain_seeds==serial.record.chain_seeds
            @test p.record.initial==serial.record.initial
            @test F.execution(p.record.controls;available_threads=1).workers==1
        end
        @test_throws ArgumentError prepare_fit(t;base...,chain_execution=:processes)
        @test_throws ArgumentError prepare_fit(t;base...,max_parallel_chains=0)
        bad=F.Plan(F.seal(merge(Base.structdiff(serial.record,(;content_hash=nothing)),
            (;execution=merge(serial.record.execution,(;workers=2))))))
        @test_throws ArgumentError F.check_plan(bad)
        mktempdir() do dir
            destination=joinpath(dir,"bad")
            @test_throws ArgumentError fit(serial;directory=destination,progress=:unknown)
            @test !ispath(destination)
        end
    end
end

# Inject a real completion-write failure after chain 1 has been saved. This tests
# the public lifecycle without replacing the sampler or adding a production hook.
struct BlockCompletion <: IO
    directory::String
end
function Base.write(io::BlockCompletion,s::String)
    if occursin("chain 2/3",s)
        mkpath(joinpath(io.directory,"chain-2.jls"))
    end
    sizeof(s)
end
Base.flush(::BlockCompletion)=nothing
Base.write(::BlockCompletion,::UInt8)=1

function fitted_checks(dir)
    mkpath(dir)
    t=Fixtures.target();original=B._cache_hash(F.model(t))
    base=(;ndraws=10,warmup=150,chains=4,seed=2026110205,max_depth=3,target_accept=.9)
    results=Dict{String,Any}();timings=Dict{String,Any}()
    @testset "Same prepared seeds across serial and bounded threaded fits" begin
        for (name,mode,cap) in (("serial",:serial,4),("threads-2",:threads,2),("threads-1",:threads,1))
            p=prepare_fit(t;base...,chain_execution=mode,max_parallel_chains=cap)
            monitor=SamplingProgress(io=nothing)
            elapsed=@elapsed f=fit(p;directory=joinpath(dir,name),progress=monitor)
            results[name]=f;timings[name]=elapsed
            @test [r.chain for r in f.chains]==collect(1:4)
            for c in 1:4
                @test isfile(joinpath(dir,name,"chain-$c.jls"))
                @test !ispath(joinpath(dir,name,"chain-$c-returned.jls"))
                @test isequal(open(deserialize,joinpath(dir,name,"chain-$c.jls")),f.chains[c])
            end
            @test sampler_controls(f).execution==fit_report(p).execution
            @test progress_snapshot(monitor).chain_completed==(160,160,160,160)
            @test progress_snapshot(monitor).status===:sampling_complete
            @test progress_snapshot(monitor).completed==640
            @test all(r->r.adaptation.metric_change_iterations==[100],f.chains)
            @test all(f.chains[i].adaptation.final_inverse_mass !== f.chains[j].adaptation.final_inverse_mass
                for i in 1:4 for j in i+1:4)
            @test B._cache_hash(F.model(t))==original
            @test F.identity(load_fit(joinpath(dir,name)))==F.identity(f)
            save_fit(joinpath(dir,name*".jls"),f)
            @test F.identity(load_fit(joinpath(dir,name*".jls")))==F.identity(f)
            @test_throws ArgumentError fit(p;directory=joinpath(dir,name))
            @test_throws ArgumentError fit(p;directory=joinpath(dir,name*"-reused"),progress=monitor)
            @test !ispath(joinpath(dir,name*"-reused"))
        end
        baseline=results["serial"]
        for name in ("threads-1","threads-2")
            f=results[name]
            @test f.plan.record.chain_seeds==baseline.plan.record.chain_seeds
            for i in 1:4
                # Includes draws, densities, telemetry, controls and sampler diagnostics.
                @test isequal(f.chains[i].run,baseline.chains[i].run)
                @test isequal(f.chains[i].adaptation,baseline.chains[i].adaptation)
            end
        end
        if Threads.nthreads(:default)>=2
            d=joinpath(dir,"threads-2")
            @test stat(joinpath(d,"chain-2-started.jls")).mtime < stat(joinpath(d,"chain-1.jls")).mtime
            @test stat(joinpath(d,"chain-1-started.jls")).mtime < stat(joinpath(d,"chain-2.jls")).mtime
        end
        @test !isequal(baseline.chains[1].run.draws,baseline.chains[2].run.draws)
    end
    @testset "Completion failure preserves completed and returned chains" begin
        d=joinpath(dir,"failure")
        p=prepare_fit(t;ndraws=10,warmup=0,chains=3,seed=29,max_depth=2,
            chain_execution=:threads,max_parallel_chains=1)
        monitor=SamplingProgress(io=BlockCompletion(d),interval=0)
        @test_throws ArgumentError fit(p;directory=d,progress=monitor)
        @test progress_snapshot(monitor).status===:failed
        @test isfile(joinpath(d,"chain-1.jls"))
        @test isfile(joinpath(d,"chain-2-returned.jls"))
        @test isfile(joinpath(d,"chain-2-failed.jls"))
        @test !ispath(joinpath(d,"chain-3-started.jls"))
        partial=load_fit(d;require_complete=false)
        @test [r.chain for r in partial.chains]==[1]
        @test !qualify(partial).qualified
        @test_throws ArgumentError load_fit(d)
        @test_throws ArgumentError event_probabilities(partial;rows=[1])
    end
    @testset "Parallel metadata and warnings survive portable reports" begin
        f=results["threads-2"]
        r=event_probabilities(f;rows=[1])
        @test !r.numerical_qualified && !r.scientific_acceptance
        @test r.execution.workers==min(2,Threads.nthreads(:default))
        receipt=save_report(joinpath(dir,"report.json"),r;return_receipt=true)
        @test load_report(receipt.path;expected_sha256=receipt.sha256)==r
        open(io->JSON3.write(io,receipt),joinpath(dir,"report-receipt.json"),"w")
        d=F.R.normalized(r);d["execution"]["workers"]=9;delete!(d,"content_hash");d["content_hash"]=B._cache_hash(d)
        @test_throws ArgumentError F.check_report(JSON3.read(JSON3.write(d)))
        d=F.R.normalized(r);delete!(d,"execution");delete!(d,"content_hash");d["content_hash"]=B._cache_hash(d)
        @test_throws ArgumentError F.check_report(JSON3.read(JSON3.write(d)))
    end
    open(io->JSON3.write(io,(;julia=string(VERSION),threads=Threads.nthreads(:default),timings,
        identities=Dict(k=>F.identity(v) for (k,v) in results))),joinpath(dir,"checks.json"),"w")
end
end
