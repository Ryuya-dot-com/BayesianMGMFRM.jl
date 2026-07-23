# testlet_design_audit.jl -- clustered-response metadata and LD0 design contracts

const _TESTLET_AUDIT_TARGETS = (
    :scalar_shared_cluster,
    :stable_person_testlet,
    :rater_response_halo,
    :rater_task,
    :mgmfrm_testlet_separation,
)

const _TESTLET_AUDIT_DEFAULT_MAX_MATERIALIZED_PAIR_ROWS = 200_000
const _TESTLET_AUDIT_DEFAULT_MAX_PAIR_COMMON_UNIT_LINKS = 10_000_000

const _LD0_STRUCTURAL_V1_THRESHOLDS = (;
    min_indicators_per_response = 2,
    min_testlets_per_person = 2,
    min_persons_per_testlet = 2,
    min_raters_per_response = 2,
    min_indicators_per_rater_response = 2,
    min_responses_per_rater = 2,
    min_shared_responses_per_rater_pair = 1,
    min_multi_rater_responses = 2,
    min_supported_halo_cells = 2,
    min_occasions_per_person_testlet = 2,
    min_repeated_person_testlet_clusters = 2,
    min_testlets_per_dimension = 2,
    min_raters_per_task = 2,
    min_responses_per_rater_task = 2,
    min_persons_per_rater_task = 2,
    min_pair_common_units = 20,
)

function _testlet_audit_positive(value::Int, name::Symbol)
    value >= 1 || throw(ArgumentError("$name must be positive"))
    return value
end

function _testlet_audit_probability(value::Real, name::Symbol)
    converted = Float64(value)
    isfinite(converted) && 0 < converted < 1 ||
        throw(ArgumentError("$name must be finite and in (0, 1)"))
    return converted
end

function _testlet_checked_pair_combinations(n::Int)
    n < 2 && return 0
    left, right = iseven(n) ? (n ÷ 2, n - 1) : (n, (n - 1) ÷ 2)
    try
        return Base.Checked.checked_mul(left, right)
    catch error
        error isa OverflowError || rethrow()
        throw(ArgumentError(
            "testlet design pair-row preflight overflowed Int"))
    end
end

function _testlet_checked_add(values::Int...)
    total = 0
    for value in values
        try
            total = Base.Checked.checked_add(total, value)
        catch error
            error isa OverflowError || rethrow()
            throw(ArgumentError(
                "testlet design pair-row preflight overflowed Int"))
        end
    end
    return total
end

function _testlet_pair_common_unit_links(groups)
    total = 0
    for facets in values(groups)
        total = _testlet_checked_add(
            total,
            _testlet_checked_pair_combinations(length(facets)),
        )
    end
    return total
end

function _testlet_materialized_pair_preflight(
        data::FacetData;
        max_materialized_pair_rows::Int,
        min_indicators_per_rater_response::Int =
            _LD0_STRUCTURAL_V1_THRESHOLDS.min_indicators_per_rater_response,
        max_pair_common_unit_links::Int =
            _TESTLET_AUDIT_DEFAULT_MAX_PAIR_COMMON_UNIT_LINKS,
        materialized_pair_rows_limit_name::Symbol =
            :max_materialized_pair_rows,
        pair_common_unit_links_limit_name::Symbol =
            :max_pair_common_unit_links)
    max_materialized_pair_rows >= 1 ||
        throw(ArgumentError(
            "$materialized_pair_rows_limit_name must be positive"))
    max_pair_common_unit_links >= 1 ||
        throw(ArgumentError(
            "$pair_common_unit_links_limit_name must be positive"))
    min_indicators_per_rater_response >= 1 ||
        throw(ArgumentError(
            "min_indicators_per_rater_response must be positive"))
    all(role -> haskey(data.optional, role), (:response_id, :testlet_id)) ||
        throw(ArgumentError(
            "pair-row preflight requires response_id and testlet_id metadata"))

    testlet = data.optional[:testlet_id]
    testlet_levels = data.optional_levels[:testlet_id]
    response = data.optional[:response_id]
    items_by_testlet = [Set{Int}() for _ in testlet_levels]
    raters_by_testlet = [Set{Int}() for _ in testlet_levels]
    raters_by_testlet_response = Dict{Tuple{Int,Int},Set{Int}}()
    raters_by_testlet_response_item =
        Dict{Tuple{Int,Int,Int},Set{Int}}()
    single_items_by_unit = Dict{Tuple{Int,Int},Set{Int}}()
    within_rater_items_by_unit = Dict{Tuple{Int,Int,Int},Set{Int}}()
    items_by_response_rater = Dict{Tuple{Int,Int},Set{Int}}()
    raters_by_common_unit = Dict{Tuple{Int,Int,Int},Set{Int}}()
    for row in 1:data.n
        push!(items_by_testlet[testlet[row]], data.item[row])
        push!(raters_by_testlet[testlet[row]], data.rater[row])
        push!(get!(raters_by_testlet_response,
            (testlet[row], response[row]), Set{Int}()), data.rater[row])
        push!(get!(raters_by_testlet_response_item,
            (testlet[row], response[row], data.item[row]), Set{Int}()),
            data.rater[row])
        push!(get!(single_items_by_unit,
            (testlet[row], response[row]), Set{Int}()), data.item[row])
        push!(get!(within_rater_items_by_unit,
            (testlet[row], response[row], data.rater[row]), Set{Int}()),
            data.item[row])
        push!(get!(items_by_response_rater,
            (response[row], data.rater[row]), Set{Int}()), data.item[row])
        push!(get!(raters_by_common_unit,
            (testlet[row], response[row], data.item[row]), Set{Int}()),
            data.rater[row])
    end
    single_rating_item_applicable_by_testlet = trues(length(testlet_levels))
    for (key, raters) in raters_by_testlet_response
        length(raters) == 1 ||
            (single_rating_item_applicable_by_testlet[first(key)] = false)
    end
    for (key, raters) in raters_by_testlet_response_item
        length(raters) == 1 ||
            (single_rating_item_applicable_by_testlet[first(key)] = false)
    end
    single_rating_item_all_testlets_applicable =
        all(single_rating_item_applicable_by_testlet)
    single_rating_item_any_testlet_applicable =
        any(single_rating_item_applicable_by_testlet)
    n_diagnostic_candidate_pairs = 0
    for stratum in eachindex(testlet_levels)
        item_pairs = _testlet_checked_pair_combinations(
            length(items_by_testlet[stratum]))
        rater_pairs = _testlet_checked_pair_combinations(
            length(raters_by_testlet[stratum]))
        item_family_pairs = single_rating_item_applicable_by_testlet[stratum] ?
            _testlet_checked_add(item_pairs, item_pairs) : item_pairs
        n_diagnostic_candidate_pairs = _testlet_checked_add(
            n_diagnostic_candidate_pairs,
            item_family_pairs,
            rater_pairs,
        )
    end
    n_projected_rater_pairs =
        _testlet_checked_pair_combinations(length(data.rater_levels))
    n_materialized_pair_rows = _testlet_checked_add(
        n_diagnostic_candidate_pairs,
        n_projected_rater_pairs,
    )
    n_materialized_pair_rows <= max_materialized_pair_rows ||
        throw(ArgumentError(
            "testlet design audit would materialize $n_materialized_pair_rows pair rows, exceeding $materialized_pair_rows_limit_name=$max_materialized_pair_rows; analyze prespecified strata separately or raise the limit deliberately"))
    n_single_rating_common_unit_links = 0
    for (key, items) in single_items_by_unit
        single_rating_item_applicable_by_testlet[first(key)] || continue
        n_single_rating_common_unit_links = _testlet_checked_add(
            n_single_rating_common_unit_links,
            _testlet_checked_pair_combinations(length(items)),
        )
    end
    n_within_rater_common_unit_links =
        _testlet_pair_common_unit_links(within_rater_items_by_unit)
    n_rater_common_unit_links =
        _testlet_pair_common_unit_links(raters_by_common_unit)
    n_pair_common_unit_links = _testlet_checked_add(
        n_single_rating_common_unit_links,
        n_within_rater_common_unit_links,
        n_rater_common_unit_links,
    )
    supported_raters_by_response = Dict{Int,Set{Int}}()
    for (key, items) in items_by_response_rater
        length(items) >= min_indicators_per_rater_response || continue
        response_id, rater_id = key
        push!(get!(supported_raters_by_response, response_id, Set{Int}()),
            rater_id)
    end
    n_projected_rater_response_links = _testlet_pair_common_unit_links(
        supported_raters_by_response)
    n_audit_pair_common_unit_links = _testlet_checked_add(
        n_pair_common_unit_links,
        n_projected_rater_response_links,
    )
    n_audit_pair_common_unit_links <= max_pair_common_unit_links ||
        throw(ArgumentError(
            "testlet design audit would process $n_audit_pair_common_unit_links pair/common-unit links, exceeding $pair_common_unit_links_limit_name=$max_pair_common_unit_links; analyze prespecified strata separately or raise the limit deliberately"))
    return (;
        schema = "bayesianmgmfrm.testlet_pair_row_preflight.v1",
        single_rating_item_all_testlets_applicable,
        single_rating_item_any_testlet_applicable,
        single_rating_item_applicable_by_testlet =
            Tuple(single_rating_item_applicable_by_testlet),
        n_diagnostic_candidate_pairs,
        n_projected_rater_pairs,
        n_materialized_pair_rows,
        max_materialized_pair_rows,
        n_single_rating_common_unit_links,
        n_within_rater_common_unit_links,
        n_rater_common_unit_links,
        n_pair_common_unit_links,
        n_projected_rater_response_links,
        projected_rater_min_indicators_per_response =
            min_indicators_per_rater_response,
        n_audit_pair_common_unit_links,
        max_pair_common_unit_links,
    )
end

function _testlet_audit_row(;
        check::Symbol,
        target = :all,
        status::Symbol,
        severity::Symbol,
        blocking_for = Symbol[],
        observed = missing,
        required = missing,
        profile::Symbol = :ld0_structural_v1,
        note::Symbol,
        examples = (),
        details = (;))
    return (;
        schema = "bayesianmgmfrm.testlet_design_audit_row.v1",
        check,
        target,
        status,
        severity,
        blocking_for = Tuple(blocking_for),
        observed,
        required,
        profile,
        note,
        examples = Tuple(examples),
        details,
    )
end

function _testlet_design_signature(data::FacetData)
    roles = (:occasion, :response_id, :task, :testlet_id)
    records = Tuple[]
    for row in 1:data.n
        optional = Tuple(
            haskey(data.optional, role) ?
                repr(data.optional_levels[role][data.optional[role][row]]) : "<absent>"
            for role in roles
        )
        push!(records, (
            repr(data.person_levels[data.person[row]]),
            repr(data.rater_levels[data.rater[row]]),
            repr(data.item_levels[data.item[row]]),
            optional...,
        ))
    end
    sort!(records; by = repr)
    # Keep the canonical container dynamically sized. Converting a large
    # record vector to `Tuple` makes its row count part of the inferred type,
    # which can trigger a fresh, very large LLVM compilation for every design
    # size even though the hash operation itself is purely runtime work.
    canonical = repr(records)
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(codeunits(canonical))),
    )
end

function _testlet_bipartite_components(
        left_name::Symbol,
        left_index::Vector{Int},
        left_levels,
        right_name::Symbol,
        right_index::Vector{Int},
        right_levels)
    adjacency = Dict{Tuple{Symbol,Int},Set{Tuple{Symbol,Int}}}()
    for index in eachindex(left_levels)
        adjacency[(left_name, index)] = Set{Tuple{Symbol,Int}}()
    end
    for index in eachindex(right_levels)
        adjacency[(right_name, index)] = Set{Tuple{Symbol,Int}}()
    end
    for row in eachindex(left_index)
        left = (left_name, left_index[row])
        right = (right_name, right_index[row])
        push!(adjacency[left], right)
        push!(adjacency[right], left)
    end

    seen = Set{Tuple{Symbol,Int}}()
    components = Tuple[]
    for start in sort(collect(keys(adjacency)); by = repr)
        start in seen && continue
        queue = [start]
        head = 1
        push!(seen, start)
        nodes = NamedTuple[]
        while head <= length(queue)
            node = queue[head]
            head += 1
            facet, index = node
            levels = facet === left_name ? left_levels : right_levels
            push!(nodes, (; facet, level = levels[index]))
            for neighbor in sort(collect(adjacency[node]); by = repr)
                neighbor in seen && continue
                push!(seen, neighbor)
                push!(queue, neighbor)
            end
        end
        sort!(nodes; by = row -> (string(row.facet), repr(row.level)))
        push!(components, Tuple(nodes))
    end
    sort!(components; by = component -> (-length(component), repr(component)))
    return Tuple(components)
end

function _testlet_graph_bridges(adjacency::Vector{Set{Int}})
    discovery = zeros(Int, length(adjacency))
    low = zeros(Int, length(adjacency))
    parent = zeros(Int, length(adjacency))
    next_neighbor = zeros(Int, length(adjacency))
    neighbors = [collect(set) for set in adjacency]
    clock = 0
    bridges = Tuple{Int,Int}[]
    for root in eachindex(adjacency)
        discovery[root] == 0 || continue
        clock += 1
        discovery[root] = clock
        low[root] = clock
        stack = Int[root]
        while !isempty(stack)
            node = stack[end]
            if next_neighbor[node] < length(neighbors[node])
                next_neighbor[node] += 1
                neighbor = neighbors[node][next_neighbor[node]]
                if discovery[neighbor] == 0
                    parent[neighbor] = node
                    clock += 1
                    discovery[neighbor] = clock
                    low[neighbor] = clock
                    push!(stack, neighbor)
                elseif neighbor != parent[node]
                    low[node] = min(low[node], discovery[neighbor])
                end
            else
                pop!(stack)
                ancestor = parent[node]
                if ancestor != 0
                    low[ancestor] = min(low[ancestor], low[node])
                    low[node] > discovery[ancestor] &&
                        push!(bridges, minmax(ancestor, node))
                end
            end
        end
    end
    sort!(bridges)
    return Tuple(bridges)
end

function _testlet_bipartite_bridges(
        left_index::Vector{Int},
        left_levels,
        right_index::Vector{Int},
        right_levels)
    n_left = length(left_levels)
    adjacency = [Set{Int}() for _ in 1:(n_left + length(right_levels))]
    for row in eachindex(left_index)
        left = left_index[row]
        right = n_left + right_index[row]
        push!(adjacency[left], right)
        push!(adjacency[right], left)
    end
    bridges = _testlet_graph_bridges(adjacency)
    rows = NamedTuple[]
    for (left, right) in bridges
        if left > n_left
            left, right = right, left
        end
        push!(rows, (;
            left = left_levels[left],
            right = right_levels[right - n_left],
        ))
    end
    sort!(rows; by = repr)
    return Tuple(rows)
end

function _testlet_pair_support(
        facet::Symbol,
        facet_index::Vector{Int},
        facet_levels,
        unit_keys,
        min_common_units::Int)
    if length(facet_levels) < 2
        return (;
            facet,
            status = :not_applicable,
            min_common_units,
            n_pairs = 0,
            n_pairs_with_observations = 0,
            n_eligible_pairs = 0,
            maximum_common_units = 0,
            duplicate_unit_facets = (),
            pairs = (),
        )
    end
    facets_by_unit = Dict{Any,Set{Int}}()
    unit_facet_counts = Dict{Tuple{Any,Int},Int}()
    for row in eachindex(facet_index)
        level = facet_index[row]
        unit = unit_keys[row]
        push!(get!(facets_by_unit, unit, Set{Int}()), level)
        key = (unit, level)
        unit_facet_counts[key] = get(unit_facet_counts, key, 0) + 1
    end
    duplicate_unit_facets = sort([
        (; unit = first(key), facet_level = facet_levels[last(key)], count)
        for (key, count) in unit_facet_counts if count > 1
    ]; by = repr)

    common_counts = Dict{Tuple{Int,Int},Int}()
    for facets in values(facets_by_unit)
        ordered = sort(collect(facets))
        length(ordered) >= 2 || continue
        for left_index in 1:(length(ordered) - 1),
                right_index in (left_index + 1):length(ordered)
            key = (ordered[left_index], ordered[right_index])
            common_counts[key] = get(common_counts, key, 0) + 1
        end
    end
    pairs = NamedTuple[]
    for left in 1:(length(facet_levels) - 1),
            right in (left + 1):length(facet_levels)
        common_units = get(common_counts, (left, right), 0)
        push!(pairs, (;
            left = facet_levels[left],
            right = facet_levels[right],
            common_units,
            eligible = isempty(duplicate_unit_facets) &&
                common_units >= min_common_units,
        ))
    end
    n_eligible = count(pair -> pair.eligible, pairs)
    n_observed = count(pair -> pair.common_units > 0, pairs)
    maximum_common_units = isempty(pairs) ? 0 : maximum(pair -> pair.common_units, pairs)
    status = !isempty(duplicate_unit_facets) ? :invalid_duplicate :
        isempty(pairs) ? :not_applicable :
        n_eligible > 0 ? :eligible : :sparse
    return (;
        facet,
        status,
        min_common_units,
        n_pairs = length(pairs),
        n_pairs_with_observations = n_observed,
        n_eligible_pairs = n_eligible,
        maximum_common_units,
        duplicate_unit_facets = Tuple(duplicate_unit_facets),
        pairs = Tuple(pairs),
    )
end

function _testlet_stratified_pair_support(
        facet::Symbol,
        facet_index::Vector{Int},
        facet_levels,
        unit_keys,
        stratum_index::Vector{Int},
        stratum_levels,
        min_common_units::Int;
        applicable::Bool = true,
        applicable_by_stratum = nothing,
        inapplicable_reason::Symbol = :not_applicable)
    applicability = applicable_by_stratum === nothing ?
        fill(applicable, length(stratum_levels)) :
        Bool.(collect(applicable_by_stratum))
    length(applicability) == length(stratum_levels) ||
        throw(ArgumentError(
            "applicable_by_stratum must match stratum_levels"))

    strata = NamedTuple[]
    pairs = NamedTuple[]
    duplicates = NamedTuple[]
    rows_by_stratum = [Int[] for _ in stratum_levels]
    for row in eachindex(stratum_index)
        push!(rows_by_stratum[stratum_index[row]], row)
    end
    for stratum in eachindex(stratum_levels)
        if !applicability[stratum]
            push!(strata, (;
                testlet_id = stratum_levels[stratum],
                facet,
                status = :not_applicable,
                min_common_units,
                n_pairs = 0,
                n_pairs_with_observations = 0,
                n_eligible_pairs = 0,
                maximum_common_units = 0,
                duplicate_unit_facets = (),
                pairs = (),
                inapplicable_reason,
            ))
            continue
        end
        rows = rows_by_stratum[stratum]
        observed_facets = sort(unique(facet_index[rows]))
        local_levels = facet_levels[observed_facets]
        local_by_global = Dict(global_index => local_index
            for (local_index, global_index) in enumerate(observed_facets))
        local_facet_index = Int[local_by_global[index]
            for index in facet_index[rows]]
        support = _testlet_pair_support(
            facet,
            local_facet_index,
            local_levels,
            unit_keys[rows],
            min_common_units,
        )
        push!(strata, (;
            testlet_id = stratum_levels[stratum],
            support...,
            inapplicable_reason = missing,
        ))
        append!(pairs, ((;
            testlet_id = stratum_levels[stratum],
            pair...,
        ) for pair in support.pairs))
        append!(duplicates, ((;
            testlet_id = stratum_levels[stratum],
            duplicate...,
        ) for duplicate in support.duplicate_unit_facets))
    end
    n_eligible_pairs = count(pair -> pair.eligible, pairs)
    n_pairs_with_observations = count(pair -> pair.common_units > 0, pairs)
    maximum_common_units = isempty(pairs) ? 0 :
        maximum(pair -> pair.common_units, pairs)
    n_applicable_strata = count(applicability)
    n_inapplicable_strata = length(applicability) - n_applicable_strata
    status = !isempty(duplicates) ? :invalid_duplicate :
        n_applicable_strata == 0 ? :not_applicable :
        n_inapplicable_strata > 0 ? :partially_applicable :
        isempty(pairs) ? :not_applicable :
        n_eligible_pairs > 0 ? :eligible : :sparse
    return (;
        facet,
        status,
        min_common_units,
        estimation_strata = :testlet_id,
        n_strata = length(strata),
        n_applicable_strata,
        n_inapplicable_strata,
        n_pairs = length(pairs),
        n_pairs_with_observations,
        n_eligible_pairs,
        maximum_common_units,
        duplicate_unit_facets = Tuple(duplicates),
        pairs = Tuple(pairs),
        strata = Tuple(strata),
        inapplicable_reason = n_inapplicable_strata > 0 ?
            inapplicable_reason : missing,
    )
end

function _testlet_projected_rater_components(data::FacetData,
        responses_by_rater,
        minimum_shared_responses::Int)
    adjacency = [Set{Int}() for _ in data.rater_levels]
    raters_by_response = Dict{Int,Vector{Int}}()
    for rater in eachindex(responses_by_rater),
            response in responses_by_rater[rater]
        push!(get!(raters_by_response, response, Int[]), rater)
    end
    shared_counts = Dict{Tuple{Int,Int},Int}()
    for raters in values(raters_by_response)
        sort!(raters)
        length(raters) >= 2 || continue
        for left_position in 1:(length(raters) - 1),
                right_position in (left_position + 1):length(raters)
            key = (raters[left_position], raters[right_position])
            shared_counts[key] = get(shared_counts, key, 0) + 1
        end
    end
    pair_counts = NamedTuple[]
    for a in 1:(length(data.rater_levels) - 1),
            b in (a + 1):length(data.rater_levels)
        n_shared = get(shared_counts, (a, b), 0)
        linked = n_shared >= minimum_shared_responses
        if linked
            push!(adjacency[a], b)
            push!(adjacency[b], a)
        end
        push!(pair_counts, (; a, b, n_shared, linked))
    end

    bridge_edges = Set(_testlet_graph_bridges(adjacency))
    pair_rows = Tuple((;
        rater_a = data.rater_levels[row.a],
        rater_b = data.rater_levels[row.b],
        shared_responses = row.n_shared,
        linked = row.linked,
        bridge = row.linked && ((row.a, row.b) in bridge_edges),
    ) for row in pair_counts)

    seen = Set{Int}()
    components = Tuple[]
    for start in eachindex(data.rater_levels)
        start in seen && continue
        queue = [start]
        head = 1
        push!(seen, start)
        levels = Any[]
        while head <= length(queue)
            current = queue[head]
            head += 1
            push!(levels, data.rater_levels[current])
            for neighbor in sort(collect(adjacency[current]))
                neighbor in seen && continue
                push!(seen, neighbor)
                push!(queue, neighbor)
            end
        end
        sort!(levels; by = repr)
        push!(components, Tuple(levels))
    end
    sort!(components; by = component -> (-length(component), repr(component)))
    return Tuple(components), pair_rows
end

function _testlet_missing_metadata_result(data::FacetData,
        spec,
        target::Symbol,
        requested_profile::Symbol,
        effective_profile::Symbol,
        profile_is_frozen::Bool,
        thresholds,
        missing_roles)
    row = _testlet_audit_row(;
        check = :required_cluster_metadata,
        status = :error,
        severity = :error,
        blocking_for = collect(_TESTLET_AUDIT_TARGETS),
        observed = Tuple(sort(collect(keys(data.optional)); by = string)),
        required = (:response_id, :testlet_id),
        profile = effective_profile,
        note = :required_response_and_testlet_identifiers_not_declared,
        examples = missing_roles,
    )
    return (;
        schema = "bayesianmgmfrm.testlet_design_audit.v1",
        object = :testlet_design_audit,
        target,
        requested_support_profile = requested_profile,
        support_profile = effective_profile,
        profile_is_frozen,
        family = spec === nothing ? missing : spec.family,
        dimensions = spec === nothing ? missing : spec.dimensions,
        design_signature = _testlet_design_signature(data),
        status = :error,
        schema_valid = false,
        structural_identification_supported = false,
        candidate_scope_supported = false,
        structurally_eligible_for_candidate = false,
        structural_profile_met = false,
        current_fit_supported = false,
        diagnostic_pair_support = (;),
        any_diagnostic_pair_family_supported = false,
        mechanism_claim_eligible = false,
        calibration_status = :not_calibrated,
        rows = (row,),
        summary = (;
            missing_required_roles = Tuple(missing_roles),
            response_nesting_valid = false,
            duplicate_rating_keys_valid = false,
            scalar_shared_cluster_structurally_eligible = false,
            stable_person_testlet_structurally_eligible = false,
            rater_response_halo_structurally_eligible = false,
            rater_task_structurally_eligible = false,
            mgmfrm_testlet_separation_structurally_eligible = false,
        ),
        thresholds,
        caveat = :design_audit_does_not_establish_a_cluster_effect,
    )
end

function _testlet_target_result(target::Symbol;
        schema_valid::Bool,
        profile_is_frozen::Bool,
        scalar_identified::Bool,
        scalar_scope_supported::Bool,
        scalar_eligible::Bool,
        scalar_profile_met::Bool,
        stable_eligible::Bool,
        stable_profile_met::Bool,
        halo_eligible::Bool,
        halo_profile_met::Bool,
        rater_task_eligible::Bool,
        rater_task_profile_met::Bool,
        q_applicable::Bool,
        q_eligible::Bool,
        q_profile_met::Bool)
    !schema_valid && return (;
        status = :error,
        structural_identification_supported = false,
        candidate_scope_supported = false,
        structurally_eligible_for_candidate = false,
        structural_profile_met = false,
        reason = :invalid_identifier_contract,
    )
    if target === :scalar_shared_cluster
        if !scalar_identified
            return (;
                status = :underidentified,
                structural_identification_supported = false,
                candidate_scope_supported = scalar_scope_supported,
                structurally_eligible_for_candidate = false,
                structural_profile_met = false,
                reason = :scalar_cluster_structure_underidentified,
            )
        elseif !scalar_scope_supported
            return (;
                status = :unsupported_candidate,
                structural_identification_supported = true,
                candidate_scope_supported = false,
                structurally_eligible_for_candidate = false,
                structural_profile_met = false,
                reason = :repeated_responses_require_a_distinct_candidate,
            )
        end
        return (;
            status = scalar_profile_met && profile_is_frozen ? :ok : :warning,
            structural_identification_supported = true,
            candidate_scope_supported = true,
            structurally_eligible_for_candidate = scalar_eligible,
            structural_profile_met = scalar_profile_met,
            reason = scalar_profile_met ?
                (profile_is_frozen ? :frozen_structural_profile_met :
                    :custom_unvalidated_profile_met) :
                :structural_profile_not_met,
        )
    elseif target === :stable_person_testlet
        return stable_eligible ? (;
            status = :warning,
            structural_identification_supported = true,
            candidate_scope_supported = true,
            structurally_eligible_for_candidate = true,
            structural_profile_met = stable_profile_met,
            reason = :candidate_not_currently_fit_supported,
        ) : (;
            status = :underidentified,
            structural_identification_supported = false,
            candidate_scope_supported = true,
            structurally_eligible_for_candidate = false,
            structural_profile_met = false,
            reason = :stable_person_testlet_structure_underidentified,
        )
    elseif target === :rater_response_halo
        return halo_eligible ? (;
            status = :warning,
            structural_identification_supported = true,
            candidate_scope_supported = true,
            structurally_eligible_for_candidate = true,
            structural_profile_met = halo_profile_met,
            reason = halo_profile_met ? :candidate_not_currently_fit_supported :
                :independent_rating_design_not_established,
        ) : (;
            status = :underidentified,
            structural_identification_supported = false,
            candidate_scope_supported = true,
            structurally_eligible_for_candidate = false,
            structural_profile_met = false,
            reason = :rater_response_halo_structure_underidentified,
        )
    elseif target === :rater_task
        return rater_task_eligible ? (;
            status = :warning,
            structural_identification_supported = true,
            candidate_scope_supported = true,
            structurally_eligible_for_candidate = true,
            structural_profile_met = rater_task_profile_met,
            reason = :candidate_not_currently_fit_supported,
        ) : (;
            status = :underidentified,
            structural_identification_supported = false,
            candidate_scope_supported = true,
            structurally_eligible_for_candidate = false,
            structural_profile_met = false,
            reason = :rater_task_structure_underidentified,
        )
    elseif target === :mgmfrm_testlet_separation
        !q_applicable && return (;
            status = :not_applicable,
            structural_identification_supported = false,
            candidate_scope_supported = false,
            structurally_eligible_for_candidate = false,
            structural_profile_met = false,
            reason = :fixed_q_mgmfrm_not_requested,
        )
        return q_eligible ? (;
            status = :warning,
            structural_identification_supported = true,
            candidate_scope_supported = true,
            structurally_eligible_for_candidate = true,
            structural_profile_met = q_profile_met,
            reason = :candidate_not_currently_fit_supported,
        ) : (;
            status = :underidentified,
            structural_identification_supported = false,
            candidate_scope_supported = true,
            structurally_eligible_for_candidate = false,
            structural_profile_met = false,
            reason = :q_by_testlet_structure_underidentified,
        )
    end
    throw(ArgumentError("unsupported testlet audit target :$target"))
end

"""
    testlet_design_audit(data_or_spec_or_design;
        target = :scalar_shared_cluster,
        support_profile = :ld0_structural_v1,
        min_indicators_per_response = 2,
        min_testlets_per_person = 2,
        min_persons_per_testlet = 2,
        independent_ratings_declared = false,
        max_materialized_pair_rows = 200_000,
        max_pair_common_unit_links = 10_000_000)

Audit the clustered-rating design encoded by `response_id` and `testlet_id`
metadata before fitting a local-dependence or testlet extension. The audit
checks globally unique response nesting, duplicate rating keys, response and
person-by-testlet replication, mechanism-specific graph connectivity,
rater-by-response halo support, repeated-response support, rater-by-task
crossing, and fixed-Q dimension-by-testlet coverage when applicable.
Before quadratic item/rater pair tables are expanded, an O(n) preflight bounds
their total row count with `max_materialized_pair_rows` and the total pair by
common-unit incidence count with `max_pair_common_unit_links`. The graph bridge
check uses a linear-time undirected-graph traversal.

The top-level `status` is target-specific. `:ok` means only that the unchanged
frozen structural profile is met; it does not show that a cluster effect exists.
`:warning` records a weak, custom, or not-yet-fit-supported candidate,
`:unsupported_candidate` distinguishes a current candidate-shape limitation
from structural underidentification, `:underidentified` blocks the requested
structure, and `:error` denotes an invalid identifier contract.
`structurally_eligible_for_candidate`, `structural_profile_met`, and
`current_fit_supported` are intentionally separate. `mechanism_claim_eligible`
remains `false` until the diagnostic and model families have been calibrated
under independent known-truth generators. The current audit targets are
`:scalar_shared_cluster`, `:stable_person_testlet`, `:rater_response_halo`,
`:rater_task`, and `:mgmfrm_testlet_separation`.
"""
function testlet_design_audit(data_or_spec_or_design;
        target::Symbol = :scalar_shared_cluster,
        support_profile::Symbol = :ld0_structural_v1,
        min_indicators_per_response::Int = 2,
        min_testlets_per_person::Int = 2,
        min_persons_per_testlet::Int = 2,
        min_raters_per_response::Int = 2,
        min_indicators_per_rater_response::Int = 2,
        min_responses_per_rater::Int = 2,
        min_shared_responses_per_rater_pair::Int = 1,
        min_multi_rater_responses::Int = 2,
        min_supported_halo_cells::Int = 2,
        min_occasions_per_person_testlet::Int = 2,
        min_repeated_person_testlet_clusters::Int = 2,
        min_testlets_per_dimension::Int = 2,
        min_raters_per_task::Int = 2,
        min_responses_per_rater_task::Int = 2,
        min_persons_per_rater_task::Int = 2,
        min_pair_common_units::Int = 20,
        independent_ratings_declared::Bool = false,
        max_materialized_pair_rows::Int =
            _TESTLET_AUDIT_DEFAULT_MAX_MATERIALIZED_PAIR_ROWS,
        max_pair_common_unit_links::Int =
            _TESTLET_AUDIT_DEFAULT_MAX_PAIR_COMMON_UNIT_LINKS)
    target in _TESTLET_AUDIT_TARGETS ||
        throw(ArgumentError("target must be one of $(_TESTLET_AUDIT_TARGETS)"))
    support_profile === :ld0_structural_v1 ||
        throw(ArgumentError("only support_profile = :ld0_structural_v1 is supported"))
    max_materialized_pair_rows >= 1 ||
        throw(ArgumentError("max_materialized_pair_rows must be positive"))
    max_pair_common_unit_links >= 1 ||
        throw(ArgumentError("max_pair_common_unit_links must be positive"))
    for (value, name) in (
            (min_indicators_per_response, :min_indicators_per_response),
            (min_testlets_per_person, :min_testlets_per_person),
            (min_persons_per_testlet, :min_persons_per_testlet),
            (min_raters_per_response, :min_raters_per_response),
            (min_indicators_per_rater_response,
                :min_indicators_per_rater_response),
            (min_responses_per_rater, :min_responses_per_rater),
            (min_shared_responses_per_rater_pair,
                :min_shared_responses_per_rater_pair),
            (min_multi_rater_responses, :min_multi_rater_responses),
            (min_supported_halo_cells, :min_supported_halo_cells),
            (min_occasions_per_person_testlet,
                :min_occasions_per_person_testlet),
            (min_repeated_person_testlet_clusters,
                :min_repeated_person_testlet_clusters),
            (min_testlets_per_dimension, :min_testlets_per_dimension),
            (min_raters_per_task, :min_raters_per_task),
            (min_responses_per_rater_task, :min_responses_per_rater_task),
            (min_persons_per_rater_task, :min_persons_per_rater_task),
            (min_pair_common_units, :min_pair_common_units),
        )
        _testlet_audit_positive(value, name)
    end

    thresholds = (;
        min_indicators_per_response,
        min_testlets_per_person,
        min_persons_per_testlet,
        min_raters_per_response,
        min_indicators_per_rater_response,
        min_responses_per_rater,
        min_shared_responses_per_rater_pair,
        min_multi_rater_responses,
        min_supported_halo_cells,
        min_occasions_per_person_testlet,
        min_repeated_person_testlet_clusters,
        min_testlets_per_dimension,
        min_raters_per_task,
        min_responses_per_rater_task,
        min_persons_per_rater_task,
        min_pair_common_units,
    )
    profile_is_frozen = thresholds == _LD0_STRUCTURAL_V1_THRESHOLDS
    effective_support_profile = profile_is_frozen ? support_profile :
        :custom_unvalidated

    data = _facet_data(data_or_spec_or_design)
    spec = _facet_spec(data_or_spec_or_design)
    missing_roles = [role for role in (:response_id, :testlet_id)
        if !haskey(data.optional, role)]
    isempty(missing_roles) || return _testlet_missing_metadata_result(
        data,
        spec,
        target,
        support_profile,
        effective_support_profile,
        profile_is_frozen,
        thresholds,
        missing_roles,
    )
    pair_row_preflight = _testlet_materialized_pair_preflight(
        data;
        max_materialized_pair_rows,
        min_indicators_per_rater_response,
        max_pair_common_unit_links,
    )

    response_index = data.optional[:response_id]
    response_levels = data.optional_levels[:response_id]
    testlet_index = data.optional[:testlet_id]
    testlet_levels = data.optional_levels[:testlet_id]
    occasion_present = haskey(data.optional, :occasion)
    occasion_index = occasion_present ? data.optional[:occasion] : Int[]
    occasion_levels = occasion_present ? data.optional_levels[:occasion] : Any[]
    task_present = haskey(data.optional, :task)
    task_index = task_present ? data.optional[:task] : Int[]
    task_levels = task_present ? data.optional_levels[:task] : Any[]

    response_persons = [Set{Int}() for _ in response_levels]
    response_testlets = [Set{Int}() for _ in response_levels]
    response_occasions = [Set{Int}() for _ in response_levels]
    response_tasks = [Set{Int}() for _ in response_levels]
    response_items = [Set{Int}() for _ in response_levels]
    response_raters = [Set{Int}() for _ in response_levels]
    responses_by_rater = [Set{Int}() for _ in data.rater_levels]
    testlets_by_person = [Set{Int}() for _ in data.person_levels]
    persons_by_testlet = [Set{Int}() for _ in testlet_levels]
    testlets_by_rater = [Set{Int}() for _ in data.rater_levels]
    item_testlets = [Set{Int}() for _ in data.item_levels]
    testlet_items = [Set{Int}() for _ in testlet_levels]
    responses_by_person_testlet = Dict{Tuple{Int,Int},Set{Int}}()
    occasions_by_person_testlet = Dict{Tuple{Int,Int},Set{Int}}()
    items_by_rater_response = Dict{Tuple{Int,Int},Set{Int}}()
    raters_by_response_item = Dict{Tuple{Int,Int},Set{Int}}()
    duplicate_counts = Dict{Tuple{Int,Int,Int},Int}()

    for row in 1:data.n
        response = response_index[row]
        testlet = testlet_index[row]
        person = data.person[row]
        rater = data.rater[row]
        item = data.item[row]
        push!(response_persons[response], person)
        push!(response_testlets[response], testlet)
        occasion_present && push!(response_occasions[response], occasion_index[row])
        task_present && push!(response_tasks[response], task_index[row])
        push!(response_items[response], item)
        push!(response_raters[response], rater)
        push!(responses_by_rater[rater], response)
        push!(testlets_by_person[person], testlet)
        push!(persons_by_testlet[testlet], person)
        push!(testlets_by_rater[rater], testlet)
        push!(item_testlets[item], testlet)
        push!(testlet_items[testlet], item)
        key = (person, testlet)
        push!(get!(responses_by_person_testlet, key, Set{Int}()), response)
        occasion_present &&
            push!(get!(occasions_by_person_testlet, key, Set{Int}()),
                occasion_index[row])
        push!(get!(items_by_rater_response, (rater, response), Set{Int}()), item)
        push!(get!(raters_by_response_item, (response, item), Set{Int}()), rater)
        duplicate_key = (response, rater, item)
        duplicate_counts[duplicate_key] = get(duplicate_counts, duplicate_key, 0) + 1
    end

    invalid_response_person = findall(set -> length(set) != 1, response_persons)
    invalid_response_testlet = findall(set -> length(set) != 1, response_testlets)
    invalid_response_occasion = occasion_present ?
        findall(set -> length(set) != 1, response_occasions) : Int[]
    invalid_response_task = task_present ?
        findall(set -> length(set) != 1, response_tasks) : Int[]
    duplicate_keys = sort([
        key => count for (key, count) in duplicate_counts if count > 1
    ]; by = pair -> repr(first(pair)))
    response_nesting_valid = isempty(invalid_response_person) &&
        isempty(invalid_response_testlet) &&
        isempty(invalid_response_occasion) &&
        isempty(invalid_response_task)
    duplicate_rating_keys_valid = isempty(duplicate_keys)
    schema_valid = response_nesting_valid && duplicate_rating_keys_valid

    rows = NamedTuple[]
    push!(rows, _testlet_audit_row(;
        check = :required_cluster_metadata,
        status = :ok,
        severity = :info,
        observed = (:response_id, :testlet_id),
        required = (:response_id, :testlet_id),
        profile = effective_support_profile,
        note = :required_response_and_testlet_identifiers_declared,
    ))
    invalid_response_examples = Tuple(
        response_levels[index]
        for index in sort(unique(vcat(
            invalid_response_person,
            invalid_response_testlet,
            invalid_response_occasion,
            invalid_response_task,
        )))[1:min(end, 10)]
    )
    push!(rows, _testlet_audit_row(;
        check = :response_nesting,
        status = isempty(invalid_response_examples) ? :ok : :error,
        severity = isempty(invalid_response_examples) ? :info : :error,
        blocking_for = isempty(invalid_response_examples) ? Symbol[] :
            collect(_TESTLET_AUDIT_TARGETS),
        observed = (;
            n_responses = length(response_levels),
            multiple_person = length(invalid_response_person),
            multiple_testlet = length(invalid_response_testlet),
            multiple_occasion = length(invalid_response_occasion),
            multiple_task = length(invalid_response_task),
        ),
        required = :one_person_one_testlet_one_declared_occasion_and_one_task_per_response,
        profile = effective_support_profile,
        note = isempty(invalid_response_examples) ?
            :response_identifiers_are_globally_nested :
            :response_identifier_reused_across_cluster_owners,
        examples = invalid_response_examples,
    ))
    duplicate_examples = Tuple((;
        response_id = response_levels[first(pair)[1]],
        rater = data.rater_levels[first(pair)[2]],
        item = data.item_levels[first(pair)[3]],
        count = last(pair),
    ) for pair in duplicate_keys[1:min(end, 10)])
    push!(rows, _testlet_audit_row(;
        check = :duplicate_rating_key,
        status = isempty(duplicate_keys) ? :ok : :error,
        severity = isempty(duplicate_keys) ? :info : :error,
        blocking_for = isempty(duplicate_keys) ? Symbol[] :
            collect(_TESTLET_AUDIT_TARGETS),
        observed = length(duplicate_keys),
        required = 0,
        profile = effective_support_profile,
        note = isempty(duplicate_keys) ?
            :response_rater_item_keys_are_unique :
            :duplicate_response_rater_item_key_requires_explicit_identity,
        examples = duplicate_examples,
    ))
    push!(rows, _testlet_audit_row(;
        check = :support_profile_identity,
        status = profile_is_frozen ? :ok : :warning,
        severity = profile_is_frozen ? :info : :warning,
        observed = thresholds,
        required = _LD0_STRUCTURAL_V1_THRESHOLDS,
        profile = effective_support_profile,
        note = profile_is_frozen ? :frozen_structural_profile_unchanged :
            :threshold_override_uses_custom_unvalidated_profile,
    ))

    response_counts = [length(set) for set in responses_by_person_testlet |> values]
    one_response_per_person_testlet = !isempty(response_counts) && all(==(1), response_counts)
    insufficient_persons = findall(set -> length(set) < min_testlets_per_person,
        testlets_by_person)
    insufficient_testlets = findall(set -> length(set) < min_persons_per_testlet,
        persons_by_testlet)
    insufficient_responses = findall(set -> length(set) < min_indicators_per_response,
        response_items)
    person_testlet_components = _testlet_bipartite_components(
        :person,
        data.person,
        data.person_levels,
        :testlet_id,
        testlet_index,
        testlet_levels,
    )
    person_testlet_bridges = _testlet_bipartite_bridges(
        data.person,
        data.person_levels,
        testlet_index,
        testlet_levels,
    )
    ordinary_components = _connected_components(data)
    graphs_connected = length(person_testlet_components) == 1 &&
        length(ordinary_components) == 1
    scalar_identified = schema_valid &&
        isempty(insufficient_persons) && isempty(insufficient_testlets) &&
        isempty(insufficient_responses) && graphs_connected
    scalar_scope_supported = one_response_per_person_testlet
    scalar_eligible = scalar_identified && scalar_scope_supported
    minimum_response_indicators = isempty(response_items) ? 0 :
        minimum(length, response_items)
    scalar_weak_indicator_support =
        minimum_response_indicators <= min_indicators_per_response
    scalar_weak_graph_support = !isempty(person_testlet_bridges)

    push!(rows, _testlet_audit_row(;
        check = :scalar_shared_cluster_support,
        target = :scalar_shared_cluster,
        status = !scalar_identified ? :underidentified :
            !scalar_scope_supported ? :unsupported_candidate :
            (scalar_weak_indicator_support || scalar_weak_graph_support) ?
                :warning : :ok,
        severity = !scalar_identified ? :error :
            (!scalar_scope_supported || scalar_weak_indicator_support ||
                scalar_weak_graph_support) ? :warning : :info,
        blocking_for = !scalar_identified ? [:scalar_shared_cluster] :
            !scalar_scope_supported ? [:current_scalar_candidate] : Symbol[],
        observed = (;
            n_person_testlet_clusters = length(responses_by_person_testlet),
            one_response_per_person_testlet,
            persons_below_testlet_minimum = length(insufficient_persons),
            testlets_below_person_minimum = length(insufficient_testlets),
            responses_below_indicator_minimum = length(insufficient_responses),
            minimum_response_indicators,
            person_testlet_bridge_count = length(person_testlet_bridges),
        ),
        required = (;
            min_testlets_per_person,
            min_persons_per_testlet,
            min_indicators_per_response,
            responses_per_person_testlet = 1,
        ),
        profile = effective_support_profile,
        note = !scalar_identified ? :scalar_cluster_structure_does_not_meet_profile :
            !scalar_scope_supported ? :repeated_responses_require_a_distinct_candidate :
            scalar_weak_indicator_support ? :indicator_count_is_at_structural_minimum :
            scalar_weak_graph_support ? :person_testlet_graph_relies_on_a_single_bridge :
            :scalar_cluster_structure_meets_profile,
        examples = Tuple(response_levels[index]
            for index in insufficient_responses[1:min(end, 10)]),
    ))
    push!(rows, _testlet_audit_row(;
        check = :person_testlet_connectivity,
        status = !graphs_connected ? :underidentified :
            isempty(person_testlet_bridges) ? :ok : :warning,
        severity = !graphs_connected ? :error :
            isempty(person_testlet_bridges) ? :info : :warning,
        blocking_for = graphs_connected ? Symbol[] :
            [:scalar_shared_cluster, :stable_person_testlet],
        observed = (;
            person_testlet_components = length(person_testlet_components),
            person_rater_item_components = length(ordinary_components),
            single_bridge_count = length(person_testlet_bridges),
        ),
        required = (person_testlet_components = 1,
            person_rater_item_components = 1),
        profile = effective_support_profile,
        note = !graphs_connected ? :mechanism_graph_disconnected :
            isempty(person_testlet_bridges) ? :mechanism_graphs_connected :
            :mechanism_graph_connected_but_weakly_bridged,
        details = (; person_testlet_components, person_testlet_bridges),
    ))

    nested_items = findall(set -> length(set) == 1, item_testlets)
    crossed_items = findall(set -> length(set) > 1, item_testlets)
    push!(rows, _testlet_audit_row(;
        check = :item_testlet_mapping,
        status = :ok,
        severity = :info,
        observed = (;
            nested_items = length(nested_items),
            crossed_items = length(crossed_items),
        ),
        required = :reported_not_forced,
        profile = effective_support_profile,
        note = :item_may_be_nested_or_a_cross_testlet_rubric_criterion,
        details = (;
            item_testlets = Tuple((;
                item = data.item_levels[item],
                testlets = Tuple(testlet_levels[index]
                    for index in sort(collect(item_testlets[item]))),
            ) for item in eachindex(data.item_levels)),
        ),
    ))

    supported_raters_by_response = [Set{Int}() for _ in response_levels]
    supported_responses_by_rater = [Set{Int}() for _ in data.rater_levels]
    n_supported_halo_cells = 0
    for ((rater, response), items) in items_by_rater_response
        length(items) >= min_indicators_per_rater_response || continue
        n_supported_halo_cells += 1
        push!(supported_raters_by_response[response], rater)
        push!(supported_responses_by_rater[rater], response)
    end
    supported_multi_rater_response_indices = findall(
        set -> length(set) >= min_raters_per_response,
        supported_raters_by_response,
    )
    n_supported_multi_rater_responses =
        length(supported_multi_rater_response_indices)
    n_observed_multi_rater_responses = count(>=(min_raters_per_response),
        length.(response_raters))
    raters_below_response_minimum = count(
        set -> length(set) < min_responses_per_rater,
        supported_responses_by_rater,
    )
    rater_components, rater_pair_rows = _testlet_projected_rater_components(
        data,
        supported_responses_by_rater,
        min_shared_responses_per_rater_pair,
    )
    rater_overlap_connected = length(rater_components) == 1
    weak_rater_bridges = Tuple(row for row in rater_pair_rows
        if row.bridge &&
            row.shared_responses <= min_shared_responses_per_rater_pair)
    halo_eligible = schema_valid &&
        n_supported_halo_cells >= min_supported_halo_cells &&
        n_supported_multi_rater_responses >= min_multi_rater_responses &&
        raters_below_response_minimum == 0 && rater_overlap_connected &&
        isempty(weak_rater_bridges)
    halo_profile_met = halo_eligible && independent_ratings_declared
    push!(rows, _testlet_audit_row(;
        check = :rater_response_halo_support,
        target = :rater_response_halo,
        status = halo_eligible ? :warning : :underidentified,
        severity = halo_eligible ? :warning : :error,
        blocking_for = halo_eligible ? [:mechanism_attribution] :
            [:rater_response_halo, :mechanism_attribution],
        observed = (;
            supported_rater_response_cells = n_supported_halo_cells,
            observed_multi_rater_responses = n_observed_multi_rater_responses,
            supported_multi_rater_responses = n_supported_multi_rater_responses,
            raters_below_response_minimum,
            projected_rater_components = length(rater_components),
            weak_projected_rater_bridges = length(weak_rater_bridges),
            independent_ratings_declared,
        ),
        required = (;
            min_indicators_per_rater_response,
            min_supported_halo_cells,
            min_raters_per_response,
            min_multi_rater_responses,
            min_responses_per_rater,
            min_shared_responses_per_rater_pair,
        ),
        profile = effective_support_profile,
        note = !halo_eligible ?
            (!isempty(weak_rater_bridges) ?
                :rater_overlap_graph_relies_on_a_single_response_bridge :
                :halo_structure_does_not_meet_profile) :
            independent_ratings_declared ?
                :independent_rating_design_declared_but_not_empirically_verified :
                :rating_independence_not_declared,
        details = (;
            supported_multi_rater_responses = Tuple(
                response_levels[index]
                for index in supported_multi_rater_response_indices),
            rater_components,
            rater_pair_rows,
            weak_rater_bridges,
        ),
    ))

    repeated_clusters = 0
    if occasion_present
        for (key, responses) in responses_by_person_testlet
            occasions = get(occasions_by_person_testlet, key, Set{Int}())
            length(responses) >= min_occasions_per_person_testlet &&
                length(occasions) >= min_occasions_per_person_testlet &&
                (repeated_clusters += 1)
        end
    end
    stable_eligible = schema_valid && occasion_present &&
        repeated_clusters >= min_repeated_person_testlet_clusters &&
        isempty(insufficient_persons) && isempty(insufficient_testlets) &&
        isempty(insufficient_responses) && graphs_connected
    stable_profile_met = stable_eligible && isempty(person_testlet_bridges)
    push!(rows, _testlet_audit_row(;
        check = :repeated_response_decomposition,
        target = :stable_person_testlet,
        status = stable_eligible ? :warning : :underidentified,
        severity = stable_eligible ? :warning : :error,
        blocking_for = stable_eligible ? [:mechanism_attribution] :
            [:stable_person_testlet],
        observed = (;
            occasion_recorded = occasion_present,
            repeated_person_testlet_clusters = repeated_clusters,
            persons_below_testlet_minimum = length(insufficient_persons),
            testlets_below_person_minimum = length(insufficient_testlets),
            person_testlet_bridge_count = length(person_testlet_bridges),
        ),
        required = (;
            min_occasions_per_person_testlet,
            min_repeated_person_testlet_clusters,
            min_indicators_per_response,
            min_testlets_per_person,
            min_persons_per_testlet,
        ),
        profile = effective_support_profile,
        note = stable_eligible ?
            (stable_profile_met ? :repeated_response_structure_meets_minimum :
                :repeated_response_structure_relies_on_a_single_bridge) :
            :stable_and_response_specific_effects_not_separable,
    ))

    rater_task_eligible = false
    rater_task_profile_met = false
    rater_task_components = ()
    person_task_components = ()
    raters_below_task_minimum = Int[]
    tasks_below_rater_minimum = Int[]
    insufficient_rater_task_cells = Pair{Tuple{Int,Int},NamedTuple}[]
    tasks_without_linking_units = Int[]
    linking_responses_per_task = Int[]
    linking_persons_per_task = Int[]
    if task_present
        tasks_by_rater = [Set{Int}() for _ in data.rater_levels]
        raters_by_task = [Set{Int}() for _ in task_levels]
        responses_by_rater_task = Dict{Tuple{Int,Int},Set{Int}}()
        persons_by_rater_task = Dict{Tuple{Int,Int},Set{Int}}()
        raters_by_task_response = Dict{Tuple{Int,Int},Set{Int}}()
        raters_by_task_person = Dict{Tuple{Int,Int},Set{Int}}()
        for row in 1:data.n
            rater = data.rater[row]
            task = task_index[row]
            response = response_index[row]
            person = data.person[row]
            push!(tasks_by_rater[rater], task)
            push!(raters_by_task[task], rater)
            push!(get!(responses_by_rater_task, (rater, task), Set{Int}()), response)
            push!(get!(persons_by_rater_task, (rater, task), Set{Int}()), person)
            push!(get!(raters_by_task_response, (task, response), Set{Int}()), rater)
            push!(get!(raters_by_task_person, (task, person), Set{Int}()), rater)
        end
        rater_task_components = _testlet_bipartite_components(
            :rater,
            data.rater,
            data.rater_levels,
            :task,
            task_index,
            task_levels,
        )
        person_task_components = _testlet_bipartite_components(
            :person,
            data.person,
            data.person_levels,
            :task,
            task_index,
            task_levels,
        )
        raters_below_task_minimum = findall(set -> length(set) < 2,
            tasks_by_rater)
        tasks_below_rater_minimum = findall(
            set -> length(set) < min_raters_per_task,
            raters_by_task,
        )
        for key in sort(collect(keys(responses_by_rater_task)))
            n_responses = length(responses_by_rater_task[key])
            n_persons = length(get(persons_by_rater_task, key, Set{Int}()))
            if n_responses < min_responses_per_rater_task ||
                    n_persons < min_persons_per_rater_task
                push!(insufficient_rater_task_cells,
                    key => (; n_responses, n_persons))
            end
        end
        linking_responses_per_task = [count(
            pair -> first(first(pair)) == task &&
                length(last(pair)) >= min_raters_per_task,
            raters_by_task_response,
        ) for task in eachindex(task_levels)]
        linking_persons_per_task = [count(
            pair -> first(first(pair)) == task &&
                length(last(pair)) >= min_raters_per_task,
            raters_by_task_person,
        ) for task in eachindex(task_levels)]
        tasks_without_linking_units = findall(eachindex(task_levels)) do task
            linking_responses_per_task[task] == 0 &&
                linking_persons_per_task[task] == 0
        end
        rater_task_eligible = schema_valid && length(ordinary_components) == 1 &&
            length(rater_task_components) == 1 &&
            length(person_task_components) == 1 &&
            isempty(raters_below_task_minimum) &&
            isempty(tasks_below_rater_minimum) &&
            isempty(insufficient_rater_task_cells) &&
            isempty(tasks_without_linking_units)
        rater_task_profile_met = rater_task_eligible
    end
    push!(rows, _testlet_audit_row(;
        check = :rater_task_crossing,
        target = :rater_task,
        status = rater_task_eligible ? :warning : :underidentified,
        severity = rater_task_eligible ? :warning : :error,
        blocking_for = rater_task_eligible ? [:mechanism_attribution] :
            [:rater_task],
        observed = (;
            task_recorded = task_present,
            ordinary_components = length(ordinary_components),
            rater_task_components = length(rater_task_components),
            person_task_components = length(person_task_components),
            raters_below_task_minimum = length(raters_below_task_minimum),
            tasks_below_rater_minimum = length(tasks_below_rater_minimum),
            insufficient_rater_task_cells = length(insufficient_rater_task_cells),
            tasks_without_linking_units = length(tasks_without_linking_units),
        ),
        required = (;
            tasks_per_rater = 2,
            min_raters_per_task,
            min_responses_per_rater_task,
            min_persons_per_rater_task,
            ordinary_components = 1,
            rater_task_components = 1,
            person_task_components = 1,
            linking_response_or_person_per_task = 1,
        ),
        profile = effective_support_profile,
        note = rater_task_eligible ? :rater_task_structure_is_crossed_and_replicated :
            :rater_task_structure_is_nested_or_absent,
        details = (;
            rater_task_components,
            person_task_components,
            insufficient_rater_task_cells = Tuple((;
                rater = data.rater_levels[first(pair)[1]],
                task = task_levels[first(pair)[2]],
                last(pair)...,
            ) for pair in insufficient_rater_task_cells),
            tasks_without_linking_units = Tuple(
                task_levels[index] for index in tasks_without_linking_units),
            linking_responses_per_task = Tuple(linking_responses_per_task),
            linking_persons_per_task = Tuple(linking_persons_per_task),
        ),
    ))

    q_applicable = spec !== nothing && spec.family === :mgmfrm &&
        spec.q_matrix !== nothing
    q_eligible = false
    q_profile_met = false
    q_cluster_base_eligible = false
    q_details = (;)
    if q_applicable
        counts = zeros(Int, length(testlet_levels), spec.dimensions)
        q_items_by_dimension = [Int[] for _ in 1:spec.dimensions]
        for dimension in 1:spec.dimensions, item in eachindex(data.item_levels)
            spec.q_matrix[item, dimension] || continue
            push!(q_items_by_dimension[dimension], item)
            for testlet in item_testlets[item]
                counts[testlet, dimension] += 1
            end
        end
        testlets_per_dimension = [count(>(0), @view counts[:, dimension])
            for dimension in 1:spec.dimensions]
        q_testlet_index = Int[]
        q_dimension_index = Int[]
        for testlet in eachindex(testlet_levels), dimension in 1:spec.dimensions
            counts[testlet, dimension] > 0 || continue
            push!(q_testlet_index, testlet)
            push!(q_dimension_index, dimension)
        end
        q_components = _testlet_bipartite_components(
            :testlet_id,
            q_testlet_index,
            testlet_levels,
            :dimension,
            q_dimension_index,
            collect(1:spec.dimensions),
        )
        dimension_has_within_testlet_contrast = falses(spec.dimensions)
        for dimension in 1:spec.dimensions, testlet in eachindex(testlet_levels)
            0 < counts[testlet, dimension] < length(testlet_items[testlet]) &&
                (dimension_has_within_testlet_contrast[dimension] = true)
        end
        testlets_by_item_signature = Dict{Tuple{Vararg{Int}},Vector{Int}}()
        for testlet in eachindex(testlet_levels)
            signature = Tuple(sort!(collect(testlet_items[testlet])))
            push!(get!(testlets_by_item_signature, signature, Int[]), testlet)
        end
        aligned_dimension_testlet_pairs = NamedTuple[]
        for dimension in 1:spec.dimensions
            signature = Tuple(q_items_by_dimension[dimension])
            for testlet in get(testlets_by_item_signature, signature, Int[])
                push!(aligned_dimension_testlet_pairs,
                    (; dimension, testlet = testlet_levels[testlet]))
            end
        end
        q_cluster_base_eligible = scalar_eligible || stable_eligible
        q_eligible = schema_valid && q_cluster_base_eligible && graphs_connected &&
            isempty(insufficient_persons) && isempty(insufficient_testlets) &&
            isempty(insufficient_responses) &&
            all(>=(min_testlets_per_dimension), testlets_per_dimension) &&
            length(q_components) == 1 &&
            all(dimension_has_within_testlet_contrast) &&
            isempty(aligned_dimension_testlet_pairs)
        q_profile_met = q_eligible && isempty(person_testlet_bridges)
        q_details = (;
            counts,
            testlets_per_dimension,
            q_testlet_graph_components = length(q_components),
            q_components,
            dimension_has_within_testlet_contrast =
                Tuple(dimension_has_within_testlet_contrast),
            aligned_dimension_testlet_pairs =
                Tuple(aligned_dimension_testlet_pairs),
            person_testlet_graph_components = length(person_testlet_components),
            person_testlet_bridge_count = length(person_testlet_bridges),
            persons_below_testlet_minimum = length(insufficient_persons),
            testlets_below_person_minimum = length(insufficient_testlets),
            responses_below_indicator_minimum = length(insufficient_responses),
            cluster_base_eligible = q_cluster_base_eligible,
        )
    end
    push!(rows, _testlet_audit_row(;
        check = :q_by_testlet_support,
        target = :mgmfrm_testlet_separation,
        status = !q_applicable ? :not_applicable :
            q_eligible ? :warning : :underidentified,
        severity = !q_applicable ? :info : q_eligible ? :warning : :error,
        blocking_for = q_applicable && !q_eligible ?
            [:mgmfrm_testlet_separation] : Symbol[],
        observed = q_applicable ? (;
            testlets_per_dimension = q_details.testlets_per_dimension,
            q_testlet_graph_components = q_details.q_testlet_graph_components,
            dimensions_without_within_testlet_contrast = count(!,
                q_details.dimension_has_within_testlet_contrast),
            aligned_dimension_testlet_pairs =
                length(q_details.aligned_dimension_testlet_pairs),
            person_testlet_graph_components =
                q_details.person_testlet_graph_components,
            person_testlet_bridge_count = q_details.person_testlet_bridge_count,
            persons_below_testlet_minimum =
                q_details.persons_below_testlet_minimum,
            testlets_below_person_minimum =
                q_details.testlets_below_person_minimum,
            responses_below_indicator_minimum =
                q_details.responses_below_indicator_minimum,
            cluster_base_eligible = q_details.cluster_base_eligible,
        ) : missing,
        required = q_applicable ? (;
            min_testlets_per_dimension,
            q_testlet_graph_components = 1,
            within_testlet_contrast_for_each_dimension = true,
            aligned_dimension_testlet_pairs = 0,
            person_testlet_graph_components = 1,
            min_testlets_per_person,
            min_persons_per_testlet,
            min_indicators_per_response,
            scalar_or_repeated_response_cluster_base = true,
        ) : missing,
        profile = effective_support_profile,
        note = !q_applicable ? :fixed_q_mgmfrm_not_requested :
            q_eligible ? :q_by_testlet_support_is_connected_and_contrasted :
            :dimension_and_testlet_support_is_confounded,
        details = q_details,
    ))

    single_rating_item_applicable_by_testlet =
        pair_row_preflight.single_rating_item_applicable_by_testlet
    single_rating_item_unit_keys = Any[
        (response_index[row],) for row in 1:data.n
    ]
    within_rater_item_unit_keys = Any[
        (response_index[row], data.rater[row]) for row in 1:data.n
    ]
    rater_response_item_unit_keys = Any[
        (response_index[row], data.item[row]) for row in 1:data.n
    ]
    diagnostic_pair_support = (;
        single_rating_item_q3 = _testlet_stratified_pair_support(
            :item,
            data.item,
            data.item_levels,
            single_rating_item_unit_keys,
            testlet_index,
            testlet_levels,
            min_pair_common_units,
            applicable_by_stratum =
                single_rating_item_applicable_by_testlet,
            inapplicable_reason =
                :multiple_ratings_or_criterion_split_within_response,
        ),
        within_rater_item_q3 = _testlet_stratified_pair_support(
            :item,
            data.item,
            data.item_levels,
            within_rater_item_unit_keys,
            testlet_index,
            testlet_levels,
            min_pair_common_units,
        ),
        rater_on_shared_response_criterion = _testlet_stratified_pair_support(
            :rater,
            data.rater,
            data.rater_levels,
            rater_response_item_unit_keys,
            testlet_index,
            testlet_levels,
            min_pair_common_units,
        ),
    )
    any_diagnostic_pair_family_supported = schema_valid && any(
        family -> family.n_eligible_pairs > 0,
        values(diagnostic_pair_support),
    )
    push!(rows, _testlet_audit_row(;
        check = :diagnostic_pair_support,
        target = :diagnostics,
        status = !schema_valid ? :error :
            any_diagnostic_pair_family_supported ? :ok : :warning,
        severity = !schema_valid ? :error :
            any_diagnostic_pair_family_supported ? :info : :warning,
        observed = Tuple((;
            family = name,
            status = support.status,
            eligible_pairs = support.n_eligible_pairs,
            maximum_common_units = support.maximum_common_units,
        ) for (name, support) in pairs(diagnostic_pair_support)),
        required = (;
            min_pair_common_units,
            duplicate_policy = :error,
            duplicate_policy_scope = :applicable_family_only,
            estimation_strata = :testlet_id,
            eligibility_is_pair_family_specific = true,
        ),
        profile = effective_support_profile,
        note = any_diagnostic_pair_family_supported ?
            :at_least_one_pair_family_has_structural_support :
            :no_pair_family_reaches_the_declared_common_unit_threshold,
        details = diagnostic_pair_support,
    ))

    scalar_profile_met = scalar_eligible &&
        !scalar_weak_indicator_support && !scalar_weak_graph_support &&
        halo_profile_met
    result = _testlet_target_result(target;
        schema_valid,
        profile_is_frozen,
        scalar_identified,
        scalar_scope_supported,
        scalar_eligible,
        scalar_profile_met,
        stable_eligible,
        stable_profile_met,
        halo_eligible,
        halo_profile_met,
        rater_task_eligible,
        rater_task_profile_met,
        q_applicable,
        q_eligible,
        q_profile_met,
    )

    return (;
        schema = "bayesianmgmfrm.testlet_design_audit.v1",
        object = :testlet_design_audit,
        target,
        requested_support_profile = support_profile,
        support_profile = effective_support_profile,
        profile_is_frozen,
        family = spec === nothing ? missing : spec.family,
        dimensions = spec === nothing ? missing : spec.dimensions,
        design_signature = _testlet_design_signature(data),
        computational_support = pair_row_preflight,
        status = result.status,
        status_reason = result.reason,
        schema_valid,
        structural_identification_supported =
            result.structural_identification_supported,
        candidate_scope_supported = result.candidate_scope_supported,
        structurally_eligible_for_candidate =
            result.structurally_eligible_for_candidate,
        structural_profile_met = result.structural_profile_met,
        current_fit_supported = false,
        diagnostic_pair_support,
        any_diagnostic_pair_family_supported,
        mechanism_claim_eligible = false,
        calibration_status = :not_calibrated,
        rows = Tuple(rows),
        summary = (;
            n_responses = length(response_levels),
            n_testlets = length(testlet_levels),
            n_person_testlet_clusters = length(responses_by_person_testlet),
            response_nesting_valid,
            duplicate_rating_keys_valid,
            one_response_per_person_testlet,
            minimum_response_indicators,
            person_testlet_graph_components = length(person_testlet_components),
            person_testlet_bridge_count = length(person_testlet_bridges),
            scalar_shared_cluster_structurally_identified = scalar_identified,
            scalar_shared_cluster_candidate_scope_supported =
                scalar_scope_supported,
            scalar_shared_cluster_structurally_eligible = scalar_eligible,
            stable_person_testlet_structurally_eligible = stable_eligible,
            rater_response_halo_structurally_eligible = halo_eligible,
            independent_ratings_declared,
            rater_task_structurally_eligible = rater_task_eligible,
            mgmfrm_testlet_separation_applicable = q_applicable,
            mgmfrm_testlet_separation_structurally_eligible = q_eligible,
        ),
        thresholds,
        caveat = :design_audit_does_not_establish_a_cluster_effect,
    )
end

"""
    local_dependence_contract(; profile = :ld0_v1,
        min_common_units = 20, min_eligible_draws = 100,
        min_eligible_draw_fraction = 0.9,
        pair_fdr_alpha = 0.05, global_fwer_alpha = 0.05,
        variance_tolerance = 1e-12,
        correlation_variance_tolerance = 1e-12)

Return the machine-readable LD0 diagnostic contract used to develop local-
dependence summaries. The contract distinguishes single-rating item Q3,
within-rater item Q3, and rater-pair estimands; fixes draw-specific support,
duplicate rejection, adjusted-Q3 centering, predictive tail definitions, and
pair weighting; and separates within-family FDR localization from one
all-enabled-family maximum-statistic FWER decision. It deliberately provides
no implicit aggregation over multiple raters or repeated responses.

The named `:ld0_v1` numerical profile is frozen but provisional until calibrated
by independent known-truth simulations. To explore other thresholds, pass
`profile = :custom_unvalidated`; such a result is never decision eligible. This
function does not compute Q3, declare local dependence, fit a testlet effect,
or authorize a mechanism interpretation.
"""
function local_dependence_contract(;
        profile::Symbol = :ld0_v1,
        min_common_units::Int = 20,
        min_eligible_draws::Int = 100,
        min_eligible_draw_fraction::Real = 0.9,
        pair_fdr_alpha::Real = 0.05,
        global_fwer_alpha::Real = 0.05,
        variance_tolerance::Real = 1e-12,
        correlation_variance_tolerance::Real = 1e-12)
    profile in (:ld0_v1, :custom_unvalidated) ||
        throw(ArgumentError(
            "profile must be :ld0_v1 or :custom_unvalidated"))
    _testlet_audit_positive(min_common_units, :min_common_units)
    _testlet_audit_positive(min_eligible_draws, :min_eligible_draws)
    eligible_fraction = Float64(min_eligible_draw_fraction)
    isfinite(eligible_fraction) && 0 < eligible_fraction <= 1 ||
        throw(ArgumentError(
            "min_eligible_draw_fraction must be finite and in (0, 1]"))
    fdr = _testlet_audit_probability(pair_fdr_alpha, :pair_fdr_alpha)
    fwer = _testlet_audit_probability(global_fwer_alpha, :global_fwer_alpha)
    tolerance = Float64(variance_tolerance)
    isfinite(tolerance) && tolerance >= 0 ||
        throw(ArgumentError("variance_tolerance must be finite and nonnegative"))
    correlation_tolerance = Float64(correlation_variance_tolerance)
    isfinite(correlation_tolerance) && correlation_tolerance >= 0 ||
        throw(ArgumentError(
            "correlation_variance_tolerance must be finite and nonnegative"))
    frozen_defaults = min_common_units == 20 && min_eligible_draws == 100 &&
        eligible_fraction == 0.9 && fdr == 0.05 && fwer == 0.05 && tolerance == 1e-12 &&
        correlation_tolerance == 1e-12
    profile === :ld0_v1 && !frozen_defaults &&
        throw(ArgumentError(
            "threshold overrides require profile = :custom_unvalidated"))

    return (;
        schema = "bayesianmgmfrm.local_dependence_contract.v1",
        object = :local_dependence_contract,
        profile,
        status = :calibration_pending,
        calibration_required = true,
        frozen_profile = profile === :ld0_v1,
        decision_labels_available = false,
        mechanism_interpretation_eligible = false,
        residual = (;
            function_name = :predictive_standardized_residuals,
            formula = :draw_specific_observed_minus_expected_over_predictive_sd,
            conditioning = :parameter_draw,
            variance_tolerance = tolerance,
            low_variance_action = :exclude_and_report,
        ),
        pair_families = (
            single_rating_item_q3 = (;
                status = :conditionally_enabled,
                pair_facet = :item,
                common_unit_key = (:response_id,),
                uniqueness_key = (:response_id, :item),
                applicability =
                    :one_rater_per_response_and_one_rating_per_response_item,
                applicability_scope = (:testlet_id,),
                multiple_rater_action = :not_applicable,
                criterion_split_action = :not_applicable,
                inapplicable_action =
                    :skip_inapplicable_testlet_strata_and_report,
                repeated_response_rule = :distinct_response_id_per_occasion,
                estimation_strata = (:testlet_id,),
                reporting_strata = (:testlet_id,),
            ),
            within_rater_item_q3 = (;
                status = :enabled,
                pair_facet = :item,
                common_unit_key = (:response_id, :rater),
                uniqueness_key = (:response_id, :rater, :item),
                applicability = :unique_response_rater_item_rows,
                repeated_response_rule = :distinct_response_id_per_occasion,
                estimation_strata = (:testlet_id,),
                reporting_strata = (:testlet_id,),
            ),
            rater_on_shared_response_criterion = (;
                status = :enabled,
                pair_facet = :rater,
                common_unit_key = (:response_id, :item),
                uniqueness_key = (:response_id, :item, :rater),
                applicability = :unique_response_item_rater_rows,
                common_response_count_reporting = :required,
                single_response_concentration_action =
                    :report_and_block_mechanism_interpretation,
                repeated_response_rule = :distinct_response_id_per_occasion,
                estimation_strata = (:testlet_id,),
                reporting_strata = (:testlet_id,),
            ),
            cross_rater_cross_item_residual_pair = (;
                status = :not_available,
                reason = :requires_prespecified_independent_rater_pairing_and_weighting,
                implicit_pairing = false,
            ),
            aggregated_person_testlet_item_q3 = (;
                status = :not_available,
                reason = :requires_prespecified_rater_aggregation_and_weighting,
                implicit_aggregation = false,
            ),
        ),
        matching = (;
            duplicate_policy = :error,
            duplicate_policy_scope = :applicable_family_only,
            evaluation_order = (
                :family_applicability,
                :family_uniqueness,
                :draw_support,
                :pair_statistic,
            ),
            aggregation = :none,
            min_common_units,
            posterior_draw_policy = :distinct_without_replacement,
            duplicate_draw_indices_action = :error,
            support_by_draw = :count_pairwise_complete_valid_common_units,
            common_unit_weighting = :equal,
            draw_weighting = :equal,
            pairwise_validity = :left_and_right_valid_on_same_draw,
            correlation_requirements = (;
                finite_centered_sums_of_squares = true,
                each_centered_sum_of_squares_above = correlation_tolerance,
            ),
            min_eligible_draw_fraction = eligible_fraction,
            min_eligible_draws,
            pair_summary_action =
                :require_count_and_fraction_of_draws_meeting_support_and_variance_rules,
            sparse_action = :report_without_pair_decision,
        ),
        pair_statistic = (;
            statistic = :pearson_correlation,
            inputs = :draw_specific_standardized_residuals,
            observed_statistic_varies_by_parameter_draw = true,
            replicated_statistic_uses_same_parameter_draw = true,
            undefined_action = :exclude_draw_and_report_reason,
        ),
        adjusted_q3 = (;
            applies_to = (:single_rating_item_q3, :within_rater_item_q3),
            centering =
                :equal_weight_mean_of_eligible_item_pairs_within_family_testlet_and_draw,
            centering_scope = (:pair_family, :testlet_id, :draw),
            eligibility_uses_same_support_rule = true,
            centering_pair_sets =
                :side_specific_overall_supported_pairs,
            minimum_pairs_for_centering = 2,
            undefined_action = :report_without_adjusted_q3,
        ),
        multiplicity = (;
            pair_evidence = (;
                method = :paired_posterior_predictive_tail_fraction,
                discrepancy = :absolute_pair_correlation,
                tail = :two_sided_absolute,
                comparison = :replicated_greater_than_or_equal_to_observed,
                finite_sample_correction = :add_one_to_numerator_and_denominator,
                replicated_datasets_per_parameter_draw = 1,
                draw_set = :draws_where_observed_and_replicated_statistics_are_defined,
                minimum_paired_draws = min_eligible_draws,
                monte_carlo_reporting = (
                    :n_eligible_paired_draws,
                    :tail_fraction_mcse,
                ),
                tail_fraction_mcse =
                    :iid_plugin_bernoulli_reference_standard_error,
            ),
            localization = (;
                method = :benjamini_hochberg_fdr,
                scope = :within_each_enabled_pair_family,
                alpha = fdr,
                input = :paired_posterior_predictive_tail_fraction,
                decision_status = :specified_but_disabled_until_calibrated,
            ),
            dataset_decision = (;
                method = :posterior_predictive_global_max_statistic,
                scope = :all_enabled_families_and_eligible_pairs,
                alpha = fwer,
                statistic = :maximum_absolute_raw_pair_correlation,
                pair_set =
                    :overall_supported_observed_replicated_intersection_by_draw,
                tail = :replicated_greater_than_or_equal_to_observed,
                finite_sample_correction = :add_one_to_numerator_and_denominator,
                overlapping_rows_included = true,
                minimum_paired_draws = min_eligible_draws,
                minimum_paired_draw_fraction = eligible_fraction,
                decision_status = :specified_but_disabled_until_calibrated,
            ),
        ),
        predictive_checks = (;
            conditional_observed_cluster = (;
                estimand = :replicated_rows_conditional_on_parameter_draw,
                observed_and_replicated_statistics_share_draw = true,
            ),
            marginal_whole_cluster = (;
                estimand = :heldout_cluster_with_unseen_effects_integrated,
                row_level_loo_is_sufficient = false,
                availability = :requires_cluster_model_and_cluster_refit,
            ),
        ),
        thresholds = (;
            min_common_units,
            min_eligible_draws,
            min_eligible_draw_fraction = eligible_fraction,
            pair_fdr_alpha = fdr,
            global_fwer_alpha = fwer,
            variance_tolerance = tolerance,
            correlation_variance_tolerance = correlation_tolerance,
        ),
        caveat = :thresholds_are_not_universal_and_require_simulation_calibration,
    )
end
