#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_pilot_results_review.json")
const DEFAULT_HARNESS =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_pilot_execution_harness.json")
const FIXTURE_ROOT = joinpath(ROOT, "test", "fixtures")

include(joinpath(@__DIR__, "local_json.jl"))

const EXPECTED_SCHEMAS = (;
    result =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_result.v1",
    diagnostics =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_diagnostics.v1",
    heldout =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_heldout_score.v1",
)

const PROTOCOL = (;
    protocol_id =
        "mgmfrm_publication_grade_refit_pilot_results_review_v1",
    review_kind =
        :local_publication_grade_refit_pilot_results_review,
    publication_or_registration_action = false,
    local_only = true,
    pilot_only = true,
    source_harness =
        :mgmfrm_publication_grade_refit_pilot_execution_harness,
    expected_execution_units = 5,
    expected_mcmc_execution_units = 4,
    expected_analytic_reference_units = 1,
    expected_artifacts_per_unit = 3,
    thresholds = (;
        require_harness_passed = true,
        require_result_artifact_rows_recorded = true,
        require_missing_or_valid_job_artifacts = true,
        require_partial_execution_detected = true,
        require_heldout_rank_rows_when_scores_complete = true,
        require_diagnostic_failure_rows_when_observed = true,
        require_descriptive_only_model_rankings = true,
        require_all_public_claims_blocked = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM publication-grade refit pilot results review.

    This review reads the execution harness and any local runner artifacts,
    records missing/partial/complete execution state, and keeps public MGMFRM
    claims blocked until all selected jobs and diagnostics are reviewed.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_pilot_results_review.jl [--output PATH]

    Options:
      --output PATH       Review fixture path.
      --harness PATH      Execution harness fixture path.
      --result-root PATH  Override runner artifact directory.
      --read-local-artifacts
                          Read local runner artifacts even when writing under
                          test/fixtures.
      --ignore-local-artifacts
                          Treat runner artifacts as absent.
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    harness = DEFAULT_HARNESS
    result_root = nothing
    ignore_local_artifacts = nothing
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg == "--harness"
            index < length(args) || error("--harness requires a path")
            harness = abspath(args[index + 1])
            index += 2
        elseif arg == "--result-root"
            index < length(args) || error("--result-root requires a path")
            result_root = abspath(args[index + 1])
            index += 2
        elseif arg == "--read-local-artifacts"
            ignore_local_artifacts = false
            index += 1
        elseif arg == "--ignore-local-artifacts"
            ignore_local_artifacts = true
            index += 1
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; output, harness, result_root, ignore_local_artifacts)
end

project_version() = String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
fixture_path(path::AbstractString) = normpath(joinpath(ROOT, path))

function path_inside(path::AbstractString, root::AbstractString)
    relative = relpath(normpath(path), normpath(root))
    return relative == "." || !(startswith(relative, "..") ||
                                isabspath(relative))
end

as_string(value) = String(value)
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_float(value) = Float64(value)
as_symbol(value) = Symbol(String(value))

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

function load_json(path::AbstractString)
    return JSON3.read(read(path, String))
end

function input_harness_record(path::AbstractString)
    exists = isfile(path)
    if !exists
        return (;
            artifact =
                :mgmfrm_publication_grade_refit_pilot_execution_harness,
            path = rel(path),
            exists = false,
            sha256 = missing,
            schema = missing,
            expected_schema =
                "bayesianmgmfrm.mgmfrm_publication_grade_refit_pilot_execution_harness.v1",
            schema_matches = false,
            summary_passed = false,
        )
    end
    artifact = load_json(path)
    schema = as_string(artifact[:schema])
    expected =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_pilot_execution_harness.v1"
    return (;
        artifact = :mgmfrm_publication_grade_refit_pilot_execution_harness,
        path = rel(path),
        exists,
        sha256 = file_sha256(path),
        schema,
        expected_schema = expected,
        schema_matches = schema == expected,
        summary_passed = json_bool(artifact[:summary], :passed),
    )
end

function artifact_paths(job, result_root)
    if result_root === nothing
        return (;
            result = fixture_path(as_string(job[:result_artifact_path])),
            diagnostics =
                fixture_path(as_string(job[:diagnostic_artifact_path])),
            heldout =
                fixture_path(as_string(job[:heldout_score_artifact_path])),
        )
    end
    unit = as_string(job[:execution_unit_id])
    return (;
        result = joinpath(result_root, string(unit, "_result.json")),
        diagnostics =
            joinpath(result_root, string(unit, "_diagnostics.json")),
        heldout =
            joinpath(result_root, string(unit, "_heldout_score.json")),
    )
end

function job_artifact_record(kind::Symbol, path::AbstractString,
        expected_schema::AbstractString; ignore_local_artifact::Bool = false)
    exists = !ignore_local_artifact && isfile(path)
    if !exists
        return (;
            kind,
            path = rel(path),
            exists = false,
            sha256 = missing,
            schema = missing,
            expected_schema,
            schema_matches = false,
            status = :missing,
            summary_passed = false,
            executed = false,
            dry_run = false,
            diagnostic_gate_passed = false,
            heldout_predictive_score_computed = false,
            posterior_predictive_check_recorded = false,
            n_observed_applicable_diagnostic_rows = 0,
            n_heldout_pointwise_rows = 0,
            heldout_elpd = missing,
            heldout_mean_log_predictive_density = missing,
            heldout_expected_score_mae = missing,
            heldout_expected_score_rmse = missing,
        )
    end
    artifact = load_json(path)
    schema = as_string(artifact[:schema])
    summary = artifact[:summary]
    return (;
        kind,
        path = rel(path),
        exists,
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
        heldout_predictive_score_computed =
            json_bool(summary, :heldout_predictive_score_computed),
        posterior_predictive_check_recorded =
            json_bool(summary, :posterior_predictive_check_recorded),
        n_observed_applicable_diagnostic_rows =
            json_int(summary, :n_observed_applicable_diagnostic_rows),
        n_heldout_pointwise_rows =
            json_int(summary, :n_heldout_pointwise_rows),
        heldout_elpd = json_float_or_missing(summary, :heldout_elpd),
        heldout_mean_log_predictive_density =
            json_float_or_missing(summary,
                :heldout_mean_log_predictive_density),
        heldout_expected_score_mae =
            json_float_or_missing(summary, :heldout_expected_score_mae),
        heldout_expected_score_rmse =
            json_float_or_missing(summary, :heldout_expected_score_rmse),
    )
end

function job_result_review_row(job, result_root; ignore_local_artifacts::Bool)
    paths = artifact_paths(job, result_root)
    result = job_artifact_record(:result, paths.result,
        EXPECTED_SCHEMAS.result; ignore_local_artifact = ignore_local_artifacts)
    diagnostics =
        job_artifact_record(:diagnostics, paths.diagnostics,
            EXPECTED_SCHEMAS.diagnostics;
            ignore_local_artifact = ignore_local_artifacts)
    heldout =
        job_artifact_record(:heldout, paths.heldout,
            EXPECTED_SCHEMAS.heldout;
            ignore_local_artifact = ignore_local_artifacts)
    artifacts = (result, diagnostics, heldout)
    complete = all(row -> row.exists && row.schema_matches &&
        row.summary_passed, artifacts)
    executed = complete && result.executed && !result.dry_run
    heldout_computed =
        complete && heldout.heldout_predictive_score_computed
    diagnostics_observed =
        complete &&
        diagnostics.n_observed_applicable_diagnostic_rows > 0
    mcmc_required = as_bool(job[:mcmc_refit_required])
    diagnostic_gate_passed =
        complete && result.diagnostic_gate_passed &&
        (!mcmc_required || diagnostics.posterior_predictive_check_recorded)
    return (;
        execution_unit_id = as_symbol(job[:execution_unit_id]),
        model = as_symbol(job[:model]),
        scenario = as_symbol(job[:scenario]),
        fold = as_int(job[:fold]),
        mcmc_refit_required = mcmc_required,
        analytic_reference_scored = as_bool(job[:analytic_reference_scored]),
        result_artifact = result,
        diagnostic_artifact = diagnostics,
        heldout_artifact = heldout,
        artifacts_complete = complete,
        execution_observed = executed,
        diagnostics_observed,
        diagnostic_gate_passed,
        heldout_predictive_score_computed = heldout_computed,
        heldout_elpd = heldout.heldout_elpd,
        heldout_mean_log_predictive_density =
            heldout.heldout_mean_log_predictive_density,
        heldout_expected_score_mae = heldout.heldout_expected_score_mae,
        heldout_expected_score_rmse = heldout.heldout_expected_score_rmse,
        public_claim_allowed = false,
    )
end

function observed_diagnostic_failures(job, result_root;
        ignore_local_artifacts::Bool)
    ignore_local_artifacts && return NamedTuple[]
    paths = artifact_paths(job, result_root)
    isfile(paths.diagnostics) || return NamedTuple[]
    artifact = load_json(paths.diagnostics)
    as_string(artifact[:schema]) == EXPECTED_SCHEMAS.diagnostics ||
        return NamedTuple[]
    haskey(artifact, :diagnostic_rows) || return NamedTuple[]
    failures = NamedTuple[]
    for diagnostic in artifact[:diagnostic_rows]
        applicable = json_bool(diagnostic, :applicable)
        observed = json_bool(diagnostic, :observed)
        passed = json_bool(diagnostic, :passed)
        applicable || continue
        passed && continue
        push!(failures, (;
            execution_unit_id = as_symbol(job[:execution_unit_id]),
            model = as_symbol(job[:model]),
            scenario = as_symbol(job[:scenario]),
            fold = as_int(job[:fold]),
            mcmc_refit_required = as_bool(job[:mcmc_refit_required]),
            analytic_reference_scored =
                as_bool(job[:analytic_reference_scored]),
            diagnostic = as_symbol(diagnostic[:diagnostic]),
            source = as_symbol(diagnostic[:source]),
            comparison = as_symbol(diagnostic[:comparison]),
            threshold = json_float_or_missing(diagnostic, :threshold),
            value = json_float_or_missing(diagnostic, :value),
            observed,
            applicable,
            passed,
            failure_kind = observed ? :threshold_failed :
                :required_diagnostic_missing,
            public_claim_blocked_if_missing =
                json_bool(diagnostic, :public_claim_blocked_if_missing),
            public_claim_allowed = false,
            required_followup =
                :review_sampler_diagnostic_failure_or_rerun_with_remediation,
        ))
    end
    return failures
end

function heldout_model_rank_rows(rows)
    scored_rows = [
        row for row in rows
        if row.heldout_predictive_score_computed &&
            !ismissing(row.heldout_elpd)
    ]
    isempty(scored_rows) && return NamedTuple[]
    sorted_rows =
        sort(scored_rows; by = row -> Float64(row.heldout_elpd), rev = true)
    best = first(sorted_rows)
    best_mlp = best.heldout_mean_log_predictive_density
    best_mae = best.heldout_expected_score_mae
    best_rmse = best.heldout_expected_score_rmse
    return [
        (;
            rank = rank,
            execution_unit_id = row.execution_unit_id,
            model = row.model,
            scenario = row.scenario,
            fold = row.fold,
            mcmc_refit_required = row.mcmc_refit_required,
            analytic_reference_scored = row.analytic_reference_scored,
            diagnostic_gate_passed = row.diagnostic_gate_passed,
            heldout_elpd = row.heldout_elpd,
            delta_elpd_from_best =
                Float64(row.heldout_elpd) - Float64(best.heldout_elpd),
            heldout_mean_log_predictive_density =
                row.heldout_mean_log_predictive_density,
            delta_mean_log_predictive_density_from_best =
                ismissing(row.heldout_mean_log_predictive_density) ||
                    ismissing(best_mlp) ?
                    missing :
                    Float64(row.heldout_mean_log_predictive_density) -
                    Float64(best_mlp),
            heldout_expected_score_mae = row.heldout_expected_score_mae,
            delta_expected_score_mae_from_best =
                ismissing(row.heldout_expected_score_mae) ||
                    ismissing(best_mae) ?
                    missing :
                    Float64(row.heldout_expected_score_mae) -
                    Float64(best_mae),
            heldout_expected_score_rmse = row.heldout_expected_score_rmse,
            delta_expected_score_rmse_from_best =
                ismissing(row.heldout_expected_score_rmse) ||
                    ismissing(best_rmse) ?
                    missing :
                    Float64(row.heldout_expected_score_rmse) -
                    Float64(best_rmse),
            mcmc_model_comparison_candidate = row.mcmc_refit_required,
            descriptive_only = true,
            public_model_weight_claim_allowed = false,
            public_fit_metric_claim_allowed = false,
            interpretation = row.analytic_reference_scored ?
                :analytic_reference_anchor_descriptive_only :
                (row.diagnostic_gate_passed ?
                    :diagnostic_passed_descriptive_only :
                    :diagnostic_failed_descriptive_only),
        )
        for (rank, row) in enumerate(sorted_rows)
    ]
end

function first_model_name(rows)
    isempty(rows) && return missing
    return first(rows).model
end

function blocker_rows(summary_values)
    return [
        (blocker = :publication_grade_pilot_not_executed,
            blocks = :pilot_runtime_and_diagnostic_assessment,
            resolved = summary_values.all_five_pilot_jobs_executed),
        (blocker = :publication_grade_results_artifacts_missing,
            blocks = :pilot_result_review,
            resolved = summary_values.all_expected_job_artifacts_present),
        (blocker = :diagnostics_not_observed,
            blocks = :public_fit_metric_and_model_comparison_claims,
            resolved = summary_values.all_executed_diagnostics_observed &&
                summary_values.all_five_pilot_jobs_executed),
        (blocker =
                :fit_metric_thresholds_not_reestimated_under_publication_grade_draws,
            blocks = :threshold_comparison_and_claim_calibration,
            resolved = summary_values.all_mcmc_diagnostic_gates_passed &&
                summary_values.all_five_pilot_jobs_executed),
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

function build_artifact(options)
    harness_record = input_harness_record(options.harness)
    harness = harness_record.exists ? load_json(options.harness) : nothing
    jobs = harness === nothing ? Any[] : [row for row in harness[:execution_job_rows]]
    ignore_local_artifacts = options.ignore_local_artifacts === nothing ?
        path_inside(options.output, FIXTURE_ROOT) :
        Bool(options.ignore_local_artifacts)
    rows = [
        job_result_review_row(job, options.result_root;
            ignore_local_artifacts)
        for job in jobs
    ]
    diagnostic_failures =
        reduce(vcat, [observed_diagnostic_failures(job, options.result_root;
                          ignore_local_artifacts)
                      for job in jobs]; init = NamedTuple[])
    heldout_ranks = heldout_model_rank_rows(rows)
    n_expected = length(jobs)
    n_mcmc = count(row -> row.mcmc_refit_required, rows)
    n_reference = n_expected - n_mcmc
    n_complete = count(row -> row.artifacts_complete, rows)
    n_executed = count(row -> row.execution_observed, rows)
    n_diagnostics_observed = count(row -> row.diagnostics_observed, rows)
    n_diagnostic_gate_passed = count(row -> row.diagnostic_gate_passed, rows)
    n_heldout = count(row -> row.heldout_predictive_score_computed, rows)
    n_present_artifacts =
        sum((row.result_artifact.exists ? 1 : 0) +
            (row.diagnostic_artifact.exists ? 1 : 0) +
            (row.heldout_artifact.exists ? 1 : 0) for row in rows; init = 0)
    n_valid_artifacts =
        sum((row.result_artifact.schema_matches ? 1 : 0) +
            (row.diagnostic_artifact.schema_matches ? 1 : 0) +
            (row.heldout_artifact.schema_matches ? 1 : 0) for row in rows; init = 0)
    all_expected_artifacts_present =
        n_expected > 0 && n_present_artifacts == 3 * n_expected
    all_expected_job_artifacts_present =
        all_expected_artifacts_present && n_valid_artifacts == 3 * n_expected
    all_five_pilot_jobs_executed =
        n_expected == PROTOCOL.expected_execution_units &&
        n_executed == PROTOCOL.expected_execution_units
    all_executed_diagnostics_observed =
        n_executed > 0 &&
        all(row -> !row.execution_observed || row.diagnostics_observed, rows)
    all_mcmc_diagnostic_gates_passed =
        n_mcmc > 0 &&
        all(row -> !row.mcmc_refit_required || row.diagnostic_gate_passed, rows)
    sampler_diagnostic_failure_detected =
        any(row -> row.mcmc_refit_required && row.diagnostics_observed &&
            !row.diagnostic_gate_passed, rows)
    mcmc_rank_rows =
        [row for row in heldout_ranks if row.mcmc_model_comparison_candidate]
    diagnostic_passed_mcmc_rank_rows =
        [row for row in mcmc_rank_rows if row.diagnostic_gate_passed]
    best_heldout_model = first_model_name(heldout_ranks)
    best_mcmc_heldout_model = first_model_name(mcmc_rank_rows)
    best_diagnostic_passed_mcmc_model =
        first_model_name(diagnostic_passed_mcmc_rank_rows)
    reference_rank_rows =
        [row for row in heldout_ranks if row.analytic_reference_scored]
    reference_best_heldout_score =
        !isempty(reference_rank_rows) && first(reference_rank_rows).rank == 1
    mcmc_model_beat_reference_on_heldout_elpd =
        isempty(reference_rank_rows) ? missing :
        any(row -> row.mcmc_model_comparison_candidate &&
            Float64(row.heldout_elpd) >
            Float64(first(reference_rank_rows).heldout_elpd), heldout_ranks)
    no_public_fit_metric_claim = true
    no_public_q_revision_claim = true
    no_public_model_weight_claim = true
    no_sparse_superiority_claim = true
    no_public_claim_allowed = all(row -> !row.public_claim_allowed, rows)
    partial_execution_detected =
        0 < n_executed < PROTOCOL.expected_execution_units
    result_review_rows_recorded = n_expected == PROTOCOL.expected_execution_units
    missing_or_valid_job_artifacts =
        all(rows) do row
            artifacts = (row.result_artifact, row.diagnostic_artifact,
                row.heldout_artifact)
            all(artifact -> !artifact.exists || artifact.schema_matches,
                artifacts)
        end
    summary_values = (;
        all_five_pilot_jobs_executed,
        all_expected_job_artifacts_present,
        all_executed_diagnostics_observed,
        all_mcmc_diagnostic_gates_passed,
    )
    blockers = blocker_rows(summary_values)
    passed = harness_record.exists &&
        harness_record.schema_matches &&
        harness_record.summary_passed &&
        result_review_rows_recorded &&
        missing_or_valid_job_artifacts &&
        no_public_claim_allowed &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim
    next_gate = !all_five_pilot_jobs_executed ?
        :execute_remaining_publication_grade_refit_pilot_jobs_or_attach_external_construct_dataset :
        (sampler_diagnostic_failure_detected ?
            :review_sampler_diagnostic_failures_before_expand_batch :
            :review_publication_grade_refit_diagnostics_or_expand_batch)
    recommendation = !all_five_pilot_jobs_executed ?
        :execute_missing_publication_grade_pilot_jobs_keep_claims_blocked :
        (sampler_diagnostic_failure_detected ?
            :review_sampler_diagnostic_failures_before_any_batch_expansion :
            :review_publication_grade_refit_diagnostics_before_any_public_claim)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_pilot_results_review.v1",
        family = :mgmfrm,
        scope = :publication_grade_refit_pilot_results_review,
        status = :publication_grade_refit_pilot_results_review_recorded,
        decision =
            :record_publication_grade_refit_pilot_results_state,
        public_fit = true,
        experimental_public = true,
        fit_ready = Bool(harness_record.summary_passed),
        local_only = true,
        pilot_only = true,
        local_artifacts_ignored_for_fixture = ignore_local_artifacts,
        publication_or_registration_action = false,
        publication_grade_gate_defined = true,
        publication_grade_pilot_plan_recorded = true,
        publication_grade_pilot_execution_harness_recorded =
            Bool(harness_record.summary_passed),
        publication_grade_pilot_results_review_recorded = true,
        publication_grade_pilot_executed = all_five_pilot_jobs_executed,
        full_125_unit_publication_grade_batch_completed = false,
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
        input_artifacts = [harness_record],
        job_result_review_rows = rows,
        heldout_model_rank_rows = heldout_ranks,
        diagnostic_failure_rows = diagnostic_failures,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :record_publication_grade_pilot_results_review,
            publication_grade_pilot_execution_harness_recorded =
                Bool(harness_record.summary_passed),
            publication_grade_pilot_executed =
                all_five_pilot_jobs_executed,
            diagnostics_observed =
                all_executed_diagnostics_observed &&
                all_five_pilot_jobs_executed,
            heldout_scores_cover_selected_units =
                n_heldout == PROTOCOL.expected_execution_units,
            sampler_diagnostic_failure_detected,
            heldout_rank_review_recorded = true,
            diagnostic_failure_review_recorded = true,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            required_followup = next_gate,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            pilot_only = true,
            local_artifacts_ignored_for_fixture = ignore_local_artifacts,
            harness_present = harness_record.exists,
            harness_schema_matches = harness_record.schema_matches,
            harness_passed = harness_record.summary_passed,
            result_review_rows_recorded,
            missing_or_valid_job_artifacts,
            partial_execution_detected,
            publication_grade_pilot_executed =
                all_five_pilot_jobs_executed,
            all_five_pilot_jobs_executed,
            all_expected_job_artifacts_present,
            all_executed_diagnostics_observed,
            all_mcmc_diagnostic_gates_passed,
            sampler_diagnostic_failure_detected,
            heldout_scores_cover_selected_units =
                n_heldout == PROTOCOL.expected_execution_units,
            heldout_rank_review_recorded = true,
            diagnostic_failure_review_recorded = true,
            full_125_unit_publication_grade_batch_completed = false,
            external_construct_dataset_still_required = true,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            n_input_artifacts = 1,
            n_expected_execution_units = n_expected,
            n_mcmc_execution_units = n_mcmc,
            n_analytic_reference_units = n_reference,
            n_job_result_review_rows = length(rows),
            n_heldout_model_rank_rows = length(heldout_ranks),
            n_diagnostic_failure_rows = length(diagnostic_failures),
            n_mcmc_diagnostic_failure_rows =
                count(row -> row.mcmc_refit_required, diagnostic_failures),
            n_expected_job_artifacts = 3 * n_expected,
            n_present_job_artifacts = n_present_artifacts,
            n_valid_job_artifacts = n_valid_artifacts,
            n_complete_execution_units = n_complete,
            n_executed_execution_units = n_executed,
            n_diagnostics_observed_units = n_diagnostics_observed,
            n_diagnostic_gate_passed_units = n_diagnostic_gate_passed,
            n_heldout_score_units = n_heldout,
            n_blocker_rows = length(blockers),
            n_blockers = count(row -> !row.resolved, blockers),
            best_heldout_model,
            best_mcmc_heldout_model,
            best_diagnostic_passed_mcmc_model,
            reference_best_heldout_score,
            mcmc_model_beat_reference_on_heldout_elpd,
            remaining_public_blockers =
                [row.blocker for row in blockers if !row.resolved],
            recommendation,
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
        " executed=", artifact.summary.n_executed_execution_units,
        "/", artifact.summary.n_expected_execution_units,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
