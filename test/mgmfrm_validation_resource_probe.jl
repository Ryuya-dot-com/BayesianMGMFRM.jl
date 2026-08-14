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
    @test measured.runtime.process_lifetime_maxrss_bytes >= 0
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

@testset "MGMFRM short-NUTS resource probe" begin
    planned = mgmfrm_validation_short_nuts_resource_probe()
    @test planned.schema ==
        "bayesianmgmfrm.mgmfrm_validation_short_nuts_resource_probe.v1"
    @test planned.object ===
        :mgmfrm_validation_short_nuts_resource_probe
    @test planned.status ===
        :short_nuts_resource_probe_planned_not_executed
    @test !planned.execute_measurement
    @test !planned.execution_started
    @test planned.mcmc_execution_state === :not_started
    @test !planned.mcmc_executed
    @test isempty(planned.fit_attempt_rows)
    @test planned.summary.n_planned_cells == 1
    @test planned.summary.n_started == 0
    @test planned.summary.denominator_preserved
    @test !planned.convergence_assessed
    @test !planned.scientific_execution_authorized
    @test !planned.recovery_evidence_available
    @test !planned.fit_objects_returned
    @test !planned.final_resource_policy_frozen
    @test :explicit_execution_not_requested in planned.blockers

    policy = planned.policy
    @test policy.profile === :short_nuts_resource_probe
    @test policy.controls.warmup == 25
    @test policy.controls.ndraws == 25
    @test policy.controls.chains == 1
    @test policy.controls.metric === :diagonal
    @test policy.default_design === :connected_sparse_systematic_link
    @test policy.maximum_cells == 1
    @test policy.default_minimum_free_memory_bytes == 2 * 1024^3
    @test policy.hard_minimum_free_memory_bytes == 1024^3
    @test !policy.convergence_assessed
    @test !policy.peak_memory_measured
    @test policy.maxrss_measurement ===
        :process_lifetime_before_and_after
    @test !policy.maxrss_is_probe_attributable
    @test policy.isolated_process_required_for_peak_attribution
    @test :full_nuts_runtime_extrapolation in policy.prohibited_uses

    sparse_plan = mgmfrm_response_stress_plan(
        design_strata = (:connected_sparse_systematic_link,),
        response_patterns = (:regular_all_categories,),
        base_seed = 20260817,
    )
    runner_calls = Ref(0)
    forbidden_runner = (plan, truth_scale) -> begin
        runner_calls[] += 1
        error("runner must not be called")
    end
    memory_rejected =
        BayesianMGMFRM._mgmfrm_validation_short_nuts_resource_probe(
            sparse_plan;
            execute_measurement = true,
            minimum_free_memory_bytes = 2 * 1024^3,
            maximum_observations_per_cell = 1_000,
            truth_scale = 0.15,
            free_memory_provider = () -> Int64(512 * 1024^2),
            runner_executor = forbidden_runner,
        )
    @test memory_rejected.status ===
        :short_nuts_resource_probe_memory_preflight_rejected
    @test !memory_rejected.execution_started
    @test !memory_rejected.mcmc_executed
    @test :insufficient_free_memory in memory_rejected.blockers
    @test runner_calls[] == 0

    fake_runner = (plan, truth_scale) -> (;
        controls = policy.controls,
        rows = ((;
            terminal_status = :completed,
            fit_seconds = 1.0,
            diagnostic_seconds = 0.1,
        ),),
        summary = (;
            n_attempts = 1,
            n_terminal_attempts = 1,
            n_completed = 1,
        ),
    )
    free_values = Int64[4 * 1024^3, 3 * 1024^3]
    maxrss_values = Int64[200_000_000, 250_000_000]
    completed =
        BayesianMGMFRM._mgmfrm_validation_short_nuts_resource_probe(
            sparse_plan;
            execute_measurement = true,
            minimum_free_memory_bytes = 2 * 1024^3,
            maximum_observations_per_cell = 1_000,
            truth_scale = 0.15,
            free_memory_provider = () -> popfirst!(free_values),
            maxrss_provider = () -> popfirst!(maxrss_values),
            runner_executor = fake_runner,
        )
    @test completed.status ===
        :short_nuts_resource_probe_complete_operational_metadata_only
    @test completed.execution_started
    @test completed.mcmc_execution_state === :executed
    @test completed.mcmc_executed
    @test completed.summary.n_terminal == 1
    @test completed.summary.n_completed == 1
    @test completed.summary.denominator_preserved
    @test completed.measurement.allocated_bytes >= 0
    @test completed.measurement.minimum_endpoint_free_memory_bytes ==
        3 * 1024^3
    @test !completed.measurement.peak_memory_measured
    @test completed.measurement.process_lifetime_maxrss_bytes_before ==
        200_000_000
    @test completed.measurement.process_lifetime_maxrss_bytes_after ==
        250_000_000
    @test completed.measurement.process_lifetime_maxrss_increased
    @test !completed.measurement.maxrss_is_probe_attributable
    @test !completed.fit_objects_returned
    @test completed.next_gate ===
        :review_scaled_resource_cells_and_peak_memory

    failing_runner = (plan, truth_scale) -> error("injected runner failure")
    failure_memory = Int64[4 * 1024^3, 4 * 1024^3]
    failure_maxrss = Int64[200_000_000, 200_000_000]
    failed = BayesianMGMFRM._mgmfrm_validation_short_nuts_resource_probe(
        sparse_plan;
        execute_measurement = true,
        minimum_free_memory_bytes = 2 * 1024^3,
        maximum_observations_per_cell = 1_000,
        truth_scale = 0.15,
        free_memory_provider = () -> popfirst!(failure_memory),
        maxrss_provider = () -> popfirst!(failure_maxrss),
        runner_executor = failing_runner,
    )
    @test failed.status === :short_nuts_resource_probe_runner_failed
    @test failed.execution_started
    @test !failed.summary.denominator_preserved
    @test ismissing(failed.mcmc_executed)
    @test failed.error isa ErrorException
    @test occursin("injected runner failure", failed.error_message)
    @test failed.next_gate === :inspect_preserved_runner_failure

    @test_throws ArgumentError mgmfrm_validation_short_nuts_resource_probe(
        minimum_free_memory_bytes = 1024^3 - 1)
    @test_throws ArgumentError mgmfrm_validation_short_nuts_resource_probe(
        maximum_observations_per_cell = 2_001)
    @test_throws ArgumentError mgmfrm_validation_short_nuts_resource_probe(
        truth_scale = 0.0)
    dense_and_sparse = mgmfrm_response_stress_plan(
        design_strata = (
            :dense_fully_crossed,
            :connected_sparse_systematic_link,
        ),
        response_patterns = (:regular_all_categories,),
    )
    @test_throws ArgumentError mgmfrm_validation_short_nuts_resource_probe(
        dense_and_sparse)

    scaled = mgmfrm_validation_scaled_resource_plan()
    @test scaled.schema ==
        "bayesianmgmfrm.mgmfrm_validation_scaled_resource_plan.v1"
    @test scaled.object === :mgmfrm_validation_scaled_resource_plan
    @test scaled.status === :predeclared_not_run
    @test length(scaled.rows) == 4
    @test scaled.expected_observations == (144, 600, 600, 2_000)
    @test length(unique(row.attempt_id for row in scaled.rows)) == 4
    @test all(row -> row.object ===
        :mgmfrm_response_stress_plan_row, scaled.rows)
    @test all(row -> row.response_pattern ===
        :regular_all_categories, scaled.rows)
    @test scaled.execution_mode === :one_cell_per_explicit_invocation
    @test !scaled.automatic_progression_allowed
    @test !scaled.final_analysis_grid_selected
    @test !scaled.mcmc_executed
    @test !scaled.primary_evaluation_seed_used
    @test scaled.scientific_decision === :not_applied
    first_scaled = mgmfrm_validation_short_nuts_resource_probe(
        first(scaled.rows))
    @test first_scaled.summary.n_planned_cells == 1
    @test first_scaled.plan[1].attempt_id ===
        :scaled_resource_01_dense_small
    @test_throws ArgumentError mgmfrm_validation_short_nuts_resource_probe(
        scaled.rows)
end
