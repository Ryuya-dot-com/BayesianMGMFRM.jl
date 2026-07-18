#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const RESULT_ROOT =
    joinpath(ROOT, "artifacts", "publication_grade_refit_pilot_brms_like")
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_brms_like_pilot_execution_review.json")

include(joinpath(@__DIR__, "local_json.jl"))

const EXPECTED_SCHEMAS = (;
    result =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_result.v1",
    diagnostics =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_diagnostics.v1",
    heldout =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_heldout_score.v1",
)

const JOBS = (
    (;
        role = :scalar,
        execution_unit_id =
            :well_specified_current_q__scalar_gmfrm_baseline__fold1,
        model = :scalar_gmfrm_baseline,
        mcmc_refit_required = true,
        analytic_reference_scored = false,
        artifact_suffix = "_4_1000_1000_ta080",
    ),
    (;
        role = :confirmatory,
        execution_unit_id =
            :well_specified_current_q__confirmatory_mgmfrm_current_q__fold1,
        model = :confirmatory_mgmfrm_current_q,
        mcmc_refit_required = true,
        analytic_reference_scored = false,
        artifact_suffix = "_4_1000_1000_ta080",
    ),
    (;
        role = :sparse,
        execution_unit_id =
            :well_specified_current_q__sparse_mgmfrm_current_q__fold1,
        model = :sparse_mgmfrm_current_q,
        mcmc_refit_required = true,
        analytic_reference_scored = false,
        artifact_suffix = "_4_1000_1000_ta080",
    ),
    (;
        role = :construct_reviewed_revised_q,
        execution_unit_id =
            :well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold1,
        model = :construct_reviewed_revised_q_mgmfrm,
        mcmc_refit_required = true,
        analytic_reference_scored = false,
        artifact_suffix = "_4_1000_1000_ta080",
    ),
    (;
        role = :analytic_reference,
        execution_unit_id =
            :well_specified_current_q__null_or_intercept_reference__fold1,
        model = :null_or_intercept_reference,
        mcmc_refit_required = false,
        analytic_reference_scored = true,
        artifact_suffix = "_analytic_reference",
    ),
)

function usage()
    return """
    Generate a compact review fixture for the brms-like full MGMFRM
    publication-grade pilot execution.

    This reads ignored local runner artifacts for the five selected pilot units
    and writes a small tracked evidence summary. It does not copy raw runner
    artifacts into the repository and does not allow public MGMFRM claims.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_brms_like_pilot_execution_review.jl [--output PATH]

    Options:
      --result-root PATH  Directory containing local runner artifacts.
      --output PATH       Review fixture path.
    """
end

function parse_args(args)
    result_root = RESULT_ROOT
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--result-root"
            index < length(args) || error("--result-root requires a path")
            result_root = abspath(args[index + 1])
            index += 2
        elseif arg == "--output"
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
    return (; result_root, output)
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

function paths_for_job(result_root::AbstractString, job)
    stem = joinpath(result_root,
        string(job.execution_unit_id, job.artifact_suffix))
    return (;
        result = string(stem, "_result.json"),
        diagnostics = string(stem, "_diagnostics.json"),
        heldout = string(stem, "_heldout_score.json"),
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
            model = job.model,
            mcmc_refit_required = Bool(job.mcmc_refit_required),
            diagnostic = as_symbol(row[:diagnostic]),
            source = as_symbol(row[:source]),
            comparison = as_symbol(row[:comparison]),
            threshold = native_scalar(row[:threshold]),
            value = native_scalar(row[:value]),
            observed,
            applicable,
            passed,
            public_claim_allowed = false,
            required_followup =
                :review_sampler_diagnostic_failure_or_rerun_with_remediation,
        ))
    end
    return rows
end

function job_review_row(job, result, diagnostics, heldout)
    score = result[:score_row]
    result_summary = result[:summary]
    diagnostic_summary = diagnostics[:summary]
    raw_sampler_summary = diagnostics[:sampler_summary]
    sampler_summary =
        raw_sampler_summary === nothing ? missing : raw_sampler_summary
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
            mcmc ? Float64(score[:target_acceptance]) : missing,
        max_rhat = json_float_or_missing(score, :max_rhat),
        min_ess = json_float_or_missing(score, :min_ess),
        e_bfmi = json_float_or_missing(score, :e_bfmi),
        n_divergences = Int(score[:n_divergences]),
        n_max_treedepth = Int(score[:n_max_treedepth]),
        n_nonfinite_logdensity =
            Int(json_get(score, :n_nonfinite_logdensity, 0)),
        n_failed_direct_constraints =
            Int(json_get(score, :n_failed_direct_constraints, 0)),
        diagnostic_surface_flag =
            mcmc ? as_symbol(json_get(sampler_summary, :flag,
                score[:diagnostic_flag])) : as_symbol(score[:diagnostic_flag]),
        diagnostic_surface_passed =
            mcmc ? json_bool(sampler_summary, :passed,
                Bool(result_summary[:diagnostic_gate_passed])) :
            Bool(result_summary[:diagnostic_gate_passed]),
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

function heldout_rank_rows(rows)
    ordered = sort(rows; by = row -> row.heldout_elpd, rev = true)
    best = first(ordered)
    return [
        (;
            rank,
            execution_unit_id = row.execution_unit_id,
            model = row.model,
            role = row.role,
            mcmc_refit_required = row.mcmc_refit_required,
            analytic_reference_scored = row.analytic_reference_scored,
            diagnostic_gate_passed = row.diagnostic_gate_passed,
            heldout_elpd = row.heldout_elpd,
            delta_elpd_from_best = row.heldout_elpd - best.heldout_elpd,
            heldout_mean_log_predictive_density =
                row.heldout_mean_log_predictive_density,
            heldout_expected_score_mae = row.heldout_expected_score_mae,
            heldout_expected_score_rmse = row.heldout_expected_score_rmse,
            descriptive_only = true,
            public_model_weight_claim_allowed = false,
            public_fit_metric_claim_allowed = false,
        )
        for (rank, row) in enumerate(ordered)
    ]
end

function blocker_rows(values)
    return [
        (blocker = :publication_grade_pilot_not_executed,
            blocks = :pilot_runtime_and_diagnostic_assessment,
            resolved = values.all_five_pilot_jobs_executed),
        (blocker = :publication_grade_results_artifacts_missing,
            blocks = :pilot_result_review,
            resolved = values.all_expected_job_artifacts_present),
        (blocker = :diagnostics_not_observed,
            blocks = :public_fit_metric_and_model_comparison_claims,
            resolved = values.all_executed_diagnostics_observed),
        (blocker =
                :fit_metric_thresholds_not_reestimated_under_publication_grade_draws,
            blocks = :threshold_comparison_and_claim_calibration,
            resolved = false),
        (blocker = :sampler_diagnostic_failure_detected,
            blocks = :batch_expansion_without_remediation_review,
            resolved = !values.sampler_diagnostic_failure_detected),
        (blocker = :null_reference_best_heldout_score,
            blocks = :structured_model_superiority_claims,
            resolved = !values.reference_best_heldout_score),
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
    input_artifacts = NamedTuple[]
    rows = NamedTuple[]
    failures = NamedTuple[]
    for job in JOBS
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

    ranks = heldout_rank_rows(rows)
    mcmc_rows = [row for row in rows if row.mcmc_refit_required]
    diagnostic_passed_mcmc_rows =
        [row for row in mcmc_rows if row.diagnostic_gate_passed]
    mcmc_ranks = [row for row in ranks if row.mcmc_refit_required]
    diagnostic_passed_mcmc_ranks =
        [row for row in ranks if row.mcmc_refit_required &&
            row.diagnostic_gate_passed]
    reference_ranks = [row for row in ranks if row.analytic_reference_scored]

    all_artifacts_valid =
        all(row -> row.exists && row.schema_matches && row.summary_passed,
            input_artifacts)
    all_five_pilot_jobs_executed =
        length(rows) == length(JOBS) && all(row -> row.executed, rows)
    all_expected_job_artifacts_present =
        length(input_artifacts) == 3 * length(JOBS) && all_artifacts_valid
    all_executed_diagnostics_observed =
        all(row -> !row.executed || row.diagnostics_observed, rows)
    all_mcmc_diagnostic_gates_passed =
        all(row -> row.diagnostic_gate_passed, mcmc_rows)
    sampler_diagnostic_failure_detected =
        any(row -> row.mcmc_refit_required && row.diagnostics_observed &&
            !row.diagnostic_gate_passed, rows)
    reference_best_heldout_score =
        !isempty(reference_ranks) && first(reference_ranks).rank == 1
    mcmc_model_beat_reference_on_heldout_elpd =
        isempty(reference_ranks) ? missing :
        any(row -> row.mcmc_refit_required &&
            row.heldout_elpd > first(reference_ranks).heldout_elpd, rows)
    best_heldout_model = first(ranks).model
    best_mcmc_heldout_model = isempty(mcmc_ranks) ? missing :
        first(mcmc_ranks).model
    best_diagnostic_passed_mcmc_model =
        isempty(diagnostic_passed_mcmc_ranks) ? missing :
        first(diagnostic_passed_mcmc_ranks).model
    values = (;
        all_five_pilot_jobs_executed,
        all_expected_job_artifacts_present,
        all_executed_diagnostics_observed,
        sampler_diagnostic_failure_detected,
        reference_best_heldout_score,
    )
    blockers = blocker_rows(values)
    remaining_blockers = [row.blocker for row in blockers if !row.resolved]
    no_public_claim_allowed =
        all(row -> !row.public_claim_allowed, rows) &&
        all(row -> !row.public_claim_allowed, failures)
    passed = all_artifacts_valid &&
        all_five_pilot_jobs_executed &&
        all_expected_job_artifacts_present &&
        all_executed_diagnostics_observed &&
        no_public_claim_allowed

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_brms_like_pilot_execution_review.v1",
        family = :mgmfrm,
        scope = :publication_grade_refit_brms_like_pilot_execution_review,
        status = :publication_grade_refit_brms_like_pilot_executed,
        decision = :record_brms_like_publication_grade_pilot_execution,
        public_fit = true,
        experimental_public = true,
        local_only = true,
        pilot_only = true,
        local_artifacts_required_for_generation = true,
        publication_or_registration_action = false,
        publication_grade_gate_defined = true,
        publication_grade_pilot_plan_recorded = true,
        publication_grade_pilot_execution_harness_recorded = true,
        publication_grade_brms_like_pilot_executed = true,
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
                :mgmfrm_publication_grade_refit_brms_like_pilot_execution_review_v1,
            review_kind =
                :local_brms_like_publication_grade_pilot_execution_review,
            source_runner = :run_mgmfrm_publication_grade_refit_job,
            expected_execution_units = 5,
            expected_mcmc_execution_units = 4,
            expected_analytic_reference_units = 1,
            expected_artifacts_per_unit = 3,
            thresholds = (;
                require_chains = 4,
                require_warmup_per_chain = 1000,
                require_draws_per_chain = 1000,
                require_total_retained_draws = 4000,
                require_rank_normalized_rhat_max = 1.01,
                require_ess_min = 400.0,
                require_divergence_count_max = 0,
                require_max_treedepth_count_max = 0,
                require_ebfmi_min = 0.3,
                require_public_claims_blocked = true,
            ),
        ),
        input_artifacts,
        job_review_rows = rows,
        heldout_model_rank_rows = ranks,
        diagnostic_failure_rows = failures,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :record_full_brms_like_pilot_execution_keep_claims_blocked,
            publication_grade_brms_like_pilot_executed =
                all_five_pilot_jobs_executed,
            all_mcmc_diagnostic_gates_passed,
            sampler_diagnostic_failure_detected,
            reference_best_heldout_score,
            mcmc_model_beat_reference_on_heldout_elpd,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            public_model_weight_claim_allowed = false,
            sparse_mgmfrm_superiority_claim_allowed = false,
            required_followup =
                sampler_diagnostic_failure_detected ?
                :review_scalar_sampler_divergences_before_batch_expansion :
                :review_publication_grade_refit_diagnostics_or_expand_batch,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            pilot_only = true,
            all_artifacts_valid,
            publication_grade_brms_like_pilot_executed =
                all_five_pilot_jobs_executed,
            all_five_pilot_jobs_executed,
            all_expected_job_artifacts_present,
            all_executed_diagnostics_observed,
            all_mcmc_diagnostic_gates_passed,
            sampler_diagnostic_failure_detected,
            reference_best_heldout_score,
            mcmc_model_beat_reference_on_heldout_elpd,
            no_public_claim_allowed,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            full_125_unit_publication_grade_batch_completed = false,
            external_construct_dataset_still_required = true,
            n_input_artifacts = length(input_artifacts),
            n_expected_execution_units = length(JOBS),
            n_mcmc_execution_units = length(mcmc_rows),
            n_analytic_reference_units =
                count(row -> row.analytic_reference_scored, rows),
            n_job_review_rows = length(rows),
            n_heldout_model_rank_rows = length(ranks),
            n_diagnostic_failure_rows = length(failures),
            n_mcmc_diagnostic_failure_rows =
                count(row -> row.mcmc_refit_required, failures),
            n_diagnostic_gate_passed_mcmc_units =
                length(diagnostic_passed_mcmc_rows),
            best_heldout_model,
            best_mcmc_heldout_model,
            best_diagnostic_passed_mcmc_model,
            best_heldout_elpd = first(ranks).heldout_elpd,
            best_mcmc_heldout_elpd =
                isempty(mcmc_ranks) ? missing : first(mcmc_ranks).heldout_elpd,
            best_diagnostic_passed_mcmc_heldout_elpd =
                isempty(diagnostic_passed_mcmc_ranks) ? missing :
                first(diagnostic_passed_mcmc_ranks).heldout_elpd,
            n_blocker_rows = length(blockers),
            n_resolved_blockers = count(row -> row.resolved, blockers),
            n_blockers = length(remaining_blockers),
            remaining_public_blockers = remaining_blockers,
            recommendation =
                sampler_diagnostic_failure_detected ?
                :review_scalar_sampler_divergences_keep_claims_blocked :
                :review_publication_grade_refit_diagnostics_keep_claims_blocked,
            next_gate =
                sampler_diagnostic_failure_detected ?
                :review_scalar_sampler_divergences_before_batch_expansion :
                :review_publication_grade_refit_diagnostics_or_expand_batch,
        ),
    )
end

function main(args)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output, artifact)
    println("wrote ", rel(options.output))
    println("passed=", artifact.summary.passed,
        " mcmc_gates=", artifact.summary.n_diagnostic_gate_passed_mcmc_units,
        "/", artifact.summary.n_mcmc_execution_units,
        " best=", artifact.summary.best_heldout_model,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
