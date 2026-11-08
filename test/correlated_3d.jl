module Correlated3DPublicChecks
using BayesianMGMFRM, Test, LinearAlgebra, ForwardDiff
import LogDensityProblems as L
const C=BayesianMGMFRM.Experimental.Correlated3D
const S=(person_sd=1.,rater_sd=.5,item_sd=.7,log_discrimination_sd=.3,log_consistency_sd=.4,step_sd=.6)
function fixture(;D=3,K=4,mixed=false,incomplete=false)
    cells=[(p,i,r) for p in 1:3 for i in 1:6 for r in 1:3 if !(incomplete && p==1 && i>4)]
    data=FacetData((person=first.(cells),item=getindex.(cells,2),rater=last.(cells),score=[mod(p+i+r,K) for (p,i,r) in cells]);
        person=:person,item=:item,rater=:rater,score=:score,category_levels=0:K-1)
    Q=[j==1+mod(cld(i,2)-1,D) for i in 1:6,j in 1:D];mixed && (Q[1,2]=true)
    mfrm_spec(data;family=:mgmfrm,dimensions=D,thresholds=:partial_credit,q_matrix=Q,dimension_labels=["T$i" for i in 1:D])
end
@testset "Public three-trait boundary and interpretation" begin
    for spec in (fixture(;D=2),fixture(;K=2),fixture(;mixed=true),fixture(;incomplete=true))
        @test_throws ArgumentError C.model(spec;scales=S,lkj_eta=2.)
    end
    t=C.model(fixture();scales=S,lkj_eta=2.5);q=C.initial(t);q[end-2:end]=[.3,-.5,.4]
    rows=C.correlations(t,q)
    @test last(rows).correlation != tanh(q[end])
    @test last(rows).correlation≈tanh(.3)*tanh(-.5)+tanh(.4)*sqrt((1-tanh(.3)^2)*(1-tanh(-.5)^2))
    @test isfinite(L.logdensity(t,q))
    @test all(isfinite,ForwardDiff.gradient(x->L.logdensity(C.SamplingTarget(t),x),q))
    @test C.contract().scientific_acceptance==false
    @test C.contract(t).person_marginal_sd==1
    @test_throws ArgumentError C.generate(t;seed=true)
    @test_throws ArgumentError C.generate(t;seed=-1)
    @test_throws ArgumentError C.generate(t;seed=1,q=q[1:end-1])
    @test_throws ArgumentError C.model(fixture();scales=merge(S,(person_sd=2.,)),lkj_eta=2.)
    @test_throws ArgumentError C.restore((schema="point",))
    @test_throws ArgumentError C.summaries(zeros(8,1),["x"],2,1.)
end
end
