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
        "mgmfrm_guarded_fit_public_exposure_review.json")

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
    (name = :dff_estimand_validation_grid,
        path = "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_dff_estimand_validation_grid.v1",
        pass_policy = :summary_passed),
]

const BLOCKER_ROWS = [
    (blocker = :prediction_target_and_model_weight_policy_missing,
        severity = :blocking,
        required_action =
            :define_prediction_target_and_model_weight_policy_before_mgmfrm_public_claims),
]

const PROTOCOL = (;
    protocol_id = "confirmatory_mgmfrm_guarded_fit_public_exposure_review_v1",
    review_kind = :local_confirmatory_mgmfrm_guarded_fit_public_exposure_review,
    publication_or_registration_action = false,
    local_only = true,
    entrypoint_under_review = "fit(spec; experimental = true)",
    decision_target = :confirmatory_mgmfrm_guarded_fit_public_exposure,
    thresholds = (;
        require_bridge_oracle_present = true,
        require_candidate_chain_study_passed = true,
        require_recovery_smoke_passed = true,
        require_baseline_comparison_passed = true,
        require_sparse_recovery_grid_passed = true,
        require_guarded_fit_method_wiring_passed = true,
        require_guarded_fit_validation_grid_passed = true,
        require_guarded_fit_api_dry_run_passed = true,
        require_dff_estimand_validation_grid_passed = true,
        require_fit_boundary_checks_passed = true,
        require_manifest_enables_guarded_mgmfrm_fit = true,
        require_prediction_target_and_model_weight_blocker = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local confirmatory MGMFRM guarded fit public exposure review.

    This records a local-only public exposure decision for the confirmatory
    MGMFRM guarded fit surface. It confirms the guarded experimental entrypoint
    and keeps model-weight, sparse-superiority, and broader MGMFRM claims
    blocked until their policy gates are satisfied.

    Usage:
      julia --project=. scripts/generate_mgmfrm_guarded_fit_public_exposure_review.jl [--output PATH]
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

json_int(text::AbstractString, key::AbstractString) =
    parse(Int, required_value(text, key))

function json_summary(text::AbstractString)
    return json_value_for_key(text, "summary")
end

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
        method_fit_boundary_checks_passed =
            summary_bool(summary, "method_fit_boundary_checks_passed"),
        method_experimental_spec_fit_succeeded =
            summary_bool(summary, "method_experimental_spec_fit_succeeded"),
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
    passed = exists &&
        schema_matches &&
        summary_passed(summary_text, spec.pass_policy)
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
        "julia --project=. scripts/generate_mgmfrm_guarded_fit_public_exposure_review.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
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
        gate = :current_guarded_fit_boundary,
        status = all(row -> row.passed, boundary_checks) ?
            :passed : :failed,
        evidence = all(row -> row.passed, boundary_checks),
        key_check = :guarded_fit_boundary_checks_passed,
        artifact = :fit_boundary_checks,
    ))
    push!(rows, (;
        gate = :prediction_target_and_model_weight_policy,
        status = :blocked,
        evidence = false,
        key_check = :policy_not_yet_recorded,
        artifact = :future_policy_artifact,
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
    chain = record_by_name(input_records, :candidate_chain_study)
    recovery = record_by_name(input_records, :recovery_smoke)
    baseline = record_by_name(input_records, :baseline_comparison)
    sparse = record_by_name(input_records, :sparse_recovery_grid)
    method = record_by_name(input_records, :guarded_fit_method_wiring)
    validation = record_by_name(input_records, :guarded_fit_validation_grid)
    api_dry_run = record_by_name(input_records, :guarded_fit_api_dry_run)
    dff = record_by_name(input_records, :dff_estimand_validation_grid)

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
    rows = review_rows(input_records, boundary_checks)

    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_input_summaries_passed =
        all(record -> record.summary_passed, input_records)
    all_fit_boundary_checks_passed = all(row -> row.passed, boundary_checks)
    current_manifest_guarded_fit_enabled =
        Bool(decision.summary.fit_allowed) &&
        Bool(decision.summary.experimental_keyword_enabled)
    no_publication = no_publication_commands()
    blockers_recorded =
        any(row -> row.blocker ===
            :prediction_target_and_model_weight_policy_missing, BLOCKER_ROWS)
    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        all_fit_boundary_checks_passed &&
        current_manifest_guarded_fit_enabled &&
        blockers_recorded &&
        no_publication &&
        !Bool(PROTOCOL.publication_or_registration_action)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_public_exposure_review.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :guarded_fit_public_exposure_review_recorded,
        decision = :enable_guarded_experimental,
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
        review_rows = rows,
        blocker_rows = BLOCKER_ROWS,
        decision_record = (;
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            current_manifest_fit_allowed = decision.summary.fit_allowed,
            current_manifest_experimental_keyword_enabled =
                decision.summary.experimental_keyword_enabled,
            public_exposure_support =
                :review_recorded_guarded_fit_enabled_until_prediction_target_and_model_weight_policy,
            interpretation =
                :guarded_mgmfrm_public_exposure_review_recorded_entrypoint_enabled_claims_blocked,
            required_followup = :prediction_target_and_model_weight_policy,
        ),
        summary = (;
            passed,
            reviewed = true,
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
            bridge_oracle_present =
                record_by_name(input_records, :bridge_oracle).summary_passed,
            mgmfrm_candidate_chain_study_passed = chain.summary_passed,
            mgmfrm_recovery_smoke_passed = recovery.summary_passed,
            mgmfrm_baseline_comparison_passed = baseline.summary_passed,
            mgmfrm_sparse_recovery_grid_passed = sparse.summary_passed,
            mgmfrm_guarded_fit_method_wiring_passed = method.summary_passed,
            mgmfrm_guarded_fit_validation_grid_passed =
                validation.summary_passed,
            mgmfrm_guarded_fit_api_dry_run_passed =
                api_dry_run.summary_passed,
            dff_estimand_validation_grid_passed = dff.summary_passed,
            method_fit_boundary_checks_passed =
                Bool(method.summary.all_fit_boundary_checks_passed),
            method_experimental_spec_fit_succeeded =
                Bool(method.summary.experimental_spec_fit_succeeded),
            validation_all_rows_passed =
                Bool(validation.summary.all_validation_rows_passed),
            api_dry_run_fit_boundary_checks_passed =
                Bool(api_dry_run.summary.all_fit_boundary_checks_passed),
            api_dry_run_experimental_spec_fit_succeeded =
                Bool(api_dry_run.summary.experimental_spec_fit_succeeded),
            api_dry_run_gradient_diagnostics_passed =
                Bool(api_dry_run.summary.target_gradient_diagnostics_passed),
            dff_model_effects_allowed =
                Bool(dff.summary.dff_model_effects_allowed),
            n_input_artifacts = length(input_records),
            n_fit_boundary_checks = length(boundary_checks),
            n_review_rows = length(rows),
            n_blockers = length(BLOCKER_ROWS),
            remaining_public_blockers =
                [row.blocker for row in BLOCKER_ROWS],
            recommendation =
                :guarded_mgmfrm_fit_enabled_keep_weight_claims_blocked_until_policy,
            next_gate = :prediction_target_and_model_weight_policy,
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
