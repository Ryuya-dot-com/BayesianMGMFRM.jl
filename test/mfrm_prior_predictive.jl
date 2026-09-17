isdefined(@__MODULE__, :MFRMCorrelated2DChecks) || include("mfrm_correlated_2d.jl")
module MFRMPriorPredictiveChecks
using Test, BayesianMGMFRM, Random, Statistics, LinearAlgebra
using ..MFRMCorrelated2DChecks: specification, PRIOR
const B = BayesianMGMFRM

@testset "fixed-coefficient prior simulation (no MCMC)" begin
    for categories in (2, 4), correlated in (false, true)
        spec = specification(categories)
        model = correlated ? B.Experimental.correlated(spec; lkj_eta = 3) : spec
        target = B._fixed_q_prior_target(model, PRIOR)
        base = correlated ? target.base : target
        check = B.Experimental.prior_predictive_check(model; prior = PRIOR, ndraws = 37, rng = MersenneTwister(83))
        @test isequal(check, B.Experimental.prior_predictive_check(model; prior = PRIOR, ndraws = 37, rng = MersenneTwister(83)))
        @test check.replicated_scores == B.Experimental.prior_predict(model; prior = PRIOR, ndraws = 37, rng = MersenneTwister(83))
        @test all(in(spec.data.category_levels), check.replicated_scores)
        @test size(check.replicated_scores) == (37, spec.data.n)
        @test check.parameter_names == target.blueprint.parameter_names
        @test length(check.model_coordinates) == length(check.parameter_summary)
        @test check.q_matrix == spec.q_matrix && check.dimension_labels == spec.dimension_labels
        @test all(isfinite, check.parameter_draws)
        @test !isempty(predictive_check_summary(check; include_grouped = true))
        contract = B.Experimental.surface_contract(correlated ? model : :mfrm)
        @test contract.prior.prior_predict_available && contract.prior.prior_predictive_check_available
        # Seeded local RNGs and later plotting leave the global RNG and check unchanged.
        Random.seed!(921); expected = rand(); Random.seed!(921)
        B.Experimental.prior_predict(model; prior = PRIOR, ndraws = 2, rng = MersenneTwister(83))
        @test rand() == expected
        snapshot = deepcopy(check)
        for (row, summary) in zip(check.model_coordinates, check.parameter_summary)
            @test summary.mean ≈ mean(row.values)
            @test summary.lower ≈ quantile(row.values, 0.025)
            @test summary.upper ≈ quantile(row.values, 0.975)
            if row.fixed
                @test all(==(row.values[1]), row.values)
            end
        end
        parameter_plot = B._fixed_q_prior_plot_data(check; block = :person, dimension = "Second", interval = 0.8)
        @test length(parameter_plot.rows) == 3
        @test all(row.dimension == 2 for row in parameter_plot.rows)
        for row in parameter_plot.rows
            coordinate = only(filter(x -> x.parameter == row.parameter, check.model_coordinates))
            @test row.lower ≈ quantile(coordinate.values, 0.1)
            @test row.upper ≈ quantile(coordinate.values, 0.9)
        end
        predictive_plot = B._prior_predictive_plot_data(check; interval = 0.8)
        @test predictive_plot.kind === :prior_predictive
        @test predictive_plot.n_replicates == 37 && predictive_plot.n_observations == spec.data.n
        expected_rows = filter(row -> row.statistic === :category_proportion, predictive_check_summary(check; interval = 0.8))
        @test predictive_plot.rows == predictive_check_plot_data(expected_rows)
        @test isequal(check, snapshot)
        rater = filter(row -> row.block === :rater, check.model_coordinates)
        @test all(isapprox.(sum(row.values for row in rater), 0; atol = 1e-14))
        steps = filter(row -> row.block === :item_steps, check.model_coordinates)
        for i in eachindex(spec.data.item_levels)
            rows = steps[((i-1)*categories+1):(i*categories)]
            @test all(iszero, first(rows).values)
            @test all(isapprox.(sum(row.values for row in rows), 0; atol = 1e-14))
        end
        # Independent unit-logit PCM calculation protects the 1.7 reference mapping.
        theta = filter(row -> row.block === :person, check.model_coordinates)
        item = filter(row -> row.block === :item, check.model_coordinates)
        for draw in (1, 37)
            pointwise = B._mfrm_fixed_q_pointwise(base, check.parameter_draws[draw, 1:B.LogDensityProblems.dimension(base)])
            for n in 1:spec.data.n
                p, i, r = spec.data.person[n], spec.data.item[n], spec.data.rater[n]
                ability = sum(theta[(p-1)*2+d].values[draw] for d in 1:2 if spec.q_matrix[i,d])
                eta = ability - item[i].values[draw] - rater[r].values[draw]
                logits = cumsum([0.0; [eta - steps[(i-1)*categories+k].values[draw] for k in 2:categories]])
                probabilities = exp.(logits .- maximum(logits)); probabilities ./= sum(probabilities)
                category = findfirst(==(spec.data.score[n]), spec.data.category_levels)
                @test pointwise[n] ≈ log(probabilities[category]) atol = 1e-12
            end
        end
        # Changing observed scores affects the comparison, not the prior draws/replications.
        source = spec.data
        changed_data = FacetData((; person = source.person, item = source.item, rater = source.rater,
            score = (source.score .+ 1) .% categories); person = :person, item = :item, rater = :rater,
            score = :score, category_levels = source.category_levels)
        changed = mfrm_spec(changed_data; dimensions = 2, q_matrix = spec.q_matrix,
            dimension_labels = spec.dimension_labels)
        changed_model = correlated ? B.Experimental.correlated(changed; lkj_eta = 3) : changed
        updated = B.Experimental.prior_predictive_check(changed_model; prior = PRIOR, ndraws = 37, rng = MersenneTwister(83))
        @test updated.parameter_draws == check.parameter_draws
        @test updated.replicated_scores == check.replicated_scores
        for options in ((; ndraws = 0), (; min_category_probability = -1), (; experimental = true))
            @test_throws ArgumentError B.Experimental.prior_predictive_check(model; options...)
        end
        @test_throws ArgumentError B.Experimental.prior_predict(model; ndraws = 0)
        @test_throws ArgumentError B._fixed_q_prior_plot_data(check; dimension = "absent")
        @test_throws ArgumentError B._fixed_q_prior_plot_data(check; scale = :raw)
        @test_throws ArgumentError B._prior_predictive_plot_data(check; interval = 1)
        if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
            @test_throws ArgumentError B.plot_prior(check)
            @test_throws ArgumentError B.plot_predictive(check)
        end
    end
end

@testset "joint prior measure, fixed scales and LKJ shape" begin
    for eta in (1, 2, 5, 10_000)
        target = B._fixed_q_prior_target(B.Experimental.correlated(specification(); lkj_eta = eta), PRIOR)
        draws = B._fixed_q_prior_draws(target, 20_000, MersenneTwister(172 + eta))
        rho = tanh.(draws[:, end])
        @test all(-1 .< rho .< 1)
        @test abs(mean(rho)) < 0.025
        @test isapprox(mean(rho.^2), 1/(2eta+1); rtol = 0.04)
        x, y = draws[:,1] ./ PRIOR.person_sd, draws[:,2] ./ PRIOR.person_sd
        residual = (y .- rho .* x) ./ sqrt.(1 .- rho.^2)
        @test abs(mean(x)) < 0.04 && abs(mean(y)) < 0.04
        @test abs(var(x)-1) < 0.04 && abs(var(y)-1) < 0.04
        @test abs(mean(residual)) < 0.04 && abs(var(residual)-1) < 0.04
        @test abs(cor(x, residual)) < 0.04
        @test abs(mean(x .* y .* rho) - 1/(2eta+1)) < 0.025
        # An independently evaluated joint density includes d_rho/d_z exactly once.
        for draw in 1:4
            row = draws[draw,:]; r = rho[draw]
            lp = B.Turing.logpdf(B.Turing.Beta(eta, eta), (r+1)/2) - log(2) + log1p(-r*r)
            covariance = PRIOR.person_sd^2 .* [1 r; r 1]
            for i in 1:2:6
                lp += B.Turing.logpdf(B.Turing.MvNormal(zeros(2), covariance), row[i:i+1])
            end
            for i in 7:(length(row)-1)
                lp += B.Turing.logpdf(B.Turing.Normal(0, B._source_fixture_prior_sd(target.base, i)), row[i])
            end
            @test logprior(target, row) ≈ lp atol = 1e-9
        end
    end
    target = B._fixed_q_prior_target(specification(), PRIOR)
    draws = B._fixed_q_prior_draws(target, 20_000, MersenneTwister(734))
    @test abs(cor(draws[:,1], draws[:,2])) < 0.04
    for i in axes(draws, 2)
        sd = B._source_fixture_prior_sd(target, i)
        @test abs(mean(draws[:,i])/sd) < 0.04
        @test abs(var(draws[:,i])/sd^2 - 1) < 0.04
    end
    @test_throws ArgumentError B._prior_predictive_plot_data((;))
    @test_throws ArgumentError B._fixed_q_prior_plot_data((;))
    changed = B.Experimental.correlated(specification()); changed.base_spec.q_matrix[1,2] = true
    @test_throws ArgumentError B.Experimental.prior_predict(changed; ndraws = 1)
end

@testset "shared prior predictive figures for existing model families" begin
    data = specification().data
    for family in (:mfrm, :gmfrm, :mgmfrm)
        spec = family === :mfrm ? mfrm_spec(data; thresholds = :partial_credit) :
            family === :gmfrm ? mfrm_spec(data; family, thresholds = :partial_credit, discrimination = :rater) :
            mfrm_spec(data; family, dimensions = 2, q_matrix = Bool[1 0; 1 0; 0 1; 0 1])
        check = family === :mfrm ? prior_predictive_check(spec; ndraws = 12, rng = MersenneTwister(19)) :
            B.Experimental.prior_predictive_check(spec; ndraws = 12, rng = MersenneTwister(19))
        plotdata = B._prior_predictive_plot_data(check)
        @test length(plotdata.rows) == length(data.category_levels)
        @test plotdata.n_replicates == 12
        @test plotdata.rows == predictive_check_plot_data(filter(row -> row.statistic === :category_proportion,
            predictive_check_summary(check)))
        @test_throws ArgumentError B._fixed_q_prior_plot_data(check)
        if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) !== nothing
            @test B.plot_predictive(check) isa Base.get_extension(B, :BayesianMGMFRMCairoMakieExt).Figure
        end
    end
end
end
