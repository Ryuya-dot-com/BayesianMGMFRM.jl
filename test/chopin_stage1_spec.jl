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
    @test length(x.data.optional_levels[:response_id]) == 84
    @test x.data.optional_levels[:response_id] == x.data.person_levels
    @test x.data.optional[:response_id] == x.data.person
    @test length(unique(x.data.optional[:response_id][x.data.person .== 1])) == 1
    response_overlap = rater_overlap(x.data;unit=:response_id)
    performance_overlap = rater_overlap(x.data;unit=:person_item)
    overlap_values(rows) = [(r.rater_a,r.rater_b,r.n_units_a,r.n_units_b,
        r.shared_units,r.union_units,r.jaccard) for r in rows]
    @test length(response_overlap) == 136
    @test overlap_values(response_overlap) == overlap_values(performance_overlap)
    @test extrema(r.shared_units for r in response_overlap) == (69,84)

    # The old metadata made every rating its own response; no judge pair overlapped.
    table = (;person=x.data.person_levels[x.data.person],
        rater=x.data.rater_levels[x.data.rater],item=x.data.item_levels[x.data.item],
        score=x.data.score,observation_id=x.observation_ids)
    legacy_data = FacetData(table;person=:person,rater=:rater,item=:item,score=:score,
        response_id=:observation_id,category_levels=1:25)
    @test all(r.shared_units == 0 for r in rater_overlap(legacy_data;unit=:response_id))
    legacy_spec = mfrm_spec(legacy_data;family=:mfrm,dimensions=1,
        discrimination=:none,thresholds=:partial_credit)
    legacy_design = getdesign(legacy_spec)
    @test x.design.parameter_names == legacy_design.parameter_names
    target = MFRMLogDensity(x.spec;prior=x.prior)
    legacy_target = MFRMLogDensity(legacy_spec;prior=x.prior)
    zero = zeros(L.dimension(target))
    @test isfinite(L.logdensity(target,zero))
    @test loglikelihood(x.design,zero) ≈ -1395log(25) # all 25 categories, not 18
    @test L.logdensity(target,zero) ≈ loglikelihood(x.design,zero)+logprior(x.design,zero,x.prior)
    # Arithmetic parameter fixtures only: no simulated responses or posterior draws.
    for coordinates in (zero,[.15*sin(i) for i in eachindex(zero)])
        @test loglikelihood(x.design,coordinates) == loglikelihood(legacy_design,coordinates)
        @test logprior(x.design,coordinates,x.prior) == logprior(legacy_design,coordinates,x.prior)
        @test L.logdensity(target,coordinates) == L.logdensity(legacy_target,coordinates)
    end
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
