#!/usr/bin/env julia

using Random
using SHA
using TOML

import AdvancedHMC
import BayesianMGMFRM
import LogDensityProblems
import LogDensityProblemsAD

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT = joinpath(ROOT, "test", "fixtures", "mgmfrm_candidate_chain_study.json")

include(joinpath(@__DIR__, "local_json.jl"))

const NEAR_ORACLE_RAW = [
    0.2, -0.1,
    -0.3, 0.4,
    0.15,
    -0.2, 0.1,
    log(1.5), log(0.7),
    log(1.25),
    0.3, -0.2,
]

const PROTOCOL = (;
    protocol_id = "confirmatory_mgmfrm_candidate_chain_v1",
    backend = :advancedhmc,
    sampler = :nuts,
    chains = 2,
    warmup = 32,
    draws = 32,
    step_size = 0.02,
    target_accept = 0.8,
    max_depth = 8,
    max_energy_error = 1000.0,
    metric = :unit,
    ad_backend = :ForwardDiff,
    init_jitter = 0.0,
    split_chains = true,
    thresholds = (;
        max_rhat = 1.35,
        min_ess = 6.0,
        min_ebfmi = 0.3,
        n_divergences = 0,
        n_max_treedepth = 0,
        n_failed_direct_constraints = 0,
        n_nonfinite_logdensity = 0,
        n_nonfinite_direct_loglikelihood = 0,
    ),
)

const FIXTURE_SPECS = [
    (;
        fixture = "near_oracle",
        seed = 20260711,
        initial_raw_parameter_values = NEAR_ORACLE_RAW,
    ),
    (;
        fixture = "zero_centered",
        seed = 20260712,
        initial_raw_parameter_values = zeros(length(NEAR_ORACLE_RAW)),
    ),
]

function usage()
    return """
    Generate the local confirmatory MGMFRM candidate-chain study artifact.

    Usage:
      julia --project=. scripts/generate_mgmfrm_candidate_chain_study.jl [--output PATH]
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

function confirmatory_mgmfrm_spec()
    table = (;
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        task = ["T1", "T1", "T2", "T1", "T2", "T2"],
        score = [0, 1, 2, 1, 0, 2],
    )
    data = BayesianMGMFRM.FacetData(table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        task = :task,
    )
    return BayesianMGMFRM.mfrm_spec(data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix = Bool[1 0; 0 1],
    )
end

maybe_float(value) = ismissing(value) ? missing : Float64(value)
maybe_int(value) = ismissing(value) ? missing : Int(value)

function parameter_order_hash(names)
    return bytes2hex(sha256(codeunits(join(names, "\n"))))
end

function protocol_passed(summary)
    thresholds = PROTOCOL.thresholds
    return summary.n_divergences == thresholds.n_divergences &&
        summary.n_max_treedepth == thresholds.n_max_treedepth &&
        summary.n_failed_direct_constraints == thresholds.n_failed_direct_constraints &&
        summary.n_nonfinite_logdensity == thresholds.n_nonfinite_logdensity &&
        summary.n_nonfinite_direct_loglikelihood ==
            thresholds.n_nonfinite_direct_loglikelihood &&
        isfinite(summary.max_rhat) &&
        summary.max_rhat <= thresholds.max_rhat &&
        isfinite(summary.min_ess) &&
        summary.min_ess >= thresholds.min_ess &&
        isfinite(summary.e_bfmi) &&
        summary.e_bfmi >= thresholds.min_ebfmi
end

function sampler_row_record(row)
    return (;
        chain = row.chain,
        acceptance_rate = row.acceptance_rate,
        n_divergences = maybe_int(row.n_divergences),
        n_max_treedepth = maybe_int(row.n_max_treedepth),
        e_bfmi = maybe_float(row.e_bfmi),
        mean_n_steps = maybe_float(row.mean_n_steps),
        mean_tree_depth = maybe_float(row.mean_tree_depth),
        max_tree_depth = maybe_int(row.max_tree_depth),
        mean_step_size = maybe_float(row.mean_step_size),
        n_nonfinite_logdensity = row.n_nonfinite_logdensity,
        flag = row.flag,
    )
end

function block_row_record(row)
    return (;
        block = row.block,
        n_parameters = row.n_parameters,
        max_rhat = maybe_float(row.max_rhat),
        min_ess = maybe_float(row.min_ess),
        n_bad_rhat = row.n_bad_rhat,
        n_low_ess = row.n_low_ess,
        n_insufficient_chains = row.n_insufficient_chains,
        n_degenerate_parameters = row.n_degenerate_parameters,
        flag = row.flag,
    )
end

function direct_constraint_rows(design, direct_params)
    rater_values = direct_params[design.blocks[:rater]]
    loading_values = direct_params[design.blocks[:item_dimension_discrimination]]
    consistency_values = direct_params[design.blocks[:rater_consistency]]
    item_step_values = direct_params[design.blocks[:item_steps]]
    rows = [
        (constraint = :rater_sum_to_zero, block = :rater,
            value = Float64(sum(rater_values)), target = 0.0,
            tolerance = 1e-8, passed = abs(sum(rater_values)) <= 1e-8),
        (constraint = :item_dimension_discrimination_positive,
            block = :item_dimension_discrimination,
            value = Float64(minimum(loading_values)), target = 0.0,
            tolerance = 0.0, passed = all(>(0), loading_values)),
        (constraint = :rater_consistency_positive, block = :rater_consistency,
            value = Float64(minimum(consistency_values)), target = 0.0,
            tolerance = 0.0, passed = all(>(0), consistency_values)),
        (constraint = :rater_consistency_product_one,
            block = :rater_consistency,
            value = Float64(prod(consistency_values)), target = 1.0,
            tolerance = 1e-8,
            passed = abs(prod(consistency_values) - 1) <= 1e-8),
    ]
    free_steps = max(length(design.spec.data.category_levels) - 2, 0)
    if free_steps > 0 && !isempty(item_step_values)
        for item_index in eachindex(design.spec.data.item_levels)
            step_sum = sum(item_step_values[
                ((item_index - 1) * free_steps + 1):(item_index * free_steps)];
                init = 0.0,
            )
            push!(rows, (constraint = :item_step_last_derived_sum_to_zero,
                block = :item_steps,
                value = Float64(step_sum + (-step_sum)),
                target = 0.0,
                tolerance = 1e-8,
                passed = true))
        end
    end
    return rows
end

function direct_draw_constraint_rows(design, direct_draws)
    n_draws = size(direct_draws, 1)
    n_draws == 0 && return NamedTuple[]
    template = direct_constraint_rows(design, @view direct_draws[1, :])
    values = [Float64[] for _ in template]
    n_failed = zeros(Int, length(template))
    for draw in 1:n_draws
        rows = direct_constraint_rows(design, @view direct_draws[draw, :])
        length(rows) == length(template) ||
            throw(ArgumentError("direct constraint row count changed across draws"))
        for index in eachindex(rows)
            rows[index].constraint === template[index].constraint &&
                rows[index].block === template[index].block ||
                throw(ArgumentError("direct constraint row identity changed across draws"))
            push!(values[index], Float64(rows[index].value))
            rows[index].passed || (n_failed[index] += 1)
        end
    end
    rows = NamedTuple[]
    for index in eachindex(template)
        row_values = values[index]
        target = Float64(template[index].target)
        push!(rows, (;
            constraint_index = index,
            constraint = template[index].constraint,
            block = template[index].block,
            target,
            tolerance = Float64(template[index].tolerance),
            n_draws,
            n_failed = n_failed[index],
            minimum_value = minimum(row_values),
            maximum_value = maximum(row_values),
            max_abs_target_error = maximum(abs(value - target) for value in row_values),
            passed = n_failed[index] == 0,
        ))
    end
    return rows
end

function constraint_row_record(row)
    return (;
        constraint = row.constraint,
        block = row.block,
        n_failed = row.n_failed,
        minimum_value = row.minimum_value,
        maximum_value = row.maximum_value,
        max_abs_target_error = row.max_abs_target_error,
        passed = row.passed,
    )
end

function direct_draw_values(target, raw_draws)
    n_draws = size(raw_draws, 1)
    n_direct = length(target.blueprint.constrained_parameter_names)
    n_observations = target.design.spec.data.n
    direct_draws = Matrix{Float64}(undef, n_draws, n_direct)
    pointwise = Matrix{Float64}(undef, n_draws, n_observations)
    loglikelihood = Vector{Float64}(undef, n_draws)
    for draw in 1:n_draws
        raw = collect(@view raw_draws[draw, :])
        direct = BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
            target.design,
            raw,
        )
        direct_pointwise = BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood(
            target.design,
            direct,
        )
        direct_draws[draw, :] .= direct
        pointwise[draw, :] .= direct_pointwise
        loglikelihood[draw] = sum(direct_pointwise; init = 0.0)
    end
    return (;
        direct_draws,
        pointwise_loglikelihood = pointwise,
        loglikelihood,
    )
end

function pointwise_summary(diagnostics)
    pointwise = vec(diagnostics.pointwise_loglikelihood)
    loglikelihood = diagnostics.loglikelihood
    return (;
        n_observations = size(diagnostics.pointwise_loglikelihood, 2),
        n_draws = size(diagnostics.pointwise_loglikelihood, 1),
        n_nonfinite_pointwise = count(!isfinite, pointwise),
        n_nonfinite_loglikelihood = count(!isfinite, loglikelihood),
        minimum_pointwise_loglikelihood = minimum(pointwise),
        maximum_pointwise_loglikelihood = maximum(pointwise),
        minimum_loglikelihood = minimum(loglikelihood),
        maximum_loglikelihood = maximum(loglikelihood),
    )
end

function run_diagnostics(target, raw_initial, seed)
    nparams = LogDensityProblems.dimension(target)
    initial = Float64.(collect(raw_initial))
    LogDensityProblems.logdensity(target, initial) |> isfinite ||
        throw(ArgumentError("initial raw parameter vector has non-finite log density"))
    rng = Random.MersenneTwister(seed)
    total_draws = PROTOCOL.draws * PROTOCOL.chains
    draws = Matrix{Float64}(undef, total_draws, nparams)
    logdensities = Vector{Float64}(undef, total_draws)
    chain_ids = Vector{Int}(undef, total_draws)
    iterations = Vector{Int}(undef, total_draws)
    chain_acceptance = Vector{Float64}(undef, PROTOCOL.chains)
    sampler_stats = NamedTuple[]

    for chain in 1:PROTOCOL.chains
        chain_initial = BayesianMGMFRM._advancedhmc_initial(
            initial,
            rng,
            Float64(PROTOCOL.init_jitter),
        )
        adtarget = LogDensityProblemsAD.ADgradient(PROTOCOL.ad_backend, target;
            x = chain_initial)
        metric_object = BayesianMGMFRM._advancedhmc_metric(PROTOCOL.metric, nparams)
        hamiltonian = AdvancedHMC.Hamiltonian(
            metric_object,
            x -> LogDensityProblems.logdensity(adtarget, x),
            x -> LogDensityProblems.logdensity_and_gradient(adtarget, x),
        )
        integrator = AdvancedHMC.Leapfrog(Float64(PROTOCOL.step_size))
        kernel = AdvancedHMC.HMCKernel(AdvancedHMC.Trajectory{AdvancedHMC.MultinomialTS}(
            integrator,
            AdvancedHMC.GeneralisedNoUTurn(
                PROTOCOL.max_depth,
                Float64(PROTOCOL.max_energy_error),
            ),
        ))
        adaptor = PROTOCOL.warmup > 0 ?
            AdvancedHMC.StanHMCAdaptor(
                AdvancedHMC.MassMatrixAdaptor(metric_object),
                AdvancedHMC.StepSizeAdaptor(Float64(PROTOCOL.target_accept), integrator),
            ) :
            AdvancedHMC.NoAdaptation()
        samples, stats = AdvancedHMC.sample(
            rng,
            hamiltonian,
            kernel,
            chain_initial,
            PROTOCOL.warmup + PROTOCOL.draws,
            adaptor,
            PROTOCOL.warmup;
            drop_warmup = PROTOCOL.warmup > 0,
            verbose = false,
            progress = false,
        )
        length(samples) == PROTOCOL.draws ||
            throw(ArgumentError("AdvancedHMC returned $(length(samples)) draw(s); expected $(PROTOCOL.draws)"))
        chain_stats = NamedTuple[]
        for iteration in 1:PROTOCOL.draws
            row = (chain - 1) * PROTOCOL.draws + iteration
            draws[row, :] .= samples[iteration]
            stat_row = BayesianMGMFRM._advancedhmc_stat_row(stats[iteration], chain, iteration)
            logdensities[row] = stat_row.log_density
            chain_ids[row] = chain
            iterations[row] = iteration
            push!(chain_stats, stat_row)
            push!(sampler_stats, stat_row)
        end
        chain_acceptance[chain] = BayesianMGMFRM._stat_mean(chain_stats, :acceptance_rate)
    end

    sampler_rows = NamedTuple[]
    for chain in 1:PROTOCOL.chains
        draw_rows = ((chain - 1) * PROTOCOL.draws + 1):(chain * PROTOCOL.draws)
        logps = @view logdensities[draw_rows]
        logdensity_summary = BayesianMGMFRM._finite_log_posterior_summary(logps)
        n_finite = count(isfinite, logps)
        n_nonfinite = length(logps) - n_finite
        chain_stats = [row for row in sampler_stats if row.chain == chain]
        sampler_summary =
            BayesianMGMFRM._candidate_chain_sampler_summary(chain_stats, PROTOCOL.max_depth)
        push!(sampler_rows, (;
            chain,
            backend = :advancedhmc,
            sampler = :nuts,
            n_draws = PROTOCOL.draws,
            warmup = PROTOCOL.warmup,
            step_size = Float64(PROTOCOL.step_size),
            first_iteration = first(@view iterations[draw_rows]),
            last_iteration = last(@view iterations[draw_rows]),
            acceptance_rate = chain_acceptance[chain],
            mean_logdensity = logdensity_summary.mean,
            minimum_logdensity = logdensity_summary.minimum,
            maximum_logdensity = logdensity_summary.maximum,
            n_finite_logdensity = n_finite,
            n_nonfinite_logdensity = n_nonfinite,
            n_divergences = sampler_summary.n_divergences,
            n_max_treedepth = sampler_summary.n_max_treedepth,
            mean_n_steps = sampler_summary.mean_n_steps,
            mean_tree_depth = sampler_summary.mean_tree_depth,
            max_tree_depth = sampler_summary.max_tree_depth,
            mean_step_size = sampler_summary.mean_step_size,
            e_bfmi = sampler_summary.e_bfmi,
            flag = BayesianMGMFRM._sampler_diagnostic_flag(chain_acceptance[chain],
                n_nonfinite,
                sampler_summary.n_divergences,
                sampler_summary.n_max_treedepth),
        ))
    end

    actual_split = PROTOCOL.split_chains && PROTOCOL.chains >= 2 && PROTOCOL.draws >= 4
    parameter_rows = BayesianMGMFRM._candidate_mcmc_diagnostic_rows(
        draws,
        target.blueprint.parameter_names,
        PROTOCOL.chains;
        split_chains = PROTOCOL.split_chains,
        rhat_threshold = PROTOCOL.thresholds.max_rhat,
        ess_threshold = PROTOCOL.thresholds.min_ess,
    )
    block_rows = BayesianMGMFRM._candidate_parameter_block_diagnostics(
        target.blueprint.blocks,
        target.blueprint.parameter_names,
        parameter_rows;
        chains = PROTOCOL.chains,
        draws_per_chain = PROTOCOL.draws,
        total_draws,
        split_chains = actual_split,
        rhat_threshold = PROTOCOL.thresholds.max_rhat,
        ess_threshold = PROTOCOL.thresholds.min_ess,
    )
    direct_values = direct_draw_values(target, draws)
    direct_constraint_rows =
        direct_draw_constraint_rows(target.design, direct_values.direct_draws)
    direct_parameter_rows = BayesianMGMFRM._candidate_mcmc_diagnostic_rows(
        direct_values.direct_draws,
        target.blueprint.constrained_parameter_names,
        PROTOCOL.chains;
        split_chains = PROTOCOL.split_chains,
        rhat_threshold = PROTOCOL.thresholds.max_rhat,
        ess_threshold = PROTOCOL.thresholds.min_ess,
    )
    direct_block_rows = BayesianMGMFRM._candidate_parameter_block_diagnostics(
        target.blueprint.constrained_blocks,
        target.blueprint.constrained_parameter_names,
        direct_parameter_rows;
        chains = PROTOCOL.chains,
        draws_per_chain = PROTOCOL.draws,
        total_draws,
        split_chains = actual_split,
        rhat_threshold = PROTOCOL.thresholds.max_rhat,
        ess_threshold = PROTOCOL.thresholds.min_ess,
    )

    n_sampler_warnings = count(row -> row.flag !== :ok, sampler_rows)
    n_block_warnings = count(row -> row.flag in
        (:insufficient_chains, :degenerate_draws, :mcmc_warning), block_rows)
    n_direct_block_warnings = count(row -> row.flag in
        (:insufficient_chains, :degenerate_draws, :mcmc_warning), direct_block_rows)
    n_nonfinite_logdensity = sum(row.n_nonfinite_logdensity for row in sampler_rows)
    n_nonfinite_direct_loglikelihood =
        count(!isfinite, direct_values.loglikelihood) +
        count(!isfinite, direct_values.pointwise_loglikelihood)
    n_failed_direct_constraints = sum(row.n_failed for row in direct_constraint_rows)
    n_divergences = BayesianMGMFRM._sum_nonmissing(row.n_divergences for row in sampler_rows)
    n_max_treedepth =
        BayesianMGMFRM._sum_nonmissing(row.n_max_treedepth for row in sampler_rows)
    e_bfmi = BayesianMGMFRM._min_nonmissing(row.e_bfmi for row in sampler_rows)
    n_insufficient = count(row -> row.flag === :insufficient_chains, parameter_rows)
    n_degenerate = count(row -> row.flag === :degenerate_draws, parameter_rows)
    n_bad_rhat = count(row -> isfinite(row.rhat) &&
        row.rhat > PROTOCOL.thresholds.max_rhat, parameter_rows)
    n_low_ess = count(row -> isfinite(row.ess) &&
        row.ess < PROTOCOL.thresholds.min_ess, parameter_rows)
    max_rhat = BayesianMGMFRM._finite_extreme((row.rhat for row in parameter_rows), maximum)
    min_ess = BayesianMGMFRM._finite_extreme((row.ess for row in parameter_rows), minimum)
    flag = BayesianMGMFRM._gmfrm_promotion_candidate_summary_flag(
        n_sampler_warnings,
        n_nonfinite_logdensity,
        n_failed_direct_constraints,
        n_nonfinite_direct_loglikelihood,
        n_insufficient,
        n_degenerate,
        n_bad_rhat,
        n_low_ess,
    )
    initial_direct = BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
        target.design,
        initial,
    )

    return (;
        schema = "bayesianmgmfrm.mgmfrm_confirmatory_candidate_sampler_diagnostics.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :internal_fit_ready_candidate,
        public_fit = false,
        fit_ready = false,
        target = :_source_fixture_logdensity,
        density_space = :raw_unconstrained,
        backend = :advancedhmc,
        sampler = :nuts,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        direct_parameter_names = copy(target.blueprint.constrained_parameter_names),
        initial_raw_parameter_values = copy(initial),
        initial_direct_parameter_values = copy(initial_direct),
        draws,
        logdensity = logdensities,
        direct_draws = direct_values.direct_draws,
        direct_pointwise_loglikelihood = direct_values.pointwise_loglikelihood,
        direct_loglikelihood = direct_values.loglikelihood,
        chain_ids,
        iterations,
        chain_acceptance_rate = chain_acceptance,
        sampler_stats,
        sampler_rows,
        parameter_rows,
        block_rows,
        direct_constraint_rows,
        direct_parameter_rows,
        direct_block_rows,
        summary = (;
            flag,
            passed = flag === :ok,
            n_chains = PROTOCOL.chains,
            draws_per_chain = PROTOCOL.draws,
            total_draws,
            n_parameters = nparams,
            n_direct_parameters = size(direct_values.direct_draws, 2),
            split_chains = actual_split,
            rhat_threshold = PROTOCOL.thresholds.max_rhat,
            ess_threshold = PROTOCOL.thresholds.min_ess,
            max_rhat,
            min_ess,
            n_bad_rhat,
            n_low_ess,
            n_insufficient_chains = n_insufficient,
            n_degenerate_parameters = n_degenerate,
            n_block_warnings,
            n_direct_block_warnings,
            n_sampler_warnings,
            n_nonfinite_logdensity,
            n_nonfinite_direct_loglikelihood,
            n_direct_constraints = length(direct_constraint_rows),
            n_failed_direct_constraints,
            n_divergences,
            n_max_treedepth,
            e_bfmi,
        ),
    )
end

function fixture_record(target, spec)
    diagnostics = run_diagnostics(target, spec.initial_raw_parameter_values, spec.seed)
    passed = protocol_passed(diagnostics.summary)
    return (;
        fixture = spec.fixture,
        seed = spec.seed,
        initial_raw_parameter_values = collect(spec.initial_raw_parameter_values),
        initial_direct_parameter_values = diagnostics.initial_direct_parameter_values,
        summary = (;
            internal_flag = diagnostics.summary.flag,
            internal_passed = diagnostics.summary.passed,
            passed_protocol = passed,
            n_chains = diagnostics.summary.n_chains,
            draws_per_chain = diagnostics.summary.draws_per_chain,
            total_draws = diagnostics.summary.total_draws,
            max_rhat = diagnostics.summary.max_rhat,
            min_ess = diagnostics.summary.min_ess,
            n_bad_rhat = diagnostics.summary.n_bad_rhat,
            n_low_ess = diagnostics.summary.n_low_ess,
            n_divergences = diagnostics.summary.n_divergences,
            n_max_treedepth = diagnostics.summary.n_max_treedepth,
            e_bfmi = diagnostics.summary.e_bfmi,
            n_sampler_warnings = diagnostics.summary.n_sampler_warnings,
            n_block_warnings = diagnostics.summary.n_block_warnings,
            n_direct_block_warnings = diagnostics.summary.n_direct_block_warnings,
            n_nonfinite_logdensity = diagnostics.summary.n_nonfinite_logdensity,
            n_nonfinite_direct_loglikelihood =
                diagnostics.summary.n_nonfinite_direct_loglikelihood,
            n_failed_direct_constraints = diagnostics.summary.n_failed_direct_constraints,
        ),
        sampler_rows = [sampler_row_record(row) for row in diagnostics.sampler_rows],
        raw_block_rows = [block_row_record(row) for row in diagnostics.block_rows],
        direct_block_rows = [block_row_record(row) for row in diagnostics.direct_block_rows],
        direct_constraint_rows =
            [constraint_row_record(row) for row in diagnostics.direct_constraint_rows],
        pointwise = pointwise_summary((;
            pointwise_loglikelihood = diagnostics.direct_pointwise_loglikelihood,
            loglikelihood = diagnostics.direct_loglikelihood,
        )),
    )
end

function project_version()
    project = TOML.parsefile(joinpath(ROOT, "Project.toml"))
    return String(project["version"])
end

function study_artifact()
    spec = confirmatory_mgmfrm_spec()
    design = BayesianMGMFRM.getdesign(spec; preview = true)
    target = BayesianMGMFRM._source_fixture_logdensity(design)
    records = [fixture_record(target, fixture) for fixture in FIXTURE_SPECS]
    summaries = [record.summary for record in records]
    return (;
        schema = "bayesianmgmfrm.mgmfrm_candidate_chain_study.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :internal_fit_ready_candidate,
        public_fit = false,
        fit_ready = false,
        target = :_source_fixture_logdensity,
        density_space = :raw_unconstrained,
        dimensions = spec.dimensions,
        q_matrix = [[spec.q_matrix[row, col] for col in axes(spec.q_matrix, 2)]
            for row in axes(spec.q_matrix, 1)],
        latent_correlation = :identity_fixed,
        ability_scale = :unit_variance_by_dimension,
        source_scale = 1.7,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        data = (;
            n_observations = spec.data.n,
            person_levels = spec.data.person_levels,
            rater_levels = spec.data.rater_levels,
            item_levels = spec.data.item_levels,
            category_levels = spec.data.category_levels,
            optional_facets = collect(keys(spec.data.optional_levels)),
        ),
        raw_parameter_order = target.blueprint.parameter_names,
        raw_parameter_order_sha256 = parameter_order_hash(target.blueprint.parameter_names),
        direct_parameter_order = target.blueprint.constrained_parameter_names,
        direct_parameter_order_sha256 =
            parameter_order_hash(target.blueprint.constrained_parameter_names),
        fixtures = records,
        summary = (;
            n_fixtures = length(records),
            n_passed_protocol = count(record -> record.summary.passed_protocol, records),
            overall_passed = all(record -> record.summary.passed_protocol, records),
            max_rhat = maximum(summary.max_rhat for summary in summaries),
            min_ess = minimum(summary.min_ess for summary in summaries),
            min_ebfmi = minimum(summary.e_bfmi for summary in summaries),
            n_divergences = sum(summary.n_divergences for summary in summaries),
            n_max_treedepth = sum(summary.n_max_treedepth for summary in summaries),
            n_failed_direct_constraints =
                sum(summary.n_failed_direct_constraints for summary in summaries),
            n_nonfinite_logdensity =
                sum(summary.n_nonfinite_logdensity for summary in summaries),
            n_nonfinite_direct_loglikelihood =
                sum(summary.n_nonfinite_direct_loglikelihood for summary in summaries),
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = study_artifact()
    write_artifact(output, artifact)
    println("Wrote ", output)
    println("overall_passed=", artifact.summary.overall_passed,
        " fixtures=", artifact.summary.n_fixtures,
        " max_rhat=", artifact.summary.max_rhat,
        " min_ess=", artifact.summary.min_ess,
        " min_ebfmi=", artifact.summary.min_ebfmi)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
