#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_BENCHMARK = joinpath(
    ROOT,
    "test",
    "fixtures",
    "mgmfrm_literature_anchored_synthetic_benchmark.json",
)
const DEFAULT_OUTPUT = joinpath(
    ROOT,
    "test",
    "fixtures",
    "mgmfrm_literature_anchored_independent_review_packet.json",
)
const BENCHMARK_SCHEMA =
    "bayesianmgmfrm.mgmfrm_literature_anchored_synthetic_benchmark.v1"
const TAM_POLICY_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_comparison_policy_review.v1"
const TAM_MULTIREP_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_multireplication_comparison.v1"
const TAM_DIRECT_PILOT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_estimate_pilot.v1"
const TAM_DIRECT_POLICY_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy.v1"
const TAM_DIRECT_POLICY_REFINEMENT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy_refinement.v1"

include(joinpath(@__DIR__, "local_json.jl"))

const REVIEW_TASKS = [
    (;
        task = :source_equation_traceability,
        required_evidence = :published_reference_equation_to_generator_crosswalk,
    ),
    (;
        task = :standalone_generator_independence,
        required_evidence = :no_package_response_simulation_or_probability_helper_call,
    ),
    (;
        task = :deterministic_reproducibility,
        required_evidence = :separate_truth_and_response_seeds_plus_hashes,
    ),
    (;
        task = :known_truth_checksums,
        required_evidence = :truth_observation_and_q_matrix_hashes,
    ),
    (;
        task = :paper_exact_vs_package_adapted_labels,
        required_evidence = :per_dataset_alignment_and_adaptation_rows,
    ),
    (;
        task = :ability_combination_recorded_as_formula,
        required_evidence = :loading_weighted_sum_not_classification_claim,
    ),
    (;
        task = :claim_limit_ledger,
        required_evidence = :unsupported_claims_are_blocked,
    ),
    (;
        task = :external_software_bridge_scope,
        required_evidence =
            :tam_direct_policy_refined_multirep_package_fits_and_facets_conquest_pending,
    ),
    (;
        task = :construct_validity_scope,
        required_evidence = :synthetic_data_only_no_construct_validity_claim,
    ),
    (;
        task = :public_claim_wording_scope,
        required_evidence = :public_claim_release_remains_blocked,
    ),
]

const REVIEWER_MANIFEST_FIELDS = [
    (field = :schema,
        validation_rule = :must_equal_literature_anchored_independent_review_manifest_v1),
    (field = :reviewer_name_or_id,
        validation_rule = :must_identify_independent_reviewer_or_review_body),
    (field = :reviewer_independence_statement,
        validation_rule = :must_state_independence_from_package_authorship),
    (field = :conflict_of_interest_statement,
        validation_rule = :must_record_conflicts_or_no_conflicts),
    (field = :reviewed_packet_sha256,
        validation_rule = :must_match_this_packet_sha256),
    (field = :reviewed_benchmark_sha256,
        validation_rule = :must_match_source_benchmark_sha256),
    (field = :reviewed_generator_sha256,
        validation_rule = :must_match_generator_source_sha256),
    (field = :review_date,
        validation_rule = :must_be_explicit_review_date),
    (field = :per_task_decision_table,
        validation_rule = :must_decide_each_review_task),
    (field = :per_claim_decision_table,
        validation_rule = :must_allow_block_or_request_revision_per_claim),
    (field = :required_revisions,
        validation_rule = :must_list_required_revisions_or_none),
    (field = :signature,
        validation_rule = :must_include_dated_signature_or_audit_record),
]

function usage()
    return """
    Generate the literature-anchored MGMFRM independent review packet.

    The packet freezes the synthetic benchmark, generator source, checksums,
    formula/adaptation labels, and claim limits for an independent reviewer. It
    does not assign a reviewer, attach a signed review, approve public claims,
    publish, register, push, or upload.

    Usage:
      julia --project=. scripts/generate_mgmfrm_literature_anchored_independent_review_packet.jl [--benchmark PATH] [--output PATH]
    """
end

function parse_args(args)
    benchmark = DEFAULT_BENCHMARK
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--benchmark"
            index < length(args) || error("--benchmark requires a path")
            benchmark = abspath(args[index + 1])
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
    return (; benchmark, output)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])

function file_sha256(path::AbstractString)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

rel(path::AbstractString) = relpath(path, ROOT)
load_json(path::AbstractString) = JSON3.read(read(path, String))

as_string(value) = String(value)
as_symbol(value) = Symbol(as_string(value))
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_float(value) = Float64(value)

function optional_string(object, key::Symbol, fallback::AbstractString)
    return haskey(object, key) ? as_string(object[key]) : fallback
end

function source_dataset_rows(benchmark)
    return [
        (;
            dataset_id = as_string(dataset[:dataset_id]),
            family = as_string(dataset[:family]),
            reference = as_string(dataset[:reference]),
            relationship_to_source = as_string(dataset[:relationship_to_source]),
            n_observations = as_int(dataset[:design][:n_observations]),
            n_dimensions = as_int(dataset[:design][:n_dimensions]),
            ability_combination =
                optional_string(dataset[:equation], :ability_combination, "not_applicable"),
            max_abs_probability_error =
                as_float(dataset[:generator_checks][:max_abs_probability_error]),
            observations_sha256 =
                as_string(dataset[:checksums][:observations_sha256]),
            truth_sha256 = as_string(dataset[:checksums][:truth_sha256]),
            q_matrix_sha256 =
                optional_string(dataset[:checksums], :q_matrix_sha256, "not_applicable"),
        )
        for dataset in benchmark[:datasets]
    ]
end

function source_benchmark_record(path::AbstractString)
    isfile(path) || error("benchmark fixture missing: $(rel(path))")
    benchmark = load_json(path)
    schema = as_string(benchmark[:schema])
    schema == BENCHMARK_SCHEMA ||
        error("unexpected benchmark schema: $schema")
    protocol = benchmark[:protocol]
    generator_source = joinpath(ROOT, as_string(protocol[:generator_source]))
    isfile(generator_source) ||
        error("generator source missing: $(rel(generator_source))")
    rows = source_dataset_rows(benchmark)
    tam_bridges = [bridge for bridge in benchmark[:external_validation_bridges]
        if as_string(bridge[:software]) == "tam"]
    length(tam_bridges) == 1 || error("expected one TAM validation bridge")
    tam_policy_relpath = as_string(only(tam_bridges)[:comparison_policy_review])
    tam_policy_path = joinpath(ROOT, tam_policy_relpath)
    isfile(tam_policy_path) ||
        error("TAM comparison policy missing: $tam_policy_relpath")
    tam_policy = load_json(tam_policy_path)
    tam_policy_schema = as_string(tam_policy[:schema])
    tam_multirep_relpath =
        as_string(only(tam_bridges)[:multireplication_comparison])
    tam_multirep_path = joinpath(ROOT, tam_multirep_relpath)
    isfile(tam_multirep_path) ||
        error("TAM multireplication comparison missing: $tam_multirep_relpath")
    tam_multirep = load_json(tam_multirep_path)
    tam_multirep_schema = as_string(tam_multirep[:schema])
    tam_direct_relpath = as_string(only(tam_bridges)[:direct_estimate_pilot])
    tam_direct_path = joinpath(ROOT, tam_direct_relpath)
    isfile(tam_direct_path) ||
        error("TAM direct estimate pilot missing: $tam_direct_relpath")
    tam_direct = load_json(tam_direct_path)
    tam_direct_schema = as_string(tam_direct[:schema])
    tam_direct_policy_relpath =
        as_string(only(tam_bridges)[:direct_agreement_policy])
    tam_direct_policy_path = joinpath(ROOT, tam_direct_policy_relpath)
    isfile(tam_direct_policy_path) ||
        error("TAM direct agreement policy missing: $tam_direct_policy_relpath")
    tam_direct_policy = load_json(tam_direct_policy_path)
    tam_direct_policy_schema = as_string(tam_direct_policy[:schema])
    tam_direct_refinement_relpath =
        as_string(only(tam_bridges)[:direct_agreement_policy_refinement])
    tam_direct_refinement_path = joinpath(ROOT, tam_direct_refinement_relpath)
    isfile(tam_direct_refinement_path) || error(
        "TAM direct agreement policy refinement missing: " *
        tam_direct_refinement_relpath)
    tam_direct_refinement = load_json(tam_direct_refinement_path)
    tam_direct_refinement_schema = as_string(tam_direct_refinement[:schema])
    return (;
        artifact = :mgmfrm_literature_anchored_synthetic_benchmark,
        path = rel(path),
        exists = true,
        expected_schema = BENCHMARK_SCHEMA,
        schema,
        schema_matches = true,
        sha256 = file_sha256(path),
        generator_source = rel(generator_source),
        generator_source_sha256 = file_sha256(generator_source),
        recorded_generator_source_sha256 =
            as_string(protocol[:generator_source_sha256]),
        recorded_generator_source_sha256_matches =
            as_string(protocol[:generator_source_sha256]) ==
            file_sha256(generator_source),
        package_simulate_responses_called =
            as_bool(protocol[:package_simulate_responses_called]),
        package_source_oracle_checked_before_write =
            as_bool(protocol[:package_source_oracle_checked_before_write]),
        n_reference_records = length(benchmark[:reference_records]),
        n_benchmark_specifications = length(benchmark[:benchmark_specifications]),
        n_datasets = length(benchmark[:datasets]),
        n_materialized_observations =
            as_int(benchmark[:summary][:n_materialized_observations]),
        standalone_generator_oracle_agreement =
            as_bool(benchmark[:summary][:standalone_generator_oracle_agreement]),
        public_claim_release_allowed =
            as_bool(benchmark[:summary][:public_claim_release_allowed]),
        independent_review_completed =
            as_bool(benchmark[:summary][:independent_review_completed]),
        source_dataset_rows = rows,
        tam_comparison_policy_path = tam_policy_relpath,
        tam_comparison_policy_sha256 = file_sha256(tam_policy_path),
        tam_comparison_policy_schema = tam_policy_schema,
        tam_comparison_policy_schema_matches =
            tam_policy_schema == TAM_POLICY_SCHEMA,
        tam_adapter_structure_review_completed =
            as_bool(tam_policy[:summary][:structural_adapter_checks_passed]),
        tam_multireplication_comparison_completed = true,
        tam_multireplication_comparison_path = tam_multirep_relpath,
        tam_multireplication_comparison_sha256 = file_sha256(tam_multirep_path),
        tam_multireplication_comparison_schema = tam_multirep_schema,
        tam_multireplication_comparison_schema_matches =
            tam_multirep_schema == TAM_MULTIREP_SCHEMA,
        tam_multireplication_comparison_passed =
            as_bool(tam_multirep[:summary][:passed]),
        tam_package_direct_comparison_completed =
            as_bool(tam_direct[:summary][:direct_estimate_pilot_completed]),
        tam_direct_estimate_pilot_path = tam_direct_relpath,
        tam_direct_estimate_pilot_sha256 = file_sha256(tam_direct_path),
        tam_direct_estimate_pilot_schema = tam_direct_schema,
        tam_direct_estimate_pilot_schema_matches =
            tam_direct_schema == TAM_DIRECT_PILOT_SCHEMA,
        tam_direct_estimate_pilot_completed =
            as_bool(tam_direct[:summary][:direct_estimate_pilot_completed]),
        tam_direct_estimate_sampler_diagnostics_passed =
            as_bool(tam_direct[:summary][:sampler_diagnostics_passed]),
        tam_direct_pilot_thresholds_predeclared =
            as_bool(tam_direct[:summary][
                :direct_agreement_thresholds_predeclared]),
        tam_direct_agreement_policy_path = tam_direct_policy_relpath,
        tam_direct_agreement_policy_sha256 =
            file_sha256(tam_direct_policy_path),
        tam_direct_agreement_policy_schema = tam_direct_policy_schema,
        tam_direct_agreement_policy_schema_matches =
            tam_direct_policy_schema == TAM_DIRECT_POLICY_SCHEMA,
        tam_direct_agreement_thresholds_predeclared =
            as_bool(tam_direct_policy[:summary][
                :direct_agreement_thresholds_predeclared]),
        tam_direct_agreement_multireplication_completed =
            as_bool(tam_direct_policy[:summary][
                :future_direct_multireplication_execution_completed]),
        tam_direct_agreement_policy_refinement_path =
            tam_direct_refinement_relpath,
        tam_direct_agreement_policy_refinement_sha256 =
            file_sha256(tam_direct_refinement_path),
        tam_direct_agreement_policy_refinement_schema =
            tam_direct_refinement_schema,
        tam_direct_agreement_policy_refinement_schema_matches =
            tam_direct_refinement_schema == TAM_DIRECT_POLICY_REFINEMENT_SCHEMA,
        tam_direct_frozen_primary_gate_unchanged =
            as_bool(tam_direct_refinement[:summary][
                :frozen_primary_gate_unchanged]),
        tam_direct_secondary_recovery_qualifier_frozen =
            as_bool(tam_direct_refinement[:summary][
                :secondary_recovery_qualifier_frozen]),
        tam_direct_refinement_execution_completed =
            as_bool(tam_direct_refinement[:summary][
                :direct_multireplication_execution_completed]),
    )
end

function review_task_rows()
    return [
        (;
            task = task.task,
            required_evidence = task.required_evidence,
            reviewer_decision = :pending_independent_review,
            reviewer_required = true,
            completed = false,
            blocks_public_claim_release = true,
        )
        for task in REVIEW_TASKS
    ]
end

function reviewer_manifest_field_rows()
    return [
        (;
            field = field.field,
            required = true,
            completed = false,
            validation_rule = field.validation_rule,
            placeholder_policy = :user_supplied_no_default,
        )
        for field in REVIEWER_MANIFEST_FIELDS
    ]
end

function required_input_rows(source)
    return [
        (;
            input = :frozen_benchmark_artifact,
            path = source.path,
            sha256 = source.sha256,
            present = source.exists,
            reviewer_must_verify = true,
        ),
        (;
            input = :generator_source,
            path = source.generator_source,
            sha256 = source.generator_source_sha256,
            present = true,
            reviewer_must_verify = true,
        ),
        (;
            input = :reference_records,
            path = source.path,
            sha256 = source.sha256,
            present = source.n_reference_records > 0,
            reviewer_must_verify = true,
        ),
        (;
            input = :dataset_checksums,
            path = source.path,
            sha256 = source.sha256,
            present = all(row -> row.observations_sha256 != "" &&
                    row.truth_sha256 != "", source.source_dataset_rows),
            reviewer_must_verify = true,
        ),
        (;
            input = :paper_exact_vs_package_adapted_labels,
            path = source.path,
            sha256 = source.sha256,
            present = true,
            reviewer_must_verify = true,
        ),
        (;
            input = :claim_limit_ledger,
            path = source.path,
            sha256 = source.sha256,
            present = true,
            reviewer_must_verify = true,
        ),
        (;
            input = :tam_comparison_policy_and_adapter_review,
            path = source.tam_comparison_policy_path,
            sha256 = source.tam_comparison_policy_sha256,
            present = source.tam_comparison_policy_schema_matches &&
                source.tam_adapter_structure_review_completed,
            reviewer_must_verify = true,
        ),
        (;
            input = :tam_multireplication_comparison,
            path = source.tam_multireplication_comparison_path,
            sha256 = source.tam_multireplication_comparison_sha256,
            present = source.tam_multireplication_comparison_schema_matches &&
                source.tam_multireplication_comparison_passed,
            reviewer_must_verify = true,
        ),
        (;
            input = :tam_direct_estimate_pilot,
            path = source.tam_direct_estimate_pilot_path,
            sha256 = source.tam_direct_estimate_pilot_sha256,
            present = source.tam_direct_estimate_pilot_schema_matches &&
                source.tam_direct_estimate_pilot_completed &&
                source.tam_direct_estimate_sampler_diagnostics_passed,
            reviewer_must_verify = true,
        ),
        (;
            input = :tam_direct_agreement_policy,
            path = source.tam_direct_agreement_policy_path,
            sha256 = source.tam_direct_agreement_policy_sha256,
            present = source.tam_direct_agreement_policy_schema_matches &&
                source.tam_direct_agreement_thresholds_predeclared &&
                !source.tam_direct_agreement_multireplication_completed,
            reviewer_must_verify = true,
        ),
        (;
            input = :tam_direct_agreement_policy_refinement,
            path = source.tam_direct_agreement_policy_refinement_path,
            sha256 = source.tam_direct_agreement_policy_refinement_sha256,
            present =
                source.tam_direct_agreement_policy_refinement_schema_matches &&
                source.tam_direct_frozen_primary_gate_unchanged &&
                source.tam_direct_secondary_recovery_qualifier_frozen &&
                !source.tam_direct_refinement_execution_completed,
            reviewer_must_verify = true,
        ),
    ]
end

function claim_review_rows(benchmark)
    return [
        (;
            claim = as_symbol(row[:claim]),
            artifact_support = as_bool(row[:supported]),
            artifact_blocker =
                haskey(row, :blocker) ? as_symbol(row[:blocker]) : :none,
            independent_review_required = true,
            reviewer_decision = :pending_independent_review,
            public_claim_allowed = false,
        )
        for row in benchmark[:claim_ledger]
    ]
end

function build_artifact(benchmark_path::AbstractString)
    benchmark = load_json(benchmark_path)
    source = source_benchmark_record(benchmark_path)
    tasks = review_task_rows()
    fields = reviewer_manifest_field_rows()
    claims = claim_review_rows(benchmark)
    all_source_checks_pass =
        source.schema_matches &&
        source.recorded_generator_source_sha256_matches &&
        !source.package_simulate_responses_called &&
        source.package_source_oracle_checked_before_write &&
        source.standalone_generator_oracle_agreement &&
        source.tam_comparison_policy_schema_matches &&
        source.tam_adapter_structure_review_completed &&
        source.tam_multireplication_comparison_schema_matches &&
        source.tam_multireplication_comparison_passed &&
        source.tam_direct_estimate_pilot_schema_matches &&
        source.tam_direct_estimate_pilot_completed &&
        source.tam_direct_estimate_sampler_diagnostics_passed &&
        !source.tam_direct_pilot_thresholds_predeclared &&
        source.tam_direct_agreement_policy_schema_matches &&
        source.tam_direct_agreement_thresholds_predeclared &&
        !source.tam_direct_agreement_multireplication_completed &&
        source.tam_direct_agreement_policy_refinement_schema_matches &&
        source.tam_direct_frozen_primary_gate_unchanged &&
        source.tam_direct_secondary_recovery_qualifier_frozen &&
        !source.tam_direct_refinement_execution_completed &&
        !source.public_claim_release_allowed &&
        !source.independent_review_completed
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_literature_anchored_independent_review_packet.v1",
        family = :gmfrm_mgmfrm,
        scope = :literature_anchored_independent_review_packet,
        status = :packet_frozen_review_not_completed,
        decision = :freeze_independent_review_packet_keep_public_claims_blocked,
        local_only = true,
        publication_or_registration_action = false,
        external_software_validation_completed = false,
        independent_review_completed = false,
        public_claim_release_allowed = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = (;
            protocol_id =
                :mgmfrm_literature_anchored_independent_review_packet_v1,
            review_kind = :independent_scientific_and_reproducibility_review,
            source_artifact = source.artifact,
            source_artifact_path = source.path,
            source_artifact_sha256 = source.sha256,
            generator =
                "scripts/generate_mgmfrm_literature_anchored_independent_review_packet.jl",
            generator_source_sha256 = file_sha256(@__FILE__),
            separate_from_external_software_comparison = true,
            signed_review_manifest_required = true,
        ),
        source_benchmark = source,
        required_input_rows = required_input_rows(source),
        review_task_rows = tasks,
        reviewer_manifest_field_rows = fields,
        claim_review_rows = claims,
        decision_record = (;
            selected_decision = :independent_review_packet_frozen,
            packet_frozen = true,
            signed_review_manifest_attached = false,
            public_claim_release_allowed = false,
            required_followup =
                :assign_independent_reviewer_and_attach_signed_review_manifest,
        ),
        summary = (;
            passed =
                all_source_checks_pass &&
                length(tasks) == length(REVIEW_TASKS) &&
                length(fields) == length(REVIEWER_MANIFEST_FIELDS) &&
                length(claims) == length(benchmark[:claim_ledger]),
            packet_frozen = true,
            source_benchmark_schema_matches = source.schema_matches,
            generator_source_hash_matches =
                source.recorded_generator_source_sha256_matches,
            standalone_generator_oracle_agreement =
                source.standalone_generator_oracle_agreement,
            independent_review_completed = false,
            signed_review_manifest_attached = false,
            external_software_validation_completed = false,
            public_claim_release_allowed = false,
            n_required_inputs = 11,
            n_review_task_rows = length(tasks),
            n_reviewer_manifest_fields = length(fields),
            n_claim_review_rows = length(claims),
            n_source_datasets = length(source.source_dataset_rows),
            n_materialized_observations = source.n_materialized_observations,
            remaining_public_blockers = [
                :independent_reviewer_not_assigned,
                :signed_review_manifest_not_attached,
                :per_claim_review_decisions_missing,
                :external_software_validation_not_completed,
                :parameter_recovery_refits_not_completed,
                :external_construct_validity_not_supplied,
            ],
            recommendation =
                :send_packet_to_independent_reviewer_without_claim_release,
            next_gate =
                :assign_independent_reviewer_and_attach_signed_review_manifest,
        ),
    )
end

function main(args)
    parsed = parse_args(args)
    artifact = build_artifact(parsed.benchmark)
    write_artifact(parsed.output, artifact)
    println("wrote ", rel(parsed.output))
    println(
        "passed=", artifact.summary.passed,
        " tasks=", artifact.summary.n_review_task_rows,
        " claims=", artifact.summary.n_claim_review_rows,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
