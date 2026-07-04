#!/usr/bin/env julia

using Random
using TOML

import BayesianMGMFRM
import LogDensityProblems

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_report_shape_simulation_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

const PROTOCOL = (;
    protocol_id = "confirmatory_mgmfrm_report_shape_simulation_grid_v1",
    review_kind = :local_confirmatory_mgmfrm_report_shape_simulation_grid,
    publication_or_registration_action = false,
    scenario_count = 3,
    sampler = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 1,
        warmup = 0,
        draws = 2,
        step_size = 0.02,
        max_depth = 2,
        metric = :unit,
    ),
    thresholds = (;
        require_all_scenarios_passed = true,
        require_q_validation_passed = true,
        require_fit_succeeded = true,
        require_report_shape_passed = true,
        require_diagnostics_shape_passed = true,
        require_artifact_shape_passed = true,
        require_waic_shape_passed = true,
        require_posterior_predictive_shape_passed = true,
        require_finite_logdensity = true,
        require_finite_pointwise_loglikelihood = true,
        require_no_failed_direct_constraints = true,
        public_exposure_decision = :guarded_fixed_q_only,
    ),
)

const SCENARIOS = [
    (;
        scenario = :simple_2d_full_crossed,
        dimensions = 2,
        persons = 3,
        raters = 2,
        q_matrix = Bool[
            1 0
            0 1
        ],
        simulation_seed = 20260741,
        sampler_seed = 20260742,
        q_shape = :simple_structure,
    ),
    (;
        scenario = :simple_3d_full_crossed,
        dimensions = 3,
        persons = 3,
        raters = 2,
        q_matrix = Bool[
            1 0 0
            0 1 0
            0 0 1
        ],
        simulation_seed = 20260743,
        sampler_seed = 20260744,
        q_shape = :simple_structure,
    ),
    (;
        scenario = :cross_loading_3d_full_crossed,
        dimensions = 3,
        persons = 3,
        raters = 2,
        q_matrix = Bool[
            1 0 0
            0 1 0
            0 0 1
            1 1 0
        ],
        simulation_seed = 20260745,
        sampler_seed = 20260746,
        q_shape = :fixed_confirmatory_cross_loading,
    ),
]

function usage()
    return """
    Generate the local fixed-Q MGMFRM report-shape simulation grid artifact.

    The grid simulates compact fixed-Q confirmatory scenarios, runs the guarded
    MGMFRM fit path, and records report, diagnostics, artifact, WAIC, and
    posterior-predictive shape checks. It is not a broad MGMFRM validation
    claim.

    Usage:
      julia --project=. scripts/generate_mgmfrm_report_shape_simulation_grid.jl [--output PATH]
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

function q_matrix_rows(q_matrix)
    return [
        [Bool(q_matrix[row, col]) for col in axes(q_matrix, 2)]
        for row in axes(q_matrix, 1)
    ]
end

function full_crossed_table(spec; scores = nothing)
    n_items = size(spec.q_matrix, 1)
    examinee = String[]
    rater = String[]
    item = String[]
    base_scores = Int[]
    for person in 1:spec.persons, rater_index in 1:spec.raters, item_index in 1:n_items
        push!(examinee, "E$person")
        push!(rater, "R$rater_index")
        push!(item, "I$item_index")
        push!(base_scores, mod(length(base_scores), 3))
    end
    return (;
        examinee,
        rater,
        item,
        score = scores === nothing ? base_scores : collect(scores),
    )
end

function facet_data(table)
    return BayesianMGMFRM.FacetData(table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

function mgmfrm_spec(data, scenario)
    return BayesianMGMFRM.mfrm_spec(data;
        thresholds = :partial_credit,
        family = :mgmfrm,
        dimensions = scenario.dimensions,
        q_matrix = scenario.q_matrix,
    )
end

function raw_pattern(n::Int, lo::Float64, hi::Float64)
    n == 0 && return Float64[]
    n == 1 && return [(lo + hi) / 2]
    return collect(range(lo, hi; length = n))
end

function raw_truth(target, scenario_index::Int)
    raw = zeros(Float64, target.blueprint.n_parameters)
    blocks = target.blueprint.blocks
    haskey(blocks, :person) &&
        (raw[blocks[:person]] .= raw_pattern(length(blocks[:person]), -0.35, 0.35))
    haskey(blocks, :rater_free) &&
        (raw[blocks[:rater_free]] .= raw_pattern(length(blocks[:rater_free]), -0.12, 0.08))
    haskey(blocks, :item) &&
        (raw[blocks[:item]] .= raw_pattern(length(blocks[:item]), -0.22, 0.18))
    if haskey(blocks, :log_item_dimension_discrimination)
        n = length(blocks[:log_item_dimension_discrimination])
        values = raw_pattern(n, 0.82 + 0.02 * scenario_index, 1.28 + 0.03 * scenario_index)
        raw[blocks[:log_item_dimension_discrimination]] .= log.(values)
    end
    if haskey(blocks, :log_rater_consistency_free)
        n = length(blocks[:log_rater_consistency_free])
        values = raw_pattern(n, 0.92, 1.12)
        raw[blocks[:log_rater_consistency_free]] .= log.(values)
    end
    haskey(blocks, :item_steps) &&
        (raw[blocks[:item_steps]] .= raw_pattern(length(blocks[:item_steps]), -0.18, 0.16))
    return raw
end

function sample_scores(design, direct_params; rng::AbstractRNG)
    rows = BayesianMGMFRM._mgmfrm_source_fixture_values(design, direct_params)
    scores = Int[]
    for observation in 1:design.spec.data.n
        observation_rows = [row for row in rows if row.row == observation]
        probabilities = exp.([row.log_probability for row in observation_rows])
        probabilities ./= sum(probabilities)
        u = rand(rng)
        cumulative = 0.0
        selected = firstindex(probabilities)
        for index in eachindex(probabilities)
            cumulative += probabilities[index]
            if u <= cumulative
                selected = index
                break
            end
        end
        push!(scores, Int(observation_rows[selected].category))
    end
    return scores
end

function sampled_scores_with_full_scale(design, direct_truth, seed::Int)
    for offset in 0:250
        scores = sample_scores(
            design,
            direct_truth;
            rng = MersenneTwister(seed + offset),
        )
        Set(scores) == Set(design.spec.data.category_levels) &&
            return (; scores, actual_seed = seed + offset)
    end
    error("could not sample scores using every category")
end

function score_count_rows(scores, category_levels)
    return [(score = value, n = count(==(value), scores)) for value in category_levels]
end

function q_validation_record(validation)
    return (;
        passed = validation.passed,
        n_error_rows = validation.summary.n_error_rows,
        n_warning_rows = validation.summary.n_warning_rows,
        n_cross_loading_items = validation.summary.n_cross_loading_items,
        n_duplicate_dimension_groups =
            validation.summary.n_duplicate_dimension_groups,
        n_dimension_facet_subgraphs_disconnected =
            validation.summary.n_dimension_facet_subgraphs_disconnected,
        cross_loading_status = only(row.status for row in validation.rows
            if row.check === :cross_loading_policy),
    )
end

function report_shape_record(report, fit, scenario)
    n_draws = size(fit.draws, 1)
    n_raw = size(fit.draws, 2)
    n_direct = size(fit.direct_draws, 2)
    n_observations = fit.design.spec.data.n
    passed =
        report.family === :mgmfrm &&
        report.dimensions == scenario.dimensions &&
        length(report.dimension_labels) == scenario.dimensions &&
        report.metadata.dimension_labels == fit.design.spec.dimension_labels &&
        report.q_matrix.summary.passed &&
        report.direct_posterior.n_rows == n_direct &&
        report.posterior.n_rows == n_raw &&
        report.calibration.status === :computed &&
        report.calibration.n_rows > 0 &&
        report.waic.stat.n_draws == n_draws &&
        report.waic.stat.n_observations == n_observations &&
        report.artifact.schema ==
            "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1"
    return (;
        passed,
        family = report.family,
        dimensions = report.dimensions,
        dimension_labels = report.dimension_labels,
        posterior_status = report.posterior.status,
        posterior_rows = report.posterior.n_rows,
        direct_posterior_status = report.direct_posterior.status,
        direct_posterior_rows = report.direct_posterior.n_rows,
        calibration_status = report.calibration.status,
        calibration_rows = report.calibration.n_rows,
        q_matrix_status = report.q_matrix.status,
        q_matrix_passed = report.q_matrix.summary.passed,
        waic_status = report.waic.status,
        waic_n_draws = report.waic.stat.n_draws,
        waic_n_observations = report.waic.stat.n_observations,
        artifact_status = report.artifact.status,
        artifact_schema = report.artifact.schema,
    )
end

function diagnostics_shape_record(diagnostics, fit)
    n_raw = size(fit.draws, 2)
    n_direct = size(fit.direct_draws, 2)
    passed =
        diagnostics.family === :mgmfrm &&
        length(diagnostics.parameter_layout.raw_parameter_names) == n_raw &&
        length(diagnostics.parameter_layout.constrained_parameter_names) == n_direct &&
        length(diagnostics.parameter_rows) == n_raw &&
        length(diagnostics.direct_parameter_rows) == n_direct &&
        length(diagnostics.sampler_rows) == length(fit.chain_acceptance_rate) &&
        all(row -> row.passed, diagnostics.direct_constraint_rows)
    return (;
        passed,
        raw_parameter_rows = length(diagnostics.parameter_rows),
        direct_parameter_rows = length(diagnostics.direct_parameter_rows),
        raw_block_rows = length(diagnostics.block_rows),
        direct_block_rows = length(diagnostics.direct_block_rows),
        sampler_rows = length(diagnostics.sampler_rows),
        direct_constraint_rows = length(diagnostics.direct_constraint_rows),
        direct_constraints_passed =
            all(row -> row.passed, diagnostics.direct_constraint_rows),
        fixed_q_invariance_rows = length(diagnostics.fixed_q_invariance_rows),
    )
end

function artifact_shape_record(artifact, fit)
    n_draws = size(fit.draws, 1)
    n_raw = size(fit.draws, 2)
    n_direct = size(fit.direct_draws, 2)
    n_observations = fit.design.spec.data.n
    passed =
        artifact.schema ==
            "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1" &&
        length(artifact.raw_parameter_names) == n_raw &&
        length(artifact.direct_parameter_names) == n_direct &&
        length(artifact.posterior_summary) == n_raw &&
        length(artifact.direct_posterior_summary) == n_direct &&
        size(artifact.pointwise_loglikelihood) == (n_draws, n_observations) &&
        artifact.q_matrix == fit.design.spec.q_matrix &&
        artifact.latent_correlation === :identity_fixed
    return (;
        passed,
        schema = artifact.schema,
        raw_parameter_names = length(artifact.raw_parameter_names),
        direct_parameter_names = length(artifact.direct_parameter_names),
        posterior_rows = length(artifact.posterior_summary),
        direct_posterior_rows = length(artifact.direct_posterior_summary),
        pointwise_shape = collect(size(artifact.pointwise_loglikelihood)),
        q_matrix = q_matrix_rows(artifact.q_matrix),
        latent_correlation = artifact.latent_correlation,
        content_hash_length = length(artifact.content_hash.value),
    )
end

function waic_shape_record(stat, fit)
    passed =
        stat.n_draws == size(fit.draws, 1) &&
        stat.n_observations == fit.design.spec.data.n &&
        isfinite(stat.elpd_waic) &&
        isfinite(stat.waic)
    return (;
        passed,
        n_draws = stat.n_draws,
        n_observations = stat.n_observations,
        waic = stat.waic,
        elpd_waic = stat.elpd_waic,
        high_variance_count = stat.high_variance_count,
        warning = stat.warning,
    )
end

function posterior_predictive_shape_record(ppc, fit)
    expected = (size(fit.draws, 1), fit.design.spec.data.n)
    passed =
        size(ppc.replicated_scores) == expected &&
        ppc.category_levels == fit.design.spec.data.category_levels
    return (;
        passed,
        replicated_shape = collect(size(ppc.replicated_scores)),
        expected_shape = collect(expected),
        n_categories = length(ppc.category_levels),
        n_summary_rows = length(BayesianMGMFRM.predictive_check_summary(ppc;
            include_grouped = true)),
    )
end

function finite_review(fit)
    pointwise = fit.direct_pointwise_loglikelihood
    return (;
        log_posterior_finite = all(isfinite, fit.log_posterior),
        direct_draws_finite = all(isfinite, fit.direct_draws),
        pointwise_finite = all(isfinite, pointwise),
        pointwise_shape = collect(size(pointwise)),
        n_nonfinite_pointwise = count(!isfinite, vec(pointwise)),
        n_failed_direct_constraints =
            fit.diagnostic_surface.summary.n_failed_direct_constraints,
    )
end

function scenario_record(scenario, scenario_index::Int)
    placeholder = full_crossed_table(scenario)
    placeholder_data = facet_data(placeholder)
    placeholder_spec = mgmfrm_spec(placeholder_data, scenario)
    placeholder_design = BayesianMGMFRM.getdesign(placeholder_spec; preview = true)
    placeholder_target =
        BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(placeholder_design)
    truth_raw = raw_truth(placeholder_target, scenario_index)
    direct_truth =
        BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
            placeholder_design,
            truth_raw,
        )
    sampled = sampled_scores_with_full_scale(
        placeholder_design,
        direct_truth,
        scenario.simulation_seed,
    )
    table = full_crossed_table(scenario; scores = sampled.scores)
    data = facet_data(table)
    spec = mgmfrm_spec(data, scenario)
    q_validation = BayesianMGMFRM.q_matrix_validation(spec)
    design = BayesianMGMFRM.getdesign(spec; preview = true)
    target = BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(design)
    logdensity = LogDensityProblems.logdensity(target, truth_raw)
    fit = BayesianMGMFRM.fit(spec;
        experimental = true,
        init = truth_raw,
        seed = scenario.sampler_seed,
        ndraws = PROTOCOL.sampler.draws,
        warmup = PROTOCOL.sampler.warmup,
        chains = PROTOCOL.sampler.chains,
        step_size = PROTOCOL.sampler.step_size,
        max_depth = PROTOCOL.sampler.max_depth,
        metric = PROTOCOL.sampler.metric,
    )
    draw_indices = collect(1:size(fit.draws, 1))
    report = BayesianMGMFRM.fit_report(fit;
        draw_indices,
        include_loo = false,
        artifact_include_environment = false,
    )
    diagnostics = BayesianMGMFRM.diagnostics(fit)
    artifact = BayesianMGMFRM.fit_artifact(fit; include_environment = false)
    waic_stat = BayesianMGMFRM.waic(fit)
    ppc = BayesianMGMFRM.posterior_predictive_check(fit;
        draw_indices,
        rng = MersenneTwister(scenario.sampler_seed + 10_000),
    )
    finite = finite_review(fit)
    report_shape = report_shape_record(report, fit, scenario)
    diagnostics_shape = diagnostics_shape_record(diagnostics, fit)
    artifact_shape = artifact_shape_record(artifact, fit)
    waic_shape = waic_shape_record(waic_stat, fit)
    posterior_predictive_shape = posterior_predictive_shape_record(ppc, fit)
    passed =
        q_validation.passed &&
        isfinite(logdensity) &&
        finite.log_posterior_finite &&
        finite.direct_draws_finite &&
        finite.pointwise_finite &&
        finite.n_failed_direct_constraints == 0 &&
        report_shape.passed &&
        diagnostics_shape.passed &&
        artifact_shape.passed &&
        waic_shape.passed &&
        posterior_predictive_shape.passed
    return (;
        scenario = scenario.scenario,
        dimensions = scenario.dimensions,
        q_shape = scenario.q_shape,
        q_matrix = q_matrix_rows(scenario.q_matrix),
        simulation_seed = scenario.simulation_seed,
        actual_simulation_seed = sampled.actual_seed,
        sampler_seed = scenario.sampler_seed,
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        n_observations = data.n,
        score_counts = score_count_rows(table.score, data.category_levels),
        q_validation = q_validation_record(q_validation),
        n_raw_parameters = size(fit.draws, 2),
        n_direct_parameters = size(fit.direct_draws, 2),
        n_draws = size(fit.draws, 1),
        raw_draw_shape = collect(size(fit.draws)),
        direct_draw_shape = collect(size(fit.direct_draws)),
        pointwise_loglikelihood_shape =
            collect(size(fit.direct_pointwise_loglikelihood)),
        initial_logdensity = logdensity,
        finite,
        report_shape,
        diagnostics_shape,
        artifact_shape,
        waic_shape,
        posterior_predictive_shape,
        summary = (;
            passed,
            q_validation_passed = q_validation.passed,
            finite_initial_logdensity = isfinite(logdensity),
            finite_log_posterior = finite.log_posterior_finite,
            finite_direct_draws = finite.direct_draws_finite,
            finite_pointwise_loglikelihood = finite.pointwise_finite,
            no_failed_direct_constraints =
                finite.n_failed_direct_constraints == 0,
            report_shape_passed = report_shape.passed,
            diagnostics_shape_passed = diagnostics_shape.passed,
            artifact_shape_passed = artifact_shape.passed,
            waic_shape_passed = waic_shape.passed,
            posterior_predictive_shape_passed =
                posterior_predictive_shape.passed,
        ),
    )
end

function grid_artifact()
    scenarios = [
        scenario_record(scenario, index)
        for (index, scenario) in pairs(SCENARIOS)
    ]
    passed = all(scenario -> scenario.summary.passed, scenarios)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_report_shape_simulation_grid.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :report_shape_simulation_grid_recorded,
        decision = :keep_guarded_fixed_q_only,
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
                :supports_guarded_fixed_q_report_shape_coverage,
            interpretation =
                :report_diagnostics_artifact_shapes_recorded_for_fixed_q_scenarios,
            required_followup = :q_matrix_validation_expansion,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            n_scenarios = length(scenarios),
            n_passed_scenarios =
                count(scenario -> scenario.summary.passed, scenarios),
            dimensions_covered =
                sort(unique([scenario.dimensions for scenario in scenarios])),
            q_shapes_covered =
                sort(unique([scenario.q_shape for scenario in scenarios]);
                    by = string),
            all_q_validation_passed =
                all(scenario -> scenario.summary.q_validation_passed, scenarios),
            all_report_shapes_passed =
                all(scenario -> scenario.summary.report_shape_passed, scenarios),
            all_diagnostics_shapes_passed =
                all(scenario -> scenario.summary.diagnostics_shape_passed,
                    scenarios),
            all_artifact_shapes_passed =
                all(scenario -> scenario.summary.artifact_shape_passed, scenarios),
            all_waic_shapes_passed =
                all(scenario -> scenario.summary.waic_shape_passed, scenarios),
            all_posterior_predictive_shapes_passed =
                all(scenario ->
                    scenario.summary.posterior_predictive_shape_passed,
                    scenarios),
            all_no_failed_direct_constraints =
                all(scenario -> scenario.summary.no_failed_direct_constraints,
                    scenarios),
            all_finite_pointwise_loglikelihood =
                all(scenario -> scenario.summary.finite_pointwise_loglikelihood,
                    scenarios),
            max_raw_parameters =
                maximum(scenario.n_raw_parameters for scenario in scenarios),
            max_direct_parameters =
                maximum(scenario.n_direct_parameters for scenario in scenarios),
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            remaining_public_blockers = [
                :free_latent_correlation_policy_missing,
                :exploratory_loading_policy_missing,
                :broad_generalized_mgmfrm_validation_missing,
            ],
            recommendation =
                :keep_fixed_q_confirmatory_guarded_continue_q_validation_expansion,
            next_gate = :q_matrix_validation_expansion,
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

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
