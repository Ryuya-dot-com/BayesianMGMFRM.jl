# local_dependence_simulation.jl -- LD1a planning grid and data adapter

using SHA

const _LD1_PROFILE = :ld1_preflight_v1
const _LD1_PHASE_NAMESPACE_WIDTH = 10_000_000
const _LD1_PHASE_OFFSETS = (smoke = 0, pilot = 10_000_000,
    evaluation = 20_000_000)
const _LD1_MAGNITUDE_SCALES = (;
    zero = 0.0,
    near_zero = 0.05,
    small = 0.20,
    moderate = 0.50,
    large = 0.80,
)

const _LD1_SCENARIOS = (
    (;
        scenario_id = :null_same_rater,
        matched_set_id = :same_rater_core,
        mechanism = :null,
        magnitude_label = :zero,
        design = :same_rater,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :null_fully_crossed_raters,
        matched_set_id = :fully_crossed_core,
        mechanism = :null,
        magnitude_label = :zero,
        design = :fully_crossed_raters,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :null_mixed_testlet_applicability,
        matched_set_id = :mixed_applicability,
        mechanism = :null,
        magnitude_label = :zero,
        design = :mixed_testlet_applicability,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :null_support_below_minimum,
        matched_set_id = :pair_support_boundary,
        mechanism = :null,
        magnitude_label = :zero,
        design = :same_rater,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = false,
        n_persons_override = 19,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :null_support_at_minimum,
        matched_set_id = :pair_support_boundary,
        mechanism = :null,
        magnitude_label = :zero,
        design = :same_rater,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = true,
        n_persons_override = 20,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :scalar_testlet_near_zero,
        matched_set_id = :same_rater_core,
        mechanism = :person_testlet,
        magnitude_label = :near_zero,
        design = :same_rater,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :scalar_testlet_small,
        matched_set_id = :same_rater_core,
        mechanism = :person_testlet,
        magnitude_label = :small,
        design = :same_rater,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :scalar_testlet_moderate,
        matched_set_id = :same_rater_core,
        mechanism = :person_testlet,
        magnitude_label = :moderate,
        design = :same_rater,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :scalar_testlet_large,
        matched_set_id = :same_rater_core,
        mechanism = :person_testlet,
        magnitude_label = :large,
        design = :same_rater,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :scalar_testlet_connected_sparse,
        matched_set_id = :connected_sparse,
        mechanism = :person_testlet,
        magnitude_label = :moderate,
        design = :connected_sparse,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = true,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :scalar_testlet_one_indicator_rejection,
        matched_set_id = :structural_rejection,
        mechanism = :person_testlet,
        magnitude_label = :moderate,
        design = :same_rater,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = false,
        expected_diagnostic_pair_support = false,
        n_persons_override = 0,
        items_per_testlet_override = 1,
    ),
    (;
        scenario_id = :scalar_testlet_one_testlet_per_person_rejection,
        matched_set_id = :structural_rejection,
        mechanism = :person_testlet,
        magnitude_label = :moderate,
        design = :one_testlet_per_person,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = false,
        expected_diagnostic_pair_support = false,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :scalar_testlet_disconnected_rejection,
        matched_set_id = :structural_rejection,
        mechanism = :person_testlet,
        magnitude_label = :moderate,
        design = :disconnected_blocks,
        assignment = :task_nested,
        order = :testlet_blocked,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = false,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :rater_response_halo_crossed,
        matched_set_id = :fully_crossed_core,
        mechanism = :rater_response_halo,
        magnitude_label = :moderate,
        design = :fully_crossed_raters,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:rater_response_halo,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :rater_task_crossed,
        matched_set_id = :fully_crossed_core,
        mechanism = :rater_task_severity,
        magnitude_label = :moderate,
        design = :fully_crossed_raters,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:rater_task,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :rater_task_nested_rejection,
        matched_set_id = :structural_rejection,
        mechanism = :rater_task_severity,
        magnitude_label = :moderate,
        design = :same_rater,
        assignment = :task_nested,
        order = :testlet_blocked,
        audit_targets = (:rater_task,),
        expected_requested_targets_eligible = false,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :omitted_dimension_crossed_q,
        matched_set_id = :same_rater_core,
        mechanism = :omitted_multidimensionality,
        magnitude_label = :moderate,
        design = :same_rater,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :temporal_sequence_randomized,
        matched_set_id = :same_rater_core,
        mechanism = :severity_drift,
        magnitude_label = :moderate,
        design = :same_rater,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :temporal_sequence_ability_confounded,
        matched_set_id = :ability_order,
        mechanism = :null,
        magnitude_label = :zero,
        design = :same_rater,
        assignment = :balanced,
        order = :low_to_high,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :null_ability_informed_assignment,
        matched_set_id = :ability_assignment,
        mechanism = :null,
        magnitude_label = :zero,
        design = :same_rater,
        assignment = :ability_informed,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :scalar_testlet_plus_sequence,
        matched_set_id = :same_rater_core,
        mechanism = :person_testlet_plus_drift,
        magnitude_label = :moderate,
        design = :same_rater,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
    (;
        scenario_id = :scalar_testlet_exact_zero,
        matched_set_id = :same_rater_core,
        mechanism = :person_testlet,
        magnitude_label = :zero,
        design = :same_rater,
        assignment = :balanced,
        order = :randomized,
        audit_targets = (:scalar_shared_cluster,),
        expected_requested_targets_eligible = true,
        expected_diagnostic_pair_support = nothing,
        n_persons_override = 0,
        items_per_testlet_override = 0,
    ),
)

function _ld1_scenario(scenario_id::Symbol)
    index = findfirst(row -> row.scenario_id === scenario_id, _LD1_SCENARIOS)
    index === nothing && throw(ArgumentError(
        "unknown local-dependence simulation scenario :$scenario_id"))
    return _LD1_SCENARIOS[index]
end

function _ld1_effect_scale(magnitude::Symbol)
    hasproperty(_LD1_MAGNITUDE_SCALES, magnitude) || throw(ArgumentError(
        "unsupported local-dependence magnitude :$magnitude"))
    return Float64(getproperty(_LD1_MAGNITUDE_SCALES, magnitude))
end

function _ld1_connected_sparse_max_common_units(
        n_persons::Int, n_testlets::Int)
    complete_cycles, remainder = divrem(n_persons, n_testlets)
    # Each complete person cycle contributes twice to every testlet. A partial
    # cycle contributes at most one when it has one person and two otherwise.
    partial_maximum = remainder == 0 ? 0 : remainder == 1 ? 1 : 2
    return 2 * complete_cycles + partial_maximum
end

function _ld1_expected_diagnostic_pair_support(
        scenario, n_persons::Int, n_testlets::Int)
    if scenario.design === :connected_sparse
        # `any_diagnostic_pair_family_supported` becomes true when at least one
        # testlet has an item pair meeting the audit default of 20 common units.
        return _ld1_connected_sparse_max_common_units(
            n_persons, n_testlets) >= 20
    end
    return scenario.expected_diagnostic_pair_support
end

function _ld1_phase_seed(base_seed, phase::Symbol, replication::Int)
    hasproperty(_LD1_PHASE_OFFSETS, phase) || throw(ArgumentError(
        "phase must be :smoke, :pilot, or :evaluation"))
    base = _ld1_checked_seed(base_seed)
    offset = getproperty(_LD1_PHASE_OFFSETS, phase)
    base <= typemax(Int) - offset - replication + 1 ||
        throw(ArgumentError("base_seed is too large for the requested phase"))
    return _ld1_checked_seed(base + offset + replication - 1)
end

const _LD1_GRID_ROW_FIELDS = (
    :schema,
    :object,
    :profile,
    :status,
    :grid_id,
    :row_index,
    :scenario_index,
    :scenario_id,
    :matched_set_id,
    :replication,
    :phase,
    :base_seed,
    :seed,
    :component_seeds,
    :family,
    :thresholds,
    :mechanism,
    :magnitude_label,
    :effect_scale,
    :effect_scale_status,
    :design,
    :assignment,
    :order,
    :n_persons,
    :n_testlets,
    :items_per_testlet,
    :n_raters,
    :n_categories,
    :audit_targets,
    :expected_requested_targets_eligible,
    :expected_diagnostic_pair_support,
    :generator_kernel,
    :response_sampling,
    :fitted_probability_or_likelihood_dependency,
    :calibration_evidence_available,
    :diagnostic_decision_labels_available,
    :observed_data_mechanism_interpretation_eligible,
    :simulation_status,
)

"""
    local_dependence_simulation_grid(;
        profile = :ld1_preflight_v1, repetitions = 1,
        base_seed = 20260720, phase = :smoke,
        grid_id = "ld1_preflight", n_persons = 40,
        n_testlets = 4, items_per_testlet = 3,
        n_raters = 4, n_categories = 4)

Return the matched LD1a known-truth planning rows for local-dependence
simulation. The rows cover exact null and zero-boundary controls, near-zero
through large person-by-testlet variation, connected sparsity, pair-support
boundaries, pre-fit rejection controls, rater-response halo, rater-by-task
severity, omitted multidimensionality, randomized severity drift, and
ability-confounded order and ability-informed rater assignment. Scenarios
within a replication share component seed streams so comparisons use common
random numbers.

These rows are a generator and design-preflight plan. They are not repeated
calibration evidence, do not supply diagnostic cutoffs or decision labels, and
do not identify an observed-data mechanism. At most 10,000,000 replications are
accepted per phase so the reserved `:smoke`, `:pilot`, and `:evaluation` seed
namespaces do not overlap.
"""
function local_dependence_simulation_grid(;
        profile::Symbol = _LD1_PROFILE,
        repetitions::Integer = 1,
        base_seed::Integer = 20260720,
        phase::Symbol = :smoke,
        grid_id::AbstractString = "ld1_preflight",
        n_persons::Integer = 40,
        n_testlets::Integer = 4,
        items_per_testlet::Integer = 3,
        n_raters::Integer = 4,
        n_categories::Integer = 4)
    profile === _LD1_PROFILE || throw(ArgumentError(
        "only profile = :ld1_preflight_v1 is supported"))
    checked_repetitions = _ld1_checked_positive_integer(
        repetitions, :repetitions)
    checked_repetitions <= _LD1_PHASE_NAMESPACE_WIDTH ||
        throw(ArgumentError(
            "repetitions must not exceed $_LD1_PHASE_NAMESPACE_WIDTH so phase seed namespaces remain disjoint"))
    checked_base_seed = _ld1_checked_seed(base_seed)
    checked_persons = _ld1_checked_positive_integer(
        n_persons, :n_persons; minimum = 8)
    checked_testlets = _ld1_checked_positive_integer(
        n_testlets, :n_testlets; minimum = 4)
    checked_items = _ld1_checked_positive_integer(
        items_per_testlet, :items_per_testlet; minimum = 2)
    checked_raters = _ld1_checked_positive_integer(
        n_raters, :n_raters; minimum = 2)
    checked_categories = _ld1_checked_positive_integer(
        n_categories, :n_categories; minimum = 2)
    isempty(grid_id) && throw(ArgumentError("grid_id must not be empty"))

    rows = NamedTuple[]
    for replication in 1:checked_repetitions
        seed = _ld1_phase_seed(checked_base_seed, phase, replication)
        seeds = _ld1_component_seeds(seed)
        for (scenario_index, scenario) in pairs(_LD1_SCENARIOS)
            persons = scenario.n_persons_override == 0 ? checked_persons :
                scenario.n_persons_override
            items = scenario.items_per_testlet_override == 0 ? checked_items :
                scenario.items_per_testlet_override
            push!(rows, (;
                schema = "bayesianmgmfrm.local_dependence_simulation_grid.v1",
                object = :local_dependence_simulation_grid_row,
                profile,
                status = :planned,
                grid_id = String(grid_id),
                row_index = length(rows) + 1,
                scenario_index,
                scenario_id = scenario.scenario_id,
                matched_set_id = scenario.matched_set_id,
                replication,
                phase,
                base_seed = checked_base_seed,
                seed,
                component_seeds = seeds,
                family = :mfrm,
                thresholds = :partial_credit,
                mechanism = scenario.mechanism,
                magnitude_label = scenario.magnitude_label,
                effect_scale = _ld1_effect_scale(scenario.magnitude_label),
                effect_scale_status = :study_local_not_universal_cutoff,
                design = scenario.design,
                assignment = scenario.assignment,
                order = scenario.order,
                n_persons = persons,
                n_testlets = checked_testlets,
                items_per_testlet = items,
                n_raters = checked_raters,
                n_categories = checked_categories,
                audit_targets = scenario.audit_targets,
                expected_requested_targets_eligible =
                    scenario.expected_requested_targets_eligible,
                expected_diagnostic_pair_support =
                    _ld1_expected_diagnostic_pair_support(
                        scenario, persons, checked_testlets),
                generator_kernel =
                    :standalone_adjacent_category_partial_credit,
                response_sampling = :event_keyed_inverse_cdf,
                fitted_probability_or_likelihood_dependency = :none,
                calibration_evidence_available = false,
                diagnostic_decision_labels_available = false,
                observed_data_mechanism_interpretation_eligible = false,
                simulation_status = :predeclared_not_run,
            ))
        end
    end
    return rows
end

function _ld1_preserve_category_scale(data::FacetData, intended_levels)
    levels = collect(Int, intended_levels)
    isempty(levels) && throw(ArgumentError(
        "intended category levels must not be empty"))
    levels == collect(first(levels):last(levels)) || throw(ArgumentError(
        "intended category levels must be consecutive integers"))
    all(score -> score in levels, data.score) || throw(ArgumentError(
        "generated score is outside the intended category scale"))
    data.category_levels == levels && return data
    level_index = Dict(level => index for (index, level) in pairs(levels))
    category = [level_index[score] for score in data.score]
    return FacetData(
        data.n,
        data.person,
        data.rater,
        data.item,
        data.score,
        category,
        data.person_levels,
        data.rater_levels,
        data.item_levels,
        levels,
        data.optional,
        data.optional_levels,
        data.columns,
    )
end

function _ld1_facet_data(raw)
    data = FacetData(
        raw.table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        task = :task,
        occasion = :occasion,
        response_id = :response_id,
        testlet_id = :testlet_id,
    )
    return _ld1_preserve_category_scale(
        data, raw.truth.intended_category_levels)
end

function _ld1_audit_for_target(audits, target::Symbol)
    target === :scalar_shared_cluster && return audits.scalar_shared_cluster
    target === :rater_response_halo && return audits.rater_response_halo
    target === :rater_task && return audits.rater_task
    throw(ArgumentError("unsupported LD1 audit target :$target"))
end

function _ld1_reader_facing_rating_audit(audit)
    anchor_linking = (; (
        key => value for (key, value) in pairs(audit.anchor_linking)
        if key !== :next_gate
    )...)
    return merge(audit, (; anchor_linking))
end

function _ld1_score_signature(scores)
    return bytes2hex(sha256(codeunits(join(scores, ','))))
end

function _ld1_source_signature(filename::AbstractString)
    path = joinpath(@__DIR__, filename)
    return (;
        algorithm = :sha256,
        path = filename,
        value = bytes2hex(open(sha256, path)),
    )
end

function _ld1_simulation_config(row, max_ratings::Int,
        max_probability_cells::Int, max_truth_cells::Int)
    return (;
        seed = row.seed,
        mechanism = row.mechanism,
        effect_scale = Float64(row.effect_scale),
        design = row.design,
        assignment = row.assignment,
        order = row.order,
        n_persons = row.n_persons,
        n_testlets = row.n_testlets,
        items_per_testlet = row.items_per_testlet,
        n_raters = row.n_raters,
        n_categories = row.n_categories,
        max_ratings,
        max_probability_cells,
        max_truth_cells,
    )
end

function _ld1_validate_grid_row(row)
    row isa NamedTuple || throw(ArgumentError(
        "simulate_local_dependence requires a planning-grid NamedTuple"))
    propertynames(row) == _LD1_GRID_ROW_FIELDS || throw(ArgumentError(
        "simulate_local_dependence requires an unmodified planning-grid row"))
    (row.schema isa String &&
        row.schema == "bayesianmgmfrm.local_dependence_simulation_grid.v1") ||
        throw(ArgumentError("unexpected local-dependence grid-row schema"))
    row.object === :local_dependence_simulation_grid_row ||
        throw(ArgumentError("unexpected local-dependence grid-row object"))
    row.profile === _LD1_PROFILE ||
        throw(ArgumentError("unexpected local-dependence grid-row profile"))
    row.status === :planned ||
        throw(ArgumentError("unexpected local-dependence grid-row status"))
    (row.grid_id isa String && !isempty(row.grid_id)) ||
        throw(ArgumentError("local-dependence grid_id must be a nonempty String"))

    row.scenario_id isa Symbol || throw(ArgumentError(
        "local-dependence scenario_id must be a Symbol"))
    canonical = _ld1_scenario(row.scenario_id)
    scenario_index = findfirst(
        scenario -> scenario.scenario_id === row.scenario_id,
        _LD1_SCENARIOS,
    )
    (row.scenario_index isa Int && row.scenario_index == scenario_index) ||
        throw(ArgumentError(
            "local-dependence scenario_index does not match scenario_id"))
    row.matched_set_id === canonical.matched_set_id ||
        throw(ArgumentError(
            "local-dependence matched_set_id does not match the frozen scenario"))
    for field in (:mechanism, :magnitude_label, :design, :assignment, :order,
            :audit_targets, :expected_requested_targets_eligible)
        isequal(getproperty(row, field), getproperty(canonical, field)) ||
            throw(ArgumentError(
                "local-dependence grid-row field :$field does not match the frozen scenario"))
    end
    (row.effect_scale isa Float64 && isfinite(row.effect_scale) &&
        row.effect_scale == _ld1_effect_scale(canonical.magnitude_label)) ||
        throw(ArgumentError(
            "local-dependence grid-row effect_scale does not match its magnitude"))

    (row.replication isa Int &&
        1 <= row.replication <= _LD1_PHASE_NAMESPACE_WIDTH) ||
        throw(ArgumentError(
            "local-dependence replication is outside its reserved phase namespace"))
    (row.phase isa Symbol && hasproperty(_LD1_PHASE_OFFSETS, row.phase)) ||
        throw(ArgumentError("unexpected local-dependence phase"))
    row.seed isa Int || throw(ArgumentError(
        "local-dependence seed must be an Int"))
    row.base_seed isa Int || throw(ArgumentError(
        "local-dependence base_seed must be an Int"))
    _ld1_checked_seed(row.seed)
    _ld1_checked_seed(row.base_seed)
    _ld1_phase_seed(row.base_seed, row.phase, row.replication) == row.seed ||
        throw(ArgumentError(
            "local-dependence seed is inconsistent with phase and replication"))
    isequal(row.component_seeds, _ld1_component_seeds(row.seed)) ||
        throw(ArgumentError(
            "local-dependence component_seeds do not match seed"))
    (row.row_index isa Int &&
        row.row_index ==
            (row.replication - 1) * length(_LD1_SCENARIOS) + scenario_index) ||
        throw(ArgumentError(
            "local-dependence row_index is inconsistent with replication and scenario_index"))

    for (field, minimum) in (
            (:n_persons, 8),
            (:n_testlets, 4),
            (:n_raters, 2),
            (:n_categories, 2),
        )
        value = getproperty(row, field)
        (value isa Int && value >= minimum) ||
            throw(ArgumentError(
                "local-dependence grid-row $field must be an Int at least $minimum"))
    end
    items_minimum = canonical.items_per_testlet_override == 0 ? 2 : 1
    (row.items_per_testlet isa Int &&
        row.items_per_testlet >= items_minimum) ||
        throw(ArgumentError(
            "local-dependence grid-row items_per_testlet must be an Int at least $items_minimum"))
    if canonical.n_persons_override != 0
        row.n_persons == canonical.n_persons_override ||
            throw(ArgumentError(
                "local-dependence n_persons does not match the frozen scenario override"))
    end
    if canonical.items_per_testlet_override != 0
        row.items_per_testlet == canonical.items_per_testlet_override ||
            throw(ArgumentError(
                "local-dependence items_per_testlet does not match the frozen scenario override"))
    end
    expected_diagnostic_pair_support =
        _ld1_expected_diagnostic_pair_support(
            canonical, row.n_persons, row.n_testlets)
    row.expected_diagnostic_pair_support ===
        expected_diagnostic_pair_support || throw(ArgumentError(
            "local-dependence expected_diagnostic_pair_support does not match its design support"))

    constants = (;
        family = :mfrm,
        thresholds = :partial_credit,
        effect_scale_status = :study_local_not_universal_cutoff,
        generator_kernel = :standalone_adjacent_category_partial_credit,
        response_sampling = :event_keyed_inverse_cdf,
        fitted_probability_or_likelihood_dependency = :none,
        calibration_evidence_available = false,
        diagnostic_decision_labels_available = false,
        observed_data_mechanism_interpretation_eligible = false,
        simulation_status = :predeclared_not_run,
    )
    for (field, expected) in pairs(constants)
        getproperty(row, field) === expected || throw(ArgumentError(
            "local-dependence grid-row field :$field does not match the planning-grid contract"))
    end
    return row
end

"""
    simulate_local_dependence(row;
        max_ratings = 1_000_000,
        max_probability_cells = 5_000_000,
        max_truth_cells = 5_000_000)
    simulate_local_dependence(scenario_id::Symbol;
        seed = 20260720, n_persons = 40, n_testlets = 4,
        items_per_testlet = 3, n_raters = 4, n_categories = 4,
        max_ratings = 1_000_000,
        max_probability_cells = 5_000_000,
        max_truth_cells = 5_000_000)

Generate one LD1a ordinal known-truth bundle from a row returned by
[`local_dependence_simulation_grid`](@ref), or from its `scenario_id`. Response
probabilities use a separately coded adjacent-category partial-credit kernel;
sampling does not depend on a fitted model's probability or likelihood
implementation. The bundle keeps the intended category scale even when a
random realization omits an extreme category, and records exact sequence
positions, event-keyed uniforms, every additive truth component, requested
design audits, and resource counts.

`max_ratings`, `max_probability_cells`, and `max_truth_cells` bound the number
of generated ratings, category-probability cells, and dense truth-surface cells
before their corresponding allocations. Response and missingness uniforms use
named component seeds and the semantic key `(person, testlet, rater,
within_testlet_item)` to initialize a fresh Julia `MersenneTwister` draw for
each event. Thus common events are invariant to row enumeration and to adding
later within-testlet items. The seed derivation is stable in source and avoids
Julia's session-dependent `hash`, but bitwise identity across Julia versions or
alternative RNG implementations is not claimed.

The result is generator and pre-fit evidence only. It does not run posterior
sampling or `local_dependence_summary`, calibrate Q3/FDR/FWER references,
provide a diagnostic decision, or identify the generating mechanism in
observed data.
"""
function simulate_local_dependence(row;
        max_ratings::Int = 1_000_000,
        max_probability_cells::Int = 5_000_000,
        max_truth_cells::Int = 5_000_000)
    _ld1_validate_grid_row(row)
    max_ratings >= 1 || throw(ArgumentError("max_ratings must be positive"))
    max_probability_cells >= 1 || throw(ArgumentError(
        "max_probability_cells must be positive"))
    max_truth_cells >= 1 || throw(ArgumentError(
        "max_truth_cells must be positive"))
    raw = _ld1_generate_raw(
        _ld1_simulation_config(
            row, max_ratings, max_probability_cells, max_truth_cells))
    data = _ld1_facet_data(raw)
    validation = validate_design(data)
    independent_ratings_declared = row.design === :fully_crossed_raters
    audits = (;
        scalar_shared_cluster = testlet_design_audit(
            data;
            target = :scalar_shared_cluster,
            independent_ratings_declared,
        ),
        rater_response_halo = testlet_design_audit(
            data;
            target = :rater_response_halo,
            independent_ratings_declared,
        ),
        rater_task = testlet_design_audit(
            data;
            target = :rater_task,
            independent_ratings_declared,
        ),
    )
    rating_audit = _ld1_reader_facing_rating_audit(
        rating_design_audit(data; unit = :person_item))
    requested_audits = Tuple(
        _ld1_audit_for_target(audits, target)
        for target in row.audit_targets
    )
    requested_targets_eligible = all(
        audit -> audit.structurally_eligible_for_candidate,
        requested_audits,
    )
    target_expectation_passed = requested_targets_eligible ==
        row.expected_requested_targets_eligible
    diagnostic_support = audits.scalar_shared_cluster.
        any_diagnostic_pair_family_supported
    diagnostic_expectation_passed =
        row.expected_diagnostic_pair_support === nothing ||
        diagnostic_support == row.expected_diagnostic_pair_support
    raw_checks_passed = raw.raw_checks.probabilities_finite &&
        raw.raw_checks.probabilities_nonnegative &&
        raw.raw_checks.maximum_probability_sum_error <= 1.0e-12 &&
        raw.raw_checks.score_support_valid && raw.raw_checks.all_rows_observed
    standalone_generator_path_used =
        raw.truth.equation === :standalone_adjacent_category_partial_credit &&
        raw.truth.sampling_independence_given_complete_truth &&
        raw.truth.rng_contract.version ===
            :stable_namespace_semantic_key_v1
    future_fit_action = !raw.truth.category_support_complete ?
        :do_not_fit_category_support_incomplete :
        (requested_targets_eligible ?
            :structurally_eligible_for_future_candidate :
            :do_not_fit_underidentified_design)
    checks = (;
        raw.raw_checks...,
        response_nesting_and_duplicate_schema_valid =
            audits.scalar_shared_cluster.schema_valid,
        target_expectation_passed,
        diagnostic_expectation_passed,
        intended_category_scale_preserved = data.category_levels ==
            collect(raw.truth.intended_category_levels),
        unique_event_ids = length(unique(raw.table.event_id)) == data.n,
        standalone_generator_path_used,
        generator_checks_passed = raw_checks_passed,
    )
    passed = raw_checks_passed && checks.standalone_generator_path_used &&
        checks.response_nesting_and_duplicate_schema_valid &&
        checks.target_expectation_passed &&
        checks.diagnostic_expectation_passed &&
        checks.intended_category_scale_preserved && checks.unique_event_ids
    return (;
        schema = "bayesianmgmfrm.local_dependence_simulation.v1",
        object = :local_dependence_simulation,
        status = passed ? :known_truth_generated : :preflight_failed,
        profile = row.profile,
        grid_id = row.grid_id,
        scenario_id = row.scenario_id,
        matched_set_id = row.matched_set_id,
        replication = row.replication,
        phase = row.phase,
        base_seed = row.base_seed,
        seed = row.seed,
        mechanism = row.mechanism,
        magnitude_label = row.magnitude_label,
        effect_scale = Float64(row.effect_scale),
        design = row.design,
        assignment = row.assignment,
        order = row.order,
        generator_contract = (;
            equation = :unidimensional_partial_credit_with_additive_truth_components,
            category_kernel = :standalone_adjacent_category_cumulative_step_softmax,
            sampling = :event_keyed_inverse_cdf,
            event_keying =
                :semantic_key_seeded_fresh_mersenne_twister_draw,
            semantic_event_key =
                (:person, :testlet, :rater, :within_testlet_item),
            enumeration_order_invariant = true,
            shared_events_stable_when_items_per_testlet_extended = true,
            uniform_is_direct_hash_output = false,
            rng_engine = :julia_mersenne_twister,
            cross_julia_bitwise_portability_claimed = false,
            rng_contract = raw.truth.rng_contract,
            fitted_probability_or_likelihood_dependency = :none,
            known_truth_source_signature = _ld1_source_signature(
                "local_dependence_known_truth_dgp.jl"),
            row_order_source = :explicit_within_rater_sequence_index,
            occasion_role = :response_level_categorical_sidecar_not_elapsed_time,
            sequence_phase_role = :derived_from_explicit_within_rater_sequence,
            all_categories_forced_to_appear = false,
        ),
        data,
        table = raw.table,
        truth = raw.truth,
        row_truth = raw.row_truth,
        validation,
        design_support = (;
            rating_design = rating_audit,
            testlet = audits,
            requested_targets = row.audit_targets,
            requested_targets_eligible,
            expected_requested_targets_eligible =
                row.expected_requested_targets_eligible,
            diagnostic_pair_support_available = diagnostic_support,
            expected_diagnostic_pair_support =
                row.expected_diagnostic_pair_support,
            future_fit_action,
        ),
        resource_counts = raw.resource_counts,
        checks,
        data_signature = validation.data_signature,
        testlet_design_signature = audits.scalar_shared_cluster.design_signature,
        score_signature = _ld1_score_signature(data.score),
        truth_known_by_construction = true,
        calibration_status = :evaluation_not_run,
        calibration_evidence_available = false,
        diagnostic_decision_labels_available = false,
        observed_data_mechanism_interpretation_eligible = false,
        summary = (;
            passed,
            n_ratings = data.n,
            n_persons = length(data.person_levels),
            n_raters = length(data.rater_levels),
            n_items = length(data.item_levels),
            n_testlets = length(data.optional_levels[:testlet_id]),
            intended_categories = length(raw.truth.intended_category_levels),
            realized_categories = length(raw.truth.realized_category_levels),
            category_support_complete = raw.truth.category_support_complete,
            requested_targets_eligible,
            future_fit_action,
        ),
        caveat = :generator_and_preflight_evidence_not_calibration_or_mechanism_classification,
    )
end

function simulate_local_dependence(scenario_id::Symbol;
        seed::Integer = 20260720,
        n_persons::Integer = 40,
        n_testlets::Integer = 4,
        items_per_testlet::Integer = 3,
        n_raters::Integer = 4,
        n_categories::Integer = 4,
        max_ratings::Int = 1_000_000,
        max_probability_cells::Int = 5_000_000,
        max_truth_cells::Int = 5_000_000)
    _ld1_scenario(scenario_id)
    rows = local_dependence_simulation_grid(;
        repetitions = 1,
        base_seed = seed,
        phase = :smoke,
        n_persons,
        n_testlets,
        items_per_testlet,
        n_raters,
        n_categories,
    )
    row = only(filter(candidate -> candidate.scenario_id === scenario_id, rows))
    return simulate_local_dependence(
        row;
        max_ratings,
        max_probability_cells,
        max_truth_cells,
    )
end
