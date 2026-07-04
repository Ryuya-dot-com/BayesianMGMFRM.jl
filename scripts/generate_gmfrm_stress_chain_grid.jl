#!/usr/bin/env julia

using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT = joinpath(ROOT, "test", "fixtures", "gmfrm_stress_chain_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

module GMFRMCandidateChain
include(joinpath(@__DIR__, "generate_gmfrm_candidate_chain_study.jl"))
end

const NEAR_ORACLE_RAW = GMFRMCandidateChain.NEAR_ORACLE_RAW

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_stress_chain_grid_v1",
    backend = :advancedhmc,
    sampler = :nuts,
    chains = 2,
    warmup = 96,
    draws = 96,
    max_energy_error = 1000.0,
    metric = :unit,
    ad_backend = :ForwardDiff,
    split_chains = true,
    thresholds = (;
        max_rhat = 1.2,
        min_ess = 16.0,
        min_ebfmi = 0.3,
        n_divergences = 0,
        n_max_treedepth = 0,
        n_failed_direct_constraints = 0,
        n_nonfinite_logdensity = 0,
        n_nonfinite_direct_loglikelihood = 0,
    ),
)

const GRID_SPECS = [
    (;
        scenario = "near_oracle_long",
        seed = 20260711,
        initial_raw_parameter_values = NEAR_ORACLE_RAW,
        step_size = 0.02,
        target_accept = 0.85,
        max_depth = 6,
        init_jitter = 0.0,
    ),
    (;
        scenario = "zero_centered_long",
        seed = 20260712,
        initial_raw_parameter_values = zeros(length(NEAR_ORACLE_RAW)),
        step_size = 0.02,
        target_accept = 0.85,
        max_depth = 6,
        init_jitter = 0.0,
    ),
    (;
        scenario = "near_oracle_high_acceptance",
        seed = 20260713,
        initial_raw_parameter_values = NEAR_ORACLE_RAW,
        step_size = 0.015,
        target_accept = 0.9,
        max_depth = 7,
        init_jitter = 0.02,
    ),
]

function usage()
    return """
    Generate the local scalar GMFRM stress-chain grid artifact.

    Usage:
      julia --project=. scripts/generate_gmfrm_stress_chain_grid.jl [--output PATH]
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

function scenario_record(target, spec)
    diagnostics = BayesianMGMFRM._gmfrm_promotion_candidate_sampler_diagnostics(
        target,
        spec.initial_raw_parameter_values;
        seed = spec.seed,
        ndraws = PROTOCOL.draws,
        warmup = PROTOCOL.warmup,
        chains = PROTOCOL.chains,
        step_size = spec.step_size,
        target_accept = spec.target_accept,
        max_depth = spec.max_depth,
        max_energy_error = PROTOCOL.max_energy_error,
        metric = PROTOCOL.metric,
        ad_backend = PROTOCOL.ad_backend,
        init_jitter = spec.init_jitter,
        split_chains = PROTOCOL.split_chains,
        rhat_threshold = PROTOCOL.thresholds.max_rhat,
        ess_threshold = PROTOCOL.thresholds.min_ess,
        progress = false,
    )
    passed = protocol_passed(diagnostics.summary)
    return (;
        scenario = spec.scenario,
        seed = spec.seed,
        controls = (;
            step_size = spec.step_size,
            target_accept = spec.target_accept,
            max_depth = spec.max_depth,
            init_jitter = spec.init_jitter,
        ),
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
        sampler_rows =
            [GMFRMCandidateChain.sampler_row_record(row) for row in diagnostics.sampler_rows],
        raw_block_rows =
            [GMFRMCandidateChain.block_row_record(row) for row in diagnostics.block_rows],
        direct_block_rows =
            [GMFRMCandidateChain.block_row_record(row) for row in diagnostics.direct_block_rows],
        direct_constraint_rows =
            [GMFRMCandidateChain.constraint_row_record(row)
                for row in diagnostics.direct_constraint_rows],
        pointwise = GMFRMCandidateChain.pointwise_summary(diagnostics),
    )
end

function project_version()
    project = TOML.parsefile(joinpath(ROOT, "Project.toml"))
    return String(project["version"])
end

function study_artifact()
    spec = GMFRMCandidateChain.scalar_gmfrm_spec()
    design = BayesianMGMFRM.getdesign(spec; preview = true)
    target = BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(design)
    records = [scenario_record(target, fixture) for fixture in GRID_SPECS]
    summaries = [record.summary for record in records]
    return (;
        schema = "bayesianmgmfrm.gmfrm_stress_chain_grid.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :internal_promotion_candidate,
        public_fit = false,
        fit_ready = false,
        target = :_gmfrm_promotion_candidate_logdensity,
        density_space = :raw_unconstrained,
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
        raw_parameter_order_sha256 =
            GMFRMCandidateChain.parameter_order_hash(target.blueprint.parameter_names),
        direct_parameter_order = target.blueprint.constrained_parameter_names,
        direct_parameter_order_sha256 =
            GMFRMCandidateChain.parameter_order_hash(target.blueprint.constrained_parameter_names),
        scenarios = records,
        summary = (;
            n_scenarios = length(records),
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
        " scenarios=", artifact.summary.n_scenarios,
        " max_rhat=", artifact.summary.max_rhat,
        " min_ess=", artifact.summary.min_ess,
        " min_ebfmi=", artifact.summary.min_ebfmi)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
