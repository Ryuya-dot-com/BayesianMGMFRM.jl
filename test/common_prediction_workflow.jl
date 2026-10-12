using BayesianMGMFRM, Test, Serialization, TOML, SHA
const B=BayesianMGMFRM
include("common_prediction_fixtures.jl")
include("../examples/saved_prediction_workflow.jl")

function common_prediction_workflow_checks(directory)
    @testset "Public saved workflow, fresh process and input boundaries" begin
        r=F.synthetic_record(F.target())
        fits=["Independent"=>normalized_fixture(r),
            "Correlated"=>B.Experimental.CorrelatedMGMFRMFit(r;expected_identity=r.target_identity)]
        input=joinpath(directory,"input");mkpath(input)
        caches=[name=>joinpath(input,"fit-$i.jls") for (i,(name,_)) in enumerate(fits)]
        for ((_,fit),(_,path)) in zip(fits,caches)
            save_fit_cache(path,fit)
        end
        before=[sha256(read(path)) for (_,path) in caches]
        ids=["internal rating $i" for i in 1:r.spec.data.n]
        opts=(;dataset_id="shared workflow",observation_ids=ids,comparison_axis=:model)
        result=saved_prediction_workflow(caches...;opts...,directory=joinpath(directory,"first"))
        @test result.comparison.model_selection===:not_performed
        @test result.comparison.scientific_acceptance===:not_established
        @test result.comparison.uncertainty.standard_error===:not_requested
        for (row,model,(_,fit)) in zip(result.comparison.rows,result.models,fits)
            @test model.model==row.model
            @test row.elpd==model.report["waic"]["stat"]["elpd_waic"]
            @test isequal(model.diagnostics,diagnostics(fit))
            @test isequal(model.parameter_mcse,posterior_mcse(fit))
            @test model.report["loo"]["observation_ids"]==ids
            @test model.report["waic"]["sampling_warning"]
            @test model.report["report_status"]=="complete"
        end
        @test before==[sha256(read(path)) for (_,path) in caches]
        @test_throws ArgumentError saved_prediction_workflow(caches...;opts...,directory=joinpath(directory,"first"))
        bad=joinpath(directory,"bad")
        @test_throws ArgumentError saved_prediction_workflow(caches...;opts...,directory=bad,criterion=:hill_smoothed_loo)
        @test_throws ArgumentError saved_prediction_workflow(caches...;opts...,directory=bad,observation_ids=fill("same",length(ids)))
        @test !ispath(bad)
        legacy=reporting_fit(:mfrm;data=r.spec.data,chains=2,ndraws=20,warmup=0)
        path=joinpath(input,"scalar.jls");save_fit_cache(path,legacy)
        mixed_opts=merge(opts,(;comparison_axis=:dimensions))
        cohort=(;id="Three fitted persons",parameters=[q.parameter for q in
            B.recovery_quantities(legacy).rows if q.block===:person && !q.fixed],target=:centered)
        response_ids=["response-$p-$i" for (p,i) in zip(r.spec.data.person,r.spec.data.item)]
        choices=Dict("Independent"=>nothing,"Scalar"=>(;category=(;interval=.99),
            agreement=(;response_ids,interval=.95,se_unit=:person),reliability=[cohort]))
        choices_before=deepcopy(choices)
        mixed=saved_prediction_workflow(caches[1],"Scalar"=>path;mixed_opts...,
            directory=joinpath(directory,"mixed"),reporting_by_model=choices)
        @test isequal(choices,choices_before)
        @test length(mixed.models)==2
        @test mixed.comparison.rows[2].elpd≈mixed.models[2].report["waic"]["stat"]["elpd_waic"]
        @test !haskey(mixed.models[1].report,"category_report")
        scalar=mixed.models[2].report
        @test scalar["category_report"]["result"]["observation_ids"]==ids
        @test scalar["rater_agreement"]["result"]["response_ids"]==response_ids
        @test scalar["posterior_reliability"]["rows"][1]["cohort_id"]==cohort.id
        @test scalar["category_report"]["result"]["sampling_warning"]
        @test scalar["report_status"]=="complete"
        for options in (NamedTuple(),Dict("Independent"=>nothing),
                Dict("Independent"=>nothing,"Scalar"=>nothing,:Scalar=>nothing),
                Dict("Independent"=>nothing,"Scalar"=>(;dataset_id="another study")),
                Dict("Independent"=>nothing,"Scalar"=>(;reliability=[merge(cohort,(;parameters=["unknown"]))])))
            @test_throws ArgumentError saved_prediction_workflow(caches[1],"Scalar"=>path;
                mixed_opts...,directory=bad,reporting_by_model=options)
            @test !ispath(bad)
        end

        # The second process gets only saved inputs, expected public results and the example.
        serialize(joinpath(input,"expected.jls"),result)
        open(joinpath(input,"inputs.toml"),"w") do io
            TOML.print(io,Dict("names"=>first.(caches),"files"=>basename.(last.(caches)),
                "dataset_id"=>opts.dataset_id,"observation_ids"=>ids))
        end
        project=dirname(@__DIR__);runner=joinpath(@__DIR__,"common_prediction_workflow_replay.jl")
        replay=joinpath(directory,"second");log=joinpath(directory,"replay.log")
        GC.gc()
        open(log,"w") do io
            process=run(pipeline(`$(Base.julia_cmd()) --startup-file=no --project=$project $runner $input $replay`;
                stdout=io,stderr=io);wait=false)
            wait(process)
            if !success(process)
                flush(io);print(stderr,read(log,String))
            end
            @test success(process)
        end
        receipt=TOML.parsefile(joinpath(replay,"replay.toml"))
        print(read(log,String))
        @test receipt["status"]=="passed" && receipt["assertions"]==13
        @test receipt["pid"]!=getpid()
        @test receipt["new_posterior_fits"]==0
        @test before==[sha256(read(path)) for (_,path) in caches]
    end
end
