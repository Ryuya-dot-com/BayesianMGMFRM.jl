#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_RANK_GATE_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_rank_normalized_diagnostic_gate",
        "uto_style_rank_normalized_diagnostic_gate.json")
const DEFAULT_BUDGET_EXTENSION_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_coupling_budget_extension",
        "uto_style_coupling_budget_extension.json")
const DEFAULT_REPLICATION_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_extended_budget_replication_gate",
        "uto_style_extended_budget_replication_gate.json")
const DEFAULT_WARMUP_THINNING_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_warmup_thinning_sensitivity_gate",
        "uto_style_warmup_thinning_sensitivity_gate.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_retained_draw_budget_guidance",
        "uto_style_retained_draw_budget_guidance.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_retained_draw_budget_guidance",
        "uto_style_retained_draw_budget_guidance.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_retained_draw_budget_guidance.v1"

function usage()
    return """
    Synthesize local retained-draw budget guidance from Uto-style MGMFRM gates.

    This is a no-new-MCMC guidance artifact. It reads the rank-normalized,
    retained-draw extension, independent-seed replication, and warmup/thinning
    sensitivity gates. The output records local diagnostic guidance only; it
    does not change package defaults or authorize public fit-threshold claims.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_retained_draw_budget_guidance.jl [options]

    Options:
      --rank-gate-json PATH          Rank-normalized diagnostic gate artifact.
      --budget-extension-json PATH   Retained-draw extension artifact.
      --replication-json PATH        Independent-seed replication artifact.
      --warmup-thinning-json PATH    Warmup/thinning sensitivity artifact.
      --output-json PATH             JSON artifact path.
      --output-md PATH               Markdown report path.
    """
end

function parse_args(args)
    rank_gate_json = DEFAULT_RANK_GATE_JSON
    budget_extension_json = DEFAULT_BUDGET_EXTENSION_JSON
    replication_json = DEFAULT_REPLICATION_JSON
    warmup_thinning_json = DEFAULT_WARMUP_THINNING_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--rank-gate-json"
            index < length(args) || error("--rank-gate-json requires a path")
            rank_gate_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--budget-extension-json"
            index < length(args) ||
                error("--budget-extension-json requires a path")
            budget_extension_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--replication-json"
            index < length(args) || error("--replication-json requires a path")
            replication_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--warmup-thinning-json"
            index < length(args) ||
                error("--warmup-thinning-json requires a path")
            warmup_thinning_json = abspath(args[index + 1])
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
    for path in (rank_gate_json, budget_extension_json, replication_json,
            warmup_thinning_json)
        isfile(path) || error("input artifact not found: $path")
    end
    return (; rank_gate_json, budget_extension_json, replication_json,
        warmup_thinning_json, output_json, output_md)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
read_json(path::AbstractString) = JSON3.read(read(path, String))
int_value(value) = Int(value)
round4(value) = round(Float64(value); digits = 4)

function input_artifact_rows(options)
    return [
        (artifact = :rank_normalized_diagnostic_gate,
            path = rel(options.rank_gate_json),
            sha256 = file_sha256(options.rank_gate_json)),
        (artifact = :coupling_budget_extension,
            path = rel(options.budget_extension_json),
            sha256 = file_sha256(options.budget_extension_json)),
        (artifact = :extended_budget_replication_gate,
            path = rel(options.replication_json),
            sha256 = file_sha256(options.replication_json)),
        (artifact = :warmup_thinning_sensitivity_gate,
            path = rel(options.warmup_thinning_json),
            sha256 = file_sha256(options.warmup_thinning_json)),
    ]
end

function source_gate_rows(rank_gate, extension, replication, warmup_thinning)
    return [
        (gate = :rank_normalized_draws_x4,
            warmup_per_chain = int_value(rank_gate.fit_controls.warmup_per_chain),
            draws_per_chain = int_value(rank_gate.fit_controls.draws_per_chain),
            chains = int_value(rank_gate.fit_controls.chains),
            rank_warning_rows = int_value(rank_gate.summary.n_rank_warnings),
            clearance_rows = 0,
            geometry_warning_rows =
                int_value(rank_gate.summary.n_geometry_warning_rows),
            thinning_warning_rows = missing,
            interpretation = :rank_warnings_remained_at_256_retained_draws,
            public_claim_allowed = false),
        (gate = :retained_draw_budget_extension,
            warmup_per_chain =
                int_value(extension.fit_controls.warmup_per_chain),
            draws_per_chain = int_value(extension.fit_controls.draws_per_chain),
            chains = int_value(extension.fit_controls.chains),
            rank_warning_rows = int_value(extension.summary.n_rank_warnings),
            clearance_rows =
                int_value(extension.summary.n_rank_warnings_cleared),
            geometry_warning_rows =
                int_value(extension.summary.n_geometry_warning_rows),
            thinning_warning_rows = missing,
            interpretation = :rank_warnings_cleared_at_512_retained_draws,
            public_claim_allowed = false),
        (gate = :independent_seed_replication,
            warmup_per_chain =
                int_value(replication.fit_controls.warmup_per_chain),
            draws_per_chain = int_value(replication.fit_controls.draws_per_chain),
            chains = int_value(replication.fit_controls.chains),
            rank_warning_rows = int_value(replication.summary.n_rank_warnings),
            clearance_rows =
                int_value(replication.summary.n_rank_clearance_replicated),
            geometry_warning_rows =
                int_value(replication.summary.n_geometry_warning_rows),
            thinning_warning_rows = missing,
            interpretation = :clearance_replicated_under_seed_offset,
            public_claim_allowed = false),
        (gate = :warmup_thinning_sensitivity,
            warmup_per_chain =
                int_value(warmup_thinning.fit_controls.warmup_per_chain),
            draws_per_chain =
                int_value(warmup_thinning.fit_controls.draws_per_chain),
            chains = int_value(warmup_thinning.fit_controls.chains),
            rank_warning_rows =
                int_value(warmup_thinning.summary.n_full_rank_warnings),
            clearance_rows =
                int_value(warmup_thinning.summary.n_model_rows),
            geometry_warning_rows =
                int_value(warmup_thinning.summary.n_geometry_warning_rows),
            thinning_warning_rows =
                int_value(warmup_thinning.summary.n_thinning_rank_warnings),
            interpretation =
                :warmup_doubling_preserved_clearance_thinning_reintroduced_warnings,
            public_claim_allowed = false),
    ]
end

function recommendation_rows(rank_gate, extension, replication, warmup_thinning)
    recommended_chains = int_value(replication.fit_controls.chains)
    recommended_warmup =
        int_value(replication.fit_controls.warmup_per_chain)
    recommended_draws =
        int_value(replication.fit_controls.draws_per_chain)
    warmup_sensitivity =
        int_value(warmup_thinning.fit_controls.warmup_per_chain)
    return [
        (recommendation = :local_mgmfrm_diagnostic_budget,
            status = :ready_for_documentation,
            guidance = string("For similar guarded local MGMFRM diagnostics, ",
                "use at least ", recommended_chains, " chains, ",
                recommended_warmup, " warmup draws per chain, and ",
                recommended_draws, " retained draws per chain before treating ",
                "rank warnings as substantive model evidence."),
            evidence = :rank_warning_clearance_replicated_at_512_draws,
            public_claim_allowed = false),
        (recommendation = :rank_warning_escalation_order,
            status = :ready_for_documentation,
            guidance = string("If rank-normalized R-hat, bulk ESS, or tail ESS ",
                "warns at ", int_value(rank_gate.fit_controls.draws_per_chain),
                " retained draws with no geometry warnings, first increase ",
                "retained draws to ", recommended_draws,
                " per chain and rerun diagnostics."),
            evidence = :draws_x4_warned_extension_and_replication_cleared,
            public_claim_allowed = false),
        (recommendation = :warmup_policy,
            status = :local_robustness_check,
            guidance = string("Increasing warmup to ", warmup_sensitivity,
                " per chain did not remove the 512-draw clearance, but it ",
                "improved only ",
                int_value(warmup_thinning.summary.n_warmup_improved), "/",
                int_value(warmup_thinning.summary.n_model_rows),
                " rows; treat warmup as a robustness check, not the main fix."),
            evidence = :warmup_doubling_preserved_clearance,
            public_claim_allowed = false),
        (recommendation = :thinning_policy,
            status = :ready_for_documentation,
            guidance = string("Do not use post-hoc thinning as the primary fix: ",
                int_value(warmup_thinning.summary.n_thinning_rank_warnings),
                "/", int_value(warmup_thinning.summary.n_thinning_rows),
                " thinned diagnostic rows reintroduced rank warnings."),
            evidence = :thinning_reduced_diagnostic_support,
            public_claim_allowed = false),
        (recommendation = :package_default_policy,
            status = :blocked_for_default_change,
            guidance = "Do not change package-wide defaults from this local three-cell gate alone.",
            evidence = :local_priority_cell_evidence_only,
            public_claim_allowed = false),
    ]
end

function prompt_rows(warmup_thinning)
    return [
        (prompt = :can_this_be_documented,
            answer = :yes_as_local_diagnostic_guidance,
            reason = :clearance_replicated_and_warmup_sensitivity_checked,
            public_claim_allowed = false),
        (prompt = :can_package_defaults_change_now,
            answer = :no,
            reason = :local_three_cell_gate_only,
            public_claim_allowed = false),
        (prompt = :should_thinning_be_added_as_primary_api_fix,
            answer = :no,
            reason = string(int_value(warmup_thinning.summary.n_thinning_rank_warnings),
                "/", int_value(warmup_thinning.summary.n_thinning_rows),
                " thinned rows warned"),
            public_claim_allowed = false),
        (prompt = :what_is_the_next_gate,
            answer = :surface_budget_guidance_in_user_facing_reports,
            reason = :guidance_ready_but_claims_blocked,
            public_claim_allowed = false),
    ]
end

function finding_rows(extension, replication, warmup_thinning)
    return [
        (finding = :retained_draw_budget_guidance_ready,
            severity = :info,
            evidence = string("512 retained draws cleared ",
                int_value(extension.summary.n_rank_warnings_cleared),
                "/3 and replicated ",
                int_value(replication.summary.n_rank_clearance_replicated),
                "/3"),
            implication = :document_local_diagnostic_budget_guidance,
            public_claim_allowed = false),
        (finding = :warmup_not_primary_local_blocker,
            severity = :info,
            evidence = string("256 warmup retained clearance; improved ",
                int_value(warmup_thinning.summary.n_warmup_improved),
                "/", int_value(warmup_thinning.summary.n_model_rows),
                " rows vs replication"),
            implication = :do_not_explain_clearance_as_burnin_only,
            public_claim_allowed = false),
        (finding = :thinning_not_primary_fix,
            severity = :warning,
            evidence = string(int_value(
                warmup_thinning.summary.n_thinning_rank_warnings), "/",
                int_value(warmup_thinning.summary.n_thinning_rows),
                " thinned rows warned"),
            implication = :avoid_thinning_first_guidance,
            public_claim_allowed = false),
        (finding = :default_change_blocked,
            severity = :blocker,
            evidence = :local_priority_cell_evidence_only,
            implication =
                :broaden_scenarios_before_package_default_or_public_claim,
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

function render_markdown(path, artifact)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# Uto-Style Retained-Draw Budget Guidance")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Package default change: `false`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Recommendations")
        table(io, ["Recommendation", "Status", "Guidance", "Evidence"],
            [[row.recommendation, row.status, row.guidance, row.evidence]
             for row in artifact.recommendation_rows])
        println(io, "## Decision Prompts")
        table(io, ["Prompt", "Answer", "Reason"],
            [[row.prompt, row.answer, row.reason] for row in artifact.prompt_rows])
        println(io, "## Source Gates")
        table(io, ["Gate", "Warmup", "Draws", "Chains", "Rank Warnings",
                "Clearance", "Geometry", "Thinning Warnings", "Interpretation"],
            [[row.gate, row.warmup_per_chain, row.draws_per_chain, row.chains,
                row.rank_warning_rows, row.clearance_rows,
                row.geometry_warning_rows, row.thinning_warning_rows,
                row.interpretation]
             for row in artifact.source_gate_rows])
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This artifact documents local budget guidance for the guarded ",
            "MGMFRM diagnostic workflow. It does not change package defaults, ",
            "does not add thinning to the fit API, and does not authorize ",
            "public fit-threshold, Q-revision, model-weight, or sparse-",
            "superiority claims.")
    end
    return path
end

function build_artifact(options)
    rank_gate = read_json(options.rank_gate_json)
    extension = read_json(options.budget_extension_json)
    replication = read_json(options.replication_json)
    warmup_thinning = read_json(options.warmup_thinning_json)
    source_rows =
        source_gate_rows(rank_gate, extension, replication, warmup_thinning)
    recommendations =
        recommendation_rows(rank_gate, extension, replication, warmup_thinning)
    prompts = prompt_rows(warmup_thinning)
    findings = finding_rows(extension, replication, warmup_thinning)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_retained_draw_budget_guidance,
        status = :local_budget_guidance_documented,
        generated_at = string(now(UTC)),
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        local_only = true,
        publication_or_registration_action = false,
        package_default_change = false,
        fit_api_change = false,
        sampler_level_thinning_api = false,
        public_fit_metric_claim = false,
        public_q_revision_claim = false,
        automatic_q_revision = false,
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        input_artifacts = input_artifact_rows(options),
        guidance_policy = (;
            recommended_min_chains =
                int_value(replication.fit_controls.chains),
            recommended_min_warmup_per_chain =
                int_value(replication.fit_controls.warmup_per_chain),
            recommended_min_draws_per_chain =
                int_value(replication.fit_controls.draws_per_chain),
            warmup_sensitivity_checked_at =
                int_value(warmup_thinning.fit_controls.warmup_per_chain),
            thinning_primary_fix = false,
            broader_scenario_replication_required_for_defaults = true,
            public_claim_allowed = false,
        ),
        source_gate_rows = source_rows,
        recommendation_rows = recommendations,
        prompt_rows = prompts,
        finding_rows = findings,
        summary = (;
            passed = true,
            n_source_gates = length(source_rows),
            n_recommendations = length(recommendations),
            recommended_min_chains =
                int_value(replication.fit_controls.chains),
            recommended_min_warmup_per_chain =
                int_value(replication.fit_controls.warmup_per_chain),
            recommended_min_draws_per_chain =
                int_value(replication.fit_controls.draws_per_chain),
            n_rank_warnings_at_256_draws =
                int_value(rank_gate.summary.n_rank_warnings),
            n_rank_warnings_at_512_draws =
                int_value(replication.summary.n_rank_warnings),
            n_full_rank_warnings_after_warmup_doubling =
                int_value(warmup_thinning.summary.n_full_rank_warnings),
            n_thinning_rank_warnings =
                int_value(warmup_thinning.summary.n_thinning_rank_warnings),
            package_default_change = false,
            thinning_primary_fix = false,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = :surface_budget_guidance_in_user_facing_reports,
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
    println("recommendations=", artifact.summary.n_recommendations,
        " min_draws=", artifact.summary.recommended_min_draws_per_chain,
        " thinning_primary_fix=", artifact.summary.thinning_primary_fix,
        " default_change=", artifact.summary.package_default_change,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
