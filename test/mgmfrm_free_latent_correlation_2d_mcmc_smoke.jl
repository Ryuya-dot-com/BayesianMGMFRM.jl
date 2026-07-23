using LogDensityProblems
using Test
using BayesianMGMFRM

function _free_correlation_mcmc_smoke_data()
    people = String[]
    raters = String[]
    items = String[]
    scores = Int[]
    item_levels = ("I1", "I2", "I3", "I4")
    score_patterns = (
        (0, 1, 2, 1),
        (1, 2, 1, 0),
        (2, 1, 0, 2),
        (1, 0, 2, 1),
    )
    for person in 1:4
        for item in 1:4
            push!(people, "P$person")
            push!(raters, isodd(person + item) ? "R1" : "R2")
            push!(items, item_levels[item])
            push!(scores, score_patterns[person][item])
        end
    end
    return FacetData(
        (; person = people, rater = raters, item = items, score = scores);
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

@testset "private 2D free-correlation AdvancedHMC smoke" begin
    experimental = BayesianMGMFRM.Experimental
    data = _free_correlation_mcmc_smoke_data()
    spec = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = Bool[1 0; 0 1; 1 0; 0 1],
        dimension_labels = ["analytic", "verbal"],
    )
    candidate = experimental.free_latent_correlation_2d_candidate(spec)
    initial = initial_params(candidate; value = 0.0, zrho = atanh(0.25))
    controls = (;
        ndraws = 8,
        warmup = 8,
        chains = 1,
        step_size = 0.03,
        seed = 20260722,
        max_depth = 4,
        metric = :unit,
        init_jitter = 0.0,
    )

    smoke = experimental.free_latent_correlation_2d_sampler_smoke(
        spec;
        raw_initial = initial,
        controls...,
    )
    replay = BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_sample_bundle(
            candidate,
            initial;
            controls...,
        )

    @test smoke isa NamedTuple
    @test smoke.schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_sample_bundle.v1"
    @test smoke.scope === :mgmfrm_2d_free_latent_correlation_candidate
    @test smoke.status === :internal_execution_smoke
    @test smoke.backend === :advancedhmc
    @test smoke.sampler === :nuts
    @test smoke.result_type === :named_tuple_only
    @test !smoke.public_fit
    @test !smoke.fit_ready
    @test !smoke.cache_enabled
    @test :_mgmfrm_free_latent_correlation_2d_sample_bundle ∉
        names(BayesianMGMFRM)
    @test :free_latent_correlation_2d_sampler_smoke ∉
        names(experimental)

    @test smoke.diagnostic_status === :not_evaluable_smoke
    @test smoke.claim_scope === :execution_smoke_not_recovery
    @test !smoke.convergence_evaluated
    @test !smoke.recovery_verified
    @test !hasproperty(smoke, :rhat)
    @test !hasproperty(smoke, :effective_sample_size)

    nparams = LogDensityProblems.dimension(candidate)
    @test size(smoke.draws) == (controls.ndraws, nparams)
    @test size(smoke.base_draws) == (controls.ndraws, nparams - 1)
    @test size(smoke.pointwise_loglikelihood) ==
        (controls.ndraws, data.n)
    @test length(smoke.logdensity) == controls.ndraws
    @test length(smoke.zrho_draws) == controls.ndraws
    @test length(smoke.rho_draws) == controls.ndraws
    @test smoke.rho_draws == tanh.(smoke.zrho_draws)
    @test all(value -> -1 < value < 1, smoke.rho_draws)
    @test size(smoke.chain_initials) == (controls.chains, nparams)
    @test length(smoke.chain_initial_logdensity) == controls.chains
    @test all(isfinite, smoke.chain_initials)
    @test all(isfinite, smoke.chain_initial_logdensity)
    @test vec(smoke.chain_initials[1, :]) == initial
    @test tanh(smoke.chain_initials[1, candidate.blueprint.zrho_index]) > 0
    @test smoke.chain_initial_logdensity == [
        LogDensityProblems.logdensity(candidate, @view smoke.chain_initials[chain, :])
        for chain in 1:controls.chains
    ]

    @test smoke.summary.raw_draws_finite
    @test smoke.summary.logdensity_finite
    @test smoke.summary.reevaluated_logdensity_finite
    @test smoke.summary.pointwise_loglikelihood_finite
    @test smoke.summary.chain_initials_finite
    @test smoke.summary.chain_initial_logdensity_finite
    @test smoke.summary.chain_initials_shape_valid
    @test smoke.summary.direct_payload_finite
    @test smoke.summary.finite_payload
    @test all(isfinite, smoke.draws)
    @test all(isfinite, smoke.logdensity)
    @test all(isfinite, smoke.pointwise_loglikelihood)
    @test smoke.likelihood_identity.passed
    @test smoke.pointwise_identity.passed
    @test smoke.summary.n_numerical_errors == 0
    @test smoke.summary.n_failed_direct_constraints == 0
    @test smoke.summary.sampler_stats_length_valid
    @test smoke.summary.sampler_stats_layout_valid
    @test smoke.summary.chain_acceptance_rate_finite
    @test smoke.summary.sampler_telemetry_finite
    @test smoke.summary.sampler_telemetry_valid
    @test smoke.summary.logdensity_revalidation_passed
    @test length(smoke.sampler_stats) == controls.ndraws * controls.chains
    @test all(isfinite, smoke.chain_acceptance_rate)
    @test all(value -> 0 <= value <= 1, smoke.chain_acceptance_rate)
    @test smoke.logdensity_revalidation.passed
    @test smoke.summary.passed

    evaluated_logdensity = [
        LogDensityProblems.logdensity(candidate, @view smoke.draws[row, :])
        for row in axes(smoke.draws, 1)
    ]
    evaluated_pointwise = reduce(
        vcat,
        (permutedims(BayesianMGMFRM.
            _mgmfrm_free_latent_correlation_2d_pointwise_loglikelihood(
                candidate,
                @view(smoke.draws[row, :]),
            )) for row in axes(smoke.draws, 1)),
    )
    @test smoke.logdensity ≈ evaluated_logdensity atol = 1e-10 rtol = 1e-10
    @test smoke.reevaluated_logdensity == evaluated_logdensity
    @test smoke.pointwise_loglikelihood == evaluated_pointwise
    @test vec(sum(smoke.pointwise_loglikelihood; dims = 2)) ≈
        smoke.candidate_loglikelihood atol = 1e-12 rtol = 1e-12

    @test smoke.sampler_controls.rng.algorithm === :MersenneTwister
    @test smoke.sampler_controls.rng.seed == controls.seed
    @test smoke.sampler_controls.rng.replayable
    @test smoke.draws == replay.draws
    @test smoke.logdensity == replay.logdensity
    @test smoke.reevaluated_logdensity == replay.reevaluated_logdensity
    @test smoke.pointwise_loglikelihood == replay.pointwise_loglikelihood
    @test smoke.zrho_draws == replay.zrho_draws
    @test smoke.rho_draws == replay.rho_draws
    @test smoke.chain_initials == replay.chain_initials
    @test smoke.chain_initial_logdensity == replay.chain_initial_logdensity

    @test_throws ArgumentError BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_sample_bundle(
            candidate,
            initial;
            ndraws = 0,
            seed = controls.seed,
        )
    @test_throws ArgumentError BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_sample_bundle(
            candidate,
            initial[1:end-1];
            seed = controls.seed,
        )
    nonfinite_initial = copy(initial)
    nonfinite_initial[end] = Inf
    @test_throws ArgumentError BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_sample_bundle(
            candidate,
            nonfinite_initial;
            seed = controls.seed,
        )

    wrong_shape_chain_initials = repeat(
        reshape(initial, 1, :),
        1,
        1,
    )
    @test_throws ArgumentError BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_sample_bundle(
            candidate,
            initial;
            ndraws = 1,
            warmup = 0,
            chains = 2,
            chain_initials = wrong_shape_chain_initials,
            seed = controls.seed,
        )
    nonfinite_chain_initials = repeat(reshape(initial, 1, :), 2, 1)
    nonfinite_chain_initials[2, end] = Inf
    @test_throws ArgumentError BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_sample_bundle(
            candidate,
            initial;
            ndraws = 1,
            warmup = 0,
            chains = 2,
            chain_initials = nonfinite_chain_initials,
            seed = controls.seed,
        )
    nonfinite_logdensity_initials = repeat(reshape(initial, 1, :), 2, 1)
    nonfinite_logdensity_initials[2, end] = 1e308
    @test_throws ArgumentError BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_sample_bundle(
            candidate,
            initial;
            ndraws = 1,
            warmup = 0,
            chains = 2,
            chain_initials = nonfinite_logdensity_initials,
            seed = controls.seed,
        )
    @test_throws ArgumentError BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_sample_bundle(
            candidate,
            initial;
            ndraws = 1,
            warmup = 0,
            chains = 2,
            chain_initials = repeat(reshape(initial, 1, :), 2, 1),
            init_jitter = 0.01,
            seed = controls.seed,
        )

    signed_chain_initials = repeat(reshape(initial, 1, :), 2, 1)
    signed_chain_initials[1, candidate.blueprint.zrho_index] = atanh(-0.25)
    signed_chain_initials[2, candidate.blueprint.zrho_index] = atanh(0.25)
    no_warmup = BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_sample_bundle(
            candidate,
            initial;
            ndraws = 2,
            warmup = 0,
            chains = 2,
            step_size = 0.001,
            seed = controls.seed + 1,
            max_depth = 2,
            metric = :unit,
            chain_initials = signed_chain_initials,
        )
    @test no_warmup.sampler_controls.warmup == 0
    @test no_warmup.sampler_controls.chain_initial_policy === :explicit_matrix
    @test no_warmup.sampler_controls.chain_initials_supplied
    @test no_warmup.summary.total_draws == 4
    @test no_warmup.summary.sampler_stats_length_valid
    @test no_warmup.summary.sampler_telemetry_valid
    @test no_warmup.summary.logdensity_revalidation_passed
    @test no_warmup.summary.passed
    @test no_warmup.diagnostic_status === :not_evaluable_smoke
    @test !no_warmup.convergence_evaluated
    @test size(no_warmup.chain_initials) == (2, nparams)
    @test no_warmup.chain_initials == signed_chain_initials
    @test tanh(no_warmup.chain_initials[
        1,
        candidate.blueprint.zrho_index,
    ]) < 0
    @test tanh(no_warmup.chain_initials[
        2,
        candidate.blueprint.zrho_index,
    ]) > 0
    @test no_warmup.chain_initial_logdensity == [
        LogDensityProblems.logdensity(candidate, @view no_warmup.chain_initials[chain, :])
        for chain in 1:2
    ]
end
