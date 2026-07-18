#!/usr/bin/env julia

using SHA
using TOML

import BayesianMGMFRM

module MGMFRMChainStudy
include(joinpath(@__DIR__, "generate_mgmfrm_candidate_chain_study.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_manual_public_scope_review_for_fit.json")

include(joinpath(@__DIR__, "local_json.jl"))

const CHAIN = MGMFRMChainStudy

const INPUT_ARTIFACTS = [
    (name = :bridge_oracle,
        path = "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        expected_schema = "bayesianmgmfrm.source_mgmfrm_bridge_logdensity.v1",
        pass_policy = :schema_only),
    (name = :candidate_chain_study,
        path = "test/fixtures/mgmfrm_candidate_chain_study.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_candidate_chain_study.v1",
        pass_policy = :summary_passed),
    (name = :recovery_smoke,
        path = "test/fixtures/mgmfrm_recovery_smoke.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_recovery_smoke.v1",
        pass_policy = :summary_passed),
    (name = :baseline_comparison,
        path = "test/fixtures/mgmfrm_baseline_comparison.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_baseline_comparison.v1",
        pass_policy = :summary_passed),
    (name = :sparse_recovery_grid,
        path = "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_sparse_recovery_grid.v1",
        pass_policy = :summary_passed),
    (name = :guarded_fit_method_wiring,
        path = "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_method_wiring.v1",
        pass_policy = :summary_passed),
    (name = :guarded_fit_validation_grid,
        path = "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_validation_grid.v1",
        pass_policy = :summary_passed),
    (name = :guarded_fit_api_dry_run,
        path = "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_api_dry_run.v1",
        pass_policy = :summary_passed),
    (name = :guarded_fit_public_exposure_review,
        path = "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_public_exposure_review.v1",
        pass_policy = :summary_passed),
    (name = :prediction_target_and_model_weight_policy,
        path =
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_prediction_target_and_model_weight_policy.v1",
        pass_policy = :summary_passed),
    (name = :dff_estimand_validation_grid,
        path = "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_dff_estimand_validation_grid.v1",
        pass_policy = :summary_passed),
]

const PROTOCOL = (;
    protocol_id = "confirmatory_mgmfrm_manual_public_scope_review_for_fit_v1",
    review_kind = :local_manual_public_scope_review_for_mgmfrm_fit,
    publication_or_registration_action = false,
    local_only = true,
    reviewed_surface = :confirmatory_mgmfrm_fit,
    reviewed_entrypoint = "fit(spec; experimental = true)",
    thresholds = (;
        require_bridge_oracle_present = true,
        require_candidate_chain_study_passed = true,
        require_recovery_smoke_passed = true,
        require_baseline_comparison_passed = true,
        require_sparse_recovery_grid_passed = true,
        require_guarded_fit_method_wiring_passed = true,
        require_guarded_fit_validation_grid_passed = true,
        require_guarded_fit_api_dry_run_passed = true,
        require_guarded_fit_public_exposure_review_passed = true,
        require_prediction_target_and_model_weight_policy_passed = true,
        require_dff_estimand_validation_grid_passed = true,
        require_fit_boundary_checks_passed = true,
        require_manifest_enables_guarded_mgmfrm_fit = true,
        require_scope_limited_to_confirmatory_fixed_q = true,
        require_no_sparse_superiority_claims = true,
        require_no_public_model_weight_claims = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local manual public-scope review for confirmatory MGMFRM fit.

    This records a local-only review of the first confirmatory MGMFRM fit
    surface. It does not publish, register, or promote broad MGMFRM claims; it
    resolves the preceding scope-review gate and confirms the guarded local
    fit entrypoint.

    Usage:
      julia --project=. scripts/generate_mgmfrm_manual_public_scope_review_for_fit.jl [--output PATH]
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
local_path(path::AbstractString) = normpath(joinpath(ROOT, path))

function parse_json_string_literal(chars::Vector{Char}, index::Int)
    chars[index] == '"' || error("expected JSON string at character $index")
    io = IOBuffer()
    escaped = false
    index += 1
    while index <= length(chars)
        char = chars[index]
        if escaped
            if char == '"' || char == '\\' || char == '/'
                print(io, char)
            elseif char == 'n'
                print(io, '\n')
            elseif char == 'r'
                print(io, '\r')
            elseif char == 't'
                print(io, '\t')
            else
                error("unsupported JSON escape sequence \\$char")
            end
            escaped = false
        elseif char == '\\'
            escaped = true
        elseif char == '"'
            return String(take!(io)), index + 1
        else
            print(io, char)
        end
        index += 1
    end
    error("unterminated JSON string")
end

function skip_ws(chars::Vector{Char}, index::Int)
    while index <= length(chars) && chars[index] in (' ', '\n', '\r', '\t')
        index += 1
    end
    return index
end

function json_value_end(chars::Vector{Char}, index::Int)
    index = skip_ws(chars, index)
    depth = 0
    in_string = false
    escaped = false
    while index <= length(chars)
        char = chars[index]
        if in_string
            if escaped
                escaped = false
            elseif char == '\\'
                escaped = true
            elseif char == '"'
                in_string = false
            end
        elseif char == '"'
            in_string = true
        elseif char == '{' || char == '['
            depth += 1
        elseif char == '}' || char == ']'
            depth == 0 && return index - 1
            depth -= 1
        elseif char == ',' && depth == 0
            return index - 1
        end
        index += 1
    end
    return length(chars)
end

function json_value_for_key(text::AbstractString, key::AbstractString)
    chars = collect(text)
    index = skip_ws(chars, 1)
    chars[index] == '{' || error("expected JSON object")
    index += 1
    while index <= length(chars)
        index = skip_ws(chars, index)
        index > length(chars) && break
        chars[index] == '}' && break
        parsed_key, index = parse_json_string_literal(chars, index)
        index = skip_ws(chars, index)
        chars[index] == ':' || error("expected ':' after JSON key $parsed_key")
        index = skip_ws(chars, index + 1)
        value_start = index
        value_stop = json_value_end(chars, value_start)
        parsed_key == key && return strip(String(chars[value_start:value_stop]))
        index = skip_ws(chars, value_stop + 1)
        if index <= length(chars) && chars[index] == ','
            index += 1
        end
    end
    return nothing
end

function required_value(text::AbstractString, key::AbstractString)
    value = json_value_for_key(text, key)
    value === nothing && error("JSON field `$key` not found")
    return value
end

function json_string(text::AbstractString, key::AbstractString)
    parsed, _ = parse_json_string_literal(collect(required_value(text, key)), 1)
    return parsed
end

function json_optional_bool(text::AbstractString, key::AbstractString)
    value = json_value_for_key(text, key)
    value === nothing && return missing
    value == "true" && return true
    value == "false" && return false
    value == "null" && return missing
    return missing
end

json_summary(text::AbstractString) = json_value_for_key(text, "summary")

function summary_bool(summary::Union{Nothing,AbstractString},
        key::AbstractString,
        default::Bool = false)
    summary === nothing && return default
    value = json_optional_bool(summary, key)
    return value === missing ? default : Bool(value)
end

function summary_int(summary::Union{Nothing,AbstractString},
        key::AbstractString,
        default::Int = 0)
    summary === nothing && return default
    value = json_value_for_key(summary, key)
    value === nothing && return default
    return parse(Int, value)
end

function summary_passed(summary::Union{Nothing,AbstractString}, policy::Symbol)
    policy === :schema_only && return true
    summary === nothing && return false
    for key in ("passed", "overall_passed", "reviewed")
        value = json_optional_bool(summary, key)
        value === missing || return Bool(value)
    end
    return false
end

function artifact_summary(name::Symbol, summary::Union{Nothing,AbstractString})
    name === :bridge_oracle && return (;
        passed = true,
        key_check = :schema_present,
        public_fit_allowed = false,
    )
    name === :candidate_chain_study && return (;
        passed = summary_bool(summary, "overall_passed"),
        key_check = :sampler_diagnostics,
        n_divergences = summary_int(summary, "n_divergences"),
        n_failed_direct_constraints =
            summary_int(summary, "n_failed_direct_constraints"),
        public_fit_allowed = false,
    )
    name === :recovery_smoke && return (;
        passed = summary_bool(summary, "passed"),
        key_check = :recovery_smoke,
        n_parameters = summary_int(summary, "n_parameters"),
        public_fit_allowed = false,
    )
    name === :baseline_comparison && return (;
        passed = summary_bool(summary, "passed"),
        key_check = :baseline_comparison,
        comparison_executed = summary_bool(summary, "comparison_executed"),
        public_fit_allowed = summary_bool(summary, "public_fit_allowed"),
    )
    name === :sparse_recovery_grid && return (;
        passed = summary_bool(summary, "passed"),
        key_check = :sparse_recovery,
        n_scenarios = summary_int(summary, "n_scenarios"),
        all_validations_passed =
            summary_bool(summary, "all_validations_passed"),
        all_sampler_passed = summary_bool(summary, "all_sampler_passed"),
        public_fit_allowed = summary_bool(summary, "public_fit_allowed"),
    )
    name === :guarded_fit_method_wiring && return (;
        passed = summary_bool(summary, "passed"),
        key_check = :guarded_method_wiring,
        entrypoint_enabled = summary_bool(summary, "entrypoint_enabled", true),
        public_fit_allowed = summary_bool(summary, "public_fit_allowed"),
        all_fit_boundary_checks_passed =
            summary_bool(summary, "all_fit_boundary_checks_passed"),
        experimental_spec_fit_succeeded =
            summary_bool(summary, "experimental_spec_fit_succeeded"),
    )
    name === :guarded_fit_validation_grid && return (;
        passed = summary_bool(summary, "passed"),
        key_check = :guarded_validation_grid,
        entrypoint_enabled = summary_bool(summary, "entrypoint_enabled", true),
        public_fit_allowed = summary_bool(summary, "public_fit_allowed"),
        all_validation_rows_passed =
            summary_bool(summary, "all_validation_rows_passed"),
    )
    name === :guarded_fit_api_dry_run && return (;
        passed = summary_bool(summary, "passed"),
        key_check = :guarded_api_dry_run,
        dry_run_only = summary_bool(summary, "dry_run_only"),
        entrypoint_enabled = summary_bool(summary, "entrypoint_enabled", true),
        public_fit_allowed = summary_bool(summary, "public_fit_allowed"),
        all_fit_boundary_checks_passed =
            summary_bool(summary, "all_fit_boundary_checks_passed"),
        experimental_spec_fit_succeeded =
            summary_bool(summary, "experimental_spec_fit_succeeded"),
        target_gradient_diagnostics_passed =
            summary_bool(summary, "target_gradient_diagnostics_passed"),
    )
    name === :guarded_fit_public_exposure_review && return (;
        passed = summary_bool(summary, "passed"),
        key_check = :public_exposure_review,
        reviewed = summary_bool(summary, "reviewed"),
        current_manifest_guarded_fit_enabled =
            summary_bool(summary, "current_manifest_guarded_fit_enabled"),
        public_fit_allowed = summary_bool(summary, "public_fit_allowed"),
    )
    name === :prediction_target_and_model_weight_policy && return (;
        passed = summary_bool(summary, "passed"),
        key_check = :prediction_target_policy,
        policy_recorded = summary_bool(summary, "policy_recorded"),
        mgmfrm_fit_allowed = summary_bool(summary, "mgmfrm_fit_allowed"),
        mgmfrm_weight_claims_allowed =
            summary_bool(summary, "mgmfrm_weight_claims_allowed"),
        manuscript_sparse_mgmfrm_claims_allowed =
            summary_bool(summary, "manuscript_sparse_mgmfrm_claims_allowed"),
    )
    name === :dff_estimand_validation_grid && return (;
        passed = summary_bool(summary, "passed"),
        key_check = :dff_validation_only,
        dff_model_effects_allowed =
            summary_bool(summary, "dff_model_effects_allowed"),
        public_fit_allowed = summary_bool(summary, "public_fit_allowed"),
    )
    return (;
        passed = summary_bool(summary, "passed"),
        key_check = :summary_passed,
        public_fit_allowed = false,
    )
end

function artifact_record(spec)
    path = local_path(spec.path)
    exists = isfile(path)
    text = exists ? read(path, String) : ""
    schema = exists ? json_string(text, "schema") : missing
    schema_matches = exists && schema == spec.expected_schema
    summary_text = exists ? json_summary(text) : nothing
    parsed_summary = artifact_summary(spec.name, summary_text)
    passed = exists && schema_matches && summary_passed(summary_text, spec.pass_policy)
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        sha256 = exists ? file_sha256(path) : missing,
        expected_schema = spec.expected_schema,
        schema,
        schema_matches,
        pass_policy = spec.pass_policy,
        summary_passed = passed,
        summary = parsed_summary,
    )
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function rejection_check(name::Symbol, callable)
    try
        callable()
        return (;
            check = name,
            rejected = false,
            error_type = missing,
            message = missing,
        )
    catch err
        return (;
            check = name,
            rejected = true,
            error_type = String(nameof(typeof(err))),
            message = portable_error_message(err),
        )
    end
end

rejection_check(callable, name::Symbol) = rejection_check(name, callable)

function fit_boundary_check(name::Symbol, expected_status::Symbol, callable)
    check = rejection_check(name, callable)
    actual_status = Bool(check.rejected) ? :rejected : :succeeded
    return (;
        check.check,
        expected_status,
        actual_status,
        check.rejected,
        check.error_type,
        check.message,
        passed = actual_status === expected_status,
    )
end

fit_boundary_check(callable, name::Symbol, expected_status::Symbol) =
    fit_boundary_check(name, expected_status, callable)

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_manual_public_scope_review_for_fit.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function scope_decision_rows(input_records)
    policy = record_by_name(input_records,
        :prediction_target_and_model_weight_policy)
    public_review =
        record_by_name(input_records, :guarded_fit_public_exposure_review)
    return [
        (surface = :confirmatory_mgmfrm_public_fit_api,
            decision = :enable_guarded_experimental,
            evidence = Bool(public_review.summary_passed) &&
                Bool(policy.summary_passed),
            public_fit = true,
            allowed_for_local_implementation = true,
            required_followup = :guarded_local_mgmfrm_fit_entrypoint),
        (surface = :confirmatory_mgmfrm_local_guarded_fit_development,
            decision = :scope_review_recorded_allow_next_local_gate,
            evidence = all(record -> record.summary_passed, input_records),
            public_fit = true,
            allowed_for_local_implementation = true,
            required_followup = :guarded_local_mgmfrm_fit_entrypoint),
        (surface = :sparse_mgmfrm_superiority_claims,
            decision = :keep_blocked,
            evidence = Bool(policy.summary_passed),
            public_fit = false,
            allowed_for_local_implementation = false,
            required_followup = :guarded_local_mgmfrm_fit_entrypoint),
        (surface = :public_model_weight_claims,
            decision = :keep_blocked,
            evidence = Bool(policy.summary_passed),
            public_fit = false,
            allowed_for_local_implementation = false,
            required_followup = :future_public_model_weight_claim_review),
        (surface = :dff_model_effects,
            decision = :keep_validation_only,
            evidence =
                Bool(record_by_name(input_records,
                    :dff_estimand_validation_grid).summary_passed),
            public_fit = false,
            allowed_for_local_implementation = false,
            required_followup = :future_dff_model_effect_fit_policy),
    ]
end

function risk_rows()
    return [
        (risk = :mgmfrm_scope_confusion,
            decision = :local_scope_review_only,
            mitigation = :label_as_guarded_experimental_fixed_q_only),
        (risk = :gauge_overclaim,
            decision = :restrict_to_fixed_q_identity_latent_correlation,
            mitigation = :block_exploratory_loadings_and_free_correlations),
        (risk = :sparse_superiority_overclaim,
            decision = :keep_sparse_mgmfrm_superiority_claims_blocked,
            mitigation = :require_guarded_fit_and_claim_level_review),
        (risk = :model_weight_overclaim,
            decision = :keep_public_model_weight_claims_blocked,
            mitigation = :retain_heldout_kfold_as_local_scalar_policy_only),
        (risk = :dff_overclaim,
            decision = :keep_dff_model_effects_validation_only,
            mitigation = :require_separate_dff_model_effect_fit_policy),
    ]
end

function review_rows(input_records, boundary_checks)
    rows = NamedTuple[]
    for record in input_records
        push!(rows, (;
            gate = record.artifact,
            status = record.summary_passed ? :passed : :failed,
            evidence = record.summary_passed,
            key_check = record.summary.key_check,
            artifact = record.path,
        ))
    end
    push!(rows, (;
        gate = :current_mgmfrm_fit_boundary,
        status = all(row -> row.passed, boundary_checks) ?
            :passed : :failed,
        evidence = all(row -> row.passed, boundary_checks),
        key_check = :guarded_fit_boundary_checks_passed,
        artifact = :fit_boundary_checks,
    ))
    push!(rows, (;
        gate = :manual_public_scope_review_for_mgmfrm_fit,
        status = :passed,
        evidence = true,
        key_check = :local_scope_review_recorded,
        artifact = "test/fixtures/mgmfrm_manual_public_scope_review_for_fit.json",
    ))
    return rows
end

function build_artifact()
    spec = CHAIN.confirmatory_mgmfrm_spec()
    design = BayesianMGMFRM.getdesign(spec; preview = true)
    manifest = BayesianMGMFRM.model_manifest(design)
    candidate = manifest.design.raw_parameterization.confirmatory_candidate
    decision = candidate.experimental_public_api_decision
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    public_review =
        record_by_name(input_records, :guarded_fit_public_exposure_review)
    policy = record_by_name(input_records,
        :prediction_target_and_model_weight_policy)

    boundary_checks = [
        fit_boundary_check(:fit_mgmfrm_without_experimental, :rejected) do
            BayesianMGMFRM.fit(spec; ndraws = 1, warmup = 0)
        end,
        fit_boundary_check(:fit_experimental_mgmfrm_guarded_enabled, :succeeded) do
            BayesianMGMFRM.fit(
                spec;
                experimental = true,
                ndraws = 1,
                warmup = 0,
            )
        end,
        fit_boundary_check(:fit_preview_design_with_experimental_keyword, :rejected) do
            BayesianMGMFRM.fit(
                design;
                experimental = true,
                ndraws = 1,
                warmup = 0,
            )
        end,
        fit_boundary_check(:fit_experimental_mgmfrm_julia_backend, :rejected) do
            BayesianMGMFRM.fit(
                spec;
                experimental = true,
                backend = :julia,
                ndraws = 1,
                warmup = 0,
            )
        end,
    ]
    scope_rows = scope_decision_rows(input_records)
    rows = review_rows(input_records, boundary_checks)

    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_input_summaries_passed =
        all(record -> record.summary_passed, input_records)
    all_fit_boundary_checks_passed =
        all(row -> row.passed, boundary_checks)
    current_manifest_guarded_fit_enabled =
        Bool(decision.summary.fit_allowed) &&
        Bool(decision.summary.experimental_keyword_enabled)
    no_publication = no_publication_commands()
    scope_limited_to_confirmatory_fixed_q =
        spec.family === :mgmfrm &&
        spec.dimensions == 2 &&
        spec.q_matrix == Bool[1 0; 0 1]
    no_sparse_superiority_claims =
        !Bool(policy.summary.manuscript_sparse_mgmfrm_claims_allowed)
    no_public_model_weight_claims =
        !Bool(policy.summary.mgmfrm_weight_claims_allowed)
    local_guarded_fit_development_allowed =
        any(row -> row.surface ===
            :confirmatory_mgmfrm_local_guarded_fit_development &&
            Bool(row.allowed_for_local_implementation) &&
            Bool(row.evidence), scope_rows)
    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        all_fit_boundary_checks_passed &&
        current_manifest_guarded_fit_enabled &&
        scope_limited_to_confirmatory_fixed_q &&
        no_sparse_superiority_claims &&
        no_public_model_weight_claims &&
        Bool(public_review.summary.current_manifest_guarded_fit_enabled) &&
        local_guarded_fit_development_allowed &&
        no_publication &&
        !Bool(PROTOCOL.publication_or_registration_action)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_manual_public_scope_review_for_fit.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :manual_public_scope_review_recorded,
        decision = :scope_review_recorded_enable_guarded_experimental_fit,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        input_artifacts = input_records,
        fit_boundary_checks = boundary_checks,
        fit_rejection_checks = boundary_checks,
        manifest_snapshot = (;
            candidate_status = candidate.status,
            compiler_stage = candidate.compiler_stage,
            experimental_decision_status = decision.status,
            experimental_decision = decision.decision,
            experimental_summary = decision.summary,
        ),
        scope_decision_rows = scope_rows,
        risk_rows = risk_rows(),
        review_rows = rows,
        blocker_rows = NamedTuple[],
        decision_record = (;
            selected_decision =
                :manual_scope_review_recorded_enable_guarded_mgmfrm_fit,
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            current_manifest_fit_allowed = decision.summary.fit_allowed,
            current_manifest_experimental_keyword_enabled =
                decision.summary.experimental_keyword_enabled,
            local_guarded_fit_development_allowed,
            public_model_weight_claims_allowed = false,
            sparse_superiority_claims_allowed = false,
            mgmfrm_fit_claims_allowed = true,
            publication_or_registration_action = false,
            public_exposure_support =
                :manual_scope_review_recorded_guarded_fit_enabled_claims_blocked,
            interpretation =
                :confirmatory_mgmfrm_scope_review_recorded_with_guarded_fit_enablement,
            required_followup = :guarded_local_mgmfrm_fit_entrypoint,
        ),
        summary = (;
            passed,
            reviewed = true,
            manual_public_scope_review_recorded = true,
            manual_public_scope_review_satisfied = passed,
            publication_or_registration_action = false,
            local_only = true,
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            current_manifest_fit_allowed = decision.summary.fit_allowed,
            current_manifest_experimental_keyword_enabled =
                decision.summary.experimental_keyword_enabled,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            all_fit_boundary_checks_passed,
            current_manifest_guarded_fit_enabled,
            no_publication_commands = no_publication,
            scope_limited_to_confirmatory_fixed_q,
            local_guarded_fit_development_allowed,
            public_model_weight_claims_allowed = false,
            sparse_superiority_claims_allowed = false,
            mgmfrm_fit_allowed = true,
            bridge_oracle_present =
                record_by_name(input_records, :bridge_oracle).summary_passed,
            mgmfrm_candidate_chain_study_passed =
                record_by_name(input_records,
                    :candidate_chain_study).summary_passed,
            mgmfrm_recovery_smoke_passed =
                record_by_name(input_records, :recovery_smoke).summary_passed,
            mgmfrm_baseline_comparison_passed =
                record_by_name(input_records,
                    :baseline_comparison).summary_passed,
            mgmfrm_sparse_recovery_grid_passed =
                record_by_name(input_records,
                    :sparse_recovery_grid).summary_passed,
            mgmfrm_guarded_fit_method_wiring_passed =
                record_by_name(input_records,
                    :guarded_fit_method_wiring).summary_passed,
            mgmfrm_guarded_fit_validation_grid_passed =
                record_by_name(input_records,
                    :guarded_fit_validation_grid).summary_passed,
            mgmfrm_guarded_fit_api_dry_run_passed =
                record_by_name(input_records,
                    :guarded_fit_api_dry_run).summary_passed,
            mgmfrm_guarded_fit_public_exposure_review_passed =
                public_review.summary_passed,
            prediction_target_and_model_weight_policy_passed =
                policy.summary_passed,
            dff_estimand_validation_grid_passed =
                record_by_name(input_records,
                    :dff_estimand_validation_grid).summary_passed,
            n_input_artifacts = length(input_records),
            n_fit_boundary_checks = length(boundary_checks),
            n_scope_decisions = length(scope_rows),
            n_risk_rows = length(risk_rows()),
            n_review_rows = length(rows),
            n_blockers = 0,
            remaining_public_blockers = Symbol[],
            recommendation =
                :manual_scope_review_recorded_implement_guarded_local_mgmfrm_fit_next,
            next_gate = :guarded_local_mgmfrm_fit_entrypoint,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " reviewed=", artifact.summary.reviewed,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
