#!/usr/bin/env julia

using TOML

import BayesianMGMFRM

module GMFRMRecoverySmoke
include(joinpath(@__DIR__, "generate_gmfrm_recovery_smoke.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_guarded_fit_method_wiring.json")

include(joinpath(@__DIR__, "local_json.jl"))

const SMOKE = GMFRMRecoverySmoke

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_guarded_fit_method_wiring_v1",
    review_kind = :local_guarded_experimental_fit_method_wiring,
    publication_or_registration_action = false,
    proposed_entrypoint = "fit(spec; experimental = true)",
    entrypoint_enabled = true,
    superseded_by_experimental_fit_validation_grid = true,
    superseded_by_posterior_predictive_grid = true,
    superseded_by_sparse_pathology_recovery_grid = true,
    public_target_label = :guarded_scalar_gmfrm_logdensity,
    public_target_description = "guarded scalar GMFRM log density",
    internal_target_constructor = :_gmfrm_promotion_candidate_logdensity,
    internal_diagnostics_constructor =
        :_gmfrm_promotion_candidate_sampler_diagnostics,
    target_constructor = :_gmfrm_promotion_candidate_logdensity,
    diagnostics_constructor = :_gmfrm_promotion_candidate_sampler_diagnostics,
    sampler = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 2,
        warmup = 4,
        draws = 4,
        step_size = 0.03,
        target_accept = 0.8,
        max_depth = 8,
        max_energy_error = 1000.0,
        metric = :unit,
        ad_backend = :ForwardDiff,
        seed = 20260627,
        rhat_threshold = 100.0,
        ess_threshold = 1.0,
    ),
    decision_rules = (;
        require_specified_only_public_fit_rejection = true,
        require_guarded_experimental_fit_success = true,
        require_gmfrm_fit_type = true,
        require_artifact_contract_satisfied = true,
        require_pointwise_loglikelihood_shape = true,
        require_waic_and_loo_finite = true,
        require_unsupported_public_options_rejected = true,
        require_no_publication_or_registration_action = true,
        sparse_pathology_recovery_grid_required_before_broader_exposure = true,
    ),
)

function usage()
    return """
    Generate the local scalar GMFRM guarded fit method-wiring artifact.

    This records that the narrow `fit(spec; experimental = true)` scalar GMFRM
    entrypoint is wired locally. It does not publish, register, or broaden the
    supported generalized model surface.

    Usage:
      julia --project=. scripts/generate_gmfrm_guarded_fit_method_wiring.jl [--output PATH]
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

function package_record()
    return (;
        name = "BayesianMGMFRM",
        version = project_version(),
        julia_version = string(VERSION),
    )
end

function method_context()
    table = SMOKE.placeholder_table()
    data = SMOKE.facet_data(table)
    spec = BayesianMGMFRM.mfrm_spec(data; family = :gmfrm, discrimination = :rater)
    preview = BayesianMGMFRM.getdesign(spec; preview = true)
    dff_table = merge(table, (;
        group = [isodd(index) ? "A" : "B" for index in eachindex(table.score)],
    ))
    dff_data = BayesianMGMFRM.FacetData(dff_table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :group)
    dff_spec = BayesianMGMFRM.mfrm_spec(
        dff_data;
        family = :gmfrm,
        discrimination = :rater,
        bias = [(:rater, :group)])
    item_discrimination_spec =
        BayesianMGMFRM.mfrm_spec(data; family = :gmfrm, discrimination = :item)
    mgmfrm_spec = BayesianMGMFRM.mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix = Bool[1 0; 0 1; 1 0],
    )
    return (;
        table,
        data,
        spec,
        preview,
        dff_spec,
        item_discrimination_spec,
        mgmfrm_spec,
    )
end

function rejection_check(
        name::Symbol,
        callable;
        legacy_blocked_option = missing,
        legacy_next_gate = missing,
        required_guidance = ())
    try
        callable()
        return (;
            check = name,
            rejected = false,
            error_type = missing,
            message = missing,
            blocked_option = missing,
            next_gate = missing,
            actionable_gate_message = false,
        )
    catch err
        message = portable_error_message(err)
        actionable_gate_message = !isempty(required_guidance) &&
            all(fragment -> occursin(fragment, message), required_guidance)
        return (;
            check = name,
            rejected = true,
            error_type = String(nameof(typeof(err))),
            message,
            # Retain the v1 artifact fields as compatibility metadata. Public
            # errors intentionally use reader-facing guidance instead of these
            # maintainer identifiers.
            blocked_option = legacy_blocked_option,
            next_gate = legacy_next_gate,
            actionable_gate_message,
        )
    end
end

rejection_check(callable, name::Symbol; kwargs...) =
    rejection_check(name, callable; kwargs...)

function sampler_kwargs()
    sampler = PROTOCOL.sampler
    return (;
        backend = sampler.backend,
        ndraws = sampler.draws,
        warmup = sampler.warmup,
        chains = sampler.chains,
        step_size = sampler.step_size,
        target_accept = sampler.target_accept,
        max_depth = sampler.max_depth,
        max_energy_error = sampler.max_energy_error,
        metric = sampler.metric,
        ad_backend = sampler.ad_backend,
        seed = sampler.seed,
        rhat_threshold = sampler.rhat_threshold,
        ess_threshold = sampler.ess_threshold,
    )
end

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
        required_provenance = [row.artifact for row in contract.provenance_rows],
        n_required_fields = length(contract.required_fields),
        n_required_provenance_artifacts = length(contract.provenance_rows),
        all_required_fields_present = isempty(missing_required_fields),
        missing_required_fields,
        all_required_provenance_recorded =
            all(row -> row.status === :required, contract.provenance_rows),
        enables_public_fit = contract.summary.enables_public_fit,
    )
end

function finite_criterion_summary(stat)
    numeric_values = Float64[]
    for key in keys(stat)
        value = getproperty(stat, key)
        value isa Real || continue
        push!(numeric_values, Float64(value))
    end
    return (;
        criterion = stat.criterion,
        n_draws = stat.n_draws,
        n_observations = stat.n_observations,
        all_top_level_numeric_finite = all(isfinite, numeric_values),
        warning = stat.warning,
    )
end

function build_artifact()
    context = method_context()
    manifest = BayesianMGMFRM.model_manifest(context.preview)
    candidate = manifest.design.raw_parameterization.promotion_candidate
    decision = candidate.experimental_public_api
    fit = BayesianMGMFRM.fit(context.spec; experimental = true, sampler_kwargs()...)
    metadata = BayesianMGMFRM.fit_metadata(fit)
    diagnostic_surface = BayesianMGMFRM.diagnostics(
        fit;
        rhat_threshold = PROTOCOL.sampler.rhat_threshold,
        ess_threshold = PROTOCOL.sampler.ess_threshold,
    )
    artifact = BayesianMGMFRM.fit_artifact(
        fit;
        include_environment = false,
        rhat_threshold = PROTOCOL.sampler.rhat_threshold,
        ess_threshold = PROTOCOL.sampler.ess_threshold,
    )
    pointwise = BayesianMGMFRM.pointwise_loglikelihood_matrix(fit)
    waic_stat = BayesianMGMFRM.waic(fit)
    loo_stat = BayesianMGMFRM.loo(fit; min_tail_draws = 2)
    waic_rows = BayesianMGMFRM.waic_diagnostics(fit)
    loo_rows = BayesianMGMFRM.loo_diagnostics(fit; min_tail_draws = 2)

    rejection_checks = [
        rejection_check(:fit_specified_only_gmfrm_without_experimental) do
            BayesianMGMFRM.fit(context.spec; ndraws = 1, warmup = 0)
        end,
        rejection_check(:fit_preview_design_with_experimental_keyword) do
            BayesianMGMFRM.fit(
                context.preview;
                experimental = true,
                ndraws = 1,
                warmup = 0,
            )
        end,
        rejection_check(
            :fit_experimental_unsupported_backend;
            legacy_blocked_option = :backend,
            legacy_next_gate = :advancedhmc_guarded_sampler_policy,
            required_guidance = (
                "does not support backend = :julia",
                "Supported configuration:",
                "backend = :advancedhmc",
            ),
        ) do
            BayesianMGMFRM.fit(
                context.spec;
                experimental = true,
                backend = :julia,
                ndraws = 1,
                warmup = 0,
            )
        end,
        rejection_check(
            :fit_experimental_public_mfrm_prior;
            legacy_blocked_option = :prior,
            legacy_next_gate = :scalar_gmfrm_prior_likelihood_sensitivity_grid,
            required_guidance = (
                "does not support prior = :MFRMPrior",
                "Supported configuration:",
                "Omit `prior`",
            ),
        ) do
            BayesianMGMFRM.fit(
                context.spec;
                experimental = true,
                prior = BayesianMGMFRM.MFRMPrior(),
                ndraws = 1,
                warmup = 0,
            )
        end,
        rejection_check(
            :fit_experimental_dff_effects;
            legacy_blocked_option = :dff_effects,
            legacy_next_gate = :gmfrm_dff_estimand_validation_grid,
            required_guidance = (
                "does not support dff_effects =",
                "Supported configuration:",
                "not fitted model effects",
            ),
        ) do
            BayesianMGMFRM.fit(
                context.dff_spec;
                experimental = true,
                ndraws = 1,
                warmup = 0,
            )
        end,
        rejection_check(
            :fit_experimental_non_rater_discrimination;
            legacy_blocked_option = :discrimination,
            legacy_next_gate = :item_discrimination_promotion_decision,
            required_guidance = (
                "does not support discrimination = :item",
                "Supported configuration:",
                "discrimination = (:rater,)",
            ),
        ) do
            BayesianMGMFRM.fit(
                context.item_discrimination_spec;
                experimental = true,
                ndraws = 1,
                warmup = 0,
            )
        end,
    ]

    contract_review = contract_review_record(
        decision.fit_artifact_contract,
        artifact,
    )
    pointwise_shape = collect(size(pointwise))
    draws_shape = collect(size(fit.draws))
    direct_draws_shape = collect(size(fit.direct_draws))
    required_actionable_gate_checks = Set([
        :fit_experimental_unsupported_backend,
        :fit_experimental_public_mfrm_prior,
        :fit_experimental_dff_effects,
        :fit_experimental_non_rater_discrimination,
    ])
    actionable_gate_messages_passed = all(check ->
            !(check.check in required_actionable_gate_checks) ||
            Bool(check.actionable_gate_message),
        rejection_checks)
    rater_step_public_option_policy_recorded =
        decision.rater_step_public_option_policy.public_keyword_enabled === false &&
        decision.rater_step_public_option_policy.next_gate ===
            :rater_step_public_option_policy
    item_discrimination_promotion_decision_recorded =
        decision.item_discrimination_promotion_decision.decision ===
            :keep_preview_only_for_v0_1_1 &&
        decision.item_discrimination_promotion_decision.next_gate ===
            :item_discrimination_promotion_decision
    passed = fit isa BayesianMGMFRM.GMFRMFit &&
        Bool(metadata.public_fit) &&
        Bool(metadata.experimental_public) &&
        artifact.schema == "bayesianmgmfrm.gmfrm_experimental_fit_artifact.v1" &&
        diagnostic_surface.schema ==
            "bayesianmgmfrm.gmfrm_experimental_fit_diagnostics.v1" &&
        Bool(contract_review.all_required_fields_present) &&
        Bool(contract_review.all_required_provenance_recorded) &&
        pointwise_shape == [PROTOCOL.sampler.draws * PROTOCOL.sampler.chains,
            context.data.n] &&
        all(check -> Bool(check.rejected), rejection_checks) &&
        actionable_gate_messages_passed &&
        rater_step_public_option_policy_recorded &&
        item_discrimination_promotion_decision_recorded &&
        all(isfinite, [waic_stat.elpd_waic, waic_stat.waic, loo_stat.elpd_loo,
            loo_stat.looic]) &&
        !Bool(PROTOCOL.publication_or_registration_action)

    return (;
        schema = "bayesianmgmfrm.gmfrm_guarded_fit_method_wiring.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :guarded_experimental_fit_method_wired,
        decision = :enable_guarded_experimental,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        package = package_record(),
        protocol = PROTOCOL,
        proposed_entrypoint = decision.proposed_entrypoint,
        entrypoint_enabled = true,
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
            experimental_public_ready = candidate.experimental_public_ready,
            decision_public_target_label = decision.public_target_label,
            decision_internal_target_constructor =
                decision.internal_target_constructor,
            decision_rater_step_public_option_policy =
                decision.rater_step_public_option_policy,
            decision_item_discrimination_promotion_decision =
                decision.item_discrimination_promotion_decision,
            experimental_decision_status = decision.status,
            experimental_decision = decision.decision,
            experimental_summary = decision.summary,
        ),
        fit_record = (;
            type = String(nameof(typeof(fit))),
            show = sprint(show, fit),
            backend = fit.backend,
            sampler = fit.sampler,
            raw_draws_shape = draws_shape,
            direct_draws_shape,
            pointwise_loglikelihood_shape = pointwise_shape,
            n_chain_acceptance_rates = length(fit.chain_acceptance_rate),
            n_sampler_stats = length(fit.sampler_stats),
        ),
        metadata_review = (;
            family = metadata.family,
            dimensions = metadata.dimensions,
            discrimination = metadata.discrimination,
            public_fit = metadata.public_fit,
            experimental_public = metadata.experimental_public,
            density_space = metadata.density_space,
            n_draws = metadata.n_draws,
            n_chains = metadata.n_chains,
            draws_per_chain = metadata.draws_per_chain,
            n_parameters = metadata.n_parameters,
            n_direct_parameters = metadata.n_direct_parameters,
        ),
        diagnostics_review = (;
            schema = diagnostic_surface.schema,
            public_fit = diagnostic_surface.public_fit,
            experimental_public = diagnostic_surface.experimental_public,
            summary = diagnostic_surface.summary,
            n_sampler_rows = length(diagnostic_surface.sampler_rows),
            n_parameter_rows = length(diagnostic_surface.parameter_rows),
            n_direct_parameter_rows =
                length(diagnostic_surface.direct_parameter_rows),
        ),
        artifact_contract_review = contract_review,
        artifact_review = (;
            schema = artifact.schema,
            status = artifact.status,
            public_fit = artifact.public_fit,
            experimental_public = artifact.experimental_public,
            fit_ready = artifact.fit_ready,
            public_target_label = artifact.public_target_label,
            public_target_description = artifact.public_target_description,
            internal_target_constructor = artifact.internal_target_constructor,
            internal_sampler_diagnostic_constructor =
                artifact.internal_sampler_diagnostic_constructor,
            density_space = artifact.density_space,
            raw_prior_control_schema =
                artifact.raw_prior_control_manifest.schema,
            n_raw_prior_control_rows =
                artifact.raw_prior_control_manifest.n_rows,
            raw_prior_control_all_active_scales_resolved =
                artifact.raw_prior_control_manifest.summary.all_active_scales_resolved,
            raw_prior_control_direct_scale_priors_enabled =
                artifact.raw_prior_control_manifest.summary.direct_scale_generalized_priors_enabled,
            raw_parameter_count = length(artifact.raw_parameter_names),
            direct_parameter_count = length(artifact.direct_parameter_names),
            pointwise_loglikelihood_shape = collect(size(artifact.pointwise_loglikelihood)),
            caveat_docs_artifact = artifact.caveat_docs_artifact,
            n_fixture_provenance_rows = length(artifact.fixture_provenance),
        ),
        waic_review = finite_criterion_summary(waic_stat),
        loo_review = finite_criterion_summary(loo_stat),
        information_criterion_rows = (;
            n_waic_rows = length(waic_rows),
            n_loo_rows = length(loo_rows),
        ),
        fit_rejection_checks = rejection_checks,
        decision_record = (;
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            public_exposure_support =
                :satisfied_by_sparse_pathology_recovery_grid,
            interpretation =
                :guarded_scalar_gmfrm_experimental_fit_method_wired_validated_ppc_and_sparse_pathology_checked_locally,
            required_followup = :scalar_gmfrm_prior_likelihood_sensitivity_grid,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            entrypoint_enabled = true,
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            gmfrm_fit_returned = fit isa BayesianMGMFRM.GMFRMFit,
            artifact_contract_satisfied =
                Bool(contract_review.all_required_fields_present) &&
                Bool(contract_review.all_required_provenance_recorded),
            pointwise_loglikelihood_shape_valid =
                pointwise_shape == [PROTOCOL.sampler.draws * PROTOCOL.sampler.chains,
                    context.data.n],
            waic_and_loo_finite = all(isfinite, [waic_stat.elpd_waic,
                waic_stat.waic, loo_stat.elpd_loo, loo_stat.looic]),
            all_unsupported_public_options_rejected =
                all(check -> Bool(check.rejected), rejection_checks),
            actionable_gate_messages_passed,
            n_actionable_gate_messages =
                count(check -> Bool(check.actionable_gate_message),
                    rejection_checks),
            rater_step_public_option_policy_recorded,
            item_discrimination_promotion_decision_recorded,
            n_rejection_checks = length(rejection_checks),
            superseded_by_experimental_fit_validation_grid = true,
            superseded_by_posterior_predictive_grid = true,
            superseded_by_sparse_pathology_recovery_grid = true,
            remaining_public_blockers =
                [:scalar_gmfrm_prior_likelihood_sensitivity_grid_missing],
            recommendation =
                :keep_guarded_experimental_until_prior_likelihood_sensitivity_grid,
            next_gate = :scalar_gmfrm_prior_likelihood_sensitivity_grid,
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
