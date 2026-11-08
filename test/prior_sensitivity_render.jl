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
        note=String(take!(io))
        @test occursin("2 unavailable",note)
        @test occursin("mean MCSE $(r.mcse.mean_mcse)",note)
        @test occursin("lower / median / upper MCSE",note)
        @test occursin("sampling warning $(original.evaluation.sampling_warning)",note)
        @test occursin("Missing: missing",note)
        @test occursin("Failed: failed",note)
        @test occursin(result.max_mcse===nothing ? "No maximum MCSE was declared" :
            "Declared maximum MCSE: $(result.max_mcse)",note)
        for (ax,row) in zip(axes,rows)
            if row.parameter_space===:dimensionless
                @test occursin("imensionless",ax.xlabel[])
                @test !occursin("1.7",ax.xlabel[])
            elseif result.scope===:normalized_d1_fixed_mean_profile
                @test occursin("multiply by 1.7 for unit logits",ax.xlabel[])
            end
        end
        @test occursin("precision screen "*(r.precision_qualified===nothing ? "not requested" :
            r.precision_qualified ? "met" : "unmet"),note)
        @test !any(x->x isa Label,fig.content)
        embedded=B.plot_prior_sensitivity(demo;annotation_io=nothing)
        @test count(x->x isa Label,embedded.content)==2
    end
end
end
