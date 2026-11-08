module RaterFreeIRTChecks
using Test, BayesianMGMFRM, ForwardDiff, LogDensityProblems, Serialization
const B = BayesianMGMFRM
include(joinpath(@__DIR__, "..", "examples", "first_irt_analysis.jl"))

@testset "Explicit absence of a rater facet" begin
    prepared = FirstIRTAnalysis.inputs()
    data, spec = prepared.data, prepared.spec
    rows = facet_response_table(data)
    @test data.n == 72
    @test data.columns.rater === nothing
    @test data.rater_levels == ["no_rater"]
    @test occursin("no rater facet", repr(data))
    @test occursin("raters: none (fixed zero reference)", repr(MIME"text/plain"(), spec))
    explicit = FacetData(rows; person=:person,item=:item,rater=:rater,score=:score,category_levels=0:1)
    @test occursin("1 raters", repr(explicit))
    @test data.person == explicit.person && data.item == explicit.item && data.score == explicit.score
    for thresholds in (:partial_credit,:rating_scale)
        d = getdesign(mfrm_spec(data; thresholds))
        old = getdesign(mfrm_spec(explicit; thresholds))
        @test length(d.parameter_names) == 26
        @test isempty(d.blocks[:rater]) && isempty(d.blocks[:thresholds])
        @test d.parameter_names == old.parameter_names
        target = MFRMLogDensity(d; prior=prepared.prior)
        oldtarget = MFRMLogDensity(old; prior=prepared.prior)
        for q in (zeros(26),collect(range(-1.2,1.2;length=26)),collect(range(-9.,9.;length=26)))
            eta = [q[data.person[n]] - (data.item[n]==1 ? 0. : q[24+data.item[n]-1]) for n in 1:72]
            p = 1 ./ (1 .+ exp.(-eta))
            ll = sum(data.score .* eta .- (max.(0.,eta) .+ log1p.(exp.(-abs.(eta)))))
            prior = sum(-log(1.5)-.5log(2pi)-.5(x/1.5)^2 for x in q[1:24]) +
                sum(-.5log(2pi)-.5x^2 for x in q[25:26])
            @test vec(predictive_probabilities(d,reshape(q,1,26))[1,:,2]) ≈ p atol=1e-12
            @test loglikelihood(d,q) ≈ ll atol=1e-10
            @test LogDensityProblems.logdensity(target,q) ≈ ll+prior atol=1e-10
            @test LogDensityProblems.logdensity(target,q) == LogDensityProblems.logdensity(oldtarget,q)
            gradient = -q ./ vcat(fill(1.5^2,24),ones(2))
            for n in 1:72
                residual=data.score[n]-p[n]
                gradient[data.person[n]] += residual
                data.item[n]>1 && (gradient[24+data.item[n]-1] -= residual)
            end
            @test ForwardDiff.gradient(x -> LogDensityProblems.logdensity(target,x),q) ≈ gradient atol=1e-9
        end
    end
    @test_throws ArgumentError mfrm_spec(data;family=:gmfrm)
    @test_throws ArgumentError mfrm_spec(data;dimensions=2,q_matrix=trues(3,2))
    @test_throws ArgumentError mfrm_spec(data;discrimination=:item)
    @test_throws ArgumentError mfrm_spec(data;bias=[(:rater,:item)])
    @test_throws ArgumentError mfrm_spec(data;anchors=[(block=:rater,level="no_rater",value=1.,type=:hard)])
    anchored=mfrm_spec(data;anchors=[(block=:item,level="I02",value=.2,type=:hard)])
    @test anchored.estimation_status === :fit_supported
    subset=B._loo_refit_training_data(data,collect(4:72))
    @test subset.columns.rater === nothing
    @test subset.category_levels==[0,1] && subset.item_levels==data.item_levels
    @test getdesign(mfrm_spec(subset)).spec.data.columns.rater === nothing
    bytes=IOBuffer(); serialize(bytes,spec); restored=deserialize(IOBuffer(take!(bytes)))
    @test restored.data.columns.rater === nothing
    @test design_identity(restored)==design_identity(spec)
    @test B._data_manifest(data).columns.rater === nothing
    @test_throws ArgumentError FacetData((p=[1,2],i=[1],y=[0,1]);person=:p,item=:i,rater=nothing,score=:y)
    @test_throws ArgumentError FacetData((p=[1,2],i=[1,1],y=[0,missing]);person=:p,item=:i,rater=nothing,score=:y)
    @test_throws ArgumentError FacetData((p=[1,2],i=[1,1],y=[0,2]);person=:p,item=:i,rater=nothing,score=:y,category_levels=0:1)
    @test_throws ArgumentError FacetData((p=[1,2],i=[1,1],y=[0,1]);person=:p,item=:i,rater=:absent,score=:y)
    for column in (:person,:item,:score,:group)
        options=merge((person=:p,item=:i,score=:y,rater=nothing),NamedTuple{(column,)}((:absent,)))
        @test_throws ArgumentError FacetData((p=[1,2],i=[1,1],y=[0,1]);options...)
    end
    disconnected=FacetData((p=[1,1,2,2],i=[1,1,2,2],y=[0,1,0,1]);
        person=:p,item=:i,score=:y,rater=nothing,category_levels=0:1)
    @test !validate_design(disconnected).passed
    # Fixed arithmetic polytomous input, not a recovery simulation.
    cells=[(p,i) for p in 1:4 for i in 1:3]
    table=(p=first.(cells),i=last.(cells),y=[mod(p+i,3) for (p,i) in cells])
    polytomous=FacetData(table;person=:p,item=:i,score=:y,rater=nothing,category_levels=0:2)
    for thresholds in (:partial_credit,:rating_scale)
        d=getdesign(mfrm_spec(polytomous;thresholds))
        old=FacetData(merge(table,(r=fill("no_rater",12),));person=:p,item=:i,score=:y,rater=:r,category_levels=0:2)
        od=getdesign(mfrm_spec(old;thresholds))
        q=collect(range(-.4,.7;length=length(d.parameter_names)))
        @test loglikelihood(d,q)==loglikelihood(od,q)
    end
end
end
