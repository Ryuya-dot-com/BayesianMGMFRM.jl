# local_dependence_known_truth_dgp.jl -- standalone LD1 ordinal-score generator

using Random

const _LD1_COMPONENT_NAMESPACES = (
    :design,
    :person_ability,
    :secondary_person_ability,
    :rater_severity,
    :item_difficulty,
    :person_testlet,
    :response_occasion,
    :rater_response_halo,
    :rater_task,
    :temporal,
    :missingness,
    :response_uniforms,
)

const _LD1_FNV_OFFSET_BASIS = UInt64(0xcbf29ce484222325)
const _LD1_FNV_PRIME = UInt64(0x00000100000001b3)
const _LD1_MIX_GAMMA = UInt64(0x9e3779b97f4a7c15)
const _LD1_MIX_MULTIPLIER_1 = UInt64(0xbf58476d1ce4e5b9)
const _LD1_MIX_MULTIPLIER_2 = UInt64(0x94d049bb133111eb)

"""
    _ld1_mix64(value)

Return a stable UInt64 avalanche mix. This deliberately avoids `hash`, whose
seed and implementation are not a persistence contract.
"""
function _ld1_mix64(value::UInt64)
    mixed = value + _LD1_MIX_GAMMA
    mixed = xor(mixed, mixed >> 30) * _LD1_MIX_MULTIPLIER_1
    mixed = xor(mixed, mixed >> 27) * _LD1_MIX_MULTIPLIER_2
    return xor(mixed, mixed >> 31)
end

function _ld1_namespace_key(namespace::Symbol)
    state = _LD1_FNV_OFFSET_BASIS
    for byte in codeunits(String(namespace))
        state = xor(state, UInt64(byte)) * _LD1_FNV_PRIME
    end
    return _ld1_mix64(state)
end

function _ld1_component_seed(seed::Int, namespace::Symbol)
    mixed = _ld1_mix64(xor(UInt64(seed), _ld1_namespace_key(namespace)))
    return Int(mixed & UInt64(typemax(Int)))
end

function _ld1_semantic_seed(component_seed::Int, keys::Int...)
    state = _ld1_mix64(UInt64(component_seed))
    for key in keys
        key >= 0 || throw(ArgumentError(
            "semantic random-number keys must be nonnegative"))
        state = _ld1_mix64(xor(state, _ld1_mix64(UInt64(key))))
    end
    return state
end

_ld1_keyed_uniform(component_seed::Int, keys::Int...) =
    rand(MersenneTwister(_ld1_semantic_seed(component_seed, keys...)))

_ld1_keyed_standard_normal(component_seed::Int, keys::Int...) =
    randn(MersenneTwister(_ld1_semantic_seed(component_seed, keys...)))

function _ld1_checked_positive_integer(value, name::Symbol; minimum::Int = 1)
    value isa Integer && !(value isa Bool) ||
        throw(ArgumentError("$name must be an integer"))
    converted = Int(value)
    converted >= minimum ||
        throw(ArgumentError("$name must be at least $minimum"))
    return converted
end

function _ld1_checked_seed(value)
    value isa Integer && !(value isa Bool) ||
        throw(ArgumentError("seed must be an integer"))
    converted = Int(value)
    converted >= 0 || throw(ArgumentError("seed must be nonnegative"))
    return converted
end

function _ld1_checked_product(limit::Int, name::AbstractString, values::Int...)
    total = 1
    for value in values
        total <= limit ÷ value ||
            throw(ArgumentError(
                "$name exceeds its configured limit $limit"))
        total *= value
    end
    return total
end

function _ld1_checked_sum(limit::Int, name::AbstractString, values::Int...)
    total = 0
    for value in values
        value >= 0 || throw(ArgumentError(
            "$name received a negative component count"))
        total <= limit - value || throw(ArgumentError(
            "$name exceeds its configured limit $limit"))
        total += value
    end
    return total
end

function _ld1_component_seeds(seed::Int)
    return NamedTuple{_LD1_COMPONENT_NAMESPACES}(
        Tuple(_ld1_component_seed(seed, namespace)
            for namespace in _LD1_COMPONENT_NAMESPACES),
    )
end

function _ld1_mean(values)
    isempty(values) && throw(ArgumentError("mean requires at least one value"))
    total = 0.0
    for value in values
        total += Float64(value)
    end
    return total / length(values)
end

function _ld1_sample_sd(values)
    length(values) >= 2 || return 0.0
    center = _ld1_mean(values)
    total = 0.0
    for value in values
        total += abs2(Float64(value) - center)
    end
    return sqrt(total / (length(values) - 1))
end

function _ld1_reference_constrain(values)
    output = Float64.(collect(values))
    reference = first(output)
    output .-= reference
    return output
end

function _ld1_double_center(matrix::AbstractMatrix)
    output = Matrix{Float64}(matrix)
    grand = _ld1_mean(output)
    row_means = [_ld1_mean(@view output[row, :]) for row in axes(output, 1)]
    column_means = [_ld1_mean(@view output[:, column])
        for column in axes(output, 2)]
    for row in axes(output, 1), column in axes(output, 2)
        output[row, column] = output[row, column] - row_means[row] -
            column_means[column] + grand
    end
    return output
end

function _ld1_label(prefix::AbstractString, index::Int, maximum_index::Int)
    width = max(2, ndigits(maximum_index))
    return prefix * lpad(string(index), width, '0')
end

function _ld1_item_index(testlet::Int, within_testlet::Int,
        items_per_testlet::Int)
    return (testlet - 1) * items_per_testlet + within_testlet
end

function _ld1_preflight_rating_count(design::Symbol, n_persons::Int,
        n_testlets::Int, items_per_testlet::Int, n_raters::Int,
        max_ratings::Int)
    if design === :fully_crossed_raters
        return _ld1_checked_product(max_ratings,
            "known-truth rating count", n_persons, n_testlets,
            n_raters, items_per_testlet)
    elseif design in (
            :same_rater,
            :mixed_testlet_applicability,
        )
        return _ld1_checked_product(max_ratings,
            "known-truth rating count", n_persons, n_testlets,
            items_per_testlet)
    elseif design in (:connected_sparse, :disconnected_blocks)
        return _ld1_checked_product(max_ratings,
            "known-truth rating count", n_persons, 2,
            items_per_testlet)
    elseif design === :one_testlet_per_person
        return _ld1_checked_product(max_ratings,
            "known-truth rating count", n_persons, items_per_testlet)
    end
    throw(ArgumentError("unsupported local-dependence design :$design"))
end

function _ld1_preflight_truth_counts(n_persons::Int, n_testlets::Int,
        n_items::Int, n_raters::Int, n_categories::Int, n_ratings::Int,
        n_probability_cells::Int, max_truth_cells::Int)
    person_ability = n_persons
    secondary_person_ability = n_persons
    rater_severity = n_raters
    item_difficulty = n_items
    item_steps = _ld1_checked_product(max_truth_cells,
        "known-truth scalar count", n_items, n_categories - 1)
    q_matrix = _ld1_checked_product(max_truth_cells,
        "known-truth scalar count", n_items, 2)
    person_testlet = _ld1_checked_product(max_truth_cells,
        "known-truth scalar count", n_persons, n_testlets)
    response_occasion = person_testlet
    rater_response_halo = _ld1_checked_product(max_truth_cells,
        "known-truth scalar count", n_raters, n_persons, n_testlets)
    rater_task = _ld1_checked_product(max_truth_cells,
        "known-truth scalar count", n_raters, n_testlets)
    temporal = n_raters
    facet_truth = _ld1_checked_sum(max_truth_cells,
        "known-truth scalar count",
        person_ability,
        secondary_person_ability,
        rater_severity,
        item_difficulty,
        item_steps,
        q_matrix,
        person_testlet,
        response_occasion,
        rater_response_halo,
        rater_task,
        temporal,
    )

    # `row_truth` stores 20 length-n_ratings vectors plus its pointwise
    # n_ratings-by-n_categories probability matrix. Keep this count beside the
    # schema so a new row-truth vector must update the preflight contract.
    row_truth_vectors = _ld1_checked_product(max_truth_cells,
        "known-truth scalar count", n_ratings, 20)
    n_probability_cells <= max_truth_cells || throw(ArgumentError(
        "known-truth scalar count exceeds its configured limit $max_truth_cells"))
    row_truth = _ld1_checked_sum(max_truth_cells,
        "known-truth scalar count", row_truth_vectors, n_probability_cells)
    n_truth_cells = _ld1_checked_sum(max_truth_cells,
        "known-truth scalar count", facet_truth, row_truth)
    return (;
        n_truth_cells,
        breakdown = (;
            facet_truth,
            row_truth,
            row_truth_vectors,
            pointwise_probabilities = n_probability_cells,
            person_ability,
            secondary_person_ability,
            rater_severity,
            item_difficulty,
            item_steps,
            q_matrix,
            person_testlet,
            response_occasion,
            rater_response_halo,
            rater_task,
            temporal,
        ),
    )
end

function _ld1_person_testlets(design::Symbol, person::Int, n_testlets::Int)
    if design === :connected_sparse
        first_testlet = mod(person - 1, n_testlets) + 1
        second_testlet = mod(person, n_testlets) + 1
        return (first_testlet, second_testlet)
    elseif design === :one_testlet_per_person
        return (mod(person - 1, n_testlets) + 1,)
    elseif design === :disconnected_blocks
        n_testlets >= 4 || throw(ArgumentError(
            "design = :disconnected_blocks requires at least four testlets"))
        split = fld(n_testlets, 2)
        block = isodd(person) ? collect(1:split) : collect((split + 1):n_testlets)
        length(block) >= 2 || throw(ArgumentError(
            "each disconnected block must contain at least two testlets"))
        offset = fld(person - 1, 2)
        first_testlet = block[mod(offset, length(block)) + 1]
        second_testlet = block[mod(offset + 1, length(block)) + 1]
        return (first_testlet, second_testlet)
    end
    return Tuple(1:n_testlets)
end

function _ld1_person_ability_ranks(abilities)
    order = sortperm(collect(eachindex(abilities)); by = index ->
        (abilities[index], index))
    ranks = zeros(Int, length(abilities))
    for (rank, person) in pairs(order)
        ranks[person] = rank
    end
    return ranks
end

function _ld1_primary_rater(person::Int, testlet::Int, n_persons::Int,
        n_raters::Int, assignment::Symbol, ability_ranks,
        rater_permutation)
    unpermuted = if assignment === :balanced
        mod(person + testlet - 2, n_raters) + 1
    elseif assignment === :ability_informed
        min(fld((ability_ranks[person] - 1) * n_raters, n_persons) + 1,
            n_raters)
    elseif assignment === :task_nested
        mod(testlet - 1, n_raters) + 1
    else
        throw(ArgumentError(
            "assignment must be :balanced, :ability_informed, or :task_nested"))
    end
    return rater_permutation[unpermuted]
end

function _ld1_rating_cells(config, abilities, rater_permutation)
    n_persons = config.n_persons
    n_testlets = config.n_testlets
    items_per_testlet = config.items_per_testlet
    n_raters = config.n_raters
    ability_ranks = _ld1_person_ability_ranks(abilities)
    cells = NamedTuple[]
    canonical_row = 0
    for person in 1:n_persons
        for testlet in _ld1_person_testlets(config.design, person, n_testlets)
            response_index = (person - 1) * n_testlets + testlet
            primary = _ld1_primary_rater(
                person,
                testlet,
                n_persons,
                n_raters,
                config.assignment,
                ability_ranks,
                rater_permutation,
            )
            if config.design === :fully_crossed_raters
                for rater in rater_permutation, within in 1:items_per_testlet
                    canonical_row += 1
                    push!(cells, (;
                        canonical_row,
                        person,
                        testlet,
                        response_index,
                        rater,
                        within_testlet_item = within,
                        item = _ld1_item_index(
                            testlet, within, items_per_testlet),
                    ))
                end
            elseif config.design === :mixed_testlet_applicability && iseven(testlet)
                for within in 1:items_per_testlet
                    rater_position = mod(within - 1, n_raters) + 1
                    rater = rater_permutation[rater_position]
                    canonical_row += 1
                    push!(cells, (;
                        canonical_row,
                        person,
                        testlet,
                        response_index,
                        rater,
                        within_testlet_item = within,
                        item = _ld1_item_index(
                            testlet, within, items_per_testlet),
                    ))
                end
            else
                for within in 1:items_per_testlet
                    canonical_row += 1
                    push!(cells, (;
                        canonical_row,
                        person,
                        testlet,
                        response_index,
                        rater = primary,
                        within_testlet_item = within,
                        item = _ld1_item_index(
                            testlet, within, items_per_testlet),
                    ))
                end
            end
        end
    end
    return cells
end

function _ld1_ordered_events(cells, config, abilities, design_seed::Int)
    event_map = Dict{Tuple{Int,Int},NamedTuple}()
    for cell in cells
        key = (cell.rater, cell.response_index)
        event_map[key] = (;
            rater = cell.rater,
            response_index = cell.response_index,
            person = cell.person,
            testlet = cell.testlet,
        )
    end
    sequence = Dict{Tuple{Int,Int},NamedTuple}()
    for rater in 1:config.n_raters
        events = [event for event in values(event_map) if event.rater == rater]
        sort!(events; by = event -> event.response_index)
        if config.order === :randomized
            sort!(events; by = event -> (
                _ld1_keyed_uniform(
                    design_seed,
                    event.rater,
                    event.person,
                    event.testlet,
                ),
                event.person,
                event.testlet,
            ))
        elseif config.order === :low_to_high
            sort!(events; by = event ->
                (abilities[event.person], event.response_index))
        elseif config.order === :high_to_low
            sort!(events; by = event ->
                (-abilities[event.person], event.response_index))
        elseif config.order === :testlet_blocked
            sort!(events; by = event ->
                (event.testlet, abilities[event.person], event.response_index))
        else
            throw(ArgumentError(
                "order must be :randomized, :low_to_high, :high_to_low, or :testlet_blocked"))
        end
        n_events = length(events)
        for (position, event) in pairs(events)
            centered_fraction = n_events <= 1 ? 0.0 :
                (position - 1) / (n_events - 1) - 0.5
            sequence_phase = centered_fraction < -1 / 6 ? :early :
                (centered_fraction < 1 / 6 ? :middle : :late)
            sequence[(rater, event.response_index)] = (;
                sequence_index = position,
                sequence_fraction = centered_fraction,
                sequence_phase,
            )
        end
    end
    return sequence
end

function _ld1_pcm_probabilities(location::Real, steps::AbstractVector)
    categories = length(steps) + 1
    logweights = Vector{Float64}(undef, categories)
    logweights[1] = 0.0
    for step in 1:length(steps)
        logweights[step + 1] = logweights[step] +
            Float64(location) - Float64(steps[step])
    end
    maximum_logweight = maximum(logweights)
    weights = exp.(logweights .- maximum_logweight)
    total = sum(weights)
    isfinite(total) && total > 0 ||
        throw(ArgumentError("standalone category weights are not finite"))
    return weights ./ total
end

function _ld1_inverse_cdf(uniform::Real, probabilities,
        category_levels)
    0 <= uniform < 1 ||
        throw(ArgumentError("response uniforms must be in [0, 1)"))
    cumulative = 0.0
    for category in eachindex(probabilities)
        cumulative += probabilities[category]
        uniform < cumulative && return category_levels[category]
    end
    return last(category_levels)
end

function _ld1_item_steps(n_items::Int, n_categories::Int)
    n_steps = n_categories - 1
    base = n_steps == 1 ? [0.0] :
        collect(range(-0.6, 0.6; length = n_steps))
    base .-= _ld1_mean(base)
    steps = Matrix{Float64}(undef, n_items, n_steps)
    for item in 1:n_items
        steps[item, :] .= base
    end
    return steps
end

function _ld1_component_scales(mechanism::Symbol, effect_scale::Float64)
    isfinite(effect_scale) && effect_scale >= 0 || throw(ArgumentError(
        "effect_scale must be finite and nonnegative"))
    testlet = 0.0
    halo = 0.0
    rater_task = 0.0
    multidimensional = 0.0
    temporal = 0.0
    if mechanism === :null
    elseif mechanism === :person_testlet
        testlet = effect_scale
    elseif mechanism === :rater_response_halo
        halo = effect_scale
    elseif mechanism === :rater_task_severity
        rater_task = effect_scale
    elseif mechanism === :omitted_multidimensionality
        multidimensional = effect_scale
    elseif mechanism === :severity_drift
        temporal = effect_scale
    elseif mechanism === :person_testlet_plus_drift
        testlet = effect_scale / sqrt(2)
        temporal = effect_scale / sqrt(2)
    else
        throw(ArgumentError("unsupported local-dependence mechanism :$mechanism"))
    end
    return (; testlet, halo, rater_task, multidimensional, temporal)
end

function _ld1_active_mechanisms(scales)
    active = Symbol[]
    scales.testlet > 0 && push!(active, :person_testlet)
    scales.halo > 0 && push!(active, :rater_response_halo)
    scales.rater_task > 0 && push!(active, :rater_task_severity)
    scales.multidimensional > 0 && push!(active, :omitted_multidimensionality)
    scales.temporal > 0 && push!(active, :severity_drift)
    return Tuple(active)
end

function _ld1_baseline_mfrm_assumption_status(active_mechanisms)
    shared_latent = any(mechanism -> mechanism in (
            :person_testlet,
            :rater_response_halo,
            :omitted_multidimensionality,
        ), active_mechanisms)
    mean_misspecified = any(mechanism -> mechanism in (
            :rater_task_severity,
            :severity_drift,
        ), active_mechanisms)
    if shared_latent && mean_misspecified
        return :shared_latent_component_and_mean_structure_misspecified
    elseif shared_latent
        return :shared_latent_component_omitted
    elseif mean_misspecified
        return :mean_structure_misspecified
    end
    return :holds_by_construction
end

function _ld1_generate_raw(config)
    seed = _ld1_checked_seed(config.seed)
    n_persons = _ld1_checked_positive_integer(
        config.n_persons, :n_persons; minimum = 4)
    n_testlets = _ld1_checked_positive_integer(
        config.n_testlets, :n_testlets; minimum = 2)
    items_per_testlet = _ld1_checked_positive_integer(
        config.items_per_testlet, :items_per_testlet)
    n_raters = _ld1_checked_positive_integer(
        config.n_raters, :n_raters; minimum = 2)
    n_categories = _ld1_checked_positive_integer(
        config.n_categories, :n_categories; minimum = 2)
    config.design in (
        :same_rater,
        :fully_crossed_raters,
        :mixed_testlet_applicability,
        :connected_sparse,
        :one_testlet_per_person,
        :disconnected_blocks,
    ) || throw(ArgumentError("unsupported local-dependence design :$(config.design)"))
    max_ratings = _ld1_checked_positive_integer(
        config.max_ratings, :max_ratings)
    max_probability_cells = _ld1_checked_positive_integer(
        config.max_probability_cells, :max_probability_cells)
    max_truth_cells = _ld1_checked_positive_integer(
        config.max_truth_cells, :max_truth_cells)
    config.design === :disconnected_blocks && n_testlets < 4 &&
        throw(ArgumentError(
            "design = :disconnected_blocks requires at least four testlets"))
    n_items = _ld1_checked_product(
        typemax(Int), "item count", n_testlets, items_per_testlet)
    n_ratings = _ld1_preflight_rating_count(
        config.design,
        n_persons,
        n_testlets,
        items_per_testlet,
        n_raters,
        max_ratings,
    )
    n_probability_cells = _ld1_checked_product(
        max_probability_cells,
        "known-truth probability workload",
        n_ratings,
        n_categories,
    )
    truth_counts = _ld1_preflight_truth_counts(
        n_persons,
        n_testlets,
        n_items,
        n_raters,
        n_categories,
        n_ratings,
        n_probability_cells,
        max_truth_cells,
    )
    scales = _ld1_component_scales(config.mechanism, config.effect_scale)
    scales.multidimensional <= 1 || throw(ArgumentError(
        "omitted-multidimensionality effect_scale must not exceed one"))
    active_mechanisms = _ld1_active_mechanisms(scales)

    seeds = _ld1_component_seeds(seed)
    abilities = [_ld1_keyed_standard_normal(
        seeds.person_ability, person) for person in 1:n_persons]
    secondary_abilities = [_ld1_keyed_standard_normal(
        seeds.secondary_person_ability, person) for person in 1:n_persons]
    rater_severity = 0.50 .* _ld1_reference_constrain(
        [_ld1_keyed_standard_normal(seeds.rater_severity, rater)
            for rater in 1:n_raters])
    item_difficulty = 0.35 .* _ld1_reference_constrain(
        [_ld1_keyed_standard_normal(
            seeds.item_difficulty, testlet, within)
            for testlet in 1:n_testlets
            for within in 1:items_per_testlet])
    item_steps = _ld1_item_steps(n_items, n_categories)

    rater_permutation = collect(1:n_raters)
    sort!(rater_permutation; by = rater -> (
        _ld1_keyed_uniform(seeds.design, rater), rater))
    cells = _ld1_rating_cells(config, abilities, rater_permutation)
    length(cells) == n_ratings || error(
        "internal LD1 rating-count mismatch: preflight=$n_ratings, generated=$(length(cells))")

    sequence = _ld1_ordered_events(cells, config, abilities, seeds.design)
    person_testlet_z = Matrix{Float64}(undef, n_persons, n_testlets)
    response_occasion_z = Matrix{Float64}(undef, n_persons, n_testlets)
    for person in 1:n_persons, testlet in 1:n_testlets
        person_testlet_z[person, testlet] = _ld1_keyed_standard_normal(
            seeds.person_testlet, person, testlet)
        response_occasion_z[person, testlet] = _ld1_keyed_standard_normal(
            seeds.response_occasion, person, testlet)
    end
    halo_z = Matrix{Float64}(
        undef, n_raters, n_persons * n_testlets)
    for rater in 1:n_raters, person in 1:n_persons,
            testlet in 1:n_testlets
        response_index = (person - 1) * n_testlets + testlet
        halo_z[rater, response_index] = _ld1_keyed_standard_normal(
            seeds.rater_response_halo, rater, person, testlet)
    end
    rater_task_raw = Matrix{Float64}(undef, n_raters, n_testlets)
    for rater in 1:n_raters, testlet in 1:n_testlets
        rater_task_raw[rater, testlet] = _ld1_keyed_standard_normal(
            seeds.rater_task, rater, testlet)
    end
    rater_task_z = _ld1_double_center(rater_task_raw)
    temporal_raw = [0.8 + 0.4 * _ld1_keyed_uniform(
        seeds.temporal, rater) for rater in 1:n_raters]
    temporal_multipliers = temporal_raw ./ _ld1_mean(temporal_raw)

    q_matrix = falses(n_items, 2)
    q_matrix[:, 1] .= true
    if items_per_testlet >= 2
        for testlet in 1:n_testlets, within in 1:items_per_testlet
            item = _ld1_item_index(testlet, within, items_per_testlet)
            q_matrix[item, 2] = isodd(testlet + within)
        end
    end

    ordered_cells = NamedTuple[]
    for cell in cells
        order_record = sequence[(cell.rater, cell.response_index)]
        push!(ordered_cells, merge(cell, order_record, (;
            response_uniform = _ld1_keyed_uniform(
                seeds.response_uniforms,
                cell.person,
                cell.testlet,
                cell.rater,
                cell.within_testlet_item,
            ),
            missingness_uniform = _ld1_keyed_uniform(
                seeds.missingness,
                cell.person,
                cell.testlet,
                cell.rater,
                cell.within_testlet_item,
            ),
        )))
    end
    sort!(ordered_cells; by = cell -> (
        cell.rater,
        cell.sequence_index,
        cell.response_index,
        cell.item,
        cell.canonical_row,
    ))

    category_levels = collect(0:(n_categories - 1))
    probabilities = Matrix{Float64}(
        undef, length(ordered_cells), n_categories)
    scores = Vector{Int}(undef, length(ordered_cells))
    baseline_location = Vector{Float64}(undef, length(ordered_cells))
    person_testlet_shift = similar(baseline_location)
    response_occasion_shift = zeros(Float64, length(ordered_cells))
    halo_shift = similar(baseline_location)
    rater_task_severity_shift = similar(baseline_location)
    multidimensional_shift = similar(baseline_location)
    temporal_severity_shift = similar(baseline_location)
    total_location = similar(baseline_location)

    for (row, cell) in pairs(ordered_cells)
        baseline = abilities[cell.person] - rater_severity[cell.rater] -
            item_difficulty[cell.item]
        testlet_effect = scales.testlet *
            person_testlet_z[cell.person, cell.testlet]
        halo_effect = scales.halo *
            halo_z[cell.rater, cell.response_index]
        task_effect = scales.rater_task *
            rater_task_z[cell.rater, cell.testlet]
        multidimensional_effect = if q_matrix[cell.item, 2]
            loading = scales.multidimensional
            (sqrt(1 - loading^2) - 1) * abilities[cell.person] +
                loading * secondary_abilities[cell.person]
        else
            0.0
        end
        temporal_effect = scales.temporal *
            temporal_multipliers[cell.rater] * cell.sequence_fraction
        location = baseline + testlet_effect + halo_effect - task_effect +
            multidimensional_effect - temporal_effect
        row_probabilities = _ld1_pcm_probabilities(
            location, @view item_steps[cell.item, :])
        probabilities[row, :] .= row_probabilities
        scores[row] = _ld1_inverse_cdf(
            cell.response_uniform,
            row_probabilities,
            category_levels,
        )
        baseline_location[row] = baseline
        person_testlet_shift[row] = testlet_effect
        halo_shift[row] = halo_effect
        rater_task_severity_shift[row] = task_effect
        multidimensional_shift[row] = multidimensional_effect
        temporal_severity_shift[row] = temporal_effect
        total_location[row] = location
    end

    person_labels = [_ld1_label("E", person, n_persons)
        for person in 1:n_persons]
    rater_labels = [_ld1_label("R", rater, n_raters)
        for rater in 1:n_raters]
    testlet_labels = [_ld1_label("T", testlet, n_testlets)
        for testlet in 1:n_testlets]
    item_labels = [
        string(_ld1_label("T", testlet, n_testlets), "-",
            _ld1_label("I", within, items_per_testlet))
        for testlet in 1:n_testlets for within in 1:items_per_testlet
    ]
    response_labels = [
        string(_ld1_label("S", cell.person, n_persons), "-",
            _ld1_label("T", cell.testlet, n_testlets))
        for cell in ordered_cells
    ]
    event_ids = [string(
        response_labels[row], "|",
        rater_labels[cell.rater], "|",
        item_labels[cell.item],
    ) for (row, cell) in pairs(ordered_cells)]
    table = (;
        person = [person_labels[cell.person] for cell in ordered_cells],
        rater = [rater_labels[cell.rater] for cell in ordered_cells],
        item = [item_labels[cell.item] for cell in ordered_cells],
        score = scores,
        task = [string("Task-", testlet_labels[cell.testlet])
            for cell in ordered_cells],
        occasion = fill("wave1", length(ordered_cells)),
        response_id = response_labels,
        testlet_id = [testlet_labels[cell.testlet] for cell in ordered_cells],
        sequence_index = [cell.sequence_index for cell in ordered_cells],
        sequence_fraction = [cell.sequence_fraction for cell in ordered_cells],
        sequence_phase = [String(cell.sequence_phase) for cell in ordered_cells],
        event_id = event_ids,
        assignment_reason = fill(String(config.assignment), length(ordered_cells)),
    )
    row_truth = (;
        event_id = event_ids,
        canonical_row = [cell.canonical_row for cell in ordered_cells],
        person_index = [cell.person for cell in ordered_cells],
        rater_index = [cell.rater for cell in ordered_cells],
        item_index = [cell.item for cell in ordered_cells],
        testlet_index = [cell.testlet for cell in ordered_cells],
        response_index = [cell.response_index for cell in ordered_cells],
        sequence_index = table.sequence_index,
        sequence_fraction = table.sequence_fraction,
        response_uniform = [cell.response_uniform for cell in ordered_cells],
        missingness_uniform = [cell.missingness_uniform for cell in ordered_cells],
        observed_mask = trues(length(ordered_cells)),
        baseline_location,
        person_testlet_shift,
        response_occasion_shift,
        rater_response_halo_shift = halo_shift,
        rater_task_severity_shift,
        multidimensional_shift,
        temporal_severity_shift,
        total_location,
        probabilities,
    )
    realized_categories = sort!(unique(scores))
    return (;
        table,
        row_truth,
        truth = (;
            schema = "bayesianmgmfrm.local_dependence_known_truth.v1",
            equation = :standalone_adjacent_category_partial_credit,
            generating_mechanism = config.mechanism,
            active_mechanisms,
            sampling_independence_given_complete_truth = true,
            baseline_mfrm_conditioning_set = (
                :person_ability,
                :rater_severity,
                :item_difficulty,
                :item_steps,
            ),
            baseline_mfrm_assumption_status =
                _ld1_baseline_mfrm_assumption_status(active_mechanisms),
            baseline_mfrm_omitted_active_truth_components =
                active_mechanisms,
            person_testlet_target_truth = scales.testlet > 0 ?
                :positive : :null,
            component_sign_convention = (;
                person_ability = :positive_location,
                item_difficulty = :negative_location,
                rater_severity = :negative_location,
                person_testlet = :positive_location,
                response_occasion = :reserved_zero,
                rater_response_halo = :positive_location,
                rater_task_severity = :negative_location,
                omitted_multidimensionality = :positive_location,
                temporal_severity = :negative_location,
            ),
            intended_category_levels = Tuple(category_levels),
            realized_category_levels = Tuple(realized_categories),
            category_support_complete = realized_categories == category_levels,
            person_labels = Tuple(person_labels),
            rater_labels = Tuple(rater_labels),
            item_labels = Tuple(item_labels),
            testlet_labels = Tuple(testlet_labels),
            person_ability = abilities,
            secondary_person_ability = secondary_abilities,
            rater_severity,
            item_difficulty,
            item_steps,
            q_matrix,
            person_testlet_standard_normal = person_testlet_z,
            response_occasion_standard_normal = response_occasion_z,
            rater_response_halo_standard_normal = halo_z,
            rater_task_double_centered_standard_normal = rater_task_z,
            temporal_rater_multipliers = temporal_multipliers,
            component_scales = scales,
            component_realized_row_sd = (;
                person_testlet = _ld1_sample_sd(person_testlet_shift),
                response_occasion = _ld1_sample_sd(response_occasion_shift),
                rater_response_halo = _ld1_sample_sd(halo_shift),
                rater_task_severity =
                    _ld1_sample_sd(rater_task_severity_shift),
                omitted_multidimensionality =
                    _ld1_sample_sd(multidimensional_shift),
                temporal_severity = _ld1_sample_sd(temporal_severity_shift),
            ),
            requested_effect_scale = config.effect_scale,
            requested_effect_scale_semantics =
                config.mechanism === :omitted_multidimensionality ?
                :standardized_secondary_ability_loading :
                :logit_location_scale,
            multidimensional_scale_semantics =
                :loading_with_variance_preserving_primary_weight,
            person_testlet_scale_is_standard_deviation = true,
            baseline_scale_inputs = (;
                rater_severity_standard_normal_multiplier = 0.50,
                item_difficulty_standard_normal_multiplier = 0.35,
            ),
            identification_constraints = (;
                first_rater_severity = 0.0,
                first_item_difficulty = 0.0,
                item_step_sum = 0.0,
                rater_task_rows_and_columns_double_centered = true,
                person_testlet_effect_population_mean = 0.0,
                realized_person_testlet_effects_not_forced_to_center = true,
            ),
            category_coverage_conditioning_applied = false,
            category_coverage_resampling_applied = false,
            response_occasion_stream_status = :reserved_not_applied,
            missingness_stream_status = :reserved_all_rows_observed,
            rng_contract = (;
                version = :stable_namespace_semantic_key_v1,
                root_seed = seed,
                component_namespaces = _LD1_COMPONENT_NAMESPACES,
                component_seed_derivation =
                    :fnv1a64_namespace_then_splitmix64,
                semantic_key_derivation =
                    :ordered_splitmix64_integer_key_fold,
                engine = :Random_MersenneTwister,
                normal_draw = :randn,
                uniform_draw = :rand,
                one_mersenne_twister_stream_per_semantic_key = true,
                component_semantic_keys = (;
                    design_rater = (:rater_index,),
                    design_response_order = (
                        :rater_index,
                        :person_index,
                        :testlet_index,
                    ),
                    person_ability = (:person_index,),
                    secondary_person_ability = (:person_index,),
                    rater_severity = (:rater_index,),
                    item_difficulty = (
                        :testlet_index,
                        :within_testlet_item,
                    ),
                    person_testlet = (:person_index, :testlet_index),
                    response_occasion = (:person_index, :testlet_index),
                    rater_response_halo = (
                        :rater_index,
                        :person_index,
                        :testlet_index,
                    ),
                    rater_task = (:rater_index, :testlet_index),
                    temporal = (:rater_index,),
                ),
                response_uniform_key = (
                    :seed,
                    :person_index,
                    :testlet_index,
                    :rater_index,
                    :within_testlet_item,
                ),
                missingness_uniform_key = (
                    :seed,
                    :person_index,
                    :testlet_index,
                    :rater_index,
                    :within_testlet_item,
                ),
                enumeration_order_invariant = true,
                items_per_testlet_extension_preserves_common_event_uniforms =
                    true,
                cross_julia_bitwise_portability_claimed = false,
            ),
            component_seeds = seeds,
            rater_label_permutation = Tuple(rater_permutation),
        ),
        resource_counts = (;
            n_ratings,
            n_probability_cells,
            n_truth_cells = truth_counts.n_truth_cells,
            max_ratings,
            max_probability_cells,
            max_truth_cells,
            truth_cell_breakdown = truth_counts.breakdown,
        ),
        raw_checks = (;
            probabilities_finite = all(isfinite, probabilities),
            probabilities_nonnegative = all(>=(0.0), probabilities),
            maximum_probability_sum_error = maximum(
                abs(sum(@view probabilities[row, :]) - 1.0)
                for row in axes(probabilities, 1)
            ),
            score_support_valid = all(score -> score in category_levels, scores),
            all_rows_observed = all(row_truth.observed_mask),
            missingness_stream_reserved_not_applied = true,
        ),
    )
end
