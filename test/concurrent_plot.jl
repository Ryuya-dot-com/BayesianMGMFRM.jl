module ConcurrentPlotChecks
using BayesianMGMFRM, JSON3, SHA, Test, Random
using BayesianMGMFRM.GlassBox
const B=BayesianMGMFRM
const R=B.Experimental.ThreeIndicator.ConcurrentReports
const FIXTURES=joinpath(@__DIR__,"fixtures/concurrent_plot")
readfixture(name)=B.load_report(joinpath(FIXTURES,"$name.json");
    expected_sha256=bytes2hex(sha256(read(joinpath(FIXTURES,"$name.json")))))
function reseal(d)
    pop!(d,"content_hash",nothing); d=R.normalized(d)
    d["content_hash"]=B._cache_hash(d);JSON3.read(JSON3.write(d))
end
function checks()
    @testset "Concurrent saved plot contract without inference" begin
        F = B.Experimental.ThreeIndicator.ConcurrentWorkflow
        @test F.has_chart_warning([F.CHART_WARNING])
        @test F.has_chart_warning(["Experimental " * F.CHART_WARNING])
        @test !F.has_chart_warning(String[])
        @test !F.has_chart_warning(["Unknown " * F.CHART_WARNING])
        p=readfixture("ppc"); c=readfixture("contrasts"); r=readfixture("reference")
        @test length(p.rows)==202
        @test length(c.rows)==24
        @test length(r.rows)==3length(r.metadata.definitions.speakers)
        @test !c.metadata.qualification.qualified && !p.metadata.posterior_fit_qualified
        for (data,view) in ((p,:joint),(p,:marginal),(c,:contrasts),(r,:eng_reference))
            Random.seed!(1234); expected=rand();Random.seed!(1234)
            @test B._concurrent_plot_data(data)==data
            @test rand()==expected
            @test occursin("Source report",B._concurrent_plot_note(data,view))
            @test all(w->occursin(w,B._concurrent_plot_note(data,view)),data.metadata.warnings)
        end
        bad=R.normalized(p);bad["rows"][1]["mean"]+=1
        @test_throws ArgumentError B._check_concurrent_plot_data(JSON3.read(JSON3.write(bad)))
        for modify in (
            d->(d["source_fit_hash"]="0"^64),
            d->pop!(d["rows"]),
            d->(d["rows"][2]=d["rows"][1]),
            d->(d["metadata"]["check_type"]="prior_predictive"),
            d->(d["metadata"]["binary_coding"]="1=error;2=correct"),
            d->(d["metadata"]["denominators"][1]+=1),
            d->(d["metadata"]["source_rows"][2]=d["metadata"]["source_rows"][1]),
            d->(d["rows"][1]["lower_endpoint"]["quantile_mcse"]=0.0),
            d->(d["metadata"]["replication_law"]="independent_three_responses"))
            d=R.normalized(p);modify(d)
            @test_throws ArgumentError B._check_concurrent_plot_data(reseal(d))
        end
        for modify in (
            d->(d["rows"][1]["unit"]="probability"),
            d->(d["rows"][1]["name"]="contrast[99]/difference/correct_probability"),
            d->(d["metadata"]["definitions"]["comparisons"][1]["left_weight"]*=2),
            d->(d["rows"][1]["mcse"]["quantiles"][1]["probability"]=.1),
            d->(d["rows"][1]["precision_passed"]=!d["rows"][1]["precision_passed"]),
            d->(d["source_rows_count"]-=1))
            d=R.normalized(c);modify(d)
            @test_throws ArgumentError B._check_concurrent_plot_data(reseal(d))
        end
        d=R.normalized(r);d["metadata"]["definitions"]["reference"]["word_weight"]*=2
        @test_throws ArgumentError B._check_concurrent_plot_data(reseal(d))
        # Row identity, not serialized order, controls focal plotting.
        d=R.normalized(c);reverse!(d["rows"])
        @test B._check_concurrent_plot_data(reseal(d)).source_report_hash==c.source_report_hash
        mktempdir() do dir
            receipt=save_report(joinpath(dir,"plot.json"),r;return_receipt=true)
            @test load_report(receipt.path;expected_sha256=receipt.sha256)==r
            @test_throws ArgumentError load_report(receipt.path)
            @test_throws ArgumentError load_report(receipt.path;expected_sha256="0"^64)
            @test_throws ArgumentError save_report(receipt.path,r)
            @test_throws ArgumentError load_report(receipt.path;expected_sha256=receipt.sha256,arbitrary=true)
        end
    end
end
end
