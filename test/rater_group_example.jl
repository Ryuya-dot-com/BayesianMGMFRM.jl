module RaterGroupExampleChecks
using Test
include(joinpath(@__DIR__,"../examples/rater_group_effects.jl"))
const E=RaterGroupExample
# Fixed report-shaped fixtures, not posterior samples or calibration evidence.
function fixture(;whole=true,status=:available,rhat=1.,bulk=800.,tail=700.,mean_mcse=.001,
        lower_mcse=.01,upper_mcse=.01,event_mcse=.001)
    (;target_identity="fixed-fixture",source_sample_content_hash="fixed-fixture",evaluated_draws_hash="fixed-draws",
        left="R1",right="R2",group="B",reference_group="A",unit=:unit_logit,practical_threshold=.3,
        diagnostics=(;qualified=whole),difference_in_differences=(;interval=.95,
            contrast_diagnostics=(;status,rank_normalized_rhat=rhat,bulk_ess=bulk,tail_ess=tail),
            precision=(;mean_mcse,quantiles=((;mcse=lower_mcse),(;mcse=.001),(;mcse=upper_mcse))),
            event_rows=[(;event="above_zero",mean_mcse=event_mcse)]))
end
@testset "Group example separates global diagnostics and focal precision" begin
    good=E.assessment(fixture())
    @test good.numerical_checks_passed
    @test all(r->r.status===:pass,good.checks)
    @test !E.assessment(fixture(;whole=false)).numerical_checks_passed
    @test !E.assessment(fixture(;status=:unavailable)).numerical_checks_passed
    for bad in ((;rhat=1.02),(;bulk=399.),(;tail=399.),(;mean_mcse=.011),
            (;lower_mcse=.021),(;upper_mcse=.021),(;event_mcse=.006))
        result=E.assessment(fixture(;bad...))
        @test !result.numerical_checks_passed
        @test count(r->r.status===:fail,result.checks)==1
    end
    for value in (missing,nothing,NaN,Inf,-.001,true)
        for bad in ((;mean_mcse=value),(;lower_mcse=value),(;event_mcse=value))
            result=E.assessment(fixture(;bad...))
            @test !result.numerical_checks_passed
            @test count(r->r.status===:unavailable,result.checks)==1
        end
    end
    @test E.assessment(fixture(;rhat=1.01,bulk=400.,tail=400.,mean_mcse=.01,
        lower_mcse=.02,upper_mcse=.02,event_mcse=.005)).numerical_checks_passed
    @test good.estimand.group=="B" && good.estimand.reference_group=="A"
    @test good.estimand.practical_threshold==.3 && good.estimand.interval==.95
    @test good.evaluated_draws_hash=="fixed-draws"
    @test good.target_identity=="fixed-fixture" && good.source_sample_content_hash=="fixed-fixture"
end
end
