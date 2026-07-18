#!/usr/bin/env julia

using JSON3
using Printf
using Random
using SHA
using Statistics
using TOML

include(joinpath(@__DIR__, "generate_mgmfrm_tam_direct_estimate_pilot.jl"))

const DIRECT_MULTIREP_DEFAULT_BASELINE = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_overlap_baseline.json")
const DIRECT_MULTIREP_DEFAULT_POLICY = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_direct_agreement_policy.json")
const DIRECT_MULTIREP_DEFAULT_REFINEMENT = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_tam_direct_agreement_policy_refinement.json")
const DIRECT_MULTIREP_DEFAULT_RECOVERY_POLICY = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_comparison_policy_review.json")
const DIRECT_MULTIREP_DEFAULT_RAW_ROOT = joinpath(
    ROOT, "artifacts", "mgmfrm_tam_direct_agreement_multireplication")
const DIRECT_MULTIREP_DEFAULT_OUTPUT = joinpath(
    ROOT, "test", "fixtures",
    "mgmfrm_tam_direct_agreement_multireplication.json")

const DIRECT_MULTIREP_POLICY_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy.v1"
const DIRECT_MULTIREP_REFINEMENT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_policy_refinement.v1"
const DIRECT_MULTIREP_RECOVERY_POLICY_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_comparison_policy_review.v1"
const DIRECT_MULTIREP_JOB_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_multireplication_job.v1"
const DIRECT_MULTIREP_RESULT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_direct_agreement_multireplication.v1"
const DIRECT_MULTIREP_BLOCKS =
    (:item_difficulty, :rater_severity, :item_step)
const DIRECT_MULTIREP_PERSON_COUNTS = (40, 100)
const DIRECT_MULTIREP_REPLICATIONS = 5
const DIRECT_MULTIREP_RANK_RHAT = 1.01
const DIRECT_MULTIREP_RANK_ESS = 400.0
const DIRECT_MULTIREP_EBFMI = 0.30

function direct_multirep_usage()
    return """
    Run or aggregate the locally frozen direct package-versus-TAM comparison.

    Default mode runs all 10 jobs sequentially and writes the committed summary
    fixture. Individual jobs can be run independently for fault isolation and
    parallel execution; raw files are retained under the ignored artifacts/
    directory and the committed fixture stores their hashes.

    Usage:
      julia --project=. scripts/generate_mgmfrm_tam_direct_agreement_multireplication.jl [options]

    Options:
      --job N REP                 Run one N-person replication only.
      --aggregate-only            Aggregate the 10 selected job results.
      --infrastructure-retry TEXT Permit a new retained attempt with a reason.
      --baseline PATH
      --policy PATH
      --refinement PATH
      --recovery-policy PATH
      --raw-root PATH
      --output PATH
      --progress                  Show package sampler progress.
    """
end

function direct_multirep_parse_args(args)
    baseline = DIRECT_MULTIREP_DEFAULT_BASELINE
    policy = DIRECT_MULTIREP_DEFAULT_POLICY
    refinement = DIRECT_MULTIREP_DEFAULT_REFINEMENT
    recovery_policy = DIRECT_MULTIREP_DEFAULT_RECOVERY_POLICY
    raw_root = DIRECT_MULTIREP_DEFAULT_RAW_ROOT
    output = DIRECT_MULTIREP_DEFAULT_OUTPUT
    job = nothing
    aggregate_only = false
    infrastructure_retry = nothing
    progress = false
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--job"
            index + 2 <= length(args) || error("--job requires N and REP")
            job = (n_persons = parse(Int, args[index + 1]),
                replication = parse(Int, args[index + 2]))
            index += 3
        elseif arg == "--aggregate-only"
            aggregate_only = true
            index += 1
        elseif arg == "--infrastructure-retry"
            index < length(args) ||
                error("--infrastructure-retry requires a reason")
            infrastructure_retry = String(args[index + 1])
            isempty(strip(infrastructure_retry)) &&
                error("infrastructure retry reason must not be empty")
            index += 2
        elseif arg == "--baseline"
            index < length(args) || error("--baseline requires a path")
            baseline = abspath(args[index + 1])
            index += 2
        elseif arg == "--policy"
            index < length(args) || error("--policy requires a path")
            policy = abspath(args[index + 1])
            index += 2
        elseif arg == "--refinement"
            index < length(args) || error("--refinement requires a path")
            refinement = abspath(args[index + 1])
            index += 2
        elseif arg == "--recovery-policy"
            index < length(args) || error("--recovery-policy requires a path")
            recovery_policy = abspath(args[index + 1])
            index += 2
        elseif arg == "--raw-root"
            index < length(args) || error("--raw-root requires a path")
            raw_root = abspath(args[index + 1])
            index += 2
        elseif arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg == "--progress"
            progress = true
            index += 1
        elseif arg in ("-h", "--help")
            println(direct_multirep_usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    job !== nothing && aggregate_only &&
        error("--job and --aggregate-only are mutually exclusive")
    infrastructure_retry !== nothing && job === nothing &&
        error("--infrastructure-retry requires --job")
    if job !== nothing
        job.n_persons in DIRECT_MULTIREP_PERSON_COUNTS ||
            error("job N must be 40 or 100")
        1 <= job.replication <= DIRECT_MULTIREP_REPLICATIONS ||
            error("job REP must be 1 through 5")
    end
    return (;
        baseline, policy, refinement, recovery_policy, raw_root, output, job,
        aggregate_only, infrastructure_retry, progress)
end

function direct_multirep_checked_artifact(path::AbstractString,
        expected_schema::AbstractString)
    isfile(path) || error("required artifact missing: $(relpath(path, ROOT))")
    artifact = load_json(path)
    as_string(artifact[:schema]) == expected_schema ||
        error("unexpected schema for $(relpath(path, ROOT))")
    return artifact
end

function direct_multirep_job_id(n_persons::Int, replication::Int)
    return @sprintf("n%03d_rep%02d", n_persons, replication)
end

function direct_multirep_job_root(raw_root::AbstractString,
        n_persons::Int, replication::Int)
    return joinpath(raw_root, direct_multirep_job_id(n_persons, replication))
end

function direct_multirep_selected_path(raw_root::AbstractString,
        n_persons::Int, replication::Int)
    return joinpath(direct_multirep_job_root(raw_root, n_persons, replication),
        "selected_attempt.json")
end

function direct_multirep_attempt_directory(raw_root::AbstractString,
        n_persons::Int, replication::Int, retry_reason)
    root = direct_multirep_job_root(raw_root, n_persons, replication)
    mkpath(root)
    existing = sort(filter(name -> startswith(name, "attempt_"), readdir(root)))
    selected = direct_multirep_selected_path(raw_root, n_persons, replication)
    if isfile(selected) && retry_reason === nothing
        error("job $(direct_multirep_job_id(n_persons, replication)) already has a selected attempt; use --infrastructure-retry only for an objective infrastructure failure")
    end
    attempt = length(existing) + 1
    directory = joinpath(root, @sprintf("attempt_%02d", attempt))
    ispath(directory) && error("attempt directory already exists: $directory")
    mkpath(directory)
    return (; directory, attempt, selected)
end

function direct_multirep_seed_row(refinement, n_persons::Int,
        replication::Int)
    rows = [row for row in refinement[:data_and_input_contract][
            :seed_registry_rows]
        if as_int(row[:n_persons]) == n_persons &&
            as_int(row[:replication]) == replication]
    length(rows) == 1 || error("expected one frozen seed row")
    return only(rows)
end

function direct_multirep_softmax(values)
    shifted = values .- maximum(values)
    weights = exp.(shifted)
    return weights ./ sum(weights)
end

function direct_multirep_probabilities(truth, ability::Float64,
        rater::Int, item::Int)
    categories = length(truth.item_steps[item]) + 1
    location = ability - truth.rater_severity[rater] -
        truth.item_difficulty[item]
    eta = zeros(Float64, categories)
    cumulative_step = 0.0
    for category in 2:categories
        cumulative_step += truth.item_steps[item][category - 1]
        eta[category] = (category - 1) * location - cumulative_step
    end
    return direct_multirep_softmax(eta)
end

function direct_multirep_sample_category(rng::AbstractRNG, probabilities)
    draw = rand(rng)
    cumulative = 0.0
    for index in eachindex(probabilities)
        cumulative += probabilities[index]
        draw <= cumulative && return index - 1
    end
    return length(probabilities) - 1
end

function direct_multirep_truth(baseline)
    truth = baseline[:truth]
    return (;
        item_difficulty = Float64.(truth[:item_difficulty]),
        rater_severity = Float64.(truth[:rater_severity]),
        item_steps = [Float64.(steps) for steps in truth[:item_steps]],
    )
end

function direct_multirep_write_dataset(directory::AbstractString, baseline,
        seed_row, n_persons::Int)
    csv_path = joinpath(directory, "input.csv")
    abilities_path = joinpath(directory, "abilities.csv")
    truth = direct_multirep_truth(baseline)
    ability_seed = as_int(seed_row[:ability_seed])
    response_seed = as_int(seed_row[:response_seed])
    ability_rng = MersenneTwister(ability_seed)
    response_rng = MersenneTwister(response_seed)
    abilities = randn(ability_rng, n_persons)
    persons = Int[]
    raters = Int[]
    items = Int[]
    scores = Int[]
    category_counts = zeros(Int, length(first(truth.item_steps)) + 1)
    open(csv_path, "w") do io
        println(io, "person,rater,item,score")
        for person in 1:n_persons,
                rater in eachindex(truth.rater_severity),
                item in eachindex(truth.item_difficulty)
            probabilities = direct_multirep_probabilities(
                truth, abilities[person], rater, item)
            score = direct_multirep_sample_category(response_rng, probabilities)
            println(io, person, ',', rater, ',', item, ',', score)
            push!(persons, person)
            push!(raters, rater)
            push!(items, item)
            push!(scores, score)
            category_counts[score + 1] += 1
        end
    end
    open(abilities_path, "w") do io
        println(io, "person,ability")
        for person in eachindex(abilities)
            println(io, person, ',', abilities[person])
        end
    end
    dataset_truth_path = joinpath(directory, "dataset_truth.json")
    write_artifact(dataset_truth_path, (;
        schema =
            "bayesianmgmfrm.mgmfrm_tam_direct_agreement_dataset_truth.v1",
        n_persons,
        ability_seed,
        response_seed,
        person_ability = abilities,
        item_difficulty = truth.item_difficulty,
        rater_severity = truth.rater_severity,
        item_steps = truth.item_steps,
    ))
    return (;
        csv_path,
        abilities_path,
        dataset_truth_path,
        persons,
        raters,
        items,
        scores,
        abilities,
        category_counts,
        all_categories_observed = all(>(0), category_counts),
        n_observations = length(scores),
        csv_sha256 = file_sha256(csv_path),
        abilities_sha256 = file_sha256(abilities_path),
        dataset_truth_sha256 = file_sha256(dataset_truth_path),
    )
end

function direct_multirep_tam_script_source()
    return raw"""
args <- commandArgs(trailingOnly = TRUE)
csv_path <- args[[1]]
output_dir <- args[[2]]

suppressPackageStartupMessages(library(TAM))
dat <- read.csv(csv_path)
resp <- data.frame(score = dat$score)
facets <- data.frame(item = factor(dat$item), rater = factor(dat$rater))
control <- list(maxiter = 1000, conv = 1e-4, convD = 1e-3, convM = 1e-4)
fit <- TAM::tam.mml.mfr(
    resp = resp,
    facets = facets,
    pid = dat$person,
    formulaA = ~ item + rater + item:step,
    constraint = "cases",
    control = control,
    delete.red.items = TRUE,
    verbose = FALSE
)

write.csv(fit$xsi.facets, file.path(output_dir, "tam_xsi_facets.csv"),
    row.names = FALSE)
ic <- fit$ic[1, ]
deviance_history <- fit$deviance.history
if (is.matrix(deviance_history) || is.data.frame(deviance_history)) {
    deviance_values <- as.numeric(deviance_history[, ncol(deviance_history)])
} else {
    deviance_values <- as.numeric(deviance_history)
}
final_deviance_delta <- if (length(deviance_values) >= 2) {
    abs(tail(deviance_values, 1) - tail(deviance_values, 2)[[1]])
} else {
    NA_real_
}
snodes <- if (is.null(fit$control$snodes)) 0 else fit$control$snodes
control_seed <- if (is.null(fit$control$seed)) NA_integer_ else fit$control$seed
summary <- data.frame(
    r_version = R.version.string,
    tam_version = as.character(utils::packageVersion("TAM")),
    iter = fit$iter,
    control_maxiter = control$maxiter,
    iteration_limit_not_reached = fit$iter < control$maxiter,
    final_deviance_delta = final_deviance_delta,
    control_convD = control$convD,
    final_deviance_delta_below_convD =
        is.finite(final_deviance_delta) && final_deviance_delta < control$convD,
    snodes = snodes,
    control_seed_is_null = is.na(control_seed),
    deviance = as.numeric(fit$deviance),
    eap_rel = as.numeric(fit$EAP.rel),
    n = ic$n,
    loglike = ic$loglike,
    AIC = ic$AIC,
    BIC = ic$BIC,
    Npars = ic$Npars
)
write.csv(summary, file.path(output_dir, "tam_summary.csv"), row.names = FALSE)

expanded <- fit$xsi.facets
n_steps <- ncol(fit$AXsi_) - 1
facet_value <- function(facet, parameter) {
    values <- expanded$xsi[expanded$facet == facet & expanded$parameter == parameter]
    if (length(values) != 1) stop("non-unique facet parameter")
    values[[1]]
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
write.csv(audit, file.path(output_dir, "tam_formula_audit.csv"),
    row.names = FALSE)
saveRDS(fit, file.path(output_dir, "tam_fit.rds"))
capture.output(sessionInfo(), file = file.path(output_dir, "tam_session_info.txt"))
"""
end

function direct_multirep_run_tam(csv_path::AbstractString,
        directory::AbstractString)
    rscript = Sys.which("Rscript")
    isempty(rscript) && error("Rscript is not available on PATH")
    script_path = joinpath(directory, "tam_runner.R")
    stdout_path = joinpath(directory, "tam_stdout.txt")
    stderr_path = joinpath(directory, "tam_stderr.txt")
    open(script_path, "w") do io
        print(io, direct_multirep_tam_script_source())
    end
    cmd = `$rscript --vanilla $script_path $csv_path $directory`
    try
        run(pipeline(cmd; stdout = stdout_path, stderr = stderr_path))
    catch err
        if err isa Base.ProcessFailedException
            error("TAM execution failed: " * strip(read(stderr_path, String)))
        end
        rethrow()
    end
    xsi_path = joinpath(directory, "tam_xsi_facets.csv")
    summary_path = joinpath(directory, "tam_summary.csv")
    audit_path = joinpath(directory, "tam_formula_audit.csv")
    return (;
        rscript,
        script_path,
        stdout_path,
        stderr_path,
        xsi_path,
        summary_path,
        audit_path,
        stdout = read(stdout_path, String),
        stderr = read(stderr_path, String),
        parameters = tam_parameter_rows(read_simple_csv(xsi_path)),
        summary = only(read_simple_csv(summary_path)),
        audit = only(read_simple_csv(audit_path)),
    )
end

function direct_multirep_tam_block_values(parameters, baseline)
    truth = baseline[:truth]
    n_items = length(truth[:item_difficulty])
    n_raters = length(truth[:rater_severity])
    n_steps = length(first(truth[:item_steps]))
    values = Dict{Tuple{String,String},NamedTuple}()
    for row in parameters
        key = (row.facet, row.parameter)
        haskey(values, key) && error("duplicate TAM parameter: $key")
        values[key] = (; estimate = row.xsi, se = row.se_xsi)
    end
    item_raw = [values[("item", string(item))] for item in 1:n_items]
    rater_raw = [values[("rater", string("rater", rater))]
        for rater in 1:n_raters]
    item_mean = mean(row.estimate for row in item_raw)
    rater_mean = mean(row.estimate for row in rater_raw)
    item = [(estimate = row.estimate - item_mean, se = row.se)
        for row in item_raw]
    rater = [(estimate = row.estimate - rater_mean, se = row.se)
        for row in rater_raw]
    steps = [values[("item:step", step_parameter_name(item_index, step))]
        for item_index in 1:n_items for step in 1:n_steps]
    return (;
        item_difficulty = (;
            estimate = [row.estimate for row in item],
            se = [row.se for row in item]),
        rater_severity = (;
            estimate = [row.estimate for row in rater],
            se = [row.se for row in rater]),
        item_step = (;
            estimate = [row.estimate for row in steps],
            se = [row.se for row in steps]),
    )
end

function direct_multirep_tam_validity(tam, expected_version::AbstractString)
    summary = tam.summary
    audit = tam.audit
    parameters = tam.parameters
    facet_counts = (;
        item = count(row -> row.facet == "item", parameters),
        rater = count(row -> row.facet == "rater", parameters),
        item_step = count(row -> row.facet == "item:step", parameters),
        pseudo_facet = count(row -> row.facet == "psf", parameters),
    )
    expected_counts = (;
        item = 5,
        rater = 4,
        item_step = 15,
        pseudo_facet = 5,
    )
    checks = [
        (check = :exit_code_zero, passed = true),
        (check = :tam_version_matches,
            passed = as_string(summary.tam_version) == expected_version),
        (check = :finite_deviance,
            passed = isfinite(parse_float(summary.deviance))),
        (check = :positive_iteration_count,
            passed = parse_int(summary.iter) > 0),
        (check = :iteration_limit_not_reached,
            passed = lowercase(as_string(summary.iteration_limit_not_reached)) == "true" &&
                parse_int(summary.iter) < parse_int(summary.control_maxiter)),
        (check = :final_deviance_delta_below_convD,
            passed = lowercase(as_string(
                summary.final_deviance_delta_below_convD)) == "true" &&
                isfinite(parse_float(summary.final_deviance_delta)) &&
                parse_float(summary.final_deviance_delta) <
                    parse_float(summary.control_convD)),
        (check = :deterministic_tam_integration,
            passed = parse_int(summary.snodes) == 0 &&
                lowercase(as_string(summary.control_seed_is_null)) == "true"),
        (check = :expected_parameter_counts,
            passed = facet_counts == expected_counts),
        (check = :all_estimates_and_standard_errors_finite,
            passed = all(row -> isfinite(row.xsi) && isfinite(row.se_xsi),
                parameters)),
        (check = :formula_expansion_matches,
            passed = as_string(audit.fitted_formulaA) ==
                "~item + rater + item:step + psf"),
        (check = :rater_sum_constraint,
            passed = parse_float(audit.rater_sum_abs) <= 1.0e-10),
        (check = :pseudo_facet_zero,
            passed = parse_float(audit.pseudo_facet_max_abs) <= 1.0e-10),
        (check = :item_step_sum_constraint,
            passed = parse_float(audit.item_step_sum_max_abs) <= 1.0e-10),
        (check = :category_intercept_reconstruction,
            passed = parse_float(
                audit.category_intercept_reconstruction_max_abs_error) <=
                1.0e-10),
        (check = :stderr_empty, passed = isempty(strip(tam.stderr))),
    ]
    return (;
        passed = all(row -> row.passed, checks),
        check_rows = checks,
        iter = parse_int(summary.iter),
        maxiter = parse_int(summary.control_maxiter),
        final_deviance_delta = parse_float(summary.final_deviance_delta),
        convD = parse_float(summary.control_convD),
        snodes = parse_int(summary.snodes),
        control_seed_is_null =
            lowercase(as_string(summary.control_seed_is_null)) == "true",
        deviance = parse_float(summary.deviance),
        eap_rel = parse_float(summary.eap_rel),
        n_parameters = parse_int(summary.Npars),
        r_version = as_string(summary.r_version),
        tam_version = as_string(summary.tam_version),
        facet_counts,
    )
end

function direct_multirep_data(generated)
    return BayesianMGMFRM.FacetData((;
            examinee = generated.persons,
            rater = generated.raters,
            item = generated.items,
            score = generated.scores,
        );
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

function direct_multirep_fit_package(generated, refinement, seed::Int,
        progress::Bool)
    contract = refinement[:package_fit_contract]
    data = direct_multirep_data(generated)
    spec = BayesianMGMFRM.mfrm_spec(data; thresholds = :partial_credit)
    design = BayesianMGMFRM.getdesign(spec)
    prior = BayesianMGMFRM.MFRMPrior()
    recorded_prior = contract[:prior]
    prior.person_sd == as_float(recorded_prior[:person_sd]) ||
        error("person prior does not match frozen contract")
    prior.rater_sd == as_float(recorded_prior[:rater_sd]) ||
        error("rater prior does not match frozen contract")
    prior.item_sd == as_float(recorded_prior[:item_sd]) ||
        error("item prior does not match frozen contract")
    prior.step_sd == as_float(recorded_prior[:step_sd]) ||
        error("step prior does not match frozen contract")
    fit = BayesianMGMFRM.fit(design;
        prior,
        backend = Symbol(as_string(contract[:backend])),
        ndraws = as_int(contract[:retained_draws_per_chain]),
        warmup = as_int(contract[:warmup_per_chain]),
        chains = as_int(contract[:chains]),
        step_size = as_float(contract[:step_size]),
        seed,
        target_accept = as_float(contract[:target_accept]),
        max_depth = as_int(contract[:max_depth]),
        max_energy_error = as_float(contract[:max_energy_error]),
        metric = Symbol(as_string(contract[:metric])),
        ad_backend = Symbol(as_string(contract[:ad_backend])),
        init_jitter = as_float(contract[:init_jitter]),
        progress,
    )
    return (; fit, prior, design, aligned_draws = package_block_draws(fit))
end

function direct_multirep_write_draws(path::AbstractString, fit)
    open(path, "w") do io
        print(io, "chain,iteration,log_posterior")
        for name in fit.design.parameter_names
            print(io, ',', String(name))
        end
        println(io)
        for row in axes(fit.draws, 1)
            print(io, fit.chain_ids[row], ',', fit.iterations[row], ',',
                fit.log_posterior[row])
            for column in axes(fit.draws, 2)
                print(io, ',', fit.draws[row, column])
            end
            println(io)
        end
    end
    return path
end

function direct_multirep_aligned_matrix(aligned)
    return hcat(aligned.item_difficulty, aligned.rater_severity,
        aligned.item_step)
end

function direct_multirep_aligned_labels()
    return vcat(block_labels(:item_difficulty, 5),
        block_labels(:rater_severity, 4), block_labels(:item_step, 15))
end

function direct_multirep_write_aligned_draws(path::AbstractString, fit,
        aligned)
    matrix = direct_multirep_aligned_matrix(aligned)
    labels = direct_multirep_aligned_labels()
    open(path, "w") do io
        println(io, join(vcat(["chain", "iteration"], labels), ','))
        for row in axes(matrix, 1)
            print(io, fit.chain_ids[row], ',', fit.iterations[row])
            for column in axes(matrix, 2)
                print(io, ',', matrix[row, column])
            end
            println(io)
        end
    end
    return path
end

function direct_multirep_normal_quantile(p::Float64)
    0 < p < 1 || throw(ArgumentError("p must be in (0, 1)"))
    a = (-39.69683028665376, 220.9460984245205, -275.9285104469687,
        138.3577518672690, -30.66479806614716, 2.506628277459239)
    b = (-54.47609879822406, 161.5858368580409, -155.6989798598866,
        66.80131188771972, -13.28068155288572)
    c = (-0.007784894002430293, -0.3223964580411365, -2.400758277161838,
        -2.549732539343734, 4.374664141464968, 2.938163982698783)
    d = (0.007784695709041462, 0.3224671290700398,
        2.445134137142996, 3.754408661907416)
    plow = 0.02425
    phigh = 1 - plow
    if p < plow
        q = sqrt(-2 * log(p))
        return (((((c[1] * q + c[2]) * q + c[3]) * q + c[4]) * q +
                 c[5]) * q + c[6]) /
               ((((d[1] * q + d[2]) * q + d[3]) * q + d[4]) * q + 1)
    elseif p > phigh
        q = sqrt(-2 * log(1 - p))
        return -(((((c[1] * q + c[2]) * q + c[3]) * q + c[4]) * q +
                  c[5]) * q + c[6]) /
               ((((d[1] * q + d[2]) * q + d[3]) * q + d[4]) * q + 1)
    end
    q = p - 0.5
    r = q * q
    return (((((a[1] * r + a[2]) * r + a[3]) * r + a[4]) * r +
             a[5]) * r + a[6]) * q /
           (((((b[1] * r + b[2]) * r + b[3]) * r + b[4]) * r +
             b[5]) * r + 1)
end

function direct_multirep_average_ranks(values::Vector{Float64})
    order = sortperm(values)
    ranks = zeros(Float64, length(values))
    index = 1
    while index <= length(values)
        last = index
        while last < length(values) &&
              values[order[last + 1]] == values[order[index]]
            last += 1
        end
        average = (index + last) / 2
        for rank_index in index:last
            ranks[order[rank_index]] = average
        end
        index = last + 1
    end
    return ranks
end

function direct_multirep_split_matrix(matrix::Matrix{Float64})
    iterations, chains = size(matrix)
    half = div(iterations, 2)
    out = Matrix{Float64}(undef, half, 2 * chains)
    for chain in 1:chains
        out[:, 2 * chain - 1] .= matrix[1:half, chain]
        out[:, 2 * chain] .= matrix[(iterations - half + 1):iterations, chain]
    end
    return out
end

function direct_multirep_rhat_ess(matrix::Matrix{Float64})
    iterations, chains = size(matrix)
    total = iterations * chains
    means = [mean(@view matrix[:, chain]) for chain in 1:chains]
    variances = [var(Float64.(@view matrix[:, chain]); corrected = true)
        for chain in 1:chains]
    within = mean(variances)
    between = iterations * var(means; corrected = true)
    if !(isfinite(within) && isfinite(between)) || within < 0 || between < 0
        return (; rhat = NaN, ess = NaN)
    end
    if within == 0
        return (; rhat = between == 0 ? 1.0 : Inf,
            ess = between == 0 ? Float64(total) : NaN)
    end
    var_plus = ((iterations - 1) / iterations) * within + between / iterations
    rhat = sqrt(max(var_plus / within, 0.0))
    autocorrelations = Float64[]
    for lag in 1:(iterations - 1)
        autocovariance = 0.0
        for chain in 1:chains
            chain_mean = means[chain]
            lag_sum = 0.0
            for iteration in 1:(iterations - lag)
                lag_sum += (matrix[iteration, chain] - chain_mean) *
                    (matrix[iteration + lag, chain] - chain_mean)
            end
            autocovariance += lag_sum / (iterations - 1)
        end
        push!(autocorrelations, autocovariance / (chains * within))
    end
    positive_sum = 0.0
    lag = 1
    while lag <= length(autocorrelations)
        if lag == length(autocorrelations)
            autocorrelations[lag] > 0 &&
                (positive_sum += autocorrelations[lag])
            break
        end
        pair_sum = autocorrelations[lag] + autocorrelations[lag + 1]
        pair_sum > 0 || break
        positive_sum += pair_sum
        lag += 2
    end
    tau = max(1.0, 1 + 2 * positive_sum)
    return (; rhat, ess = clamp(total / tau, 1.0, Float64(total)))
end

function direct_multirep_rank_diagnostic(matrix::Matrix{Float64})
    flat = vec(matrix)
    ranks = direct_multirep_average_ranks(flat)
    n = length(flat)
    normalized = [direct_multirep_normal_quantile(
        (rank - 0.375) / (n + 0.25)) for rank in ranks]
    z = reshape(normalized, size(matrix))
    split_z = direct_multirep_split_matrix(z)
    bulk = direct_multirep_rhat_ess(split_z)
    folded = abs.(z .- median(vec(z)))
    folded_rhat = direct_multirep_rhat_ess(
        direct_multirep_split_matrix(folded)).rhat
    rank_rhat = maximum(filter(isfinite, [bulk.rhat, folded_rhat]))
    sorted_values = sort(flat)
    low_q = quantile(sorted_values, 0.05)
    high_q = quantile(sorted_values, 0.95)
    low = direct_multirep_rhat_ess(direct_multirep_split_matrix(
        Float64.(matrix .<= low_q))).ess
    high = direct_multirep_rhat_ess(direct_multirep_split_matrix(
        Float64.(matrix .>= high_q))).ess
    tail = minimum(filter(isfinite, [low, high]))
    return (;
        rank_rhat,
        folded_rank_rhat = folded_rhat,
        bulk_ess = bulk.ess,
        tail_ess = tail,
        low_tail_ess = low,
        high_tail_ess = high,
    )
end

function direct_multirep_rank_rows(fit, aligned)
    matrix = direct_multirep_aligned_matrix(aligned)
    labels = direct_multirep_aligned_labels()
    draws_per_chain = div(size(matrix, 1), length(fit.chain_acceptance_rate))
    rows = NamedTuple[]
    for parameter in axes(matrix, 2)
        chain_matrix = reshape(matrix[:, parameter], draws_per_chain,
            length(fit.chain_acceptance_rate))
        diagnostic = direct_multirep_rank_diagnostic(chain_matrix)
        push!(rows, (;
            parameter = labels[parameter],
            rank_rhat = diagnostic.rank_rhat,
            folded_rank_rhat = diagnostic.folded_rank_rhat,
            bulk_ess = diagnostic.bulk_ess,
            tail_ess = diagnostic.tail_ess,
            low_tail_ess = diagnostic.low_tail_ess,
            high_tail_ess = diagnostic.high_tail_ess,
            advisory_passed = diagnostic.rank_rhat <= DIRECT_MULTIREP_RANK_RHAT &&
                diagnostic.bulk_ess >= DIRECT_MULTIREP_RANK_ESS &&
                diagnostic.tail_ess >= DIRECT_MULTIREP_RANK_ESS,
        ))
    end
    return rows
end

function direct_multirep_sampler_summary(fit, rank_rows)
    sampler_rows = BayesianMGMFRM.sampler_diagnostics(fit)
    mcmc_rows = BayesianMGMFRM.mcmc_diagnostics(fit)
    finite_rhat = [row.rhat for row in mcmc_rows if isfinite(row.rhat)]
    finite_ess = [row.ess for row in mcmc_rows if isfinite(row.ess)]
    finite_ebfmi = [Float64(row.e_bfmi) for row in sampler_rows
        if !ismissing(row.e_bfmi) && isfinite(row.e_bfmi)]
    return (;
        n_parameters = length(fit.design.parameter_names),
        total_posterior_draws = size(fit.draws, 1),
        all_draws_and_logposterior_finite =
            all(isfinite, fit.draws) && all(isfinite, fit.log_posterior),
        acceptance_rate = fit.acceptance_rate,
        chain_acceptance_rate = fit.chain_acceptance_rate,
        n_divergences = sum(row.n_divergences for row in sampler_rows),
        n_max_treedepth = sum(ismissing(row.n_max_treedepth) ? 0 :
            row.n_max_treedepth for row in sampler_rows),
        max_classical_split_rhat = isempty(finite_rhat) ? Inf : maximum(finite_rhat),
        min_autocorrelation_ess = isempty(finite_ess) ? 0.0 : minimum(finite_ess),
        n_mcmc_warning_parameters = count(row -> row.flag !== :ok, mcmc_rows),
        min_ebfmi = isempty(finite_ebfmi) ? missing : minimum(finite_ebfmi),
        max_rank_normalized_rhat = maximum(row.rank_rhat for row in rank_rows),
        min_bulk_ess = minimum(row.bulk_ess for row in rank_rows),
        min_tail_ess = minimum(row.tail_ess for row in rank_rows),
        n_rank_advisory_warnings = count(row -> !row.advisory_passed, rank_rows),
        rank_ebfmi_advisory_passed =
            all(row -> row.advisory_passed, rank_rows) &&
            !isempty(finite_ebfmi) && minimum(finite_ebfmi) >= DIRECT_MULTIREP_EBFMI,
    )
end

function direct_multirep_sampler_gate_rows(summary, policy)
    rows = NamedTuple[]
    for rule in policy[:sampler_threshold_rows]
        metric = Symbol(as_string(rule[:metric]))
        observed = getproperty(summary, metric)
        direction = Symbol(as_string(rule[:direction]))
        threshold = rule[:threshold]
        passed = if direction === :equals
            observed == threshold
        elseif direction === :minimum
            Float64(observed) >= as_float(threshold)
        elseif direction === :maximum
            Float64(observed) <= as_float(threshold)
        else
            false
        end
        push!(rows, (;
            metric,
            observed,
            direction,
            threshold,
            passed,
            role = :frozen_primary_sampler_gate,
        ))
    end
    return rows
end

function direct_multirep_correlation(x::Vector{Float64}, y::Vector{Float64})
    centered_x = x .- mean(x)
    centered_y = y .- mean(y)
    denominator = sqrt(sum(abs2, centered_x) * sum(abs2, centered_y))
    denominator == 0 && return missing
    return sum(centered_x .* centered_y) / denominator
end

function direct_multirep_metrics(reference_values, estimate_values, labels)
    reference = Float64.(reference_values)
    estimate = Float64.(estimate_values)
    differences = estimate .- reference
    absolute = abs.(differences)
    maximum_index = argmax(absolute)
    reference_centered = reference .- mean(reference)
    slope_denominator = sum(abs2, reference_centered)
    slope = slope_denominator == 0 ? missing :
        sum(reference_centered .* (estimate .- mean(estimate))) /
        slope_denominator
    covariance = mean((reference .- mean(reference)) .*
        (estimate .- mean(estimate)))
    ccc_denominator = var(reference; corrected = false) +
        var(estimate; corrected = false) + (mean(reference) - mean(estimate))^2
    concordance = ccc_denominator == 0 ? missing :
        2 * covariance / ccc_denominator
    return (;
        n_parameters = length(reference),
        pearson_correlation = direct_multirep_correlation(reference, estimate),
        mean_abs_difference = mean(absolute),
        median_abs_difference = median(absolute),
        percentile90_abs_difference = quantile(absolute, 0.90),
        max_abs_difference = maximum(absolute),
        max_abs_difference_parameter = labels[maximum_index],
        mean_signed_difference = mean(differences),
        root_mean_square_difference = sqrt(mean(abs2, differences)),
        regression_slope = slope,
        concordance_correlation = concordance,
    )
end

function direct_multirep_rule_map(rows)
    output = Dict{Tuple{Symbol,Symbol},NamedTuple}()
    for row in rows
        output[(Symbol(as_string(row[:block])), Symbol(as_string(row[:metric])))] = (;
            direction = Symbol(as_string(row[:direction])),
            threshold = as_float(row[:threshold]),
        )
    end
    return output
end

function direct_multirep_rule_evaluation(value, rule)
    if ismissing(value) || !(value isa Real) || !isfinite(Float64(value))
        return (; passed = false, margin = missing)
    end
    observed = Float64(value)
    passed = rule.direction === :minimum ? observed >= rule.threshold :
        observed <= rule.threshold
    margin = rule.direction === :minimum ? observed - rule.threshold :
        rule.threshold - observed
    return (; passed, margin)
end

function direct_multirep_parameter_rows(aligned, tam, truth)
    rows = NamedTuple[]
    for block in DIRECT_MULTIREP_BLOCKS
        draws = getproperty(aligned, block)
        tam_block = getproperty(tam, block)
        truth_block = getproperty(truth, block)
        labels = block_labels(block, size(draws, 2))
        for parameter in axes(draws, 2)
            values = sort(Float64.(draws[:, parameter]))
            lower95 = quantile(values, 0.025)
            upper95 = quantile(values, 0.975)
            lower90 = quantile(values, 0.05)
            upper90 = quantile(values, 0.95)
            tam_estimate = tam_block.estimate[parameter]
            known_truth = truth_block[parameter]
            difference_lower90 = lower90 - tam_estimate
            difference_upper90 = upper90 - tam_estimate
            equivalence = if -0.30 <= difference_lower90 &&
                    difference_upper90 <= 0.30
                :conditional_equivalence_demonstrated
            elseif difference_lower90 > 0.30 || difference_upper90 < -0.30
                :meaningful_difference_supported
            else
                :conditional_equivalence_inconclusive
            end
            push!(rows, (;
                block,
                parameter = labels[parameter],
                package_posterior_mean = mean(values),
                package_posterior_sd = std(values),
                package_posterior_lower95 = lower95,
                package_posterior_upper95 = upper95,
                package_posterior_lower90 = lower90,
                package_posterior_upper90 = upper90,
                tam_estimate,
                tam_se = tam_block.se[parameter],
                known_truth,
                package_minus_tam = mean(values) - tam_estimate,
                package_minus_truth = mean(values) - known_truth,
                tam_minus_truth = tam_estimate - known_truth,
                tam_inside_package_interval95 =
                    lower95 <= tam_estimate <= upper95,
                truth_inside_package_interval95 =
                    lower95 <= known_truth <= upper95,
                conditional_rope90_classification = equivalence,
            ))
        end
    end
    return rows
end

function direct_multirep_block_result_rows(aligned, tam, truth,
        parameter_rows, direct_rules, recovery_rules)
    rows = NamedTuple[]
    for block in DIRECT_MULTIREP_BLOCKS
        labels = block_labels(block, size(getproperty(aligned, block), 2))
        package_mean = vec(mean(getproperty(aligned, block); dims = 1))
        tam_values = getproperty(tam, block).estimate
        truth_values = getproperty(truth, block)
        package_tam = direct_multirep_metrics(tam_values, package_mean, labels)
        package_truth = direct_multirep_metrics(truth_values, package_mean, labels)
        tam_truth = direct_multirep_metrics(truth_values, tam_values, labels)
        selected_parameters = [row for row in parameter_rows if row.block == block]
        interval_rate = mean(row.tam_inside_package_interval95
            for row in selected_parameters)
        interval_count = count(row -> row.tam_inside_package_interval95,
            selected_parameters)
        truth_interval_rate = mean(row.truth_inside_package_interval95
            for row in selected_parameters)
        direct_values = Dict(
            :pearson_correlation => package_tam.pearson_correlation,
            :mean_abs_difference => package_tam.mean_abs_difference,
            :max_abs_difference => package_tam.max_abs_difference,
            :tam_inside_package_interval95_rate => interval_rate,
        )
        direct_metric_rows = [begin
            rule = direct_rules[(block, metric)]
            evaluation = direct_multirep_rule_evaluation(
                direct_values[metric], rule)
            (;
                metric,
                observed = direct_values[metric],
                direction = rule.direction,
                threshold = rule.threshold,
                margin = evaluation.margin,
                passed = evaluation.passed,
            )
        end for metric in (:pearson_correlation, :mean_abs_difference,
            :max_abs_difference, :tam_inside_package_interval95_rate)]
        function recovery_metric_rows(metrics, estimator)
            return [begin
                rule = recovery_rules[(block, metric)]
                observed = getproperty(metrics, metric)
                evaluation = direct_multirep_rule_evaluation(observed, rule)
                (;
                    estimator,
                    metric,
                    observed,
                    direction = rule.direction,
                    threshold = rule.threshold,
                    margin = evaluation.margin,
                    passed = evaluation.passed,
                )
            end for metric in (:pearson_correlation,
                :mean_abs_difference, :max_abs_difference)]
        end
        package_recovery = recovery_metric_rows(package_truth, :package)
        tam_recovery = recovery_metric_rows(tam_truth, :tam)
        package_recovery_passed = all(row -> row.passed, package_recovery)
        tam_recovery_passed = all(row -> row.passed, tam_recovery)
        triangle_class = package_recovery_passed && tam_recovery_passed ?
            :both_recover : package_recovery_passed ? :package_only :
            tam_recovery_passed ? :tam_only : :neither
        rope_rows = [row for row in selected_parameters]
        push!(rows, (;
            block,
            n_parameters = package_tam.n_parameters,
            shared_data = true,
            edges_are_statistically_independent = false,
            shared_sampling_error_warning = true,
            alignment_transform =
                :center_item_rater_and_reconstruct_sum_zero_item_steps,
            package_vs_tam = package_tam,
            package_vs_truth = package_truth,
            tam_vs_truth = tam_truth,
            tam_inside_package_interval95_count = interval_count,
            tam_inside_package_interval95_rate = interval_rate,
            truth_inside_package_interval95_rate = truth_interval_rate,
            direct_metric_rows,
            direct_all_metrics_passed = all(row -> row.passed,
                direct_metric_rows),
            package_recovery_metric_rows = package_recovery,
            package_recovery_profile_passed = package_recovery_passed,
            tam_recovery_metric_rows = tam_recovery,
            tam_recovery_profile_passed = tam_recovery_passed,
            triangle_class,
            conditional_equivalence_demonstrated_count = count(row ->
                row.conditional_rope90_classification ===
                    :conditional_equivalence_demonstrated, rope_rows),
            conditional_equivalence_inconclusive_count = count(row ->
                row.conditional_rope90_classification ===
                    :conditional_equivalence_inconclusive, rope_rows),
            meaningful_difference_supported_count = count(row ->
                row.conditional_rope90_classification ===
                    :meaningful_difference_supported, rope_rows),
        ))
    end
    return rows
end

function direct_multirep_chain_stability_rows(fit, aligned, tam, truth,
        parameter_rows, direct_rules, recovery_rules)
    rows = NamedTuple[]
    draws_per_chain = div(size(fit.draws, 1), length(fit.chain_acceptance_rate))
    for chain in 1:length(fit.chain_acceptance_rate)
        indices = ((chain - 1) * draws_per_chain + 1):(chain * draws_per_chain)
        chain_aligned = (;
            item_difficulty = aligned.item_difficulty[indices, :],
            rater_severity = aligned.rater_severity[indices, :],
            item_step = aligned.item_step[indices, :],
        )
        chain_parameters = direct_multirep_parameter_rows(
            chain_aligned, tam, truth)
        block_rows = direct_multirep_block_result_rows(
            chain_aligned, tam, truth, chain_parameters,
            direct_rules, recovery_rules)
        for row in block_rows
            push!(rows, (;
                chain,
                block = row.block,
                direct_all_metrics_passed = row.direct_all_metrics_passed,
                package_vs_tam_pearson =
                    row.package_vs_tam.pearson_correlation,
                package_vs_tam_mean_abs_difference =
                    row.package_vs_tam.mean_abs_difference,
                package_vs_tam_max_abs_difference =
                    row.package_vs_tam.max_abs_difference,
                tam_inside_package_interval95_rate =
                    row.tam_inside_package_interval95_rate,
            ))
        end
    end
    return rows
end

function direct_multirep_package_constraints(aligned)
    item_sum = maximum(abs.(vec(sum(aligned.item_difficulty; dims = 2))))
    rater_sum = maximum(abs.(vec(sum(aligned.rater_severity; dims = 2))))
    n_items = size(aligned.item_difficulty, 2)
    n_steps = div(size(aligned.item_step, 2), n_items)
    step_sum = 0.0
    for item in 1:n_items
        columns = ((item - 1) * n_steps + 1):(item * n_steps)
        step_sum = max(step_sum,
            maximum(abs.(vec(sum(aligned.item_step[:, columns]; dims = 2)))))
    end
    return (;
        item_sum_max_abs = item_sum,
        rater_sum_max_abs = rater_sum,
        item_step_sum_max_abs = step_sum,
        tolerance = 1.0e-10,
        passed = item_sum <= 1.0e-10 && rater_sum <= 1.0e-10 &&
            step_sum <= 1.0e-10,
    )
end

function direct_multirep_file_rows(directory::AbstractString;
        exclude = Set{String}())
    rows = NamedTuple[]
    for path in sort(filter(isfile, readdir(directory; join = true)))
        basename(path) in exclude && continue
        push!(rows, (;
            path = relpath(path, ROOT),
            bytes = filesize(path),
            sha256 = file_sha256(path),
        ))
    end
    return rows
end

function direct_multirep_manifest_fingerprint(rows)
    text = join([string(row.path, '|', row.bytes, '|', row.sha256)
        for row in rows], "\n")
    return bytes2hex(sha256(text))
end

function direct_multirep_write_raw_json(path::AbstractString, value)
    write_artifact(path, value)
    return path
end

function direct_multirep_run_job(parsed, n_persons::Int, replication::Int)
    baseline = direct_multirep_checked_artifact(parsed.baseline, BASELINE_SCHEMA)
    policy = direct_multirep_checked_artifact(
        parsed.policy, DIRECT_MULTIREP_POLICY_SCHEMA)
    refinement = direct_multirep_checked_artifact(
        parsed.refinement, DIRECT_MULTIREP_REFINEMENT_SCHEMA)
    recovery_policy = direct_multirep_checked_artifact(
        parsed.recovery_policy, DIRECT_MULTIREP_RECOVERY_POLICY_SCHEMA)
    as_bool(refinement[:summary][:frozen_primary_gate_unchanged]) ||
        error("frozen primary gate integrity failed")
    as_bool(refinement[:summary][:direct_multireplication_execution_completed]) &&
        error("refinement unexpectedly records completed execution")
    as_string(refinement[:source_artifacts][:frozen_policy_sha256]) ==
        file_sha256(parsed.policy) || error("frozen policy hash mismatch")
    as_string(refinement[:source_artifacts][:baseline_sha256]) ==
        file_sha256(parsed.baseline) || error("baseline hash mismatch")
    as_string(refinement[:source_artifacts][:recovery_policy_sha256]) ==
        file_sha256(parsed.recovery_policy) || error("recovery policy hash mismatch")
    attempt = direct_multirep_attempt_directory(parsed.raw_root,
        n_persons, replication, parsed.infrastructure_retry)
    job_id = direct_multirep_job_id(n_persons, replication)
    result_path = joinpath(attempt.directory, "job_result.json")
    seed_row = direct_multirep_seed_row(refinement, n_persons, replication)
    historical_baseline_seeds = Set([
        as_int(baseline[:protocol][:base_seed]),
        as_int(baseline[:protocol][:truth_seed]),
        as_int(baseline[:protocol][:response_seed]),
        20260713,
    ])
    frozen_job_seeds = Set([
        as_int(seed_row[:ability_seed]),
        as_int(seed_row[:response_seed]),
        as_int(seed_row[:package_fit_seed]),
    ])
    isempty(intersect(historical_baseline_seeds, frozen_job_seeds)) ||
        error("frozen job seed overlaps a historical baseline or pilot seed")
    retry = (;
        attempt = attempt.attempt,
        infrastructure_retry = parsed.infrastructure_retry !== nothing,
        infrastructure_retry_reason = parsed.infrastructure_retry,
    )
    cp(joinpath(ROOT, "Project.toml"),
        joinpath(attempt.directory, "Project.toml"))
    cp(joinpath(ROOT, "Manifest.toml"),
        joinpath(attempt.directory, "Manifest.toml"))
    println("job=", job_id, " attempt=", attempt.attempt,
        " stage=data_generation")
    try
        generated = direct_multirep_write_dataset(
            attempt.directory, baseline, seed_row, n_persons)
        println("job=", job_id, " stage=tam_fit")
        tam = direct_multirep_run_tam(generated.csv_path, attempt.directory)
        tam_validity = direct_multirep_tam_validity(tam,
            as_string(refinement[:tam_fit_contract][:tam_version]))
        tam_values = direct_multirep_tam_block_values(tam.parameters, baseline)
        println("job=", job_id, " stage=package_fit")
        package = direct_multirep_fit_package(generated, refinement,
            as_int(seed_row[:package_fit_seed]), parsed.progress)
        aligned = package.aligned_draws
        rank_rows = direct_multirep_rank_rows(package.fit, aligned)
        sampler_summary = direct_multirep_sampler_summary(
            package.fit, rank_rows)
        sampler_gate_rows = direct_multirep_sampler_gate_rows(
            sampler_summary, policy)
        sampler_gate_passed = all(row -> row.passed, sampler_gate_rows)
        truth_values = truth_block_values(baseline)
        parameter_rows = direct_multirep_parameter_rows(
            aligned, tam_values, truth_values)
        direct_rules = direct_multirep_rule_map(policy[:direct_threshold_rows])
        recovery_rules = direct_multirep_rule_map(
            refinement[:secondary_recovery_qualifier][:threshold_rows])
        block_rows = direct_multirep_block_result_rows(
            aligned, tam_values, truth_values, parameter_rows,
            direct_rules, recovery_rules)
        chain_rows = direct_multirep_chain_stability_rows(package.fit,
            aligned, tam_values, truth_values, parameter_rows,
            direct_rules, recovery_rules)
        constraints = direct_multirep_package_constraints(aligned)
        draws_path = direct_multirep_write_draws(
            joinpath(attempt.directory, "package_draws.csv"), package.fit)
        aligned_path = direct_multirep_write_aligned_draws(
            joinpath(attempt.directory, "package_aligned_draws.csv"),
            package.fit, aligned)
        direct_multirep_write_raw_json(
            joinpath(attempt.directory, "package_sampler_rows.json"),
            BayesianMGMFRM.sampler_diagnostics(package.fit))
        direct_multirep_write_raw_json(
            joinpath(attempt.directory, "package_mcmc_rows.json"),
            BayesianMGMFRM.mcmc_diagnostics(package.fit))
        direct_multirep_write_raw_json(
            joinpath(attempt.directory, "package_rank_rows.json"), rank_rows)
        direct_multirep_write_raw_json(
            joinpath(attempt.directory, "package_parameter_rows.json"),
            parameter_rows)
        raw_rows = direct_multirep_file_rows(attempt.directory;
            exclude = Set(["job_result.json"]))
        result = (;
            schema = DIRECT_MULTIREP_JOB_SCHEMA,
            job_id,
            n_persons,
            replication,
            attempt = attempt.attempt,
            execution_completed = true,
            engine_failure = false,
            retry,
            protocol = (;
                generator =
                    "scripts/generate_mgmfrm_tam_direct_agreement_multireplication.jl",
                generator_source_sha256 = file_sha256(@__FILE__),
                baseline_sha256 = file_sha256(parsed.baseline),
                frozen_policy_sha256 = file_sha256(parsed.policy),
                refinement_sha256 = file_sha256(parsed.refinement),
                recovery_policy_sha256 = file_sha256(parsed.recovery_policy),
                truth_sha256 = as_string(baseline[:checksums][:truth_sha256]),
                ability_seed = as_int(seed_row[:ability_seed]),
                response_seed = as_int(seed_row[:response_seed]),
                package_fit_seed = as_int(seed_row[:package_fit_seed]),
            ),
            data = (;
                n_observations = generated.n_observations,
                category_counts = generated.category_counts,
                all_categories_observed = generated.all_categories_observed,
                input_csv_sha256 = generated.csv_sha256,
                package_input_csv_sha256 = generated.csv_sha256,
                tam_input_csv_sha256 = generated.csv_sha256,
                identical_package_tam_input = true,
                abilities_sha256 = generated.abilities_sha256,
                dataset_truth_sha256 = generated.dataset_truth_sha256,
            ),
            tam_validity,
            package = (;
                n_parameters = length(package.design.parameter_names),
                total_draws = size(package.fit.draws, 1),
                draws_sha256 = file_sha256(draws_path),
                aligned_draws_sha256 = file_sha256(aligned_path),
                constraints,
                sampler_summary,
                sampler_gate_rows,
                frozen_sampler_gate_passed = sampler_gate_passed,
                rank_ebfmi_advisory_passed =
                    sampler_summary.rank_ebfmi_advisory_passed,
            ),
            parameter_rows,
            block_result_rows = block_rows,
            chain_stability_rows = chain_rows,
            all_chain_block_decisions_match_pooled = all(begin
                pooled = only(row for row in block_rows if row.block == chain.block)
                chain.direct_all_metrics_passed == pooled.direct_all_metrics_passed
            end for chain in chain_rows),
            protocol_alignment_valid = generated.all_categories_observed &&
                tam_validity.passed && constraints.passed &&
                generated.csv_sha256 == file_sha256(generated.csv_path),
            all_direct_blocks_passed =
                all(row -> row.direct_all_metrics_passed, block_rows),
            raw_file_manifest_rows = raw_rows,
            raw_file_manifest_sha256 = direct_multirep_manifest_fingerprint(raw_rows),
        )
        write_artifact(result_path, result)
        pointer = (;
            schema =
                "bayesianmgmfrm.mgmfrm_tam_direct_agreement_selected_attempt.v1",
            job_id,
            selected_attempt = attempt.attempt,
            selected_job_result = relpath(result_path, ROOT),
            selected_job_result_sha256 = file_sha256(result_path),
            infrastructure_retry_reason = parsed.infrastructure_retry,
        )
        write_artifact(attempt.selected, pointer)
        println("job=", job_id, " stage=complete sampler_pass=",
            sampler_gate_passed, " tam_valid=", tam_validity.passed,
            " direct_blocks_pass=", result.all_direct_blocks_passed)
        return result
    catch err
        failure = (;
            schema = DIRECT_MULTIREP_JOB_SCHEMA,
            job_id,
            n_persons,
            replication,
            attempt = attempt.attempt,
            execution_completed = false,
            engine_failure = true,
            retry,
            error_type = Symbol(nameof(typeof(err))),
            error_message = sprint(showerror, err),
            protocol = (;
                generator =
                    "scripts/generate_mgmfrm_tam_direct_agreement_multireplication.jl",
                generator_source_sha256 = file_sha256(@__FILE__),
                baseline_sha256 = file_sha256(parsed.baseline),
                frozen_policy_sha256 = file_sha256(parsed.policy),
                refinement_sha256 = file_sha256(parsed.refinement),
                recovery_policy_sha256 = file_sha256(parsed.recovery_policy),
                ability_seed = as_int(seed_row[:ability_seed]),
                response_seed = as_int(seed_row[:response_seed]),
                package_fit_seed = as_int(seed_row[:package_fit_seed]),
            ),
            raw_file_manifest_rows = direct_multirep_file_rows(
                attempt.directory; exclude = Set(["job_result.json"])),
        )
        write_artifact(result_path, failure)
        pointer = (;
            schema =
                "bayesianmgmfrm.mgmfrm_tam_direct_agreement_selected_attempt.v1",
            job_id,
            selected_attempt = attempt.attempt,
            selected_job_result = relpath(result_path, ROOT),
            selected_job_result_sha256 = file_sha256(result_path),
            infrastructure_retry_reason = parsed.infrastructure_retry,
        )
        write_artifact(attempt.selected, pointer)
        println("job=", job_id, " stage=failed error=", sprint(showerror, err))
        return failure
    end
end

function direct_multirep_load_selected_jobs(raw_root::AbstractString)
    jobs = Any[]
    pointer_rows = NamedTuple[]
    for n_persons in DIRECT_MULTIREP_PERSON_COUNTS,
            replication in 1:DIRECT_MULTIREP_REPLICATIONS
        pointer_path = direct_multirep_selected_path(
            raw_root, n_persons, replication)
        isfile(pointer_path) || error("selected attempt missing: $pointer_path")
        pointer = load_json(pointer_path)
        result_path = joinpath(ROOT, as_string(pointer[:selected_job_result]))
        isfile(result_path) || error("selected job result missing: $result_path")
        file_sha256(result_path) ==
            as_string(pointer[:selected_job_result_sha256]) ||
            error("selected job result hash mismatch")
        result = load_json(result_path)
        as_string(result[:schema]) == DIRECT_MULTIREP_JOB_SCHEMA ||
            error("unexpected job result schema")
        push!(jobs, result)
        push!(pointer_rows, (;
            job_id = as_string(pointer[:job_id]),
            pointer_path = relpath(pointer_path, ROOT),
            pointer_sha256 = file_sha256(pointer_path),
            result_path = relpath(result_path, ROOT),
            result_sha256 = file_sha256(result_path),
            selected_attempt = as_int(pointer[:selected_attempt]),
        ))
    end
    return (; jobs, pointer_rows)
end

function direct_multirep_summary_rows(jobs)
    rows = NamedTuple[]
    for n_persons in DIRECT_MULTIREP_PERSON_COUNTS,
            block in DIRECT_MULTIREP_BLOCKS
        selected = [(job = job, row = only(row for row in job[:block_result_rows]
                if Symbol(as_string(row[:block])) == block))
            for job in jobs if as_int(job[:n_persons]) == n_persons &&
                as_bool(job[:execution_completed])]
        length(selected) == DIRECT_MULTIREP_REPLICATIONS ||
            error("expected five completed rows for $n_persons/$block")
        direct_passes = count(pair ->
            as_bool(pair.row[:direct_all_metrics_passed]), selected)
        package_recovery_passes = count(pair ->
            as_bool(pair.row[:package_recovery_profile_passed]), selected)
        tam_recovery_passes = count(pair ->
            as_bool(pair.row[:tam_recovery_profile_passed]), selected)
        primary = n_persons == 100
        direct_primary_passed = primary && direct_passes >= 4
        package_qualifier = primary && package_recovery_passes >= 4
        tam_qualifier = primary && tam_recovery_passes >= 4
        fragility = direct_passes == 5 ? :all_five_pass :
            direct_passes == 4 ? :threshold_fragile_four_of_five :
            :primary_fail
        push!(rows, (;
            n_persons,
            block,
            n_replications = length(selected),
            direct_n_passed = direct_passes,
            direct_pass_rate = direct_passes / length(selected),
            direct_primary_block_passed = direct_primary_passed,
            direct_fragility_class = fragility,
            package_truth_n_passed = package_recovery_passes,
            package_truth_pass_rate =
                package_recovery_passes / length(selected),
            package_recovery_qualifier_passed = package_qualifier,
            tam_truth_n_passed = tam_recovery_passes,
            tam_truth_pass_rate = tam_recovery_passes / length(selected),
            tam_recovery_qualifier_passed = tam_qualifier,
            triangle_classification = package_qualifier && tam_qualifier ?
                :both_recover : package_qualifier ? :package_only :
                tam_qualifier ? :tam_only : :neither,
            median_package_vs_tam_pearson = median(as_float(
                pair.row[:package_vs_tam][:pearson_correlation])
                for pair in selected),
            minimum_package_vs_tam_pearson = minimum(as_float(
                pair.row[:package_vs_tam][:pearson_correlation])
                for pair in selected),
            median_package_vs_tam_mean_abs_difference = median(as_float(
                pair.row[:package_vs_tam][:mean_abs_difference])
                for pair in selected),
            maximum_package_vs_tam_mean_abs_difference = maximum(as_float(
                pair.row[:package_vs_tam][:mean_abs_difference])
                for pair in selected),
            median_package_vs_tam_max_abs_difference = median(as_float(
                pair.row[:package_vs_tam][:max_abs_difference])
                for pair in selected),
            maximum_package_vs_tam_max_abs_difference = maximum(as_float(
                pair.row[:package_vs_tam][:max_abs_difference])
                for pair in selected),
            minimum_tam_inside_package_interval95_rate = minimum(as_float(
                pair.row[:tam_inside_package_interval95_rate])
                for pair in selected),
            primary_gate_row = primary,
        ))
    end
    return rows
end

function direct_multirep_failure_rows(jobs, summaries)
    rows = NamedTuple[]
    for job in jobs
        if !as_bool(job[:execution_completed])
            push!(rows, (;
                job_id = as_string(job[:job_id]),
                failure = :engine_failure,
                detail = as_string(job[:error_message]),
            ))
            continue
        end
        !as_bool(job[:protocol_alignment_valid]) && push!(rows, (;
            job_id = as_string(job[:job_id]),
            failure = :protocol_or_alignment_failure,
            detail = :protocol_alignment_valid_false,
        ))
        !as_bool(job[:tam_validity][:passed]) && push!(rows, (;
            job_id = as_string(job[:job_id]),
            failure = :tam_engine_or_numerical_failure,
            detail = :tam_validity_false,
        ))
        !as_bool(job[:package][:frozen_sampler_gate_passed]) && push!(rows, (;
            job_id = as_string(job[:job_id]),
            failure = :package_sampler_confirmatory_failure,
            detail = :frozen_sampler_gate_false,
        ))
        !as_bool(job[:package][:rank_ebfmi_advisory_passed]) && push!(rows, (;
            job_id = as_string(job[:job_id]),
            failure = :sampler_advisory_warning,
            detail = :rank_or_ebfmi_advisory_false,
        ))
    end
    for row in summaries
        as_bool(row.direct_primary_block_passed) || !as_bool(row.primary_gate_row) ||
            push!(rows, (;
                job_id = :primary_aggregate,
                failure = :multireplication_aggregation_failure,
                detail = Symbol(string(row.block, "_fewer_than_four_of_five")),
            ))
        as_string(row.direct_fragility_class) ==
            "threshold_fragile_four_of_five" && push!(rows, (;
                job_id = :primary_aggregate,
                failure = :threshold_fragile_pass,
                detail = row.block,
            ))
    end
    return rows
end

function direct_multirep_scientific_interpretation(primary_passed::Bool,
        package_recovery::Bool, tam_recovery::Bool, computation_valid::Bool,
        protocol_valid::Bool)
    !protocol_valid && return :protocol_invalid_no_scientific_conclusion
    !computation_valid && return :computationally_inconclusive
    if !primary_passed
        return package_recovery && tam_recovery ?
            :direct_nonagreement_despite_both_recovery_profiles :
            :direct_nonagreement_with_incomplete_recovery_support
    end
    return package_recovery && tam_recovery ?
        :local_numerical_agreement_with_both_recovery_profiles :
        package_recovery ?
        :local_numerical_agreement_with_package_only_recovery_support :
        tam_recovery ?
        :local_numerical_agreement_with_tam_only_recovery_support :
        :local_numerical_agreement_without_recovery_support
end

function direct_multirep_aggregate(parsed)
    baseline = direct_multirep_checked_artifact(parsed.baseline, BASELINE_SCHEMA)
    policy = direct_multirep_checked_artifact(
        parsed.policy, DIRECT_MULTIREP_POLICY_SCHEMA)
    refinement = direct_multirep_checked_artifact(
        parsed.refinement, DIRECT_MULTIREP_REFINEMENT_SCHEMA)
    recovery_policy = direct_multirep_checked_artifact(
        parsed.recovery_policy, DIRECT_MULTIREP_RECOVERY_POLICY_SCHEMA)
    loaded = direct_multirep_load_selected_jobs(parsed.raw_root)
    jobs = loaded.jobs
    length(jobs) == 10 || error("expected 10 selected jobs")
    all_completed = all(job -> as_bool(job[:execution_completed]), jobs)
    summaries = all_completed ? direct_multirep_summary_rows(jobs) : NamedTuple[]
    primary_rows = [row for row in summaries if row.primary_gate_row]
    protocol_valid = all_completed && all(job ->
        as_bool(job[:protocol_alignment_valid]), jobs)
    tam_valid = all_completed && all(job ->
        as_bool(job[:tam_validity][:passed]), jobs)
    sampler_valid = all_completed && all(job ->
        as_bool(job[:package][:frozen_sampler_gate_passed]), jobs)
    computation_valid = all_completed && tam_valid && sampler_valid
    primary_direct_passed = computation_valid && protocol_valid &&
        length(primary_rows) == 3 &&
        all(row -> row.direct_primary_block_passed, primary_rows)
    package_recovery = length(primary_rows) == 3 &&
        all(row -> row.package_recovery_qualifier_passed, primary_rows)
    tam_recovery = length(primary_rows) == 3 &&
        all(row -> row.tam_recovery_qualifier_passed, primary_rows)
    interpretation = direct_multirep_scientific_interpretation(
        primary_direct_passed, package_recovery, tam_recovery,
        computation_valid, protocol_valid)
    primary_policy_decision = protocol_valid && computation_valid ?
        (primary_direct_passed ? :pass : :fail) : :not_passed
    failure_rows = direct_multirep_failure_rows(jobs, summaries)
    raw_manifest_rows = NamedTuple[]
    for job in jobs
        result_path = joinpath(ROOT, only(row.result_path
            for row in loaded.pointer_rows if row.job_id == as_string(job[:job_id])))
        push!(raw_manifest_rows, (;
            job_id = Symbol(as_string(job[:job_id])),
            path = relpath(result_path, ROOT),
            bytes = filesize(result_path),
            sha256 = file_sha256(result_path),
            role = :job_result,
        ))
        if haskey(job, :raw_file_manifest_rows)
            for row in job[:raw_file_manifest_rows]
                push!(raw_manifest_rows, (;
                    job_id = Symbol(as_string(job[:job_id])),
                    path = as_string(row[:path]),
                    bytes = as_int(row[:bytes]),
                    sha256 = as_string(row[:sha256]),
                    role = :raw_attempt_file,
                ))
            end
        end
    end
    decision = primary_direct_passed ?
        :record_frozen_direct_gate_pass_keep_broad_claims_blocked :
        computation_valid && protocol_valid ?
        :record_frozen_direct_gate_fail_keep_broad_claims_blocked :
        :record_inconclusive_execution_keep_all_claims_blocked
    safe_wording = primary_direct_passed ?
        :locally_frozen_synthetic_fully_crossed_unit_discrimination_mfrm_pcm_runs_met_the_numerical_agreement_rule_against_tam :
        interpretation === :protocol_invalid_no_scientific_conclusion ?
        :execution_was_protocol_invalid_and_supports_no_agreement_conclusion :
        interpretation === :computationally_inconclusive ?
        :scheduled_computation_requirements_failed_and_numerical_agreement_is_inconclusive :
        :aligned_summaries_did_not_meet_the_frozen_numerical_agreement_rule
    artifact = (;
        schema = DIRECT_MULTIREP_RESULT_SCHEMA,
        family = :mfrm,
        scope = :tam_direct_package_vs_tam_multireplication_execution,
        status = :direct_multireplication_execution_recorded,
        decision,
        local_only = true,
        externally_preregistered = false,
        external_software = :tam,
        tam_overlap_direct_evaluation_completed = all_completed,
        tam_overlap_direct_gate_passed = primary_direct_passed,
        package_wide_validation_completed = false,
        external_software_validation_completed = false,
        public_claim_release_allowed = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = (;
            protocol_id =
                :mgmfrm_tam_direct_agreement_multireplication_v1,
            generator =
                "scripts/generate_mgmfrm_tam_direct_agreement_multireplication.jl",
            generator_source_sha256 = file_sha256(@__FILE__),
            baseline_artifact = relpath(parsed.baseline, ROOT),
            baseline_artifact_sha256 = file_sha256(parsed.baseline),
            frozen_policy_artifact = relpath(parsed.policy, ROOT),
            frozen_policy_artifact_sha256 = file_sha256(parsed.policy),
            refinement_artifact = relpath(parsed.refinement, ROOT),
            refinement_artifact_sha256 = file_sha256(parsed.refinement),
            recovery_policy_artifact = relpath(parsed.recovery_policy, ROOT),
            recovery_policy_artifact_sha256 =
                file_sha256(parsed.recovery_policy),
            frozen_primary_gate_fingerprint_sha256 = as_string(
                refinement[:frozen_primary_gate_fingerprint_sha256]),
            direct_threshold_table_sha256 =
                as_string(refinement[:direct_threshold_table_sha256]),
            sampler_threshold_table_sha256 =
                as_string(refinement[:sampler_threshold_table_sha256]),
            inherited_thresholds_unchanged = true,
            person_counts = collect(DIRECT_MULTIREP_PERSON_COUNTS),
            replications_per_person_count = DIRECT_MULTIREP_REPLICATIONS,
            primary_person_count = 100,
            n40_role = :secondary_sample_size_stress_condition,
            n100_role = :primary_confirmatory_condition,
            sampler_gate_scope = :all_ten_scheduled_package_fits,
            failed_fit_disposition = :counts_as_failure_no_exclusion,
            replacement_seed_allowed = false,
        ),
        tested_scope = (;
            tested_family = :mfrm,
            tested_model = :unidimensional_many_facet_rasch_partial_credit,
            dimensions = 1,
            item_discrimination_fixed = 1.0,
            rater_consistency_fixed = 1.0,
            q_matrix_used = false,
            source_scale_1_7_used = false,
            generalized_parameter_blocks_evaluated = Symbol[],
            scalar_gmfrm_evaluated = false,
            fixed_q_mgmfrm_evaluated = false,
            uto_2021_model_evaluated = false,
            uto_2021_relationship =
                :constrained_rasch_pcm_lineage_only_not_direct_validation,
            result_transfer_to_gmfrm_or_mgmfrm_allowed = false,
            facets_or_conquest_executed = false,
            construct_or_population_validity_assessed = false,
        ),
        policy_integrity = (;
            frozen_policy_hash_matches_refinement =
                file_sha256(parsed.policy) == as_string(
                    refinement[:source_artifacts][:frozen_policy_sha256]),
            baseline_hash_matches_refinement =
                file_sha256(parsed.baseline) == as_string(
                    refinement[:source_artifacts][:baseline_sha256]),
            recovery_policy_hash_matches_refinement =
                file_sha256(parsed.recovery_policy) == as_string(
                    refinement[:source_artifacts][:recovery_policy_sha256]),
            refinement_records_gate_unchanged = as_bool(
                refinement[:summary][:frozen_primary_gate_unchanged]),
            pilot_excluded_from_confirmatory_denominator = true,
        ),
        selected_attempt_rows = loaded.pointer_rows,
        replication_rows = jobs,
        scenario_block_summary_rows = summaries,
        failure_rows,
        raw_archive_manifest = (;
            root = relpath(parsed.raw_root, ROOT),
            local_ignored_artifact = true,
            n_files = length(raw_manifest_rows),
            file_rows = raw_manifest_rows,
            manifest_sha256 = direct_multirep_manifest_fingerprint(
                [(path = row.path, bytes = row.bytes, sha256 = row.sha256)
                    for row in raw_manifest_rows]),
        ),
        outcome = (;
            primary_policy_decision,
            scientific_interpretation = interpretation,
            primary_direct_gate_passed = primary_direct_passed,
            package_recovery_qualifier_passed = package_recovery,
            tam_recovery_qualifier_passed = tam_recovery,
            both_estimators_recovery_qualifier_passed =
                package_recovery && tam_recovery,
            fragility_by_block = [(;
                block = row.block,
                fragility_class = row.direct_fragility_class,
                direct_n_passed = row.direct_n_passed,
            ) for row in primary_rows],
            safe_local_wording = safe_wording,
            prohibited_regardless_of_outcome = [
                :bayesianmgmfrm_validated_by_tam,
                :estimators_are_equivalent,
                :uto_2021_reproduced_or_externally_validated,
                :gmfrm_or_mgmfrm_validated,
                :construct_population_fairness_or_performance_claim,
            ],
        ),
        claim_limits = [
            :locally_frozen_not_externally_preregistered,
            :synthetic_known_truth_only,
            :single_fixed_truth_profile,
            :fully_crossed_five_item_four_rater_four_category_design_only,
            :unidimensional_unit_discrimination_unit_consistency_mfrm_pcm_only,
            :tam_version_and_configuration_specific,
            :parameter_summary_concordance_only,
            :interval_inclusion_is_not_coverage_or_equivalence,
            :five_replication_pass_rate_is_imprecise,
            :agreement_does_not_establish_accuracy_or_construct_validity,
            :no_sparse_unbalanced_or_real_data_validity,
            :no_facets_or_conquest_evidence,
            :no_gmfrm_mgmfrm_or_uto_2021_generalization,
            :independent_post_execution_review_pending,
            :no_public_claim_release,
        ],
        summary = (;
            passed = length(jobs) == 10 &&
                length(loaded.pointer_rows) == 10 &&
                length(summaries) == 6 &&
                as_bool(refinement[:summary][:frozen_primary_gate_unchanged]),
            execution_completed = all_completed,
            all_protocol_alignment_valid = protocol_valid,
            all_tam_executions_valid = tam_valid,
            all_package_sampler_gates_passed = sampler_valid,
            primary_direct_gate_passed = primary_direct_passed,
            primary_policy_decision,
            scientific_interpretation = interpretation,
            package_recovery_qualifier_passed = package_recovery,
            tam_recovery_qualifier_passed = tam_recovery,
            n_selected_jobs = length(jobs),
            n_primary_block_rows = length(primary_rows),
            n_primary_block_rows_passed = count(row ->
                row.direct_primary_block_passed, primary_rows),
            n_failure_rows = length(failure_rows),
            external_software_validation_completed = false,
            public_claim_release_allowed = false,
            next_gate =
                :generate_independent_post_execution_tam_direct_review_packet,
        ),
    )
    write_artifact(parsed.output, artifact)
    println("wrote ", relpath(parsed.output, ROOT))
    println("artifact_pass=", artifact.summary.passed,
        " primary_decision=", artifact.outcome.primary_policy_decision,
        " interpretation=", artifact.outcome.scientific_interpretation,
        " failures=", artifact.summary.n_failure_rows)
    return artifact
end

function direct_multirep_main(args)
    parsed = direct_multirep_parse_args(args)
    if parsed.job !== nothing
        direct_multirep_run_job(parsed,
            parsed.job.n_persons, parsed.job.replication)
        return nothing
    elseif parsed.aggregate_only
        direct_multirep_aggregate(parsed)
        return nothing
    end
    for n_persons in DIRECT_MULTIREP_PERSON_COUNTS,
            replication in 1:DIRECT_MULTIREP_REPLICATIONS
        direct_multirep_run_job(parsed, n_persons, replication)
    end
    direct_multirep_aggregate(parsed)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && direct_multirep_main(ARGS)
