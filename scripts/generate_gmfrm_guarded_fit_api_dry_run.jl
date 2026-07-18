#!/usr/bin/env julia

using SHA
using TOML

import BayesianMGMFRM
import LogDensityProblems

module GMFRMRecoverySmoke
include(joinpath(@__DIR__, "generate_gmfrm_recovery_smoke.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_guarded_fit_api_dry_run.json")

include(joinpath(@__DIR__, "local_json.jl"))

const SMOKE = GMFRMRecoverySmoke

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_guarded_fit_api_dry_run_v1",
    review_kind = :local_guarded_fit_api_contract_dry_run,
    publication_or_registration_action = false,
    dry_run_only = true,
    proposed_entrypoint = "fit(spec; experimental = true)",
    entrypoint_enabled = false,
    superseded_by_guarded_fit_method_wiring = true,
    superseded_by_experimental_fit_validation_grid = true,
    superseded_by_posterior_predictive_grid = true,
    superseded_by_sparse_pathology_recovery_grid = true,
    superseded_by_prior_likelihood_sensitivity_grid = true,
    superseded_by_real_data_case_study = true,
    superseded_by_claim_recovery_reproduction_archive = true,
    superseded_by_broader_experimental_exposure_decision_review = true,
    public_target_label = :guarded_scalar_gmfrm_logdensity,
    public_target_description = "guarded scalar GMFRM log density",
    internal_target_constructor = :_gmfrm_promotion_candidate_logdensity,
    internal_diagnostics_constructor = :_gmfrm_promotion_candidate_diagnostics,
    target_constructor = :_gmfrm_promotion_candidate_logdensity,
    diagnostics_constructor = :_gmfrm_promotion_candidate_diagnostics,
    decision_rules = (;
        require_specified_only_public_fit_rejection = true,
        require_preview_design_experimental_keyword_rejection = true,
        require_artifact_contract_recorded = true,
        require_required_fields_recorded = true,
        require_required_provenance_recorded = true,
        require_file_evidence_present = true,
        require_finite_internal_target = true,
        require_gradient_diagnostics_passed = true,
        guarded_fit_method_wiring_required_before_public_exposure = true,
    ),
)

function usage()
    return """
    Generate the local scalar GMFRM guarded fit API dry-run artifact.

    This dry-run records the proposed guarded entrypoint and validates the
    artifact contract locally. It does not enable fitting, publish, register,
    or expose a public experimental API.

    Usage:
      julia --project=. scripts/generate_gmfrm_guarded_fit_api_dry_run.jl [--output PATH]
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

function dry_run_data_and_spec()
    table = SMOKE.placeholder_table()
    data = SMOKE.facet_data(table)
    spec = BayesianMGMFRM.mfrm_spec(data; family = :gmfrm, discrimination = :rater)
    preview = BayesianMGMFRM.getdesign(spec; preview = true)
    return (; table, data, spec, preview)
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

function path_without_anchor(value::AbstractString)
    parts = split(value, '#'; limit = 2)
    return first(parts)
end

function artifact_reference_record(artifact)
    if artifact isa AbstractString
        if artifact == "test/fixtures/gmfrm_guarded_fit_api_dry_run.json"
            return (;
                artifact,
                reference_kind = :current_artifact_self,
                exists = true,
                sha256 = missing,
            )
        end
        if artifact == "test/fixtures/gmfrm_guarded_exposure_review.json"
            return (;
                artifact,
                reference_kind = :review_cycle_break,
                exists = isfile(joinpath(ROOT, artifact)),
                sha256 = missing,
            )
        end
        if artifact == "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json"
            return (;
                artifact,
                reference_kind = :claim_archive_cycle_break,
                exists = isfile(joinpath(ROOT, artifact)),
                sha256 = missing,
            )
        end
        if artifact == "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json"
            return (;
                artifact,
                reference_kind = :broader_review_cycle_break,
                exists = isfile(joinpath(ROOT, artifact)),
                sha256 = missing,
            )
        end
        if artifact == "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json"
            return (;
                artifact,
                reference_kind = :manuscript_grid_cycle_break,
                exists = isfile(joinpath(ROOT, artifact)),
                sha256 = missing,
            )
        end
        if artifact == "test/fixtures/gmfrm_full_paper_reproduction_archive.json"
            return (;
                artifact,
                reference_kind = :full_archive_cycle_break,
                exists = isfile(joinpath(ROOT, artifact)),
                sha256 = missing,
            )
        end
        path = path_without_anchor(artifact)
        local_path = joinpath(ROOT, path)
        exists = isfile(local_path)
        return (;
            artifact,
            reference_kind = :local_file,
            exists,
            sha256 = exists ? file_sha256(local_path) : missing,
        )
    end
    return (;
        artifact,
        reference_kind = :manifest_internal,
        exists = true,
        sha256 = missing,
    )
end

function evidence_reference_rows(decision)
    rows = NamedTuple[]
    for row in decision.evidence_rows
        reference = artifact_reference_record(row.artifact)
        push!(rows, (;
            evidence = row.evidence,
            status = row.status,
            artifact = row.artifact,
            reference_kind = reference.reference_kind,
            exists = reference.exists,
            sha256 = reference.sha256,
        ))
    end
    return rows
end

function contract_review_record(contract)
    required_field_names = [row.field for row in contract.required_fields]
    required_provenance = [row.artifact for row in contract.provenance_rows]
    return (;
        schema = contract.schema,
        status = contract.status,
        public_fit = contract.public_fit,
        experimental_public = contract.experimental_public,
        artifact_kind = contract.artifact_kind,
        required_fields = contract.required_fields,
        provenance_rows = contract.provenance_rows,
        required_field_names,
        required_provenance,
        n_required_fields = length(contract.required_fields),
        n_required_provenance_artifacts = length(contract.provenance_rows),
        all_required_fields_recorded =
            all(row -> row.status === :required, contract.required_fields),
        all_required_provenance_recorded =
            all(row -> row.status === :required, contract.provenance_rows),
    )
end

function target_dry_run_record(preview)
    target = BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(preview)
    raw_initial = BayesianMGMFRM.initial_params(target)
    logdensity = LogDensityProblems.logdensity(target, raw_initial)
    diagnostics = BayesianMGMFRM._gmfrm_promotion_candidate_diagnostics(
        target,
        raw_initial;
        finite_difference_coords = collect(1:min(6, length(raw_initial))),
    )
    return (;
        public_target_label = PROTOCOL.public_target_label,
        public_target_description = PROTOCOL.public_target_description,
        internal_target_constructor = PROTOCOL.internal_target_constructor,
        internal_diagnostics_constructor = PROTOCOL.internal_diagnostics_constructor,
        target = :_gmfrm_promotion_candidate_logdensity,
        diagnostics = :_gmfrm_promotion_candidate_diagnostics,
        n_raw_parameters = LogDensityProblems.dimension(target),
        n_checked_gradient_coordinates = diagnostics.summary.n_checked,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        finite_logdensity = isfinite(logdensity),
        logdensity,
        diagnostics_flag = diagnostics.summary.flag,
        diagnostics_passed = diagnostics.summary.passed,
        n_failed_gradient_checks = diagnostics.summary.n_failed,
        max_abs_error = diagnostics.summary.max_abs_error,
        max_tolerance = diagnostics.summary.max_tolerance,
    )
end

function build_artifact()
    context = dry_run_data_and_spec()
    manifest = BayesianMGMFRM.model_manifest(context.preview)
    candidate = manifest.design.raw_parameterization.promotion_candidate
    decision = candidate.experimental_public_api
    contract_review = contract_review_record(decision.fit_artifact_contract)
    evidence_rows = evidence_reference_rows(decision)
    target_dry_run = target_dry_run_record(context.preview)
    public_fit_rejection = rejection_check(:fit_specified_only_gmfrm) do
        BayesianMGMFRM.fit(context.spec; ndraws = 1, warmup = 0)
    end
    experimental_keyword_rejection =
        rejection_check(:fit_preview_design_with_experimental_keyword) do
            BayesianMGMFRM.fit(
                context.preview;
                experimental = true,
                ndraws = 1,
                warmup = 0,
            )
        end
    all_file_evidence_present =
        all(row -> row.reference_kind === :manifest_internal ||
            row.reference_kind === :current_artifact_self ||
            row.reference_kind === :review_cycle_break ||
            row.reference_kind === :claim_archive_cycle_break ||
            row.reference_kind === :broader_review_cycle_break ||
            row.reference_kind === :manuscript_grid_cycle_break ||
            row.reference_kind === :full_archive_cycle_break ||
            Bool(row.exists), evidence_rows)
    item_discrimination_promotion_decision_recorded =
        decision.item_discrimination_promotion_decision.decision ===
            :keep_preview_only_for_v0_1_1 &&
        decision.item_discrimination_promotion_decision.next_gate ===
            :item_discrimination_promotion_decision
    passed = Bool(public_fit_rejection.rejected) &&
        Bool(experimental_keyword_rejection.rejected) &&
        Bool(contract_review.all_required_fields_recorded) &&
        Bool(contract_review.all_required_provenance_recorded) &&
        all_file_evidence_present &&
        item_discrimination_promotion_decision_recorded &&
        Bool(target_dry_run.finite_logdensity) &&
        Bool(target_dry_run.diagnostics_passed)
    return (;
        schema = "bayesianmgmfrm.gmfrm_guarded_fit_api_dry_run.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :internal_guarded_fit_api_dry_run,
        decision = :keep_internal,
        public_fit = false,
        experimental_public = false,
        fit_ready = false,
        package = package_record(),
        protocol = PROTOCOL,
        proposed_entrypoint = decision.proposed_entrypoint,
        entrypoint_enabled = false,
        fit_rejection_checks = [
            public_fit_rejection,
            experimental_keyword_rejection,
        ],
        artifact_contract_review = contract_review,
        evidence_reference_rows = evidence_rows,
        target_dry_run,
        manifest_snapshot = (;
            candidate_status = candidate.status,
            compiler_stage = candidate.compiler_stage,
            public_target_label = candidate.public_target_label,
            public_target_description = candidate.public_target_description,
            internal_target_constructor = candidate.internal_target_constructor,
            internal_diagnostic_constructor =
                candidate.internal_diagnostic_constructor,
            internal_sampler_diagnostic_constructor =
                candidate.internal_sampler_diagnostic_constructor,
            rater_step_public_option_policy =
                candidate.rater_step_public_option_policy,
            item_discrimination_promotion_decision =
                candidate.item_discrimination_promotion_decision,
            target_constructor = candidate.target_constructor,
            diagnostic_constructor = candidate.diagnostic_constructor,
            sampler_diagnostic_constructor =
                candidate.sampler_diagnostic_constructor,
            fit_ready_compiler_ready = candidate.fit_ready_compiler_ready,
            experimental_public_ready = candidate.experimental_public_ready,
            decision_public_target_label = decision.public_target_label,
            decision_internal_target_constructor =
                decision.internal_target_constructor,
            decision_rater_step_public_option_policy =
                decision.rater_step_public_option_policy,
            decision_item_discrimination_promotion_decision =
                decision.item_discrimination_promotion_decision,
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
        public_fit_allowed = false,
        experimental_keyword_enabled = false,
        current_manifest_fit_allowed = decision.summary.fit_allowed,
        current_manifest_experimental_keyword_enabled =
            decision.summary.experimental_keyword_enabled,
        public_exposure_support =
            :guarded_scalar_gmfrm_only,
        interpretation =
            :guarded_entrypoint_contract_dry_run_superseded_by_broader_exposure_decision_review,
        required_followup = :manual_publication_or_registration_by_user_only,
    ),
    summary = (;
        passed,
        dry_run_only = true,
        publication_or_registration_action = false,
        entrypoint_enabled = false,
        superseded_by_guarded_fit_method_wiring = true,
        superseded_by_experimental_fit_validation_grid = true,
        superseded_by_posterior_predictive_grid = true,
        superseded_by_sparse_pathology_recovery_grid = true,
        superseded_by_prior_likelihood_sensitivity_grid = true,
        superseded_by_real_data_case_study = true,
        superseded_by_claim_recovery_reproduction_archive = true,
        superseded_by_broader_experimental_exposure_decision_review = true,
        superseded_by_full_paper_reproduction_archive = true,
        public_fit_allowed = false,
        experimental_keyword_enabled = false,
        current_manifest_fit_allowed = decision.summary.fit_allowed,
        current_manifest_experimental_keyword_enabled =
            decision.summary.experimental_keyword_enabled,
        fit_rejects_specified_only_gmfrm = public_fit_rejection.rejected,
        fit_preview_rejects_experimental_keyword =
            experimental_keyword_rejection.rejected,
            artifact_contract_recorded =
                contract_review.status === :contract_recorded,
            all_required_artifact_fields_recorded =
                contract_review.all_required_fields_recorded,
            all_required_provenance_artifacts_recorded =
                contract_review.all_required_provenance_recorded,
            n_required_artifact_fields = contract_review.n_required_fields,
            n_required_provenance_artifacts =
                contract_review.n_required_provenance_artifacts,
            all_file_evidence_present,
            rater_step_public_option_policy_recorded =
                decision.rater_step_public_option_policy.public_keyword_enabled === false &&
                decision.rater_step_public_option_policy.next_gate ===
                    :rater_step_public_option_policy,
            item_discrimination_promotion_decision_recorded =
                item_discrimination_promotion_decision_recorded,
        n_evidence_references = length(evidence_rows),
        target_logdensity_finite = target_dry_run.finite_logdensity,
        target_diagnostics_passed = target_dry_run.diagnostics_passed,
        remaining_public_blockers = Symbol[],
        recommendation =
            :full_archive_recorded_keep_guarded_scalar_gmfrm_only,
        next_gate = :manual_publication_or_registration_by_user_only,
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
