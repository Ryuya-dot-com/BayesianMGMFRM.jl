#!/usr/bin/env julia

using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "gmfrm_broader_experimental_exposure_decision_review.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :guarded_exposure_review,
        path = "test/fixtures/gmfrm_guarded_exposure_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_guarded_exposure_review.v1",
        pass_policy = :summary_passed,
        hash_policy = :existence_only_avoids_broader_review_guarded_exposure_cycle),
    (name = :claim_recovery_reproduction_archive,
        path = "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_claim_recovery_reproduction_archive.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :real_data_case_study,
        path = "test/fixtures/gmfrm_real_data_case_study.json",
        expected_schema = "bayesianmgmfrm.gmfrm_real_data_case_study.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_candidate_chain_study,
        path = "test/fixtures/mgmfrm_candidate_chain_study.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_candidate_chain_study.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_recovery_smoke,
        path = "test/fixtures/mgmfrm_recovery_smoke.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_recovery_smoke.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_baseline_comparison,
        path = "test/fixtures/mgmfrm_baseline_comparison.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_baseline_comparison.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_sparse_recovery_grid,
        path = "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_sparse_recovery_grid.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_guarded_fit_method_wiring,
        path = "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_method_wiring.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_guarded_fit_validation_grid,
        path = "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_validation_grid.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_guarded_fit_api_dry_run,
        path = "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_api_dry_run.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_guarded_fit_public_exposure_review,
        path = "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_public_exposure_review.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :prediction_target_and_model_weight_policy,
        path =
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_prediction_target_and_model_weight_policy.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_manual_public_scope_review_for_fit,
        path =
            "test/fixtures/mgmfrm_manual_public_scope_review_for_fit.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_manual_public_scope_review_for_fit.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :dff_estimand_validation_grid,
        path = "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_dff_estimand_validation_grid.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :manuscript_scale_simulation_grid,
        path = "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_manuscript_scale_simulation_grid.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :full_paper_reproduction_archive,
        path = "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_full_paper_reproduction_archive.v1",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_bridge_oracle,
        path = "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        expected_schema = "bayesianmgmfrm.source_mgmfrm_bridge_logdensity.v1",
        pass_policy = :schema_only,
        hash_policy = :sha256),
]

const PROTOCOL = (;
    protocol_id = "gmfrm_broader_experimental_exposure_decision_review_v1",
    review_kind = :local_broader_experimental_exposure_decision,
    publication_or_registration_action = false,
    local_only = true,
    entrypoint_under_review = "fit(spec; experimental = true)",
    decision_target = :broader_generalized_model_exposure,
    thresholds = (;
        require_guarded_exposure_review_passed = true,
        require_claim_recovery_reproduction_archive_passed = true,
        require_real_data_case_study_passed = true,
        require_mgmfrm_bridge_oracle_present = true,
        require_mgmfrm_candidate_chain_study_passed = true,
        require_mgmfrm_recovery_smoke_passed = true,
        require_mgmfrm_baseline_comparison_passed = true,
        require_mgmfrm_sparse_recovery_grid_passed = true,
        require_mgmfrm_guarded_fit_method_wiring_passed = true,
        require_mgmfrm_guarded_fit_validation_grid_passed = true,
        require_mgmfrm_guarded_fit_api_dry_run_passed = true,
        require_mgmfrm_guarded_fit_public_exposure_review_passed = true,
        require_prediction_target_and_model_weight_policy_passed = true,
        require_mgmfrm_manual_public_scope_review_for_fit_passed = true,
        require_dff_estimand_validation_grid_passed = true,
        require_manuscript_scale_simulation_grid_passed = true,
        require_full_paper_reproduction_archive_passed = true,
        require_scalar_guarded_fit_kept_enabled = true,
        require_mgmfrm_fit_kept_internal = true,
        require_broader_generalized_fit_blocked = true,
        require_dff_model_effects_blocked = true,
        require_model_weights_blocked = true,
        require_manuscript_claims_blocked = true,
        require_no_publication_commands = true,
    ),
)

const BLOCKER_ROWS = NamedTuple[]

function usage()
    return """
    Generate the local broader experimental exposure decision review.

    Usage:
      julia --project=. scripts/generate_gmfrm_broader_experimental_exposure_decision_review.jl [--output PATH]
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

function json_optional_summary(text::AbstractString)
    value = json_value_for_key(text, "summary")
    value === nothing && return missing
    return value
end

function summary_passed(name::Symbol, summary)
    ismissing(summary) && return false
    for key in ("passed", "overall_passed", "all_local_evidence_passed")
        value = json_optional_bool(summary, key)
        value === missing || return Bool(value)
    end
    return false
end

function artifact_record(spec)
    path = local_path(spec.path)
    exists = isfile(path)
    text = exists ? read(path, String) : ""
    schema = exists ? json_string(text, "schema") : missing
    schema_matches = exists && schema == spec.expected_schema
    summary = exists ? json_optional_summary(text) : missing
    summary_ok = spec.pass_policy === :schema_only ?
        schema_matches : summary_passed(spec.name, summary)
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        hash_policy = spec.hash_policy,
        sha256 = exists && spec.hash_policy === :sha256 ?
            file_sha256(path) : missing,
        expected_schema = spec.expected_schema,
        schema,
        schema_matches,
        summary_passed = summary_ok,
    )
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function scope_decision_rows(input_records)
    guarded = record_by_name(input_records, :guarded_exposure_review)
    archive = record_by_name(input_records, :claim_recovery_reproduction_archive)
    real_data = record_by_name(input_records, :real_data_case_study)
    mgmfrm_chain = record_by_name(input_records, :mgmfrm_candidate_chain_study)
    mgmfrm_recovery = record_by_name(input_records, :mgmfrm_recovery_smoke)
    mgmfrm_baseline =
        record_by_name(input_records, :mgmfrm_baseline_comparison)
    mgmfrm_sparse =
        record_by_name(input_records, :mgmfrm_sparse_recovery_grid)
    mgmfrm_method =
        record_by_name(input_records, :mgmfrm_guarded_fit_method_wiring)
    mgmfrm_validation =
        record_by_name(input_records, :mgmfrm_guarded_fit_validation_grid)
    mgmfrm_api_dry_run =
        record_by_name(input_records, :mgmfrm_guarded_fit_api_dry_run)
    mgmfrm_public_review =
        record_by_name(input_records,
            :mgmfrm_guarded_fit_public_exposure_review)
    prediction_policy =
        record_by_name(input_records,
            :prediction_target_and_model_weight_policy)
    mgmfrm_scope_review =
        record_by_name(input_records,
            :mgmfrm_manual_public_scope_review_for_fit)
    dff_grid =
        record_by_name(input_records, :dff_estimand_validation_grid)
    manuscript_grid =
        record_by_name(input_records, :manuscript_scale_simulation_grid)
    full_archive =
        record_by_name(input_records, :full_paper_reproduction_archive)
    mgmfrm_bridge = record_by_name(input_records, :mgmfrm_bridge_oracle)
    return [
        (surface = :scalar_gmfrm_guarded_fit,
            current_status = :enabled_guarded_experimental,
            decision = :keep_enabled_guarded_experimental,
            evidence = Bool(guarded.summary_passed) &&
                Bool(archive.summary_passed) &&
                Bool(real_data.summary_passed),
            public_fit = true,
            experimental_public = true,
            next_required_evidence = :none_for_local_guarded_scalar_use),
        (surface = :broader_gmfrm_variants,
            current_status = :not_promoted,
            decision = :keep_blocked,
            evidence = Bool(archive.summary_passed) &&
                Bool(full_archive.summary_passed),
            public_fit = false,
            experimental_public = false,
            next_required_evidence = :broader_generalized_fit_scope_review),
        (surface = :confirmatory_mgmfrm_fit,
            current_status = :enabled_guarded_experimental,
            decision = :enable_guarded_experimental,
            evidence = Bool(mgmfrm_bridge.summary_passed) &&
                Bool(mgmfrm_chain.summary_passed) &&
                Bool(mgmfrm_recovery.summary_passed) &&
                Bool(mgmfrm_baseline.summary_passed) &&
                Bool(mgmfrm_sparse.summary_passed) &&
                Bool(mgmfrm_method.summary_passed) &&
                Bool(mgmfrm_validation.summary_passed) &&
                Bool(mgmfrm_api_dry_run.summary_passed) &&
                Bool(mgmfrm_public_review.summary_passed) &&
                Bool(prediction_policy.summary_passed) &&
                Bool(mgmfrm_scope_review.summary_passed) &&
                Bool(manuscript_grid.summary_passed) &&
                Bool(full_archive.summary_passed),
            public_fit = true,
            experimental_public = true,
            next_required_evidence = :guarded_local_mgmfrm_fit_entrypoint),
        (surface = :dff_model_effects,
            current_status = :validation_only,
            decision = :keep_blocked,
            evidence = Bool(dff_grid.summary_passed),
            public_fit = false,
            experimental_public = false,
            next_required_evidence = :future_dff_model_effect_fit_policy),
        (surface = :loo_or_stacking_model_weights,
            current_status = :prediction_target_policy_recorded,
            decision = :policy_recorded_keep_public_claims_blocked,
            evidence = Bool(prediction_policy.summary_passed) &&
                Bool(mgmfrm_scope_review.summary_passed),
            public_fit = false,
            experimental_public = false,
            next_required_evidence = :future_public_model_weight_claim_review),
        (surface = :manuscript_sparse_mgmfrm_claims,
            current_status = :not_claim_ready,
            decision = :keep_blocked,
            evidence = Bool(manuscript_grid.summary_passed) &&
                Bool(full_archive.summary_passed) &&
                Bool(prediction_policy.summary_passed) &&
                Bool(mgmfrm_scope_review.summary_passed),
            public_fit = false,
            experimental_public = false,
            next_required_evidence = :guarded_local_mgmfrm_fit_entrypoint),
    ]
end

function risk_rows()
    return [
        (risk = :high_variance_waic,
            decision = :do_not_use_same_data_waic_as_public_weight_claim,
            mitigation = :exact_kfold_refit_recorded_but_weights_not_promoted),
        (risk = :high_pareto_k,
            decision = :do_not_promote_raw_importance_loo_weights,
            mitigation = :pareto_k_screen_and_kfold_refit_recorded),
        (risk = :compact_real_data_scope,
            decision = :do_not_generalize_to_broad_workflow_claim,
            mitigation = :recorded_as_case_study_not_population_evidence),
        (risk = :mgmfrm_sparse_overclaim,
            decision = :keep_mgmfrm_internal,
            mitigation = :require_baseline_and_sparse_recovery_grids),
        (risk = :dff_fairness_overclaim,
            decision = :keep_dff_as_validation_only,
            mitigation = :require_predeclared_estimands_and_practical_scale_checks),
    ]
end

function no_publication_commands()
    command = "julia --project=. scripts/generate_gmfrm_broader_experimental_exposure_decision_review.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    decisions = scope_decision_rows(input_records)
    guarded = record_by_name(input_records, :guarded_exposure_review)
    archive = record_by_name(input_records, :claim_recovery_reproduction_archive)
    real_data = record_by_name(input_records, :real_data_case_study)
    mgmfrm_chain = record_by_name(input_records, :mgmfrm_candidate_chain_study)
    mgmfrm_recovery = record_by_name(input_records, :mgmfrm_recovery_smoke)
    mgmfrm_baseline =
        record_by_name(input_records, :mgmfrm_baseline_comparison)
    mgmfrm_sparse =
        record_by_name(input_records, :mgmfrm_sparse_recovery_grid)
    mgmfrm_method =
        record_by_name(input_records, :mgmfrm_guarded_fit_method_wiring)
    mgmfrm_validation =
        record_by_name(input_records, :mgmfrm_guarded_fit_validation_grid)
    mgmfrm_api_dry_run =
        record_by_name(input_records, :mgmfrm_guarded_fit_api_dry_run)
    mgmfrm_public_review =
        record_by_name(input_records,
            :mgmfrm_guarded_fit_public_exposure_review)
    prediction_policy =
        record_by_name(input_records,
            :prediction_target_and_model_weight_policy)
    mgmfrm_scope_review =
        record_by_name(input_records,
            :mgmfrm_manual_public_scope_review_for_fit)
    dff_grid =
        record_by_name(input_records, :dff_estimand_validation_grid)
    manuscript_grid =
        record_by_name(input_records, :manuscript_scale_simulation_grid)
    full_archive =
        record_by_name(input_records, :full_paper_reproduction_archive)
    mgmfrm_bridge = record_by_name(input_records, :mgmfrm_bridge_oracle)
    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_required_inputs_passed = all(record -> record.summary_passed, input_records)
    scalar_guarded_fit_allowed =
        Bool(first(row for row in decisions
            if row.surface === :scalar_gmfrm_guarded_fit).public_fit)
    broader_generalized_fit_allowed =
        any(row -> row.surface in (:broader_gmfrm_variants,) && row.public_fit,
            decisions)
    mgmfrm_fit_allowed =
        Bool(first(row for row in decisions
            if row.surface === :confirmatory_mgmfrm_fit).public_fit)
    dff_model_effects_allowed =
        Bool(first(row for row in decisions
            if row.surface === :dff_model_effects).public_fit)
    model_weights_allowed =
        Bool(first(row for row in decisions
            if row.surface === :loo_or_stacking_model_weights).public_fit)
    manuscript_claims_allowed =
        Bool(first(row for row in decisions
            if row.surface === :manuscript_sparse_mgmfrm_claims).public_fit)
    no_publication = no_publication_commands()
    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_required_inputs_passed &&
        scalar_guarded_fit_allowed &&
        !broader_generalized_fit_allowed &&
        mgmfrm_fit_allowed &&
        !dff_model_effects_allowed &&
        !model_weights_allowed &&
        !manuscript_claims_allowed &&
        no_publication
    return (;
        schema =
            "bayesianmgmfrm.gmfrm_broader_experimental_exposure_decision_review.v1",
        family = :gmfrm,
        scope = :broader_generalized_exposure_decision,
        status = :broader_experimental_exposure_decision_review_recorded,
        decision = :keep_guarded_scalar_gmfrm_and_confirmatory_mgmfrm_only,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        broader_public_fit = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        input_artifacts = input_records,
        scope_decision_rows = decisions,
        risk_rows = risk_rows(),
        blocker_rows = BLOCKER_ROWS,
        cycle_break_references = [
            (artifact = "test/fixtures/gmfrm_guarded_exposure_review.json",
                reason = :avoid_broader_review_guarded_exposure_hash_cycle,
                hash_policy = :existence_only),
        ],
        decision_record = (;
            scalar_guarded_fit_allowed,
            mgmfrm_fit_allowed,
            broader_generalized_fit_allowed,
            public_exposure_support =
                :guarded_scalar_gmfrm_and_fixed_q_mgmfrm_only,
            interpretation =
                :broader_exposure_review_recorded_guarded_confirmatory_mgmfrm_enabled_keep_broader_claims_blocked,
            required_followup = :guarded_local_mgmfrm_fit_entrypoint,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_required_inputs_passed,
            guarded_exposure_review_passed = Bool(guarded.summary_passed),
            claim_recovery_reproduction_archive_passed =
                Bool(archive.summary_passed),
            real_data_case_study_passed = Bool(real_data.summary_passed),
            mgmfrm_bridge_oracle_present = Bool(mgmfrm_bridge.summary_passed),
            mgmfrm_candidate_chain_study_passed =
                Bool(mgmfrm_chain.summary_passed),
            mgmfrm_recovery_smoke_passed =
                Bool(mgmfrm_recovery.summary_passed),
            mgmfrm_baseline_comparison_passed =
                Bool(mgmfrm_baseline.summary_passed),
            mgmfrm_sparse_recovery_grid_passed =
                Bool(mgmfrm_sparse.summary_passed),
            mgmfrm_guarded_fit_method_wiring_passed =
                Bool(mgmfrm_method.summary_passed),
            mgmfrm_guarded_fit_validation_grid_passed =
                Bool(mgmfrm_validation.summary_passed),
            mgmfrm_guarded_fit_api_dry_run_passed =
                Bool(mgmfrm_api_dry_run.summary_passed),
            mgmfrm_guarded_fit_public_exposure_review_passed =
                Bool(mgmfrm_public_review.summary_passed),
            prediction_target_and_model_weight_policy_passed =
                Bool(prediction_policy.summary_passed),
            mgmfrm_manual_public_scope_review_for_fit_passed =
                Bool(mgmfrm_scope_review.summary_passed),
            dff_estimand_validation_grid_passed =
                Bool(dff_grid.summary_passed),
            manuscript_scale_simulation_grid_passed =
                Bool(manuscript_grid.summary_passed),
            full_paper_reproduction_archive_passed =
                Bool(full_archive.summary_passed),
            n_input_artifacts = length(input_records),
            n_scope_decisions = length(decisions),
            n_risk_rows = length(risk_rows()),
            n_blockers = length(BLOCKER_ROWS),
            scalar_guarded_fit_allowed,
            broader_generalized_fit_allowed,
            mgmfrm_fit_allowed,
            dff_model_effects_allowed,
            model_weights_allowed,
            manuscript_claims_allowed,
            no_publication_commands = no_publication,
            remaining_public_blockers =
                [row.blocker for row in BLOCKER_ROWS],
            recommendation =
                :manual_scope_review_recorded_keep_guarded_scalar_and_confirmatory_mgmfrm_only,
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
        " decision=", artifact.decision,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
