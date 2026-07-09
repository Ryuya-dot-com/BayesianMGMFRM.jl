#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_external_construct_dataset_and_independent_public_scope_review.json")
const DEFAULT_THRESHOLD_MODEL_WEIGHT_REVIEW =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_threshold_model_weight_policy_review.json")
const DEFAULT_FULL_HELDOUT_REFIT_REVIEW =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_full_heldout_refit_or_construct_validation_review.json")
const DEFAULT_BATCH_RESULTS_REVIEW =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_batch_results_review.json")
const DEFAULT_MANUAL_SCOPE_REVIEW =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_manual_public_scope_review_for_fit.json")
const DEFAULT_EXTERNAL_CONSTRUCT_DATASET_MANIFEST =
    joinpath(ROOT, "test", "fixtures", "external",
        "mgmfrm_external_construct_dataset_manifest.json")
const DEFAULT_INDEPENDENT_PUBLIC_SCOPE_REVIEW_MANIFEST =
    joinpath(ROOT, "test", "fixtures", "external",
        "mgmfrm_independent_public_scope_review_manifest.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_SPECS = [
    (artifact = :mgmfrm_publication_grade_threshold_model_weight_policy_review,
        expected_schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_threshold_model_weight_policy_review.v1"),
    (artifact = :mgmfrm_full_heldout_refit_or_construct_validation_review,
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_refit_or_construct_validation_review.v1"),
    (artifact = :mgmfrm_publication_grade_refit_batch_results_review,
        expected_schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_results_review.v1"),
    (artifact = :mgmfrm_manual_public_scope_review_for_fit,
        expected_schema =
            "bayesianmgmfrm.mgmfrm_manual_public_scope_review_for_fit.v1"),
]

const PROTOCOL = (;
    protocol_id =
        "mgmfrm_external_construct_dataset_and_independent_public_scope_review_v1",
    review_kind =
        :local_external_construct_dataset_and_independent_public_scope_review,
    publication_or_registration_action = false,
    local_only = true,
    source_gate =
        :attach_external_construct_dataset_and_independent_public_scope_review,
    decision_scope =
        :requirements_before_public_mgmfrm_construct_model_weight_or_sparse_claims,
    thresholds = (;
        require_threshold_model_weight_policy_review_passed = true,
        require_threshold_model_weight_policy_review_next_gate_matched = true,
        require_full_heldout_refit_or_construct_validation_review_passed = true,
        require_publication_grade_batch_results_review_passed = true,
        require_manual_public_scope_review_for_fit_passed = true,
        require_publication_grade_batch_completed = true,
        require_external_construct_requirements_recorded = true,
        require_external_attachment_schema_recorded = true,
        require_independent_review_schema_recorded = true,
        require_missing_external_dataset_manifest_recorded = true,
        require_missing_independent_review_manifest_recorded = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_q_revision_claim = true,
        require_no_public_model_weight_claim = true,
        require_no_sparse_superiority_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM external construct dataset / independent
    public-scope review gate.

    This artifact audits the gate after the publication-grade threshold and
    model-weight review. It records the external dataset manifest, construct
    validation, and independent public-scope review requirements that remain
    before any public fit-metric, Q-revision, model-weight, construct-validity,
    or sparse-superiority claim can be made.

    Usage:
      julia --project=. scripts/generate_mgmfrm_external_construct_dataset_and_independent_public_scope_review.jl [--output PATH]
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    threshold_model_weight_review = DEFAULT_THRESHOLD_MODEL_WEIGHT_REVIEW
    full_heldout_refit_review = DEFAULT_FULL_HELDOUT_REFIT_REVIEW
    batch_results_review = DEFAULT_BATCH_RESULTS_REVIEW
    manual_scope_review = DEFAULT_MANUAL_SCOPE_REVIEW
    external_construct_dataset_manifest =
        DEFAULT_EXTERNAL_CONSTRUCT_DATASET_MANIFEST
    independent_public_scope_review_manifest =
        DEFAULT_INDEPENDENT_PUBLIC_SCOPE_REVIEW_MANIFEST
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg == "--threshold-model-weight-review"
            index < length(args) ||
                error("--threshold-model-weight-review requires a path")
            threshold_model_weight_review = abspath(args[index + 1])
            index += 2
        elseif arg == "--full-heldout-refit-review"
            index < length(args) ||
                error("--full-heldout-refit-review requires a path")
            full_heldout_refit_review = abspath(args[index + 1])
            index += 2
        elseif arg == "--batch-results-review"
            index < length(args) ||
                error("--batch-results-review requires a path")
            batch_results_review = abspath(args[index + 1])
            index += 2
        elseif arg == "--manual-scope-review"
            index < length(args) || error("--manual-scope-review requires a path")
            manual_scope_review = abspath(args[index + 1])
            index += 2
        elseif arg == "--external-construct-dataset-manifest"
            index < length(args) ||
                error("--external-construct-dataset-manifest requires a path")
            external_construct_dataset_manifest = abspath(args[index + 1])
            index += 2
        elseif arg == "--independent-public-scope-review-manifest"
            index < length(args) ||
                error("--independent-public-scope-review-manifest requires a path")
            independent_public_scope_review_manifest = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; output, threshold_model_weight_review,
        full_heldout_refit_review, batch_results_review, manual_scope_review,
        external_construct_dataset_manifest,
        independent_public_scope_review_manifest)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_string(value) = String(value)

function load_json(path::AbstractString)
    return JSON3.read(read(path, String))
end

function json_get(object, key::Symbol, default = missing)
    return haskey(object, key) && object[key] !== nothing ? object[key] :
           default
end

function artifact_record(artifact::Symbol, path::AbstractString,
        expected_schema::AbstractString)
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
            summary_passed = false,
        )
    end
    parsed = load_json(path)
    schema = as_string(parsed[:schema])
    return (;
        artifact,
        path = rel(path),
        exists,
        sha256 = file_sha256(path),
        expected_schema,
        schema,
        schema_matches = schema == expected_schema,
        summary_passed = as_bool(parsed[:summary][:passed]),
    )
end

function attachment_record(artifact::Symbol, path::AbstractString,
        expected_schema::AbstractString, purpose::Symbol)
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
            summary_passed = false,
            attachment_required = true,
            purpose,
        )
    end
    parsed = load_json(path)
    schema = as_string(parsed[:schema])
    summary = json_get(parsed, :summary, missing)
    summary_passed =
        summary === missing ? false : as_bool(summary[:passed])
    return (;
        artifact,
        path = rel(path),
        exists,
        sha256 = file_sha256(path),
        expected_schema,
        schema,
        schema_matches = schema == expected_schema,
        summary_passed,
        attachment_required = true,
        purpose,
    )
end

function input_artifacts(options)
    paths = Dict(
        :mgmfrm_publication_grade_threshold_model_weight_policy_review =>
            options.threshold_model_weight_review,
        :mgmfrm_full_heldout_refit_or_construct_validation_review =>
            options.full_heldout_refit_review,
        :mgmfrm_publication_grade_refit_batch_results_review =>
            options.batch_results_review,
        :mgmfrm_manual_public_scope_review_for_fit =>
            options.manual_scope_review,
    )
    return [artifact_record(spec.artifact, paths[spec.artifact],
        spec.expected_schema) for spec in INPUT_SPECS]
end

function attachment_records(options)
    return [
        attachment_record(
            :external_construct_dataset_manifest,
            options.external_construct_dataset_manifest,
            "bayesianmgmfrm.external_construct_dataset_manifest.v1",
            :construct_validation_dataset_attachment),
        attachment_record(
            :independent_public_scope_review_manifest,
            options.independent_public_scope_review_manifest,
            "bayesianmgmfrm.independent_public_scope_review_manifest.v1",
            :independent_public_claim_scope_review),
    ]
end

function external_construct_requirement_rows(full_review)
    return [
        (scenario = as_string(row[:scenario]),
            validation_target = as_string(row[:validation_target]),
            trigger = as_string(row[:trigger]),
            evidence_required = as_string(row[:evidence_required]),
            external_construct_dataset_manifest_attached = false,
            external_construct_validation_completed =
                as_bool(row[:external_construct_validation_completed]),
            public_q_revision_claim_allowed = false,
            public_model_superiority_claim_allowed = false,
            status = :blocked_external_construct_dataset_missing)
        for row in full_review[:external_construct_validation_rows]
    ]
end

function attachment_requirement_rows()
    return [
        (attachment = :external_construct_dataset_manifest,
            requirement = :manifest_schema,
            expected = :bayesianmgmfrm_external_construct_dataset_manifest_v1),
        (attachment = :external_construct_dataset_manifest,
            requirement = :dataset_source_documentation,
            expected = :source_dataset_id_provenance_license_and_collection_context),
        (attachment = :external_construct_dataset_manifest,
            requirement = :observation_crosswalk,
            expected = :observation_person_item_rater_and_score_keys),
        (attachment = :external_construct_dataset_manifest,
            requirement = :construct_anchor,
            expected = :external_construct_measure_or_independent_rubric_score),
        (attachment = :external_construct_dataset_manifest,
            requirement = :validation_split,
            expected = :predeclared_split_or_external_sample_membership),
        (attachment = :external_construct_dataset_manifest,
            requirement = :reproducible_scoring_plan,
            expected = :heldout_or_external_log_score_recomputation_instructions),
        (attachment = :independent_public_scope_review_manifest,
            requirement = :manifest_schema,
            expected = :bayesianmgmfrm_independent_public_scope_review_manifest_v1),
        (attachment = :independent_public_scope_review_manifest,
            requirement = :reviewer_independence_statement,
            expected = :reviewer_not_involved_in_model_development_or_batch_generation),
        (attachment = :independent_public_scope_review_manifest,
            requirement = :conflict_of_interest_statement,
            expected = :explicit_conflict_disclosure_and_resolution),
        (attachment = :independent_public_scope_review_manifest,
            requirement = :reviewed_artifacts,
            expected = :threshold_model_weight_batch_and_external_construct_artifacts),
        (attachment = :independent_public_scope_review_manifest,
            requirement = :claim_decision_table,
            expected = :per_claim_allow_block_or_request_revision_decision),
        (attachment = :independent_public_scope_review_manifest,
            requirement = :signed_public_scope_decision,
            expected = :dated_reviewer_signature_or_equivalent_audit_record),
    ]
end

function independent_review_requirement_rows()
    return [
        (review_surface = :fit_metric_claim,
            required_artifacts =
                [:publication_grade_batch_results_review,
                    :threshold_model_weight_policy_review],
            independent_review_completed = false,
            public_claim_allowed = false),
        (review_surface = :model_weight_claim,
            required_artifacts =
                [:publication_grade_batch_results_review,
                    :threshold_model_weight_policy_review,
                    :prediction_target_and_model_weight_policy],
            independent_review_completed = false,
            public_claim_allowed = false),
        (review_surface = :q_revision_claim,
            required_artifacts =
                [:external_construct_dataset_manifest,
                    :external_construct_validation_results],
            independent_review_completed = false,
            public_claim_allowed = false),
        (review_surface = :sparse_superiority_claim,
            required_artifacts =
                [:external_construct_dataset_manifest,
                    :publication_grade_threshold_model_weight_policy_review],
            independent_review_completed = false,
            public_claim_allowed = false),
    ]
end

function claim_release_rows()
    return [
        (claim = :publication_grade_fit_metric_claim,
            local_preconditions_satisfied = true,
            external_construct_dataset_required = false,
            independent_public_scope_review_required = true,
            release_status = :blocked_independent_public_scope_review_missing,
            public_claim_allowed = false),
        (claim = :model_weight_claim,
            local_preconditions_satisfied = true,
            external_construct_dataset_required = true,
            independent_public_scope_review_required = true,
            release_status =
                :blocked_external_construct_dataset_and_independent_review_missing,
            public_claim_allowed = false),
        (claim = :q_revision_claim,
            local_preconditions_satisfied = true,
            external_construct_dataset_required = true,
            independent_public_scope_review_required = true,
            release_status =
                :blocked_external_construct_dataset_and_independent_review_missing,
            public_claim_allowed = false),
        (claim = :construct_validity_claim,
            local_preconditions_satisfied = false,
            external_construct_dataset_required = true,
            independent_public_scope_review_required = true,
            release_status = :blocked_external_construct_validation_missing,
            public_claim_allowed = false),
        (claim = :sparse_mgmfrm_superiority_claim,
            local_preconditions_satisfied = true,
            external_construct_dataset_required = true,
            independent_public_scope_review_required = true,
            release_status =
                :blocked_external_construct_dataset_and_independent_review_missing,
            public_claim_allowed = false),
    ]
end

function blocker_rows(external_manifest_present::Bool,
        external_validation_completed::Bool,
        independent_manifest_present::Bool,
        independent_review_completed::Bool)
    return [
        (blocker = :external_construct_dataset_manifest_missing,
            blocks = :public_construct_q_revision_model_weight_and_sparse_claims,
            resolved = external_manifest_present),
        (blocker = :external_construct_validation_not_completed,
            blocks = :public_construct_and_q_revision_claims,
            resolved = external_validation_completed),
        (blocker = :independent_public_scope_review_manifest_missing,
            blocks = :all_public_mgmfrm_claims,
            resolved = independent_manifest_present),
        (blocker = :independent_public_scope_review_not_completed,
            blocks = :all_public_mgmfrm_claims,
            resolved = independent_review_completed),
        (blocker = :public_claim_release_decision_not_signed,
            blocks = :public_model_weight_q_revision_fit_metric_and_sparse_claims,
            resolved = independent_review_completed),
    ]
end

function evidence_link_rows(threshold_review, full_review, batch_review,
        manual_review, attachments)
    threshold_summary = threshold_review[:summary]
    full_summary = full_review[:summary]
    batch_summary = batch_review[:summary]
    manual_summary = manual_review[:summary]
    external_record = only(row for row in attachments
        if row.artifact === :external_construct_dataset_manifest)
    independent_record = only(row for row in attachments
        if row.artifact === :independent_public_scope_review_manifest)
    return [
        (evidence = :threshold_model_weight_policy_review_next_gate,
            link_satisfied =
                as_string(threshold_summary[:next_gate]) ==
                "attach_external_construct_dataset_and_independent_public_scope_review",
            role = :supplies_current_public_claim_blockers),
        (evidence = :full_heldout_refit_or_construct_validation_review,
            link_satisfied =
                as_bool(full_summary[
                    :external_construct_validation_requirements_recorded]),
            role = :supplies_external_construct_validation_requirements),
        (evidence = :publication_grade_batch_results_review,
            link_satisfied = as_bool(batch_summary[:all_125_units_executed]),
            role = :supplies_completed_publication_grade_batch_state),
        (evidence = :manual_public_scope_review_for_fit,
            link_satisfied =
                as_bool(manual_summary[:manual_public_scope_review_satisfied]),
            role = :supplies_local_scope_review_not_independent_release),
        (evidence = :external_attachment_manifests,
            link_satisfied = !external_record.exists && !independent_record.exists,
            role = :records_missing_external_and_independent_review_inputs),
    ]
end

function build_artifact(options)
    inputs = input_artifacts(options)
    attachments = attachment_records(options)
    threshold_review = load_json(options.threshold_model_weight_review)
    full_review = load_json(options.full_heldout_refit_review)
    batch_review = load_json(options.batch_results_review)
    manual_review = load_json(options.manual_scope_review)

    threshold_summary = threshold_review[:summary]
    full_summary = full_review[:summary]
    batch_summary = batch_review[:summary]
    manual_summary = manual_review[:summary]

    external_record = only(row for row in attachments
        if row.artifact === :external_construct_dataset_manifest)
    independent_record = only(row for row in attachments
        if row.artifact === :independent_public_scope_review_manifest)
    external_construct_dataset_attached =
        external_record.exists && external_record.schema_matches &&
        external_record.summary_passed
    independent_public_scope_review_completed =
        independent_record.exists && independent_record.schema_matches &&
        independent_record.summary_passed
    external_construct_validation_completed =
        as_bool(full_summary[:external_construct_validation_completed]) &&
        external_construct_dataset_attached

    external_rows = external_construct_requirement_rows(full_review)
    attachment_requirements = attachment_requirement_rows()
    independent_rows = independent_review_requirement_rows()
    claim_rows = claim_release_rows()
    blockers = blocker_rows(external_record.exists,
        external_construct_validation_completed, independent_record.exists,
        independent_public_scope_review_completed)
    evidence_rows = evidence_link_rows(threshold_review, full_review,
        batch_review, manual_review, attachments)

    all_input_artifacts_present = all(row -> row.exists, inputs)
    all_expected_schemas = all(row -> row.schema_matches, inputs)
    all_input_summaries_passed = all(row -> row.summary_passed, inputs)
    threshold_review_next_gate_matched =
        as_string(threshold_summary[:next_gate]) ==
        "attach_external_construct_dataset_and_independent_public_scope_review"
    external_construct_requirements_recorded = !isempty(external_rows)
    external_attachment_schema_recorded =
        count(row -> row.attachment === :external_construct_dataset_manifest,
            attachment_requirements) == 6
    independent_review_schema_recorded =
        count(row -> row.attachment ===
            :independent_public_scope_review_manifest,
            attachment_requirements) == 6
    missing_external_dataset_manifest_recorded = !external_record.exists
    missing_independent_review_manifest_recorded = !independent_record.exists
    all_public_claims_blocked =
        all(row -> !row.public_claim_allowed, claim_rows) &&
        all(row -> !row.public_claim_allowed, independent_rows) &&
        all(row -> !row.public_q_revision_claim_allowed &&
            !row.public_model_superiority_claim_allowed, external_rows)
    no_public_fit_metric_claim = true
    no_public_q_revision_claim = true
    no_public_model_weight_claim = true
    no_sparse_superiority_claim = true
    remaining_public_blockers =
        [row.blocker for row in blockers if !row.resolved]

    passed =
        all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        threshold_review_next_gate_matched &&
        as_bool(threshold_summary[:passed]) &&
        as_bool(full_summary[:passed]) &&
        as_bool(batch_summary[:all_125_units_executed]) &&
        as_bool(manual_summary[:manual_public_scope_review_satisfied]) &&
        external_construct_requirements_recorded &&
        external_attachment_schema_recorded &&
        independent_review_schema_recorded &&
        missing_external_dataset_manifest_recorded &&
        missing_independent_review_manifest_recorded &&
        all_public_claims_blocked &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim

    next_gate = isempty(remaining_public_blockers) ?
        :independent_public_claim_release_decision :
        :provide_external_construct_dataset_manifest_and_independent_public_scope_review
    n_review_cells = length(external_rows) + length(attachment_requirements) +
        length(independent_rows) + length(claim_rows) + length(blockers) +
        length(evidence_rows)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_external_construct_dataset_and_independent_public_scope_review.v1",
        family = :mgmfrm,
        scope =
            :external_construct_dataset_and_independent_public_scope_review,
        status =
            :external_construct_dataset_and_independent_public_scope_review_recorded,
        decision =
            :record_external_construct_and_independent_review_requirements_keep_claims_blocked,
        public_fit = true,
        experimental_public = true,
        local_only = true,
        publication_or_registration_action = false,
        external_construct_dataset_attached,
        external_construct_validation_completed,
        independent_public_scope_review_completed,
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
        input_artifacts = inputs,
        attachment_records = attachments,
        external_construct_requirement_rows = external_rows,
        attachment_requirement_rows = attachment_requirements,
        independent_review_requirement_rows = independent_rows,
        claim_release_rows = claim_rows,
        blocker_rows = blockers,
        evidence_link_rows = evidence_rows,
        decision_record = (;
            selected_decision =
                :external_construct_and_independent_review_gate_recorded,
            publication_grade_batch_completed =
                as_bool(batch_summary[:all_125_units_executed]),
            threshold_model_weight_policy_review_completed =
                as_bool(threshold_summary[:passed]),
            local_manual_scope_review_satisfied =
                as_bool(manual_summary[:manual_public_scope_review_satisfied]),
            external_construct_dataset_attached,
            external_construct_validation_completed,
            independent_public_scope_review_completed,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            public_model_weight_claim_allowed = false,
            sparse_superiority_claim_allowed = false,
            required_followup = next_gate,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            threshold_model_weight_policy_review_passed =
                as_bool(threshold_summary[:passed]),
            threshold_model_weight_policy_review_next_gate_matched =
                threshold_review_next_gate_matched,
            full_heldout_refit_or_construct_validation_review_passed =
                as_bool(full_summary[:passed]),
            publication_grade_batch_results_review_passed =
                as_bool(batch_summary[:passed]),
            manual_public_scope_review_for_fit_passed =
                as_bool(manual_summary[:passed]),
            manual_public_scope_review_satisfied =
                as_bool(manual_summary[:manual_public_scope_review_satisfied]),
            publication_grade_batch_completed =
                as_bool(batch_summary[:all_125_units_executed]),
            all_mcmc_diagnostic_gates_passed =
                as_bool(batch_summary[:all_mcmc_diagnostic_gates_passed]),
            external_construct_requirements_recorded,
            external_attachment_schema_recorded,
            independent_review_schema_recorded,
            missing_external_dataset_manifest_recorded,
            missing_independent_review_manifest_recorded,
            external_construct_dataset_manifest_present =
                Bool(external_record.exists),
            independent_public_scope_review_manifest_present =
                Bool(independent_record.exists),
            external_construct_dataset_attached,
            external_construct_validation_completed,
            independent_public_scope_review_completed,
            all_public_claims_blocked,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            n_input_artifacts = length(inputs),
            n_attachment_records = length(attachments),
            n_external_construct_requirement_rows = length(external_rows),
            n_attachment_requirement_rows = length(attachment_requirements),
            n_independent_review_requirement_rows = length(independent_rows),
            n_claim_release_rows = length(claim_rows),
            n_blocker_rows = length(blockers),
            n_evidence_link_rows = length(evidence_rows),
            n_review_cells,
            n_external_construct_validation_scenarios =
                as_int(full_summary[:n_external_construct_validation_scenarios]),
            n_blockers = length(remaining_public_blockers),
            remaining_public_blockers,
            recommendation =
                :attach_external_construct_dataset_manifest_and_independent_review_before_public_claims,
            next_gate,
        ),
    )
end

function main(args)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output, artifact)
    println("wrote ", rel(options.output))
    println("passed=", artifact.summary.passed,
        " blockers=", artifact.summary.n_blockers,
        " external_dataset_attached=",
        artifact.summary.external_construct_dataset_attached,
        " independent_review_completed=",
        artifact.summary.independent_public_scope_review_completed,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

main(ARGS)
