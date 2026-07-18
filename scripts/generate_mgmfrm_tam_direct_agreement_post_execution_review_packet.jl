#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_RESULT = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_tam_direct_agreement_multireplication.json")
const DEFAULT_RAW_AUDIT = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_tam_direct_agreement_raw_archive_audit.json")
const DEFAULT_POLICY = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_direct_agreement_policy.json")
const DEFAULT_REFINEMENT = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_tam_direct_agreement_policy_refinement.json")
const DEFAULT_PRE_EXECUTION_PACKET = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_literature_anchored_independent_review_packet.json")
const DEFAULT_OUTPUT = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_tam_direct_agreement_post_execution_review_packet.json")

const RESULT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_multireplication.v1"
const RAW_AUDIT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_raw_archive_audit.v1"
const POLICY_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy.v1"
const REFINEMENT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy_refinement.v1"
const PRE_EXECUTION_PACKET_SCHEMA =
    "bayesianmgmfrm.mgmfrm_literature_anchored_independent_review_packet.v1"
const PACKET_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_post_execution_review_packet.v1"

include(joinpath(@__DIR__, "local_json.jl"))

const REVIEW_TASKS = [
    (task = :frozen_policy_integrity,
        evidence = :policy_refinement_and_result_hash_chain),
    (task = :pre_execution_chronology_and_amendment,
        evidence =
            :immutable_pre_execution_packet_hashes_compared_with_final_execution_inputs),
    (task = :protocol_alignment,
        evidence = :all_ten_jobs_follow_the_frozen_design_and_seed_registry),
    (task = :tam_execution_validity,
        evidence = :per_job_tam_version_convergence_formula_and_constraint_checks),
    (task = :package_sampler_validity,
        evidence = :frozen_sampler_gate_on_all_ten_scheduled_fits),
    (task = :primary_gate_independent_recomputation,
        evidence = :n100_four_of_five_rule_for_all_three_parameter_blocks),
    (task = :stress_condition_review,
        evidence = :n40_results_reported_separately_from_the_primary_gate),
    (task = :truth_recovery_separation,
        evidence = :package_and_tam_recovery_are_qualifiers_not_agreement_metrics),
    (task = :interval_and_rope_interpretation,
        evidence = :interval_inclusion_and_conditional_rope_are_not_equivalence_tests),
    (task = :chain_stability_and_rank_advisories,
        evidence = :pooled_chain_decision_stability_and_rank_diagnostics),
    (task = :failure_and_retry_accounting,
        evidence = :all_attempts_retained_and_retry_does_not_reduce_denominator),
    (task = :raw_archive_hash_verification,
        evidence = :selected_and_nonselected_attempt_file_hash_manifest),
    (task = :independent_reexecution,
        evidence = :fresh_environment_reexecution_against_recorded_versions),
    (task = :claim_scope_review,
        evidence = :mfrm_pcm_only_no_package_wide_or_construct_validity_claim),
    (task = :uto_gmfrm_mgmfrm_nonextrapolation,
        evidence = :no_transfer_beyond_the_executed_unidimensional_unit_slope_scope),
]

const REVIEWER_MANIFEST_FIELDS = [
    (field = :schema,
        rule = :must_equal_tam_direct_post_execution_review_manifest_v1),
    (field = :reviewer_name_or_id,
        rule = :must_identify_the_independent_reviewer_or_review_body),
    (field = :reviewer_independence_statement,
        rule = :must_state_independence_from_package_authorship_and_execution),
    (field = :conflict_of_interest_statement,
        rule = :must_record_conflicts_or_no_conflicts),
    (field = :review_date,
        rule = :must_be_an_explicit_date),
    (field = :reviewed_packet_sha256,
        rule = :must_match_this_generated_packet),
    (field = :reviewed_result_sha256,
        rule = :must_match_the_multireplication_result),
    (field = :reviewed_raw_audit_sha256,
        rule = :must_match_the_all_attempt_raw_archive_audit),
    (field = :independent_environment_record,
        rule = :must_record_os_julia_r_tam_and_package_versions),
    (field = :independent_reexecution_record,
        rule = :must_record_commands_exit_statuses_and_output_hashes),
    (field = :per_task_decision_table,
        rule = :must_decide_every_review_task),
    (field = :per_claim_decision_table,
        rule = :must_allow_block_or_request_revision_for_every_claim),
    (field = :required_revisions,
        rule = :must_list_required_revisions_or_explicitly_state_none),
    (field = :signature,
        rule = :must_include_a_dated_signature_or_equivalent_audit_record),
]

function usage()
    return """
    Generate the independent post-execution review packet for the frozen
    package-versus-TAM multireplication run.

    This packet records the completed local execution and prepares evidence for
    review. It does not perform the independent review, approve public claims,
    publish, register, upload, or assign a reviewer.

    Usage:
      julia --project=. scripts/generate_mgmfrm_tam_direct_agreement_post_execution_review_packet.jl [options]

    Options:
      --result PATH
      --raw-audit PATH
      --policy PATH
      --refinement PATH
      --pre-execution-packet PATH
      --output PATH
    """
end

function parse_args(args)
    result = DEFAULT_RESULT
    raw_audit = DEFAULT_RAW_AUDIT
    policy = DEFAULT_POLICY
    refinement = DEFAULT_REFINEMENT
    pre_execution_packet = DEFAULT_PRE_EXECUTION_PACKET
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--result"
            index < length(args) || error("--result requires a path")
            result = abspath(args[index + 1])
            index += 2
        elseif arg == "--raw-audit"
            index < length(args) || error("--raw-audit requires a path")
            raw_audit = abspath(args[index + 1])
            index += 2
        elseif arg == "--policy"
            index < length(args) || error("--policy requires a path")
            policy = abspath(args[index + 1])
            index += 2
        elseif arg == "--refinement"
            index < length(args) || error("--refinement requires a path")
            refinement = abspath(args[index + 1])
            index += 2
        elseif arg == "--pre-execution-packet"
            index < length(args) ||
                error("--pre-execution-packet requires a path")
            pre_execution_packet = abspath(args[index + 1])
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
        result, raw_audit, policy, refinement, pre_execution_packet, output)
end

load_json(path::AbstractString) = JSON3.read(read(path, String))
as_string(value) = String(value)
as_symbol(value) = Symbol(as_string(value))
as_bool(value) = Bool(value)
as_int(value) = Int(value)

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])

function file_sha256(path::AbstractString)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

function checked_artifact(path::AbstractString, schema::AbstractString)
    isfile(path) || error("required artifact missing: $(relpath(path, ROOT))")
    artifact = load_json(path)
    as_string(artifact[:schema]) == schema ||
        error("unexpected schema for $(relpath(path, ROOT))")
    return artifact
end

function source_row(name::Symbol, path::AbstractString,
        schema::AbstractString; role::Symbol)
    return (;
        input = name,
        path = relpath(path, ROOT),
        sha256 = file_sha256(path),
        schema,
        present = true,
        role,
        reviewer_must_verify = true,
    )
end

function review_task_rows()
    return [(;
        task = row.task,
        required_evidence = row.evidence,
        reviewer_required = true,
        reviewer_decision = :pending_independent_review,
        completed = false,
        blocks_public_claim_release = true,
    ) for row in REVIEW_TASKS]
end

function reviewer_manifest_field_rows()
    return [(;
        field = row.field,
        required = true,
        completed = false,
        validation_rule = row.rule,
        placeholder_policy = :reviewer_supplied_no_default,
    ) for row in REVIEWER_MANIFEST_FIELDS]
end

function claim_review_rows(result)
    primary_supported = as_bool(
        result[:outcome][:primary_direct_gate_passed])
    safe_wording = as_symbol(result[:outcome][:safe_local_wording])
    return [
        (;
            claim = :safe_local_outcome_wording,
            wording = safe_wording,
            artifact_support = true,
            primary_direct_gate_passed = primary_supported,
            tested_scope_only = true,
            reviewer_decision = :pending_independent_review,
            public_claim_allowed = false,
        ),
        (;
            claim = :package_and_tam_estimators_are_equivalent,
            wording = :prohibited_equivalence_claim,
            artifact_support = false,
            tested_scope_only = false,
            reviewer_decision = :must_remain_blocked,
            public_claim_allowed = false,
        ),
        (;
            claim = :tam_validates_the_package,
            wording = :prohibited_package_wide_validation_claim,
            artifact_support = false,
            tested_scope_only = false,
            reviewer_decision = :must_remain_blocked,
            public_claim_allowed = false,
        ),
        (;
            claim = :gmfrm_or_mgmfrm_validated,
            wording = :prohibited_generalized_model_transfer,
            artifact_support = false,
            tested_scope_only = false,
            reviewer_decision = :must_remain_blocked,
            public_claim_allowed = false,
        ),
        (;
            claim = :uto_2021_reproduced_or_externally_validated,
            wording = :prohibited_source_study_validation_claim,
            artifact_support = false,
            tested_scope_only = false,
            reviewer_decision = :must_remain_blocked,
            public_claim_allowed = false,
        ),
        (;
            claim = :construct_population_fairness_or_performance_validity,
            wording = :prohibited_construct_or_population_transfer,
            artifact_support = false,
            tested_scope_only = false,
            reviewer_decision = :must_remain_blocked,
            public_claim_allowed = false,
        ),
    ]
end

function build_artifact(parsed)
    result = checked_artifact(parsed.result, RESULT_SCHEMA)
    raw_audit = checked_artifact(parsed.raw_audit, RAW_AUDIT_SCHEMA)
    policy = checked_artifact(parsed.policy, POLICY_SCHEMA)
    refinement = checked_artifact(parsed.refinement, REFINEMENT_SCHEMA)
    pre_packet = checked_artifact(
        parsed.pre_execution_packet, PRE_EXECUTION_PACKET_SCHEMA)
    tasks = review_task_rows()
    fields = reviewer_manifest_field_rows()
    claims = claim_review_rows(result)
    required_inputs = [
        source_row(:multireplication_result, parsed.result, RESULT_SCHEMA;
            role = :completed_execution_and_decision_record),
        source_row(:all_attempt_raw_archive_audit, parsed.raw_audit,
            RAW_AUDIT_SCHEMA; role = :raw_hash_and_retry_accounting),
        source_row(:frozen_policy, parsed.policy, POLICY_SCHEMA;
            role = :pre_execution_primary_threshold_contract),
        source_row(:policy_refinement, parsed.refinement, REFINEMENT_SCHEMA;
            role = :pre_execution_interpretation_and_execution_contract),
        source_row(:pre_execution_independent_review_packet,
            parsed.pre_execution_packet, PRE_EXECUTION_PACKET_SCHEMA;
            role = :immutable_pre_execution_review_snapshot),
    ]
    result_protocol = result[:protocol]
    baseline_path = joinpath(ROOT,
        as_string(result_protocol[:baseline_artifact]))
    recovery_policy_path = joinpath(ROOT,
        as_string(result_protocol[:recovery_policy_artifact]))
    execution_generator_path = joinpath(ROOT,
        as_string(result_protocol[:generator]))
    pre_inputs = pre_packet[:required_input_rows]
    pre_policy_rows = [row for row in pre_inputs
        if as_string(row[:input]) == "tam_direct_agreement_policy"]
    pre_refinement_rows = [row for row in pre_inputs
        if as_string(row[:input]) ==
            "tam_direct_agreement_policy_refinement"]
    pre_execution_packet_policy_hash_matches =
        length(pre_policy_rows) == 1 &&
        as_string(only(pre_policy_rows)[:sha256]) ==
        file_sha256(parsed.policy)
    pre_execution_packet_refinement_hash_matches =
        length(pre_refinement_rows) == 1 &&
        as_string(only(pre_refinement_rows)[:sha256]) ==
        file_sha256(parsed.refinement)
    pre_execution_packet_exact_input_lineage =
        pre_execution_packet_policy_hash_matches &&
        pre_execution_packet_refinement_hash_matches
    core_source_hash_chain_valid =
        file_sha256(parsed.policy) ==
            as_string(result_protocol[:frozen_policy_artifact_sha256]) &&
        file_sha256(parsed.refinement) ==
            as_string(result_protocol[:refinement_artifact_sha256]) &&
        isfile(baseline_path) && file_sha256(baseline_path) ==
            as_string(result_protocol[:baseline_artifact_sha256]) &&
        isfile(recovery_policy_path) &&
            file_sha256(recovery_policy_path) ==
            as_string(result_protocol[:recovery_policy_artifact_sha256]) &&
        isfile(execution_generator_path) &&
            file_sha256(execution_generator_path) ==
            as_string(result_protocol[:generator_source_sha256]) &&
        as_string(result_protocol[:frozen_primary_gate_fingerprint_sha256]) ==
            as_string(refinement[:frozen_primary_gate_fingerprint_sha256]) &&
        as_string(result_protocol[:direct_threshold_table_sha256]) ==
            as_string(refinement[:direct_threshold_table_sha256]) &&
        as_string(result_protocol[:sampler_threshold_table_sha256]) ==
            as_string(refinement[:sampler_threshold_table_sha256]) &&
        file_sha256(parsed.result) ==
            as_string(raw_audit[:protocol][:result_artifact_sha256]) &&
        as_string(raw_audit[:protocol][
            :execution_generator_source_sha256]) ==
            as_string(result_protocol[:generator_source_sha256])
    execution_completed = as_bool(result[:summary][:execution_completed])
    execution_valid =
        execution_completed &&
        as_bool(result[:summary][:all_protocol_alignment_valid]) &&
        as_bool(result[:summary][:all_tam_executions_valid]) &&
        as_bool(result[:summary][:all_package_sampler_gates_passed])
    packet_integrity =
        as_bool(raw_audit[:summary][:passed]) &&
        as_bool(refinement[:summary][:frozen_primary_gate_unchanged]) &&
        as_bool(pre_packet[:summary][:packet_frozen]) &&
        !as_bool(pre_packet[:summary][:independent_review_completed]) &&
        core_source_hash_chain_valid &&
        length(tasks) == length(REVIEW_TASKS) &&
        length(fields) == length(REVIEWER_MANIFEST_FIELDS)
    primary_rows = [row for row in result[:scenario_block_summary_rows]
        if as_bool(row[:primary_gate_row])]
    return (;
        schema = PACKET_SCHEMA,
        family = :mfrm,
        scope = :tam_direct_agreement_independent_post_execution_review_packet,
        status = :packet_frozen_review_not_completed,
        decision =
            :freeze_post_execution_review_packet_keep_public_claims_blocked,
        local_only = true,
        tam_direct_local_execution_completed = execution_completed,
        scheduled_execution_recorded = true,
        external_software_validation_completed = false,
        independent_review_completed = false,
        signed_review_manifest_attached = false,
        public_claim_release_allowed = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = (;
            protocol_id =
                :mgmfrm_tam_direct_agreement_post_execution_review_packet_v1,
            review_kind =
                :independent_scientific_computational_and_reproducibility_review,
            generator =
                "scripts/generate_mgmfrm_tam_direct_agreement_post_execution_review_packet.jl",
            generator_source_sha256 = file_sha256(@__FILE__),
            generated_after_execution = true,
            distinct_from_pre_execution_packet = true,
            pre_execution_packet_remains_immutable = true,
            signed_review_manifest_required = true,
            independent_reexecution_required = true,
        ),
        required_input_rows = required_inputs,
        source_hash_chain_valid = core_source_hash_chain_valid,
        core_source_hash_chain_valid,
        pre_execution_lineage = (;
            exact_input_lineage = pre_execution_packet_exact_input_lineage,
            policy_hash_matches = pre_execution_packet_policy_hash_matches,
            refinement_hash_matches =
                pre_execution_packet_refinement_hash_matches,
            immutable_pre_execution_packet_preserved = true,
            post_execution_regeneration_used_to_erase_mismatch = false,
            status = pre_execution_packet_exact_input_lineage ?
                :exact_pre_execution_input_lineage :
                :refinement_snapshot_hash_mismatch_requires_independent_review,
        ),
        decision_layers = (;
            primary_policy = (;
                decision = as_symbol(
                    result[:outcome][:primary_policy_decision]),
                passed = as_bool(
                    result[:outcome][:primary_direct_gate_passed]),
                rule = :all_three_n100_blocks_pass_at_least_four_of_five_runs,
            ),
            scientific_interpretation = (;
                classification = as_symbol(
                    result[:outcome][:scientific_interpretation]),
                safe_local_wording = as_symbol(
                    result[:outcome][:safe_local_wording]),
                independent_review_pending = true,
            ),
            recovery_qualifiers = (;
                package_passed = as_bool(result[:outcome][
                    :package_recovery_qualifier_passed]),
                tam_passed = as_bool(result[:outcome][
                    :tam_recovery_qualifier_passed]),
                both_passed = as_bool(result[:outcome][
                    :both_estimators_recovery_qualifier_passed]),
                changes_primary_agreement_decision = false,
            ),
            computation_and_protocol = (;
                valid = execution_valid,
                all_protocol_alignment_valid = as_bool(result[:summary][
                    :all_protocol_alignment_valid]),
                all_tam_executions_valid = as_bool(result[:summary][
                    :all_tam_executions_valid]),
                all_package_sampler_gates_passed = as_bool(result[:summary][
                    :all_package_sampler_gates_passed]),
                all_attempt_raw_archive_audit_passed = as_bool(
                    raw_audit[:summary][:passed]),
            ),
        ),
        primary_scenario_block_rows = primary_rows,
        all_scenario_block_rows = result[:scenario_block_summary_rows],
        failure_rows = result[:failure_rows],
        retry_accounting = raw_audit[:failure_and_retry_accounting],
        review_task_rows = tasks,
        reviewer_manifest_field_rows = fields,
        claim_review_rows = claims,
        decision_record = (;
            selected_decision = :post_execution_packet_frozen,
            packet_integrity_passed = packet_integrity,
            independent_reviewer_assigned = false,
            independent_reexecution_completed = false,
            signed_review_manifest_attached = false,
            independent_review_completed = false,
            public_claim_release_allowed = false,
            required_followup =
                :assign_independent_reviewer_reexecute_and_attach_signed_manifest,
        ),
        claim_limits = [
            :local_tam_comparison_is_not_package_wide_external_validation,
            :agreement_and_truth_recovery_are_distinct_evidence_layers,
            :interval_inclusion_is_not_frequentist_coverage,
            :conditional_rope_is_advisory_not_an_equivalence_test,
            :five_replications_give_imprecise_pass_rates,
            :synthetic_fully_crossed_fixed_truth_scope_only,
            :no_sparse_unbalanced_real_data_or_construct_validity,
            :no_facets_or_conquest_execution,
            :no_gmfrm_mgmfrm_or_uto_2021_result_transfer,
            :pre_execution_packet_refinement_hash_mismatch_preserved_for_review,
            :independent_review_and_reexecution_pending,
            :no_public_claim_release,
        ],
        summary = (;
            passed = packet_integrity,
            packet_integrity_passed = packet_integrity,
            source_hash_chain_valid = core_source_hash_chain_valid,
            core_source_hash_chain_valid,
            pre_execution_packet_exact_input_lineage,
            pre_execution_packet_policy_hash_matches,
            pre_execution_packet_refinement_hash_matches,
            tam_direct_local_execution_completed = execution_completed,
            scheduled_execution_recorded = true,
            execution_valid,
            primary_policy_decision = as_symbol(
                result[:outcome][:primary_policy_decision]),
            scientific_interpretation = as_symbol(
                result[:outcome][:scientific_interpretation]),
            primary_direct_gate_passed = as_bool(
                result[:outcome][:primary_direct_gate_passed]),
            package_recovery_qualifier_passed = as_bool(
                result[:outcome][:package_recovery_qualifier_passed]),
            tam_recovery_qualifier_passed = as_bool(
                result[:outcome][:tam_recovery_qualifier_passed]),
            n_required_inputs = length(required_inputs),
            n_review_tasks = length(tasks),
            n_reviewer_manifest_fields = length(fields),
            n_claim_rows = length(claims),
            n_primary_scenario_block_rows = length(primary_rows),
            independent_review_completed = false,
            signed_review_manifest_attached = false,
            external_software_validation_completed = false,
            public_claim_release_allowed = false,
            remaining_public_blockers = [
                :independent_reviewer_not_assigned,
                :independent_reexecution_not_completed,
                :signed_review_manifest_not_attached,
                :per_task_review_decisions_missing,
                :per_claim_review_decisions_missing,
                :external_construct_validity_not_supplied,
                :pre_execution_packet_refinement_hash_lineage_mismatch,
            ],
            recommendation =
                :send_frozen_packet_to_independent_reviewer_without_claim_release,
            next_gate =
                :assign_independent_reviewer_reexecute_and_attach_signed_manifest,
        ),
    )
end

function main(args)
    parsed = parse_args(args)
    artifact = build_artifact(parsed)
    write_artifact(parsed.output, artifact)
    println("wrote ", relpath(parsed.output, ROOT))
    println("passed=", artifact.summary.passed,
        " primary_decision=", artifact.summary.primary_policy_decision,
        " independent_review_completed=",
        artifact.summary.independent_review_completed)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
