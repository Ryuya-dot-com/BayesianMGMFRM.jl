#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const RESULT_ROOT =
    joinpath(ROOT, "artifacts", "publication_grade_refit_batch")
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_well_specified_scenario_execution_review.json")
const DEFAULT_PLAN =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_batch_expansion_plan.json")
const DEFAULT_MANIFEST =
    joinpath(ROOT, "artifacts", "publication_grade_refit_batch",
        "orchestrator_well_specified_scenario_brms_like.json")
const SCENARIO = :well_specified_current_q

include(joinpath(@__DIR__, "local_json.jl"))

const EXPECTED_SCHEMAS = (;
    plan =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_expansion_plan.v1",
    manifest =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_orchestrator_run.v1",
    result =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_result.v1",
    diagnostics =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_diagnostics.v1",
    heldout =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_heldout_score.v1",
)

function usage()
    return """
    Generate the local well-specified scenario execution review.

    This reads all 25 well_specified_current_q batch-runner artifacts and the
    scenario-level orchestrator manifest. Raw runner artifacts remain ignored;
    this script writes a compact tracked evidence summary.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_well_specified_scenario_execution_review.jl [--output PATH]

    Options:
      --output PATH       Review fixture path.
      --plan PATH         Batch expansion plan fixture path.
      --manifest PATH     Batch orchestrator scenario manifest path.
      --result-root PATH  Directory containing local batch runner artifacts.
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    plan = DEFAULT_PLAN
    manifest = DEFAULT_MANIFEST
    result_root = RESULT_ROOT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg == "--plan"
            index < length(args) || error("--plan requires a path")
            plan = abspath(args[index + 1])
            index += 2
        elseif arg == "--manifest"
            index < length(args) || error("--manifest requires a path")
            manifest = abspath(args[index + 1])
            index += 2
        elseif arg == "--result-root"
            index < length(args) || error("--result-root requires a path")
            result_root = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; output, plan, manifest, result_root)
end

project_version() = String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)

as_bool(value) = Bool(value)
as_float(value) = Float64(value)
as_int(value) = Int(value)
as_string(value) = String(value)
as_symbol(value) = Symbol(String(value))

function load_json(path::AbstractString)
    isfile(path) || error("required local artifact is missing: $(rel(path))")
    return JSON3.read(read(path, String))
end

function json_get(object, key::Symbol, default = missing)
    haskey(object, key) || return default
    value = object[key]
    value === nothing && return default
    ismissing(value) && return default
    return value
end

function json_bool(object, key::Symbol, default::Bool = false)
    value = json_get(object, key, missing)
    ismissing(value) && return default
    return Bool(value)
end

function json_int(object, key::Symbol, default::Int = 0)
    value = json_get(object, key, missing)
    ismissing(value) && return default
    return Int(value)
end

function json_float_or_missing(object, key::Symbol)
    value = json_get(object, key, missing)
    ismissing(value) && return missing
    return Float64(value)
end

function native_scalar(value)
    value === nothing && return missing
    ismissing(value) && return missing
    value isa Bool && return Bool(value)
    value isa Integer && return Int(value)
    value isa AbstractFloat && return Float64(value)
    value isa AbstractString && return String(value)
    value isa Symbol && return value
    return String(value)
end

function model_role(model::Symbol)
    model === :scalar_gmfrm_baseline && return :scalar
    model === :confirmatory_mgmfrm_current_q && return :confirmatory
    model === :sparse_mgmfrm_current_q && return :sparse
    model === :construct_reviewed_revised_q_mgmfrm &&
        return :construct_reviewed_revised_q
    model === :null_or_intercept_reference && return :analytic_reference
    return model
end

function scenario_plan_jobs(plan)
    rows = NamedTuple[]
    for row in plan[:batch_execution_job_rows]
        as_symbol(row[:scenario]) === SCENARIO || continue
        model = as_symbol(row[:model])
        push!(rows, (;
            execution_unit_id = as_symbol(row[:execution_unit_id]),
            scenario = SCENARIO,
            model,
            role = model_role(model),
            fold = Int(row[:fold]),
            mcmc_refit_required = Bool(row[:mcmc_refit_required]),
            analytic_reference_scored = Bool(row[:analytic_reference_scored]),
            target_acceptance = json_float_or_missing(row, :target_acceptance),
            chains = Int(row[:chains]),
            warmup_per_chain = Int(row[:warmup_per_chain]),
            draws_per_chain = Int(row[:draws_per_chain]),
        ))
    end
    return sort(rows; by = row -> (row.fold, String(row.model)))
end

function paths_for_job(result_root::AbstractString, job)
    stem = joinpath(result_root, string(job.execution_unit_id))
    return (;
        result = string(stem, "_result.json"),
        diagnostics = string(stem, "_diagnostics.json"),
        heldout = string(stem, "_heldout_score.json"),
    )
end

function plan_input_record(path::AbstractString, plan)
    summary = plan[:summary]
    schema = as_string(plan[:schema])
    return (;
        artifact = :mgmfrm_publication_grade_refit_batch_expansion_plan,
        path = rel(path),
        exists = true,
        sha256 = file_sha256(path),
        schema,
        expected_schema = EXPECTED_SCHEMAS.plan,
        schema_matches = schema == EXPECTED_SCHEMAS.plan,
        summary_passed = json_bool(summary, :passed),
        batch_execution_ready_local_only =
            json_bool(summary, :batch_execution_ready_local_only),
        scalar_target_acceptance =
            json_float_or_missing(summary, :scalar_target_acceptance),
        n_batch_execution_job_rows =
            json_int(summary, :n_batch_execution_job_rows),
        planned_warmup_iterations =
            json_int(summary, :planned_warmup_iterations),
    )
end

function manifest_input_record(path::AbstractString, manifest)
    summary = manifest[:summary]
    schema = as_string(manifest[:schema])
    return (;
        artifact = :mgmfrm_publication_grade_refit_batch_orchestrator_run,
        path = rel(path),
        exists = true,
        sha256 = file_sha256(path),
        schema,
        expected_schema = EXPECTED_SCHEMAS.manifest,
        schema_matches = schema == EXPECTED_SCHEMAS.manifest,
        summary_passed = json_bool(summary, :passed),
        action = as_symbol(summary[:action]),
        n_plan_jobs = json_int(summary, :n_plan_jobs),
        n_matching_jobs = json_int(summary, :n_matching_jobs),
        n_selected_for_action = json_int(summary, :n_selected_for_action),
        n_attempted_jobs = json_int(summary, :n_attempted_jobs),
        n_failed_jobs = json_int(summary, :n_failed_jobs),
        n_successful_action_jobs =
            json_int(summary, :n_successful_action_jobs),
        n_skipped_jobs = json_int(summary, :n_skipped_jobs),
        n_complete_after =
            json_int(summary[:status_after], :complete_executed),
        n_pending_after = json_int(summary[:status_after], :pending),
        next_gate = as_symbol(summary[:next_gate]),
    )
end

function artifact_record(kind::Symbol, path::AbstractString,
        artifact, expected_schema::AbstractString)
    schema = as_string(artifact[:schema])
    summary = artifact[:summary]
    return (;
        kind,
        path = rel(path),
        exists = true,
        sha256 = file_sha256(path),
        schema,
        expected_schema,
        schema_matches = schema == expected_schema,
        status = json_get(artifact, :status, :unknown),
        summary_passed = json_bool(summary, :passed),
        executed = json_bool(summary, :executed),
        dry_run = json_bool(summary, :dry_run),
        diagnostic_gate_passed =
            json_bool(summary, :diagnostic_gate_passed),
        public_claim_allowed = json_bool(summary, :public_claim_allowed),
    )
end

function diagnostic_failure_rows(job, diagnostics)
    rows = NamedTuple[]
    for row in diagnostics[:diagnostic_rows]
        applicable = Bool(row[:applicable])
        observed = Bool(row[:observed])
        passed = Bool(row[:passed])
        applicable || continue
        observed || continue
        passed && continue
        push!(rows, (;
            execution_unit_id = job.execution_unit_id,
            scenario = job.scenario,
            model = job.model,
            fold = job.fold,
            diagnostic = as_symbol(row[:diagnostic]),
            source = as_symbol(row[:source]),
            comparison = as_symbol(row[:comparison]),
            threshold = native_scalar(row[:threshold]),
            value = native_scalar(row[:value]),
            observed,
            applicable,
            passed,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function job_review_row(job, result, diagnostics, heldout)
    score = result[:score_row]
    result_summary = result[:summary]
    diagnostic_summary = diagnostics[:summary]
    heldout_summary = heldout[:summary]
    mcmc = Bool(job.mcmc_refit_required)
    return (;
        execution_unit_id = job.execution_unit_id,
        role = job.role,
        scenario = as_symbol(score[:scenario]),
        model = job.model,
        fold = Int(score[:fold]),
        model_family = as_symbol(score[:model_family]),
        mcmc_refit_required = mcmc,
        analytic_reference_scored = Bool(job.analytic_reference_scored),
        executed = Bool(result_summary[:executed]),
        dry_run = Bool(result_summary[:dry_run]),
        artifacts_complete = true,
        diagnostic_gate_passed = Bool(result_summary[:diagnostic_gate_passed]),
        diagnostics_observed =
            mcmc ? Int(diagnostic_summary[:n_observed_applicable_diagnostic_rows]) >
                   0 : true,
        sampler_flag = as_symbol(score[:diagnostic_flag]),
        chains = Int(score[:chains]),
        warmup_per_chain = Int(score[:warmup]),
        draws_per_chain = Int(score[:draws_per_chain]),
        total_retained_draws = Int(score[:n_draws]),
        target_acceptance =
            mcmc ? json_float_or_missing(score, :target_acceptance) : missing,
        max_rhat = json_float_or_missing(score, :max_rhat),
        min_ess = json_float_or_missing(score, :min_ess),
        e_bfmi = json_float_or_missing(score, :e_bfmi),
        n_divergences = Int(score[:n_divergences]),
        n_max_treedepth = Int(score[:n_max_treedepth]),
        n_nonfinite_logdensity =
            Int(json_get(score, :n_nonfinite_logdensity, 0)),
        n_failed_direct_constraints =
            Int(json_get(score, :n_failed_direct_constraints, 0)),
        heldout_predictive_score_computed =
            Bool(heldout_summary[:heldout_predictive_score_computed]),
        heldout_elpd = Float64(heldout_summary[:heldout_elpd]),
        heldout_mean_log_predictive_density =
            Float64(heldout_summary[:heldout_mean_log_predictive_density]),
        heldout_expected_score_mae =
            Float64(heldout_summary[:heldout_expected_score_mae]),
        heldout_expected_score_rmse =
            Float64(heldout_summary[:heldout_expected_score_rmse]),
        all_pointwise_scores_finite =
            Bool(heldout_summary[:all_pointwise_scores_finite]),
        public_claim_allowed = false,
    )
end

function selected_manifest_rows(manifest)
    return [
        (;
            execution_unit_id = as_symbol(row[:execution_unit_id]),
            scenario = as_symbol(row[:scenario]),
            model = as_symbol(row[:model]),
            fold = Int(row[:fold]),
            selected_for_action = Bool(row[:selected_for_action]),
            action_status = as_symbol(row[:action_status]),
            status_before = as_symbol(row[:status_before]),
            status_after = as_symbol(row[:status_after]),
            command_elapsed_ms =
                Int(json_get(row, :command_elapsed_ms, 0)),
            log_path = as_string(row[:log_path]),
            public_claim_allowed = false,
        )
        for row in manifest[:job_selection_rows]
        if Bool(row[:selected_for_action])
    ]
end

function fold_rank_rows(rows)
    ranks = NamedTuple[]
    for fold in sort(unique(row.fold for row in rows))
        fold_rows = [row for row in rows if row.fold == fold]
        ordered = sort(fold_rows; by = row -> row.heldout_elpd, rev = true)
        best = first(ordered)
        for (rank, row) in enumerate(ordered)
            push!(ranks, (;
                fold,
                rank,
                execution_unit_id = row.execution_unit_id,
                model = row.model,
                role = row.role,
                mcmc_refit_required = row.mcmc_refit_required,
                analytic_reference_scored = row.analytic_reference_scored,
                diagnostic_gate_passed = row.diagnostic_gate_passed,
                heldout_elpd = row.heldout_elpd,
                delta_elpd_from_fold_best = row.heldout_elpd - best.heldout_elpd,
                heldout_expected_score_mae = row.heldout_expected_score_mae,
                heldout_expected_score_rmse = row.heldout_expected_score_rmse,
                descriptive_only = true,
                public_model_weight_claim_allowed = false,
                public_fit_metric_claim_allowed = false,
            ))
        end
    end
    return ranks
end

function model_summary_rows(rows)
    summaries = NamedTuple[]
    for model in sort(unique(row.model for row in rows); by = string)
        model_rows = [row for row in rows if row.model === model]
        mcmc_rows = [row for row in model_rows if row.mcmc_refit_required]
        push!(summaries, (;
            scenario = SCENARIO,
            model,
            n_execution_units = length(model_rows),
            n_mcmc_execution_units = length(mcmc_rows),
            n_analytic_reference_units =
                count(row -> row.analytic_reference_scored, model_rows),
            n_executed_units = count(row -> row.executed, model_rows),
            n_diagnostic_gate_passed_units =
                count(row -> row.diagnostic_gate_passed, model_rows),
            n_divergences = sum(row.n_divergences for row in model_rows),
            mean_heldout_elpd =
                sum(row.heldout_elpd for row in model_rows) / length(model_rows),
            min_heldout_elpd = minimum(row.heldout_elpd for row in model_rows),
            max_heldout_elpd = maximum(row.heldout_elpd for row in model_rows),
            all_public_claims_blocked =
                all(row -> !row.public_claim_allowed, model_rows),
        ))
    end
    return summaries
end

function fold_best_rows(ranks)
    return [
        (;
            fold = Int(row.fold),
            best_model = row.model,
            best_role = row.role,
            best_heldout_elpd = row.heldout_elpd,
            best_is_analytic_reference = row.analytic_reference_scored,
            public_model_weight_claim_allowed = false,
        )
        for row in ranks
        if Int(row.rank) == 1
    ]
end

function blocker_rows(values)
    return [
        (blocker = :well_specified_scenario_not_executed,
            blocks = :scenario_level_result_review,
            resolved = values.all_scenario_jobs_executed),
        (blocker = :scenario_mcmc_diagnostic_failure,
            blocks = :public_sampler_stability_claims,
            resolved = values.all_mcmc_diagnostic_gates_passed),
        (blocker = :scalar_target_acceptance_policy_not_stable_across_folds,
            blocks = :scalar_batch_sampler_policy,
            resolved = values.scalar_batch_policy_stable_across_folds),
        (blocker = :null_reference_best_all_well_specified_folds,
            blocks = :structured_model_superiority_claims,
            resolved = !values.reference_best_all_folds),
        (blocker =
                :fit_metric_thresholds_not_reestimated_under_publication_grade_batch,
            blocks = :threshold_comparison_and_claim_calibration,
            resolved = false),
        (blocker = :remaining_100_unit_publication_grade_batch_not_executed,
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

function build_artifact(options)
    plan = load_json(options.plan)
    manifest = load_json(options.manifest)
    plan_record = plan_input_record(options.plan, plan)
    manifest_record = manifest_input_record(options.manifest, manifest)
    jobs = scenario_plan_jobs(plan)

    input_artifacts = NamedTuple[]
    rows = NamedTuple[]
    failures = NamedTuple[]
    for job in jobs
        paths = paths_for_job(options.result_root, job)
        result = load_json(paths.result)
        diagnostics = load_json(paths.diagnostics)
        heldout = load_json(paths.heldout)
        append!(input_artifacts, [
            artifact_record(:result, paths.result, result,
                EXPECTED_SCHEMAS.result),
            artifact_record(:diagnostics, paths.diagnostics, diagnostics,
                EXPECTED_SCHEMAS.diagnostics),
            artifact_record(:heldout, paths.heldout, heldout,
                EXPECTED_SCHEMAS.heldout),
        ])
        push!(rows, job_review_row(job, result, diagnostics, heldout))
        append!(failures, diagnostic_failure_rows(job, diagnostics))
    end

    selected_rows = selected_manifest_rows(manifest)
    ranks = fold_rank_rows(rows)
    model_summaries = model_summary_rows(rows)
    fold_bests = fold_best_rows(ranks)
    mcmc_rows = [row for row in rows if row.mcmc_refit_required]
    scalar_rows = [row for row in rows if row.model === :scalar_gmfrm_baseline]
    all_artifacts_valid =
        plan_record.exists &&
        plan_record.schema_matches &&
        plan_record.summary_passed &&
        manifest_record.exists &&
        manifest_record.schema_matches &&
        manifest_record.summary_passed &&
        all(row -> row.exists && row.schema_matches && row.summary_passed,
            input_artifacts)
    all_scenario_jobs_executed =
        length(rows) == 25 &&
        all(row -> row.executed && !row.dry_run, rows) &&
        count(row -> row.action_status === :executed, selected_rows) ==
            manifest_record.n_attempted_jobs &&
        manifest_record.n_attempted_jobs == 20 &&
        manifest_record.n_failed_jobs == 0
    all_mcmc_diagnostic_gates_passed =
        all(row -> row.diagnostic_gate_passed, mcmc_rows)
    scalar_target_acceptance_policy_applied =
        length(scalar_rows) == 5 &&
        all(row -> row.target_acceptance == 0.9, scalar_rows)
    scalar_batch_policy_stable_across_folds =
        scalar_target_acceptance_policy_applied &&
        all(row -> row.n_divergences == 0 && row.diagnostic_gate_passed,
            scalar_rows)
    reference_best_all_folds =
        length(fold_bests) == 5 &&
        all(row -> row.best_model === :null_or_intercept_reference, fold_bests)
    no_public_claim_allowed =
        all(row -> !row.public_claim_allowed, rows) &&
        all(row -> !row.public_claim_allowed, failures) &&
        all(row -> !row.public_claim_allowed, input_artifacts)
    values = (;
        all_scenario_jobs_executed,
        all_mcmc_diagnostic_gates_passed,
        scalar_batch_policy_stable_across_folds,
        reference_best_all_folds,
    )
    blockers = blocker_rows(values)
    remaining_blockers = [row.blocker for row in blockers if !row.resolved]
    passed = all_artifacts_valid &&
        all_scenario_jobs_executed &&
        scalar_target_acceptance_policy_applied &&
        no_public_claim_allowed

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_well_specified_scenario_execution_review.v1",
        family = :mgmfrm,
        scope =
            :publication_grade_refit_well_specified_scenario_execution_review,
        status =
            :publication_grade_refit_well_specified_scenario_execution_review_recorded,
        decision =
            :record_well_specified_scenario_publication_grade_execution,
        public_fit = true,
        experimental_public = true,
        local_only = true,
        scenario_only = true,
        publication_or_registration_action = false,
        publication_grade_batch_plan_recorded = true,
        publication_grade_well_specified_scenario_executed = true,
        full_125_unit_publication_grade_batch_completed = false,
        public_fit_metric_claim = false,
        public_q_revision_claim = false,
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = (;
            protocol_id =
                :mgmfrm_publication_grade_refit_well_specified_scenario_execution_review_v1,
            review_kind =
                :local_publication_grade_well_specified_scenario_execution_review,
            source_orchestrator =
                :run_mgmfrm_publication_grade_refit_batch,
            source_runner = :run_mgmfrm_publication_grade_refit_job,
            source_plan =
                :mgmfrm_publication_grade_refit_batch_expansion_plan,
            scenario = SCENARIO,
            expected_execution_units = 25,
            expected_folds = 5,
            expected_models_per_fold = 5,
            expected_mcmc_execution_units = 20,
            expected_analytic_reference_units = 5,
            thresholds = (;
                require_manifest_matching_jobs = 25,
                require_manifest_attempted_jobs = 20,
                require_failed_jobs = 0,
                require_chains = 4,
                require_warmup_per_chain = 1000,
                require_draws_per_chain = 1000,
                require_scalar_target_acceptance = 0.9,
                require_fixed_q_target_acceptance = 0.8,
                require_divergence_count_max = 0,
                require_public_claims_blocked = true,
            ),
        ),
        input_artifacts = [plan_record, manifest_record],
        job_input_artifacts = input_artifacts,
        manifest_selected_job_rows = selected_rows,
        job_review_rows = rows,
        model_summary_rows = model_summaries,
        fold_best_rows = fold_bests,
        heldout_model_rank_rows = ranks,
        diagnostic_failure_rows = failures,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :continue_batch_execution_after_well_specified_scenario_review,
            well_specified_scenario_executed = all_scenario_jobs_executed,
            all_mcmc_diagnostic_gates_passed,
            scalar_target_acceptance_policy_applied,
            scalar_target_acceptance_policy_stable_across_folds =
                scalar_batch_policy_stable_across_folds,
            reference_best_all_folds,
            public_fit_metric_claim_allowed = false,
            public_model_weight_claim_allowed = false,
            sparse_superiority_claim_allowed = false,
            required_followup =
                :run_remaining_publication_grade_refit_batch_jobs_and_review_scalar_divergences,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            scenario_only = true,
            all_artifacts_valid,
            publication_grade_well_specified_scenario_executed =
                all_scenario_jobs_executed,
            full_125_unit_publication_grade_batch_completed = false,
            all_mcmc_diagnostic_gates_passed,
            scalar_target_acceptance_policy_applied,
            scalar_target_acceptance_policy_stable_across_folds =
                scalar_batch_policy_stable_across_folds,
            reference_best_all_folds,
            no_public_claim_allowed,
            n_input_artifacts = 2,
            n_job_input_artifacts = length(input_artifacts),
            n_manifest_selected_job_rows = length(selected_rows),
            n_job_review_rows = length(rows),
            n_model_summary_rows = length(model_summaries),
            n_fold_best_rows = length(fold_bests),
            n_mcmc_execution_units = length(mcmc_rows),
            n_analytic_reference_units =
                count(row -> row.analytic_reference_scored, rows),
            n_diagnostic_failure_rows = length(failures),
            n_heldout_model_rank_rows = length(ranks),
            n_manifest_matching_jobs = manifest_record.n_matching_jobs,
            n_manifest_selected_for_action =
                manifest_record.n_selected_for_action,
            n_manifest_attempted_jobs = manifest_record.n_attempted_jobs,
            n_manifest_skipped_jobs = manifest_record.n_skipped_jobs,
            n_manifest_failed_jobs = manifest_record.n_failed_jobs,
            n_manifest_successful_action_jobs =
                manifest_record.n_successful_action_jobs,
            n_batch_complete_after_manifest =
                manifest_record.n_complete_after,
            n_batch_pending_after_manifest = manifest_record.n_pending_after,
            n_scalar_diagnostic_gate_passed =
                count(row -> row.diagnostic_gate_passed, scalar_rows),
            scalar_divergences_by_fold =
                [(fold = row.fold, n_divergences = row.n_divergences)
                 for row in sort(scalar_rows; by = row -> row.fold)],
            scalar_total_divergences =
                sum(row.n_divergences for row in scalar_rows),
            folds_with_scalar_divergences =
                [row.fold for row in sort(scalar_rows; by = row -> row.fold)
                 if row.n_divergences > 0],
            best_heldout_models_by_fold =
                [(fold = row.fold, model = row.best_model,
                  heldout_elpd = row.best_heldout_elpd)
                 for row in fold_bests],
            n_blocker_rows = length(blockers),
            n_resolved_blockers = count(row -> row.resolved, blockers),
            n_blockers = length(remaining_blockers),
            remaining_public_blockers = remaining_blockers,
            recommendation =
                :review_scalar_divergences_and_run_remaining_publication_grade_batch_jobs_keep_claims_blocked,
            next_gate =
                :review_scalar_divergences_or_run_remaining_publication_grade_refit_batch_jobs,
        ),
    )
end

function main(args)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output, artifact)
    println("wrote ", rel(options.output))
    println("passed=", artifact.summary.passed,
        " executed=", artifact.summary.publication_grade_well_specified_scenario_executed,
        " mcmc_gates=", artifact.summary.all_mcmc_diagnostic_gates_passed,
        " scalar_divergences=", artifact.summary.scalar_total_divergences,
        " public_claim_allowed=false")
end

main(ARGS)
