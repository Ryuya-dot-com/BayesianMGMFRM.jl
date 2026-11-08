isdefined(@__MODULE__, :MGMFRMArtifactReuseChecks) || include("mgmfrm_artifact_reuse.jl")
module MGMFRMReportReuseChecks
using Test, BayesianMGMFRM
using ..MGMFRMArtifactReuseChecks: fixtures
const B=BayesianMGMFRM

function checks()
    @testset "Recorded reports preserve public results and recheck mutations" begin
        for fit in fixtures()
            original=deepcopy(fit.record.run)
            inventory=B.recovery_quantities(fit)
            names=[r.parameter for r in inventory.rows if r.block===:person && r.dimension==1]
            rank=(;parameters=names,direction=:higher,top_k=1,interval=.95)
            options=(;view=:full,reporting=(;ranking=rank),include_artifact=false,
                include_posterior_predictive=false,include_prior_predictive=false,require_complete=true)
            report=fit_report(fit;options...)
            diagnostic=diagnostics(fit)
            metadata=fit_metadata(fit)
            ranked=B.posterior_ranking(fit;rank...)
            @test all(isequal(getproperty(report.metadata,k),v) for (k,v) in pairs(metadata))
            @test all(isequal(getproperty(report.diagnostics,k),v) for (k,v) in pairs(diagnostic))
            @test isequal(report.posterior.rows,posterior_summary(fit))
            @test isequal(report.posterior_ranking.result,
                Base.structdiff(ranked,(;schema=nothing,content_hash=nothing)))
            @test report.posterior_ranking.source_result_hash==ranked.content_hash
            @test !report.diagnostics.summary.passed
            @test report.posterior_ranking.result.sampling_warning
            @test !isempty(report.posterior_ranking.warning_rows)
            @test isequal(fit.record.run,original)
            @test_throws ArgumentError fit_report(fit;options...,split_chains=false)
            @test_throws ArgumentError fit_report(fit;options...,rhat_threshold=1.1)
            @test_throws ArgumentError fit_report(fit;options...,ess_threshold=200)
            @test_throws ArgumentError fit_report(fit;merge(options,(;view=:invalid))...)
            @test_throws ArgumentError fit_report(fit;options...,posterior_lower=.1)
            bad=(;parameters=["unknown","also_unknown"],direction=:higher)
            captured=fit_report(fit;merge(options,(;reporting=(;ranking=bad),require_complete=false))...)
            @test captured.posterior_ranking.status===:error
            @test_throws ArgumentError fit_report(fit;merge(options,(;reporting=(;ranking=bad)))...)
            @test_throws ArgumentError fit_report(fit;merge(options,(;reporting=(;ranking=bad),
                require_complete=false,on_section_error=:throw))...)
            mktempdir() do dir
                path=joinpath(dir,"report.json")
                save_fit_report(path,report;require_complete=true)
                restored=load_fit_report(path;require_complete=true)
                @test length(restored["posterior_ranking"]["rows"])==length(names)
                @test restored["posterior_ranking"]["source_result_hash"]==ranked.content_hash
                @test restored["posterior_ranking"]["result"]["sampling_warning"]
            end
            # Repeated public operations must not trust a prior successful call.
            fit.record.run.draws[1,1]+=.1
            @test_throws ArgumentError fit_report(fit;options...)
            @test_throws ArgumentError B.posterior_ranking(fit;rank...)
            fit.record.run.draws[1,1]=original.draws[1,1]
            fit.record.run.chain_ids[1]=99
            @test_throws ArgumentError fit_report(fit;options...)
            fit.record.run.chain_ids[1]=original.chain_ids[1]
            push!(fit.record.run.warmup_stats,(;chain=1,iteration=1))
            @test_throws ArgumentError fit_report(fit;options...)
            empty!(fit.record.run.warmup_stats)
            @test isequal(fit.record.run,original)
            @test isequal(fit_report(fit;options...).posterior_ranking,report.posterior_ranking)
        end
    end
end
end
