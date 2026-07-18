#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const RESULT_ROOT =
    joinpath(ROOT, "artifacts", "publication_grade_refit_pilot_brms_like")
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review.json")
const PRIMARY_REVIEW =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_brms_like_pilot_execution_review.json")

include(joinpath(@__DIR__, "local_json.jl"))

const EXPECTED_SCHEMAS = (;
    pilot_review =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_brms_like_pilot_execution_review.v1",
    result =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_result.v1",
    diagnostics =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_diagnostics.v1",
    heldout =
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_heldout_score.v1",
)

const EXECUTION_UNIT_ID =
    "well_specified_current_q__scalar_gmfrm_baseline__fold1"
const PRIMARY_SUFFIX = "_4_1000_1000_ta080"
const REMEDIATION_SUFFIX = "_4_1000_1000_ta090"

function usage()
    return """
    Generate the brms-like scalar GMFRM sampler-remediation review fixture.

    This reads the ignored scalar pilot artifacts at target acceptance 0.8 and
    0.9, records whether the 0.9 rerun removes divergences under the same
    4-chain/1000-warmup/1000-retained-draw budget, and keeps all public model
    comparison claims blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review.jl [--output PATH]

    Options:
      --result-root PATH    Directory containing local runner artifacts.
      --primary-review PATH Brms-like pilot execution review fixture path.
      --output PATH         Review fixture path.
    """
end

function parse_args(args)
    result_root = RESULT_ROOT
    primary_review = PRIMARY_REVIEW
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--result-root"
            index < length(args) || error("--result-root requires a path")
            result_root = abspath(args[index + 1])
            index += 2
        elseif arg == "--primary-review"
            index < length(args) || error("--primary-review requires a path")
            primary_review = abspath(args[index + 1])
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
    return (; result_root, primary_review, output)
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

function artifact_paths(result_root::AbstractString, suffix::AbstractString)
    stem = joinpath(result_root, string(EXECUTION_UNIT_ID, suffix))
    return (;
        result = string(stem, "_result.json"),
        diagnostics = string(stem, "_diagnostics.json"),
        heldout = string(stem, "_heldout_score.json"),
    )
end

function input_record(kind::Symbol, path::AbstractString,
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

function review_input_record(path::AbstractString, artifact)
    schema = as_string(artifact[:schema])
    summary = artifact[:summary]
    return (;
        artifact = :mgmfrm_publication_grade_refit_brms_like_pilot_execution_review,
        path = rel(path),
        exists = true,
        sha256 = file_sha256(path),
        schema,
        expected_schema = EXPECTED_SCHEMAS.pilot_review,
        schema_matches = schema == EXPECTED_SCHEMAS.pilot_review,
        summary_passed = json_bool(summary, :passed),
        sampler_diagnostic_failure_detected =
            json_bool(summary, :sampler_diagnostic_failure_detected),
        next_gate = as_symbol(summary[:next_gate]),
    )
end

function diagnostic_map(diagnostics)
    return Dict(
        as_symbol(row[:diagnostic]) => row for row in diagnostics[:diagnostic_rows]
        if Bool(row[:applicable]) && Bool(row[:observed])
    )
end

function diagnostic_review_rows(label::Symbol, diagnostics)
    return [
        (;
            run_label = label,
            diagnostic = as_symbol(row[:diagnostic]),
            source = as_symbol(row[:source]),
            comparison = as_symbol(row[:comparison]),
            threshold = row[:threshold],
            value = row[:value],
            passed = Bool(row[:passed]),
            public_claim_allowed = false,
        )
        for row in diagnostics[:diagnostic_rows]
        if Bool(row[:applicable]) && Bool(row[:observed])
    ]
end

function scalar_summary(label::Symbol, suffix::AbstractString,
        result, diagnostics, heldout)
    score = result[:score_row]
    result_summary = result[:summary]
    diagnostic_summary = diagnostics[:summary]
    sampler_summary = diagnostics[:sampler_summary]
    heldout_summary = heldout[:summary]
    return (;
        run_label = label,
        execution_unit_id = Symbol(EXECUTION_UNIT_ID),
        artifact_suffix = suffix,
        scenario = as_symbol(score[:scenario]),
        model = :scalar_gmfrm_baseline,
        fold = Int(score[:fold]),
        model_family = as_symbol(score[:model_family]),
        executed = Bool(result_summary[:executed]),
        dry_run = Bool(result_summary[:dry_run]),
        diagnostic_gate_passed = Bool(result_summary[:diagnostic_gate_passed]),
        diagnostics_observed =
            Int(diagnostic_summary[:n_observed_applicable_diagnostic_rows]) >
            0,
        sampler_flag = as_symbol(score[:diagnostic_flag]),
        diagnostic_surface_flag = as_symbol(sampler_summary[:flag]),
        diagnostic_surface_passed = Bool(sampler_summary[:passed]),
        fit_seed = Int(json_get(score, :fit_seed,
            result[:fit_controls][:seed])),
        backend = as_symbol(score[:backend]),
        sampler = as_symbol(score[:sampler]),
        target_acceptance = Float64(score[:target_acceptance]),
        chains = Int(score[:chains]),
        warmup_per_chain = Int(score[:warmup]),
        draws_per_chain = Int(score[:draws_per_chain]),
        total_retained_draws = Int(score[:n_draws]),
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
        public_claim_allowed = false,
    )
end

function comparison_row(primary, remediation)
    delta_elpd = remediation.heldout_elpd - primary.heldout_elpd
    return (;
        comparison = :primary_ta080_vs_remediated_ta090_scalar_gmfrm,
        execution_unit_id = Symbol(EXECUTION_UNIT_ID),
        model = :scalar_gmfrm_baseline,
        same_mcmc_budget =
            primary.chains == remediation.chains &&
            primary.warmup_per_chain == remediation.warmup_per_chain &&
            primary.draws_per_chain == remediation.draws_per_chain,
        primary_target_acceptance = primary.target_acceptance,
        remediation_target_acceptance = remediation.target_acceptance,
        primary_diagnostic_gate_passed = primary.diagnostic_gate_passed,
        remediation_diagnostic_gate_passed =
            remediation.diagnostic_gate_passed,
        primary_n_divergences = primary.n_divergences,
        remediation_n_divergences = remediation.n_divergences,
        delta_n_divergences_remediation_minus_primary =
            remediation.n_divergences - primary.n_divergences,
        delta_max_rhat_remediation_minus_primary =
            remediation.max_rhat - primary.max_rhat,
        delta_min_ess_remediation_minus_primary =
            remediation.min_ess - primary.min_ess,
        delta_e_bfmi_remediation_minus_primary =
            remediation.e_bfmi - primary.e_bfmi,
        delta_heldout_elpd_remediation_minus_primary = delta_elpd,
        delta_expected_score_mae_remediation_minus_primary =
            remediation.heldout_expected_score_mae -
            primary.heldout_expected_score_mae,
        delta_expected_score_rmse_remediation_minus_primary =
            remediation.heldout_expected_score_rmse -
            primary.heldout_expected_score_rmse,
        remediation_resolves_primary_divergence =
            primary.n_divergences > 0 &&
            remediation.n_divergences == 0 &&
            remediation.diagnostic_gate_passed,
        heldout_elpd_materially_changed = abs(delta_elpd) > 0.05,
        remediation_improves_heldout_elpd = delta_elpd > 0.0,
        interpretation =
            :target_acceptance_0p90_removed_scalar_divergences_without_material_heldout_shift,
        primary_result_replaced = false,
        descriptive_only = true,
        public_claim_allowed = false,
    )
end

function batch_policy_row(comparison)
    resolved = comparison.remediation_resolves_primary_divergence
    return (;
        policy = :brms_like_publication_grade_scalar_sampler_setting,
        affected_model = :scalar_gmfrm_baseline,
        affected_execution_unit = Symbol(EXECUTION_UNIT_ID),
        primary_target_acceptance = 0.8,
        selected_batch_target_acceptance = resolved ? 0.9 : missing,
        default_non_scalar_target_acceptance = 0.8,
        selected_warmup_per_chain = 1000,
        selected_draws_per_chain = 1000,
        selection_basis = resolved ?
            :local_brms_like_rerun_removed_scalar_divergences :
            :scalar_divergence_remediation_not_resolved,
        primary_pilot_result_replaced = false,
        batch_expansion_allowed_for_scalar_local_only = resolved,
        batch_expansion_allowed_for_public_claim = false,
        requires_replication_across_folds = true,
        public_claim_allowed = false,
    )
end

function blocker_rows(values)
    return [
        (blocker = :scalar_divergence_not_remediated,
            blocks = :scalar_batch_sampler_policy,
            resolved = values.scalar_divergence_remediated),
        (blocker = :target_acceptance_policy_not_replicated_across_folds,
            blocks = :public_sampler_stability_claims,
            resolved = false),
        (blocker =
                :fit_metric_thresholds_not_reestimated_under_publication_grade_draws,
            blocks = :threshold_comparison_and_claim_calibration,
            resolved = false),
        (blocker = :null_reference_best_heldout_score,
            blocks = :structured_model_superiority_claims,
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
    primary_review = load_json(options.primary_review)
    primary_paths = artifact_paths(options.result_root, PRIMARY_SUFFIX)
    remediation_paths = artifact_paths(options.result_root, REMEDIATION_SUFFIX)

    primary_result = load_json(primary_paths.result)
    primary_diagnostics = load_json(primary_paths.diagnostics)
    primary_heldout = load_json(primary_paths.heldout)
    remediation_result = load_json(remediation_paths.result)
    remediation_diagnostics = load_json(remediation_paths.diagnostics)
    remediation_heldout = load_json(remediation_paths.heldout)

    input_review = review_input_record(options.primary_review, primary_review)
    input_artifacts = [
        input_record(:primary_result, primary_paths.result, primary_result,
            EXPECTED_SCHEMAS.result),
        input_record(:primary_diagnostics, primary_paths.diagnostics,
            primary_diagnostics, EXPECTED_SCHEMAS.diagnostics),
        input_record(:primary_heldout, primary_paths.heldout, primary_heldout,
            EXPECTED_SCHEMAS.heldout),
        input_record(:remediation_result, remediation_paths.result,
            remediation_result, EXPECTED_SCHEMAS.result),
        input_record(:remediation_diagnostics, remediation_paths.diagnostics,
            remediation_diagnostics, EXPECTED_SCHEMAS.diagnostics),
        input_record(:remediation_heldout, remediation_paths.heldout,
            remediation_heldout, EXPECTED_SCHEMAS.heldout),
    ]

    primary = scalar_summary(:primary_ta080, PRIMARY_SUFFIX, primary_result,
        primary_diagnostics, primary_heldout)
    remediation = scalar_summary(:remediated_ta090, REMEDIATION_SUFFIX,
        remediation_result, remediation_diagnostics, remediation_heldout)
    comparison = comparison_row(primary, remediation)
    policy = batch_policy_row(comparison)
    diagnostic_rows = vcat(
        diagnostic_review_rows(:primary_ta080, primary_diagnostics),
        diagnostic_review_rows(:remediated_ta090, remediation_diagnostics),
    )
    failures = [row for row in diagnostic_rows if !Bool(row.passed)]
    scalar_divergence_remediated =
        comparison.remediation_resolves_primary_divergence
    blockers = blocker_rows((; scalar_divergence_remediated))
    remaining_blockers = [row.blocker for row in blockers if !row.resolved]
    all_input_artifacts_valid =
        input_review.exists &&
        input_review.schema_matches &&
        input_review.summary_passed &&
        all(row -> row.exists && row.schema_matches && row.summary_passed,
            input_artifacts)
    same_mcmc_budget = comparison.same_mcmc_budget
    no_public_claim_allowed =
        all(row -> !row.public_claim_allowed, input_artifacts) &&
        !primary.public_claim_allowed &&
        !remediation.public_claim_allowed &&
        !comparison.public_claim_allowed &&
        !policy.public_claim_allowed &&
        all(row -> !row.public_claim_allowed, diagnostic_rows)
    passed = all_input_artifacts_valid &&
        primary.n_divergences == 2 &&
        !primary.diagnostic_gate_passed &&
        scalar_divergence_remediated &&
        same_mcmc_budget &&
        no_public_claim_allowed &&
        !policy.primary_pilot_result_replaced

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review.v1",
        family = :mgmfrm,
        scope =
            :publication_grade_refit_brms_like_scalar_remediation_review,
        status =
            :publication_grade_refit_brms_like_scalar_remediation_review_recorded,
        decision =
            :record_brms_like_scalar_target_acceptance_remediation,
        public_fit = true,
        experimental_public = true,
        local_only = true,
        pilot_only = true,
        remediation_only = true,
        local_artifacts_required_for_generation = true,
        publication_or_registration_action = false,
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
                :mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review_v1,
            review_kind =
                :local_brms_like_scalar_sampler_remediation_review,
            source_runner = :run_mgmfrm_publication_grade_refit_job,
            source_pilot_review =
                :mgmfrm_publication_grade_refit_brms_like_pilot_execution_review,
            execution_unit_id = Symbol(EXECUTION_UNIT_ID),
            primary_artifact_suffix = PRIMARY_SUFFIX,
            remediation_artifact_suffix = REMEDIATION_SUFFIX,
            thresholds = (;
                require_chains = 4,
                require_warmup_per_chain = 1000,
                require_draws_per_chain = 1000,
                require_total_retained_draws = 4000,
                require_primary_target_acceptance = 0.8,
                require_remediation_target_acceptance = 0.9,
                require_rank_normalized_rhat_max = 1.01,
                require_ess_min = 400.0,
                require_divergence_count_max = 0,
                require_max_treedepth_count_max = 0,
                require_ebfmi_min = 0.3,
                material_heldout_elpd_shift_threshold = 0.05,
                require_primary_result_preserved = true,
                require_public_claims_blocked = true,
            ),
        ),
        input_review_artifact = input_review,
        input_artifacts,
        primary_scalar_summary = primary,
        remediated_scalar_summary = remediation,
        scalar_remediation_comparison_row = comparison,
        batch_sampler_policy_row = policy,
        diagnostic_review_rows = diagnostic_rows,
        failed_diagnostic_review_rows = failures,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :use_target_acceptance_0p90_for_scalar_batch_local_only,
            primary_scalar_failure_reviewed =
                primary.n_divergences > 0 && !primary.diagnostic_gate_passed,
            remediation_success_observed = scalar_divergence_remediated,
            same_mcmc_budget,
            primary_result_replaced = false,
            scalar_batch_target_acceptance =
                policy.selected_batch_target_acceptance,
            scalar_batch_expansion_allowed_local_only =
                policy.batch_expansion_allowed_for_scalar_local_only,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            public_model_weight_claim_allowed = false,
            sparse_mgmfrm_superiority_claim_allowed = false,
            required_followup =
                :update_publication_grade_batch_plan_with_brms_like_scalar_target_acceptance_0p90,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            pilot_only = true,
            remediation_only = true,
            all_input_artifacts_valid,
            publication_grade_brms_like_pilot_executed = true,
            full_125_unit_publication_grade_batch_completed = false,
            primary_scalar_diagnostic_gate_passed =
                primary.diagnostic_gate_passed,
            remediated_scalar_diagnostic_gate_passed =
                remediation.diagnostic_gate_passed,
            primary_scalar_divergence_failure_recorded =
                primary.n_divergences > 0,
            remediation_success_observed = scalar_divergence_remediated,
            remediation_resolves_primary_divergence =
                comparison.remediation_resolves_primary_divergence,
            same_mcmc_budget,
            heldout_elpd_materially_changed =
                comparison.heldout_elpd_materially_changed,
            remediation_improves_heldout_elpd =
                comparison.remediation_improves_heldout_elpd,
            primary_result_preserved = true,
            scalar_batch_target_acceptance_policy_recorded = true,
            scalar_batch_target_acceptance =
                policy.selected_batch_target_acceptance,
            scalar_batch_expansion_allowed_local_only =
                policy.batch_expansion_allowed_for_scalar_local_only,
            scalar_batch_expansion_allowed_for_public_claim = false,
            no_public_claim_allowed,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            primary_n_divergences = primary.n_divergences,
            remediation_n_divergences = remediation.n_divergences,
            delta_n_divergences_remediation_minus_primary =
                comparison.delta_n_divergences_remediation_minus_primary,
            primary_heldout_elpd = primary.heldout_elpd,
            remediation_heldout_elpd = remediation.heldout_elpd,
            delta_heldout_elpd_remediation_minus_primary =
                comparison.delta_heldout_elpd_remediation_minus_primary,
            n_input_artifacts = length(input_artifacts),
            n_diagnostic_review_rows = length(diagnostic_rows),
            n_failed_diagnostic_review_rows = length(failures),
            n_blocker_rows = length(blockers),
            n_resolved_blockers = count(row -> row.resolved, blockers),
            n_blockers = length(remaining_blockers),
            remaining_public_blockers = remaining_blockers,
            recommendation =
                :update_scalar_batch_policy_to_target_acceptance_0p90_keep_claims_blocked,
            next_gate =
                :update_publication_grade_batch_plan_with_brms_like_scalar_target_acceptance_0p90,
        ),
    )
end

function main(args)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output, artifact)
    println("wrote ", rel(options.output))
    println("passed=", artifact.summary.passed,
        " divergences=", artifact.summary.primary_n_divergences,
        "->", artifact.summary.remediation_n_divergences,
        " delta_elpd=",
        artifact.summary.delta_heldout_elpd_remediation_minus_primary,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
