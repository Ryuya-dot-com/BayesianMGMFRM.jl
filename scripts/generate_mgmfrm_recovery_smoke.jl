#!/usr/bin/env julia

using Random
using SHA
using TOML

import BayesianMGMFRM

module MGMFRMChainStudy
include(joinpath(@__DIR__, "generate_mgmfrm_candidate_chain_study.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT = joinpath(ROOT, "test", "fixtures", "mgmfrm_recovery_smoke.json")

include(joinpath(@__DIR__, "local_json.jl"))

const TRUTH_RAW = [
    -0.45, 0.2,
    -0.15, -0.25,
    0.15, 0.3,
    0.45, -0.1,
    -0.2, 0.05,
    -0.1, 0.15,
    log(1.3), log(0.8),
    log(1.15), log(0.9),
    0.2, -0.15,
]

const CHAIN_PROTOCOL = MGMFRMChainStudy.PROTOCOL

const PROTOCOL = (;
    protocol_id = "confirmatory_mgmfrm_recovery_smoke_v1",
    simulation_seed = 20260721,
    sampler_seed = 20260722,
    grid = (;
        persons = 4,
        items = 2,
        raters = 3,
        categories = 3,
        dimensions = 2,
        q_matrix = [[true, false], [false, true]],
        rating_density = :full_crossed,
        observations = 24,
        latent_correlation = :identity_fixed,
        rater_consistency_variation = :moderate,
        item_dimension_discrimination_variation = :moderate,
        category_step_spread = :moderate,
        sparse_cell_pathologies = :none_in_smoke,
    ),
    sampler = (;
        backend = CHAIN_PROTOCOL.backend,
        sampler = CHAIN_PROTOCOL.sampler,
        chains = CHAIN_PROTOCOL.chains,
        warmup = CHAIN_PROTOCOL.warmup,
        draws = CHAIN_PROTOCOL.draws,
        step_size = CHAIN_PROTOCOL.step_size,
        target_accept = CHAIN_PROTOCOL.target_accept,
        max_depth = CHAIN_PROTOCOL.max_depth,
        max_energy_error = CHAIN_PROTOCOL.max_energy_error,
        metric = CHAIN_PROTOCOL.metric,
        ad_backend = CHAIN_PROTOCOL.ad_backend,
        init_jitter = CHAIN_PROTOCOL.init_jitter,
        split_chains = CHAIN_PROTOCOL.split_chains,
    ),
    thresholds = (;
        max_rhat = CHAIN_PROTOCOL.thresholds.max_rhat,
        min_ess = CHAIN_PROTOCOL.thresholds.min_ess,
        min_ebfmi = CHAIN_PROTOCOL.thresholds.min_ebfmi,
        n_divergences = CHAIN_PROTOCOL.thresholds.n_divergences,
        n_max_treedepth = CHAIN_PROTOCOL.thresholds.n_max_treedepth,
        n_failed_direct_constraints =
            CHAIN_PROTOCOL.thresholds.n_failed_direct_constraints,
        n_nonfinite_logdensity = CHAIN_PROTOCOL.thresholds.n_nonfinite_logdensity,
        n_nonfinite_direct_loglikelihood =
            CHAIN_PROTOCOL.thresholds.n_nonfinite_direct_loglikelihood,
        max_block_mean_absolute_error = 0.9,
        max_parameter_absolute_error = 1.8,
        min_block_coverage_rate = 0.0,
    ),
)

function usage()
    return """
    Generate the local confirmatory MGMFRM recovery-smoke artifact.

    Usage:
      julia --project=. scripts/generate_mgmfrm_recovery_smoke.jl [--output PATH]
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

function placeholder_table()
    examinee = String[]
    rater = String[]
    item = String[]
    score = Int[]
    for person in 1:PROTOCOL.grid.persons,
            rater_index in 1:PROTOCOL.grid.raters,
            item_index in 1:PROTOCOL.grid.items
        push!(examinee, "E$person")
        push!(rater, "R$rater_index")
        push!(item, "I$item_index")
        push!(score, mod(length(score), PROTOCOL.grid.categories))
    end
    return (; examinee, rater, item, score)
end

function facet_data(table)
    return BayesianMGMFRM.FacetData(table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

function confirmatory_mgmfrm_design(table)
    data = facet_data(table)
    spec = BayesianMGMFRM.mfrm_spec(data;
        family = :mgmfrm,
        dimensions = PROTOCOL.grid.dimensions,
        q_matrix = Bool[1 0; 0 1],
    )
    return BayesianMGMFRM.getdesign(spec; preview = true)
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

function simulated_table(design, direct_truth)
    base = placeholder_table()
    scores = sample_scores(
        design,
        direct_truth;
        rng = MersenneTwister(PROTOCOL.simulation_seed),
    )
    return (;
        examinee = base.examinee,
        rater = base.rater,
        item = base.item,
        score = scores,
    )
end

function parameter_order_hash(names)
    return bytes2hex(sha256(codeunits(join(names, "\n"))))
end

function project_version()
    project = TOML.parsefile(joinpath(ROOT, "Project.toml"))
    return String(project["version"])
end

function score_count_rows(scores)
    return [(score = value, n = count(==(value), scores))
        for value in sort(unique(scores))]
end

function sampler_summary_record(diagnostics)
    summary = diagnostics.summary
    return (;
        internal_flag = summary.flag,
        internal_passed = summary.passed,
        n_chains = summary.n_chains,
        draws_per_chain = summary.draws_per_chain,
        total_draws = summary.total_draws,
        max_rhat = summary.max_rhat,
        min_ess = summary.min_ess,
        n_bad_rhat = summary.n_bad_rhat,
        n_low_ess = summary.n_low_ess,
        n_divergences = summary.n_divergences,
        n_max_treedepth = summary.n_max_treedepth,
        e_bfmi = summary.e_bfmi,
        n_sampler_warnings = summary.n_sampler_warnings,
        n_block_warnings = summary.n_block_warnings,
        n_direct_block_warnings = summary.n_direct_block_warnings,
        n_nonfinite_logdensity = summary.n_nonfinite_logdensity,
        n_nonfinite_direct_loglikelihood = summary.n_nonfinite_direct_loglikelihood,
        n_failed_direct_constraints = summary.n_failed_direct_constraints,
    )
end

function recovery_row_record(row)
    return (;
        parameter = row.parameter,
        parameter_index = row.parameter_index,
        block = row.block,
        true_value = row.true_value,
        posterior_mean = row.posterior_mean,
        posterior_sd = row.posterior_sd,
        posterior_median = row.posterior_median,
        posterior_lower = row.posterior_lower,
        posterior_upper = row.posterior_upper,
        interval_probability = row.interval_probability,
        bias = row.bias,
        absolute_bias = row.absolute_bias,
        relative_bias = row.relative_bias,
        interval_width = row.interval_width,
        covered = row.covered,
        flag = row.flag,
    )
end

function recovery_summary_record(row)
    return (;
        by = row.by,
        group = row.group,
        n_parameters = row.n_parameters,
        mean_bias = row.mean_bias,
        mean_absolute_error = row.mean_absolute_error,
        rmse = row.rmse,
        median_absolute_error = row.median_absolute_error,
        max_absolute_error = row.max_absolute_error,
        coverage_rate = row.coverage_rate,
        nominal_coverage = row.nominal_coverage,
        coverage_gap = row.coverage_gap,
        mean_interval_width = row.mean_interval_width,
        n_covered = row.n_covered,
        flag = row.flag,
    )
end

function protocol_passed(sampler_summary, recovery_by_block)
    thresholds = PROTOCOL.thresholds
    max_block_mae = maximum(row.mean_absolute_error for row in recovery_by_block)
    max_abs = maximum(row.max_absolute_error for row in recovery_by_block)
    min_coverage = minimum(row.coverage_rate for row in recovery_by_block)
    return sampler_summary.internal_passed &&
        sampler_summary.n_divergences == thresholds.n_divergences &&
        sampler_summary.n_max_treedepth == thresholds.n_max_treedepth &&
        sampler_summary.n_failed_direct_constraints ==
            thresholds.n_failed_direct_constraints &&
        sampler_summary.n_nonfinite_logdensity == thresholds.n_nonfinite_logdensity &&
        sampler_summary.n_nonfinite_direct_loglikelihood ==
            thresholds.n_nonfinite_direct_loglikelihood &&
        sampler_summary.max_rhat <= thresholds.max_rhat &&
        sampler_summary.min_ess >= thresholds.min_ess &&
        sampler_summary.e_bfmi >= thresholds.min_ebfmi &&
        max_block_mae <= thresholds.max_block_mean_absolute_error &&
        max_abs <= thresholds.max_parameter_absolute_error &&
        min_coverage >= thresholds.min_block_coverage_rate
end

function recovery_artifact()
    placeholder_design = confirmatory_mgmfrm_design(placeholder_table())
    placeholder_target = BayesianMGMFRM._source_fixture_logdensity(placeholder_design)
    direct_truth = BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
        placeholder_design,
        TRUTH_RAW,
    )
    table = simulated_table(placeholder_design, direct_truth)
    design = confirmatory_mgmfrm_design(table)
    design.parameter_names == placeholder_design.parameter_names ||
        error("simulated design changed direct parameter order")
    target = BayesianMGMFRM._source_fixture_logdensity(design)
    target.blueprint.parameter_names == placeholder_target.blueprint.parameter_names ||
        error("simulated design changed raw parameter order")
    diagnostics = MGMFRMChainStudy.run_diagnostics(
        target,
        zeros(length(TRUTH_RAW)),
        PROTOCOL.sampler_seed,
    )
    recovery_rows = BayesianMGMFRM.parameter_recovery(
        design,
        diagnostics.direct_draws,
        direct_truth;
        interval = 0.8,
    )
    recovery_by_block = BayesianMGMFRM.parameter_recovery_summary(recovery_rows; by = :block)
    sampler_summary = sampler_summary_record(diagnostics)
    passed = protocol_passed(sampler_summary, recovery_by_block)
    max_block_mae = maximum(row.mean_absolute_error for row in recovery_by_block)
    max_parameter_abs_error = maximum(row.absolute_bias for row in recovery_rows)
    min_block_coverage = minimum(row.coverage_rate for row in recovery_by_block)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_recovery_smoke.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :internal_fit_ready_candidate,
        public_fit = false,
        experimental_public = false,
        fit_ready = false,
        target = :_source_fixture_logdensity,
        density_space = :raw_unconstrained,
        dimensions = PROTOCOL.grid.dimensions,
        q_matrix = PROTOCOL.grid.q_matrix,
        latent_correlation = :identity_fixed,
        ability_scale = :unit_variance_by_dimension,
        source_scale = 1.7,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        raw_parameter_order = target.blueprint.parameter_names,
        raw_parameter_order_sha256 = parameter_order_hash(target.blueprint.parameter_names),
        direct_parameter_order = target.blueprint.constrained_parameter_names,
        direct_parameter_order_sha256 =
            parameter_order_hash(target.blueprint.constrained_parameter_names),
        truth = (;
            raw_parameter_values = TRUTH_RAW,
            direct_parameter_values = direct_truth,
        ),
        simulated_data = (;
            n_observations = design.spec.data.n,
            score_counts = score_count_rows(table.score),
            person_levels = design.spec.data.person_levels,
            rater_levels = design.spec.data.rater_levels,
            item_levels = design.spec.data.item_levels,
            category_levels = design.spec.data.category_levels,
        ),
        sampler_summary,
        recovery_rows = [recovery_row_record(row) for row in recovery_rows],
        recovery_by_block = [recovery_summary_record(row) for row in recovery_by_block],
        baseline_comparison = (;
            status = :pending,
            reason = :public_generalized_fit_not_enabled,
        ),
        summary = (;
            passed,
            n_parameters = length(recovery_rows),
            n_blocks = length(recovery_by_block),
            max_block_mean_absolute_error = max_block_mae,
            max_parameter_absolute_error = max_parameter_abs_error,
            min_block_coverage_rate = min_block_coverage,
            sampler_flag = sampler_summary.internal_flag,
            n_divergences = sampler_summary.n_divergences,
            n_max_treedepth = sampler_summary.n_max_treedepth,
            e_bfmi = sampler_summary.e_bfmi,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = recovery_artifact()
    write_artifact(output, artifact)
    println("Wrote ", output)
    println("passed=", artifact.summary.passed,
        " blocks=", artifact.summary.n_blocks,
        " max_block_mae=", artifact.summary.max_block_mean_absolute_error,
        " max_abs=", artifact.summary.max_parameter_absolute_error,
        " min_coverage=", artifact.summary.min_block_coverage_rate)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
