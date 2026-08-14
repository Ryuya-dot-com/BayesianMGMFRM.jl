using Test

isdefined(Main, :CmdStanBackendValidation) ||
    include(joinpath(@__DIR__, "..", "scripts", "run_cmdstan_backend_validation.jl"))

@testset "paired AdvancedHMC and CmdStan dense/sparse validation" begin
    result = CmdStanBackendValidation.run_validation(; profile = :smoke)
    @test result.execution_passed
    @test length(result.rows) == 12
    @test length(result.pairs) == 6
    @test all(row -> row.execution_passed, result.rows)
    @test all(row -> row.n_failed_direct_constraints == 0, result.rows)
    @test all(pair -> pair.both_executed, result.pairs)
    @test all(pair -> pair.comparison_status === :descriptive_only,
        result.pairs)
    @test result.caveat ===
        :not_repeated_parameter_recovery_or_backend_equivalence_evidence
    @test result.timing_caveat ===
        :single_run_times_include_jit_and_cache_state_not_benchmark_evidence
end
