include("posterior_mcse_draws.jl")

@testset "posterior MCSE MFRM fit dispatch" begin
    table = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2],
    )
    data = FacetData(
        table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
    fit_result = fit(
        getdesign(mfrm_spec(data; thresholds = :partial_credit));
        backend = :julia,
        ndraws = 10,
        warmup = 2,
        chains = 2,
        step_size = 0.05,
        seed = 20260816,
    )
    rows = posterior_mcse(fit_result)
    @test length(rows) == size(fit_result.draws, 2)
    @test [row.parameter for row in rows] ==
        fit_result.design.parameter_names
    @test all(row -> row.parameter_space === :identified, rows)
    @test all(row -> row.n_chains == 2, rows)
    @test all(row -> row.draws_per_chain == 10, rows)
    @test all(row -> row.mcse_status in
        (:available, :mcse_unavailable, :degenerate_draws), rows)
    @test_throws ArgumentError posterior_mcse(
        fit_result;
        parameter_space = :direct_constrained,
    )
end
