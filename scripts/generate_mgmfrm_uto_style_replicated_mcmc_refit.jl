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
    joinpath(ROOT, "artifacts", "uto_style_replicated_mcmc_refit",
        "uto_style_replicated_mcmc_refit.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_replicated_mcmc_refit",
        "uto_style_replicated_mcmc_refit.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_replicated_mcmc_refit.v1"

function usage()
    return """
    Run replicated local Uto-style small MCMC refits across seeds.

    This is a local stability diagnostic. It reuses the source-aligned
    small-MCMC condition and summarizes whether true-Q MGMFRM keeps beating
    the Null reference across generated datasets/splits. Public model-weight,
    fit-threshold, Q-revision, and sparse-superiority claims remain blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_replicated_mcmc_refit.jl [options]

    Options:
      --output-json PATH       JSON artifact path.
      --output-md PATH         Markdown report path.
      --seeds LIST             Comma-separated base seeds. Default: 20260707,20260717,20260727.
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

function parse_args(args)
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    seeds = [20260707, 20260717, 20260727]
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
    return (;
        output_json,
        output_md,
        seeds,
        n_persons,
        n_items = size(SmallMCMC.Q_TRUE, 1),
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

function small_options(options, seed::Int)
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
        prior_profile = :default,
        seed,
        progress = options.progress,
    )
end

function comparison_value(artifact, comparison::Symbol, field::Symbol)
    matches = [row for row in artifact.comparison_rows
        if row.comparison === comparison]
    isempty(matches) && return NaN
    return Float64(getproperty(only(matches), field))
end

function model_row(artifact, model::Symbol)
    matches = [row for row in artifact.model_score_rows
        if row.model === model]
    isempty(matches) && return nothing
    return only(matches)
end

function replicate_row(seed::Int, artifact)
    true_row = model_row(artifact, :true_q_mgmfrm_mcmc)
    wrong_row = model_row(artifact, :wrong_q_mgmfrm_mcmc)
    scalar_row = model_row(artifact, :scalar_gmfrm_mcmc)
    return (;
        seed,
        observed_best_model = artifact.summary.observed_best_model,
        true_q_direction_recovered =
            artifact.summary.true_q_mcmc_direction_recovered,
        true_q_delta_elpd_vs_null =
            round3(comparison_value(artifact,
                :true_q_mgmfrm_mcmc_minus_null, :delta_elpd)),
        true_q_delta_mae_vs_null =
            round3(comparison_value(artifact,
                :true_q_mgmfrm_mcmc_minus_null, :delta_mae)),
        true_q_delta_elpd_vs_oracle =
            round3(comparison_value(artifact,
                :true_q_mgmfrm_mcmc_minus_true_q_source_oracle,
                :delta_elpd)),
        oracle_delta_elpd_vs_null =
            round3(comparison_value(artifact,
                :true_q_source_oracle_minus_null, :delta_elpd)),
        true_q_minus_wrong_q_elpd =
            wrong_row === nothing || true_row === nothing ? NaN :
            round3(true_row.heldout_elpd - wrong_row.heldout_elpd),
        true_q_minus_scalar_elpd =
            scalar_row === nothing || true_row === nothing ? NaN :
            round3(true_row.heldout_elpd - scalar_row.heldout_elpd),
        true_q_sampler_flag =
            true_row === nothing ? :missing : true_row.sampler_flag,
        wrong_q_sampler_flag =
            wrong_row === nothing ? :missing : wrong_row.sampler_flag,
        scalar_sampler_flag =
            scalar_row === nothing ? :missing : scalar_row.sampler_flag,
        all_mcmc_fits_succeeded =
            all(row.fit_succeeded for row in artifact.model_score_rows
                if row.model in SmallMCMC.MCMC_MODELS),
        public_claim_allowed = false,
    )
end

function mean_round(rows, field::Symbol)
    values = [Float64(getproperty(row, field)) for row in rows
        if isfinite(Float64(getproperty(row, field)))]
    isempty(values) && return NaN
    return round3(mean(values))
end

function min_round(rows, field::Symbol)
    values = [Float64(getproperty(row, field)) for row in rows
        if isfinite(Float64(getproperty(row, field)))]
    isempty(values) && return NaN
    return round3(minimum(values))
end

function max_round(rows, field::Symbol)
    values = [Float64(getproperty(row, field)) for row in rows
        if isfinite(Float64(getproperty(row, field)))]
    isempty(values) && return NaN
    return round3(maximum(values))
end

function stability_rows(replicates)
    n = length(replicates)
    return [
        (metric = :true_q_direction_recovery_rate,
            value = round4(count(row -> row.true_q_direction_recovered,
                replicates) / n),
            threshold = 1.0,
            passed = all(row -> row.true_q_direction_recovered, replicates),
            interpretation =
                :share_of_replicates_where_true_q_mcmc_beats_null),
        (metric = :mcmc_fit_success_rate,
            value = round4(count(row -> row.all_mcmc_fits_succeeded,
                replicates) / n),
            threshold = 1.0,
            passed = all(row -> row.all_mcmc_fits_succeeded, replicates),
            interpretation = :all_mcmc_candidates_returned_finite_scores),
        (metric = :mean_true_q_delta_elpd_vs_null,
            value = mean_round(replicates, :true_q_delta_elpd_vs_null),
            threshold = 0.0,
            passed = mean_round(replicates, :true_q_delta_elpd_vs_null) > 0,
            interpretation = :average_true_q_advantage_over_null),
        (metric = :minimum_true_q_delta_elpd_vs_null,
            value = min_round(replicates, :true_q_delta_elpd_vs_null),
            threshold = 0.0,
            passed = min_round(replicates, :true_q_delta_elpd_vs_null) > 0,
            interpretation = :worst_seed_true_q_advantage_over_null),
        (metric = :mean_true_q_estimation_loss_vs_oracle,
            value = mean_round(replicates, :true_q_delta_elpd_vs_oracle),
            threshold = 0.0,
            passed = mean_round(replicates, :true_q_delta_elpd_vs_oracle) < 0,
            interpretation =
                :posterior_recovery_gap_relative_to_known_truth_oracle),
        (metric = :minimum_true_q_minus_wrong_q_elpd,
            value = min_round(replicates, :true_q_minus_wrong_q_elpd),
            threshold = 0.0,
            passed = min_round(replicates, :true_q_minus_wrong_q_elpd) > 0,
            interpretation = :true_q_beats_wrong_q_in_every_replicate),
    ]
end

function finding_rows(replicates, stability)
    recovery = only(row for row in stability
        if row.metric === :true_q_direction_recovery_rate)
    worst = only(row for row in stability
        if row.metric === :minimum_true_q_delta_elpd_vs_null)
    q_gap = only(row for row in stability
        if row.metric === :minimum_true_q_minus_wrong_q_elpd)
    return [
        (finding = :uto_style_direction_replicated,
            severity = recovery.passed ? :info : :warning,
            evidence = string("recovery rate = ", recovery.value,
                " across ", length(replicates), " seeds"),
            implication = recovery.passed ?
                :true_q_advantage_is_stable_in_this_small_condition :
                :increase_replications_or_inspect_failed_seeds),
        (finding = :worst_seed_margin_recorded,
            severity = worst.passed ? :info : :warning,
            evidence = string("minimum true-Q dELPD vs null = ", worst.value),
            implication =
                :quantifies_how_much_estimation_or_calibration_loss_would_flip_direction),
        (finding = :q_mask_signal_recorded,
            severity = q_gap.passed ? :info : :warning,
            evidence = string("minimum true-Q minus wrong-Q ELPD = ",
                q_gap.value),
            implication = q_gap.passed ?
                :q_mask_matters_under_source_aligned_strong_signal :
                :wrong_q_can_compete_under_some_seed_or_sampler_state),
        (finding = :prior_sensitivity_still_pending,
            severity = :warning,
            evidence =
                "replicated seeds completed with the default internal source prior only",
            implication =
                :next_gate_is_internal_prior_scale_sensitivity_without_public_api_exposure),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local replicated small-MCMC diagnostic only",
            implication =
                :do_not_claim_public_fit_thresholds_q_revisions_or_model_weights),
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
        println(io, "# Uto-Style Replicated Small MCMC Refit")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report repeats the source-aligned Uto-style small-MCMC ",
            "condition across seeds. It checks whether the true-Q MGMFRM ",
            "direction survives generated data and split variation before ",
            "moving to internal prior-scale sensitivity.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Stability")
        table(io, ["Metric", "Value", "Threshold", "Passed",
                "Interpretation"],
            [[row.metric, row.value, row.threshold, row.passed,
                row.interpretation]
             for row in artifact.stability_rows])
        println(io, "## Replicates")
        table(io, ["Seed", "Recovered", "Best", "True-Q dELPD vs Null",
                "True-Q dELPD vs Oracle", "Oracle dELPD vs Null",
                "True-Q - Wrong-Q", "True-Q - Scalar", "True-Q Flag"],
            [[row.seed, row.true_q_direction_recovered,
                row.observed_best_model, row.true_q_delta_elpd_vs_null,
                row.true_q_delta_elpd_vs_oracle,
                row.oracle_delta_elpd_vs_null,
                row.true_q_minus_wrong_q_elpd,
                row.true_q_minus_scalar_elpd,
                row.true_q_sampler_flag]
             for row in artifact.replicate_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This is a local robustness check, not a publication-grade ",
            "simulation. Prior sensitivity is recorded as pending because the ",
            "current prior is an internal source-fixture contract, not a public ",
            "package API.")
    end
    return path
end

function build_artifact(options)
    replicate_artifacts = []
    rows = NamedTuple[]
    for seed in options.seeds
        artifact = SmallMCMC.build_artifact(small_options(options, seed))
        push!(replicate_artifacts, artifact)
        push!(rows, replicate_row(seed, artifact))
    end
    stability = stability_rows(rows)
    findings = finding_rows(rows, stability)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_replicated_small_mcmc_refit,
        status = :local_replicated_mcmc_refit_recorded,
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
            scenario = :uto_like_source_aligned_strong_signal_replicated_small_mcmc,
            seeds = options.seeds,
            n_replicates = length(options.seeds),
            n_persons = options.n_persons,
            n_items = options.n_items,
            n_raters = options.n_raters,
            heldout_fraction = options.heldout_fraction,
            q_true = SmallMCMC.q_rows(SmallMCMC.Q_TRUE),
            q_wrong = SmallMCMC.q_rows(SmallMCMC.Q_WRONG),
        ),
        fit_controls = (;
            backend = :advancedhmc,
            sampler = :nuts,
            chains = options.chains,
            warmup_per_chain = options.warmup_per_chain,
            draws_per_chain = options.draws_per_chain,
            target_acceptance = options.target_acceptance,
            progress = options.progress,
            prior_profile = :default_internal_source_fixture_prior,
        ),
        replicate_rows = rows,
        stability_rows = stability,
        finding_rows = findings,
        summary = (;
            passed = all(row.passed for row in stability
                if row.metric in (:true_q_direction_recovery_rate,
                    :mcmc_fit_success_rate,
                    :mean_true_q_delta_elpd_vs_null)),
            n_replicates = length(rows),
            true_q_direction_recovery_rate =
                only(row for row in stability
                    if row.metric === :true_q_direction_recovery_rate).value,
            minimum_true_q_delta_elpd_vs_null =
                only(row for row in stability
                    if row.metric === :minimum_true_q_delta_elpd_vs_null).value,
            minimum_true_q_minus_wrong_q_elpd =
                only(row for row in stability
                    if row.metric === :minimum_true_q_minus_wrong_q_elpd).value,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = :internal_prior_scale_sensitivity,
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
    println("recovery_rate=",
        artifact.summary.true_q_direction_recovery_rate,
        " min_true_q_delta_elpd_vs_null=",
        artifact.summary.minimum_true_q_delta_elpd_vs_null,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
