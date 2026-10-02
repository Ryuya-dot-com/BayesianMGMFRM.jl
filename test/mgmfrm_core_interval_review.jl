using Test, Random, Statistics
include(joinpath(@__DIR__, "..", "scripts", "mgmfrm_core_interval_review.jl"))
const I = MGMFRMCoreIntervalReview

@testset "Named interval review and finite-draw limitations" begin
    x = randn(MersenneTwister(9320101), 4000, 2)
    result = I.interval_review(x, Dict("a"=>0., "b"=>10.);
        chains=4, parameter_names=["a", "b"])
    a, b = result.rows
    @test result.total_draws == 4000 && result.draws_per_chain == 1000
    @test !result.diagnostic_qualification_applied && !result.calibration_verified
    @test all(r -> r.covered, a.intervals)
    @test all(r -> !r.covered, b.intervals)
    @test .45 < a.cdf.strictly_below < .55
    @test 0 < a.cdf.mean_mcse < .02
    @test a.cdf.ties == 0
    # No exceedances in these samples does not mean zero uncertainty about a tail.
    @test b.cdf.strictly_below == b.cdf.less_or_equal == 1
    @test ismissing(b.cdf.mean_mcse)
    @test b.cdf.mean_mcse_status == :degenerate_draws
    @test all(r -> r.boundary_sensitivity == :beyond_two_mcse, b.intervals)
    @test all(r -> r.maximum_endpoint_mcse_over_width < .05, a.intervals)
    # Translation and positive rescaling preserve CDF, coverage and relative MCSE.
    transformed = I.interval_review(3 .* x .+ 7, Dict("a"=>7., "b"=>37.);
        chains=4, parameter_names=["a", "b"])
    @test transformed.rows[1].cdf == a.cdf
    for (r, s) in zip(a.intervals, transformed.rows[1].intervals)
        @test s.covered == r.covered
        @test s.lower ≈ 3r.lower + 7
        @test s.upper ≈ 3r.upper + 7
        @test s.maximum_endpoint_mcse_over_width ≈ r.maximum_endpoint_mcse_over_width
    end
    boundary = I.interval_review(x[:, 1:1], Dict("a"=>a.intervals[1].lower);
        chains=4, parameter_names=["a"])
    @test only(boundary.rows).intervals[1].boundary_sensitivity == :within_two_mcse
    tied = I.interval_review(zeros(80, 1), Dict("a"=>0.); chains=4, parameter_names=["a"])
    t = only(tied.rows)
    @test t.cdf.strictly_below == 0 && t.cdf.less_or_equal == 1 && t.cdf.ties == 80
    @test ismissing(t.cdf.mean_mcse)
    @test all(r -> r.covered && r.boundary_sensitivity == :mcse_unavailable, t.intervals)
    short = I.interval_review(x[1:8, 1:1], Dict("a"=>0.); chains=4, parameter_names=["a"])
    @test only(short.rows).precision.mcse_status == :insufficient_draws
    @test all(r -> r.boundary_sensitivity == :mcse_unavailable, only(short.rows).intervals)
    for truth in (Dict("a"=>0.), Dict("a"=>0., "c"=>0.), Dict("a"=>NaN, "b"=>0.))
        @test_throws ArgumentError I.interval_review(x, truth; chains=4, parameter_names=["a", "b"])
    end
    @test_throws ArgumentError I.interval_review(x, Dict("a"=>0.); chains=4, parameter_names=["a", "a"])
    @test_throws ArgumentError I.interval_review(fill(Inf, 80, 1), Dict("a"=>0.); chains=4, parameter_names=["a"])
    @test_throws ArgumentError I.interval_review(x[1:79, 1:1], Dict("a"=>0.); chains=4, parameter_names=["a"])
    @test_throws ArgumentError I.interval_review(x[:, 1:1], Dict("a"=>0.); chains=0, parameter_names=["a"])
    @test_throws ArgumentError I.interval_review(x[:, 1:1], Dict("a"=>0.); chains=true, parameter_names=["a"])
end

@testset "Truth-blind quantile precision and unresolved mass" begin
    x = randn(MersenneTwister(9320102), 4000, 2)
    result = I.quantile_precision(x; chains=4, parameter_names=["a", "b"])
    transformed = I.quantile_precision(3 .* x .+ 7; chains=4, parameter_names=["a", "b"])
    @test !result.truth_used && !result.probability_bound_verified
    @test !result.diagnostic_qualification_applied && !result.scientific_acceptance
    for (j,(r,s)) in enumerate(zip(result.rows,transformed.rows))
        @test r.median_precision_available && r.coverage_precision_available
        @test r.rank_rhat ≈ s.rank_rhat
        @test r.median_guard_mass == s.median_guard_mass
        @test r.coverage_guard_mass == s.coverage_guard_mass
        lo,med,hi = r.quantiles
        # Direct empirical CDF differences check the median band; count the
        # endpoint union explicitly so overlap cannot inflate its mass.
        cdf(v) = count(<=(v),x[:,j])/size(x,1)
        @test r.median_guard_mass ≈ cdf(med.estimate+2med.mcse)-cdf(med.estimate-2med.mcse)
        @test r.coverage_guard_mass == count(v ->
            lo.estimate-2lo.mcse <= v <= lo.estimate+2lo.mcse ||
            hi.estimate-2hi.mcse <= v <= hi.estimate+2hi.mcse,x[:,j])/size(x,1)
        for (q,t) in zip(r.quantiles,s.quantiles)
            @test q.ess ≈ t.ess
            @test q.mcse ≈ t.mcse/3
            @test q.probability_mcse ≈ t.probability_mcse
        end
    end
    for values in (zeros(80,1),x[1:8,1:1])
        r = only(I.quantile_precision(values; chains=4,parameter_names=["a"]).rows)
        @test !r.median_precision_available && !r.coverage_precision_available
        @test r.median_unresolved_mass_proxy == r.coverage_unresolved_mass_proxy == 1
        @test ismissing(r.median_guard_mass) && ismissing(r.rank_rhat)
    end
    single = only(I.quantile_precision(x[:,1:1];chains=1,parameter_names=["a"]).rows)
    @test single.mcse_status == :insufficient_chains
    for (values,names,chains) in ((x,["a","a"],4),(x,["a"," "],4),
            (x,["a"],4),(fill(Inf,80,1),["a"],4),(trues(80,1),["a"],4),
            (x[1:79,1:1],["a"],4),(x,["a","b"],0),(x,["a","b"],true))
        @test_throws ArgumentError I.quantile_precision(values;parameter_names=names,chains)
    end
end
