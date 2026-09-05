using Test

import BayesianMGMFRM

include(joinpath(@__DIR__, "..", "scripts", "run_cmdstan_backend_validation.jl"))
include(joinpath(@__DIR__, "..", "scripts", "run_cmdstan_recovery_pilot.jl"))

@testset "CmdStan paired validation contract" begin
    smoke = CmdStanBackendValidation.validation_controls(:smoke)
    pilot = CmdStanBackendValidation.validation_controls(:pilot)
    @test smoke.chains == 1
    @test !smoke.convergence_assessed
    @test pilot.chains == 2
    @test pilot.convergence_assessed
    @test_throws ArgumentError CmdStanBackendValidation.validation_controls(
        :analysis,
    )

    dense = CmdStanBackendValidation.scenario_data(:dense)
    sparse = CmdStanBackendValidation.scenario_data(:sparse)
    @test dense.n == 72
    @test sparse.n == 26
    @test CmdStanBackendValidation.rating_fraction(dense) == 1.0
    @test CmdStanBackendValidation.rating_fraction(sparse) == 13 / 48
    @test_throws ArgumentError CmdStanBackendValidation.scenario_data(:unknown)

    for (family_index, family) in pairs((:mfrm, :gmfrm, :mgmfrm))
        for (scenario_index, scenario) in pairs((:dense, :sparse))
            case = CmdStanBackendValidation.simulated_case(
                family,
                scenario;
                seed = 9_000 + 10 * family_index + scenario_index,
            )
            @test case.family === family
            @test case.scenario === scenario
            @test case.spec.validation.passed
            @test case.spec.data.category_levels == [0, 1, 2]
            @test case.truth_parameter_space ===
                (family === :mfrm ? :direct : :raw)
            @test all(isfinite, case.truth)
            @test any(!iszero, case.truth)
            @test all(isfinite, case.direct_truth)
            fitted_design = family === :mfrm ?
                BayesianMGMFRM.getdesign(case.spec) :
                BayesianMGMFRM.Experimental.preview(case.spec)
            @test length(case.direct_truth) ==
                length(fitted_design.parameter_names)
        end
    end

    recovery_rows = [
        (;
            family = :mfrm,
            backend = :advancedhmc,
            mean_absolute_error = value,
            rmse = value + 0.1,
            coverage_rate = 0.75,
            mean_interval_width = 1.0,
            max_absolute_error = value + 0.2,
            max_block_mean_absolute_error = value + 0.1,
            min_block_coverage_rate = 0.5,
            elapsed_seconds = 2.0,
            execution_passed = true,
            sampler_flags = (),
            n_mcmc_warning_parameters = 0,
            n_divergences = 0,
            n_max_treedepth = 0,
            max_rank_normalized_rhat = 1.01,
            min_bulk_ess = 80.0,
            min_tail_ess = 70.0,
        )
        for value in (0.2, 0.4)
    ]
    aggregate = CmdStanRecoveryPilot.aggregate_row(
        recovery_rows,
        :mfrm,
        :advancedhmc,
    )
    @test aggregate.n_replications == 2
    @test aggregate.mean_absolute_error ≈ 0.3
    @test aggregate.total_elapsed_seconds == 4.0
    @test_throws ArgumentError CmdStanRecoveryPilot.run_pilot(
        replications = 0,
    )
end
