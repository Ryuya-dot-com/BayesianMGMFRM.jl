#!/usr/bin/env julia

using JSON3
using Random
using SHA
using Statistics
using TOML

include(joinpath(@__DIR__, "generate_mgmfrm_tam_overlap_execution_review.jl"))

const MULTIREP_DEFAULT_BASELINE = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_overlap_baseline.json")
const MULTIREP_DEFAULT_POLICY = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_comparison_policy_review.json")
const MULTIREP_DEFAULT_OUTPUT = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_multireplication_comparison.json")
const MULTIREP_POLICY_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_comparison_policy_review.v1"
const MULTIREP_BASE_SEED = 20260712
const MULTIREP_PERSON_COUNTS = [40, 100, 250]
const MULTIREP_REPLICATIONS = 10
const MULTIREP_PRIMARY_PERSON_COUNT = 250
const MULTIREP_PRIMARY_PASS_RATE = 0.80

function multirep_usage()
    return """
    Run the predeclared multi-replication TAM known-truth comparison.

    The protocol inherits numerical thresholds from the frozen TAM comparison
    policy. It evaluates 10 replications at 40, 100, and 250 persons, with the
    250-person condition serving as the primary gate. It does not fit the
    BayesianMGMFRM estimator, approve broad external validation, publish,
    register, push, or upload.

    Usage:
      julia --project=. scripts/generate_mgmfrm_tam_multireplication_comparison.jl [--baseline PATH] [--policy PATH] [--output PATH]
    """
end

function multirep_parse_args(args)
    baseline = MULTIREP_DEFAULT_BASELINE
    policy = MULTIREP_DEFAULT_POLICY
    output = MULTIREP_DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--baseline"
            index < length(args) || error("--baseline requires a path")
            baseline = abspath(args[index + 1])
            index += 2
        elseif arg == "--policy"
            index < length(args) || error("--policy requires a path")
            policy = abspath(args[index + 1])
            index += 2
        elseif arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(multirep_usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; baseline, policy, output)
end

function multirep_seed(n_persons::Int, replication::Int, stream::Int)
    scenario = findfirst(==(n_persons), MULTIREP_PERSON_COUNTS)
    scenario === nothing && error("unregistered person count: $n_persons")
    return MULTIREP_BASE_SEED + 100000 * scenario + 1000 * replication + stream
end

function fixed_truth(baseline)
    truth = baseline[:truth]
    return (;
        item_difficulty = Float64.(truth[:item_difficulty]),
        rater_severity = Float64.(truth[:rater_severity]),
        item_steps = [Float64.(steps) for steps in truth[:item_steps]],
    )
end

function softmax_probabilities(values)
    shifted = values .- maximum(values)
    weights = exp.(shifted)
    return weights ./ sum(weights)
end

function response_probabilities(truth, ability::Float64, rater::Int, item::Int)
    categories = length(truth.item_steps[item]) + 1
    location = ability - truth.rater_severity[rater] -
        truth.item_difficulty[item]
    eta = zeros(Float64, categories)
    cumulative_step = 0.0
    for category in 2:categories
        cumulative_step += truth.item_steps[item][category - 1]
        eta[category] = (category - 1) * location - cumulative_step
    end
    return softmax_probabilities(eta)
end

function sample_category(rng::AbstractRNG, probabilities)
    draw = rand(rng)
    cumulative = 0.0
    for index in eachindex(probabilities)
        cumulative += probabilities[index]
        draw <= cumulative && return index - 1
    end
    return length(probabilities) - 1
end

function write_replication_csv(path::AbstractString, baseline,
        n_persons::Int, replication::Int)
    truth = fixed_truth(baseline)
    ability_seed = multirep_seed(n_persons, replication, 1)
    response_seed = multirep_seed(n_persons, replication, 3)
    ability_rng = MersenneTwister(ability_seed)
    response_rng = MersenneTwister(response_seed)
    abilities = randn(ability_rng, n_persons)
    category_counts = zeros(Int, length(first(truth.item_steps)) + 1)
    observation_count = 0
    open(path, "w") do io
        println(io, "person,rater,item,score")
        for person in 1:n_persons,
                rater in eachindex(truth.rater_severity),
                item in eachindex(truth.item_difficulty)
            probabilities = response_probabilities(
                truth, abilities[person], rater, item)
            score = sample_category(response_rng, probabilities)
            println(io, person, ',', rater, ',', item, ',', score)
            category_counts[score + 1] += 1
            observation_count += 1
        end
    end
    return (;
        ability_seed,
        response_seed,
        n_observations = observation_count,
        category_counts,
        all_categories_observed = all(>(0), category_counts),
        csv_sha256 = file_sha256(path),
    )
end

function threshold_map(policy)
    output = Dict{Tuple{String,String},NamedTuple}()
    for row in policy[:numerical_threshold_rows]
        key = (as_string(row[:block]), as_string(row[:metric]))
        output[key] = (;
            direction = Symbol(as_string(row[:direction])),
            threshold = as_float(row[:threshold]),
        )
    end
    return output
end

function metric_pass(value::Real, rule)
    return rule.direction === :minimum ? value >= rule.threshold :
           value <= rule.threshold
end

function evaluated_comparison_rows(comparisons, thresholds)
    return [(;
        block = comparison.block,
        n_parameters = comparison.n_parameters,
        adapter = comparison.adapter,
        pearson_correlation = comparison.pearson_correlation,
        mean_abs_difference = comparison.mean_abs_difference,
        max_abs_difference = comparison.max_abs_difference,
        correlation_threshold = thresholds[(
            String(comparison.block), "pearson_correlation")].threshold,
        mean_abs_difference_threshold = thresholds[(
            String(comparison.block), "mean_abs_difference")].threshold,
        max_abs_difference_threshold = thresholds[(
            String(comparison.block), "max_abs_difference")].threshold,
        correlation_passed = metric_pass(
            comparison.pearson_correlation,
            thresholds[(String(comparison.block), "pearson_correlation")]),
        mean_abs_difference_passed = metric_pass(
            comparison.mean_abs_difference,
            thresholds[(String(comparison.block), "mean_abs_difference")]),
        max_abs_difference_passed = metric_pass(
            comparison.max_abs_difference,
            thresholds[(String(comparison.block), "max_abs_difference")]),
        all_thresholds_passed =
            metric_pass(comparison.pearson_correlation,
                thresholds[(String(comparison.block), "pearson_correlation")]) &&
            metric_pass(comparison.mean_abs_difference,
                thresholds[(String(comparison.block), "mean_abs_difference")]) &&
            metric_pass(comparison.max_abs_difference,
                thresholds[(String(comparison.block), "max_abs_difference")]),
    ) for comparison in comparisons]
end

function replication_row(baseline, thresholds, n_persons::Int, replication::Int)
    temp_root = mktempdir()
    csv_path = joinpath(temp_root, "tam_replication.csv")
    generated = write_replication_csv(
        csv_path, baseline, n_persons, replication)
    tam = run_tam(csv_path)
    summary = only(tam.summary_rows)
    parameters = tam_parameter_rows(tam.xsi_rows)
    comparisons = evaluated_comparison_rows(
        comparison_rows(baseline, parameters), thresholds)
    return (;
        n_persons,
        replication,
        ability_seed = generated.ability_seed,
        response_seed = generated.response_seed,
        n_observations = generated.n_observations,
        category_counts = generated.category_counts,
        all_categories_observed = generated.all_categories_observed,
        observation_csv_sha256 = generated.csv_sha256,
        tam_iter = parse_int(summary.iter),
        tam_deviance = parse_float(summary.deviance),
        tam_eap_rel = parse_float(summary.eap_rel),
        tam_n_parameters = parse_int(summary.Npars),
        tam_r_version = as_string(summary.r_version),
        tam_version = as_string(summary.tam_version),
        rscript_path = tam.rscript,
        tam_xsi_facets_sha256 = tam.xsi_csv_sha256,
        comparisons,
        all_blocks_passed = all(row -> row.all_thresholds_passed, comparisons),
    )
end

function quantile_value(values, probability::Real)
    return quantile(Float64.(values), probability)
end

function scenario_block_rows(replications)
    output = NamedTuple[]
    for n_persons in MULTIREP_PERSON_COUNTS,
            block in (:item_difficulty, :rater_severity, :item_step)
        rows = [only(row for row in replication.comparisons
                    if row.block == block)
            for replication in replications if replication.n_persons == n_persons]
        pass_rate = mean(row.all_thresholds_passed for row in rows)
        push!(output, (;
            n_persons,
            block,
            n_replications = length(rows),
            median_pearson_correlation =
                median(row.pearson_correlation for row in rows),
            minimum_pearson_correlation =
                minimum(row.pearson_correlation for row in rows),
            median_mean_abs_difference =
                median(row.mean_abs_difference for row in rows),
            percentile90_mean_abs_difference = quantile_value(
                [row.mean_abs_difference for row in rows], 0.90),
            median_max_abs_difference =
                median(row.max_abs_difference for row in rows),
            percentile90_max_abs_difference = quantile_value(
                [row.max_abs_difference for row in rows], 0.90),
            n_all_thresholds_passed = count(row -> row.all_thresholds_passed, rows),
            all_thresholds_pass_rate = pass_rate,
            primary_gate_row = n_persons == MULTIREP_PRIMARY_PERSON_COUNT,
            primary_pass_rate_threshold = MULTIREP_PRIMARY_PASS_RATE,
            primary_gate_passed = n_persons == MULTIREP_PRIMARY_PERSON_COUNT ?
                pass_rate >= MULTIREP_PRIMARY_PASS_RATE : false,
        ))
    end
    return output
end

function multirep_build_artifact(baseline_path::AbstractString,
        policy_path::AbstractString)
    baseline = load_json(baseline_path)
    as_string(baseline[:schema]) == BASELINE_SCHEMA ||
        error("unexpected baseline schema")
    policy = load_json(policy_path)
    as_string(policy[:schema]) == MULTIREP_POLICY_SCHEMA ||
        error("unexpected policy schema")
    Bool(policy[:summary][:prospective_thresholds_frozen]) ||
        error("TAM thresholds are not frozen")
    thresholds = threshold_map(policy)
    replications = NamedTuple[]
    for n_persons in MULTIREP_PERSON_COUNTS, replication in 1:MULTIREP_REPLICATIONS
        push!(replications,
            replication_row(baseline, thresholds, n_persons, replication))
    end
    scenario_blocks = scenario_block_rows(replications)
    primary_rows = [row for row in scenario_blocks if row.primary_gate_row]
    primary_passed = all(row -> row.primary_gate_passed, primary_rows)
    all_executions_valid = all(row ->
            row.tam_iter > 0 && isfinite(row.tam_deviance) &&
            row.tam_n_parameters == 19 && row.all_categories_observed,
        replications)
    first_environment = first(replications)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_tam_multireplication_comparison.v1",
        family = :mfrm,
        scope = :tam_predeclared_multireplication_known_truth_comparison,
        status = :tam_multireplication_comparison_recorded,
        decision = primary_passed ?
            :record_tam_multireplication_gate_pass_keep_broad_claim_blocked :
            :record_tam_multireplication_gate_fail_keep_broad_claim_blocked,
        local_only = true,
        external_software = :tam,
        tam_multireplication_execution_completed = true,
        package_estimator_direct_comparison_completed = false,
        external_software_validation_completed = false,
        public_claim_release_allowed = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = (;
            protocol_id = :mgmfrm_tam_multireplication_comparison_v1,
            generator =
                "scripts/generate_mgmfrm_tam_multireplication_comparison.jl",
            generator_source_sha256 = file_sha256(@__FILE__),
            baseline_artifact = relpath(baseline_path, ROOT),
            baseline_artifact_sha256 = file_sha256(baseline_path),
            policy_artifact = relpath(policy_path, ROOT),
            policy_artifact_sha256 = file_sha256(policy_path),
            inherited_thresholds_unchanged = true,
            base_seed = MULTIREP_BASE_SEED,
            person_counts = MULTIREP_PERSON_COUNTS,
            replications_per_person_count = MULTIREP_REPLICATIONS,
            primary_person_count = MULTIREP_PRIMARY_PERSON_COUNT,
            primary_block_pass_rate_threshold = MULTIREP_PRIMARY_PASS_RATE,
            primary_gate =
                :each_parameter_block_all_metric_pass_rate_at_least_0_80,
            response_assignment = :fully_crossed_person_by_rater_by_item,
            item_rater_step_truth = :fixed_from_tam_overlap_baseline,
            person_abilities = :new_normal_0_1_draw_per_replication,
        ),
        tam_environment = (;
            r_version = first_environment.tam_r_version,
            tam_version = first_environment.tam_version,
            rscript_path = first_environment.rscript_path,
        ),
        relationship_scope = (;
            comparison = :tam_estimates_against_shared_known_truth,
            package_role =
                :standalone_generator_previously_checked_against_package_probability_oracle,
            direct_package_posterior_vs_tam_estimate_comparison = false,
            generalized_gmfrm_or_mgmfrm_scope = false,
        ),
        replication_rows = replications,
        scenario_block_summary_rows = scenario_blocks,
        claim_limits = [
            :known_truth_tam_recovery_only,
            :not_direct_bayesianmgmfrm_posterior_vs_tam_estimate_agreement,
            :fixed_item_rater_step_truth_single_design,
            :no_facets_or_conquest_execution,
            :no_generalized_gmfrm_or_mgmfrm_external_validation,
            :no_external_construct_validity_claim,
            :no_public_claim_release,
        ],
        summary = (;
            passed = all_executions_valid && primary_passed,
            all_tam_executions_valid = all_executions_valid,
            primary_multireplication_gate_passed = primary_passed,
            n_scenarios = length(MULTIREP_PERSON_COUNTS),
            n_replications = length(replications),
            n_parameter_comparison_rows =
                sum(length(row.comparisons) for row in replications),
            n_primary_block_rows = length(primary_rows),
            n_primary_block_rows_passed =
                count(row -> row.primary_gate_passed, primary_rows),
            package_estimator_direct_comparison_completed = false,
            external_software_validation_completed = false,
            public_claim_release_allowed = false,
            next_gate = :compare_package_posterior_summaries_directly_with_tam_estimates,
        ),
    )
end

function multirep_main(args)
    parsed = multirep_parse_args(args)
    artifact = multirep_build_artifact(parsed.baseline, parsed.policy)
    write_artifact(parsed.output, artifact)
    println("wrote ", relpath(parsed.output, ROOT))
    println(
        "passed=", artifact.summary.passed,
        " replications=", artifact.summary.n_replications,
        " primary_blocks=", artifact.summary.n_primary_block_rows_passed,
        "/", artifact.summary.n_primary_block_rows,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && multirep_main(ARGS)
