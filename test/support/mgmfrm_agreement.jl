function check_mgmfrm_tam_direct_agreement_policy_refinement_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy_refinement.v1"
    @test String(fixture[:family]) == "mfrm"
    @test String(fixture[:scope]) ==
        "tam_direct_agreement_multiaxial_policy_refinement"
    @test String(fixture[:status]) ==
        "frozen_policy_refined_without_primary_gate_change"
    @test String(fixture[:decision]) ==
        "apply_adjudication_overlay_then_run_frozen_direct_multireplication"
    @test Bool(fixture[:local_only])
    @test String(fixture[:external_software]) == "tam"
    @test String(fixture[:refinement_kind]) ==
        "interpretation_adjudication_and_reporting_overlay"
    @test Bool(fixture[:frozen_primary_thresholds_modified]) == false
    @test Bool(fixture[:frozen_primary_design_modified]) == false
    @test Bool(fixture[:direct_multireplication_execution_completed]) == false
    @test Bool(fixture[:external_software_validation_completed]) == false
    @test Bool(fixture[:public_claim_release_allowed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_tam_direct_agreement_policy_refinement_v1"
    @test String(protocol[:generator]) ==
        "scripts/generate_mgmfrm_tam_direct_agreement_policy_refinement.jl"
    @test String(protocol[:generator_source_sha256]) == file_sha256(joinpath(
        root, String(protocol[:generator])))
    @test String(protocol[:refinement_freeze_order]) ==
        "after_frozen_primary_policy_before_direct_multireplication_execution"
    @test String(protocol[:primary_policy_role]) ==
        "immutable_confirmatory_decision_rule"
    @test String(protocol[:refinement_role]) ==
        "prospective_interpretation_and_adjudication_overlay"
    @test String(protocol[:retrospective_evidence_role]) ==
        "context_only_no_threshold_recalibration"

    sources = fixture[:source_artifacts]
    expected_sources = Dict(
        :frozen_policy =>
            "test/fixtures/mgmfrm_tam_direct_agreement_policy.json",
        :baseline => "test/fixtures/mgmfrm_tam_overlap_baseline.json",
        :direct_pilot =>
            "test/fixtures/mgmfrm_tam_direct_estimate_pilot.json",
        :recovery_policy =>
            "test/fixtures/mgmfrm_tam_comparison_policy_review.json",
        :tam_multireplication =>
            "test/fixtures/mgmfrm_tam_multireplication_comparison.json",
    )
    for (field, path) in expected_sources
        @test String(sources[field]) == path
        @test String(sources[Symbol(String(field) * "_sha256")]) ==
            file_sha256(joinpath(root, path))
    end
    @test occursin(r"^[0-9a-f]{64}$",
        String(fixture[:frozen_primary_gate_fingerprint_sha256]))
    @test occursin(r"^[0-9a-f]{64}$",
        String(fixture[:direct_threshold_table_sha256]))
    @test occursin(r"^[0-9a-f]{64}$",
        String(fixture[:sampler_threshold_table_sha256]))

    freeze = fixture[:freeze_provenance]
    @test String(freeze[:external_registration_status]) == "not_registered"
    @test String(freeze[:cryptographic_timestamp_status]) == "not_recorded"
    @test Bool(freeze[:local_hash_evidence_only])
    @test Bool(freeze[:can_be_called_preregistered]) == false
    @test Bool(freeze[:can_be_called_locally_frozen_before_future_direct_runs])
    @test Bool(freeze[:independent_freeze_verification_pending])

    environment = fixture[:environment_contract]
    @test String(environment[:project_toml]) == "Project.toml"
    @test occursin(r"^[0-9a-f]{64}$",
        String(environment[:project_toml_sha256]))
    @test String(environment[:manifest_toml]) == "Manifest.toml"
    @test occursin(r"^[0-9a-f]{64}$",
        String(environment[:manifest_toml_sha256]))
    @test String(environment[:environment_hash_mismatch_disposition]) ==
        "record_and_classify_as_new_versioned_reproduction_run"
    @test Bool(environment[:os_blas_and_cpu_metadata_required_in_result])

    parent = JSON3.read(read(joinpath(root,
        String(sources[:frozen_policy])), String))
    snapshot = fixture[:frozen_primary_gate_snapshot]
    direct = snapshot[:direct_threshold_rows]
    @test length(direct) == 12
    @test Set((String(row[:block]), String(row[:metric]),
        String(row[:direction]), Float64(row[:threshold])) for row in direct) ==
        Set((String(row[:block]), String(row[:metric]),
            String(row[:direction]), Float64(row[:threshold]))
            for row in parent[:direct_threshold_rows])
    sampler = snapshot[:sampler_threshold_rows]
    @test length(sampler) == 6
    @test Set(String(row[:metric]) for row in sampler) ==
        Set(String(row[:metric]) for row in parent[:sampler_threshold_rows])
    @test Int.(snapshot[:person_counts]) == [40, 100]
    @test Int(snapshot[:replications_per_person_count]) == 5
    @test Int(snapshot[:primary_person_count]) == 100
    @test Float64(snapshot[:primary_block_pass_rate_threshold]) == 0.80
    @test Int(snapshot[:chains]) == 4
    @test Int(snapshot[:ndraws_per_chain]) == 400
    @test Int(snapshot[:warmup_per_chain]) == 400
    @test Float64(snapshot[:target_accept]) == 0.90
    @test Int(snapshot[:max_depth]) == 10

    design = fixture[:inherited_design_scope]
    @test Bool(design[:inherited_without_change])
    @test Int.(design[:person_counts]) == [40, 100]
    @test Int(design[:primary_person_count]) == 100
    @test Int(design[:n_items]) == 5
    @test Int(design[:n_raters]) == 4
    @test Int(design[:n_dimensions]) == 1
    @test Int.(design[:category_levels]) == [0, 1, 2, 3]
    @test Int(design[:n_categories]) == 4
    @test String(design[:assignment]) == "fully_crossed"
    @test String(design[:thresholds]) == "partial_credit"
    @test Float64(design[:item_discrimination]) == 1.0
    @test Float64(design[:rater_consistency]) == 1.0

    data_contract = fixture[:data_and_input_contract]
    @test String(data_contract[:generator]) ==
        "standalone_adjacent_category_softmax"
    @test Bool(data_contract[
        :package_probability_or_simulation_helper_used_for_generation]) == false
    @test Int(data_contract[:base_seed]) == 20260714
    @test Bool(data_contract[
        :seed_disjoint_from_direct_pilot_and_tam_only_multireplication])
    @test Bool(data_contract[:adaptive_seed_search_or_redraw_allowed]) == false
    @test Bool(data_contract[:missing_category_regeneration_allowed]) == false
    @test Int(data_contract[:n_items]) == 5
    @test Int(data_contract[:n_raters]) == 4
    @test Int.(data_contract[:category_levels]) == [0, 1, 2, 3]
    @test String(data_contract[:canonical_row_order]) ==
        "person_then_rater_then_item"
    @test Bool(data_contract[:package_and_tam_must_use_identical_csv_sha256])
    seed_rows = data_contract[:seed_registry_rows]
    @test length(seed_rows) == 10
    all_seeds = Int[]
    for row in seed_rows
        append!(all_seeds, [Int(row[:ability_seed]), Int(row[:response_seed]),
            Int(row[:package_fit_seed])])
    end
    @test length(unique(all_seeds)) == 30
    @test 20260713 ∉ all_seeds

    package_fit = fixture[:package_fit_contract]
    @test String(package_fit[:backend]) == "advancedhmc"
    @test String(package_fit[:sampler]) == "nuts"
    @test Int(package_fit[:chains]) == 4
    @test Int(package_fit[:warmup_per_chain]) == 400
    @test Int(package_fit[:retained_draws_per_chain]) == 400
    @test Float64(package_fit[:step_size]) == 0.05
    @test Float64(package_fit[:target_accept]) == 0.90
    @test Float64(package_fit[:max_energy_error]) == 1000.0
    @test Float64(package_fit[:init_jitter]) == 0.05
    @test Float64(package_fit[:prior][:person_sd]) == 1.5
    @test Bool(package_fit[:post_result_tuning_change_allowed]) == false

    tam_fit = fixture[:tam_fit_contract]
    @test String(tam_fit[:r_command]) == "TAM_tam_mml_mfr"
    @test String(tam_fit[:formulaA]) == "~ item + rater + item:step"
    @test String(tam_fit[:constraint]) == "cases"
    @test Int(tam_fit[:control][:maxiter]) == 1000
    @test Float64(tam_fit[:control][:conv]) == 1.0e-4
    @test Float64(tam_fit[:control][:convD]) == 1.0e-3
    @test Float64(tam_fit[:control][:convM]) == 1.0e-4
    @test Bool(tam_fit[:delete_red_items])
    @test String(tam_fit[:tam_version]) == "4.3.25"
    @test Set(String.(tam_fit[:required_validity_checks])) == Set([
        "exit_code_zero",
        "finite_deviance",
        "positive_iteration_count",
        "iteration_limit_not_reached",
        "all_expected_parameters_present_once",
        "no_unexpected_parameters_after_adapter",
        "all_estimates_and_standard_errors_finite",
        "formula_and_constraint_audit_pass",
        "sum_zero_and_category_intercept_reconstruction_pass",
    ])

    archive = fixture[:artifact_archive_contract]
    @test Bool(archive[:raw_local_archive_required])
    @test Bool(archive[:per_attempt_command_environment_and_sha256_manifest_required])
    @test Bool(archive[:failed_and_retried_attempts_both_retained])
    @test Bool(archive[:independent_metric_recomputation_from_raw_outputs_required])

    estimands = fixture[:estimand_alignment_rows]
    @test length(estimands) == 7
    @test Set(String(row[:estimand]) for row in estimands
        if Bool(row[:included_in_primary_gate])) ==
        Set(["item_difficulty", "rater_severity", "item_step"])
    @test any(row -> String(row[:estimand]) == "person_ability" &&
        String(row[:alignment]) == "not_directly_aligned" &&
        Bool(row[:included_in_primary_gate]) == false, estimands)
    @test any(row -> String(row[:estimand]) == "uncertainty" &&
        String(row[:alignment]) == "not_identical_interval_frameworks",
        estimands)

    axes = fixture[:evidence_axis_rows]
    @test length(axes) == 9
    axis_by_name = Dict(Symbol(String(row[:axis])) => row for row in axes)
    @test String(axis_by_name[:protocol_and_parameterization_alignment][
        :current_status]) == "passed"
    @test String(axis_by_name[:direct_cross_software_numerical_agreement][
        :current_status]) ==
        "descriptive_pilot_pass_confirmatory_runs_pending"
    @test String(axis_by_name[:known_truth_recovery][:current_status]) ==
        "tam_primary_n250_pass_package_multirep_pending"
    @test String(axis_by_name[:model_family_coverage][:current_status]) ==
        "unit_discrimination_unidimensional_mfrm_overlap_only"
    @test String(axis_by_name[:software_diversity][:current_status]) ==
        "tam_only"

    metric_roles = fixture[:metric_role_rows]
    @test length(metric_roles) == 4
    @test all(row -> Bool(row[:independent_evidence_unit]) == false,
        metric_roles)
    @test any(row -> String(row[:metric]) ==
        "tam_inside_package_interval95_rate" &&
        occursin("not_an_equivalence_test", String(row[:limitation])),
        metric_roles)

    discreteness = fixture[:block_discreteness_rows]
    @test length(discreteness) == 3
    discrete_by_block = Dict(Symbol(String(row[:block])) => row
        for row in discreteness)
    @test Int(discrete_by_block[:item_difficulty][
        :minimum_interval_containment_count]) == 4
    @test Int(discrete_by_block[:rater_severity][
        :minimum_interval_containment_count]) == 4
    @test Int(discrete_by_block[:item_step][
        :minimum_interval_containment_count]) == 12
    @test Int(discrete_by_block[:rater_severity][
        :correlation_degrees_of_freedom]) == 2
    @test all(row -> Int(row[:minimum_replications_passing]) == 4,
        discreteness)

    precision = fixture[:replication_precision_rows]
    @test Int.(getindex.(precision, :successes)) == [4, 5]
    @test all(row -> Int(row[:trials]) == 5 &&
        Bool(row[:frozen_gate_passed]), precision)
    @test Float64(first(precision)[:wilson95_lower]) < 0.40
    @test Float64(last(precision)[:wilson95_lower]) < 0.60
    @test all(row -> String(row[:inferential_role]) ==
        "precision_context_not_primary_gate", precision)
    replication_design = fixture[:replication_design_interpretation]
    @test Bool(replication_design[:observed_pass_rates_are_discrete])
    @test Float64.(replication_design[:possible_pass_rates]) ==
        [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
    @test Int(replication_design[:minimum_successes]) == 4
    @test isapprox(Float64(replication_design[
        :probability_of_observing_at_least_four_of_five_if_true_rate_is_0_80]),
        0.73728; atol = 1e-12)
    @test Bool(replication_design[
        :can_establish_population_pass_probability_at_least_0_80]) == false

    margins = fixture[:retrospective_pilot_direct_margin_rows]
    @test length(margins) == 12
    @test all(row -> Bool(row[:pilot_passed]), margins)
    @test all(row -> Bool(row[:can_confirm_future_gate]) == false, margins)
    @test all(row -> String(row[:role]) ==
        "retrospective_descriptive_context_only", margins)

    triangle = fixture[:retrospective_pilot_triangle_rows]
    @test length(triangle) == 3
    item_step = only(row for row in triangle
        if String(row[:block]) == "item_step")
    @test Float64(item_step[:package_vs_tam_pearson]) > 0.99
    @test Float64(item_step[:package_vs_truth_pearson]) < 0.70
    @test Float64(item_step[:tam_vs_truth_pearson]) < 0.72
    @test Float64(item_step[:tam_vs_truth_mean_abs_difference]) > 0.27
    @test Bool(item_step[:package_truth_recovery_profile_passed]) == false
    @test Bool(item_step[:tam_truth_recovery_profile_passed]) == false
    @test Bool(item_step[
        :both_estimators_truth_recovery_profiles_passed]) == false
    @test String(item_step[:interpretation]) ==
        "direct_agreement_but_neither_estimator_has_descriptive_recovery_support"
    @test all(row -> Bool(row[:confirmatory]) == false, triangle)

    tam_context = fixture[:tam_known_truth_context_rows]
    @test length(tam_context) == 9
    @test all(row -> Bool(row[:direct_threshold_cross_application_allowed]) ==
        false, tam_context)
    @test only(Float64(row[:all_recovery_thresholds_pass_rate])
        for row in tam_context if Int(row[:n_persons]) == 40 &&
            String(row[:block]) == "item_step") == 0.6
    @test only(Float64(row[:all_recovery_thresholds_pass_rate])
        for row in tam_context if Int(row[:n_persons]) == 100 &&
            String(row[:block]) == "item_step") == 1.0

    qualifier = fixture[:secondary_recovery_qualifier]
    @test String(qualifier[:status]) ==
        "prospective_secondary_claim_qualifier_frozen"
    @test Int(qualifier[:primary_person_count]) == 100
    @test Int(qualifier[:replications]) == 5
    @test Int(qualifier[:minimum_replications_passing_per_block]) == 4
    @test Bool(qualifier[:all_blocks_required_for_qualifier])
    @test Bool(qualifier[:changes_frozen_primary_direct_gate]) == false
    @test Bool(qualifier[:cannot_rescue_primary_direct_failure])
    @test Bool(qualifier[:cannot_veto_primary_direct_pass])
    recovery_thresholds = qualifier[:threshold_rows]
    @test length(recovery_thresholds) == 9
    @test all(row -> String(row[:source_role]) ==
        "inherited_unchanged_from_frozen_tam_known_truth_policy",
        recovery_thresholds)
    @test all(row -> String(row[:primary_direct_gate_effect]) == "none",
        recovery_thresholds)

    retry = fixture[:retry_and_missingness_policy]
    @test Int(retry[:fixed_primary_denominator]) == 5
    @test String(retry[:sampler_gate_scope]) ==
        "all_ten_scheduled_package_fits"
    @test Bool(retry[:n40_and_n100_pooling_allowed]) == false
    @test String(retry[:n40_role]) ==
        "secondary_sample_size_stress_condition"
    @test String(retry[:n100_role]) == "primary_confirmatory_condition"
    @test String(retry[:undefined_or_nonfinite_primary_metric]) ==
        "automatic_replication_block_failure"
    @test String(retry[:interval_metric_denominator]) ==
        "all_expected_parameters_in_block"
    @test Bool(retry[:all_scheduled_replications_must_be_recorded])
    @test Bool(retry[:sampler_failure_counts_as_primary_gate_failure])
    @test Bool(retry[:sampler_failure_may_be_replaced]) == false
    @test Bool(retry[:agreement_metric_failure_may_be_replaced]) == false
    @test Bool(retry[:replacement_seed_allowed]) == false
    @test Bool(retry[:denominator_reduction_allowed]) == false
    @test Bool(retry[:post_result_threshold_or_tuning_change_allowed]) == false

    decisions = fixture[:decision_state_rows]
    @test length(decisions) == 6
    @test all(row -> Bool(row[:public_claim_release]) == false, decisions)
    @test Set(String(row[:state]) for row in decisions) == Set([
        "direct_pass_recovery_qualifier_pass",
        "direct_pass_recovery_qualifier_fail",
        "direct_fail_sampler_valid",
        "sampler_invalid",
        "execution_incomplete",
        "protocol_violation",
    ])

    failures = fixture[:failure_taxonomy_rows]
    @test length(failures) == 9
    @test Int.(getindex.(failures, :priority)) == collect(1:9)
    @test String(first(failures)[:failure]) ==
        "protocol_or_alignment_failure"
    @test any(row -> String(row[:failure]) == "threshold_fragile_pass" &&
        String(row[:disposition]) ==
            "primary_pass_retained_with_fragility_label", failures)
    @test any(row -> String(row[:failure]) ==
        "truth_triangulation_limitation" &&
        "agree_but_both_miss_truth" in String.(row[:examples]), failures)

    equivalence = fixture[:equivalence_advisory]
    @test Bool(equivalence[:primary_metric_is_equivalence_test]) == false
    rope = equivalence[:conditional_rope_analysis]
    @test String(rope[:status]) == "prospective_advisory_only"
    @test Float64(rope[:posterior_interval_probability]) == 0.90
    @test Float64(rope[:rope_half_width]) == 0.30
    @test Bool(rope[:changes_frozen_primary_gate]) == false
    @test Bool(equivalence[:full_estimator_equivalence_completed]) == false

    reports = fixture[:required_reporting_rows]
    @test length(reports) == 10
    @test any(row -> String(row[:report]) ==
        "package_vs_tam_package_vs_truth_and_tam_vs_truth_triangle" &&
        String(row[:role]) == "required_secondary_interpretation", reports)
    @test any(row -> String(row[:report]) ==
        "rank_normalized_rhat_bulk_tail_ess_and_ebfmi_when_available" &&
        occursin("no_change_to_frozen_gate", String(row[:role])), reports)

    scope = fixture[:model_scope_rows]
    @test any(row -> String(row[:component]) ==
        "uto_2021_loading_weighted_multidimensional_model" &&
        String(row[:status]) == "excluded_no_inference_from_tam_overlap",
        scope)
    @test any(row -> String(row[:component]) ==
        "multidimensional_fixed_q_mgmfrm" &&
        String(row[:status]) == "excluded", scope)
    @test any(row -> String(row[:component]) == "person_ability" &&
        String(row[:status]) == "shared_kernel_term_not_direct_estimand",
        scope)

    claims = fixture[:claim_wording_rows]
    @test length(claims) == 5
    @test count(row -> String(row[:claim]) == "prohibited", claims) == 3
    @test any(row -> occursin("uto_2021", String(row[:wording])), claims)

    @test Set(String.(fixture[:claim_limits])) == Set([
        "original_thresholds_and_design_remain_unchanged",
        "direct_agreement_is_not_known_truth_recovery",
        "five_replications_are_a_decision_rule_not_precise_rate_estimation",
        "small_item_and_rater_blocks_make_correlation_and_coverage_discrete",
        "interval_containment_is_not_equivalence_testing",
        "same_data_estimators_can_share_sampling_error",
        "classical_rhat_and_autocorrelation_ess_are_provisional",
        "no_facets_or_conquest_execution",
        "no_generalized_gmfrm_or_mgmfrm_external_validation",
        "no_uto_2021_validation_inference_from_tam_overlap",
        "no_external_construct_or_population_validity_claim",
        "no_public_claim_release",
    ])

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:frozen_primary_gate_unchanged])
    @test Bool(summary[:frozen_primary_thresholds_modified]) == false
    @test Bool(summary[:frozen_primary_design_modified]) == false
    @test Bool(summary[:seed_registry_complete_and_disjoint])
    @test Bool(summary[:structural_adapter_checks_passed])
    @test Bool(summary[:retrospective_direct_pilot_all_thresholds_passed])
    @test Bool(summary[:retrospective_pilot_full_recovery_support]) == false
    @test String(summary[:retrospective_pilot_classification]) ==
        "descriptive_agreement_without_full_recovery_support"
    @test Float64(summary[:tam_known_truth_n40_item_step_pass_rate]) == 0.6
    @test Float64(summary[:tam_known_truth_n100_item_step_pass_rate]) == 1.0
    @test Bool(summary[:tam_known_truth_n250_primary_gate_passed])
    @test Bool(summary[:secondary_recovery_qualifier_frozen])
    @test Bool(summary[:direct_multireplication_execution_completed]) == false
    @test Bool(summary[:external_software_validation_completed]) == false
    @test Bool(summary[:public_claim_release_allowed]) == false
    @test Int(summary[:n_evidence_axes]) == 9
    @test Int(summary[:n_estimand_alignment_rows]) == 7
    @test Int(summary[:n_metric_roles]) == 4
    @test Int(summary[:n_decision_states]) == 6
    @test Int(summary[:n_failure_taxonomy_rows]) == 9
    @test Int(summary[:n_required_reporting_rows]) == 10
    @test String(summary[:next_gate]) ==
        "run_predeclared_multireplication_package_vs_tam_direct_agreement_under_refined_adjudication"
end

function check_mgmfrm_literature_anchored_independent_review_packet_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_literature_anchored_independent_review_packet.v1"
    @test String(fixture[:family]) == "gmfrm_mgmfrm"
    @test String(fixture[:scope]) ==
        "literature_anchored_independent_review_packet"
    @test String(fixture[:status]) == "packet_frozen_review_not_completed"
    @test String(fixture[:decision]) ==
        "freeze_independent_review_packet_keep_public_claims_blocked"
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:external_software_validation_completed]) == false
    @test Bool(fixture[:independent_review_completed]) == false
    @test Bool(fixture[:public_claim_release_allowed]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_literature_anchored_independent_review_packet_v1"
    @test String(protocol[:review_kind]) ==
        "independent_scientific_and_reproducibility_review"
    @test String(protocol[:source_artifact]) ==
        "mgmfrm_literature_anchored_synthetic_benchmark"
    @test String(protocol[:source_artifact_path]) ==
        "test/fixtures/mgmfrm_literature_anchored_synthetic_benchmark.json"
    @test Bool(protocol[:separate_from_external_software_comparison])
    @test Bool(protocol[:signed_review_manifest_required])
    @test String(protocol[:generator]) ==
        "scripts/generate_mgmfrm_literature_anchored_independent_review_packet.jl"
    @test String(protocol[:generator_source_sha256]) == file_sha256(joinpath(
        root,
        String(protocol[:generator]),
    ))

    source = fixture[:source_benchmark]
    @test String(source[:path]) ==
        "test/fixtures/mgmfrm_literature_anchored_synthetic_benchmark.json"
    @test String(source[:expected_schema]) ==
        "bayesianmgmfrm.mgmfrm_literature_anchored_synthetic_benchmark.v1"
    @test Bool(source[:schema_matches])
    @test String(source[:sha256]) ==
        file_sha256(joinpath(root, String(source[:path])))
    @test String(source[:generator_source]) ==
        "scripts/generate_mgmfrm_literature_anchored_synthetic_benchmark.jl"
    @test Bool(source[:recorded_generator_source_sha256_matches])
    @test Bool(source[:package_simulate_responses_called]) == false
    @test Bool(source[:package_source_oracle_checked_before_write])
    @test Int(source[:n_reference_records]) == 4
    @test Int(source[:n_benchmark_specifications]) == 4
    @test Int(source[:n_datasets]) == 2
    @test Int(source[:n_materialized_observations]) == 1700
    @test Bool(source[:standalone_generator_oracle_agreement])
    @test Bool(source[:public_claim_release_allowed]) == false
    @test Bool(source[:independent_review_completed]) == false
    @test Bool(source[:tam_direct_pilot_thresholds_predeclared]) == false
    @test String(source[:tam_direct_agreement_policy_path]) ==
        "test/fixtures/mgmfrm_tam_direct_agreement_policy.json"
    @test String(source[:tam_direct_agreement_policy_schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy.v1"
    @test Bool(source[:tam_direct_agreement_policy_schema_matches])
    @test Bool(source[:tam_direct_agreement_thresholds_predeclared])
    @test Bool(source[:tam_direct_agreement_multireplication_completed]) ==
        false
    @test String(source[:tam_direct_agreement_policy_refinement_path]) ==
        "test/fixtures/mgmfrm_tam_direct_agreement_policy_refinement.json"
    @test String(source[:tam_direct_agreement_policy_refinement_schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy_refinement.v1"
    @test Bool(source[
        :tam_direct_agreement_policy_refinement_schema_matches])
    @test Bool(source[:tam_direct_frozen_primary_gate_unchanged])
    @test Bool(source[:tam_direct_secondary_recovery_qualifier_frozen])
    @test Bool(source[:tam_direct_refinement_execution_completed]) == false

    source_rows = source[:source_dataset_rows]
    @test length(source_rows) == 2
    @test any(row -> String(row[:dataset_id]) ==
        "uto_ueno_2020_scalar_recovery_smallest_cell_rep01" &&
        String(row[:ability_combination]) == "not_applicable", source_rows)
    @test any(row -> String(row[:dataset_id]) ==
        "uto_2021_fixed_q_recovery_smallest_cell_rep01" &&
        String(row[:ability_combination]) == "loading_weighted_sum" &&
        String(row[:q_matrix_sha256]) != "not_applicable", source_rows)
    @test all(row -> occursin(r"^[0-9a-f]{64}$",
        String(row[:observations_sha256])), source_rows)
    @test all(row -> occursin(r"^[0-9a-f]{64}$",
        String(row[:truth_sha256])), source_rows)
    @test all(row -> Float64(row[:max_abs_probability_error]) <= 1e-12,
        source_rows)

    required_inputs = fixture[:required_input_rows]
    @test length(required_inputs) == 11
    @test Set(String(row[:input]) for row in required_inputs) == Set([
        "frozen_benchmark_artifact",
        "generator_source",
        "reference_records",
        "dataset_checksums",
        "paper_exact_vs_package_adapted_labels",
        "claim_limit_ledger",
        "tam_comparison_policy_and_adapter_review",
        "tam_multireplication_comparison",
        "tam_direct_estimate_pilot",
        "tam_direct_agreement_policy",
        "tam_direct_agreement_policy_refinement",
    ])
    @test all(row -> Bool(row[:present]), required_inputs)
    @test all(row -> Bool(row[:reviewer_must_verify]), required_inputs)

    tasks = fixture[:review_task_rows]
    @test length(tasks) == 10
    @test all(row -> String(row[:reviewer_decision]) ==
        "pending_independent_review", tasks)
    @test all(row -> Bool(row[:reviewer_required]), tasks)
    @test all(row -> Bool(row[:completed]) == false, tasks)
    @test all(row -> Bool(row[:blocks_public_claim_release]), tasks)
    @test any(row -> String(row[:task]) ==
        "ability_combination_recorded_as_formula" &&
        String(row[:required_evidence]) ==
            "loading_weighted_sum_not_classification_claim", tasks)
    @test any(row -> String(row[:task]) == "external_software_bridge_scope" &&
        String(row[:required_evidence]) ==
            "tam_direct_policy_refined_multirep_package_fits_and_facets_conquest_pending", tasks)

    fields = fixture[:reviewer_manifest_field_rows]
    @test length(fields) == 12
    @test all(row -> Bool(row[:required]), fields)
    @test all(row -> Bool(row[:completed]) == false, fields)
    @test any(row -> String(row[:field]) == "reviewed_benchmark_sha256" &&
        String(row[:validation_rule]) ==
            "must_match_source_benchmark_sha256", fields)
    @test any(row -> String(row[:field]) == "per_claim_decision_table" &&
        String(row[:validation_rule]) ==
            "must_allow_block_or_request_revision_per_claim", fields)

    claim_rows = fixture[:claim_review_rows]
    @test length(claim_rows) == 6
    @test count(row -> Bool(row[:artifact_support]), claim_rows) == 2
    @test all(row -> Bool(row[:independent_review_required]), claim_rows)
    @test all(row -> String(row[:reviewer_decision]) ==
        "pending_independent_review", claim_rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, claim_rows)
    @test any(row -> String(row[:claim]) == "independent_review" &&
        String(row[:artifact_blocker]) ==
            "signed_independent_review_not_attached", claim_rows)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "independent_review_packet_frozen"
    @test Bool(decision[:packet_frozen])
    @test Bool(decision[:signed_review_manifest_attached]) == false
    @test Bool(decision[:public_claim_release_allowed]) == false
    @test String(decision[:required_followup]) ==
        "assign_independent_reviewer_and_attach_signed_review_manifest"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:packet_frozen])
    @test Bool(summary[:source_benchmark_schema_matches])
    @test Bool(summary[:generator_source_hash_matches])
    @test Bool(summary[:standalone_generator_oracle_agreement])
    @test Bool(summary[:independent_review_completed]) == false
    @test Bool(summary[:signed_review_manifest_attached]) == false
    @test Bool(summary[:external_software_validation_completed]) == false
    @test Bool(summary[:public_claim_release_allowed]) == false
    @test Int(summary[:n_required_inputs]) == 11
    @test Int(summary[:n_review_task_rows]) == 10
    @test Int(summary[:n_reviewer_manifest_fields]) == 12
    @test Int(summary[:n_claim_review_rows]) == 6
    @test Int(summary[:n_source_datasets]) == 2
    @test Int(summary[:n_materialized_observations]) == 1700
    @test Set(String.(summary[:remaining_public_blockers])) == Set([
        "independent_reviewer_not_assigned",
        "signed_review_manifest_not_attached",
        "per_claim_review_decisions_missing",
        "external_software_validation_not_completed",
        "parameter_recovery_refits_not_completed",
        "external_construct_validity_not_supplied",
    ])
    @test String(summary[:recommendation]) ==
        "send_packet_to_independent_reviewer_without_claim_release"
    @test String(summary[:next_gate]) ==
        "assign_independent_reviewer_and_attach_signed_review_manifest"
end

function check_mgmfrm_tam_direct_agreement_multireplication_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_direct_agreement_multireplication.v1"
    @test String(fixture[:family]) == "mfrm"
    @test String(fixture[:scope]) ==
        "tam_direct_package_vs_tam_multireplication_execution"
    @test String(fixture[:status]) ==
        "direct_multireplication_execution_recorded"
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:externally_preregistered]) == false
    @test String(fixture[:external_software]) == "tam"
    @test Bool(fixture[:tam_overlap_direct_evaluation_completed])
    @test Bool(fixture[:package_wide_validation_completed]) == false
    @test Bool(fixture[:external_software_validation_completed]) == false
    @test Bool(fixture[:public_claim_release_allowed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_tam_direct_agreement_multireplication_v1"
    @test String(protocol[:generator]) ==
        "scripts/generate_mgmfrm_tam_direct_agreement_multireplication.jl"
    @test String(protocol[:generator_source_sha256]) == file_sha256(joinpath(
        root, String(protocol[:generator])))
    for (path_key, hash_key) in (
            (:baseline_artifact, :baseline_artifact_sha256),
            (:frozen_policy_artifact, :frozen_policy_artifact_sha256),
            (:refinement_artifact, :refinement_artifact_sha256),
            (:recovery_policy_artifact, :recovery_policy_artifact_sha256))
        source_path = joinpath(root, String(protocol[path_key]))
        @test isfile(source_path)
        @test String(protocol[hash_key]) == file_sha256(source_path)
    end
    @test Bool(protocol[:inherited_thresholds_unchanged])
    @test Int.(protocol[:person_counts]) == [40, 100]
    @test Int(protocol[:replications_per_person_count]) == 5
    @test Int(protocol[:primary_person_count]) == 100
    @test String(protocol[:n40_role]) ==
        "secondary_sample_size_stress_condition"
    @test String(protocol[:n100_role]) == "primary_confirmatory_condition"
    @test String(protocol[:sampler_gate_scope]) ==
        "all_ten_scheduled_package_fits"
    @test String(protocol[:failed_fit_disposition]) ==
        "counts_as_failure_no_exclusion"
    @test Bool(protocol[:replacement_seed_allowed]) == false

    tested_scope = fixture[:tested_scope]
    @test String(tested_scope[:tested_family]) == "mfrm"
    @test Int(tested_scope[:dimensions]) == 1
    @test Float64(tested_scope[:item_discrimination_fixed]) == 1.0
    @test Float64(tested_scope[:rater_consistency_fixed]) == 1.0
    @test Bool(tested_scope[:q_matrix_used]) == false
    @test Bool(tested_scope[:uto_2021_model_evaluated]) == false
    @test Bool(tested_scope[:result_transfer_to_gmfrm_or_mgmfrm_allowed]) ==
        false
    @test Bool(tested_scope[:facets_or_conquest_executed]) == false
    @test Bool(tested_scope[:construct_or_population_validity_assessed]) ==
        false

    integrity = fixture[:policy_integrity]
    @test Bool(integrity[:frozen_policy_hash_matches_refinement])
    @test Bool(integrity[:baseline_hash_matches_refinement])
    @test Bool(integrity[:recovery_policy_hash_matches_refinement])
    @test Bool(integrity[:refinement_records_gate_unchanged])
    @test Bool(integrity[:pilot_excluded_from_confirmatory_denominator])
    @test Bool(integrity[:execution_refinement_snapshot_validated])
    @test Bool(integrity[:selected_job_input_lineage_validated])
    @test Bool(integrity[:selected_job_seed_lineage_validated])
    @test Bool(integrity[:selected_job_environment_lineage_validated])

    aggregation = fixture[:aggregation_provenance]
    @test String(aggregation[:mode]) ==
        "aggregate_only_from_selected_attempts"
    @test Bool(aggregation[:mcmc_executed]) == false
    @test Bool(aggregation[:fail_closed])
    @test String(aggregation[:generator]) ==
        "scripts/generate_mgmfrm_tam_direct_agreement_multireplication_aggregate.jl"
    @test String(aggregation[:generator_source_sha256]) == file_sha256(
        joinpath(root, String(aggregation[:generator])))
    @test String(aggregation[:wrapped_execution_generator]) ==
        String(protocol[:generator])
    @test String(aggregation[:wrapped_execution_generator_source_sha256]) ==
        String(protocol[:generator_source_sha256])
    @test Bool(aggregation[:protocol_generator_fields_preserved])
    execution_snapshot_path = joinpath(root,
        String(aggregation[:refinement_execution_snapshot]))
    @test isfile(execution_snapshot_path)
    @test Int(aggregation[:refinement_execution_snapshot_bytes]) ==
        filesize(execution_snapshot_path)
    @test String(aggregation[:refinement_execution_snapshot_sha256]) ==
        file_sha256(execution_snapshot_path) ==
        "03fe1a903d4fd218b5ab3e5ad51f5133ec1d8f274fafcea0bf8ac330876d8f4e"
    execution_snapshot = JSON3.read(read(execution_snapshot_path, String))
    @test String(aggregation[:expected_project_toml_sha256]) == String(
        execution_snapshot[:environment_contract][:project_toml_sha256])
    @test String(aggregation[:expected_manifest_toml_sha256]) == String(
        execution_snapshot[:environment_contract][:manifest_toml_sha256])
    @test Int(aggregation[:n_selected_jobs_expected]) == 10
    @test Int(aggregation[:n_selected_jobs_validated]) == 10
    @test Bool(aggregation[:all_selected_job_lineage_valid])
    selected_lineage = aggregation[:selected_job_lineage_rows]
    @test length(selected_lineage) == 10
    @test length(unique(String(row[:job_id]) for row in selected_lineage)) == 10
    @test all(row -> Bool(row[:passed]) &&
        String(row[:execution_generator_source_sha256]) ==
            String(protocol[:generator_source_sha256]) &&
        String(row[:refinement_snapshot_sha256]) ==
            String(aggregation[:refinement_execution_snapshot_sha256]) &&
        String(row[:truth_sha256]) == String(
            execution_snapshot[:data_and_input_contract][
                :fixed_truth_sha256]) &&
        String(row[:project_toml][:sha256]) ==
            String(aggregation[:expected_project_toml_sha256]) &&
        String(row[:manifest_toml][:sha256]) ==
            String(aggregation[:expected_manifest_toml_sha256]),
        selected_lineage)

    selected = fixture[:selected_attempt_rows]
    @test length(selected) == 10
    @test length(unique(String(row[:job_id]) for row in selected)) == 10
    @test all(row -> occursin(r"^[0-9a-f]{64}$",
        String(row[:pointer_sha256])) &&
        occursin(r"^[0-9a-f]{64}$", String(row[:result_sha256])), selected)

    replications = fixture[:replication_rows]
    @test length(replications) == 10
    @test Set(Int(row[:n_persons]) for row in replications) == Set([40, 100])
    @test count(row -> Int(row[:n_persons]) == 40, replications) == 5
    @test count(row -> Int(row[:n_persons]) == 100, replications) == 5
    @test all(row -> Bool(row[:execution_completed]), replications)
    @test all(row -> Bool(row[:engine_failure]) == false, replications)
    @test all(row -> Bool(row[:protocol_alignment_valid]), replications)
    @test all(row -> Bool(row[:tam_validity][:passed]), replications)
    @test all(row -> Bool(row[:package][:frozen_sampler_gate_passed]),
        replications)
    @test count(row -> !Bool(row[:package][
        :rank_ebfmi_advisory_passed]), replications) == 4
    @test Set(String(row[:job_id]) for row in replications
        if !Bool(row[:package][:rank_ebfmi_advisory_passed])) == Set([
        "n040_rep03", "n040_rep05", "n100_rep02", "n100_rep05"])
    @test all(row -> length(row[:block_result_rows]) == 3, replications)
    @test all(row -> all(block -> length(block[:direct_metric_rows]) == 4,
        row[:block_result_rows]), replications)

    scenario_rows = fixture[:scenario_block_summary_rows]
    @test length(scenario_rows) == 6
    @test Set(String(row[:block]) for row in scenario_rows) == Set([
        "item_difficulty", "rater_severity", "item_step"])
    @test all(row -> Int(row[:n_replications]) == 5, scenario_rows)
    @test all(row -> Int(row[:direct_n_passed]) in 0:5, scenario_rows)
    @test all(row -> Float64(row[:direct_pass_rate]) ==
        Int(row[:direct_n_passed]) / 5, scenario_rows)
    primary_rows = [row for row in scenario_rows
        if Bool(row[:primary_gate_row])]
    stress_rows = [row for row in scenario_rows
        if !Bool(row[:primary_gate_row])]
    @test length(primary_rows) == 3
    @test length(stress_rows) == 3
    @test all(row -> Int(row[:n_persons]) == 100, primary_rows)
    @test all(row -> Int(row[:n_persons]) == 40, stress_rows)
    computed_primary = all(row -> Int(row[:direct_n_passed]) >= 4,
        primary_rows)
    computed_package_recovery = all(row ->
        Int(row[:package_truth_n_passed]) >= 4, primary_rows)
    computed_tam_recovery = all(row ->
        Int(row[:tam_truth_n_passed]) >= 4, primary_rows)
    @test all(row -> Int(row[:direct_n_passed]) == 5, primary_rows)
    @test all(row -> Int(row[:package_truth_n_passed]) == 5, primary_rows)
    @test all(row -> Int(row[:tam_truth_n_passed]) == 5, primary_rows)
    stress_by_block = Dict(String(row[:block]) => row for row in stress_rows)
    @test Int(stress_by_block["item_difficulty"][
        :package_truth_n_passed]) == 4
    @test Int(stress_by_block["rater_severity"][
        :package_truth_n_passed]) == 5
    @test Int(stress_by_block["item_step"][:package_truth_n_passed]) == 3
    @test all(row -> Int(row[:package_truth_n_passed]) ==
        Int(row[:tam_truth_n_passed]), stress_rows)
    @test all(row -> Bool(row[:direct_primary_block_passed]) ==
        (Int(row[:direct_n_passed]) >= 4), primary_rows)

    outcome = fixture[:outcome]
    @test Bool(outcome[:primary_direct_gate_passed]) == computed_primary
    @test Bool(outcome[:package_recovery_qualifier_passed]) ==
        computed_package_recovery
    @test Bool(outcome[:tam_recovery_qualifier_passed]) ==
        computed_tam_recovery
    @test Bool(outcome[:both_estimators_recovery_qualifier_passed]) ==
        (computed_package_recovery && computed_tam_recovery)
    @test String(outcome[:primary_policy_decision]) ==
        (computed_primary ? "pass" : "fail")
    @test String(outcome[:primary_policy_decision]) == "pass"
    @test String(outcome[:scientific_interpretation]) ==
        "local_numerical_agreement_with_both_recovery_profiles"
    @test Set(String.(outcome[:prohibited_regardless_of_outcome])) == Set([
        "bayesianmgmfrm_validated_by_tam",
        "estimators_are_equivalent",
        "uto_2021_reproduced_or_externally_validated",
        "gmfrm_or_mgmfrm_validated",
        "construct_population_fairness_or_performance_claim",
    ])

    raw_manifest = fixture[:raw_archive_manifest]
    @test Bool(raw_manifest[:local_ignored_artifact])
    @test Int(raw_manifest[:n_files]) == length(raw_manifest[:file_rows])
    @test occursin(r"^[0-9a-f]{64}$",
        String(raw_manifest[:manifest_sha256]))
    @test all(row -> occursin(r"^[0-9a-f]{64}$",
        String(row[:sha256])) && Int(row[:bytes]) >= 0,
        raw_manifest[:file_rows])
    raw_manifest_payload = join([
        string(String(row[:path]), '|', Int(row[:bytes]), '|',
            String(row[:sha256])) for row in raw_manifest[:file_rows]
    ], "\n")
    @test String(raw_manifest[:manifest_sha256]) ==
        bytes2hex(sha256(raw_manifest_payload))

    failures = fixture[:failure_rows]
    @test length(failures) == 4
    @test all(row -> String(row[:failure]) ==
        "sampler_advisory_warning" &&
        String(row[:detail]) == "rank_or_ebfmi_advisory_false", failures)

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:execution_completed])
    @test Bool(summary[:all_protocol_alignment_valid])
    @test Bool(summary[:all_tam_executions_valid])
    @test Bool(summary[:all_package_sampler_gates_passed])
    @test Bool(summary[:primary_direct_gate_passed]) == computed_primary
    @test String(summary[:primary_policy_decision]) ==
        String(outcome[:primary_policy_decision])
    @test String(summary[:scientific_interpretation]) ==
        String(outcome[:scientific_interpretation])
    @test Int(summary[:n_selected_jobs]) == 10
    @test Int(summary[:n_primary_block_rows]) == 3
    @test Int(summary[:n_primary_block_rows_passed]) ==
        count(row -> Bool(row[:direct_primary_block_passed]), primary_rows)
    @test Int(summary[:n_failure_rows]) == length(fixture[:failure_rows])
    @test Bool(summary[:aggregate_only])
    @test Bool(summary[:mcmc_executed]) == false
    @test Bool(summary[:selected_job_lineage_validation_passed])
    @test Int(summary[:n_selected_job_lineage_rows]) == 10
    @test Bool(summary[:external_software_validation_completed]) == false
    @test Bool(summary[:public_claim_release_allowed]) == false
    @test String(summary[:next_gate]) ==
        "generate_independent_post_execution_tam_direct_review_packet"
end

function check_mgmfrm_tam_direct_agreement_raw_archive_audit_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_direct_agreement_raw_archive_audit.v1"
    @test String(fixture[:family]) == "mfrm"
    @test String(fixture[:scope]) ==
        "tam_direct_agreement_all_attempt_raw_archive_audit"
    @test String(fixture[:status]) == "all_attempt_archive_audited"
    @test String(fixture[:decision]) ==
        "retain_all_attempts_commit_hash_manifest_only"
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:raw_archive_committed]) == false
    @test Bool(fixture[:raw_archive_hash_manifest_committed])
    @test Bool(fixture[:public_claim_release_allowed]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_tam_direct_agreement_raw_archive_audit_v1"
    @test String(protocol[:generator]) ==
        "scripts/generate_mgmfrm_tam_direct_agreement_raw_archive_audit.jl"
    @test String(protocol[:generator_source_sha256]) == file_sha256(joinpath(
        root, String(protocol[:generator])))
    @test String(protocol[:execution_generator]) ==
        "scripts/generate_mgmfrm_tam_direct_agreement_multireplication.jl"
    @test String(protocol[:execution_generator_source_sha256]) ==
        file_sha256(joinpath(root, String(protocol[:execution_generator])))
    @test occursin(r"^[0-9a-f]{64}$", String(protocol[
        :expected_retained_failed_generator_source_sha256]))
    execution_snapshot_path = joinpath(root,
        String(protocol[:execution_refinement_snapshot]))
    @test isfile(execution_snapshot_path)
    @test String(protocol[:execution_refinement_snapshot_schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy_refinement.v1"
    @test String(protocol[:execution_refinement_snapshot_sha256]) ==
        file_sha256(execution_snapshot_path)
    @test String(protocol[:expected_execution_refinement_snapshot_sha256]) ==
        "03fe1a903d4fd218b5ab3e5ad51f5133ec1d8f274fafcea0bf8ac330876d8f4e"
    @test String(protocol[:execution_refinement_snapshot_sha256]) ==
        String(protocol[:expected_execution_refinement_snapshot_sha256])
    @test Bool(protocol[
        :execution_refinement_snapshot_sha256_matches_pinned])
    @test length(protocol[:execution_source_rows]) == 3
    @test all(row -> Bool(row[:present]) &&
        Bool(row[:artifact_sha256_matches]) &&
        String(row[:actual_sha256]) == String(row[:expected_sha256]),
        protocol[:execution_source_rows])
    @test Bool(protocol[:all_execution_source_artifacts_present_exact])
    @test Bool(protocol[:execution_seed_registry_exact])
    execution_snapshot = JSON3.read(read(execution_snapshot_path, String))
    @test String(protocol[:expected_project_toml_sha256]) == String(
        execution_snapshot[:environment_contract][:project_toml_sha256])
    @test String(protocol[:expected_manifest_toml_sha256]) == String(
        execution_snapshot[:environment_contract][:manifest_toml_sha256])
    result_path = joinpath(root, String(protocol[:result_artifact]))
    @test isfile(result_path)
    @test String(protocol[:result_artifact_sha256]) == file_sha256(result_path)
    @test Bool(protocol[:raw_root_is_gitignored])
    @test Bool(protocol[:selected_and_nonselected_attempts_in_scope])
    @test String(protocol[:manifest_fingerprint_format]) ==
        "newline_joined_path_pipe_bytes_pipe_sha256_v1_order_preserving"
    @test String(protocol[:audit_file_order]) == "lexicographic_path"
    @test Bool(protocol[:repository_generated_paths_exclude_pipe_and_newline])

    jobs = fixture[:job_rows]
    pointers = fixture[:selected_pointer_rows]
    attempts = fixture[:attempt_rows]
    @test length(jobs) == 10
    @test length(pointers) == 10
    @test length(attempts) == 11
    @test all(row -> Bool(row[:selected_pointer_valid]), jobs)
    @test all(row -> Bool(row[:all_attempts_retained]), jobs)
    @test all(row -> Bool(row[:attempts_are_contiguous]), jobs)
    @test all(row -> Bool(row[:all_attempt_integrity_passed]), jobs)
    @test all(row -> Bool(row[:selected_execution_completed]), jobs)
    @test all(row -> Bool(row[:schema_matches]) &&
        Bool(row[:job_id_matches]) &&
        Bool(row[:selected_attempt_is_latest]) &&
        Bool(row[:selected_result_exists]) &&
        Bool(row[:selected_result_path_matches]) &&
        Bool(row[:selected_result_hash_matches]) &&
        Bool(row[:pointer_hash_and_path_valid]) &&
        Bool(row[:selected_retry_documented]), pointers)
    @test count(row -> Bool(row[:selected]), attempts) == 10
    @test count(row -> !Bool(row[:selected]), attempts) == 1
    @test count(row -> Bool(row[:engine_failure]), attempts) == 1
    @test any(row -> String(row[:job_id]) == "n040_rep01" &&
        Int(row[:attempt]) == 1 && !Bool(row[:selected]) &&
        String(row[:error_type]) == "UndefVarError", attempts)
    @test any(row -> String(row[:job_id]) == "n040_rep01" &&
        Int(row[:attempt]) == 2 && Bool(row[:selected]) &&
        String(row[:infrastructure_retry_reason]) ==
            "runner_serialization_bug_fixed_before_result_write", attempts)
    @test all(row -> Bool(row[:recorded_file_rows_match_actual]) &&
        Bool(row[:retry_attempt_matches]) &&
        Bool(row[:safe_manifest_paths]) &&
        Bool(row[:attempt_integrity_passed]), attempts)
    @test any(row -> String(row[:job_id]) == "n040_rep01" &&
        Int(row[:attempt]) == 1 &&
        String(row[:recorded_manifest_fingerprint_status]) ==
            "missing_from_engine_failure_record_recomputed_by_audit",
        attempts)
    @test count(row -> String(row[
        :recorded_manifest_fingerprint_status]) == "matched", attempts) == 10
    @test all(row -> Bool(row[:refinement_snapshot_sha256_matches]) &&
        Bool(row[:truth_sha256_matches]) &&
        Bool(row[:source_input_lineage_exact]) &&
        Bool(row[:seed_registry_lineage_exact]) &&
        Bool(row[:project_toml_lineage_exact]) &&
        Bool(row[:manifest_toml_lineage_exact]) &&
        Bool(row[:environment_input_lineage_exact]) &&
        Bool(row[:generator_lineage_accepted]) &&
        Bool(row[:execution_input_lineage_exact]), attempts)
    @test all(row -> length(row[:source_input_rows]) == 3 &&
        all(source -> Bool(source[:recorded_sha256_matches]) &&
            Bool(source[:source_artifact_sha256_matches]),
            row[:source_input_rows]), attempts)
    failed_attempt = only(row for row in attempts if Bool(row[:engine_failure]))
    @test Bool(failed_attempt[:generator_current_match_required]) == false
    @test Bool(failed_attempt[
        :generator_source_sha256_matches_current]) == false
    @test Bool(failed_attempt[
        :generator_source_sha256_matches_retained_failed_version])
    @test all(row -> Bool(row[:generator_current_match_required]) &&
        Bool(row[:generator_source_sha256_matches_current]) &&
        !Bool(row[:generator_source_sha256_matches_retained_failed_version]),
        (row for row in attempts if !Bool(row[:engine_failure])))

    files = fixture[:raw_file_rows]
    @test length(files) == Int(fixture[:archive_manifest][:n_files])
    @test length(files) == 230
    @test length(unique(String(row[:path]) for row in files)) == length(files)
    @test all(row -> Int(row[:bytes]) >= 0 &&
        occursin(r"^[0-9a-f]{64}$", String(row[:sha256])), files)
    fingerprint_rows = [(;
        path = String(row[:path]),
        bytes = Int(row[:bytes]),
        sha256 = String(row[:sha256]),
    ) for row in files]
    payload = join([string(row.path, '|', row.bytes, '|', row.sha256)
        for row in fingerprint_rows], "\n")
    @test String(fixture[:archive_manifest][:manifest_sha256]) ==
        bytes2hex(sha256(payload))
    @test Bool(fixture[:archive_manifest][
        :includes_nonselected_attempts])
    @test Bool(fixture[:archive_manifest][:includes_failed_attempts])

    verification = fixture[:result_manifest_verification_rows]
    @test !isempty(verification)
    @test all(row -> Bool(row[:exists]) && Bool(row[:bytes_match]) &&
        Bool(row[:sha256_matches]), verification)
    result = JSON3.read(read(result_path, String))
    result_manifest = result[:raw_archive_manifest]
    result_manifest_payload = join([
        string(String(row[:path]), '|', Int(row[:bytes]), '|',
            String(row[:sha256])) for row in result_manifest[:file_rows]
    ], "\n")
    @test String(result_manifest[:manifest_sha256]) ==
        bytes2hex(sha256(result_manifest_payload))
    selected_attempt_by_job = Dict(String(row[:job_id]) => Int(row[:attempt])
        for row in attempts if Bool(row[:selected]))
    selected_file_tuples = Set((String(row[:path]), Int(row[:bytes]),
        String(row[:sha256])) for row in files
        if Int(row[:attempt]) != 0 &&
            Int(row[:attempt]) == selected_attempt_by_job[String(row[:job_id])])
    result_file_tuples = Set((String(row[:path]), Int(row[:bytes]),
        String(row[:sha256])) for row in result_manifest[:file_rows])
    @test selected_file_tuples == result_file_tuples
    selected_attempt_rows_by_job = Dict(String(row[:job_id]) => row
        for row in attempts if Bool(row[:selected]))
    pointer_rows_by_job = Dict(String(row[:job_id]) => row for row in pointers)
    @test all(row -> begin
        job_id = String(row[:job_id])
        pointer = pointer_rows_by_job[job_id]
        selected_attempt_row = selected_attempt_rows_by_job[job_id]
        String(row[:pointer_path]) == String(pointer[:path]) &&
            String(row[:pointer_sha256]) == String(pointer[:sha256]) &&
            String(row[:result_path]) ==
                String(pointer[:selected_result_path]) &&
            String(row[:result_sha256]) ==
                String(selected_attempt_row[:result_sha256]) &&
            Int(row[:selected_attempt]) == Int(pointer[:selected_attempt])
    end, result[:selected_attempt_rows])
    accounting = fixture[:failure_and_retry_accounting]
    @test Int(accounting[:n_failed_attempts]) == 1
    @test Int(accounting[:n_nonselected_attempts]) == 1
    @test Int(accounting[:n_documented_selected_retries]) == 1
    @test Bool(accounting[:failed_attempts_excluded_from_archive]) == false
    @test Bool(accounting[:selected_attempt_denominator_reduced]) == false
    @test Bool(accounting[:replacement_seed_used]) == false

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:archive_integrity_passed])
    @test Int(summary[:n_expected_jobs]) == 10
    @test Int(summary[:n_job_rows]) == 10
    @test Int(summary[:n_selected_pointers]) == 10
    @test Int(summary[:n_attempts]) == 11
    @test Int(summary[:n_expected_retained_attempts]) == 11
    @test Int(summary[:n_selected_attempts]) == 10
    @test Int(summary[:n_nonselected_attempts]) == 1
    @test Int(summary[:n_failed_attempts]) == 1
    @test Int(summary[:n_files]) == 230
    @test Bool(summary[:all_selected_pointers_valid])
    @test Bool(summary[:all_attempt_integrity_passed])
    @test Bool(summary[:all_attempts_retained])
    @test Bool(summary[:selected_result_sets_match])
    @test Bool(summary[:result_selected_attempt_rows_match_audit])
    @test Bool(summary[:selected_attempt_files_match_result_manifest])
    @test Bool(summary[:recorded_result_manifest_fingerprint_matches])
    @test Bool(summary[:all_recorded_result_manifest_files_match])
    @test Bool(summary[:all_selected_generator_hashes_match_current])
    @test String(summary[:execution_refinement_snapshot_sha256]) ==
        String(protocol[:execution_refinement_snapshot_sha256])
    @test Bool(summary[
        :execution_refinement_snapshot_sha256_matches_pinned])
    @test Bool(summary[:all_execution_source_artifacts_present_exact])
    @test Bool(summary[:execution_seed_registry_exact])
    @test Bool(summary[:all_retained_refinement_lineage_exact])
    @test Bool(summary[:all_retained_truth_lineage_exact])
    @test Bool(summary[:all_retained_source_input_lineage_exact])
    @test Bool(summary[:all_retained_seed_registry_lineage_exact])
    @test Bool(summary[:all_retained_project_toml_lineage_exact])
    @test Bool(summary[:all_retained_manifest_toml_lineage_exact])
    @test Bool(summary[:all_retained_environment_input_lineage_exact])
    @test Bool(summary[:all_retained_generator_lineage_accepted])
    @test Bool(summary[:retained_failed_generator_exception_exact])
    @test Int(summary[:n_retained_failed_generator_exceptions]) == 1
    @test Bool(summary[:all_retained_execution_input_lineage_exact])
    @test Int(summary[:n_execution_input_lineage_failures]) == 0
    @test Bool(summary[:all_file_paths_unique])
    @test Bool(summary[:raw_root_is_gitignored])
    @test Bool(summary[:result_execution_completed])
    @test Bool(summary[:all_selected_execution_completed])
    @test Int(summary[:n_selected_engine_failures]) == 0
    @test Bool(summary[:raw_archive_committed]) == false
    @test Bool(summary[:hash_manifest_committed])
    @test Bool(summary[:public_claim_release_allowed]) == false
end

function check_mgmfrm_tam_direct_agreement_post_execution_review_packet_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_direct_agreement_post_execution_review_packet.v1"
    @test String(fixture[:family]) == "mfrm"
    @test String(fixture[:scope]) ==
        "tam_direct_agreement_independent_post_execution_review_packet"
    @test String(fixture[:status]) == "packet_frozen_review_not_completed"
    @test String(fixture[:decision]) ==
        "freeze_post_execution_review_packet_keep_public_claims_blocked"
    @test Bool(fixture[:tam_direct_local_execution_completed])
    @test Bool(fixture[:scheduled_execution_recorded])
    @test Bool(fixture[:external_software_validation_completed]) == false
    @test Bool(fixture[:independent_review_completed]) == false
    @test Bool(fixture[:signed_review_manifest_attached]) == false
    @test Bool(fixture[:public_claim_release_allowed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_tam_direct_agreement_post_execution_review_packet_v1"
    @test String(protocol[:review_kind]) ==
        "independent_scientific_computational_and_reproducibility_review"
    @test String(protocol[:generator]) ==
        "scripts/generate_mgmfrm_tam_direct_agreement_post_execution_review_packet.jl"
    @test String(protocol[:generator_source_sha256]) == file_sha256(joinpath(
        root, String(protocol[:generator])))
    @test Bool(protocol[:generated_after_execution])
    @test Bool(protocol[:distinct_from_pre_execution_packet])
    @test Bool(protocol[:pre_execution_packet_remains_immutable])
    @test Bool(protocol[:signed_review_manifest_required])
    @test Bool(protocol[:independent_reexecution_required])

    inputs = fixture[:required_input_rows]
    @test length(inputs) == 6
    @test Set(String(row[:input]) for row in inputs) == Set([
        "multireplication_result",
        "all_attempt_raw_archive_audit",
        "frozen_policy",
        "policy_refinement",
        "policy_refinement_execution_snapshot",
        "pre_execution_independent_review_packet",
    ])
    @test all(row -> Bool(row[:present]) &&
        Bool(row[:reviewer_must_verify]), inputs)
    @test all(row -> isfile(joinpath(root, String(row[:path]))) &&
        String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path]))), inputs)
    input_by_name = Dict(String(row[:input]) => row for row in inputs)
    post_result_path = joinpath(root,
        String(input_by_name["multireplication_result"][:path]))
    post_audit_path = joinpath(root,
        String(input_by_name["all_attempt_raw_archive_audit"][:path]))
    post_policy_path = joinpath(root,
        String(input_by_name["frozen_policy"][:path]))
    post_refinement_path = joinpath(root,
        String(input_by_name["policy_refinement"][:path]))
    post_execution_snapshot_path = joinpath(root,
        String(input_by_name[
            "policy_refinement_execution_snapshot"][:path]))
    post_pre_packet_path = joinpath(root,
        String(input_by_name[
            "pre_execution_independent_review_packet"][:path]))
    post_result = JSON3.read(read(post_result_path, String))
    post_audit = JSON3.read(read(post_audit_path, String))
    post_refinement = JSON3.read(read(post_refinement_path, String))
    post_execution_snapshot =
        JSON3.read(read(post_execution_snapshot_path, String))
    post_pre_packet = JSON3.read(read(post_pre_packet_path, String))
    result_protocol = post_result[:protocol]
    @test String(result_protocol[:frozen_policy_artifact_sha256]) ==
        file_sha256(post_policy_path)
    @test String(result_protocol[:refinement_artifact_sha256]) ==
        file_sha256(post_execution_snapshot_path)
    @test joinpath(root, String(result_protocol[:refinement_artifact])) ==
        post_execution_snapshot_path
    @test String(result_protocol[:generator_source_sha256]) ==
        file_sha256(joinpath(root, String(result_protocol[:generator])))
    @test String(result_protocol[:baseline_artifact_sha256]) ==
        file_sha256(joinpath(root,
            String(result_protocol[:baseline_artifact])))
    @test String(result_protocol[:recovery_policy_artifact_sha256]) ==
        file_sha256(joinpath(root,
            String(result_protocol[:recovery_policy_artifact])))
    @test String(result_protocol[
        :frozen_primary_gate_fingerprint_sha256]) == String(post_refinement[
        :frozen_primary_gate_fingerprint_sha256])
    @test String(post_audit[:protocol][:result_artifact_sha256]) ==
        file_sha256(post_result_path)
    @test String(post_audit[:protocol][
        :execution_generator_source_sha256]) ==
        String(result_protocol[:generator_source_sha256])
    pre_input_by_name = Dict(String(row[:input]) => row
        for row in post_pre_packet[:required_input_rows])
    @test String(pre_input_by_name[
        "tam_direct_agreement_policy"][:sha256]) ==
        file_sha256(post_policy_path)
    @test String(pre_input_by_name[
        "tam_direct_agreement_policy_refinement"][:sha256]) !=
        file_sha256(post_refinement_path)
    @test Bool(fixture[:source_hash_chain_valid])
    @test Bool(fixture[:core_source_hash_chain_valid])
    execution_lineage = fixture[:execution_input_lineage]
    @test joinpath(root,
        String(execution_lineage[:execution_refinement_snapshot])) ==
        post_execution_snapshot_path
    @test String(execution_lineage[
        :execution_refinement_snapshot_sha256]) ==
        file_sha256(post_execution_snapshot_path)
    @test String(execution_lineage[
        :expected_execution_refinement_snapshot_sha256]) ==
        "03fe1a903d4fd218b5ab3e5ad51f5133ec1d8f274fafcea0bf8ac330876d8f4e"
    @test Bool(execution_lineage[
        :execution_refinement_snapshot_sha256_matches_pinned])
    @test Bool(execution_lineage[:aggregation_provenance_present])
    @test Bool(execution_lineage[:aggregation_generator_hash_matches])
    @test Bool(execution_lineage[:aggregate_wrapper_lineage_exact])
    @test Int(execution_lineage[
        :n_aggregate_selected_job_lineage_rows]) == 10
    @test Bool(execution_lineage[:aggregate_selected_seed_registry_exact])
    @test length(execution_lineage[
        :aggregate_selected_job_lineage_rows]) == 10
    @test all(row -> Bool(row[:execution_input_lineage_exact]),
        execution_lineage[:aggregate_selected_job_lineage_rows])
    @test Bool(execution_lineage[
        :aggregate_selected_execution_input_lineage_exact])
    @test Int(execution_lineage[
        :n_raw_retained_attempt_lineage_rows]) == 11
    @test Bool(execution_lineage[:raw_audit_snapshot_lineage_exact])
    @test Bool(execution_lineage[:raw_attempt_lineage_rows_exact])
    @test Bool(execution_lineage[:raw_summary_lineage_exact])
    @test Bool(execution_lineage[:raw_job_execution_input_lineage_exact])
    @test Bool(execution_lineage[
        :aggregate_selected_and_raw_retained_lineage_independently_exact])
    @test String(execution_lineage[
        :execution_refinement_snapshot_sha256]) == String(
        post_audit[:protocol][:execution_refinement_snapshot_sha256])
    @test String(execution_lineage[
        :execution_refinement_snapshot_sha256]) == file_sha256(
        post_execution_snapshot_path)
    @test String(post_execution_snapshot[:schema]) ==
        "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy_refinement.v1"
    lineage = fixture[:pre_execution_lineage]
    @test Bool(lineage[:exact_input_lineage]) == false
    @test Bool(lineage[:policy_hash_matches])
    @test Bool(lineage[:refinement_hash_matches]) == false
    @test Bool(lineage[:immutable_pre_execution_packet_preserved])
    @test Bool(lineage[:post_execution_regeneration_used_to_erase_mismatch]) ==
        false
    @test String(lineage[:status]) ==
        "refinement_snapshot_hash_mismatch_requires_independent_review"

    layers = fixture[:decision_layers]
    @test String(layers[:primary_policy][:rule]) ==
        "all_three_n100_blocks_pass_at_least_four_of_five_runs"
    @test Bool(layers[:recovery_qualifiers][
        :changes_primary_agreement_decision]) == false
    @test Bool(layers[:computation_and_protocol][:valid])
    @test Bool(layers[:computation_and_protocol][
        :all_protocol_alignment_valid])
    @test Bool(layers[:computation_and_protocol][
        :all_tam_executions_valid])
    @test Bool(layers[:computation_and_protocol][
        :all_package_sampler_gates_passed])
    @test Bool(layers[:computation_and_protocol][
        :all_attempt_raw_archive_audit_passed])
    @test Bool(layers[:computation_and_protocol][
        :aggregate_selected_execution_input_lineage_exact])
    @test Bool(layers[:computation_and_protocol][
        :raw_job_execution_input_lineage_exact])
    @test length(fixture[:primary_scenario_block_rows]) == 3
    @test length(fixture[:all_scenario_block_rows]) == 6

    tasks = fixture[:review_task_rows]
    @test length(tasks) == 15
    @test all(row -> Bool(row[:reviewer_required]) &&
        String(row[:reviewer_decision]) == "pending_independent_review" &&
        !Bool(row[:completed]) &&
        Bool(row[:blocks_public_claim_release]), tasks)
    @test any(row -> String(row[:task]) ==
        "failure_and_retry_accounting", tasks)
    @test any(row -> String(row[:task]) ==
        "pre_execution_chronology_and_amendment", tasks)
    @test any(row -> String(row[:task]) ==
        "uto_gmfrm_mgmfrm_nonextrapolation", tasks)

    fields = fixture[:reviewer_manifest_field_rows]
    @test length(fields) == 14
    @test all(row -> Bool(row[:required]) && !Bool(row[:completed]) &&
        String(row[:placeholder_policy]) == "reviewer_supplied_no_default",
        fields)
    @test any(row -> String(row[:field]) ==
        "independent_reexecution_record", fields)
    @test any(row -> String(row[:field]) == "signature", fields)

    claims = fixture[:claim_review_rows]
    @test length(claims) == 6
    @test all(row -> Bool(row[:public_claim_allowed]) == false, claims)
    @test count(row -> Bool(row[:artifact_support]), claims) == 1
    @test any(row -> String(row[:claim]) ==
        "safe_local_outcome_wording" &&
        String(row[:reviewer_decision]) == "pending_independent_review",
        claims)
    @test all(row -> String(row[:reviewer_decision]) ==
        "must_remain_blocked", claims[2:end])

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "post_execution_packet_frozen"
    @test Bool(decision[:packet_integrity_passed])
    @test Bool(decision[:aggregate_selected_execution_input_lineage_exact])
    @test Bool(decision[:raw_job_execution_input_lineage_exact])
    @test Bool(decision[:independent_reviewer_assigned]) == false
    @test Bool(decision[:independent_reexecution_completed]) == false
    @test Bool(decision[:signed_review_manifest_attached]) == false
    @test Bool(decision[:independent_review_completed]) == false
    @test Bool(decision[:public_claim_release_allowed]) == false

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:packet_integrity_passed])
    @test Bool(summary[:source_hash_chain_valid])
    @test Bool(summary[:core_source_hash_chain_valid])
    @test Bool(summary[
        :execution_refinement_snapshot_sha256_matches_pinned])
    @test Bool(summary[:aggregate_wrapper_lineage_exact])
    @test Bool(summary[:aggregate_selected_execution_input_lineage_exact])
    @test Bool(summary[:raw_job_execution_input_lineage_exact])
    @test Bool(summary[
        :aggregate_selected_and_raw_retained_lineage_independently_exact])
    @test Bool(summary[:pre_execution_packet_exact_input_lineage]) == false
    @test Bool(summary[:pre_execution_refinement_mismatch_preserved])
    @test Bool(summary[:pre_execution_packet_policy_hash_matches])
    @test Bool(summary[:pre_execution_packet_refinement_hash_matches]) == false
    @test Bool(summary[:tam_direct_local_execution_completed])
    @test Bool(summary[:scheduled_execution_recorded])
    @test Bool(summary[:execution_valid])
    @test String(summary[:primary_policy_decision]) == "pass"
    @test String(summary[:scientific_interpretation]) ==
        "local_numerical_agreement_with_both_recovery_profiles"
    @test Bool(summary[:primary_direct_gate_passed])
    @test Bool(summary[:package_recovery_qualifier_passed])
    @test Bool(summary[:tam_recovery_qualifier_passed])
    @test Int(summary[:n_required_inputs]) == 6
    @test Int(summary[:n_review_tasks]) == 15
    @test Int(summary[:n_reviewer_manifest_fields]) == 14
    @test Int(summary[:n_claim_rows]) == 6
    @test Int(summary[:n_primary_scenario_block_rows]) == 3
    @test Bool(summary[:independent_review_completed]) == false
    @test Bool(summary[:signed_review_manifest_attached]) == false
    @test Bool(summary[:external_software_validation_completed]) == false
    @test Bool(summary[:public_claim_release_allowed]) == false
    @test Set(String.(summary[:remaining_public_blockers])) == Set([
        "independent_reviewer_not_assigned",
        "independent_reexecution_not_completed",
        "signed_review_manifest_not_attached",
        "per_task_review_decisions_missing",
        "per_claim_review_decisions_missing",
        "external_construct_validity_not_supplied",
        "pre_execution_packet_refinement_hash_lineage_mismatch",
    ])
    @test String(summary[:recommendation]) ==
        "send_frozen_packet_to_independent_reviewer_without_claim_release"
    @test String(summary[:next_gate]) ==
        "assign_independent_reviewer_reexecute_and_attach_signed_manifest"
end
