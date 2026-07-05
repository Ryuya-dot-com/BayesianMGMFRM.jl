#!/usr/bin/env julia

using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_guarded_exposure_review.json")

include(joinpath(@__DIR__, "local_json.jl"))

const REVIEWED_ARTIFACTS = [
    (name = :candidate_chain_study,
        path = "test/fixtures/gmfrm_candidate_chain_study.json",
        expected_schema = "bayesianmgmfrm.gmfrm_candidate_chain_study.v1"),
    (name = :stress_chain_grid,
        path = "test/fixtures/gmfrm_stress_chain_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_stress_chain_grid.v1"),
    (name = :recovery_smoke_study,
        path = "test/fixtures/gmfrm_recovery_smoke.json",
        expected_schema = "bayesianmgmfrm.gmfrm_recovery_smoke.v1"),
    (name = :baseline_comparison,
        path = "test/fixtures/gmfrm_baseline_comparison.json",
        expected_schema = "bayesianmgmfrm.gmfrm_baseline_comparison.v1"),
    (name = :baseline_calibration_grid,
        path = "test/fixtures/gmfrm_baseline_calibration_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_baseline_calibration_grid.v1"),
    (name = :interval_decision_grid,
        path = "test/fixtures/gmfrm_interval_decision_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_interval_decision_grid.v1"),
    (name = :sparse_design_grid,
        path = "test/fixtures/gmfrm_sparse_design_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_sparse_design_grid.v1"),
    (name = :waic_influence_review,
        path = "test/fixtures/gmfrm_waic_influence_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_waic_influence_review.v1"),
    (name = :psis_loo_review,
        path = "test/fixtures/gmfrm_psis_loo_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_psis_loo_review.v1"),
    (name = :exact_loo_or_kfold_review,
        path = "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_exact_loo_or_kfold_review.v1"),
    (name = :guarded_fit_api_dry_run,
        path = "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        expected_schema = "bayesianmgmfrm.gmfrm_guarded_fit_api_dry_run.v1"),
    (name = :guarded_fit_method_wiring,
        path = "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
        expected_schema = "bayesianmgmfrm.gmfrm_guarded_fit_method_wiring.v1"),
    (name = :experimental_fit_validation_grid,
        path = "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_experimental_fit_validation_grid.v1"),
    (name = :posterior_predictive_grid,
        path = "test/fixtures/gmfrm_posterior_predictive_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_posterior_predictive_grid.v1"),
    (name = :sparse_pathology_recovery_grid,
        path = "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_sparse_pathology_recovery_grid.v1"),
    (name = :prior_likelihood_sensitivity_grid,
        path = "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_prior_likelihood_sensitivity_grid.v1"),
    (name = :real_data_case_study,
        path = "test/fixtures/gmfrm_real_data_case_study.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_real_data_case_study.v1"),
    (name = :claim_recovery_reproduction_archive,
        path = "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_claim_recovery_reproduction_archive.v1"),
    (name = :broader_experimental_exposure_decision_review,
        path =
            "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_broader_experimental_exposure_decision_review.v1"),
    (name = :mgmfrm_sparse_recovery_grid,
        path = "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_sparse_recovery_grid.v1"),
    (name = :mgmfrm_guarded_fit_method_wiring,
        path = "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_method_wiring.v1"),
    (name = :mgmfrm_guarded_fit_validation_grid,
        path = "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_validation_grid.v1"),
    (name = :mgmfrm_guarded_fit_api_dry_run,
        path = "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_api_dry_run.v1"),
    (name = :mgmfrm_guarded_fit_public_exposure_review,
        path = "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_public_exposure_review.v1"),
    (name = :prediction_target_and_model_weight_policy,
        path =
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_prediction_target_and_model_weight_policy.v1"),
    (name = :mgmfrm_manual_public_scope_review_for_fit,
        path =
            "test/fixtures/mgmfrm_manual_public_scope_review_for_fit.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_manual_public_scope_review_for_fit.v1"),
    (name = :dff_estimand_validation_grid,
        path = "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_dff_estimand_validation_grid.v1"),
    (name = :manuscript_scale_simulation_grid,
        path = "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_manuscript_scale_simulation_grid.v1"),
    (name = :full_paper_reproduction_archive,
        path = "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_full_paper_reproduction_archive.v1"),
]

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_guarded_exposure_review_v1",
    review_kind = :local_guarded_exposure_review,
    publication_or_registration_action = false,
    entrypoint_under_review = "fit(spec; experimental = true)",
    decision_target = :experimental_public_scalar_gmfrm,
    thresholds = (;
        require_candidate_chain_passed = true,
        require_stress_chain_grid_passed = true,
        require_recovery_smoke_passed = true,
        require_baseline_comparison_passed = true,
        require_baseline_calibration_grid_passed = true,
        require_interval_decision_grid_passed = true,
        require_sparse_design_grid_passed = true,
        require_waic_influence_review_passed = true,
        require_psis_loo_review_passed = true,
        require_exact_loo_or_kfold_review_passed = true,
        require_guarded_fit_api_dry_run_passed = true,
        require_guarded_fit_method_wiring_passed = true,
        require_experimental_fit_validation_grid_passed = true,
        require_posterior_predictive_grid_passed = true,
        require_sparse_pathology_recovery_grid_passed = true,
        require_prior_likelihood_sensitivity_grid_passed = true,
        require_real_data_case_study_passed = true,
        require_claim_recovery_reproduction_archive_passed = true,
        require_broader_experimental_exposure_decision_review_passed = true,
        require_mgmfrm_sparse_recovery_grid_passed = true,
        require_mgmfrm_guarded_fit_method_wiring_passed = true,
        require_mgmfrm_guarded_fit_validation_grid_passed = true,
        require_mgmfrm_guarded_fit_api_dry_run_passed = true,
        require_mgmfrm_guarded_fit_public_exposure_review_passed = true,
        require_prediction_target_and_model_weight_policy_passed = true,
        require_mgmfrm_manual_public_scope_review_for_fit_passed = true,
        require_dff_estimand_validation_grid_passed = true,
        require_manuscript_scale_simulation_grid_passed = true,
        require_full_paper_reproduction_archive_passed = true,
        require_mgmfrm_construct_reviewed_q_fit_reporting_policy_passed = true,
        require_mgmfrm_heldout_prediction_validation_policy_passed = true,
        require_mgmfrm_validation_split_model_comparison_policy_passed =
            true,
        require_mgmfrm_heldout_prediction_simulation_grid_passed = true,
        high_variance_waic_blocks_public_exposure = true,
        psis_loo_or_exact_loo_required_before_exposure = true,
        high_pareto_k_blocks_public_exposure = true,
        exact_loo_or_kfold_required_before_exposure = true,
        guarded_fit_api_dry_run_required_before_exposure = true,
        guarded_fit_method_wiring_required_before_exposure = true,
        experimental_fit_validation_grid_required_before_exposure = true,
        posterior_predictive_grid_required_before_exposure = true,
        sparse_pathology_recovery_grid_required_before_exposure = true,
        prior_likelihood_sensitivity_grid_required_before_exposure = true,
        real_data_case_study_required_before_exposure = true,
        claim_level_recovery_and_reproduction_archive_required_before_exposure =
            true,
        broader_experimental_exposure_decision_review_required_before_exposure =
            true,
    ),
)

function usage()
    return """
    Generate the local scalar GMFRM guarded-exposure review artifact.

    Usage:
      julia --project=. scripts/generate_gmfrm_guarded_exposure_review.jl [--output PATH]
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

function file_sha256(path::AbstractString)
    return bytes2hex(open(sha256, path))
end

function fixture_path(relpath::AbstractString)
    return joinpath(ROOT, relpath)
end

function read_fixture_text(relpath::AbstractString)
    return read(fixture_path(relpath), String)
end

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
    value = required_value(text, key)
    parsed, next_index = parse_json_string_literal(collect(value), 1)
    next_index == length(collect(value)) + 1 ||
        error("JSON field `$key` is not a string literal")
    return parsed
end

function json_optional_string(text::AbstractString, key::AbstractString)
    value = json_value_for_key(text, key)
    value === nothing && return missing
    value == "null" && return missing
    parsed, _ = parse_json_string_literal(collect(value), 1)
    return parsed
end

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

json_int(text::AbstractString, key::AbstractString) =
    parse(Int, required_value(text, key))

json_float(text::AbstractString, key::AbstractString) =
    parse(Float64, required_value(text, key))

function json_summary(text::AbstractString)
    return required_value(text, "summary")
end

function summary_passed(summary::AbstractString)
    passed = json_value_for_key(summary, "passed")
    passed !== nothing && return passed == "true"
    overall = json_value_for_key(summary, "overall_passed")
    overall !== nothing && return overall == "true"
    return false
end

function artifact_summary(name::Symbol, text::AbstractString)
    summary = json_summary(text)
    name === :candidate_chain_study && return (;
        overall_passed = json_bool(summary, "overall_passed"),
        max_rhat = json_float(summary, "max_rhat"),
        min_ess = json_float(summary, "min_ess"),
        min_ebfmi = json_float(summary, "min_ebfmi"),
        n_divergences = json_int(summary, "n_divergences"),
        n_max_treedepth = json_int(summary, "n_max_treedepth"),
        n_failed_direct_constraints =
            json_int(summary, "n_failed_direct_constraints"),
    )
    name === :stress_chain_grid && return (;
        overall_passed = json_bool(summary, "overall_passed"),
        n_scenarios = json_int(summary, "n_scenarios"),
        n_passed_protocol = json_int(summary, "n_passed_protocol"),
        max_rhat = json_float(summary, "max_rhat"),
        min_ess = json_float(summary, "min_ess"),
        min_ebfmi = json_float(summary, "min_ebfmi"),
        n_divergences = json_int(summary, "n_divergences"),
        n_max_treedepth = json_int(summary, "n_max_treedepth"),
        n_failed_direct_constraints =
            json_int(summary, "n_failed_direct_constraints"),
    )
    name === :recovery_smoke_study && return (;
        passed = json_bool(summary, "passed"),
        n_parameters = json_int(summary, "n_parameters"),
        n_blocks = json_int(summary, "n_blocks"),
        max_block_mean_absolute_error =
            json_float(summary, "max_block_mean_absolute_error"),
        max_parameter_absolute_error =
            json_float(summary, "max_parameter_absolute_error"),
        min_block_coverage_rate = json_float(summary, "min_block_coverage_rate"),
        sampler_flag = json_string(summary, "sampler_flag"),
        n_divergences = json_int(summary, "n_divergences"),
        n_max_treedepth = json_int(summary, "n_max_treedepth"),
        e_bfmi = json_float(summary, "e_bfmi"),
    )
    name === :baseline_comparison && return (;
        passed = json_bool(summary, "passed"),
        comparison_executed = json_bool(summary, "comparison_executed"),
        n_models = json_int(summary, "n_models"),
        best_model = json_string(summary, "best_model"),
        gmfrm_rank = json_int(summary, "gmfrm_rank"),
        gmfrm_elpd_difference = json_float(summary, "gmfrm_elpd_difference"),
        gmfrm_relative_weight = json_float(summary, "gmfrm_relative_weight"),
        any_high_variance_waic = json_bool(summary, "any_high_variance_waic"),
        recommendation = json_string(summary, "recommendation"),
    )
    name === :baseline_calibration_grid && return (;
        passed = json_bool(summary, "passed"),
        n_scenarios = json_int(summary, "n_scenarios"),
        n_passed_scenarios = json_int(summary, "n_passed_scenarios"),
        n_models = json_int(summary, "n_models"),
        n_public_baseline_models = json_int(summary, "n_public_baseline_models"),
        n_internal_candidate_models =
            json_int(summary, "n_internal_candidate_models"),
        max_expected_score_rmse = json_float(summary, "max_expected_score_rmse"),
        max_mean_absolute_calibration_error =
            json_float(summary, "max_mean_absolute_calibration_error"),
        any_high_variance_waic = json_bool(summary, "any_high_variance_waic"),
        recommendation = json_string(summary, "recommendation"),
    )
    name === :interval_decision_grid && return (;
        passed = json_bool(summary, "passed"),
        n_scenarios = json_int(summary, "n_scenarios"),
        n_passed_scenarios = json_int(summary, "n_passed_scenarios"),
        n_interval_records = json_int(summary, "n_interval_records"),
        n_models = json_int(summary, "n_models"),
        all_local_intervals_finite =
            json_bool(summary, "all_local_intervals_finite"),
        min_interval_coverage_rate =
            json_float(summary, "min_interval_coverage_rate"),
        min_block_coverage_rate = json_float(summary, "min_block_coverage_rate"),
        max_parameter_absolute_error =
            json_float(summary, "max_parameter_absolute_error"),
        keep_internal_decision_count =
            json_int(summary, "keep_internal_decision_count"),
        decision_stability = json_string(summary, "decision_stability"),
        any_high_variance_waic = json_bool(summary, "any_high_variance_waic"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :sparse_design_grid && return (;
        passed = json_bool(summary, "passed"),
        n_scenarios = json_int(summary, "n_scenarios"),
        n_passed_scenarios = json_int(summary, "n_passed_scenarios"),
        n_sparse_validation_records =
            json_int(summary, "n_sparse_validation_records"),
        n_interval_records = json_int(summary, "n_interval_records"),
        n_models = json_int(summary, "n_models"),
        n_observations_minimum =
            json_int(summary, "n_observations_minimum"),
        n_observations_maximum =
            json_int(summary, "n_observations_maximum"),
        all_sparse_validations_passed =
            json_bool(summary, "all_sparse_validations_passed"),
        all_location_designs_full_rank =
            json_bool(summary, "all_location_designs_full_rank"),
        all_local_intervals_finite =
            json_bool(summary, "all_local_intervals_finite"),
        min_interval_coverage_rate =
            json_float(summary, "min_interval_coverage_rate"),
        min_block_coverage_rate = json_float(summary, "min_block_coverage_rate"),
        max_parameter_absolute_error =
            json_float(summary, "max_parameter_absolute_error"),
        keep_internal_decision_count =
            json_int(summary, "keep_internal_decision_count"),
        decision_stability = json_string(summary, "decision_stability"),
        any_high_variance_waic = json_bool(summary, "any_high_variance_waic"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :waic_influence_review && return (;
        passed = json_bool(summary, "passed"),
        n_scenario_reviews = json_int(summary, "n_scenario_reviews"),
        n_full_crossed_scenarios =
            json_int(summary, "n_full_crossed_scenarios"),
        n_sparse_scenarios = json_int(summary, "n_sparse_scenarios"),
        n_passed_scenarios = json_int(summary, "n_passed_scenarios"),
        n_models = json_int(summary, "n_models"),
        n_flagged_model_observations =
            json_int(summary, "n_flagged_model_observations"),
        max_p_waic = json_float(summary, "max_p_waic"),
        min_retained_observations =
            json_int(summary, "min_retained_observations"),
        n_best_model_changes_after_flagged_removal =
            json_int(summary, "n_best_model_changes_after_flagged_removal"),
        n_gmfrm_rank_changes_after_flagged_removal =
            json_int(summary, "n_gmfrm_rank_changes_after_flagged_removal"),
        all_samplers_passed = json_bool(summary, "all_samplers_passed"),
        all_masked_comparisons_finite =
            json_bool(summary, "all_masked_comparisons_finite"),
        any_high_variance_waic = json_bool(summary, "any_high_variance_waic"),
        keep_internal_decision_count =
            json_int(summary, "keep_internal_decision_count"),
        decision_stability = json_string(summary, "decision_stability"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :psis_loo_review && return (;
        passed = json_bool(summary, "passed"),
        n_scenario_reviews = json_int(summary, "n_scenario_reviews"),
        n_full_crossed_scenarios =
            json_int(summary, "n_full_crossed_scenarios"),
        n_sparse_scenarios = json_int(summary, "n_sparse_scenarios"),
        n_passed_scenarios = json_int(summary, "n_passed_scenarios"),
        n_models = json_int(summary, "n_models"),
        n_high_pareto_model_observations =
            json_int(summary, "n_high_pareto_model_observations"),
        n_high_pareto_unique_scenario_observations =
            json_int(summary, "n_high_pareto_unique_scenario_observations"),
        max_pareto_k = json_float(summary, "max_pareto_k"),
        min_effective_sample_size =
            json_float(summary, "min_effective_sample_size"),
        n_best_model_changes_from_waic_to_loo =
            json_int(summary, "n_best_model_changes_from_waic_to_loo"),
        n_gmfrm_rank_changes_from_waic_to_loo =
            json_int(summary, "n_gmfrm_rank_changes_from_waic_to_loo"),
        all_samplers_passed = json_bool(summary, "all_samplers_passed"),
        all_loo_comparisons_finite =
            json_bool(summary, "all_loo_comparisons_finite"),
        any_high_pareto_k = json_bool(summary, "any_high_pareto_k"),
        psis_smoothing_enabled = json_bool(summary, "psis_smoothing_enabled"),
        keep_internal_decision_count =
            json_int(summary, "keep_internal_decision_count"),
        decision_stability = json_string(summary, "decision_stability"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :exact_loo_or_kfold_review && return (;
        passed = json_bool(summary, "passed"),
        n_scenario_reviews = json_int(summary, "n_scenario_reviews"),
        n_full_crossed_scenarios =
            json_int(summary, "n_full_crossed_scenarios"),
        n_sparse_scenarios = json_int(summary, "n_sparse_scenarios"),
        n_passed_scenarios = json_int(summary, "n_passed_scenarios"),
        n_models = json_int(summary, "n_models"),
        n_fold_model_records = json_int(summary, "n_fold_model_records"),
        n_folds = json_int(summary, "n_folds"),
        all_observations_held_out_once =
            json_bool(summary, "all_observations_held_out_once"),
        all_parameter_orders_matched =
            json_bool(summary, "all_parameter_orders_matched"),
        all_samplers_passed = json_bool(summary, "all_samplers_passed"),
        all_kfold_comparisons_finite =
            json_bool(summary, "all_kfold_comparisons_finite"),
        min_train_observations = json_int(summary, "min_train_observations"),
        n_gmfrm_best_model_scenarios =
            json_int(summary, "n_gmfrm_best_model_scenarios"),
        max_gmfrm_kfoldic_difference =
            json_float(summary, "max_gmfrm_kfoldic_difference"),
        min_gmfrm_relative_weight =
            json_float(summary, "min_gmfrm_relative_weight"),
        keep_internal_decision_count =
            json_int(summary, "keep_internal_decision_count"),
        decision_stability = json_string(summary, "decision_stability"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :guarded_fit_api_dry_run && return (;
        passed = json_bool(summary, "passed"),
        dry_run_only = json_bool(summary, "dry_run_only"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        entrypoint_enabled = json_bool(summary, "entrypoint_enabled"),
        superseded_by_guarded_fit_method_wiring =
            json_bool(summary, "superseded_by_guarded_fit_method_wiring"),
        superseded_by_real_data_case_study =
            json_bool(summary, "superseded_by_real_data_case_study"),
        superseded_by_claim_recovery_reproduction_archive =
            json_bool(summary, "superseded_by_claim_recovery_reproduction_archive"),
        superseded_by_broader_experimental_exposure_decision_review =
            json_bool(
                summary,
                "superseded_by_broader_experimental_exposure_decision_review",
            ),
        superseded_by_full_paper_reproduction_archive =
            json_bool(summary,
                "superseded_by_full_paper_reproduction_archive"),
        public_fit_allowed = json_bool(summary, "public_fit_allowed"),
        experimental_keyword_enabled =
            json_bool(summary, "experimental_keyword_enabled"),
        current_manifest_fit_allowed =
            json_bool(summary, "current_manifest_fit_allowed"),
        current_manifest_experimental_keyword_enabled =
            json_bool(summary, "current_manifest_experimental_keyword_enabled"),
        fit_rejects_specified_only_gmfrm =
            json_bool(summary, "fit_rejects_specified_only_gmfrm"),
        fit_preview_rejects_experimental_keyword =
            json_bool(summary, "fit_preview_rejects_experimental_keyword"),
        artifact_contract_recorded =
            json_bool(summary, "artifact_contract_recorded"),
        all_required_artifact_fields_recorded =
            json_bool(summary, "all_required_artifact_fields_recorded"),
        all_required_provenance_artifacts_recorded =
            json_bool(summary, "all_required_provenance_artifacts_recorded"),
        n_required_artifact_fields =
            json_int(summary, "n_required_artifact_fields"),
        n_required_provenance_artifacts =
            json_int(summary, "n_required_provenance_artifacts"),
        all_file_evidence_present =
            json_bool(summary, "all_file_evidence_present"),
        n_evidence_references = json_int(summary, "n_evidence_references"),
        target_logdensity_finite =
            json_bool(summary, "target_logdensity_finite"),
        target_diagnostics_passed =
            json_bool(summary, "target_diagnostics_passed"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :guarded_fit_method_wiring && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        entrypoint_enabled = json_bool(summary, "entrypoint_enabled"),
        public_fit_allowed = json_bool(summary, "public_fit_allowed"),
        experimental_keyword_enabled =
            json_bool(summary, "experimental_keyword_enabled"),
        gmfrm_fit_returned = json_bool(summary, "gmfrm_fit_returned"),
        artifact_contract_satisfied =
            json_bool(summary, "artifact_contract_satisfied"),
        pointwise_loglikelihood_shape_valid =
            json_bool(summary, "pointwise_loglikelihood_shape_valid"),
        waic_and_loo_finite = json_bool(summary, "waic_and_loo_finite"),
        all_unsupported_public_options_rejected =
            json_bool(summary, "all_unsupported_public_options_rejected"),
        n_rejection_checks = json_int(summary, "n_rejection_checks"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :experimental_fit_validation_grid && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        n_scenarios = json_int(summary, "n_scenarios"),
        n_passed_scenarios = json_int(summary, "n_passed_scenarios"),
        n_total_draws_per_scenario =
            json_int(summary, "n_total_draws_per_scenario"),
        all_guarded_fit_returned =
            json_bool(summary, "all_guarded_fit_returned"),
        all_artifact_contracts_satisfied =
            json_bool(summary, "all_artifact_contracts_satisfied"),
        all_pointwise_shapes_valid =
            json_bool(summary, "all_pointwise_shapes_valid"),
        all_information_criteria_finite =
            json_bool(summary, "all_information_criteria_finite"),
        all_no_divergences = json_bool(summary, "all_no_divergences"),
        all_no_max_treedepth = json_bool(summary, "all_no_max_treedepth"),
        all_no_failed_direct_constraints =
            json_bool(summary, "all_no_failed_direct_constraints"),
        max_direct_parameter_mean_absolute_error =
            json_float(summary, "max_direct_parameter_mean_absolute_error"),
        max_direct_block_mean_absolute_error =
            json_float(summary, "max_direct_block_mean_absolute_error"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :posterior_predictive_grid && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        n_scenarios = json_int(summary, "n_scenarios"),
        n_passed_scenarios = json_int(summary, "n_passed_scenarios"),
        n_replicates_per_scenario =
            json_int(summary, "n_replicates_per_scenario"),
        all_ppc_returned = json_bool(summary, "all_ppc_returned"),
        all_replicated_scores_in_categories =
            json_bool(summary, "all_replicated_scores_in_categories"),
        all_probability_sums_valid =
            json_bool(summary, "all_probability_sums_valid"),
        all_summary_rows_finite =
            json_bool(summary, "all_summary_rows_finite"),
        all_calibration_rows_finite =
            json_bool(summary, "all_calibration_rows_finite"),
        all_mean_scores_inside_interval =
            json_bool(summary, "all_mean_scores_inside_interval"),
        max_outside_interval_rate =
            json_float(summary, "max_outside_interval_rate"),
        max_absolute_summary_error =
            json_float(summary, "max_absolute_summary_error"),
        max_absolute_mean_score_error =
            json_float(summary, "max_absolute_mean_score_error"),
        max_absolute_category_proportion_error =
            json_float(summary, "max_absolute_category_proportion_error"),
        max_absolute_calibration_error =
            json_float(summary, "max_absolute_calibration_error"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :sparse_pathology_recovery_grid && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        n_scenarios = json_int(summary, "n_scenarios"),
        n_passed_scenarios = json_int(summary, "n_passed_scenarios"),
        n_replicates_per_scenario =
            json_int(summary, "n_replicates_per_scenario"),
        n_observations_minimum = json_int(summary, "n_observations_minimum"),
        n_observations_maximum = json_int(summary, "n_observations_maximum"),
        all_validations_passed = json_bool(summary, "all_validations_passed"),
        all_location_designs_full_rank =
            json_bool(summary, "all_location_designs_full_rank"),
        all_guarded_fit_returned =
            json_bool(summary, "all_guarded_fit_returned"),
        all_pointwise_shapes_valid =
            json_bool(summary, "all_pointwise_shapes_valid"),
        all_information_criteria_finite =
            json_bool(summary, "all_information_criteria_finite"),
        all_no_divergences = json_bool(summary, "all_no_divergences"),
        all_no_max_treedepth = json_bool(summary, "all_no_max_treedepth"),
        all_no_failed_direct_constraints =
            json_bool(summary, "all_no_failed_direct_constraints"),
        all_ppc_returned = json_bool(summary, "all_ppc_returned"),
        all_replicated_scores_in_categories =
            json_bool(summary, "all_replicated_scores_in_categories"),
        all_probability_sums_valid =
            json_bool(summary, "all_probability_sums_valid"),
        all_summary_rows_finite =
            json_bool(summary, "all_summary_rows_finite"),
        all_calibration_rows_finite =
            json_bool(summary, "all_calibration_rows_finite"),
        max_direct_parameter_mean_absolute_error =
            json_float(summary, "max_direct_parameter_mean_absolute_error"),
        max_direct_block_mean_absolute_error =
            json_float(summary, "max_direct_block_mean_absolute_error"),
        max_outside_interval_rate =
            json_float(summary, "max_outside_interval_rate"),
        max_absolute_summary_error =
            json_float(summary, "max_absolute_summary_error"),
        max_absolute_calibration_error =
            json_float(summary, "max_absolute_calibration_error"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :prior_likelihood_sensitivity_grid && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        n_scenarios = json_int(summary, "n_scenarios"),
        n_passed_scenarios = json_int(summary, "n_passed_scenarios"),
        n_sensitivity_cells = json_int(summary, "n_sensitivity_cells"),
        n_prior_profiles = json_int(summary, "n_prior_profiles"),
        n_likelihood_powers = json_int(summary, "n_likelihood_powers"),
        all_cells_finite = json_bool(summary, "all_cells_finite"),
        all_baseline_identity =
            json_bool(summary, "all_baseline_identity"),
        min_weight_ess_rate = json_float(summary, "min_weight_ess_rate"),
        max_weight = json_float(summary, "max_weight"),
        max_direct_parameter_mean_shift =
            json_float(summary, "max_direct_parameter_mean_shift"),
        max_direct_block_mean_shift =
            json_float(summary, "max_direct_block_mean_shift"),
        max_expected_score_shift =
            json_float(summary, "max_expected_score_shift"),
        max_top_category_probability_shift =
            json_float(summary, "max_top_category_probability_shift"),
        max_loglikelihood_mean_shift =
            json_float(summary, "max_loglikelihood_mean_shift"),
        max_logposterior_decomposition_error =
            json_float(summary, "max_logposterior_decomposition_error"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :real_data_case_study && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        n_cases = json_int(summary, "n_cases"),
        n_passed_cases = json_int(summary, "n_passed_cases"),
        n_observations_total = json_int(summary, "n_observations_total"),
        n_replicates_per_case =
            json_int(summary, "n_replicates_per_case"),
        all_source_files_available =
            json_bool(summary, "all_source_files_available"),
        all_validations_passed =
            json_bool(summary, "all_validations_passed"),
        all_complete_crossing =
            json_bool(summary, "all_complete_crossing"),
        all_guarded_fit_returned =
            json_bool(summary, "all_guarded_fit_returned"),
        all_baseline_fits_returned =
            json_bool(summary, "all_baseline_fits_returned"),
        all_pointwise_shapes_valid =
            json_bool(summary, "all_pointwise_shapes_valid"),
        all_information_criteria_finite =
            json_bool(summary, "all_information_criteria_finite"),
        all_model_comparisons_finite =
            json_bool(summary, "all_model_comparisons_finite"),
        all_no_divergences = json_bool(summary, "all_no_divergences"),
        all_no_max_treedepth =
            json_bool(summary, "all_no_max_treedepth"),
        all_no_failed_direct_constraints =
            json_bool(summary, "all_no_failed_direct_constraints"),
        all_no_nonfinite_logdensity =
            json_bool(summary, "all_no_nonfinite_logdensity"),
        all_no_nonfinite_direct_loglikelihood =
            json_bool(summary, "all_no_nonfinite_direct_loglikelihood"),
        all_ppc_returned = json_bool(summary, "all_ppc_returned"),
        all_replicated_scores_in_categories =
            json_bool(summary, "all_replicated_scores_in_categories"),
        all_probability_sums_valid =
            json_bool(summary, "all_probability_sums_valid"),
        all_summary_rows_finite =
            json_bool(summary, "all_summary_rows_finite"),
        all_calibration_rows_finite =
            json_bool(summary, "all_calibration_rows_finite"),
        max_outside_interval_rate =
            json_float(summary, "max_outside_interval_rate"),
        max_absolute_summary_error =
            json_float(summary, "max_absolute_summary_error"),
        max_absolute_mean_score_error =
            json_float(summary, "max_absolute_mean_score_error"),
        max_absolute_category_proportion_error =
            json_float(summary, "max_absolute_category_proportion_error"),
        max_absolute_calibration_error =
            json_float(summary, "max_absolute_calibration_error"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :claim_recovery_reproduction_archive && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        local_only = json_bool(summary, "local_only"),
        n_fixture_artifacts = json_int(summary, "n_fixture_artifacts"),
        n_source_records = json_int(summary, "n_source_records"),
        n_code_doc_records = json_int(summary, "n_code_doc_records"),
        n_full_regeneration_commands =
            json_int(summary, "n_full_regeneration_commands"),
        n_verification_commands = json_int(summary, "n_verification_commands"),
        all_fixture_artifacts_present =
            json_bool(summary, "all_fixture_artifacts_present"),
        all_expected_schemas = json_bool(summary, "all_expected_schemas"),
        all_fixture_summaries_passed =
            json_bool(summary, "all_fixture_summaries_passed"),
        all_generator_scripts_present =
            json_bool(summary, "all_generator_scripts_present"),
        all_code_doc_references_present =
            json_bool(summary, "all_code_doc_references_present"),
        all_external_sources_present =
            json_bool(summary, "all_external_sources_present"),
        all_commands_local_only =
            json_bool(summary, "all_commands_local_only"),
        no_publication_commands =
            json_bool(summary, "no_publication_commands"),
        guarded_exposure_review_passed =
            json_bool(summary, "guarded_exposure_review_passed"),
        real_data_case_study_passed =
            json_bool(summary, "real_data_case_study_passed"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :broader_experimental_exposure_decision_review && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        local_only = json_bool(summary, "local_only"),
        all_input_artifacts_present =
            json_bool(summary, "all_input_artifacts_present"),
        all_expected_schemas = json_bool(summary, "all_expected_schemas"),
        all_required_inputs_passed =
            json_bool(summary, "all_required_inputs_passed"),
        guarded_exposure_review_passed =
            json_bool(summary, "guarded_exposure_review_passed"),
        claim_recovery_reproduction_archive_passed =
            json_bool(summary, "claim_recovery_reproduction_archive_passed"),
        real_data_case_study_passed =
            json_bool(summary, "real_data_case_study_passed"),
        mgmfrm_bridge_oracle_present =
            json_bool(summary, "mgmfrm_bridge_oracle_present"),
        mgmfrm_candidate_chain_study_passed =
            json_bool(summary, "mgmfrm_candidate_chain_study_passed"),
        mgmfrm_recovery_smoke_passed =
            json_bool(summary, "mgmfrm_recovery_smoke_passed"),
        mgmfrm_baseline_comparison_passed =
            json_bool(summary, "mgmfrm_baseline_comparison_passed"),
        mgmfrm_sparse_recovery_grid_passed =
            json_bool(summary, "mgmfrm_sparse_recovery_grid_passed"),
        mgmfrm_guarded_fit_method_wiring_passed =
            json_bool(summary, "mgmfrm_guarded_fit_method_wiring_passed"),
        mgmfrm_guarded_fit_validation_grid_passed =
            json_bool(summary, "mgmfrm_guarded_fit_validation_grid_passed"),
        mgmfrm_guarded_fit_api_dry_run_passed =
            json_bool(summary, "mgmfrm_guarded_fit_api_dry_run_passed"),
        mgmfrm_guarded_fit_public_exposure_review_passed =
            json_bool(summary,
                "mgmfrm_guarded_fit_public_exposure_review_passed"),
        prediction_target_and_model_weight_policy_passed =
            json_bool(summary,
                "prediction_target_and_model_weight_policy_passed"),
        mgmfrm_manual_public_scope_review_for_fit_passed =
            json_bool(summary,
                "mgmfrm_manual_public_scope_review_for_fit_passed"),
        dff_estimand_validation_grid_passed =
            json_bool(summary, "dff_estimand_validation_grid_passed"),
        manuscript_scale_simulation_grid_passed =
            json_bool(summary, "manuscript_scale_simulation_grid_passed"),
        full_paper_reproduction_archive_passed =
            json_bool(summary, "full_paper_reproduction_archive_passed"),
        n_input_artifacts = json_int(summary, "n_input_artifacts"),
        n_scope_decisions = json_int(summary, "n_scope_decisions"),
        n_risk_rows = json_int(summary, "n_risk_rows"),
        n_blockers = json_int(summary, "n_blockers"),
        scalar_guarded_fit_allowed =
            json_bool(summary, "scalar_guarded_fit_allowed"),
        broader_generalized_fit_allowed =
            json_bool(summary, "broader_generalized_fit_allowed"),
        mgmfrm_fit_allowed = json_bool(summary, "mgmfrm_fit_allowed"),
        dff_model_effects_allowed =
            json_bool(summary, "dff_model_effects_allowed"),
        model_weights_allowed =
            json_bool(summary, "model_weights_allowed"),
        manuscript_claims_allowed =
            json_bool(summary, "manuscript_claims_allowed"),
        no_publication_commands =
            json_bool(summary, "no_publication_commands"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :mgmfrm_sparse_recovery_grid && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        n_scenarios = json_int(summary, "n_scenarios"),
        n_passed_scenarios = json_int(summary, "n_passed_scenarios"),
        n_observations_minimum =
            json_int(summary, "n_observations_minimum"),
        n_observations_maximum =
            json_int(summary, "n_observations_maximum"),
        all_validations_passed =
            json_bool(summary, "all_validations_passed"),
        all_location_designs_full_rank =
            json_bool(summary, "all_location_designs_full_rank"),
        all_parameter_orders_match_reference =
            json_bool(summary, "all_parameter_orders_match_reference"),
        all_sampler_passed =
            json_bool(summary, "all_sampler_passed"),
        all_no_divergences =
            json_bool(summary, "all_no_divergences"),
        all_no_max_treedepth =
            json_bool(summary, "all_no_max_treedepth"),
        all_no_failed_direct_constraints =
            json_bool(summary, "all_no_failed_direct_constraints"),
        all_no_nonfinite_logdensity =
            json_bool(summary, "all_no_nonfinite_logdensity"),
        all_no_nonfinite_direct_loglikelihood =
            json_bool(summary, "all_no_nonfinite_direct_loglikelihood"),
        all_waic_finite = json_bool(summary, "all_waic_finite"),
        any_high_variance_waic =
            json_bool(summary, "any_high_variance_waic"),
        max_block_mean_absolute_error =
            json_float(summary, "max_block_mean_absolute_error"),
        max_parameter_absolute_error =
            json_float(summary, "max_parameter_absolute_error"),
        min_block_coverage_rate =
            json_float(summary, "min_block_coverage_rate"),
        public_fit_allowed = json_bool(summary, "public_fit_allowed"),
        experimental_keyword_enabled =
            json_bool(summary, "experimental_keyword_enabled"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :mgmfrm_guarded_fit_method_wiring && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        entrypoint_enabled = json_bool(summary, "entrypoint_enabled"),
        public_fit_allowed = json_bool(summary, "public_fit_allowed"),
        experimental_keyword_enabled =
            json_bool(summary, "experimental_keyword_enabled"),
        target_constructor_available =
            json_bool(summary, "target_constructor_available"),
        raw_to_direct_transform_available =
            json_bool(summary, "raw_to_direct_transform_available"),
        sampler_protocol_passed =
            json_bool(summary, "sampler_protocol_passed"),
        artifact_contract_satisfied =
            json_bool(summary, "artifact_contract_satisfied"),
        pointwise_loglikelihood_shape_valid =
            json_bool(summary, "pointwise_loglikelihood_shape_valid"),
        all_fit_boundary_checks_passed =
            json_bool(summary, "all_fit_boundary_checks_passed"),
        experimental_spec_fit_succeeded =
            json_bool(summary, "experimental_spec_fit_succeeded"),
        all_fixture_references_present =
            json_bool(summary, "all_fixture_references_present"),
        n_fit_boundary_checks = json_int(summary, "n_fit_boundary_checks"),
        n_fixture_references = json_int(summary, "n_fixture_references"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :mgmfrm_guarded_fit_validation_grid && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        entrypoint_enabled = json_bool(summary, "entrypoint_enabled"),
        public_fit_allowed = json_bool(summary, "public_fit_allowed"),
        experimental_keyword_enabled =
            json_bool(summary, "experimental_keyword_enabled"),
        all_input_artifacts_present =
            json_bool(summary, "all_input_artifacts_present"),
        all_expected_schemas = json_bool(summary, "all_expected_schemas"),
        all_input_summaries_passed =
            json_bool(summary, "all_input_summaries_passed"),
        all_validation_rows_passed =
            json_bool(summary, "all_validation_rows_passed"),
        guarded_fit_method_wiring_passed =
            json_bool(summary, "guarded_fit_method_wiring_passed"),
        method_sampler_protocol_passed =
            json_bool(summary, "method_sampler_protocol_passed"),
        method_artifact_contract_satisfied =
            json_bool(summary, "method_artifact_contract_satisfied"),
        method_fit_boundary_checks_passed =
            json_bool(summary, "method_fit_boundary_checks_passed"),
        method_experimental_spec_fit_succeeded =
            json_bool(summary, "method_experimental_spec_fit_succeeded"),
        n_input_artifacts = json_int(summary, "n_input_artifacts"),
        n_validation_rows = json_int(summary, "n_validation_rows"),
        n_passed_validation_rows = json_int(summary, "n_passed_validation_rows"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :mgmfrm_guarded_fit_api_dry_run && return (;
        passed = json_bool(summary, "passed"),
        dry_run_only = json_bool(summary, "dry_run_only"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        entrypoint_enabled = json_bool(summary, "entrypoint_enabled"),
        public_fit_allowed = json_bool(summary, "public_fit_allowed"),
        experimental_keyword_enabled =
            json_bool(summary, "experimental_keyword_enabled"),
        all_input_artifacts_present =
            json_bool(summary, "all_input_artifacts_present"),
        all_expected_schemas = json_bool(summary, "all_expected_schemas"),
        all_input_summaries_passed =
            json_bool(summary, "all_input_summaries_passed"),
        guarded_fit_validation_grid_passed =
            json_bool(summary, "guarded_fit_validation_grid_passed"),
        validation_grid_all_rows_passed =
            json_bool(summary, "validation_grid_all_rows_passed"),
        all_fit_boundary_checks_passed =
            json_bool(summary, "all_fit_boundary_checks_passed"),
        experimental_spec_fit_succeeded =
            json_bool(summary, "experimental_spec_fit_succeeded"),
        artifact_contract_satisfied =
            json_bool(summary, "artifact_contract_satisfied"),
        target_logdensity_finite =
            json_bool(summary, "target_logdensity_finite"),
        target_gradient_diagnostics_passed =
            json_bool(summary, "target_gradient_diagnostics_passed"),
        n_input_artifacts = json_int(summary, "n_input_artifacts"),
        n_fit_boundary_checks = json_int(summary, "n_fit_boundary_checks"),
        n_gradient_checks = json_int(summary, "n_gradient_checks"),
        n_failed_gradient_checks = json_int(summary, "n_failed_gradient_checks"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :mgmfrm_guarded_fit_public_exposure_review && return (;
        passed = json_bool(summary, "passed"),
        reviewed = json_bool(summary, "reviewed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        local_only = json_bool(summary, "local_only"),
        public_fit_allowed = json_bool(summary, "public_fit_allowed"),
        experimental_keyword_enabled =
            json_bool(summary, "experimental_keyword_enabled"),
        all_input_artifacts_present =
            json_bool(summary, "all_input_artifacts_present"),
        all_expected_schemas = json_bool(summary, "all_expected_schemas"),
        all_input_summaries_passed =
            json_bool(summary, "all_input_summaries_passed"),
        all_fit_boundary_checks_passed =
            json_bool(summary, "all_fit_boundary_checks_passed"),
        current_manifest_guarded_fit_enabled =
            json_bool(summary, "current_manifest_guarded_fit_enabled"),
        no_publication_commands =
            json_bool(summary, "no_publication_commands"),
        mgmfrm_guarded_fit_api_dry_run_passed =
            json_bool(summary, "mgmfrm_guarded_fit_api_dry_run_passed"),
        dff_estimand_validation_grid_passed =
            json_bool(summary, "dff_estimand_validation_grid_passed"),
        n_input_artifacts = json_int(summary, "n_input_artifacts"),
        n_review_rows = json_int(summary, "n_review_rows"),
        n_blockers = json_int(summary, "n_blockers"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :prediction_target_and_model_weight_policy && return (;
        passed = json_bool(summary, "passed"),
        policy_recorded = json_bool(summary, "policy_recorded"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        local_only = json_bool(summary, "local_only"),
        all_input_artifacts_present =
            json_bool(summary, "all_input_artifacts_present"),
        all_expected_schemas = json_bool(summary, "all_expected_schemas"),
        all_input_summaries_passed =
            json_bool(summary, "all_input_summaries_passed"),
        same_data_waic_blocked =
            json_bool(summary, "same_data_waic_blocked"),
        raw_psis_loo_blocked =
            json_bool(summary, "raw_psis_loo_blocked"),
        heldout_kfold_selected =
            json_bool(summary, "heldout_kfold_selected"),
        scalar_local_model_weight_reporting_allowed =
            json_bool(summary,
                "scalar_local_model_weight_reporting_allowed"),
        public_model_weight_claims_allowed =
            json_bool(summary, "public_model_weight_claims_allowed"),
        mgmfrm_fit_allowed = json_bool(summary, "mgmfrm_fit_allowed"),
        mgmfrm_weight_claims_allowed =
            json_bool(summary, "mgmfrm_weight_claims_allowed"),
        manuscript_sparse_mgmfrm_claims_allowed =
            json_bool(summary, "manuscript_sparse_mgmfrm_claims_allowed"),
        current_mgmfrm_manifest_guarded_fit_enabled =
            json_bool(summary, "current_mgmfrm_manifest_guarded_fit_enabled"),
        mgmfrm_fit_boundary_checks_passed =
            json_bool(summary, "mgmfrm_fit_boundary_checks_passed"),
        no_publication_commands =
            json_bool(summary, "no_publication_commands"),
        n_input_artifacts = json_int(summary, "n_input_artifacts"),
        n_prediction_target_rows =
            json_int(summary, "n_prediction_target_rows"),
        n_model_weight_policy_rows =
            json_int(summary, "n_model_weight_policy_rows"),
        n_blockers = json_int(summary, "n_blockers"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :mgmfrm_manual_public_scope_review_for_fit && return (;
        passed = json_bool(summary, "passed"),
        reviewed = json_bool(summary, "reviewed"),
        manual_public_scope_review_recorded =
            json_bool(summary, "manual_public_scope_review_recorded"),
        manual_public_scope_review_satisfied =
            json_bool(summary, "manual_public_scope_review_satisfied"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        local_only = json_bool(summary, "local_only"),
        public_fit_allowed = json_bool(summary, "public_fit_allowed"),
        experimental_keyword_enabled =
            json_bool(summary, "experimental_keyword_enabled"),
        current_manifest_guarded_fit_enabled =
            json_bool(summary, "current_manifest_guarded_fit_enabled"),
        all_input_artifacts_present =
            json_bool(summary, "all_input_artifacts_present"),
        all_expected_schemas = json_bool(summary, "all_expected_schemas"),
        all_input_summaries_passed =
            json_bool(summary, "all_input_summaries_passed"),
        all_fit_boundary_checks_passed =
            json_bool(summary, "all_fit_boundary_checks_passed"),
        no_publication_commands =
            json_bool(summary, "no_publication_commands"),
        scope_limited_to_confirmatory_fixed_q =
            json_bool(summary, "scope_limited_to_confirmatory_fixed_q"),
        local_guarded_fit_development_allowed =
            json_bool(summary, "local_guarded_fit_development_allowed"),
        public_model_weight_claims_allowed =
            json_bool(summary, "public_model_weight_claims_allowed"),
        sparse_superiority_claims_allowed =
            json_bool(summary, "sparse_superiority_claims_allowed"),
        mgmfrm_fit_allowed = json_bool(summary, "mgmfrm_fit_allowed"),
        n_input_artifacts = json_int(summary, "n_input_artifacts"),
        n_fit_boundary_checks = json_int(summary, "n_fit_boundary_checks"),
        n_scope_decisions = json_int(summary, "n_scope_decisions"),
        n_risk_rows = json_int(summary, "n_risk_rows"),
        n_review_rows = json_int(summary, "n_review_rows"),
        n_blockers = json_int(summary, "n_blockers"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :dff_estimand_validation_grid && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        local_only = json_bool(summary, "local_only"),
        n_estimands = json_int(summary, "n_estimands"),
        n_predeclared_reporting_scales =
            json_int(summary, "n_predeclared_reporting_scales"),
        n_scenarios = json_int(summary, "n_scenarios"),
        n_passed_scenarios = json_int(summary, "n_passed_scenarios"),
        n_validation_passed_scenarios =
            json_int(summary, "n_validation_passed_scenarios"),
        n_validation_error_scenarios =
            json_int(summary, "n_validation_error_scenarios"),
        n_sparse_warning_scenarios =
            json_int(summary, "n_sparse_warning_scenarios"),
        n_empty_warning_scenarios =
            json_int(summary, "n_empty_warning_scenarios"),
        n_confounding_warning_scenarios =
            json_int(summary, "n_confounding_warning_scenarios"),
        all_expected_outcomes_matched =
            json_bool(summary, "all_expected_outcomes_matched"),
        all_valid_dff_terms_retained_as_validation_only =
            json_bool(summary,
                "all_valid_dff_terms_retained_as_validation_only"),
        all_estimands_predeclared =
            json_bool(summary, "all_estimands_predeclared"),
        all_reporting_scales_predeclared =
            json_bool(summary, "all_reporting_scales_predeclared"),
        dff_model_effects_allowed =
            json_bool(summary, "dff_model_effects_allowed"),
        public_fit_allowed = json_bool(summary, "public_fit_allowed"),
        experimental_keyword_enabled =
            json_bool(summary, "experimental_keyword_enabled"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :manuscript_scale_simulation_grid && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        local_only = json_bool(summary, "local_only"),
        all_input_artifacts_present =
            json_bool(summary, "all_input_artifacts_present"),
        all_expected_schemas = json_bool(summary, "all_expected_schemas"),
        all_input_summaries_passed =
            json_bool(summary, "all_input_summaries_passed"),
        all_primary_checks_passed =
            json_bool(summary, "all_primary_checks_passed"),
        n_input_artifacts = json_int(summary, "n_input_artifacts"),
        n_evidence_rows = json_int(summary, "n_evidence_rows"),
        total_evidence_cells = json_int(summary, "total_evidence_cells"),
        minimum_required_evidence_cells =
            json_int(summary, "minimum_required_evidence_cells"),
        scalar_fit_validation_grid_passed =
            json_bool(summary, "scalar_fit_validation_grid_passed"),
        posterior_predictive_grid_passed =
            json_bool(summary, "posterior_predictive_grid_passed"),
        sparse_pathology_recovery_grid_passed =
            json_bool(summary, "sparse_pathology_recovery_grid_passed"),
        prior_likelihood_sensitivity_grid_passed =
            json_bool(summary, "prior_likelihood_sensitivity_grid_passed"),
        real_data_case_study_passed =
            json_bool(summary, "real_data_case_study_passed"),
        prediction_target_and_model_weight_policy_passed =
            json_bool(summary,
                "prediction_target_and_model_weight_policy_passed"),
        mgmfrm_manual_public_scope_review_for_fit_passed =
            json_bool(summary,
                "mgmfrm_manual_public_scope_review_for_fit_passed"),
        dff_estimand_validation_grid_passed =
            json_bool(summary, "dff_estimand_validation_grid_passed"),
        mgmfrm_sparse_recovery_grid_passed =
            json_bool(summary, "mgmfrm_sparse_recovery_grid_passed"),
        mgmfrm_q_revision_cross_validation_policy_passed =
            json_bool(summary,
                "mgmfrm_q_revision_cross_validation_policy_passed"),
        mgmfrm_q_revision_construct_validity_review_passed =
            json_bool(summary,
                "mgmfrm_q_revision_construct_validity_review_passed"),
        mgmfrm_guarded_local_fit_entrypoint_passed =
            json_bool(summary,
                "mgmfrm_guarded_local_fit_entrypoint_passed"),
        mgmfrm_fit_metric_threshold_sensitivity_passed =
            json_bool(summary,
                "mgmfrm_fit_metric_threshold_sensitivity_passed"),
        mgmfrm_construct_reviewed_q_fit_reporting_policy_passed =
            json_bool(summary,
                "mgmfrm_construct_reviewed_q_fit_reporting_policy_passed"),
        mgmfrm_heldout_prediction_validation_policy_passed =
            json_bool(summary,
                "mgmfrm_heldout_prediction_validation_policy_passed"),
        mgmfrm_validation_split_model_comparison_policy_passed =
            json_bool(summary,
                "mgmfrm_validation_split_model_comparison_policy_passed"),
        mgmfrm_heldout_prediction_simulation_grid_passed =
            json_bool(summary,
                "mgmfrm_heldout_prediction_simulation_grid_passed"),
        full_paper_reproduction_archive_passed =
            json_bool(summary, "full_paper_reproduction_archive_passed"),
        manuscript_claims_allowed =
            json_bool(summary, "manuscript_claims_allowed"),
        n_blockers = json_int(summary, "n_blockers"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    name === :full_paper_reproduction_archive && return (;
        passed = json_bool(summary, "passed"),
        publication_or_registration_action =
            json_bool(summary, "publication_or_registration_action"),
        local_only = json_bool(summary, "local_only"),
        all_fixture_artifacts_present =
            json_bool(summary, "all_fixture_artifacts_present"),
        all_expected_schemas = json_bool(summary, "all_expected_schemas"),
        all_fixture_summaries_passed =
            json_bool(summary, "all_fixture_summaries_passed"),
        all_generator_scripts_present =
            json_bool(summary, "all_generator_scripts_present"),
        all_code_doc_references_present =
            json_bool(summary, "all_code_doc_references_present"),
        all_external_sources_present =
            json_bool(summary, "all_external_sources_present"),
        all_commands_local_only =
            json_bool(summary, "all_commands_local_only"),
        no_publication_commands =
            json_bool(summary, "no_publication_commands"),
        n_fixture_artifacts = json_int(summary, "n_fixture_artifacts"),
        n_code_doc_records = json_int(summary, "n_code_doc_records"),
        n_source_records = json_int(summary, "n_source_records"),
        n_full_regeneration_commands =
            json_int(summary, "n_full_regeneration_commands"),
        n_verification_commands = json_int(summary, "n_verification_commands"),
        guarded_exposure_review_passed =
            json_bool(summary, "guarded_exposure_review_passed"),
        broader_experimental_exposure_decision_review_passed =
            json_bool(summary,
                "broader_experimental_exposure_decision_review_passed"),
        manuscript_scale_simulation_grid_passed =
            json_bool(summary, "manuscript_scale_simulation_grid_passed"),
        mgmfrm_report_shape_simulation_grid_passed =
            json_bool(summary,
                "mgmfrm_report_shape_simulation_grid_passed"),
        mgmfrm_q_matrix_validation_expansion_passed =
            json_bool(summary,
                "mgmfrm_q_matrix_validation_expansion_passed"),
        mgmfrm_empirical_q_matrix_recovery_policy_passed =
            json_bool(summary,
                "mgmfrm_empirical_q_matrix_recovery_policy_passed"),
        mgmfrm_empirical_q_matrix_recovery_simulation_grid_passed =
            json_bool(summary,
                "mgmfrm_empirical_q_matrix_recovery_simulation_grid_passed"),
        mgmfrm_q_candidate_real_fit_diagnostic_linkage_passed =
            json_bool(summary,
                "mgmfrm_q_candidate_real_fit_diagnostic_linkage_passed"),
        mgmfrm_q_revision_cross_validation_policy_passed =
            json_bool(summary,
                "mgmfrm_q_revision_cross_validation_policy_passed"),
        mgmfrm_q_revision_construct_validity_review_passed =
            json_bool(summary,
                "mgmfrm_q_revision_construct_validity_review_passed"),
        mgmfrm_guarded_local_fit_entrypoint_passed =
            json_bool(summary,
                "mgmfrm_guarded_local_fit_entrypoint_passed"),
        mgmfrm_fit_metric_threshold_sensitivity_passed =
            json_bool(summary,
                "mgmfrm_fit_metric_threshold_sensitivity_passed"),
        mgmfrm_construct_reviewed_q_fit_reporting_policy_passed =
            json_bool(summary,
                "mgmfrm_construct_reviewed_q_fit_reporting_policy_passed"),
        mgmfrm_heldout_prediction_validation_policy_passed =
            json_bool(summary,
                "mgmfrm_heldout_prediction_validation_policy_passed"),
        mgmfrm_validation_split_model_comparison_policy_passed =
            json_bool(summary,
                "mgmfrm_validation_split_model_comparison_policy_passed"),
        mgmfrm_heldout_prediction_simulation_grid_passed =
            json_bool(summary,
                "mgmfrm_heldout_prediction_simulation_grid_passed"),
        prediction_target_and_model_weight_policy_passed =
            json_bool(summary,
                "prediction_target_and_model_weight_policy_passed"),
        mgmfrm_manual_public_scope_review_for_fit_passed =
            json_bool(summary,
                "mgmfrm_manual_public_scope_review_for_fit_passed"),
        manuscript_reproducibility_claims_supported =
            json_bool(summary,
                "manuscript_reproducibility_claims_supported"),
        n_blockers = json_int(summary, "n_blockers"),
        recommendation = json_string(summary, "recommendation"),
        next_gate = json_string(summary, "next_gate"),
    )
    return (; passed = summary_passed(summary))
end

function artifact_record(spec)
    path = fixture_path(spec.path)
    isfile(path) || error("review artifact is missing: $(spec.path)")
    text = read_fixture_text(spec.path)
    schema = json_string(text, "schema")
    schema == spec.expected_schema ||
        error("unexpected schema for $(spec.path): $schema")
    return (;
        artifact = spec.name,
        path = spec.path,
        sha256 = file_sha256(path),
        schema,
        family = json_optional_string(text, "family"),
        scope = json_optional_string(text, "scope"),
        status = json_optional_string(text, "status"),
        public_fit = json_optional_bool(text, "public_fit"),
        experimental_public = json_optional_bool(text, "experimental_public"),
        fit_ready = json_optional_bool(text, "fit_ready"),
        summary = artifact_summary(spec.name, text),
    )
end

function artifact_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function artifact_passed(record)
    summary = record.summary
    haskey(summary, :passed) && return Bool(summary.passed)
    haskey(summary, :overall_passed) && return Bool(summary.overall_passed)
    return false
end

function best_model_counts(grid_text::AbstractString)
    summary = json_summary(grid_text)
    array = required_value(summary, "best_model_counts")
    rows = NamedTuple[]
    for matched in eachmatch(r"\{\s*\"model\"\s*:\s*\"([^\"]+)\"\s*,\s*\"n\"\s*:\s*(\d+)\s*\}", array)
        push!(rows, (model = matched.captures[1], n = parse(Int, matched.captures[2])))
    end
    isempty(rows) && error("best_model_counts rows not found")
    return rows
end

function review_rows(records)
    baseline = artifact_by_name(records, :baseline_comparison)
    grid = artifact_by_name(records, :baseline_calibration_grid)
    interval_grid = artifact_by_name(records, :interval_decision_grid)
    sparse_grid = artifact_by_name(records, :sparse_design_grid)
    waic_review = artifact_by_name(records, :waic_influence_review)
    psis_review = artifact_by_name(records, :psis_loo_review)
    exact_review = artifact_by_name(records, :exact_loo_or_kfold_review)
    dry_run = artifact_by_name(records, :guarded_fit_api_dry_run)
    method_wiring = artifact_by_name(records, :guarded_fit_method_wiring)
    validation_grid = artifact_by_name(records, :experimental_fit_validation_grid)
    posterior_predictive_grid =
        artifact_by_name(records, :posterior_predictive_grid)
    sparse_pathology_recovery_grid =
        artifact_by_name(records, :sparse_pathology_recovery_grid)
    prior_likelihood_sensitivity_grid =
        artifact_by_name(records, :prior_likelihood_sensitivity_grid)
    real_data_case_study =
        artifact_by_name(records, :real_data_case_study)
    claim_archive =
        artifact_by_name(records, :claim_recovery_reproduction_archive)
    broader_review =
        artifact_by_name(records, :broader_experimental_exposure_decision_review)
    mgmfrm_sparse_grid =
        artifact_by_name(records, :mgmfrm_sparse_recovery_grid)
    mgmfrm_method =
        artifact_by_name(records, :mgmfrm_guarded_fit_method_wiring)
    mgmfrm_validation =
        artifact_by_name(records, :mgmfrm_guarded_fit_validation_grid)
    mgmfrm_api_dry_run =
        artifact_by_name(records, :mgmfrm_guarded_fit_api_dry_run)
    mgmfrm_public_review =
        artifact_by_name(records,
            :mgmfrm_guarded_fit_public_exposure_review)
    prediction_policy =
        artifact_by_name(records,
            :prediction_target_and_model_weight_policy)
    mgmfrm_scope_review =
        artifact_by_name(records,
            :mgmfrm_manual_public_scope_review_for_fit)
    dff_grid =
        artifact_by_name(records, :dff_estimand_validation_grid)
    manuscript_grid =
        artifact_by_name(records, :manuscript_scale_simulation_grid)
    full_archive =
        artifact_by_name(records, :full_paper_reproduction_archive)
    high_variance =
        Bool(baseline.summary.any_high_variance_waic) ||
        Bool(grid.summary.any_high_variance_waic) ||
        Bool(interval_grid.summary.any_high_variance_waic) ||
        Bool(sparse_grid.summary.any_high_variance_waic) ||
        Bool(waic_review.summary.any_high_variance_waic)
    high_pareto = Bool(psis_review.summary.any_high_pareto_k)
    return [
        (gate = :candidate_chain_study, status = :passed,
            evidence = :gmfrm_candidate_chain_study,
            finding = :fixture_chains_have_no_sampler_blockers),
        (gate = :stress_chain_grid, status = :passed,
            evidence = :gmfrm_stress_chain_grid,
            finding = :stress_scenarios_have_no_sampler_blockers),
        (gate = :recovery_smoke_study, status = :passed,
            evidence = :gmfrm_recovery_smoke,
            finding = :direct_block_recovery_smoke_passed),
        (gate = :baseline_comparison, status = :passed_with_caution,
            evidence = :gmfrm_baseline_comparison,
            finding = :same_observation_waic_smoke_has_high_variance_warning),
        (gate = :baseline_calibration_grid, status = :passed_with_caution,
            evidence = :gmfrm_baseline_calibration_grid,
            finding = :expected_score_calibration_passed_but_waic_high_variance),
        (gate = :interval_decision_grid, status = :passed_with_caution,
            evidence = :gmfrm_interval_decision_grid,
            finding = :intervals_finite_and_keep_internal_decision_stable),
        (gate = :sparse_design_grid, status = :passed_with_caution,
            evidence = :gmfrm_sparse_design_grid,
            finding = :sparse_designs_validated_and_keep_internal_decision_stable),
        (gate = :waic_influence_review, status = :passed_with_caution,
            evidence = :gmfrm_waic_influence_review,
            finding = :flagged_observation_removal_changes_some_model_ranks),
        (gate = :psis_loo_review, status = :passed_with_caution,
            evidence = :gmfrm_psis_loo_review,
            finding = :raw_importance_loo_recorded_with_high_pareto_k),
        (gate = :exact_loo_or_kfold_review, status = :passed_with_caution,
            evidence = :gmfrm_exact_loo_or_kfold_review,
            finding = :kfold_refit_review_satisfied_exact_loo_followup),
        (gate = :guarded_fit_api_dry_run, status = :passed,
            evidence = Bool(dry_run.summary.passed) &&
                Bool(exact_review.summary.passed),
            finding =
                :guarded_entrypoint_contract_dry_run_recorded_without_public_fit),
        (gate = :guarded_fit_method_wiring, status = :passed,
            evidence = Bool(method_wiring.summary.passed) &&
                Bool(method_wiring.summary.entrypoint_enabled),
            finding =
                :guarded_scalar_gmfrm_experimental_fit_method_wired),
        (gate = :experimental_fit_validation_grid, status = :passed,
            evidence = Bool(validation_grid.summary.passed) &&
                Bool(validation_grid.summary.all_guarded_fit_returned) &&
                Bool(validation_grid.summary.all_artifact_contracts_satisfied),
            finding =
                :guarded_scalar_gmfrm_experimental_fit_validation_grid_passed_and_ppc_checked),
        (gate = :scalar_gmfrm_posterior_predictive_grid, status = :passed,
            evidence = Bool(posterior_predictive_grid.summary.passed) &&
                Bool(posterior_predictive_grid.summary.all_ppc_returned) &&
                Bool(posterior_predictive_grid.summary.all_summary_rows_finite),
            finding =
                :guarded_scalar_gmfrm_posterior_predictive_grid_passed),
        (gate = :scalar_gmfrm_sparse_pathology_recovery_grid, status = :passed,
            evidence = Bool(sparse_pathology_recovery_grid.summary.passed) &&
                Bool(sparse_pathology_recovery_grid.summary.all_guarded_fit_returned) &&
                Bool(sparse_pathology_recovery_grid.summary.all_ppc_returned),
            finding =
                :guarded_scalar_gmfrm_sparse_pathology_recovery_grid_passed),
        (gate = :scalar_gmfrm_prior_likelihood_sensitivity_grid, status = :passed,
            evidence = Bool(prior_likelihood_sensitivity_grid.summary.passed) &&
                Bool(prior_likelihood_sensitivity_grid.summary.all_cells_finite) &&
                Bool(prior_likelihood_sensitivity_grid.summary.all_baseline_identity),
            finding =
                :guarded_scalar_gmfrm_prior_likelihood_sensitivity_grid_passed),
        (gate = :scalar_gmfrm_real_data_case_study, status = :passed,
            evidence = Bool(real_data_case_study.summary.passed) &&
                Bool(real_data_case_study.summary.all_guarded_fit_returned) &&
                Bool(real_data_case_study.summary.all_model_comparisons_finite),
            finding =
                :guarded_scalar_gmfrm_real_data_case_study_passed),
        (gate = :claim_level_recovery_and_reproduction_archive, status = :passed,
            evidence = Bool(claim_archive.summary.passed) &&
                Bool(claim_archive.summary.all_fixture_artifacts_present) &&
                Bool(claim_archive.summary.all_commands_local_only),
            finding =
                :claim_level_recovery_reproduction_archive_recorded),
        (gate = :broader_experimental_exposure_decision_review, status = :passed,
            evidence = Bool(broader_review.summary.passed) &&
                Bool(broader_review.summary.scalar_guarded_fit_allowed) &&
                Bool(broader_review.summary.mgmfrm_fit_allowed) &&
                !Bool(broader_review.summary.broader_generalized_fit_allowed),
            finding =
                :broader_experimental_exposure_decision_review_recorded_scalar_and_confirmatory_mgmfrm_only),
        (gate = :confirmatory_mgmfrm_sparse_recovery_grid, status = :passed,
            evidence = Bool(mgmfrm_sparse_grid.summary.passed) &&
                Bool(mgmfrm_sparse_grid.summary.all_validations_passed) &&
                Bool(mgmfrm_sparse_grid.summary.all_sampler_passed),
            finding =
                :confirmatory_mgmfrm_sparse_recovery_grid_recorded_no_superiority_claim),
        (gate = :confirmatory_mgmfrm_guarded_fit_method_wiring,
            status = :passed,
            evidence = Bool(mgmfrm_method.summary.passed) &&
                Bool(mgmfrm_method.summary.sampler_protocol_passed) &&
                Bool(mgmfrm_method.summary.artifact_contract_satisfied) &&
                Bool(mgmfrm_method.summary.entrypoint_enabled) &&
                Bool(mgmfrm_method.summary.all_fit_boundary_checks_passed),
            finding =
                :confirmatory_mgmfrm_guarded_fit_method_recorded_entrypoint_enabled),
        (gate = :confirmatory_mgmfrm_guarded_fit_validation_grid,
            status = :passed,
            evidence = Bool(mgmfrm_validation.summary.passed) &&
                Bool(mgmfrm_validation.summary.all_validation_rows_passed) &&
                Bool(mgmfrm_validation.summary.entrypoint_enabled),
            finding =
                :confirmatory_mgmfrm_guarded_fit_validation_grid_recorded_entrypoint_enabled),
        (gate = :confirmatory_mgmfrm_guarded_fit_api_dry_run,
            status = :passed,
            evidence = Bool(mgmfrm_api_dry_run.summary.passed) &&
                Bool(mgmfrm_api_dry_run.summary.dry_run_only) &&
                Bool(mgmfrm_api_dry_run.summary.all_fit_boundary_checks_passed) &&
                Bool(mgmfrm_api_dry_run.summary.experimental_spec_fit_succeeded) &&
                Bool(mgmfrm_api_dry_run.summary.target_gradient_diagnostics_passed) &&
                Bool(mgmfrm_api_dry_run.summary.entrypoint_enabled),
            finding =
                :confirmatory_mgmfrm_guarded_fit_api_dry_run_recorded_entrypoint_enabled),
        (gate = :confirmatory_mgmfrm_guarded_fit_public_exposure_review,
            status = :passed_with_policy_blocker,
            evidence = Bool(mgmfrm_public_review.summary.passed) &&
                Bool(mgmfrm_public_review.summary.reviewed) &&
                Bool(mgmfrm_public_review.summary.all_fit_boundary_checks_passed) &&
                Bool(mgmfrm_public_review.summary.current_manifest_guarded_fit_enabled) &&
                Bool(mgmfrm_public_review.summary.public_fit_allowed),
            finding =
                :confirmatory_mgmfrm_public_exposure_review_recorded_entrypoint_enabled_claims_blocked),
        (gate = :prediction_target_and_model_weight_policy,
            status = :passed_with_scope_blocker,
            evidence = Bool(prediction_policy.summary.passed) &&
                Bool(prediction_policy.summary.policy_recorded) &&
                Bool(prediction_policy.summary.heldout_kfold_selected) &&
                Bool(prediction_policy.summary.same_data_waic_blocked) &&
                Bool(prediction_policy.summary.raw_psis_loo_blocked) &&
                Bool(prediction_policy.summary.mgmfrm_fit_allowed),
            finding =
                :heldout_kfold_weight_policy_recorded_keep_mgmfrm_claims_blocked),
        (gate = :mgmfrm_manual_public_scope_review_for_fit,
            status = :passed,
            evidence = Bool(mgmfrm_scope_review.summary.passed) &&
                Bool(mgmfrm_scope_review.summary.manual_public_scope_review_satisfied) &&
                Bool(mgmfrm_scope_review.summary.local_guarded_fit_development_allowed) &&
                Bool(mgmfrm_scope_review.summary.public_fit_allowed) &&
                Bool(mgmfrm_scope_review.summary.mgmfrm_fit_allowed),
            finding =
                :manual_mgmfrm_scope_review_recorded_guarded_fit_enabled),
        (gate = :confirmatory_mgmfrm_fit_metric_threshold_sensitivity,
            status = :passed_with_policy_blocker,
            evidence = Bool(getproperty(full_archive.summary,
                :mgmfrm_fit_metric_threshold_sensitivity_passed)),
            finding =
                :fit_metric_threshold_sensitivity_recorded_local_diagnostic_only),
        (gate = :confirmatory_mgmfrm_construct_reviewed_q_fit_reporting_policy,
            status = :passed_with_policy_blocker,
            evidence = Bool(getproperty(full_archive.summary,
                :mgmfrm_construct_reviewed_q_fit_reporting_policy_passed)),
            finding =
                :construct_reviewed_q_fit_reporting_policy_recorded_local_appendix_only),
        (gate = :confirmatory_mgmfrm_heldout_prediction_validation_policy,
            status = :passed_with_policy_blocker,
            evidence = Bool(getproperty(full_archive.summary,
                :mgmfrm_heldout_prediction_validation_policy_passed)),
            finding =
                :heldout_prediction_validation_policy_recorded_claims_blocked),
        (gate = :confirmatory_mgmfrm_validation_split_model_comparison_policy,
            status = :passed_with_policy_blocker,
            evidence = Bool(getproperty(full_archive.summary,
                :mgmfrm_validation_split_model_comparison_policy_passed)),
            finding =
                :validation_split_and_model_comparison_policy_recorded_execution_pending),
        (gate = :confirmatory_mgmfrm_heldout_prediction_simulation_grid,
            status = :passed_with_policy_blocker,
            evidence = Bool(getproperty(full_archive.summary,
                :mgmfrm_heldout_prediction_simulation_grid_passed)),
            finding =
                :heldout_prediction_simulation_grid_recorded_execution_pending),
        (gate = :dff_estimand_and_validation_grid, status = :passed,
            evidence = Bool(dff_grid.summary.passed) &&
                Bool(dff_grid.summary.all_estimands_predeclared) &&
                Bool(dff_grid.summary.all_valid_dff_terms_retained_as_validation_only),
            finding =
                :dff_estimands_predeclared_and_validation_only_grid_recorded),
        (gate = :manuscript_scale_simulation_grid, status = :passed,
            evidence = Bool(manuscript_grid.summary.passed) &&
                Bool(manuscript_grid.summary.all_primary_checks_passed) &&
                !Bool(manuscript_grid.summary.manuscript_claims_allowed),
            finding =
                :manuscript_scale_grid_recorded_full_archive_available),
        (gate = :full_paper_reproduction_archive, status = :passed,
            evidence = Bool(full_archive.summary.passed) &&
                Bool(full_archive.summary.all_fixture_artifacts_present) &&
                Bool(full_archive.summary.all_commands_local_only),
            finding =
                :full_paper_reproduction_archive_recorded_local_only),
    ]
end

function blocking_rows(rows)
    return NamedTuple[]
end

function build_artifact()
    records = [artifact_record(spec) for spec in REVIEWED_ARTIFACTS]
    rows = review_rows(records)
    blockers = blocking_rows(rows)
    grid_text = read_fixture_text("test/fixtures/gmfrm_baseline_calibration_grid.json")
    baseline = artifact_by_name(records, :baseline_comparison)
    grid = artifact_by_name(records, :baseline_calibration_grid)
    interval_grid = artifact_by_name(records, :interval_decision_grid)
    sparse_grid = artifact_by_name(records, :sparse_design_grid)
    waic_review = artifact_by_name(records, :waic_influence_review)
    psis_review = artifact_by_name(records, :psis_loo_review)
    exact_review = artifact_by_name(records, :exact_loo_or_kfold_review)
    dry_run = artifact_by_name(records, :guarded_fit_api_dry_run)
    method_wiring = artifact_by_name(records, :guarded_fit_method_wiring)
    validation_grid = artifact_by_name(records, :experimental_fit_validation_grid)
    posterior_predictive_grid =
        artifact_by_name(records, :posterior_predictive_grid)
    sparse_pathology_recovery_grid =
        artifact_by_name(records, :sparse_pathology_recovery_grid)
    prior_likelihood_sensitivity_grid =
        artifact_by_name(records, :prior_likelihood_sensitivity_grid)
    real_data_case_study =
        artifact_by_name(records, :real_data_case_study)
    claim_archive =
        artifact_by_name(records, :claim_recovery_reproduction_archive)
    broader_review =
        artifact_by_name(records, :broader_experimental_exposure_decision_review)
    mgmfrm_sparse_grid =
        artifact_by_name(records, :mgmfrm_sparse_recovery_grid)
    mgmfrm_method =
        artifact_by_name(records, :mgmfrm_guarded_fit_method_wiring)
    mgmfrm_validation =
        artifact_by_name(records, :mgmfrm_guarded_fit_validation_grid)
    mgmfrm_api_dry_run =
        artifact_by_name(records, :mgmfrm_guarded_fit_api_dry_run)
    mgmfrm_public_review =
        artifact_by_name(records,
            :mgmfrm_guarded_fit_public_exposure_review)
    prediction_policy =
        artifact_by_name(records,
            :prediction_target_and_model_weight_policy)
    mgmfrm_scope_review =
        artifact_by_name(records,
            :mgmfrm_manual_public_scope_review_for_fit)
    dff_grid =
        artifact_by_name(records, :dff_estimand_validation_grid)
    manuscript_grid =
        artifact_by_name(records, :manuscript_scale_simulation_grid)
    full_archive =
        artifact_by_name(records, :full_paper_reproduction_archive)
    all_local_evidence_passed = all(artifact_passed, records)
    any_high_variance_waic =
        Bool(baseline.summary.any_high_variance_waic) ||
        Bool(grid.summary.any_high_variance_waic) ||
        Bool(interval_grid.summary.any_high_variance_waic) ||
        Bool(sparse_grid.summary.any_high_variance_waic) ||
        Bool(waic_review.summary.any_high_variance_waic)
    any_high_pareto_k = Bool(psis_review.summary.any_high_pareto_k)
    return (;
        schema = "bayesianmgmfrm.gmfrm_guarded_exposure_review.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :guarded_exposure_review_recorded,
        decision = :enable_guarded_experimental,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        reviewed_artifacts = records,
        baseline_calibration_best_model_counts = best_model_counts(grid_text),
        review_rows = rows,
        blocker_rows = blockers,
        decision_record = (;
            proposed_entrypoint = "fit(spec; experimental = true)",
            public_exposure_support =
                :guarded_scalar_gmfrm_only,
            interpretation =
                :local_evidence_reviewed_manual_scope_review_recorded_and_broader_exposure_decision_recorded,
            required_followup = :heldout_mgmfrm_prediction_execution,
        ),
        summary = (;
            reviewed = true,
            publication_or_registration_action = false,
            all_local_evidence_passed,
            any_high_variance_waic,
            any_high_pareto_k,
            exact_loo_or_kfold_review_passed = Bool(exact_review.summary.passed),
            guarded_fit_api_dry_run_passed = Bool(dry_run.summary.passed),
            guarded_fit_method_wiring_passed =
                Bool(method_wiring.summary.passed),
            experimental_fit_validation_grid_passed =
                Bool(validation_grid.summary.passed),
            posterior_predictive_grid_passed =
                Bool(posterior_predictive_grid.summary.passed),
            sparse_pathology_recovery_grid_passed =
                Bool(sparse_pathology_recovery_grid.summary.passed),
            prior_likelihood_sensitivity_grid_passed =
                Bool(prior_likelihood_sensitivity_grid.summary.passed),
            real_data_case_study_passed =
                Bool(real_data_case_study.summary.passed),
            claim_recovery_reproduction_archive_passed =
                Bool(claim_archive.summary.passed),
            broader_experimental_exposure_decision_review_passed =
                Bool(broader_review.summary.passed),
            mgmfrm_sparse_recovery_grid_passed =
                Bool(mgmfrm_sparse_grid.summary.passed),
            mgmfrm_guarded_fit_method_wiring_passed =
                Bool(mgmfrm_method.summary.passed),
            mgmfrm_guarded_fit_validation_grid_passed =
                Bool(mgmfrm_validation.summary.passed),
            mgmfrm_guarded_fit_api_dry_run_passed =
                Bool(mgmfrm_api_dry_run.summary.passed),
            mgmfrm_guarded_fit_public_exposure_review_passed =
                Bool(mgmfrm_public_review.summary.passed),
            mgmfrm_report_shape_simulation_grid_passed =
                Bool(getproperty(full_archive.summary,
                    :mgmfrm_report_shape_simulation_grid_passed)),
            mgmfrm_q_matrix_validation_expansion_passed =
                Bool(getproperty(full_archive.summary,
                    :mgmfrm_q_matrix_validation_expansion_passed)),
            mgmfrm_empirical_q_matrix_recovery_policy_passed =
                Bool(getproperty(full_archive.summary,
                    :mgmfrm_empirical_q_matrix_recovery_policy_passed)),
            mgmfrm_empirical_q_matrix_recovery_simulation_grid_passed =
                Bool(getproperty(full_archive.summary,
                    :mgmfrm_empirical_q_matrix_recovery_simulation_grid_passed)),
            mgmfrm_q_candidate_real_fit_diagnostic_linkage_passed =
                Bool(getproperty(full_archive.summary,
                    :mgmfrm_q_candidate_real_fit_diagnostic_linkage_passed)),
            mgmfrm_q_revision_cross_validation_policy_passed =
                Bool(getproperty(full_archive.summary,
                    :mgmfrm_q_revision_cross_validation_policy_passed)),
            mgmfrm_q_revision_construct_validity_review_passed =
                Bool(getproperty(full_archive.summary,
                    :mgmfrm_q_revision_construct_validity_review_passed)),
            mgmfrm_guarded_local_fit_entrypoint_passed =
                Bool(getproperty(full_archive.summary,
                    :mgmfrm_guarded_local_fit_entrypoint_passed)),
            mgmfrm_fit_metric_threshold_sensitivity_passed =
                Bool(getproperty(full_archive.summary,
                    :mgmfrm_fit_metric_threshold_sensitivity_passed)),
            mgmfrm_construct_reviewed_q_fit_reporting_policy_passed =
                Bool(getproperty(full_archive.summary,
                    :mgmfrm_construct_reviewed_q_fit_reporting_policy_passed)),
            mgmfrm_heldout_prediction_validation_policy_passed =
                Bool(getproperty(full_archive.summary,
                    :mgmfrm_heldout_prediction_validation_policy_passed)),
            mgmfrm_validation_split_model_comparison_policy_passed =
                Bool(getproperty(full_archive.summary,
                    :mgmfrm_validation_split_model_comparison_policy_passed)),
            mgmfrm_heldout_prediction_simulation_grid_passed =
                Bool(getproperty(full_archive.summary,
                    :mgmfrm_heldout_prediction_simulation_grid_passed)),
            prediction_target_and_model_weight_policy_passed =
                Bool(prediction_policy.summary.passed),
            mgmfrm_manual_public_scope_review_for_fit_passed =
                Bool(mgmfrm_scope_review.summary.passed),
            dff_estimand_validation_grid_passed =
                Bool(dff_grid.summary.passed),
            manuscript_scale_simulation_grid_passed =
                Bool(manuscript_grid.summary.passed),
            full_paper_reproduction_archive_passed =
                Bool(full_archive.summary.passed),
            scalar_guarded_fit_allowed =
                Bool(broader_review.summary.scalar_guarded_fit_allowed),
            broader_generalized_fit_allowed =
                Bool(broader_review.summary.broader_generalized_fit_allowed),
            mgmfrm_fit_allowed =
                Bool(broader_review.summary.mgmfrm_fit_allowed),
            n_reviewed_artifacts = length(records),
            n_review_rows = length(rows),
            n_blockers = length(blockers),
            fit_allowed = true,
            experimental_keyword_enabled = true,
            recommendation =
                :manual_scope_review_recorded_keep_guarded_scalar_and_confirmatory_mgmfrm_only,
            next_gate = :heldout_mgmfrm_prediction_execution,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("decision=", artifact.decision,
        " blockers=", artifact.summary.n_blockers,
        " all_local_evidence_passed=", artifact.summary.all_local_evidence_passed)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
