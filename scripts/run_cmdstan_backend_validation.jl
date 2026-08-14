module CmdStanBackendValidation

using Random
using Statistics

using BayesianMGMFRM

const _FAMILIES = (:mfrm, :gmfrm, :mgmfrm)
const _SCENARIOS = (:dense, :sparse)
const _Q_MATRIX = Bool[1 0; 1 0; 0 1; 0 1]

"""
    validation_controls(profile)

Return a resource budget for paired AdvancedHMC/CmdStan validation. `:smoke`
checks execution wiring and `:pilot` measures local behavior with a small
budget. Neither is repeated parameter-recovery evidence.
"""
function validation_controls(profile::Symbol)
    profile === :smoke && return (;
        profile,
        ndraws = 4,
        warmup = 4,
        chains = 1,
        step_size = 0.03,
        target_accept = 0.8,
        max_depth = 10,
        metric = :unit,
        convergence_assessed = false,
        claim_scope = :execution_and_sparse_wiring_only,
    )
    profile === :pilot && return (;
        profile,
        ndraws = 100,
        warmup = 100,
        chains = 2,
        step_size = 0.03,
        target_accept = 0.9,
        max_depth = 12,
        metric = :diagonal,
        convergence_assessed = true,
        claim_scope = :local_diagnostic_pilot_not_recovery_evidence,
    )
    throw(ArgumentError("profile must be :smoke or :pilot"))
end

function _check_selection(values, allowed, label::AbstractString)
    checked = Tuple(Symbol(value) for value in values)
    isempty(checked) && throw(ArgumentError("$label must not be empty"))
    length(unique(checked)) == length(checked) ||
        throw(ArgumentError("$label contains duplicate values"))
    unsupported = Tuple(value for value in checked if !(value in allowed))
    isempty(unsupported) || throw(ArgumentError(
        "$label contains unsupported values: $(join(string.(unsupported), ", "))",
    ))
    return checked
end

function _dense_columns()
    person = String[]
    rater = String[]
    item = String[]
    score = Int[]
    row = 0
    for person_index in 1:6, item_index in 1:4, rater_index in 1:3
        row += 1
        push!(person, "P$person_index")
        push!(rater, "R$rater_index")
        push!(item, "I$item_index")
        push!(score, mod(row - 1, 3))
    end
    return (; person, rater, item, score)
end

function _sparse_columns()
    person = String[]
    rater = String[]
    item = String[]
    score = Int[]
    row = 0
    for person_index in 1:8, item_index in 1:4, rater_index in 1:3
        selected_items = (
            1 + mod(person_index - 1, 2),
            3 + mod(person_index - 1, 2),
        )
        primary_rater = 1 + mod(person_index - 1, 3)
        selected = person_index == 1 ||
            (rater_index == primary_rater && item_index in selected_items)
        if selected
            row += 1
            push!(person, "P$person_index")
            push!(rater, "R$rater_index")
            push!(item, "I$item_index")
            push!(score, mod(row - 1, 3))
        end
    end
    return (; person, rater, item, score)
end

"""
    scenario_data(scenario)

Build a deterministic validation layout. The dense layout observes every
person-rater-item cell. In the sparse layout, non-bridge persons observe two of
four items, one from each fixed-Q dimension, through rotating primary raters;
one fully crossed bridge person keeps the facet graph connected and full rank.
"""
function scenario_data(scenario::Symbol)
    columns = scenario === :dense ? _dense_columns() :
        scenario === :sparse ? _sparse_columns() :
        throw(ArgumentError("scenario must be :dense or :sparse"))
    return FacetData(
        columns;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

function rating_fraction(data::FacetData)
    denominator = length(data.person_levels) * length(data.rater_levels) *
        length(data.item_levels)
    return data.n / denominator
end

function _model_spec(data::FacetData, family::Symbol)
    family === :mfrm && return mfrm_spec(
        data;
        thresholds = :partial_credit,
    )
    family === :gmfrm && return mfrm_spec(
        data;
        family = :gmfrm,
        thresholds = :partial_credit,
        discrimination = :rater,
    )
    family === :mgmfrm && return mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = _Q_MATRIX,
    )
    throw(ArgumentError("family must be :mfrm, :gmfrm, or :mgmfrm"))
end

function _truth_pattern(n_parameters::Int, scale::Float64)
    return [scale * sin(index) for index in 1:n_parameters]
end

function _simulation_source(spec::FacetSpec, family::Symbol, truth_scale::Float64)
    if family === :mfrm
        design = getdesign(spec)
        return (;
            design,
            truth = _truth_pattern(length(initial_params(design)), truth_scale),
            parameter_space = :direct,
        )
    end

    design = BayesianMGMFRM.Experimental.preview(spec)
    target = family === :gmfrm ?
        BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(design) :
        BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(design)
    return (;
        design,
        truth = _truth_pattern(length(initial_params(target)), truth_scale),
        parameter_space = :raw,
    )
end

_direct_truth(family::Symbol, design::FacetDesign, truth) =
    family === :mfrm ? copy(truth) :
    family === :gmfrm ?
        BayesianMGMFRM._gmfrm_source_constrained_params_from_unconstrained(
            design,
            truth,
        ) :
        BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
            design,
            truth,
        )

"""
    simulated_case(family, scenario; seed, truth_scale = 0.15)

Create one known-truth response dataset while retaining the intended 0:2
category scale even when a simulated sample does not use every category.
The returned truth is for simulation bookkeeping; a single short-chain run
must not be interpreted as parameter-recovery evidence.
"""
function simulated_case(family::Symbol, scenario::Symbol;
        seed::Integer,
        truth_scale::Real = 0.15)
    family in _FAMILIES ||
        throw(ArgumentError("family must be :mfrm, :gmfrm, or :mgmfrm"))
    isfinite(truth_scale) && truth_scale >= 0 ||
        throw(ArgumentError("truth_scale must be finite and non-negative"))
    source_data = scenario_data(scenario)
    source_spec = _model_spec(source_data, family)
    simulation = _simulation_source(source_spec, family, Float64(truth_scale))
    direct_truth = _direct_truth(
        family,
        simulation.design,
        simulation.truth,
    )
    simulated_data = simulate_responses(
        simulation.design,
        simulation.truth;
        rng = MersenneTwister(Int(seed)),
        parameter_space = simulation.parameter_space,
    )
    fitted_spec = _model_spec(simulated_data, family)
    return (;
        family,
        scenario,
        spec = fitted_spec,
        truth = simulation.truth,
        direct_truth,
        truth_parameter_space = simulation.parameter_space,
        truth_scale = Float64(truth_scale),
        simulation_seed = Int(seed),
        n_observations = simulated_data.n,
        rating_fraction = rating_fraction(simulated_data),
    )
end

function _fit_case(case, backend::Symbol, controls, seed::Int;
        cmdstan_path,
        cmdstan_cache_dir)
    common = (;
        backend,
        ndraws = controls.ndraws,
        warmup = controls.warmup,
        chains = controls.chains,
        step_size = controls.step_size,
        seed,
        target_accept = controls.target_accept,
        max_depth = controls.max_depth,
        metric = controls.metric,
        progress = false,
    )
    backend_options = backend === :cmdstan ? (;
        cmdstan_path,
        cmdstan_cache_dir,
    ) : NamedTuple()
    if case.family === :mfrm
        return fit(case.spec; common..., backend_options...)
    end
    return BayesianMGMFRM.Experimental.fit(
        case.spec;
        common...,
        backend_options...,
    )
end

_direct_draws(fit::MFRMFit) = fit.draws
_direct_draws(fit::Union{GMFRMFit,MGMFRMFit}) = fit.direct_draws

function _diagnostic_total(rows, field::Symbol)
    values = Int[]
    for row in rows
        value = getproperty(row, field)
        ismissing(value) || push!(values, Int(value))
    end
    return isempty(values) ? missing : sum(values)
end

function _diagnostic_extreme(rows, field::Symbol, reducer)
    values = Float64[]
    for row in rows
        value = getproperty(row, field)
        ismissing(value) && continue
        converted = Float64(value)
        isfinite(converted) && push!(values, converted)
    end
    return isempty(values) ? NaN : reducer(values)
end

function _fit_record(case, backend::Symbol, controls, fit_result, elapsed_seconds)
    direct_draws = _direct_draws(fit_result)
    pointwise = pointwise_loglikelihood_matrix(fit_result)
    probabilities = predictive_probabilities(fit_result)
    probability_sums = dropdims(sum(probabilities; dims = 3); dims = 3)
    sampler_rows = sampler_diagnostics(fit_result)
    mcmc_rows = controls.convergence_assessed ?
        mcmc_diagnostics(fit_result) : NamedTuple[]
    sampler_flags = Tuple(sort(unique(
        row.flag for row in sampler_rows if row.flag !== :ok,
    ); by = string))
    n_mcmc_warning_parameters = count(
        row -> row.flag !== :ok,
        mcmc_rows,
    )
    n_failed_direct_constraints = fit_result isa MFRMFit ? 0 :
        Int(fit_result.diagnostic_surface.summary.n_failed_direct_constraints)
    execution_passed = all(isfinite, direct_draws) &&
        all(isfinite, fit_result.log_posterior) &&
        all(isfinite, pointwise) && all(isfinite, probabilities) &&
        maximum(abs.(probability_sums .- 1)) <= 1e-10 &&
        n_failed_direct_constraints == 0
    row = (;
        family = case.family,
        scenario = case.scenario,
        backend,
        profile = controls.profile,
        claim_scope = controls.claim_scope,
        n_observations = case.n_observations,
        rating_fraction = case.rating_fraction,
        n_draws = size(direct_draws, 1),
        n_direct_parameters = size(direct_draws, 2),
        elapsed_seconds = Float64(elapsed_seconds),
        timing_scope = :single_local_run_includes_jit_and_cache_state_not_benchmark,
        execution_passed,
        convergence_assessed = controls.convergence_assessed,
        n_mcmc_warning_parameters,
        max_rank_normalized_rhat = _diagnostic_extreme(
            mcmc_rows,
            :rank_normalized_rhat,
            maximum,
        ),
        min_bulk_ess = _diagnostic_extreme(mcmc_rows, :bulk_ess, minimum),
        min_tail_ess = _diagnostic_extreme(mcmc_rows, :tail_ess, minimum),
        n_failed_direct_constraints,
        n_divergences = _diagnostic_total(sampler_rows, :n_divergences),
        n_max_treedepth = _diagnostic_total(sampler_rows, :n_max_treedepth),
        sampler_flags,
        maximum_probability_sum_error = maximum(abs.(probability_sums .- 1)),
        mean_expected_score = mean(expected_scores(fit_result)),
    )
    return (; row, fit = fit_result, direct_draws)
end

function _paired_row(advancedhmc, cmdstan)
    left = advancedhmc.fit
    right = cmdstan.fit
    left_expected = vec(mean(expected_scores(left); dims = 1))
    right_expected = vec(mean(expected_scores(right); dims = 1))
    left_parameter_mean = vec(mean(advancedhmc.direct_draws; dims = 1))
    right_parameter_mean = vec(mean(cmdstan.direct_draws; dims = 1))
    length(left_expected) == length(right_expected) ||
        throw(ArgumentError("paired fits have different observation counts"))
    length(left_parameter_mean) == length(right_parameter_mean) ||
        throw(ArgumentError("paired fits have different direct parameter counts"))
    expected_difference = abs.(left_expected .- right_expected)
    parameter_difference = abs.(left_parameter_mean .- right_parameter_mean)
    return (;
        family = advancedhmc.row.family,
        scenario = advancedhmc.row.scenario,
        profile = advancedhmc.row.profile,
        both_executed = advancedhmc.row.execution_passed &&
            cmdstan.row.execution_passed,
        mean_expected_score_absolute_difference = mean(expected_difference),
        maximum_expected_score_absolute_difference = maximum(expected_difference),
        maximum_direct_parameter_mean_absolute_difference =
            maximum(parameter_difference),
        comparison_status = :descriptive_only,
        interpretation = :short_mcmc_not_backend_equivalence_or_recovery_evidence,
    )
end

"""
    run_validation(; profile = :smoke, families = (:mfrm, :gmfrm, :mgmfrm),
        scenarios = (:dense, :sparse), cmdstan_path = nothing,
        cmdstan_cache_dir = nothing)

Fit the same simulated response data with AdvancedHMC and CmdStan for every
selected model/design cell. Runtime errors are deliberately not caught: an
unavailable CmdStan installation, malformed output, or model failure aborts
the run with its original typed error. Short-chain results establish execution
and sparse-design wiring only; reported backend differences are descriptive.
"""
function run_validation(;
        profile::Symbol = :smoke,
        families = _FAMILIES,
        scenarios = _SCENARIOS,
        cmdstan_path::Union{Nothing,AbstractString} = nothing,
        cmdstan_cache_dir::Union{Nothing,AbstractString} = nothing)
    controls = validation_controls(profile)
    checked_families = _check_selection(families, _FAMILIES, "families")
    checked_scenarios = _check_selection(scenarios, _SCENARIOS, "scenarios")
    records = Dict{Tuple{Symbol,Symbol,Symbol},NamedTuple}()
    rows = NamedTuple[]
    pairs = NamedTuple[]

    case_index = 0
    for scenario in checked_scenarios, family in checked_families
        case_index += 1
        simulation_seed = 7_000 + case_index
        fit_seed = 8_000 + case_index
        case = simulated_case(family, scenario; seed = simulation_seed)
        for backend in (:advancedhmc, :cmdstan)
            started = time_ns()
            fit_result = _fit_case(
                case,
                backend,
                controls,
                fit_seed;
                cmdstan_path,
                cmdstan_cache_dir,
            )
            elapsed_seconds = (time_ns() - started) / 1.0e9
            record = _fit_record(
                case,
                backend,
                controls,
                fit_result,
                elapsed_seconds,
            )
            records[(family, scenario, backend)] = record
            push!(rows, record.row)
        end
        push!(pairs, _paired_row(
            records[(family, scenario, :advancedhmc)],
            records[(family, scenario, :cmdstan)],
        ))
    end

    execution_passed = all(row.execution_passed for row in rows)
    n_sampler_warning_rows = count(row -> !isempty(row.sampler_flags), rows)
    n_convergence_warning_rows = count(
        row -> row.n_mcmc_warning_parameters > 0,
        rows,
    )
    return (;
        profile,
        claim_scope = controls.claim_scope,
        controls,
        rows = Tuple(rows),
        pairs = Tuple(pairs),
        execution_passed,
        operability_passed = execution_passed,
        n_sampler_warning_rows,
        n_convergence_warning_rows,
        status = execution_passed ? :completed_operability_check : :failed,
        diagnostic_decision = :not_applied_in_smoke_or_pilot,
        caveat = :not_repeated_parameter_recovery_or_backend_equivalence_evidence,
        timing_caveat = :single_run_times_include_jit_and_cache_state_not_benchmark_evidence,
    )
end

function print_summary(result; io::IO = stdout)
    println(io, "profile\tfamily\tscenario\tbackend\tN\tdensity\tseconds\tdivergences\tflags")
    for row in result.rows
        println(io, join((
            row.profile,
            row.family,
            row.scenario,
            row.backend,
            row.n_observations,
            round(row.rating_fraction; digits = 3),
            round(row.elapsed_seconds; digits = 3),
            row.n_divergences,
            isempty(row.sampler_flags) ? "ok" : join(string.(row.sampler_flags), ","),
        ), '\t'))
    end
    println(io)
    println(io, "profile\tfamily\tscenario\tmean_expected_score_abs_diff\tmax_expected_score_abs_diff\tmax_parameter_mean_abs_diff")
    for pair in result.pairs
        println(io, join((
            pair.profile,
            pair.family,
            pair.scenario,
            round(pair.mean_expected_score_absolute_difference; digits = 4),
            round(pair.maximum_expected_score_absolute_difference; digits = 4),
            round(pair.maximum_direct_parameter_mean_absolute_difference; digits = 4),
        ), '\t'))
    end
    println(io, "status\t", result.status)
    println(io, "claim_scope\t", result.claim_scope)
    println(io, "diagnostic_decision\t", result.diagnostic_decision)
    println(io, "caveat\t", result.caveat)
    println(io, "timing_caveat\t", result.timing_caveat)
    return nothing
end

function main(args = ARGS)
    length(args) <= 1 || throw(ArgumentError(
        "usage: julia --project=. scripts/run_cmdstan_backend_validation.jl [smoke|pilot]",
    ))
    profile = isempty(args) ? :smoke : Symbol(args[1])
    result = run_validation(; profile)
    print_summary(result)
    result.execution_passed || error("paired backend validation failed")
    return result
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    CmdStanBackendValidation.main()
end
