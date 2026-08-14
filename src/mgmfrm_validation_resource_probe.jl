# Portable, MCMC-free resource profiling for the fixed-Q MGMFRM candidate.

const _MGMFRM_VALIDATION_RESOURCE_PROBE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_validation_resource_probe.v1"
const _MGMFRM_VALIDATION_SHORT_NUTS_RESOURCE_PROBE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_validation_short_nuts_resource_probe.v1"

function _mgmfrm_validation_resource_probe_policy()
    return (;
        phase = :initial_gradient_resource_probe,
        operation = :forwarddiff_logdensity_and_gradient,
        default_repetitions = 3,
        minimum_repetitions = 1,
        maximum_repetitions = 5,
        default_maximum_cells = 2,
        hard_maximum_cells = 4,
        default_maximum_observations_per_cell = 10_000,
        hard_maximum_observations_per_cell = 10_000,
        hard_maximum_probability_cells_per_cell = 50_000,
        adapter_validation_evaluations = 1,
        warmup_evaluations = 1,
        gc_before_each_timed_evaluation = true,
        response_pattern = :regular_all_categories,
        prior_regime = :implementation_reference,
        backend = :advancedhmc_target_only,
        mcmc_allowed = false,
        fit_runtime_extrapolation_allowed = false,
        measurement_thresholds_applied = false,
        final_resource_policy_may_be_frozen_from_this_probe_alone = false,
        bounded_short_nuts_probe_required_next = true,
        permitted_uses = (
            :estimate_local_gradient_cost,
            :choose_bounded_short_nuts_cells,
            :choose_batch_size,
            :identify_obviously_infeasible_shapes,
        ),
        prohibited_uses = (
            :scientific_threshold_selection,
            :recovery_or_coverage_evidence,
            :backend_ranking,
            :prior_selection,
            :q_selection,
            :performance_claim,
        ),
    )
end

function _mgmfrm_validation_short_nuts_resource_probe_policy()
    controls = _mgmfrm_stress_fit_controls(:short_nuts_resource_probe)
    return (;
        phase = :bounded_short_nuts_resource_probe,
        profile = controls.profile,
        controls,
        backend = :advancedhmc,
        prior_regime = :implementation_reference,
        response_pattern = :regular_all_categories,
        default_design = :connected_sparse_systematic_link,
        maximum_cells = 1,
        default_maximum_observations_per_cell = 1_000,
        hard_maximum_observations_per_cell = 2_000,
        hard_maximum_probability_cells_per_cell = 10_000,
        default_minimum_free_memory_bytes = Int64(2 * 1024^3),
        hard_minimum_free_memory_bytes = Int64(1024^3),
        scaled_resource_plan_function =
            :mgmfrm_validation_scaled_resource_plan,
        explicit_execution_required = true,
        convergence_assessed = false,
        peak_memory_measured = false,
        maxrss_measurement = :process_lifetime_before_and_after,
        maxrss_is_probe_attributable = false,
        isolated_process_required_for_peak_attribution = true,
        measurement_thresholds_applied = false,
        final_resource_policy_may_be_frozen_from_this_probe_alone = false,
        permitted_uses = (
            :verify_short_nuts_operability,
            :measure_local_short_chain_runtime,
            :measure_cumulative_julia_allocations,
            :choose_next_scaled_resource_cell,
        ),
        prohibited_uses = (
            :scientific_threshold_selection,
            :convergence_claim,
            :recovery_or_coverage_evidence,
            :backend_ranking,
            :prior_selection,
            :q_selection,
            :performance_claim,
            :full_nuts_runtime_extrapolation,
        ),
    )
end

function _mgmfrm_validation_default_resource_probe_plan()
    return Tuple(mgmfrm_response_stress_plan(
        design_strata = (
            :dense_fully_crossed,
            :connected_sparse_systematic_link,
        ),
        response_patterns = (:regular_all_categories,),
        replications = 1,
        base_seed = 20260816,
    ))
end

function _mgmfrm_validation_default_short_nuts_resource_probe_plan()
    return Tuple(mgmfrm_response_stress_plan(
        design_strata = (:connected_sparse_systematic_link,),
        response_patterns = (:regular_all_categories,),
        replications = 1,
        base_seed = 20260817,
    ))
end

function _mgmfrm_validation_scaled_resource_cell(
        cell_id::Symbol,
        sequence::Int,
        design::Symbol,
        n_persons::Int,
        n_items::Int,
        n_raters::Int,
        role::Symbol,
        seed::Int)
    source = only(mgmfrm_response_stress_plan(
        design_strata = (design,),
        response_patterns = (:regular_all_categories,),
        replications = 1,
        base_seed = seed,
        n_persons = n_persons,
        n_items = n_items,
        n_raters = n_raters,
    ))
    return merge(source, (;
        attempt_id = cell_id,
        attempt_index = sequence,
        resource_sequence = sequence,
        resource_role = role,
        resource_claim_scope = :operational_scaling_only,
        prerequisite = sequence == 1 ?
            :default_sparse_short_nuts_completed_operationally :
            :all_previous_resource_cells_completed_operationally,
    ))
end

"""
    mgmfrm_validation_scaled_resource_plan()

Return four ordered, non-executing resource cells for the fixed-Q MGMFRM
short-NUTS probe. The sequence adds a small dense cell, matched-observation
sparse and dense cells, then a larger sparse cell. Every row remains compatible
with [`mgmfrm_validation_short_nuts_resource_probe`](@ref), but must be passed
and executed one at a time.

The plan is operational rather than scientific. It does not select the final
sample-size grid, run MCMC, use evaluation seeds, or authorize automatic
progression after a failure or memory rejection.
"""
function mgmfrm_validation_scaled_resource_plan()
    rows = (
        _mgmfrm_validation_scaled_resource_cell(
            :scaled_resource_01_dense_small,
            1, :dense_fully_crossed, 12, 4, 3,
            :density_boundary_after_sparse_baseline, 20260818),
        _mgmfrm_validation_scaled_resource_cell(
            :scaled_resource_02_sparse_medium,
            2, :connected_sparse_systematic_link, 50, 6, 5,
            :increase_parameter_and_observation_scale, 20260819),
        _mgmfrm_validation_scaled_resource_cell(
            :scaled_resource_03_dense_medium,
            3, :dense_fully_crossed, 20, 6, 5,
            :match_sparse_medium_observation_count, 20260820),
        _mgmfrm_validation_scaled_resource_cell(
            :scaled_resource_04_sparse_large,
            4, :connected_sparse_systematic_link, 100, 10, 15,
            :upper_bounded_sparse_operational_shape, 20260821),
    )
    expected_observations = Tuple(
        _mgmfrm_validation_probe_expected_observations(row) for row in rows)
    expected_observations == (144, 600, 600, 2_000) ||
        throw(ArgumentError(
            "scaled resource plan observation counts are inconsistent",
        ))
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_validation_scaled_resource_plan.v1",
        object = :mgmfrm_validation_scaled_resource_plan,
        status = :predeclared_not_run,
        rows,
        expected_observations,
        execution_order = Tuple(row.attempt_id for row in rows),
        execution_mode = :one_cell_per_explicit_invocation,
        automatic_progression_allowed = false,
        stop_conditions = (
            :memory_preflight_rejected,
            :generation_or_fit_failure,
            :diagnostic_failure,
            :unexpected_allocation_growth,
        ),
        final_analysis_grid_selected = false,
        mcmc_executed = false,
        primary_evaluation_seed_used = false,
        scientific_decision = :not_applied,
        claim_scope = :mcmc_free_operational_scaling_plan,
    )
end

function _mgmfrm_validation_probe_integer(value::Integer,
        label::AbstractString; minimum::Int = 1)
    checked = Int(value)
    checked >= minimum || throw(ArgumentError("$label must be >= $minimum"))
    return checked
end

function _mgmfrm_validation_probe_expected_observations(row)
    if row.design === :dense_fully_crossed
        return Int(row.n_persons) * Int(row.n_items) * Int(row.n_raters)
    elseif row.design === :connected_sparse_systematic_link
        return Int(row.n_persons) * Int(row.n_items) *
            Int(row.raters_per_person)
    end
    throw(ArgumentError(
        "unsupported resource-probe design :$(row.design)"))
end

function _mgmfrm_validation_checked_resource_probe_plan(
        plan,
        policy,
        maximum_cells::Int,
        maximum_observations_per_cell::Int)
    rows = Tuple(plan)
    isempty(rows) && throw(ArgumentError("resource-probe plan must not be empty"))
    length(rows) <= maximum_cells || throw(ArgumentError(
        "resource-probe plan has $(length(rows)) cells, exceeding " *
        "maximum_cells = $maximum_cells",
    ))
    ids = Symbol[]
    for row in rows
        hasproperty(row, :object) &&
            row.object === :mgmfrm_response_stress_plan_row ||
            throw(ArgumentError(
                "resource-probe rows must come from mgmfrm_response_stress_plan",
            ))
        row.response_pattern === policy.response_pattern ||
            throw(ArgumentError(
                "resource probing is restricted to regular response cells",
            ))
        row.q_structure === :pure_between_item_two_dimensions ||
            throw(ArgumentError(
                "resource probing currently requires the pure fixed-Q branch",
            ))
        expected_observations =
            _mgmfrm_validation_probe_expected_observations(row)
        expected_observations <= maximum_observations_per_cell ||
            throw(ArgumentError(
                "resource-probe cell $(row.attempt_id) has " *
                "$expected_observations observations, exceeding " *
                "maximum_observations_per_cell = " *
                "$maximum_observations_per_cell",
            ))
        expected_probability_cells =
            expected_observations * Int(row.n_categories)
        expected_probability_cells <=
            policy.hard_maximum_probability_cells_per_cell ||
            throw(ArgumentError(
                "resource-probe cell $(row.attempt_id) exceeds the hard " *
                "probability-cell bound",
            ))
        push!(ids, Symbol(row.attempt_id))
    end
    length(unique(ids)) == length(ids) || throw(ArgumentError(
        "resource-probe attempt_id values must be unique",
    ))
    return rows
end

function _mgmfrm_validation_resource_probe_runtime()
    return (;
        julia_version = string(VERSION),
        n_threads = Threads.nthreads(),
        cpu_threads = Sys.CPU_THREADS,
        os = string(Sys.KERNEL),
        arch = string(Sys.ARCH),
        total_memory_bytes = Int64(Sys.total_memory()),
        process_lifetime_maxrss_bytes = Int64(Sys.maxrss()),
    )
end

function _mgmfrm_validation_resource_probe_measure(case, repetitions::Int,
        policy)
    prior = _source_fixture_prior(
        _mgmfrm_stress_prior(policy.prior_regime))
    free_memory_before = Int64(Sys.free_memory())
    setup = @timed begin
        target = _mgmfrm_guarded_local_fit_logdensity(
            case.design; prior)
        initial = initial_params(target)
        adapter = _logdensity_gradient_target(
            target, initial, :ForwardDiff).target
        (; target, initial, adapter)
    end
    payload = setup.value
    dimension = LogDensityProblems.dimension(payload.target)
    length(payload.initial) == dimension || throw(ArgumentError(
        "resource-probe initial parameter dimension is inconsistent",
    ))

    for _ in 1:policy.warmup_evaluations
        logdensity, gradient = LogDensityProblems.logdensity_and_gradient(
            payload.adapter, payload.initial)
        _check_logdensity_gradient_result(
            logdensity, gradient, dimension, :ForwardDiff)
    end

    timed_rows = NamedTuple[]
    for repetition in 1:repetitions
        policy.gc_before_each_timed_evaluation && GC.gc()
        timed = @timed LogDensityProblems.logdensity_and_gradient(
            payload.adapter, payload.initial)
        logdensity, gradient = timed.value
        _check_logdensity_gradient_result(
            logdensity, gradient, dimension, :ForwardDiff)
        elapsed_seconds = Float64(timed.time)
        gc_seconds = Float64(timed.gctime)
        push!(timed_rows, (;
            repetition,
            elapsed_seconds,
            allocated_bytes = Int(timed.bytes),
            gc_seconds,
            gc_time_fraction = iszero(elapsed_seconds) ? 0.0 :
                gc_seconds / elapsed_seconds,
            logdensity = Float64(logdensity),
            gradient_length = length(gradient),
            maximum_absolute_gradient =
                maximum(abs, gradient; init = 0.0),
        ))
    end
    free_memory_after = Int64(Sys.free_memory())
    rows = Tuple(timed_rows)
    return (;
        initial_parameter_dimension = dimension,
        adapter_setup_seconds = Float64(setup.time),
        adapter_setup_allocated_bytes = Int(setup.bytes),
        adapter_validation_evaluations =
            policy.adapter_validation_evaluations,
        warmup_evaluations = policy.warmup_evaluations,
        timed_evaluations = repetitions,
        free_memory_bytes_before = free_memory_before,
        free_memory_bytes_after = free_memory_after,
        minimum_free_memory_bytes_observed =
            min(free_memory_before, free_memory_after),
        timed_rows = rows,
        median_gradient_seconds = median(
            row.elapsed_seconds for row in rows),
        median_allocated_bytes = median(
            row.allocated_bytes for row in rows),
        median_gc_time_fraction = median(
            row.gc_time_fraction for row in rows),
    )
end

function _mgmfrm_validation_resource_probe_measurement_valid(
        measurement,
        repetitions::Int,
        policy)
    measurement isa NamedTuple ||
        throw(ArgumentError(
            "resource-probe measurement must be a NamedTuple",
        ))
    required = (
        :initial_parameter_dimension, :adapter_validation_evaluations,
        :warmup_evaluations, :timed_evaluations, :timed_rows,
        :median_gradient_seconds, :median_allocated_bytes,
        :minimum_free_memory_bytes_observed,
    )
    all(field -> hasproperty(measurement, field), required) ||
        throw(ArgumentError("resource-probe measurement is incomplete"))
    measurement.initial_parameter_dimension isa Integer &&
        measurement.initial_parameter_dimension > 0 ||
        throw(ArgumentError("resource-probe dimension must be positive"))
    measurement.adapter_validation_evaluations ==
        policy.adapter_validation_evaluations &&
        measurement.warmup_evaluations == policy.warmup_evaluations &&
        measurement.timed_evaluations == repetitions ||
        throw(ArgumentError("resource-probe counts are inconsistent"))
    measurement.timed_rows isa Tuple &&
        length(measurement.timed_rows) == repetitions ||
        throw(ArgumentError("resource-probe timed rows are inconsistent"))
    all(value -> isfinite(value) && value >= 0, (
        measurement.median_gradient_seconds,
        measurement.median_allocated_bytes,
    )) || throw(ArgumentError("resource-probe summaries are invalid"))
    all(row -> row.gradient_length ==
            measurement.initial_parameter_dimension &&
        isfinite(row.elapsed_seconds) && row.elapsed_seconds >= 0 &&
        isfinite(row.logdensity), measurement.timed_rows) ||
        throw(ArgumentError("resource-probe timed rows are invalid"))
    return measurement
end

function _mgmfrm_validation_resource_probe_base_row(row, index::Int)
    expected_observations =
        _mgmfrm_validation_probe_expected_observations(row)
    return (;
        cell_id = row.attempt_id,
        cell_index = index,
        design = row.design,
        response_pattern = row.response_pattern,
        n_persons = Int(row.n_persons),
        n_items = Int(row.n_items),
        n_raters = Int(row.n_raters),
        n_categories = Int(row.n_categories),
        expected_observations,
        expected_probability_cells =
            expected_observations * Int(row.n_categories),
        simulation_seed = Int(row.seed),
    )
end

function _mgmfrm_validation_resource_probe_row(base;
        status::Symbol,
        terminal::Bool,
        generation_seconds::Real = 0.0,
        generation_allocated_bytes::Integer = 0,
        actual_observations = missing,
        measurement = missing,
        error_phase = missing,
        error = missing)
    return merge(base, (;
        status,
        terminal,
        generation_seconds = Float64(generation_seconds),
        generation_allocated_bytes = Int(generation_allocated_bytes),
        actual_observations,
        measurement,
        error_phase,
        error_type = ismissing(error) ? missing : string(typeof(error)),
        error_message = ismissing(error) ? missing : sprint(showerror, error),
        error,
    ))
end

function _mgmfrm_validation_resource_probe(
        plan;
        execute_measurement::Bool,
        repetitions::Integer,
        maximum_cells::Integer,
        maximum_observations_per_cell::Integer,
        truth_scale::Real,
        measurement_executor =
            _mgmfrm_validation_resource_probe_measure)
    policy = _mgmfrm_validation_resource_probe_policy()
    checked_repetitions = _mgmfrm_validation_probe_integer(
        repetitions, "repetitions";
        minimum = policy.minimum_repetitions,
    )
    checked_repetitions <= policy.maximum_repetitions ||
        throw(ArgumentError(
            "repetitions exceeds the resource-probe maximum",
        ))
    checked_maximum_cells = _mgmfrm_validation_probe_integer(
        maximum_cells, "maximum_cells")
    checked_maximum_cells <= policy.hard_maximum_cells ||
        throw(ArgumentError(
            "maximum_cells exceeds the hard resource-probe maximum",
        ))
    checked_maximum_observations = _mgmfrm_validation_probe_integer(
        maximum_observations_per_cell,
        "maximum_observations_per_cell",
    )
    checked_maximum_observations <=
        policy.hard_maximum_observations_per_cell ||
        throw(ArgumentError(
            "maximum_observations_per_cell exceeds the hard resource bound",
        ))
    isfinite(truth_scale) && truth_scale > 0 || throw(ArgumentError(
        "truth_scale must be finite and positive",
    ))
    rows = _mgmfrm_validation_checked_resource_probe_plan(
        plan,
        policy,
        checked_maximum_cells,
        checked_maximum_observations,
    )

    if !execute_measurement
        planned_rows = Tuple(
            _mgmfrm_validation_resource_probe_row(
                _mgmfrm_validation_resource_probe_base_row(row, index);
                status = :planned_not_measured,
                terminal = false,
            ) for (index, row) in pairs(rows)
        )
        return (;
            schema = _MGMFRM_VALIDATION_RESOURCE_PROBE_SCHEMA,
            object = :mgmfrm_validation_resource_probe,
            status = :resource_probe_planned_measurement_not_executed,
            execute_measurement = false,
            policy,
            repetitions = checked_repetitions,
            maximum_cells = checked_maximum_cells,
            maximum_observations_per_cell =
                checked_maximum_observations,
            runtime = missing,
            rows = planned_rows,
            summary = (;
                n_planned_cells = length(rows),
                n_terminal_cells = 0,
                n_completed = 0,
                n_failed = 0,
                denominator_preserved = true,
            ),
            mcmc_executed = false,
            fit_objects_returned = false,
            recovery_evidence_available = false,
            scientific_execution_authorized = false,
            primary_evaluation_seed_used = false,
            final_resource_policy_frozen = false,
            claim_scope = :planning_only_no_measurement,
            next_gate = :execute_initial_gradient_resource_probe,
        )
    end

    result_rows = NamedTuple[]
    for (index, row) in pairs(rows)
        base = _mgmfrm_validation_resource_probe_base_row(row, index)
        generated = try
            @timed simulate_mgmfrm_response_stress(row; truth_scale)
        catch err
            _mgmfrm_stress_fatal_exception(err) && rethrow()
            err
        end
        if generated isa Exception
            push!(result_rows, _mgmfrm_validation_resource_probe_row(
                base;
                status = :generation_failed,
                terminal = true,
                error_phase = :generation_and_preflight,
                error = generated,
            ))
            continue
        end
        case = generated.value
        if !case.preflight_passed || !case.fit_eligible
            push!(result_rows, _mgmfrm_validation_resource_probe_row(
                base;
                status = :pre_fit_rejected,
                terminal = true,
                generation_seconds = generated.time,
                generation_allocated_bytes = generated.bytes,
                actual_observations = case.data.n,
            ))
            continue
        end
        measurement = try
            _mgmfrm_validation_resource_probe_measurement_valid(
                measurement_executor(case, checked_repetitions, policy),
                checked_repetitions,
                policy,
            )
        catch err
            _mgmfrm_stress_fatal_exception(err) && rethrow()
            err
        end
        if measurement isa Exception
            push!(result_rows, _mgmfrm_validation_resource_probe_row(
                base;
                status = :gradient_measurement_failed,
                terminal = true,
                generation_seconds = generated.time,
                generation_allocated_bytes = generated.bytes,
                actual_observations = case.data.n,
                error_phase = :gradient_measurement,
                error = measurement,
            ))
            continue
        end
        push!(result_rows, _mgmfrm_validation_resource_probe_row(
            base;
            status = :completed,
            terminal = true,
            generation_seconds = generated.time,
            generation_allocated_bytes = generated.bytes,
            actual_observations = case.data.n,
            measurement,
        ))
    end

    completed = count(row -> row.status === :completed, result_rows)
    failed = length(result_rows) - completed
    return (;
        schema = _MGMFRM_VALIDATION_RESOURCE_PROBE_SCHEMA,
        object = :mgmfrm_validation_resource_probe,
        status = failed == 0 ?
            :runtime_probe_complete_operational_metadata_only :
            :runtime_probe_complete_with_recorded_failures,
        execute_measurement = true,
        policy,
        repetitions = checked_repetitions,
        maximum_cells = checked_maximum_cells,
        maximum_observations_per_cell = checked_maximum_observations,
        runtime = _mgmfrm_validation_resource_probe_runtime(),
        rows = Tuple(result_rows),
        summary = (;
            n_planned_cells = length(rows),
            n_terminal_cells = count(row -> row.terminal, result_rows),
            n_completed = completed,
            n_failed = failed,
            denominator_preserved = length(result_rows) == length(rows),
        ),
        mcmc_executed = false,
        fit_objects_returned = false,
        recovery_evidence_available = false,
        scientific_execution_authorized = false,
        primary_evaluation_seed_used = false,
        final_resource_policy_frozen = false,
        claim_scope = :local_operational_metadata_not_validation_evidence,
        next_gate = :bounded_short_nuts_resource_probe,
    )
end

"""
    mgmfrm_validation_resource_probe(
        plan = nothing; execute_measurement = false, repetitions = 3,
        maximum_cells = 2, maximum_observations_per_cell = 10_000,
        truth_scale = 0.15)

Plan or execute a portable, MCMC-free resource probe for fixed-Q MGMFRM.
The default plan contains one dense and one connected-sparse regular-response
cell. Execution measures generation and repeated ForwardDiff log-density/
gradient evaluations after one untimed warmup. Hard cell and observation bounds
are checked before generation.

The result records local runtime and allocation metadata without repository
paths, commit IDs, source hashes, or fit objects. It cannot assess convergence,
recovery, coverage, priors, Q, backend superiority, or scientific thresholds.
Gradient timings are not extrapolated to full NUTS runtime; a separate bounded
short-NUTS probe remains required before final resource caps can be frozen.
"""
function mgmfrm_validation_resource_probe(
        plan = nothing;
        execute_measurement::Bool = false,
        repetitions::Integer = 3,
        maximum_cells::Integer = 2,
        maximum_observations_per_cell::Integer = 10_000,
        truth_scale::Real = 0.15)
    selected_plan = isnothing(plan) ?
        _mgmfrm_validation_default_resource_probe_plan() : plan
    return _mgmfrm_validation_resource_probe(
        selected_plan;
        execute_measurement,
        repetitions,
        maximum_cells,
        maximum_observations_per_cell,
        truth_scale,
    )
end

# Explicit-execution, memory-guarded short-NUTS profiling.

function _mgmfrm_validation_default_short_nuts_runner(plan, truth_scale)
    return _mgmfrm_stress_fit_attempts(
        plan;
        profile = :short_nuts_resource_probe,
        backends = (:advancedhmc,),
        prior_regimes = (:implementation_reference,),
        maximum_attempts = 1,
        truth_scale,
        cmdstan_path = nothing,
        cmdstan_cache_dir = nothing,
    )
end

function _mgmfrm_validation_short_nuts_execution_state(rows)
    statuses = Tuple(row.terminal_status for row in rows)
    any(status -> status in (:completed, :diagnostic_failed), statuses) &&
        return :executed
    any(==(:fit_failed), statuses) && return :attempted_state_unknown
    return :not_started
end

function _mgmfrm_validation_short_nuts_base_result(
        plan,
        policy,
        runtime,
        free_memory_bytes::Int64,
        minimum_free_memory_bytes::Int64,
        maximum_observations_per_cell::Int)
    memory_preflight_passed =
        free_memory_bytes >= minimum_free_memory_bytes
    return (;
        schema = _MGMFRM_VALIDATION_SHORT_NUTS_RESOURCE_PROBE_SCHEMA,
        object = :mgmfrm_validation_short_nuts_resource_probe,
        policy,
        plan,
        runtime,
        preflight = (;
            free_memory_bytes_observed = free_memory_bytes,
            minimum_free_memory_bytes_required = minimum_free_memory_bytes,
            memory_preflight_passed,
            maximum_observations_per_cell,
            workload_preflight_passed = true,
        ),
    )
end

function _mgmfrm_validation_short_nuts_resource_probe(
        plan;
        execute_measurement::Bool,
        minimum_free_memory_bytes::Integer,
        maximum_observations_per_cell::Integer,
        truth_scale::Real,
        free_memory_provider = () -> Int64(Sys.free_memory()),
        maxrss_provider = () -> Int64(Sys.maxrss()),
        runner_executor = _mgmfrm_validation_default_short_nuts_runner)
    policy = _mgmfrm_validation_short_nuts_resource_probe_policy()
    checked_minimum_memory = _mgmfrm_validation_probe_integer(
        minimum_free_memory_bytes,
        "minimum_free_memory_bytes";
        minimum = Int(policy.hard_minimum_free_memory_bytes),
    )
    checked_maximum_observations = _mgmfrm_validation_probe_integer(
        maximum_observations_per_cell,
        "maximum_observations_per_cell",
    )
    checked_maximum_observations <=
        policy.hard_maximum_observations_per_cell ||
        throw(ArgumentError(
            "maximum_observations_per_cell exceeds the short-NUTS hard bound",
        ))
    isfinite(truth_scale) && truth_scale > 0 || throw(ArgumentError(
        "truth_scale must be finite and positive",
    ))
    checked_plan = _mgmfrm_validation_checked_resource_probe_plan(
        plan,
        policy,
        policy.maximum_cells,
        checked_maximum_observations,
    )
    runtime = _mgmfrm_validation_resource_probe_runtime()
    free_memory = Int64(free_memory_provider())
    free_memory >= 0 || throw(ArgumentError(
        "free_memory_provider returned a negative value",
    ))
    base = _mgmfrm_validation_short_nuts_base_result(
        checked_plan,
        policy,
        runtime,
        free_memory,
        Int64(checked_minimum_memory),
        checked_maximum_observations,
    )

    if !execute_measurement || !base.preflight.memory_preflight_passed
        memory_blocker = base.preflight.memory_preflight_passed ? () :
            (:insufficient_free_memory,)
        execution_blocker = execute_measurement ? () :
            (:explicit_execution_not_requested,)
        return merge(base, (;
            status = !execute_measurement ?
                :short_nuts_resource_probe_planned_not_executed :
                :short_nuts_resource_probe_memory_preflight_rejected,
            execute_measurement,
            operational_execution_eligible =
                base.preflight.memory_preflight_passed,
            execution_started = false,
            mcmc_execution_state = :not_started,
            mcmc_executed = false,
            fit_attempt_rows = (),
            summary = (;
                n_planned_cells = length(checked_plan),
                n_started = 0,
                n_terminal = 0,
                n_completed = 0,
                denominator_preserved = true,
            ),
            measurement = missing,
            blockers = (execution_blocker..., memory_blocker...),
            convergence_assessed = false,
            scientific_execution_authorized = false,
            recovery_evidence_available = false,
            fit_objects_returned = false,
            final_resource_policy_frozen = false,
            claim_scope = :operational_preflight_not_validation_evidence,
            next_gate = base.preflight.memory_preflight_passed ?
                :explicitly_execute_bounded_short_nuts_probe :
                :rerun_in_environment_with_sufficient_free_memory,
        ))
    end

    free_memory_before = free_memory
    process_maxrss_before = Int64(maxrss_provider())
    timed_run = try
        @timed begin
            run = runner_executor(checked_plan, Float64(truth_scale))
            hasproperty(run, :rows) && hasproperty(run, :summary) &&
                hasproperty(run, :controls) || throw(ArgumentError(
                "short-NUTS runner returned an invalid result",
            ))
            run
        end
    catch err
        _mgmfrm_stress_fatal_exception(err) && rethrow()
        err
    end
    free_memory_after = Int64(free_memory_provider())
    process_maxrss_after = Int64(maxrss_provider())
    if timed_run isa Exception
        return merge(base, (;
            status = :short_nuts_resource_probe_runner_failed,
            execute_measurement = true,
            operational_execution_eligible = true,
            execution_started = true,
            mcmc_execution_state = :unknown_after_runner_failure,
            mcmc_executed = missing,
            fit_attempt_rows = (),
            summary = (;
                n_planned_cells = length(checked_plan),
                n_started = 1,
                n_terminal = 0,
                n_completed = 0,
                denominator_preserved = false,
            ),
            measurement = (;
                elapsed_seconds = missing,
                allocated_bytes = missing,
                free_memory_bytes_before = free_memory_before,
                free_memory_bytes_after = free_memory_after,
                minimum_endpoint_free_memory_bytes =
                    min(free_memory_before, free_memory_after),
                process_lifetime_maxrss_bytes_before =
                    process_maxrss_before,
                process_lifetime_maxrss_bytes_after =
                    process_maxrss_after,
                peak_memory_measured = false,
                maxrss_is_probe_attributable = false,
            ),
            blockers = (:short_nuts_runner_failed,),
            error_type = string(typeof(timed_run)),
            error_message = sprint(showerror, timed_run),
            error = timed_run,
            convergence_assessed = false,
            scientific_execution_authorized = false,
            recovery_evidence_available = false,
            fit_objects_returned = false,
            final_resource_policy_frozen = false,
            claim_scope = :failed_operational_probe_not_validation_evidence,
            next_gate = :inspect_preserved_runner_failure,
        ))
    end

    run = timed_run.value
    execution_state =
        _mgmfrm_validation_short_nuts_execution_state(run.rows)
    return merge(base, (;
        status = run.summary.n_completed == length(checked_plan) ?
            :short_nuts_resource_probe_complete_operational_metadata_only :
            :short_nuts_resource_probe_complete_with_recorded_failures,
        execute_measurement = true,
        operational_execution_eligible = true,
        execution_started = true,
        mcmc_execution_state = execution_state,
        mcmc_executed = execution_state === :executed,
        fit_attempt_rows = run.rows,
        summary = (;
            n_planned_cells = length(checked_plan),
            n_started = run.summary.n_attempts,
            n_terminal = run.summary.n_terminal_attempts,
            n_completed = run.summary.n_completed,
            denominator_preserved =
                run.summary.n_terminal_attempts == length(checked_plan),
        ),
        measurement = (;
            elapsed_seconds = Float64(timed_run.time),
            allocated_bytes = Int(timed_run.bytes),
            gc_seconds = Float64(timed_run.gctime),
            free_memory_bytes_before = free_memory_before,
            free_memory_bytes_after = free_memory_after,
            minimum_endpoint_free_memory_bytes =
                min(free_memory_before, free_memory_after),
            process_lifetime_maxrss_bytes_before = process_maxrss_before,
            process_lifetime_maxrss_bytes_after = process_maxrss_after,
            process_lifetime_maxrss_increased =
                process_maxrss_after > process_maxrss_before,
            peak_memory_measured = false,
            maxrss_is_probe_attributable = false,
        ),
        blockers = (:scaled_resource_cells_and_peak_memory_review_pending,),
        error_type = missing,
        error_message = missing,
        error = missing,
        convergence_assessed = false,
        scientific_execution_authorized = false,
        recovery_evidence_available = false,
        fit_objects_returned = false,
        final_resource_policy_frozen = false,
        claim_scope = :short_chain_operational_metadata_not_validation_evidence,
        next_gate = :review_scaled_resource_cells_and_peak_memory,
    ))
end

"""
    mgmfrm_validation_short_nuts_resource_probe(
        plan = nothing; execute_measurement = false,
        minimum_free_memory_bytes = 2 * 1024^3,
        maximum_observations_per_cell = 1_000, truth_scale = 0.15)

Plan or explicitly execute one memory-guarded, short AdvancedHMC/NUTS resource
probe for fixed-Q MGMFRM. The default cell is connected-sparse with one chain,
25 warmup transitions, and 25 retained draws. The memory and workload gates
run before data generation or MCMC; the minimum memory requirement cannot be
lowered below 1 GiB.

This probe assesses only local short-chain operability. It does not assess
convergence, recovery, coverage, backend performance, prior choice, Q choice,
or scientific thresholds. Returned fit-attempt rows preserve typed failures,
but fit objects are discarded. Cumulative Julia allocations and endpoint free
memory are recorded; peak memory is not claimed.
"""
function mgmfrm_validation_short_nuts_resource_probe(
        plan = nothing;
        execute_measurement::Bool = false,
        minimum_free_memory_bytes::Integer = 2 * 1024^3,
        maximum_observations_per_cell::Integer = 1_000,
        truth_scale::Real = 0.15)
    selected_plan = if isnothing(plan)
        _mgmfrm_validation_default_short_nuts_resource_probe_plan()
    elseif plan isa NamedTuple && hasproperty(plan, :object) &&
            plan.object === :mgmfrm_response_stress_plan_row
        (plan,)
    else
        plan
    end
    return _mgmfrm_validation_short_nuts_resource_probe(
        selected_plan;
        execute_measurement,
        minimum_free_memory_bytes,
        maximum_observations_per_cell,
        truth_scale,
    )
end
