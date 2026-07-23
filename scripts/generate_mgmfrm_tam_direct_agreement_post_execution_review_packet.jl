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
const DEFAULT_EXECUTION_SNAPSHOT = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_tam_direct_agreement_policy_refinement_execution_snapshot.json")
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
const EXPECTED_EXECUTION_SNAPSHOT_SHA256 =
    "03fe1a903d4fd218b5ab3e5ad51f5133ec1d8f274fafcea0bf8ac330876d8f4e"
const EXPECTED_PRE_EXECUTION_PACKET_SHA256 =
    "696a9ad921d2bc68c42a6e095ef130d356f1cc893cd99405b58c1f68a2619e02"
const EXPECTED_AGGREGATION_GENERATOR =
    "scripts/generate_mgmfrm_tam_direct_agreement_multireplication_aggregate.jl"
const EXPECTED_AGGREGATION_GENERATOR_SHA256 =
    "787b11b0ebfc1a6a66104f97178b3a04383390dbc3864bdb7e3591f0d0a10324"
const EXPECTED_SELECTED_JOBS = 10
const EXPECTED_RETAINED_ATTEMPTS = 11

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
      --execution-snapshot PATH
      --pre-execution-packet PATH
      --output PATH
    """
end

function parse_args(args)
    result = DEFAULT_RESULT
    raw_audit = DEFAULT_RAW_AUDIT
    policy = DEFAULT_POLICY
    refinement = DEFAULT_REFINEMENT
    execution_snapshot = DEFAULT_EXECUTION_SNAPSHOT
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
        elseif arg == "--execution-snapshot"
            index < length(args) ||
                error("--execution-snapshot requires a path")
            execution_snapshot = abspath(args[index + 1])
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
        result, raw_audit, policy, refinement, execution_snapshot,
        pre_execution_packet, output)
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

function path_from_root(path::AbstractString)
    return isabspath(path) ? normpath(path) : normpath(joinpath(ROOT, path))
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

field_is_true(object, key::Symbol) =
    haskey(object, key) && as_bool(object[key])

function execution_snapshot_seed_rows(snapshot)
    rows = snapshot[:data_and_input_contract][:seed_registry_rows]
    expected_pairs = Set((n_persons, replication)
        for n_persons in (40, 100) for replication in 1:5)
    pairs = [(as_int(row[:n_persons]), as_int(row[:replication]))
        for row in rows]
    exact = length(rows) == EXPECTED_SELECTED_JOBS &&
        length(unique(pairs)) == length(pairs) &&
        Set(pairs) == expected_pairs
    return (; rows, exact)
end

function execution_snapshot_seed_row(seed_contract, n_persons::Int,
        replication::Int)
    rows = [row for row in seed_contract.rows
        if as_int(row[:n_persons]) == n_persons &&
            as_int(row[:replication]) == replication]
    return length(rows) == 1 ? only(rows) : nothing
end

function selected_environment_row(job, filename::String,
        expected_sha256::AbstractString)
    rows = [row for row in job[:raw_file_manifest_rows]
        if basename(as_string(row[:path])) == filename]
    exactly_one = length(rows) == 1
    row = exactly_one ? only(rows) : nothing
    path = exactly_one ? path_from_root(as_string(row[:path])) : nothing
    present = path !== nothing && isfile(path)
    actual_bytes = present ? filesize(path) : nothing
    actual_sha256 = present ? file_sha256(path) : nothing
    recorded_bytes_match = present &&
        actual_bytes == as_int(row[:bytes])
    recorded_sha256_match = present &&
        actual_sha256 == as_string(row[:sha256])
    expected_sha256_match = present && actual_sha256 == expected_sha256
    return (;
        filename,
        exactly_one,
        path = path === nothing ? nothing : relpath(path, ROOT),
        present,
        actual_bytes,
        actual_sha256,
        expected_sha256,
        recorded_bytes_match,
        recorded_sha256_match,
        expected_sha256_match,
        exact = exactly_one && present && recorded_bytes_match &&
            recorded_sha256_match && expected_sha256_match,
    )
end

function aggregate_selected_lineage(result, snapshot,
        snapshot_sha256::AbstractString)
    seed_contract = execution_snapshot_seed_rows(snapshot)
    sources = snapshot[:source_artifacts]
    environment = snapshot[:environment_contract]
    expected_project_sha256 =
        as_string(environment[:project_toml_sha256])
    expected_manifest_sha256 =
        as_string(environment[:manifest_toml_sha256])
    expected_source_hashes = (;
        baseline_sha256 = as_string(sources[:baseline_sha256]),
        frozen_policy_sha256 = as_string(sources[:frozen_policy_sha256]),
        recovery_policy_sha256 =
            as_string(sources[:recovery_policy_sha256]),
    )
    expected_truth_sha256 = as_string(
        snapshot[:data_and_input_contract][:fixed_truth_sha256])
    result_protocol = result[:protocol]
    expected_generator = as_string(result_protocol[:generator])
    expected_generator_sha256 =
        as_string(result_protocol[:generator_source_sha256])
    rows = NamedTuple[]
    for job in result[:replication_rows]
        n_persons = as_int(job[:n_persons])
        replication = as_int(job[:replication])
        expected_job_id =
            "n$(lpad(n_persons, 3, '0'))_rep$(lpad(replication, 2, '0'))"
        protocol = job[:protocol]
        seed = execution_snapshot_seed_row(
            seed_contract, n_persons, replication)
        seed_registry_row_present = seed !== nothing
        generator_lineage_exact =
            as_string(protocol[:generator]) == expected_generator &&
            as_string(protocol[:generator_source_sha256]) ==
                expected_generator_sha256
        refinement_snapshot_lineage_exact =
            as_string(protocol[:refinement_sha256]) == snapshot_sha256
        source_input_lineage_exact =
            as_string(protocol[:baseline_sha256]) ==
                expected_source_hashes.baseline_sha256 &&
            as_string(protocol[:frozen_policy_sha256]) ==
                expected_source_hashes.frozen_policy_sha256 &&
            as_string(protocol[:recovery_policy_sha256]) ==
                expected_source_hashes.recovery_policy_sha256
        truth_sha256_matches =
            as_string(protocol[:truth_sha256]) == expected_truth_sha256
        seed_registry_lineage_exact = seed_contract.exact &&
            seed_registry_row_present &&
            as_int(protocol[:ability_seed]) == as_int(seed[:ability_seed]) &&
            as_int(protocol[:response_seed]) ==
                as_int(seed[:response_seed]) &&
            as_int(protocol[:package_fit_seed]) ==
                as_int(seed[:package_fit_seed])
        project = selected_environment_row(
            job, "Project.toml", expected_project_sha256)
        manifest = selected_environment_row(
            job, "Manifest.toml", expected_manifest_sha256)
        environment_input_lineage_exact = project.exact && manifest.exact
        job_identity_exact = as_string(job[:job_id]) == expected_job_id
        execution_input_lineage_exact = job_identity_exact &&
            as_bool(job[:execution_completed]) &&
            !as_bool(job[:engine_failure]) && generator_lineage_exact &&
            refinement_snapshot_lineage_exact &&
            source_input_lineage_exact && truth_sha256_matches &&
            seed_registry_lineage_exact &&
            environment_input_lineage_exact
        push!(rows, (;
            job_id = Symbol(as_string(job[:job_id])),
            n_persons,
            replication,
            attempt = as_int(job[:attempt]),
            job_identity_exact,
            generator_lineage_exact,
            refinement_snapshot_lineage_exact,
            source_input_lineage_exact,
            truth_sha256_matches,
            seed_registry_row_present,
            seed_registry_lineage_exact,
            project_toml = project,
            manifest_toml = manifest,
            environment_input_lineage_exact,
            execution_input_lineage_exact,
        ))
    end
    expected_pairs = Set((n_persons, replication)
        for n_persons in (40, 100) for replication in 1:5)
    observed_pairs = Set((row.n_persons, row.replication) for row in rows)
    exact = length(rows) == EXPECTED_SELECTED_JOBS &&
        observed_pairs == expected_pairs &&
        all(row -> row.execution_input_lineage_exact, rows)
    return (;
        rows,
        seed_registry_exact = seed_contract.exact,
        all_truth_lineage_exact = all(
            row -> row.truth_sha256_matches, rows),
        exact,
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
    execution_snapshot = checked_artifact(
        parsed.execution_snapshot, REFINEMENT_SCHEMA)
    execution_snapshot_sha256 = file_sha256(parsed.execution_snapshot)
    execution_snapshot_sha256_matches_pinned =
        execution_snapshot_sha256 == EXPECTED_EXECUTION_SNAPSHOT_SHA256
    pre_packet = checked_artifact(
        parsed.pre_execution_packet, PRE_EXECUTION_PACKET_SCHEMA)
    pre_execution_packet_sha256 = file_sha256(parsed.pre_execution_packet)
    pre_execution_packet_sha256_matches_pinned =
        pre_execution_packet_sha256 == EXPECTED_PRE_EXECUTION_PACKET_SHA256
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
        source_row(:policy_refinement_execution_snapshot,
            parsed.execution_snapshot, REFINEMENT_SCHEMA;
            role = :immutable_byte_exact_execution_input_snapshot),
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
        execution_snapshot_sha256
    pre_execution_packet_exact_input_lineage =
        pre_execution_packet_policy_hash_matches &&
        pre_execution_packet_refinement_hash_matches
    pre_execution_refinement_mismatch_preserved =
        pre_execution_packet_sha256_matches_pinned &&
        pre_execution_packet_policy_hash_matches &&
        !pre_execution_packet_refinement_hash_matches &&
        !pre_execution_packet_exact_input_lineage
    aggregate_selected = aggregate_selected_lineage(
        result, execution_snapshot, execution_snapshot_sha256)
    aggregation_provenance_present =
        haskey(result, :aggregation_provenance)
    aggregation_provenance = aggregation_provenance_present ?
        result[:aggregation_provenance] : nothing
    aggregation_generator_path = aggregation_provenance_present ?
        path_from_root(as_string(aggregation_provenance[:generator])) :
        nothing
    expected_aggregation_generator_path =
        path_from_root(EXPECTED_AGGREGATION_GENERATOR)
    aggregation_generator_path_matches =
        aggregation_generator_path !== nothing &&
        aggregation_generator_path == expected_aggregation_generator_path &&
        as_string(aggregation_provenance[:generator]) ==
            EXPECTED_AGGREGATION_GENERATOR
    aggregation_generator_hash_matches =
        aggregation_generator_path_matches &&
        isfile(aggregation_generator_path) &&
        file_sha256(aggregation_generator_path) ==
            as_string(aggregation_provenance[:generator_source_sha256])
    aggregation_generator_hash_matches_pinned =
        aggregation_generator_hash_matches &&
        file_sha256(aggregation_generator_path) ==
            EXPECTED_AGGREGATION_GENERATOR_SHA256
    wrapped_execution_generator_lineage_exact =
        aggregation_provenance_present &&
        as_string(aggregation_provenance[:wrapped_execution_generator]) ==
            as_string(result_protocol[:generator]) &&
        as_string(aggregation_provenance[
            :wrapped_execution_generator_source_sha256]) ==
            as_string(result_protocol[:generator_source_sha256])
    aggregate_wrapper_lineage_exact = aggregation_provenance_present &&
        as_string(aggregation_provenance[:mode]) ==
            "aggregate_only_from_selected_attempts" &&
        !as_bool(aggregation_provenance[:mcmc_executed]) &&
        as_bool(aggregation_provenance[:fail_closed]) &&
        as_bool(aggregation_provenance[
            :protocol_generator_fields_preserved]) &&
        wrapped_execution_generator_lineage_exact &&
        as_string(aggregation_provenance[
            :refinement_execution_snapshot]) ==
            relpath(parsed.execution_snapshot, ROOT) &&
        as_int(aggregation_provenance[
            :refinement_execution_snapshot_bytes]) ==
            filesize(parsed.execution_snapshot) &&
        as_string(aggregation_provenance[
            :refinement_execution_snapshot_sha256]) ==
            execution_snapshot_sha256 &&
        as_int(aggregation_provenance[:n_selected_jobs_expected]) ==
            EXPECTED_SELECTED_JOBS &&
        as_int(aggregation_provenance[:n_selected_jobs_validated]) ==
            EXPECTED_SELECTED_JOBS &&
        as_bool(aggregation_provenance[:all_selected_job_lineage_valid]) &&
        length(aggregation_provenance[:selected_job_lineage_rows]) ==
            EXPECTED_SELECTED_JOBS &&
        all(row -> as_bool(row[:passed]),
            aggregation_provenance[:selected_job_lineage_rows]) &&
        Set(as_string(row[:job_id]) for row in
            aggregation_provenance[:selected_job_lineage_rows]) ==
            Set(String(row.job_id) for row in aggregate_selected.rows) &&
        as_string(aggregation_provenance[
            :expected_project_toml_sha256]) ==
            as_string(execution_snapshot[:environment_contract][
                :project_toml_sha256]) &&
        as_string(aggregation_provenance[
            :expected_manifest_toml_sha256]) ==
            as_string(execution_snapshot[:environment_contract][
                :manifest_toml_sha256]) &&
        aggregation_generator_path_matches &&
        aggregation_generator_hash_matches_pinned
    aggregate_selected_execution_input_lineage_exact =
        execution_snapshot_sha256_matches_pinned &&
        aggregate_selected.exact && aggregate_wrapper_lineage_exact
    raw_attempt_rows = raw_audit[:attempt_rows]
    raw_attempt_lineage_rows_exact =
        length(raw_attempt_rows) == EXPECTED_RETAINED_ATTEMPTS &&
        all(row -> field_is_true(row, :execution_input_lineage_exact),
            raw_attempt_rows)
    raw_audit_snapshot_lineage_exact =
        haskey(raw_audit[:protocol],
            :execution_refinement_snapshot_sha256) &&
        as_string(raw_audit[:protocol][
            :execution_refinement_snapshot_sha256]) ==
            execution_snapshot_sha256 &&
        field_is_true(raw_audit[:protocol],
            :execution_refinement_snapshot_sha256_matches_pinned)
    raw_summary = raw_audit[:summary]
    raw_summary_lineage_exact =
        as_int(raw_summary[:n_attempts]) == EXPECTED_RETAINED_ATTEMPTS &&
        haskey(raw_summary, :n_expected_retained_attempts) &&
        as_int(raw_summary[:n_expected_retained_attempts]) ==
            EXPECTED_RETAINED_ATTEMPTS &&
        field_is_true(raw_summary,
            :all_retained_refinement_lineage_exact) &&
        field_is_true(raw_summary,
            :all_retained_job_design_identity_exact) &&
        field_is_true(raw_summary,
            :all_retained_truth_lineage_exact) &&
        field_is_true(raw_summary,
            :all_retained_source_input_lineage_exact) &&
        field_is_true(raw_summary,
            :all_retained_seed_registry_lineage_exact) &&
        field_is_true(raw_summary,
            :all_retained_project_toml_lineage_exact) &&
        field_is_true(raw_summary,
            :all_retained_manifest_toml_lineage_exact) &&
        field_is_true(raw_summary,
            :all_retained_environment_input_lineage_exact) &&
        field_is_true(raw_summary,
            :all_retained_generator_lineage_accepted) &&
        field_is_true(raw_summary,
            :retained_failed_generator_exception_exact) &&
        haskey(raw_summary, :n_retained_failed_generator_exceptions) &&
        as_int(raw_summary[:n_retained_failed_generator_exceptions]) == 1 &&
        field_is_true(raw_summary,
            :all_retained_execution_input_lineage_exact) &&
        as_int(raw_summary[:n_execution_input_lineage_failures]) == 0
    raw_job_execution_input_lineage_exact =
        execution_snapshot_sha256_matches_pinned &&
        raw_audit_snapshot_lineage_exact &&
        raw_attempt_lineage_rows_exact && raw_summary_lineage_exact
    core_source_hash_chain_valid =
        file_sha256(parsed.policy) ==
            as_string(result_protocol[:frozen_policy_artifact_sha256]) &&
        execution_snapshot_sha256 ==
            as_string(result_protocol[:refinement_artifact_sha256]) &&
        path_from_root(as_string(result_protocol[:refinement_artifact])) ==
            normpath(parsed.execution_snapshot) &&
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
        execution_snapshot_sha256_matches_pinned &&
        aggregate_selected_execution_input_lineage_exact &&
        raw_job_execution_input_lineage_exact &&
        pre_execution_refinement_mismatch_preserved &&
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
        execution_input_lineage = (;
            execution_refinement_snapshot =
                relpath(parsed.execution_snapshot, ROOT),
            execution_refinement_snapshot_sha256 =
                execution_snapshot_sha256,
            expected_execution_refinement_snapshot_sha256 =
                EXPECTED_EXECUTION_SNAPSHOT_SHA256,
            execution_refinement_snapshot_sha256_matches_pinned =
                execution_snapshot_sha256_matches_pinned,
            aggregation_provenance_present,
            expected_aggregation_generator =
                EXPECTED_AGGREGATION_GENERATOR,
            expected_aggregation_generator_sha256 =
                EXPECTED_AGGREGATION_GENERATOR_SHA256,
            aggregation_generator_path_matches,
            aggregation_generator_hash_matches,
            aggregation_generator_hash_matches_pinned,
            wrapped_execution_generator_lineage_exact,
            aggregate_wrapper_lineage_exact,
            n_aggregate_selected_job_lineage_rows =
                length(aggregate_selected.rows),
            aggregate_selected_seed_registry_exact =
                aggregate_selected.seed_registry_exact,
            aggregate_selected_truth_lineage_exact =
                aggregate_selected.all_truth_lineage_exact,
            aggregate_selected_job_lineage_rows =
                aggregate_selected.rows,
            aggregate_selected_execution_input_lineage_exact,
            n_raw_retained_attempt_lineage_rows =
                length(raw_attempt_rows),
            raw_audit_snapshot_lineage_exact,
            raw_attempt_lineage_rows_exact,
            raw_summary_lineage_exact,
            raw_job_execution_input_lineage_exact,
            aggregate_selected_and_raw_retained_lineage_independently_exact =
                aggregate_selected_execution_input_lineage_exact &&
                raw_job_execution_input_lineage_exact,
        ),
        source_hash_chain_valid = core_source_hash_chain_valid,
        core_source_hash_chain_valid,
        pre_execution_lineage = (;
            pre_execution_packet_sha256,
            expected_pre_execution_packet_sha256 =
                EXPECTED_PRE_EXECUTION_PACKET_SHA256,
            pre_execution_packet_sha256_matches_pinned,
            exact_input_lineage = pre_execution_packet_exact_input_lineage,
            policy_hash_matches = pre_execution_packet_policy_hash_matches,
            refinement_hash_matches =
                pre_execution_packet_refinement_hash_matches,
            refinement_mismatch_preserved =
                pre_execution_refinement_mismatch_preserved,
            immutable_pre_execution_packet_preserved =
                pre_execution_refinement_mismatch_preserved,
            post_execution_regeneration_used_to_erase_mismatch =
                pre_execution_packet_exact_input_lineage,
            status = pre_execution_refinement_mismatch_preserved ?
                :refinement_snapshot_hash_mismatch_requires_independent_review :
                pre_execution_packet_exact_input_lineage ?
                :unexpected_exact_pre_execution_input_lineage :
                :pre_execution_packet_lineage_invalid,
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
                aggregate_selected_execution_input_lineage_exact,
                raw_job_execution_input_lineage_exact,
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
            aggregate_selected_execution_input_lineage_exact,
            raw_job_execution_input_lineage_exact,
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
            :execution_snapshot_lineage_is_distinct_from_pre_execution_packet_lineage,
            :independent_review_and_reexecution_pending,
            :no_public_claim_release,
        ],
        summary = (;
            passed = packet_integrity,
            packet_integrity_passed = packet_integrity,
            source_hash_chain_valid = core_source_hash_chain_valid,
            core_source_hash_chain_valid,
            execution_refinement_snapshot_sha256_matches_pinned =
                execution_snapshot_sha256_matches_pinned,
            aggregate_wrapper_lineage_exact,
            aggregation_generator_hash_matches_pinned,
            wrapped_execution_generator_lineage_exact,
            aggregate_selected_execution_input_lineage_exact,
            raw_job_execution_input_lineage_exact,
            aggregate_selected_and_raw_retained_lineage_independently_exact =
                aggregate_selected_execution_input_lineage_exact &&
                raw_job_execution_input_lineage_exact,
            pre_execution_packet_exact_input_lineage,
            pre_execution_refinement_mismatch_preserved,
            pre_execution_packet_sha256_matches_pinned,
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
