#!/usr/bin/env julia

using Random
using SHA
using TOML

import BayesianMGMFRM

module GMFRMRecoverySmoke
include(joinpath(@__DIR__, "generate_gmfrm_recovery_smoke.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_experimental_fit_validation_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

const SMOKE = GMFRMRecoverySmoke

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_experimental_fit_validation_grid_v1",
    review_kind = :local_guarded_experimental_fit_validation_grid,
    publication_or_registration_action = false,
    entrypoint_under_validation = "fit(spec; experimental = true)",
    superseded_by_posterior_predictive_grid = true,
    superseded_by_sparse_pathology_recovery_grid = true,
    simulation_source = :scalar_gmfrm_baseline_calibration_grid_scenarios,
    data_grid = SMOKE.PROTOCOL.grid,
    sampler = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 2,
        warmup = 12,
        draws = 12,
        step_size = 0.03,
        target_accept = 0.85,
        max_depth = 8,
        max_energy_error = 1000.0,
        metric = :unit,
        ad_backend = :ForwardDiff,
        init_jitter = 0.0,
        split_chains = true,
    ),
    diagnostics = (;
        rhat_threshold = 100.0,
        ess_threshold = 1.0,
        loo_min_tail_draws = 5,
    ),
    thresholds = (;
        n_scenarios = 3,
        n_observations = SMOKE.PROTOCOL.grid.observations,
        require_guarded_fit_returned = true,
        require_public_fit_metadata = true,
        require_artifact_contract_satisfied = true,
        require_pointwise_shape = true,
        require_information_criteria_finite = true,
        require_no_divergences = true,
        require_no_max_treedepth = true,
        require_no_failed_direct_constraints = true,
        require_no_nonfinite_logdensity = true,
        require_no_nonfinite_direct_loglikelihood = true,
        max_direct_parameter_mean_absolute_error = 5.0,
        max_direct_block_mean_absolute_error = 3.0,
    ),
)

const SCENARIOS = [
    (;
        scenario = :near_rasch,
        simulation_seed = 20260751,
        fit_seed = 20260851,
        raw_truth = [
            -0.4, -0.1, 0.1, 0.4,
            -0.2, 0.0, 0.2,
            -0.15, 0.15,
            log(1.05), log(0.95),
            log(1.05), log(0.95), log(1.0),
            0.1, -0.05, 0.0,
        ],
    ),
    (;
        scenario = :moderate_generalized,
        simulation_seed = SMOKE.PROTOCOL.simulation_seed,
        fit_seed = 20260852,
        raw_truth = SMOKE.TRUTH_RAW,
    ),
    (;
        scenario = :stronger_generalized,
        simulation_seed = 20260758,
        fit_seed = 20260853,
        raw_truth = [
            -0.8, -0.25, 0.25, 0.8,
            -0.45, 0.05, 0.4,
            -0.4, 0.2,
            log(1.6), log(0.7),
            log(1.4), log(0.75), log(1.1),
            0.35, -0.25, 0.1,
        ],
    ),
]

function usage()
    return """
    Generate the local scalar GMFRM experimental fit validation-grid artifact.

    The grid runs the guarded `fit(spec; experimental = true)` method over
    fixed scalar GMFRM simulation scenarios. It validates artifact shape and
    diagnostics; it does not publish, register, or broaden the generalized
    model surface.

    Usage:
      julia --project=. scripts/generate_gmfrm_experimental_fit_validation_grid.jl [--output PATH]
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

function score_count_rows(scores)
    return [(score = value, n = count(==(value), scores))
        for value in sort(unique(scores))]
end

function mean_float(values)
    return sum(Float64, values) / length(values)
end

function sd_float(values, mean_value::Float64)
    n = length(values)
    n <= 1 && return NaN
    ss = sum((Float64(value) - mean_value)^2 for value in values)
    return sqrt(ss / (n - 1))
end

function raw_truth_hash(raw_truth)
    return bytes2hex(sha256(codeunits(join(raw_truth, "\n"))))
end

function table_for_scenario(spec)
    placeholder_design = SMOKE.scalar_gmfrm_design(SMOKE.placeholder_table())
    direct_truth =
        BayesianMGMFRM._gmfrm_source_constrained_params_from_unconstrained(
            placeholder_design,
            spec.raw_truth,
        )
    scores = SMOKE.sample_scores(
        placeholder_design,
        direct_truth;
        rng = MersenneTwister(spec.simulation_seed),
    )
    base = SMOKE.placeholder_table()
    return (;
        placeholder_design,
        direct_truth,
        table = (;
            examinee = base.examinee,
            rater = base.rater,
            item = base.item,
            score = scores,
        ),
    )
end

function sampler_kwargs(seed::Int)
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
        init_jitter = sampler.init_jitter,
        seed,
        rhat_threshold = PROTOCOL.diagnostics.rhat_threshold,
        ess_threshold = PROTOCOL.diagnostics.ess_threshold,
        progress = false,
    )
end

function diagnostic_kwargs()
    return (;
        split_chains = PROTOCOL.sampler.split_chains,
        rhat_threshold = PROTOCOL.diagnostics.rhat_threshold,
        ess_threshold = PROTOCOL.diagnostics.ess_threshold,
    )
end

function parameter_block(design, index::Int)
    for block in sort(collect(keys(design.blocks)); by = string)
        index in design.blocks[block] && return block
    end
    return :unknown
end

function direct_recovery_rows(fit, truth_direct)
    size(fit.direct_draws, 2) == length(truth_direct) ||
        error("direct truth length does not match fit direct draws")
    rows = NamedTuple[]
    for index in axes(fit.direct_draws, 2)
        values = Float64.(fit.direct_draws[:, index])
        posterior_mean = mean_float(values)
        posterior_sd = sd_float(values, posterior_mean)
        true_value = Float64(truth_direct[index])
        bias = posterior_mean - true_value
        push!(rows, (;
            parameter = fit.diagnostic_surface.direct_parameter_names[index],
            parameter_index = index,
            block = parameter_block(fit.design, index),
            true_value,
            posterior_mean,
            posterior_sd,
            bias,
            absolute_bias = abs(bias),
            finite = isfinite(posterior_mean) && isfinite(true_value),
        ))
    end
    return rows
end

function direct_recovery_by_block(rows)
    blocks = sort(unique(row.block for row in rows); by = string)
    out = NamedTuple[]
    for block in blocks
        block_rows = [row for row in rows if row.block === block]
        push!(out, (;
            block,
            n_parameters = length(block_rows),
            mean_absolute_error =
                mean_float([row.absolute_bias for row in block_rows]),
            max_absolute_error =
                maximum(row.absolute_bias for row in block_rows),
            all_finite = all(row -> row.finite, block_rows),
        ))
    end
    return out
end

function finite_stat_summary(stat)
    values = Float64[]
    for key in keys(stat)
        value = getproperty(stat, key)
        value isa Real || continue
        push!(values, Float64(value))
    end
    return (;
        criterion = stat.criterion,
        n_draws = stat.n_draws,
        n_observations = stat.n_observations,
        warning = stat.warning,
        all_top_level_numeric_finite = all(isfinite, values),
    )
end

function contract_review_record(contract, artifact)
    required = [row.field for row in contract.required_fields]
    missing_required = [field for field in required if !(field in keys(artifact))]
    return (;
        schema = contract.schema,
        status = contract.status,
        public_fit = contract.public_fit,
        experimental_public = contract.experimental_public,
        artifact_kind = contract.artifact_kind,
        n_required_fields = length(required),
        n_required_provenance_artifacts = length(contract.provenance_rows),
        all_required_fields_present = isempty(missing_required),
        missing_required_fields = missing_required,
        all_required_provenance_recorded =
            all(row -> row.status === :required, contract.provenance_rows),
        enables_public_fit = contract.summary.enables_public_fit,
    )
end

function pointwise_shape_valid(pointwise, data)
    return collect(size(pointwise)) == [
        PROTOCOL.sampler.draws * PROTOCOL.sampler.chains,
        data.n,
    ]
end

function scenario_record(spec)
    simulated = table_for_scenario(spec)
    data = SMOKE.facet_data(simulated.table)
    gmfrm_spec = BayesianMGMFRM.mfrm_spec(
        data;
        family = :gmfrm,
        discrimination = :rater,
    )
    fit = BayesianMGMFRM.fit(
        gmfrm_spec;
        experimental = true,
        sampler_kwargs(spec.fit_seed)...,
    )
    metadata = BayesianMGMFRM.fit_metadata(fit)
    diagnostics = BayesianMGMFRM.diagnostics(fit; diagnostic_kwargs()...)
    artifact = BayesianMGMFRM.fit_artifact(
        fit;
        include_environment = false,
        diagnostic_kwargs()...,
    )
    manifest = BayesianMGMFRM.model_manifest(fit.design)
    contract =
        manifest.design.raw_parameterization.promotion_candidate.
        experimental_public_api.fit_artifact_contract
    contract_review = contract_review_record(contract, artifact)
    pointwise = BayesianMGMFRM.pointwise_loglikelihood_matrix(fit)
    waic_stat = BayesianMGMFRM.waic(fit)
    loo_stat = BayesianMGMFRM.loo(
        fit;
        min_tail_draws = PROTOCOL.diagnostics.loo_min_tail_draws,
    )
    waic_rows = BayesianMGMFRM.waic_diagnostics(fit)
    loo_rows = BayesianMGMFRM.loo_diagnostics(
        fit;
        min_tail_draws = PROTOCOL.diagnostics.loo_min_tail_draws,
    )
    preview = BayesianMGMFRM.getdesign(gmfrm_spec; preview = true)
    truth_direct =
        BayesianMGMFRM._gmfrm_source_constrained_params_from_unconstrained(
            preview,
            spec.raw_truth,
        )
    recovery_rows = direct_recovery_rows(fit, truth_direct)
    recovery_by_block = direct_recovery_by_block(recovery_rows)
    diagnostic_summary = diagnostics.summary
    information_criteria_finite =
        isfinite(waic_stat.elpd_waic) && isfinite(waic_stat.waic) &&
        isfinite(loo_stat.elpd_loo) && isfinite(loo_stat.looic)
    passed = fit isa BayesianMGMFRM.GMFRMFit &&
        Bool(metadata.public_fit) &&
        Bool(metadata.experimental_public) &&
        Bool(diagnostics.public_fit) &&
        Bool(diagnostics.experimental_public) &&
        Bool(contract_review.all_required_fields_present) &&
        Bool(contract_review.all_required_provenance_recorded) &&
        pointwise_shape_valid(pointwise, data) &&
        all(isfinite, pointwise) &&
        all(isfinite, fit.log_posterior) &&
        all(isfinite, fit.direct_loglikelihood) &&
        all(isfinite, fit.direct_pointwise_loglikelihood) &&
        information_criteria_finite &&
        diagnostic_summary.n_divergences == 0 &&
        diagnostic_summary.n_max_treedepth == 0 &&
        diagnostic_summary.n_failed_direct_constraints == 0 &&
        diagnostic_summary.n_nonfinite_logdensity == 0 &&
        diagnostic_summary.n_nonfinite_direct_loglikelihood == 0 &&
        all(row -> row.finite, recovery_rows) &&
        maximum(row.absolute_bias for row in recovery_rows) <=
            PROTOCOL.thresholds.max_direct_parameter_mean_absolute_error &&
        maximum(row.mean_absolute_error for row in recovery_by_block) <=
            PROTOCOL.thresholds.max_direct_block_mean_absolute_error

    return (;
        scenario = spec.scenario,
        simulation_seed = spec.simulation_seed,
        fit_seed = spec.fit_seed,
        raw_truth_sha256 = raw_truth_hash(spec.raw_truth),
        simulated_data = (;
            n_observations = data.n,
            score_counts = score_count_rows(simulated.table.score),
            person_levels = data.person_levels,
            rater_levels = data.rater_levels,
            item_levels = data.item_levels,
            category_levels = data.category_levels,
        ),
        fit_record = (;
            type = String(nameof(typeof(fit))),
            backend = fit.backend,
            sampler = fit.sampler,
            raw_draws_shape = collect(size(fit.draws)),
            direct_draws_shape = collect(size(fit.direct_draws)),
            pointwise_loglikelihood_shape = collect(size(pointwise)),
        ),
        metadata_review = (;
            public_fit = metadata.public_fit,
            experimental_public = metadata.experimental_public,
            family = metadata.family,
            dimensions = metadata.dimensions,
            discrimination = metadata.discrimination,
            n_draws = metadata.n_draws,
            n_chains = metadata.n_chains,
            draws_per_chain = metadata.draws_per_chain,
            n_parameters = metadata.n_parameters,
            n_direct_parameters = metadata.n_direct_parameters,
        ),
        diagnostics_review = (;
            schema = diagnostics.schema,
            public_fit = diagnostics.public_fit,
            experimental_public = diagnostics.experimental_public,
            summary = diagnostics.summary,
        ),
        artifact_review = (;
            schema = artifact.schema,
            public_fit = artifact.public_fit,
            experimental_public = artifact.experimental_public,
            fit_ready = artifact.fit_ready,
            density_space = artifact.density_space,
            raw_prior_control_schema =
                artifact.raw_prior_control_manifest.schema,
            n_raw_prior_control_rows =
                artifact.raw_prior_control_manifest.n_rows,
            raw_prior_control_all_active_scales_resolved =
                artifact.raw_prior_control_manifest.summary.all_active_scales_resolved,
            raw_prior_control_direct_scale_priors_enabled =
                artifact.raw_prior_control_manifest.summary.direct_scale_generalized_priors_enabled,
            pointwise_loglikelihood_shape =
                collect(size(artifact.pointwise_loglikelihood)),
            n_fixture_provenance_rows = length(artifact.fixture_provenance),
        ),
        artifact_contract_review = contract_review,
        waic_review = finite_stat_summary(waic_stat),
        loo_review = finite_stat_summary(loo_stat),
        information_criterion_rows = (;
            n_waic_rows = length(waic_rows),
            n_loo_rows = length(loo_rows),
        ),
        direct_recovery_rows = recovery_rows,
        direct_recovery_by_block = recovery_by_block,
        summary = (;
            passed,
            pointwise_shape_valid = pointwise_shape_valid(pointwise, data),
            artifact_contract_satisfied =
                Bool(contract_review.all_required_fields_present) &&
                Bool(contract_review.all_required_provenance_recorded),
            information_criteria_finite,
            n_divergences = diagnostic_summary.n_divergences,
            n_max_treedepth = diagnostic_summary.n_max_treedepth,
            n_failed_direct_constraints =
                diagnostic_summary.n_failed_direct_constraints,
            n_nonfinite_logdensity = diagnostic_summary.n_nonfinite_logdensity,
            n_nonfinite_direct_loglikelihood =
                diagnostic_summary.n_nonfinite_direct_loglikelihood,
            max_direct_parameter_mean_absolute_error =
                maximum(row.absolute_bias for row in recovery_rows),
            max_direct_block_mean_absolute_error =
                maximum(row.mean_absolute_error for row in recovery_by_block),
        ),
    )
end

function grid_artifact()
    scenarios = [scenario_record(spec) for spec in SCENARIOS]
    passed = all(scenario -> scenario.summary.passed, scenarios)
    return (;
        schema = "bayesianmgmfrm.gmfrm_experimental_fit_validation_grid.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :guarded_experimental_fit_validation_grid_recorded,
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
        scenarios,
        decision_record = (;
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            public_exposure_support =
                :satisfied_by_sparse_pathology_recovery_grid,
            interpretation =
                :guarded_scalar_gmfrm_experimental_fit_validation_grid_passed_ppc_and_sparse_pathology_checked,
            required_followup = :scalar_gmfrm_prior_likelihood_sensitivity_grid,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            n_scenarios = length(scenarios),
            n_passed_scenarios = count(scenario -> scenario.summary.passed, scenarios),
            n_total_draws_per_scenario =
                PROTOCOL.sampler.draws * PROTOCOL.sampler.chains,
            all_guarded_fit_returned =
                all(scenario -> String(scenario.fit_record.type) == "GMFRMFit", scenarios),
            all_artifact_contracts_satisfied =
                all(scenario -> scenario.summary.artifact_contract_satisfied, scenarios),
            all_pointwise_shapes_valid =
                all(scenario -> scenario.summary.pointwise_shape_valid, scenarios),
            all_information_criteria_finite =
                all(scenario -> scenario.summary.information_criteria_finite, scenarios),
            all_no_divergences =
                all(scenario -> scenario.summary.n_divergences == 0, scenarios),
            all_no_max_treedepth =
                all(scenario -> scenario.summary.n_max_treedepth == 0, scenarios),
            all_no_failed_direct_constraints =
                all(scenario -> scenario.summary.n_failed_direct_constraints == 0, scenarios),
            max_direct_parameter_mean_absolute_error =
                maximum(scenario.summary.max_direct_parameter_mean_absolute_error
                    for scenario in scenarios),
            max_direct_block_mean_absolute_error =
                maximum(scenario.summary.max_direct_block_mean_absolute_error
                    for scenario in scenarios),
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
    artifact = grid_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " scenarios=", artifact.summary.n_scenarios,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
