# Four-category known-truth generation for the blocked MGMFRM primary grid.

function _mgmfrm_validation_primary_grid_candidate_contract(protocol)
    sizes = protocol.design_domain.source_sample_size_candidates
    gradient_policy = _mgmfrm_validation_resource_probe_policy()
    short_nuts_policy = _mgmfrm_validation_short_nuts_resource_probe_policy()
    cells = NamedTuple[]
    for design in (:dense_fully_crossed,
            :connected_sparse_systematic_link),
            persons in sizes.persons,
            items in sizes.items,
            raters in sizes.raters
        cell_index = length(cells) + 1
        raters_per_person = design === :dense_fully_crossed ? raters :
                            protocol.design_domain.sparse_raters_per_person
        observations = persons * items * raters_per_person
        probability_cells = observations * protocol.design_domain.categories
        within_gradient_bound = observations <=
            gradient_policy.hard_maximum_observations_per_cell &&
            probability_cells <=
            gradient_policy.hard_maximum_probability_cells_per_cell
        within_short_nuts_bound = observations <=
            short_nuts_policy.hard_maximum_observations_per_cell &&
            probability_cells <=
            short_nuts_policy.hard_maximum_probability_cells_per_cell
        push!(cells, (;
            schema =
                "bayesianmgmfrm.mgmfrm_validation_primary_grid_candidate.v1",
            object = :mgmfrm_validation_primary_grid_candidate,
            cell_id = Symbol(
                "primary_candidate_",
                lpad(string(cell_index), 2, '0'),
            ),
            design,
            persons,
            items,
            raters,
            raters_per_person,
            expected_observations = observations,
            expected_probability_cells = probability_cells,
            dimensions = protocol.claim_target.dimensions,
            categories = protocol.design_domain.categories,
            q_structure =
                :pure_between_item_one_active_dimension_per_item,
            pure_items_per_dimension =
                (items ÷ 2, items - items ÷ 2),
            latent_correlation = protocol.claim_target.latent_correlation,
            response_pattern = :regular_all_categories,
            prior_regime = :implementation_reference,
            backend = protocol.backends.primary,
            scientific_role = :well_specified_primary_candidate,
            preflight_seed = 2_026_082_200 + cell_index,
            seed_role = :structural_preflight_only_not_evaluation,
            within_current_gradient_probe_bound = within_gradient_bound,
            within_current_short_nuts_probe_bound = within_short_nuts_bound,
            generator_status =
                :public_primary_four_category_known_truth_generator,
            status = :candidate_not_frozen,
            execution_authorized = false,
        ))
    end

    observation_counts = Tuple(row.expected_observations for row in cells)
    n_within_gradient = count(
        row -> row.within_current_gradient_probe_bound,
        cells,
    )
    n_within_short_nuts = count(
        row -> row.within_current_short_nuts_probe_bound,
        cells,
    )
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_validation_primary_grid_candidates.v1",
        object = :mgmfrm_validation_primary_grid_candidates,
        status = :candidate_grid_generation_ready_execution_blocked,
        cells = Tuple(cells),
        summary = (;
            n_candidate_cells = length(cells),
            n_dense_cells = count(
                row -> row.design === :dense_fully_crossed,
                cells,
            ),
            n_sparse_cells = count(
                row -> row.design ===
                    :connected_sparse_systematic_link,
                cells,
            ),
            minimum_expected_observations = minimum(observation_counts),
            maximum_expected_observations = maximum(observation_counts),
            n_within_current_gradient_probe_bound = n_within_gradient,
            n_above_current_gradient_probe_bound =
                length(cells) - n_within_gradient,
            n_within_current_short_nuts_probe_bound = n_within_short_nuts,
            n_above_current_short_nuts_probe_bound =
                length(cells) - n_within_short_nuts,
            current_resource_envelope_covers_all_candidates =
                n_within_short_nuts == length(cells),
            primary_four_category_generator_implemented = true,
        ),
        source_anchor = (;
            study = protocol.source_anchor.source,
            persons = sizes.persons,
            items = sizes.items,
            raters = sizes.raters,
        ),
        axes = (;
            design = (:dense_fully_crossed,
                :connected_sparse_systematic_link),
            persons = sizes.persons,
            items = sizes.items,
            raters = sizes.raters,
            dimensions = (protocol.claim_target.dimensions,),
            categories = (protocol.design_domain.categories,),
        ),
        cells_frozen = false,
        evaluation_replications_frozen = false,
        execution_allowed = false,
        blockers = (
            :select_final_primary_cells_after_resource_review,
            :extend_resource_envelope_or_narrow_candidate_grid,
            :freeze_evaluation_replications,
        ),
        claim_scope =
            :candidate_generation_preflight_not_validation_evidence,
    )
end

"""
    mgmfrm_validation_primary_grid_candidates()

Enumerate the 16 fixed-Q MGMFRM primary-grid candidates implied by the two
dense/sparse designs and the source-anchored person, item, and rater sample
sizes. Each row can be passed to
[`simulate_mgmfrm_validation_primary_candidate`](@ref).

These rows are candidates, not a frozen analysis grid. Their seeds are only
for structural generation preflight. The function runs no sampler, applies no
scientific thresholds, and cannot authorize evaluation. Final cell selection,
evaluation replications, and a resource envelope covering the selected cells
remain unresolved.
"""
function mgmfrm_validation_primary_grid_candidates()
    return _mgmfrm_validation_primary_grid_candidate_contract(
        mgmfrm_validation_protocol(),
    )
end

function _mgmfrm_validation_optional_positive(value, name::AbstractString)
    value === nothing && return nothing
    value isa Real || throw(ArgumentError(
        "$name must be a real number when supplied",
    ))
    converted = Float64(value)
    isfinite(converted) && converted > 0 || throw(ArgumentError(
        "$name must be finite and positive when supplied",
    ))
    return converted
end

function _mgmfrm_validation_minimum_replications(variance::Float64,
        target::Union{Nothing,Float64})
    target === nothing && return missing
    ratio = variance / target^2
    isfinite(ratio) && ratio <= typemax(Int) || throw(ArgumentError(
        "the requested MCSE target implies an unsupported replication count",
    ))
    nearest_integer = round(ratio)
    adjusted = isapprox(
        ratio,
        nearest_integer;
        rtol = 8eps(Float64),
        atol = 0.0,
    ) ? nearest_integer : ratio
    return max(1, ceil(Int, adjusted))
end

function _mgmfrm_validation_mcse_target_met(value::Float64,
        target::Union{Nothing,Float64})
    target === nothing && return missing
    return value <= target || isapprox(
        value,
        target;
        rtol = 8eps(Float64),
        atol = 0.0,
    )
end

"""
    mgmfrm_validation_replication_precision(replications;
        nominal_coverage = 0.95,
        coverage_mcse_target = nothing,
        binary_rate_mcse_target = nothing,
        bias_error_sd_reference = nothing,
        bias_mcse_target = nothing)

Return an MCMC-free Monte Carlo precision reference for proposed independent
simulation replication counts. Coverage-rate MCSE is evaluated at
`nominal_coverage`; decision, calibration, and failure rates use the
conservative Bernoulli variance `0.25`. Bias MCSE is available only when an
external or predeclared replication-error standard deviation is supplied.

Optional targets report the algebraic minimum replication count and whether
each proposed count reaches it. The function does not select a count, freeze a
study, authorize execution, or define scientific thresholds. Bias precision is
conditional on replications that produce numeric errors; an attempt-complete
study must still report failures on the full planned denominator and specify a
failure-sensitivity analysis rather than dropping failed fits silently.
"""
function mgmfrm_validation_replication_precision(replications;
        nominal_coverage::Real = 0.95,
        coverage_mcse_target = nothing,
        binary_rate_mcse_target = nothing,
        bias_error_sd_reference = nothing,
        bias_mcse_target = nothing)
    source = replications isa Integer ? (replications,) :
             Tuple(replications)
    isempty(source) && throw(ArgumentError(
        "replications must contain at least one proposed count",
    ))
    all(value -> value isa Integer, source) || throw(ArgumentError(
        "replications must contain integers",
    ))
    counts = Tuple(Int(value) for value in source)
    all(>(0), counts) || throw(ArgumentError(
        "replication counts must be positive",
    ))
    length(unique(counts)) == length(counts) || throw(ArgumentError(
        "replication counts must be unique",
    ))

    coverage_probability = Float64(nominal_coverage)
    isfinite(coverage_probability) && 0 < coverage_probability < 1 ||
        throw(ArgumentError("nominal_coverage must lie strictly between 0 and 1"))
    coverage_target = _mgmfrm_validation_optional_positive(
        coverage_mcse_target,
        "coverage_mcse_target",
    )
    binary_target = _mgmfrm_validation_optional_positive(
        binary_rate_mcse_target,
        "binary_rate_mcse_target",
    )
    bias_sd = _mgmfrm_validation_optional_positive(
        bias_error_sd_reference,
        "bias_error_sd_reference",
    )
    bias_target = _mgmfrm_validation_optional_positive(
        bias_mcse_target,
        "bias_mcse_target",
    )

    coverage_variance = coverage_probability * (1 - coverage_probability)
    binary_worst_case_variance = 0.25
    bias_variance = bias_sd === nothing ? nothing : bias_sd^2
    requirements = (;
        coverage = _mgmfrm_validation_minimum_replications(
            coverage_variance,
            coverage_target,
        ),
        binary_rate_worst_case = _mgmfrm_validation_minimum_replications(
            binary_worst_case_variance,
            binary_target,
        ),
        bias = bias_variance === nothing ? missing :
            _mgmfrm_validation_minimum_replications(
                bias_variance,
                bias_target,
            ),
    )
    rows = Tuple((;
        replications = count,
        nominal_coverage_mcse = sqrt(coverage_variance / count),
        coverage_target_met = _mgmfrm_validation_mcse_target_met(
            sqrt(coverage_variance / count),
            coverage_target,
        ),
        binary_rate_worst_case_mcse = sqrt(
            binary_worst_case_variance / count,
        ),
        binary_rate_target_met = _mgmfrm_validation_mcse_target_met(
            sqrt(binary_worst_case_variance / count),
            binary_target,
        ),
        bias_mcse_reference = bias_sd === nothing ? missing :
            bias_sd / sqrt(count),
        bias_target_met = bias_target === nothing || bias_sd === nothing ?
            missing : _mgmfrm_validation_mcse_target_met(
                bias_sd / sqrt(count),
                bias_target,
            ),
    ) for count in counts)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_validation_replication_precision.v1",
        object = :mgmfrm_validation_replication_precision,
        status = :precision_reference_not_replication_freeze,
        rows,
        assumptions = (;
            independent_replications = true,
            adaptive_stopping_allowed = false,
            binary_rate_variance = :bernoulli_worst_case_one_quarter,
            coverage_probability,
            bias_error_sd_reference = bias_sd === nothing ? missing : bias_sd,
            bias_error_sd_source = bias_sd === nothing ?
                :not_supplied : :caller_supplied_reference,
        ),
        targets = (;
            coverage_mcse = coverage_target === nothing ? missing :
                coverage_target,
            binary_rate_mcse = binary_target === nothing ? missing :
                binary_target,
            bias_mcse = bias_target === nothing ? missing : bias_target,
        ),
        minimum_replications = requirements,
        bias_precision_status = bias_sd === nothing ?
            :reference_sd_required : :reference_available,
        failure_accounting = (;
            binary_failure_rate_covered = true,
            bias_mcse_conditional_on_numeric_errors = true,
            failed_fits_may_be_dropped_from_planned_denominator = false,
            failure_sensitivity_policy_required = true,
        ),
        replication_count_selected = false,
        precision_targets_selected = false,
        execution_authorized = false,
        scientific_decision = :not_applied,
        claim_scope = :mcse_planning_not_validation_evidence,
    )
end

function _mgmfrm_validation_primary_resource_cell(
        candidates,
        cell_id::Symbol,
        sequence::Int,
        design::Symbol,
        persons::Int,
        items::Int,
        raters::Int,
        resource_role::Symbol)
    source = only(row for row in candidates.cells
        if row.design === design && row.persons == persons &&
            row.items == items && row.raters == raters)
    return merge(source, (;
        source_candidate_cell_id = source.cell_id,
        cell_id,
        resource_sequence = sequence,
        resource_role,
        resource_seed = 2_026_082_300 + sequence,
        seed_role = :resource_probe_only_not_evaluation,
        resource_claim_scope = :primary_gradient_operability_only,
        prerequisite = sequence == 1 ? :none :
            :all_previous_primary_resource_cells_completed_operationally,
    ))
end

"""
    mgmfrm_validation_primary_resource_plan()

Return four ordered, non-executing four-category primary-grid cells for
MCMC-free gradient resource profiling. The cells cover the minimum sparse
shape, the only dense shape inside the current short-NUTS observation bound,
an intermediate dense shape, and one of the largest shapes inside the current
gradient bound.

Pass one row at a time to [`mgmfrm_validation_resource_probe`](@ref). The plan
does not authorize automatic progression, short-NUTS execution, final grid
selection, or scientific interpretation.
"""
function mgmfrm_validation_primary_resource_plan()
    candidates = mgmfrm_validation_primary_grid_candidates()
    rows = (
        _mgmfrm_validation_primary_resource_cell(
            candidates,
            :primary_resource_01_sparse_minimum,
            1,
            :connected_sparse_systematic_link,
            50, 5, 5,
            :minimum_observation_candidate,
        ),
        _mgmfrm_validation_primary_resource_cell(
            candidates,
            :primary_resource_02_dense_short_bound,
            2,
            :dense_fully_crossed,
            50, 5, 5,
            :dense_candidate_inside_current_short_nuts_bound,
        ),
        _mgmfrm_validation_primary_resource_cell(
            candidates,
            :primary_resource_03_dense_intermediate,
            3,
            :dense_fully_crossed,
            50, 15, 5,
            :intermediate_observation_and_item_scale,
        ),
        _mgmfrm_validation_primary_resource_cell(
            candidates,
            :primary_resource_04_dense_upper_gradient,
            4,
            :dense_fully_crossed,
            100, 15, 5,
            :largest_observation_count_inside_current_gradient_bound,
        ),
    )
    expected_observations =
        Tuple(row.expected_observations for row in rows)
    expected_observations == (500, 1_250, 3_750, 7_500) ||
        throw(ArgumentError(
            "primary resource-plan observation counts are inconsistent"))
    expected_probability_cells =
        Tuple(row.expected_probability_cells for row in rows)
    expected_probability_cells == (2_000, 5_000, 15_000, 30_000) ||
        throw(ArgumentError(
            "primary resource-plan probability-cell counts are inconsistent"))
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_validation_primary_resource_plan.v1",
        object = :mgmfrm_validation_primary_resource_plan,
        status = :predeclared_not_run,
        rows,
        expected_observations,
        expected_probability_cells,
        execution_order = Tuple(row.cell_id for row in rows),
        execution_mode = :one_cell_per_explicit_invocation,
        automatic_progression_allowed = false,
        stop_conditions = (
            :memory_preflight_rejected,
            :generation_or_gradient_failure,
            :unexpected_allocation_growth,
        ),
        all_primary_axes_covered = false,
        all_primary_candidates_measured = false,
        short_nuts_adapter_available = true,
        n_current_short_nuts_eligible_cells = count(
            row -> row.within_current_short_nuts_probe_bound,
            rows,
        ),
        final_analysis_grid_selected = false,
        mcmc_executed = false,
        primary_evaluation_seed_used = false,
        scientific_decision = :not_applied,
        claim_scope = :mcmc_free_primary_gradient_scaling_plan,
    )
end

function _mgmfrm_validation_primary_generation_plan(candidate, seed)
    hasproperty(candidate, :object) &&
        candidate.object === :mgmfrm_validation_primary_grid_candidate ||
        throw(ArgumentError(
            "candidate must be returned by " *
            "mgmfrm_validation_primary_grid_candidates"))
    Int(candidate.dimensions) == 2 || throw(ArgumentError(
        "primary-grid candidates must use two dimensions"))
    Int(candidate.categories) == 4 || throw(ArgumentError(
        "primary-grid candidates must use four categories"))
    candidate.response_pattern === :regular_all_categories ||
        throw(ArgumentError(
            "primary-grid candidates must use regular_all_categories"))
    hasproperty(candidate, :preflight_seed) || throw(ArgumentError(
        "primary-grid candidate is missing preflight_seed"))
    selected_seed = seed === nothing ? Int(candidate.preflight_seed) :
                    Int(seed)
    return (plan = (;
        design = Symbol(candidate.design),
        n_persons = Int(candidate.persons),
        n_items = Int(candidate.items),
        n_raters = Int(candidate.raters),
        n_categories = Int(candidate.categories),
        seed = selected_seed,
    ), selected_seed)
end

"""
    simulate_mgmfrm_validation_primary_candidate(candidate;
        truth_scale = 0.15, seed = nothing)

Generate one regular four-category, two-dimensional fixed-Q MGMFRM dataset
from a row returned by [`mgmfrm_validation_primary_grid_candidates`](@ref).
The default seed belongs only to structural preflight; an explicit seed may be
supplied for later evaluation protocols.

The returned case preserves the generating parameters and probabilities and
checks data validity, fixed-Q identification, category support, and expected
observation count. It does not fit a model or produce validation evidence.
"""
function simulate_mgmfrm_validation_primary_candidate(candidate;
        truth_scale::Real = 0.15,
        seed::Union{Nothing,Integer} = nothing)
    isfinite(truth_scale) && truth_scale > 0 ||
        throw(ArgumentError("truth_scale must be finite and positive"))
    generation = _mgmfrm_validation_primary_generation_plan(
        candidate,
        seed,
    )
    baseline = _mgmfrm_known_truth_baseline(
        generation.plan,
        Float64(truth_scale),
    )
    validation = validate_design(baseline.data)
    spec = _mgmfrm_known_truth_spec(
        baseline.data,
        baseline.q_matrix;
        validation_report = validation,
    )
    design = getdesign(spec; preview = true)
    q_validation = q_matrix_validation(spec)
    response_pattern_audit = ordinal_response_pattern_audit(baseline.data)
    category_support_passed =
        isempty(response_pattern_audit.overall.unused_categories)
    observation_count_passed =
        baseline.data.n == Int(candidate.expected_observations)
    preflight_passed = validation.passed && q_validation.passed &&
        category_support_passed && observation_count_passed &&
        baseline.truth_parameters_valid &&
        baseline.truth_probabilities_valid

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_validation_primary_candidate_case.v1",
        object = :mgmfrm_validation_primary_candidate_case,
        status = preflight_passed ? :primary_candidate_generated :
                 :primary_candidate_preflight_failed,
        cell_id = candidate.cell_id,
        candidate,
        seed = generation.selected_seed,
        seed_role = seed === nothing ? candidate.seed_role :
                    :caller_supplied,
        data = baseline.data,
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
        validation,
        q_validation,
        response_pattern_audit,
        category_support_passed,
        observation_count_passed,
        preflight_passed,
        fit_eligible = validation.passed &&
            q_validation.identification.guarded_fit_structure_ready,
        fit_evidence = :not_run,
        scientific_decision = :not_applied,
        claim_scope =
            :mcmc_free_generation_and_preflight_not_recovery_evidence,
    )
end

"""
    mgmfrm_validation_primary_grid_preflight(
        contract = mgmfrm_validation_primary_grid_candidates();
        truth_scale = 0.15)

Generate and structurally inspect every candidate in the primary grid without
running MCMC. Generation errors remain typed exceptions; this planning
preflight does not convert failures into missing values or analysis outcomes.
"""
function mgmfrm_validation_primary_grid_preflight(
        contract = mgmfrm_validation_primary_grid_candidates();
        truth_scale::Real = 0.15)
    hasproperty(contract, :object) && contract.object ===
        :mgmfrm_validation_primary_grid_candidates || throw(ArgumentError(
        "contract must be returned by " *
        "mgmfrm_validation_primary_grid_candidates"))
    isempty(contract.cells) &&
        throw(ArgumentError("primary-grid contract must not be empty"))
    cases = Tuple(simulate_mgmfrm_validation_primary_candidate(
        candidate;
        truth_scale,
    ) for candidate in contract.cells)
    rows = Tuple((;
        cell_id = generated.cell_id,
        status = generated.status,
        preflight_passed = generated.preflight_passed,
        validation_passed = generated.validation.passed,
        q_validation_passed = generated.q_validation.passed,
        category_support_passed = generated.category_support_passed,
        observation_count_passed = generated.observation_count_passed,
        truth_probabilities_valid = generated.truth_probabilities_valid,
        truth_parameters_valid = generated.truth_parameters_valid,
        fit_eligible = generated.fit_eligible,
        fit_evidence = :not_run,
    ) for generated in cases)
    n_passed = count(row -> row.preflight_passed, rows)
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_validation_primary_grid_preflight.v1",
        object = :mgmfrm_validation_primary_grid_preflight,
        status = n_passed == length(rows) ? :preflight_complete :
                 :preflight_complete_with_rejections,
        rows,
        cases,
        summary = (;
            n_candidates = length(rows),
            n_preflight_passed = n_passed,
            n_preflight_rejected = length(rows) - n_passed,
            all_candidates_accounted_for = length(rows) ==
                contract.summary.n_candidate_cells,
        ),
        fit_evidence = :not_run,
        scientific_decision = :not_applied,
        next_gate = :freeze_resource_bounded_primary_grid_and_replications,
        claim_scope =
            :mcmc_free_generation_and_preflight_not_validation_evidence,
    )
end
