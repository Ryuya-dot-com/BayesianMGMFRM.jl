#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_FROZEN_POLICY = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_direct_agreement_policy.json")
const DEFAULT_BASELINE = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_overlap_baseline.json")
const DEFAULT_DIRECT_PILOT = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_direct_estimate_pilot.json")
const DEFAULT_RECOVERY_POLICY = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_comparison_policy_review.json")
const DEFAULT_TAM_MULTIREP = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_multireplication_comparison.json")
const DEFAULT_OUTPUT = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_tam_direct_agreement_policy_refinement.json")

const FROZEN_POLICY_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy.v1"
const BASELINE_SCHEMA = "bayesianmgmfrm.mgmfrm_tam_overlap_baseline.v1"
const DIRECT_PILOT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_estimate_pilot.v1"
const RECOVERY_POLICY_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_comparison_policy_review.v1"
const TAM_MULTIREP_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_multireplication_comparison.v1"

const BLOCKS = (:item_difficulty, :rater_severity, :item_step)
const DIRECT_METRICS = (
    :pearson_correlation,
    :mean_abs_difference,
    :max_abs_difference,
    :tam_inside_package_interval95_rate,
)
const Z95 = 1.959963984540054
const DIRECT_MULTIREP_BASE_SEED = 20260714
const DIRECT_STREAM_OFFSETS = (ability = 11, response = 29, package_fit = 47)

include(joinpath(@__DIR__, "local_json.jl"))

function usage()
    return """
    Refine interpretation and adjudication for the frozen package-versus-TAM
    direct-agreement policy without changing its primary thresholds or design.

    The output is a versioned overlay. It separates numerical agreement,
    known-truth recovery, computation, structural alignment, robustness, and
    claim scope. It does not rewrite the frozen policy or promote the existing
    descriptive pilot to a confirmatory result.

    Usage:
      julia --project=. scripts/generate_mgmfrm_tam_direct_agreement_policy_refinement.jl [options]

    Options:
      --frozen-policy PATH
      --baseline PATH
      --direct-pilot PATH
      --recovery-policy PATH
      --tam-multirep PATH
      --output PATH
    """
end

function parse_args(args)
    frozen_policy = DEFAULT_FROZEN_POLICY
    baseline = DEFAULT_BASELINE
    direct_pilot = DEFAULT_DIRECT_PILOT
    recovery_policy = DEFAULT_RECOVERY_POLICY
    tam_multirep = DEFAULT_TAM_MULTIREP
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--frozen-policy"
            index < length(args) || error("--frozen-policy requires a path")
            frozen_policy = abspath(args[index + 1])
            index += 2
        elseif arg == "--baseline"
            index < length(args) || error("--baseline requires a path")
            baseline = abspath(args[index + 1])
            index += 2
        elseif arg == "--direct-pilot"
            index < length(args) || error("--direct-pilot requires a path")
            direct_pilot = abspath(args[index + 1])
            index += 2
        elseif arg == "--recovery-policy"
            index < length(args) || error("--recovery-policy requires a path")
            recovery_policy = abspath(args[index + 1])
            index += 2
        elseif arg == "--tam-multirep"
            index < length(args) || error("--tam-multirep requires a path")
            tam_multirep = abspath(args[index + 1])
            index += 2
        elseif arg == "--output"
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
    return (;
        frozen_policy, baseline, direct_pilot, recovery_policy, tam_multirep,
        output)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])

function file_sha256(path::AbstractString)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

load_json(path::AbstractString) = JSON3.read(read(path, String))
as_string(value) = String(value)
as_float(value) = Float64(value)
as_int(value) = Int(value)
as_bool(value) = Bool(value)

function checked_artifact(path::AbstractString, expected_schema::AbstractString)
    isfile(path) || error("required fixture missing: $(relpath(path, ROOT))")
    artifact = load_json(path)
    as_string(artifact[:schema]) == expected_schema ||
        error("unexpected schema for $(relpath(path, ROOT))")
    return artifact
end

function comparison_row(pilot, block::Symbol, interpretation_fragment::String)
    rows = [row for row in pilot[:direct_comparison_rows]
        if as_string(row[:block]) == String(block) &&
            occursin(interpretation_fragment, as_string(row[:interpretation]))]
    length(rows) == 1 ||
        error("expected one $interpretation_fragment comparison for $block")
    return only(rows)
end

function interval_row(pilot, block::Symbol)
    rows = [row for row in pilot[:block_interval_summary_rows]
        if as_string(row[:block]) == String(block)]
    length(rows) == 1 || error("expected one interval row for $block")
    return only(rows)
end

function policy_threshold_row(policy, block::Symbol, metric::Symbol)
    rows = [row for row in policy[:direct_threshold_rows]
        if as_string(row[:block]) == String(block) &&
            as_string(row[:metric]) == String(metric)]
    length(rows) == 1 || error("expected one frozen $block/$metric threshold")
    return only(rows)
end

function recovery_threshold_row(policy, block::Symbol, metric::Symbol)
    rows = [row for row in policy[:numerical_threshold_rows]
        if as_string(row[:block]) == String(block) &&
            as_string(row[:metric]) == String(metric)]
    length(rows) == 1 || error("expected one recovery $block/$metric threshold")
    return only(rows)
end

function metric_passed(observed::Real, direction::AbstractString, threshold::Real)
    direction == "minimum" && return observed >= threshold
    direction == "maximum" && return observed <= threshold
    error("unsupported threshold direction: $direction")
end

function direct_gate_snapshot(policy)
    direct = [(
        block = Symbol(as_string(row[:block])),
        metric = Symbol(as_string(row[:metric])),
        direction = Symbol(as_string(row[:direction])),
        threshold = as_float(row[:threshold]),
    ) for row in policy[:direct_threshold_rows]]
    sampler = [(
        metric = Symbol(as_string(row[:metric])),
        direction = Symbol(as_string(row[:direction])),
        threshold = row[:threshold],
    ) for row in policy[:sampler_threshold_rows]]
    plan = policy[:future_execution_plan]
    return (;
        direct_threshold_rows = direct,
        sampler_threshold_rows = sampler,
        person_counts = as_int.(plan[:person_counts]),
        replications_per_person_count = as_int(plan[:replications_per_person_count]),
        primary_person_count = as_int(plan[:primary_person_count]),
        primary_block_pass_rate_threshold =
            as_float(plan[:primary_block_pass_rate_threshold]),
        chains = as_int(plan[:chains]),
        ndraws_per_chain = as_int(plan[:ndraws_per_chain]),
        warmup_per_chain = as_int(plan[:warmup_per_chain]),
        target_accept = as_float(plan[:target_accept]),
        max_depth = as_int(plan[:max_depth]),
        metric = Symbol(as_string(plan[:metric])),
        ad_backend = Symbol(as_string(plan[:ad_backend])),
    )
end

function gate_fingerprint(snapshot)
    tokens = String[]
    for row in sort(snapshot.direct_threshold_rows;
            by = row -> (String(row.block), String(row.metric)))
        push!(tokens, join(("direct", row.block, row.metric, row.direction,
            repr(row.threshold)), "|"))
    end
    for row in sort(snapshot.sampler_threshold_rows;
            by = row -> String(row.metric))
        push!(tokens, join(("sampler", row.metric, row.direction,
            string(row.threshold)), "|"))
    end
    append!(tokens, [
        "persons|" * join(snapshot.person_counts, ","),
        "replications|$(snapshot.replications_per_person_count)",
        "primary_n|$(snapshot.primary_person_count)",
        "block_rate|$(repr(snapshot.primary_block_pass_rate_threshold))",
        "chains|$(snapshot.chains)",
        "draws|$(snapshot.ndraws_per_chain)",
        "warmup|$(snapshot.warmup_per_chain)",
        "target_accept|$(repr(snapshot.target_accept))",
        "max_depth|$(snapshot.max_depth)",
        "metric|$(snapshot.metric)",
        "ad_backend|$(snapshot.ad_backend)",
    ])
    return bytes2hex(sha256(join(tokens, "\n")))
end

function threshold_table_fingerprint(rows, kind::Symbol)
    tokens = String[]
    if kind === :direct
        for row in sort(collect(rows);
                by = row -> (as_string(row[:block]), as_string(row[:metric])))
            push!(tokens, join((as_string(row[:block]), as_string(row[:metric]),
                as_string(row[:direction]), string(row[:threshold])), "|"))
        end
    elseif kind === :sampler
        for row in sort(collect(rows); by = row -> as_string(row[:metric]))
            push!(tokens, join((as_string(row[:metric]),
                as_string(row[:direction]), string(row[:threshold])), "|"))
        end
    else
        error("unsupported threshold fingerprint kind: $kind")
    end
    return bytes2hex(sha256(join(tokens, "\n")))
end

function validate_frozen_gate(policy, snapshot)
    expected_direct = Dict(
        :pearson_correlation => 0.95,
        :mean_abs_difference => 0.10,
        :max_abs_difference => 0.30,
        :tam_inside_package_interval95_rate => 0.80,
    )
    length(snapshot.direct_threshold_rows) == 12 || return false
    for block in BLOCKS, metric in DIRECT_METRICS
        row = policy_threshold_row(policy, block, metric)
        as_float(row[:threshold]) == expected_direct[metric] || return false
    end
    plan = policy[:future_execution_plan]
    return as_int.(plan[:person_counts]) == [40, 100] &&
        as_int(plan[:replications_per_person_count]) == 5 &&
        as_int(plan[:primary_person_count]) == 100 &&
        as_float(plan[:primary_block_pass_rate_threshold]) == 0.80 &&
        as_int(plan[:chains]) == 4 &&
        as_int(plan[:ndraws_per_chain]) == 400 &&
        as_int(plan[:warmup_per_chain]) == 400 &&
        as_float(plan[:target_accept]) == 0.90 &&
        as_int(plan[:max_depth]) == 10
end

function pilot_direct_margin_rows(frozen_policy, pilot)
    rows = NamedTuple[]
    for block in BLOCKS, metric in DIRECT_METRICS
        threshold = policy_threshold_row(frozen_policy, block, metric)
        observed = if metric === :tam_inside_package_interval95_rate
            as_float(interval_row(pilot, block)[metric])
        else
            as_float(comparison_row(pilot, block, "tam_estimate")[metric])
        end
        direction = as_string(threshold[:direction])
        limit = as_float(threshold[:threshold])
        margin = direction == "minimum" ? observed - limit : limit - observed
        push!(rows, (;
            block,
            metric,
            observed,
            direction = Symbol(direction),
            frozen_threshold = limit,
            pass_margin = margin,
            pilot_passed = metric_passed(observed, direction, limit),
            role = :retrospective_descriptive_context_only,
            can_confirm_future_gate = false,
        ))
    end
    return rows
end

function current_pilot_triangle_rows(recovery_policy, pilot)
    rows = NamedTuple[]
    for block in BLOCKS
        package_tam = comparison_row(pilot, block, "tam_estimate")
        package_truth = comparison_row(pilot, block, "known_truth")
        interval = interval_row(pilot, block)
        package_recovery_passes = Bool[]
        tam_recovery_passes = Bool[]
        tam_truth_values = Dict{Symbol,Float64}()
        for metric in (:pearson_correlation, :mean_abs_difference,
                :max_abs_difference)
            rule = recovery_threshold_row(recovery_policy, block, metric)
            push!(package_recovery_passes, metric_passed(
                as_float(package_truth[metric]), as_string(rule[:direction]),
                as_float(rule[:threshold])))
            tam_truth_values[metric] = as_float(rule[:observed])
            push!(tam_recovery_passes, metric_passed(
                tam_truth_values[metric], as_string(rule[:direction]),
                as_float(rule[:threshold])))
        end
        package_recovery = all(package_recovery_passes)
        tam_recovery = all(tam_recovery_passes)
        interpretation = if package_recovery && tam_recovery
            :direct_agreement_with_descriptive_recovery_support_for_both_estimators
        elseif package_recovery
            :direct_agreement_with_package_only_descriptive_recovery_support
        elseif tam_recovery
            :direct_agreement_with_tam_only_descriptive_recovery_support
        else
            :direct_agreement_but_neither_estimator_has_descriptive_recovery_support
        end
        push!(rows, (;
            block,
            n_parameters = as_int(package_tam[:n_parameters]),
            package_vs_tam_pearson = as_float(package_tam[:pearson_correlation]),
            package_vs_tam_mean_abs_difference =
                as_float(package_tam[:mean_abs_difference]),
            package_vs_tam_max_abs_difference =
                as_float(package_tam[:max_abs_difference]),
            package_vs_truth_pearson =
                as_float(package_truth[:pearson_correlation]),
            package_vs_truth_mean_abs_difference =
                as_float(package_truth[:mean_abs_difference]),
            package_vs_truth_max_abs_difference =
                as_float(package_truth[:max_abs_difference]),
            tam_vs_truth_pearson = tam_truth_values[:pearson_correlation],
            tam_vs_truth_mean_abs_difference =
                tam_truth_values[:mean_abs_difference],
            tam_vs_truth_max_abs_difference =
                tam_truth_values[:max_abs_difference],
            tam_inside_package_interval95_rate =
                as_float(interval[:tam_inside_package_interval95_rate]),
            truth_inside_package_interval95_rate =
                as_float(interval[:truth_inside_package_interval95_rate]),
            package_truth_recovery_profile_passed = package_recovery,
            tam_truth_recovery_profile_passed = tam_recovery,
            both_estimators_truth_recovery_profiles_passed =
                package_recovery && tam_recovery,
            interpretation,
            confirmatory = false,
        ))
    end
    return rows
end

function block_discreteness_rows(frozen_policy, pilot)
    replication_count = as_int(
        frozen_policy[:future_execution_plan][:replications_per_person_count])
    replication_rate = as_float(
        frozen_policy[:future_execution_plan][:primary_block_pass_rate_threshold])
    interval_rate = as_float(policy_threshold_row(
        frozen_policy, :item_difficulty,
        :tam_inside_package_interval95_rate)[:threshold])
    return [begin
        comparison = comparison_row(pilot, block, "tam_estimate")
        n_parameters = as_int(comparison[:n_parameters])
        (;
            block,
            n_parameters,
            correlation_degrees_of_freedom = n_parameters - 2,
            small_parameter_block = n_parameters < 10,
            interval_rate_threshold = interval_rate,
            minimum_interval_containment_count =
                ceil(Int, interval_rate * n_parameters - 1.0e-12),
            replications_per_person_count = replication_count,
            block_pass_rate_threshold = replication_rate,
            minimum_replications_passing =
                ceil(Int, replication_rate * replication_count - 1.0e-12),
            interpretation = n_parameters < 10 ?
                :correlation_and_interval_rate_are_discrete_small_block_statistics :
                :parameter_level_statistics_still_share_constraints_and_data,
        )
    end for block in BLOCKS]
end

function wilson_interval(successes::Int, trials::Int)
    proportion = successes / trials
    denominator = 1 + Z95^2 / trials
    center = (proportion + Z95^2 / (2trials)) / denominator
    half_width = Z95 * sqrt(
        proportion * (1 - proportion) / trials + Z95^2 / (4trials^2)) /
        denominator
    return (; lower = center - half_width, upper = center + half_width)
end

function replication_precision_rows(frozen_policy)
    trials = as_int(
        frozen_policy[:future_execution_plan][:replications_per_person_count])
    minimum_passes = ceil(Int,
        as_float(frozen_policy[:future_execution_plan][
            :primary_block_pass_rate_threshold]) * trials - 1.0e-12)
    return [begin
        interval = wilson_interval(successes, trials)
        (;
            successes,
            trials,
            observed_pass_rate = successes / trials,
            frozen_gate_passed = successes >= minimum_passes,
            wilson95_lower = interval.lower,
            wilson95_upper = interval.upper,
            inferential_role = :precision_context_not_primary_gate,
            interpretation =
                :five_replications_define_a_decision_rule_not_a_precise_population_pass_rate,
        )
    end for successes in minimum_passes:trials]
end

function direct_multirep_seed(n_persons::Int, replication::Int, stream::Symbol)
    person_counts = [40, 100]
    scenario = findfirst(==(n_persons), person_counts)
    scenario === nothing && error("unregistered direct person count: $n_persons")
    1 <= replication <= 5 || error("unregistered direct replication: $replication")
    offset = getproperty(DIRECT_STREAM_OFFSETS, stream)
    return DIRECT_MULTIREP_BASE_SEED + 100000 * scenario +
        1000 * replication + offset
end

function seed_registry_rows()
    return [(
        n_persons,
        replication,
        ability_seed = direct_multirep_seed(n_persons, replication, :ability),
        response_seed = direct_multirep_seed(n_persons, replication, :response),
        package_fit_seed =
            direct_multirep_seed(n_persons, replication, :package_fit),
        chain_rng_contract =
            :single_replayable_mersenne_twister_consumed_sequentially_by_four_chains,
    ) for n_persons in (40, 100), replication in 1:5] |> vec
end

function old_tam_multirep_seeds()
    seeds = Int[]
    for scenario in 1:3, replication in 1:10, stream in (1, 3)
        push!(seeds, 20260712 + 100000 * scenario + 1000 * replication + stream)
    end
    return seeds
end

function seed_registry_is_disjoint(rows)
    new_seeds = Int[]
    for row in rows
        append!(new_seeds,
            (row.ability_seed, row.response_seed, row.package_fit_seed))
    end
    return length(unique(new_seeds)) == length(new_seeds) &&
        isempty(intersect(Set(new_seeds), Set(old_tam_multirep_seeds()))) &&
        20260713 ∉ Set(new_seeds)
end

function tam_recovery_context_rows(multirep)
    return [(
        n_persons = as_int(row[:n_persons]),
        block = Symbol(as_string(row[:block])),
        n_replications = as_int(row[:n_replications]),
        median_pearson_correlation =
            as_float(row[:median_pearson_correlation]),
        minimum_pearson_correlation =
            as_float(row[:minimum_pearson_correlation]),
        median_mean_abs_difference =
            as_float(row[:median_mean_abs_difference]),
        percentile90_mean_abs_difference =
            as_float(row[:percentile90_mean_abs_difference]),
        median_max_abs_difference =
            as_float(row[:median_max_abs_difference]),
        percentile90_max_abs_difference =
            as_float(row[:percentile90_max_abs_difference]),
        all_recovery_thresholds_pass_rate =
            as_float(row[:all_thresholds_pass_rate]),
        role = :known_truth_sample_size_context_only,
        direct_threshold_cross_application_allowed = false,
        interpretation = as_string(row[:block]) == "item_step" &&
            as_int(row[:n_persons]) == 40 ?
            :item_step_recovery_is_small_sample_sensitive :
            :context_for_recovery_not_direct_agreement,
    ) for row in multirep[:scenario_block_summary_rows]]
end

function metric_role_rows()
    return [
        (metric = :pearson_correlation,
            primary_role = :linear_pattern_agreement,
            strength = :detects_relative_order_and_linear_pattern,
            limitation = :insensitive_to_common_location_and_scale_and_unstable_in_small_blocks,
            independent_evidence_unit = false),
        (metric = :mean_abs_difference,
            primary_role = :typical_logit_scale_difference,
            strength = :detects_average_level_disagreement,
            limitation = :scale_dependent_and_can_hide_a_single_large_error,
            independent_evidence_unit = false),
        (metric = :max_abs_difference,
            primary_role = :worst_parameter_difference,
            strength = :prevents_average_metrics_from_hiding_a_local_mismatch,
            limitation = :highly_outlier_and_parameter_count_sensitive,
            independent_evidence_unit = false),
        (metric = :tam_inside_package_interval95_rate,
            primary_role = :asymmetric_interval_compatibility,
            strength = :records_whether_tam_points_fall_inside_package_intervals,
            limitation = :not_an_equivalence_test_not_symmetric_and_increases_with_wider_intervals,
            independent_evidence_unit = false),
    ]
end

function evidence_axis_rows(structural_passed::Bool, pilot, recovery_policy,
        multirep)
    return [
        (axis = :protocol_and_parameterization_alignment,
            current_status = structural_passed ? :passed : :failed,
            evidence = :ten_tam_item_step_adapter_structural_checks,
            primary_gate_effect = :execution_precondition),
        (axis = :computational_reliability,
            current_status = as_bool(pilot[:summary][:sampler_diagnostics_passed]) ?
                :descriptive_pilot_pass : :descriptive_pilot_fail,
            evidence = :classical_split_rhat_autocorrelation_ess_and_hmc_geometry,
            primary_gate_effect = :frozen_sampler_conjunction),
        (axis = :direct_cross_software_numerical_agreement,
            current_status = :descriptive_pilot_pass_confirmatory_runs_pending,
            evidence = :package_posterior_summary_vs_tam_same_data_estimate,
            primary_gate_effect = :frozen_primary_decision),
        (axis = :known_truth_recovery,
            current_status = as_bool(multirep[:summary][
                :primary_multireplication_gate_passed]) ?
                :tam_primary_n250_pass_package_multirep_pending :
                :tam_primary_n250_fail_package_multirep_pending,
            evidence = :tam_multireplication_plus_single_package_pilot,
            primary_gate_effect = :secondary_claim_qualifier_no_rescue_or_veto),
        (axis = :sample_size_robustness,
            current_status = :item_step_sensitivity_observed,
            evidence = :tam_n40_n100_n250_known_truth_comparison,
            primary_gate_effect = :n40_secondary_n100_primary_as_frozen),
        (axis = :software_diversity,
            current_status = :tam_only,
            evidence = :facets_and_conquest_not_executed,
            primary_gate_effect = :blocks_broad_external_software_claim),
        (axis = :model_family_coverage,
            current_status = :unit_discrimination_unidimensional_mfrm_overlap_only,
            evidence = :tam_mml_mfr_partial_credit_bridge,
            primary_gate_effect = :blocks_gmfrm_and_mgmfrm_generalization),
        (axis = :external_construct_and_population_validity,
            current_status = :not_supplied,
            evidence = :synthetic_known_truth_data_only,
            primary_gate_effect = :blocks_construct_and_population_claims),
        (axis = :independent_review,
            current_status = :packet_only_review_not_completed,
            evidence = :signed_independent_review_manifest_missing,
            primary_gate_effect = :blocks_public_claim_release),
    ]
end

function secondary_recovery_threshold_rows(recovery_policy)
    return [(
        block = Symbol(as_string(row[:block])),
        metric = Symbol(as_string(row[:metric])),
        direction = Symbol(as_string(row[:direction])),
        threshold = as_float(row[:threshold]),
        source_role = :inherited_unchanged_from_frozen_tam_known_truth_policy,
        future_application = :apply_separately_to_package_vs_truth_and_tam_vs_truth,
        aggregation = :four_of_five_primary_n100_replications_per_block,
        primary_direct_gate_effect = :none,
    ) for row in recovery_policy[:numerical_threshold_rows]]
end

function decision_state_rows()
    return [
        (state = :direct_pass_recovery_qualifier_pass,
            condition = :frozen_direct_gate_passes_and_both_estimators_pass_secondary_recovery_profile,
            interpretation = :local_cross_software_agreement_with_known_truth_recovery_support,
            public_claim_release = false),
        (state = :direct_pass_recovery_qualifier_fail,
            condition = :frozen_direct_gate_passes_but_either_estimator_fails_secondary_recovery_profile,
            interpretation = :local_cross_software_agreement_without_known_truth_recovery_support,
            public_claim_release = false),
        (state = :direct_fail_sampler_valid,
            condition = :all_fits_computationally_valid_but_any_primary_block_has_fewer_than_four_of_five_passes,
            interpretation = :nonagreement_under_frozen_rule_no_threshold_revision_or_secondary_rescue,
            public_claim_release = false),
        (state = :sampler_invalid,
            condition = :any_scheduled_fit_fails_any_frozen_sampler_gate,
            interpretation = :primary_gate_not_passed_computational_failure_retained,
            public_claim_release = false),
        (state = :execution_incomplete,
            condition = :any_scheduled_dataset_or_fit_is_missing,
            interpretation = :incomplete_no_denominator_reduction_or_replacement_seed,
            public_claim_release = false),
        (state = :protocol_violation,
            condition = :input_hash_parameter_mapping_seed_or_frozen_setting_mismatch,
            interpretation = :execution_invalid_preserve_attempt_and_restart_only_under_documented_protocol,
            public_claim_release = false),
    ]
end

function estimand_alignment_rows()
    return [
        (estimand = :item_difficulty,
            package_quantity = :centered_identified_item_effect,
            tam_quantity = :centered_expanded_item_facet_xsi,
            alignment = :contrast_aligned_after_centering,
            included_in_primary_gate = true),
        (estimand = :rater_severity,
            package_quantity = :centered_identified_rater_effect,
            tam_quantity = :centered_expanded_rater_facet_xsi,
            alignment = :contrast_aligned_after_centering,
            included_in_primary_gate = true),
        (estimand = :item_step,
            package_quantity = :free_steps_plus_reconstructed_negative_sum_last_step,
            tam_quantity = :expanded_item_colon_step_facet_under_within_item_sum_constraint,
            alignment = :same_item_adjacent_step_after_constraint_reconstruction,
            included_in_primary_gate = true),
        (estimand = :person_ability,
            package_quantity = :fixed_person_parameter_with_prior,
            tam_quantity = :marginal_latent_distribution_and_eap_quantity,
            alignment = :not_directly_aligned,
            included_in_primary_gate = false),
        (estimand = :uncertainty,
            package_quantity = :bayesian_posterior_credible_interval,
            tam_quantity = :mml_point_estimate_and_standard_error,
            alignment = :not_identical_interval_frameworks,
            included_in_primary_gate = false),
        (estimand = :model_fit_or_prediction,
            package_quantity = :waic_loo_or_posterior_predictive_quantities,
            tam_quantity = :deviance_aic_bic_or_eap_reliability,
            alignment = :undefined_in_current_policy,
            included_in_primary_gate = false),
        (estimand = :generalized_discrimination_loading_or_consistency,
            package_quantity = :gmfrm_or_mgmfrm_parameter,
            tam_quantity = :absent_from_current_rasch_pcm_target,
            alignment = :nonoverlap,
            included_in_primary_gate = false),
    ]
end

function design_scope(baseline, frozen_policy)
    design = baseline[:design]
    return (;
        inherited_without_change = true,
        person_counts = as_int.(
            frozen_policy[:future_execution_plan][:person_counts]),
        primary_person_count = as_int(
            frozen_policy[:future_execution_plan][:primary_person_count]),
        n_items = as_int(design[:n_items]),
        n_raters = as_int(design[:n_raters]),
        n_dimensions = as_int(design[:n_dimensions]),
        category_levels = as_int.(design[:category_levels]),
        n_categories = length(design[:category_levels]),
        assignment = Symbol(as_string(design[:assignment])),
        thresholds = :partial_credit,
        item_discrimination = 1.0,
        rater_consistency = 1.0,
        truth_source = :tam_overlap_baseline_fixed_item_rater_and_step_truth,
        varying_component = :new_person_ability_and_response_draw_per_replication,
    )
end

function scope_rows()
    return [
        (component = :unidimensional_many_facet_rasch_partial_credit,
            status = :included_primary_overlap),
        (component = :fully_crossed_person_item_rater_assignment,
            status = :included_only_design),
        (component = :item_difficulty_rater_severity_item_steps,
            status = :included_aligned_parameter_blocks),
        (component = :person_ability,
            status = :shared_kernel_term_not_direct_estimand),
        (component = :rating_scale_mfrm,
            status = :not_tested),
        (component = :binary_mfrm,
            status = :nested_but_not_tested),
        (component = :free_item_discrimination,
            status = :excluded),
        (component = :rater_consistency_or_rater_specific_steps,
            status = :excluded),
        (component = :multidimensional_fixed_q_mgmfrm,
            status = :excluded),
        (component = :uto_2021_loading_weighted_multidimensional_model,
            status = :excluded_no_inference_from_tam_overlap),
        (component = :tam_gpcm_mirt_or_other_functions,
            status = :not_executed),
        (component = :sparse_or_incomplete_rating_design,
            status = :excluded),
        (component = :facets_or_conquest_agreement,
            status = :excluded_not_executed),
        (component = :real_data_construct_or_population_validity,
            status = :excluded_not_supplied),
        (component = :posterior_uncertainty_calibration,
            status = :excluded_requires_sbc_or_replicated_coverage),
    ]
end

function reporting_rows()
    return [
        (report = :all_scheduled_attempts_and_failure_reasons,
            role = :required_no_silent_exclusion),
        (report = :per_replication_per_block_all_four_primary_metrics,
            role = :required_primary_audit),
        (report = :per_metric_pass_rates_alongside_conjunctive_block_pass_rate,
            role = :diagnostic_only_no_rescue),
        (report = :package_vs_tam_package_vs_truth_and_tam_vs_truth_triangle,
            role = :required_secondary_interpretation),
        (report = :parameter_ids_for_max_errors,
            role = :required_localization),
        (report = :rmse_median_absolute_difference_regression_slope_and_concordance,
            role = :descriptive_no_threshold),
        (report = :package_interval_widths_tam_standard_errors_and_interval_counts,
            role = :descriptive_uncertainty_context_not_equivalence),
        (report = :rank_normalized_rhat_bulk_tail_ess_and_ebfmi_when_available,
            role = :secondary_quality_overlay_no_change_to_frozen_gate),
        (report = :n40_vs_n100_sample_size_pattern,
            role = :secondary_robustness_context),
        (report = :adapter_constraint_and_input_hash_checks,
            role = :required_protocol_integrity),
    ]
end

function failure_taxonomy_rows()
    return [
        (priority = 1, failure = :protocol_or_alignment_failure,
            examples = [:hash_mismatch, :seed_mismatch, :sign_or_centering_mismatch,
                :missing_or_duplicate_parameter, :undefined_correlation],
            disposition = :protocol_invalid),
        (priority = 2, failure = :tam_engine_or_numerical_failure,
            examples = [:nonzero_exit, :nonfinite_estimate_or_se,
                :iteration_limit, :invalid_parameter_table],
            disposition = :scheduled_replication_failure_no_replacement),
        (priority = 3, failure = :package_engine_failure,
            examples = [:exception, :nonfinite_draw_or_logposterior],
            disposition = :scheduled_replication_failure_no_replacement),
        (priority = 4, failure = :package_sampler_confirmatory_failure,
            examples = [:divergence, :max_treedepth, :classical_rhat,
                :autocorrelation_ess, :warning_parameter],
            disposition = :primary_gate_not_passed),
        (priority = 5, failure = :sampler_advisory_warning,
            examples = [:rank_rhat, :bulk_or_tail_ess, :ebfmi, :mcse],
            disposition = :retain_separately_no_primary_gate_change),
        (priority = 6, failure = :direct_metric_failure,
            examples = [:correlation, :mad, :max_difference,
                :interval_compatibility],
            disposition = :block_replication_failure),
        (priority = 7, failure = :multireplication_aggregation_failure,
            examples = [:fewer_than_four_of_five_block_passes],
            disposition = :direct_nonagreement),
        (priority = 8, failure = :threshold_fragile_pass,
            examples = [:exactly_four_of_five, :small_normalized_margin,
                :leave_one_replication_out_flip],
            disposition = :primary_pass_retained_with_fragility_label),
        (priority = 9, failure = :truth_triangulation_limitation,
            examples = [:agree_but_both_miss_truth,
                :agree_package_only_recovers, :agree_tam_only_recovers],
            disposition = :recovery_qualifier_and_claim_wording_only),
    ]
end

function data_and_input_contract(baseline, seed_rows)
    design = baseline[:design]
    return (;
        generator = :standalone_adjacent_category_softmax,
        package_probability_or_simulation_helper_used_for_generation = false,
        fixed_truth_sha256 = as_string(baseline[:checksums][:truth_sha256]),
        base_seed = DIRECT_MULTIREP_BASE_SEED,
        seed_formula =
            :base_plus_100000_times_scenario_plus_1000_times_replication_plus_stream_offset,
        stream_offsets = DIRECT_STREAM_OFFSETS,
        seed_registry_rows = seed_rows,
        seed_disjoint_from_direct_pilot_and_tam_only_multireplication =
            seed_registry_is_disjoint(seed_rows),
        adaptive_seed_search_or_redraw_allowed = false,
        missing_category_regeneration_allowed = false,
        n_items = as_int(design[:n_items]),
        n_raters = as_int(design[:n_raters]),
        category_levels = as_int.(design[:category_levels]),
        assignment = Symbol(as_string(design[:assignment])),
        canonical_row_order = :person_then_rater_then_item,
        package_and_tam_must_use_identical_csv_sha256 = true,
        package_and_tam_must_match_row_count_ids_and_categories = true,
        each_dataset_truth_observations_and_csv_sha256_required = true,
    )
end

function package_fit_contract()
    return (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 4,
        warmup_per_chain = 400,
        retained_draws_per_chain = 400,
        step_size = 0.05,
        target_accept = 0.90,
        max_depth = 10,
        max_energy_error = 1000.0,
        metric = :diagonal,
        ad_backend = :ForwardDiff,
        init = :zeros,
        init_jitter = 0.05,
        progress = false,
        prior = (;
            person_sd = 1.5,
            rater_sd = 1.0,
            item_sd = 1.0,
            step_sd = 1.0,
        ),
        post_result_tuning_change_allowed = false,
    )
end

function tam_fit_contract(multirep)
    environment = multirep[:tam_environment]
    return (;
        r_command = :TAM_tam_mml_mfr,
        formulaA = "~ item + rater + item:step",
        constraint = "cases",
        control = (;
            maxiter = 1000,
            conv = 1.0e-4,
            convD = 1.0e-3,
            convM = 1.0e-4,
        ),
        delete_red_items = true,
        tam_version = as_string(environment[:tam_version]),
        r_version = as_string(environment[:r_version]),
        version_mismatch_disposition = :new_versioned_protocol_required,
        required_validity_checks = [
            :exit_code_zero,
            :finite_deviance,
            :positive_iteration_count,
            :iteration_limit_not_reached,
            :all_expected_parameters_present_once,
            :no_unexpected_parameters_after_adapter,
            :all_estimates_and_standard_errors_finite,
            :formula_and_constraint_audit_pass,
            :sum_zero_and_category_intercept_reconstruction_pass,
        ],
    )
end

function artifact_archive_contract()
    return (;
        committed_fixture_role = :summary_decision_and_hash_manifest,
        raw_local_archive_required = true,
        raw_tam_outputs = [
            :input_csv, :xsi_facets_csv, :fit_summary_csv,
            :formula_audit_csv, :stdout, :stderr,
        ],
        raw_package_outputs = [
            :draws, :log_posterior, :sampler_rows, :parameter_diagnostics,
            :derived_aligned_parameter_draws, :fit_controls,
        ],
        per_attempt_command_environment_and_sha256_manifest_required = true,
        failed_and_retried_attempts_both_retained = true,
        independent_metric_recomputation_from_raw_outputs_required = true,
    )
end

function equivalence_advisory()
    return (;
        frozen_primary_interval_metric =
            :tam_point_inside_package_equal_tail_interval95_rate,
        primary_metric_is_equivalence_test = false,
        conditional_rope_analysis = (;
            status = :prospective_advisory_only,
            difference = :package_parameter_draw_minus_fixed_tam_point_estimate,
            posterior_interval_probability = 0.90,
            rope_half_width = 0.30,
            outcomes = [
                :conditional_equivalence_demonstrated,
                :conditional_equivalence_inconclusive,
                :meaningful_difference_supported,
            ],
            changes_frozen_primary_gate = false,
        ),
        full_estimator_equivalence_requires =
            :paired_same_resample_refits_with_joint_difference_uncertainty,
        full_estimator_equivalence_completed = false,
    )
end

function retry_policy()
    return (;
        fixed_primary_denominator = 5,
        sampler_gate_scope = :all_ten_scheduled_package_fits,
        n40_and_n100_pooling_allowed = false,
        n40_role = :secondary_sample_size_stress_condition,
        n100_role = :primary_confirmatory_condition,
        undefined_or_nonfinite_primary_metric = :automatic_replication_block_failure,
        interval_metric_denominator = :all_expected_parameters_in_block,
        all_scheduled_replications_must_be_recorded = true,
        sampler_failure_counts_as_primary_gate_failure = true,
        sampler_failure_may_be_replaced = false,
        agreement_metric_failure_may_be_replaced = false,
        replacement_seed_allowed = false,
        denominator_reduction_allowed = false,
        post_result_threshold_or_tuning_change_allowed = false,
        objective_infrastructure_failure_retry =
            :same_dataset_same_seed_same_frozen_settings_only,
        retry_audit =
            :retain_original_attempt_record_error_correction_and_retry_hash,
        remediation_after_sampler_failure =
            :new_versioned_protocol_not_continuation_of_frozen_confirmatory_run,
    )
end

function claim_wording_rows()
    return [
        (claim = :allowed_if_direct_primary_gate_passes,
            wording = :under_the_predeclared_synthetic_unit_discrimination_mfrm_overlap_cells_package_parameter_summaries_met_the_frozen_numerical_agreement_rule_against_tam,
            requires_secondary_recovery_qualifier = false),
        (claim = :allowed_only_if_secondary_recovery_qualifier_also_passes,
            wording = :the_same_runs_also_supported_known_truth_recovery_for_both_estimators_under_the_inherited_recovery_profile,
            requires_secondary_recovery_qualifier = true),
        (claim = :prohibited,
            wording = :bayesianmgmfrm_is_equivalent_to_or_validated_by_tam,
            requires_secondary_recovery_qualifier = true),
        (claim = :prohibited,
            wording = :gmfrm_or_mgmfrm_including_uto_2021_is_externally_validated,
            requires_secondary_recovery_qualifier = true),
        (claim = :prohibited,
            wording = :construct_validity_population_generalizability_or_publication_grade_validation,
            requires_secondary_recovery_qualifier = true),
    ]
end

function build_artifact(paths)
    frozen_policy = checked_artifact(paths.frozen_policy, FROZEN_POLICY_SCHEMA)
    baseline = checked_artifact(paths.baseline, BASELINE_SCHEMA)
    pilot = checked_artifact(paths.direct_pilot, DIRECT_PILOT_SCHEMA)
    recovery_policy = checked_artifact(paths.recovery_policy, RECOVERY_POLICY_SCHEMA)
    multirep = checked_artifact(paths.tam_multirep, TAM_MULTIREP_SCHEMA)
    as_bool(frozen_policy[:summary][
        :future_direct_multireplication_execution_completed]) &&
        error("refinement must be frozen before direct multireplication execution")

    snapshot = direct_gate_snapshot(frozen_policy)
    frozen_gate_unchanged = validate_frozen_gate(frozen_policy, snapshot)
    structural_passed = as_bool(
        recovery_policy[:summary][:structural_adapter_checks_passed])
    pilot_triangle = current_pilot_triangle_rows(recovery_policy, pilot)
    tam_context = tam_recovery_context_rows(multirep)
    direct_margins = pilot_direct_margin_rows(frozen_policy, pilot)
    axes = evidence_axis_rows(structural_passed, pilot, recovery_policy, multirep)
    recovery_thresholds = secondary_recovery_threshold_rows(recovery_policy)
    seed_rows = seed_registry_rows()
    seed_disjoint = seed_registry_is_disjoint(seed_rows)
    decision_probability_at_true_rate_080 = sum(
        binomial(5, successes) * 0.80^successes * 0.20^(5 - successes)
        for successes in 4:5)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy_refinement.v1",
        family = :mfrm,
        scope = :tam_direct_agreement_multiaxial_policy_refinement,
        status = :frozen_policy_refined_without_primary_gate_change,
        decision =
            :apply_adjudication_overlay_then_run_frozen_direct_multireplication,
        local_only = true,
        external_software = :tam,
        refinement_kind = :interpretation_adjudication_and_reporting_overlay,
        frozen_primary_thresholds_modified = false,
        frozen_primary_design_modified = false,
        direct_multireplication_execution_completed = false,
        external_software_validation_completed = false,
        public_claim_release_allowed = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = (;
            protocol_id = :mgmfrm_tam_direct_agreement_policy_refinement_v1,
            generator =
                "scripts/generate_mgmfrm_tam_direct_agreement_policy_refinement.jl",
            generator_source_sha256 = file_sha256(@__FILE__),
            refinement_freeze_order =
                :after_frozen_primary_policy_before_direct_multireplication_execution,
            primary_policy_role = :immutable_confirmatory_decision_rule,
            refinement_role = :prospective_interpretation_and_adjudication_overlay,
            retrospective_evidence_role = :context_only_no_threshold_recalibration,
        ),
        freeze_provenance = (;
            external_registration_status = :not_registered,
            cryptographic_timestamp_status = :not_recorded,
            git_commit_anchor_status = :not_recorded_for_this_local_freeze,
            local_hash_evidence_only = true,
            can_be_called_preregistered = false,
            can_be_called_locally_frozen_before_future_direct_runs = true,
            independent_freeze_verification_pending = true,
        ),
        environment_contract = (;
            project_toml = "Project.toml",
            project_toml_sha256 = file_sha256(joinpath(ROOT, "Project.toml")),
            manifest_toml = "Manifest.toml",
            manifest_toml_sha256 = file_sha256(joinpath(ROOT, "Manifest.toml")),
            julia_version = string(VERSION),
            r_and_tam_versions = :recorded_in_tam_fit_contract,
            os_blas_and_cpu_metadata_required_in_result = true,
            environment_hash_mismatch_disposition =
                :record_and_classify_as_new_versioned_reproduction_run,
        ),
        source_artifacts = (;
            frozen_policy = relpath(paths.frozen_policy, ROOT),
            frozen_policy_sha256 = file_sha256(paths.frozen_policy),
            baseline = relpath(paths.baseline, ROOT),
            baseline_sha256 = file_sha256(paths.baseline),
            direct_pilot = relpath(paths.direct_pilot, ROOT),
            direct_pilot_sha256 = file_sha256(paths.direct_pilot),
            recovery_policy = relpath(paths.recovery_policy, ROOT),
            recovery_policy_sha256 = file_sha256(paths.recovery_policy),
            tam_multireplication = relpath(paths.tam_multirep, ROOT),
            tam_multireplication_sha256 = file_sha256(paths.tam_multirep),
        ),
        frozen_primary_gate_snapshot = snapshot,
        frozen_primary_gate_fingerprint_sha256 = gate_fingerprint(snapshot),
        direct_threshold_table_sha256 = threshold_table_fingerprint(
            frozen_policy[:direct_threshold_rows], :direct),
        sampler_threshold_table_sha256 = threshold_table_fingerprint(
            frozen_policy[:sampler_threshold_rows], :sampler),
        inherited_design_scope = design_scope(baseline, frozen_policy),
        data_and_input_contract = data_and_input_contract(baseline, seed_rows),
        package_fit_contract = package_fit_contract(),
        tam_fit_contract = tam_fit_contract(multirep),
        artifact_archive_contract = artifact_archive_contract(),
        estimand_alignment_rows = estimand_alignment_rows(),
        evidence_axis_rows = axes,
        metric_role_rows = metric_role_rows(),
        block_discreteness_rows = block_discreteness_rows(frozen_policy, pilot),
        replication_precision_rows = replication_precision_rows(frozen_policy),
        replication_design_interpretation = (;
            observed_pass_rates_are_discrete = true,
            possible_pass_rates = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
            minimum_successes = 4,
            probability_of_observing_at_least_four_of_five_if_true_rate_is_0_80 =
                decision_probability_at_true_rate_080,
            can_establish_population_pass_probability_at_least_0_80 = false,
        ),
        retrospective_pilot_direct_margin_rows = direct_margins,
        retrospective_pilot_triangle_rows = pilot_triangle,
        tam_known_truth_context_rows = tam_context,
        secondary_recovery_qualifier = (;
            status = :prospective_secondary_claim_qualifier_frozen,
            purpose = :distinguish_direct_agreement_from_known_truth_recovery,
            estimators = [:package_posterior_mean, :tam_mml_estimate],
            application = :separate_estimator_vs_truth_evaluation_on_same_future_datasets,
            primary_person_count = 100,
            replications = 5,
            minimum_replications_passing_per_block = 4,
            all_blocks_required_for_qualifier = true,
            changes_frozen_primary_direct_gate = false,
            cannot_rescue_primary_direct_failure = true,
            cannot_veto_primary_direct_pass = true,
            threshold_rows = recovery_thresholds,
        ),
        estimand_triangle = (;
            primary_edge = :package_posterior_summary_vs_tam_mml_estimate,
            secondary_edges = [
                :package_posterior_summary_vs_known_truth,
                :tam_mml_estimate_vs_known_truth,
            ],
            required_interpretive_classification = [
                :agreement_with_recovery_support,
                :agreement_without_recovery_support,
                :nonagreement,
                :computationally_inconclusive,
                :protocol_invalid,
            ],
            shared_error_warning =
                :same_data_estimators_can_agree_while_both_deviate_from_truth,
        ),
        retry_and_missingness_policy = retry_policy(),
        decision_state_rows = decision_state_rows(),
        failure_taxonomy_rows = failure_taxonomy_rows(),
        equivalence_advisory = equivalence_advisory(),
        required_reporting_rows = reporting_rows(),
        model_scope_rows = scope_rows(),
        claim_wording_rows = claim_wording_rows(),
        claim_limits = [
            :original_thresholds_and_design_remain_unchanged,
            :direct_agreement_is_not_known_truth_recovery,
            :five_replications_are_a_decision_rule_not_precise_rate_estimation,
            :small_item_and_rater_blocks_make_correlation_and_coverage_discrete,
            :interval_containment_is_not_equivalence_testing,
            :same_data_estimators_can_share_sampling_error,
            :classical_rhat_and_autocorrelation_ess_are_provisional,
            :no_facets_or_conquest_execution,
            :no_generalized_gmfrm_or_mgmfrm_external_validation,
            :no_uto_2021_validation_inference_from_tam_overlap,
            :no_external_construct_or_population_validity_claim,
            :no_public_claim_release,
        ],
        summary = (;
            passed = frozen_gate_unchanged && structural_passed && seed_disjoint &&
                as_bool(pilot[:summary][:direct_estimate_pilot_completed]) &&
                as_bool(multirep[:summary][:primary_multireplication_gate_passed]) &&
                length(direct_margins) == 12 && length(pilot_triangle) == 3 &&
                length(tam_context) == 9 && length(recovery_thresholds) == 9,
            frozen_primary_gate_unchanged = frozen_gate_unchanged,
            frozen_primary_thresholds_modified = false,
            frozen_primary_design_modified = false,
            seed_registry_complete_and_disjoint = seed_disjoint &&
                length(seed_rows) == 10,
            structural_adapter_checks_passed = structural_passed,
            retrospective_direct_pilot_all_thresholds_passed =
                all(row -> row.pilot_passed, direct_margins),
            retrospective_pilot_full_recovery_support =
                all(row -> row.both_estimators_truth_recovery_profiles_passed,
                    pilot_triangle),
            retrospective_pilot_classification =
                all(row -> row.both_estimators_truth_recovery_profiles_passed,
                    pilot_triangle) ?
                    :descriptive_agreement_with_both_estimators_recovery_support :
                    :descriptive_agreement_without_full_recovery_support,
            tam_known_truth_n40_item_step_pass_rate = only(
                row.all_recovery_thresholds_pass_rate for row in tam_context
                if row.n_persons == 40 && row.block === :item_step),
            tam_known_truth_n100_item_step_pass_rate = only(
                row.all_recovery_thresholds_pass_rate for row in tam_context
                if row.n_persons == 100 && row.block === :item_step),
            tam_known_truth_n250_primary_gate_passed =
                as_bool(multirep[:summary][:primary_multireplication_gate_passed]),
            secondary_recovery_qualifier_frozen = true,
            direct_multireplication_execution_completed = false,
            external_software_validation_completed = false,
            public_claim_release_allowed = false,
            n_evidence_axes = length(axes),
            n_estimand_alignment_rows = length(estimand_alignment_rows()),
            n_metric_roles = length(metric_role_rows()),
            n_decision_states = length(decision_state_rows()),
            n_failure_taxonomy_rows = length(failure_taxonomy_rows()),
            n_required_reporting_rows = length(reporting_rows()),
            next_gate =
                :run_predeclared_multireplication_package_vs_tam_direct_agreement_under_refined_adjudication,
        ),
    )
end

function main(args)
    parsed = parse_args(args)
    artifact = build_artifact(parsed)
    write_artifact(parsed.output, artifact)
    println("wrote ", relpath(parsed.output, ROOT))
    println(
        "passed=", artifact.summary.passed,
        " frozen_gate_unchanged=", artifact.summary.frozen_primary_gate_unchanged,
        " pilot_classification=", artifact.summary.retrospective_pilot_classification,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
