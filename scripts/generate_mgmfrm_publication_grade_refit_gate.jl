#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_gate.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :mgmfrm_full_heldout_mcmc_refit_execution_plan,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_execution_plan.v1"),
    (name = :mgmfrm_full_heldout_mcmc_refit_anchor_scoring,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_anchor_scoring.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_anchor_scoring.v1"),
    (name = :mgmfrm_validation_split_model_comparison_policy,
        path =
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_validation_split_model_comparison_policy.v1"),
    (name = :mgmfrm_fit_threshold_q_heldout_linkage,
        path = "test/fixtures/mgmfrm_fit_threshold_q_heldout_linkage.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_fit_threshold_q_heldout_linkage.v1"),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_publication_grade_refit_gate_v1",
    review_kind = :local_publication_grade_refit_gate_definition,
    publication_or_registration_action = false,
    local_only = true,
    gate_scope =
        :publication_grade_refit_diagnostics_or_external_construct_dataset_review,
    refit_split = :observation_kfold,
    pilot_scope = :one_scenario_one_fold_all_comparison_models,
    pilot_scenario = :well_specified_current_q,
    pilot_fold = 1,
    full_batch_scope = :five_scenarios_five_folds_five_models,
    fit_controls = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 4,
        warmup_per_chain = 500,
        draws_per_chain = 1000,
        target_acceptance = 0.8,
    ),
    thresholds = (;
        require_input_artifacts_passed = true,
        require_anchor_scoring_completed = true,
        require_diagnostic_gate_rows_recorded = true,
        require_metric_profile_rows_recorded = true,
        require_pilot_scope_recorded = true,
        require_claim_rules_block_public_claims = true,
        require_publication_grade_pilot_not_yet_executed = true,
        require_full_batch_not_yet_executed = true,
        require_external_construct_dataset_still_required = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_q_revision_claim = true,
        require_no_public_model_weight_claim = true,
        require_no_sparse_superiority_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM publication-grade refit gate artifact.

    This artifact fixes the diagnostic, metric, pilot-scope, and claim-blocking
    conditions that must be satisfied before descriptive heldout scoring can be
    used for public MGMFRM claims. It does not run publication-grade MCMC and
    it does not attach external construct-validation evidence.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_gate.jl [--output PATH]
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
    name === :mgmfrm_full_heldout_mcmc_refit_execution_plan && return (;
        passed = as_bool(summary[:passed]),
        full_mcmc_refit_execution_plan_recorded =
            as_bool(summary[:full_mcmc_refit_execution_plan_recorded]),
        full_mcmc_refit_execution_completed =
            as_bool(summary[:full_mcmc_refit_execution_completed]),
        all_scenario_model_fold_units_materialized =
            as_bool(summary[:all_scenario_model_fold_units_materialized]),
        n_execution_unit_rows = as_int(summary[:n_execution_unit_rows]),
        n_planned_posterior_draws =
            as_int(summary[:n_planned_posterior_draws]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_full_heldout_mcmc_refit_anchor_scoring && return (;
        passed = as_bool(summary[:passed]),
        full_125_unit_scoring_completed =
            as_bool(summary[:full_125_unit_scoring_completed]),
        full_heldout_predictive_scores_computed =
            as_bool(summary[:full_heldout_predictive_scores_computed]),
        comparison_anchor_scores_computed =
            as_bool(summary[:comparison_anchor_scores_computed]),
        publication_grade_diagnostics_blocked =
            as_bool(summary[:publication_grade_diagnostics_blocked]),
        n_full_execution_units_scored =
            as_int(summary[:n_full_execution_units_scored]),
        n_combined_rank_rows = as_int(summary[:n_combined_rank_rows]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_validation_split_model_comparison_policy && return (;
        passed = as_bool(summary[:passed]),
        primary_holdout_target_selected =
            as_bool(summary[:primary_holdout_target_selected]),
        split_policy_recorded = as_bool(summary[:split_policy_recorded]),
        comparison_model_set_recorded =
            as_bool(summary[:comparison_model_set_recorded]),
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        no_model_weight_or_sparse_superiority_claim =
            as_bool(summary[:no_model_weight_or_sparse_superiority_claim]),
    )
    name === :mgmfrm_fit_threshold_q_heldout_linkage && return (;
        passed = as_bool(summary[:passed]),
        no_single_threshold_profile_promoted =
            as_bool(summary[:no_single_threshold_profile_promoted]),
        no_automatic_q_revision =
            as_bool(summary[:no_automatic_q_revision]),
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        no_public_model_weight_claim =
            as_bool(summary[:no_public_model_weight_claim]),
        no_sparse_superiority_claim =
            as_bool(summary[:no_sparse_superiority_claim]),
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

function diagnostic_gate_rows()
    return [
        (diagnostic = :chains_min, threshold = 4.0,
            comparison = :greater_or_equal, source = :fit_controls,
            required_for_pilot = true, required_for_full_batch = true,
            public_claim_blocked_if_missing = true),
        (diagnostic = :warmup_per_chain_min, threshold = 500.0,
            comparison = :greater_or_equal, source = :fit_controls,
            required_for_pilot = true, required_for_full_batch = true,
            public_claim_blocked_if_missing = true),
        (diagnostic = :draws_per_chain_min, threshold = 1000.0,
            comparison = :greater_or_equal, source = :fit_controls,
            required_for_pilot = true, required_for_full_batch = true,
            public_claim_blocked_if_missing = true),
        (diagnostic = :rank_normalized_rhat_max, threshold = 1.01,
            comparison = :less_or_equal, source = :posterior_diagnostics,
            required_for_pilot = true, required_for_full_batch = true,
            public_claim_blocked_if_missing = true),
        (diagnostic = :ess_bulk_min, threshold = 400.0,
            comparison = :greater_or_equal, source = :posterior_diagnostics,
            required_for_pilot = true, required_for_full_batch = true,
            public_claim_blocked_if_missing = true),
        (diagnostic = :ess_tail_min, threshold = 400.0,
            comparison = :greater_or_equal, source = :posterior_diagnostics,
            required_for_pilot = true, required_for_full_batch = true,
            public_claim_blocked_if_missing = true),
        (diagnostic = :divergence_count_max, threshold = 0.0,
            comparison = :equal, source = :hmc_diagnostics,
            required_for_pilot = true, required_for_full_batch = true,
            public_claim_blocked_if_missing = true),
        (diagnostic = :max_treedepth_count_max, threshold = 0.0,
            comparison = :equal, source = :hmc_diagnostics,
            required_for_pilot = true, required_for_full_batch = true,
            public_claim_blocked_if_missing = true),
        (diagnostic = :ebfmi_min, threshold = 0.3,
            comparison = :greater_or_equal, source = :hmc_diagnostics,
            required_for_pilot = true, required_for_full_batch = true,
            public_claim_blocked_if_missing = true),
        (diagnostic = :pointwise_loglikelihood_finite, threshold = 1.0,
            comparison = :boolean_true, source = :heldout_scoring,
            required_for_pilot = true, required_for_full_batch = true,
            public_claim_blocked_if_missing = true),
        (diagnostic = :posterior_predictive_check_recorded, threshold = 1.0,
            comparison = :boolean_true, source = :posterior_predictive_check,
            required_for_pilot = true, required_for_full_batch = true,
            public_claim_blocked_if_missing = true),
        (diagnostic = :expected_score_calibration_recorded, threshold = 1.0,
            comparison = :boolean_true, source = :calibration,
            required_for_pilot = true, required_for_full_batch = true,
            public_claim_blocked_if_missing = true),
    ]
end

function metric_profile_rows()
    return [
        (metric = :heldout_elpd,
            role = :primary_prediction_score,
            threshold_policy = :no_universal_cutoff,
            compared_to = :candidate_and_anchor_models,
            public_claim_allowed_from_pilot_alone = false),
        (metric = :kfoldic,
            role = :derived_predictive_summary,
            threshold_policy = :descriptive_only,
            compared_to = :candidate_and_anchor_models,
            public_claim_allowed_from_pilot_alone = false),
        (metric = :posterior_infit_outfit,
            role = :bayesian_residual_screening,
            threshold_policy = :named_profile_required,
            compared_to = :mfrm_baseline_and_mgmfrm_ppc,
            public_claim_allowed_from_pilot_alone = false),
        (metric = :posterior_predictive_category_use,
            role = :category_functioning_check,
            threshold_policy = :scenario_sensitivity_required,
            compared_to = :observed_category_use,
            public_claim_allowed_from_pilot_alone = false),
        (metric = :expected_score_mae_rmse_bias,
            role = :calibration_and_score_residual_check,
            threshold_policy = :simulation_calibration_required,
            compared_to = :candidate_and_anchor_models,
            public_claim_allowed_from_pilot_alone = false),
        (metric = :q_recovery_or_mismatch_flag,
            role = :q_matrix_sensitivity_context,
            threshold_policy = :no_automatic_q_revision,
            compared_to = :known_truth_simulation_conditions,
            public_claim_allowed_from_pilot_alone = false),
    ]
end

function pilot_scope_rows()
    return [
        (pilot_stage = :single_cell_publication_grade_pilot,
            scenario = PROTOCOL.pilot_scenario,
            fold = PROTOCOL.pilot_fold,
            models = [
                :scalar_gmfrm_baseline,
                :confirmatory_mgmfrm_current_q,
                :sparse_mgmfrm_current_q,
                :construct_reviewed_revised_q_mgmfrm,
                :null_or_intercept_reference,
            ],
            purpose =
                :estimate_runtime_and_diagnostics_before_full_125_unit_batch,
            public_claim_allowed = false),
        (pilot_stage = :scenario_coverage_expansion,
            scenario = :all_five_scenarios,
            fold = PROTOCOL.pilot_fold,
            models = [
                :scalar_gmfrm_baseline,
                :confirmatory_mgmfrm_current_q,
                :sparse_mgmfrm_current_q,
                :construct_reviewed_revised_q_mgmfrm,
                :null_or_intercept_reference,
            ],
            purpose = :check_scenario_specific_metric_direction_changes,
            public_claim_allowed = false),
        (pilot_stage = :full_kfold_batch,
            scenario = :all_five_scenarios,
            fold = :all_five_folds,
            models = [
                :scalar_gmfrm_baseline,
                :confirmatory_mgmfrm_current_q,
                :sparse_mgmfrm_current_q,
                :construct_reviewed_revised_q_mgmfrm,
                :null_or_intercept_reference,
            ],
            purpose = :publication_grade_descriptive_model_comparison,
            public_claim_allowed = false),
    ]
end

function claim_rule_rows()
    return [
        (claim = :fit_metric_threshold_interpretation,
            required_before_public_claim =
                :named_threshold_profile_and_publication_grade_refit,
            pilot_sufficient = false, public_claim_allowed = false),
        (claim = :model_weight_or_best_model,
            required_before_public_claim =
                :full_kfold_refit_plus_sensitivity_and_independent_review,
            pilot_sufficient = false, public_claim_allowed = false),
        (claim = :sparse_mgmfrm_superiority,
            required_before_public_claim =
                :known_truth_simulation_and_full_kfold_refit,
            pilot_sufficient = false, public_claim_allowed = false),
        (claim = :q_matrix_revision,
            required_before_public_claim =
                :external_construct_validation_or_controlled_q_recovery,
            pilot_sufficient = false, public_claim_allowed = false),
        (claim = :general_mgmfrm_readiness,
            required_before_public_claim =
                :publication_grade_refit_diagnostics_and_scope_review,
            pilot_sufficient = false, public_claim_allowed = false),
    ]
end

function blocker_rows()
    return [
        (blocker = :publication_grade_pilot_not_executed,
            blocks = :first_runtime_and_diagnostic_assessment,
            resolved = false),
        (blocker = :full_125_unit_publication_grade_batch_not_executed,
            blocks = :public_heldout_model_comparison_claims,
            resolved = false),
        (blocker = :external_construct_dataset_missing,
            blocks = :public_construct_or_q_revision_claims,
            resolved = false),
        (blocker = :independent_public_scope_review_missing,
            blocks = :all_public_mgmfrm_claims,
            resolved = false),
    ]
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_publication_grade_refit_gate.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    execution_plan =
        record_by_name(records,
            :mgmfrm_full_heldout_mcmc_refit_execution_plan)
    anchor_scoring =
        record_by_name(records,
            :mgmfrm_full_heldout_mcmc_refit_anchor_scoring)
    split_policy =
        record_by_name(records,
            :mgmfrm_validation_split_model_comparison_policy)
    linkage =
        record_by_name(records, :mgmfrm_fit_threshold_q_heldout_linkage)

    diagnostics = diagnostic_gate_rows()
    metrics = metric_profile_rows()
    pilot_scope = pilot_scope_rows()
    claims = claim_rule_rows()
    blockers = blocker_rows()
    no_publication = no_publication_commands()

    all_input_artifacts_present = all(record -> record.exists, records)
    all_expected_schemas = all(record -> record.schema_matches, records)
    all_input_summaries_passed = all(record -> record.summary_passed, records)
    anchor_scoring_completed =
        Bool(anchor_scoring.summary.full_125_unit_scoring_completed) &&
        Bool(anchor_scoring.summary.full_heldout_predictive_scores_computed) &&
        Bool(anchor_scoring.summary.comparison_anchor_scores_computed)
    diagnostic_gate_rows_recorded =
        length(diagnostics) == 12 &&
        all(row -> Bool(row.required_for_pilot), diagnostics)
    metric_profile_rows_recorded =
        length(metrics) == 6 &&
        all(row -> !Bool(row.public_claim_allowed_from_pilot_alone), metrics)
    pilot_scope_recorded =
        length(pilot_scope) == 3 &&
        pilot_scope[1].scenario === PROTOCOL.pilot_scenario &&
        pilot_scope[1].fold == PROTOCOL.pilot_fold
    claim_rules_block_public_claims =
        all(row -> !Bool(row.public_claim_allowed), claims)
    no_public_fit_metric_claim =
        Bool(split_policy.summary.no_public_fit_metric_claim) &&
        Bool(linkage.summary.no_public_fit_metric_claim)
    no_public_q_revision_claim =
        Bool(split_policy.summary.no_public_q_revision_claim) &&
        Bool(linkage.summary.no_public_q_revision_claim)
    no_public_model_weight_claim =
        Bool(split_policy.summary.no_model_weight_or_sparse_superiority_claim) &&
        Bool(linkage.summary.no_public_model_weight_claim)
    no_sparse_superiority_claim =
        Bool(split_policy.summary.no_model_weight_or_sparse_superiority_claim) &&
        Bool(linkage.summary.no_sparse_superiority_claim)
    publication_grade_pilot_executed = false
    full_125_unit_publication_grade_batch_completed = false
    external_construct_dataset_attached = false
    external_construct_validation_completed = false

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        Bool(execution_plan.summary.full_mcmc_refit_execution_plan_recorded) &&
        anchor_scoring_completed &&
        diagnostic_gate_rows_recorded &&
        metric_profile_rows_recorded &&
        pilot_scope_recorded &&
        claim_rules_block_public_claims &&
        !publication_grade_pilot_executed &&
        !full_125_unit_publication_grade_batch_completed &&
        !external_construct_dataset_attached &&
        !external_construct_validation_completed &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim &&
        no_publication

    n_review_cells =
        length(diagnostics) + length(metrics) + length(pilot_scope) +
        length(claims)

    return (;
        schema = "bayesianmgmfrm.mgmfrm_publication_grade_refit_gate.v1",
        family = :mgmfrm,
        scope = :publication_grade_refit_gate,
        status = :publication_grade_refit_gate_defined,
        decision =
            :record_publication_grade_refit_diagnostics_and_pilot_scope,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        publication_or_registration_action = false,
        publication_grade_gate_defined = true,
        publication_grade_pilot_executed,
        full_125_unit_publication_grade_batch_completed,
        external_construct_dataset_attached,
        external_construct_validation_completed,
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
        diagnostic_gate_rows = diagnostics,
        metric_profile_rows = metrics,
        pilot_scope_rows = pilot_scope,
        claim_rule_rows = claims,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :record_publication_grade_refit_gate_before_running_heavy_pilot,
            gate_definition_recorded = true,
            anchor_scoring_completed,
            publication_grade_pilot_executed,
            full_125_unit_publication_grade_batch_completed,
            external_construct_dataset_attached,
            external_construct_validation_completed,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            required_followup =
                :publication_grade_refit_pilot_plan,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            execution_plan_passed = Bool(execution_plan.summary.passed),
            anchor_scoring_passed = Bool(anchor_scoring.summary.passed),
            validation_split_policy_passed = Bool(split_policy.summary.passed),
            fit_threshold_q_heldout_linkage_passed =
                Bool(linkage.summary.passed),
            publication_grade_gate_defined = true,
            anchor_scoring_completed,
            diagnostic_gate_rows_recorded,
            metric_profile_rows_recorded,
            pilot_scope_recorded,
            claim_rules_block_public_claims,
            publication_grade_pilot_required = true,
            publication_grade_pilot_executed,
            full_125_unit_publication_grade_batch_completed,
            external_construct_dataset_attached,
            external_construct_validation_completed,
            external_construct_dataset_still_required = true,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            n_input_artifacts = length(records),
            n_diagnostic_gate_rows = length(diagnostics),
            n_metric_profile_rows = length(metrics),
            n_pilot_scope_rows = length(pilot_scope),
            n_claim_rule_rows = length(claims),
            n_blocker_rows = length(blockers),
            n_review_cells,
            n_planned_full_execution_units =
                Int(execution_plan.summary.n_execution_unit_rows),
            n_anchor_scored_execution_units =
                Int(anchor_scoring.summary.n_full_execution_units_scored),
            planned_chains_per_unit = PROTOCOL.fit_controls.chains,
            planned_draws_per_chain = PROTOCOL.fit_controls.draws_per_chain,
            planned_warmup_per_chain =
                PROTOCOL.fit_controls.warmup_per_chain,
            n_blockers = length(blockers),
            remaining_public_blockers =
                [row.blocker for row in blockers if !row.resolved],
            recommendation =
                :freeze_gate_and_prepare_single_cell_publication_grade_pilot,
            next_gate = :publication_grade_refit_pilot_plan,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=$(artifact.summary.passed) diagnostics=$(artifact.summary.n_diagnostic_gate_rows) next_gate=$(artifact.summary.next_gate)")
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
