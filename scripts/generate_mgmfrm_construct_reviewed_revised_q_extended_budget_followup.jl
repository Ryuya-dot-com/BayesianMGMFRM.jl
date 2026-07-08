#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_RECOMMENDED_GATE =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_recommended_budget_empirical_gate.json")
const DEFAULT_RECOMMENDED_ROOT =
    joinpath(ROOT, "artifacts", "recommended_budget_empirical_gate")
const DEFAULT_FOLLOWUP_ROOT =
    joinpath(ROOT, "artifacts",
        "construct_reviewed_revised_q_extended_budget_followup")
const DEFAULT_PUBLICATION_ROOT =
    joinpath(ROOT, "artifacts", "publication_grade_refit_pilot")
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_construct_reviewed_revised_q_extended_budget_followup.json")
const DEFAULT_MARKDOWN =
    joinpath(ROOT, "artifacts",
        "construct_reviewed_revised_q_extended_budget_followup",
        "construct_reviewed_revised_q_extended_budget_followup.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_construct_reviewed_revised_q_extended_budget_followup.v1"
const EXECUTION_UNIT_ID =
    "well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold1"
const MODEL = :construct_reviewed_revised_q_mgmfrm

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

const PROFILES = (
    (profile = :recommended_4_128_512_ta080,
        role = :baseline_recommended_budget,
        root = :recommended,
        stem = EXECUTION_UNIT_ID),
    (profile = :draws_only_4_128_1000_ta080,
        role = :retained_draw_extension_only,
        root = :followup,
        stem = "draws_only_4_128_1000_ta080"),
    (profile = :warmup_only_4_256_512_ta080,
        role = :warmup_extension_only,
        root = :followup,
        stem = "warmup_only_4_256_512_ta080"),
    (profile = :warmup_draws_4_256_1000_ta080,
        role = :warmup_and_retained_draw_extension,
        root = :followup,
        stem = "warmup_draws_4_256_1000_ta080"),
    (profile = :warmup_draws_4_256_1000_ta090,
        role = :target_acceptance_sensitivity,
        root = :followup,
        stem = "warmup_draws_4_256_1000_ta090"),
    (profile = :publication_4_500_1000_ta080,
        role = :publication_grade_comparator,
        root = :publication,
        stem = EXECUTION_UNIT_ID),
)

function usage()
    return """
    Generate the construct-reviewed revised-Q extended-budget follow-up.

    This script reads local runner artifacts for the fold-1
    construct-reviewed revised-Q MGMFRM job. It compares the failing
    4/128/512 recommended-budget profile with draws-only, warmup-only,
    warmup+draws, target-acceptance, and publication-grade comparator profiles.
    It does not run MCMC.

    Usage:
      julia --project=. scripts/generate_mgmfrm_construct_reviewed_revised_q_extended_budget_followup.jl [options]

    Options:
      --recommended-gate PATH     Recommended-budget empirical gate fixture.
      --recommended-root PATH     Root containing baseline 4/128/512 artifacts.
      --followup-root PATH        Root containing extended-budget artifacts.
      --publication-root PATH     Root containing publication comparator artifacts.
      --output PATH               JSON fixture path.
      --markdown PATH             Markdown report path.
    """
end

function parse_args(args)
    recommended_gate = DEFAULT_RECOMMENDED_GATE
    recommended_root = DEFAULT_RECOMMENDED_ROOT
    followup_root = DEFAULT_FOLLOWUP_ROOT
    publication_root = DEFAULT_PUBLICATION_ROOT
    output = DEFAULT_OUTPUT
    markdown = DEFAULT_MARKDOWN
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--recommended-gate"
            index < length(args) || error("--recommended-gate requires a path")
            recommended_gate = abspath(args[index + 1])
            index += 2
        elseif arg == "--recommended-root"
            index < length(args) || error("--recommended-root requires a path")
            recommended_root = abspath(args[index + 1])
            index += 2
        elseif arg == "--followup-root"
            index < length(args) || error("--followup-root requires a path")
            followup_root = abspath(args[index + 1])
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
    isfile(recommended_gate) ||
        error("recommended gate fixture not found: $recommended_gate")
    isdir(recommended_root) ||
        error("recommended artifact root not found: $recommended_root")
    isdir(followup_root) ||
        error("follow-up artifact root not found: $followup_root")
    isdir(publication_root) ||
        error("publication artifact root not found: $publication_root")
    return (; recommended_gate, recommended_root, followup_root,
        publication_root, output, markdown)
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
    root === :recommended && return options.recommended_root
    root === :followup && return options.followup_root
    root === :publication && return options.publication_root
    error("unknown artifact root: $root")
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
                :sampler_or_rank_warning,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function profile_row(profile, artifacts, baseline_score, publication_score)
    score = artifacts.result[:score_row]
    controls = artifacts.result[:fit_controls]
    local_summary = local_gate_summary(score, controls)
    heldout_elpd = as_float(score[:heldout_elpd])
    heldout_mae = as_float(score[:heldout_expected_score_mae])
    return (;
        profile = profile.profile,
        role = profile.role,
        model = MODEL,
        execution_unit_id = EXECUTION_UNIT_ID,
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
            heldout_elpd,
            heldout_mean_log_predictive_density =
                as_float(score[:heldout_mean_log_predictive_density]),
            heldout_expected_score_mae = heldout_mae,
            heldout_expected_score_rmse =
                as_float(score[:heldout_expected_score_rmse]),
        ),
        deltas = (;
            max_rhat_vs_baseline =
                local_summary.max_rhat - as_float(baseline_score[:max_rhat]),
            min_ess_vs_baseline =
                local_summary.min_ess - as_float(baseline_score[:min_ess]),
            heldout_elpd_vs_baseline =
                heldout_elpd - as_float(baseline_score[:heldout_elpd]),
            heldout_expected_score_mae_vs_baseline =
                heldout_mae -
                as_float(baseline_score[:heldout_expected_score_mae]),
            heldout_elpd_vs_publication =
                heldout_elpd - as_float(publication_score[:heldout_elpd]),
            heldout_expected_score_mae_vs_publication =
                heldout_mae -
                as_float(publication_score[:heldout_expected_score_mae]),
        ),
        public_claim_allowed = false,
    )
end

function row_for_profile(rows, profile::Symbol)
    return only(row for row in rows if row.profile === profile)
end

function finding_rows(profile_rows, failure_rows)
    baseline =
        row_for_profile(profile_rows, :recommended_4_128_512_ta080)
    draws_only =
        row_for_profile(profile_rows, :draws_only_4_128_1000_ta080)
    warmup_only =
        row_for_profile(profile_rows, :warmup_only_4_256_512_ta080)
    warmup_draws =
        row_for_profile(profile_rows, :warmup_draws_4_256_1000_ta080)
    target_accept =
        row_for_profile(profile_rows, :warmup_draws_4_256_1000_ta090)
    rank_failures = [row for row in failure_rows
        if row.failure_class === :sampler_or_rank_warning]
    followup_rank_failures = [row for row in rank_failures
        if row.profile !== :recommended_4_128_512_ta080]
    return [
        (finding = :baseline_recommended_budget_borderline,
            severity = :warning,
            evidence = string("4/128/512 R-hat = ",
                round(baseline.metrics.max_rhat; digits = 4)),
            implication =
                :do_not_broaden_recommended_budget_without_targeted_followup,
            public_claim_allowed = false),
        (finding = :retained_draw_extension_cleared_warning,
            severity = Bool(draws_only.local_gate_passed) ? :info : :warning,
            evidence = string("4/128/1000 R-hat = ",
                round(draws_only.metrics.max_rhat; digits = 4),
                ", ESS = ", round(draws_only.metrics.min_ess; digits = 1)),
            implication =
                :retained_draw_extension_is_sufficient_in_this_cell,
            public_claim_allowed = false),
        (finding = :warmup_extension_also_cleared_warning,
            severity = Bool(warmup_only.local_gate_passed) ? :info : :warning,
            evidence = string("4/256/512 R-hat = ",
                round(warmup_only.metrics.max_rhat; digits = 4),
                ", ESS = ", round(warmup_only.metrics.min_ess; digits = 1)),
            implication =
                :warmup_can_be_secondary_sensitivity_not_primary_default,
            public_claim_allowed = false),
        (finding = :target_acceptance_not_required_for_clearance,
            severity = :info,
            evidence = Bool(warmup_draws.local_gate_passed) &&
                Bool(target_accept.local_gate_passed) ?
                "4/256/1000 passed at target_accept 0.8 and 0.9" :
                "target_accept sensitivity did not establish a clean clearance",
            implication =
                :do_not_add_target_acceptance_as_first_line_guidance,
            public_claim_allowed = false),
        (finding = :publication_grade_comparator_remains_clean,
            severity = :info,
            evidence = isempty(followup_rank_failures) ?
                "no sampler/rank failures after the extended follow-up profiles" :
                string(length(followup_rank_failures),
                    " follow-up sampler/rank publication-gate failure(s) remain"),
            implication =
                :use_publication_grade_budget_as_heavy_reference_not_default,
            public_claim_allowed = false),
        (finding = :public_claims_remain_blocked,
            severity = :blocker,
            evidence =
                :single_model_single_fold_local_followup_only,
            implication =
                :replicate_across_scenarios_folds_and_external_construct_evidence,
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
        println(io, "# Construct-Reviewed Revised-Q Extended-Budget Follow-Up")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Model: `construct_reviewed_revised_q_mgmfrm`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Profiles")
        table(io,
            ["Profile", "Gate", "Rhat", "ESS", "Divergences",
                "Heldout ELPD", "Delta ELPD vs publication"],
            [[row.profile, row.local_gate_passed,
                 round(row.metrics.max_rhat; digits = 4),
                 round(row.metrics.min_ess; digits = 1),
                 row.metrics.n_divergences,
                 round(row.metrics.heldout_elpd; digits = 4),
                 round(row.deltas.heldout_elpd_vs_publication; digits = 4)]
             for row in artifact.profile_rows])
        println(io, "## Publication-Gate Failures")
        table(io, ["Profile", "Diagnostic", "Value", "Threshold", "Class"],
            [[row.profile, row.diagnostic, row.value, row.threshold,
                 row.failure_class]
             for row in artifact.publication_gate_failure_rows])
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
    end
    return path
end

function build_artifact(options)
    gate = read_json(options.recommended_gate)
    as_string(gate[:schema]) ==
        "bayesianmgmfrm.mgmfrm_recommended_budget_empirical_gate.v1" ||
        error("unexpected recommended gate schema")
    artifacts_by_profile = Dict{Symbol,Any}()
    input_rows = [
        input_artifact_row(:recommended_budget_empirical_gate,
            options.recommended_gate),
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
    baseline_score =
        artifacts_by_profile[:recommended_4_128_512_ta080].result[:score_row]
    publication_score =
        artifacts_by_profile[:publication_4_500_1000_ta080].result[:score_row]
    profile_rows = [
        profile_row(profile, artifacts_by_profile[profile.profile],
            baseline_score, publication_score)
        for profile in PROFILES
    ]
    failure_rows = reduce(vcat, [
        publication_gate_failure_rows(profile.profile,
            artifacts_by_profile[profile.profile].diagnostics)
        for profile in PROFILES
    ]; init = NamedTuple[])
    findings = finding_rows(profile_rows, failure_rows)

    baseline =
        row_for_profile(profile_rows, :recommended_4_128_512_ta080)
    draws_only =
        row_for_profile(profile_rows, :draws_only_4_128_1000_ta080)
    warmup_only =
        row_for_profile(profile_rows, :warmup_only_4_256_512_ta080)
    warmup_draws =
        row_for_profile(profile_rows, :warmup_draws_4_256_1000_ta080)
    target_accept =
        row_for_profile(profile_rows, :warmup_draws_4_256_1000_ta090)
    publication =
        row_for_profile(profile_rows, :publication_4_500_1000_ta080)
    followups = [row for row in profile_rows
        if row.role !== :baseline_recommended_budget &&
           row.role !== :publication_grade_comparator]
    n_followup_passed = count(row -> row.local_gate_passed, followups)
    best_rhat_row = argmin(row -> row.metrics.max_rhat, profile_rows)
    best_heldout_row = argmax(row -> row.metrics.heldout_elpd, profile_rows)
    max_abs_publication_elpd_delta =
        maximum(abs(row.deltas.heldout_elpd_vs_publication)
            for row in profile_rows)
    n_publication_budget_failures =
        count(row -> row.failure_class ===
            :publication_grade_budget_threshold_not_targeted, failure_rows)
    n_sampler_or_rank_failures =
        count(row -> row.failure_class === :sampler_or_rank_warning,
            failure_rows)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :construct_reviewed_revised_q_extended_budget_followup,
        status =
            :construct_reviewed_revised_q_extended_budget_followup_recorded,
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
        execution_unit_id = EXECUTION_UNIT_ID,
        local_threshold_policy = LOCAL_THRESHOLDS,
        input_artifacts = input_rows,
        profile_rows,
        publication_gate_failure_rows = failure_rows,
        finding_rows = findings,
        summary = (;
            passed = true,
            baseline_recommended_budget_passed =
                Bool(baseline.local_gate_passed),
            baseline_rank_passed = Bool(baseline.local_rank_passed),
            baseline_max_rhat = baseline.metrics.max_rhat,
            n_followup_profiles = length(followups),
            n_followup_profiles_passed = n_followup_passed,
            all_followup_profiles_passed =
                n_followup_passed == length(followups),
            draws_only_cleared = Bool(draws_only.local_gate_passed),
            warmup_only_cleared = Bool(warmup_only.local_gate_passed),
            warmup_draws_cleared = Bool(warmup_draws.local_gate_passed),
            target_acceptance_0p9_cleared =
                Bool(target_accept.local_gate_passed),
            target_acceptance_0p9_required = false,
            retained_draw_extension_sufficient =
                Bool(draws_only.local_gate_passed),
            warmup_extension_also_sufficient =
                Bool(warmup_only.local_gate_passed),
            publication_comparator_passed =
                Bool(publication.local_gate_passed) &&
                Bool(publication.publication_gate_passed),
            n_profiles = length(profile_rows),
            n_local_gate_passed =
                count(row -> row.local_gate_passed, profile_rows),
            n_geometry_passed =
                count(row -> row.local_geometry_passed, profile_rows),
            n_publication_gate_failures = length(failure_rows),
            n_publication_budget_threshold_failures =
                n_publication_budget_failures,
            n_sampler_or_rank_failures,
            best_rhat_profile = best_rhat_row.profile,
            best_rhat = best_rhat_row.metrics.max_rhat,
            best_heldout_elpd_profile = best_heldout_row.profile,
            best_heldout_elpd = best_heldout_row.metrics.heldout_elpd,
            max_abs_heldout_elpd_delta_vs_publication =
                max_abs_publication_elpd_delta,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_mgmfrm_superiority_claim = true,
            recommendation =
                :use_retained_draw_extension_for_construct_reviewed_revised_q_replication,
            next_gate =
                :construct_reviewed_revised_q_1000_draw_scenario_replication,
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
    println("baseline_passed=",
        artifact.summary.baseline_recommended_budget_passed,
        " followup_passed=", artifact.summary.n_followup_profiles_passed,
        "/", artifact.summary.n_followup_profiles,
        " draws_only_cleared=", artifact.summary.draws_only_cleared,
        " warmup_only_cleared=", artifact.summary.warmup_only_cleared,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
