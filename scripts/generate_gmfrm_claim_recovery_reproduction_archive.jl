#!/usr/bin/env julia

using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "gmfrm_claim_recovery_reproduction_archive.json")

include(joinpath(@__DIR__, "local_json.jl"))

const FIXTURE_SPECS = [
    (name = :candidate_chain_study,
        path = "test/fixtures/gmfrm_candidate_chain_study.json",
        expected_schema = "bayesianmgmfrm.gmfrm_candidate_chain_study.v1",
        generator = "scripts/generate_gmfrm_candidate_chain_study.jl",
        env_var = "MFRM_GMFRM_CANDIDATE_CHAIN_STUDY_FIXTURE"),
    (name = :stress_chain_grid,
        path = "test/fixtures/gmfrm_stress_chain_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_stress_chain_grid.v1",
        generator = "scripts/generate_gmfrm_stress_chain_grid.jl",
        env_var = "MFRM_GMFRM_STRESS_CHAIN_GRID_FIXTURE"),
    (name = :recovery_smoke_study,
        path = "test/fixtures/gmfrm_recovery_smoke.json",
        expected_schema = "bayesianmgmfrm.gmfrm_recovery_smoke.v1",
        generator = "scripts/generate_gmfrm_recovery_smoke.jl",
        env_var = "MFRM_GMFRM_RECOVERY_SMOKE_FIXTURE"),
    (name = :baseline_comparison,
        path = "test/fixtures/gmfrm_baseline_comparison.json",
        expected_schema = "bayesianmgmfrm.gmfrm_baseline_comparison.v1",
        generator = "scripts/generate_gmfrm_baseline_comparison.jl",
        env_var = "MFRM_GMFRM_BASELINE_COMPARISON_FIXTURE"),
    (name = :baseline_calibration_grid,
        path = "test/fixtures/gmfrm_baseline_calibration_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_baseline_calibration_grid.v1",
        generator = "scripts/generate_gmfrm_baseline_calibration_grid.jl",
        env_var = "MFRM_GMFRM_BASELINE_CALIBRATION_GRID_FIXTURE"),
    (name = :interval_decision_grid,
        path = "test/fixtures/gmfrm_interval_decision_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_interval_decision_grid.v1",
        generator = "scripts/generate_gmfrm_interval_decision_grid.jl",
        env_var = "MFRM_GMFRM_INTERVAL_DECISION_GRID_FIXTURE"),
    (name = :sparse_design_grid,
        path = "test/fixtures/gmfrm_sparse_design_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_sparse_design_grid.v1",
        generator = "scripts/generate_gmfrm_sparse_design_grid.jl",
        env_var = "MFRM_GMFRM_SPARSE_DESIGN_GRID_FIXTURE"),
    (name = :waic_influence_review,
        path = "test/fixtures/gmfrm_waic_influence_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_waic_influence_review.v1",
        generator = "scripts/generate_gmfrm_waic_influence_review.jl",
        env_var = "MFRM_GMFRM_WAIC_INFLUENCE_REVIEW_FIXTURE"),
    (name = :psis_loo_review,
        path = "test/fixtures/gmfrm_psis_loo_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_psis_loo_review.v1",
        generator = "scripts/generate_gmfrm_psis_loo_review.jl",
        env_var = "MFRM_GMFRM_PSIS_LOO_REVIEW_FIXTURE"),
    (name = :exact_loo_or_kfold_review,
        path = "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_exact_loo_or_kfold_review.v1",
        generator = "scripts/generate_gmfrm_exact_loo_or_kfold_review.jl",
        env_var = "MFRM_GMFRM_EXACT_LOO_OR_KFOLD_REVIEW_FIXTURE"),
    (name = :guarded_fit_method_wiring,
        path = "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
        expected_schema = "bayesianmgmfrm.gmfrm_guarded_fit_method_wiring.v1",
        generator = "scripts/generate_gmfrm_guarded_fit_method_wiring.jl",
        env_var = "MFRM_GMFRM_GUARDED_FIT_METHOD_WIRING_FIXTURE"),
    (name = :experimental_fit_validation_grid,
        path = "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_experimental_fit_validation_grid.v1",
        generator = "scripts/generate_gmfrm_experimental_fit_validation_grid.jl",
        env_var = "MFRM_GMFRM_EXPERIMENTAL_FIT_VALIDATION_GRID_FIXTURE"),
    (name = :posterior_predictive_grid,
        path = "test/fixtures/gmfrm_posterior_predictive_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_posterior_predictive_grid.v1",
        generator = "scripts/generate_gmfrm_posterior_predictive_grid.jl",
        env_var = "MFRM_GMFRM_POSTERIOR_PREDICTIVE_GRID_FIXTURE"),
    (name = :sparse_pathology_recovery_grid,
        path = "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_sparse_pathology_recovery_grid.v1",
        generator = "scripts/generate_gmfrm_sparse_pathology_recovery_grid.jl",
        env_var = "MFRM_GMFRM_SPARSE_PATHOLOGY_RECOVERY_GRID_FIXTURE"),
    (name = :prior_likelihood_sensitivity_grid,
        path = "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_prior_likelihood_sensitivity_grid.v1",
        generator = "scripts/generate_gmfrm_prior_likelihood_sensitivity_grid.jl",
        env_var = "MFRM_GMFRM_PRIOR_LIKELIHOOD_SENSITIVITY_GRID_FIXTURE"),
    (name = :real_data_case_study,
        path = "test/fixtures/gmfrm_real_data_case_study.json",
        expected_schema = "bayesianmgmfrm.gmfrm_real_data_case_study.v1",
        generator = "scripts/generate_gmfrm_real_data_case_study.jl",
        env_var = "MFRM_GMFRM_REAL_DATA_CASE_STUDY_FIXTURE"),
    (name = :guarded_fit_api_dry_run,
        path = "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        expected_schema = "bayesianmgmfrm.gmfrm_guarded_fit_api_dry_run.v1",
        generator = "scripts/generate_gmfrm_guarded_fit_api_dry_run.jl",
        env_var = "MFRM_GMFRM_GUARDED_FIT_API_DRY_RUN_FIXTURE"),
    (name = :tam_direct_agreement_multireplication,
        path =
            "test/fixtures/mgmfrm_tam_direct_agreement_multireplication.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_tam_direct_agreement_multireplication.v1",
        generator =
            "scripts/generate_mgmfrm_tam_direct_agreement_multireplication.jl",
        generation_command =
            "julia --project=. scripts/generate_mgmfrm_tam_direct_agreement_multireplication.jl --aggregate-only",
        env_var =
            "MFRM_MGMFRM_TAM_DIRECT_AGREEMENT_MULTIREPLICATION_FIXTURE",
        evidence_scope = :mfrm_tam_overlap_nontransfer),
    (name = :tam_direct_agreement_raw_archive_audit,
        path =
            "test/fixtures/mgmfrm_tam_direct_agreement_raw_archive_audit.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_tam_direct_agreement_raw_archive_audit.v1",
        generator =
            "scripts/generate_mgmfrm_tam_direct_agreement_raw_archive_audit.jl",
        generation_command =
            "julia --project=. scripts/generate_mgmfrm_tam_direct_agreement_raw_archive_audit.jl",
        env_var =
            "MFRM_MGMFRM_TAM_DIRECT_AGREEMENT_RAW_ARCHIVE_AUDIT_FIXTURE",
        evidence_scope = :mfrm_tam_overlap_nontransfer),
    (name = :tam_direct_agreement_post_execution_review_packet,
        path =
            "test/fixtures/mgmfrm_tam_direct_agreement_post_execution_review_packet.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_tam_direct_agreement_post_execution_review_packet.v1",
        generator =
            "scripts/generate_mgmfrm_tam_direct_agreement_post_execution_review_packet.jl",
        generation_command =
            "julia --project=. scripts/generate_mgmfrm_tam_direct_agreement_post_execution_review_packet.jl",
        env_var =
            "MFRM_MGMFRM_TAM_DIRECT_AGREEMENT_POST_EXECUTION_REVIEW_PACKET_FIXTURE",
        evidence_scope = :mfrm_tam_overlap_nontransfer),
    (name = :guarded_exposure_review,
        path = "test/fixtures/gmfrm_guarded_exposure_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_guarded_exposure_review.v1",
        generator = "scripts/generate_gmfrm_guarded_exposure_review.jl",
        env_var = "MFRM_GMFRM_GUARDED_EXPOSURE_REVIEW_FIXTURE"),
]

const CODE_AND_DOC_PATHS = [
    "Project.toml",
    "README.md",
    "NEWS.md",
    "ROADMAP.md",
    "src/facet_workflow.jl",
    "src/bayesian_fit.jl",
    "test/runtests.jl",
    "test/fixtures/README.md",
    "docs/src/fitting.md",
    "docs/src/model-equations.md",
    "docs/src/roadmap.md",
    "scripts/local_json.jl",
    "scripts/pre_registration_gate.jl",
    "scripts/generate_mgmfrm_tam_direct_agreement_multireplication.jl",
    "scripts/generate_mgmfrm_tam_direct_agreement_raw_archive_audit.jl",
    "scripts/generate_mgmfrm_tam_direct_agreement_post_execution_review_packet.jl",
    "scripts/generate_gmfrm_claim_recovery_reproduction_archive.jl",
]

const EXTERNAL_SOURCE_PATHS = [
    "../Simulation/data/writing_long.csv",
    "../Simulation/data/speaking_long.csv",
]

const VERIFICATION_COMMANDS = [
    (name = :package_tests,
        command = "julia --project=. -e 'import Pkg; Pkg.test()'",
        execution = :required_before_claim_use),
    (name = :documentation_build,
        command = "julia --project=docs docs/make.jl",
        execution = :required_before_claim_use),
    (name = :local_pre_registration_gate,
        command =
            "julia --startup-file=no scripts/pre_registration_gate.jl --skip-tests --skip-docs --skip-public-wording",
        execution = :required_before_claim_use),
    (name = :whitespace_check,
        command = "git diff --check",
        execution = :required_before_claim_use),
]

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_claim_recovery_reproduction_archive_v1",
    review_kind = :local_claim_recovery_reproduction_archive,
    publication_or_registration_action = false,
    local_only = true,
    target = :guarded_experimental_scalar_gmfrm_claim_support,
    archive_scope = :fast_and_full_local_reproduction_manifest,
    thresholds = (;
        require_all_fixture_artifacts_present = true,
        require_all_expected_schemas = true,
        require_all_fixture_summaries_passed = true,
        require_all_generator_scripts_present = true,
        require_all_code_doc_references_present = true,
        require_all_external_sources_present = true,
        require_all_commands_local_only = true,
        require_no_publication_commands = true,
        require_guarded_exposure_review_passed = true,
        require_real_data_case_study_passed = true,
    ),
)

function usage()
    return """
    Generate the local scalar GMFRM claim-level recovery/reproduction archive.

    Usage:
      julia --project=. scripts/generate_gmfrm_claim_recovery_reproduction_archive.jl [--output PATH]
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

function local_path(path::AbstractString)
    return normpath(joinpath(ROOT, path))
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
    error("JSON field `$key` is not boolean or null")
end

function json_summary(text::AbstractString)
    return required_value(text, "summary")
end

function summary_passed(name::Symbol, summary::AbstractString)
    for key in ("passed", "overall_passed")
        value = json_optional_bool(summary, key)
        value === missing || return Bool(value)
    end
    if name === :guarded_exposure_review
        return Bool(json_optional_bool(summary, "all_local_evidence_passed"))
    end
    return false
end

function guarded_exposure_passed(summary::AbstractString)
    value = json_optional_bool(summary, "all_local_evidence_passed")
    return value === missing ? false : Bool(value)
end

function real_data_passed(summary::AbstractString)
    value = json_optional_bool(summary, "passed")
    return value === missing ? false : Bool(value)
end

function artifact_record(spec)
    path = local_path(spec.path)
    exists = isfile(path)
    text = exists ? read(path, String) : ""
    schema = exists ? json_string(text, "schema") : missing
    summary = exists ? json_summary(text) : ""
    schema_matches = exists && schema == spec.expected_schema
    hash_policy = spec.name === :guarded_exposure_review ?
        :existence_only_avoids_archive_review_hash_cycle : :sha256
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        hash_policy,
        sha256 = exists && hash_policy === :sha256 ? file_sha256(path) : missing,
        expected_schema = spec.expected_schema,
        schema,
        schema_matches,
        generator = spec.generator,
        generation_command = hasproperty(spec, :generation_command) ?
            spec.generation_command : "julia --project=. $(spec.generator)",
        env_var = spec.env_var,
        evidence_scope = hasproperty(spec, :evidence_scope) ?
            spec.evidence_scope : :scalar_gmfrm_claim_archive,
        generator_exists = isfile(local_path(spec.generator)),
        summary_passed = exists ? summary_passed(spec.name, summary) : false,
    )
end

function source_record(path)
    resolved = local_path(path)
    return (;
        path,
        exists = isfile(resolved),
        sha256 = isfile(resolved) ? file_sha256(resolved) : missing,
        hash_policy = :sha256_when_available,
        line_count = isfile(resolved) ? countlines(resolved) : missing,
    )
end

function code_doc_record(path)
    resolved = local_path(path)
    return (;
        path,
        exists = isfile(resolved),
        sha256 = isfile(resolved) ? file_sha256(resolved) : missing,
    )
end

function command_is_local_only(command::AbstractString)
    banned = [
        "git push",
        "gh release",
        "gh repo",
        "Registrator",
        "Pkg.register",
        "registry add",
        "publish",
    ]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function command_record(spec)
    return (;
        spec...,
        local_only = command_is_local_only(spec.command),
    )
end

function archive_artifact()
    fixture_records = [artifact_record(spec) for spec in FIXTURE_SPECS]
    source_records = [source_record(path) for path in EXTERNAL_SOURCE_PATHS]
    code_doc_records = [code_doc_record(path) for path in CODE_AND_DOC_PATHS]
    verification_commands = [command_record(spec) for spec in VERIFICATION_COMMANDS]
    supporting_records = [
        record for record in fixture_records
        if record.artifact !== :guarded_exposure_review
    ]
    full_regeneration_commands = NamedTuple[]
    for record in supporting_records
        push!(full_regeneration_commands, (;
            step = length(full_regeneration_commands) + 1,
            artifact = record.artifact,
            command = record.generation_command,
            local_only = command_is_local_only(record.generation_command),
        ))
    end
    archive_command =
        "julia --project=. scripts/generate_gmfrm_claim_recovery_reproduction_archive.jl"
    push!(full_regeneration_commands, (;
        step = length(full_regeneration_commands) + 1,
        artifact = :claim_recovery_reproduction_archive,
        command = archive_command,
        local_only = command_is_local_only(archive_command),
    ))
    guarded_record = only(record for record in fixture_records
        if record.artifact === :guarded_exposure_review)
    push!(full_regeneration_commands, (;
        step = length(full_regeneration_commands) + 1,
        artifact = guarded_record.artifact,
        command = guarded_record.generation_command,
        local_only = command_is_local_only(guarded_record.generation_command),
    ))

    guarded_review = only(record for record in fixture_records
        if record.artifact === :guarded_exposure_review)
    real_data = only(record for record in fixture_records
        if record.artifact === :real_data_case_study)
    tam_result = only(record for record in fixture_records
        if record.artifact === :tam_direct_agreement_multireplication)
    tam_audit = only(record for record in fixture_records
        if record.artifact === :tam_direct_agreement_raw_archive_audit)
    tam_post_packet = only(record for record in fixture_records
        if record.artifact ===
            :tam_direct_agreement_post_execution_review_packet)
    tam_result_summary = json_summary(read(local_path(tam_result.path), String))
    tam_audit_summary = json_summary(read(local_path(tam_audit.path), String))
    tam_post_summary =
        json_summary(read(local_path(tam_post_packet.path), String))
    tam_direct_primary_gate_passed = Bool(json_optional_bool(
        tam_result_summary, "primary_direct_gate_passed"))
    tam_raw_archive_integrity_passed = Bool(json_optional_bool(
        tam_audit_summary, "archive_integrity_passed"))
    tam_post_packet_integrity_passed = Bool(json_optional_bool(
        tam_post_summary, "packet_integrity_passed"))
    tam_independent_review_completed = Bool(json_optional_bool(
        tam_post_summary, "independent_review_completed"))
    tam_pre_execution_exact_input_lineage = Bool(json_optional_bool(
        tam_post_summary, "pre_execution_packet_exact_input_lineage"))

    all_fixture_artifacts_present = all(record -> record.exists, fixture_records)
    all_expected_schemas = all(record -> record.schema_matches, fixture_records)
    all_fixture_summaries_passed =
        all(record -> record.summary_passed, fixture_records)
    all_generator_scripts_present =
        all(record -> record.generator_exists, fixture_records)
    all_code_doc_references_present =
        all(record -> record.exists, code_doc_records)
    all_external_sources_present = all(record -> record.exists, source_records)
    all_commands_local_only =
        all(record -> record.local_only, verification_commands) &&
        all(row -> row.local_only, full_regeneration_commands)
    no_publication_commands = all_commands_local_only
    guarded_exposure_review_passed = guarded_review.summary_passed
    real_data_case_study_passed = real_data.summary_passed

    passed = all_fixture_artifacts_present &&
        all_expected_schemas &&
        all_fixture_summaries_passed &&
        all_generator_scripts_present &&
        all_code_doc_references_present &&
        all_external_sources_present &&
        all_commands_local_only &&
        no_publication_commands &&
        guarded_exposure_review_passed &&
        real_data_case_study_passed

    return (;
        schema =
            "bayesianmgmfrm.gmfrm_claim_recovery_reproduction_archive.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :claim_recovery_reproduction_archive_recorded,
        decision = :keep_guarded_experimental,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        fixture_records,
        source_records,
        code_doc_records,
        full_regeneration_commands,
        verification_commands,
        cycle_break_references = [
            (artifact = "test/fixtures/gmfrm_guarded_exposure_review.json",
                reason = :avoid_guarded_review_archive_hash_cycle,
                hash_policy = :existence_only),
        ],
        decision_record = (;
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            public_exposure_support =
                :satisfied_for_broader_experimental_exposure_decision_followup,
            interpretation =
                :claim_level_recovery_reproduction_archive_recorded,
            tam_direct_evidence_scope = :mfrm_tam_overlap_nontransfer,
            tam_direct_evidence_transfers_to_scalar_gmfrm = false,
            tam_independent_review_completed,
            required_followup = :broader_experimental_exposure_decision_review,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            n_fixture_artifacts = length(fixture_records),
            n_source_records = length(source_records),
            n_code_doc_records = length(code_doc_records),
            n_full_regeneration_commands = length(full_regeneration_commands),
            n_verification_commands = length(verification_commands),
            all_fixture_artifacts_present,
            all_expected_schemas,
            all_fixture_summaries_passed,
            all_generator_scripts_present,
            all_code_doc_references_present,
            all_external_sources_present,
            all_commands_local_only,
            no_publication_commands,
            guarded_exposure_review_passed,
            real_data_case_study_passed,
            tam_direct_primary_gate_passed,
            tam_raw_archive_integrity_passed,
            tam_post_packet_integrity_passed,
            tam_independent_review_completed,
            tam_pre_execution_exact_input_lineage,
            tam_direct_evidence_transfers_to_scalar_gmfrm = false,
            remaining_public_blockers =
                [
                    :broader_experimental_exposure_decision_review_missing,
                    :tam_direct_independent_review_pending,
                    :tam_pre_execution_refinement_lineage_adjudication_pending,
                ],
            recommendation =
                :keep_guarded_experimental_until_broader_exposure_decision_review,
            next_gate = :broader_experimental_exposure_decision_review,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = archive_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " fixtures=", artifact.summary.n_fixture_artifacts,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
