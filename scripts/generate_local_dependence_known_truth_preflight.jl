#!/usr/bin/env julia

using SHA
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT = joinpath(
    ROOT,
    "test",
    "fixtures",
    "local_dependence_known_truth_preflight.json",
)
const DGP_SOURCE = joinpath(ROOT, "src", "local_dependence_known_truth_dgp.jl")
const ADAPTER_SOURCE = joinpath(ROOT, "src", "local_dependence_simulation.jl")

include(joinpath(@__DIR__, "local_json.jl"))

const EXPECTED_SCENARIO_COUNT = 22
const FORBIDDEN_DGP_TOKENS = (
    "BayesianMGMFRM",
    "FacetData",
    "predictive_probabilities",
    "simulate_responses",
    "loglikelihood",
    "_replicate_scores",
    "local_dependence_summary",
)
const REQUIRED_DGP_TOKENS = (
    "_ld1_pcm_probabilities",
    "_ld1_inverse_cdf",
    "_ld1_generate_raw",
    "MersenneTwister",
)
const COMPONENT_FIELDS = (
    :person_testlet_shift,
    :response_occasion_shift,
    :rater_response_halo_shift,
    :rater_task_severity_shift,
    :multidimensional_shift,
    :temporal_severity_shift,
)

function usage()
    return """
    Generate the deterministic, MCMC-free LD1a known-truth preflight artifact.

    The artifact executes the 22 frozen generator scenarios and checks source
    independence, exact-zero equivalence, ability/order confounding, declared
    mechanism components, and design-support boundaries. It does not fit a
    model, calibrate a diagnostic, assign a diagnostic decision label, or
    identify an observed-data mechanism.

    Usage:
      julia --project=. scripts/generate_local_dependence_known_truth_preflight.jl [--output PATH]
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return output
end

function project_version()
    project = TOML.parsefile(joinpath(ROOT, "Project.toml"))
    return String(project["version"])
end

function project_julia_compat()
    project = TOML.parsefile(joinpath(ROOT, "Project.toml"))
    return String(project["compat"]["julia"])
end

file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))

function canonical_json_sha256(value)
    io = IOBuffer()
    write_canonical_json(io, value)
    return bytes2hex(sha256(take!(io)))
end

function shape_explicit_projection(value)
    if value isa AbstractMatrix
        n_rows, n_columns = size(value)
        return (;
            encoding = :matrix_row_major_v1,
            dimensions = (; n_rows, n_columns),
            rows = [[shape_explicit_projection(value[row, column])
                for column in 1:n_columns] for row in 1:n_rows],
        )
    elseif value isa NamedTuple
        return (; (key => shape_explicit_projection(element)
            for (key, element) in pairs(value))...)
    elseif value isa AbstractDict
        return Dict(key => shape_explicit_projection(element)
            for (key, element) in pairs(value))
    elseif value isa AbstractVector || value isa Tuple
        return [shape_explicit_projection(element) for element in value]
    end
    return value
end

function maximum_absolute(values)
    isempty(values) && return 0.0
    return maximum(abs(Float64(value)) for value in values)
end

function maximum_absolute_difference(left, right)
    axes(left) == axes(right) || return Inf
    isempty(left) && return 0.0
    return maximum(abs(Float64(left[index]) - Float64(right[index]))
        for index in eachindex(left, right))
end

function dependency_statements(source::AbstractString)
    statements = String[]
    for line in split(source, '\n')
        stripped = strip(line)
        (startswith(stripped, "using ") ||
            startswith(stripped, "import ") ||
            startswith(stripped, "include(")) || continue
        push!(statements, stripped)
    end
    return statements
end

function standalone_include_check()
    module_name = gensym(:LD1StandaloneKnownTruthPreflight)
    sandbox = Module(module_name)
    try
        Base.include(sandbox, DGP_SOURCE)
        required_bindings = (
            :_ld1_pcm_probabilities,
            :_ld1_inverse_cdf,
            :_ld1_generate_raw,
        )
        bindings_present = all(name -> isdefined(sandbox, name), required_bindings)
        probability_kernel = Base.invokelatest(
            getproperty, sandbox, :_ld1_pcm_probabilities)
        probabilities = Base.invokelatest(
            probability_kernel,
            0.0,
            [0.0],
        )
        probability_smoke_passed = probabilities == [0.5, 0.5]
        return (;
            passed = bindings_present && probability_smoke_passed,
            source_loaded_in_fresh_module = true,
            required_bindings_present = bindings_present,
            probability_smoke_passed,
            probability_smoke_value = probabilities,
            error_type = missing,
            message = missing,
        )
    catch err
        return (;
            passed = false,
            source_loaded_in_fresh_module = false,
            required_bindings_present = false,
            probability_smoke_passed = false,
            probability_smoke_value = (),
            error_type = String(nameof(typeof(err))),
            message = portable_error_message(err),
        )
    end
end

function source_independence_record()
    source = read(DGP_SOURCE, String)
    forbidden_rows = [(;
        token,
        absent = !occursin(token, source),
    ) for token in FORBIDDEN_DGP_TOKENS]
    required_rows = [(;
        token,
        present = occursin(token, source),
    ) for token in REQUIRED_DGP_TOKENS]
    dependencies = dependency_statements(source)
    dependencies_are_random_stdlib_only = dependencies == ["using Random"]
    fresh_module = standalone_include_check()
    passed = all(row.absent for row in forbidden_rows) &&
        all(row.present for row in required_rows) &&
        dependencies_are_random_stdlib_only && fresh_module.passed
    return (;
        passed,
        source = "src/local_dependence_known_truth_dgp.jl",
        source_sha256 = file_sha256(DGP_SOURCE),
        source_dependency_statements = dependencies,
        allowed_dependency_statements = ("using Random",),
        dependencies_are_random_stdlib_only,
        forbidden_token_rows = forbidden_rows,
        required_kernel_rows = required_rows,
        fresh_module_include = fresh_module,
        fitted_probability_or_likelihood_dependency = :none,
    )
end

function category_count_rows(result)
    levels = collect(result.truth.intended_category_levels)
    return [(;
        category = level,
        count = count(==(level), result.table.score),
    ) for level in levels]
end

function component_maxima(result)
    truth = result.row_truth
    return (;
        person_testlet_shift = maximum_absolute(truth.person_testlet_shift),
        response_occasion_shift = maximum_absolute(truth.response_occasion_shift),
        rater_response_halo_shift =
            maximum_absolute(truth.rater_response_halo_shift),
        rater_task_severity_shift =
            maximum_absolute(truth.rater_task_severity_shift),
        multidimensional_shift = maximum_absolute(truth.multidimensional_shift),
        temporal_severity_shift =
            maximum_absolute(truth.temporal_severity_shift),
    )
end

function scenario_summary(row, result)
    scalar_audit = result.design_support.testlet.scalar_shared_cluster
    pair_support = scalar_audit.diagnostic_pair_support
    truth_surface = (;
        truth = result.truth,
        row_truth = result.row_truth,
    )
    return (;
        scenario_index = row.scenario_index,
        scenario_id = row.scenario_id,
        matched_set_id = row.matched_set_id,
        seed = row.seed,
        component_seeds = row.component_seeds,
        mechanism = row.mechanism,
        magnitude_label = row.magnitude_label,
        effect_scale = row.effect_scale,
        design = row.design,
        assignment = row.assignment,
        order = row.order,
        status = result.status,
        passed = result.summary.passed,
        n_ratings = result.summary.n_ratings,
        n_probability_cells = result.resource_counts.n_probability_cells,
        n_persons = result.summary.n_persons,
        n_raters = result.summary.n_raters,
        n_items = result.summary.n_items,
        n_testlets = result.summary.n_testlets,
        intended_category_levels = result.truth.intended_category_levels,
        realized_category_levels = result.truth.realized_category_levels,
        category_support_complete = result.truth.category_support_complete,
        category_counts = category_count_rows(result),
        component_maximum_absolute_shifts = component_maxima(result),
        requested_targets = result.design_support.requested_targets,
        requested_targets_eligible =
            result.design_support.requested_targets_eligible,
        expected_requested_targets_eligible =
            result.design_support.expected_requested_targets_eligible,
        diagnostic_pair_support_available =
            result.design_support.diagnostic_pair_support_available,
        expected_diagnostic_pair_support =
            result.design_support.expected_diagnostic_pair_support,
        single_rating_item_pair_status = pair_support.single_rating_item_q3.status,
        within_rater_item_pair_status = pair_support.within_rater_item_q3.status,
        shared_response_rater_pair_status =
            pair_support.rater_on_shared_response_criterion.status,
        future_fit_action = result.design_support.future_fit_action,
        data_signature = string(result.data_signature),
        testlet_design_signature = result.testlet_design_signature,
        score_signature = result.score_signature,
        truth_surface_encoding =
            :local_json_shape_explicit_matrix_row_major_v1,
        truth_surface_sha256 = canonical_json_sha256(
            shape_explicit_projection(truth_surface)),
        truth_known_by_construction = result.truth_known_by_construction,
        calibration_evidence_available = result.calibration_evidence_available,
        diagnostic_decision_labels_available =
            result.diagnostic_decision_labels_available,
        observed_data_mechanism_interpretation_eligible =
            result.observed_data_mechanism_interpretation_eligible,
    )
end

function event_index(result)
    return Dict(String(event_id) => index
        for (index, event_id) in pairs(result.table.event_id))
end

function exact_zero_check(results)
    null_result = results[:null_same_rater]
    zero_result = results[:scalar_testlet_exact_zero]
    checks = (;
        event_rows_identical = isequal(null_result.table.event_id,
            zero_result.table.event_id),
        response_uniforms_bit_identical = isequal(
            null_result.row_truth.response_uniform,
            zero_result.row_truth.response_uniform,
        ),
        baseline_locations_bit_identical = isequal(
            null_result.row_truth.baseline_location,
            zero_result.row_truth.baseline_location,
        ),
        component_scales_bit_identical = isequal(
            null_result.truth.component_scales,
            zero_result.truth.component_scales,
        ),
        total_locations_bit_identical = isequal(
            null_result.row_truth.total_location,
            zero_result.row_truth.total_location,
        ),
        probabilities_bit_identical = isequal(
            null_result.row_truth.probabilities,
            zero_result.row_truth.probabilities,
        ),
        scores_bit_identical = isequal(
            null_result.table.score,
            zero_result.table.score,
        ),
    )
    return (;
        check = :exact_zero_matches_null,
        left_scenario = :null_same_rater,
        right_scenario = :scalar_testlet_exact_zero,
        passed = all(values(checks)),
        checks,
        maximum_probability_difference = maximum_absolute_difference(
            null_result.row_truth.probabilities,
            zero_result.row_truth.probabilities,
        ),
    )
end

function eventwise_order_equivalence(randomized, ordered)
    randomized_index = event_index(randomized)
    ordered_index = event_index(ordered)
    identifiers = sort!(collect(keys(randomized_index)))
    same_identifiers = identifiers == sort!(collect(keys(ordered_index)))
    same_identifiers || return (;
        same_identifiers = false,
        response_uniforms_bit_identical = false,
        baseline_locations_bit_identical = false,
        probabilities_bit_identical = false,
        scores_bit_identical = false,
        sequence_assignment_changed = false,
        maximum_probability_difference = Inf,
    )
    n_categories = size(randomized.row_truth.probabilities, 2)
    response_uniforms_equal = true
    baselines_equal = true
    probabilities_equal = true
    scores_equal = true
    sequence_changed = false
    maximum_difference = 0.0
    for identifier in identifiers
        left = randomized_index[identifier]
        right = ordered_index[identifier]
        response_uniforms_equal &= isequal(
            randomized.row_truth.response_uniform[left],
            ordered.row_truth.response_uniform[right],
        )
        baselines_equal &= isequal(
            randomized.row_truth.baseline_location[left],
            ordered.row_truth.baseline_location[right],
        )
        scores_equal &= randomized.table.score[left] == ordered.table.score[right]
        sequence_changed |= randomized.table.sequence_index[left] !=
            ordered.table.sequence_index[right]
        for category in 1:n_categories
            difference = abs(
                randomized.row_truth.probabilities[left, category] -
                ordered.row_truth.probabilities[right, category],
            )
            maximum_difference = max(maximum_difference, difference)
            probabilities_equal &= difference == 0.0
        end
    end
    return (;
        same_identifiers,
        response_uniforms_bit_identical = response_uniforms_equal,
        baseline_locations_bit_identical = baselines_equal,
        probabilities_bit_identical = probabilities_equal,
        scores_bit_identical = scores_equal,
        sequence_assignment_changed = sequence_changed,
        maximum_probability_difference = maximum_difference,
    )
end

function low_to_high_order_verified(result)
    ability_by_person = Dict(
        String(label) => Float64(result.truth.person_ability[index])
        for (index, label) in pairs(result.truth.person_labels)
    )
    events = Dict{Tuple{String,String},NamedTuple}()
    for row in eachindex(result.table.score)
        key = (
            String(result.table.rater[row]),
            String(result.table.response_id[row]),
        )
        events[key] = (;
            sequence_index = result.table.sequence_index[row],
            person = String(result.table.person[row]),
        )
    end
    by_rater = Dict{String,Vector{NamedTuple}}()
    for ((rater, _), event) in events
        push!(get!(by_rater, rater, NamedTuple[]), event)
    end
    for rows in values(by_rater)
        sort!(rows; by = row -> row.sequence_index)
        abilities = [ability_by_person[row.person] for row in rows]
        all(abilities[index] <= abilities[index + 1]
            for index in 1:(length(abilities) - 1)) || return false
    end
    return true
end

function ability_order_check(results)
    randomized = results[:null_same_rater]
    ordered = results[:temporal_sequence_ability_confounded]
    equivalence = eventwise_order_equivalence(randomized, ordered)
    low_to_high_verified = low_to_high_order_verified(ordered)
    no_temporal_effect = maximum_absolute(
        ordered.row_truth.temporal_severity_shift) == 0.0
    passed = equivalence.same_identifiers &&
        equivalence.response_uniforms_bit_identical &&
        equivalence.baseline_locations_bit_identical &&
        equivalence.probabilities_bit_identical &&
        equivalence.scores_bit_identical &&
        equivalence.sequence_assignment_changed && low_to_high_verified &&
        no_temporal_effect
    return (;
        check = :ability_confounded_order_changes_sequence_not_outcomes,
        randomized_scenario = :null_same_rater,
        ordered_scenario = :temporal_sequence_ability_confounded,
        passed,
        eventwise_equivalence = equivalence,
        low_to_high_order_verified = low_to_high_verified,
        no_temporal_effect,
        interpretation =
            :case_mix_order_can_change_without_a_generating_severity_drift,
    )
end

function ability_assignment_check(results)
    result = results[:null_ability_informed_assignment]
    person_raters = Dict{Int,Set{Int}}()
    for row in eachindex(result.table.score)
        person = result.row_truth.person_index[row]
        rater = result.row_truth.rater_index[row]
        push!(get!(person_raters, person, Set{Int}()), rater)
    end
    one_rater_per_person = all(length(raters) == 1
        for raters in values(person_raters))
    actual_rater_by_person = Dict(
        person => only(raters) for (person, raters) in person_raters)
    sorted_persons = sortperm(result.truth.person_ability)
    bucket_by_actual_rater = invperm(collect(
        result.truth.rater_label_permutation))
    assigned_buckets = [bucket_by_actual_rater[
        actual_rater_by_person[person]] for person in sorted_persons]
    ability_groups_monotone = issorted(assigned_buckets)
    all_raters_represented = length(unique(values(actual_rater_by_person))) ==
        length(result.truth.rater_labels)
    assignment_reason_recorded = all(==("ability_informed"),
        result.table.assignment_reason)
    null_local_dependence_truth = isempty(result.truth.active_mechanisms)
    passed = one_rater_per_person && ability_groups_monotone &&
        all_raters_represented && assignment_reason_recorded &&
        null_local_dependence_truth
    return (;
        check = :ability_informed_rater_assignment,
        scenario_id = :null_ability_informed_assignment,
        passed,
        one_rater_per_person,
        ability_groups_monotone,
        all_raters_represented,
        assignment_reason_recorded,
        null_local_dependence_truth,
        interpretation =
            :ability_dependent_assignment_is_present_without_generated_local_dependence,
    )
end

function maximum_row_or_column_mean(matrix)
    row_means = [sum(matrix[row, :]) / size(matrix, 2)
        for row in axes(matrix, 1)]
    column_means = [sum(matrix[:, column]) / size(matrix, 1)
        for column in axes(matrix, 2)]
    return (;
        maximum_absolute_row_mean = maximum_absolute(row_means),
        maximum_absolute_column_mean = maximum_absolute(column_means),
    )
end

function mechanism_pair_check(results, check::Symbol, baseline_id::Symbol,
        scenario_id::Symbol, active_fields::Tuple)
    baseline = results[baseline_id]
    scenario = results[scenario_id]
    maxima = component_maxima(scenario)
    baseline_maxima = component_maxima(baseline)
    inactive_fields = Tuple(field for field in COMPONENT_FIELDS
        if field ∉ active_fields)
    baseline_all_components_zero = all(
        getproperty(baseline_maxima, field) == 0.0
        for field in COMPONENT_FIELDS
    )
    declared_components_nonzero = all(
        getproperty(maxima, field) > 0.0 for field in active_fields)
    undeclared_components_zero = all(
        getproperty(maxima, field) == 0.0 for field in inactive_fields)
    event_rows_identical = isequal(
        baseline.table.event_id, scenario.table.event_id)
    response_uniforms_bit_identical = isequal(
        baseline.row_truth.response_uniform,
        scenario.row_truth.response_uniform,
    )
    baseline_locations_bit_identical = isequal(
        baseline.row_truth.baseline_location,
        scenario.row_truth.baseline_location,
    )
    maximum_probability_difference = maximum_absolute_difference(
        baseline.row_truth.probabilities,
        scenario.row_truth.probabilities,
    )
    probability_surface_changed = maximum_probability_difference > 0.0
    constraint_check = if :rater_task_severity_shift in active_fields
        center = maximum_row_or_column_mean(
            scenario.truth.rater_task_double_centered_standard_normal)
        (;
            applicable = true,
            tolerance = 1.0e-12,
            maximum_absolute_row_mean = center.maximum_absolute_row_mean,
            maximum_absolute_column_mean = center.maximum_absolute_column_mean,
            passed = center.maximum_absolute_row_mean <= 1.0e-12 &&
                center.maximum_absolute_column_mean <= 1.0e-12,
        )
    else
        (;
            applicable = false,
            tolerance = missing,
            maximum_absolute_row_mean = missing,
            maximum_absolute_column_mean = missing,
            passed = true,
        )
    end
    passed = baseline_all_components_zero && declared_components_nonzero &&
        undeclared_components_zero && event_rows_identical &&
        response_uniforms_bit_identical && baseline_locations_bit_identical &&
        probability_surface_changed && constraint_check.passed
    return (;
        check,
        baseline_scenario = baseline_id,
        scenario_id,
        active_fields,
        inactive_fields,
        passed,
        baseline_all_components_zero,
        declared_components_nonzero,
        undeclared_components_zero,
        event_rows_identical,
        response_uniforms_bit_identical,
        baseline_locations_bit_identical,
        probability_surface_changed,
        maximum_probability_difference,
        component_maximum_absolute_shifts = maxima,
        rater_task_double_center_constraint = constraint_check,
    )
end

function mechanism_checks(results)
    return [
        mechanism_pair_check(
            results,
            :person_testlet_component,
            :null_same_rater,
            :scalar_testlet_moderate,
            (:person_testlet_shift,),
        ),
        mechanism_pair_check(
            results,
            :rater_response_halo_component,
            :null_fully_crossed_raters,
            :rater_response_halo_crossed,
            (:rater_response_halo_shift,),
        ),
        mechanism_pair_check(
            results,
            :rater_task_severity_component,
            :null_fully_crossed_raters,
            :rater_task_crossed,
            (:rater_task_severity_shift,),
        ),
        mechanism_pair_check(
            results,
            :omitted_dimension_component,
            :null_same_rater,
            :omitted_dimension_crossed_q,
            (:multidimensional_shift,),
        ),
        mechanism_pair_check(
            results,
            :temporal_severity_component,
            :null_same_rater,
            :temporal_sequence_randomized,
            (:temporal_severity_shift,),
        ),
        mechanism_pair_check(
            results,
            :person_testlet_plus_temporal_components,
            :null_same_rater,
            :scalar_testlet_plus_sequence,
            (:person_testlet_shift, :temporal_severity_shift),
        ),
    ]
end

function design_expectation_row(results, scenario_id::Symbol)
    result = results[scenario_id]
    support = result.design_support
    requested_match = support.requested_targets_eligible ==
        support.expected_requested_targets_eligible
    diagnostic_match = support.expected_diagnostic_pair_support === nothing ||
        support.diagnostic_pair_support_available ==
        support.expected_diagnostic_pair_support
    return (;
        scenario_id,
        passed = result.summary.passed && requested_match && diagnostic_match,
        requested_targets = support.requested_targets,
        requested_targets_eligible = support.requested_targets_eligible,
        expected_requested_targets_eligible =
            support.expected_requested_targets_eligible,
        diagnostic_pair_support_available =
            support.diagnostic_pair_support_available,
        expected_diagnostic_pair_support =
            support.expected_diagnostic_pair_support,
        requested_expectation_matched = requested_match,
        diagnostic_expectation_matched = diagnostic_match,
        future_fit_action = support.future_fit_action,
    )
end

function design_boundary_checks(results)
    below = results[:null_support_below_minimum]
    at = results[:null_support_at_minimum]
    support_boundary_passed =
        !below.design_support.diagnostic_pair_support_available &&
        at.design_support.diagnostic_pair_support_available
    support_boundary = (;
        check = :minimum_pair_support_boundary,
        below_scenario = :null_support_below_minimum,
        at_scenario = :null_support_at_minimum,
        minimum_common_units =
            at.design_support.testlet.scalar_shared_cluster.thresholds.min_pair_common_units,
        below_persons = below.summary.n_persons,
        at_persons = at.summary.n_persons,
        below_support = below.design_support.diagnostic_pair_support_available,
        at_support = at.design_support.diagnostic_pair_support_available,
        passed = support_boundary_passed,
    )

    mixed = results[:null_mixed_testlet_applicability]
    single_rating = mixed.design_support.testlet.scalar_shared_cluster.
        diagnostic_pair_support.single_rating_item_q3
    mixed_passed = single_rating.status === :partially_applicable &&
        single_rating.n_applicable_strata > 0 &&
        single_rating.n_inapplicable_strata > 0 &&
        mixed.design_support.diagnostic_pair_support_available
    mixed_boundary = (;
        check = :mixed_testlet_pair_family_applicability,
        scenario_id = :null_mixed_testlet_applicability,
        status = single_rating.status,
        n_strata = single_rating.n_strata,
        n_applicable_strata = single_rating.n_applicable_strata,
        n_inapplicable_strata = single_rating.n_inapplicable_strata,
        any_pair_family_supported =
            mixed.design_support.diagnostic_pair_support_available,
        passed = mixed_passed,
    )

    expectation_ids = (
        :scalar_testlet_connected_sparse,
        :scalar_testlet_one_indicator_rejection,
        :scalar_testlet_one_testlet_per_person_rejection,
        :scalar_testlet_disconnected_rejection,
        :rater_response_halo_crossed,
        :rater_task_crossed,
        :rater_task_nested_rejection,
    )
    expectation_rows = [design_expectation_row(results, id)
        for id in expectation_ids]
    return (;
        support_boundary,
        mixed_applicability = mixed_boundary,
        structural_expectation_rows = expectation_rows,
        passed = support_boundary.passed && mixed_boundary.passed &&
            all(row.passed for row in expectation_rows),
    )
end

function build_artifact()
    grid = BayesianMGMFRM.local_dependence_simulation_grid()
    length(grid) == EXPECTED_SCENARIO_COUNT || error(
        "expected $EXPECTED_SCENARIO_COUNT LD1a scenarios, found $(length(grid))",
    )
    length(unique(row.scenario_id for row in grid)) == EXPECTED_SCENARIO_COUNT ||
        error("LD1a scenario identifiers must be unique")

    results = Dict{Symbol,Any}()
    for row in grid
        results[row.scenario_id] = BayesianMGMFRM.simulate_local_dependence(row)
    end
    scenario_rows = [scenario_summary(row, results[row.scenario_id])
        for row in grid]
    source_scan = source_independence_record()
    exact_zero = exact_zero_check(results)
    ability_order = ability_order_check(results)
    ability_assignment = ability_assignment_check(results)
    mechanism_rows = mechanism_checks(results)
    design_boundaries = design_boundary_checks(results)

    scenario_preflights_passed = all(row.passed for row in scenario_rows)
    paired_checks_passed = exact_zero.passed && ability_order.passed &&
        ability_assignment.passed &&
        all(row.passed for row in mechanism_rows) && design_boundaries.passed
    all_checks_passed = source_scan.passed && scenario_preflights_passed &&
        paired_checks_passed

    artifact = (;
        schema = "bayesianmgmfrm.local_dependence_known_truth_preflight.v1",
        family = :mfrm,
        scope = :ld1a_known_truth_generator_preflight,
        status = all_checks_passed ?
            :generator_contract_passed_calibration_not_run :
            :generator_contract_preflight_failed,
        package = (;
            name = :BayesianMGMFRM,
            version = project_version(),
        ),
        generator = (;
            script =
                "scripts/generate_local_dependence_known_truth_preflight.jl",
            script_source_sha256 = file_sha256(@__FILE__),
            known_truth_source =
                "src/local_dependence_known_truth_dgp.jl",
            known_truth_source_sha256 = file_sha256(DGP_SOURCE),
            adapter_source = "src/local_dependence_simulation.jl",
            adapter_source_sha256 = file_sha256(ADAPTER_SOURCE),
            deterministic_within_recorded_rng_contract = true,
            rng_contract = results[:null_same_rater].truth.rng_contract,
            environment_provenance = (;
                project = "Project.toml",
                project_sha256 = file_sha256(joinpath(ROOT, "Project.toml")),
                manifest = "Manifest.toml",
                manifest_sha256 = file_sha256(joinpath(ROOT, "Manifest.toml")),
                julia_compat = project_julia_compat(),
                exact_runtime_version_recorded = false,
                cross_julia_bitwise_portability_claimed = false,
            ),
            mcmc_free = true,
        ),
        execution_scope = (;
            planning_profile = :ld1_preflight_v1,
            phase = :smoke,
            repetitions = 1,
            n_scenarios = length(grid),
            runs_known_truth_generation = true,
            runs_design_preflight = true,
            runs_model_fit = false,
            runs_mcmc = false,
            runs_local_dependence_summary = false,
            calibrates_diagnostic_reference = false,
            assigns_diagnostic_decision_labels = false,
            classifies_observed_data_mechanisms = false,
        ),
        source_independence = source_scan,
        scenario_summaries = scenario_rows,
        paired_checks = (;
            exact_zero,
            ability_order,
            ability_assignment,
            mechanism_rows,
            design_boundaries,
        ),
        claim_boundaries = (;
            truth_known_by_construction = true,
            generator_contract_evidence_available = all_checks_passed,
            repeated_calibration_completed = false,
            calibration_evidence_available = false,
            diagnostic_decision_labels_available = false,
            observed_data_mechanism_interpretation_eligible = false,
            parameter_recovery_claim_supported = false,
            diagnostic_power_or_error_rate_claim_supported = false,
            public_claim_release_allowed = false,
        ),
        summary = (;
            passed = all_checks_passed,
            n_scenarios = length(scenario_rows),
            n_scenarios_passed = count(row -> row.passed, scenario_rows),
            source_independence_passed = source_scan.passed,
            exact_zero_check_passed = exact_zero.passed,
            ability_order_check_passed = ability_order.passed,
            ability_assignment_check_passed = ability_assignment.passed,
            n_mechanism_checks = length(mechanism_rows),
            n_mechanism_checks_passed = count(row -> row.passed, mechanism_rows),
            design_boundary_checks_passed = design_boundaries.passed,
            repeated_calibration_completed = false,
            diagnostic_decisions_available = false,
            mechanism_classification_available = false,
            subsequent_stage = :ld1b_repeated_null_and_alternative_calibration,
        ),
    )
    return merge(artifact, (;
        content_hash = (;
            algorithm = :sha256,
            value = canonical_json_sha256(artifact),
            covers = :artifact_without_content_hash,
            canonical_format = :local_json_sorted_compact,
        ),
    ))
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println(
        "passed=", artifact.summary.passed,
        " scenarios=", artifact.summary.n_scenarios_passed,
        "/", artifact.summary.n_scenarios,
        " mechanism_checks=", artifact.summary.n_mechanism_checks_passed,
        "/", artifact.summary.n_mechanism_checks,
        " calibration_completed=", artifact.summary.repeated_calibration_completed,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
