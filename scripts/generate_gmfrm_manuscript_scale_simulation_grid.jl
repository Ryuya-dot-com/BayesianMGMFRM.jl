#!/usr/bin/env julia

using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "gmfrm_manuscript_scale_simulation_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :experimental_fit_validation_grid,
        path = "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_experimental_fit_validation_grid.v1",
        hash_policy = :sha256),
    (name = :posterior_predictive_grid,
        path = "test/fixtures/gmfrm_posterior_predictive_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_posterior_predictive_grid.v1",
        hash_policy = :sha256),
    (name = :sparse_pathology_recovery_grid,
        path = "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_sparse_pathology_recovery_grid.v1",
        hash_policy = :sha256),
    (name = :prior_likelihood_sensitivity_grid,
        path = "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_prior_likelihood_sensitivity_grid.v1",
        hash_policy = :sha256),
    (name = :real_data_case_study,
        path = "test/fixtures/gmfrm_real_data_case_study.json",
        expected_schema = "bayesianmgmfrm.gmfrm_real_data_case_study.v1",
        hash_policy = :sha256),
    (name = :claim_recovery_reproduction_archive,
        path = "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_claim_recovery_reproduction_archive.v1",
        hash_policy =
            :existence_only_avoids_dry_run_claim_manuscript_grid_cycle),
    (name = :broader_experimental_exposure_decision_review,
        path =
            "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_broader_experimental_exposure_decision_review.v1",
        hash_policy =
            :existence_only_avoids_broader_review_manuscript_grid_cycle),
    (name = :prediction_target_and_model_weight_policy,
        path =
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_prediction_target_and_model_weight_policy.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_manual_public_scope_review_for_fit,
        path =
            "test/fixtures/mgmfrm_manual_public_scope_review_for_fit.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_manual_public_scope_review_for_fit.v1",
        hash_policy = :sha256),
    (name = :dff_estimand_validation_grid,
        path = "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_dff_estimand_validation_grid.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_sparse_recovery_grid,
        path = "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_sparse_recovery_grid.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_empirical_q_matrix_recovery_simulation_grid,
        path =
            "test/fixtures/mgmfrm_empirical_q_matrix_recovery_simulation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_empirical_q_matrix_recovery_simulation_grid.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_q_candidate_real_fit_diagnostic_linkage,
        path =
            "test/fixtures/mgmfrm_q_candidate_real_fit_diagnostic_linkage.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_candidate_real_fit_diagnostic_linkage.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_q_revision_cross_validation_policy,
        path =
            "test/fixtures/mgmfrm_q_revision_cross_validation_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_revision_cross_validation_policy.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_q_revision_construct_validity_review,
        path =
            "test/fixtures/mgmfrm_q_revision_construct_validity_review.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_revision_construct_validity_review.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_guarded_local_fit_entrypoint,
        path =
            "test/fixtures/mgmfrm_guarded_local_fit_entrypoint.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_local_fit_entrypoint.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_fit_metric_threshold_sensitivity,
        path =
            "test/fixtures/mgmfrm_fit_metric_threshold_sensitivity.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_fit_metric_threshold_sensitivity.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_construct_reviewed_q_fit_reporting_policy,
        path =
            "test/fixtures/mgmfrm_construct_reviewed_q_fit_reporting_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_construct_reviewed_q_fit_reporting_policy.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_heldout_prediction_validation_policy,
        path =
            "test/fixtures/mgmfrm_heldout_prediction_validation_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_heldout_prediction_validation_policy.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_validation_split_model_comparison_policy,
        path =
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_validation_split_model_comparison_policy.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_heldout_prediction_simulation_grid,
        path =
            "test/fixtures/mgmfrm_heldout_prediction_simulation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_heldout_prediction_simulation_grid.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_heldout_prediction_execution,
        path =
            "test/fixtures/mgmfrm_heldout_prediction_execution.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_heldout_prediction_execution.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_full_heldout_refit_or_construct_validation_review,
        path =
            "test/fixtures/mgmfrm_full_heldout_refit_or_construct_validation_review.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_refit_or_construct_validation_review.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_full_heldout_mcmc_refit_execution_plan,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_execution_plan.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_full_heldout_mcmc_refit_batch_smoke,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_batch_smoke.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_batch_smoke.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_full_heldout_mcmc_refit_fold1_pilot,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_fold1_pilot.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_fold1_pilot.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_full_heldout_mcmc_refit_fold1_scoring,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_fold1_scoring.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_fold1_scoring.v1",
        hash_policy = :sha256),
    (name = :mgmfrm_fit_threshold_q_heldout_linkage,
        path =
            "test/fixtures/mgmfrm_fit_threshold_q_heldout_linkage.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_fit_threshold_q_heldout_linkage.v1",
        hash_policy = :sha256),
    (name = :full_paper_reproduction_archive,
        path = "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_full_paper_reproduction_archive.v1",
        hash_policy = :sha256),
]

const PROTOCOL = (;
    protocol_id = "gmfrm_manuscript_scale_simulation_grid_v1",
    review_kind = :local_manuscript_scale_simulation_evidence_grid,
    publication_or_registration_action = false,
    local_only = true,
    decision_target = :gate_e_broader_generalized_claim_evidence,
    evidence_policy = (;
        rerun_policy = :aggregate_versioned_local_simulation_artifacts,
        public_claim_policy =
            :do_not_make_manuscript_claims_until_full_archive_exists,
        dff_policy = :validation_only_no_fitted_dff_effects,
    ),
    thresholds = (;
        require_all_input_artifacts_present = true,
        require_all_expected_schemas = true,
        require_all_input_summaries_passed = true,
        require_scalar_fit_validation_grid_passed = true,
        require_posterior_predictive_grid_passed = true,
        require_sparse_pathology_recovery_grid_passed = true,
        require_prior_likelihood_sensitivity_grid_passed = true,
        require_real_data_case_study_passed = true,
        require_claim_archive_recorded = true,
        require_broader_review_passed = true,
        require_prediction_target_and_model_weight_policy_passed = true,
        require_mgmfrm_manual_public_scope_review_for_fit_passed = true,
        require_dff_validation_grid_passed = true,
        require_mgmfrm_sparse_recovery_grid_passed = true,
        require_mgmfrm_empirical_q_matrix_recovery_simulation_grid_passed =
            true,
        require_mgmfrm_q_candidate_real_fit_diagnostic_linkage_passed = true,
        require_mgmfrm_q_revision_cross_validation_policy_passed = true,
        require_mgmfrm_q_revision_construct_validity_review_passed = true,
        require_mgmfrm_guarded_local_fit_entrypoint_passed = true,
        require_mgmfrm_fit_metric_threshold_sensitivity_passed = true,
        require_mgmfrm_construct_reviewed_q_fit_reporting_policy_passed = true,
        require_mgmfrm_heldout_prediction_validation_policy_passed = true,
        require_mgmfrm_validation_split_model_comparison_policy_passed =
            true,
        require_mgmfrm_heldout_prediction_simulation_grid_passed = true,
        require_mgmfrm_heldout_prediction_execution_passed = true,
        require_mgmfrm_full_heldout_refit_or_construct_validation_review_passed =
            true,
        require_mgmfrm_full_heldout_mcmc_refit_execution_plan_passed =
            true,
        require_mgmfrm_full_heldout_mcmc_refit_batch_smoke_passed =
            true,
        require_mgmfrm_full_heldout_mcmc_refit_fold1_pilot_passed =
            true,
        require_mgmfrm_full_heldout_mcmc_refit_fold1_scoring_passed =
            true,
        require_mgmfrm_fit_threshold_q_heldout_linkage_passed = true,
        require_full_paper_reproduction_archive_passed = true,
        require_minimum_total_evidence_cells = 60,
        require_no_publication_commands = true,
        require_full_archive_before_claims = false,
    ),
)

const BLOCKER_ROWS = NamedTuple[]

function usage()
    return """
    Generate the local Gate E manuscript-scale simulation evidence grid.

    The artifact aggregates already versioned local GMFRM/MGMFRM simulation,
    recovery, sensitivity, real-data, and DFF validation artifacts. It does not
    publish, register, enable broader generalized fitting, or make manuscript
    claims. Full paper reproduction archives remain required.

    Usage:
      julia --project=. scripts/generate_gmfrm_manuscript_scale_simulation_grid.jl [--output PATH]
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

file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
fixture_path(relpath::AbstractString) = joinpath(ROOT, relpath)
read_fixture_text(relpath::AbstractString) = read(fixture_path(relpath), String)

function parse_json_string_literal(chars::Vector{Char}, index::Int)
    chars[index] == '"' || error("expected JSON string at character $index")
    io = IOBuffer()
    escaped = false
    index += 1
    while index <= length(chars)
        char = chars[index]
        if escaped
            if char == '"' || char == '\\' || char == '/'
                print(io, char)
            elseif char == 'n'
                print(io, '\n')
            elseif char == 'r'
                print(io, '\r')
            elseif char == 't'
                print(io, '\t')
            else
                error("unsupported JSON escape sequence \\$char")
            end
            escaped = false
        elseif char == '\\'
            escaped = true
        elseif char == '"'
            return String(take!(io)), index + 1
        else
            print(io, char)
        end
        index += 1
    end
    error("unterminated JSON string")
end

function skip_ws(chars::Vector{Char}, index::Int)
    while index <= length(chars) && chars[index] in (' ', '\n', '\r', '\t')
        index += 1
    end
    return index
end

function json_value_end(chars::Vector{Char}, index::Int)
    index = skip_ws(chars, index)
    depth = 0
    in_string = false
    escaped = false
    while index <= length(chars)
        char = chars[index]
        if in_string
            if escaped
                escaped = false
            elseif char == '\\'
                escaped = true
            elseif char == '"'
                in_string = false
            end
        elseif char == '"'
            in_string = true
        elseif char == '{' || char == '['
            depth += 1
        elseif char == '}' || char == ']'
            depth == 0 && return index - 1
            depth -= 1
        elseif char == ',' && depth == 0
            return index - 1
        end
        index += 1
    end
    return length(chars)
end

function json_value_for_key(text::AbstractString, key::AbstractString)
    chars = collect(text)
    index = skip_ws(chars, 1)
    chars[index] == '{' || error("expected JSON object")
    index += 1
    while index <= length(chars)
        index = skip_ws(chars, index)
        index > length(chars) && break
        chars[index] == '}' && break
        parsed_key, index = parse_json_string_literal(chars, index)
        index = skip_ws(chars, index)
        chars[index] == ':' || error("expected ':' after JSON key $parsed_key")
        index = skip_ws(chars, index + 1)
        value_start = index
        value_stop = json_value_end(chars, value_start)
        parsed_key == key && return strip(String(chars[value_start:value_stop]))
        index = skip_ws(chars, value_stop + 1)
        if index <= length(chars) && chars[index] == ','
            index += 1
        end
    end
    return nothing
end

function required_value(text::AbstractString, key::AbstractString)
    value = json_value_for_key(text, key)
    value === nothing && error("JSON field `$key` not found")
    return value
end

function json_string(text::AbstractString, key::AbstractString)
    parsed, next_index =
        parse_json_string_literal(collect(required_value(text, key)), 1)
    next_index == length(collect(required_value(text, key))) + 1 ||
        error("JSON field `$key` is not a string literal")
    return parsed
end

json_int(text::AbstractString, key::AbstractString) =
    parse(Int, required_value(text, key))

function json_bool(text::AbstractString, key::AbstractString)
    value = required_value(text, key)
    value == "true" && return true
    value == "false" && return false
    error("JSON field `$key` is not boolean")
end

function json_optional_bool(text::AbstractString, key::AbstractString)
    value = json_value_for_key(text, key)
    value === nothing && return missing
    value == "null" && return missing
    value == "true" && return true
    value == "false" && return false
    error("JSON field `$key` is not boolean or null")
end

json_summary(text::AbstractString) = required_value(text, "summary")

function summary_passed(summary::AbstractString)
    passed = json_value_for_key(summary, "passed")
    passed !== nothing && return passed == "true"
    overall = json_value_for_key(summary, "overall_passed")
    overall !== nothing && return overall == "true"
    return false
end

function artifact_summary(name::Symbol, summary::AbstractString)
    name === :experimental_fit_validation_grid && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_scenarios"),
        key_check = :guarded_fit_validation,
        all_primary_checks =
            json_bool(summary, "all_guarded_fit_returned") &&
            json_bool(summary, "all_artifact_contracts_satisfied") &&
            json_bool(summary, "all_information_criteria_finite"),
    )
    name === :posterior_predictive_grid && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_scenarios"),
        key_check = :posterior_predictive_calibration,
        all_primary_checks =
            json_bool(summary, "all_ppc_returned") &&
            json_bool(summary, "all_probability_sums_valid") &&
            json_bool(summary, "all_summary_rows_finite"),
    )
    name === :sparse_pathology_recovery_grid && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_scenarios"),
        key_check = :sparse_pathology_recovery,
        all_primary_checks =
            json_bool(summary, "all_validations_passed") &&
            json_bool(summary, "all_guarded_fit_returned") &&
            json_bool(summary, "all_ppc_returned"),
    )
    name === :prior_likelihood_sensitivity_grid && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_sensitivity_cells"),
        key_check = :prior_likelihood_sensitivity,
        all_primary_checks =
            json_bool(summary, "all_cells_finite") &&
            json_bool(summary, "all_baseline_identity"),
    )
    name === :real_data_case_study && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_cases"),
        key_check = :compact_real_data_case_study,
        all_primary_checks =
            json_bool(summary, "all_guarded_fit_returned") &&
            json_bool(summary, "all_baseline_fits_returned") &&
            json_bool(summary, "all_ppc_returned"),
    )
    name === :claim_recovery_reproduction_archive && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_fixture_artifacts"),
        key_check = :claim_level_reproduction_archive,
        all_primary_checks =
            json_bool(summary, "all_fixture_artifacts_present") &&
            json_bool(summary, "all_commands_local_only") &&
            json_bool(summary, "no_publication_commands"),
    )
    name === :broader_experimental_exposure_decision_review && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_input_artifacts"),
        key_check = :broader_exposure_decision,
        all_primary_checks =
            json_bool(summary, "scalar_guarded_fit_allowed") &&
            !json_bool(summary, "broader_generalized_fit_allowed") &&
            !json_bool(summary, "manuscript_claims_allowed"),
    )
    name === :prediction_target_and_model_weight_policy && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells =
            json_int(summary, "n_prediction_target_rows") +
            json_int(summary, "n_model_weight_policy_rows"),
        key_check = :prediction_target_and_model_weight_policy,
        all_primary_checks =
            json_bool(summary, "policy_recorded") &&
            json_bool(summary, "heldout_kfold_selected") &&
            json_bool(summary, "same_data_waic_blocked") &&
            json_bool(summary, "raw_psis_loo_blocked") &&
            json_bool(summary, "mgmfrm_fit_allowed") &&
            !json_bool(summary, "manuscript_sparse_mgmfrm_claims_allowed"),
    )
    name === :mgmfrm_manual_public_scope_review_for_fit && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells =
            json_int(summary, "n_scope_decisions") +
            json_int(summary, "n_risk_rows"),
        key_check = :mgmfrm_manual_public_scope_review_for_fit,
        all_primary_checks =
            json_bool(summary, "manual_public_scope_review_satisfied") &&
            json_bool(summary, "local_guarded_fit_development_allowed") &&
            json_bool(summary, "public_fit_allowed") &&
            json_bool(summary, "mgmfrm_fit_allowed"),
    )
    name === :dff_estimand_validation_grid && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_scenarios"),
        key_check = :dff_validation_only_grid,
        all_primary_checks =
            json_bool(summary, "all_estimands_predeclared") &&
            json_bool(summary, "all_valid_dff_terms_retained_as_validation_only") &&
            !json_bool(summary, "dff_model_effects_allowed"),
    )
    name === :mgmfrm_sparse_recovery_grid && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_scenarios"),
        key_check = :confirmatory_mgmfrm_sparse_recovery,
        all_primary_checks =
            json_bool(summary, "all_validations_passed") &&
            json_bool(summary, "all_sampler_passed") &&
            !json_bool(summary, "public_fit_allowed"),
    )
    name === :mgmfrm_empirical_q_matrix_recovery_simulation_grid && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_scenarios"),
        key_check = :mgmfrm_empirical_q_matrix_recovery_simulation,
        all_primary_checks =
            json_bool(summary, "all_scenarios_passed") &&
            json_bool(summary, "all_candidate_validations_checked") &&
            json_bool(summary, "false_public_promotion_rate_zero") &&
            json_bool(summary, "q_matrix_reference_records_recorded") &&
            !json_bool(summary, "empirical_q_recovery_allowed"),
    )
    name === :mgmfrm_q_candidate_real_fit_diagnostic_linkage && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_scenarios"),
        key_check = :mgmfrm_q_candidate_real_fit_diagnostic_linkage,
        all_primary_checks =
            json_bool(summary, "all_linkage_scenarios_checked") &&
            json_bool(summary, "all_fit_attempts_succeeded") &&
            json_bool(summary, "all_fit_terms_finite") &&
            json_bool(summary, "invalid_candidates_blocked_before_fit") &&
            json_bool(summary, "no_public_q_revision_claim"),
    )
    name === :mgmfrm_q_revision_cross_validation_policy && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_scenarios"),
        key_check = :mgmfrm_q_revision_cross_validation_policy,
        all_primary_checks =
            json_bool(summary, "all_policy_scenarios_checked") &&
            json_bool(summary, "all_cv_eligible_candidates_have_fold_rows") &&
            json_bool(summary, "false_positive_candidate_rejected") &&
            json_bool(summary, "supported_candidates_remain_manual_review_only") &&
            json_bool(summary, "no_public_q_revision_claim"),
    )
    name === :mgmfrm_q_revision_construct_validity_review && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_construct_review_rows"),
        key_check = :mgmfrm_q_revision_construct_validity_review,
        all_primary_checks =
            json_bool(summary, "all_supported_candidates_reviewed") &&
            json_bool(summary, "all_construct_map_evidence_recorded") &&
            json_bool(summary, "reviewer_agreement_recorded") &&
            json_bool(summary, "supported_candidates_remain_manual_local_only") &&
            json_bool(summary, "no_public_q_revision_claim"),
    )
    name === :mgmfrm_guarded_local_fit_entrypoint && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_fit_entrypoint_rows"),
        key_check = :mgmfrm_guarded_local_fit_entrypoint,
        all_primary_checks =
            json_bool(summary, "all_candidate_q_validations_passed") &&
            json_bool(summary, "all_guarded_fit_attempts_succeeded") &&
            json_bool(summary, "fit_outputs_finite") &&
            json_bool(summary, "all_candidates_remain_manual_local_only") &&
            json_bool(summary, "no_public_q_revision_claim"),
    )
    name === :mgmfrm_fit_metric_threshold_sensitivity && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_fit_metric_evidence_cells"),
        key_check = :mgmfrm_fit_metric_threshold_sensitivity,
        all_primary_checks =
            json_bool(summary, "all_mgmfrm_fit_pairs_succeeded") &&
            json_bool(summary, "all_fit_metric_values_finite") &&
            json_bool(summary, "mfrm_baseline_mean_square_recorded") &&
            json_bool(summary, "existing_model_comparison_recorded") &&
            json_bool(summary, "parameter_shift_recorded") &&
            json_bool(summary, "no_public_fit_metric_claim") &&
            json_bool(summary, "no_public_q_revision_claim"),
    )
    name === :mgmfrm_construct_reviewed_q_fit_reporting_policy && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_reporting_evidence_cells"),
        key_check = :mgmfrm_construct_reviewed_q_fit_reporting_policy,
        all_primary_checks =
            json_bool(summary, "threshold_profile_surface_recorded") &&
            json_bool(summary, "indicator_conflicts_recorded") &&
            json_bool(summary, "existing_model_reference_recorded") &&
            json_bool(summary, "parameter_shift_impact_recorded") &&
            json_bool(summary, "all_policy_rows_block_public_claims") &&
            json_bool(summary, "no_public_fit_metric_claim") &&
            json_bool(summary, "no_public_q_revision_claim"),
    )
    name === :mgmfrm_heldout_prediction_validation_policy && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_validation_policy_cells"),
        key_check = :mgmfrm_heldout_prediction_validation_policy,
        all_primary_checks =
            json_bool(summary, "heldout_or_external_validation_required") &&
            json_bool(summary,
                "heldout_kfold_selected_from_scalar_policy") &&
            json_bool(summary,
                "external_construct_validation_required_for_q_claims") &&
            json_bool(summary, "same_data_waic_claim_blocked") &&
            json_bool(summary, "raw_psis_loo_claim_blocked") &&
            json_bool(summary, "all_claim_gate_rows_block_public_claims") &&
            json_bool(summary, "no_public_fit_metric_claim") &&
            json_bool(summary, "no_public_q_revision_claim") &&
            json_bool(summary, "no_automatic_q_revision"),
    )
    name === :mgmfrm_validation_split_model_comparison_policy && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells =
            json_int(summary, "n_validation_split_policy_cells"),
        key_check = :mgmfrm_validation_split_model_comparison_policy,
        all_primary_checks =
            json_bool(summary, "primary_holdout_target_selected") &&
            json_bool(summary, "split_policy_recorded") &&
            json_bool(summary, "comparison_model_set_recorded") &&
            json_bool(summary, "all_metrics_predeclared") &&
            json_bool(summary, "all_leakage_guards_recorded") &&
            json_bool(summary, "all_claim_rules_block_public_claims") &&
            json_bool(summary, "same_data_fit_metrics_diagnostic_only") &&
            json_bool(summary, "no_public_fit_metric_claim") &&
            json_bool(summary, "no_public_q_revision_claim") &&
            json_bool(summary,
                "no_model_weight_or_sparse_superiority_claim"),
    )
    name === :mgmfrm_heldout_prediction_simulation_grid && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_heldout_simulation_grid_cells"),
        key_check = :mgmfrm_heldout_prediction_simulation_grid,
        all_primary_checks =
            json_bool(summary, "predeclared_splits_carried_forward") &&
            json_bool(summary, "all_comparison_models_planned") &&
            json_bool(summary, "all_scenarios_predeclared") &&
            json_bool(summary, "all_metric_surface_values_finite") &&
            json_bool(summary, "threshold_impact_rows_recorded") &&
            json_bool(summary, "leakage_guards_carried_forward") &&
            json_bool(summary, "all_claim_rules_block_public_claims") &&
            json_bool(summary, "no_public_fit_metric_claim") &&
            json_bool(summary, "no_public_model_weight_claim") &&
            json_bool(summary, "no_sparse_superiority_claim") &&
            !json_bool(summary, "heldout_prediction_execution_completed"),
    )
    name === :mgmfrm_heldout_prediction_execution && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_observed_metric_cells"),
        key_check = :mgmfrm_heldout_prediction_execution,
        all_primary_checks =
            json_bool(summary, "heldout_prediction_execution_completed") &&
            json_bool(summary, "observed_heldout_results_recorded") &&
            json_bool(summary, "fold_assignments_materialized") &&
            json_bool(summary, "all_observations_held_out_once") &&
            json_bool(summary, "observed_metric_rows_recorded") &&
            json_bool(summary, "all_observed_metric_values_finite") &&
            json_bool(summary, "rank_stability_review_recorded") &&
            json_bool(summary,
                "threshold_profile_observed_rows_recorded") &&
            json_bool(summary, "model_weight_rows_recorded") &&
            json_bool(summary, "all_claim_rules_block_public_claims") &&
            json_bool(summary, "no_public_fit_metric_claim") &&
            json_bool(summary, "no_public_model_weight_claim") &&
            json_bool(summary, "no_sparse_superiority_claim") &&
            !json_bool(summary, "mcmc_refit_execution_completed") &&
            json_bool(summary, "full_refit_execution_required"),
    )
    name === :mgmfrm_full_heldout_refit_or_construct_validation_review && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_review_cells"),
        key_check =
            :mgmfrm_full_heldout_refit_or_construct_validation_review,
        all_primary_checks =
            json_bool(summary, "refit_or_external_validation_review_completed") &&
            json_bool(summary, "heldout_prediction_execution_completed") &&
            json_bool(summary, "full_mcmc_refit_required") &&
            json_bool(summary, "observed_metric_cells_recorded") &&
            json_bool(summary, "rank_instability_carried_forward") &&
            json_bool(summary,
                "external_construct_validation_requirements_recorded") &&
            json_bool(summary, "refit_execution_plan_recorded") &&
            json_bool(summary, "all_claim_rules_block_public_claims") &&
            json_bool(summary, "no_public_fit_metric_claim") &&
            json_bool(summary, "no_public_model_weight_claim") &&
            json_bool(summary, "no_sparse_superiority_claim") &&
            !json_bool(summary, "full_mcmc_refit_execution_completed") &&
            !json_bool(summary, "external_construct_validation_completed"),
    )
    name === :mgmfrm_full_heldout_mcmc_refit_execution_plan && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_review_cells"),
        key_check = :mgmfrm_full_heldout_mcmc_refit_execution_plan,
        all_primary_checks =
            json_bool(summary, "full_mcmc_refit_execution_plan_recorded") &&
            json_bool(summary, "full_mcmc_refit_required") &&
            json_bool(summary,
                "all_scenario_model_fold_units_materialized") &&
            json_bool(summary, "diagnostic_thresholds_recorded") &&
            json_bool(summary, "execution_budget_recorded") &&
            json_bool(summary,
                "external_construct_dataset_review_recorded") &&
            json_bool(summary, "all_claim_rules_block_public_claims") &&
            json_bool(summary, "no_public_fit_metric_claim") &&
            json_bool(summary, "no_public_model_weight_claim") &&
            json_bool(summary, "no_sparse_superiority_claim") &&
            !json_bool(summary, "full_mcmc_refit_execution_completed") &&
            !json_bool(summary, "external_construct_dataset_attached"),
    )
    name === :mgmfrm_full_heldout_mcmc_refit_batch_smoke && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_review_cells"),
        key_check = :mgmfrm_full_heldout_mcmc_refit_batch_smoke,
        all_primary_checks =
            json_bool(summary, "representative_batch_smoke_completed") &&
            json_bool(summary, "representative_units_selected") &&
            json_bool(summary, "smoke_fit_attempts_succeeded") &&
            json_bool(summary, "smoke_outputs_finite") &&
            json_bool(summary, "training_pointwise_loglikelihood_recorded") &&
            json_bool(summary, "publication_grade_diagnostics_blocked") &&
            json_bool(summary, "full_125_unit_batch_not_claimed") &&
            json_bool(summary,
                "heldout_predictive_scores_blocked_until_full_batch") &&
            json_bool(summary, "external_construct_dataset_still_required") &&
            json_bool(summary, "no_public_fit_metric_claim") &&
            json_bool(summary, "no_public_q_revision_claim") &&
            json_bool(summary, "no_public_model_weight_claim") &&
            json_bool(summary, "no_sparse_superiority_claim") &&
            !json_bool(summary, "full_mcmc_refit_execution_completed") &&
            !json_bool(summary, "full_125_unit_batch_completed") &&
            !json_bool(summary, "heldout_predictive_scores_computed") &&
            !json_bool(summary, "external_construct_dataset_attached") &&
            !json_bool(summary, "external_construct_validation_completed"),
    )
    name === :mgmfrm_full_heldout_mcmc_refit_fold1_pilot && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_review_cells"),
        key_check = :mgmfrm_full_heldout_mcmc_refit_fold1_pilot,
        all_primary_checks =
            json_bool(summary, "fold1_pilot_completed") &&
            json_bool(summary, "fold1_units_selected") &&
            json_bool(summary, "all_scenarios_covered") &&
            json_bool(summary, "all_models_recorded") &&
            json_bool(summary,
                "mgmfrm_candidate_fit_attempts_succeeded") &&
            json_bool(summary, "mgmfrm_candidate_outputs_finite") &&
            json_bool(summary, "q_validations_passed") &&
            json_bool(summary, "training_pointwise_loglikelihood_recorded") &&
            json_bool(summary, "publication_grade_diagnostics_blocked") &&
            json_bool(summary,
                "comparison_anchors_recorded_not_claimed") &&
            json_bool(summary, "full_125_unit_batch_not_claimed") &&
            json_bool(summary,
                "heldout_predictive_scores_blocked_until_full_batch") &&
            json_bool(summary, "external_construct_dataset_still_required") &&
            json_bool(summary, "no_public_fit_metric_claim") &&
            json_bool(summary, "no_public_q_revision_claim") &&
            json_bool(summary, "no_public_model_weight_claim") &&
            json_bool(summary, "no_sparse_superiority_claim") &&
            !json_bool(summary, "full_mcmc_refit_execution_completed") &&
            !json_bool(summary, "full_125_unit_batch_completed") &&
            !json_bool(summary, "heldout_predictive_scores_computed") &&
            !json_bool(summary, "external_construct_dataset_attached") &&
            !json_bool(summary, "external_construct_validation_completed"),
    )
    name === :mgmfrm_full_heldout_mcmc_refit_fold1_scoring && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_review_cells"),
        key_check = :mgmfrm_full_heldout_mcmc_refit_fold1_scoring,
        all_primary_checks =
            json_bool(summary, "fold1_pilot_completed") &&
            json_bool(summary,
                "fold1_heldout_predictive_scores_computed") &&
            json_bool(summary, "all_candidate_scores_recorded") &&
            json_bool(summary, "all_pointwise_scores_recorded") &&
            json_bool(summary, "all_score_values_finite") &&
            json_bool(summary, "expected_score_residuals_recorded") &&
            json_bool(summary,
                "training_heldout_alignment_rows_recorded") &&
            json_bool(summary, "candidate_rank_rows_recorded") &&
            json_bool(summary, "comparison_anchors_not_scored") &&
            json_bool(summary, "full_125_unit_batch_not_completed") &&
            json_bool(summary, "publication_grade_diagnostics_blocked") &&
            json_bool(summary,
                "full_heldout_scores_blocked_until_full_batch") &&
            json_bool(summary, "no_public_fit_metric_claim") &&
            json_bool(summary, "no_public_q_revision_claim") &&
            json_bool(summary, "no_public_model_weight_claim") &&
            json_bool(summary, "no_sparse_superiority_claim") &&
            json_bool(summary, "heldout_predictive_scores_computed") &&
            !json_bool(summary, "full_mcmc_refit_execution_completed") &&
            !json_bool(summary, "full_125_unit_batch_completed") &&
            !json_bool(summary, "full_heldout_predictive_scores_computed") &&
            !json_bool(summary, "comparison_anchor_scores_computed") &&
            !json_bool(summary, "external_construct_dataset_attached") &&
            !json_bool(summary, "external_construct_validation_completed"),
    )
    name === :mgmfrm_fit_threshold_q_heldout_linkage && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells =
            json_int(summary, "n_scenario_link_rows") +
            json_int(summary, "n_threshold_profile_link_rows") +
            json_int(summary, "n_q_recovery_link_rows") +
            json_int(summary, "n_parameter_absorption_rows"),
        key_check = :mgmfrm_fit_threshold_q_heldout_linkage,
        all_primary_checks =
            json_bool(summary, "all_scenario_link_rows_recorded") &&
            json_bool(summary, "threshold_profile_link_rows_recorded") &&
            json_bool(summary, "q_recovery_link_rows_recorded") &&
            json_bool(summary, "parameter_absorption_rows_recorded") &&
            json_bool(summary, "fold1_observed_rank_recorded") &&
            json_bool(summary, "observed_vs_expected_rank_match_recorded") &&
            json_bool(summary, "any_observed_expected_mismatch_flagged") &&
            json_bool(summary, "anchor_limitations_recorded") &&
            json_bool(summary, "no_single_threshold_profile_promoted") &&
            json_bool(summary, "no_automatic_q_revision") &&
            json_bool(summary, "no_public_fit_metric_claim") &&
            json_bool(summary, "no_public_q_revision_claim") &&
            json_bool(summary, "no_public_model_weight_claim") &&
            json_bool(summary, "no_sparse_superiority_claim"),
    )
    name === :full_paper_reproduction_archive && return (;
        passed = json_bool(summary, "passed"),
        n_evidence_cells = json_int(summary, "n_fixture_artifacts"),
        key_check = :full_paper_reproduction_archive,
        all_primary_checks =
            json_bool(summary, "all_fixture_artifacts_present") &&
            json_bool(summary, "all_code_doc_references_present") &&
            json_bool(summary, "all_external_sources_present") &&
            json_bool(summary, "all_commands_local_only") &&
            json_bool(summary, "no_publication_commands"),
    )
    return (;
        passed = summary_passed(summary),
        n_evidence_cells = 1,
        key_check = :generic_summary_passed,
        all_primary_checks = summary_passed(summary),
    )
end

function artifact_record(spec)
    path = fixture_path(spec.path)
    exists = isfile(path)
    exists || error("input artifact is missing: $(spec.path)")
    text = read(path, String)
    schema = json_string(text, "schema")
    schema_matches = schema == spec.expected_schema
    summary = artifact_summary(spec.name, json_summary(text))
    should_hash = spec.hash_policy === :sha256
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        schema,
        expected_schema = spec.expected_schema,
        schema_matches,
        summary_passed = summary.passed,
        hash_policy = spec.hash_policy,
        sha256 = should_hash ? file_sha256(path) : missing,
        summary,
    )
end

function evidence_rows(records)
    return [
        (gate = record.artifact,
            status = record.summary_passed && record.summary.all_primary_checks ?
                :passed : :failed,
            n_evidence_cells = record.summary.n_evidence_cells,
            key_check = record.summary.key_check,
            artifact = record.path)
        for record in records
    ]
end

function claim_decision_rows()
    return [
        (claim = :guarded_scalar_gmfrm_fit,
            decision = :local_guarded_experimental_remains_enabled,
            public_claim_allowed = true,
            required_followup = :manual_publication_or_registration_by_user_only),
        (claim = :broader_gmfrm_or_mgmfrm_fit,
            decision = :keep_blocked_until_public_scope_review,
            public_claim_allowed = false,
            required_followup = :broader_generalized_fit_scope_review),
        (claim = :dff_model_effects,
            decision = :keep_validation_only,
            public_claim_allowed = false,
            required_followup = :future_dff_model_effect_fit_policy),
        (claim = :model_weights_or_sparse_mgmfrm_superiority,
            decision =
                :fold1_scoring_recorded_keep_blocked_until_full_batch_or_external_dataset_review,
            public_claim_allowed = false,
            required_followup =
                :full_heldout_mgmfrm_mcmc_refit_full_batch_execution_or_external_construct_dataset_attachment),
    ]
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_gmfrm_manuscript_scale_simulation_grid.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    rows = evidence_rows(input_records)
    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_input_summaries_passed =
        all(record -> record.summary_passed, input_records)
    all_primary_checks_passed =
        all(record -> record.summary.all_primary_checks, input_records)
    total_evidence_cells =
        sum(record.summary.n_evidence_cells for record in input_records)
    no_publication = no_publication_commands()
    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        all_primary_checks_passed &&
        total_evidence_cells >=
            PROTOCOL.thresholds.require_minimum_total_evidence_cells &&
        no_publication
    return (;
        schema = "bayesianmgmfrm.gmfrm_manuscript_scale_simulation_grid.v1",
        family = :gmfrm,
        scope = :manuscript_scale_simulation_grid,
        status = :manuscript_scale_simulation_grid_recorded,
        decision = :full_archive_recorded_keep_guarded_scalar_and_confirmatory_mgmfrm_only,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        broader_public_fit = false,
        manuscript_claims_allowed = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        input_artifacts = input_records,
        evidence_rows = rows,
        claim_decision_rows = claim_decision_rows(),
        blocker_rows = BLOCKER_ROWS,
        decision_record = (;
            selected_decision =
                :full_archive_recorded_keep_guarded_scalar_and_confirmatory_mgmfrm_only,
            scalar_guarded_fit_allowed = true,
            broader_generalized_fit_allowed = false,
            manuscript_claims_allowed = false,
            public_exposure_support =
                :gate_e_and_full_archive_recorded_no_publication_action,
            interpretation =
                :manuscript_scale_grid_recorded_full_archive_available,
            required_followup =
                :full_heldout_mgmfrm_mcmc_refit_full_batch_execution_or_external_construct_dataset_attachment,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            all_primary_checks_passed,
            n_input_artifacts = length(input_records),
            n_evidence_rows = length(rows),
            total_evidence_cells,
            minimum_required_evidence_cells =
                PROTOCOL.thresholds.require_minimum_total_evidence_cells,
            scalar_fit_validation_grid_passed =
                record_by_name(input_records,
                    :experimental_fit_validation_grid).summary_passed,
            posterior_predictive_grid_passed =
                record_by_name(input_records,
                    :posterior_predictive_grid).summary_passed,
            sparse_pathology_recovery_grid_passed =
                record_by_name(input_records,
                    :sparse_pathology_recovery_grid).summary_passed,
            prior_likelihood_sensitivity_grid_passed =
                record_by_name(input_records,
                    :prior_likelihood_sensitivity_grid).summary_passed,
            real_data_case_study_passed =
                record_by_name(input_records, :real_data_case_study).summary_passed,
            claim_recovery_reproduction_archive_passed =
                record_by_name(input_records,
                    :claim_recovery_reproduction_archive).summary_passed,
            broader_experimental_exposure_decision_review_passed =
                record_by_name(input_records,
                    :broader_experimental_exposure_decision_review).summary_passed,
            prediction_target_and_model_weight_policy_passed =
                record_by_name(input_records,
                    :prediction_target_and_model_weight_policy).summary_passed,
            mgmfrm_manual_public_scope_review_for_fit_passed =
                record_by_name(input_records,
                    :mgmfrm_manual_public_scope_review_for_fit).summary_passed,
            dff_estimand_validation_grid_passed =
                record_by_name(input_records,
                    :dff_estimand_validation_grid).summary_passed,
            mgmfrm_sparse_recovery_grid_passed =
                record_by_name(input_records,
                    :mgmfrm_sparse_recovery_grid).summary_passed,
            mgmfrm_empirical_q_matrix_recovery_simulation_grid_passed =
                record_by_name(input_records,
                    :mgmfrm_empirical_q_matrix_recovery_simulation_grid).
                    summary_passed,
            mgmfrm_q_candidate_real_fit_diagnostic_linkage_passed =
                record_by_name(input_records,
                    :mgmfrm_q_candidate_real_fit_diagnostic_linkage).
                    summary_passed,
            mgmfrm_q_revision_cross_validation_policy_passed =
                record_by_name(input_records,
                    :mgmfrm_q_revision_cross_validation_policy).summary_passed,
            mgmfrm_q_revision_construct_validity_review_passed =
                record_by_name(input_records,
                    :mgmfrm_q_revision_construct_validity_review).summary_passed,
            mgmfrm_guarded_local_fit_entrypoint_passed =
                record_by_name(input_records,
                    :mgmfrm_guarded_local_fit_entrypoint).summary_passed,
            mgmfrm_fit_metric_threshold_sensitivity_passed =
                record_by_name(input_records,
                    :mgmfrm_fit_metric_threshold_sensitivity).summary_passed,
            mgmfrm_construct_reviewed_q_fit_reporting_policy_passed =
                record_by_name(input_records,
                    :mgmfrm_construct_reviewed_q_fit_reporting_policy).
                    summary_passed,
            mgmfrm_heldout_prediction_validation_policy_passed =
                record_by_name(input_records,
                    :mgmfrm_heldout_prediction_validation_policy).summary_passed,
            mgmfrm_validation_split_model_comparison_policy_passed =
                record_by_name(input_records,
                    :mgmfrm_validation_split_model_comparison_policy).
                    summary_passed,
            mgmfrm_heldout_prediction_simulation_grid_passed =
                record_by_name(input_records,
                    :mgmfrm_heldout_prediction_simulation_grid).
                    summary_passed,
            mgmfrm_heldout_prediction_execution_passed =
                record_by_name(input_records,
                    :mgmfrm_heldout_prediction_execution).summary_passed,
            mgmfrm_full_heldout_refit_or_construct_validation_review_passed =
                record_by_name(input_records,
                    :mgmfrm_full_heldout_refit_or_construct_validation_review).
                    summary_passed,
            mgmfrm_full_heldout_mcmc_refit_execution_plan_passed =
                record_by_name(input_records,
                    :mgmfrm_full_heldout_mcmc_refit_execution_plan).
                    summary_passed,
            mgmfrm_full_heldout_mcmc_refit_batch_smoke_passed =
                record_by_name(input_records,
                    :mgmfrm_full_heldout_mcmc_refit_batch_smoke).
                    summary_passed,
            mgmfrm_full_heldout_mcmc_refit_fold1_pilot_passed =
                record_by_name(input_records,
                    :mgmfrm_full_heldout_mcmc_refit_fold1_pilot).
                    summary_passed,
            mgmfrm_full_heldout_mcmc_refit_fold1_scoring_passed =
                record_by_name(input_records,
                    :mgmfrm_full_heldout_mcmc_refit_fold1_scoring).
                    summary_passed,
            mgmfrm_fit_threshold_q_heldout_linkage_passed =
                record_by_name(input_records,
                    :mgmfrm_fit_threshold_q_heldout_linkage).
                    summary_passed,
            full_paper_reproduction_archive_passed =
                record_by_name(input_records,
                    :full_paper_reproduction_archive).summary_passed,
            scalar_guarded_fit_allowed = true,
            broader_generalized_fit_allowed = false,
            mgmfrm_fit_allowed = true,
            dff_model_effects_allowed = false,
            manuscript_claims_allowed = false,
            no_publication_commands = no_publication,
            n_blockers = length(BLOCKER_ROWS),
            remaining_public_blockers =
                [row.blocker for row in BLOCKER_ROWS],
            recommendation =
                :manual_scope_review_recorded_keep_broader_claims_blocked,
            next_gate =
                :full_heldout_mgmfrm_mcmc_refit_full_batch_execution_or_external_construct_dataset_attachment,
        ),
    )
end

function record_by_name(records, name::Symbol)
    for record in records
        record.artifact === name && return record
    end
    error("artifact not found: $name")
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " evidence_cells=", artifact.summary.total_evidence_cells,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
