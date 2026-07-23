using Test
using Random
using BayesianMGMFRM

function _ld1b_fixture_fit(data; n_draws::Int = 4)
    design = getdesign(mfrm_spec(data; thresholds = :partial_credit))
    draws = zeros(n_draws, length(design.parameter_names))
    for draw in 2:n_draws
        draws[draw, :] .= range(
            -0.02 * draw,
            0.02 * draw;
            length = size(draws, 2),
        )
    end
    return MFRMFit(
        design,
        MFRMPrior(),
        draws,
        zeros(n_draws),
        1.0,
        ones(Int, n_draws),
        collect(1:n_draws),
        [1.0],
        :fixture,
        :fixture,
        0,
        0.1,
    )
end

function _ld1b_diagnostic_contract(; pair_fdr_alpha::Real = 0.05,
        global_fwer_alpha::Real = 0.05)
    return local_dependence_contract(
        profile = :custom_unvalidated,
        min_common_units = 2,
        min_eligible_draws = 2,
        min_eligible_draw_fraction = 0.5,
        pair_fdr_alpha = pair_fdr_alpha,
        global_fwer_alpha = global_fwer_alpha,
    )
end

function _ld1b_plan_row(scenario_id::Symbol;
        replication::Int = 1,
        phase::Symbol = :pilot,
        base_seed::Int = 2301,
        grid_id::String = "ld1b-fixture")
    rows = local_dependence_simulation_grid(
        repetitions = replication,
        base_seed = base_seed,
        phase = phase,
        grid_id = grid_id,
        n_persons = 8,
        n_testlets = 4,
        items_per_testlet = 2,
        n_raters = 2,
        n_categories = 3,
    )
    return only(row for row in rows
        if row.scenario_id === scenario_id && row.replication == replication)
end

function _ld1b_integration_inputs(plan_row;
        diagnostic_contract = _ld1b_diagnostic_contract(),
        diagnostic_seed::Int = 7301)
    simulation = simulate_local_dependence(plan_row)
    fit = _ld1b_fixture_fit(simulation.data)
    diagnostic = local_dependence_summary(
        fit;
        contract = diagnostic_contract,
        draw_indices = 1:4,
        rng = MersenneTwister(diagnostic_seed),
    )
    return (; plan_row, simulation, fit, diagnostic_contract, diagnostic)
end

const _LD1B_INTEGRATION_CACHE = Dict{Any,Any}()

function _ld1b_cached_integration(plan_row;
        diagnostic_contract = _ld1b_diagnostic_contract(),
        diagnostic_seed::Int = 7301)
    key = (
        plan_row.grid_id,
        plan_row.phase,
        plan_row.base_seed,
        plan_row.replication,
        plan_row.scenario_id,
        diagnostic_contract,
        diagnostic_seed,
    )
    return get!(_LD1B_INTEGRATION_CACHE, key) do
        _ld1b_integration_inputs(
            plan_row;
            diagnostic_contract,
            diagnostic_seed,
        )
    end
end

function _ld1b_calibration_contract(
        diagnostic_contract = _ld1b_diagnostic_contract(); kwargs...)
    return local_dependence_calibration_contract(;
        diagnostic_contract = diagnostic_contract,
        kwargs...,
    )
end

function _ld1b_value_at(value, index::Int)
    value isa Function && return value(index)
    value isa AbstractVector && return value[index]
    return value
end

function _ld1b_diagnostic_evidence(diagnostic;
        n_pairs::Int = length(diagnostic.pair_rows),
        pair_raw = 1.0,
        pair_bh = 1.0,
        pair_status = :eligible_report_only,
        family_tail = 1.0,
        global_tail = 1.0,
        reverse_pairs::Bool = false)
    0 <= n_pairs <= length(diagnostic.pair_rows) ||
        throw(ArgumentError("invalid fixture pair count"))
    source_pairs = collect(diagnostic.pair_rows[1:n_pairs])
    reverse_pairs && reverse!(source_pairs)
    pair_rows = Tuple(merge(pair, (;
        status = _ld1b_value_at(pair_status, index),
        posterior_predictive_tail_fraction =
            _ld1b_value_at(pair_raw, index),
        bh_adjusted_tail_fraction = _ld1b_value_at(pair_bh, index),
    )) for (index, pair) in pairs(source_pairs))
    family_max_rows = Tuple(merge(row, (;
        posterior_predictive_tail_fraction =
            _ld1b_value_at(family_tail, index),
    )) for (index, row) in pairs(diagnostic.family_max_rows))
    global_evidence = merge(diagnostic.global_evidence, (;
        posterior_predictive_tail_fraction = global_tail,
    ))
    return merge(diagnostic, (;
        n_pair_rows = length(pair_rows),
        pair_rows,
        family_max_rows,
        global_evidence,
    ))
end

function _ld1b_status_count(summary, status::Symbol)
    return only(row.n for row in summary.status_rows if row.status === status)
end

function _ld1b_scenario_row(summary, scenario_id::Symbol)
    return only(row for row in summary.scenario_rows
        if row.scenario_id === scenario_id)
end

function _ld1b_global_row(summary, scenario_id::Symbol)
    return only(row for row in summary.global_rows
        if row.scenario_id === scenario_id)
end

@testset "LD1b phase seed namespaces remain deterministic" begin
    smoke = _ld1b_plan_row(:null_same_rater; phase = :smoke)
    pilot = _ld1b_plan_row(:null_same_rater; phase = :pilot)
    evaluation = _ld1b_plan_row(:null_same_rater; phase = :evaluation)
    repeated = _ld1b_plan_row(:null_same_rater; phase = :pilot)
    next_replication = _ld1b_plan_row(
        :null_same_rater;
        replication = 2,
        phase = :pilot,
    )

    @test smoke.seed + 10_000_000 == pilot.seed
    @test pilot.seed + 10_000_000 == evaluation.seed
    @test pilot.seed + 1 == next_replication.seed
    @test pilot.component_seeds == repeated.component_seeds
    @test pilot.component_seeds != smoke.component_seeds
    @test pilot.component_seeds != evaluation.component_seeds
    @test pilot.component_seeds != next_replication.component_seeds
end

@testset "LD1b calibration contract and claim boundary" begin
    diagnostic_contract = _ld1b_diagnostic_contract(
        pair_fdr_alpha = 0.07,
        global_fwer_alpha = 0.08,
    )
    contract = _ld1b_calibration_contract(
        diagnostic_contract;
        candidate_pair_raw_alpha = 0.01,
        candidate_pair_bh_alpha = 0.02,
        candidate_family_alpha = 0.03,
        candidate_global_alpha = 0.04,
    )

    @test contract.schema ==
        "bayesianmgmfrm.local_dependence_calibration_contract.v1"
    @test contract.object === :local_dependence_calibration_contract
    @test contract.profile === :ld1b0_protocol_v1
    @test contract.status === :protocol_preflight_only
    @test contract.diagnostic_contract == diagnostic_contract
    @test contract.candidate_thresholds.pair_raw_alpha == 0.01
    @test contract.candidate_thresholds.pair_bh_alpha == 0.02
    @test contract.candidate_thresholds.family_maximum_alpha == 0.03
    @test contract.candidate_thresholds.global_maximum_alpha == 0.04
    @test contract.candidate_thresholds.comparison ===
        :less_than_or_equal_to
    @test contract.monte_carlo_interval.method === :wilson_score
    @test contract.monte_carlo_interval.confidence == 0.95
    @test contract.monte_carlo_interval.applies_to ===
        :replication_level_binary_rates_only
    @test contract.seed_contract.mutable_default_rng_used === false
    @test contract.seed_contract.cross_julia_bitwise_portability_claimed ===
        false
    for field in (
            :target_evidence_available,
            :pair_truth_oracle_available,
            :pairwise_power_available,
            :repeated_calibration_completed,
            :calibration_evidence_available,
            :diagnostic_decision_labels_available,
            :mechanism_interpretation_eligible,
        )
        @test getproperty(contract, field) === false
    end
    @test !hasproperty(contract, :public_claim_release_allowed)

    @test_throws ArgumentError local_dependence_calibration_contract(
        profile = :other)
    for keyword in (
            :candidate_pair_raw_alpha,
            :candidate_pair_bh_alpha,
            :candidate_family_alpha,
            :candidate_global_alpha,
        ), value in (0.0, 1.0, NaN, Inf)
        arguments = NamedTuple{(keyword,)}((value,))
        @test_throws ArgumentError local_dependence_calibration_contract(;
            diagnostic_contract,
            arguments...,
        )
    end
    @test_throws ArgumentError local_dependence_calibration_contract(
        diagnostic_contract = merge(
            diagnostic_contract,
            (; status = :calibrated),
        ),
    )
    plan = _ld1b_plan_row(:null_same_rater)
    @test_throws ArgumentError local_dependence_calibration_row(
        plan;
        contract = merge(contract, (; status = :calibration_complete)),
        status = :generation_failed,
        failure_code = :fixture,
    )
end

@testset "LD1b completed MFRM diagnostic integration" begin
    plan = _ld1b_plan_row(:null_same_rater)
    diagnostic_contract = _ld1b_diagnostic_contract()
    contract = _ld1b_calibration_contract(diagnostic_contract)
    fixture = _ld1b_cached_integration(plan; diagnostic_contract)
    result = local_dependence_calibration_row(
        plan;
        contract,
        simulation = fixture.simulation,
        diagnostic = fixture.diagnostic,
    )
    repeated = local_dependence_calibration_row(
        plan;
        contract,
        simulation = fixture.simulation,
        diagnostic = fixture.diagnostic,
    )

    @test fixture.fit isa MFRMFit
    @test fixture.diagnostic.schema ==
        "bayesianmgmfrm.local_dependence_summary.v1"
    @test fixture.diagnostic.profile === :custom_unvalidated
    @test fixture.diagnostic.contract == diagnostic_contract
    @test result.schema ==
        "bayesianmgmfrm.local_dependence_calibration_row.v1"
    @test result.object === :local_dependence_calibration_row
    @test result.status === :completed
    @test result.protocol_status === :protocol_preflight_only
    @test result.planning_profile === :ld1_preflight_v1
    @test result.simulation_provenance.data_signature ==
        fixture.simulation.data_signature
    @test result.simulation_provenance.score_signature ==
        fixture.simulation.score_signature
    @test result.simulation_provenance.requested_targets_eligible
    @test result.diagnostic_provenance.data_signature ==
        fixture.diagnostic.data_signature
    @test result.diagnostic_provenance.n_draws == 4
    @test result.n_pair_evidence == length(fixture.diagnostic.pair_rows)
    @test length(result.family_evidence) == 3
    @test !ismissing(result.global_evidence)
    @test result.truth.complete_null
    @test result.truth.active_mechanisms == ()
    @test result.truth.target_truth_class === :complete_null
    @test result.execution_seeds == repeated.execution_seeds
    @test length(unique((
        result.execution_seeds.fit,
        result.execution_seeds.draw_selection,
        result.execution_seeds.posterior_predictive,
    ))) == 3
    @test result.target_evidence === missing
    for field in (
            :target_evidence_available,
            :pair_truth_oracle_available,
            :pairwise_power_available,
            :repeated_calibration_completed,
            :calibration_evidence_available,
            :diagnostic_decision_labels_available,
            :mechanism_interpretation_eligible,
        )
        @test getproperty(result, field) === false
    end
    @test !hasproperty(result, :public_claim_release_allowed)

    other_plan = _ld1b_plan_row(:scalar_testlet_small)
    @test other_plan.seed == plan.seed
    other_result = local_dependence_calibration_row(
        other_plan;
        contract,
        status = :generation_failed,
        failure_code = :fixture_not_run,
    )
    @test other_result.execution_seeds != result.execution_seeds

    summary = local_dependence_calibration_summary(
        [plan],
        [result];
        contract,
    )
    @test summary.schema ==
        "bayesianmgmfrm.local_dependence_calibration_summary.v1"
    @test summary.object === :local_dependence_calibration_summary
    @test summary.status === :protocol_preflight_only
    @test summary.n_plan_rows == 1
    @test summary.n_result_rows == 1
    @test summary.n_missing_result_rows == 0
    @test summary.n_pair_evidence_rows == result.n_pair_evidence
    @test summary.planning_profile === :ld1_preflight_v1
    @test summary.base_seed == plan.base_seed
    @test summary.pairwise_power_available === false
    @test summary.calibration_evidence_available === false
    @test summary.diagnostic_decision_labels_available === false
    @test summary.mechanism_interpretation_eligible === false
    @test !hasproperty(summary, :public_claim_release_allowed)
end

@testset "LD1b complete-null and alternative truth remain separate" begin
    contract = _ld1b_calibration_contract()
    scenario_ids = (
        :scalar_testlet_exact_zero,
        :scalar_testlet_small,
        :rater_response_halo_crossed,
        :scalar_testlet_plus_sequence,
    )
    plans = [_ld1b_plan_row(scenario_id) for scenario_id in scenario_ids]
    results = [local_dependence_calibration_row(
        plan;
        contract,
        status = :generation_failed,
        failure_code = :truth_routing_fixture,
    ) for plan in plans]
    by_id = Dict(result.scenario_id => result for result in results)

    exact_zero = by_id[:scalar_testlet_exact_zero].truth
    @test exact_zero.generating_mechanism === :person_testlet
    @test exact_zero.active_mechanisms == ()
    @test exact_zero.complete_null
    @test exact_zero.target_standard_deviation == 0.0
    @test exact_zero.target_truth_class === :complete_null

    target = by_id[:scalar_testlet_small].truth
    @test target.active_mechanisms == (:person_testlet,)
    @test !target.complete_null
    @test target.target_standard_deviation > 0
    @test target.target_truth_class === :target_only

    competing = by_id[:rater_response_halo_crossed].truth
    @test competing.active_mechanisms == (:rater_response_halo,)
    @test !competing.complete_null
    @test competing.target_standard_deviation == 0.0
    @test competing.target_truth_class === :competing_mechanism_only

    combined = by_id[:scalar_testlet_plus_sequence].truth
    @test combined.active_mechanisms ==
        (:person_testlet, :severity_drift)
    @test combined.target_truth_class === :target_plus_competing_mechanism
    @test all(result -> !result.truth.pair_truth_oracle_available &&
        !result.truth.pairwise_power_available, results)

    summary = local_dependence_calibration_summary(
        plans,
        results;
        contract,
    )
    @test _ld1b_global_row(
        summary, :scalar_testlet_exact_zero).role ===
            :complete_null_fwer_reference
    for scenario_id in scenario_ids[2:end]
        @test _ld1b_global_row(summary, scenario_id).role ===
            :alternative_detection_reference
    end
end

@testset "LD1b inclusive alpha, BH ties, and missing support" begin
    plan = _ld1b_plan_row(:null_same_rater)
    diagnostic_contract = _ld1b_diagnostic_contract()
    contract = _ld1b_calibration_contract(
        diagnostic_contract;
        candidate_pair_raw_alpha = 0.05,
        candidate_pair_bh_alpha = 0.05,
        candidate_family_alpha = 0.05,
        candidate_global_alpha = 0.05,
    )
    fixture = _ld1b_cached_integration(plan; diagnostic_contract)

    exact_diagnostic = _ld1b_diagnostic_evidence(
        fixture.diagnostic;
        pair_raw = 0.05,
        pair_bh = 0.05,
        family_tail = 0.05,
        global_tail = 0.05,
    )
    exact = local_dependence_calibration_row(
        plan;
        contract,
        simulation = fixture.simulation,
        diagnostic = exact_diagnostic,
    )
    @test all(pair -> pair.eligible &&
        pair.candidate_raw_declared === true &&
        pair.candidate_bh_declared === true, exact.pair_evidence)
    applicable_families = filter(row -> row.applicable, exact.family_evidence)
    @test !isempty(applicable_families)
    pair_supported_families = filter(
        row -> row.n_eligible_pairs > 0,
        applicable_families,
    )
    @test all(row -> row.any_raw_declared === true &&
        row.any_bh_declared === true &&
        row.candidate_family_declared === true, pair_supported_families)
    @test all(row -> row.candidate_family_declared === true,
        applicable_families)
    @test exact.global_evidence.candidate_global_declared === true

    above = nextfloat(0.05)
    above_diagnostic = _ld1b_diagnostic_evidence(
        fixture.diagnostic;
        pair_raw = above,
        pair_bh = above,
        family_tail = above,
        global_tail = above,
    )
    above_result = local_dependence_calibration_row(
        plan;
        contract,
        simulation = fixture.simulation,
        diagnostic = above_diagnostic,
    )
    @test all(pair -> pair.candidate_raw_declared === false &&
        pair.candidate_bh_declared === false, above_result.pair_evidence)
    @test all(row -> !row.applicable ||
        row.candidate_family_declared === false,
        above_result.family_evidence)
    @test above_result.global_evidence.candidate_global_declared === false

    reversed_diagnostic = _ld1b_diagnostic_evidence(
        fixture.diagnostic;
        pair_raw = 0.05,
        pair_bh = 0.05,
        family_tail = 0.05,
        global_tail = 0.05,
        reverse_pairs = true,
    )
    reversed = local_dependence_calibration_row(
        plan;
        contract,
        simulation = fixture.simulation,
        diagnostic = reversed_diagnostic,
    )
    pair_identity = row ->
        (row.family, row.testlet_id, row.left, row.right)
    @test Set(pair_identity(row) for row in exact.pair_evidence) ==
        Set(pair_identity(row) for row in reversed.pair_evidence)
    @test all(row -> row.candidate_bh_declared === true,
        reversed.pair_evidence)
    exact_summary = local_dependence_calibration_summary(
        [plan], [exact]; contract)
    reversed_summary = local_dependence_calibration_summary(
        [plan], [reversed]; contract)
    @test exact_summary.scenario_rows == reversed_summary.scenario_rows
    @test isequal(exact_summary.family_rows, reversed_summary.family_rows)
    @test exact_summary.global_rows == reversed_summary.global_rows

    success_rate = only(exact_summary.scenario_rows).global_maximum.rate
    @test success_rate.successes == 1
    @test success_rate.trials == 1
    @test success_rate.estimate == 1.0
    @test 0.0 < success_rate.lower < 1.0
    @test success_rate.upper == 1.0
    failure_summary = local_dependence_calibration_summary(
        [plan], [above_result]; contract)
    failure_rate = only(failure_summary.scenario_rows).global_maximum.rate
    @test failure_rate.successes == 0
    @test failure_rate.trials == 1
    @test failure_rate.estimate == 0.0
    @test failure_rate.lower == 0.0
    @test 0.0 < failure_rate.upper < 1.0

    missing_diagnostic = _ld1b_diagnostic_evidence(
        fixture.diagnostic;
        pair_raw = missing,
        pair_bh = missing,
        pair_status = :sparse,
        family_tail = missing,
        global_tail = missing,
    )
    missing_result = local_dependence_calibration_row(
        plan;
        contract,
        simulation = fixture.simulation,
        diagnostic = missing_diagnostic,
    )
    @test all(pair -> !pair.eligible &&
        ismissing(pair.candidate_raw_declared) &&
        ismissing(pair.candidate_bh_declared), missing_result.pair_evidence)
    @test all(row -> ismissing(row.any_raw_declared) &&
        ismissing(row.any_bh_declared) &&
        ismissing(row.candidate_family_declared),
        filter(row -> row.applicable, missing_result.family_evidence))
    @test !missing_result.global_evidence.evaluable
    @test ismissing(missing_result.global_evidence.candidate_global_declared)
    missing_summary = local_dependence_calibration_summary(
        [plan], [missing_result]; contract)
    missing_block = only(missing_summary.scenario_rows).pair_raw_any
    @test missing_block.n_planned == 1
    @test missing_block.n_resolved == 0
    @test missing_block.n_unresolved == 1
    @test missing_block.rate.trials == 0
    @test ismissing(missing_block.rate.estimate)
    @test ismissing(missing_block.rate.lower)
    @test ismissing(missing_block.rate.upper)
    @test missing_block.unresolved_bounds == (lower = 0.0, upper = 1.0)
    @test only(missing_summary.scenario_rows).pooled_pair_raw.n_pairs == 0
end

@testset "LD1b expected rejection and failure accounting" begin
    contract = _ld1b_calibration_contract()
    rejection_ids = (
        :scalar_testlet_one_indicator_rejection,
        :scalar_testlet_one_testlet_per_person_rejection,
        :scalar_testlet_disconnected_rejection,
        :rater_task_nested_rejection,
    )
    rejection_plans = [_ld1b_plan_row(id) for id in rejection_ids]
    rejection_results = map(rejection_plans) do plan
        @test !plan.expected_requested_targets_eligible
        simulation = simulate_local_dependence(plan)
        @test !simulation.design_support.requested_targets_eligible
        result = local_dependence_calibration_row(
            plan;
            contract,
            status = :pre_fit_rejected,
            simulation,
        )
        @test result.status === :pre_fit_rejected
        @test result.expected_structural_eligibility === false
        @test !ismissing(result.simulation_provenance)
        @test result.simulation_provenance.requested_targets_eligible === false
        if plan.scenario_id ===
                :scalar_testlet_one_testlet_per_person_rejection
            @test plan.n_raters == 2
            @test length(simulation.truth.rater_labels) == 2
            @test simulation.summary.n_raters == 1
            @test result.planning_shape.n_raters == 2
            @test result.simulation_provenance.planning_shape.n_raters == 2
            @test result.simulation_provenance.
                observed_shape.n_raters == 1
        end
        @test result.diagnostic_provenance === missing
        @test isempty(result.pair_evidence)
        @test isempty(result.family_evidence)
        @test result.global_evidence === missing
        result
    end
    rejection_summary = local_dependence_calibration_summary(
        rejection_plans,
        rejection_results;
        contract,
    )
    @test _ld1b_status_count(
        rejection_summary, :pre_fit_rejected) == 4
    @test _ld1b_status_count(rejection_summary, :completed) == 0
    @test all(row -> row.n_pre_fit_rejected == 1 &&
        row.n_completed == 0, rejection_summary.scenario_rows)
    @test only(rejection_summary.matched_set_rows).
        n_fully_resolved_replications == 1

    eligible_plan = _ld1b_plan_row(:null_same_rater)
    eligible_simulation = simulate_local_dependence(eligible_plan)
    rejected_plan = first(rejection_plans)
    rejected_simulation = simulate_local_dependence(rejected_plan)
    @test_throws ArgumentError local_dependence_calibration_row(
        eligible_plan;
        contract,
        status = :pre_fit_rejected,
        simulation = eligible_simulation,
    )
    @test_throws ArgumentError local_dependence_calibration_row(
        rejected_plan;
        contract,
        status = :completed,
        simulation = rejected_simulation,
        diagnostic = nothing,
    )
    @test_throws ArgumentError local_dependence_calibration_row(
        rejected_plan;
        contract,
        status = :fit_failed,
        simulation = rejected_simulation,
        failure_code = :should_not_fit,
    )
    @test_throws ArgumentError local_dependence_calibration_row(
        eligible_plan;
        contract,
        status = :other,
    )

    failure_plans = [_ld1b_plan_row(
        :null_same_rater;
        replication,
    ) for replication in 1:4]
    fit_simulation = simulate_local_dependence(failure_plans[2])
    diagnostic_simulation = simulate_local_dependence(failure_plans[3])
    failure_results = [
        local_dependence_calibration_row(
            failure_plans[1];
            contract,
            status = :generation_failed,
            failure_code = :generator_exception,
        ),
        local_dependence_calibration_row(
            failure_plans[2];
            contract,
            status = :fit_failed,
            simulation = fit_simulation,
            failure_code = :sampler_exception,
        ),
        local_dependence_calibration_row(
            failure_plans[3];
            contract,
            status = :diagnostic_failed,
            simulation = diagnostic_simulation,
            failure_code = :diagnostic_exception,
        ),
    ]
    failure_summary = local_dependence_calibration_summary(
        failure_plans,
        failure_results;
        contract,
    )
    @test failure_summary.n_missing_result_rows == 1
    @test _ld1b_status_count(failure_summary, :generation_failed) == 1
    @test _ld1b_status_count(failure_summary, :fit_failed) == 1
    @test _ld1b_status_count(failure_summary, :diagnostic_failed) == 1
    failure_scenario = only(failure_summary.scenario_rows)
    @test failure_scenario.n_planned == 4
    @test failure_scenario.n_results == 3
    @test failure_scenario.n_missing_results == 1
    @test failure_scenario.n_generation_failed == 1
    @test failure_scenario.n_fit_failed == 1
    @test failure_scenario.n_diagnostic_failed == 1
    @test failure_scenario.global_maximum.n_resolved == 0
    @test failure_scenario.global_maximum.n_unresolved == 4
    @test failure_scenario.global_maximum.unresolved_bounds ==
        (lower = 0.0, upper = 1.0)
    @test only(failure_summary.matched_set_rows).
        n_incomplete_replications == 4

    @test_throws ArgumentError local_dependence_calibration_row(
        failure_plans[1];
        contract,
        status = :generation_failed,
    )
    @test_throws ArgumentError local_dependence_calibration_row(
        failure_plans[1];
        contract,
        status = :generation_failed,
        simulation = eligible_simulation,
        failure_code = :invalid_evidence,
    )
    @test_throws ArgumentError local_dependence_calibration_row(
        failure_plans[2];
        contract,
        status = :fit_failed,
        simulation = fit_simulation,
        failure_code = "not-a-symbol",
    )
end

@testset "LD1b replication weighting and input permutation" begin
    diagnostic_contract = _ld1b_diagnostic_contract()
    contract = _ld1b_calibration_contract(diagnostic_contract)
    plans = [_ld1b_plan_row(
        :null_same_rater;
        replication,
    ) for replication in 1:3]
    first_fixture = _ld1b_cached_integration(
        plans[1]; diagnostic_contract)
    second_fixture = _ld1b_cached_integration(
        plans[2]; diagnostic_contract, diagnostic_seed = 7302)
    first_diagnostic = _ld1b_diagnostic_evidence(
        first_fixture.diagnostic;
        n_pairs = 1,
        pair_raw = 0.05,
        pair_bh = 0.05,
        family_tail = 1.0,
        global_tail = 0.05,
    )
    second_diagnostic = _ld1b_diagnostic_evidence(
        second_fixture.diagnostic;
        pair_raw = 1.0,
        pair_bh = 1.0,
        family_tail = 1.0,
        global_tail = 1.0,
    )
    results = [
        local_dependence_calibration_row(
            plans[1];
            contract,
            simulation = first_fixture.simulation,
            diagnostic = first_diagnostic,
        ),
        local_dependence_calibration_row(
            plans[2];
            contract,
            simulation = second_fixture.simulation,
            diagnostic = second_diagnostic,
        ),
    ]
    summary = local_dependence_calibration_summary(
        plans,
        results;
        contract,
    )
    scenario = only(summary.scenario_rows)
    second_pair_count = length(second_diagnostic.pair_rows)
    @test scenario.pair_raw_any.n_planned == 3
    @test scenario.pair_raw_any.n_resolved == 2
    @test scenario.pair_raw_any.n_unresolved == 1
    @test scenario.pair_raw_any.rate.successes == 1
    @test scenario.pair_raw_any.rate.trials == 2
    @test scenario.pair_raw_any.rate.estimate == 0.5
    @test scenario.pair_raw_any.rate.lower ≈
        1 - scenario.pair_raw_any.rate.upper
    @test scenario.pair_raw_any.unresolved_bounds ==
        (lower = 1 / 3, upper = 2 / 3)
    @test scenario.pooled_pair_raw.n_pairs == 1 + second_pair_count
    @test scenario.pooled_pair_raw.n_declared == 1
    @test scenario.pooled_pair_raw.rate == 1 / (1 + second_pair_count)
    @test scenario.pooled_pair_raw.equal_replication_weight_mean_rate == 0.5
    @test scenario.pooled_pair_raw.rate !=
        scenario.pooled_pair_raw.equal_replication_weight_mean_rate
    @test !scenario.pooled_pair_raw.wilson_interval_available
    @test scenario.pooled_pair_bh.rate == scenario.pooled_pair_raw.rate
    @test !scenario.pairwise_power_available

    single_family = only(row for row in summary.family_rows
        if row.family === :single_rating_item_q3)
    @test single_family.pooled_pair_raw_rate == 1 / 5
    @test single_family.equal_replication_weight_mean_raw_rate == 0.5
    @test single_family.pooled_pair_raw_rate !=
        single_family.equal_replication_weight_mean_raw_rate
    @test !single_family.pooled_pair_wilson_interval_available
    @test !single_family.pairwise_power_available

    reversed = local_dependence_calibration_summary(
        reverse(plans),
        reverse(results);
        contract,
    )
    @test isequal(summary, reversed)
end

@testset "LD1b provenance, duplicates, and protocol mixing" begin
    plan = _ld1b_plan_row(:null_same_rater)
    diagnostic_contract = _ld1b_diagnostic_contract()
    contract = _ld1b_calibration_contract(diagnostic_contract)
    fixture = _ld1b_cached_integration(plan; diagnostic_contract)
    diagnostic = _ld1b_diagnostic_evidence(
        fixture.diagnostic;
        pair_raw = 0.05,
        pair_bh = 0.05,
        family_tail = 0.05,
        global_tail = 0.05,
    )
    result = local_dependence_calibration_row(
        plan;
        contract,
        simulation = fixture.simulation,
        diagnostic,
    )

    other_plan = _ld1b_plan_row(:scalar_testlet_small)
    other_simulation = simulate_local_dependence(other_plan)
    @test_throws ArgumentError local_dependence_calibration_row(
        plan;
        contract,
        simulation = other_simulation,
        diagnostic,
    )
    dimension_plans = NamedTuple[]
    for (n_persons, n_raters) in ((9, 2), (8, 3))
        grid = local_dependence_simulation_grid(
            repetitions = 1,
            base_seed = plan.base_seed,
            phase = plan.phase,
            grid_id = plan.grid_id,
            n_persons = n_persons,
            n_testlets = plan.n_testlets,
            items_per_testlet = plan.items_per_testlet,
            n_raters = n_raters,
            n_categories = plan.n_categories,
        )
        push!(dimension_plans, only(row for row in grid
            if row.scenario_id === plan.scenario_id))
    end
    for dimension_plan in dimension_plans
        @test dimension_plan.scenario_id === plan.scenario_id
        @test dimension_plan.grid_id == plan.grid_id
        @test dimension_plan.base_seed == plan.base_seed
        @test dimension_plan.seed == plan.seed
        mismatched_simulation = simulate_local_dependence(dimension_plan)
        @test_throws ArgumentError local_dependence_calibration_row(
            plan;
            contract,
            simulation = mismatched_simulation,
            diagnostic,
        )
    end
    for forged_simulation in (
            merge(fixture.simulation, (; seed = fixture.simulation.seed + 1)),
            merge(fixture.simulation, (;
                truth = merge(fixture.simulation.truth, (;
                    active_mechanisms = (:person_testlet,),
                )),
            )),
            merge(fixture.simulation, (;
                design_support = merge(fixture.simulation.design_support, (;
                    requested_targets_eligible = false,
                )),
            )),
        )
        @test_throws ArgumentError local_dependence_calibration_row(
            plan;
            contract,
            simulation = forged_simulation,
            diagnostic,
        )
    end

    other_diagnostic_contract = _ld1b_diagnostic_contract(
        pair_fdr_alpha = 0.06)
    other_protocol = _ld1b_calibration_contract(other_diagnostic_contract)
    @test_throws ArgumentError local_dependence_calibration_row(
        plan;
        contract = other_protocol,
        simulation = fixture.simulation,
        diagnostic,
    )
    for forged_diagnostic in (
            merge(diagnostic, (; data_signature = "forged")),
            merge(diagnostic, (; design_signature = "forged")),
            merge(diagnostic, (;
                observed_score_signature = merge(
                    diagnostic.observed_score_signature,
                    (; value = "forged"),
                ),
            )),
            merge(diagnostic, (; decision_labels_available = true)),
            merge(diagnostic, (; decision = true)),
        )
        @test_throws ArgumentError local_dependence_calibration_row(
            plan;
            contract,
            simulation = fixture.simulation,
            diagnostic = forged_diagnostic,
        )
    end
    duplicate_pairs = (diagnostic.pair_rows..., first(diagnostic.pair_rows))
    duplicate_diagnostic = merge(diagnostic, (;
        n_pair_rows = length(duplicate_pairs),
        pair_rows = duplicate_pairs,
    ))
    @test_throws ArgumentError local_dependence_calibration_row(
        plan;
        contract,
        simulation = fixture.simulation,
        diagnostic = duplicate_diagnostic,
    )

    @test_throws ArgumentError local_dependence_calibration_summary(
        [plan, plan], [result]; contract)
    @test_throws ArgumentError local_dependence_calibration_summary(
        [plan], [result, result]; contract)
    @test_throws ArgumentError local_dependence_calibration_summary(
        [plan], [local_dependence_calibration_row(
            other_plan;
            contract,
            status = :generation_failed,
            failure_code = :unmatched,
        )]; contract)

    smoke_plan = _ld1b_plan_row(:null_same_rater; phase = :smoke)
    other_grid_plan = _ld1b_plan_row(
        :scalar_testlet_small;
        grid_id = "ld1b-other-grid",
    )
    other_seed_plan = _ld1b_plan_row(
        :scalar_testlet_small;
        base_seed = plan.base_seed + 1,
    )
    @test_throws ArgumentError local_dependence_calibration_summary(
        [plan, smoke_plan], NamedTuple[]; contract)
    @test_throws ArgumentError local_dependence_calibration_summary(
        [plan, other_grid_plan], NamedTuple[]; contract)
    @test_throws ArgumentError local_dependence_calibration_summary(
        [plan, other_seed_plan], NamedTuple[]; contract)

    other_calibration_contract = _ld1b_calibration_contract(
        diagnostic_contract;
        candidate_pair_raw_alpha = 0.04,
    )
    other_contract_result = local_dependence_calibration_row(
        plan;
        contract = other_calibration_contract,
        simulation = fixture.simulation,
        diagnostic,
    )
    @test_throws ArgumentError local_dependence_calibration_summary(
        [plan], [other_contract_result]; contract)

    forged_result_rows = NamedTuple[]
    push!(forged_result_rows, merge(result, (; seed = result.seed + 1)))
    push!(forged_result_rows, merge(result, (;
        truth = merge(result.truth, (; complete_null = false)),
    )))
    push!(forged_result_rows, merge(result, (;
        execution_seeds = merge(
            result.execution_seeds,
            (; fit = result.execution_seeds.fit + 1),
        ),
    )))
    push!(forged_result_rows, merge(result, (; simulation_provenance = missing)))
    push!(forged_result_rows, merge(result, (; diagnostic_provenance = missing)))
    push!(forged_result_rows, merge(result, (;
        diagnostic_provenance = merge(result.diagnostic_provenance, (;
            observed_score_signature = merge(
                result.diagnostic_provenance.observed_score_signature,
                (; value = "forged"),
            ),
        )),
    )))
    forged_pairs = collect(result.pair_evidence)
    forged_pairs[1] = merge(forged_pairs[1], (;
        candidate_raw_declared = false,
    ))
    push!(forged_result_rows, merge(result, (;
        pair_evidence = Tuple(forged_pairs),
    )))
    for forged_result in forged_result_rows
        @test_throws ArgumentError local_dependence_calibration_summary(
            [plan], [forged_result]; contract)
    end
    incomplete_result = (; (
        name => getproperty(result, name)
        for name in propertynames(result)
        if name !== :simulation_provenance
    )...)
    @test_throws ArgumentError local_dependence_calibration_summary(
        [plan], [incomplete_result]; contract)
end

@testset "LD1b row and summary resource guards" begin
    plan = _ld1b_plan_row(:null_same_rater)
    diagnostic_contract = _ld1b_diagnostic_contract()
    contract = _ld1b_calibration_contract(diagnostic_contract)
    fixture = _ld1b_cached_integration(plan; diagnostic_contract)
    n_pairs = length(fixture.diagnostic.pair_rows)

    @test_throws ArgumentError local_dependence_calibration_row(
        plan;
        contract,
        simulation = fixture.simulation,
        diagnostic = fixture.diagnostic,
        max_pair_rows = 0,
    )
    @test_throws ArgumentError local_dependence_calibration_row(
        plan;
        contract,
        simulation = fixture.simulation,
        diagnostic = fixture.diagnostic,
        max_pair_rows = n_pairs - 1,
    )
    exact = local_dependence_calibration_row(
        plan;
        contract,
        simulation = fixture.simulation,
        diagnostic = fixture.diagnostic,
        max_pair_rows = n_pairs,
    )
    @test exact.n_pair_evidence == n_pairs

    exact_summary = local_dependence_calibration_summary(
        [plan],
        [exact];
        contract,
        max_plan_rows = 1,
        max_result_rows = 1,
        max_pair_rows = n_pairs,
        max_group_rows = 6,
    )
    @test exact_summary.n_plan_rows == 1
    @test exact_summary.n_result_rows == 1
    @test exact_summary.n_pair_evidence_rows == n_pairs
    @test length(exact_summary.scenario_rows) +
        length(exact_summary.family_rows) +
        length(exact_summary.global_rows) +
        length(exact_summary.matched_set_rows) == 6

    for keyword in (
            :max_plan_rows,
            :max_result_rows,
            :max_pair_rows,
            :max_group_rows,
        )
        arguments = NamedTuple{(keyword,)}((0,))
        @test_throws ArgumentError local_dependence_calibration_summary(
            [plan], [exact]; contract, arguments...)
    end
    @test_throws ArgumentError local_dependence_calibration_summary(
        NamedTuple[], NamedTuple[]; contract)
    @test_throws ArgumentError local_dependence_calibration_summary(
        [plan], [exact]; contract, max_pair_rows = n_pairs - 1)
    @test_throws ArgumentError local_dependence_calibration_summary(
        [plan], [exact]; contract, max_group_rows = 5)

    other_plan = _ld1b_plan_row(:scalar_testlet_small)
    other_result = local_dependence_calibration_row(
        other_plan;
        contract,
        status = :generation_failed,
        failure_code = :fixture,
    )
    @test_throws ArgumentError local_dependence_calibration_summary(
        [plan, other_plan], [exact]; contract, max_plan_rows = 1)
    @test_throws ArgumentError local_dependence_calibration_summary(
        [plan, other_plan], [exact, other_result];
        contract,
        max_result_rows = 1,
    )
end
