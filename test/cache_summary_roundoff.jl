module CacheSummaryRoundoffChecks
using BayesianMGMFRM,Test
const B=BayesianMGMFRM
function checks()
    @testset "Cache summary roundoff is local to recomputed moments" begin
        row=(;parameter="theta[1]",mean=0.0,sd=1.0,median=.25,lower=-2.,upper=2.,n_draws=16)
        expected=(;schema="example",posterior_summary=[row],direct_posterior_summary=[row],metadata=(;fixed=false))
        function changed(;kwargs...)
            merge(expected,(;posterior_summary=[merge(row,(;kwargs...))]))
        end
        tolerance=8*row.n_draws*eps(Float64)*max(abs(row.mean),row.sd)
        @test B._fit_cache_artifact_equal(expected,expected)
        @test B._fit_cache_artifact_equal(changed(mean=eps(Float64)),expected)
        @test B._fit_cache_artifact_equal(changed(sd=nextfloat(row.sd)),expected)
        @test B._fit_cache_artifact_equal(changed(mean=tolerance),expected)
        @test !B._fit_cache_artifact_equal(changed(mean=nextfloat(tolerance)),expected)
        for bad in (changed(mean=.001),changed(sd=1.001),changed(sd=-eps(Float64)),
                changed(mean=Inf),changed(sd=NaN),changed(mean=missing),
                changed(parameter="theta[2]"),changed(n_draws=17),
                changed(median=nextfloat(row.median)),changed(lower=nextfloat(row.lower)),
                merge(expected,(;metadata=(;fixed=true))),merge(expected,(;extra=1)),
                merge(expected,(;posterior_summary=[row,row])))
            @test !B._fit_cache_artifact_equal(bad,expected)
        end
        zeros=merge(expected,(;posterior_summary=[merge(row,(;sd=0.0))]))
        @test !B._fit_cache_artifact_equal(merge(zeros,(;posterior_summary=[merge(row,(;mean=eps(Float64),sd=0.0))])),zeros)
        # There is no absolute unit-scale floor for a very small parameter.
        tiny=merge(row,(;mean=1e-100,sd=1e-101))
        @test B._fit_cache_summary_rows_equal([merge(tiny,(;mean=nextfloat(tiny.mean)))],[tiny])
        @test !B._fit_cache_summary_rows_equal([merge(tiny,(;mean=1e-99))],[tiny])

        drow=(;parameter="theta[1]",flag=:ok,rhat=1.001,ess=612.5,rank_normalized_rhat=1.002,
               bulk_rank_normalized_rhat=1.001,folded_rank_normalized_rhat=1.002,bulk_ess=600.0,tail_ess=550.0)
        brow=(;block=:person,flag=:ok,max_rhat=1.001,min_ess=612.5,
               max_rank_normalized_rhat=1.002,min_bulk_ess=600.0,min_tail_ess=550.0)
        sub_m=(;max_rhat=1.001,min_ess=612.5,max_rank_normalized_rhat=1.002,min_bulk_ess=600.0,min_tail_ess=550.0,n_low_bulk_ess=0)
        dsum=(;total_draws=40,flag=:ok,passed=true,max_rhat=1.001,min_ess=612.5,
               max_rank_normalized_rhat=1.002,min_bulk_ess=600.0,min_tail_ess=550.0,n_low_bulk_ess=0,
               raw_diagnostic_metrics=sub_m,direct_diagnostic_metrics=sub_m,combined_diagnostic_metrics=sub_m)
        mfields=(;max_rhat=1.001,min_ess=612.5,max_rank_normalized_rhat=1.002,min_bulk_ess=600.0,min_tail_ess=550.0,
                  raw_diagnostic_metrics=sub_m,direct_diagnostic_metrics=sub_m,combined_diagnostic_metrics=sub_m)
        with_diag=merge(expected,(;
            diagnostics=(;summary=dsum,parameter_rows=[drow],direct_parameter_rows=[drow],
                          block_rows=[brow],direct_block_rows=[brow],
                          raw_metrics=sub_m,direct_metrics=sub_m,combined_metrics=sub_m,metric_fields=mfields,
                          sampler_rows=[(chain=1,divergences=0)]),
            manifest=(;object=:fit,diagnostics=dsum)))
        @test B._fit_cache_artifact_equal(with_diag,with_diag)
        sub_m_tw=merge(sub_m,(;min_bulk_ess=sub_m.min_bulk_ess+1e-14,max_rank_normalized_rhat=nextfloat(sub_m.max_rank_normalized_rhat)))
        dsum_tw=merge(dsum,(;min_bulk_ess=dsum.min_bulk_ess+1e-14,max_rank_normalized_rhat=nextfloat(dsum.max_rank_normalized_rhat),
                             raw_diagnostic_metrics=sub_m_tw,direct_diagnostic_metrics=sub_m_tw,combined_diagnostic_metrics=sub_m_tw))
        tweaked=merge(with_diag,(;
            diagnostics=merge(with_diag.diagnostics,(;
                summary=dsum_tw,
                parameter_rows=[merge(drow,(;bulk_ess=drow.bulk_ess-1.1e-14,bulk_rank_normalized_rhat=prevfloat(drow.bulk_rank_normalized_rhat)))],
                direct_parameter_rows=[merge(drow,(;bulk_ess=drow.bulk_ess+1.1e-14,bulk_rank_normalized_rhat=nextfloat(drow.bulk_rank_normalized_rhat)))],
                block_rows=[merge(brow,(;min_bulk_ess=brow.min_bulk_ess-1.1e-14))],
                direct_block_rows=[merge(brow,(;min_bulk_ess=brow.min_bulk_ess+1.1e-14))],
                raw_metrics=sub_m_tw,direct_metrics=sub_m_tw,combined_metrics=sub_m_tw,
                metric_fields=merge(mfields,(;min_bulk_ess=mfields.min_bulk_ess+1e-14,direct_diagnostic_metrics=sub_m_tw)))),
            manifest=(;object=:fit,diagnostics=dsum_tw)))
        @test B._fit_cache_artifact_equal(tweaked,with_diag)
        @test !B._fit_cache_artifact_equal(merge(with_diag,(;diagnostics=merge(with_diag.diagnostics,(;summary=merge(dsum,(;n_low_bulk_ess=1)))))),with_diag)
        @test !B._fit_cache_artifact_equal(merge(with_diag,(;diagnostics=merge(with_diag.diagnostics,(;direct_parameter_rows=[merge(drow,(;flag=:mcmc_warning))])))),with_diag)
        @test !B._fit_cache_artifact_equal(merge(with_diag,(;diagnostics=merge(with_diag.diagnostics,(;summary=merge(dsum,(;min_bulk_ess=dsum.min_bulk_ess+1e-3)))))),with_diag)
    end
end
end
