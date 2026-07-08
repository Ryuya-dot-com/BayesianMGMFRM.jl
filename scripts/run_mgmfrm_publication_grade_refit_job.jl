#!/usr/bin/env julia

using JSON3
using Random
using SHA
using TOML

import BayesianMGMFRM

module FoldPilotHelpers
include(joinpath(@__DIR__,
    "generate_mgmfrm_full_heldout_mcmc_refit_fold1_pilot.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_PLAN =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_pilot_plan.json")
const DEFAULT_GATE =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_gate.json")
const DEFAULT_RESULT_ROOT =
    joinpath(ROOT, "artifacts", "publication_grade_refit_pilot")

include(joinpath(@__DIR__, "local_json.jl"))

const MGMFRM_MODELS = (
    :confirmatory_mgmfrm_current_q,
    :sparse_mgmfrm_current_q,
    :construct_reviewed_revised_q_mgmfrm,
)

const REFERENCE_CONTROLS = (;
    alpha = 1.0,
    categories = [0, 1, 2],
)

function usage()
    return """
    Run one local MGMFRM publication-grade refit job.

    The runner materializes the executable side of a publication-grade pilot or
    batch plan: it selects one planned unit, fits or analytically scores it,
    writes result, diagnostic, and heldout-score artifacts, and keeps all public
    claims blocked.

    Usage:
      julia --project=. scripts/run_mgmfrm_publication_grade_refit_job.jl \\
        --execution-unit UNIT_ID [--output PATH]

    Options:
      --execution-unit ID       Required execution unit id.
      --plan PATH               Pilot or batch expansion plan fixture path.
      --pilot-plan PATH         Backward-compatible alias for --plan.
      --gate PATH               Diagnostic gate fixture path.
      --output PATH             Result artifact path.
      --diagnostics-output PATH Diagnostic artifact path.
      --heldout-output PATH     Heldout-score artifact path.
      --chains N                MCMC chains for refit jobs.
      --warmup-per-chain N      Warmup iterations per chain.
      --draws-per-chain N       Posterior draws per chain.
      --target-acceptance X     NUTS target acceptance.
      --seed N                  MCMC seed.
      --ppc-draws N             Posterior predictive check draw cap.
      --backend NAME            Currently advancedhmc.
      --sampler NAME            Currently nuts.
      --analytic-reference      Require analytic scoring for the reference unit.
      --dry-run                 Write planned artifacts without fitting/scoring.
      --progress                Show sampler progress.
    """
end

project_version() = String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))

as_string(value) = String(value)
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_float(value) = Float64(value)
as_symbol(value) = Symbol(String(value))

function parse_args(args)
    execution_unit = nothing
    plan = DEFAULT_PLAN
    gate = DEFAULT_GATE
    output = nothing
    diagnostics_output = nothing
    heldout_output = nothing
    chains = nothing
    warmup_per_chain = nothing
    draws_per_chain = nothing
    target_acceptance = nothing
    seed = nothing
    ppc_draws = 100
    backend = :advancedhmc
    sampler = :nuts
    analytic_reference = false
    dry_run = false
    progress = false

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--execution-unit"
            index < length(args) || error("--execution-unit requires an id")
            execution_unit = args[index + 1]
            index += 2
        elseif arg == "--pilot-plan"
            index < length(args) || error("--pilot-plan requires a path")
            plan = abspath(args[index + 1])
            index += 2
        elseif arg == "--plan"
            index < length(args) || error("--plan requires a path")
            plan = abspath(args[index + 1])
            index += 2
        elseif arg == "--gate"
            index < length(args) || error("--gate requires a path")
            gate = abspath(args[index + 1])
            index += 2
        elseif arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg == "--diagnostics-output"
            index < length(args) || error("--diagnostics-output requires a path")
            diagnostics_output = abspath(args[index + 1])
            index += 2
        elseif arg == "--heldout-output"
            index < length(args) || error("--heldout-output requires a path")
            heldout_output = abspath(args[index + 1])
            index += 2
        elseif arg == "--chains"
            index < length(args) || error("--chains requires an integer")
            chains = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--warmup-per-chain"
            index < length(args) || error("--warmup-per-chain requires an integer")
            warmup_per_chain = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--draws-per-chain"
            index < length(args) || error("--draws-per-chain requires an integer")
            draws_per_chain = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--target-acceptance"
            index < length(args) || error("--target-acceptance requires a number")
            target_acceptance = parse(Float64, args[index + 1])
            index += 2
        elseif arg == "--seed"
            index < length(args) || error("--seed requires an integer")
            seed = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--ppc-draws"
            index < length(args) || error("--ppc-draws requires an integer")
            ppc_draws = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--backend"
            index < length(args) || error("--backend requires a name")
            backend = Symbol(args[index + 1])
            index += 2
        elseif arg == "--sampler"
            index < length(args) || error("--sampler requires a name")
            sampler = Symbol(args[index + 1])
            index += 2
        elseif arg == "--analytic-reference"
            analytic_reference = true
            index += 1
        elseif arg == "--dry-run"
            dry_run = true
            index += 1
        elseif arg == "--progress"
            progress = true
            index += 1
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end

    execution_unit === nothing && error("--execution-unit is required")
    ppc_draws >= 1 || error("--ppc-draws must be positive")
    return (;
        execution_unit = String(execution_unit),
        plan,
        gate,
        output,
        diagnostics_output,
        heldout_output,
        chains,
        warmup_per_chain,
        draws_per_chain,
        target_acceptance,
        seed,
        ppc_draws,
        backend,
        sampler,
        analytic_reference,
        dry_run,
        progress,
    )
end

function result_output_path(options)
    options.output !== nothing && return options.output
    return joinpath(DEFAULT_RESULT_ROOT,
        string(options.execution_unit, "_result.json"))
end

function sibling_output_path(result_path::AbstractString, suffix::AbstractString)
    marker = "_result.json"
    if endswith(result_path, marker)
        return string(first(result_path, lastindex(result_path) - length(marker)),
            suffix)
    end
    stem, _ = splitext(result_path)
    return string(stem, suffix)
end

function artifact_paths(options)
    result = abspath(result_output_path(options))
    diagnostics = options.diagnostics_output === nothing ?
        sibling_output_path(result, "_diagnostics.json") :
        abspath(options.diagnostics_output)
    heldout = options.heldout_output === nothing ?
        sibling_output_path(result, "_heldout_score.json") :
        abspath(options.heldout_output)
    return (; result, diagnostics, heldout)
end

function load_json(path::AbstractString)
    return JSON3.read(read(path, String))
end

function json_get(object, key::Symbol, default = missing)
    haskey(object, key) || return default
    value = object[key]
    value === nothing && return default
    ismissing(value) && return default
    return value
end

function plan_row_key(plan)
    haskey(plan, :selected_pilot_unit_rows) &&
        return :selected_pilot_unit_rows
    haskey(plan, :batch_execution_job_rows) &&
        return :batch_execution_job_rows
    error("plan does not contain selected_pilot_unit_rows or batch_execution_job_rows")
end

function plan_scope(plan)
    haskey(plan, :scope) || return :unknown_plan
    return as_symbol(plan[:scope])
end

function plan_artifact_name(plan)
    scope = plan_scope(plan)
    scope === :publication_grade_refit_pilot_plan &&
        return :mgmfrm_publication_grade_refit_pilot_plan
    scope === :publication_grade_refit_batch_expansion_plan &&
        return :mgmfrm_publication_grade_refit_batch_expansion_plan
    return :mgmfrm_publication_grade_refit_plan
end

function plan_is_batch(plan)
    return plan_scope(plan) === :publication_grade_refit_batch_expansion_plan
end

function selected_plan_row(plan, execution_unit::AbstractString)
    key = plan_row_key(plan)
    matches = [row for row in plan[key]
        if as_string(row[:execution_unit_id]) == execution_unit]
    isempty(matches) &&
        error("execution unit not found in plan: $execution_unit")
    length(matches) == 1 ||
        error("execution unit is not unique in plan: $execution_unit")
    return only(matches)
end

function q_matrix_rows(matrix::AbstractMatrix{Bool})
    return [[Bool(matrix[row, col]) for col in axes(matrix, 2)]
        for row in axes(matrix, 1)]
end

function scenario_n_items(scenario::Symbol)
    profile = FoldPilotHelpers.q_profile(
        scenario,
        :confirmatory_mgmfrm_current_q,
    )
    return size(profile.q_matrix, 1)
end

function execution_unit_from_row(row)
    scenario = as_symbol(row[:scenario])
    model = as_symbol(row[:model])
    q_profile = model in MGMFRM_MODELS ?
        FoldPilotHelpers.q_profile(scenario, model) : nothing
    n_items = q_profile === nothing ?
        scenario_n_items(scenario) : size(q_profile.q_matrix, 1)
    chains = as_int(json_get(row, :planned_chains,
        json_get(row, :chains, 0)))
    warmup = as_int(json_get(row, :planned_warmup_per_chain,
        json_get(row, :warmup_per_chain, 0)))
    draws = as_int(json_get(row, :planned_draws_per_chain,
        json_get(row, :draws_per_chain, 0)))
    seed = json_get(row, :pilot_seed, json_get(row, :batch_seed, missing))
    target_acceptance = json_get(row, :target_acceptance, missing)
    role = json_get(row, :pilot_role,
        json_get(row, :job_kind,
            model === :null_or_intercept_reference ?
                :analytic_reference_anchor : :publication_grade_mcmc_refit))
    return (;
        execution_unit_id = as_symbol(row[:execution_unit_id]),
        scenario,
        model,
        fold = as_int(row[:fold]),
        split = as_symbol(row[:split]),
        pilot_role = as_symbol(role),
        mcmc_refit_required = as_bool(row[:mcmc_refit_required]),
        analytic_reference_scored = as_bool(row[:analytic_reference_scored]),
        q_profile = q_profile === nothing ? missing : q_profile.q_profile,
        q_matrix = q_profile === nothing ? missing :
            q_matrix_rows(q_profile.q_matrix),
        n_dimensions = q_profile === nothing ? (model === :scalar_gmfrm_baseline ? 1 : 0) :
            size(q_profile.q_matrix, 2),
        n_items,
        n_train_observations = as_int(row[:n_train_observations]),
        n_heldout_observations = as_int(row[:n_heldout_observations]),
        heldout_observations =
            [as_int(value) for value in row[:heldout_observations]],
        planned_chains = chains,
        planned_warmup_per_chain = warmup,
        planned_draws_per_chain = draws,
        planned_posterior_draws = as_int(json_get(row,
            :planned_posterior_draws, chains * draws)),
        planned_target_acceptance = target_acceptance,
        pilot_seed = ismissing(seed) ? missing : as_int(seed),
        public_claim_allowed = false,
    )
end

function fit_controls(unit, options)
    chains = options.chains === nothing ? unit.planned_chains : options.chains
    warmup = options.warmup_per_chain === nothing ?
        unit.planned_warmup_per_chain : options.warmup_per_chain
    draws = options.draws_per_chain === nothing ?
        unit.planned_draws_per_chain : options.draws_per_chain
    default_target_acceptance = ismissing(unit.planned_target_acceptance) ?
        0.8 : Float64(unit.planned_target_acceptance)
    target_acceptance = options.target_acceptance === nothing ?
        default_target_acceptance : Float64(options.target_acceptance)
    seed = options.seed === nothing ? unit.pilot_seed : options.seed
    if unit.mcmc_refit_required
        chains >= 1 || error("MCMC jobs require at least one chain")
        warmup >= 0 || error("warmup must be non-negative")
        draws >= 1 || error("draws must be positive")
        ismissing(seed) && error("MCMC jobs require a seed")
        0 < target_acceptance < 1 ||
            error("target acceptance must be in (0, 1)")
    end
    return (;
        backend = options.backend,
        sampler = options.sampler,
        chains = unit.mcmc_refit_required ? chains : 0,
        warmup_per_chain = unit.mcmc_refit_required ? warmup : 0,
        draws_per_chain = unit.mcmc_refit_required ? draws : 0,
        target_acceptance =
            unit.mcmc_refit_required ? target_acceptance : missing,
        seed = unit.mcmc_refit_required ? Int(seed) : missing,
        ppc_draws = options.ppc_draws,
        progress = options.progress,
    )
end

function table_from_rows(rows)
    return (;
        examinee = [row.examinee for row in rows],
        rater = [row.rater for row in rows],
        item = [row.item for row in rows],
        score = [row.score for row in rows],
    )
end

function logmeanexp(values::AbstractVector{<:Real})
    isempty(values) && return NaN
    max_value = maximum(values)
    isfinite(max_value) || return max_value
    return max_value +
        log(sum(exp(value - max_value) for value in values) / length(values))
end

function finite_mean(values)
    finite = [Float64(value) for value in values if isfinite(Float64(value))]
    isempty(finite) && return NaN
    return sum(finite) / length(finite)
end

function finite_rmse(values)
    finite = [Float64(value) for value in values if isfinite(Float64(value))]
    isempty(finite) && return NaN
    return sqrt(sum(value^2 for value in finite) / length(finite))
end

function row_expected_scores(design, direct_draws::AbstractMatrix)
    n_draws = size(direct_draws, 1)
    n_observations = design.spec.data.n
    output = zeros(Float64, n_draws, n_observations)
    fixture_values = design.spec.family === :gmfrm ?
        BayesianMGMFRM._gmfrm_source_fixture_values :
        BayesianMGMFRM._mgmfrm_source_fixture_values
    for draw in axes(direct_draws, 1)
        values = fixture_values(design, vec(direct_draws[draw, :]))
        for row in values
            output[draw, Int(row.row)] +=
                exp(Float64(row.log_probability)) * Float64(row.category)
        end
    end
    return output
end

function q_matrix_from_rows(rows)
    return FoldPilotHelpers.q_matrix_from_rows(rows)
end

function train_full_data(unit)
    rows = FoldPilotHelpers.synthetic_rows(unit)
    train_rows = [row for row in rows if row.split_role === :train]
    train_data = BayesianMGMFRM.FacetData(table_from_rows(train_rows);
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
    full_data = BayesianMGMFRM.FacetData(table_from_rows(rows);
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
    return (; rows, train_rows, train_data, full_data)
end

function specs_for_unit(unit, train_data, full_data)
    if unit.model === :scalar_gmfrm_baseline
        train_spec = BayesianMGMFRM.mfrm_spec(train_data;
            family = :gmfrm,
            discrimination = :rater,
        )
        full_spec = BayesianMGMFRM.mfrm_spec(full_data;
            family = :gmfrm,
            discrimination = :rater,
        )
        return (;
            train_spec,
            full_spec,
            q_matrix = missing,
            q_validation = missing,
            family = :gmfrm,
        )
    end
    unit.model in MGMFRM_MODELS ||
        error("unsupported MCMC publication-grade model: $(unit.model)")
    q_matrix = q_matrix_from_rows(unit.q_matrix)
    train_spec = BayesianMGMFRM.mfrm_spec(train_data;
        family = :mgmfrm,
        dimensions = size(q_matrix, 2),
        q_matrix,
    )
    full_spec = BayesianMGMFRM.mfrm_spec(full_data;
        family = :mgmfrm,
        dimensions = size(q_matrix, 2),
        q_matrix,
    )
    q_validation = BayesianMGMFRM.q_matrix_validation(train_spec)
    return (;
        train_spec,
        full_spec,
        q_matrix,
        q_validation,
        family = :mgmfrm,
    )
end

function heldout_pointwise_rows(unit, rows, heldout, pointwise_elpd,
        expected_score_mean, residuals, absolute_errors, squared_errors)
    output = NamedTuple[]
    for (offset, observation) in enumerate(heldout)
        push!(output, (;
            execution_unit_id = unit.execution_unit_id,
            scenario = unit.scenario,
            model = unit.model,
            fold = unit.fold,
            observation,
            heldout_position = offset,
            person = rows[observation].examinee,
            rater = rows[observation].rater,
            item = rows[observation].item,
            observed_score = Int(rows[observation].score),
            pointwise_log_predictive_density = pointwise_elpd[offset],
            expected_score_mean = expected_score_mean[offset],
            observed_minus_expected_score = residuals[offset],
            absolute_expected_score_error = absolute_errors[offset],
            squared_expected_score_error = squared_errors[offset],
            finite_score =
                isfinite(pointwise_elpd[offset]) &&
                isfinite(expected_score_mean[offset]) &&
                isfinite(residuals[offset]),
            public_claim_allowed = false,
        ))
    end
    return output
end

function compact_ppc_summary(fit, controls)
    n_available = size(fit.direct_draws, 1)
    n_draws = min(Int(controls.ppc_draws), n_available)
    ppc = BayesianMGMFRM.posterior_predictive_check(fit;
        ndraws = n_draws,
        rng = MersenneTwister(Int(controls.seed) + 1),
    )
    return (;
        posterior_predictive_check_recorded = true,
        n_ppc_draws = length(ppc.draw_indices),
        draw_indices = collect(Int, ppc.draw_indices),
        replicated_score_matrix_size = collect(size(ppc.replicated_scores)),
    )
end

function fit_and_score_mcmc(unit, controls)
    data = train_full_data(unit)
    specs = specs_for_unit(unit, data.train_data, data.full_data)
    validation = BayesianMGMFRM.validate_design(data.train_data)
    train_design = BayesianMGMFRM.getdesign(specs.train_spec; preview = true)
    full_design = BayesianMGMFRM.getdesign(specs.full_spec; preview = true)
    layout_matches = train_design.parameter_names == full_design.parameter_names
    fit = BayesianMGMFRM.fit(specs.train_spec;
        experimental = true,
        backend = controls.backend,
        ndraws = controls.draws_per_chain,
        warmup = controls.warmup_per_chain,
        chains = controls.chains,
        seed = controls.seed,
        target_accept = controls.target_acceptance,
        progress = controls.progress,
    )
    ppc_summary = compact_ppc_summary(fit, controls)

    full_loglikelihood =
        BayesianMGMFRM.pointwise_loglikelihood_matrix(
            full_design,
            fit.direct_draws,
        )
    expected = row_expected_scores(full_design, fit.direct_draws)
    heldout = Int.(unit.heldout_observations)
    heldout_loglikelihood = full_loglikelihood[:, heldout]
    heldout_expected = expected[:, heldout]
    observed_scores = Float64.(data.full_data.score[heldout])
    pointwise_elpd =
        [logmeanexp(vec(heldout_loglikelihood[:, column]))
            for column in axes(heldout_loglikelihood, 2)]
    expected_score_mean =
        [finite_mean(heldout_expected[:, column])
            for column in axes(heldout_expected, 2)]
    residuals = observed_scores .- expected_score_mean
    absolute_errors = abs.(residuals)
    squared_errors = residuals .^ 2
    train_pointwise =
        [logmeanexp(vec(fit.direct_pointwise_loglikelihood[:, column]))
            for column in axes(fit.direct_pointwise_loglikelihood, 2)]
    summary = fit.diagnostic_surface.summary
    pointwise_rows = heldout_pointwise_rows(
        unit,
        data.rows,
        heldout,
        pointwise_elpd,
        expected_score_mean,
        residuals,
        absolute_errors,
        squared_errors,
    )

    score_row = (;
        execution_unit_id = unit.execution_unit_id,
        scenario = unit.scenario,
        model = unit.model,
        fold = unit.fold,
        model_family = specs.family,
        q_profile = unit.q_profile,
        q_matrix = unit.q_matrix,
        fit_seed = controls.seed,
        fit_succeeded =
            (specs.family === :gmfrm && fit isa BayesianMGMFRM.GMFRMFit) ||
            (specs.family === :mgmfrm && fit isa BayesianMGMFRM.MGMFRMFit),
        scoring_succeeded = true,
        returned_type = Symbol(nameof(typeof(fit))),
        layout_matches,
        mcmc_refit_attempted = true,
        analytic_reference_scored = false,
        n_train_observations = data.train_data.n,
        n_heldout_observations = length(heldout),
        n_draws = size(fit.direct_draws, 1),
        chains = length(fit.chain_acceptance_rate),
        draws_per_chain = size(fit.draws, 1) ÷
            length(fit.chain_acceptance_rate),
        warmup = fit.warmup,
        n_dimensions = unit.n_dimensions,
        n_items = unit.n_items,
        n_categories = length(data.train_data.category_levels),
        validation_passed = Bool(validation.passed),
        q_validation_passed = specs.family === :mgmfrm ?
            Bool(specs.q_validation.passed) : true,
        n_q_validation_warnings = specs.family === :mgmfrm ?
            Int(specs.q_validation.summary.n_warning_rows) : 0,
        backend = fit.backend,
        sampler = fit.sampler,
        target_acceptance = controls.target_acceptance,
        n_raw_parameters = size(fit.draws, 2),
        n_direct_parameters = size(fit.direct_draws, 2),
        training_elpd = sum(train_pointwise; init = 0.0),
        training_mean_log_predictive_density = finite_mean(train_pointwise),
        heldout_elpd = sum(pointwise_elpd; init = 0.0),
        heldout_mean_log_predictive_density = finite_mean(pointwise_elpd),
        heldout_min_pointwise_log_predictive_density =
            minimum(pointwise_elpd),
        heldout_max_pointwise_log_predictive_density =
            maximum(pointwise_elpd),
        heldout_expected_score_mae = finite_mean(absolute_errors),
        heldout_expected_score_rmse = finite_rmse(residuals),
        heldout_expected_score_bias = finite_mean(residuals),
        train_heldout_mean_log_predictive_gap =
            finite_mean(train_pointwise) - finite_mean(pointwise_elpd),
        all_pointwise_scores_finite = all(isfinite, pointwise_elpd),
        expected_score_residuals_finite =
            all(isfinite, expected_score_mean) &&
            all(isfinite, residuals),
        finite_log_posterior = all(isfinite, fit.log_posterior),
        finite_raw_draws = all(isfinite, fit.draws),
        finite_direct_draws = all(isfinite, fit.direct_draws),
        finite_training_pointwise_loglikelihood =
            all(isfinite, fit.direct_pointwise_loglikelihood),
        finite_heldout_pointwise_loglikelihood =
            all(isfinite, heldout_loglikelihood),
        posterior_predictive_check_recorded =
            ppc_summary.posterior_predictive_check_recorded,
        n_ppc_draws = ppc_summary.n_ppc_draws,
        diagnostic_flag = summary.flag,
        diagnostic_passed = Bool(summary.passed),
        n_nonfinite_logdensity = Int(summary.n_nonfinite_logdensity),
        n_nonfinite_direct_loglikelihood =
            Int(summary.n_nonfinite_direct_loglikelihood),
        n_failed_direct_constraints =
            Int(summary.n_failed_direct_constraints),
        max_rhat = Float64(summary.max_rhat),
        min_ess = Float64(summary.min_ess),
        e_bfmi = ismissing(summary.e_bfmi) ? missing :
            Float64(summary.e_bfmi),
        n_divergences = Int(summary.n_divergences),
        n_max_treedepth = Int(summary.n_max_treedepth),
        heldout_predictive_score_computed = true,
        public_fit_metric_claim_allowed = false,
        public_model_weight_claim_allowed = false,
        sparse_superiority_claim_allowed = false,
    )
    return (;
        score_row,
        pointwise_rows,
        probability_rows = NamedTuple[],
        diagnostic_summary = summary,
        ppc_summary,
    )
end

function reference_probabilities(train_rows, categories::Vector{Int})
    alpha = Float64(REFERENCE_CONTROLS.alpha)
    counts = Dict(category => 0 for category in categories)
    for row in train_rows
        counts[Int(row.score)] = counts[Int(row.score)] + 1
    end
    denominator = length(train_rows) + alpha * length(categories)
    probabilities = Dict(
        category => (counts[category] + alpha) / denominator
        for category in categories
    )
    expected_score =
        sum(Float64(category) * probabilities[category] for category in categories)
    return (; counts, probabilities, expected_score)
end

function score_analytic_reference(unit)
    data = train_full_data(unit)
    categories = Int.(REFERENCE_CONTROLS.categories)
    reference = reference_probabilities(data.train_rows, categories)
    heldout = Int.(unit.heldout_observations)
    pointwise_elpd =
        [log(reference.probabilities[Int(data.rows[observation].score)])
            for observation in heldout]
    expected_score_mean = fill(reference.expected_score, length(heldout))
    observed_scores =
        [Float64(data.rows[observation].score) for observation in heldout]
    residuals = observed_scores .- expected_score_mean
    absolute_errors = abs.(residuals)
    squared_errors = residuals .^ 2
    train_pointwise =
        [log(reference.probabilities[Int(row.score)])
            for row in data.train_rows]
    pointwise_rows = heldout_pointwise_rows(
        unit,
        data.rows,
        heldout,
        pointwise_elpd,
        expected_score_mean,
        residuals,
        absolute_errors,
        squared_errors,
    )
    probability_rows = [
        (execution_unit_id = unit.execution_unit_id,
            scenario = unit.scenario,
            model = unit.model,
            fold = unit.fold,
            category,
            training_count = reference.counts[category],
            smoothing_alpha = Float64(REFERENCE_CONTROLS.alpha),
            smoothed_probability = reference.probabilities[category],
            public_claim_allowed = false)
        for category in categories
    ]
    score_row = (;
        execution_unit_id = unit.execution_unit_id,
        scenario = unit.scenario,
        model = unit.model,
        fold = unit.fold,
        model_family = :reference_anchor,
        scoring_method = :analytic_intercept_category_rate,
        fit_seed = missing,
        fit_succeeded = true,
        scoring_succeeded = true,
        returned_type = :AnalyticInterceptReference,
        layout_matches = true,
        mcmc_refit_attempted = false,
        analytic_reference_scored = true,
        n_train_observations = length(data.train_rows),
        n_heldout_observations = length(heldout),
        n_draws = 1,
        chains = 0,
        draws_per_chain = 0,
        warmup = 0,
        n_dimensions = 0,
        n_items = unit.n_items,
        training_elpd = sum(train_pointwise; init = 0.0),
        training_mean_log_predictive_density = finite_mean(train_pointwise),
        heldout_elpd = sum(pointwise_elpd; init = 0.0),
        heldout_mean_log_predictive_density = finite_mean(pointwise_elpd),
        heldout_min_pointwise_log_predictive_density =
            minimum(pointwise_elpd),
        heldout_max_pointwise_log_predictive_density =
            maximum(pointwise_elpd),
        heldout_expected_score_mae = finite_mean(absolute_errors),
        heldout_expected_score_rmse = finite_rmse(residuals),
        heldout_expected_score_bias = finite_mean(residuals),
        train_heldout_mean_log_predictive_gap =
            finite_mean(train_pointwise) - finite_mean(pointwise_elpd),
        all_pointwise_scores_finite = all(isfinite, pointwise_elpd),
        expected_score_residuals_finite =
            all(isfinite, expected_score_mean) &&
            all(isfinite, residuals),
        finite_direct_draws = true,
        finite_training_pointwise_loglikelihood = all(isfinite, train_pointwise),
        finite_heldout_pointwise_loglikelihood = all(isfinite, pointwise_elpd),
        posterior_predictive_check_recorded = false,
        n_ppc_draws = 0,
        diagnostic_flag = :analytic_reference_no_mcmc,
        diagnostic_passed = false,
        n_nonfinite_logdensity = 0,
        n_nonfinite_direct_loglikelihood = 0,
        n_failed_direct_constraints = 0,
        max_rhat = NaN,
        min_ess = NaN,
        e_bfmi = missing,
        n_divergences = 0,
        n_max_treedepth = 0,
        heldout_predictive_score_computed = true,
        public_fit_metric_claim_allowed = false,
        public_model_weight_claim_allowed = false,
        sparse_superiority_claim_allowed = false,
    )
    return (;
        score_row,
        pointwise_rows,
        probability_rows,
        diagnostic_summary = missing,
        ppc_summary = (;
            posterior_predictive_check_recorded = false,
            n_ppc_draws = 0,
            draw_indices = Int[],
            replicated_score_matrix_size = Int[],
        ),
    )
end

function compare_metric(value, threshold, comparison::Symbol)
    ismissing(value) && return false
    comparison === :greater_or_equal &&
        return isfinite(Float64(value)) && Float64(value) >= Float64(threshold)
    comparison === :less_or_equal &&
        return isfinite(Float64(value)) && Float64(value) <= Float64(threshold)
    comparison === :equal && return Float64(value) == Float64(threshold)
    comparison === :boolean_true && return Bool(value)
    error("unsupported diagnostic comparison: $comparison")
end

function diagnostic_value(diagnostic::Symbol, score_row)
    diagnostic === :chains_min && return score_row.chains
    diagnostic === :warmup_per_chain_min && return score_row.warmup
    diagnostic === :draws_per_chain_min && return score_row.draws_per_chain
    diagnostic === :rank_normalized_rhat_max && return score_row.max_rhat
    diagnostic === :ess_bulk_min && return score_row.min_ess
    diagnostic === :ess_tail_min && return score_row.min_ess
    diagnostic === :divergence_count_max && return score_row.n_divergences
    diagnostic === :max_treedepth_count_max && return score_row.n_max_treedepth
    diagnostic === :ebfmi_min && return score_row.e_bfmi
    diagnostic === :pointwise_loglikelihood_finite &&
        return score_row.all_pointwise_scores_finite
    diagnostic === :posterior_predictive_check_recorded &&
        return score_row.posterior_predictive_check_recorded
    diagnostic === :expected_score_calibration_recorded &&
        return score_row.expected_score_residuals_finite
    error("unknown diagnostic: $diagnostic")
end

function diagnostic_applicable(diagnostic::Symbol, unit)
    unit.mcmc_refit_required && return true
    return diagnostic in (
        :pointwise_loglikelihood_finite,
        :expected_score_calibration_recorded,
    )
end

function diagnostic_rows(gate, unit, score_row, dry_run::Bool)
    rows = NamedTuple[]
    for row in gate[:diagnostic_gate_rows]
        diagnostic = as_symbol(row[:diagnostic])
        comparison = as_symbol(row[:comparison])
        threshold = row[:threshold]
        applicable = diagnostic_applicable(diagnostic, unit)
        observed = !dry_run && applicable
        value = observed ? diagnostic_value(diagnostic, score_row) : missing
        passed = observed &&
            compare_metric(value, threshold, comparison)
        push!(rows, (;
            execution_unit_id = unit.execution_unit_id,
            scenario = unit.scenario,
            model = unit.model,
            fold = unit.fold,
            diagnostic,
            source = as_symbol(row[:source]),
            comparison,
            threshold,
            applicable,
            observed,
            value,
            passed,
            public_claim_blocked_if_missing =
                as_bool(row[:public_claim_blocked_if_missing]),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function planned_score_row(unit, controls)
    return (;
        execution_unit_id = unit.execution_unit_id,
        scenario = unit.scenario,
        model = unit.model,
        fold = unit.fold,
        mcmc_refit_attempted = false,
        analytic_reference_scored = false,
        dry_run = true,
        chains = controls.chains,
        warmup = controls.warmup_per_chain,
        draws_per_chain = controls.draws_per_chain,
        target_acceptance = controls.target_acceptance,
        fit_seed = controls.seed,
        n_train_observations = unit.n_train_observations,
        n_heldout_observations = unit.n_heldout_observations,
        heldout_predictive_score_computed = false,
        posterior_predictive_check_recorded = false,
        public_fit_metric_claim_allowed = false,
        public_model_weight_claim_allowed = false,
        sparse_superiority_claim_allowed = false,
    )
end

function input_artifact_records(options, plan)
    return [
        (artifact = plan_artifact_name(plan),
            path = relpath(options.plan, ROOT),
            exists = isfile(options.plan),
            sha256 = isfile(options.plan) ?
                file_sha256(options.plan) : missing),
        (artifact = :mgmfrm_publication_grade_refit_gate,
            path = relpath(options.gate, ROOT),
            exists = isfile(options.gate),
            sha256 = isfile(options.gate) ?
                file_sha256(options.gate) : missing),
    ]
end

function build_artifacts(options)
    paths = artifact_paths(options)
    plan = load_json(options.plan)
    gate = load_json(options.gate)
    batch_plan = plan_is_batch(plan)
    unit = execution_unit_from_row(
        selected_plan_row(plan, options.execution_unit))
    controls = fit_controls(unit, options)
    unit.model === :null_or_intercept_reference ||
        !options.analytic_reference ||
        error("--analytic-reference is only valid for the reference unit")

    result = if options.dry_run
        (;
            score_row = planned_score_row(unit, controls),
            pointwise_rows = NamedTuple[],
            probability_rows = NamedTuple[],
            diagnostic_summary = missing,
            ppc_summary = (;
                posterior_predictive_check_recorded = false,
                n_ppc_draws = 0,
                draw_indices = Int[],
                replicated_score_matrix_size = Int[],
            ),
        )
    elseif unit.model === :null_or_intercept_reference
        score_analytic_reference(unit)
    elseif unit.mcmc_refit_required
        fit_and_score_mcmc(unit, controls)
    else
        error("selected unit is neither MCMC nor analytic reference")
    end

    diagnostics = diagnostic_rows(gate, unit, result.score_row, options.dry_run)
    applicable_diagnostics = [row for row in diagnostics if row.applicable]
    observed_applicable_diagnostics =
        [row for row in applicable_diagnostics if row.observed]
    all_observed_applicable_passed =
        !isempty(observed_applicable_diagnostics) &&
        all(row -> Bool(row.passed), observed_applicable_diagnostics)
    executed = !options.dry_run
    input_records = input_artifact_records(options, plan)
    job_scope = batch_plan ?
        :publication_grade_refit_batch_job : :publication_grade_refit_pilot_job
    result_status = options.dry_run ?
        (batch_plan ?
            :publication_grade_refit_batch_job_dry_run_recorded :
            :publication_grade_refit_job_dry_run_recorded) :
        (batch_plan ?
            :publication_grade_refit_batch_job_executed :
            :publication_grade_refit_job_executed)
    diagnostics_scope = batch_plan ?
        :publication_grade_refit_batch_job_diagnostics :
        :publication_grade_refit_pilot_job_diagnostics
    diagnostics_status = options.dry_run ?
        (batch_plan ?
            :publication_grade_refit_batch_job_diagnostics_dry_run :
            :publication_grade_refit_job_diagnostics_dry_run) :
        (batch_plan ?
            :publication_grade_refit_batch_job_diagnostics_recorded :
            :publication_grade_refit_job_diagnostics_recorded)
    heldout_scope = batch_plan ?
        :publication_grade_refit_batch_job_heldout_score :
        :publication_grade_refit_pilot_job_heldout_score
    heldout_status = options.dry_run ?
        (batch_plan ?
            :publication_grade_refit_batch_job_heldout_score_dry_run :
            :publication_grade_refit_job_heldout_score_dry_run) :
        (batch_plan ?
            :publication_grade_refit_batch_job_heldout_score_recorded :
            :publication_grade_refit_job_heldout_score_recorded)
    next_gate = batch_plan ?
        :review_publication_grade_batch_diagnostics_or_run_remaining_batch_jobs :
        :review_publication_grade_refit_diagnostics_or_run_remaining_pilot_jobs

    result_artifact = (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_result.v1",
        family = :mgmfrm,
        scope = job_scope,
        status = result_status,
        execution_unit_id = unit.execution_unit_id,
        scenario = unit.scenario,
        model = unit.model,
        fold = unit.fold,
        local_only = true,
        pilot_only = !batch_plan,
        batch_plan,
        dry_run = options.dry_run,
        publication_or_registration_action = false,
        public_claim_allowed = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        fit_controls = controls,
        input_artifacts = input_records,
        output_artifacts = (;
            result_artifact_path = relpath(paths.result, ROOT),
            diagnostic_artifact_path = relpath(paths.diagnostics, ROOT),
            heldout_score_artifact_path = relpath(paths.heldout, ROOT),
        ),
        selected_unit = unit,
        score_row = options.dry_run ? missing : result.score_row,
        planned_score_row = options.dry_run ? result.score_row : missing,
        summary = (;
            passed = true,
            executed,
            dry_run = options.dry_run,
            mcmc_refit_required = unit.mcmc_refit_required,
            analytic_reference_scored =
                !options.dry_run && unit.model === :null_or_intercept_reference,
            heldout_predictive_score_computed =
                !options.dry_run &&
                Bool(result.score_row.heldout_predictive_score_computed),
            posterior_predictive_check_recorded =
                !options.dry_run &&
                Bool(result.score_row.posterior_predictive_check_recorded),
            all_pointwise_scores_finite =
                !options.dry_run &&
                Bool(result.score_row.all_pointwise_scores_finite),
            expected_score_residuals_finite =
                !options.dry_run &&
                Bool(result.score_row.expected_score_residuals_finite),
            diagnostic_gate_passed = all_observed_applicable_passed,
            n_diagnostic_rows = length(diagnostics),
            n_observed_applicable_diagnostic_rows =
                length(observed_applicable_diagnostics),
            n_heldout_pointwise_rows = length(result.pointwise_rows),
            public_claim_allowed = false,
            next_gate,
        ),
    )

    diagnostics_artifact = (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_diagnostics.v1",
        family = :mgmfrm,
        scope = diagnostics_scope,
        status = diagnostics_status,
        execution_unit_id = unit.execution_unit_id,
        scenario = unit.scenario,
        model = unit.model,
        fold = unit.fold,
        dry_run = options.dry_run,
        local_only = true,
        pilot_only = !batch_plan,
        batch_plan,
        publication_or_registration_action = false,
        public_claim_allowed = false,
        fit_controls = controls,
        diagnostic_rows = diagnostics,
        posterior_predictive_check = result.ppc_summary,
        sampler_summary = result.diagnostic_summary,
        summary = (;
            passed = true,
            diagnostics_recorded = true,
            dry_run = options.dry_run,
            n_diagnostic_rows = length(diagnostics),
            n_applicable_diagnostic_rows = length(applicable_diagnostics),
            n_observed_applicable_diagnostic_rows =
                length(observed_applicable_diagnostics),
            n_passed_observed_applicable_diagnostic_rows =
                count(row -> Bool(row.passed),
                    observed_applicable_diagnostics),
            all_observed_applicable_diagnostics_passed =
                all_observed_applicable_passed,
            posterior_predictive_check_recorded =
                !options.dry_run &&
                Bool(result.score_row.posterior_predictive_check_recorded),
            public_claim_allowed = false,
        ),
    )

    heldout_artifact = (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_heldout_score.v1",
        family = :mgmfrm,
        scope = heldout_scope,
        status = heldout_status,
        execution_unit_id = unit.execution_unit_id,
        scenario = unit.scenario,
        model = unit.model,
        fold = unit.fold,
        dry_run = options.dry_run,
        local_only = true,
        pilot_only = !batch_plan,
        batch_plan,
        publication_or_registration_action = false,
        public_claim_allowed = false,
        heldout_pointwise_rows = result.pointwise_rows,
        reference_probability_rows = result.probability_rows,
        summary = (;
            passed = true,
            heldout_predictive_score_computed =
                !options.dry_run &&
                Bool(result.score_row.heldout_predictive_score_computed),
            n_heldout_pointwise_rows = length(result.pointwise_rows),
            n_reference_probability_rows = length(result.probability_rows),
            heldout_elpd = options.dry_run ? missing :
                result.score_row.heldout_elpd,
            heldout_mean_log_predictive_density = options.dry_run ? missing :
                result.score_row.heldout_mean_log_predictive_density,
            heldout_expected_score_mae = options.dry_run ? missing :
                result.score_row.heldout_expected_score_mae,
            heldout_expected_score_rmse = options.dry_run ? missing :
                result.score_row.heldout_expected_score_rmse,
            all_pointwise_scores_finite =
                !options.dry_run &&
                Bool(result.score_row.all_pointwise_scores_finite),
            public_claim_allowed = false,
        ),
    )
    return (; paths, result_artifact, diagnostics_artifact, heldout_artifact)
end

function main(args)
    options = parse_args(args)
    artifacts = build_artifacts(options)
    write_artifact(artifacts.paths.result, artifacts.result_artifact)
    write_artifact(artifacts.paths.diagnostics, artifacts.diagnostics_artifact)
    write_artifact(artifacts.paths.heldout, artifacts.heldout_artifact)
    println("wrote ", relpath(artifacts.paths.result, ROOT))
    println("wrote ", relpath(artifacts.paths.diagnostics, ROOT))
    println("wrote ", relpath(artifacts.paths.heldout, ROOT))
    println("executed=", artifacts.result_artifact.summary.executed,
        " dry_run=", artifacts.result_artifact.summary.dry_run,
        " diagnostic_gate_passed=",
        artifacts.result_artifact.summary.diagnostic_gate_passed,
        " public_claim_allowed=false")
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
