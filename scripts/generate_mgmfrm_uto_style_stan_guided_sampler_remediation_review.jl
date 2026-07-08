#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_WARNING_SURFACE_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_sampler_warning_surface_diagnosis",
        "uto_style_sampler_warning_surface_diagnosis.json")
const DEFAULT_DRAWS_X4_JSON =
    joinpath(ROOT, "artifacts", "uto_style_draws_x4_gate_followup",
        "uto_style_draws_x4_gate_followup.json")
const DEFAULT_CHAIN_JSON =
    joinpath(ROOT, "artifacts", "uto_style_chain_count_gate_followup",
        "uto_style_chain_count_gate_followup.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_stan_guided_sampler_remediation_review",
        "uto_style_stan_guided_sampler_remediation_review.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_stan_guided_sampler_remediation_review",
        "uto_style_stan_guided_sampler_remediation_review.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_stan_guided_sampler_remediation_review.v1"

function usage()
    return """
    Review local MGMFRM sampler-remediation results against Stan guidance.

    This artifact records how the local warning surface should be interpreted
    in light of Stan diagnostics, Stan posterior R-hat/ESS guidance, and Stan
    community discussions about thinning and reparameterization. It does not
    rerun MCMC and does not authorize public threshold or Q-revision claims.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_stan_guided_sampler_remediation_review.jl [options]

    Options:
      --warning-surface-json PATH  Warning-surface artifact.
      --draws-x4-json PATH         Draws-x4 gate artifact.
      --chain-json PATH            Chain-count gate artifact.
      --output-json PATH           JSON artifact path.
      --output-md PATH             Markdown report path.
    """
end

function parse_args(args)
    warning_surface_json = DEFAULT_WARNING_SURFACE_JSON
    draws_x4_json = DEFAULT_DRAWS_X4_JSON
    chain_json = DEFAULT_CHAIN_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--warning-surface-json"
            index < length(args) ||
                error("--warning-surface-json requires a path")
            warning_surface_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--draws-x4-json"
            index < length(args) || error("--draws-x4-json requires a path")
            draws_x4_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--chain-json"
            index < length(args) || error("--chain-json requires a path")
            chain_json = abspath(args[index + 1])
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

    isfile(warning_surface_json) ||
        error("warning-surface artifact not found: $warning_surface_json")
    isfile(draws_x4_json) || error("draws-x4 artifact not found: $draws_x4_json")
    isfile(chain_json) || error("chain-count artifact not found: $chain_json")
    return (; warning_surface_json, draws_x4_json, chain_json, output_json,
        output_md)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
read_json(path::AbstractString) = JSON3.read(read(path, String))
symbol_value(value) = Symbol(string(value))
int_value(value) = Int(value)
round4(value) = round(Float64(value); digits = 4)

function finite_float(value)
    ismissing(value) && return missing
    float = Float64(value)
    return isfinite(float) ? float : missing
end

function minimum_or_missing(values)
    finite = Float64[]
    for value in values
        float = finite_float(value)
        ismissing(float) || push!(finite, float)
    end
    isempty(finite) && return missing
    return minimum(finite)
end

function maximum_or_missing(values)
    finite = Float64[]
    for value in values
        float = finite_float(value)
        ismissing(float) || push!(finite, float)
    end
    isempty(finite) && return missing
    return maximum(finite)
end

round_or_missing(value) =
    ismissing(finite_float(value)) ? missing : round4(finite_float(value))

function source_rows()
    return [
        (source = :stan_diagnostics_warnings,
            title = "How to Diagnose and Resolve Convergence Problems",
            url = "https://mc-stan.org/learn-stan/diagnostics-warnings.html",
            guidance =
                :high_rhat_and_low_ess_are_validity_warnings_divergence_and_geometry_checked_separately,
            local_use = :classify_current_warning_as_rhat_ess_not_geometry,
            public_claim_allowed = false),
        (source = :stan_posterior_ess_bulk,
            title = "posterior::ess_bulk",
            url = "https://mc-stan.org/posterior/reference/ess_bulk.html",
            guidance =
                :bulk_ess_is_rank_normalized_split_chain_diagnostic_with_tail_ess_companion,
            local_use = :add_rank_normalized_bulk_tail_ess_before_public_gate,
            public_claim_allowed = false),
        (source = :stan_efficiency_tuning,
            title = "Stan User's Guide: Efficiency Tuning",
            url = "https://mc-stan.org/docs/stan-users-guide/efficiency-tuning.html",
            guidance =
                :reparameterization_can_improve_effective_sample_size_for_difficult_hierarchical_geometry,
            local_use = :audit_person_item_discrimination_and_step_blocks,
            public_claim_allowed = false),
        (source = :stan_thinning_discourse,
            title = "Thining and diagnostics",
            url = "https://discourse.mc-stan.org/t/thining-and-diagnostics/11185",
            guidance =
                :diagnose_non_thinned_chains_then_thin_only_for_storage_or_quantity_specific_mcse,
            local_use = :do_not_treat_thinning_as_primary_remediation,
            public_claim_allowed = false),
        (source = :stan_ess_reporting_discourse,
            title = "Reporting effective sample sizes in manuscripts",
            url = "https://discourse.mc-stan.org/t/reporting-effective-sample-sizes-in-manuscripts-include-log-posterior/6975",
            guidance =
                :report_effective_sample_size_or_mcse_for_quantities_of_interest_after_convergence,
            local_use = :add_mcse_or_quantity_specific_ess_before_claims,
            public_claim_allowed = false),
        (source = :stan_new_rhat_ess_discourse,
            title = "New R-hat and ESS",
            url = "https://discourse.mc-stan.org/t/new-r-hat-and-ess/8165",
            guidance =
                :use_rank_normalized_rhat_and_separate_bulk_tail_ess,
            local_use = :current_classical_rhat_ess_is_provisional,
            public_claim_allowed = false),
    ]
end

function local_evidence_rows(warning_surface, draws_x4, chain)
    return [
        (evidence = :warning_surface,
            finding = :warnings_are_rhat_ess_not_sampler_geometry,
            value = string(
                warning_surface.summary.n_raw_rhat_ess_warning_rows,
                " raw R-hat/ESS warning rows; ",
                warning_surface.summary.n_sampler_geometry_warning_rows,
                " sampler-geometry warning rows"),
            implication = :geometry_controls_are_not_primary,
            public_claim_allowed = false),
        (evidence = :draws_x4_gate,
            finding = :retained_draws_improve_but_do_not_clear,
            value = string(draws_x4.summary.n_min_ess_improved_vs_x2,
                "/", draws_x4.summary.n_jobs,
                " improved ESS; ",
                draws_x4.summary.n_warnings_cleared,
                "/", draws_x4.summary.n_jobs, " cleared warnings"),
            implication = :draws_help_but_public_gate_not_met,
            public_claim_allowed = false),
        (evidence = :chain_count_gate,
            finding = :chain_count_did_not_improve_over_draws_x4,
            value = string(chain.summary.n_max_rhat_improved_vs_x4,
                "/", chain.summary.n_jobs, " improved R-hat; ",
                chain.summary.n_min_ess_improved_vs_x4,
                "/", chain.summary.n_jobs, " improved ESS"),
            implication = :parameterization_and_rank_diagnostics_next,
            public_claim_allowed = false),
    ]
end

function parameterization_audit_rows(warning_surface)
    raw = [row for row in warning_surface.block_diagnostic_rows
        if symbol_value(row.parameter_space) === :raw_unconstrained]
    blocks = sort(unique(symbol_value(row.block) for row in raw); by = string)
    rows = NamedTuple[]
    for block in blocks
        group = [row for row in raw if symbol_value(row.block) === block]
        total_low = sum(int_value(row.n_low_ess) for row in group)
        total_bad = sum(int_value(row.n_bad_rhat) for row in group)
        push!(rows, (;
            block,
            n_rows = length(group),
            max_rhat = round_or_missing(maximum_or_missing(
                row.max_rhat for row in group)),
            min_ess = round_or_missing(minimum_or_missing(
                row.min_ess for row in group)),
            total_bad_rhat = total_bad,
            total_low_ess = total_low,
            audit_target = block in (:person,) ?
                :noncentered_or_identification_review :
                block in (:item, :item_steps) ?
                :anchor_category_and_step_scale_review :
                block in (:log_item_dimension_discrimination,
                    :log_item_discrimination_free) ?
                :positive_scale_transform_and_q_anchor_review :
                block in (:log_rater_consistency,
                    :log_rater_consistency_free) ?
                :positive_rater_consistency_transform_review :
                :constraint_and_scale_review,
            public_claim_allowed = false,
        ))
    end
    return sort(rows; by = row -> (-(row.total_low_ess + 2 * row.total_bad_rhat),
        string(row.block)))
end

function decision_rows()
    return [
        (decision = :do_not_use_thinning_as_primary_fix,
            rationale =
                :stan_discourse_treats_thinning_mainly_as_storage_or_post_diagnostic_step,
            local_action = :keep_non_thinned_diagnostics_for_gates,
            public_claim_allowed = false),
        (decision = :add_rank_normalized_diagnostics,
            rationale =
                :stan_posterior_and_forums_recommend_rank_normalized_rhat_bulk_tail_ess,
            local_action =
                :implement_rank_normalized_rhat_bulk_ess_tail_ess_or_export_compatible_draw_arrays,
            public_claim_allowed = false),
        (decision = :run_parameterization_audit,
            rationale =
                :draws_helped_but_chain_count_did_not_surpass_draws_x4,
            local_action =
                :review_person_item_discrimination_and_step_parameter_blocks,
            public_claim_allowed = false),
        (decision = :keep_claims_blocked,
            rationale = :all_priority_followups_still_have_mcmc_warning,
            local_action =
                :no_public_threshold_model_weight_or_q_revision_wording,
            public_claim_allowed = false),
    ]
end

function finding_rows(warning_surface, draws_x4, chain)
    return [
        (finding = :stan_guided_review_recorded,
            severity = :info,
            evidence = "Stan diagnostics, posterior ESS, and Stan Discourse reviewed",
            implication = :local_gate_aligned_to_external_mcmc_practice,
            public_claim_allowed = false),
        (finding = :geometry_not_primary,
            severity = :info,
            evidence = string(
                warning_surface.summary.n_sampler_geometry_warning_rows,
                " geometry warning row(s); ",
                warning_surface.summary.n_direct_transform_warning_rows,
                " direct-transform warning row(s)"),
            implication = :adapt_delta_treedepth_not_first_line_here,
            public_claim_allowed = false),
        (finding = :draws_helped_chain_count_did_not,
            severity = :warning,
            evidence = string("draws_x4 ESS/R-hat improved in ",
                draws_x4.summary.n_jobs, "/", draws_x4.summary.n_jobs,
                " jobs; chain-count improved R-hat in ",
                chain.summary.n_max_rhat_improved_vs_x4, "/",
                chain.summary.n_jobs),
            implication =
                :parameterization_and_rank_normalized_diagnostics_are_next,
            public_claim_allowed = false),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "priority followups still have mcmc_warning",
            implication =
                :do_not_claim_public_fit_thresholds_model_weights_or_q_revisions,
            public_claim_allowed = false),
    ]
end

function input_artifact_rows(options)
    return [
        (artifact = :sampler_warning_surface_diagnosis,
            path = rel(options.warning_surface_json),
            sha256 = file_sha256(options.warning_surface_json)),
        (artifact = :draws_x4_gate_followup,
            path = rel(options.draws_x4_json),
            sha256 = file_sha256(options.draws_x4_json)),
        (artifact = :chain_count_gate_followup,
            path = rel(options.chain_json),
            sha256 = file_sha256(options.chain_json)),
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
        println(io, "# Stan-Guided Sampler Remediation Review")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Stan Sources")
        table(io, ["Source", "Guidance", "Local Use"],
            [[row.source, row.guidance, row.local_use]
             for row in artifact.source_rows])
        println(io, "## Local Evidence")
        table(io, ["Evidence", "Finding", "Value", "Implication"],
            [[row.evidence, row.finding, row.value, row.implication]
             for row in artifact.local_evidence_rows])
        println(io, "## Parameterization Audit Targets")
        table(io, ["Block", "Max Rhat", "Min ESS", "Bad Rhat", "Low ESS",
                "Audit"],
            [[row.block, row.max_rhat, row.min_ess, row.total_bad_rhat,
                row.total_low_ess, row.audit_target]
             for row in artifact.parameterization_audit_rows[1:6]])
        println(io, "## Decisions")
        table(io, ["Decision", "Rationale", "Local Action"],
            [[row.decision, row.rationale, row.local_action]
             for row in artifact.decision_rows])
        println(io, "## Source URLs")
        for row in artifact.source_rows
            println(io, "- ", row.title, ": ", row.url)
        end
        println(io)
        println(io, "## Boundary")
        println(io)
        println(io,
            "This review aligns local diagnostics with Stan practice. It does ",
            "not create public threshold, Q-revision, model-weight, or ",
            "sparse-superiority claims.")
    end
    return path
end

function build_artifact(options)
    warning_surface = read_json(options.warning_surface_json)
    draws_x4 = read_json(options.draws_x4_json)
    chain = read_json(options.chain_json)
    sources = source_rows()
    local_evidence = local_evidence_rows(warning_surface, draws_x4, chain)
    audit = parameterization_audit_rows(warning_surface)
    decisions = decision_rows()
    findings = finding_rows(warning_surface, draws_x4, chain)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_stan_guided_sampler_remediation_review,
        status = :local_stan_guided_sampler_review_recorded,
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
        automatic_q_revision = false,
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        input_artifacts = input_artifact_rows(options),
        source_rows = sources,
        local_evidence_rows = local_evidence,
        parameterization_audit_rows = audit,
        decision_rows = decisions,
        finding_rows = findings,
        summary = (;
            passed = true,
            n_sources = length(sources),
            n_local_evidence_rows = length(local_evidence),
            top_parameterization_audit_block = first(audit).block,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate =
                :rank_normalized_diagnostics_and_parameterization_audit,
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
    println("sources=", artifact.summary.n_sources,
        " top_block=", artifact.summary.top_parameterization_audit_block,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
