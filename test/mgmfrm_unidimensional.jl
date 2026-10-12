module UnidimensionalMGMFRMChecks
using Test, BayesianMGMFRM, ForwardDiff, LinearAlgebra, Random
const B=BayesianMGMFRM
const E=B.Experimental
const SCALES=(;person_sd=.8,rater_sd=.6,item_sd=.9,
    log_discrimination_sd=.3,log_consistency_sd=.4,step_sd=.7)

function specification(D=1; R=3,K=4)
    cells=[(p,i,r) for p in 1:4 for i in 1:4 for r in 1:R]
    data=FacetData((;person=first.(cells),item=getindex.(cells,2),rater=last.(cells),
        score=[mod(p+2i+r,K) for (p,i,r) in cells]);
        person=:person,item=:item,rater=:rater,score=:score,category_levels=0:K-1)
    q=D==1 ? trues(4,1) : Bool[1 0;1 0;0 1;0 1]
    mfrm_spec(data;family=:mgmfrm,dimensions=D,thresholds=:partial_credit,q_matrix=q)
end

prior(model=:exchangeable)=E.NormalizedMGMFRMPrior(;prior_model=model,SCALES...,
    source_rater=model===:source ? 2 : nothing)

# Independent scalar adjacent-category equation and full-vector Gaussian law.
# No production transform, probability or log-prior helpers are used.
function reference(x,spec; model=:exchangeable)
    d=spec.data; J=length(d.person_levels); I=length(d.item_levels)
    R=length(d.rater_levels); K=length(d.category_levels); o=0
    take(n)=(v=x[o+1:o+n];o+=n;v)
    theta=take(J); severity_free=take(R-1); difficulty=take(I)
    loga=take(I); logg_free=take(R-1); step_free=[take(K-2) for _ in 1:I]
    @assert o==length(x)
    centered(v)=vcat(v,-sum(v))
    severity=centered(severity_free);logg=centered(logg_free)
    steps=centered.(step_free)
    normal(v,s)=sum(z->-.5*(z/s)^2-log(s)-.5log(2pi),v;init=zero(eltype(x)))
    centered_normal(v,s)=normal(centered(v),s)+log(s)+.5log(2pi*(length(v)+1))
    block_normal=model===:raw ? normal : centered_normal
    lp=normal(theta,SCALES.person_sd)+normal(difficulty,SCALES.item_sd)+
        normal(loga,SCALES.log_discrimination_sd)+block_normal(severity_free,SCALES.rater_sd)+
        block_normal(logg_free,SCALES.log_consistency_sd)+sum(v->block_normal(v,SCALES.step_sd),step_free)
    model===:source && (lp-=logg[2]+SCALES.log_consistency_sd^2*(R-1)/(2R))
    probabilities=map(1:d.n) do n
        p,i,r=d.person[n],d.item[n],d.rater[n]
        adjacent=1.7exp(logg[r]).*(exp(loga[i])*theta[p].-difficulty[i].-severity[r].-steps[i])
        eta=vcat(zero(eltype(x)),cumsum(adjacent));z=maximum(eta)
        exp.(eta.-z)./sum(exp.(eta.-z))
    end
    pointwise=[log(probabilities[n][d.category[n]]) for n in 1:d.n]
    (;logdensity=lp+sum(pointwise),logprior=lp,pointwise,probabilities)
end

@testset "One-dimensional item-step MGMFRM equation and contract" begin
    for (R,K) in ((1,2),(2,3),(3,4))
        spec=specification(;R,K); contract=model_family_contract(spec)
        @test contract.branch===:mgmfrm_unidimensional_item_step_gpcm
        @test contract.dimensionality.classification===:unidimensional
        @test contract.dimensionality.algebraic_aggregation===:single_dimension
        @test contract.dimensionality.source_classification===:not_applicable
        @test contract.category.family===:generalized_partial_credit
        @test contract.steps.owner===:item && contract.support.fit_available
        for model in (R==1 ? (:raw,:exchangeable) : (:raw,:exchangeable,:source))
            target=model===:raw ? B._mgmfrm_guarded_local_fit_logdensity(spec;
                prior=B._SourceFixturePrior(;SCALES...)) : B._normalized_mgmfrm_target(spec,prior(model))
            P=B.LogDensityProblems.dimension(target)
            @test P==4+2(R-1)+8+4(K-2)
            f=x->B.LogDensityProblems.logdensity(target,x)
            for x in (zeros(P),.3sin.(1:P),1.2cos.(1:P))
                expected=reference(x,spec;model)
                @test f(x)≈expected.logdensity atol=1e-10 rtol=1e-12
                @test ForwardDiff.gradient(f,x)≈ForwardDiff.gradient(
                    v->reference(v,spec;model).logdensity,x) atol=1e-9 rtol=1e-10
                @test (model===:raw ? B._source_fixture_logprior(target,x) : B.logprior(target,x))≈expected.logprior atol=1e-10 rtol=1e-12
            end
        end
    end
    spec=specification()
    @test E.surface_contract().families.mgmfrm.minimum_dimensions==1
    @test_throws ArgumentError mfrm_spec(spec.data;family=:mgmfrm,dimensions=0,q_matrix=falses(4,0))
    @test_throws ArgumentError mfrm_spec(spec.data;family=:mgmfrm,dimensions=1,q_matrix=falses(4,1))
    @test_throws ArgumentError E.correlated(spec)
    @test model_family_contract(mfrm_spec(spec.data;family=:gmfrm,
        thresholds=:partial_credit,discrimination=:rater)).steps.owner===:rater
    @test model_family_contract(specification(2)).branch===:mgmfrm_fixed_q_between_item_gpcm
end
end
