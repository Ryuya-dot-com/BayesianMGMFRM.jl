#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_sampler_remediation_review.json")
const DEFAULT_PRIMARY_REVIEW =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_pilot_results_review.json")
const DEFAULT_RESULT_ROOT =
    joinpath(ROOT, "artifacts", "publication_grade_refit_pilot_remediation")
const FIXTURE_ROOT = joinpath(ROOT, "test", "fixtures")
const RUNNER_SCRIPT =
    "scripts/run_mgmfrm_publication_grade_refit_job.jl"

include(joinpath(@__DIR__, "local_json.jl"))

const PRIMARY_REVIEW_SCHEMA =
    "bayesianmgmfrm.mgmfrm_publication_grade_refit_pilot_results_review.v1"

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
        "mgmfrm_publication_grade_refit_sampler_remediation_review_v1",
    review_kind =
        :local_publication_grade_refit_sampler_remediation_review,
    publication_or_registration_action = false,
    local_only = true,
    pilot_only = true,
    remediation_only = true,
    source_primary_review =
        :mgmfrm_publication_grade_refit_pilot_results_review,
    trigger_gate = :review_sampler_diagnostic_failures_before_expand_batch,
    remediation_scope =
        :scalar_gmfrm_divergence_target_acceptance_escalation,
    thresholds = (;
        require_primary_review_present = true,
        require_primary_review_passed = true,
        require_remediation_target_rows_recorded = true,
        require_missing_or_valid_remediation_artifacts = true,
        require_primary_pilot_results_preserved = true,
        require_remediation_descriptive_only = true,
        require_all_public_claims_blocked = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM publication-grade sampler remediation review.

    This review records a separate scalar-GMFRM remediation run for the pilot
    sampler warning without replacing the preregistered primary pilot result.
    Local runner artifacts are ignored when writing committed fixtures unless
    --read-local-artifacts is supplied.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_sampler_remediation_review.jl [--output PATH]

    Options:
      --output PATH          Review fixture path.
      --primary-review PATH  Pilot results-review fixture path.
      --result-root PATH     Override remediation artifact directory.
      --read-local-artifacts Read local remediation artifacts even when writing
                             under test/fixtures.
      --ignore-local-artifacts
                             Treat remediation artifacts as absent.
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    primary_review = DEFAULT_PRIMARY_REVIEW
    result_root = DEFAULT_RESULT_ROOT
    ignore_local_artifacts = nothing
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg == "--primary-review"
            index < length(args) || error("--primary-review requires a path")
            primary_review = abspath(args[index + 1])
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
    return (; output, primary_review, result_root, ignore_local_artifacts)
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

function primary_review_record(path::AbstractString)
    exists = isfile(path)
    if !exists
        return (;
            artifact = :mgmfrm_publication_grade_refit_pilot_results_review,
            path = rel(path),
            exists = false,
            sha256 = missing,
            schema = missing,
            expected_schema = PRIMARY_REVIEW_SCHEMA,
            schema_matches = false,
            summary_passed = false,
            n_executed_execution_units = 0,
            sampler_diagnostic_failure_detected = false,
            next_gate = missing,
        )
    end
    artifact = load_json(path)
    schema = as_string(artifact[:schema])
    summary = artifact[:summary]
    return (;
        artifact = :mgmfrm_publication_grade_refit_pilot_results_review,
        path = rel(path),
        exists,
        sha256 = file_sha256(path),
        schema,
        expected_schema = PRIMARY_REVIEW_SCHEMA,
        schema_matches = schema == PRIMARY_REVIEW_SCHEMA,
        summary_passed = json_bool(summary, :passed),
        n_executed_execution_units =
            json_int(summary, :n_executed_execution_units),
        sampler_diagnostic_failure_detected =
            json_bool(summary, :sampler_diagnostic_failure_detected),
        next_gate = json_get(summary, :next_gate, missing),
    )
end

function remediation_target_rows(result_root)
    remediation_id =
        "well_specified_current_q__scalar_gmfrm_baseline__fold1__target_accept_0p90"
    result_path = joinpath(result_root, string(remediation_id, "_result.json"))
    command =
        "julia --project=. $RUNNER_SCRIPT " *
        "--execution-unit well_specified_current_q__scalar_gmfrm_baseline__fold1 " *
        "--chains 4 --warmup-per-chain 500 --draws-per-chain 1000 " *
        "--target-acceptance 0.9 --seed 2026375901 " *
        "--output $(rel(result_path))"
    return [
        (;
            remediation_id = Symbol(remediation_id),
            source_execution_unit_id =
                :well_specified_current_q__scalar_gmfrm_baseline__fold1,
            scenario = :well_specified_current_q,
            model = :scalar_gmfrm_baseline,
            fold = 1,
            trigger_diagnostic = :divergence_count_max,
            trigger_value_observed_locally = 2.0,
            trigger_threshold = 0.0,
            remediation_action = :increase_target_acceptance,
            primary_target_acceptance = 0.8,
            remediation_target_acceptance = 0.9,
            chains = 4,
            warmup_per_chain = 500,
            draws_per_chain = 1000,
            seed = 2026375901,
            result_artifact_path = rel(result_path),
            diagnostic_artifact_path =
                rel(joinpath(result_root,
                    string(remediation_id, "_diagnostics.json"))),
            heldout_score_artifact_path =
                rel(joinpath(result_root,
                    string(remediation_id, "_heldout_score.json"))),
            command,
            local_only = true,
            primary_result_replaced = false,
            public_claim_allowed = false,
        ),
    ]
end

function artifact_path(row, key::Symbol)
    return fixture_path(as_string(row[key]))
end

function remediation_artifact_record(kind::Symbol, path::AbstractString,
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
            n_divergences = missing,
            max_rhat = missing,
            min_ess = missing,
            e_bfmi = missing,
            heldout_elpd = missing,
            heldout_expected_score_mae = missing,
            heldout_expected_score_rmse = missing,
        )
    end
    artifact = load_json(path)
    schema = as_string(artifact[:schema])
    summary = artifact[:summary]
    score_row = haskey(artifact, :score_row) ? artifact[:score_row] : nothing
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
        n_divergences = score_row === nothing ? missing :
            json_float_or_missing(score_row, :n_divergences),
        max_rhat = score_row === nothing ? missing :
            json_float_or_missing(score_row, :max_rhat),
        min_ess = score_row === nothing ? missing :
            json_float_or_missing(score_row, :min_ess),
        e_bfmi = score_row === nothing ? missing :
            json_float_or_missing(score_row, :e_bfmi),
        heldout_elpd = score_row === nothing ? missing :
            json_float_or_missing(score_row, :heldout_elpd),
        heldout_expected_score_mae = score_row === nothing ? missing :
            json_float_or_missing(score_row, :heldout_expected_score_mae),
        heldout_expected_score_rmse = score_row === nothing ? missing :
            json_float_or_missing(score_row, :heldout_expected_score_rmse),
    )
end

function remediation_review_row(target; ignore_local_artifacts::Bool)
    result = remediation_artifact_record(
        :result,
        artifact_path(target, :result_artifact_path),
        EXPECTED_SCHEMAS.result;
        ignore_local_artifact = ignore_local_artifacts,
    )
    diagnostics = remediation_artifact_record(
        :diagnostics,
        artifact_path(target, :diagnostic_artifact_path),
        EXPECTED_SCHEMAS.diagnostics;
        ignore_local_artifact = ignore_local_artifacts,
    )
    heldout = remediation_artifact_record(
        :heldout,
        artifact_path(target, :heldout_score_artifact_path),
        EXPECTED_SCHEMAS.heldout;
        ignore_local_artifact = ignore_local_artifacts,
    )
    artifacts = (result, diagnostics, heldout)
    complete = all(row -> row.exists && row.schema_matches &&
        row.summary_passed, artifacts)
    observed = complete && result.executed && !result.dry_run
    return (;
        remediation_id = target.remediation_id,
        source_execution_unit_id = target.source_execution_unit_id,
        scenario = target.scenario,
        model = target.model,
        fold = target.fold,
        trigger_diagnostic = target.trigger_diagnostic,
        remediation_action = target.remediation_action,
        primary_target_acceptance = target.primary_target_acceptance,
        remediation_target_acceptance = target.remediation_target_acceptance,
        result_artifact = result,
        diagnostic_artifact = diagnostics,
        heldout_artifact = heldout,
        artifacts_complete = complete,
        remediation_observed = observed,
        diagnostic_gate_passed = complete && result.diagnostic_gate_passed,
        n_divergences = result.n_divergences,
        max_rhat = result.max_rhat,
        min_ess = result.min_ess,
        e_bfmi = result.e_bfmi,
        heldout_elpd = result.heldout_elpd,
        heldout_expected_score_mae = result.heldout_expected_score_mae,
        heldout_expected_score_rmse = result.heldout_expected_score_rmse,
        primary_result_replaced = false,
        descriptive_only = true,
        public_claim_allowed = false,
    )
end

function blocker_rows(values)
    return [
        (blocker = :primary_sampler_failure_review_not_completed,
            blocks = :batch_expansion,
            resolved = values.remediation_success_observed),
        (blocker = :remediation_not_independently_replicated,
            blocks = :public_sampler_stability_claims,
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

function build_artifact(options)
    ignore_local_artifacts = options.ignore_local_artifacts === nothing ?
        path_inside(options.output, FIXTURE_ROOT) :
        Bool(options.ignore_local_artifacts)
    primary = primary_review_record(options.primary_review)
    targets = remediation_target_rows(options.result_root)
    rows = [
        remediation_review_row(row; ignore_local_artifacts)
        for row in targets
    ]
    n_present_artifacts =
        sum((row.result_artifact.exists ? 1 : 0) +
            (row.diagnostic_artifact.exists ? 1 : 0) +
            (row.heldout_artifact.exists ? 1 : 0) for row in rows; init = 0)
    n_valid_artifacts =
        sum((row.result_artifact.schema_matches ? 1 : 0) +
            (row.diagnostic_artifact.schema_matches ? 1 : 0) +
            (row.heldout_artifact.schema_matches ? 1 : 0) for row in rows; init = 0)
    all_expected_artifacts_present =
        n_present_artifacts == 3 * length(rows)
    all_expected_remediation_artifacts_present =
        all_expected_artifacts_present && n_valid_artifacts == 3 * length(rows)
    missing_or_valid_remediation_artifacts =
        all(rows) do row
            artifacts = (row.result_artifact, row.diagnostic_artifact,
                row.heldout_artifact)
            all(artifact -> !artifact.exists || artifact.schema_matches,
                artifacts)
        end
    n_observed = count(row -> row.remediation_observed, rows)
    n_passed = count(row -> row.diagnostic_gate_passed, rows)
    remediation_success_observed =
        !isempty(rows) && n_observed == length(rows) && n_passed == length(rows)
    no_public_claim_allowed = all(row -> !row.public_claim_allowed, rows)
    no_primary_result_replaced = all(row -> !row.primary_result_replaced, rows)
    blockers = blocker_rows((; remediation_success_observed))
    passed = primary.exists &&
        primary.schema_matches &&
        primary.summary_passed &&
        length(targets) == 1 &&
        missing_or_valid_remediation_artifacts &&
        no_primary_result_replaced &&
        no_public_claim_allowed
    next_gate = remediation_success_observed ?
        :review_remediated_scalar_against_primary_before_batch_expansion :
        :execute_sampler_remediation_if_scalar_divergence_observed
    recommendation = remediation_success_observed ?
        :retain_primary_result_and_record_remediated_scalar_diagnostic_context :
        :run_remediation_after_primary_sampler_failure_keep_claims_blocked

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_sampler_remediation_review.v1",
        family = :mgmfrm,
        scope = :publication_grade_refit_sampler_remediation_review,
        status =
            :publication_grade_refit_sampler_remediation_review_recorded,
        decision =
            :record_sampler_remediation_without_replacing_primary_pilot_result,
        public_fit = true,
        experimental_public = true,
        fit_ready = Bool(primary.summary_passed),
        local_only = true,
        pilot_only = true,
        remediation_only = true,
        local_artifacts_ignored_for_fixture = ignore_local_artifacts,
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
        input_artifacts = [primary],
        remediation_target_rows = targets,
        remediation_review_rows = rows,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :record_sampler_remediation_review_keep_primary_result,
            primary_pilot_results_reviewed = Bool(primary.summary_passed),
            primary_sampler_diagnostic_failure_detected =
                primary.sampler_diagnostic_failure_detected,
            remediation_success_observed,
            primary_result_replaced = false,
            public_fit_metric_claim_allowed = false,
            public_model_weight_claim_allowed = false,
            required_followup = next_gate,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            pilot_only = true,
            remediation_only = true,
            local_artifacts_ignored_for_fixture = ignore_local_artifacts,
            primary_review_present = primary.exists,
            primary_review_schema_matches = primary.schema_matches,
            primary_review_passed = primary.summary_passed,
            primary_sampler_diagnostic_failure_detected =
                primary.sampler_diagnostic_failure_detected,
            remediation_target_rows_recorded = length(targets) == 1,
            missing_or_valid_remediation_artifacts,
            all_expected_remediation_artifacts_present,
            remediation_success_observed,
            primary_result_preserved = no_primary_result_replaced,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            n_input_artifacts = 1,
            n_remediation_target_rows = length(targets),
            n_remediation_review_rows = length(rows),
            n_expected_remediation_artifacts = 3 * length(rows),
            n_present_remediation_artifacts = n_present_artifacts,
            n_valid_remediation_artifacts = n_valid_artifacts,
            n_observed_remediation_units = n_observed,
            n_diagnostic_gate_passed_remediation_units = n_passed,
            n_blocker_rows = length(blockers),
            n_blockers = count(row -> !row.resolved, blockers),
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
        " observed=", artifact.summary.n_observed_remediation_units,
        "/", artifact.summary.n_remediation_target_rows,
        " remediation_success=",
        artifact.summary.remediation_success_observed,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
