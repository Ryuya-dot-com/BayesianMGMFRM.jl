using BayesianMGMFRM,Test,TOML
const B=BayesianMGMFRM
previous,output=ARGS;mkpath(output)
started=time()
checks=@testset "Warning-only tables and unchanged existing report results" begin
    for i in 1:2
        fit=load_fit_cache(joinpath(previous,"model-$i.jls"))
        old=load_fit_report_bundle(joinpath(previous,"model-$i");require_complete=true)
        new=fit_report(fit;dataset_id=old["waic"]["dataset_id"],observation_ids=old["waic"]["observation_ids"],
            include_waic=true,include_loo=true,draw_indices=[40,1,1],include_artifact=false,require_complete=true)
        for name in (:waic,:loo)
            section=getproperty(new,name)
            @test section.n_problem_rows>0
            @test section.n_problem_rows==length(section.problem_observation_ids)
            @test getproperty.(section.problem_rows,:observation_id)==section.problem_observation_ids
            @test all(row->row.flag!==:ok,section.problem_rows)
            prior_fields=Base.structdiff(section,(;problem_rows=nothing,n_problem_rows=nothing))
            @test B._json_export_value(prior_fields)==old[String(name)]
        end
        @test B._json_export_value(new.direct_posterior)==old["direct_posterior"]
        @test B._json_export_value(new.diagnostics)==old["diagnostics"]
        markdown=fit_report_markdown(new;max_rows=40)
        @test occursin("### waic / problem_rows",markdown)
        @test occursin("### loo / problem_rows",markdown)
        directory=joinpath(output,"model-$i")
        save_fit_report_bundle(directory,new;require_complete=true,max_rows=6)
        restored=load_fit_report_bundle(directory;require_complete=true)
        for name in (:waic,:loo)
            @test restored[String(name)]["problem_rows"]==B._json_export_value(getproperty(new,name).problem_rows)
            @test isfile(joinpath(directory,"tables","$(name)__problem_rows.json"))
        end
    end
end
counts=Test.get_test_counts(checks)
open(joinpath(output,"verification.toml"),"w") do io
    TOML.print(io,Dict("status"=>"passed","passed"=>counts.passes+counts.cumulative_passes,
        "seconds"=>time()-started,"new_posterior_fits"=>0,
        "scope"=>"added warning-only tables, numerical and diagnostic identity against check-01; no full-suite rerun"))
end
