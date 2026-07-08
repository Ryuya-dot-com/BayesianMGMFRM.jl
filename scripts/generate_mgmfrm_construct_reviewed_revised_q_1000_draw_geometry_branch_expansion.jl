#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_PREVIOUS_FIXTURE =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_construct_reviewed_revised_q_1000_draw_scenario_replication.json")
const DEFAULT_FOLLOWUP_ROOT =
    joinpath(ROOT, "artifacts",
        "construct_reviewed_revised_q_extended_budget_followup")
const DEFAULT_SMOKE_ROOT =
    joinpath(ROOT, "artifacts",
        "construct_reviewed_revised_q_1000_draw_scenario_replication")
const DEFAULT_EXPANSION_ROOT =
    joinpath(ROOT, "artifacts",
        "construct_reviewed_revised_q_1000_draw_geometry_branch_expansion")
const DEFAULT_PUBLICATION_BATCH_ROOT =
    joinpath(ROOT, "artifacts", "publication_grade_refit_batch")
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_construct_reviewed_revised_q_1000_draw_geometry_branch_expansion.json")
const DEFAULT_MARKDOWN =
    joinpath(ROOT, "artifacts",
        "construct_reviewed_revised_q_1000_draw_geometry_branch_expansion",
        "construct_reviewed_revised_q_1000_draw_geometry_branch_expansion.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_construct_reviewed_revised_q_1000_draw_geometry_branch_expansion.v1"
const MODEL = :construct_reviewed_revised_q_mgmfrm
const SCENARIOS = (
    :missing_loading_revised_q,
    :rater_method_noise,
    :sparse_signal_current_q,
    :weak_dimension_ambiguous,
    :well_specified_current_q,
)
const FOLDS = 1:5

const LOCAL_THRESHOLDS = (;
    chains = 4,
    warmup_per_chain = 128,
    draws_per_chain = 1000,
    max_rhat = 1.01,
    min_ess = 400.0,
    max_divergences = 0,
    max_treedepth = 0,
    min_ebfmi = 0.3,
)

const GEOMETRY_REMEDIATION_PROFILES = (
    (suffix = "4_128_1000_ta090",
        role = :target_acceptance_geometry_remediation,
        warmup_per_chain = 128,
        target_acceptance = 0.9),
    (suffix = "4_256_1000_ta080",
        role = :warmup_geometry_remediation,
        warmup_per_chain = 256,
        target_acceptance = 0.8),
    (suffix = "4_256_1000_ta090",
        role = :combined_geometry_remediation,
        warmup_per_chain = 256,
        target_acceptance = 0.9),
)

function usage()
    return """
    Generate the construct-reviewed revised-Q 1000-draw geometry-branch expansion.

    This script reads local runner artifacts. It does not run MCMC. It expands
    the default 4/128/1000 construct-reviewed revised-Q check to all 25
    scenario/fold cells, then summarizes geometry-remediation profiles for the
    divergent cells.

    Usage:
      julia --project=. scripts/generate_mgmfrm_construct_reviewed_revised_q_1000_draw_geometry_branch_expansion.jl [options]

    Options:
      --previous-fixture PATH          Scenario-replication fixture.
      --followup-root PATH             Prior fold-1 follow-up artifact root.
      --smoke-root PATH                Scenario-replication artifact root.
      --expansion-root PATH            Geometry-branch expansion artifact root.
      --publication-batch-root PATH    Publication-batch comparator artifact root.
      --output PATH                    JSON fixture path.
      --markdown PATH                  Markdown report path.
    """
end

function parse_args(args)
    previous_fixture = DEFAULT_PREVIOUS_FIXTURE
    followup_root = DEFAULT_FOLLOWUP_ROOT
    smoke_root = DEFAULT_SMOKE_ROOT
    expansion_root = DEFAULT_EXPANSION_ROOT
    publication_batch_root = DEFAULT_PUBLICATION_BATCH_ROOT
    output = DEFAULT_OUTPUT
    markdown = DEFAULT_MARKDOWN
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--previous-fixture"
            index < length(args) || error("--previous-fixture requires a path")
            previous_fixture = abspath(args[index + 1])
            index += 2
        elseif arg == "--followup-root"
            index < length(args) || error("--followup-root requires a path")
            followup_root = abspath(args[index + 1])
            index += 2
        elseif arg == "--smoke-root"
            index < length(args) || error("--smoke-root requires a path")
            smoke_root = abspath(args[index + 1])
            index += 2
        elseif arg == "--expansion-root"
            index < length(args) || error("--expansion-root requires a path")
            expansion_root = abspath(args[index + 1])
            index += 2
        elseif arg == "--publication-batch-root"
            index < length(args) ||
                error("--publication-batch-root requires a path")
            publication_batch_root = abspath(args[index + 1])
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
    isfile(previous_fixture) ||
        error("previous fixture not found: $previous_fixture")
    isdir(followup_root) || error("follow-up root not found: $followup_root")
    isdir(smoke_root) || error("smoke root not found: $smoke_root")
    isdir(expansion_root) ||
        error("expansion root not found: $expansion_root")
    isdir(publication_batch_root) ||
        error("publication batch root not found: $publication_batch_root")
    return (; previous_fixture, followup_root, smoke_root, expansion_root,
        publication_batch_root, output, markdown)
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

function unit_id(scenario::Symbol, fold::Int)
    return string(scenario, "__", MODEL, "__fold", fold)
end

function default_stem(unit::AbstractString)
    return string(unit, "_4_128_1000_ta080")
end

function default_result_path(options, scenario::Symbol, fold::Int)
    unit = unit_id(scenario, fold)
    if scenario === :well_specified_current_q && fold == 1
        return joinpath(options.followup_root,
            "draws_only_4_128_1000_ta080_result.json")
    elseif (scenario === :well_specified_current_q && fold in (2, 3)) ||
           (scenario === :missing_loading_revised_q && fold == 1)
        return joinpath(options.smoke_root,
            string(default_stem(unit), "_result.json"))
    end
    return joinpath(options.expansion_root,
        string(default_stem(unit), "_result.json"))
end

function remediation_result_path(options, scenario::Symbol, fold::Int,
        suffix::AbstractString)
    unit = unit_id(scenario, fold)
    root = fold == 2 ? options.smoke_root : options.expansion_root
    return joinpath(root, string(unit, "_", suffix, "_result.json"))
end

publication_result_path(options, scenario::Symbol, fold::Int) =
    joinpath(options.publication_batch_root,
        string(unit_id(scenario, fold), "_result.json"))

function sibling_output_path(result_path::AbstractString, suffix::AbstractString)
    marker = "_result.json"
    if endswith(result_path, marker)
        return string(first(result_path, lastindex(result_path) - length(marker)),
            suffix)
    end
    stem, _ = splitext(result_path)
    return string(stem, suffix)
end

function artifact_paths(result::AbstractString)
    return (;
        result,
        diagnostics = sibling_output_path(result, "_diagnostics.json"),
        heldout = sibling_output_path(result, "_heldout_score.json"),
    )
end

function require_paths(paths)
    for path in (paths.result, paths.diagnostics, paths.heldout)
        isfile(path) || error("required artifact not found: $path")
    end
    return nothing
end

function input_artifact_row(artifact::Symbol, path::AbstractString)
    return (;
        artifact,
        path = rel(path),
        exists = isfile(path),
        sha256 = isfile(path) ? file_sha256(path) : missing,
    )
end

function local_gate_summary(score_row, controls)
    chains = as_int(controls[:chains])
    warmup = as_int(controls[:warmup_per_chain])
    draws = as_int(controls[:draws_per_chain])
    max_rhat = as_float(score_row[:max_rhat])
    min_ess = as_float(score_row[:min_ess])
    e_bfmi = as_float(score_row[:e_bfmi])
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
        as_bool(score_row[:finite_log_posterior]) &&
        as_bool(score_row[:finite_raw_draws]) &&
        as_bool(score_row[:finite_direct_draws]) &&
        as_bool(score_row[:finite_training_pointwise_loglikelihood]) &&
        as_bool(score_row[:finite_heldout_pointwise_loglikelihood]) &&
        as_bool(score_row[:all_pointwise_scores_finite]) &&
        as_bool(score_row[:expected_score_residuals_finite])
    ppc_passed = as_bool(score_row[:posterior_predictive_check_recorded])
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

function profile_row(profile::Symbol, role::Symbol, paths)
    artifact = read_json(paths.result)
    score = artifact[:score_row]
    controls = artifact[:fit_controls]
    local_summary = local_gate_summary(score, controls)
    return (;
        profile,
        role,
        scenario = as_symbol(score[:scenario]),
        model = MODEL,
        execution_unit_id = as_symbol(score[:execution_unit_id]),
        fold = as_int(score[:fold]),
        controls = (;
            chains = as_int(controls[:chains]),
            warmup_per_chain = as_int(controls[:warmup_per_chain]),
            draws_per_chain = as_int(controls[:draws_per_chain]),
            target_acceptance = as_float(controls[:target_acceptance]),
            seed = as_int(controls[:seed]),
        ),
        local_gate_passed = local_summary.passed,
        local_control_passed = local_summary.control_passed,
        local_rank_passed = local_summary.rank_passed,
        local_ess_passed = local_summary.ess_passed,
        local_geometry_passed = local_summary.geometry_passed,
        local_finite_passed = local_summary.finite_passed,
        local_ppc_passed = local_summary.ppc_passed,
        diagnostic_flag = as_symbol(score[:diagnostic_flag]),
        fit_diagnostic_passed = as_bool(score[:diagnostic_passed]),
        publication_gate_passed =
            as_bool(artifact[:summary][:diagnostic_gate_passed]),
        metrics = (;
            max_rhat = local_summary.max_rhat,
            min_ess = local_summary.min_ess,
            e_bfmi = local_summary.e_bfmi,
            n_divergences = local_summary.n_divergences,
            n_max_treedepth = local_summary.n_max_treedepth,
            heldout_elpd = as_float(score[:heldout_elpd]),
            heldout_expected_score_mae =
                as_float(score[:heldout_expected_score_mae]),
            heldout_expected_score_rmse =
                as_float(score[:heldout_expected_score_rmse]),
        ),
        artifact_path = rel(paths.result),
        public_claim_allowed = false,
    )
end

function default_profile(options, scenario::Symbol, fold::Int)
    paths = artifact_paths(default_result_path(options, scenario, fold))
    require_paths(paths)
    return profile_row(Symbol(string(scenario, "_fold", fold, "_4_128_1000_ta080")),
        :default_4_128_1000, paths), paths
end

function remediation_profile(options, scenario::Symbol, fold::Int, remediation)
    paths = artifact_paths(remediation_result_path(options, scenario, fold,
        remediation.suffix))
    require_paths(paths)
    return profile_row(Symbol(string(scenario, "_fold", fold, "_",
            remediation.suffix)),
        remediation.role, paths), paths
end

function publication_comparator_row(options, scenario::Symbol, fold::Int,
        light_row)
    paths = artifact_paths(publication_result_path(options, scenario, fold))
    require_paths(paths)
    heavy = profile_row(Symbol(string(scenario, "_fold", fold,
            "_4_500_1000_ta080")),
        :publication_grade_comparator, paths)
    return (;
        scenario,
        fold,
        light_profile = light_row.profile,
        heavy_profile = heavy.profile,
        light_local_gate_passed = Bool(light_row.local_gate_passed),
        heavy_local_gate_passed = Bool(heavy.local_gate_passed),
        heavy_publication_gate_passed = Bool(heavy.publication_gate_passed),
        light_heldout_elpd = light_row.metrics.heldout_elpd,
        heavy_heldout_elpd = heavy.metrics.heldout_elpd,
        heldout_elpd_delta =
            light_row.metrics.heldout_elpd - heavy.metrics.heldout_elpd,
        light_heldout_expected_score_mae =
            light_row.metrics.heldout_expected_score_mae,
        heavy_heldout_expected_score_mae =
            heavy.metrics.heldout_expected_score_mae,
        heldout_expected_score_mae_delta =
            light_row.metrics.heldout_expected_score_mae -
            heavy.metrics.heldout_expected_score_mae,
        light_max_rhat = light_row.metrics.max_rhat,
        heavy_max_rhat = heavy.metrics.max_rhat,
        light_n_divergences = light_row.metrics.n_divergences,
        heavy_n_divergences = heavy.metrics.n_divergences,
        heavy_artifact_path = rel(paths.result),
    ), paths
end

function table(io, headers, rows)
    println(io, "| ", join(headers, " | "), " |")
    println(io, "| ", join(fill("---", length(headers)), " | "), " |")
    for row in rows
        println(io, "| ", join(string.(row), " | "), " |")
    end
    println(io)
end

function finding_rows(default_rows, remediation_rows, comparator_rows)
    default_failures = [row for row in default_rows if !row.local_gate_passed]
    geometry_failures =
        [row for row in default_rows if !row.local_geometry_passed]
    rank_failures = [row for row in default_rows if !row.local_rank_passed]
    remission_by_failed_fold = Dict{Tuple{Symbol,Int},Vector{Any}}()
    for row in remediation_rows
        key = (row.scenario, row.fold)
        remission_by_failed_fold[key] =
            get(remission_by_failed_fold, key, Any[])
        push!(remission_by_failed_fold[key], row)
    end
    all_geometry_failures_remediated = all(geometry_failures) do row
        remedial = get(remission_by_failed_fold, (row.scenario, row.fold), Any[])
        !isempty(remedial) && all(r -> Bool(r.local_gate_passed), remedial)
    end
    max_abs_elpd_delta = maximum(abs(row.heldout_elpd_delta)
        for row in comparator_rows)
    return [
        (finding = :full_default_1000_draw_rank_replicated,
            severity = isempty(rank_failures) ? :info : :warning,
            evidence = string(length(default_rows) - length(rank_failures),
                "/", length(default_rows),
                " default profiles passed rank; max R-hat = ",
                round(maximum(row.metrics.max_rhat for row in default_rows);
                    digits = 4)),
            implication = :retain_1000_draw_rank_guidance_candidate,
            public_claim_allowed = false),
        (finding = :default_geometry_failures_localized,
            severity = isempty(geometry_failures) ? :info : :warning,
            evidence = string(length(geometry_failures),
                " default geometry failures; all in well_specified_current_q = ",
                all(row.scenario === :well_specified_current_q
                    for row in geometry_failures)),
            implication = :use_geometry_branch_instead_of_rank_budget_change,
            public_claim_allowed = false),
        (finding = :geometry_remediation_branch_cleared_failures,
            severity = all_geometry_failures_remediated ? :info : :warning,
            evidence = string(count(row -> row.local_gate_passed,
                    remediation_rows), "/", length(remediation_rows),
                " remediation profiles passed"),
            implication =
                :target_acceptance_or_warmup_sensitivity_can_clear_divergent_cells,
            public_claim_allowed = false),
        (finding = :missing_loading_lightweight_close_to_heavy_comparator,
            severity = :info,
            evidence = string("max abs dELPD vs 4/500/1000 = ",
                round(max_abs_elpd_delta; digits = 4)),
            implication =
                :lightweight_profile_tracks_heavy_reference_descriptively_in_this_scenario,
            public_claim_allowed = false),
        (finding = :public_claims_remain_blocked,
            severity = :blocker,
            evidence = :local_synthetic_construct_reviewed_revised_q_diagnostic_only,
            implication =
                :connect_to_model_comparison_category_calibration_and_external_construct_evidence,
            public_claim_allowed = false),
    ]
end

function render_markdown(path::AbstractString, artifact)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# Construct-Reviewed Revised-Q 1000-Draw Geometry Branch Expansion")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Model: `construct_reviewed_revised_q_mgmfrm`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Scenario Summary")
        table(io,
            ["Scenario", "Default gate", "Rank", "Geometry", "Total div", "Max Rhat"],
            [[row.scenario, string(row.n_default_local_gate_passed, "/",
                 row.n_default_profiles),
                 string(row.n_default_rank_passed, "/", row.n_default_profiles),
                 string(row.n_default_geometry_passed, "/", row.n_default_profiles),
                 row.total_divergences,
                 round(row.max_rhat; digits = 4)]
             for row in artifact.scenario_summary_rows])
        println(io, "## Geometry Failure Rows")
        table(io,
            ["Scenario", "Fold", "Rhat", "ESS", "Divergences", "EBFMI"],
            [[row.scenario, row.fold,
                 round(row.metrics.max_rhat; digits = 4),
                 round(row.metrics.min_ess; digits = 1),
                 row.metrics.n_divergences,
                 round(row.metrics.e_bfmi; digits = 4)]
             for row in artifact.default_geometry_failure_rows])
        println(io, "## Remediation Rows")
        table(io,
            ["Profile", "Fold", "Gate", "Rhat", "Divergences", "ELPD"],
            [[row.profile, row.fold, row.local_gate_passed,
                 round(row.metrics.max_rhat; digits = 4),
                 row.metrics.n_divergences,
                 round(row.metrics.heldout_elpd; digits = 4)]
             for row in artifact.remediation_rows])
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
    end
    return path
end

function build_artifact(options)
    previous = read_json(options.previous_fixture)
    as_string(previous[:schema]) ==
        "bayesianmgmfrm.mgmfrm_construct_reviewed_revised_q_1000_draw_scenario_replication.v1" ||
        error("unexpected previous fixture schema")

    input_rows = [
        input_artifact_row(:previous_1000_draw_scenario_replication_fixture,
            options.previous_fixture),
    ]
    default_rows = NamedTuple[]
    default_paths = []
    for scenario in SCENARIOS, fold in FOLDS
        row, paths = default_profile(options, scenario, fold)
        push!(default_rows, row)
        push!(default_paths, paths)
        append!(input_rows, [
            input_artifact_row(Symbol(string(row.profile, "_result")),
                paths.result),
            input_artifact_row(Symbol(string(row.profile, "_diagnostics")),
                paths.diagnostics),
            input_artifact_row(Symbol(string(row.profile, "_heldout")),
                paths.heldout),
        ])
    end
    sort!(default_rows; by = row -> (String(row.scenario), row.fold))

    geometry_failures =
        [row for row in default_rows if !row.local_geometry_passed]
    remediation_rows = NamedTuple[]
    for failed in geometry_failures, remediation in GEOMETRY_REMEDIATION_PROFILES
        row, paths = remediation_profile(options, failed.scenario,
            failed.fold, remediation)
        push!(remediation_rows, row)
        append!(input_rows, [
            input_artifact_row(Symbol(string(row.profile, "_result")),
                paths.result),
            input_artifact_row(Symbol(string(row.profile, "_diagnostics")),
                paths.diagnostics),
            input_artifact_row(Symbol(string(row.profile, "_heldout")),
                paths.heldout),
        ])
    end
    sort!(remediation_rows; by = row -> (String(row.scenario), row.fold,
        row.controls.warmup_per_chain, row.controls.target_acceptance))

    comparator_rows = NamedTuple[]
    for fold in FOLDS
        light = only(row for row in default_rows
            if row.scenario === :missing_loading_revised_q && row.fold == fold)
        row, paths = publication_comparator_row(options,
            :missing_loading_revised_q, fold, light)
        push!(comparator_rows, row)
        append!(input_rows, [
            input_artifact_row(Symbol(string(row.heavy_profile, "_result")),
                paths.result),
            input_artifact_row(Symbol(string(row.heavy_profile, "_diagnostics")),
                paths.diagnostics),
            input_artifact_row(Symbol(string(row.heavy_profile, "_heldout")),
                paths.heldout),
        ])
    end

    scenario_summary_rows = [
        begin
            rows = [row for row in default_rows if row.scenario === scenario]
            (;
                scenario,
                n_default_profiles = length(rows),
                n_default_local_gate_passed =
                    count(row -> row.local_gate_passed, rows),
                n_default_rank_passed =
                    count(row -> row.local_rank_passed, rows),
                n_default_geometry_passed =
                    count(row -> row.local_geometry_passed, rows),
                total_divergences =
                    sum(row.metrics.n_divergences for row in rows),
                max_rhat = maximum(row.metrics.max_rhat for row in rows),
                min_ess = minimum(row.metrics.min_ess for row in rows),
                min_ebfmi = minimum(row.metrics.e_bfmi for row in rows),
                public_claim_allowed = false,
            )
        end
        for scenario in SCENARIOS
    ]
    findings = finding_rows(default_rows, remediation_rows, comparator_rows)
    default_rank_failures =
        [row for row in default_rows if !row.local_rank_passed]
    default_local_failures =
        [row for row in default_rows if !row.local_gate_passed]
    all_remediation_passed = all(row -> Bool(row.local_gate_passed),
        remediation_rows)
    target_accept_rows = [row for row in remediation_rows
        if row.role === :target_acceptance_geometry_remediation]
    warmup_rows = [row for row in remediation_rows
        if row.role === :warmup_geometry_remediation]
    combined_rows = [row for row in remediation_rows
        if row.role === :combined_geometry_remediation]
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :construct_reviewed_revised_q_1000_draw_geometry_branch_expansion,
        status =
            :construct_reviewed_revised_q_1000_draw_geometry_branch_expansion_recorded,
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
        model = MODEL,
        local_threshold_policy = LOCAL_THRESHOLDS,
        input_artifacts = input_rows,
        default_profile_rows = default_rows,
        default_geometry_failure_rows = geometry_failures,
        remediation_rows,
        missing_loading_publication_comparator_rows = comparator_rows,
        scenario_summary_rows,
        finding_rows = findings,
        summary = (;
            passed = true,
            n_default_profiles = length(default_rows),
            n_default_local_gate_passed =
                count(row -> row.local_gate_passed, default_rows),
            n_default_rank_passed =
                count(row -> row.local_rank_passed, default_rows),
            n_default_ess_passed =
                count(row -> row.local_ess_passed, default_rows),
            n_default_geometry_passed =
                count(row -> row.local_geometry_passed, default_rows),
            default_1000_draw_rank_replicated =
                isempty(default_rank_failures),
            default_1000_draw_geometry_clean =
                isempty(geometry_failures),
            n_default_local_failures = length(default_local_failures),
            n_default_geometry_failure_cells = length(geometry_failures),
            all_default_geometry_failures_in_well_specified_current_q =
                all(row.scenario === :well_specified_current_q
                    for row in geometry_failures),
            max_default_rhat =
                maximum(row.metrics.max_rhat for row in default_rows),
            min_default_ess =
                minimum(row.metrics.min_ess for row in default_rows),
            min_default_ebfmi =
                minimum(row.metrics.e_bfmi for row in default_rows),
            total_default_divergences =
                sum(row.metrics.n_divergences for row in default_rows),
            n_remediation_profiles = length(remediation_rows),
            n_remediation_profiles_passed =
                count(row -> row.local_gate_passed, remediation_rows),
            all_remediation_profiles_passed = all_remediation_passed,
            target_acceptance_0p9_cleared_all_geometry_failures =
                all(row -> Bool(row.local_gate_passed), target_accept_rows),
            warmup_256_cleared_all_geometry_failures =
                all(row -> Bool(row.local_gate_passed), warmup_rows),
            combined_256_0p9_cleared_all_geometry_failures =
                all(row -> Bool(row.local_gate_passed), combined_rows),
            n_missing_loading_publication_comparisons =
                length(comparator_rows),
            max_abs_missing_loading_light_vs_heavy_heldout_elpd_delta =
                maximum(abs(row.heldout_elpd_delta)
                    for row in comparator_rows),
            mean_missing_loading_light_vs_heavy_heldout_elpd_delta =
                sum(row.heldout_elpd_delta for row in comparator_rows) /
                length(comparator_rows),
            max_abs_missing_loading_light_vs_heavy_mae_delta =
                maximum(abs(row.heldout_expected_score_mae_delta)
                    for row in comparator_rows),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_mgmfrm_superiority_claim = true,
            recommendation =
                :retain_1000_draw_rank_guidance_with_geometry_remediation_branch,
            next_gate =
                :join_construct_reviewed_revised_q_budget_diagnostics_to_model_comparison_and_calibration,
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
    println("default_rank_replicated=",
        artifact.summary.default_1000_draw_rank_replicated,
        " default_geometry_clean=",
        artifact.summary.default_1000_draw_geometry_clean,
        " default_local_passed=",
        artifact.summary.n_default_local_gate_passed,
        "/", artifact.summary.n_default_profiles,
        " remediation_passed=",
        artifact.summary.n_remediation_profiles_passed,
        "/", artifact.summary.n_remediation_profiles,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
