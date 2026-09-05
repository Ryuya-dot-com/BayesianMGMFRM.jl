# Sampler-free audits for sparse and boundary ordinal-response patterns.

function _ordinal_pattern_rows(data::FacetData, facet::Symbol)
    facet_data = _facet(data, facet)
    facet_data === nothing &&
        throw(ArgumentError("facet :$facet is not present in FacetData"))
    index, levels = facet_data
    categories = data.category_levels
    scale_minimum = isempty(categories) ? missing : first(categories)
    scale_maximum = isempty(categories) ? missing : last(categories)
    rows = NamedTuple[]
    score_buckets = [Int[] for _ in levels]
    for observation in eachindex(index)
        push!(score_buckets[index[observation]], data.score[observation])
    end

    for (level_index, level) in pairs(levels)
        scores = score_buckets[level_index]
        counts = Dict(category => count(==(category), scores)
            for category in categories)
        used = [category for category in categories if counts[category] > 0]
        unused = [category for category in categories if counts[category] == 0]
        constant_score = length(used) == 1
        all_minimum = constant_score && !isempty(categories) &&
            only(used) == scale_minimum
        all_maximum = constant_score && !isempty(categories) &&
            only(used) == scale_maximum
        push!(rows, (;
            facet,
            level,
            n_observations = length(scores),
            n_categories_used = length(used),
            categories_used = Tuple(used),
            unused_categories = Tuple(unused),
            category_counts = counts,
            score_minimum = isempty(scores) ? missing : minimum(scores),
            score_maximum = isempty(scores) ? missing : maximum(scores),
            score_range = isempty(scores) ? missing : maximum(scores) - minimum(scores),
            constant_score,
            all_minimum,
            all_maximum,
            boundary_extreme = all_minimum || all_maximum,
        ))
    end
    return rows
end

"""
    ordinal_response_pattern_audit(data_or_spec_or_design;
                                   minimum_pattern_observations = 2)

Return a sampler-free audit of category gaps and constant or boundary response
patterns by person, rater, and item. The audit distinguishes a structural
ordered-response failure (only one category in the whole dataset) from stress
conditions that can be fitted with proper priors but may be weakly informed.

By default, `FacetData` infers the category scale as the contiguous integer
range between the observed minimum and maximum. Pass `category_levels` to the
constructor when an intended endpoint or other structurally possible category
may be absent from the realized data. The audit then reports intended,
observed, interior-unobserved, and endpoint-unobserved categories separately.
"""
function ordinal_response_pattern_audit(
        object;
        minimum_pattern_observations::Int = 2)
    minimum_pattern_observations >= 1 ||
        throw(ArgumentError("minimum_pattern_observations must be positive"))
    data = _facet_data(object)
    categories = data.category_levels
    counts = _category_counts(data)
    category_scale = _category_scale_contract(data)
    observed = category_scale.observed_levels
    unused = category_scale.unobserved_levels
    unused_interior = category_scale.unobserved_interior_levels
    unused_endpoints = category_scale.unobserved_endpoint_levels

    person_rows = _ordinal_pattern_rows(data, :person)
    rater_rows = _ordinal_pattern_rows(data, :rater)
    item_rows = _ordinal_pattern_rows(data, :item)
    eligible_person_extremes = [row for row in person_rows
        if row.n_observations >= minimum_pattern_observations && row.boundary_extreme]
    eligible_constant_raters = [row for row in rater_rows
        if row.n_observations >= minimum_pattern_observations && row.constant_score]
    eligible_boundary_raters = [row for row in eligible_constant_raters
        if row.boundary_extreme]

    fit_prohibited = data.n == 0 || length(observed) < 2
    stress_required = !fit_prohibited && (
        !isempty(unused) ||
        !isempty(eligible_person_extremes) ||
        !isempty(eligible_constant_raters)
    )
    status = fit_prohibited ? :structural_error :
        stress_required ? :stress_review_required : :no_pattern_flag

    return (;
        schema = "bayesianmgmfrm.ordinal_response_pattern_audit.v1",
        object = :ordinal_response_pattern_audit,
        status,
        minimum_pattern_observations,
        fit_prohibited,
        stress_required,
        category_scale = (;
            levels = Tuple(categories),
            source = category_scale.source,
            intended_levels = Tuple(category_scale.intended_levels),
            observed_levels = Tuple(observed),
            unobserved_interior_categories = Tuple(unused_interior),
            unobserved_endpoint_categories = Tuple(unused_endpoints),
            unobserved_endpoints_detectable =
                category_scale.endpoints_explicitly_declared,
            note = category_scale.endpoints_explicitly_declared ?
                :declared_scale_preserved :
                :declare_category_levels_to_detect_unobserved_endpoints,
        ),
        overall = (;
            n_observations = data.n,
            categories_observed = Tuple(observed),
            unused_categories = Tuple(unused),
            category_counts = counts,
            single_observed_category = length(observed) < 2,
        ),
        facets = (;
            person = person_rows,
            rater = rater_rows,
            item = item_rows,
        ),
        flags = (;
            extreme_person_levels = Tuple(row.level for row in eligible_person_extremes),
            constant_rater_levels = Tuple(row.level for row in eligible_constant_raters),
            boundary_rater_levels = Tuple(row.level for row in eligible_boundary_raters),
            n_extreme_person_levels = length(eligible_person_extremes),
            n_constant_rater_levels = length(eligible_constant_raters),
            n_boundary_rater_levels = length(eligible_boundary_raters),
        ),
        interpretation = (;
            unused_interior_category = :adjacent_step_transitions_weakly_separated_check_prior_sensitivity,
            extreme_person = :one_sided_ability_information_do_not_interpret_as_infinite_ability,
            constant_rater = :severity_and_generalized_consistency_may_be_weakly_separated_check_assignment_and_priors,
            global_single_category = :ordered_response_likelihood_not_estimable,
        ),
        decision_policy = :audit_and_stress_axis_not_scientific_pass_fail_threshold,
    )
end

function _validate_ordinal_response_patterns!(issues, data::FacetData)
    audit = ordinal_response_pattern_audit(data)
    audit.fit_prohibited && return nothing
    extreme_people = audit.flags.extreme_person_levels
    if !isempty(extreme_people)
        push!(issues, ValidationIssue(
            :extreme_person_score_pattern,
            :warning,
            "$(length(extreme_people)) person level(s) have only boundary-category ratings; ability recovery may be one-sided and prior-sensitive",
            context = Dict{Symbol,Any}(
                :levels => collect(extreme_people),
                :minimum_observations => audit.minimum_pattern_observations,
            ),
        ))
    end

    constant_raters = audit.flags.constant_rater_levels
    if !isempty(constant_raters)
        push!(issues, ValidationIssue(
            :constant_rater_score_pattern,
            :warning,
            "$(length(constant_raters)) rater level(s) use one score category only; inspect severity and, for generalized families, rater-consistency separation",
            context = Dict{Symbol,Any}(
                :levels => collect(constant_raters),
                :boundary_levels => collect(audit.flags.boundary_rater_levels),
                :minimum_observations => audit.minimum_pattern_observations,
            ),
        ))
    end
    return nothing
end
