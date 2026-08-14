using Test

isdefined(Main, :CmdStanRecoveryPilot) ||
    include(joinpath(@__DIR__, "..", "scripts", "run_cmdstan_recovery_pilot.jl"))

@testset "paired CmdStan known-truth recovery pilot" begin
    result = CmdStanRecoveryPilot.run_pilot(; replications = 1)
    @test result.execution_passed
    @test result.operability_passed
    @test length(result.rows) == 6
    @test length(result.pairs) == 3
    @test length(result.aggregates) == 6
    @test all(row -> row.execution_passed, result.rows)
    @test all(row -> row.total_divergences >= 0, result.aggregates)
    @test all(row -> row.comparison_status === :descriptive_only,
        result.pairs)
    @test result.claim_scope ===
        :small_repeated_known_truth_pilot_not_calibration_evidence
    @test result.diagnostic_decision === :not_applied_in_pilot
end
