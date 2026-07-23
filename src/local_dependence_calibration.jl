# local_dependence_calibration.jl -- LD1b0 repeated diagnostic calibration

const _LD1B0_PROFILE = :ld1b0_protocol_v1
const _LD1B0_STATUSES = (
    :completed,
    :pre_fit_rejected,
    :generation_failed,
    :fit_failed,
    :diagnostic_failed,
)
const _LD1B0_WILSON_CONFIDENCE = 0.95
const _LD1B0_WILSON_Z = 1.959963984540054
const _LD1B0_SEED_NAMESPACES = (;
    fit = :ld1b0_fit,
    draw_selection = :ld1b0_draw_selection,
    posterior_predictive = :ld1b0_posterior_predictive,
)

function _ld1b0_probability(value, name::Symbol)
    checked = Float64(value)
    isfinite(checked) && 0 < checked < 1 || throw(ArgumentError(
        "$name must be finite and in (0, 1)"))
    return checked
end

function _ld1b0_probability_or_missing(value, name::Symbol)
    ismissing(value) && return missing
    checked = Float64(value)
    isfinite(checked) && 0 <= checked <= 1 || throw(ArgumentError(
        "$name must be missing or finite and in [0, 1]"))
    return checked
end

"""
    local_dependence_calibration_contract(;
        profile = :ld1b0_protocol_v1,
        diagnostic_contract = local_dependence_contract(),
        candidate_pair_raw_alpha = 0.05,
        candidate_pair_bh_alpha = 0.05,
        candidate_family_alpha = 0.05,
        candidate_global_alpha = 0.05)

Return the LD1b0 protocol-preflight contract for repeated calibration of the
existing report-only local-dependence diagnostic. The four alphas define
candidate decisions computed from finite-sample-corrected unadjusted pair
tails, within-family BH-adjusted tails, family maximum-statistic tails, and the
all-family maximum-statistic tail. They do not enable decisions in
`local_dependence_summary` or authorize a mechanism interpretation.

Replication-level binary rates use a fixed 95% Wilson interval. Pairwise power
is unavailable because the current known-truth generator has no pair-specific
null/non-null oracle.
"""
function local_dependence_calibration_contract(;
        profile::Symbol = _LD1B0_PROFILE,
        diagnostic_contract = local_dependence_contract(),
        candidate_pair_raw_alpha::Real = 0.05,
        candidate_pair_bh_alpha::Real = 0.05,
        candidate_family_alpha::Real = 0.05,
        candidate_global_alpha::Real = 0.05)
    profile === _LD1B0_PROFILE || throw(ArgumentError(
        "profile must be :$_LD1B0_PROFILE"))
    checked_diagnostic_contract =
        _local_dependence_validate_contract(diagnostic_contract)
    pair_raw = _ld1b0_probability(
        candidate_pair_raw_alpha, :candidate_pair_raw_alpha)
    pair_bh = _ld1b0_probability(
        candidate_pair_bh_alpha, :candidate_pair_bh_alpha)
    family = _ld1b0_probability(
        candidate_family_alpha, :candidate_family_alpha)
    global_alpha = _ld1b0_probability(
        candidate_global_alpha, :candidate_global_alpha)
    return (;
        schema = "bayesianmgmfrm.local_dependence_calibration_contract.v1",
        object = :local_dependence_calibration_contract,
        profile,
        status = :protocol_preflight_only,
        diagnostic_contract = checked_diagnostic_contract,
        candidate_thresholds = (;
            pair_raw_alpha = pair_raw,
            pair_bh_alpha = pair_bh,
            family_maximum_alpha = family,
            global_maximum_alpha = global_alpha,
            pair_raw_source =
                :finite_sample_corrected_posterior_predictive_tail_fraction,
            pair_bh_source = :within_family_bh_adjusted_tail_fraction,
            family_source = :family_maximum_statistic_tail_fraction,
            global_source = :all_family_maximum_statistic_tail_fraction,
            comparison = :less_than_or_equal_to,
        ),
        monte_carlo_interval = (;
            method = :wilson_score,
            confidence = _LD1B0_WILSON_CONFIDENCE,
            z = _LD1B0_WILSON_Z,
            applies_to = :replication_level_binary_rates_only,
        ),
        seed_contract = (;
            root = :ld1_planning_row_seed,
            namespaces = _LD1B0_SEED_NAMESPACES,
            scenario_key = :frozen_scenario_id,
            derivation = :stable_namespace_mixer,
            mutable_default_rng_used = false,
            cross_julia_bitwise_portability_claimed = false,
        ),
        target_evidence_available = false,
        pair_truth_oracle_available = false,
        pairwise_power_available = false,
        repeated_calibration_completed = false,
        calibration_evidence_available = false,
        diagnostic_decision_labels_available = false,
        mechanism_interpretation_eligible = false,
    )
end

function _ld1b0_validate_contract(contract)
    contract isa NamedTuple || throw(ArgumentError(
        "contract must be returned by local_dependence_calibration_contract"))
    required = (:schema, :object, :profile, :status, :diagnostic_contract,
        :candidate_thresholds,
        :monte_carlo_interval, :seed_contract, :target_evidence_available,
        :pair_truth_oracle_available, :pairwise_power_available,
        :repeated_calibration_completed, :calibration_evidence_available,
        :diagnostic_decision_labels_available,
        :mechanism_interpretation_eligible)
    all(field -> hasproperty(contract, field), required) || throw(ArgumentError(
        "contract is incomplete"))
    canonical = local_dependence_calibration_contract(;
        profile = contract.profile,
        diagnostic_contract = contract.diagnostic_contract,
        candidate_pair_raw_alpha =
            contract.candidate_thresholds.pair_raw_alpha,
        candidate_pair_bh_alpha = contract.candidate_thresholds.pair_bh_alpha,
        candidate_family_alpha =
            contract.candidate_thresholds.family_maximum_alpha,
        candidate_global_alpha =
            contract.candidate_thresholds.global_maximum_alpha,
    )
    isequal(contract, canonical) || throw(ArgumentError(
        "contract must be an unmodified local_dependence_calibration_contract result"))
    return contract
end

function _ld1b0_truth(row)
    scales = _ld1_component_scales(row.mechanism, Float64(row.effect_scale))
    active = _ld1_active_mechanisms(scales)
    target = Float64(scales.testlet)
    truth_class = isempty(active) ? :complete_null :
        target > 0 && length(active) == 1 ? :target_only :
        target > 0 ? :target_plus_competing_mechanism :
        :competing_mechanism_only
    return (;
        generating_mechanism = row.mechanism,
        active_mechanisms = active,
        complete_null = isempty(active),
        target = :person_testlet_standard_deviation,
        target_standard_deviation = target,
        target_truth_class = truth_class,
        baseline_mfrm_assumption_status =
            _ld1_baseline_mfrm_assumption_status(active),
        pair_truth_oracle_available = false,
        pairwise_power_available = false,
    )
end

function _ld1b0_execution_seeds(row, contract)
    scenario = String(row.scenario_id)
    seed_for(namespace) = _ld1_component_seed(
        row.seed, Symbol(String(namespace), "__", scenario))
    namespaces = contract.seed_contract.namespaces
    return (;
        fit = seed_for(namespaces.fit),
        draw_selection = seed_for(namespaces.draw_selection),
        posterior_predictive = seed_for(namespaces.posterior_predictive),
        contract = contract.seed_contract,
    )
end

_ld1b0_planning_shape(row) = (;
    n_persons = row.n_persons,
    n_testlets = row.n_testlets,
    items_per_testlet = row.items_per_testlet,
    n_items = row.n_testlets * row.items_per_testlet,
    n_raters = row.n_raters,
    n_categories = row.n_categories,
    audit_targets = row.audit_targets,
    expected_diagnostic_pair_support = row.expected_diagnostic_pair_support,
)

function _ld1b0_validate_simulation(row, simulation)
    simulation isa NamedTuple || throw(ArgumentError(
        "simulation must be returned by simulate_local_dependence"))
    simulation.schema == "bayesianmgmfrm.local_dependence_simulation.v1" &&
        simulation.object === :local_dependence_simulation || throw(ArgumentError(
        "unexpected local-dependence simulation schema"))
    simulation.status === :known_truth_generated || throw(ArgumentError(
        "calibration requires a successfully generated known-truth simulation"))
    for field in (:profile, :grid_id, :scenario_id, :matched_set_id,
            :replication, :phase, :base_seed, :seed, :mechanism,
            :magnitude_label, :effect_scale, :design, :assignment, :order)
        isequal(getproperty(simulation, field), getproperty(row, field)) ||
            throw(ArgumentError(
                "simulation field :$field does not match its planning row"))
    end
    simulation.truth_known_by_construction === true || throw(ArgumentError(
        "simulation truth is not marked known by construction"))
    simulation.calibration_evidence_available === false &&
        simulation.diagnostic_decision_labels_available === false &&
        simulation.observed_data_mechanism_interpretation_eligible === false ||
        throw(ArgumentError("simulation claim-boundary fields were modified"))
    expected_shape = _ld1b0_planning_shape(row)
    length(simulation.truth.person_labels) == expected_shape.n_persons &&
        length(simulation.truth.testlet_labels) == expected_shape.n_testlets &&
        length(simulation.truth.item_labels) == expected_shape.n_items &&
        length(simulation.truth.rater_labels) == expected_shape.n_raters &&
        length(simulation.truth.intended_category_levels) ==
            expected_shape.n_categories ||
        throw(ArgumentError(
            "simulation configured dimensions do not match the planning row"))
    simulation.summary.n_persons == expected_shape.n_persons &&
        simulation.summary.n_testlets == expected_shape.n_testlets &&
        simulation.summary.n_items == expected_shape.n_items &&
        1 <= simulation.summary.n_raters <= expected_shape.n_raters &&
        simulation.summary.intended_categories == expected_shape.n_categories &&
        1 <= simulation.summary.realized_categories <=
            expected_shape.n_categories || throw(ArgumentError(
        "simulation observed dimensions are inconsistent with its configured design"))
    simulation.design_support.requested_targets == expected_shape.audit_targets ||
        throw(ArgumentError(
            "simulation audit targets do not match the planning row"))
    simulation.design_support.expected_diagnostic_pair_support ===
        expected_shape.expected_diagnostic_pair_support ||
        throw(ArgumentError(
            "simulation diagnostic support expectation does not match plan"))
    expected_truth = _ld1b0_truth(row)
    expected_scales = _ld1_component_scales(
        row.mechanism, Float64(row.effect_scale))
    isequal(simulation.truth.component_scales, expected_scales) ||
        throw(ArgumentError(
            "simulation component scales do not match the planning row"))
    Tuple(simulation.truth.active_mechanisms) == expected_truth.active_mechanisms ||
        throw(ArgumentError("simulation active mechanisms do not match the plan"))
    Float64(simulation.truth.component_scales.testlet) ==
        expected_truth.target_standard_deviation || throw(ArgumentError(
        "simulation target truth does not match the plan"))
    simulation.design_support.requested_targets_eligible ===
        row.expected_requested_targets_eligible || throw(ArgumentError(
        "simulation structural eligibility does not match the plan"))
    simulation.design_support.expected_requested_targets_eligible ===
        row.expected_requested_targets_eligible || throw(ArgumentError(
        "simulation expected structural eligibility does not match the plan"))
    simulation.summary.requested_targets_eligible ===
        row.expected_requested_targets_eligible || throw(ArgumentError(
        "simulation summary structural eligibility does not match the plan"))
    expected_future_action = !simulation.truth.category_support_complete ?
        :do_not_fit_category_support_incomplete :
        row.expected_requested_targets_eligible ?
            :structurally_eligible_for_future_candidate :
            :do_not_fit_underidentified_design
    simulation.design_support.future_fit_action === expected_future_action ||
        throw(ArgumentError(
            "simulation future fit action does not match structural support"))
    return (;
        status = simulation.status,
        data_signature = simulation.data_signature,
        score_signature = simulation.score_signature,
        observed_score_signature =
            _local_dependence_observed_score_signature(simulation.data),
        testlet_design_signature = simulation.testlet_design_signature,
        n_ratings = simulation.summary.n_ratings,
        planning_shape = expected_shape,
        observed_shape = (;
            n_persons = simulation.summary.n_persons,
            n_testlets = simulation.summary.n_testlets,
            n_items = simulation.summary.n_items,
            n_raters = simulation.summary.n_raters,
            n_categories = simulation.summary.realized_categories,
        ),
        requested_targets_eligible =
            simulation.design_support.requested_targets_eligible,
        future_fit_action = simulation.design_support.future_fit_action,
    )
end

function _ld1b0_validate_diagnostic(simulation, diagnostic, contract)
    diagnostic isa NamedTuple || throw(ArgumentError(
        "diagnostic must be returned by local_dependence_summary"))
    diagnostic.schema == "bayesianmgmfrm.local_dependence_summary.v1" &&
        diagnostic.object === :local_dependence_summary || throw(ArgumentError(
        "unexpected local-dependence diagnostic schema"))
    diagnostic.decision_labels_available === false &&
        diagnostic.mechanism_interpretation_eligible === false &&
        ismissing(diagnostic.decision) || throw(ArgumentError(
        "diagnostic claim-boundary fields were modified"))
    _local_dependence_validate_contract(diagnostic.contract)
    isequal(diagnostic.contract, contract.diagnostic_contract) ||
        throw(ArgumentError(
            "diagnostic contract does not match the calibration protocol"))
    diagnostic.data_signature == simulation.data_signature ||
        throw(ArgumentError("diagnostic data signature does not match simulation"))
    diagnostic.design_signature == simulation.testlet_design_signature ||
        throw(ArgumentError("diagnostic design signature does not match simulation"))
    expected_score_signature =
        _local_dependence_observed_score_signature(simulation.data)
    isequal(diagnostic.observed_score_signature, expected_score_signature) ||
        throw(ArgumentError("diagnostic score signature does not match simulation"))
    diagnostic.n_pair_rows == length(diagnostic.pair_rows) || throw(ArgumentError(
        "diagnostic pair-row count is inconsistent"))
    all(pair -> pair.decision_available === false &&
        ismissing(pair.decision) && ismissing(pair.local_dependence_detected) &&
        pair.mechanism_interpretation_eligible === false,
        diagnostic.pair_rows) || throw(ArgumentError(
        "diagnostic pair decision fields were modified"))
    Tuple(diagnostic.selected_families) == _LOCAL_DEPENDENCE_PAIR_FAMILIES ||
        throw(ArgumentError(
            "diagnostic selected-family contract was modified"))
    all(row -> row.decision_available === false &&
        row.mechanism_interpretation_eligible === false,
        diagnostic.family_rows) || throw(ArgumentError(
        "diagnostic family decision fields were modified"))
    all(row -> row.decision_available === false,
        diagnostic.family_max_rows) || throw(ArgumentError(
        "diagnostic family-maximum decision fields were modified"))
    diagnostic.global_evidence.decision_available === false ||
        throw(ArgumentError("diagnostic global decision field was modified"))
    return (;
        status = diagnostic.status,
        profile = diagnostic.profile,
        n_draws = diagnostic.n_draws,
        data_signature = diagnostic.data_signature,
        observed_score_signature = diagnostic.observed_score_signature,
        design_signature = diagnostic.design_signature,
    )
end

function _ld1b0_pair_evidence(diagnostic, contract, max_pair_rows::Int)
    length(diagnostic.pair_rows) <= max_pair_rows || throw(ArgumentError(
        "diagnostic pair rows exceed max_pair_rows=$max_pair_rows"))
    alpha = contract.candidate_thresholds
    rows = NamedTuple[]
    seen = Set{Tuple{Symbol,Any,Any,Any}}()
    for pair in diagnostic.pair_rows
        pair.family in _LOCAL_DEPENDENCE_PAIR_FAMILIES || throw(ArgumentError(
            "diagnostic pair uses an unsupported family"))
        key = (pair.family, pair.testlet_id, pair.left, pair.right)
        key in seen && throw(ArgumentError("duplicate diagnostic pair identity"))
        push!(seen, key)
        raw = _ld1b0_probability_or_missing(
            pair.posterior_predictive_tail_fraction,
            :posterior_predictive_tail_fraction)
        bh = _ld1b0_probability_or_missing(
            pair.bh_adjusted_tail_fraction, :bh_adjusted_tail_fraction)
        eligible = pair.status === :eligible_report_only && !ismissing(raw)
        eligible && ismissing(bh) && throw(ArgumentError(
            "eligible diagnostic pair is missing its BH-adjusted tail"))
        push!(rows, (;
            family = pair.family,
            testlet_id = pair.testlet_id,
            left = pair.left,
            right = pair.right,
            support_status = pair.status,
            eligible,
            posterior_predictive_tail_fraction = raw,
            bh_adjusted_tail_fraction = bh,
            candidate_raw_declared = eligible ?
                raw <= alpha.pair_raw_alpha : missing,
            candidate_bh_declared = eligible ?
                bh <= alpha.pair_bh_alpha : missing,
        ))
    end
    return Tuple(rows)
end

function _ld1b0_family_evidence(diagnostic, pair_evidence, contract)
    alpha = contract.candidate_thresholds.family_maximum_alpha
    support_families = [row.family for row in diagnostic.family_rows]
    maximum_families = [row.family for row in diagnostic.family_max_rows]
    canonical_families = sort(collect(_LOCAL_DEPENDENCE_PAIR_FAMILIES);
        by = string)
    sort(support_families; by = string) == canonical_families ||
        throw(ArgumentError(
            "diagnostic family support identities are not canonical"))
    sort(maximum_families; by = string) == canonical_families ||
        throw(ArgumentError(
            "diagnostic family maximum identities are not canonical"))
    support = Dict(row.family => row for row in diagnostic.family_rows)
    maxima = Dict(row.family => row for row in diagnostic.family_max_rows)
    return Tuple((function ()
        family_row = get(support, family, nothing)
        maximum_row = get(maxima, family, nothing)
        family_row === nothing && throw(ArgumentError(
            "diagnostic is missing family support for :$family"))
        maximum_row === nothing && throw(ArgumentError(
            "diagnostic is missing family maximum evidence for :$family"))
        tail = _ld1b0_probability_or_missing(
            maximum_row.posterior_predictive_tail_fraction,
            :family_maximum_tail_fraction)
        pairs = [row for row in pair_evidence if row.family === family]
        eligible_pairs = [row for row in pairs if row.eligible]
        applicable = family_row.status !== :not_applicable
        family_evaluable = applicable && !ismissing(tail)
        (;
            family,
            support_status = family_row.status,
            applicable,
            n_pair_rows = length(pairs),
            n_eligible_pairs = length(eligible_pairs),
            n_raw_declared = count(row -> row.candidate_raw_declared === true,
                eligible_pairs),
            n_bh_declared = count(row -> row.candidate_bh_declared === true,
                eligible_pairs),
            any_raw_declared = isempty(eligible_pairs) ? missing :
                any(row -> row.candidate_raw_declared === true, eligible_pairs),
            any_bh_declared = isempty(eligible_pairs) ? missing :
                any(row -> row.candidate_bh_declared === true, eligible_pairs),
            maximum_support_status = maximum_row.support_status,
            maximum_tail_fraction = tail,
            family_evaluable,
            candidate_family_declared = family_evaluable ? tail <= alpha : missing,
        )
    end)() for family in _LOCAL_DEPENDENCE_PAIR_FAMILIES)
end

function _ld1b0_global_evidence(diagnostic, contract)
    global_row = diagnostic.global_evidence
    tail = _ld1b0_probability_or_missing(
        global_row.posterior_predictive_tail_fraction,
        :global_maximum_tail_fraction)
    evaluable = !ismissing(tail)
    return (;
        support_status = global_row.support_status,
        n_overall_supported_pairs = global_row.n_overall_supported_pairs,
        tail_fraction = tail,
        evaluable,
        candidate_global_declared = evaluable ?
            tail <= contract.candidate_thresholds.global_maximum_alpha : missing,
    )
end

"""
    local_dependence_calibration_row(plan_row;
        contract = local_dependence_calibration_contract(),
        status = :completed, simulation = nothing, diagnostic = nothing,
        failure_code = missing, max_pair_rows = 200_000)

Create one LD1b0 result row for a canonical LD1 planning row. Completed rows
require matching known-truth simulation and report-only diagnostic bundles.
Pre-fit rejection and failure statuses retain their planned denominator rather
than being silently dropped. Candidate decisions are derived without modifying
the supplied diagnostic.
"""
function local_dependence_calibration_row(plan_row;
        contract = local_dependence_calibration_contract(),
        status::Symbol = :completed,
        simulation = nothing,
        diagnostic = nothing,
        failure_code = missing,
        max_pair_rows::Int = 200_000)
    checked_contract = _ld1b0_validate_contract(contract)
    _ld1_validate_grid_row(plan_row)
    status in _LD1B0_STATUSES || throw(ArgumentError(
        "status must be one of $_LD1B0_STATUSES"))
    max_pair_rows >= 1 || throw(ArgumentError("max_pair_rows must be positive"))
    expected_eligible = plan_row.expected_requested_targets_eligible
    if status === :completed
        expected_eligible || throw(ArgumentError(
            "a structurally rejected planning row cannot be completed"))
        simulation === nothing && throw(ArgumentError(
            "completed calibration rows require simulation"))
        diagnostic === nothing && throw(ArgumentError(
            "completed calibration rows require diagnostic"))
        ismissing(failure_code) || throw(ArgumentError(
            "completed calibration rows cannot record failure_code"))
    elseif status === :pre_fit_rejected
        !expected_eligible || throw(ArgumentError(
            "pre_fit_rejected requires a planned structural rejection"))
        simulation === nothing && throw(ArgumentError(
            "pre_fit_rejected rows require simulation preflight evidence"))
        diagnostic === nothing || throw(ArgumentError(
            "pre_fit_rejected rows cannot contain diagnostic evidence"))
        ismissing(failure_code) || throw(ArgumentError(
            "pre_fit_rejected is not a failure and cannot record failure_code"))
    elseif status === :generation_failed
        simulation === nothing || throw(ArgumentError(
            "generation_failed rows cannot contain simulation evidence"))
        diagnostic === nothing || throw(ArgumentError(
            "generation_failed rows cannot contain diagnostic evidence"))
        failure_code isa Symbol || throw(ArgumentError(
            "failed rows require a symbolic failure_code"))
    else
        expected_eligible || throw(ArgumentError(
            "$status is not applicable to a planned structural rejection"))
        simulation === nothing && throw(ArgumentError(
            "$status rows require generated simulation evidence"))
        diagnostic === nothing || throw(ArgumentError(
            "$status rows cannot contain completed diagnostic evidence"))
        failure_code isa Symbol || throw(ArgumentError(
            "failed rows require a symbolic failure_code"))
    end

    simulation_provenance = simulation === nothing ? missing :
        _ld1b0_validate_simulation(plan_row, simulation)
    diagnostic_provenance = diagnostic === nothing ? missing :
        _ld1b0_validate_diagnostic(simulation, diagnostic, checked_contract)
    pair_evidence = diagnostic === nothing ? () :
        _ld1b0_pair_evidence(diagnostic, checked_contract, max_pair_rows)
    family_evidence = diagnostic === nothing ? () :
        _ld1b0_family_evidence(diagnostic, pair_evidence, checked_contract)
    global_evidence = diagnostic === nothing ? missing :
        _ld1b0_global_evidence(diagnostic, checked_contract)

    return (;
        schema = "bayesianmgmfrm.local_dependence_calibration_row.v1",
        object = :local_dependence_calibration_row,
        profile = checked_contract.profile,
        planning_profile = plan_row.profile,
        protocol_status = :protocol_preflight_only,
        status,
        contract = checked_contract,
        grid_id = plan_row.grid_id,
        row_index = plan_row.row_index,
        scenario_index = plan_row.scenario_index,
        scenario_id = plan_row.scenario_id,
        matched_set_id = plan_row.matched_set_id,
        replication = plan_row.replication,
        phase = plan_row.phase,
        base_seed = plan_row.base_seed,
        seed = plan_row.seed,
        component_seeds = plan_row.component_seeds,
        mechanism = plan_row.mechanism,
        magnitude_label = plan_row.magnitude_label,
        effect_scale = plan_row.effect_scale,
        design = plan_row.design,
        assignment = plan_row.assignment,
        order = plan_row.order,
        expected_structural_eligibility = expected_eligible,
        planning_shape = _ld1b0_planning_shape(plan_row),
        truth = _ld1b0_truth(plan_row),
        execution_seeds = _ld1b0_execution_seeds(plan_row, checked_contract),
        failure_code,
        simulation_provenance,
        diagnostic_provenance,
        n_pair_evidence = length(pair_evidence),
        pair_evidence,
        family_evidence,
        global_evidence,
        target_evidence = missing,
        target_evidence_available = false,
        pair_truth_oracle_available = false,
        pairwise_power_available = false,
        repeated_calibration_completed = false,
        calibration_evidence_available = false,
        diagnostic_decision_labels_available = false,
        mechanism_interpretation_eligible = false,
        caveat = :candidate_diagnostic_decisions_for_protocol_preflight_only,
    )
end

function _ld1b0_wilson(successes::Int, trials::Int)
    0 <= successes <= trials || throw(ArgumentError(
        "Wilson successes must be between zero and trials"))
    trials == 0 && return (;
        method = :wilson_score, confidence = _LD1B0_WILSON_CONFIDENCE,
        successes, trials, estimate = missing, lower = missing, upper = missing)
    p = successes / trials
    z2 = _LD1B0_WILSON_Z^2
    denominator = 1 + z2 / trials
    center = (p + z2 / (2trials)) / denominator
    half = _LD1B0_WILSON_Z *
        sqrt((p * (1 - p) + z2 / (4trials)) / trials) / denominator
    return (;
        method = :wilson_score,
        confidence = _LD1B0_WILSON_CONFIDENCE,
        successes,
        trials,
        estimate = p,
        lower = max(0.0, center - half),
        upper = min(1.0, center + half),
    )
end

function _ld1b0_bounds(successes::Int, resolved::Int, planned::Int)
    0 <= successes <= resolved <= planned || throw(ArgumentError(
        "invalid unresolved-rate accounting"))
    planned == 0 && return (lower = missing, upper = missing)
    unresolved = planned - resolved
    return (lower = successes / planned,
        upper = (successes + unresolved) / planned)
end

function _ld1b0_result_check(result, contract)
    result isa NamedTuple || throw(ArgumentError(
        "calibration result rows must be NamedTuples"))
    required = (
        :schema, :object, :profile, :planning_profile, :protocol_status,
        :status, :contract, :grid_id, :row_index, :scenario_index,
        :scenario_id, :matched_set_id, :replication, :phase, :base_seed,
        :seed, :component_seeds, :mechanism, :magnitude_label, :effect_scale,
        :design, :assignment, :order, :expected_structural_eligibility,
        :planning_shape, :truth, :execution_seeds, :failure_code,
        :simulation_provenance, :diagnostic_provenance, :n_pair_evidence,
        :pair_evidence, :family_evidence, :global_evidence, :target_evidence,
        :target_evidence_available, :pair_truth_oracle_available,
        :pairwise_power_available, :repeated_calibration_completed,
        :calibration_evidence_available, :diagnostic_decision_labels_available,
        :mechanism_interpretation_eligible, :caveat,
    )
    all(field -> hasproperty(result, field), required) || throw(ArgumentError(
        "calibration result row is incomplete"))
    result.schema == "bayesianmgmfrm.local_dependence_calibration_row.v1" &&
        result.object === :local_dependence_calibration_row || throw(ArgumentError(
        "unexpected calibration result-row schema"))
    result.status in _LD1B0_STATUSES || throw(ArgumentError(
        "unexpected calibration result-row status"))
    result.profile === contract.profile &&
        result.protocol_status === :protocol_preflight_only ||
        throw(ArgumentError("calibration result protocol fields were modified"))
    isequal(result.contract, contract) || throw(ArgumentError(
        "calibration result rows mix contracts"))
    result.n_pair_evidence == length(result.pair_evidence) ||
        throw(ArgumentError("calibration pair-evidence count is inconsistent"))
    result.target_evidence_available === false &&
        ismissing(result.target_evidence) &&
        result.pair_truth_oracle_available === false &&
        result.pairwise_power_available === false &&
        result.repeated_calibration_completed === false &&
        result.calibration_evidence_available === false &&
        result.diagnostic_decision_labels_available === false &&
        result.mechanism_interpretation_eligible === false &&
        result.caveat ===
            :candidate_diagnostic_decisions_for_protocol_preflight_only ||
        throw(ArgumentError(
        "calibration result claim-boundary fields were modified"))
    return result
end

function _ld1b0_result_plan_check(result, plan, contract)
    isequal(result.truth, _ld1b0_truth(plan)) || throw(ArgumentError(
        "calibration result truth does not match its planning row"))
    isequal(result.execution_seeds,
        _ld1b0_execution_seeds(plan, contract)) || throw(ArgumentError(
        "calibration result execution seeds do not match its planning row"))
    isequal(result.planning_shape, _ld1b0_planning_shape(plan)) ||
        throw(ArgumentError(
            "calibration result dimensions do not match its planning row"))
    has_simulation = !ismissing(result.simulation_provenance)
    has_diagnostic = !ismissing(result.diagnostic_provenance)
    if plan.expected_requested_targets_eligible
        result.status === :pre_fit_rejected && throw(ArgumentError(
            "eligible planning rows cannot be recorded as pre-fit rejected"))
    else
        result.status in (:completed, :fit_failed, :diagnostic_failed) &&
            throw(ArgumentError(
                "planned structural rejections cannot contain fit outcomes"))
    end
    if result.status === :completed
        has_simulation && has_diagnostic || throw(ArgumentError(
            "completed result rows require simulation and diagnostic provenance"))
        ismissing(result.failure_code) || throw(ArgumentError(
            "completed result rows cannot record failure_code"))
    elseif result.status === :pre_fit_rejected
        has_simulation && !has_diagnostic || throw(ArgumentError(
            "pre-fit rejection provenance is inconsistent"))
        ismissing(result.failure_code) || throw(ArgumentError(
            "pre-fit rejection rows cannot record failure_code"))
    elseif result.status === :generation_failed
        !has_simulation && !has_diagnostic || throw(ArgumentError(
            "generation-failure provenance is inconsistent"))
        result.failure_code isa Symbol || throw(ArgumentError(
            "failed result rows require a symbolic failure_code"))
    else
        has_simulation && !has_diagnostic || throw(ArgumentError(
            "fit/diagnostic-failure provenance is inconsistent"))
        result.failure_code isa Symbol || throw(ArgumentError(
            "failed result rows require a symbolic failure_code"))
    end
    if has_simulation
        isequal(result.simulation_provenance.planning_shape,
            _ld1b0_planning_shape(plan)) || throw(ArgumentError(
            "stored simulation dimensions do not match plan"))
        observed = result.simulation_provenance.observed_shape
        shape = _ld1b0_planning_shape(plan)
        observed.n_persons == shape.n_persons &&
            observed.n_testlets == shape.n_testlets &&
            observed.n_items == shape.n_items &&
            1 <= observed.n_raters <= shape.n_raters &&
            1 <= observed.n_categories <= shape.n_categories ||
            throw(ArgumentError(
                "stored observed dimensions are inconsistent with plan"))
        result.simulation_provenance.requested_targets_eligible ===
            plan.expected_requested_targets_eligible || throw(ArgumentError(
            "stored simulation structural eligibility does not match plan"))
        allowed_actions = plan.expected_requested_targets_eligible ?
            (:structurally_eligible_for_future_candidate,
                :do_not_fit_category_support_incomplete) :
            (:do_not_fit_underidentified_design,
                :do_not_fit_category_support_incomplete)
        result.simulation_provenance.future_fit_action in allowed_actions ||
            throw(ArgumentError("stored simulation future fit action is invalid"))
    end
    if has_diagnostic
        result.diagnostic_provenance.profile ===
            contract.diagnostic_contract.profile || throw(ArgumentError(
            "stored diagnostic profile does not match protocol"))
        result.diagnostic_provenance.data_signature ==
            result.simulation_provenance.data_signature || throw(ArgumentError(
            "stored diagnostic data provenance does not match simulation"))
        isequal(result.diagnostic_provenance.observed_score_signature,
            result.simulation_provenance.observed_score_signature) ||
            throw(ArgumentError(
                "stored diagnostic score provenance does not match simulation"))
        result.diagnostic_provenance.design_signature ==
            result.simulation_provenance.testlet_design_signature ||
            throw(ArgumentError(
                "stored diagnostic design provenance does not match simulation"))
    end
    alpha = contract.candidate_thresholds
    pair_identities = Set{Tuple{Symbol,Any,Any,Any}}()
    for pair in result.pair_evidence
        pair.family in _LOCAL_DEPENDENCE_PAIR_FAMILIES || throw(ArgumentError(
            "stored pair evidence uses an unsupported family"))
        identity = (pair.family, pair.testlet_id, pair.left, pair.right)
        identity in pair_identities && throw(ArgumentError(
            "stored pair evidence contains a duplicate identity"))
        push!(pair_identities, identity)
        raw = _ld1b0_probability_or_missing(
            pair.posterior_predictive_tail_fraction,
            :posterior_predictive_tail_fraction)
        bh = _ld1b0_probability_or_missing(
            pair.bh_adjusted_tail_fraction, :bh_adjusted_tail_fraction)
        expected_eligible = pair.support_status === :eligible_report_only &&
            !ismissing(raw)
        pair.eligible === expected_eligible || throw(ArgumentError(
            "stored pair eligibility is inconsistent with support"))
        expected_eligible && ismissing(bh) && throw(ArgumentError(
            "eligible stored pair evidence is missing its BH-adjusted tail"))
        expected_raw = expected_eligible ? raw <= alpha.pair_raw_alpha : missing
        expected_bh = expected_eligible ? bh <= alpha.pair_bh_alpha : missing
        pair.candidate_raw_declared === expected_raw &&
            pair.candidate_bh_declared === expected_bh || throw(ArgumentError(
            "stored pair candidate decision is inconsistent"))
    end
    if result.status === :completed
        ismissing(result.global_evidence) && throw(ArgumentError(
            "completed result rows require global evidence"))
        length(result.family_evidence) == length(_LOCAL_DEPENDENCE_PAIR_FAMILIES) ||
            throw(ArgumentError("stored family evidence is incomplete"))
        Tuple(sort([row.family for row in result.family_evidence]; by = string)) ==
            Tuple(sort(collect(_LOCAL_DEPENDENCE_PAIR_FAMILIES); by = string)) ||
            throw(ArgumentError(
                "stored family evidence identities are not canonical"))
        for family in result.family_evidence
            all_pairs = [row for row in result.pair_evidence
                if row.family === family.family]
            pairs = [row for row in all_pairs if row.eligible]
            family.n_pair_rows == length(all_pairs) &&
                family.n_eligible_pairs == length(pairs) &&
                family.n_raw_declared == count(row ->
                    row.candidate_raw_declared === true, pairs) &&
                family.n_bh_declared == count(row ->
                    row.candidate_bh_declared === true, pairs) ||
                throw(ArgumentError(
                    "stored family evidence does not match pair evidence"))
            tail = _ld1b0_probability_or_missing(
                family.maximum_tail_fraction, :family_maximum_tail_fraction)
            expected_applicable = family.support_status !== :not_applicable
            family.applicable === expected_applicable || throw(ArgumentError(
                "stored family applicability is inconsistent"))
            expected_evaluable = expected_applicable && !ismissing(tail)
            family.family_evaluable === expected_evaluable ||
                throw(ArgumentError(
                    "stored family evaluability is inconsistent"))
            expected_any_raw = isempty(pairs) ? missing :
                any(row -> row.candidate_raw_declared === true, pairs)
            expected_any_bh = isempty(pairs) ? missing :
                any(row -> row.candidate_bh_declared === true, pairs)
            family.any_raw_declared === expected_any_raw &&
                family.any_bh_declared === expected_any_bh ||
                throw(ArgumentError(
                    "stored family any-pair decision is inconsistent"))
            expected = expected_evaluable ?
                tail <= alpha.family_maximum_alpha : missing
            family.candidate_family_declared === expected ||
                throw(ArgumentError(
                    "stored family candidate decision is inconsistent"))
        end
        global_tail = _ld1b0_probability_or_missing(
            result.global_evidence.tail_fraction,
            :global_maximum_tail_fraction)
        expected_global_evaluable = !ismissing(global_tail)
        result.global_evidence.evaluable === expected_global_evaluable ||
            throw(ArgumentError(
                "stored global evaluability is inconsistent"))
        expected_global = expected_global_evaluable ?
            global_tail <= alpha.global_maximum_alpha : missing
        result.global_evidence.candidate_global_declared === expected_global ||
            throw(ArgumentError(
                "stored global candidate decision is inconsistent"))
    elseif !isempty(result.pair_evidence) || !isempty(result.family_evidence) ||
            !ismissing(result.global_evidence)
        throw(ArgumentError(
            "non-completed result rows cannot contain diagnostic evidence"))
    end
    return result
end

function _ld1b0_binary_summary(values, planned::Int)
    resolved_values = Bool[value for value in values if !ismissing(value)]
    successes = count(identity, resolved_values)
    resolved = length(resolved_values)
    return (;
        n_planned = planned,
        n_resolved = resolved,
        n_unresolved = planned - resolved,
        rate = _ld1b0_wilson(successes, resolved),
        unresolved_bounds = _ld1b0_bounds(successes, resolved, planned),
    )
end

_ld1b0_mean_or_missing(values) = isempty(values) ? missing :
    sum(Float64(value) for value in values) / length(values)

function _ld1b0_scenario_summary(plan, results)
    completed = [row for row in results if row.status === :completed]
    eligible_planned = count(row -> row.expected_requested_targets_eligible, plan)
    pair_rows = [pair for row in completed for pair in row.pair_evidence
        if pair.eligible]
    raw_values = Any[]
    bh_values = Any[]
    global_values = Any[]
    raw_replication_rates = Float64[]
    bh_replication_rates = Float64[]
    for row in completed
        eligible = [pair for pair in row.pair_evidence if pair.eligible]
        push!(raw_values, isempty(eligible) ? missing :
            any(pair -> pair.candidate_raw_declared === true, eligible))
        push!(bh_values, isempty(eligible) ? missing :
            any(pair -> pair.candidate_bh_declared === true, eligible))
        push!(global_values, ismissing(row.global_evidence) ? missing :
            row.global_evidence.candidate_global_declared)
        if !isempty(eligible)
            push!(raw_replication_rates,
                count(pair -> pair.candidate_raw_declared === true, eligible) /
                    length(eligible))
            push!(bh_replication_rates,
                count(pair -> pair.candidate_bh_declared === true, eligible) /
                    length(eligible))
        end
    end
    missing_results = length(plan) - length(results)
    first_plan = first(plan)
    return (;
        scenario_index = first_plan.scenario_index,
        scenario_id = first_plan.scenario_id,
        matched_set_id = first_plan.matched_set_id,
        mechanism = first_plan.mechanism,
        magnitude_label = first_plan.magnitude_label,
        truth = _ld1b0_truth(first_plan),
        n_planned = length(plan),
        n_results = length(results),
        n_missing_results = missing_results,
        n_completed = length(completed),
        n_pre_fit_rejected = count(row -> row.status === :pre_fit_rejected, results),
        n_generation_failed = count(row -> row.status === :generation_failed, results),
        n_fit_failed = count(row -> row.status === :fit_failed, results),
        n_diagnostic_failed = count(row -> row.status === :diagnostic_failed, results),
        pair_raw_any = _ld1b0_binary_summary(raw_values, eligible_planned),
        pair_bh_any = _ld1b0_binary_summary(bh_values, eligible_planned),
        global_maximum = _ld1b0_binary_summary(global_values, eligible_planned),
        pooled_pair_raw = (;
            role = :descriptive_dependent_pair_pool,
            n_pairs = length(pair_rows),
            n_declared = count(pair -> pair.candidate_raw_declared === true,
                pair_rows),
            rate = isempty(pair_rows) ? missing :
                count(pair -> pair.candidate_raw_declared === true,
                    pair_rows) / length(pair_rows),
            equal_replication_weight_mean_rate =
                _ld1b0_mean_or_missing(raw_replication_rates),
            wilson_interval_available = false,
        ),
        pooled_pair_bh = (;
            role = :descriptive_dependent_pair_pool,
            n_pairs = length(pair_rows),
            n_declared = count(pair -> pair.candidate_bh_declared === true,
                pair_rows),
            rate = isempty(pair_rows) ? missing :
                count(pair -> pair.candidate_bh_declared === true,
                    pair_rows) / length(pair_rows),
            equal_replication_weight_mean_rate =
                _ld1b0_mean_or_missing(bh_replication_rates),
            wilson_interval_available = false,
        ),
        pairwise_power_available = false,
        status = :protocol_preflight_only,
    )
end

function _ld1b0_family_summary(plan, results, family::Symbol)
    completed = [row for row in results if row.status === :completed]
    family_rows = NamedTuple[]
    for result in completed
        index = findfirst(row -> row.family === family, result.family_evidence)
        index === nothing || push!(family_rows, result.family_evidence[index])
    end
    applicable = [row for row in family_rows if row.applicable]
    raw_values = Any[row.any_raw_declared for row in applicable]
    bh_values = Any[row.any_bh_declared for row in applicable]
    maximum_values = Any[row.candidate_family_declared for row in applicable]
    pooled_pairs = [pair for result in completed for pair in result.pair_evidence
        if pair.family === family && pair.eligible]
    raw_replication_rates = Float64[]
    bh_replication_rates = Float64[]
    for row in applicable
        row.n_eligible_pairs == 0 && continue
        push!(raw_replication_rates, row.n_raw_declared / row.n_eligible_pairs)
        push!(bh_replication_rates, row.n_bh_declared / row.n_eligible_pairs)
    end
    planned = count(row -> row.expected_requested_targets_eligible, plan)
    first_plan = first(plan)
    return (;
        scenario_index = first_plan.scenario_index,
        scenario_id = first_plan.scenario_id,
        family,
        complete_null = _ld1b0_truth(first_plan).complete_null,
        n_planned = planned,
        n_completed = length(completed),
        n_applicable = length(applicable),
        n_not_applicable = length(family_rows) - length(applicable),
        pair_raw_any = _ld1b0_binary_summary(raw_values, planned),
        pair_bh_any = _ld1b0_binary_summary(bh_values, planned),
        family_maximum = _ld1b0_binary_summary(maximum_values, planned),
        pooled_pair_raw_rate = isempty(pooled_pairs) ? missing :
            count(row -> row.candidate_raw_declared === true, pooled_pairs) /
                length(pooled_pairs),
        pooled_pair_bh_rate = isempty(pooled_pairs) ? missing :
            count(row -> row.candidate_bh_declared === true, pooled_pairs) /
                length(pooled_pairs),
        equal_replication_weight_mean_raw_rate =
            _ld1b0_mean_or_missing(raw_replication_rates),
        equal_replication_weight_mean_bh_rate =
            _ld1b0_mean_or_missing(bh_replication_rates),
        n_pooled_pairs = length(pooled_pairs),
        pooled_pair_wilson_interval_available = false,
        pairwise_power_available = false,
        status = :protocol_preflight_only,
    )
end

function _ld1b0_global_summary(plan, results)
    completed = [row for row in results if row.status === :completed]
    values = Any[ismissing(row.global_evidence) ? missing :
        row.global_evidence.candidate_global_declared for row in completed]
    first_plan = first(plan)
    planned = count(row -> row.expected_requested_targets_eligible, plan)
    return (;
        scenario_index = first_plan.scenario_index,
        scenario_id = first_plan.scenario_id,
        complete_null = _ld1b0_truth(first_plan).complete_null,
        role = _ld1b0_truth(first_plan).complete_null ?
            :complete_null_fwer_reference : :alternative_detection_reference,
        candidate_global_maximum = _ld1b0_binary_summary(values, planned),
        pairwise_power_available = false,
        status = :protocol_preflight_only,
    )
end

"""
    local_dependence_calibration_summary(plan_rows, result_rows;
        contract = local_dependence_calibration_contract(),
        max_plan_rows = 1_000_000, max_result_rows = 1_000_000,
        max_pair_rows = 5_000_000, max_group_rows = 100_000)

Summarize LD1b0 result rows against the complete set of planned rows. Missing
and failed replications remain explicit. Wilson intervals are used only for
replication-level binary candidate rates; pooled pair rates are descriptive.
The result remains protocol-preflight evidence and does not enable public
diagnostic decisions or mechanism labels.
"""
function local_dependence_calibration_summary(
        plan_rows::AbstractVector, result_rows::AbstractVector;
        contract = local_dependence_calibration_contract(),
        max_plan_rows::Int = 1_000_000,
        max_result_rows::Int = 1_000_000,
        max_pair_rows::Int = 5_000_000,
        max_group_rows::Int = 100_000)
    checked_contract = _ld1b0_validate_contract(contract)
    for (value, name) in ((max_plan_rows, :max_plan_rows),
            (max_result_rows, :max_result_rows),
            (max_pair_rows, :max_pair_rows),
            (max_group_rows, :max_group_rows))
        value >= 1 || throw(ArgumentError("$name must be positive"))
    end
    isempty(plan_rows) && throw(ArgumentError("plan_rows must not be empty"))
    length(plan_rows) <= max_plan_rows || throw(ArgumentError(
        "plan_rows exceed max_plan_rows=$max_plan_rows"))
    length(result_rows) <= max_result_rows || throw(ArgumentError(
        "result_rows exceed max_result_rows=$max_result_rows"))
    for row in plan_rows
        _ld1_validate_grid_row(row)
    end
    grid_ids = unique(row.grid_id for row in plan_rows)
    phases = unique(row.phase for row in plan_rows)
    base_seeds = unique(row.base_seed for row in plan_rows)
    planning_profiles = unique(row.profile for row in plan_rows)
    length(grid_ids) == 1 || throw(ArgumentError(
        "plan_rows mix grid_id values"))
    length(phases) == 1 || throw(ArgumentError("plan_rows mix phases"))
    length(base_seeds) == 1 || throw(ArgumentError(
        "plan_rows mix base_seed values"))
    length(planning_profiles) == 1 || throw(ArgumentError(
        "plan_rows mix planning profiles"))
    plan_by_index = Dict{Int,Any}()
    for row in plan_rows
        haskey(plan_by_index, row.row_index) && throw(ArgumentError(
            "plan_rows contain duplicate row_index values"))
        plan_by_index[row.row_index] = row
    end
    result_by_index = Dict{Int,Any}()
    total_pairs = 0
    for result in result_rows
        _ld1b0_result_check(result, checked_contract)
        result.grid_id == only(grid_ids) || throw(ArgumentError(
            "result_rows mix grid_id values"))
        result.phase === only(phases) || throw(ArgumentError(
            "result_rows mix phases"))
        plan = get(plan_by_index, result.row_index, nothing)
        plan === nothing && throw(ArgumentError(
            "result row has no matching planning row"))
        _ld1b0_result_plan_check(result, plan, checked_contract)
        for field in (:grid_id, :scenario_index, :scenario_id, :matched_set_id,
                :replication, :phase, :base_seed, :seed, :mechanism,
                :component_seeds, :magnitude_label, :effect_scale, :design,
                :assignment, :order, :expected_structural_eligibility)
            plan_field = field === :expected_structural_eligibility ?
                :expected_requested_targets_eligible : field
            isequal(getproperty(result, field), getproperty(plan, plan_field)) ||
                throw(ArgumentError(
                    "result field :$field does not match its planning row"))
        end
        result.planning_profile === plan.profile || throw(ArgumentError(
            "result planning_profile does not match its planning row"))
        haskey(result_by_index, result.row_index) && throw(ArgumentError(
            "result_rows contain duplicate planning-row results"))
        result_by_index[result.row_index] = result
        length(result.pair_evidence) <= max_pair_rows - total_pairs ||
            throw(ArgumentError(
                "nested pair evidence exceeds max_pair_rows=$max_pair_rows"))
        total_pairs += length(result.pair_evidence)
    end

    scenario_indices = sort(unique(row.scenario_index for row in plan_rows))
    matched_sets = sort(unique(row.matched_set_id for row in plan_rows);
        by = string)
    n_families = length(_LOCAL_DEPENDENCE_PAIR_FAMILIES)
    projected_groups = length(scenario_indices) * (2 + n_families) +
        length(matched_sets)
    projected_groups <= max_group_rows || throw(ArgumentError(
        "summary groups exceed max_group_rows=$max_group_rows"))

    scenario_rows = NamedTuple[]
    family_rows = NamedTuple[]
    global_rows = NamedTuple[]
    for scenario_index in scenario_indices
        plan = [row for row in plan_rows if row.scenario_index == scenario_index]
        results = [result_by_index[row.row_index] for row in plan
            if haskey(result_by_index, row.row_index)]
        push!(scenario_rows, _ld1b0_scenario_summary(plan, results))
        for family in _LOCAL_DEPENDENCE_PAIR_FAMILIES
            push!(family_rows, _ld1b0_family_summary(plan, results, family))
        end
        push!(global_rows, _ld1b0_global_summary(plan, results))
    end

    matched_set_rows = Tuple((function ()
        plan = [row for row in plan_rows if row.matched_set_id === matched_set]
        results = [result_by_index[row.row_index] for row in plan
            if haskey(result_by_index, row.row_index)]
        replications = sort(unique(row.replication for row in plan))
        resolved_statuses = (:completed, :pre_fit_rejected)
        fully_resolved = count(replication -> begin
            cells = [row for row in plan if row.replication == replication]
            all(cell -> haskey(result_by_index, cell.row_index) &&
                result_by_index[cell.row_index].status in resolved_statuses,
                cells)
        end, replications)
        (;
            matched_set_id = matched_set,
            n_scenarios = length(unique(row.scenario_id for row in plan)),
            n_planned = length(plan),
            n_results = length(results),
            n_replications = length(replications),
            n_fully_resolved_replications = fully_resolved,
            n_incomplete_replications = length(replications) - fully_resolved,
            status = :protocol_preflight_only,
        )
    end)() for matched_set in matched_sets)

    missing_count = length(plan_rows) - length(result_rows)
    status_rows = Tuple((;
        status,
        n = count(row -> row.status === status, result_rows),
    ) for status in _LD1B0_STATUSES)
    return (;
        schema = "bayesianmgmfrm.local_dependence_calibration_summary.v1",
        object = :local_dependence_calibration_summary,
        profile = checked_contract.profile,
        status = :protocol_preflight_only,
        contract = checked_contract,
        grid_id = only(grid_ids),
        phase = only(phases),
        base_seed = only(base_seeds),
        planning_profile = only(planning_profiles),
        n_plan_rows = length(plan_rows),
        n_result_rows = length(result_rows),
        n_missing_result_rows = missing_count,
        n_pair_evidence_rows = total_pairs,
        n_scenarios = length(scenario_rows),
        n_matched_sets = length(matched_set_rows),
        status_rows,
        scenario_rows = Tuple(scenario_rows),
        family_rows = Tuple(family_rows),
        global_rows = Tuple(global_rows),
        matched_set_rows,
        target_evidence_available = false,
        pair_truth_oracle_available = false,
        pairwise_power_available = false,
        repeated_calibration_completed = false,
        calibration_evidence_available = false,
        diagnostic_decision_labels_available = false,
        mechanism_interpretation_eligible = false,
        caveats = (
            :protocol_preflight_candidate_rates_not_enabled_decisions,
            :pooled_pair_rates_are_descriptive_and_not_binomial,
            :pairwise_power_requires_a_pair_truth_oracle,
            :missing_and_failed_replications_are_not_treated_as_nondeclarations,
        ),
    )
end
