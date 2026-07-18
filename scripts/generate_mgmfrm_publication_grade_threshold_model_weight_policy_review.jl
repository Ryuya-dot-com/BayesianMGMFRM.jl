#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_threshold_model_weight_policy_review.json")
const DEFAULT_BATCH_REVIEW =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_batch_results_review.json")
const DEFAULT_THRESHOLD_SENSITIVITY =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_fit_metric_threshold_sensitivity.json")
const DEFAULT_MODEL_WEIGHT_POLICY =
    joinpath(ROOT, "test", "fixtures",
        "gmfrm_prediction_target_and_model_weight_policy.json")
const DEFAULT_MANUAL_SCOPE_REVIEW =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_manual_public_scope_review_for_fit.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_SPECS = [
    (artifact = :mgmfrm_publication_grade_refit_batch_results_review,
        expected_schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_results_review.v1"),
    (artifact = :mgmfrm_fit_metric_threshold_sensitivity,
        expected_schema =
            "bayesianmgmfrm.mgmfrm_fit_metric_threshold_sensitivity.v1"),
    (artifact = :prediction_target_and_model_weight_policy,
        expected_schema =
            "bayesianmgmfrm.gmfrm_prediction_target_and_model_weight_policy.v1"),
    (artifact = :mgmfrm_manual_public_scope_review_for_fit,
        expected_schema =
            "bayesianmgmfrm.mgmfrm_manual_public_scope_review_for_fit.v1"),
]

const PROTOCOL = (;
    protocol_id =
        "mgmfrm_publication_grade_threshold_model_weight_policy_review_v1",
    review_kind =
        :local_publication_grade_threshold_model_weight_policy_review,
    publication_or_registration_action = false,
    local_only = true,
    source_gate =
        :compare_publication_grade_batch_against_threshold_and_model_weight_policy,
    primary_prediction_target = :heldout_observation_log_score,
    thresholds = (;
        require_publication_grade_batch_results_review_passed = true,
        require_fit_metric_threshold_sensitivity_passed = true,
        require_prediction_target_and_model_weight_policy_passed = true,
        require_manual_public_scope_review_for_fit_passed = true,
        require_all_125_units_executed = true,
        require_all_mcmc_diagnostic_gates_passed = true,
        require_zero_diagnostic_failure_rows = true,
        require_threshold_profile_batch_rows_recorded = true,
        require_threshold_profiles_change_observed_batch_flag = true,
        require_no_single_threshold_profile_promoted = true,
        require_model_weight_policy_blocks_public_weight_claims = true,
        require_manual_scope_review_blocks_public_weight_claims = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_model_weight_claim = true,
        require_no_sparse_superiority_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

const MODEL_SURFACE = Dict(
    "null_or_intercept_reference" => :analytic_reference_model,
    "scalar_gmfrm_baseline" => :scalar_gmfrm_guarded_fit,
    "confirmatory_mgmfrm_current_q" => :confirmatory_mgmfrm_fit,
    "construct_reviewed_revised_q_mgmfrm" => :confirmatory_mgmfrm_fit,
    "sparse_mgmfrm_current_q" => :confirmatory_mgmfrm_fit,
)

function usage()
    return """
    Generate the local publication-grade threshold/model-weight policy review.

    This compares the completed 125-unit publication-grade batch against the
    threshold-sensitivity artifact and prediction-target/model-weight policy.
    It records local diagnostic weights and threshold sensitivity while keeping
    public fit-threshold, model-weight, Q-revision, and sparse-superiority
    claims blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_threshold_model_weight_policy_review.jl [--output PATH]
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    batch_review = DEFAULT_BATCH_REVIEW
    threshold_sensitivity = DEFAULT_THRESHOLD_SENSITIVITY
    model_weight_policy = DEFAULT_MODEL_WEIGHT_POLICY
    manual_scope_review = DEFAULT_MANUAL_SCOPE_REVIEW
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg == "--batch-review"
            index < length(args) || error("--batch-review requires a path")
            batch_review = abspath(args[index + 1])
            index += 2
        elseif arg == "--threshold-sensitivity"
            index < length(args) ||
                error("--threshold-sensitivity requires a path")
            threshold_sensitivity = abspath(args[index + 1])
            index += 2
        elseif arg == "--model-weight-policy"
            index < length(args) ||
                error("--model-weight-policy requires a path")
            model_weight_policy = abspath(args[index + 1])
            index += 2
        elseif arg == "--manual-scope-review"
            index < length(args) ||
                error("--manual-scope-review requires a path")
            manual_scope_review = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; output, batch_review, threshold_sensitivity,
        model_weight_policy, manual_scope_review)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_float(value) = Float64(value)
as_string(value) = String(value)
json_get(object, key::Symbol, default = missing) =
    haskey(object, key) && object[key] !== nothing ? object[key] : default

function load_json(path::AbstractString)
    return JSON3.read(read(path, String))
end

function artifact_record(artifact::Symbol, path::AbstractString,
        expected_schema::AbstractString)
    exists = isfile(path)
    if !exists
        return (;
            artifact,
            path = rel(path),
            exists = false,
            sha256 = missing,
            expected_schema,
            schema = missing,
            schema_matches = false,
            summary_passed = false,
        )
    end
    parsed = load_json(path)
    schema = as_string(parsed[:schema])
    return (;
        artifact,
        path = rel(path),
        exists,
        sha256 = file_sha256(path),
        expected_schema,
        schema,
        schema_matches = schema == expected_schema,
        summary_passed = as_bool(parsed[:summary][:passed]),
    )
end

function input_artifacts(options)
    paths = Dict(
        :mgmfrm_publication_grade_refit_batch_results_review =>
            options.batch_review,
        :mgmfrm_fit_metric_threshold_sensitivity =>
            options.threshold_sensitivity,
        :prediction_target_and_model_weight_policy =>
            options.model_weight_policy,
        :mgmfrm_manual_public_scope_review_for_fit =>
            options.manual_scope_review,
    )
    return [artifact_record(spec.artifact, paths[spec.artifact],
        spec.expected_schema) for spec in INPUT_SPECS]
end

function policy_by_surface(policy)
    rows = Dict{String,Any}()
    for row in policy[:model_weight_policy_rows]
        rows[as_string(row[:surface])] = row
    end
    return rows
end

function threshold_rows_by_model(batch)
    rows = Dict{String,Vector{Any}}()
    for row in batch[:threshold_profile_model_summary_rows]
        model = as_string(row[:model])
        push!(get!(rows, model, Any[]), row)
    end
    return rows
end

function heldout_rows_by_model(batch)
    rows = Dict{String,Vector{Any}}()
    for row in batch[:heldout_model_rank_rows]
        model = as_string(row[:model])
        push!(get!(rows, model, Any[]), row)
    end
    return rows
end

function check_completed_model_weight_surface(batch)
    summary = batch[:summary]
    heldout_rows = batch[:heldout_model_rank_rows]
    by_model = heldout_rows_by_model(batch)
    expected_models = Set(keys(MODEL_SURFACE))
    observed_models = Set(keys(by_model))
    all_125_units_executed =
        as_bool(json_get(summary, :all_125_units_executed, false))
    summary_row_count =
        as_int(json_get(summary, :n_heldout_model_rank_rows, 0))
    actual_row_count = length(heldout_rows)
    balanced_surface = observed_models == expected_models &&
        all(length(get(by_model, model, Any[])) == 25
            for model in expected_models)

    if !(all_125_units_executed && summary_row_count == 125 &&
            actual_row_count == 125 && balanced_surface)
        model_counts = join([
            "$(model)=$(length(get(by_model, model, Any[])))"
            for model in sort(collect(expected_models))
        ], ", ")
        throw(ArgumentError(
            "publication-grade model weights require a completed " *
            "125-unit heldout surface (5 models x 25 cells); got " *
            "all_125_units_executed=$(all_125_units_executed), " *
            "summary_rows=$(summary_row_count), " *
            "actual_rows=$(actual_row_count), model_rows={$(model_counts)}. " *
            "Regenerate the batch review with --read-local-artifacts after " *
            "all local job artifacts exist."
        ))
    end
    return by_model
end

function model_weight_rows(batch, policy)
    by_model = check_completed_model_weight_surface(batch)
    threshold_by_model = threshold_rows_by_model(batch)
    policy_rows = policy_by_surface(policy)
    totals = Dict(model => sum(as_float(row[:heldout_elpd]) for row in rows)
        for (model, rows) in by_model)
    best_total = maximum(values(totals))
    weight_numerators =
        Dict(model => exp(total - best_total) for (model, total) in totals)
    denominator = sum(values(weight_numerators))

    rows = NamedTuple[]
    for model in sort(collect(keys(totals)))
        threshold_rows = get(threshold_by_model, model, Any[])
        surface = get(MODEL_SURFACE, model, :unmapped_publication_batch_model)
        policy_row = get(policy_rows, String(surface), nothing)
        policy_local_weight =
            policy_row === nothing ? false :
            as_bool(policy_row[:allowed_for_local_model_weight_reporting])
        policy_public_sparse =
            policy_row === nothing ? false :
            as_bool(policy_row[:allowed_for_public_sparse_mgmfrm_claims])
        push!(rows, (;
            model,
            policy_surface = surface,
            n_heldout_rows = length(by_model[model]),
            total_heldout_elpd = totals[model],
            delta_elpd_from_best_total = totals[model] - best_total,
            local_diagnostic_weight =
                weight_numerators[model] / denominator,
            n_threshold_profile_rows = sum(as_int(row[:n_threshold_profile_rows])
                for row in threshold_rows),
            n_threshold_profile_passed_rows =
                sum(as_int(row[:n_passed_rows]) for row in threshold_rows),
            n_threshold_profile_flagged_rows =
                sum(as_int(row[:n_flagged_rows]) for row in threshold_rows),
            any_threshold_profile_passed =
                any(row -> as_bool(row[:any_threshold_profile_passed]),
                    threshold_rows),
            all_threshold_profiles_passed =
                !isempty(threshold_rows) &&
                all(row -> as_bool(row[:all_evaluable_rows_passed]),
                    threshold_rows),
            threshold_profile_promoted =
                any(row -> as_bool(row[:threshold_profile_promoted]),
                    threshold_rows),
            policy_local_weight_reporting_allowed = policy_local_weight,
            policy_public_sparse_claim_allowed = policy_public_sparse,
            public_model_weight_claim_allowed = false,
            public_fit_metric_claim_allowed = false,
            sparse_superiority_claim_allowed = false,
            descriptive_only = true,
        ))
    end
    return sort(rows; by = row -> row.local_diagnostic_weight, rev = true)
end

function threshold_profile_decision_rows(batch)
    rows = NamedTuple[]
    for profile_row in batch[:threshold_profile_rows]
        profile = as_string(profile_row[:profile])
        matching = [row for row in batch[:threshold_profile_job_rows]
            if as_string(row[:profile]) == profile]
        n_rows = length(matching)
        n_passed = count(row -> as_bool(row[:threshold_profile_passed]),
            matching)
        n_flagged = sum(as_int(row[:n_threshold_flags]) > 0 ? 1 : 0
            for row in matching)
        push!(rows, (;
            profile,
            n_threshold_profile_rows = n_rows,
            n_passed_rows = n_passed,
            n_flagged_rows = n_flagged,
            pass_rate = n_rows == 0 ? 0.0 : n_passed / n_rows,
            threshold_profile_promoted = false,
            public_fit_metric_claim_allowed = false,
            descriptive_only = true,
        ))
    end
    return rows
end

function claim_gate_rows(batch, policy, manual_review)
    batch_summary = batch[:summary]
    policy_summary = policy[:summary]
    manual_summary = manual_review[:summary]
    return [
        (claim = :public_fit_threshold_claim,
            status = :blocked,
            evidence = :publication_grade_threshold_profiles_compared,
            reason =
                :no_single_threshold_profile_promoted_and_batch_flags_remain,
            resolved_by_this_gate = false,
            public_claim_allowed = false),
        (claim = :public_model_weight_claim,
            status = :blocked,
            evidence = :prediction_target_and_model_weight_policy,
            reason =
                :policy_and_manual_scope_review_keep_public_weight_claims_blocked,
            policy_public_model_weight_claims_allowed =
                as_bool(policy_summary[:public_model_weight_claims_allowed]),
            manual_public_model_weight_claims_allowed =
                as_bool(manual_summary[:public_model_weight_claims_allowed]),
            resolved_by_this_gate = false,
            public_claim_allowed = false),
        (claim = :sparse_mgmfrm_superiority_claim,
            status = :blocked,
            evidence = :publication_grade_batch_heldout_ranking,
            reason =
                :sparse_model_not_promoted_and_external_construct_dataset_missing,
            resolved_by_this_gate = false,
            public_claim_allowed = false),
        (claim = :q_revision_claim,
            status = :blocked,
            evidence = :publication_grade_batch_and_construct_policy,
            reason = :external_construct_dataset_missing,
            resolved_by_this_gate = false,
            public_claim_allowed = false),
        (claim = :diagnostic_gate_claim,
            status = :local_diagnostic_passed,
            evidence = :all_mcmc_diagnostic_gates_passed,
            n_diagnostic_failure_rows =
                as_int(batch_summary[:n_diagnostic_failure_rows]),
            resolved_by_this_gate = true,
            public_claim_allowed = false),
    ]
end

function blocker_rows(batch)
    rows = NamedTuple[]
    for row in batch[:blocker_rows]
        push!(rows, (;
            blocker = as_string(row[:blocker]),
            blocks = as_string(row[:blocks]),
            resolved = as_bool(row[:resolved]),
            source = :publication_grade_batch_results_review,
            carried_into_policy_review = true,
        ))
    end
    return rows
end

function build_artifact(options)
    inputs = input_artifacts(options)
    batch = load_json(options.batch_review)
    threshold = load_json(options.threshold_sensitivity)
    policy = load_json(options.model_weight_policy)
    manual_review = load_json(options.manual_scope_review)

    batch_summary = batch[:summary]
    threshold_summary = threshold[:summary]
    policy_summary = policy[:summary]
    manual_summary = manual_review[:summary]

    model_rows = model_weight_rows(batch, policy)
    threshold_profile_rows = threshold_profile_decision_rows(batch)
    claims = claim_gate_rows(batch, policy, manual_review)
    blockers = blocker_rows(batch)

    all_input_artifacts_present = all(row -> row.exists, inputs)
    all_expected_schemas = all(row -> row.schema_matches, inputs)
    all_input_summaries_passed = all(row -> row.summary_passed, inputs)
    all_125_units_executed = as_bool(batch_summary[:all_125_units_executed])
    all_mcmc_diagnostic_gates_passed =
        as_bool(batch_summary[:all_mcmc_diagnostic_gates_passed])
    zero_diagnostic_failures =
        as_int(batch_summary[:n_diagnostic_failure_rows]) == 0
    threshold_rows_recorded =
        as_int(batch_summary[:n_threshold_profile_job_rows]) == 500
    threshold_profiles_change_observed_batch_flag =
        as_bool(batch_summary[:threshold_profiles_change_observed_batch_flag])
    no_single_threshold_profile_promoted =
        as_bool(batch_summary[:no_single_threshold_profile_promoted]) &&
        all(row -> !row.threshold_profile_promoted, threshold_profile_rows)
    policy_blocks_public_weight =
        !as_bool(policy_summary[:public_model_weight_claims_allowed])
    manual_blocks_public_weight =
        !as_bool(manual_summary[:public_model_weight_claims_allowed])
    no_public_fit_metric_claim =
        all(row -> !row.public_fit_metric_claim_allowed, model_rows)
    no_public_model_weight_claim =
        all(row -> !row.public_model_weight_claim_allowed, model_rows) &&
        policy_blocks_public_weight &&
        manual_blocks_public_weight
    no_sparse_superiority_claim =
        all(row -> !row.sparse_superiority_claim_allowed, model_rows)
    remaining_public_blockers =
        [row.blocker for row in blockers if !row.resolved]

    passed =
        all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        all_125_units_executed &&
        all_mcmc_diagnostic_gates_passed &&
        zero_diagnostic_failures &&
        threshold_rows_recorded &&
        threshold_profiles_change_observed_batch_flag &&
        no_single_threshold_profile_promoted &&
        policy_blocks_public_weight &&
        manual_blocks_public_weight &&
        no_public_fit_metric_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim

    best_model = model_rows[1].model
    next_gate = isempty(remaining_public_blockers) ?
        :independent_public_claim_review_before_any_model_weight_or_sparse_claim :
        :attach_external_construct_dataset_and_independent_public_scope_review

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_threshold_model_weight_policy_review.v1",
        family = :mgmfrm,
        scope = :publication_grade_threshold_model_weight_policy_review,
        status = :publication_grade_threshold_model_weight_policy_review_recorded,
        decision =
            :record_threshold_model_weight_policy_comparison_keep_claims_blocked,
        public_fit = true,
        experimental_public = true,
        local_only = true,
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
        input_artifacts = inputs,
        threshold_profile_decision_rows = threshold_profile_rows,
        model_weight_policy_alignment_rows = model_rows,
        claim_gate_rows = claims,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :threshold_model_weight_policy_review_recorded_local_only,
            publication_grade_batch_completed = all_125_units_executed,
            all_mcmc_diagnostic_gates_passed,
            threshold_profiles_promoted = false,
            best_total_heldout_elpd_model = best_model,
            local_diagnostic_weights_recorded = true,
            public_fit_metric_claim_allowed = false,
            public_model_weight_claim_allowed = false,
            sparse_superiority_claim_allowed = false,
            required_followup = next_gate,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            publication_grade_batch_results_review_passed =
                as_bool(batch_summary[:passed]),
            fit_metric_threshold_sensitivity_passed =
                as_bool(threshold_summary[:passed]),
            prediction_target_and_model_weight_policy_passed =
                as_bool(policy_summary[:passed]),
            manual_public_scope_review_for_fit_passed =
                as_bool(manual_summary[:passed]),
            all_125_units_executed,
            all_mcmc_diagnostic_gates_passed,
            zero_diagnostic_failures,
            threshold_profile_batch_rows_recorded = threshold_rows_recorded,
            threshold_profiles_change_observed_batch_flag,
            no_single_threshold_profile_promoted,
            policy_blocks_public_model_weight_claims =
                policy_blocks_public_weight,
            manual_scope_review_blocks_public_model_weight_claims =
                manual_blocks_public_weight,
            no_public_fit_metric_claim,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            n_input_artifacts = length(inputs),
            n_threshold_profile_decision_rows =
                length(threshold_profile_rows),
            n_model_weight_policy_alignment_rows = length(model_rows),
            n_claim_gate_rows = length(claims),
            n_threshold_profile_job_rows =
                as_int(batch_summary[:n_threshold_profile_job_rows]),
            n_threshold_profile_passed_rows =
                as_int(batch_summary[:n_threshold_profile_passed_rows]),
            n_threshold_profile_flagged_rows =
                as_int(batch_summary[:n_threshold_profile_flagged_rows]),
            n_batch_execution_job_rows =
                as_int(batch_summary[:n_batch_execution_job_rows]),
            n_diagnostic_failure_rows =
                as_int(batch_summary[:n_diagnostic_failure_rows]),
            best_total_heldout_elpd_model = best_model,
            best_total_heldout_elpd =
                model_rows[1].total_heldout_elpd,
            null_or_intercept_reference_local_weight =
                only(row for row in model_rows
                    if row.model == "null_or_intercept_reference").
                    local_diagnostic_weight,
            scalar_gmfrm_baseline_local_weight =
                only(row for row in model_rows
                    if row.model == "scalar_gmfrm_baseline").
                    local_diagnostic_weight,
            n_blocker_rows = length(blockers),
            n_blockers = count(row -> !row.resolved, blockers),
            remaining_public_blockers,
            recommendation =
                :keep_public_threshold_model_weight_q_revision_and_sparse_claims_blocked,
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
        " best_model=", artifact.summary.best_total_heldout_elpd_model,
        " blockers=", artifact.summary.n_blockers,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
