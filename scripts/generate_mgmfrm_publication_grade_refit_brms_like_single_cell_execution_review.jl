#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const UNIT_ID =
    "well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold1"
const ARTIFACT_STEM =
    joinpath(ROOT, "artifacts", "publication_grade_refit_pilot_brms_like",
        "$(UNIT_ID)_4_1000_1000_ta080")
const DEFAULT_RESULT = string(ARTIFACT_STEM, "_result.json")
const DEFAULT_DIAGNOSTICS = string(ARTIFACT_STEM, "_diagnostics.json")
const DEFAULT_HELDOUT = string(ARTIFACT_STEM, "_heldout_score.json")
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_brms_like_single_cell_execution_review.json")

include(joinpath(@__DIR__, "local_json.jl"))

const EXPECTED_SCHEMAS = (;
    result =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_result.v1",
    diagnostics =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_diagnostics.v1",
    heldout =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_heldout_score.v1",
)

function usage()
    return """
    Generate a compact review fixture for the brms-like single-cell MGMFRM
    publication-grade pilot execution.

    This reads local ignored runner artifacts and writes a small tracked
    evidence summary. It does not copy raw runner artifacts into the repository
    and does not allow any public MGMFRM claim.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_brms_like_single_cell_execution_review.jl [--output PATH]

    Options:
      --result PATH       Result artifact path.
      --diagnostics PATH  Diagnostics artifact path.
      --heldout PATH      Heldout-score artifact path.
      --output PATH       Review fixture path.
    """
end

function parse_args(args)
    result = DEFAULT_RESULT
    diagnostics = DEFAULT_DIAGNOSTICS
    heldout = DEFAULT_HELDOUT
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--result"
            index < length(args) || error("--result requires a path")
            result = abspath(args[index + 1])
            index += 2
        elseif arg == "--diagnostics"
            index < length(args) || error("--diagnostics requires a path")
            diagnostics = abspath(args[index + 1])
            index += 2
        elseif arg == "--heldout"
            index < length(args) || error("--heldout requires a path")
            heldout = abspath(args[index + 1])
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
    return (; result, diagnostics, heldout, output)
end

project_version() = String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)

as_string(value) = String(value)
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_float(value) = Float64(value)

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

function diagnostic_review_rows(diagnostics)
    return [
        (;
            diagnostic = String(row[:diagnostic]),
            source = String(row[:source]),
            comparison = String(row[:comparison]),
            threshold = native_scalar(row[:threshold]),
            value = native_scalar(row[:value]),
            applicable = Bool(row[:applicable]),
            observed = Bool(row[:observed]),
            passed = Bool(row[:passed]),
            public_claim_allowed = Bool(row[:public_claim_allowed]),
        )
        for row in diagnostics[:diagnostic_rows]
    ]
end

function blocker_rows()
    return [
        (blocker = :single_brms_like_revised_q_cell_not_executed,
            blocks = :initial_publication_grade_runtime_evidence,
            resolved = true),
        (blocker = :remaining_publication_grade_pilot_jobs_not_executed,
            blocks = :pilot_model_comparison_and_rank_review,
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

function build_artifact(options)
    result = load_json(options.result)
    diagnostics = load_json(options.diagnostics)
    heldout = load_json(options.heldout)
    score = result[:score_row]
    sampler = diagnostics[:sampler_summary]
    heldout_summary = heldout[:summary]
    rows = diagnostic_review_rows(diagnostics)
    blockers = blocker_rows()
    remaining_blockers = [row.blocker for row in blockers if !row.resolved]
    brms_like_budget_observed =
        Int(score[:chains]) == 4 &&
        Int(score[:warmup]) == 1000 &&
        Int(score[:draws_per_chain]) == 1000 &&
        Int(score[:n_draws]) == 4000
    all_diagnostics_passed =
        !isempty(rows) && all(row -> row.observed && row.passed, rows)
    all_public_claims_blocked =
        !Bool(score[:public_fit_metric_claim_allowed]) &&
        !Bool(score[:public_model_weight_claim_allowed]) &&
        !Bool(score[:sparse_superiority_claim_allowed]) &&
        all(row -> !row.public_claim_allowed, rows)
    input_artifacts = [
        artifact_record(:result, options.result, result,
            EXPECTED_SCHEMAS.result),
        artifact_record(:diagnostics, options.diagnostics, diagnostics,
            EXPECTED_SCHEMAS.diagnostics),
        artifact_record(:heldout, options.heldout, heldout,
            EXPECTED_SCHEMAS.heldout),
    ]
    all_artifacts_valid =
        all(row -> row.exists && row.schema_matches && row.summary_passed,
            input_artifacts)
    passed = all_artifacts_valid &&
        brms_like_budget_observed &&
        Bool(score[:fit_succeeded]) &&
        Bool(score[:scoring_succeeded]) &&
        Bool(score[:diagnostic_passed]) &&
        all_diagnostics_passed &&
        all_public_claims_blocked &&
        Bool(heldout_summary[:heldout_predictive_score_computed]) &&
        Bool(heldout_summary[:all_pointwise_scores_finite])
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_brms_like_single_cell_execution_review.v1",
        family = :mgmfrm,
        scope = :publication_grade_refit_brms_like_single_cell_execution_review,
        status = :publication_grade_refit_brms_like_single_cell_executed,
        decision =
            :record_brms_like_single_cell_revised_q_publication_grade_execution,
        public_fit = true,
        experimental_public = true,
        local_only = true,
        pilot_only = true,
        single_cell_only = true,
        local_artifacts_required_for_generation = true,
        publication_or_registration_action = false,
        publication_grade_gate_defined = true,
        publication_grade_pilot_plan_recorded = true,
        publication_grade_pilot_execution_harness_recorded = true,
        publication_grade_brms_like_single_cell_executed = true,
        full_publication_grade_pilot_executed = false,
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
                :mgmfrm_publication_grade_refit_brms_like_single_cell_execution_review_v1,
            review_kind =
                :local_brms_like_single_cell_publication_grade_execution_review,
            source_runner = :run_mgmfrm_publication_grade_refit_job,
            execution_unit_id = Symbol(UNIT_ID),
            planned_followup =
                :execute_remaining_publication_grade_refit_pilot_jobs_or_attach_external_construct_dataset,
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
        execution_summary = (;
            execution_unit_id = String(score[:execution_unit_id]),
            scenario = String(score[:scenario]),
            model = String(score[:model]),
            fold = Int(score[:fold]),
            model_family = String(score[:model_family]),
            q_profile = String(score[:q_profile]),
            fit_seed = Int(score[:fit_seed]),
            backend = String(score[:backend]),
            sampler = String(score[:sampler]),
            target_acceptance = Float64(score[:target_acceptance]),
            chains = Int(score[:chains]),
            warmup_per_chain = Int(score[:warmup]),
            draws_per_chain = Int(score[:draws_per_chain]),
            total_retained_draws = Int(score[:n_draws]),
            n_train_observations = Int(score[:n_train_observations]),
            n_heldout_observations = Int(score[:n_heldout_observations]),
            n_dimensions = Int(score[:n_dimensions]),
            n_items = Int(score[:n_items]),
            q_validation_passed = Bool(score[:q_validation_passed]),
            n_q_validation_warnings = Int(score[:n_q_validation_warnings]),
            fit_succeeded = Bool(score[:fit_succeeded]),
            scoring_succeeded = Bool(score[:scoring_succeeded]),
            returned_type = String(score[:returned_type]),
        ),
        sampler_summary = (;
            diagnostic_flag = String(score[:diagnostic_flag]),
            diagnostic_passed = Bool(score[:diagnostic_passed]),
            max_rhat = Float64(score[:max_rhat]),
            min_ess = Float64(score[:min_ess]),
            e_bfmi = Float64(score[:e_bfmi]),
            n_divergences = Int(score[:n_divergences]),
            n_max_treedepth = Int(score[:n_max_treedepth]),
            n_nonfinite_logdensity =
                Int(score[:n_nonfinite_logdensity]),
            n_failed_direct_constraints =
                Int(score[:n_failed_direct_constraints]),
            diagnostic_surface_flag = String(sampler[:flag]),
            diagnostic_surface_passed = Bool(sampler[:passed]),
        ),
        heldout_summary = (;
            heldout_predictive_score_computed =
                Bool(heldout_summary[:heldout_predictive_score_computed]),
            n_heldout_pointwise_rows =
                Int(heldout_summary[:n_heldout_pointwise_rows]),
            heldout_elpd = Float64(heldout_summary[:heldout_elpd]),
            heldout_mean_log_predictive_density =
                Float64(heldout_summary[:heldout_mean_log_predictive_density]),
            heldout_expected_score_mae =
                Float64(heldout_summary[:heldout_expected_score_mae]),
            heldout_expected_score_rmse =
                Float64(heldout_summary[:heldout_expected_score_rmse]),
            all_pointwise_scores_finite =
                Bool(heldout_summary[:all_pointwise_scores_finite]),
        ),
        diagnostic_review_rows = rows,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :record_brms_like_single_cell_execution_keep_claims_blocked,
            brms_like_budget_observed,
            single_cell_execution_passed = passed,
            full_publication_grade_pilot_executed = false,
            full_publication_grade_batch_completed = false,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            public_model_weight_claim_allowed = false,
            sparse_mgmfrm_superiority_claim_allowed = false,
            required_followup =
                :execute_remaining_publication_grade_refit_pilot_jobs_or_attach_external_construct_dataset,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            pilot_only = true,
            single_cell_only = true,
            all_artifacts_valid,
            brms_like_budget_observed,
            publication_grade_brms_like_single_cell_executed = true,
            full_publication_grade_pilot_executed = false,
            full_125_unit_publication_grade_batch_completed = false,
            fit_succeeded = Bool(score[:fit_succeeded]),
            scoring_succeeded = Bool(score[:scoring_succeeded]),
            diagnostic_gate_passed = Bool(result[:summary][:diagnostic_gate_passed]),
            all_diagnostics_passed,
            all_public_claims_blocked,
            q_validation_passed = Bool(score[:q_validation_passed]),
            n_q_validation_warnings = Int(score[:n_q_validation_warnings]),
            max_rhat = Float64(score[:max_rhat]),
            min_ess = Float64(score[:min_ess]),
            e_bfmi = Float64(score[:e_bfmi]),
            n_divergences = Int(score[:n_divergences]),
            n_max_treedepth = Int(score[:n_max_treedepth]),
            heldout_elpd = Float64(heldout_summary[:heldout_elpd]),
            heldout_mean_log_predictive_density =
                Float64(heldout_summary[:heldout_mean_log_predictive_density]),
            heldout_expected_score_mae =
                Float64(heldout_summary[:heldout_expected_score_mae]),
            heldout_expected_score_rmse =
                Float64(heldout_summary[:heldout_expected_score_rmse]),
            n_input_artifacts = length(input_artifacts),
            n_diagnostic_review_rows = length(rows),
            n_failed_diagnostic_review_rows =
                count(row -> !row.passed, rows),
            n_blocker_rows = length(blockers),
            n_resolved_blockers = count(row -> row.resolved, blockers),
            n_blockers = length(remaining_blockers),
            remaining_public_blockers = remaining_blockers,
            recommendation =
                :execute_remaining_publication_grade_pilot_jobs_keep_claims_blocked,
            next_gate =
                :execute_remaining_publication_grade_refit_pilot_jobs_or_attach_external_construct_dataset,
        ),
    )
end

function main(args)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output, artifact)
    println("wrote ", rel(options.output))
    println("passed=", artifact.summary.passed,
        " max_rhat=", artifact.summary.max_rhat,
        " min_ess=", artifact.summary.min_ess,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
