# practitioner_diagnostics.jl -- report-ready MFRM category and rater summaries.

function _practitioner_draw_indices(draws::AbstractMatrix,
        ndraws::Union{Nothing,Int},
        draw_indices,
        rng::AbstractRNG)
    return _posterior_draw_indices((; draws), ndraws, draw_indices, rng)
end

function _check_practitioner_draws(design::FacetDesign,
        draws::AbstractMatrix,
        caller::AbstractString)
    _check_fit_supported_mfrm(design, caller)
    return _check_rater_diagnostic_draws(design, draws, caller)
end

function _category_functioning_controls(interval::Real,
        min_count::Int,
        min_proportion::Real,
        order_probability_threshold::Real)
    lower_probability, upper_probability = _interval_probabilities(interval)
    min_count >= 1 || throw(ArgumentError("min_count must be positive"))
    isfinite(min_proportion) && 0 <= min_proportion <= 1 ||
        throw(ArgumentError("min_proportion must be finite and in [0, 1]"))
    isfinite(order_probability_threshold) &&
        0.5 < order_probability_threshold <= 1 ||
        throw(ArgumentError(
            "order_probability_threshold must be finite and in (0.5, 1]",
        ))
    return (;
        interval = Float64(interval),
        lower_probability,
        upper_probability,
        min_count,
        min_proportion = Float64(min_proportion),
        order_probability_threshold = Float64(order_probability_threshold),
    )
end

function _category_functioning_groups(data::FacetData)
    groups = NamedTuple[(;
        facet = :overall,
        level = missing,
        level_index = missing,
        observations = collect(1:data.n),
    )]
    for (facet, index, levels) in (
            (:rater, data.rater, data.rater_levels),
            (:item, data.item, data.item_levels),
        )
        for (level_index, level) in pairs(levels)
            push!(groups, (;
                facet,
                level,
                level_index,
                observations = findall(==(level_index), index),
            ))
        end
    end
    return groups
end

function _category_observed_flag(count::Int,
        proportion::Float64,
        controls)
    count == 0 && return :skipped
    (count < controls.min_count || proportion < controls.min_proportion) &&
        return :sparse
    return :ok
end

function _category_predictive_flag(observed::Float64, summary)
    return observed < summary.lower || observed > summary.upper ?
        :outside_predictive_interval : :ok
end

function _category_functioning_usage_rows(data::FacetData,
        replicated_scores::AbstractMatrix{<:Integer},
        controls)
    rows = NamedTuple[]
    for group in _category_functioning_groups(data)
        observations = group.observations
        n_observations = length(observations)
        for category in data.category_levels
            observed_count = count(
                observation -> data.score[observation] == category,
                observations,
            )
            observed_proportion = observed_count / n_observations
            replicated_proportions = Vector{Float64}(
                undef,
                size(replicated_scores, 1),
            )
            for replication in axes(replicated_scores, 1)
                replicated_count = count(
                    observation -> replicated_scores[replication, observation] ==
                        category,
                    observations,
                )
                replicated_proportions[replication] =
                    replicated_count / n_observations
            end
            replicated_summary = _finite_draw_summary(
                replicated_proportions,
                controls.lower_probability,
                controls.upper_probability,
            )
            tails = _tail_probabilities(
                replicated_proportions,
                observed_proportion,
            )
            observed_flag = _category_observed_flag(
                observed_count,
                observed_proportion,
                controls,
            )
            predictive_flag = _category_predictive_flag(
                observed_proportion,
                replicated_summary,
            )
            review_recommended =
                observed_flag !== :ok || predictive_flag !== :ok
            push!(rows, (;
                schema = "bayesianmgmfrm.category_functioning_usage_row.v1",
                object = :category_functioning_usage_row,
                model_family = :mfrm,
                facet = group.facet,
                level = group.level,
                level_index = group.level_index,
                category,
                n_observations,
                observed_count,
                observed_proportion,
                min_count = controls.min_count,
                min_proportion = controls.min_proportion,
                observed_flag,
                n_replicates = length(replicated_proportions),
                replicated_proportion_mean = replicated_summary.mean,
                replicated_proportion_median = replicated_summary.median,
                replicated_proportion_lower = replicated_summary.lower,
                replicated_proportion_upper = replicated_summary.upper,
                interval_probability = controls.interval,
                interval_type = :central_posterior_predictive_replication,
                lower_probability = controls.lower_probability,
                upper_probability = controls.upper_probability,
                replicated_probability_skipped =
                    count(iszero, replicated_proportions) /
                    length(replicated_proportions),
                lower_tail_probability = tails.lower,
                upper_tail_probability = tails.upper,
                two_sided_tail_probability = tails.two_sided,
                predictive_flag,
                flag = observed_flag !== :ok ? observed_flag : predictive_flag,
                review_recommended,
                recommendation = review_recommended ?
                    :review_category_functioning : :none,
                automatic_category_collapse = false,
                analysis_decision_required = review_recommended,
                caveat = :diagnostic_screen_not_automatic_category_collapse,
            ))
        end
    end
    return rows
end

function _threshold_item_index(design::FacetDesign, row)
    design.spec.thresholds === :rating_scale && return 1
    index = findfirst(isequal(row.item), design.spec.data.item_levels)
    index === nothing &&
        throw(ArgumentError("threshold row item was not found in the design"))
    return index
end

function _category_functioning_threshold_rows(design::FacetDesign,
        draws::AbstractMatrix,
        controls)
    metadata_rows = threshold_map_data(design)
    rows = NamedTuple[]
    for metadata in metadata_rows
        item_index = _threshold_item_index(design, metadata)
        values = [
            Float64(_threshold_step(
                design,
                @view(draws[draw, :]),
                item_index,
                metadata.step,
            ))
            for draw in axes(draws, 1)
        ]
        summary = _finite_draw_summary(
            values,
            controls.lower_probability,
            controls.upper_probability,
        )
        if metadata.step == 1
            probability_greater_than_previous = missing
            probability_less_equal_previous = missing
            ordering_flag = :not_applicable
        else
            previous_values = [
                Float64(_threshold_step(
                    design,
                    @view(draws[draw, :]),
                    item_index,
                    metadata.step - 1,
                ))
                for draw in axes(draws, 1)
            ]
            probability_greater_than_previous =
                count(index -> values[index] > previous_values[index],
                    eachindex(values)) / length(values)
            probability_less_equal_previous =
                1 - probability_greater_than_previous
            ordering_flag =
                probability_greater_than_previous >=
                    controls.order_probability_threshold ? :likely_ordered :
                probability_less_equal_previous >=
                    controls.order_probability_threshold ? :likely_disordered :
                :order_uncertain
        end
        review_recommended = ordering_flag in
            (:likely_disordered, :order_uncertain)
        push!(rows, (;
            schema = "bayesianmgmfrm.category_functioning_threshold_row.v1",
            object = :category_functioning_threshold_row,
            model_family = :mfrm,
            thresholds = design.spec.thresholds,
            threshold_type = design.spec.thresholds === :rating_scale ?
                :shared_rating_scale_step : :item_partial_credit_step,
            item = metadata.item,
            item_index = design.spec.thresholds === :rating_scale ?
                missing : item_index,
            step = metadata.step,
            from_category = metadata.from_category,
            to_category = metadata.to_category,
            parameter_index = metadata.parameter_index,
            parameter_name = metadata.parameter_name,
            parameter_status = metadata.status,
            n_draws = length(values),
            step_mean = summary.mean,
            step_sd = _column_sd(values, summary.mean),
            step_median = summary.median,
            step_lower = summary.lower,
            step_upper = summary.upper,
            interval_probability = controls.interval,
            interval_type = :central_posterior_parameter,
            lower_probability = controls.lower_probability,
            upper_probability = controls.upper_probability,
            probability_step_greater_than_previous =
                probability_greater_than_previous,
            probability_step_less_equal_previous =
                probability_less_equal_previous,
            order_probability_threshold =
                controls.order_probability_threshold,
            ordering_flag,
            review_recommended,
            recommendation = review_recommended ?
                :review_step_order_and_category_evidence : :none,
            automatic_category_collapse = false,
            analysis_decision_required = review_recommended,
            caveat = :step_order_screen_not_automatic_category_collapse,
        ))
    end
    return rows
end

"""
    category_functioning_summary(fit::MFRMFit; interval = 0.95,
        min_count = 5, min_proportion = 0.01,
        order_probability_threshold = 0.8, ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())
    category_functioning_summary(design::FacetDesign, draws; kwargs...)

Return a versioned MFRM/RSM/PCM category-functioning bundle. `usage_rows`
contain overall, rater-by-category, and item-by-category observed use together
with posterior predictive replicated proportions and tail probabilities.
`threshold_rows` contain posterior step intervals and draw-wise adjacent-step
ordering probabilities for the shared RSM steps or item-specific PCM steps.

Flags are diagnostic review prompts. This function never collapses, recodes,
or refits score categories; a flagged row records that an explicit analysis
decision is required.
"""
function category_functioning_summary(design::FacetDesign,
        draws::AbstractMatrix;
        interval::Real = 0.95,
        min_count::Int = 5,
        min_proportion::Real = 0.01,
        order_probability_threshold::Real = 0.8,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    _check_practitioner_draws(design, draws, "category_functioning_summary")
    controls = _category_functioning_controls(
        interval,
        min_count,
        min_proportion,
        order_probability_threshold,
    )
    indices = _practitioner_draw_indices(draws, ndraws, draw_indices, rng)
    selected_draws = draws[indices, :]
    replicated_scores = _replicate_scores(design, selected_draws, rng)
    usage_rows = _category_functioning_usage_rows(
        design.spec.data,
        replicated_scores,
        controls,
    )
    threshold_rows = _category_functioning_threshold_rows(
        design,
        selected_draws,
        controls,
    )
    n_review_rows = count(row -> row.review_recommended, usage_rows) +
        count(row -> row.review_recommended, threshold_rows)
    return (;
        schema = "bayesianmgmfrm.category_functioning_summary.v1",
        object = :category_functioning_summary,
        model_family = :mfrm,
        thresholds = design.spec.thresholds,
        data_signature = design.spec.validation.data_signature,
        n_draws = length(indices),
        draw_indices = Tuple(indices),
        controls,
        usage_rows = Tuple(usage_rows),
        threshold_rows = Tuple(threshold_rows),
        summary = (;
            n_usage_rows = length(usage_rows),
            n_threshold_rows = length(threshold_rows),
            n_skipped_usage_rows =
                count(row -> row.observed_flag === :skipped, usage_rows),
            n_sparse_usage_rows =
                count(row -> row.observed_flag === :sparse, usage_rows),
            n_predictive_flag_rows = count(
                row -> row.predictive_flag !== :ok,
                usage_rows,
            ),
            n_likely_disordered_step_rows = count(
                row -> row.ordering_flag === :likely_disordered,
                threshold_rows,
            ),
            n_order_uncertain_step_rows = count(
                row -> row.ordering_flag === :order_uncertain,
                threshold_rows,
            ),
            n_review_rows,
            review_recommended = n_review_rows > 0,
        ),
        policy = (;
            usage_interval_type = :central_posterior_predictive_replication,
            threshold_interval_type = :central_posterior_parameter,
            ordering_estimand = :probability_current_step_exceeds_previous_step,
            recommendation_status = :diagnostic_review_only,
            automatic_category_collapse = false,
            refit_performed = false,
        ),
        caveat = :category_functioning_diagnostics_not_category_collapse_rule,
    )
end

function category_functioning_summary(fit::MFRMFit; kwargs...)
    return category_functioning_summary(fit.design, fit.draws; kwargs...)
end

function _rater_homogeneity_controls(interval::Real,
        severity_rope,
        rope_probability_threshold::Real,
        min_shared_units::Int)
    lower_probability, upper_probability = _interval_probabilities(interval)
    rope_bounds = _posterior_rope_bounds(severity_rope)
    isfinite(rope_probability_threshold) &&
        0 < rope_probability_threshold <= 1 ||
        throw(ArgumentError(
            "rope_probability_threshold must be finite and in (0, 1]",
        ))
    min_shared_units >= 1 ||
        throw(ArgumentError("min_shared_units must be positive"))
    return (;
        interval = Float64(interval),
        lower_probability,
        upper_probability,
        severity_rope = rope_bounds,
        rope_probability_threshold = Float64(rope_probability_threshold),
        min_shared_units,
    )
end

function _rater_overlap_network(data::FacetData,
        overlap_rows,
        min_shared_units::Int)
    n_raters = length(data.rater_levels)
    level_index = Dict(level => index
        for (index, level) in pairs(data.rater_levels))
    adjacency = [Int[] for _ in 1:n_raters]
    overlap_by_pair = Dict{Tuple{Int,Int},Any}()
    for row in overlap_rows
        a = level_index[row.rater_a]
        b = level_index[row.rater_b]
        overlap_by_pair[(a, b)] = row
        if row.shared_units >= min_shared_units
            push!(adjacency[a], b)
            push!(adjacency[b], a)
        end
    end
    component = zeros(Int, n_raters)
    n_components = 0
    for start in 1:n_raters
        component[start] != 0 && continue
        n_components += 1
        queue = [start]
        component[start] = n_components
        head = 1
        while head <= length(queue)
            current = queue[head]
            head += 1
            for neighbor in adjacency[current]
                component[neighbor] == 0 || continue
                component[neighbor] = n_components
                push!(queue, neighbor)
            end
        end
    end
    return (;
        overlap_by_pair,
        component,
        n_components,
        network_status = n_components <= 1 ? :connected : :disconnected,
    )
end

function _rater_pair_support(a::Int, b::Int, overlap, network, min_shared_units)
    overlap.shared_units >= min_shared_units && return :direct
    network.component[a] == network.component[b] && return :network
    return :disconnected
end

function _rater_model_identification_network(design::FacetDesign)
    data = design.spec.data
    validation = design.spec.validation
    components = validation.components
    rater_component = zeros(Int, length(data.rater_levels))
    rater_level_index = Dict(level => index
        for (index, level) in pairs(data.rater_levels))
    for (component_index, component) in pairs(components)
        for (facet, level) in component
            facet === :rater || continue
            rater_component[rater_level_index[level]] = component_index
        end
    end
    rank_issue = findfirst(
        issue -> issue.code === :rank_deficient_design,
        validation.issues,
    )
    n_location_parameters = length(data.person_levels) +
        max(length(data.rater_levels) - 1, 0) +
        max(length(data.item_levels) - 1, 0)
    location_full_rank = rank_issue === nothing
    location_rank = location_full_rank ? n_location_parameters :
        get(validation.issues[rank_issue].context, :rank, missing)
    person_sets = [Set{Int}() for _ in data.rater_levels]
    item_sets = [Set{Int}() for _ in data.rater_levels]
    for observation in 1:data.n
        rater_index = data.rater[observation]
        push!(person_sets[rater_index], data.person[observation])
        push!(item_sets[rater_index], data.item[observation])
    end
    return (;
        components,
        rater_component,
        n_components = length(components),
        location_rank,
        n_location_parameters,
        location_full_rank,
        person_sets,
        item_sets,
        validation_passed = validation.passed,
        validation_source = :stored_validation_report,
    )
end

function _rater_common_response_status(overlap_unit::Symbol)
    overlap_unit in (:response_id, :response_item) &&
        return :verified_common_response
    overlap_unit === :person_item && return :person_item_proxy
    return :not_verified_by_requested_unit
end

function _rater_model_identification_pair(a::Int, b::Int, network)
    connected = network.rater_component[a] != 0 &&
        network.rater_component[a] == network.rater_component[b]
    shared_persons = length(intersect(
        network.person_sets[a],
        network.person_sets[b],
    ))
    shared_items = length(intersect(
        network.item_sets[a],
        network.item_sets[b],
    ))
    direct_additive_link = shared_persons > 0 || shared_items > 0
    support = !connected ? :disconnected :
        !network.location_full_rank ? :rank_deficient :
        :full_rank_connected
    path = !connected ? :disconnected :
        direct_additive_link ? :shared_person_or_item :
        :connected_additive_facet_network
    return (;
        support,
        supported = support === :full_rank_connected,
        connected,
        path,
        shared_persons,
        shared_items,
        direct_additive_link,
    )
end

"""
    rater_homogeneity_summary(fit::MFRMFit; interval = 0.95,
        severity_rope = nothing, rope_probability_threshold = 0.95,
        overlap_unit = :person_item, min_shared_units = 1,
        ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    rater_homogeneity_summary(design::FacetDesign, draws; kwargs...)

Return draw-wise pairwise rater-severity contrasts for the minimal MFRM. Each
unordered pair reports `severity_a - severity_b` on the logit scale; a positive
contrast means rater A is more severe. Rows include a central posterior
interval, probability of direction, optional ROPE probabilities and practical-
equivalence classification, and direct/network/disconnected overlap under the
requested `overlap_unit`. This shared-unit overlap is reported separately from
identification by the full reference-constrained additive MFRM location
design. With the default `overlap_unit = :person_item`, overlap is a person-item
proxy and is not proof that two raters scored the identical response when
repeated responses or occasions exist. Use `:response_id` or `:response_item`
with declared response identifiers for verified common-response linking.
Raters linked through shared persons, shared items, or a connected facet
network are not labelled unidentified merely because their requested shared-
unit overlap graph is disconnected.

`severity_rope` is deliberately `nothing` by default because no universal
practical-equivalence margin exists. Supply a preregistered symmetric radius or
two-value interval to request `:inside_rope`, `:outside_rope`, or `:mixed`
classification. Bayes factors are not computed.
"""
function rater_homogeneity_summary(design::FacetDesign,
        draws::AbstractMatrix;
        interval::Real = 0.95,
        severity_rope = nothing,
        rope_probability_threshold::Real = 0.95,
        overlap_unit::Symbol = :person_item,
        min_shared_units::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    _check_practitioner_draws(design, draws, "rater_homogeneity_summary")
    controls = _rater_homogeneity_controls(
        interval,
        severity_rope,
        rope_probability_threshold,
        min_shared_units,
    )
    _require_rater_linking_unit(overlap_unit, :rater_homogeneity_summary)
    indices = _practitioner_draw_indices(draws, ndraws, draw_indices, rng)
    selected_draws = draws[indices, :]
    data = design.spec.data
    overlap_rows = rater_overlap(design; unit = overlap_unit)
    network = _rater_overlap_network(
        data,
        overlap_rows,
        controls.min_shared_units,
    )
    model_identification = _rater_model_identification_network(design)
    common_response_status = _rater_common_response_status(overlap_unit)
    severity_draws = [
        _rater_mfrm_severity_draws(design, selected_draws, rater_index)
        for rater_index in eachindex(data.rater_levels)
    ]
    rater_counts = [count(==(index), data.rater)
        for index in eachindex(data.rater_levels)]
    rows = NamedTuple[]
    for a in 1:(length(data.rater_levels) - 1)
        for b in (a + 1):length(data.rater_levels)
            overlap = network.overlap_by_pair[(a, b)]
            support = _rater_pair_support(
                a,
                b,
                overlap,
                network,
                controls.min_shared_units,
            )
            identification = _rater_model_identification_pair(
                a,
                b,
                model_identification,
            )
            contrast_values = severity_draws[a] .- severity_draws[b]
            contrast_summary = _finite_draw_summary(
                contrast_values,
                controls.lower_probability,
                controls.upper_probability,
            )
            direction = _posterior_direction_summary(contrast_values, 0.0)
            rope = _posterior_rope_summary(
                contrast_values,
                controls.severity_rope,
                controls.rope_probability_threshold,
            )
            push!(rows, (;
                schema = "bayesianmgmfrm.rater_homogeneity_contrast_row.v1",
                object = :rater_homogeneity_contrast_row,
                model_family = :mfrm,
                estimand = :severity_difference,
                contrast = :severity_a_minus_severity_b,
                interpretation = :positive_means_rater_a_more_severe,
                scale = :logit,
                rater_a = data.rater_levels[a],
                rater_b = data.rater_levels[b],
                rater_a_index = a,
                rater_b_index = b,
                rater_a_reference = a == 1,
                rater_b_reference = b == 1,
                n_observations_a = rater_counts[a],
                n_observations_b = rater_counts[b],
                n_draws = length(contrast_values),
                severity_difference_mean = contrast_summary.mean,
                severity_difference_median = contrast_summary.median,
                severity_difference_lower = contrast_summary.lower,
                severity_difference_upper = contrast_summary.upper,
                interval_probability = controls.interval,
                lower_probability = controls.lower_probability,
                upper_probability = controls.upper_probability,
                interval_excludes_zero = contrast_summary.lower > 0 ||
                    contrast_summary.upper < 0,
                direction.reference,
                direction.probability_positive,
                direction.probability_negative,
                direction.probability_equal,
                direction.probability_of_direction,
                direction.direction,
                rope.rope_lower,
                rope.rope_upper,
                rope.probability_in_rope,
                rope.probability_below_rope,
                rope.probability_above_rope,
                rope.practical_equivalence,
                rope_probability_threshold = controls.severity_rope === nothing ?
                    nothing : controls.rope_probability_threshold,
                overlap_unit,
                n_units_a = overlap.n_units_a,
                n_units_b = overlap.n_units_b,
                shared_units = overlap.shared_units,
                union_units = overlap.union_units,
                jaccard = overlap.jaccard,
                min_shared_units = controls.min_shared_units,
                shared_unit_overlap_support = support,
                shared_unit_overlap_definition =
                    :requested_unit_overlap,
                common_response_status,
                common_response_linking_verified =
                    common_response_status === :verified_common_response,
                model_identification_support = identification.support,
                model_identification_supported = identification.supported,
                model_identification_connected = identification.connected,
                model_identification_path = identification.path,
                shared_persons = identification.shared_persons,
                shared_items = identification.shared_items,
                direct_additive_link = identification.direct_additive_link,
                location_design_rank = model_identification.location_rank,
                location_design_n_parameters =
                    model_identification.n_location_parameters,
                location_design_full_rank =
                    model_identification.location_full_rank,
                support,
                support_compatibility_alias = :shared_unit_overlap_support,
                interpretation_status = identification.supported ?
                    :diagnostic : :design_unsupported,
                caveat = !identification.supported ?
                    :posterior_contrast_reported_but_additive_model_identification_unsupported :
                    support === :disconnected ?
                    :additive_model_identified_without_requested_shared_unit_overlap :
                    :posterior_contrast_not_score_agreement_or_bias_proof,
            ))
        end
    end
    n_disconnected = count(row -> row.support === :disconnected, rows)
    n_model_unsupported = count(
        row -> !row.model_identification_supported,
        rows,
    )
    return (;
        schema = "bayesianmgmfrm.rater_homogeneity_summary.v1",
        object = :rater_homogeneity_summary,
        model_family = :mfrm,
        thresholds = design.spec.thresholds,
        data_signature = design.spec.validation.data_signature,
        n_draws = length(indices),
        draw_indices = Tuple(indices),
        overlap_unit,
        controls,
        contrast_rows = Tuple(rows),
        summary = (;
            n_raters = length(data.rater_levels),
            n_contrasts = length(rows),
            n_direct_contrasts = count(row -> row.support === :direct, rows),
            n_network_contrasts = count(row -> row.support === :network, rows),
            n_disconnected_contrasts = n_disconnected,
            n_rater_network_components = network.n_components,
            rater_network_status = network.network_status,
            shared_unit_overlap_unit = overlap_unit,
            common_response_status,
            common_response_linking_verified =
                common_response_status === :verified_common_response,
            n_shared_unit_direct_contrasts = count(
                row -> row.shared_unit_overlap_support === :direct,
                rows,
            ),
            n_shared_unit_network_contrasts = count(
                row -> row.shared_unit_overlap_support === :network,
                rows,
            ),
            n_shared_unit_disconnected_contrasts = n_disconnected,
            n_shared_unit_overlap_components = network.n_components,
            shared_unit_overlap_network_status = network.network_status,
            model_identification_status =
                model_identification.n_components == 1 &&
                    model_identification.location_full_rank ?
                :full_rank_connected :
                model_identification.n_components > 1 ? :disconnected :
                :rank_deficient,
            n_model_graph_components = model_identification.n_components,
            location_design_rank = model_identification.location_rank,
            location_design_n_parameters =
                model_identification.n_location_parameters,
            location_design_full_rank =
                model_identification.location_full_rank,
            validation_passed = model_identification.validation_passed,
            model_identification_validation_source =
                model_identification.validation_source,
            n_model_identification_unsupported_contrasts =
                n_model_unsupported,
            n_inside_rope = count(
                row -> row.practical_equivalence === :inside_rope,
                rows,
            ),
            n_outside_rope = count(
                row -> row.practical_equivalence === :outside_rope,
                rows,
            ),
            n_mixed_rope = count(
                row -> row.practical_equivalence === :mixed,
                rows,
            ),
            interpretation_supported = n_model_unsupported == 0,
        ),
        policy = (;
            interval_type = :central_posterior,
            contrast_pairing = :draw_wise,
            shared_unit_overlap_role =
                :descriptive_requested_unit_overlap,
            common_response_linking_status = common_response_status,
            model_identification_role =
                :reference_constrained_additive_location_design,
            shared_unit_overlap_disconnection_does_not_imply_model_nonidentification =
                true,
            model_identification_source = :stored_validation_report,
            practical_margin_source = controls.severity_rope === nothing ?
                :not_requested : :user_declared,
            absence_of_evidence_is_not_practical_equivalence = true,
            bayes_factor = :not_computed,
        ),
        caveat = :severity_homogeneity_is_not_observed_score_agreement,
    )
end

function rater_homogeneity_summary(fit::MFRMFit; kwargs...)
    return rater_homogeneity_summary(fit.design, fit.draws; kwargs...)
end
