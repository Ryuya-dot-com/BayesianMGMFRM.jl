#!/usr/bin/env julia

using Dates
using SHA
using Statistics
using TOML

module SmallMCMC
include(joinpath(@__DIR__, "generate_mgmfrm_uto_style_small_mcmc_refit.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_calibration_bridge",
        "uto_style_calibration_bridge.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_calibration_bridge",
        "uto_style_calibration_bridge.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_calibration_bridge.v1"
const DEFAULT_THRESHOLDS = [0.0, 2.0, 4.0, 8.0]

const SCENARIO_LIBRARY = [
    (;
        name = :strong_source_aligned,
        role = :uto_direction_reproduction_anchor,
        seed_offset = 0,
        ability_scale = 1.25,
        item_discrimination_scale = 1.15,
        rater_severity_scale = 0.55,
        rater_consistency_spread = 0.35,
        item_step = -0.55,
        expected_boundary = :true_q_should_clear_low_and_moderate_thresholds,
    ),
    (;
        name = :moderate_transition,
        role = :margin_transition_probe,
        seed_offset = 1009,
        ability_scale = 0.75,
        item_discrimination_scale = 0.85,
        rater_severity_scale = 0.35,
        rater_consistency_spread = 0.18,
        item_step = -0.15,
        expected_boundary = :threshold_sensitivity_expected,
    ),
    (;
        name = :weak_compressed_category,
        role = :null_win_mechanism_probe,
        seed_offset = 2027,
        ability_scale = 0.35,
        item_discrimination_scale = 0.55,
        rater_severity_scale = 0.20,
        rater_consistency_spread = 0.08,
        item_step = 0.35,
        expected_boundary = :null_or_empirical_reference_can_compete,
    ),
]

function usage()
    return """
    Generate a local Uto-style MGMFRM calibration bridge.

    The bridge varies signal strength and category-step calibration across
    source-aligned known-truth scenarios, then refits the guarded fixed-Q
    MGMFRM with the existing small MCMC path. It records oracle-vs-MCMC loss
    and a multiple-threshold dELPD profile. This is local diagnostic evidence,
    not a public fit-threshold, model-weight, or Q-revision claim.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_calibration_bridge.jl [options]

    Options:
      --output-json PATH       JSON artifact path.
      --output-md PATH         Markdown report path.
      --scenarios LIST         Comma-separated scenarios. Default: all.
                               Choices: strong_source_aligned,
                               moderate_transition, weak_compressed_category.
      --thresholds LIST        Comma-separated dELPD thresholds. Default: 0,2,4,8.
      --n-persons N            Number of persons. Default: 8.
      --n-raters N             Number of raters. Default: 3.
      --heldout-fraction X     Observation holdout fraction. Default: 0.17.
      --chains N               MCMC chains. Default: 2.
      --warmup-per-chain N     Warmup iterations per chain. Default: 20.
      --draws-per-chain N      Posterior draws per chain. Default: 20.
      --target-acceptance X    NUTS target acceptance. Default: 0.8.
      --prior-profile NAME     Internal source prior profile: default, tight, or diffuse.
                               Default: default.
      --seed N                 Base random seed. Default: 20260707.
      --progress               Show sampler progress.
    """
end

function parse_symbol_list(text::AbstractString)
    values = Symbol[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        push!(values, Symbol(stripped))
    end
    isempty(values) && error("list must contain at least one value")
    length(unique(values)) == length(values) || error("list values must be unique")
    return values
end

function parse_thresholds(text::AbstractString)
    values = Float64[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        push!(values, parse(Float64, stripped))
    end
    isempty(values) && error("--thresholds must contain at least one value")
    all(value >= 0 for value in values) ||
        error("--thresholds must be non-negative")
    length(unique(values)) == length(values) ||
        error("--thresholds must be unique")
    return sort(values)
end

function scenario_by_name(name::Symbol)
    matches = [scenario for scenario in SCENARIO_LIBRARY
        if scenario.name === name]
    isempty(matches) && error("unknown scenario: $name")
    return only(matches)
end

function parse_args(args)
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    scenario_names = [scenario.name for scenario in SCENARIO_LIBRARY]
    thresholds = copy(DEFAULT_THRESHOLDS)
    n_persons = 8
    n_raters = 3
    heldout_fraction = 0.17
    chains = 2
    warmup_per_chain = 20
    draws_per_chain = 20
    target_acceptance = 0.8
    prior_profile = :default
    seed = 20260707
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
        elseif arg == "--scenarios"
            index < length(args) || error("--scenarios requires a comma list")
            scenario_names = parse_symbol_list(args[index + 1])
            index += 2
        elseif arg == "--thresholds"
            index < length(args) || error("--thresholds requires a comma list")
            thresholds = parse_thresholds(args[index + 1])
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
        elseif arg == "--prior-profile"
            index < length(args) || error("--prior-profile requires a name")
            prior_profile = Symbol(args[index + 1])
            index += 2
        elseif arg == "--seed"
            index < length(args) || error("--seed requires an integer")
            seed = parse(Int, args[index + 1])
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
    prior_profile in (:default, :tight, :diffuse) ||
        error("--prior-profile must be default, tight, or diffuse")
    scenarios = [scenario_by_name(name) for name in scenario_names]
    return (;
        output_json,
        output_md,
        scenarios,
        thresholds,
        n_persons,
        n_items = size(SmallMCMC.Q_TRUE, 1),
        n_raters,
        heldout_fraction,
        chains,
        warmup_per_chain,
        draws_per_chain,
        target_acceptance,
        prior_profile,
        seed,
        progress,
    )
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
round3(value) = round(Float64(value); digits = 3)
round4(value) = round(Float64(value); digits = 4)

function fit_options(options, scenario)
    return (;
        output_json = "",
        output_md = "",
        n_persons = options.n_persons,
        n_items = options.n_items,
        n_raters = options.n_raters,
        heldout_fraction = options.heldout_fraction,
        chains = options.chains,
        warmup_per_chain = options.warmup_per_chain,
        draws_per_chain = options.draws_per_chain,
        target_acceptance = options.target_acceptance,
        prior_profile = options.prior_profile,
        seed = options.seed + scenario.seed_offset,
        progress = options.progress,
    )
end

function generation_options(options, scenario)
    return merge(fit_options(options, scenario), (;
        ability_scale = scenario.ability_scale,
        item_discrimination_scale = scenario.item_discrimination_scale,
        rater_severity_scale = scenario.rater_severity_scale,
        rater_consistency_spread = scenario.rater_consistency_spread,
        item_step = scenario.item_step,
    ))
end

function row_by_model(rows, model::Symbol)
    matches = [row for row in rows if row.model === model]
    isempty(matches) && return nothing
    return only(matches)
end

function comparison_value(rows, comparison::Symbol, field::Symbol)
    matches = [row for row in rows if row.comparison === comparison]
    isempty(matches) && return NaN
    return Float64(getproperty(only(matches), field))
end

function model_delta(rows, lhs::Symbol, rhs::Symbol)
    lhs_row = row_by_model(rows, lhs)
    rhs_row = row_by_model(rows, rhs)
    lhs_row === nothing && return NaN
    rhs_row === nothing && return NaN
    isfinite(Float64(lhs_row.heldout_elpd)) || return NaN
    isfinite(Float64(rhs_row.heldout_elpd)) || return NaN
    return Float64(lhs_row.heldout_elpd) - Float64(rhs_row.heldout_elpd)
end

function category_rows(scenario, rows)
    n = length(rows)
    return [(;
        scenario = scenario.name,
        score,
        count = count(row -> row.score == score, rows),
        share = round4(count(row -> row.score == score, rows) / n),
        public_claim_allowed = false,
    ) for score in SmallMCMC.CATEGORY_LEVELS]
end

function flatten_model_rows(scenario, rows)
    return [merge(row, (scenario = scenario.name,))
        for row in rows]
end

function flatten_comparison_rows(scenario, rows)
    return [merge(row, (scenario = scenario.name,))
        for row in rows]
end

function scenario_result(options, scenario)
    fit = fit_options(options, scenario)
    generation = generation_options(options, scenario)
    generated = SmallMCMC.generate_source_rows(generation)
    split = SmallMCMC.split_rows(generated.rows, generation)
    scored = SmallMCMC.score_all_models(generated.rows, split.train_rows,
        split.heldout_indices, generated.truth, fit)
    model_rows = SmallMCMC.ranked_rows(scored.fit_rows)
    comparisons = SmallMCMC.comparison_rows(model_rows)
    true_q = row_by_model(model_rows, :true_q_mgmfrm_mcmc)
    null = row_by_model(model_rows, :null_or_intercept_reference)
    leader = first(sort([row for row in model_rows
        if isfinite(Float64(row.heldout_elpd))];
        by = row -> Float64(row.heldout_elpd), rev = true))
    true_delta = comparison_value(comparisons,
        :true_q_mgmfrm_mcmc_minus_null, :delta_elpd)
    oracle_delta = comparison_value(comparisons,
        :true_q_source_oracle_minus_null, :delta_elpd)
    mcmc_loss = comparison_value(comparisons,
        :true_q_mgmfrm_mcmc_minus_true_q_source_oracle, :delta_elpd)
    return (;
        scenario,
        generated_rows = generated.rows,
        train_rows = split.train_rows,
        heldout_indices = split.heldout_indices,
        model_rows,
        comparison_rows = comparisons,
        scenario_row = (;
            scenario = scenario.name,
            role = scenario.role,
            expected_boundary = scenario.expected_boundary,
            seed = fit.seed,
            n_train_observations = length(split.train_rows),
            n_heldout_observations = length(split.heldout_indices),
            ability_scale = scenario.ability_scale,
            item_discrimination_scale = scenario.item_discrimination_scale,
            rater_severity_scale = scenario.rater_severity_scale,
            rater_consistency_spread = scenario.rater_consistency_spread,
            item_step = scenario.item_step,
            observed_best_model = leader.model,
            true_q_direction_recovered =
                true_q !== nothing && null !== nothing &&
                isfinite(Float64(true_q.heldout_elpd)) &&
                true_q.heldout_elpd > null.heldout_elpd,
            oracle_delta_elpd_vs_null = round3(oracle_delta),
            true_q_mcmc_delta_elpd_vs_null = round3(true_delta),
            true_q_mcmc_delta_elpd_vs_oracle = round3(mcmc_loss),
            wrong_q_delta_elpd_vs_null = round3(comparison_value(comparisons,
                :wrong_q_mgmfrm_mcmc_minus_null, :delta_elpd)),
            scalar_delta_elpd_vs_null = round3(comparison_value(comparisons,
                :scalar_gmfrm_mcmc_minus_null, :delta_elpd)),
            true_q_minus_wrong_q_elpd = round3(model_delta(model_rows,
                :true_q_mgmfrm_mcmc, :wrong_q_mgmfrm_mcmc)),
            true_q_minus_scalar_elpd = round3(model_delta(model_rows,
                :true_q_mgmfrm_mcmc, :scalar_gmfrm_mcmc)),
            oracle_to_mcmc_loss_abs = round3(oracle_delta - true_delta),
            oracle_positive_mcmc_nonpositive =
                isfinite(oracle_delta) && isfinite(true_delta) &&
                oracle_delta > 0 && true_delta <= 0,
            sampler_flag = true_q === nothing ? :missing : true_q.sampler_flag,
            public_claim_allowed = false,
        ),
        category_rows = category_rows(scenario, generated.rows),
        model_score_rows = flatten_model_rows(scenario, model_rows),
        flattened_comparison_rows = flatten_comparison_rows(scenario, comparisons),
    )
end

function threshold_rows(scenario_rows, thresholds)
    rows = NamedTuple[]
    for row in scenario_rows, threshold in thresholds
        oracle_pass = row.oracle_delta_elpd_vs_null >= threshold
        mcmc_pass = row.true_q_mcmc_delta_elpd_vs_null >= threshold
        push!(rows, (;
            scenario = row.scenario,
            threshold = round3(threshold),
            metric = :delta_elpd_vs_null,
            oracle_true_q_passed = oracle_pass,
            mcmc_true_q_passed = mcmc_pass,
            scalar_passed = row.scalar_delta_elpd_vs_null >= threshold,
            wrong_q_passed = row.wrong_q_delta_elpd_vs_null >= threshold,
            decision_profile =
                oracle_pass && mcmc_pass ? :oracle_and_mcmc_clear :
                oracle_pass && !mcmc_pass ? :oracle_only :
                !oracle_pass && mcmc_pass ? :mcmc_only :
                :neither_clear,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function finding_rows(scenario_rows, threshold_rows)
    strong = [row for row in scenario_rows
        if row.scenario === :strong_source_aligned]
    weak = [row for row in scenario_rows
        if row.scenario === :weak_compressed_category]
    oracle_only = [row for row in threshold_rows
        if row.decision_profile === :oracle_only]
    threshold_sensitive = [row for row in scenario_rows
        if row.true_q_mcmc_delta_elpd_vs_null > 0 &&
           row.true_q_mcmc_delta_elpd_vs_null < 8]
    return [
        (finding = :strong_signal_anchor_checked,
            severity = !isempty(strong) &&
                only(strong).true_q_direction_recovered ? :info : :warning,
            evidence = isempty(strong) ? "not run" :
                string("true-Q MCMC dELPD vs Null = ",
                    only(strong).true_q_mcmc_delta_elpd_vs_null,
                    "; oracle dELPD vs Null = ",
                    only(strong).oracle_delta_elpd_vs_null),
            implication =
                :tests_whether_uto_style_direction_survives_refit_at_anchor),
        (finding = :weak_or_compressed_boundary_checked,
            severity = isempty(weak) ? :warning :
                only(weak).true_q_direction_recovered ? :warning : :info,
            evidence = isempty(weak) ? "not run" :
                string("best = ", only(weak).observed_best_model,
                    "; true-Q MCMC dELPD vs Null = ",
                    only(weak).true_q_mcmc_delta_elpd_vs_null),
            implication =
                :tests_how_category_calibration_and_weak_signal_can_let_null_compete),
        (finding = :multiple_threshold_profile_recorded,
            severity = isempty(threshold_sensitive) ? :info : :warning,
            evidence = string(length(threshold_sensitive),
                " scenario(s) have positive but small true-Q margins"),
            implication =
                :do_not_promote_a_single_unchecked_fit_threshold),
        (finding = :oracle_mcmc_gap_profile_recorded,
            severity = isempty(oracle_only) ? :info : :warning,
            evidence = string(length(oracle_only),
                " threshold cell(s) clear at oracle but not MCMC"),
            implication =
                :separate_data_generating_signal_from_estimation_loss),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local calibration bridge only",
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
        println(io, "# Uto-Style MGMFRM Calibration Bridge")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report bridges the Uto-style source-aligned strong-signal ",
            "condition and compact Null-win conditions. It varies signal ",
            "strength and category-step calibration, then compares known-truth ",
            "oracle margins, small-MCMC recovery, and multiple dELPD thresholds.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Scenario Summary")
        table(io, ["Scenario", "Best", "Recovered", "Oracle dELPD",
                "MCMC dELPD", "MCMC vs Oracle", "True-Q - Wrong-Q",
                "True-Q - Scalar", "Step", "Flag"],
            [[row.scenario, row.observed_best_model,
                row.true_q_direction_recovered,
                row.oracle_delta_elpd_vs_null,
                row.true_q_mcmc_delta_elpd_vs_null,
                row.true_q_mcmc_delta_elpd_vs_oracle,
                row.true_q_minus_wrong_q_elpd,
                row.true_q_minus_scalar_elpd,
                row.item_step,
                row.sampler_flag]
             for row in artifact.scenario_rows])
        println(io, "## Threshold Profile")
        table(io, ["Scenario", "Threshold", "Oracle", "MCMC",
                "Scalar", "Wrong-Q", "Profile"],
            [[row.scenario, row.threshold, row.oracle_true_q_passed,
                row.mcmc_true_q_passed, row.scalar_passed,
                row.wrong_q_passed, row.decision_profile]
             for row in artifact.threshold_rows])
        println(io, "## Category Distribution")
        table(io, ["Scenario", "Score", "Count", "Share"],
            [[row.scenario, row.score, row.count, row.share]
             for row in artifact.category_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "The thresholds above are a sensitivity profile, not recommended ",
            "cutoffs. The bridge is meant to show where the conclusion depends ",
            "on signal strength, category calibration, and posterior recovery ",
            "loss before any public fit-index threshold is proposed.")
    end
    return path
end

function build_artifact(options)
    results = [scenario_result(options, scenario)
        for scenario in options.scenarios]
    scenario_rows = [result.scenario_row for result in results]
    thresholds = threshold_rows(scenario_rows, options.thresholds)
    categories = vcat([result.category_rows for result in results]...)
    model_rows = vcat([result.model_score_rows for result in results]...)
    comparisons =
        vcat([result.flattened_comparison_rows for result in results]...)
    findings = finding_rows(scenario_rows, thresholds)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_calibration_bridge,
        status = :local_calibration_bridge_recorded,
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
            scenarios = [scenario.name for scenario in options.scenarios],
            thresholds = options.thresholds,
            n_persons = options.n_persons,
            n_items = options.n_items,
            n_raters = options.n_raters,
            heldout_fraction = options.heldout_fraction,
            q_true = SmallMCMC.q_rows(SmallMCMC.Q_TRUE),
            q_wrong = SmallMCMC.q_rows(SmallMCMC.Q_WRONG),
            category_levels = SmallMCMC.CATEGORY_LEVELS,
        ),
        fit_controls = (;
            backend = :advancedhmc,
            sampler = :nuts,
            chains = options.chains,
            warmup_per_chain = options.warmup_per_chain,
            draws_per_chain = options.draws_per_chain,
            target_acceptance = options.target_acceptance,
            prior_profile = options.prior_profile,
            seed = options.seed,
            progress = options.progress,
        ),
        scenario_rows,
        threshold_rows = thresholds,
        category_rows = categories,
        model_score_rows = model_rows,
        comparison_rows = comparisons,
        finding_rows = findings,
        summary = (;
            passed = all(row.sampler_flag !== :fit_failed
                for row in scenario_rows),
            n_scenarios = length(scenario_rows),
            thresholds = options.thresholds,
            recovered_scenarios = count(row -> row.true_q_direction_recovered,
                scenario_rows),
            oracle_only_threshold_cells = count(row ->
                row.decision_profile === :oracle_only, thresholds),
            threshold_sensitive_scenarios = count(row ->
                row.true_q_mcmc_delta_elpd_vs_null > 0 &&
                row.true_q_mcmc_delta_elpd_vs_null < maximum(options.thresholds),
                scenario_rows),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate =
                :replicate_calibration_bridge_across_seeds_and_fit_profiles,
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
    println("recovered_scenarios=", artifact.summary.recovered_scenarios,
        "/", artifact.summary.n_scenarios,
        " oracle_only_threshold_cells=",
        artifact.summary.oracle_only_threshold_cells,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
