using Test
using BayesianMGMFRM

@testset "FACETS compatibility plugin statistics" begin
    table = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2", "E3", "E3", "E3"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2, 1, 2, 0],
    )
    data = FacetData(
        table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
    spec = mfrm_spec(data; thresholds = :partial_credit)
    design = getdesign(spec)
    n_parameters = length(design.parameter_names)
    draws = zeros(2, n_parameters)
    draws[2, :] .= range(-0.2, 0.2; length = n_parameters)
    plugin = vec(sum(draws; dims = 1) ./ size(draws, 1))
    fit_result = MFRMFit(
        design,
        MFRMPrior(),
        draws,
        zeros(2),
        1.0,
        [1, 1],
        [1, 2],
        [1.0],
        :julia,
        :random_walk_metropolis,
        0,
        0.1,
    )

    rows = facets_compatibility_stats(fit_result; draw_indices = [1, 2])
    report_rows = facets_report(fit_result; draw_indices = [1, 2])
    supplied_rows = facets_compatibility_stats(design, plugin)
    @test isequal(report_rows, rows)
    @test isequal(facets_report(design, plugin), supplied_rows)
    @test length(rows) == length(data.rater_levels)
    @test [row.level for row in rows] == data.rater_levels
    @test [row.infit for row in rows] ≈ [row.infit for row in supplied_rows]
    @test [row.outfit for row in rows] ≈ [row.outfit for row in supplied_rows]
    @test [row.infit_df for row in rows] ≈ [row.infit_df for row in supplied_rows]
    @test [row.outfit_df for row in rows] ≈ [row.outfit_df for row in supplied_rows]
    @test all(row -> row.schema ==
        "bayesianmgmfrm.facets_compatibility_stats.v1", rows)
    @test all(row -> row.model_family === :mfrm, rows)
    @test all(row -> row.threshold_regime === :partial_credit, rows)
    @test all(row -> row.rasch_model === :pcm, rows)
    @test all(row -> row.method === :posterior_mean_plugin, rows)
    @test all(row -> row.parameter_estimate === :posterior_mean, rows)
    @test all(row -> row.n_draws_aggregated == 2, rows)
    @test all(row -> row.weighting === :unit, rows)
    @test all(row -> row.df_method ===
        :facets_wright_masters_fourth_moment, rows)
    @test all(row -> row.zstd_transform ===
        :wilson_hilferty_cube_root, rows)
    @test all(row -> row.approximation ===
        :facets_compatible_bayesian_plugin, rows)
    @test all(row -> row.facets_software_equivalence === :not_claimed, rows)
    @test all(row -> row.posterior_uncertainty === :not_propagated, rows)
    @test all(row -> row.generalized_model_support === :rejected, rows)
    @test all(row -> row.flag === :ok, rows)

    probabilities = predictive_probabilities(
        design,
        reshape(plugin, 1, length(plugin)),
    )
    levels = Float64.(data.category_levels)
    observations = findall(==(1), data.rater)
    expected = [
        sum(probabilities[1, row, category] * levels[category]
            for category in eachindex(levels))
        for row in observations
    ]
    variance = [
        sum(probabilities[1, row, category] *
            (levels[category] - expected[index])^2
            for category in eachindex(levels))
        for (index, row) in pairs(observations)
    ]
    fourth = [
        sum(probabilities[1, row, category] *
            (levels[category] - expected[index])^4
            for category in eachindex(levels))
        for (index, row) in pairs(observations)
    ]
    residual = Float64.(data.score[observations]) .- expected
    infit_information = sum(variance)
    outfit_weight_sum = Float64(length(observations))
    infit_denominator = sum(fourth .- variance .^ 2)
    outfit_denominator = sum(fourth ./ variance .^ 2 .- 1)
    expected_infit = sum(residual .^ 2) / infit_information
    expected_outfit = sum(residual .^ 2 ./ variance) / outfit_weight_sum
    expected_infit_df = 2 * infit_information^2 / infit_denominator
    expected_outfit_df = 2 * outfit_weight_sum^2 / outfit_denominator
    expected_infit_zstd = clamp(
        (cbrt(expected_infit) - (1 - 2 / (9 * expected_infit_df))) /
            sqrt(2 / (9 * expected_infit_df)),
        -9.0,
        9.0,
    )
    expected_outfit_zstd = clamp(
        (cbrt(expected_outfit) - (1 - 2 / (9 * expected_outfit_df))) /
            sqrt(2 / (9 * expected_outfit_df)),
        -9.0,
        9.0,
    )
    r1 = first(rows)
    @test r1.infit_information ≈ infit_information
    @test r1.outfit_weight_sum ≈ outfit_weight_sum
    @test r1.infit_fourth_moment_denominator ≈ infit_denominator
    @test r1.outfit_fourth_moment_denominator ≈ outfit_denominator
    @test r1.infit ≈ expected_infit
    @test r1.outfit ≈ expected_outfit
    @test r1.infit_df ≈ expected_infit_df
    @test r1.outfit_df ≈ expected_outfit_df
    @test r1.infit_zstd ≈ expected_infit_zstd
    @test r1.outfit_zstd ≈ expected_outfit_zstd

    capped = facets_compatibility_stats(
        fit_result;
        draw_indices = [1, 2],
        zstd_cap = 0.01,
    )
    @test all(row -> abs(row.infit_zstd) <= 0.01, capped)
    @test all(row -> abs(row.outfit_zstd) <= 0.01, capped)

    sparse = facets_compatibility_stats(
        fit_result;
        draw_indices = [1, 2],
        min_n = data.n + 1,
    )
    @test all(row -> row.flag === :below_min_n, sparse)
    @test all(row -> isnan(row.infit) && isnan(row.outfit), sparse)

    rsm_design = getdesign(mfrm_spec(data; thresholds = :rating_scale))
    rsm_rows = facets_compatibility_stats(
        rsm_design,
        zeros(length(rsm_design.parameter_names)),
    )
    @test all(row -> row.threshold_regime === :rating_scale, rsm_rows)
    @test all(row -> row.rasch_model === :rsm, rsm_rows)

    @test_throws ArgumentError facets_compatibility_stats(
        fit_result;
        point_estimate = :posterior_median,
    )
    @test_throws ArgumentError facets_compatibility_stats(
        fit_result;
        weighting = :frequency,
    )
    @test_throws ArgumentError facets_report(
        fit_result;
        weighting = :frequency,
    )
    @test_throws ArgumentError facets_compatibility_stats(
        fit_result;
        zstd_cap = 0,
    )
    @test_throws ArgumentError facets_compatibility_stats(
        fit_result;
        variance_tolerance = 0,
    )
    @test_throws ArgumentError facets_compatibility_stats(
        design,
        plugin;
        by = :unknown,
    )
    @test_throws ArgumentError facets_compatibility_stats(design, plugin[1:end-1])

    generalized_prior = BayesianMGMFRM._SourceFixturePrior()
    generalized_args = (
        design,
        generalized_prior,
        zeros(1, n_parameters),
        [0.0],
        zeros(1, n_parameters),
        [0.0],
        zeros(1, data.n),
        [1],
        [1],
        [1.0],
        :advancedhmc,
        :nuts,
        0,
        0.1,
        NamedTuple[],
        NamedTuple(),
        NamedTuple(),
    )
    for generalized_fit in (GMFRMFit(generalized_args...),
            MGMFRMFit(generalized_args...))
        @test_throws ArgumentError facets_report(generalized_fit)
        @test_throws ArgumentError facets_compatibility_stats(generalized_fit)
    end

    posterior_rows = fit_stats(fit_result; draw_indices = [1, 2])
    @test all(row -> row.method === :posterior, posterior_rows)
end
