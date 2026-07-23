module LD1StandaloneDGPForTest

include(joinpath(@__DIR__, "..", "src",
    "local_dependence_known_truth_dgp.jl"))

end

const LD1StandaloneDGP = LD1StandaloneDGPForTest

function ld1_raw_config(;
        seed = 20260720,
        mechanism = :null,
        effect_scale = 0.0,
        design = :same_rater,
        assignment = :balanced,
        order = :randomized,
        n_persons = 12,
        n_testlets = 4,
        items_per_testlet = 2,
        n_raters = 3,
        n_categories = 4,
        max_ratings = 1_000_000,
        max_probability_cells = 5_000_000,
        max_truth_cells = 5_000_000)
    return (;
        seed,
        mechanism,
        effect_scale = Float64(effect_scale),
        design,
        assignment,
        order,
        n_persons,
        n_testlets,
        items_per_testlet,
        n_raters,
        n_categories,
        max_ratings,
        max_probability_cells,
        max_truth_cells,
    )
end

ld1_generate_raw(; kwargs...) = LD1StandaloneDGP._ld1_generate_raw(
    ld1_raw_config(; kwargs...))

function ld1_event_row_map(raw)
    return Dict(event_id => row
        for (row, event_id) in pairs(raw.table.event_id))
end

function ld1_all_zero(values)
    return all(iszero, values)
end

function ld1_expected_truth_cells(raw)
    n_persons = length(raw.truth.person_ability)
    n_raters = length(raw.truth.rater_severity)
    n_items = length(raw.truth.item_difficulty)
    n_testlets = length(raw.truth.testlet_labels)
    n_categories = length(raw.truth.intended_category_levels)
    n_ratings = raw.resource_counts.n_ratings
    facet_cells = 2 * n_persons + 2 * n_raters +
        (n_categories + 2) * n_items +
        2 * n_persons * n_testlets +
        n_raters * n_persons * n_testlets +
        n_raters * n_testlets
    row_cells = 20 * n_ratings + n_ratings * n_categories
    return facet_cells + row_cells
end

function ld1_json_value(value)
    if value isa AbstractDict
        return Dict(String(key) => ld1_json_value(element)
            for (key, element) in pairs(value))
    elseif value isa AbstractArray || value isa Tuple
        return [ld1_json_value(element) for element in value]
    end
    return value
end

@testset "LD1 standalone known-truth kernel isolation" begin
    source_path = joinpath(
        dirname(@__DIR__), "src", "local_dependence_known_truth_dgp.jl")
    source = read(source_path, String)
    dependency_lines = [strip(line) for line in split(source, '\n')
        if startswith(strip(line), "using ") ||
            startswith(strip(line), "import ")]
    @test dependency_lines == ["using Random"]
    for forbidden in (
            "BayesianMGMFRM",
            "FacetData",
            "predictive_probabilities",
            "simulate_responses",
            "loglikelihood",
            "_replicate_scores",
            "AdvancedHMC",
            "Distributions",
            "Turing",
        )
        @test !occursin(forbidden, source)
    end

    standalone_code =
        "include(ARGS[1]); print(_ld1_pcm_probabilities(0.0, [0.0]))"
    standalone_command = addenv(
        `$(Base.julia_cmd()) --startup-file=no --history-file=no -e $standalone_code $source_path`,
        "JULIA_LOAD_PATH" => "@stdlib",
    )
    @test read(standalone_command, String) == "[0.5, 0.5]"

    binary = LD1StandaloneDGP._ld1_pcm_probabilities(0.0, [0.0])
    @test binary == [0.5, 0.5]

    location = 0.2
    steps = [-0.3, 0.7]
    manual_weights = [1.0, exp(0.5), 1.0]
    manual = manual_weights ./ sum(manual_weights)
    @test LD1StandaloneDGP._ld1_pcm_probabilities(location, steps) ≈ manual

    low = LD1StandaloneDGP._ld1_pcm_probabilities(-1_000.0, steps)
    high = LD1StandaloneDGP._ld1_pcm_probabilities(1_000.0, steps)
    @test all(isfinite, low)
    @test all(isfinite, high)
    @test all(>=(0.0), low)
    @test all(>=(0.0), high)
    @test sum(low) ≈ 1.0 atol = 1.0e-15
    @test sum(high) ≈ 1.0 atol = 1.0e-15
    categories = collect(0:2)
    @test sum(categories .* low) < sum(categories .* manual) <
        sum(categories .* high)

    @test LD1StandaloneDGP._ld1_inverse_cdf(0.0, [0.2, 0.8], [0, 1]) == 0
    @test LD1StandaloneDGP._ld1_inverse_cdf(0.2, [0.2, 0.8], [0, 1]) == 1
    @test LD1StandaloneDGP._ld1_inverse_cdf(0.20001, [0.2, 0.8], [0, 1]) == 1
    @test LD1StandaloneDGP._ld1_inverse_cdf(0.0, [0.0, 1.0], [0, 1]) == 1
    @test_throws ArgumentError LD1StandaloneDGP._ld1_inverse_cdf(
        -eps(), [0.2, 0.8], [0, 1])
    @test_throws ArgumentError LD1StandaloneDGP._ld1_inverse_cdf(
        1.0, [0.2, 0.8], [0, 1])
end

@testset "LD1 planning-grid contract" begin
    grid = local_dependence_simulation_grid(
        repetitions = 2,
        base_seed = 71,
        phase = :smoke,
        grid_id = "ld1-test",
        n_persons = 20,
        n_testlets = 4,
        items_per_testlet = 2,
        n_raters = 3,
        n_categories = 3,
    )
    @test length(grid) == 44
    @test Set(row.scenario_index for row in grid) == Set(1:22)
    @test all(row -> row.schema ==
        "bayesianmgmfrm.local_dependence_simulation_grid.v1", grid)
    @test all(row -> row.object === :local_dependence_simulation_grid_row, grid)
    @test all(row -> row.profile === :ld1_preflight_v1, grid)
    @test all(row -> row.status === :planned, grid)
    @test all(row -> row.grid_id == "ld1-test", grid)
    @test all(row -> row.base_seed == 71, grid)
    @test all(row -> row.family === :mfrm &&
        row.thresholds === :partial_credit, grid)
    @test all(row -> row.generator_kernel ===
        :standalone_adjacent_category_partial_credit, grid)
    @test all(row -> row.response_sampling === :event_keyed_inverse_cdf, grid)
    @test all(row -> row.fitted_probability_or_likelihood_dependency === :none,
        grid)
    @test all(row -> !row.calibration_evidence_available &&
        !row.diagnostic_decision_labels_available &&
        !row.observed_data_mechanism_interpretation_eligible, grid)

    first_replication = filter(row -> row.replication == 1, grid)
    second_replication = filter(row -> row.replication == 2, grid)
    @test length(unique(row.seed for row in first_replication)) == 1
    @test length(unique(row.component_seeds for row in first_replication)) == 1
    @test length(unique(row.seed for row in second_replication)) == 1
    @test first(first_replication).seed + 1 == first(second_replication).seed
    @test first(first_replication).component_seeds !=
        first(second_replication).component_seeds
    @test length(unique(row.scenario_id for row in first_replication)) == 22

    pilot = local_dependence_simulation_grid(
        repetitions = 1, base_seed = 71, phase = :pilot)
    evaluation = local_dependence_simulation_grid(
        repetitions = 1, base_seed = 71, phase = :evaluation)
    @test first(pilot).seed == first(first_replication).seed + 10_000_000
    @test first(evaluation).seed == first(first_replication).seed + 20_000_000

    by_id = Dict(row.scenario_id => row for row in first_replication)
    @test by_id[:null_support_below_minimum].n_persons == 19
    @test by_id[:null_support_below_minimum].expected_diagnostic_pair_support === false
    @test by_id[:null_support_at_minimum].n_persons == 20
    @test by_id[:null_support_at_minimum].expected_diagnostic_pair_support === true
    @test by_id[:scalar_testlet_one_indicator_rejection].items_per_testlet == 1
    @test !by_id[:scalar_testlet_one_indicator_rejection].expected_requested_targets_eligible
    @test !by_id[:scalar_testlet_one_testlet_per_person_rejection].expected_requested_targets_eligible
    @test !by_id[:scalar_testlet_disconnected_rejection].expected_requested_targets_eligible
    @test by_id[:rater_response_halo_crossed].audit_targets ==
        (:rater_response_halo,)
    @test by_id[:rater_task_crossed].audit_targets == (:rater_task,)
    @test !by_id[:rater_task_nested_rejection].expected_requested_targets_eligible
    @test by_id[:temporal_sequence_ability_confounded].mechanism === :null
    @test by_id[:temporal_sequence_ability_confounded].order === :low_to_high
    @test by_id[:null_ability_informed_assignment].mechanism === :null
    @test by_id[:null_ability_informed_assignment].assignment ===
        :ability_informed
    @test by_id[:scalar_testlet_exact_zero].mechanism === :person_testlet
    @test by_id[:scalar_testlet_exact_zero].effect_scale == 0.0
    @test by_id[:scalar_testlet_connected_sparse].
        expected_diagnostic_pair_support === false
    supported_sparse = only(filter(
        row -> row.scenario_id === :scalar_testlet_connected_sparse,
        local_dependence_simulation_grid(n_persons = 40),
    ))
    @test supported_sparse.expected_diagnostic_pair_support === true

    @test_throws ArgumentError local_dependence_simulation_grid(profile = :other)
    @test_throws ArgumentError local_dependence_simulation_grid(repetitions = 0)
    @test_throws ArgumentError local_dependence_simulation_grid(
        repetitions = 10_000_001)
    @test_throws ArgumentError local_dependence_simulation_grid(base_seed = -1)
    @test_throws ArgumentError local_dependence_simulation_grid(phase = :other)
    @test_throws ArgumentError local_dependence_simulation_grid(grid_id = "")
    @test_throws ArgumentError local_dependence_simulation_grid(n_persons = 7)
    @test_throws ArgumentError local_dependence_simulation_grid(n_testlets = 3)
    @test_throws ArgumentError local_dependence_simulation_grid(items_per_testlet = 1)
    @test_throws ArgumentError local_dependence_simulation_grid(n_raters = 1)
    @test_throws ArgumentError local_dependence_simulation_grid(n_categories = 1)
    @test_throws ArgumentError simulate_local_dependence(:unknown_ld1_scenario)
end

@testset "LD1 exact-zero and reproducibility contracts" begin
    null_raw = ld1_generate_raw(
        seed = 812,
        mechanism = :null,
        effect_scale = 0.0,
    )
    exact_zero = ld1_generate_raw(
        seed = 812,
        mechanism = :person_testlet,
        effect_scale = 0.0,
    )
    repeated = ld1_generate_raw(
        seed = 812,
        mechanism = :null,
        effect_scale = 0.0,
    )
    changed_seed = ld1_generate_raw(
        seed = 813,
        mechanism = :null,
        effect_scale = 0.0,
    )

    @test isequal(null_raw.table, exact_zero.table)
    @test isequal(null_raw.row_truth, exact_zero.row_truth)
    @test isequal(null_raw.truth.component_scales,
        exact_zero.truth.component_scales)
    @test isequal(null_raw.table, repeated.table)
    @test isequal(null_raw.row_truth, repeated.row_truth)
    @test isequal(null_raw.truth, repeated.truth)
    @test null_raw.resource_counts.n_ratings ==
        changed_seed.resource_counts.n_ratings
    @test null_raw.truth.component_seeds != changed_seed.truth.component_seeds
    @test null_raw.row_truth.response_uniform !=
        changed_seed.row_truth.response_uniform
    @test null_raw.truth.person_ability != changed_seed.truth.person_ability

    @test length(unique(null_raw.table.event_id)) ==
        null_raw.resource_counts.n_ratings
    @test null_raw.raw_checks.probabilities_finite
    @test null_raw.raw_checks.probabilities_nonnegative
    @test null_raw.raw_checks.maximum_probability_sum_error <= 1.0e-12
    @test null_raw.raw_checks.score_support_valid
    @test null_raw.raw_checks.all_rows_observed
    @test null_raw.raw_checks.missingness_stream_reserved_not_applied
    @test !hasproperty(null_raw.truth, :global_local_independence_truth)
    @test null_raw.truth.sampling_independence_given_complete_truth
    @test null_raw.truth.baseline_mfrm_assumption_status ===
        :holds_by_construction
    @test null_raw.truth.baseline_mfrm_conditioning_set == (
        :person_ability,
        :rater_severity,
        :item_difficulty,
        :item_steps,
    )
    @test null_raw.truth.baseline_mfrm_omitted_active_truth_components == ()
    rng_contract = null_raw.truth.rng_contract
    @test rng_contract.version === :stable_namespace_semantic_key_v1
    @test rng_contract.component_seed_derivation ===
        :fnv1a64_namespace_then_splitmix64
    @test rng_contract.semantic_key_derivation ===
        :ordered_splitmix64_integer_key_fold
    @test rng_contract.engine === :Random_MersenneTwister
    @test rng_contract.normal_draw === :randn
    @test rng_contract.uniform_draw === :rand
    @test rng_contract.one_mersenne_twister_stream_per_semantic_key
    @test rng_contract.component_semantic_keys.person_ability ==
        (:person_index,)
    @test rng_contract.component_semantic_keys.item_difficulty ==
        (:testlet_index, :within_testlet_item)
    @test rng_contract.component_semantic_keys.rater_response_halo ==
        (:rater_index, :person_index, :testlet_index)
    @test rng_contract.component_semantic_keys.rater_task ==
        (:rater_index, :testlet_index)
    expected_uniform_key = (
        :seed,
        :person_index,
        :testlet_index,
        :rater_index,
        :within_testlet_item,
    )
    @test rng_contract.response_uniform_key == expected_uniform_key
    @test rng_contract.missingness_uniform_key == expected_uniform_key
    @test rng_contract.enumeration_order_invariant
    @test rng_contract.items_per_testlet_extension_preserves_common_event_uniforms
    @test !rng_contract.cross_julia_bitwise_portability_claimed
    @test null_raw.truth.active_mechanisms == ()
    @test null_raw.truth.person_testlet_target_truth === :null
    @test all(==("wave1"), null_raw.table.occasion)
    @test Set(null_raw.table.sequence_phase) == Set(["early", "middle", "late"])
    @test ld1_all_zero(null_raw.row_truth.response_occasion_shift)
end

@testset "LD1 component-stream extension invariance" begin
    two_items = ld1_generate_raw(
        seed = 20260720,
        n_persons = 12,
        n_testlets = 4,
        items_per_testlet = 2,
    )
    three_items = ld1_generate_raw(
        seed = 20260720,
        n_persons = 12,
        n_testlets = 4,
        items_per_testlet = 3,
    )
    two_item_rows = ld1_event_row_map(two_items)
    three_item_rows = ld1_event_row_map(three_items)
    @test issubset(Set(keys(two_item_rows)), Set(keys(three_item_rows)))
    for event_id in keys(two_item_rows)
        row_two = two_item_rows[event_id]
        row_three = three_item_rows[event_id]
        @test two_items.row_truth.response_uniform[row_two] ===
            three_items.row_truth.response_uniform[row_three]
        @test two_items.row_truth.missingness_uniform[row_two] ===
            three_items.row_truth.missingness_uniform[row_three]
    end

    nineteen = ld1_generate_raw(
        seed = 20260720,
        n_persons = 19,
        n_testlets = 4,
        items_per_testlet = 2,
        n_raters = 3,
    )
    twenty = ld1_generate_raw(
        seed = 20260720,
        n_persons = 20,
        n_testlets = 4,
        items_per_testlet = 2,
        n_raters = 3,
    )
    @test nineteen.truth.person_ability ==
        twenty.truth.person_ability[1:19]
    @test nineteen.truth.secondary_person_ability ==
        twenty.truth.secondary_person_ability[1:19]
    @test nineteen.truth.person_testlet_standard_normal ==
        twenty.truth.person_testlet_standard_normal[1:19, :]
    @test nineteen.truth.response_occasion_standard_normal ==
        twenty.truth.response_occasion_standard_normal[1:19, :]
    @test nineteen.truth.rater_response_halo_standard_normal ==
        twenty.truth.rater_response_halo_standard_normal[:, 1:(19 * 4)]
    for field in (
            :rater_severity,
            :item_difficulty,
            :item_steps,
            :q_matrix,
            :rater_task_double_centered_standard_normal,
            :temporal_rater_multipliers,
            :rater_label_permutation,
        )
        @test isequal(
            getproperty(nineteen.truth, field),
            getproperty(twenty.truth, field),
        )
    end
end

@testset "LD1 mechanism isolation and truth sidecars" begin
    fields = (;
        person_testlet = :person_testlet_shift,
        rater_response_halo = :rater_response_halo_shift,
        rater_task_severity = :rater_task_severity_shift,
        omitted_multidimensionality = :multidimensional_shift,
        severity_drift = :temporal_severity_shift,
    )
    expected_baseline_status = (;
        person_testlet = :shared_latent_component_omitted,
        rater_response_halo = :shared_latent_component_omitted,
        rater_task_severity = :mean_structure_misspecified,
        omitted_multidimensionality = :shared_latent_component_omitted,
        severity_drift = :mean_structure_misspecified,
    )
    all_component_fields = collect(values(fields))
    for (mechanism, active_field) in pairs(fields)
        raw = ld1_generate_raw(
            seed = 91,
            mechanism = mechanism,
            effect_scale = 0.5,
        )
        @test any(value -> !iszero(value),
            getproperty(raw.row_truth, active_field))
        @test !hasproperty(raw.truth, :global_local_independence_truth)
        @test raw.truth.sampling_independence_given_complete_truth
        @test raw.truth.baseline_mfrm_assumption_status ===
            getproperty(expected_baseline_status, mechanism)
        @test raw.truth.baseline_mfrm_conditioning_set == (
            :person_ability,
            :rater_severity,
            :item_difficulty,
            :item_steps,
        )
        @test raw.truth.baseline_mfrm_omitted_active_truth_components ==
            raw.truth.active_mechanisms
        for field in all_component_fields
            field === active_field && continue
            @test ld1_all_zero(getproperty(raw.row_truth, field))
        end
        @test ld1_all_zero(raw.row_truth.response_occasion_shift)
        reconstructed = raw.row_truth.baseline_location .+
            raw.row_truth.person_testlet_shift .+
            raw.row_truth.rater_response_halo_shift .-
            raw.row_truth.rater_task_severity_shift .+
            raw.row_truth.multidimensional_shift .-
            raw.row_truth.temporal_severity_shift
        @test reconstructed ≈ raw.row_truth.total_location atol = 1.0e-14 rtol = 0.0
    end

    combined = ld1_generate_raw(
        seed = 91,
        mechanism = :person_testlet_plus_drift,
        effect_scale = 0.5,
    )
    @test any(value -> !iszero(value),
        combined.row_truth.person_testlet_shift)
    @test any(value -> !iszero(value),
        combined.row_truth.temporal_severity_shift)
    @test combined.truth.baseline_mfrm_assumption_status ===
        :shared_latent_component_and_mean_structure_misspecified
    @test ld1_all_zero(combined.row_truth.rater_response_halo_shift)
    @test ld1_all_zero(combined.row_truth.rater_task_severity_shift)
    @test ld1_all_zero(combined.row_truth.multidimensional_shift)

    multidimensional = ld1_generate_raw(
        seed = 91,
        mechanism = :omitted_multidimensionality,
        effect_scale = 0.5,
    )
    for row in eachindex(multidimensional.table.score)
        person = multidimensional.row_truth.person_index[row]
        item = multidimensional.row_truth.item_index[row]
        expected = multidimensional.truth.q_matrix[item, 2] ?
            (sqrt(1 - 0.5^2) - 1) *
                multidimensional.truth.person_ability[person] +
            0.5 * multidimensional.truth.secondary_person_ability[person] :
            0.0
        @test multidimensional.row_truth.multidimensional_shift[row] ≈ expected
    end

    near_zero = ld1_generate_raw(
        seed = 91,
        mechanism = :person_testlet,
        effect_scale = 0.05,
    )
    moderate = ld1_generate_raw(
        seed = 91,
        mechanism = :person_testlet,
        effect_scale = 0.5,
    )
    @test moderate.row_truth.person_testlet_shift ≈
        10 .* near_zero.row_truth.person_testlet_shift
    @test near_zero.row_truth.response_uniform ==
        moderate.row_truth.response_uniform
    @test near_zero.row_truth.baseline_location ==
        moderate.row_truth.baseline_location

    centered = moderate.truth.rater_task_double_centered_standard_normal
    @test maximum(abs.(vec(sum(centered; dims = 1)))) <= 1.0e-12
    @test maximum(abs.(vec(sum(centered; dims = 2)))) <= 1.0e-12
    @test moderate.truth.rater_severity[1] == 0.0
    @test moderate.truth.item_difficulty[1] == 0.0
    @test all(moderate.truth.q_matrix[:, 1])
    @test any(moderate.truth.q_matrix[:, 2])
    @test any(.!moderate.truth.q_matrix[:, 2])
    for testlet in 1:4
        rows = ((testlet - 1) * 2 + 1):(testlet * 2)
        @test any(moderate.truth.q_matrix[rows, 2])
        @test any(.!moderate.truth.q_matrix[rows, 2])
    end
    @test all(sum(moderate.truth.item_steps; dims = 2) .== 0.0)
end

@testset "LD1 event-keyed order-confounding control" begin
    randomized = ld1_generate_raw(
        seed = 404,
        mechanism = :null,
        effect_scale = 0.0,
        order = :randomized,
    )
    ability_ordered = ld1_generate_raw(
        seed = 404,
        mechanism = :null,
        effect_scale = 0.0,
        order = :low_to_high,
    )
    random_map = ld1_event_row_map(randomized)
    ordered_map = ld1_event_row_map(ability_ordered)
    @test Set(keys(random_map)) == Set(keys(ordered_map))
    @test any(event_id -> randomized.row_truth.sequence_index[
            random_map[event_id]] != ability_ordered.row_truth.sequence_index[
            ordered_map[event_id]], keys(random_map))
    for event_id in keys(random_map)
        random_row = random_map[event_id]
        ordered_row = ordered_map[event_id]
        @test randomized.row_truth.canonical_row[random_row] ==
            ability_ordered.row_truth.canonical_row[ordered_row]
        @test randomized.row_truth.response_uniform[random_row] ==
            ability_ordered.row_truth.response_uniform[ordered_row]
        @test randomized.row_truth.baseline_location[random_row] ==
            ability_ordered.row_truth.baseline_location[ordered_row]
        @test randomized.row_truth.total_location[random_row] ==
            ability_ordered.row_truth.total_location[ordered_row]
        @test randomized.row_truth.probabilities[random_row, :] ==
            ability_ordered.row_truth.probabilities[ordered_row, :]
        @test randomized.table.score[random_row] ==
            ability_ordered.table.score[ordered_row]
    end

    for rater in unique(ability_ordered.row_truth.rater_index)
        event_rows = Dict{Int,Int}()
        for row in eachindex(ability_ordered.table.score)
            ability_ordered.row_truth.rater_index[row] == rater || continue
            response = ability_ordered.row_truth.response_index[row]
            get!(event_rows, response, row)
        end
        rows = sort!(collect(values(event_rows)); by = row ->
            ability_ordered.row_truth.sequence_index[row])
        ordered_abilities = [ability_ordered.truth.person_ability[
            ability_ordered.row_truth.person_index[row]] for row in rows]
        @test issorted(ordered_abilities)
    end
end

@testset "LD1 rating skeletons and resource guards" begin
    same = ld1_generate_raw(design = :same_rater)
    crossed = ld1_generate_raw(design = :fully_crossed_raters)
    mixed = ld1_generate_raw(design = :mixed_testlet_applicability)
    sparse = ld1_generate_raw(design = :connected_sparse)
    ability_assigned = ld1_generate_raw(assignment = :ability_informed)
    one_testlet = ld1_generate_raw(design = :one_testlet_per_person)
    disconnected = ld1_generate_raw(
        design = :disconnected_blocks,
        assignment = :task_nested,
        order = :testlet_blocked,
    )

    @test same.resource_counts.n_ratings == 12 * 4 * 2
    @test crossed.resource_counts.n_ratings == 12 * 4 * 2 * 3
    @test mixed.resource_counts.n_ratings == same.resource_counts.n_ratings
    @test sparse.resource_counts.n_ratings == 12 * 2 * 2
    @test ability_assigned.resource_counts.n_ratings ==
        same.resource_counts.n_ratings
    @test one_testlet.resource_counts.n_ratings == 12 * 2
    @test disconnected.resource_counts.n_ratings == 12 * 2 * 2
    for raw in (same, crossed, mixed, sparse, ability_assigned, one_testlet,
            disconnected)
        @test raw.resource_counts.n_probability_cells ==
            raw.resource_counts.n_ratings * 4
        @test raw.resource_counts.n_truth_cells <=
            raw.resource_counts.max_truth_cells
        @test raw.resource_counts.n_truth_cells ==
            ld1_expected_truth_cells(raw)
        @test raw.resource_counts.max_truth_cells == 5_000_000
        truth_breakdown = raw.resource_counts.truth_cell_breakdown
        @test truth_breakdown.facet_truth + truth_breakdown.row_truth ==
            raw.resource_counts.n_truth_cells
        @test truth_breakdown.row_truth_vectors +
            truth_breakdown.pointwise_probabilities ==
            truth_breakdown.row_truth
        @test length(unique(raw.table.event_id)) ==
            raw.resource_counts.n_ratings
        response_membership = Dict{String,Tuple{Int,Int}}()
        for row in eachindex(raw.table.score)
            key = raw.table.response_id[row]
            membership = (
                raw.row_truth.person_index[row],
                raw.row_truth.testlet_index[row],
            )
            @test get!(response_membership, key, membership) == membership
        end
    end

    for response in unique(crossed.row_truth.response_index)
        rows = findall(==(response), crossed.row_truth.response_index)
        @test length(unique(crossed.row_truth.rater_index[rows])) == 3
    end
    for response in unique(mixed.row_truth.response_index)
        rows = findall(==(response), mixed.row_truth.response_index)
        n_response_raters = length(unique(mixed.row_truth.rater_index[rows]))
        testlet = first(mixed.row_truth.testlet_index[rows])
        @test n_response_raters == (iseven(testlet) ? 2 : 1)
    end
    @test all(count(==(person), one_testlet.row_truth.person_index) == 2
        for person in 1:12)
    @test all(row -> isodd(disconnected.row_truth.person_index[row]) ?
        disconnected.row_truth.testlet_index[row] <= 2 :
        disconnected.row_truth.testlet_index[row] > 2,
        eachindex(disconnected.table.score))

    person_rater = Dict{Int,Int}()
    for row in eachindex(ability_assigned.table.score)
        person = ability_assigned.row_truth.person_index[row]
        rater = ability_assigned.row_truth.rater_index[row]
        @test get!(person_rater, person, rater) == rater
    end
    sorted_persons = sortperm(ability_assigned.truth.person_ability)
    rater_bucket = invperm(collect(
        ability_assigned.truth.rater_label_permutation))
    assigned_buckets = [rater_bucket[person_rater[person]]
        for person in sorted_persons]
    @test issorted(assigned_buckets)
    @test length(unique(values(person_rater))) == 3
    @test all(==("ability_informed"),
        ability_assigned.table.assignment_reason)

    @test_throws ArgumentError ld1_generate_raw(max_ratings = 95)
    @test_throws ArgumentError ld1_generate_raw(max_probability_cells = 383)
    @test ld1_raw_config().max_truth_cells == 5_000_000
    @test_throws ArgumentError ld1_generate_raw(max_truth_cells = 0)
    @test_throws ArgumentError ld1_generate_raw(max_truth_cells = 1)
    huge_truth_error = try
        ld1_generate_raw(
            n_persons = 1_000_000_000,
            n_testlets = 4,
            items_per_testlet = 2,
            n_raters = 3,
            max_ratings = typemax(Int),
            max_probability_cells = typemax(Int),
            max_truth_cells = 10,
        )
        nothing
    catch error
        error
    end
    @test huge_truth_error isa ArgumentError
    if huge_truth_error isa ArgumentError
        message = sprint(showerror, huge_truth_error)
        @test occursin("known-truth scalar count", message)
        @test occursin("configured limit 10", message)
    end
    @test_throws ArgumentError ld1_generate_raw(seed = -1)
    @test_throws ArgumentError ld1_generate_raw(n_persons = 3)
    @test_throws ArgumentError ld1_generate_raw(n_testlets = 1)
    @test_throws ArgumentError ld1_generate_raw(n_raters = 1)
    @test_throws ArgumentError ld1_generate_raw(n_categories = 1)
    @test_throws ArgumentError ld1_generate_raw(mechanism = :unknown)
    @test_throws ArgumentError ld1_generate_raw(effect_scale = -0.1)
    @test_throws ArgumentError ld1_generate_raw(effect_scale = NaN)
    @test_throws ArgumentError ld1_generate_raw(
        mechanism = :omitted_multidimensionality, effect_scale = 1.01)
    @test_throws ArgumentError ld1_generate_raw(design = :unknown)
    @test_throws ArgumentError ld1_generate_raw(assignment = :unknown)
    @test_throws ArgumentError ld1_generate_raw(order = :unknown)
    @test_throws ArgumentError ld1_generate_raw(
        design = :disconnected_blocks, n_testlets = 2)
end

@testset "LD1 public adapter, row integrity, and category scale" begin
    row = first(local_dependence_simulation_grid(
        base_seed = 515,
        n_persons = 8,
        n_testlets = 4,
        items_per_testlet = 2,
        n_raters = 2,
        n_categories = 3,
    ))
    simulation = simulate_local_dependence(row)
    @test simulation.schema ==
        "bayesianmgmfrm.local_dependence_simulation.v1"
    @test simulation.object === :local_dependence_simulation
    @test simulation.status === :known_truth_generated
    @test simulation.summary.passed
    @test simulation.scenario_id === :null_same_rater
    @test simulation.generator_contract.fitted_probability_or_likelihood_dependency === :none
    @test simulation.generator_contract.sampling === :event_keyed_inverse_cdf
    @test simulation.generator_contract.occasion_role ===
        :response_level_categorical_sidecar_not_elapsed_time
    @test simulation.generator_contract.sequence_phase_role ===
        :derived_from_explicit_within_rater_sequence
    @test length(simulation.generator_contract.known_truth_source_signature.value) == 64
    @test simulation.truth_known_by_construction
    @test simulation.calibration_status === :evaluation_not_run
    @test !simulation.calibration_evidence_available
    @test !simulation.diagnostic_decision_labels_available
    @test !simulation.observed_data_mechanism_interpretation_eligible
    @test simulation.data.category_levels == [0, 1, 2]
    @test simulation.checks.intended_category_scale_preserved
    @test simulation.checks.standalone_generator_path_used
    @test simulation.checks.generator_checks_passed
    @test !hasproperty(
        simulation.checks, :standalone_generator_contract_passed)
    @test simulation.checks.unique_event_ids
    @test !hasproperty(
        simulation.design_support.rating_design.anchor_linking, :next_gate)
    @test simulation.resource_counts.n_ratings == 8 * 4 * 2
    @test simulation.resource_counts.n_probability_cells == 8 * 4 * 2 * 3
    @test simulation.resource_counts.n_truth_cells ==
        ld1_expected_truth_cells(simulation)
    @test length(simulation.score_signature) == 64
    @test simulation.data_signature == simulation.validation.data_signature
    @test simulation.caveat ===
        :generator_and_preflight_evidence_not_calibration_or_mechanism_classification

    @test_throws ArgumentError simulate_local_dependence(
        row; max_ratings = simulation.resource_counts.n_ratings - 1)
    @test_throws ArgumentError simulate_local_dependence(
        row;
        max_probability_cells =
            simulation.resource_counts.n_probability_cells - 1,
    )
    @test_throws ArgumentError simulate_local_dependence(
        row;
        max_truth_cells = simulation.resource_counts.n_truth_cells - 1,
    )
    @test_throws ArgumentError simulate_local_dependence(
        row; max_truth_cells = 0)
    @test_throws ArgumentError simulate_local_dependence(
        Base.structdiff(row, (; magnitude_label = nothing)))

    for forged in (
            merge(row, (; schema = "forged")),
            merge(row, (; object = :forged)),
            merge(row, (; profile = :forged)),
            merge(row, (; status = :known_truth_generated)),
            merge(row, (; scenario_index = row.scenario_index + 1)),
            merge(row, (; scenario_id = :forged)),
            merge(row, (; matched_set_id = :forged)),
            merge(row, (; base_seed = row.base_seed + 1)),
            merge(row, (; base_seed = Float64(row.base_seed))),
            merge(row, (; replication = row.replication + 1)),
            merge(row, (; phase = :pilot)),
            merge(row, (; component_seeds = merge(
                row.component_seeds,
                (; design = row.component_seeds.design + 1),
            ))),
            merge(row, (; family = :gmfrm)),
            merge(row, (; thresholds = :rating_scale)),
            merge(row, (; mechanism = :severity_drift)),
            merge(row, (; magnitude_label = :large)),
            merge(row, (; effect_scale = 0.5)),
            merge(row, (; design = :fully_crossed_raters)),
            merge(row, (; assignment = :task_nested)),
            merge(row, (; order = :low_to_high)),
            merge(row, (; audit_targets = (:rater_task,))),
            merge(row, (; expected_requested_targets_eligible = false)),
            merge(row, (; expected_diagnostic_pair_support = true)),
        )
        @test_throws ArgumentError simulate_local_dependence(forged)
    end
    @test_throws ArgumentError simulate_local_dependence(
        merge(row, (; unexpected_field = true)))
    @test_throws ArgumentError simulate_local_dependence((; scenario_id = :null_same_rater))

    incomplete_raw = ld1_generate_raw(
        seed = 1,
        n_persons = 4,
        n_testlets = 2,
        items_per_testlet = 1,
        n_raters = 2,
        n_categories = 8,
    )
    incomplete_data = BayesianMGMFRM._ld1_facet_data(incomplete_raw)
    @test incomplete_data.category_levels == collect(0:7)
    @test all(score -> score in incomplete_data.category_levels,
        incomplete_data.score)
    @test Tuple(incomplete_data.category_levels) ==
        incomplete_raw.truth.intended_category_levels
end

@testset "LD1 committed known-truth preflight artifact" begin
    root = dirname(@__DIR__)
    fixture_path = joinpath(
        root, "test", "fixtures", "local_dependence_known_truth_preflight.json")
    fixture_text = read(fixture_path, String)
    fixture = JSON3.read(fixture_text)
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.local_dependence_known_truth_preflight.v1"
    @test String(fixture[:status]) ==
        "generator_contract_passed_calibration_not_run"
    @test Bool(fixture[:summary][:passed])
    @test Int(fixture[:summary][:n_scenarios]) == 22
    @test Int(fixture[:summary][:n_scenarios_passed]) == 22
    @test Bool(fixture[:summary][:source_independence_passed])
    @test Bool(fixture[:summary][:exact_zero_check_passed])
    @test Bool(fixture[:summary][:ability_order_check_passed])
    @test Bool(fixture[:summary][:ability_assignment_check_passed])
    @test Int(fixture[:summary][:n_mechanism_checks]) == 6
    @test Int(fixture[:summary][:n_mechanism_checks_passed]) == 6
    @test Bool(fixture[:summary][:design_boundary_checks_passed])
    @test !Bool(fixture[:summary][:repeated_calibration_completed])
    @test String(fixture[:summary][:subsequent_stage]) ==
        "ld1b_repeated_null_and_alternative_calibration"
    @test !haskey(fixture[:package], :julia_version)

    scenario_rows = fixture[:scenario_summaries]
    @test length(scenario_rows) == 22
    @test all(row -> Bool(row[:passed]), scenario_rows)
    @test Set(String(row[:scenario_id]) for row in scenario_rows) ==
        Set(String(row.scenario_id) for row in
            local_dependence_simulation_grid())
    @test all(row -> String(row[:truth_surface_encoding]) ==
        "local_json_shape_explicit_matrix_row_major_v1", scenario_rows)
    @test Bool(fixture[:paired_checks][:exact_zero][:passed])
    @test Bool(fixture[:paired_checks][:ability_order][:passed])
    @test Bool(fixture[:paired_checks][:ability_assignment][:passed])
    @test all(row -> Bool(row[:passed]),
        fixture[:paired_checks][:mechanism_rows])
    @test Bool(fixture[:paired_checks][:design_boundaries][:passed])

    claims = fixture[:claim_boundaries]
    @test Bool(claims[:truth_known_by_construction])
    @test Bool(claims[:generator_contract_evidence_available])
    for field in (
            :repeated_calibration_completed,
            :calibration_evidence_available,
            :diagnostic_decision_labels_available,
            :observed_data_mechanism_interpretation_eligible,
            :parameter_recovery_claim_supported,
            :diagnostic_power_or_error_rate_claim_supported,
            :public_claim_release_allowed,
        )
        @test !Bool(claims[field])
    end

    generator = fixture[:generator]
    @test Bool(generator[:deterministic_within_recorded_rng_contract])
    @test !Bool(generator[:rng_contract][
        :cross_julia_bitwise_portability_claimed])
    provenance = generator[:environment_provenance]
    @test !Bool(provenance[:exact_runtime_version_recorded])
    @test !Bool(provenance[:cross_julia_bitwise_portability_claimed])
    @test String(provenance[:project_sha256]) ==
        bytes2hex(open(sha256, joinpath(root, "Project.toml")))
    @test String(provenance[:manifest_sha256]) ==
        bytes2hex(open(sha256, joinpath(root, "Manifest.toml")))
    for (field, relative_path) in (
            (:script_source_sha256,
                "scripts/generate_local_dependence_known_truth_preflight.jl"),
            (:known_truth_source_sha256,
                "src/local_dependence_known_truth_dgp.jl"),
            (:adapter_source_sha256, "src/local_dependence_simulation.jl"),
        )
        @test String(generator[field]) ==
            bytes2hex(open(sha256, joinpath(root, relative_path)))
    end
    @test !occursin(root, fixture_text)

    native = ld1_json_value(fixture)
    stored_hash = String(native["content_hash"]["value"])
    delete!(native, "content_hash")
    io = IOBuffer()
    write_canonical_json(io, native)
    @test stored_hash == bytes2hex(sha256(take!(io)))
end
