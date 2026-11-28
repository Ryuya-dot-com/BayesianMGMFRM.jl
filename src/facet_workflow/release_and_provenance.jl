_release_gate_default_root() = normpath(joinpath(dirname(@__DIR__), ".."))

function _release_gate_document_specs()
    return (
        (;
            target = :readme_public_surface,
            path = "README.md",
        ),
        (;
            target = :news_public_changes,
            path = "NEWS.md",
        ),
        (;
            target = :docs_index_public_surface,
            path = joinpath("docs", "src", "index.md"),
        ),
        (;
            target = :docs_fitting_experimental_contract,
            path = joinpath("docs", "src", "fitting.md"),
        ),
        (;
            target = :docs_experimental_namespace_contract,
            path = joinpath("docs", "src", "experimental.md"),
        ),
        (;
            target = :docs_scope_public_surface,
            path = joinpath("docs", "src", "scope.md"),
        ),
        (;
            target = :docs_model_equations_scope,
            path = joinpath("docs", "src", "model-equations.md"),
        ),
        (;
            target = :docs_bayesian_workflow_scope,
            path = joinpath("docs", "src", "bayesian-workflow.md"),
        ),
        (;
            target = :docs_examples_public_surface,
            path = joinpath("docs", "src", "examples.md"),
        ),
        (;
            target = :documenter_public_boundary,
            path = joinpath("docs", "make.jl"),
        ),
    )
end

function _release_gate_row(; source::Symbol, target::Symbol, path = missing,
        check::Symbol, expected, observed, passed::Bool, note::AbstractString = "")
    return (;
        schema = "bayesianmgmfrm.release_gate_check_row.v1",
        source,
        target,
        path,
        check,
        expected,
        observed,
        status = passed ? :passed : :failed,
        note,
    )
end

function _release_gate_document_rows(root::AbstractString)
    rows = NamedTuple[]
    for spec in _release_gate_document_specs()
        path = joinpath(root, spec.path)
        present = isfile(path)
        push!(rows, _release_gate_row(
            source = :documentation,
            target = spec.target,
            path = spec.path,
            check = :document_present,
            expected = :present,
            observed = present ? :present : :missing,
            passed = present,
            note = "required package-facing document is present",
        ))
    end
    return Tuple(rows)
end

function _release_gate_manifest_rows(scope)
    rows = NamedTuple[]
    statuses = Tuple(row.status for row in scope.status_vocabulary)
    for status in (:supported, :experimental_public, :specified_only, :blocked,
            :stable_public, :external_validated)
        passed = status in statuses
        push!(rows, _release_gate_row(
            source = :manifest,
            target = :status_vocabulary,
            check = :status_defined,
            expected = status,
            observed = passed ? status : statuses,
            passed = passed,
            note = "release status vocabulary includes the expected status",
        ))
    end

    surfaces = scope.public_fit_surfaces
    blocked_claims = Tuple(row.claim for row in scope.blocked_claims)
    evidence_rows = scope.evidence_rows
    progress_evidence_scopes = _release_scope_progress_evidence_scopes()
    progress_evidence_rows = Tuple(row for row in evidence_rows
        if row.scope in progress_evidence_scopes)
    current_ld1b_integration_gates =
        _release_scope_current_ld1b_integration_gate_rows()
    current_ld1b_integration_numerator = count(
        row -> row.gate_status in (:complete, :complete_local_worktree),
        current_ld1b_integration_gates,
    )
    current_ld1b_integration_denominator =
        length(current_ld1b_integration_gates)
    progress_evidence_required_fields = (
        :record_status,
        :gate_status,
        :execution_status,
        :numerator,
        :denominator,
        :attainment_percent,
        :denominator_kind,
        :counts_toward_scientific_denominator,
        :source_artifact,
    )
    has_progress_evidence_fields = row -> all(
        field -> haskey(row, field),
        progress_evidence_required_fields,
    )
    ladder = model_ladder()
    gmfrm_guarded_surface = only(row for row in ladder
        if row.scope === :scalar_gmfrm_guarded_experimental)
    mgmfrm_guarded_surface = only(row for row in ladder
        if row.scope === :fixed_q_confirmatory_mgmfrm_guarded_experimental)
    manifest_checks = (
        (target = :minimal_mfrm_supported,
            expected = :supported_public_fit,
            observed = any(row -> row.surface === :minimal_mfrm_rsm_pcm &&
                row.public_fit && !row.experimental_public,
                surfaces)),
        (target = :fixed_coefficient_mfrm_experimental_public,
            expected = :experimental_public_guarded_fit,
            observed = any(row -> row.surface === :fixed_coefficient_multidimensional_mfrm &&
                row.public_fit && row.experimental_public &&
                row.entrypoint == _EXPERIMENTAL_CANONICAL_ENTRYPOINT &&
                row.q_matrix_policy === :fixed_coefficients &&
                !row.anchors_allowed && !row.validation_bias_terms_allowed,
                surfaces)),
        (target = :scalar_gmfrm_experimental_public,
            expected = :experimental_public_guarded_fit,
            observed = any(row -> row.surface === :scalar_gmfrm_guarded_experimental &&
                row.public_fit && row.experimental_public &&
                row.entrypoint == _EXPERIMENTAL_CANONICAL_ENTRYPOINT &&
                row.legacy_entrypoint == _EXPERIMENTAL_LEGACY_ENTRYPOINT &&
                row.claim_scope === :guarded_scalar_rater_consistency_only &&
                row.threshold_regimes == (:partial_credit,) &&
                row.spec_discrimination == (:rater,) &&
                !row.anchors_allowed && !row.validation_bias_terms_allowed,
                surfaces)),
        (target = :fixed_q_mgmfrm_experimental_public,
            expected = :experimental_public_guarded_fit,
            observed = any(row -> row.surface ===
                :fixed_q_confirmatory_mgmfrm_guarded_experimental &&
                row.public_fit && row.experimental_public &&
                row.entrypoint == _EXPERIMENTAL_CANONICAL_ENTRYPOINT &&
                row.legacy_entrypoint == _EXPERIMENTAL_LEGACY_ENTRYPOINT &&
                row.claim_scope === :fixed_q_confirmatory_only &&
                row.threshold_regimes == (:partial_credit,) &&
                row.spec_discrimination == (:none,) &&
                row.q_matrix_policy === :fixed_confirmatory &&
                !row.anchors_allowed && !row.validation_bias_terms_allowed,
                surfaces)),
        (target = :scalar_gmfrm_fail_closed_option_contract,
            expected = :partial_credit_rater_no_implicit_variant,
            observed = gmfrm_guarded_surface.threshold_regimes ==
                (:partial_credit,) &&
                gmfrm_guarded_surface.spec_discrimination == (:rater,)),
        (target = :fixed_q_mgmfrm_fail_closed_option_contract,
            expected = :partial_credit_generic_none_no_implicit_variant,
            observed = mgmfrm_guarded_surface.threshold_regimes ==
                (:partial_credit,) &&
                mgmfrm_guarded_surface.spec_discrimination == (:none,)),
        (target = :broad_generalized_claims_blocked,
            expected = :blocked,
            observed = :broad_generalized_fit in blocked_claims &&
                !scope.summary.broader_generalized_fit_allowed),
        (target = :dff_model_effects_blocked,
            expected = :blocked,
            observed = :dff_model_effects in blocked_claims &&
                !scope.summary.dff_model_effects_allowed),
        (target = :model_weight_claims_blocked,
            expected = :blocked,
            observed = :model_weight_or_superiority in blocked_claims &&
                !scope.summary.model_weight_claims_allowed),
        (target = :sparse_superiority_claims_blocked,
            expected = :blocked,
            observed = :sparse_mgmfrm_superiority in blocked_claims &&
                !scope.summary.sparse_superiority_claims_allowed),
        (target = :post_v0_2_external_validation_blocked,
            expected = :blocked_until_external_validation,
            observed = all(claim -> claim in blocked_claims,
                (:r_package_overlap_comparison, :real_data_validation,
                    :external_validation))),
        (target = :v0_1_1_refinement_evidence_row,
            expected = :completed,
            observed = any(row -> row.scope === :v0_1_1_generalized_refinement &&
                row.evidence === :implementation_checklist_created &&
                row.status === :done &&
                haskey(row, :phase_status) && row.phase_status === :completed &&
                haskey(row, :historical_release) && row.historical_release,
                evidence_rows)),
        (target = :current_development_version,
            expected = string(pkgversion(@__MODULE__)),
            observed = scope.summary.development_version ==
                string(pkgversion(@__MODULE__))),
        (target = :current_development_phase,
            expected = :v0_1_2_fixed_q_productionization,
            observed = scope.summary.development_phase ===
                :v0_1_2_fixed_q_productionization &&
                scope.summary.development_next_gate ===
                    :v0_1_2_fixed_q_productionization),
        (target = :guarded_experimental_surface_next_gate,
            expected = :v0_1_2_fixed_q_productionization,
            observed = all(row -> !(row.experimental_public && row.family in (:gmfrm, :mgmfrm)) ||
                (haskey(row, :completed_gate) &&
                    row.completed_gate === :v0_1_1_generalized_refinement &&
                    haskey(row, :next_gate) &&
                    row.next_gate === :v0_1_2_fixed_q_productionization),
                surfaces)),
        (target = :roadmap_progress_evidence_row_set,
            expected = progress_evidence_scopes,
            observed = length(progress_evidence_rows) ==
                length(progress_evidence_scopes) &&
                Set(row.scope for row in progress_evidence_rows) ==
                    Set(progress_evidence_scopes)),
        (target = :roadmap_progress_evidence_schema,
            expected = progress_evidence_required_fields,
            observed = all(row -> has_progress_evidence_fields(row) &&
                !haskey(row, :status) &&
                row.numerator isa Integer &&
                row.denominator isa Integer &&
                0 <= row.numerator <= row.denominator &&
                row.attainment_percent isa Real &&
                row.attainment_percent == round(
                    100 * row.numerator / row.denominator;
                    digits = 1,
                ) &&
                0.0 <= row.attainment_percent <= 100.0 &&
                row.counts_toward_scientific_denominator isa Bool &&
                !ismissing(row.source_artifact),
                progress_evidence_rows)),
        (target = :free_correlation_operational_progress,
            expected = (numerator = 0, denominator = 3),
            observed = any(row -> row.scope ===
                    :free_latent_correlation_operational_prerequisites &&
                has_progress_evidence_fields(row) &&
                row.record_status === :current_progress_recorded &&
                row.gate_status === :not_passed &&
                row.execution_status ===
                    :mcmc_free_initial_gradient_profile_failed &&
                row.numerator == 0 && row.denominator == 3 &&
                row.denominator_kind ===
                    :conjunctive_pre_scientific_operational_gates &&
                !row.counts_toward_scientific_denominator &&
                row.source_artifact ===
                    :mgmfrm_free_latent_correlation_2d_resource_probe_receipt &&
                haskey(row, :gate_rows) && length(row.gate_rows) == 3,
                progress_evidence_rows)),
        (target = :free_correlation_scientific_progress,
            expected = (numerator = 0, denominator = 525,
                feasibility = (0, 25), evaluation = (0, 500)),
            observed = any(row -> row.scope ===
                    :free_latent_correlation_scientific_execution &&
                has_progress_evidence_fields(row) &&
                row.record_status === :current_progress_recorded &&
                row.gate_status === :blocked_by_operational_prerequisites &&
                row.execution_status === :not_executed &&
                row.numerator == 0 && row.denominator == 525 &&
                row.denominator_kind === :frozen_scientific_study_units &&
                row.counts_toward_scientific_denominator &&
                row.source_artifact ===
                    :mgmfrm_free_latent_correlation_2d_study_plan_v2 &&
                haskey(row, :component_counts) &&
                row.component_counts.computation_only_feasibility ==
                    (numerator = 0, denominator = 25) &&
                row.component_counts.recovery_evaluation ==
                    (numerator = 0, denominator = 500),
                progress_evidence_rows)),
        (target = :v0_1_2_ld1b_integration_progress,
            expected = (numerator = current_ld1b_integration_numerator,
                denominator = current_ld1b_integration_denominator,
                attainment_percent = 77.8,
                provenance = :local_dirty_worktree),
            observed = any(row -> row.scope === :v0_1_2_ld1b_integration &&
                has_progress_evidence_fields(row) &&
                row.record_status ===
                    :current_dirty_worktree_snapshot_recorded &&
                row.gate_status === :partially_attained_local_worktree_only &&
                row.execution_status ===
                    :bounded_verification_mcmc_nonpilot_integration_evidence_only &&
                row.numerator == current_ld1b_integration_numerator &&
                row.denominator == current_ld1b_integration_denominator &&
                row.attainment_percent == 77.8 &&
                row.denominator_kind === :ordered_integration_acceptance_gates &&
                !row.counts_toward_scientific_denominator &&
                row.source_artifact ===
                    :roadmap_current_v0_1_2_ld1b_integration_checklist &&
                haskey(row, :release_lineage_verified) &&
                !row.release_lineage_verified &&
                haskey(row, :scientific_numerator_contribution) &&
                row.scientific_numerator_contribution == 0 &&
                haskey(row, :gate_rows) &&
                row.gate_rows == current_ld1b_integration_gates,
                progress_evidence_rows)),
        (target = :ld1b_scientific_progress,
            expected = (numerator = 0, denominator = 660,
                fitting = (0, 540), structural_rejections = (0, 120)),
            observed = any(row -> row.scope === :ld1b_scientific_execution &&
                has_progress_evidence_fields(row) &&
                row.record_status === :current_progress_recorded &&
                row.gate_status === :blocked_by_open_integration_gates &&
                row.execution_status === :not_executed &&
                row.numerator == 0 && row.denominator == 660 &&
                row.denominator_kind === :frozen_pilot_primary_jobs &&
                row.counts_toward_scientific_denominator &&
                row.source_artifact ===
                    :local_dependence_calibration_pilot_contract_v1 &&
                haskey(row, :component_counts) &&
                row.component_counts.eligible_fitting_jobs ==
                    (numerator = 0, denominator = 540) &&
                row.component_counts.planned_structural_rejections ==
                    (numerator = 0, denominator = 120),
                progress_evidence_rows)),
        (target = :release_gate_check_evidence_row,
            expected = :recorded,
            observed = any(row -> row.scope === :status_synchronization &&
                row.evidence === :release_gate_check,
                evidence_rows)),
        (target = :related_software_capability_matrix_evidence_row,
            expected = :recorded,
            observed = any(row -> row.scope === :positioning_and_non_superiority &&
                row.evidence === :related_software_capability_matrix,
                evidence_rows)),
    )
    for check in manifest_checks
        passed = check.observed === true
        push!(rows, _release_gate_row(
            source = :manifest,
            target = check.target,
            check = :manifest_consistency,
            expected = check.expected,
            observed = check.observed,
            passed = passed,
            note = "release-scope manifest agrees with the current narrow public-surface policy",
        ))
    end
    return Tuple(rows)
end

"""
    release_gate_check(; root = package root, throw_on_failure = false)

Check that required package-facing documents exist and that the machine-readable
release-scope manifest represents the current support policy. Exact prose is
intentionally not a release contract: Documenter, public examples, and the
public-language checks cover the reader-facing surface without pinning sentences.
The structured gate expects minimal MFRM/RSM/PCM to remain `supported`, the
scalar rater-consistency GMFRM and fixed-Q confirmatory MGMFRM paths to remain
`experimental_public`, and broad generalized fitting, DFF model effects,
model-weight claims, sparse-superiority claims, and post-v0.2.0
external-validation claims to remain blocked.

Set `throw_on_failure = true` for release scripts or CI steps that should fail
as soon as documentation and manifest status rows drift.
"""
function release_gate_check(; root::AbstractString = _release_gate_default_root(),
        throw_on_failure::Bool = false)
    normalized_root = normpath(root)
    scope = release_scope_summary(; include_evidence = true)
    document_rows = _release_gate_document_rows(normalized_root)
    manifest_rows = _release_gate_manifest_rows(scope)
    rows = (document_rows..., manifest_rows...)
    failed_rows = Tuple(row for row in rows if row.status !== :passed)
    passed = isempty(failed_rows)
    summary = (;
        passed,
        n_rows = length(rows),
        n_document_rows = length(document_rows),
        n_manifest_rows = length(manifest_rows),
        n_failed_rows = length(failed_rows),
        failed_targets = Tuple(row.target for row in failed_rows),
        broad_generalized_fit_allowed = scope.summary.broader_generalized_fit_allowed,
        dff_model_effects_allowed = scope.summary.dff_model_effects_allowed,
        model_weight_claims_allowed = scope.summary.model_weight_claims_allowed,
        sparse_superiority_claims_allowed =
            scope.summary.sparse_superiority_claims_allowed,
        development_version = scope.summary.development_version,
        development_phase = scope.summary.development_phase,
        development_next_gate = scope.summary.development_next_gate,
        publication_or_registration_action = false,
        next_gate = passed ? :manual_publication_or_registration_by_user_only :
            :repair_package_surface_or_structured_scope_contract,
    )
    result = (;
        schema = "bayesianmgmfrm.release_gate_check.v1",
        object = :release_gate_check,
        status = passed ? :passed : :failed,
        root = normalized_root,
        release_scope = scope,
        rows,
        summary,
    )
    if throw_on_failure && !passed
        throw(ArgumentError(
            "release gate failed with $(summary.n_failed_rows) failed row(s): " *
            join(string.(summary.failed_targets), ", ")))
    end
    return result
end

function _default_case_study_source_records()
    return (
        (;
            source_id = :writing_rater_mediated_slice,
            source_role = :real_data_case_study_input,
            family = :gmfrm,
            scope = :scalar_gmfrm_fit_ready_candidate,
            data_release = :not_public,
            license_status = :local_review_recorded_not_public_license,
            anonymization_status = :pseudonymized,
            direct_identifiers_removed = true,
            person_ids_pseudonymized = true,
            rater_ids_pseudonymized = true,
            archive_sync_required = true,
        ),
        (;
            source_id = :speaking_rater_mediated_slice,
            source_role = :real_data_case_study_input,
            family = :gmfrm,
            scope = :scalar_gmfrm_fit_ready_candidate,
            data_release = :not_public,
            license_status = :local_review_recorded_not_public_license,
            anonymization_status = :pseudonymized,
            direct_identifiers_removed = true,
            person_ids_pseudonymized = true,
            rater_ids_pseudonymized = true,
            archive_sync_required = true,
        ),
    )
end

function _default_case_study_archive_records()
    return (
        (;
            archive = :real_data_case_study,
            path = "test/fixtures/gmfrm_real_data_case_study.json",
            role = :case_study_evidence,
            publication_facing = false,
            requires_source_license_record = true,
            requires_anonymization_record = true,
            sync_status = :synchronized_by_manifest,
            publication_or_registration_action = false,
        ),
        (;
            archive = :claim_recovery_reproduction_archive,
            path = "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
            role = :claim_recovery_archive,
            publication_facing = false,
            requires_source_license_record = true,
            requires_anonymization_record = true,
            sync_status = :synchronized_by_manifest,
            publication_or_registration_action = false,
        ),
        (;
            archive = :manuscript_scale_simulation_grid,
            path = "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
            role = :gate_e_evidence_grid,
            publication_facing = true,
            requires_source_license_record = true,
            requires_anonymization_record = true,
            sync_status = :synchronized_by_manifest,
            publication_or_registration_action = false,
        ),
        (;
            archive = :full_paper_reproduction_archive,
            path = "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
            role = :full_local_reproduction_archive,
            publication_facing = true,
            requires_source_license_record = true,
            requires_anonymization_record = true,
            sync_status = :synchronized_by_manifest,
            publication_or_registration_action = false,
        ),
    )
end

function _case_study_record_tuple(records, name::Symbol)
    records isa NamedTuple && return (records,)
    records isa Tuple && (tupled = records)
    records isa AbstractVector && (tupled = Tuple(records))
    @isdefined(tupled) ||
        throw(ArgumentError("$name must be a NamedTuple, Tuple, or vector of NamedTuples"))
    isempty(tupled) && throw(ArgumentError("$name cannot be empty"))
    all(row -> row isa NamedTuple, tupled) ||
        throw(ArgumentError("$name must contain only NamedTuple rows"))
    return tupled
end

_case_study_nt_get(row::NamedTuple, key::Symbol, default) =
    haskey(row, key) ? getproperty(row, key) : default

function _case_study_required(row::NamedTuple, key::Symbol, name::Symbol)
    haskey(row, key) || throw(ArgumentError("$name row is missing required field $key"))
    return getproperty(row, key)
end

function _case_study_normalize_source(row::NamedTuple)
    source_id = _case_study_required(row, :source_id, :source_records)
    anonymization_status =
        _case_study_nt_get(row, :anonymization_status, :missing)
    license_status = _case_study_nt_get(row, :license_status, :missing)
    direct_identifiers_removed =
        _case_study_nt_get(row, :direct_identifiers_removed, false) === true
    anonymization_record_passed =
        direct_identifiers_removed &&
        anonymization_status in (:anonymized, :pseudonymized, :deidentified)
    license_record_declared =
        !(ismissing(license_status) || license_status === :missing)
    return merge(row, (;
        schema = "bayesianmgmfrm.case_study_source_provenance.v1",
        object = :case_study_source_provenance,
        source_id,
        anonymization_record_passed,
        license_record_declared,
        external_public_release_allowed =
            _case_study_nt_get(row, :external_public_release_allowed, false) === true,
        archive_sync_required =
            _case_study_nt_get(row, :archive_sync_required, true) === true,
    ))
end

function _case_study_normalize_archive(row::NamedTuple)
    archive = _case_study_required(row, :archive, :archive_records)
    sync_status = _case_study_nt_get(row, :sync_status, :missing)
    requires_source_license_record =
        _case_study_nt_get(row, :requires_source_license_record, true) === true
    requires_anonymization_record =
        _case_study_nt_get(row, :requires_anonymization_record, true) === true
    publication_facing =
        _case_study_nt_get(row, :publication_facing, false) === true
    publication_or_registration_action =
        _case_study_nt_get(row, :publication_or_registration_action, false) === true
    provenance_sync_passed =
        sync_status in (:synchronized, :synchronized_by_manifest) &&
        requires_source_license_record &&
        requires_anonymization_record &&
        !publication_or_registration_action
    return merge(row, (;
        schema = "bayesianmgmfrm.case_study_archive_sync.v1",
        object = :case_study_archive_sync,
        archive,
        publication_facing,
        requires_source_license_record,
        requires_anonymization_record,
        publication_or_registration_action,
        provenance_sync_passed,
    ))
end

"""
    case_study_provenance_manifest(; source_records = ..., archive_records = ...)

Return a machine-readable provenance manifest tying the compact real-data case
study source records to claim-level and publication-facing reproduction
archives. The default records cover the local guarded scalar GMFRM writing and
speaking rater-mediated slices and the current real-data, claim-recovery,
manuscript-scale, and full-paper archive artifacts.

The manifest checks only that licensing status and anonymization status are
declared and synchronized with archive records. It is not a data license grant,
IRB determination, publication action, registration action, or manuscript claim
approval.
"""
function case_study_provenance_manifest(;
        source_records = _default_case_study_source_records(),
        archive_records = _default_case_study_archive_records())
    sources = Tuple(_case_study_normalize_source(row)
        for row in _case_study_record_tuple(source_records, :source_records))
    archives = Tuple(_case_study_normalize_archive(row)
        for row in _case_study_record_tuple(archive_records, :archive_records))
    all_source_records_anonymized =
        all(row -> row.anonymization_record_passed, sources)
    all_license_records_declared =
        all(row -> row.license_record_declared, sources)
    all_archive_records_synchronized =
        all(row -> row.provenance_sync_passed, archives)
    publication_archives_synchronized =
        all(row -> !row.publication_facing || row.provenance_sync_passed, archives)
    no_public_source_release =
        all(row -> !row.external_public_release_allowed, sources)
    no_publication_actions =
        all(row -> !row.publication_or_registration_action, archives)
    passed = all_source_records_anonymized &&
        all_license_records_declared &&
        all_archive_records_synchronized &&
        publication_archives_synchronized &&
        no_publication_actions

    return (;
        schema = "bayesianmgmfrm.case_study_provenance_manifest.v1",
        object = :case_study_provenance_manifest,
        status = passed ? :synchronized : :incomplete,
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        source_records = sources,
        archive_records = archives,
        summary = (;
            passed,
            n_source_records = length(sources),
            n_archive_records = length(archives),
            n_publication_facing_archives =
                count(row -> row.publication_facing, archives),
            all_source_records_anonymized,
            all_license_records_declared,
            all_archive_records_synchronized,
            publication_archives_synchronized,
            no_public_source_release,
            no_publication_actions,
            license_grant = false,
            irb_determination = false,
            publication_or_registration_action = false,
            manuscript_claims_allowed = false,
            caveat = :provenance_manifest_not_license_irb_or_publication_approval,
            next_gate = :manual_publication_or_registration_by_user_only,
        ),
    )
end
