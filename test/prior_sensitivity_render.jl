module PriorSensitivityRenderChecks
using Test,BayesianMGMFRM,CairoMakie
const B=BayesianMGMFRM
function checks(result)
    @testset "Ridge display keeps missing, warning and fixed rows" begin
        # Artificial display-only derivative of an existing record; no fit claim.
        original=first(result.ledger)
        rows=deepcopy(original.evaluation.rows)
        r=first(rows);v=first(r.values)
        rows[1]=merge(r,(;values=fill(v,length(r.values)),median=v,lower=v,upper=v,fixed=true))
        warning=merge(original,(;status=:warning,evaluation=merge(original.evaluation,(;rows))))
        ledger=NamedTuple[warning,(;prior_id="Missing",status=:missing,reason=nothing,evaluation=nothing),
            (;prior_id="Failed",status=:failed,reason="Display fixture",evaluation=nothing)]
        demo=B._prediction_seal(merge(Base.structdiff(result,(;content_hash=nothing)),(;ledger)))
        io=IOBuffer();fig=B.plot_prior_sensitivity(demo;kind=:ridge,annotation_io=io)
        axes=filter(x->x isa Axis,fig.content)
        @test length(axes)==length(rows)
        labels=axes[1].yticks[][2]
        @test length(labels)==3
        @test occursin("[warning]",labels[1])
        @test occursin("[fixed]",labels[1])
        @test occursin("[missing]",labels[2])
        @test occursin("[failed]",labels[3])
        @test occursin("2 unavailable",String(take!(io)))
        @test !any(x->x isa Label,fig.content)
        embedded=B.plot_prior_sensitivity(demo;annotation_io=nothing)
        @test count(x->x isa Label,embedded.content)==2
    end
end
end
