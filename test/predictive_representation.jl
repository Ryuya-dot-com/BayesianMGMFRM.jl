using Test, BayesianMGMFRM, Distributions
@testset "Unrepresentable predictive replicas are not endpoint atoms" begin
 d,o=slope_fixture();o=merge(o,(intercept=Normal(100.,1e-10),))
 t=mfrm_spec(d;o...);r=prior_predictive_check(t;ndraws=3,seed=341)
 @test !r.replications_complete && length(r.numerical_failures)==3
 @test all(c->c.defined_replicas==0 && c.lower===nothing,r.cells)
 @test all(isnothing,r.replicated_statistics)
 @test RS.check_bounded_report(r)===r
 @test_throws ArgumentError RS.check_bounded_report(merge(r,(replications_complete=true,)))
 @test_throws ArgumentError RS.check_bounded_report(merge(r,(interval_conditioning=:requested_predictive_distribution,)))
end
