#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_validation_split_model_comparison_policy.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :mgmfrm_heldout_prediction_validation_policy,
        path =
            "test/fixtures/mgmfrm_heldout_prediction_validation_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_heldout_prediction_validation_policy.v1"),
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
    (name = :mgmfrm_construct_reviewed_q_fit_reporting_policy,
        path =
            "test/fixtures/mgmfrm_construct_reviewed_q_fit_reporting_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_construct_reviewed_q_fit_reporting_policy.v1"),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_validation_split_model_comparison_policy_v1",
    review_kind = :local_validation_split_and_model_comparison_policy,
    publication_or_registration_action = false,
    local_only = true,
    policy_scope =
        :pre_execution_protocol_for_heldout_mgmfrm_prediction_validation,
    decision_target =
        :predeclare_split_units_leakage_guards_and_comparison_models,
    thresholds = (;
        require_heldout_prediction_validation_policy_passed = true,
        require_prediction_target_and_model_weight_policy_passed = true,
        require_q_revision_cross_validation_policy_passed = true,
        require_construct_reviewed_q_fit_reporting_policy_passed = true,
        require_heldout_policy_next_gate_matched = true,
        require_primary_holdout_target_selected = true,
        require_split_policy_recorded = true,
        require_comparison_model_set_recorded = true,
        require_all_leakage_guards_recorded = true,
        require_all_claim_rules_block_public_claims_before_execution = true,
        require_same_data_fit_metrics_diagnostic_only = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_q_revision_claim = true,
        require_no_model_weight_or_sparse_superiority_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM validation split and model-comparison policy.

    This artifact predeclares the split units, leakage guards, comparison model
    set, and claim rules for the next heldout MGMFRM prediction study. It does
    not run MCMC, compute heldout results, publish, register, or promote
    same-data fit statistics.

    Usage:
      julia --project=. scripts/generate_mgmfrm_validation_split_model_comparison_policy.jl [--output PATH]
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
    name === :mgmfrm_heldout_prediction_validation_policy && return (;
        passed = as_bool(summary[:passed]),
        heldout_or_external_validation_required =
            as_bool(summary[:heldout_or_external_validation_required]),
        heldout_kfold_selected_from_scalar_policy =
            as_bool(summary[:heldout_kfold_selected_from_scalar_policy]),
        same_data_waic_claim_blocked =
            as_bool(summary[:same_data_waic_claim_blocked]),
        raw_psis_loo_claim_blocked =
            as_bool(summary[:raw_psis_loo_claim_blocked]),
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        no_automatic_q_revision =
            as_bool(summary[:no_automatic_q_revision]),
        no_model_weight_or_sparse_superiority_claim =
            as_bool(summary[:no_model_weight_or_sparse_superiority_claim]),
        n_validation_policy_cells =
            as_int(summary[:n_validation_policy_cells]),
        next_gate = as_string(summary[:next_gate]),
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
    name === :mgmfrm_construct_reviewed_q_fit_reporting_policy && return (;
        passed = as_bool(summary[:passed]),
        threshold_profile_surface_recorded =
            as_bool(summary[:threshold_profile_surface_recorded]),
        indicator_conflicts_recorded =
            as_bool(summary[:indicator_conflicts_recorded]),
        existing_model_reference_recorded =
            as_bool(summary[:existing_model_reference_recorded]),
        parameter_shift_impact_recorded =
            as_bool(summary[:parameter_shift_impact_recorded]),
        no_single_threshold_profile_promoted =
            as_bool(summary[:no_single_threshold_profile_promoted]),
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        no_automatic_q_revision =
            as_bool(summary[:no_automatic_q_revision]),
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

function split_policy_rows()
    return [
        (split = :observation_kfold,
            role = :primary_heldout_prediction_target,
            fold_assignment = :pre_fit_seeded_deterministic,
            heldout_unit = :rating_observation,
            minimum_train_fraction = 0.80,
            selected_for_first_execution = true,
            leakage_guard_required = true),
        (split = :respondent_holdout,
            role = :person_generalization_sensitivity,
            fold_assignment = :pre_fit_seeded_deterministic,
            heldout_unit = :respondent,
            minimum_train_fraction = 0.80,
            selected_for_first_execution = false,
            leakage_guard_required = true),
        (split = :item_holdout,
            role = :item_generalization_sensitivity,
            fold_assignment = :pre_fit_seeded_deterministic,
            heldout_unit = :item,
            minimum_train_fraction = 0.80,
            selected_for_first_execution = false,
            leakage_guard_required = true),
        (split = :scenario_replicate_holdout,
            role = :simulation_replication_sensitivity,
            fold_assignment = :pre_fit_seeded_deterministic,
            heldout_unit = :simulation_replicate,
            minimum_train_fraction = 0.80,
            selected_for_first_execution = false,
            leakage_guard_required = true),
    ]
end

function comparison_model_rows()
    return [
        (model = :scalar_gmfrm_baseline,
            family = :gmfrm,
            role = :existing_baseline,
            included = true,
            q_matrix_source = :not_applicable,
            claim_scope = :reference_only),
        (model = :confirmatory_mgmfrm_current_q,
            family = :mgmfrm,
            role = :primary_candidate,
            included = true,
            q_matrix_source = :current_construct_reviewed_q,
            claim_scope = :local_diagnostic_until_heldout_execution),
        (model = :sparse_mgmfrm_current_q,
            family = :mgmfrm,
            role = :sparsity_candidate,
            included = true,
            q_matrix_source = :current_construct_reviewed_q,
            claim_scope = :local_diagnostic_until_heldout_execution),
        (model = :construct_reviewed_revised_q_mgmfrm,
            family = :mgmfrm,
            role = :q_revision_candidate,
            included = true,
            q_matrix_source = :train_only_candidate_plus_construct_review,
            claim_scope = :blocked_until_external_construct_validation),
        (model = :null_or_intercept_reference,
            family = :reference,
            role = :calibration_anchor,
            included = true,
            q_matrix_source = :not_applicable,
            claim_scope = :reference_only),
    ]
end

function metric_rows()
    return [
        (metric = :heldout_log_predictive_density,
            role = :primary_predictive_metric,
            direction = :higher_is_better,
            public_claim_requires_execution = true),
        (metric = :heldout_response_accuracy_or_rank_score,
            role = :secondary_response_prediction_metric,
            direction = :higher_is_better,
            public_claim_requires_execution = true),
        (metric = :heldout_calibration_error,
            role = :secondary_calibration_metric,
            direction = :lower_is_better,
            public_claim_requires_execution = true),
        (metric = :posterior_predictive_discrepancy,
            role = :diagnostic_replication_metric,
            direction = :closer_to_reference_is_better,
            public_claim_requires_execution = true),
        (metric = :simulation_parameter_recovery_shift,
            role = :simulation_only_impact_metric,
            direction = :lower_is_better,
            public_claim_requires_execution = true),
    ]
end

function leakage_guard_rows()
    return [
        (guard = :fold_assignment_before_fit,
            requirement = :all_holdout_indices_fixed_before_model_fitting,
            requirement_recorded = true,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :q_revision_train_only,
            requirement =
                :q_revision_candidates_must_not_use_heldout_responses,
            requirement_recorded = true,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :threshold_profiles_locked_before_fit,
            requirement =
                :fit_indicator_threshold_profiles_must_be_predeclared,
            requirement_recorded = true,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :model_weight_claim_heldout_only,
            requirement =
                :model_weight_or_sparse_superiority_claims_use_heldout_metrics,
            requirement_recorded = true,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :same_data_diagnostics_not_claim_targets,
            requirement =
                :waic_loo_and_threshold_pass_fail_remain_diagnostic_only,
            requirement_recorded = true,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :external_validation_not_used_for_tuning,
            requirement =
                :external_construct_validation_cannot_tune_heldout_split,
            requirement_recorded = true,
            public_claim_blocked_if_unsatisfied = true),
    ]
end

function claim_rule_rows()
    return [
        (claim = :heldout_prediction_improvement,
            required_evidence = :executed_heldout_model_comparison,
            execution_completed = false,
            public_claim_allowed = false),
        (claim = :fit_metric_threshold_superiority,
            required_evidence = :heldout_metric_consistency_not_threshold_only,
            execution_completed = false,
            public_claim_allowed = false),
        (claim = :q_revision_improvement,
            required_evidence =
                :train_only_q_revision_plus_external_construct_validation,
            execution_completed = false,
            public_claim_allowed = false),
        (claim = :model_weight_or_sparse_mgmfrm_superiority,
            required_evidence = :heldout_prediction_study_with_stable_ranking,
            execution_completed = false,
            public_claim_allowed = false),
        (claim = :local_protocol_description,
            required_evidence = :this_policy_artifact,
            execution_completed = true,
            public_claim_allowed = false),
    ]
end

function evidence_link_rows(heldout, prediction, qcv, reporting)
    return [
        (artifact = heldout.artifact,
            path = heldout.path,
            link_satisfied = Bool(heldout.summary_passed) &&
                heldout.summary.next_gate ==
                    "heldout_mgmfrm_prediction_or_external_validation_study" &&
                Bool(heldout.summary.heldout_or_external_validation_required),
            evidence_role = :supplies_unmet_validation_gate),
        (artifact = prediction.artifact,
            path = prediction.path,
            link_satisfied = Bool(prediction.summary_passed) &&
                Bool(prediction.summary.heldout_kfold_selected) &&
                prediction.summary.primary_prediction_target ==
                    "heldout_observation_log_score",
            evidence_role = :supplies_primary_prediction_target),
        (artifact = qcv.artifact,
            path = qcv.path,
            link_satisfied = Bool(qcv.summary_passed) &&
                Bool(qcv.summary.construct_validity_manual_review_required) &&
                Bool(qcv.summary.supported_candidates_remain_manual_review_only),
            evidence_role = :supplies_train_only_q_revision_constraint),
        (artifact = reporting.artifact,
            path = reporting.path,
            link_satisfied = Bool(reporting.summary_passed) &&
                Bool(reporting.summary.threshold_profile_surface_recorded) &&
                Bool(reporting.summary.no_single_threshold_profile_promoted) &&
                Bool(reporting.summary.no_public_fit_metric_claim),
            evidence_role = :supplies_threshold_profile_diagnostic_constraint),
    ]
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_validation_split_model_comparison_policy.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    heldout =
        record_by_name(records, :mgmfrm_heldout_prediction_validation_policy)
    prediction =
        record_by_name(records, :prediction_target_and_model_weight_policy)
    qcv = record_by_name(records, :mgmfrm_q_revision_cross_validation_policy)
    reporting =
        record_by_name(records, :mgmfrm_construct_reviewed_q_fit_reporting_policy)

    splits = split_policy_rows()
    models = comparison_model_rows()
    metrics = metric_rows()
    leakage_guards = leakage_guard_rows()
    claim_rules = claim_rule_rows()
    links = evidence_link_rows(heldout, prediction, qcv, reporting)
    no_publication = no_publication_commands()

    all_input_artifacts_present = all(record -> record.exists, records)
    all_expected_schemas = all(record -> record.schema_matches, records)
    all_input_summaries_passed = all(record -> record.summary_passed, records)
    heldout_policy_next_gate_matched =
        heldout.summary.next_gate ==
            "heldout_mgmfrm_prediction_or_external_validation_study"
    primary_holdout_target_selected =
        Bool(prediction.summary.heldout_kfold_selected) &&
        prediction.summary.primary_prediction_target ==
            "heldout_observation_log_score"
    split_policy_recorded =
        any(row -> Bool(row.selected_for_first_execution), splits) &&
        all(row -> Bool(row.leakage_guard_required), splits)
    comparison_model_set_recorded =
        all(row -> Bool(row.included), models) &&
        length(models) >= 4
    all_metrics_predeclared =
        all(row -> Bool(row.public_claim_requires_execution), metrics)
    all_leakage_guards_recorded =
        all(row -> Bool(row.requirement_recorded) &&
            Bool(row.public_claim_blocked_if_unsatisfied), leakage_guards)
    all_evidence_links_satisfied = all(row -> Bool(row.link_satisfied), links)
    all_claim_rules_block_public_claims =
        all(row -> !Bool(row.public_claim_allowed), claim_rules)
    same_data_fit_metrics_diagnostic_only =
        Bool(heldout.summary.same_data_waic_claim_blocked) &&
        Bool(heldout.summary.raw_psis_loo_claim_blocked) &&
        Bool(reporting.summary.no_single_threshold_profile_promoted)
    no_public_fit_metric_claim =
        Bool(heldout.summary.no_public_fit_metric_claim) &&
        Bool(reporting.summary.no_public_fit_metric_claim)
    no_public_q_revision_claim =
        Bool(heldout.summary.no_public_q_revision_claim) &&
        Bool(qcv.summary.no_public_q_revision_claim) &&
        Bool(reporting.summary.no_public_q_revision_claim)
    no_automatic_q_revision =
        Bool(heldout.summary.no_automatic_q_revision) &&
        Bool(qcv.summary.no_automatic_q_revision) &&
        Bool(reporting.summary.no_automatic_q_revision)
    no_model_weight_or_sparse_superiority_claim =
        Bool(heldout.summary.no_model_weight_or_sparse_superiority_claim) &&
        !Bool(prediction.summary.public_model_weight_claims_allowed) &&
        !Bool(prediction.summary.mgmfrm_weight_claims_allowed) &&
        !Bool(prediction.summary.manuscript_sparse_mgmfrm_claims_allowed)
    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        heldout_policy_next_gate_matched &&
        primary_holdout_target_selected &&
        split_policy_recorded &&
        comparison_model_set_recorded &&
        all_metrics_predeclared &&
        all_leakage_guards_recorded &&
        all_evidence_links_satisfied &&
        all_claim_rules_block_public_claims &&
        same_data_fit_metrics_diagnostic_only &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_automatic_q_revision &&
        no_model_weight_or_sparse_superiority_claim &&
        no_publication
    remaining_public_blockers = [
        :heldout_split_execution_missing,
        :heldout_model_comparison_results_missing,
        :external_construct_validation_missing,
    ]

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_validation_split_model_comparison_policy.v1",
        family = :mgmfrm,
        scope = :validation_split_model_comparison_policy,
        status = :validation_split_model_comparison_policy_recorded,
        decision =
            :predeclare_heldout_split_and_model_comparison_before_validation_study,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        heldout_validation_study_completed = false,
        external_construct_validation_completed = false,
        publication_or_registration_action = false,
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
        input_artifacts = records,
        split_policy_rows = splits,
        comparison_model_rows = models,
        metric_rows = metrics,
        leakage_guard_rows = leakage_guards,
        claim_rule_rows = claim_rules,
        evidence_link_rows = links,
        decision_record = (;
            selected_decision =
                :predeclare_heldout_split_and_model_comparison_before_validation_study,
            split_policy_recorded,
            comparison_model_set_recorded,
            primary_split = :observation_kfold,
            primary_prediction_target = :heldout_observation_log_score,
            heldout_validation_study_completed = false,
            external_construct_validation_completed = false,
            same_data_fit_metrics_diagnostic_only,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            required_followup = :heldout_mgmfrm_prediction_simulation_grid,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            heldout_policy_next_gate_matched,
            heldout_prediction_validation_policy_passed =
                heldout.summary_passed,
            prediction_target_and_model_weight_policy_passed =
                prediction.summary_passed,
            mgmfrm_q_revision_cross_validation_policy_passed =
                qcv.summary_passed,
            mgmfrm_construct_reviewed_q_fit_reporting_policy_passed =
                reporting.summary_passed,
            primary_holdout_target_selected,
            split_policy_recorded,
            comparison_model_set_recorded,
            all_metrics_predeclared,
            all_leakage_guards_recorded,
            all_evidence_links_satisfied,
            all_claim_rules_block_public_claims,
            same_data_fit_metrics_diagnostic_only,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_automatic_q_revision,
            no_model_weight_or_sparse_superiority_claim,
            heldout_validation_study_completed = false,
            external_construct_validation_completed = false,
            validation_execution_required = true,
            n_input_artifacts = length(records),
            n_split_policy_rows = length(splits),
            n_comparison_model_rows = length(models),
            n_metric_rows = length(metrics),
            n_leakage_guard_rows = length(leakage_guards),
            n_claim_rule_rows = length(claim_rules),
            n_evidence_link_rows = length(links),
            n_validation_split_policy_cells =
                length(splits) + length(models) + length(metrics) +
                length(leakage_guards) + length(claim_rules) + length(links),
            n_unmet_public_claim_requirements =
                length(remaining_public_blockers),
            n_blockers = length(remaining_public_blockers),
            remaining_public_blockers,
            recommendation =
                :run_predeclared_heldout_prediction_simulation_or_external_validation,
            next_gate = :heldout_mgmfrm_prediction_simulation_grid,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " split_policy_cells=",
        artifact.summary.n_validation_split_policy_cells,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
