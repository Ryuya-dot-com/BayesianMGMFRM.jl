module PriorPredictiveSensitivityRenderChecks
using Test, BayesianMGMFRM, CairoMakie
const B=BayesianMGMFRM
function checks(result; only_unavailable=false)
    @testset "Prior predictive figure semantics and unavailable rows" begin
        if !only_unavailable
        io=IOBuffer()
        fig=B.plot_prior_predictive_sensitivity(result;annotation_io=io)
        axes=filter(x->x isa Axis,fig.content)
        @test length(axes)==length(result.category_levels)
        @test !any(x->x isa Label,fig.content)
        note=String(take!(io))
        @test occursin("equal-tailed predictive intervals",note)
        @test occursin("not posterior parameter uncertainty",note)
        @test occursin("Endpoint MCSE is not computed",note)
        @test all(a->a.limits[]==axes[1].limits[],axes)
        @test all(a->length(a.yticks[][2])==length(result.ledger),axes)
        embedded=B.plot_prior_predictive_sensitivity(result;levels=result.category_levels[1:1],annotation_io=nothing)
        @test count(x->x isa Label,embedded.content)==2
        @test_throws ArgumentError B.plot_prior_predictive_sensitivity(result;levels=[])
        @test_throws ArgumentError B.plot_prior_predictive_sensitivity(result;levels=[9999])
        @test_throws ArgumentError B.plot_prior_predictive_sensitivity(result;levels=repeat(result.category_levels[1:1],2))
        @test_throws ArgumentError B.plot_prior_predictive_sensitivity(result;statistic=:absent)
        end
        entries=NamedTuple[deepcopy(e) for e in result.ledger]
        entries[2]=merge(entries[2],(;status=:missing,evaluation=nothing))
        entries[3]=merge(entries[3],(;status=:failed,reason="Display-only failure",evaluation=nothing))
        demo=B._prediction_seal(merge(Base.structdiff(result,(;content_hash=nothing)),(;ledger=entries)))
        io=IOBuffer();fig=B.plot_prior_predictive_sensitivity(demo;annotation_io=io)
        labels=first(filter(x->x isa Axis,fig.content)).yticks[][2]
        @test occursin("[missing]",labels[2])
        @test occursin("[failed]",labels[3])
        @test length(labels)==3
        bad=deepcopy(result);bad.ledger[1].evaluation.rows[1].values[1]+=.1
        @test_throws ArgumentError B.plot_prior_predictive_sensitivity(bad)
    end
end
end
