using LogDensityProblems
using Test
using BayesianMGMFRM

function _free_correlation_recovery_capture_error(f)
    try
        f()
        return nothing
    catch error
        return error
    end
end

@testset "quarantined 2D free-correlation known-truth recovery wiring" begin
    experimental = BayesianMGMFRM.Experimental
    fixture_controls = (;
        n_persons = 8,
        items_per_dimension = 2,
        n_raters = 2,
        n_categories = 3,
        rho_truth = 0.45,
        ability_seed = 20260731,
        response_seed = 20260732,
        lkj_eta = 2,
        max_observations = 1_000,
        max_probability_cells = 10_000,
    )
    build_fixture = overrides ->
        experimental.free_latent_correlation_2d_known_truth_fixture(;
            merge(fixture_controls, overrides)...,
        )

    fixture = build_fixture((;))
    replay = build_fixture((;))
    response_reseeded = build_fixture((; response_seed = 20260733))
    ability_reseeded = build_fixture((; ability_seed = 20260734))

    @test fixture isa NamedTuple
    @test fixture.family === :mgmfrm
    @test fixture.scope === :mgmfrm_2d_free_latent_correlation_candidate
    @test fixture.status === :known_truth_generated
    @test fixture.claim_scope === :response_level_dgp_not_recovery
    @test !fixture.public_fit
    @test !fixture.fit_ready
    @test !fixture.cache_enabled
    @test fixture.promotion_effect === :none
    @test fixture.result_type === :named_tuple_only
    @test !fixture.recovery_verified
    @test fixture.next_gate === :single_dataset_multichain_recovery_pilot

    @test isdefined(
        experimental,
        :free_latent_correlation_2d_known_truth_fixture,
    )
    @test isdefined(experimental, :free_latent_correlation_2d_recovery_pilot)
    @test :free_latent_correlation_2d_known_truth_fixture ∉
        names(experimental)
    @test :free_latent_correlation_2d_recovery_pilot ∉ names(experimental)
    @test :free_latent_correlation_2d_known_truth_fixture ∉
        names(BayesianMGMFRM)
    @test :free_latent_correlation_2d_recovery_pilot ∉
        names(BayesianMGMFRM)
    @test :_mgmfrm_free_latent_correlation_2d_known_truth_fixture ∉
        names(BayesianMGMFRM)
    @test :_mgmfrm_free_latent_correlation_2d_recovery_pilot ∉
        names(BayesianMGMFRM)
    @test_throws ArgumentError experimental.fit(fixture.candidate)
    @test_throws ArgumentError experimental.fit_cache_key(fixture.candidate)

    # Exact replay is deliberately stronger than a distributional comparison:
    # the fixture is a deterministic scientific input artifact for one Julia
    # environment, not merely a stochastic generator with similar moments.
    @test fixture.seeds == replay.seeds
    @test fixture.data.person == replay.data.person
    @test fixture.data.rater == replay.data.rater
    @test fixture.data.item == replay.data.item
    @test fixture.data.score == replay.data.score
    @test fixture.response_probabilities == replay.response_probabilities
    @test fixture.shared_kernel_replay_probabilities ==
        replay.shared_kernel_replay_probabilities
    @test fixture.source_oracle_probabilities ==
        replay.source_oracle_probabilities
    @test fixture.probability_oracle_contract ==
        replay.probability_oracle_contract
    @test fixture.score_counts == replay.score_counts
    @test fixture.truth.person_abilities == replay.truth.person_abilities
    @test fixture.truth.base_raw_parameter_values ==
        replay.truth.base_raw_parameter_values
    @test fixture.truth.candidate_raw_parameter_values ==
        replay.truth.candidate_raw_parameter_values
    @test fixture.truth.direct_parameter_values ==
        replay.truth.direct_parameter_values

    @test fixture.seeds.ability == fixture_controls.ability_seed
    @test fixture.seeds.response == fixture_controls.response_seed
    @test fixture.seeds.ability != fixture.seeds.response
    @test fixture.seeds.separated
    @test fixture.seeds.rng === :MersenneTwister
    @test response_reseeded.truth.person_abilities ==
        fixture.truth.person_abilities
    @test response_reseeded.truth.base_raw_parameter_values ==
        fixture.truth.base_raw_parameter_values
    @test response_reseeded.response_probabilities ==
        fixture.response_probabilities
    @test response_reseeded.data.score != fixture.data.score
    @test ability_reseeded.truth.person_abilities !=
        fixture.truth.person_abilities

    truth = fixture.truth
    @test truth.population_rho == fixture_controls.rho_truth
    @test truth.zrho == atanh(truth.population_rho)
    @test isfinite(truth.realized_latent_correlation)
    @test -1 < truth.realized_latent_correlation < 1
    @test truth.realized_latent_correlation != truth.population_rho
    @test length(truth.base_raw_parameter_names) ==
        length(truth.base_raw_parameter_values)
    @test length(truth.candidate_raw_parameter_names) ==
        length(truth.candidate_raw_parameter_values)
    @test length(truth.direct_parameter_names) ==
        length(truth.direct_parameter_values)
    @test truth.candidate_raw_parameter_names ==
        fixture.candidate.blueprint.parameter_names
    @test truth.candidate_raw_parameter_values[1:end-1] ==
        truth.base_raw_parameter_values
    @test truth.candidate_raw_parameter_values[end] == truth.zrho
    @test all(isfinite, truth.person_abilities)
    @test all(isfinite, truth.base_raw_parameter_values)
    @test all(isfinite, truth.candidate_raw_parameter_values)
    @test all(isfinite, truth.direct_parameter_values)

    q_matrix = fixture.spec.q_matrix
    @test size(q_matrix) == (2 * fixture_controls.items_per_dimension, 2)
    @test all(item -> count(@view(q_matrix[item, :])) == 1,
        axes(q_matrix, 1))
    @test Tuple(count(@view(q_matrix[:, dimension]))
        for dimension in axes(q_matrix, 2)) ==
        (fixture_controls.items_per_dimension,
            fixture_controls.items_per_dimension)

    data = fixture.data
    person_dimension_observed = falses(length(data.person_levels), 2)
    for row in 1:data.n
        for dimension in 1:2
            q_matrix[data.item[row], dimension] &&
                (person_dimension_observed[data.person[row], dimension] = true)
        end
    end
    @test all(person_dimension_observed)
    @test all(item -> sort!(unique(data.rater[data.item .== item])) ==
        collect(1:fixture_controls.n_raters), axes(q_matrix, 1))
    @test all(rater -> all(dimension -> any(
        row -> data.rater[row] == rater &&
            q_matrix[data.item[row], dimension],
        1:data.n,
    ), 1:2), 1:fixture_controls.n_raters)

    @test fixture.checks.passed
    @test all(row -> row.passed, fixture.constraint_rows)
    @test fixture.summary.passed
    @test size(fixture.response_probabilities) ==
        (data.n, fixture_controls.n_categories)
    @test all(isfinite, fixture.response_probabilities)
    @test fixture.probability_oracle_contract.source_oracle ===
        :independent_closed_form_direct_scale
    @test fixture.probability_oracle_contract.shared_kernel_replay ===
        :source_fixture_values
    @test fixture.likelihood_identity.passed
    @test fixture.likelihood_identity.maximum_truth_pointwise_error <= 1e-12
    @test fixture.likelihood_identity.maximum_shared_kernel_replay_error <=
        1e-12
    @test fixture.likelihood_identity.maximum_closed_form_oracle_error <=
        1e-12
    @test fixture.likelihood_identity.maximum_source_oracle_error <= 1e-12
    @test fixture.likelihood_identity.maximum_source_oracle_error ==
        fixture.likelihood_identity.maximum_closed_form_oracle_error
    @test fixture.shared_kernel_replay_probabilities ≈
        fixture.response_probabilities atol = 1e-12 rtol = 0
    @test fixture.response_probabilities ≈
        fixture.source_oracle_probabilities atol = 1e-12 rtol = 0

    binary_fixture =
        experimental.free_latent_correlation_2d_known_truth_fixture(;
            n_categories = 2,
        )
    five_category_fixture =
        experimental.free_latent_correlation_2d_known_truth_fixture(;
            n_categories = 5,
        )
    for oracle_fixture in (binary_fixture, fixture, five_category_fixture)
        design = oracle_fixture.candidate.base.design
        modified_direct = copy(oracle_fixture.truth.direct_parameter_values)
        discrimination_block = design.blocks[:item_dimension_discrimination]
        consistency_block = design.blocks[:rater_consistency]
        step_block = design.blocks[:item_steps]

        modified_direct[discrimination_block] .= collect(range(
            0.7,
            1.3;
            length = length(discrimination_block),
        ))
        consistency_logs = collect(range(
            -0.3,
            0.3;
            length = length(consistency_block),
        ))
        consistency_logs .-= sum(consistency_logs; init = 0.0) /
            length(consistency_logs)
        modified_direct[consistency_block] .= exp.(consistency_logs)
        if !isempty(step_block)
            modified_direct[step_block] .= collect(range(
                -0.45,
                0.35;
                length = length(step_block),
            ))
        end

        @test length(unique(modified_direct[discrimination_block])) > 1
        @test length(unique(modified_direct[consistency_block])) > 1
        @test prod(modified_direct[consistency_block]) ≈ 1.0 atol = 1e-12 rtol = 1e-12
        if oracle_fixture.design_contract.n_categories == 2
            @test isempty(step_block)
        else
            @test length(unique(modified_direct[step_block])) > 1
        end
        @test all(row -> row.passed,
            BayesianMGMFRM._mgmfrm_direct_constraint_rows(
                design,
                modified_direct,
            ))

        closed_form = BayesianMGMFRM.
            _free_correlation_closed_form_probabilities(
                design,
                modified_direct,
            )
        shared_cube = BayesianMGMFRM.
            _mgmfrm_predictive_probabilities_direct(
                design,
                reshape(modified_direct, 1, :),
            )
        shared_kernel = Matrix(@view shared_cube[1, :, :])
        @test size(closed_form) == size(shared_kernel) == (
            oracle_fixture.data.n,
            oracle_fixture.design_contract.n_categories,
        )
        @test all(isfinite, closed_form)
        @test all(isfinite, shared_kernel)
        @test maximum(abs.(closed_form .- shared_kernel)) <= 1e-12
        @test all(isapprox.(
            vec(sum(closed_form; dims = 2)),
            1.0;
            atol = 1e-12,
            rtol = 1e-12,
        ))
        @test all(isapprox.(
            vec(sum(shared_kernel; dims = 2)),
            1.0;
            atol = 1e-12,
            rtol = 1e-12,
        ))
    end
    @test all(probability -> 0 <= probability <= 1,
        fixture.response_probabilities)
    @test all(isapprox.(
        vec(sum(fixture.response_probabilities; dims = 2)),
        1.0;
        atol = 1e-12,
        rtol = 1e-12,
    ))
    @test sum(row.count for row in fixture.score_counts) == data.n
    @test length(fixture.score_counts) == fixture_controls.n_categories
    @test Tuple(row.category for row in fixture.score_counts) ==
        Tuple(0:(fixture_controls.n_categories - 1))
    @test all(score -> 0 <= score < fixture_controls.n_categories, data.score)

    logdensity = LogDensityProblems.logdensity(
        fixture.candidate,
        truth.candidate_raw_parameter_values,
    )
    loglikelihood = BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_loglikelihood(
            fixture.candidate,
            truth.candidate_raw_parameter_values,
        )
    pointwise = BayesianMGMFRM.
        _mgmfrm_free_latent_correlation_2d_pointwise_loglikelihood(
            fixture.candidate,
            truth.candidate_raw_parameter_values,
        )
    @test isfinite(logdensity)
    @test isfinite(loglikelihood)
    @test length(pointwise) == data.n
    @test all(isfinite, pointwise)
    @test sum(pointwise) ≈ loglikelihood atol = 1e-12 rtol = 1e-12
    correlation_state = experimental.free_latent_correlation_2d_state(
        fixture.candidate,
        truth.candidate_raw_parameter_values,
    )
    @test correlation_state.rho ≈ truth.population_rho atol = 1e-14 rtol = 0

    @test_throws ArgumentError build_fixture((; n_persons = 1))
    @test_throws ArgumentError build_fixture((; items_per_dimension = 1))
    @test_throws ArgumentError build_fixture((; n_raters = 1))
    @test_throws ArgumentError build_fixture((; n_categories = 1))
    @test_throws ArgumentError build_fixture((; rho_truth = -1.0))
    @test_throws ArgumentError build_fixture((; rho_truth = 1.0))
    @test_throws ArgumentError build_fixture((; rho_truth = NaN))
    @test_throws ArgumentError build_fixture((; rho_truth = true))
    @test_throws ArgumentError build_fixture((; ability_seed = -1))
    @test_throws ArgumentError build_fixture((; response_seed = -1))
    @test_throws ArgumentError build_fixture((;
        response_seed = fixture_controls.ability_seed,
    ))
    @test_throws ArgumentError build_fixture((; max_observations = 1))
    @test_throws ArgumentError build_fixture((; max_probability_cells = 1))
    @test_throws ArgumentError build_fixture((; max_observations = 100_001))
    @test_throws ArgumentError build_fixture((;
        max_probability_cells = 500_001,
    ))

    scientific_base_initial = initial_params(fixture.candidate)
    scientific_chain_initials, scientific_starts = BayesianMGMFRM.
        _free_correlation_scientific_chain_initials(
            fixture.candidate,
            scientific_base_initial,
            4,
        )
    expected_rho_starts = [-0.8, -0.3, 0.3, 0.8]
    @test scientific_starts.rho == expected_rho_starts
    @test scientific_starts.zrho == atanh.(expected_rho_starts)
    @test scientific_chain_initials[:,
        fixture.candidate.blueprint.zrho_index] == scientific_starts.zrho
    @test size(scientific_chain_initials) ==
        (4, LogDensityProblems.dimension(fixture.candidate))
    @test all(chain -> all(
        scientific_chain_initials[chain, index] ==
            scientific_base_initial[index]
        for index in fixture.candidate.blueprint.base_parameter_range
    ), 1:4)
    @test truth.population_rho ∉ scientific_starts.rho

    for colliding_seed in (fixture.seeds.ability, fixture.seeds.response)
        error = _free_correlation_recovery_capture_error() do
            experimental.free_latent_correlation_2d_recovery_pilot(
                fixture;
                mode = :diagnostic_smoke,
                ndraws = 1,
                warmup = 0,
                chains = 2,
                seed = colliding_seed,
                metric = :invalid_preflight_sentinel,
            )
        end
        @test error isa ArgumentError
        message = error isa Exception ?
            lowercase(sprint(showerror, error)) : ""
        @test occursin("seed", message)
        @test occursin("differ", message)
    end

    rho_tampered = merge(fixture, (;
        truth = merge(truth, (;
            population_rho = truth.population_rho / 2,
        )),
    ))
    probability_values = copy(fixture.response_probabilities)
    probability_values[1, 1] += 1e-4
    probability_tampered = merge(fixture, (;
        response_probabilities = probability_values,
    ))
    shared_kernel_values = copy(fixture.shared_kernel_replay_probabilities)
    shared_kernel_values[1, 1] += 1e-4
    shared_kernel_tampered = merge(fixture, (;
        shared_kernel_replay_probabilities = shared_kernel_values,
    ))
    closed_form_values = copy(fixture.source_oracle_probabilities)
    closed_form_values[1, 1] += 1e-4
    closed_form_tampered = merge(fixture, (;
        source_oracle_probabilities = closed_form_values,
    ))
    raw_values = copy(truth.candidate_raw_parameter_values)
    raw_values[1] += 1e-4
    raw_tampered = merge(fixture, (;
        truth = merge(truth, (;
            candidate_raw_parameter_values = raw_values,
        )),
    ))
    response_tampered = deepcopy(fixture)
    response_tampered.data.score[1] = mod(
        response_tampered.data.score[1] + 1,
        fixture_controls.n_categories,
    )
    for (tampered, expected_message) in (
            (rho_tampered, "rho"),
            (probability_tampered, "probabilit"),
            (shared_kernel_tampered, "shared-kernel"),
            (closed_form_tampered, "independent"),
            (raw_tampered, "raw truth"),
            (response_tampered, "response"))
        error = _free_correlation_recovery_capture_error() do
            experimental.free_latent_correlation_2d_recovery_pilot(
                tampered;
                mode = :diagnostic_smoke,
                ndraws = 1,
                warmup = 0,
                chains = 2,
                seed = 20260735,
                metric = :invalid_preflight_sentinel,
            )
        end
        @test error isa ArgumentError
        message = error isa Exception ?
            lowercase(sprint(showerror, error)) : ""
        @test occursin(expected_message, message)
    end

    # These calls must fail at the scientific-workload preflight. The invalid
    # metric is a fail-fast sentinel: if the workload guard regresses, a test
    # fails immediately instead of accidentally launching a large HMC run.
    scientific_cases = (
        ((; chains = 3, warmup = 500, ndraws = 500), "chains"),
        ((; chains = 4, warmup = 499, ndraws = 500), "warmup"),
        ((; chains = 4, warmup = 500, ndraws = 499), "draw"),
    )
    for (workload, field) in scientific_cases
        error = _free_correlation_recovery_capture_error() do
            experimental.free_latent_correlation_2d_recovery_pilot(
                fixture;
                mode = :scientific,
                workload...,
                metric = :invalid_preflight_sentinel,
            )
        end
        @test error isa ArgumentError
        message = error isa Exception ?
            lowercase(sprint(showerror, error)) : ""
        @test occursin("scientific", message)
        @test occursin(field, message)
    end

    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_recovery_pilot(
            fixture;
            mode = :unsupported,
            ndraws = 1,
            warmup = 0,
            chains = 1,
        )

    # Direct execution is still MCMC-free unless the diagnostic sampler smoke
    # is requested explicitly.
    run_diagnostic_smoke = lowercase(get(
            ENV,
            "BAYESIANMGMFRM_FREE_CORRELATION_RECOVERY_SMOKE",
            "false",
        )) in ("1", "true", "yes")
    if run_diagnostic_smoke
        pilot = experimental.free_latent_correlation_2d_recovery_pilot(
            fixture;
            mode = :diagnostic_smoke,
            ndraws = 12,
            warmup = 12,
            chains = 2,
            seed = 20260735,
            step_size = 0.03,
            target_accept = 0.8,
            max_depth = 4,
            metric = :unit,
            init_jitter = 0.02,
        )

        @test pilot isa NamedTuple
        @test pilot.family === :mgmfrm
        @test pilot.scope === :mgmfrm_2d_free_latent_correlation_candidate
        @test pilot.status === :internal_diagnostic_smoke
        @test pilot.mode === :diagnostic_smoke
        @test pilot.claim_scope ===
            :single_dataset_response_recovery_pilot_not_replicated_recovery
        @test !pilot.public_fit
        @test !pilot.fit_ready
        @test !pilot.cache_enabled
        @test pilot.promotion_effect === :none
        @test !pilot.recovery_verified
        @test pilot.sampler_seed == 20260735
        @test pilot.sampler_seed != fixture.seeds.ability
        @test pilot.sampler_seed != fixture.seeds.response
        @test pilot.controls.max_depth == 4
        @test pilot.controls.metric === :unit
        @test pilot.next_gate ===
            :replicated_known_truth_correlation_recovery

        sample = pilot.sample_bundle
        nparams = LogDensityProblems.dimension(fixture.candidate)
        total_draws = 2 * 12
        @test size(sample.draws) == (total_draws, nparams)
        @test length(sample.logdensity) == total_draws
        @test length(sample.chain_ids) == total_draws
        @test length(sample.iterations) == total_draws
        @test sample.chain_ids == vcat(fill(1, 12), fill(2, 12))
        @test sample.iterations == vcat(collect(1:12), collect(1:12))
        @test length(sample.sampler_stats) == total_draws
        @test all(isfinite, sample.draws)
        @test all(isfinite, sample.logdensity)
        @test all(isfinite, sample.reevaluated_logdensity)
        @test all(isfinite, sample.pointwise_loglikelihood)
        @test sample.summary.sampler_stats_length_valid
        @test sample.summary.sampler_stats_layout_valid
        @test sample.summary.sampler_telemetry_finite
        @test sample.summary.logdensity_revalidation_passed
        @test sample.sampler_controls.max_depth == 4
        @test sample.sampler_controls.metric === :unit
        @test pilot.chain_layout.passed

        diagnostics = pilot.diagnostics
        @test length(diagnostics.raw_parameter_rows) == nparams
        @test length(diagnostics.direct_parameter_rows) ==
            length(truth.direct_parameter_names)
        @test diagnostics.rho_row.parameter ==
            "latent_correlation[dimension_1,dimension_2]"
        @test diagnostics.rho_row.n_chains == 2
        @test diagnostics.rho_row.draws_per_chain == 12
        @test diagnostics.rho_row.total_draws == total_draws
        @test diagnostics.rho_row.split_chains_requested
        @test diagnostics.rho_row.split_chains
        for row in diagnostics.raw_parameter_rows
            @test hasproperty(row, :rank_normalized_rhat)
            @test hasproperty(row, :bulk_ess)
            @test hasproperty(row, :tail_ess)
            @test hasproperty(row, :rank_normalized_flag)
        end
        @test diagnostics.e_bfmi.n_e_bfmi_expected == 2
        @test 0 <= diagnostics.e_bfmi.n_e_bfmi_available <= 2
        @test diagnostics.e_bfmi.n_e_bfmi_unavailable ==
            2 - diagnostics.e_bfmi.n_e_bfmi_available

        fixed_direct_rows = filter(
            row -> !row.quality_gate_applicable,
            diagnostics.direct_parameter_rows,
        )
        applicable_direct_rows = filter(
            row -> row.quality_gate_applicable,
            diagnostics.direct_parameter_rows,
        )
        # This candidate's named constrained layout contains active Q cells and
        # free step coordinates only. Sum-to-zero/geometric-mean final values
        # are derived but vary by draw, so they must not be misclassified as
        # structurally fixed.
        @test isempty(fixed_direct_rows)
        @test length(applicable_direct_rows) ==
            length(diagnostics.direct_parameter_rows)
        @test Set(row.parameter for row in fixed_direct_rows) ==
            diagnostics.structurally_fixed_direct_parameters
        @test all(row -> row.diagnostic_status === :structurally_fixed &&
            row.rank_normalized_flag === :structurally_fixed &&
            row.classical_compatibility_flag === :structurally_fixed &&
            row.flag === :structurally_fixed,
        fixed_direct_rows)
        @test diagnostics.contract.quality_gate.structurally_fixed_status ===
            :structurally_fixed
        @test diagnostics.contract.quality_gate.structurally_fixed_policy ===
            :exclude_zero_raw_dimension_transforms

        # Add a synthetic structurally-fixed informational row with
        # catastrophic-looking metrics. The scientific metric reducer must
        # still use only rows whose quality_gate_applicable flag is true.
        poisoned_fixed_row = merge(first(applicable_direct_rows), (;
            parameter = "synthetic_structurally_fixed_sentinel",
            quality_gate_applicable = false,
            rhat = 1e6,
            ess = 0.0,
            rank_normalized_rhat = 1e6,
            bulk_rank_normalized_rhat = 1e6,
            folded_rank_normalized_rhat = 1e6,
            bulk_ess = 0.0,
            tail_ess = 0.0,
            diagnostic_status = :structurally_fixed,
            rank_normalized_flag = :structurally_fixed,
            classical_compatibility_flag = :structurally_fixed,
            flag = :structurally_fixed,
        ))
        applicable_metrics = BayesianMGMFRM._mcmc_metric_summary(
            applicable_direct_rows,
            1.01,
            400.0,
        )
        poisoned_metrics = BayesianMGMFRM._mcmc_metric_summary(
            vcat(applicable_direct_rows, [poisoned_fixed_row]),
            1.01,
            400.0,
        )
        @test poisoned_metrics.n_quality_gate_parameters ==
            length(applicable_direct_rows)
        @test poisoned_metrics.n_structurally_fixed_parameters ==
            1
        for field in (
                :max_rhat,
                :min_ess,
                :max_rank_normalized_rhat,
                :min_bulk_ess,
                :min_tail_ess,
                :n_bad_rhat,
                :n_low_ess,
                :n_bad_rank_normalized_rhat,
                :n_low_bulk_ess,
                :n_low_tail_ess,
                :n_insufficient_chains,
                :n_insufficient_draws,
                :n_nonfinite_parameters,
                :n_degenerate_parameters)
            @test getproperty(poisoned_metrics, field) ==
                getproperty(applicable_metrics, field)
        end

        recovery = pilot.recovery
        @test length(recovery.raw_rows) == nparams
        @test length(recovery.direct_rows) ==
            length(truth.direct_parameter_names)
        @test recovery.rho_row.parameter ==
            "latent_correlation[dimension_1,dimension_2]"
        @test recovery.rho_row.block === :latent_correlation
        @test recovery.rho_row.true_value == truth.population_rho
        @test recovery.rho_row.interval_probability == 0.9
        for row in (recovery.rho_row, recovery.raw_rows[1],
                recovery.direct_rows[1])
            @test hasproperty(row, :posterior_mean)
            @test hasproperty(row, :posterior_sd)
            @test hasproperty(row, :posterior_median)
            @test hasproperty(row, :posterior_lower)
            @test hasproperty(row, :posterior_upper)
            @test hasproperty(row, :covered)
        end
        @test isfinite(recovery.sign_probabilities.positive)
        @test isfinite(recovery.sign_probabilities.negative)
        @test 0 <= recovery.sign_probabilities.positive <= 1
        @test 0 <= recovery.sign_probabilities.negative <= 1

        # Deliberately absent: short-run R-hat/ESS thresholds, direction,
        # interval inclusion/coverage, or a recovery-success assertion.
        @test pilot.summary.diagnostic_wiring_complete
        @test !pilot.summary.recovery_claimed
    end
end
