#!/usr/bin/env julia

using SHA
using TOML

import BayesianMGMFRM
import ForwardDiff
import LogDensityProblems

module MGMFRMChainStudy
include(joinpath(@__DIR__, "generate_mgmfrm_candidate_chain_study.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "mgmfrm_guarded_fit_api_dry_run.json")

include(joinpath(@__DIR__, "local_json.jl"))

const CHAIN = MGMFRMChainStudy

const INPUT_ARTIFACTS = [
    (name = :bridge_oracle,
        path = "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        expected_schema = "bayesianmgmfrm.source_mgmfrm_bridge_logdensity.v1",
        pass_policy = :schema_only),
    (name = :guarded_fit_method_wiring,
        path = "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_guarded_fit_method_wiring.v1",
        pass_policy = :summary_passed),
    (name = :guarded_fit_validation_grid,
        path = "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_guarded_fit_validation_grid.v1",
        pass_policy = :summary_passed),
]

const PROTOCOL = (;
    protocol_id = "confirmatory_mgmfrm_guarded_fit_api_dry_run_v1",
    review_kind = :local_confirmatory_mgmfrm_guarded_fit_api_contract_dry_run,
    publication_or_registration_action = false,
    dry_run_only = true,
    proposed_entrypoint = "fit(spec; experimental = true)",
    entrypoint_enabled = true,
    public_target_label = :guarded_confirmatory_mgmfrm_logdensity,
    public_target_description =
        "guarded fixed-Q confirmatory MGMFRM log density",
    internal_target_constructor = :_mgmfrm_guarded_local_fit_logdensity,
    target_constructor = :_source_fixture_logdensity,
    transform_constructor = :_mgmfrm_source_constrained_params_from_unconstrained,
    diagnostics = (;
        finite_difference_coords = collect(1:6),
        finite_difference_step = 1.0e-5,
        max_gradient_abs_error = 1.0e-4,
    ),
    decision_rules = (;
        require_non_experimental_fit_rejection = true,
        require_experimental_keyword_success = true,
        require_preview_design_experimental_keyword_rejection = true,
        require_unsupported_backend_rejection = true,
        require_validation_grid_passed = true,
        require_artifact_contract_recorded = true,
        require_required_fields_recorded = true,
        require_required_provenance_recorded = true,
        require_finite_internal_target = true,
        require_gradient_diagnostics_passed = true,
        require_entrypoint_enabled = true,
        require_no_publication_or_registration_action = true,
        public_exposure_review_required_before_broader_claims = true,
    ),
)

function usage()
    return """
    Generate the local confirmatory MGMFRM guarded fit API dry-run artifact.

    This records the proposed guarded MGMFRM entrypoint boundary, validates the
    source-aligned target shape, checks guarded fit boundary behavior, and
    keeps broader MGMFRM claims blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_guarded_fit_api_dry_run.jl [--output PATH]
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

function project_version()
    project = TOML.parsefile(joinpath(ROOT, "Project.toml"))
    return String(project["version"])
end

function file_sha256(path::AbstractString)
    return bytes2hex(open(sha256, path))
end

function package_record()
    return (;
        name = "BayesianMGMFRM",
        version = project_version(),
        julia_version = string(VERSION),
    )
end

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
    if chars[index] == '"'
        _, next_index = parse_json_string_literal(chars, index)
        return next_index - 1
    end
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

function json_value_span(text::AbstractString, key::AbstractString)
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
        parsed_key == key && return value_start:value_stop
        index = skip_ws(chars, value_stop + 1)
        if index <= length(chars) && chars[index] == ','
            index += 1
        end
    end
    return nothing
end

function json_string(text::AbstractString, key::AbstractString)
    span = json_value_span(text, key)
    span === nothing && return ""
    value = strip(String(text[span]))
    startswith(value, "\"") || return value
    parsed, _ = parse_json_string_literal(collect(value), firstindex(value))
    return parsed
end

function json_summary(text::AbstractString)
    span = json_value_span(text, "summary")
    span === nothing && return nothing
    return String(text[span])
end

function json_optional_bool(text::AbstractString, key::AbstractString)
    span = json_value_span(text, key)
    span === nothing && return missing
    value = strip(String(text[span]))
    value == "true" && return true
    value == "false" && return false
    return missing
end

function summary_bool(summary::Union{Nothing,AbstractString},
        key::AbstractString,
        default::Bool = false)
    summary === nothing && return default
    value = json_optional_bool(summary, key)
    return value === missing ? default : Bool(value)
end

function summary_passed(summary::Union{Nothing,AbstractString}, policy::Symbol)
    policy === :schema_only && return true
    summary === nothing && return false
    policy === :summary_passed && return summary_bool(summary, "passed")
    throw(ArgumentError("unknown pass policy: $policy"))
end

function artifact_summary(name::Symbol, summary::Union{Nothing,AbstractString})
    name === :guarded_fit_method_wiring && return (;
        passed = summary_bool(summary, "passed"),
        entrypoint_enabled = summary_bool(summary, "entrypoint_enabled", true),
        sampler_protocol_passed = summary_bool(summary, "sampler_protocol_passed"),
        artifact_contract_satisfied =
            summary_bool(summary, "artifact_contract_satisfied"),
        all_fit_boundary_checks_passed =
            summary_bool(summary, "all_fit_boundary_checks_passed"),
        experimental_spec_fit_succeeded =
            summary_bool(summary, "experimental_spec_fit_succeeded"),
    )
    name === :guarded_fit_validation_grid && return (;
        passed = summary_bool(summary, "passed"),
        entrypoint_enabled = summary_bool(summary, "entrypoint_enabled", true),
        all_validation_rows_passed =
            summary_bool(summary, "all_validation_rows_passed"),
        method_artifact_contract_satisfied =
            summary_bool(summary, "method_artifact_contract_satisfied"),
        method_fit_boundary_checks_passed =
            summary_bool(summary, "method_fit_boundary_checks_passed"),
        method_experimental_spec_fit_succeeded =
            summary_bool(summary, "method_experimental_spec_fit_succeeded"),
    )
    return (; passed = summary_bool(summary, "passed"))
end

function artifact_record(spec)
    path = joinpath(ROOT, spec.path)
    exists = isfile(path)
    text = exists ? read(path, String) : ""
    schema = exists ? json_string(text, "schema") : ""
    schema_matches = schema == spec.expected_schema
    summary_text = exists ? json_summary(text) : nothing
    parsed_summary = artifact_summary(spec.name, summary_text)
    passed = exists && schema_matches && summary_passed(summary_text, spec.pass_policy)
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        sha256 = exists ? file_sha256(path) : missing,
        expected_schema = spec.expected_schema,
        schema = exists ? schema : missing,
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

function contract_review_record(contract)
    return (;
        schema = contract.schema,
        status = contract.status,
        public_fit = contract.public_fit,
        experimental_public = contract.experimental_public,
        artifact_kind = contract.artifact_kind,
        required_field_names = [row.field for row in contract.required_fields],
        required_provenance = [row.artifact for row in contract.provenance_rows],
        n_required_fields = length(contract.required_fields),
        n_required_provenance_artifacts = length(contract.provenance_rows),
        all_required_fields_recorded =
            all(row -> row.status === :required, contract.required_fields),
        all_required_provenance_recorded =
            all(row -> row.status === :required, contract.provenance_rows),
        enables_public_fit = contract.summary.enables_public_fit,
    )
end

function gradient_diagnostics_record(target, raw_initial)
    x = Float64.(collect(raw_initial))
    logp = values -> LogDensityProblems.logdensity(target, values)
    gradient = ForwardDiff.gradient(logp, x)
    rows = NamedTuple[]
    step = PROTOCOL.diagnostics.finite_difference_step
    tolerance = PROTOCOL.diagnostics.max_gradient_abs_error
    for coord in PROTOCOL.diagnostics.finite_difference_coords
        plus = copy(x)
        minus = copy(x)
        plus[coord] += step
        minus[coord] -= step
        finite_difference = (logp(plus) - logp(minus)) / (2.0 * step)
        abs_error = abs(gradient[coord] - finite_difference)
        push!(rows, (;
            coordinate = coord,
            ad_gradient = gradient[coord],
            finite_difference,
            abs_error,
            tolerance,
            passed = isfinite(gradient[coord]) &&
                isfinite(finite_difference) &&
                abs_error <= tolerance,
        ))
    end
    return (;
        n_parameters = length(x),
        n_checked = length(rows),
        finite_gradient = all(isfinite, gradient),
        max_abs_error = maximum(row.abs_error for row in rows),
        max_tolerance = maximum(row.tolerance for row in rows),
        n_failed = count(row -> !row.passed, rows),
        passed = all(row -> row.passed, rows) && all(isfinite, gradient),
        rows,
    )
end

function target_dry_run_record(design)
    target = BayesianMGMFRM._source_fixture_logdensity(design)
    raw_initial = CHAIN.NEAR_ORACLE_RAW
    logdensity = LogDensityProblems.logdensity(target, raw_initial)
    direct = BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
        design,
        raw_initial,
    )
    pointwise = BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood(
        design,
        direct,
    )
    gradient_diagnostics = gradient_diagnostics_record(target, raw_initial)
    return (;
        public_target_label = PROTOCOL.public_target_label,
        public_target_description = PROTOCOL.public_target_description,
        internal_target_constructor = PROTOCOL.internal_target_constructor,
        target = PROTOCOL.target_constructor,
        transform = PROTOCOL.transform_constructor,
        n_raw_parameters = LogDensityProblems.dimension(target),
        n_direct_parameters = length(target.blueprint.constrained_parameter_names),
        n_observations = design.spec.data.n,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        direct_parameter_names = copy(target.blueprint.constrained_parameter_names),
        finite_logdensity = isfinite(logdensity),
        logdensity,
        finite_direct_parameters = all(isfinite, direct),
        finite_pointwise_loglikelihood = all(isfinite, pointwise),
        pointwise_loglikelihood_sum = sum(pointwise),
        gradient_diagnostics,
    )
end

function build_artifact()
    spec = CHAIN.confirmatory_mgmfrm_spec()
    design = BayesianMGMFRM.getdesign(spec; preview = true)
    manifest = BayesianMGMFRM.model_manifest(design)
    candidate = manifest.design.raw_parameterization.confirmatory_candidate
    decision = candidate.experimental_public_api_decision
    target_dry_run = target_dry_run_record(design)
    contract_review = contract_review_record(decision.fit_artifact_contract)
    input_artifacts = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    method = record_by_name(input_artifacts, :guarded_fit_method_wiring)
    validation = record_by_name(input_artifacts, :guarded_fit_validation_grid)
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
    all_input_artifacts_present = all(row -> row.exists, input_artifacts)
    all_expected_schemas = all(row -> row.schema_matches, input_artifacts)
    all_input_summaries_passed = all(row -> row.summary_passed, input_artifacts)
    all_fit_boundary_checks_passed = all(row -> row.passed, boundary_checks)
    artifact_contract_satisfied =
        Bool(contract_review.all_required_fields_recorded) &&
        Bool(contract_review.all_required_provenance_recorded)
    target_diagnostics_passed =
        Bool(target_dry_run.finite_logdensity) &&
        Bool(target_dry_run.finite_direct_parameters) &&
        Bool(target_dry_run.finite_pointwise_loglikelihood) &&
        Bool(target_dry_run.gradient_diagnostics.passed)
    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        all_fit_boundary_checks_passed &&
        artifact_contract_satisfied &&
        target_diagnostics_passed &&
        Bool(PROTOCOL.entrypoint_enabled) &&
        !Bool(PROTOCOL.publication_or_registration_action)

    return (;
        schema = "bayesianmgmfrm.mgmfrm_guarded_fit_api_dry_run.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :guarded_fit_api_dry_run_recorded,
        decision = :enable_guarded_experimental,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        publication_or_registration_action = false,
        package = package_record(),
        protocol = PROTOCOL,
        proposed_entrypoint = PROTOCOL.proposed_entrypoint,
        entrypoint_enabled = true,
        input_artifacts,
        fit_boundary_checks = boundary_checks,
        fit_rejection_checks = boundary_checks,
        artifact_contract_review = contract_review,
        target_dry_run,
        manifest_snapshot = (;
            candidate_status = candidate.status,
            compiler_stage = candidate.compiler_stage,
            public_target_label = decision.public_target_label,
            public_target_description = decision.public_target_description,
            internal_target_constructor = decision.internal_target_constructor,
            decision_raw_prior_control_manifest_schema =
                decision.raw_prior_control_manifest.schema,
            decision_raw_prior_control_rows =
                decision.raw_prior_control_manifest.n_rows,
            decision_raw_prior_control_direct_scale_priors_enabled =
                decision.raw_prior_control_manifest.summary.direct_scale_generalized_priors_enabled,
            experimental_decision_status = decision.status,
            experimental_decision = decision.decision,
            experimental_summary = decision.summary,
        ),
        decision_record = (;
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            current_manifest_fit_allowed = decision.summary.fit_allowed,
            current_manifest_experimental_keyword_enabled =
                decision.summary.experimental_keyword_enabled,
            public_exposure_support =
                :api_dry_run_satisfies_guarded_entrypoint_boundary,
            interpretation =
                :confirmatory_mgmfrm_guarded_fit_api_dry_run_recorded_entrypoint_enabled,
            required_followup = :mgmfrm_guarded_fit_public_exposure_review,
        ),
        summary = (;
            passed,
            dry_run_only = true,
            publication_or_registration_action = false,
            entrypoint_enabled = true,
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            current_manifest_fit_allowed = decision.summary.fit_allowed,
            current_manifest_experimental_keyword_enabled =
                decision.summary.experimental_keyword_enabled,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            guarded_fit_method_wiring_passed = method.summary_passed,
            guarded_fit_validation_grid_passed = validation.summary_passed,
            validation_grid_all_rows_passed =
                Bool(validation.summary.all_validation_rows_passed),
            method_artifact_contract_satisfied =
                Bool(method.summary.artifact_contract_satisfied),
            method_fit_boundary_checks_passed =
                Bool(method.summary.all_fit_boundary_checks_passed),
            method_experimental_spec_fit_succeeded =
                Bool(method.summary.experimental_spec_fit_succeeded),
            all_fit_boundary_checks_passed,
            non_experimental_fit_rejected =
                Bool(first(check for check in boundary_checks
                    if check.check === :fit_mgmfrm_without_experimental).rejected),
            experimental_spec_fit_succeeded =
                !Bool(first(check for check in boundary_checks
                    if check.check === :fit_experimental_mgmfrm_guarded_enabled).rejected),
            preview_design_experimental_keyword_rejected =
                Bool(first(check for check in boundary_checks
                    if check.check === :fit_preview_design_with_experimental_keyword).rejected),
            unsupported_backend_rejected =
                Bool(first(check for check in boundary_checks
                    if check.check === :fit_experimental_mgmfrm_julia_backend).rejected),
            artifact_contract_satisfied,
            all_required_artifact_fields_recorded =
                contract_review.all_required_fields_recorded,
            all_required_provenance_artifacts_recorded =
                contract_review.all_required_provenance_recorded,
            target_logdensity_finite = target_dry_run.finite_logdensity,
            target_direct_parameters_finite =
                target_dry_run.finite_direct_parameters,
            target_pointwise_loglikelihood_finite =
                target_dry_run.finite_pointwise_loglikelihood,
            target_gradient_diagnostics_passed =
                target_dry_run.gradient_diagnostics.passed,
            n_input_artifacts = length(input_artifacts),
            n_fit_boundary_checks = length(boundary_checks),
            n_gradient_checks = target_dry_run.gradient_diagnostics.n_checked,
            n_failed_gradient_checks = target_dry_run.gradient_diagnostics.n_failed,
            remaining_public_blockers =
                [:mgmfrm_guarded_fit_public_exposure_review_missing],
            recommendation =
                :guarded_entrypoint_api_dry_run_recorded_review_public_exposure_next,
            next_gate = :mgmfrm_guarded_fit_public_exposure_review,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " entrypoint_enabled=", artifact.summary.entrypoint_enabled,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
