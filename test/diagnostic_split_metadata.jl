using Test
import BayesianMGMFRM

@testset "Diagnostic split metadata preserves odd and short chains" begin
    for n in (0, 1, 2, 3, 4, 5, 9, 10, 11, 32), chains in (1, 2, 4), split in (false, true)
        values = zeros(n * chains, 2)
        rows = BayesianMGMFRM._candidate_mcmc_diagnostic_rows(values, ["fixed_a", "fixed_b"], chains;
            parameter_space=:model, structurally_fixed_parameters=Set(["fixed_a", "fixed_b"]),
            split_chains=split, rhat_threshold=1.01, ess_threshold=400.)
        divided = split && chains >= 2 && n >= 4
        @test length(rows) == 2
        @test all(r -> r.draws_per_chain == n && r.n_chains == chains, rows)
        @test all(r -> r.diagnostic_draws_per_chain == (divided ? n ÷ 2 : n), rows)
        @test all(r -> r.diagnostic_chains == (divided ? 2chains : chains), rows)
        @test all(r -> r.total_draws == n * chains && r.split_chains === divided, rows)
        @test all(r -> r.split_chains_requested === split && r.flag === :structurally_fixed, rows)
        @test all(iszero, values)
    end
end
