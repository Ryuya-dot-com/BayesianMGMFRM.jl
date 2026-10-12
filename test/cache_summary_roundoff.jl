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
    end
end
end
