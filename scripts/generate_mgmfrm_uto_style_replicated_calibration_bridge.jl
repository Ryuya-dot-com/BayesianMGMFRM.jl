#!/usr/bin/env julia

using Dates
using SHA
using Statistics
using TOML

module Bridge
include(joinpath(@__DIR__, "generate_mgmfrm_uto_style_calibration_bridge.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_replicated_calibration_bridge",
        "uto_style_replicated_calibration_bridge.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_replicated_calibration_bridge",
        "uto_style_replicated_calibration_bridge.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_replicated_calibration_bridge.v1"
const DEFAULT_PROFILES = [:default, :tight, :diffuse]

function usage()
    return """
    Generate a replicated local Uto-style MGMFRM calibration bridge.

    This repeats the calibration bridge over seeds and internal source-prior
    profiles. It records threshold profiles and oracle-vs-MCMC gaps without
    promoting any public fit-threshold, model-weight, Q-revision, or
    sparse-superiority claim.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_replicated_calibration_bridge.jl [options]

    Options:
      --output-json PATH       JSON artifact path.
      --output-md PATH         Markdown report path.
      --seeds LIST             Comma-separated base seeds. Default: 20260707,20260717.
      --profiles LIST          Comma-separated profiles. Default: default,tight,diffuse.
      --scenarios LIST         Comma-separated scenarios. Default: all bridge scenarios.
      --thresholds LIST        Comma-separated dELPD thresholds. Default: 0,2,4,8.
      --n-persons N            Number of persons. Default: 8.
      --n-raters N             Number of raters. Default: 3.
      --heldout-fraction X     Observation holdout fraction. Default: 0.17.
      --chains N               MCMC chains. Default: 2.
      --warmup-per-chain N     Warmup iterations per chain. Default: 20.
      --draws-per-chain N      Posterior draws per chain. Default: 20.
      --target-acceptance X    NUTS target acceptance. Default: 0.8.
      --progress               Show sampler progress.
    """
end

function parse_seed_list(text::AbstractString)
    seeds = Int[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        push!(seeds, parse(Int, stripped))
    end
    isempty(seeds) && error("--seeds must contain at least one integer")
    length(unique(seeds)) == length(seeds) ||
        error("--seeds must be unique")
    return seeds
end

function parse_profile_list(text::AbstractString)
    profiles = Symbol[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        profile = Symbol(stripped)
        profile in DEFAULT_PROFILES ||
            error("profile must be one of default, tight, diffuse")
        push!(profiles, profile)
    end
    isempty(profiles) && error("--profiles must contain at least one profile")
    length(unique(profiles)) == length(profiles) ||
        error("--profiles must be unique")
    return profiles
end

function parse_args(args)
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    seeds = [20260707, 20260717]
    profiles = copy(DEFAULT_PROFILES)
    scenario_names = [scenario.name for scenario in Bridge.SCENARIO_LIBRARY]
    thresholds = copy(Bridge.DEFAULT_THRESHOLDS)
    n_persons = 8
    n_raters = 3
    heldout_fraction = 0.17
    chains = 2
    warmup_per_chain = 20
    draws_per_chain = 20
    target_acceptance = 0.8
    progress = false

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output-json"
            index < length(args) || error("--output-json requires a path")
            output_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-md"
            index < length(args) || error("--output-md requires a path")
            output_md = abspath(args[index + 1])
            index += 2
        elseif arg == "--seeds"
            index < length(args) || error("--seeds requires a comma list")
            seeds = parse_seed_list(args[index + 1])
            index += 2
        elseif arg == "--profiles"
            index < length(args) || error("--profiles requires a comma list")
            profiles = parse_profile_list(args[index + 1])
            index += 2
        elseif arg == "--scenarios"
            index < length(args) || error("--scenarios requires a comma list")
            scenario_names = Bridge.parse_symbol_list(args[index + 1])
            index += 2
        elseif arg == "--thresholds"
            index < length(args) || error("--thresholds requires a comma list")
            thresholds = Bridge.parse_thresholds(args[index + 1])
            index += 2
        elseif arg == "--n-persons"
            index < length(args) || error("--n-persons requires an integer")
            n_persons = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--n-raters"
            index < length(args) || error("--n-raters requires an integer")
            n_raters = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--heldout-fraction"
            index < length(args) ||
                error("--heldout-fraction requires a number")
            heldout_fraction = parse(Float64, args[index + 1])
            index += 2
        elseif arg == "--chains"
            index < length(args) || error("--chains requires an integer")
            chains = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--warmup-per-chain"
            index < length(args) ||
                error("--warmup-per-chain requires an integer")
            warmup_per_chain = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--draws-per-chain"
            index < length(args) ||
                error("--draws-per-chain requires an integer")
            draws_per_chain = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--target-acceptance"
            index < length(args) ||
                error("--target-acceptance requires a number")
            target_acceptance = parse(Float64, args[index + 1])
            index += 2
        elseif arg == "--progress"
            progress = true
            index += 1
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end

    n_persons >= 6 || error("--n-persons must be at least 6")
    n_raters >= 3 || error("--n-raters must be at least 3")
    0 < heldout_fraction < 0.5 ||
        error("--heldout-fraction must be in (0, 0.5)")
    chains >= 1 || error("--chains must be positive")
    warmup_per_chain >= 0 || error("--warmup-per-chain must be non-negative")
    draws_per_chain >= 1 || error("--draws-per-chain must be positive")
    0 < target_acceptance < 1 ||
        error("--target-acceptance must be in (0, 1)")
    scenarios = [Bridge.scenario_by_name(name) for name in scenario_names]
    return (;
        output_json,
        output_md,
        seeds,
        profiles,
        scenarios,
        thresholds,
        n_persons,
        n_items = size(Bridge.SmallMCMC.Q_TRUE, 1),
        n_raters,
        heldout_fraction,
        chains,
        warmup_per_chain,
        draws_per_chain,
        target_acceptance,
        progress,
    )
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
round3(value) = round(Float64(value); digits = 3)
round4(value) = round(Float64(value); digits = 4)

function bridge_options(options, seed::Int, profile::Symbol)
    return (;
        output_json = "",
        output_md = "",
        scenarios = options.scenarios,
        thresholds = options.thresholds,
        n_persons = options.n_persons,
        n_items = options.n_items,
        n_raters = options.n_raters,
        heldout_fraction = options.heldout_fraction,
        chains = options.chains,
        warmup_per_chain = options.warmup_per_chain,
        draws_per_chain = options.draws_per_chain,
        target_acceptance = options.target_acceptance,
        prior_profile = profile,
        seed,
        progress = options.progress,
    )
end

function finite_values(rows, field::Symbol)
    return [Float64(getproperty(row, field)) for row in rows
        if isfinite(Float64(getproperty(row, field)))]
end

function mean_round(rows, field::Symbol)
    values = finite_values(rows, field)
    isempty(values) && return NaN
    return round3(mean(values))
end

function min_round(rows, field::Symbol)
    values = finite_values(rows, field)
    isempty(values) && return NaN
    return round3(minimum(values))
end

function max_round(rows, field::Symbol)
    values = finite_values(rows, field)
    isempty(values) && return NaN
    return round3(maximum(values))
end

function with_cell(row, seed::Int, profile::Symbol)
    return merge(row, (;
        seed,
        prior_profile = profile,
        public_claim_allowed = false,
    ))
end

function cell_summary(seed::Int, profile::Symbol, artifact)
    return (;
        seed,
        prior_profile = profile,
        n_scenarios = artifact.summary.n_scenarios,
        recovered_scenarios = artifact.summary.recovered_scenarios,
        recovery_rate = round4(artifact.summary.recovered_scenarios /
                               artifact.summary.n_scenarios),
        oracle_only_threshold_cells =
            artifact.summary.oracle_only_threshold_cells,
        threshold_sensitive_scenarios =
            artifact.summary.threshold_sensitive_scenarios,
        passed = artifact.summary.passed,
        public_claim_allowed = false,
    )
end

function scenario_stability_rows(scenario_rows)
    output = NamedTuple[]
    for scenario in sort(unique(row.scenario for row in scenario_rows);
            by = string)
        group = [row for row in scenario_rows if row.scenario === scenario]
        n = length(group)
        push!(output, (;
            scenario,
            n_cells = n,
            direction_recovery_rate =
                round4(count(row -> row.true_q_direction_recovered, group) / n),
            oracle_positive_mcmc_nonpositive_rate =
                round4(count(row -> row.oracle_positive_mcmc_nonpositive,
                    group) / n),
            mean_oracle_delta_elpd_vs_null =
                mean_round(group, :oracle_delta_elpd_vs_null),
            mean_true_q_mcmc_delta_elpd_vs_null =
                mean_round(group, :true_q_mcmc_delta_elpd_vs_null),
            min_true_q_mcmc_delta_elpd_vs_null =
                min_round(group, :true_q_mcmc_delta_elpd_vs_null),
            max_true_q_mcmc_delta_elpd_vs_null =
                max_round(group, :true_q_mcmc_delta_elpd_vs_null),
            mean_oracle_to_mcmc_loss_abs =
                mean_round(group, :oracle_to_mcmc_loss_abs),
            min_true_q_minus_wrong_q_elpd =
                min_round(group, :true_q_minus_wrong_q_elpd),
            public_claim_allowed = false,
        ))
    end
    return output
end

function threshold_stability_rows(threshold_rows)
    output = NamedTuple[]
    keys = sort(unique((row.scenario, row.threshold)
        for row in threshold_rows); by = pair -> (string(pair[1]), pair[2]))
    for (scenario, threshold) in keys
        group = [row for row in threshold_rows
            if row.scenario === scenario && row.threshold == threshold]
        n = length(group)
        push!(output, (;
            scenario,
            threshold,
            n_cells = n,
            oracle_pass_rate =
                round4(count(row -> row.oracle_true_q_passed, group) / n),
            mcmc_pass_rate =
                round4(count(row -> row.mcmc_true_q_passed, group) / n),
            scalar_pass_rate =
                round4(count(row -> row.scalar_passed, group) / n),
            wrong_q_pass_rate =
                round4(count(row -> row.wrong_q_passed, group) / n),
            oracle_only_rate =
                round4(count(row -> row.decision_profile === :oracle_only,
                    group) / n),
            public_claim_allowed = false,
        ))
    end
    return output
end

function profile_stability_rows(scenario_rows)
    output = NamedTuple[]
    for profile in sort(unique(row.prior_profile for row in scenario_rows);
            by = string)
        group = [row for row in scenario_rows if row.prior_profile === profile]
        n = length(group)
        push!(output, (;
            prior_profile = profile,
            n_scenario_cells = n,
            direction_recovery_rate =
                round4(count(row -> row.true_q_direction_recovered, group) / n),
            mean_true_q_mcmc_delta_elpd_vs_null =
                mean_round(group, :true_q_mcmc_delta_elpd_vs_null),
            min_true_q_mcmc_delta_elpd_vs_null =
                min_round(group, :true_q_mcmc_delta_elpd_vs_null),
            mean_oracle_to_mcmc_loss_abs =
                mean_round(group, :oracle_to_mcmc_loss_abs),
            public_claim_allowed = false,
        ))
    end
    return output
end

function row_for_scenario(rows, scenario::Symbol)
    matches = [row for row in rows if row.scenario === scenario]
    isempty(matches) && return nothing
    return only(matches)
end

function threshold_row(rows, scenario::Symbol, threshold::Real)
    matches = [row for row in rows
        if row.scenario === scenario && row.threshold == threshold]
    isempty(matches) && return nothing
    return only(matches)
end

function finding_rows(scenario_stability, threshold_stability, profile_stability)
    strong = row_for_scenario(scenario_stability, :strong_source_aligned)
    moderate = row_for_scenario(scenario_stability, :moderate_transition)
    weak = row_for_scenario(scenario_stability, :weak_compressed_category)
    weak_t4 = threshold_row(threshold_stability, :weak_compressed_category, 4.0)
    profile_min = isempty(profile_stability) ? NaN :
        minimum(Float64(row.direction_recovery_rate) for row in profile_stability)
    return [
        (finding = :strong_signal_recovery_profile,
            severity = strong !== nothing &&
                strong.direction_recovery_rate == 1.0 ? :info : :warning,
            evidence = strong === nothing ? "not run" :
                string("recovery rate = ", strong.direction_recovery_rate,
                    "; min true-Q MCMC dELPD vs Null = ",
                    strong.min_true_q_mcmc_delta_elpd_vs_null),
            implication =
                :checks_whether_the_uto_style_anchor_survives_seed_and_prior_profiles),
        (finding = :transition_boundary_profile,
            severity = moderate === nothing ? :warning : :info,
            evidence = moderate === nothing ? "not run" :
                string("recovery rate = ", moderate.direction_recovery_rate,
                    "; oracle-positive/MCMC-nonpositive rate = ",
                    moderate.oracle_positive_mcmc_nonpositive_rate),
            implication =
                :identifies_where_positive_oracle_margins_can_fail_after_refit),
        (finding = :compressed_category_threshold_profile,
            severity = weak_t4 !== nothing &&
                weak_t4.mcmc_pass_rate < 1.0 ? :warning : :info,
            evidence = weak === nothing ? "not run" :
                string("weak recovery rate = ",
                    weak.direction_recovery_rate,
                    "; threshold 4 MCMC pass rate = ",
                    weak_t4 === nothing ? "not run" : weak_t4.mcmc_pass_rate),
            implication =
                :records_how_higher_thresholds_change_the_conclusion),
        (finding = :prior_profile_stability_profile,
            severity = isfinite(profile_min) && profile_min == 1.0 ?
                :info : :warning,
            evidence = string("minimum profile recovery rate = ", profile_min),
            implication =
                :internal_prior_profiles_remain_diagnostic_not_public_api),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "replicated local calibration bridge only",
            implication =
                :do_not_claim_public_fit_thresholds_model_weights_or_q_revisions),
    ]
end

function table(io, headers, rows)
    println(io, "| ", join(headers, " | "), " |")
    println(io, "| ", join(fill("---", length(headers)), " | "), " |")
    for row in rows
        println(io, "| ", join(string.(row), " | "), " |")
    end
    println(io)
end

function render_markdown(path, artifact)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# Uto-Style Replicated Calibration Bridge")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report repeats the calibration bridge across seeds and ",
            "internal source-prior profiles. It keeps the fit-threshold result ",
            "as a profile: thresholds are diagnostic cut points, not recommended ",
            "package defaults.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Scenario Stability")
        table(io, ["Scenario", "Cells", "Recovery", "Oracle+/MCMC-",
                "Mean Oracle dELPD", "Mean MCMC dELPD", "Min MCMC dELPD",
                "Mean Oracle-MCMC Loss", "Min True-Wrong"],
            [[row.scenario, row.n_cells, row.direction_recovery_rate,
                row.oracle_positive_mcmc_nonpositive_rate,
                row.mean_oracle_delta_elpd_vs_null,
                row.mean_true_q_mcmc_delta_elpd_vs_null,
                row.min_true_q_mcmc_delta_elpd_vs_null,
                row.mean_oracle_to_mcmc_loss_abs,
                row.min_true_q_minus_wrong_q_elpd]
             for row in artifact.scenario_stability_rows])
        println(io, "## Threshold Stability")
        table(io, ["Scenario", "Threshold", "Cells", "Oracle Pass",
                "MCMC Pass", "Scalar Pass", "Wrong-Q Pass", "Oracle Only"],
            [[row.scenario, row.threshold, row.n_cells,
                row.oracle_pass_rate, row.mcmc_pass_rate,
                row.scalar_pass_rate, row.wrong_q_pass_rate,
                row.oracle_only_rate]
             for row in artifact.threshold_stability_rows])
        println(io, "## Prior Profile Stability")
        table(io, ["Profile", "Cells", "Recovery", "Mean MCMC dELPD",
                "Min MCMC dELPD", "Mean Oracle-MCMC Loss"],
            [[row.prior_profile, row.n_scenario_cells,
                row.direction_recovery_rate,
                row.mean_true_q_mcmc_delta_elpd_vs_null,
                row.min_true_q_mcmc_delta_elpd_vs_null,
                row.mean_oracle_to_mcmc_loss_abs]
             for row in artifact.profile_stability_rows])
        println(io, "## Cell Summary")
        table(io, ["Seed", "Profile", "Recovered", "Scenarios",
                "Recovery", "Oracle-only Cells", "Threshold-sensitive",
                "Passed"],
            [[row.seed, row.prior_profile, row.recovered_scenarios,
                row.n_scenarios, row.recovery_rate,
                row.oracle_only_threshold_cells,
                row.threshold_sensitive_scenarios,
                row.passed]
             for row in artifact.cell_summary_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This is a local replicated diagnostic. It can justify which ",
            "failure modes should be studied next, but it does not justify a ",
            "public fit cutoff, model-weight statement, Q-matrix revision, or ",
            "sparse-MGMFRM superiority claim.")
    end
    return path
end

function build_artifact(options)
    artifacts = []
    cell_rows = NamedTuple[]
    scenario_rows = NamedTuple[]
    threshold_rows = NamedTuple[]
    category_rows = NamedTuple[]
    model_rows = NamedTuple[]
    comparison_rows = NamedTuple[]

    for seed in options.seeds, profile in options.profiles
        bridge = Bridge.build_artifact(bridge_options(options, seed, profile))
        push!(artifacts, bridge)
        push!(cell_rows, cell_summary(seed, profile, bridge))
        append!(scenario_rows, [with_cell(row, seed, profile)
            for row in bridge.scenario_rows])
        append!(threshold_rows, [with_cell(row, seed, profile)
            for row in bridge.threshold_rows])
        append!(category_rows, [with_cell(row, seed, profile)
            for row in bridge.category_rows])
        append!(model_rows, [with_cell(row, seed, profile)
            for row in bridge.model_score_rows])
        append!(comparison_rows, [with_cell(row, seed, profile)
            for row in bridge.comparison_rows])
    end

    scenario_stability = scenario_stability_rows(scenario_rows)
    threshold_stability = threshold_stability_rows(threshold_rows)
    profile_stability = profile_stability_rows(scenario_rows)
    findings = finding_rows(scenario_stability, threshold_stability,
        profile_stability)

    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_replicated_calibration_bridge,
        status = :local_replicated_calibration_bridge_recorded,
        generated_at = string(now(UTC)),
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        local_only = true,
        publication_or_registration_action = false,
        public_fit_metric_claim = false,
        public_q_revision_claim = false,
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        design = (;
            seeds = options.seeds,
            profiles = options.profiles,
            scenarios = [scenario.name for scenario in options.scenarios],
            thresholds = options.thresholds,
            n_persons = options.n_persons,
            n_items = options.n_items,
            n_raters = options.n_raters,
            heldout_fraction = options.heldout_fraction,
            q_true = Bridge.SmallMCMC.q_rows(Bridge.SmallMCMC.Q_TRUE),
            q_wrong = Bridge.SmallMCMC.q_rows(Bridge.SmallMCMC.Q_WRONG),
        ),
        fit_controls = (;
            backend = :advancedhmc,
            sampler = :nuts,
            chains = options.chains,
            warmup_per_chain = options.warmup_per_chain,
            draws_per_chain = options.draws_per_chain,
            target_acceptance = options.target_acceptance,
            progress = options.progress,
        ),
        cell_summary_rows = cell_rows,
        scenario_rows,
        threshold_rows,
        category_rows,
        model_score_rows = model_rows,
        comparison_rows,
        scenario_stability_rows = scenario_stability,
        threshold_stability_rows = threshold_stability,
        profile_stability_rows = profile_stability,
        finding_rows = findings,
        summary = (;
            passed = all(row.passed for row in cell_rows),
            n_cells = length(cell_rows),
            n_scenario_cells = length(scenario_rows),
            n_threshold_cells = length(threshold_rows),
            mean_cell_recovery_rate =
                mean_round(cell_rows, :recovery_rate),
            total_oracle_only_threshold_cells =
                sum(row.oracle_only_threshold_cells for row in cell_rows),
            total_threshold_sensitive_scenarios =
                sum(row.threshold_sensitive_scenarios for row in cell_rows),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate =
                :larger_mcmc_budget_or_category_calibration_metric_design,
        ),
    )
end

function main(args = ARGS)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output_json, artifact)
    render_markdown(options.output_md, artifact)
    println("wrote ", rel(options.output_json))
    println("wrote ", rel(options.output_md))
    println("cells=", artifact.summary.n_cells,
        " scenario_cells=", artifact.summary.n_scenario_cells,
        " mean_cell_recovery_rate=",
        artifact.summary.mean_cell_recovery_rate,
        " oracle_only_threshold_cells=",
        artifact.summary.total_oracle_only_threshold_cells,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
