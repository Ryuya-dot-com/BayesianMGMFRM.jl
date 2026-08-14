using Test
using BayesianMGMFRM

@testset "bounded MGMFRM fit attempts" begin
    plan = mgmfrm_response_stress_plan(
        design_strata = (:connected_sparse_systematic_link,),
        response_patterns = (:regular_all_categories,),
    )

    fake_fit = (case, backend, prior, controls, fit_seed;
            cmdstan_path, cmdstan_cache_dir) -> (;
        case_id = case.attempt_id,
        backend,
        prior,
        controls,
        fit_seed,
        cmdstan_path,
        cmdstan_cache_dir,
    )
    fake_diagnostics = (fit, controls) -> (;
        diagnostic_status = :integrity_passed_not_convergence_assessed,
        output_integrity_passed = true,
        n_draws = controls.ndraws,
        n_direct_parameters = 50,
        maximum_probability_sum_error = 0.0,
        n_failed_direct_constraints = 0,
        n_divergences = 0,
        n_max_treedepth = 0,
        sampler_flags = (),
        convergence_assessed = false,
        diagnostic_decision = :not_applied_short_chain,
    )

    completed = BayesianMGMFRM._mgmfrm_bounded_fit_attempts(
        plan;
        profile = :wiring_smoke,
        backends = (:advancedhmc, :cmdstan),
        prior_regimes = (:implementation_reference, :source_aligned),
        maximum_attempts = 4,
        truth_scale = 0.15,
        cmdstan_path = nothing,
        cmdstan_cache_dir = nothing,
        fit_executor = fake_fit,
        diagnostic_executor = fake_diagnostics,
    )
    @test completed.status === :wiring_smoke_complete
    @test completed.schema ==
        "bayesianmgmfrm.mgmfrm_response_stress_fit_attempts.v1"
    @test completed.object === :mgmfrm_response_stress_fit_attempts
    @test completed.summary.n_planned_source_cases == 1
    @test completed.summary.n_attempts == 4
    @test completed.summary.n_terminal_attempts == 4
    @test completed.summary.n_completed == 4
    @test completed.summary.denominator_preserved
    @test completed.maximum_attempts == 4
    @test completed.truth_scale == 0.15
    @test completed.controls.chains == 1
    @test completed.controls.warmup == 4
    @test completed.controls.ndraws == 4
    @test completed.operability_completed
    @test !completed.convergence_assessed
    @test completed.computational_decision === :not_applied_short_chain
    @test completed.scientific_decision === :not_applied
    @test completed.recovery_evidence === :not_established
    @test all(row -> row.terminal_status === :completed, completed.rows)
    @test all(row -> row.object ===
        :mgmfrm_response_stress_fit_attempt_row, completed.rows)
    @test all(row -> row.output_integrity_passed, completed.rows)
    @test length(unique(row.attempt_id for row in completed.rows)) == 4
    @test Set(row.backend for row in completed.rows) ==
        Set((:advancedhmc, :cmdstan))
    @test Set(row.prior_regime for row in completed.rows) ==
        Set((:implementation_reference, :source_aligned))
    @test all(fit -> !ismissing(fit), completed.fits)

    selective_failure_fit = (case, backend, prior, controls, fit_seed;
            cmdstan_path, cmdstan_cache_dir) -> begin
        backend === :cmdstan && error("injected CmdStan fit failure")
        return fake_fit(
            case, backend, prior, controls, fit_seed;
            cmdstan_path, cmdstan_cache_dir)
    end
    fit_failed = BayesianMGMFRM._mgmfrm_bounded_fit_attempts(
        plan;
        profile = :wiring_smoke,
        backends = (:advancedhmc, :cmdstan),
        prior_regimes = (:implementation_reference,),
        maximum_attempts = 2,
        truth_scale = 0.15,
        cmdstan_path = nothing,
        cmdstan_cache_dir = nothing,
        fit_executor = selective_failure_fit,
        diagnostic_executor = fake_diagnostics,
    )
    @test fit_failed.status ===
        :wiring_smoke_complete_with_recorded_failures
    @test fit_failed.summary.n_attempts == 2
    @test fit_failed.summary.n_completed == 1
    @test fit_failed.summary.n_fit_failed == 1
    @test fit_failed.summary.denominator_preserved
    failed_fit_row = only(row for row in fit_failed.rows
        if row.terminal_status === :fit_failed)
    @test failed_fit_row.error_phase === :fit
    @test failed_fit_row.error isa ErrorException
    @test failed_fit_row.error_type == "ErrorException"
    @test occursin("injected CmdStan fit failure",
        failed_fit_row.error_message)

    failing_diagnostics = (fit, controls) ->
        error("injected diagnostic failure")
    diagnostic_failed = BayesianMGMFRM._mgmfrm_bounded_fit_attempts(
        plan;
        profile = :wiring_smoke,
        backends = (:advancedhmc,),
        prior_regimes = (:implementation_reference,),
        maximum_attempts = 1,
        truth_scale = 0.15,
        cmdstan_path = nothing,
        cmdstan_cache_dir = nothing,
        fit_executor = fake_fit,
        diagnostic_executor = failing_diagnostics,
    )
    @test diagnostic_failed.summary.n_diagnostic_failed == 1
    diagnostic_row = only(diagnostic_failed.rows)
    @test diagnostic_row.terminal_status === :diagnostic_failed
    @test diagnostic_row.error_phase === :diagnostic
    @test diagnostic_row.error isa ErrorException
    @test !ismissing(only(diagnostic_failed.fits))

    malformed = merge(first(plan), (;
        response_pattern = :not_a_response_pattern,
    ))
    generation_failed = BayesianMGMFRM._mgmfrm_bounded_fit_attempts(
        [malformed];
        profile = :wiring_smoke,
        backends = (:advancedhmc,),
        prior_regimes = (:implementation_reference,),
        maximum_attempts = 1,
        truth_scale = 0.15,
        cmdstan_path = nothing,
        cmdstan_cache_dir = nothing,
        fit_executor = fake_fit,
        diagnostic_executor = fake_diagnostics,
    )
    @test generation_failed.summary.n_generation_failed == 1
    generation_row = only(generation_failed.rows)
    @test generation_row.terminal_status === :generation_failed
    @test generation_row.error_phase === :generation_and_preflight
    @test generation_row.error isa ArgumentError
    @test generation_row.error_type == "ArgumentError"

    incompatible_expected = merge(first(plan).expected_pattern, (;
        unused_interior_category_3 = true,
    ))
    rejected_plan = [merge(first(plan), (;
        expected_pattern = incompatible_expected,
    ))]
    rejected = BayesianMGMFRM._mgmfrm_bounded_fit_attempts(
        rejected_plan;
        profile = :wiring_smoke,
        backends = (:advancedhmc,),
        prior_regimes = (:implementation_reference,),
        maximum_attempts = 1,
        truth_scale = 0.15,
        cmdstan_path = nothing,
        cmdstan_cache_dir = nothing,
        fit_executor = fake_fit,
        diagnostic_executor = fake_diagnostics,
    )
    @test rejected.summary.n_pre_fit_rejected == 1
    @test only(rejected.rows).terminal_status === :pre_fit_rejected
    @test only(rejected.fits) === missing

    @test_throws ArgumentError mgmfrm_response_stress_fit_attempts(
        mgmfrm_response_stress_plan(); maximum_attempts = 1)
    @test_throws ArgumentError mgmfrm_response_stress_fit_attempts(
        plan; profile = :analysis)
    @test_throws ArgumentError mgmfrm_response_stress_fit_attempts(
        plan; profile = :short_nuts_resource_probe)
    @test_throws ArgumentError mgmfrm_response_stress_fit_attempts(
        plan; backends = (:unknown,))
    @test_throws ArgumentError mgmfrm_response_stress_fit_attempts(
        plan; prior_regimes = (:unknown,))
    @test_throws ArgumentError mgmfrm_response_stress_fit_attempts(
        plan; cmdstan_path = "/not/used")
    @test_throws ArgumentError mgmfrm_response_stress_fit_attempts(
        plan; maximum_attempts = 0)
    int32_bound = BayesianMGMFRM._mgmfrm_bounded_fit_attempts(
        plan;
        profile = :wiring_smoke,
        backends = (:advancedhmc,),
        prior_regimes = (:implementation_reference,),
        maximum_attempts = Int32(1),
        truth_scale = 0.15,
        cmdstan_path = nothing,
        cmdstan_cache_dir = nothing,
        fit_executor = fake_fit,
        diagnostic_executor = fake_diagnostics,
    )
    @test int32_bound.maximum_attempts === 1

    short_probe = BayesianMGMFRM._mgmfrm_bounded_fit_attempts(
        plan;
        profile = :short_nuts_resource_probe,
        backends = (:advancedhmc,),
        prior_regimes = (:implementation_reference,),
        maximum_attempts = 1,
        truth_scale = 0.15,
        cmdstan_path = nothing,
        cmdstan_cache_dir = nothing,
        fit_executor = fake_fit,
        diagnostic_executor = fake_diagnostics,
    )
    @test short_probe.status === :short_nuts_resource_probe_complete
    @test short_probe.controls.warmup == 25
    @test short_probe.controls.ndraws == 25
    @test short_probe.controls.chains == 1
    @test short_probe.controls.target_accept == 0.90
    @test short_probe.controls.metric === :diagonal
    @test !short_probe.controls.convergence_assessed
    @test short_probe.claim_scope === :runtime_and_operability_only

    primary_row = first(mgmfrm_validation_primary_resource_plan().rows)
    primary_fake_fit = (case, backend, prior, controls, fit_seed;
            cmdstan_path, cmdstan_cache_dir) -> (;
        case_id = case.cell_id,
        backend,
        prior,
        controls,
        fit_seed,
        cmdstan_path,
        cmdstan_cache_dir,
    )
    primary_short = BayesianMGMFRM._mgmfrm_bounded_fit_attempts(
        (primary_row,);
        profile = :short_nuts_resource_probe,
        backends = (:advancedhmc,),
        prior_regimes = (:implementation_reference,),
        maximum_attempts = 1,
        truth_scale = 0.15,
        cmdstan_path = nothing,
        cmdstan_cache_dir = nothing,
        fit_executor = primary_fake_fit,
        diagnostic_executor = fake_diagnostics,
    )
    @test primary_short.schema ==
        "bayesianmgmfrm.mgmfrm_validation_primary_fit_attempts.v1"
    @test primary_short.object ===
        :mgmfrm_validation_primary_fit_attempts
    @test primary_short.status === :short_nuts_resource_probe_complete
    @test primary_short.summary.n_completed == 1
    @test only(primary_short.rows).object ===
        :mgmfrm_validation_primary_fit_attempt_row
    @test only(primary_short.rows).source_object ===
        :mgmfrm_validation_primary_grid_candidate
    @test only(primary_short.rows).simulation_seed ==
        primary_row.resource_seed
    @test ismissing(only(primary_short.rows).replication)
    @test only(primary_short.cases).data.category_levels == [1, 2, 3, 4]
    @test !ismissing(only(primary_short.fits))

    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_bounded_fit_attempts(
        (first(plan), primary_row);
        profile = :short_nuts_resource_probe,
        backends = (:advancedhmc,),
        prior_regimes = (:implementation_reference,),
        maximum_attempts = 2,
        truth_scale = 0.15,
        cmdstan_path = nothing,
        cmdstan_cache_dir = nothing,
        fit_executor = primary_fake_fit,
        diagnostic_executor = fake_diagnostics,
    )
end
