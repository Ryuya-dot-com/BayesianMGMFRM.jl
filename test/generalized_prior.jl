using Test
using Random
using BayesianMGMFRM

@testset "experimental generalized raw-coordinate prior" begin
    @test isdefined(BayesianMGMFRM.Experimental, :GeneralizedPrior)
    @test :GeneralizedPrior ∉ names(BayesianMGMFRM)

    default_prior = BayesianMGMFRM.Experimental.GeneralizedPrior()
    @test default_prior.person_sd == 1.0
    @test default_prior.rater_sd == 1.0
    @test default_prior.item_sd == 1.0
    @test default_prior.log_discrimination_sd == 0.5
    @test default_prior.log_consistency_sd == 0.5
    @test default_prior.step_sd == 1.0

    source_prior = BayesianMGMFRM.Experimental.GeneralizedPrior(;
        person_sd = 1,
        rater_sd = 1,
        item_sd = 1,
        log_discrimination_sd = 1,
        log_consistency_sd = 1,
        step_sd = 1,
    )
    internal = BayesianMGMFRM._source_fixture_prior(source_prior)
    @test BayesianMGMFRM._source_fixture_prior_values(internal) == (;
        person_sd = 1.0,
        rater_sd = 1.0,
        item_sd = 1.0,
        log_discrimination_sd = 1.0,
        log_consistency_sd = 1.0,
        step_sd = 1.0,
    )

    for bad_scale in (0.0, -1.0, Inf, NaN)
        @test_throws ArgumentError BayesianMGMFRM.Experimental.GeneralizedPrior(;
            log_consistency_sd = bad_scale,
        )
    end

    data = FacetData(
        (;
            person = ["P1", "P1", "P1", "P2", "P2", "P2"],
            rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
            item = ["I1", "I1", "I2", "I1", "I2", "I2"],
            score = [0, 1, 2, 1, 0, 2],
        );
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
    gmfrm_spec = mfrm_spec(
        data;
        family = :gmfrm,
        thresholds = :partial_credit,
        discrimination = :rater,
    )
    mgmfrm_spec = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = Bool[1 0; 0 1],
    )

    for spec in (gmfrm_spec, mgmfrm_spec)
        implicit_key = BayesianMGMFRM.Experimental.fit_cache_key(
            spec;
            seed = 20260814,
        )
        explicit_default_key = BayesianMGMFRM.Experimental.fit_cache_key(
            spec;
            prior = default_prior,
            seed = 20260814,
        )
        source_key = BayesianMGMFRM.Experimental.fit_cache_key(
            spec;
            prior = source_prior,
            seed = 20260814,
        )
        @test implicit_key == explicit_default_key
        @test source_key != implicit_key

        replicated = BayesianMGMFRM.Experimental.prior_predict(
            spec;
            prior = source_prior,
            ndraws = 7,
            rng = MersenneTwister(410),
        )
        check = BayesianMGMFRM.Experimental.prior_predictive_check(
            spec;
            prior = source_prior,
            ndraws = 7,
            rng = MersenneTwister(410),
        )
        design = BayesianMGMFRM.Experimental.preview(spec)
        @test replicated == check.replicated_scores
        @test size(replicated) == (7, data.n)
        @test all(score -> score in data.category_levels, replicated)
        @test check.model_family === spec.family
        @test check.stability === :experimental
        @test check.parameter_space === :raw_unconstrained_coordinates
        @test size(check.raw_parameter_draws, 1) == 7
        @test size(check.raw_parameter_draws, 2) ==
            length(check.raw_parameter_names)
        @test size(check.direct_parameter_draws) ==
            (7, length(design.parameter_names))
        @test check.direct_parameter_names == design.parameter_names
        @test check.prior.scales.log_discrimination_sd == 1.0
        @test check.prior.scales.log_consistency_sd == 1.0
        @test check.prior.jacobian_policy === :none_raw_coordinate_density
        for draw in axes(check.direct_parameter_draws, 1)
            params = @view check.direct_parameter_draws[draw, :]
            constraint_rows = spec.family === :gmfrm ?
                BayesianMGMFRM._gmfrm_direct_constraint_rows(design, params) :
                BayesianMGMFRM._mgmfrm_direct_constraint_rows(design, params)
            @test all(row.passed for row in constraint_rows)
        end
        @test check.implication_diagnostics.schema ==
            "bayesianmgmfrm.prior_predictive_implication_diagnostics.v1"
        @test !isempty(predictive_check_summary(check))
    end

    @test_throws ArgumentError BayesianMGMFRM.Experimental.prior_predict(
        gmfrm_spec;
        ndraws = 0,
    )
    @test_throws ArgumentError BayesianMGMFRM.Experimental.prior_predict(
        gmfrm_spec;
        prior = MFRMPrior(),
        ndraws = 1,
    )
    @test_throws ArgumentError BayesianMGMFRM.Experimental.prior_predictive_check(
        gmfrm_spec;
        ndraws = 1,
        min_category_probability = -0.1,
    )
    @test_throws ArgumentError BayesianMGMFRM.Experimental.prior_predict(
        gmfrm_spec;
        experimental = true,
        ndraws = 1,
    )
    unsupported_spec = mfrm_spec(
        data;
        family = :gmfrm,
        thresholds = :rating_scale,
        discrimination = :rater,
    )
    @test_throws ArgumentError BayesianMGMFRM.Experimental.prior_predict(
        unsupported_spec;
        ndraws = 1,
    )

    contract = BayesianMGMFRM.Experimental.surface_contract(:mgmfrm)
    @test contract.prior.constructor === :GeneralizedPrior
    @test contract.prior.parameter_space === :raw_unconstrained_coordinates
    @test contract.prior.custom_scales_allowed
    @test contract.prior.prior_predict_available
    @test contract.prior.prior_predictive_check_available
    @test !contract.prior.direct_scale_prior_allowed
    @test contract.prior.jacobian_policy === :none_raw_coordinate_density
end
