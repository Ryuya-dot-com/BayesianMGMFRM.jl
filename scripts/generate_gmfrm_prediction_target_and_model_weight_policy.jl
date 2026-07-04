#!/usr/bin/env julia

using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "gmfrm_prediction_target_and_model_weight_policy.json")

include(joinpath(@__DIR__, "local_json.jl"))

module FullArchiveJSON
include(joinpath(@__DIR__, "generate_gmfrm_full_paper_reproduction_archive.jl"))
end

const JSON = FullArchiveJSON

const INPUT_ARTIFACTS = [
    (name = :sparse_design_grid,
        path = "test/fixtures/gmfrm_sparse_design_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_sparse_design_grid.v1",
        pass_policy = :summary_passed),
    (name = :waic_influence_review,
        path = "test/fixtures/gmfrm_waic_influence_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_waic_influence_review.v1",
        pass_policy = :summary_passed),
    (name = :psis_loo_review,
        path = "test/fixtures/gmfrm_psis_loo_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_psis_loo_review.v1",
        pass_policy = :summary_passed),
    (name = :exact_loo_or_kfold_review,
        path = "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_exact_loo_or_kfold_review.v1",
        pass_policy = :summary_passed),
    (name = :guarded_fit_api_dry_run,
        path = "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        expected_schema = "bayesianmgmfrm.gmfrm_guarded_fit_api_dry_run.v1",
        pass_policy = :summary_passed),
    (name = :guarded_fit_method_wiring,
        path = "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_guarded_fit_method_wiring.v1",
        pass_policy = :summary_passed),
    (name = :experimental_fit_validation_grid,
        path = "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_experimental_fit_validation_grid.v1",
        pass_policy = :summary_passed),
    (name = :posterior_predictive_grid,
        path = "test/fixtures/gmfrm_posterior_predictive_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_posterior_predictive_grid.v1",
        pass_policy = :summary_passed),
    (name = :mgmfrm_baseline_comparison,
        path = "test/fixtures/mgmfrm_baseline_comparison.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_baseline_comparison.v1",
        pass_policy = :summary_passed),
    (name = :mgmfrm_sparse_recovery_grid,
        path = "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_sparse_recovery_grid.v1",
        pass_policy = :summary_passed),
    (name = :mgmfrm_guarded_fit_public_exposure_review,
        path = "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_public_exposure_review.v1",
        pass_policy = :summary_passed),
    (name = :dff_estimand_validation_grid,
        path = "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_dff_estimand_validation_grid.v1",
        pass_policy = :summary_passed),
]

const PROTOCOL = (;
    protocol_id = "gmfrm_prediction_target_and_model_weight_policy_v1",
    review_kind = :local_prediction_target_and_model_weight_policy,
    publication_or_registration_action = false,
    local_only = true,
    policy_scope =
        :guarded_scalar_gmfrm_and_confirmatory_mgmfrm_claim_boundaries,
    primary_prediction_target = :heldout_observation_log_score,
    thresholds = (;
        require_sparse_design_grid_passed = true,
        require_waic_influence_review_passed = true,
        require_psis_loo_review_passed = true,
        require_exact_loo_or_kfold_review_passed = true,
        require_guarded_scalar_fit_evidence_passed = true,
        require_mgmfrm_public_exposure_review_passed = true,
        require_dff_estimand_validation_grid_passed = true,
        require_same_data_waic_blocked_for_weight_claims = true,
        require_raw_psis_loo_blocked_for_weight_claims = true,
        require_heldout_kfold_target_selected = true,
        require_mgmfrm_weight_claims_blocked_until_public_scope_review = true,
        require_no_publication_or_registration_action = true,
    ),
)

const BLOCKER_ROWS = [
    (blocker = :manual_public_scope_review_for_mgmfrm_fit_missing,
        severity = :blocking,
        required_action =
            :record_local_manual_public_scope_review_before_mgmfrm_fit_claims),
]

function usage()
    return """
    Generate the local GMFRM prediction-target/model-weight policy artifact.

    This records which prediction target may support model comparison weights
    and which targets remain diagnostics only. It does not publish, register,
    or enable MGMFRM fitting.

    Usage:
      julia --project=. scripts/generate_gmfrm_prediction_target_and_model_weight_policy.jl [--output PATH]
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
local_path(path::AbstractString) = normpath(joinpath(ROOT, path))

function json_optional_int(text::Union{Nothing,AbstractString},
        key::AbstractString,
        default::Int = 0)
    text === nothing && return default
    value = JSON.json_value_for_key(text, key)
    value === nothing && return default
    return parse(Int, value)
end

function json_optional_float(text::Union{Nothing,AbstractString},
        key::AbstractString,
        default::Float64 = NaN)
    text === nothing && return default
    value = JSON.json_value_for_key(text, key)
    value === nothing && return default
    return parse(Float64, value)
end

function json_optional_string(text::Union{Nothing,AbstractString},
        key::AbstractString,
        default::Symbol = :missing)
    text === nothing && return default
    value = JSON.json_value_for_key(text, key)
    value === nothing && return default
    value == "null" && return default
    parsed, _ = JSON.parse_json_string_literal(collect(value), 1)
    return Symbol(parsed)
end

function summary_bool(summary::Union{Nothing,AbstractString},
        key::AbstractString,
        default::Bool = false)
    summary === nothing && return default
    value = JSON.json_optional_bool(summary, key)
    return value === missing ? default : Bool(value)
end

function summary_passed(summary::Union{Nothing,AbstractString}, policy::Symbol)
    policy === :schema_only && return true
    summary === nothing && return false
    policy === :summary_passed && return summary_bool(summary, "passed")
    policy === :summary_overall_passed &&
        return summary_bool(summary, "overall_passed")
    throw(ArgumentError("unknown pass policy: $policy"))
end

function artifact_summary(name::Symbol, summary::Union{Nothing,AbstractString})
    name === :sparse_design_grid && return (;
        passed = summary_bool(summary, "passed"),
        prediction_target = :same_observation_waic,
        any_high_variance_waic =
            summary_bool(summary, "any_high_variance_waic"),
        decision_stability =
            json_optional_string(summary, "decision_stability"),
    )
    name === :waic_influence_review && return (;
        passed = summary_bool(summary, "passed"),
        prediction_target = :same_observation_waic,
        any_high_variance_waic =
            summary_bool(summary, "any_high_variance_waic"),
        n_flagged_model_observations =
            json_optional_int(summary, "n_flagged_model_observations"),
        decision_stability =
            json_optional_string(summary, "decision_stability"),
    )
    name === :psis_loo_review && return (;
        passed = summary_bool(summary, "passed"),
        prediction_target = :leave_one_observation_importance_log_score,
        any_high_pareto_k = summary_bool(summary, "any_high_pareto_k"),
        max_pareto_k = json_optional_float(summary, "max_pareto_k"),
        decision_stability =
            json_optional_string(summary, "decision_stability"),
    )
    name === :exact_loo_or_kfold_review && return (;
        passed = summary_bool(summary, "passed"),
        prediction_target = :heldout_observation_log_score,
        n_folds = json_optional_int(summary, "n_folds"),
        all_observations_held_out_once =
            summary_bool(summary, "all_observations_held_out_once"),
        all_kfold_comparisons_finite =
            summary_bool(summary, "all_kfold_comparisons_finite"),
        n_gmfrm_best_model_scenarios =
            json_optional_int(summary, "n_gmfrm_best_model_scenarios"),
        min_gmfrm_relative_weight =
            json_optional_float(summary, "min_gmfrm_relative_weight"),
        decision_stability =
            json_optional_string(summary, "decision_stability"),
    )
    name === :guarded_fit_api_dry_run && return (;
        passed = summary_bool(summary, "passed"),
        entrypoint_enabled = summary_bool(summary, "entrypoint_enabled"),
        public_fit_allowed = summary_bool(summary, "public_fit_allowed"),
        target_gradient_diagnostics_passed =
            summary_bool(summary, "target_gradient_diagnostics_passed"),
    )
    name === :guarded_fit_method_wiring && return (;
        passed = summary_bool(summary, "passed"),
        entrypoint_enabled = summary_bool(summary, "entrypoint_enabled"),
        public_fit_allowed = summary_bool(summary, "public_fit_allowed"),
        gmfrm_fit_returned = summary_bool(summary, "gmfrm_fit_returned"),
    )
    name === :experimental_fit_validation_grid && return (;
        passed = summary_bool(summary, "passed"),
        all_guarded_fit_returned =
            summary_bool(summary, "all_guarded_fit_returned"),
        all_information_criteria_finite =
            summary_bool(summary, "all_information_criteria_finite"),
    )
    name === :posterior_predictive_grid && return (;
        passed = summary_bool(summary, "passed"),
        all_ppc_returned = summary_bool(summary, "all_ppc_returned"),
        all_calibration_rows_finite =
            summary_bool(summary, "all_calibration_rows_finite"),
    )
    name === :mgmfrm_baseline_comparison && return (;
        passed = summary_bool(summary, "passed"),
        public_fit_allowed = summary_bool(summary, "public_fit_allowed"),
        comparison_executed = summary_bool(summary, "comparison_executed"),
    )
    name === :mgmfrm_sparse_recovery_grid && return (;
        passed = summary_bool(summary, "passed"),
        public_fit_allowed = summary_bool(summary, "public_fit_allowed"),
        all_validations_passed =
            summary_bool(summary, "all_validations_passed"),
        all_sampler_passed = summary_bool(summary, "all_sampler_passed"),
    )
    name === :mgmfrm_guarded_fit_public_exposure_review && return (;
        passed = summary_bool(summary, "passed"),
        public_fit_allowed = summary_bool(summary, "public_fit_allowed"),
        reviewed = summary_bool(summary, "reviewed"),
        current_manifest_guarded_fit_enabled =
            summary_bool(summary, "current_manifest_guarded_fit_enabled"),
        all_fit_boundary_checks_passed =
            summary_bool(summary, "all_fit_boundary_checks_passed"),
    )
    name === :dff_estimand_validation_grid && return (;
        passed = summary_bool(summary, "passed"),
        dff_model_effects_allowed =
            summary_bool(summary, "dff_model_effects_allowed"),
    )
    return (; passed = summary_bool(summary, "passed"))
end

function artifact_record(spec)
    path = local_path(spec.path)
    exists = isfile(path)
    text = exists ? read(path, String) : ""
    schema = exists ? JSON.json_string(text, "schema") : missing
    schema_matches = exists && schema == spec.expected_schema
    summary_text = exists ? JSON.json_summary(text) : nothing
    parsed_summary = artifact_summary(spec.name, summary_text)
    passed = exists && schema_matches && summary_passed(summary_text, spec.pass_policy)
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        sha256 = exists ? file_sha256(path) : missing,
        expected_schema = spec.expected_schema,
        schema,
        schema_matches,
        pass_policy = spec.pass_policy,
        summary_passed = passed,
        summary = parsed_summary,
    )
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_gmfrm_prediction_target_and_model_weight_policy.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function prediction_target_rows(records)
    sparse = record_by_name(records, :sparse_design_grid)
    waic = record_by_name(records, :waic_influence_review)
    psis = record_by_name(records, :psis_loo_review)
    kfold = record_by_name(records, :exact_loo_or_kfold_review)
    return [
        (target = :same_observation_waic,
            status = :diagnostic_only,
            evidence = Bool(sparse.summary_passed) && Bool(waic.summary_passed),
            allowed_for_model_weight_claims = false,
            allowed_for_sparse_mgmfrm_superiority_claims = false,
            reason =
                :same_observation_elpd_and_high_variance_waic_are_not_public_weight_targets,
            artifact = waic.path),
        (target = :raw_importance_loo,
            status = :diagnostic_only,
            evidence = Bool(psis.summary_passed),
            allowed_for_model_weight_claims = false,
            allowed_for_sparse_mgmfrm_superiority_claims = false,
            reason =
                :raw_importance_loo_requires_pareto_screen_and_is_not_promoted_to_weights,
            artifact = psis.path),
        (target = :heldout_observation_log_score,
            status = :selected_primary_local_target,
            evidence = Bool(kfold.summary_passed) &&
                Bool(kfold.summary.all_observations_held_out_once) &&
                Bool(kfold.summary.all_kfold_comparisons_finite),
            allowed_for_model_weight_claims = true,
            allowed_for_sparse_mgmfrm_superiority_claims = false,
            reason =
                :deterministic_kfold_refits_define_the_local_weight_target,
            artifact = kfold.path),
    ]
end

function model_weight_policy_rows(records)
    scalar_api = record_by_name(records, :guarded_fit_api_dry_run)
    scalar_method = record_by_name(records, :guarded_fit_method_wiring)
    scalar_validation = record_by_name(records, :experimental_fit_validation_grid)
    ppc = record_by_name(records, :posterior_predictive_grid)
    mgmfrm_baseline = record_by_name(records, :mgmfrm_baseline_comparison)
    mgmfrm_sparse = record_by_name(records, :mgmfrm_sparse_recovery_grid)
    mgmfrm_public_review =
        record_by_name(records, :mgmfrm_guarded_fit_public_exposure_review)
    dff = record_by_name(records, :dff_estimand_validation_grid)
    return [
        (surface = :scalar_gmfrm_guarded_fit,
            status = :policy_recorded,
            primary_prediction_target = :heldout_observation_log_score,
            allowed_for_local_model_weight_reporting = true,
            allowed_for_public_sparse_mgmfrm_claims = false,
            evidence = Bool(scalar_api.summary_passed) &&
                Bool(scalar_method.summary_passed) &&
                Bool(scalar_validation.summary_passed) &&
                Bool(ppc.summary_passed),
            required_followup = :manual_publication_or_registration_by_user_only),
        (surface = :confirmatory_mgmfrm_fit,
            status = :policy_recorded_fit_allowed_weights_blocked,
            primary_prediction_target = :heldout_observation_log_score,
            allowed_for_local_model_weight_reporting = false,
            allowed_for_public_sparse_mgmfrm_claims = false,
            evidence = Bool(mgmfrm_baseline.summary_passed) &&
                Bool(mgmfrm_sparse.summary_passed) &&
                Bool(mgmfrm_public_review.summary_passed),
            required_followup = :guarded_local_mgmfrm_fit_entrypoint),
        (surface = :dff_model_effects,
            status = :validation_only,
            primary_prediction_target = :not_applicable,
            allowed_for_local_model_weight_reporting = false,
            allowed_for_public_sparse_mgmfrm_claims = false,
            evidence = Bool(dff.summary_passed),
            required_followup = :future_dff_model_effect_fit_policy),
    ]
end

function risk_rows()
    return [
        (risk = :same_data_waic_overweighting,
            decision = :block_same_data_waic_weight_claims,
            mitigation = :use_only_as_screening_with_influence_review),
        (risk = :raw_importance_loo_instability,
            decision = :block_raw_psis_loo_weight_claims,
            mitigation = :prefer_refit_kfold_when_weights_are_discussed),
        (risk = :mgmfrm_fit_scope_overclaim,
            decision = :allow_guarded_fit_but_block_weight_claims,
            mitigation = :require_separate_public_model_weight_claim_review),
        (risk = :dff_policy_overclaim,
            decision = :keep_dff_as_validation_only,
            mitigation = :require_separate_dff_model_effect_fit_policy),
    ]
end

function build_artifact()
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    target_rows = prediction_target_rows(input_records)
    weight_rows = model_weight_policy_rows(input_records)
    kfold = record_by_name(input_records, :exact_loo_or_kfold_review)
    psis = record_by_name(input_records, :psis_loo_review)
    waic = record_by_name(input_records, :waic_influence_review)
    mgmfrm_public_review =
        record_by_name(input_records, :mgmfrm_guarded_fit_public_exposure_review)
    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_input_summaries_passed =
        all(record -> record.summary_passed, input_records)
    same_data_waic_blocked =
        all(!Bool(row.allowed_for_model_weight_claims)
            for row in target_rows if row.target === :same_observation_waic)
    raw_psis_loo_blocked =
        all(!Bool(row.allowed_for_model_weight_claims)
            for row in target_rows if row.target === :raw_importance_loo)
    heldout_kfold_selected =
        any(row -> row.target === :heldout_observation_log_score &&
            row.status === :selected_primary_local_target &&
            Bool(row.allowed_for_model_weight_claims) &&
            Bool(row.evidence), target_rows)
    scalar_local_weight_reporting_allowed =
        any(row -> row.surface === :scalar_gmfrm_guarded_fit &&
            Bool(row.allowed_for_local_model_weight_reporting) &&
            Bool(row.evidence), weight_rows)
    mgmfrm_weight_claims_allowed =
        any(row -> row.surface === :confirmatory_mgmfrm_fit &&
            Bool(row.allowed_for_local_model_weight_reporting), weight_rows)
    manuscript_sparse_mgmfrm_claims_allowed =
        any(row -> Bool(row.allowed_for_public_sparse_mgmfrm_claims), weight_rows)
    no_publication = no_publication_commands()
    blockers_recorded = !isempty(BLOCKER_ROWS)
    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        same_data_waic_blocked &&
        raw_psis_loo_blocked &&
        heldout_kfold_selected &&
        scalar_local_weight_reporting_allowed &&
        !mgmfrm_weight_claims_allowed &&
        !manuscript_sparse_mgmfrm_claims_allowed &&
        Bool(mgmfrm_public_review.summary.current_manifest_guarded_fit_enabled) &&
        blockers_recorded &&
        no_publication

    return (;
        schema =
            "bayesianmgmfrm.gmfrm_prediction_target_and_model_weight_policy.v1",
        family = :gmfrm,
        scope = :prediction_target_and_model_weight_policy,
        status = :prediction_target_and_model_weight_policy_recorded,
        decision = :select_heldout_kfold_for_local_weight_policy,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        broader_public_fit = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        input_artifacts = input_records,
        prediction_target_rows = target_rows,
        model_weight_policy_rows = weight_rows,
        risk_rows = risk_rows(),
        blocker_rows = BLOCKER_ROWS,
        decision_record = (;
            selected_prediction_target = :heldout_observation_log_score,
            same_data_waic_weight_claims_allowed = false,
            raw_psis_loo_weight_claims_allowed = false,
            scalar_local_model_weight_reporting_allowed =
                scalar_local_weight_reporting_allowed,
            mgmfrm_weight_claims_allowed,
            manuscript_sparse_mgmfrm_claims_allowed,
            mgmfrm_fit_allowed =
                Bool(mgmfrm_public_review.summary.current_manifest_guarded_fit_enabled),
            public_exposure_support =
                :scalar_local_weight_policy_recorded_mgmfrm_fit_allowed_claims_blocked,
            interpretation =
                :prediction_target_policy_recorded_with_guarded_mgmfrm_fit_no_weight_claims,
            required_followup = :manual_public_scope_review_for_mgmfrm_fit,
        ),
        summary = (;
            passed,
            policy_recorded = true,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            same_data_waic_blocked,
            raw_psis_loo_blocked,
            heldout_kfold_selected,
            primary_prediction_target = :heldout_observation_log_score,
            exact_loo_or_kfold_review_passed = kfold.summary_passed,
            psis_loo_review_passed = psis.summary_passed,
            waic_influence_review_passed = waic.summary_passed,
            any_high_variance_waic = Bool(waic.summary.any_high_variance_waic),
            any_high_pareto_k = Bool(psis.summary.any_high_pareto_k),
            n_gmfrm_best_model_scenarios =
                kfold.summary.n_gmfrm_best_model_scenarios,
            min_gmfrm_relative_weight =
                kfold.summary.min_gmfrm_relative_weight,
            scalar_local_model_weight_reporting_allowed =
                scalar_local_weight_reporting_allowed,
            public_model_weight_claims_allowed = false,
            mgmfrm_fit_allowed =
                Bool(mgmfrm_public_review.summary.current_manifest_guarded_fit_enabled),
            mgmfrm_weight_claims_allowed,
            manuscript_sparse_mgmfrm_claims_allowed,
            mgmfrm_public_exposure_review_passed =
                mgmfrm_public_review.summary_passed,
            current_mgmfrm_manifest_guarded_fit_enabled =
                Bool(mgmfrm_public_review.summary.current_manifest_guarded_fit_enabled),
            mgmfrm_fit_boundary_checks_passed =
                Bool(mgmfrm_public_review.summary.all_fit_boundary_checks_passed),
            no_publication_commands = no_publication,
            n_input_artifacts = length(input_records),
            n_prediction_target_rows = length(target_rows),
            n_model_weight_policy_rows = length(weight_rows),
            n_risk_rows = length(risk_rows()),
            n_blockers = length(BLOCKER_ROWS),
            remaining_public_blockers =
                [row.blocker for row in BLOCKER_ROWS],
            recommendation =
                :use_heldout_kfold_for_local_weights_keep_mgmfrm_claims_blocked,
            next_gate = :manual_public_scope_review_for_mgmfrm_fit,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " policy_recorded=", artifact.summary.policy_recorded,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
