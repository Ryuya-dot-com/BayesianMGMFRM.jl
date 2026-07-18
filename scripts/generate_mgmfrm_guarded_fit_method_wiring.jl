#!/usr/bin/env julia

using SHA
using TOML

import BayesianMGMFRM
import LogDensityProblems

module MGMFRMChainStudy
include(joinpath(@__DIR__, "generate_mgmfrm_candidate_chain_study.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "mgmfrm_guarded_fit_method_wiring.json")

include(joinpath(@__DIR__, "local_json.jl"))

const CHAIN = MGMFRMChainStudy

const PROTOCOL = (;
    protocol_id = "confirmatory_mgmfrm_guarded_fit_method_wiring_v1",
    review_kind = :local_confirmatory_mgmfrm_guarded_fit_method_wiring,
    publication_or_registration_action = false,
    proposed_entrypoint = "fit(spec; experimental = true)",
    entrypoint_enabled = true,
    public_target_label = :guarded_confirmatory_mgmfrm_logdensity,
    public_target_description =
        "guarded fixed-Q confirmatory MGMFRM log density",
    internal_target_constructor = :_mgmfrm_guarded_local_fit_logdensity,
    target_constructor = :_source_fixture_logdensity,
    transform_constructor = :_mgmfrm_source_constrained_params_from_unconstrained,
    pointwise_constructor = :_mgmfrm_source_pointwise_loglikelihood,
    sampler = (;
        backend = CHAIN.PROTOCOL.backend,
        sampler = CHAIN.PROTOCOL.sampler,
        chains = CHAIN.PROTOCOL.chains,
        warmup = CHAIN.PROTOCOL.warmup,
        draws = CHAIN.PROTOCOL.draws,
        step_size = CHAIN.PROTOCOL.step_size,
        target_accept = CHAIN.PROTOCOL.target_accept,
        max_depth = CHAIN.PROTOCOL.max_depth,
        max_energy_error = CHAIN.PROTOCOL.max_energy_error,
        metric = CHAIN.PROTOCOL.metric,
        ad_backend = CHAIN.PROTOCOL.ad_backend,
        init_jitter = CHAIN.PROTOCOL.init_jitter,
        split_chains = CHAIN.PROTOCOL.split_chains,
        seed = 20260811,
        rhat_threshold = CHAIN.PROTOCOL.thresholds.max_rhat,
        ess_threshold = CHAIN.PROTOCOL.thresholds.min_ess,
    ),
    decision_rules = (;
        require_entrypoint_enabled = true,
        require_non_experimental_fit_rejection = true,
        require_experimental_spec_fit_success = true,
        require_preview_design_experimental_keyword_rejection = true,
        require_unsupported_backend_rejection = true,
        require_target_constructor_available = true,
        require_raw_to_direct_transform_available = true,
        require_artifact_contract_satisfied = true,
        require_candidate_sampler_protocol_passed = true,
        require_pointwise_loglikelihood_shape = true,
        require_no_publication_or_registration_action = true,
        validation_grid_required_before_public_entrypoint = true,
    ),
)

const FIXTURE_REFERENCES = [
    (artifact = :bridge_oracle,
        path = "test/fixtures/source_mgmfrm_bridge_logdensity.json"),
    (artifact = :candidate_chain_study,
        path = "test/fixtures/mgmfrm_candidate_chain_study.json"),
    (artifact = :recovery_smoke_study,
        path = "test/fixtures/mgmfrm_recovery_smoke.json"),
    (artifact = :baseline_comparison,
        path = "test/fixtures/mgmfrm_baseline_comparison.json"),
    (artifact = :sparse_recovery_grid,
        path = "test/fixtures/mgmfrm_sparse_recovery_grid.json"),
]

function usage()
    return """
    Generate the local confirmatory MGMFRM guarded fit method-wiring artifact.

    This records the local target, transform, sampler, artifact-contract, and
    boundary checks for the guarded MGMFRM fit entrypoint. It does not publish,
    register, or promote broad MGMFRM claims.

    Usage:
      julia --project=. scripts/generate_mgmfrm_guarded_fit_method_wiring.jl [--output PATH]
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

function fixture_reference_record(row)
    path = joinpath(ROOT, row.path)
    return (;
        artifact = row.artifact,
        path = row.path,
        exists = isfile(path),
        sha256 = isfile(path) ? file_sha256(path) : missing,
    )
end

function package_record()
    return (;
        name = "BayesianMGMFRM",
        version = project_version(),
        julia_version = string(VERSION),
    )
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

function contract_review_record(contract, artifact)
    required_field_names = [row.field for row in contract.required_fields]
    missing_required_fields =
        [field for field in required_field_names if !(field in keys(artifact))]
    return (;
        schema = contract.schema,
        status = contract.status,
        public_fit = contract.public_fit,
        experimental_public = contract.experimental_public,
        artifact_kind = contract.artifact_kind,
        required_field_names,
        n_required_fields = length(contract.required_fields),
        n_required_provenance_artifacts = length(contract.provenance_rows),
        all_required_fields_present = isempty(missing_required_fields),
        missing_required_fields,
        all_required_provenance_recorded =
            all(row -> row.status === :required, contract.provenance_rows),
        enables_public_fit = contract.summary.enables_public_fit,
    )
end

function q_matrix_record(spec)
    return [[Bool(spec.q_matrix[row, col]) for col in axes(spec.q_matrix, 2)]
        for row in axes(spec.q_matrix, 1)]
end

function sampler_controls_record()
    sampler = PROTOCOL.sampler
    return (;
        backend = sampler.backend,
        sampler = sampler.sampler,
        chains = sampler.chains,
        warmup = sampler.warmup,
        draws = sampler.draws,
        step_size = sampler.step_size,
        target_accept = sampler.target_accept,
        max_depth = sampler.max_depth,
        max_energy_error = sampler.max_energy_error,
        metric = sampler.metric,
        ad_backend = sampler.ad_backend,
        init_jitter = sampler.init_jitter,
        split_chains = sampler.split_chains,
        seed = sampler.seed,
    )
end

function posterior_rows(draws, parameter_names)
    return BayesianMGMFRM._posterior_summary_rows(
        draws,
        parameter_names;
        lower = 0.025,
        upper = 0.975,
        intervals = (0.66, 0.9, 0.95),
        reference = 0.0,
        rope = nothing,
        rope_probability_threshold = 0.95,
    )
end

function fixed_q_policy_records(design, target, diagnostics)
    guarded_target = BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(
        design;
        prior = target.prior,
    )
    initial_logdensity = LogDensityProblems.logdensity(
        guarded_target,
        diagnostics.initial_raw_parameter_values,
    )
    initialization_policy = BayesianMGMFRM._mgmfrm_initialization_policy(
        guarded_target,
        diagnostics.initial_raw_parameter_values,
        diagnostics.initial_direct_parameter_values,
        initial_logdensity,
        (; init_jitter = PROTOCOL.sampler.init_jitter);
        initial_source = :user_supplied_raw,
    )
    return (;
        initialization_policy,
        initialization_rows =
            BayesianMGMFRM._mgmfrm_initialization_rows(initialization_policy),
        fixed_q_invariance_rows =
            BayesianMGMFRM._mgmfrm_fixed_q_invariance_rows(design, diagnostics),
    )
end

function synthetic_fit_artifact(spec, design, target, diagnostics, decision)
    parameter_layout = BayesianMGMFRM.fit_ready_parameter_layout(design)
    raw_posterior_rows =
        posterior_rows(diagnostics.draws, parameter_layout.raw_parameter_names)
    direct_posterior_rows =
        posterior_rows(
            diagnostics.direct_draws,
            parameter_layout.constrained_parameter_names,
        )
    raw_prior_control_manifest =
        BayesianMGMFRM._resolved_generalized_raw_prior_control_manifest(
            decision.raw_prior_control_manifest,
            target.prior,
        )
    fixed_q_policy = fixed_q_policy_records(design, target, diagnostics)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_guarded_fit_artifact_preview.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :guarded_fit_artifact_preview_recorded,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        public_target_label = decision.public_target_label,
        public_target_description = decision.public_target_description,
        internal_target_constructor = decision.internal_target_constructor,
        internal_sampler_diagnostic_constructor =
            decision.internal_sampler_diagnostic_constructor,
        density_space = :raw_unconstrained,
        raw_prior_control_manifest,
        parameter_layout,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        direct_parameter_names = copy(target.blueprint.constrained_parameter_names),
        raw_to_direct_transform = parameter_layout.transforms,
        sampler_controls = sampler_controls_record(),
        diagnostics = (;
            schema = diagnostics.schema,
            summary = diagnostics.summary,
            n_sampler_rows = length(diagnostics.sampler_rows),
            n_parameter_rows = length(diagnostics.parameter_rows),
            n_direct_parameter_rows = length(diagnostics.direct_parameter_rows),
        ),
        pointwise_loglikelihood = diagnostics.direct_pointwise_loglikelihood,
        caveat_docs_artifact = decision.caveat_docs_artifact,
        fixture_provenance = decision.fit_artifact_contract.provenance_rows,
        q_matrix = q_matrix_record(spec),
        latent_correlation = :identity_fixed,
        ability_scale = :standard_normal_by_dimension,
        initialization_policy = fixed_q_policy.initialization_policy,
        initialization_rows = fixed_q_policy.initialization_rows,
        fixed_q_invariance_rows = fixed_q_policy.fixed_q_invariance_rows,
        raw_posterior_row_schema =
            BayesianMGMFRM._posterior_summary_row_schema(
                raw_posterior_rows;
                family = :mgmfrm,
                scope = :minimal_confirmatory_mgmfrm_candidate,
                parameter_space = :raw_unconstrained,
                summary_function = :posterior_summary,
                parameter_names = parameter_layout.raw_parameter_names,
                blocks = parameter_layout.raw_blocks,
                layout = parameter_layout,
            ),
        direct_posterior_row_schema =
            BayesianMGMFRM._posterior_summary_row_schema(
                direct_posterior_rows;
                family = :mgmfrm,
                scope = :minimal_confirmatory_mgmfrm_candidate,
                parameter_space = :constrained_direct,
                summary_function = :direct_posterior_summary,
                parameter_names = parameter_layout.constrained_parameter_names,
                blocks = parameter_layout.constrained_blocks,
                layout = parameter_layout,
            ),
    )
end

function build_artifact()
    spec = CHAIN.confirmatory_mgmfrm_spec()
    design = BayesianMGMFRM.getdesign(spec; preview = true)
    manifest = BayesianMGMFRM.model_manifest(design)
    candidate = manifest.design.raw_parameterization.confirmatory_candidate
    decision = candidate.experimental_public_api_decision
    target = BayesianMGMFRM._source_fixture_logdensity(design)
    diagnostics =
        CHAIN.run_diagnostics(target, CHAIN.NEAR_ORACLE_RAW, PROTOCOL.sampler.seed)
    sampler_protocol_passed = CHAIN.protocol_passed(diagnostics.summary)
    artifact_preview =
        synthetic_fit_artifact(spec, design, target, diagnostics, decision)
    contract_review =
        contract_review_record(decision.fit_artifact_contract, artifact_preview)
    pointwise_shape = collect(size(diagnostics.direct_pointwise_loglikelihood))

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

    fixture_refs = [fixture_reference_record(row) for row in FIXTURE_REFERENCES]
    passed = sampler_protocol_passed &&
        Bool(contract_review.all_required_fields_present) &&
        Bool(contract_review.all_required_provenance_recorded) &&
        pointwise_shape == [PROTOCOL.sampler.draws * PROTOCOL.sampler.chains,
            spec.data.n] &&
        all(check -> Bool(check.passed), boundary_checks) &&
        all(row -> Bool(row.exists), fixture_refs) &&
        !Bool(PROTOCOL.publication_or_registration_action)

    return (;
        schema = "bayesianmgmfrm.mgmfrm_guarded_fit_method_wiring.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :guarded_fit_method_wiring_recorded,
        decision = :enable_guarded_experimental,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        publication_or_registration_action = false,
        package = package_record(),
        protocol = PROTOCOL,
        proposed_entrypoint = PROTOCOL.proposed_entrypoint,
        entrypoint_enabled = true,
        manifest_snapshot = (;
            candidate_status = candidate.status,
            compiler_stage = candidate.compiler_stage,
            public_target_label = decision.public_target_label,
            public_target_description = decision.public_target_description,
            internal_target_constructor = decision.internal_target_constructor,
            experimental_decision_status = decision.status,
            experimental_decision = decision.decision,
            experimental_summary = decision.summary,
        ),
        target_review = (;
            constructor = PROTOCOL.target_constructor,
            type = String(nameof(typeof(target))),
            show = sprint(show, target),
            family = target.blueprint.family,
            scope = target.blueprint.scope,
            n_raw_parameters = target.blueprint.n_parameters,
            n_direct_parameters = length(target.blueprint.constrained_parameter_names),
            raw_parameter_names = copy(target.blueprint.parameter_names),
            direct_parameter_names = copy(target.blueprint.constrained_parameter_names),
        ),
        sampler_review = (;
            schema = diagnostics.schema,
            target = diagnostics.target,
            backend = diagnostics.backend,
            sampler = diagnostics.sampler,
            summary = diagnostics.summary,
            protocol_passed = sampler_protocol_passed,
            n_sampler_rows = length(diagnostics.sampler_rows),
            n_parameter_rows = length(diagnostics.parameter_rows),
            n_direct_parameter_rows = length(diagnostics.direct_parameter_rows),
            n_direct_constraint_rows = length(diagnostics.direct_constraint_rows),
        ),
        artifact_contract_review = contract_review,
        fit_artifact_preview = (;
            schema = artifact_preview.schema,
            status = artifact_preview.status,
            public_fit = artifact_preview.public_fit,
            experimental_public = artifact_preview.experimental_public,
            public_target_label = artifact_preview.public_target_label,
            public_target_description = artifact_preview.public_target_description,
            internal_target_constructor = artifact_preview.internal_target_constructor,
            internal_sampler_diagnostic_constructor =
                artifact_preview.internal_sampler_diagnostic_constructor,
            density_space = artifact_preview.density_space,
            raw_prior_control_schema =
                artifact_preview.raw_prior_control_manifest.schema,
            n_raw_prior_control_rows =
                artifact_preview.raw_prior_control_manifest.n_rows,
            raw_prior_control_all_active_scales_resolved =
                artifact_preview.raw_prior_control_manifest.summary.all_active_scales_resolved,
            raw_prior_control_direct_scale_priors_enabled =
                artifact_preview.raw_prior_control_manifest.summary.direct_scale_generalized_priors_enabled,
            parameter_layout_schema = artifact_preview.parameter_layout.schema,
            parameter_layout_scope = artifact_preview.parameter_layout.scope,
            raw_to_direct_transform_count =
                length(artifact_preview.raw_to_direct_transform),
            raw_parameter_count = length(artifact_preview.raw_parameter_names),
            direct_parameter_count = length(artifact_preview.direct_parameter_names),
            raw_posterior_row_schema =
                artifact_preview.raw_posterior_row_schema.schema,
            raw_posterior_row_fields =
                artifact_preview.raw_posterior_row_schema.row_fields,
            direct_posterior_row_schema =
                artifact_preview.direct_posterior_row_schema.schema,
            direct_posterior_row_fields =
                artifact_preview.direct_posterior_row_schema.row_fields,
            pointwise_loglikelihood_shape = pointwise_shape,
            q_matrix = artifact_preview.q_matrix,
            latent_correlation = artifact_preview.latent_correlation,
            ability_scale = artifact_preview.ability_scale,
            initialization_policy = artifact_preview.initialization_policy,
            initialization_rows = artifact_preview.initialization_rows,
            n_initialization_rows =
                length(artifact_preview.initialization_rows),
            fixed_q_invariance_rows =
                artifact_preview.fixed_q_invariance_rows,
            n_fixed_q_invariance_rows =
                length(artifact_preview.fixed_q_invariance_rows),
            caveat_docs_artifact = artifact_preview.caveat_docs_artifact,
            n_fixture_provenance_rows =
                length(artifact_preview.fixture_provenance),
        ),
        fixture_references = fixture_refs,
        fit_boundary_checks = boundary_checks,
        fit_rejection_checks = boundary_checks,
        decision_record = (;
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            public_exposure_support =
                :method_wiring_satisfies_guarded_entrypoint_boundary,
            interpretation =
                :confirmatory_mgmfrm_guarded_fit_method_wiring_recorded_entrypoint_enabled,
            required_followup = :mgmfrm_guarded_fit_validation_grid,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            entrypoint_enabled = true,
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            target_constructor_available = true,
            raw_to_direct_transform_available = true,
            sampler_protocol_passed,
            artifact_contract_satisfied =
                Bool(contract_review.all_required_fields_present) &&
                Bool(contract_review.all_required_provenance_recorded),
            pointwise_loglikelihood_shape_valid =
                pointwise_shape == [PROTOCOL.sampler.draws * PROTOCOL.sampler.chains,
                    spec.data.n],
            all_fit_boundary_checks_passed =
                all(check -> Bool(check.passed), boundary_checks),
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
            all_fixture_references_present = all(row -> Bool(row.exists),
                fixture_refs),
            n_fit_boundary_checks = length(boundary_checks),
            n_fixture_references = length(fixture_refs),
            remaining_public_blockers =
                [:mgmfrm_guarded_fit_validation_grid_missing],
            recommendation =
                :guarded_entrypoint_enabled_validate_grid_next,
            next_gate = :mgmfrm_guarded_fit_validation_grid,
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
