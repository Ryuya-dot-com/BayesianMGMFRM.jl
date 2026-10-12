using Test
include(joinpath(@__DIR__,"../scripts/mgmfrm_core_evaluation.jl"))
const E=MGMFRMCoreEvaluation
@testset "Fixed retained length belongs to the joint-prior plan" begin
    args=(;mode=:prior,backend=:advancedhmc,generator_sha256=repeat("a",64))
    original=E.evaluation_plan(["one"];args...)
    explicit=E.evaluation_plan(["one"];args...,retained_per_chain=1000)
    longer=E.evaluation_plan(["one"];args...,retained_per_chain=4000)
    @test original==explicit
    @test original.controls==E.P.CONTROLS
    @test longer.controls==merge(E.P.CONTROLS,(;ndraws=4000))
    @test longer.content_hash!=original.content_hash
    @test longer.criteria==original.criteria
    @test E.check_seal(longer)==longer
    for n in (0,-1,true,1.5)
        @test_throws ArgumentError E.evaluation_plan(["one"];args...,retained_per_chain=n)
    end
    for mode in (:fixed,:recovery)
        @test_throws ArgumentError E.evaluation_plan(["one"];mode,condition=mode===:recovery ? "R0" : nothing,
            backend=:advancedhmc,generator_sha256=repeat("a",64),retained_per_chain=4000)
    end
end
