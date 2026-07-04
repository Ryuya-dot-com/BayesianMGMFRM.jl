#!/usr/bin/env julia

using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "mgmfrm_guarded_fit_validation_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

module FullArchiveJSON
include(joinpath(@__DIR__, "generate_gmfrm_full_paper_reproduction_archive.jl"))
end

const JSON = FullArchiveJSON

const INPUT_ARTIFACTS = [
    (name = :bridge_oracle,
        path = "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        expected_schema = "bayesianmgmfrm.source_mgmfrm_bridge_logdensity.v1",
        pass_policy = :schema_only),
    (name = :candidate_chain_study,
        path = "test/fixtures/mgmfrm_candidate_chain_study.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_candidate_chain_study.v1",
        pass_policy = :summary_overall_passed),
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
    (name = :report_shape_simulation_grid,
        path = "test/fixtures/mgmfrm_report_shape_simulation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_report_shape_simulation_grid.v1",
        pass_policy = :summary_passed),
    (name = :guarded_fit_method_wiring,
        path = "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_guarded_fit_method_wiring.v1",
        pass_policy = :summary_passed),
]

const PROTOCOL = (;
    protocol_id = "confirmatory_mgmfrm_guarded_fit_validation_grid_v1",
    review_kind = :local_confirmatory_mgmfrm_guarded_fit_validation_grid,
    publication_or_registration_action = false,
    proposed_entrypoint = "fit(spec; experimental = true)",
    entrypoint_enabled = true,
    target = :minimal_confirmatory_mgmfrm_candidate,
    thresholds = (;
        require_bridge_oracle_present = true,
        require_candidate_chain_passed = true,
        require_recovery_smoke_passed = true,
        require_baseline_comparison_passed = true,
        require_sparse_recovery_grid_passed = true,
        require_report_shape_simulation_grid_passed = true,
        require_guarded_fit_method_wiring_passed = true,
        require_sampler_protocol_passed = true,
        require_artifact_contract_satisfied = true,
        require_fit_boundary_checks_passed = true,
        require_experimental_spec_fit_success = true,
        require_entrypoint_enabled = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local confirmatory MGMFRM guarded fit validation-grid artifact.

    This aggregates the existing confirmatory MGMFRM oracle, chain, recovery,
    baseline, sparse-recovery, and guarded method-wiring artifacts. It does not
    publish, register, or promote broad MGMFRM claims.

    Usage:
      julia --project=. scripts/generate_mgmfrm_guarded_fit_validation_grid.jl [--output PATH]
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

function summary_bool(summary::Union{Nothing,AbstractString},
        key::AbstractString,
        default::Bool = false)
    summary === nothing && return default
    value = JSON.json_optional_bool(summary, key)
    return value === missing ? default : Bool(value)
end

function summary_passed(summary::Union{Nothing,AbstractString}, policy::Symbol)
    policy === :schema_only && return true
    summary === nothing && return false
    policy === :summary_passed && return summary_bool(summary, "passed")
    policy === :summary_overall_passed &&
        return summary_bool(summary, "overall_passed")
    throw(ArgumentError("unknown pass policy: $policy"))
end

function artifact_summary(name::Symbol, summary::Union{Nothing,AbstractString})
    name === :baseline_comparison && return (;
        passed = summary_bool(summary, "passed"),
        comparison_executed = summary_bool(summary, "comparison_executed"),
    )
    name === :sparse_recovery_grid && return (;
        passed = summary_bool(summary, "passed"),
        all_validations_passed = summary_bool(summary, "all_validations_passed"),
        all_sampler_passed = summary_bool(summary, "all_sampler_passed"),
    )
    name === :report_shape_simulation_grid && return (;
        passed = summary_bool(summary, "passed"),
        all_report_shapes_passed =
            summary_bool(summary, "all_report_shapes_passed"),
        all_diagnostics_shapes_passed =
            summary_bool(summary, "all_diagnostics_shapes_passed"),
        all_artifact_shapes_passed =
            summary_bool(summary, "all_artifact_shapes_passed"),
        all_waic_shapes_passed =
            summary_bool(summary, "all_waic_shapes_passed"),
        all_posterior_predictive_shapes_passed =
            summary_bool(summary, "all_posterior_predictive_shapes_passed"),
    )
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
    name === :candidate_chain_study && return (;
        overall_passed = summary_bool(summary, "overall_passed"),
    )
    return (; passed = summary_bool(summary, "passed"))
end

function artifact_record(spec)
    path = joinpath(ROOT, spec.path)
    exists = isfile(path)
    text = exists ? read(path, String) : ""
    schema = exists ? JSON.json_string(text, "schema") : ""
    schema_matches = schema == spec.expected_schema
    summary_text = exists ? JSON.json_summary(text) : nothing
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

function validation_rows(records)
    bridge = record_by_name(records, :bridge_oracle)
    chain = record_by_name(records, :candidate_chain_study)
    recovery = record_by_name(records, :recovery_smoke)
    baseline = record_by_name(records, :baseline_comparison)
    sparse = record_by_name(records, :sparse_recovery_grid)
    report_shape = record_by_name(records, :report_shape_simulation_grid)
    method = record_by_name(records, :guarded_fit_method_wiring)
    method_summary = method.summary
    sparse_summary = sparse.summary
    report_shape_summary = report_shape.summary
    baseline_summary = baseline.summary
    return [
        (scenario = :bridge_and_chain_oracles,
            evidence = Bool(bridge.summary_passed) &&
                Bool(chain.summary_passed),
            finding = :bridge_oracle_and_candidate_chain_recorded),
        (scenario = :full_crossed_recovery_smoke,
            evidence = Bool(recovery.summary_passed),
            finding = :recovery_smoke_recorded),
        (scenario = :baseline_model_comparison,
            evidence = Bool(baseline.summary_passed) &&
                Bool(baseline_summary.comparison_executed),
            finding = :baseline_comparison_recorded),
        (scenario = :sparse_connected_recovery_grid,
            evidence = Bool(sparse.summary_passed) &&
                Bool(sparse_summary.all_validations_passed) &&
                Bool(sparse_summary.all_sampler_passed),
            finding = :sparse_connected_grid_recorded),
        (scenario = :report_shape_simulation_grid,
            evidence = Bool(report_shape.summary_passed) &&
                Bool(report_shape_summary.all_report_shapes_passed) &&
                Bool(report_shape_summary.all_diagnostics_shapes_passed) &&
                Bool(report_shape_summary.all_artifact_shapes_passed) &&
                Bool(report_shape_summary.all_waic_shapes_passed) &&
                Bool(report_shape_summary.all_posterior_predictive_shapes_passed),
            finding = :report_diagnostics_artifact_shapes_recorded),
        (scenario = :guarded_method_contract,
            evidence = Bool(method.summary_passed) &&
                Bool(method_summary.sampler_protocol_passed) &&
                Bool(method_summary.artifact_contract_satisfied),
            finding = :guarded_method_contract_satisfied),
        (scenario = :current_guarded_fit_boundary,
            evidence = Bool(method.summary_passed) &&
                Bool(method_summary.all_fit_boundary_checks_passed) &&
                Bool(method_summary.experimental_spec_fit_succeeded) &&
                Bool(method_summary.entrypoint_enabled),
            finding = :guarded_experimental_entrypoint_wired),
    ]
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_guarded_fit_validation_grid.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    rows = validation_rows(records)
    method = record_by_name(records, :guarded_fit_method_wiring)
    sparse = record_by_name(records, :sparse_recovery_grid)
    report_shape = record_by_name(records, :report_shape_simulation_grid)
    all_artifacts_present = all(record -> record.exists, records)
    all_expected_schemas = all(record -> record.schema_matches, records)
    all_inputs_passed = all(record -> record.summary_passed, records)
    all_validation_rows_passed = all(row -> row.evidence, rows)
    no_publication = no_publication_commands()
    passed = all_artifacts_present &&
        all_expected_schemas &&
        all_inputs_passed &&
        all_validation_rows_passed &&
        no_publication &&
        Bool(method.summary.entrypoint_enabled)

    return (;
        schema = "bayesianmgmfrm.mgmfrm_guarded_fit_validation_grid.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :guarded_fit_validation_grid_recorded,
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
        input_artifacts = records,
        validation_rows = rows,
        decision_record = (;
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            public_exposure_support =
                :validation_grid_satisfies_guarded_entrypoint_boundary,
            interpretation =
                :confirmatory_mgmfrm_guarded_fit_validation_grid_recorded_entrypoint_enabled,
            required_followup = :mgmfrm_guarded_fit_api_dry_run,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            entrypoint_enabled = true,
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            all_input_artifacts_present = all_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed = all_inputs_passed,
            all_validation_rows_passed,
            no_publication_commands = no_publication,
            bridge_oracle_present =
                record_by_name(records, :bridge_oracle).summary_passed,
            candidate_chain_study_passed =
                record_by_name(records, :candidate_chain_study).summary_passed,
            recovery_smoke_passed =
                record_by_name(records, :recovery_smoke).summary_passed,
            baseline_comparison_passed =
                record_by_name(records, :baseline_comparison).summary_passed,
            sparse_recovery_grid_passed = sparse.summary_passed,
            report_shape_simulation_grid_passed = report_shape.summary_passed,
            guarded_fit_method_wiring_passed = method.summary_passed,
            sparse_grid_all_validations_passed =
                Bool(sparse.summary.all_validations_passed),
            sparse_grid_all_sampler_passed =
                Bool(sparse.summary.all_sampler_passed),
            report_shape_all_report_shapes_passed =
                Bool(report_shape.summary.all_report_shapes_passed),
            report_shape_all_diagnostics_shapes_passed =
                Bool(report_shape.summary.all_diagnostics_shapes_passed),
            report_shape_all_artifact_shapes_passed =
                Bool(report_shape.summary.all_artifact_shapes_passed),
            report_shape_all_waic_shapes_passed =
                Bool(report_shape.summary.all_waic_shapes_passed),
            report_shape_all_posterior_predictive_shapes_passed =
                Bool(report_shape.summary.all_posterior_predictive_shapes_passed),
            method_sampler_protocol_passed =
                Bool(method.summary.sampler_protocol_passed),
            method_artifact_contract_satisfied =
                Bool(method.summary.artifact_contract_satisfied),
            method_fit_boundary_checks_passed =
                Bool(method.summary.all_fit_boundary_checks_passed),
            method_experimental_spec_fit_succeeded =
                Bool(method.summary.experimental_spec_fit_succeeded),
            n_input_artifacts = length(records),
            n_validation_rows = length(rows),
            n_passed_validation_rows = count(row -> row.evidence, rows),
            remaining_public_blockers =
                [:mgmfrm_guarded_fit_api_dry_run_missing],
            recommendation =
                :guarded_entrypoint_validated_run_api_dry_run_next,
            next_gate = :mgmfrm_guarded_fit_api_dry_run,
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
