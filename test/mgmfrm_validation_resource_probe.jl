using Test
using Statistics
using BayesianMGMFRM

function _fake_mgmfrm_resource_measurement(case, repetitions, policy)
    dimension = length(case.raw_truth)
    rows = Tuple((;
        repetition,
        elapsed_seconds = 0.01 * repetition,
        allocated_bytes = 1024 * repetition,
        gc_seconds = 0.0,
        gc_time_fraction = 0.0,
        logdensity = -10.0,
        gradient_length = dimension,
        maximum_absolute_gradient = 1.0,
    ) for repetition in 1:repetitions)
    return (;
        initial_parameter_dimension = dimension,
        adapter_setup_seconds = 0.02,
        adapter_setup_allocated_bytes = 2048,
        adapter_validation_evaluations =
            policy.adapter_validation_evaluations,
        warmup_evaluations = policy.warmup_evaluations,
        timed_evaluations = repetitions,
        free_memory_bytes_before = Int64(8_000_000),
        free_memory_bytes_after = Int64(7_500_000),
        minimum_free_memory_bytes_observed = Int64(7_500_000),
        timed_rows = rows,
        median_gradient_seconds = median(
            row.elapsed_seconds for row in rows),
        median_allocated_bytes = median(
            row.allocated_bytes for row in rows),
        median_gc_time_fraction = 0.0,
    )
end

@testset "MGMFRM validation resource probe" begin
    planned = mgmfrm_validation_resource_probe()
    @test planned.schema ==
        "bayesianmgmfrm.mgmfrm_validation_resource_probe.v1"
    @test planned.object === :mgmfrm_validation_resource_probe
    @test planned.status ===
        :resource_probe_planned_measurement_not_executed
    @test !planned.execute_measurement
    @test planned.summary.n_planned_cells == 2
    @test planned.summary.n_terminal_cells == 0
    @test planned.summary.denominator_preserved
    @test all(row -> row.status === :planned_not_measured, planned.rows)
    @test all(row -> !row.terminal, planned.rows)
    @test ismissing(planned.runtime)
    @test !planned.mcmc_executed
    @test !planned.fit_objects_returned
    @test !planned.recovery_evidence_available
    @test !planned.scientific_execution_authorized
    @test !planned.primary_evaluation_seed_used
    @test !planned.final_resource_policy_frozen
    @test planned.next_gate === :execute_initial_gradient_resource_probe

    policy = planned.policy
    @test policy.operation === :forwarddiff_logdensity_and_gradient
    @test policy.default_repetitions == 3
    @test policy.maximum_repetitions == 5
    @test policy.hard_maximum_cells == 4
    @test !policy.mcmc_allowed
    @test !policy.fit_runtime_extrapolation_allowed
    @test !policy.measurement_thresholds_applied
    @test !policy.final_resource_policy_may_be_frozen_from_this_probe_alone
    @test policy.bounded_short_nuts_probe_required_next
    @test :performance_claim in policy.prohibited_uses
    @test :choose_batch_size in policy.permitted_uses

    sparse_plan = mgmfrm_response_stress_plan(
        design_strata = (:connected_sparse_systematic_link,),
        response_patterns = (:regular_all_categories,),
        base_seed = 20260816,
    )
    measured = BayesianMGMFRM._mgmfrm_validation_resource_probe(
        sparse_plan;
        execute_measurement = true,
        repetitions = 3,
        maximum_cells = 1,
        maximum_observations_per_cell = 10_000,
        truth_scale = 0.15,
        measurement_executor = _fake_mgmfrm_resource_measurement,
    )
    @test measured.status ===
        :runtime_probe_complete_operational_metadata_only
    @test measured.execute_measurement
    @test measured.summary.n_planned_cells == 1
    @test measured.summary.n_terminal_cells == 1
    @test measured.summary.n_completed == 1
    @test measured.summary.n_failed == 0
    @test measured.summary.denominator_preserved
    @test measured.runtime.n_threads >= 1
    @test measured.runtime.cpu_threads >= 1
    @test !measured.mcmc_executed
    @test !measured.final_resource_policy_frozen
    @test measured.next_gate === :bounded_short_nuts_resource_probe

    row = only(measured.rows)
    @test row.status === :completed
    @test row.terminal
    @test row.expected_observations == 96
    @test row.actual_observations == 96
    @test row.expected_probability_cells == 480
    @test row.measurement.timed_evaluations == 3
    @test length(row.measurement.timed_rows) == 3
    @test row.measurement.initial_parameter_dimension ==
        length(only(mgmfrm_response_stress_preflight(sparse_plan).cases).raw_truth)
    @test ismissing(row.error)

    failing_executor = (case, repetitions, policy) ->
        error("injected gradient failure")
    failed = BayesianMGMFRM._mgmfrm_validation_resource_probe(
        sparse_plan;
        execute_measurement = true,
        repetitions = 1,
        maximum_cells = 1,
        maximum_observations_per_cell = 10_000,
        truth_scale = 0.15,
        measurement_executor = failing_executor,
    )
    failed_row = only(failed.rows)
    @test failed.status === :runtime_probe_complete_with_recorded_failures
    @test failed.summary.n_failed == 1
    @test failed.summary.denominator_preserved
    @test failed_row.status === :gradient_measurement_failed
    @test failed_row.error_phase === :gradient_measurement
    @test failed_row.error isa ErrorException
    @test failed_row.error_type == "ErrorException"
    @test occursin("injected gradient failure", failed_row.error_message)

    malformed_executor = (case, repetitions, policy) -> (; wrong = true)
    malformed = BayesianMGMFRM._mgmfrm_validation_resource_probe(
        sparse_plan;
        execute_measurement = true,
        repetitions = 1,
        maximum_cells = 1,
        maximum_observations_per_cell = 10_000,
        truth_scale = 0.15,
        measurement_executor = malformed_executor,
    )
    @test only(malformed.rows).status === :gradient_measurement_failed
    @test only(malformed.rows).error isa ArgumentError

    @test_throws ArgumentError mgmfrm_validation_resource_probe(
        maximum_cells = 1)
    @test_throws ArgumentError mgmfrm_validation_resource_probe(
        repetitions = 6)
    @test_throws ArgumentError mgmfrm_validation_resource_probe(
        maximum_cells = 5)
    @test_throws ArgumentError mgmfrm_validation_resource_probe(
        maximum_observations_per_cell = 10_001)
    @test_throws ArgumentError mgmfrm_validation_resource_probe(
        maximum_observations_per_cell = 95)
    @test_throws ArgumentError mgmfrm_validation_resource_probe(
        truth_scale = 0.0)

    nonregular = mgmfrm_response_stress_plan(
        design_strata = (:connected_sparse_systematic_link,),
        response_patterns = (:all_maximum_person,),
    )
    @test_throws ArgumentError mgmfrm_validation_resource_probe(
        nonregular; maximum_cells = 1)

    execution = mgmfrm_validation_execution_design_contract()
    @test execution.resource_probe == policy
    @test !execution.resource_probe.mcmc_allowed
end
