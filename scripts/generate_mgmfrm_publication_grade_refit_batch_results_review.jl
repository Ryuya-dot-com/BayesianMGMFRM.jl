#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_batch_results_review.json")
const DEFAULT_PLAN =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_batch_expansion_plan.json")
const DEFAULT_THRESHOLD_SENSITIVITY =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_fit_metric_threshold_sensitivity.json")
const FIXTURE_ROOT = joinpath(ROOT, "test", "fixtures")

include(joinpath(@__DIR__, "local_json.jl"))

const PLAN_SCHEMA =
    "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_expansion_plan.v1"
const THRESHOLD_SENSITIVITY_SCHEMA =
    "bayesianmgmfrm.mgmfrm_fit_metric_threshold_sensitivity.v1"

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
        "mgmfrm_publication_grade_refit_batch_results_review_v1",
    review_kind =
        :local_publication_grade_refit_batch_results_review,
    publication_or_registration_action = false,
    local_only = true,
    source_plan =
        :mgmfrm_publication_grade_refit_batch_expansion_plan,
    expected_execution_units = 125,
    expected_mcmc_execution_units = 100,
    expected_analytic_reference_units = 25,
    expected_artifacts_per_unit = 3,
    thresholds = (;
        require_batch_plan_passed = true,
        require_result_review_rows_recorded = true,
        require_missing_or_valid_job_artifacts = true,
        require_fit_metric_threshold_sensitivity_passed = true,
        require_threshold_profiles_recorded = true,
        require_threshold_profile_job_rows_recorded = true,
        require_threshold_profile_model_summary_rows_recorded = true,
        require_threshold_profile_scenario_model_summary_rows_recorded = true,
        require_model_summary_rows_recorded = true,
        require_scenario_model_summary_rows_recorded = true,
        require_descriptive_only_rankings = true,
        require_no_single_threshold_profile_promoted = true,
        require_all_public_claims_blocked = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM publication-grade refit batch results review.

    This review reads the 125-unit batch plan and any local runner artifacts,
    records missing/partial/complete execution state, and keeps all public
    MGMFRM fit, Q-revision, model-weight, and sparse-superiority claims blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_batch_results_review.jl [--output PATH]

    Options:
      --output PATH       Review fixture path.
      --plan PATH         Batch expansion plan fixture path.
      --threshold-sensitivity PATH
                          Fit-metric threshold sensitivity fixture path.
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
    plan = DEFAULT_PLAN
    threshold_sensitivity = DEFAULT_THRESHOLD_SENSITIVITY
    result_root = nothing
    ignore_local_artifacts = nothing
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
        elseif arg == "--threshold-sensitivity"
            index < length(args) ||
                error("--threshold-sensitivity requires a path")
            threshold_sensitivity = abspath(args[index + 1])
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
    return (; output, plan, threshold_sensitivity, result_root,
        ignore_local_artifacts)
end

project_version() = String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
root_path(path::AbstractString) =
    isabspath(path) ? normpath(path) : normpath(joinpath(ROOT, path))

as_string(value) = String(value)
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_float(value) = Float64(value)
as_symbol(value) = Symbol(String(value))

function path_inside(path::AbstractString, root::AbstractString)
    relative = relpath(normpath(path), normpath(root))
    return relative == "." || !(startswith(relative, "..") ||
                                isabspath(relative))
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

function load_json(path::AbstractString)
    return JSON3.read(read(path, String))
end

function input_plan_record(path::AbstractString)
    exists = isfile(path)
    if !exists
        return (;
            artifact =
                :mgmfrm_publication_grade_refit_batch_expansion_plan,
            path = rel(path),
            exists = false,
            sha256 = missing,
            schema = missing,
            expected_schema = PLAN_SCHEMA,
            schema_matches = false,
            summary_passed = false,
        )
    end
    artifact = load_json(path)
    schema = as_string(artifact[:schema])
    return (;
        artifact = :mgmfrm_publication_grade_refit_batch_expansion_plan,
        path = rel(path),
        exists,
        sha256 = file_sha256(path),
        schema,
        expected_schema = PLAN_SCHEMA,
        schema_matches = schema == PLAN_SCHEMA,
        summary_passed = json_bool(artifact[:summary], :passed),
    )
end

function input_threshold_sensitivity_record(path::AbstractString)
    exists = isfile(path)
    if !exists
        return (;
            artifact = :mgmfrm_fit_metric_threshold_sensitivity,
            path = rel(path),
            exists = false,
            sha256 = missing,
            schema = missing,
            expected_schema = THRESHOLD_SENSITIVITY_SCHEMA,
            schema_matches = false,
            summary_passed = false,
            summary = (;
                passed = false,
                n_threshold_profiles = 0,
                threshold_profiles_change_at_least_one_flag = false,
                no_single_threshold_profile_promoted = false,
                no_public_fit_metric_claim = false,
            ),
        )
    end
    artifact = load_json(path)
    schema = as_string(artifact[:schema])
    summary = artifact[:summary]
    return (;
        artifact = :mgmfrm_fit_metric_threshold_sensitivity,
        path = rel(path),
        exists,
        sha256 = file_sha256(path),
        schema,
        expected_schema = THRESHOLD_SENSITIVITY_SCHEMA,
        schema_matches = schema == THRESHOLD_SENSITIVITY_SCHEMA,
        summary_passed = json_bool(summary, :passed),
        summary = (;
            passed = json_bool(summary, :passed),
            n_threshold_profiles =
                json_int(summary, :n_threshold_profiles),
            threshold_profiles_change_at_least_one_flag =
                json_bool(summary,
                    :threshold_profiles_change_at_least_one_flag),
            no_single_threshold_profile_promoted =
                json_bool(summary, :no_single_threshold_profile_promoted),
            no_public_fit_metric_claim =
                json_bool(summary, :no_public_fit_metric_claim),
        ),
    )
end

function threshold_profile_rows(path::AbstractString,
        record)
    record.exists || return NamedTuple[]
    record.schema_matches || return NamedTuple[]
    artifact = load_json(path)
    rows = NamedTuple[]
    for profile in artifact[:threshold_profiles]
        calibration_abs_threshold =
            json_float_or_missing(profile, :calibration_abs_threshold)
        heldout_expected_score_mae_threshold =
            ismissing(calibration_abs_threshold) ? missing :
            2.0 * calibration_abs_threshold
        push!(rows, (;
            profile = as_symbol(profile[:profile]),
            rationale = as_symbol(profile[:rationale]),
            rhat_threshold =
                json_float_or_missing(profile, :rhat_threshold),
            ess_threshold =
                json_float_or_missing(profile, :ess_threshold),
            waic_p_threshold =
                json_float_or_missing(profile, :waic_p_threshold),
            pareto_k_threshold =
                json_float_or_missing(profile, :pareto_k_threshold),
            calibration_abs_threshold,
            ppc_abs_threshold =
                json_float_or_missing(profile, :ppc_abs_threshold),
            heldout_expected_score_mae_threshold,
            heldout_threshold_binding =
                :calibration_abs_threshold_times_score_range_proxy,
            score_range_proxy = 2.0,
            mean_square_rule = as_symbol(profile[:mean_square_rule]),
            infit_lower = json_float_or_missing(profile, :infit_lower),
            infit_upper = json_float_or_missing(profile, :infit_upper),
            outfit_lower = json_float_or_missing(profile, :outfit_lower),
            outfit_upper = json_float_or_missing(profile, :outfit_upper),
            public_fit_metric_claim_allowed = false,
        ))
    end
    return rows
end

function artifact_paths(job, result_root)
    if result_root === nothing
        return (;
            result = root_path(as_string(job[:result_artifact_path])),
            diagnostics =
                root_path(as_string(job[:diagnostic_artifact_path])),
            heldout =
                root_path(as_string(job[:heldout_score_artifact_path])),
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
    execution_observed = complete && result.executed && !result.dry_run
    dry_run_observed = complete && result.dry_run
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
        execution_job_id = as_symbol(json_get(job, :execution_job_id,
            job[:execution_unit_id])),
        scenario = as_symbol(job[:scenario]),
        model = as_symbol(job[:model]),
        fold = as_int(job[:fold]),
        mcmc_refit_required = mcmc_required,
        analytic_reference_scored = as_bool(job[:analytic_reference_scored]),
        result_artifact = result,
        diagnostic_artifact = diagnostics,
        heldout_artifact = heldout,
        artifacts_complete = complete,
        execution_observed,
        dry_run_observed,
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
            scenario = as_symbol(job[:scenario]),
            model = as_symbol(job[:model]),
            fold = as_int(job[:fold]),
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
            public_claim_allowed = false,
        ))
    end
    return failures
end

function observed_diagnostic_values(job, result_root;
        ignore_local_artifacts::Bool)
    values = Dict{Symbol, Any}()
    ignore_local_artifacts && return values
    paths = artifact_paths(job, result_root)
    isfile(paths.diagnostics) || return values
    artifact = load_json(paths.diagnostics)
    as_string(artifact[:schema]) == EXPECTED_SCHEMAS.diagnostics ||
        return values
    haskey(artifact, :diagnostic_rows) || return values
    for diagnostic in artifact[:diagnostic_rows]
        json_bool(diagnostic, :observed) || continue
        values[as_symbol(diagnostic[:diagnostic])] =
            json_get(diagnostic, :value, missing)
    end
    return values
end

function lookup_float(values, key::Symbol)
    haskey(values, key) || return missing
    value = values[key]
    ismissing(value) && return missing
    value === nothing && return missing
    value isa Bool && return missing
    return Float64(value)
end

function lookup_bool(values, key::Symbol)
    haskey(values, key) || return missing
    value = values[key]
    ismissing(value) && return missing
    value === nothing && return missing
    return Bool(value)
end

function leq_pass(value, threshold)
    ismissing(value) && return false
    ismissing(threshold) && return false
    return isfinite(Float64(value)) && Float64(value) <= Float64(threshold)
end

function geq_pass(value, threshold)
    ismissing(value) && return false
    ismissing(threshold) && return false
    return isfinite(Float64(value)) && Float64(value) >= Float64(threshold)
end

function zero_pass(value)
    ismissing(value) && return false
    return isfinite(Float64(value)) && Float64(value) == 0.0
end

function true_pass(value)
    ismissing(value) && return false
    return Bool(value)
end

function count_missing(values)
    return count(ismissing, values)
end

function threshold_profile_job_row(job, review_row, profile, result_root;
        ignore_local_artifacts::Bool)
    diagnostics = observed_diagnostic_values(job, result_root;
        ignore_local_artifacts)
    mcmc_required = Bool(review_row.mcmc_refit_required)
    rank_normalized_rhat_max =
        lookup_float(diagnostics, :rank_normalized_rhat_max)
    ess_bulk_min = lookup_float(diagnostics, :ess_bulk_min)
    ess_tail_min = lookup_float(diagnostics, :ess_tail_min)
    divergence_count = lookup_float(diagnostics, :divergence_count_max)
    max_treedepth_count =
        lookup_float(diagnostics, :max_treedepth_count_max)
    ebfmi_min = lookup_float(diagnostics, :ebfmi_min)
    pointwise_loglikelihood_finite =
        lookup_bool(diagnostics, :pointwise_loglikelihood_finite)
    posterior_predictive_check_recorded =
        lookup_bool(diagnostics, :posterior_predictive_check_recorded)
    expected_score_calibration_recorded =
        lookup_bool(diagnostics, :expected_score_calibration_recorded)
    heldout_expected_score_mae = review_row.heldout_expected_score_mae

    mcmc_inputs = mcmc_required ? [
        rank_normalized_rhat_max,
        ess_bulk_min,
        ess_tail_min,
        divergence_count,
        max_treedepth_count,
        ebfmi_min,
    ] : Any[]
    predictive_inputs = Any[
        pointwise_loglikelihood_finite,
        expected_score_calibration_recorded,
        heldout_expected_score_mae,
    ]
    mcmc_required &&
        push!(predictive_inputs, posterior_predictive_check_recorded)
    mcmc_thresholds_evaluable =
        !mcmc_required || count_missing(mcmc_inputs) == 0
    predictive_thresholds_evaluable =
        count_missing(predictive_inputs) == 0
    threshold_profile_evaluable =
        Bool(review_row.execution_observed) &&
        Bool(review_row.diagnostics_observed) &&
        Bool(review_row.heldout_predictive_score_computed) &&
        mcmc_thresholds_evaluable &&
        predictive_thresholds_evaluable

    rhat_passed =
        !mcmc_required ||
        leq_pass(rank_normalized_rhat_max, profile.rhat_threshold)
    ess_bulk_passed =
        !mcmc_required ||
        geq_pass(ess_bulk_min, profile.ess_threshold)
    ess_tail_passed =
        !mcmc_required ||
        geq_pass(ess_tail_min, profile.ess_threshold)
    divergence_passed =
        !mcmc_required || zero_pass(divergence_count)
    max_treedepth_passed =
        !mcmc_required || zero_pass(max_treedepth_count)
    ebfmi_passed =
        !mcmc_required || geq_pass(ebfmi_min, 0.3)
    pointwise_loglikelihood_passed =
        true_pass(pointwise_loglikelihood_finite)
    ppc_recording_passed =
        !mcmc_required || true_pass(posterior_predictive_check_recorded)
    expected_score_calibration_recorded_passed =
        true_pass(expected_score_calibration_recorded)
    heldout_expected_score_mae_proxy_passed =
        leq_pass(heldout_expected_score_mae,
            profile.heldout_expected_score_mae_threshold)
    checks = [
        rhat_passed,
        ess_bulk_passed,
        ess_tail_passed,
        divergence_passed,
        max_treedepth_passed,
        ebfmi_passed,
        pointwise_loglikelihood_passed,
        ppc_recording_passed,
        expected_score_calibration_recorded_passed,
        heldout_expected_score_mae_proxy_passed,
    ]
    n_threshold_flags =
        threshold_profile_evaluable ? count(!, checks) : 0
    n_missing_profile_inputs =
        count_missing(vcat(mcmc_inputs, predictive_inputs))
    threshold_profile_passed =
        threshold_profile_evaluable && n_threshold_flags == 0
    return (;
        execution_unit_id = review_row.execution_unit_id,
        scenario = review_row.scenario,
        model = review_row.model,
        fold = review_row.fold,
        profile = profile.profile,
        mcmc_refit_required = mcmc_required,
        execution_observed = review_row.execution_observed,
        diagnostics_observed = review_row.diagnostics_observed,
        heldout_predictive_score_computed =
            review_row.heldout_predictive_score_computed,
        rhat_threshold = profile.rhat_threshold,
        ess_threshold = profile.ess_threshold,
        calibration_abs_threshold = profile.calibration_abs_threshold,
        ppc_abs_threshold = profile.ppc_abs_threshold,
        heldout_expected_score_mae_threshold =
            profile.heldout_expected_score_mae_threshold,
        heldout_threshold_binding = profile.heldout_threshold_binding,
        rank_normalized_rhat_max,
        ess_bulk_min,
        ess_tail_min,
        divergence_count,
        max_treedepth_count,
        ebfmi_min,
        pointwise_loglikelihood_finite,
        posterior_predictive_check_recorded,
        expected_score_calibration_recorded,
        heldout_expected_score_mae,
        mcmc_thresholds_evaluable,
        predictive_thresholds_evaluable,
        threshold_profile_evaluable,
        rhat_passed,
        ess_bulk_passed,
        ess_tail_passed,
        divergence_passed,
        max_treedepth_passed,
        ebfmi_passed,
        pointwise_loglikelihood_passed,
        ppc_recording_passed,
        expected_score_calibration_recorded_passed,
        heldout_expected_score_mae_proxy_passed,
        n_missing_profile_inputs,
        n_threshold_flags,
        threshold_profile_passed,
        descriptive_only = true,
        threshold_profile_promoted = false,
        public_fit_metric_claim_allowed = false,
        public_model_weight_claim_allowed = false,
    )
end

function threshold_profile_job_rows(jobs, rows, profiles, result_root;
        ignore_local_artifacts::Bool)
    output = NamedTuple[]
    for (job, row) in zip(jobs, rows), profile in profiles
        push!(output, threshold_profile_job_row(job, row, profile,
            result_root; ignore_local_artifacts))
    end
    return output
end

function threshold_profile_summary_rows(rows, group_keys)
    isempty(rows) && return NamedTuple[]
    groups = Dict{Tuple, Vector{eltype(rows)}}()
    for row in rows
        key = Tuple(getproperty(row, key) for key in group_keys)
        push!(get!(groups, key, eltype(rows)[]), row)
    end
    output = NamedTuple[]
    for key in sort(collect(Base.keys(groups)); by = string)
        group = groups[key]
        evaluable = count(row -> row.threshold_profile_evaluable, group)
        passed = count(row -> row.threshold_profile_passed, group)
        push!(output, merge(NamedTuple{Tuple(group_keys)}(key), (;
            n_threshold_profile_rows = length(group),
            n_evaluable_rows = evaluable,
            n_missing_input_rows =
                count(row -> row.n_missing_profile_inputs > 0, group),
            n_passed_rows = passed,
            n_flagged_rows =
                count(row -> row.threshold_profile_evaluable &&
                    row.n_threshold_flags > 0, group),
            pass_rate_among_evaluable =
                evaluable == 0 ? missing : passed / evaluable,
            any_threshold_profile_passed = passed > 0,
            all_evaluable_rows_passed =
                evaluable > 0 && passed == evaluable,
            descriptive_only = true,
            threshold_profile_promoted = false,
            public_fit_metric_claim_allowed = false,
        )))
    end
    return output
end

function threshold_profiles_change_batch_decision(rows)
    isempty(rows) && return false
    groups = Dict{Symbol, Vector{Bool}}()
    for row in rows
        row.threshold_profile_evaluable || continue
        push!(get!(groups, row.execution_unit_id, Bool[]),
            row.threshold_profile_passed)
    end
    return any(values(groups)) do decisions
        length(unique(decisions)) > 1
    end
end

function heldout_model_rank_rows(rows)
    scored_rows = [
        row for row in rows
        if row.heldout_predictive_score_computed &&
            !ismissing(row.heldout_elpd)
    ]
    groups = Dict{Tuple{Symbol, Int}, Vector{eltype(scored_rows)}}()
    for row in scored_rows
        key = (row.scenario, row.fold)
        push!(get!(groups, key, eltype(scored_rows)[]), row)
    end
    output = NamedTuple[]
    for key in sort(collect(keys(groups)); by = string)
        sorted_rows =
            sort(groups[key]; by = row -> Float64(row.heldout_elpd),
                rev = true)
        best = first(sorted_rows)
        for (rank, row) in enumerate(sorted_rows)
            push!(output, (;
                scenario = row.scenario,
                fold = row.fold,
                rank,
                execution_unit_id = row.execution_unit_id,
                model = row.model,
                mcmc_refit_required = row.mcmc_refit_required,
                analytic_reference_scored = row.analytic_reference_scored,
                diagnostic_gate_passed = row.diagnostic_gate_passed,
                heldout_elpd = row.heldout_elpd,
                delta_elpd_from_best =
                    Float64(row.heldout_elpd) - Float64(best.heldout_elpd),
                heldout_mean_log_predictive_density =
                    row.heldout_mean_log_predictive_density,
                heldout_expected_score_mae = row.heldout_expected_score_mae,
                heldout_expected_score_rmse = row.heldout_expected_score_rmse,
                descriptive_only = true,
                public_model_weight_claim_allowed = false,
                public_fit_metric_claim_allowed = false,
            ))
        end
    end
    return output
end

function summarize_rows(rows, group_keys)
    groups = Dict{Tuple, Vector{eltype(rows)}}()
    for row in rows
        key = Tuple(getproperty(row, key) for key in group_keys)
        push!(get!(groups, key, eltype(rows)[]), row)
    end
    output = NamedTuple[]
    for key in sort(collect(Base.keys(groups)); by = string)
        group = groups[key]
        push!(output, merge(NamedTuple{Tuple(group_keys)}(key), (;
            n_execution_units = length(group),
            n_mcmc_execution_units =
                count(row -> row.mcmc_refit_required, group),
            n_analytic_reference_units =
                count(row -> row.analytic_reference_scored, group),
            n_complete_artifact_units =
                count(row -> row.artifacts_complete, group),
            n_executed_units =
                count(row -> row.execution_observed, group),
            n_dry_run_units =
                count(row -> row.dry_run_observed, group),
            n_diagnostic_gate_passed_units =
                count(row -> row.diagnostic_gate_passed, group),
            n_heldout_scored_units =
                count(row -> row.heldout_predictive_score_computed, group),
            public_claim_allowed = false,
        )))
    end
    return output
end

function blocker_rows(values)
    return [
        (blocker = :full_125_unit_publication_grade_batch_not_executed,
            blocks = :public_kfold_model_comparison_claims,
            resolved = values.all_125_units_executed),
        (blocker = :publication_grade_batch_diagnostics_not_observed,
            blocks = :public_fit_metric_claims,
            resolved = values.all_executed_diagnostics_observed &&
                values.all_125_units_executed),
        (blocker = :mcmc_candidate_diagnostic_gates_not_all_passed,
            blocks = :model_weight_and_sparse_superiority_claims,
            resolved = values.all_mcmc_diagnostic_gates_passed &&
                values.all_125_units_executed),
        (blocker = :external_construct_dataset_missing,
            blocks = :public_construct_or_q_revision_claims,
            resolved = false),
        (blocker = :independent_public_scope_review_missing,
            blocks = :all_public_mgmfrm_claims,
            resolved = false),
    ]
end

function build_artifact(options)
    plan_record = input_plan_record(options.plan)
    threshold_record =
        input_threshold_sensitivity_record(options.threshold_sensitivity)
    plan = plan_record.exists ? load_json(options.plan) : nothing
    jobs = plan === nothing ? Any[] : [row for row in plan[:batch_execution_job_rows]]
    threshold_profiles =
        threshold_profile_rows(options.threshold_sensitivity, threshold_record)
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
    ranks = heldout_model_rank_rows(rows)
    threshold_profile_jobs =
        threshold_profile_job_rows(jobs, rows, threshold_profiles,
            options.result_root; ignore_local_artifacts)
    threshold_profile_model_summaries =
        threshold_profile_summary_rows(threshold_profile_jobs,
            (:model, :profile))
    threshold_profile_scenario_model_summaries =
        threshold_profile_summary_rows(threshold_profile_jobs,
            (:scenario, :model, :profile))
    model_summaries = summarize_rows(rows, (:model,))
    scenario_model_summaries =
        summarize_rows(rows, (:scenario, :model))

    n_expected = length(jobs)
    n_mcmc = count(row -> row.mcmc_refit_required, rows)
    n_reference = count(row -> row.analytic_reference_scored, rows)
    n_complete = count(row -> row.artifacts_complete, rows)
    n_executed = count(row -> row.execution_observed, rows)
    n_dry_run = count(row -> row.dry_run_observed, rows)
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
    all_expected_job_artifacts_present =
        n_expected > 0 && n_present_artifacts == 3 * n_expected
    all_expected_job_artifacts_valid =
        all_expected_job_artifacts_present &&
        n_valid_artifacts == 3 * n_expected
    all_125_units_materialized =
        n_expected == PROTOCOL.expected_execution_units &&
        n_mcmc == PROTOCOL.expected_mcmc_execution_units &&
        n_reference == PROTOCOL.expected_analytic_reference_units
    all_125_units_executed =
        all_125_units_materialized && n_executed == n_expected
    all_executed_diagnostics_observed =
        n_executed > 0 &&
        all(row -> !row.execution_observed || row.diagnostics_observed, rows)
    all_mcmc_diagnostic_gates_passed =
        n_mcmc > 0 &&
        all(row -> !row.mcmc_refit_required ||
            row.diagnostic_gate_passed, rows)
    missing_or_valid_job_artifacts =
        all(rows) do row
            artifacts = (row.result_artifact, row.diagnostic_artifact,
                row.heldout_artifact)
            all(artifact -> !artifact.exists || artifact.schema_matches,
                artifacts)
        end
    no_public_fit_metric_claim = true
    no_public_q_revision_claim = true
    no_public_model_weight_claim = true
    no_sparse_superiority_claim = true
    no_single_threshold_profile_promoted =
        all(row -> !row.threshold_profile_promoted, threshold_profile_jobs)
    no_public_claim_allowed = all(row -> !row.public_claim_allowed, rows)
    threshold_profiles_change_observed_batch_flag =
        threshold_profiles_change_batch_decision(threshold_profile_jobs)
    values = (;
        all_125_units_executed,
        all_executed_diagnostics_observed,
        all_mcmc_diagnostic_gates_passed,
    )
    blockers = blocker_rows(values)
    passed = plan_record.exists &&
        plan_record.schema_matches &&
        plan_record.summary_passed &&
        threshold_record.exists &&
        threshold_record.schema_matches &&
        threshold_record.summary_passed &&
        all_125_units_materialized &&
        missing_or_valid_job_artifacts &&
        length(threshold_profiles) == 4 &&
        length(threshold_profile_jobs) == 4 * n_expected &&
        length(threshold_profile_model_summaries) == 20 &&
        length(threshold_profile_scenario_model_summaries) == 100 &&
        length(model_summaries) == 5 &&
        length(scenario_model_summaries) == 25 &&
        no_public_claim_allowed &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim &&
        no_single_threshold_profile_promoted
    next_gate = all_125_units_executed ?
        (isempty(diagnostic_failures) ?
            :compare_publication_grade_batch_against_threshold_and_model_weight_policy :
            :inspect_publication_grade_batch_diagnostic_failures) :
        (n_executed > 0 || n_dry_run > 0 ?
            :run_remaining_publication_grade_refit_batch_jobs :
            :execute_publication_grade_refit_batch_locally)
    recommendation = all_125_units_executed ?
        (isempty(diagnostic_failures) ?
            :review_batch_fit_thresholds_and_model_weight_sensitivity_keep_claims_blocked :
            :review_batch_diagnostic_failures_keep_claims_blocked) :
        :execute_missing_publication_grade_batch_jobs_keep_claims_blocked

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_results_review.v1",
        family = :mgmfrm,
        scope = :publication_grade_refit_batch_results_review,
        status = :publication_grade_refit_batch_results_review_recorded,
        decision =
            :record_publication_grade_refit_batch_results_state,
        public_fit = true,
        experimental_public = true,
        fit_ready = Bool(plan_record.summary_passed),
        local_only = true,
        batch_only = true,
        local_artifacts_ignored_for_fixture = ignore_local_artifacts,
        publication_or_registration_action = false,
        publication_grade_batch_plan_recorded = Bool(plan_record.summary_passed),
        publication_grade_batch_results_review_recorded = true,
        full_125_unit_publication_grade_batch_completed =
            all_125_units_executed,
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
        input_artifacts = [plan_record, threshold_record],
        threshold_profile_rows = threshold_profiles,
        job_result_review_rows = rows,
        model_summary_rows = model_summaries,
        scenario_model_summary_rows = scenario_model_summaries,
        threshold_profile_job_rows = threshold_profile_jobs,
        threshold_profile_model_summary_rows =
            threshold_profile_model_summaries,
        threshold_profile_scenario_model_summary_rows =
            threshold_profile_scenario_model_summaries,
        heldout_model_rank_rows = ranks,
        diagnostic_failure_rows = diagnostic_failures,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :record_publication_grade_batch_results_review,
            batch_plan_recorded = Bool(plan_record.summary_passed),
            all_125_units_executed,
            all_expected_job_artifacts_present =
                all_expected_job_artifacts_present,
            all_expected_job_artifacts_valid,
            diagnostics_observed =
                all_executed_diagnostics_observed &&
                all_125_units_executed,
            all_mcmc_diagnostic_gates_passed,
            threshold_profiles_recorded = length(threshold_profiles) == 4,
            threshold_profiles_inherited_change_at_least_one_flag =
                Bool(threshold_record.summary.
                    threshold_profiles_change_at_least_one_flag),
            threshold_profiles_change_observed_batch_flag,
            threshold_profiles_promoted = false,
            public_fit_metric_claim_allowed = false,
            public_model_weight_claim_allowed = false,
            sparse_superiority_claim_allowed = false,
            required_followup = next_gate,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            batch_only = true,
            local_artifacts_ignored_for_fixture = ignore_local_artifacts,
            batch_plan_present = Bool(plan_record.exists),
            batch_plan_schema_matches = Bool(plan_record.schema_matches),
            batch_plan_passed = Bool(plan_record.summary_passed),
            fit_metric_threshold_sensitivity_present =
                Bool(threshold_record.exists),
            fit_metric_threshold_sensitivity_schema_matches =
                Bool(threshold_record.schema_matches),
            fit_metric_threshold_sensitivity_passed =
                Bool(threshold_record.summary_passed),
            result_review_rows_recorded =
                n_expected == PROTOCOL.expected_execution_units,
            all_125_units_materialized,
            all_125_units_executed,
            missing_or_valid_job_artifacts,
            threshold_profiles_recorded = length(threshold_profiles) == 4,
            threshold_profile_job_rows_recorded =
                length(threshold_profile_jobs) == 4 * n_expected,
            threshold_profile_model_summary_rows_recorded =
                length(threshold_profile_model_summaries) == 20,
            threshold_profile_scenario_model_summary_rows_recorded =
                length(threshold_profile_scenario_model_summaries) == 100,
            threshold_profiles_inherited_change_at_least_one_flag =
                Bool(threshold_record.summary.
                    threshold_profiles_change_at_least_one_flag),
            threshold_profiles_change_observed_batch_flag,
            no_single_threshold_profile_promoted,
            all_expected_job_artifacts_present,
            all_expected_job_artifacts_valid,
            all_executed_diagnostics_observed,
            all_mcmc_diagnostic_gates_passed,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            n_input_artifacts = 2,
            n_threshold_profiles = length(threshold_profiles),
            n_threshold_profile_job_rows = length(threshold_profile_jobs),
            n_threshold_profile_model_summary_rows =
                length(threshold_profile_model_summaries),
            n_threshold_profile_scenario_model_summary_rows =
                length(threshold_profile_scenario_model_summaries),
            n_threshold_profile_evaluable_rows =
                count(row -> row.threshold_profile_evaluable,
                    threshold_profile_jobs),
            n_threshold_profile_passed_rows =
                count(row -> row.threshold_profile_passed,
                    threshold_profile_jobs),
            n_threshold_profile_flagged_rows =
                count(row -> row.threshold_profile_evaluable &&
                    row.n_threshold_flags > 0, threshold_profile_jobs),
            n_batch_execution_job_rows = n_expected,
            n_mcmc_execution_jobs = n_mcmc,
            n_analytic_reference_jobs = n_reference,
            n_expected_job_artifacts = 3 * n_expected,
            n_present_job_artifacts = n_present_artifacts,
            n_valid_job_artifacts = n_valid_artifacts,
            n_complete_artifact_units = n_complete,
            n_executed_units = n_executed,
            n_dry_run_units = n_dry_run,
            n_diagnostics_observed_units = n_diagnostics_observed,
            n_diagnostic_gate_passed_units = n_diagnostic_gate_passed,
            n_heldout_scored_units = n_heldout,
            n_model_summary_rows = length(model_summaries),
            n_scenario_model_summary_rows = length(scenario_model_summaries),
            n_heldout_model_rank_rows = length(ranks),
            n_diagnostic_failure_rows = length(diagnostic_failures),
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
        " executed=", artifact.summary.n_executed_units,
        " dry_run=", artifact.summary.n_dry_run_units,
        " artifacts=", artifact.summary.n_present_job_artifacts,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
