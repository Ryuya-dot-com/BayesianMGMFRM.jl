#!/usr/bin/env julia

using SHA
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT = joinpath(
    ROOT,
    "test",
    "fixtures",
    "local_dependence_calibration_scorer_preflight.json",
)
const CALIBRATION_SOURCE =
    joinpath(ROOT, "src", "local_dependence_calibration.jl")
const CALIBRATION_TEST =
    joinpath(ROOT, "test", "local_dependence_calibration.jl")
const LD1_DGP_SOURCE =
    joinpath(ROOT, "src", "local_dependence_known_truth_dgp.jl")
const LD1_ADAPTER_SOURCE =
    joinpath(ROOT, "src", "local_dependence_simulation.jl")

include(joinpath(@__DIR__, "local_json.jl"))

function usage()
    return """
    Generate the deterministic, MCMC-free LD1b0 calibration-scorer preflight.

    The artifact freezes the scorer contract, retains every planned scenario in
    the denominator, materializes the declared pre-fit rejection rows, and
    checks unresolved-rate and aggregation semantics. It does not fit a model,
    run MCMC, complete repeated calibration, or assign diagnostic decisions.

    Usage:
      julia --project=. scripts/generate_local_dependence_calibration_scorer_preflight.jl [--output PATH]
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

function planning_row_record(row)
    return (;
        row_index = row.row_index,
        scenario_index = row.scenario_index,
        scenario_id = row.scenario_id,
        matched_set_id = row.matched_set_id,
        replication = row.replication,
        phase = row.phase,
        base_seed = row.base_seed,
        seed = row.seed,
        mechanism = row.mechanism,
        magnitude_label = row.magnitude_label,
        design = row.design,
        assignment = row.assignment,
        order = row.order,
        expected_structural_eligibility =
            row.expected_requested_targets_eligible,
    )
end

function simulation_provenance_record(provenance)
    ismissing(provenance) && return missing
    return merge(provenance, (;
        data_signature = string(provenance.data_signature),
    ))
end

function result_row_record(row)
    return (;
        row_index = row.row_index,
        scenario_index = row.scenario_index,
        scenario_id = row.scenario_id,
        matched_set_id = row.matched_set_id,
        status = row.status,
        expected_structural_eligibility =
            row.expected_structural_eligibility,
        truth = row.truth,
        execution_seeds = row.execution_seeds,
        simulation_provenance =
            simulation_provenance_record(row.simulation_provenance),
        n_pair_evidence = row.n_pair_evidence,
        target_evidence_available = row.target_evidence_available,
        pair_truth_oracle_available = row.pair_truth_oracle_available,
        pairwise_power_available = row.pairwise_power_available,
        repeated_calibration_completed = row.repeated_calibration_completed,
        calibration_evidence_available = row.calibration_evidence_available,
        diagnostic_decision_labels_available =
            row.diagnostic_decision_labels_available,
        mechanism_interpretation_eligible =
            row.mechanism_interpretation_eligible,
    )
end

function contract_checks(contract)
    thresholds = contract.candidate_thresholds
    return (;
        schema_valid = contract.schema ==
            "bayesianmgmfrm.local_dependence_calibration_contract.v1",
        object_valid = contract.object ===
            :local_dependence_calibration_contract,
        protocol_status_valid = contract.status === :protocol_preflight_only,
        threshold_sources_frozen =
            thresholds.pair_raw_source ===
                :finite_sample_corrected_posterior_predictive_tail_fraction &&
            thresholds.pair_bh_source ===
                :within_family_bh_adjusted_tail_fraction &&
            thresholds.family_source ===
                :family_maximum_statistic_tail_fraction &&
            thresholds.global_source ===
                :all_family_maximum_statistic_tail_fraction,
        wilson_scope_valid =
            contract.monte_carlo_interval.method === :wilson_score &&
            contract.monte_carlo_interval.applies_to ===
                :replication_level_binary_rates_only,
        deterministic_seed_namespaces_recorded =
            !contract.seed_contract.mutable_default_rng_used &&
            contract.seed_contract.scenario_key === :frozen_scenario_id,
        target_evidence_unavailable = !contract.target_evidence_available,
        pair_truth_oracle_unavailable =
            !contract.pair_truth_oracle_available,
        pairwise_power_unavailable = !contract.pairwise_power_available,
        repeated_calibration_incomplete =
            !contract.repeated_calibration_completed,
        calibration_evidence_unavailable =
            !contract.calibration_evidence_available,
        diagnostic_decision_labels_unavailable =
            !contract.diagnostic_decision_labels_available,
        mechanism_interpretation_unavailable =
            !contract.mechanism_interpretation_eligible,
    )
end

function scorer_checks(plan, result_rows, summary)
    eligible_plan = count(row ->
        row.expected_requested_targets_eligible, plan)
    scenario_unresolved = all(summary.scenario_rows) do row
        blocks = (row.pair_raw_any, row.pair_bh_any, row.global_maximum)
        all(block -> block.n_resolved == 0 &&
            block.n_unresolved == block.n_planned &&
            ismissing(block.rate.estimate), blocks)
    end
    family_unresolved = all(summary.family_rows) do row
        blocks = (row.pair_raw_any, row.pair_bh_any, row.family_maximum)
        all(block -> block.n_resolved == 0 &&
            block.n_unresolved == block.n_planned &&
            ismissing(block.rate.estimate), blocks)
    end
    global_unresolved = all(summary.global_rows) do row
        block = row.candidate_global_maximum
        block.n_resolved == 0 && block.n_unresolved == block.n_planned &&
            ismissing(block.rate.estimate)
    end
    pooled_pair_intervals_absent =
        all(row -> !row.pooled_pair_raw.wilson_interval_available &&
            !row.pooled_pair_bh.wilson_interval_available,
            summary.scenario_rows) &&
        all(row -> !row.pooled_pair_wilson_interval_available,
            summary.family_rows)
    status_counts = Dict(row.status => row.n for row in summary.status_rows)
    return (;
        frozen_planning_scenario_count = length(plan) == 22,
        structural_routing_complete = eligible_plan == 18 &&
            length(result_rows) == 4 &&
            eligible_plan + length(result_rows) == length(plan),
        all_planned_rows_retained = summary.n_plan_rows == length(plan),
        pre_fit_rejections_recorded =
            get(status_counts, :pre_fit_rejected, 0) == length(result_rows),
        eligible_rows_remain_unresolved =
            summary.n_missing_result_rows == eligible_plan,
        no_pair_evidence_scored = summary.n_pair_evidence_rows == 0,
        scenario_binary_rates_unresolved = scenario_unresolved,
        family_binary_rates_unresolved = family_unresolved,
        global_binary_rates_unresolved = global_unresolved,
        pooled_pair_rates_have_no_wilson_interval =
            pooled_pair_intervals_absent,
        pairwise_power_unavailable = !summary.pairwise_power_available,
        target_evidence_unavailable = !summary.target_evidence_available,
        repeated_calibration_incomplete =
            !summary.repeated_calibration_completed,
        calibration_evidence_unavailable =
            !summary.calibration_evidence_available,
        diagnostic_decision_labels_unavailable =
            !summary.diagnostic_decision_labels_available,
        mechanism_interpretation_unavailable =
            !summary.mechanism_interpretation_eligible,
    )
end

all_checks_pass(checks) = all(identity, values(checks))

function build_artifact()
    plan = BayesianMGMFRM.local_dependence_simulation_grid(
        repetitions = 1,
        phase = :smoke,
        grid_id = "ld1b0_scorer_preflight",
        n_persons = 8,
        n_testlets = 4,
        items_per_testlet = 2,
        n_raters = 2,
        n_categories = 4,
    )
    diagnostic_contract = BayesianMGMFRM.local_dependence_contract()
    contract = BayesianMGMFRM.local_dependence_calibration_contract(;
        diagnostic_contract,
    )

    rejected_plan = [row for row in plan
        if !row.expected_requested_targets_eligible]
    result_rows = NamedTuple[]
    for row in rejected_plan
        simulation = BayesianMGMFRM.simulate_local_dependence(row)
        push!(result_rows,
            BayesianMGMFRM.local_dependence_calibration_row(
                row;
                contract,
                status = :pre_fit_rejected,
                simulation,
            ))
    end
    scorer_summary = BayesianMGMFRM.local_dependence_calibration_summary(
        plan,
        result_rows;
        contract,
    )
    checked_contract = contract_checks(contract)
    checked_scorer = scorer_checks(plan, result_rows, scorer_summary)
    passed = all_checks_pass(checked_contract) &&
        all_checks_pass(checked_scorer)

    artifact = (;
        schema =
            "bayesianmgmfrm.local_dependence_calibration_scorer_preflight.v1",
        family = :mfrm,
        scope = :ld1b0_calibration_scorer_protocol_preflight,
        status = passed ? :scorer_protocol_preflight_passed :
            :scorer_protocol_preflight_failed,
        package = (;
            name = :BayesianMGMFRM,
            version = project_version(),
        ),
        generator = (;
            script =
                "scripts/generate_local_dependence_calibration_scorer_preflight.jl",
            script_source_sha256 = file_sha256(@__FILE__),
            calibration_source = "src/local_dependence_calibration.jl",
            calibration_source_sha256 = file_sha256(CALIBRATION_SOURCE),
            calibration_test = "test/local_dependence_calibration.jl",
            calibration_test_sha256 = file_sha256(CALIBRATION_TEST),
            known_truth_source =
                "src/local_dependence_known_truth_dgp.jl",
            known_truth_source_sha256 = file_sha256(LD1_DGP_SOURCE),
            adapter_source = "src/local_dependence_simulation.jl",
            adapter_source_sha256 = file_sha256(LD1_ADAPTER_SOURCE),
            environment_provenance = (;
                project = "Project.toml",
                project_sha256 =
                    file_sha256(joinpath(ROOT, "Project.toml")),
                manifest = "Manifest.toml",
                manifest_sha256 =
                    file_sha256(joinpath(ROOT, "Manifest.toml")),
                julia_compat = project_julia_compat(),
                exact_runtime_version_recorded = false,
                cross_julia_bitwise_portability_claimed = false,
            ),
        ),
        execution_scope = (;
            planning_profile = first(plan).profile,
            calibration_profile = contract.profile,
            phase = first(plan).phase,
            repetitions = 1,
            base_dimensions = (;
                n_persons = 8,
                n_testlets = 4,
                items_per_testlet = 2,
                n_raters = 2,
                n_categories = 4,
            ),
            n_planned_rows = length(plan),
            n_structurally_eligible_rows = count(
                row -> row.expected_requested_targets_eligible, plan),
            n_pre_fit_rejection_rows = length(result_rows),
            n_completed_diagnostic_rows = 0,
            runs_known_truth_generation = true,
            runs_design_preflight = true,
            runs_model_fit = false,
            runs_mcmc = false,
            runs_local_dependence_summary = false,
            calibration_completed = false,
        ),
        protocol_contract = contract,
        planning_rows = Tuple(planning_row_record(row) for row in plan),
        pre_fit_rejection_rows =
            Tuple(result_row_record(row) for row in result_rows),
        scorer_summary,
        checks = (;
            contract = checked_contract,
            scorer = checked_scorer,
        ),
        evidence_status = (;
            target_evidence_available = false,
            pair_truth_oracle_available = false,
            pairwise_power_available = false,
            repeated_calibration_completed = false,
            calibration_evidence_available = false,
            diagnostic_decision_labels_available = false,
            mechanism_interpretation_eligible = false,
        ),
        remaining_work = (;
            pilot_repetitions = :pending,
            evaluation_repetitions = :pending,
            completed_diagnostic_rows = :pending,
            frozen_threshold_evaluation = :pending,
        ),
        summary = (;
            passed,
            n_planned_rows = length(plan),
            n_structurally_eligible_rows = count(
                row -> row.expected_requested_targets_eligible, plan),
            n_pre_fit_rejection_rows = length(result_rows),
            n_scenario_rows = length(scorer_summary.scenario_rows),
            n_family_rows = length(scorer_summary.family_rows),
            n_global_rows = length(scorer_summary.global_rows),
            n_matched_set_rows = length(scorer_summary.matched_set_rows),
            runs_mcmc = false,
            calibration_completed = false,
            calibration_evidence_available = false,
            diagnostic_decision_labels_available = false,
            mechanism_interpretation_eligible = false,
            subsequent_stage = :ld1b_pilot_then_frozen_evaluation,
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
        " planned_rows=", artifact.summary.n_planned_rows,
        " pre_fit_rejections=", artifact.summary.n_pre_fit_rejection_rows,
        " calibration_completed=", artifact.summary.calibration_completed,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
