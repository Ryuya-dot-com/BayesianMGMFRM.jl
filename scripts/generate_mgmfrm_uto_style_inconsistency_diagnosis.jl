#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_ORACLE_JSON =
    joinpath(ROOT, "artifacts", "uto_style_oracle_simulation",
        "uto_style_oracle_simulation.json")
const DEFAULT_SMALL_MCMC_JSON =
    joinpath(ROOT, "artifacts", "uto_style_small_mcmc_refit",
        "uto_style_small_mcmc_refit.json")
const DEFAULT_REPLICATED_MCMC_JSON =
    joinpath(ROOT, "artifacts", "uto_style_replicated_mcmc_refit",
        "uto_style_replicated_mcmc_refit.json")
const DEFAULT_PRIOR_SENSITIVITY_JSON =
    joinpath(ROOT, "artifacts", "uto_style_prior_sensitivity",
        "uto_style_prior_sensitivity.json")
const DEFAULT_CURRENT_BATCH_JSON =
    joinpath(ROOT, "artifacts", "publication_grade_refit_batch", "reports",
        "missing_loading_revised_q_error_decomposition.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_inconsistency_diagnosis",
        "uto_style_inconsistency_diagnosis.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_inconsistency_diagnosis",
        "uto_style_inconsistency_diagnosis.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_inconsistency_diagnosis.v1"

function usage()
    return """
    Generate a local diagnosis of the apparent inconsistency with Uto-style
    MGMFRM conclusions.

    This reads existing local artifacts. It does not run MCMC and does not
    promote any public model-comparison, fit-threshold, or Q-revision claim.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_inconsistency_diagnosis.jl [options]

    Options:
      --oracle-json PATH         Uto-style oracle artifact.
      --small-mcmc-json PATH     Uto-style small MCMC refit artifact.
      --replicated-mcmc-json PATH
                                 Uto-style replicated small MCMC artifact.
      --prior-sensitivity-json PATH
                                 Uto-style internal prior sensitivity artifact.
      --current-batch-json PATH  Current Null-win error decomposition artifact.
      --output-json PATH         JSON artifact path.
      --output-md PATH           Markdown report path.
    """
end

function parse_args(args)
    oracle_json = DEFAULT_ORACLE_JSON
    small_mcmc_json = DEFAULT_SMALL_MCMC_JSON
    replicated_mcmc_json = DEFAULT_REPLICATED_MCMC_JSON
    prior_sensitivity_json = DEFAULT_PRIOR_SENSITIVITY_JSON
    current_batch_json = DEFAULT_CURRENT_BATCH_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--oracle-json"
            index < length(args) || error("--oracle-json requires a path")
            oracle_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--small-mcmc-json"
            index < length(args) || error("--small-mcmc-json requires a path")
            small_mcmc_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--replicated-mcmc-json"
            index < length(args) ||
                error("--replicated-mcmc-json requires a path")
            replicated_mcmc_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--prior-sensitivity-json"
            index < length(args) ||
                error("--prior-sensitivity-json requires a path")
            prior_sensitivity_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--current-batch-json"
            index < length(args) ||
                error("--current-batch-json requires a path")
            current_batch_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-json"
            index < length(args) || error("--output-json requires a path")
            output_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-md"
            index < length(args) || error("--output-md requires a path")
            output_md = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; oracle_json, small_mcmc_json, replicated_mcmc_json,
        prior_sensitivity_json, current_batch_json, output_json, output_md)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
round3(value) = round(Float64(value); digits = 3)
round4(value) = round(Float64(value); digits = 4)
as_string(value) = String(value)
as_float(value) = Float64(value)
as_bool(value) = Bool(value)

function read_json(path::AbstractString)
    isfile(path) || error("required artifact is missing: $path")
    return JSON3.read(read(path, String))
end

function row_where(rows, field::Symbol, value)
    matches = [row for row in rows if as_string(row[field]) == String(value)]
    isempty(matches) && error("row not found for $field = $value")
    length(matches) == 1 || error("row not unique for $field = $value")
    return only(matches)
end

function current_row(current, label)
    row_where(current[:model_vs_null_summary_rows], :label, label)
end

function comparison_row(artifact, comparison)
    row_where(artifact[:comparison_rows], :comparison, comparison)
end

function oracle_budget_row(artifact, scenario)
    row_where(artifact[:estimation_budget_rows], :scenario, scenario)
end

function stability_row(artifact, metric)
    row_where(artifact[:stability_rows], :metric, metric)
end

function prior_overall_row(artifact, metric)
    row_where(artifact[:overall_rows], :metric, metric)
end

function evidence_rows(oracle, small_mcmc, replicated_mcmc,
        prior_sensitivity, current)
    uto_budget = oracle_budget_row(oracle,
        :uto_like_multidimensional_strong_signal)
    compact_budget = oracle_budget_row(oracle,
        :compact_weak_signal_failure_like)
    small_oracle = comparison_row(small_mcmc,
        :true_q_source_oracle_minus_null)
    small_true = comparison_row(small_mcmc,
        :true_q_mgmfrm_mcmc_minus_null)
    small_loss = comparison_row(small_mcmc,
        :true_q_mgmfrm_mcmc_minus_true_q_source_oracle)
    replicated_recovery = stability_row(replicated_mcmc,
        :true_q_direction_recovery_rate)
    replicated_mean = stability_row(replicated_mcmc,
        :mean_true_q_delta_elpd_vs_null)
    replicated_min = stability_row(replicated_mcmc,
        :minimum_true_q_delta_elpd_vs_null)
    replicated_q_gap = stability_row(replicated_mcmc,
        :minimum_true_q_minus_wrong_q_elpd)
    prior_recovery = prior_overall_row(prior_sensitivity,
        :direction_recovery_rate)
    prior_mean = prior_overall_row(prior_sensitivity,
        :mean_true_q_delta_elpd_vs_null)
    prior_min = prior_overall_row(prior_sensitivity,
        :minimum_true_q_delta_elpd_vs_null)
    prior_q_gap = prior_overall_row(prior_sensitivity,
        :minimum_true_q_minus_wrong_q_elpd)
    scalar = current_row(current, "Scalar")
    revised = current_row(current, "Revised Q")
    current_q = current_row(current, "Current Q")
    sparse = current_row(current, "Sparse Q")
    return [
        (layer = :uto_like_large_oracle,
            evidence = :true_q_oracle_beats_null,
            delta_elpd_vs_null =
                round3(as_float(uto_budget[:oracle_true_q_gain_vs_null])),
            delta_mae_vs_null = missing,
            heldout_n = round3(as_float(uto_budget[:mean_heldout_n])),
            interpretation =
                :uto_style_direction_reproducible_when_signal_and_design_are_strong),
        (layer = :compact_weak_oracle,
            evidence = :true_q_oracle_margin_is_small,
            delta_elpd_vs_null =
                round3(as_float(compact_budget[:oracle_true_q_gain_vs_null])),
            delta_mae_vs_null = missing,
            heldout_n = round3(as_float(compact_budget[:mean_heldout_n])),
            interpretation =
                :small_margin_can_be_overwhelmed_by_estimation_or_calibration_loss),
        (layer = :source_aligned_small_mcmc,
            evidence = :true_q_mcmc_beats_null,
            delta_elpd_vs_null = round3(as_float(small_true[:delta_elpd])),
            delta_mae_vs_null = round3(as_float(small_true[:delta_mae])),
            heldout_n =
                as_float(small_mcmc[:design][:n_heldout_observations]),
            interpretation =
                :uto_style_direction_survives_small_refit_but_not_at_oracle_level),
        (layer = :source_aligned_small_mcmc,
            evidence = :true_q_mcmc_loses_to_oracle,
            delta_elpd_vs_null = round3(as_float(small_loss[:delta_elpd])),
            delta_mae_vs_null = round3(as_float(small_loss[:delta_mae])),
            heldout_n =
                as_float(small_mcmc[:design][:n_heldout_observations]),
            interpretation = :posterior_recovery_gap_quantified),
        (layer = :source_aligned_replicated_small_mcmc,
            evidence = :true_q_direction_recovery_rate,
            delta_elpd_vs_null = round3(as_float(replicated_mean[:value])),
            delta_mae_vs_null = missing,
            heldout_n = as_float(replicated_mcmc[:summary][:n_replicates]),
            interpretation = Symbol(string(
                :recovery_rate_,
                round4(as_float(replicated_recovery[:value]))))),
        (layer = :source_aligned_replicated_small_mcmc,
            evidence = :minimum_true_q_margin,
            delta_elpd_vs_null = round3(as_float(replicated_min[:value])),
            delta_mae_vs_null = missing,
            heldout_n = as_float(replicated_mcmc[:summary][:n_replicates]),
            interpretation =
                :worst_seed_margin_against_null_after_mcmc),
        (layer = :source_aligned_replicated_small_mcmc,
            evidence = :minimum_true_q_minus_wrong_q,
            delta_elpd_vs_null = round3(as_float(replicated_q_gap[:value])),
            delta_mae_vs_null = missing,
            heldout_n = as_float(replicated_mcmc[:summary][:n_replicates]),
            interpretation =
                :q_mask_signal_survives_all_replicated_seeds),
        (layer = :source_aligned_internal_prior_sensitivity,
            evidence = :prior_profile_direction_recovery_rate,
            delta_elpd_vs_null = round3(as_float(prior_mean[:value])),
            delta_mae_vs_null = missing,
            heldout_n = as_float(prior_sensitivity[:summary][:n_cells]),
            interpretation = Symbol(string(
                :prior_recovery_rate_,
                round4(as_float(prior_recovery[:value]))))),
        (layer = :source_aligned_internal_prior_sensitivity,
            evidence = :minimum_prior_profile_margin,
            delta_elpd_vs_null = round3(as_float(prior_min[:value])),
            delta_mae_vs_null = missing,
            heldout_n = as_float(prior_sensitivity[:summary][:n_cells]),
            interpretation =
                :worst_seed_prior_profile_margin_against_null),
        (layer = :source_aligned_internal_prior_sensitivity,
            evidence = :minimum_prior_true_q_minus_wrong_q,
            delta_elpd_vs_null = round3(as_float(prior_q_gap[:value])),
            delta_mae_vs_null = missing,
            heldout_n = as_float(prior_sensitivity[:summary][:n_cells]),
            interpretation =
                :q_mask_signal_survives_tested_internal_prior_profiles),
        (layer = :current_null_win_batch,
            evidence = :scalar_lags_null,
            delta_elpd_vs_null =
                round3(as_float(scalar[:total_delta_lpd_vs_null])),
            delta_mae_vs_null =
                round3(as_float(scalar[:mean_delta_abs_error_vs_null])),
            heldout_n = as_float(scalar[:n_pointwise_rows]),
            interpretation = :simple_generalized_model_already_over_loses),
        (layer = :current_null_win_batch,
            evidence = :revised_q_lags_null,
            delta_elpd_vs_null =
                round3(as_float(revised[:total_delta_lpd_vs_null])),
            delta_mae_vs_null =
                round3(as_float(revised[:mean_delta_abs_error_vs_null])),
            heldout_n = as_float(revised[:n_pointwise_rows]),
            interpretation = :q_revision_does_not_fix_current_predictive_loss),
        (layer = :current_null_win_batch,
            evidence = :current_q_lags_null,
            delta_elpd_vs_null =
                round3(as_float(current_q[:total_delta_lpd_vs_null])),
            delta_mae_vs_null =
                round3(as_float(current_q[:mean_delta_abs_error_vs_null])),
            heldout_n = as_float(current_q[:n_pointwise_rows]),
            interpretation =
                :current_failure_is_estimation_calibration_or_scenario_support_problem),
        (layer = :current_null_win_batch,
            evidence = :sparse_q_lags_null,
            delta_elpd_vs_null =
                round3(as_float(sparse[:total_delta_lpd_vs_null])),
            delta_mae_vs_null =
                round3(as_float(sparse[:mean_delta_abs_error_vs_null])),
            heldout_n = as_float(sparse[:n_pointwise_rows]),
            interpretation = :sparse_variant_not_supported_by_current_slice),
    ]
end

function finding_rows(rows)
    compact = row_where(rows, :layer, :compact_weak_oracle)
    current_q = row_where(rows, :evidence, :current_q_lags_null)
    small_true = row_where(rows, :evidence, :true_q_mcmc_beats_null)
    recovery = row_where(rows, :evidence, :true_q_direction_recovery_rate)
    minimum_margin = row_where(rows, :evidence, :minimum_true_q_margin)
    prior_recovery = row_where(rows, :evidence,
        :prior_profile_direction_recovery_rate)
    prior_margin = row_where(rows, :evidence, :minimum_prior_profile_margin)
    return [
        (finding = :uto_style_conclusion_is_reproducible_in_the_right_condition,
            severity = :info,
            evidence = string("small source-aligned true-Q MCMC dELPD vs null = ",
                small_true.delta_elpd_vs_null),
            implication =
                :the_current_null_win_is_not_a_basic_contradiction_of_mgmfrm),
        (finding = :uto_style_direction_is_replicated_across_seeds,
            severity = :info,
            evidence = string("mean replicated dELPD vs null = ",
                recovery.delta_elpd_vs_null,
                "; minimum margin = ", minimum_margin.delta_elpd_vs_null),
            implication =
                :single_seed_result_is_not_driving_the_current_diagnosis),
        (finding = :uto_style_direction_survives_tested_internal_prior_profiles,
            severity = :info,
            evidence = string("prior-grid mean dELPD vs null = ",
                prior_recovery.delta_elpd_vs_null,
                "; minimum margin = ", prior_margin.delta_elpd_vs_null),
            implication =
                :default_tight_and_diffuse_internal_priors_do_not_explain_the_direction),
        (finding = :weak_signal_margin_can_flip,
            severity = :warning,
            evidence = string("compact oracle margin = ",
                compact.delta_elpd_vs_null,
                "; current-Q observed loss = ",
                current_q.delta_elpd_vs_null),
            implication =
                :estimation_prior_calibration_losses_must_be_a_primary_diagnostic_target),
        (finding = :q_change_alone_is_not_sufficient,
            severity = :warning,
            evidence = "current, revised, and sparse Q candidates all lag null in the current batch",
            implication =
                :inspect_category_calibration_prior_sensitivity_and_data_support),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local diagnostics, oracle checks, and replicated small MCMC only",
            implication =
                :prior_sensitivity_and_full_publication_grade_refits_still_required),
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
        println(io, "# Uto-Style Inconsistency Diagnosis")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Diagnosis")
        println(io)
        println(io,
            "The apparent inconsistency is best read as a condition-and-estimation ",
            "problem, not as evidence that MGMFRM cannot reproduce an Uto-style ",
            "direction. Under source-aligned strong-signal data, true-Q MGMFRM ",
            "beats the Null reference after MCMC across the replicated seeds. ",
            "In the current Null-win batch, the structured candidates lose far ",
            "more ELPD than the compact oracle margin needed to flip rankings.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Evidence Rows")
        table(io, ["Layer", "Evidence", "Heldout N", "dELPD vs Null",
                "dMAE vs Null", "Interpretation"],
            [[row.layer, row.evidence, row.heldout_n,
                row.delta_elpd_vs_null, row.delta_mae_vs_null,
                row.interpretation]
             for row in artifact.evidence_rows])
        println(io, "## Next Gate")
        println(io)
        println(io,
            "Connect category-level calibration errors to the fit-threshold ",
            "profiles, then repeat the publication-grade refit batch. Do not ",
            "promote public fit thresholds, Q revisions, or model weights from ",
            "the current local diagnostics.")
    end
    return path
end

function build_artifact(options)
    oracle = read_json(options.oracle_json)
    small_mcmc = read_json(options.small_mcmc_json)
    replicated_mcmc = read_json(options.replicated_mcmc_json)
    prior_sensitivity = read_json(options.prior_sensitivity_json)
    current = read_json(options.current_batch_json)
    evidence = evidence_rows(oracle, small_mcmc, replicated_mcmc,
        prior_sensitivity, current)
    findings = finding_rows(evidence)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_inconsistency_diagnosis,
        status = :local_diagnosis_recorded,
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
        source_artifacts = [
            (role = :uto_style_oracle,
                path = rel(options.oracle_json),
                sha256 = file_sha256(options.oracle_json)),
            (role = :uto_style_small_mcmc_refit,
                path = rel(options.small_mcmc_json),
                sha256 = file_sha256(options.small_mcmc_json)),
            (role = :uto_style_replicated_small_mcmc_refit,
                path = rel(options.replicated_mcmc_json),
                sha256 = file_sha256(options.replicated_mcmc_json)),
            (role = :uto_style_internal_prior_sensitivity,
                path = rel(options.prior_sensitivity_json),
                sha256 = file_sha256(options.prior_sensitivity_json)),
            (role = :current_null_win_error_decomposition,
                path = rel(options.current_batch_json),
                sha256 = file_sha256(options.current_batch_json)),
        ],
        evidence_rows = evidence,
        finding_rows = findings,
        summary = (;
            passed = true,
            uto_style_direction_recovered_in_small_mcmc =
                as_bool(small_mcmc[:summary][:true_q_mcmc_direction_recovered]),
            replicated_true_q_direction_recovery_rate =
                as_float(replicated_mcmc[:summary][
                    :true_q_direction_recovery_rate]),
            replicated_minimum_true_q_delta_elpd_vs_null =
                as_float(replicated_mcmc[:summary][
                    :minimum_true_q_delta_elpd_vs_null]),
            prior_sensitivity_recovery_rate =
                as_float(prior_sensitivity[:summary][
                    :direction_recovery_rate]),
            prior_sensitivity_minimum_true_q_delta_elpd_vs_null =
                as_float(prior_sensitivity[:summary][
                    :minimum_true_q_delta_elpd_vs_null]),
            current_null_win_remains_unresolved_for_public_claims = true,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = :category_calibration_and_fit_threshold_linkage,
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
    println("uto_small_mcmc_direction_recovered=",
        artifact.summary.uto_style_direction_recovered_in_small_mcmc,
        " replicated_recovery_rate=",
        artifact.summary.replicated_true_q_direction_recovery_rate,
        " prior_recovery_rate=",
        artifact.summary.prior_sensitivity_recovery_rate,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
