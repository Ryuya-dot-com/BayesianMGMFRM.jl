using Test
using Random

using BayesianMGMFRM

@testset "CmdStan supported MFRM-family sampling" begin
    runtime = cmdstan_backend_check(; require_ready = true)
    @test runtime.runtime_ready

    table = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2", "E3", "E3", "E3"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2, 1, 2, 0],
    )
    data = FacetData(
        table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )

    pcm_design = getdesign(mfrm_spec(data; thresholds = :partial_credit))
    pcm_fit = fit(
        pcm_design;
        backend = :cmdstan,
        ndraws = 5,
        warmup = 5,
        chains = 2,
        seed = 4107,
    )
    @test pcm_fit.backend === :cmdstan
    @test pcm_fit.sampler === :nuts
    @test size(pcm_fit.draws) == (10, length(pcm_design.parameter_names))
    @test pcm_fit.chain_ids == [fill(1, 5); fill(2, 5)]
    @test pcm_fit.iterations == [collect(1:5); collect(1:5)]
    @test all(isfinite, pcm_fit.draws)
    @test all(isfinite, pcm_fit.log_posterior)
    @test length(pcm_fit.sampler_controls.rng.chain_seeds) == 2
    @test length(unique(pcm_fit.sampler_controls.rng.chain_seeds)) == 2
    @test length(sampler_diagnostics(pcm_fit)) == 2
    @test fit_metadata(pcm_fit).backend === :cmdstan
    @test length(posterior_summary(pcm_fit)) ==
        length(pcm_design.parameter_names)
    ppc = posterior_predictive_check(
        pcm_fit;
        ndraws = 2,
        rng = MersenneTwister(4109),
    )
    @test size(ppc.replicated_scores) == (2, data.n)

    rsm_design = getdesign(mfrm_spec(data; thresholds = :rating_scale))
    rsm_fit = fit(
        rsm_design;
        backend = :cmdstan,
        ndraws = 3,
        warmup = 3,
        chains = 1,
        seed = 4108,
    )
    @test rsm_fit.backend === :cmdstan
    @test size(rsm_fit.draws) == (3, length(rsm_design.parameter_names))
    @test all(isfinite, rsm_fit.log_posterior)

    gmfrm_spec = mfrm_spec(
        data;
        family = :gmfrm,
        thresholds = :partial_credit,
        discrimination = :rater,
    )
    gmfrm_design = BayesianMGMFRM.Experimental.preview(gmfrm_spec)
    gmfrm_fit = BayesianMGMFRM.Experimental.fit(
        gmfrm_spec;
        backend = :cmdstan,
        ndraws = 2,
        warmup = 2,
        chains = 1,
        seed = 4110,
        metric = :unit,
    )
    @test gmfrm_fit isa GMFRMFit
    @test gmfrm_fit.backend === :cmdstan
    @test gmfrm_fit.sampler === :nuts
    @test size(gmfrm_fit.draws) ==
        (2, gmfrm_fit.diagnostic_surface.summary.n_parameters)
    @test size(gmfrm_fit.direct_draws) ==
        (2, length(gmfrm_design.parameter_names))
    @test size(gmfrm_fit.direct_pointwise_loglikelihood) == (2, data.n)
    @test all(isfinite, gmfrm_fit.log_posterior)
    @test fit_metadata(gmfrm_fit).backend === :cmdstan
    @test all(row -> row.backend === :cmdstan,
        sampler_diagnostics(gmfrm_fit))
    @test gmfrm_fit.diagnostic_surface.summary.n_failed_direct_constraints == 0
    @test gmfrm_fit.sampler_controls.thinning == 1
    @test gmfrm_fit.sampler_controls.gradient_backend === :stan_autodiff
    gmfrm_ppc = posterior_predictive_check(
        gmfrm_fit;
        ndraws = 1,
        rng = MersenneTwister(4111),
    )
    @test size(gmfrm_ppc.replicated_scores) == (1, data.n)

    mgmfrm_spec = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = Bool[1 0; 0 1],
    )
    mgmfrm_design = BayesianMGMFRM.Experimental.preview(mgmfrm_spec)
    mgmfrm_fit = BayesianMGMFRM.Experimental.fit(
        mgmfrm_spec;
        backend = :cmdstan,
        ndraws = 2,
        warmup = 2,
        chains = 1,
        seed = 4112,
        metric = :unit,
    )
    @test mgmfrm_fit isa MGMFRMFit
    @test mgmfrm_fit.backend === :cmdstan
    @test mgmfrm_fit.sampler === :nuts
    @test size(mgmfrm_fit.draws) ==
        (2, mgmfrm_fit.diagnostic_surface.summary.n_parameters)
    @test size(mgmfrm_fit.direct_draws) ==
        (2, length(mgmfrm_design.parameter_names))
    @test size(mgmfrm_fit.direct_pointwise_loglikelihood) == (2, data.n)
    @test all(isfinite, mgmfrm_fit.log_posterior)
    @test fit_metadata(mgmfrm_fit).backend === :cmdstan
    @test all(row -> row.backend === :cmdstan,
        sampler_diagnostics(mgmfrm_fit))
    @test mgmfrm_fit.diagnostic_surface.summary.n_failed_direct_constraints == 0
    @test mgmfrm_fit.sampler_controls.thinning == 1
    @test mgmfrm_fit.sampler_controls.gradient_backend === :stan_autodiff
    mgmfrm_ppc = posterior_predictive_check(
        mgmfrm_fit;
        ndraws = 1,
        rng = MersenneTwister(4113),
    )
    @test size(mgmfrm_ppc.replicated_scores) == (1, data.n)
end
