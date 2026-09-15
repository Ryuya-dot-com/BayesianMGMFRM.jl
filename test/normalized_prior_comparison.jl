module NormalizedPriorComparisonChecks
using Test, Random, Statistics
include(joinpath(@__DIR__, "..", "scripts", "run_normalized_prior_comparison.jl"))
const C = NormalizedPriorComparison

@testset "normalized-prior comparison decisions (synthetic, no fitting)" begin
    sample_summary(value; mcse = 0.01, sd = 1.0, passed = true, name = "p") =
        [(; parameter = name, posterior_sd = sd, diagnostic_passed = passed,
            summaries = ((; statistic = :mean, estimate = value, mcse),))]
    score(a, b; diagnostic_passed = true) = only(C.compare(a, b; diagnostic_passed))
    a, b = sample_summary(0.0), sample_summary(0.02)
    row = score(a, b)
    @test row.status === :within_resolution
    @test row.combined_mcse ≈ sqrt(0.0002)
    @test row.difference == 0.02
    @test row.absolute_mcse_z ≈ sqrt(2)
    @test row.difference_bound_sd_ratio ≈ 0.02 + 4.5sqrt(0.0002)
    @test score(b, a).difference == -row.difference
    @test score(b, a).status == row.status
    @test score(a, b; diagnostic_passed = false).status === :diagnostic_hold
    @test score(sample_summary(0.0; passed = false), b).status === :diagnostic_hold
    @test score(a, sample_summary(0.0; mcse = missing)).status === :mcse_unavailable
    @test score(a, sample_summary(0.0; mcse = 0.0)).status === :mcse_unavailable
    @test score(a, sample_summary(0.0; mcse = NaN)).status === :mcse_unavailable
    @test score(a, sample_summary(0.0; mcse = 0.1)).status === :precision_hold
    @test score(a, sample_summary(0.2)).status === :backend_difference
    @test score(sample_summary(0.0; mcse = 0.05),
        sample_summary(0.0; mcse = 0.05)).status === :resolution_hold
    @test_throws ArgumentError C.compare(a, sample_summary(0.0; name = "wrong"); diagnostic_passed = true)
    @test_throws ArgumentError C.compare(a, vcat(b, b); diagnostic_passed = true)
    @test_throws ArgumentError C.compare([], []; diagnostic_passed = true)
    # Real existing MCSE/diagnostic machinery: retain chains, scale and ordering.
    draws = randn(MersenneTwister(914), 4000, 2)
    summaries = C.summarize(draws, ["a", "b"], 4)
    scaled = C.summarize(2draws .+ 3, ["a", "b"], 4)
    for (x, y) in zip(summaries, scaled)
        @test x.diagnostic_passed
        @test x.mcse_status === :available
        @test length(x.summaries) == 5
        @test y.posterior_sd ≈ 2x.posterior_sd
        for (u, v) in zip(x.summaries, y.summaries)
            @test v.estimate ≈ (u.statistic === :sd ? 2u.estimate : 2u.estimate + 3)
            @test v.mcse ≈ 2u.mcse
        end
    end
    targets = C.targets()
    @test targets[1].base.design.spec.data.n == 72
    @test targets[1].base.design.spec.q_matrix == Bool[1 0; 1 0; 0 1; 0 1]
    @test targets[1].base.design.spec.data.category_levels == [0, 1, 2]
    @test targets[2].source_rater_index == 2
    @test targets[1].base.design.spec.data.category == targets[2].base.design.spec.data.category
    @test length(unique(vcat(collect.(C.SEEDS)...))) == 4
    @test C.PRECISION_CONTROLS.ndraws == 4C.CONTROLS.ndraws
    @test Base.structdiff(C.PRECISION_CONTROLS, (; ndraws = nothing)) ==
        Base.structdiff(C.CONTROLS, (; ndraws = nothing))
    @test C.PRECISION_SEEDS == ((9174101, 9174102), (9174201, 9174202))
    @test length(unique(vcat(collect.(C.SEEDS)..., collect.(C.PRECISION_SEEDS)...))) == 8
    mktempdir() do directory
        @test_throws ArgumentError C.run(directory; precision_followup = true)
    end
end
end
