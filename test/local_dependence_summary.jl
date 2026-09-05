using Test
using Random
using BayesianMGMFRM

function _ld_single_rating_data(; n_responses::Int = 6)
    patterns = (
        (0, 0, 2),
        (0, 1, 1),
        (1, 0, 2),
        (1, 2, 0),
        (2, 1, 1),
        (2, 2, 0),
    )
    person = String[]
    rater = String[]
    item = String[]
    score = Int[]
    response = String[]
    testlet = String[]
    for response_index in 1:n_responses
        values = patterns[mod1(response_index, length(patterns))]
        for item_index in 1:3
            push!(person, "P$response_index")
            push!(rater, "R1")
            push!(item, "I$item_index")
            push!(score, values[item_index])
            push!(response, "Y$response_index")
            push!(testlet, "T1")
        end
    end
    return FacetData(
        (; person, rater, item, score, response, testlet);
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        response_id = :response,
        testlet_id = :testlet,
    )
end

function _ld_two_item_data()
    person = String[]
    rater = String[]
    item = String[]
    score = Int[]
    response = String[]
    testlet = String[]
    patterns = ((0, 2), (1, 1), (2, 0), (0, 1), (2, 1), (1, 2))
    for response_index in 1:length(patterns), item_index in 1:2
        push!(person, "P$response_index")
        push!(rater, "R1")
        push!(item, "I$item_index")
        push!(score, patterns[response_index][item_index])
        push!(response, "Y$response_index")
        push!(testlet, "T1")
    end
    return FacetData(
        (; person, rater, item, score, response, testlet);
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        response_id = :response,
        testlet_id = :testlet,
    )
end

function _ld_mfrm_fit(data; n_draws::Int = 4)
    design = getdesign(mfrm_spec(data; thresholds = :partial_credit))
    draws = zeros(n_draws, length(design.parameter_names))
    for draw in 2:n_draws
        draws[draw, :] .= range(
            -0.04 * draw,
            0.04 * draw;
            length = size(draws, 2),
        )
    end
    return MFRMFit(
        design,
        MFRMPrior(),
        draws,
        zeros(n_draws),
        1.0,
        ones(Int, n_draws),
        collect(1:n_draws),
        [1.0],
        :fixture,
        :fixture,
        0,
        0.1,
    )
end

function _ld_generalized_raw_draws(target, n_draws::Int)
    draws = zeros(n_draws, length(initial_params(target)))
    for draw in 2:n_draws
        draws[draw, :] .= range(
            -0.025 * draw,
            0.025 * draw;
            length = size(draws, 2),
        )
    end
    return draws
end

function _ld_gmfrm_fit(data; n_draws::Int = 4)
    spec = mfrm_spec(
        data;
        family = :gmfrm,
        discrimination = :rater,
        thresholds = :partial_credit,
    )
    design = getdesign(spec; preview = true)
    prior = BayesianMGMFRM._SourceFixturePrior()
    target = BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(design; prior)
    raw = _ld_generalized_raw_draws(target, n_draws)
    direct = BayesianMGMFRM._gmfrm_candidate_direct_draw_values(target, raw)
    return GMFRMFit(
        design,
        prior,
        raw,
        zeros(n_draws),
        direct.direct_draws,
        direct.loglikelihood,
        direct.pointwise_loglikelihood,
        ones(Int, n_draws),
        collect(1:n_draws),
        [1.0],
        :fixture,
        :fixture,
        0,
        0.1,
        NamedTuple[],
        (;),
        (;),
    )
end

function _ld_mgmfrm_fit(data; n_draws::Int = 4)
    spec = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix = Bool[1 0; 0 1],
        thresholds = :partial_credit,
    )
    design = getdesign(spec; preview = true)
    prior = BayesianMGMFRM._SourceFixturePrior()
    target = BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(design; prior)
    raw = _ld_generalized_raw_draws(target, n_draws)
    direct = BayesianMGMFRM._mgmfrm_guarded_local_fit_direct_draw_values(
        target,
        raw,
    )
    return MGMFRMFit(
        design,
        prior,
        raw,
        zeros(n_draws),
        direct.direct_draws,
        direct.loglikelihood,
        direct.pointwise_loglikelihood,
        ones(Int, n_draws),
        collect(1:n_draws),
        [1.0],
        :fixture,
        :fixture,
        0,
        0.1,
        NamedTuple[],
        (;),
        (;),
    )
end

function _ld_custom_contract(; min_common_units = 3,
        min_eligible_draws = 3,
        min_eligible_draw_fraction = 0.75)
    return local_dependence_contract(
        profile = :custom_unvalidated,
        min_common_units = min_common_units,
        min_eligible_draws = min_eligible_draws,
        min_eligible_draw_fraction = min_eligible_draw_fraction,
    )
end

@testset "LD0b paired residual summary kernel" begin
    data = _ld_single_rating_data()
    fit = _ld_mfrm_fit(data)
    indices = collect(1:4)
    probabilities = BayesianMGMFRM._local_dependence_predictive_probabilities(
        fit,
        indices,
    )
    replicated = repeat(permutedims(data.score), 4, 1)
    result = BayesianMGMFRM._local_dependence_summary_from_probabilities(
        fit,
        indices,
        probabilities;
        contract = _ld_custom_contract(),
        interval = 0.95,
        rng = MersenneTwister(11),
        replicated_scores = replicated,
    )

    @test result.schema == "bayesianmgmfrm.local_dependence_summary.v1"
    @test result.object === :local_dependence_summary
    @test result.status === :report_only
    @test result.profile === :custom_unvalidated
    @test !result.frozen_profile
    @test !result.decision_labels_available
    @test !result.mechanism_interpretation_eligible
    @test result.draw_indices == (1, 2, 3, 4)
    @test result.replication_source === :supplied_for_reproduction
    @test result.n_summary_supported_pairs == 6
    @test result.computational_support.n_candidate_pairs == 6
    @test result.computational_support.candidate_pair_draw_cells == 24
    @test result.computational_support.n_positive_common_pairs == 6
    @test result.computational_support.pair_draw_cells == 24
    @test result.computational_support.n_pair_common_unit_links == 36
    @test result.computational_support.common_unit_draw_cells == 144
    @test result.computational_support.prediction_cells == 216
    @test !result.computational_support.zero_common_pair_rows_retained
    @test result.global_evidence.n_overall_supported_pairs == 6
    @test result.global_evidence.posterior_predictive_tail_fraction == 1.0
    @test result.global_evidence.decision_available === false
    @test result.decision === missing

    single_rows = [row for row in result.pair_rows
        if row.family === :single_rating_item_q3]
    within_rows = [row for row in result.pair_rows
        if row.family === :within_rater_item_q3]
    rater_rows = [row for row in result.pair_rows
        if row.family === :rater_on_shared_response_criterion]
    @test length(single_rows) == 3
    @test length(within_rows) == 3
    @test isempty(rater_rows)
    @test all(row -> row.status === :eligible_report_only, single_rows)
    @test all(row -> row.n_structural_common_units == 6, single_rows)
    @test all(row -> row.n_eligible_paired_draws == 4, single_rows)
    @test all(row -> row.posterior_predictive_tail_fraction == 1.0,
        single_rows)
    @test all(row -> row.raw_tail_fraction == 1.0, single_rows)
    @test all(row -> row.tail_fraction_mcse == 0.0, single_rows)
    @test all(row -> row.bh_adjusted_tail_fraction == 1.0, single_rows)
    @test all(row -> row.observed_adjusted_q3.n_defined == 4, single_rows)
    @test sum(row.observed_adjusted_q3.mean for row in single_rows) ≈ 0.0 atol = 1e-12
    @test all(row -> row.decision === missing, result.pair_rows)
    @test all(row -> row.local_dependence_detected === missing,
        result.pair_rows)
    @test all(row -> !row.mechanism_interpretation_eligible,
        result.pair_rows)

    graph = only([row for row in result.family_testlet_rows
        if row.family === :single_rating_item_q3])
    @test graph.observed_common_unit_graph.n_components == 1
    @test isempty(graph.observed_common_unit_graph.isolated_levels)
    @test graph.summary_supported_graph.n_components == 1
end

@testset "LD0b tail, BH, variance, and draw-selection boundaries" begin
    evidence = BayesianMGMFRM._local_dependence_tail_evidence(
        [0.1, 0.2],
        [0.1, 0.1],
        2,
        1.0,
    )
    @test evidence.exceedances == 1
    @test evidence.corrected_tail_fraction ≈ 2 / 3
    @test evidence.raw_tail_fraction == 0.5
    @test evidence.tail_fraction_mcse ≈ sqrt(0.25 / 2)
    @test evidence.support_met

    sparse = BayesianMGMFRM._local_dependence_tail_evidence(
        [0.1, 0.2],
        [0.1, 0.1],
        3,
        0.5,
    )
    @test !sparse.support_met
    @test sparse.corrected_tail_fraction === missing
    @test sparse.reason === :insufficient_eligible_draws

    absolute_boundary = BayesianMGMFRM._local_dependence_tail_evidence(
        vcat(zeros(99), fill(NaN, 11)),
        vcat(zeros(99), fill(NaN, 11)),
        100,
        0.9,
    )
    @test absolute_boundary.reason === :insufficient_eligible_draws
    fraction_boundary = BayesianMGMFRM._local_dependence_tail_evidence(
        vcat(zeros(100), fill(NaN, 12)),
        vcat(zeros(100), fill(NaN, 12)),
        100,
        0.9,
    )
    @test fraction_boundary.reason === :insufficient_eligible_draw_fraction
    exact_fraction = BayesianMGMFRM._local_dependence_tail_evidence(
        vcat(zeros(108), fill(NaN, 12)),
        vcat(zeros(108), fill(NaN, 12)),
        100,
        0.9,
    )
    @test exact_fraction.support_met
    @test exact_fraction.paired_fraction == 0.9

    bh = BayesianMGMFRM._local_dependence_bh_adjust([
        (1, 0.01),
        (2, 0.04),
        (3, 0.03),
    ])
    @test bh[1].adjusted ≈ 0.03
    @test bh[3].adjusted ≈ 0.04
    @test bh[2].adjusted ≈ 0.04
    @test bh[1].rank == 1
    @test bh[2].family_size == 3

    graph = BayesianMGMFRM._local_dependence_graph_components(
        ["I1", "I2", "I3", "I4"],
        [("I1", "I2"), ("I2", "I3")],
    )
    @test graph.n_components == 2
    @test graph.isolated_levels == ("I4",)

    values = [1.0 2.0 3.0; 1.0 1.0 1.0]
    valid = trues(2, 3)
    defined = BayesianMGMFRM._local_dependence_pair_correlation(
        values,
        valid,
        1,
        [1, 2, 3],
        [3, 2, 1],
        3,
        1e-12,
    )
    @test defined.value ≈ -1.0
    @test defined.reason === :defined
    constant = BayesianMGMFRM._local_dependence_pair_correlation(
        values,
        valid,
        2,
        [1, 2, 3],
        [3, 2, 1],
        3,
        1e-12,
    )
    @test isnan(constant.value)
    @test constant.reason === :negligible_centered_variance
    large_left = 1.0e10 .+ collect(0.0:19.0)
    large_right = reverse(large_left)
    large_values = permutedims(vcat(large_left, large_right))
    large_correlation =
        BayesianMGMFRM._local_dependence_pair_correlation(
            large_values,
            trues(1, 40),
            1,
            collect(1:20),
            collect(21:40),
            20,
            1e-12,
        )
    @test large_correlation.value ≈ -1.0 atol = 1e-12
    @test large_correlation.reason === :defined

    fit = _ld_mfrm_fit(_ld_single_rating_data())
    @test_throws ArgumentError local_dependence_summary(
        fit;
        draw_indices = [1, 1],
    )
    @test_throws ArgumentError local_dependence_summary(fit; ndraws = 5)
    @test_throws ArgumentError local_dependence_summary(
        fit;
        draw_indices = 1:4,
        max_pair_draw_cells = 0,
    )
    @test_throws ArgumentError local_dependence_summary(
        fit;
        draw_indices = 1:4,
        max_prediction_cells = 0,
    )
    @test_throws ArgumentError local_dependence_summary(
        fit;
        draw_indices = 1:4,
        max_audit_pair_rows = 0,
    )
    @test_throws ArgumentError local_dependence_summary(
        fit;
        draw_indices = 1:4,
        max_common_unit_draw_cells = 0,
    )
    exact_resource_boundary = local_dependence_summary(
        fit;
        contract = _ld_custom_contract(),
        draw_indices = 1:4,
        rng = MersenneTwister(41),
        max_pair_draw_cells = 24,
        max_prediction_cells = 216,
        max_audit_pair_rows = 6,
        max_common_unit_draw_cells = 144,
    )
    @test exact_resource_boundary.computational_support.pair_draw_cells == 24
    @test exact_resource_boundary.computational_support.prediction_cells == 216
    @test exact_resource_boundary.computational_support.n_audit_materialized_pair_rows == 6
    @test exact_resource_boundary.computational_support.common_unit_draw_cells == 144
    @test_throws ArgumentError local_dependence_summary(
        fit;
        contract = _ld_custom_contract(),
        draw_indices = 1:4,
        max_pair_draw_cells = 23,
    )
    @test_throws ArgumentError local_dependence_summary(
        fit;
        contract = _ld_custom_contract(),
        draw_indices = 1:4,
        max_prediction_cells = 215,
    )
    @test_throws ArgumentError local_dependence_summary(
        fit;
        contract = _ld_custom_contract(),
        draw_indices = 1:4,
        max_audit_pair_rows = 5,
    )
    @test_throws ArgumentError local_dependence_summary(
        fit;
        contract = _ld_custom_contract(),
        draw_indices = 1:4,
        max_common_unit_draw_cells = 143,
    )
    first_result = local_dependence_summary(
        fit;
        contract = _ld_custom_contract(min_eligible_draws = 2),
        ndraws = 3,
        rng = MersenneTwister(902),
    )
    second_result = local_dependence_summary(
        fit;
        contract = _ld_custom_contract(min_eligible_draws = 2),
        ndraws = 3,
        rng = MersenneTwister(902),
    )
    @test length(unique(first_result.draw_indices)) == 3
    @test first_result.draw_indices == second_result.draw_indices
    @test isequal(first_result.pair_rows, second_result.pair_rows)
    different_replication = local_dependence_summary(
        fit;
        contract = _ld_custom_contract(min_eligible_draws = 2),
        draw_indices = first_result.draw_indices,
        rng = MersenneTwister(903),
    )
    first_observed_adjusted = Tuple(row.observed_adjusted_q3
        for row in first_result.pair_rows
        if row.family in (:single_rating_item_q3, :within_rater_item_q3))
    different_observed_adjusted = Tuple(row.observed_adjusted_q3
        for row in different_replication.pair_rows
        if row.family in (:single_rating_item_q3, :within_rater_item_q3))
    @test isequal(first_observed_adjusted, different_observed_adjusted)

    default_result = local_dependence_summary(
        fit;
        draw_indices = 1:4,
        rng = MersenneTwister(1),
    )
    @test default_result.status === :no_eligible_pairs
    @test default_result.n_summary_supported_pairs == 0
    @test default_result.global_evidence.support_status ===
        :no_overall_supported_pairs
    @test all(row -> row.support_status === :no_eligible_pairs,
        default_result.family_max_rows)
    @test all(row -> row.posterior_predictive_tail_fraction === missing,
        default_result.pair_rows)
    @test_throws ArgumentError local_dependence_summary(
        fit;
        contract = merge(_ld_custom_contract(), (; status = :ready)),
        draw_indices = 1:4,
    )
    @test_throws ArgumentError local_dependence_summary(
        fit;
        contract = _ld_custom_contract(),
        interval = 1.0,
        draw_indices = 1:4,
    )

    empty_probabilities = zeros(Float64, 0, fit.design.spec.data.n,
        length(fit.design.spec.data.category_levels))
    @test_throws ArgumentError BayesianMGMFRM._local_dependence_summary_from_probabilities(
        fit,
        Int[],
        empty_probabilities;
        contract = _ld_custom_contract(),
        interval = 0.95,
        rng = MersenneTwister(1),
        replicated_scores = zeros(Int, 0, fit.design.spec.data.n),
    )

    degenerate_probabilities = zeros(Float64, 4, fit.design.spec.data.n,
        length(fit.design.spec.data.category_levels))
    degenerate_probabilities[:, :, 1] .= 1.0
    degenerate =
        BayesianMGMFRM._local_dependence_summary_from_probabilities(
            fit,
            collect(1:4),
            degenerate_probabilities;
            contract = _ld_custom_contract(),
            interval = 0.95,
            rng = MersenneTwister(1),
            replicated_scores = zeros(Int, 4, fit.design.spec.data.n),
        )
    @test degenerate.status === :undefined_residual_variation
    @test degenerate.n_summary_supported_pairs == 0
    @test all(row -> row.status === :undefined_residual_variation,
        degenerate.pair_rows)
end

@testset "LD0b model-family smoke and metadata errors" begin
    data = _ld_two_item_data()
    contract = _ld_custom_contract(
        min_common_units = 3,
        min_eligible_draws = 2,
        min_eligible_draw_fraction = 0.5,
    )
    for fit in (
            _ld_mfrm_fit(data),
            _ld_gmfrm_fit(data),
            _ld_mgmfrm_fit(data),
        )
        result = local_dependence_summary(
            fit;
            contract,
            draw_indices = 1:4,
            rng = MersenneTwister(8),
        )
        @test result.family === fit.design.spec.family
        @test result.n_draws == 4
        @test result.draw_source === :distinct_posterior_draws
        @test result.calibration_required
        @test result.decision_labels_available === false
    end

    no_metadata = FacetData(
        (; person = ["P1", "P1"], rater = ["R1", "R1"],
            item = ["I1", "I2"], score = [0, 1]);
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
    @test_throws ArgumentError local_dependence_summary(
        _ld_mfrm_fit(no_metadata);
        draw_indices = 1:4,
    )
end

@testset "LD0b residual definition matches public Pearson residuals" begin
    data = _ld_two_item_data()
    indices = [2, 1]
    for fit in (
            _ld_mfrm_fit(data),
            _ld_gmfrm_fit(data),
            _ld_mgmfrm_fit(data),
        )
        probabilities =
            BayesianMGMFRM._local_dependence_predictive_probabilities(
                fit,
                indices,
            )
        replicated = repeat(permutedims(data.score), length(indices), 1)
        kernel = BayesianMGMFRM._local_dependence_standardized_residual_pair(
            data,
            probabilities,
            replicated,
            0.0,
        )
        public_residuals = predictive_standardized_residuals(
            fit;
            draw_indices = indices,
            variance_tolerance = 0.0,
        )
        @test kernel.observed.valid == public_residuals.valid
        @test isequal(kernel.observed.values, public_residuals.values)
        @test kernel.observed.n_valid == public_residuals.n_valid
        @test kernel.observed.n_excluded == public_residuals.n_excluded

        variances = BayesianMGMFRM._predictive_variances_from_probabilities(
            probabilities,
            data.category_levels,
        )
        boundary = variances[1, 1]
        masked_kernel =
            BayesianMGMFRM._local_dependence_standardized_residual_pair(
                data,
                probabilities,
                replicated,
                boundary,
            )
        masked_public = predictive_standardized_residuals(
            fit;
            draw_indices = indices,
            variance_tolerance = boundary,
        )
        @test !masked_kernel.observed.valid[1, 1]
        @test masked_kernel.observed.valid == masked_public.valid
        @test isequal(masked_kernel.observed.values, masked_public.values)
    end
end

@testset "LD0b identifier errors, signatures, and serialization" begin
    data = _ld_single_rating_data()
    mutated_fit = _ld_mfrm_fit(_ld_single_rating_data())
    mutated_data = mutated_fit.design.spec.data
    mutated_data.score[1] = mutated_data.score[1] == 0 ? 1 : 0
    @test_throws ArgumentError local_dependence_summary(
        mutated_fit;
        contract = _ld_custom_contract(),
        draw_indices = 1:4,
    )
    duplicate_fit = _ld_mfrm_fit(data)
    duplicate_data = duplicate_fit.design.spec.data
    duplicate_data.item[2] = duplicate_data.item[1]
    @test_throws ArgumentError local_dependence_summary(
        duplicate_fit;
        contract = _ld_custom_contract(),
        draw_indices = 1:4,
    )

    nesting_fit = _ld_mfrm_fit(_ld_single_rating_data())
    nesting_data = nesting_fit.design.spec.data
    nesting_data.person[2] = nesting_data.person[4]
    @test_throws ArgumentError local_dependence_summary(
        nesting_fit;
        contract = _ld_custom_contract(),
        draw_indices = 1:4,
    )

    original_data = _ld_single_rating_data()
    original_fit = _ld_mfrm_fit(original_data)
    original_probabilities =
        BayesianMGMFRM._local_dependence_predictive_probabilities(
            original_fit,
            collect(1:4),
        )
    original_result =
        BayesianMGMFRM._local_dependence_summary_from_probabilities(
            original_fit,
            collect(1:4),
            original_probabilities;
            contract = _ld_custom_contract(),
            interval = 0.95,
            rng = MersenneTwister(1),
            replicated_scores = repeat(permutedims(original_data.score), 4, 1),
        )
    table = facet_response_table(original_data)
    permutation = reverse(1:original_data.n)
    permuted_table = (; (name => getproperty(table, name)[permutation]
        for name in propertynames(table))...)
    permuted_data = FacetData(
        permuted_table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        response_id = :response_id,
        testlet_id = :testlet_id,
    )
    permuted_fit = _ld_mfrm_fit(permuted_data)
    permuted_probabilities =
        BayesianMGMFRM._local_dependence_predictive_probabilities(
            permuted_fit,
            collect(1:4),
        )
    permuted_result =
        BayesianMGMFRM._local_dependence_summary_from_probabilities(
            permuted_fit,
            collect(1:4),
            permuted_probabilities;
            contract = _ld_custom_contract(),
            interval = 0.95,
            rng = MersenneTwister(1),
            replicated_scores = repeat(permutedims(permuted_data.score), 4, 1),
        )
    @test original_result.design_signature == permuted_result.design_signature
    @test original_result.observed_score_signature ==
        permuted_result.observed_score_signature
    @test isequal(original_result.pair_rows, permuted_result.pair_rows)
    preflight = BayesianMGMFRM._local_dependence_preflight(
        original_fit,
        collect(1:4),
        _ld_custom_contract();
        max_pair_draw_cells = 1_000,
        max_prediction_cells = 1_000,
        max_audit_pair_rows = 1_000,
        max_common_unit_draw_cells = 1_000,
    )
    @test_throws ArgumentError BayesianMGMFRM._local_dependence_summary_from_probabilities(
        original_fit,
        collect(1:4),
        original_probabilities;
        contract = _ld_custom_contract(min_common_units = 4),
        interval = 0.95,
        rng = MersenneTwister(1),
        replicated_scores = repeat(permutedims(original_data.score), 4, 1),
        max_pair_draw_cells = 1_000,
        max_prediction_cells = 1_000,
        max_audit_pair_rows = 1_000,
        max_common_unit_draw_cells = 1_000,
        preflight,
    )
    public_original = local_dependence_summary(
        original_fit;
        contract = _ld_custom_contract(),
        draw_indices = 1:4,
        rng = MersenneTwister(771),
    )
    public_permuted = local_dependence_summary(
        permuted_fit;
        contract = _ld_custom_contract(),
        draw_indices = 1:4,
        rng = MersenneTwister(771),
    )
    @test isequal(public_original.pair_rows, public_permuted.pair_rows)
    serialized = String(BayesianMGMFRM.JSON3.write(original_result))
    @test occursin("bayesianmgmfrm.local_dependence_summary.v1", serialized)
    @test occursin("decision_labels_available", serialized)

    @test_throws ArgumentError BayesianMGMFRM._local_dependence_summary_from_probabilities(
            original_fit,
            collect(1:4),
            original_probabilities;
            contract = _ld_custom_contract(),
            interval = 0.95,
            rng = MersenneTwister(1),
            replicated_scores = zeros(Int, 3, original_data.n),
        )
    invalid_scores = repeat(permutedims(original_data.score), 4, 1)
    invalid_scores[1, 1] = 99
    @test_throws ArgumentError BayesianMGMFRM._local_dependence_summary_from_probabilities(
            original_fit,
            collect(1:4),
            original_probabilities;
            contract = _ld_custom_contract(),
            interval = 0.95,
            rng = MersenneTwister(1),
            replicated_scores = invalid_scores,
        )
end

@testset "LD0b family and testlet support statuses stay separate" begin
    person = String[]
    rater = String[]
    item = String[]
    score = Int[]
    response = String[]
    testlet = String[]
    patterns = (
        (0, 0, 2),
        (0, 1, 1),
        (1, 0, 2),
        (1, 2, 0),
        (2, 1, 1),
        (2, 2, 0),
    )
    for response_index in 1:6, item_index in 1:3
        push!(person, "P$response_index")
        push!(rater, "R1")
        push!(item, "I$item_index")
        push!(score, patterns[response_index][item_index])
        push!(response, "Y$response_index")
        push!(testlet, "T1")
    end
    for item_index in 1:3
        push!(person, "P7")
        push!(rater, "R1")
        push!(item, "I$item_index")
        push!(score, item_index - 1)
        push!(response, "Y7")
        push!(testlet, "T2")
    end
    data = FacetData(
        (; person, rater, item, score, response, testlet);
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        response_id = :response,
        testlet_id = :testlet,
    )
    result = local_dependence_summary(
        _ld_mfrm_fit(data);
        contract = _ld_custom_contract(),
        draw_indices = 1:4,
        rng = MersenneTwister(312),
    )
    single_rows = [row for row in result.family_testlet_rows
        if row.family === :single_rating_item_q3]
    dense = only([row for row in single_rows if row.testlet_id == "T1"])
    sparse = only([row for row in single_rows if row.testlet_id == "T2"])
    @test dense.family_status === :eligible
    @test sparse.family_status === :eligible
    @test dense.testlet_status === :eligible
    @test dense.testlet_status_reason === :pair_meets_minimum_common_units
    @test sparse.testlet_status === :sparse
    @test sparse.testlet_status_reason === :no_pair_meets_minimum_common_units
    @test dense.n_structural_threshold_pairs == 3
    @test sparse.n_structural_threshold_pairs == 0
    dense_pairs = [row for row in result.pair_rows
        if row.family === :single_rating_item_q3 && row.testlet_id == "T1"]
    sparse_pairs = [row for row in result.pair_rows
        if row.family === :single_rating_item_q3 && row.testlet_id == "T2"]
    @test length(dense_pairs) == 3
    @test length(sparse_pairs) == 3
    @test all(row -> row.observed_adjusted_q3.n_defined == 4, dense_pairs)
    @test all(row -> row.observed_adjusted_q3.n_defined == 0, sparse_pairs)
end

@testset "LD0b single-rating applicability is testlet-specific" begin
    person = String[]
    rater = String[]
    item = String[]
    score = Int[]
    response = String[]
    testlet = String[]
    patterns = ((0, 2), (1, 1), (2, 0), (0, 1), (2, 1), (1, 2))
    for response_index in 1:6, item_index in 1:2
        push!(person, "P$response_index")
        push!(rater, "R1")
        push!(item, "I$item_index")
        push!(score, patterns[response_index][item_index])
        push!(response, "T1-Y$response_index")
        push!(testlet, "T1")
    end
    for response_index in 1:6, item_index in 1:2
        push!(person, "P$(response_index + 6)")
        rater_index = isodd(response_index) ? item_index : 3 - item_index
        push!(rater, "R$rater_index")
        push!(item, "I$item_index")
        push!(score, patterns[response_index][item_index])
        push!(response, "T2-Y$response_index")
        push!(testlet, "T2")
    end
    data = FacetData(
        (; person, rater, item, score, response, testlet);
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        response_id = :response,
        testlet_id = :testlet,
    )
    result = local_dependence_summary(
        _ld_mfrm_fit(data);
        contract = _ld_custom_contract(),
        draw_indices = 1:4,
        rng = MersenneTwister(91),
    )
    family = only([row for row in result.family_rows
        if row.family === :single_rating_item_q3])
    @test family.status === :partially_applicable
    @test family.n_applicable_testlets == 1
    @test family.n_inapplicable_testlets == 1
    support = [row for row in result.family_testlet_rows
        if row.family === :single_rating_item_q3]
    t1 = only([row for row in support if row.testlet_id == "T1"])
    t2 = only([row for row in support if row.testlet_id == "T2"])
    @test t1.testlet_status === :eligible
    @test ismissing(t1.testlet_inapplicable_reason)
    @test t2.testlet_status === :not_applicable
    @test t2.testlet_status_reason ===
        :multiple_ratings_or_criterion_split_within_response
    @test t2.testlet_inapplicable_reason ===
        :multiple_ratings_or_criterion_split_within_response
    single_pairs = [row for row in result.pair_rows
        if row.family === :single_rating_item_q3]
    @test length(single_pairs) == 1
    @test only(single_pairs).testlet_id == "T1"
    @test result.computational_support.single_rating_item_applicable_by_testlet ==
        (true, false)
end

@testset "LD0b criterion split and single-response concentration" begin
    person = String[]
    rater = String[]
    item = String[]
    score = Int[]
    response = String[]
    testlet = String[]
    patterns = ((0, 2), (1, 1), (2, 0), (0, 1), (2, 1), (1, 2))
    for response_index in 1:length(patterns), item_index in 1:2
        push!(person, "P$response_index")
        rater_index = isodd(response_index) ? item_index : 3 - item_index
        push!(rater, "R$rater_index")
        push!(item, "I$item_index")
        push!(score, patterns[response_index][item_index])
        push!(response, "Y$response_index")
        push!(testlet, "T1")
    end
    split_data = FacetData(
        (; person, rater, item, score, response, testlet);
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        response_id = :response,
        testlet_id = :testlet,
    )
    split_result = local_dependence_summary(
        _ld_mfrm_fit(split_data);
        contract = _ld_custom_contract(),
        draw_indices = 1:4,
        rng = MersenneTwister(5),
    )
    single_family = only([row for row in split_result.family_rows
        if row.family === :single_rating_item_q3])
    @test single_family.status === :not_applicable
    @test single_family.inapplicable_reason ===
        :multiple_ratings_or_criterion_split_within_response
    @test isempty(split_result.pair_rows)
    @test !split_result.computational_support.single_rating_item_any_testlet_applicable
    @test split_result.computational_support.n_positive_common_pairs == 0
    @test split_result.computational_support.n_audit_projected_rater_response_links ==
        0
    for family in (
            :within_rater_item_q3,
            :rater_on_shared_response_criterion,
        )
        family_row = only([row for row in split_result.family_rows
            if row.family === family])
        @test family_row.status === :sparse
        @test family_row.n_pairs_with_observations == 0
        support_row = only([row for row in split_result.family_testlet_rows
            if row.family === family])
        @test support_row.testlet_status === :sparse
        @test support_row.n_observed_pairs == 0
        @test length(
            support_row.observed_common_unit_graph.isolated_levels) == 2
    end

    person2 = fill("P1", 40)
    response2 = fill("Y1", 40)
    testlet2 = fill("T1", 40)
    rater2 = vcat(fill("R1", 20), fill("R2", 20))
    item2 = vcat(["I$i" for i in 1:20], ["I$i" for i in 1:20])
    score2 = vcat([mod(i, 3) for i in 1:20],
        [mod(2i + 1, 3) for i in 1:20])
    concentrated_data = FacetData(
        (; person = person2, rater = rater2, item = item2, score = score2,
            response = response2, testlet = testlet2);
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        response_id = :response,
        testlet_id = :testlet,
    )
    concentrated_fit = _ld_mfrm_fit(concentrated_data)
    indices = collect(1:4)
    probabilities = BayesianMGMFRM._local_dependence_predictive_probabilities(
        concentrated_fit,
        indices,
    )
    concentrated_result =
        BayesianMGMFRM._local_dependence_summary_from_probabilities(
            concentrated_fit,
            indices,
            probabilities;
            contract = _ld_custom_contract(),
            interval = 0.95,
            rng = MersenneTwister(2),
            replicated_scores = repeat(permutedims(concentrated_data.score), 4, 1),
        )
    rater_pair = only([row for row in concentrated_result.pair_rows
        if row.family === :rater_on_shared_response_criterion])
    @test rater_pair.n_structural_common_units == 20
    @test rater_pair.n_common_responses == 1
    @test rater_pair.common_response_support === :single_response
    @test rater_pair.rater_single_response_concentration
    @test rater_pair.rater_response_halo_global_structural_eligibility === false
    @test !rater_pair.mechanism_interpretation_eligible
end
