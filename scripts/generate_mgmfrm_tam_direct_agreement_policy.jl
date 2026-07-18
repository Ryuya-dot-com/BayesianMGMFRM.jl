#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_DIRECT_PILOT = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_direct_estimate_pilot.json")
const DEFAULT_OUTPUT = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_direct_agreement_policy.json")
const DIRECT_PILOT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_estimate_pilot.v1"

include(joinpath(@__DIR__, "local_json.jl"))

function usage()
    return """
    Freeze a prospective direct package-versus-TAM agreement policy.

    The existing direct same-data package/TAM comparison is treated as a
    descriptive pilot. Thresholds in this artifact apply only to future
    multi-replication package fits; they do not convert the pilot into a
    confirmatory validation result.

    Usage:
      julia --project=. scripts/generate_mgmfrm_tam_direct_agreement_policy.jl [--direct-pilot PATH] [--output PATH]
    """
end

function parse_args(args)
    direct_pilot = DEFAULT_DIRECT_PILOT
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--direct-pilot"
            index < length(args) || error("--direct-pilot requires a path")
            direct_pilot = abspath(args[index + 1])
            index += 2
        elseif arg == "--output"
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
    return (; direct_pilot, output)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])

function file_sha256(path::AbstractString)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

load_json(path::AbstractString) = JSON3.read(read(path, String))
as_string(value) = String(value)
as_float(value) = Float64(value)
as_int(value) = Int(value)
as_bool(value) = Bool(value)

function metric_passed(observed, direction::Symbol, threshold)
    direction === :minimum && return observed >= threshold
    direction === :maximum && return observed <= threshold
    direction === :equals && return observed == threshold
    error("unknown threshold direction: $direction")
end

function tam_comparison_by_block(pilot, block::Symbol)
    rows = [row for row in pilot[:direct_comparison_rows]
        if as_string(row[:block]) == String(block) &&
            occursin("tam_estimate", as_string(row[:interpretation]))]
    length(rows) == 1 || error("expected one TAM comparison row for $block")
    return only(rows)
end

function interval_by_block(pilot, block::Symbol)
    rows = [row for row in pilot[:block_interval_summary_rows]
        if as_string(row[:block]) == String(block)]
    length(rows) == 1 || error("expected one interval row for $block")
    return only(rows)
end

function direct_threshold_row(block::Symbol, metric::Symbol,
        direction::Symbol, threshold::Real, observed::Real)
    passed = metric_passed(Float64(observed), direction, Float64(threshold))
    return (;
        block,
        metric,
        target = metric === :tam_inside_package_interval95_rate ?
            :tam_estimate_inside_package_interval95 :
            :package_posterior_mean_vs_tam_estimate,
        direction,
        threshold = Float64(threshold),
        observed = Float64(observed),
        pilot_passed = passed,
        evaluation_role = :descriptive_pilot_calibration_only,
        future_role = :prospective_multireplication_gate,
    )
end

function direct_threshold_rows(pilot)
    rows = NamedTuple[]
    for block in (:item_difficulty, :rater_severity, :item_step)
        comparison = tam_comparison_by_block(pilot, block)
        interval = interval_by_block(pilot, block)
        append!(rows, [
            direct_threshold_row(block, :pearson_correlation,
                :minimum, 0.95, as_float(comparison[:pearson_correlation])),
            direct_threshold_row(block, :mean_abs_difference,
                :maximum, 0.10, as_float(comparison[:mean_abs_difference])),
            direct_threshold_row(block, :max_abs_difference,
                :maximum, 0.30, as_float(comparison[:max_abs_difference])),
            direct_threshold_row(block, :tam_inside_package_interval95_rate,
                :minimum, 0.80,
                as_float(interval[:tam_inside_package_interval95_rate])),
        ])
    end
    return rows
end

function sampler_threshold_row(metric::Symbol, direction::Symbol, threshold,
        observed)
    passed = metric_passed(observed, direction, threshold)
    return (;
        metric,
        direction,
        threshold,
        observed,
        pilot_passed = passed,
        evaluation_role = :descriptive_pilot_calibration_only,
        future_role = :prospective_fit_diagnostic_gate,
    )
end

function sampler_threshold_rows(pilot)
    sampler = pilot[:sampler_summary]
    return [
        sampler_threshold_row(:all_draws_and_logposterior_finite,
            :equals, true,
            as_bool(sampler[:all_draws_and_logposterior_finite])),
        sampler_threshold_row(:n_divergences,
            :maximum, 0, as_int(sampler[:n_divergences])),
        sampler_threshold_row(:n_max_treedepth,
            :maximum, 0, as_int(sampler[:n_max_treedepth])),
        sampler_threshold_row(:max_classical_split_rhat,
            :maximum, 1.01, as_float(sampler[:max_classical_split_rhat])),
        sampler_threshold_row(:min_autocorrelation_ess,
            :minimum, 400.0, as_float(sampler[:min_autocorrelation_ess])),
        sampler_threshold_row(:n_mcmc_warning_parameters,
            :maximum, 0, as_int(sampler[:n_mcmc_warning_parameters])),
    ]
end

function block_policy_rows(thresholds)
    return [(;
        block,
        n_thresholds = count(row -> row.block == block, thresholds),
        n_pilot_thresholds_passed =
            count(row -> row.block == block && row.pilot_passed, thresholds),
        all_pilot_thresholds_passed =
            all(row -> row.block != block || row.pilot_passed, thresholds),
        interpretation =
            :pilot_supports_policy_calibration_but_future_multireplication_required,
    ) for block in (:item_difficulty, :rater_severity, :item_step)]
end

function build_artifact(direct_pilot_path::AbstractString)
    isfile(direct_pilot_path) ||
        error("direct pilot fixture missing: $(relpath(direct_pilot_path, ROOT))")
    pilot = load_json(direct_pilot_path)
    as_string(pilot[:schema]) == DIRECT_PILOT_SCHEMA ||
        error("unexpected direct pilot schema")
    thresholds = direct_threshold_rows(pilot)
    sampler_thresholds = sampler_threshold_rows(pilot)
    direct_pilot_passed = all(row -> row.pilot_passed, thresholds)
    sampler_pilot_passed = all(row -> row.pilot_passed, sampler_thresholds)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy.v1",
        family = :mfrm,
        scope = :tam_direct_package_vs_tam_agreement_policy,
        status = :prospective_direct_agreement_policy_frozen,
        decision =
            :run_multireplication_package_vs_tam_fits_keep_claim_blocked,
        local_only = true,
        external_software = :tam,
        direct_agreement_thresholds_predeclared = true,
        future_direct_multireplication_execution_completed = false,
        external_software_validation_completed = false,
        public_claim_release_allowed = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = (;
            protocol_id = :mgmfrm_tam_direct_agreement_policy_v1,
            generator =
                "scripts/generate_mgmfrm_tam_direct_agreement_policy.jl",
            generator_source_sha256 = file_sha256(@__FILE__),
            direct_estimate_pilot =
                relpath(direct_pilot_path, ROOT),
            direct_estimate_pilot_sha256 = file_sha256(direct_pilot_path),
            threshold_freeze_order =
                :after_single_dataset_direct_pilot_before_direct_multireplication_execution,
            current_pilot_role = :retrospective_calibration_only,
            future_runs_role = :prospective_confirmatory_gate,
        ),
        relationship_to_tam = (;
            overlap_target = :many_facet_rasch_partial_credit,
            compared_estimand =
                :aligned_item_rater_and_item_step_parameter_summaries,
            package_estimator =
                :bayesian_fixed_person_advancedhmc_posterior_mean_and_interval,
            tam_estimator = :marginal_maximum_likelihood_xsi_estimate,
            exact_estimator_equality_expected = false,
            agreement_target =
                :numerical_parameter_alignment_under_shared_overlap_model,
        ),
        future_execution_plan = (;
            planned_artifact =
                "test/fixtures/mgmfrm_tam_direct_agreement_multireplication.json",
            person_counts = [40, 100],
            replications_per_person_count = 5,
            primary_person_count = 100,
            primary_block_pass_rate_threshold = 0.80,
            package_fit = :BayesianMGMFRM_AdvancedHMC_NUTS,
            chains = 4,
            ndraws_per_chain = 400,
            warmup_per_chain = 400,
            target_accept = 0.90,
            max_depth = 10,
            metric = :diagonal,
            ad_backend = :ForwardDiff,
            gate =
                :each_primary_block_all_direct_metrics_pass_rate_at_least_0_80_and_all_sampler_gates_pass,
        ),
        direct_threshold_rows = thresholds,
        sampler_threshold_rows = sampler_thresholds,
        block_policy_rows = block_policy_rows(thresholds),
        claim_limits = [
            :thresholds_frozen_after_single_direct_pilot_not_before_it,
            :current_pilot_is_calibration_only,
            :future_multireplication_package_vs_tam_fits_required,
            :package_and_tam_estimators_are_not_identical,
            :no_facets_or_conquest_execution,
            :no_generalized_gmfrm_or_mgmfrm_external_validation,
            :no_public_claim_release,
        ],
        summary = (;
            passed = length(thresholds) == 12 &&
                length(sampler_thresholds) == 6,
            direct_agreement_thresholds_predeclared = true,
            current_pilot_all_direct_thresholds_passed = direct_pilot_passed,
            current_pilot_all_sampler_thresholds_passed = sampler_pilot_passed,
            future_direct_multireplication_execution_completed = false,
            external_software_validation_completed = false,
            public_claim_release_allowed = false,
            n_direct_threshold_rows = length(thresholds),
            n_sampler_threshold_rows = length(sampler_thresholds),
            n_block_policy_rows = 3,
            next_gate =
                :run_predeclared_multireplication_package_vs_tam_direct_agreement,
        ),
    )
end

function main(args)
    parsed = parse_args(args)
    artifact = build_artifact(parsed.direct_pilot)
    write_artifact(parsed.output, artifact)
    println("wrote ", relpath(parsed.output, ROOT))
    println(
        "policy_pass=", artifact.summary.passed,
        " pilot_direct_pass=",
        artifact.summary.current_pilot_all_direct_thresholds_passed,
        " pilot_sampler_pass=",
        artifact.summary.current_pilot_all_sampler_thresholds_passed,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
