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
