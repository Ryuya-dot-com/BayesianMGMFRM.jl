function _rating_design_audit_row(; audit::Symbol,
        status::Symbol,
        severity::Symbol = :info,
        facets = Symbol[],
        unit = missing,
        n_expected = missing,
        n_observed = missing,
        n_missing = missing,
        n_sparse = missing,
        n_repeated = missing,
        n_components = missing,
        min_count = missing,
        max_count = missing,
        note::Symbol = :none,
        details = (;))
    return (;
        schema = "bayesianmgmfrm.rating_design_audit_row.v1",
        audit,
        status,
        severity,
        facets = Tuple(facets),
        unit,
        n_expected,
        n_observed,
        n_missing,
        n_sparse,
        n_repeated,
        n_components,
        min_count,
        max_count,
        note,
        details,
    )
end

function _rating_design_facet_value(data::FacetData, facet::Symbol, row::Int)
    indexed = _facet(data, facet)
    indexed === nothing &&
        throw(ArgumentError("facet :$facet is not present in FacetData"))
    index, levels = indexed
    return levels[index[row]]
end

function _rating_design_pair_examples(pairs; limit::Int = 10)
    n = min(length(pairs), limit)
    return Tuple((; cell = first(pairs[index]), count = last(pairs[index]))
        for index in 1:n)
end

function _rating_design_cell_count_summary(data::FacetData, facets,
        min_sparse_cell_count::Int)
    isempty(facets) &&
        throw(ArgumentError("at least one facet is required"))
    level_counts = Int[]
    for facet in facets
        indexed = _facet(data, facet)
        indexed === nothing &&
            throw(ArgumentError("facet :$facet is not present in FacetData"))
        push!(level_counts, length(indexed[2]))
    end

    counts = Dict{Tuple,Int}()
    for row in 1:data.n
        key = Tuple(_rating_design_facet_value(data, facet, row) for facet in facets)
        counts[key] = get(counts, key, 0) + 1
    end
    pairs = sort(collect(counts); by = pair -> string(first(pair)))
    observed_counts = [last(pair) for pair in pairs]
    sparse_pairs = [pair for pair in pairs if last(pair) < min_sparse_cell_count]
    repeated_pairs = [pair for pair in pairs if last(pair) > 1]
    n_expected = prod(level_counts)
    n_observed = length(pairs)
    return (;
        facets = Tuple(facets),
        n_expected,
        n_observed,
        n_missing = max(n_expected - n_observed, 0),
        n_sparse = length(sparse_pairs),
        n_repeated = length(repeated_pairs),
        min_count = isempty(observed_counts) ? missing : minimum(observed_counts),
        max_count = isempty(observed_counts) ? missing : maximum(observed_counts),
        sparse_examples = _rating_design_pair_examples(sparse_pairs),
        repeated_examples = _rating_design_pair_examples(repeated_pairs),
        missingness_class = :unobserved_grid_cells,
        distinguishability =
            :structural_vs_accidental_not_distinguishable_from_observed_long_data,
    )
end

function _rating_design_components(data::FacetData, validation)
    raw_components = validation === nothing ?
        [[_label_node(data, node) for node in component]
         for component in _connected_components(data)] :
        validation.components
    components = [
        Tuple((; facet = facet, level) for (facet, level) in component)
        for component in raw_components
    ]
    return Tuple(components)
end

function _rating_design_optional_summary(data::FacetData)
    optional_facets = sort(collect(keys(data.optional)); by = string)
    time_order_facets = [facet for facet in optional_facets if facet === :occasion]
    descriptive_assignment_facets = [
        facet for facet in optional_facets
        if facet in (:group, :task, :form, :occasion)
    ]
    return (;
        optional_facets = Tuple(optional_facets),
        time_order_facets = Tuple(time_order_facets),
        descriptive_assignment_facets = Tuple(descriptive_assignment_facets),
        occasion_recorded = haskey(data.optional, :occasion),
    )
end

"""
    rating_design_audit(data_or_spec_or_design; unit = :person_item,
        min_shared_units = 1, min_sparse_cell_count = 2, view = :full)

Return a report-ready audit of the observed rating design before fitting. Rows
summarize person-rater-item graph components, rater overlap strength, anchor
coverage, complete-grid coverage for required facet combinations, repeated
ratings, sparse observed person-rater-item blocks, optional time/order fields,
and the interpretation limitation caused by unmodeled rater assignment.

The current `FacetData` contract stores complete observed long-format rows but
does not store an external planned-design table. Consequently the audit counts
unobserved complete-grid cells and explicitly marks structural versus
accidental missingness as not identified from the observed data alone.
`unit = :testlet_id` and `:person_testlet` are descriptive coverage units and
cannot be used for the audit's rater-link connectivity decision.
The compatibility default `view = :full` retains the complete audit record.
Use `view = :public` for a reader-facing projection with a public nested anchor
summary and without model-compiler status fields.
"""
function rating_design_audit(data_or_spec_or_design;
        unit::Symbol = :person_item,
        min_shared_units::Int = 1,
        min_sparse_cell_count::Int = 2,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    min_shared_units >= 1 ||
        throw(ArgumentError("min_shared_units must be positive"))
    min_sparse_cell_count >= 1 ||
        throw(ArgumentError("min_sparse_cell_count must be positive"))
    _require_rater_linking_unit(unit, :rating_design_audit)

    data = _facet_data(data_or_spec_or_design)
    spec = _facet_spec(data_or_spec_or_design)
    validation = _validation_report(data_or_spec_or_design)
    anchor_summary = anchor_linking_summary(
        data_or_spec_or_design;
        unit,
        min_shared_units)
    overlap_rows = anchor_summary.overlap_rows
    components = _rating_design_components(data, validation)
    n_graph_components = length(components)
    graph_status = n_graph_components <= 1 ? :connected : :disconnected

    optional = _rating_design_optional_summary(data)
    coverage_specs = (
        (:person, :rater),
        (:person, :item),
        (:rater, :item),
        (:person, :rater, :item),
    )
    coverage_summaries = [
        _rating_design_cell_count_summary(data, facets, min_sparse_cell_count)
        for facets in coverage_specs
    ]
    person_rater_item = coverage_summaries[end]

    rows = NamedTuple[]
    push!(rows, _rating_design_audit_row(;
        audit = :rating_graph_components,
        status = graph_status,
        severity = graph_status === :connected ? :info : :error,
        facets = (:person, :rater, :item),
        n_components = n_graph_components,
        min_count = isempty(components) ? missing : minimum(length, components),
        max_count = isempty(components) ? missing : maximum(length, components),
        note = graph_status === :connected ?
            :person_rater_item_graph_connected :
            :person_rater_item_graph_disconnected,
        details = (;
            component_sizes = Tuple(length(component) for component in components),
            components,
        ),
    ))

    rater_linking_status = anchor_summary.rater_linking_status
    push!(rows, _rating_design_audit_row(;
        audit = :rater_linking,
        status = rater_linking_status,
        severity = rater_linking_status === :disconnected ? :error : :info,
        facets = (:rater,),
        unit,
        n_observed = anchor_summary.n_links_at_or_above_min,
        n_missing = anchor_summary.n_zero_overlap_pairs,
        n_sparse = anchor_summary.n_weak_links,
        n_components = anchor_summary.n_rater_components,
        min_count = anchor_summary.minimum_shared_units,
        max_count = isempty(overlap_rows) ? missing :
            maximum(row.shared_units for row in overlap_rows),
        note = rater_linking_status === :disconnected ?
            :rater_overlap_below_minimum_disconnects_graph :
            :rater_overlap_links_graph_at_minimum_threshold,
        details = (;
            min_shared_units,
            rater_components = anchor_summary.rater_components,
            n_overlap_pairs = anchor_summary.n_overlap_pairs,
            overlap_rows,
        ),
    ))

    anchor_status = anchor_summary.anchor_status
    anchor_severity = anchor_summary.n_anchor_target_failures == 0 ? :info : :error
    push!(rows, _rating_design_audit_row(;
        audit = :anchor_coverage,
        status = anchor_status,
        severity = anchor_severity,
        facets = (:person, :rater, :item, :thresholds),
        n_observed = anchor_summary.n_anchors,
        n_missing = anchor_summary.n_anchor_target_failures,
        note = anchor_status === :not_declared ?
            :anchors_not_declared :
            anchor_status === :declared ?
                :declared_anchor_targets_found :
                :declared_anchor_targets_missing,
        details = (;
            n_hard_anchors = anchor_summary.n_hard_anchors,
            n_soft_anchors = anchor_summary.n_soft_anchors,
            anchor_rows = anchor_summary.anchor_rows,
            anchor_sensitivity_status = anchor_summary.anchor_sensitivity_status,
            anchor_sensitivity_passed = anchor_summary.anchor_sensitivity_passed,
        ),
    ))

    coverage_rows = NamedTuple[]
    for summary in coverage_summaries
        status = summary.n_missing == 0 ? :complete_observed_grid :
            :unobserved_grid_cells
        row = _rating_design_audit_row(;
            audit = :observed_cell_coverage,
            status,
            severity = summary.n_missing == 0 ? :info : :warning,
            facets = summary.facets,
            n_expected = summary.n_expected,
            n_observed = summary.n_observed,
            n_missing = summary.n_missing,
            min_count = summary.min_count,
            max_count = summary.max_count,
            note =
                :structural_vs_accidental_missingness_not_identified_by_observed_long_data,
            details = (;
                missingness_class = summary.missingness_class,
                distinguishability = summary.distinguishability,
            ),
        )
        push!(coverage_rows, row)
        push!(rows, row)
    end

    repeated_status = person_rater_item.n_repeated == 0 ? :none_detected :
        :repeated_ratings_detected
    push!(rows, _rating_design_audit_row(;
        audit = :repeated_person_rater_item_ratings,
        status = repeated_status,
        severity = person_rater_item.n_repeated == 0 ? :info : :warning,
        facets = (:person, :rater, :item),
        n_observed = person_rater_item.n_observed,
        n_repeated = person_rater_item.n_repeated,
        min_count = person_rater_item.min_count,
        max_count = person_rater_item.max_count,
        note = person_rater_item.n_repeated == 0 ?
            :no_repeated_person_rater_item_cells :
            :repeated_person_rater_item_cells_require_interpretation_policy,
        details = (;
            repeated_examples = person_rater_item.repeated_examples,
        ),
    ))

    sparse_status = person_rater_item.n_sparse == 0 ? :none_detected :
        :sparse_observed_cells_detected
    push!(rows, _rating_design_audit_row(;
        audit = :sparse_person_rater_item_blocks,
        status = sparse_status,
        severity = person_rater_item.n_sparse == 0 ? :info : :warning,
        facets = (:person, :rater, :item),
        n_observed = person_rater_item.n_observed,
        n_sparse = person_rater_item.n_sparse,
        min_count = person_rater_item.min_count,
        max_count = person_rater_item.max_count,
        note = person_rater_item.n_sparse == 0 ?
            :observed_person_rater_item_cells_meet_sparse_threshold :
            :observed_person_rater_item_cells_below_sparse_threshold,
        details = (;
            min_sparse_cell_count,
            sparse_examples = person_rater_item.sparse_examples,
        ),
    ))

    push!(rows, _rating_design_audit_row(;
        audit = :optional_time_order_fields,
        status = optional.occasion_recorded ? :recorded_not_modeled : :not_declared,
        severity = :info,
        facets = optional.optional_facets,
        n_observed = length(optional.time_order_facets),
        note = optional.occasion_recorded ?
            :occasion_recorded_as_metadata_not_likelihood_term :
            :time_or_order_field_not_declared,
        details = optional,
    ))

    push!(rows, _rating_design_audit_row(;
        audit = :nonignorable_assignment,
        status = :limitation,
        severity = :warning,
        facets = optional.descriptive_assignment_facets,
        note = :current_likelihood_does_not_model_rater_assignment,
        details = (;
            assignment_model = :not_included,
            descriptive_assignment_facets = optional.descriptive_assignment_facets,
            interpretation =
                :nonrandom_or_nonignorable_rater_assignment_requires_external_design_or_assignment_model,
        ),
    ))

    total_unobserved_grid_cells = sum(row.n_missing for row in coverage_rows)
    passed = graph_status !== :disconnected &&
        rater_linking_status !== :disconnected &&
        anchor_summary.passed === true
    full = (;
        schema = "bayesianmgmfrm.rating_design_audit.v1",
        object = :rating_design_audit,
        family = spec === nothing ? missing : spec.family,
        thresholds = spec === nothing ? missing : spec.thresholds,
        estimation_status = spec === nothing ? missing : spec.estimation_status,
        data_signature = validation === nothing ? _data_signature(data) :
            validation.data_signature,
        unit,
        min_shared_units,
        min_sparse_cell_count,
        status = passed ? :reviewed : :warning,
        passed,
        rows = Tuple(rows),
        n_rows = length(rows),
        overlap_rows,
        anchor_linking = anchor_summary,
        summary = (;
            passed,
            n_rows = length(rows),
            rating_graph_status = graph_status,
            n_rating_graph_components = n_graph_components,
            rater_linking_status,
            n_rater_components = anchor_summary.n_rater_components,
            anchor_status,
            n_anchors = anchor_summary.n_anchors,
            n_anchor_target_failures = anchor_summary.n_anchor_target_failures,
            n_unobserved_grid_cells = total_unobserved_grid_cells,
            n_repeated_person_rater_item_cells = person_rater_item.n_repeated,
            n_sparse_person_rater_item_cells = person_rater_item.n_sparse,
            structural_missingness_distinguishable = false,
            missingness_note =
                :structural_vs_accidental_missingness_not_identified_by_observed_long_data,
            optional_time_order_recorded = optional.occasion_recorded,
            nonignorable_assignment_flagged = true,
        ),
    )
    return view === :public ? _public_rating_design_audit(full) : full
end

function _public_rating_design_audit(audit)
    return (;
        schema = "bayesianmgmfrm.rating_design_audit_public.v1",
        object = :rating_design_audit,
        stability = :stable,
        claim_scope = :observed_rating_design_diagnostic_only,
        family = audit.family,
        thresholds = audit.thresholds,
        data_signature = audit.data_signature,
        unit = audit.unit,
        min_shared_units = audit.min_shared_units,
        min_sparse_cell_count = audit.min_sparse_cell_count,
        status = audit.status,
        passed = audit.passed,
        rows = audit.rows,
        n_rows = audit.n_rows,
        overlap_rows = audit.overlap_rows,
        anchor_linking = _public_anchor_linking_summary(audit.anchor_linking),
        summary = audit.summary,
    )
end

function _rating_design_check_row(row)
    return (;
        schema = "bayesianmgmfrm.rating_design_check_row.v1",
        check = row.audit,
        status = row.status,
        severity = row.severity,
        facets = row.facets,
        unit = row.unit,
        n_expected = row.n_expected,
        n_observed = row.n_observed,
        n_missing = row.n_missing,
        n_sparse = row.n_sparse,
        n_repeated = row.n_repeated,
        n_components = row.n_components,
        min_count = row.min_count,
        max_count = row.max_count,
        note = row.note,
        details = row.details,
    )
end

"""
    rating_design_check(data_or_spec_or_design; unit = :person_item,
        min_shared_units = 1, min_sparse_cell_count = 2, view = :full)

Check the observed rating design before fitting. The result describes graph
connectivity, overlap, coverage, repeated ratings, sparse cells, optional
time/order fields, and assignment limitations. Use `view = :public` for the
reader-facing projection.
"""
function rating_design_check(data_or_spec_or_design;
        unit::Symbol = :person_item,
        min_shared_units::Int = 1,
        min_sparse_cell_count::Int = 2,
        view::Symbol = :full)
    legacy = rating_design_audit(
        data_or_spec_or_design;
        unit,
        min_shared_units,
        min_sparse_cell_count,
        view,
    )
    schema = view === :public ?
        "bayesianmgmfrm.rating_design_check_public.v1" :
        "bayesianmgmfrm.rating_design_check.v1"
    return merge(legacy, (;
        schema,
        object = :rating_design_check,
        rows = Tuple(_rating_design_check_row(row) for row in legacy.rows),
    ))
end
