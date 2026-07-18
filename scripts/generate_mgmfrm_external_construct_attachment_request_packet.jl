#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_external_construct_attachment_request_packet.json")
const DEFAULT_PREFLIGHT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_external_construct_attachment_intake_preflight.json")

include(joinpath(@__DIR__, "local_json.jl"))

const PREFLIGHT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_external_construct_attachment_intake_preflight.v1"
const EXPECTED_PREFLIGHT_NEXT_GATE =
    "attach_valid_external_construct_dataset_manifest_and_independent_public_scope_review_manifest"

const PROTOCOL = (;
    protocol_id = "mgmfrm_external_construct_attachment_request_packet_v1",
    review_kind = :local_external_attachment_request_packet,
    publication_or_registration_action = false,
    local_only = true,
    source_gate =
        :attach_valid_external_construct_dataset_manifest_and_independent_public_scope_review_manifest,
    decision_scope =
        :make_external_attachment_requirements_actionable_without_creating_external_evidence,
    thresholds = (;
        require_preflight_passed = true,
        require_preflight_next_gate_matched = true,
        require_manifest_templates_recorded = true,
        require_attachment_checklist_recorded = true,
        require_rejection_conditions_recorded = true,
        require_no_placeholder_values_marked_valid = true,
        require_no_public_claim_release = true,
        require_no_publication_or_registration_action = true,
    ),
)

const ATTACHMENT_CHECKLIST = [
    (step = 1,
        action = :place_external_construct_dataset_manifest_at_recorded_path,
        required_input = :external_construct_dataset_manifest_json,
        completion_condition = :expected_schema_and_all_required_fields_present),
    (step = 2,
        action = :provide_source_provenance_and_use_terms,
        required_input = :source_provenance_license_or_use_terms,
        completion_condition = :origin_permissions_and_governance_reviewed),
    (step = 3,
        action = :hash_all_external_dataset_files,
        required_input = :file_records_with_sha256,
        completion_condition = :every_file_record_has_path_role_and_sha256),
    (step = 4,
        action = :provide_observation_crosswalk,
        required_input = :person_item_rater_score_and_fold_keys,
        completion_condition = :crosswalk_matches_scoring_plan_keys),
    (step = 5,
        action = :provide_construct_anchor_records,
        required_input = :external_measure_or_independent_rubric_scores,
        completion_condition = :anchor_records_cover_construct_scenarios),
    (step = 6,
        action = :predeclare_validation_split_and_scoring_plan,
        required_input = :validation_split_and_scoring_plan,
        completion_condition = :leakage_controls_and_recomputation_plan_recorded),
    (step = 7,
        action = :place_independent_public_scope_review_manifest_at_recorded_path,
        required_input = :independent_public_scope_review_manifest_json,
        completion_condition = :expected_schema_and_all_required_fields_present),
    (step = 8,
        action = :bind_independent_review_to_external_manifest_hash,
        required_input = :external_manifest_sha256_in_review_manifest,
        completion_condition = :review_hash_matches_attached_external_manifest),
    (step = 9,
        action = :record_reviewer_independence_conflicts_and_signature,
        required_input = :independence_conflict_and_signature_fields,
        completion_condition = :reviewer_signoff_is_dated_and_unconflicted),
    (step = 10,
        action = :rerun_attachment_preflight_and_public_scope_gate,
        required_input = :valid_external_and_review_manifests,
        completion_condition = :public_claim_release_decision_remains_machine_checked),
]

const REJECTION_CONDITIONS = [
    (condition = :manifest_schema_mismatch,
        rejection_reason = :expected_manifest_schema_not_present),
    (condition = :required_field_missing_or_placeholder,
        rejection_reason = :required_user_supplied_value_not_provided),
    (condition = :file_sha256_missing_or_unresolved,
        rejection_reason = :external_dataset_file_integrity_not_auditable),
    (condition = :observation_crosswalk_missing_required_keys,
        rejection_reason = :external_scores_cannot_be_joined_to_fit_or_fold_keys),
    (condition = :independent_review_unsigned_or_conflicted,
        rejection_reason = :public_scope_review_not_independent_or_not_signed),
    (condition = :claim_decision_allows_release_without_valid_external_attachment,
        rejection_reason = :claim_release_not_allowed_before_manifest_validation),
]

function usage()
    return """
    Generate the local MGMFRM external construct attachment request packet.

    This records actionable instructions, field templates, and rejection
    conditions for external construct dataset and independent public-scope
    review attachments. It does not create external manifests, infer external
    evidence, approve public claims, publish, register, push, or upload.

    Usage:
      julia --project=. scripts/generate_mgmfrm_external_construct_attachment_request_packet.jl [--output PATH]
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    preflight = DEFAULT_PREFLIGHT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg == "--preflight"
            index < length(args) || error("--preflight requires a path")
            preflight = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; output, preflight)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)

load_json(path::AbstractString) = JSON3.read(read(path, String))
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_string(value) = String(value)
as_symbol(value) = Symbol(as_string(value))

function preflight_record(path::AbstractString)
    isfile(path) || error("attachment intake preflight missing: $(rel(path))")
    artifact = load_json(path)
    schema = as_string(artifact[:schema])
    summary = artifact[:summary]
    return (;
        artifact = :mgmfrm_external_construct_attachment_intake_preflight,
        path = rel(path),
        exists = true,
        sha256 = file_sha256(path),
        expected_schema = PREFLIGHT_SCHEMA,
        schema,
        schema_matches = schema == PREFLIGHT_SCHEMA,
        summary_passed = as_bool(summary[:passed]),
        next_gate = as_string(summary[:next_gate]),
        n_manifest_field_rows = as_int(summary[:n_manifest_field_rows]),
        n_blockers = as_int(summary[:n_blockers]),
    )
end

function field_validation_rule(field::Symbol)
    field === :schema && return :must_equal_expected_manifest_schema
    field === :file_records && return :all_file_records_have_path_role_sha256
    field === :observation_crosswalk &&
        return :must_include_person_item_rater_score_and_fold_keys
    field === :construct_anchor_records &&
        return :must_cover_external_construct_anchor_scores
    field === :validation_split &&
        return :must_predeclare_external_or_heldout_membership
    field === :scoring_plan &&
        return :must_enable_reproducible_heldout_or_external_scoring
    field === :privacy_review &&
        return :must_record_deidentification_and_access_governance
    field === :reviewed_artifacts &&
        return :must_name_threshold_batch_external_construct_and_policy_artifacts
    field === :external_construct_dataset_manifest_sha256 &&
        return :must_match_attached_external_manifest_sha256
    field === :threshold_model_weight_review_sha256 &&
        return :must_match_threshold_model_weight_policy_review_sha256
    field === :claim_decision_table &&
        return :must_record_per_claim_allow_block_or_revision_decision
    field === :public_scope_decision &&
        return :must_record_allow_block_or_request_revision_summary
    field === :signature && return :must_include_dated_signature_or_audit_record
    field === :summary && return :must_include_passed_flag_and_attachment_decision
    return :must_be_nonempty_user_supplied_value
end

function manifest_template_records(preflight)
    return [
        (artifact = as_symbol(record[:artifact]),
            target_path = as_string(record[:path]),
            expected_schema = as_string(record[:expected_schema]),
            required_field_count = as_int(record[:required_field_count]),
            source_preflight_manifest_valid = as_bool(record[:manifest_valid]),
            evidence_attached = false,
            template_recorded = true,
            user_supplied_required = true,
            placeholder_values_allowed = false,
            public_claim_release_allowed = false)
        for record in preflight[:manifest_records]
    ]
end

function template_field_rows(preflight)
    return [
        (attachment = as_symbol(row[:attachment]),
            field = as_symbol(row[:field]),
            expected = as_symbol(row[:expected]),
            purpose = as_symbol(row[:purpose]),
            validation_rule = field_validation_rule(as_symbol(row[:field])),
            placeholder_policy = :user_supplied_no_default,
            source_preflight_status = as_symbol(row[:status]),
            required = true,
            completed = false,
            attachment_valid = false,
            public_claim_release_allowed = false)
        for row in preflight[:manifest_field_rows]
    ]
end

function attachment_checklist_rows()
    return [
        (row...,
            required = true,
            complete = false,
            blocks_public_claim_release = true)
        for row in ATTACHMENT_CHECKLIST
    ]
end

function rejection_rows()
    return [
        (row...,
            active = true,
            reject_attachment = true,
            public_claim_release_allowed = false)
        for row in REJECTION_CONDITIONS
    ]
end

function claim_release_request_rows(preflight)
    return [
        (claim = as_symbol(row[:claim]),
            external_construct_dataset_manifest_required =
                as_bool(row[:external_construct_dataset_manifest_required]),
            independent_public_scope_review_manifest_required =
                as_bool(row[:independent_public_scope_review_manifest_required]),
            attachment_packet_complete = false,
            valid_external_inputs_attached = false,
            public_claim_release_allowed = false,
            required_followup =
                :attach_valid_external_construct_dataset_manifest_and_independent_public_scope_review_manifest)
        for row in preflight[:claim_release_preflight_rows]
    ]
end

function build_artifact(options)
    preflight = load_json(options.preflight)
    source = preflight_record(options.preflight)
    preflight_next_gate_matched =
        source.next_gate == EXPECTED_PREFLIGHT_NEXT_GATE
    templates = manifest_template_records(preflight)
    field_rows = template_field_rows(preflight)
    checklist = attachment_checklist_rows()
    rejections = rejection_rows()
    claim_rows = claim_release_request_rows(preflight)
    no_placeholder_values_marked_valid =
        all(row -> !row.attachment_valid, field_rows) &&
        all(row -> !row.placeholder_values_allowed, templates)
    no_public_claim_release =
        all(row -> !row.public_claim_release_allowed, templates) &&
        all(row -> !row.public_claim_release_allowed, field_rows) &&
        all(row -> !row.public_claim_release_allowed, rejections) &&
        all(row -> !row.public_claim_release_allowed, claim_rows)
    manifest_templates_recorded =
        length(templates) == 2 &&
        sum(row.required_field_count for row in templates) == 25
    attachment_checklist_recorded = length(checklist) == 10
    rejection_conditions_recorded = length(rejections) == 6
    passed =
        source.schema_matches &&
        source.summary_passed &&
        preflight_next_gate_matched &&
        manifest_templates_recorded &&
        attachment_checklist_recorded &&
        rejection_conditions_recorded &&
        no_placeholder_values_marked_valid &&
        no_public_claim_release

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_external_construct_attachment_request_packet.v1",
        family = :mgmfrm,
        scope = :external_construct_attachment_request_packet,
        status = :external_construct_attachment_request_packet_recorded,
        decision =
            :record_external_attachment_request_packet_keep_public_claims_blocked,
        public_fit = true,
        experimental_public = true,
        local_only = true,
        publication_or_registration_action = false,
        external_evidence_created = false,
        external_manifest_files_written = false,
        independent_review_manifest_written = false,
        public_fit_metric_claim = false,
        public_q_revision_claim = false,
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        input_artifacts = [source],
        manifest_template_records = templates,
        template_field_rows = field_rows,
        attachment_checklist_rows = checklist,
        rejection_rows = rejections,
        claim_release_request_rows = claim_rows,
        decision_record = (;
            selected_decision = :external_attachment_request_packet_recorded,
            external_evidence_created = false,
            placeholder_values_marked_valid = false,
            public_claim_release_allowed = false,
            required_followup =
                :attach_valid_external_construct_dataset_manifest_and_independent_public_scope_review_manifest,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            preflight_passed = source.summary_passed,
            preflight_schema_matches = source.schema_matches,
            preflight_next_gate_matched,
            manifest_templates_recorded,
            attachment_checklist_recorded,
            rejection_conditions_recorded,
            no_placeholder_values_marked_valid,
            no_public_claim_release,
            external_evidence_created = false,
            external_manifest_files_written = false,
            independent_review_manifest_written = false,
            n_input_artifacts = 1,
            n_manifest_template_records = length(templates),
            n_template_field_rows = length(field_rows),
            n_external_manifest_template_fields =
                count(row -> row.attachment === :external_construct_dataset_manifest,
                    field_rows),
            n_independent_review_template_fields =
                count(row -> row.attachment === :independent_public_scope_review_manifest,
                    field_rows),
            n_attachment_checklist_rows = length(checklist),
            n_rejection_rows = length(rejections),
            n_claim_release_request_rows = length(claim_rows),
            n_blockers = length(rejections),
            remaining_public_blockers = [row.condition for row in rejections],
            recommendation =
                :send_attachment_request_packet_to_data_owner_and_independent_reviewer,
            next_gate =
                :attach_valid_external_construct_dataset_manifest_and_independent_public_scope_review_manifest,
        ),
    )
end

function main(args)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output, artifact)
    println("wrote ", rel(options.output))
    println("passed=", artifact.summary.passed,
        " template_fields=", artifact.summary.n_template_field_rows,
        " checklist=", artifact.summary.n_attachment_checklist_rows,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

main(ARGS)
