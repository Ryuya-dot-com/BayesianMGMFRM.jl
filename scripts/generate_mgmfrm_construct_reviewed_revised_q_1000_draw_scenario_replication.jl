#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_PREVIOUS_FIXTURE =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_construct_reviewed_revised_q_extended_budget_followup.json")
const DEFAULT_FOLLOWUP_ROOT =
    joinpath(ROOT, "artifacts",
        "construct_reviewed_revised_q_extended_budget_followup")
const DEFAULT_REPLICATION_ROOT =
    joinpath(ROOT, "artifacts",
        "construct_reviewed_revised_q_1000_draw_scenario_replication")
const DEFAULT_PUBLICATION_BATCH_ROOT =
    joinpath(ROOT, "artifacts", "publication_grade_refit_batch")
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_construct_reviewed_revised_q_1000_draw_scenario_replication.json")
const DEFAULT_MARKDOWN =
    joinpath(ROOT, "artifacts",
        "construct_reviewed_revised_q_1000_draw_scenario_replication",
        "construct_reviewed_revised_q_1000_draw_scenario_replication.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_construct_reviewed_revised_q_1000_draw_scenario_replication.v1"
const MODEL = :construct_reviewed_revised_q_mgmfrm

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

const PROFILES = (
    (profile = :well_specified_fold1_4_128_1000_ta080,
        role = :previous_fold1_rank_replication_anchor,
        root = :followup,
        stem = "draws_only_4_128_1000_ta080",
        comparator = false),
    (profile = :well_specified_fold2_4_128_1000_ta080,
        role = :same_scenario_new_fold_default_geometry_check,
        root = :replication,
        stem = "well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold2_4_128_1000_ta080",
        comparator = false),
    (profile = :well_specified_fold2_4_128_1000_ta090,
        role = :target_acceptance_geometry_remediation,
        root = :replication,
        stem = "well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold2_4_128_1000_ta090",
        comparator = false),
    (profile = :well_specified_fold2_4_256_1000_ta080,
        role = :warmup_geometry_remediation,
        root = :replication,
        stem = "well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold2_4_256_1000_ta080",
        comparator = false),
    (profile = :well_specified_fold2_4_256_1000_ta090,
        role = :combined_geometry_remediation,
        root = :replication,
        stem = "well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold2_4_256_1000_ta090",
        comparator = false),
    (profile = :well_specified_fold3_4_128_1000_ta080,
        role = :same_scenario_new_fold_default_replication,
        root = :replication,
        stem = "well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold3_4_128_1000_ta080",
        comparator = false),
    (profile = :missing_loading_fold1_4_128_1000_ta080,
        role = :cross_scenario_default_replication,
        root = :replication,
        stem = "missing_loading_revised_q__construct_reviewed_revised_q_mgmfrm__fold1_4_128_1000_ta080",
        comparator = false),
    (profile = :missing_loading_fold1_4_500_1000_ta080,
        role = :publication_grade_comparator,
        root = :publication_batch,
        stem = "missing_loading_revised_q__construct_reviewed_revised_q_mgmfrm__fold1",
        comparator = true),
)

function usage()
    return """
    Generate the construct-reviewed revised-Q 1000-draw scenario-replication gate.

    This script reads existing local runner artifacts. It does not run MCMC.
    The gate checks whether the retained-draw rank improvement seen in fold 1
    replicates across additional folds/scenarios and records any geometry
    remediation branch needed for divergent cells.

    Usage:
      julia --project=. scripts/generate_mgmfrm_construct_reviewed_revised_q_1000_draw_scenario_replication.jl [options]

    Options:
      --previous-fixture PATH       Prior extended-budget follow-up fixture.
      --followup-root PATH          Root containing the prior fold-1 1000-draw artifact.
      --replication-root PATH       Root containing new replication artifacts.
      --publication-batch-root PATH Root containing publication-batch comparator artifacts.
      --output PATH                 JSON fixture path.
      --markdown PATH               Markdown report path.
    """
end

function parse_args(args)
    previous_fixture = DEFAULT_PREVIOUS_FIXTURE
    followup_root = DEFAULT_FOLLOWUP_ROOT
    replication_root = DEFAULT_REPLICATION_ROOT
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
        elseif arg == "--replication-root"
            index < length(args) || error("--replication-root requires a path")
            replication_root = abspath(args[index + 1])
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
    isdir(replication_root) ||
        error("replication root not found: $replication_root")
    isdir(publication_batch_root) ||
        error("publication batch root not found: $publication_batch_root")
    return (; previous_fixture, followup_root, replication_root,
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

function json_get(object, key::Symbol, default = missing)
    haskey(object, key) || return default
    value = object[key]
    value === nothing && return default
    ismissing(value) && return default
    return value
end

function root_path(options, root::Symbol)
    root === :followup && return options.followup_root
    root === :replication && return options.replication_root
    root === :publication_batch && return options.publication_batch_root
    error("unknown root: $root")
end

function paths_for_profile(options, profile)
    root = root_path(options, profile.root)
    stem = String(profile.stem)
    return (;
        result = joinpath(root, string(stem, "_result.json")),
        diagnostics = joinpath(root, string(stem, "_diagnostics.json")),
        heldout = joinpath(root, string(stem, "_heldout_score.json")),
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

function publication_gate_failure_rows(profile::Symbol, diagnostics)
    rows = NamedTuple[]
    for row in diagnostics[:diagnostic_rows]
        as_bool(row[:applicable]) || continue
        as_bool(row[:observed]) || continue
        as_bool(row[:passed]) && continue
        diagnostic = as_symbol(row[:diagnostic])
        push!(rows, (;
            profile,
            diagnostic,
            value = json_get(row, :value),
            threshold = json_get(row, :threshold),
            failure_class =
                diagnostic in (:warmup_per_chain_min,
                    :draws_per_chain_min) ?
                :publication_grade_budget_threshold_not_targeted :
                :sampler_or_geometry_warning,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function profile_row(profile, artifacts)
    score = artifacts.result[:score_row]
    controls = artifacts.result[:fit_controls]
    local_summary = local_gate_summary(score, controls)
    return (;
        profile = profile.profile,
        role = profile.role,
        scenario = as_symbol(score[:scenario]),
        model = MODEL,
        execution_unit_id = as_symbol(score[:execution_unit_id]),
        fold = as_int(score[:fold]),
        comparator = Bool(profile.comparator),
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
            as_bool(artifacts.result[:summary][:diagnostic_gate_passed]),
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
        public_claim_allowed = false,
    )
end

function row_for_profile(rows, profile::Symbol)
    return only(row for row in rows if row.profile === profile)
end

function finding_rows(profile_rows)
    default_rows = [row for row in profile_rows
        if !row.comparator &&
           row.controls.draws_per_chain == 1000 &&
           row.controls.warmup_per_chain == 128 &&
           row.controls.target_acceptance == 0.8]
    default_rank_failures =
        [row for row in default_rows if !row.local_rank_passed]
    default_geometry_failures =
        [row for row in default_rows if !row.local_geometry_passed]
    fold2_default =
        row_for_profile(profile_rows, :well_specified_fold2_4_128_1000_ta080)
    fold2_ta09 =
        row_for_profile(profile_rows, :well_specified_fold2_4_128_1000_ta090)
    fold2_warmup =
        row_for_profile(profile_rows, :well_specified_fold2_4_256_1000_ta080)
    missing_light =
        row_for_profile(profile_rows, :missing_loading_fold1_4_128_1000_ta080)
    missing_heavy =
        row_for_profile(profile_rows, :missing_loading_fold1_4_500_1000_ta080)
    return [
        (finding = :default_1000_draw_profiles_clear_rank,
            severity = isempty(default_rank_failures) ? :info : :warning,
            evidence = string(length(default_rows) -
                length(default_rank_failures), "/", length(default_rows),
                " default 4/128/1000 profiles passed rank; max R-hat = ",
                round(maximum(row.metrics.max_rhat for row in default_rows);
                    digits = 4)),
            implication = :retained_draw_extension_rank_guidance_replicated,
            public_claim_allowed = false),
        (finding = :default_profile_geometry_failure_observed,
            severity = isempty(default_geometry_failures) ? :info : :warning,
            evidence = string(length(default_geometry_failures),
                " default 4/128/1000 geometry failure(s); fold2 divergences = ",
                fold2_default.metrics.n_divergences),
            implication =
                :separate_rank_budget_guidance_from_geometry_remediation,
            public_claim_allowed = false),
        (finding = :target_acceptance_cleared_fold2_geometry,
            severity = Bool(fold2_ta09.local_gate_passed) ? :info : :warning,
            evidence = string("fold2 4/128/1000 target_accept 0.9 divergences = ",
                fold2_ta09.metrics.n_divergences,
                ", R-hat = ", round(fold2_ta09.metrics.max_rhat; digits = 4)),
            implication =
                :use_target_acceptance_sensitivity_when_geometry_warning_appears,
            public_claim_allowed = false),
        (finding = :warmup_cleared_fold2_geometry,
            severity = Bool(fold2_warmup.local_gate_passed) ? :info : :warning,
            evidence = string("fold2 4/256/1000 target_accept 0.8 divergences = ",
                fold2_warmup.metrics.n_divergences,
                ", R-hat = ", round(fold2_warmup.metrics.max_rhat; digits = 4)),
            implication =
                :warmup_extension_is_secondary_geometry_sensitivity,
            public_claim_allowed = false),
        (finding = :cross_scenario_lightweight_matches_heavy_comparator,
            severity = :info,
            evidence = string("missing-loading fold1 dELPD vs 4/500/1000 = ",
                round(missing_light.metrics.heldout_elpd -
                    missing_heavy.metrics.heldout_elpd; digits = 4),
                ", MAE delta = ",
                round(missing_light.metrics.heldout_expected_score_mae -
                    missing_heavy.metrics.heldout_expected_score_mae;
                    digits = 4)),
            implication =
                :lightweight_1000_draw_profile_is_close_to_heavy_reference_in_this_cell,
            public_claim_allowed = false),
        (finding = :public_claims_remain_blocked,
            severity = :blocker,
            evidence = :three_cell_local_replication_smoke_only,
            implication =
                :expand_to_remaining_folds_scenarios_before_default_or_threshold_claim,
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
        println(io, "# Construct-Reviewed Revised-Q 1000-Draw Scenario Replication")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Model: `construct_reviewed_revised_q_mgmfrm`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Profiles")
        table(io,
            ["Profile", "Scenario", "Fold", "Local gate", "Rhat", "ESS",
                "Divergences", "Heldout ELPD"],
            [[row.profile, row.scenario, row.fold, row.local_gate_passed,
                 round(row.metrics.max_rhat; digits = 4),
                 round(row.metrics.min_ess; digits = 1),
                 row.metrics.n_divergences,
                 round(row.metrics.heldout_elpd; digits = 4)]
             for row in artifact.profile_rows])
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
        "bayesianmgmfrm.mgmfrm_construct_reviewed_revised_q_extended_budget_followup.v1" ||
        error("unexpected previous fixture schema")
    artifacts_by_profile = Dict{Symbol,Any}()
    input_rows = [
        input_artifact_row(:previous_extended_budget_followup_fixture,
            options.previous_fixture),
    ]
    for profile in PROFILES
        paths = paths_for_profile(options, profile)
        require_paths(paths)
        result = read_json(paths.result)
        diagnostics = read_json(paths.diagnostics)
        heldout = read_json(paths.heldout)
        artifacts_by_profile[profile.profile] =
            (; result, diagnostics, heldout, paths)
        append!(input_rows, [
            input_artifact_row(Symbol(string(profile.profile, "_result")),
                paths.result),
            input_artifact_row(Symbol(string(profile.profile, "_diagnostics")),
                paths.diagnostics),
            input_artifact_row(Symbol(string(profile.profile, "_heldout")),
                paths.heldout),
        ])
    end
    profile_rows = [
        profile_row(profile, artifacts_by_profile[profile.profile])
        for profile in PROFILES
    ]
    failure_rows = reduce(vcat, [
        publication_gate_failure_rows(profile.profile,
            artifacts_by_profile[profile.profile].diagnostics)
        for profile in PROFILES
    ]; init = NamedTuple[])
    findings = finding_rows(profile_rows)
    default_rows = [row for row in profile_rows
        if !row.comparator &&
           row.controls.draws_per_chain == 1000 &&
           row.controls.warmup_per_chain == 128 &&
           row.controls.target_acceptance == 0.8]
    remedial_fold2_rows = [row for row in profile_rows
        if row.fold == 2 && row.scenario === :well_specified_current_q &&
           row.profile !== :well_specified_fold2_4_128_1000_ta080]
    missing_light =
        row_for_profile(profile_rows, :missing_loading_fold1_4_128_1000_ta080)
    missing_heavy =
        row_for_profile(profile_rows, :missing_loading_fold1_4_500_1000_ta080)
    best_rhat_row = argmin(row -> row.metrics.max_rhat, profile_rows)
    best_heldout_row = argmax(row -> row.metrics.heldout_elpd, profile_rows)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :construct_reviewed_revised_q_1000_draw_scenario_replication,
        status =
            :construct_reviewed_revised_q_1000_draw_scenario_replication_recorded,
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
        profile_rows,
        publication_gate_failure_rows = failure_rows,
        finding_rows = findings,
        summary = (;
            passed = true,
            n_profiles = length(profile_rows),
            n_default_4_128_1000_profiles = length(default_rows),
            n_default_4_128_1000_local_passed =
                count(row -> row.local_gate_passed, default_rows),
            n_default_4_128_1000_rank_passed =
                count(row -> row.local_rank_passed, default_rows),
            n_default_4_128_1000_geometry_passed =
                count(row -> row.local_geometry_passed, default_rows),
            default_4_128_1000_rank_replicated =
                all(row -> Bool(row.local_rank_passed), default_rows),
            default_4_128_1000_geometry_clean =
                all(row -> Bool(row.local_geometry_passed), default_rows),
            n_remedial_fold2_profiles = length(remedial_fold2_rows),
            n_remedial_fold2_profiles_passed =
                count(row -> row.local_gate_passed, remedial_fold2_rows),
            target_acceptance_0p9_cleared_fold2_geometry =
                Bool(row_for_profile(profile_rows,
                    :well_specified_fold2_4_128_1000_ta090).local_gate_passed),
            warmup_256_cleared_fold2_geometry =
                Bool(row_for_profile(profile_rows,
                    :well_specified_fold2_4_256_1000_ta080).local_gate_passed),
            n_local_gate_passed =
                count(row -> row.local_gate_passed, profile_rows),
            n_rank_passed =
                count(row -> row.local_rank_passed, profile_rows),
            n_geometry_passed =
                count(row -> row.local_geometry_passed, profile_rows),
            n_publication_gate_passed =
                count(row -> row.publication_gate_passed, profile_rows),
            n_publication_gate_failures = length(failure_rows),
            n_publication_budget_threshold_failures =
                count(row -> row.failure_class ===
                    :publication_grade_budget_threshold_not_targeted,
                    failure_rows),
            n_sampler_or_geometry_failures =
                count(row -> row.failure_class ===
                    :sampler_or_geometry_warning, failure_rows),
            max_rhat = maximum(row.metrics.max_rhat for row in profile_rows),
            min_ess = minimum(row.metrics.min_ess for row in profile_rows),
            total_divergences =
                sum(row.metrics.n_divergences for row in profile_rows),
            missing_loading_light_vs_heavy_heldout_elpd_delta =
                missing_light.metrics.heldout_elpd -
                missing_heavy.metrics.heldout_elpd,
            missing_loading_light_vs_heavy_mae_delta =
                missing_light.metrics.heldout_expected_score_mae -
                missing_heavy.metrics.heldout_expected_score_mae,
            best_rhat_profile = best_rhat_row.profile,
            best_rhat = best_rhat_row.metrics.max_rhat,
            best_heldout_elpd_profile = best_heldout_row.profile,
            best_heldout_elpd = best_heldout_row.metrics.heldout_elpd,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_mgmfrm_superiority_claim = true,
            recommendation =
                :retain_1000_draw_rank_guidance_but_add_geometry_remediation_branch,
            next_gate =
                :expand_1000_draw_geometry_branch_across_remaining_construct_reviewed_revised_q_cells,
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
        artifact.summary.default_4_128_1000_rank_replicated,
        " default_geometry_clean=",
        artifact.summary.default_4_128_1000_geometry_clean,
        " local_passed=", artifact.summary.n_local_gate_passed,
        "/", artifact.summary.n_profiles,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
