#!/usr/bin/env julia

using SHA
using TOML

import BayesianMGMFRM

module MGMFRMRecoverySmoke
include(joinpath(@__DIR__, "generate_mgmfrm_recovery_smoke.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT = joinpath(ROOT, "test", "fixtures", "mgmfrm_baseline_comparison.json")

include(joinpath(@__DIR__, "local_json.jl"))

const RECOVERY_PROTOCOL = MGMFRMRecoverySmoke.PROTOCOL

const PROTOCOL = (;
    protocol_id = "confirmatory_mgmfrm_baseline_comparison_v1",
    simulation_source = :confirmatory_mgmfrm_recovery_smoke_v1,
    simulation_seed = RECOVERY_PROTOCOL.simulation_seed,
    data_grid = RECOVERY_PROTOCOL.grid,
    mgmfrm_sampler = (;
        backend = RECOVERY_PROTOCOL.sampler.backend,
        sampler = RECOVERY_PROTOCOL.sampler.sampler,
        seed = RECOVERY_PROTOCOL.sampler_seed,
        chains = RECOVERY_PROTOCOL.sampler.chains,
        warmup = RECOVERY_PROTOCOL.sampler.warmup,
        draws = RECOVERY_PROTOCOL.sampler.draws,
        step_size = RECOVERY_PROTOCOL.sampler.step_size,
        target_accept = RECOVERY_PROTOCOL.sampler.target_accept,
        max_depth = RECOVERY_PROTOCOL.sampler.max_depth,
        max_energy_error = RECOVERY_PROTOCOL.sampler.max_energy_error,
        metric = RECOVERY_PROTOCOL.sampler.metric,
        ad_backend = RECOVERY_PROTOCOL.sampler.ad_backend,
        init_jitter = RECOVERY_PROTOCOL.sampler.init_jitter,
        split_chains = RECOVERY_PROTOCOL.sampler.split_chains,
    ),
    baseline_sampler = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 2,
        warmup = 32,
        draws = 32,
        step_size = 0.03,
        target_accept = 0.8,
        max_depth = 6,
        max_energy_error = 1000.0,
        metric = :unit,
        ad_backend = :ForwardDiff,
        init_jitter = 0.0,
        split_chains = true,
        seeds = (;
            partial_credit = 20260762,
            rating_scale = 20260763,
        ),
    ),
    diagnostics = (;
        rhat_threshold = 1.5,
        ess_threshold = 4.0,
    ),
    thresholds = (;
        minimum_models = 3,
        n_observations = RECOVERY_PROTOCOL.grid.observations,
        require_same_observations = true,
        require_finite_elpd = true,
        require_finite_weights = true,
    ),
)

function usage()
    return """
    Generate the local confirmatory MGMFRM baseline-comparison artifact.

    Usage:
      julia --project=. scripts/generate_mgmfrm_baseline_comparison.jl [--output PATH]
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

function parameter_order_hash(names)
    return bytes2hex(sha256(codeunits(join(names, "\n"))))
end

function simulated_mgmfrm_table()
    placeholder_design = MGMFRMRecoverySmoke.confirmatory_mgmfrm_design(
        MGMFRMRecoverySmoke.placeholder_table(),
    )
    direct_truth =
        BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
            placeholder_design,
            MGMFRMRecoverySmoke.TRUTH_RAW,
        )
    table = MGMFRMRecoverySmoke.simulated_table(placeholder_design, direct_truth)
    return (; placeholder_design, direct_truth, table)
end

function pointwise_se(values::AbstractVector{<:Real})
    n = length(values)
    n <= 1 && return NaN
    mean_value = sum(Float64, values) / n
    ss = sum((Float64(value) - mean_value)^2 for value in values)
    return sqrt(n * ss / (n - 1))
end

function score_count_rows(scores)
    return [(score = value, n = count(==(value), scores))
        for value in sort(unique(scores))]
end

function maybe_float(value)
    return ismissing(value) ? missing : Float64(value)
end

function maybe_int(value)
    return ismissing(value) ? missing : Int(value)
end

function mgmfrm_sampler_summary_record(summary)
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
        n_nonfinite_direct_loglikelihood =
            summary.n_nonfinite_direct_loglikelihood,
        n_failed_direct_constraints = summary.n_failed_direct_constraints,
    )
end

function baseline_sampler_summary_record(summary)
    return (;
        internal_flag = summary.flag,
        internal_passed = summary.passed,
        n_chains = summary.n_chains,
        draws_per_chain = summary.draws_per_chain,
        total_draws = summary.total_draws,
        n_parameters = summary.n_parameters,
        max_rhat = maybe_float(summary.max_rhat),
        min_ess = maybe_float(summary.min_ess),
        n_bad_rhat = summary.n_bad_rhat,
        n_low_ess = summary.n_low_ess,
        n_divergences = maybe_int(summary.n_divergences),
        n_max_treedepth = maybe_int(summary.n_max_treedepth),
        e_bfmi = maybe_float(summary.e_bfmi),
        n_sampler_warnings = summary.n_sampler_warnings,
        n_block_warnings = summary.n_block_warnings,
        n_nonfinite_log_posterior = summary.n_nonfinite_log_posterior,
    )
end

function mgmfrm_candidate_record(table)
    design = MGMFRMRecoverySmoke.confirmatory_mgmfrm_design(table)
    target = BayesianMGMFRM._source_fixture_logdensity(design)
    sampler = PROTOCOL.mgmfrm_sampler
    diagnostics = MGMFRMRecoverySmoke.MGMFRMChainStudy.run_diagnostics(
        target,
        zeros(length(MGMFRMRecoverySmoke.TRUTH_RAW)),
        sampler.seed,
    )
    stat = BayesianMGMFRM.waic(diagnostics.direct_pointwise_loglikelihood)
    record = (;
        model = :mgmfrm_internal_candidate,
        family = :mgmfrm,
        source = :internal_source_fixture_candidate,
        threshold_regime = :confirmatory_fixed_q_multidimensional_partial_credit,
        estimation_status = :internal_fit_ready_candidate,
        public_fit = false,
        n_parameters = target.blueprint.n_parameters,
        parameter_order_sha256 = parameter_order_hash(target.blueprint.parameter_names),
        direct_parameter_order_sha256 =
            parameter_order_hash(target.blueprint.constrained_parameter_names),
        sampler_summary = mgmfrm_sampler_summary_record(diagnostics.summary),
    )
    return (; record, stat)
end

function baseline_record(data, model::Symbol, thresholds::Symbol, seed::Int)
    spec = BayesianMGMFRM.mfrm_spec(data; thresholds)
    design = BayesianMGMFRM.getdesign(spec)
    sampler = PROTOCOL.baseline_sampler
    prior = BayesianMGMFRM.MFRMPrior()
    fit = BayesianMGMFRM.fit(design;
        prior,
        backend = sampler.backend,
        ndraws = sampler.draws,
        warmup = sampler.warmup,
        chains = sampler.chains,
        step_size = sampler.step_size,
        seed,
        target_accept = sampler.target_accept,
        max_depth = sampler.max_depth,
        max_energy_error = sampler.max_energy_error,
        metric = sampler.metric,
        ad_backend = sampler.ad_backend,
        init_jitter = sampler.init_jitter,
        progress = false)
    diagnostics = BayesianMGMFRM.diagnostics(fit;
        split_chains = sampler.split_chains,
        rhat_threshold = PROTOCOL.diagnostics.rhat_threshold,
        ess_threshold = PROTOCOL.diagnostics.ess_threshold)
    stat = BayesianMGMFRM.waic(fit)
    record = (;
        model,
        family = :mfrm,
        source = :public_minimal_fit,
        threshold_regime = thresholds,
        estimation_status = :fit_supported,
        public_fit = true,
        n_parameters = length(design.parameter_names),
        parameter_order_sha256 = parameter_order_hash(design.parameter_names),
        direct_parameter_order_sha256 = missing,
        sampler_summary = baseline_sampler_summary_record(diagnostics.summary),
    )
    return (; record, stat)
end

function comparison_rows(records, stats)
    order = sortperm(eachindex(stats); by = index -> stats[index].elpd_waic, rev = true)
    best = stats[order[1]]
    unnormalized_weights = [exp(stat.elpd_waic - best.elpd_waic) for stat in stats]
    weight_total = sum(unnormalized_weights)
    rows = NamedTuple[]
    for (rank, index) in pairs(order)
        stat = stats[index]
        record = records[index]
        pointwise_difference = stat.pointwise.elpd_waic .- best.pointwise.elpd_waic
        push!(rows, (;
            record...,
            rank,
            criterion = :waic,
            elpd_waic = stat.elpd_waic,
            elpd_difference = stat.elpd_waic - best.elpd_waic,
            se_elpd_difference = pointwise_se(pointwise_difference),
            se_elpd_waic = stat.se_elpd_waic,
            waic = stat.waic,
            waic_difference = stat.waic - best.waic,
            se_waic = stat.se_waic,
            relative_weight = unnormalized_weights[index] / weight_total,
            p_waic = stat.p_waic,
            lppd = stat.lppd,
            n_draws = stat.n_draws,
            n_observations = stat.n_observations,
            high_variance_count = stat.high_variance_count,
            warning = stat.warning,
        ))
    end
    return rows
end

function comparison_passed(rows)
    thresholds = PROTOCOL.thresholds
    length(rows) >= thresholds.minimum_models || return false
    observations = [row.n_observations for row in rows]
    if thresholds.require_same_observations && length(unique(observations)) != 1
        return false
    end
    only(unique(observations)) == thresholds.n_observations || return false
    if thresholds.require_finite_elpd
        all(row -> isfinite(row.elpd_waic) && isfinite(row.waic), rows) ||
            return false
    end
    if thresholds.require_finite_weights
        all(row -> isfinite(row.relative_weight), rows) || return false
        isapprox(sum(row.relative_weight for row in rows), 1.0; atol = 1e-10) ||
            return false
    end
    return true
end

function baseline_comparison_artifact()
    simulated = simulated_mgmfrm_table()
    table = simulated.table
    data = MGMFRMRecoverySmoke.facet_data(table)
    mgmfrm = mgmfrm_candidate_record(table)
    partial_credit = baseline_record(
        data,
        :mfrm_partial_credit,
        :partial_credit,
        PROTOCOL.baseline_sampler.seeds.partial_credit,
    )
    rating_scale = baseline_record(
        data,
        :mfrm_rating_scale,
        :rating_scale,
        PROTOCOL.baseline_sampler.seeds.rating_scale,
    )
    model_results = [mgmfrm, partial_credit, rating_scale]
    records = [result.record for result in model_results]
    stats = [result.stat for result in model_results]
    rows = comparison_rows(records, stats)
    mgmfrm_row = only(row for row in rows if row.model === :mgmfrm_internal_candidate)
    passed = comparison_passed(rows)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_baseline_comparison.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :internal_baseline_comparison,
        public_fit = false,
        experimental_public = false,
        fit_ready = false,
        dimensions = PROTOCOL.data_grid.dimensions,
        q_matrix = PROTOCOL.data_grid.q_matrix,
        latent_correlation = :identity_fixed,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        simulated_data = (;
            n_observations = length(table.score),
            score_counts = score_count_rows(table.score),
            person_levels = data.person_levels,
            rater_levels = data.rater_levels,
            item_levels = data.item_levels,
            category_levels = data.category_levels,
            truth_source = :mgmfrm_recovery_smoke_truth,
            raw_parameter_order_sha256 =
                mgmfrm.record.parameter_order_sha256,
            direct_parameter_order_sha256 =
                mgmfrm.record.direct_parameter_order_sha256,
        ),
        model_rows = rows,
        summary = (;
            passed,
            comparison_executed = true,
            n_models = length(rows),
            best_model = rows[1].model,
            mgmfrm_rank = mgmfrm_row.rank,
            mgmfrm_elpd_difference = mgmfrm_row.elpd_difference,
            mgmfrm_relative_weight = mgmfrm_row.relative_weight,
            any_high_variance_waic = any(row -> row.warning !== :ok, rows),
            public_fit_allowed = false,
            experimental_keyword_enabled = false,
            recommendation = :keep_internal_until_sparse_recovery_grid,
            next_gate = :mgmfrm_sparse_recovery_grid,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = baseline_comparison_artifact()
    write_artifact(output, artifact)
    println("Wrote ", output)
    println("passed=", artifact.summary.passed,
        " best=", artifact.summary.best_model,
        " mgmfrm_rank=", artifact.summary.mgmfrm_rank,
        " mgmfrm_elpd_diff=", artifact.summary.mgmfrm_elpd_difference)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
