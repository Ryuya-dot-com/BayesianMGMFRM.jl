#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_pilot_execution_harness.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :mgmfrm_publication_grade_refit_pilot_plan,
        path =
            "test/fixtures/mgmfrm_publication_grade_refit_pilot_plan.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_pilot_plan.v1"),
    (name = :mgmfrm_publication_grade_refit_gate,
        path = "test/fixtures/mgmfrm_publication_grade_refit_gate.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_gate.v1"),
    (name = :mgmfrm_full_heldout_mcmc_refit_fold1_scoring,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_fold1_scoring.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_fold1_scoring.v1"),
    (name = :mgmfrm_full_heldout_mcmc_refit_anchor_scoring,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_anchor_scoring.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_anchor_scoring.v1"),
    (name = :mgmfrm_fit_threshold_q_heldout_linkage,
        path = "test/fixtures/mgmfrm_fit_threshold_q_heldout_linkage.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_fit_threshold_q_heldout_linkage.v1"),
]

const RUNNER_SCRIPT =
    "scripts/run_mgmfrm_publication_grade_refit_job.jl"

const PROTOCOL = (;
    protocol_id =
        "mgmfrm_publication_grade_refit_pilot_execution_harness_v1",
    review_kind =
        :local_publication_grade_refit_pilot_execution_harness,
    publication_or_registration_action = false,
    local_only = true,
    pilot_only = true,
    execution_scope =
        :single_scenario_single_fold_publication_grade_execution_harness,
    selected_scenario = :well_specified_current_q,
    selected_fold = 1,
    source_pilot_plan = :mgmfrm_publication_grade_refit_pilot_plan,
    source_gate = :mgmfrm_publication_grade_refit_gate,
    result_root = "artifacts/publication_grade_refit_pilot",
    runner_script = RUNNER_SCRIPT,
    fit_controls = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 4,
        warmup_per_chain = 500,
        draws_per_chain = 1000,
        target_acceptance = 0.8,
    ),
    thresholds = (;
        require_pilot_plan_passed = true,
        require_gate_passed = true,
        require_fold1_scoring_passed = true,
        require_anchor_scoring_passed = true,
        require_fit_threshold_linkage_passed = true,
        require_execution_jobs_materialized = true,
        require_execution_commands_recorded = true,
        require_runner_state_recorded = true,
        require_result_artifact_targets_recorded = true,
        require_diagnostic_capture_manifest_recorded = true,
        require_comparison_hooks_recorded = true,
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
    Generate the local MGMFRM publication-grade refit pilot execution harness.

    This artifact materializes the job, command-template, result-target,
    diagnostic-capture, and comparison-hook rows needed before running the
    heavy single-cell publication-grade pilot. It does not run MCMC, does not
    create result artifacts, and does not attach external construct evidence.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_pilot_execution_harness.jl [--output PATH]
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
as_symbol(value) = Symbol(String(value))

function artifact_summary(name::Symbol, summary)
    name === :mgmfrm_publication_grade_refit_pilot_plan && return (;
        passed = as_bool(summary[:passed]),
        publication_grade_pilot_plan_recorded =
            as_bool(summary[:publication_grade_pilot_plan_recorded]),
        publication_grade_pilot_executed =
            as_bool(summary[:publication_grade_pilot_executed]),
        selected_units_recorded = as_bool(summary[:selected_units_recorded]),
        all_five_models_selected =
            as_bool(summary[:all_five_models_selected]),
        publication_grade_controls_match_gate =
            as_bool(summary[:publication_grade_controls_match_gate]),
        n_selected_pilot_unit_rows =
            as_int(summary[:n_selected_pilot_unit_rows]),
        n_mcmc_pilot_units = as_int(summary[:n_mcmc_pilot_units]),
        n_analytic_reference_units =
            as_int(summary[:n_analytic_reference_units]),
        planned_chains = as_int(summary[:planned_chains]),
        planned_posterior_draws =
            as_int(summary[:planned_posterior_draws]),
        planned_warmup_iterations =
            as_int(summary[:planned_warmup_iterations]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_publication_grade_refit_gate && return (;
        passed = as_bool(summary[:passed]),
        publication_grade_gate_defined =
            as_bool(summary[:publication_grade_gate_defined]),
        diagnostic_gate_rows_recorded =
            as_bool(summary[:diagnostic_gate_rows_recorded]),
        metric_profile_rows_recorded =
            as_bool(summary[:metric_profile_rows_recorded]),
        pilot_scope_recorded = as_bool(summary[:pilot_scope_recorded]),
        planned_chains_per_unit =
            as_int(summary[:planned_chains_per_unit]),
        planned_draws_per_chain =
            as_int(summary[:planned_draws_per_chain]),
        planned_warmup_per_chain =
            as_int(summary[:planned_warmup_per_chain]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_full_heldout_mcmc_refit_fold1_scoring && return (;
        passed = as_bool(summary[:passed]),
        fold1_heldout_predictive_scores_computed =
            as_bool(summary[:fold1_heldout_predictive_scores_computed]),
        heldout_predictive_scores_computed =
            as_bool(summary[:heldout_predictive_scores_computed]),
        full_mcmc_refit_execution_completed =
            as_bool(summary[:full_mcmc_refit_execution_completed]),
        full_125_unit_batch_completed =
            as_bool(summary[:full_125_unit_batch_completed]),
        publication_grade_diagnostics_blocked =
            as_bool(summary[:publication_grade_diagnostics_blocked]),
        n_candidate_score_rows =
            as_int(summary[:n_candidate_score_rows]),
        n_heldout_pointwise_rows =
            as_int(summary[:n_heldout_pointwise_rows]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_full_heldout_mcmc_refit_anchor_scoring && return (;
        passed = as_bool(summary[:passed]),
        full_125_unit_scoring_completed =
            as_bool(summary[:full_125_unit_scoring_completed]),
        comparison_anchor_scores_computed =
            as_bool(summary[:comparison_anchor_scores_computed]),
        candidate_and_anchor_scores_cover_125_units =
            as_bool(summary[:candidate_and_anchor_scores_cover_125_units]),
        publication_grade_diagnostics_blocked =
            as_bool(summary[:publication_grade_diagnostics_blocked]),
        n_full_execution_units_scored =
            as_int(summary[:n_full_execution_units_scored]),
        n_combined_rank_rows = as_int(summary[:n_combined_rank_rows]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_fit_threshold_q_heldout_linkage && return (;
        passed = as_bool(summary[:passed]),
        no_single_threshold_profile_promoted =
            as_bool(summary[:no_single_threshold_profile_promoted]),
        no_automatic_q_revision =
            as_bool(summary[:no_automatic_q_revision]),
        fold1_observed_rank_recorded =
            as_bool(summary[:fold1_observed_rank_recorded]),
        observed_vs_expected_rank_match_recorded =
            as_bool(summary[:observed_vs_expected_rank_match_recorded]),
        any_observed_expected_mismatch_flagged =
            as_bool(summary[:any_observed_expected_mismatch_flagged]),
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

function load_fixture(path::AbstractString)
    return JSON3.read(read(fixture_path(path), String))
end

rows_as_vector(fixture, key::Symbol) = [row for row in fixture[key]]

function execution_job_rows(plan)
    rows = NamedTuple[]
    for row in rows_as_vector(plan, :selected_pilot_unit_rows)
        unit_id = as_symbol(row[:execution_unit_id])
        mcmc_required = as_bool(row[:mcmc_refit_required])
        analytic_reference = as_bool(row[:analytic_reference_scored])
        unit_path = joinpath(PROTOCOL.result_root, String(unit_id))
        push!(rows, (;
            execution_job_id =
                Symbol("publication_grade__", String(unit_id)),
            execution_unit_id = unit_id,
            scenario = as_symbol(row[:scenario]),
            model = as_symbol(row[:model]),
            fold = as_int(row[:fold]),
            job_kind = mcmc_required ?
                :publication_grade_mcmc_refit :
                :analytic_reference_rescore,
            pilot_role = as_symbol(row[:pilot_role]),
            mcmc_refit_required = mcmc_required,
            analytic_reference_scored = analytic_reference,
            backend = mcmc_required ?
                PROTOCOL.fit_controls.backend : :not_applicable,
            sampler = mcmc_required ?
                PROTOCOL.fit_controls.sampler : :not_applicable,
            chains = mcmc_required ? PROTOCOL.fit_controls.chains : 0,
            warmup_per_chain =
                mcmc_required ? PROTOCOL.fit_controls.warmup_per_chain : 0,
            draws_per_chain =
                mcmc_required ? PROTOCOL.fit_controls.draws_per_chain : 0,
            target_acceptance = mcmc_required ?
                PROTOCOL.fit_controls.target_acceptance : missing,
            pilot_seed = mcmc_required ? as_int(row[:pilot_seed]) : missing,
            n_train_observations = as_int(row[:n_train_observations]),
            n_heldout_observations = as_int(row[:n_heldout_observations]),
            result_artifact_path = string(unit_path, "_result.json"),
            diagnostic_artifact_path =
                string(unit_path, "_diagnostics.json"),
            heldout_score_artifact_path =
                string(unit_path, "_heldout_score.json"),
            runner_script = RUNNER_SCRIPT,
            execution_status = :ready_not_executed,
            publication_grade_pilot_executed = false,
            diagnostics_observed = false,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function execution_command_rows(jobs)
    runner_exists = isfile(fixture_path(RUNNER_SCRIPT))
    rows = NamedTuple[]
    for job in jobs
        base = "julia --project=. $(RUNNER_SCRIPT) --execution-unit $(job.execution_unit_id)"
        command = job.mcmc_refit_required ?
            string(base,
                " --chains $(job.chains)",
                " --warmup-per-chain $(job.warmup_per_chain)",
                " --draws-per-chain $(job.draws_per_chain)",
                " --target-acceptance $(job.target_acceptance)",
                " --seed $(job.pilot_seed)",
                " --output $(job.result_artifact_path)") :
            string(base,
                " --analytic-reference",
                " --output $(job.result_artifact_path)")
        push!(rows, (;
            execution_job_id = job.execution_job_id,
            execution_unit_id = job.execution_unit_id,
            model = job.model,
            runner_script = RUNNER_SCRIPT,
            runner_script_required = true,
            runner_script_exists = runner_exists,
            command,
            command_status =
                runner_exists ? :ready_not_executed : :planned_runner_pending,
            execute_now = false,
            local_only = true,
            publication_or_registration_action = false,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function result_artifact_target_rows(jobs)
    targets = (
        (target = :fit_result, suffix = "_result.json"),
        (target = :diagnostic_summary, suffix = "_diagnostics.json"),
        (target = :heldout_score_summary, suffix = "_heldout_score.json"),
    )
    rows = NamedTuple[]
    for job in jobs
        for target in targets
            push!(rows, (;
                execution_job_id = job.execution_job_id,
                execution_unit_id = job.execution_unit_id,
                model = job.model,
                artifact_target = target.target,
                path = string(joinpath(PROTOCOL.result_root,
                    String(job.execution_unit_id)), target.suffix),
                exists = false,
                required_before_public_claim = true,
                public_claim_allowed = false,
            ))
        end
    end
    return rows
end

function diagnostic_capture_rows(jobs, gate)
    gate_diagnostics = [
        as_symbol(row[:diagnostic])
        for row in gate[:diagnostic_gate_rows]
    ]
    rows = NamedTuple[]
    for job in jobs
        for diagnostic in gate_diagnostics
            applicable =
                job.mcmc_refit_required ||
                diagnostic in (
                    :pointwise_loglikelihood_finite,
                    :expected_score_calibration_recorded,
                )
            push!(rows, (;
                execution_job_id = job.execution_job_id,
                execution_unit_id = job.execution_unit_id,
                scenario = job.scenario,
                model = job.model,
                fold = job.fold,
                diagnostic,
                applicable,
                observed = false,
                passed = false,
                diagnostic_artifact_path = job.diagnostic_artifact_path,
                blocks_public_claim = true,
            ))
        end
    end
    return rows
end

function comparison_hook_rows()
    return [
        (hook = :publication_grade_vs_fold1_smoke_heldout_elpd,
            source_artifact =
                :mgmfrm_full_heldout_mcmc_refit_fold1_scoring,
            target_artifact =
                :mgmfrm_publication_grade_refit_pilot_execution_results,
            comparison_status = :planned_not_executed,
            public_claim_allowed = false),
        (hook = :publication_grade_vs_anchor_scores,
            source_artifact =
                :mgmfrm_full_heldout_mcmc_refit_anchor_scoring,
            target_artifact =
                :mgmfrm_publication_grade_refit_pilot_execution_results,
            comparison_status = :planned_not_executed,
            public_claim_allowed = false),
        (hook = :diagnostic_gate_pass_fail_snapshot,
            source_artifact = :mgmfrm_publication_grade_refit_gate,
            target_artifact =
                :mgmfrm_publication_grade_refit_pilot_execution_results,
            comparison_status = :planned_not_executed,
            public_claim_allowed = false),
        (hook = :fit_threshold_q_heldout_linkage_review,
            source_artifact = :mgmfrm_fit_threshold_q_heldout_linkage,
            target_artifact =
                :mgmfrm_publication_grade_refit_pilot_execution_results,
            comparison_status = :planned_not_executed,
            public_claim_allowed = false),
        (hook = :parameter_absorption_and_q_mismatch_review,
            source_artifact = :mgmfrm_fit_threshold_q_heldout_linkage,
            target_artifact =
                :mgmfrm_publication_grade_refit_pilot_execution_results,
            comparison_status = :planned_not_executed,
            public_claim_allowed = false),
    ]
end

function blocker_rows(runner_materialized::Bool)
    return [
        (blocker = :publication_grade_runner_not_materialized,
            blocks = :pilot_execution,
            resolved = runner_materialized),
        (blocker = :publication_grade_pilot_not_executed,
            blocks = :pilot_runtime_and_diagnostic_assessment,
            resolved = false),
        (blocker = :diagnostics_not_observed,
            blocks = :public_fit_metric_and_model_comparison_claims,
            resolved = false),
        (blocker =
                :fit_metric_thresholds_not_reestimated_under_publication_grade_draws,
            blocks = :threshold_comparison_and_claim_calibration,
            resolved = false),
        (blocker = :full_125_unit_publication_grade_batch_not_executed,
            blocks = :public_kfold_model_comparison_claims,
            resolved = false),
        (blocker = :external_construct_dataset_missing,
            blocks = :public_construct_or_q_revision_claims,
            resolved = false),
        (blocker = :independent_public_scope_review_missing,
            blocks = :all_public_mgmfrm_claims,
            resolved = false),
    ]
end

function no_publication_commands(commands)
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    return all(commands) do row
        lowered = lowercase(String(row.command))
        Bool(row.local_only) &&
            !Bool(row.publication_or_registration_action) &&
            all(!occursin(lowercase(term), lowered) for term in banned)
    end
end

function build_artifact()
    records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    plan_record =
        record_by_name(records, :mgmfrm_publication_grade_refit_pilot_plan)
    gate_record =
        record_by_name(records, :mgmfrm_publication_grade_refit_gate)
    fold1_scoring_record =
        record_by_name(records,
            :mgmfrm_full_heldout_mcmc_refit_fold1_scoring)
    anchor_scoring_record =
        record_by_name(records,
            :mgmfrm_full_heldout_mcmc_refit_anchor_scoring)
    threshold_linkage_record =
        record_by_name(records, :mgmfrm_fit_threshold_q_heldout_linkage)

    plan =
        load_fixture(
            "test/fixtures/mgmfrm_publication_grade_refit_pilot_plan.json")
    gate = load_fixture("test/fixtures/mgmfrm_publication_grade_refit_gate.json")

    jobs = execution_job_rows(plan)
    commands = execution_command_rows(jobs)
    targets = result_artifact_target_rows(jobs)
    diagnostics = diagnostic_capture_rows(jobs, gate)
    comparisons = comparison_hook_rows()
    runner_materialized =
        !isempty(commands) && all(row -> Bool(row.runner_script_exists), commands)
    blockers = blocker_rows(runner_materialized)
    no_publication = no_publication_commands(commands)

    all_input_artifacts_present = all(record -> record.exists, records)
    all_expected_schemas = all(record -> record.schema_matches, records)
    all_input_summaries_passed = all(record -> record.summary_passed, records)
    pilot_plan_passed = Bool(plan_record.summary.passed)
    gate_passed = Bool(gate_record.summary.passed)
    fold1_scoring_passed = Bool(fold1_scoring_record.summary.passed)
    anchor_scoring_passed = Bool(anchor_scoring_record.summary.passed)
    fit_threshold_linkage_passed = Bool(threshold_linkage_record.summary.passed)
    execution_jobs_materialized =
        length(jobs) == Int(plan_record.summary.n_selected_pilot_unit_rows) &&
        count(row -> Bool(row.mcmc_refit_required), jobs) ==
            Int(plan_record.summary.n_mcmc_pilot_units) &&
        count(row -> Bool(row.analytic_reference_scored), jobs) ==
            Int(plan_record.summary.n_analytic_reference_units) &&
        all(row -> row.scenario === PROTOCOL.selected_scenario, jobs) &&
        all(row -> row.fold == PROTOCOL.selected_fold, jobs)
    execution_commands_recorded =
        length(commands) == length(jobs) &&
        all(row -> Bool(row.runner_script_required), commands) &&
        all(row -> !Bool(row.execute_now), commands)
    runner_state_recorded =
        all(row -> hasproperty(row, :runner_script_exists), commands)
    result_artifact_targets_recorded =
        length(targets) == 3 * length(jobs) &&
        all(row -> Bool(row.required_before_public_claim), targets)
    diagnostic_capture_manifest_recorded =
        length(diagnostics) ==
            length(jobs) * length(gate[:diagnostic_gate_rows]) &&
        all(row -> Bool(row.blocks_public_claim), diagnostics)
    comparison_hooks_recorded =
        length(comparisons) == 5 &&
        all(row -> Bool(row.public_claim_allowed) == false, comparisons)
    publication_grade_pilot_executed = false
    full_125_unit_publication_grade_batch_completed = false
    external_construct_dataset_still_required = true
    no_public_fit_metric_claim = true
    no_public_q_revision_claim = true
    no_public_model_weight_claim = true
    no_sparse_superiority_claim = true

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        pilot_plan_passed &&
        gate_passed &&
        fold1_scoring_passed &&
        anchor_scoring_passed &&
        fit_threshold_linkage_passed &&
        execution_jobs_materialized &&
        execution_commands_recorded &&
        runner_state_recorded &&
        result_artifact_targets_recorded &&
        diagnostic_capture_manifest_recorded &&
        comparison_hooks_recorded &&
        !publication_grade_pilot_executed &&
        !full_125_unit_publication_grade_batch_completed &&
        external_construct_dataset_still_required &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim &&
        no_publication

    n_mcmc_jobs = count(row -> Bool(row.mcmc_refit_required), jobs)
    n_review_cells =
        length(jobs) + length(commands) + length(targets) +
        length(diagnostics) + length(comparisons)
    selected_decision = runner_materialized ?
        :record_execution_harness_runner_materialized_before_heavy_refit :
        :record_execution_harness_before_materializing_runner_or_heavy_refit
    required_followup = runner_materialized ?
        :execute_publication_grade_refit_pilot_or_attach_external_construct_dataset :
        :materialize_publication_grade_refit_runner_or_attach_external_construct_dataset
    recommendation = runner_materialized ?
        :execute_single_cell_publication_grade_pilot_or_attach_external_dataset :
        :materialize_runner_then_execute_single_cell_publication_grade_pilot_or_attach_external_dataset

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_pilot_execution_harness.v1",
        family = :mgmfrm,
        scope = :publication_grade_refit_pilot_execution_harness,
        status =
            :publication_grade_refit_pilot_execution_harness_recorded,
        decision =
            :record_publication_grade_refit_pilot_execution_harness,
        public_fit = true,
        experimental_public = true,
        fit_ready = runner_materialized,
        harness_ready = true,
        execution_ready = runner_materialized,
        local_only = true,
        pilot_only = true,
        publication_or_registration_action = false,
        publication_grade_gate_defined = true,
        publication_grade_pilot_plan_recorded = true,
        publication_grade_pilot_execution_harness_recorded = true,
        publication_grade_pilot_runner_materialized = runner_materialized,
        publication_grade_pilot_executed,
        full_125_unit_publication_grade_batch_completed,
        external_construct_dataset_attached = false,
        external_construct_validation_completed = false,
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
        execution_job_rows = jobs,
        execution_command_rows = commands,
        result_artifact_target_rows = targets,
        diagnostic_capture_rows = diagnostics,
        comparison_hook_rows = comparisons,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision,
            publication_grade_gate_defined = true,
            publication_grade_pilot_plan_recorded = true,
            publication_grade_pilot_execution_harness_recorded = true,
            publication_grade_pilot_runner_materialized = runner_materialized,
            publication_grade_pilot_executed,
            full_125_unit_publication_grade_batch_completed,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            required_followup,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            pilot_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            pilot_plan_passed,
            gate_passed,
            fold1_scoring_passed,
            anchor_scoring_passed,
            fit_threshold_linkage_passed,
            publication_grade_gate_defined = true,
            publication_grade_pilot_plan_recorded = true,
            publication_grade_pilot_execution_harness_recorded = true,
            publication_grade_pilot_runner_materialized = runner_materialized,
            execution_jobs_materialized,
            execution_commands_recorded,
            runner_state_recorded,
            result_artifact_targets_recorded,
            diagnostic_capture_manifest_recorded,
            comparison_hooks_recorded,
            publication_grade_pilot_executed,
            full_125_unit_publication_grade_batch_completed,
            external_construct_dataset_attached = false,
            external_construct_validation_completed = false,
            external_construct_dataset_still_required,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            n_input_artifacts = length(records),
            n_execution_job_rows = length(jobs),
            n_mcmc_execution_jobs = n_mcmc_jobs,
            n_analytic_reference_jobs = length(jobs) - n_mcmc_jobs,
            n_execution_command_rows = length(commands),
            n_result_artifact_target_rows = length(targets),
            n_diagnostic_capture_rows = length(diagnostics),
            n_comparison_hook_rows = length(comparisons),
            n_blocker_rows = length(blockers),
            n_review_cells,
            planned_chains =
                n_mcmc_jobs * PROTOCOL.fit_controls.chains,
            planned_posterior_draws =
                n_mcmc_jobs * PROTOCOL.fit_controls.chains *
                PROTOCOL.fit_controls.draws_per_chain,
            planned_warmup_iterations =
                n_mcmc_jobs * PROTOCOL.fit_controls.chains *
                PROTOCOL.fit_controls.warmup_per_chain,
            n_blockers = length(blockers),
            remaining_public_blockers =
                [row.blocker for row in blockers if !row.resolved],
            recommendation,
            next_gate = required_followup,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " jobs=", artifact.summary.n_execution_job_rows,
        " runner_materialized=",
        artifact.summary.publication_grade_pilot_runner_materialized,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
