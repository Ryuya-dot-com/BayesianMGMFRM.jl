using Test
using BayesianMGMFRM

function _ld1b1_test_plan(;
        repetitions = 30,
        phase = :pilot,
        base_seed = 20260720,
        grid_id = "ld1b1_pilot_test",
        n_persons = 40,
        n_testlets = 4,
        items_per_testlet = 3,
        n_raters = 4,
        n_categories = 4)
    return local_dependence_simulation_grid(;
        repetitions,
        phase,
        base_seed,
        grid_id,
        n_persons,
        n_testlets,
        items_per_testlet,
        n_raters,
        n_categories,
    )
end

function _ld1b1_reader_tokens!(tokens, value)
    if value isa NamedTuple
        append!(tokens, lowercase.(String.(propertynames(value))))
        for item in values(value)
            _ld1b1_reader_tokens!(tokens, item)
        end
    elseif value isa AbstractDict
        for (key, item) in pairs(value)
            push!(tokens, lowercase(string(key)))
            _ld1b1_reader_tokens!(tokens, item)
        end
    elseif value isa Tuple || value isa AbstractVector
        for item in value
            _ld1b1_reader_tokens!(tokens, item)
        end
    elseif value isa Symbol || value isa AbstractString
        push!(tokens, lowercase(string(value)))
    end
    return tokens
end

_ld1b1_reader_text(value) = join(_ld1b1_reader_tokens!(String[], value), '\n')

@testset "LD1b1 pilot contract" begin
    calibration = local_dependence_calibration_contract()
    contract = local_dependence_calibration_pilot_contract(;
        calibration_contract = calibration,
    )

    @test contract.schema ==
        "bayesianmgmfrm.local_dependence_calibration_pilot_contract.v1"
    @test contract.object === :local_dependence_calibration_pilot_contract
    @test contract.profile === :ld1b1_pilot_protocol_v1
    @test contract.status === :pilot_protocol_preflight_only
    @test contract.calibration_contract == calibration

    planning = contract.planning
    @test planning.planning_profile === :ld1_preflight_v1
    @test planning.phase === :pilot
    @test planning.pilot_repetitions == 30
    @test planning.evaluation_repetition_candidates == (50, 100)
    @test planning.evaluation_repetitions_selected_before_evaluation
    @test !planning.mid_evaluation_extension_allowed
    @test planning.n_scenarios == 22
    @test planning.n_structurally_eligible_scenarios == 18
    @test planning.n_structural_rejection_scenarios == 4
    @test planning.n_jobs == 660
    @test planning.n_fit_jobs == 540
    @test planning.n_pre_fit_rejection_jobs == 120
    @test planning.base_dimensions == (;
        n_persons = 40,
        n_testlets = 4,
        items_per_testlet = 3,
        n_raters = 4,
        n_categories = 4,
    )

    sampler = contract.sampler
    @test sampler.backend === :advancedhmc
    @test sampler.algorithm === :nuts
    @test sampler.chains == 4
    @test sampler.warmup_per_chain == 500
    @test sampler.draws_per_chain == 500
    @test sampler.total_retained_draws == 2_000
    @test sampler.target_accept == 0.90
    @test sampler.max_depth == 10
    @test sampler.metric === :diagonal
    @test sampler.ad_backend === :analytic
    @test sampler.diagnostic_draws == 250
    @test sampler.diagnostic_draw_policy === :distinct_without_replacement
    @test sampler.posterior_predictive_replicates_per_draw == 1

    quality = contract.quality_requirements
    expected_diagnostic_contract =
        BayesianMGMFRM._MCMC_DIAGNOSTIC_CONTRACT
    expected_diagnostic_contract_details =
        BayesianMGMFRM._mcmc_diagnostic_contract_record()
    @test quality.diagnostic_contract === expected_diagnostic_contract
    @test isequal(
        quality.diagnostic_contract_details,
        expected_diagnostic_contract_details,
    )
    @test quality.diagnostic_contract_details.id ===
        expected_diagnostic_contract
    @test quality.rhat_method === :rank_normalized
    @test quality.primary_rhat_field === :rank_normalized_rhat
    @test quality.maximum_rhat == 1.01
    @test quality.ess_method === :bulk_and_tail
    @test quality.primary_ess_fields == (:bulk_ess, :tail_ess)
    @test quality.primary_flag_field === :rank_normalized_flag
    @test quality.tail_probability == 0.10
    @test quality.minimum_bulk_ess == 400
    @test quality.minimum_tail_ess == 400
    @test quality.maximum_divergences == 0
    @test quality.maximum_depth_hits == 0
    @test quality.e_bfmi_field === :e_bfmi
    @test quality.e_bfmi_completeness_field === :e_bfmi_complete
    @test quality.e_bfmi_chain_coverage_required
    @test quality.minimum_e_bfmi == 0.30

    operational = contract.operational_requirements
    @test operational.minimum_completed_per_eligible_scenario == 27
    @test operational.maximum_categorized_failures_per_eligible_scenario == 3
    @test operational.categorized_failure_statuses == (
        :generation_failed,
        :fit_failed,
        :diagnostic_failed,
    )
    @test all(status -> status in BayesianMGMFRM._LD1B0_STATUSES,
        operational.categorized_failure_statuses)
    @test operational.required_missing_results == 0
    @test operational.required_pre_fit_rejections_per_rejection_scenario == 30
    @test operational.primary_attempt == 1
    @test !operational.primary_outcomes_overwritable_by_retries
    @test operational.retry_role === :separate_remediation_record_only

    precision = contract.precision_policy
    @test precision.method === :wilson_score
    @test precision.confidence == 0.95
    @test precision.applies_to === :replication_level_binary_rates_only
    @test precision.pilot_maximum_half_width == 0.18
    @test precision.evaluation_target_half_width == 0.10
    @test precision.selection_time === :after_pilot_before_evaluation
    @test !precision.mid_evaluation_extension_allowed
    @test !precision.pooled_pair_interval_available

    resources = contract.resource_policy
    @test resources.expected_totals == (;
        n_jobs = 660,
        n_fit_jobs = 540,
        n_pre_fit_rejection_jobs = 120,
        n_ratings = 396_840,
        n_probability_cells = 1_587_360,
        n_truth_cells = 10_240_500,
    )
    @test resources.total_caps == (;
        n_jobs = 700,
        n_fit_jobs = 600,
        n_ratings = 500_000,
        n_probability_cells = 2_000_000,
        n_truth_cells = 13_000_000,
    )
    @test resources.per_dataset_caps == (;
        n_ratings = 2_500,
        n_probability_cells = 10_000,
        n_truth_cells = 60_000,
    )
    @test resources.positive_total_headroom_required

    @test !contract.pair_truth_oracle_available
    @test !contract.pairwise_power_available
    @test contract.pairwise_power_scope ===
        :out_of_scope_without_pair_truth_oracle
    @test !contract.pilot_execution_completed
    @test !contract.evaluation_profile_frozen
    @test !contract.repeated_calibration_completed
    @test !contract.calibration_evidence_available
    @test !contract.diagnostic_decision_labels_available
    @test !contract.mechanism_interpretation_eligible

    reader_text = _ld1b1_reader_text(contract)
    for fragment in ("public_claim", "internal", "next_gate")
        @test !occursin(fragment, reader_text)
    end

    tampered_calibration = merge(calibration, (; status = :changed))
    @test_throws ArgumentError local_dependence_calibration_pilot_contract(
        calibration_contract = tampered_calibration,
    )
end

@testset "LD1b1 canonical pilot preflight" begin
    contract = local_dependence_calibration_pilot_contract()
    plan = _ld1b1_test_plan()
    preflight = local_dependence_calibration_pilot_preflight(
        plan;
        contract,
    )

    @test preflight.schema ==
        "bayesianmgmfrm.local_dependence_calibration_pilot_preflight.v1"
    @test preflight.object === :local_dependence_calibration_pilot_preflight
    @test preflight.profile === contract.profile
    @test preflight.status === :pilot_plan_preflight_passed
    @test preflight.contract == contract
    @test preflight.grid_id == "ld1b1_pilot_test"
    @test preflight.base_seed == 20260720
    @test preflight.planning_profile === :ld1_preflight_v1
    @test preflight.phase === :pilot
    @test preflight.n_plan_rows == 660
    @test preflight.n_scenarios == 22
    @test preflight.n_replications == 30
    @test preflight.n_fit_jobs == 540
    @test preflight.n_pre_fit_rejection_jobs == 120
    @test length(preflight.scenario_counts) == 22
    @test all(row -> row.n == 30, preflight.scenario_counts)
    @test length(preflight.rejection_counts) == 4
    @test all(row -> row.n == 30, preflight.rejection_counts)
    @test length(preflight.job_rows) == 660
    @test [row.row_index for row in preflight.job_rows] == collect(1:660)
    @test count(row -> row.expected_action === :fit_and_score_diagnostic,
        preflight.job_rows) == 540
    @test count(row -> row.expected_action === :pre_fit_reject,
        preflight.job_rows) == 120
    @test all(row -> row.primary_attempt == 1 &&
        !row.primary_outcome_overwritable_by_retries &&
        row.execution_status === :not_executed,
        preflight.job_rows)
    @test length(unique(row.fit_seed for row in preflight.job_rows)) == 660
    @test length(unique(row.draw_selection_seed for row in
        preflight.job_rows)) == 660
    @test length(unique(row.posterior_predictive_seed for row in
        preflight.job_rows)) == 660

    @test preflight.plan_checks.passed
    @test all(identity, values(preflight.plan_checks)[1:(end - 1)])
    @test preflight.resource_summary.actual ==
        contract.resource_policy.expected_totals
    @test preflight.resource_summary.caps ==
        contract.resource_policy.total_caps
    @test preflight.resource_summary.checks.passed
    @test preflight.resource_summary.checks.actual_matches_reference
    @test preflight.resource_summary.checks.within_total_caps
    @test preflight.resource_summary.checks.positive_total_headroom
    @test preflight.resource_summary.checks.within_per_dataset_caps
    @test preflight.resource_summary.maxima.n_ratings <= 2_500
    @test preflight.resource_summary.maxima.n_probability_cells <= 10_000
    @test preflight.resource_summary.maxima.n_truth_cells <= 60_000

    @test preflight.seed_checks.passed
    @test preflight.seed_checks.pilot_root_unique_by_replication
    @test preflight.seed_checks.scenario_specific_execution_seeds
    @test preflight.seed_checks.pilot_execution_seed_values_unique
    @test preflight.seed_checks.root_namespaces_disjoint
    @test preflight.seed_checks.component_namespaces_disjoint
    @test preflight.seed_checks.execution_namespaces_disjoint
    @test preflight.seed_checks.n_unique_pilot_root_seeds == 30
    @test preflight.seed_checks.n_unique_pilot_execution_seed_values == 1_980
    @test preflight.seed_checks.n_evaluation_replications_checked == 100

    capability = preflight.sampler_capability
    expected_diagnostic_contract =
        BayesianMGMFRM._MCMC_DIAGNOSTIC_CONTRACT
    expected_diagnostic_contract_details =
        BayesianMGMFRM._mcmc_diagnostic_contract_record()
    @test capability.current_rhat_method === :rank_normalized
    @test capability.current_ess_method === :bulk_and_tail
    @test capability.current_rhat_ess_status === :rank_normalized_available
    @test capability.current_diagnostic_contract ===
        expected_diagnostic_contract
    @test isequal(
        capability.current_diagnostic_contract_details,
        expected_diagnostic_contract_details,
    )
    @test capability.required_diagnostic_contract ===
        expected_diagnostic_contract
    @test isequal(
        capability.required_diagnostic_contract_details,
        expected_diagnostic_contract_details,
    )
    @test capability.rank_normalized_rhat_available
    @test capability.bulk_tail_ess_available
    @test capability.required_rhat_method === :rank_normalized
    @test capability.required_ess_method === :bulk_and_tail
    @test capability.rhat_method_matches_requirement
    @test capability.ess_method_matches_requirement
    @test capability.diagnostic_contract_matches_requirement
    @test capability.diagnostic_contract_details_match_requirement
    @test capability.primary_fields_match_requirement
    @test capability.tail_probability_matches_requirement
    @test capability.e_bfmi_contract_matches_requirement
    @test capability.minimum_independent_chains == 2
    @test capability.planned_independent_chains == 4
    @test capability.independent_chain_requirement_met
    @test capability.minimum_draws_per_diagnostic_chain == 5
    @test capability.planned_draws_per_diagnostic_chain == 250
    @test capability.diagnostic_draw_requirement_met
    @test capability.requirement_met
    @test isempty(capability.blockers)
    @test preflight.capability_blockers == capability.blockers

    altered_details = merge(
        contract.quality_requirements.diagnostic_contract_details,
        (; odd_draw_policy = :altered_for_negative_test),
    )
    altered_contract = merge(contract, (;
        quality_requirements = merge(
            contract.quality_requirements,
            (; diagnostic_contract_details = altered_details),
        ),
    ))
    altered_capability =
        BayesianMGMFRM._ld1b1_sampler_capability(altered_contract)
    @test !altered_capability.diagnostic_contract_details_match_requirement
    @test !altered_capability.requirement_met
    @test :diagnostic_contract_details_mismatch in
        altered_capability.blockers

    @test ismissing(preflight.evaluation_repetitions_selected)
    @test preflight.evaluation_repetition_selection_status ===
        :pending_pilot_results
    @test !preflight.pair_truth_oracle_available
    @test !preflight.pairwise_power_available
    @test preflight.pilot_execution_authorized
    @test !preflight.pilot_execution_completed
    @test !preflight.evaluation_profile_frozen
    @test !preflight.repeated_calibration_completed
    @test !preflight.calibration_evidence_available
    @test !preflight.diagnostic_decision_labels_available
    @test !preflight.mechanism_interpretation_eligible

    reader_text = _ld1b1_reader_text(preflight)
    for fragment in ("public_claim", "internal", "next_gate")
        @test !occursin(fragment, reader_text)
    end
end

@testset "LD1b1 Wilson precision boundaries" begin
    plan = _ld1b1_test_plan()
    preflight = local_dependence_calibration_pilot_preflight(plan)
    @test length(preflight.precision_reference) == 3
    by_n = Dict(row.replications => row for row in
        preflight.precision_reference)
    pilot = by_n[30]
    candidate_50 = by_n[50]
    candidate_100 = by_n[100]
    @test pilot.role === :pilot
    @test pilot.worst_case_successes == 15
    @test pilot.estimate == 0.5
    @test pilot.half_width <= 0.18
    @test pilot.precision_requirement_met
    @test candidate_50.role === :evaluation_candidate
    @test candidate_50.half_width > 0.10
    @test !candidate_50.precision_requirement_met
    @test candidate_100.half_width <= 0.10
    @test candidate_100.precision_requirement_met
    @test candidate_50.half_width > candidate_100.half_width
    @test nextfloat(pilot.maximum_half_width) > pilot.maximum_half_width
    @test prevfloat(candidate_100.maximum_half_width) <
        candidate_100.maximum_half_width
end

@testset "LD1b1 plan and contract tamper rejection" begin
    plan = _ld1b1_test_plan()
    contract = local_dependence_calibration_pilot_contract()

    @test_throws ArgumentError local_dependence_calibration_pilot_preflight(
        plan[1:(end - 1)]; contract)

    reordered = copy(plan)
    reordered[1], reordered[2] = reordered[2], reordered[1]
    @test_throws ArgumentError local_dependence_calibration_pilot_preflight(
        reordered; contract)

    evaluation = _ld1b1_test_plan(phase = :evaluation)
    mixed_phase = copy(plan)
    mixed_phase[end] = evaluation[end]
    @test_throws ArgumentError local_dependence_calibration_pilot_preflight(
        mixed_phase; contract)
    @test_throws ArgumentError local_dependence_calibration_pilot_preflight(
        evaluation; contract)

    tampered_seed = copy(plan)
    tampered_seed[1] = merge(tampered_seed[1], (;
        seed = tampered_seed[1].seed + 1,
    ))
    @test_throws ArgumentError local_dependence_calibration_pilot_preflight(
        tampered_seed; contract)

    wrong_dimensions = _ld1b1_test_plan(n_persons = 41)
    @test_throws ArgumentError local_dependence_calibration_pilot_preflight(
        wrong_dimensions; contract)

    caps = contract.resource_policy.total_caps
    tampered_caps = merge(contract, (;
        resource_policy = merge(contract.resource_policy, (;
            total_caps = merge(caps, (; n_jobs = 660)),
        )),
    ))
    @test_throws ArgumentError local_dependence_calibration_pilot_preflight(
        plan; contract = tampered_caps)

    tampered_status = merge(contract, (; status = :changed))
    @test_throws ArgumentError local_dependence_calibration_pilot_preflight(
        plan; contract = tampered_status)
end
