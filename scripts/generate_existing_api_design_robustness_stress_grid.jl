#!/usr/bin/env julia

# Materialize the paired known-truth stress grid for the existing static MFRM,
# guarded scalar GMFRM, and guarded fixed-Q MGMFRM APIs. The default invocation
# is a deterministic simulation/compilation dry-run: it never starts MCMC.
# Sampling requires --execute, and pilot/calibration budgets additionally
# require --allow-heavy.

using JSON3
using Dates
using Random
using SHA
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT = joinpath(
    ROOT,
    "test",
    "fixtures",
    "existing_api_design_robustness_stress_grid.json",
)
const PLAN_PATH = joinpath(
    ROOT,
    "test",
    "fixtures",
    "existing_api_design_robustness_plan.json",
)

include(joinpath(@__DIR__, "local_json.jl"))

const FAMILIES = (:mfrm, :guarded_scalar_gmfrm, :guarded_fixed_q_mgmfrm)
const BASE_SKELETON_SEED = 20260630
const BASE_SIMULATION_SEED = 20260730
const BASE_SAMPLER_SEED = 20260830
const ORDER_EFFECT_SLOPE = 0.8
const RECOVERY_GATE_SCORER_IMPLEMENTED = true
const PREDICTIVE_GATE_SCORER_IMPLEMENTED = false
const DECISION_GATE_SCORER_IMPLEMENTED = false
const MINIMUM_CALIBRATION_REPLICATIONS = 50
const RECOVERY_NUMERIC_TOLERANCE = 1.0e-10
const FULL_GATE_SCORER_IMPLEMENTED = RECOVERY_GATE_SCORER_IMPLEMENTED &&
    PREDICTIVE_GATE_SCORER_IMPLEMENTED && DECISION_GATE_SCORER_IMPLEMENTED

const CANONICAL_FAMILY_BY_RUNNER_FAMILY = Dict(
    :mfrm => :mfrm,
    :guarded_scalar_gmfrm => :gmfrm,
    :guarded_fixed_q_mgmfrm => :mgmfrm,
)

const CANONICAL_RECOVERY_BLOCK_BY_FAMILY = Dict(
    :mfrm => Dict(
        :person => :person_ability,
        :rater => :rater_severity,
        :item => :item_difficulty,
        :thresholds => :thresholds,
    ),
    :guarded_scalar_gmfrm => Dict(
        :person => :person_ability,
        :rater => :rater_severity,
        :item => :item_difficulty,
        :item_discrimination => :item_discrimination,
        :rater_consistency => :rater_consistency,
        :rater_steps => :thresholds,
    ),
    :guarded_fixed_q_mgmfrm => Dict(
        :person => :person_ability,
        :rater => :rater_severity,
        :item => :item_difficulty,
        :item_dimension_discrimination => :fixed_q_dimension_parameters,
        :rater_consistency => :rater_consistency,
        :item_steps => :thresholds,
    ),
)

const FOCAL_RECOVERY_BLOCKS = (
    :person_ability,
    :rater_severity,
    :item_difficulty,
    :thresholds,
    :item_discrimination,
    :rater_consistency,
    :fixed_q_dimension_parameters,
)

const REQUIRED_RECOVERY_CONDITIONS = (
    :A_well_specified_static,
    :B_unmodeled_order_effect,
)

const REQUIRED_DETERMINISTIC_CHECKS = (
    :prerequisite_plan_passed,
    :mandatory_plus_fractional_subset_not_full_factorial,
    :positive_cells_compile_and_have_finite_probabilities,
    :negative_controls_rejected_before_sampling,
    :rating_budget_accounting,
    :three_family_s0p_s2p_row_permutation_equivariance,
    :three_family_c2p_same_event_placement_contrast,
    :profile_fit_cells_meet_requested_vs_achieved_gate,
    :replication_seed_resamples_assignment_and_order_skeleton,
    :paired_static_and_order_effect_conditions_separated,
    :known_truth_likelihood_smoke_finite,
    :default_path_does_not_attempt_mcmc,
    :executed_fit_wiring,
)

const SEED_NAMESPACE_OFFSETS = (;
    smoke_wiring = 0,
    pilot_threshold = 10_000_000,
    calibration_evaluation = 20_000_000,
)

const _CANONICAL_PROFILE_PREFLIGHT_CACHE = Dict{Tuple{Symbol,Int},Any}()

function arithmetic_mean(values)
    total = 0.0
    n = 0
    for value in values
        total += Float64(value)
        n += 1
    end
    n > 0 || throw(ArgumentError("mean requires at least one value"))
    return total / n
end

function sample_standard_deviation(values)
    materialized = Float64.(collect(values))
    length(materialized) >= 2 || return NaN
    center = arithmetic_mean(materialized)
    return sqrt(sum(abs2(value - center) for value in materialized) /
        (length(materialized) - 1))
end

function nearest_rank_quantile(values, probability::Real)
    0.0 <= probability <= 1.0 || throw(ArgumentError(
        "quantile probability must be in [0, 1]",
    ))
    sorted = sort!(Float64.(collect(values)))
    isempty(sorted) && throw(ArgumentError(
        "quantile requires at least one value",
    ))
    index = clamp(ceil(Int, Float64(probability) * length(sorted)),
        1, length(sorted))
    return sorted[index]
end

function wilson_upper(successes::Int, trials::Int, z::Real)
    0 <= successes <= trials || throw(ArgumentError(
        "Wilson counts must satisfy 0 <= successes <= trials",
    ))
    trials > 0 || throw(ArgumentError("Wilson interval requires trials > 0"))
    checked_z = Float64(z)
    isfinite(checked_z) && checked_z > 0 || throw(ArgumentError(
        "Wilson z must be finite and positive",
    ))
    p = successes / trials
    z2 = checked_z * checked_z
    denominator = 1.0 + z2 / trials
    center = p + z2 / (2trials)
    radius = checked_z * sqrt(
        p * (1.0 - p) / trials + z2 / (4trials * trials),
    )
    return min(1.0, (center + radius) / denominator)
end

function replication_cluster_mean_upper(values, z::Real)
    rates = Float64.(collect(values))
    length(rates) >= 2 || return (;
        n_replications = length(rates),
        mean = isempty(rates) ? missing : only(rates),
        standard_deviation = missing,
        standard_error = missing,
        upper = missing,
        status = :insufficient_replications,
    )
    all(value -> isfinite(value) && 0.0 <= value <= 1.0, rates) ||
        throw(ArgumentError("replication coverage rates must be in [0, 1]"))
    checked_z = Float64(z)
    isfinite(checked_z) && checked_z > 0 || throw(ArgumentError(
        "cluster coverage z must be finite and positive",
    ))
    center = arithmetic_mean(rates)
    standard_deviation = sample_standard_deviation(rates)
    standard_error = standard_deviation / sqrt(length(rates))
    return (;
        n_replications = length(rates),
        mean = center,
        standard_deviation,
        standard_error,
        upper = min(1.0, center + checked_z * standard_error),
        status = :computed,
    )
end

const GATE_CONTRACT = (;
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
        recovery_interval_probability = 0.90,
        coverage_cluster_z = 3.50,
        block_mae_quantile_probability = 0.95,
        focal_absolute_error_quantile_probability = 0.99,
        uncertainty_ratio_lower_quantile_probability = 0.01,
        uncertainty_ratio_upper_quantile_probability = 0.99,
        status = :fixed_before_pilot,
    ),
    provisional_recovery_and_decision = (;
        nominal_interval_coverage = 0.90,
        max_block_mae_quantile = 0.35,
        max_focal_absolute_error_quantile = 0.75,
        min_empirical_to_posterior_sd_ratio_quantile = 0.50,
        max_empirical_to_posterior_sd_ratio_quantile = 2.00,
        max_expected_score_calibration_error = 0.25,
        max_category_probability_error = 0.10,
        max_decision_flip_rate = 0.10,
        status = :freeze_after_pilot_before_evaluation_seeds,
    ),
    threshold_policy =
        :fixed_sampler_contract_then_pilot_freeze_for_recovery_gates,
)

const DESIGN_CELLS = [
    (;
        cell_id = :C0_balanced_random_double_rated,
        tier = :mandatory,
        role = :identified_baseline,
        rating_topology = :rotating_pairs,
        assignment = :balanced_random,
        routine_ratings_per_target = 2,
        common_linking_fraction = 0.0,
        common_linking_support = :full_ability_and_item_range,
        common_linking_placement = :not_applicable,
        presentation_order = :random,
        budget_policy = :baseline_double_rating,
        ability_sd = 1.0,
        rater_severity_sd = 0.75,
        threshold_spacing = :reference,
        expected_prefit_rejection = false,
        smoke_fit = true,
        pilot_fit = true,
        families = FAMILIES,
    ),
    (;
        cell_id = :C1_ability_nested_no_link,
        tier = :mandatory,
        role = :negative_design_control,
        rating_topology = :mostly_single_no_link_disconnected,
        assignment = :ability_informed_nested,
        routine_ratings_per_target = 1,
        common_linking_fraction = 0.0,
        common_linking_support = :full_ability_and_item_range,
        common_linking_placement = :not_applicable,
        presentation_order = :high_to_low,
        budget_policy = :single_rating_baseline,
        ability_sd = 1.0,
        rater_severity_sd = 0.75,
        threshold_spacing = :reference,
        expected_prefit_rejection = true,
        smoke_fit = false,
        pilot_fit = false,
        families = FAMILIES,
    ),
    (;
        cell_id = :C2A_nested_5pct_link_early_additive,
        tier = :mandatory,
        role = :weak_linking_additive_budget,
        rating_topology = :mostly_single_common_linking_set,
        assignment = :ability_informed_nested,
        routine_ratings_per_target = 1,
        common_linking_fraction = 0.05,
        common_linking_support = :full_ability_and_item_range,
        common_linking_placement = :early_only,
        presentation_order = :high_to_low,
        budget_policy = :additive,
        ability_sd = 1.0,
        rater_severity_sd = 0.75,
        threshold_spacing = :reference,
        expected_prefit_rejection = false,
        smoke_fit = false,
        pilot_fit = true,
        families = FAMILIES,
    ),
    (;
        cell_id = :C2F_nested_5pct_link_early_fixed_total,
        tier = :mandatory,
        role = :weak_linking_fixed_total_budget,
        rating_topology = :mostly_single_common_linking_set,
        assignment = :ability_informed_nested,
        routine_ratings_per_target = 1,
        common_linking_fraction = 0.05,
        common_linking_support = :full_ability_and_item_range,
        common_linking_placement = :early_only,
        presentation_order = :high_to_low,
        budget_policy = :fixed_total_target_displacement,
        ability_sd = 1.0,
        rater_severity_sd = 0.75,
        threshold_spacing = :reference,
        expected_prefit_rejection = false,
        smoke_fit = false,
        pilot_fit = true,
        families = FAMILIES,
    ),
    (;
        cell_id = :C3A_nested_10pct_link_distributed_additive,
        tier = :mandatory,
        role = :linking_dose_additive_budget,
        rating_topology = :mostly_single_common_linking_set,
        assignment = :ability_informed_nested,
        routine_ratings_per_target = 1,
        common_linking_fraction = 0.10,
        common_linking_support = :full_ability_and_item_range,
        common_linking_placement = :distributed,
        presentation_order = :high_to_low,
        budget_policy = :additive,
        ability_sd = 1.0,
        rater_severity_sd = 0.75,
        threshold_spacing = :reference,
        expected_prefit_rejection = false,
        smoke_fit = false,
        pilot_fit = true,
        families = FAMILIES,
    ),
    (;
        cell_id = :C3F_nested_10pct_link_distributed_fixed_total,
        tier = :mandatory,
        role = :linking_dose_fixed_total_budget,
        rating_topology = :mostly_single_common_linking_set,
        assignment = :ability_informed_nested,
        routine_ratings_per_target = 1,
        common_linking_fraction = 0.10,
        common_linking_support = :full_ability_and_item_range,
        common_linking_placement = :distributed,
        presentation_order = :high_to_low,
        budget_policy = :fixed_total_target_displacement,
        ability_sd = 1.0,
        rater_severity_sd = 0.75,
        threshold_spacing = :reference,
        expected_prefit_rejection = false,
        smoke_fit = false,
        pilot_fit = true,
        families = FAMILIES,
    ),
    (;
        cell_id = :C4_ability_nested_10pct_narrow_support,
        tier = :mandatory_second_batch,
        role = :linking_range_blind_spot,
        rating_topology = :mostly_single_common_linking_set,
        assignment = :ability_informed_nested,
        routine_ratings_per_target = 1,
        common_linking_fraction = 0.10,
        common_linking_support = :narrow_middle,
        common_linking_placement = :distributed,
        presentation_order = :high_to_low,
        budget_policy = :additive,
        ability_sd = 1.0,
        rater_severity_sd = 0.75,
        threshold_spacing = :reference,
        expected_prefit_rejection = false,
        smoke_fit = false,
        pilot_fit = false,
        families = FAMILIES,
    ),
    (;
        cell_id = :F1_mfrm_2pct_high_variance_random_order,
        tier = :fractional_subset,
        role = :weak_bridge_high_ability_variance,
        rating_topology = :weak_bridge,
        assignment = :ability_stratified_balanced,
        routine_ratings_per_target = 1,
        common_linking_fraction = 0.02,
        common_linking_support = :full_ability_and_item_range,
        common_linking_placement = :distributed,
        presentation_order = :random,
        budget_policy = :additive,
        ability_sd = 2.0,
        rater_severity_sd = 0.75,
        threshold_spacing = :wide,
        expected_prefit_rejection = false,
        smoke_fit = false,
        pilot_fit = false,
        families = (:mfrm,),
    ),
    (;
        cell_id = :F2_gmfrm_20pct_low_variance_opposed_order,
        tier = :fractional_subset,
        role = :high_linking_low_ability_variance,
        rating_topology = :mostly_single_common_linking_set,
        assignment = :severity_opposed,
        routine_ratings_per_target = 1,
        common_linking_fraction = 0.20,
        common_linking_support = :full_ability_and_item_range,
        common_linking_placement = :distributed,
        presentation_order = :low_to_high,
        budget_policy = :additive,
        ability_sd = 0.5,
        rater_severity_sd = 1.50,
        threshold_spacing = :compressed,
        expected_prefit_rejection = false,
        smoke_fit = false,
        pilot_fit = false,
        families = (:guarded_scalar_gmfrm,),
    ),
    (;
        cell_id = :F3_mgmfrm_10pct_narrow_support_fixed_total,
        tier = :fractional_subset,
        role = :linking_range_blind_spot,
        rating_topology = :mostly_single_common_linking_set,
        assignment = :severity_aligned,
        routine_ratings_per_target = 1,
        common_linking_fraction = 0.10,
        common_linking_support = :narrow_middle,
        common_linking_placement = :distributed,
        presentation_order = :block_clustered,
        budget_policy = :fixed_total_target_displacement,
        ability_sd = 2.0,
        rater_severity_sd = 1.50,
        threshold_spacing = :wide,
        expected_prefit_rejection = false,
        smoke_fit = false,
        pilot_fit = false,
        families = (:guarded_fixed_q_mgmfrm,),
    ),
]

const C2P_CONTROL_CELL = let source = only(cell for cell in DESIGN_CELLS
        if cell.cell_id === :C2A_nested_5pct_link_early_additive)
    merge(source, (;
        cell_id = :C2P_same_ratings_5pct_link_distributed,
        tier = :deterministic_control,
        role = :same_rating_event_placement_contrast,
        common_linking_placement = :distributed,
        smoke_fit = false,
        pilot_fit = false,
    ))
end

function usage()
    return """
    Generate the paired known-truth existing-API design stress grid.

    The default is a one-replication deterministic dry-run. It materializes
    designs, simulates paired static/order-effect scores, and evaluates the
    known-truth likelihood, but does not run MCMC.

    Usage:
      julia --project=. scripts/generate_existing_api_design_robustness_stress_grid.jl [options]

    Options:
      --output PATH                Output JSON path.
      --profile smoke|pilot|calibration
                                   Execution plan (default: smoke).
      --replications N             Override the profile replication count.
      --execute                    Run public fit entrypoints.
      --allow-heavy                Required with --execute outside the one-rep smoke.
      -h, --help                   Show this help.

    Safety:
      --execute requires an explicit non-fixture --output path. Pilot/calibration
      MCMC and any executed run with more than one replication require --allow-heavy.
      Pilot/calibration MCMC is blocked until the declared full gate scorer is
      implemented; their profiles remain available as MCMC-free design plans.
    """
end

function resolves_to_default_output(path::AbstractString)
    normalized_path = normpath(abspath(path))
    normalized_default = normpath(abspath(DEFAULT_OUTPUT))
    normalized_path == normalized_default && return true
    return ispath(normalized_path) && ispath(normalized_default) &&
        realpath(normalized_path) == realpath(normalized_default)
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    output_explicit = false
    profile = :smoke
    replications = nothing
    execute = false
    allow_heavy = false
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            output_explicit = true
            index += 2
        elseif arg == "--profile"
            index < length(args) || error("--profile requires a value")
            profile = Symbol(args[index + 1])
            profile in (:smoke, :pilot, :calibration) ||
                error("--profile must be smoke, pilot, or calibration")
            index += 2
        elseif arg == "--replications"
            index < length(args) || error("--replications requires a value")
            replications = parse(Int, args[index + 1])
            replications >= 1 || error("--replications must be positive")
            index += 2
        elseif arg == "--execute"
            execute = true
            index += 1
        elseif arg == "--allow-heavy"
            allow_heavy = true
            index += 1
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    config = profile_config(profile)
    requested_replications = replications === nothing ?
        config.default_replications : replications
    if execute
        output_explicit || error(
            "--execute requires an explicit --output path so the deterministic fixture is not overwritten",
        )
        !resolves_to_default_output(output) || error(
            "--execute output must not resolve to the deterministic fixture; choose a separate result path",
        )
        profile === :smoke || FULL_GATE_SCORER_IMPLEMENTED || error(
            "pilot/calibration MCMC is blocked until the declared full gate scorer is implemented",
        )
        heavy = profile !== :smoke || requested_replications > 1
        heavy && !allow_heavy && error(
            "executed pilot/calibration or multi-replication MCMC requires --allow-heavy",
        )
    end
    return (;
        output,
        output_explicit,
        profile,
        requested_replications,
        execute,
        allow_heavy,
    )
end

function profile_config(profile::Symbol)
    if profile === :smoke
        return (;
            n_persons = 12,
            n_items = 4,
            n_raters = 4,
            n_categories = 4,
            default_replications = 1,
            sampler = (;
                sampler_contract_id = :smoke_wiring_v1,
                backend = :advancedhmc,
                sampler = :nuts,
                chains = 1,
                warmup = 8,
                draws = 8,
                step_size = 0.03,
                target_accept = 0.8,
                max_depth = 4,
                max_energy_error = 1000.0,
                metric = :unit,
                ad_backend = :ForwardDiff,
                init_jitter = 0.0,
                split_chains = false,
                rhat_threshold = 1.01,
                ess_threshold = 4.0,
                evidence_status = :wiring_only_not_recovery_evidence,
            ),
        )
    elseif profile === :pilot
        return (;
            n_persons = 50,
            n_items = 8,
            n_raters = 6,
            n_categories = 4,
            default_replications = 30,
            sampler = (;
                sampler_contract_id = :pilot_evaluation_fixed_v1,
                backend = :advancedhmc,
                sampler = :nuts,
                chains = 4,
                warmup = 500,
                draws = 500,
                step_size = 0.02,
                target_accept = 0.9,
                max_depth = 10,
                max_energy_error = 1000.0,
                metric = :diagonal,
                ad_backend = :ForwardDiff,
                init_jitter = 0.05,
                split_chains = true,
                rhat_threshold = 1.01,
                ess_threshold = 400.0,
                evidence_status = :threshold_debugging_not_release_evidence,
            ),
        )
    end
    return (;
        # Hold sample size fixed from threshold-setting pilot to evaluation so
        # the evaluation changes replication count, not two axes at once.
        n_persons = 50,
        n_items = 8,
        n_raters = 6,
        n_categories = 4,
        default_replications = 50,
        sampler = (;
            sampler_contract_id = :pilot_evaluation_fixed_v1,
            backend = :advancedhmc,
            sampler = :nuts,
            chains = 4,
            warmup = 500,
            draws = 500,
            step_size = 0.02,
            target_accept = 0.9,
            max_depth = 10,
            max_energy_error = 1000.0,
            metric = :diagonal,
            ad_backend = :ForwardDiff,
            init_jitter = 0.05,
            split_chains = true,
            rhat_threshold = 1.01,
            ess_threshold = 400.0,
            evidence_status = :calibration_candidate_requires_scoring_review,
        ),
    )
end

function seed_namespace(profile::Symbol)
    if profile === :smoke
        return (name = :smoke_wiring,
            offset = SEED_NAMESPACE_OFFSETS.smoke_wiring)
    elseif profile === :pilot
        return (name = :pilot_threshold,
            offset = SEED_NAMESPACE_OFFSETS.pilot_threshold)
    end
    return (name = :calibration_evaluation,
        offset = SEED_NAMESPACE_OFFSETS.calibration_evaluation)
end

function replication_seeds(profile::Symbol, replication::Int, cell_index::Int,
        family::Symbol)
    namespace = seed_namespace(profile)
    family_index = something(findfirst(==(family), FAMILIES), 0)
    replication_offset = 100_000replication + 1_000cell_index
    return (;
        namespace = namespace.name,
        skeleton = BASE_SKELETON_SEED + namespace.offset + replication_offset,
        simulation = BASE_SIMULATION_SEED + namespace.offset + replication_offset,
        sampler = BASE_SAMPLER_SEED + namespace.offset + replication_offset +
            family_index,
    )
end

function project_version()
    project = TOML.parsefile(joinpath(ROOT, "Project.toml"))
    return String(project["version"])
end

file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))

portable_path(path::AbstractString) = replace(String(path), '\\' => '/')

function portable_json_hash(value)
    io = IOBuffer()
    write_canonical_json(io, value)
    return bytes2hex(sha256(take!(io)))
end

function package_runtime_provenance()
    source_rows = NamedTuple[]
    source_root = joinpath(ROOT, "src")
    for (directory, _, files) in walkdir(source_root)
        for file in sort(files)
            endswith(file, ".jl") || continue
            path = joinpath(directory, file)
            push!(source_rows, (;
                path = portable_path(relpath(path, ROOT)),
                sha256 = file_sha256(path),
            ))
        end
    end
    sort!(source_rows; by = row -> row.path)
    manifest_path = joinpath(ROOT, "Manifest.toml")
    return (;
        julia_version = string(VERSION),
        project_toml_sha256 = file_sha256(joinpath(ROOT, "Project.toml")),
        manifest_toml_sha256 = isfile(manifest_path) ?
            file_sha256(manifest_path) : nothing,
        source_files = source_rows,
        source_tree_sha256 = portable_json_hash(source_rows),
        immutable_vcs_revision_verified = false,
        clean_worktree_verified = false,
        raw_draw_cache_identity_verified = false,
        interpretation =
            :runtime_and_source_snapshot_not_external_chronology_attestation,
    )
end

function plan_reference()
    isfile(PLAN_PATH) || error(
        "missing prerequisite plan artifact: $(portable_path(relpath(PLAN_PATH, ROOT)))",
    )
    parsed = JSON3.read(read(PLAN_PATH, String))
    schema = String(parsed[:schema])
    schema == "bayesianmgmfrm.existing_api_design_robustness_plan.v1" ||
        error("unexpected prerequisite plan schema: $schema")
    return (;
        path = portable_path(relpath(PLAN_PATH, ROOT)),
        sha256 = file_sha256(PLAN_PATH),
        schema,
        summary_passed = Bool(parsed[:summary][:passed]),
        paired_known_truth_recovery_completed =
            Bool(parsed[:summary][:paired_known_truth_recovery_completed]),
    )
end

function padded_label(prefix::AbstractString, index::Int, n::Int)
    width = max(2, ndigits(n))
    return prefix * lpad(string(index), width, '0')
end

function standardized_sequence(n::Int)
    n >= 2 || return zeros(Float64, n)
    values = collect(range(-1.0, 1.0; length = n))
    values .-= arithmetic_mean(values)
    values ./= sample_standard_deviation(values)
    return values
end

function secondary_dimension_sequence(n::Int)
    values = [sin(2pi * (index - 1) / n) for index in 1:n]
    values .-= arithmetic_mean(values)
    scale = sample_standard_deviation(values)
    scale > 0 || return reverse(standardized_sequence(n))
    return values ./ scale
end

function even_selection(values::AbstractVector{Int}, count::Int)
    count == 0 && return Int[]
    count <= length(values) || error("cannot select $count from $(length(values)) values")
    count == 1 && return [values[cld(length(values), 2)]]
    count == length(values) && return collect(values)
    indices = unique(round.(Int, range(1, length(values); length = count)))
    length(indices) == count || error("even selection did not retain the requested count")
    return collect(values[indices])
end

function target_rows(config)
    abilities = standardized_sequence(config.n_persons)
    rows = NamedTuple[]
    target_index = 0
    for person_index in 1:config.n_persons, item_index in 1:config.n_items
        target_index += 1
        push!(rows, (;
            target_index,
            person_index,
            person = padded_label("E", person_index, config.n_persons),
            item_index,
            item = padded_label("I", item_index, config.n_items),
            assignment_ability = abilities[person_index],
        ))
    end
    return rows
end

component_seed(skeleton_seed::Int, component::Int, index::Int = 0) =
    skeleton_seed + 1_000_003component + 10_007index

event_identity(row) = (target_index = row.target_index, rater_index = row.rater_index)

function stratified_random_selection(values::AbstractVector{Int}, count::Int,
        rng::AbstractRNG)
    count == 0 && return Int[]
    count <= length(values) || error("cannot select $count from $(length(values)) values")
    count == length(values) && return collect(values)
    selected = Int[]
    for stratum in 1:count
        first_index = fld((stratum - 1) * length(values), count) + 1
        last_index = fld(stratum * length(values), count)
        first_index <= last_index || error("empty selection stratum")
        push!(selected, values[rand(rng, first_index:last_index)])
    end
    return selected
end

function constrained_full_range_selection(targets, count::Int, rng::AbstractRNG)
    count == 0 && return Int[]
    count <= length(targets) || error(
        "cannot select $count full-range targets from $(length(targets)) targets",
    )
    ordered = sort(collect(eachindex(targets)); by = index ->
        (targets[index].assignment_ability,
            targets[index].item_index,
            targets[index].target_index))
    count == 1 && return [rand(rng, ordered)]

    ability_values = [target.assignment_ability for target in targets]
    ability_minimum, ability_maximum = extrema(ability_values)
    ability_range = ability_maximum - ability_minimum
    item_range = maximum(target.item_index for target in targets) -
        minimum(target.item_index for target in targets)
    ability_range > 0 || error("full-range selection requires ability variation")
    item_range > 0 || error("full-range selection requires item variation")

    # Select a seeded pair from opposite ability-by-item corners. The explicit
    # ratio filter makes the >= .75 support guarantee part of construction,
    # rather than something that merely tends to hold for large samples.
    low_ability_cut = ability_minimum + 0.25ability_range
    high_ability_cut = ability_maximum - 0.25ability_range
    item_minimum = minimum(target.item_index for target in targets)
    item_maximum = maximum(target.item_index for target in targets)
    low_item_cut = item_minimum + 0.25item_range
    high_item_cut = item_maximum - 0.25item_range
    corner_pairs = Tuple{Int,Int}[]
    orientations = (
        (low_item = true, high_item = true),
        (low_item = false, high_item = false),
    )
    for orientation in orientations
        low_candidates = [index for index in eachindex(targets)
            if targets[index].assignment_ability <= low_ability_cut &&
                (orientation.low_item ?
                    targets[index].item_index <= low_item_cut :
                    targets[index].item_index >= high_item_cut)]
        high_candidates = [index for index in eachindex(targets)
            if targets[index].assignment_ability >= high_ability_cut &&
                (orientation.high_item ?
                    targets[index].item_index >= high_item_cut :
                    targets[index].item_index <= low_item_cut)]
        for low in low_candidates, high in high_candidates
            ability_ratio = abs(targets[high].assignment_ability -
                targets[low].assignment_ability) / ability_range
            item_ratio = abs(targets[high].item_index -
                targets[low].item_index) / item_range
            ability_ratio >= 0.75 && item_ratio >= 0.75 &&
                push!(corner_pairs, (low, high))
        end
    end
    isempty(corner_pairs) && error(
        "requested full-range count $count cannot realize both ability and item support",
    )
    first_index, second_index = rand(rng, corner_pairs)
    selected = [first_index, second_index]
    remaining_count = count - length(selected)
    if remaining_count > 0
        remaining = [index for index in ordered if !(index in selected)]
        append!(selected,
            stratified_random_selection(remaining, remaining_count, rng))
    end
    return sort(selected)
end

function common_linking_indices(targets, cell, skeleton_seed::Int)
    count = round(Int, cell.common_linking_fraction * length(targets))
    cell.common_linking_fraction > 0 && (count = max(count, 1))
    rng = MersenneTwister(component_seed(skeleton_seed, 1))
    candidates = if cell.common_linking_support === :narrow_middle
        sorted = sort(collect(eachindex(targets));
            by = index -> (abs(targets[index].assignment_ability),
                targets[index].item_index, targets[index].target_index))
        support_count = max(count, cld(length(targets), 3))
        support = sorted[1:min(support_count, length(sorted))]
        shuffle!(rng, support)
        support
    else
        sort(collect(eachindex(targets));
            by = index -> (targets[index].assignment_ability,
                targets[index].item_index, targets[index].target_index))
    end
    selected = cell.common_linking_support === :narrow_middle ?
        candidates[1:count] : constrained_full_range_selection(targets, count, rng)
    return sort(selected)
end

function balanced_random_labels(n::Int, n_raters::Int, rng::AbstractRNG)
    labels = [mod(index - 1, n_raters) + 1 for index in 1:n]
    shuffle!(rng, labels)
    return labels
end

function primary_rater_assignments(targets, cell, config, skeleton_seed::Int)
    rng = MersenneTwister(component_seed(skeleton_seed, 2))
    assignments = zeros(Int, length(targets))
    label_permutation = collect(1:config.n_raters)
    if cell.assignment === :balanced_random
        assignments .= balanced_random_labels(length(targets), config.n_raters, rng)
    elseif cell.assignment === :ability_stratified_balanced
        n_strata = min(config.n_raters, config.n_persons)
        for stratum in 1:n_strata
            indices = [index for index in eachindex(targets) if
                min(cld(targets[index].person_index * n_strata, config.n_persons),
                    n_strata) == stratum]
            assignments[indices] .=
                balanced_random_labels(length(indices), config.n_raters, rng)
        end
    else
        if cell.assignment === :ability_informed_nested
            shuffle!(rng, label_permutation)
        elseif cell.assignment === :severity_opposed
            reverse!(label_permutation)
        end
        for (index, target) in pairs(targets)
            stratum = min(
                cld(target.person_index * config.n_raters, config.n_persons),
                config.n_raters,
            )
            assignments[index] = label_permutation[stratum]
        end
    end
    all(>(0), assignments) || error("primary rater assignment left unassigned targets")
    return (;
        assignments,
        rater_label_permutation = label_permutation,
        assignment_sha256 = portable_json_hash(assignments),
    )
end

function fixed_total_drop_indices(targets, common_set::Set{Int}, required::Int,
        config, skeleton_seed::Int)
    required == 0 && return Int[]
    candidates = [index for index in eachindex(targets) if !(index in common_set)]
    required <= length(candidates) || error(
        "fixed-total linking requires $required displaced targets but only $(length(candidates)) are available",
    )
    order = copy(candidates)
    shuffle!(MersenneTwister(component_seed(skeleton_seed, 3)), order)
    person_remaining = fill(config.n_items, config.n_persons)
    item_remaining = fill(config.n_persons, config.n_items)
    dropped = Int[]
    for index in order
        target = targets[index]
        person_remaining[target.person_index] > 2 || continue
        item_remaining[target.item_index] > config.n_raters || continue
        push!(dropped, index)
        person_remaining[target.person_index] -= 1
        item_remaining[target.item_index] -= 1
        length(dropped) == required && break
    end
    length(dropped) == required || error(
        "fixed-total displacement could place only $(length(dropped)) of $required targets while retaining coverage",
    )
    return sort(dropped)
end

function randomized_event_ranks(events, seed::Int)
    shuffled = copy(events)
    shuffle!(MersenneTwister(seed), shuffled)
    return Dict(event_identity(row) => rank for (rank, row) in pairs(shuffled))
end

function base_order(events, cell, rater_index::Int, skeleton_seed::Int)
    seed = component_seed(skeleton_seed, 4, rater_index)
    if cell.presentation_order === :random
        ordered = copy(events)
        shuffle!(MersenneTwister(seed), ordered)
        return ordered
    elseif cell.presentation_order === :high_to_low
        ranks = randomized_event_ranks(events, seed)
        return sort(events; by = row -> (-row.assignment_ability,
            ranks[event_identity(row)]))
    elseif cell.presentation_order === :low_to_high
        ranks = randomized_event_ranks(events, seed)
        return sort(events; by = row -> (row.assignment_ability,
            ranks[event_identity(row)]))
    end
    item_order = sort(unique(row.item_index for row in events))
    shuffle!(MersenneTwister(seed), item_order)
    item_rank = Dict(item => rank for (rank, item) in pairs(item_order))
    ranks = randomized_event_ranks(events, component_seed(seed, 1))
    return sort(events; by = row -> (item_rank[row.item_index],
        -row.assignment_ability, ranks[event_identity(row)]))
end

function place_common_linking(events, cell, rater_index::Int, skeleton_seed::Int)
    ordered = base_order(events, cell, rater_index, skeleton_seed)
    cell.common_linking_placement === :not_applicable && return ordered
    common = [row for row in ordered if row.is_common_linking_target]
    ordinary = [row for row in ordered if !row.is_common_linking_target]
    isempty(common) && return ordered
    cell.common_linking_placement === :early_only && return vcat(common, ordinary)
    final_positions = Set(even_selection(collect(1:length(ordered)), length(common)))
    out = NamedTuple[]
    common_index = 1
    ordinary_index = 1
    for position in 1:length(ordered)
        if position in final_positions
            push!(out, common[common_index])
            common_index += 1
        else
            push!(out, ordinary[ordinary_index])
            ordinary_index += 1
        end
    end
    return out
end

function materialize_events(cell, config; skeleton_seed::Int)
    targets = target_rows(config)
    common_vector = common_linking_indices(targets, cell, skeleton_seed)
    common_set = Set(common_vector)
    primary = primary_rater_assignments(targets, cell, config, skeleton_seed)
    secondary_rng = MersenneTwister(component_seed(skeleton_seed, 5))
    secondary_offsets = cell.routine_ratings_per_target == 2 ?
        rand(secondary_rng, 1:(config.n_raters - 1), length(targets)) : Int[]
    extra_per_anchor = config.n_raters - cell.routine_ratings_per_target
    extra_per_anchor >= 0 || error("routine ratings exceed the number of raters")
    n_displaced = cell.budget_policy === :fixed_total_target_displacement ?
        length(common_set) * extra_per_anchor : 0
    dropped_vector = fixed_total_drop_indices(
        targets,
        common_set,
        n_displaced,
        config,
        skeleton_seed,
    )
    dropped = Set(dropped_vector)

    raw_events = NamedTuple[]
    for (index, target) in pairs(targets)
        index in dropped && continue
        primary_rater = primary.assignments[index]
        routine = if cell.routine_ratings_per_target == 2
            secondary = mod(primary_rater + secondary_offsets[index] - 1,
                config.n_raters) + 1
            (primary_rater, secondary)
        else
            (primary_rater,)
        end
        raters = index in common_set ? collect(1:config.n_raters) : collect(routine)
        for rater_index in raters
            push!(raw_events, merge(target, (;
                rater_index,
                rater = padded_label("R", rater_index, config.n_raters),
                primary_rater,
                is_common_linking_target = index in common_set,
                is_routine_secondary =
                    length(routine) == 2 && rater_index == routine[2],
            )))
        end
    end

    ordered_events = NamedTuple[]
    for rater_index in 1:config.n_raters
        rater_events = [row for row in raw_events if row.rater_index == rater_index]
        ordered = place_common_linking(
            rater_events,
            cell,
            rater_index,
            skeleton_seed,
        )
        load = length(ordered)
        for (position, row) in pairs(ordered)
            fraction = load == 1 ? 0.5 : (position - 1) / (load - 1)
            occasion = fraction < 1 / 3 ? "early" :
                (fraction < 2 / 3 ? "middle" : "late")
            push!(ordered_events, merge(row, (;
                rater_position = position,
                rater_position_fraction = fraction,
                occasion,
            )))
        end
    end
    sort!(ordered_events; by = row -> (row.rater_index, row.rater_position))
    return (;
        events = ordered_events,
        targets,
        common_linking_indices = common_vector,
        dropped_indices = dropped_vector,
        skeleton_seed,
        skeleton_resampling = (;
            primary_rater_assignment = true,
            rater_label_permutation = primary.rater_label_permutation,
            routine_secondary_rater_assignment =
                cell.routine_ratings_per_target == 2,
            common_linking_target_selection = !isempty(common_vector),
            common_linking_target_selection_method =
                isempty(common_vector) ? :not_applicable :
                (cell.common_linking_support === :full_ability_and_item_range ?
                    :seeded_constrained_ability_by_item_corner_support :
                    :seeded_narrow_middle_support),
            fixed_total_displaced_target_selection = n_displaced > 0,
            within_rater_order = true,
        ),
    )
end

function table_from_events(events, scores)
    length(events) == length(scores) || error("score/event length mismatch")
    return (;
        examinee = [row.person for row in events],
        rater = [row.rater for row in events],
        item = [row.item for row in events],
        score = collect(Int, scores),
        occasion = [row.occasion for row in events],
    )
end

function placeholder_scores(n::Int, n_categories::Int)
    return [mod(index - 1, n_categories) for index in 1:n]
end

function facet_data(table)
    return BayesianMGMFRM.FacetData(
        table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        occasion = :occasion,
    )
end

function fixed_q_matrix(n_items::Int)
    q = falses(n_items, 2)
    for item in 1:n_items
        q[item, isodd(item) ? 1 : 2] = true
    end
    return q
end

function family_spec(data, family::Symbol, config)
    family === :mfrm && return BayesianMGMFRM.mfrm_spec(data)
    family === :guarded_scalar_gmfrm && return BayesianMGMFRM.mfrm_spec(
        data;
        family = :gmfrm,
        discrimination = :rater,
    )
    family === :guarded_fixed_q_mgmfrm && return BayesianMGMFRM.mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix = fixed_q_matrix(config.n_items),
    )
    error("unknown family: $family")
end

function family_design(spec, family::Symbol)
    return BayesianMGMFRM.getdesign(spec; preview = family !== :mfrm)
end

function step_values!(values, block::UnitRange{Int}, free_per_level::Int,
        threshold_spacing::Symbol)
    free_per_level == 0 && return values
    multiplier = threshold_spacing === :compressed ? 0.50 :
        (threshold_spacing === :reference ? 1.0 :
            (threshold_spacing === :wide ? 1.75 :
                error("unknown threshold spacing: $threshold_spacing")))
    for (offset, index) in pairs(block)
        step = mod(offset - 1, free_per_level) + 1
        values[index] = multiplier * (-0.30 + 0.22 * (step - 1))
    end
    return values
end

function mfrm_truth(design, cell, config)
    direct = zeros(Float64, length(design.parameter_names))
    direct[design.blocks[:person]] .=
        cell.ability_sd .* standardized_sequence(config.n_persons)
    severity = cell.rater_severity_sd .* standardized_sequence(config.n_raters)
    direct[design.blocks[:rater]] .= severity[2:end] .- severity[1]
    item_values = 0.35 .* standardized_sequence(config.n_items)
    direct[design.blocks[:item]] .= item_values[2:end] .- item_values[1]
    free_per_item = max(config.n_categories - 2, 0)
    step_values!(direct, design.blocks[:thresholds], free_per_item,
        cell.threshold_spacing)
    return (; raw = nothing, direct)
end

function gmfrm_truth(design, cell, config)
    blueprint = BayesianMGMFRM._gmfrm_source_unconstrained_blueprint(design)
    raw = zeros(Float64, blueprint.n_parameters)
    blocks = blueprint.blocks
    raw[blocks[:person]] .=
        cell.ability_sd .* standardized_sequence(config.n_persons)
    raw[blocks[:rater]] .=
        cell.rater_severity_sd .* standardized_sequence(config.n_raters)
    item_values = 0.35 .* standardized_sequence(config.n_items)
    raw[blocks[:item_free]] .= item_values[1:(end - 1)]
    log_item = 0.12 .* standardized_sequence(config.n_items)
    raw[blocks[:log_item_discrimination_free]] .= log_item[1:(end - 1)]
    raw[blocks[:log_rater_consistency]] .=
        0.10 .* standardized_sequence(config.n_raters)
    step_values!(raw, blocks[:rater_steps], max(config.n_categories - 2, 0),
        cell.threshold_spacing)
    direct = BayesianMGMFRM._gmfrm_source_constrained_params_from_unconstrained(
        design,
        raw,
    )
    return (; raw, direct)
end

function mgmfrm_truth(design, cell, config)
    blueprint = BayesianMGMFRM._mgmfrm_source_unconstrained_blueprint(design)
    raw = zeros(Float64, blueprint.n_parameters)
    blocks = blueprint.blocks
    first_dimension = cell.ability_sd .* standardized_sequence(config.n_persons)
    second_dimension = cell.ability_sd .* secondary_dimension_sequence(config.n_persons)
    person_values = Float64[]
    for person in 1:config.n_persons
        push!(person_values, first_dimension[person], second_dimension[person])
    end
    raw[blocks[:person]] .= person_values
    severity = cell.rater_severity_sd .* standardized_sequence(config.n_raters)
    raw[blocks[:rater_free]] .= severity[1:(end - 1)]
    raw[blocks[:item]] .= 0.35 .* standardized_sequence(config.n_items)
    loading_count = length(blocks[:log_item_dimension_discrimination])
    raw[blocks[:log_item_dimension_discrimination]] .=
        0.08 .* standardized_sequence(loading_count)
    log_consistency = 0.10 .* standardized_sequence(config.n_raters)
    raw[blocks[:log_rater_consistency_free]] .= log_consistency[1:(end - 1)]
    step_values!(raw, blocks[:item_steps], max(config.n_categories - 2, 0),
        cell.threshold_spacing)
    direct = BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
        design,
        raw,
    )
    return (; raw, direct)
end

function known_truth(design, family::Symbol, cell, config)
    family === :mfrm && return mfrm_truth(design, cell, config)
    family === :guarded_scalar_gmfrm && return gmfrm_truth(design, cell, config)
    return mgmfrm_truth(design, cell, config)
end

function static_probabilities(design, family::Symbol, direct_truth)
    draws = reshape(direct_truth, 1, :)
    array = if family === :mfrm
        BayesianMGMFRM.predictive_probabilities(design, draws)
    elseif family === :guarded_scalar_gmfrm
        BayesianMGMFRM._gmfrm_predictive_probabilities_direct(design, draws)
    else
        BayesianMGMFRM._mgmfrm_predictive_probabilities_direct(design, draws)
    end
    return Matrix(dropdims(array; dims = 1))
end

function order_effect_probabilities(static, events, config)
    out = similar(static)
    for row in axes(static, 1)
        event = events[row]
        rater_multiplier = config.n_raters == 1 ? 1.0 :
            0.85 + 0.30 * (event.rater_index - 1) / (config.n_raters - 1)
        location_shift = -ORDER_EFFECT_SLOPE *
            (event.rater_position_fraction - 0.5) * rater_multiplier
        logweights = [log(static[row, category]) +
            (category - 1) * location_shift for category in axes(static, 2)]
        maxlog = maximum(logweights)
        weights = exp.(logweights .- maxlog)
        out[row, :] .= weights ./ sum(weights)
    end
    return out
end

function sample_scores(probabilities, uniforms, category_levels)
    scores = Int[]
    for row in axes(probabilities, 1)
        cumulative = 0.0
        selected = lastindex(category_levels)
        for category in axes(probabilities, 2)
            cumulative += probabilities[row, category]
            if uniforms[row] <= cumulative
                selected = category
                break
            end
        end
        push!(scores, category_levels[selected])
    end
    return scores
end

function safe_correlation(x, y)
    length(x) >= 2 || return 0.0
    length(x) == length(y) || throw(ArgumentError(
        "correlation inputs must have equal lengths",
    ))
    x_values = Float64.(collect(x))
    y_values = Float64.(collect(y))
    x_sd = sample_standard_deviation(x_values)
    y_sd = sample_standard_deviation(y_values)
    x_scale = max(1.0, maximum(abs, x_values))
    y_scale = max(1.0, maximum(abs, y_values))
    tolerance = sqrt(eps(Float64))
    isfinite(x_sd) && isfinite(y_sd) || return 0.0
    x_sd > tolerance * x_scale && y_sd > tolerance * y_scale || return 0.0
    x_mean = arithmetic_mean(x_values)
    y_mean = arithmetic_mean(y_values)
    covariance = sum(
        (x_value - x_mean) * (y_value - y_mean)
        for (x_value, y_value) in zip(x_values, y_values)
    ) / (length(x_values) - 1)
    return covariance / (x_sd * y_sd)
end

function order_metric_rows(values, events, config)
    rows = NamedTuple[]
    for rater in 1:config.n_raters
        indices = [index for index in eachindex(events)
            if events[index].rater_index == rater]
        rater_values = values[indices]
        early = [values[index] for index in indices
            if events[index].occasion == "early"]
        late = [values[index] for index in indices
            if events[index].occasion == "late"]
        early_mean = isempty(early) ? missing : arithmetic_mean(early)
        late_mean = isempty(late) ? missing : arithmetic_mean(late)
        push!(rows, (;
            rater = padded_label("R", rater, config.n_raters),
            rater_index = rater,
            n_rating_events = length(indices),
            value_position_correlation = safe_correlation(
                rater_values,
                [events[index].rater_position_fraction for index in indices],
            ),
            early_mean_value = early_mean,
            late_mean_value = late_mean,
            late_minus_early_mean_value =
                ismissing(early_mean) || ismissing(late_mean) ? missing :
                late_mean - early_mean,
        ))
    end
    return rows
end

function mgmfrm_order_diagnostics(events, design, truth, family, config)
    family === :guarded_fixed_q_mgmfrm || return nothing
    dimensions = design.spec.dimensions
    person_block = design.blocks[:person]
    dimension_rows = NamedTuple[]
    for dimension in 1:dimensions
        values = [truth.direct[person_block[
            (event.person_index - 1) * dimensions + dimension]] for event in events]
        early = [values[index] for index in eachindex(events)
            if events[index].occasion == "early"]
        late = [values[index] for index in eachindex(events)
            if events[index].occasion == "late"]
        push!(dimension_rows, (;
            dimension,
            source = :dimension_specific_direct_truth,
            pooled_value_position_correlation = safe_correlation(
                values,
                [event.rater_position_fraction for event in events],
            ),
            pooled_late_minus_early_mean_value =
                arithmetic_mean(late) - arithmetic_mean(early),
            by_rater = order_metric_rows(values, events, config),
        ))
    end
    index_by_name = BayesianMGMFRM._parameter_index_map(design)
    active_values = [BayesianMGMFRM._mgmfrm_source_row_terms(
        design,
        index_by_name,
        truth.direct,
        row,
    ).ability_score for row in eachindex(events)]
    active_early = [active_values[index] for index in eachindex(events)
        if events[index].occasion == "early"]
    active_late = [active_values[index] for index in eachindex(events)
        if events[index].occasion == "late"]
    return (;
        dimension_specific = dimension_rows,
        q_active_source = (;
            source = :loading_weighted_q_active_ability_truth,
            pooled_value_position_correlation = safe_correlation(
                active_values,
                [event.rater_position_fraction for event in events],
            ),
            pooled_late_minus_early_mean_value =
                arithmetic_mean(active_late) - arithmetic_mean(active_early),
            by_rater = order_metric_rows(active_values, events, config),
        ),
    )
end

function implied_rater_severity(design, truth, family, config)
    if family === :mfrm
        return vcat(0.0, collect(truth.direct[design.blocks[:rater]]))
    end
    return collect(truth.direct[design.blocks[:rater]])
end

function requested_vs_achieved_design_gate(materialized, cell, config, audit)
    events = materialized.events
    n_planned_targets = length(materialized.targets)
    n_common = length(materialized.common_linking_indices)
    common_events = [row for row in events if row.is_common_linking_target]
    placement_counts = [(occasion = occasion,
        n = count(row -> row.occasion == occasion, common_events))
        for occasion in ("early", "middle", "late")]
    common_abilities = [cell.ability_sd *
        materialized.targets[index].assignment_ability
        for index in materialized.common_linking_indices]
    common_items = [materialized.targets[index].item_index
        for index in materialized.common_linking_indices]
    all_abilities = [cell.ability_sd * row.assignment_ability
        for row in materialized.targets]
    expected_events = if cell.budget_policy === :baseline_double_rating
        2n_planned_targets
    elseif cell.budget_policy === :additive
        n_planned_targets + n_common *
            (config.n_raters - cell.routine_ratings_per_target)
    else
        n_planned_targets
    end
    requested_common_count = cell.common_linking_fraction > 0 ?
        max(1, round(Int, cell.common_linking_fraction * n_planned_targets)) : 0
    common_fraction_count_passed = n_common == requested_common_count
    support_ratio = isempty(common_abilities) ? missing :
        (maximum(common_abilities) - minimum(common_abilities)) /
        (maximum(all_abilities) - minimum(all_abilities))
    item_support_ratio = isempty(common_items) ? missing :
        (config.n_items == 1 ? 1.0 :
            (maximum(common_items) - minimum(common_items)) /
            (config.n_items - 1))
    support_passed = if cell.common_linking_fraction == 0
        true
    elseif cell.common_linking_support === :narrow_middle
        !ismissing(support_ratio) && support_ratio <= 0.50
    else
        length(common_abilities) >= 2 && !ismissing(support_ratio) &&
            support_ratio >= 0.75 && !ismissing(item_support_ratio) &&
            item_support_ratio >= 0.75
    end
    placement_passed = if cell.common_linking_fraction == 0
        true
    elseif cell.common_linking_placement === :early_only
        !isempty(common_events) && all(rater -> begin
            rater_events = [row for row in events if row.rater_index == rater]
            common_positions = [row.rater_position for row in rater_events
                if row.is_common_linking_target]
            ordinary_positions = [row.rater_position for row in rater_events
                if !row.is_common_linking_target]
            !isempty(common_positions) && (isempty(ordinary_positions) ||
                maximum(common_positions) < minimum(ordinary_positions))
        end, 1:config.n_raters)
    elseif cell.common_linking_placement === :distributed
        all(row.n > 0 for row in placement_counts)
    else
        true
    end
    linking_passed = audit.summary.rater_linking_status !== :disconnected
    passed = length(events) == expected_events &&
        common_fraction_count_passed && support_passed && placement_passed &&
        linking_passed
    return (;
        expected_events,
        common_abilities,
        common_items,
        placement_counts,
        support_ratio,
        item_support_ratio,
        record = (;
            requested_common_linking_target_count = requested_common_count,
            achieved_common_linking_target_count = n_common,
            common_linking_fraction_count_passed = common_fraction_count_passed,
            requested_common_linking_support = cell.common_linking_support,
            achieved_ability_range_ratio = support_ratio,
            achieved_item_range_ratio = item_support_ratio,
            support_passed,
            requested_common_linking_placement = cell.common_linking_placement,
            placement_passed,
            minimum_shared_person_item_units_requested = 2,
            rater_linking_passed = linking_passed,
            rating_budget_passed = length(events) == expected_events,
            passed,
            status = passed ? :resolved_fit_eligible : :underresolved_planned_only,
            fit_eligible = passed,
        ),
    )
end

function design_metrics(materialized, cell, config, data, audit,
        design, truth, family)
    events = materialized.events
    target_raters = Dict{Int,Set{Int}}()
    for event in events
        push!(get!(target_raters, event.target_index, Set{Int}()), event.rater_index)
    end
    n_multi = count(raters -> length(raters) >= 2, values(target_raters))
    n_observed_targets = length(target_raters)
    n_planned_targets = length(materialized.targets)
    n_common = length(materialized.common_linking_indices)
    achieved_gate = requested_vs_achieved_design_gate(
        materialized, cell, config, audit)
    common_events = [row for row in events if row.is_common_linking_target]
    placement_counts = achieved_gate.placement_counts
    loads = [count(row -> row.rater_index == rater, events)
        for rater in 1:config.n_raters]
    common_abilities = achieved_gate.common_abilities
    common_items = achieved_gate.common_items
    common_ratings = length(common_events)
    severities = implied_rater_severity(design, truth, family, config)
    rater_sequence_rows = NamedTuple[]
    for rater in 1:config.n_raters
        rater_events = [row for row in events if row.rater_index == rater]
        early = [cell.ability_sd * row.assignment_ability for row in rater_events
            if row.occasion == "early"]
        late = [cell.ability_sd * row.assignment_ability for row in rater_events
            if row.occasion == "late"]
        early_mean = isempty(early) ? missing : arithmetic_mean(early)
        late_mean = isempty(late) ? missing : arithmetic_mean(late)
        push!(rater_sequence_rows, (;
            rater = padded_label("R", rater, config.n_raters),
            rater_index = rater,
            n_rating_events = length(rater_events),
            severity_truth = severities[rater],
            mean_assigned_ability = arithmetic_mean(
                cell.ability_sd * row.assignment_ability for row in rater_events),
            ability_position_correlation = safe_correlation(
                [cell.ability_sd * row.assignment_ability for row in rater_events],
                [row.rater_position_fraction for row in rater_events],
            ),
            early_mean_ability = early_mean,
            late_mean_ability = late_mean,
            late_minus_early_mean_ability =
                ismissing(early_mean) || ismissing(late_mean) ? missing :
                late_mean - early_mean,
        ))
    end
    rater_correlations = [row.ability_position_correlation
        for row in rater_sequence_rows]
    rater_mean_abilities = [row.mean_assigned_ability for row in rater_sequence_rows]
    pooled_early = [cell.ability_sd * row.assignment_ability for row in events
        if row.occasion == "early"]
    pooled_late = [cell.ability_sd * row.assignment_ability for row in events
        if row.occasion == "late"]
    expected_events = achieved_gate.expected_events
    budget_implementation = cell.budget_policy === :fixed_total_target_displacement ?
        :fixed_total_target_displacement :
        (cell.budget_policy === :additive ? :additive_common_linking_ratings :
            cell.budget_policy)
    support_ratio = achieved_gate.support_ratio
    item_support_ratio = achieved_gate.item_support_ratio
    mgmfrm_diagnostics = mgmfrm_order_diagnostics(
        events, design, truth, family, config)
    return (;
        planned_target_denominator = n_planned_targets,
        observed_target_denominator = n_observed_targets,
        n_planned_person_item_targets = n_planned_targets,
        n_observed_person_item_targets = n_observed_targets,
        observed_target_coverage = n_observed_targets / n_planned_targets,
        n_rating_events = length(events),
        expected_rating_events = expected_events,
        rating_budget_accounting_passed = length(events) == expected_events,
        rating_budget_policy = cell.budget_policy,
        rating_budget_implementation = budget_implementation,
        rating_budget_delta_vs_one_rating_per_planned_target =
            length(events) - n_planned_targets,
        n_displaced_operational_targets = length(materialized.dropped_indices),
        dropped_target_fraction_of_planned =
            length(materialized.dropped_indices) / n_planned_targets,
        requested_common_linking_fraction = cell.common_linking_fraction,
        n_common_linking_targets = n_common,
        achieved_common_linking_fraction_planned_denominator =
            n_common / n_planned_targets,
        achieved_common_linking_fraction_observed_denominator =
            n_observed_targets == 0 ? 0.0 : n_common / n_observed_targets,
        achieved_multi_rated_target_fraction_planned_denominator =
            n_planned_targets == 0 ? 0.0 : n_multi / n_planned_targets,
        achieved_multi_rated_target_fraction_observed_denominator =
            n_observed_targets == 0 ? 0.0 : n_multi / n_observed_targets,
        n_multi_rated_targets = n_multi,
        common_linking_rating_burden =
            isempty(events) ? 0.0 : common_ratings / length(events),
        common_linking_ratings = common_ratings,
        common_linking_placement_counts = placement_counts,
        common_linking_placement_covers_all_terciles =
            all(row.n > 0 for row in placement_counts),
        controlled_benchmark_status = :not_materialized,
        n_controlled_benchmark_targets = 0,
        common_linking_targets_are_controlled_benchmarks = false,
        common_linking_support = cell.common_linking_support,
        common_linking_ability_minimum =
            isempty(common_abilities) ? missing : minimum(common_abilities),
        common_linking_ability_maximum =
            isempty(common_abilities) ? missing : maximum(common_abilities),
        common_linking_to_full_ability_range_ratio = support_ratio,
        common_linking_to_full_item_range_ratio = item_support_ratio,
        n_unique_common_linking_items = length(unique(common_items)),
        minimum_rater_load = minimum(loads),
        maximum_rater_load = maximum(loads),
        rater_load_cv = arithmetic_mean(loads) == 0 ? 0.0 :
            sample_standard_deviation(loads) / arithmetic_mean(loads),
        ability_position_correlation = safe_correlation(
            [cell.ability_sd * row.assignment_ability for row in events],
            [row.rater_position_fraction for row in events],
        ),
        ability_position_correlation_by_rater = rater_sequence_rows,
        mean_rater_ability_position_correlation =
            arithmetic_mean(rater_correlations),
        maximum_absolute_rater_ability_position_correlation =
            maximum(abs, rater_correlations),
        pooled_early_mean_ability = arithmetic_mean(pooled_early),
        pooled_late_mean_ability = arithmetic_mean(pooled_late),
        pooled_late_minus_early_mean_ability =
            arithmetic_mean(pooled_late) - arithmetic_mean(pooled_early),
        assigned_ability_rater_severity_correlation_event_weighted =
            safe_correlation(
                [cell.ability_sd * row.assignment_ability for row in events],
                [severities[row.rater_index] for row in events],
            ),
        mean_assigned_ability_rater_severity_correlation =
            safe_correlation(rater_mean_abilities, severities),
        n_rating_graph_components = audit.summary.n_rating_graph_components,
        rating_graph_status = audit.summary.rating_graph_status,
        n_rater_components = audit.summary.n_rater_components,
        rater_linking_status = audit.summary.rater_linking_status,
        minimum_shared_person_item_units =
            audit.anchor_linking.minimum_shared_units,
        assignment_warning_retained = audit.summary.nonignorable_assignment_flagged,
        occasion_recorded_not_modeled = audit.summary.optional_time_order_recorded,
        ability_metric_scale = :known_truth_ability_units,
        mgmfrm_order_diagnostics = mgmfrm_diagnostics,
        requested_vs_achieved = achieved_gate.record,
        data_n = data.n,
    )
end

function rejection_record(data, family, config)
    validation = BayesianMGMFRM.validate_design(data)
    audit = BayesianMGMFRM.rating_design_audit(data;
        unit = :person_item, min_shared_units = 2)
    rejected = false
    error_type = missing
    message = missing
    try
        family_spec(data, family, config)
    catch err
        rejected = true
        error_type = Symbol(nameof(typeof(err)))
        message = portable_error_message(err)
    end
    error_codes = Tuple(sort!(unique(issue.code for issue in validation.issues
        if issue.severity === :error)))
    passed = rejected && !validation.passed &&
        :rank_deficient_design in error_codes &&
        audit.summary.rater_linking_status === :disconnected
    return (;
        expected_prefit_rejection = true,
        passed,
        rejected,
        error_type,
        message,
        validation_passed = validation.passed,
        validation_error_codes = error_codes,
        rating_graph_status = audit.summary.rating_graph_status,
        rater_linking_status = audit.summary.rater_linking_status,
        fit_attempted = false,
    )
end

function truth_manifest(design, truth, family)
    raw_names = if family === :mfrm
        nothing
    elseif family === :guarded_scalar_gmfrm
        BayesianMGMFRM._gmfrm_source_unconstrained_blueprint(design).parameter_names
    else
        BayesianMGMFRM._mgmfrm_source_unconstrained_blueprint(design).parameter_names
    end
    direct_record = (;
        parameter_names = design.parameter_names,
        values = truth.direct,
    )
    raw_record = truth.raw === nothing ? nothing : (;
        parameter_names = raw_names,
        values = truth.raw,
    )
    return (;
        parameter_space = :direct_constrained_static_component,
        direct = direct_record,
        raw = raw_record,
        direct_sha256 = portable_json_hash(direct_record),
        raw_sha256 = raw_record === nothing ? missing : portable_json_hash(raw_record),
    )
end

function canonical_event_set(events)
    return sort([(;
        target_index = row.target_index,
        person_index = row.person_index,
        item_index = row.item_index,
        rater_index = row.rater_index,
        is_common_linking_target = row.is_common_linking_target,
    ) for row in events]; by = row -> (row.target_index, row.rater_index))
end

function event_skeleton_manifest(materialized)
    events = materialized.events
    ordered = [(;
        target_index = row.target_index,
        rater_index = row.rater_index,
        rater_position = row.rater_position,
        occasion = row.occasion,
        is_common_linking_target = row.is_common_linking_target,
    ) for row in events]
    common = sort([(target_index = row.target_index,
        rater_index = row.rater_index) for row in events
        if row.is_common_linking_target]; by = row ->
            (row.target_index, row.rater_index))
    return (;
        seed = materialized.skeleton_seed,
        resampled_components = materialized.skeleton_resampling,
        event_set_sha256 = portable_json_hash(canonical_event_set(events)),
        ordered_event_skeleton_sha256 = portable_json_hash(ordered),
        common_target_rater_events_sha256 = portable_json_hash(common),
    )
end

function preflight_model_cell(cell, family, config; skeleton_seed::Int)
    materialized = materialize_events(cell, config; skeleton_seed)
    events = materialized.events
    placeholder = placeholder_scores(length(events), config.n_categories)
    data = facet_data(table_from_events(events, placeholder))
    design_hash = portable_json_hash([(
        target = row.target_index,
        rater = row.rater_index,
        position = row.rater_position,
        common_linking = row.is_common_linking_target,
    ) for row in events])
    skeleton = event_skeleton_manifest(materialized)
    if cell.expected_prefit_rejection
        rejection = rejection_record(data, family, config)
        artifact = (;
            cell_id = cell.cell_id,
            family,
            tier = cell.tier,
            role = cell.role,
            axes = cell,
            design_sha256 = design_hash,
            event_skeleton = skeleton,
            design_metrics = nothing,
            validation = rejection,
            truth = nothing,
            static_probability_sha256 = missing,
        )
        return (; artifact, runtime = nothing)
    end

    validation = BayesianMGMFRM.validate_design(data)
    validation.passed || error(
        "positive cell $(cell.cell_id)/$family failed validation: " *
        string([issue.code for issue in validation.issues if issue.severity === :error]),
    )
    spec = family_spec(data, family, config)
    design = family_design(spec, family)
    truth = known_truth(design, family, cell, config)
    probabilities = static_probabilities(design, family, truth.direct)
    all(isfinite, probabilities) || error("non-finite static probability")
    maximum(abs.(sum(probabilities; dims = 2) .- 1)) <= 1e-12 ||
        error("static category probabilities do not sum to one")
    audit = BayesianMGMFRM.rating_design_audit(spec;
        unit = :person_item, min_shared_units = 2)
    metrics = design_metrics(
        materialized,
        cell,
        config,
        data,
        audit,
        design,
        truth,
        family,
    )
    artifact = (;
        cell_id = cell.cell_id,
        family,
        tier = cell.tier,
        role = cell.role,
        axes = cell,
        design_sha256 = design_hash,
        event_skeleton = skeleton,
        design_metrics = metrics,
        validation = (;
            passed = validation.passed,
            n_errors = count(issue -> issue.severity === :error, validation.issues),
            n_warnings = count(issue -> issue.severity === :warning, validation.issues),
            spec_estimation_status = spec.estimation_status,
            compiled = true,
            n_direct_parameters = length(design.parameter_names),
        ),
        truth = truth_manifest(design, truth, family),
        static_probability_sha256 = portable_json_hash(probabilities),
    )
    runtime = (;
        cell,
        family,
        materialized,
        spec,
        design,
        truth,
        probabilities,
        artifact,
    )
    return (; artifact, runtime)
end

function execution_selected(cell, profile)
    profile === :smoke && return cell.smoke_fit
    profile === :pilot && return cell.pilot_fit
    return !cell.expected_prefit_rejection
end

function profile_fit_skeleton_preflight(options, config, cell_index)
    rows = NamedTuple[]
    n_unique_design_skeletons = 0
    for cell in DESIGN_CELLS
        execution_selected(cell, options.profile) || continue
        for replication in 1:options.requested_replications
            family_for_seed = first(cell.families)
            seeds = replication_seeds(
                options.profile,
                replication,
                cell_index[cell.cell_id],
                family_for_seed,
            )
            materialized = materialize_events(
                cell,
                config;
                skeleton_seed = seeds.skeleton,
            )
            scores = placeholder_scores(length(materialized.events),
                config.n_categories)
            data = facet_data(table_from_events(materialized.events, scores))
            audit = BayesianMGMFRM.rating_design_audit(
                data;
                unit = :person_item,
                min_shared_units = 2,
            )
            gate = requested_vs_achieved_design_gate(
                materialized,
                cell,
                config,
                audit,
            )
            skeleton = event_skeleton_manifest(materialized)
            n_unique_design_skeletons += 1
            for family in cell.families
                family_seeds = replication_seeds(
                    options.profile,
                    replication,
                    cell_index[cell.cell_id],
                    family,
                )
                family_seeds.skeleton == seeds.skeleton || error(
                    "family-specific sampler namespace changed the shared design seed",
                )
                family_preflight = preflight_model_cell(
                    cell,
                    family,
                    config;
                    skeleton_seed = seeds.skeleton,
                )
                runtime = family_preflight.runtime
                runtime.artifact.event_skeleton.event_set_sha256 ==
                    skeleton.event_set_sha256 || error(
                    "family preflight changed the shared event set",
                )
                truth_contract = recovery_truth_contract(
                    runtime.design,
                    runtime.truth.direct,
                )
                sampler_contract = recovery_sampler_contract(config.sampler)
                failed_checks = Symbol[]
                gate.record.common_linking_fraction_count_passed ||
                    push!(failed_checks, :common_linking_fraction_count)
                gate.record.support_passed || push!(failed_checks, :support)
                gate.record.placement_passed || push!(failed_checks, :placement)
                gate.record.rater_linking_passed ||
                    push!(failed_checks, :rater_linking)
                gate.record.rating_budget_passed ||
                    push!(failed_checks, :rating_budget)
                push!(rows, (;
                    cell_id = cell.cell_id,
                    family,
                    replication,
                    seed_namespace = seeds.namespace,
                    skeleton_seed = seeds.skeleton,
                    event_set_sha256 = skeleton.event_set_sha256,
                    ordered_event_skeleton_sha256 =
                        skeleton.ordered_event_skeleton_sha256,
                    common_target_rater_events_sha256 =
                        skeleton.common_target_rater_events_sha256,
                    rating_assignment_design_sha256 =
                        runtime.artifact.design_sha256,
                    direct_truth_sha256 =
                        runtime.artifact.truth.direct_sha256,
                    truth_contract_sha256 =
                        truth_contract.content_sha256,
                    recovery_truth_contract = truth_contract,
                    sampler_contract_sha256 =
                        sampler_contract.content_sha256,
                    requested_vs_achieved = gate.record,
                    failed_checks,
                    passed = gate.record.passed,
                ))
            end
        end
    end
    failure_rows = [row for row in rows if !row.passed]
    n_passed = count(row -> row.passed, rows)
    recovery_pair_contract_rows = [(;
        cell_id = row.cell_id,
        family = row.family,
        replication = row.replication,
        seed_namespace = row.seed_namespace,
        rating_assignment_design_sha256 =
            row.rating_assignment_design_sha256,
        event_set_sha256 = row.event_set_sha256,
        ordered_event_skeleton_sha256 =
            row.ordered_event_skeleton_sha256,
        direct_truth_sha256 = row.direct_truth_sha256,
        truth_contract_sha256 = row.truth_contract_sha256,
        sampler_contract_sha256 = row.sampler_contract_sha256,
    ) for row in rows]
    return (;
        schema =
            "bayesianmgmfrm.existing_api_design_skeleton_preflight.v2",
        generator_source_sha256 = file_sha256(@__FILE__),
        profile = options.profile,
        requested_replications = options.requested_replications,
        scope = :design_only_before_score_generation_and_family_fit,
        score_generation_attempted = false,
        mcmc_fit_attempted = false,
        response_uniforms_generated = false,
        response_scores_generated = false,
        family_likelihood_compile_required = false,
        n_profile_fit_candidate_families = sum(length(cell.families)
            for cell in DESIGN_CELLS
            if execution_selected(cell, options.profile)),
        n_unique_design_skeletons,
        n_candidate_family_replication_rows = length(rows),
        n_passed,
        n_failed = length(failure_rows),
        passed = isempty(failure_rows),
        failure_rows,
        rows,
        recovery_pair_contract_rows,
        recovery_pair_contract_manifest_sha256 =
            portable_json_hash(recovery_pair_contract_rows),
        recovery_freeze_input_candidate_ready =
            options.profile === :calibration &&
            options.requested_replications >=
                MINIMUM_CALIBRATION_REPLICATIONS && isempty(failure_rows),
    )
end

function _canonical_profile_fit_skeleton_preflight(
        profile::Symbol,
        requested_replications::Int)
    profile in (:pilot, :calibration) || throw(ArgumentError(
        "canonical recovery preflight is available only for pilot/calibration",
    ))
    requested_replications >= 1 || throw(ArgumentError(
        "canonical recovery preflight requires positive replications",
    ))
    key = (profile, requested_replications)
    cached = get!(_CANONICAL_PROFILE_PREFLIGHT_CACHE, key) do
        config = profile_config(profile)
        options = (;
            output = DEFAULT_OUTPUT,
            output_explicit = false,
            profile,
            requested_replications,
            execute = false,
            allow_heavy = false,
        )
        cell_index = Dict(cell.cell_id => index
            for (index, cell) in pairs(DESIGN_CELLS))
        profile_fit_skeleton_preflight(options, config, cell_index)
    end
    return deepcopy(cached)
end

function score_summary(scores, category_levels)
    category_counts = [(value = value, n = count(==(value), scores))
        for value in category_levels]
    return (;
        n = length(scores),
        mean = arithmetic_mean(scores),
        standard_deviation = sample_standard_deviation(scores),
        minimum = minimum(scores),
        maximum = maximum(scores),
        category_counts,
        unused_categories = [row.value for row in category_counts if row.n == 0],
        all_declared_categories_observed = all(row.n > 0 for row in category_counts),
    )
end

function likelihood_smoke(runtime, scores, config)
    data = BayesianMGMFRM._facet_data_with_scores(
        runtime.design.spec.data,
        scores,
    )
    spec = family_spec(data, runtime.family, config)
    design = family_design(spec, runtime.family)
    design.parameter_names == runtime.design.parameter_names || error(
        "simulated response changed direct parameter ordering for $(runtime.cell.cell_id)/$(runtime.family)",
    )
    pointwise = BayesianMGMFRM.pointwise_loglikelihood_matrix(
        design,
        reshape(runtime.truth.direct, 1, :);
        parameter_space = :direct,
    )
    return (;
        data,
        spec,
        design,
        finite = all(isfinite, pointwise),
        loglikelihood_at_static_truth = sum(pointwise),
        maximum_absolute_pointwise_loglikelihood = maximum(abs, pointwise),
    )
end

function field_or(value, field::Symbol, default = missing)
    return hasproperty(value, field) ? getproperty(value, field) : default
end

function canonical_model_family(family::Symbol)
    haskey(CANONICAL_FAMILY_BY_RUNNER_FAMILY, family) ||
        throw(ArgumentError("unsupported design-robustness family: $family"))
    return CANONICAL_FAMILY_BY_RUNNER_FAMILY[family]
end

function canonical_recovery_block(family::Symbol, block::Symbol)
    canonical_model_family(family)
    aliases = CANONICAL_RECOVERY_BLOCK_BY_FAMILY[family]
    haskey(aliases, block) || throw(ArgumentError(
        "unmapped recovery block :$block for design-robustness family :$family",
    ))
    return aliases[block]
end

function required_canonical_recovery_blocks(family::Symbol)
    canonical_model_family(family)
    return Tuple(sort!(unique!(collect(values(
        CANONICAL_RECOVERY_BLOCK_BY_FAMILY[family],
    ))); by = string))
end

function _nonempty_string(value, label::AbstractString)
    value isa AbstractString || throw(ArgumentError("$label must be a string"))
    checked = strip(String(value))
    isempty(checked) && throw(ArgumentError("$label must not be empty"))
    return checked
end

function _sha256_string(value, label::AbstractString)
    checked = _nonempty_string(value, label)
    checked == lowercase(checked) || throw(ArgumentError(
        "$label must use lowercase hexadecimal",
    ))
    occursin(r"^[0-9a-f]{64}$", checked) || throw(ArgumentError(
        "$label must be a lowercase 64-character SHA-256 digest",
    ))
    return checked
end

function _strict_bool(value, label::AbstractString)
    value isa Bool || throw(ArgumentError("$label must be Bool"))
    return value
end

function _contract_payload(record, expected_schema::AbstractString,
        label::AbstractString)
    record === nothing && throw(ArgumentError("$label is required"))
    String(field_or(record, :schema, "")) == expected_schema ||
        throw(ArgumentError("$label has an unsupported schema"))
    payload = field_or(record, :payload, nothing)
    payload === nothing && throw(ArgumentError("$label is missing payload"))
    content_sha256 = _sha256_string(
        field_or(record, :content_sha256, ""),
        "$label content_sha256",
    )
    portable_json_hash(payload) == content_sha256 || throw(ArgumentError(
        "$label content SHA-256 does not match its payload",
    ))
    return payload
end

function recovery_truth_contract(design, truth)
    layout = BayesianMGMFRM._design_recovery_layout(design, :direct)
    length(layout.parameter_names) == length(truth) || throw(ArgumentError(
        "recovery truth length does not match the direct parameter layout",
    ))
    structurally_fixed_parameters = if design.spec.family === :mfrm
        Set{String}()
    elseif design.spec.family === :gmfrm
        BayesianMGMFRM._structurally_fixed_constrained_parameter_names(
            BayesianMGMFRM._gmfrm_fit_ready_candidate_blueprint(design),
        )
    else
        BayesianMGMFRM._structurally_fixed_constrained_parameter_names(
            BayesianMGMFRM._mgmfrm_fit_ready_candidate_blueprint(design),
        )
    end
    rows = NamedTuple[]
    for index in eachindex(layout.parameter_names)
        value = Float64(truth[index])
        isfinite(value) || throw(ArgumentError(
            "recovery truth contains a non-finite direct parameter",
        ))
        parameter = String(layout.parameter_names[index])
        quality_gate_applicable =
            !(parameter in structurally_fixed_parameters)
        push!(rows, (;
            parameter,
            raw_block = BayesianMGMFRM._parameter_block_name(
                layout.blocks,
                index,
            ),
            true_value = value,
            quality_gate_applicable,
            diagnostic_status = quality_gate_applicable ?
                :rank_normalized_available : :structurally_fixed,
        ))
    end
    length(unique(row.parameter for row in rows)) == length(rows) ||
        throw(ArgumentError("recovery truth parameter names must be unique"))
    payload = (;
        parameter_space = :direct,
        parameters = rows,
    )
    return (;
        schema = "bayesianmgmfrm.existing_api_recovery_truth_contract.v1",
        payload,
        content_sha256 = portable_json_hash(payload),
    )
end

function recovery_sampler_contract(sampler)
    payload = (;
        sampler_contract_id = Symbol(sampler.sampler_contract_id),
        diagnostic_contract = BayesianMGMFRM._MCMC_DIAGNOSTIC_CONTRACT,
        diagnostic_contract_details =
            BayesianMGMFRM._mcmc_diagnostic_contract_record(),
        n_chains = Int(sampler.chains),
        draws_per_chain = Int(sampler.draws),
        total_draws = Int(sampler.chains) * Int(sampler.draws),
        split_chains = Bool(sampler.split_chains),
        max_rhat = Float64(sampler.rhat_threshold),
        min_bulk_ess = Float64(sampler.ess_threshold),
        min_tail_ess = Float64(sampler.ess_threshold),
        min_e_bfmi = 0.30,
        required_divergences =
            GATE_CONTRACT.fixed_contract_and_sampler.required_divergences,
        required_max_treedepth_hits = GATE_CONTRACT.fixed_contract_and_sampler.
            required_max_treedepth_hits,
        require_complete_chain_e_bfmi = true,
        required_nonfinite_logdensity = 0,
        required_failed_direct_constraints = 0,
    )
    return (;
        schema = "bayesianmgmfrm.existing_api_recovery_sampler_contract.v1",
        payload,
        content_sha256 = portable_json_hash(payload),
    )
end

function canonical_calibration_recovery_roster()
    rows = NamedTuple[]
    for cell in DESIGN_CELLS
        cell.expected_prefit_rejection && continue
        for family in cell.families
            push!(rows, (; cell_id = cell.cell_id, family))
        end
    end
    return sort!(rows; by = row ->
        (string(row.cell_id), string(row.family)))
end

function canonical_pilot_recovery_roster()
    rows = NamedTuple[]
    for cell in DESIGN_CELLS
        cell.pilot_fit || continue
        for family in cell.families
            push!(rows, (; cell_id = cell.cell_id, family))
        end
    end
    return sort!(rows; by = row ->
        (string(row.cell_id), string(row.family)))
end

function calibration_recovery_freeze_input(preflight)
    String(field_or(preflight, :schema, "")) ==
        "bayesianmgmfrm.existing_api_design_skeleton_preflight.v2" ||
        throw(ArgumentError("unsupported calibration preflight schema"))
    _sha256_string(
        field_or(preflight, :generator_source_sha256, ""),
        "calibration preflight generator source SHA-256",
    ) == file_sha256(@__FILE__) || throw(ArgumentError(
        "calibration preflight was not produced by the current generator source",
    ))
    Symbol(field_or(preflight, :profile, :missing)) === :calibration ||
        throw(ArgumentError(
            "recovery freeze input must come from the calibration design preflight",
        ))
    Int(field_or(preflight, :requested_replications, 0)) >=
        MINIMUM_CALIBRATION_REPLICATIONS || throw(ArgumentError(
            "recovery freeze input has too few calibration replications",
        ))
    requested_replications = Int(preflight.requested_replications)
    canonical_preflight = _canonical_profile_fit_skeleton_preflight(
        :calibration,
        requested_replications,
    )
    portable_json_hash(preflight) == portable_json_hash(canonical_preflight) ||
        throw(ArgumentError(
            "calibration preflight does not exactly match regeneration from canonical options",
        ))
    field_or(preflight, :mcmc_fit_attempted, true) === false ||
        throw(ArgumentError("recovery freeze input must be MCMC-free"))
    field_or(preflight, :response_uniforms_generated, true) === false &&
        field_or(preflight, :response_scores_generated, true) === false ||
        throw(ArgumentError(
            "recovery freeze input must be fixed before response generation",
        ))
    Symbol(field_or(preflight, :scope, :missing)) ===
        :design_only_before_score_generation_and_family_fit ||
        throw(ArgumentError("calibration preflight scope is invalid"))
    field_or(preflight, :passed, false) === true &&
        field_or(
            preflight,
            :recovery_freeze_input_candidate_ready,
            false,
        ) === true ||
        throw(ArgumentError("calibration design preflight did not pass"))
    source_rows = collect(field_or(preflight, :rows, NamedTuple[]))
    isempty(source_rows) && throw(ArgumentError(
        "calibration preflight source rows are missing",
    ))
    all(row -> field_or(row, :passed, false) === true &&
        isempty(collect(field_or(row, :failed_checks, Symbol[]))),
        source_rows) || throw(ArgumentError(
        "calibration preflight contains a failed source row",
    ))
    rows = collect(field_or(
        preflight,
        :recovery_pair_contract_rows,
        NamedTuple[],
    ))
    expected_manifest_sha256 = _sha256_string(
        field_or(
            preflight,
            :recovery_pair_contract_manifest_sha256,
            "",
        ),
        "recovery pair contract manifest SHA-256",
    )
    portable_json_hash(rows) == expected_manifest_sha256 ||
        throw(ArgumentError(
            "recovery pair contract manifest hash does not match its rows",
        ))
    canonical_rows = _canonical_expected_pair_contracts(rows)
    _canonical_expected_pair_contracts(source_rows) == canonical_rows ||
        throw(ArgumentError(
            "calibration recovery contracts do not match the passed source rows",
        ))
    length(source_rows) == length(canonical_rows) ==
        Int(field_or(preflight, :n_candidate_family_replication_rows, 0)) ||
        throw(ArgumentError("calibration preflight row counts are inconsistent"))
    Int(field_or(preflight, :n_passed, -1)) == length(source_rows) &&
        Int(field_or(preflight, :n_failed, -1)) == 0 &&
        isempty(collect(field_or(preflight, :failure_rows, NamedTuple[]))) ||
        throw(ArgumentError("calibration preflight completion counts are invalid"))
    expected_keys = _canonical_expected_pair_keys([(
        cell_id = roster.cell_id,
        family = roster.family,
        replication,
    ) for roster in canonical_calibration_recovery_roster()
        for replication in 1:requested_replications])
    observed_keys = _canonical_expected_pair_keys([(
        cell_id = row.cell_id,
        family = row.family,
        replication = row.replication,
    ) for row in canonical_rows])
    observed_keys == expected_keys || throw(ArgumentError(
        "calibration preflight does not match the canonical full roster",
    ))
    sampler_hashes = unique(row.sampler_contract_sha256
        for row in canonical_rows)
    length(sampler_hashes) == 1 || throw(ArgumentError(
        "calibration recovery preflight must use one sampler contract",
    ))
    canonical_sampler = recovery_sampler_contract(
        profile_config(:calibration).sampler,
    )
    only(sampler_hashes) == canonical_sampler.content_sha256 ||
        throw(ArgumentError(
            "calibration recovery preflight sampler contract is not canonical",
        ))
    payload = (;
        generator_source_sha256 = file_sha256(@__FILE__),
        source_preflight = preflight,
        source_preflight_schema = String(preflight.schema),
        source_preflight_content_sha256 = portable_json_hash(preflight),
        requested_replications,
        expected_pair_contracts = canonical_rows,
        expected_pair_contract_manifest_sha256 =
            portable_json_hash(canonical_rows),
        sampler_contract_sha256 = only(sampler_hashes),
        source_pair_contract_manifest_sha256 = expected_manifest_sha256,
        response_data_generated = false,
        mcmc_executed = false,
        source_reexecution_required_for_evidence = true,
        recovery_claim_supported = false,
    )
    return (;
        schema =
            "bayesianmgmfrm.existing_api_recovery_freeze_input.v2",
        payload,
        content_sha256 = portable_json_hash(payload),
    )
end

function _validated_calibration_recovery_freeze_input(record)
    payload = _contract_payload(
        record,
        "bayesianmgmfrm.existing_api_recovery_freeze_input.v2",
        "pre-response calibration recovery freeze input",
    )
    source_preflight = field_or(payload, :source_preflight, nothing)
    source_preflight === nothing && throw(ArgumentError(
        "freeze input is missing its source calibration preflight",
    ))
    canonical_record = calibration_recovery_freeze_input(source_preflight)
    String(field_or(record, :content_sha256, "")) ==
        canonical_record.content_sha256 || throw(ArgumentError(
            "freeze input is not the canonical projection of its revalidated source preflight",
        ))
    payload = canonical_record.payload
    _sha256_string(
        field_or(payload, :generator_source_sha256, ""),
        "freeze-input generator source SHA-256",
    ) == file_sha256(@__FILE__) || throw(ArgumentError(
        "freeze input was not produced by the current generator source",
    ))
    String(field_or(payload, :source_preflight_schema, "")) ==
        "bayesianmgmfrm.existing_api_design_skeleton_preflight.v2" ||
        throw(ArgumentError("freeze-input source preflight schema is invalid"))
    _sha256_string(
        field_or(payload, :source_preflight_content_sha256, ""),
        "freeze-input source preflight content SHA-256",
    )
    field_or(payload, :response_data_generated, true) === false &&
        field_or(payload, :mcmc_executed, true) === false ||
        throw(ArgumentError(
            "freeze input must be sealed before response generation and MCMC",
        ))
    field_or(payload, :source_reexecution_required_for_evidence, false) ===
        true || throw(ArgumentError(
            "freeze input must require source-preflight reexecution for evidence",
        ))
    field_or(payload, :recovery_claim_supported, true) === false ||
        throw(ArgumentError("freeze input cannot itself support a recovery claim"))
    requested_replications = Int(field_or(
        payload,
        :requested_replications,
        0,
    ))
    requested_replications >= MINIMUM_CALIBRATION_REPLICATIONS ||
        throw(ArgumentError("freeze input has too few replications"))
    pair_contracts = _canonical_expected_pair_contracts(collect(field_or(
        payload,
        :expected_pair_contracts,
        NamedTuple[],
    )))
    portable_json_hash(pair_contracts) == _sha256_string(
        field_or(
            payload,
            :expected_pair_contract_manifest_sha256,
            "",
        ),
        "freeze-input expected pair-contract manifest SHA-256",
    ) || throw(ArgumentError(
        "freeze-input pair contracts do not match their canonical manifest",
    ))
    _sha256_string(
        field_or(payload, :source_pair_contract_manifest_sha256, ""),
        "freeze-input source pair-contract manifest SHA-256",
    )
    expected_keys = _canonical_expected_pair_keys([(
        cell_id = roster.cell_id,
        family = roster.family,
        replication,
    ) for roster in canonical_calibration_recovery_roster()
        for replication in 1:requested_replications])
    observed_keys = _canonical_expected_pair_keys([(
        cell_id = row.cell_id,
        family = row.family,
        replication = row.replication,
    ) for row in pair_contracts])
    observed_keys == expected_keys || throw(ArgumentError(
        "freeze input does not contain the complete canonical calibration roster",
    ))
    canonical_sampler = recovery_sampler_contract(
        profile_config(:calibration).sampler,
    )
    sampler_contract_sha256 = _sha256_string(
        field_or(payload, :sampler_contract_sha256, ""),
        "freeze-input sampler contract SHA-256",
    )
    sampler_contract_sha256 == canonical_sampler.content_sha256 ||
        throw(ArgumentError(
            "freeze input does not use the canonical calibration sampler",
        ))
    all(row -> row.sampler_contract_sha256 == sampler_contract_sha256,
        pair_contracts) || throw(ArgumentError(
            "freeze-input pairs do not all use the sealed sampler contract",
        ))
    return (;
        generator_source_sha256 = String(payload.generator_source_sha256),
        source_preflight = payload.source_preflight,
        source_preflight_schema = String(payload.source_preflight_schema),
        source_preflight_content_sha256 =
            String(payload.source_preflight_content_sha256),
        requested_replications,
        expected_pair_contracts = pair_contracts,
        expected_pair_contract_manifest_sha256 =
            String(payload.expected_pair_contract_manifest_sha256),
        sampler_contract_sha256,
        source_pair_contract_manifest_sha256 =
            String(payload.source_pair_contract_manifest_sha256),
        response_data_generated = false,
        mcmc_executed = false,
        source_reexecution_required_for_evidence = true,
        recovery_claim_supported = false,
    )
end

function _canonical_expected_pair_keys(expected_pair_keys)
    rows = NamedTuple[]
    for row in expected_pair_keys
        raw_replication = field_or(row, :replication, 0)
        raw_replication isa Integer && !(raw_replication isa Bool) ||
            throw(ArgumentError(
                "frozen recovery gate replications must be integers",
            ))
        push!(rows, (;
            cell_id = Symbol(field_or(row, :cell_id, :missing)),
            family = Symbol(field_or(row, :family, :missing)),
            replication = Int(raw_replication),
        ))
    end
    isempty(rows) && throw(ArgumentError(
        "frozen recovery gate expected_pair_keys must not be empty",
    ))
    for row in rows
        row.cell_id === :missing && throw(ArgumentError(
            "frozen recovery gate cell_id must be explicit",
        ))
        canonical_model_family(row.family)
        row.replication >= 1 || throw(ArgumentError(
            "frozen recovery gate replications must be positive",
        ))
    end
    length(unique((row.cell_id, row.family, row.replication) for row in rows)) ==
        length(rows) || throw(ArgumentError(
            "frozen recovery gate expected_pair_keys must be unique",
        ))
    return sort!(rows; by = row ->
        (string(row.cell_id), string(row.family), row.replication))
end

function _canonical_expected_pair_contracts(records;
        required_seed_namespace::Symbol = :calibration_evaluation)
    rows = NamedTuple[]
    for row in records
        key = only(_canonical_expected_pair_keys((row,)))
        seed_namespace = Symbol(field_or(row, :seed_namespace, :missing))
        seed_namespace === required_seed_namespace || throw(ArgumentError(
            "expected recovery pair contracts use the wrong seed namespace",
        ))
        push!(rows, (;
            key...,
            seed_namespace,
            rating_assignment_design_sha256 = _sha256_string(
                field_or(row, :rating_assignment_design_sha256, ""),
                "expected rating_assignment_design_sha256",
            ),
            event_set_sha256 = _sha256_string(
                field_or(row, :event_set_sha256, ""),
                "expected event_set_sha256",
            ),
            ordered_event_skeleton_sha256 = _sha256_string(
                field_or(row, :ordered_event_skeleton_sha256, ""),
                "expected ordered_event_skeleton_sha256",
            ),
            direct_truth_sha256 = _sha256_string(
                field_or(row, :direct_truth_sha256, ""),
                "expected direct_truth_sha256",
            ),
            truth_contract_sha256 = _sha256_string(
                field_or(row, :truth_contract_sha256, ""),
                "expected truth_contract_sha256",
            ),
            sampler_contract_sha256 = _sha256_string(
                field_or(row, :sampler_contract_sha256, ""),
                "expected sampler_contract_sha256",
            ),
        ))
    end
    length(unique((row.cell_id, row.family, row.replication)
        for row in rows)) == length(rows) || throw(ArgumentError(
            "expected recovery pair contracts must have unique keys",
        ))
    return sort!(rows; by = row ->
        (string(row.cell_id), string(row.family), row.replication))
end

function _checked_recovery_thresholds(thresholds)
    names = (
        :nominal_interval_coverage,
        :max_block_mae_quantile,
        :max_focal_absolute_error_quantile,
        :min_empirical_to_posterior_sd_ratio_quantile,
        :max_empirical_to_posterior_sd_ratio_quantile,
    )
    values = Dict{Symbol,Float64}()
    for name in names
        raw = field_or(thresholds, name, missing)
        ismissing(raw) && throw(ArgumentError(
            "frozen recovery threshold :$name is required",
        ))
        raw isa Real && !(raw isa Bool) || throw(ArgumentError(
            "frozen recovery threshold :$name must be a real number",
        ))
        value = Float64(raw)
        isfinite(value) || throw(ArgumentError(
            "frozen recovery threshold :$name must be finite",
        ))
        values[name] = value
    end
    0.0 < values[:nominal_interval_coverage] < 1.0 ||
        throw(ArgumentError("nominal interval coverage must be in (0, 1)"))
    values[:max_block_mae_quantile] >= 0.0 ||
        throw(ArgumentError("block MAE quantile must be nonnegative"))
    values[:max_focal_absolute_error_quantile] >= 0.0 || throw(ArgumentError(
        "focal absolute-error quantile must be nonnegative",
    ))
    values[:min_empirical_to_posterior_sd_ratio_quantile] > 0.0 ||
        throw(ArgumentError("minimum uncertainty ratio must be positive"))
    values[:max_empirical_to_posterior_sd_ratio_quantile] >=
        values[:min_empirical_to_posterior_sd_ratio_quantile] ||
        throw(ArgumentError(
            "maximum uncertainty ratio must be at least the minimum",
        ))
    outer = GATE_CONTRACT.provisional_recovery_and_decision
    values[:nominal_interval_coverage] >=
        outer.nominal_interval_coverage || throw(ArgumentError(
            "frozen nominal coverage cannot be looser than the fixed outer bound",
        ))
    values[:max_block_mae_quantile] <= outer.max_block_mae_quantile ||
        throw(ArgumentError(
        "frozen block MAE cannot be looser than the fixed outer bound",
    ))
    values[:max_focal_absolute_error_quantile] <=
        outer.max_focal_absolute_error_quantile || throw(ArgumentError(
            "frozen focal error cannot be looser than the fixed outer bound",
        ))
    values[:min_empirical_to_posterior_sd_ratio_quantile] >=
        outer.min_empirical_to_posterior_sd_ratio_quantile ||
        throw(ArgumentError(
            "frozen minimum uncertainty ratio cannot be looser than the fixed outer bound",
        ))
    values[:max_empirical_to_posterior_sd_ratio_quantile] <=
        outer.max_empirical_to_posterior_sd_ratio_quantile ||
        throw(ArgumentError(
            "frozen maximum uncertainty ratio cannot be looser than the fixed outer bound",
        ))
    return (; (name => values[name] for name in names)...)
end

function pilot_recovery_threshold_freeze_decision(
        pilot_artifact;
        thresholds,
        decision_revision,
        decided_at_utc)
    pilot_artifact_content_sha256 =
        _validated_pilot_artifact_content_hash(pilot_artifact)
    pilot_gate = field_or(pilot_artifact, :repeated_recovery_gate, nothing)
    pilot_gate === nothing && throw(ArgumentError(
        "pilot threshold decision requires the recomputable pilot gate",
    ))
    observed = field_or(pilot_gate, :observed, nothing)
    observed === nothing && throw(ArgumentError(
        "pilot threshold decision requires pilot observed statistics",
    ))
    statistical_gate_policy = field_or(
        pilot_gate,
        :statistical_gate_policy,
        nothing,
    )
    statistical_gate_policy === nothing && throw(ArgumentError(
        "pilot threshold decision requires the pilot statistical policy",
    ))
    checked_decided_at = _nonempty_string(decided_at_utc, "decided_at_utc")
    occursin(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$",
        checked_decided_at) || throw(ArgumentError(
            "decided_at_utc must use YYYY-MM-DDTHH:MM:SSZ",
        ))
    try
        DateTime(chop(checked_decided_at), dateformat"yyyy-mm-ddTHH:MM:SS")
    catch
        throw(ArgumentError("decided_at_utc is not a valid UTC timestamp"))
    end
    payload = (;
        pilot_artifact_content_sha256,
        pilot_observed = observed,
        pilot_observed_sha256 = portable_json_hash(observed),
        pilot_statistical_gate_policy = statistical_gate_policy,
        pilot_statistical_gate_policy_sha256 =
            portable_json_hash(statistical_gate_policy),
        thresholds = _checked_recovery_thresholds(thresholds),
        selection_policy =
            :manual_review_of_pilot_snapshot_with_fixed_outer_bounds_and_no_data_adaptive_loosening,
        decision_revision = _nonempty_string(
            decision_revision,
            "decision_revision",
        ),
        decided_at_utc = checked_decided_at,
        raw_draw_cache_identity_verified = false,
        chronology_external_attestation_verified = false,
        public_claim_supported = false,
    )
    return (;
        schema =
            "bayesianmgmfrm.existing_api_pilot_recovery_threshold_decision.v1",
        payload,
        content_sha256 = portable_json_hash(payload),
    )
end

function _validated_pilot_recovery_threshold_freeze_decision(record)
    payload = _contract_payload(
        record,
        "bayesianmgmfrm.existing_api_pilot_recovery_threshold_decision.v1",
        "pilot recovery threshold decision",
    )
    observed = field_or(payload, :pilot_observed, nothing)
    observed === nothing && throw(ArgumentError(
        "pilot threshold decision is missing observed statistics",
    ))
    portable_json_hash(observed) == _sha256_string(
        field_or(payload, :pilot_observed_sha256, ""),
        "pilot observed-statistics SHA-256",
    ) || throw(ArgumentError(
        "pilot observed-statistics hash does not match its snapshot",
    ))
    policy = field_or(payload, :pilot_statistical_gate_policy, nothing)
    policy === nothing && throw(ArgumentError(
        "pilot threshold decision is missing its statistical policy",
    ))
    portable_json_hash(policy) == _sha256_string(
        field_or(payload, :pilot_statistical_gate_policy_sha256, ""),
        "pilot statistical-policy SHA-256",
    ) || throw(ArgumentError(
        "pilot statistical-policy hash does not match its snapshot",
    ))
    Symbol(field_or(payload, :selection_policy, :missing)) ===
        :manual_review_of_pilot_snapshot_with_fixed_outer_bounds_and_no_data_adaptive_loosening ||
        throw(ArgumentError("pilot threshold selection policy is invalid"))
    field_or(payload, :raw_draw_cache_identity_verified, true) === false &&
        field_or(payload, :chronology_external_attestation_verified, true) ===
            false &&
        field_or(payload, :public_claim_supported, true) === false ||
        throw(ArgumentError(
            "pilot threshold decision overstates its evidence boundary",
        ))
    checked_decided_at = _nonempty_string(
        payload.decided_at_utc,
        "decided_at_utc",
    )
    occursin(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$",
        checked_decided_at) || throw(ArgumentError(
            "decided_at_utc must use YYYY-MM-DDTHH:MM:SSZ",
        ))
    try
        DateTime(chop(checked_decided_at), dateformat"yyyy-mm-ddTHH:MM:SS")
    catch
        throw(ArgumentError("decided_at_utc is not a valid UTC timestamp"))
    end
    checked = (;
        pilot_artifact_content_sha256 = _sha256_string(
            field_or(payload, :pilot_artifact_content_sha256, ""),
            "pilot artifact content SHA-256",
        ),
        pilot_observed = observed,
        pilot_observed_sha256 = String(payload.pilot_observed_sha256),
        pilot_statistical_gate_policy = policy,
        pilot_statistical_gate_policy_sha256 =
            String(payload.pilot_statistical_gate_policy_sha256),
        thresholds = _checked_recovery_thresholds(payload.thresholds),
        selection_policy = Symbol(payload.selection_policy),
        decision_revision = _nonempty_string(
            payload.decision_revision,
            "decision_revision",
        ),
        decided_at_utc = checked_decided_at,
        raw_draw_cache_identity_verified = false,
        chronology_external_attestation_verified = false,
        public_claim_supported = false,
    )
    canonical = (;
        schema =
            "bayesianmgmfrm.existing_api_pilot_recovery_threshold_decision.v1",
        payload = checked,
        content_sha256 = portable_json_hash(checked),
    )
    canonical.content_sha256 == String(record.content_sha256) ||
        throw(ArgumentError(
            "pilot threshold decision is not in canonical form",
        ))
    return canonical.payload
end

function recovery_gate_freeze_contract(;
        pilot_threshold_decision,
        freeze_source_revision,
        frozen_at_utc,
        freeze_input,
        minimum_replications::Int = MINIMUM_CALIBRATION_REPLICATIONS,
        seed_namespace::Symbol = :calibration_evaluation)
    minimum_replications >= MINIMUM_CALIBRATION_REPLICATIONS ||
        throw(ArgumentError(
            "calibration requires at least $MINIMUM_CALIBRATION_REPLICATIONS replications per cell/family",
        ))
    seed_namespace === :calibration_evaluation || throw(ArgumentError(
        "frozen recovery evaluation must use :calibration_evaluation seeds",
    ))
    freeze_input_payload =
        _validated_calibration_recovery_freeze_input(freeze_input)
    pilot_threshold_payload =
        _validated_pilot_recovery_threshold_freeze_decision(
            pilot_threshold_decision,
        )
    pair_contracts = freeze_input_payload.expected_pair_contracts
    canonical_sampler_contract = recovery_sampler_contract(
        profile_config(:calibration).sampler,
    )
    checked_sampler_contract_sha256 = _sha256_string(
        freeze_input_payload.sampler_contract_sha256,
        "sampler_contract_sha256",
    )
    checked_sampler_contract_sha256 ==
        canonical_sampler_contract.content_sha256 || throw(ArgumentError(
            "frozen recovery gate must use the canonical calibration sampler contract",
        ))
    keys = [(;
        cell_id = row.cell_id,
        family = row.family,
        replication = row.replication,
    ) for row in pair_contracts]
    expected_roster = canonical_calibration_recovery_roster()
    supplied_roster = sort!(unique!([(;
        cell_id = row.cell_id,
        family = row.family,
    ) for row in keys]); by = row ->
        (string(row.cell_id), string(row.family)))
    supplied_roster == expected_roster || throw(ArgumentError(
        "frozen recovery gate must contain the complete canonical calibration cell/family roster",
    ))
    all(row -> row.sampler_contract_sha256 ==
        checked_sampler_contract_sha256, pair_contracts) || throw(ArgumentError(
            "every expected pair must use the frozen sampler contract",
        ))
    grouped = Dict{Tuple{Symbol,Symbol},Vector{Int}}()
    for row in keys
        push!(get!(grouped, (row.cell_id, row.family), Int[]), row.replication)
    end
    for (key, replications) in grouped
        sort!(replications)
        replications == collect(1:maximum(replications)) || throw(ArgumentError(
            "frozen recovery key $key must contain contiguous replications from 1",
        ))
        length(replications) >= minimum_replications || throw(ArgumentError(
            "frozen recovery key $key has fewer than $minimum_replications replications",
        ))
    end
    checked_frozen_at = _nonempty_string(frozen_at_utc, "frozen_at_utc")
    occursin(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", checked_frozen_at) ||
        throw(ArgumentError("frozen_at_utc must use YYYY-MM-DDTHH:MM:SSZ"))
    decided_at = DateTime(
        chop(pilot_threshold_payload.decided_at_utc),
        dateformat"yyyy-mm-ddTHH:MM:SS",
    )
    frozen_at = try
        DateTime(chop(checked_frozen_at), dateformat"yyyy-mm-ddTHH:MM:SS")
    catch
        throw(ArgumentError("frozen_at_utc is not a valid UTC timestamp"))
    end
    decided_at <= frozen_at || throw(ArgumentError(
        "pilot threshold decision must not postdate the freeze contract",
    ))
    payload = (;
        pre_response_freeze_input = freeze_input,
        pre_response_freeze_input_content_sha256 = _sha256_string(
            field_or(freeze_input, :content_sha256, ""),
            "pre_response_freeze_input_content_sha256",
        ),
        pilot_threshold_decision,
        pilot_threshold_decision_content_sha256 = _sha256_string(
            field_or(pilot_threshold_decision, :content_sha256, ""),
            "pilot_threshold_decision_content_sha256",
        ),
        pilot_artifact_content_sha256 =
            pilot_threshold_payload.pilot_artifact_content_sha256,
        pilot_observed_sha256 = pilot_threshold_payload.
            pilot_observed_sha256,
        pilot_statistical_gate_policy_sha256 = pilot_threshold_payload.
            pilot_statistical_gate_policy_sha256,
        freeze_source_revision = _nonempty_string(
            freeze_source_revision,
            "freeze_source_revision",
        ),
        frozen_at_utc = checked_frozen_at,
        expected_pair_keys = keys,
        expected_pair_contracts = pair_contracts,
        expected_cell_family_roster = expected_roster,
        expected_conditions = REQUIRED_RECOVERY_CONDITIONS,
        minimum_replications,
        seed_namespace,
        sampler_contract_sha256 = _sha256_string(
            checked_sampler_contract_sha256,
            "sampler_contract_sha256",
        ),
        thresholds = pilot_threshold_payload.thresholds,
    )
    return (;
        schema = "bayesianmgmfrm.existing_api_recovery_gate_freeze.v2",
        payload,
        content_sha256 = portable_json_hash(payload),
    )
end

function design_robustness_scorer_capabilities()
    return (;
        schema = "bayesianmgmfrm.existing_api_design_robustness_scorer_capabilities.v1",
        recovery = (;
            implemented = RECOVERY_GATE_SCORER_IMPLEMENTED,
            repeated_bias_mae_rmse = true,
            repeated_interval_coverage = true,
            empirical_vs_posterior_uncertainty = true,
            failed_or_missing_fit_is_failure = true,
        ),
        prediction = (;
            implemented = PREDICTIVE_GATE_SCORER_IMPLEMENTED,
            category_probability_error = false,
            expected_score_error = false,
            heldout_log_predictive_density = false,
            posterior_predictive_calibration = false,
        ),
        decision = (;
            implemented = DECISION_GATE_SCORER_IMPLEMENTED,
            rank_stability = false,
            cut_score_flip_rate = false,
            pairwise_rater_contrast_stability = false,
        ),
        full_gate_scorer_implemented = FULL_GATE_SCORER_IMPLEMENTED,
    )
end

function recovery_scorer_stage_contract(stage::Symbol)
    stage in (:smoke, :pilot, :calibration) || throw(ArgumentError(
        "recovery scorer stage must be :smoke, :pilot, or :calibration",
    ))
    if stage === :smoke
        return (;
            stage,
            status = :wiring_only,
            threshold_action = :none,
            recovery_pass_fail_allowed = false,
            recovery_claim_allowed = false,
            public_design_robustness_claim_allowed = false,
        )
    elseif stage === :pilot
        return (;
            stage,
            status = :threshold_freeze_candidate_only,
            threshold_action = :freeze_candidates_before_evaluation_seeds,
            recovery_pass_fail_allowed = false,
            recovery_claim_allowed = false,
            public_design_robustness_claim_allowed = false,
        )
    end
    return (;
        stage,
        status = :evaluate_previously_frozen_thresholds,
        threshold_action = :evaluate_frozen_thresholds,
        recovery_pass_fail_allowed = true,
        recovery_claim_allowed = true,
        public_design_robustness_claim_allowed = false,
    )
end

function _recovery_condition_by_name(conditions, required::Symbol)
    matches = [row for row in conditions
        if Symbol(field_or(row, :condition, :missing)) === required]
    length(matches) <= 1 || throw(ArgumentError(
        "paired recovery row contains duplicate condition :$required",
    ))
    return isempty(matches) ? nothing : only(matches)
end

function _recovery_row_float(row, field::Symbol)
    value = field_or(row, field, missing)
    ismissing(value) && throw(ArgumentError(
        "recovery parameter row is missing :$field",
    ))
    value isa Real && !(value isa Bool) || throw(ArgumentError(
        "recovery parameter row :$field must be a real number, not Bool",
    ))
    converted = Float64(value)
    isfinite(converted) || throw(ArgumentError(
        "recovery parameter row contains non-finite :$field",
    ))
    return converted
end

function _diagnostic_gate_passed(summary, sampler_contract)
    summary === nothing && return false
    payload = try
        _contract_payload(
            sampler_contract,
            "bayesianmgmfrm.existing_api_recovery_sampler_contract.v1",
            "recovery sampler contract",
        )
    catch
        return false
    end
    field_or(summary, :passed, false) === true || return false
    Symbol(field_or(summary, :flag, :missing)) === :ok || return false
    Symbol(field_or(summary, :diagnostic_contract, :missing)) ===
        Symbol(payload.diagnostic_contract) || return false
    portable_json_hash(field_or(
        summary,
        :diagnostic_contract_details,
        nothing,
    )) == portable_json_hash(payload.diagnostic_contract_details) || return false
    field_or(summary, :split_chains, missing) === payload.split_chains ||
        return false
    max_rhat = field_or(summary, :max_rhat, missing)
    min_bulk_ess = field_or(summary, :min_bulk_ess,
        field_or(summary, :min_ess, missing))
    min_tail_ess = field_or(summary, :min_tail_ess,
        field_or(summary, :min_ess, missing))
    n_divergences = field_or(summary, :n_divergences, missing)
    n_max_treedepth = field_or(summary, :n_max_treedepth, missing)
    n_chains = field_or(summary, :n_chains, missing)
    draws_per_chain = field_or(summary, :draws_per_chain, missing)
    total_draws = field_or(summary, :total_draws, missing)
    n_e_bfmi_expected = field_or(summary, :n_e_bfmi_expected, missing)
    n_e_bfmi_available = field_or(summary, :n_e_bfmi_available, missing)
    n_e_bfmi_unavailable = field_or(summary, :n_e_bfmi_unavailable, missing)
    e_bfmi_complete = field_or(summary, :e_bfmi_complete, missing)
    e_bfmi = field_or(summary, :e_bfmi, missing)
    n_nonfinite_logdensity = field_or(
        summary,
        :n_nonfinite_logdensity,
        missing,
    )
    n_failed_direct_constraints = field_or(
        summary,
        :n_failed_direct_constraints,
        missing,
    )
    any(ismissing, (max_rhat, min_bulk_ess, min_tail_ess,
        n_divergences, n_max_treedepth, n_chains, draws_per_chain,
        total_draws, n_e_bfmi_expected, n_e_bfmi_available,
        n_e_bfmi_unavailable, e_bfmi_complete, e_bfmi,
        n_nonfinite_logdensity, n_failed_direct_constraints)) && return false
    all(value -> value isa Real && !(value isa Bool), (
        max_rhat, min_bulk_ess, min_tail_ess, n_divergences,
        n_max_treedepth, n_chains, draws_per_chain, total_draws,
        n_e_bfmi_expected, n_e_bfmi_available, n_e_bfmi_unavailable,
        e_bfmi, n_nonfinite_logdensity, n_failed_direct_constraints,
    )) || return false
    all(value -> isfinite(Float64(value)), (
        max_rhat, min_bulk_ess, min_tail_ess, e_bfmi,
    )) || return false
    return Int(n_chains) == payload.n_chains &&
        Int(draws_per_chain) == payload.draws_per_chain &&
        Int(total_draws) == payload.total_draws &&
        Float64(max_rhat) <= payload.max_rhat &&
        Float64(min_bulk_ess) >= payload.min_bulk_ess &&
        Float64(min_tail_ess) >= payload.min_tail_ess &&
        Float64(e_bfmi) >= payload.min_e_bfmi &&
        Int(n_divergences) == payload.required_divergences &&
        Int(n_max_treedepth) == payload.required_max_treedepth_hits &&
        e_bfmi_complete === payload.require_complete_chain_e_bfmi &&
        Int(n_e_bfmi_expected) == payload.n_chains &&
        Int(n_e_bfmi_available) == payload.n_chains &&
        Int(n_e_bfmi_unavailable) == 0 &&
        Int(n_nonfinite_logdensity) ==
            payload.required_nonfinite_logdensity &&
        Int(n_failed_direct_constraints) ==
            payload.required_failed_direct_constraints
end

function _validated_recovery_truth_contract(record, family::Symbol)
    payload = _contract_payload(
        record,
        "bayesianmgmfrm.existing_api_recovery_truth_contract.v1",
        "recovery truth contract",
    )
    Symbol(field_or(payload, :parameter_space, :missing)) === :direct ||
        throw(ArgumentError("recovery truth must use direct parameter space"))
    rows = collect(field_or(payload, :parameters, NamedTuple[]))
    isempty(rows) && throw(ArgumentError(
        "recovery truth contract must contain parameters",
    ))
    names = String[]
    truth_by_name = Dict{String,NamedTuple}()
    for row in rows
        parameter = _nonempty_string(
            field_or(row, :parameter, ""),
            "recovery truth parameter",
        )
        parameter in names && throw(ArgumentError(
            "recovery truth parameter names must be unique",
        ))
        raw_block = Symbol(field_or(row, :raw_block, :unknown))
        canonical_block = canonical_recovery_block(family, raw_block)
        true_value = _recovery_row_float(row, :true_value)
        quality_gate_applicable = _strict_bool(
            field_or(row, :quality_gate_applicable, missing),
            "recovery truth quality_gate_applicable",
        )
        diagnostic_status = Symbol(field_or(
            row,
            :diagnostic_status,
            :missing,
        ))
        diagnostic_status === (quality_gate_applicable ?
            :rank_normalized_available : :structurally_fixed) ||
            throw(ArgumentError(
                "recovery truth diagnostic status is inconsistent",
            ))
        checked = (;
            parameter,
            raw_block,
            canonical_block,
            true_value,
            quality_gate_applicable,
            diagnostic_status,
        )
        push!(names, parameter)
        truth_by_name[parameter] = checked
    end
    return (;
        parameter_names = Tuple(names),
        truth_by_name,
        content_sha256 = String(record.content_sha256),
    )
end

function _validated_sampler_contract(record, seed_namespace::Symbol)
    payload = _contract_payload(
        record,
        "bayesianmgmfrm.existing_api_recovery_sampler_contract.v1",
        "recovery sampler contract",
    )
    Symbol(payload.diagnostic_contract) ===
        BayesianMGMFRM._MCMC_DIAGNOSTIC_CONTRACT || throw(ArgumentError(
            "recovery sampler contract uses an unsupported diagnostic contract",
        ))
    portable_json_hash(payload.diagnostic_contract_details) == portable_json_hash(
        BayesianMGMFRM._mcmc_diagnostic_contract_record(),
    ) || throw(ArgumentError(
        "recovery sampler diagnostic contract details do not match runtime",
    ))
    payload.n_chains >= 1 && payload.draws_per_chain >= 1 &&
        payload.total_draws == payload.n_chains * payload.draws_per_chain ||
        throw(ArgumentError("recovery sampler draw counts are inconsistent"))
    profile = if seed_namespace === :smoke_wiring
        :smoke
    elseif seed_namespace === :pilot_threshold
        :pilot
    elseif seed_namespace === :calibration_evaluation
        :calibration
    else
        throw(ArgumentError("unsupported recovery seed namespace"))
    end
    canonical = recovery_sampler_contract(profile_config(profile).sampler)
    String(record.content_sha256) == canonical.content_sha256 &&
        portable_json_hash(payload) == portable_json_hash(canonical.payload) ||
        throw(ArgumentError(
            "recovery sampler contract does not match the canonical profile policy",
        ))
    return (;
        payload,
        content_sha256 = String(record.content_sha256),
    )
end

function aggregate_repeated_recovery(paired_rows;
        required_conditions = REQUIRED_RECOVERY_CONDITIONS)
    conditions_required = Tuple(Symbol(value) for value in required_conditions)
    isempty(conditions_required) && throw(ArgumentError(
        "required_conditions must not be empty",
    ))
    length(unique(conditions_required)) == length(conditions_required) ||
        throw(ArgumentError("required_conditions must be unique"))

    seen_pairs = Set{Tuple{Symbol,Symbol,Int}}()
    pair_contract_records = NamedTuple[]
    completion_records = NamedTuple[]
    flattened = NamedTuple[]
    for pair in paired_rows
        cell_id = Symbol(field_or(pair, :cell_id, :missing))
        family = Symbol(field_or(pair, :family, :missing))
        raw_replication = field_or(pair, :replication, 0)
        raw_replication isa Integer && !(raw_replication isa Bool) ||
            throw(ArgumentError(
                "paired recovery replication must be an integer",
            ))
        replication = Int(raw_replication)
        replication >= 1 || throw(ArgumentError(
            "paired recovery replication must be positive",
        ))
        canonical_family = canonical_model_family(family)
        pair_key = (cell_id, family, replication)
        pair_key in seen_pairs && throw(ArgumentError(
            "duplicate paired recovery row for $pair_key",
        ))
        push!(seen_pairs, pair_key)
        truth_contract = _validated_recovery_truth_contract(
            field_or(pair, :recovery_truth_contract, nothing),
            family,
        )
        seed_namespace = Symbol(field_or(pair, :seed_namespace, :missing))
        seed_namespace === :missing && throw(ArgumentError(
            "paired recovery row must declare its seed namespace",
        ))
        sampler_contract_record = field_or(
            pair,
            :recovery_sampler_contract,
            nothing,
        )
        sampler_contract = _validated_sampler_contract(
            sampler_contract_record,
            seed_namespace,
        )
        push!(pair_contract_records, (;
            cell_id,
            family,
            replication,
            seed_namespace,
            rating_assignment_design_sha256 = _sha256_string(
                field_or(pair, :rating_assignment_design_sha256, ""),
                "paired rating_assignment_design_sha256",
            ),
            event_set_sha256 = _sha256_string(
                field_or(pair, :event_set_sha256, ""),
                "paired event_set_sha256",
            ),
            ordered_event_skeleton_sha256 = _sha256_string(
                field_or(pair, :ordered_event_skeleton_sha256, ""),
                "paired ordered_event_skeleton_sha256",
            ),
            direct_truth_sha256 = _sha256_string(
                field_or(pair, :direct_truth_sha256, ""),
                "paired direct_truth_sha256",
            ),
            truth_contract_sha256 = truth_contract.content_sha256,
            sampler_contract_sha256 = sampler_contract.content_sha256,
        ))
        conditions = field_or(pair, :conditions, NamedTuple[])
        required_blocks = required_canonical_recovery_blocks(family)

        for required_condition in conditions_required
            condition = _recovery_condition_by_name(
                conditions,
                required_condition,
            )
            condition_present = condition !== nothing
            fit_record = condition_present ?
                field_or(condition, :fit, nothing) : nothing
            fit_present = fit_record !== nothing
            fit_status = fit_present ?
                Symbol(field_or(fit_record, :status, :unknown)) : :missing
            fit_attempted = fit_present &&
                fit_status !== :planned_not_run
            fit_succeeded = fit_attempted && fit_status === :completed &&
                field_or(fit_record, :succeeded, false) === true
            parameter_rows = fit_succeeded ?
                collect(field_or(fit_record, :recovery_parameter_rows,
                    NamedTuple[])) : NamedTuple[]
            diagnostics = fit_present ?
                field_or(fit_record, :diagnostics, nothing) : nothing
            sampler_gate_passed = fit_succeeded &&
                _diagnostic_gate_passed(
                    diagnostics,
                    sampler_contract_record,
                )
            parameter_names = String[
                String(field_or(row, :parameter, ""))
                for row in parameter_rows
            ]
            any(isempty, parameter_names) && throw(ArgumentError(
                "recovery parameter name must not be empty",
            ))
            duplicate_parameter_names = Tuple(sort!(unique!([
                name for name in parameter_names
                if count(==(name), parameter_names) > 1
            ])))
            expected_parameter_names = truth_contract.parameter_names
            missing_parameter_names = Tuple(sort!(collect(setdiff(
                Set(expected_parameter_names),
                Set(parameter_names),
            ))))
            unexpected_parameter_names = Tuple(sort!(collect(setdiff(
                Set(parameter_names),
                Set(expected_parameter_names),
            ))))
            parameter_set_complete = fit_succeeded &&
                isempty(duplicate_parameter_names) &&
                isempty(missing_parameter_names) &&
                isempty(unexpected_parameter_names) &&
                length(parameter_rows) == length(expected_parameter_names)
            observed_blocks = Symbol[]
            for row in (parameter_set_complete ? parameter_rows : NamedTuple[])
                raw_block = Symbol(field_or(row, :block, :unknown))
                canonical_block = canonical_recovery_block(family, raw_block)
                push!(observed_blocks, canonical_block)
                parameter = String(field_or(row, :parameter, ""))
                expected = truth_contract.truth_by_name[parameter]
                raw_block === expected.raw_block || throw(ArgumentError(
                    "recovery block does not match the authoritative truth layout for $parameter",
                ))
                true_value = _recovery_row_float(row, :true_value)
                isapprox(
                    true_value,
                    expected.true_value;
                    atol = RECOVERY_NUMERIC_TOLERANCE,
                    rtol = RECOVERY_NUMERIC_TOLERANCE,
                ) || throw(ArgumentError(
                    "recovery true_value does not match the authoritative truth for $parameter",
                ))
                posterior_mean = _recovery_row_float(row, :posterior_mean)
                posterior_sd = _recovery_row_float(row, :posterior_sd)
                posterior_sd >= 0 || throw(ArgumentError(
                    "recovery posterior_sd must be nonnegative",
                ))
                bias = _recovery_row_float(row, :bias)
                isapprox(
                    bias,
                    posterior_mean - true_value;
                    atol = RECOVERY_NUMERIC_TOLERANCE,
                    rtol = RECOVERY_NUMERIC_TOLERANCE,
                ) || throw(ArgumentError(
                    "recovery bias does not equal posterior_mean - true_value",
                ))
                absolute_bias = _recovery_row_float(row, :absolute_bias)
                isapprox(absolute_bias, abs(bias);
                    atol = RECOVERY_NUMERIC_TOLERANCE,
                    rtol = RECOVERY_NUMERIC_TOLERANCE) || throw(ArgumentError(
                    "recovery absolute_bias does not match abs(bias)",
                ))
                squared_error = _recovery_row_float(row, :squared_error)
                isapprox(squared_error, bias * bias;
                    atol = RECOVERY_NUMERIC_TOLERANCE,
                    rtol = RECOVERY_NUMERIC_TOLERANCE) || throw(ArgumentError(
                    "recovery squared_error does not match bias^2",
                ))
                posterior_lower = _recovery_row_float(row, :posterior_lower)
                posterior_upper = _recovery_row_float(row, :posterior_upper)
                posterior_lower <= posterior_upper || throw(ArgumentError(
                    "recovery posterior interval bounds are reversed",
                ))
                interval_probability = _recovery_row_float(
                    row,
                    :interval_probability,
                )
                lower_probability = _recovery_row_float(
                    row,
                    :lower_probability,
                )
                upper_probability = _recovery_row_float(
                    row,
                    :upper_probability,
                )
                isapprox(
                    interval_probability,
                    GATE_CONTRACT.fixed_contract_and_sampler.
                        recovery_interval_probability;
                    atol = RECOVERY_NUMERIC_TOLERANCE,
                    rtol = 0.0,
                ) || throw(ArgumentError(
                    "recovery interval probability does not match the fixed contract",
                ))
                isapprox(lower_probability,
                    (1.0 - interval_probability) / 2.0;
                    atol = RECOVERY_NUMERIC_TOLERANCE,
                    rtol = 0.0) &&
                    isapprox(upper_probability,
                        1.0 - lower_probability;
                        atol = RECOVERY_NUMERIC_TOLERANCE,
                        rtol = 0.0) || throw(ArgumentError(
                    "recovery interval tail probabilities are inconsistent",
                ))
                interval_width = _recovery_row_float(row, :interval_width)
                interval_width >= 0 || throw(ArgumentError(
                    "recovery interval_width must be nonnegative",
                ))
                isapprox(interval_width, posterior_upper - posterior_lower;
                    atol = RECOVERY_NUMERIC_TOLERANCE,
                    rtol = RECOVERY_NUMERIC_TOLERANCE) || throw(ArgumentError(
                    "recovery interval_width does not match its bounds",
                ))
                covered = _strict_bool(
                    field_or(row, :covered, missing),
                    "recovery covered",
                )
                covered ===
                    (posterior_lower <= true_value <= posterior_upper) ||
                    throw(ArgumentError(
                        "recovery covered flag does not match interval bounds",
                    ))
                quality_gate_applicable = _strict_bool(
                    field_or(row, :quality_gate_applicable, missing),
                    "recovery quality_gate_applicable",
                )
                diagnostic_status = Symbol(field_or(
                    row,
                    :diagnostic_status,
                    :missing,
                ))
                quality_gate_applicable ===
                    expected.quality_gate_applicable || throw(ArgumentError(
                        "recovery applicability does not match the authoritative truth layout",
                    ))
                diagnostic_status === expected.diagnostic_status ||
                    throw(ArgumentError(
                        "recovery diagnostic status does not match the authoritative truth layout",
                    ))
                quality_gate_applicable ||
                    diagnostic_status === :structurally_fixed ||
                    throw(ArgumentError(
                        "non-applicable recovery coordinates must be structurally fixed",
                    ))
                structurally_fixed_exact = quality_gate_applicable ||
                    (absolute_bias <= RECOVERY_NUMERIC_TOLERANCE &&
                        posterior_sd <= RECOVERY_NUMERIC_TOLERANCE &&
                        interval_width <= RECOVERY_NUMERIC_TOLERANCE && covered)
                push!(flattened, (;
                    cell_id,
                    family,
                    canonical_family,
                    condition = required_condition,
                    replication,
                    parameter,
                    raw_block,
                    canonical_block,
                    true_value,
                    posterior_mean,
                    bias,
                    absolute_bias,
                    squared_error,
                    posterior_sd,
                    posterior_lower,
                    posterior_upper,
                    interval_probability,
                    lower_probability,
                    upper_probability,
                    interval_width,
                    covered,
                    quality_gate_applicable,
                    diagnostic_status,
                    structurally_fixed_exact,
                ))
            end
            observed_unique = Tuple(sort!(unique!(observed_blocks); by = string))
            missing_blocks = Tuple(block for block in required_blocks
                if !(block in observed_unique))
            recovery_rows_present = !isempty(parameter_rows)
            recovery_complete = fit_succeeded && recovery_rows_present &&
                parameter_set_complete && isempty(missing_blocks)
            push!(completion_records, (;
                cell_id,
                family,
                canonical_family,
                condition = required_condition,
                replication,
                condition_present,
                fit_present,
                fit_attempted,
                fit_status,
                fit_succeeded,
                recovery_rows_present,
                n_recovery_parameter_rows = length(parameter_rows),
                n_expected_recovery_parameters =
                    length(expected_parameter_names),
                parameter_set_complete,
                duplicate_parameter_names,
                missing_parameter_names,
                unexpected_parameter_names,
                required_canonical_blocks = required_blocks,
                observed_canonical_blocks = observed_unique,
                missing_canonical_blocks = missing_blocks,
                sampler_gate_passed,
                recovery_complete,
            ))
        end
    end

    completion_groups = Dict{
        Tuple{Symbol,Symbol,Symbol},Vector{NamedTuple}}()
    for row in completion_records
        key = (row.cell_id, row.family, row.condition)
        push!(get!(completion_groups, key, NamedTuple[]), row)
    end
    completion_rows = NamedTuple[]
    for key in sort(collect(keys(completion_groups)); by = string)
        rows = completion_groups[key]
        push!(completion_rows, (;
            cell_id = key[1],
            family = key[2],
            canonical_family = canonical_model_family(key[2]),
            condition = key[3],
            n_expected_replications = length(rows),
            n_condition_missing = count(row -> !row.condition_present, rows),
            n_fit_not_attempted = count(row -> row.fit_present &&
                !row.fit_attempted, rows),
            n_fit_failed = count(row -> row.fit_attempted &&
                !row.fit_succeeded, rows),
            n_fit_missing = count(row -> !row.fit_present, rows),
            n_recovery_empty = count(row -> row.fit_succeeded &&
                !row.recovery_rows_present, rows),
            n_recovery_incomplete = count(row -> row.fit_succeeded &&
                row.recovery_rows_present &&
                !row.recovery_complete, rows),
            n_recovery_complete = count(row -> row.recovery_complete, rows),
            n_sampler_gate_passed = count(row -> row.sampler_gate_passed, rows),
            n_sampler_gate_not_evaluated = count(row ->
                !row.fit_attempted, rows),
            n_sampler_gate_failed = count(row -> row.fit_attempted &&
                !row.sampler_gate_passed, rows),
            recovery_complete = all(row -> row.recovery_complete, rows),
            sampler_gate_passed = all(row -> row.sampler_gate_passed, rows),
        ))
    end

    block_groups = Dict{
        Tuple{Symbol,Symbol,Symbol,Symbol},Vector{NamedTuple}}()
    for row in flattened
        key = (row.cell_id, row.family, row.condition, row.canonical_block)
        push!(get!(block_groups, key, NamedTuple[]), row)
    end
    completion_by_key = Dict(
        (row.cell_id, row.family, row.condition) => row
        for row in completion_rows
    )
    block_rows = NamedTuple[]
    for key in sort(collect(keys(block_groups)); by = string)
        rows = block_groups[key]
        completion = completion_by_key[(key[1], key[2], key[3])]
        n = length(rows)
        scored_rows = [row for row in rows if row.quality_gate_applicable]
        fixed_rows = [row for row in rows if !row.quality_gate_applicable]
        n_scored = length(scored_rows)
        n_covered = count(row -> row.covered, scored_rows)
        raw_blocks = Tuple(sort!(unique!(collect(
            row.raw_block for row in rows)); by = string))
        push!(block_rows, (;
            cell_id = key[1],
            family = key[2],
            canonical_family = canonical_model_family(key[2]),
            condition = key[3],
            canonical_block = key[4],
            raw_blocks,
            n_expected_replications = completion.n_expected_replications,
            n_fit_replications = length(unique(row.replication for row in rows)),
            n_parameter_replication_rows = n,
            n_scored_parameter_replication_rows = n_scored,
            n_structurally_fixed_parameter_replication_rows =
                length(fixed_rows),
            mean_bias = n_scored == 0 ? missing :
                arithmetic_mean(row.bias for row in scored_rows),
            mean_absolute_error = n_scored == 0 ? missing :
                arithmetic_mean(row.absolute_bias for row in scored_rows),
            rmse = n_scored == 0 ? missing : sqrt(arithmetic_mean(
                row.squared_error for row in scored_rows)),
            max_absolute_error = n_scored == 0 ? missing :
                maximum(row.absolute_bias for row in scored_rows),
            coverage_rate = n_scored == 0 ? missing : n_covered / n_scored,
            n_covered,
            mean_interval_width = n_scored == 0 ? missing : arithmetic_mean(
                row.interval_width for row in scored_rows),
            structurally_fixed_exact = all(
                row -> row.structurally_fixed_exact,
                fixed_rows,
            ),
            empirical_to_posterior_uncertainty_available =
                completion.n_expected_replications >= 2,
            recovery_complete = completion.recovery_complete,
            sampler_gate_passed = completion.sampler_gate_passed,
        ))
    end

    uncertainty_groups = Dict{
        Tuple{Symbol,Symbol,Symbol,Symbol,String},Vector{NamedTuple}}()
    for row in flattened
        row.quality_gate_applicable || continue
        key = (row.cell_id, row.family, row.condition,
            row.canonical_block, row.parameter)
        push!(get!(uncertainty_groups, key, NamedTuple[]), row)
    end
    uncertainty_rows = NamedTuple[]
    for key in sort(collect(keys(uncertainty_groups)); by = string)
        rows = uncertainty_groups[key]
        biases = [row.bias for row in rows]
        posterior_sds = [row.posterior_sd for row in rows]
        empirical_sd = length(rows) >= 2 ?
            sample_standard_deviation(biases) : missing
        mean_posterior_sd = arithmetic_mean(posterior_sds)
        ratio = ismissing(empirical_sd) || mean_posterior_sd <= 0 ? missing :
            empirical_sd / mean_posterior_sd
        completion = completion_by_key[(key[1], key[2], key[3])]
        fully_replicated = length(rows) == completion.n_expected_replications
        push!(uncertainty_rows, (;
            cell_id = key[1],
            family = key[2],
            canonical_family = canonical_model_family(key[2]),
            condition = key[3],
            canonical_block = key[4],
            parameter = key[5],
            n_replications = length(rows),
            n_expected_replications = completion.n_expected_replications,
            empirical_sd_of_posterior_mean = empirical_sd,
            mean_posterior_sd,
            empirical_to_posterior_sd_ratio = ratio,
            status = fully_replicated && length(rows) >= 2 ? :computed :
                :incomplete_or_insufficient_replications,
        ))
    end

    all_recovery_complete = !isempty(completion_records) &&
        all(row -> row.recovery_complete, completion_records)
    all_sampler_gates_passed = !isempty(completion_records) &&
        all(row -> row.sampler_gate_passed, completion_records)
    return (;
        schema = "bayesianmgmfrm.existing_api_repeated_recovery.v2",
        required_conditions = conditions_required,
        pair_contract_records,
        completion_records,
        completion_rows,
        parameter_replication_rows = flattened,
        block_rows,
        uncertainty_rows,
        summary = (;
            n_paired_replications = length(paired_rows),
            n_expected_condition_fits = length(completion_records),
            n_recovery_complete = count(row -> row.recovery_complete,
                completion_records),
            n_fit_not_attempted = count(row -> row.fit_present &&
                !row.fit_attempted, completion_records),
            n_fit_failed = count(row -> row.fit_attempted &&
                !row.fit_succeeded, completion_records),
            n_fit_or_condition_missing = count(row -> !row.fit_present,
                completion_records),
            n_recovery_empty_or_incomplete = count(row ->
                row.fit_succeeded && !row.recovery_complete,
                completion_records),
            n_sampler_gate_not_evaluated = count(row ->
                !row.fit_attempted, completion_records),
            n_sampler_gate_failed = count(row -> row.fit_attempted &&
                !row.sampler_gate_passed, completion_records),
            n_uncertainty_rows = length(uncertainty_rows),
            n_uncertainty_rows_computed = count(row ->
                row.status === :computed, uncertainty_rows),
            all_structurally_fixed_coordinates_exact = all(
                row -> row.structurally_fixed_exact,
                flattened,
            ),
            pair_keys = sort!(collect(seen_pairs); by = string),
            seed_namespaces = Tuple(sort!(unique!(collect(
                row.seed_namespace for row in pair_contract_records));
                by = string)),
            sampler_contract_sha256s = Tuple(sort!(unique!(collect(
                row.sampler_contract_sha256 for row in
                    pair_contract_records)))),
            all_expected_recovery_fits_completed = all_recovery_complete,
            all_sampler_gates_passed,
        ),
    )
end

function _validated_recovery_gate_freeze(record)
    payload = _contract_payload(
        record,
        "bayesianmgmfrm.existing_api_recovery_gate_freeze.v2",
        "frozen recovery gate contract",
    )
    canonical = recovery_gate_freeze_contract(;
        pilot_threshold_decision = payload.pilot_threshold_decision,
        freeze_source_revision = payload.freeze_source_revision,
        frozen_at_utc = payload.frozen_at_utc,
        freeze_input = payload.pre_response_freeze_input,
        minimum_replications = Int(payload.minimum_replications),
        seed_namespace = Symbol(payload.seed_namespace),
    )
    canonical.content_sha256 == String(record.content_sha256) ||
        throw(ArgumentError(
            "frozen recovery gate contract is not in canonical form",
        ))
    return canonical.payload
end


function _validated_pilot_artifact_content_hash(artifact)
    artifact === nothing && throw(ArgumentError(
        "the frozen recovery gate requires the actual pilot artifact payload",
    ))
    String(field_or(artifact, :schema, "")) ==
        "bayesianmgmfrm.existing_api_design_robustness_stress_grid.v1" ||
        throw(ArgumentError("pilot artifact schema is not supported"))
    Symbol(field_or(artifact, :family, :missing)) ===
        :mfrm_gmfrm_mgmfrm || throw(ArgumentError(
            "pilot artifact family is invalid",
        ))
    Symbol(field_or(artifact, :scope, :missing)) ===
        :existing_static_api_paired_known_truth_design_stress ||
        throw(ArgumentError("pilot artifact scope is invalid"))
    field_or(artifact, :publication_or_registration_action, true) === false &&
        field_or(artifact, :public_claim_release_allowed, true) === false ||
        throw(ArgumentError("pilot artifact public-claim boundary is invalid"))
    package = field_or(artifact, :package, nothing)
    package === nothing && throw(ArgumentError(
        "pilot artifact is missing package provenance",
    ))
    Symbol(field_or(package, :name, :missing)) === :BayesianMGMFRM &&
        String(field_or(package, :version, "")) == project_version() ||
        throw(ArgumentError("pilot artifact package provenance is invalid"))
    generator = field_or(artifact, :generator, nothing)
    generator === nothing && throw(ArgumentError(
        "pilot artifact is missing generator provenance",
    ))
    String(field_or(generator, :script, "")) ==
        "scripts/generate_existing_api_design_robustness_stress_grid.jl" &&
        _sha256_string(
            field_or(generator, :source_sha256, ""),
            "pilot generator source SHA-256",
        ) == file_sha256(@__FILE__) || throw(ArgumentError(
            "pilot artifact generator provenance is invalid",
        ))
    runtime_provenance = field_or(artifact, :runtime_provenance, nothing)
    runtime_provenance === nothing && throw(ArgumentError(
        "pilot artifact is missing runtime/source provenance",
    ))
    portable_json_hash(runtime_provenance) ==
        portable_json_hash(package_runtime_provenance()) ||
        throw(ArgumentError(
            "pilot artifact runtime/source provenance does not match the current environment",
        ))
    field_or(
        runtime_provenance,
        :immutable_vcs_revision_verified,
        true,
    ) === false &&
        field_or(runtime_provenance, :clean_worktree_verified, true) === false &&
        field_or(
            runtime_provenance,
            :raw_draw_cache_identity_verified,
            true,
        ) === false || throw(ArgumentError(
            "pilot artifact runtime provenance overstates unverified evidence",
        ))
    content_hash = field_or(artifact, :content_hash, nothing)
    content_hash === nothing && throw(ArgumentError(
        "pilot artifact is missing its complete-artifact content hash",
    ))
    Symbol(field_or(content_hash, :algorithm, :missing)) === :sha256 &&
        Symbol(field_or(content_hash, :covers, :missing)) ===
            :artifact_without_content_hash || throw(ArgumentError(
                "pilot artifact content-hash contract is invalid",
            ))
    artifact_without_hash = Dict{String,Any}()
    for (key, value) in pairs(artifact)
        String(key) == "content_hash" && continue
        artifact_without_hash[String(key)] = value
    end
    portable_json_hash(artifact_without_hash) == _sha256_string(
        field_or(content_hash, :value, ""),
        "pilot artifact content hash",
    ) || throw(ArgumentError(
        "pilot artifact content hash does not match the complete payload",
    ))
    execution = field_or(artifact, :execution, nothing)
    execution === nothing && throw(ArgumentError(
        "pilot artifact is missing execution metadata",
    ))
    Symbol(field_or(execution, :profile, :missing)) === :pilot ||
        throw(ArgumentError("threshold source artifact must be a pilot run"))
    _strict_bool(
        field_or(execution, :execute_mcmc, missing),
        "pilot execute_mcmc",
    ) || throw(ArgumentError("pilot artifact must contain executed MCMC"))
    requested = Int(field_or(execution, :requested_replications, 0))
    materialized = Int(field_or(execution, :materialized_replications, 0))
    requested >= 30 && materialized == requested || throw(ArgumentError(
        "pilot artifact must contain the complete predeclared replication set",
    ))
    _strict_bool(
        field_or(execution, :paired_fit_execution_completed, missing),
        "pilot paired_fit_execution_completed",
    ) || throw(ArgumentError("pilot fit execution is incomplete"))
    Int(field_or(execution, :n_fit_failed, -1)) == 0 || throw(ArgumentError(
        "pilot artifact contains failed fits",
    ))
    summary = field_or(artifact, :summary, nothing)
    summary === nothing && throw(ArgumentError("pilot summary is missing"))
    _strict_bool(field_or(summary, :passed, missing), "pilot summary passed") ||
        throw(ArgumentError("pilot deterministic checks did not pass"))
    pilot_gate = field_or(artifact, :repeated_recovery_gate, nothing)
    pilot_gate === nothing && throw(ArgumentError(
        "pilot artifact is missing its recovery gate record",
    ))
    Symbol(field_or(pilot_gate, :stage, :missing)) === :pilot ||
        throw(ArgumentError("pilot recovery gate stage is invalid"))
    field_or(pilot_gate, :evaluated, true) === false || throw(ArgumentError(
        "pilot thresholds must not be evaluated as calibration evidence",
    ))
    Symbol(field_or(pilot_gate, :status, :missing)) ===
        :pilot_threshold_freeze_candidate_not_pass_fail_evidence ||
        throw(ArgumentError("pilot recovery gate status is invalid"))
    repeated_recovery = field_or(artifact, :repeated_recovery, nothing)
    repeated_recovery === nothing && throw(ArgumentError(
        "pilot artifact is missing repeated recovery evidence",
    ))
    recovery_summary = field_or(repeated_recovery, :summary, nothing)
    recovery_summary === nothing && throw(ArgumentError(
        "pilot repeated recovery summary is missing",
    ))
    field_or(
        recovery_summary,
        :all_expected_recovery_fits_completed,
        false,
    ) === true || throw(ArgumentError(
        "pilot recovery rows are incomplete",
    ))
    field_or(recovery_summary, :all_sampler_gates_passed, false) === true ||
        throw(ArgumentError("pilot sampler gates did not all pass"))
    n_uncertainty = Int(field_or(
        recovery_summary,
        :n_uncertainty_rows,
        0,
    ))
    n_uncertainty_computed = Int(field_or(
        recovery_summary,
        :n_uncertainty_rows_computed,
        0,
    ))
    n_uncertainty > 0 && n_uncertainty_computed == n_uncertainty ||
        throw(ArgumentError(
            "pilot uncertainty calibration rows are incomplete",
        ))
    deterministic_checks = collect(field_or(
        artifact,
        :deterministic_checks,
        NamedTuple[],
    ))
    isempty(deterministic_checks) && throw(ArgumentError(
        "pilot deterministic checks are missing",
    ))
    all(row -> field_or(row, :passed, false) === true,
        deterministic_checks) || throw(ArgumentError(
        "pilot deterministic checks contain a failure",
    ))
    deterministic_check_names = Tuple(sort!(Symbol[
        Symbol(field_or(row, :check, :missing))
        for row in deterministic_checks
    ]; by = string))
    deterministic_check_names == Tuple(sort!(collect(
        REQUIRED_DETERMINISTIC_CHECKS); by = string)) ||
        throw(ArgumentError(
            "pilot deterministic check roster is incomplete or unexpected",
        ))
    pilot_preflight = field_or(
        artifact,
        :all_requested_replication_skeleton_preflight,
        nothing,
    )
    pilot_preflight === nothing && throw(ArgumentError(
        "pilot artifact is missing its design preflight",
    ))
    String(field_or(pilot_preflight, :schema, "")) ==
        "bayesianmgmfrm.existing_api_design_skeleton_preflight.v2" ||
        throw(ArgumentError("pilot design preflight schema is invalid"))
    _sha256_string(
        field_or(pilot_preflight, :generator_source_sha256, ""),
        "pilot preflight generator source SHA-256",
    ) == file_sha256(@__FILE__) || throw(ArgumentError(
        "pilot preflight source does not match the current generator",
    ))
    Symbol(field_or(pilot_preflight, :profile, :missing)) === :pilot &&
        Int(field_or(pilot_preflight, :requested_replications, 0)) ==
            requested &&
        field_or(pilot_preflight, :passed, false) === true &&
        field_or(pilot_preflight, :mcmc_fit_attempted, true) === false &&
        field_or(pilot_preflight, :response_uniforms_generated, true) ===
            false &&
        field_or(pilot_preflight, :response_scores_generated, true) === false ||
        throw(ArgumentError("pilot design preflight metadata is invalid"))
    canonical_pilot_preflight = _canonical_profile_fit_skeleton_preflight(
        :pilot,
        requested,
    )
    portable_json_hash(pilot_preflight) ==
        portable_json_hash(canonical_pilot_preflight) || throw(ArgumentError(
            "pilot design preflight does not exactly match regeneration from canonical options",
        ))
    pilot_preflight_rows = collect(field_or(
        pilot_preflight,
        :rows,
        NamedTuple[],
    ))
    all(row -> field_or(row, :passed, false) === true &&
        isempty(collect(field_or(row, :failed_checks, Symbol[]))),
        pilot_preflight_rows) || throw(ArgumentError(
        "pilot design preflight contains failed rows",
    ))
    pilot_contract_rows = collect(field_or(
        pilot_preflight,
        :recovery_pair_contract_rows,
        NamedTuple[],
    ))
    portable_json_hash(pilot_contract_rows) == _sha256_string(
        field_or(
            pilot_preflight,
            :recovery_pair_contract_manifest_sha256,
            "",
        ),
        "pilot recovery pair contract manifest SHA-256",
    ) || throw(ArgumentError(
        "pilot recovery pair contract manifest does not match its rows",
    ))
    canonical_pilot_contracts = _canonical_expected_pair_contracts(
        pilot_contract_rows;
        required_seed_namespace = :pilot_threshold,
    )
    _canonical_expected_pair_contracts(
        pilot_preflight_rows;
        required_seed_namespace = :pilot_threshold,
    ) == canonical_pilot_contracts || throw(ArgumentError(
        "pilot preflight source rows and recovery contracts disagree",
    ))
    length(pilot_preflight_rows) == length(canonical_pilot_contracts) ==
        Int(field_or(
            pilot_preflight,
            :n_candidate_family_replication_rows,
            0,
        )) || throw(ArgumentError("pilot preflight row counts disagree"))
    paired_rows = collect(field_or(
        artifact,
        :paired_replication_rows,
        NamedTuple[],
    ))
    isempty(paired_rows) && throw(ArgumentError(
        "pilot artifact is missing paired replication rows",
    ))
    recomputed = aggregate_repeated_recovery(paired_rows)
    portable_json_hash(recomputed) == portable_json_hash(repeated_recovery) ||
        throw(ArgumentError(
            "pilot repeated recovery evidence does not match reaggregation from paired rows",
        ))
    recomputed_pilot_gate = _score_repeated_recovery_aggregate(
        recomputed;
        stage = :pilot,
    )
    portable_json_hash(recomputed_pilot_gate) == portable_json_hash(pilot_gate) ||
        throw(ArgumentError(
            "pilot recovery-gate snapshot does not match reaggregation from paired rows",
        ))
    expected_keys = _canonical_expected_pair_keys([(
        cell_id = roster.cell_id,
        family = roster.family,
        replication,
    ) for roster in canonical_pilot_recovery_roster()
        for replication in 1:requested])
    actual_keys = _canonical_expected_pair_keys([(
        cell_id = key[1],
        family = key[2],
        replication = key[3],
    ) for key in recomputed.summary.pair_keys])
    actual_keys == expected_keys || throw(ArgumentError(
        "pilot paired rows do not match the canonical cell/family/replication roster",
    ))
    recomputed.summary.seed_namespaces == (:pilot_threshold,) ||
        throw(ArgumentError("pilot rows use the wrong seed namespace"))
    _canonical_expected_pair_contracts(
        recomputed.pair_contract_records;
        required_seed_namespace = :pilot_threshold,
    ) == canonical_pilot_contracts || throw(ArgumentError(
        "pilot paired rows do not match their frozen design preflight contracts",
    ))
    recomputed.summary.all_expected_recovery_fits_completed === true ||
        throw(ArgumentError("recomputed pilot recovery is incomplete"))
    recomputed.summary.all_sampler_gates_passed === true ||
        throw(ArgumentError("recomputed pilot sampler gates failed"))
    return portable_json_hash(artifact)
end

function _score_repeated_recovery_aggregate(aggregate;
        stage::Symbol,
        frozen_gate_contract = nothing,
        pilot_artifact = nothing)
    RECOVERY_GATE_SCORER_IMPLEMENTED || error(
        "repeated recovery gate scorer is not implemented",
    )
    stage_contract = recovery_scorer_stage_contract(stage)
    static_rows = [row for row in aggregate.block_rows
        if row.condition === :A_well_specified_static &&
            row.n_scored_parameter_replication_rows > 0]
    static_parameter_rows = [row for row in
        aggregate.parameter_replication_rows
        if row.condition === :A_well_specified_static &&
            row.quality_gate_applicable]
    focal_parameter_rows = [row for row in static_parameter_rows
        if row.canonical_block in FOCAL_RECOVERY_BLOCKS]
    n_static = sum(row.n_scored_parameter_replication_rows for row in static_rows;
        init = 0)
    n_static_covered = sum(row.n_covered for row in static_rows; init = 0)
    static_uncertainty_rows = [row for row in aggregate.uncertainty_rows
        if row.condition === :A_well_specified_static &&
            row.status === :computed &&
            !ismissing(row.empirical_to_posterior_sd_ratio)]
    uncertainty_ratios = Float64[
        row.empirical_to_posterior_sd_ratio for row in static_uncertainty_rows
    ]
    fixed_policy = GATE_CONTRACT.fixed_contract_and_sampler
    coverage_replication_groups = Dict{
        Tuple{Symbol,Symbol,Symbol,Int},Vector{NamedTuple}}()
    coverage_overall_replication_groups = Dict{
        Tuple{Symbol,Symbol,Int},Vector{NamedTuple}}()
    for row in static_parameter_rows
        block_key = (
            row.cell_id,
            row.family,
            row.canonical_block,
            row.replication,
        )
        push!(get!(coverage_replication_groups, block_key, NamedTuple[]), row)
        overall_key = (row.cell_id, row.family, row.replication)
        push!(get!(coverage_overall_replication_groups,
            overall_key, NamedTuple[]), row)
    end
    replication_coverage_rows = [(;
        cell_id = key[1],
        family = key[2],
        canonical_block = key[3],
        replication = key[4],
        n_parameters = length(rows),
        n_covered = count(row -> row.covered, rows),
        coverage_rate = count(row -> row.covered, rows) / length(rows),
    ) for (key, rows) in coverage_replication_groups]
    coverage_block_groups = Dict{
        Tuple{Symbol,Symbol,Symbol},Vector{NamedTuple}}()
    for row in replication_coverage_rows
        key = (row.cell_id, row.family, row.canonical_block)
        push!(get!(coverage_block_groups, key, NamedTuple[]), row)
    end
    coverage_block_rows = NamedTuple[]
    for key in sort(collect(keys(coverage_block_groups)); by = string)
        rows = coverage_block_groups[key]
        cluster = replication_cluster_mean_upper(
            (row.coverage_rate for row in rows),
            fixed_policy.coverage_cluster_z,
        )
        n_parameter_rows = sum(row.n_parameters for row in rows)
        n_covered = sum(row.n_covered for row in rows)
        push!(coverage_block_rows, (;
            cell_id = key[1],
            family = key[2],
            canonical_block = key[3],
            cluster...,
            n_parameter_rows,
            n_covered,
            parameter_row_coverage_rate = n_covered / n_parameter_rows,
            parameter_row_wilson_upper_sensitivity = wilson_upper(
                n_covered,
                n_parameter_rows,
                fixed_policy.coverage_cluster_z,
            ),
        ))
    end
    overall_replication_rates = Float64[
        count(row -> row.covered, rows) / length(rows)
        for rows in values(coverage_overall_replication_groups)
    ]
    overall_coverage_cluster = replication_cluster_mean_upper(
        overall_replication_rates,
        fixed_policy.coverage_cluster_z,
    )
    block_maes = Float64[row.mean_absolute_error for row in static_rows]
    focal_absolute_errors = Float64[
        row.absolute_bias for row in focal_parameter_rows
    ]
    observed = (;
        aggregate_interval_coverage = n_static == 0 ? missing :
            n_static_covered / n_static,
        aggregate_replication_cluster_coverage_mean =
            overall_coverage_cluster.mean,
        aggregate_replication_cluster_coverage_upper =
            overall_coverage_cluster.upper,
        aggregate_parameter_row_wilson_upper_sensitivity =
            n_static == 0 ? missing : wilson_upper(
                n_static_covered,
                n_static,
                fixed_policy.coverage_cluster_z,
            ),
        minimum_block_replication_cluster_coverage_upper =
            isempty(coverage_block_rows) ? missing :
            minimum(row.upper for row in coverage_block_rows),
        block_mae_q95 = isempty(block_maes) ? missing :
            nearest_rank_quantile(
                block_maes,
                fixed_policy.block_mae_quantile_probability,
            ),
        maximum_block_mean_absolute_error_sentinel =
            isempty(block_maes) ? missing : maximum(block_maes),
        focal_absolute_error_q99 = isempty(focal_absolute_errors) ? missing :
            nearest_rank_quantile(
                focal_absolute_errors,
                fixed_policy.focal_absolute_error_quantile_probability,
            ),
        maximum_focal_absolute_error_sentinel =
            isempty(focal_absolute_errors) ? missing :
            maximum(focal_absolute_errors),
        empirical_to_posterior_sd_ratio_q01 =
            isempty(uncertainty_ratios) ? missing : nearest_rank_quantile(
                uncertainty_ratios,
                fixed_policy.uncertainty_ratio_lower_quantile_probability,
            ),
        empirical_to_posterior_sd_ratio_q99 =
            isempty(uncertainty_ratios) ? missing : nearest_rank_quantile(
                uncertainty_ratios,
                fixed_policy.uncertainty_ratio_upper_quantile_probability,
            ),
        minimum_empirical_to_posterior_sd_ratio_sentinel =
            isempty(uncertainty_ratios) ? missing : minimum(uncertainty_ratios),
        maximum_empirical_to_posterior_sd_ratio_sentinel =
            isempty(uncertainty_ratios) ? missing : maximum(uncertainty_ratios),
    )
    freeze_payload = nothing
    freeze_contract_valid = false
    if stage === :calibration && frozen_gate_contract !== nothing
        try
            freeze_payload = _validated_recovery_gate_freeze(
                frozen_gate_contract,
            )
            freeze_contract_valid = true
        catch
            freeze_contract_valid = false
        end
    end
    thresholds = freeze_contract_valid ? freeze_payload.thresholds : (;
        nominal_interval_coverage = GATE_CONTRACT.
            provisional_recovery_and_decision.
            nominal_interval_coverage,
        max_block_mae_quantile = GATE_CONTRACT.
            provisional_recovery_and_decision.max_block_mae_quantile,
        max_focal_absolute_error_quantile = GATE_CONTRACT.
            provisional_recovery_and_decision.
            max_focal_absolute_error_quantile,
        min_empirical_to_posterior_sd_ratio_quantile = GATE_CONTRACT.
            provisional_recovery_and_decision.
            min_empirical_to_posterior_sd_ratio_quantile,
        max_empirical_to_posterior_sd_ratio_quantile = GATE_CONTRACT.
            provisional_recovery_and_decision.
            max_empirical_to_posterior_sd_ratio_quantile,
    )
    observations_available = all(!ismissing, (
        observed.aggregate_replication_cluster_coverage_upper,
        observed.minimum_block_replication_cluster_coverage_upper,
        observed.block_mae_q95,
        observed.focal_absolute_error_q99,
        observed.empirical_to_posterior_sd_ratio_q01,
        observed.empirical_to_posterior_sd_ratio_q99,
    ))
    threshold_results = observations_available && freeze_contract_valid ? (;
        interval_coverage =
            observed.aggregate_replication_cluster_coverage_upper >=
                thresholds.nominal_interval_coverage,
        block_interval_coverage =
            observed.minimum_block_replication_cluster_coverage_upper >=
                thresholds.nominal_interval_coverage,
        block_mean_absolute_error = observed.block_mae_q95 <=
            thresholds.max_block_mae_quantile,
        focal_absolute_error = observed.focal_absolute_error_q99 <=
            thresholds.max_focal_absolute_error_quantile,
        empirical_to_posterior_sd_ratio =
            observed.empirical_to_posterior_sd_ratio_q01 >=
                thresholds.min_empirical_to_posterior_sd_ratio_quantile &&
            observed.empirical_to_posterior_sd_ratio_q99 <=
                thresholds.max_empirical_to_posterior_sd_ratio_quantile,
    ) : (;
        interval_coverage = false,
        block_interval_coverage = false,
        block_mean_absolute_error = false,
        focal_absolute_error = false,
        empirical_to_posterior_sd_ratio = false,
    )
    recovery_complete = aggregate.summary.
        all_expected_recovery_fits_completed === true
    sampler_complete = aggregate.summary.all_sampler_gates_passed === true
    fixed_coordinates_exact = aggregate.summary.
        all_structurally_fixed_coordinates_exact === true
    actual_pair_keys = _canonical_expected_pair_keys([(
        cell_id = key[1],
        family = key[2],
        replication = key[3],
    ) for key in aggregate.summary.pair_keys])
    actual_pair_contracts = freeze_contract_valid ?
        _canonical_expected_pair_contracts(
            aggregate.pair_contract_records,
        ) : NamedTuple[]
    expected_grid_exact = freeze_contract_valid &&
        actual_pair_keys == freeze_payload.expected_pair_keys &&
        actual_pair_contracts == freeze_payload.expected_pair_contracts &&
        Tuple(aggregate.required_conditions) ==
            Tuple(Symbol(value) for value in
                freeze_payload.expected_conditions)
    seed_namespace_exact = freeze_contract_valid &&
        aggregate.summary.seed_namespaces == (freeze_payload.seed_namespace,)
    sampler_contract_exact = freeze_contract_valid &&
        aggregate.summary.sampler_contract_sha256s ==
            (freeze_payload.sampler_contract_sha256,)
    pilot_artifact_contract_consistent = freeze_contract_valid &&
        try
            _validated_pilot_artifact_content_hash(pilot_artifact) ==
                freeze_payload.pilot_artifact_content_sha256
        catch
            false
        end
    pilot_threshold_source_exact = pilot_artifact_contract_consistent &&
        try
            pilot_gate = field_or(
                pilot_artifact,
                :repeated_recovery_gate,
                nothing,
            )
            portable_json_hash(field_or(
                pilot_gate,
                :observed,
                nothing,
            )) == freeze_payload.pilot_observed_sha256 &&
                portable_json_hash(field_or(
                    pilot_gate,
                    :statistical_gate_policy,
                    nothing,
                )) == freeze_payload.pilot_statistical_gate_policy_sha256
        catch
            false
        end
    uncertainty_complete = !isempty(aggregate.uncertainty_rows) &&
        all(row -> row.status === :computed &&
            row.n_replications == row.n_expected_replications &&
            row.n_replications >= (freeze_contract_valid ?
                freeze_payload.minimum_replications :
                MINIMUM_CALIBRATION_REPLICATIONS) &&
            !ismissing(row.empirical_to_posterior_sd_ratio) &&
            isfinite(Float64(row.empirical_to_posterior_sd_ratio)),
            aggregate.uncertainty_rows)
    calibration_authorized = stage_contract.recovery_pass_fail_allowed &&
        freeze_contract_valid && pilot_artifact_contract_consistent &&
        pilot_threshold_source_exact &&
        expected_grid_exact && seed_namespace_exact &&
        sampler_contract_exact
    evaluated = calibration_authorized
    passed = evaluated ? recovery_complete && sampler_complete &&
        fixed_coordinates_exact && uncertainty_complete &&
        observations_available && all(values(threshold_results)) : missing
    status = if stage === :smoke
        :wiring_only_not_recovery_evidence
    elseif stage === :pilot
        :pilot_threshold_freeze_candidate_not_pass_fail_evidence
    elseif frozen_gate_contract === nothing
        :calibration_blocked_frozen_gate_contract_missing
    elseif !freeze_contract_valid
        :calibration_blocked_frozen_gate_contract_invalid
    elseif !pilot_artifact_contract_consistent
        :calibration_blocked_pilot_artifact_not_contract_consistent
    elseif !pilot_threshold_source_exact
        :calibration_blocked_pilot_threshold_source_mismatch
    elseif !expected_grid_exact
        :calibration_blocked_expected_grid_mismatch
    elseif !seed_namespace_exact || !sampler_contract_exact
        :calibration_blocked_execution_contract_mismatch
    elseif passed
        :calibration_recovery_gate_passed
    else
        :calibration_recovery_gate_failed
    end
    return (;
        schema = "bayesianmgmfrm.existing_api_repeated_recovery_gate.v3",
        stage,
        stage_contract,
        status,
        frozen_gate_contract_present = frozen_gate_contract !== nothing,
        freeze_contract_valid,
        pilot_artifact_contract_consistent,
        pilot_threshold_source_exact,
        pilot_artifact_verified = false,
        pilot_artifact_raw_draw_cache_identity_verified = false,
        expected_grid_exact,
        seed_namespace_exact,
        sampler_contract_exact,
        uncertainty_complete,
        structurally_fixed_coordinates_exact = fixed_coordinates_exact,
        evaluated,
        passed,
        observed,
        coverage_block_rows,
        statistical_gate_policy = (;
            nominal_interval_coverage =
                thresholds.nominal_interval_coverage,
            coverage_method =
                :replication_cluster_mean_plus_fixed_z_standard_error,
            coverage_cluster_z = fixed_policy.coverage_cluster_z,
            parameter_row_wilson_is_sensitivity_only = true,
            block_mae_quantile_probability =
                fixed_policy.block_mae_quantile_probability,
            focal_absolute_error_quantile_probability =
                fixed_policy.focal_absolute_error_quantile_probability,
            uncertainty_ratio_quantile_probabilities = (
                fixed_policy.uncertainty_ratio_lower_quantile_probability,
                fixed_policy.uncertainty_ratio_upper_quantile_probability,
            ),
            raw_maxima_are_stress_sentinels_not_pass_fail_statistics = true,
            status = :study_local_fixed_outer_policy,
        ),
        thresholds = (;
            nominal_interval_coverage =
                thresholds.nominal_interval_coverage,
            max_block_mae_quantile = thresholds.max_block_mae_quantile,
            max_focal_absolute_error_quantile =
                thresholds.max_focal_absolute_error_quantile,
            min_empirical_to_posterior_sd_ratio_quantile =
                thresholds.min_empirical_to_posterior_sd_ratio_quantile,
            max_empirical_to_posterior_sd_ratio_quantile =
                thresholds.max_empirical_to_posterior_sd_ratio_quantile,
        ),
        threshold_results = evaluated ? threshold_results : nothing,
        all_expected_recovery_fits_completed = recovery_complete,
        all_sampler_gates_passed = sampler_complete,
        well_specified_static_distributional_gate_passed_under_contract =
            evaluated && passed,
        distributional_recovery_gate_supported = false,
        recovery_claim_supported = false,
        all_conditions_recovery_claim_supported = false,
        recovery_gate_interpretation =
            :distributional_q95_q99_and_replication_cluster_coverage_not_every_cell_parameter_recovery,
        chronology_external_attestation_verified = false,
        full_design_robustness_claim_supported = false,
        public_claim_release_allowed = false,
    )
end

function score_repeated_recovery_gate(paired_rows::AbstractVector;
        stage::Symbol,
        frozen_gate_contract = nothing,
        pilot_artifact = nothing)
    aggregate = aggregate_repeated_recovery(paired_rows)
    result = _score_repeated_recovery_aggregate(
        aggregate;
        stage,
        frozen_gate_contract,
        pilot_artifact,
    )
    return merge(result, (;
        input_contract = :paired_rows_reaggregated_inside_gate,
        aggregate_schema = aggregate.schema,
        aggregate_recomputed_inside_gate = true,
    ))
end

function recovery_summary_record(row)
    return (;
        block = row.group,
        n_parameters = row.n_parameters,
        mean_bias = row.mean_bias,
        mean_absolute_error = row.mean_absolute_error,
        rmse = row.rmse,
        max_absolute_error = row.max_absolute_error,
        coverage_rate = row.coverage_rate,
        nominal_coverage = row.nominal_coverage,
        mean_interval_width = row.mean_interval_width,
    )
end

function recovery_parameter_record(row;
        quality_gate_applicable::Bool = true,
        diagnostic_status::Symbol = :rank_normalized_available)
    return (;
        parameter = row.parameter,
        block = row.block,
        true_value = row.true_value,
        posterior_mean = row.posterior_mean,
        posterior_sd = row.posterior_sd,
        bias = row.bias,
        absolute_bias = row.absolute_bias,
        squared_error = row.squared_error,
        posterior_lower = row.posterior_lower,
        posterior_upper = row.posterior_upper,
        interval_probability = row.interval_probability,
        lower_probability = row.lower_probability,
        upper_probability = row.upper_probability,
        covered = row.covered,
        interval_width = row.interval_width,
        quality_gate_applicable,
        diagnostic_status,
    )
end

function diagnostic_summary_record(summary; family::Symbol = :mfrm)
    min_bulk_ess = field_or(summary, :min_bulk_ess,
        field_or(summary, :min_ess))
    min_tail_ess = field_or(summary, :min_tail_ess,
        field_or(summary, :min_ess))
    return (;
        flag = field_or(summary, :flag),
        passed = field_or(summary, :passed, false),
        diagnostic_contract = field_or(summary, :diagnostic_contract),
        diagnostic_contract_details =
            field_or(summary, :diagnostic_contract_details),
        n_chains = field_or(summary, :n_chains),
        draws_per_chain = field_or(summary, :draws_per_chain),
        total_draws = field_or(summary, :total_draws),
        split_chains = field_or(summary, :split_chains),
        rhat_threshold = field_or(summary, :rhat_threshold),
        ess_threshold = field_or(summary, :ess_threshold),
        max_rhat = field_or(summary, :max_rhat),
        min_bulk_ess,
        min_tail_ess,
        min_ess = field_or(summary, :min_ess,
            ismissing(min_bulk_ess) || ismissing(min_tail_ess) ? missing :
                min(min_bulk_ess, min_tail_ess)),
        n_divergences = field_or(summary, :n_divergences),
        n_max_treedepth = field_or(summary, :n_max_treedepth),
        e_bfmi = field_or(summary, :e_bfmi),
        n_e_bfmi_expected = field_or(summary, :n_e_bfmi_expected),
        n_e_bfmi_available = field_or(summary, :n_e_bfmi_available),
        n_e_bfmi_unavailable = field_or(summary, :n_e_bfmi_unavailable),
        e_bfmi_complete = field_or(summary, :e_bfmi_complete),
        n_nonfinite_logdensity = field_or(summary, :n_nonfinite_logdensity,
            field_or(summary, :n_nonfinite_log_posterior)),
        n_failed_direct_constraints =
            field_or(summary, :n_failed_direct_constraints,
                family === :mfrm ? 0 : missing),
    )
end

function execute_fit(runtime, likelihood, config, profile, sampler_seed)
    sampler = config.sampler
    init = if profile === :smoke
        runtime.family === :mfrm ? runtime.truth.direct : runtime.truth.raw
    else
        nothing
    end
    common = (;
        backend = sampler.backend,
        ndraws = sampler.draws,
        warmup = sampler.warmup,
        chains = sampler.chains,
        step_size = sampler.step_size,
        init,
        seed = sampler_seed,
        target_accept = sampler.target_accept,
        max_depth = sampler.max_depth,
        max_energy_error = sampler.max_energy_error,
        metric = sampler.metric,
        ad_backend = sampler.ad_backend,
        init_jitter = sampler.init_jitter,
        progress = false,
    )
    try
        fit = if runtime.family === :mfrm
            BayesianMGMFRM.fit(likelihood.spec; common...)
        else
            BayesianMGMFRM.fit(
                likelihood.spec;
                experimental = true,
                common...,
                split_chains = sampler.split_chains,
                rhat_threshold = sampler.rhat_threshold,
                ess_threshold = sampler.ess_threshold,
            )
        end
        diagnostics = BayesianMGMFRM.diagnostics(
            fit;
            split_chains = sampler.split_chains,
            rhat_threshold = sampler.rhat_threshold,
            ess_threshold = sampler.ess_threshold,
        )
        recovery = BayesianMGMFRM.parameter_recovery(
            fit,
            runtime.truth.direct;
            interval = 0.90,
            parameter_space = :direct,
        )
        by_block = BayesianMGMFRM.parameter_recovery_summary(recovery; by = :block)
        direct_diagnostic_by_parameter = Dict{String,NamedTuple}()
        if runtime.family !== :mfrm
            for row in diagnostics.direct_parameter_rows
                direct_diagnostic_by_parameter[String(row.parameter)] = row
            end
        end
        return (;
            status = :completed,
            succeeded = true,
            evidence_status = sampler.evidence_status,
            diagnostics = diagnostic_summary_record(
                diagnostics.summary;
                family = runtime.family,
            ),
            recovery_parameter_rows = [begin
                diagnostic = get(
                    direct_diagnostic_by_parameter,
                    String(row.parameter),
                    nothing,
                )
                recovery_parameter_record(
                    row;
                    quality_gate_applicable = diagnostic === nothing ? true :
                        Bool(diagnostic.quality_gate_applicable),
                    diagnostic_status = diagnostic === nothing ?
                        :rank_normalized_available :
                        Symbol(diagnostic.diagnostic_status),
                )
            end for row in recovery],
            recovery_by_block = [recovery_summary_record(row) for row in by_block],
        )
    catch err
        return (;
            status = :failed,
            succeeded = false,
            evidence_status = sampler.evidence_status,
            error_type = Symbol(nameof(typeof(err))),
            message = portable_error_message(err),
            diagnostics = nothing,
            recovery_parameter_rows = NamedTuple[],
            recovery_by_block = NamedTuple[],
        )
    end
end

function order_misspecification_scenario(cell)
    cell.presentation_order === :random && return :M1_order_effect_random_sequence
    cell.presentation_order === :high_to_low &&
        return :M2_order_effect_reinforcing_ability_sequence
    cell.presentation_order === :low_to_high &&
        return :M3_order_effect_opposing_ability_sequence
    return :M4_order_effect_block_clustered_sequence
end

function condition_record(runtime, condition, probabilities, scores,
        config, execute, profile, sampler_seed)
    smoke = likelihood_smoke(runtime, scores, config)
    fit_record = execute ?
        execute_fit(runtime, smoke, config, profile, sampler_seed) :
        (;
            status = :planned_not_run,
            succeeded = false,
            reason = :mcmc_requires_explicit_execute,
            evidence_status = :not_evaluated,
            diagnostics = nothing,
            recovery_parameter_rows = NamedTuple[],
            recovery_by_block = NamedTuple[],
        )
    return (;
        condition,
        dgp = condition === :A_well_specified_static ? (;
            study_track = :A_well_specified_static_recovery,
            misspecification_scenario = :not_applicable,
            static_model = true,
            unmodeled_order_effect = false,
            order_effect_slope = 0.0,
        ) : (;
            study_track = :B_static_misspecification_boundary,
            misspecification_scenario =
                order_misspecification_scenario(runtime.cell),
            static_model = false,
            unmodeled_order_effect = true,
            order_effect_slope = ORDER_EFFECT_SLOPE,
        ),
        probability_sha256 = portable_json_hash(probabilities),
        scores_sha256 = portable_json_hash(scores),
        score_summary = score_summary(
            scores,
            runtime.design.spec.data.category_levels,
        ),
        likelihood_smoke = (;
            finite = smoke.finite,
            loglikelihood_at_static_truth = smoke.loglikelihood_at_static_truth,
            maximum_absolute_pointwise_loglikelihood =
                smoke.maximum_absolute_pointwise_loglikelihood,
        ),
        fit = fit_record,
    )
end

function paired_replication(runtime, replication, config, execute, profile, cell_index)
    seeds = replication_seeds(profile, replication, cell_index, runtime.family)
    runtime.materialized.skeleton_seed == seeds.skeleton || error(
        "runtime skeleton seed does not match the replication seed namespace",
    )
    simulation_seed = seeds.simulation
    sampler_seed = seeds.sampler
    order_probabilities = order_effect_probabilities(
        runtime.probabilities,
        runtime.materialized.events,
        config,
    )
    levels = runtime.design.spec.data.category_levels
    uniforms = rand(MersenneTwister(simulation_seed),
        length(runtime.materialized.events))
    static_scores = sample_scores(runtime.probabilities, uniforms, levels)
    order_scores = sample_scores(order_probabilities, uniforms, levels)
    static_condition = condition_record(
        runtime,
        :A_well_specified_static,
        runtime.probabilities,
        static_scores,
        config,
        execute,
        profile,
        sampler_seed,
    )
    order_condition = condition_record(
        runtime,
        :B_unmodeled_order_effect,
        order_probabilities,
        order_scores,
        config,
        execute,
        profile,
        sampler_seed,
    )
    truth_contract = recovery_truth_contract(
        runtime.design,
        runtime.truth.direct,
    )
    sampler_contract = recovery_sampler_contract(config.sampler)
    return (;
        pair_id = Symbol("$(runtime.cell.cell_id)__$(runtime.family)__rep$(replication)"),
        cell_id = runtime.cell.cell_id,
        family = runtime.family,
        replication,
        seed_namespace = seeds.namespace,
        skeleton_seed = seeds.skeleton,
        requested_threshold_spacing = runtime.cell.threshold_spacing,
        achieved_design_resolution_status = runtime.artifact.design_metrics.
            requested_vs_achieved.status,
        achieved_design_fit_eligible = runtime.artifact.design_metrics.
            requested_vs_achieved.fit_eligible,
        fit_plan = runtime.artifact.design_metrics.requested_vs_achieved.
            fit_eligible ? :eligible_when_profile_selected :
            :planned_only_not_fit_under_achieved_design,
        design_sha256 = runtime.artifact.design_sha256,
        rating_assignment_design_sha256 =
            runtime.artifact.design_sha256,
        event_set_sha256 = runtime.artifact.event_skeleton.event_set_sha256,
        ordered_event_skeleton_sha256 =
            runtime.artifact.event_skeleton.ordered_event_skeleton_sha256,
        resampled_skeleton_components =
            runtime.materialized.skeleton_resampling,
        direct_truth_sha256 = runtime.artifact.truth.direct_sha256,
        recovery_truth_contract = truth_contract,
        recovery_sampler_contract = sampler_contract,
        static_probability_sha256 = runtime.artifact.static_probability_sha256,
        common_random_numbers = true,
        simulation_seed,
        category_support_conditioning = false,
        category_support_resampling = false,
        uniform_variates_sha256 = portable_json_hash(uniforms),
        common_sampler_seed = sampler_seed,
        conditions = [static_condition, order_condition],
        paired_score_change_rate =
            arithmetic_mean(static_scores .!= order_scores),
    )
end

function paired_recovery_contrasts(rows)
    contrasts = NamedTuple[]
    for pair in rows
        conditions = pair.conditions
        length(conditions) == 2 || continue
        a = conditions[1].fit
        b = conditions[2].fit
        a.succeeded && b.succeeded || continue
        b_by_block = Dict(row.block => row for row in b.recovery_by_block)
        for arow in a.recovery_by_block
            haskey(b_by_block, arow.block) || continue
            brow = b_by_block[arow.block]
            push!(contrasts, (;
                pair_id = pair.pair_id,
                cell_id = pair.cell_id,
                family = pair.family,
                replication = pair.replication,
                block = arow.block,
                order_minus_static_mean_absolute_error =
                    brow.mean_absolute_error - arow.mean_absolute_error,
                order_minus_static_rmse = brow.rmse - arow.rmse,
                order_minus_static_coverage_rate =
                    brow.coverage_rate - arow.coverage_rate,
                order_minus_static_interval_width =
                    brow.mean_interval_width - arow.mean_interval_width,
            ))
        end
    end
    return contrasts
end

function mean_field(rows, field)
    return arithmetic_mean(Float64(getproperty(row, field)) for row in rows)
end

function aggregate_contrasts(contrasts)
    groups = Dict{Tuple{Symbol,Symbol,Symbol},Vector{NamedTuple}}()
    for row in contrasts
        key = (row.cell_id, row.family, row.block)
        push!(get!(groups, key, NamedTuple[]), row)
    end
    out = NamedTuple[]
    for key in sort(collect(keys(groups)); by = string)
        rows = groups[key]
        push!(out, (;
            cell_id = key[1],
            family = key[2],
            block = key[3],
            n_paired_replications = length(rows),
            mean_order_minus_static_mean_absolute_error =
                mean_field(rows, :order_minus_static_mean_absolute_error),
            mean_order_minus_static_rmse =
                mean_field(rows, :order_minus_static_rmse),
            mean_order_minus_static_coverage_rate =
                mean_field(rows, :order_minus_static_coverage_rate),
            mean_order_minus_static_interval_width =
                mean_field(rows, :order_minus_static_interval_width),
        ))
    end
    return out
end

function empirical_posterior_uncertainty_rows(paired_rows)
    groups = Dict{Tuple{Symbol,Symbol,Symbol,Symbol,String},Vector{NamedTuple}}()
    for pair in paired_rows, condition in pair.conditions
        condition.fit.succeeded || continue
        for row in condition.fit.recovery_parameter_rows
            field_or(row, :quality_gate_applicable, true) === true || continue
            key = (
                pair.cell_id,
                pair.family,
                condition.condition,
                row.block,
                String(row.parameter),
            )
            push!(get!(groups, key, NamedTuple[]), row)
        end
    end
    out = NamedTuple[]
    for key in sort(collect(keys(groups)); by = string)
        rows = groups[key]
        posterior_means = [Float64(row.posterior_mean) for row in rows]
        posterior_sds = [Float64(row.posterior_sd) for row in rows]
        empirical_sd = length(rows) >= 2 ?
            sample_standard_deviation(posterior_means) : missing
        mean_posterior_sd = arithmetic_mean(posterior_sds)
        ratio = ismissing(empirical_sd) || mean_posterior_sd <= 0 ? missing :
            empirical_sd / mean_posterior_sd
        push!(out, (;
            cell_id = key[1],
            family = key[2],
            condition = key[3],
            block = key[4],
            parameter = key[5],
            n_replications = length(rows),
            empirical_sd_of_posterior_mean = empirical_sd,
            mean_posterior_sd,
            empirical_to_posterior_sd_ratio = ratio,
            status = length(rows) >= 2 && !ismissing(ratio) ? :computed :
                :insufficient_replications_or_zero_posterior_sd,
        ))
    end
    return out
end

function row_permutation_equivariance_check(runtime, contract_id, config)
    events = runtime.materialized.events
    scores = placeholder_scores(length(events), config.n_categories)
    n = length(events)
    split = div(n, 2)
    permutation = vcat(collect(1:split), reverse(collect((split + 1):n)))
    permuted_table = table_from_events(events[permutation], scores[permutation])
    permuted_data = facet_data(permuted_table)
    permuted_spec = family_spec(permuted_data, runtime.family, config)
    permuted_design = family_design(permuted_spec, runtime.family)
    name_to_truth = Dict(name => value for (name, value) in
        zip(runtime.design.parameter_names, runtime.truth.direct))
    same_parameter_name_set =
        Set(runtime.design.parameter_names) == Set(permuted_design.parameter_names)
    permuted_truth = same_parameter_name_set ?
        [name_to_truth[name] for name in permuted_design.parameter_names] : Float64[]
    original = BayesianMGMFRM.pointwise_loglikelihood_matrix(
        runtime.design,
        reshape(runtime.truth.direct, 1, :);
        parameter_space = :direct,
    )
    permuted = same_parameter_name_set ?
        BayesianMGMFRM.pointwise_loglikelihood_matrix(
            permuted_design,
            reshape(permuted_truth, 1, :);
            parameter_space = :direct,
        ) : fill(Inf, 1, n)
    aligned_error = maximum(abs.(vec(permuted) .- vec(original)[permutation]))
    total_error = abs(sum(permuted) - sum(original))
    tolerance = 1.0e-12
    total_reduction_tolerance = 1.0e-10
    return (;
        contract_id,
        cell_id = runtime.cell.cell_id,
        family = runtime.family,
        passed = same_parameter_name_set && aligned_error <= tolerance &&
            total_error <= total_reduction_tolerance,
        same_parameter_name_set,
        n_observations = n,
        maximum_aligned_pointwise_loglikelihood_error = aligned_error,
        absolute_total_loglikelihood_error = total_error,
        tolerance,
        total_reduction_tolerance,
        interpretation = :same_scores_and_events_pure_row_permutation,
    )
end

function event_value_map(events, values)
    length(events) == length(values) || error("event/value length mismatch")
    return Dict(event_identity(row) => values[index]
        for (index, row) in pairs(events))
end

function named_truth_for_design(runtime, design)
    truth_by_name = Dict(name => value for (name, value) in
        zip(runtime.design.parameter_names, runtime.truth.direct))
    same_names = Set(keys(truth_by_name)) == Set(design.parameter_names)
    return same_names ? [truth_by_name[name] for name in design.parameter_names] :
        Float64[]
end

function scored_pointwise(runtime, scores, config)
    data = BayesianMGMFRM._facet_data_with_scores(runtime.design.spec.data, scores)
    spec = family_spec(data, runtime.family, config)
    design = family_design(spec, runtime.family)
    truth = named_truth_for_design(runtime, design)
    isempty(truth) && error("placement control changed the parameter name set")
    pointwise = vec(BayesianMGMFRM.pointwise_loglikelihood_matrix(
        design,
        reshape(truth, 1, :);
        parameter_space = :direct,
    ))
    return (; design, truth, pointwise)
end

function c2p_placement_contrast_check(early_runtime, distributed_runtime,
        config, control_seed::Int)
    early_events = early_runtime.materialized.events
    distributed_events = distributed_runtime.materialized.events
    early_event_set = canonical_event_set(early_events)
    distributed_event_set = canonical_event_set(distributed_events)
    same_event_set = early_event_set == distributed_event_set
    identities = sort(collect(event_identity(row) for row in early_events);
        by = row -> (row.target_index, row.rater_index))
    rng = MersenneTwister(control_seed)
    uniform_by_event = Dict(identity => rand(rng) for identity in identities)
    early_probability_by_event = event_value_map(
        early_events,
        [collect(early_runtime.probabilities[index, :])
            for index in axes(early_runtime.probabilities, 1)],
    )
    distributed_probability_by_event = event_value_map(
        distributed_events,
        [collect(distributed_runtime.probabilities[index, :])
            for index in axes(distributed_runtime.probabilities, 1)],
    )
    probability_error = same_event_set ? maximum(
        maximum(abs.(early_probability_by_event[identity] .-
            distributed_probability_by_event[identity])) for identity in identities) : Inf
    levels = early_runtime.design.spec.data.category_levels
    score_by_event = Dict(identity => only(sample_scores(
        reshape(early_probability_by_event[identity], 1, :),
        [uniform_by_event[identity]],
        levels,
    )) for identity in identities)
    early_scores = [score_by_event[event_identity(row)] for row in early_events]
    distributed_scores = [score_by_event[event_identity(row)]
        for row in distributed_events]
    early_scored = scored_pointwise(early_runtime, early_scores, config)
    distributed_scored = scored_pointwise(
        distributed_runtime, distributed_scores, config)
    early_loglikelihood = event_value_map(early_events, early_scored.pointwise)
    distributed_loglikelihood = event_value_map(
        distributed_events, distributed_scored.pointwise)
    aligned_error = same_event_set ? maximum(abs(
        early_loglikelihood[identity] - distributed_loglikelihood[identity])
        for identity in identities) : Inf
    early_positions = event_value_map(early_events,
        [row.rater_position for row in early_events])
    distributed_positions = event_value_map(distributed_events,
        [row.rater_position for row in distributed_events])
    # The common flag is constant for every rater of a target. Deriving the
    # subset directly from the event rows avoids relying on row order.
    common_identities = sort(collect(event_identity(row) for row in early_events
        if row.is_common_linking_target);
        by = row -> (row.target_index, row.rater_index))
    assignment_record = (events, scores) -> sort([(;
        target_index = row.target_index,
        rater_index = row.rater_index,
        uniform = uniform_by_event[event_identity(row)],
        score = scores[index],
    ) for (index, row) in pairs(events)]; by = row ->
        (row.target_index, row.rater_index))
    early_assignment_record = assignment_record(early_events, early_scores)
    distributed_assignment_record = assignment_record(
        distributed_events, distributed_scores)
    truth_record_early = sort([(name = String(name), value = value)
        for (name, value) in zip(early_runtime.design.parameter_names,
            early_runtime.truth.direct)]; by = row -> row.name)
    truth_record_distributed = sort([(name = String(name), value = value)
        for (name, value) in zip(distributed_runtime.design.parameter_names,
            distributed_runtime.truth.direct)]; by = row -> row.name)
    early_common_occasions = [row.occasion for row in early_events
        if row.is_common_linking_target]
    distributed_common_occasions = Set(row.occasion for row in distributed_events
        if row.is_common_linking_target)
    tolerance = 1.0e-12
    same_truth = truth_record_early == truth_record_distributed
    positions_recomputed = any(early_positions[identity] !=
        distributed_positions[identity] for identity in common_identities)
    distributed_spans_sequence = "early" in distributed_common_occasions &&
        "late" in distributed_common_occasions
    placement_realized = !isempty(early_common_occasions) &&
        all(==("early"), early_common_occasions) &&
        distributed_spans_sequence
    assignment_hash_early = portable_json_hash(early_assignment_record)
    assignment_hash_distributed = portable_json_hash(distributed_assignment_record)
    same_assignment = early_assignment_record == distributed_assignment_record
    event_set_hash_early = portable_json_hash(early_event_set)
    event_set_hash_distributed = portable_json_hash(distributed_event_set)
    truth_hash_early = portable_json_hash(truth_record_early)
    truth_hash_distributed = portable_json_hash(truth_record_distributed)
    common_hash_early = early_runtime.artifact.event_skeleton.
        common_target_rater_events_sha256
    common_hash_distributed = distributed_runtime.artifact.event_skeleton.
        common_target_rater_events_sha256
    return (;
        contract_id = :C2P,
        family = early_runtime.family,
        early_cell_id = early_runtime.cell.cell_id,
        distributed_cell_id = distributed_runtime.cell.cell_id,
        passed = same_event_set && same_truth && same_assignment &&
            positions_recomputed &&
            placement_realized && probability_error <= tolerance &&
            aligned_error <= tolerance && common_hash_early == common_hash_distributed,
        same_event_set,
        same_common_target_rater_events = common_hash_early == common_hash_distributed,
        same_named_truth = same_truth,
        same_uniform_score_assignment_by_named_event = same_assignment,
        positions_and_occasions_recomputed = positions_recomputed,
        early_only_realized = all(==("early"), early_common_occasions),
        distributed_spans_early_and_late = distributed_spans_sequence,
        distributed_covers_all_terciles =
            distributed_common_occasions == Set(("early", "middle", "late")),
        event_set_sha256_early = event_set_hash_early,
        event_set_sha256_distributed = event_set_hash_distributed,
        common_target_rater_events_sha256_early = common_hash_early,
        common_target_rater_events_sha256_distributed = common_hash_distributed,
        named_truth_sha256_early = truth_hash_early,
        named_truth_sha256_distributed = truth_hash_distributed,
        uniform_score_assignment_sha256_early = assignment_hash_early,
        uniform_score_assignment_sha256_distributed = assignment_hash_distributed,
        maximum_aligned_static_probability_error = probability_error,
        maximum_aligned_pointwise_loglikelihood_error = aligned_error,
        tolerance,
        interpretation = :same_named_events_truth_uniforms_and_scores_placement_only,
    )
end

function full_factorial_size()
    # Mirrors the declared plan axes, then adds the two explicitly separated
    # budget policies and paired data-generating conditions.
    return length(FAMILIES) * 7 * 5 * 5 * 5 * 4 * 3 * 3 * 3 * 2 * 2
end

function design_cell_manifest(cell)
    return (;
        cell_id = cell.cell_id,
        tier = cell.tier,
        role = cell.role,
        rating_topology = cell.rating_topology,
        assignment = cell.assignment,
        routine_ratings_per_target = cell.routine_ratings_per_target,
        requested_common_linking_fraction = cell.common_linking_fraction,
        common_linking_support = cell.common_linking_support,
        common_linking_placement = cell.common_linking_placement,
        controlled_benchmark_status = :not_materialized,
        presentation_order = cell.presentation_order,
        budget_policy = cell.budget_policy,
        budget_implementation = cell.budget_policy === :fixed_total_target_displacement ?
            :fixed_total_target_displacement :
            (cell.budget_policy === :additive ?
                :additive_common_linking_ratings : cell.budget_policy),
        ability_sd = cell.ability_sd,
        rater_severity_sd = cell.rater_severity_sd,
        threshold_spacing = cell.threshold_spacing,
        expected_prefit_rejection = cell.expected_prefit_rejection,
        model_families = cell.families,
        smoke_fit = cell.smoke_fit,
        pilot_fit = cell.pilot_fit,
    )
end

function build_artifact(options)
    config = profile_config(options.profile)
    prerequisite = plan_reference()
    cell_index = Dict(cell.cell_id => index for (index, cell) in pairs(DESIGN_CELLS))
    all_skeleton_preflight = profile_fit_skeleton_preflight(
        options,
        config,
        cell_index,
    )
    if options.execute && !all_skeleton_preflight.passed
        first_failure = first(all_skeleton_preflight.failure_rows)
        error("all-replication achieved-design hard gate failed before score " *
            "generation/MCMC at $(first_failure.cell_id)/" *
            "$(first_failure.family)/rep$(first_failure.replication): " *
            "$(first_failure.failed_checks)")
    end
    model_cells = NamedTuple[]
    runtimes = NamedTuple[]
    for cell in DESIGN_CELLS, family in cell.families
        reference_seed = replication_seeds(
            options.profile,
            1,
            cell_index[cell.cell_id],
            family,
        ).skeleton
        preflight = preflight_model_cell(
            cell,
            family,
            config;
            skeleton_seed = reference_seed,
        )
        push!(model_cells, preflight.artifact)
        preflight.runtime === nothing || push!(runtimes, preflight.runtime)
    end
    permutation_runtimes = [runtime for runtime in runtimes
        if runtime.cell.cell_id in (
            :C0_balanced_random_double_rated,
            :C2A_nested_5pct_link_early_additive,
        )]
    row_permutation_checks = [row_permutation_equivariance_check(
        runtime,
        runtime.cell.cell_id === :C0_balanced_random_double_rated ?
            :C0P_pure_row_permutation : :C2A_pure_row_permutation,
        config,
    ) for runtime in permutation_runtimes]
    c2a_runtimes = sort([runtime for runtime in runtimes
        if runtime.cell.cell_id === :C2A_nested_5pct_link_early_additive];
        by = runtime -> findfirst(==(runtime.family), FAMILIES))
    c2p_preflights = [preflight_model_cell(
        C2P_CONTROL_CELL,
        early_runtime.family,
        config;
        skeleton_seed = early_runtime.materialized.skeleton_seed,
    ) for early_runtime in c2a_runtimes]
    c2p_runtimes = [row.runtime for row in c2p_preflights]
    c2p_placement_checks = [c2p_placement_contrast_check(
        early_runtime,
        distributed_runtime,
        config,
        component_seed(early_runtime.materialized.skeleton_seed, 9),
    ) for (early_runtime, distributed_runtime) in
        zip(c2a_runtimes, c2p_runtimes)]
    skeleton_probe_reference = only(runtime for runtime in c2a_runtimes
        if runtime.family === :mfrm)
    skeleton_probe_seed = replication_seeds(
        options.profile,
        2,
        cell_index[skeleton_probe_reference.cell.cell_id],
        skeleton_probe_reference.family,
    ).skeleton
    skeleton_probe_resampled = preflight_model_cell(
        skeleton_probe_reference.cell,
        skeleton_probe_reference.family,
        config;
        skeleton_seed = skeleton_probe_seed,
    ).runtime
    skeleton_resampling_probe = (;
        cell_id = skeleton_probe_reference.cell.cell_id,
        family = skeleton_probe_reference.family,
        reference_replication = 1,
        resampled_replication = 2,
        reference_seed = skeleton_probe_reference.materialized.skeleton_seed,
        resampled_seed = skeleton_probe_resampled.materialized.skeleton_seed,
        reference_event_set_sha256 =
            skeleton_probe_reference.artifact.event_skeleton.event_set_sha256,
        resampled_event_set_sha256 =
            skeleton_probe_resampled.artifact.event_skeleton.event_set_sha256,
        reference_ordered_event_skeleton_sha256 = skeleton_probe_reference.
            artifact.event_skeleton.ordered_event_skeleton_sha256,
        resampled_ordered_event_skeleton_sha256 = skeleton_probe_resampled.
            artifact.event_skeleton.ordered_event_skeleton_sha256,
        event_assignment_changed = skeleton_probe_reference.artifact.
            event_skeleton.event_set_sha256 != skeleton_probe_resampled.artifact.
            event_skeleton.event_set_sha256,
        within_rater_order_changed = skeleton_probe_reference.artifact.
            event_skeleton.ordered_event_skeleton_sha256 !=
            skeleton_probe_resampled.artifact.event_skeleton.
            ordered_event_skeleton_sha256,
        passed = skeleton_probe_reference.materialized.skeleton_seed !=
            skeleton_probe_resampled.materialized.skeleton_seed &&
            skeleton_probe_reference.artifact.event_skeleton.event_set_sha256 !=
            skeleton_probe_resampled.artifact.event_skeleton.event_set_sha256 &&
            skeleton_probe_reference.artifact.event_skeleton.
                ordered_event_skeleton_sha256 != skeleton_probe_resampled.
                artifact.event_skeleton.ordered_event_skeleton_sha256,
        interpretation = :replication_seed_resamples_assignment_and_order_skeleton,
    )

    negative_controls = [row.validation for row in model_cells
        if row.axes.expected_prefit_rejection]
    positive_cells = [row for row in model_cells if !row.axes.expected_prefit_rejection]
    selected_runtimes = options.execute ?
        [runtime for runtime in runtimes
            if execution_selected(runtime.cell, options.profile) &&
                runtime.artifact.design_metrics.requested_vs_achieved.fit_eligible] :
        runtimes
    materialized_replications = options.execute ? options.requested_replications : 1
    paired_rows = NamedTuple[]
    for replication in 1:materialized_replications, reference_runtime in selected_runtimes
        runtime = if replication == 1
            reference_runtime
        else
            seed = replication_seeds(
                options.profile,
                replication,
                cell_index[reference_runtime.cell.cell_id],
                reference_runtime.family,
            ).skeleton
            preflight_model_cell(
                reference_runtime.cell,
                reference_runtime.family,
                config;
                skeleton_seed = seed,
            ).runtime
        end
        if options.execute && options.profile !== :smoke &&
                !runtime.artifact.design_metrics.requested_vs_achieved.fit_eligible
            error("pilot/evaluation fit cell $(runtime.cell.cell_id)/" *
                "$(runtime.family)/rep$(replication) failed the achieved-design gate")
        end
        push!(paired_rows, paired_replication(
            runtime,
            replication,
            config,
            options.execute,
            options.profile,
            cell_index[runtime.cell.cell_id],
        ))
    end

    pair_contrasts = paired_recovery_contrasts(paired_rows)
    aggregate = aggregate_contrasts(pair_contrasts)
    uncertainty_rows = empirical_posterior_uncertainty_rows(paired_rows)
    repeated_recovery = aggregate_repeated_recovery(paired_rows)
    repeated_recovery_gate = score_repeated_recovery_gate(
        paired_rows;
        stage = options.profile,
    )
    fit_records = [condition.fit for pair in paired_rows for condition in pair.conditions]
    n_fit_attempted = options.execute ? length(fit_records) : 0
    n_fit_succeeded = options.execute ? count(row -> row.succeeded, fit_records) : 0
    n_fit_failed = options.execute ? n_fit_attempted - n_fit_succeeded : 0

    checks = [
        (;
            check = :prerequisite_plan_passed,
            passed = prerequisite.summary_passed,
        ),
        (;
            check = :mandatory_plus_fractional_subset_not_full_factorial,
            passed = length(model_cells) < full_factorial_size(),
            selected_model_design_cells = length(model_cells),
            candidate_full_factorial_cells = full_factorial_size(),
        ),
        (;
            check = :positive_cells_compile_and_have_finite_probabilities,
            passed = all(row -> row.validation.passed &&
                row.validation.compiled, positive_cells),
        ),
        (;
            check = :negative_controls_rejected_before_sampling,
            passed = all(row -> row.passed && !row.fit_attempted, negative_controls),
        ),
        (;
            check = :rating_budget_accounting,
            passed = all(row -> row.design_metrics.rating_budget_accounting_passed,
                positive_cells),
        ),
        (;
            check = :three_family_s0p_s2p_row_permutation_equivariance,
            passed = length(row_permutation_checks) == 2length(FAMILIES) &&
                all(row -> row.passed, row_permutation_checks),
            n_checks = length(row_permutation_checks),
            tolerance = 1.0e-12,
        ),
        (;
            check = :three_family_c2p_same_event_placement_contrast,
            passed = length(c2p_placement_checks) == length(FAMILIES) &&
                all(row -> row.passed, c2p_placement_checks),
            n_checks = length(c2p_placement_checks),
            tolerance = 1.0e-12,
        ),
        (;
            check = :profile_fit_cells_meet_requested_vs_achieved_gate,
            passed = all_skeleton_preflight.passed,
            all_requested_replication_skeletons_preflighted = true,
            hard_gate_applies_before_execute = true,
            execute_requested = options.execute,
            n_profile_fit_cells =
                all_skeleton_preflight.n_candidate_family_replication_rows,
            n_fit_eligible_cells = all_skeleton_preflight.n_passed,
            n_failed_cells = all_skeleton_preflight.n_failed,
        ),
        (;
            check = :replication_seed_resamples_assignment_and_order_skeleton,
            passed = skeleton_resampling_probe.passed,
            reference_replication = 1,
            resampled_replication = 2,
        ),
        (;
            check = :paired_static_and_order_effect_conditions_separated,
            passed = all(pair ->
                pair.common_random_numbers &&
                pair.conditions[1].condition === :A_well_specified_static &&
                !pair.conditions[1].dgp.unmodeled_order_effect &&
                pair.conditions[2].condition === :B_unmodeled_order_effect &&
                pair.conditions[2].dgp.unmodeled_order_effect,
                paired_rows),
        ),
        (;
            check = :known_truth_likelihood_smoke_finite,
            passed = all(condition -> condition.likelihood_smoke.finite,
                (condition for pair in paired_rows for condition in pair.conditions)),
        ),
        (;
            check = :default_path_does_not_attempt_mcmc,
            passed = options.execute || n_fit_attempted == 0,
            execute = options.execute,
            n_fit_attempted,
        ),
        (;
            check = :executed_fit_wiring,
            passed = !options.execute || n_fit_failed == 0,
            applicable = options.execute,
            n_fit_attempted,
            n_fit_succeeded,
            n_fit_failed,
        ),
    ]
    all_checks_passed = all(row.passed for row in checks)
    paired_fit_execution_completed = options.execute && n_fit_attempted > 0 &&
        n_fit_failed == 0
    status = if !all_checks_passed
        :stress_grid_contract_failed
    elseif !options.execute
        :paired_known_truth_dry_run_passed_mcmc_not_run
    elseif options.profile === :smoke
        :paired_fit_wiring_smoke_passed_not_recovery_evidence
    elseif options.profile === :pilot
        :paired_pilot_fit_execution_completed_full_gate_scorer_incomplete
    else
        :paired_calibration_fit_execution_completed_full_gate_scorer_incomplete
    end
    artifact = (;
        schema = "bayesianmgmfrm.existing_api_design_robustness_stress_grid.v1",
        family = :mfrm_gmfrm_mgmfrm,
        scope = :existing_static_api_paired_known_truth_design_stress,
        status,
        publication_or_registration_action = false,
        public_claim_release_allowed = false,
        package = (;
            name = :BayesianMGMFRM,
            version = project_version(),
        ),
        generator = (;
            script = "scripts/generate_existing_api_design_robustness_stress_grid.jl",
            source_sha256 = file_sha256(@__FILE__),
            deterministic_without_mcmc = true,
        ),
        runtime_provenance = package_runtime_provenance(),
        prerequisite_plan = prerequisite,
        gate_contract = GATE_CONTRACT,
        scorer_capabilities = design_robustness_scorer_capabilities(),
        terminology = (;
            parameter_anchor =
                :model_parameter_constraint_not_a_shared_scored_response,
            inclusive_multiply_scored_target =
                :observed_person_item_target_with_two_or_more_raters_including_common_linking_targets,
            common_linking_target =
                :person_item_target_scored_by_every_rater_for_cross_rater_linking,
            controlled_benchmark =
                :repeated_temporal_control_response_distinct_from_common_linking,
            controlled_benchmark_materialized = false,
        ),
        execution = (;
            profile = options.profile,
            execute_mcmc = options.execute,
            allow_heavy = options.allow_heavy,
            requested_replications = options.requested_replications,
            materialized_replications,
            all_requested_replication_skeletons_design_preflighted = true,
            all_requested_replication_skeletons_passed =
                all_skeleton_preflight.passed,
            all_skeleton_preflight_hard_gate_before_execute = true,
            default_fixture_path_is_mcmc_free = true,
            explicit_output_required_for_mcmc = true,
            sampler = config.sampler,
            fixed_sampler_gate_applies = options.profile !== :smoke,
            provisional_recovery_gate_evaluated =
                repeated_recovery_gate.evaluated,
            recovery_gate_scorer_implemented =
                RECOVERY_GATE_SCORER_IMPLEMENTED,
            predictive_gate_scorer_implemented =
                PREDICTIVE_GATE_SCORER_IMPLEMENTED,
            decision_gate_scorer_implemented =
                DECISION_GATE_SCORER_IMPLEMENTED,
            full_gate_scorer_implemented = FULL_GATE_SCORER_IMPLEMENTED,
            paired_fit_execution_completed,
            fit_execution_completion_is_separate_from_recovery_gate = true,
            seed_namespace = seed_namespace(options.profile).name,
            replication_skeleton_policy = (;
                replication_one_is_deterministic_reference = true,
                later_replications_resample_from_replication_seed = true,
                resampled_components = (
                    :primary_rater_assignment,
                    :routine_secondary_rater_assignment_when_applicable,
                    :common_linking_target_selection_when_applicable,
                    :fixed_total_displaced_target_selection_when_applicable,
                    :within_rater_order,
                ),
                paired_A_B_share_the_same_skeleton = true,
                row_permutation_controls_use_fixed_reference_skeleton = true,
            ),
            n_fit_attempted,
            n_fit_succeeded,
            n_fit_failed,
        ),
        data_scale = (;
            persons = config.n_persons,
            items = config.n_items,
            raters = config.n_raters,
            categories = config.n_categories,
            pilot_and_calibration_sample_size_held_constant = true,
            pilot_and_calibration_sampler_settings_held_constant = true,
            calibration_changes_replication_budget_not_sample_size = true,
        ),
        outcome_dispersion_contract = (;
            requested_axis = :threshold_spacing,
            requested_levels = (:compressed, :reference, :wide),
            applied_to_truth_step_blocks = true,
            achieved_metric_paths = (
                "paired_replication_rows.conditions.score_summary.standard_deviation",
                "paired_replication_rows.conditions.score_summary.category_counts",
            ),
            interpretation =
                :achieved_score_dispersion_not_requested_label_is_used_for_scoring,
        ),
        paired_dgp_contract = (;
            pair_unit = :same_family_design_truth_replication,
            common_design = true,
            common_known_static_truth = true,
            common_response_uniform_variates = true,
            common_sampler_seed_within_pair = true,
            category_support_conditioning = false,
            unused_declared_categories_retained_in_achieved_counts = true,
            condition_A_dgp_and_fit_share_package_likelihood_kernel = true,
            independent_dgp_cross_check_completed = false,
            kernel_independent_validation_claim_supported = false,
            interpretation_boundary =
                :design_robustness_pilot_not_independent_kernel_validation,
            condition_A = (;
                label = :A_well_specified_static,
                order_effect = :none,
                recovery_interpretation = :static_model_calibration,
            ),
            condition_B = (;
                label = :B_unmodeled_order_effect,
                order_effect = :rater_specific_linear_severity_drift,
                slope = ORDER_EFFECT_SLOPE,
                scale = :adjacent_category_location_logit_from_early_to_late,
                fitted_model = :existing_static_api,
                order_effect_parameter_estimated = false,
                recovery_interpretation = :misspecification_sensitivity_not_drift_recovery,
            ),
            nonrandom_order_diagnostics = (
                :ability_position_correlation_by_rater,
                :maximum_absolute_rater_ability_position_correlation,
                :pooled_late_minus_early_mean_ability,
                :mean_assigned_ability_rater_severity_correlation,
            ),
        ),
        linking_budget_contract = (;
            additive = :retain_all_operational_targets_and_add_common_rater_scores,
            fixed_total_target_displacement =
                :each_extra_common_rater_score_displaces_one_operational_target,
            fixed_total_routine_overlap_reallocation =
                :future_distinct_policy_not_implemented,
            common_linking_target =
                :person_item_target_scored_by_every_rater,
            controlled_benchmark =
                :separate_temporal_control_concept_not_materialized_in_this_grid,
            achieved_metrics_not_requested_labels_are_authoritative = true,
            achieved_metric_fields = (
                :planned_target_denominator,
                :observed_target_denominator,
                :observed_target_coverage,
                :dropped_target_fraction_of_planned,
                :achieved_common_linking_fraction_planned_denominator,
                :achieved_common_linking_fraction_observed_denominator,
                :achieved_multi_rated_target_fraction_planned_denominator,
                :achieved_multi_rated_target_fraction_observed_denominator,
                :common_linking_rating_burden,
                :ability_position_correlation_by_rater,
                :mean_assigned_ability_rater_severity_correlation,
                :rater_load_cv,
            ),
        ),
        grid_selection = (;
            method = :mandatory_cells_plus_deterministic_fractional_subset,
            all_axes_fully_crossed = false,
            candidate_full_factorial_cells = full_factorial_size(),
            selected_design_cells = length(DESIGN_CELLS),
            selected_model_design_cells = length(model_cells),
            design_cells = [design_cell_manifest(cell) for cell in DESIGN_CELLS],
            deterministic_control_cells = [design_cell_manifest(C2P_CONTROL_CELL)],
        ),
        model_cell_preflight = model_cells,
        all_requested_replication_skeleton_preflight = all_skeleton_preflight,
        row_permutation_equivariance_checks = row_permutation_checks,
        c2p_placement_contrast_preflight =
            [row.artifact for row in c2p_preflights],
        c2p_placement_contrast_checks = c2p_placement_checks,
        replication_skeleton_resampling_probe = skeleton_resampling_probe,
        paired_replication_rows = paired_rows,
        paired_recovery_contrasts = pair_contrasts,
        paired_recovery_contrast_aggregate = aggregate,
        empirical_posterior_uncertainty_rows = uncertainty_rows,
        repeated_recovery,
        repeated_recovery_gate,
        deterministic_checks = checks,
        evidence_boundary = (;
            dry_run_is_recovery_evidence = false,
            one_rep_low_draw_smoke_is_recovery_evidence = false,
            unmodeled_order_effect_is_estimated = false,
            temporal_drift_claim_supported = false,
            dynamic_model_extension_in_scope = false,
            recovery_thresholds_evaluated = repeated_recovery_gate.evaluated,
            repeated_recovery_scorer_implemented =
                RECOVERY_GATE_SCORER_IMPLEMENTED,
            predictive_scorer_implemented =
                PREDICTIVE_GATE_SCORER_IMPLEMENTED,
            decision_scorer_implemented =
                DECISION_GATE_SCORER_IMPLEMENTED,
            full_gate_scorer_implemented = FULL_GATE_SCORER_IMPLEMENTED,
            condition_A_dgp_and_fit_share_package_likelihood_kernel = true,
            independent_dgp_cross_check_completed = false,
            kernel_independent_validation_claim_supported = false,
        ),
        summary = (;
            passed = all_checks_passed,
            n_design_cells = length(DESIGN_CELLS),
            n_model_design_cells = length(model_cells),
            n_positive_model_design_cells = length(positive_cells),
            n_negative_control_model_design_cells = length(negative_controls),
            n_paired_replication_rows = length(paired_rows),
            n_paired_recovery_contrasts = length(pair_contrasts),
            n_empirical_posterior_uncertainty_rows = length(uncertainty_rows),
            n_repeated_recovery_block_rows =
                length(repeated_recovery.block_rows),
            n_repeated_recovery_uncertainty_rows =
                length(repeated_recovery.uncertainty_rows),
            n_fit_attempted,
            n_fit_succeeded,
            n_fit_failed,
            paired_fit_execution_completed,
            paired_known_truth_recovery_completed = false,
            repeated_recovery_gate_evaluated =
                repeated_recovery_gate.evaluated,
            repeated_recovery_scorer_implemented =
                RECOVERY_GATE_SCORER_IMPLEMENTED,
            predictive_scorer_implemented =
                PREDICTIVE_GATE_SCORER_IMPLEMENTED,
            decision_scorer_implemented =
                DECISION_GATE_SCORER_IMPLEMENTED,
            fit_execution_completion_is_separate_from_recovery_gate = true,
            design_robustness_claim_supported = false,
            temporal_drift_claim_supported = false,
            public_claim_release_allowed = false,
            next_gate = FULL_GATE_SCORER_IMPLEMENTED ?
                :run_30_replication_pilot_threshold_stage :
                :implement_full_gate_scorer_before_30_replication_pilot,
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
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output, artifact)
    println("wrote ", relpath(options.output, ROOT))
    println(
        "passed=", artifact.summary.passed,
        " profile=", options.profile,
        " execute_mcmc=", options.execute,
        " pairs=", artifact.summary.n_paired_replication_rows,
        " fits=", artifact.summary.n_fit_succeeded,
        "/", artifact.summary.n_fit_attempted,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
