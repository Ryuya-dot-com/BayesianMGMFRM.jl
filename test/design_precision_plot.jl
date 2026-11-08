module DesignPrecisionPlotChecks
using BayesianMGMFRM, CairoMakie, Test, Serialization
const B = BayesianMGMFRM
include("common_recovery_replications.jl")
const C = CommonRecoveryReplicationChecks

function checks(directory)
    function record(id,width)
        row=C.row("rater[R2]",0.;width)
        row=merge(row,(;mcse=(;mcse_status=:available,mean_mcse=.01,
            quantiles=((;probability=.025000000000000022,mcse=.02),
                (;probability=.975,mcse=.02)))))
        C.evaluation(id,[row])
    end
    function summary(es,id,planned;independence=C.INDEPENDENT,confidence=.95)
        B.recovery_replications(es;planned_dataset_ids=planned,parameters=["rater[R2]"],
            scenario_id=id,dataset_independence=independence,
            mcse_limits=Dict("rater[R2]"=>(;mean_mcse_max=.01,endpoint_mcse_max=.02)),
            max_interval_widths=Dict("rater[R2]"=>1.),width_confidence_level=confidence)
    end
    records=[record("one",.5),record("two",.8),record("three",1.2)]
    results=[summary(records,"Artificial: 2 of 3 qualified",["one","two","three","missing"]),
        summary(records[1:1],"Artificial: one result",["one"]),
        summary([],"Artificial: all missing",["missing"]),
        summary(records,"Artificial: dependence unresolved",["one","two","three"];independence=C.UNKNOWN)]
    @testset "Design precision figures retain conditional and unresolved outcomes" begin
        data=B.design_precision_plot_data(results;parameter="rater[R2]")
        @test data.rows[1].all_planned_frequency_bounds==(.5,.75)
        @test data.rows[3].n_qualified==0
        before=deepcopy(results)
        notes=IOBuffer()
        fig=B.plot_design_precision(results;parameter="rater[R2]",annotation_io=notes)
        note=String(take!(notes))
        @test fig isa Figure
        @test isempty(filter(x->x isa Label,fig.content))
        @test occursin("not corrected",note) && occursin("conditional",note)
        @test occursin("no confidence level",note)
        axes=filter(x->x isa Axis,fig.content)
        @test length(axes)==2
        @test all(ax->ax.yreversed[],axes)
        @test occursin("not a confidence interval",axes[2].xlabel[])
        @test occursin("no qualified datasets",join(axes[1].yticks[][2]))
        @test occursin("independence unresolved",join(axes[1].yticks[][2]))
        @test isequal(before,results)
        path=joinpath(directory,"design-summaries.jls");serialize(path,results)
        restored=deserialize(path)
        @test isequal(data,B.design_precision_plot_data(restored;parameter="rater[R2]"))
        repeated=IOBuffer()
        replay=B.plot_design_precision(restored;parameter="rater[R2]",annotation_io=repeated)
        @test String(take!(repeated))==note
        @test length(replay.content)==length(fig.content)
        embedded=B.plot_design_precision(results;parameter="rater[R2]",annotation_io=nothing)
        @test length(filter(x->x isa Label,embedded.content))==2
        for bad in (false,"not an IO",IOBuffer("read only"))
            @test_throws ArgumentError B.plot_design_precision(results;parameter="rater[R2]",annotation_io=bad)
        end
        unavailable=summary(records,"No CI requested",["one","two","three"];confidence=nothing)
        @test B.plot_design_precision(unavailable;parameter="rater[R2]",annotation_io=IOBuffer()) isa Figure
        for suffix in ("png","svg","pdf")
            path=joinpath(directory,"design-precision.$suffix")
            save(path,fig)
            @test filesize(path)>1000
        end
        write(joinpath(directory,"design-precision-note.txt"),note * "\nAll rows are deterministic artificial test records, not simulation results.\n")
        B._write_json_record(joinpath(directory,"design-precision-data.json"),data)
    end
end
end
