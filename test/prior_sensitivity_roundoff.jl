module PriorSensitivityRoundoffChecks
using BayesianMGMFRM, Test
const B=BayesianMGMFRM
@testset "Saved summary comparison permits only bounded reductions" begin
    actual=[(;mean_logdensity=-1000.,mean_n_steps=15.,mean_tree_depth=4.,mean_step_size=.2,e_bfmi=.9,
        n_divergences=0,flag=:ok,minimum_logdensity=-1200.)]
    for key in (:mean_logdensity,:mean_n_steps,:mean_tree_depth,:mean_step_size,:e_bfmi)
        for relative in (eps(Float64),1e-13)
            changed=[merge(only(actual),NamedTuple{(key,)}((only(actual)[key]*(1+relative),)))]
            @test B._generalized_sampler_rows_equal(actual,changed,1000)
        end
        changed=[merge(only(actual),NamedTuple{(key,)}((only(actual)[key]+.001,)))]
        @test !B._generalized_sampler_rows_equal(actual,changed,1000)
        changed=[merge(only(actual),NamedTuple{(key,)}((NaN,)))]
        @test !B._generalized_sampler_rows_equal(actual,changed,1000)
    end
    @test !B._generalized_sampler_rows_equal(actual,[merge(only(actual),(;n_divergences=1))],1000)
    @test !B._generalized_sampler_rows_equal(actual,[merge(only(actual),(;flag=:warning))],1000)
    @test !B._generalized_sampler_rows_equal(actual,[merge(only(actual),(;minimum_logdensity= -1200.0 + 1e-12))],1000)
    @test !B._generalized_sampler_rows_equal(actual,[],1000)
    context=(;spec=(;family=:mgmfrm,dimension_labels=["D1"]),chain_ids=[1],
        coordinates=[(;parameter="x",values=[1.],block=:person,dimension=1,fixed=true)])
    @test_throws ArgumentError B._sensitivity_estimands(["x"],context)
    e=only(B._sensitivity_estimands(["x"=>"x"],context))
    r=B._sensitivity_row(e,context,.99,1.,nothing,2.)
    @test ismissing(r.sd)
    @test r.numerical_decision===:structurally_fixed
end
end
