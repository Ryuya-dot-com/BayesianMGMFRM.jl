isdefined(@__MODULE__, :CmdStanBackendValidation) ||
    include(joinpath(@__DIR__, "run_cmdstan_backend_validation.jl"))

module CmdStanRecoveryPilot

using Statistics

using BayesianMGMFRM

const Validation = getfield(parentmodule(@__MODULE__), :CmdStanBackendValidation)

function _fit_row(case, backend::Symbol, controls, fit_result,
        elapsed_seconds::Float64, replication::Int, interval::Float64)
    execution = Validation._fit_record(
        case,
        backend,
        controls,
        fit_result,
        elapsed_seconds,
    ).row
    recovery = parameter_recovery(
        fit_result,
        case.direct_truth;
        interval,
        parameter_space = :direct,
    )
    overall = only(parameter_recovery_summary(recovery; by = :all))
    blocks = parameter_recovery_summary(recovery; by = :block)
    return merge(execution, (;
        replication,
        simulation_seed = case.simulation_seed,
        truth_scale = case.truth_scale,
        interval_probability = interval,
        mean_bias = overall.mean_bias,
        mean_absolute_error = overall.mean_absolute_error,
        rmse = overall.rmse,
        max_absolute_error = overall.max_absolute_error,
        coverage_rate = overall.coverage_rate,
        coverage_gap = overall.coverage_gap,
        mean_interval_width = overall.mean_interval_width,
        max_block_mean_absolute_error =
            maximum(row.mean_absolute_error for row in blocks),
        min_block_coverage_rate =
            minimum(row.coverage_rate for row in blocks),
    ))
end

function aggregate_row(rows, family::Symbol, backend::Symbol)
    selected = [row for row in rows
        if row.family === family && row.backend === backend]
    isempty(selected) && throw(ArgumentError(
        "recovery aggregate has no $family/$backend rows",
    ))
    return (;
        family,
        backend,
        n_replications = length(selected),
        mean_absolute_error = mean(row.mean_absolute_error for row in selected),
        mean_rmse = mean(row.rmse for row in selected),
        mean_coverage_rate = mean(row.coverage_rate for row in selected),
        mean_interval_width = mean(row.mean_interval_width for row in selected),
        maximum_absolute_error = maximum(row.max_absolute_error for row in selected),
        maximum_block_mean_absolute_error =
            maximum(row.max_block_mean_absolute_error for row in selected),
        minimum_block_coverage_rate =
            minimum(row.min_block_coverage_rate for row in selected),
        total_elapsed_seconds = sum(row.elapsed_seconds for row in selected),
        n_execution_failures = count(row -> !row.execution_passed, selected),
        n_sampler_warning_fits = count(row -> !isempty(row.sampler_flags), selected),
        n_convergence_warning_fits = count(
            row -> row.n_mcmc_warning_parameters > 0,
            selected,
        ),
        total_divergences = sum(
            ismissing(row.n_divergences) ? 0 : row.n_divergences
            for row in selected
        ),
        total_max_treedepth = sum(
            ismissing(row.n_max_treedepth) ? 0 : row.n_max_treedepth
            for row in selected
        ),
        maximum_rank_normalized_rhat = maximum(
            row.max_rank_normalized_rhat for row in selected
        ),
        minimum_bulk_ess = minimum(row.min_bulk_ess for row in selected),
        minimum_tail_ess = minimum(row.min_tail_ess for row in selected),
        interpretation = :descriptive_small_replication_pilot,
    )
end

function _paired_row(advancedhmc, cmdstan)
    return (;
        family = advancedhmc.family,
        scenario = advancedhmc.scenario,
        replication = advancedhmc.replication,
        cmdstan_minus_advancedhmc_mae =
            cmdstan.mean_absolute_error - advancedhmc.mean_absolute_error,
        cmdstan_minus_advancedhmc_rmse = cmdstan.rmse - advancedhmc.rmse,
        cmdstan_minus_advancedhmc_coverage =
            cmdstan.coverage_rate - advancedhmc.coverage_rate,
        comparison_status = :descriptive_only,
        interpretation = :too_few_replications_for_backend_ranking,
    )
end

"""
    run_pilot(; replications = 2, scenario = :sparse,
        truth_scale = 0.15, interval = 0.8,
        families = (:mfrm, :gmfrm, :mgmfrm))

Run a small paired known-truth pilot with the validation module's `:pilot`
sampler budget. Every replication uses one simulated dataset for both backends
and evaluates recovery on the common identified direct-parameter scale. No
pass threshold or backend ranking is applied. Runtime and model errors are not
caught.
"""
function run_pilot(;
        replications::Int = 2,
        scenario::Symbol = :sparse,
        truth_scale::Real = 0.15,
        interval::Real = 0.8,
        families = Validation._FAMILIES,
        cmdstan_path::Union{Nothing,AbstractString} = nothing,
        cmdstan_cache_dir::Union{Nothing,AbstractString} = nothing)
    replications >= 1 || throw(ArgumentError("replications must be positive"))
    scenario in Validation._SCENARIOS ||
        throw(ArgumentError("scenario must be :dense or :sparse"))
    isfinite(truth_scale) && truth_scale > 0 ||
        throw(ArgumentError("truth_scale must be finite and positive"))
    0 < interval < 1 || throw(ArgumentError("interval must be in (0, 1)"))
    checked_families = Validation._check_selection(
        families,
        Validation._FAMILIES,
        "families",
    )
    controls = Validation.validation_controls(:pilot)
    rows = NamedTuple[]
    paired_rows = NamedTuple[]

    for replication in 1:replications
        for (family_index, family) in Base.pairs(checked_families)
            case = Validation.simulated_case(
                family,
                scenario;
                seed = 12_000 + 100 * replication + family_index,
                truth_scale,
            )
            fit_seed = 13_000 + 100 * replication + family_index
            backend_rows = Dict{Symbol,NamedTuple}()
            for backend in (:advancedhmc, :cmdstan)
                started = time_ns()
                fit_result = Validation._fit_case(
                    case,
                    backend,
                    controls,
                    fit_seed;
                    cmdstan_path,
                    cmdstan_cache_dir,
                )
                row = _fit_row(
                    case,
                    backend,
                    controls,
                    fit_result,
                    (time_ns() - started) / 1.0e9,
                    replication,
                    Float64(interval),
                )
                backend_rows[backend] = row
                push!(rows, row)
            end
            push!(paired_rows, _paired_row(
                backend_rows[:advancedhmc],
                backend_rows[:cmdstan],
            ))
        end
    end

    aggregates = [
        aggregate_row(rows, family, backend)
        for family in checked_families
        for backend in (:advancedhmc, :cmdstan)
    ]
    execution_passed = all(row.execution_passed for row in rows)
    return (;
        profile = :recovery_pilot,
        scenario,
        replications,
        truth_scale = Float64(truth_scale),
        interval = Float64(interval),
        controls,
        rows = Tuple(rows),
        pairs = Tuple(paired_rows),
        aggregates = Tuple(aggregates),
        execution_passed,
        operability_passed = execution_passed,
        status = execution_passed ? :completed_descriptive_pilot : :failed,
        claim_scope = :small_repeated_known_truth_pilot_not_calibration_evidence,
        diagnostic_decision = :not_applied_in_pilot,
        caveat = :no_pass_threshold_or_backend_ranking_from_pilot,
        next_gate = :design_separate_validation_protocol_on_fresh_seeds,
    )
end

function print_summary(result; io::IO = stdout)
    println(io, "family\tbackend\treps\tmean_MAE\tmean_RMSE\tmean_coverage\tmax_block_MAE\tmax_Rhat\tmin_bulk_ESS\tmin_tail_ESS\tdivergences\tsampler_warning_fits\tmcmc_warning_fits\tseconds")
    for row in result.aggregates
        println(io, join((
            row.family,
            row.backend,
            row.n_replications,
            round(row.mean_absolute_error; digits = 4),
            round(row.mean_rmse; digits = 4),
            round(row.mean_coverage_rate; digits = 4),
            round(row.maximum_block_mean_absolute_error; digits = 4),
            round(row.maximum_rank_normalized_rhat; digits = 3),
            round(row.minimum_bulk_ess; digits = 1),
            round(row.minimum_tail_ess; digits = 1),
            row.total_divergences,
            row.n_sampler_warning_fits,
            row.n_convergence_warning_fits,
            round(row.total_elapsed_seconds; digits = 3),
        ), '\t'))
    end
    println(io, "status\t", result.status)
    println(io, "claim_scope\t", result.claim_scope)
    println(io, "diagnostic_decision\t", result.diagnostic_decision)
    println(io, "caveat\t", result.caveat)
    println(io, "next_gate\t", result.next_gate)
    return nothing
end

function main(args = ARGS)
    length(args) <= 1 || throw(ArgumentError(
        "usage: julia --project=. scripts/run_cmdstan_recovery_pilot.jl [replications]",
    ))
    parsed = isempty(args) ? 2 : tryparse(Int, args[1])
    parsed === nothing && throw(ArgumentError("replications must be an integer"))
    result = run_pilot(; replications = Int(parsed))
    print_summary(result)
    result.execution_passed || error("paired recovery pilot failed")
    return result
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    CmdStanRecoveryPilot.main()
end
