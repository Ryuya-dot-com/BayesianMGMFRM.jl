#!/usr/bin/env julia

using JSON3
using SHA
using Statistics
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_BASELINE = joinpath(
    ROOT,
    "test",
    "fixtures",
    "mgmfrm_tam_overlap_baseline.json",
)
const DEFAULT_OUTPUT = joinpath(
    ROOT,
    "test",
    "fixtures",
    "mgmfrm_tam_overlap_execution_review.json",
)
const BASELINE_SCHEMA = "bayesianmgmfrm.mgmfrm_tam_overlap_baseline.v1"

include(joinpath(@__DIR__, "local_json.jl"))

function usage()
    return """
    Run the local TAM overlap baseline and record an execution review.

    This script calls Rscript and TAM::tam.mml.mfr against the committed
    long-format CSV from mgmfrm_tam_overlap_baseline.json. It records execution
    metadata, TAM parameter rows, and diagnostic parameter-comparison metrics.
    It does not approve broad external validation, publish, register, push, or
    upload.

    Usage:
      julia --project=. scripts/generate_mgmfrm_tam_overlap_execution_review.jl [--baseline PATH] [--output PATH]
    """
end

function parse_args(args)
    baseline = DEFAULT_BASELINE
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--baseline"
            index < length(args) || error("--baseline requires a path")
            baseline = abspath(args[index + 1])
            index += 2
        elseif arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; baseline, output)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])

function file_sha256(path::AbstractString)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

load_json(path::AbstractString) = JSON3.read(read(path, String))
as_string(value) = String(value)
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_float(value) = Float64(value)

function strip_csv_token(value::AbstractString)
    text = strip(value)
    if startswith(text, "\"") && endswith(text, "\"") && length(text) >= 2
        text = text[2:(end - 1)]
    end
    return replace(text, "\"\"" => "\"")
end

function read_simple_csv(path::AbstractString)
    lines = readlines(path)
    isempty(lines) && return NamedTuple[]
    header = Symbol.(replace.(strip_csv_token.(split(first(lines), ",")), "." => "_"))
    rows = NamedTuple[]
    for line in lines[2:end]
        isempty(strip(line)) && continue
        values = strip_csv_token.(split(line, ","))
        length(values) == length(header) ||
            error("CSV row in $(basename(path)) has $(length(values)) value(s); expected $(length(header))")
        push!(rows, NamedTuple{Tuple(header)}(Tuple(values)))
    end
    return rows
end

function parse_float(value)
    text = strip_csv_token(String(value))
    isempty(text) && return NaN
    return parse(Float64, text)
end

function parse_int(value)
    text = strip_csv_token(String(value))
    isempty(text) && return 0
    return parse(Int, text)
end

function r_script_source()
    return raw"""
args <- commandArgs(trailingOnly = TRUE)
csv_path <- args[[1]]
xsi_path <- args[[2]]
summary_path <- args[[3]]
audit_path <- args[[4]]

suppressPackageStartupMessages(library(TAM))
dat <- read.csv(csv_path)
resp <- data.frame(score = dat$score)
facets <- data.frame(item = factor(dat$item), rater = factor(dat$rater))
fit <- TAM::tam.mml.mfr(
    resp = resp,
    facets = facets,
    pid = dat$person,
    formulaA = ~ item + rater + item:step,
    constraint = "cases",
    verbose = FALSE
)
write.csv(fit$xsi.facets, xsi_path, row.names = FALSE)
ic <- fit$ic[1, ]
summary <- data.frame(
    r_version = R.version.string,
    tam_version = as.character(utils::packageVersion("TAM")),
    iter = fit$iter,
    deviance = as.numeric(fit$deviance),
    eap_rel = as.numeric(fit$EAP.rel),
    n = ic$n,
    loglike = ic$loglike,
    AIC = ic$AIC,
    BIC = ic$BIC,
    Npars = ic$Npars
)
write.csv(summary, summary_path, row.names = FALSE)

expanded <- fit$xsi.facets
n_steps <- ncol(fit$AXsi_) - 1
facet_value <- function(facet, parameter) {
    expanded$xsi[expanded$facet == facet & expanded$parameter == parameter][[1]]
}
item_step_sums <- vapply(levels(facets$item), function(item) {
    sum(vapply(seq_len(n_steps), function(step) {
        facet_value("item:step", paste0(item, ":step", step))
    }, numeric(1)))
}, numeric(1))

manual_axsi <- matrix(0, nrow = nrow(fit$AXsi_), ncol = ncol(fit$AXsi_))
for (row in seq_len(nrow(fit$AXsi_))) {
    tokens <- strsplit(as.character(fit$item$item[[row]]), "-", fixed = TRUE)[[1]]
    item <- tokens[[1]]
    rater <- tokens[[2]]
    item_effect <- facet_value("item", item)
    rater_effect <- facet_value("rater", rater)
    for (step in seq_len(n_steps)) {
        cumulative_step <- sum(vapply(seq_len(step), function(index) {
            facet_value("item:step", paste0(item, ":step", index))
        }, numeric(1)))
        manual_axsi[row, step + 1] <-
            step * (item_effect + rater_effect) + cumulative_step
    }
}

xsi_table <- fit$xsi.constr$xsi.table
audit <- data.frame(
    fitted_formulaA = paste(deparse(fit$formulaA), collapse = " "),
    n_design_rows = dim(fit$A)[[1]],
    n_score_categories = dim(fit$A)[[2]],
    n_independent_xsi = dim(fit$A)[[3]],
    n_expanded_xsi = nrow(expanded),
    n_constraint_rows = sum(xsi_table$constraint == 1),
    n_item_step_constraint_rows =
        sum(xsi_table$constraint == 1 & xsi_table$facet == "item:step"),
    rater_sum_abs = abs(sum(expanded$xsi[expanded$facet == "rater"])),
    pseudo_facet_max_abs = max(abs(expanded$xsi[expanded$facet == "psf"])),
    item_step_sum_max_abs = max(abs(item_step_sums)),
    category_intercept_reconstruction_max_abs_error =
        max(abs(manual_axsi - fit$AXsi_))
)
write.csv(audit, audit_path, row.names = FALSE)
"""
end

function run_tam(csv_path::AbstractString)
    rscript = Sys.which("Rscript")
    isempty(rscript) && error("Rscript is not available on PATH")
    temp_root = mktempdir()
    script_path = joinpath(temp_root, "run_tam_overlap.R")
    xsi_path = joinpath(temp_root, "tam_xsi_facets.csv")
    summary_path = joinpath(temp_root, "tam_summary.csv")
    audit_path = joinpath(temp_root, "tam_formula_audit.csv")
    stdout_path = joinpath(temp_root, "tam_stdout.txt")
    stderr_path = joinpath(temp_root, "tam_stderr.txt")
    open(script_path, "w") do io
        print(io, r_script_source())
    end
    cmd = `$rscript --vanilla $script_path $csv_path $xsi_path $summary_path $audit_path`
    exit_code = 0
    try
        run(pipeline(cmd; stdout = stdout_path, stderr = stderr_path))
    catch err
        if err isa Base.ProcessFailedException
            exit_code = err.procs[1].exitcode
        else
            rethrow()
        end
    end
    exit_code == 0 || error(
        "TAM execution failed with exit code $exit_code: " *
        strip(read(stderr_path, String)),
    )
    return (;
        rscript,
        stdout = read(stdout_path, String),
        stderr = read(stderr_path, String),
        xsi_rows = read_simple_csv(xsi_path),
        summary_rows = read_simple_csv(summary_path),
        audit_rows = read_simple_csv(audit_path),
        xsi_csv_sha256 = file_sha256(xsi_path),
        summary_csv_sha256 = file_sha256(summary_path),
        audit_csv_sha256 = file_sha256(audit_path),
    )
end

function tam_parameter_rows(rows)
    return [
        (;
            parameter = as_string(row.parameter),
            facet = as_string(row.facet),
            xsi = parse_float(row.xsi),
            se_xsi = parse_float(row.se_xsi),
        )
        for row in rows
    ]
end

function pearson_correlation(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    length(x) == length(y) || error("correlation vectors must have equal length")
    length(x) >= 2 || return missing
    centered_x = Float64.(x) .- mean(Float64.(x))
    centered_y = Float64.(y) .- mean(Float64.(y))
    denom = sqrt(sum(abs2, centered_x) * sum(abs2, centered_y))
    denom == 0 && return missing
    return sum(centered_x .* centered_y) / denom
end

function comparison_summary(block::Symbol, truth_values, tam_values;
        adapter::Symbol, interpretation::Symbol)
    truth = Float64.(truth_values)
    tam = Float64.(tam_values)
    length(truth) == length(tam) ||
        error("comparison block $block has $(length(truth)) truth value(s) and $(length(tam)) TAM value(s)")
    diff = tam .- truth
    return (;
        block,
        n_parameters = length(truth),
        adapter,
        pearson_correlation = pearson_correlation(truth, tam),
        mean_abs_difference = mean(abs.(diff)),
        max_abs_difference = maximum(abs.(diff)),
        mean_signed_difference = mean(diff),
        interpretation,
    )
end

function value_by_parameter(rows, facet::AbstractString)
    output = Dict{String,Float64}()
    for row in rows
        row.facet == facet || continue
        output[row.parameter] = row.xsi
    end
    return output
end

function centered(values)
    output = Float64.(values)
    output .-= mean(output)
    return output
end

function step_parameter_name(item::Int, step::Int)
    return string(item, ":step", step)
end

function comparison_rows(baseline, parameter_rows)
    truth = baseline[:truth]
    item_truth = centered(Float64.(truth[:item_difficulty]))
    rater_truth = centered(Float64.(truth[:rater_severity]))
    item_rows = value_by_parameter(parameter_rows, "item")
    rater_rows = value_by_parameter(parameter_rows, "rater")
    step_rows = value_by_parameter(parameter_rows, "item:step")
    item_tam = centered([item_rows[string(item)] for item in 1:length(item_truth)])
    rater_tam = centered([rater_rows[string("rater", rater)]
        for rater in 1:length(rater_truth)])
    step_truth = Float64[]
    step_tam = Float64[]
    for item in eachindex(truth[:item_steps])
        steps = Float64.(truth[:item_steps][item])
        for step in eachindex(steps)
            push!(step_truth, steps[step])
            push!(step_tam, step_rows[step_parameter_name(item, step)])
        end
    end
    return [
        comparison_summary(:item_difficulty, item_truth, item_tam;
            adapter = :center_truth_and_tam_item_facets,
            interpretation = :diagnostic_overlap_not_claim_threshold),
        comparison_summary(:rater_severity, rater_truth, rater_tam;
            adapter = :center_truth_and_tam_rater_facets,
            interpretation = :diagnostic_overlap_not_claim_threshold),
        comparison_summary(:item_step, step_truth, step_tam;
            adapter = :expanded_tam_item_step_sum_constraint_adapter,
            interpretation = :structurally_audited_numerically_pilot_only),
    ]
end

function build_artifact(baseline_path::AbstractString)
    isfile(baseline_path) || error("baseline fixture missing: $(relpath(baseline_path, ROOT))")
    baseline = load_json(baseline_path)
    schema = as_string(baseline[:schema])
    schema == BASELINE_SCHEMA || error("unexpected baseline schema: $schema")
    csv_path = joinpath(ROOT, as_string(baseline[:tam_export][:path]))
    isfile(csv_path) || error("baseline CSV missing: $(relpath(csv_path, ROOT))")
    tam = run_tam(csv_path)
    summary = only(tam.summary_rows)
    audit = only(tam.audit_rows)
    parameters = tam_parameter_rows(tam.xsi_rows)
    comparisons = comparison_rows(baseline, parameters)
    n_item = count(row -> row.facet == "item", parameters)
    n_rater = count(row -> row.facet == "rater", parameters)
    n_step = count(row -> row.facet == "item:step", parameters)
    n_psf = count(row -> row.facet == "psf", parameters)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_tam_overlap_execution_review.v1",
        family = :mfrm,
        scope = :tam_overlap_execution_review,
        status = :tam_overlap_execution_recorded,
        decision = :record_tam_execution_keep_external_validation_claim_blocked,
        local_only = true,
        external_software = :tam,
        tam_execution_completed = true,
        tam_parameter_table_extracted = true,
        parameter_comparison_completed = true,
        external_software_validation_completed = false,
        public_claim_release_allowed = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = (;
            protocol_id = :mgmfrm_tam_overlap_execution_review_v1,
            generator = "scripts/generate_mgmfrm_tam_overlap_execution_review.jl",
            generator_source_sha256 = file_sha256(@__FILE__),
            baseline_artifact = relpath(baseline_path, ROOT),
            baseline_artifact_sha256 = file_sha256(baseline_path),
            baseline_csv = relpath(csv_path, ROOT),
            baseline_csv_sha256 = file_sha256(csv_path),
            rscript_path = tam.rscript,
            r_command = :TAM_tam_mml_mfr,
            tam_formulaA = "~ item + rater + item:step",
            tam_constraint = "cases",
        ),
        tam_environment = (;
            r_version = as_string(summary.r_version),
            tam_version = as_string(summary.tam_version),
            rscript_path = tam.rscript,
        ),
        tam_fit_summary = (;
            iter = parse_int(summary.iter),
            deviance = parse_float(summary.deviance),
            eap_rel = parse_float(summary.eap_rel),
            n_persons = parse_int(summary.n),
            loglike = parse_float(summary.loglike),
            aic = parse_float(summary.AIC),
            bic = parse_float(summary.BIC),
            n_parameters = parse_int(summary.Npars),
            stdout_contains_pseudo_facet_notice =
                occursin("pseudo facet", tam.stdout),
            stderr_empty = isempty(strip(tam.stderr)),
        ),
        tam_formula_adapter_audit = (;
            fitted_formulaA = as_string(audit.fitted_formulaA),
            n_design_rows = parse_int(audit.n_design_rows),
            n_score_categories = parse_int(audit.n_score_categories),
            n_independent_xsi = parse_int(audit.n_independent_xsi),
            n_expanded_xsi = parse_int(audit.n_expanded_xsi),
            n_constraint_rows = parse_int(audit.n_constraint_rows),
            n_item_step_constraint_rows =
                parse_int(audit.n_item_step_constraint_rows),
            rater_sum_abs = parse_float(audit.rater_sum_abs),
            pseudo_facet_max_abs = parse_float(audit.pseudo_facet_max_abs),
            item_step_sum_max_abs = parse_float(audit.item_step_sum_max_abs),
            category_intercept_reconstruction_max_abs_error = parse_float(
                audit.category_intercept_reconstruction_max_abs_error,
            ),
            interpretation =
                :expanded_facets_reconstruct_tam_category_intercepts_under_sum_constraints,
        ),
        tam_parameter_rows = parameters,
        parameter_comparison_rows = comparisons,
        adapter_notes = [
            (;
                adapter = :center_truth_and_tam_item_facets,
                scope = :item_difficulty,
                claim_role = :diagnostic_overlap_only,
            ),
            (;
                adapter = :center_truth_and_tam_rater_facets,
                scope = :rater_severity,
                claim_role = :diagnostic_overlap_only,
            ),
            (;
                adapter = :expanded_tam_item_step_sum_constraint_adapter,
                scope = :item_step,
                claim_role = :structurally_audited_numerically_pilot_only,
            ),
        ],
        output_hashes = (;
            transient_tam_xsi_facets_csv_sha256 = tam.xsi_csv_sha256,
            transient_tam_summary_csv_sha256 = tam.summary_csv_sha256,
            transient_tam_formula_audit_csv_sha256 = tam.audit_csv_sha256,
        ),
        claim_limits = [
            :single_local_tam_overlap_execution_only,
            :parameter_differences_include_sampling_error,
            :item_step_adapter_structure_audited_single_pilot_only,
            :no_facets_or_conquest_execution,
            :no_generalized_gmfrm_or_mgmfrm_external_validation,
            :no_external_construct_validity_claim,
            :no_public_claim_release,
        ],
        summary = (;
            passed = n_item == 5 && n_rater == 4 && n_step == 15 &&
                parse_int(summary.iter) > 0 &&
                isfinite(parse_float(summary.deviance)),
            tam_execution_completed = true,
            tam_parameter_table_extracted = true,
            parameter_comparison_completed = true,
            external_software_validation_completed = false,
            public_claim_release_allowed = false,
            n_tam_parameter_rows = length(parameters),
            n_item_rows = n_item,
            n_rater_rows = n_rater,
            n_item_step_rows = n_step,
            n_pseudo_facet_rows = n_psf,
            n_parameter_comparison_rows = length(comparisons),
            formula_adapter_audit_completed = true,
            next_gate =
                :freeze_prospective_tam_thresholds_and_run_multireplication_comparison,
        ),
    )
end

function main(args)
    parsed = parse_args(args)
    artifact = build_artifact(parsed.baseline)
    write_artifact(parsed.output, artifact)
    println("wrote ", relpath(parsed.output, ROOT))
    println(
        "passed=", artifact.summary.passed,
        " tam_iter=", artifact.tam_fit_summary.iter,
        " parameters=", artifact.summary.n_tam_parameter_rows,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
