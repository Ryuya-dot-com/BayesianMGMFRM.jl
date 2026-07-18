#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_external_construct_attachment_intake_preflight.json")
const DEFAULT_GATE_REVIEW =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_external_construct_dataset_and_independent_public_scope_review.json")
const DEFAULT_EXTERNAL_CONSTRUCT_DATASET_MANIFEST =
    joinpath(ROOT, "test", "fixtures", "external",
        "mgmfrm_external_construct_dataset_manifest.json")
const DEFAULT_INDEPENDENT_PUBLIC_SCOPE_REVIEW_MANIFEST =
    joinpath(ROOT, "test", "fixtures", "external",
        "mgmfrm_independent_public_scope_review_manifest.json")

include(joinpath(@__DIR__, "local_json.jl"))

const GATE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_external_construct_dataset_and_independent_public_scope_review.v1"
const EXTERNAL_MANIFEST_SCHEMA =
    "bayesianmgmfrm.external_construct_dataset_manifest.v1"
const INDEPENDENT_REVIEW_SCHEMA =
    "bayesianmgmfrm.independent_public_scope_review_manifest.v1"

const EXTERNAL_MANIFEST_FIELDS = [
    (field = :schema, expected = :external_construct_dataset_manifest_schema,
        purpose = :machine_readable_manifest_type),
    (field = :dataset_id, expected = :stable_external_dataset_identifier,
        purpose = :dataset_identity),
    (field = :source_dataset_name, expected = :human_readable_source_name,
        purpose = :dataset_identity),
    (field = :source_provenance, expected = :collection_context_and_origin,
        purpose = :source_documentation),
    (field = :license_or_use_terms, expected = :explicit_use_permissions,
        purpose = :source_documentation),
    (field = :file_records, expected = :paths_sha256_and_roles,
        purpose = :artifact_integrity),
    (field = :observation_crosswalk,
        expected = :person_item_rater_score_and_fold_keys,
        purpose = :score_table_linkage),
    (field = :construct_anchor_records,
        expected = :external_measure_or_independent_rubric_scores,
        purpose = :construct_validity_anchor),
    (field = :scenario_coverage,
        expected = :missing_loading_and_weak_dimension_scenarios,
        purpose = :gate_alignment),
    (field = :validation_split,
        expected = :predeclared_external_or_heldout_membership,
        purpose = :leakage_control),
    (field = :scoring_plan,
        expected = :reproducible_heldout_or_external_log_score_plan,
        purpose = :recomputation_protocol),
    (field = :privacy_review, expected = :deidentification_and_access_notes,
        purpose = :data_governance),
    (field = :summary, expected = :passed_flag_and_attachment_decision,
        purpose = :machine_readable_gate_summary),
]

const INDEPENDENT_REVIEW_FIELDS = [
    (field = :schema, expected = :independent_public_scope_review_schema,
        purpose = :machine_readable_manifest_type),
    (field = :reviewer_identity, expected = :reviewer_or_review_body_id,
        purpose = :reviewer_accountability),
    (field = :review_date, expected = :dated_review_record,
        purpose = :audit_timing),
    (field = :independence_statement,
        expected = :not_involved_in_model_development_or_batch_generation,
        purpose = :reviewer_independence),
    (field = :conflict_of_interest_statement,
        expected = :explicit_disclosure_and_resolution,
        purpose = :reviewer_independence),
    (field = :reviewed_artifacts,
        expected = :threshold_batch_external_construct_and_policy_artifacts,
        purpose = :review_scope),
    (field = :external_construct_dataset_manifest_sha256,
        expected = :sha256_of_reviewed_external_dataset_manifest,
        purpose = :artifact_binding),
    (field = :threshold_model_weight_review_sha256,
        expected = :sha256_of_reviewed_threshold_model_weight_gate,
        purpose = :artifact_binding),
    (field = :claim_decision_table,
        expected = :per_claim_allow_block_or_request_revision,
        purpose = :claim_release_control),
    (field = :public_scope_decision,
        expected = :allow_block_or_request_revision_summary,
        purpose = :claim_release_control),
    (field = :signature, expected = :dated_signature_or_equivalent_audit_record,
        purpose = :review_signoff),
    (field = :summary, expected = :passed_flag_and_review_completion,
        purpose = :machine_readable_gate_summary),
]

const CLAIMS = [
    (claim = :publication_grade_fit_metric_claim,
        external_manifest_required = false),
    (claim = :model_weight_claim, external_manifest_required = true),
    (claim = :q_revision_claim, external_manifest_required = true),
    (claim = :construct_validity_claim, external_manifest_required = true),
    (claim = :sparse_mgmfrm_superiority_claim,
        external_manifest_required = true),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_external_construct_attachment_intake_preflight_v1",
    review_kind = :local_attachment_intake_preflight,
    publication_or_registration_action = false,
    local_only = true,
    source_gate =
        :provide_external_construct_dataset_manifest_and_independent_public_scope_review,
    decision_scope =
        :preflight_before_external_construct_or_independent_review_attachment_is_accepted,
    thresholds = (;
        require_external_construct_gate_review_passed = true,
        require_external_construct_gate_next_gate_matched = true,
        require_external_manifest_field_spec_recorded = true,
        require_independent_review_field_spec_recorded = true,
        require_missing_manifest_paths_recorded = true,
        require_no_public_claim_release_without_valid_manifests = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM external construct attachment intake preflight.

    This records the required fields and local validation checks for the
    external construct dataset manifest and independent public-scope review
    manifest. It does not create, infer, publish, or approve external evidence.

    Usage:
      julia --project=. scripts/generate_mgmfrm_external_construct_attachment_intake_preflight.jl [--output PATH]
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    gate_review = DEFAULT_GATE_REVIEW
    external_manifest = DEFAULT_EXTERNAL_CONSTRUCT_DATASET_MANIFEST
    independent_review = DEFAULT_INDEPENDENT_PUBLIC_SCOPE_REVIEW_MANIFEST
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg == "--gate-review"
            index < length(args) || error("--gate-review requires a path")
            gate_review = abspath(args[index + 1])
            index += 2
        elseif arg == "--external-construct-dataset-manifest"
            index < length(args) ||
                error("--external-construct-dataset-manifest requires a path")
            external_manifest = abspath(args[index + 1])
            index += 2
        elseif arg == "--independent-public-scope-review-manifest"
            index < length(args) ||
                error("--independent-public-scope-review-manifest requires a path")
            independent_review = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; output, gate_review, external_manifest, independent_review)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)

as_bool(value) = Bool(value)
as_string(value) = String(value)

function load_json(path::AbstractString)
    return JSON3.read(read(path, String))
end

function json_get(object, key::Symbol, default = missing)
    haskey(object, key) || return default
    value = object[key]
    value === nothing && return default
    ismissing(value) && return default
    return value
end

function summary_passed(parsed)
    summary = json_get(parsed, :summary, missing)
    summary === missing && return false
    value = json_get(summary, :passed, missing)
    value === missing && return false
    return as_bool(value)
end

function present_value(value)
    value === nothing && return false
    ismissing(value) && return false
    value isa AbstractString && return !isempty(strip(value))
    value isa JSON3.Array && return !isempty(value)
    value isa JSON3.Object && return !isempty(collect(pairs(value)))
    return true
end

function manifest_record(artifact::Symbol, path::AbstractString,
        expected_schema::AbstractString, required_fields)
    exists = isfile(path)
    if !exists
        return (;
            artifact,
            path = rel(path),
            exists = false,
            sha256 = missing,
            expected_schema,
            schema = missing,
            schema_matches = false,
            required_field_count = length(required_fields),
            present_required_field_count = 0,
            all_required_fields_present = false,
            summary_passed = false,
            manifest_valid = false,
        )
    end
    parsed = load_json(path)
    schema = as_string(json_get(parsed, :schema, ""))
    present_count =
        count(row -> present_value(json_get(parsed, row.field, missing)),
            required_fields)
    all_required_fields_present = present_count == length(required_fields)
    schema_matches = schema == expected_schema
    passed = summary_passed(parsed)
    return (;
        artifact,
        path = rel(path),
        exists,
        sha256 = file_sha256(path),
        expected_schema,
        schema,
        schema_matches,
        required_field_count = length(required_fields),
        present_required_field_count = present_count,
        all_required_fields_present,
        summary_passed = passed,
        manifest_valid = schema_matches && all_required_fields_present && passed,
    )
end

function gate_record(path::AbstractString)
    exists = isfile(path)
    exists || error("external construct gate review is missing: $(rel(path))")
    parsed = load_json(path)
    schema = as_string(parsed[:schema])
    summary = parsed[:summary]
    return (;
        artifact =
            :mgmfrm_external_construct_dataset_and_independent_public_scope_review,
        path = rel(path),
        exists,
        sha256 = file_sha256(path),
        expected_schema = GATE_SCHEMA,
        schema,
        schema_matches = schema == GATE_SCHEMA,
        summary_passed = as_bool(summary[:passed]),
        next_gate = as_string(summary[:next_gate]),
        n_blockers = Int(summary[:n_blockers]),
    )
end

function field_present(record, field::Symbol)
    record.exists || return false
    parsed = load_json(joinpath(ROOT, record.path))
    return present_value(json_get(parsed, field, missing))
end

function manifest_field_rows(record, required_fields)
    status_for(present) =
        !record.exists ? :pending_attachment_manifest_missing :
        present ? :present : :missing_required_field
    return [
        begin
            present = field_present(record, row.field)
            (attachment = record.artifact,
                field = row.field,
                expected = row.expected,
                purpose = row.purpose,
                required = true,
                present,
                status = status_for(present))
        end
        for row in required_fields
    ]
end

function preflight_check_rows(gate, external_record, independent_record)
    gate_next_matched =
        gate.next_gate ==
        "provide_external_construct_dataset_manifest_and_independent_public_scope_review"
    return [
        (check = :external_construct_gate_review_passed,
            satisfied = gate.summary_passed,
            status = gate.summary_passed ? :passed : :failed,
            public_claim_release_allowed = false),
        (check = :external_construct_gate_next_gate_matched,
            satisfied = gate_next_matched,
            status = gate_next_matched ? :passed : :failed,
            public_claim_release_allowed = false),
        (check = :external_construct_dataset_manifest_path_recorded,
            satisfied = !isempty(external_record.path),
            status = :passed,
            public_claim_release_allowed = false),
        (check = :independent_public_scope_review_manifest_path_recorded,
            satisfied = !isempty(independent_record.path),
            status = :passed,
            public_claim_release_allowed = false),
        (check = :external_construct_dataset_manifest_valid,
            satisfied = external_record.manifest_valid,
            status = external_record.manifest_valid ? :passed :
                     :blocked_missing_or_invalid_manifest,
            public_claim_release_allowed = false),
        (check = :independent_public_scope_review_manifest_valid,
            satisfied = independent_record.manifest_valid,
            status = independent_record.manifest_valid ? :passed :
                     :blocked_missing_or_invalid_manifest,
            public_claim_release_allowed = false),
        (check = :external_construct_validation_not_claimed_without_manifest,
            satisfied = !external_record.manifest_valid,
            status = :passed_blocker_retained,
            public_claim_release_allowed = false),
        (check = :independent_public_claim_release_not_signed_without_review,
            satisfied = !independent_record.manifest_valid,
            status = :passed_blocker_retained,
            public_claim_release_allowed = false),
    ]
end

function claim_release_preflight_rows(external_record, independent_record)
    return [
        (claim = row.claim,
            external_construct_dataset_manifest_required =
                row.external_manifest_required,
            independent_public_scope_review_manifest_required = true,
            external_construct_dataset_manifest_valid =
                external_record.manifest_valid,
            independent_public_scope_review_manifest_valid =
                independent_record.manifest_valid,
            public_claim_release_allowed = false,
            status =
                :blocked_until_valid_external_inputs_and_independent_release_decision)
        for row in CLAIMS
    ]
end

function blocker_rows(external_record, independent_record)
    return [
        (blocker = :external_construct_dataset_manifest_missing_or_invalid,
            resolved = external_record.manifest_valid,
            blocks = :construct_q_revision_model_weight_and_sparse_claims),
        (blocker = :external_construct_dataset_file_integrity_unverified,
            resolved = external_record.manifest_valid,
            blocks = :external_construct_validation),
        (blocker = :independent_public_scope_review_manifest_missing_or_invalid,
            resolved = independent_record.manifest_valid,
            blocks = :all_public_mgmfrm_claims),
        (blocker = :independent_public_scope_review_signature_missing,
            resolved = independent_record.manifest_valid,
            blocks = :all_public_mgmfrm_claims),
        (blocker = :public_claim_release_decision_not_signed,
            resolved = independent_record.manifest_valid,
            blocks = :fit_metric_model_weight_q_revision_construct_and_sparse_claims),
    ]
end

function build_artifact(options)
    gate = gate_record(options.gate_review)
    external_record = manifest_record(:external_construct_dataset_manifest,
        options.external_manifest, EXTERNAL_MANIFEST_SCHEMA,
        EXTERNAL_MANIFEST_FIELDS)
    independent_record =
        manifest_record(:independent_public_scope_review_manifest,
            options.independent_review, INDEPENDENT_REVIEW_SCHEMA,
            INDEPENDENT_REVIEW_FIELDS)
    manifests = [external_record, independent_record]
    field_rows = vcat(
        manifest_field_rows(external_record, EXTERNAL_MANIFEST_FIELDS),
        manifest_field_rows(independent_record, INDEPENDENT_REVIEW_FIELDS),
    )
    checks = preflight_check_rows(gate, external_record, independent_record)
    claim_rows = claim_release_preflight_rows(external_record, independent_record)
    blockers = blocker_rows(external_record, independent_record)
    remaining_blockers = [row.blocker for row in blockers if !row.resolved]
    field_specs_recorded =
        length(EXTERNAL_MANIFEST_FIELDS) == 13 &&
        length(INDEPENDENT_REVIEW_FIELDS) == 12
    missing_manifest_paths_recorded =
        !external_record.exists && !independent_record.exists
    no_public_claim_release =
        all(row -> !row.public_claim_release_allowed, claim_rows) &&
        all(row -> !row.public_claim_release_allowed, checks)
    gate_next_matched =
        gate.next_gate ==
        "provide_external_construct_dataset_manifest_and_independent_public_scope_review"
    passed =
        gate.summary_passed &&
        gate.schema_matches &&
        gate_next_matched &&
        field_specs_recorded &&
        missing_manifest_paths_recorded &&
        no_public_claim_release

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_external_construct_attachment_intake_preflight.v1",
        family = :mgmfrm,
        scope = :external_construct_attachment_intake_preflight,
        status = :external_construct_attachment_intake_preflight_recorded,
        decision =
            :record_manifest_intake_preflight_keep_public_claims_blocked,
        public_fit = true,
        experimental_public = true,
        local_only = true,
        publication_or_registration_action = false,
        external_construct_dataset_manifest_valid =
            external_record.manifest_valid,
        independent_public_scope_review_manifest_valid =
            independent_record.manifest_valid,
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
        input_artifacts = [gate],
        manifest_records = manifests,
        manifest_field_rows = field_rows,
        preflight_check_rows = checks,
        claim_release_preflight_rows = claim_rows,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :external_attachment_intake_preflight_recorded,
            external_construct_dataset_manifest_valid =
                external_record.manifest_valid,
            independent_public_scope_review_manifest_valid =
                independent_record.manifest_valid,
            public_claim_release_allowed = false,
            required_followup =
                :attach_valid_external_construct_dataset_manifest_and_independent_public_scope_review_manifest,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            external_construct_gate_review_passed = gate.summary_passed,
            external_construct_gate_next_gate_matched = gate_next_matched,
            external_manifest_field_spec_recorded =
                length(EXTERNAL_MANIFEST_FIELDS) == 13,
            independent_review_field_spec_recorded =
                length(INDEPENDENT_REVIEW_FIELDS) == 12,
            missing_manifest_paths_recorded,
            external_construct_dataset_manifest_present =
                external_record.exists,
            independent_public_scope_review_manifest_present =
                independent_record.exists,
            external_construct_dataset_manifest_valid =
                external_record.manifest_valid,
            independent_public_scope_review_manifest_valid =
                independent_record.manifest_valid,
            no_public_claim_release,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            n_input_artifacts = 1,
            n_manifest_records = length(manifests),
            n_external_manifest_required_fields =
                length(EXTERNAL_MANIFEST_FIELDS),
            n_independent_review_required_fields =
                length(INDEPENDENT_REVIEW_FIELDS),
            n_manifest_field_rows = length(field_rows),
            n_preflight_check_rows = length(checks),
            n_claim_release_preflight_rows = length(claim_rows),
            n_blocker_rows = length(blockers),
            n_blockers = length(remaining_blockers),
            remaining_public_blockers = remaining_blockers,
            recommendation =
                :attach_valid_external_manifests_before_public_claim_release,
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
        " manifest_fields=", artifact.summary.n_manifest_field_rows,
        " blockers=", artifact.summary.n_blockers,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

main(ARGS)
