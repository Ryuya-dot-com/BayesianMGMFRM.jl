# local_dependence_calibration_pilot.jl -- LD1b1 pilot protocol preflight

const _LD1B1_PILOT_PROFILE = :ld1b1_pilot_protocol_v1
const _LD1B1_PILOT_REPETITIONS = 30
const _LD1B1_EVALUATION_REPETITIONS = (50, 100)
const _LD1B1_BASE_DIMENSIONS = (;
    n_persons = 40,
    n_testlets = 4,
    items_per_testlet = 3,
    n_raters = 4,
    n_categories = 4,
)
const _LD1B1_EXPECTED_TOTALS = (;
    n_jobs = 660,
    n_fit_jobs = 540,
    n_pre_fit_rejection_jobs = 120,
    n_ratings = 396_840,
    n_probability_cells = 1_587_360,
    n_truth_cells = 10_240_500,
)
const _LD1B1_RESOURCE_CAPS = (;
    n_jobs = 700,
    n_fit_jobs = 600,
    n_ratings = 500_000,
    n_probability_cells = 2_000_000,
    n_truth_cells = 13_000_000,
)
const _LD1B1_PER_DATASET_CAPS = (;
    n_ratings = 2_500,
    n_probability_cells = 10_000,
    n_truth_cells = 60_000,
)

"""
    local_dependence_calibration_pilot_contract(;
        calibration_contract = local_dependence_calibration_contract())

Return the fixed LD1b1 planning contract for the 30-replication diagnostic
pilot. The contract fixes the complete LD1a scenario set, computation and
quality requirements, operational completion bounds, Wilson-interval precision
references, and bounded generator workload. Evaluation uses either 50 or 100
replications, selected after the pilot and before any evaluation result is
observed; a mid-evaluation extension is not part of this protocol.

This object is planning evidence only. It does not execute fitting, complete
the pilot, freeze an evaluation profile, enable diagnostic decisions, or
support a dependence-mechanism interpretation. Pairwise power remains outside
this protocol because the current generator has no pair-specific truth oracle.
"""
function local_dependence_calibration_pilot_contract(;
        calibration_contract = local_dependence_calibration_contract())
    checked_calibration = _ld1b0_validate_contract(calibration_contract)
    return (;
        schema =
            "bayesianmgmfrm.local_dependence_calibration_pilot_contract.v1",
        object = :local_dependence_calibration_pilot_contract,
        profile = _LD1B1_PILOT_PROFILE,
        status = :pilot_protocol_preflight_only,
        calibration_contract = checked_calibration,
        planning = (;
            planning_profile = _LD1_PROFILE,
            family = :mfrm,
            thresholds = :partial_credit,
            phase = :pilot,
            pilot_repetitions = _LD1B1_PILOT_REPETITIONS,
            evaluation_repetition_candidates =
                _LD1B1_EVALUATION_REPETITIONS,
            evaluation_repetitions_selected_before_evaluation = true,
            mid_evaluation_extension_allowed = false,
            n_scenarios = length(_LD1_SCENARIOS),
            n_structurally_eligible_scenarios = count(
                row -> row.expected_requested_targets_eligible,
                _LD1_SCENARIOS,
            ),
            n_structural_rejection_scenarios = count(
                row -> !row.expected_requested_targets_eligible,
                _LD1_SCENARIOS,
            ),
            n_jobs = _LD1B1_EXPECTED_TOTALS.n_jobs,
            n_fit_jobs = _LD1B1_EXPECTED_TOTALS.n_fit_jobs,
            n_pre_fit_rejection_jobs =
                _LD1B1_EXPECTED_TOTALS.n_pre_fit_rejection_jobs,
            base_dimensions = _LD1B1_BASE_DIMENSIONS,
            complete_scenario_by_replication_cross_required = true,
        ),
        sampler = (;
            backend = :advancedhmc,
            algorithm = :nuts,
            chains = 4,
            warmup_per_chain = 500,
            draws_per_chain = 500,
            total_retained_draws = 2_000,
            target_accept = 0.90,
            max_depth = 10,
            metric = :diagonal,
            ad_backend = :analytic,
            split_chains = true,
            diagnostic_draws = 250,
            diagnostic_draw_policy = :distinct_without_replacement,
            posterior_predictive_replicates_per_draw = 1,
        ),
        quality_requirements = (;
            diagnostic_contract = _MCMC_DIAGNOSTIC_CONTRACT,
            diagnostic_contract_details =
                _mcmc_diagnostic_contract_record(),
            rhat_method = :rank_normalized,
            primary_rhat_field = :rank_normalized_rhat,
            maximum_rhat = 1.01,
            ess_method = :bulk_and_tail,
            primary_ess_fields = (:bulk_ess, :tail_ess),
            primary_flag_field = :rank_normalized_flag,
            tail_probability = _RANK_NORMALIZED_TAIL_PROBABILITY,
            minimum_bulk_ess = 400,
            minimum_tail_ess = 400,
            maximum_divergences = 0,
            maximum_depth_hits = 0,
            e_bfmi_field = :e_bfmi,
            e_bfmi_completeness_field = :e_bfmi_complete,
            e_bfmi_chain_coverage_required = true,
            minimum_e_bfmi = 0.30,
        ),
        operational_requirements = (;
            minimum_completed_per_eligible_scenario = 27,
            maximum_categorized_failures_per_eligible_scenario = 3,
            categorized_failure_statuses = (
                :generation_failed,
                :fit_failed,
                :diagnostic_failed,
            ),
            required_missing_results = 0,
            required_pre_fit_rejections_per_rejection_scenario = 30,
            primary_attempt = 1,
            primary_outcomes_overwritable_by_retries = false,
            retry_role = :separate_remediation_record_only,
        ),
        precision_policy = (;
            method = :wilson_score,
            confidence = _LD1B0_WILSON_CONFIDENCE,
            applies_to = :replication_level_binary_rates_only,
            pilot_maximum_half_width = 0.18,
            evaluation_target_half_width = 0.10,
            evaluation_repetition_candidates =
                _LD1B1_EVALUATION_REPETITIONS,
            selection_time = :after_pilot_before_evaluation,
            mid_evaluation_extension_allowed = false,
            pooled_pair_interval_available = false,
        ),
        resource_policy = (;
            expected_totals = _LD1B1_EXPECTED_TOTALS,
            total_caps = _LD1B1_RESOURCE_CAPS,
            per_dataset_caps = _LD1B1_PER_DATASET_CAPS,
            positive_total_headroom_required = true,
        ),
        pair_truth_oracle_available = false,
        pairwise_power_available = false,
        pairwise_power_scope = :out_of_scope_without_pair_truth_oracle,
        pilot_execution_completed = false,
        evaluation_profile_frozen = false,
        repeated_calibration_completed = false,
        calibration_evidence_available = false,
        diagnostic_decision_labels_available = false,
        mechanism_interpretation_eligible = false,
    )
end

function _ld1b1_validate_pilot_contract(contract)
    contract isa NamedTuple || throw(ArgumentError(
        "contract must be returned by local_dependence_calibration_pilot_contract"))
    required = (
        :schema, :object, :profile, :status, :calibration_contract,
        :planning, :sampler, :quality_requirements,
        :operational_requirements, :precision_policy, :resource_policy,
        :pair_truth_oracle_available, :pairwise_power_available,
        :pairwise_power_scope, :pilot_execution_completed,
        :evaluation_profile_frozen, :repeated_calibration_completed,
        :calibration_evidence_available,
        :diagnostic_decision_labels_available,
        :mechanism_interpretation_eligible,
    )
    all(field -> hasproperty(contract, field), required) || throw(ArgumentError(
        "pilot contract is incomplete"))
    canonical = local_dependence_calibration_pilot_contract(;
        calibration_contract = contract.calibration_contract,
    )
    isequal(contract, canonical) || throw(ArgumentError(
        "contract must be an unmodified local_dependence_calibration_pilot_contract result"))
    return contract
end

function _ld1b1_checked_add(total::Int, value::Int, name::Symbol)
    return try
        Base.Checked.checked_add(total, value)
    catch error
        error isa OverflowError || rethrow()
        throw(ArgumentError("$name exceeds the supported integer range"))
    end
end

function _ld1b1_resource_row(row, per_dataset_caps)
    n_items = try
        Base.Checked.checked_mul(row.n_testlets, row.items_per_testlet)
    catch error
        error isa OverflowError || rethrow()
        throw(ArgumentError("planned item count exceeds the supported integer range"))
    end
    n_ratings = _ld1_preflight_rating_count(
        row.design,
        row.n_persons,
        row.n_testlets,
        row.items_per_testlet,
        row.n_raters,
        per_dataset_caps.n_ratings,
    )
    n_probability_cells = try
        Base.Checked.checked_mul(n_ratings, row.n_categories)
    catch error
        error isa OverflowError || rethrow()
        throw(ArgumentError(
            "planned probability workload exceeds the supported integer range"))
    end
    n_probability_cells <= per_dataset_caps.n_probability_cells ||
        throw(ArgumentError(
            "planned probability workload exceeds the per-dataset cap"))
    truth = _ld1_preflight_truth_counts(
        row.n_persons,
        row.n_testlets,
        n_items,
        row.n_raters,
        row.n_categories,
        n_ratings,
        n_probability_cells,
        per_dataset_caps.n_truth_cells,
    )
    return (;
        n_ratings,
        n_probability_cells,
        n_truth_cells = truth.n_truth_cells,
    )
end

function _ld1b1_resource_summary(plan_rows, contract)
    per_dataset_caps = contract.resource_policy.per_dataset_caps
    resources = [_ld1b1_resource_row(row, per_dataset_caps) for row in plan_rows]
    total_ratings = 0
    total_probability = 0
    total_truth = 0
    for row in resources
        total_ratings = _ld1b1_checked_add(
            total_ratings, row.n_ratings, :total_ratings)
        total_probability = _ld1b1_checked_add(
            total_probability,
            row.n_probability_cells,
            :total_probability_cells,
        )
        total_truth = _ld1b1_checked_add(
            total_truth, row.n_truth_cells, :total_truth_cells)
    end
    actual = (;
        n_jobs = length(plan_rows),
        n_fit_jobs = count(
            row -> row.expected_requested_targets_eligible,
            plan_rows,
        ),
        n_pre_fit_rejection_jobs = count(
            row -> !row.expected_requested_targets_eligible,
            plan_rows,
        ),
        n_ratings = total_ratings,
        n_probability_cells = total_probability,
        n_truth_cells = total_truth,
    )
    expected = contract.resource_policy.expected_totals
    caps = contract.resource_policy.total_caps
    actual_matches_reference = isequal(actual, expected)
    within_total_caps = actual.n_jobs <= caps.n_jobs &&
        actual.n_fit_jobs <= caps.n_fit_jobs &&
        actual.n_ratings <= caps.n_ratings &&
        actual.n_probability_cells <= caps.n_probability_cells &&
        actual.n_truth_cells <= caps.n_truth_cells
    positive_total_headroom = actual.n_jobs < caps.n_jobs &&
        actual.n_fit_jobs < caps.n_fit_jobs &&
        actual.n_ratings < caps.n_ratings &&
        actual.n_probability_cells < caps.n_probability_cells &&
        actual.n_truth_cells < caps.n_truth_cells
    maxima = (;
        n_ratings = maximum(row -> row.n_ratings, resources),
        n_probability_cells = maximum(
            row -> row.n_probability_cells,
            resources,
        ),
        n_truth_cells = maximum(row -> row.n_truth_cells, resources),
    )
    within_per_dataset_caps =
        maxima.n_ratings <= per_dataset_caps.n_ratings &&
        maxima.n_probability_cells <= per_dataset_caps.n_probability_cells &&
        maxima.n_truth_cells <= per_dataset_caps.n_truth_cells
    checks = (;
        actual_matches_reference,
        within_total_caps,
        positive_total_headroom,
        within_per_dataset_caps,
        passed = actual_matches_reference && within_total_caps &&
            positive_total_headroom && within_per_dataset_caps,
    )
    return (; resources, actual, maxima, checks)
end

function _ld1b1_precision_row(replications::Int, role::Symbol, threshold::Float64)
    successes = fld(replications, 2)
    interval = _ld1b0_wilson(successes, replications)
    half_width = (interval.upper - interval.lower) / 2
    return (;
        role,
        replications,
        worst_case_successes = successes,
        estimate = interval.estimate,
        lower = interval.lower,
        upper = interval.upper,
        half_width,
        maximum_half_width = threshold,
        precision_requirement_met = half_width <= threshold,
    )
end

function _ld1b1_precision_reference(contract)
    policy = contract.precision_policy
    rows = NamedTuple[_ld1b1_precision_row(
        contract.planning.pilot_repetitions,
        :pilot,
        policy.pilot_maximum_half_width,
    )]
    for replications in policy.evaluation_repetition_candidates
        push!(rows, _ld1b1_precision_row(
            replications,
            :evaluation_candidate,
            policy.evaluation_target_half_width,
        ))
    end
    return Tuple(rows)
end

function _ld1b1_sampler_capability(contract)
    policy = _diagnostic_row_policy(;
        family = :mfrm,
        parameter_spaces = (:identified,),
    )
    rank_available = policy.rank_normalized_rhat_available === true
    bulk_tail_available = policy.bulk_tail_ess_available === true
    rank_method_matches = policy.rhat_method ===
        contract.quality_requirements.rhat_method
    ess_method_matches = policy.ess_method ===
        contract.quality_requirements.ess_method
    contract_id_matches = policy.diagnostic_contract ===
        contract.quality_requirements.diagnostic_contract
    contract_details_match = isequal(
        policy.diagnostic_contract_details,
        contract.quality_requirements.diagnostic_contract_details,
    )
    primary_fields_match =
        policy.primary_rhat_field ===
            contract.quality_requirements.primary_rhat_field &&
        policy.primary_ess_fields ==
            contract.quality_requirements.primary_ess_fields &&
        policy.primary_flag_field ===
            contract.quality_requirements.primary_flag_field
    tail_probability_matches = policy.tail_probability ==
        contract.quality_requirements.tail_probability
    e_bfmi_contract_matches =
        policy.e_bfmi_field ===
            contract.quality_requirements.e_bfmi_field &&
        policy.e_bfmi_completeness_field ===
            contract.quality_requirements.e_bfmi_completeness_field &&
        policy.e_bfmi_chain_coverage_required ===
            contract.quality_requirements.e_bfmi_chain_coverage_required
    minimum_chains = policy.diagnostic_contract_details.
        minimum_independent_chains
    minimum_diagnostic_draws = policy.diagnostic_contract_details.
        minimum_draws_per_diagnostic_chain_for_ess
    planned_diagnostic_draws_per_chain = contract.sampler.split_chains ?
        div(
            contract.sampler.draws_per_chain,
            policy.diagnostic_contract_details.split_factor,
        ) : contract.sampler.draws_per_chain
    chain_requirement_met = contract.sampler.chains >= minimum_chains
    draw_requirement_met =
        planned_diagnostic_draws_per_chain >= minimum_diagnostic_draws
    blockers = Symbol[]
    if !rank_available
        push!(blockers, :rank_normalized_rhat_unavailable)
    elseif !rank_method_matches
        push!(blockers, :rank_normalized_rhat_method_mismatch)
    end
    if !bulk_tail_available
        push!(blockers, :bulk_tail_ess_unavailable)
    elseif !ess_method_matches
        push!(blockers, :bulk_tail_ess_method_mismatch)
    end
    contract_id_matches ||
        push!(blockers, :diagnostic_contract_mismatch)
    contract_details_match ||
        push!(blockers, :diagnostic_contract_details_mismatch)
    primary_fields_match ||
        push!(blockers, :diagnostic_primary_fields_mismatch)
    tail_probability_matches ||
        push!(blockers, :diagnostic_tail_probability_mismatch)
    e_bfmi_contract_matches ||
        push!(blockers, :e_bfmi_coverage_contract_mismatch)
    chain_requirement_met ||
        push!(blockers, :insufficient_planned_independent_chains)
    draw_requirement_met ||
        push!(blockers, :insufficient_planned_diagnostic_draws)
    passed = isempty(blockers)
    return (;
        current_rhat_method = policy.rhat_method,
        current_ess_method = policy.ess_method,
        current_rhat_ess_status = policy.rhat_ess_status,
        current_diagnostic_contract = policy.diagnostic_contract,
        current_diagnostic_contract_details =
            policy.diagnostic_contract_details,
        required_diagnostic_contract =
            contract.quality_requirements.diagnostic_contract,
        required_diagnostic_contract_details =
            contract.quality_requirements.diagnostic_contract_details,
        rank_normalized_rhat_available = rank_available,
        bulk_tail_ess_available = bulk_tail_available,
        required_rhat_method = contract.quality_requirements.rhat_method,
        required_ess_method = contract.quality_requirements.ess_method,
        rhat_method_matches_requirement = rank_method_matches,
        ess_method_matches_requirement = ess_method_matches,
        diagnostic_contract_matches_requirement = contract_id_matches,
        diagnostic_contract_details_match_requirement =
            contract_details_match,
        primary_fields_match_requirement = primary_fields_match,
        tail_probability_matches_requirement = tail_probability_matches,
        e_bfmi_contract_matches_requirement = e_bfmi_contract_matches,
        minimum_independent_chains = minimum_chains,
        planned_independent_chains = contract.sampler.chains,
        independent_chain_requirement_met = chain_requirement_met,
        minimum_draws_per_diagnostic_chain = minimum_diagnostic_draws,
        planned_draws_per_diagnostic_chain =
            planned_diagnostic_draws_per_chain,
        diagnostic_draw_requirement_met = draw_requirement_met,
        requirement_met = passed,
        blockers = Tuple(blockers),
    )
end

function _ld1b1_seed_values(rows, calibration_contract)
    root = Set{Int}()
    component = Set{Int}()
    execution = Set{Int}()
    execution_identities = Set{NTuple{3,Int}}()
    for row in rows
        push!(root, row.seed)
        union!(component, Int[value for value in values(row.component_seeds)])
        seeds = _ld1b0_execution_seeds(row, calibration_contract)
        identity = (seeds.fit, seeds.draw_selection,
            seeds.posterior_predictive)
        push!(execution_identities, identity)
        union!(execution, Int[identity...])
    end
    return (; root, component, execution, execution_identities)
end

function _ld1b1_seed_checks(plan_rows, contract, grid_id::String,
        base_seed::Int)
    dimensions = contract.planning.base_dimensions
    evaluation_rows = local_dependence_simulation_grid(;
        repetitions = maximum(contract.planning.evaluation_repetition_candidates),
        base_seed,
        phase = :evaluation,
        grid_id,
        dimensions...,
    )
    pilot = _ld1b1_seed_values(plan_rows, contract.calibration_contract)
    evaluation = _ld1b1_seed_values(
        evaluation_rows,
        contract.calibration_contract,
    )
    pilot_root_unique_by_replication =
        length(pilot.root) == contract.planning.pilot_repetitions
    scenario_specific_execution_seeds =
        length(pilot.execution_identities) == length(plan_rows)
    pilot_execution_seed_values_unique =
        length(pilot.execution) == 3 * length(plan_rows)
    root_namespaces_disjoint = isempty(intersect(pilot.root, evaluation.root))
    component_namespaces_disjoint =
        isempty(intersect(pilot.component, evaluation.component))
    execution_namespaces_disjoint =
        isempty(intersect(pilot.execution, evaluation.execution))
    passed = pilot_root_unique_by_replication &&
        scenario_specific_execution_seeds &&
        pilot_execution_seed_values_unique && root_namespaces_disjoint &&
        component_namespaces_disjoint && execution_namespaces_disjoint
    return (;
        pilot_root_unique_by_replication,
        scenario_specific_execution_seeds,
        pilot_execution_seed_values_unique,
        root_namespaces_disjoint,
        component_namespaces_disjoint,
        execution_namespaces_disjoint,
        n_unique_pilot_root_seeds = length(pilot.root),
        n_unique_pilot_execution_seed_values = length(pilot.execution),
        n_evaluation_replications_checked =
            maximum(contract.planning.evaluation_repetition_candidates),
        passed,
    )
end

function _ld1b1_job_rows(plan_rows, resources, contract)
    return Tuple((function ()
        seeds = _ld1b0_execution_seeds(row, contract.calibration_contract)
        expected_action = row.expected_requested_targets_eligible ?
            :fit_and_score_diagnostic : :pre_fit_reject
        (;
            row_index = row.row_index,
            scenario_index = row.scenario_index,
            scenario_id = row.scenario_id,
            matched_set_id = row.matched_set_id,
            replication = row.replication,
            phase = row.phase,
            seed = row.seed,
            fit_seed = seeds.fit,
            draw_selection_seed = seeds.draw_selection,
            posterior_predictive_seed = seeds.posterior_predictive,
            expected_action,
            expected_structural_eligibility =
                row.expected_requested_targets_eligible,
            resources = resources[index],
            primary_attempt =
                contract.operational_requirements.primary_attempt,
            primary_outcome_overwritable_by_retries =
                contract.operational_requirements.
                    primary_outcomes_overwritable_by_retries,
            execution_status = :not_executed,
        )
    end)() for (index, row) in pairs(plan_rows))
end

"""
    local_dependence_calibration_pilot_preflight(plan_rows;
        contract = local_dependence_calibration_pilot_contract())

Validate the complete 660-job LD1b1 pilot plan without generating scores or
fitting models. The plan must be the unmodified 22-scenario by 30-replication
cross returned by `local_dependence_simulation_grid` with `phase = :pilot` and
the fixed base dimensions. The result records compact job rows, deterministic
workload counts, Wilson precision references, pilot/evaluation seed separation,
and the currently available sampler-diagnostic capability.

Execution is authorized only when the required rank-normalized R-hat and
bulk/tail ESS capabilities match the frozen quality contract. Authorization
does not execute the pilot: a successful planning preflight alone is not
calibration evidence and does not enable decision or mechanism labels.
"""
function local_dependence_calibration_pilot_preflight(
        plan_rows::AbstractVector;
        contract = local_dependence_calibration_pilot_contract())
    checked_contract = _ld1b1_validate_pilot_contract(contract)
    isempty(plan_rows) && throw(ArgumentError("plan_rows must not be empty"))
    length(plan_rows) == checked_contract.planning.n_jobs || throw(ArgumentError(
        "pilot plan must contain exactly $(checked_contract.planning.n_jobs) rows"))
    for row in plan_rows
        _ld1_validate_grid_row(row)
    end

    grid_ids = unique(row.grid_id for row in plan_rows)
    base_seeds = unique(row.base_seed for row in plan_rows)
    profiles = unique(row.profile for row in plan_rows)
    phases = unique(row.phase for row in plan_rows)
    length(grid_ids) == 1 || throw(ArgumentError(
        "pilot plan must use one grid_id"))
    length(base_seeds) == 1 || throw(ArgumentError(
        "pilot plan must use one base_seed"))
    length(profiles) == 1 || throw(ArgumentError(
        "pilot plan must use one planning profile"))
    phases == [:pilot] || throw(ArgumentError(
        "pilot plan must use phase = :pilot only"))
    only(profiles) === checked_contract.planning.planning_profile ||
        throw(ArgumentError("pilot planning profile does not match contract"))
    grid_id = only(grid_ids)
    base_seed = only(base_seeds)
    dimensions = checked_contract.planning.base_dimensions
    canonical = local_dependence_simulation_grid(;
        repetitions = checked_contract.planning.pilot_repetitions,
        base_seed,
        phase = :pilot,
        grid_id,
        dimensions...,
    )
    isequal(collect(plan_rows), canonical) || throw(ArgumentError(
        "plan_rows must be the ordered, unmodified canonical LD1b1 pilot grid"))

    replications = sort(unique(row.replication for row in plan_rows))
    expected_replications = collect(1:checked_contract.planning.pilot_repetitions)
    replications == expected_replications || throw(ArgumentError(
        "pilot replications must be exactly 1:$(checked_contract.planning.pilot_repetitions)"))
    scenario_ids = Tuple(row.scenario_id for row in _LD1_SCENARIOS)
    scenario_counts = Tuple((;
        scenario_id,
        n = count(row -> row.scenario_id === scenario_id, plan_rows),
    ) for scenario_id in scenario_ids)
    all(row -> row.n == checked_contract.planning.pilot_repetitions,
        scenario_counts) || throw(ArgumentError(
        "every frozen scenario must occur exactly once per pilot replication"))
    row_indexes = [row.row_index for row in plan_rows]
    row_indexes == collect(1:length(plan_rows)) || throw(ArgumentError(
        "pilot row indexes must be consecutive and canonically ordered"))

    n_fit_jobs = count(
        row -> row.expected_requested_targets_eligible,
        plan_rows,
    )
    n_pre_fit_rejection_jobs = length(plan_rows) - n_fit_jobs
    n_fit_jobs == checked_contract.planning.n_fit_jobs || throw(ArgumentError(
        "pilot fit-job routing does not match contract"))
    n_pre_fit_rejection_jobs ==
        checked_contract.planning.n_pre_fit_rejection_jobs ||
        throw(ArgumentError(
            "pilot pre-fit rejection routing does not match contract"))
    rejection_counts = Tuple((;
        scenario_id = scenario.scenario_id,
        n = count(row -> row.scenario_id === scenario.scenario_id,
            plan_rows),
    ) for scenario in _LD1_SCENARIOS
        if !scenario.expected_requested_targets_eligible)
    all(row -> row.n == checked_contract.operational_requirements.
            required_pre_fit_rejections_per_rejection_scenario,
        rejection_counts) || throw(ArgumentError(
        "structural rejection scenarios do not match the required denominator"))

    resource = _ld1b1_resource_summary(plan_rows, checked_contract)
    resource.checks.passed || throw(ArgumentError(
        "pilot resource plan does not satisfy its frozen counts and caps"))
    seed_checks = _ld1b1_seed_checks(
        plan_rows,
        checked_contract,
        grid_id,
        base_seed,
    )
    seed_checks.passed || throw(ArgumentError(
        "pilot and evaluation seed namespaces are not valid and disjoint"))
    plan_checks = (;
        canonical_row_count = length(plan_rows) ==
            checked_contract.planning.n_jobs,
        canonical_row_order = row_indexes == collect(1:length(plan_rows)),
        exact_replication_set = replications == expected_replications,
        exact_scenario_counts = all(row -> row.n ==
            checked_contract.planning.pilot_repetitions, scenario_counts),
        single_grid_id = length(grid_ids) == 1,
        single_base_seed = length(base_seeds) == 1,
        single_planning_profile = length(profiles) == 1,
        pilot_phase_only = phases == [:pilot],
        exact_fit_routing = n_fit_jobs ==
            checked_contract.planning.n_fit_jobs,
        exact_pre_fit_rejection_routing = n_pre_fit_rejection_jobs ==
            checked_contract.planning.n_pre_fit_rejection_jobs,
        passed = true,
    )
    sampler_capability = _ld1b1_sampler_capability(checked_contract)
    pilot_execution_authorized = plan_checks.passed &&
        resource.checks.passed && seed_checks.passed &&
        sampler_capability.requirement_met
    status = pilot_execution_authorized ?
        :pilot_plan_preflight_passed :
        :pilot_plan_preflight_blocked_by_sampler_capability
    precision_reference = _ld1b1_precision_reference(checked_contract)
    return (;
        schema =
            "bayesianmgmfrm.local_dependence_calibration_pilot_preflight.v1",
        object = :local_dependence_calibration_pilot_preflight,
        profile = checked_contract.profile,
        status,
        contract = checked_contract,
        grid_id,
        base_seed,
        planning_profile = only(profiles),
        phase = :pilot,
        n_plan_rows = length(plan_rows),
        n_scenarios = length(scenario_ids),
        n_replications = length(replications),
        n_fit_jobs,
        n_pre_fit_rejection_jobs,
        scenario_counts,
        rejection_counts,
        job_rows = _ld1b1_job_rows(
            plan_rows,
            resource.resources,
            checked_contract,
        ),
        precision_reference,
        evaluation_repetitions_selected = missing,
        evaluation_repetition_selection_status = :pending_pilot_results,
        plan_checks,
        resource_summary = (;
            actual = resource.actual,
            caps = checked_contract.resource_policy.total_caps,
            per_dataset_caps =
                checked_contract.resource_policy.per_dataset_caps,
            maxima = resource.maxima,
            checks = resource.checks,
        ),
        seed_checks,
        sampler_capability,
        capability_blockers = sampler_capability.blockers,
        pair_truth_oracle_available = false,
        pairwise_power_available = false,
        pairwise_power_scope = :out_of_scope_without_pair_truth_oracle,
        pilot_execution_authorized,
        pilot_execution_completed = false,
        evaluation_profile_frozen = false,
        repeated_calibration_completed = false,
        calibration_evidence_available = false,
        diagnostic_decision_labels_available = false,
        mechanism_interpretation_eligible = false,
        caveats = (
            :planning_preflight_is_not_pilot_execution,
            :primary_outcomes_cannot_be_replaced_by_retry_results,
            :evaluation_size_must_be_selected_before_evaluation,
            :pairwise_power_requires_a_pair_truth_oracle,
        ),
    )
end
