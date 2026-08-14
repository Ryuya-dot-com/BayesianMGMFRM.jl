# Portable, MCMC-free resource profiling for the fixed-Q MGMFRM candidate.

const _MGMFRM_VALIDATION_RESOURCE_PROBE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_validation_resource_probe.v1"

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
