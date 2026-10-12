module SavedMGMFRMContrastChecks
using Test, Random, Statistics
include(joinpath(@__DIR__, "..", "examples", "saved_mgmfrm_contrasts.jl"))
const B = BayesianMGMFRM
include("fixtures/reporting_fit.jl")

@testset "paired saved-draw contrasts without fitting" begin
    rng = MersenneTwister(9232026)
    common = 5randn(rng, 400)
    delta = 0.2 .+ 0.1randn(rng, 400)
    left, right = common .+ delta, common
    result = paired_contrast_summary(left, right; chains = 4, rope = (0.0, 0.3))
    @test result.mean ≈ mean(delta)
    @test result.sd ≈ std(delta)
    @test result.lower ≈ quantile(delta, 0.05)
    @test result.upper ≈ quantile(delta, 0.95)
    # Marginal-interval subtraction discards the strong shared posterior movement.
    @test result.upper - result.lower < (quantile(left, .95) - quantile(right, .05)) / 10
    @test result.precision.mean_mcse > 0
    @test result.contrast_diagnostics.status === :available
    @test sum(r.count for r in result.event_rows[2:4]) == 400
    @test result.event_rows[3].probability ≈ count(x -> 0 <= x <= .3, delta) / 400
    swapped = paired_contrast_summary(right, left; chains = 4, rope = (-.3, 0.0))
    @test swapped.mean ≈ -result.mean
    @test swapped.lower ≈ -result.upper
    @test swapped.upper ≈ -result.lower
    @test swapped.event_rows[3].probability == result.event_rows[3].probability
    sticky = paired_contrast_summary(repeat([fill(-1., 40); fill(1., 40)], 5),
        zeros(400); chains = 4)
    event = only(sticky.event_rows)
    @test event.mean_mcse > sqrt(event.probability * (1 - event.probability) / 400)
    separated = paired_contrast_summary(repeat([-5., -1., 1., 5.]; inner = 100) .+
        .1randn(rng, 400), zeros(400); chains = 4)
    @test separated.contrast_diagnostics.rank_normalized_rhat > 1.1
    @test !separated.contrast_diagnostics.thresholds_applied

    logged = paired_contrast_summary(exp.(left), exp.(right); chains = 4,
        log_ratio = true, rope = (0.0, .3))
    @test logged.mean ≈ result.mean
    @test logged.ratio_interval.lower ≈ exp(result.lower)
    @test logged.ratio_interval.upper ≈ exp(result.upper)
    @test logged.precision.mean_mcse ≈ result.precision.mean_mcse
    all_positive = paired_contrast_summary(2 .+ rand(rng, 400), zeros(400); chains = 4)
    @test only(all_positive.event_rows).probability == 1
    @test only(all_positive.event_rows).mcse_status === :degenerate_draws
    @test ismissing(only(all_positive.event_rows).mean_mcse)
    flat = paired_contrast_summary(ones(40), zeros(40); chains = 4)
    @test flat.contrast_diagnostics.status === :degenerate_draws
    @test ismissing(flat.contrast_diagnostics.rank_normalized_rhat)
    @test ismissing(flat.precision.mean_mcse)
    @test ismissing(paired_contrast_summary([1.], [0.]; chains = 1).sd)
    extreme = paired_contrast_summary(fill(floatmax(Float64), 40), fill(floatmin(Float64), 40);
        chains = 4, log_ratio = true)
    @test extreme.ratio_interval.status === :not_representable
    @test ismissing(extreme.ratio_interval.upper)
    zeros_event = paired_contrast_summary(-ones(40), zeros(40); chains = 4)
    @test only(zeros_event.event_rows).probability == 0
    @test ismissing(only(zeros_event.event_rows).mean_mcse)
    @test paired_contrast_summary(left, right; chains = 1).contrast_diagnostics.status === :insufficient_chains
    @test paired_contrast_summary(left[1:20], right[1:20]; chains = 4).contrast_diagnostics.status === :insufficient_draws
    @test_throws ArgumentError paired_contrast_summary(left, right[1:10]; chains = 4)
    @test_throws ArgumentError paired_contrast_summary(left, right; chains = 3)
    @test_throws ArgumentError paired_contrast_summary(left, right; chains = 0)
    @test_throws ArgumentError paired_contrast_summary(left, right; chains = 4, interval = 1)
    @test_throws ArgumentError paired_contrast_summary(left, right; chains = 4, rope = (.3, .1))
    @test_throws ArgumentError paired_contrast_summary(left, right; chains = 4, rope = (0., Inf))
    @test_throws ArgumentError paired_contrast_summary(left, right; chains = 4, log_ratio = true)
    @test_throws ArgumentError paired_contrast_summary([NaN, 1.], [0., 0.]; chains = 2)
end

@testset "MGMFRM contrast selection and cache reload without fitting" begin
    # Reuse deterministic reporting inputs, not posterior or backend evidence.
    cells = [(p, i, r) for p in ("P2", "P1") for i in ("I2", "I1") for r in ("R3", "R1", "R2")]
    data = FacetData((; person = first.(cells), item = getindex.(cells, 2),
        rater = last.(cells), score = [mod(i, 3) for i in eachindex(cells)]);
        person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:2)
    fitted = reporting_fit(:mgmfrm; data, chains = 2, ndraws = 20,
        dimension_labels = ["Ability α", "Ability β"])
    before = copy(fitted.direct_draws)
    check = diagnostics(fitted; view = :public)
    @test !check.summary.passed
    requests = [
        (; kind = :ability, left = "P2", right = "P1", dimension = "Ability α"),
        (; kind = :ability, left = "P2", right = "P1", dimension = "Ability β"),
        (; kind = :severity, left = "R3", right = "R1"),
        (; kind = :log_consistency_ratio, left = "R3", right = "R1")]
    names = fit_metadata(fitted; view = :public).direct_parameter_names
    results = map(requests) do request
        selected = request.kind === :ability ?
            ["person[$p,$(request.dimension)]" for p in ("P2", "P1")] :
            request.kind === :severity ? ["rater[R3]", "rater[R1]"] :
            ["rater_consistency[rater=R3]", "rater_consistency[rater=R1]"]
        a, b = [only(findall(==(name), names)) for name in selected]
        x, y = fitted.direct_draws[:, a], fitted.direct_draws[:, b]
        expected = request.kind === :log_consistency_ratio ? log.(x) - log.(y) : x - y
        result = saved_mgmfrm_contrast(fitted; request..., rope = (-.01, .01))
        @test result.summary.mean ≈ mean(expected)
        @test result.summary.lower ≈ quantile(expected, .05)
        @test result.summary.upper ≈ quantile(expected, .95)
        @test isequal(result.whole_fit_diagnostics, check.summary)
        @test result.summary.total_draws == 40
        @test result.summary.chains == 2 && result.summary.draws_per_chain == 20
        result
    end
    @test fitted.direct_draws == before
    # The selected last rater is reconstructed; selection must include it.
    a, b, reconstructed = [only(findall(==("rater[$r]"), names)) for r in ("R1", "R2", "R3")]
    @test fitted.direct_draws[:, reconstructed] ≈ -fitted.direct_draws[:, a] - fitted.direct_draws[:, b]
    mktempdir() do directory
        path = joinpath(directory, "synthetic-fit.jls")
        save_fit_cache(path, fitted)
        bytes = read(path)
        restored = load_fit_cache(path)
        for (request, expected) in zip(requests, results)
            @test isequal(saved_mgmfrm_contrast(restored; request..., rope = (-.01, .01)), expected)
        end
        @test read(path) == bytes
    end
    for request in ((; kind = :unknown, left = "R1", right = "R2"),
            (; kind = :severity, left = "R1", right = "R1"),
            (; kind = :severity, left = "missing", right = "R2"),
            (; kind = :severity, left = "R1", right = "R2", dimension = "Ability α"),
            (; kind = :ability, left = "P1", right = "P2"),
            (; kind = :ability, left = "P1", right = "P2", dimension = "missing"))
        @test_throws ArgumentError saved_mgmfrm_contrast(fitted; request...)
    end
    for field in (:chain_ids, :iterations)
        damaged = deepcopy(fitted)
        getproperty(damaged, field)[1] = -1
        @test_throws ArgumentError saved_mgmfrm_contrast(damaged; first(requests)...)
    end
end
end
