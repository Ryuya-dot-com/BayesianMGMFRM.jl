using Test
using Random
using Statistics
using MCMCDiagnosticTools
using BayesianMGMFRM

@testset "posterior MCSE for parameters and derived estimands" begin
    rng = MersenneTwister(20260815)
    chains = 4
    draws_per_chain = 40
    draws = randn(rng, chains * draws_per_chain, 2)
    rows = posterior_mcse(
        draws;
        chains,
        parameter_names = ["alpha", "beta"],
    )

    @test length(rows) == 2
    @test [row.parameter for row in rows] == ["alpha", "beta"]
    @test all(row -> row.parameter_space === :user_defined_estimand, rows)
    @test all(row -> row.mcse_status === :available, rows)
    @test all(row -> row.convergence_review_required, rows)
    @test all(row -> !row.precision_threshold_applied, rows)
    @test all(row -> row.precision_decision === :not_applied, rows)
    @test all(row -> row.n_chains == chains, rows)
    @test all(row -> row.draws_per_chain == draws_per_chain, rows)
    @test all(row -> row.total_draws == size(draws, 1), rows)
    @test all(row -> row.mcse_method ===
        :mcmcdiagnostictools_ess_asymptotic_variance, rows)
    @test all(row -> row.split_chains == 2, rows)
    @test all(row -> row.minimum_draws_per_chain == 10, rows)
    @test all(row -> isfinite(row.mean_mcse) && row.mean_mcse >= 0, rows)
    @test all(row -> isfinite(row.sd_mcse) && row.sd_mcse >= 0, rows)
    @test all(row -> length(row.quantiles) == 3, rows)
    @test [row.probability for row in rows[1].quantiles] ==
        [0.025, 0.5, 0.975]

    values = BayesianMGMFRM._draw_matrix_to_chain_array(draws, chains)
    alpha = @view values[:, :, 1]
    @test rows[1].mean_mcse ≈ MCMCDiagnosticTools.mcse(
        alpha; kind = Statistics.mean, split_chains = 2)
    @test rows[1].sd_mcse ≈ MCMCDiagnosticTools.mcse(
        alpha; kind = Statistics.std, split_chains = 2)
    for quantile_row in rows[1].quantiles
        probability = quantile_row.probability
        @test quantile_row.estimate ≈ quantile(vec(alpha), probability)
        @test quantile_row.mcse ≈ MCMCDiagnosticTools.mcse(
            alpha;
            kind = Base.Fix2(Statistics.quantile, probability),
            split_chains = 2,
        )
    end

    contrast_draws = reshape(draws[:, 1] .- draws[:, 2], :, 1)
    contrast = only(posterior_mcse(
        contrast_draws;
        chains,
        parameter_names = ["alpha_minus_beta"],
        probabilities = (0.1, 0.9),
        parameter_space = :derived_contrast,
    ))
    @test contrast.parameter == "alpha_minus_beta"
    @test contrast.parameter_space === :derived_contrast
    @test [row.probability for row in contrast.quantiles] == [0.1, 0.9]
    @test contrast.mcse_status === :available

    constant_draws = hcat(draws[:, 1], fill(2.0, size(draws, 1)))
    constant = posterior_mcse(
        constant_draws;
        chains,
        parameter_names = ["varying", "constant"],
    )
    @test constant[2].mcse_status === :degenerate_draws
    @test ismissing(constant[2].mean_mcse)
    fixed = BayesianMGMFRM._posterior_mcse_rows(
        constant_draws,
        ["varying", "fixed"],
        chains;
        parameter_space = :direct_constrained,
        structurally_fixed_parameters = Set(["fixed"]),
    )
    @test fixed[2].mcse_status === :structurally_fixed
    @test fixed[2].mean_mcse == 0.0
    @test fixed[2].sd_mcse == 0.0
    @test all(row -> row.mcse == 0.0, fixed[2].quantiles)
    @test !fixed[2].convergence_review_required
    varied_fixed = BayesianMGMFRM._posterior_mcse_rows(
        draws,
        ["varying", "declared_fixed"],
        chains;
        parameter_space = :direct_constrained,
        structurally_fixed_parameters = Set(["declared_fixed"]),
    )
    @test varied_fixed[2].mcse_status === :fixed_parameter_varied
    @test ismissing(varied_fixed[2].mean_mcse)
    @test varied_fixed[2].convergence_review_required

    one_chain = posterior_mcse(draws; chains = 1)
    @test all(row -> row.mcse_status === :insufficient_chains, one_chain)
    short = posterior_mcse(draws[1:32, :]; chains = 4)
    @test all(row -> row.mcse_status === :insufficient_draws, short)
    nonfinite_draws = copy(draws)
    nonfinite_draws[1, 1] = NaN
    nonfinite = posterior_mcse(nonfinite_draws; chains)
    @test nonfinite[1].mcse_status === :nonfinite_draws
    @test ismissing(nonfinite[1].mean_mcse)

    mean_only = posterior_mcse(
        draws;
        chains,
        probabilities = (),
    )
    @test all(row -> isempty(row.quantiles), mean_only)
    @test all(row -> row.mcse_status === :available, mean_only)

    @test_throws ArgumentError posterior_mcse(draws; chains = 0)
    @test_throws ArgumentError posterior_mcse(draws; chains = 3)
    @test_throws ArgumentError posterior_mcse(
        draws;
        chains,
        parameter_names = ["only_one"],
    )
    @test_throws ArgumentError posterior_mcse(
        draws;
        chains,
        probabilities = (0.0, 0.5),
    )
end

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
