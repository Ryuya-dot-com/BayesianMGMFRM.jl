using Test

include(joinpath(@__DIR__, "..", "scripts", "run_cmdstan_backend_validation.jl"))

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
        end
    end
end
