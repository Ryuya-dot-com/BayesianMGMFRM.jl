#!/usr/bin/env julia

using Random
using SHA
using Statistics
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT = joinpath(
    ROOT,
    "test",
    "fixtures",
    "mgmfrm_literature_anchored_synthetic_benchmark.json",
)
const ORACLE_TOLERANCE = 1.0e-12
const BASE_SEED = 20260707

include(joinpath(@__DIR__, "local_json.jl"))

const REFERENCE_RECORDS = [
    (;
        citation_key = :uto_ueno_2020_gmfrm,
        source = :doi,
        title =
            "A generalized many-facet Rasch model and its Bayesian estimation using Hamiltonian Monte Carlo",
        author = "Uto, Masaki; Ueno, Maomi",
        year = 2020,
        journal = "Behaviormetrika",
        doi = "10.1007/s41237-020-00115-7",
        url = "https://doi.org/10.1007/s41237-020-00115-7",
    ),
    (;
        citation_key = :uto_2021_mgmfrm,
        source = :doi,
        title =
            "A multidimensional generalized many-facet Rasch model for rubric-based performance assessment",
        author = "Uto, Masaki",
        year = 2021,
        journal = "Behaviormetrika",
        doi = "10.1007/s41237-021-00144-w",
        url = "https://doi.org/10.1007/s41237-021-00144-w",
    ),
    (;
        citation_key = :da_silva_etal_2019_q_matrix,
        source = :doi,
        title =
            "Incorporating the Q-Matrix Into Multidimensional Item Response Theory Models",
        author = "da Silva, Marcelo A.; and colleagues",
        year = 2019,
        journal = "Educational and Psychological Measurement",
        doi = "10.1177/0013164418814898",
        url = "https://doi.org/10.1177/0013164418814898",
    ),
    (;
        citation_key = :wang_wilson_2005_mrcml_conquest,
        source = :doi,
        title = "The Rasch Testlet Model",
        author = "Wang, Wen-Chung; Wilson, Mark",
        year = 2005,
        journal = "Applied Psychological Measurement",
        doi = "10.1177/0146621604271053",
        url = "https://doi.org/10.1177/0146621604271053",
    ),
]

const BENCHMARK_SPECIFICATIONS = [
    (;
        benchmark_id = :uto_ueno_2020_scalar_recovery_smallest_cell,
        reference = :uto_ueno_2020_gmfrm,
        materialization = :pilot_dataset_materialized,
        source_design = (;
            persons = [30, 50, 100],
            items = [3, 4, 5],
            raters = [5, 10, 30],
            categories = 5,
            replications = 10,
        ),
        selected_pilot_cell = (;
            persons = 30,
            items = 3,
            raters = 5,
            categories = 5,
            replications_materialized = 1,
        ),
        alignment = (;
            sample_size_cell = :paper_exact,
            fully_crossed_assignment = :paper_exact,
            likelihood_core = :paper_and_package_overlap,
            parameter_distributions = :paper_anchored_with_identifying_transforms,
            range_restriction_component = :not_included,
        ),
    ),
    (;
        benchmark_id = :uto_2021_fixed_q_recovery_smallest_cell,
        reference = :uto_2021_mgmfrm,
        materialization = :pilot_dataset_materialized,
        source_design = (;
            persons = [50, 100],
            items = [5, 15],
            raters = [5, 15],
            dimensions = [1, 2, 3],
            categories = 4,
            replications = 30,
        ),
        selected_pilot_cell = (;
            persons = 50,
            items = 5,
            raters = 5,
            dimensions = 2,
            categories = 4,
            replications_materialized = 1,
        ),
        alignment = (;
            sample_size_cell = :paper_exact,
            fully_crossed_assignment = :paper_exact,
            likelihood_core = :paper_and_package_overlap,
            ability_combination = :loading_weighted_sum,
            loading_structure = :package_adapted_fixed_q,
            paper_nonprimary_anchor_loading = 0.2,
            package_inactive_loading = 0.0,
            exploratory_loading_recovery = :not_claimed,
        ),
    ),
    (;
        benchmark_id = :da_silva_2019_q_mask_stress_grid,
        reference = :da_silva_etal_2019_q_matrix,
        materialization = :design_only,
        source_design = (;
            persons = [500, 1000],
            items = 28,
            dimensions = 3,
            categories = 2,
            replications = 10,
        ),
        reason_not_materialized =
            :binary_mirt_without_rater_facet_is_a_q_mask_stress_source_not_an_exact_mgmfrm_target,
    ),
    (;
        benchmark_id = :wang_wilson_2005_conquest_mrcml_bridge,
        reference = :wang_wilson_2005_mrcml_conquest,
        materialization = :design_only,
        source_design = (;
            persons = [200, 500],
            testlets = [4, 8],
            response_types = [:dichotomous, :polytomous, :mixed],
            replications = 100,
            external_software = :conquest,
        ),
        reason_not_materialized =
            :mrcml_testlet_bridge_requires_a_separately_aligned_parameterization_and_output_adapter,
    ),
]

function parse_args(args)
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index == length(args) && error("--output requires a path")
            index += 1
            output = abspath(args[index])
        elseif arg in ("-h", "--help")
            println("Usage: julia --project=. scripts/$(basename(@__FILE__)) [--output PATH]")
            exit(0)
        else
            error("unknown argument: $arg")
        end
        index += 1
    end
    return output
end

project_version() = String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])

function file_sha256(path::AbstractString)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

function canonical_json_sha256(value)
    io = IOBuffer()
    write_json(io, value)
    return bytes2hex(sha256(take!(io)))
end

matrix_rows(matrix::AbstractMatrix) = [
    [matrix[row, column] for column in axes(matrix, 2)]
    for row in axes(matrix, 1)
]

function centered(values)
    output = collect(Float64, values)
    output .-= mean(output)
    return output
end

function geometric_mean_one(values)
    output = collect(Float64, values)
    output ./= exp(mean(log.(output)))
    return output
end

function identified_source_steps(rng::AbstractRNG, n_facets::Int, categories::Int)
    categories >= 2 || error("categories must be at least two")
    steps = zeros(Float64, n_facets, categories)
    free_steps = max(categories - 2, 0)
    for facet in 1:n_facets
        for column in 1:free_steps
            steps[facet, column + 1] = randn(rng)
        end
        categories > 2 &&
            (steps[facet, categories] = -sum(@view steps[facet, 2:(categories - 1)]))
    end
    return steps
end

function softmax(values)
    shifted = values .- maximum(values)
    weights = exp.(shifted)
    return weights ./ sum(weights)
end

function sample_score(rng::AbstractRNG, probabilities, category_levels)
    draw = rand(rng)
    cumulative = 0.0
    for category in eachindex(probabilities)
        cumulative += probabilities[category]
        draw <= cumulative && return category_levels[category]
    end
    return last(category_levels)
end

function full_cross_columns(n_persons::Int, n_raters::Int, n_items::Int;
        scores = nothing, categories::Int)
    person = Int[]
    rater = Int[]
    item = Int[]
    score = Int[]
    row = 0
    for person_index in 1:n_persons,
            rater_index in 1:n_raters,
            item_index in 1:n_items
        row += 1
        push!(person, person_index)
        push!(rater, rater_index)
        push!(item, item_index)
        push!(score, scores === nothing ? mod(row - 1, categories) : Int(scores[row]))
    end
    return (; person, rater, item, score)
end

function facet_data(columns)
    return BayesianMGMFRM.FacetData((;
            examinee = columns.person,
            rater = columns.rater,
            item = columns.item,
            score = columns.score,
        );
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

function gmfrm_truth(rng::AbstractRNG, n_persons::Int, n_raters::Int,
        n_items::Int, categories::Int)
    item_discrimination = geometric_mean_one(exp.(randn(rng, n_items)))
    return (;
        person_ability = randn(rng, n_persons),
        item_difficulty = centered(randn(rng, n_items)),
        item_discrimination,
        rater_severity = randn(rng, n_raters),
        rater_consistency = exp.(randn(rng, n_raters)),
        rater_steps = identified_source_steps(rng, n_raters, categories),
    )
end

function gmfrm_probability(truth, person::Int, rater::Int, item::Int,
        categories::Int)
    location = truth.person_ability[person] - truth.item_difficulty[item] -
        truth.rater_severity[rater]
    scale = truth.item_discrimination[item] * truth.rater_consistency[rater]
    eta = zeros(Float64, categories)
    for category in 2:categories
        eta[category] = eta[category - 1] +
            scale * (location - truth.rater_steps[rater, category])
    end
    return softmax(eta)
end

function fixed_q()
    return Bool[
        1 0
        0 1
        1 0
        0 1
        1 1
    ]
end

function mgmfrm_truth(rng::AbstractRNG, n_persons::Int, n_raters::Int,
        n_items::Int, dimensions::Int, categories::Int, q_matrix)
    dimensions == 2 || error("the committed pilot uses two dimensions")
    n_items == 5 || error("the committed pilot uses five items")
    loadings = zeros(Float64, n_items, dimensions)
    for item in 1:n_items, dimension in 1:dimensions
        q_matrix[item, dimension] || continue
        loadings[item, dimension] = exp(randn(rng))
    end
    loadings[1, 1] = 1.5
    loadings[2, 2] = 1.5
    return (;
        person_ability = randn(rng, n_persons, dimensions),
        item_difficulty = randn(rng, n_items),
        item_dimension_discrimination = loadings,
        rater_severity = centered(randn(rng, n_raters)),
        rater_consistency = geometric_mean_one(exp.(randn(rng, n_raters))),
        item_steps = identified_source_steps(rng, n_items, categories),
    )
end

function mgmfrm_probability(truth, person::Int, rater::Int, item::Int,
        categories::Int)
    ability_score = sum(
        truth.item_dimension_discrimination[item, dimension] *
        truth.person_ability[person, dimension]
        for dimension in axes(truth.person_ability, 2)
    )
    location = ability_score - truth.item_difficulty[item] -
        truth.rater_severity[rater]
    scale = 1.7 * truth.rater_consistency[rater]
    eta = zeros(Float64, categories)
    for category in 2:categories
        eta[category] = eta[category - 1] +
            scale * (location - truth.item_steps[item, category])
    end
    return softmax(eta)
end

function gmfrm_direct_params(design, truth)
    params = zeros(Float64, length(design.parameter_names))
    data = design.spec.data
    for (index, level) in pairs(data.person_levels)
        params[design.blocks[:person][index]] = truth.person_ability[Int(level)]
    end
    for (index, level) in pairs(data.rater_levels)
        rater = Int(level)
        params[design.blocks[:rater][index]] = truth.rater_severity[rater]
        params[design.blocks[:rater_consistency][index]] = truth.rater_consistency[rater]
    end
    for (index, level) in pairs(data.item_levels)
        item = Int(level)
        params[design.blocks[:item][index]] = truth.item_difficulty[item]
        params[design.blocks[:item_discrimination][index]] =
            truth.item_discrimination[item]
    end
    free_steps = max(length(data.category_levels) - 2, 0)
    for rater in eachindex(data.rater_levels), free_step in 1:free_steps
        offset = (rater - 1) * free_steps
        params[design.blocks[:rater_steps][offset + free_step]] =
            truth.rater_steps[rater, free_step + 1]
    end
    return params
end

function mgmfrm_direct_params(design, truth)
    params = zeros(Float64, length(design.parameter_names))
    data = design.spec.data
    dimensions = design.spec.dimensions
    for (index, level) in pairs(data.person_levels), dimension in 1:dimensions
        params[design.blocks[:person][(index - 1) * dimensions + dimension]] =
            truth.person_ability[Int(level), dimension]
    end
    for (index, level) in pairs(data.rater_levels)
        rater = Int(level)
        params[design.blocks[:rater][index]] = truth.rater_severity[rater]
        params[design.blocks[:rater_consistency][index]] = truth.rater_consistency[rater]
    end
    for (index, level) in pairs(data.item_levels)
        params[design.blocks[:item][index]] = truth.item_difficulty[Int(level)]
    end
    index_by_name = Dict(name => index for (index, name) in pairs(design.parameter_names))
    for (item_index, item_level) in pairs(data.item_levels), dimension in 1:dimensions
        design.spec.q_matrix[item_index, dimension] || continue
        name = "item_dimension_discrimination[item=$(item_level),$(design.spec.dimension_labels[dimension])]"
        params[index_by_name[name]] =
            truth.item_dimension_discrimination[Int(item_level), dimension]
    end
    free_steps = max(length(data.category_levels) - 2, 0)
    for item in eachindex(data.item_levels), free_step in 1:free_steps
        offset = (item - 1) * free_steps
        params[design.blocks[:item_steps][offset + free_step]] =
            truth.item_steps[item, free_step + 1]
    end
    return params
end

function oracle_probability_matrix(design, direct_params, family::Symbol)
    values = family === :gmfrm ?
        BayesianMGMFRM._gmfrm_source_fixture_values(design, direct_params) :
        BayesianMGMFRM._mgmfrm_source_fixture_values(design, direct_params)
    probabilities = zeros(Float64, design.spec.data.n,
        length(design.spec.data.category_levels))
    for row in values
        probabilities[Int(row.row), Int(row.category_index)] =
            exp(Float64(row.log_probability))
    end
    return probabilities
end

function observation_sha256(columns)
    io = IOBuffer()
    println(io, "person,rater,item,score")
    for row in eachindex(columns.person)
        println(io, columns.person[row], ',', columns.rater[row], ',',
            columns.item[row], ',', columns.score[row])
    end
    return bytes2hex(sha256(take!(io)))
end

function probability_check_rows(columns, independent, oracle)
    indices = unique([1, cld(length(columns.person), 2), length(columns.person)])
    return [(;
        row,
        person = columns.person[row],
        rater = columns.rater[row],
        item = columns.item[row],
        independent_generator_probabilities = vec(independent[row, :]),
        package_source_oracle_probabilities = vec(oracle[row, :]),
        max_abs_error = maximum(abs.(independent[row, :] .- oracle[row, :])),
    ) for row in indices]
end

function category_count_rows(scores, category_levels)
    return [(; category, count = count(==(category), scores))
        for category in category_levels]
end

function build_gmfrm_dataset()
    truth_seed = BASE_SEED + 100000 + 100 + 1000 + 1
    response_seed = BASE_SEED + 100000 + 100 + 1000 + 3
    n_persons, n_items, n_raters, categories = 30, 3, 5, 5
    category_levels = collect(0:(categories - 1))
    truth_rng = MersenneTwister(truth_seed)
    response_rng = MersenneTwister(response_seed)
    truth = gmfrm_truth(truth_rng, n_persons, n_raters, n_items, categories)
    dummy = full_cross_columns(n_persons, n_raters, n_items; categories)
    independent = zeros(Float64, length(dummy.person), categories)
    for row in eachindex(dummy.person)
        independent[row, :] = gmfrm_probability(
            truth,
            dummy.person[row],
            dummy.rater[row],
            dummy.item[row],
            categories,
        )
    end
    data = facet_data(dummy)
    spec = BayesianMGMFRM.mfrm_spec(data;
        family = :gmfrm,
        discrimination = :rater,
    )
    design = BayesianMGMFRM.getdesign(spec; preview = true)
    oracle = oracle_probability_matrix(
        design,
        gmfrm_direct_params(design, truth),
        :gmfrm,
    )
    oracle_error = maximum(abs.(independent .- oracle))
    oracle_error <= ORACLE_TOLERANCE ||
        error("standalone GMFRM generator disagrees with source oracle: $oracle_error")
    scores = [sample_score(response_rng, @view(independent[row, :]), category_levels)
        for row in axes(independent, 1)]
    observations = full_cross_columns(n_persons, n_raters, n_items;
        scores,
        categories,
    )
    counts = category_count_rows(scores, category_levels)
    all(row -> row.count > 0, counts) ||
        error("GMFRM pilot did not realize every category")
    truth_record = (;
        person_ability = truth.person_ability,
        item_difficulty = truth.item_difficulty,
        item_discrimination = truth.item_discrimination,
        rater_severity = truth.rater_severity,
        rater_consistency = truth.rater_consistency,
        rater_steps = matrix_rows(truth.rater_steps),
    )
    return (;
        dataset_id = :uto_ueno_2020_scalar_recovery_smallest_cell_rep01,
        family = :gmfrm,
        reference = :uto_ueno_2020_gmfrm,
        seeds = (; truth = truth_seed, response = response_seed),
        rng = :Random_MersenneTwister,
        relationship_to_source = :paper_exact_design_cell_package_overlap_equation,
        materialization = :row_level_synthetic_pilot,
        contains_personal_data = false,
        design = (;
            n_persons,
            n_items,
            n_raters,
            n_dimensions = 1,
            category_levels,
            assignment = :fully_crossed,
            n_observations = length(scores),
        ),
        equation = (;
            source_equation = :uto_ueno_2020_equation_9,
            implementation = :standalone_adjacent_category_softmax,
            eta_baseline = 0.0,
            adjacent_increment =
                :item_discrimination_times_rater_consistency_times_ability_minus_item_difficulty_minus_rater_severity_minus_rater_step,
            package_generator_called = false,
        ),
        parameter_generation = [
            (block = :person_ability, draw = :normal_0_1,
                transform = :none, source_alignment = :paper_exact),
            (block = :item_difficulty, draw = :normal_0_1,
                transform = :arithmetic_center_sum_zero,
                source_alignment = :paper_anchored_package_identified),
            (block = :log_item_discrimination, draw = :normal_0_1,
                transform = :exponentiate_then_geometric_center_product_one,
                source_alignment = :paper_anchored_package_identified),
            (block = :rater_severity, draw = :normal_0_1,
                transform = :none, source_alignment = :paper_exact),
            (block = :log_rater_consistency, draw = :normal_0_1,
                transform = :exponentiate,
                source_alignment = :paper_exact_positive_scale),
            (block = :rater_steps_free, draw = :normal_0_1,
                transform = :first_zero_and_final_negative_free_sum,
                source_alignment = :paper_anchored_package_identified),
        ],
        truth = truth_record,
        observations,
        checksums = (;
            canonical_observation_format = :csv_header_then_integer_rows_lf,
            observations_sha256 = observation_sha256(observations),
            truth_canonical_format = :local_json_compact_named_record,
            truth_sha256 = canonical_json_sha256(truth_record),
        ),
        generator_checks = (;
            package_source_oracle = :gmfrm_source_fixture_values,
            tolerance = ORACLE_TOLERANCE,
            max_abs_probability_error = oracle_error,
            selected_rows = probability_check_rows(dummy, independent, oracle),
        ),
        summary = (;
            category_counts = counts,
            all_categories_observed = true,
            complete_person_coverage = length(unique(observations.person)) == n_persons,
            complete_rater_coverage = length(unique(observations.rater)) == n_raters,
            complete_item_coverage = length(unique(observations.item)) == n_items,
        ),
        claim_limits = [
            :one_replication_is_not_parameter_recovery_evidence,
            :range_restriction_and_behavior_modification_conditions_not_materialized,
            :no_external_software_comparison,
            :no_construct_validity_claim,
        ],
    )
end

function build_mgmfrm_dataset()
    truth_seed = BASE_SEED + 200000 + 200 + 1000 + 1
    response_seed = BASE_SEED + 200000 + 200 + 1000 + 3
    n_persons, n_items, n_raters, dimensions, categories = 50, 5, 5, 2, 4
    category_levels = collect(0:(categories - 1))
    q_matrix = fixed_q()
    truth_rng = MersenneTwister(truth_seed)
    response_rng = MersenneTwister(response_seed)
    truth = mgmfrm_truth(
        truth_rng,
        n_persons,
        n_raters,
        n_items,
        dimensions,
        categories,
        q_matrix,
    )
    dummy = full_cross_columns(n_persons, n_raters, n_items; categories)
    independent = zeros(Float64, length(dummy.person), categories)
    for row in eachindex(dummy.person)
        independent[row, :] = mgmfrm_probability(
            truth,
            dummy.person[row],
            dummy.rater[row],
            dummy.item[row],
            categories,
        )
    end
    data = facet_data(dummy)
    spec = BayesianMGMFRM.mfrm_spec(data;
        family = :mgmfrm,
        dimensions,
        q_matrix,
    )
    design = BayesianMGMFRM.getdesign(spec; preview = true)
    oracle = oracle_probability_matrix(
        design,
        mgmfrm_direct_params(design, truth),
        :mgmfrm,
    )
    oracle_error = maximum(abs.(independent .- oracle))
    oracle_error <= ORACLE_TOLERANCE ||
        error("standalone MGMFRM generator disagrees with source oracle: $oracle_error")
    scores = [sample_score(response_rng, @view(independent[row, :]), category_levels)
        for row in axes(independent, 1)]
    observations = full_cross_columns(n_persons, n_raters, n_items;
        scores,
        categories,
    )
    counts = category_count_rows(scores, category_levels)
    all(row -> row.count > 0, counts) ||
        error("MGMFRM pilot did not realize every category")
    truth_record = (;
        person_ability = matrix_rows(truth.person_ability),
        item_difficulty = truth.item_difficulty,
        item_dimension_discrimination =
            matrix_rows(truth.item_dimension_discrimination),
        rater_severity = truth.rater_severity,
        rater_consistency = truth.rater_consistency,
        item_steps = matrix_rows(truth.item_steps),
    )
    q_record = matrix_rows(q_matrix)
    return (;
        dataset_id = :uto_2021_fixed_q_recovery_smallest_cell_rep01,
        family = :mgmfrm,
        reference = :uto_2021_mgmfrm,
        seeds = (; truth = truth_seed, response = response_seed),
        rng = :Random_MersenneTwister,
        relationship_to_source = :paper_exact_sample_size_package_adapted_fixed_q,
        materialization = :row_level_synthetic_pilot,
        contains_personal_data = false,
        design = (;
            n_persons,
            n_items,
            n_raters,
            n_dimensions = dimensions,
            category_levels,
            assignment = :fully_crossed,
            n_observations = length(scores),
            q_matrix = q_record,
        ),
        equation = (;
            source_equation = :uto_2021_equation_6,
            implementation = :standalone_adjacent_category_softmax,
            eta_baseline = 0.0,
            source_scale = 1.7,
            ability_combination = :loading_weighted_sum,
            adjacent_increment =
                :source_scale_times_rater_consistency_times_loading_weighted_ability_minus_item_difficulty_minus_rater_severity_minus_item_step,
            package_generator_called = false,
        ),
        parameter_generation = [
            (block = :person_ability_by_dimension, draw = :normal_0_1,
                transform = :none, source_alignment = :paper_exact),
            (block = :item_difficulty, draw = :normal_0_1,
                transform = :none, source_alignment = :paper_exact),
            (block = :active_log_item_dimension_discrimination,
                draw = :normal_0_1,
                transform = :exponentiate_then_override_two_primary_anchors_at_1_5,
                source_alignment = :package_adapted_fixed_q),
            (block = :inactive_item_dimension_discrimination,
                draw = :none,
                transform = :fixed_zero_by_q_mask,
                source_alignment = :package_adaptation_of_paper_0_2_anchor_cross_loading),
            (block = :rater_severity, draw = :normal_0_1,
                transform = :arithmetic_center_sum_zero,
                source_alignment = :paper_anchored_package_identified),
            (block = :log_rater_consistency, draw = :normal_0_1,
                transform = :exponentiate_then_geometric_center_product_one,
                source_alignment = :paper_anchored_package_identified),
            (block = :item_steps_free, draw = :normal_0_1,
                transform = :first_zero_and_final_negative_free_sum,
                source_alignment = :paper_anchored_package_identified),
        ],
        adaptation = (;
            type = :confirmatory_fixed_q,
            anchor_items = [1, 2],
            anchor_primary_loading = 1.5,
            source_nonprimary_anchor_loading = 0.2,
            adapted_inactive_loading = 0.0,
            reason = :current_package_surface_requires_a_fixed_confirmatory_q_mask,
            ability_combination_scope =
                :record_generation_formula_not_compensatory_classification_claim,
            paper_exact_loading_recovery_claim = false,
        ),
        truth = truth_record,
        observations,
        checksums = (;
            canonical_observation_format = :csv_header_then_integer_rows_lf,
            observations_sha256 = observation_sha256(observations),
            truth_canonical_format = :local_json_compact_named_record,
            truth_sha256 = canonical_json_sha256(truth_record),
            q_matrix_canonical_format = :local_json_compact_row_major_boolean_rows,
            q_matrix_sha256 = canonical_json_sha256(q_record),
        ),
        generator_checks = (;
            package_source_oracle = :mgmfrm_source_fixture_values,
            tolerance = ORACLE_TOLERANCE,
            max_abs_probability_error = oracle_error,
            selected_rows = probability_check_rows(dummy, independent, oracle),
        ),
        summary = (;
            category_counts = counts,
            all_categories_observed = true,
            complete_person_coverage = length(unique(observations.person)) == n_persons,
            complete_rater_coverage = length(unique(observations.rater)) == n_raters,
            complete_item_coverage = length(unique(observations.item)) == n_items,
        ),
        claim_limits = [
            :one_replication_is_not_parameter_recovery_evidence,
            :fixed_q_adaptation_is_not_an_exact_reproduction_of_free_loading_recovery,
            :dimension_selection_grid_not_materialized,
            :systematic_link_sparse_condition_not_materialized,
            :no_external_software_comparison,
            :no_construct_validity_claim,
        ],
    )
end

function build_artifact()
    datasets = [build_gmfrm_dataset(), build_mgmfrm_dataset()]
    all_oracles_pass = all(
        dataset.generator_checks.max_abs_probability_error <=
            dataset.generator_checks.tolerance
        for dataset in datasets
    )
    all_coverage_pass = all(
        dataset.summary.all_categories_observed &&
        dataset.summary.complete_person_coverage &&
        dataset.summary.complete_rater_coverage &&
        dataset.summary.complete_item_coverage
        for dataset in datasets
    )
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_literature_anchored_synthetic_benchmark.v1",
        family = :gmfrm_mgmfrm,
        scope = :literature_anchored_synthetic_benchmark,
        status = :pilot_datasets_materialized,
        decision = :use_for_known_truth_and_external_software_bridge_preparation_only,
        public_fit = true,
        experimental_public = true,
        synthetic_data_only = true,
        construct_validity_evidence = false,
        external_software_validation_completed = false,
        independent_review_completed = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = (;
            protocol_id = :mgmfrm_literature_anchored_synthetic_benchmark_v1,
            source_discovery = :zotero_library_review,
            committed_reference_policy = :public_doi_and_url_only_no_reference_manager_item_keys,
            generator = :standalone_equation_implementation,
            generator_independence_scope =
                :response_sampling_does_not_call_package_probability_simulation_or_parameter_layout_helpers,
            package_simulate_responses_called = false,
            package_source_oracle_checked_before_write = true,
            row_data_policy = :synthetic_integer_facet_identifiers_only,
            replication_scope = :one_pilot_replication_per_materialized_source_condition,
            seed_policy = (;
                rng = :Random_MersenneTwister,
                base_seed = BASE_SEED,
                formula =
                    :base_seed_plus_source_offset_plus_scenario_offset_plus_1000_times_replication_plus_stream_offset,
                source_offsets = (; uto_2020 = 100000, uto_2021 = 200000),
                scenario_offsets = (; uto_2020_minimum = 100, uto_2021_fixed_q = 200),
                stream_offsets = (; truth = 1, response = 3),
            ),
            generator_source =
                "scripts/generate_mgmfrm_literature_anchored_synthetic_benchmark.jl",
            generator_source_sha256 = file_sha256(@__FILE__),
        ),
        reference_records = REFERENCE_RECORDS,
        benchmark_specifications = BENCHMARK_SPECIFICATIONS,
        datasets,
        external_validation_bridges = [
            (;
                software = :tam,
                status =
                    :direct_agreement_policy_frozen_and_multiaxially_refined_multirep_package_fits_pending,
                overlap_target = :many_facet_rasch_partial_credit_baseline,
                prepared_dataset =
                    "test/fixtures/mgmfrm_tam_overlap_baseline.json",
                prepared_csv =
                    "test/fixtures/mgmfrm_tam_overlap_baseline.csv",
                execution_review =
                    "test/fixtures/mgmfrm_tam_overlap_execution_review.json",
                comparison_policy_review =
                    "test/fixtures/mgmfrm_tam_comparison_policy_review.json",
                multireplication_comparison =
                    "test/fixtures/mgmfrm_tam_multireplication_comparison.json",
                direct_estimate_pilot =
                    "test/fixtures/mgmfrm_tam_direct_estimate_pilot.json",
                direct_agreement_policy =
                    "test/fixtures/mgmfrm_tam_direct_agreement_policy.json",
                direct_agreement_policy_refinement =
                    "test/fixtures/mgmfrm_tam_direct_agreement_policy_refinement.json",
                reason_current_pilots_are_not_direct_validation_targets =
                    :uto_style_generalized_discrimination_and_fixed_q_loading_terms_do_not_exactly_overlap_tam_mfr,
            ),
            (;
                software = :facets,
                status = :not_executed,
                overlap_target = :many_facet_rasch_baseline_with_unit_discriminations,
                required_new_dataset = :facets_overlap_baseline,
                reason_current_pilots_are_not_direct_validation_targets =
                    :generalized_item_and_rater_discrimination_parameters_do_not_exactly_overlap_facets_mfrm,
            ),
            (;
                software = :conquest,
                status = :not_executed,
                overlap_target = :mrcml_or_multidimensional_rasch_baseline,
                required_new_dataset = :conquest_mrcml_overlap_baseline,
                reason_current_pilots_are_not_direct_validation_targets =
                    :uto_style_rater_consistency_and_fixed_q_loading_parameterization_require_an_explicit_alignment_adapter,
            ),
        ],
        independent_review = (;
            status = :packet_frozen_review_not_started,
            separate_from_external_software_comparison = true,
            review_packet_artifact =
                "test/fixtures/mgmfrm_literature_anchored_independent_review_packet.json",
            review_packet_schema =
                "bayesianmgmfrm.mgmfrm_literature_anchored_independent_review_packet.v1",
            required_inputs = [
                :frozen_protocol,
                :generator_source,
                :dataset_checksums,
                :parameter_truth,
                :paper_exact_vs_package_adapted_labels,
                :claim_limit_ledger,
            ],
            remaining_requirements = [
                :assign_independent_reviewer,
                :attach_signed_independent_review_manifest,
                :record_per_claim_review_decisions,
            ],
        ),
        claim_ledger = [
            (;
                claim = :standalone_generator_matches_in_repository_source_equation_oracle,
                supported = all_oracles_pass,
            ),
            (;
                claim = :selected_literature_scale_conditions_are_materialized,
                supported = length(datasets) == 2 && all_coverage_pass,
            ),
            (;
                claim = :parameter_recovery,
                supported = false,
                blocker = :paper_replication_grids_and_refits_not_run,
            ),
            (;
                claim = :external_software_agreement,
                supported = false,
                blocker =
                    :tam_direct_policy_refined_multirep_package_fits_and_facets_conquest_pending,
            ),
            (;
                claim = :external_construct_validity,
                supported = false,
                blocker = :synthetic_known_truth_data_cannot_supply_construct_evidence,
            ),
            (;
                claim = :independent_review,
                supported = false,
                blocker = :signed_independent_review_not_attached,
            ),
        ],
        summary = (;
            passed = all_oracles_pass && all_coverage_pass && length(datasets) == 2,
            n_reference_records = length(REFERENCE_RECORDS),
            n_benchmark_specifications = length(BENCHMARK_SPECIFICATIONS),
            n_materialized_datasets = length(datasets),
            n_materialized_observations =
                sum(dataset.design.n_observations for dataset in datasets),
            standalone_generator_oracle_agreement = all_oracles_pass,
            row_and_category_coverage_passed = all_coverage_pass,
            parameter_recovery_completed = false,
            external_software_validation_completed = false,
            external_construct_validation_completed = false,
            independent_review_completed = false,
            public_claim_release_allowed = false,
            next_gates = [
                :run_predeclared_recovery_refits_across_paper_grid_cells,
                :run_predeclared_multireplication_package_vs_tam_direct_agreement_under_refined_adjudication,
                :add_facets_unit_discrimination_overlap_dataset_and_adapter,
                :add_conquest_mrcml_overlap_dataset_and_adapter,
                :assign_independent_reviewer_and_attach_signed_review,
                :attach_real_external_construct_dataset_separately,
            ],
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println(
        "passed=", artifact.summary.passed,
        " datasets=", artifact.summary.n_materialized_datasets,
        " observations=", artifact.summary.n_materialized_observations,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
