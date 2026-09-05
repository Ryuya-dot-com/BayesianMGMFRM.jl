# MCMC-free known-truth response-pattern stress generation and preflight.

using Random

const _MGMFRM_RESPONSE_STRESS_PATTERNS = (
    :regular_all_categories,
    :unused_interior_category_3,
    :all_maximum_person,
    :all_minimum_rater,
    :combined_unused_category_and_boundary_patterns,
)

const _MGMFRM_RESPONSE_STRESS_DESIGNS = (
    :dense_fully_crossed,
    :connected_sparse_systematic_link,
)

# Plan construction and validation.

function _mgmfrm_stress_selection(values, allowed, label::AbstractString)
    selected = Tuple(Symbol(value) for value in values)
    isempty(selected) && throw(ArgumentError("$label must not be empty"))
    length(unique(selected)) == length(selected) ||
        throw(ArgumentError("$label contains duplicate values"))
    unsupported = Tuple(value for value in selected if !(value in allowed))
    isempty(unsupported) || throw(ArgumentError(
        "$label contains unsupported values: $(join(string.(unsupported), ", "))",
    ))
    return selected
end

function _mgmfrm_stress_positive_integer(value::Integer, label::AbstractString;
        minimum::Int = 1)
    Int(value) >= minimum ||
        throw(ArgumentError("$label must be >= $minimum"))
    return Int(value)
end

function _mgmfrm_stress_expected_pattern(pattern::Symbol, design::Symbol)
    combined = pattern === :combined_unused_category_and_boundary_patterns
    target_person = pattern in (
        :all_maximum_person,
        :combined_unused_category_and_boundary_patterns,
    ) ? (combined ? "P2" : "P1") : missing
    target_rater = pattern in (
        :all_minimum_rater,
        :combined_unused_category_and_boundary_patterns,
    ) ? "R1" : missing
    return (;
        unused_interior_category_3 = pattern in (
            :unused_interior_category_3,
            :combined_unused_category_and_boundary_patterns,
        ),
        all_maximum_person = pattern in (
            :all_maximum_person,
            :combined_unused_category_and_boundary_patterns,
        ),
        all_minimum_rater = pattern in (
            :all_minimum_rater,
            :combined_unused_category_and_boundary_patterns,
        ),
        target_person,
        target_rater,
        boundary_targets_have_no_common_observations = combined ?
            design === :connected_sparse_systematic_link : missing,
    )
end

"""
    mgmfrm_response_stress_plan(; design_strata = (...),
        response_patterns = (...), replications = 1,
        base_seed = 20260814, n_persons = 12, n_items = 4,
        n_raters = 3)

Return a small predeclared plan for five-category fixed-Q MGMFRM response-
pattern stress cases. The default covers dense and connected systematic-link
designs with ordinary category use, an unused interior category, an all-
maximum person, and an all-minimum rater. Their exact combination is included
only in the sparse design, where the target person and rater have no common
observation; exact all-maximum and all-minimum constraints cannot coexist in a
fully crossed person-rater design.

Rows are planning records, not fitted attempts or scientific evidence. Seeds
are assigned by row order without repository paths or source hashes. Odd item
counts are supported: pure items are divided between the two fixed dimensions
with a count difference of one, rather than imposing equal counts as an
identification condition.
"""
function mgmfrm_response_stress_plan(;
        design_strata = _MGMFRM_RESPONSE_STRESS_DESIGNS,
        response_patterns = _MGMFRM_RESPONSE_STRESS_PATTERNS,
        replications::Integer = 1,
        base_seed::Integer = 20260814,
        n_persons::Integer = 12,
        n_items::Integer = 4,
        n_raters::Integer = 3)
    designs = _mgmfrm_stress_selection(
        design_strata,
        _MGMFRM_RESPONSE_STRESS_DESIGNS,
        "design_strata",
    )
    patterns = _mgmfrm_stress_selection(
        response_patterns,
        _MGMFRM_RESPONSE_STRESS_PATTERNS,
        "response_patterns",
    )
    checked_replications = _mgmfrm_stress_positive_integer(
        replications, "replications")
    checked_persons = _mgmfrm_stress_positive_integer(
        n_persons, "n_persons"; minimum = 4)
    checked_items = _mgmfrm_stress_positive_integer(
        n_items, "n_items"; minimum = 4)
    checked_raters = _mgmfrm_stress_positive_integer(
        n_raters, "n_raters"; minimum = 2)
    :connected_sparse_systematic_link in designs &&
        checked_persons < checked_raters && throw(ArgumentError(
            "n_persons must be at least n_raters for the systematic-link " *
            "plan to include every declared rater",
        ))
    :combined_unused_category_and_boundary_patterns in patterns &&
        :connected_sparse_systematic_link in designs &&
        checked_raters < 3 && throw(ArgumentError(
            "the combined boundary pattern requires at least three raters " *
            "so its target person and rater do not intersect",
        ))
    Int(base_seed) > 0 || throw(ArgumentError("base_seed must be positive"))

    rows = NamedTuple[]
    for design in designs, pattern in patterns,
            replication in 1:checked_replications
        design === :dense_fully_crossed &&
            pattern === :combined_unused_category_and_boundary_patterns &&
            continue
        attempt_index = length(rows) + 1
        push!(rows, (;
            schema = "bayesianmgmfrm.mgmfrm_response_stress_plan_row.v1",
            object = :mgmfrm_response_stress_plan_row,
            attempt_id = Symbol(
                "response_stress_",
                lpad(string(attempt_index), 4, '0'),
            ),
            attempt_index,
            design,
            response_pattern = pattern,
            replication,
            seed = Int(base_seed) + attempt_index - 1,
            n_persons = checked_persons,
            n_items = checked_items,
            n_raters = checked_raters,
            n_categories = 5,
            pure_items_per_dimension = (
                checked_items ÷ 2,
                checked_items - checked_items ÷ 2,
            ),
            pure_item_balance_rule = :dimension_count_difference_at_most_one,
            raters_per_person = design === :dense_fully_crossed ?
                checked_raters : 2,
            q_structure = :pure_between_item_two_dimensions,
            latent_correlation = :identity_fixed,
            expected_pattern = _mgmfrm_stress_expected_pattern(
                pattern,
                design,
            ),
            data_generating_role = pattern === :regular_all_categories ?
                :well_specified_model_draw :
                :model_draw_with_deterministic_response_pattern_intervention,
            evaluation_role = pattern === :regular_all_categories ?
                :baseline_recovery : :robustness_stress,
            status = :predeclared_not_run,
            claim_scope = :mcmc_free_stress_plan_not_validation_evidence,
        ))
    end
    isempty(rows) && throw(ArgumentError(
        "the selected design/pattern combination has no feasible attempts; " *
        "the exact combined boundary pattern is excluded from a fully " *
        "crossed design because its target constraints conflict",
    ))
    return rows
end

function _mgmfrm_known_truth_q_matrix(n_items::Int)
    q = falses(n_items, 2)
    split = n_items ÷ 2
    q[1:split, 1] .= true
    q[(split + 1):n_items, 2] .= true
    return q
end

# Known-truth generation and deterministic response-pattern interventions.

function _mgmfrm_known_truth_columns(plan_row)
    persons = String[]
    raters = String[]
    items = String[]
    scores = Int[]
    row_index = 0
    for person in 1:Int(plan_row.n_persons)
        selected_raters = if plan_row.design === :dense_fully_crossed
            1:Int(plan_row.n_raters)
        elseif plan_row.design === :connected_sparse_systematic_link
            first_rater = 1 + mod(person - 1, Int(plan_row.n_raters))
            second_rater = 1 + mod(person, Int(plan_row.n_raters))
            (first_rater, second_rater)
        else
            throw(ArgumentError(
                "unsupported MGMFRM known-truth design " *
                ":$(plan_row.design)"))
        end
        for item in 1:Int(plan_row.n_items), rater in selected_raters
            row_index += 1
            push!(persons, "P$person")
            push!(raters, "R$rater")
            push!(items, "I$item")
            push!(scores,
                1 + mod(row_index - 1, Int(plan_row.n_categories)))
        end
    end
    return (; person = persons, rater = raters, item = items, score = scores)
end

function _mgmfrm_known_truth_spec(data::FacetData, q_matrix;
        validation_report = validate_design(data))
    return mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix,
        validation_report,
    )
end

function _mgmfrm_known_truth_parameters(
        design::FacetDesign, truth_scale::Float64)
    target = _mgmfrm_guarded_local_fit_logdensity(design)
    raw = [truth_scale * sin(index) for index in eachindex(initial_params(target))]
    direct = _mgmfrm_source_constrained_params_from_unconstrained(design, raw)
    return (; raw, direct)
end

function _mgmfrm_known_truth_baseline(plan_row, truth_scale::Float64)
    source_data = FacetData(
        _mgmfrm_known_truth_columns(plan_row);
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
    q_matrix = _mgmfrm_known_truth_q_matrix(Int(plan_row.n_items))
    source_spec = _mgmfrm_known_truth_spec(source_data, q_matrix)
    source_design = getdesign(source_spec; preview = true)
    truth = _mgmfrm_known_truth_parameters(source_design, truth_scale)
    truth_parameters_valid =
        all(isfinite, truth.raw) && all(isfinite, truth.direct)
    truth_probabilities = _mgmfrm_predictive_probabilities_direct(
        source_design,
        reshape(truth.direct, 1, :),
    )
    probability_sums = dropdims(
        sum(truth_probabilities; dims = 3);
        dims = 3,
    )
    maximum_probability_sum_error =
        maximum(abs.(probability_sums .- 1.0))
    truth_probabilities_valid = all(isfinite, truth_probabilities) &&
        maximum_probability_sum_error <= 1e-10
    data = simulate_responses(
        source_design,
        truth.raw;
        rng = MersenneTwister(Int(plan_row.seed)),
        parameter_space = :raw,
    )
    return (;
        data,
        q_matrix,
        raw_truth = truth.raw,
        direct_truth = truth.direct,
        truth_parameters_valid,
        truth_category_probabilities = truth_probabilities,
        truth_probabilities_valid,
        maximum_probability_sum_error,
    )
end

function _mgmfrm_apply_response_pattern(data::FacetData, pattern::Symbol,
        expected)
    pattern in _MGMFRM_RESPONSE_STRESS_PATTERNS ||
        throw(ArgumentError("unsupported response pattern :$pattern"))
    scores = copy(data.score)
    changed = falses(data.n)
    remove_middle = pattern in (
        :unused_interior_category_3,
        :combined_unused_category_and_boundary_patterns,
    )
    set_person_maximum = pattern in (
        :all_maximum_person,
        :combined_unused_category_and_boundary_patterns,
    )
    set_rater_minimum = pattern in (
        :all_minimum_rater,
        :combined_unused_category_and_boundary_patterns,
    )

    if remove_middle
        for row in eachindex(scores)
            scores[row] == 3 || continue
            replacement = isodd(row) ? 2 : 4
            changed[row] |= scores[row] != replacement
            scores[row] = replacement
        end
    end
    if set_person_maximum
        person_index = findfirst(==(expected.target_person), data.person_levels)
        person_index === nothing && throw(ArgumentError(
            "target person $(repr(expected.target_person)) is absent"))
        for row in eachindex(scores)
            data.person[row] == person_index || continue
            changed[row] |= scores[row] != 5
            scores[row] = 5
        end
    end
    if set_rater_minimum
        rater_index = findfirst(==(expected.target_rater), data.rater_levels)
        rater_index === nothing && throw(ArgumentError(
            "target rater $(repr(expected.target_rater)) is absent"))
        for row in eachindex(scores)
            data.rater[row] == rater_index || continue
            changed[row] |= scores[row] != 1
            scores[row] = 1
        end
    end
    return (;
        data = _facet_data_with_scores(data, scores),
        changed_rows = findall(changed),
    )
end

function _mgmfrm_stress_pattern_check(audit, expected)
    expected_unused = expected.unused_interior_category_3 ? (3,) : ()
    unused_ok = audit.overall.unused_categories == expected_unused
    person_ok = expected.all_maximum_person ?
        expected.target_person in audit.flags.extreme_person_levels : true
    rater_ok = expected.all_minimum_rater ?
        expected.target_rater in audit.flags.boundary_rater_levels : true
    return (;
        unused_interior_category_3 = unused_ok,
        all_maximum_person = person_ok,
        all_minimum_rater = rater_ok,
        passed = unused_ok && person_ok && rater_ok,
    )
end

"""
    simulate_mgmfrm_response_stress(plan_row; truth_scale = 0.15)

Generate one five-category, two-dimensional fixed-Q MGMFRM stress case from a
row returned by [`mgmfrm_response_stress_plan`](@ref). Responses are first
drawn from the package MGMFRM kernel. Non-baseline scenarios then apply a
declared deterministic intervention to create the requested category gap or
boundary pattern while preserving the intended `1:5` scale.

The returned object retains raw/direct generating parameters, pre-intervention
probabilities and scores, changed-row indices, design validation, Q validation,
and the sampler-free ordinal-pattern audit. No model is fitted.
"""
function simulate_mgmfrm_response_stress(plan_row; truth_scale::Real = 0.15)
    hasproperty(plan_row, :object) &&
        plan_row.object === :mgmfrm_response_stress_plan_row ||
        throw(ArgumentError(
            "plan_row must be returned by mgmfrm_response_stress_plan"))
    isfinite(truth_scale) && truth_scale > 0 ||
        throw(ArgumentError("truth_scale must be finite and positive"))
    Int(plan_row.n_categories) == 5 ||
        throw(ArgumentError("response-stress plan rows must use five categories"))

    baseline = _mgmfrm_known_truth_baseline(
        plan_row,
        Float64(truth_scale),
    )
    intervention = _mgmfrm_apply_response_pattern(
        baseline.data,
        Symbol(plan_row.response_pattern),
        plan_row.expected_pattern,
    )
    data = intervention.data
    validation = validate_design(data)
    spec = _mgmfrm_known_truth_spec(
        data,
        baseline.q_matrix;
        validation_report = validation,
    )
    design = getdesign(spec; preview = true)
    q_validation = q_matrix_validation(spec)
    audit = ordinal_response_pattern_audit(data)
    pattern_check = _mgmfrm_stress_pattern_check(
        audit,
        plan_row.expected_pattern,
    )
    preflight_passed = validation.passed && q_validation.passed &&
        pattern_check.passed && baseline.truth_parameters_valid &&
        baseline.truth_probabilities_valid

    return (;
        schema = "bayesianmgmfrm.mgmfrm_response_stress_case.v1",
        object = :mgmfrm_response_stress_case,
        status = preflight_passed ?
            :stress_case_generated : :stress_case_preflight_failed,
        attempt_id = plan_row.attempt_id,
        plan = plan_row,
        data,
        spec,
        design,
        q_matrix = baseline.q_matrix,
        raw_truth = baseline.raw_truth,
        direct_truth = baseline.direct_truth,
        truth_parameters_valid = baseline.truth_parameters_valid,
        truth_category_probabilities =
            baseline.truth_category_probabilities,
        truth_probabilities_valid = baseline.truth_probabilities_valid,
        maximum_probability_sum_error =
            baseline.maximum_probability_sum_error,
        baseline_scores = copy(baseline.data.score),
        changed_rows = intervention.changed_rows,
        validation,
        q_validation,
        response_pattern_audit = audit,
        pattern_check,
        preflight_passed,
        fit_eligible = validation.passed &&
            q_validation.identification.guarded_fit_structure_ready,
        data_generating_role = plan_row.data_generating_role,
        probability_truth_role = plan_row.response_pattern ===
            :regular_all_categories ? :observed_data_generating_probability :
            :pre_intervention_reference_probability,
        fit_evidence = :not_run,
        scientific_decision = :not_applied,
        claim_scope = :mcmc_free_generation_and_preflight_not_recovery_evidence,
    )
end

function _mgmfrm_stress_fatal_exception(err)
    return err isa InterruptException || err isa OutOfMemoryError ||
        err isa StackOverflowError
end

# Attempt-complete sampler-free orchestration.

function _mgmfrm_stress_attempt_identity(plan_row, index::Int)
    return hasproperty(plan_row, :attempt_id) ? plan_row.attempt_id :
        Symbol("unidentified_attempt_", lpad(string(index), 4, '0'))
end

function _mgmfrm_stress_issue_codes(validation)
    return Tuple(issue.code for issue in validation.issues)
end

"""
    mgmfrm_response_stress_preflight(
        plan = mgmfrm_response_stress_plan(); truth_scale = 0.15)

Generate and preflight every response-stress attempt while retaining the full
attempt denominator. Each row terminates as `:preflight_passed`,
`:pre_fit_rejected`, or `:generation_failed`. Caught generation errors are not
converted to `nothing`: the in-memory exception, concrete type, message, phase,
and elapsed time are retained in the result row. Interrupt, out-of-memory, and
stack-overflow exceptions are rethrown.

This function does not run MCMC, apply computational/scientific thresholds, or
resolve the Stage-A attempt-complete evaluation-runner blocker.
"""
function mgmfrm_response_stress_preflight(
        plan = mgmfrm_response_stress_plan();
        truth_scale::Real = 0.15)
    isfinite(truth_scale) && truth_scale > 0 ||
        throw(ArgumentError("truth_scale must be finite and positive"))
    attempts = collect(plan)
    isempty(attempts) && throw(ArgumentError("plan must not be empty"))
    attempt_ids = [_mgmfrm_stress_attempt_identity(row, index)
        for (index, row) in pairs(attempts)]
    length(unique(attempt_ids)) == length(attempt_ids) ||
        throw(ArgumentError("plan attempt_id values must be unique"))
    rows = NamedTuple[]
    cases = Any[]

    for (index, plan_row) in pairs(attempts)
        started = time_ns()
        attempt_id = attempt_ids[index]
        try
            generated = simulate_mgmfrm_response_stress(
                plan_row;
                truth_scale,
            )
            terminal_status = generated.preflight_passed ?
                :preflight_passed : :pre_fit_rejected
            push!(rows, (;
                attempt_id,
                attempt_index = index,
                terminal_status,
                terminal = true,
                error_phase = missing,
                error_type = missing,
                error_message = missing,
                error = missing,
                elapsed_seconds = (time_ns() - started) / 1.0e9,
                validation_passed = generated.validation.passed,
                validation_issue_codes =
                    _mgmfrm_stress_issue_codes(generated.validation),
                q_validation_passed = generated.q_validation.passed,
                response_pattern_passed = generated.pattern_check.passed,
                truth_probabilities_valid =
                    generated.truth_probabilities_valid,
                truth_parameters_valid = generated.truth_parameters_valid,
                fit_eligible = generated.fit_eligible,
                fit_evidence = :not_run,
            ))
            push!(cases, generated)
        catch err
            _mgmfrm_stress_fatal_exception(err) && rethrow()
            push!(rows, (;
                attempt_id,
                attempt_index = index,
                terminal_status = :generation_failed,
                terminal = true,
                error_phase = :generation_and_preflight,
                error_type = string(typeof(err)),
                error_message = sprint(showerror, err),
                error = err,
                elapsed_seconds = (time_ns() - started) / 1.0e9,
                validation_passed = missing,
                validation_issue_codes = (),
                q_validation_passed = missing,
                response_pattern_passed = missing,
                truth_probabilities_valid = missing,
                truth_parameters_valid = missing,
                fit_eligible = false,
                fit_evidence = :not_run,
            ))
            push!(cases, missing)
        end
    end

    statuses = Tuple(row.terminal_status for row in rows)
    n_passed = count(==(:preflight_passed), statuses)
    n_rejected = count(==(:pre_fit_rejected), statuses)
    n_failed = count(==(:generation_failed), statuses)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_response_stress_preflight.v1",
        object = :mgmfrm_response_stress_preflight,
        status = n_rejected == 0 && n_failed == 0 ?
            :preflight_complete : :preflight_complete_with_recorded_failures,
        rows = Tuple(rows),
        cases = Tuple(cases),
        summary = (;
            n_attempts = length(attempts),
            n_terminal_attempts = count(row -> row.terminal, rows),
            n_preflight_passed = n_passed,
            n_pre_fit_rejected = n_rejected,
            n_generation_failed = n_failed,
            denominator_preserved = length(rows) == length(attempts),
        ),
        fit_evidence = :not_run,
        computational_decision = :not_applied,
        scientific_decision = :not_applied,
        claim_scope = :mcmc_free_attempt_complete_preflight_not_validation_evidence,
        next_gate = :implement_attempt_complete_fit_and_diagnostic_phases,
    )
end
