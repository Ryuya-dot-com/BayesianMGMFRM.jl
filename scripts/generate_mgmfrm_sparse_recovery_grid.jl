#!/usr/bin/env julia

using LinearAlgebra
using Random
using SHA
using TOML

import BayesianMGMFRM

module MGMFRMRecoverySmoke
include(joinpath(@__DIR__, "generate_mgmfrm_recovery_smoke.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "mgmfrm_sparse_recovery_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

const SMOKE = MGMFRMRecoverySmoke

const PROTOCOL = (;
    protocol_id = "confirmatory_mgmfrm_sparse_recovery_grid_v1",
    review_kind = :local_confirmatory_mgmfrm_sparse_recovery_grid,
    publication_or_registration_action = false,
    simulation_source = :confirmatory_mgmfrm_recovery_smoke_grid_variant,
    full_crossed_observations = SMOKE.PROTOCOL.grid.observations,
    sparse_designs = (;
        persons = SMOKE.PROTOCOL.grid.persons,
        items = SMOKE.PROTOCOL.grid.items,
        raters = SMOKE.PROTOCOL.grid.raters,
        categories = SMOKE.PROTOCOL.grid.categories,
        dimensions = SMOKE.PROTOCOL.grid.dimensions,
        q_matrix = SMOKE.PROTOCOL.grid.q_matrix,
        rating_density = :sparse_connected,
        patterns = (
            :rater_item_bridge,
            :alternating_dimension_bridge,
            :leave_one_pair_out,
        ),
    ),
    validation = (;
        bias_terms = ((:rater, :item),),
        min_cell_count = 2,
        require_no_validation_errors = true,
        require_connected_design = true,
        require_full_location_rank = true,
    ),
    sampler = SMOKE.PROTOCOL.sampler,
    diagnostics = (;
        max_rhat = 1.6,
        min_ess = 4.0,
        min_ebfmi = SMOKE.PROTOCOL.thresholds.min_ebfmi,
        n_divergences = 0,
        n_max_treedepth = 0,
        n_failed_direct_constraints = 0,
        n_nonfinite_logdensity = 0,
        n_nonfinite_direct_loglikelihood = 0,
    ),
    recovery = (;
        interval = 0.8,
        max_block_mean_absolute_error = 2.5,
        max_parameter_absolute_error = 4.0,
        min_block_coverage_rate = 0.0,
    ),
    thresholds = (;
        n_scenarios = 3,
        min_observations = 16,
        max_observations = SMOKE.PROTOCOL.grid.observations - 4,
        require_all_scenarios_passed = true,
        require_validation_passed = true,
        require_connected_design = true,
        require_full_location_rank = true,
        require_same_parameter_order = true,
        require_sampler_passed = true,
        require_finite_logdensity = true,
        require_finite_pointwise_loglikelihood = true,
        require_finite_waic = true,
        require_recovery_within_thresholds = true,
        public_exposure_decision = :keep_internal,
    ),
)

const SCENARIOS = [
    (;
        scenario = :rater_item_bridge_sparse,
        sparse_pattern = :rater_item_bridge,
        simulation_seed = 20260781,
        sampler_seed = 20260782,
        raw_truth = SMOKE.TRUTH_RAW,
    ),
    (;
        scenario = :alternating_dimension_bridge_sparse,
        sparse_pattern = :alternating_dimension_bridge,
        simulation_seed = 20260783,
        sampler_seed = 20260784,
        raw_truth = [
            -0.35, 0.15,
            -0.1, -0.2,
            0.1, 0.25,
            0.35, -0.05,
            -0.15, 0.05,
            -0.08, 0.12,
            log(1.15), log(0.9),
            log(1.05), log(0.95),
            0.12, -0.1,
        ],
    ),
    (;
        scenario = :leave_one_pair_out_sparse,
        sparse_pattern = :leave_one_pair_out,
        simulation_seed = 20260785,
        sampler_seed = 20260786,
        raw_truth = [
            -0.55, 0.25,
            -0.18, -0.3,
            0.18, 0.35,
            0.55, -0.18,
            -0.25, 0.08,
            -0.12, 0.18,
            log(1.4), log(0.75),
            log(1.2), log(0.85),
            0.28, -0.18,
        ],
    ),
]

function usage()
    return """
    Generate the local confirmatory MGMFRM sparse-recovery grid artifact.

    The grid keeps MGMFRM internal, runs the source-aligned raw-coordinate
    target on three sparse connected fixed-Q scenarios, and records validation,
    sampler, WAIC, and direct-scale recovery summaries.

    Usage:
      julia --project=. scripts/generate_mgmfrm_sparse_recovery_grid.jl [--output PATH]
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

function fixture_reference(path::AbstractString)
    local_path = joinpath(ROOT, path)
    return (;
        artifact = path,
        exists = isfile(local_path),
        sha256 = isfile(local_path) ? file_sha256(local_path) : missing,
    )
end

function parameter_order_hash(names)
    return bytes2hex(sha256(codeunits(join(names, "\n"))))
end

function raw_truth_hash(values)
    return bytes2hex(sha256(codeunits(join(values, "\n"))))
end

function sparse_indices(pattern::Symbol)
    base = SMOKE.placeholder_table()
    indices = Int[]
    for index in eachindex(base.score)
        person = parse(Int, base.examinee[index][2:end])
        rater = parse(Int, base.rater[index][2:end])
        item = parse(Int, base.item[index][2:end])
        selected = pattern === :rater_item_bridge ?
            (rater == 1 || item == 1 || isodd(person + rater)) :
            pattern === :alternating_dimension_bridge ?
            (item == mod(person + rater, 2) + 1 || rater == 1) :
            pattern === :leave_one_pair_out ?
            !((person + rater + item) % 4 == 0) :
            throw(ArgumentError("unknown sparse pattern: $pattern"))
        selected && push!(indices, index)
    end
    return indices
end

function table_subset(indices, scores)
    base = SMOKE.placeholder_table()
    return (;
        examinee = base.examinee[indices],
        rater = base.rater[indices],
        item = base.item[indices],
        score = scores,
    )
end

function placeholder_table_for_pattern(pattern::Symbol)
    indices = sparse_indices(pattern)
    base = SMOKE.placeholder_table()
    return (; table = table_subset(indices, base.score[indices]), indices)
end

function score_count_rows(scores, category_levels)
    return [(score = value, n = count(==(value), scores)) for value in category_levels]
end

function sampled_scores_with_full_scale(design, direct_truth, seed::Int)
    for offset in 0:250
        actual_seed = seed + offset
        scores = SMOKE.sample_scores(
            design,
            direct_truth;
            rng = MersenneTwister(actual_seed),
        )
        if Set(scores) == Set(design.spec.data.category_levels)
            return (; scores, actual_seed)
        end
    end
    error("could not sample sparse MGMFRM scores using all score categories")
end

function table_for_scenario(spec)
    placeholder = placeholder_table_for_pattern(spec.sparse_pattern)
    placeholder_design = SMOKE.confirmatory_mgmfrm_design(placeholder.table)
    placeholder_design.spec.data.category_levels == [0, 1, 2] ||
        error("sparse placeholder must keep the full three-category scale")
    direct_truth =
        BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
            placeholder_design,
            spec.raw_truth,
        )
    sampled = sampled_scores_with_full_scale(
        placeholder_design,
        direct_truth,
        spec.simulation_seed,
    )
    table = table_subset(placeholder.indices, sampled.scores)
    data = SMOKE.facet_data(table)
    data.category_levels == [0, 1, 2] ||
        error("sampled sparse table changed category levels")
    return (;
        placeholder_design,
        direct_truth,
        table,
        selected_indices = placeholder.indices,
        actual_simulation_seed = sampled.actual_seed,
    )
end

function issue_record(issue)
    return (;
        code = issue.code,
        severity = issue.severity,
        message = issue.message,
        context_keys = sort([String(key) for key in keys(issue.context)]),
    )
end

function category_count_rows(report)
    return [
        (category = category, n = report.category_counts[category])
        for category in sort(collect(keys(report.category_counts)))
    ]
end

function facet_count_rows(report)
    rows = NamedTuple[]
    for facet in (:person, :rater, :item)
        counts = report.facet_counts[facet]
        for level in sort(collect(keys(counts)); by = string)
            push!(rows, (; facet, level, n = counts[level]))
        end
    end
    return rows
end

function component_rows(report)
    return [
        (component = index,
            n_nodes = length(component),
            nodes = [(facet = node[1], level = node[2]) for node in component])
        for (index, component) in pairs(report.components)
    ]
end

function dff_cell_count_rows(report)
    rows = NamedTuple[]
    for (term, counts) in report.dff_counts
        left, right = term
        for ((left_level, right_level), n) in sort(collect(counts); by = string)
            push!(rows, (;
                left_facet = left,
                right_facet = right,
                left_level,
                right_level,
                n,
            ))
        end
    end
    return rows
end

function validation_record(data, report)
    matrix = BayesianMGMFRM._minimal_location_matrix(data)
    location_rank = rank(matrix)
    n_location_parameters = size(matrix, 2)
    issue_rows = [issue_record(issue) for issue in report.issues]
    return (;
        n_observations = data.n,
        passed = report.passed,
        n_errors = count(row -> row.severity === :error, issue_rows),
        n_warnings = count(row -> row.severity === :warning, issue_rows),
        issue_rows,
        issue_codes = [row.code for row in issue_rows],
        category_counts = category_count_rows(report),
        facet_counts = facet_count_rows(report),
        components = component_rows(report),
        n_components = length(report.components),
        component_sizes = length.(report.components),
        location_design_rank = location_rank,
        n_location_parameters,
        location_design_full_rank = location_rank == n_location_parameters,
        dff_cell_counts = dff_cell_count_rows(report),
    )
end

function selected_cell_rows(table)
    return [
        (row = index,
            person = table.examinee[index],
            rater = table.rater[index],
            item = table.item[index],
            score = table.score[index])
        for index in eachindex(table.score)
    ]
end

function sampler_summary_record(diagnostics)
    return SMOKE.sampler_summary_record(diagnostics)
end

function finite_waic_summary(stat)
    return (;
        criterion = stat.criterion,
        elpd_waic = stat.elpd_waic,
        p_waic = stat.p_waic,
        lppd = stat.lppd,
        waic = stat.waic,
        se_elpd_waic = stat.se_elpd_waic,
        se_waic = stat.se_waic,
        n_draws = stat.n_draws,
        n_observations = stat.n_observations,
        high_variance_count = stat.high_variance_count,
        warning = stat.warning,
    )
end

function pointwise_review(pointwise)
    values = vec(pointwise)
    return (;
        shape = collect(size(pointwise)),
        n_nonfinite = count(!isfinite, values),
        minimum = minimum(values),
        maximum = maximum(values),
    )
end

function recovery_thresholds_passed(recovery_rows, recovery_by_block)
    thresholds = PROTOCOL.recovery
    return maximum(row.absolute_bias for row in recovery_rows) <=
        thresholds.max_parameter_absolute_error &&
        maximum(row.mean_absolute_error for row in recovery_by_block) <=
        thresholds.max_block_mean_absolute_error &&
        minimum(row.coverage_rate for row in recovery_by_block) >=
        thresholds.min_block_coverage_rate
end

function scenario_passed(validation, sampler_summary, recovery_rows,
        recovery_by_block, waic_stat, pointwise, parameter_order_matches,
        n_observations)
    thresholds = PROTOCOL.thresholds
    diagnostics = PROTOCOL.diagnostics
    thresholds.min_observations <= n_observations <= thresholds.max_observations ||
        return false
    validation.passed || return false
    validation.n_components == 1 || return false
    validation.location_design_full_rank || return false
    parameter_order_matches || return false
    sampler_summary.internal_passed || return false
    sampler_summary.n_divergences == diagnostics.n_divergences || return false
    sampler_summary.n_max_treedepth == diagnostics.n_max_treedepth || return false
    sampler_summary.n_failed_direct_constraints ==
        diagnostics.n_failed_direct_constraints || return false
    sampler_summary.n_nonfinite_logdensity == diagnostics.n_nonfinite_logdensity ||
        return false
    sampler_summary.n_nonfinite_direct_loglikelihood ==
        diagnostics.n_nonfinite_direct_loglikelihood || return false
    sampler_summary.max_rhat <= diagnostics.max_rhat || return false
    sampler_summary.min_ess >= diagnostics.min_ess || return false
    sampler_summary.e_bfmi >= diagnostics.min_ebfmi || return false
    all(isfinite, pointwise) || return false
    isfinite(waic_stat.elpd_waic) && isfinite(waic_stat.waic) || return false
    recovery_thresholds_passed(recovery_rows, recovery_by_block) || return false
    return true
end

function scenario_record(spec, reference_raw_hash, reference_direct_hash)
    simulated = table_for_scenario(spec)
    table = simulated.table
    data = SMOKE.facet_data(table)
    validation_report = BayesianMGMFRM.validate_design(
        data;
        bias = collect(PROTOCOL.validation.bias_terms),
        min_cell_count = PROTOCOL.validation.min_cell_count,
    )
    validation = validation_record(data, validation_report)
    design = SMOKE.confirmatory_mgmfrm_design(table)
    target = BayesianMGMFRM._source_fixture_logdensity(design)
    diagnostics = SMOKE.MGMFRMChainStudy.run_diagnostics(
        target,
        zeros(length(spec.raw_truth)),
        spec.sampler_seed,
    )
    recovery_rows = BayesianMGMFRM.parameter_recovery(
        design,
        diagnostics.direct_draws,
        simulated.direct_truth;
        interval = PROTOCOL.recovery.interval,
    )
    recovery_by_block = BayesianMGMFRM.parameter_recovery_summary(recovery_rows; by = :block)
    sampler_summary = sampler_summary_record(diagnostics)
    waic_stat = BayesianMGMFRM.waic(diagnostics.direct_pointwise_loglikelihood)
    raw_hash = parameter_order_hash(target.blueprint.parameter_names)
    direct_hash = parameter_order_hash(target.blueprint.constrained_parameter_names)
    parameter_order_matches =
        raw_hash == reference_raw_hash && direct_hash == reference_direct_hash &&
        design.parameter_names == simulated.placeholder_design.parameter_names
    passed = scenario_passed(
        validation,
        sampler_summary,
        recovery_rows,
        recovery_by_block,
        waic_stat,
        diagnostics.direct_pointwise_loglikelihood,
        parameter_order_matches,
        data.n,
    )
    return (;
        scenario = spec.scenario,
        sparse_pattern = spec.sparse_pattern,
        simulation_seed = spec.simulation_seed,
        actual_simulation_seed = simulated.actual_simulation_seed,
        sampler_seed = spec.sampler_seed,
        raw_truth_sha256 = raw_truth_hash(spec.raw_truth),
        selected_row_indices = simulated.selected_indices,
        selected_cells = selected_cell_rows(table),
        design_density = (;
            rating_density = :sparse_connected,
            n_observations = data.n,
            full_crossed_observations = PROTOCOL.full_crossed_observations,
            observed_fraction = data.n / PROTOCOL.full_crossed_observations,
            missing_observations = PROTOCOL.full_crossed_observations - data.n,
        ),
        simulated_data = (;
            n_observations = data.n,
            score_counts = score_count_rows(table.score, data.category_levels),
            person_levels = data.person_levels,
            rater_levels = data.rater_levels,
            item_levels = data.item_levels,
            category_levels = data.category_levels,
        ),
        validation,
        raw_parameter_order_sha256 = raw_hash,
        direct_parameter_order_sha256 = direct_hash,
        parameter_order_matches_reference = parameter_order_matches,
        sampler_summary,
        pointwise_loglikelihood_review =
            pointwise_review(diagnostics.direct_pointwise_loglikelihood),
        waic = finite_waic_summary(waic_stat),
        recovery_rows = [SMOKE.recovery_row_record(row) for row in recovery_rows],
        recovery_by_block = [
            SMOKE.recovery_summary_record(row) for row in recovery_by_block
        ],
        summary = (;
            passed,
            n_observations = data.n,
            validation_passed = validation.passed,
            validation_warnings = validation.n_warnings,
            location_design_full_rank = validation.location_design_full_rank,
            parameter_order_matches_reference = parameter_order_matches,
            sampler_flag = sampler_summary.internal_flag,
            n_divergences = sampler_summary.n_divergences,
            n_max_treedepth = sampler_summary.n_max_treedepth,
            n_failed_direct_constraints =
                sampler_summary.n_failed_direct_constraints,
            n_nonfinite_logdensity = sampler_summary.n_nonfinite_logdensity,
            n_nonfinite_direct_loglikelihood =
                sampler_summary.n_nonfinite_direct_loglikelihood,
            max_rhat = sampler_summary.max_rhat,
            min_ess = sampler_summary.min_ess,
            e_bfmi = sampler_summary.e_bfmi,
            waic_finite = isfinite(waic_stat.elpd_waic) && isfinite(waic_stat.waic),
            waic_warning = waic_stat.warning,
            max_block_mean_absolute_error =
                maximum(row.mean_absolute_error for row in recovery_by_block),
            max_parameter_absolute_error =
                maximum(row.absolute_bias for row in recovery_rows),
            min_block_coverage_rate =
                minimum(row.coverage_rate for row in recovery_by_block),
        ),
    )
end

function grid_artifact()
    reference_design = SMOKE.confirmatory_mgmfrm_design(SMOKE.placeholder_table())
    reference_target = BayesianMGMFRM._source_fixture_logdensity(reference_design)
    reference_raw_hash = parameter_order_hash(reference_target.blueprint.parameter_names)
    reference_direct_hash =
        parameter_order_hash(reference_target.blueprint.constrained_parameter_names)
    scenarios = [
        scenario_record(spec, reference_raw_hash, reference_direct_hash)
        for spec in SCENARIOS
    ]
    passed = all(scenario -> scenario.summary.passed, scenarios)
    all_recovery_rows = reduce(vcat, [scenario.recovery_rows for scenario in scenarios])
    all_recovery_by_block =
        reduce(vcat, [scenario.recovery_by_block for scenario in scenarios])
    return (;
        schema = "bayesianmgmfrm.mgmfrm_sparse_recovery_grid.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :internal_sparse_recovery_grid,
        decision = :keep_internal,
        public_fit = false,
        experimental_public = false,
        fit_ready = false,
        dimensions = PROTOCOL.sparse_designs.dimensions,
        q_matrix = PROTOCOL.sparse_designs.q_matrix,
        latent_correlation = :identity_fixed,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        reviewed_artifacts = [
            fixture_reference("test/fixtures/mgmfrm_recovery_smoke.json"),
            fixture_reference("test/fixtures/mgmfrm_baseline_comparison.json"),
        ],
        raw_parameter_order_sha256 = reference_raw_hash,
        direct_parameter_order_sha256 = reference_direct_hash,
        scenarios,
        decision_record = (;
            selected_decision = :keep_internal,
            public_fit_allowed = false,
            experimental_keyword_enabled = false,
            public_exposure_support =
                :insufficient_for_mgmfrm_public_fit,
            interpretation =
                :confirmatory_mgmfrm_sparse_recovery_grid_recorded_keep_internal,
            required_followup = :dff_estimand_and_validation_grid,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            n_scenarios = length(scenarios),
            n_passed_scenarios = count(scenario -> scenario.summary.passed, scenarios),
            n_observations_minimum =
                minimum(scenario.summary.n_observations for scenario in scenarios),
            n_observations_maximum =
                maximum(scenario.summary.n_observations for scenario in scenarios),
            all_validations_passed =
                all(scenario -> scenario.summary.validation_passed, scenarios),
            all_location_designs_full_rank =
                all(scenario -> scenario.summary.location_design_full_rank, scenarios),
            all_parameter_orders_match_reference =
                all(scenario -> scenario.summary.parameter_order_matches_reference,
                    scenarios),
            all_sampler_passed =
                all(scenario -> scenario.summary.sampler_flag === :ok, scenarios),
            all_no_divergences =
                all(scenario -> scenario.summary.n_divergences == 0, scenarios),
            all_no_max_treedepth =
                all(scenario -> scenario.summary.n_max_treedepth == 0, scenarios),
            all_no_failed_direct_constraints =
                all(scenario -> scenario.summary.n_failed_direct_constraints == 0,
                    scenarios),
            all_no_nonfinite_logdensity =
                all(scenario -> scenario.summary.n_nonfinite_logdensity == 0,
                    scenarios),
            all_no_nonfinite_direct_loglikelihood =
                all(scenario ->
                    scenario.summary.n_nonfinite_direct_loglikelihood == 0,
                    scenarios),
            all_waic_finite = all(scenario -> scenario.summary.waic_finite, scenarios),
            any_high_variance_waic =
                any(scenario -> scenario.summary.waic_warning !== :ok, scenarios),
            max_block_mean_absolute_error =
                maximum(row.mean_absolute_error for row in all_recovery_by_block),
            max_parameter_absolute_error =
                maximum(row.absolute_bias for row in all_recovery_rows),
            min_block_coverage_rate =
                minimum(row.coverage_rate for row in all_recovery_by_block),
            public_fit_allowed = false,
            experimental_keyword_enabled = false,
            remaining_public_blockers = [
                :dff_estimand_and_validation_evidence_missing,
                :manuscript_scale_simulation_grid_missing,
                :full_paper_reproduction_archive_missing,
            ],
            recommendation =
                :keep_mgmfrm_internal_until_dff_and_gate_e_evidence,
            next_gate = :dff_estimand_and_validation_grid,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = grid_artifact()
    write_artifact(output, artifact)
    println("wrote ", output)
    println("passed=", artifact.summary.passed,
        " scenarios=", artifact.summary.n_scenarios,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
