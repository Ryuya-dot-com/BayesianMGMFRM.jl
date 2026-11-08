module SamplingProgressChecks
using Test, Logging, BayesianMGMFRM
const B = BayesianMGMFRM
const E = B.Experimental

@testset "Sampling progress state, output and failure boundaries" begin
    @test_throws ArgumentError SamplingProgress(interval=-1)
    @test_throws ArgumentError SamplingProgress(interval=Inf)
    @test_throws ArgumentError SamplingProgress(path="")
    mktempdir() do directory
        output=IOBuffer();path=joinpath(directory,"progress.json")
        p=SamplingProgress(;io=output,path,interval=1e6)
        @test progress_snapshot(p).status === :idle
        events=NamedTuple[]
        B._with_sampling_progress(p,2,2,3) do
            for chain in 1:2
                B._progress_chain!(p,chain,2,3)
                for i in 1:5
                    B._progress_transition!(p,chain,i,2,3)
                    push!(events,progress_snapshot(p))
                end
            end
        end
        @test getproperty.(events,:completed)==1:10
        @test getproperty.(events,:percent)==10:10:100
        @test events[2].phase === :warmup && events[2].phase_completed==2
        @test events[3].phase === :sampling && events[3].phase_completed==1
        @test events[6].chain==2 && events[6].phase === :warmup
        @test progress_snapshot(p).status === :sampling_complete
        @test B.JSON3.read(read(path,String)).percent==100
        @test isempty(progress_snapshot(p).output_errors)
        text=String(take!(output))
        @test occursin("Sampling [####################] 100.0%",text)
        @test occursin("chain 2/2",text)
        @test !occursin('\r',text) && !occursin('\e',text)
        @test length(split(chomp(text),'\n'))<length(events)+4 # throttled within phases
        @test_throws ArgumentError SamplingProgress(;path)
        @test_throws ArgumentError B._with_sampling_progress(()->nothing,p,1,0,1)

        for (error_value,status) in ((ErrorException("test failure"),:failed),(InterruptException(),:interrupted))
            p=SamplingProgress(io=nothing)
            @test_throws typeof(error_value) B._with_sampling_progress(p,1,0,10) do
                B._progress_chain!(p,1,0,10)
                B._progress_transition!(p,1,2,0,10)
                throw(error_value)
            end
            s=progress_snapshot(p)
            @test s.status===status && s.percent==20
            @test s.phase===:sampling && s.phase_total==10
        end
        # A broken display/file must not discard a sampler's result.
        closed=IOBuffer();close(closed)
        badparent=joinpath(directory,"not-a-directory");write(badparent,"keep")
        p=SamplingProgress(io=closed,path=joinpath(badparent,"progress.json"))
        value=with_logger(NullLogger()) do
            B._with_sampling_progress(p,1,0,1) do
                B._progress_chain!(p,1,0,1)
                B._progress_transition!(p,1,1,0,1)
                :retained_result
            end
        end
        @test value===:retained_result
        @test length(progress_snapshot(p).output_errors)==2
        @test progress_snapshot(p).status===:sampling_complete
        @test read(badparent,String)=="keep"
        @test readdir(directory)==["not-a-directory","progress.json"]
    end
end

@testset "Atomic progress publication preserves readers and unexpected destinations" begin
    mktempdir() do directory
        path=joinpath(directory,"progress.json")
        p=SamplingProgress(io=nothing,path=path,interval=0)
        done=Threads.Atomic{Bool}(false)
        errors=String[];ready=Channel{Nothing}(1)
        B._with_sampling_progress(p,1,0,100) do
            reader=Threads.@spawn begin
                announced=false
                while !done[]
                    try
                        record=B.JSON3.read(read(path,String))
                        0<=record.completed<=100 || push!(errors,"invalid count")
                    catch err
                        push!(errors,sprint(showerror,err))
                    end
                    if !announced
                        put!(ready,nothing);announced=true
                    end
                    yield()
                end
            end
            take!(ready)
            try
                for i in 1:100
                    B._progress_transition!(p,1,i,0,100)
                    yield()
                end
            finally
                done[]=true
            end
            fetch(reader)
        end
        @test isempty(errors)
        @test B.JSON3.read(read(path,String)).status=="sampling_complete"
        # An external directory appearing at the output path must never be removed.
        destination=joinpath(directory,"collision.json")
        p=SamplingProgress(io=nothing,path=destination,interval=0)
        with_logger(NullLogger()) do
            B._with_sampling_progress(p,1,0,1) do
                rm(destination);mkdir(destination)
                write(joinpath(destination,"keep.txt"),"keep")
                B._progress_transition!(p,1,1,0,1)
            end
        end
        @test read(joinpath(destination,"keep.txt"),String)=="keep"
        @test length(progress_snapshot(p).output_errors)==1
        @test progress_snapshot(p).status===:sampling_complete
        raced=joinpath(directory,"created-by-someone-else.json")
        p=SamplingProgress(io=nothing,path=raced)
        write(raced,"preserve")
        with_logger(NullLogger()) do
            B._publish_progress!(p;force=true)
        end
        @test read(raced,String)=="preserve"
        @test length(progress_snapshot(p).output_errors)==1
    end
end

include(joinpath(@__DIR__,"..","examples","first_analysis.jl"))
@testset "Progress preserves actual scalar and mean-profile sampling" begin
    prepared=FirstMFRMAnalysis.inputs()
    @test prepared.data.n==72
    for backend in (:julia,:turing,:cmdstan)
        @test_throws ArgumentError fit(prepared.spec;backend,progress=SamplingProgress(io=nothing))
    end
    options=(;backend=:advancedhmc,chains=2,warmup=0,ndraws=8,max_depth=2,seed=2026102404)
    p=SamplingProgress(io=IOBuffer(),interval=0)
    @test fit_cache_key(prepared.spec;options...,progress=p)==fit_cache_key(prepared.spec;options...)
    @test progress_snapshot(p).status===:idle
    plain=fit(prepared.spec;prior=prepared.prior,options...)
    monitored=fit(prepared.spec;prior=prepared.prior,options...,progress=p)
    for field in (:draws,:log_posterior,:chain_ids,:iterations,:chain_acceptance_rate,
                  :sampler_stats,:sampler_controls)
        @test isequal(getproperty(plain,field),getproperty(monitored,field))
    end
    @test progress_snapshot(p).completed==16
    @test progress_snapshot(p).percent==100
    @test progress_snapshot(p).status===:sampling_complete
    @test !occursin("| warmup ",String(take!(p.io)))

    spec=mfrm_spec(prepared.data;family=:mgmfrm,dimensions=1,thresholds=:partial_credit,
        q_matrix=trues(4,1))
    model=E.slope_restriction(spec;item_slopes=:fixed_one,rater_consistency=:fixed_one)
    base=E.NormalizedMGMFRMPrior(prior_model=:exchangeable,person_sd=.5,rater_sd=.3,
        item_sd=.5,step_sd=.25,log_discrimination_sd=.3,log_consistency_sd=.4)
    prior=E.MeanProfilePrior(model,base;
        item_means=Dict(i=>0. for i in prepared.data.item_levels),
        step_means=Dict(i=>[-.2,0.,.2] for i in prepared.data.item_levels),
        category_levels=0:3,units=:unit_logit)
    @test_throws ArgumentError E.fit(model;prior,backend=:cmdstan,progress=SamplingProgress(io=nothing))
    opts=(;prior,chains=2,warmup=24,ndraws=8,max_depth=2,seed=2026102405)
    mktempdir() do directory
        p=SamplingProgress(io=IOBuffer(),path=joinpath(directory,"progress.json"),interval=0)
        events=NamedTuple[]
        observer=e->push!(events,(;phase=e.phase,chain=e.chain))
        plain=E.fit(model;opts...)
        monitored=E.fit(model;opts...,progress=p,_sampling_observer=observer)
        @test isequal(plain.record.run,monitored.record.run)
        @test plain.record.content_hash==monitored.record.content_hash
        @test progress_snapshot(p).completed==64
        @test progress_snapshot(p).status===:sampling_complete
        @test B.JSON3.read(read(p.path,String)).total==64
        @test count(e->e.phase===:transition,events)==64
        @test count(e->e.phase===:sampling_start,events)==2
        @test count(e->e.phase===:sampling_end,events)==2
        text=String(take!(p.io))
        @test occursin("warmup 24/24",text) && occursin("sampling 8/8",text)
    end
end
end
