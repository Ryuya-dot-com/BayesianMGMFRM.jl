using Test
using Random
using BayesianMGMFRM
using LinearAlgebra
using ForwardDiff

@testset "generalized product-one constraints at finite extremes (no fitting)" begin
    cells = [(p, i, r) for p in 1:2 for i in 1:5 for r in 1:5]
    data = FacetData((;
            person = ["P$p" for (p, i, r) in cells],
            item = ["I$i" for (p, i, r) in cells],
            rater = ["R$r" for (p, i, r) in cells],
            score = [mod(p + i + r, 3) for (p, i, r) in cells],
        ); person = :person, item = :item, rater = :rater, score = :score,
        category_levels = 0:2)
    for family in (:gmfrm, :mgmfrm)
        spec = family === :gmfrm ?
            mfrm_spec(data; family, thresholds = :partial_credit, discrimination = :rater) :
            mfrm_spec(data; family, thresholds = :partial_credit, dimensions = 2,
                q_matrix = Bool[1 0; 1 0; 1 0; 0 1; 0 1])
        target = family === :gmfrm ?
            BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(spec) :
            BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(spec)
        raw_block = target.blueprint.blocks[family === :gmfrm ?
            :log_item_discrimination_free : :log_rater_consistency_free]
        direct_block = target.design.blocks[family === :gmfrm ?
            :item_discrimination : :rater_consistency]
        constraint_rows = family === :gmfrm ?
            BayesianMGMFRM._gmfrm_direct_constraint_rows :
            BayesianMGMFRM._mgmfrm_direct_constraint_rows
        probabilities = family === :gmfrm ?
            BayesianMGMFRM._gmfrm_predictive_probabilities_direct :
            BayesianMGMFRM._mgmfrm_predictive_probabilities_direct
        product_constraint = family === :gmfrm ?
            :item_discrimination_product_one : :rater_consistency_product_one
        for log_values in ([400.0, 400.0, -400.0, -400.0],
                [-400.0, -400.0, 400.0, 400.0], [400.0, -400.0, 400.0, -400.0])
            raw = initial_params(target)
            raw[raw_block] .= log_values
            direct = BayesianMGMFRM._guarded_generalized_direct_params(target, raw)
            values = direct[direct_block]
            @test all(isfinite, values)
            # Independent high-precision multiplication checks the constraint;
            # ordinary multiplication can overflow/underflow in this ordering.
            reference_product = Float64(prod(BigFloat.(values)))
            @test reference_product ≈ 1.0 atol = 1e-12
            rows = constraint_rows(target.design, direct)
            @test all(row.passed for row in rows)
            @test only(row for row in rows if row.constraint === product_constraint).value ≈
                reference_product atol = 1e-12
            @test BayesianMGMFRM._source_fixture_loglikelihood(target, raw) ≈
                -data.n * log(3)
            @test all(probability -> probability ≈ 1 / 3,
                probabilities(target.design, reshape(direct, 1, :)))
            gradient = ForwardDiff.gradient(
                x -> BayesianMGMFRM._source_fixture_logposterior(target, x), raw)
            @test all(isfinite, gradient)
            sd = BayesianMGMFRM._source_fixture_prior_sd(target, first(raw_block))
            @test gradient[raw_block] ≈ -log_values ./ sd^2

            for invalid in (2values[1], 0.0, -values[1], Inf, NaN)
                bad = copy(direct)
                bad[first(direct_block)] = invalid
                @test_throws ArgumentError probabilities(
                    target.design, reshape(bad, 1, :))
                bad_rows = constraint_rows(target.design, bad)
                @test !only(row for row in bad_rows if row.constraint === product_constraint).passed
            end
        end
    end
end

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

    @testset "MGMFRM actual ability-prior reporting (no fitting)" begin
        design = BayesianMGMFRM.Experimental.preview(mgmfrm_spec)
        ability_row(rows) = only(row for row in rows if row.policy === :ability_scale)
        unrecorded = ability_row(BayesianMGMFRM._mgmfrm_fixed_q_invariance_rows(design))
        @test unrecorded.status === :not_recorded
        @test ismissing(unrecorded.value) && ismissing(unrecorded.passed)
        @test ismissing(unrecorded.prior.sd)

        for person_sd in (1.0, 2.0, 0.5)
            prior = BayesianMGMFRM._source_fixture_prior(
                BayesianMGMFRM.Experimental.GeneralizedPrior(; person_sd))
            target = BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(design; prior)
            initial = initial_params(target)
            # Deterministic reporting input, not posterior draws or convergence evidence.
            draws = [initial[p] + 0.01 * sin(d + p) for d in 1:4, p in eachindex(initial)]
            logdensities = [BayesianMGMFRM._source_fixture_logposterior(target, row)
                for row in eachrow(draws)]
            controls = (; ndraws = 4, chains = 1, warmup = 0, step_size = 0.1,
                max_depth = 2, init_jitter = 0.0)
            iterations = collect(1:4)
            sampler_stats = [BayesianMGMFRM._advancedhmc_stat_row(
                (; log_density = logdensities[d], step_size = 0.1), 1, d) for d in 1:4]
            sampler_rows = BayesianMGMFRM._generalized_candidate_sampler_rows(
                logdensities, iterations, [1.0], sampler_stats, controls, :fixture)
            run = (; checked = BayesianMGMFRM._check_diagnostic_thresholds(1.01, 400),
                nparams = length(initial), initial,
                initial_logdensity = BayesianMGMFRM._source_fixture_logposterior(target, initial),
                total_draws = 4, draws, logdensities, chain_ids = ones(Int, 4), iterations,
                chain_acceptance = [1.0], sampler_stats, controls, sampler_rows,
                backend = :fixture, sampler = :fixture,
                split_chains_requested = true, actual_split = false)
            surface = BayesianMGMFRM._mgmfrm_guarded_local_fit_diagnostic_surface(target, run)
            expected_scale = person_sd == 1.0 ? :standard_normal_by_dimension : :normal_by_dimension
            expected_status = person_sd == 1.0 ? :fixed_standard_normal_by_dimension : :fixed_normal_by_dimension
            expected_prior = (; distribution = :normal, mean = 0.0, sd = person_sd,
                independent_dimensions = true, conditioning = :fixed_prior_hyperparameters,
                status = :resolved_from_prior)
            stored_row = ability_row(surface.fixed_q_invariance_rows)
            @test (stored_row.value, stored_row.status, stored_row.passed, stored_row.prior) ==
                (expected_scale, expected_status, true, expected_prior)

            pointwise = BayesianMGMFRM._mgmfrm_confirmatory_candidate_pointwise_fixture(target, initial)
            unresolved = BayesianMGMFRM._mgmfrm_confirmatory_candidate_pointwise_fixture(
                design, surface.initial_direct_parameter_values)
            @test (pointwise.ability_scale, pointwise.ability_prior) == (expected_scale, expected_prior)
            @test ismissing(unresolved.ability_scale) && ismissing(unresolved.ability_prior.sd)
            @test pointwise.pointwise_loglikelihood == unresolved.pointwise_loglikelihood

            # Old stored scale rows must not override the prior attached to a fit.
            stale_surface = merge(surface, (; fixed_q_invariance_rows = [unrecorded]))
            fit = BayesianMGMFRM._mgmfrm_fit_from_sampler_diagnostics(design, prior, stale_surface)
            for view in (:full, :public)
                diagnostic = diagnostics(fit; view)
                artifact = fit_artifact(fit; view, include_environment = false)
                report = fit_report(fit; view, include_posterior_predictive = false,
                    include_grouped_predictive = false, include_calibration = false,
                    include_waic = false, include_loo = false, include_artifact = false,
                    on_section_error = :throw)
                for rows in (diagnostic.fixed_q_invariance_rows,
                        artifact.fixed_q_invariance_rows, report.q_matrix.fixed_q_invariance_rows)
                    row = ability_row(rows)
                    @test (row.value, row.status, row.passed, row.prior) ==
                        (expected_scale, expected_status, true, expected_prior)
                end
                @test (artifact.ability_scale, artifact.ability_prior) == (expected_scale, expected_prior)
                @test artifact.content_hash.value == artifact_content_hash(artifact)
                @test report.q_matrix.design_prior_scope === artifact.design_prior_scope ===
                    :source_reference_not_resolved_fit_prior
                @test only(row for row in report.prior_policy.rows if row.block === :person).scale == person_sd
            end
        end
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

@testset "MGMFRM raw-prior relabeling limitation (no fitting)" begin
    # Characterize the existing raw-coordinate policy, not an acceptance gate
    # for exchangeability. Revisit these expectations with any prior change.
    cells = [(p, i, r) for p in 1:2 for i in 1:4 for r in 1:3]
    scores = [r == 1 ? 1 : 2 + mod(p + i + r, 4) for (p, i, r) in cells]
    targets = map(((1, 2, 3), (3, 2, 1))) do permutation
        data = FacetData((;
                person = ["P$p" for (p, i, r) in cells],
                item = ["I$i" for (p, i, r) in cells],
                rater = ["R$(permutation[r])" for (p, i, r) in cells],
                score = scores,
            ); person = :person, item = :item, rater = :rater, score = :score,
            category_levels = 1:5)
        spec = mfrm_spec(data; family = :mgmfrm, dimensions = 2,
            thresholds = :partial_credit, discrimination = :none,
            q_matrix = Bool[1 0; 1 0; 0 1; 0 1])
        BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(spec)
    end
    @test targets[1].design.spec.data.category == targets[2].design.spec.data.category
    @test targets[1].design.spec.data.rater_levels == ["R1", "R2", "R3"]
    @test targets[2].design.spec.data.rater == 4 .- targets[1].design.spec.data.rater
    # The difference below is not just an additive normalization constant.
    @test BayesianMGMFRM._source_fixture_logposterior(targets[1], initial_params(targets[1])) ≈
        BayesianMGMFRM._source_fixture_logposterior(targets[2], initial_params(targets[2]))

    for (raw_block, direct_block) in ((:rater_free, :rater),
            (:log_rater_consistency_free, :rater_consistency))
        original, renamed = targets
        raw = initial_params(original)
        raw[original.blueprint.blocks[:person]] .= 0.2
        block = original.blueprint.blocks[raw_block]
        scale = BayesianMGMFRM._source_fixture_prior_sd(original, first(block))
        raw[block] .= scale
        relabeled = copy(raw)
        relabeled[renamed.blueprint.blocks[raw_block]] .= (-2scale, scale)
        direct = BayesianMGMFRM._guarded_generalized_direct_params(original, raw)
        renamed_direct = BayesianMGMFRM._guarded_generalized_direct_params(renamed, relabeled)
        @test renamed_direct[renamed.design.blocks[direct_block]] ≈
            reverse(direct[original.design.blocks[direct_block]])
        pointwise = BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood(
            original.design, direct)
        renamed_pointwise = BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood(
            renamed.design, renamed_direct)
        @test pointwise ≈ renamed_pointwise
        prior_delta = BayesianMGMFRM._source_fixture_logprior(renamed, relabeled) -
            BayesianMGMFRM._source_fixture_logprior(original, raw)
        @test prior_delta ≈ -1.5
        @test BayesianMGMFRM._source_fixture_logposterior(renamed, relabeled) -
            BayesianMGMFRM._source_fixture_logposterior(original, raw) ≈ prior_delta
        # Whole constrained-block quadratic penalties are permutation invariant;
        # the implemented prior omits the reconstructed coordinate's penalty.
        values = direct[original.design.blocks[direct_block]]
        renamed_values = renamed_direct[renamed.design.blocks[direct_block]]
        if direct_block === :rater_consistency
            values, renamed_values = log.(values), log.(renamed_values)
        end
        @test sum(abs2, values) ≈ sum(abs2, renamed_values)
    end
end

@testset "MGMFRM zero-sum prior measures (algebra only, no new prior)" begin
    for n in (2, 3, 5), sd in (0.5, 1.0, 2.0)
        identity_free = Matrix{Float64}(I, n - 1, n - 1)
        last_chart = hcat([BayesianMGMFRM._sum_to_zero_from_raw(column, n)
            for column in eachcol(identity_free)]...)
        @test diag(sd^2 * last_chart * last_chart') ≈
            sd^2 .* vcat(ones(n - 1), n - 1)

        # Stdlib basis of the zero-sum space: no production transform is added.
        basis = nullspace(ones(1, n))
        projection = Matrix{Float64}(I, n, n) - ones(n, n) / n
        covariance_free = sd^2 .* (identity_free - ones(n - 1, n - 1) / n)
        @test basis' * basis ≈ identity_free
        @test norm(basis' * ones(n)) < 1e-12
        @test basis * basis' ≈ projection
        @test last_chart * covariance_free * last_chart' ≈ sd^2 * projection
        marginal_covariance = sd^2 * n / (n - 1) .* (basis * basis')
        @test diag(marginal_covariance) ≈ fill(sd^2, n)
        @test marginal_covariance[end:-1:1, end:-1:1] ≈ marginal_covariance

        # Uto Appendix 1, p. 451: positive free consistencies, FIRST derived.
        # All-rater lognormal densities cancel their -sum(log(alpha)) terms,
        # but changing the density to free-log coordinates contributes +sum(z).
        full_logs(z) = vcat(-sum(z), z)
        source_logdensity(z) = sum(BayesianMGMFRM._normal_logpdf(log(alpha), sd) - log(alpha)
            for alpha in exp.(full_logs(z))) + sum(z)
        mean_free = covariance_free * ones(n - 1)
        reference(z) = -dot(z - mean_free, covariance_free \ (z - mean_free)) / 2
        zero_free = zeros(n - 1)
        z = fill(0.4, n - 1)
        @test full_logs(mean_free) ≈ sd^2 / n .* vcat(-(n - 1), ones(n - 1))
        # The density difference can be exactly zero; allow floating-point cancellation.
        @test source_logdensity(z) - source_logdensity(zero_free) ≈
            reference(z) - reference(zero_free) atol = 1e-12
        relabeled = reverse(full_logs(z))
        @test sum(abs2, relabeled) ≈ sum(abs2, full_logs(z))
        @test source_logdensity(relabeled[2:end]) - source_logdensity(z) ≈ -0.4n
    end
end
