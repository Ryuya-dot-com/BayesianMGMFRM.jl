function _suggestion_for_issue(issue::ValidationIssue)
    code = issue.code
    code === :empty_data && return (
        action = :provide_ratings,
        suggestion = "Provide at least one complete long-format rating row before constructing a model specification.",
    )
    code === :single_observed_category && return (
        action = :review_single_category_fit_support,
        suggestion = "Preserve the observed scores and intended category scale. The current fitting interface rejects single-category data; this does not establish that a posterior under proper priors is undefined. Record the rejection in simulation studies without redrawing or recoding to bypass it.",
    )
    code === :unused_interior_category && return (
        action = :inspect_scale_use,
        suggestion = "Inspect skipped interior categories; consider collapsing sparse categories or documenting that the unused category is structurally possible.",
    )
    code === :unobserved_declared_endpoint && return (
        action = :verify_declared_scale_and_threshold_support,
        suggestion = "Verify that the declared endpoint is structurally possible, then inspect category coverage and prior sensitivity; do not silently shrink the intended score scale.",
    )
    code === :single_item_category && return (
        action = :simplify_thresholds_or_collect_data,
        suggestion = "Items using only one category weakly inform partial-credit thresholds; collect more ratings, collapse categories, or prefer a simpler threshold structure.",
    )
    code === :unobserved_item_category && return (
        action = :check_threshold_support,
        suggestion = "Unobserved item/category cells can make partial-credit thresholds weakly informed; inspect category coverage before fitting item-specific steps.",
    )
    code === :extreme_person_score_pattern && return (
        action = :run_extreme_response_prior_sensitivity,
        suggestion = "Treat all-minimum or all-maximum person patterns as finite but one-sided information; inspect posterior/prior overlap and repeat the fit under predeclared priors.",
    )
    code === :constant_rater_score_pattern && return (
        action = :inspect_rater_assignment_and_prior_sensitivity,
        suggestion = "Inspect assignment overlap and severity; for generalized families, also check separation from rater consistency under predeclared prior regimes.",
    )
    code === :singleton_facet_level && return (
        action = :collect_more_linking_data,
        suggestion = "Facet levels with one rating are weakly linked; collect more ratings, merge levels, or keep the level out of modelled effects.",
    )
    code === :disconnected_design && return (
        action = :add_links_or_split_design,
        suggestion = "Add observed ratings that share persons, raters, or items across components; otherwise analyze connected components separately. Individual parameter anchors do not create graph links, and group-anchored component alignment is not implemented.",
    )
    code === :rank_deficient_design && return (
        action = :simplify_or_relink_design,
        suggestion = "The current reference-constrained location design is rank deficient; add linking observations or remove aliased facet effects.",
    )
    code === :invalid_bias_term && return (
        action = :fix_bias_syntax,
        suggestion = "Use two-facet tuples such as (:rater, :group) for bias/DFF validation terms.",
    )
    code === :unknown_bias_facet && return (
        action = :check_facet_roles,
        suggestion = "Bias/DFF terms must reference required facets or optional roles supplied to FacetData.",
    )
    code === :empty_dff_cell && return (
        action = :pool_or_remove_dff_term,
        suggestion = "Empty DFF cells cannot support unpooled interaction estimates; collect data, collapse levels, use hierarchical pooling, or remove the term.",
    )
    code === :sparse_dff_cell && return (
        action = :pool_or_collect_dff_data,
        suggestion = "Sparse DFF cells require caution; collect more data, collapse levels, or use hierarchical shrinkage with sensitivity checks.",
    )
    code === :potential_dff_confounding && return (
        action = :inspect_dff_confounding,
        suggestion = "A facet level is observed with only one level of the paired DFF facet; improve crossing or avoid interpreting the DFF contrast.",
    )
    code === :facet_person_disconnected_subsets && return (
        action = :add_bridging_ratings_or_split_subsets,
        suggestion = "Add overlapping ratings where common examinees bridge disconnected facet subsets, supply independently calibrated anchors, or analyze subsets separately.",
    )
    code === :score_conditioned_disconnected_design && return (
        action = :add_interior_bridging_ratings_or_use_mmle_or_bayes,
        suggestion = "After excluding extreme-scoring persons, the residual design is disconnected or loses facet levels; add interior bridging ratings, or use MMLE, Bayesian NUTS with proper priors, or positive extreme_adjustment.",
    )
    code === :one_sided_score_separation && return (
        action = :add_two_way_bridging_ratings_or_use_mmle_or_bayes,
        suggestion = "A separating recession direction was demonstrated in the compiled free coordinates (no finite unpenalized JMLE); add two-way bridging ratings or use MMLE / Bayesian estimation.",
    )
    code === :thin_facet_bridge && return (
        action = :strengthen_linking_bridge,
        suggestion = "Increase shared interior examinees across the weakest facet bridge; under generalized/GMFRM slopes, prefer high-consistency raters on bridge performances.",
    )
    code === :extreme_facet_level && return (
        action = :inspect_extreme_facet_levels,
        suggestion = "Free extreme facet levels have unbounded unpenalized ML estimates and prior-sensitive Bayesian estimates; inspect extreme_facet_levels or anchor if externally calibrated.",
    )
    code === :sparse_category_cell && return (
        action = :inspect_category_support,
        suggestion = "Sparse category counts yield imprecise or prior-sensitive step thresholds; inspect category diagnostics, simplify steps, or run prior sensitivity checks.",
    )
    code === :empirical_category_order_inversion && return (
        action = :inspect_step_ordering,
        suggestion = "Empirical mean ability proxy decreases across adjacent categories; inspect category definitions and posterior threshold ordering.",
    )
    code === :nested_or_aliased_facets && return (
        action = :resolve_facet_nesting_or_aliasing,
        suggestion = "Inspect validate_design(spec).nesting_and_aliasing for estimable vs. aliased contrasts; add bridging ratings, supply independently calibrated anchors, declare an explicit within-panel mean convention (`fixed_calibration = (groups = ...)`), or collapse confounded roles into a composite facet.",
    )
    code === :within_event_local_dependence_unmodeled && return (
        action = :audit_within_event_dependence,
        suggestion = "Multiple criteria share a rater-response event under the conditional-independence baseline; inspect dependence_units and consider response random effects, JointRatings, or StarAssociation if local dependence is substantive.",
    )
    return (
        action = :inspect_issue,
        suggestion = "Inspect this validation issue before fitting a more complex model.",
    )
end

"""
    validation_suggestions(report::ValidationReport)
    validation_suggestions(report::NamedTuple)
    validation_suggestions(issue::ValidationIssue)

Return machine-readable next-step suggestions for validation issues. Suggestions
are intentionally conservative and are meant to guide design repair or model
simplification before fitting more complex MFRM/GMFRM/MGMFRM specifications.
"""
function validation_suggestions(issue::ValidationIssue)
    suggestion = _suggestion_for_issue(issue)
    return (;
        code = issue.code,
        severity = issue.severity,
        action = suggestion.action,
        message = issue.message,
        suggestion = suggestion.suggestion,
        context = copy(issue.context),
    )
end

function validation_suggestions(report::ValidationReport)
    return [validation_suggestions(issue) for issue in report.issues]
end

function validation_suggestions(report::NamedTuple)
    hasproperty(report, :issues) ||
        throw(ArgumentError("validation_suggestions expects a ValidationReport or a validate_design result containing `issues`"))
    return [validation_suggestions(issue) for issue in report.issues]
end

function _median_count(values::Vector{Int})
    isempty(values) && return 0.0
    sorted = sort(values)
    n = length(sorted)
    mid = n ÷ 2
    return isodd(n) ? Float64(sorted[mid + 1]) : (sorted[mid] + sorted[mid + 1]) / 2
end

function _coverage_roles(data::FacetData)
    roles = Any[
        (:person, data.person, data.person_levels),
        (:rater, data.rater, data.rater_levels),
        (:item, data.item, data.item_levels),
    ]
    for role in sort(collect(keys(data.optional)); by = string)
        push!(roles, (role, data.optional[role], data.optional_levels[role]))
    end
    return roles
end

function _validation_summary(report)
    report === nothing && return nothing
    n_error = count(issue -> issue.severity === :error, report.issues)
    n_warning = count(issue -> issue.severity === :warning, report.issues)
    return (passed = report.passed, n_errors = n_error, n_warnings = n_warning)
end

"""
    coverage_summary(data_or_spec)

Return fit-independent coverage summaries for long-format rating data. The
result is a `NamedTuple` containing rating counts, category counts, long-form
facet-level counts, compact facet summaries, and validation status when a
`FacetSpec` or `FacetDesign` is supplied.
"""
function coverage_summary(data_or_spec)
    data = _facet_data(data_or_spec)
    facet_counts = NamedTuple[]
    facet_summary = NamedTuple[]
    for (facet, index, levels) in _coverage_roles(data)
        counts = _counts(index, levels)
        values = [counts[level] for level in levels]
        for level in levels
            count = counts[level]
            push!(facet_counts, (;
                facet,
                level,
                count,
                proportion = data.n == 0 ? 0.0 : count / data.n,
            ))
        end
        push!(facet_summary, (;
            facet,
            n_levels = length(levels),
            min_count = isempty(values) ? 0 : minimum(values),
            median_count = _median_count(values),
            max_count = isempty(values) ? 0 : maximum(values),
            singleton_count = count(==(1), values),
            total_count = sum(values),
        ))
    end

    category_counts = NamedTuple[]
    category_count_map = _category_counts(data)
    for category in data.category_levels
        count = category_count_map[category]
        push!(category_counts, (;
            category,
            count,
            proportion = data.n == 0 ? 0.0 : count / data.n,
        ))
    end

    return (;
        n_ratings = data.n,
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        n_categories = length(data.category_levels),
        facet_summary,
        facet_counts,
        category_counts,
        validation = _validation_summary(_validation_report(data_or_spec)),
    )
end

"""
    coverage_matrix(data_or_spec; rows = :rater, columns = :person)

Return a facet-by-facet rating-count matrix for heat maps and design coverage
checks. `rows` and `columns` may be required facets (`:person`, `:rater`,
`:item`) or optional metadata roles present in `FacetData`, such as `:group`,
`:task`, `:form`, `:occasion`, `:response_id`, or `:testlet_id`.
"""
function coverage_matrix(data_or_spec; rows::Symbol = :rater, columns::Symbol = :person)
    data = _facet_data(data_or_spec)
    row_facet = _facet(data, rows)
    row_facet === nothing &&
        throw(ArgumentError("rows = :$rows is not present in FacetData"))
    column_facet = _facet(data, columns)
    column_facet === nothing &&
        throw(ArgumentError("columns = :$columns is not present in FacetData"))

    row_index, row_levels = row_facet
    column_index, column_levels = column_facet
    counts = zeros(Int, length(row_levels), length(column_levels))
    for n in 1:data.n
        counts[row_index[n], column_index[n]] += 1
    end

    return (;
        row_facet = rows,
        column_facet = columns,
        row_levels = copy(row_levels),
        column_levels = copy(column_levels),
        counts,
    )
end

function _overlap_unit(data::FacetData, row::Int, unit::Symbol)
    unit === :person && return (data.person[row],)
    unit === :item && return (data.item[row],)
    unit === :person_item && return (data.person[row], data.item[row])
    if unit === :task
        haskey(data.optional, :task) ||
            throw(ArgumentError("unit = :task requires FacetData(...; task = ...)"))
        return (data.optional[:task][row],)
    end
    if unit === :person_task
        haskey(data.optional, :task) ||
            throw(ArgumentError("unit = :person_task requires FacetData(...; task = ...)"))
        return (data.person[row], data.optional[:task][row])
    end
    if unit === :response_id
        haskey(data.optional, :response_id) ||
            throw(ArgumentError("unit = :response_id requires FacetData(...; response_id = ...)"))
        return (data.optional[:response_id][row],)
    end
    if unit === :testlet_id
        haskey(data.optional, :testlet_id) ||
            throw(ArgumentError("unit = :testlet_id requires FacetData(...; testlet_id = ...)"))
        return (data.optional[:testlet_id][row],)
    end
    if unit === :person_testlet
        haskey(data.optional, :testlet_id) ||
            throw(ArgumentError("unit = :person_testlet requires FacetData(...; testlet_id = ...)"))
        return (data.person[row], data.optional[:testlet_id][row])
    end
    if unit === :response_item
        haskey(data.optional, :response_id) ||
            throw(ArgumentError("unit = :response_item requires FacetData(...; response_id = ...)"))
        return (data.optional[:response_id][row], data.item[row])
    end
    throw(ArgumentError(
        "unit must be one of :person, :item, :person_item, :task, " *
        ":person_task, :response_id, :testlet_id, :person_testlet, or :response_item"))
end

function _rater_overlap_unit_metadata(unit::Symbol)
    if unit in (:testlet_id, :person_testlet)
        return (;
            overlap_purpose = :descriptive_coverage,
            rater_linking_eligible = false,
            interpretation =
                :shared_testlet_coverage_does_not_establish_common_response_linking,
        )
    elseif unit in (:response_id, :response_item)
        return (;
            overlap_purpose = :common_response_linking,
            rater_linking_eligible = true,
            interpretation = :shared_response_overlap_can_support_rater_linking,
        )
    end
    return (;)
end

function _require_rater_linking_unit(unit::Symbol, caller::Symbol)
    unit in (:testlet_id, :person_testlet) || return nothing
    throw(ArgumentError(
        "$(String(caller)) cannot use unit = :$unit for rater-link " *
        "connectivity because it is descriptive cluster coverage only; " *
        "use rater_overlap(...; unit = :$unit) for coverage counts, or " *
        "use unit = :response_id or :response_item for common-response linking"))
end

"""
    rater_overlap(data_or_spec; unit = :person_item)

Return pairwise rater-overlap data for coverage and linking plots. `unit`
controls what counts as a shared rated unit and may be `:person`, `:item`,
`:person_item`, `:task`, `:person_task`, `:response_id`, `:testlet_id`,
`:person_testlet`, or `:response_item`. Metadata-based units require the
corresponding optional role in `FacetData`. Rows for `:testlet_id` and
`:person_testlet` are explicitly marked as descriptive coverage and are not
eligible for rater-link connectivity. Rows for `:response_id` and
`:response_item` are marked as common-response linking units.
"""
function rater_overlap(data_or_spec; unit::Symbol = :person_item)
    data = _facet_data(data_or_spec)
    unit_metadata = _rater_overlap_unit_metadata(unit)
    unit_sets = [Set{Any}() for _ in data.rater_levels]
    for row in 1:data.n
        push!(unit_sets[data.rater[row]], _overlap_unit(data, row, unit))
    end

    rows = NamedTuple[]
    for a in 1:(length(data.rater_levels) - 1), b in (a + 1):length(data.rater_levels)
        shared = intersect(unit_sets[a], unit_sets[b])
        all_units = union(unit_sets[a], unit_sets[b])
        push!(rows, (;
            rater_a = data.rater_levels[a],
            rater_b = data.rater_levels[b],
            unit,
            n_units_a = length(unit_sets[a]),
            n_units_b = length(unit_sets[b]),
            shared_units = length(shared),
            union_units = length(all_units),
            jaccard = isempty(all_units) ? 0.0 : length(shared) / length(all_units),
            unit_metadata...,
        ))
    end
    return rows
end

function _anchor_target(anchor)
    target = _anchor_symbol(anchor, (:level, :facet_level, :target, :parameter))
    return target === nothing ? missing : target
end

function _anchor_block_levels(data::FacetData, block::Symbol)
    block in (:person, :person_location, :persons) && return data.person_levels
    block in (:rater, :rater_severity, :raters) && return data.rater_levels
    block in (:item, :item_difficulty, :items) && return data.item_levels
    block in (:thresholds, :threshold_steps, :steps) && return data.category_levels
    return Any[]
end

function _anchor_linking_anchor_rows(spec, data::FacetData)
    spec === nothing && return NamedTuple[]
    rows = NamedTuple[]
    for (index, anchor) in pairs(spec.anchors)
        target = _anchor_target(anchor)
        levels = _anchor_block_levels(data, anchor.block)
        target_found = ismissing(target) ? missing :
            any(level -> isequal(level, target), levels)
        passed = ismissing(target_found) || target_found
        push!(rows, (;
            anchor_index = index,
            block = anchor.block,
            target,
            target_found,
            anchor_type = anchor.anchor_type,
            anchor_value = anchor.value,
            anchor_scale = anchor.anchor_scale,
            implementation_status = spec.estimation_status === :fit_supported &&
                anchor.anchor_type === :hard_anchor ? :implemented : :specified_only,
            passed,
            status = passed ? :declared : :anchor_target_not_in_data,
        ))
    end
    return rows
end

function _anchor_link_root!(parent::Vector{Int}, index::Int)
    while parent[index] != index
        parent[index] = parent[parent[index]]
        index = parent[index]
    end
    return index
end

function _anchor_link_union!(parent::Vector{Int}, a::Int, b::Int)
    root_a = _anchor_link_root!(parent, a)
    root_b = _anchor_link_root!(parent, b)
    root_a == root_b && return nothing
    parent[root_b] = root_a
    return nothing
end

function _rater_level_index(levels, level)
    index = findfirst(candidate -> isequal(candidate, level), levels)
    index === nothing &&
        throw(ArgumentError("rater overlap row references an unknown rater level"))
    return index
end

function _rater_link_components(data::FacetData, overlap_rows, min_shared_units::Int)
    n_raters = length(data.rater_levels)
    parent = collect(1:n_raters)
    for row in overlap_rows
        row.shared_units >= min_shared_units || continue
        a = _rater_level_index(data.rater_levels, row.rater_a)
        b = _rater_level_index(data.rater_levels, row.rater_b)
        _anchor_link_union!(parent, a, b)
    end

    grouped = Dict{Int,Vector{Any}}()
    for index in 1:n_raters
        root = _anchor_link_root!(parent, index)
        push!(get!(grouped, root, Any[]), data.rater_levels[index])
    end
    components = collect(values(grouped))
    for component in components
        sort!(component; by = string)
    end
    sort!(components; by = component -> isempty(component) ? "" : string(first(component)))
    return Tuple(Tuple(component) for component in components)
end

function _anchor_sensitivity_status(sensitivity_rows)
    sensitivity_rows === nothing && return (;
        status = :not_supplied,
        passed = missing,
        n_rows = 0,
        missing_required_axes = (:anchor,),
        summary = nothing,
    )
    summary = sensitivity_comparison_summary(sensitivity_rows; required_axes = (:anchor,))
    return (;
        status = summary.passed ? :complete : :incomplete,
        passed = summary.passed,
        n_rows = summary.n_rows,
        missing_required_axes = summary.missing_required_axes,
        summary,
    )
end

"""
    anchor_linking_summary(data_or_spec; unit = :person_item,
        min_shared_units = 1, sensitivity_rows = nothing, view = :full)

Return a compact anchoring and rater-linking diagnostic summary. The summary
combines declared hard/soft anchor rows from a `FacetSpec` or `FacetDesign`,
pairwise rater-overlap connectivity for the chosen linking `unit`, and an
optional anchor-axis sensitivity coverage check from
[`sensitivity_comparison_summary`](@ref).

This is a report and design-review helper. It does not fit hard anchors, turn
soft anchors into priors, estimate linking constants, or create sensitivity
refits. Use it to document whether declared anchors are internally consistent
and describe rater overlap under the declared link rule. Connectivity alone does
not establish adequate information, precision or a suitable rating design.
`unit = :testlet_id` and `:person_testlet` are descriptive coverage units and
are rejected here; use `rater_overlap` to inspect them without a linking claim.
The compatibility default `view = :full` retains the complete design-review
record. Use `view = :public` for a concise diagnostic projection without
workflow-control fields or attached sensitivity records.
"""
function anchor_linking_summary(data_or_spec; unit::Symbol = :person_item,
        min_shared_units::Int = 1,
        sensitivity_rows = nothing,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    min_shared_units >= 1 ||
        throw(ArgumentError("min_shared_units must be positive"))
    _require_rater_linking_unit(unit, :anchor_linking_summary)
    data = _facet_data(data_or_spec)
    spec = _facet_spec(data_or_spec)
    validation = _validation_report(data_or_spec)
    overlap_rows = rater_overlap(data; unit)
    components = _rater_link_components(data, overlap_rows, min_shared_units)
    n_raters = length(data.rater_levels)
    n_components = length(components)
    n_links = count(row -> row.shared_units >= min_shared_units, overlap_rows)
    n_weak_links = count(row -> 0 < row.shared_units < min_shared_units, overlap_rows)
    n_zero_overlap_pairs = count(row -> row.shared_units == 0, overlap_rows)
    rater_linking_status = n_raters <= 1 ? :single_rater :
        n_components == 1 ? :connected : :disconnected

    anchor_rows = _anchor_linking_anchor_rows(spec, data)
    n_hard_anchors = count(row -> row.anchor_type === :hard_anchor, anchor_rows)
    n_soft_anchors = count(row -> row.anchor_type === :soft_anchor, anchor_rows)
    n_anchor_target_failures = count(row -> !row.passed, anchor_rows)
    anchor_status = isempty(anchor_rows) ? :not_declared :
        n_anchor_target_failures == 0 ? :declared : :invalid_targets
    sensitivity = _anchor_sensitivity_status(sensitivity_rows)
    linking_passed = rater_linking_status !== :disconnected
    sensitivity_passed = sensitivity_rows === nothing || sensitivity.passed === true

    full = (;
        schema = "bayesianmgmfrm.anchor_linking_summary.v1",
        object = :anchor_linking_summary,
        family = spec === nothing ? missing : spec.family,
        thresholds = spec === nothing ? missing : spec.thresholds,
        estimation_status = spec === nothing ? missing : spec.estimation_status,
        data_signature = validation === nothing ? _data_signature(data) :
            validation.data_signature,
        unit,
        min_shared_units,
        n_raters,
        rater_linking_status,
        n_rater_components = n_components,
        rater_components = components,
        largest_rater_component = isempty(components) ? 0 : maximum(length, components),
        n_overlap_pairs = length(overlap_rows),
        n_links_at_or_above_min = n_links,
        n_weak_links,
        n_zero_overlap_pairs,
        minimum_shared_units = isempty(overlap_rows) ? missing :
            minimum(row.shared_units for row in overlap_rows),
        overlap_rows = Tuple(overlap_rows),
        anchor_status,
        n_anchors = length(anchor_rows),
        n_hard_anchors,
        n_soft_anchors,
        n_anchor_target_failures,
        anchor_rows = Tuple(anchor_rows),
        anchor_sensitivity_status = sensitivity.status,
        anchor_sensitivity_passed = sensitivity.passed,
        anchor_sensitivity_n_rows = sensitivity.n_rows,
        anchor_sensitivity_missing_required_axes = sensitivity.missing_required_axes,
        anchor_sensitivity_summary = sensitivity.summary,
        passed = linking_passed && n_anchor_target_failures == 0 && sensitivity_passed,
        caveat = :diagnostic_summary_not_anchor_refit_or_linking_estimator,
        next_gate = :predeclared_anchor_sensitivity_case_study,
    )
    return view === :public ? _public_anchor_linking_summary(full) : full
end

function _public_anchor_linking_summary(summary)
    return (;
        schema = "bayesianmgmfrm.anchor_linking_summary_public.v1",
        object = :anchor_linking_summary,
        stability = :stable,
        claim_scope = :anchor_and_rater_linking_diagnostic_only,
        family = summary.family,
        thresholds = summary.thresholds,
        data_signature = summary.data_signature,
        unit = summary.unit,
        min_shared_units = summary.min_shared_units,
        n_raters = summary.n_raters,
        rater_linking_status = summary.rater_linking_status,
        n_rater_components = summary.n_rater_components,
        rater_components = summary.rater_components,
        largest_rater_component = summary.largest_rater_component,
        n_overlap_pairs = summary.n_overlap_pairs,
        n_links_at_or_above_min = summary.n_links_at_or_above_min,
        n_weak_links = summary.n_weak_links,
        n_zero_overlap_pairs = summary.n_zero_overlap_pairs,
        minimum_shared_units = summary.minimum_shared_units,
        overlap_rows = summary.overlap_rows,
        anchor_status = summary.anchor_status,
        n_anchors = summary.n_anchors,
        n_hard_anchors = summary.n_hard_anchors,
        n_soft_anchors = summary.n_soft_anchors,
        n_anchor_target_failures = summary.n_anchor_target_failures,
        anchor_rows = summary.anchor_rows,
        anchor_sensitivity_status = summary.anchor_sensitivity_status,
        anchor_sensitivity_passed = summary.anchor_sensitivity_passed,
        anchor_sensitivity_n_rows = summary.anchor_sensitivity_n_rows,
        anchor_sensitivity_missing_required_axes =
            summary.anchor_sensitivity_missing_required_axes,
        passed = summary.passed,
    )
end
