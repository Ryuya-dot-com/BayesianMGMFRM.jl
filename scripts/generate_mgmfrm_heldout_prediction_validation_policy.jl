#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_heldout_prediction_validation_policy.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :mgmfrm_construct_reviewed_q_fit_reporting_policy,
        path =
            "test/fixtures/mgmfrm_construct_reviewed_q_fit_reporting_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_construct_reviewed_q_fit_reporting_policy.v1"),
    (name = :prediction_target_and_model_weight_policy,
        path =
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_prediction_target_and_model_weight_policy.v1"),
    (name = :mgmfrm_q_revision_cross_validation_policy,
        path =
            "test/fixtures/mgmfrm_q_revision_cross_validation_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_revision_cross_validation_policy.v1"),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_heldout_prediction_validation_policy_v1",
    review_kind = :local_heldout_prediction_or_external_validation_policy,
    publication_or_registration_action = false,
    local_only = true,
    policy_scope = :claim_gate_after_construct_reviewed_q_fit_reporting_policy,
    decision_target = :heldout_prediction_or_external_validation_before_claims,
    thresholds = (;
        require_construct_reviewed_q_fit_reporting_policy_passed = true,
        require_prediction_target_and_model_weight_policy_passed = true,
        require_q_revision_cross_validation_policy_passed = true,
        require_reporting_policy_next_gate_matched = true,
        require_heldout_kfold_target_selected = true,
        require_same_data_waic_blocked_for_claims = true,
        require_raw_psis_loo_blocked_for_claims = true,
        require_external_construct_validation_before_q_claims = true,
        require_no_single_threshold_profile_promoted = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_q_revision_claim = true,
        require_no_model_weight_or_sparse_superiority_claim = true,
        require_no_automatic_q_revision = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM heldout-prediction validation policy.

    This artifact records the post-fit-reporting-policy gate: MGMFRM fit
    metrics, Q revisions, and model-weight or sparse-superiority claims remain
    blocked until heldout prediction or external construct-validation evidence
    is recorded. It consumes existing local policy artifacts and does not run
    MCMC, publish, register, or promote same-data fit statistics.

    Usage:
      julia --project=. scripts/generate_mgmfrm_heldout_prediction_validation_policy.jl [--output PATH]
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

project_version() = String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
fixture_path(path::AbstractString) = normpath(joinpath(ROOT, path))

as_string(value) = String(value)
as_bool(value) = Bool(value)
as_int(value) = Int(value)

function artifact_summary(name::Symbol, summary)
    name === :mgmfrm_construct_reviewed_q_fit_reporting_policy && return (;
        passed = as_bool(summary[:passed]),
        next_gate = as_string(summary[:next_gate]),
        threshold_profile_surface_recorded =
            as_bool(summary[:threshold_profile_surface_recorded]),
        indicator_conflicts_recorded =
            as_bool(summary[:indicator_conflicts_recorded]),
        all_policy_rows_block_public_claims =
            as_bool(summary[:all_policy_rows_block_public_claims]),
        no_single_threshold_profile_promoted =
            as_bool(summary[:no_single_threshold_profile_promoted]),
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        no_automatic_q_revision =
            as_bool(summary[:no_automatic_q_revision]),
        n_reporting_evidence_cells =
            as_int(summary[:n_reporting_evidence_cells]),
    )
    name === :prediction_target_and_model_weight_policy && return (;
        passed = as_bool(summary[:passed]),
        heldout_kfold_selected =
            as_bool(summary[:heldout_kfold_selected]),
        same_data_waic_blocked =
            as_bool(summary[:same_data_waic_blocked]),
        raw_psis_loo_blocked =
            as_bool(summary[:raw_psis_loo_blocked]),
        public_model_weight_claims_allowed =
            as_bool(summary[:public_model_weight_claims_allowed]),
        mgmfrm_fit_allowed =
            as_bool(summary[:mgmfrm_fit_allowed]),
        mgmfrm_weight_claims_allowed =
            as_bool(summary[:mgmfrm_weight_claims_allowed]),
        manuscript_sparse_mgmfrm_claims_allowed =
            as_bool(summary[:manuscript_sparse_mgmfrm_claims_allowed]),
        primary_prediction_target =
            as_string(summary[:primary_prediction_target]),
    )
    name === :mgmfrm_q_revision_cross_validation_policy && return (;
        passed = as_bool(summary[:passed]),
        construct_validity_manual_review_required =
            as_bool(summary[:construct_validity_manual_review_required]),
        supported_candidates_remain_manual_review_only =
            as_bool(summary[:supported_candidates_remain_manual_review_only]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        no_automatic_q_revision =
            as_bool(summary[:no_automatic_q_revision]),
        n_cv_supported_candidates =
            as_int(summary[:n_cv_supported_candidates]),
    )
    return (; passed = as_bool(summary[:passed]))
end

function artifact_record(spec)
    path = fixture_path(spec.path)
    exists = isfile(path)
    if !exists
        return (;
            artifact = spec.name,
            path = spec.path,
            exists = false,
            sha256 = missing,
            schema = missing,
            expected_schema = spec.expected_schema,
            schema_matches = false,
            summary_passed = false,
            summary = (; passed = false),
        )
    end
    fixture = JSON3.read(read(path, String))
    schema = as_string(fixture[:schema])
    schema_matches = schema == spec.expected_schema
    summary = artifact_summary(spec.name, fixture[:summary])
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        sha256 = file_sha256(path),
        schema,
        expected_schema = spec.expected_schema,
        schema_matches,
        summary_passed = summary.passed,
        summary,
    )
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function validation_target_rows(reporting, prediction, qcv)
    return [
        (target = :heldout_kfold_log_score,
            status = :required_before_model_weight_or_sparse_superiority_claims,
            selected_by_existing_policy =
                Bool(prediction.summary.heldout_kfold_selected),
            requirement_recorded = true,
            evidence_available_for_public_mgmfrm_claim = false,
            public_claim_allowed = false,
            source_artifact = prediction.path),
        (target = :external_construct_validation,
            status = :required_before_q_revision_claims,
            selected_by_existing_policy =
                Bool(qcv.summary.construct_validity_manual_review_required),
            requirement_recorded = true,
            evidence_available_for_public_mgmfrm_claim = false,
            public_claim_allowed = false,
            source_artifact = qcv.path),
        (target = :same_data_waic_or_loo,
            status = :diagnostic_only_not_claim_target,
            selected_by_existing_policy = false,
            requirement_recorded = true,
            evidence_available_for_public_mgmfrm_claim = false,
            public_claim_allowed = false,
            source_artifact = reporting.path),
        (target = :threshold_profile_pass_fail,
            status = :diagnostic_only_not_claim_target,
            selected_by_existing_policy = false,
            requirement_recorded =
                Bool(reporting.summary.threshold_profile_surface_recorded),
            evidence_available_for_public_mgmfrm_claim = false,
            public_claim_allowed = false,
            source_artifact = reporting.path),
        (target = :posterior_predictive_calibration,
            status = :local_diagnostic_requires_replication,
            selected_by_existing_policy = false,
            requirement_recorded =
                Bool(reporting.summary.indicator_conflicts_recorded),
            evidence_available_for_public_mgmfrm_claim = false,
            public_claim_allowed = false,
            source_artifact = reporting.path),
        (target = :common_parameter_shift,
            status = :impact_screen_not_claim_target,
            selected_by_existing_policy = false,
            requirement_recorded =
                Bool(reporting.summary.indicator_conflicts_recorded),
            evidence_available_for_public_mgmfrm_claim = false,
            public_claim_allowed = false,
            source_artifact = reporting.path),
    ]
end

function claim_gate_rows()
    return [
        (claim = :construct_reviewed_q_fit_metric_claim,
            status = :blocked_until_heldout_or_external_validation,
            local_reporting_allowed = true,
            public_claim_allowed = false,
            required_evidence =
                :heldout_mgmfrm_prediction_or_external_validation_study),
        (claim = :candidate_q_revision_claim,
            status = :blocked_until_external_construct_validation,
            local_reporting_allowed = false,
            public_claim_allowed = false,
            required_evidence =
                :external_construct_validation_plus_cross_validation),
        (claim = :automatic_q_revision,
            status = :blocked,
            local_reporting_allowed = false,
            public_claim_allowed = false,
            required_evidence = :not_supported_by_policy),
        (claim = :model_weight_or_sparse_mgmfrm_superiority,
            status = :blocked_until_heldout_mgmfrm_prediction_study,
            local_reporting_allowed = false,
            public_claim_allowed = false,
            required_evidence =
                :heldout_mgmfrm_prediction_study_and_public_scope_review),
        (claim = :local_appendix_diagnostics,
            status = :allowed_as_local_diagnostic_only,
            local_reporting_allowed = true,
            public_claim_allowed = false,
            required_evidence = :existing_local_policy_artifacts),
    ]
end

function evidence_link_rows(reporting, prediction, qcv)
    return [
        (artifact = reporting.artifact,
            path = reporting.path,
            link_satisfied = Bool(reporting.summary_passed) &&
                reporting.summary.next_gate ==
                    "heldout_prediction_or_external_validation_before_claims" &&
                Bool(reporting.summary.all_policy_rows_block_public_claims) &&
                Bool(reporting.summary.no_public_fit_metric_claim) &&
                Bool(reporting.summary.no_public_q_revision_claim) &&
                Bool(reporting.summary.no_automatic_q_revision),
            evidence_role =
                :fit_reporting_policy_supplies_claim_blocking_surface),
        (artifact = prediction.artifact,
            path = prediction.path,
            link_satisfied = Bool(prediction.summary_passed) &&
                Bool(prediction.summary.heldout_kfold_selected) &&
                Bool(prediction.summary.same_data_waic_blocked) &&
                Bool(prediction.summary.raw_psis_loo_blocked) &&
                !Bool(prediction.summary.public_model_weight_claims_allowed) &&
                !Bool(prediction.summary.mgmfrm_weight_claims_allowed) &&
                !Bool(prediction.summary.manuscript_sparse_mgmfrm_claims_allowed),
            evidence_role =
                :heldout_target_selected_while_mgmfrm_weight_claims_remain_blocked),
        (artifact = qcv.artifact,
            path = qcv.path,
            link_satisfied = Bool(qcv.summary_passed) &&
                Bool(qcv.summary.construct_validity_manual_review_required) &&
                Bool(qcv.summary.supported_candidates_remain_manual_review_only) &&
                Bool(qcv.summary.no_public_q_revision_claim) &&
                Bool(qcv.summary.no_automatic_q_revision),
            evidence_role =
                :q_revision_cv_requires_construct_validation_and_blocks_claims),
    ]
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_heldout_prediction_validation_policy.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    reporting =
        record_by_name(records, :mgmfrm_construct_reviewed_q_fit_reporting_policy)
    prediction =
        record_by_name(records, :prediction_target_and_model_weight_policy)
    qcv = record_by_name(records, :mgmfrm_q_revision_cross_validation_policy)
    targets = validation_target_rows(reporting, prediction, qcv)
    claim_gates = claim_gate_rows()
    links = evidence_link_rows(reporting, prediction, qcv)
    no_publication = no_publication_commands()

    all_input_artifacts_present = all(record -> record.exists, records)
    all_expected_schemas = all(record -> record.schema_matches, records)
    all_input_summaries_passed = all(record -> record.summary_passed, records)
    input_next_gate_matched =
        reporting.summary.next_gate ==
            "heldout_prediction_or_external_validation_before_claims"
    heldout_kfold_selected_from_scalar_policy =
        Bool(prediction.summary.heldout_kfold_selected) &&
        prediction.summary.primary_prediction_target ==
            "heldout_observation_log_score"
    same_data_waic_claim_blocked =
        Bool(prediction.summary.same_data_waic_blocked)
    raw_psis_loo_claim_blocked =
        Bool(prediction.summary.raw_psis_loo_blocked)
    external_construct_validation_required_for_q_claims =
        Bool(qcv.summary.construct_validity_manual_review_required)
    no_single_threshold_profile_promoted =
        Bool(reporting.summary.no_single_threshold_profile_promoted)
    no_public_fit_metric_claim =
        Bool(reporting.summary.no_public_fit_metric_claim)
    no_public_q_revision_claim =
        Bool(reporting.summary.no_public_q_revision_claim) &&
        Bool(qcv.summary.no_public_q_revision_claim)
    no_automatic_q_revision =
        Bool(reporting.summary.no_automatic_q_revision) &&
        Bool(qcv.summary.no_automatic_q_revision)
    no_model_weight_or_sparse_superiority_claim =
        !Bool(prediction.summary.public_model_weight_claims_allowed) &&
        !Bool(prediction.summary.mgmfrm_weight_claims_allowed) &&
        !Bool(prediction.summary.manuscript_sparse_mgmfrm_claims_allowed)
    all_claim_gate_rows_block_public_claims =
        all(row -> !Bool(row.public_claim_allowed), claim_gates)
    all_validation_requirements_recorded =
        all(row -> Bool(row.requirement_recorded), targets)
    all_evidence_links_satisfied = all(row -> Bool(row.link_satisfied), links)
    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        input_next_gate_matched &&
        heldout_kfold_selected_from_scalar_policy &&
        same_data_waic_claim_blocked &&
        raw_psis_loo_claim_blocked &&
        external_construct_validation_required_for_q_claims &&
        no_single_threshold_profile_promoted &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_automatic_q_revision &&
        no_model_weight_or_sparse_superiority_claim &&
        all_claim_gate_rows_block_public_claims &&
        all_validation_requirements_recorded &&
        all_evidence_links_satisfied &&
        no_publication
    remaining_public_blockers = [
        :heldout_mgmfrm_prediction_study_missing,
        :external_construct_validation_missing,
    ]

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_heldout_prediction_validation_policy.v1",
        family = :mgmfrm,
        scope = :heldout_prediction_validation_policy,
        status = :heldout_prediction_validation_policy_recorded,
        decision =
            :require_heldout_or_external_validation_before_fit_or_q_claims,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        public_fit_metric_claim = false,
        public_q_revision_claim = false,
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        automatic_q_revision = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        input_artifacts = records,
        validation_target_rows = targets,
        claim_gate_rows = claim_gates,
        evidence_link_rows = links,
        decision_record = (;
            selected_decision =
                :require_heldout_or_external_validation_before_fit_or_q_claims,
            validation_policy_recorded = true,
            heldout_kfold_selected_from_scalar_policy,
            heldout_mgmfrm_prediction_study_completed = false,
            external_construct_validation_completed = false,
            same_data_waic_claim_allowed = false,
            raw_psis_loo_claim_allowed = false,
            threshold_only_fit_claim_allowed = false,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            automatic_q_revision_allowed = false,
            local_appendix_diagnostics_allowed = true,
            required_followup =
                :heldout_mgmfrm_prediction_or_external_validation_study,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            input_next_gate_matched,
            construct_reviewed_q_fit_reporting_policy_passed =
                reporting.summary_passed,
            prediction_target_and_model_weight_policy_passed =
                prediction.summary_passed,
            mgmfrm_q_revision_cross_validation_policy_passed =
                qcv.summary_passed,
            heldout_kfold_selected_from_scalar_policy,
            heldout_or_external_validation_required = true,
            external_construct_validation_required_for_q_claims,
            same_data_waic_claim_blocked,
            raw_psis_loo_claim_blocked,
            threshold_profile_only_claim_blocked = true,
            no_single_threshold_profile_promoted,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_automatic_q_revision,
            no_model_weight_or_sparse_superiority_claim,
            all_claim_gate_rows_block_public_claims,
            all_validation_requirements_recorded,
            all_evidence_links_satisfied,
            n_input_artifacts = length(records),
            n_validation_target_rows = length(targets),
            n_claim_gate_rows = length(claim_gates),
            n_evidence_link_rows = length(links),
            n_validation_policy_cells =
                length(targets) + length(claim_gates) + length(links),
            n_unmet_public_claim_requirements =
                length(remaining_public_blockers),
            n_blockers = length(remaining_public_blockers),
            remaining_public_blockers,
            recommendation =
                :run_heldout_mgmfrm_prediction_or_external_validation_before_claims,
            next_gate =
                :heldout_mgmfrm_prediction_or_external_validation_study,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " validation_policy_cells=",
        artifact.summary.n_validation_policy_cells,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
