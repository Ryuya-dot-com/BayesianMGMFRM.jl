using Test
using BayesianMGMFRM

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
