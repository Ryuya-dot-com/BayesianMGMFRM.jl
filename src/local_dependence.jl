# local_dependence.jl -- report-only LD0b residual-association summaries

const _LOCAL_DEPENDENCE_PAIR_FAMILIES = (
    :single_rating_item_q3,
    :within_rater_item_q3,
    :rater_on_shared_response_criterion,
)

const _LOCAL_DEPENDENCE_DEFAULT_MAX_PAIR_DRAW_CELLS = 2_000_000
const _LOCAL_DEPENDENCE_DEFAULT_MAX_PREDICTION_CELLS = 10_000_000
const _LOCAL_DEPENDENCE_DEFAULT_MAX_AUDIT_PAIR_ROWS =
    _TESTLET_AUDIT_DEFAULT_MAX_MATERIALIZED_PAIR_ROWS
const _LOCAL_DEPENDENCE_DEFAULT_MAX_COMMON_UNIT_DRAW_CELLS = 2_000_000

function _local_dependence_validate_contract(contract)
    contract isa NamedTuple ||
        throw(ArgumentError(
            "contract must be returned by local_dependence_contract"))
    required = (
        :schema,
        :object,
        :profile,
        :status,
        :frozen_profile,
        :decision_labels_available,
        :mechanism_interpretation_eligible,
        :residual,
        :pair_families,
        :matching,
        :pair_statistic,
        :adjusted_q3,
        :multiplicity,
        :thresholds,
    )
    all(name -> hasproperty(contract, name), required) ||
        throw(ArgumentError(
            "contract is not a complete local_dependence_contract result"))
    contract.schema == "bayesianmgmfrm.local_dependence_contract.v1" ||
        throw(ArgumentError("unsupported local-dependence contract schema"))
    contract.object === :local_dependence_contract ||
        throw(ArgumentError("invalid local-dependence contract object"))
    threshold_names = (
        :min_common_units,
        :min_eligible_draws,
        :min_eligible_draw_fraction,
        :pair_fdr_alpha,
        :global_fwer_alpha,
        :variance_tolerance,
        :correlation_variance_tolerance,
    )
    contract.thresholds isa NamedTuple &&
        all(name -> hasproperty(contract.thresholds, name), threshold_names) ||
        throw(ArgumentError(
            "contract is missing local-dependence threshold fields"))
    canonical = local_dependence_contract(
        profile = contract.profile,
        min_common_units = contract.thresholds.min_common_units,
        min_eligible_draws = contract.thresholds.min_eligible_draws,
        min_eligible_draw_fraction =
            contract.thresholds.min_eligible_draw_fraction,
        pair_fdr_alpha = contract.thresholds.pair_fdr_alpha,
        global_fwer_alpha = contract.thresholds.global_fwer_alpha,
        variance_tolerance = contract.thresholds.variance_tolerance,
        correlation_variance_tolerance =
            contract.thresholds.correlation_variance_tolerance,
    )
    isequal(contract, canonical) ||
        throw(ArgumentError(
            "contract must be an unmodified local_dependence_contract result"))
    contract.status === :calibration_pending ||
        throw(ArgumentError("local-dependence contract must remain calibration pending"))
    contract.decision_labels_available === false ||
        throw(ArgumentError("decision-enabled local-dependence contracts are unsupported"))
    contract.mechanism_interpretation_eligible === false ||
        throw(ArgumentError("mechanism-enabled local-dependence contracts are unsupported"))
    contract.residual.function_name === :predictive_standardized_residuals ||
        throw(ArgumentError("unsupported residual definition in contract"))
    contract.matching.duplicate_policy === :error ||
        throw(ArgumentError("local-dependence duplicate policy must be :error"))
    contract.matching.aggregation === :none ||
        throw(ArgumentError("implicit residual aggregation is unsupported"))
    contract.matching.posterior_draw_policy === :distinct_without_replacement ||
        throw(ArgumentError(
            "local-dependence posterior draws must be distinct and sampled without replacement"))
    contract.matching.duplicate_draw_indices_action === :error ||
        throw(ArgumentError("duplicate posterior draw indices must be rejected"))
    contract.pair_statistic.statistic === :pearson_correlation ||
        throw(ArgumentError("unsupported local-dependence pair statistic"))
    contract.multiplicity.pair_evidence.replicated_datasets_per_parameter_draw == 1 ||
        throw(ArgumentError(
            "local_dependence_summary supports one replicated dataset per parameter draw"))
    for family in _LOCAL_DEPENDENCE_PAIR_FAMILIES
        hasproperty(contract.pair_families, family) ||
            throw(ArgumentError("contract is missing pair family :$family"))
    end
    return contract
end

function _local_dependence_draw_indices(
        fit,
        ndraws::Union{Nothing,Int},
        draw_indices,
        rng::AbstractRNG)
    draw_indices !== nothing && ndraws !== nothing &&
        throw(ArgumentError("pass either ndraws or draw_indices, not both"))
    total = size(fit.draws, 1)
    total >= 1 ||
        throw(ArgumentError("local_dependence_summary requires posterior draws"))
    if draw_indices !== nothing
        indices = collect(Int, draw_indices)
        isempty(indices) &&
            throw(ArgumentError("draw_indices must not be empty"))
        all(index -> 1 <= index <= total, indices) ||
            throw(ArgumentError("draw_indices are out of bounds"))
        length(unique(indices)) == length(indices) ||
            throw(ArgumentError(
                "draw_indices must be distinct for local_dependence_summary"))
        return indices
    end
    ndraws === nothing && return collect(1:total)
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    ndraws <= total ||
        throw(ArgumentError(
            "ndraws cannot exceed the number of distinct posterior draws"))
    return randperm(rng, total)[1:ndraws]
end

function _local_dependence_predictive_probabilities(
        fit::MFRMFit,
        indices::AbstractVector{Int})
    return predictive_probabilities(fit.design, @view(fit.draws[indices, :]))
end

function _local_dependence_predictive_probabilities(
        fit::GMFRMFit,
        indices::AbstractVector{Int})
    return _gmfrm_predictive_probabilities_direct(
        fit.design,
        @view(fit.direct_draws[indices, :]),
    )
end

function _local_dependence_predictive_probabilities(
        fit::MGMFRMFit,
        indices::AbstractVector{Int})
    return _mgmfrm_predictive_probabilities_direct(
        fit.design,
        @view(fit.direct_draws[indices, :]),
    )
end

function _local_dependence_sample_replicated_scores(
        data::FacetData,
        probabilities::AbstractArray{<:Real,3},
        levels::AbstractVector{Int},
        rng::AbstractRNG)
    replicated = Matrix{Int}(undef, size(probabilities, 1), size(probabilities, 2))
    probs = zeros(Float64, length(levels))
    response = data.optional[:response_id]
    response_levels = data.optional_levels[:response_id]
    canonical_rows = sort(collect(1:data.n); by = row -> (
        repr(response_levels[response[row]]),
        repr(data.rater_levels[data.rater[row]]),
        repr(data.item_levels[data.item[row]]),
    ))
    for draw in axes(probabilities, 1), row in canonical_rows
        for category in eachindex(levels)
            probs[category] = Float64(probabilities[draw, row, category])
        end
        all(isfinite, probs) ||
            throw(ArgumentError(
                "predictive probabilities contain non-finite values"))
        category = _sample_category_index(rng, probs)
        replicated[draw, row] = levels[category]
    end
    return replicated
end

function _local_dependence_validate_replicated_scores(
        replicated_scores,
        n_draws::Int,
        data::FacetData)
    replicated_scores isa AbstractMatrix ||
        throw(ArgumentError("replicated_scores must be a draws-by-observations matrix"))
    size(replicated_scores) == (n_draws, data.n) ||
        throw(ArgumentError(
            "replicated_scores must have size ($n_draws, $(data.n))"))
    allowed = Set(data.category_levels)
    checked = Matrix{Int}(undef, n_draws, data.n)
    for draw in 1:n_draws, row in 1:data.n
        score = _score_to_int(replicated_scores[draw, row], :replicated_scores)
        score in allowed ||
            throw(ArgumentError(
                "replicated_scores contains score $score outside the fitted category scale"))
        checked[draw, row] = score
    end
    return checked
end

function _local_dependence_standardized_residual_pair(
        data::FacetData,
        probabilities::AbstractArray{<:Real,3},
        replicated_scores::AbstractMatrix{<:Integer},
        variance_tolerance::Real)
    tolerance = Float64(variance_tolerance)
    isfinite(tolerance) && tolerance >= 0 ||
        throw(ArgumentError(
            "variance_tolerance must be finite and nonnegative"))
    observed_values = fill(NaN, size(probabilities, 1), size(probabilities, 2))
    replicated_values = fill(NaN, size(probabilities, 1), size(probabilities, 2))
    valid = falses(size(observed_values))
    for draw in axes(probabilities, 1), row in axes(probabilities, 2)
        expected = 0.0
        for category in eachindex(data.category_levels)
            probability = Float64(probabilities[draw, row, category])
            isfinite(probability) ||
                throw(ArgumentError(
                    "predictive probabilities contain non-finite values"))
            score = Float64(data.category_levels[category])
            expected += score * probability
        end
        second_moment = 0.0
        for category in eachindex(data.category_levels)
            score = Float64(data.category_levels[category])
            second_moment += (score * score) *
                Float64(probabilities[draw, row, category])
        end
        variance = max(second_moment - expected * expected, 0.0)
        isfinite(expected) && isfinite(variance) ||
            throw(ArgumentError(
                "predictive moments contain non-finite values"))
        if variance > tolerance
            scale = sqrt(variance)
            observed_value = (Float64(data.score[row]) - expected) / scale
            replicated_value =
                (Float64(replicated_scores[draw, row]) - expected) / scale
            isfinite(observed_value) && isfinite(replicated_value) ||
                throw(ArgumentError(
                    "standardized residual is non-finite at draw $draw, observation $row"))
            observed_values[draw, row] = observed_value
            replicated_values[draw, row] = replicated_value
            valid[draw, row] = true
        end
    end
    n_valid = count(valid)
    n_excluded = length(valid) - n_valid
    return (;
        observed = (;
            values = observed_values,
            valid,
            n_valid,
            n_excluded,
        ),
        replicated = (;
            values = replicated_values,
            valid,
            n_valid,
            n_excluded,
        ),
    )
end

function _local_dependence_observed_score_signature(data::FacetData)
    records = Tuple[]
    response = data.optional[:response_id]
    response_levels = data.optional_levels[:response_id]
    testlet = data.optional[:testlet_id]
    testlet_levels = data.optional_levels[:testlet_id]
    for row in 1:data.n
        push!(records, (
            repr(data.person_levels[data.person[row]]),
            repr(data.rater_levels[data.rater[row]]),
            repr(data.item_levels[data.item[row]]),
            repr(response_levels[response[row]]),
            repr(testlet_levels[testlet[row]]),
            data.score[row],
        ))
    end
    sort!(records; by = repr)
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(codeunits(repr(Tuple(records))))),
    )
end

function _local_dependence_family_arrays(data::FacetData, family::Symbol)
    response = data.optional[:response_id]
    if family === :single_rating_item_q3
        return (;
            pair_facet = :item,
            facet_index = data.item,
            facet_levels = data.item_levels,
            unit_keys = Any[(response[row],) for row in 1:data.n],
            common_unit_key = (:response_id,),
        )
    elseif family === :within_rater_item_q3
        return (;
            pair_facet = :item,
            facet_index = data.item,
            facet_levels = data.item_levels,
            unit_keys = Any[(response[row], data.rater[row]) for row in 1:data.n],
            common_unit_key = (:response_id, :rater),
        )
    elseif family === :rater_on_shared_response_criterion
        return (;
            pair_facet = :rater,
            facet_index = data.rater,
            facet_levels = data.rater_levels,
            unit_keys = Any[(response[row], data.item[row]) for row in 1:data.n],
            common_unit_key = (:response_id, :item),
        )
    end
    throw(ArgumentError("unsupported local-dependence pair family :$family"))
end

function _local_dependence_pair_matches(
        data::FacetData,
        family::Symbol,
        arrays)
    testlet = data.optional[:testlet_id]
    rows_by_unit = Dict{Tuple{Int,Any},Dict{Int,Int}}()
    for row in 1:data.n
        unit = arrays.unit_keys[row]
        key = (testlet[row], unit)
        facet_rows = get!(rows_by_unit, key, Dict{Int,Int}())
        facet = arrays.facet_index[row]
        haskey(facet_rows, facet) &&
            throw(ArgumentError(
                "duplicate common-unit/facet row in applicable family :$family"))
        facet_rows[facet] = row
    end
    matches = Dict{Tuple{Int,Int,Int},Vector{NamedTuple}}()
    for ((stratum, unit), facet_rows) in rows_by_unit
        facets = sort(collect(keys(facet_rows)))
        length(facets) >= 2 || continue
        for left_position in 1:(length(facets) - 1),
                right_position in (left_position + 1):length(facets)
            left = facets[left_position]
            right = facets[right_position]
            push!(get!(matches, (stratum, left, right), NamedTuple[]), (;
                unit,
                left_row = facet_rows[left],
                right_row = facet_rows[right],
            ))
        end
    end
    for rows in values(matches)
        sort!(rows; by = row -> repr(row.unit))
    end
    return matches
end

function _local_dependence_pair_correlation(
        values::AbstractMatrix{<:Real},
        valid::AbstractMatrix{Bool},
        draw::Int,
        left_rows::AbstractVector{Int},
        right_rows::AbstractVector{Int},
        min_common_units::Int,
        variance_tolerance::Float64)
    n = 0
    mean_left = 0.0
    mean_right = 0.0
    centered_left = 0.0
    centered_right = 0.0
    centered_cross = 0.0
    for index in eachindex(left_rows)
        left = left_rows[index]
        right = right_rows[index]
        valid[draw, left] && valid[draw, right] || continue
        x = Float64(values[draw, left])
        y = Float64(values[draw, right])
        isfinite(x) && isfinite(y) ||
            throw(ArgumentError(
                "valid standardized residuals must be finite"))
        n += 1
        delta_left = x - mean_left
        mean_left += delta_left / n
        delta_right = y - mean_right
        mean_right += delta_right / n
        centered_left += delta_left * (x - mean_left)
        centered_right += delta_right * (y - mean_right)
        centered_cross += delta_left * (y - mean_right)
    end
    n >= min_common_units ||
        return (; value = NaN, n_common = n, reason = :insufficient_common_units)
    isfinite(centered_left) && isfinite(centered_right) ||
        throw(ArgumentError("centered residual sums of squares are non-finite"))
    centered_left > variance_tolerance && centered_right > variance_tolerance ||
        return (; value = NaN, n_common = n, reason = :negligible_centered_variance)
    value = centered_cross / sqrt(centered_left * centered_right)
    isfinite(value) ||
        throw(ArgumentError("pair residual correlation is non-finite"))
    abs(value) <= 1 + 1e-12 ||
        throw(ArgumentError(
            "pair residual correlation exceeds its numerical range"))
    return (;
        value = clamp(value, -1.0, 1.0),
        n_common = n,
        reason = :defined,
    )
end

_local_dependence_report_value(value::Real) =
    isfinite(value) ? Float64(value) : missing

function _local_dependence_distribution_summary(
        values::AbstractVector{<:Real},
        lower::Float64,
        upper::Float64)
    finite = [Float64(value) for value in values if isfinite(value)]
    isempty(finite) && return (;
        n_defined = 0,
        mean = missing,
        sd = missing,
        median = missing,
        lower = missing,
        upper = missing,
    )
    summary = _finite_draw_summary(finite, lower, upper)
    sd = if length(finite) < 2
        missing
    else
        center = summary.mean
        sqrt(sum((value - center)^2 for value in finite) / (length(finite) - 1))
    end
    return (;
        n_defined = length(finite),
        mean = summary.mean,
        sd,
        median = summary.median,
        lower = summary.lower,
        upper = summary.upper,
    )
end

function _local_dependence_reason_counts(reasons::AbstractVector{Symbol})
    return (;
        defined = count(reason -> reason === :defined, reasons),
        insufficient_common_units =
            count(reason -> reason === :insufficient_common_units, reasons),
        negligible_centered_variance =
            count(reason -> reason === :negligible_centered_variance, reasons),
    )
end

function _local_dependence_tail_evidence(
        observed::AbstractVector{<:Real},
        replicated::AbstractVector{<:Real},
        min_draws::Int,
        min_fraction::Float64)
    length(observed) == length(replicated) ||
        throw(ArgumentError("paired discrepancy vectors must have equal length"))
    paired = [index for index in eachindex(observed)
        if isfinite(observed[index]) && isfinite(replicated[index])]
    n_total = length(observed)
    n_paired = length(paired)
    fraction = n_total == 0 ? 0.0 : n_paired / n_total
    exceedances = count(index ->
        abs(Float64(replicated[index])) >= abs(Float64(observed[index])), paired)
    support_met = n_paired >= min_draws && fraction >= min_fraction
    corrected = support_met ? (exceedances + 1) / (n_paired + 1) : missing
    raw_fraction = n_paired == 0 ? missing : exceedances / n_paired
    mcse = if support_met
        raw = exceedances / n_paired
        sqrt(raw * (1 - raw) / n_paired)
    else
        missing
    end
    reason = n_paired < min_draws ? :insufficient_eligible_draws :
        fraction < min_fraction ? :insufficient_eligible_draw_fraction :
        :report_only
    return (;
        n_paired,
        paired_fraction = fraction,
        exceedances,
        raw_tail_fraction = raw_fraction,
        corrected_tail_fraction = corrected,
        tail_fraction_mcse = mcse,
        tail_fraction_mcse_method =
            :iid_plugin_bernoulli_reference_standard_error,
        mcmc_autocorrelation_adjusted = false,
        support_met,
        reason,
    )
end

function _local_dependence_bh_adjust(values::Vector{Tuple{Int,Float64}})
    isempty(values) && return Dict{Int,NamedTuple}()
    ordered = sort(values; by = value -> (last(value), first(value)))
    m = length(ordered)
    adjusted = fill(1.0, m)
    running = 1.0
    for position in m:-1:1
        candidate = ordered[position][2] * m / position
        running = min(running, candidate, 1.0)
        adjusted[position] = running
    end
    return Dict(
        ordered[position][1] => (;
            adjusted = adjusted[position],
            rank = position,
            family_size = m,
        ) for position in 1:m
    )
end

function _local_dependence_adjusted_q3!(records, n_draws::Int)
    groups = Dict{Tuple{Symbol,Int},Vector{Int}}()
    for (index, record) in pairs(records)
        record.family in (:single_rating_item_q3, :within_rater_item_q3) ||
            continue
        push!(get!(groups, (record.family, record.testlet_index), Int[]), index)
    end
    for indices in values(groups), draw in 1:n_draws
        observed_indices = [index for index in indices
            if records[index].observed_support_met &&
                isfinite(records[index].observed[draw])]
        if length(observed_indices) >= 2
            center = sum(records[index].observed[draw]
                for index in observed_indices) / length(observed_indices)
            for index in observed_indices
                records[index].observed_adjusted[draw] =
                    records[index].observed[draw] - center
            end
        end
        replicated_indices = [index for index in indices
            if records[index].replicated_support_met &&
                isfinite(records[index].replicated[draw])]
        if length(replicated_indices) >= 2
            center = sum(records[index].replicated[draw]
                for index in replicated_indices) / length(replicated_indices)
            for index in replicated_indices
                records[index].replicated_adjusted[draw] =
                    records[index].replicated[draw] - center
            end
        end
    end
    return records
end

function _local_dependence_maximum_evidence(
        records,
        record_indices::AbstractVector{Int},
        n_draws::Int,
        min_draws::Int,
        min_fraction::Float64;
        scope::Symbol,
        lower::Float64 = 0.025,
        upper::Float64 = 0.975)
    observed = fill(NaN, n_draws)
    replicated = fill(NaN, n_draws)
    pair_counts = zeros(Int, n_draws)
    supported = [index for index in record_indices
        if records[index].summary_support_met]
    for draw in 1:n_draws
        eligible = [index for index in supported
            if isfinite(records[index].observed[draw]) &&
                isfinite(records[index].replicated[draw])]
        isempty(eligible) && continue
        pair_counts[draw] = length(eligible)
        observed[draw] = maximum(
            abs(records[index].observed[draw]) for index in eligible)
        replicated[draw] = maximum(
            abs(records[index].replicated[draw]) for index in eligible)
    end
    evidence = _local_dependence_tail_evidence(
        observed,
        replicated,
        min_draws,
        min_fraction,
    )
    support_status = isempty(supported) ?
        (scope === :within_pair_family ?
            :no_eligible_pairs : :no_overall_supported_pairs) :
        evidence.reason
    positive_counts = pair_counts[pair_counts .> 0]
    return (;
        schema = "bayesianmgmfrm.local_dependence_maximum_evidence.v1",
        scope,
        statistic = :maximum_absolute_raw_pair_correlation,
        pair_set = :overall_supported_observed_replicated_intersection_by_draw,
        n_overall_supported_pairs = length(supported),
        n_draws_with_nonempty_pair_set = count(>(0), pair_counts),
        minimum_pairs_per_defined_draw =
            isempty(positive_counts) ? missing : minimum(positive_counts),
        maximum_pairs_per_defined_draw =
            isempty(positive_counts) ? missing : maximum(positive_counts),
        observed = _local_dependence_distribution_summary(observed, lower, upper),
        replicated =
            _local_dependence_distribution_summary(replicated, lower, upper),
        posterior_predictive_tail_fraction = evidence.corrected_tail_fraction,
        raw_tail_fraction = evidence.raw_tail_fraction,
        tail_exceedances = evidence.exceedances,
        n_eligible_paired_draws = evidence.n_paired,
        eligible_paired_draw_fraction = evidence.paired_fraction,
        tail_fraction_mcse = evidence.tail_fraction_mcse,
        tail_fraction_mcse_method = evidence.tail_fraction_mcse_method,
        mcmc_autocorrelation_adjusted = false,
        support_status,
        decision_available = false,
        decision_status = :specified_but_disabled_until_calibrated,
    )
end

function _local_dependence_graph_components(levels, edges)
    index = Dict{Any,Int}(level => position for (position, level) in pairs(levels))
    adjacency = [Set{Int}() for _ in levels]
    for (left, right) in edges
        a = index[left]
        b = index[right]
        push!(adjacency[a], b)
        push!(adjacency[b], a)
    end
    seen = Set{Int}()
    components = Tuple[]
    for start in eachindex(levels)
        start in seen && continue
        queue = [start]
        head = 1
        push!(seen, start)
        component = Int[]
        while head <= length(queue)
            current = queue[head]
            head += 1
            push!(component, current)
            for neighbor in sort(collect(adjacency[current]))
                neighbor in seen && continue
                push!(seen, neighbor)
                push!(queue, neighbor)
            end
        end
        push!(components, Tuple(levels[position]
            for position in sort(component)))
    end
    isolated = Tuple(levels[index] for index in eachindex(levels)
        if isempty(adjacency[index]))
    return (;
        n_components = length(components),
        components = Tuple(components),
        isolated_levels = isolated,
    )
end

function _local_dependence_pair_records(
        data::FacetData,
        audit,
        observed,
        replicated,
        contract)
    testlet_index = data.optional[:testlet_id]
    testlet_levels = data.optional_levels[:testlet_id]
    testlet_by_level = Dict{Any,Int}(
        level => index for (index, level) in pairs(testlet_levels))
    n_draws = size(observed.values, 1)
    min_common = contract.thresholds.min_common_units
    min_draws = contract.thresholds.min_eligible_draws
    min_fraction = Float64(contract.thresholds.min_eligible_draw_fraction)
    correlation_tolerance =
        Float64(contract.thresholds.correlation_variance_tolerance)
    records = NamedTuple[]

    for family in _LOCAL_DEPENDENCE_PAIR_FAMILIES
        support = getproperty(audit.diagnostic_pair_support, family)
        support.status === :not_applicable && continue
        support.status === :invalid_duplicate &&
            throw(ArgumentError(
                "duplicate matching keys in applicable pair family :$family"))
        arrays = _local_dependence_family_arrays(data, family)
        facet_by_level = Dict{Any,Int}(
            level => index for (index, level) in pairs(arrays.facet_levels))
        pair_matches = _local_dependence_pair_matches(data, family, arrays)
        for pair in support.pairs
            pair.common_units == 0 && continue
            testlet = testlet_by_level[pair.testlet_id]
            left_facet = facet_by_level[pair.left]
            right_facet = facet_by_level[pair.right]
            matches = get(pair_matches,
                (testlet, left_facet, right_facet), NamedTuple[])
            length(matches) == pair.common_units ||
                throw(ArgumentError(
                    "pair-support audit and residual matching disagree for family :$family"))
            common_units = Any[match.unit for match in matches]
            left_rows = Int[match.left_row for match in matches]
            right_rows = Int[match.right_row for match in matches]
            common_responses = unique(Int[first(unit) for unit in common_units])
            observed_values = fill(NaN, n_draws)
            replicated_values = fill(NaN, n_draws)
            valid_common = zeros(Int, n_draws)
            observed_reasons = fill(:insufficient_common_units, n_draws)
            replicated_reasons = fill(:insufficient_common_units, n_draws)
            for draw in 1:n_draws
                observed_result = _local_dependence_pair_correlation(
                    observed.values,
                    observed.valid,
                    draw,
                    left_rows,
                    right_rows,
                    min_common,
                    correlation_tolerance,
                )
                replicated_result = _local_dependence_pair_correlation(
                    replicated.values,
                    replicated.valid,
                    draw,
                    left_rows,
                    right_rows,
                    min_common,
                    correlation_tolerance,
                )
                observed_values[draw] = observed_result.value
                replicated_values[draw] = replicated_result.value
                observed_result.n_common == replicated_result.n_common ||
                    throw(ArgumentError(
                        "observed and replicated residual validity masks disagree"))
                valid_common[draw] = observed_result.n_common
                observed_reasons[draw] = observed_result.reason
                replicated_reasons[draw] = replicated_result.reason
            end
            evidence = _local_dependence_tail_evidence(
                observed_values,
                replicated_values,
                min_draws,
                min_fraction,
            )
            structural_support_met = length(common_units) >= min_common
            n_observed_defined = count(isfinite, observed_values)
            n_replicated_defined = count(isfinite, replicated_values)
            observed_defined_fraction = n_observed_defined / n_draws
            replicated_defined_fraction = n_replicated_defined / n_draws
            observed_support_met = structural_support_met &&
                n_observed_defined >= min_draws &&
                observed_defined_fraction >= min_fraction
            replicated_support_met = structural_support_met &&
                n_replicated_defined >= min_draws &&
                replicated_defined_fraction >= min_fraction
            summary_support_met = structural_support_met && evidence.support_met
            support_status = !structural_support_met ? :sparse :
                summary_support_met ? :eligible_report_only :
                count(isfinite, observed_values) == 0 ||
                    count(isfinite, replicated_values) == 0 ?
                    :undefined_residual_variation : :insufficient_draw_support
            support_reason = !structural_support_met ?
                :insufficient_common_units : evidence.reason
            common_response_support = isempty(common_responses) ?
                :no_common_response : length(common_responses) == 1 ?
                :single_response : :multiple_responses
            rater_single_response_concentration =
                family === :rater_on_shared_response_criterion &&
                length(common_responses) == 1
            push!(records, (;
                pair_id = length(records) + 1,
                family,
                testlet_index = testlet,
                testlet_id = pair.testlet_id,
                pair_facet = arrays.pair_facet,
                left = pair.left,
                right = pair.right,
                common_unit_key = arrays.common_unit_key,
                structural_common_units = length(common_units),
                n_common_responses = length(common_responses),
                common_response_support,
                rater_single_response_concentration,
                observed = observed_values,
                replicated = replicated_values,
                observed_adjusted = family in
                    (:single_rating_item_q3, :within_rater_item_q3) ?
                    fill(NaN, n_draws) : Float64[],
                replicated_adjusted = family in
                    (:single_rating_item_q3, :within_rater_item_q3) ?
                    fill(NaN, n_draws) : Float64[],
                valid_common,
                observed_reason_counts =
                    _local_dependence_reason_counts(observed_reasons),
                replicated_reason_counts =
                    _local_dependence_reason_counts(replicated_reasons),
                evidence,
                structural_support_met,
                observed_support_met,
                replicated_support_met,
                observed_defined_fraction,
                replicated_defined_fraction,
                summary_support_met,
                support_status,
                support_reason,
            ))
        end
    end
    _local_dependence_adjusted_q3!(records, n_draws)
    return records
end

function _local_dependence_count_summary(values::AbstractVector{Int})
    isempty(values) && return (minimum = missing, median = missing, maximum = missing)
    sorted = sort(collect(values))
    return (;
        minimum = minimum(values),
        median = _quantile_sorted(Float64.(sorted), 0.5),
        maximum = maximum(values),
    )
end

function _local_dependence_pair_rows(
        records,
        contract,
        lower::Float64,
        upper::Float64,
        interval::Float64,
        audit)
    bh_by_pair = Dict{Int,NamedTuple}()
    for family in _LOCAL_DEPENDENCE_PAIR_FAMILIES
        inputs = Tuple{Int,Float64}[]
        for record in records
            record.family === family || continue
            tail = record.evidence.corrected_tail_fraction
            ismissing(tail) || push!(inputs, (record.pair_id, Float64(tail)))
        end
        merge!(bh_by_pair, _local_dependence_bh_adjust(inputs))
    end
    rows = NamedTuple[]
    for record in records
        raw_difference = [
            isfinite(record.observed[draw]) && isfinite(record.replicated[draw]) ?
                record.replicated[draw] - record.observed[draw] : NaN
            for draw in eachindex(record.observed)
        ]
        bh = get(bh_by_pair, record.pair_id, nothing)
        item_family = record.family in
            (:single_rating_item_q3, :within_rater_item_q3)
        adjusted_difference = item_family ? [
            isfinite(record.observed_adjusted[draw]) &&
                isfinite(record.replicated_adjusted[draw]) ?
                record.replicated_adjusted[draw] -
                    record.observed_adjusted[draw] : NaN
            for draw in eachindex(record.observed_adjusted)
        ] : Float64[]
        push!(rows, (;
            schema = "bayesianmgmfrm.local_dependence_pair_row.v1",
            pair_id = record.pair_id,
            family = record.family,
            testlet_id = record.testlet_id,
            pair_facet = record.pair_facet,
            left = record.left,
            right = record.right,
            common_unit_key = record.common_unit_key,
            status = record.support_status,
            status_reason = record.support_reason,
            n_structural_common_units = record.structural_common_units,
            n_common_responses = record.n_common_responses,
            common_response_support = record.common_response_support,
            rater_single_response_concentration =
                record.rater_single_response_concentration,
            valid_common_units_by_draw =
                _local_dependence_count_summary(record.valid_common),
            n_total_draws = length(record.observed),
            n_support_draws = count(draw ->
                record.valid_common[draw] >=
                    contract.thresholds.min_common_units,
                eachindex(record.observed),
            ),
            n_observed_defined_draws = count(isfinite, record.observed),
            n_replicated_defined_draws = count(isfinite, record.replicated),
            observed_defined_draw_fraction =
                record.observed_defined_fraction,
            replicated_defined_draw_fraction =
                record.replicated_defined_fraction,
            observed_summary_support_met = record.observed_support_met,
            replicated_summary_support_met = record.replicated_support_met,
            n_eligible_paired_draws = record.evidence.n_paired,
            eligible_paired_draw_fraction = record.evidence.paired_fraction,
            interval_probability = interval,
            observed_correlation = _local_dependence_distribution_summary(
                record.observed,
                lower,
                upper,
            ),
            replicated_correlation = _local_dependence_distribution_summary(
                record.replicated,
                lower,
                upper,
            ),
            replicated_minus_observed =
                _local_dependence_distribution_summary(
                    raw_difference,
                    lower,
                    upper,
                ),
            observed_adjusted_q3 = item_family ?
                _local_dependence_distribution_summary(
                    record.observed_adjusted,
                    lower,
                    upper,
                ) : missing,
            replicated_adjusted_q3 = item_family ?
                _local_dependence_distribution_summary(
                    record.replicated_adjusted,
                    lower,
                    upper,
                ) : missing,
            replicated_minus_observed_adjusted_q3 = item_family ?
                _local_dependence_distribution_summary(
                    adjusted_difference,
                    lower,
                    upper,
                ) : missing,
            posterior_predictive_tail_fraction =
                record.evidence.corrected_tail_fraction,
            raw_tail_fraction = record.evidence.raw_tail_fraction,
            tail_exceedances = record.evidence.exceedances,
            tail_fraction_mcse = record.evidence.tail_fraction_mcse,
            tail_fraction_mcse_method =
                record.evidence.tail_fraction_mcse_method,
            mcmc_autocorrelation_adjusted = false,
            bh_adjusted_tail_fraction = bh === nothing ? missing : bh.adjusted,
            bh_rank = bh === nothing ? missing : bh.rank,
            bh_family_size = bh === nothing ? missing : bh.family_size,
            observed_exclusions = record.observed_reason_counts,
            replicated_exclusions = record.replicated_reason_counts,
            rater_response_halo_global_structural_eligibility =
                record.family === :rater_on_shared_response_criterion ?
                    audit.summary.rater_response_halo_structurally_eligible :
                    missing,
            decision = missing,
            decision_available = false,
            decision_status = :specified_but_disabled_until_calibrated,
            local_dependence_detected = missing,
            mechanism_label = missing,
            mechanism_interpretation_eligible = false,
        ))
    end
    return Tuple(rows)
end

function _local_dependence_family_support_rows(
        data::FacetData,
        audit,
        records,
        contract)
    testlet_index = data.optional[:testlet_id]
    testlet_levels = data.optional_levels[:testlet_id]
    rows = NamedTuple[]
    families = NamedTuple[]
    for family in _LOCAL_DEPENDENCE_PAIR_FAMILIES
        support = getproperty(audit.diagnostic_pair_support, family)
        family_records = [record for record in records if record.family === family]
        arrays = _local_dependence_family_arrays(data, family)
        for testlet in eachindex(testlet_levels)
            testlet_id = testlet_levels[testlet]
            stratum_index = findfirst(stratum ->
                stratum.testlet_id == testlet_id,
                support.strata,
            )
            stratum_index === nothing &&
                throw(ArgumentError(
                    "pair-support audit is missing testlet stratum $(repr(testlet_id))"))
            stratum_support = support.strata[stratum_index]
            testlet_status = stratum_support.status
            testlet_inapplicable_reason =
                stratum_support.inapplicable_reason
            testlet_status_reason = if testlet_status === :eligible
                :pair_meets_minimum_common_units
            elseif testlet_status === :sparse
                :no_pair_meets_minimum_common_units
            elseif testlet_status === :not_applicable
                ismissing(testlet_inapplicable_reason) ?
                    :fewer_than_two_observed_facet_levels :
                    testlet_inapplicable_reason
            else
                :invalid_duplicate_common_unit_facet_rows
            end
            observed_facets = sort(unique(arrays.facet_index[
                testlet_index .== testlet]))
            levels = Any[arrays.facet_levels[index] for index in observed_facets]
            structural_pairs = [pair for pair in support.pairs
                if pair.testlet_id == testlet_levels[testlet]]
            observed_edges = Tuple{Any,Any}[(pair.left, pair.right)
                for pair in structural_pairs if pair.common_units > 0]
            threshold_edges = Tuple{Any,Any}[(pair.left, pair.right)
                for pair in structural_pairs if pair.eligible]
            summary_edges = Tuple{Any,Any}[(record.left, record.right)
                for record in family_records
                if record.testlet_index == testlet && record.summary_support_met]
            push!(rows, (;
                schema =
                    "bayesianmgmfrm.local_dependence_family_testlet_support.v1",
                family,
                testlet_id,
                pair_facet = arrays.pair_facet,
                family_status = support.status,
                inapplicable_reason = support.inapplicable_reason,
                testlet_status,
                testlet_status_reason,
                testlet_inapplicable_reason,
                n_observed_facet_levels = length(levels),
                observed_facet_levels = Tuple(levels),
                n_observed_pairs = count(pair -> pair.common_units > 0,
                    structural_pairs),
                n_structural_threshold_pairs = count(pair -> pair.eligible,
                    structural_pairs),
                n_summary_supported_pairs = count(record ->
                    record.testlet_index == testlet && record.summary_support_met,
                    family_records),
                observed_common_unit_graph =
                    _local_dependence_graph_components(levels, observed_edges),
                structural_threshold_graph =
                    _local_dependence_graph_components(levels, threshold_edges),
                summary_supported_graph =
                    _local_dependence_graph_components(levels, summary_edges),
                graph_interpretation = :descriptive_support_only,
                mechanism_interpretation_eligible = false,
            ))
        end
        push!(families, (;
            schema = "bayesianmgmfrm.local_dependence_family_summary.v1",
            family,
            status = support.status,
            inapplicable_reason = support.inapplicable_reason,
            n_testlets = length(testlet_levels),
            n_applicable_testlets = support.n_applicable_strata,
            n_inapplicable_testlets = support.n_inapplicable_strata,
            n_pairs = support.n_pairs,
            n_pairs_with_observations = support.n_pairs_with_observations,
            n_structural_threshold_pairs = support.n_eligible_pairs,
            n_summary_supported_pairs =
                count(record -> record.summary_support_met, family_records),
            maximum_common_units = support.maximum_common_units,
            maximum_common_responses = isempty(family_records) ? 0 :
                maximum(record -> record.n_common_responses, family_records),
            duplicate_policy = :error,
            decision_available = false,
            mechanism_interpretation_eligible = false,
        ))
    end
    return (; family_rows = Tuple(families), family_testlet_rows = Tuple(rows))
end

function _local_dependence_preflight(
        fit,
        indices::AbstractVector{Int},
        contract;
        max_pair_draw_cells::Int,
        max_prediction_cells::Int,
        max_audit_pair_rows::Int,
        max_common_unit_draw_cells::Int)
    max_pair_draw_cells >= 1 ||
        throw(ArgumentError("max_pair_draw_cells must be positive"))
    max_prediction_cells >= 1 ||
        throw(ArgumentError("max_prediction_cells must be positive"))
    max_audit_pair_rows >= 1 ||
        throw(ArgumentError("max_audit_pair_rows must be positive"))
    max_common_unit_draw_cells >= 1 ||
        throw(ArgumentError("max_common_unit_draw_cells must be positive"))
    isempty(indices) &&
        throw(ArgumentError("local_dependence_summary requires posterior draws"))
    length(unique(indices)) == length(indices) ||
        throw(ArgumentError(
            "local-dependence draw indices must be distinct"))
    all(index -> 1 <= index <= size(fit.draws, 1), indices) ||
        throw(ArgumentError("local-dependence draw indices are out of bounds"))

    data = fit.design.spec.data
    current_data_signature = _data_signature(data)
    current_data_signature == fit.design.spec.validation.data_signature ||
        throw(ArgumentError(
            "fitted FacetData changed after design construction; refit before local-dependence diagnostics"))
    missing_roles = [role for role in (:response_id, :testlet_id)
        if !haskey(data.optional, role)]
    isempty(missing_roles) ||
        throw(ArgumentError(
            "local_dependence_summary requires FacetData metadata roles $(Tuple(missing_roles))"))

    n_draws = length(indices)
    n_categories = length(data.category_levels)
    data.n <= max_prediction_cells ÷ n_categories ||
        throw(ArgumentError(
            "local-dependence predictive workload exceeds max_prediction_cells=$max_prediction_cells; reduce observations or analyze prespecified strata separately"))
    prediction_cells_per_draw = data.n * n_categories
    prediction_cells_per_draw <= max_prediction_cells ÷ n_draws ||
        throw(ArgumentError(
            "local-dependence predictive workload exceeds max_prediction_cells=$max_prediction_cells; reduce ndraws/draw_indices or analyze prespecified strata separately"))
    prediction_cells = prediction_cells_per_draw * n_draws

    max_audit_common_unit_links = max_common_unit_draw_cells
    audit_pair_preflight = _testlet_materialized_pair_preflight(
        data;
        max_materialized_pair_rows = max_audit_pair_rows,
        max_pair_common_unit_links = max_audit_common_unit_links,
        materialized_pair_rows_limit_name = :max_audit_pair_rows,
        pair_common_unit_links_limit_name = :max_common_unit_draw_cells,
    )
    single_rating_item_all_testlets_applicable =
        audit_pair_preflight.single_rating_item_all_testlets_applicable
    single_rating_item_any_testlet_applicable =
        audit_pair_preflight.single_rating_item_any_testlet_applicable
    single_rating_item_applicable_by_testlet =
        audit_pair_preflight.single_rating_item_applicable_by_testlet
    n_candidate_pairs =
        audit_pair_preflight.n_diagnostic_candidate_pairs
    candidate_pair_draw_cells = try
        Base.Checked.checked_mul(n_candidate_pairs, n_draws)
    catch error
        error isa OverflowError || rethrow()
        typemax(Int)
    end

    audit = testlet_design_audit(
        fit.design;
        target = :scalar_shared_cluster,
        min_pair_common_units = contract.thresholds.min_common_units,
        max_materialized_pair_rows = max_audit_pair_rows,
        max_pair_common_unit_links = max_audit_common_unit_links,
    )
    audit.schema_valid ||
        throw(ArgumentError(
            "local_dependence_summary requires valid response nesting and unique response-rater-item rows"))

    n_positive_common_pairs = sum(
        count(pair -> pair.common_units > 0, support.pairs)
        for support in values(audit.diagnostic_pair_support)
    )
    n_audit_diagnostic_pairs = sum(
        length(support.pairs)
        for support in values(audit.diagnostic_pair_support)
    )
    n_audit_diagnostic_pairs == n_candidate_pairs ||
        throw(ArgumentError(
            "pair-support audit candidate count disagrees with preflight"))
    n_audit_pair_common_unit_links = sum(
        sum((pair.common_units for pair in support.pairs); init = 0)
        for support in values(audit.diagnostic_pair_support);
        init = 0,
    )
    n_audit_pair_common_unit_links ==
        audit_pair_preflight.n_pair_common_unit_links ||
        throw(ArgumentError(
            "pair-support audit common-unit count disagrees with preflight"))
    single_support = audit.diagnostic_pair_support.single_rating_item_q3
    audit_single_applicability = Tuple(
        ismissing(stratum.inapplicable_reason)
        for stratum in single_support.strata
    )
    audit_single_applicability ==
        single_rating_item_applicable_by_testlet ||
        throw(ArgumentError(
            "single-rating applicability disagrees between audit and preflight"))
    n_positive_common_pairs <= n_candidate_pairs ||
        throw(ArgumentError(
            "pair-support audit returned more positive-overlap pairs than the preflight candidate bound"))
    n_positive_common_pairs <= max_pair_draw_cells ÷ n_draws ||
        throw(ArgumentError(
            "local-dependence positive-overlap pair-by-draw workload exceeds max_pair_draw_cells=$max_pair_draw_cells; reduce ndraws/draw_indices or analyze prespecified strata separately"))
    pair_draw_cells = n_positive_common_pairs * n_draws
    n_pair_common_unit_links =
        audit_pair_preflight.n_pair_common_unit_links
    n_pair_common_unit_links <= max_common_unit_draw_cells ÷ n_draws ||
        throw(ArgumentError(
            "local-dependence pair/common-unit-by-draw workload exceeds max_common_unit_draw_cells=$max_common_unit_draw_cells; reduce ndraws/draw_indices or analyze prespecified strata separately"))
    common_unit_draw_cells = n_pair_common_unit_links * n_draws
    return (;
        schema = "bayesianmgmfrm.local_dependence_preflight.v1",
        audit,
        contract,
        design_signature = audit.design_signature,
        data_signature = current_data_signature,
        draw_indices = Tuple(indices),
        single_rating_item_all_testlets_applicable,
        single_rating_item_any_testlet_applicable,
        single_rating_item_applicable_by_testlet,
        audit_pair_preflight,
        n_candidate_pairs,
        candidate_pair_draw_cells,
        n_positive_common_pairs,
        pair_draw_cells,
        max_pair_draw_cells,
        n_pair_common_unit_links,
        common_unit_draw_cells,
        max_common_unit_draw_cells,
        max_audit_pair_rows,
        prediction_cells,
        max_prediction_cells,
    )
end

function _local_dependence_summary_from_probabilities(
        fit,
        indices::AbstractVector{Int},
        probabilities::AbstractArray{<:Real,3};
        contract,
        interval::Real,
        rng::AbstractRNG,
        replicated_scores = nothing,
        max_pair_draw_cells::Int =
            _LOCAL_DEPENDENCE_DEFAULT_MAX_PAIR_DRAW_CELLS,
        max_prediction_cells::Int =
            _LOCAL_DEPENDENCE_DEFAULT_MAX_PREDICTION_CELLS,
        max_audit_pair_rows::Int =
            _LOCAL_DEPENDENCE_DEFAULT_MAX_AUDIT_PAIR_ROWS,
        max_common_unit_draw_cells::Int =
            _LOCAL_DEPENDENCE_DEFAULT_MAX_COMMON_UNIT_DRAW_CELLS,
        preflight = nothing)
    checked_contract = _local_dependence_validate_contract(contract)
    lower, upper = _interval_probabilities(interval)
    interval_probability = Float64(interval)
    data = fit.design.spec.data
    max_pair_draw_cells >= 1 ||
        throw(ArgumentError("max_pair_draw_cells must be positive"))
    max_prediction_cells >= 1 ||
        throw(ArgumentError("max_prediction_cells must be positive"))
    max_audit_pair_rows >= 1 ||
        throw(ArgumentError("max_audit_pair_rows must be positive"))
    max_common_unit_draw_cells >= 1 ||
        throw(ArgumentError("max_common_unit_draw_cells must be positive"))
    length(indices) == size(probabilities, 1) ||
        throw(ArgumentError(
            "draw_indices and predictive probabilities must have the same draw count"))
    size(probabilities, 2) == data.n ||
        throw(ArgumentError(
            "predictive probabilities observation count does not match data"))
    size(probabilities, 3) == length(data.category_levels) ||
        throw(ArgumentError(
            "predictive probabilities category count does not match data"))
    checked_preflight = preflight === nothing ?
        _local_dependence_preflight(
            fit,
            indices,
            checked_contract;
            max_pair_draw_cells,
            max_prediction_cells,
            max_audit_pair_rows,
            max_common_unit_draw_cells,
        ) : preflight
    checked_preflight isa NamedTuple &&
        hasproperty(checked_preflight, :schema) &&
        checked_preflight.schema ==
            "bayesianmgmfrm.local_dependence_preflight.v1" ||
        throw(ArgumentError("invalid local-dependence preflight result"))
    all(name -> hasproperty(checked_preflight, name), (
            :audit,
            :contract,
            :design_signature,
            :data_signature,
            :draw_indices,
            :single_rating_item_all_testlets_applicable,
            :single_rating_item_any_testlet_applicable,
            :single_rating_item_applicable_by_testlet,
            :audit_pair_preflight,
            :n_candidate_pairs,
            :candidate_pair_draw_cells,
            :n_positive_common_pairs,
            :pair_draw_cells,
            :max_pair_draw_cells,
            :n_pair_common_unit_links,
            :common_unit_draw_cells,
            :max_common_unit_draw_cells,
            :max_audit_pair_rows,
            :prediction_cells,
            :max_prediction_cells,
        )) || throw(ArgumentError(
            "incomplete local-dependence preflight result"))
    checked_preflight.data_signature ==
        fit.design.spec.validation.data_signature ||
        throw(ArgumentError(
            "local-dependence preflight data signature does not match fit"))
    checked_preflight.data_signature == _data_signature(data) ||
        throw(ArgumentError(
            "local-dependence preflight data signature does not match current fit data"))
    checked_preflight.draw_indices == Tuple(indices) ||
        throw(ArgumentError(
            "local-dependence preflight draw indices do not match"))
    isequal(checked_preflight.contract, checked_contract) ||
        throw(ArgumentError(
            "local-dependence preflight contract does not match"))
    checked_preflight.design_signature ==
        checked_preflight.audit.design_signature ||
        throw(ArgumentError(
            "local-dependence preflight audit signature does not match"))
    checked_preflight.design_signature ==
        _testlet_design_signature(data) ||
        throw(ArgumentError(
            "local-dependence preflight design signature does not match current fit data"))
    checked_preflight.max_pair_draw_cells == max_pair_draw_cells ||
        throw(ArgumentError(
            "local-dependence preflight pair-cell limit does not match"))
    checked_preflight.max_audit_pair_rows == max_audit_pair_rows ||
        throw(ArgumentError(
            "local-dependence preflight audit-pair limit does not match"))
    checked_preflight.max_common_unit_draw_cells ==
        max_common_unit_draw_cells ||
        throw(ArgumentError(
            "local-dependence preflight common-unit-cell limit does not match"))
    checked_preflight.max_prediction_cells == max_prediction_cells ||
        throw(ArgumentError(
            "local-dependence preflight prediction-cell limit does not match"))
    audit = checked_preflight.audit
    audit_pair_preflight = checked_preflight.audit_pair_preflight
    isequal(audit.computational_support, audit_pair_preflight) ||
        throw(ArgumentError(
            "local-dependence audit pair-row support does not match preflight"))
    n_candidate_pairs = checked_preflight.n_candidate_pairs
    candidate_pair_draw_cells =
        checked_preflight.candidate_pair_draw_cells
    n_positive_common_pairs = checked_preflight.n_positive_common_pairs
    pair_draw_cells = checked_preflight.pair_draw_cells
    n_pair_common_unit_links =
        checked_preflight.n_pair_common_unit_links
    common_unit_draw_cells = checked_preflight.common_unit_draw_cells
    prediction_cells = checked_preflight.prediction_cells

    scores = replicated_scores === nothing ?
        _local_dependence_sample_replicated_scores(
            data,
            probabilities,
            data.category_levels,
            rng,
        ) :
        _local_dependence_validate_replicated_scores(
            replicated_scores,
            length(indices),
            data,
        )
    residual_pair = _local_dependence_standardized_residual_pair(
        data,
        probabilities,
        scores,
        checked_contract.thresholds.variance_tolerance,
    )
    observed = residual_pair.observed
    replicated = residual_pair.replicated
    records = _local_dependence_pair_records(
        data,
        audit,
        observed,
        replicated,
        checked_contract,
    )
    pair_rows = _local_dependence_pair_rows(
        records,
        checked_contract,
        lower,
        upper,
        interval_probability,
        audit,
    )
    support_rows = _local_dependence_family_support_rows(
        data,
        audit,
        records,
        checked_contract,
    )
    min_draws = checked_contract.thresholds.min_eligible_draws
    min_fraction =
        Float64(checked_contract.thresholds.min_eligible_draw_fraction)
    family_max_rows = Tuple((;
        family,
        role = :descriptive_localization_aid,
        _local_dependence_maximum_evidence(
            records,
            [index for index in eachindex(records)
                if records[index].family === family],
            length(indices),
            min_draws,
            min_fraction;
            scope = :within_pair_family,
            lower,
            upper,
        )...,
    ) for family in _LOCAL_DEPENDENCE_PAIR_FAMILIES)
    global_evidence = _local_dependence_maximum_evidence(
        records,
        collect(eachindex(records)),
        length(indices),
        min_draws,
        min_fraction;
        scope = :all_enabled_families_and_eligible_pairs,
        lower,
        upper,
    )
    n_supported = count(record -> record.summary_support_met, records)
    any_structural = any(record -> record.structural_support_met, records)
    any_paired_defined = any(record -> any(draw ->
            isfinite(record.observed[draw]) &&
                isfinite(record.replicated[draw]),
            eachindex(record.observed)),
        records)
    status = n_supported > 0 ? :report_only :
        any_structural && !any_paired_defined ?
            :undefined_residual_variation :
        any_structural ? :insufficient_draw_support : :no_eligible_pairs
    halo_row_index = findfirst(row ->
        row.check === :rater_response_halo_support,
        audit.rows,
    )
    halo_row = halo_row_index === nothing ? nothing : audit.rows[halo_row_index]
    return (;
        schema = "bayesianmgmfrm.local_dependence_summary.v1",
        object = :local_dependence_summary,
        status,
        family = fit.design.spec.family,
        model_thresholds = fit.design.spec.thresholds,
        profile = checked_contract.profile,
        frozen_profile = checked_contract.frozen_profile,
        calibration_status = :pending_independent_known_truth_simulation,
        calibration_required = true,
        decision_labels_available = false,
        mechanism_interpretation_eligible = false,
        conditioning = :observed_rows_and_fitted_latent_effects,
        prediction_target = :conditional_observed_cluster,
        draw_source = :distinct_posterior_draws,
        draw_indices = Tuple(indices),
        chain_ids = Tuple(fit.chain_ids[indices]),
        iterations = Tuple(fit.iterations[indices]),
        n_draws = length(indices),
        replicated_datasets_per_parameter_draw = 1,
        replication_source = replicated_scores === nothing ?
            :generated_from_parameter_draw : :supplied_for_reproduction,
        interval_probability,
        data_signature = fit.design.spec.validation.data_signature,
        observed_score_signature =
            _local_dependence_observed_score_signature(data),
        design_signature = audit.design_signature,
        contract = checked_contract,
        diagnostic_thresholds = checked_contract.thresholds,
        computational_support = (;
            single_rating_item_all_testlets_applicable =
                checked_preflight.single_rating_item_all_testlets_applicable,
            single_rating_item_any_testlet_applicable =
                checked_preflight.single_rating_item_any_testlet_applicable,
            single_rating_item_applicable_by_testlet =
                checked_preflight.single_rating_item_applicable_by_testlet,
            n_audit_projected_rater_pairs =
                audit_pair_preflight.n_projected_rater_pairs,
            n_audit_materialized_pair_rows =
                audit_pair_preflight.n_materialized_pair_rows,
            n_audit_projected_rater_response_links =
                audit_pair_preflight.n_projected_rater_response_links,
            n_audit_pair_common_unit_links =
                audit_pair_preflight.n_audit_pair_common_unit_links,
            max_audit_pair_rows,
            n_candidate_pairs,
            candidate_pair_draw_cells,
            n_positive_common_pairs,
            pair_draw_cells,
            max_pair_draw_cells,
            n_pair_common_unit_links,
            common_unit_draw_cells,
            max_common_unit_draw_cells,
            prediction_cells,
            max_prediction_cells,
            zero_common_pair_rows_retained = false,
            zero_common_pair_support_available_in = :family_testlet_rows,
        ),
        design_support = (;
            audit_target = :scalar_shared_cluster,
            scalar_candidate_audit_status = audit.status,
            scalar_candidate_audit_status_reason = audit.status_reason,
            schema_valid = audit.schema_valid,
            person_testlet_graph_components =
                audit.summary.person_testlet_graph_components,
            person_testlet_bridge_count =
                audit.summary.person_testlet_bridge_count,
            rater_response_halo_structurally_eligible =
                audit.summary.rater_response_halo_structurally_eligible,
            rater_response_halo_observed =
                halo_row === nothing ? missing : halo_row.observed,
            rater_response_halo_note =
                halo_row === nothing ? missing : halo_row.note,
        ),
        selected_families = _LOCAL_DEPENDENCE_PAIR_FAMILIES,
        family_rows = support_rows.family_rows,
        family_testlet_rows = support_rows.family_testlet_rows,
        pair_rows,
        family_max_rows,
        global_evidence,
        residual_support = (;
            n_valid_observed_residuals = observed.n_valid,
            n_excluded_observed_residuals = observed.n_excluded,
            n_valid_replicated_residuals = count(replicated.valid),
            n_excluded_replicated_residuals =
                length(replicated.valid) - count(replicated.valid),
            variance_tolerance =
                checked_contract.thresholds.variance_tolerance,
        ),
        n_pair_rows = length(pair_rows),
        n_summary_supported_pairs = n_supported,
        decision = missing,
        caveats = (
            :posterior_predictive_tail_fractions_are_not_calibrated_decision_p_values,
            :q3_style_association_does_not_identify_a_dependence_mechanism,
            :family_specific_maxima_are_localization_aids_only,
            :tail_fraction_mcse_is_an_iid_plugin_reference_not_chain_adjusted,
            :marginal_whole_cluster_prediction_requires_a_cluster_model_and_refit,
        ),
    )
end

"""
    local_dependence_summary(fit;
        contract = local_dependence_contract(), interval = 0.95,
        ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng(), max_pair_draw_cells = 2_000_000,
        max_prediction_cells = 10_000_000,
        max_audit_pair_rows = 200_000,
        max_common_unit_draw_cells = 2_000_000)

Return report-only residual-association summaries for a fitted MFRM, guarded
GMFRM, or guarded MGMFRM model whose `FacetData` declares `response_id` and
`testlet_id`. The summary keeps single-rating item pairs, within-rater item
pairs, and rater pairs on the same response and criterion separate. It reports
draw-specific Pearson-correlation summaries, item-family adjusted-Q3-style
summaries, paired posterior predictive tail fractions, within-family BH
adjustments, support graphs, and one all-family maximum-statistic reference.

Posterior draws are distinct and, when `ndraws` is supplied, sampled without
replacement. Observed and replicated residual statistics use the same
parameter draw and one replicated dataset per draw. Sparse or undefined pairs
with at least one common unit remain in the pair rows with structured support
reasons and missing evidence values; they are not converted to zero
association. Zero-overlap combinations remain visible through family counts
and testlet-stratified support graphs. Before large allocations,
`max_audit_pair_rows` bounds materialized audit pair rows,
`max_pair_draw_cells` bounds positive-overlap pair-by-draw cells, and
`max_common_unit_draw_cells` bounds both audit pair/common-unit links and the
pair/common-unit-by-draw correlation work; `max_prediction_cells` bounds
draw-by-observation-by-category cells. Reduce `ndraws` or prespecify separate
strata when a guard is exceeded.

This function provides no universal Q3 cutoff, calibrated FDR/FWER decision,
or testlet, halo, rater-by-task, multidimensional, or temporal mechanism label.
Posterior predictive tail fractions and BH-adjusted values are descriptive
calibration-pending references, not decision p-values.
"""
function local_dependence_summary(
        fit::Union{MFRMFit,GMFRMFit,MGMFRMFit};
        contract = local_dependence_contract(),
        interval::Real = 0.95,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        max_pair_draw_cells::Int =
            _LOCAL_DEPENDENCE_DEFAULT_MAX_PAIR_DRAW_CELLS,
        max_prediction_cells::Int =
            _LOCAL_DEPENDENCE_DEFAULT_MAX_PREDICTION_CELLS,
        max_audit_pair_rows::Int =
            _LOCAL_DEPENDENCE_DEFAULT_MAX_AUDIT_PAIR_ROWS,
        max_common_unit_draw_cells::Int =
            _LOCAL_DEPENDENCE_DEFAULT_MAX_COMMON_UNIT_DRAW_CELLS)
    max_pair_draw_cells >= 1 ||
        throw(ArgumentError("max_pair_draw_cells must be positive"))
    max_prediction_cells >= 1 ||
        throw(ArgumentError("max_prediction_cells must be positive"))
    max_audit_pair_rows >= 1 ||
        throw(ArgumentError("max_audit_pair_rows must be positive"))
    max_common_unit_draw_cells >= 1 ||
        throw(ArgumentError("max_common_unit_draw_cells must be positive"))
    checked_contract = _local_dependence_validate_contract(contract)
    _interval_probabilities(interval)
    indices = _local_dependence_draw_indices(
        fit,
        ndraws,
        draw_indices,
        rng,
    )
    preflight = _local_dependence_preflight(
        fit,
        indices,
        checked_contract;
        max_pair_draw_cells,
        max_prediction_cells,
        max_audit_pair_rows,
        max_common_unit_draw_cells,
    )
    probabilities = _local_dependence_predictive_probabilities(fit, indices)
    return _local_dependence_summary_from_probabilities(
        fit,
        indices,
        probabilities;
        contract = checked_contract,
        interval,
        rng,
        max_pair_draw_cells,
        max_prediction_cells,
        max_audit_pair_rows,
        max_common_unit_draw_cells,
        preflight,
    )
end
