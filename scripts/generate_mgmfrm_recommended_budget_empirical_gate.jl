#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_GUIDANCE =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_uto_style_retained_draw_budget_guidance.json")
const DEFAULT_RECOMMENDED_ROOT =
    joinpath(ROOT, "artifacts", "recommended_budget_empirical_gate")
const DEFAULT_PUBLICATION_ROOT =
    joinpath(ROOT, "artifacts", "publication_grade_refit_pilot")
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_recommended_budget_empirical_gate.json")
const DEFAULT_MARKDOWN =
    joinpath(ROOT, "artifacts", "recommended_budget_empirical_gate",
        "recommended_budget_empirical_gate.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_recommended_budget_empirical_gate.v1"

const MGMFRM_UNITS = (
    (model = :confirmatory_mgmfrm_current_q,
        execution_unit_id =
            "well_specified_current_q__confirmatory_mgmfrm_current_q__fold1"),
    (model = :construct_reviewed_revised_q_mgmfrm,
        execution_unit_id =
            "well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold1"),
    (model = :sparse_mgmfrm_current_q,
        execution_unit_id =
            "well_specified_current_q__sparse_mgmfrm_current_q__fold1"),
)

const LOCAL_THRESHOLDS = (;
    chains = 4,
    warmup_per_chain = 128,
    draws_per_chain = 512,
    max_rhat = 1.01,
    min_ess = 400.0,
    max_divergences = 0,
    max_treedepth = 0,
    min_ebfmi = 0.3,
)

function usage()
    return """
    Generate the empirical gate for the local MGMFRM recommended MCMC budget.

    The script summarizes local 4-chain / 128-warmup / 512-retained-draw
    MGMFRM pilot runs, compares them with the heavier publication-grade
    4-chain / 500-warmup / 1000-retained-draw pilot artifacts, and records
    whether the retained-draw guidance is empirically supported for each
    selected MGMFRM model. It does not run MCMC.

    Usage:
      julia --project=. scripts/generate_mgmfrm_recommended_budget_empirical_gate.jl [options]

    Options:
      --guidance PATH              Retained-draw guidance fixture.
      --recommended-root PATH      Root containing 4/128/512 result artifacts.
      --publication-root PATH      Root containing 4/500/1000 pilot artifacts.
      --output PATH                JSON fixture path.
      --markdown PATH              Markdown report path.
    """
end

function parse_args(args)
    guidance = DEFAULT_GUIDANCE
    recommended_root = DEFAULT_RECOMMENDED_ROOT
    publication_root = DEFAULT_PUBLICATION_ROOT
    output = DEFAULT_OUTPUT
    markdown = DEFAULT_MARKDOWN
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--guidance"
            index < length(args) || error("--guidance requires a path")
            guidance = abspath(args[index + 1])
            index += 2
        elseif arg == "--recommended-root"
            index < length(args) || error("--recommended-root requires a path")
            recommended_root = abspath(args[index + 1])
            index += 2
        elseif arg == "--publication-root"
            index < length(args) || error("--publication-root requires a path")
            publication_root = abspath(args[index + 1])
            index += 2
        elseif arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg == "--markdown"
            index < length(args) || error("--markdown requires a path")
            markdown = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    isfile(guidance) || error("guidance fixture not found: $guidance")
    isdir(recommended_root) ||
        error("recommended artifact root not found: $recommended_root")
    isdir(publication_root) ||
        error("publication artifact root not found: $publication_root")
    return (; guidance, recommended_root, publication_root, output, markdown)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
read_json(path::AbstractString) = JSON3.read(read(path, String))

as_string(value) = String(value)
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_float(value) = Float64(value)
as_symbol(value) = Symbol(String(value))

function json_get(object, key::Symbol, default = missing)
    haskey(object, key) || return default
    value = object[key]
    value === nothing && return default
    ismissing(value) && return default
    return value
end

function json_float(object, key::Symbol)
    return as_float(json_get(object, key))
end

function json_bool(object, key::Symbol)
    return as_bool(json_get(object, key))
end

function unit_artifact_path(root::AbstractString, unit_id::AbstractString,
        suffix::AbstractString)
    return joinpath(root, string(unit_id, suffix))
end

function result_paths(root::AbstractString, unit_id::AbstractString)
    return (;
        result = unit_artifact_path(root, unit_id, "_result.json"),
        diagnostics = unit_artifact_path(root, unit_id, "_diagnostics.json"),
        heldout = unit_artifact_path(root, unit_id, "_heldout_score.json"),
    )
end

function require_paths(paths)
    for path in (paths.result, paths.diagnostics, paths.heldout)
        isfile(path) || error("required artifact not found: $path")
    end
    return nothing
end

function input_artifact_row(kind::Symbol, path::AbstractString)
    return (;
        artifact = kind,
        path = rel(path),
        exists = isfile(path),
        sha256 = isfile(path) ? file_sha256(path) : missing,
    )
end

function unit_bundle(root::AbstractString, unit)
    paths = result_paths(root, unit.execution_unit_id)
    require_paths(paths)
    return (;
        result = read_json(paths.result),
        diagnostics = read_json(paths.diagnostics),
        heldout = read_json(paths.heldout),
        paths,
    )
end

function publication_gate_failure_rows(diagnostics, model::Symbol)
    rows = NamedTuple[]
    for row in diagnostics[:diagnostic_rows]
        as_bool(row[:applicable]) || continue
        as_bool(row[:observed]) || continue
        as_bool(row[:passed]) && continue
        diagnostic = as_symbol(row[:diagnostic])
        push!(rows, (;
            model,
            diagnostic,
            value = json_get(row, :value),
            threshold = json_get(row, :threshold),
            failure_class =
                diagnostic in (:warmup_per_chain_min,
                    :draws_per_chain_min) ?
                :publication_grade_budget_threshold_not_targeted :
                :sampler_or_rank_warning,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function local_gate_summary(score_row, controls)
    chains = as_int(controls[:chains])
    warmup = as_int(controls[:warmup_per_chain])
    draws = as_int(controls[:draws_per_chain])
    max_rhat = json_float(score_row, :max_rhat)
    min_ess = json_float(score_row, :min_ess)
    e_bfmi = json_float(score_row, :e_bfmi)
    n_divergences = as_int(score_row[:n_divergences])
    n_max_treedepth = as_int(score_row[:n_max_treedepth])
    control_passed =
        chains >= LOCAL_THRESHOLDS.chains &&
        warmup >= LOCAL_THRESHOLDS.warmup_per_chain &&
        draws >= LOCAL_THRESHOLDS.draws_per_chain
    rank_passed = max_rhat <= LOCAL_THRESHOLDS.max_rhat
    ess_passed = min_ess >= LOCAL_THRESHOLDS.min_ess
    geometry_passed =
        n_divergences <= LOCAL_THRESHOLDS.max_divergences &&
        n_max_treedepth <= LOCAL_THRESHOLDS.max_treedepth &&
        e_bfmi >= LOCAL_THRESHOLDS.min_ebfmi
    finite_passed =
        json_bool(score_row, :finite_log_posterior) &&
        json_bool(score_row, :finite_raw_draws) &&
        json_bool(score_row, :finite_direct_draws) &&
        json_bool(score_row, :finite_training_pointwise_loglikelihood) &&
        json_bool(score_row, :finite_heldout_pointwise_loglikelihood) &&
        json_bool(score_row, :all_pointwise_scores_finite) &&
        json_bool(score_row, :expected_score_residuals_finite)
    ppc_passed = json_bool(score_row, :posterior_predictive_check_recorded)
    passed = control_passed && rank_passed && ess_passed &&
        geometry_passed && finite_passed && ppc_passed
    return (;
        passed,
        control_passed,
        rank_passed,
        ess_passed,
        geometry_passed,
        finite_passed,
        ppc_passed,
        max_rhat,
        min_ess,
        e_bfmi,
        n_divergences,
        n_max_treedepth,
    )
end

function model_row(unit, recommended, publication)
    rec_score = recommended.result[:score_row]
    pub_score = publication.result[:score_row]
    rec_controls = recommended.result[:fit_controls]
    pub_controls = publication.result[:fit_controls]
    local_summary = local_gate_summary(rec_score, rec_controls)
    return (;
        model = unit.model,
        execution_unit_id = unit.execution_unit_id,
        recommended_controls = (;
            chains = as_int(rec_controls[:chains]),
            warmup_per_chain = as_int(rec_controls[:warmup_per_chain]),
            draws_per_chain = as_int(rec_controls[:draws_per_chain]),
            target_acceptance = as_float(rec_controls[:target_acceptance]),
            seed = as_int(rec_controls[:seed]),
        ),
        publication_controls = (;
            chains = as_int(pub_controls[:chains]),
            warmup_per_chain = as_int(pub_controls[:warmup_per_chain]),
            draws_per_chain = as_int(pub_controls[:draws_per_chain]),
            target_acceptance = as_float(pub_controls[:target_acceptance]),
            seed = as_int(pub_controls[:seed]),
        ),
        local_gate_passed = local_summary.passed,
        local_control_passed = local_summary.control_passed,
        local_rank_passed = local_summary.rank_passed,
        local_ess_passed = local_summary.ess_passed,
        local_geometry_passed = local_summary.geometry_passed,
        local_finite_passed = local_summary.finite_passed,
        local_ppc_passed = local_summary.ppc_passed,
        recommended_diagnostic_flag =
            as_symbol(rec_score[:diagnostic_flag]),
        recommended_fit_diagnostic_passed =
            as_bool(rec_score[:diagnostic_passed]),
        recommended_publication_gate_passed =
            as_bool(recommended.result[:summary][:diagnostic_gate_passed]),
        publication_reference_gate_passed =
            as_bool(publication.result[:summary][:diagnostic_gate_passed]),
        recommended_metrics = (;
            max_rhat = local_summary.max_rhat,
            min_ess = local_summary.min_ess,
            e_bfmi = local_summary.e_bfmi,
            n_divergences = local_summary.n_divergences,
            n_max_treedepth = local_summary.n_max_treedepth,
            heldout_elpd = json_float(rec_score, :heldout_elpd),
            heldout_mean_log_predictive_density =
                json_float(rec_score, :heldout_mean_log_predictive_density),
            heldout_expected_score_mae =
                json_float(rec_score, :heldout_expected_score_mae),
            heldout_expected_score_rmse =
                json_float(rec_score, :heldout_expected_score_rmse),
            train_heldout_mean_log_predictive_gap =
                json_float(rec_score, :train_heldout_mean_log_predictive_gap),
        ),
        publication_metrics = (;
            max_rhat = json_float(pub_score, :max_rhat),
            min_ess = json_float(pub_score, :min_ess),
            e_bfmi = json_float(pub_score, :e_bfmi),
            n_divergences = as_int(pub_score[:n_divergences]),
            n_max_treedepth = as_int(pub_score[:n_max_treedepth]),
            heldout_elpd = json_float(pub_score, :heldout_elpd),
            heldout_mean_log_predictive_density =
                json_float(pub_score, :heldout_mean_log_predictive_density),
            heldout_expected_score_mae =
                json_float(pub_score, :heldout_expected_score_mae),
            heldout_expected_score_rmse =
                json_float(pub_score, :heldout_expected_score_rmse),
            train_heldout_mean_log_predictive_gap =
                json_float(pub_score, :train_heldout_mean_log_predictive_gap),
        ),
        deltas = (;
            heldout_elpd =
                json_float(rec_score, :heldout_elpd) -
                json_float(pub_score, :heldout_elpd),
            heldout_mean_log_predictive_density =
                json_float(rec_score, :heldout_mean_log_predictive_density) -
                json_float(pub_score, :heldout_mean_log_predictive_density),
            heldout_expected_score_mae =
                json_float(rec_score, :heldout_expected_score_mae) -
                json_float(pub_score, :heldout_expected_score_mae),
            heldout_expected_score_rmse =
                json_float(rec_score, :heldout_expected_score_rmse) -
                json_float(pub_score, :heldout_expected_score_rmse),
            max_rhat =
                local_summary.max_rhat - json_float(pub_score, :max_rhat),
            min_ess =
                local_summary.min_ess - json_float(pub_score, :min_ess),
        ),
        public_claim_allowed = false,
    )
end

function finding_rows(model_rows, failure_rows)
    n_passed = count(row -> row.local_gate_passed, model_rows)
    n_models = length(model_rows)
    max_abs_elpd_delta =
        maximum(abs(row.deltas.heldout_elpd) for row in model_rows)
    rank_failures =
        [row for row in failure_rows
         if row.failure_class === :sampler_or_rank_warning]
    return [
        (finding = :recommended_budget_empirical_gate_partially_passed,
            severity = n_passed == n_models ? :info : :warning,
            evidence = string(n_passed, "/", n_models,
                " MGMFRM models passed local 4/128/512 diagnostics"),
            implication =
                n_passed == n_models ?
                :eligible_for_broader_scenario_replication :
                :target_failed_model_before_broader_claims,
            public_claim_allowed = false),
        (finding = :publication_grade_budget_thresholds_not_targeted,
            severity = :blocker,
            evidence =
                "4/128/512 intentionally does not meet the 500/1000 publication-grade budget rows",
            implication =
                :do_not_treat_recommended_budget_as_publication_grade_default,
            public_claim_allowed = false),
        (finding = :borderline_rank_warning_detected,
            severity = isempty(rank_failures) ? :info : :warning,
            evidence = isempty(rank_failures) ?
                "no non-budget publication-gate failures at 4/128/512" :
                string(length(rank_failures),
                    " non-budget publication-gate failure(s), led by ",
                    first(rank_failures).model, " ",
                    first(rank_failures).diagnostic),
            implication = isempty(rank_failures) ?
                :continue_to_scenario_replication :
                :rerun_failed_model_with_extended_budget_or_parameterization_review,
            public_claim_allowed = false),
        (finding = :heldout_metrics_descriptively_close_to_publication_budget,
            severity = :info,
            evidence = string("max absolute heldout elpd delta = ",
                round(max_abs_elpd_delta; digits = 4)),
            implication =
                :compare_more_models_and_folds_before_interpreting_fit_metrics,
            public_claim_allowed = false),
        (finding = :public_claims_remain_blocked,
            severity = :blocker,
            evidence =
                :single_fold_local_empirical_budget_gate_only,
            implication =
                :keep_fit_threshold_q_revision_model_weight_and_sparse_superiority_claims_blocked,
            public_claim_allowed = false),
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

function render_markdown(path::AbstractString, artifact)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# MGMFRM Recommended-Budget Empirical Gate")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local budget: `4 chains / 128 warmup / 512 draws`")
        println(io, "- Publication-grade comparator: `4 chains / 500 warmup / 1000 draws`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Model Rows")
        table(io,
            ["Model", "Local Gate", "Rhat", "ESS", "Divergences",
                "Heldout ELPD", "Delta ELPD"],
            [[row.model, row.local_gate_passed,
                 round(row.recommended_metrics.max_rhat; digits = 4),
                 round(row.recommended_metrics.min_ess; digits = 1),
                 row.recommended_metrics.n_divergences,
                 round(row.recommended_metrics.heldout_elpd; digits = 4),
                 round(row.deltas.heldout_elpd; digits = 4)]
             for row in artifact.model_comparison_rows])
        println(io, "## Publication-Gate Failures at 4/128/512")
        table(io, ["Model", "Diagnostic", "Value", "Threshold", "Class"],
            [[row.model, row.diagnostic, row.value, row.threshold,
                 row.failure_class]
             for row in artifact.recommended_publication_gate_failure_rows])
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This gate is a local empirical check of the report-facing ",
            "retained-draw budget guidance. It is not a publication-grade ",
            "default, not a fit-threshold claim, and not evidence for automatic ",
            "Q revision or model-weight claims.")
    end
    return path
end

function build_artifact(options)
    guidance = read_json(options.guidance)
    as_string(guidance[:schema]) ==
        "bayesianmgmfrm.mgmfrm_uto_style_retained_draw_budget_guidance.v1" ||
        error("unexpected guidance schema")
    model_rows = NamedTuple[]
    failure_rows = NamedTuple[]
    input_rows = [input_artifact_row(:retained_draw_budget_guidance,
        options.guidance)]
    for unit in MGMFRM_UNITS
        recommended = unit_bundle(options.recommended_root, unit)
        publication = unit_bundle(options.publication_root, unit)
        append!(input_rows, [
            input_artifact_row(Symbol(string(unit.model, "_recommended_result")),
                recommended.paths.result),
            input_artifact_row(Symbol(string(unit.model, "_recommended_diagnostics")),
                recommended.paths.diagnostics),
            input_artifact_row(Symbol(string(unit.model, "_recommended_heldout")),
                recommended.paths.heldout),
            input_artifact_row(Symbol(string(unit.model, "_publication_result")),
                publication.paths.result),
            input_artifact_row(Symbol(string(unit.model, "_publication_diagnostics")),
                publication.paths.diagnostics),
            input_artifact_row(Symbol(string(unit.model, "_publication_heldout")),
                publication.paths.heldout),
        ])
        push!(model_rows, model_row(unit, recommended, publication))
        append!(failure_rows,
            publication_gate_failure_rows(recommended.diagnostics, unit.model))
    end
    findings = finding_rows(model_rows, failure_rows)
    n_local_passed = count(row -> row.local_gate_passed, model_rows)
    n_publication_reference_passed =
        count(row -> row.publication_reference_gate_passed, model_rows)
    n_geometry_passed = count(row -> row.local_geometry_passed, model_rows)
    n_budget_failures = count(row -> row.failure_class ===
        :publication_grade_budget_threshold_not_targeted, failure_rows)
    n_rank_failures = count(row -> row.failure_class ===
        :sampler_or_rank_warning, failure_rows)
    max_abs_elpd_delta =
        maximum(abs(row.deltas.heldout_elpd) for row in model_rows)
    max_abs_mae_delta =
        maximum(abs(row.deltas.heldout_expected_score_mae)
            for row in model_rows)
    empirical_gate_passed = n_local_passed == length(model_rows)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :recommended_budget_empirical_gate,
        status = :recommended_budget_empirical_gate_recorded,
        generated_at = string(now(UTC)),
        local_only = true,
        publication_or_registration_action = false,
        package_default_change = false,
        fit_api_change = false,
        public_fit_metric_claim = false,
        public_q_revision_claim = false,
        automatic_q_revision = false,
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        local_threshold_policy = LOCAL_THRESHOLDS,
        publication_comparator_policy = (;
            chains = 4,
            warmup_per_chain = 500,
            draws_per_chain = 1000,
            max_rhat = 1.01,
            min_ess = 400.0,
            max_divergences = 0,
            max_treedepth = 0,
            min_ebfmi = 0.3,
        ),
        input_artifacts = input_rows,
        model_comparison_rows = model_rows,
        recommended_publication_gate_failure_rows = failure_rows,
        finding_rows = findings,
        summary = (;
            passed = true,
            empirical_gate_passed,
            n_models = length(model_rows),
            n_recommended_budget_runs = length(model_rows),
            n_local_gate_passed = n_local_passed,
            n_publication_reference_gate_passed =
                n_publication_reference_passed,
            n_local_geometry_passed = n_geometry_passed,
            n_recommended_publication_gate_failures = length(failure_rows),
            n_publication_budget_threshold_failures = n_budget_failures,
            n_sampler_or_rank_failures = n_rank_failures,
            max_abs_heldout_elpd_delta_vs_publication =
                max_abs_elpd_delta,
            max_abs_heldout_expected_score_mae_delta_vs_publication =
                max_abs_mae_delta,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            recommendation = empirical_gate_passed ?
                :replicate_recommended_budget_gate_across_more_scenarios :
                :target_construct_reviewed_revised_q_rank_warning_before_broadening,
            next_gate = empirical_gate_passed ?
                :recommended_budget_scenario_replication :
                :construct_reviewed_revised_q_extended_budget_followup,
        ),
    )
end

function main(args = ARGS)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output, artifact)
    render_markdown(options.markdown, artifact)
    println("wrote ", rel(options.output))
    println("wrote ", rel(options.markdown))
    println("empirical_gate_passed=", artifact.summary.empirical_gate_passed,
        " local_passed=", artifact.summary.n_local_gate_passed,
        "/", artifact.summary.n_models,
        " rank_failures=", artifact.summary.n_sampler_or_rank_failures,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
