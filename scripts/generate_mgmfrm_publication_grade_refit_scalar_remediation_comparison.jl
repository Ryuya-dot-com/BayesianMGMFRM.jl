#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_scalar_remediation_comparison.json")
const DEFAULT_PRIMARY_REVIEW =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_pilot_results_review.json")
const DEFAULT_REMEDIATION_REVIEW =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_sampler_remediation_review.json")
const FIXTURE_ROOT = joinpath(ROOT, "test", "fixtures")

include(joinpath(@__DIR__, "local_json.jl"))

const PRIMARY_SCHEMA =
    "bayesianmgmfrm.mgmfrm_publication_grade_refit_pilot_results_review.v1"
const REMEDIATION_SCHEMA =
    "bayesianmgmfrm.mgmfrm_publication_grade_refit_sampler_remediation_review.v1"

const SCALAR_EXECUTION_UNIT =
    "well_specified_current_q__scalar_gmfrm_baseline__fold1"
const SCALAR_REMEDIATION_ID =
    "well_specified_current_q__scalar_gmfrm_baseline__fold1__target_accept_0p90"

const PROTOCOL = (;
    protocol_id =
        "mgmfrm_publication_grade_refit_scalar_remediation_comparison_v1",
    review_kind =
        :local_publication_grade_scalar_remediation_comparison,
    publication_or_registration_action = false,
    local_only = true,
    pilot_only = true,
    remediation_only = true,
    trigger_gate = :review_remediated_scalar_against_primary_before_batch_expansion,
    comparison_scope =
        :primary_scalar_target_accept_0p80_vs_remediated_target_accept_0p90,
    primary_execution_unit = Symbol(SCALAR_EXECUTION_UNIT),
    remediation_id = Symbol(SCALAR_REMEDIATION_ID),
    thresholds = (;
        require_primary_review_present = true,
        require_remediation_review_present = true,
        require_primary_scalar_row_recorded = true,
        require_remediation_scalar_row_recorded = true,
        require_primary_failure_or_pending_recorded = true,
        require_remediation_success_or_pending_recorded = true,
        require_primary_result_preserved = true,
        require_batch_sampler_policy_recorded = true,
        require_all_public_claims_blocked = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Compare the primary scalar GMFRM pilot fit against its local sampler
    remediation before any publication-grade batch expansion.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_scalar_remediation_comparison.jl [--output PATH]

    Options:
      --output PATH              Review fixture path.
      --primary-review PATH      Pilot results review path.
      --remediation-review PATH  Sampler remediation review path.
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    primary_review = DEFAULT_PRIMARY_REVIEW
    remediation_review = DEFAULT_REMEDIATION_REVIEW
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
        elseif arg == "--remediation-review"
            index < length(args) ||
                error("--remediation-review requires a path")
            remediation_review = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; output, primary_review, remediation_review)
end

project_version() = String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)

as_string(value) = String(value)
as_float(value) = Float64(value)

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

function load_json(path::AbstractString)
    return JSON3.read(read(path, String))
end

function input_record(path::AbstractString, artifact_name::Symbol,
        expected_schema::AbstractString)
    exists = isfile(path)
    if !exists
        return (;
            artifact = artifact_name,
            path = rel(path),
            exists = false,
            sha256 = missing,
            schema = missing,
            expected_schema,
            schema_matches = false,
            summary_passed = false,
        )
    end
    artifact = load_json(path)
    schema = as_string(artifact[:schema])
    return (;
        artifact = artifact_name,
        path = rel(path),
        exists,
        sha256 = file_sha256(path),
        schema,
        expected_schema,
        schema_matches = schema == expected_schema,
        summary_passed = json_bool(artifact[:summary], :passed),
    )
end

function find_row(rows, key::Symbol, value::AbstractString)
    for row in rows
        haskey(row, key) || continue
        as_string(row[key]) == value && return row
    end
    return nothing
end

function primary_scalar_row(primary_artifact)
    primary_artifact === nothing && return nothing
    haskey(primary_artifact, :job_result_review_rows) || return nothing
    return find_row(primary_artifact[:job_result_review_rows],
        :execution_unit_id, SCALAR_EXECUTION_UNIT)
end

function primary_failure_row(primary_artifact)
    primary_artifact === nothing && return nothing
    haskey(primary_artifact, :diagnostic_failure_rows) || return nothing
    for row in primary_artifact[:diagnostic_failure_rows]
        as_string(row[:execution_unit_id]) == SCALAR_EXECUTION_UNIT ||
            continue
        as_string(row[:diagnostic]) == "divergence_count_max" && return row
    end
    return nothing
end

function remediation_scalar_row(remediation_artifact)
    remediation_artifact === nothing && return nothing
    haskey(remediation_artifact, :remediation_review_rows) || return nothing
    return find_row(remediation_artifact[:remediation_review_rows],
        :remediation_id, SCALAR_REMEDIATION_ID)
end

function diagnostic_value_from_failure(row)
    row === nothing && return missing
    return json_float_or_missing(row, :value)
end

function primary_summary_row(primary_row, failure_row)
    observed = primary_row !== nothing && json_bool(primary_row,
        :execution_observed)
    diagnostic_gate_passed =
        primary_row === nothing ? false :
        json_bool(primary_row, :diagnostic_gate_passed)
    heldout_elpd =
        primary_row === nothing ? missing :
        json_float_or_missing(primary_row, :heldout_elpd)
    heldout_mae =
        primary_row === nothing ? missing :
        json_float_or_missing(primary_row, :heldout_expected_score_mae)
    heldout_rmse =
        primary_row === nothing ? missing :
        json_float_or_missing(primary_row, :heldout_expected_score_rmse)
    n_divergences = diagnostic_value_from_failure(failure_row)
    return (;
        row_kind = :primary_scalar,
        execution_unit_id = Symbol(SCALAR_EXECUTION_UNIT),
        model = :scalar_gmfrm_baseline,
        target_acceptance = 0.8,
        execution_observed = observed,
        diagnostic_gate_passed,
        divergence_failure_recorded = failure_row !== nothing,
        n_divergences,
        heldout_elpd,
        heldout_expected_score_mae = heldout_mae,
        heldout_expected_score_rmse = heldout_rmse,
        primary_result_replaced = false,
        descriptive_only = true,
        public_claim_allowed = false,
    )
end

function remediation_summary_row(remediation_row)
    observed = remediation_row !== nothing &&
        json_bool(remediation_row, :remediation_observed)
    diagnostic_gate_passed =
        remediation_row === nothing ? false :
        json_bool(remediation_row, :diagnostic_gate_passed)
    return (;
        row_kind = :remediated_scalar,
        remediation_id = Symbol(SCALAR_REMEDIATION_ID),
        source_execution_unit_id = Symbol(SCALAR_EXECUTION_UNIT),
        model = :scalar_gmfrm_baseline,
        target_acceptance = 0.9,
        remediation_observed = observed,
        diagnostic_gate_passed,
        n_divergences = remediation_row === nothing ? missing :
            json_float_or_missing(remediation_row, :n_divergences),
        max_rhat = remediation_row === nothing ? missing :
            json_float_or_missing(remediation_row, :max_rhat),
        min_ess = remediation_row === nothing ? missing :
            json_float_or_missing(remediation_row, :min_ess),
        e_bfmi = remediation_row === nothing ? missing :
            json_float_or_missing(remediation_row, :e_bfmi),
        heldout_elpd = remediation_row === nothing ? missing :
            json_float_or_missing(remediation_row, :heldout_elpd),
        heldout_expected_score_mae = remediation_row === nothing ? missing :
            json_float_or_missing(remediation_row,
                :heldout_expected_score_mae),
        heldout_expected_score_rmse = remediation_row === nothing ? missing :
            json_float_or_missing(remediation_row,
                :heldout_expected_score_rmse),
        primary_result_replaced = false,
        descriptive_only = true,
        public_claim_allowed = false,
    )
end

function comparison_row(primary, remediation)
    primary_elpd = primary.heldout_elpd
    remediation_elpd = remediation.heldout_elpd
    primary_mae = primary.heldout_expected_score_mae
    remediation_mae = remediation.heldout_expected_score_mae
    primary_rmse = primary.heldout_expected_score_rmse
    remediation_rmse = remediation.heldout_expected_score_rmse
    values_observed =
        !ismissing(primary_elpd) && !ismissing(remediation_elpd)
    return (;
        comparison = :primary_scalar_vs_target_acceptance_remediation,
        primary_target_acceptance = primary.target_acceptance,
        remediation_target_acceptance = remediation.target_acceptance,
        primary_diagnostic_gate_passed = primary.diagnostic_gate_passed,
        remediation_diagnostic_gate_passed =
            remediation.diagnostic_gate_passed,
        primary_n_divergences = primary.n_divergences,
        remediation_n_divergences = remediation.n_divergences,
        heldout_comparison_observed = values_observed,
        delta_heldout_elpd_remediation_minus_primary =
            values_observed ?
            as_float(remediation_elpd) - as_float(primary_elpd) :
            missing,
        delta_expected_score_mae_remediation_minus_primary =
            !ismissing(primary_mae) && !ismissing(remediation_mae) ?
            as_float(remediation_mae) - as_float(primary_mae) :
            missing,
        delta_expected_score_rmse_remediation_minus_primary =
            !ismissing(primary_rmse) && !ismissing(remediation_rmse) ?
            as_float(remediation_rmse) - as_float(primary_rmse) :
            missing,
        remediation_resolves_primary_divergence =
            primary.divergence_failure_recorded &&
            remediation.diagnostic_gate_passed &&
            !ismissing(remediation.n_divergences) &&
            as_float(remediation.n_divergences) == 0.0,
        remediation_improves_heldout_elpd =
            values_observed &&
            as_float(remediation_elpd) > as_float(primary_elpd),
        public_claim_allowed = false,
        interpretation = values_observed ?
            :remediation_diagnostic_context_descriptive_only :
            :comparison_pending_local_artifacts,
    )
end

function batch_policy_row(comparison)
    resolved = comparison.remediation_resolves_primary_divergence
    return (;
        policy = :publication_grade_batch_sampler_setting,
        affected_model = :scalar_gmfrm_baseline,
        affected_execution_unit = Symbol(SCALAR_EXECUTION_UNIT),
        primary_target_acceptance = 0.8,
        selected_batch_target_acceptance = resolved ? 0.9 : missing,
        fallback_batch_target_acceptance = 0.9,
        selection_basis = resolved ?
            :local_remediation_removed_scalar_divergences :
            :await_local_remediation_before_batch_expansion,
        primary_pilot_result_replaced = false,
        batch_expansion_allowed_for_scalar =
            resolved,
        batch_expansion_allowed_for_public_claim =
            false,
        requires_independent_replication = true,
        public_claim_allowed = false,
    )
end

function blocker_rows(values)
    return [
        (blocker = :scalar_remediation_comparison_not_observed,
            blocks = :batch_sampler_policy_finalization,
            resolved = values.comparison_observed),
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
    primary_record = input_record(options.primary_review,
        :mgmfrm_publication_grade_refit_pilot_results_review, PRIMARY_SCHEMA)
    remediation_record = input_record(options.remediation_review,
        :mgmfrm_publication_grade_refit_sampler_remediation_review,
        REMEDIATION_SCHEMA)
    primary_artifact =
        primary_record.exists ? load_json(options.primary_review) : nothing
    remediation_artifact =
        remediation_record.exists ? load_json(options.remediation_review) :
        nothing
    primary_row = primary_summary_row(
        primary_scalar_row(primary_artifact),
        primary_failure_row(primary_artifact),
    )
    remediation_row =
        remediation_summary_row(remediation_scalar_row(remediation_artifact))
    comparison = comparison_row(primary_row, remediation_row)
    policy = batch_policy_row(comparison)
    comparison_observed = comparison.heldout_comparison_observed &&
        primary_row.execution_observed &&
        remediation_row.remediation_observed
    remediation_success_observed =
        remediation_row.remediation_observed &&
        remediation_row.diagnostic_gate_passed &&
        !ismissing(remediation_row.n_divergences) &&
        as_float(remediation_row.n_divergences) == 0.0
    no_public_claims =
        !primary_row.public_claim_allowed &&
        !remediation_row.public_claim_allowed &&
        !comparison.public_claim_allowed &&
        !policy.public_claim_allowed
    blockers = blocker_rows((; comparison_observed))
    passed = primary_record.exists &&
        primary_record.schema_matches &&
        primary_record.summary_passed &&
        remediation_record.exists &&
        remediation_record.schema_matches &&
        remediation_record.summary_passed &&
        no_public_claims &&
        !policy.primary_pilot_result_replaced
    next_gate = comparison_observed && remediation_success_observed ?
        :expand_publication_grade_batch_with_scalar_target_acceptance_0p90_local_only :
        :execute_or_attach_scalar_remediation_comparison_before_batch_expansion
    recommendation = comparison_observed && remediation_success_observed ?
        :use_target_acceptance_0p90_for_scalar_batch_expansion_keep_claims_blocked :
        :complete_scalar_remediation_comparison_keep_batch_expansion_blocked

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_scalar_remediation_comparison.v1",
        family = :mgmfrm,
        scope = :publication_grade_refit_scalar_remediation_comparison,
        status =
            :publication_grade_refit_scalar_remediation_comparison_recorded,
        decision =
            :record_scalar_remediation_comparison_before_batch_expansion,
        public_fit = true,
        experimental_public = true,
        fit_ready = Bool(primary_record.summary_passed),
        local_only = true,
        pilot_only = true,
        remediation_only = true,
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
        input_artifacts = [primary_record, remediation_record],
        scalar_primary_row = primary_row,
        scalar_remediation_row = remediation_row,
        scalar_comparison_row = comparison,
        batch_sampler_policy_row = policy,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :record_remediated_scalar_against_primary,
            primary_scalar_failure_reviewed =
                primary_row.divergence_failure_recorded,
            remediation_success_observed,
            primary_result_replaced = false,
            scalar_batch_target_acceptance =
                policy.selected_batch_target_acceptance,
            scalar_batch_expansion_allowed_local_only =
                policy.batch_expansion_allowed_for_scalar,
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
            primary_review_present = primary_record.exists,
            primary_review_schema_matches = primary_record.schema_matches,
            primary_review_passed = primary_record.summary_passed,
            remediation_review_present = remediation_record.exists,
            remediation_review_schema_matches =
                remediation_record.schema_matches,
            remediation_review_passed = remediation_record.summary_passed,
            primary_scalar_row_recorded = primary_row.execution_observed,
            primary_scalar_divergence_failure_recorded =
                primary_row.divergence_failure_recorded,
            remediation_scalar_row_recorded =
                remediation_row.remediation_observed,
            remediation_success_observed,
            comparison_observed,
            heldout_comparison_observed =
                comparison.heldout_comparison_observed,
            remediation_resolves_primary_divergence =
                comparison.remediation_resolves_primary_divergence,
            remediation_improves_heldout_elpd =
                comparison.remediation_improves_heldout_elpd,
            primary_result_preserved = true,
            scalar_batch_target_acceptance_policy_recorded = true,
            scalar_batch_target_acceptance =
                policy.selected_batch_target_acceptance,
            scalar_batch_expansion_allowed_local_only =
                policy.batch_expansion_allowed_for_scalar,
            scalar_batch_expansion_allowed_for_public_claim = false,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            n_input_artifacts = 2,
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
        " comparison_observed=", artifact.summary.comparison_observed,
        " remediation_success=",
        artifact.summary.remediation_success_observed,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
