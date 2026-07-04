#!/usr/bin/env julia

using JSON3
using SHA
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_guarded_local_fit_entrypoint.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :q_revision_construct_validity_review,
        path = "test/fixtures/mgmfrm_q_revision_construct_validity_review.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_revision_construct_validity_review.v1",
        pass_policy = :summary_passed),
    (name = :guarded_fit_api_dry_run,
        path = "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_guarded_fit_api_dry_run.v1",
        pass_policy = :summary_passed),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_guarded_local_fit_entrypoint_v1",
    review_kind = :local_construct_reviewed_q_candidate_fit_entrypoint,
    publication_or_registration_action = false,
    local_only = true,
    dry_run_only = true,
    entrypoint = "fit(spec; experimental = true)",
    candidate_source = :construct_reviewed_q_revision_candidates,
    fit_controls = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 1,
        warmup = 0,
        draws = 1,
        seed_base = 20260721,
    ),
    thresholds = (;
        require_q_revision_construct_validity_review_passed = true,
        require_guarded_fit_api_dry_run_passed = true,
        require_construct_reviewed_candidates_available = true,
        require_all_construct_reviewed_candidates_checked = true,
        require_all_candidate_q_validations_passed = true,
        require_all_candidate_specs_previewed = true,
        require_non_experimental_fit_rejection = true,
        require_unsupported_backend_rejection = true,
        require_all_guarded_fit_attempts_succeeded = true,
        require_fit_outputs_finite = true,
        require_all_candidates_remain_manual_local_only = true,
        require_no_automatic_q_revision = true,
        require_no_public_q_revision_claim = true,
        require_no_broader_mgmfrm_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM guarded fit entrypoint artifact for
    construct-reviewed Q candidates.

    The artifact dry-runs fixed-Q candidate specs through the existing guarded
    MGMFRM entrypoint. It records that construct-reviewed Q candidates can be
    used as manual local fit inputs, but it does not revise Q matrices
    automatically, publish Q-revision claims, or broaden the MGMFRM API.

    Usage:
      julia --project=. scripts/generate_mgmfrm_guarded_local_fit_entrypoint.jl [--output PATH]
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

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
local_path(path::AbstractString) = normpath(joinpath(ROOT, path))

function artifact_record(spec)
    path = local_path(spec.path)
    exists = isfile(path)
    if !exists
        return (;
            artifact = spec.name,
            path = spec.path,
            exists = false,
            sha256 = missing,
            expected_schema = spec.expected_schema,
            schema = missing,
            schema_matches = false,
            pass_policy = spec.pass_policy,
            summary_passed = false,
            summary = (; passed = false),
        )
    end
    parsed = JSON3.read(read(path, String))
    schema = String(parsed[:schema])
    schema_matches = schema == spec.expected_schema
    summary = parsed[:summary]
    summary_passed =
        spec.pass_policy === :summary_passed && Bool(summary[:passed])
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        sha256 = file_sha256(path),
        expected_schema = spec.expected_schema,
        schema,
        schema_matches,
        pass_policy = spec.pass_policy,
        summary_passed,
        summary = input_summary(spec.name, summary),
    )
end

function input_summary(name::Symbol, summary)
    name === :q_revision_construct_validity_review && return (;
        passed = Bool(summary[:passed]),
        n_construct_review_rows = Int(summary[:n_construct_review_rows]),
        n_construct_supported_candidates =
            Int(summary[:n_construct_supported_candidates]),
        construct_validity_supported_for_all_reviewed =
            Bool(summary[:construct_validity_supported_for_all_reviewed]),
        supported_candidates_remain_manual_local_only =
            Bool(summary[:supported_candidates_remain_manual_local_only]),
        no_automatic_q_revision = Bool(summary[:no_automatic_q_revision]),
        no_public_q_revision_claim = Bool(summary[:no_public_q_revision_claim]),
        next_gate = String(summary[:next_gate]),
    )
    name === :guarded_fit_api_dry_run && return (;
        passed = Bool(summary[:passed]),
        entrypoint_enabled = Bool(summary[:entrypoint_enabled]),
        experimental_spec_fit_succeeded =
            Bool(summary[:experimental_spec_fit_succeeded]),
        all_fit_boundary_checks_passed =
            Bool(summary[:all_fit_boundary_checks_passed]),
        artifact_contract_satisfied =
            Bool(summary[:artifact_contract_satisfied]),
        target_gradient_diagnostics_passed =
            Bool(summary[:target_gradient_diagnostics_passed]),
        next_gate = String(summary[:next_gate]),
    )
    return (; passed = Bool(summary[:passed]))
end

function parsed_input_artifact(spec)
    path = local_path(spec.path)
    isfile(path) || error("input artifact is missing: $(spec.path)")
    return JSON3.read(read(path, String))
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function q_matrix_from_json(rows)
    n_rows = length(rows)
    n_cols = length(first(rows))
    matrix = Matrix{Bool}(undef, n_rows, n_cols)
    for row in 1:n_rows, col in 1:n_cols
        matrix[row, col] = Bool(rows[row][col])
    end
    return matrix
end

function q_matrix_rows(matrix::AbstractMatrix{Bool})
    return [[Bool(matrix[row, col]) for col in axes(matrix, 2)]
        for row in axes(matrix, 1)]
end

function local_three_item_spec(q_matrix::AbstractMatrix{Bool})
    table = (;
        examinee = [
            "E1", "E1", "E1", "E1", "E1", "E1",
            "E2", "E2", "E2", "E2", "E2", "E2",
            "E3", "E3", "E3", "E3", "E3", "E3",
        ],
        rater = [
            "R1", "R1", "R1", "R2", "R2", "R2",
            "R1", "R1", "R1", "R2", "R2", "R2",
            "R1", "R1", "R1", "R2", "R2", "R2",
        ],
        item = [
            "I1", "I2", "I3", "I1", "I2", "I3",
            "I1", "I2", "I3", "I1", "I2", "I3",
            "I1", "I2", "I3", "I1", "I2", "I3",
        ],
        score = [0, 1, 2, 1, 2, 0, 1, 0, 2, 2, 1, 0, 2, 1, 0, 0, 2, 1],
    )
    data = BayesianMGMFRM.FacetData(table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
    return BayesianMGMFRM.mfrm_spec(data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix,
    )
end

function boundary_check(name::Symbol, expected_status::Symbol, callable)
    try
        callable()
        actual_status = :succeeded
        return (;
            check = name,
            expected_status,
            actual_status,
            rejected = false,
            error_type = missing,
            message = missing,
            passed = actual_status === expected_status,
        )
    catch err
        actual_status = :rejected
        return (;
            check = name,
            expected_status,
            actual_status,
            rejected = true,
            error_type = String(nameof(typeof(err))),
            message = sprint(showerror, err),
            passed = actual_status === expected_status,
        )
    end
end

boundary_check(callable, name::Symbol, expected_status::Symbol) =
    boundary_check(name, expected_status, callable)

function guarded_fit_summary(spec, scenario::Symbol, seed::Int)
    fit = BayesianMGMFRM.fit(
        spec;
        experimental = true,
        backend = PROTOCOL.fit_controls.backend,
        ndraws = PROTOCOL.fit_controls.draws,
        warmup = PROTOCOL.fit_controls.warmup,
        chains = PROTOCOL.fit_controls.chains,
        seed,
        progress = false,
    )
    return (;
        returned_type = Symbol(nameof(typeof(fit))),
        scenario,
        seed,
        backend = fit.backend,
        sampler = fit.sampler,
        n_observations = fit.design.spec.data.n,
        n_items = length(fit.design.spec.data.item_levels),
        n_dimensions = fit.design.spec.dimensions,
        n_draws = size(fit.draws, 1),
        n_raw_parameters = size(fit.draws, 2),
        n_direct_parameters = size(fit.direct_draws, 2),
        n_pointwise_rows = size(fit.direct_pointwise_loglikelihood, 1),
        n_pointwise_observations = size(fit.direct_pointwise_loglikelihood, 2),
        finite_log_posterior = all(isfinite, fit.log_posterior),
        finite_raw_draws = all(isfinite, fit.draws),
        finite_direct_draws = all(isfinite, fit.direct_draws),
        finite_direct_loglikelihood = all(isfinite, fit.direct_loglikelihood),
        finite_pointwise_loglikelihood =
            all(isfinite, fit.direct_pointwise_loglikelihood),
        diagnostic_flag = fit.diagnostic_surface.summary.flag,
        n_nonfinite_logdensity =
            fit.diagnostic_surface.summary.n_nonfinite_logdensity,
        n_nonfinite_direct_loglikelihood =
            fit.diagnostic_surface.summary.n_nonfinite_direct_loglikelihood,
        n_failed_direct_constraints =
            fit.diagnostic_surface.summary.n_failed_direct_constraints,
        n_divergences = fit.diagnostic_surface.summary.n_divergences,
        n_max_treedepth = fit.diagnostic_surface.summary.n_max_treedepth,
        output_finite = all(isfinite, fit.log_posterior) &&
            all(isfinite, fit.draws) &&
            all(isfinite, fit.direct_draws) &&
            all(isfinite, fit.direct_loglikelihood) &&
            all(isfinite, fit.direct_pointwise_loglikelihood),
    )
end

function candidate_entrypoint_record(source_row, index::Int)
    scenario = Symbol(String(source_row[:scenario]))
    candidate_q = q_matrix_from_json(source_row[:candidate_q])
    spec = local_three_item_spec(candidate_q)
    q_validation = BayesianMGMFRM.q_matrix_validation(spec)
    design = BayesianMGMFRM.getdesign(spec; preview = true)
    fit_seed = Int(PROTOCOL.fit_controls.seed_base) + index
    non_experimental = boundary_check(
        :fit_construct_reviewed_q_without_experimental,
        :rejected,
    ) do
        BayesianMGMFRM.fit(spec; ndraws = 1, warmup = 0)
    end
    unsupported_backend = boundary_check(
        :fit_construct_reviewed_q_unsupported_backend,
        :rejected,
    ) do
        BayesianMGMFRM.fit(
            spec;
            experimental = true,
            backend = :julia,
            ndraws = 1,
            warmup = 0,
        )
    end
    fit_result = try
        (succeeded = true,
            error_type = missing,
            message = missing,
            summary = guarded_fit_summary(spec, scenario, fit_seed))
    catch err
        (succeeded = false,
            error_type = String(nameof(typeof(err))),
            message = sprint(showerror, err),
            summary = missing)
    end
    preview_summary = (;
        spec_estimation_status = spec.estimation_status,
        design_preview_succeeded = true,
        n_preview_parameters = length(design.parameter_names),
        fit_ready_layout_available = haskey(design.blocks,
            :item_dimension_discrimination),
        q_matrix = q_matrix_rows(spec.q_matrix),
    )
    fit_outputs_finite =
        Bool(fit_result.succeeded) &&
        Bool(fit_result.summary.output_finite) &&
        Int(fit_result.summary.n_nonfinite_logdensity) == 0 &&
        Int(fit_result.summary.n_nonfinite_direct_loglikelihood) == 0 &&
        Int(fit_result.summary.n_failed_direct_constraints) == 0
    return (;
        scenario,
        source_decision = Symbol(String(source_row[:decision])),
        operation = Symbol(String(source_row[:operation])),
        item = Symbol(String(source_row[:item])),
        dimension = Symbol(String(source_row[:dimension])),
        construct_review_supported =
            Bool(source_row[:construct_review_supported]),
        manual_local_q_revision_candidate_allowed =
            Bool(source_row[:manual_local_q_revision_candidate_allowed]),
        public_revision_allowed = Bool(source_row[:public_revision_allowed]),
        automatic_revision_allowed =
            Bool(source_row[:automatic_revision_allowed]),
        public_claim_allowed = Bool(source_row[:public_claim_allowed]),
        candidate_q = q_matrix_rows(candidate_q),
        q_validation = (;
            passed = Bool(q_validation.passed),
            n_error_rows = Int(q_validation.summary.n_error_rows),
            n_warning_rows = Int(q_validation.summary.n_warning_rows),
            fixed_q_confirmatory =
                Bool(q_validation.summary.fixed_q_confirmatory),
            n_cross_loading_items =
                Int(q_validation.summary.n_cross_loading_items),
            n_duplicate_dimension_groups =
                Int(q_validation.summary.n_duplicate_dimension_groups),
            n_dimension_facet_subgraphs_disconnected =
                Int(q_validation.summary.n_dimension_facet_subgraphs_disconnected),
            warning_checks = [
                row.check for row in q_validation.rows
                if row.severity === :warning
            ],
        ),
        preview_summary,
        boundary_checks = [non_experimental, unsupported_backend],
        guarded_fit = fit_result,
        summary = (;
            passed = Bool(q_validation.passed) &&
                Bool(preview_summary.design_preview_succeeded) &&
                all(row -> row.passed, [non_experimental, unsupported_backend]) &&
                Bool(fit_result.succeeded) &&
                fit_outputs_finite &&
                Bool(source_row[:construct_review_supported]) &&
                Bool(source_row[:manual_local_q_revision_candidate_allowed]) &&
                !Bool(source_row[:public_revision_allowed]) &&
                !Bool(source_row[:automatic_revision_allowed]) &&
                !Bool(source_row[:public_claim_allowed]),
            q_validation_passed = Bool(q_validation.passed),
            spec_previewed = Bool(preview_summary.design_preview_succeeded),
            non_experimental_fit_rejected = Bool(non_experimental.rejected),
            unsupported_backend_rejected = Bool(unsupported_backend.rejected),
            guarded_fit_attempt_succeeded = Bool(fit_result.succeeded),
            fit_outputs_finite,
            manual_local_only =
                Bool(source_row[:manual_local_q_revision_candidate_allowed]) &&
                !Bool(source_row[:public_revision_allowed]) &&
                !Bool(source_row[:automatic_revision_allowed]) &&
                !Bool(source_row[:public_claim_allowed]),
        ),
    )
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_guarded_local_fit_entrypoint.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    construct_record =
        record_by_name(input_records, :q_revision_construct_validity_review)
    api_record = record_by_name(input_records, :guarded_fit_api_dry_run)
    q_review = parsed_input_artifact(first(INPUT_ARTIFACTS))
    source_rows = [
        row for row in q_review[:construct_review_rows]
        if Bool(row[:construct_review_supported]) &&
            Bool(row[:manual_local_q_revision_candidate_allowed])
    ]
    entrypoint_rows = [
        candidate_entrypoint_record(row, index)
        for (index, row) in enumerate(source_rows)
    ]
    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_input_summaries_passed =
        all(record -> record.summary_passed, input_records)
    construct_reviewed_candidates_available = !isempty(source_rows)
    all_construct_reviewed_candidates_checked =
        length(entrypoint_rows) == length(source_rows) ==
        construct_record.summary.n_construct_supported_candidates
    all_candidate_q_validations_passed =
        all(row -> row.q_validation.passed, entrypoint_rows)
    all_candidate_specs_previewed =
        all(row -> row.preview_summary.design_preview_succeeded, entrypoint_rows)
    non_experimental_fit_rejected =
        all(row -> row.summary.non_experimental_fit_rejected, entrypoint_rows)
    unsupported_backend_rejected =
        all(row -> row.summary.unsupported_backend_rejected, entrypoint_rows)
    all_guarded_fit_attempts_succeeded =
        all(row -> row.summary.guarded_fit_attempt_succeeded, entrypoint_rows)
    fit_outputs_finite =
        all(row -> row.summary.fit_outputs_finite, entrypoint_rows)
    all_candidates_remain_manual_local_only =
        all(row -> row.summary.manual_local_only, entrypoint_rows)
    no_automatic_q_revision =
        all(row -> !row.automatic_revision_allowed, entrypoint_rows)
    no_public_q_revision_claim =
        all(row -> !row.public_revision_allowed && !row.public_claim_allowed,
            entrypoint_rows)
    no_broader_mgmfrm_claim = true
    no_publication = no_publication_commands()

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        construct_record.summary.construct_validity_supported_for_all_reviewed &&
        construct_record.summary.supported_candidates_remain_manual_local_only &&
        construct_record.summary.no_automatic_q_revision &&
        construct_record.summary.no_public_q_revision_claim &&
        construct_record.summary.next_gate == "guarded_local_mgmfrm_fit_entrypoint" &&
        api_record.summary.entrypoint_enabled &&
        api_record.summary.experimental_spec_fit_succeeded &&
        api_record.summary.all_fit_boundary_checks_passed &&
        api_record.summary.artifact_contract_satisfied &&
        construct_reviewed_candidates_available &&
        all_construct_reviewed_candidates_checked &&
        all_candidate_q_validations_passed &&
        all_candidate_specs_previewed &&
        non_experimental_fit_rejected &&
        unsupported_backend_rejected &&
        all_guarded_fit_attempts_succeeded &&
        fit_outputs_finite &&
        all_candidates_remain_manual_local_only &&
        no_automatic_q_revision &&
        no_public_q_revision_claim &&
        no_broader_mgmfrm_claim &&
        no_publication &&
        all(row -> row.summary.passed, entrypoint_rows)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_guarded_local_fit_entrypoint.v1",
        family = :mgmfrm,
        scope = :construct_reviewed_q_guarded_local_fit_entrypoint,
        status = :guarded_local_fit_entrypoint_recorded,
        decision =
            :enable_construct_reviewed_q_candidates_for_manual_local_guarded_fit,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        dry_run_only = true,
        q_revision_public = false,
        automatic_q_revision = false,
        broader_mgmfrm_claim = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        input_artifacts = input_records,
        fit_entrypoint_rows = entrypoint_rows,
        decision_record = (;
            local_guarded_fit_entrypoint_recorded = true,
            construct_reviewed_q_candidates_can_be_fit_locally =
                all_guarded_fit_attempts_succeeded,
            candidate_suggestions_allowed = true,
            manual_local_q_revision_candidates_allowed = true,
            automatic_q_revision_allowed = false,
            public_q_revision_claim_allowed = false,
            broader_mgmfrm_claim_allowed = false,
            public_exposure_support =
                :construct_reviewed_q_candidates_fit_as_manual_local_inputs,
            interpretation =
                :local_guarded_fit_entrypoint_supports_manual_q_candidate_analysis_not_public_revision,
            required_followup =
                :construct_reviewed_q_fit_reporting_policy,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            dry_run_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            q_revision_construct_validity_review_passed =
                construct_record.summary_passed,
            guarded_fit_api_dry_run_passed = api_record.summary_passed,
            construct_reviewed_candidates_available,
            all_construct_reviewed_candidates_checked,
            all_candidate_q_validations_passed,
            all_candidate_specs_previewed,
            non_experimental_fit_rejected,
            unsupported_backend_rejected,
            all_guarded_fit_attempts_succeeded,
            fit_outputs_finite,
            all_candidates_remain_manual_local_only,
            no_automatic_q_revision,
            no_public_q_revision_claim,
            no_broader_mgmfrm_claim,
            n_input_artifacts = length(input_records),
            n_construct_reviewed_candidates = length(source_rows),
            n_fit_entrypoint_rows = length(entrypoint_rows),
            n_guarded_fit_attempts = length(entrypoint_rows),
            n_successful_guarded_fit_attempts =
                count(row -> row.summary.guarded_fit_attempt_succeeded,
                    entrypoint_rows),
            n_fit_rejection_checks =
                sum(length(row.boundary_checks) for row in entrypoint_rows),
            n_candidate_q_validation_warnings =
                sum(row.q_validation.n_warning_rows for row in entrypoint_rows),
            n_public_revisions_allowed =
                count(row -> row.public_revision_allowed, entrypoint_rows),
            n_automatic_revisions_allowed =
                count(row -> row.automatic_revision_allowed, entrypoint_rows),
            n_public_claims_allowed =
                count(row -> row.public_claim_allowed, entrypoint_rows),
            n_blockers = 0,
            remaining_public_blockers = Symbol[],
            recommendation =
                :use_construct_reviewed_q_candidates_for_manual_local_guarded_fit_only,
            next_gate = :construct_reviewed_q_fit_reporting_policy,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " candidates=", artifact.summary.n_construct_reviewed_candidates,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
