function check_gmfrm_waic_influence_review_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_waic_influence_review.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_waic_influence_review"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_waic_influence_review_v1"
    @test Set(String(source) for source in protocol[:simulation_sources]) == Set([
        "scalar_gmfrm_interval_decision_grid_v1",
        "scalar_gmfrm_sparse_design_grid_v1",
    ])
    @test String(protocol[:review_kind]) == "local_pointwise_waic_influence_review"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Float64(protocol[:pointwise_threshold]) == 0.4
    @test String(protocol[:influence_action]) ==
        "remove_union_of_flagged_observations_within_scenario"
    @test Set(String(model) for model in protocol[:models]) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test String(protocol[:decision_rules][:public_exposure_decision]) == "keep_internal"
    @test Bool(protocol[:decision_rules][:high_variance_waic_review_recorded])
    @test Bool(protocol[:decision_rules][:require_all_samplers_passed])
    @test Bool(protocol[:decision_rules][:require_masked_comparison_finite])
    @test Bool(protocol[:decision_rules][:psis_loo_or_exact_loo_required_before_public_exposure])
    @test Int(thresholds[:n_full_crossed_scenarios]) == 3
    @test Int(thresholds[:n_sparse_scenarios]) == 3
    @test Int(thresholds[:n_models_per_scenario]) == 3
    @test Int(thresholds[:min_retained_observations_after_mask]) == 4
    @test Bool(thresholds[:require_same_observations_within_scenario])
    @test Bool(thresholds[:require_sampler_passed])
    @test Bool(thresholds[:require_finite_elpd])

    reviews = fixture[:scenario_reviews]
    @test length(reviews) ==
        Int(thresholds[:n_full_crossed_scenarios]) +
        Int(thresholds[:n_sparse_scenarios])
    @test count(review -> String(review[:scenario_group]) == "full_crossed",
        reviews) == 3
    @test count(review -> String(review[:scenario_group]) == "sparse_connected",
        reviews) == 3
    for review in reviews
        simulated = review[:simulated_data]
        n_observations = Int(simulated[:n_observations])
        @test sum(Int(row[:n]) for row in simulated[:score_counts]) == n_observations
        @test Set(Int(row[:score]) for row in simulated[:score_counts]) == Set([0, 1, 2])

        full_rows = review[:full_comparison_rows]
        masked_rows = review[:masked_comparison_rows]
        @test length(full_rows) == Int(thresholds[:n_models_per_scenario])
        @test length(masked_rows) == Int(thresholds[:n_models_per_scenario])
        @test [Int(row[:rank]) for row in full_rows] == [1, 2, 3]
        @test [Int(row[:rank]) for row in masked_rows] == [1, 2, 3]
        @test Set(String(row[:model]) for row in full_rows) == Set([
            "gmfrm_internal_candidate",
            "mfrm_partial_credit",
            "mfrm_rating_scale",
        ])
        @test all(row -> Bool(row[:sampler_summary][:internal_passed]), full_rows)
        @test all(row -> isfinite(Float64(row[:elpd_waic])) &&
            isfinite(Float64(row[:waic])), full_rows)
        @test all(row -> isfinite(Float64(row[:elpd_waic])) &&
            isfinite(Float64(row[:waic])), masked_rows)
        @test sum(Float64(row[:relative_weight]) for row in full_rows) ≈ 1.0
        @test sum(Float64(row[:relative_weight]) for row in masked_rows) ≈ 1.0

        flagged_rows = review[:flagged_observation_rows]
        flagged_union = review[:flagged_observation_union]
        @test !isempty(flagged_rows)
        @test !isempty(flagged_union)
        @test all(row -> Float64(row[:p_waic]) > Float64(protocol[:pointwise_threshold]),
            flagged_rows)
        @test all(row -> String(row[:flag]) == "high_loglik_variance",
            flagged_rows)

        influence = review[:influence_summary]
        @test Bool(influence[:passed])
        @test Int(influence[:n_observations]) == n_observations
        @test Int(influence[:n_flagged_model_observations]) == length(flagged_rows)
        @test Int(influence[:n_flagged_unique_observations]) == length(flagged_union)
        @test Int(influence[:n_retained_observations]) >=
            Int(thresholds[:min_retained_observations_after_mask])
        @test Float64(influence[:max_p_waic]) >=
            Float64(protocol[:pointwise_threshold])
        @test Bool(influence[:all_samplers_passed])
        @test Bool(influence[:all_masked_comparisons_finite])
        @test String(influence[:selected_decision]) == "keep_internal"
    end

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) == "keep_internal"
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test String(decision[:public_exposure_support]) ==
        "insufficient_for_public_experimental_fit"
    @test String(decision[:interpretation]) ==
        "pointwise_waic_influence_review_recorded_but_high_variance_persists"
    @test String(decision[:required_followup]) == "psis_loo_or_exact_loo_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenario_reviews]) == length(reviews)
    @test Int(summary[:n_full_crossed_scenarios]) == 3
    @test Int(summary[:n_sparse_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == length(reviews)
    @test Int(summary[:n_models]) == 3 * length(reviews)
    @test Int(summary[:n_flagged_model_observations]) > 0
    @test Float64(summary[:max_p_waic]) > Float64(protocol[:pointwise_threshold])
    @test Int(summary[:min_retained_observations]) >=
        Int(thresholds[:min_retained_observations_after_mask])
    @test Int(summary[:n_best_model_changes_after_flagged_removal]) >= 1
    @test Int(summary[:n_gmfrm_rank_changes_after_flagged_removal]) >= 1
    @test Bool(summary[:all_samplers_passed])
    @test Bool(summary[:all_masked_comparisons_finite])
    @test Bool(summary[:any_high_variance_waic])
    @test Int(summary[:keep_internal_decision_count]) == length(reviews)
    @test String(summary[:decision_stability]) == "stable_keep_internal"
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["high_variance_waic_requires_psis_loo_followup"])
    @test String(summary[:recommendation]) == "keep_internal_until_psis_loo_followup"
    @test String(summary[:next_gate]) == "scalar_gmfrm_psis_loo_review"
end

function check_gmfrm_psis_loo_review_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_psis_loo_review.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_psis_loo_review"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_psis_loo_review_v1"
    @test Set(String(source) for source in protocol[:simulation_sources]) == Set([
        "scalar_gmfrm_interval_decision_grid_v1",
        "scalar_gmfrm_sparse_design_grid_v1",
        "scalar_gmfrm_waic_influence_review_v1",
    ])
    @test String(protocol[:review_kind]) ==
        "local_raw_importance_loo_pareto_k_review"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:psis_smoothing_enabled]) == false
    @test String(protocol[:loo_method]) == "raw_importance_sampling"
    @test String(protocol[:pareto_k_estimator]) == "hill_log_tail"
    @test Float64(protocol[:pareto_k_threshold]) == 0.7
    @test Float64(protocol[:tail_fraction]) == 0.2
    @test Int(protocol[:min_tail_draws]) == 5
    @test Set(String(model) for model in protocol[:models]) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test String(protocol[:decision_rules][:public_exposure_decision]) ==
        "keep_internal"
    @test Bool(protocol[:decision_rules][:raw_importance_loo_review_recorded])
    @test Bool(protocol[:decision_rules][:require_all_samplers_passed])
    @test Bool(protocol[:decision_rules][:require_finite_loo_comparison])
    @test Bool(protocol[:decision_rules][:high_pareto_k_blocks_public_exposure])
    @test Bool(protocol[:decision_rules][:exact_loo_or_kfold_required_before_public_exposure])
    @test Int(thresholds[:n_full_crossed_scenarios]) == 3
    @test Int(thresholds[:n_sparse_scenarios]) == 3
    @test Int(thresholds[:n_models_per_scenario]) == 3
    @test Bool(thresholds[:require_same_observations_within_scenario])
    @test Bool(thresholds[:require_sampler_passed])
    @test Bool(thresholds[:require_finite_elpd])

    reviews = fixture[:scenario_reviews]
    @test length(reviews) ==
        Int(thresholds[:n_full_crossed_scenarios]) +
        Int(thresholds[:n_sparse_scenarios])
    @test count(review -> String(review[:scenario_group]) == "full_crossed",
        reviews) == 3
    @test count(review -> String(review[:scenario_group]) == "sparse_connected",
        reviews) == 3
    for review in reviews
        simulated = review[:simulated_data]
        n_observations = Int(simulated[:n_observations])
        @test sum(Int(row[:n]) for row in simulated[:score_counts]) == n_observations
        @test Set(Int(row[:score]) for row in simulated[:score_counts]) == Set([0, 1, 2])

        waic_rows = review[:waic_comparison_rows]
        loo_rows = review[:loo_comparison_rows]
        @test length(waic_rows) == Int(thresholds[:n_models_per_scenario])
        @test length(loo_rows) == Int(thresholds[:n_models_per_scenario])
        @test [Int(row[:rank]) for row in waic_rows] == [1, 2, 3]
        @test [Int(row[:rank]) for row in loo_rows] == [1, 2, 3]
        @test Set(String(row[:model]) for row in loo_rows) == Set([
            "gmfrm_internal_candidate",
            "mfrm_partial_credit",
            "mfrm_rating_scale",
        ])
        @test all(row -> String(row[:criterion]) == "loo", loo_rows)
        @test all(row -> String(row[:method]) == "raw_importance_sampling",
            loo_rows)
        @test all(row -> Bool(row[:psis_smoothing]) == false, loo_rows)
        @test all(row -> Bool(row[:sampler_summary][:internal_passed]),
            loo_rows)
        @test all(row -> isfinite(Float64(row[:elpd_loo])) &&
            isfinite(Float64(row[:looic])), loo_rows)
        @test all(row -> Float64(row[:max_pareto_k]) >= 0, loo_rows)
        @test all(row -> Float64(row[:min_effective_sample_size]) >= 1,
            loo_rows)
        @test sum(Float64(row[:relative_weight]) for row in loo_rows) ≈ 1.0

        high_pareto_rows = review[:high_pareto_observation_rows]
        high_pareto_union = review[:high_pareto_observation_union]
        @test !isempty(high_pareto_rows)
        @test !isempty(high_pareto_union)
        @test all(row -> Float64(row[:pareto_k]) >
            Float64(protocol[:pareto_k_threshold]), high_pareto_rows)
        @test all(row -> String(row[:flag]) == "high_pareto_k",
            high_pareto_rows)

        summary = review[:loo_summary]
        @test Bool(summary[:passed])
        @test Int(summary[:n_observations]) == n_observations
        @test Int(summary[:n_high_pareto_model_observations]) ==
            length(high_pareto_rows)
        @test Int(summary[:n_high_pareto_unique_observations]) ==
            length(high_pareto_union)
        @test Float64(summary[:max_pareto_k]) >
            Float64(protocol[:pareto_k_threshold])
        @test Bool(summary[:all_samplers_passed])
        @test Bool(summary[:all_loo_comparisons_finite])
        @test Bool(summary[:any_high_pareto_k])
        @test String(summary[:selected_decision]) == "keep_internal"
    end

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) == "keep_internal"
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test String(decision[:public_exposure_support]) ==
        "insufficient_for_public_experimental_fit"
    @test String(decision[:interpretation]) ==
        "raw_importance_loo_review_recorded_but_not_public_sufficient"
    @test String(decision[:required_followup]) == "exact_loo_or_kfold_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenario_reviews]) == length(reviews)
    @test Int(summary[:n_full_crossed_scenarios]) == 3
    @test Int(summary[:n_sparse_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == length(reviews)
    @test Int(summary[:n_models]) == 3 * length(reviews)
    @test Int(summary[:n_high_pareto_model_observations]) > 0
    @test Float64(summary[:max_pareto_k]) > Float64(protocol[:pareto_k_threshold])
    @test Int(summary[:n_best_model_changes_from_waic_to_loo]) >= 1
    @test Int(summary[:n_gmfrm_rank_changes_from_waic_to_loo]) >= 1
    @test Bool(summary[:all_samplers_passed])
    @test Bool(summary[:all_loo_comparisons_finite])
    @test Bool(summary[:any_high_pareto_k])
    @test Bool(summary[:psis_smoothing_enabled]) == false
    @test Int(summary[:keep_internal_decision_count]) == length(reviews)
    @test String(summary[:decision_stability]) == "stable_keep_internal"
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["high_pareto_k_requires_exact_loo_or_kfold_followup"])
    @test String(summary[:recommendation]) ==
        "keep_internal_until_exact_loo_or_kfold_followup"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_exact_loo_or_kfold_review"
end

function check_gmfrm_exact_loo_or_kfold_review_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_exact_loo_or_kfold_review.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_exact_loo_or_kfold_review"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_exact_loo_or_kfold_review_v1"
    @test Set(String(source) for source in protocol[:simulation_sources]) == Set([
        "scalar_gmfrm_interval_decision_grid_v1",
        "scalar_gmfrm_sparse_design_grid_v1",
        "scalar_gmfrm_psis_loo_review_v1",
    ])
    @test String(protocol[:review_kind]) == "local_refit_kfold_elpd_review"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:exact_loo_enabled]) == false
    @test Bool(protocol[:kfold_enabled])
    @test Int(protocol[:k_folds]) == 3
    @test Int(protocol[:fold_seed]) == 1
    @test String(protocol[:prediction_target]) ==
        "heldout_observation_log_score"
    @test Set(String(model) for model in protocol[:models]) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test Bool(protocol[:decision_rules][:exact_loo_or_kfold_review_recorded])
    @test Bool(protocol[:decision_rules][:require_all_training_designs_parameter_order_matched])
    @test Bool(protocol[:decision_rules][:require_all_samplers_passed])
    @test Bool(protocol[:decision_rules][:require_finite_kfold_comparison])
    @test Bool(protocol[:decision_rules][:require_all_observations_held_out_once])
    @test Bool(protocol[:decision_rules][:guarded_fit_api_dry_run_required_before_public_exposure])
    @test Int(thresholds[:n_full_crossed_scenarios]) == 3
    @test Int(thresholds[:n_sparse_scenarios]) == 3
    @test Int(thresholds[:n_models_per_scenario]) == 3
    @test Int(thresholds[:n_folds]) == 3
    @test Bool(thresholds[:require_same_observations_within_scenario])
    @test Bool(thresholds[:require_sampler_passed])
    @test Bool(thresholds[:require_finite_elpd])
    @test Bool(thresholds[:require_parameter_order_match])

    reviews = fixture[:scenario_reviews]
    @test length(reviews) ==
        Int(thresholds[:n_full_crossed_scenarios]) +
        Int(thresholds[:n_sparse_scenarios])
    @test count(review -> String(review[:scenario_group]) == "full_crossed",
        reviews) == 3
    @test count(review -> String(review[:scenario_group]) == "sparse_connected",
        reviews) == 3
    for review in reviews
        simulated = review[:simulated_data]
        n_observations = Int(simulated[:n_observations])
        @test sum(Int(row[:n]) for row in simulated[:score_counts]) ==
            n_observations
        @test Set(Int(row[:score]) for row in simulated[:score_counts]) ==
            Set([0, 1, 2])

        folds = review[:folds]
        @test length(folds) == Int(protocol[:k_folds])
        heldout = Int[]
        for fold in folds
            append!(heldout, Int.(fold[:heldout_observations]))
            @test Int(fold[:n_heldout_observations]) ==
                length(fold[:heldout_observations])
            @test length(fold[:heldout_rows]) ==
                Int(fold[:n_heldout_observations])
        end
        @test sort(heldout) == collect(1:n_observations)

        fold_rows = review[:fold_model_rows]
        @test length(fold_rows) ==
            Int(protocol[:k_folds]) * Int(thresholds[:n_models_per_scenario])
        @test all(row -> String(row[:criterion]) == "kfold", fold_rows)
        @test all(row -> Bool(row[:parameter_order_matched]), fold_rows)
        @test all(row -> Bool(row[:sampler_summary][:internal_passed]),
            fold_rows)
        @test all(row -> isfinite(Float64(row[:elpd_heldout])) &&
            isfinite(Float64(row[:kfoldic_heldout])), fold_rows)
        @test all(row -> Int(row[:n_train_observations]) +
            Int(row[:n_heldout_observations]) == n_observations, fold_rows)

        rows = review[:kfold_comparison_rows]
        @test length(rows) == Int(thresholds[:n_models_per_scenario])
        @test [Int(row[:rank]) for row in rows] == [1, 2, 3]
        @test Set(String(row[:model]) for row in rows) == Set([
            "gmfrm_internal_candidate",
            "mfrm_partial_credit",
            "mfrm_rating_scale",
        ])
        @test all(row -> String(row[:criterion]) == "kfold", rows)
        @test all(row -> String(row[:prediction_target]) ==
            "heldout_observation_log_score", rows)
        @test all(row -> Bool(row[:all_parameter_orders_matched]), rows)
        @test all(row -> Bool(row[:all_samplers_passed]), rows)
        @test all(row -> isfinite(Float64(row[:elpd_kfold])) &&
            isfinite(Float64(row[:kfoldic])), rows)
        @test sum(Float64(row[:relative_weight]) for row in rows) ≈ 1.0

        summary = review[:kfold_summary]
        @test Bool(summary[:passed])
        @test Int(summary[:n_observations]) == n_observations
        @test Int(summary[:n_folds]) == Int(protocol[:k_folds])
        @test Bool(summary[:all_observations_held_out_once])
        @test Bool(summary[:all_parameter_orders_matched])
        @test Bool(summary[:all_samplers_passed])
        @test Bool(summary[:all_kfold_comparisons_finite])
        @test String(summary[:selected_decision]) == "keep_internal"
    end

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) == "keep_internal"
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test String(decision[:public_exposure_support]) ==
        "insufficient_for_public_experimental_fit"
    @test String(decision[:interpretation]) ==
        "kfold_refit_review_recorded_and_exact_loo_gate_satisfied"
    @test String(decision[:required_followup]) == "guarded_fit_api_dry_run"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenario_reviews]) == length(reviews)
    @test Int(summary[:n_full_crossed_scenarios]) == 3
    @test Int(summary[:n_sparse_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == length(reviews)
    @test Int(summary[:n_models]) == 3 * length(reviews)
    @test Int(summary[:n_fold_model_records]) ==
        3 * Int(protocol[:k_folds]) * length(reviews)
    @test Int(summary[:n_folds]) == Int(protocol[:k_folds])
    @test Bool(summary[:all_observations_held_out_once])
    @test Bool(summary[:all_parameter_orders_matched])
    @test Bool(summary[:all_samplers_passed])
    @test Bool(summary[:all_kfold_comparisons_finite])
    @test Int(summary[:min_train_observations]) >= 12
    @test Int(summary[:n_gmfrm_best_model_scenarios]) >= 1
    @test Float64(summary[:max_gmfrm_kfoldic_difference]) >= 0
    @test 0 <= Float64(summary[:min_gmfrm_relative_weight]) <= 1
    @test Int(summary[:keep_internal_decision_count]) == length(reviews)
    @test String(summary[:decision_stability]) == "stable_keep_internal"
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["guarded_fit_api_dry_run_missing"])
    @test String(summary[:recommendation]) ==
        "keep_internal_until_guarded_fit_api_dry_run"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_guarded_fit_api_dry_run"
end
