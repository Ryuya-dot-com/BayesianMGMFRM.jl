#!/usr/bin/env julia

# Generate and execute the deterministic contract layer of the known-truth
# design-robustness study for the existing static APIs. The artifact also
# freezes the later paired-replication recovery grid. It does not run MCMC or
# widen any public model surface.

using JSON3
using SHA
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT = joinpath(
    ROOT,
    "test",
    "fixtures",
    "existing_api_design_robustness_plan.json",
)

include(joinpath(@__DIR__, "local_json.jl"))

const REFERENCE_RECORDS = [
    (;
        citation = "DeMars, Shapovalov, and Hathcoat (2023)",
        title = "Many-Facet Rasch Designs: How Should Raters be Assigned to Examinees?",
        source = :url,
        url = "https://commons.lib.jmu.edu/gradpsych/63/",
        contribution = :linking_topology_and_empirical_uncertainty,
    ),
    (;
        citation = "Hombo, Donoghue, and Thayer (2001)",
        title = "A simulation study of the effect of rater designs on ability estimation",
        source = :doi,
        doi = "10.1002/j.2333-8504.2001.tb01847.x",
        contribution = :nested_vs_spiral_assignment_bias,
    ),
    (;
        citation = "Wind and Jones (2018)",
        title = "The stabilizing influences of linking set size and model-data fit in sparse rater-mediated assessment networks",
        source = :doi,
        doi = "10.1177/0013164417703733",
        contribution = :linking_set_size_and_sparse_network_stability,
    ),
    (;
        citation = "Uto (2021)",
        title = "Accuracy of performance-test linking based on a many-facet Rasch model",
        source = :doi,
        doi = "10.3758/s13428-020-01498-x",
        contribution = :common_rater_and_task_linking_accuracy,
    ),
    (;
        citation = "Wang, Song, Wang, and Wolfe (2017)",
        title = "Essay selection methods for adaptive rater monitoring",
        source = :doi,
        doi = "10.1177/0146621616672855",
        contribution = :benchmark_information_efficiency,
    ),
    (;
        citation = "Huang (2023)",
        title = "Modeling rating order effects under item response theory models for rater-mediated assessments",
        source = :doi,
        doi = "10.1177/01466216231174566",
        contribution = :static_api_misspecification_boundary_for_order_effects,
    ),
    (;
        citation = "Yeates et al. (2022)",
        title = "Determining influence, interaction and causality of contrast and sequence effects in objective structured clinical exams",
        source = :doi,
        doi = "10.1111/medu.14713",
        contribution = :embedded_performance_early_late_order_effect,
    ),
]

function usage()
    return """
    Generate the existing-API design-robustness plan and deterministic checks.

    Usage:
      julia --project=. scripts/generate_existing_api_design_robustness_plan.jl [--output PATH]
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

function file_sha256(path::AbstractString)
    return bytes2hex(open(sha256, path))
end

function portable_json_hash(value)
    io = IOBuffer()
    write_json(io, value)
    return bytes2hex(sha256(take!(io)))
end

function fixture_record(name::Symbol, path::AbstractString,
        expected_schema::AbstractString, evidence_scope::Symbol)
    resolved = joinpath(ROOT, path)
    fixture = JSON3.read(read(resolved, String))
    schema = String(fixture[:schema])
    schema == expected_schema ||
        error("unexpected schema for $path: $schema")
    summary = fixture[:summary]
    return (;
        name,
        path = String(path),
        sha256 = file_sha256(resolved),
        schema,
        summary_passed = Bool(summary[:passed]),
        evidence_scope,
        design_robustness_claim_supported = false,
    )
end

function subset_table(table, indices; occasion = nothing)
    out = (;
        examinee = table.examinee[indices],
        rater = table.rater[indices],
        item = table.item[indices],
        score = table.score[indices],
    )
    occasion === nothing && return out
    return merge(out, (; occasion = occasion))
end

function balanced_double_rated_table(; n_persons::Int = 12,
        n_items::Int = 2, n_raters::Int = 4, n_categories::Int = 4)
    examinee = String[]
    rater = String[]
    item = String[]
    score = Int[]
    for person in 1:n_persons, item_index in 1:n_items
        first_rater = mod(person + item_index - 2, n_raters) + 1
        for rater_index in (first_rater, mod(first_rater, n_raters) + 1)
            push!(examinee, "E$(person)")
            push!(rater, "R$(rater_index)")
            push!(item, "I$(item_index)")
            push!(score, mod(person + 2item_index + rater_index, n_categories))
        end
    end
    return (; examinee, rater, item, score)
end

function facet_data(table; occasion::Bool = false)
    return BayesianMGMFRM.FacetData(
        table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        occasion = occasion ? :occasion : nothing,
    )
end

function named_parameter_values(names)
    ordered = sort(collect(String, names))
    midpoint = (length(ordered) + 1) / 2
    return Dict(name => 0.03 * (index - midpoint)
        for (index, name) in pairs(ordered))
end

function target_multiplicity_metrics(table)
    raters_by_target = Dict{Tuple{String,String},Set{String}}()
    for index in eachindex(table.score)
        target = (String(table.examinee[index]), String(table.item[index]))
        raters = get!(raters_by_target, target, Set{String}())
        push!(raters, String(table.rater[index]))
    end
    n_targets = length(raters_by_target)
    n_raters = length(unique(table.rater))
    n_multiply_scored = count(raters -> length(raters) >= 2,
        values(raters_by_target))
    n_all_raters_common = count(raters -> length(raters) == n_raters,
        values(raters_by_target))
    return (;
        n_targets,
        n_raters,
        multiply_scored_target_fraction = n_multiply_scored / n_targets,
        all_raters_common_target_fraction = n_all_raters_common / n_targets,
    )
end

function row_order_check()
    table = balanced_double_rated_table()
    multiplicity = target_multiplicity_metrics(table)
    n = length(table.score)
    permutation = vcat(collect(1:8), reverse(collect(9:n)))
    permuted_table = subset_table(table, permutation)
    data = facet_data(table)
    permuted_data = facet_data(permuted_table)
    design = BayesianMGMFRM.getdesign(BayesianMGMFRM.mfrm_spec(data))
    permuted_design =
        BayesianMGMFRM.getdesign(BayesianMGMFRM.mfrm_spec(permuted_data))
    name_values = named_parameter_values(design.parameter_names)
    Set(design.parameter_names) == Set(permuted_design.parameter_names) ||
        error("row permutation changed the named parameter set")
    params = [name_values[name] for name in design.parameter_names]
    permuted_params = [name_values[name] for name in permuted_design.parameter_names]
    pointwise = BayesianMGMFRM.pointwise_loglikelihood(design, params)
    permuted_pointwise = BayesianMGMFRM.pointwise_loglikelihood(
        permuted_design,
        permuted_params,
    )
    aligned_error = maximum(abs.(permuted_pointwise .- pointwise[permutation]))
    total_error = abs(sum(permuted_pointwise) - sum(pointwise))
    passed = aligned_error <= 1.0e-12 && total_error <= 1.0e-12 &&
        multiplicity.multiply_scored_target_fraction == 1.0 &&
        multiplicity.all_raters_common_target_fraction == 0.0
    return (;
        check_id = :row_order_equivariance,
        passed,
        n_observations = n,
        parameter_name_set_preserved = true,
        max_aligned_pointwise_loglikelihood_error = aligned_error,
        absolute_total_loglikelihood_error = total_error,
        tolerance = 1.0e-12,
        achieved_multiply_scored_target_fraction =
            multiplicity.multiply_scored_target_fraction,
        achieved_all_raters_common_target_fraction =
            multiplicity.all_raters_common_target_fraction,
        note = :same_observed_ratings_only_row_order_changed,
    )
end

function occasion_metadata_check()
    table = balanced_double_rated_table()
    n = length(table.score)
    plain_data = facet_data(table)
    occasion_table = subset_table(table, collect(1:n);
        occasion = ["O$(mod(index - 1, 4) + 1)" for index in 1:n])
    occasion_data = facet_data(occasion_table; occasion = true)
    plain_design = BayesianMGMFRM.getdesign(BayesianMGMFRM.mfrm_spec(plain_data))
    occasion_design =
        BayesianMGMFRM.getdesign(BayesianMGMFRM.mfrm_spec(occasion_data))
    same_names = plain_design.parameter_names == occasion_design.parameter_names
    params = [0.02 * index for index in eachindex(plain_design.parameter_names)]
    error = maximum(abs.(
        BayesianMGMFRM.pointwise_loglikelihood(plain_design, params) .-
        BayesianMGMFRM.pointwise_loglikelihood(occasion_design, params)
    ))
    audit = BayesianMGMFRM.rating_design_audit(occasion_data)
    occasion_row = only(row for row in audit.rows
        if row.audit === :optional_time_order_fields)
    passed = same_names && error <= 1.0e-12 &&
        occasion_row.status === :recorded_not_modeled
    return (;
        check_id = :occasion_metadata_not_likelihood,
        passed,
        parameter_names_preserved = same_names,
        max_pointwise_loglikelihood_error = error,
        tolerance = 1.0e-12,
        audit_status = occasion_row.status,
        interpretation = :occasion_presence_does_not_identify_order_or_drift,
    )
end

function nested_assignment_table(; n_persons::Int = 12,
        n_items::Int = 2, n_raters::Int = 4, n_categories::Int = 4)
    examinee = String[]
    rater = String[]
    item = String[]
    score = Int[]
    persons_per_rater = cld(n_persons, n_raters)
    for person in 1:n_persons, item_index in 1:n_items
        rater_index = min(cld(person, persons_per_rater), n_raters)
        push!(examinee, "E$(person)")
        push!(rater, "R$(rater_index)")
        push!(item, "I$(item_index)")
        push!(score, mod(person + item_index + rater_index, n_categories))
    end
    return (; examinee, rater, item, score)
end

function nested_negative_control_check()
    data = facet_data(nested_assignment_table())
    validation = BayesianMGMFRM.validate_design(data)
    audit = BayesianMGMFRM.rating_design_audit(data)
    codes = Tuple(sort!(unique(issue.code for issue in validation.issues)))
    passed = !validation.passed && :rank_deficient_design in codes &&
        !audit.passed && audit.summary.rater_linking_status === :disconnected &&
        audit.summary.nonignorable_assignment_flagged
    return (;
        check_id = :ability_nested_no_link_negative_control,
        passed,
        validation_passed = validation.passed,
        validation_issue_codes = codes,
        rating_design_audit_passed = audit.passed,
        rating_graph_status = audit.summary.rating_graph_status,
        rater_linking_status = audit.summary.rater_linking_status,
        nonignorable_assignment_flagged =
            audit.summary.nonignorable_assignment_flagged,
        expected_action = :block_fit_before_sampling,
    )
end

function linking_table(common_linking_target_fraction::Float64;
        n_persons::Int = 50, n_items::Int = 8,
        n_raters::Int = 6, n_categories::Int = 4)
    n_targets = n_persons * n_items
    n_linking_targets = round(Int, common_linking_target_fraction * n_targets)
    linking_indices = n_linking_targets == 0 ? Int[] :
        unique(round.(Int, range(1, n_targets; length = n_linking_targets)))
    length(linking_indices) == n_linking_targets ||
        error("linking-index construction did not preserve requested count")
    linking_set = Set(linking_indices)
    examinee = String[]
    rater = String[]
    item = String[]
    score = Int[]
    target_index = 0
    persons_per_rater = cld(n_persons, n_raters)
    for person in 1:n_persons, item_index in 1:n_items
        target_index += 1
        primary = min(cld(person, persons_per_rater), n_raters)
        raters = target_index in linking_set ? (1:n_raters) : (primary:primary)
        for rater_index in raters
            push!(examinee, "E$(person)")
            push!(rater, "R$(rater_index)")
            push!(item, "I$(item_index)")
            push!(score, mod(person + 2item_index + rater_index, n_categories))
        end
    end
    return (;
        table = (; examinee, rater, item, score),
        n_targets,
        n_linking_targets,
        requested_common_linking_target_fraction =
            common_linking_target_fraction,
        achieved_multiply_scored_target_fraction =
            n_linking_targets / n_targets,
        achieved_all_raters_common_target_fraction =
            n_linking_targets / n_targets,
        controlled_benchmark_target_fraction = 0.0,
        base_rating_events = n_targets,
        total_rating_events = length(score),
        linking_ratings_added = n_linking_targets * (n_raters - 1),
        additional_link_rating_fraction =
            n_linking_targets * (n_raters - 1) / length(score),
        common_target_rating_event_fraction =
            n_linking_targets * n_raters / length(score),
        rating_budget_policy = :additive,
    )
end

function linking_fraction_check(fraction::Float64)
    generated = linking_table(fraction)
    data = facet_data(generated.table)
    validation = BayesianMGMFRM.validate_design(data)
    linking = BayesianMGMFRM.anchor_linking_summary(
        data;
        unit = :person_item,
        min_shared_units = 2,
    )
    audit = BayesianMGMFRM.rating_design_audit(
        data;
        unit = :person_item,
        min_shared_units = 2,
    )
    minimum_shared = linking.minimum_shared_units
    passed = validation.passed && linking.passed && audit.passed &&
        generated.achieved_multiply_scored_target_fraction == fraction &&
        generated.achieved_all_raters_common_target_fraction == fraction &&
        generated.controlled_benchmark_target_fraction == 0.0 &&
        linking.anchor_status === :not_declared && linking.n_anchors == 0 &&
        minimum_shared == generated.n_linking_targets
    return (;
        check_id = Symbol("materialized_common_linking_fraction_" *
            replace(string(Int(round(100fraction))), "-" => "minus") * "pct"),
        passed,
        requested_common_linking_target_fraction = fraction,
        achieved_multiply_scored_target_fraction =
            generated.achieved_multiply_scored_target_fraction,
        achieved_all_raters_common_target_fraction =
            generated.achieved_all_raters_common_target_fraction,
        controlled_benchmark_target_fraction =
            generated.controlled_benchmark_target_fraction,
        n_targets = generated.n_targets,
        n_linking_targets = generated.n_linking_targets,
        base_rating_events = generated.base_rating_events,
        total_rating_events = generated.total_rating_events,
        linking_ratings_added = generated.linking_ratings_added,
        additional_link_rating_fraction =
            generated.additional_link_rating_fraction,
        common_target_rating_event_fraction =
            generated.common_target_rating_event_fraction,
        rating_budget_policy = generated.rating_budget_policy,
        minimum_shared_person_item_units = minimum_shared,
        rater_linking_status = linking.rater_linking_status,
        parameter_anchor_count = linking.n_anchors,
        parameter_anchor_status = linking.anchor_status,
        assignment_warning_retained = audit.summary.nonignorable_assignment_flagged,
    )
end

function parameter_anchor_guard_check()
    data = facet_data(balanced_double_rated_table())
    spec = BayesianMGMFRM.mfrm_spec(
        data;
        anchors = [(;
            block = :rater,
            level = "R1",
            value = 0.0,
            type = :hard,
        )],
    )
    linking = BayesianMGMFRM.anchor_linking_summary(spec)
    blocked = false
    error_type = missing
    try
        BayesianMGMFRM.getdesign(spec)
    catch err
        blocked = true
        error_type = Symbol(nameof(typeof(err)))
    end
    passed = spec.estimation_status === :specified_only && blocked &&
        linking.n_anchors == 1 &&
        linking.caveat === :diagnostic_summary_not_anchor_refit_or_linking_estimator
    return (;
        check_id = :parameter_anchor_guard,
        passed,
        estimation_status = spec.estimation_status,
        ordinary_design_compilation_blocked = blocked,
        error_type,
        parameter_anchor_count = linking.n_anchors,
        linking_summary_caveat = linking.caveat,
        interpretation = :parameter_anchor_not_materialized_linking_response,
    )
end

function simulation_anchor_metadata_check()
    rows = BayesianMGMFRM.simulation_grid(;
        densities = (:moderate,),
        anchor_sizes = (0, 20),
        ratings_per_target = (2,),
        category_pathologies = (:none,),
        rater_noise = (:moderate,),
        dff = (:none,),
        dimensionalities = (1,),
        misspecifications = (:none,),
        repetitions = 1,
        n_persons = 50,
        n_items = 8,
        n_raters = 6,
    )
    counts = unique(row.planned_n_ratings for row in rows)
    passed = length(rows) == 2 && length(counts) == 1 &&
        all(row -> row.simulation_status === :predeclared_not_run, rows)
    return (;
        check_id = :simulation_grid_anchor_size_is_planning_metadata,
        passed,
        anchor_sizes = Tuple(row.anchor_size for row in rows),
        planned_n_ratings = Tuple(row.planned_n_ratings for row in rows),
        unique_planned_n_ratings = Tuple(counts),
        simulation_statuses = Tuple(row.simulation_status for row in rows),
        interpretation = :anchor_size_does_not_materialize_shared_ratings,
    )
end

function current_evidence_records()
    return [
        fixture_record(
            :scalar_gmfrm_sparse_pathology_recovery,
            "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
            "bayesianmgmfrm.gmfrm_sparse_pathology_recovery_grid.v1",
            :three_small_connected_sparse_patterns_computational_smoke,
        ),
        fixture_record(
            :confirmatory_mgmfrm_sparse_recovery,
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
            "bayesianmgmfrm.mgmfrm_sparse_recovery_grid.v1",
            :three_small_connected_fixed_q_patterns_computational_smoke,
        ),
    ]
end

function scenario_rows()
    return [
        (;
            scenario_id = :C0_balanced_random_double_rated,
            assignment = :balanced_random,
            ratings_per_target = 2,
            planned_multiply_scored_target_fraction = 1.0,
            common_linking_target_fraction = 0.0,
            all_raters_common_target_fraction = 0.0,
            controlled_benchmark_target_fraction = 0.0,
            rating_budget_policy = :baseline_double_rating,
            planned_total_rating_events = 800,
            planned_ordinary_overlap_target_fraction = 1.0,
            linking_placement = :not_applicable,
            execution = :fit,
            role = :identified_baseline,
        ),
        (;
            scenario_id = :C0P_same_ratings_row_permuted,
            assignment = :same_as_C0,
            ratings_per_target = 2,
            planned_multiply_scored_target_fraction = 1.0,
            common_linking_target_fraction = 0.0,
            all_raters_common_target_fraction = 0.0,
            controlled_benchmark_target_fraction = 0.0,
            rating_budget_policy = :same_as_C0,
            planned_total_rating_events = 800,
            planned_ordinary_overlap_target_fraction = 1.0,
            linking_placement = :not_applicable,
            execution = :deterministic_invariance_only,
            role = :row_order_equivariance,
        ),
        (;
            scenario_id = :C1_ability_nested_no_link,
            assignment = :ability_informed_nested,
            ratings_per_target = 1,
            planned_multiply_scored_target_fraction = 0.0,
            common_linking_target_fraction = 0.0,
            all_raters_common_target_fraction = 0.0,
            controlled_benchmark_target_fraction = 0.0,
            rating_budget_policy = :single_rating_baseline,
            planned_total_rating_events = 400,
            planned_ordinary_overlap_target_fraction = 0.0,
            linking_placement = :not_applicable,
            execution = :prefit_rejection_only,
            role = :negative_design_control,
        ),
        (;
            scenario_id = :C2A_nested_5pct_link_early_additive,
            assignment = :ability_informed_nested,
            ratings_per_target = 1,
            planned_multiply_scored_target_fraction = 0.05,
            common_linking_target_fraction = 0.05,
            all_raters_common_target_fraction = 0.05,
            controlled_benchmark_target_fraction = 0.0,
            rating_budget_policy = :additive,
            planned_total_rating_events = 500,
            planned_ordinary_overlap_target_fraction = 0.0,
            linking_placement = :early_only,
            execution = :fit,
            role = :weak_linking_stress,
        ),
        (;
            scenario_id = :C2P_same_ratings_5pct_link_distributed,
            assignment = :same_as_C2A,
            ratings_per_target = 1,
            planned_multiply_scored_target_fraction = 0.05,
            common_linking_target_fraction = 0.05,
            all_raters_common_target_fraction = 0.05,
            controlled_benchmark_target_fraction = 0.0,
            rating_budget_policy = :same_as_C2A,
            planned_total_rating_events = 500,
            planned_ordinary_overlap_target_fraction = 0.0,
            linking_placement = :distributed,
            execution = :deterministic_invariance_only,
            role = :placement_only_static_contrast,
        ),
        (;
            scenario_id = :C2F_nested_5pct_link_early_fixed_total,
            assignment = :ability_informed_nested,
            ratings_per_target = 1,
            planned_multiply_scored_target_fraction = 0.05,
            planned_multiply_scored_target_fraction_observed = 1 / 15,
            common_linking_target_fraction = 0.05,
            all_raters_common_target_fraction = 0.05,
            controlled_benchmark_target_fraction = 0.0,
            rating_budget_policy = :fixed_total_target_displacement,
            planned_total_rating_events = 400,
            planned_observed_target_fraction = 0.75,
            planned_dropped_target_fraction = 0.25,
            planned_ordinary_overlap_target_fraction = 0.0,
            linking_placement = :early_only,
            execution = :fit,
            role = :weak_linking_vs_operational_target_coverage,
        ),
        (;
            scenario_id = :C3A_nested_10pct_link_distributed_additive,
            assignment = :ability_informed_nested,
            ratings_per_target = 1,
            planned_multiply_scored_target_fraction = 0.10,
            common_linking_target_fraction = 0.10,
            all_raters_common_target_fraction = 0.10,
            controlled_benchmark_target_fraction = 0.0,
            rating_budget_policy = :additive,
            planned_total_rating_events = 600,
            planned_ordinary_overlap_target_fraction = 0.0,
            linking_placement = :distributed,
            execution = :fit,
            role = :linking_dose_contrast,
        ),
        (;
            scenario_id = :C3F_nested_10pct_link_distributed_fixed_total,
            assignment = :ability_informed_nested,
            ratings_per_target = 1,
            planned_multiply_scored_target_fraction = 0.10,
            planned_multiply_scored_target_fraction_observed = 0.20,
            common_linking_target_fraction = 0.10,
            all_raters_common_target_fraction = 0.10,
            controlled_benchmark_target_fraction = 0.0,
            rating_budget_policy = :fixed_total_target_displacement,
            planned_total_rating_events = 400,
            planned_observed_target_fraction = 0.50,
            planned_dropped_target_fraction = 0.50,
            planned_ordinary_overlap_target_fraction = 0.0,
            linking_placement = :distributed,
            execution = :fit,
            role = :linking_information_vs_operational_target_coverage,
        ),
        (;
            scenario_id = :C4_ability_nested_10pct_narrow_support,
            assignment = :ability_informed_nested,
            ratings_per_target = 1,
            planned_multiply_scored_target_fraction = 0.10,
            common_linking_target_fraction = 0.10,
            all_raters_common_target_fraction = 0.10,
            controlled_benchmark_target_fraction = 0.0,
            rating_budget_policy = :additive,
            planned_total_rating_events = 600,
            planned_ordinary_overlap_target_fraction = 0.0,
            linking_placement = :distributed,
            execution = :second_batch_fit,
            role = :linking_range_blind_spot,
        ),
    ]
end

function order_misspecification_rows()
    return [
        (;
            scenario_id = :M0_no_order_effect_random_sequence,
            true_order_effect = :none,
            ability_order = :random,
            expected_static_status = :well_specified,
            role = :negative_control,
        ),
        (;
            scenario_id = :M1_order_effect_random_sequence,
            true_order_effect = :linear_severity_change,
            ability_order = :random,
            expected_static_status = :misspecified,
            role = :order_effect_without_case_mix_trend,
        ),
        (;
            scenario_id = :M2_order_effect_reinforcing_ability_sequence,
            true_order_effect = :linear_severity_change,
            ability_order = :reinforcing_low_to_high_or_high_to_low,
            expected_static_status = :misspecified,
            role = :order_and_case_mix_amplification,
        ),
        (;
            scenario_id = :M3_order_effect_opposing_ability_sequence,
            true_order_effect = :linear_severity_change,
            ability_order = :opposing_low_to_high_or_high_to_low,
            expected_static_status = :misspecified,
            role = :order_and_case_mix_cancellation,
        ),
        (;
            scenario_id = :M4_order_effect_block_clustered_sequence,
            true_order_effect = :linear_severity_change,
            ability_order = :block_clustered,
            expected_static_status = :misspecified,
            role = :order_and_case_mix_local_clustering,
        ),
    ]
end

function build_artifact()
    checks = [
        row_order_check(),
        occasion_metadata_check(),
        nested_negative_control_check(),
        linking_fraction_check(0.05),
        linking_fraction_check(0.10),
        parameter_anchor_guard_check(),
        simulation_anchor_metadata_check(),
    ]
    evidence = current_evidence_records()
    scenarios = scenario_rows()
    misspecification_scenarios = order_misspecification_rows()
    all_checks_passed = all(row.passed for row in checks)
    artifact = (;
        schema = "bayesianmgmfrm.existing_api_design_robustness_plan.v1",
        family = :mfrm_gmfrm_mgmfrm,
        scope = :existing_static_api_design_robustness,
        status = all_checks_passed ?
            :deterministic_contract_checks_passed_recovery_not_run :
            :deterministic_contract_checks_failed,
        decision = :run_paired_known_truth_recovery_before_dynamic_extension,
        public_claim_release_allowed = false,
        publication_or_registration_action = false,
        package = (;
            name = :BayesianMGMFRM,
            version = project_version(),
        ),
        generator = (;
            script = "scripts/generate_existing_api_design_robustness_plan.jl",
            source_sha256 = file_sha256(@__FILE__),
            deterministic = true,
        ),
        terminology = (;
            parameter_anchor =
                :hard_or_soft_parameter_constraint_currently_specified_only,
            multiply_scored_target =
                :unique_person_item_response_scored_by_two_or_more_raters,
            common_linking_target =
                :planned_shared_response_scored_by_the_designated_linking_raters,
            controlled_benchmark_target =
                :planned_control_response_with_reference_information,
            requested_target_fraction_denominator =
                :all_planned_unique_person_item_targets,
            observed_target_fraction_denominator =
                :observed_unique_person_item_targets,
            common_target_rating_event_fraction_denominator =
                :all_rating_events,
            additional_link_rating_fraction_denominator = :all_rating_events,
            temporal_benchmark =
                :repeated_control_response_placed_across_sequence_not_a_parameter_anchor,
            anchor_size_legacy_grid_field =
                :planning_metadata_not_materialized_shared_response_count,
        ),
        reference_records = REFERENCE_RECORDS,
        current_evidence_audit = evidence,
        current_evidence_boundary = (;
            generic_simulation_grid_runs_fits = false,
            generic_anchor_size_materializes_linking_targets = false,
            existing_sparse_fixtures_cross_nonrandom_assignment = false,
            existing_sparse_fixtures_cross_presentation_order = false,
            existing_sparse_fixtures_cross_omitted_order_effect = false,
            existing_sparse_fixtures_cross_linking_target_fraction = false,
            conclusion = :computational_smoke_is_not_design_robustness_evidence,
        ),
        deterministic_contract_checks = checks,
        study_tracks = (;
            A_well_specified_static_recovery = (;
                true_order_effect = :none,
                purpose =
                    :isolate_topology_assignment_linking_and_latent_dispersion,
                order_role =
                    :pure_permutation_equivariance_only_not_a_confounding_test,
            ),
            B_static_misspecification_boundary = (;
                fitted_model = :same_existing_static_api,
                true_order_effect = (:none, :linear_severity_change,
                    :change_point),
                purpose =
                    :measure_bias_and_detection_when_order_dependence_is_omitted,
                interpretation =
                    :failure_maps_the_static_api_boundary_not_a_dynamic_fit_claim,
            ),
        ),
        study_axes = (;
            model_family = (:mfrm, :guarded_scalar_gmfrm,
                :guarded_fixed_q_mgmfrm),
            rating_topology = (:fully_crossed, :rotating_pairs,
                :fixed_pairs, :random_pairs, :mostly_single_common_linking_set,
                :weak_bridge, :disconnected_rejection),
            assignment = (:balanced_random, :ability_stratified_balanced,
                :ability_informed_nested, :severity_aligned,
                :severity_opposed),
            presentation_order = (:random, :row_permutation_only),
            misspecification_ability_order = (:random, :low_to_high,
                :high_to_low, :block_clustered),
            common_linking_target_fraction = (0.0, 0.02, 0.05, 0.10, 0.20),
            linking_raters_per_common_target = (2, 3, :all_raters),
            rating_budget_policy =
                (:additive, :fixed_total_target_displacement),
            linking_support = (:full_ability_and_item_range, :narrow_low,
                :narrow_middle, :narrow_high),
            linking_placement = (:not_applicable, :early_only,
                :distributed),
            ability_sd = (0.5, 1.0, 2.0),
            rater_severity_sd = (0.25, 0.75, 1.50),
            threshold_spacing = (:compressed, :reference, :wide),
        ),
        mandatory_scenarios = scenarios,
        order_misspecification_scenarios = misspecification_scenarios,
        design_realization_metrics = (;
            required = (:n_rating_events, :achieved_score_sd,
                :observed_target_fraction, :dropped_target_fraction,
                :achieved_multiply_scored_target_fraction,
                :achieved_all_raters_common_target_fraction,
                :achieved_controlled_benchmark_target_fraction,
                :achieved_common_target_rating_event_fraction,
                :achieved_additional_link_rating_fraction,
                :rater_load_min, :rater_load_max, :rater_load_cv,
                :common_target_ability_range,
                :common_target_ability_quantile_coverage,
                :within_rater_sequence_ability_correlation,
                :assignment_severity_correlation,
                :late_minus_early_ability_mean,
                :common_target_fraction_by_sequence_block,
                :rating_graph_components, :rater_link_components,
                :minimum_pairwise_overlap, :category_use_counts),
            source = :materialized_rating_rows_not_scenario_labels,
        ),
        design_selection = (;
            strategy =
                :mandatory_paired_cells_then_interaction_focused_fractional_factorial,
            full_factorial_allowed = false,
            reason = :full_cross_is_computationally_intractable_and_scientifically_redundant,
            paired_truth_and_seed_policy = true,
            fixed_total_target_displacement = (;
                base_unique_targets = 400,
                rating_event_budget = 400,
                allocation_rule =
                    :each_added_common_rating_displaces_one_ordinary_person_item_target,
                required_reporting = (:planned_target_fraction,
                    :observed_target_fraction, :dropped_target_fraction),
            ),
            future_unimplemented_budget_policy = (;
                policy = :fixed_total_routine_overlap_reallocation,
                purpose =
                    :retain_all_targets_and_reallocate_routine_duplicate_ratings_to_common_targets,
            ),
        ),
        execution_stages = [
            (;
                stage = :D0_deterministic_contract,
                status = all_checks_passed ? :passed : :failed,
                simulations = false,
                mcmc_fits = false,
                purpose = :api_equivariance_guards_and_materialized_design_counts,
            ),
            (;
                stage = :D1_paired_pilot,
                status = :predeclared_not_run,
                replications = 30,
                fitted_scenarios = (:C0_balanced_random_double_rated,
                    :C2A_nested_5pct_link_early_additive,
                    :C2F_nested_5pct_link_early_fixed_total,
                    :C3A_nested_10pct_link_distributed_additive,
                    :C3F_nested_10pct_link_distributed_fixed_total),
                families = (:mfrm, :guarded_scalar_gmfrm,
                    :guarded_fixed_q_mgmfrm),
                study_track = :A_well_specified_static_recovery,
                purpose = :debug_and_recovery_threshold_freeze_not_release_evidence,
            ),
            (;
                stage = :D1B_order_misspecification_pilot,
                status = :predeclared_not_run,
                replications = 30,
                fitted_candidate = :same_existing_static_api,
                scenarios = Tuple(row.scenario_id
                    for row in misspecification_scenarios),
                study_track = :B_static_misspecification_boundary,
                purpose = :quantify_omitted_order_effect_bias_and_audit_power,
            ),
            (;
                stage = :D2_calibration,
                status = :blocked_until_D1_thresholds_frozen,
                replications = :at_least_50_extend_to_100_if_monte_carlo_uncertain,
                paired_seed_policy = true,
                purpose = :known_truth_recovery_calibration_and_linking_dose_curve,
            ),
        ],
        estimands = (;
            recovery = (:bias, :mae, :rmse, :interval_coverage,
                :interval_width, :empirical_to_posterior_se_ratio),
            focal_blocks = (:person_ability, :rater_severity,
                :item_difficulty, :thresholds, :rater_consistency,
                :fixed_q_dimension_parameters),
            prediction = (:category_probability_error,
                :expected_score_error, :heldout_log_predictive_density,
                :posterior_predictive_calibration),
            decision = (:rank_stability, :cut_score_flip_rate,
                :pairwise_rater_contrast_stability),
            design = (:graph_components, :rater_link_components,
                :achieved_linking_fraction, :benchmark_burden,
                :assignment_warning_retention),
        ),
        gates = (;
            fixed_contract_and_sampler = (;
                max_rhat = 1.01,
                min_bulk_ess = 400,
                min_tail_ess = 400,
                required_divergences = 0,
                required_max_treedepth_hits = 0,
                disconnected_negative_control_fit_attempts = 0,
                permutation_equivariance_tolerance = 1.0e-12,
                require_empirical_vs_posterior_uncertainty_comparison = true,
                require_assignment_warning_under_ability_informed_design = true,
                require_parameter_anchor_and_linking_target_separation = true,
                require_requested_vs_achieved_design_checks = true,
            ),
            provisional_recovery_and_decision = (;
                min_aggregate_interval_coverage = 0.90,
                max_block_mae = 0.35,
                max_focal_absolute_error = 0.75,
                max_expected_score_calibration_error = 0.25,
                max_category_probability_error = 0.10,
                max_decision_flip_rate = 0.10,
                status = :freeze_after_pilot_before_evaluation_seeds,
            ),
            threshold_policy =
                :fixed_sampler_contract_then_pilot_freeze_for_recovery_gates,
        ),
        execution_policy = (;
            deterministic_checks_executed = true,
            simulations_executed = false,
            mcmc_fits_executed = false,
            recovery_claim_evaluated = false,
            dynamic_model_in_scope = false,
            next_artifact =
                "scripts/generate_existing_api_design_robustness_stress_grid.jl",
        ),
        summary = (;
            passed = all_checks_passed,
            n_reference_records = length(REFERENCE_RECORDS),
            n_current_evidence_artifacts = length(evidence),
            n_deterministic_checks = length(checks),
            n_deterministic_checks_passed = count(row -> row.passed, checks),
            n_mandatory_scenarios = length(scenarios),
            n_order_misspecification_scenarios =
                length(misspecification_scenarios),
            deterministic_contract_checks_passed = all_checks_passed,
            paired_known_truth_recovery_completed = false,
            design_robustness_claim_supported = false,
            public_claim_release_allowed = false,
            recommendation =
                :run_paired_static_recovery_grid_before_temporal_drift_grid,
            next_gate = :existing_api_design_robustness_stress_grid,
        ),
    )
    return merge(artifact, (;
        content_hash = (;
            algorithm = :sha256,
            value = portable_json_hash(artifact),
            covers = :artifact_without_content_hash,
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
        " deterministic_checks=", artifact.summary.n_deterministic_checks_passed,
        "/", artifact.summary.n_deterministic_checks,
        " recovery_completed=", artifact.summary.paired_known_truth_recovery_completed,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
