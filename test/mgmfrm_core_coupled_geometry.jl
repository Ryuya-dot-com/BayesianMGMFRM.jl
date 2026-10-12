module MGMFRMCoreCoupledGeometryChecks
using Test, LinearAlgebra, ForwardDiff, BayesianMGMFRM
include("../scripts/mgmfrm_core_coupled_geometry.jl")
const C = MGMFRMCoreCoupledGeometry
const B = BayesianMGMFRM

@testset "Coupled location-map gradients and nonlinear curvature without fits" begin
    for (n,Q) in ((1,Bool[1 0;1 1;0 1]),(5,Bool[1 0;1 1;0 1]),
            (4,Bool[1 0 0;0 1 0;0 0 1;1 1 1]))
        cells = [(p,i,r) for p in 1:n for i in axes(Q,1) for r in 1:3]
        data = FacetData((;person=first.(cells),item=getindex.(cells,2),rater=last.(cells),
            score=[mod(sum(c),3) for c in cells]);person=:person,item=:item,rater=:rater,
            score=:score,category_levels=0:2)
        spec = mfrm_spec(data;family=:mgmfrm,dimensions=size(Q,2),q_matrix=Q,thresholds=:partial_credit)
        base = B._mgmfrm_guarded_local_fit_logdensity(spec;
            prior=B._SourceFixturePrior(person_sd=1.3,item_sd=.7))
        raw = [.35sin(.7j)+.12 for j in 1:C.L.dimension(base)]
        original = copy(raw)
        result = C.probe(base,raw)
        J = result.jacobian
        @test raw == original
        @test result.restored ≈ raw atol=1e-12
        @test result.lp ≈ result.raw_lp atol=1e-9
        @test J ≈ result.automatic_jacobian atol=2e-12
        @test abs(det(J)) ≈ 1 atol=1e-12
        @test result.gradient ≈ J'*result.raw_gradient atol=2e-9
        target = B._MGMFRMLocationLogDensity(base)
        forward = x -> B._mgmfrm_location_to_raw(target,x)
        for pair in result.pairs
            @test pair.chain_rule_error < 2e-8
            second = [C.mixed(x -> forward(x)[j],result.q,pair.v,pair.w) for j in eachindex(raw)]
            @test second ≈ pair.second atol=2e-12
            # Numerical curvature from gradients includes the changing Jacobian.
            h = 1e-4
            gradient = x -> ForwardDiff.gradient(y -> C.L.logdensity(target,y),x)
            finite = dot(pair.v,gradient(result.q+h*pair.w)-gradient(result.q-h*pair.w))/(2h)
            @test finite ≈ pair.curvature atol=2e-6 rtol=2e-7
        end
        # The incorrect omissions must be visible; |det J|=1 is insufficient.
        wrong = copy(J)
        wrong[base.blueprint.blocks[:item],base.blueprint.blocks[:log_item_dimension_discrimination]] .= 0
        @test maximum(abs,wrong'*result.raw_gradient-result.gradient) > 1e-6
        @test maximum(abs(p.nonlinear_term) for p in result.pairs) > 1e-6
        @test abs(B._source_fixture_logprior(base,result.q)-B._source_fixture_logprior(base,raw)) > 1e-6
    end
end
end
