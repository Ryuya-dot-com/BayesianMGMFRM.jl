# Opt-in integration check using the locally imported official PDF. No MCMC.
using Test, SHA, JSON3, BayesianMGMFRM
import LogDensityProblems as L
include("../scripts/chopin_stage1_spec.jl")
length(ARGS) == 1 || error("provide the new Chopin input directory")
x = ChopinStage1Spec.prepare(ARGS[1])
@testset "Chopin stage-1 raw data to existing MFRM target" begin
    @test x.report.passed
    @test x.data.n == 1395
    @test x.data.category_levels == collect(1:25)
    @test sort(unique(x.data.score)) == collect(8:25)
    @test length(x.design.parameter_names) == 123 # 84 person + 16 rater + 23 steps
    @test length(x.design.blocks[:item]) == 0
    @test length(x.design.blocks[:rater]) == 16
    @test x.data.rater_levels[1] == "J01"
    @test x.data.score[1:6] == [14,17,19,21,21,18] # recusal column J06 omitted
    @test x.observation_ids[6] == "2025-S1-C001-J07"
    @test length(unique(x.observation_ids)) == 1395
    target = MFRMLogDensity(x.spec;prior=x.prior)
    zero = zeros(L.dimension(target))
    @test isfinite(L.logdensity(target,zero))
    @test loglikelihood(x.design,zero) ≈ -1395log(25) # all 25 categories, not 18
    @test L.logdensity(target,zero) ≈ loglikelihood(x.design,zero)+logprior(x.design,zero,x.prior)
    @test any(i -> i.code == :unobserved_declared_endpoint,x.report.issues)
    mktempdir() do dir
        path = joinpath(dir,"spec.json")
        ChopinStage1Spec.write_report(ARGS[1],path)
        record = JSON3.read(read(path,String))
        @test record.parameter_count == 123
        @test record.posterior_fitted == false
        @test_throws ArgumentError ChopinStage1Spec.write_report(ARGS[1],path)
        for name in ("manifest.json","ratings.json","cells.json","performances.json","judges.json","stage1-layout.txt")
            cp(joinpath(ARGS[1],name),joinpath(dir,name))
        end
        open(joinpath(dir,"ratings.json"),"a") do io
            write(io," ")
        end
        @test_throws ArgumentError ChopinStage1Spec.prepare(dir)
    end
end
