using Test
using BayesianMGMFRM

@testset "Predictive recovery from normalized log probabilities" begin
    score = mgmfrm_predictive_recovery_score
    truth = [0.75 0.25 0.0; 0.2 0.3 0.5]
    predicted = [0.6 0.4 0.0; 0.3 0.2 0.5]
    draws = repeat(reshape(predicted, 1, 2, 3), 2, 1, 1)
    draws[2, :, :] = [0.4 0.6 0.0; 0.1 0.1 0.8]
    for input in (predicted, draws)
        ordinary = score(input, truth; category_levels = [-2, 0, 3])
        logged = score(log.(input), log.(truth);
            category_levels = [-2, 0, 3], log_probabilities = true)
        @test ordinary.schema == logged.schema
        @test ordinary.status === logged.status === :scored
        @test !logged.thresholds_applied && !logged.validation_claim_allowed
        @test all(isapprox(getproperty(ordinary.summary, field), getproperty(logged.summary, field);
            atol = 1e-14) for field in propertynames(ordinary.summary))
        @test all(isapprox(getproperty(a, field), getproperty(b, field); atol = 1e-14)
            for (a, b) in zip(ordinary.rows, logged.rows) for field in propertynames(a))
    end
    @test score(log.(truth), log.(truth); log_probabilities = true).summary.mean_log_score_regret == 0.0

    # Zero-probability draws stay in the mixture denominator; an all-zero
    # category stays -Inf, not NaN, and only matters where truth has support.
    mixed = reshape([0.0, 0.25, 1.0, 0.75, 0.0, 0.0], 2, 1, 3)
    observed = [1.0 0.0 0.0]
    mixture = score(log.(mixed), log.(observed); log_probabilities = true)
    @test mixture.summary.n_prediction_draws == 2
    @test mixture.summary.mean_log_score_regret ≈ log(8)
    @test score(log.(mixed), log.([0.0 0.0 1.0]); log_probabilities = true).status === :nonfinite_log_score_regret
    @test score(log.([0.0 1.0]), log.([0.0 1.0]); log_probabilities = true).summary.mean_log_score_regret == 0.0

    log_truth, log_predicted = [-800.0 0.0], [-1e308 0.0]
    oracle = setprecision(256) do
        Float64(exp(BigFloat(-800)) * (BigFloat(-800) - BigFloat(-1e308)))
    end
    tiny = score(log_predicted, log_truth; log_probabilities = true)
    @test exp(-800.0) == 0.0
    @test isfinite(oracle) && oracle > 0
    @test tiny.summary.mean_log_score_regret > 0
    @test tiny.summary.mean_log_score_regret ≈ oracle rtol = 1e-12
    @test score(exp.(log_predicted), exp.(log_truth)).summary.mean_log_score_regret == 0.0
    @test score([-Inf 0.0], log_truth; log_probabilities = true).summary.mean_log_score_regret == Inf
    huge = score(repeat(log_predicted, 3, 1), repeat([0.0 -Inf], 3, 1);
        log_probabilities = true)
    @test huge.summary.finite_log_score_regret
    @test isfinite(huge.summary.mean_log_score_regret)
    @test huge.summary.mean_log_score_regret ≈ 1e308 rtol = 1e-12
    smallest = nextfloat(0.0)
    subnormal = score(repeat([-smallest log(smallest)], 2, 1),
        repeat([0.0 -Inf], 2, 1); log_probabilities = true)
    @test all(row.log_score_regret == smallest for row in subnormal.rows)
    @test subnormal.summary.mean_log_score_regret == smallest
    for log_p in ([0.0 -Inf; -Inf 0.0], [-Inf 0.0; 0.0 -Inf], [0.0 -Inf; 0.0 -Inf])
        @test score([-Inf 0.0; -Inf 0.0], log_p;
            log_probabilities = true).summary.mean_log_score_regret == Inf
    end

    for invalid in ([NaN 0.0], [Inf 0.0], [0.01 -Inf], [-Inf -Inf],
            log.([0.2 0.2]), [0.0 0.0])
        @test_throws ArgumentError score(invalid, log_truth; log_probabilities = true)
        @test_throws ArgumentError score(log_predicted, invalid; log_probabilities = true)
    end
    invalid_draws = reshape(log.([0.25, 0.75, 0.25, 0.75]), 2, 1, 2)
    @test_throws ArgumentError score(invalid_draws, log_truth; log_probabilities = true)
    @test_throws ArgumentError score(zeros(0, 1, 2), log_truth; log_probabilities = true)
    @test_throws ArgumentError score(zeros(0, 2), zeros(0, 2); log_probabilities = true)
    @test_throws ArgumentError score(zeros(1, 1), zeros(1, 1); log_probabilities = true)
    @test_throws ArgumentError score(log_predicted, log.(truth); log_probabilities = true)
    @test_throws ArgumentError score(log_predicted, log_truth; log_probabilities = true,
        probability_tolerance = NaN)
end

@testset "MGMFRM Stage-A predictive and decision scoring" begin
    truth = [0.75 0.25; 0.20 0.80]
    identical_draws = repeat(reshape(truth, 1, 2, 2), 3, 1, 1)
    exact = mgmfrm_predictive_recovery_score(
        identical_draws,
        truth;
        category_levels = [0, 2],
    )
    @test exact.status === :scored
    @test !exact.thresholds_applied
    @test !exact.validation_claim_allowed
    @test exact.summary.n_prediction_draws == 3
    @test exact.summary.mean_absolute_category_probability_error ≈ 0.0 atol = 1e-15
    @test exact.summary.root_mean_squared_expected_score_error ≈ 0.0 atol = 1e-15
    @test exact.summary.mean_log_score_regret ≈ 0.0 atol = 1e-15
    @test length(exact.rows) == 2

    predicted = [0.60 0.40; 0.30 0.70]
    shifted = mgmfrm_predictive_recovery_score(
        predicted,
        truth;
        category_levels = [0, 2],
    )
    @test shifted.summary.n_prediction_draws == 1
    @test shifted.summary.mean_absolute_category_probability_error ≈ 0.125
    @test shifted.summary.mean_absolute_expected_score_error ≈ 0.25
    @test shifted.summary.maximum_absolute_expected_score_error ≈ 0.30
    @test shifted.summary.mean_log_score_regret > 0

    zero_support = mgmfrm_predictive_recovery_score(
        [0.0 1.0; 0.2 0.8],
        truth,
    )
    @test zero_support.status === :nonfinite_log_score_regret
    @test !zero_support.summary.finite_log_score_regret
    @test isinf(zero_support.summary.mean_log_score_regret)

    # Positive subnormal support has finite KL even when truth / predicted
    # overflows. Compare with an independent high-precision calculation.
    tiny_truth = [0.5 0.5]
    tiny_prediction = [nextfloat(0.0) 1.0]
    tiny = mgmfrm_predictive_recovery_score(tiny_prediction, tiny_truth)
    oracle = setprecision(256) do
        Float64(sum(BigFloat(tiny_truth[i]) *
            log(BigFloat(tiny_truth[i]) / BigFloat(tiny_prediction[i]))
            for i in eachindex(tiny_truth)))
    end
    @test isfinite(oracle)
    @test tiny.status === :scored
    @test tiny.summary.finite_log_score_regret
    @test tiny.summary.mean_log_score_regret ≈ oracle
    for (p, q, expected) in (([0.0 1.0], [0.0 1.0], 0.0),
            ([0.0 1.0], [0.5 0.5], log(2.0)))
        @test mgmfrm_predictive_recovery_score(q, p).summary.mean_log_score_regret ≈ expected
    end
    for invalid in ([NaN 1.0], [-0.1 1.1], [0.2 0.2], [Inf 0.0])
        @test_throws ArgumentError mgmfrm_predictive_recovery_score(invalid, tiny_truth)
        @test_throws ArgumentError mgmfrm_predictive_recovery_score(tiny_prediction, invalid)
    end
    @test_throws ArgumentError mgmfrm_predictive_recovery_score(zeros(0, 1, 2), tiny_truth)
    # A valid average cannot excuse invalid individual draw rows.
    @test_throws ArgumentError mgmfrm_predictive_recovery_score(
        reshape([-0.1, 1.1, 1.1, -0.1], 2, 1, 2), tiny_truth)

    @test_throws ArgumentError mgmfrm_predictive_recovery_score(
        [0.7 0.4; 0.2 0.8],
        truth,
    )
    @test_throws ArgumentError mgmfrm_predictive_recovery_score(
        predicted[:, 1:1],
        truth[:, 1:1],
    )
    @test_throws ArgumentError mgmfrm_predictive_recovery_score(
        predicted,
        truth;
        category_levels = [0],
    )

    reference = [1.0, 2.0, 3.0]
    candidates = [
        1.0 2.0 3.0
        3.0 2.0 1.0
        1.0 1.0 4.0
    ]
    decisions = mgmfrm_decision_stability_score(
        reference,
        candidates;
        cutpoints = (1.5,),
        condition_labels = (:exact, :reversed, :partial_tie),
        unit_labels = (:a, :b, :c),
    )
    @test decisions.status === :scored_descriptive
    @test !decisions.thresholds_applied
    @test !decisions.validation_claim_allowed
    @test decisions.summary.classification_evaluated
    @test decisions.rows[1].pairwise_order_disagreement_rate == 0.0
    @test decisions.rows[1].classification_flip_rate == 0.0
    @test decisions.rows[2].pairwise_order_disagreement_rate == 1.0
    @test decisions.rows[2].classification_flip_rate ≈ 2 / 3
    @test decisions.rows[3].pairwise_order_disagreement_rate ≈ 1 / 3
    @test decisions.summary.maximum_pairwise_order_disagreement_rate == 1.0
    @test decisions.summary.maximum_classification_flip_rate ≈ 2 / 3
    @test decisions.condition_labels == (:exact, :reversed, :partial_tie)
    @test decisions.unit_labels == (:a, :b, :c)

    unclassified = mgmfrm_decision_stability_score(
        reference,
        candidates[1:1, :],
    )
    @test !unclassified.summary.classification_evaluated
    @test ismissing(unclassified.rows[1].classification_flip_rate)
    @test ismissing(unclassified.summary.maximum_classification_flip_rate)

    tied_reference = mgmfrm_decision_stability_score(
        [1.0, 1.0],
        [1.0 2.0],
    )
    @test tied_reference.rows[1].n_comparable_order_pairs == 0
    @test ismissing(tied_reference.rows[1].pairwise_order_disagreement_rate)

    @test_throws ArgumentError mgmfrm_decision_stability_score(
        reference,
        candidates;
        cutpoints = (2.0, 1.0),
    )
    @test_throws ArgumentError mgmfrm_decision_stability_score(
        reference,
        candidates;
        condition_labels = (:too_short,),
    )
    @test_throws ArgumentError mgmfrm_decision_stability_score(
        reference,
        candidates[:, 1:2],
    )
end
