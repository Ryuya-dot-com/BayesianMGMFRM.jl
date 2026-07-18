#!/usr/bin/env julia

using JSON3
using SHA
using Statistics
using TOML

import BayesianMGMFRM

include(joinpath(@__DIR__, "generate_mgmfrm_tam_overlap_execution_review.jl"))

const DIRECT_DEFAULT_BASELINE = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_overlap_baseline.json")
const DIRECT_DEFAULT_TAM_REVIEW = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_overlap_execution_review.json")
const DIRECT_DEFAULT_OUTPUT = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_direct_estimate_pilot.json")
const DIRECT_TAM_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_overlap_execution_review.v1"
const DIRECT_SEED = 20260713
const DIRECT_DRAWS = 400
const DIRECT_WARMUP = 400
const DIRECT_CHAINS = 4

function direct_usage()
    return """
    Fit the package MFRM to the committed TAM overlap data and record a direct
    estimate-comparison pilot.

    The package fit uses AdvancedHMC/NUTS. Item and rater effects are centered,
    and partial-credit steps are reconstructed under the same within-item
    sum constraint as the expanded TAM facet table. The result is descriptive
    pilot evidence only; direct-agreement thresholds are not retrofitted.

    Usage:
      julia --project=. scripts/generate_mgmfrm_tam_direct_estimate_pilot.jl [--baseline PATH] [--tam-review PATH] [--output PATH]
    """
end

function direct_parse_args(args)
    baseline = DIRECT_DEFAULT_BASELINE
    tam_review = DIRECT_DEFAULT_TAM_REVIEW
    output = DIRECT_DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--baseline"
            index < length(args) || error("--baseline requires a path")
            baseline = abspath(args[index + 1])
            index += 2
        elseif arg == "--tam-review"
            index < length(args) || error("--tam-review requires a path")
            tam_review = abspath(args[index + 1])
            index += 2
        elseif arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(direct_usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; baseline, tam_review, output)
end

function direct_data(baseline)
    observations = baseline[:observations]
    return BayesianMGMFRM.FacetData((;
            examinee = Int.(observations[:person]),
            rater = Int.(observations[:rater]),
            item = Int.(observations[:item]),
            score = Int.(observations[:score]),
        );
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

function centered_rows(matrix::AbstractMatrix{<:Real})
    output = Float64.(matrix)
    output .-= mean(output; dims = 2)
    return output
end

function package_block_draws(fit)
    design = fit.design
    n_draws = size(fit.draws, 1)
    n_raters = length(design.spec.data.rater_levels)
    n_items = length(design.spec.data.item_levels)
    n_steps = length(design.spec.data.category_levels) - 1
    free_steps = n_steps - 1

    rater = zeros(Float64, n_draws, n_raters)
    rater[:, 2:end] .= fit.draws[:, design.blocks[:rater]]
    item = zeros(Float64, n_draws, n_items)
    item[:, 2:end] .= fit.draws[:, design.blocks[:item]]
    steps = zeros(Float64, n_draws, n_items * n_steps)
    free = fit.draws[:, design.blocks[:thresholds]]
    for item_index in 1:n_items
        free_range = ((item_index - 1) * free_steps + 1):(item_index * free_steps)
        step_range = ((item_index - 1) * n_steps + 1):(item_index * n_steps)
        steps[:, first(step_range):(last(step_range) - 1)] .= free[:, free_range]
        steps[:, last(step_range)] .= -sum(free[:, free_range]; dims = 2)
    end
    return (;
        item_difficulty = centered_rows(item),
        rater_severity = centered_rows(rater),
        item_step = steps,
    )
end

function tam_block_values(review, baseline)
    parameters = [(;
        parameter = as_string(row[:parameter]),
        facet = as_string(row[:facet]),
        xsi = as_float(row[:xsi]),
        se_xsi = as_float(row[:se_xsi]),
    ) for row in review[:tam_parameter_rows]]
    truth = baseline[:truth]
    n_items = length(truth[:item_difficulty])
    n_raters = length(truth[:rater_severity])
    n_steps = length(first(truth[:item_steps]))
    item_rows = value_by_parameter(parameters, "item")
    rater_rows = value_by_parameter(parameters, "rater")
    step_rows = value_by_parameter(parameters, "item:step")
    return (;
        item_difficulty = centered(
            [item_rows[string(item)] for item in 1:n_items]),
        rater_severity = centered(
            [rater_rows[string("rater", rater)] for rater in 1:n_raters]),
        item_step = [step_rows[step_parameter_name(item, step)]
            for item in 1:n_items for step in 1:n_steps],
    )
end

function truth_block_values(baseline)
    truth = baseline[:truth]
    return (;
        item_difficulty = centered(Float64.(truth[:item_difficulty])),
        rater_severity = centered(Float64.(truth[:rater_severity])),
        item_step = [as_float(value)
            for steps in truth[:item_steps] for value in steps],
    )
end

function block_labels(block::Symbol, n_parameters::Int)
    if block === :item_difficulty
        return ["item[$index]" for index in 1:n_parameters]
    elseif block === :rater_severity
        return ["rater[$index]" for index in 1:n_parameters]
    end
    n_steps = 3
    return ["item[$item]:step[$step]"
        for item in 1:div(n_parameters, n_steps) for step in 1:n_steps]
end

function parameter_rows(package_draws, tam_values, truth_values)
    rows = NamedTuple[]
    for block in (:item_difficulty, :rater_severity, :item_step)
        draws = getproperty(package_draws, block)
        tam = getproperty(tam_values, block)
        truth = getproperty(truth_values, block)
        labels = block_labels(block, size(draws, 2))
        for index in axes(draws, 2)
            values = sort(Float64.(draws[:, index]))
            lower = quantile(values, 0.025)
            upper = quantile(values, 0.975)
            push!(rows, (;
                block,
                parameter = labels[index],
                package_posterior_mean = mean(values),
                package_posterior_sd = std(values),
                package_posterior_lower95 = lower,
                package_posterior_upper95 = upper,
                tam_estimate = tam[index],
                known_truth = truth[index],
                tam_inside_package_interval95 = lower <= tam[index] <= upper,
                truth_inside_package_interval95 = lower <= truth[index] <= upper,
            ))
        end
    end
    return rows
end

function direct_comparison_rows(package_draws, tam_values, truth_values)
    rows = NamedTuple[]
    for block in (:item_difficulty, :rater_severity, :item_step)
        posterior_mean = vec(mean(getproperty(package_draws, block); dims = 1))
        for (target, values) in (
                (:tam_estimate, getproperty(tam_values, block)),
                (:known_truth, getproperty(truth_values, block)))
            push!(rows, comparison_summary(block, values, posterior_mean;
                adapter = :centered_item_rater_and_reconstructed_sum_zero_steps,
                interpretation = Symbol("descriptive_package_posterior_mean_vs_", target)))
        end
    end
    return rows
end

function direct_build_artifact(baseline_path::AbstractString,
        tam_review_path::AbstractString)
    baseline = load_json(baseline_path)
    as_string(baseline[:schema]) == BASELINE_SCHEMA ||
        error("unexpected baseline schema")
    tam_review = load_json(tam_review_path)
    as_string(tam_review[:schema]) == DIRECT_TAM_SCHEMA ||
        error("unexpected TAM review schema")
    data = direct_data(baseline)
    spec = BayesianMGMFRM.mfrm_spec(data; thresholds = :partial_credit)
    design = BayesianMGMFRM.getdesign(spec)
    prior = BayesianMGMFRM.MFRMPrior()
    fit = BayesianMGMFRM.fit(design;
        prior,
        backend = :advancedhmc,
        ndraws = DIRECT_DRAWS,
        warmup = DIRECT_WARMUP,
        chains = DIRECT_CHAINS,
        step_size = 0.05,
        seed = DIRECT_SEED,
        target_accept = 0.90,
        max_depth = 10,
        max_energy_error = 1000.0,
        metric = :diagonal,
        ad_backend = :ForwardDiff,
        init_jitter = 0.05,
        progress = false,
    )
    package_draws = package_block_draws(fit)
    tam_values = tam_block_values(tam_review, baseline)
    truth_values = truth_block_values(baseline)
    parameters = parameter_rows(package_draws, tam_values, truth_values)
    comparisons = direct_comparison_rows(package_draws, tam_values, truth_values)
    sampler_rows = BayesianMGMFRM.sampler_diagnostics(fit)
    mcmc_rows = BayesianMGMFRM.mcmc_diagnostics(fit)
    finite_rhat = [row.rhat for row in mcmc_rows if isfinite(row.rhat)]
    finite_ess = [row.ess for row in mcmc_rows if isfinite(row.ess)]
    n_divergences = sum(row.n_divergences for row in sampler_rows)
    n_max_treedepth = sum(ismissing(row.n_max_treedepth) ? 0 :
        row.n_max_treedepth for row in sampler_rows)
    max_rhat = isempty(finite_rhat) ? Inf : maximum(finite_rhat)
    min_ess = isempty(finite_ess) ? 0.0 : minimum(finite_ess)
    all_finite = all(isfinite, fit.draws) && all(isfinite, fit.log_posterior)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_tam_direct_estimate_pilot.v1",
        family = :mfrm,
        scope = :tam_direct_package_posterior_estimate_pilot,
        status = :direct_estimate_pilot_recorded_thresholds_not_predeclared,
        decision = :record_descriptive_direct_comparison_keep_claim_blocked,
        local_only = true,
        external_software = :tam,
        package_estimator_direct_comparison_completed = true,
        direct_agreement_thresholds_predeclared = false,
        external_software_validation_completed = false,
        public_claim_release_allowed = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = (;
            protocol_id = :mgmfrm_tam_direct_estimate_pilot_v1,
            generator = "scripts/generate_mgmfrm_tam_direct_estimate_pilot.jl",
            generator_source_sha256 = file_sha256(@__FILE__),
            baseline_artifact = relpath(baseline_path, ROOT),
            baseline_artifact_sha256 = file_sha256(baseline_path),
            tam_execution_review = relpath(tam_review_path, ROOT),
            tam_execution_review_sha256 = file_sha256(tam_review_path),
            package_fit = :BayesianMGMFRM_AdvancedHMC_NUTS,
            seed = DIRECT_SEED,
            ndraws_per_chain = DIRECT_DRAWS,
            warmup_per_chain = DIRECT_WARMUP,
            chains = DIRECT_CHAINS,
            target_accept = 0.90,
            max_depth = 10,
            metric = :diagonal,
            ad_backend = :ForwardDiff,
            prior = (; person_sd = prior.person_sd, rater_sd = prior.rater_sd,
                item_sd = prior.item_sd, step_sd = prior.step_sd),
        ),
        estimand_crosswalk = (;
            item = :center_reference_coded_package_and_tam_item_effects,
            rater = :center_reference_coded_package_and_tam_rater_effects,
            item_step = :reconstruct_last_step_as_negative_free_step_sum,
            estimator_difference =
                :package_fixed_person_bayesian_model_vs_tam_marginal_maximum_likelihood,
            equality_expected = false,
        ),
        sampler_summary = (;
            n_parameters = length(design.parameter_names),
            total_posterior_draws = size(fit.draws, 1),
            all_draws_and_logposterior_finite = all_finite,
            acceptance_rate = fit.acceptance_rate,
            chain_acceptance_rate = fit.chain_acceptance_rate,
            n_divergences,
            n_max_treedepth,
            max_classical_split_rhat = max_rhat,
            min_autocorrelation_ess = min_ess,
            n_mcmc_warning_parameters = count(row -> row.flag !== :ok, mcmc_rows),
            manuscript_diagnostic_thresholds_passed =
                n_divergences == 0 && n_max_treedepth == 0 &&
                max_rhat <= 1.01 && min_ess >= 400.0,
        ),
        parameter_rows = parameters,
        direct_comparison_rows = comparisons,
        block_interval_summary_rows = [(;
            block,
            n_parameters = count(row -> row.block == block, parameters),
            tam_inside_package_interval95_rate = mean(
                row.tam_inside_package_interval95 for row in parameters
                if row.block == block),
            truth_inside_package_interval95_rate = mean(
                row.truth_inside_package_interval95 for row in parameters
                if row.block == block),
        ) for block in (:item_difficulty, :rater_severity, :item_step)],
        claim_limits = [
            :single_dataset_direct_estimate_pilot,
            :direct_agreement_thresholds_not_predeclared,
            :package_and_tam_estimators_are_not_identical,
            :package_uses_fixed_person_parameters_tam_uses_marginal_likelihood,
            :no_facets_or_conquest_execution,
            :no_generalized_gmfrm_or_mgmfrm_external_validation,
            :no_public_claim_release,
        ],
        summary = (;
            passed = all_finite && length(parameters) == 24 &&
                length(comparisons) == 6,
            direct_estimate_pilot_completed = true,
            direct_agreement_thresholds_predeclared = false,
            sampler_diagnostics_passed =
                n_divergences == 0 && n_max_treedepth == 0 &&
                max_rhat <= 1.01 && min_ess >= 400.0,
            n_parameter_rows = length(parameters),
            n_direct_comparison_rows = length(comparisons),
            external_software_validation_completed = false,
            public_claim_release_allowed = false,
            next_gate = :freeze_direct_agreement_policy_then_run_multireplication_package_vs_tam_fits,
        ),
    )
end

function direct_main(args)
    parsed = direct_parse_args(args)
    artifact = direct_build_artifact(parsed.baseline, parsed.tam_review)
    write_artifact(parsed.output, artifact)
    println("wrote ", relpath(parsed.output, ROOT))
    println(
        "passed=", artifact.summary.passed,
        " sampler_pass=", artifact.summary.sampler_diagnostics_passed,
        " max_rhat=", artifact.sampler_summary.max_classical_split_rhat,
        " min_ess=", artifact.sampler_summary.min_autocorrelation_ess,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && direct_main(ARGS)
