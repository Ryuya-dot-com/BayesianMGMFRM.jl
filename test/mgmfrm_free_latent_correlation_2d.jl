using LogDensityProblems
using Test
using BayesianMGMFRM

function _free_correlation_test_data()
    people = String[]
    raters = String[]
    items = String[]
    scores = Int[]
    item_levels = ["I1", "I2", "I3", "I4"]
    score_patterns = (
        [0, 1, 2, 1],
        [1, 2, 1, 0],
        [2, 1, 0, 2],
        [1, 0, 2, 1],
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

function _free_correlation_category_test_data(n_categories::Int)
    people = String[]
    raters = String[]
    items = String[]
    scores = Int[]
    item_levels = ["I1", "I2", "I3", "I4"]
    for person in 1:4
        for item in 1:4
            push!(people, "P$person")
            push!(raters, isodd(person + item) ? "R1" : "R2")
            push!(items, item_levels[item])
            push!(scores, mod(person + item - 2, n_categories))
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

function _free_correlation_two_item_data()
    return FacetData(
        (;
            person = repeat(["P1", "P2", "P3", "P4"]; inner = 2),
            rater = ["R1", "R2", "R2", "R1", "R1", "R2", "R2", "R1"],
            item = repeat(["I1", "I2"], 4),
            score = [0, 1, 1, 2, 2, 0, 1, 2],
        );
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

function _free_correlation_incomplete_person_data()
    return FacetData(
        (;
            person = [
                "P1", "P1", "P1", "P1",
                "P2", "P2",
                "P3", "P3", "P3", "P3",
            ],
            rater = [
                "R1", "R2", "R1", "R2",
                "R1", "R2",
                "R2", "R1", "R2", "R1",
            ],
            item = [
                "I1", "I2", "I3", "I4",
                "I1", "I3",
                "I1", "I2", "I3", "I4",
            ],
            score = [0, 1, 2, 1, 1, 2, 2, 1, 0, 2],
        );
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

@testset "quarantined MGMFRM 2D free latent correlation" begin
    experimental = BayesianMGMFRM.Experimental
    data = _free_correlation_test_data()
    spec = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = Bool[1 0; 0 1; 1 0; 0 1],
        dimension_labels = ["analytic", "verbal"],
    )

    contract = experimental.free_latent_correlation_2d_contract()
    @test contract.scope === :mgmfrm_2d_free_latent_correlation_candidate
    @test contract.dimensions == 2
    @test contract.q_matrix === :fixed_simple_structure
    @test contract.minimum_pure_items_per_dimension == 2
    @test contract.person_dimension_observation_coverage === :complete
    @test contract.kernel_discrimination === :q_masked_item_dimension
    @test contract.latent_correlation === :free_tanh_coordinate
    @test contract.latent_correlation_prior === :normalized_lkj_2d
    @test contract.default_lkj_eta == 2
    @test contract.maximum_lkj_eta == 10_000
    @test !contract.fit_enabled
    @test !contract.cache_enabled
    @test contract.sampler_smoke_enabled
    @test contract.sampler_smoke_claim_scope ===
        :execution_smoke_not_recovery
    @test contract.oracle_profile_enabled
    @test contract.oracle_profile_claim_scope ===
        :oracle_complete_latent_profile_not_response_recovery
    @test contract.known_truth_fixture_enabled
    @test contract.known_truth_fixture_claim_scope ===
        :response_level_dgp_not_recovery
    @test contract.recovery_pilot_enabled
    @test contract.recovery_pilot_modes == (:diagnostic_smoke, :scientific)
    @test contract.recovery_pilot_sampler_defaults == (;
        max_depth = 10,
        metric = :diagonal,
    )
    @test contract.scientific_pilot_minimum == (;
        chains = 4,
        warmup_per_chain = 500,
        draws_per_chain = 500,
    )
    @test contract.end_to_end_response_recovery_status ===
        :internal_single_dataset_pilot_available
    @test contract.reproducibility_archive_status ===
        :pending_closed_set_refresh
    @test contract.replicated_study_status ===
        :frozen_v2_plan_preexecution_controls_and_deterministic_scoring_scientific_execution_not_started
    @test contract.replicated_study_plan_fingerprint ==
        "d3f39355bf16c8ae984b58f5b2c52b5ab81ccbbe26a68379e31d0281b2beb4e3"
    @test contract.replicated_study_unit_roster_sha256 ==
        "0c4939ab76a0e5f78c2dd13896446c51a7faecdff65288b5b94c9c957cc62d08"
    @test contract.replicated_study_scientific_mcmc_units_executed == 0
    @test contract.replicated_study_run_unit_entrypoint_preflight_only
    @test !contract.
        replicated_study_run_unit_entrypoint_scientific_execution_enabled
    @test !contract.replicated_study_frozen_plan_resource_probe_completed
    @test !contract.replicated_study_short_nuts_resource_profile_completed
    @test contract.replicated_study_preexecution_archive_runner_enabled
    @test !contract.
        replicated_study_preexecution_archive_runner_scientific_execution_enabled
    @test !contract.replicated_study_atomic_scientific_worker_ready
    @test !contract.
        replicated_study_preload_immutable_source_snapshot_ready
    @test !contract.
        replicated_study_independently_recalculable_raw_draw_archive_ready
    @test !contract.replicated_study_operational_execution_authorized
    @test !contract.replicated_study_scientific_execution_authorized
    @test contract.replicated_study_scientific_execution_required_gates ==
        (:protocol, :operational, :atomic_archive_receipt)
    @test contract.next_gate ===
        :initial_gradient_resource_probe_then_short_nuts_profile_and_atomic_runner
    @test contract.promotion_effect === :none
    @test experimental.surface_contract().candidate_surfaces.
        mgmfrm_free_latent_correlation_2d == contract
    @test experimental.surface_contract(:mgmfrm).latent_correlation ===
        :identity_fixed
    @test :free_latent_correlation_2d_candidate ∉ names(experimental)

    candidate = experimental.free_latent_correlation_2d_candidate(
        spec;
        lkj_eta = 2,
    )
    base = candidate.base
    @test candidate.blueprint.scope ===
        :mgmfrm_2d_free_latent_correlation_candidate
    @test candidate.blueprint.status ===
        :internal_free_latent_correlation_candidate
    @test !candidate.blueprint.public_fit
    @test !candidate.blueprint.fit_ready
    @test !candidate.blueprint.cache_enabled
    @test LogDensityProblems.dimension(candidate) ==
        LogDensityProblems.dimension(base) + 1
    @test candidate.blueprint.base_parameter_range ==
        1:LogDensityProblems.dimension(base)
    @test candidate.blueprint.zrho_index ==
        LogDensityProblems.dimension(candidate)
    @test candidate.blueprint.parameter_names[1:end-1] ==
        base.blueprint.parameter_names
    @test candidate.blueprint.parameter_names[end] ==
        "z_latent_correlation[analytic,verbal]"
    @test candidate.blueprint.blocks[:z_latent_correlation] ==
        candidate.blueprint.zrho_index:candidate.blueprint.zrho_index
    @test occursin("public_fit = false", sprint(show, candidate))

    initialized = initial_params(candidate; value = 0.1, zrho = 0.35)
    @test initialized[1:end-1] == fill(
        0.1,
        LogDensityProblems.dimension(base),
    )
    @test initialized[end] == 0.35
    @test_throws ArgumentError initial_params(candidate; zrho = true)
    @test_throws ArgumentError initial_params(candidate; zrho = Inf)

    base_raw = collect(range(
        -0.3,
        0.3;
        length = LogDensityProblems.dimension(base),
    ))
    person_block = base.blueprint.blocks[:person]
    base_raw[person_block] .= [
        0.4, -0.2,
        -0.1, 0.3,
        0.25, 0.15,
        -0.35, -0.05,
    ]
    raw = vcat(base_raw, 0.35)
    state = experimental.free_latent_correlation_2d_state(candidate, raw)
    @test state.parameterization === :tanh_unconstrained
    @test state.zrho == 0.35
    @test state.rho ≈ tanh(0.35)
    @test state.correlation_matrix == [1.0 state.rho; state.rho 1.0]
    @test 1 - state.rho^2 > 0
    @test !state.numerically_saturated
    @test state.log_determinant ≈ log(1 - state.rho^2)
    @test state.lkj_eta == 2

    base_likelihood = BayesianMGMFRM._source_fixture_loglikelihood(
        base,
        base_raw,
    )
    candidate_likelihood = BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_loglikelihood(candidate, raw)
    @test candidate_likelihood == base_likelihood
    pointwise = BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_pointwise_loglikelihood(
            candidate,
            raw,
        )
    @test length(pointwise) == data.n
    @test sum(pointwise; init = 0.0) == candidate_likelihood

    # The scalar sampler kernel is a construction-time integer layout.  Its
    # optimized likelihood must remain numerically identical to the unchanged
    # source-aligned pointwise/reference path across raw perturbations.
    @test candidate.scalar_kernel.n_categories == 3
    @test length(candidate.scalar_kernel.observed_category) == data.n
    for scale in (-0.19, 0.07, 0.23)
        perturbed = copy(raw)
        for index in candidate.blueprint.base_parameter_range
            perturbed[index] += scale * sin(index)
        end
        perturbed[candidate.blueprint.zrho_index] = scale
        perturbed_base =
            @view perturbed[candidate.blueprint.base_parameter_range]
        reference_likelihood = BayesianMGMFRM._source_fixture_loglikelihood(
            base,
            perturbed_base,
        )
        scalar_likelihood = BayesianMGMFRM.
            _mgmfrm_free_latent_correlation_2d_loglikelihood(
                candidate,
                perturbed,
            )
        reference_pointwise = BayesianMGMFRM.
            _mgmfrm_free_latent_correlation_2d_pointwise_loglikelihood(
                candidate,
                perturbed,
            )
        @test abs(scalar_likelihood - reference_likelihood) <= 1e-10
        @test abs(
            scalar_likelihood - sum(reference_pointwise; init = 0.0),
        ) <= 1e-10
    end

    fast_likelihood_gradient = BayesianMGMFRM.ForwardDiff.gradient(
        values -> BayesianMGMFRM.
            _mgmfrm_free_latent_correlation_2d_loglikelihood(
                candidate,
                values,
            ),
        raw,
    )
    reference_likelihood_gradient = BayesianMGMFRM.ForwardDiff.gradient(
        values -> BayesianMGMFRM._source_fixture_loglikelihood(
            base,
            @view(values[candidate.blueprint.base_parameter_range]),
        ),
        raw,
    )
    @test maximum(abs.(
        fast_likelihood_gradient .- reference_likelihood_gradient,
    )) <= 1e-10

    for n_categories in (2, 4)
        category_data = _free_correlation_category_test_data(n_categories)
        category_spec = mfrm_spec(
            category_data;
            family = :mgmfrm,
            dimensions = 2,
            thresholds = :partial_credit,
            discrimination = :none,
            q_matrix = Bool[1 0; 0 1; 1 0; 0 1],
        )
        category_candidate =
            experimental.free_latent_correlation_2d_candidate(category_spec)
        category_base = category_candidate.base
        category_raw = vcat(
            collect(range(
                -0.25,
                0.25;
                length = LogDensityProblems.dimension(category_base),
            )),
            -0.2,
        )
        @test category_candidate.scalar_kernel.n_categories == n_categories
        @test category_candidate.scalar_kernel.free_steps_per_item ==
            max(n_categories - 2, 0)
        for scale in (-0.11, 0.0, 0.17)
            perturbed = category_raw .+
                scale .* cos.(eachindex(category_raw))
            category_base_raw = @view perturbed[
                category_candidate.blueprint.base_parameter_range
            ]
            reference_likelihood =
                BayesianMGMFRM._source_fixture_loglikelihood(
                    category_base,
                    category_base_raw,
                )
            scalar_likelihood = BayesianMGMFRM.
                _mgmfrm_free_latent_correlation_2d_loglikelihood(
                    category_candidate,
                    perturbed,
                )
            @test abs(scalar_likelihood - reference_likelihood) <= 1e-10
        end
    end

    overflow_raw = copy(raw)
    overflow_raw[first(
        base.blueprint.blocks[:log_item_dimension_discrimination],
    )] = 1_000.0
    @test_throws ArgumentError BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_loglikelihood(
            candidate,
            overflow_raw,
        )
    @test_throws ArgumentError BayesianMGMFRM._source_fixture_loglikelihood(
        base,
        @view(overflow_raw[candidate.blueprint.base_parameter_range]),
    )

    for (eta, expected_difference) in (
            (1, -log(2.0)),
            (2, log(3.0 / 4.0)))
        eta_candidate =
            experimental.free_latent_correlation_2d_candidate(spec; lkj_eta = eta)
        raw_zero = vcat(base_raw, 0.0)
        actual_difference = LogDensityProblems.logdensity(
            eta_candidate,
            raw_zero,
        ) - LogDensityProblems.logdensity(eta_candidate.base, base_raw)
        @test actual_difference ≈ expected_difference atol = 2e-13 rtol = 0
        @test -eta_candidate.prior.log_beta_half_eta ≈
            expected_difference atol = 2e-13 rtol = 0

        grid = range(-12.0, 12.0; length = 12_001)
        density = exp.(BayesianMGMFRM._lkj2_zrho_logpdf.(
            grid,
            Ref(eta_candidate.prior),
        ))
        spacing = step(grid)
        integral = spacing * (
            sum(density; init = 0.0) -
            0.5 * density[1] -
            0.5 * density[end]
        )
        @test integral ≈ 1.0 atol = 2e-9 rtol = 0
    end

    raw_zero = vcat(base_raw, 0.0)
    gradient_zero = BayesianMGMFRM.ForwardDiff.gradient(
        x -> LogDensityProblems.logdensity(candidate, x),
        raw_zero,
    )
    expected_zrho_gradient = sum(
        base_raw[index] * base_raw[index + 1] /
            candidate.prior.source_prior.person_sd^2
        for index in first(person_block):2:last(person_block)
    )
    @test gradient_zero[end] ≈ expected_zrho_gradient atol = 2e-12 rtol = 2e-12

    huge_u = 1e154
    moderate_zrho = 0.1
    aligned_u2 = tanh(moderate_zrho) * huge_u
    moderate_conditional = BayesianMGMFRM._correlated_conditional_square(
        huge_u,
        aligned_u2,
        moderate_zrho,
    )
    @test iszero(moderate_conditional)
    moderate_logpdf = BayesianMGMFRM._correlated_person_2d_logpdf(
        huge_u,
        aligned_u2,
        1.0,
        moderate_zrho,
    )
    moderate_expected = -log(2pi) -
        0.5 * log1p(-tanh(moderate_zrho)^2) -
        0.5 * huge_u^2
    @test isfinite(moderate_logpdf)
    @test moderate_logpdf != Inf
    @test moderate_logpdf ≈ moderate_expected rtol = 2e-13

    saturated_zrho = 400.0
    saturated_conditional = BayesianMGMFRM._correlated_conditional_square(
        huge_u,
        huge_u,
        saturated_zrho,
    )
    saturated_expected_conditional =
        0.25 * exp(2log(2huge_u) - 2saturated_zrho)
    @test isfinite(saturated_conditional)
    @test saturated_conditional >= 0
    @test saturated_conditional ≈ saturated_expected_conditional rtol = 2e-13
    saturated_logpdf = BayesianMGMFRM._correlated_person_2d_logpdf(
        huge_u,
        huge_u,
        1.0,
        saturated_zrho,
    )
    saturated_expected = -log(2pi) + saturated_zrho +
        log1p(exp(-2saturated_zrho)) - log(2.0) -
        0.5 * (huge_u^2 + saturated_expected_conditional)
    @test isfinite(saturated_logpdf)
    @test saturated_logpdf != Inf
    @test saturated_logpdf ≈ saturated_expected rtol = 2e-13

    for (checked_u1, checked_u2, checked_zrho) in (
            (9e153, 9e153, 0.1),
            (8e153, 8e153, 0.0),
            (9e153, -9e153, -0.1))
        reference = setprecision(BigFloat, 256) do
            big_u1 = BigFloat(checked_u1)
            big_zrho = BigFloat(checked_zrho)
            conditional = big_u1^2 * exp(-2abs(big_zrho))
            log_normalizer = abs(big_zrho) +
                log1p(exp(-2abs(big_zrho))) - log(BigFloat(2))
            logpdf = -log(BigFloat(2) * BigFloat(pi)) +
                log_normalizer -
                BigFloat(0.5) * (big_u1^2 + conditional)
            (; conditional = Float64(conditional), logpdf = Float64(logpdf))
        end
        conditional = BayesianMGMFRM._correlated_conditional_square(
            checked_u1,
            checked_u2,
            checked_zrho,
        )
        logpdf = BayesianMGMFRM._correlated_person_2d_logpdf(
            checked_u1,
            checked_u2,
            1.0,
            checked_zrho,
        )
        @test isfinite(conditional)
        @test conditional ≈ reference.conditional rtol = 5e-14
        @test isfinite(logpdf)
        @test logpdf ≈ reference.logpdf rtol = 2e-13
    end
    overflow_regression_reference = setprecision(BigFloat, 256) do
        big_u = BigFloat(9e153)
        big_zrho = BigFloat(0.1)
        conditional = big_u^2 * exp(-2big_zrho)
        log_normalizer = big_zrho + log1p(exp(-2big_zrho)) -
            log(BigFloat(2))
        logpdf = -log(BigFloat(2) * BigFloat(pi)) + log_normalizer -
            BigFloat(0.5) * (big_u^2 + conditional)
        (; conditional = Float64(conditional), logpdf = Float64(logpdf))
    end
    @test overflow_regression_reference.conditional ≈
        6.631719099931653e307 rtol = 2e-15
    @test overflow_regression_reference.logpdf ≈
        -7.365859549965827e307 rtol = 2e-15

    for (checked_u, checked_zrho) in (
            (1e154, 0.1),
            (1e154, 0.0),
            (1.2e154, 0.1),
            (1.2e154, 0.0))
        reference = setprecision(BigFloat, 256) do
            big_u = BigFloat(checked_u)
            big_zrho = BigFloat(checked_zrho)
            rho = tanh(big_zrho)
            delta = 1 - rho^2
            residual = big_u - rho * big_u
            conditional = residual^2 / delta
            logpdf = -log(BigFloat(2) * BigFloat(pi)) -
                BigFloat(0.5) * log(delta) -
                BigFloat(0.5) * (big_u^2 + conditional)
            gradient = BigFloat[
                -big_u + rho * residual / delta,
                -residual / delta,
                rho + residual * big_u - rho * conditional,
            ]
            (;
                conditional = Float64(conditional),
                logpdf = Float64(logpdf),
                gradient = Float64.(gradient),
            )
        end
        point = [checked_u, checked_u, checked_zrho]
        conditional = BayesianMGMFRM._correlated_conditional_square(
            point...,
        )
        logpdf = BayesianMGMFRM._correlated_person_2d_logpdf(
            point[1], point[2], 1.0, point[3],
        )
        gradient = BayesianMGMFRM.ForwardDiff.gradient(
            values -> BayesianMGMFRM._correlated_person_2d_logpdf(
                values[1], values[2], 1.0, values[3],
            ),
            point,
        )
        @test isfinite(conditional)
        @test conditional ≈ reference.conditional rtol = 3e-13
        @test isfinite(logpdf)
        @test logpdf ≈ reference.logpdf rtol = 3e-13
        @test all(isfinite, gradient)
        for index in eachindex(gradient)
            @test isapprox(
                gradient[index],
                reference.gradient[index];
                rtol = 3e-12,
                atol = 1e-14,
            )
        end
    end

    weighted_only_reference = setprecision(BigFloat, 256) do
        big_u = BigFloat(1e154)
        big_zrho = BigFloat(-0.3)
        rho = tanh(big_zrho)
        delta = 1 - rho^2
        conditional = (big_u - rho * big_u)^2 / delta
        logpdf = -log(BigFloat(2) * BigFloat(pi)) -
            BigFloat(0.5) * log(delta) -
            BigFloat(0.5) * (big_u^2 + conditional)
        (; conditional = Float64(conditional), logpdf = Float64(logpdf))
    end
    @test isinf(weighted_only_reference.conditional)
    weighted_only_logpdf = BayesianMGMFRM._correlated_person_2d_logpdf(
        1e154,
        1e154,
        1.0,
        -0.3,
    )
    @test isfinite(weighted_only_logpdf)
    @test weighted_only_logpdf ≈ weighted_only_reference.logpdf rtol = 3e-13

    for (checked_u1, checked_u2, checked_zrho) in (
            (1.0, nextfloat(1.0), 18.256828509181442),
            (1.0, nextfloat(1.0), 19.0),
            (1.0, nextfloat(1.0), 20.0),
            (1.0, -nextfloat(1.0), -18.256828509181442),
            (1.0, -nextfloat(1.0), -19.0),
            (1.0, -nextfloat(1.0), -20.0))
        reference = setprecision(BigFloat, 256) do
            big_u1 = BigFloat(checked_u1)
            big_u2 = BigFloat(checked_u2)
            big_zrho = BigFloat(checked_zrho)
            rho = tanh(big_zrho)
            delta = 1 - rho^2
            residual = big_u2 - rho * big_u1
            conditional = residual^2 / delta
            logpdf = -log(BigFloat(2) * BigFloat(pi)) -
                BigFloat(0.5) * log(delta) -
                BigFloat(0.5) * (big_u1^2 + conditional)
            gradient = BigFloat[
                -big_u1 + rho * residual / delta,
                -residual / delta,
                rho + residual * big_u1 - rho * conditional,
            ]
            (;
                conditional = Float64(conditional),
                logpdf = Float64(logpdf),
                gradient = Float64.(gradient),
            )
        end
        point = [checked_u1, checked_u2, checked_zrho]
        conditional = BayesianMGMFRM._correlated_conditional_square(
            point...,
        )
        logpdf = BayesianMGMFRM._correlated_person_2d_logpdf(
            point[1], point[2], 1.0, point[3],
        )
        gradient = BayesianMGMFRM.ForwardDiff.gradient(
            values -> BayesianMGMFRM._correlated_person_2d_logpdf(
                values[1], values[2], 1.0, values[3],
            ),
            point,
        )
        @test conditional ≈ reference.conditional rtol = 2e-12 atol = 0
        @test logpdf ≈ reference.logpdf rtol = 2e-13 atol = 2e-14
        @test all(isfinite, gradient)
        for index in eachindex(gradient)
            @test isapprox(
                gradient[index],
                reference.gradient[index];
                rtol = 2e-12,
                atol = 2e-14,
            )
        end
        if checked_zrho == 20.0
            @test reference.conditional ≈
                3.127640375941901e-15 rtol = 2e-15
            @test reference.gradient[1] ≈ 12.566507145 rtol = 2e-11
            @test reference.gradient[2] ≈ -13.566507145 rtol = 2e-11
        end
    end

    switch_lower = 9.357486931971325
    switch_upper = nextfloat(switch_lower)
    @test 1 - tanh(switch_lower) > sqrt(eps(1.0))
    @test 1 - tanh(switch_upper) <= sqrt(eps(1.0))
    switch_tolerance = 4sqrt(eps(1.0))
    for checked_zrho in (
            switch_lower,
            switch_upper,
            -switch_lower,
            -switch_upper)
        checked_u1 = 1.0
        checked_u2 = checked_zrho > 0 ? nextfloat(1.0) : -nextfloat(1.0)
        reference = setprecision(BigFloat, 256) do
            big_u1 = BigFloat(checked_u1)
            big_u2 = BigFloat(checked_u2)
            big_zrho = BigFloat(checked_zrho)
            rho = tanh(big_zrho)
            delta = 1 - rho^2
            residual = big_u2 - rho * big_u1
            conditional = residual^2 / delta
            logpdf = -log(BigFloat(2) * BigFloat(pi)) -
                BigFloat(0.5) * log(delta) -
                BigFloat(0.5) * (big_u1^2 + conditional)
            gradient = BigFloat[
                -big_u1 + rho * residual / delta,
                -residual / delta,
                rho + residual * big_u1 - rho * conditional,
            ]
            (;
                conditional = Float64(conditional),
                logpdf = Float64(logpdf),
                gradient = Float64.(gradient),
            )
        end
        point = [checked_u1, checked_u2, checked_zrho]
        conditional = BayesianMGMFRM._correlated_conditional_square(point...)
        logpdf = BayesianMGMFRM._correlated_person_2d_logpdf(
            point[1], point[2], 1.0, point[3],
        )
        gradient = BayesianMGMFRM.ForwardDiff.gradient(
            values -> BayesianMGMFRM._correlated_person_2d_logpdf(
                values[1], values[2], 1.0, values[3],
            ),
            point,
        )
        @test isapprox(
            conditional,
            reference.conditional;
            rtol = switch_tolerance,
            atol = 0,
        )
        @test isapprox(
            logpdf,
            reference.logpdf;
            rtol = switch_tolerance,
            atol = 0,
        )
        for index in eachindex(gradient)
            @test isapprox(
                gradient[index],
                reference.gradient[index];
                rtol = switch_tolerance,
                atol = switch_tolerance * eps(1.0),
            )
        end
    end

    for (checked_zrho, checked_u2) in (
            (moderate_zrho, aligned_u2),
            (saturated_zrho, huge_u))
        huge_raw = initial_params(candidate)
        huge_raw[first(person_block)] =
            candidate.prior.source_prior.person_sd * huge_u
        huge_raw[first(person_block) + 1] =
            candidate.prior.source_prior.person_sd * checked_u2
        huge_raw[candidate.blueprint.zrho_index] = checked_zrho
        @test all(isfinite, huge_raw)
        @test isfinite(LogDensityProblems.logdensity(candidate, huge_raw))
    end

    for (checked_zrho, checked_u) in (
            (17.0, 1.0),
            (17.5, 1.0),
            (18.0, 1.0),
            (18.1, 1.0),
            (18.2, 1.0),
            (19.0, 1.0),
            (20.0, 1.0),
            (400.0, huge_u))
        point = [checked_u, checked_u, checked_zrho]
        gradient = BayesianMGMFRM.ForwardDiff.gradient(
            values -> BayesianMGMFRM._correlated_person_2d_logpdf(
                values[1],
                values[2],
                1.0,
                values[3],
            ),
            point,
        )
        tail = exp(-2checked_zrho)
        stable_rho = (1 - tail) / (1 + tail)
        conditional = exp(2log(checked_u) - 2checked_zrho)
        expected = [
            -checked_u / (1 + stable_rho),
            -checked_u / (1 + stable_rho),
            stable_rho + conditional,
        ]
        @test isfinite(BayesianMGMFRM._correlated_person_2d_logpdf(
            point[1], point[2], 1.0, point[3],
        ))
        @test BayesianMGMFRM._correlated_conditional_square(point...) ≈
            conditional rtol = 3e-13 atol = 0
        @test all(isfinite, gradient)
        for index in eachindex(gradient)
            @test gradient[index] ≈ expected[index] rtol = 3e-13 atol = 1e-14
        end
    end

    for (checked_zrho, checked_u) in (
            (-17.0, 1.0),
            (-17.5, 1.0),
            (-18.0, 1.0),
            (-18.1, 1.0),
            (-18.2, 1.0),
            (-19.0, 1.0),
            (-20.0, 1.0),
            (-400.0, huge_u))
        point = [checked_u, -checked_u, checked_zrho]
        gradient = BayesianMGMFRM.ForwardDiff.gradient(
            values -> BayesianMGMFRM._correlated_person_2d_logpdf(
                values[1],
                values[2],
                1.0,
                values[3],
            ),
            point,
        )
        tail = exp(2checked_zrho)
        stable_rho = (tail - 1) / (tail + 1)
        conditional = exp(2log(checked_u) + 2checked_zrho)
        expected = [
            -checked_u / (1 - stable_rho),
            checked_u / (1 - stable_rho),
            stable_rho - conditional,
        ]
        @test isfinite(BayesianMGMFRM._correlated_person_2d_logpdf(
            point[1], point[2], 1.0, point[3],
        ))
        @test BayesianMGMFRM._correlated_conditional_square(point...) ≈
            conditional rtol = 3e-13 atol = 0
        @test all(isfinite, gradient)
        for index in eachindex(gradient)
            @test gradient[index] ≈ expected[index] rtol = 3e-13 atol = 1e-14
        end
    end

    for checked_zrho in (400.0, 800.0, 1000.0, -400.0, -800.0, -1000.0)
        checked_u1 = 1.0
        checked_u2 = checked_zrho > 0 ? 1.0 : -1.0
        reference = setprecision(BigFloat, 256) do
            big_zrho = BigFloat(checked_zrho)
            absolute_zrho = abs(big_zrho)
            tail = exp(-2absolute_zrho)
            one_plus_tail = 1 + tail
            stable_abs_rho = (1 - tail) / one_plus_tail
            conditional = tail
            log_normalizer = absolute_zrho + log1p(tail) -
                log(BigFloat(2))
            logpdf = -log(BigFloat(2) * BigFloat(pi)) +
                log_normalizer - BigFloat(0.5) * (1 + conditional)
            half_one_plus_tail = BigFloat(0.5) * one_plus_tail
            gradient = if checked_zrho > 0
                BigFloat[
                    -half_one_plus_tail,
                    -half_one_plus_tail,
                    stable_abs_rho + tail,
                ]
            else
                BigFloat[
                    -half_one_plus_tail,
                    half_one_plus_tail,
                    -stable_abs_rho - tail,
                ]
            end
            (;
                conditional = Float64(conditional),
                logpdf = Float64(logpdf),
                gradient = Float64.(gradient),
            )
        end
        point = [checked_u1, checked_u2, checked_zrho]
        conditional = BayesianMGMFRM._correlated_conditional_square(
            point...,
        )
        logpdf = BayesianMGMFRM._correlated_person_2d_logpdf(
            point[1], point[2], 1.0, point[3],
        )
        gradient = BayesianMGMFRM.ForwardDiff.gradient(
            values -> BayesianMGMFRM._correlated_person_2d_logpdf(
                values[1], values[2], 1.0, values[3],
            ),
            point,
        )
        @test conditional == reference.conditional
        @test isfinite(logpdf)
        @test logpdf ≈ reference.logpdf rtol = 2e-14 atol = 2e-13
        @test all(isfinite, gradient)
        for index in eachindex(gradient)
            @test isapprox(
                gradient[index],
                reference.gradient[index];
                rtol = 2e-13,
                atol = 2e-13,
            )
        end
    end

    for tiny_value in (1e-300, 1e-308, 1e-320, nextfloat(0.0))
        scaled_square_derivative = BayesianMGMFRM.ForwardDiff.derivative(
            value -> BayesianMGMFRM._zero_primal_scaled_square(value, 0.0),
            tiny_value,
        )
        @test isfinite(scaled_square_derivative)
        @test isapprox(
            scaled_square_derivative,
            tiny_value + tiny_value;
            rtol = 2e-13,
            atol = 0,
        )

        log_scale = log(1e-16)
        signed_scale_derivative = BayesianMGMFRM.ForwardDiff.derivative(
            value -> BayesianMGMFRM._signed_primal_log_scaled(
                value,
                log_scale,
            ),
            tiny_value,
        )
        @test isfinite(signed_scale_derivative)
        @test signed_scale_derivative ≈ exp(log_scale) rtol = 2e-15

        tiny_point = [0.0, tiny_value, 0.0]
        tiny_gradient = BayesianMGMFRM.ForwardDiff.gradient(
            values -> BayesianMGMFRM._correlated_person_2d_logpdf(
                values[1], values[2], 1.0, values[3],
            ),
            tiny_point,
        )
        @test all(isfinite, tiny_gradient)
        @test tiny_gradient[1] == 0.0
        @test isapprox(
            tiny_gradient[2],
            -tiny_value;
            rtol = 2e-13,
            atol = 0,
        )
        @test tiny_gradient[3] == 0.0
    end

    wide_scale_derivative = BayesianMGMFRM.ForwardDiff.derivative(
        value -> BayesianMGMFRM._zero_primal_scaled_square(
            value,
            log(1e-308),
        ),
        1e308,
    )
    @test isfinite(wide_scale_derivative)
    @test wide_scale_derivative ≈ 2.0 rtol = 1e-13
    minimum_subnormal = nextfloat(0.0)
    half_scale_derivative = BayesianMGMFRM.ForwardDiff.derivative(
        value -> BayesianMGMFRM._zero_primal_scaled_square(
            value,
            -log(2.0),
        ),
        minimum_subnormal,
    )
    @test half_scale_derivative == minimum_subnormal

    extreme_positive = BayesianMGMFRM._correlated_person_2d_logpdf(
        1.0,
        1.0,
        1.0,
        1000.0,
    )
    extreme_negative = BayesianMGMFRM._correlated_person_2d_logpdf(
        1.0,
        -1.0,
        1.0,
        -1000.0,
    )
    @test isfinite(extreme_positive)
    @test isfinite(extreme_negative)
    @test isfinite(BayesianMGMFRM.ForwardDiff.derivative(
        z -> BayesianMGMFRM._correlated_person_2d_logpdf(1.0, 1.0, 1.0, z),
        1000.0,
    ))
    @test isfinite(BayesianMGMFRM._correlated_person_2d_logpdf(
        0.0,
        1e-200,
        1.0,
        400.0,
    ))
    extreme_raw = vcat(base_raw, 1000.0)
    extreme_state = experimental.free_latent_correlation_2d_state(
        candidate,
        extreme_raw,
    )
    @test extreme_state.numerically_saturated
    @test ismissing(extreme_state.correlation_matrix)
    @test isfinite(extreme_state.log_determinant)

    for checked_raw in (raw_zero, raw)
        diagnostics = experimental.free_latent_correlation_2d_diagnostics(
            spec,
            checked_raw;
            lkj_eta = 2,
            finite_difference_coords = (1, 2, length(checked_raw)),
            finite_difference_eps = 1e-5,
            gradient_atol = 2e-5,
            gradient_rtol = 2e-5,
        )
        @test diagnostics.summary.passed
        @test diagnostics.likelihood_identity.passed
        @test diagnostics.likelihood_identity.abs_error == 0.0
        @test diagnostics.correlation.rho ≈ tanh(checked_raw[end])
        @test all(row -> row.passed, diagnostics.finite_difference_rows)
        @test !diagnostics.public_fit
        @test !diagnostics.cache_enabled
    end

    positive_oracle_raw = copy(base_raw)
    positive_oracle_raw[person_block] .= [
        -1.2, -0.9,
        -0.4, -0.1,
        0.4, 0.2,
        1.2, 0.9,
    ]
    negative_oracle_raw = copy(base_raw)
    negative_oracle_raw[person_block] .= [
        -1.2, 0.9,
        -0.4, 0.1,
        0.4, -0.2,
        1.2, -0.9,
    ]
    positive_oracle = experimental.free_latent_correlation_2d_oracle_profile(
        spec,
        positive_oracle_raw;
        lkj_eta = 2,
        truth_rho = 0.6,
    )
    negative_oracle = experimental.free_latent_correlation_2d_oracle_profile(
        spec,
        negative_oracle_raw;
        lkj_eta = 2,
        truth_rho = -0.6,
    )
    for oracle in (positive_oracle, negative_oracle)
        @test oracle.claim_scope ===
            :oracle_complete_latent_profile_not_response_recovery
        @test oracle.summary.profile_valid
        @test oracle.boundary_mass <= 1e-4
        @test !oracle.summary.response_recovery_verified
        @test oracle.summary.direction_matches_truth
        @test sum(oracle.weights; init = 0.0) ≈ 1.0 atol = 2e-14
        @test oracle.posterior.lower <= oracle.posterior.median <=
            oracle.posterior.upper
        @test oracle.posterior.mode_measure === :rho_density
        @test oracle.posterior.mode ==
            oracle.rho_grid[argmax(oracle.rho_density_log_profile)]
        @test oracle.posterior.transformed_z_mode ==
            oracle.rho_grid[argmax(oracle.log_profile)]
        @test oracle.posterior.positive_probability +
            oracle.posterior.negative_probability ≈ 1.0 atol = 2e-14
        @test !oracle.public_fit
        @test !oracle.cache_enabled
    end
    @test positive_oracle.realized_latent_correlation > 0
    @test positive_oracle.posterior.median > 0
    @test positive_oracle.posterior.positive_probability > 0.8
    @test negative_oracle.realized_latent_correlation < 0
    @test negative_oracle.posterior.median < 0
    @test negative_oracle.posterior.negative_probability > 0.8
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_oracle_profile(
            spec,
            base_raw;
            truth_rho = 1.0,
        )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_oracle_profile(
            spec,
            base_raw;
            zrho_grid = [0.0, -1.0, 1.0],
        )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_oracle_profile(
            spec,
            zeros(length(base_raw)),
        )

    @test_throws ArgumentError LogDensityProblems.logdensity(
        candidate,
        raw[1:end-1],
    )
    invalid_raw = copy(raw)
    invalid_raw[end] = NaN
    @test_throws ArgumentError LogDensityProblems.logdensity(candidate, invalid_raw)
    for invalid_eta in (true, 0, -1, 1.5, NaN, Inf, 10_001)
        @test_throws ArgumentError experimental.
            free_latent_correlation_2d_candidate(spec; lkj_eta = invalid_eta)
    end
    @test experimental.free_latent_correlation_2d_candidate(
        spec;
        lkj_eta = BigFloat(2),
    ).prior.lkj_eta == 2
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_candidate(
            spec;
            lkj_eta = BigFloat(2) + eps(BigFloat(2)),
        )

    cross_loading_spec = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = Bool[1 0; 0 1; 1 1; 1 0],
    )
    @test q_matrix_validation(cross_loading_spec).passed
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_candidate(cross_loading_spec)

    three_dimensional_spec = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 3,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = Bool[1 0 0; 0 1 0; 0 0 1; 1 0 0],
    )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_candidate(three_dimensional_spec)

    two_item_spec = mfrm_spec(
        _free_correlation_two_item_data();
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = Bool[1 0; 0 1],
    )
    @test q_matrix_validation(two_item_spec).passed
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_candidate(two_item_spec)

    incomplete_person_spec = mfrm_spec(
        _free_correlation_incomplete_person_data();
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = Bool[1 0; 0 1; 1 0; 0 1],
    )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_candidate(incomplete_person_spec)

    gmfrm_spec = mfrm_spec(
        data;
        family = :gmfrm,
        thresholds = :partial_credit,
        discrimination = :rater,
    )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_candidate(gmfrm_spec)
    @test_throws ArgumentError experimental.fit(candidate; ndraws = 1, warmup = 0)
    @test_throws ArgumentError experimental.fit_cache_key(candidate)

    # Directly running this contract test remains MCMC-free. The diagnostic
    # sampler smoke requires an explicit opt-in even outside test/runtests.jl.
    run_sampler_smoke = lowercase(get(
            ENV,
            "BAYESIANMGMFRM_FREE_CORRELATION_SMOKE",
            "false",
        )) in ("1", "true", "yes")
    if run_sampler_smoke
        include("mgmfrm_free_latent_correlation_2d_mcmc_smoke.jl")
    end

    include("mgmfrm_free_latent_correlation_2d_recovery.jl")
end
